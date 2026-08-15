`timescale 1ns/1ps
module edge_rv_lite_frontend_redirect_tb;
  reg clk = 0; always #5 clk = ~clk;
  reg reset_n = 0;
  wire imem_req_valid; reg imem_req_ready = 1;
  wire [39:0] imem_req_addr;
  reg imem_resp_valid = 0; reg [31:0] imem_resp_data = 0;
  reg imem_resp_error = 0;
  wire op_valid; reg op_ready = 1;
  wire [39:0] op_pc; wire [31:0] op_inst; wire op_error;
  reg halt = 0, redirect_valid = 0; reg [39:0] redirect_pc = 0;
  edge_rv_lite_frontend dut(.*);

  task respond;
    input [31:0] data;
    begin
      wait (imem_req_valid); @(posedge clk);
      imem_resp_data <= data; imem_resp_valid <= 1;
      @(posedge clk); imem_resp_valid <= 0;
    end
  endtask

  initial begin
    fork
      begin
        repeat (200) @(posedge clk);
        $fatal(1, "frontend redirect timeout");
      end
    join_none
    repeat (2) @(posedge clk); reset_n <= 1;
    respond(32'h0000_0093);
    wait (op_valid);
    if (op_pc != 0) begin $display("bad reset PC"); $finish; end
    // Model EX resolving a taken branch while a sequential fetch is pending.
    op_ready <= 0;
    wait (dut.request_pending_q); @(posedge clk);
    redirect_pc <= 40'h80; redirect_valid <= 1;
    @(posedge clk); redirect_valid <= 0;
    // Return the killed sequential response; it must never issue.
    imem_resp_data <= 32'hdead_beef; imem_resp_valid <= 1;
    @(posedge clk); imem_resp_valid <= 0; op_ready <= 1;
    wait (imem_req_valid);
    if (imem_req_addr != 40'h80) begin $display("redirect target lost"); $finish; end
    @(posedge clk); imem_resp_data <= 32'h0010_0113; imem_resp_valid <= 1;
    @(posedge clk); imem_resp_valid <= 0;
    wait (op_valid);
    if ((op_pc != 40'h80) || (op_inst == 32'hdead_beef)) begin
      $display("wrong-path instruction escaped"); $finish;
    end
    $display("TEST PASS: EX redirect flushes F/D and restarts target fetch");
    $finish;
  end
endmodule
