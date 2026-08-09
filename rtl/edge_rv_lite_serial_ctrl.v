`timescale 1ns/1ps
// Single architectural owner replacing RTU, snapshots and completion merge.
module edge_rv_lite_serial_ctrl (
  input wire clk, input wire reset_n,
  input wire decoded_valid, output wire decoded_ready,
  input wire decoded_is_accel,
  output wire scalar_issue_valid, input wire scalar_issue_ready,
  input wire scalar_done,
  output wire accel_issue_valid, input wire accel_issue_ready,
  input wire accel_done,
  output reg retire_valid, output reg retire_is_accel,
  output wire busy
);
  reg owner_valid;
  reg owner_is_accel;
  reg owner_issued;
  assign busy = owner_valid;
  assign decoded_ready = !owner_valid;
  assign scalar_issue_valid = owner_valid && !owner_is_accel && !owner_issued;
  assign accel_issue_valid = owner_valid && owner_is_accel && !owner_issued;
  wire scalar_fire = scalar_issue_valid && scalar_issue_ready;
  wire accel_fire = accel_issue_valid && accel_issue_ready;
  wire owner_done = owner_issued &&
                    (owner_is_accel ? accel_done : scalar_done);

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      owner_valid <= 1'b0; owner_is_accel <= 1'b0; owner_issued <= 1'b0;
      retire_valid <= 1'b0; retire_is_accel <= 1'b0;
    end else begin
      retire_valid <= 1'b0;
      if (decoded_valid && decoded_ready) begin
        owner_valid <= 1'b1;
        owner_is_accel <= decoded_is_accel;
        owner_issued <= 1'b0;
      end
      if (scalar_fire || accel_fire) owner_issued <= 1'b1;
      if (owner_done) begin
        retire_valid <= 1'b1;
        retire_is_accel <= owner_is_accel;
        owner_valid <= 1'b0;
        owner_issued <= 1'b0;
      end
    end
  end
endmodule
