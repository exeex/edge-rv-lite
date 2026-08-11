`timescale 1ns/1ps
module edge_rv_lite_dtcm_router_tb;
  reg clk=0; always #5 clk=~clk;
  reg reset_n=0,core_req_valid=0,core_req_write=0;
  reg [63:0] core_req_addr=0,core_req_wdata=0;
  reg [7:0] core_req_wstrb=0;
  reg [1:0] core_req_size=2'd3; reg core_req_signed=0;
  reg cache_req_ready=0,cache_resp_valid=0,cache_resp_error=0;
  reg [63:0] cache_resp_rdata=0;
  reg dtcm_ready=0,dtcm_rvalid=0; reg [63:0] dtcm_rdata=0;
  wire core_req_ready,core_resp_valid,core_resp_error,cache_req_valid;
  wire cache_req_write,dtcm_req,dtcm_we; wire [63:0] core_resp_rdata;
  wire [63:0] cache_req_addr,cache_req_wdata,dtcm_wdata;
  wire [7:0] cache_req_wstrb,dtcm_wstrb; wire [13:0] dtcm_addr;

  edge_rv_lite_dtcm_router dut(
    .clk(clk),.reset_n(reset_n),.dtcm_base(64'h1000_0000),
    .dtcm_mask(64'hffff_ffff_ffff_0000),.dtcm_enable(1'b1),.*);

  initial begin
    repeat(2) @(posedge clk); reset_n=1;
    @(negedge clk); core_req_valid=1; core_req_addr=64'h2000_0040;
    cache_req_ready=1; #1;
    if(!cache_req_valid||dtcm_req||!core_req_ready) $fatal(1,"cache select");
    @(posedge clk); #1; core_req_valid=0; cache_req_ready=0;
    repeat(2) @(posedge clk); @(negedge clk);
    cache_resp_error=1; cache_resp_rdata=64'hbad; cache_resp_valid=1; #1;
    if(!core_resp_valid||!core_resp_error||core_resp_rdata!=64'hbad)
      $fatal(1,"cache response route");
    @(posedge clk); #1; cache_resp_valid=0; cache_resp_error=0;

    @(negedge clk); core_req_valid=1; core_req_addr=64'h1000_001a;
    core_req_size=2'd1; core_req_signed=1'b0;
    core_req_write=0; dtcm_ready=0; #1;
    if(!dtcm_req||cache_req_valid||core_req_ready||dtcm_addr!=14'd3)
      $fatal(1,"dtcm load select/stall");
    dtcm_ready=1; @(posedge clk); #1; core_req_valid=0; dtcm_ready=0;
    repeat(2) @(posedge clk); @(negedge clk);
    dtcm_rdata=64'hdead_beef_1234_cafe; dtcm_rvalid=1; #1;
    if(!core_resp_valid||core_resp_error||core_resp_rdata!=64'h1234)
      $fatal(1,"dtcm load response");
    @(posedge clk); #1; dtcm_rvalid=0;

    @(negedge clk); core_req_valid=1; core_req_write=1;
    core_req_addr=64'h1000_0020; core_req_wdata=64'hfeed;
    core_req_wstrb=8'h0f; dtcm_ready=1; #1;
    if(!dtcm_req||!dtcm_we||dtcm_addr!=14'd4||dtcm_wdata!=64'hfeed||
       dtcm_wstrb!=8'h0f) $fatal(1,"dtcm store payload");
    @(posedge clk); #1; core_req_valid=0; dtcm_ready=0;
    if(!core_resp_valid||core_resp_error) $fatal(1,"dtcm store ack");
    @(posedge clk); #1;
    if(core_resp_valid) $fatal(1,"duplicate store ack");
    $display("EDGE_RV_LITE_DTCM_ROUTER TEST PASS"); $finish;
  end
endmodule
