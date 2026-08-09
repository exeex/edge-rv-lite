`timescale 1ns/1ps
// Standard single-issue three-stage pipeline register/control slice:
// external fetch (IF) -> decode/register-read (ID) -> execute/writeback (EX).
module edge_rv_lite_pipeline #(
  parameter PC_WIDTH = 40,
  parameter VALUE_WIDTH = 64
) (
  input  wire                   clk,
  input  wire                   reset_n,

  input  wire                   fetch_valid,
  output wire                   fetch_ready,
  input  wire [PC_WIDTH-1:0]    fetch_pc,
  input  wire [31:0]            fetch_inst,
  input  wire                   fetch_error,

  output wire                   id_valid,
  output wire [PC_WIDTH-1:0]    id_pc,
  output wire [31:0]            id_inst,
  output wire                   id_error,
  input  wire [4:0]             id_rs1,
  input  wire [4:0]             id_rs2,
  input  wire [VALUE_WIDTH-1:0] id_rs1_raw,
  input  wire [VALUE_WIDTH-1:0] id_rs2_raw,

  output wire                   ex_valid,
  output wire [PC_WIDTH-1:0]    ex_pc,
  output wire [31:0]            ex_inst,
  output wire                   ex_error,
  output wire [VALUE_WIDTH-1:0] ex_rs1_value,
  output wire [VALUE_WIDTH-1:0] ex_rs2_value,
  input  wire                   ex_done,
  input  wire                   ex_write_valid,
  input  wire [4:0]             ex_write_rd,
  input  wire [VALUE_WIDTH-1:0] ex_write_value,
  input  wire                   ex_redirect_valid
);
  reg id_valid_q;
  reg [PC_WIDTH-1:0] id_pc_q;
  reg [31:0] id_inst_q;
  reg id_error_q;
  reg ex_valid_q;
  reg [PC_WIDTH-1:0] ex_pc_q;
  reg [31:0] ex_inst_q;
  reg ex_error_q;
  reg [VALUE_WIDTH-1:0] ex_rs1_q;
  reg [VALUE_WIDTH-1:0] ex_rs2_q;

  wire ex_blocked = ex_valid_q && !ex_done;
  wire id_can_advance = !ex_blocked;
  wire forward_rs1 = ex_valid_q && ex_done && ex_write_valid &&
                     (ex_write_rd != 5'd0) && (id_rs1 == ex_write_rd);
  wire forward_rs2 = ex_valid_q && ex_done && ex_write_valid &&
                     (ex_write_rd != 5'd0) && (id_rs2 == ex_write_rd);

  assign fetch_ready = id_can_advance && !ex_redirect_valid;
  assign id_valid = id_valid_q;
  assign id_pc = id_pc_q;
  assign id_inst = id_inst_q;
  assign id_error = id_error_q;
  assign ex_valid = ex_valid_q;
  assign ex_pc = ex_pc_q;
  assign ex_inst = ex_inst_q;
  assign ex_error = ex_error_q;
  assign ex_rs1_value = ex_rs1_q;
  assign ex_rs2_value = ex_rs2_q;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      id_valid_q <= 1'b0;
      ex_valid_q <= 1'b0;
      id_pc_q <= {PC_WIDTH{1'b0}};
      ex_pc_q <= {PC_WIDTH{1'b0}};
      id_inst_q <= 32'h0000_0013;
      ex_inst_q <= 32'h0000_0013;
      id_error_q <= 1'b0;
      ex_error_q <= 1'b0;
      ex_rs1_q <= {VALUE_WIDTH{1'b0}};
      ex_rs2_q <= {VALUE_WIDTH{1'b0}};
    end else if (ex_redirect_valid) begin
      // The resolving EX instruction completes; all younger ID/IF work dies.
      id_valid_q <= 1'b0;
      ex_valid_q <= 1'b0;
    end else if (id_can_advance) begin
      ex_valid_q <= id_valid_q;
      ex_pc_q <= id_pc_q;
      ex_inst_q <= id_inst_q;
      ex_error_q <= id_error_q;
      ex_rs1_q <= forward_rs1 ? ex_write_value : id_rs1_raw;
      ex_rs2_q <= forward_rs2 ? ex_write_value : id_rs2_raw;
      id_valid_q <= fetch_valid && fetch_ready;
      if (fetch_valid && fetch_ready) begin
        id_pc_q <= fetch_pc;
        id_inst_q <= fetch_inst;
        id_error_q <= fetch_error;
      end
    end
  end
endmodule

