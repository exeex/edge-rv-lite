`timescale 1ns/1ps

module edge_rv_lite_fault_tb;
  localparam integer FETCH_ALU_FAULT = 1;
  localparam integer FETCH_STORE_FAULT = 2;
  localparam integer LOAD_RESP_FAULT = 3;
  localparam integer ACCEL_RESP_FAULT = 4;
  localparam integer RESERVED_OP32_M = 5;
  localparam integer CACHE_INDEX_NONZERO_RS1 = 6;
  localparam integer CACHE_NONZERO_FUNCT7 = 7;
  localparam integer INVALID_FP_MEM = 8;

  reg clk = 0;
  always #5 clk = ~clk;
  reg reset_n = 0;
  integer test_case = 0;
  integer dmem_requests = 0;
  integer accel_requests = 0;
  integer cache_requests = 0;
  integer timeout;

  wire imem_req_valid;
  wire [39:0] imem_req_addr;
  reg imem_resp_valid = 0;
  reg [31:0] imem_resp_data = 0;
  reg imem_resp_error = 0;
  wire dmem_req_valid;
  reg dmem_resp_valid = 0;
  reg dmem_resp_error = 0;
  wire accel_req_valid;
  wire cache_op_valid;
  reg accel_resp_valid = 0;
  reg accel_resp_error = 0;
  wire halted, illegal;
  wire [63:0] instret_count;

  edge_rv_lite_core #(.ENABLE_FPU(1)) dut(
    .clk(clk), .reset_n(reset_n),
    .imem_req_valid(imem_req_valid), .imem_req_ready(1'b1),
    .imem_req_addr(imem_req_addr), .imem_resp_valid(imem_resp_valid),
    .imem_resp_data(imem_resp_data), .imem_resp_error(imem_resp_error),
    .dmem_req_valid(dmem_req_valid), .dmem_req_ready(1'b1),
    .dmem_req_write(), .dmem_req_addr(), .dmem_req_wdata(),
    .dmem_req_wstrb(), .dmem_req_size(), .dmem_req_signed(),
    .dmem_resp_valid(dmem_resp_valid), .dmem_resp_error(dmem_resp_error),
    .dmem_resp_rdata(64'hfeed_face_dead_beef),
    .cache_op_valid(cache_op_valid), .cache_op_ready(1'b1), .cache_op_is_va(),
    .cache_op_kind(), .cache_op_addr(), .cache_op_complete_valid(1'b0),
    .accel_req_valid(accel_req_valid), .accel_req_ready(1'b1),
    .accel_req_inst(), .accel_req_src0(), .accel_req_src1(),
    .accel_resp_valid(accel_resp_valid),
    .accel_resp_error(accel_resp_error),
    .accel_resp_value(64'h0123_4567_89ab_cdef),
    .halted(halted), .illegal(illegal), .debug_x31(), .cycle_count(),
    .instret_count(instret_count));

  always @(posedge clk) begin
    imem_resp_valid <= imem_req_valid;
    imem_resp_error <= 1'b0;
    case (test_case)
      FETCH_ALU_FAULT: begin
        imem_resp_data <= 32'h02a0_0293; // addi x5,x0,42
        imem_resp_error <= imem_req_valid;
      end
      FETCH_STORE_FAULT: begin
        imem_resp_data <= 32'h0000_3023; // sd x0,0(x0)
        imem_resp_error <= imem_req_valid;
      end
      LOAD_RESP_FAULT: begin
        imem_resp_data <= imem_req_addr == 0 ?
          32'h0000_3283 : 32'h0010_0073; // ld x5,0(x0); ebreak
      end
      ACCEL_RESP_FAULT: begin
        case (imem_req_addr)
          40'h0: imem_resp_data <= 32'h0000_02bf; // tensor.getcsr rd=x5 low
          40'h4: imem_resp_data <= 32'h0000_00af; // tensor.getcsr high
          default: imem_resp_data <= 32'h0010_0073;
        endcase
      end
      RESERVED_OP32_M: begin
        // funct7=1/funct3=1 is reserved in RV64 OP-32 (not MULW/DIVW/REMW).
        imem_resp_data <= 32'h0200_12bb;
      end
      CACHE_INDEX_NONZERO_RS1: begin
        // Index cache operations require rs1=x0.
        imem_resp_data <= 32'h0010_800b;
      end
      CACHE_NONZERO_FUNCT7: begin
        // Cache operations reserve every nonzero funct7.
        imem_resp_data <= 32'h0210_000b;
      end
      INVALID_FP_MEM: begin
        // LOAD_FP funct3=000 is unallocated.
        imem_resp_data <= 32'h0000_0287;
      end
      default: imem_resp_data <= 32'h0010_0073;
    endcase

    dmem_resp_valid <= dmem_req_valid;
    dmem_resp_error <= dmem_req_valid && test_case == LOAD_RESP_FAULT;
    if (dmem_req_valid) dmem_requests <= dmem_requests + 1;

    accel_resp_valid <= accel_req_valid;
    accel_resp_error <= accel_req_valid && test_case == ACCEL_RESP_FAULT;
    if (accel_req_valid) accel_requests <= accel_requests + 1;
    if (cache_op_valid) cache_requests <= cache_requests + 1;
  end

  task start_case;
    input integer selected_case;
    begin
      reset_n = 0;
      test_case = selected_case;
      dmem_requests = 0;
      accel_requests = 0;
      cache_requests = 0;
      imem_resp_valid = 0;
      imem_resp_error = 0;
      dmem_resp_valid = 0;
      dmem_resp_error = 0;
      accel_resp_valid = 0;
      accel_resp_error = 0;
      repeat (3) @(posedge clk);
      @(negedge clk);
      reset_n = 1;
      timeout = 0;
      while (!halted && timeout < 100) begin
        @(posedge clk);
        timeout = timeout + 1;
      end
      if (!halted || !illegal)
        $fatal(1, "case %0d did not halt as a fault", selected_case);
      if (instret_count != 0)
        $fatal(1, "case %0d retired faulting instruction count=%0d",
               selected_case, instret_count);
      if (dut.gpr[5] != 0)
        $fatal(1, "case %0d wrote x5=%h", selected_case, dut.gpr[5]);
    end
  endtask

  initial begin
    start_case(FETCH_ALU_FAULT);
    start_case(FETCH_STORE_FAULT);
    if (dmem_requests != 0)
      $fatal(1, "fetch-faulted store issued %0d memory requests", dmem_requests);
    start_case(LOAD_RESP_FAULT);
    if (dmem_requests != 1)
      $fatal(1, "errored load request count=%0d", dmem_requests);
    start_case(ACCEL_RESP_FAULT);
    if (accel_requests != 1)
      $fatal(1, "errored accelerator request count=%0d", accel_requests);
    start_case(RESERVED_OP32_M);
    start_case(CACHE_INDEX_NONZERO_RS1);
    if (cache_requests != 0)
      $fatal(1, "invalid cache index op issued %0d requests", cache_requests);
    start_case(CACHE_NONZERO_FUNCT7);
    if (cache_requests != 0)
      $fatal(1, "invalid cache funct7 issued %0d requests", cache_requests);
    start_case(INVALID_FP_MEM);
    if (dmem_requests != 0)
      $fatal(1, "invalid FP memory op issued %0d requests", dmem_requests);
    $display("TEST PASS: faults and reserved scalar/cache encodings stop cleanly");
    $finish;
  end
endmodule
