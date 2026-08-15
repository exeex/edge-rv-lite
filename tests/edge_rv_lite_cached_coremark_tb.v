`timescale 1ns/1ps

module edge_rv_lite_cached_coremark_tb;
  localparam integer MEM_BYTES = 1024 * 1024;
  localparam integer MEM_WORDS = MEM_BYTES / 8;
  localparam integer TIMEOUT_CYCLES = 10_000_000;
  // Linux LLVM 19.1.1 baseline for the parent-produced CoreMark image.
  // The LLVM 22.1.8 image is a separate checkpoint at 616228 instructions.
  localparam [63:0] LLVM19_COREMARK_INSTRET = 64'd743510;
  localparam [39:0] MEM_BYTES_40 = 40'd1_048_576;
  localparam [63:0] MEM_BYTES_64 = 64'd1_048_576;

  reg clk = 1'b0;
  reg reset_n = 1'b0;
  always #5 clk = ~clk;

  reg [63:0] mem [0:MEM_WORDS-1];
  string mem64_file;
  integer i;
  integer cycles;
  integer imem_refill_count;
  integer dmem_refill_count;
  integer dmem_writeback_beats;

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
    mem[(dmem_refill_base_q[19:3]) + (dmem_refill_beat_q * 2) + 1],
    mem[(dmem_refill_base_q[19:3]) + (dmem_refill_beat_q * 2)]
  };
  wire dmem_refill_resp_last = dmem_refill_beat_q == 2'd3;
  wire dmem_refill_resp_error = dmem_refill_base_q >= MEM_BYTES_64;

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

  function [31:0] read32;
    input [63:0] addr;
    begin
      read32 = addr[2] ? mem[addr[19:3]][63:32] : mem[addr[19:3]][31:0];
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
    .dmem_refill_resp_error(dmem_refill_resp_error),
    .dmem_clean_wb_valid(dmem_clean_wb_valid),
    .dmem_clean_wb_ready(1'b1),
    .dmem_clean_wb_addr(dmem_clean_wb_addr),
    .dmem_clean_wb_data(dmem_clean_wb_data),
    .dmem_clean_wb_last(dmem_clean_wb_last),
    .dmem_clean_wb_complete(dmem_clean_wb_complete),
    .halted(halted), .illegal(illegal), .debug_x31(debug_x31),
    .cycle_count(cycle_count), .instret_count(instret_count),
    .debug_icache_hit(), .debug_icache_miss_pending(),
    .debug_dcache_load_miss_pending()
  );

  always @(posedge clk) begin
    imem_refill_resp_valid <= 1'b0;
    if (imem_refill_req_valid) begin
      imem_refill_count <= imem_refill_count + 1;
      imem_refill_resp_valid <= 1'b1;
      if (imem_refill_req_addr < MEM_BYTES_40) begin
        imem_refill_resp_data <= {
          read32({24'd0, imem_refill_req_addr} + 64'd12),
          read32({24'd0, imem_refill_req_addr} + 64'd8),
          read32({24'd0, imem_refill_req_addr} + 64'd4),
          read32({24'd0, imem_refill_req_addr})
        };
      end else begin
        imem_refill_resp_data <= {4{32'h0010_0073}};
      end
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

    dmem_clean_wb_complete <= 1'b0;
    if (dmem_clean_wb_valid) begin
      if (dmem_clean_wb_addr < MEM_BYTES_64) begin
        mem[dmem_clean_wb_addr[19:3]] <= dmem_clean_wb_data[63:0];
        mem[dmem_clean_wb_addr[19:3] + 1] <= dmem_clean_wb_data[127:64];
      end
      dmem_writeback_beats <= dmem_writeback_beats + 1;
      if (dmem_clean_wb_last) dmem_clean_wb_complete <= 1'b1;
    end
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
    dmem_writeback_beats = 0;
    for (i = 0; i < MEM_WORDS; i = i + 1) mem[i] = 64'd0;
    if (!$value$plusargs("mem64=%s", mem64_file))
      $fatal(1, "pass +mem64=<coremark_bench.data64.memh>");
    $readmemh(mem64_file, mem);

    repeat (4) @(posedge clk);
    reset_n <= 1'b1;
    cycles = 0;
    while (!halted && cycles < TIMEOUT_CYCLES) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    $display("cached CoreMark halt=%0d illegal=%0d pc=%h inst=%h x31=%0d cycles=%0d instret=%0d I$refill=%0d D$refill=%0d wb=%0d",
             halted, illegal, dut.core.ex_pc, dut.core.ex_inst, debug_x31,
             cycle_count, instret_count, imem_refill_count,
             dmem_refill_count, dmem_writeback_beats);
    if (!halted) $fatal(1, "cached CoreMark timeout instret=%0d", instret_count);
    if (illegal)
      $fatal(1, "cached CoreMark illegal pc=%h inst=%h", dut.core.ex_pc,
             dut.core.ex_inst);
    if (debug_x31 == 0) $fatal(1, "cached CoreMark returned zero");
    if (instret_count != LLVM19_COREMARK_INSTRET)
      $fatal(1, "cached CoreMark instret mismatch=%0d", instret_count);
    if (imem_refill_count == 0 || dmem_refill_count == 0)
      $fatal(1, "cached CoreMark did not use both caches");
    $display("PASS: cached edge-rv-lite CoreMark x31=%0d cycles=%0d instret=%0d I$refill=%0d D$refill=%0d wb_beats=%0d",
             debug_x31, cycle_count, instret_count, imem_refill_count,
             dmem_refill_count, dmem_writeback_beats);
    $finish;
  end
endmodule
