`timescale 1ns/1ps
module edge_rv_lite_dtcm_router #(
  parameter ADDR_WIDTH = 64,
  parameter DTCM_ADDR_WIDTH = 14
) (
  input  wire clk, input wire reset_n,
  input  wire [ADDR_WIDTH-1:0] dtcm_base,
  input  wire [ADDR_WIDTH-1:0] dtcm_mask,
  input  wire dtcm_enable,
  input  wire core_req_valid, output wire core_req_ready,
  input  wire core_req_write,
  input  wire [ADDR_WIDTH-1:0] core_req_addr,
  input  wire [63:0] core_req_wdata, input wire [7:0] core_req_wstrb,
  output wire core_resp_valid, output wire core_resp_error,
  output wire [63:0] core_resp_rdata,
  output wire cache_req_valid, input wire cache_req_ready,
  output wire cache_req_write,
  output wire [ADDR_WIDTH-1:0] cache_req_addr,
  output wire [63:0] cache_req_wdata, output wire [7:0] cache_req_wstrb,
  input  wire cache_resp_valid, input wire cache_resp_error,
  input  wire [63:0] cache_resp_rdata,
  output wire dtcm_req, input wire dtcm_ready,
  output wire dtcm_we, output wire [DTCM_ADDR_WIDTH-1:0] dtcm_addr,
  output wire [63:0] dtcm_wdata, output wire [7:0] dtcm_wstrb,
  input  wire dtcm_rvalid, input wire [63:0] dtcm_rdata
);
  localparam OWNER_NONE=2'd0, OWNER_CACHE=2'd1, OWNER_DTCM_LOAD=2'd2;
  reg [1:0] owner_q;
  reg dtcm_store_resp_q;
  wire idle = owner_q==OWNER_NONE && !dtcm_store_resp_q;
  wire hit = dtcm_enable &&
             ((core_req_addr & dtcm_mask)==(dtcm_base & dtcm_mask));
  wire select_dtcm = idle && core_req_valid && hit;
  wire select_cache = idle && core_req_valid && !hit;
  wire dtcm_fire = select_dtcm && dtcm_ready;
  wire cache_fire = select_cache && cache_req_ready;
  wire [ADDR_WIDTH-1:0] dtcm_byte_offset = core_req_addr-dtcm_base;

  assign core_req_ready = idle && (hit ? dtcm_ready:cache_req_ready);
  assign cache_req_valid = select_cache;
  assign cache_req_write = core_req_write;
  assign cache_req_addr = core_req_addr;
  assign cache_req_wdata = core_req_wdata;
  assign cache_req_wstrb = core_req_wstrb;
  assign dtcm_req = select_dtcm;
  assign dtcm_we = core_req_write;
  assign dtcm_addr = dtcm_byte_offset[DTCM_ADDR_WIDTH+2:3];
  assign dtcm_wdata = core_req_wdata;
  assign dtcm_wstrb = core_req_wstrb;
  assign core_resp_valid = dtcm_store_resp_q ||
    ((owner_q==OWNER_DTCM_LOAD) && dtcm_rvalid) ||
    ((owner_q==OWNER_CACHE) && cache_resp_valid);
  assign core_resp_error = (owner_q==OWNER_CACHE) ? cache_resp_error:1'b0;
  assign core_resp_rdata = (owner_q==OWNER_DTCM_LOAD) ? dtcm_rdata:
                           cache_resp_rdata;

  always @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin owner_q<=OWNER_NONE; dtcm_store_resp_q<=1'b0; end
    else begin
      dtcm_store_resp_q<=dtcm_fire&&core_req_write;
      if(cache_fire) owner_q<=OWNER_CACHE;
      else if(dtcm_fire&&!core_req_write) owner_q<=OWNER_DTCM_LOAD;
      else if((owner_q==OWNER_CACHE)&&cache_resp_valid) owner_q<=OWNER_NONE;
      else if((owner_q==OWNER_DTCM_LOAD)&&dtcm_rvalid) owner_q<=OWNER_NONE;
    end
  end
endmodule
