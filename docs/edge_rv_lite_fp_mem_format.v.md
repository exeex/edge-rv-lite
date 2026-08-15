# edge_rv_lite_fp_mem_format

This combinational leaf is the lite core's FP memory-format boundary. The FPR
file remains physical FP32. Loads promote FP16 (`funct3=001`), FP32 (`010`),
BF16 (`101`), FP8 E5M2 (`110`), and FP8 E4M3FN (`111`) into FP32. Stores narrow
the FP32 source with round-to-nearest, ties-to-even; FP8 overflow saturates to
the largest finite encoding and NaNs are canonicalized.

The classifier owns encoding legality and the LSU owns byte addressing and
strobes. This leaf does not issue memory requests or maintain state. Directed
lite FPU integration tests load and store 1.5 in every supported format and
check the resulting request width and payload.
