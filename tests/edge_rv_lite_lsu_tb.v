`timescale 1ns/1ps
module edge_rv_lite_lsu_tb;
  reg clk = 0; always #5 clk = ~clk;
  reg reset_n = 0, op_valid = 0, op_store = 0;
  reg [2:0] op_funct3 = 0;
  reg [63:0] op_base = 0, op_offset = 0, op_store_data = 0;
  wire op_ready, mem_req_valid, mem_req_write;
  reg mem_req_ready = 0;
  wire [63:0] mem_req_addr, mem_req_wdata; wire [7:0] mem_req_wstrb;
  reg mem_resp_valid = 0, mem_resp_error = 0;
  reg [63:0] mem_resp_rdata = 0;
  wire op_done, op_error; wire [63:0] op_load_value; wire busy;
  edge_rv_lite_lsu dut(.*);

  initial begin
    repeat (2) @(posedge clk); reset_n <= 1;
    // Signed byte load at byte offset 3; request backpressure must hold payload.
    @(posedge clk); op_valid <= 1; op_funct3 <= 3'b000;
    op_base <= 64'h1000; op_offset <= 3; op_store <= 0;
    @(posedge clk); op_valid <= 0;
    repeat (2) begin
      @(posedge clk);
      if (!mem_req_valid || mem_req_addr != 64'h1003 || op_ready)
        begin $display("load request was not held"); $finish; end
    end
    mem_req_ready <= 1; @(posedge clk); mem_req_ready <= 0;
    repeat (2) begin
      @(posedge clk);
      if (!busy || op_ready || op_done)
        begin $display("load did not wait for response"); $finish; end
    end
    mem_resp_rdata <= 64'h0000_0080_0000_0000; mem_resp_valid <= 1;
    @(posedge clk); mem_resp_valid <= 0;
    if (!op_done || op_load_value != 64'hffff_ffff_ffff_ff80)
      begin $display("bad signed load result %h", op_load_value); $finish; end

    // Store is also not complete at request acceptance; wait for write ack.
    @(posedge clk); op_valid <= 1; op_store <= 1;
    op_funct3 <= 3'b010; op_base <= 64'h2000; op_offset <= 4;
    op_store_data <= 64'h0000_0000_aabb_ccdd;
    @(posedge clk); op_valid <= 0;
    wait (mem_req_valid); mem_req_ready <= 1; @(posedge clk); mem_req_ready <= 0;
    if (op_done || !busy || mem_req_wstrb != 8'hf0)
      begin $display("store completed before ack or bad strobe"); $finish; end
    repeat (2) @(posedge clk);
    mem_resp_valid <= 1; @(posedge clk); mem_resp_valid <= 0;
    if (!op_done || op_error)
      begin $display("store ack did not complete"); $finish; end
    $display("TEST PASS: one memory op waits through request and response");
    $finish;
  end
endmodule
