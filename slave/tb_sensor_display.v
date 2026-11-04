`timescale 1ns / 1ps
module tb_sensor_display;
  reg clk=0, rst=1, valid=0;
  reg [1:0] sel=0;
  reg [8:0] distance=300;
  reg [7:0] temp=24, hum=55;
  wire [3:0] an;
  wire [7:0] seg;
  always #5 clk=~clk;
  sensor_display #(.CLK_HZ(1000)) dut(.clk(clk),.rst(rst),.select_sensor(sel),
      .distance(distance),.temperature(temp),.humidity(hum),.dht_valid(valid),.an(an),.seg(seg));
  task check;
    input [3:0] expected_an;
    input [7:0] expected_seg;
    begin
      @(negedge clk);
      if (an !== expected_an || seg !== expected_seg)
        $fatal(1,"display an=%b seg=%h expected=%b/%h",an,seg,expected_an,expected_seg);
    end
  endtask
  initial begin
    #1; rst=1; #10; @(negedge clk) rst=0;
    // Wait for each scan phase explicitly so the test is independent of alignment.
    wait(an==4'b1110); #1; if(seg!==8'hc0) $fatal(1,"distance units");
    wait(an==4'b1011); #1; if(seg!==8'hb0) $fatal(1,"distance hundreds");
    wait(an==4'b0111); #1; if(seg!==8'ha1) $fatal(1,"distance label");
    sel=1; valid=0;
    wait(an==4'b1110); #1; if(seg!==8'hbf) $fatal(1,"invalid DHT");
    valid=1; #1; if(seg!==8'h99) $fatal(1,"temperature units");
    wait(an==4'b1101); #1; if(seg!==8'ha4) $fatal(1,"temperature tens");
    wait(an==4'b0111); #1; if(seg!==8'h87) $fatal(1,"temperature label");
    sel=2;
    wait(an==4'b1110); #1; if(seg!==8'h92) $fatal(1,"humidity units");
    wait(an==4'b0111); #1; if(seg!==8'h89) $fatal(1,"humidity label");
    $display("PASS: distance/temperature/humidity display and invalid DHT");
    $finish;
  end
  initial begin #10000; $fatal(1,"watchdog"); end
endmodule
