`timescale 1ns/1ps
module edge_rv_lite_accel_serial_tb;
  reg clk=0; always #5 clk=~clk;
  reg reset_n=0;
  wire imem_req_valid; wire [39:0] imem_req_addr;
  reg imem_resp_valid=0; reg [31:0] imem_resp_data=0;
  wire accel_req_valid; reg accel_req_ready=0;
  wire [63:0] accel_req_inst, accel_req_src0, accel_req_src1;
  reg accel_resp_valid=0, accel_resp_error=0;
  reg [63:0] accel_resp_value=0;
  wire halted, illegal; wire [63:0] instret_count;
  integer accepted=0, delay=0;

  edge_rv_lite_core dut(
    .clk(clk),.reset_n(reset_n),
    .imem_req_valid(imem_req_valid),.imem_req_ready(1'b1),
    .imem_req_addr(imem_req_addr),.imem_resp_valid(imem_resp_valid),
    .imem_resp_data(imem_resp_data),.imem_resp_error(1'b0),
    .dmem_req_valid(),.dmem_req_ready(1'b1),.dmem_req_write(),
    .dmem_req_addr(),.dmem_req_wdata(),.dmem_req_wstrb(),
    .dmem_req_size(),.dmem_req_signed(),.dmem_resp_valid(1'b0),
    .dmem_resp_error(1'b0),.dmem_resp_rdata(64'b0),
    .cache_op_valid(),.cache_op_ready(1'b1),.cache_op_is_va(),
    .cache_op_kind(),.cache_op_addr(),.cache_op_complete_valid(1'b0),
    .accel_req_valid(accel_req_valid),.accel_req_ready(accel_req_ready),
    .accel_req_inst(accel_req_inst),.accel_req_src0(accel_req_src0),
    .accel_req_src1(accel_req_src1),.accel_resp_valid(accel_resp_valid),
    .accel_resp_error(accel_resp_error),.accel_resp_value(accel_resp_value),
    .halted(halted),.illegal(illegal),.debug_x31(),.cycle_count(),
    .instret_count(instret_count));

  always @(posedge clk) begin
    imem_resp_valid<=imem_req_valid;
    case(imem_req_addr)
      40'h0: imem_resp_data<=32'h02a0_0293; // addi x5,x0,42
      40'h4: imem_resp_data<=32'h0630_0313; // addi x6,x0,99
      40'h8: imem_resp_data<=32'h0062_803f; // rs1/capture=x5, ordinary rs2=x6
      40'hc: imem_resp_data<=32'h0000_00a4; // actu.setscalar
      default: imem_resp_data<=32'h0010_0073;
    endcase
    accel_resp_valid<=0;
    if(accel_req_valid&&accel_req_ready) begin
      accepted<=accepted+1; delay<=3;
      if(accel_req_inst!=64'h0000_00a4_0062_803f ||
         accel_req_src0!=64'd42 || accel_req_src1!=64'd42)
        $fatal(1,"serialized accelerator payload mismatch");
    end
    if(delay>0) begin
      delay<=delay-1;
      if(delay==1) accel_resp_valid<=1;
    end
  end

  initial begin
    repeat(3) @(posedge clk); reset_n<=1;
    wait(accel_req_valid);
    repeat(3) begin
      @(posedge clk);
      if(accel_req_inst!=64'h0000_00a4_0062_803f ||
         accel_req_src0!=64'd42 || accel_req_src1!=64'd42)
        $fatal(1,"request changed under backpressure inst=%h src0=%h src1=%h",
               accel_req_inst, accel_req_src0, accel_req_src1);
    end
    accel_req_ready<=1;
    wait(halted);
    if(illegal||accepted!=1||instret_count!=4)
      $fatal(1,"serial accelerator completion/retire mismatch");
    $display("TEST PASS: Edge64 fetch and serialized accelerator completion");
    $finish;
  end
endmodule
