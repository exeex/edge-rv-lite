`timescale 1ns/1ps

// Bootable lite scalar core composed with the maintained Edge I/D caches.
// The exposed refill/writeback ports are the cache-to-BIU boundary used by the
// later edge_core_top-compatible wrapper.
module edge_rv_lite_cached_core #(
  parameter PC_WIDTH = 40,
  parameter ICACHE_BYTES = 16384,
  parameter DCACHE_BYTES = 16384,
  parameter DTCM_ADDR_WIDTH = 14,
  parameter ENABLE_DTCM_PORT = 0,
  parameter [46:0] EDGE_ASIC_ID = 47'd0
) (
  input  wire                   clk,
  input  wire                   reset_n,

  output wire                   imem_refill_req_valid,
  input  wire                   imem_refill_req_ready,
  output wire [PC_WIDTH-1:0]    imem_refill_req_addr,
  input  wire                   imem_refill_resp_valid,
  output wire                   imem_refill_resp_ready,
  input  wire [127:0]           imem_refill_resp_data,

  output wire                   dmem_refill_req_valid,
  input  wire                   dmem_refill_req_ready,
  output wire [63:0]            dmem_refill_req_addr,
  input  wire                   dmem_refill_resp_valid,
  output wire                   dmem_refill_resp_ready,
  input  wire [127:0]           dmem_refill_resp_data,
  input  wire                   dmem_refill_resp_last,
  input  wire                   dmem_refill_resp_error,

  output wire                   dmem_clean_wb_valid,
  input  wire                   dmem_clean_wb_ready,
  output wire [63:0]            dmem_clean_wb_addr,
  output wire [127:0]           dmem_clean_wb_data,
  output wire                   dmem_clean_wb_last,
  input  wire                   dmem_clean_wb_complete,

  input  wire [63:0]            dtcm_base,
  input  wire [63:0]            dtcm_mask,
  input  wire                   dtcm_enable,
  output wire                   dtcm_lsu_req,
  input  wire                   dtcm_lsu_ready,
  output wire                   dtcm_lsu_we,
  output wire [DTCM_ADDR_WIDTH-1:0] dtcm_lsu_addr,
  output wire [63:0]            dtcm_lsu_wdata,
  output wire [7:0]             dtcm_lsu_wstrb,
  input  wire                   dtcm_lsu_rvalid,
  input  wire [63:0]            dtcm_lsu_rdata,

  output wire                   accel_req_valid,
  input  wire                   accel_req_ready,
  output wire [63:0]            accel_req_inst,
  output wire [63:0]            accel_req_src0,
  output wire [63:0]            accel_req_src1,
  input  wire                   accel_resp_valid,
  input  wire                   accel_resp_error,
  input  wire [63:0]            accel_resp_value,

  output wire                   halted,
  output wire                   illegal,
  output wire [63:0]            debug_x31,
  output wire [63:0]            cycle_count,
  output wire [63:0]            instret_count,
  output wire                   debug_icache_hit,
  output wire                   debug_icache_miss_pending,
  output wire                   debug_dcache_load_miss_pending
);
  wire core_imem_req_valid;
  wire core_imem_req_ready;
  wire [PC_WIDTH-1:0] core_imem_req_addr;
  wire core_imem_resp_valid;
  wire [31:0] core_imem_resp_data;
  wire core_imem_resp_error;

  wire core_dmem_req_valid;
  wire core_dmem_req_ready;
  wire core_dmem_req_write;
  wire [63:0] core_dmem_req_addr;
  wire [63:0] core_dmem_req_wdata;
  wire [7:0] core_dmem_req_wstrb;
  wire [1:0] core_dmem_req_size;
  wire core_dmem_req_signed;
  wire core_dmem_resp_valid;
  wire core_dmem_resp_error;
  wire [63:0] core_dmem_resp_rdata;
  wire cache_core_req_valid,cache_core_req_ready,cache_core_req_write;
  wire [63:0] cache_core_req_addr,cache_core_req_wdata;
  wire [7:0] cache_core_req_wstrb;
  wire cache_core_resp_valid,cache_core_resp_error;
  wire [63:0] cache_core_resp_rdata;

  wire icache_req_valid;
  wire icache_req_ready;
  wire [PC_WIDTH-1:0] icache_req_addr;
  wire icache_resp_valid;
  wire icache_resp_ready;
  wire [127:0] icache_resp_bits;

  wire dcache_load_req_valid;
  wire dcache_load_req_ready;
  wire [7:0] dcache_load_req_seq_id;
  wire [3:0] dcache_load_req_epoch;
  wire [63:0] dcache_load_req_addr;
  wire [1:0] dcache_load_req_size;
  wire dcache_load_req_signed;
  wire dcache_load_resp_valid;
  wire dcache_load_resp_error;
  wire [63:0] dcache_load_resp_value;
  wire dcache_store_req_valid;
  wire dcache_store_req_ready;
  wire [7:0] dcache_store_req_seq_id;
  wire [3:0] dcache_store_req_epoch;
  wire [63:0] dcache_store_req_addr;
  wire [1:0] dcache_store_req_size;
  wire [63:0] dcache_store_req_data;
  wire [7:0] dcache_store_req_wstrb;
  wire cache_op_valid,cache_op_ready,cache_op_is_va;
  wire [1:0] cache_op_kind;
  wire [63:0] cache_op_addr;
  wire cache_op_complete_valid;

  edge_rv_lite_core #(
    .PC_WIDTH(PC_WIDTH), .DMEM_RESP_FORMATTED(1),
    .EDGE_ASIC_ID(EDGE_ASIC_ID)
  ) core (
    .clk(clk), .reset_n(reset_n),
    .imem_req_valid(core_imem_req_valid),
    .imem_req_ready(core_imem_req_ready),
    .imem_req_addr(core_imem_req_addr),
    .imem_resp_valid(core_imem_resp_valid),
    .imem_resp_data(core_imem_resp_data),
    .imem_resp_error(core_imem_resp_error),
    .dmem_req_valid(core_dmem_req_valid),
    .dmem_req_ready(core_dmem_req_ready),
    .dmem_req_write(core_dmem_req_write),
    .dmem_req_addr(core_dmem_req_addr),
    .dmem_req_wdata(core_dmem_req_wdata),
    .dmem_req_wstrb(core_dmem_req_wstrb),
    .dmem_req_size(core_dmem_req_size),
    .dmem_req_signed(core_dmem_req_signed),
    .dmem_resp_valid(core_dmem_resp_valid),
    .dmem_resp_error(core_dmem_resp_error),
    .dmem_resp_rdata(core_dmem_resp_rdata),
    .cache_op_valid(cache_op_valid),.cache_op_ready(cache_op_ready),
    .cache_op_is_va(cache_op_is_va),.cache_op_kind(cache_op_kind),
    .cache_op_addr(cache_op_addr),
    .cache_op_complete_valid(cache_op_complete_valid),
    .accel_req_valid(accel_req_valid), .accel_req_ready(accel_req_ready),
    .accel_req_inst(accel_req_inst), .accel_req_src0(accel_req_src0),
    .accel_req_src1(accel_req_src1), .accel_resp_valid(accel_resp_valid),
    .accel_resp_error(accel_resp_error), .accel_resp_value(accel_resp_value),
    .halted(halted), .illegal(illegal), .debug_x31(debug_x31),
    .cycle_count(cycle_count), .instret_count(instret_count)
  );

  edge_rv_lite_icache_adapter #(.PC_WIDTH(PC_WIDTH)) icache_adapter (
    .clk(clk), .reset_n(reset_n),
    .core_req_valid(core_imem_req_valid),
    .core_req_ready(core_imem_req_ready),
    .core_req_addr(core_imem_req_addr),
    .core_resp_valid(core_imem_resp_valid),
    .core_resp_data(core_imem_resp_data),
    .core_resp_error(core_imem_resp_error),
    .cache_req_valid(icache_req_valid),
    .cache_req_ready(icache_req_ready), .cache_req_addr(icache_req_addr),
    .cache_resp_valid(icache_resp_valid),
    .cache_resp_ready(icache_resp_ready), .cache_resp_bits(icache_resp_bits)
  );

  generate if(ENABLE_DTCM_PORT) begin: g_dtcm
    edge_rv_lite_dtcm_router #(.DTCM_ADDR_WIDTH(DTCM_ADDR_WIDTH)) dtcm_router(
      .clk(clk),.reset_n(reset_n),.dtcm_base(dtcm_base),.dtcm_mask(dtcm_mask),
      .dtcm_enable(dtcm_enable),.core_req_valid(core_dmem_req_valid),
      .core_req_ready(core_dmem_req_ready),.core_req_write(core_dmem_req_write),
      .core_req_addr(core_dmem_req_addr),.core_req_wdata(core_dmem_req_wdata),
      .core_req_wstrb(core_dmem_req_wstrb),.core_resp_valid(core_dmem_resp_valid),
      .core_resp_error(core_dmem_resp_error),.core_resp_rdata(core_dmem_resp_rdata),
      .cache_req_valid(cache_core_req_valid),.cache_req_ready(cache_core_req_ready),
      .cache_req_write(cache_core_req_write),.cache_req_addr(cache_core_req_addr),
      .cache_req_wdata(cache_core_req_wdata),.cache_req_wstrb(cache_core_req_wstrb),
      .core_req_size(core_dmem_req_size),.core_req_signed(core_dmem_req_signed),
      .cache_resp_valid(cache_core_resp_valid),.cache_resp_error(cache_core_resp_error),
      .cache_resp_rdata(cache_core_resp_rdata),.dtcm_req(dtcm_lsu_req),
      .dtcm_ready(dtcm_lsu_ready),.dtcm_we(dtcm_lsu_we),.dtcm_addr(dtcm_lsu_addr),
      .dtcm_wdata(dtcm_lsu_wdata),.dtcm_wstrb(dtcm_lsu_wstrb),
      .dtcm_rvalid(dtcm_lsu_rvalid),.dtcm_rdata(dtcm_lsu_rdata));
  end else begin: g_no_dtcm
    assign cache_core_req_valid=core_dmem_req_valid;
    assign core_dmem_req_ready=cache_core_req_ready;
    assign cache_core_req_write=core_dmem_req_write;
    assign cache_core_req_addr=core_dmem_req_addr;
    assign cache_core_req_wdata=core_dmem_req_wdata;
    assign cache_core_req_wstrb=core_dmem_req_wstrb;
    assign core_dmem_resp_valid=cache_core_resp_valid;
    assign core_dmem_resp_error=cache_core_resp_error;
    assign core_dmem_resp_rdata=cache_core_resp_rdata;
    assign dtcm_lsu_req=1'b0; assign dtcm_lsu_we=1'b0;
    assign dtcm_lsu_addr={DTCM_ADDR_WIDTH{1'b0}};
    assign dtcm_lsu_wdata=64'b0;
    assign dtcm_lsu_wstrb=8'b0;
  end endgenerate

  edge_ifu_icache #(
    .PC_WIDTH(PC_WIDTH), .ICACHE_BYTES(ICACHE_BYTES), .LINE_BYTES(16)
  ) icache (
    .forever_cpuclk(clk), .cpurst_b(reset_n),
    .fetch_req_valid(icache_req_valid), .fetch_req_ready(icache_req_ready),
    .fetch_req_addr(icache_req_addr),
    .invalidate_valid(1'b0), .invalidate_ready(),
    .fetch_resp_valid(icache_resp_valid),
    .fetch_resp_ready(icache_resp_ready), .fetch_resp_bits(icache_resp_bits),
    .imem_req_valid(imem_refill_req_valid),
    .imem_req_ready(imem_refill_req_ready),
    .imem_req_addr(imem_refill_req_addr),
    .imem_resp_valid(imem_refill_resp_valid),
    .imem_resp_ready(imem_refill_resp_ready),
    .imem_resp_bits(imem_refill_resp_data),
    .debug_icache_bytes(), .debug_hit(debug_icache_hit),
    .debug_miss_pending(debug_icache_miss_pending),
    .debug_invalidate_busy()
  );

  edge_rv_lite_dcache_adapter dcache_adapter (
    .clk(clk), .reset_n(reset_n),
    .core_req_valid(cache_core_req_valid),
    .core_req_ready(cache_core_req_ready),
    .core_req_write(cache_core_req_write),
    .core_req_addr(cache_core_req_addr),
    .core_req_wdata(cache_core_req_wdata),
    .core_req_wstrb(cache_core_req_wstrb),
    .core_req_size(core_dmem_req_size),
    .core_req_signed(core_dmem_req_signed),
    .core_resp_valid(cache_core_resp_valid),
    .core_resp_error(cache_core_resp_error),
    .core_resp_rdata(cache_core_resp_rdata),
    .cache_load_req_valid(dcache_load_req_valid),
    .cache_load_req_ready(dcache_load_req_ready),
    .cache_load_req_seq_id(dcache_load_req_seq_id),
    .cache_load_req_epoch(dcache_load_req_epoch),
    .cache_load_req_addr(dcache_load_req_addr),
    .cache_load_req_size(dcache_load_req_size),
    .cache_load_req_signed(dcache_load_req_signed),
    .cache_load_resp_valid(dcache_load_resp_valid),
    .cache_load_resp_error(dcache_load_resp_error),
    .cache_load_resp_value(dcache_load_resp_value),
    .cache_store_req_valid(dcache_store_req_valid),
    .cache_store_req_ready(dcache_store_req_ready),
    .cache_store_req_seq_id(dcache_store_req_seq_id),
    .cache_store_req_epoch(dcache_store_req_epoch),
    .cache_store_req_addr(dcache_store_req_addr),
    .cache_store_req_size(dcache_store_req_size),
    .cache_store_req_data(dcache_store_req_data),
    .cache_store_req_wstrb(dcache_store_req_wstrb)
  );

  edge_dcache #(
    .SEQ_ID_WIDTH(8), .EPOCH_WIDTH(4), .VALUE_WIDTH(64),
    .ICACHE_BYTES(ICACHE_BYTES), .DCACHE_BYTES(DCACHE_BYTES)
  ) dcache (
    .forever_cpuclk(clk), .cpurst_b(reset_n),
    .redirect_kill_valid(1'b0), .redirect_kill_seq_id(8'd0),
    .redirect_kill_epoch(4'd0),
    .backend_load_pause(1'b0), .backend_store_pause(1'b0),
    .lsu_load_req_valid(dcache_load_req_valid),
    .lsu_load_req_ready(dcache_load_req_ready),
    .lsu_load_req_seq_id(dcache_load_req_seq_id),
    .lsu_load_req_epoch(dcache_load_req_epoch),
    .lsu_load_req_addr(dcache_load_req_addr),
    .lsu_load_req_size(dcache_load_req_size),
    .lsu_load_req_signed(dcache_load_req_signed),
    .lsu_load_req1_valid(1'b0), .lsu_load_req1_ready(),
    .lsu_load_req1_seq_id(8'd0), .lsu_load_req1_epoch(4'd0),
    .lsu_load_req1_addr(64'd0), .lsu_load_req1_size(2'd0),
    .lsu_load_req1_signed(1'b0),
    .lsu_load_resp_valid(dcache_load_resp_valid),
    .lsu_load_resp_seq_id(), .lsu_load_resp_epoch(),
    .lsu_load_resp_error(dcache_load_resp_error),
    .lsu_load_resp_value(dcache_load_resp_value),
    .lsu_store_req_valid(dcache_store_req_valid),
    .lsu_store_req_ready(dcache_store_req_ready),
    .lsu_store_req_seq_id(dcache_store_req_seq_id),
    .lsu_store_req_epoch(dcache_store_req_epoch),
    .lsu_store_req_addr(dcache_store_req_addr),
    .lsu_store_req_size(dcache_store_req_size),
    .lsu_store_req_data(dcache_store_req_data),
    .lsu_store_req_wstrb(dcache_store_req_wstrb),
    .lsu_store_req1_valid(1'b0), .lsu_store_req1_ready(),
    .lsu_store_req1_seq_id(8'd0), .lsu_store_req1_epoch(4'd0),
    .lsu_store_req1_addr(64'd0), .lsu_store_req1_size(2'd0),
    .lsu_store_req1_data(64'd0), .lsu_store_req1_wstrb(8'd0),
    .cache_op_valid(cache_op_valid), .cache_op_ready(cache_op_ready),
    .cache_op_is_va(cache_op_is_va),
    .cache_op_kind(cache_op_kind), .cache_op_addr(cache_op_addr),
    .cache_op_seq_id(8'd0), .cache_op_epoch(4'd0),
    .cache_op_complete_valid(cache_op_complete_valid), .cache_op_complete_seq_id(),
    .cache_op_complete_epoch(),
    .clean_wb_valid(dmem_clean_wb_valid),
    .clean_wb_ready(dmem_clean_wb_ready),
    .clean_wb_addr(dmem_clean_wb_addr), .clean_wb_data(dmem_clean_wb_data),
    .clean_wb_last(dmem_clean_wb_last),
    .clean_wb_complete(dmem_clean_wb_complete),
    .refill_req_valid(dmem_refill_req_valid),
    .refill_req_ready(dmem_refill_req_ready),
    .refill_req_addr(dmem_refill_req_addr),
    .refill_resp_valid(dmem_refill_resp_valid),
    .refill_resp_ready(dmem_refill_resp_ready),
    .refill_resp_data(dmem_refill_resp_data),
    .refill_resp_last(dmem_refill_resp_last),
    .refill_resp_error(dmem_refill_resp_error),
    .debug_icache_bytes(), .debug_dcache_bytes(), .debug_load_pending(),
    .debug_load_miss_pending(debug_dcache_load_miss_pending),
    .debug_store_fire(), .store_predict_phase(),
    .store_predict_mem_active(), .store_predict_backend_blocked(),
    .debug_cache_op_fire(), .debug_cache_op_kind(),
    .debug_cache_op_is_va()
  );
endmodule
