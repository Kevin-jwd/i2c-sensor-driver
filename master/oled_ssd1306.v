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
    reg data_mode;
    reg [7:0] tx_byte;
    reg [7:0] temp_buf, humidity_buf;
    reg [8:0] distance_buf;
    reg valid_buf;
    wire tick = (divider == DIV-1);
    wire [10:0] pixel_index = byte_index - 2;

    // Five-column, seven-pixel font, one byte per vertical column.
    function [39:0] glyph;
        input [7:0] c;
        begin
            case (c)
              "0": glyph=40'h3e4551493e; "1": glyph=40'h00427f4000;
              "2": glyph=40'h4649516142; "3": glyph=40'h3641494102;
              "4": glyph=40'h7f100c0a08; "5": glyph=40'h3949494927;
              "6": glyph=40'h3049494a3c; "7": glyph=40'h0305790101;
              "8": glyph=40'h3649494936; "9": glyph=40'h1e29494906;
              "T": glyph=40'h01017f0101; "E": glyph=40'h414949497f;
              "M": glyph=40'h7f020c027f; "P": glyph=40'h060909097f;
              "H": glyph=40'h7f0808087f; "U": glyph=40'h3f4040403f;
              "D": glyph=40'h3e4141417f; "I": glyph=40'h00417f4100;
              "S": glyph=40'h3149494946; "C": glyph=40'h224141413e;
              ":": glyph=40'h0000363600; "-": glyph=40'h0808080808;
              "%": glyph=40'h6131084643;
              default: glyph=0;
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

    // SSD1306 GDDRAM: each byte is eight vertical pixels, D0 at top.
    // Two pages per text row: expand each glyph pixel to a 2x2 block.
    function [7:0] pixel;
        input [10:0] index;
        reg [6:0] column;
        reg [2:0] page;
        reg [4:0] position;
        reg [2:0] subcolumn;
        reg [39:0] columns;
        reg [7:0] source_column;
        reg [15:0] expanded;
        integer bit_number;
        begin
            column = index[6:0];
            page = index[9:7];
            position = column / 12;
            subcolumn = (column % 12) / 2;
            // Pages 0-1: temperature, 2: blank, 3-4: humidity,
            // 5: blank, 6-7: distance. Each blank page is eight pixels high.
            if (page < 2) columns = glyph(screen_char(0, position));
            else if (page == 3 || page == 4) columns = glyph(screen_char(1, position));
            else if (page >= 6) columns = glyph(screen_char(2, position));
            else columns = 0;
            source_column = (subcolumn == 5) ? 0 : (columns >> (subcolumn * 8));
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1)
                expanded[bit_number*2 +: 2] = {2{source_column[bit_number]}};
            pixel = (page == 1 || page == 4 || page == 7) ? expanded[15:8] : expanded[7:0];
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
            temp_buf <= 0; humidity_buf <= 0; distance_buf <= 0; valid_buf <= 0;
        end else begin
            done <= 0;
            if (state == IDLE) begin
                if (start && ready) begin
                    temp_buf <= temperature; humidity_buf <= humidity;
                    distance_buf <= distance; valid_buf <= data_valid;
                    busy <= 1; error <= 0; data_mode <= 0;
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
                    else if (!data_mode) tx_byte <= command(byte_index-2);
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
                      if (error || (!data_mode && byte_index==33) ||
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
                      end else begin busy<=0; done<=1; state<=IDLE; end
                    end
                  endcase
                  default: begin sda_low<=0; scl_low<=0; busy<=0; state<=IDLE; end
                endcase
            end
        end
    end
endmodule
