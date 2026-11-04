`timescale 1ns / 1ps

module tb_dht11;
    reg clk = 0, rst = 1, start = 0, sensor_low = 0;
    tri1 data;
    wire busy, done;
    wire error;
    wire [7:0] humidity, temperature;
    integer completions = 0;
    reg last_done = 0;

    // 1 MHz simulation clock; all protocol and waiting times remain real.
    always #500 clk = ~clk;
    assign data = sensor_low ? 1'b0 : 1'bz;
    dht11 #(.CLK_HZ(1_000_000)) dut (
        .clk(clk), .rst(rst), .start(start), .dht11_data(data),
        .busy(busy), .done(done), .error(error),
        .humidity(humidity), .temperature(temperature)
    );

    always @(posedge clk) begin
        #1;
        if (done && last_done) $fatal(1, "done lasted more than one clock");
        if (done) completions = completions + 1;
        last_done = done;
    end

    task request;
        begin
            wait (!busy);
            @(negedge clk) start = 1;
        end
    endtask

    task wait_release;
        time low_start;
        begin
            @(negedge data);
            start = 0;
            low_start = $time;
            @(posedge data);
            if ($time - low_start != 19_000_000)
                $fatal(1, "host start must be 19 ms");
        end
    endtask

    task send_frame;
        input [39:0] bits;
        integer i;
        begin
            wait_release;
            #25_000 sensor_low = 1;
            #80_000 sensor_low = 0;
            #80_000;
            for (i = 39; i >= 0; i = i - 1) begin
                sensor_low = 1;
                #50_000 sensor_low = 0;
                if (bits[i]) #70_000;
                else #27_000;
            end
            sensor_low = 1;
            #50_000 sensor_low = 0;
        end
    endtask

    task expect_result;
        input integer target;
        input expected_error;
        input [15:0] expected_values;
        begin
            wait (completions == target);
            #10;
            if (error !== expected_error ||
                {humidity, temperature}
                !== expected_values)
                $fatal(1, "unexpected result: error=%d values=%h", error,
                       {humidity, temperature});
        end
    endtask

    initial begin
        #100;
        @(negedge clk) rst = 0;
        request;
        send_frame({8'd55, 8'd0, 8'd24, 8'd0, 8'd79});
        expect_result(1, 0, {8'd55, 8'd24});
        if (!busy) $fatal(1, "missing cooldown");
        @(negedge clk) start = 1;
        @(negedge clk) start = 0;
        wait (!busy);
        #10_000;
        if (data !== 1 || busy) $fatal(1, "busy request was queued");
        request;
        send_frame({8'd60, 8'd0, 8'd25, 8'd0, 8'd0});
        expect_result(2, 1, {8'd55, 8'd24});
        request;
        wait_release;
        expect_result(3, 1, {8'd55, 8'd24});
        request;
        wait_release;
        #25_000 sensor_low = 1;
        expect_result(4, 1, {8'd55, 8'd24});
        sensor_low = 0;
        request;
        // Synthetic bytes test preservation and checksum modulo 256.
        send_frame({8'd90, 8'd100, 8'd30, 8'd100, 8'd64});
        expect_result(5, 0, {8'd90, 8'd30});
        request;
        @(negedge data);
        #1000 rst = 1;
        #100;
        if (data !== 1 || done || error != 0 || humidity != 0 || temperature != 0)
            $fatal(1, "reset did not clear/release controller");
        $display("PASS: DHT11 frame/checksum/timeout/recovery/reset tests");
        $finish;
    end

    initial begin
        #(64'd16_000_000_000);
        $fatal(1, "DHT11 simulation watchdog");
    end
endmodule
