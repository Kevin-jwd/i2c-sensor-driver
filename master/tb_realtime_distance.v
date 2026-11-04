`timescale 1ns / 1ps
module tb_realtime_distance;
  reg master_clk=0, slave_clk=0, rst=1, echo=0;
  tri1 sda, scl, dht;
  wire trig, rs_tx;
  wire [3:0] master_an, slave_an;
  wire [7:0] master_seg, slave_seg;
  wire [15:0] master_led, slave_led;
  integer measurements=0, master_reads=0;
  always #5 master_clk=~master_clk;
  initial begin #2; forever #5 slave_clk=~slave_clk; end
  top_i2c_master master(.clk(master_clk),.rst(rst),.start(1'b0),
    .select_sensor(2'b00),.sda(sda),.scl(scl),.an(master_an),.seg(master_seg),.led(master_led));
  top_i2c_slave slave(.clk(slave_clk),.rst(rst),.scl(scl),.sda(sda),
    .dht11_data(dht),.trig(trig),.echo(echo),.btn(3'b0),.RsRx(1'b1),
    .RsTx(rs_tx),.seg(slave_seg),.an(slave_an),.led(slave_led));

  always @(posedge master_clk) if (!rst && master.done && !master.error)
    master_reads=master_reads+1;
  always @(posedge trig) begin
    measurements=measurements+1;
    #200000 echo=1;
    if(measurements==1) #603000; else #11623000;
    echo=0;
  end
  task next_slave_measurement;
    begin
      force slave.trigger_count = 9_999_998;
      repeat(3) @(negedge slave_clk);
      release slave.trigger_count;
    end
  endtask
  task next_master_poll;
    begin
      force master.poll_count = 49_999_998;
      repeat(3) @(negedge master_clk);
      release master.poll_count;
    end
  endtask
  initial begin
    #100; rst=0;
    // Skip OLED power-up only, to isolate sensor sampling and I2C polling.
    force master.u_oled.ready=0;
    if(slave.TRIGGER_PERIOD != 10_000_000 || master.POLL_CYCLES != 50_000_000)
      $fatal(1,"incorrect real periods");
    wait(slave.distance==10);
    next_master_poll;
    wait(master_reads==1); #100;
    if(master.distance!==10 || master.display_value!==10) $fatal(1,"first distance");
    next_slave_measurement;
    wait(slave.distance==200);
    next_master_poll;
    wait(master_reads==2); #100;
    if(master.distance!==200 || master.display_value!==200) $fatal(1,"updated distance");
    $display("PASS: automatic ultrasonic measurement and master polling, 10cm to 200cm");
    $finish;
  end
  initial begin #25_000_000; $fatal(1,"watchdog"); end
endmodule
