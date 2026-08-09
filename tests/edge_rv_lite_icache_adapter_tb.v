`timescale 1ns/1ps

module edge_rv_lite_icache_adapter_tb;
  reg clk = 1'b0;
  reg reset_n = 1'b0;
  always #5 clk = ~clk;

  reg core_req_valid = 1'b0;
  wire core_req_ready;
  reg [39:0] core_req_addr = 40'd0;
  wire core_resp_valid;
  wire [31:0] core_resp_data;
  wire core_resp_error;
  wire cache_req_valid;
  reg cache_req_ready = 1'b0;
  wire [39:0] cache_req_addr;
  reg cache_resp_valid = 1'b0;
  wire cache_resp_ready;
  reg [127:0] cache_resp_bits = 128'd0;

  edge_rv_lite_icache_adapter dut (.*);

  initial begin
    repeat (2) @(posedge clk);
    reset_n <= 1'b1;

    @(negedge clk);
    core_req_valid = 1'b1;
    core_req_addr = 40'h8;
    if (core_req_ready) $fatal(1, "request ignored cache backpressure");
    cache_req_ready = 1'b1;
    @(posedge clk);
    @(negedge clk);
    core_req_valid = 1'b0;
    if (!cache_resp_ready) $fatal(1, "accepted fetch not tracked");

    // Return word 2 while crossing a new request for word 3.
    cache_resp_bits = {32'h4444_0003, 32'h3333_0002,
                       32'h2222_0001, 32'h1111_0000};
    cache_resp_valid = 1'b1;
    core_req_valid = 1'b1;
    core_req_addr = 40'hc;
    #1;
    if (!core_resp_valid || core_resp_data != 32'h3333_0002)
      $fatal(1, "wrong 128b response word selection");
    if (!core_req_ready || !cache_req_valid || cache_req_addr != 40'hc)
      $fatal(1, "response/request crossing lost");
    @(posedge clk);

    @(negedge clk);
    cache_resp_valid = 1'b0;
    core_req_valid = 1'b0;
    cache_resp_bits = {32'haaaa_0003, 96'd0};
    cache_resp_valid = 1'b1;
    #1;
    if (!core_resp_valid || core_resp_data != 32'haaaa_0003)
      $fatal(1, "crossing request address was not retained");
    if (core_resp_error) $fatal(1, "unexpected fetch error");
    @(posedge clk);

    $display("TEST PASS: lite I-cache adapter selects words and crosses requests");
    $finish;
  end
endmodule
