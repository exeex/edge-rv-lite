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
D-cache; the maintained I-cache contract has no error result.

Dirty writeback is independent of the read owner. Each accepted 128-bit cache
beat becomes one AXI write transaction with ID `0xc1`, full byte strobes and
independent AW/W backpressure state. `dcache_wb_complete` pulses only when the
write response for the cache line's final beat is accepted. The bridge does
not issue DMA, uncached, cache-operation, or multiple-ID traffic.

`DATA_WIDTH` must be 128 and `LEN_WIDTH` must be at least two. `ADDR_WIDTH`,
`ID_WIDTH`, and `LEN_WIDTH` otherwise follow the SoC AXI boundary; fixed ID
constants are sized to `ID_WIDTH`.

The focused test must prove simultaneous I/D arbitration, all four D-cache
response beats, buffered I-cache progress, AW and W backpressure, full write
strobes, and final-beat writeback completion.
