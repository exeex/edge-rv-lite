`timescale 1ns/1ps

// Bootable edge-rv-lite cache hierarchy with the Edge 128-bit AXI boundary.
module edge_rv_lite_axi_core #(
  parameter PC_WIDTH = 40,
  parameter AXI_DATA_WIDTH = 128,
  parameter AXI_ID_WIDTH = 8,
  parameter AXI_LEN_WIDTH = 8,
  parameter ICACHE_BYTES = 16384,
  parameter DCACHE_BYTES = 16384,
  parameter DTCM_ADDR_WIDTH = 14,
  parameter ENABLE_DTCM_PORT = 0,
  parameter ENABLE_FPU = 0,
  parameter [46:0] EDGE_ASIC_ID = 47'd0
) (
  input  wire                         forever_cpuclk,
  input  wire                         cpurst_b,

  output wire [PC_WIDTH-1:0]          biu_pad_araddr,
  output wire [1:0]                   biu_pad_arburst,
  output wire [3:0]                   biu_pad_arcache,
  output wire [AXI_ID_WIDTH-1:0]      biu_pad_arid,
  output wire [AXI_LEN_WIDTH-1:0]     biu_pad_arlen,
  output wire                         biu_pad_arlock,
  output wire [2:0]                   biu_pad_arprot,
  output wire [2:0]                   biu_pad_arsize,
  output wire                         biu_pad_arvalid,
  input  wire                         pad_biu_arready,
  input  wire [AXI_DATA_WIDTH-1:0]    pad_biu_rdata,
  input  wire [AXI_ID_WIDTH-1:0]      pad_biu_rid,
  input  wire                         pad_biu_rlast,
  input  wire [1:0]                   pad_biu_rresp,
  input  wire                         pad_biu_rvalid,
  output wire                         biu_pad_rready,

  output wire [PC_WIDTH-1:0]          biu_pad_awaddr,
  output wire [1:0]                   biu_pad_awburst,
  output wire [3:0]                   biu_pad_awcache,
  output wire [AXI_ID_WIDTH-1:0]      biu_pad_awid,
  output wire [AXI_LEN_WIDTH-1:0]     biu_pad_awlen,
  output wire                         biu_pad_awlock,
  output wire [2:0]                   biu_pad_awprot,
  output wire [2:0]                   biu_pad_awsize,
  output wire                         biu_pad_awvalid,
  input  wire                         pad_biu_awready,
  input  wire [AXI_ID_WIDTH-1:0]      pad_biu_bid,
  input  wire [1:0]                   pad_biu_bresp,
  input  wire                         pad_biu_bvalid,
  output wire                         biu_pad_bready,
  output wire [AXI_DATA_WIDTH-1:0]    biu_pad_wdata,
  output wire                         biu_pad_wlast,
  output wire [(AXI_DATA_WIDTH/8)-1:0] biu_pad_wstrb,
  output wire                         biu_pad_wvalid,
  input  wire                         pad_biu_wready,

  input  wire [63:0]                  dtcm_base,
  input  wire [63:0]                  dtcm_mask,
  input  wire                         dtcm_enable,
  output wire                         dtcm_lsu_req,
  input  wire                         dtcm_lsu_ready,
  output wire                         dtcm_lsu_we,
  output wire [DTCM_ADDR_WIDTH-1:0]   dtcm_lsu_addr,
  output wire [63:0]                  dtcm_lsu_wdata,
  output wire [7:0]                   dtcm_lsu_wstrb,
  input  wire                         dtcm_lsu_rvalid,
  input  wire [63:0]                  dtcm_lsu_rdata,

  output wire                         accel_req_valid,
  input  wire                         accel_req_ready,
  output wire [63:0]                  accel_req_inst,
  output wire [63:0]                  accel_req_src0,
  output wire [63:0]                  accel_req_src1,
  input  wire                         accel_resp_valid,
  input  wire                         accel_resp_error,
  input  wire [63:0]                  accel_resp_value,

  output wire                         halted,
  output wire                         illegal,
  output wire [63:0]                  debug_x31,
  output wire [63:0]                  cycle_count,
  output wire [63:0]                  instret_count
);
  wire imem_refill_req_valid;
  wire imem_refill_req_ready;
  wire [PC_WIDTH-1:0] imem_refill_req_addr;
  wire imem_refill_resp_valid;
  wire imem_refill_resp_ready;
  wire [127:0] imem_refill_resp_data;
  wire imem_refill_resp_error;
  wire dmem_refill_req_valid;
  wire dmem_refill_req_ready;
  wire [63:0] dmem_refill_req_addr;
  wire dmem_refill_resp_valid;
  wire dmem_refill_resp_ready;
  wire [127:0] dmem_refill_resp_data;
  wire dmem_refill_resp_last;
  wire dmem_refill_resp_error;
  wire dmem_clean_wb_valid;
  wire dmem_clean_wb_ready;
  wire [63:0] dmem_clean_wb_addr;
  wire [127:0] dmem_clean_wb_data;
  wire dmem_clean_wb_last;
  wire dmem_clean_wb_complete;

  edge_rv_lite_cached_core #(
    .PC_WIDTH(PC_WIDTH), .ICACHE_BYTES(ICACHE_BYTES),
    .DCACHE_BYTES(DCACHE_BYTES),.DTCM_ADDR_WIDTH(DTCM_ADDR_WIDTH),
    .ENABLE_DTCM_PORT(ENABLE_DTCM_PORT),.ENABLE_FPU(ENABLE_FPU),
    .EDGE_ASIC_ID(EDGE_ASIC_ID)
  ) cached_core (
    .clk(forever_cpuclk), .reset_n(cpurst_b),
    .imem_refill_req_valid(imem_refill_req_valid),
    .imem_refill_req_ready(imem_refill_req_ready),
    .imem_refill_req_addr(imem_refill_req_addr),
    .imem_refill_resp_valid(imem_refill_resp_valid),
    .imem_refill_resp_ready(imem_refill_resp_ready),
    .imem_refill_resp_data(imem_refill_resp_data),
    .imem_refill_resp_error(imem_refill_resp_error),
    .dmem_refill_req_valid(dmem_refill_req_valid),
    .dmem_refill_req_ready(dmem_refill_req_ready),
    .dmem_refill_req_addr(dmem_refill_req_addr),
    .dmem_refill_resp_valid(dmem_refill_resp_valid),
    .dmem_refill_resp_ready(dmem_refill_resp_ready),
    .dmem_refill_resp_data(dmem_refill_resp_data),
    .dmem_refill_resp_last(dmem_refill_resp_last),
    .dmem_refill_resp_error(dmem_refill_resp_error),
    .dmem_clean_wb_valid(dmem_clean_wb_valid),
    .dmem_clean_wb_ready(dmem_clean_wb_ready),
    .dmem_clean_wb_addr(dmem_clean_wb_addr),
    .dmem_clean_wb_data(dmem_clean_wb_data),
    .dmem_clean_wb_last(dmem_clean_wb_last),
    .dmem_clean_wb_complete(dmem_clean_wb_complete),
    .dtcm_base(dtcm_base),.dtcm_mask(dtcm_mask),.dtcm_enable(dtcm_enable),
    .dtcm_lsu_req(dtcm_lsu_req),.dtcm_lsu_ready(dtcm_lsu_ready),
    .dtcm_lsu_we(dtcm_lsu_we),.dtcm_lsu_addr(dtcm_lsu_addr),
    .dtcm_lsu_wdata(dtcm_lsu_wdata),.dtcm_lsu_wstrb(dtcm_lsu_wstrb),
    .dtcm_lsu_rvalid(dtcm_lsu_rvalid),.dtcm_lsu_rdata(dtcm_lsu_rdata),
    .accel_req_valid(accel_req_valid), .accel_req_ready(accel_req_ready),
    .accel_req_inst(accel_req_inst), .accel_req_src0(accel_req_src0),
    .accel_req_src1(accel_req_src1), .accel_resp_valid(accel_resp_valid),
    .accel_resp_error(accel_resp_error), .accel_resp_value(accel_resp_value),
    .halted(halted), .illegal(illegal), .debug_x31(debug_x31),
    .cycle_count(cycle_count), .instret_count(instret_count),
    .debug_icache_hit(), .debug_icache_miss_pending(),
    .debug_dcache_load_miss_pending()
  );

  edge_rv_lite_cache_biu #(
    .ADDR_WIDTH(PC_WIDTH), .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH(AXI_ID_WIDTH), .LEN_WIDTH(AXI_LEN_WIDTH)
  ) cache_biu (
    .clk(forever_cpuclk), .reset_n(cpurst_b),
    .icache_req_valid(imem_refill_req_valid),
    .icache_req_ready(imem_refill_req_ready),
    .icache_req_addr(imem_refill_req_addr),
    .icache_resp_valid(imem_refill_resp_valid),
    .icache_resp_ready(imem_refill_resp_ready),
    .icache_resp_data(imem_refill_resp_data),
    .icache_resp_error(imem_refill_resp_error),
    .dcache_refill_req_valid(dmem_refill_req_valid),
    .dcache_refill_req_ready(dmem_refill_req_ready),
    .dcache_refill_req_addr(dmem_refill_req_addr),
    .dcache_refill_resp_valid(dmem_refill_resp_valid),
    .dcache_refill_resp_ready(dmem_refill_resp_ready),
    .dcache_refill_resp_data(dmem_refill_resp_data),
    .dcache_refill_resp_last(dmem_refill_resp_last),
    .dcache_refill_resp_error(dmem_refill_resp_error),
    .dcache_wb_valid(dmem_clean_wb_valid),
    .dcache_wb_ready(dmem_clean_wb_ready),
    .dcache_wb_addr(dmem_clean_wb_addr),
    .dcache_wb_data(dmem_clean_wb_data),
    .dcache_wb_last(dmem_clean_wb_last),
    .dcache_wb_complete(dmem_clean_wb_complete),
    .dcache_wb_error(),
    .axi_araddr(biu_pad_araddr), .axi_arburst(biu_pad_arburst),
    .axi_arcache(biu_pad_arcache), .axi_arid(biu_pad_arid),
    .axi_arlen(biu_pad_arlen), .axi_arlock(biu_pad_arlock),
    .axi_arprot(biu_pad_arprot), .axi_arsize(biu_pad_arsize),
    .axi_arvalid(biu_pad_arvalid), .axi_arready(pad_biu_arready),
    .axi_rdata(pad_biu_rdata), .axi_rid(pad_biu_rid),
    .axi_rlast(pad_biu_rlast), .axi_rresp(pad_biu_rresp),
    .axi_rvalid(pad_biu_rvalid), .axi_rready(biu_pad_rready),
    .axi_awaddr(biu_pad_awaddr), .axi_awburst(biu_pad_awburst),
    .axi_awcache(biu_pad_awcache), .axi_awid(biu_pad_awid),
    .axi_awlen(biu_pad_awlen), .axi_awlock(biu_pad_awlock),
    .axi_awprot(biu_pad_awprot), .axi_awsize(biu_pad_awsize),
    .axi_awvalid(biu_pad_awvalid), .axi_awready(pad_biu_awready),
    .axi_bid(pad_biu_bid), .axi_bresp(pad_biu_bresp),
    .axi_bvalid(pad_biu_bvalid), .axi_bready(biu_pad_bready),
    .axi_wdata(biu_pad_wdata), .axi_wlast(biu_pad_wlast),
    .axi_wstrb(biu_pad_wstrb), .axi_wvalid(biu_pad_wvalid),
    .axi_wready(pad_biu_wready)
  );

  initial begin
    if (AXI_DATA_WIDTH != 128) $error("edge-rv-lite requires 128-bit AXI");
  end
endmodule
