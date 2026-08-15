`timescale 1ns/1ps

module edge_rv_lite_halt_tb;
  localparam integer EBREAK_CASE = 1;
  localparam integer ILLEGAL_CASE = 2;
  localparam integer FORMER_MAILBOX_STORE_CASE = 3;
  localparam [63:0] FORMER_MAILBOX_ADDR = 64'h0000_0000_0000_2ee8;

  reg clk = 0;
  always #5 clk = ~clk;
  reg reset_n = 0;
  integer test_case = 0;
  integer dmem_requests = 0;
  integer timeout;
  reg [63:0] halted_instret;
  reg [39:0] halted_pc;
  reg last_dmem_write;
  reg [63:0] last_dmem_addr;
  reg [63:0] last_dmem_wdata;
  reg [7:0] last_dmem_wstrb;

  wire imem_req_valid;
  wire [39:0] imem_req_addr;
  reg imem_resp_valid = 0;
  reg [31:0] imem_resp_data = 0;
  wire dmem_req_valid;
  wire dmem_req_write;
  wire [63:0] dmem_req_addr;
  wire [63:0] dmem_req_wdata;
  wire [7:0] dmem_req_wstrb;
  reg dmem_resp_valid = 0;
  wire cache_op_valid;
  wire accel_req_valid;
  wire halted, illegal;
  wire [63:0] instret_count;

  edge_rv_lite_core dut(
    .clk(clk), .reset_n(reset_n),
    .imem_req_valid(imem_req_valid), .imem_req_ready(1'b1),
    .imem_req_addr(imem_req_addr), .imem_resp_valid(imem_resp_valid),
    .imem_resp_data(imem_resp_data), .imem_resp_error(1'b0),
    .dmem_req_valid(dmem_req_valid), .dmem_req_ready(1'b1),
    .dmem_req_write(dmem_req_write), .dmem_req_addr(dmem_req_addr),
    .dmem_req_wdata(dmem_req_wdata), .dmem_req_wstrb(dmem_req_wstrb),
    .dmem_req_size(), .dmem_req_signed(),
    .dmem_resp_valid(dmem_resp_valid), .dmem_resp_error(1'b0),
    .dmem_resp_rdata(64'b0),
    .cache_op_valid(cache_op_valid), .cache_op_ready(1'b1),
    .cache_op_is_va(), .cache_op_kind(), .cache_op_addr(),
    .cache_op_complete_valid(1'b0),
    .icache_invalidate_valid(), .icache_invalidate_ready(1'b1),
    .icache_invalidate_complete(1'b1),
    .accel_req_valid(accel_req_valid), .accel_req_ready(1'b1),
    .accel_req_inst(), .accel_req_src0(), .accel_req_src1(),
    .accel_resp_valid(1'b0), .accel_resp_error(1'b0),
    .accel_resp_value(64'b0),
    .halted(halted), .illegal(illegal), .debug_x31(), .cycle_count(),
    .instret_count(instret_count));

  always @(posedge clk) begin
    imem_resp_valid <= imem_req_valid;
    dmem_resp_valid <= dmem_req_valid;
    case (test_case)
      EBREAK_CASE: begin
        case (imem_req_addr)
          40'h0: imem_resp_data <= 32'h0010_0073; // ebreak
          40'h4: imem_resp_data <= 32'h02a0_0293; // addi x5,x0,42
          default: imem_resp_data <= 32'h0050_3023; // sd x5,0(x0)
        endcase
      end
      ILLEGAL_CASE: begin
        imem_resp_data <= imem_req_addr == 0 ?
          32'hffff_ffff : 32'h0050_3023; // illegal; sd x5,0(x0)
      end
      FORMER_MAILBOX_STORE_CASE: begin
        case (imem_req_addr)
          40'h00: imem_resp_data <= 32'h0000_32b7; // lui x5,0x3
          40'h04: imem_resp_data <= 32'hee82_8293; // addi x5,x5,-280
          40'h08: imem_resp_data <= 32'h02a0_0313; // addi x6,x0,42
          40'h0c: imem_resp_data <= 32'h0062_b023; // sd x6,0(x5)
          40'h10: imem_resp_data <= 32'h0070_0393; // addi x7,x0,7
          default: imem_resp_data <= 32'h0010_0073; // ebreak
        endcase
      end
      default: imem_resp_data <= 32'h0010_0073;
    endcase
    if (dmem_req_valid) begin
      dmem_requests <= dmem_requests + 1;
      last_dmem_write <= dmem_req_write;
      last_dmem_addr <= dmem_req_addr;
      last_dmem_wdata <= dmem_req_wdata;
      last_dmem_wstrb <= dmem_req_wstrb;
    end
    if (reset_n && halted) begin
      if (imem_req_valid || dmem_req_valid || cache_op_valid || accel_req_valid)
        $fatal(1, "halted core emitted an external request");
      if (dut.wb_valid || dut.ex_issue_ok)
        $fatal(1, "halted core retained writeback or issue activity");
    end
  end

  task run_case;
    input integer selected_case;
    input [63:0] expected_instret;
    input expected_illegal;
    input integer expected_dmem_requests;
    begin
      reset_n = 0;
      test_case = selected_case;
      dmem_requests = 0;
      last_dmem_write = 1'b0;
      last_dmem_addr = 64'd0;
      last_dmem_wdata = 64'd0;
      last_dmem_wstrb = 8'd0;
      imem_resp_valid = 0;
      dmem_resp_valid = 0;
      repeat (3) @(posedge clk);
      @(negedge clk);
      reset_n = 1;
      timeout = 0;
      while (!halted && timeout < 100) begin
        @(posedge clk);
        timeout = timeout + 1;
      end
      if (!halted || illegal != expected_illegal)
        $fatal(1, "case %0d terminal mismatch halt=%0d illegal=%0d pc=%h inst=%h instret=%0d dmem=%0d",
               selected_case, halted, illegal, dut.ex_pc, dut.ex_inst,
               instret_count, dmem_requests);
      halted_instret = instret_count;
      halted_pc = dut.ex_pc;
      repeat (10) begin
        @(posedge clk);
        if (instret_count != halted_instret || dut.ex_pc != halted_pc)
          $fatal(1, "case %0d architectural state changed after halt",
                 selected_case);
      end
      if (halted_instret != expected_instret ||
          dmem_requests != expected_dmem_requests)
        $fatal(1, "case %0d retire/request mismatch instret=%0d dmem=%0d",
               selected_case, halted_instret, dmem_requests);
      if (selected_case == FORMER_MAILBOX_STORE_CASE &&
          (!last_dmem_write || last_dmem_addr != FORMER_MAILBOX_ADDR ||
           last_dmem_wdata != 64'd42 || last_dmem_wstrb != 8'hff ||
           dut.gpr[7] != 64'd7))
        $fatal(1, "former mailbox address was not an ordinary store");
    end
  endtask

  initial begin
    run_case(EBREAK_CASE, 64'd1, 1'b0, 0);
    run_case(ILLEGAL_CASE, 64'd0, 1'b1, 0);
    run_case(FORMER_MAILBOX_STORE_CASE, 64'd6, 1'b0, 1);
    $display("TEST PASS: terminal halt is quiescent and former mailbox stores are ordinary");
    $finish;
  end
endmodule
