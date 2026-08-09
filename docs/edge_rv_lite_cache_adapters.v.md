# edge-rv-lite cache adapters

`edge_rv_lite_icache_adapter` converts one 32-bit lite fetch into the existing
Edge I-cache request and 128-bit response interface. It records only the
requested word offset. A returning response may cross the next request, but no
second request is outstanding.

`edge_rv_lite_dcache_adapter` maps the lite LSU to lane 0 of `edge_dcache`.
Sequence and epoch fields are tied to zero because the core cannot have more
than one memory instruction in flight. Loads complete only on the D-cache load
response. Stores complete one cycle after the D-cache accepts their request.
Lane 1, cache operations, redirects, and DTCM selection belong to the future
SoC compatibility base and are not implemented by these leaf adapters.
