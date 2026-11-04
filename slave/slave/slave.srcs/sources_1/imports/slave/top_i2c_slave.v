module top_i2c_slave (
    input clk,
    input rst,

    input scl,
    inout sda,  // 양방향 입출력 포트

    inout dht11_data,

    output trig,
    input  echo,

    input [2:0] btn,
    input RsRx,
    output RsTx,

    output [7:0] seg,
    output [3:0] an,

    output [15:0] led
);

  wire start;
  wire [8:0] distance;
  wire [7:0] humidity;
  wire [7:0] temperature;
  wire dht11_busy;
  wire dht11_done;
  wire dht11_error;

  reg dht_valid;
  reg dht_last_error;
  reg dht_attempt_toggle;
  wire [1:0] display_select = btn[2] ? 2'd2 : (btn[1] ? 2'd1 : 2'd0);

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      dht_valid <= 0;
      dht_last_error <= 0;
      dht_attempt_toggle <= 0;
    end else if (dht11_done) begin
      dht_last_error <= dht11_error;
      dht_attempt_toggle <= ~dht_attempt_toggle;
      if (!dht11_error) dht_valid <= 1;
    end
  end

  sensor_display u_sensor_display (
      .clk(clk),
      .rst(rst),
      .select_sensor(display_select),
      .distance(distance),
      .temperature(temperature),
      .humidity(humidity),
      .dht_valid(dht_valid),
      .an(an),
      .seg(seg)
  );

  assign RsTx  = 1'b1;

  // 초음파 센서를 100ms마다 시작한다. start를 10us 유지해
  // 센서 모듈의 1us tick이 요청을 놓치지 않도록 한다.
  // Basys3 100MHz clock: 10,000,000 cycles = 100ms.
  localparam integer TRIGGER_PERIOD = 10_000_000;
  localparam integer TRIGGER_WINDOW = 1_000;
  localparam integer TRIGGER_WIDTH = (TRIGGER_PERIOD > 1) ? $clog2(TRIGGER_PERIOD) : 1;
  reg [TRIGGER_WIDTH-1:0] trigger_count;
  always @(posedge clk or posedge rst) begin
    if (rst) trigger_count <= 0;
    else if (trigger_count == TRIGGER_PERIOD-1) trigger_count <= 0;
    else trigger_count <= trigger_count + 1'b1;
  end
  assign start = (trigger_count < TRIGGER_WINDOW);
  wire [7:0] i2c_received;
  wire i2c_write_toggle, i2c_read_toggle, i2c_active;
  // LED[10:13]: DHT11 valid, last error, attempt toggle, DATA line.
  assign led = {i2c_active, 1'b0, dht11_data, dht_attempt_toggle,
                dht_last_error, dht_valid, i2c_read_toggle,
                i2c_write_toggle, i2c_received};

  i2c_slave u_i2c_slave (
      .clk(clk),
      .rst(rst),
      .scl(scl),
      .sda(sda),
      .temperature(temperature),
      .humidity(humidity),
      .distance(distance),
      .received_data(i2c_received),
      .write_toggle(i2c_write_toggle),
      .read_toggle(i2c_read_toggle),
      .active(i2c_active)
  );

  // =========== DHT11 (온습도 센서) 모듈 ===========
  dht11 u_dht11 (
      .clk(clk),
      .rst(rst),
      .start(1'b1),
      .dht11_data(dht11_data),
      .busy(dht11_busy),
      .done(dht11_done),
      .error(dht11_error),
      .humidity(humidity),
      .temperature(temperature)

  );

  // =========== HC-SR04 (초음파 센서) 모듈 ===========
  ultrasonic_sensor u_ultrasonic_sensor (
      .clk(clk),
      .rst(rst),
      .start(start),
      .trig(trig),
      .echo(echo),
      .distance(distance)
  );

endmodule
