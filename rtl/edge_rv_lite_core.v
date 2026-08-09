`timescale 1ns/1ps
// Bootable RV64IM_Zba three-stage core. Variable-latency EX freezes IF/ID.
module edge_rv_lite_core #(
  parameter PC_WIDTH = 40
) (
  input wire clk, input wire reset_n,
  output wire imem_req_valid, input wire imem_req_ready,
  output wire [PC_WIDTH-1:0] imem_req_addr,
  input wire imem_resp_valid, input wire [31:0] imem_resp_data,
  input wire imem_resp_error,
  output wire dmem_req_valid, input wire dmem_req_ready,
  output wire dmem_req_write, output wire [63:0] dmem_req_addr,
  output wire [63:0] dmem_req_wdata, output wire [7:0] dmem_req_wstrb,
  output wire [1:0] dmem_req_size, output wire dmem_req_signed,
  input wire dmem_resp_valid, input wire dmem_resp_error,
  input wire [63:0] dmem_resp_rdata,
  output reg halted, output reg illegal,
  output wire [63:0] debug_x31, output wire [63:0] cycle_count,
  output wire [63:0] instret_count
);
  localparam [3:0] A_IMM=0, A_OP=1, A_IMM32=2, A_OP32=3,
    A_LUI=4, A_AUIPC=5, A_JAL=6, A_JALR=7, A_BRANCH=8,
    A_ZBA=9, A_ZBA_UW=10;
  reg [63:0] gpr [0:31];
  reg [63:0] cycle_q, instret_q;
  reg mem_started_q, mul_started_q;
  integer ri;

  wire if_valid, if_ready, if_error;
  wire [PC_WIDTH-1:0] if_pc; wire [31:0] if_inst;
  wire id_valid, id_error; wire [PC_WIDTH-1:0] id_pc; wire [31:0] id_inst;
  wire ex_valid, ex_error; wire [PC_WIDTH-1:0] ex_pc; wire [31:0] ex_inst;
  wire [63:0] ex_rs1_value, ex_rs2_value;
  wire [4:0] id_rs1=id_inst[19:15], id_rs2=id_inst[24:20];
  wire [63:0] id_rs1_raw=id_rs1==0 ? 0 : gpr[id_rs1];
  wire [63:0] id_rs2_raw=id_rs2==0 ? 0 : gpr[id_rs2];

  wire [6:0] opc=ex_inst[6:0]; wire [2:0] f3=ex_inst[14:12];
  wire [6:0] f7=ex_inst[31:25]; wire [4:0] rd=ex_inst[11:7];
  wire is_opimm=opc==7'h13, is_op=opc==7'h33;
  wire is_opimm32=opc==7'h1b, is_op32=opc==7'h3b;
  wire is_lui=opc==7'h37, is_auipc=opc==7'h17;
  wire is_jal=opc==7'h6f, is_jalr=(opc==7'h67)&&(f3==0);
  wire is_branch=opc==7'h63;
  wire is_load=opc==7'h03, is_store=opc==7'h23;
  wire is_muldiv=(is_op||is_op32)&&(f7==7'b0000001);
  wire is_zba=is_op&&(f7==7'b0010000)&&
    ((f3==2)||(f3==4)||(f3==6));
  wire is_zba_uw=is_op32&&(((f7==7'b0000100)&&(f3==0))||
    ((f7==7'b0010000)&&((f3==2)||(f3==4)||(f3==6))));
  wire is_slli_uw=is_opimm32&&(f3==1)&&(ex_inst[31:26]==6'b000010);
  wire is_cycle=(opc==7'h73)&&(f3==3'b010)&&(ex_inst[31:20]==12'hc00)&&
    (ex_inst[19:15]==0);
  wire is_instret=(opc==7'h73)&&(f3==3'b010)&&(ex_inst[31:20]==12'hc02)&&
    (ex_inst[19:15]==0);
  wire is_ebreak=ex_inst==32'h0010_0073;
  wire legal_branch=(f3==0)||(f3==1)||(f3>=4);
  wire legal_load=f3!=7;
  wire legal_store=f3<=3;
  wire legal_opimm=is_opimm&&(((f3!=1)&&(f3!=5))||
    ((f3==1)&&(ex_inst[31:26]==0))||
    ((f3==5)&&((ex_inst[31:26]==0)||(ex_inst[31:26]==6'b010000))));
  wire legal_op=is_op&&(is_muldiv||is_zba||(f7==0)||
    ((f7==7'b0100000)&&((f3==0)||(f3==5))));
  wire legal_opimm32=is_opimm32&&((f3==0)||is_slli_uw||
    ((f3==1)&&(f7==0))||((f3==5)&&((f7==0)||(f7==7'b0100000))));
  wire legal_op32=is_op32&&(is_muldiv||is_zba_uw||
    ((f3==0)&&((f7==0)||(f7==7'b0100000)))||
    ((f3==1)&&(f7==0))||((f3==5)&&((f7==0)||(f7==7'b0100000))));
  wire legal_fast=legal_opimm||legal_op||legal_opimm32||legal_op32||
    is_lui||is_auipc||is_jal||is_jalr||(is_branch&&legal_branch);
  wire legal_mem=(is_load&&legal_load)||(is_store&&legal_store);
  wire legal_sys=is_cycle||is_instret||is_ebreak;
  wire ex_legal=legal_fast||legal_mem||legal_sys;

  wire [11:0] i12=ex_inst[31:20];
  wire [11:0] s12={ex_inst[31:25],ex_inst[11:7]};
  wire [63:0] imm_i={{52{i12[11]}},i12};
  wire [63:0] imm_s={{52{s12[11]}},s12};
  wire [63:0] imm_u={{32{ex_inst[31]}},ex_inst[31:12],12'b0};
  wire [63:0] imm_b={{51{ex_inst[31]}},ex_inst[31],ex_inst[7],
    ex_inst[30:25],ex_inst[11:8],1'b0};
  wire [63:0] imm_j={{43{ex_inst[31]}},ex_inst[31],ex_inst[19:12],
    ex_inst[20],ex_inst[30:21],1'b0};
  reg [3:0] alu_op;
  always @* begin
    alu_op=A_OP;
    if(is_opimm) alu_op=A_IMM;
    else if(is_opimm32) alu_op=is_slli_uw ? A_ZBA_UW:A_IMM32;
    else if(is_op32) alu_op=is_zba_uw||is_slli_uw ? A_ZBA_UW:A_OP32;
    else if(is_zba) alu_op=A_ZBA; else if(is_lui) alu_op=A_LUI;
    else if(is_auipc) alu_op=A_AUIPC; else if(is_jal) alu_op=A_JAL;
    else if(is_jalr) alu_op=A_JALR; else if(is_branch) alu_op=A_BRANCH;
  end
  wire [63:0] fast_result;
  edge_scalar_fast_alu fast_alu(.fast_issue_op(alu_op),.fast_issue_pc(ex_pc),
    .fast_issue_src0_value(ex_rs1_value),.fast_issue_src1_value(ex_rs2_value),
    .fast_issue_imm((is_lui||is_auipc)?imm_u:imm_i),.fast_issue_funct3(f3),
    .fast_issue_funct7_bit5(ex_inst[30]),.fast_issue_funct7_is_m(1'b0),
    .fast_issue_shamt(ex_inst[25:20]),.fast_issue_shamt32(ex_inst[24:20]),
    .fast_result(fast_result));
  wire branch_taken; wire [PC_WIDTH-1:0] branch_target;
  edge_scalar_branch branch(.branch_issue_op(alu_op),.branch_issue_pc(ex_pc),
    .branch_issue_src0_value(ex_rs1_value),.branch_issue_src1_value(ex_rs2_value),
    .branch_issue_imm(imm_i),.branch_issue_branch_imm(imm_b),
    .branch_issue_jal_imm(imm_j),.branch_issue_funct3(f3),
    .branch_taken(branch_taken),.branch_target(branch_target));

  wire mul_ready,mul_result_valid,mul_busy; wire [63:0] mul_result;
  wire mul_start=ex_valid&&is_muldiv&&!mul_started_q;
  edge_scalar_muldiv_leaf muldiv(.clk(clk),.reset_n(reset_n),
    .op_valid(mul_start),.op_ready(mul_ready),.op(alu_op),
    .src0(ex_rs1_value),.src1(ex_rs2_value),.funct3(f3),
    .result_valid(mul_result_valid),.result_value(mul_result),.busy(mul_busy));

  wire lsu_ready,lsu_done,lsu_error,lsu_busy; wire [63:0] lsu_value;
  wire lsu_start=ex_valid&&legal_mem&&!mem_started_q;
  edge_rv_lite_lsu lsu(.clk(clk),.reset_n(reset_n),.op_valid(lsu_start),
    .op_ready(lsu_ready),.op_store(is_store),.op_funct3(f3),
    .op_base(ex_rs1_value),.op_offset(is_store?imm_s:imm_i),
    .op_store_data(ex_rs2_value),.mem_req_valid(dmem_req_valid),
    .mem_req_ready(dmem_req_ready),.mem_req_write(dmem_req_write),
    .mem_req_addr(dmem_req_addr),.mem_req_wdata(dmem_req_wdata),
    .mem_req_wstrb(dmem_req_wstrb),.mem_req_size(dmem_req_size),
    .mem_req_signed(dmem_req_signed),.mem_resp_valid(dmem_resp_valid),
    .mem_resp_error(dmem_resp_error),.mem_resp_rdata(dmem_resp_rdata),
    .op_done(lsu_done),.op_error(lsu_error),.op_load_value(lsu_value),.busy(lsu_busy));

  wire fast_done=ex_valid&&legal_fast&&!is_muldiv;
  wire sys_done=ex_valid&&legal_sys;
  wire ex_done=fast_done||sys_done||(is_muldiv&&mul_result_valid)||
    (legal_mem&&lsu_done)||(ex_valid&&!ex_legal);
  wire ex_control=is_jal||is_jalr||is_branch;
  wire redirect=fast_done&&ex_control&&branch_taken;
  wire [63:0] wb_value=is_muldiv?mul_result:is_load?lsu_value:
    is_cycle?cycle_q:is_instret?instret_q:fast_result;
  wire wb_valid=ex_done&&(rd!=0)&&!is_store&&!is_branch&&!is_ebreak&&ex_legal;

  edge_rv_lite_frontend frontend(.clk(clk),.reset_n(reset_n),
    .imem_req_valid(imem_req_valid),.imem_req_ready(imem_req_ready),
    .imem_req_addr(imem_req_addr),.imem_resp_valid(imem_resp_valid),
    .imem_resp_data(imem_resp_data),.imem_resp_error(imem_resp_error),
    .op_valid(if_valid),.op_ready(if_ready),.op_pc(if_pc),.op_inst(if_inst),
    .op_error(if_error),.redirect_valid(redirect),.redirect_pc(branch_target));
  edge_rv_lite_pipeline pipeline(.clk(clk),.reset_n(reset_n),
    .fetch_valid(if_valid),.fetch_ready(if_ready),.fetch_pc(if_pc),
    .fetch_inst(if_inst),.fetch_error(if_error),.id_valid(id_valid),.id_pc(id_pc),
    .id_inst(id_inst),.id_error(id_error),.id_rs1(id_rs1),.id_rs2(id_rs2),
    .id_rs1_raw(id_rs1_raw),.id_rs2_raw(id_rs2_raw),.ex_valid(ex_valid),
    .ex_pc(ex_pc),.ex_inst(ex_inst),.ex_error(ex_error),
    .ex_rs1_value(ex_rs1_value),.ex_rs2_value(ex_rs2_value),.ex_done(ex_done),
    .ex_write_valid(wb_valid),.ex_write_rd(rd),.ex_write_value(wb_value),
    .ex_redirect_valid(redirect));

  assign debug_x31=gpr[31]; assign cycle_count=cycle_q; assign instret_count=instret_q;
  always @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
      for(ri=0;ri<32;ri=ri+1) gpr[ri]<=0;
      cycle_q<=0; instret_q<=0; mem_started_q<=0; mul_started_q<=0;
      halted<=0; illegal<=0;
    end else begin
      cycle_q<=cycle_q+1; gpr[0]<=0;
      if(lsu_start&&lsu_ready) mem_started_q<=1;
      if(mul_start&&mul_ready) mul_started_q<=1;
      if(ex_done) begin
        mem_started_q<=0; mul_started_q<=0;
        if(ex_valid) instret_q<=instret_q+1;
        if(wb_valid) gpr[rd]<=wb_value;
        if(is_ebreak) halted<=1;
        if(!ex_legal||ex_error||(legal_mem&&lsu_error)) begin illegal<=1; halted<=1; end
      end
    end
  end
endmodule
