`timescale 1ns/1ps
module edge_fpu_alu_tb;
  reg clk=0, reset_n=0, issue_valid=0, load_write_valid=0;
  reg [31:0] issue_inst=0, load_write_value=0;
  reg [63:0] issue_gpr_src=0;
  reg [4:0] load_write_rd=0, store_read_rs=0;
  wire issue_ready, issue_legal, complete_valid, complete_gpr_write;
  wire [4:0] complete_rd, complete_fflags;
  wire [63:0] complete_value; wire [31:0] store_read_value;
  always #5 clk=~clk;
  edge_fpu_alu dut(.*);
  task load_fpr(input [4:0] r, input [31:0] v); begin
    @(negedge clk); load_write_rd=r; load_write_value=v; load_write_valid=1;
    @(negedge clk); load_write_valid=0;
  end endtask
  function [31:0] fp4_value(input [3:0] nibble); begin
    case(nibble[2:0])
      0: fp4_value={nibble[3],31'b0};
      1: fp4_value={nibble[3],8'h7e,23'b0};
      2: fp4_value={nibble[3],8'h7f,23'b0};
      3: fp4_value={nibble[3],8'h7f,1'b1,22'b0};
      4: fp4_value={nibble[3],8'h80,23'b0};
      5: fp4_value={nibble[3],8'h80,1'b1,22'b0};
      6: fp4_value={nibble[3],8'h81,23'b0};
      default: fp4_value={nibble[3],8'h81,1'b1,22'b0};
    endcase
  end endfunction
  task decode_fp4(input [3:0] nibble); begin
    @(negedge clk); issue_gpr_src={60'ha5a5a5a5a5a5a5a,nibble};
    issue_inst={7'b1111011,5'd0,5'd4,3'b000,5'd5,7'h53}; issue_valid=1;
    #1; if(!issue_ready||!issue_legal) $fatal(1,"fp4 decode not accepted");
    @(negedge clk); issue_valid=0; wait(complete_valid); #1;
    if(complete_gpr_write||complete_rd!=5||complete_value[31:0]!=fp4_value(nibble))
      $fatal(1,"bad fp4 decode nibble=%h value=%h",nibble,complete_value);
  end endtask
  task encode_fp4(input [31:0] value, input [3:0] nibble); begin
    load_fpr(6,value);
    @(negedge clk); issue_inst={7'b1110011,5'd0,5'd6,3'b000,5'd7,7'h53};
    issue_valid=1; #1;
    if(!issue_ready||!issue_legal) $fatal(1,"fp4 encode not accepted");
    @(negedge clk); issue_valid=0; wait(complete_valid); #1;
    if(!complete_gpr_write||complete_rd!=7||complete_value!={60'b0,nibble})
      $fatal(1,"bad fp4 encode value=%h got=%h expected=%h",
             value,complete_value,nibble);
  end endtask
  integer n;
  initial begin
    repeat(2) @(negedge clk); reset_n=1;
    load_fpr(1,32'h3f800000); load_fpr(2,32'h40000000);
    @(negedge clk); issue_inst=32'h002081d3; issue_valid=1; #1;
    if(!issue_ready||!issue_legal) $fatal(1,"fadd not accepted");
    @(negedge clk); issue_valid=0;
    wait(complete_valid); #1;
    if(complete_gpr_write||complete_rd!=3||complete_value[31:0]!=32'h40400000)
      $fatal(1,"bad fadd completion rd=%0d value=%h",complete_rd,complete_value);
    store_read_rs=3; #1;
    if(store_read_value!=32'h40400000)
      $fatal(1,"bad FPR store read %h",store_read_value);
    for(n=0;n<16;n=n+1) decode_fp4(n[3:0]);
    encode_fp4(32'h3e800000,4'h0); // +0.25 tie -> even +0
    encode_fp4(32'h3f400000,4'h2); // +0.75 tie -> even +1
    encode_fp4(32'h3fa00000,4'h2); // +1.25 tie -> even +1
    encode_fp4(32'h3fe00000,4'h4); // +1.75 tie -> even +2
    encode_fp4(32'h40a00000,4'h6); // +5 tie -> even +4
    encode_fp4(32'h7f800000,4'h7); // +Inf saturates to +6
    encode_fp4(32'hff800000,4'hf); // -Inf saturates to -6
    encode_fp4(32'h80000000,4'h8); // preserve negative zero
    encode_fp4(32'h7fc00000,4'h0); // NaN policy: positive zero
    $display("EDGE_FPU_ALU TEST PASS"); $finish;
  end
endmodule
