`timescale 1ns/1ps

module edge_rv_lite_dcache_adapter_tb;
  reg clk = 1'b0;
  reg reset_n = 1'b0;
  always #5 clk = ~clk;

  reg core_req_valid = 1'b0;
  wire core_req_ready;
  reg core_req_write = 1'b0;
  reg [63:0] core_req_addr = 64'd0;
  reg [63:0] core_req_wdata = 64'd0;
  reg [7:0] core_req_wstrb = 8'd0;
  reg [1:0] core_req_size = 2'd0;
  reg core_req_signed = 1'b0;
  wire core_resp_valid, core_resp_error;
  wire [63:0] core_resp_rdata;

  wire cache_load_req_valid;
  reg cache_load_req_ready = 1'b0;
  wire [7:0] cache_load_req_seq_id;
  wire [3:0] cache_load_req_epoch;
  wire [63:0] cache_load_req_addr;
  wire [1:0] cache_load_req_size;
  wire cache_load_req_signed;
  reg cache_load_resp_valid = 1'b0;
  reg cache_load_resp_error = 1'b0;
  reg [63:0] cache_load_resp_value = 64'd0;

  wire cache_store_req_valid;
  reg cache_store_req_ready = 1'b0;
  wire [7:0] cache_store_req_seq_id;
  wire [3:0] cache_store_req_epoch;
  wire [63:0] cache_store_req_addr;
  wire [1:0] cache_store_req_size;
  wire [63:0] cache_store_req_data;
  wire [7:0] cache_store_req_wstrb;

  edge_rv_lite_dcache_adapter dut (.*);

  initial begin
    repeat (2) @(posedge clk);
    reset_n <= 1'b1;

    @(negedge clk);
    core_req_valid = 1'b1;
    core_req_addr = 64'h108;
    core_req_size = 2'd2;
    core_req_signed = 1'b1;
    #1;
    if (!cache_load_req_valid || core_req_ready)
      $fatal(1, "load backpressure routing failed");
    cache_load_req_ready = 1'b1;
    #1;
    if (!core_req_ready || cache_load_req_addr != 64'h108 ||
        cache_load_req_size != 2'd2 || !cache_load_req_signed)
      $fatal(1, "load payload mismatch");
    @(posedge clk);
    @(negedge clk);
    core_req_valid = 1'b0;
    cache_load_req_ready = 1'b0;
    cache_load_resp_value = 64'h0123_4567_89ab_cdef;
    cache_load_resp_valid = 1'b1;
    #1;
    if (!core_resp_valid || core_resp_error ||
        core_resp_rdata != 64'h0123_4567_89ab_cdef)
      $fatal(1, "load response mismatch");
    @(posedge clk);

    @(negedge clk);
    cache_load_resp_valid = 1'b0;
    core_req_valid = 1'b1;
    core_req_write = 1'b1;
    core_req_addr = 64'h11c;
    core_req_size = 2'd2;
    core_req_wdata = 64'haabb_ccdd_0000_0000;
    core_req_wstrb = 8'hf0;
    cache_store_req_ready = 1'b1;
    #1;
    if (!core_req_ready || !cache_store_req_valid ||
        cache_store_req_addr != 64'h11c || cache_store_req_wstrb != 8'hf0)
      $fatal(1, "store payload mismatch");
    @(posedge clk);
    @(negedge clk);
    core_req_valid = 1'b0;
    cache_store_req_ready = 1'b0;
    #1;
    if (!core_resp_valid || core_resp_error)
      $fatal(1, "accepted store did not complete");

    $display("TEST PASS: lite D-cache adapter serializes lane0 load/store");
    $finish;
  end
endmodule
