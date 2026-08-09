# edge_rv_lite_pipeline

This is a standard single-issue three-stage pipeline: IF, ID/register-read, and
EX/writeback. Independent fast operations may occupy all stages concurrently.
An unfinished EX operation freezes ID and IF; no younger operation can enter a
functional unit or bypass a load, store, MUL/DIV, FPU, or ASIC command.

The only data bypass is the completing EX GPR result into the ID operands that
advance on the same edge. A redirect from EX clears ID and the current EX valid
after the branch completes; the frontend independently restarts target fetch.
There are no sequence IDs, epochs, RTU records, completion ports, or snapshots.

