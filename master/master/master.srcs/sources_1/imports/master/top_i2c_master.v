`timescale 1ns / 1ps
module top_i2c_master #(
    parameter CLK_HZ = 100_000_000,
    parameter I2C_HZ = 100_000,
    parameter OLED_HEIGHT = 64
) (
    input clk,
    rst,
    start,
    input [1:0] select_sensor,
    inout sda,
    output scl,
    output [3:0] an,
    output [7:0] seg,
    output [15:0] led
);
  // 센서 값을 0.5초마다 읽는다. 버튼으로 즉시 읽기도 가능하다.
  localparam POLL_CYCLES = CLK_HZ / 2;
  localparam ACTIVE_DISTANCE_CM = 50;
  localparam POLL_WIDTH  = (POLL_CYCLES > 1) ? $clog2(POLL_CYCLES) : 1;
  reg [POLL_WIDTH-1:0] poll_count;
  reg start_meta, start_sync, start_prev;
  wire start_pulse = start_sync && !start_prev;
  wire busy, done, error;
  wire sensor_sda_low, sensor_scl_low;
  wire oled_sda_low, oled_scl_low, oled_busy, oled_done, oled_error, oled_ready;
  reg sensor_start, oled_start, pending_read, pending_oled, oled_failed;
  assign sda = (sensor_sda_low || oled_sda_low) ? 1'b0 : 1'bz;
  assign scl = (sensor_scl_low || oled_scl_low) ? 1'b0 : 1'bz;
  wire [7:0] temperature, humidity;
  wire [8:0] distance;
  reg valid, failed;
  wire tick;
  wire [13:0] display_value = (select_sensor == 2'b01) ? {6'b0, temperature} :
                                (select_sensor == 2'b10) ? {6'b0, humidity} :
                                {5'b0, distance};
  wire [7:0] fnd_seg;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      start_meta <= 0;
      start_sync <= 0;
      start_prev <= 0;
      valid <= 0;
      failed <= 0;
      sensor_start <= 0;
      oled_start <= 0;
      pending_read <= 0;
      pending_oled <= 1;
      oled_failed <= 0;
      poll_count <= 0;
    end else begin
      sensor_start <= 0;
      oled_start   <= 0;
      if (poll_count == POLL_CYCLES - 1) begin
        poll_count   <= 0;
        pending_read <= 1;
      end else poll_count <= poll_count + 1'b1;
      if (start_pulse) pending_read <= 1;
      if (done && !error) pending_oled <= 1;
      // 대기 화면은 매 프레임을 이어 그리되, 센서 읽기 요청이 우선이다.
      if (oled_done && !oled_error && valid && distance > ACTIVE_DISTANCE_CM)
        pending_oled <= 1;
      if (oled_done) oled_failed <= oled_error;
      // 두 전송기는 같은 버스를 공유하므로 한 번에 하나만 시작
      if (!busy && !oled_busy && !sensor_start && !oled_start) begin
        if (pending_read) begin
          sensor_start <= 1;
          pending_read <= 0;
        end else if (pending_oled && oled_ready) begin
          oled_start   <= 1;
          pending_oled <= 0;
        end
      end
      start_meta <= start;
      start_sync <= start_meta;
      start_prev <= start_sync;
      if (sensor_start) failed <= 0;
      if (done) begin
        if (error) failed <= 1;
        else valid <= 1;
      end
    end
  end

  i2c_master #(
      .CLK_HZ(CLK_HZ),
      .I2C_HZ(I2C_HZ),
      .DRIVE_BUS(0)
  ) u_i2c_master (
      .clk(clk),
      .rst(rst),
      .start(sensor_start),
      .sda(sda),
      .scl(),
      .sda_drive_low(sensor_sda_low),
      .scl_drive_low(sensor_scl_low),
      .busy(busy),
      .done(done),
      .error(error),
      .temperature(temperature),
      .humidity(humidity),
      .distance(distance)
  );
  oled_ssd1306 #(
      .CLK_HZ(CLK_HZ),
      .I2C_HZ(I2C_HZ),
      .HEIGHT(OLED_HEIGHT)
  ) u_oled (
      .clk(clk),
      .rst(rst),
      .start(oled_start),
      .sda(sda),
      .temperature(temperature),
      .humidity(humidity),
      .distance(distance),
      .data_valid(valid),
      .standby(valid && distance > ACTIVE_DISTANCE_CM),
      .sda_low(oled_sda_low),
      .scl_low(oled_scl_low),
      .ready(oled_ready),
      .busy(oled_busy),
      .done(oled_done),
      .error(oled_error)
  );
  tick_generator #(
      .INPUT_FREQ(CLK_HZ),
      .TICK_FREQ (1000)
  ) u_tick (
      .clk (clk),
      .rst (rst),
      .tick(tick)
  );
  fnd_controller u_fnd (
      .clk(clk),
      .rst(rst),
      .tick(tick),
      .in_data(display_value),
      .an(an),
      .seg(fnd_seg)
  );
  // Before the first successful read display dashes; decimal point off.
  assign seg = valid ? {1'b1, fnd_seg[6:0]} : 8'b10111111;
  assign led = {
    valid && !failed,
    failed,
    failed,
    (busy || oled_busy),
    oled_failed,
    oled_busy,
    2'b0,
    distance[7:0]
  };
endmodule
