`timescale 1ns / 1ps

module tb_oled_bounce;
  reg clk = 0, rst = 1, start = 0;
  wire sda_low, scl_low, ready, busy, done, error;
  always #5 clk = ~clk;
  oled_ssd1306 #(.CLK_HZ(1_000_000), .I2C_HZ(100_000), .POWERUP_US(1)) dut (
    .clk(clk), .rst(rst), .start(start), .sda(1'b0),
    .temperature(8'd0), .humidity(8'd0), .distance(9'd100),
    .data_valid(1'b1), .standby(1'b1), .sda_low(sda_low), .scl_low(scl_low),
    .ready(ready), .busy(busy), .done(done), .error(error));

  task check_bounce;
    input [6:0] x;
    input [5:0] y;
    input left, up;
    input [6:0] expected_x;
    input [5:0] expected_y;
    input expected_left, expected_up;
    begin
      @(negedge clk) rst = 1;
      @(negedge clk) rst = 0;
      wait (ready);
      @(negedge clk);
      dut.ball_x = x; dut.ball_y = y;
      dut.ball_left = left; dut.ball_up = up;
      start = 1;
      @(posedge clk); #1;
      if (dut.ball_x !== expected_x || dut.ball_y !== expected_y ||
          dut.ball_left !== expected_left || dut.ball_up !== expected_up)
        $fatal(1, "bounce failed at x=%d y=%d", x, y);
      @(negedge clk) start = 0;
    end
  endtask

  initial begin
    check_bounce(111, 47, 0, 0, 111, 47, 1, 1);
    check_bounce(1, 1, 1, 1, 1, 1, 0, 0);
    check_bounce(111, 1, 0, 1, 111, 1, 1, 0);
    check_bounce(1, 47, 1, 0, 1, 47, 0, 1);
    $display("PASS: ball reverses at all four screen corners");
    $finish;
  end
endmodule
