# Slave: ultrasonic sensor

`ultrasonic_sensor.v` measures HC-SR04 distance independently of the transport.
`top_i2c_slave.v` instantiates the sensor and automatically measures after reset
and after each cooldown. Add both files as design sources and select
`top_i2c_slave` as the synthesis top. The top exposes `echo` (input) and `trig`
(output); assign these to the connected PMOD pins in the project's XDC.
I2C is pending: SDA is released and SCL is unused.

The top retains a 16-bit successful distance in `distance_cm` for future bus
reads. Temporary debug LEDs: [7:0] = low byte of distance in cm, [8] = a
successful value exists, [9] = sensor busy (including cooldown), [10] = latest
measurement timed out, [15:11] = zero. The previous distance/valid flag remain
on timeout. This temporary map will change to the assignment's I2C LED map
when the bus interface is integrated.

- Default clock: 100 MHz; active-high asynchronous reset `rst`.
- Pulse `start` for one clock when `busy == 0`; requests during busy are ignored.
- `trig`: 10 us pulse. Synchronize the asynchronous `echo` through two registers.
- Distance: echo high cycles / (clock cycles per us * 58), truncated to cm.
- `done`: one-clock pulse for success or timeout. Capture `distance_cm` only
  when `done && !timeout`; it retains the last successful result on failure.
- `timeout`: set for a missing response, excessively long echo, or echo already
  high when starting. Clears on reset or the next accepted request.
- `busy` includes cooldown, enforcing at least 60 ms between trigger starts.
- Parameters require an integer-MHz clock, positive trigger/timeout values,
  and `INTERVAL_US >= 60000`. Counters and calculated cycle counts must fit 32 bits.

Suggested integration: latch a successful measurement into a sensor register;
let the I2C slave read it as two bytes. Snapshot both bytes at the beginning of
a read so a sensor update cannot mix bytes. An SPI slave can use the same
register interface later. Address, byte order and register map must be agreed
with the Master implementation before integration.

## Simulation (Vivado command shell)

Run in a scratch directory, with paths adjusted to the repository:

```powershell
xvlog ../../slave/ultrasonic_sensor.v ../../slave/tb_ultrasonic_sensor.v
xelab tb_ultrasonic_sensor -s ultrasonic_test
xsim ultrasonic_test -runall
```

The testbench checks 100 cm and 2 cm, 10 us trigger width, 60 ms spacing,
ignored busy requests, missing/stuck echo timeouts, recovery, and reset.

Before wiring, verify the actual HC-SR04 supply and Echo output voltage.
Match Echo to the Basys3's 3.3 V input level using appropriate level conversion
when needed. Pin assignments are intentionally left for board integration.
