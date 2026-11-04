`timescale 1ns / 1ps

module top_i2c_slave #(
    parameter integer CLK_HZ = 100_000_000
) (
    input clk,
    input rst,

    input scl,
    inout sda,
    input echo,
    output trig,
    output [15:0] led
);

    wire sensor_busy;
    wire sensor_done;
    wire sensor_timeout;
    wire [15:0] sensor_distance_cm;
    reg [15:0] distance_cm;
    reg distance_valid;
    reg measurement_timeout;

    // Automatically request the next measurement after the sensor's
    // 60 ms cooldown. A request is accepted for one clock before busy rises.
    ultrasonic_sensor #(.CLK_HZ(CLK_HZ)) u_ultrasonic_sensor (
        .clk(clk),
        .rst(rst),
        .start(!sensor_busy),
        .echo(echo),
        .trig(trig),
        .busy(sensor_busy),
        .done(sensor_done),
        .timeout(sensor_timeout),
        .distance_cm(sensor_distance_cm)
    );

    // Stable sensor register for the future I2C/SPI interface.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            distance_cm <= 0;
            distance_valid <= 0;
            measurement_timeout <= 0;
        end else if (sensor_done) begin
            measurement_timeout <= sensor_timeout;
            if (!sensor_timeout) begin
                distance_cm <= sensor_distance_cm;
                distance_valid <= 1;
            end
        end
    end

    // Temporary sensor debug display, replaced by the assignment's I2C
    // debug mapping when the bus interface is implemented.
    assign led = {5'b0, measurement_timeout, sensor_busy,
                  distance_valid, distance_cm[7:0]};

    // Release the bus until an I2C slave is implemented. scl is unused here.
    assign sda = 1'bz;
endmodule
