`timescale 1ns / 1ps

module tick_generator (
    input clk,
    input rst,
    output reg tick
);

  parameter INPUT_FREQ = 100_000_000;             // 100MHz
  parameter TICK_FREQ  = 1_000;                   // 1kHz
  parameter TICK_CNT   = INPUT_FREQ / TICK_FREQ;  // 100_000

  reg [$clog2(TICK_CNT)-1:0] r_cnt = 0;

  always @(posedge clk, posedge rst) begin
    if (rst) begin
      r_cnt = 0;
      tick <= 0;
    end else begin
      // send 1tick pulse at the moment r_cnt reaches maximum value 
      if (r_cnt == TICK_CNT - 1) begin
        r_cnt <= 0;
        tick  <= 1;
        // returns to LOW instantly
      end else begin
        r_cnt <= r_cnt + 1;
        tick  <= 0;
      end
    end
  end

endmodule
