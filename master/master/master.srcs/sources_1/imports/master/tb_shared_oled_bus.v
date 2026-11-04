`timescale 1ns / 1ps
module tb_shared_oled_bus;
  reg clk=0, rst=1, start=0, oled_ack=1, oled_low=0;
  reg [1:0] select_sensor=0;
  tri1 sda, scl;
  wire [3:0] an;
  wire [7:0] seg;
  wire [15:0] led;
  wire [7:0] received;
  wire wt, rt, active;
  reg bus_active=0, addressed_oled=0;
  reg [3:0] bit_count=0;
  reg [7:0] shift=0, control_byte=0;
  integer index=0, oled_stops=0, sensor_reads=0, completed_frames=0;
  always #50 clk=~clk;
  assign sda = oled_low ? 1'b0 : 1'bz;
  top_i2c_master #(.CLK_HZ(10_000_000), .I2C_HZ(100_000)) dut (
    .clk(clk),.rst(rst),.start(start),.select_sensor(select_sensor),
    .sda(sda),.scl(scl),.an(an),.seg(seg),.led(led));
  i2c_slave sensor(.clk(clk),.rst(rst),.scl(scl),.sda(sda),
    .temperature(8'd24),.humidity(8'd55),.distance(9'd300),
    .received_data(received),.write_toggle(wt),.read_toggle(rt),.active(active));

  always @(posedge clk) if(!rst) begin
    if(dut.busy && dut.oled_busy) $fatal(1,"two I2C masters active together");
    if(dut.done && !dut.error) sensor_reads=sensor_reads+1;
  end
  always @(negedge sda) if(scl===1'b1 && !rst) begin
    bus_active=1; addressed_oled=0; bit_count=0; index=0; control_byte=0;
  end
  always @(posedge sda) if(scl===1'b1 && bus_active) begin
    if(addressed_oled) begin
      oled_stops=oled_stops+1;
      if(control_byte==8'h40 && index==1026) completed_frames=completed_frames+1;
    end
    bus_active=0;
  end
  always @(posedge scl) if(bus_active) begin
    if(bit_count<8) begin
      shift={shift[6:0],sda}; bit_count=bit_count+1;
      if(bit_count==8) begin
        if(index==0) addressed_oled=(shift==8'h78);
        if(index==1 && addressed_oled) control_byte=shift;
        index=index+1;
      end
    end else bit_count=9;
  end
  always @(negedge scl) if(bus_active) begin
    if(bit_count==8 && addressed_oled && oled_ack) oled_low=1;
    else if(bit_count==9) begin oled_low=0; bit_count=0; end
  end
  task request; begin
    @(negedge clk) start=1; repeat(10) @(negedge clk); start=0;
  end endtask
  initial begin
    #300; @(negedge clk) rst=0;
    // Skip only OLED power-up delay; keep its 100 kHz bus timing.
    force dut.u_oled.ready=1;
    wait(dut.oled_busy);
    request;
    if(!dut.pending_read) $fatal(1,"sensor request not queued");
    wait(sensor_reads==1); #200;
    if(dut.temperature!==24 || dut.humidity!==55 || dut.distance!==300)
      $fatal(1,"sensor result after OLED");
    wait(completed_frames==2); wait(!dut.oled_busy); #200;
    if(led[11] || !led[15] || oled_stops!=4) $fatal(1,"OLED refresh status");
    // OLED absent: sensor reading must still succeed and OLED reports NACK.
    oled_ack=0; request;
    wait(sensor_reads==2);
    wait(led[11]);
    if(!led[15] || dut.temperature!==24) $fatal(1,"OLED NACK blocked sensor");
    wait(!dut.oled_busy); request;
    wait(sensor_reads==3);
    if(!led[15] || dut.distance!==300) $fatal(1,"sensor did not recover after OLED NACK");
    $display("PASS: shared bus, queued read, OLED refresh, OLED NACK isolation");
    $finish;
  end
  initial begin #350_000_000; $fatal(1,"watchdog"); end
endmodule
