`timescale 1ns/1ps

module edge_rv_lite_axi_coremark_tb;
  localparam integer MEM_BYTES = 1024 * 1024;
  localparam integer MEM_WORDS = MEM_BYTES / 8;
  localparam integer TIMEOUT_CYCLES = 10_000_000;

  reg clk = 1'b0;
  reg reset_n = 1'b0;
  always #5 clk = ~clk;

  reg [63:0] mem [0:MEM_WORDS-1];
  string mem64_file;
  integer i;
  integer cycles;
  integer icache_reads;
  integer dcache_reads;
  integer write_responses;
  integer byte_i;

  wire [39:0] araddr;
  wire [1:0] arburst;
  wire [3:0] arcache;
  wire [7:0] arid;
  wire [7:0] arlen;
  wire arlock;
  wire [2:0] arprot;
  wire [2:0] arsize;
  wire arvalid;
  wire arready;
  reg [127:0] rdata_q;
  reg [7:0] rid_q;
  reg rlast_q;
  reg [1:0] rresp_q;
  reg rvalid_q;
  wire rready;
  reg [39:0] raddr_q;
  reg [7:0] rbeats_left_q;

  wire [39:0] awaddr;
  wire [1:0] awburst;
  wire [3:0] awcache;
  wire [7:0] awid;
  wire [7:0] awlen;
  wire awlock;
  wire [2:0] awprot;
  wire [2:0] awsize;
  wire awvalid;
  wire awready;
  wire [127:0] wdata;
  wire wlast;
  wire [15:0] wstrb;
  wire wvalid;
  wire wready;
  reg aw_pending_q;
  reg [39:0] awaddr_q;
  reg [7:0] awid_q;
  reg bvalid_q;
  reg [7:0] bid_q;
  wire bready;

  wire halted;
  wire illegal;
  wire [63:0] debug_x31;
  wire [63:0] cycle_count;
  wire [63:0] instret_count;

  function [127:0] read128;
    input [39:0] addr;
    begin
      read128 = {mem[addr[19:3] + 1], mem[addr[19:3]]};
    end
  endfunction

  assign arready = !rvalid_q && rbeats_left_q == 0;
  assign awready = !aw_pending_q && !bvalid_q;
  assign wready = aw_pending_q && !bvalid_q;

  edge_rv_lite_axi_core dut (
    .forever_cpuclk(clk), .cpurst_b(reset_n),
    .biu_pad_araddr(araddr), .biu_pad_arburst(arburst),
    .biu_pad_arcache(arcache), .biu_pad_arid(arid),
    .biu_pad_arlen(arlen), .biu_pad_arlock(arlock),
    .biu_pad_arprot(arprot), .biu_pad_arsize(arsize),
    .biu_pad_arvalid(arvalid), .pad_biu_arready(arready),
    .pad_biu_rdata(rdata_q), .pad_biu_rid(rid_q),
    .pad_biu_rlast(rlast_q), .pad_biu_rresp(rresp_q),
    .pad_biu_rvalid(rvalid_q), .biu_pad_rready(rready),
    .biu_pad_awaddr(awaddr), .biu_pad_awburst(awburst),
    .biu_pad_awcache(awcache), .biu_pad_awid(awid),
    .biu_pad_awlen(awlen), .biu_pad_awlock(awlock),
    .biu_pad_awprot(awprot), .biu_pad_awsize(awsize),
    .biu_pad_awvalid(awvalid), .pad_biu_awready(awready),
    .pad_biu_bid(bid_q), .pad_biu_bresp(2'b00),
    .pad_biu_bvalid(bvalid_q), .biu_pad_bready(bready),
    .biu_pad_wdata(wdata), .biu_pad_wlast(wlast),
    .biu_pad_wstrb(wstrb), .biu_pad_wvalid(wvalid),
    .pad_biu_wready(wready), .halted(halted), .illegal(illegal),
    .debug_x31(debug_x31), .cycle_count(cycle_count),
    .instret_count(instret_count)
  );

  always @(posedge clk) begin
    if (arvalid && arready) begin
      if (arburst != 2'b01 || arsize != 3'd4 || arcache != 0 || arlock ||
          arprot != 0 || (arid == 8'hf1 && arlen != 0) ||
          (arid == 8'hd1 && arlen != 3))
        $fatal(1, "invalid lite AXI read attributes");
      rdata_q <= read128(araddr);
      rid_q <= arid;
      rlast_q <= arlen == 0;
      rvalid_q <= 1'b1;
      raddr_q <= araddr + 40'd16;
      rbeats_left_q <= arlen;
      if (arid == 8'hf1) icache_reads <= icache_reads + 1;
      else if (arid == 8'hd1) dcache_reads <= dcache_reads + 1;
      else $fatal(1, "unexpected lite AXI read ID=%h", arid);
    end else if (rvalid_q && rready) begin
      if (rbeats_left_q != 0) begin
        rdata_q <= read128(raddr_q);
        raddr_q <= raddr_q + 40'd16;
        rbeats_left_q <= rbeats_left_q - 1'b1;
        rlast_q <= rbeats_left_q == 1;
      end else begin
        rvalid_q <= 1'b0;
        rlast_q <= 1'b0;
      end
    end

    if (awvalid && awready) begin
      if (awburst != 2'b01 || awsize != 3'd4 || awlen != 0 ||
          awid != 8'hc1 || awcache != 0 || awlock || awprot != 0)
        $fatal(1, "invalid lite AXI write attributes");
      aw_pending_q <= 1'b1;
      awaddr_q <= awaddr;
      awid_q <= awid;
    end
    if (wvalid && wready) begin
      if (!wlast) $fatal(1, "lite dirty writeback must be one AXI beat");
      for (byte_i = 0; byte_i < 16; byte_i = byte_i + 1)
        if (wstrb[byte_i])
          mem[awaddr_q[19:3] + (byte_i >= 8)]
             [(byte_i % 8) * 8 +: 8] <= wdata[byte_i * 8 +: 8];
      aw_pending_q <= 1'b0;
      bvalid_q <= 1'b1;
      bid_q <= awid_q;
    end
    if (bvalid_q && bready) begin
      bvalid_q <= 1'b0;
      write_responses <= write_responses + 1;
    end
  end

  initial begin
    rdata_q = 0; rid_q = 0; rlast_q = 0; rresp_q = 0; rvalid_q = 0;
    raddr_q = 0; rbeats_left_q = 0; aw_pending_q = 0; awaddr_q = 0;
    awid_q = 0; bvalid_q = 0; bid_q = 0; icache_reads = 0;
    dcache_reads = 0; write_responses = 0;
    for (i = 0; i < MEM_WORDS; i = i + 1) mem[i] = 64'd0;
    if (!$value$plusargs("mem64=%s", mem64_file))
      $fatal(1, "pass +mem64=<coremark_bench.data64.memh>");
    $readmemh(mem64_file, mem);

    repeat (4) @(posedge clk);
    reset_n <= 1'b1;
    cycles = 0;
    while (!halted && cycles < TIMEOUT_CYCLES) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    if (!halted) $fatal(1, "AXI CoreMark timeout instret=%0d", instret_count);
    if (illegal) $fatal(1, "AXI CoreMark reported illegal instruction");
    if (debug_x31 == 0) $fatal(1, "AXI CoreMark returned zero");
    if (instret_count != 64'd616228)
      $fatal(1, "AXI CoreMark instret mismatch=%0d", instret_count);
    if (icache_reads == 0 || dcache_reads == 0)
      $fatal(1, "AXI CoreMark did not use both cache read IDs");
    $display("PASS: AXI edge-rv-lite CoreMark x31=%0d cycles=%0d instret=%0d I$AR=%0d D$AR=%0d B=%0d",
             debug_x31, cycle_count, instret_count, icache_reads,
             dcache_reads, write_responses);
    $finish;
  end
endmodule
