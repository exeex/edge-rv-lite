`timescale 1ns/1ps

// Compatibility name retained for lite users; all classification is owned by
// the shared metadata-free edge-rv leaf.
module edge_rv_lite_decode (
  input  wire [63:0] inst,
  input  wire        inst_is_64b,
  output wire [3:0]  op_class,
  output wire        legal,
  output wire [4:0]  rd,
  output wire [4:0]  rs1,
  output wire [4:0]  rs2,
  output wire        writes_gpr,
  output wire [6:0]  accel_subop,
  output wire        accel_needs_capture,
  output wire [4:0]  accel_capture_src_gpr
);
  edge_instruction_classifier classifier (
    .inst(inst), .inst_is_64b(inst_is_64b), .op_class(op_class),
    .legal(legal), .rd(rd), .rs1(rs1), .rs2(rs2),
    .scalar_issue_class(), .writes_gpr(writes_gpr), .is_edge64(),
    .accel_is_tensor(), .accel_subop(accel_subop),
    .accel_needs_capture(accel_needs_capture),
    .accel_capture_src_gpr(accel_capture_src_gpr),
    .accel_needs_base_gpr(), .accel_base_src_gpr(),
    .accel_is_sync(), .accel_is_getcsr()
  );
endmodule
