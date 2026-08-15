`timescale 1ns/1ps
module edge_rv_lite_fpu_tb;
  reg clk=0, reset_n=0; always #5 clk=~clk;
  wire imem_req_valid; wire [39:0] imem_req_addr;
  reg imem_resp_valid=0; reg [31:0] imem_resp_data=0;
  wire dmem_req_valid,dmem_req_write; wire [63:0] dmem_req_addr,dmem_req_wdata;
  wire [7:0] dmem_req_wstrb; reg dmem_resp_valid=0;
  reg [63:0] dmem_resp_rdata=0; wire halted,illegal;
  reg saw_fp32_store=0, saw_fp4_store=0;
  reg saw_fp16_store=0, saw_bf16_store=0;
  reg saw_fp8_e5m2_store=0, saw_fp8_e4m3_store=0;
  edge_rv_lite_core #(.ENABLE_FPU(1)) dut(
    .clk(clk),.reset_n(reset_n),.imem_req_valid(imem_req_valid),
    .imem_req_ready(1'b1),.imem_req_addr(imem_req_addr),
    .imem_resp_valid(imem_resp_valid),.imem_resp_data(imem_resp_data),
    .imem_resp_error(1'b0),.dmem_req_valid(dmem_req_valid),
    .dmem_req_ready(1'b1),.dmem_req_write(dmem_req_write),
    .dmem_req_addr(dmem_req_addr),.dmem_req_wdata(dmem_req_wdata),
    .dmem_req_wstrb(dmem_req_wstrb),.dmem_req_size(),.dmem_req_signed(),
    .dmem_resp_valid(dmem_resp_valid),.dmem_resp_error(1'b0),
    .dmem_resp_rdata(dmem_resp_rdata),.cache_op_valid(),.cache_op_ready(1'b1),
    .cache_op_is_va(),.cache_op_kind(),.cache_op_addr(),
    .cache_op_complete_valid(1'b0),.icache_invalidate_valid(),
    .icache_invalidate_ready(1'b1),.icache_invalidate_complete(1'b1),
    .accel_req_valid(),.accel_req_ready(1'b1),
    .accel_req_inst(),.accel_req_src0(),.accel_req_src1(),
    .accel_resp_valid(1'b0),.accel_resp_error(1'b0),.accel_resp_value(64'b0),
    .halted(halted),.illegal(illegal),.debug_x31(),.cycle_count(),.instret_count());
  always @(posedge clk) begin
    imem_resp_valid<=imem_req_valid;
    case(imem_req_addr)
      0: imem_resp_data<=32'h00002087; // flw f1,0(x0)
      4: imem_resp_data<=32'h00402107; // flw f2,4(x0)
      8: imem_resp_data<=32'h002081d3; // fadd.s f3,f1,f2
      12: imem_resp_data<=32'h00302427; // fsw f3,8(x0)
      16: imem_resp_data<=32'h00f00293; // addi x5,x0,15 (E2M1 -6)
      20: imem_resp_data<=32'hf60280d3; // fmv.s.xfp4 f1,x5
      24: imem_resp_data<=32'he6008353; // fmv.xfp4.s x6,f1
      28: imem_resp_data<=32'h00603823; // sd x6,16(x0)
      32: imem_resp_data<=32'h00001387; // fp16 load f7,0(x0)
      36: imem_resp_data<=32'h00701c27; // fp16 store f7,24(x0)
      40: imem_resp_data<=32'h00005407; // bf16 load f8,0(x0)
      44: imem_resp_data<=32'h02805027; // bf16 store f8,32(x0)
      48: imem_resp_data<=32'h00006487; // fp8 e5m2 load f9,0(x0)
      52: imem_resp_data<=32'h02906427; // fp8 e5m2 store f9,40(x0)
      56: imem_resp_data<=32'h00007507; // fp8 e4m3 load f10,0(x0)
      60: imem_resp_data<=32'h02a07827; // fp8 e4m3 store f10,48(x0)
      default: imem_resp_data<=32'h00100073;
    endcase
    dmem_resp_valid<=dmem_req_valid;
    case(dut.f3)
      3'b001: dmem_resp_rdata<=64'h0000_0000_0000_3e00; // FP16 1.5
      3'b101: dmem_resp_rdata<=64'h0000_0000_0000_3fc0; // BF16 1.5
      3'b110: dmem_resp_rdata<=64'h0000_0000_0000_003e; // E5M2 1.5
      3'b111: dmem_resp_rdata<=64'h0000_0000_0000_003c; // E4M3FN 1.5
      default: dmem_resp_rdata<=64'h40000000_3f800000;
    endcase
    if(dmem_req_valid&&dmem_req_write) begin
      if(dmem_req_addr==8) begin
        if(dmem_req_wstrb!=8'h0f||dmem_req_wdata[31:0]!=32'h40400000)
          $fatal(1,"bad FP32 store strb=%h data=%h",dmem_req_wstrb,dmem_req_wdata);
        saw_fp32_store<=1;
      end else if(dmem_req_addr==16) begin
        if(dmem_req_wstrb!=8'hff||dmem_req_wdata!=64'hf)
          $fatal(1,"bad FP4 GPR store strb=%h data=%h",dmem_req_wstrb,dmem_req_wdata);
        saw_fp4_store<=1;
      end else if(dmem_req_addr==24) begin
        if(dmem_req_wstrb!=8'h03||dmem_req_wdata[15:0]!=16'h3e00)
          $fatal(1,"bad FP16 store strb=%h data=%h",dmem_req_wstrb,dmem_req_wdata);
        saw_fp16_store<=1;
      end else if(dmem_req_addr==32) begin
        if(dmem_req_wstrb!=8'h03||dmem_req_wdata[15:0]!=16'h3fc0)
          $fatal(1,"bad BF16 store strb=%h data=%h",dmem_req_wstrb,dmem_req_wdata);
        saw_bf16_store<=1;
      end else if(dmem_req_addr==40) begin
        if(dmem_req_wstrb!=8'h01||dmem_req_wdata[7:0]!=8'h3e)
          $fatal(1,"bad E5M2 store strb=%h data=%h",dmem_req_wstrb,dmem_req_wdata);
        saw_fp8_e5m2_store<=1;
      end else if(dmem_req_addr==48) begin
        if(dmem_req_wstrb!=8'h01||dmem_req_wdata[7:0]!=8'h3c)
          $fatal(1,"bad E4M3 store strb=%h data=%h",dmem_req_wstrb,dmem_req_wdata);
        saw_fp8_e4m3_store<=1;
      end else $fatal(1,"unexpected store addr=%h",dmem_req_addr);
    end
  end
  initial begin
    repeat(3) @(posedge clk); reset_n<=1; wait(halted);
    if(illegal||!saw_fp32_store||!saw_fp4_store||!saw_fp16_store||
       !saw_bf16_store||!saw_fp8_e5m2_store||!saw_fp8_e4m3_store)
      $fatal(1,"enabled lite FPU did not complete");
    $display("EDGE_RV_LITE_FPU TEST PASS"); $finish;
  end
endmodule
