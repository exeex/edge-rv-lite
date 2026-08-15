`timescale 1ns/1ps
module edge_rv_lite_lsu_tb;
  reg clk = 0; always #5 clk = ~clk;
  reg reset_n = 0, op_valid = 0, op_store = 0, op_fp = 0;
  reg [2:0] op_funct3 = 0;
  reg [63:0] op_base = 0, op_offset = 0, op_store_data = 0;
  wire op_ready, mem_req_valid, mem_req_write;
  reg mem_req_ready = 0;
  wire [63:0] mem_req_addr, mem_req_wdata; wire [7:0] mem_req_wstrb;
  wire [1:0] mem_req_size; wire mem_req_signed;
  reg mem_resp_valid = 0, mem_resp_error = 0;
  reg [63:0] mem_resp_rdata = 0;
  wire op_done, op_error; wire [63:0] op_load_value; wire busy;
  edge_rv_lite_lsu dut(.*);

  task check_legal_access;
    input store;
    input [2:0] funct3;
    input [3:0] offset;
    input [7:0] expected_strobe;
    begin
      @(negedge clk);
      if (!op_ready) $fatal(1, "LSU not ready for legal boundary access");
      op_valid = 1'b1;
      op_store = store;
      op_fp = 1'b0;
      op_funct3 = funct3;
      op_base = 64'h3000;
      op_offset = {60'd0, offset};
      op_store_data = 64'h8877_6655_4433_2211;
      @(posedge clk); #1;
      op_valid = 1'b0;
      if (!mem_req_valid ||
          mem_req_addr != 64'h3000 + {60'd0, offset} ||
          mem_req_size != funct3[1:0])
        $fatal(1, "legal boundary access did not issue size=%0d off=%0d",
               funct3[1:0], offset);
      if (store && mem_req_wstrb != expected_strobe)
        $fatal(1, "legal store strobe size=%0d off=%0d got=%h",
               funct3[1:0], offset, mem_req_wstrb);
      mem_req_ready = 1'b1;
      @(posedge clk); #1;
      mem_req_ready = 1'b0;
      mem_resp_rdata = 64'h8877_6655_4433_2211;
      mem_resp_error = 1'b0;
      mem_resp_valid = 1'b1;
      @(posedge clk); #1;
      mem_resp_valid = 1'b0;
      if (!op_done || op_error)
        $fatal(1, "legal boundary access faulted size=%0d off=%0d",
               funct3[1:0], offset);
    end
  endtask

  task check_misaligned_fault;
    input store;
    input [2:0] funct3;
    input [3:0] offset;
    begin
      @(negedge clk);
      if (!op_ready) $fatal(1, "LSU not ready for misaligned access");
      op_valid = 1'b1;
      op_store = store;
      op_fp = 1'b0;
      op_funct3 = funct3;
      op_base = 64'h4000;
      op_offset = {60'd0, offset};
      op_store_data = 64'hffff_ffff_ffff_ffff;
      @(posedge clk); #1;
      op_valid = 1'b0;
      if (!op_done || !op_error || mem_req_valid || busy)
        $fatal(1, "misaligned access escaped size=%0d off=%0d store=%0d",
               funct3[1:0], offset, store);
    end
  endtask

  initial begin
    repeat (2) @(posedge clk); reset_n <= 1;
    // Signed byte load at byte offset 3; request backpressure must hold payload.
    @(posedge clk); op_valid <= 1; op_funct3 <= 3'b000;
    op_base <= 64'h1000; op_offset <= 3; op_store <= 0;
    @(posedge clk); op_valid <= 0;
    repeat (2) begin
      @(posedge clk);
      if (!mem_req_valid || mem_req_addr != 64'h1003 || op_ready)
        begin $display("load request was not held"); $finish; end
    end
    mem_req_ready <= 1; @(posedge clk); mem_req_ready <= 0;
    repeat (2) begin
      @(posedge clk);
      if (!busy || op_ready || op_done)
        begin $display("load did not wait for response"); $finish; end
    end
    mem_resp_rdata <= 64'h0000_0080_0000_0000; mem_resp_valid <= 1;
    @(posedge clk); mem_resp_valid <= 0;
    if (!op_done || op_load_value != 64'hffff_ffff_ffff_ff80)
      begin $display("bad signed load result %h", op_load_value); $finish; end

    // Store is also not complete at request acceptance; wait for write ack.
    @(posedge clk); op_valid <= 1; op_store <= 1;
    op_funct3 <= 3'b010; op_base <= 64'h2000; op_offset <= 4;
    op_store_data <= 64'h0000_0000_aabb_ccdd;
    @(posedge clk); op_valid <= 0;
    wait (mem_req_valid); mem_req_ready <= 1; @(posedge clk); mem_req_ready <= 0;
    if (op_done || !busy || mem_req_wstrb != 8'hf0)
      begin $display("store completed before ack or bad strobe"); $finish; end
    repeat (2) @(posedge clk);
    mem_resp_valid <= 1; @(posedge clk); mem_resp_valid <= 0;
    if (!op_done || op_error)
      begin $display("store ack did not complete"); $finish; end

    // Byte offset 7 is the last byte in a word; offset 8 starts the next word.
    check_legal_access(1'b0, 3'b000, 4'd7, 8'h80);
    check_legal_access(1'b1, 3'b000, 4'd7, 8'h80);
    check_legal_access(1'b0, 3'b000, 4'd8, 8'h01);
    check_legal_access(1'b1, 3'b000, 4'd8, 8'h01);

    // Last in-word aligned access and first boundary-crossing offset per size.
    check_legal_access(1'b0, 3'b001, 4'd6, 8'hc0);
    check_legal_access(1'b1, 3'b001, 4'd6, 8'hc0);
    check_misaligned_fault(1'b0, 3'b001, 4'd1);
    check_misaligned_fault(1'b1, 3'b001, 4'd1);
    check_misaligned_fault(1'b0, 3'b001, 4'd7);
    check_misaligned_fault(1'b1, 3'b001, 4'd7);
    check_legal_access(1'b0, 3'b010, 4'd4, 8'hf0);
    check_legal_access(1'b1, 3'b010, 4'd4, 8'hf0);
    check_misaligned_fault(1'b0, 3'b010, 4'd2);
    check_misaligned_fault(1'b1, 3'b010, 4'd2);
    check_misaligned_fault(1'b0, 3'b010, 4'd5);
    check_misaligned_fault(1'b1, 3'b010, 4'd5);
    check_legal_access(1'b0, 3'b011, 4'd0, 8'hff);
    check_legal_access(1'b1, 3'b011, 4'd0, 8'hff);
    check_misaligned_fault(1'b0, 3'b011, 4'd4);
    check_misaligned_fault(1'b1, 3'b011, 4'd4);
    check_misaligned_fault(1'b0, 3'b011, 4'd1);
    check_misaligned_fault(1'b1, 3'b011, 4'd1);

    $display("TEST PASS: LSU waits for responses and traps misaligned accesses");
    $finish;
  end
endmodule
