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
  output wire                issue_valid,
  input  wire                issue_ready,
  output wire [PC_WIDTH-1:0] issue_pc,
  output wire [31:0]         issue_inst,
  output wire                issue_error,
  input  wire                redirect_valid,
  input  wire [PC_WIDTH-1:0] redirect_pc
);
  reg [PC_WIDTH-1:0] fetch_pc_q;
  reg request_pending_q;
  reg request_killed_q;
  reg [PC_WIDTH-1:0] request_pc_q;
  reg decode_valid_q;
  reg [PC_WIDTH-1:0] decode_pc_q;
  reg [31:0] decode_inst_q;
  reg decode_error_q;

  assign imem_req_valid = !request_pending_q && !decode_valid_q &&
                          !redirect_valid;
  assign imem_req_addr = fetch_pc_q;
  assign issue_valid = decode_valid_q && !redirect_valid;
  assign issue_pc = decode_pc_q;
  assign issue_inst = decode_inst_q;
  assign issue_error = decode_error_q;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      fetch_pc_q <= RESET_PC;
      request_pending_q <= 1'b0;
      request_killed_q <= 1'b0;
      request_pc_q <= RESET_PC;
      decode_valid_q <= 1'b0;
      decode_pc_q <= RESET_PC;
      decode_inst_q <= 32'h0000_0013;
      decode_error_q <= 1'b0;
    end else begin
      if (imem_req_valid && imem_req_ready) begin
        request_pending_q <= 1'b1;
        request_killed_q <= 1'b0;
        request_pc_q <= fetch_pc_q;
      end
      if (imem_resp_valid && request_pending_q) begin
        request_pending_q <= 1'b0;
        if (!request_killed_q && !redirect_valid) begin
          decode_valid_q <= 1'b1;
          decode_pc_q <= request_pc_q;
          decode_inst_q <= imem_resp_data;
          decode_error_q <= imem_resp_error;
          fetch_pc_q <= request_pc_q + {{(PC_WIDTH-3){1'b0}}, 3'd4};
        end
      end
      if (issue_valid && issue_ready) decode_valid_q <= 1'b0;
      if (redirect_valid) begin
        fetch_pc_q <= redirect_pc;
        decode_valid_q <= 1'b0;
        if (request_pending_q && !imem_resp_valid) request_killed_q <= 1'b1;
      end
    end
  end
endmodule

