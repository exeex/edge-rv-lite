`timescale 1ns/1ps

// Converts the frontend's ordered 32-bit parcels into complete scalar32 or
// Edge64 instructions. The 7'h3f low-parcel marker owns the following parcel.
module edge_rv_lite_instruction_assembler #(
  parameter PC_WIDTH = 40
) (
  input  wire                 clk,
  input  wire                 reset_n,
  input  wire                 parcel_valid,
  output wire                 parcel_ready,
  input  wire [PC_WIDTH-1:0]  parcel_pc,
  input  wire [31:0]          parcel_data,
  input  wire                 parcel_error,
  output wire                 op_valid,
  input  wire                 op_ready,
  output wire [PC_WIDTH-1:0]  op_pc,
  output wire [63:0]          op_inst,
  output wire                 op_is_64b,
  output wire                 op_error,
  input  wire                 flush
);
  reg low_valid_q;
  reg [PC_WIDTH-1:0] low_pc_q;
  reg [31:0] low_data_q;
  reg low_error_q;

  wire parcel_is_marker = parcel_data[6:0] == 7'h3f;
  assign op_valid = parcel_valid && (!parcel_is_marker || low_valid_q) && !flush;
  assign op_pc = low_valid_q ? low_pc_q : parcel_pc;
  assign op_inst = low_valid_q ? {parcel_data, low_data_q} : {32'b0, parcel_data};
  assign op_is_64b = low_valid_q;
  assign op_error = low_valid_q ? (low_error_q || parcel_error) : parcel_error;
  assign parcel_ready = !flush && (low_valid_q ? op_ready :
                        (parcel_is_marker ? 1'b1 : op_ready));

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      low_valid_q <= 1'b0;
      low_pc_q <= {PC_WIDTH{1'b0}};
      low_data_q <= 32'b0;
      low_error_q <= 1'b0;
    end else if (flush) begin
      low_valid_q <= 1'b0;
    end else if (parcel_valid && parcel_ready) begin
      if (!low_valid_q && parcel_is_marker) begin
        low_valid_q <= 1'b1;
        low_pc_q <= parcel_pc;
        low_data_q <= parcel_data;
        low_error_q <= parcel_error;
      end else if (low_valid_q) begin
        low_valid_q <= 1'b0;
      end
    end
  end
endmodule
