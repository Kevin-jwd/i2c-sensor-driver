`timescale 1ns / 1ps
module tb_dht11_top;
  reg clk=0, rst=1, sensor_low=0;
  reg [2:0] btn=0;
  tri1 data, sda;
  wire trig, rs_tx;
  wire [3:0] an;
  wire [7:0] seg;
  wire [15:0] led;
  reg [39:0] frame = {8'd55, 8'd0, 8'd24, 8'd0, 8'd79};
  integer i;
  always #5 clk=~clk;
  assign data = sensor_low ? 1'b0 : 1'bz;
  top_i2c_slave dut(.clk(clk),.rst(rst),.scl(1'b1),.sda(sda),
    .dht11_data(data),.trig(trig),.echo(1'b0),.btn(btn),
    .RsRx(1'b1),.RsTx(rs_tx),.seg(seg),.an(an),.led(led));

  task skip_wait;
    begin
      // Shorten only the 2.1 s initial wait; all protocol timing is real.
      force dut.u_dht11.us_count = 22'd2099998;
      #2000;
      release dut.u_dht11.us_count;
    end
  endtask
  initial begin
    #100; @(negedge clk) rst=0;
    skip_wait;
    @(negedge data); @(posedge data);
    #25000 sensor_low=1;
    #80000 sensor_low=0;
    #80000;
    for(i=39;i>=0;i=i-1) begin
      sensor_low=1; #50000 sensor_low=0;
      if(frame[i]) #70000; else #27000;
    end
    sensor_low=1; #50000 sensor_low=0;
    #2000;
    if (!led[10] || led[11] || !led[12] || !led[13] ||
        dut.temperature !== 8'd24 || dut.humidity !== 8'd55)
      $fatal(1,"valid frame not displayed or LED state wrong: led=%h",led);
    btn[1]=1;
    wait(an==4'b1110); #1; if(seg !== 8'h99) $fatal(1,"temperature display");
    btn[1]=0; btn[2]=1;
    wait(an==4'b1110); #1; if(seg !== 8'h92) $fatal(1,"humidity display");
    rst=1; #100; @(negedge clk) rst=0; btn=0;
    skip_wait;
    @(negedge data); @(posedge data);
    wait(led[12]); #100;
    if (led[10] || !led[11] || !led[13]) $fatal(1,"missing timeout diagnostic");
    $display("PASS: 100 MHz DHT valid frame, display, and missing sensor diagnostics");
    $finish;
  end
  initial begin #100_000_000; $fatal(1,"watchdog"); end
endmodule
