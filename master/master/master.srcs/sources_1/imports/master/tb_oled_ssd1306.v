`timescale 1ns / 1ps
module tb_oled_ssd1306;
  reg clk=0, rst=1, start=0, sensor_low=0;
  reg [7:0] temperature=24, humidity=55;
  reg [8:0] distance=300;
  tri1 sda, scl;
  wire drive_sda, drive_scl, ready, busy, done, error;
  reg [7:0] shift=0;
  reg [3:0] bit_count=0;
  reg active=0;
  integer transaction=0, byte_count=0, data_bytes=0;
  reg [7:0] incoming;
  always #50 clk=~clk;
  assign sda = (drive_sda || sensor_low) ? 1'b0 : 1'bz;
  assign scl = drive_scl ? 1'b0 : 1'bz;
  oled_ssd1306 #(.CLK_HZ(10_000_000),.POWERUP_US(10)) dut (
    .clk(clk),.rst(rst),.start(start),.sda(sda),
    .temperature(temperature),.humidity(humidity),.distance(distance),
    .data_valid(1'b1),.sda_low(drive_sda),.scl_low(drive_scl),
    .ready(ready),.busy(busy),.done(done),.error(error));

  always @(negedge sda) if(scl===1'b1 && !rst) begin
    active=1; transaction=transaction+1; byte_count=0; bit_count=0;
  end
  always @(posedge sda) if(scl===1'b1 && active) begin
    if (transaction==1 && byte_count!=34) $fatal(1,"command count %d",byte_count);
    if (transaction==2 && byte_count!=1026) $fatal(1,"data count %d",byte_count);
    active=0;
  end
  always @(posedge scl) if(active) begin
    if(bit_count<8) begin
      shift={shift[6:0],sda};
      bit_count=bit_count+1;
      if(bit_count==8) begin
        incoming=shift;
        if(byte_count==0 && incoming!==8'h78) $fatal(1,"address %h",incoming);
        if(byte_count==1 && incoming!==(transaction==1 ? 8'h00 : 8'h40)) $fatal(1,"control %h",incoming);
        if(transaction==1) begin
          if(byte_count==2 && incoming!==8'hae) $fatal(1,"display off");
          if(byte_count==6 && incoming!==8'h3f) $fatal(1,"64 row multiplex");
          if(byte_count==17 && incoming!==8'h12) $fatal(1,"COM config");
          if(byte_count==33 && incoming!==8'h07) $fatal(1,"page end");
        end
        if(transaction==2 && byte_count>=2) begin
          data_bytes=data_bytes+1;
          case(byte_count-2)
             0:if(incoming!==8'h01) $fatal(1,"T column %h",incoming);
             2:if(incoming!==8'h7f) $fatal(1,"T center");
             36:if(incoming!==8'h3e) $fatal(1,"temperature hundreds");
             42:if(incoming!==8'h46) $fatal(1,"temperature tens %h",incoming);
             48:if(incoming!==8'h08) $fatal(1,"temperature units %h",incoming);
             158:if(incoming!==8'h3e) $fatal(1,"humidity hundreds");
             164:if(incoming!==8'h27) $fatal(1,"humidity tens");
             292:if(incoming!==8'h02) $fatal(1,"distance hundreds %h",incoming);
             298:if(incoming!==8'h3e) $fatal(1,"distance tens");
             304:if(incoming!==8'h3e) $fatal(1,"distance units");
             1023:if(incoming!==0) $fatal(1,"last blank pixel");
          endcase
          if(data_bytes==20) begin temperature=99; humidity=99; distance=1; end
        end
        byte_count=byte_count+1;
      end
    end else bit_count=9;
  end
  always @(negedge scl) if(active) begin
    if(bit_count==8) sensor_low=1;
    else if(bit_count==9) begin sensor_low=0; bit_count=0; end
  end
  initial begin
    #300; @(negedge clk) rst=0;
    wait(ready); @(negedge clk) start=1; @(negedge clk) start=0;
    wait(done); #100;
    if(error || transaction!=2 || data_bytes!=1024 || busy) $fatal(1,"OLED completion");
    $display("PASS: 128x64 OLED init, ACKs, 1024 pixels, text and snapshot"); $finish;
  end
  initial begin #250_000_000; $fatal(1,"watchdog"); end
endmodule
