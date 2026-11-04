# I2C Slave protocol

- FPGA clock: 100 MHz; recommended I2C clock: 100 kHz.
- Seven-bit address: `0x42` (`0x85` read address byte, `0x84` write address byte).
- Read transaction: START, `0x85`, ACK, then the bytes below, followed by STOP.
  The master ACKs each byte it wants to continue reading and NACKs the last byte.
- Read bytes: temperature (8 bits, degrees C), humidity (8 bits, %RH),
  distance high (only bit 0 used), distance low. Distance is in cm.
  Example: 300 cm = `01 2c`. After the fourth byte, further reads return `ff`.
- Sensor values are captured together when a matching read address is received.
  A new read transaction captures new values; the sensors update independently.
- Values are zero after reset until the sensors measure. DHT11 retains its last
  successful value on error; no validity/error flag is sent over I2C yet.
- Write data is acknowledged and displayed on LED[7:0]. Writes do not select
  a register or change sensor readings. LED[8] toggles per received write byte;
  LED[9] toggles per transmitted read byte. LED[15] stays on from START until
  STOP, including transactions addressed to other devices.
- SDA is open drain; use external pull-ups on SDA and SCL to 3.3 V.
  SCL is input-only and clock stretching is not implemented.
- SDA/JA1, SCL/JA2 as required by the assignment; assign the actual pins in XDC.
  The supplied XDC is not configured for the top ports yet.
- The Slave starts ultrasonic measurement automatically every 100 ms. The
  sensor FSM times out after approximately 25 ms of echo HIGH; timeouts
  retain the last successful measurement.

Run simulation from `tmp/i2c_sim`:

    xvlog ../../slave/slave/slave.srcs/sources_1/new/i2c_slave.v ../../slave/tb_i2c_slave.v
    xelab tb_i2c_slave -s i2c_slave_test
    xsim i2c_slave_test -runall
