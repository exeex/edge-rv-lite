# edge_rv_lite_pipeline

The containing `edge_rv_lite_core` handles the read-only hardware-ID CSR
`0xfc0` as a local single-cycle system operation. Its core fields are constants
owned by lite; its product fields come from the elaboration-time
`EDGE_ASIC_ID` parameter. No runtime ID interface crosses this pipeline.

This is a standard single-issue three-stage pipeline: IF, ID/register-read, and
EX/writeback. Independent fast operations may occupy all stages concurrently.
An unfinished EX operation freezes ID and IF; no younger operation can enter a
functional unit or bypass a load, store, MUL/DIV, FPU, or ASIC command.

The only data bypass is the completing EX GPR result into the ID operands that
advance on the same edge. A redirect from EX clears ID and the current EX valid
after the branch completes; the frontend independently restarts target fetch.
There are no sequence IDs, epochs, RTU records, completion ports, or snapshots.

The pipeline carries a complete 64-bit instruction plus an explicit
`is_64b` bit. Scalar instructions keep their upper word zero. The separate
`edge_rv_lite_instruction_assembler` consumes ordered 32-bit frontend parcels;
an opcode `7'h3f` low parcel captures the following parcel and emits one Edge64
instruction at the low parcel's PC. Redirect flush discards an incomplete pair.

An Edge64 instruction remains the sole EX owner until the serialized
accelerator request is accepted and its matching response arrives. This is a
single-owner handshake, not a command queue: no younger scalar or accelerator
instruction can execute while the command is outstanding.

The containing core uses one `ex_faulting` commit gate. A fetch/decode fault
completes without issuing ALU redirects, MUL/DIV, LSU, FPU, cache, or accelerator
requests. An LSU or accelerator response error suppresses GPR writeback. Every
faulting instruction halts as illegal without incrementing `instret`; only a
non-faulting `ebreak` or Edge break performs its normal halt-side effects.

The request operands follow the shared Edge64 classifier rather than assuming
ordinary scalar `rs1/rs2` conventions. `accel_req_src0` carries the classified
base GPR and `accel_req_src1` carries the command-specific capture GPR;
commands without a capture operand drive the latter to zero.
