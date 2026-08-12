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
    $display("EDGE_FPU_ALU TEST PASS"); $finish;
  end
endmodule
