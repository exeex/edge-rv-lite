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

  edge_rv_lite_decode dut (.*);

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

    $display("TEST PASS: lite decode separates RV32 parcels and Edge64 ASIC");
    $finish;
  end
endmodule
