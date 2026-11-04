`timescale 1ns / 1ps

module tb_ultrasonic_sensor;
    reg clk = 0;
    reg rst = 1;
    reg start = 0;
    reg echo = 0;
    wire trig, busy, done, timeout;
    wire [15:0] distance_cm;
    integer errors = 0;
    time trigger_start;
    time last_trigger = 0;

    // 1 MHz keeps all real sensor timings while reducing simulation cycles.
    always #500 clk = ~clk;
    ultrasonic_sensor #(.CLK_HZ(1_000_000)) dut (
        .clk(clk), .rst(rst), .start(start), .echo(echo),
        .trig(trig), .busy(busy), .done(done), .timeout(timeout),
        .distance_cm(distance_cm)
    );

    always @(posedge trig) begin
        if (last_trigger != 0 && $time - last_trigger < 60_000_000) begin
            $display("FAIL: trigger interval below 60 ms");
            errors = errors + 1;
        end
        last_trigger = $time;
        trigger_start = $time;
    end
    always @(negedge trig) begin
        if (!rst && $time - trigger_start != 10_000) begin
            $display("FAIL: trigger pulse is not 10 us");
            errors = errors + 1;
        end
    end

    task request;
        begin
            wait (!busy);
            @(negedge clk) start = 1;
            @(negedge clk) start = 0;
        end
    endtask

    task check_result;
        input expected_timeout;
        input [15:0] expected_distance;
        begin
            wait (done);
            #1;
            if (timeout !== expected_timeout || distance_cm !== expected_distance) begin
                $display("FAIL: timeout=%b distance=%d expected=%b/%d",
                         timeout, distance_cm, expected_timeout, expected_distance);
                errors = errors + 1;
            end
            @(posedge clk); #1;
            if (done !== 0) begin
                $display("FAIL: done must last one clock");
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        #2500;
        @(negedge clk) rst = 0;
        // 100 cm: 5800 us echo pulse.
        request;
        @(negedge trig);
        #200_000 echo = 1;
        #5_800_000 echo = 0;
        check_result(0, 100);
        // Requests during cooldown must not trigger another measurement.
        @(negedge clk) start = 1;
        @(negedge clk) start = 0;
        #20_000;
        if (trig || !busy) begin
            $display("FAIL: cooldown did not reject request");
            errors = errors + 1;
        end
        // No response: timeout, previous measurement retained.
        request;
        check_result(1, 100);
        // Echo stuck high after trigger: bounded measurement timeout.
        request;
        @(negedge trig);
        #200_000 echo = 1;
        check_result(1, 100);
        // Recovery and short distance (2 cm).
        echo = 0;
        request;
        @(negedge trig);
        #200_000 echo = 1;
        #116_000 echo = 0;
        check_result(0, 2);
        // Reset aborts an active request and clears state/results.
        request;
        #2000 rst = 1;
        #1;
        if (trig || busy || done || timeout || distance_cm != 0) begin
            $display("FAIL: reset did not clear outputs");
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS: ultrasonic sensor tests");
        else $fatal(1, "FAIL: %0d errors", errors);
        $finish;
    end

    initial begin
        #400_000_000;
        $fatal(1, "FAIL: simulation watchdog");
    end
endmodule
