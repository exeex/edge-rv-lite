`timescale 1ns/1ps
// One memory instruction at a time: capture, request, wait for completion.
module edge_rv_lite_lsu #(
  parameter VALUE_WIDTH = 64,
  parameter STORE_ACK_ON_ACCEPT = 0,
  parameter MEM_RESP_FORMATTED = 0
) (
  input  wire                   clk,
  input  wire                   reset_n,
  input  wire                   op_valid,
  output wire                   op_ready,
  input  wire                   op_store,
  input  wire                   op_fp,
  input  wire [2:0]             op_funct3,
  input  wire [VALUE_WIDTH-1:0] op_base,
  input  wire [VALUE_WIDTH-1:0] op_offset,
  input  wire [VALUE_WIDTH-1:0] op_store_data,
  output wire                   mem_req_valid,
  input  wire                   mem_req_ready,
  output wire                   mem_req_write,
  output wire [VALUE_WIDTH-1:0] mem_req_addr,
  output wire [VALUE_WIDTH-1:0] mem_req_wdata,
  output wire [7:0]             mem_req_wstrb,
  output wire [1:0]             mem_req_size,
  output wire                   mem_req_signed,
  input  wire                   mem_resp_valid,
  input  wire                   mem_resp_error,
  input  wire [VALUE_WIDTH-1:0] mem_resp_rdata,
  output reg                    op_done,
  output reg                    op_error,
  output reg  [VALUE_WIDTH-1:0] op_load_value,
  output wire                   busy
);
  localparam IDLE = 2'd0, REQUEST = 2'd1, RESPONSE = 2'd2;
  reg [1:0] state_q;
  reg store_q;
  reg fp_q;
  reg [2:0] funct3_q;
  reg [VALUE_WIDTH-1:0] addr_q;
  reg [VALUE_WIDTH-1:0] store_data_q;
  wire [1:0] size = fp_q && (funct3_q[2:1] == 2'b11) ?
                    2'b00 : funct3_q[1:0];
  wire [2:0] byte_offset = addr_q[2:0];
  wire [63:0] shifted_store = store_data_q << (byte_offset * 8);
  wire [7:0] base_strobe = size == 2'd0 ? 8'h01 :
                           size == 2'd1 ? 8'h03 :
                           size == 2'd2 ? 8'h0f : 8'hff;
  wire [63:0] shifted_load = mem_resp_rdata >> (byte_offset * 8);
  reg [63:0] formatted_load;

  assign op_ready = state_q == IDLE;
  assign busy = state_q != IDLE;
  assign mem_req_valid = state_q == REQUEST;
  assign mem_req_write = store_q;
  assign mem_req_addr = addr_q;
  assign mem_req_wdata = shifted_store;
  assign mem_req_wstrb = base_strobe << byte_offset;
  assign mem_req_size = size;
  assign mem_req_signed = !fp_q && !funct3_q[2];

  always @* begin
    case (size)
      2'd0: formatted_load = funct3_q[2] ? {56'd0, shifted_load[7:0]} :
                                           {{56{shifted_load[7]}}, shifted_load[7:0]};
      2'd1: formatted_load = funct3_q[2] ? {48'd0, shifted_load[15:0]} :
                                           {{48{shifted_load[15]}}, shifted_load[15:0]};
      2'd2: formatted_load = funct3_q[2] ? {32'd0, shifted_load[31:0]} :
                                           {{32{shifted_load[31]}}, shifted_load[31:0]};
      default: formatted_load = shifted_load;
    endcase
  end

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state_q <= IDLE;
      store_q <= 1'b0;
      fp_q <= 1'b0;
      funct3_q <= 3'd0;
      addr_q <= {VALUE_WIDTH{1'b0}};
      store_data_q <= {VALUE_WIDTH{1'b0}};
      op_done <= 1'b0;
      op_error <= 1'b0;
      op_load_value <= {VALUE_WIDTH{1'b0}};
    end else begin
      op_done <= 1'b0;
      if (op_valid && op_ready) begin
        store_q <= op_store;
        fp_q <= op_fp;
        funct3_q <= op_funct3;
        addr_q <= op_base + op_offset;
        store_data_q <= op_store_data;
        state_q <= REQUEST;
      end
      if ((state_q == REQUEST) && mem_req_ready) begin
        if (store_q && STORE_ACK_ON_ACCEPT) begin
          state_q <= IDLE;
          op_done <= 1'b1;
          op_error <= 1'b0;
          op_load_value <= {VALUE_WIDTH{1'b0}};
        end else begin
          state_q <= RESPONSE;
        end
      end
      if ((state_q == RESPONSE) && mem_resp_valid) begin
        state_q <= IDLE;
        op_done <= 1'b1;
        op_error <= mem_resp_error;
        op_load_value <= store_q ? {VALUE_WIDTH{1'b0}} :
                         (MEM_RESP_FORMATTED ? mem_resp_rdata : formatted_load);
      end
    end
  end
endmodule
