# edge-rv-lite

## Hardware identification CSR

`edge-rv-lite` implements the read-only custom CSR `0xfc0` locally and reports
RV core ID 2, VPU version 0, and FPU version 0/1 according to `ENABLE_FPU`.
The selected product supplies
the other 47 constant bits through the `EDGE_ASIC_ID` elaboration parameter;
the implementation adds no runtime identification port or CSR wiring.

The shared `edge_get_hardware_id()` and `edge_decode_hardware_id()` intrinsics
decode the complete core, product, Tensor-dimension and format description.

`edge-rv-lite` is the minimum-area control-plane alternative to `edge-rv`.
It preserves the same 32-bit scalar opcode families and the same 64-bit Edge
accelerator instruction envelope, but deliberately gives up overlap and
throughput.

## edge-rv versus edge-rv-lite only

This comparison removes the edge-e3 Tensor, DTCM, DMA, ACTU and CMPU product
logic. `edge_rv_top` represents the reusable edge-rv layer, including its
scalar/FPU pipeline, frontend, snapshot/dispatch machinery and I/D caches.
`edge_rv_lite_cached_core` represents the lite scalar core with the same I/D
caches.

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

Looking only at the reusable RV layer, lite uses **75.4% fewer total cells**,
**80.6% fewer LUTs**, and **63.4% fewer flip-flops**. The cache BRAM count is
unchanged.

## CoreMark and Tensor benchmark report

All numbers below are the LLVM 22.1.8 Verilator checkpoint using the same
software source on `edge-e3@rv` and `edge-e3@rv-lite`. Internal `rdcycle` is
the primary metric; whole-harness cycles include boot and setup work. Generated
images and instruction-count baselines are toolchain-specific.

| Case | Metric | edge-e3@rv | edge-e3@rv-lite | Lite / RV |
| --- | --- | ---: | ---: | ---: |
| CoreMark, 2 iterations | cycles/iteration | 409,503 | 785,777 | 1.919x |
| CoreMark | retired instructions | 616,228 | 616,228 | 1.000x |
| `tile8x8_stream64tokens` | X30 Tensor window | 534 | 539 | 1.009x |
| `tile8x8_stream64tokens` | ideal / X30 utilization | 95.88% | 94.99% | -0.89 pp |
| `matmul64x64_runtime_shape`, 64 tokens | X30 Tensor window | 4,660 | 4,699 | 1.008x |
| `matmul64x64_runtime_shape`, 64 tokens | MAC utilization | 87.90% | 87.17% | -0.73 pp |
| `matmul64x64_runtime_shape`, 128 tokens | X30 Tensor window | 8,772 | 8,785 | 1.001x |
| `matmul64x64_runtime_shape`, 128 tokens | MAC utilization | 93.39% | 93.25% | -0.14 pp |

The Tensor case performs 512 consecutive 8x8 vector steps with one WLD and one
Tensor start. Its 4096 BF16 output elements are checked after DTCM-to-AXI DMA.
The five-cycle lite gap is therefore small: serialized scalar issue hurts
CoreMark substantially, but it does not materially reduce a long Tensor run
after launch. This case intentionally isolates the Tensor engine.

The two runtime-shape cases use one shared C++ implementation on both cores and
check every 4096- or 8192-element public-contiguous BF16 output. Software reads
the hardware-ID CSR to derive Tensor rows and columns, packs the public input
with strided DMA, streams public BF16 weights through packed-XY DMA and
transposed circular WLD, then scatters the private blocked output back to its
public layout. The X30 window isolates weight production and Tensor execution;
input packing and output scatter remain outside it. Lite is 39 cycles slower
for 64 tokens and 13 cycles slower for 128 tokens, so serialized scalar issue
does not reduce steady Tensor throughput.

The unchanged standard `bf16_wld_direct_circular.cpp` program is also a lite
regression. It covers cache clean-by-VA, direct DMA, direct and transposed WLD,
XY-strided circular DMA, circular WLD, scalar DTCM result checks, DMA sync, and
the Edge break CSR. A successful return proves that these paths use the same
shared implementation rather than a reduced lite substitute.

## Microarchitecture

The core is single issue and has three architectural stages:

1. **F** accepts one 32- or 64-bit instruction.
2. **D** classifies it with the Edge-compatible predecoder and reads operands.
3. **X/W** owns the instruction until its one completion handshake arrives,
   then writes architectural state and accepts the next instruction.

Branches, JAL and JALR resolve in X. A taken control transfer clears F and D,
then restarts fetch at the target. There is no predictor or epoch machinery;
the fixed taken penalty is the intended area tradeoff.

Fast instructions overlap across the three stages, but only EX may start an
operation. An unfinished EX freezes IF and ID, so variable-latency operations
remain strictly one at a time. Consequently the core has no RTU,
sequence ID, epoch, snapshot, scoreboard, completion arbitration, replay queue,
or multi-port writeback. Accelerator operands are read only when its request is
accepted, and the core cannot execute a younger register write until that
accelerator operation completes.

This is an area/performance trade: it is suitable when the RISC-V core mainly
boots, configures, and occasionally synchronizes an ASIC.  `edge-rv` remains
the better choice when scalar preparation must overlap accelerator work.

## Decode compatibility

`edge_rv_lite_decode.v` is a compatibility wrapper around the shared
`edge_instruction_classifier`; it does not own a second legality table. ID
classifies once and carries the class, legality, and GPR-write metadata into
EX. The shared classifier covers RV64I, RV64M, Zba, Edge FP32/low-precision
load-store, CSR/system/fence, Edge cache/DMA control, and the 64-bit
vector/tensor/DMA/ACTU/CMPU/get-CSR envelope selected by the `7'h3f` length
marker. Lite applies only product capability checks for units it actually
implements.

The ALU, branch, MUL/DIV and FPU RTL is not forked: the lite filelist references
the implementations in `../edge-rv` directly. Lite owns only predecode/control,
the one-entry LSU/BIU path, and the serialized ASIC glue. `ENABLE_FPU` defaults
to `0` on the bare, cached, and AXI tops. Setting it to `1` instantiates the
shared single-issue `edge_fpu_alu`, enables FP32 load/store and arithmetic, and
reports FPU version 1 in hardware ID CSR `0xfc0`.

The "one-entry LSU" is not an outstanding queue. It is one request register and
a three-state `IDLE -> REQUEST -> RESPONSE` controller. The whole core waits for
that response before another instruction may enter execution.

## Optional FPU and precision normalization

`ENABLE_FPU` defaults to `0`. Enabling it adds the shared single-issue
`edge_fpu_alu` and FPR file. FP8, FP16, BF16, and FP32 are memory formats:
loads convert to FP32, all arithmetic uses the FP32 ALU, and stores convert from
FP32. This lets bare-metal C++ accept accidental `double` code (`1.0` instead
of `1.0f`) without soft-float helpers, but does not provide FP64 accuracy.

The enabled profile implements architectural `fflags` (`0x001`), `frm`
(`0x002`), and `fcsr` (`0x003`) CSRs. FPU completions sticky-OR
`NV,DZ,OF,UF,NX` into `fflags`; CSR writes can clear or replace them. Static
RNE, RTZ, RDN, RUP, and RMM are supported. An instruction with dynamic
`rm=111` uses `frm`, and traps as illegal when `frm` contains a reserved value.
With `ENABLE_FPU=0`, these FP CSRs and all FP operations remain illegal.

FP memory instructions use I-type loads (`opcode=0000111`) and S-type stores
(`opcode=0100111`). `imm[11:0]`, `rs1`, and `rd`/`rs2` retain their standard
positions.

| Memory format | Load encoding: `imm[11:0] rs1 funct3 rd opcode` | Store encoding: `imm[11:5] rs2 rs1 funct3 imm[4:0] opcode` | Bytes |
| --- | --- | --- | ---: |
| FP16 | `imm rs1 001 rd 0000111` | `imm[11:5] rs2 rs1 001 imm[4:0] 0100111` | 2 |
| FP32 | `imm rs1 010 rd 0000111` | `imm[11:5] rs2 rs1 010 imm[4:0] 0100111` | 4 |
| BF16 | `imm rs1 101 rd 0000111` | `imm[11:5] rs2 rs1 101 imm[4:0] 0100111` | 2 |
| FP8 E5M2 | `imm rs1 110 rd 0000111` | `imm[11:5] rs2 rs1 110 imm[4:0] 0100111` | 1 |
| FP8 E4M3FN | `imm rs1 111 rd 0000111` | `imm[11:5] rs2 rs1 111 imm[4:0] 0100111` | 1 |

Loads promote each format to the physical FP32 FPR representation. Stores use
round-to-nearest, ties-to-even; FP8 overflow saturates to the largest finite
value. `funct3=000`, `011`, and `100` are unsupported and trap before issuing a
memory request.

Arithmetic format suffixes do not select different datapaths. For example,
`fmul.s`, `fmul.h`, and `fmul.d` ignore `fmt=inst[26:25]` and all execute as
`fmul.s` on the physical FP32 operands.

### Packed FP4

FP4 uses the NVFP4 finite E2M1 element (`S EE M`, exponent bias 1):
`+/-0`, `+/-0.5`, `+/-1`, `+/-1.5`, `+/-2`, `+/-3`, `+/-4`, and `+/-6`.
It has no Inf or NaN encoding. Block scaling is outside this definition and is
left to WLD/SLD.

`fp4x16_t` is one `uint64_t data` field and remains packed in a GPR; FP4 is not
loaded into the FPR file through the LSU.

| Instruction | `funct7` | `rs2` | `funct3` | `opcode` | Operation |
| --- | --- | --- | --- | --- | --- |
| `fmv.s.xfp4 fd, rs1` | `1111011` | `00000` | `000` | `1010011` | Expand `rs1[3:0]` to FP32 `fd`; ignore `rs1[63:4]` |
| `fmv.xfp4.s rd, fs1` | `1110011` | `00000` | `000` | `1010011` | RNE FP32 `fs1` to a zero-extended E2M1 nibble in `rd` |

The reverse conversion saturates finite overflow and infinity to `+/-6`,
preserves signed zero, and maps NaN to positive zero. Software selects an
element with RV64I shifts before `fmv.s.xfp4`. To build `fp4x16_t`, repeatedly
shift the packed GPR left by four and OR in the result of `fmv.xfp4.s`.

Enable the FPU when software needs to:

1. Generate test or model data, such as FP8 weights.
2. Implement a fallback kernel for an operation not supported by ACTU, CMPU,
   or another ASIC unit. It is slower, but guarantees a software path exists.
3. Use floating-point formatting such as `printf("%f", value)` to dump data.
4. Compute reference results in C++ and check ASIC outputs during bring-up.

Once the ASIC units cover the complete workload and FPU-based generation,
fallback, debug, and validation are no longer needed, disable the FPU to
recover ASIC area and FPGA resources.

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

## Drop-in boundary

The integration rule is source-level compatibility, selected by filelist:

- keep the Edge SoC-facing IFU, BIU/D-cache/DTCM and ASIC command signals;
- keep `edge-rv` ALU/FPU module interfaces and RTL;
- replace the dual-issue predecoder/scalar pipe and RTU/snapshot/command queues
  with the lite top and its one-owner controller;
- tie lane 1 permanently invalid at any compatibility wrapper.

`filelists/edge_rv_lite.fl` is the canonical source selection. The parent
product supplies `${EDGE_RV_ROOT}` and `${EDGE_RV_LITE_ROOT}`. A composed
edge-e3 lite top must use the same external module ports as the normal
`edge_core_top`; merely swapping leaf implementations while retaining the
normal top would still synthesize its RTU and queues.

## Build and test

```sh
cmake -S . -B build
cmake --build build --target edge_rv_lite_coremark_vvp
ctest --test-dir build --output-on-failure
```

The `edge_rv_lite_coremark` test runs the exact RV64 CoreMark memory image built
by the parent edge-e3 harness. The first bootable LLVM 22.1.8 result retired
616,228 instructions, matching edge-rv instruction-for-instruction, and
returned a measured CoreMark interval of 724,712 cycles before the crt0
`ebreak`. The locally reproducible LLVM 19.1.1 image retires 743,510
instructions on lite; cached and AXI integration tests use that value as their
regression baseline. Do not compare either instruction count against an image
generated by the other compiler.

Software-test termination is a harness contract, not a memory-map feature of
the core. Bare-metal crt0 writes its optional report symbols as ordinary RAM,
then executes `csrw 0x7e0, a0`; the simulation harness observes the resulting
`halted` output and reads the return value from `debug_x31`. No RAM address is
implicitly decoded as a mailbox or exit request. In particular, stores to the
former `0x2ee8` test-image location remain ordinary data-memory transactions.

The current bootable core covers RV64IM_Zba, `rdcycle`, `rdinstret`, the crt0
`ebreak`, the Edge break CSR, and the standard D-cache clean/invalidate
instructions used around DMA. `FENCE.I` drains accepted instruction refills,
invalidates every I-cache line, flushes younger fetch/decode state, and resumes
at the following instruction. After self-modifying stores or DMA code loading,
software must complete the D-cache clean/writeback or DMA operation before
executing `FENCE.I`. Ordered 32-bit fetch parcels are assembled into
complete Edge64 instructions and held in EX across a serialized accelerator
request and response. The product-side single-owner leaf connects this
boundary to the shared accelerator dispatch without snapshots, sequence IDs
or epochs.

The integration boundary is intentionally split into a shared platform and a
replaceable scalar cluster. The platform owns I/D cache, BIU, DTCM, DMA and the
ASIC execution units. A stateless shared classifier owns the 32-bit versus
64-bit instruction format; edge-rv adds dual-issue/RTU/snapshot policy around
it, while edge-rv-lite consumes one classified instruction at a time. The lite
cache adapters and `edge_rv_lite_cached_core` now compose the bootable core with
the maintained I/D caches. An optional stateful DTCM router bypasses D-cache for
the configured base/mask window, acknowledges accepted stores, and retains the
selected cache or DTCM read owner through its response. `edge_rv_lite_cache_biu` and
`edge_rv_lite_axi_core` carry that hierarchy onto the existing 128-bit Edge AXI
channel shape. The cache BIU checks response IDs, response status, burst beat
counts, and `RLAST`; failed instruction fills fault without populating I-cache,
while failed dirty writeback beats remain buffered and retry. AW and W
handshake independently. `edge_core_lite_top` composes those proven boundaries with the
shared DTCM/accelerator subsystem and external AXI ownership mux.

Lite memory operations use a single architectural alignment policy before any
cached, uncached, or DTCM routing. Byte accesses are unrestricted; halfword,
word, and doubleword accesses must be naturally aligned. Misaligned loads and
stores fault without issuing a memory request.

Below the issue-policy boundary, both products instantiate
`edge_accel_data_ctrl`. This common layer owns direct DMA, XY-strided DMA,
circular DMA, Tensor circular WLD/SLD/WSLD scheduling, and the Tensor/DTCM
command mux. The normal core keeps its dual-issue queue and snapshot policy;
lite keeps its one-command owner. Lite therefore changes scheduling policy,
not accelerator behavior, and does not contain a rewritten DMA engine.

The lite DTCM router also normalizes raw bank reads to the same size/sign
formatted response used by D-cache. This is required for standard accelerator
tests that validate BF16 or byte results through scalar loads.

## Choosing between edge-rv and edge-rv-lite

The main question is not only how much scalar performance is required. It is
whether the workload needs to construct and queue many fine-grained ASIC
instructions dynamically.

### Choose edge-rv dual issue for dynamic command generation

`edge-rv` is the better fit when the accelerator instruction stream has many
stages and benefits from the snapshot mechanism. Software can prepare the next
instruction's operands in advance, snapshot them into the command queue, and
then issue that ASIC instruction without waiting for its parameters to be
reconstructed at dispatch time.

In this role, the RISC-V dual-issue pipeline acts like a small JIT compiler: it
runs a real loop, calculates the next command and dynamically produces the ASIC
instruction queue. This avoids statically expanding the loop into tens of
thousands of ASIC instructions, which would consume I-cache capacity and make
instruction fetch compete with data traffic.

This does not mean that every optimized kernel needs a large I-cache. In the
author's experience, a well-written attention kernel is around 8 KiB, so its
hot path can fit entirely in I-cache and run at a 100% I-cache hit rate. The
important distinction is whether the compact loop must dynamically generate
addresses, shapes or commands.

Dual issue is recommended when the workload needs capabilities such as:

1. Calculating sparse addresses for MoE routing or gathers.
2. Handling a growing token count or another dynamic shape. A fixed 64- or
   128-token kernel fitted to a vLLM page can avoid this requirement, but a
   general dynamic-shape implementation cannot.
3. Preparing and queueing many dependent ASIC commands while earlier commands
   are still running.

### Choose edge-rv-lite for static, coarse-grained acceleration

`edge-rv-lite` is a better fit when the execution flow is mostly static, the
ASIC is highly integrated, and circular DMA is already used effectively to
buffer DRAM traffic. It works especially well when one accelerator instruction
does a large amount of work—for example, launching an entire 512x512 matrix
multiplication—because scalar command-generation overhead is then negligible.

The tradeoff is therefore straightforward: use dual issue when RISC-V must
dynamically build a fine-grained accelerator schedule; use lite when RISC-V
mostly configures and launches a small number of coarse-grained operations.

## Overall product area comparison

Both product tops were synthesized from the same revision with Yosys
`synth_xilinx -family xc7 -noiopad -noclkbuf`. `edge_core_top` uses the normal
dual-issue scalar owner; `edge_core_lite_top` replaces only that outer owner
with the serialized rv-lite core. Both tops retain the same Tensor, DMA, DTCM,
ACTU/CMPU, I-cache, and D-cache product RTL and use the same SRAM-to-BRAM
wrappers.

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

Replacing `edge-rv` with `edge-rv-lite` reduces the complete product by 98,522
Yosys cells, or **34.7%**. LUT usage falls by **37.4%** and flip-flop usage by
**27.3%**, while BRAM capacity is unchanged.

Reproduce the comparison with:

```sh
EDGE_YOSYS_VARIANT=xilinx-top-compare-20260811 \
  ./synth/run_yosys.sh edge_core_top xilinx \
  synth/filelists/edge_existing.fl
EDGE_YOSYS_VARIANT=xilinx-top-compare-20260811 \
  ./synth/run_yosys.sh edge_core_lite_top xilinx \
  synth/filelists/edge_lite_top.fl

EDGE_YOSYS_VARIANT=xilinx-clean \
  ./synth/run_yosys.sh edge_rv_top xilinx \
  synth/filelists/edge_rv.fl
EDGE_YOSYS_VARIANT=xilinx-lite-cached \
  ./synth/run_yosys.sh edge_rv_lite_cached_core xilinx \
  src/edge-rv-lite/filelists/edge_rv_lite.fl
```

These are FPGA-oriented Yosys estimates, not Vivado placement/routing or ASIC
area results.

Build and run the maintained lite Tensor proof with:

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
