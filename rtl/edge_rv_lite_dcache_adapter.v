`timescale 1ns/1ps

// Serial lane0 adapter between the lite LSU and the maintained Edge D-cache.
// No sequence/epoch identity is required because only one operation may exist.
module edge_rv_lite_dcache_adapter #(
  parameter VALUE_WIDTH = 64,
  parameter SEQ_ID_WIDTH = 8,
  parameter EPOCH_WIDTH = 4
) (
  input  wire                       clk,
  input  wire                       reset_n,

  input  wire                       core_req_valid,
  output wire                       core_req_ready,
  input  wire                       core_req_write,
  input  wire [VALUE_WIDTH-1:0]     core_req_addr,
  input  wire [VALUE_WIDTH-1:0]     core_req_wdata,
  input  wire [(VALUE_WIDTH/8)-1:0] core_req_wstrb,
  input  wire [1:0]                 core_req_size,
  input  wire                       core_req_signed,
  output wire                       core_resp_valid,
  output wire                       core_resp_error,
  output wire [VALUE_WIDTH-1:0]     core_resp_rdata,

  output wire                       cache_load_req_valid,
  input  wire                       cache_load_req_ready,
  output wire [SEQ_ID_WIDTH-1:0]    cache_load_req_seq_id,
  output wire [EPOCH_WIDTH-1:0]     cache_load_req_epoch,
  output wire [VALUE_WIDTH-1:0]     cache_load_req_addr,
  output wire [1:0]                 cache_load_req_size,
  output wire                       cache_load_req_signed,
  input  wire                       cache_load_resp_valid,
  input  wire                       cache_load_resp_error,
  input  wire [VALUE_WIDTH-1:0]     cache_load_resp_value,

  output wire                       cache_store_req_valid,
  input  wire                       cache_store_req_ready,
  output wire [SEQ_ID_WIDTH-1:0]    cache_store_req_seq_id,
  output wire [EPOCH_WIDTH-1:0]     cache_store_req_epoch,
  output wire [VALUE_WIDTH-1:0]     cache_store_req_addr,
  output wire [1:0]                 cache_store_req_size,
  output wire [VALUE_WIDTH-1:0]     cache_store_req_data,
  output wire [(VALUE_WIDTH/8)-1:0] cache_store_req_wstrb
);
  reg store_done_q;
  wire store_fire = cache_store_req_valid && cache_store_req_ready;

  assign cache_load_req_valid = core_req_valid && !core_req_write;
  assign cache_store_req_valid = core_req_valid && core_req_write;
  assign core_req_ready = core_req_write ? cache_store_req_ready :
                                           cache_load_req_ready;

  assign cache_load_req_seq_id = {SEQ_ID_WIDTH{1'b0}};
  assign cache_load_req_epoch = {EPOCH_WIDTH{1'b0}};
  assign cache_load_req_addr = core_req_addr;
  assign cache_load_req_size = core_req_size;
  assign cache_load_req_signed = core_req_signed;

  assign cache_store_req_seq_id = {SEQ_ID_WIDTH{1'b0}};
  assign cache_store_req_epoch = {EPOCH_WIDTH{1'b0}};
  assign cache_store_req_addr = core_req_addr;
  assign cache_store_req_size = core_req_size;
  assign cache_store_req_data = core_req_wdata;
  assign cache_store_req_wstrb = core_req_wstrb;

  assign core_resp_valid = store_done_q || cache_load_resp_valid;
  assign core_resp_error = cache_load_resp_valid && cache_load_resp_error;
  assign core_resp_rdata = cache_load_resp_valid ? cache_load_resp_value :
                                                   {VALUE_WIDTH{1'b0}};

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) store_done_q <= 1'b0;
    else begin
      store_done_q <= store_fire;
    end
  end
endmodule
