`timescale 1ns / 1ps
module tb_i2c_slave;
  reg clk=0, rst=1, scl=1, master_low=0;
  reg [7:0] temperature=24, humidity=55;
  reg [8:0] distance=9'd300;
  tri1 sda;
  wire [7:0] received;
  wire wt, rt, active;
  reg [7:0] result;
  reg ack;
  always #5 clk=~clk;
  assign sda=master_low ? 1'b0 : 1'bz;
  i2c_slave dut(.clk(clk),.rst(rst),.scl(scl),.sda(sda),
    .temperature(temperature),.humidity(humidity),.distance(distance),
    .received_data(received),.write_toggle(wt),.read_toggle(rt),.active(active));

  task i2c_start; begin
    master_low=0; scl=1; #5000; master_low=1; #5000; scl=0; #5000;
  end endtask
  task i2c_stop; begin
    scl=0; master_low=1; #5000; scl=1; #5000; master_low=0; #5000;
  end endtask
  task write_byte;
    input [7:0] data;
    output got_ack;
    integer i;
    begin
      for(i=7;i>=0;i=i-1) begin
        master_low=!data[i]; #5000; scl=1; #5000; scl=0;
      end
      master_low=0; #5000; scl=1; #2500; got_ack=!sda; #2500; scl=0; #5000;
    end
  endtask
  task read_byte;
    output [7:0] data;
    input send_ack;
    integer i;
    begin
      master_low=0;
      for(i=7;i>=0;i=i-1) begin
        #5000; scl=1; #2500; data[i]=sda; #2500; scl=0;
      end
      master_low=send_ack; #5000; scl=1; #5000; scl=0; #5000;
      master_low=0;
    end
  endtask
  initial begin
    #100 rst=0;
    i2c_start; if (!active) $fatal(1,"active not asserted");
    write_byte(8'h84,ack); if(!ack) $fatal(1,"write address NACK");
    write_byte(8'ha5,ack); if(!ack || received!==8'ha5 || wt!==1) $fatal(1,"first write LED");
    write_byte(8'h3c,ack); if(!ack || received!==8'h3c || wt!==0) $fatal(1,"second write LED");
    i2c_start; write_byte(8'h85,ack); if(!ack) $fatal(1,"read address NACK");
    read_byte(result,1); if(result!==24) $fatal(1,"temperature %h",result);
    if (rt !== 1) $fatal(1,"first read toggle");
    temperature=99; humidity=77; distance=1;
    read_byte(result,1); if(result!==55) $fatal(1,"humidity snapshot %h",result);
    if (rt !== 0) $fatal(1,"second read toggle");
    read_byte(result,1); if(result!==1) $fatal(1,"distance high %h",result);
    read_byte(result,1); if(result!==8'h2c) $fatal(1,"distance low %h",result);
    read_byte(result,0); if(result!==8'hff) $fatal(1,"extra byte %h",result);
    i2c_stop;
    if (active !== 0) $fatal(1,"active after STOP");
    i2c_start; write_byte(8'h87,ack); if(ack) $fatal(1,"wrong address ACK"); i2c_stop;
    i2c_start; write_byte(8'h85,ack); if(!ack) $fatal(1,"second read address");
    read_byte(result,0); if(result!==99) $fatal(1,"new snapshot %h",result);
    i2c_stop;
    $display("PASS: I2C write/read LED flags, repeated START, burst, NACK, snapshot"); $finish;
  end
  initial begin #20_000_000; $fatal(1,"watchdog"); end
endmodule
