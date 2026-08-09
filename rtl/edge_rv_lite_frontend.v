`timescale 1ns/1ps
// Single-outstanding fetch frontend. A resolved control transfer discards the
// F/D contents and restarts at redirect_pc; no epoch or prediction is needed.
module edge_rv_lite_frontend #(
  parameter PC_WIDTH = 40,
  parameter [PC_WIDTH-1:0] RESET_PC = {PC_WIDTH{1'b0}}
) (
  input  wire                clk,
  input  wire                reset_n,
  output wire                imem_req_valid,
  input  wire                imem_req_ready,
  output wire [PC_WIDTH-1:0] imem_req_addr,
  input  wire                imem_resp_valid,
  input  wire [31:0]         imem_resp_data,
  input  wire                imem_resp_error,
  output wire                op_valid,
  input  wire                op_ready,
  output wire [PC_WIDTH-1:0] op_pc,
  output wire [31:0]         op_inst,
  output wire                op_error,
  input  wire                redirect_valid,
  input  wire [PC_WIDTH-1:0] redirect_pc
);
  reg [PC_WIDTH-1:0] fetch_pc_q;
  reg request_pending_q;
  reg request_killed_q;
  reg [PC_WIDTH-1:0] request_pc_q;
  reg [1:0] fifo_count_q;
  reg fifo_read_q, fifo_write_q;
  reg [PC_WIDTH-1:0] fifo_pc_q [0:1];
  reg [31:0] fifo_inst_q [0:1];
  reg fifo_error_q [0:1];

  wire request_fire = imem_req_valid && imem_req_ready;
  wire response_fire = imem_resp_valid && request_pending_q;
  wire response_push = response_fire && !request_killed_q && !redirect_valid;
  wire output_pop = op_valid && op_ready;
  wire [2:0] reserved_count = {1'b0, fifo_count_q} + request_pending_q;
  wire reservation_space = (reserved_count < 3'd2) ||
                           (output_pop && (reserved_count == 3'd2));
  // A response and the next request may cross. The two-entry IF FIFO provides
  // the skid slot required when EX starts a variable-latency stall.
  assign imem_req_valid = (!request_pending_q || response_fire) &&
                          reservation_space && !redirect_valid;
  assign imem_req_addr = fetch_pc_q;
  assign op_valid = (fifo_count_q != 0) && !redirect_valid;
  assign op_pc = fifo_pc_q[fifo_read_q];
  assign op_inst = fifo_inst_q[fifo_read_q];
  assign op_error = fifo_error_q[fifo_read_q];

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      fetch_pc_q <= RESET_PC;
      request_pending_q <= 1'b0;
      request_killed_q <= 1'b0;
      request_pc_q <= RESET_PC;
      fifo_count_q <= 2'd0;
      fifo_read_q <= 1'b0;
      fifo_write_q <= 1'b0;
      fifo_pc_q[0] <= RESET_PC;
      fifo_pc_q[1] <= RESET_PC;
      fifo_inst_q[0] <= 32'h0000_0013;
      fifo_inst_q[1] <= 32'h0000_0013;
      fifo_error_q[0] <= 1'b0;
      fifo_error_q[1] <= 1'b0;
    end else begin
      if (request_fire) begin
        request_pending_q <= 1'b1;
        request_killed_q <= 1'b0;
        request_pc_q <= fetch_pc_q;
        fetch_pc_q <= fetch_pc_q + {{(PC_WIDTH-3){1'b0}}, 3'd4};
      end
      if (response_fire) begin
        request_pending_q <= 1'b0;
        request_killed_q <= 1'b0;
      end
      // A crossing request owns the newly freed outstanding slot.
      if (request_fire) request_pending_q <= 1'b1;

      if (response_push) begin
        fifo_pc_q[fifo_write_q] <= request_pc_q;
        fifo_inst_q[fifo_write_q] <= imem_resp_data;
        fifo_error_q[fifo_write_q] <= imem_resp_error;
        fifo_write_q <= ~fifo_write_q;
      end
      if (output_pop) fifo_read_q <= ~fifo_read_q;
      case ({response_push, output_pop})
        2'b10: fifo_count_q <= fifo_count_q + 1'b1;
        2'b01: fifo_count_q <= fifo_count_q - 1'b1;
        default: fifo_count_q <= fifo_count_q;
      endcase

      if (redirect_valid) begin
        fetch_pc_q <= redirect_pc;
        fifo_count_q <= 2'd0;
        fifo_read_q <= 1'b0;
        fifo_write_q <= 1'b0;
        if (request_pending_q && !response_fire) request_killed_q <= 1'b1;
      end
    end
  end
endmodule
