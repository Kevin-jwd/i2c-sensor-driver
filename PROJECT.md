# Project

## 유형
Basys3 FPGA 2대에서 동작하는 I²C 센서 드라이버 및 표시 장치 프로젝트.

## 목표와 사용자
Slave가 DHT11 온습도와 초음파 거리를 측정해 Master로 보내고, Master가 값을 FND와 SSD1306 OLED에 표시한다. 사용자 요구에는 UART 출력도 포함되어 있으나 현재 구현 완료로 가정하지 않는다.

## 기술 스택·실행 환경
Verilog HDL, AMD/Xilinx Vivado 프로젝트와 XDC, Basys3 보드(`xc7a35tcpg236-1`). 각 `.xpr`은 Vivado Simulator를 설정한다. 기본 보드 클록은 100 MHz다.

## 아키텍처
- `slave/slave/slave.xpr`: DHT11 단일 데이터선, 초음파 Trigger/Echo, I²C Slave 및 보드 FND. 읽기 주소는 기본 7비트 `0x42`다.
- `master/master/master.xpr`: I²C Master, FND와 128×64 SSD1306 OLED. OLED 기본 7비트 주소는 `0x3C`다.
- Master와 Slave는 별도 보드로, Master 측 OLED와 센서 Slave가 I²C SDA/SCL을 공유한다. 기본 통신 속도는 100 kHz다.
- 초음파 측정 요청은 약 100 ms 주기, Master 읽기 요청은 약 0.5초 주기다. 센서 유효성은 현재 I²C 값에 포함되지 않는다.
- 주요 진입점과 테스트 경로는 `AGENTS.md`를 참조한다. 프로젝트에 포함된 소스와 저장소의 별도 사본은 서로 다를 수 있다.

## 실행·검증
각 `.xpr`을 Vivado에서 각각 열어 합성·구현·시뮬레이션한다. `master/README.md`와 `slave/README.md`에 테스트벤치 및 시뮬레이션 안내가 있으나 일부 Slave 문서는 현재 설계와 다르므로 실행 전 인터페이스를 확인한다. 저장소 전체에 적용할 단일 검증 명령은 확인되지 않아 `.ai/verification.yaml`의 명령을 미설정으로 유지한다. 테스트 파일 존재는 통과를 의미하지 않는다.

## 제약
기존 프로젝트 사실·사용자 변경·모델 선택·검증 명령을 보존한다. 비밀값을 이 파일에 저장하지 않는다. 확인되지 않은 프레임워크·게임·제품 요구를 넣지 않는다.

최소한의 이해하기 쉬운 구현을 선호한다. 실제 배선 시 Basys3 3.3 V 입출력과 센서·OLED의 전압, 공통 접지 및 풀업을 확인한다. Master와 Slave 프로젝트는 별도로 유지한다.
