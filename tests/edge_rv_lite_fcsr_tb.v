`timescale 1ns/1ps
module edge_rv_lite_fcsr_tb;
  reg clk=0,reset_n=0; always #5 clk=~clk;
  wire imem_req_valid; wire [39:0] imem_req_addr;
  reg imem_resp_valid=0; reg [31:0] imem_resp_data=0;
  wire dmem_req_valid,dmem_req_write;
  wire [63:0] dmem_req_addr,dmem_req_wdata; wire [7:0] dmem_req_wstrb;
  reg dmem_resp_valid=0; reg [63:0] dmem_resp_rdata=0;
  wire halted,illegal;
  reg saw_flags=0,saw_dynamic=0,saw_frm=0,saw_clear=0;
  integer timeout;

  edge_rv_lite_core #(.ENABLE_FPU(1)) dut(
    .clk(clk),.reset_n(reset_n),
    .imem_req_valid(imem_req_valid),.imem_req_ready(1'b1),
    .imem_req_addr(imem_req_addr),.imem_resp_valid(imem_resp_valid),
    .imem_resp_data(imem_resp_data),.imem_resp_error(1'b0),
    .dmem_req_valid(dmem_req_valid),.dmem_req_ready(1'b1),
    .dmem_req_write(dmem_req_write),.dmem_req_addr(dmem_req_addr),
    .dmem_req_wdata(dmem_req_wdata),.dmem_req_wstrb(dmem_req_wstrb),
    .dmem_req_size(),.dmem_req_signed(),.dmem_resp_valid(dmem_resp_valid),
    .dmem_resp_error(1'b0),.dmem_resp_rdata(dmem_resp_rdata),
    .cache_op_valid(),.cache_op_ready(1'b1),.cache_op_is_va(),
    .cache_op_kind(),.cache_op_addr(),.cache_op_complete_valid(1'b0),
    .icache_invalidate_valid(),.icache_invalidate_ready(1'b1),
    .icache_invalidate_complete(1'b1),.accel_req_valid(),
    .accel_req_ready(1'b1),.accel_req_inst(),.accel_req_src0(),
    .accel_req_src1(),.accel_resp_valid(1'b0),.accel_resp_error(1'b0),
    .accel_resp_value(64'b0),.halted(halted),.illegal(illegal),
    .debug_x31(),.cycle_count(),.instret_count());

  always @(posedge clk) begin
    imem_resp_valid<=imem_req_valid;
    case(imem_req_addr)
      40'h00: imem_resp_data<=32'h00002087; // flw f1,0(x0): sNaN
      40'h04: imem_resp_data<=32'h00402107; // flw f2,4(x0): 1.0
      40'h08: imem_resp_data<=32'h002081d3; // fadd.s: NV
      40'h0c: imem_resp_data<=32'h00802087; // flw f1,8(x0): 1.0
      40'h10: imem_resp_data<=32'h00c02107; // flw f2,12(x0): 0.0
      40'h14: imem_resp_data<=32'h182081d3; // fdiv.s: DZ
      40'h18: imem_resp_data<=32'h01002087; // flw f1,16(x0): max finite
      40'h1c: imem_resp_data<=32'h01402107; // flw f2,20(x0): 2.0
      40'h20: imem_resp_data<=32'h102081d3; // fmul.s: OF|NX
      40'h24: imem_resp_data<=32'h01802087; // flw f1,24(x0): min subnormal
      40'h28: imem_resp_data<=32'h01c02107; // flw f2,28(x0): 0.5
      40'h2c: imem_resp_data<=32'h102081d3; // fmul.s: UF|NX
      40'h30: imem_resp_data<=32'h001022f3; // csrr x5,fflags
      40'h34: imem_resp_data<=32'h04503023; // sd x5,64(x0)
      40'h38: imem_resp_data<=32'h0021d073; // csrwi frm,3 (RUP)
      40'h3c: imem_resp_data<=32'h02002087; // flw f1,32(x0): 1.0
      40'h40: imem_resp_data<=32'h02402107; // flw f2,36(x0): 2^-24
      40'h44: imem_resp_data<=32'h0020f1d3; // fadd.s dynamic
      40'h48: imem_resp_data<=32'h04302427; // fsw f3,72(x0)
      40'h4c: imem_resp_data<=32'h002023f3; // csrr x7,frm
      40'h50: imem_resp_data<=32'h04703823; // sd x7,80(x0)
      40'h54: imem_resp_data<=32'h00101073; // csrw fflags,x0
      40'h58: imem_resp_data<=32'h00102473; // csrr x8,fflags
      40'h5c: imem_resp_data<=32'h04803c23; // sd x8,88(x0)
      default: imem_resp_data<=32'h00100073; // ebreak
    endcase

    dmem_resp_valid<=dmem_req_valid;
    case({dmem_req_addr[63:3],3'b000})
      64'h00: dmem_resp_rdata<=64'h3f80_0000_7f80_0001;
      64'h08: dmem_resp_rdata<=64'h0000_0000_3f80_0000;
      64'h10: dmem_resp_rdata<=64'h4000_0000_7f7f_ffff;
      64'h18: dmem_resp_rdata<=64'h3f00_0000_0000_0001;
      64'h20: dmem_resp_rdata<=64'h3380_0000_3f80_0000;
      default: dmem_resp_rdata<=64'd0;
    endcase

    if(dmem_req_valid&&dmem_req_write) begin
      case(dmem_req_addr)
        64'd64: begin
          if(dmem_req_wstrb!=8'hff||dmem_req_wdata!=64'h1f)
            $fatal(1,"fflags did not accumulate all five flags: %h",
                   dmem_req_wdata);
          saw_flags<=1;
        end
        64'd72: begin
          if(dmem_req_wstrb!=8'h0f||dmem_req_wdata[31:0]!=32'h3f800001)
            $fatal(1,"dynamic RUP result mismatch: %h",dmem_req_wdata);
          saw_dynamic<=1;
        end
        64'd80: begin
          if(dmem_req_wstrb!=8'hff||dmem_req_wdata!=64'd3)
            $fatal(1,"frm CSR read mismatch: %h",dmem_req_wdata);
          saw_frm<=1;
        end
        64'd88: begin
          if(dmem_req_wstrb!=8'hff||dmem_req_wdata!=64'd0)
            $fatal(1,"fflags CSR clear mismatch: %h",dmem_req_wdata);
          saw_clear<=1;
        end
        default: $fatal(1,"unexpected store address %h",dmem_req_addr);
      endcase
    end
  end

  initial begin
    repeat(3) @(posedge clk); reset_n<=1;
    timeout=0;
    while(!halted&&timeout<3000) begin @(posedge clk); timeout=timeout+1; end
    if(!halted||illegal||!saw_flags||!saw_dynamic||!saw_frm||!saw_clear)
      $fatal(1,"FCSR integration failed halt=%0d illegal=%0d flags=%0d dyn=%0d frm=%0d clear=%0d pc=%h inst=%h fflags=%h",
             halted,illegal,saw_flags,saw_dynamic,saw_frm,saw_clear,
             dut.ex_pc,dut.ex_inst,dut.fflags_q);
    $display("EDGE_RV_LITE_FCSR TEST PASS"); $finish;
  end
endmodule
