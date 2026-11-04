`timescale 1ns / 1ps

// SSD1306 128x64, I2C address 0x3c. Uses the same open-drain bus as the sensor.
module oled_ssd1306 #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer I2C_HZ = 100_000,
    parameter integer POWERUP_US = 100_000,
    parameter integer HEIGHT = 64
)(
    input wire clk, rst, start,
    input wire sda,
    input wire [7:0] temperature, humidity,
    input wire [8:0] distance,
    input wire data_valid,
    output reg sda_low, scl_low,
    output reg ready, busy, done, error
);
    localparam integer DIV = CLK_HZ / (I2C_HZ * 4);
    localparam integer DIV_WIDTH = (DIV > 1) ? $clog2(DIV) : 1;
    localparam integer POWERUP_CYCLES = (CLK_HZ / 1_000_000) * POWERUP_US;
    localparam integer POWER_WIDTH = (POWERUP_CYCLES > 1) ? $clog2(POWERUP_CYCLES) : 1;
    localparam integer PAGES = HEIGHT / 8;
    localparam IDLE=0, START=1, LOAD=2, SEND=3, ACK=4, STOP=5;
    reg [2:0] state;
    reg [1:0] phase;
    reg [DIV_WIDTH-1:0] divider;
    reg [POWER_WIDTH-1:0] power_count;
    reg [2:0] bit_index;
    reg [10:0] byte_index;
    reg data_mode, initialized, init_sequence;
    reg [7:0] tx_byte;
    reg [7:0] temp_buf, humidity_buf;
    reg [8:0] distance_buf;
    reg valid_buf;
    wire tick = (divider == DIV-1);
    wire [10:0] pixel_index = byte_index - 2;

  // 각 문자는 왼쪽 열부터 12비트씩 총 8열(96비트)로 정의한다.
  function [95:0] glyph;
    input [7:0] c;
    begin
      case (c)
        "0": glyph = 96'h3fc3fcc03c03c03c033fc3fc;
        "1": glyph = 96'h000000c0cfffc00c00000000;
        "2": glyph = 96'hc1cc1cc63c83f03f03c0cc0c;
        "3": glyph = 96'h39c39cc63c63c63c63c03c03;
        "4": glyph = 96'h0c00c00c0fff0c30ce0fc0f0;
        "5": glyph = 96'h3e33e3c63c63c63c6331f31f;
        "6": glyph = 96'h380380c63c63c6cc6c3f03f0;
        "7": glyph = 96'h00701f07b1e3f83e03003003;
        "8": glyph = 96'h39c39cc63c63c63c6339c39c;
        "9": glyph = 96'h0fc0fc363c63c63c6301c01c;
        "T": glyph = 96'h003003003fff003003003003;
        "E": glyph = 96'hc03c03c63c63c63c63ffffff;
        "M": glyph = 96'hffffff00c07000c00cffffff;
        "P": glyph = 96'h01c01c063063063063ffffff;
        "H": glyph = 96'hffffff060060060060ffffff;
        "U": glyph = 96'h3ff3ffc00c00c00c003ff3ff;
        "D": glyph = 96'h3fc3fcc03c03c03c03ffffff;
        "I": glyph = 96'h000000c03fffc03c03000000;
        "S": glyph = 96'h383383c63c63c63c63c1cc1c;
        "C": glyph = 96'h30c30cc03c03c03c033fc3fc;
        ":": glyph = 96'h00000000039c39c39c000000;
        "-": glyph = 96'h060060060060060060060060;
        "%": glyph = 96'h301486498320046089309406;
        default: glyph = 0;
      endcase
    end
  endfunction

    function [7:0] screen_char;
        input [2:0] page;
        input [4:0] pos;
        reg [8:0] value;
        reg [4:0] first_digit;
        begin
            screen_char = " "; value = 0; first_digit = 5;
            case (page)
              0: begin
                value = temp_buf;
                case(pos)
                  0:screen_char="T"; 1:screen_char="E"; 2:screen_char="M";
                  3:screen_char="P"; 4:screen_char=":"; 8:screen_char="C";
                endcase
              end
              1: begin
                value = humidity_buf; first_digit = 4;
                case(pos)
                  0:screen_char="H"; 1:screen_char="U"; 2:screen_char="M";
                  3:screen_char=":"; 7:screen_char="%";
                endcase
              end
              2: begin
                value = distance_buf;
                case(pos)
                  0:screen_char="D"; 1:screen_char="I"; 2:screen_char="S";
                  3:screen_char="T"; 4:screen_char=":"; 8:screen_char="C";
                  9:screen_char="M";
                endcase
              end
            endcase
            if (page < 3 && pos >= first_digit && pos <= first_digit + 2) begin
                if (!valid_buf) screen_char = "-";
                else if (pos == first_digit) screen_char = "0" + ((value / 100) % 10);
                else if (pos == first_digit + 1) screen_char = "0" + ((value / 10) % 10);
                else screen_char = "0" + (value % 10);
            end
        end
    endfunction

    function [7:0] command;
        input [5:0] index;
        begin
            case (index)
               0:command=8'hae;  1:command=8'hd5;  2:command=8'h80;
               3:command=8'ha8;  4:command=HEIGHT-1; 5:command=8'hd3;
               6:command=0;      7:command=8'h40;  8:command=8'h8d;
               9:command=8'h14; 10:command=8'h20; 11:command=0;
              12:command=8'ha1; 13:command=8'hc8; 14:command=8'hda;
              15:command=(HEIGHT==64)?8'h12:8'h02;
              16:command=8'h81; 17:command=8'h8f; 18:command=8'hd9;
              19:command=8'hf1; 20:command=8'hdb; 21:command=8'h40;
              22:command=8'ha4; 23:command=8'ha6; 24:command=8'h2e;
              25:command=8'haf; 26:command=8'h21; 27:command=0;
              28:command=8'h7f; 29:command=8'h22; 30:command=0;
              31:command=PAGES-1; default:command=0;
            endcase
        end
    endfunction

  // 8열의 비트맵 뒤에 문자 간격을 위한 빈 열을 둔다.
  function [11:0] enlarged_column;
    input [2:0] row;
    input [4:0] position;
    input [3:0] subcolumn;
    reg [95:0] columns;
    begin
      columns = glyph(screen_char(row, position));
      enlarged_column = (subcolumn < 8) ? (columns >> (subcolumn * 12)) : 12'b0;
    end
  endfunction

  // SSD1306 GDDRAM의 각 바이트는 세로 8픽셀이다.
  // 세 줄의 시작 위치는 위에서 각각 2, 26, 50픽셀이다.
  function [7:0] pixel;
    input [10:0] index;
    reg [6:0] column;
    reg [2:0] page;
    reg [4:0] position;
    reg [3:0] subcolumn;
    reg [11:0] row0, row1, row2;
    begin
      column = index[6:0];
      page = index[9:7];
      position = column / 9;
      subcolumn = column % 9;
      row0 = enlarged_column(0, position, subcolumn);
      row1 = enlarged_column(1, position, subcolumn);
      row2 = enlarged_column(2, position, subcolumn);
      case (page)
        0: pixel = {row0[5:0], 2'b00};
        1: pixel = {2'b00, row0[11:6]};
        2: pixel = 0;
        3: pixel = {row1[5:0], 2'b00};
        4: pixel = {2'b00, row1[11:6]};
        5: pixel = 0;
        6: pixel = {row2[5:0], 2'b00};
        7: pixel = {2'b00, row2[11:6]};
      endcase
    end
  endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ready <= 0; power_count <= 0; divider <= 0;
        end else begin
            if (!ready) begin
                if (power_count >= POWERUP_CYCLES-1) ready <= 1;
                else power_count <= power_count + 1'b1;
            end
            if (!busy || tick) divider <= 0;
            else divider <= divider + 1'b1;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE; phase <= 0; sda_low <= 0; scl_low <= 0;
            busy <= 0; done <= 0; error <= 0; byte_index <= 0;
            bit_index <= 0; tx_byte <= 0; data_mode <= 0;
            initialized <= 0; init_sequence <= 1;
            temp_buf <= 0; humidity_buf <= 0; distance_buf <= 0; valid_buf <= 0;
        end else begin
            done <= 0;
            if (state == IDLE) begin
                if (start && ready) begin
                    temp_buf <= temperature; humidity_buf <= humidity;
                    distance_buf <= distance; valid_buf <= data_valid;
                    busy <= 1; error <= 0; data_mode <= 0;
                    init_sequence <= !initialized;
                    byte_index <= 0; phase <= 0; state <= START;
                end
            end else if (tick) begin
                case (state)
                  START: case (phase)
                    0: begin scl_low<=0; sda_low<=0; phase<=1; end
                    1: begin sda_low<=1; phase<=2; end
                    2: begin scl_low<=1; phase<=0; state<=LOAD; end
                    default: phase<=0;
                  endcase
                  LOAD: begin
                    if (byte_index == 0) tx_byte <= 8'h78; // 0x3c + write
                    else if (byte_index == 1) tx_byte <= data_mode ? 8'h40 : 8'h00;
                    // Refresh: only reset the column/page address window.
                    else if (!data_mode) tx_byte <= command(init_sequence ? byte_index-2 : byte_index+24);
                    else tx_byte <= pixel(pixel_index);
                    bit_index <= 7; phase <= 0; state <= SEND;
                  end
                  SEND: case (phase)
                    0: begin sda_low<=!tx_byte[bit_index]; phase<=1; end
                    1: begin scl_low<=0; phase<=2; end
                    2: phase<=3;
                    3: begin
                      scl_low<=1; phase<=0;
                      if (bit_index==0) state<=ACK;
                      else bit_index<=bit_index-1'b1;
                    end
                  endcase
                  ACK: case (phase)
                    0: begin sda_low<=0; phase<=1; end
                    1: begin scl_low<=0; phase<=2; end
                    2: begin if (sda != 1'b0) error<=1; phase<=3; end
                    3: begin
                      scl_low<=1; phase<=0;
                      if (error || (!data_mode && byte_index==(init_sequence ? 33 : 7)) ||
                          (data_mode && byte_index==1+PAGES*128)) state<=STOP;
                      else begin byte_index<=byte_index+1'b1; state<=LOAD; end
                    end
                  endcase
                  STOP: case (phase)
                    0: begin scl_low<=1; sda_low<=1; phase<=1; end
                    1: begin scl_low<=0; phase<=2; end
                    2: begin sda_low<=0; phase<=3; end
                    3: begin
                      phase<=0;
                      if (!error && !data_mode) begin
                        data_mode<=1; byte_index<=0; state<=START;
                      end else begin
                        // Any NACK invalidates setup; next attempt reinitializes.
                        initialized <= !error;
                        busy<=0; done<=1; state<=IDLE;
                      end
                    end
                  endcase
                  default: begin sda_low<=0; scl_low<=0; busy<=0; state<=IDLE; end
                endcase
            end
        end
    end
endmodule
