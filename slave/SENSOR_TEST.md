# Slave standalone sensor test

- Reset: BTND (lower button). The 100 MHz clock is on W5.
- Distance: normally shown as `d` and three digits in cm. The ultrasonic
  sensor measures automatically every 100 ms; BTNC is no longer needed.
- Temperature: hold BTNU; `t` and three digits in degrees C appear.
- Humidity: hold BTNL; `H` and three digits in %RH appear. BTNL has priority
  if BTNU is also held. Release buttons to return to distance.
- `---` for temperature/humidity means no valid DHT11 frame since reset.
  DHT11 waits 2.1 seconds on reset and samples about every 2.1 seconds.
- I2C: JA1 (J1) SDA, JA2 (L2) SCL. Pull both signals to 3.3 V; without
  a master they remain idle. Keep common ground when connecting the master.
- Sensors: JXADC XA4_P (N2) ultrasonic TRIG, XA3_P (M2) ultrasonic ECHO,
  XA2_P (L3) DHT11 DATA. DHT11 requires a pull-up to 3.3 V and common ground.
  Check the exact sensor module supply and output levels; ECHO must be 3.3 V
  compatible before connecting to the FPGA. A 5 V echo needs level conversion.
- LED[7:0], LED[8], LED[9], LED[15] remain assigned to I2C debug signals.
- Echo HIGH timeout is about 25 ms, allowing the HC-SR04 nominal 4 m range;
  a timeout retains the previous distance.

XDC: `slave/slave.srcs/constrs_1/imports/digilent-xdc-master/Basys3-Master_orginal.xdc`.
Paths above are relative to this folder. The I2C bus is not needed for display.

## DHT11 diagnostic LEDs

- LED10: at least one valid frame has arrived since reset.
- LED11: the latest attempt failed (timeout or checksum). Updated on completion.
- LED12: toggles after each attempt, successful or failed.
- LED13: current DATA logic level. It normally stays high; the short LOW pulses
  are too fast to see reliably. A steady LOW can indicate a wiring/pull-up issue.
- LED15 and LED[9:0] retain their I2C functions. To use the new indicators,
  regenerate the bitstream and program the FPGA again.
