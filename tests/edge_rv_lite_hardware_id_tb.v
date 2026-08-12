`timescale 1ns/1ps
module edge_rv_lite_hardware_id_tb;
  reg clk=0; always #5 clk=~clk;
  reg reset_n=0;
  wire imem_req_valid; wire [39:0] imem_req_addr;
  reg imem_resp_valid=0; reg [31:0] imem_resp_data=0;
  wire halted,illegal; wire [63:0] debug_x31;

  edge_rv_lite_core #(
    .ENABLE_FPU(1),
    .EDGE_ASIC_ID({15'd3,4'd3,4'd3,8'h03,8'h01,8'h01})
  ) dut(
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
    .accel_req_valid(),.accel_req_ready(1'b1),.accel_req_inst(),
    .accel_req_src0(),.accel_req_src1(),.accel_resp_valid(1'b0),
    .accel_resp_error(1'b0),.accel_resp_value(64'b0),
    .halted(halted),.illegal(illegal),.debug_x31(debug_x31),
    .cycle_count(),.instret_count());

  always @(posedge clk) begin
    imem_resp_valid<=imem_req_valid;
    case(imem_req_addr)
      40'h0: imem_resp_data<=32'hfc00_2ff3; // csrr x31, 0xfc0
      default: imem_resp_data<=32'h0010_0073; // ebreak
    endcase
  end

  initial begin
    repeat(3) @(posedge clk); reset_n<=1;
    wait(halted);
    if(illegal) $fatal(1,"hardware ID CSR decoded as illegal");
    if(debug_x31!==64'h0100_0310_3303_0101)
      $fatal(1,"lite hardware ID mismatch: %h",debug_x31);
    $display("EDGE_RV_LITE_HARDWARE_ID TEST PASS id=%h",debug_x31);
    $finish;
  end
endmodule
