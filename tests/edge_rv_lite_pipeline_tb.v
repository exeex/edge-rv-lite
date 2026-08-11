`timescale 1ns/1ps
module edge_rv_lite_pipeline_tb;
  reg clk = 0; always #5 clk = ~clk;
  reg reset_n = 0, fetch_valid = 0, fetch_error = 0;
  wire fetch_ready; reg [39:0] fetch_pc = 0; reg [63:0] fetch_inst = 0;
  reg fetch_is_64b = 0;
  wire id_valid; wire [39:0] id_pc; wire [63:0] id_inst; wire id_is_64b;
  wire id_error;
  reg [4:0] id_rs1 = 0, id_rs2 = 0;
  reg [63:0] id_rs1_raw = 0, id_rs2_raw = 0;
  wire ex_valid; wire [39:0] ex_pc; wire [63:0] ex_inst; wire ex_is_64b;
  wire ex_error;
  wire [63:0] ex_rs1_value, ex_rs2_value;
  reg ex_done = 1, ex_write_valid = 0, ex_redirect_valid = 0;
  reg [4:0] ex_write_rd = 0; reg [63:0] ex_write_value = 0;
  edge_rv_lite_pipeline dut(.*);

  task push;
    input [39:0] pc; input [31:0] inst;
    begin
      while (!fetch_ready) @(posedge clk);
      fetch_valid <= 1; fetch_pc <= pc; fetch_inst <= {32'b0, inst};
      @(posedge clk); fetch_valid <= 0;
    end
  endtask

  initial begin
    repeat (2) @(posedge clk); reset_n <= 1;
    // Normal overlap: one instruction in ID while the older one is in EX.
    fetch_valid <= 1; fetch_pc <= 0; fetch_inst <= 64'h0010_0093;
    @(posedge clk); fetch_pc <= 4; fetch_inst <= 64'h0010_8113;
    @(posedge clk); fetch_valid <= 0;
    if (!id_valid || !ex_valid || id_pc != 4 || ex_pc != 0)
      begin $display("three-stage overlap missing"); $finish; end

    // Completing EX x1 result forwards into the dependent ID instruction.
    id_rs1 <= 5'd1; id_rs1_raw <= 64'hdead;
    ex_write_valid <= 1; ex_write_rd <= 5'd1; ex_write_value <= 64'h55;
    @(posedge clk); ex_write_valid <= 0;
    if (!ex_valid || ex_pc != 4 || ex_rs1_value != 64'h55)
      begin $display("EX-to-ID forwarding failed"); $finish; end

    // Variable-latency EX freezes both ID and fetch acceptance.
    fetch_valid <= 1; fetch_pc <= 8; fetch_inst <= 64'h0001_2183;
    ex_done <= 0;
    repeat (3) begin
      @(posedge clk);
      if (fetch_ready || ex_pc != 4)
        begin $display("busy EX did not freeze pipeline"); $finish; end
    end
    ex_done <= 1; @(posedge clk); fetch_valid <= 0;
    if (!id_valid || id_pc != 8)
      begin $display("pipeline did not resume"); $finish; end

    // A resolving branch kills the younger ID instruction.
    ex_redirect_valid <= 1; @(posedge clk); ex_redirect_valid <= 0;
    if (id_valid || ex_valid)
      begin $display("redirect did not flush younger work"); $finish; end

    // Width metadata travels with an Edge64 instruction.
    fetch_pc <= 40'h100; fetch_inst <= 64'h1234_5678_0000_003f;
    fetch_is_64b <= 1; fetch_valid <= 1;
    @(posedge clk); fetch_valid <= 0; fetch_is_64b <= 0;
    @(posedge clk);
    if (!ex_valid || !ex_is_64b || ex_inst != 64'h1234_5678_0000_003f)
      begin $display("Edge64 metadata lost"); $finish; end
    $display("TEST PASS: overlap, forwarding, EX freeze, redirect, Edge64");
    $finish;
  end
endmodule
