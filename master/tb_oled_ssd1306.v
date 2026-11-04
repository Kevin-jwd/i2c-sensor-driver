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
  reg ack_enabled=1;
  integer transaction=0, byte_count=0, data_bytes=0;
  reg [7:0] incoming;
  reg [7:0] captured_frame [0:1023];
  reg [7:0] updated_frame [0:1023];
  reg [63:0] glyph_expected;
  integer glyph_column;
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
    if ((transaction==1 || transaction==6 || transaction==8) && byte_count!=34)
      $fatal(1,"initialization command count %d",byte_count);
    if (transaction==3 && byte_count!=8) $fatal(1,"refresh command count %d",byte_count);
    if ((transaction==2 || transaction==4 || transaction==7 || transaction==9) && byte_count!=1026)
      $fatal(1,"data count %d",byte_count);
    if (transaction==5 && byte_count!=1) $fatal(1,"NACK should stop immediately");
    active=0;
  end
  always @(posedge scl) if(active) begin
    if(bit_count<8) begin
      shift={shift[6:0],sda};
      bit_count=bit_count+1;
      if(bit_count==8) begin
        incoming=shift;
        if(byte_count==0 && incoming!==8'h78) $fatal(1,"address %h",incoming);
        if(byte_count==1 && incoming!==((transaction==1 || transaction==3 || transaction==6 || transaction==8) ? 8'h00 : 8'h40)) $fatal(1,"control %h",incoming);
        if(transaction==1 || transaction==6 || transaction==8) begin
          if(byte_count==2 && incoming!==8'hae) $fatal(1,"display off");
          if(byte_count==6 && incoming!==8'h3f) $fatal(1,"64 row multiplex");
          if(byte_count==17 && incoming!==8'h12) $fatal(1,"COM config");
          if(byte_count==33 && incoming!==8'h07) $fatal(1,"page end");
        end
        // Normal refresh must only set the RAM window; no display OFF/ON.
        if(transaction==3) begin
          case(byte_count)
            2: if(incoming!==8'h21) $fatal(1,"refresh column command");
            3: if(incoming!==8'h00) $fatal(1,"refresh column start");
            4: if(incoming!==8'h7f) $fatal(1,"refresh column end");
            5: if(incoming!==8'h22) $fatal(1,"refresh page command");
            6: if(incoming!==8'h00) $fatal(1,"refresh page start");
            7: if(incoming!==8'h07) $fatal(1,"refresh page end");
          endcase
        end
        if(transaction==2 && byte_count>=2) begin
          data_bytes=data_bytes+1;
          captured_frame[byte_count-2]=incoming;
          // 8x12 glyphs: lines begin at y=2, y=26 and y=50.
          case(byte_count-2)
             0,1:if(incoming!==8'h0c) $fatal(1,"T first column");
             4:if(incoming!==8'hfc) $fatal(1,"T center column");
             132:if(incoming!==8'h3f) $fatal(1,"T lower page");
             45:if(incoming!==8'hf0) $fatal(1,"temperature zero outline");
             47:if(incoming!==8'h0c) $fatal(1,"temperature zero interior");
             54:if(incoming!==8'h30) $fatal(1,"temperature 2 first column");
             56:if(incoming!==8'h0c) $fatal(1,"temperature 2 second column");
             59:if(incoming!==8'h8c) $fatal(1,"temperature 2 fourth column");
             60:if(incoming!==8'h70) $fatal(1,"temperature 2 last column");
             63:if(incoming!==8'hc0) $fatal(1,"temperature 4 first column");
             384:if(incoming!==8'hfc) $fatal(1,"humidity starts at y=26");
             420:if(incoming!==8'hf0) $fatal(1,"humidity hundreds");
             429,438:if(incoming!==8'h7c) $fatal(1,"humidity digits");
             768:if(incoming!==8'hfc) $fatal(1,"distance starts at y=50");
             813:if(incoming!==8'h0c) $fatal(1,"distance digit 3 first column");
             815:if(incoming!==8'h8c) $fatal(1,"distance digit 3 center");
             822,831:if(incoming!==8'hf0) $fatal(1,"distance zero outline");
             824:if(incoming!==8'h0c) $fatal(1,"distance zero interior");
             1023:if(incoming!==0) $fatal(1,"last pixel");
          endcase
          // Two blank GDDRAM pages separate rows; outer margins are blank.
          if ((((byte_count-2)/128 == 2 || (byte_count-2)/128 == 5) && incoming !== 0) ||
              (((byte_count-2)/128 == 0 || (byte_count-2)/128 == 3 || (byte_count-2)/128 == 6) && (incoming & 8'h03) != 0) ||
              (((byte_count-2)/128 == 1 || (byte_count-2)/128 == 4 || (byte_count-2)/128 == 7) && (incoming & 8'hc0) != 0))
             $fatal(1,"row spacing pixel %d",byte_count-2);
          if(data_bytes==20) begin temperature=47; humidity=54; distance=1; end
        end
        if(transaction==4 && byte_count>=2) begin
          updated_frame[byte_count-2]=incoming;
          // Independent expected columns for 4, 7 and % in both pages.
          if(byte_count-2 >= 54 && byte_count-2 < 62) begin
            glyph_expected=64'h000000fc0c38f0c0; glyph_column=byte_count-2-54;
            if(incoming !== ((glyph_expected >> (glyph_column*8)) & 8'hff)) $fatal(1,"4 upper page column %d",glyph_column);
          end
          if(byte_count-2 >= 182 && byte_count-2 < 190) begin
            glyph_expected=64'h0303033f03030303; glyph_column=byte_count-2-182;
            if(incoming !== ((glyph_expected >> (glyph_column*8)) & 8'hff)) $fatal(1,"4 lower page column %d",glyph_column);
          end
          if(byte_count-2 >= 63 && byte_count-2 < 71) begin
            glyph_expected=64'h1c7cec8c0c0c0c0c; glyph_column=byte_count-2-63;
            if(incoming !== ((glyph_expected >> (glyph_column*8)) & 8'hff)) $fatal(1,"7 upper page column %d",glyph_column);
          end
          if(byte_count-2 >= 191 && byte_count-2 < 199) begin
            glyph_expected=64'h000001073e380000; glyph_column=byte_count-2-191;
            if(incoming !== ((glyph_expected >> (glyph_column*8)) & 8'hff)) $fatal(1,"7 lower page column %d",glyph_column);
          end
          if(byte_count-2 >= 447 && byte_count-2 < 455) begin
            glyph_expected=64'h0418608018242418; glyph_column=byte_count-2-447;
            if(incoming !== ((glyph_expected >> (glyph_column*8)) & 8'hff)) $fatal(1,"percent upper page column %d",glyph_column);
          end
          if(byte_count-2 >= 575 && byte_count-2 < 583) begin
            glyph_expected=64'h0c12120c01020c10; glyph_column=byte_count-2-575;
            if(incoming !== ((glyph_expected >> (glyph_column*8)) & 8'hff)) $fatal(1,"percent lower page column %d",glyph_column);
          end
        end
        byte_count=byte_count+1;
      end
    end else bit_count=9;
  end
  always @(negedge scl) if(active) begin
    if(bit_count==8 && ack_enabled) sensor_low=1;
    else if(bit_count==9) begin sensor_low=0; bit_count=0; end
  end
  initial begin
    #300; @(negedge clk) rst=0;
    wait(ready); @(negedge clk) start=1; @(negedge clk) start=0;
    wait(done); #100;
    if(error || transaction!=2 || data_bytes!=1024 || busy) $fatal(1,"OLED completion");
    $writememh("oled_first_frame.hex", captured_frame);
    // A regular refresh must omit display OFF/ON and preserve initialization.
    @(negedge clk) start=1; @(negedge clk) start=0;
    wait(done); #100;
    if(error || transaction!=4) $fatal(1,"refresh completion");
    $writememh("oled_updated_frame.hex", updated_frame);
    // Address NACK invalidates initialization, so the next success reinitializes.
    ack_enabled=0;
    @(negedge clk) start=1; @(negedge clk) start=0;
    wait(done); #100;
    if(!error || transaction!=5) $fatal(1,"NACK detection");
    ack_enabled=1;
    @(negedge clk) start=1; @(negedge clk) start=0;
    wait(done); #100;
    if(error || transaction!=7) $fatal(1,"NACK recovery");
    // FPGA reset also requires complete initialization again.
    @(negedge clk) rst=1; repeat(3) @(negedge clk); rst=0;
    wait(ready); @(negedge clk) start=1; @(negedge clk) start=0;
    wait(done); #100;
    if(error || transaction!=9) $fatal(1,"reset recovery");
    $display("PASS: OLED init once, no OFF/ON on refresh, NACK and reset recovery"); $finish;
  end
  initial begin #700_000_000; $fatal(1,"watchdog"); end
endmodule

