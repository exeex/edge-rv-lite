# edge-rv-lite

`edge-rv-lite` is the minimum-area control-plane alternative to `edge-rv`.
It preserves the same 32-bit scalar opcode families and the same 64-bit Edge
accelerator instruction envelope, but deliberately gives up overlap and
throughput.

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

`edge_rv_lite_decode.v` mirrors the opcode families accepted by the maintained
`edge-rv` scalar pipe: RV64I, RV64M, Zba, Edge FP32/low-precision load-store,
CSR/system/fence, Edge cache/DMA control, and the 64-bit vector/tensor/DMA/
ACTU/CMPU/get-CSR envelope selected by the `7'h3f` length marker.

The ALU, branch, MUL/DIV and FPU RTL is not forked: the lite filelist references
the implementations in `../edge-rv` directly. Lite owns only predecode/control,
the one-entry LSU/BIU path, and the serialized ASIC glue.

The "one-entry LSU" is not an outstanding queue. It is one request register and
a three-state `IDLE -> REQUEST -> RESPONSE` controller. The whole core waits for
that response before another instruction may enter execution.

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
by the parent edge-e3 harness. The first bootable result retires 616,228
instructions, matching edge-rv instruction-for-instruction, and returns a
measured CoreMark interval of 724,712 cycles before the crt0 `ebreak`.

The current bootable core covers RV64IM_Zba, `rdcycle`, `rdinstret`, the crt0
`ebreak`, the Edge break CSR, and the standard D-cache clean/invalidate
instructions used around DMA. Ordered 32-bit fetch parcels are assembled into
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
channel shape. `edge_core_lite_top` composes those proven boundaries with the
shared DTCM/accelerator subsystem and external AXI ownership mux.

Below the issue-policy boundary, both products instantiate
`edge_accel_data_ctrl`. This common layer owns direct DMA, XY-strided DMA,
circular DMA, Tensor circular WLD/SLD/WSLD scheduling, and the Tensor/DTCM
command mux. The normal core keeps its dual-issue queue and snapshot policy;
lite keeps its one-command owner. Lite therefore changes scheduling policy,
not accelerator behavior, and does not contain a rewritten DMA engine.

The lite DTCM router also normalizes raw bank reads to the same size/sign
formatted response used by D-cache. This is required for standard accelerator
tests that validate BF16 or byte results through scalar loads.

## CoreMark and Tensor benchmark report

All numbers below are current local Verilator results using the same software
source on `edge-e3@rv` and `edge-e3@rv-lite`. Internal `rdcycle` is the primary
metric; whole-harness cycles include boot and setup work.

| Case | Metric | edge-e3@rv | edge-e3@rv-lite | Lite / RV |
| --- | --- | ---: | ---: | ---: |
| CoreMark, 2 iterations | cycles/iteration | 409,503 | 785,777 | 1.919x |
| CoreMark | retired instructions | 616,228 | 616,228 | 1.000x |
| `tile8x8_stream64tokens` | X30 Tensor window | 534 | 539 | 1.009x |
| `tile8x8_stream64tokens` | ideal / X30 utilization | 95.88% | 94.99% | -0.89 pp |
| `matmul64x64_64tokens_tiled_circular` | X30 Tensor window | 4,629 | 4,671 | 1.009x |
| `matmul64x64_64tokens_tiled_circular` | MAC utilization | 88.49% | 87.69% | -0.80 pp |
| `matmul64x64_128tokens_tiled_circular` | X30 Tensor window | 8,751 | 8,794 | 1.005x |
| `matmul64x64_128tokens_tiled_circular` | MAC utilization | 93.61% | 93.15% | -0.46 pp |

The Tensor case performs 512 consecutive 8x8 vector steps with one WLD and one
Tensor start. Its 4096 BF16 output elements are checked after DTCM-to-AXI DMA.
The five-cycle lite gap is therefore small: serialized scalar issue hurts
CoreMark substantially, but it does not materially reduce a long Tensor run
after launch. This case intentionally isolates the Tensor engine.

The two tiled circular cases use exactly the same C++ source on both cores and
check every 4096- or 8192-element BF16 output in the testbench. The 64-token
case includes circular weight DMA/WLD; the 128-token case additionally uses
packed-XY DMA and transposed circular WLD. Lite is 42 cycles (0.91%) slower in
the former and 43 cycles (0.49%) slower in the latter. The nearly fixed gap
shows that serialized scalar command issue adds setup cost but does not reduce
steady Tensor throughput.

The unchanged standard `bf16_wld_direct_circular.cpp` program is also a lite
regression. It covers cache clean-by-VA, direct DMA, direct and transposed WLD,
XY-strided circular DMA, circular WLD, scalar DTCM result checks, DMA sync, and
the Edge break CSR. A successful return proves that these paths use the same
shared implementation rather than a reduced lite substitute.

## Shared-layer Yosys guard

The standard `edge-e3@rv` top was synthesized with the Xilinx flow immediately
before and after extracting `edge_accel_data_ctrl`. Tensor and DTCM attribution
are bit-for-bit unchanged; the small LUT/mux differences are packing changes
in the remaining `Other` bucket.

| Resource | Before | After | Delta |
| --- | ---: | ---: | ---: |
| Total cells | 283,884 | 283,882 | -2 |
| LUT1-6 | 169,760 | 169,752 | -8 |
| Flip-flops | 43,301 | 43,301 | 0 |
| CARRY4 | 8,425 | 8,425 | 0 |
| DSP48E1 | 101 | 101 | 0 |
| BRAM36 / BRAM18 | 38 / 32 | 38 / 32 | 0 / 0 |
| Tensor cells | 105,956 | 105,956 | 0 |
| DTCM cells, excluding Tensor | 40,711 | 40,711 | 0 |

The extracted controller itself remains visible as 2,541 synthesized cells,
including the existing 1,203-cell strided controller, so the matching totals
are not caused by accidentally optimizing the functionality away.

## Full-top Yosys comparison

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

The hierarchy attribution confirms where the reduction comes from:

| Bucket | `edge-e3@rv` cells | `edge-e3@rv-lite` cells | Lite delta | Lite share |
| --- | ---: | ---: | ---: | ---: |
| Tensor | 105,956 | 106,052 | +96 | 57.2% |
| DTCM/DMA, excluding Tensor | 40,711 | 40,987 | +276 | 22.1% |
| Other | 137,215 | 38,321 | -98,894 | 20.7% |
| Total | 283,882 | 185,360 | -98,522 | 100.0% |

The small Tensor and DTCM bucket differences are top-context LUT/mux mapping
changes: Tensor keeps the same 72 DSP48E1 and 16,634 flip-flops, DTCM keeps the
same 19 DSP48E1, 6,665 flip-flops, and 32 RAMB36E1. The large reduction is in
`Other`, as expected from removing the normal scalar snapshot, queue, FPU, and
dual-issue machinery. The lite top is therefore 34.7% smaller in total Yosys
cells while preserving the accelerator and memory capacity used by the Tensor
benchmarks above.

Reproduce the comparison with:

```sh
STAREDGE_YOSYS_VARIANT=xilinx-top-compare-20260811 \
  ./synth/run_yosys.sh edge_core_top xilinx \
  synth/filelists/edge_existing.fl
STAREDGE_YOSYS_VARIANT=xilinx-top-compare-20260811 \
  ./synth/run_yosys.sh edge_core_lite_top xilinx \
  synth/filelists/edge_lite_top.fl
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
