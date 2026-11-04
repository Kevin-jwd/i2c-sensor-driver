`timescale 1ns / 1ps

// HC-SR04 measurement only: independent of I2C/SPI transport.
// start is a one-clock request, accepted only while busy == 0.
// done pulses for one clock on either success or timeout. distance_cm
// retains the last successful result; timeout describes the latest request.
module ultrasonic_sensor #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer TRIGGER_US = 10,
    parameter integer TIMEOUT_US = 30_000,
    parameter integer INTERVAL_US = 60_000
) (
    input wire clk,
    input wire rst,
    input wire start,
    input wire echo,
    output reg trig,
    output wire busy,
    output reg done,
    output reg timeout,
    output reg [15:0] distance_cm
);
    // CLK_HZ must be a positive integer multiple of 1 MHz.
    // INTERVAL_US >= 60_000 for the HC-SR04.
    localparam integer CYCLES_PER_US = CLK_HZ / 1_000_000;
    localparam integer TRIGGER_CYCLES = CYCLES_PER_US * TRIGGER_US;
    localparam integer TIMEOUT_CYCLES = CYCLES_PER_US * TIMEOUT_US;
    localparam integer INTERVAL_CYCLES = CYCLES_PER_US * INTERVAL_US;
    localparam integer CYCLES_PER_CM = CYCLES_PER_US * 58;
    localparam [2:0] IDLE = 0, TRIGGER = 1, WAIT_ECHO = 2,
                     MEASURE = 3, COOLDOWN = 4;

    reg [2:0] state;
    reg [31:0] phase_count;
    reg [31:0] interval_count;
    (* ASYNC_REG = "TRUE" *) reg echo_meta;
    (* ASYNC_REG = "TRUE" *) reg echo_sync;

    assign busy = (state != IDLE);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            echo_meta <= 0;
            echo_sync <= 0;
        end else begin
            echo_meta <= echo;
            echo_sync <= echo_meta;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            phase_count <= 0;
            interval_count <= 0;
            trig <= 0;
            done <= 0;
            timeout <= 0;
            distance_cm <= 0;
        end else begin
            done <= 0;
            if (state != IDLE && interval_count < INTERVAL_CYCLES)
                interval_count <= interval_count + 1;

            case (state)
                IDLE: begin
                    trig <= 0;
                    if (start) begin
                        timeout <= 0;
                        phase_count <= 0;
                        interval_count <= 0;
                        // A line already high is not a new sensor response.
                        if (echo_sync) begin
                            timeout <= 1;
                            done <= 1;
                            state <= COOLDOWN;
                        end else begin
                            trig <= 1;
                            state <= TRIGGER;
                        end
                    end
                end
                TRIGGER: begin
                    if (phase_count == TRIGGER_CYCLES - 1) begin
                        trig <= 0;
                        phase_count <= 0;
                        state <= WAIT_ECHO;
                    end else
                        phase_count <= phase_count + 1;
                end
                WAIT_ECHO: begin
                    if (echo_sync) begin
                        phase_count <= 1;
                        state <= MEASURE;
                    end else if (phase_count == TIMEOUT_CYCLES - 1) begin
                        timeout <= 1;
                        done <= 1;
                        state <= COOLDOWN;
                    end else
                        phase_count <= phase_count + 1;
                end
                MEASURE: begin
                    if (!echo_sync) begin
                        distance_cm <= phase_count / CYCLES_PER_CM;
                        done <= 1;
                        state <= COOLDOWN;
                    end else if (phase_count == TIMEOUT_CYCLES - 1) begin
                        timeout <= 1;
                        done <= 1;
                        state <= COOLDOWN;
                    end else
                        phase_count <= phase_count + 1;
                end
                COOLDOWN: begin
                    if (interval_count >= INTERVAL_CYCLES - 1)
                        state <= IDLE;
                end
                default: begin
                    trig <= 0;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
