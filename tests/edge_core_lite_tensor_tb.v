`timescale 1ns/1ps

module edge_core_lite_tensor_tb;
  localparam integer TIMEOUT_CYCLES = 2_500_000;

  reg clk = 1'b0;
  reg reset_n = 1'b0;
  always #5 clk = ~clk;

  wire [39:0] araddr, awaddr;
  wire [1:0] arburst, awburst;
  wire [3:0] arcache, awcache;
  wire [7:0] arid, awid, arlen, awlen, rid, bid;
  wire arlock, awlock, arvalid, arready, rlast, rready, rvalid;
  wire [2:0] arprot, arsize, awprot, awsize;
  wire [127:0] rdata, wdata;
  wire [1:0] rresp, bresp;
  wire awvalid, awready, bready, bvalid, wlast, wready, wvalid;
  wire [15:0] wstrb;
  wire halted, illegal, tensor_busy, actu_busy, cmpu_busy, accel_dma_busy;
  wire [63:0] debug_x31, cycle_count, instret_count;
  integer cycles;
  integer word_i;
  reg return_only;
  reg trace_cmd;
  reg check_matmul64;
  reg check_matmul128;

  always @(posedge clk) begin
    if (trace_cmd && dut.platform.req_valid && dut.platform.req_ready)
      $display("lite accel inst=%h capture=%h", dut.platform.req_inst,
               dut.platform.req_capture_value);
    if (trace_cmd && dut.platform.dtcm_dma_start_req)
      $display("lite dma src=%h dst=%h len=%0d", dut.platform.dma_start_addr_src,
               dut.platform.dma_start_addr_dst, dut.platform.dtcm_dma_start_len);
    if (trace_cmd && dut.platform.tensor_unit_cmd_wld_req)
      $display("lite wld ptr=%h trans=0", dut.platform.tensor_unit_cmd_wld_ptr);
    if (trace_cmd && dut.platform.tensor_unit_cmd_wld_trans_req)
      $display("lite wld ptr=%h trans=1", dut.platform.tensor_unit_cmd_wld_ptr);
  end

  function [127:0] expected_word;
    input integer index;
    begin
      case ((index * 8) % 13)
        0: expected_word=128'h4040c188c1e0c1f0c1b8c0e041904250;
        1: expected_word=128'h40c0c170c1d8c1f0c1c0c11041704240;
        2: expected_word=128'h4110c150c1d0c1f0c1c8c13041404230;
        3: expected_word=128'h4140c130c1c8c1f0c1d0c15041104220;
        4: expected_word=128'h4170c110c1c0c1f0c1d8c17040c04210;
        5: expected_word=128'h4190c0e0c1b8c1f0c1e0c18840404200;
        6: expected_word=128'h429242084080c188c1e8c200c1d0c130;
        7: expected_word=128'h41c042b042304110c188c208c228c224;
        8: expected_word=128'hc140421842c242404100c1b8c234c268;
        9: expected_word=128'hc20c3f80423842c842383f80c20cc278;
        10: expected_word=128'hc234c1b84100424042c24218c140c254;
        11: expected_word=128'hc228c208c1884110423042b041c0c1f8;
        default: expected_word=128'hc1d0c200c1e8c1884080420842924080;
      endcase
    end
  endfunction

  function [15:0] matmul_expected_bf16;
    input integer elem_i;
    begin
      case (elem_i % 13)
        0: matmul_expected_bf16 = 16'hc0c0;
        1: matmul_expected_bf16 = 16'hc0a0;
        2: matmul_expected_bf16 = 16'hc080;
        3: matmul_expected_bf16 = 16'hc040;
        4: matmul_expected_bf16 = 16'hc000;
        5: matmul_expected_bf16 = 16'hbf80;
        6: matmul_expected_bf16 = 16'h0000;
        7: matmul_expected_bf16 = 16'h3f80;
        8: matmul_expected_bf16 = 16'h4000;
        9: matmul_expected_bf16 = 16'h4040;
        10: matmul_expected_bf16 = 16'h4080;
        11: matmul_expected_bf16 = 16'h40a0;
        default: matmul_expected_bf16 = 16'h40c0;
      endcase
    end
  endfunction

  task check_matmul_output;
    input integer words;
    integer check_word;
    integer lane;
    integer elem;
    reg [127:0] expected;
    begin
      for (check_word = 0; check_word < words; check_word = check_word + 1) begin
        expected = 128'b0;
        for (lane = 0; lane < 8; lane = lane + 1) begin
          elem = check_word * 8 + lane;
          expected[lane * 16 +: 16] = matmul_expected_bf16(elem);
        end
        if (ram.mem[17'h10000 + check_word] !== expected)
          $fatal(1, "lite matmul output mismatch word=%0d got=%032h expected=%032h",
                 check_word, ram.mem[17'h10000 + check_word], expected);
      end
    end
  endtask

  edge_core_lite_top dut (
    .forever_cpuclk(clk), .cpurst_b(reset_n),
    .mem_region_base(40'h0040000000),
    .mem_region_mask(40'hfffffe0000), .mem_region_enable(1'b1),
    .dma_araddr(araddr), .dma_arburst(arburst), .dma_arcache(arcache),
    .dma_arid(arid), .dma_arlen(arlen), .dma_arlock(arlock),
    .dma_arprot(arprot), .dma_arsize(arsize), .dma_arvalid(arvalid),
    .dma_arready(arready), .dma_rdata(rdata), .dma_rid(rid),
    .dma_rlast(rlast), .dma_rready(rready), .dma_rresp(rresp),
    .dma_rvalid(rvalid), .dma_awaddr(awaddr), .dma_awburst(awburst),
    .dma_awcache(awcache), .dma_awid(awid), .dma_awlen(awlen),
    .dma_awlock(awlock), .dma_awprot(awprot), .dma_awsize(awsize),
    .dma_awvalid(awvalid), .dma_awready(awready), .dma_bid(bid),
    .dma_bready(bready), .dma_bresp(bresp), .dma_bvalid(bvalid),
    .dma_wdata(wdata), .dma_wlast(wlast), .dma_wready(wready),
    .dma_wstrb(wstrb), .dma_wvalid(wvalid), .halted(halted),
    .illegal(illegal), .debug_x31(debug_x31), .cycle_count(cycle_count),
    .instret_count(instret_count), .tensor_busy(tensor_busy),
    .actu_busy(actu_busy), .cmpu_busy(cmpu_busy),
    .accel_dma_busy(accel_dma_busy)
  );

  edge_axi_ram #(.RAM_ADDR_BITS(17)) ram (
    .aclk(clk), .aresetn(reset_n), .araddr(araddr), .arburst(arburst),
    .arcache(arcache), .arid(arid), .arlen(arlen), .arlock(arlock),
    .arprot(arprot), .arsize(arsize), .arvalid(arvalid), .arready(arready),
    .rdata(rdata), .rid(rid), .rlast(rlast), .rready(rready),
    .rresp(rresp), .rvalid(rvalid), .imem_req_valid(1'b0),
    .imem_req_ready(), .imem_req_addr(40'b0), .imem_resp_valid(),
    .imem_resp_ready(1'b1), .imem_resp_bits(), .awaddr(awaddr),
    .awburst(awburst), .awcache(awcache), .awid(awid), .awlen(awlen),
    .awlock(awlock), .awprot(awprot), .awsize(awsize),
    .awvalid(awvalid), .awready(awready), .bid(bid), .bready(bready),
    .bresp(bresp), .bvalid(bvalid), .wdata(wdata), .wlast(wlast),
    .wready(wready), .wstrb(wstrb), .wvalid(wvalid)
  );

  initial begin
    return_only = $test$plusargs("return_only");
    trace_cmd = $test$plusargs("trace_cmd");
    check_matmul64 = $test$plusargs("check_matmul64");
    check_matmul128 = $test$plusargs("check_matmul128");
    repeat (4) @(posedge clk);
    reset_n <= 1'b1;
    cycles = 0;
    while (!halted && cycles < TIMEOUT_CYCLES) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    if (!halted) $fatal(1, "lite Tensor timeout instret=%0d", instret_count);
    if (illegal)
      $fatal(1, "lite Tensor illegal pc=%h inst=%h is64=%0d class=%0d legal=%0d ex_error=%0d resp_error=%0d",
             dut.core.cached_core.core.ex_pc,
             dut.core.cached_core.core.ex_inst,
             dut.core.cached_core.core.ex_is_64b,
             dut.core.cached_core.core.decoded_class,
             dut.core.cached_core.core.decoded_legal,
             dut.core.cached_core.core.ex_error,
             dut.core.cached_core.core.accel_resp_error);
    if (return_only) begin
      if (debug_x31 != 64'd0)
        $fatal(1, "lite Tensor program returned %0d", debug_x31);
      if (check_matmul64)
        check_matmul_output(512);
      if (check_matmul128)
        check_matmul_output(1024);
    end else begin
      if (debug_x31 != 64'h100000)
        $fatal(1, "lite Tensor x31=%h", debug_x31);
      for (word_i = 0; word_i < 512; word_i = word_i + 1)
        if (ram.mem[17'h10000 + word_i] !== expected_word(word_i))
          $fatal(1, "lite Tensor output mismatch word=%0d got=%032h expected=%032h",
                 word_i, ram.mem[17'h10000 + word_i],
                 expected_word(word_i));
    end
    $display("PASS: edge-rv-lite Tensor x30=%0d x31=%0d cycles=%0d instret=%0d",
             dut.core.cached_core.core.gpr[30], debug_x31, cycle_count,
             instret_count);
    $finish;
  end
endmodule
