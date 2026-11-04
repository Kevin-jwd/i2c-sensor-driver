`timescale 1ns / 1ps

// Read four bytes from the project I2C slave (no clock stretching).
module i2c_master #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer I2C_HZ = 100_000,
    parameter [6:0] ADDRESS = 7'h42,
    parameter DRIVE_BUS = 1
) (
    input wire clk,
    rst,
    start,
    inout wire sda,
    output wire scl,
    output wire sda_drive_low,
    scl_drive_low,
    output reg busy,
    done,
    error,
    output reg [7:0] temperature,
    humidity,
    output reg [8:0] distance
);
  localparam integer DIV = CLK_HZ / (I2C_HZ * 4);
  localparam integer WIDTH = (DIV > 1) ? $clog2(DIV) : 1;
  localparam IDLE=0, START=1, ADDRESS_BITS=2, ADDRESS_ACK=3,
               READ_BITS=4, READ_ACK=5, STOP=6;
  reg [2:0] state;
  reg [1:0] phase, byte_index;
  reg [2:0] bit_index;
  reg [WIDTH-1:0] divider;
  reg sda_low, scl_low;
  reg [7:0] rx_byte;
  reg [7:0] temp_buffer, humidity_buffer;
  reg [8:0] distance_buffer;
  wire [7:0] address_byte = {ADDRESS, 1'b1};
  wire tick = (divider == DIV - 1);
  assign sda = (DRIVE_BUS && sda_low) ? 1'b0 : 1'bz;
  assign sda_drive_low = sda_low;
  assign scl_drive_low = scl_low;
  assign scl = scl_low ? 1'b0 : 1'bz;

  // DIV must be >= 1. No clock stretching or multi-master arbitration.
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      divider <= 0;
    end else if (!busy || tick) begin
      divider <= 0;
    end else begin
      divider <= divider + 1'b1;
    end
  end

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= IDLE;
      phase <= 0;
      bit_index <= 0;
      byte_index <= 0;
      scl_low <= 0;
      sda_low <= 0;
      busy <= 0;
      done <= 0;
      error <= 0;
      rx_byte <= 0;
      temp_buffer <= 0;
      humidity_buffer <= 0;
      distance_buffer <= 0;
      temperature <= 0;
      humidity <= 0;
      distance <= 0;
    end else begin
      done <= 0;
      if (state == IDLE) begin
        if (start) begin
          busy  <= 1;
          error <= 0;
          phase <= 0;
          state <= START;
        end
      end else if (tick) begin
        case (state)
          START:
          case (phase)
            0: begin
              scl_low <= 0;
              sda_low <= 0;
              phase   <= 1;
            end
            1: begin
              sda_low <= 1;
              phase   <= 2;
            end
            2: begin
              scl_low <= 1;
              phase <= 0;
              bit_index <= 7;
              state <= ADDRESS_BITS;
            end
            default: phase <= 0;
          endcase
          ADDRESS_BITS:
          case (phase)
            0: begin
              sda_low <= !address_byte[bit_index];
              phase   <= 1;
            end
            1: begin
              scl_low <= 0;
              phase   <= 2;
            end
            2: phase <= 3;
            3: begin
              scl_low <= 1;
              phase   <= 0;
              if (bit_index == 0) state <= ADDRESS_ACK;
              else bit_index <= bit_index - 1'b1;
            end
          endcase
          ADDRESS_ACK:
          case (phase)
            0: begin
              sda_low <= 0;
              phase   <= 1;
            end
            1: begin
              scl_low <= 0;
              phase   <= 2;
            end
            2: begin
              if (sda != 1'b0) error <= 1;
              phase <= 3;
            end
            3: begin
              scl_low <= 1;
              phase   <= 0;
              if (error) state <= STOP;
              else begin
                bit_index <= 7;
                byte_index <= 0;
                state <= READ_BITS;
              end
            end
          endcase
          READ_BITS:
          case (phase)
            0: begin
              sda_low <= 0;
              phase   <= 1;
            end
            1: begin
              scl_low <= 0;
              phase   <= 2;
            end
            2: begin
              rx_byte[bit_index] <= sda;
              phase <= 3;
            end
            3: begin
              scl_low <= 1;
              phase   <= 0;
              if (bit_index == 0) begin
                case (byte_index)
                  0: temp_buffer <= rx_byte;
                  1: humidity_buffer <= rx_byte;
                  2: distance_buffer[8] <= rx_byte[0];
                  3: distance_buffer[7:0] <= rx_byte;
                endcase
                state <= READ_ACK;
              end else bit_index <= bit_index - 1'b1;
            end
          endcase
          READ_ACK:
          case (phase)
            0: begin
              sda_low <= (byte_index != 3);
              phase   <= 1;
            end
            1: begin
              scl_low <= 0;
              phase   <= 2;
            end
            2: phase <= 3;
            3: begin
              scl_low <= 1;
              sda_low <= 0;
              phase   <= 0;
              if (byte_index == 3) state <= STOP;
              else begin
                byte_index <= byte_index + 1'b1;
                bit_index <= 7;
                state <= READ_BITS;
              end
            end
          endcase
          STOP:
          case (phase)
            0: begin
              scl_low <= 1;
              sda_low <= 1;
              phase   <= 1;
            end
            1: begin
              scl_low <= 0;
              phase   <= 2;
            end
            2: begin
              sda_low <= 0;
              phase   <= 3;
            end
            3: begin
              if (!error) begin
                temperature <= temp_buffer;
                humidity <= humidity_buffer;
                distance <= distance_buffer;
              end
              busy  <= 0;
              done  <= 1;
              phase <= 0;
              state <= IDLE;
            end
          endcase
          default: begin
            scl_low <= 0;
            sda_low <= 0;
            busy <= 0;
            state <= IDLE;
          end
        endcase
      end
    end
  end
endmodule

