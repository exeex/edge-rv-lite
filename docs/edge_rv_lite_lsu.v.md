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

There are no sequence IDs, epochs, load queue, store buffer, forwarding, replay,
or redirect handling. The global lite owner prevents a younger instruction
from existing, so an LSU operation cannot be wrong-path once started.

The focused test covers request backpressure, signed subword formatting, store
strobes, and the rule that neither load nor store completes before its response.
