`timescale 1ns/1ps
module edge_rv_lite_tb;
  reg clk = 0; always #5 clk = ~clk;
  reg reset_n = 0, decoded_valid = 0, decoded_is_accel = 0;
  wire decoded_ready, scalar_issue_valid, accel_issue_valid;
  reg scalar_issue_ready = 1, scalar_done = 0;
  reg accel_issue_ready = 1, accel_done = 0;
  wire retire_valid, retire_is_accel, busy;
  edge_rv_lite_serial_ctrl dut(.*);

  initial begin
    repeat (2) @(posedge clk); reset_n <= 1;
    @(posedge clk); decoded_valid <= 1; decoded_is_accel <= 1;
    @(posedge clk); decoded_valid <= 0;
    wait (accel_issue_valid); @(posedge clk);
    repeat (3) begin
      if (decoded_ready || !busy) begin
        $display("accepted younger instruction while ASIC busy"); $finish;
      end
      @(posedge clk);
    end
    accel_done <= 1; @(posedge clk); accel_done <= 0;
    wait (retire_valid);
    if (!retire_is_accel) begin $display("wrong retire owner"); $finish; end
    @(posedge clk);
    if (!decoded_ready) begin $display("owner not released"); $finish; end
    decoded_valid <= 1; decoded_is_accel <= 0;
    @(posedge clk); decoded_valid <= 0;
    wait (scalar_issue_valid); @(posedge clk);
    if (accel_issue_valid) begin $display("dual issue occurred"); $finish; end
    scalar_done <= 1; @(posedge clk); scalar_done <= 0;
    wait (retire_valid);
    if (retire_is_accel) begin $display("wrong scalar retire"); $finish; end
    $display("TEST PASS: one owner, one issue, one completion");
    $finish;
  end
endmodule

