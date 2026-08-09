# edge_rv_lite_cached_core.v

This integration leaf composes the bootable single-issue lite core with the
maintained `edge_ifu_icache` and `edge_dcache`. The lite adapters translate the
one-owner 32-bit fetch and scalar LSU handshakes into the existing cache
contracts. No testbench memory may connect directly to the core-side request
ports at this boundary.

The external instruction interface is one aligned 16-byte refill. The external
data interface is the maintained 64-byte D-cache refill protocol carried as
four 128-bit beats, plus the 128-bit dirty-line writeback stream and completion
acknowledgement. These are the cache-to-BIU ports that the later
`edge_core_top`-compatible wrapper will arbitrate onto AXI.

Only lane 0 is connected. Lane 1, redirect-kill metadata, cache operations and
backend pause inputs are tied inactive because the lite core cannot have a
younger outstanding scalar memory operation. D-cache sequence and epoch fields
are constant zero. This module adds no RTU, snapshot, replay or completion
queue.

The focused test boots a six-instruction program through real I-cache misses,
loads `41` through a real D-cache miss/refill, stores `42` into the cached line,
loads the hit into `x31`, and executes `ebreak`. It requires at least two
instruction refills, at least one instruction hit, exactly one data refill and
the final value `x31=42`.

The cached CoreMark integration test loads the parent harness memory image only
behind these refill/writeback ports. It services I-cache lines and D-cache
four-beat refills independently, commits dirty writeback beats to the backing
array, and requires the architectural `instret=616228` result. This is the
first lite CoreMark test that includes real cache hit/miss state; it still
stops at the pre-BIU boundary and therefore does not model AXI arbitration.
