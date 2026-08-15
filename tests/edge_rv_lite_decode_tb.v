`timescale 1ns/1ps

module edge_rv_lite_decode_tb;
  reg [63:0] inst;
  reg inst_is_64b;
  wire [3:0] op_class;
  wire legal;
  wire [4:0] rd, rs1, rs2;
  wire accel_needs_capture;
  wire [4:0] accel_capture_src_gpr;
  wire writes_gpr;
  wire [6:0] accel_subop;

  wire [3:0] shared_op_class;
  wire shared_legal, shared_writes_gpr;
  wire [4:0] shared_rd, shared_rs1, shared_rs2;
  wire [6:0] shared_accel_subop;
  wire shared_accel_needs_capture;
  wire [4:0] shared_accel_capture_src_gpr;
  integer opcode_i, funct3_i, funct7_i;

  edge_rv_lite_decode dut (.*);
  edge_instruction_classifier shared (
    .inst(inst), .inst_is_64b(inst_is_64b),
    .op_class(shared_op_class), .legal(shared_legal),
    .rd(shared_rd), .rs1(shared_rs1), .rs2(shared_rs2),
    .scalar_issue_class(), .writes_gpr(shared_writes_gpr), .is_edge64(),
    .accel_is_tensor(), .accel_subop(shared_accel_subop),
    .accel_needs_capture(shared_accel_needs_capture),
    .accel_capture_src_gpr(shared_accel_capture_src_gpr),
    .accel_needs_base_gpr(), .accel_base_src_gpr(),
    .accel_is_sync(), .accel_is_getcsr());

  task check_shared_match;
    begin
      #1;
      if ({op_class, legal, rd, rs1, rs2, writes_gpr, accel_subop,
           accel_needs_capture, accel_capture_src_gpr} !==
          {shared_op_class, shared_legal, shared_rd, shared_rs1, shared_rs2,
           shared_writes_gpr, shared_accel_subop,
           shared_accel_needs_capture, shared_accel_capture_src_gpr})
        $fatal(1, "lite/shared drift inst=%h lite class/legal=%0d/%0d shared=%0d/%0d",
               inst, op_class, legal, shared_op_class, shared_legal);
    end
  endtask

  task check_accel;
    input tensor;
    input [6:0] subop;
    input expected_legal;
    begin
      inst = 64'd0;
      inst[6:0] = 7'h3f;
      inst[38:32] = subop;
      inst[39] = tensor;
      inst_is_64b = 1'b1;
      #1;
      if (op_class != 4'd8 || legal != expected_legal ||
          accel_subop != subop)
        $fatal(1, "accel decode tensor=%0d subop=%h legal=%0d class=%0d",
               tensor, subop, legal, op_class);
    end
  endtask

  initial begin
    check_accel(1'b1, 7'h11, 1'b1); // tensor.wld
    check_accel(1'b1, 7'h15, 1'b1); // tensor.start
    check_accel(1'b1, 7'h19, 1'b1); // tensor.start_tile
    check_accel(1'b1, 7'h1b, 1'b1); // tensor.wld_circular
    check_accel(1'b1, 7'h1c, 1'b1); // tensor.wld_t_circular
    check_accel(1'b1, 7'h1e, 1'b1); // tensor.wsld_circular
    check_accel(1'b1, 7'h1f, 1'b1); // tensor.sld_circular
    check_accel(1'b1, 7'h24, 1'b1); // actu.setscalar
    check_accel(1'b1, 7'h7f, 1'b0); // unallocated ASIC command
    check_accel(1'b0, 7'h33, 1'b1); // structurally valid vector opcode

    inst = 64'h0000_0000_0000_003f;
    inst_is_64b = 1'b0;
    #1;
    if (legal) $fatal(1, "32-bit length marker escaped as scalar");

    inst = 64'h0000_0000_0000_00b3; // add x1,x0,x0
    inst_is_64b = 1'b0;
    #1;
    if (!legal || op_class != 4'd0 || rd != 5'd1)
      $fatal(1, "RV64 ALU decode changed");

    // Every opcode/funct3/funct7 combination must be identical at the lite
    // compatibility boundary and the shared classifier.
    inst_is_64b = 1'b0;
    for (opcode_i = 0; opcode_i < 128; opcode_i = opcode_i + 1)
      for (funct3_i = 0; funct3_i < 8; funct3_i = funct3_i + 1)
        for (funct7_i = 0; funct7_i < 128; funct7_i = funct7_i + 1) begin
          inst = 64'd0;
          inst[6:0] = opcode_i[6:0];
          inst[14:12] = funct3_i[2:0];
          inst[31:25] = funct7_i[6:0];
          check_shared_match();
        end

    // RV64M OP-32 reserves funct3 1, 2 and 3 when funct7 is 1.
    for (funct3_i = 1; funct3_i <= 3; funct3_i = funct3_i + 1) begin
      inst = 64'd0;
      inst[6:0] = 7'h3b;
      inst[14:12] = funct3_i[2:0];
      inst[31:25] = 7'h01;
      #1;
      if (legal)
        $fatal(1, "reserved OP-32 M encoding accepted funct3=%0d", funct3_i);
    end

    // Cache legality, including funct7 and the index-op rs1 constraint, is
    // owned by the same classifier for every consumer.
    inst = 64'd0; inst[6:0] = 7'h0b; inst[24:20] = 5'd1;
    #1; if (!legal) $fatal(1, "legal cache index op rejected");
    inst[19:15] = 5'd1;
    #1; if (legal) $fatal(1, "cache index op accepted nonzero rs1");
    inst[19:15] = 5'd0; inst[31:25] = 7'd1;
    #1; if (legal) $fatal(1, "cache op accepted nonzero funct7");

    $display("TEST PASS: exhaustive lite/shared decode and reserved encodings");
    $finish;
  end
endmodule
