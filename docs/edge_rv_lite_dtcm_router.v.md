# edge_rv_lite_dtcm_router

This leaf owns the single in-order scalar memory transaction after the lite LSU
selects either the configured DTCM base/mask window or the normal D-cache path.
The selection is made only while idle and remains owned until the selected
response completes; no request can be emitted to both destinations.

DTCM addresses are translated from byte addresses to 64-bit word offsets from
`dtcm_base`. A DTCM read completes on `dtcm_rvalid`. The DTCM SRAM interface
does not return a write response, so an accepted DTCM store generates exactly
one zero/error-free completion on the next cycle. Cache errors and read data
are returned only while cache owns the transaction.

The leaf has no queue, IDs, epochs or flush state because the lite LSU cannot
issue a second operation before the first response. The focused test covers
window misses, DTCM load stalls, store acknowledgement, error routing and the
absence of duplicate or cross-destination requests.
