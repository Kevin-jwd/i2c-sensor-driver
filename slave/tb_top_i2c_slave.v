`timescale 1ns / 1ps

module tb_top_i2c_slave;
    reg clk = 0;
    reg rst = 1;
    reg echo = 0;
    wire trig;
    tri1 sda;
    wire [15:0] led;
    time first_trigger;

    always #500 clk = ~clk;
    top_i2c_slave #(.CLK_HZ(1_000_000)) dut (
        .clk(clk), .rst(rst), .scl(1'b1), .sda(sda),
        .echo(echo), .trig(trig), .led(led)
    );

    initial begin
        #2500;
        @(negedge clk) rst = 0;
        @(posedge trig);
        first_trigger = $time;
        @(negedge trig);
        #200_000 echo = 1;
        #5_800_000 echo = 0;
        wait (led[8]);
        #1;
        if (dut.distance_cm !== 16'd100 || led[7:0] !== 8'd100 ||
            led[10] !== 0 || sda !== 1)
            $fatal(1, "FAIL: top did not latch 100 cm / bus not released");
        @(posedge trig);
        if ($time - first_trigger < 60_000_000)
            $fatal(1, "FAIL: automatic trigger interval too short");
        // Second automatic measurement receives no echo.
        wait (led[10]);
        #1;
        if (dut.distance_cm !== 16'd100 || led[8] !== 1)
            $fatal(1, "FAIL: timeout overwrote successful measurement");
        rst = 1;
        #1;
        if (led !== 0 || trig !== 0)
            $fatal(1, "FAIL: top reset");
        $display("PASS: top sensor integration tests");
        $finish;
    end

    initial begin
        #150_000_000;
        $fatal(1, "FAIL: top simulation watchdog");
    end
endmodule
