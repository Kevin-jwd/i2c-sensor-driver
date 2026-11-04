`timescale 1ns / 1ps

module dht11 #(
    parameter integer CLK_HZ = 100_000_000
) (
    input clk,
    input rst,
    input start,
    inout dht11_data,
    output busy,
    output reg done,
    output reg error,
    output reg [7:0] humidity,
    output reg [7:0] temperature
);
    localparam IDLE = 0, START = 1, RESPONSE = 2, RESPONSE_LOW = 3,
               RESPONSE_HIGH = 4, BIT_LOW = 5, BIT_HIGH = 6,
               CHECK = 7, WAIT = 8;
    localparam US_DIV = CLK_HZ / 1_000_000;

    reg [3:0] state;
    reg [31:0] clk_count;
    reg [21:0] us_count;
    reg [5:0] bit_count;
    reg [39:0] data;
    reg data_meta, data_sync;
    wire tick = (clk_count == US_DIV - 1);
    wire [7:0] checksum = data[39:32] + data[31:24] + data[23:16] + data[15:8];

    // START에서만 LOW를 출력하고, 나머지 시간에는 센서가 선을 사용하도록 놓음
    assign dht11_data = (state == START) ? 1'b0 : 1'bz;
    assign busy = (state != IDLE);

    // 1us tick 생성 및 센서 입력을 clk에 동기화
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_count <= 0;
            data_meta <= 1;
            data_sync <= 1;
        end else begin
            if (tick) clk_count <= 0;
            else clk_count <= clk_count + 1;
            data_meta <= dht11_data;
            data_sync <= data_meta;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= WAIT;
            us_count <= 0;
            bit_count <= 0;
            data <= 0;
            done <= 0;
            error <= 0;
            humidity <= 0;
            temperature <= 0;
        end else begin
            done <= 0;
            // 1. start signal 수신
            if (state == IDLE && start) begin
                state <= START;
                us_count <= 0;
                bit_count <= 0;
                data <= 0;
                error <= 0;
            end else if (tick) begin
                us_count <= us_count + 1;
                // 응답이나 데이터가 200us 동안 바뀌지 않으면 수신 실패
                if (state >= RESPONSE && state <= BIT_HIGH && us_count >= 199) begin
                    error <= 1;
                    done <= 1;
                    us_count <= 0;
                    state <= WAIT;
                end else begin
                    case (state)
                        // 전원 인가 후 또는 측정 후 2.1초 대기
                        WAIT: if (us_count == 2_099_999) begin
                            us_count <= 0;
                            state <= IDLE;
                        end
                        IDLE: us_count <= 0;
                        // 2. DATA를 최소 18ms LOW로 내려 측정 요청 (여기서는 약 19ms)
                        // * DHT11 data sheet page | 6 *
                        // * the programmer of MCU will set Data Single-bus voltage level from high to low *
                        // * and this process must take at least 18ms to ensure DHT's deteciton of MCU's signal *
                        START: if (us_count == 18_999) begin
                            us_count <= 0;
                            state <= RESPONSE;
                        end
                        // 3. DATA를 놓고 센서의 응답 LOW를 기다림
                        RESPONSE: if (us_count >= 5 && !data_sync) begin
                            us_count <= 0;
                            state <= RESPONSE_LOW;
                        end
                        // 4. 센서 응답: 약 80us LOW 후 약 80us HIGH
                        // * DHT11 data sheet page | 7 *
                        // * Once DHT detects the start signal, it will send out a low-voltage-level response signal *
                        // * which lasts 80us *
                        RESPONSE_LOW: if (data_sync) begin
                            us_count <= 0;
                            state <= RESPONSE_HIGH;
                        end
                        RESPONSE_HIGH: if (!data_sync) begin
                            us_count <= 0;
                            state <= BIT_LOW;
                        end
                        // 5. 각 데이터 비트는 약 50us LOW로 시작
                        // * DHT11 data sheet page | 7 *
                        // * When DHT is sending data to MCU, every bit of data begins with the 50us low-voltage-level *
                        BIT_LOW: if (data_sync) begin
                            us_count <= 0;
                            state <= BIT_HIGH;
                        end
                        // HIGH 길이로 0/1을 구분해 총 40비트를 순서대로 저장
                        // * and the length of the following high-voltage-level signal determines wheter data bit is "0" or "1" *
                        BIT_HIGH: if (!data_sync) begin
                            data <= {data[38:0], (us_count >= 49)};
                            us_count <= 0;
                            bit_count <= bit_count + 1;
                            if (bit_count == 39) state <= CHECK;
                            else state <= BIT_LOW;
                        end
                        // 6. 앞의 4바이트 합과 체크섬이 같으면 온습도 저장
                        CHECK: begin
                            error <= (checksum != data[7:0]);
                            if (checksum == data[7:0]) begin
                                humidity <= data[39:32];
                                temperature <= data[23:16];
                            end
                            // 성공 또는 실패를 알리고 다음 측정까지 대기
                            done <= 1;
                            us_count <= 0;
                            state <= WAIT;
                        end
                        default: begin
                            us_count <= 0;
                            state <= WAIT;
                        end
                    endcase
                end
            end
        end
    end
endmodule
