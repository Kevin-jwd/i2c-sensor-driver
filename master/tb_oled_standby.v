`timescale 1ns / 1ps

module tb_oled_standby;
  reg clk = 0, rst = 1, start = 0, oled_low = 0;
  reg [8:0] distance = 51;
  tri1 sda, scl;
  wire [3:0] an;
  wire [7:0] seg;
  wire [15:0] led;
  wire [7:0] received;
  wire wt, rt, active;
  reg bus_active = 0, oled_addressed = 0;
  reg [3:0] bit_count = 0;
  reg [7:0] shift = 0, control = 0;
  integer byte_count = 0, reads = 0, frames = 0, ball_pixels = 0;
  reg [6:0] first_x;
  reg [5:0] first_y;

  always #50 clk = ~clk;
  assign sda = oled_low ? 1'b0 : 1'bz;
  top_i2c_master #(.CLK_HZ(10_000_000), .I2C_HZ(100_000)) dut (
    .clk(clk), .rst(rst), .start(start), .select_sensor(2'b00),
    .sda(sda), .scl(scl), .an(an), .seg(seg), .led(led));
  i2c_slave sensor (.clk(clk), .rst(rst), .scl(scl), .sda(sda),
    .temperature(8'd24), .humidity(8'd55), .distance(distance),
    .received_data(received), .write_toggle(wt), .read_toggle(rt), .active(active));

  always @(posedge clk) if (!rst && dut.done && !dut.error) reads = reads + 1;
  always @(negedge sda) if (scl === 1'b1 && !rst) begin
    bus_active = 1; oled_addressed = 0; bit_count = 0; byte_count = 0; control = 0;
  end
  always @(posedge sda) if (scl === 1'b1 && bus_active) begin
    if (oled_addressed && control == 8'h40 && byte_count == 1026) frames = frames + 1;
    bus_active = 0;
  end
  always @(posedge scl) if (bus_active) begin
    if (bit_count < 8) begin
      shift = {shift[6:0], sda};
      bit_count = bit_count + 1;
      if (bit_count == 8) begin
        if (byte_count == 0) oled_addressed = (shift == 8'h78);
        if (byte_count == 1 && oled_addressed) control = shift;
        if (oled_addressed && control == 8'h40 && dut.u_oled.standby_buf && byte_count >= 2) begin
          if ((byte_count - 2) % 128 == 0 && shift !== 8'hff)
            $fatal(1, "standby left wall missing");
          if ((byte_count - 2) / 128 != 0 && (byte_count - 2) / 128 != 7 &&
              (byte_count - 2) % 128 != 0 && (byte_count - 2) % 128 != 127 && shift != 0)
            ball_pixels = ball_pixels + 1;
        end
        byte_count = byte_count + 1;
      end
    end else bit_count = 9;
  end
  always @(negedge scl) if (bus_active) begin
    if (bit_count == 8 && oled_addressed) oled_low = 1;
    else if (bit_count == 9) begin oled_low = 0; bit_count = 0; end
  end
  task request;
    begin @(negedge clk) start = 1; repeat (10) @(negedge clk); start = 0; end
  endtask

  initial begin
    #300; @(negedge clk) rst = 0;
    force dut.u_oled.ready = 1;
    request;
    wait (reads == 1);
    wait (dut.oled_busy && dut.u_oled.standby_buf);
    first_x = dut.u_oled.ball_x; first_y = dut.u_oled.ball_y;
    wait (frames >= 2);
    wait (dut.oled_busy && dut.u_oled.ball_x != first_x);
    if (dut.u_oled.ball_y == first_y || ball_pixels == 0)
      $fatal(1, "standby ball did not move or render");

    distance = 50;
    request;
    wait (reads == 2);
    wait (dut.oled_busy && !dut.u_oled.standby_buf);
    if (dut.distance !== 50 || dut.display_value !== 50)
      $fatal(1, "50 cm must show sensor values");

    distance = 51;
    request;
    wait (reads == 3);
    wait (dut.oled_busy && dut.u_oled.standby_buf);
    if (dut.distance !== 51) $fatal(1, "standby did not resume");
    $display("PASS: standby frames, moving ball, 50 cm threshold and wake-up");
    $finish;
  end
  initial begin #1_000_000_000; $fatal(1, "watchdog"); end
endmodule
