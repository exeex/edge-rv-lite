# edge_rv_lite_lsu

The lite LSU owns exactly one architectural memory instruction. `op_ready`
is asserted only in `IDLE`; request payload is registered and held throughout
backpressure. Loads wait for `mem_resp_valid`. Stores also wait for an explicit
write acknowledgement unless `STORE_ACK_ON_ACCEPT=1` is selected for a local
memory whose request acceptance is architecturally complete. `op_done` is the
architectural completion pulse; it is not an RTU retirement event.

`MEM_RESP_FORMATTED=0` selects the standalone raw 64-bit memory contract and
performs byte-offset extraction plus sign extension in the lite LSU.
`MEM_RESP_FORMATTED=1` selects the maintained `edge_dcache` contract, whose
response is already extracted and extended; the LSU forwards that value
without formatting it a second time. The cached-core wrapper uses this mode.

`op_fp` selects the FP memory size mapping. FP16/BF16 are two-byte accesses,
FP32 is four bytes, and both FP8 formats are one byte despite their reserved
`funct3=110/111` encodings. FP requests are unsigned at the memory boundary;
`edge_rv_lite_fp_mem_format` performs promotion and narrowing at the FPR edge.

All integer and FP memory operations require natural alignment: two-byte
accesses require `addr[0]=0`, four-byte accesses require `addr[1:0]=0`, and
eight-byte accesses require `addr[2:0]=0`; byte accesses are always aligned.
An unsupported misaligned operation completes locally with `op_error=1` and
never asserts `mem_req_valid`. Because this check precedes cached, uncached,
and DTCM routing, every memory path has the same policy and a faulting store
cannot partially modify memory.

There are no sequence IDs, epochs, load queue, store buffer, forwarding, replay,
or redirect handling. The global lite owner prevents a younger instruction
from existing, so an LSU operation cannot be wrong-path once started.

The focused test covers request backpressure, signed subword formatting, store
strobes, completion ordering, and every size at the last legal and first
crossing offset, including side-effect-free load/store faults.
