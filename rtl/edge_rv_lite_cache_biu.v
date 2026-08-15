`timescale 1ns/1ps

// Serial cache-to-AXI bridge for edge-rv-lite. One read burst and one dirty
// writeback beat may be in flight independently; no transaction IDs are kept
// inside the scalar core.
module edge_rv_lite_cache_biu #(
  parameter ADDR_WIDTH = 40,
  parameter DATA_WIDTH = 128,
  parameter ID_WIDTH = 8,
  parameter LEN_WIDTH = 8
) (
  input  wire                       clk,
  input  wire                       reset_n,

  input  wire                       icache_req_valid,
  output wire                       icache_req_ready,
  input  wire [ADDR_WIDTH-1:0]      icache_req_addr,
  output wire                       icache_resp_valid,
  input  wire                       icache_resp_ready,
  output wire [DATA_WIDTH-1:0]      icache_resp_data,
  output wire                       icache_resp_error,

  input  wire                       dcache_refill_req_valid,
  output wire                       dcache_refill_req_ready,
  input  wire [63:0]                dcache_refill_req_addr,
  output wire                       dcache_refill_resp_valid,
  input  wire                       dcache_refill_resp_ready,
  output wire [DATA_WIDTH-1:0]      dcache_refill_resp_data,
  output wire                       dcache_refill_resp_last,
  output wire                       dcache_refill_resp_error,

  input  wire                       dcache_wb_valid,
  output wire                       dcache_wb_ready,
  input  wire [63:0]                dcache_wb_addr,
  input  wire [DATA_WIDTH-1:0]      dcache_wb_data,
  input  wire                       dcache_wb_last,
  output wire                       dcache_wb_complete,
  output wire                       dcache_wb_error,

  output wire [ADDR_WIDTH-1:0]      axi_araddr,
  output wire [1:0]                 axi_arburst,
  output wire [3:0]                 axi_arcache,
  output wire [ID_WIDTH-1:0]        axi_arid,
  output wire [LEN_WIDTH-1:0]       axi_arlen,
  output wire                       axi_arlock,
  output wire [2:0]                 axi_arprot,
  output wire [2:0]                 axi_arsize,
  output wire                       axi_arvalid,
  input  wire                       axi_arready,
  input  wire [DATA_WIDTH-1:0]      axi_rdata,
  input  wire [ID_WIDTH-1:0]        axi_rid,
  input  wire                       axi_rlast,
  input  wire [1:0]                 axi_rresp,
  input  wire                       axi_rvalid,
  output wire                       axi_rready,

  output wire [ADDR_WIDTH-1:0]      axi_awaddr,
  output wire [1:0]                 axi_awburst,
  output wire [3:0]                 axi_awcache,
  output wire [ID_WIDTH-1:0]        axi_awid,
  output wire [LEN_WIDTH-1:0]       axi_awlen,
  output wire                       axi_awlock,
  output wire [2:0]                 axi_awprot,
  output wire [2:0]                 axi_awsize,
  output wire                       axi_awvalid,
  input  wire                       axi_awready,
  input  wire [ID_WIDTH-1:0]        axi_bid,
  input  wire [1:0]                 axi_bresp,
  input  wire                       axi_bvalid,
  output wire                       axi_bready,
  output wire [DATA_WIDTH-1:0]      axi_wdata,
  output wire                       axi_wlast,
  output wire [(DATA_WIDTH/8)-1:0]  axi_wstrb,
  output wire                       axi_wvalid,
  input  wire                       axi_wready
);
  localparam OWNER_ICACHE = 1'b0;
  localparam OWNER_DCACHE = 1'b1;
  localparam [ID_WIDTH-1:0] ICACHE_AXI_ID = 8'hf1;
  localparam [ID_WIDTH-1:0] DCACHE_AXI_ID = 8'hd1;
  localparam [ID_WIDTH-1:0] WRITEBACK_AXI_ID = 8'hc1;

  reg icache_buf_valid_q;
  reg [ADDR_WIDTH-1:0] icache_buf_addr_q;
  reg read_active_q;
  reg read_owner_q;
  reg [LEN_WIDTH-1:0] read_len_q;
  reg [LEN_WIDTH-1:0] read_beat_q;

  reg wb_valid_q;
  reg wb_aw_sent_q;
  reg wb_w_sent_q;
  reg [ADDR_WIDTH-1:0] wb_addr_q;
  reg [DATA_WIDTH-1:0] wb_data_q;
  reg wb_last_q;

  wire read_idle = !read_active_q;
  // D-cache has priority because its MSHR blocks the scalar pipeline. The
  // one-entry I-cache buffer keeps a simultaneous fetch request lossless.
  wire grant_dcache = read_idle && dcache_refill_req_valid;
  wire grant_icache = read_idle && !grant_dcache && icache_buf_valid_q;
  wire ar_fire = axi_arvalid && axi_arready;
  wire r_fire = axi_rvalid && axi_rready;
  wire wb_accept = dcache_wb_valid && dcache_wb_ready;
  wire wb_b_fire = axi_bvalid && axi_bready;
  wire [ID_WIDTH-1:0] read_expected_id =
    read_owner_q == OWNER_DCACHE ? DCACHE_AXI_ID : ICACHE_AXI_ID;
  wire read_expected_last = read_beat_q == read_len_q;
  wire read_response_error = (axi_rid != read_expected_id) ||
                             |axi_rresp ||
                             (axi_rlast != read_expected_last);
  wire read_terminal = axi_rlast || read_expected_last;
  wire wb_response_error = (axi_bid != WRITEBACK_AXI_ID) || |axi_bresp;

  assign icache_req_ready = !icache_buf_valid_q;
  assign dcache_refill_req_ready = grant_dcache && axi_arready;

  assign axi_arvalid = grant_dcache || grant_icache;
  assign axi_araddr = grant_dcache ?
    dcache_refill_req_addr[ADDR_WIDTH-1:0] : icache_buf_addr_q;
  assign axi_arburst = 2'b01;
  assign axi_arcache = 4'h0;
  assign axi_arid = grant_dcache ? DCACHE_AXI_ID : ICACHE_AXI_ID;
  assign axi_arlen = grant_dcache ?
    {{(LEN_WIDTH-2){1'b0}}, 2'b11} : {LEN_WIDTH{1'b0}};
  assign axi_arlock = 1'b0;
  assign axi_arprot = 3'b000;
  assign axi_arsize = 3'b100;

  assign icache_resp_valid = read_active_q &&
                             (read_owner_q == OWNER_ICACHE) && axi_rvalid;
  assign icache_resp_data = axi_rdata;
  assign icache_resp_error = icache_resp_valid && read_response_error;
  assign dcache_refill_resp_valid = read_active_q &&
                                    (read_owner_q == OWNER_DCACHE) && axi_rvalid;
  assign dcache_refill_resp_data = axi_rdata;
  assign dcache_refill_resp_last = dcache_refill_resp_valid && read_terminal;
  assign dcache_refill_resp_error = dcache_refill_resp_valid &&
                                    read_response_error;
  assign axi_rready = read_active_q &&
    ((read_owner_q == OWNER_DCACHE) ? dcache_refill_resp_ready :
                                     icache_resp_ready);

  assign dcache_wb_ready = !wb_valid_q;
  assign axi_awaddr = wb_addr_q;
  assign axi_awburst = 2'b01;
  assign axi_awcache = 4'h0;
  assign axi_awid = WRITEBACK_AXI_ID;
  assign axi_awlen = {LEN_WIDTH{1'b0}};
  assign axi_awlock = 1'b0;
  assign axi_awprot = 3'b000;
  assign axi_awsize = 3'b100;
  assign axi_awvalid = wb_valid_q && !wb_aw_sent_q;
  assign axi_wdata = wb_data_q;
  assign axi_wlast = 1'b1;
  assign axi_wstrb = {(DATA_WIDTH/8){1'b1}};
  assign axi_wvalid = wb_valid_q && !wb_w_sent_q;
  assign axi_bready = wb_valid_q && wb_aw_sent_q && wb_w_sent_q;
  assign dcache_wb_complete = wb_b_fire && wb_last_q && !wb_response_error;
  assign dcache_wb_error = wb_b_fire && wb_response_error;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      icache_buf_valid_q <= 1'b0;
      icache_buf_addr_q <= {ADDR_WIDTH{1'b0}};
      read_active_q <= 1'b0;
      read_owner_q <= OWNER_ICACHE;
      read_len_q <= {LEN_WIDTH{1'b0}};
      read_beat_q <= {LEN_WIDTH{1'b0}};
    end else begin
      if (icache_req_valid && icache_req_ready) begin
        icache_buf_valid_q <= 1'b1;
        icache_buf_addr_q <= icache_req_addr;
      end
      if (ar_fire) begin
        read_active_q <= 1'b1;
        read_owner_q <= grant_dcache ? OWNER_DCACHE : OWNER_ICACHE;
        read_len_q <= axi_arlen;
        read_beat_q <= {LEN_WIDTH{1'b0}};
        if (grant_icache) icache_buf_valid_q <= 1'b0;
      end
      if (r_fire) begin
        if (read_terminal) begin
          read_active_q <= 1'b0;
        end else begin
          read_beat_q <= read_beat_q + {{(LEN_WIDTH-1){1'b0}}, 1'b1};
        end
      end
    end
  end

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      wb_valid_q <= 1'b0;
      wb_aw_sent_q <= 1'b0;
      wb_w_sent_q <= 1'b0;
      wb_addr_q <= {ADDR_WIDTH{1'b0}};
      wb_data_q <= {DATA_WIDTH{1'b0}};
      wb_last_q <= 1'b0;
    end else begin
      if (wb_accept) begin
        wb_valid_q <= 1'b1;
        wb_aw_sent_q <= 1'b0;
        wb_w_sent_q <= 1'b0;
        wb_addr_q <= dcache_wb_addr[ADDR_WIDTH-1:0];
        wb_data_q <= dcache_wb_data;
        wb_last_q <= dcache_wb_last;
      end
      if (axi_awvalid && axi_awready) wb_aw_sent_q <= 1'b1;
      if (axi_wvalid && axi_wready) wb_w_sent_q <= 1'b1;
      if (wb_b_fire) begin
        wb_aw_sent_q <= 1'b0;
        wb_w_sent_q <= 1'b0;
        if (!wb_response_error) wb_valid_q <= 1'b0;
      end
    end
  end

  initial begin
    if (DATA_WIDTH != 128) $error("lite cache BIU requires 128-bit AXI");
    if (LEN_WIDTH < 2) $error("lite cache BIU requires AXI LEN width >= 2");
  end
endmodule
