`timescale 1ns/1ps

module edge_rv_lite_cache_biu_tb;
  reg clk = 1'b0;
  reg reset_n = 1'b0;
  always #5 clk = ~clk;

  reg ic_req_valid;
  wire ic_req_ready;
  reg [39:0] ic_req_addr;
  wire ic_resp_valid;
  reg ic_resp_ready;
  wire [127:0] ic_resp_data;
  reg dc_req_valid;
  wire dc_req_ready;
  reg [63:0] dc_req_addr;
  wire dc_resp_valid;
  reg dc_resp_ready;
  wire [127:0] dc_resp_data;
  wire dc_resp_last;
  wire dc_resp_error;
  reg wb_valid;
  wire wb_ready;
  reg [63:0] wb_addr;
  reg [127:0] wb_data;
  reg wb_last;
  wire wb_complete;

  wire [39:0] araddr;
  wire [1:0] arburst;
  wire [3:0] arcache;
  wire [7:0] arid;
  wire [7:0] arlen;
  wire arlock;
  wire [2:0] arprot;
  wire [2:0] arsize;
  wire arvalid;
  reg arready;
  reg [127:0] rdata;
  reg [7:0] rid;
  reg rlast;
  reg [1:0] rresp;
  reg rvalid;
  wire rready;
  wire [39:0] awaddr;
  wire [1:0] awburst;
  wire [3:0] awcache;
  wire [7:0] awid;
  wire [7:0] awlen;
  wire awlock;
  wire [2:0] awprot;
  wire [2:0] awsize;
  wire awvalid;
  reg awready;
  reg [7:0] bid;
  reg [1:0] bresp;
  reg bvalid;
  wire bready;
  wire [127:0] wdata;
  wire wlast;
  wire [15:0] wstrb;
  wire wvalid;
  reg wready;
  integer beat;

  edge_rv_lite_cache_biu dut (
    .clk(clk), .reset_n(reset_n),
    .icache_req_valid(ic_req_valid), .icache_req_ready(ic_req_ready),
    .icache_req_addr(ic_req_addr), .icache_resp_valid(ic_resp_valid),
    .icache_resp_ready(ic_resp_ready), .icache_resp_data(ic_resp_data),
    .dcache_refill_req_valid(dc_req_valid),
    .dcache_refill_req_ready(dc_req_ready),
    .dcache_refill_req_addr(dc_req_addr),
    .dcache_refill_resp_valid(dc_resp_valid),
    .dcache_refill_resp_ready(dc_resp_ready),
    .dcache_refill_resp_data(dc_resp_data),
    .dcache_refill_resp_last(dc_resp_last),
    .dcache_refill_resp_error(dc_resp_error),
    .dcache_wb_valid(wb_valid), .dcache_wb_ready(wb_ready),
    .dcache_wb_addr(wb_addr), .dcache_wb_data(wb_data),
    .dcache_wb_last(wb_last), .dcache_wb_complete(wb_complete),
    .axi_araddr(araddr), .axi_arburst(arburst), .axi_arcache(arcache),
    .axi_arid(arid), .axi_arlen(arlen), .axi_arlock(arlock),
    .axi_arprot(arprot), .axi_arsize(arsize), .axi_arvalid(arvalid),
    .axi_arready(arready), .axi_rdata(rdata), .axi_rid(rid),
    .axi_rlast(rlast), .axi_rresp(rresp), .axi_rvalid(rvalid),
    .axi_rready(rready), .axi_awaddr(awaddr), .axi_awburst(awburst),
    .axi_awcache(awcache), .axi_awid(awid), .axi_awlen(awlen),
    .axi_awlock(awlock), .axi_awprot(awprot), .axi_awsize(awsize),
    .axi_awvalid(awvalid), .axi_awready(awready), .axi_bid(bid),
    .axi_bresp(bresp), .axi_bvalid(bvalid), .axi_bready(bready),
    .axi_wdata(wdata), .axi_wlast(wlast), .axi_wstrb(wstrb),
    .axi_wvalid(wvalid), .axi_wready(wready)
  );

  task fail;
    input [8*96-1:0] message;
    begin
      $display("TEST FAIL: %0s", message);
      $finish;
    end
  endtask

  initial begin
    ic_req_valid = 1'b0; ic_req_addr = 40'd0; ic_resp_ready = 1'b1;
    dc_req_valid = 1'b0; dc_req_addr = 64'd0; dc_resp_ready = 1'b1;
    wb_valid = 1'b0; wb_addr = 64'd0; wb_data = 128'd0; wb_last = 1'b0;
    arready = 1'b0; rdata = 128'd0; rid = 8'd0; rlast = 1'b0;
    rresp = 2'b00; rvalid = 1'b0; awready = 1'b0; bid = 8'hc1;
    bresp = 2'b00; bvalid = 1'b0; wready = 1'b0;
    repeat (3) @(posedge clk);
    reset_n = 1'b1;
    @(posedge clk); #1;

    // Simultaneous misses: buffer I$, issue blocking D$ first.
    ic_req_valid = 1'b1; ic_req_addr = 40'h0000_0010;
    dc_req_valid = 1'b1; dc_req_addr = 64'h0000_0000_0000_0100;
    @(posedge clk); #1;
    ic_req_valid = 1'b0;
    if (!arvalid || arid != 8'hd1 || araddr != 40'h100 || arlen != 8'd3 ||
        arsize != 3'd4 || arburst != 2'b01)
      fail("D-cache burst did not win simultaneous arbitration");
    arready = 1'b1;
    @(posedge clk); #1;
    arready = 1'b0; dc_req_valid = 1'b0;

    for (beat = 0; beat < 4; beat = beat + 1) begin
      rvalid = 1'b1;
      rdata = {96'd0, beat[31:0]};
      rlast = beat == 3;
      #1;
      if (!rready || !dc_resp_valid || dc_resp_data[31:0] != beat[31:0] ||
          dc_resp_last != (beat == 3) || dc_resp_error)
        fail("D-cache refill response beat mismatch");
      @(posedge clk); #1;
    end
    rvalid = 1'b0; rlast = 1'b0;

    if (!arvalid || arid != 8'hf1 || araddr != 40'h10 || arlen != 0)
      fail("buffered I-cache request did not follow D-cache burst");
    arready = 1'b1;
    @(posedge clk); #1;
    arready = 1'b0;
    rvalid = 1'b1; rlast = 1'b1;
    rdata = 128'h0123_4567_89ab_cdef_fedc_ba98_7654_3210;
    #1;
    if (!ic_resp_valid || ic_resp_data != rdata || !rready)
      fail("I-cache response routing mismatch");
    @(posedge clk); #1;
    rvalid = 1'b0; rlast = 1'b0;

    // Dirty beat must survive independent AW and W backpressure.
    wb_valid = 1'b1; wb_addr = 64'h380;
    wb_data = 128'hdead_beef_cafe_babe_1122_3344_5566_7788;
    wb_last = 1'b1;
    @(posedge clk); #1;
    wb_valid = 1'b0;
    if (!awvalid || awaddr != 40'h380 || awid != 8'hc1 || awlen != 0 ||
        awsize != 3'd4 || wb_ready)
      fail("writeback AW payload or buffering mismatch");
    repeat (2) @(posedge clk);
    awready = 1'b1;
    @(posedge clk); #1;
    awready = 1'b0;
    if (!wvalid || wdata != wb_data || wstrb != 16'hffff || !wlast)
      fail("writeback W payload mismatch");
    wready = 1'b1;
    @(posedge clk); #1;
    wready = 1'b0;
    bvalid = 1'b1;
    #1;
    if (!bready || !wb_complete)
      fail("final write response did not complete dirty line");
    @(posedge clk); #1;
    bvalid = 1'b0;
    if (!wb_ready) fail("writeback buffer did not release");

    $display("EDGE_RV_LITE_CACHE_BIU TEST PASS");
    $finish;
  end
endmodule
