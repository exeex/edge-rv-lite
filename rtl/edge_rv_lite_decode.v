`timescale 1ns/1ps
// Edge-compatible instruction-family decoder for the serialized lite core.
module edge_rv_lite_decode (
  input  wire [63:0] inst,
  input  wire        inst_is_64b,
  output reg  [3:0]  op_class,
  output reg         legal,
  output wire [4:0]  rd,
  output wire [4:0]  rs1,
  output wire [4:0]  rs2,
  output wire [6:0]  accel_subop
);
  localparam [3:0] CLASS_ALU    = 4'd0;
  localparam [3:0] CLASS_BRANCH = 4'd1;
  localparam [3:0] CLASS_LOAD   = 4'd2;
  localparam [3:0] CLASS_STORE  = 4'd3;
  localparam [3:0] CLASS_MULDIV = 4'd4;
  localparam [3:0] CLASS_FPU    = 4'd5;
  localparam [3:0] CLASS_SYSTEM = 4'd6;
  localparam [3:0] CLASS_CUSTOM = 4'd7;
  localparam [3:0] CLASS_ACCEL  = 4'd8;
  localparam [3:0] CLASS_ILLEGAL = 4'd15;

  wire [6:0] opcode = inst[6:0];
  wire [2:0] funct3 = inst[14:12];
  wire [6:0] funct7 = inst[31:25];
  assign rd = inst[11:7];
  assign rs1 = inst[19:15];
  assign rs2 = inst[24:20];
  assign accel_subop = inst[38:32];

  wire edge64 = inst_is_64b && (opcode == 7'h3f);
  wire edge64_is_tensor = edge64 && inst[39];
  wire zba_op = (opcode == 7'h33) && (funct7 == 7'b0010000) &&
                ((funct3 == 3'b010) || (funct3 == 3'b100) ||
                 (funct3 == 3'b110));
  wire zba_uw = (opcode == 7'h3b) &&
                (((funct7 == 7'b0000100) && (funct3 == 3'b000)) ||
                 ((funct7 == 7'b0010000) &&
                  ((funct3 == 3'b010) || (funct3 == 3'b100) ||
                   (funct3 == 3'b110))));
  wire slli_uw = (opcode == 7'h1b) && (funct3 == 3'b001) &&
                 (inst[31:26] == 6'b000010);
  wire legal_op_imm = (opcode == 7'h13) &&
    (((funct3 != 3'b001) && (funct3 != 3'b101)) ||
     ((funct3 == 3'b001) && (inst[31:26] == 6'b000000)) ||
     ((funct3 == 3'b101) && ((inst[31:26] == 6'b000000) ||
                             (inst[31:26] == 6'b010000))));
  wire legal_op = (opcode == 7'h33) &&
    (zba_op || (funct7 == 7'b0000000) || (funct7 == 7'b0000001) ||
     ((funct7 == 7'b0100000) &&
      ((funct3 == 3'b000) || (funct3 == 3'b101))));
  wire legal_op_imm32 = (opcode == 7'h1b) &&
    ((funct3 == 3'b000) ||
     ((funct3 == 3'b001) && (funct7 == 7'b0000000)) || slli_uw ||
     ((funct3 == 3'b101) &&
      ((funct7 == 7'b0000000) || (funct7 == 7'b0100000))));
  wire legal_op32 = (opcode == 7'h3b) &&
    (zba_uw ||
     ((funct3 == 3'b000) && ((funct7 == 7'b0000000) ||
                             (funct7 == 7'b0000001) ||
                             (funct7 == 7'b0100000))) ||
     ((funct7 == 7'b0000001) && (funct3 >= 3'b100)) ||
     ((funct3 == 3'b001) && (funct7 == 7'b0000000)) ||
     ((funct3 == 3'b101) && ((funct7 == 7'b0000000) ||
                             (funct7 == 7'b0100000))));
  wire legal_branch = (opcode == 7'h63) && (funct3 != 3'b010) &&
                      (funct3 != 3'b011);
  wire legal_load = (opcode == 7'h03) && (funct3 != 3'b111);
  wire legal_store = (opcode == 7'h23) && (funct3 <= 3'b011);
  wire legal_fp_mem = ((opcode == 7'h07) || (opcode == 7'h27)) &&
                      ((funct3 == 3'b001) || (funct3 == 3'b010) ||
                       (funct3 == 3'b011) || (funct3 >= 3'b101));
  wire fp_opcode = (opcode == 7'h43) || (opcode == 7'h47) ||
                   (opcode == 7'h4b) || (opcode == 7'h4f) ||
                   (opcode == 7'h53);
  wire legal_cache = (opcode == 7'h0b) && (funct7 == 7'd0) && (rd == 5'd0) &&
    (((funct3 == 3'b000) && (rs1 == 5'd0) &&
      ((rs2 == 5'd1) || (rs2 == 5'd2) || (rs2 == 5'd3))) ||
     ((funct3 == 3'b001) &&
      ((rs2 == 5'd5) || (rs2 == 5'd6) || (rs2 == 5'd7))));
  wire legal_dma32 = (opcode == 7'h2b) && (funct3 == 3'b000) &&
    ((funct7 == 7'd0) || ((funct7 == 7'd1) && (rd == 5'd0) &&
                          (rs1 == 5'd0) && (rs2 == 5'd0)));

  always @* begin
    op_class = CLASS_ILLEGAL;
    legal = 1'b1;
    if (edge64) begin
      op_class = CLASS_ACCEL;
      // Vector legality remains owned by its execution decoder. Tensor/ASIC
      // commands use the same allocated sub-op set as edge-rv predecode.
      if (edge64_is_tensor) begin
        case (accel_subop)
          7'h01, 7'h02, 7'h03, 7'h04, 7'h05, 7'h06, 7'h07, 7'h08,
          7'h10, 7'h11, 7'h12, 7'h13, 7'h14, 7'h16, 7'h17, 7'h18,
          7'h1a, 7'h1d, 7'h20, 7'h21, 7'h22, 7'h23, 7'h24, 7'h26,
          7'h27, 7'h28, 7'h29, 7'h2a, 7'h2b, 7'h2c, 7'h2e, 7'h2f:
            legal = 1'b1;
          default: legal = 1'b0;
        endcase
      end
    end else if (inst_is_64b) begin
      legal = 1'b0;
    end else if (legal_op || legal_op_imm || legal_op32 || legal_op_imm32 ||
                 (opcode == 7'h37) || (opcode == 7'h17)) begin
      op_class = ((opcode == 7'h33 || opcode == 7'h3b) &&
                  (funct7 == 7'b0000001)) ? CLASS_MULDIV : CLASS_ALU;
    end else if ((opcode == 7'h6f) || ((opcode == 7'h67) &&
                                      (funct3 == 3'b000)) || legal_branch) begin
      op_class = CLASS_BRANCH;
    end else if (legal_load) begin
      op_class = CLASS_LOAD;
    end else if (legal_store) begin
      op_class = CLASS_STORE;
    end else if (legal_fp_mem || fp_opcode) begin
      op_class = CLASS_FPU;
    end else if ((opcode == 7'h73) ||
                 ((opcode == 7'h0f) && (funct3 <= 3'b001))) begin
      op_class = CLASS_SYSTEM;
    end else if (legal_cache || legal_dma32) begin
      op_class = CLASS_CUSTOM;
    end else begin
      legal = 1'b0;
    end
  end
endmodule
