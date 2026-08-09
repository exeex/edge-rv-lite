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

The current bootable core covers RV64IM_Zba, `rdcycle`, `rdinstret`, and the
crt0 `ebreak`. The Edge predecoder describes the eventual ASIC routing surface;
connecting that routing and the cache/BIU-compatible product wrapper is the
next integration slice, not part of the standalone CoreMark test yet.
