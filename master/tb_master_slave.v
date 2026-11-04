`timescale 1ns / 1ps
module tb_master_slave;
  reg clk = 0, rst = 1, start = 0, slave_reset = 1;
  reg [1:0] select_sensor = 0;
  tri1 sda;
  tri1 scl;
  wire [3:0] an;
  wire [7:0] seg;
  wire [15:0] led;
  wire [7:0] received;
  wire wt, rt, active;
  reg [7:0] temp = 24, humidity = 55;
  reg [8:0] distance = 300;
  always #50 clk = ~clk;
  top_i2c_master #(
      .CLK_HZ(10_000_000),
      .I2C_HZ(100_000)
  ) dut (
      .clk(clk),
      .rst(rst),
      .start(start),
      .select_sensor(select_sensor),
      .sda(sda),
      .scl(scl),
      .an(an),
      .seg(seg),
      .led(led)
  );
  i2c_slave sensor_slave (
      .clk(clk),
      .rst(slave_reset),
      .scl(scl),
      .sda(sda),
      .temperature(temp),
      .humidity(humidity),
      .distance(distance),
      .received_data(received),
      .write_toggle(wt),
      .read_toggle(rt),
      .active(active)
  );
  task request;
    begin
      @(negedge clk) start = 1;
      repeat (10) @(negedge clk);
      start = 0;
    end
  endtask
  initial begin
    #300;
    @(negedge clk) rst = 0;
    slave_reset = 0;
    #1000;
    if (seg !== 8'hbf) $fatal(1, "initial display");
    request;
    wait (dut.done);
    #200;
    if(dut.error || dut.temperature!==24 || dut.humidity!==55 || dut.distance!==300 || !led[15])
      $fatal(
          1, "read failed T=%d H=%d D=%d led=%h", dut.temperature, dut.humidity, dut.distance, led
      );
    // Display current value using each switch selection.
    select_sensor = 0;
    #1;
    if (dut.display_value !== 300) $fatal(1, "distance select");
    wait(an == 4'b1011); #1; if(seg !== 8'hb0) $fatal(1,"FND distance hundreds %h",seg);
    wait(an == 4'b1110); #1; if(seg !== 8'hc0) $fatal(1,"FND distance units %h",seg);
    select_sensor = 1;
    #1;
    if (dut.display_value !== 24) $fatal(1, "temperature select");
    wait(an == 4'b1101); #1; if(seg !== 8'ha4) $fatal(1,"FND temperature tens %h",seg);
    wait(an == 4'b1110); #1; if(seg !== 8'h99) $fatal(1,"FND temperature units %h",seg);
    select_sensor = 2;
    #1;
    if (dut.display_value !== 55) $fatal(1, "humidity select");
    wait (an == 4'b1110);
    #1;
    if (seg !== 8'h92) $fatal(1, "FND humidity units %h", seg);
    wait (an == 4'b1101);
    #1;
    if (seg !== 8'h92) $fatal(1, "FND humidity tens %h", seg);
    // Missing slave produces NACK and preserves the previous measurement.
    slave_reset = 1;
    #1000;
    request;
    wait (dut.done);
    #200;
    if(!dut.error || !led[13] || !led[14] || led[15] ||
           dut.temperature!==24 || dut.humidity!==55 || dut.distance!==300)
      $fatal(1, "NACK handling or retained values");
    // Recovery with a fresh result and distance above 255 cm.
    temp = 27;
    humidity = 66;
    distance = 9'd511;
    slave_reset = 0;
    #1000;
    request;
    wait (dut.done);
    #200;
    if(dut.error || dut.temperature!==27 || dut.humidity!==66 || dut.distance!==511 || !led[15])
      $fatal(1, "recovery failed");
    $display("PASS: actual master/slave read, FND selection, NACK and recovery");
    $finish;
  end
  initial begin
    #20_000_000;
    $fatal(1, "watchdog");
  end
endmodule
