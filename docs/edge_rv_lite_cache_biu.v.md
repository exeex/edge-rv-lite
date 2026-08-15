# edge_rv_lite_cache_biu.v

This leaf owns the edge-rv-lite cache-to-AXI protocol boundary. It converts
one 16-byte I-cache refill, one four-beat/64-byte D-cache refill, and the
D-cache 16-byte dirty writeback stream into the same 128-bit AXI channel shape
used by `edge_core_top`.

Only one read burst is outstanding. D-cache refill has priority because its
single MSHR blocks the scalar pipeline; a one-entry instruction request buffer
keeps a simultaneous I-cache miss lossless. I-cache reads use ID `0xf1`, one
beat and 16-byte transfers. D-cache reads use ID `0xd1`, four incrementing
beats and 16-byte transfers. AXI read response errors are forwarded to the
D-cache and I-cache. The bridge validates `RID`, `RRESP`, the expected beat
count, and `RLAST` on every accepted response. Early or missing `RLAST` ends
the internal read at the expected protocol boundary and reports an error, so
the bridge cannot silently change ownership or cache a malformed response.

Dirty writeback is independent of the read owner. Each accepted 128-bit cache
beat becomes one AXI write transaction with ID `0xc1`, full byte strobes and
independent AW/W backpressure state. `dcache_wb_complete` pulses only when the
successful write response for the cache line's final beat is accepted. AW and
W may handshake in either order. A bad `BRESP` or `BID` pulses
`dcache_wb_error`, retains the buffered beat, and restarts both write channels;
the D-cache therefore cannot clear dirty state until the retry succeeds. The
bridge does not issue DMA, uncached, cache-operation, or multiple-ID traffic.

`DATA_WIDTH` must be 128 and `LEN_WIDTH` must be at least two. `ADDR_WIDTH`,
`ID_WIDTH`, and `LEN_WIDTH` otherwise follow the SoC AXI boundary; fixed ID
constants are sized to `ID_WIDTH`.

The focused test proves simultaneous I/D arbitration, all four D-cache beats,
I-cache `SLVERR`/`DECERR`, wrong `RID`/`BID`, early and late `RLAST`, buffered
I-cache progress, independent AW/W backpressure, writeback retry, full write
strobes, and final-beat completion.
