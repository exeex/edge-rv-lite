# edge-rv-lite: Is Single Issue Enough for an ASIC Control Plane?

## Abstract

`edge-rv-lite` is a single-issue, three-stage RV64 control core built to test a
specific product question: **when most computation runs in dedicated ASIC
units, does the scalar control plane still need a dual-issue processor?**

The normal `edge-rv` core uses dual issue, scalar snapshots, command queues,
scoreboards, an RTU, and completion machinery to prepare accelerator commands
while older work remains in flight. `edge-rv-lite` removes that scalar-side
machinery, but it does **not** wait for an ASIC operation to finish. RV64 and
Edge64 instructions are separated before execution. Edge64 commands enter the
dedicated `edge_accel_pipe`; once the selected ASIC accepts a command, the
three-stage scalar pipeline continues. The resulting core has no RTU, sequence
IDs, epochs, snapshot RAM, replay queue, or multi-port scalar writeback.

This is not a proposal to reduce the ASIC subsystem. The experiment keeps the
same edge-e3 Tensor, DTCM, DMA, ACTU/CMPU, cache, AXI, instruction classifier,
and shared scalar execution RTL. Only the scalar scheduling owner changes.
That controlled substitution makes it possible to measure where dual issue
matters and where a single-issue scalar control plane is sufficient.

The current results expose the trade directly:

- the reusable RV layer uses 75.4% fewer Yosys cells than `edge-rv`;
- the complete edge-e3 product uses 34.7% fewer Yosys cells;
- CoreMark takes 1.919x as many cycles per iteration;
- long-running Tensor windows change by only 0.1% to 0.9%.

The conclusion is workload-dependent. Dual issue remains valuable when the
RISC-V core dynamically constructs a fine-grained accelerator schedule. Single
issue is enough when software mainly configures and launches coarse-grained
ASIC operations whose execution time dominates scalar command preparation.

## 1. Research question

An accelerator product can spend substantial control logic on a scalar core
even when nearly all arithmetic happens elsewhere. In edge-e3, `edge-rv`
provides a capable dual-issue control plane. It can compute operands, snapshot
them, queue ASIC commands, and continue preparing younger work while an older
command executes.

That machinery is useful, but it is not free. It consumes area in the scalar
pipeline and in the structures needed to identify, order, complete, cancel,
and retire concurrent work. Whether the cost is justified depends on the
granularity of the attached ASIC instructions.

This work asks three related questions:

1. Can a single-issue three-stage core retain the Edge software and product
   boundary without implementing a second ISA or a reduced ASIC subsystem?
2. How much scalar and product-level logic is removed when dual-issue command
   preparation is replaced by single-issue, direct accelerator dispatch?
3. Does reduced scalar issue bandwidth materially reduce the throughput of
   realistic Tensor operations when accepted ASIC work runs independently?

The experiment is intentionally asymmetric. CoreMark represents scalar-heavy
work and should expose the performance cost of single issue. Long Tensor runs
represent coarse-grained acceleration and test whether that cost remains
visible after the ASIC has been launched.

## 2. Hypothesis

The hypothesis is not that single issue is universally better. It is that
**single issue is sufficient for an ASIC control plane when accelerator
commands are coarse-grained and the schedule is mostly static**.

The expected outcomes are:

- scalar workloads become slower because the RV64 pipeline is single issue and
  serializes its own variable-latency operations;
- ASIC behavior remains unchanged because Tensor, DMA, DTCM, ACTU, and CMPU
  are shared rather than reimplemented;
- accepted ASIC commands execute in their own pipes while RV64 continues;
- Tensor descriptor and weight double buffering allow software to prepare the
  next launch without corrupting the active one;
- product area falls because both the dual-issue pipe and its concurrency
  bookkeeping disappear.

Conversely, `edge-rv-lite` is the wrong choice when RISC-V acts as a dynamic
command generator. Sparse addresses, changing shapes, fine-grained
dependencies, and a stream of short ASIC commands can all make scalar
preparation part of the critical path.

## 3. Evaluation scope

`edge-rv-lite` lives in this directory, but the complete experiment does not.
The work uses three verification and evaluation boundaries.

| Level | Boundary | What it proves | Required source |
| --- | --- | --- | --- |
| Module | Lite pipeline and local wrappers | Decode, issue/completion, faults, FPU, LSU, cache and DTCM contracts | `edge-rv-lite` plus shared `edge-rv` RTL |
| Scalar integration | Bootable RV subsystem | Same-source CoreMark, cache/AXI integration, RV-layer synthesis | complete `edge-cores` parent project |
| Product integration | Complete edge-e3 composition | Tensor/DMA/DTCM execution and full-product area | `edge-cores` plus the edge-e3 ASIC RTL |

CoreMark depends on the parent project's toolchain, generated memory image,
CMake/CTest harness, and normal `edge-rv` baseline. The Tensor experiments
additionally depend on the complete edge-e3 ASIC subsystem, including Tensor
execution, DTCM, DMA, cache-coherence paths, and the composed product tops.

The Tensor result is therefore a controlled system substitution:

```text
same software                  same software
same edge-e3 ASICs             same edge-e3 ASICs
same Tensor/DMA/DTCM           same Tensor/DMA/DTCM
same cache and AXI hierarchy   same cache and AXI hierarchy
          |                              |
   dual-issue edge-rv       single-issue edge-rv-lite
```

The claim is not that `edge-rv-lite` contains its own Tensor engine. The claim
is that replacing only the scalar scheduling owner in an otherwise unchanged
edge-e3 product has little effect on coarse-grained Tensor execution.

## 4. Baseline: dual-issue edge-rv

`edge-rv` is the baseline scalar owner. Its reusable layer includes the scalar
and optional FPU pipeline, frontend, snapshot and dispatch machinery, RTU, and
I/D caches. It is designed to preserve overlap between scalar preparation and
accelerator execution.

The important capability is dynamic command generation. A compact RISC-V loop
can calculate the next command's addresses, shapes, and operands, snapshot
those values, and place the ASIC instruction into a queue while earlier work
is still executing. In this role, the scalar pipeline acts like a small JIT
compiler for the accelerator schedule.

This avoids statically expanding a dynamic loop into thousands of ASIC
instructions. Static expansion would consume I-cache capacity and cause
instruction fetch to compete with data traffic. A well-written attention
kernel can keep an approximately 8 KiB hot path in I-cache; the relevant
question is not code size alone, but whether that compact loop must continually
construct new commands.

The baseline pays for mechanisms that `edge-rv-lite` intentionally omits:

- dual scalar issue;
- architectural dependency scoreboards;
- RTU ownership and retirement records;
- snapshot capture of accelerator operands;
- accelerator command queueing;
- sequence and epoch identity;
- completion arbitration and multi-source writeback;
- multiple queued command preparation independent of downstream readiness.

## 5. The edge-rv-lite design

### 5.1 Single-issue three-stage pipeline

`edge-rv-lite` has three architectural stages:

1. **F** accepts one 32-bit scalar parcel or the parcels of one 64-bit Edge
   instruction.
2. **D** classifies the complete instruction and reads its operands.
3. **X/W** starts the selected operation, owns it until completion, and writes
   architectural state.

Independent fast instructions may occupy all three stages. Only X/W may start
an operation, however, and an unfinished scalar X/W operation freezes F and D.
Loads, stores, MUL/DIV, and FPU operations therefore remain the single scalar
execution owner until completion. An ASIC command is different: X/W holds it
only until `edge_accel_pipe` and the selected unit accept it. The ASIC then
continues independently and the RV64 pipeline advances.

Branches, JAL, and JALR resolve in X/W. A taken control transfer clears F and D
and restarts fetch at the target. There is no predictor or epoch machinery;
the fixed taken penalty is part of the intended area tradeoff.

The only GPR bypass forwards a completing X/W result to operands advancing
from D on the same edge. There is no need to reserve destinations in a
scoreboard because a younger instruction cannot pass an unfinished producer.

### 5.2 RV64 and ASIC instruction separation

The instruction stream contains ordinary 32-bit RV64 instructions and 64-bit
Edge ASIC instructions. In the dual-issue core, the maintained module is still
named `edge_predecoder`. It tokenizes and classifies the mixed stream, sends
scalar work toward `edge_scalar_pipe`, and sends accelerator work through the
snapshot/command-queue path to `edge_accel_pipe`.

Lite implements the same architectural split with less policy. Ordered 32-bit
fetch parcels first pass through `edge_rv_lite_instruction_assembler`; the
shared `edge_instruction_classifier` then identifies scalar versus ASIC
operation classes. Scalar instructions enter the three-stage RV64 pipe. Edge64
instructions use the lite accelerator owner and the same maintained
`edge_accel_pipe` used by the full product.

This separation is why a running ASIC does not block the three-stage scalar
pipeline. The lite owner holds an Edge64 instruction and its capture operand
stable only while the destination applies backpressure. When the destination
accepts the command, the owner returns one registered scalar response on the
following cycle. Setup and start commands return zero; get-CSR returns the
selected ASIC result; illegal decode returns an error.

For a start instruction, this response means **the ASIC has accepted and owns
the command**, not that computation has finished. Software uses the matching
`sync` instruction when it requires execution completion. Thus lite removes
the scalar accelerator queue without making RV64 wait for the entire ASIC
latency.

Only one Edge64 command handshakes through the lite dispatch boundary at a
time, but multiple previously accepted ASIC operations may coexist in
unit-owned pipelines and buffers. Tensor compute, WLD/SLD, DMA, ACTU, and CMPU
each retain their own readiness and lifetime. The scalar core stalls only when
the destination cannot accept the next command, not merely because an earlier
ASIC operation is still running.

The LSU remains serialized inside the scalar pipeline: its request register
and controller move through `IDLE -> REQUEST -> RESPONSE` while F and D wait.

| Mechanism | `edge-rv` | `edge-rv-lite` |
| --- | --- | --- |
| Issue policy | Dual issue | Single issue |
| Pipeline role | Prepare and queue work | Single-issue RV64 plus direct ASIC dispatch |
| Accelerator operands | Snapshot and queue | Read on accepted request |
| Scalar-side ASIC queue | Sequence/epoch-identified commands | None |
| ASIC execution | Dedicated `edge_accel_pipe` and units | Same dedicated pipe and units |
| RV64 after accepted ASIC start | Continues | Continues |
| Dependencies | Scoreboards and scheduling policy | In-order pipeline blocking |
| Scalar dispatch identity | RTU, sequence, and epoch | Current request until acceptance |
| Redirect recovery | Concurrent-state cleanup | Flush F and D |
| Writeback | Multi-source arbitration | One completing owner |
| Scalar/ASIC execution overlap | Supported | Supported after command acceptance |

### 5.3 Instruction assembly and decode

The frontend supplies ordered 32-bit parcels. An opcode `7'h3f` length marker
causes `edge_rv_lite_instruction_assembler` to capture the following parcel
and emit one complete 64-bit Edge instruction at the first parcel's PC. A
redirect discards an incomplete pair.

`edge_rv_lite_decode.v` wraps the shared `edge_instruction_classifier`; it
does not maintain a second legality table. D classifies once and carries the
class, legality, and GPR-write metadata into X/W.

The classifier covers RV64I, RV64M, Zba, Edge FP32 and low-precision
load/store, CSR/system/fence operations, Edge cache/DMA control, and the
64-bit vector/Tensor/DMA/ACTU/CMPU/get-CSR envelope. Lite adds only product
capability checks for units present in its configuration.

The ALU, branch, MUL/DIV, and FPU RTL is also not forked. The lite filelist
references the maintained implementations under `../edge-rv`. Lite owns the
predecode/control path, one-owner LSU/BIU path, and backpressured direct ASIC
dispatch.

### 5.4 Fault, halt, and hardware ID

A single X/W commit gate prevents a faulting instruction from issuing ALU
redirects, MUL/DIV, LSU, FPU, cache, or accelerator side effects. LSU or
accelerator response errors suppress GPR writeback. Faulting instructions halt
as illegal without incrementing `instret`.

A terminal instruction becomes visible on its completion edge. That edge
flushes younger F/D state and partial Edge64 assembly. Sticky `halted` then
gates fetch, issue, writeback, and retirement until reset.

Software-test termination is a harness contract, not a memory-map feature.
Bare-metal `crt0` writes report symbols as normal RAM and executes
`csrw 0x7e0, a0`; the harness observes `halted` and reads `debug_x31`. Stores
to the former `0x2ee8` test-image location remain ordinary memory transactions.

The read-only custom CSR `0xfc0` reports RV core ID 2, VPU version 0, and FPU
version 0 or 1 according to `ENABLE_FPU`. The selected product supplies the
remaining 47 bits through the `EDGE_ASIC_ID` elaboration parameter. Shared
intrinsics decode the complete product, Tensor-dimension, and format identity,
so software does not need a lite-specific ABI.

## 6. Preserving the ASIC product

The central implementation rule is that lite changes **scalar scheduling
policy, not accelerator behavior**.

Below the scalar issue boundary, both products instantiate `edge_accel_pipe`
as the common command decoder and dispatch boundary. Both products then use
`edge_accel_data_ctrl`, which owns direct DMA, XY-strided DMA, circular DMA,
Tensor circular WLD/SLD/WSLD scheduling, and the Tensor/DTCM command mux. The
normal core adds a dual-issue queue and snapshot policy before the accelerator
pipe; lite drives it from a backpressured single command owner. Once accepted,
commands live in ASIC-owned state rather than in the three-stage scalar
pipeline. There is no rewritten lite DMA engine or reduced Tensor
implementation.

### 6.1 Tensor descriptor and execution double buffering

Tensor commands are designed so that accepted ASIC work and younger RV64 setup
can overlap safely. `tensor.setcsr`, `tensor.setin`, `tensor.setout`,
`tensor.setpsum`, `tensor.setn`, and WLD-related setup build a pending
descriptor for the next start.

When `tensor.start` is accepted, the complete descriptor used by that job is
snapshotted into ASIC-owned active state. In software terms, the CSR set for
the launched instruction is frozen: later set commands cannot modify the
running job's datatype, pointers, run count, weight selection, or mode.
Software may immediately program the pending descriptor as a second CSR set
for the next job while the active job is executing.

The Tensor unit also contains a one-entry queued-start descriptor. If the
current job is active, a loaded weight tile is available, and the queued slot
is empty, a second `tensor.start` can be accepted. That start snapshots the
new pending descriptor and selected weight buffer. It launches immediately
when the active stream drains.

Weight state follows the same ownership principle. Two physical weight
buffers provide active/pending ping-pong storage. A queued start owns its
selected buffer, so a younger WLD cannot overwrite weights already bound to an
active or queued job. Scale state is independently double buffered as well.

This unit-local buffering is different from the full core's scalar snapshot
and command queue. The ASIC buffers protect commands that have already been
accepted; they allow the single-issue RV64 core to keep programming and
launching work without retaining completed Edge64 instructions in its
three-stage pipeline. Backpressure occurs only when the target command slot,
queued start, or required weight/scale buffer is unavailable, or when software
explicitly executes a synchronization command.

### 6.2 Software-visible pipeline

The open-source C++ kernels show how this contract is used in real software:

- [`cpp/libnn/activation.hpp`](https://github.com/exeex/edge-cores/blob/main/cpp/libnn/activation.hpp)
  issues ACTU setup and `start`, then uses an explicit `sync` because the chunk
  result is needed before the following DMA or loop iteration;
- [`cpp/libnn/matmul.hpp`](https://github.com/exeex/edge-cores/blob/main/cpp/libnn/matmul.hpp)
  pipelines Tensor tiles. Its inner loops issue `setin`, `setout`, optional
  `setpsum`, `tensor.start`, and the next circular WLD without placing
  `tensor.sync` inside the loop. One sync appears only after all tile commands
  have been issued.

The matmul loop makes the non-blocking behavior concrete. After an accepted
`tensor.start`, the active Tensor job runs independently. The RV64 pipeline
continues through the remaining loop body, increments the induction variables,
executes the loop branch and redirect, and begins programming the next pending
descriptor. These writes cannot alter the active descriptor frozen by the
previous start.

```text
RV64:   set CSR A -- start A -- loop branch/redirect -- set CSR B -- start B
                           |                              |
Tensor:                    +-- execute A ----------------+-- queue/launch B
```

The next `tensor.start`, rather than the for-loop itself, is the natural
backpressure point. It proceeds immediately when the queued-start descriptor
and required ping-pong weight buffer are available; otherwise it waits until
the Tensor unit can take ownership. This lets ordinary single-issue RV64 work
run ahead during Tensor execution without requiring a scalar-side accelerator
command queue.

The source-level integration boundary is selected by filelist:

- preserve the Edge SoC-facing IFU, BIU/D-cache/DTCM, and ASIC command signals;
- preserve the shared `edge-rv` ALU/FPU implementations and interfaces;
- replace the dual-issue scalar pipe, RTU, snapshots, and command queues with
  the lite top and its single-owner controller;
- tie compatibility lane 1 permanently invalid;
- compose the result with the same edge-e3 ASIC platform.

`filelists/edge_rv_lite.fl` is the canonical lite source selection. The parent
project supplies `${EDGE_RV_ROOT}` and `${EDGE_RV_LITE_ROOT}`. A complete lite
product must instantiate `edge_core_lite_top`; swapping only leaf RTL beneath
the normal `edge_core_top` would retain the baseline RTU and queue area.

## 7. Memory and product integration

```text
edge_rv_lite_core
        |
        +-- instruction adapter -- I-cache --------+
        |                                          |
        +-- LSU -- DTCM router -- D-cache ----------+-- cache BIU -- AXI
                    |
                    +-- scalar DTCM port

edge_core_lite_top
        +-- hierarchy above
        +-- shared DTCM and DMA
        +-- shared Tensor, ACTU, and CMPU units
        +-- shared accelerator data controller
```

`edge_rv_lite_cached_core` composes the bootable core with the maintained
I-cache and D-cache. Its adapters convert one-owner fetch and LSU handshakes to
the existing cache contracts. Lane 1, redirect-kill metadata, and backend
pause inputs are tied inactive because lite cannot have a younger outstanding
scalar memory operation.

An optional stateful DTCM router bypasses D-cache for a configured base/mask
window. It acknowledges accepted stores and retains the chosen cache or DTCM
read owner until response. Raw DTCM bank data is normalized to the same
size/sign-formatted response used by D-cache, allowing scalar code to verify
BF16 and byte results produced by ASIC tests.

`edge_rv_lite_cache_biu` and `edge_rv_lite_axi_core` connect this hierarchy to
the existing 128-bit Edge AXI boundary. The BIU checks response IDs, status,
burst beat counts, and `RLAST`. Failed instruction fills do not populate
I-cache. Failed dirty writebacks remain buffered for retry, and AW/W may
handshake independently.

Byte accesses are unrestricted; halfword, word, and doubleword accesses must
be naturally aligned. Misaligned accesses fault before any cache, uncached, or
DTCM request. `FENCE.I` drains accepted instruction refills, sweeps I-cache
valid bits, flushes younger fetch/decode state, and resumes at the following
instruction. Software must first complete the D-cache clean/writeback or DMA
operation that makes modified code visible.

## 8. Optional FPU and precision normalization

`ENABLE_FPU` defaults to `0`. Enabling it instantiates the shared single-issue
`edge_fpu_alu`, FPR file, FP operations, and FPU version 1 in CSR `0xfc0`.

The FPU is primarily a bring-up, fallback, data-generation, and validation
facility. FP8, FP16, BF16, and FP32 are memory formats: loads promote them to a
physical FP32 FPR, arithmetic uses the FP32 ALU, and stores narrow from FP32.
This lets bare-metal C++ tolerate accidental `double` constants without
soft-float helpers, but it does not provide FP64 accuracy.

The enabled profile implements `fflags`, `frm`, and `fcsr`. FPU completions
sticky-OR `NV,DZ,OF,UF,NX`; CSR writes can clear or replace them. RNE, RTZ,
RDN, RUP, and RMM are supported. Dynamic rounding uses `frm` and traps for a
reserved value. With the FPU disabled, these CSRs and all FP operations are
illegal.

| Memory format | Load/store `funct3` | Bytes |
| --- | --- | ---: |
| FP16 | `001` | 2 |
| FP32 | `010` | 4 |
| BF16 | `101` | 2 |
| FP8 E5M2 | `110` | 1 |
| FP8 E4M3FN | `111` | 1 |

Stores use RNE; FP8 overflow saturates to the largest finite value. Arithmetic
suffixes do not select different datapaths: `.s`, `.h`, and `.d` aliases all
operate on physical FP32 values.

### 8.1 Scalar FP4 conversion and packed `fp4x16_t`

Edge FP4 uses the NVFP4 finite E2M1 element. One nibble is laid out as
`S EE M`, with exponent bias 1. Its representable values are signed zero and
signed magnitudes 0.5, 1, 1.5, 2, 3, 4, and 6. There is no FP4 Inf or NaN
encoding.

FP4 is not an LSU format and does not occupy an FPR in packed form. A packed
`fp4x16_t` is exactly one 64-bit GPR payload containing sixteen independent
nibbles. Two scalar move/convert instructions cross the boundary between one
packed nibble and the physical FP32 FPR representation:

| Instruction | `funct7` | `rs2` | `funct3` | `opcode` | Data movement |
| --- | :---: | :---: | :---: | :---: | --- |
| `fmv.s.xfp4 fd, rs1` | `1111011` | `00000` | `000` | `1010011` | Expand GPR `rs1[3:0]` exactly to FP32 FPR `fd`; ignore `rs1[63:4]` |
| `fmv.xfp4.s rd, fs1` | `1110011` | `00000` | `000` | `1010011` | Quantize FP32 FPR `fs1` with RNE and return `{60'b0, fp4}` in GPR `rd` |

`fmv.s.xfp4` is an exact decode of all sixteen E2M1 bit patterns. The sign bit
is preserved, including negative zero. Because every FP4 encoding is finite,
this direction needs no NaN or infinity policy.

`fmv.xfp4.s` performs the lossy direction. It rounds to nearest with ties to
even, saturates finite overflow and positive/negative infinity to `+6` or
`-6`, preserves signed zero, and maps any FP32 NaN to positive zero. The upper
60 bits of the integer result are always zero. Neither instruction accesses
memory or applies a block scale; packed Tensor scaling remains WLD/SLD policy.

The public
[`edge_intrinsic.hpp`](https://github.com/exeex/edge-cores/blob/main/cpp/intrinsic/edge_intrinsic.hpp)
exposes the instructions as `edge_fp4_to_fp32()` and `edge_fp32_to_fp4()` and
builds indexed packed-element access on ordinary RV64 shifts and masks:

```cpp
// idx 0 addresses the least-significant nibble; valid indices are 0..15.
static inline float get_element_fp4(fp4x16_t x, int idx)
{
    return edge_fp4_to_fp32(
        static_cast<uint8_t>((x.data >> (idx * 4)) & 0x0fu));
}

static inline void set_element_fp4(fp4x16_t &x, float y, int idx)
{
    const unsigned shift = static_cast<unsigned>(idx) * 4u;
    const uint64_t mask = UINT64_C(0xf) << shift;
    const uint64_t nibble = static_cast<uint64_t>(edge_fp32_to_fp4(y));
    x.data = (x.data & ~mask) | ((nibble & UINT64_C(0xf)) << shift);
}
```

The packed layout is therefore:

```text
bits  3:0   = element 0
bits  7:4   = element 1
...
bits 63:60  = element 15
```

`get_element_fp4()` extracts the selected nibble into the low four GPR bits
and executes `fmv.s.xfp4`. `set_element_fp4()` executes `fmv.xfp4.s`, clears
only the selected nibble, and inserts the new four-bit value without modifying
the other fifteen elements. Callers must provide an index in the documented
0 through 15 range.

The intrinsic header also provides sequential `pack_next_fp4()` and
`unpack_next_fp4()` helpers. Calling `pack_next_fp4()` exactly sixteen times
from a zero-initialized value produces CUDA-linear element order; the indexed
helpers are preferable when software must update a specific element in place.

Standalone Yosys `synth_xilinx -family xc7` estimate for `edge_fpu_alu`:

| Resource | Additional FPU cost |
| --- | ---: |
| Total cells | 15,604 |
| LUT1-6 | 9,260 |
| Flip-flops | 2,080 |
| CARRY4 | 458 |
| DSP48E1 | 2 |
| MUXF7 | 1,165 |
| MUXF8 | 274 |

## 9. Experimental methodology

Performance numbers are LLVM 22.1.8 Verilator checkpoints using identical
software source on `edge-e3@rv` and `edge-e3@rv-lite`. Internal `rdcycle` is
the primary metric; whole-harness cycles include boot and setup.

Retired counts identify generated images, not toolchain-independent behavior.
The LLVM 22.1.8 CoreMark image retires 616,228 instructions. A local LLVM
19.1.1 image retires 743,510 instructions and supplies the cached/AXI
regression baseline. These counts must not be mixed.

Area uses Yosys `synth_xilinx -family xc7 -noiopad -noclkbuf`. These are
FPGA-oriented estimates, not placed-and-routed FPGA or ASIC physical area.
Two boundaries are reported:

1. **RV layer:** `edge_rv_top` versus `edge_rv_lite_cached_core`, excluding
   Tensor, DTCM, DMA, ACTU, and CMPU product logic.
2. **Complete product:** `edge_core_top` versus `edge_core_lite_top`, retaining
   the same ASICs, caches, and SRAM-to-BRAM wrappers.

## 10. Results

### 10.1 Scalar performance

| Case | Metric | `edge-e3@rv` | `edge-e3@rv-lite` | Lite / RV |
| --- | --- | ---: | ---: | ---: |
| CoreMark, 2 iterations | cycles/iteration | 409,503 | 785,777 | 1.919x |
| CoreMark | retired instructions | 616,228 | 616,228 | 1.000x |

The identical retired count proves both products execute the same image. The
1.919x cycle ratio exposes the intended cost: single issue nearly halves
effective throughput on a scalar-dominated workload.

An earlier bootable checkpoint reported a 724,712-cycle whole-program interval
before `crt0` break. It is not used in the table because it is not the same
cycles-per-iteration metric.

### 10.2 Tensor execution

| Case | Metric | `edge-e3@rv` | `edge-e3@rv-lite` | Lite / RV |
| --- | --- | ---: | ---: | ---: |
| `tile8x8_stream64tokens` | X30 Tensor window | 534 | 539 | 1.009x |
| `tile8x8_stream64tokens` | ideal / X30 utilization | 95.88% | 94.99% | -0.89 pp |
| `matmul64x64_runtime_shape`, 64 tokens | X30 Tensor window | 4,660 | 4,699 | 1.008x |
| `matmul64x64_runtime_shape`, 64 tokens | MAC utilization | 87.90% | 87.17% | -0.73 pp |
| `matmul64x64_runtime_shape`, 128 tokens | X30 Tensor window | 8,772 | 8,785 | 1.001x |
| `matmul64x64_runtime_shape`, 128 tokens | MAC utilization | 93.39% | 93.25% | -0.14 pp |

The stream case performs 512 consecutive 8x8 vector steps with one WLD and one
Tensor start. All 4096 BF16 outputs are checked after DTCM-to-AXI DMA. Lite
adds five cycles because launch overhead is small relative to the Tensor run.

The runtime-shape cases share one C++ implementation and check every element
of the 4096- or 8192-element output. Software reads hardware ID, packs public
input with strided DMA, streams BF16 weights through packed-XY DMA and
transposed circular WLD, and scatters private blocked output back to public
layout. The X30 window isolates weight production and Tensor execution; input
packing and output scatter remain outside it.

The measured window uses the same software-pipelined structure visible in the
open-source matmul kernel: `tensor.start` does not stop the C++ tile loop. RV64
runs ahead through its branch/redirect and next descriptor writes, and stalls
only if the following start reaches a full Tensor queue/buffer boundary. This
is the mechanism that allows a single-issue scalar core to keep the Tensor
engine fed.

Lite adds 39 cycles at 64 tokens and 13 cycles at 128 tokens. As the ASIC
window grows, lower scalar issue bandwidth becomes a smaller fraction of
execution. The unchanged `bf16_wld_direct_circular.cpp` regression additionally
covers cache clean-by-VA, direct and circular DMA, direct and transposed WLD,
scalar DTCM checks, DMA sync, and the Edge break CSR.

### 10.3 RV-layer synthesis

| Resource | `edge-rv` | `edge-rv-lite` | Lite delta | Lite / RV |
| --- | ---: | ---: | ---: | ---: |
| Total cells | 127,943 | 31,473 | -96,470 | 24.6% |
| LUT1-6 | 76,602 | 14,877 | -61,725 | 19.4% |
| Flip-flops | 17,937 | 6,560 | -11,377 | 36.6% |
| CARRY4 | 1,913 | 653 | -1,260 | 34.1% |
| DSP48E1 | 6 | 4 | -2 | 66.7% |
| MUXF7 | 10,110 | 2,158 | -7,952 | 21.3% |
| MUXF8 | 2,843 | 452 | -2,391 | 15.9% |
| BRAM36 / BRAM18 | 6 / 32 | 6 / 32 | 0 / 0 | 100% / 100% |

Lite removes 75.4% of total cells, 80.6% of LUTs, and 63.4% of flip-flops from
the reusable RV layer. Cache BRAM is unchanged.

### 10.4 Complete-product synthesis

| Resource | `edge-e3@rv` | `edge-e3@rv-lite` | Lite delta | Lite / RV |
| --- | ---: | ---: | ---: | ---: |
| Total cells | 283,882 | 185,360 | -98,522 | 65.3% |
| LUT1-6 | 169,752 | 106,185 | -63,567 | 62.6% |
| Flip-flops | 43,301 | 31,467 | -11,834 | 72.7% |
| CARRY4 | 8,425 | 7,060 | -1,365 | 83.8% |
| DSP48E1 | 101 | 99 | -2 | 98.0% |
| MUXF7 | 16,798 | 9,424 | -7,374 | 56.1% |
| MUXF8 | 5,113 | 2,847 | -2,266 | 55.7% |
| BRAM36 / BRAM18 | 38 / 32 | 38 / 32 | 0 / 0 | 100% / 100% |

Replacing only the scalar owner reduces the complete product by 98,522 Yosys
cells, or 34.7%. LUT usage falls 37.4% and flip-flops 27.3%, while the shared
ASIC datapaths and BRAM capacity remain unchanged.

## 11. Interpretation: when is single issue enough?

The results support the hypothesis only for the intended workload class.

`edge-rv` is preferable when the scalar core must construct many short ASIC
commands, calculate sparse addresses, respond to dynamic shapes, or overlap
bookkeeping with accelerator latency. Its snapshots and queues let a compact
loop behave as a dynamic schedule generator.

`edge-rv-lite` is preferable when execution is mostly static, circular DMA
already buffers DRAM traffic, and each ASIC launch performs substantial work.
A 512x512 matrix multiplication is the clearest example: a few extra scalar
cycles are negligible once execution begins.

| Workload property | Preferred scalar owner |
| --- | --- |
| Dynamic addresses, shapes, or sparse routing | `edge-rv` |
| Many fine-grained ASIC commands | `edge-rv` |
| Multiple future commands must be snapshotted and queued | `edge-rv` |
| RV64 should continue after an accepted coarse-grained start | Either core |
| Static schedule with circular DMA | `edge-rv-lite` |
| Few coarse-grained ASIC launches | `edge-rv-lite` |
| Area-dominated boot/configure/synchronize core | `edge-rv-lite` |

The decision is not simply scalar performance versus area. It is whether the
scalar core participates in the accelerator's steady-state scheduler. If it
does, dual issue can be architecturally valuable. If it does not, single issue
is enough and the extra scheduling machinery becomes product overhead.

## 12. Reproducing the experiments

These commands assume a configured checkout of the complete `edge-cores`
parent project. This directory explains and tests the lite RTL, but it is not a
standalone package for the CoreMark, Tensor, or full-product results.

### 12.1 Lite RTL and scalar integration

```sh
cmake -S src/edge-rv-lite -B build/edge-rv-lite
cmake --build build/edge-rv-lite --target edge_rv_lite_coremark_vvp
ctest --test-dir build/edge-rv-lite \
  -R '^edge_rv_lite_coremark$' --output-on-failure
```

The local CMake harness also registers focused tests for pipeline, redirects,
instruction assembly, decode, LSU, DTCM routing, faults, halt, hardware ID,
FPU/FCSR, cache adapters, cached-core integration, cache BIU, AXI CoreMark, and
serialized accelerator issue.

### 12.2 edge-e3 Tensor evaluation

These tests require the complete edge-e3 Tensor, DTCM, DMA, cache, AXI, and
product-top composition supplied by the parent project:

```sh
cmake --build build/edge-rv-lite --target edge_rv_lite_tensor_stream64_vvp -j2
cmake --build build/edge-rv-lite --target edge_rv_lite_tensor_circular_vvp -j2
cmake --build build/edge-rv-lite --target \
  edge_rv_lite_matmul64x64_64tokens_circular_vvp \
  edge_rv_lite_matmul64x64_128tokens_circular_vvp -j2

ctest --test-dir build/edge-rv-lite \
  -R '^edge_rv_lite_(tensor_(stream64|circular)|matmul64x64_(64|128)tokens_circular)$' \
  --output-on-failure
```

### 12.3 Synthesis comparison

Complete product:

```sh
EDGE_YOSYS_VARIANT=xilinx-top-compare-20260811 \
  ./synth/run_yosys.sh edge_core_top xilinx \
  synth/filelists/edge_existing.fl
EDGE_YOSYS_VARIANT=xilinx-top-compare-20260811 \
  ./synth/run_yosys.sh edge_core_lite_top xilinx \
  synth/filelists/edge_lite_top.fl
```

RV layer:

```sh
EDGE_YOSYS_VARIANT=xilinx-clean \
  ./synth/run_yosys.sh edge_rv_top xilinx \
  synth/filelists/edge_rv.fl
EDGE_YOSYS_VARIANT=xilinx-lite-cached \
  ./synth/run_yosys.sh edge_rv_lite_cached_core xilinx \
  src/edge-rv-lite/filelists/edge_rv_lite.fl
```

Use the same revision, Yosys version, target family, filelists, and elaboration
parameters before comparing cell counts.

## 13. Implementation contracts

This README presents the system argument. Cycle-level contracts remain beside
the implementation:

- `docs/edge_rv_lite_pipeline.v.md`: scalar serialization, redirects, faults,
  halt, and Edge64 acceptance ownership;
- `docs/edge_rv_lite_lsu.v.md`: scalar memory request and completion;
- `docs/edge_rv_lite_fp_mem_format.v.md`: FP memory normalization;
- `docs/edge_rv_lite_cache_adapters.v.md`: one-owner cache adaptation;
- `docs/edge_rv_lite_cached_core.v.md`: bootable cache composition and
  `FENCE.I`;
- `docs/edge_rv_lite_dtcm_router.v.md`: cache/DTCM ownership and formatting;
- `docs/edge_rv_lite_cache_biu.v.md`: refill, writeback, error, and retry;
- `docs/edge_rv_lite_axi_core.v.md`: maintained Edge AXI boundary.

Together, these contracts and tests establish that the performance and area
comparison comes from scalar issue policy—not from silently removing product
behavior.
