# 초음파 센서 동작 과정

Slave 보드에서 초음파 센서의 Echo 펄스 길이를 측정해 거리를 cm 단위로 계산한다. 구현은 [ultrasonic_sensor.v](slave/slave/slave.srcs/sources_1/imports/slave/ultrasonic_sensor.v), 측정 시작 주기는 [top_i2c_slave.v](slave/slave/slave.srcs/sources_1/imports/slave/top_i2c_slave.v)에 있다.

## 연결과 초기 상태

| 신호 | 방향 | Slave FPGA 핀 | 역할 |
| --- | --- | --- | --- |
| `trig` | FPGA → 센서 | N2 | 측정 시작 펄스 |
| `echo` | 센서 → FPGA | M2 | 왕복 시간에 해당하는 HIGH 펄스 |

센서와 보드의 GND는 공통으로 연결한다. 사용하는 모듈의 전원 및 Echo 출력 전압을 확인해야 한다. 일반적인 5 V HC-SR04의 Echo는 5 V일 수 있으므로 Basys3의 3.3 V FPGA 입력에 직접 연결하지 말고 전압 변환 회로를 사용한다.

별도 센서 설정 명령이나 I²C 주소는 없다. 리셋 시 상태는 `IDLE`, `trig`와 `distance`는 0으로 초기화된다. 모듈 내부 [tick_generator.v](slave/slave/slave.srcs/sources_1/imports/new/tick_generator.v)가 기본 100 MHz 클록에서 1 MHz tick을 만들어 1 µs 단위로 시간을 잰다.

## 측정 순서

1. Top은 100 MHz 기준 `10,000,000`클록마다 `start`를 약 10 µs 동안 HIGH로 만들어 약 100 ms 간격으로 측정을 요청한다.
2. **IDLE**: `start`를 감지하면 `trig`를 HIGH로 올리고 카운터를 0으로 만든다.
3. **START_SIGNAL**: 약 10 µs 동안 HIGH를 유지한 뒤 `trig`를 LOW로 내린다. 센서가 초음파를 발사하는 시작 신호다.
4. **WAIT_HIGH**: 센서가 `echo`를 HIGH로 올릴 때까지 기다린다. 약 10 ms 동안 응답이 없으면 `IDLE`로 돌아간다.
5. **READ_DATA**: `echo`가 HIGH인 동안 1 µs마다 카운터를 증가시킨다. LOW로 내려가면 경과 시간으로 거리를 계산한다. HIGH가 약 25 ms를 초과해도 대기 상태로 돌아간다.
6. 성공적으로 측정한 `distance`는 다음 성공 측정까지 유지된다. 타임아웃 때는 이전 거리 값을 유지하며, 별도의 오류 출력은 없다.

```text
IDLE → START_SIGNAL → WAIT_HIGH → READ_DATA → IDLE
                          └─ 응답 타임아웃 ───→ IDLE
                                      └─ Echo 타임아웃 → IDLE
```

## 거리 계산과 Master 전달

센서가 반환한 시간은 초음파가 물체까지 갔다가 돌아온 왕복 시간이다. 코드에서는 이 시간을 이용해 정수 나눗셈을 한다.

```text
거리(cm) = Echo HIGH 시간(µs) / 58
예: 약 5,800 µs / 58 = 약 100 cm
```

소수점은 버리며 결과는 9비트 `distance`에 저장한다. 약 25 ms 제한은 약 4 m 수준의 왕복 시간에 해당하지만 실제 측정 범위와 오차는 센서와 환경에 따른다.

Slave의 [i2c_slave.v](slave/slave/slave.srcs/sources_1/new/i2c_slave.v)는 Master가 주소 `0x42`로 읽기를 시작할 때 온도·습도·거리를 함께 복사한다. 이어서 온도, 습도, 거리 상위 비트가 들어 있는 바이트, 거리 하위 8비트 순으로 총 4바이트를 보낸다. Master는 기본적으로 약 0.5초마다 읽고 OLED와 FND에 사용하므로, 표시 값은 센서의 약 100 ms 측정 주기마다 바로 바뀌지는 않는다.
