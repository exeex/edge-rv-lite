`timescale 1ns/1ps
module edge_rv_lite_fpu_tb;
  reg clk=0, reset_n=0; always #5 clk=~clk;
  wire imem_req_valid; wire [39:0] imem_req_addr;
  reg imem_resp_valid=0; reg [31:0] imem_resp_data=0;
  wire dmem_req_valid,dmem_req_write; wire [63:0] dmem_req_addr,dmem_req_wdata;
  wire [7:0] dmem_req_wstrb; reg dmem_resp_valid=0;
  reg [63:0] dmem_resp_rdata=0; wire halted,illegal;
  reg saw_store=0;
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
    .cache_op_complete_valid(1'b0),.accel_req_valid(),.accel_req_ready(1'b1),
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
      default: imem_resp_data<=32'h00100073;
    endcase
    dmem_resp_valid<=dmem_req_valid;
    dmem_resp_rdata<=64'h40000000_3f800000;
    if(dmem_req_valid&&dmem_req_write) begin
      if(dmem_req_addr!=8||dmem_req_wstrb!=8'h0f||dmem_req_wdata[31:0]!=32'h40400000)
        $fatal(1,"bad FPU store addr=%h strb=%h data=%h",dmem_req_addr,dmem_req_wstrb,dmem_req_wdata);
      saw_store<=1;
    end
  end
  initial begin
    repeat(3) @(posedge clk); reset_n<=1; wait(halted);
    if(illegal||!saw_store) $fatal(1,"enabled lite FPU did not complete");
    $display("EDGE_RV_LITE_FPU TEST PASS"); $finish;
  end
endmodule
