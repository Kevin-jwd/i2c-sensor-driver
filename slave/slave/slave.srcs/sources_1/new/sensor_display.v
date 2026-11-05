`timescale 1ns / 1ps
// 4-digit Basys3 display: d=distance, t=temperature, H=humidity.
module sensor_display #(
    parameter integer CLK_HZ = 100_000_000
) (
    input clk,
    rst,
    input [1:0] select_sensor,
    input [8:0] distance,
    input [7:0] temperature,
    humidity,
    input dht_valid,
    output reg [3:0] an,
    output reg [7:0] seg
);
  localparam integer SCAN_DIV = CLK_HZ / 1000;
  localparam integer WIDTH = (SCAN_DIV > 1) ? $clog2(SCAN_DIV) : 1;
  reg [WIDTH-1:0] scan_count;
  reg [1:0] digit;
  reg [8:0] value;
  reg [3:0] number;
  reg blank_value;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      scan_count <= 0;
      digit <= 0;
    end else if (scan_count == SCAN_DIV - 1) begin
      scan_count <= 0;
      digit <= digit + 1'b1;
    end else scan_count <= scan_count + 1'b1;
  end

  always @* begin
    case (select_sensor)
      2'd1: value = {1'b0, temperature};
      2'd2: value = {1'b0, humidity};
      default: value = distance;
    endcase
    blank_value = (select_sensor != 0 && !dht_valid);
    case (digit)
      0: begin
        an = 4'b1110;
        number = value % 10;
      end
      1: begin
        an = 4'b1101;
        number = (value / 10) % 10;
      end
      2: begin
        an = 4'b1011;
        number = (value / 100) % 10;
      end
      default: begin
        an = 4'b0111;
        number = 0;
      end
    endcase
    if (digit == 3) begin
      case (select_sensor)
        2'd1: seg = 8'b10000111;  // t
        2'd2: seg = 8'b10001001;  // H
        default: seg = 8'b10100001;  // d
      endcase
    end else if (blank_value) seg = 8'b10111111;  // -
    else begin
      case (number)
        0: seg = 8'b11000000;
        1: seg = 8'b11111001;
        2: seg = 8'b10100100;
        3: seg = 8'b10110000;
        4: seg = 8'b10011001;
        5: seg = 8'b10010010;
        6: seg = 8'b10000010;
        7: seg = 8'b11111000;
        8: seg = 8'b10000000;
        9: seg = 8'b10010000;
        default: seg = 8'b11111111;
      endcase
    end
  end
endmodule
