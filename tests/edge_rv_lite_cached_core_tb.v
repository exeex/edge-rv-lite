`timescale 1ns/1ps

module edge_rv_lite_cached_core_tb;
  reg clk = 1'b0;
  reg reset_n = 1'b0;
  always #5 clk = ~clk;

  reg [63:0] mem [0:127];
  integer i;
  integer cycles;
  integer imem_refill_count;
  integer dmem_refill_count;
  integer icache_hit_count;
  reg saw_dcache_miss;

  wire imem_refill_req_valid;
  wire [39:0] imem_refill_req_addr;
  reg imem_refill_resp_valid;
  wire imem_refill_resp_ready;
  reg [127:0] imem_refill_resp_data;

  wire dmem_refill_req_valid;
  wire [63:0] dmem_refill_req_addr;
  reg dmem_refill_active_q;
  reg [63:0] dmem_refill_base_q;
  reg [1:0] dmem_refill_beat_q;
  wire dmem_refill_resp_valid = dmem_refill_active_q;
  wire dmem_refill_resp_ready;
  wire [127:0] dmem_refill_resp_data = {
    mem[(dmem_refill_base_q[9:3]) + (dmem_refill_beat_q * 2) + 1],
    mem[(dmem_refill_base_q[9:3]) + (dmem_refill_beat_q * 2)]
  };
  wire dmem_refill_resp_last = dmem_refill_beat_q == 2'd3;

  wire dmem_clean_wb_valid;
  wire [63:0] dmem_clean_wb_addr;
  wire [127:0] dmem_clean_wb_data;
  wire dmem_clean_wb_last;
  reg dmem_clean_wb_complete;

  wire halted;
  wire illegal;
  wire [63:0] debug_x31;
  wire [63:0] cycle_count;
  wire [63:0] instret_count;
  wire debug_icache_hit;
  wire debug_icache_miss_pending;
  wire debug_dcache_load_miss_pending;

  function [31:0] read32;
    input [63:0] addr;
    begin
      read32 = addr[2] ? mem[addr[9:3]][63:32] : mem[addr[9:3]][31:0];
    end
  endfunction

  edge_rv_lite_cached_core dut (
    .clk(clk), .reset_n(reset_n),
    .imem_refill_req_valid(imem_refill_req_valid),
    .imem_refill_req_ready(1'b1),
    .imem_refill_req_addr(imem_refill_req_addr),
    .imem_refill_resp_valid(imem_refill_resp_valid),
    .imem_refill_resp_ready(imem_refill_resp_ready),
    .imem_refill_resp_data(imem_refill_resp_data),
    .imem_refill_resp_error(1'b0),
    .dmem_refill_req_valid(dmem_refill_req_valid),
    .dmem_refill_req_ready(1'b1),
    .dmem_refill_req_addr(dmem_refill_req_addr),
    .dmem_refill_resp_valid(dmem_refill_resp_valid),
    .dmem_refill_resp_ready(dmem_refill_resp_ready),
    .dmem_refill_resp_data(dmem_refill_resp_data),
    .dmem_refill_resp_last(dmem_refill_resp_last),
    .dmem_refill_resp_error(1'b0),
    .dmem_clean_wb_valid(dmem_clean_wb_valid),
    .dmem_clean_wb_ready(1'b1),
    .dmem_clean_wb_addr(dmem_clean_wb_addr),
    .dmem_clean_wb_data(dmem_clean_wb_data),
    .dmem_clean_wb_last(dmem_clean_wb_last),
    .dmem_clean_wb_complete(dmem_clean_wb_complete),
    .halted(halted), .illegal(illegal), .debug_x31(debug_x31),
    .cycle_count(cycle_count), .instret_count(instret_count),
    .debug_icache_hit(debug_icache_hit),
    .debug_icache_miss_pending(debug_icache_miss_pending),
    .debug_dcache_load_miss_pending(debug_dcache_load_miss_pending)
  );

  always @(posedge clk) begin
    imem_refill_resp_valid <= 1'b0;
    if (imem_refill_req_valid) begin
      imem_refill_count <= imem_refill_count + 1;
      imem_refill_resp_valid <= 1'b1;
      imem_refill_resp_data <= {
        read32({24'd0, imem_refill_req_addr} + 64'd12),
        read32({24'd0, imem_refill_req_addr} + 64'd8),
        read32({24'd0, imem_refill_req_addr} + 64'd4),
        read32({24'd0, imem_refill_req_addr})
      };
    end

    if (dmem_refill_req_valid && !dmem_refill_active_q) begin
      dmem_refill_active_q <= 1'b1;
      dmem_refill_base_q <= dmem_refill_req_addr;
      dmem_refill_beat_q <= 2'd0;
      dmem_refill_count <= dmem_refill_count + 1;
    end else if (dmem_refill_resp_valid && dmem_refill_resp_ready) begin
      if (dmem_refill_resp_last) dmem_refill_active_q <= 1'b0;
      else dmem_refill_beat_q <= dmem_refill_beat_q + 1'b1;
    end

    dmem_clean_wb_complete <= dmem_clean_wb_valid && dmem_clean_wb_last;
    if (debug_icache_hit) icache_hit_count <= icache_hit_count + 1;
    if (debug_dcache_load_miss_pending) saw_dcache_miss <= 1'b1;
  end

  initial begin
    imem_refill_resp_valid = 1'b0;
    imem_refill_resp_data = 128'd0;
    dmem_refill_active_q = 1'b0;
    dmem_refill_base_q = 64'd0;
    dmem_refill_beat_q = 2'd0;
    dmem_clean_wb_complete = 1'b0;
    imem_refill_count = 0;
    dmem_refill_count = 0;
    icache_hit_count = 0;
    saw_dcache_miss = 1'b0;
    for (i = 0; i < 128; i = i + 1) mem[i] = 64'd0;

    // addi x1,x0,0x100; ld x2,0(x1); addi x2,x2,1;
    // sd x2,0(x1); ld x31,0(x1); ebreak.
    mem[0] = {32'h0000_b103, 32'h1000_0093};
    mem[1] = {32'h0020_b023, 32'h0011_0113};
    mem[2] = {32'h0010_0073, 32'h0000_bf83};
    mem[3] = {32'h0000_0013, 32'h0000_0013};
    mem[32] = 64'd41;

    repeat (4) @(posedge clk);
    reset_n <= 1'b1;
    cycles = 0;
    while (!halted && cycles < 500) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    if (!halted) $fatal(1, "cached lite core timeout");
    if (illegal) $fatal(1, "cached lite core reported illegal instruction");
    if (debug_x31 != 64'd42)
      $fatal(1, "cached load/store result mismatch x31=%0d", debug_x31);
    if (dmem_refill_count != 1 || !saw_dcache_miss)
      $fatal(1, "D-cache miss/refill not observed count=%0d", dmem_refill_count);
    if (imem_refill_count < 2 || icache_hit_count == 0)
      $fatal(1, "I-cache miss/hit path not observed refill=%0d hit=%0d",
             imem_refill_count, icache_hit_count);
    if (dmem_clean_wb_valid)
      $fatal(1, "unexpected D-cache writeback in no-eviction test");
    $display("TEST PASS: cached lite core I$refill=%0d I$hit=%0d D$refill=%0d cycles=%0d instret=%0d",
             imem_refill_count, icache_hit_count, dmem_refill_count,
             cycle_count, instret_count);
    $finish;
  end
endmodule
