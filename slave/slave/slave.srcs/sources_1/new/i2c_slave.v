`timescale 1ns / 1ps

// 7-bit I2C slave, 100 kHz master recommended. SDA requires a pull-up.
// Read sequence: temperature, humidity, distance[8], distance[7:0].
module i2c_slave #(
    parameter [6:0] ADDRESS = 7'h42
) (
    input wire clk,
    rst,
    input wire scl,
    inout wire sda,
    input wire [7:0] temperature,
    humidity,
    input wire [8:0] distance,
    output reg [7:0] received_data,
    output reg write_toggle, read_toggle, active
);
  localparam IDLE = 0, ADDRESS_BITS = 1, ADDRESS_ACK = 2,
               READ_BITS = 3, READ_ACK = 4, IGNORE = 5,
               WRITE_BITS = 6, WRITE_ACK = 7;
  reg [2:0] state;
  reg scl_meta, scl_sync, scl_prev;
  reg sda_meta, sda_sync, sda_prev;
  reg sda_low;
  reg [7:0] shift, tx_byte;
  reg [3:0] bit_count;
  reg ack_phase, matched, read_mode;
  reg [2:0] byte_index;
  reg [7:0] temp_snapshot, humidity_snapshot;
  reg [8:0] distance_snapshot;
  wire scl_rise = scl_sync && !scl_prev;
  wire scl_fall = !scl_sync && scl_prev;
  wire start_condition = scl_sync && sda_prev && !sda_sync;
  wire stop_condition = scl_sync && !sda_prev && sda_sync;
  assign sda = sda_low ? 1'b0 : 1'bz;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      scl_meta <= 1;
      scl_sync <= 1;
      scl_prev <= 1;
      sda_meta <= 1;
      sda_sync <= 1;
      sda_prev <= 1;
    end else begin
      scl_meta <= scl;
      scl_sync <= scl_meta;
      scl_prev <= scl_sync;
      sda_meta <= sda;
      sda_sync <= sda_meta;
      sda_prev <= sda_sync;
    end
  end

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= IDLE;
      sda_low <= 0;
      shift <= 0;
      tx_byte <= 0;
      bit_count <= 0;
      ack_phase <= 0;
      matched <= 0;
      byte_index <= 0;
      temp_snapshot <= 0;
      humidity_snapshot <= 0;
      distance_snapshot <= 0;
      received_data <= 0;
      write_toggle <= 0;
      read_toggle <= 0;
      active <= 0;
      read_mode <= 0;
    end else if (start_condition) begin
      state <= ADDRESS_BITS;
      sda_low <= 0;
      bit_count <= 0;
      shift <= 0;
      ack_phase <= 0;
      active <= 1;
    end else if (stop_condition) begin
      state   <= IDLE;
      sda_low <= 0;
      active <= 0;
    end else begin
      case (state)
        ADDRESS_BITS:
        if (scl_rise) begin
          shift <= {shift[6:0], sda_sync};
          if (bit_count == 7) begin
            matched <= (shift[6:0] == ADDRESS);
            read_mode <= sda_sync;
            bit_count <= 0;
            ack_phase <= 0;
            state <= ADDRESS_ACK;
            if (shift[6:0] == ADDRESS && sda_sync) begin
              temp_snapshot <= temperature;
              humidity_snapshot <= humidity;
              distance_snapshot <= distance;
            end
          end else bit_count <= bit_count + 1'b1;
        end
        ADDRESS_ACK:
        if (scl_fall) begin
          if (!ack_phase) begin
            sda_low   <= matched;
            ack_phase <= 1;
          end else begin
            ack_phase <= 0;
            if (!matched) begin
              sda_low <= 0;
              state   <= IGNORE;
            end else if (read_mode) begin
              tx_byte <= temp_snapshot;
              sda_low <= !temp_snapshot[7];
              byte_index <= 0;
              bit_count <= 0;
              state <= READ_BITS;
            end else begin
              sda_low <= 0;
              state <= WRITE_BITS;
            end
          end
        end
        // Master가 보낸 데이터를 저장하고 바이트마다 LED 상태를 반전
        WRITE_BITS: if (scl_rise) begin
          shift <= {shift[6:0], sda_sync};
          if (bit_count == 7) begin
            received_data <= {shift[6:0], sda_sync};
            write_toggle <= ~write_toggle;
            bit_count <= 0;
            ack_phase <= 0;
            state <= WRITE_ACK;
          end else bit_count <= bit_count + 1'b1;
        end
        WRITE_ACK: if (scl_fall) begin
          if (!ack_phase) begin
            sda_low <= 1;
            ack_phase <= 1;
          end else begin
            sda_low <= 0;
            ack_phase <= 0;
            state <= WRITE_BITS;
          end
        end
        READ_BITS: begin
          if (scl_rise) begin
            if (bit_count == 7) begin
              bit_count <= 0;
              read_toggle <= ~read_toggle;
              state <= READ_ACK;
              ack_phase <= 0;
            end else bit_count <= bit_count + 1'b1;
          end
          if (scl_fall) sda_low <= !tx_byte[7-bit_count];
        end
        READ_ACK: begin
          if (scl_fall && !ack_phase) begin
            sda_low   <= 0;
            ack_phase <= 1;
          end else if (scl_rise && ack_phase) begin
            if (sda_sync) state <= IGNORE;
            else begin
              if (byte_index < 3) byte_index <= byte_index + 1'b1;
              case (byte_index)
                0: tx_byte <= humidity_snapshot;
                1: tx_byte <= {7'b0, distance_snapshot[8]};
                2: tx_byte <= distance_snapshot[7:0];
                default: tx_byte <= 8'hff;
              endcase
              state <= READ_BITS;
              bit_count <= 0;
            end
          end
        end
        IGNORE: sda_low <= 0;
        default: begin
          sda_low <= 0;
          state   <= IDLE;
        end
      endcase
    end
  end
endmodule
