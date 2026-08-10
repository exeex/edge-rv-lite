# edge_rv_lite_axi_core.v

This integration wrapper composes `edge_rv_lite_cached_core` and
`edge_rv_lite_cache_biu`. Its AXI port names, widths, IDs, burst lengths and
cache attributes match the `biu_pad_*`/`pad_biu_*` boundary of the maintained
Edge product core. It is therefore the first lite boundary that can connect to
the existing SoC AXI interconnect without testbench SRAM ports.

The wrapper currently starts at reset PC zero and exposes halt, illegal, x31,
cycle and instret status for bring-up. It does not yet implement the full
`edge_core_top` control surface (`core_start`, dynamic `boot_pc`, DMA or ASIC
commands), so it is not yet a drop-in module-name replacement. Those controls
belong in the later product-compatible wrapper rather than in the cache BIU.

`AXI_DATA_WIDTH` is fixed architecturally to 128 bits because both maintained
caches exchange 16-byte beats. Reads and dirty writebacks may progress
independently, matching the separate AXI read and write channels.

The integration CoreMark test places the same parent-produced 64-bit image
behind an AXI slave model, checks the `0xf1` and `0xd1` refill IDs and burst
attributes, and requires the same architectural `instret=616228` signature as
the direct-memory and cache-boundary tests.
