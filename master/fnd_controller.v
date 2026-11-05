`timescale 1ns / 1ps

// 1 kHz tick마다 한 자리를 선택해 4자리 7-segment를 표시한다.
module fnd_controller (
    input clk,
    input rst,
    input tick,
    input [13:0] in_data,
    output reg [3:0] an,
    output reg [7:0] seg
);
  reg [1:0] digit;
  reg [3:0] number;

  always @(posedge clk or posedge rst) begin
    if (rst) digit <= 0;
    else if (tick) digit <= digit + 1'b1;
  end

  // an과 seg는 모두 LOW일 때 켜진다.
  always @* begin
    case (digit)
      0: begin an = 4'b1110; number = in_data % 10; end
      1: begin an = 4'b1101; number = (in_data / 10) % 10; end
      2: begin an = 4'b1011; number = (in_data / 100) % 10; end
      3: begin an = 4'b0111; number = (in_data / 1000) % 10; end
    endcase

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
endmodule
