// 10us trigger pulse를 센서에 인가
// echo pulse high level 시간 측정
// 측정한 시간 -> 거리 값 환산 (distanc)
// trigger pulse 주기 >= 60ms

module ultrasonic_sensor (
    input clk,
    input rst,
    input start,
    output reg trig,
    input echo,
    output reg [8:0] distance
);

  parameter IDLE = 2'b00, START_SIGNAL = 2'b01, WAIT_HIGH = 2'b10, READ_DATA = 2'b11;

  reg [1:0] state;
  wire tick;
  reg [14:0] tick_cnt;

  tick_generator #(
      .TICK_FREQ(1_000_000)
  ) u_tick_1Hz (
      .clk (clk),
      .rst (rst),
      .tick(tick)
  );

  always @(posedge clk, posedge rst) begin
    if (rst) begin
      state <= IDLE;
      trig <= 0;
      distance <= 14'b0;
      tick_cnt <= 0;
    end else if (tick) begin
      case (state)
        // 1. start 신호를 받으면 Trigger HIGH 출력 시작
        IDLE: begin
          if (start) begin
            trig <= 1;
            tick_cnt <= 0;
            state <= START_SIGNAL;
          end
        end
        // 2. Trigger를 약 10us 동안 HIGH로 유지한 뒤 LOW로 변경
        START_SIGNAL: begin
          if (tick_cnt == 10) begin
            trig <= 0;
            tick_cnt <= 0;
            state <= WAIT_HIGH;
          end else begin
            tick_cnt <= tick_cnt + 1;
          end
        end
        // 3. 센서가 Echo를 HIGH로 올릴 때까지 대기
        WAIT_HIGH: begin
          if (echo) begin
            tick_cnt <= 0;
            state <= READ_DATA;
          // Echo 응답이 없으면 약 10ms 후 대기 상태로 복귀
          end else if (tick_cnt > 10_000) begin
            state <= IDLE;
          end else begin
            tick_cnt <= tick_cnt + 1;
          end
        end
        // 4. Echo가 HIGH인 시간을 1us 단위로 측정
        READ_DATA: begin
          if (!echo) begin
            // 5. Echo HIGH 시간(us)을 58로 나누어 거리(cm)로 변환
            distance <= tick_cnt / 58;
            state <= IDLE;
          // 최대 약 4m 측정을 위해 Echo HIGH를 최대 약 25ms 대기
          end else if (tick_cnt > 25_000) begin
            state <= IDLE;
          end else begin
            tick_cnt <= tick_cnt + 1;
          end
        end
        default: state <= IDLE;
      endcase
    end
  end
endmodule
