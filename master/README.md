# Basys3 I2C Master

Add these design files to a Vivado project targeting `xc7a35tcpg236-1`:
`top_i2c_master.v`, `i2c_master.v`, `oled_ssd1306.v`, `tick_generator.v`, `fnd_controller.v`.
Set `top_i2c_master` as top and add `master.xdc` as constraints.
The Master and Slave must be separate projects/boards: each contains its own
`tick_generator` module. Do not add both copies to the same design.

- SSD1306 OLED: 128x64, 7-bit address 0x3c. Connect its SDA and SCL to the
  same JA1/JA2 I2C bus as the sensor Slave, with common ground and 3.3 V-compatible
  power/logic. FND remains available. OLED shows TEMP, HUM and DIST with 2x (10x14 pixel) characters and 8-pixel blank lines.
- At power-up the OLED initializes after 100 ms and shows dashes. After each
  successful sensor read the OLED is refreshed. A BTNC request during an OLED
  update is queued until the bus is free. One pending request is remembered.
- OLED module must have its own appropriate SSD1306 initialization / power
  circuit, including its charge pump. This design uses the internal charge pump.
- BTND: reset. The Master reads the Slave automatically every 0.5 seconds;
  BTNC also requests an immediate reading from Slave address 0x42.
- SW1 SW0 = 00: distance in cm; 01: temperature in C; 10: humidity in %RH;
  11 also selects distance. The 4-digit FND shows only the numerical value.
- FND shows `----` until a successful read. The last values are retained if a
  later request receives a NACK. Press BTNC again to retry.
- LED[12]: I2C busy (sensor or OLED), LED[13]: sensor address NACK,
  LED[14]: sensor read failed, LED[15]: successful
  result with no subsequent failure, LED[7:0]: distance low byte.
  LED[11]: OLED NACK on last update, LED[10]: OLED transfer busy; LED[9:8] are off. A sensor NACK and failure remain until the next request.
- Master JA1 (J1/SDA) to Slave JA1 (J1/SDA), JA2 (L2/SCL) to JA2, and GND to
  GND. Both SDA and SCL need suitable external pull-ups to 3.3 V. Account for
  any pull-ups already installed on the bus.
- Standard 100 kHz; single master, no clock stretching or arbitration. The
  implemented Slave fits these assumptions. The Master reads temperature,
  humidity, distance high and distance low, ACKing the first three bytes and
  NACKing the last. Sensor validity/error is not present in the Slave protocol;
  successful I2C transfer does not establish that sensor measurement succeeded.
- For parameter changes, `CLK_HZ` must allow integer division by four times
  `I2C_HZ`; the default is 100 MHz / 100 kHz.

Simulation: compile the five Master design files, the current Slave
`slave/slave/slave.srcs/sources_1/new/i2c_slave.v`, and `tb_master_slave.v`.
The self-checking test covers sensor bytes, display selection, 9-bit distance,
address NACK, retained data and retry. It does not require hardware.

OLED simulation: `tb_oled_ssd1306.v` checks init bytes, ACKs and all 1024
framebuffer bytes; `tb_shared_oled_bus.v` checks queued sensor reads and OLED
NACK isolation on the shared bus. Actual display appearance is not yet tested.
