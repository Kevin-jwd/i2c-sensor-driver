`timescale 1ns / 1ps

module fnd_controller (
    input clk,
    input rst,
    input tick,
    input [13:0] in_data,
    output [3:0] an,
    output [7:0] seg
);

  wire [1:0] w_sel;
  wire [3:0] w_d1, w_d10, w_d100, w_d1000;

  fnd_digit_select u_fnd_digit_select (
      .clk(clk),
      .rst(rst),
      .tick(tick),
      .sel(w_sel)
  );

  fnd_digit_display u_fnd_digit_display (
      .clk(clk),
      .tick(tick),
      .rst(rst),
      .sel(w_sel),
      .d1(w_d1),
      .d10(w_d10),
      .d100(w_d100),
      .d1000(w_d1000),
      .an(an),
      .seg(seg)
  );

  bin2bcd_4digit u_bin2bcd_4digit (
      .in_data(in_data),
      .d1(w_d1),
      .d10(w_d10),
      .d100(w_d100),
      .d1000(w_d1000)
  );

endmodule

module fnd_digit_select (
    input clk,
    input rst,
    input tick,
    output reg [1:0] sel
);

  always @(posedge clk or posedge rst) begin
    if (rst)
      sel <= 2'b00;
    else if (tick)
      sel <= sel + 1'b1;
  end

endmodule

module bin2bcd_4digit (
    input  [13:0] in_data,
    output [3:0] d1,
    output [3:0] d10,
    output [3:0] d100,
    output [3:0] d1000
);

  assign d1 = in_data % 10;
  assign d10 = (in_data / 10) % 10;
  assign d100 = (in_data / 100) % 10;
  assign d1000 = (in_data / 1000) % 10;

endmodule

module fnd_digit_display (
    input clk,
    input tick,
    input rst,
    input [1:0] sel,
    input [3:0] d1,
    input [3:0] d10,
    input [3:0] d100,
    input [3:0] d1000,
    output reg [3:0] an,
    output reg [7:0] seg
);

  reg [3:0] bcd_data;
  reg [$clog2(500)-1:0] blink_cnt;
  reg blink;

  always @(*) begin
    case (sel)
      2'b00: begin
        bcd_data = d1;
        an = 4'b1110;
      end
      2'b01: begin
        bcd_data = d10;
        an = 4'b1101;
      end
      2'b10: begin
        bcd_data = d100;
        an = 4'b1011;
      end
      2'b11: begin
        bcd_data = d1000;
        an = 4'b0111;
      end
      default: begin
        bcd_data = 4'b0000;
        an = 4'b1111;
      end
    endcase
  end

  always @(*) begin
    seg[7] = (sel == 2'b10) ? blink : 1'b1;

    case (bcd_data)
      4'd0: seg[6:0] = 7'b1000000;
      4'd1: seg[6:0] = 7'b1111001;
      4'd2: seg[6:0] = 7'b0100100;
      4'd3: seg[6:0] = 7'b0110000;
      4'd4: seg[6:0] = 7'b0011001;
      4'd5: seg[6:0] = 7'b0010010;
      4'd6: seg[6:0] = 7'b0000010;
      4'd7: seg[6:0] = 7'b1111000;
      4'd8: seg[6:0] = 7'b0000000;
      4'd9: seg[6:0] = 7'b0010000;
      default: seg[6:0] = 7'b1111111;
    endcase
  end

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      blink_cnt <= 0;
      blink <= 1'b0;
    end else if (tick) begin
      if (blink_cnt == 499) begin
        blink_cnt <= 0;
        blink <= ~blink;
      end else begin
        blink_cnt <= blink_cnt + 1'b1;
      end
    end
  end

endmodule
