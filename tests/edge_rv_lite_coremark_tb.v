`timescale 1ns/1ps

module edge_rv_lite_coremark_tb;
  localparam integer MEM_BYTES = 1024 * 1024;
  localparam integer MEM_WORDS = MEM_BYTES / 8;
  localparam [63:0] SIM_EXIT_ADDR = 64'h0000_0000_0000_2ee8;
  localparam [63:0] TOHOST_ADDR = 64'h0000_0000_0000_2ef0;
  localparam integer TIMEOUT_CYCLES = 10_000_000;

  reg clk = 1'b0;
  reg reset_n = 1'b0;
  always #5 clk = ~clk;

  reg [63:0] mem [0:MEM_WORDS-1];
  string mem64_file;
  integer i;
  integer cycles;

  wire imem_req_valid;
  wire [39:0] imem_req_addr;
  reg imem_resp_valid;
  reg [31:0] imem_resp_data;
  reg imem_resp_error;

  wire dmem_req_valid;
  wire dmem_req_write;
  wire [63:0] dmem_req_addr;
  wire [63:0] dmem_req_wdata;
  wire [7:0] dmem_req_wstrb;
  reg dmem_resp_valid;
  reg dmem_resp_error;
  reg [63:0] dmem_resp_rdata;

  wire halted;
  wire illegal;
  wire [63:0] debug_x31;
  wire [63:0] cycle_count;
  wire [63:0] instret_count;

  edge_rv_lite_core dut (
    .clk(clk), .reset_n(reset_n),
    .imem_req_valid(imem_req_valid), .imem_req_ready(1'b1),
    .imem_req_addr(imem_req_addr), .imem_resp_valid(imem_resp_valid),
    .imem_resp_data(imem_resp_data), .imem_resp_error(imem_resp_error),
    .dmem_req_valid(dmem_req_valid), .dmem_req_ready(1'b1),
    .dmem_req_write(dmem_req_write), .dmem_req_addr(dmem_req_addr),
    .dmem_req_wdata(dmem_req_wdata), .dmem_req_wstrb(dmem_req_wstrb),
    .dmem_req_size(), .dmem_req_signed(),
    .dmem_resp_valid(dmem_resp_valid), .dmem_resp_error(dmem_resp_error),
    .dmem_resp_rdata(dmem_resp_rdata), .halted(halted), .illegal(illegal),
    .debug_x31(debug_x31), .cycle_count(cycle_count),
    .instret_count(instret_count)
  );

  always @(posedge clk) begin
    imem_resp_valid <= 1'b0;
    imem_resp_error <= 1'b0;
    if (imem_req_valid) begin
      imem_resp_valid <= 1'b1;
      if (imem_req_addr < 40'(MEM_BYTES)) begin
        if (imem_req_addr[2])
          imem_resp_data <= mem[imem_req_addr[19:3]][63:32];
        else
          imem_resp_data <= mem[imem_req_addr[19:3]][31:0];
      end else begin
        imem_resp_data <= 32'h0010_0073;
        imem_resp_error <= 1'b1;
      end
    end

    dmem_resp_valid <= 1'b0;
    dmem_resp_error <= 1'b0;
    if (dmem_req_valid) begin
      dmem_resp_valid <= 1'b1;
      if (dmem_req_addr < 64'(MEM_BYTES)) begin
        dmem_resp_rdata <= mem[dmem_req_addr[19:3]];
        if (dmem_req_write) begin
          for (i = 0; i < 8; i = i + 1)
            if (dmem_req_wstrb[i])
              mem[dmem_req_addr[19:3]][i*8 +: 8] <=
                dmem_req_wdata[i*8 +: 8];
        end
      end else begin
        dmem_resp_rdata <= 64'd0;
        dmem_resp_error <= 1'b1;
      end
    end
  end

  initial begin
    imem_resp_valid = 1'b0;
    imem_resp_data = 32'h0000_0013;
    imem_resp_error = 1'b0;
    dmem_resp_valid = 1'b0;
    dmem_resp_error = 1'b0;
    dmem_resp_rdata = 64'd0;
    for (i = 0; i < MEM_WORDS; i = i + 1) mem[i] = 64'd0;
    if (!$value$plusargs("mem64=%s", mem64_file)) begin
      $display("FAIL: pass +mem64=<coremark_bench.data64.memh>");
      $fatal(1);
    end
    $readmemh(mem64_file, mem);

    repeat (4) @(posedge clk);
    reset_n <= 1'b1;
    cycles = 0;
    while (!halted && cycles < TIMEOUT_CYCLES) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    if (!halted) begin
      $display("FAIL: timeout pc=%h instret=%0d", dut.ex_pc, instret_count);
      $fatal(1);
    end
    if (illegal) begin
      $display("FAIL: illegal instruction pc=%h inst=%h", dut.ex_pc, dut.ex_inst);
      $fatal(1);
    end
    if (mem[SIM_EXIT_ADDR[19:3]] !== debug_x31) begin
      $display("FAIL: exit memory=%h x31=%h", mem[SIM_EXIT_ADDR[19:3]], debug_x31);
      $fatal(1);
    end
    if (mem[TOHOST_ADDR[19:3]] !== ((debug_x31 << 1) | 64'd1)) begin
      $display("FAIL: tohost=%h expected=%h", mem[TOHOST_ADDR[19:3]],
               ((debug_x31 << 1) | 64'd1));
      $fatal(1);
    end
    if (debug_x31 == 0) begin
      $display("FAIL: CoreMark returned a zero cycle count");
      $fatal(1);
    end
    $display("PASS: edge-rv-lite CoreMark x31=%0d cycles=%0d instret=%0d",
             debug_x31, cycle_count, instret_count);
    $finish;
  end
endmodule
