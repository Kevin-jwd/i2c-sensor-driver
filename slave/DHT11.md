# DHT11 (minimal controller)

Active source: `slave/slave.srcs/sources_1/new/dht11.v`.
Active top: `slave/slave.srcs/sources_1/imports/slave/top_i2c_slave.v`.
Paths are relative to this folder.

- Only parameter: `CLK_HZ` (default 100 MHz, integer multiple of 1 MHz).
- `rst`: active HIGH. DATA is released during reset.
- `start`: one-clock request when `busy == 0`; HIGH enables periodic sampling.
- Wait 2.1 seconds after reset and after each completed attempt.
- Start signal: about 19 ms LOW (at least 18 ms).
- Receive 40 bits, distinguish 0/1 by HIGH duration, verify checksum.
- `humidity`, `temperature`: 8-bit integer %RH and degrees C.
- Decimal bytes participate in the checksum but are not output.
- `done`: one-clock completion pulse; `error`: 0 success, 1 checksum/timeout.
- On failure, retain the last successful temperature/humidity.
- Use `done && !error` when storing a fresh sample.
- Two input synchronizer registers are ordinary registers, without attributes.

The top requests periodic measurements. Its LEDs still show ultrasonic distance.
DATA requires an external pull-up to an FPGA-compatible voltage.

## Simulation

From the repository's `tmp/dht11_sim`, in a Vivado command shell:

```powershell
xvlog ../../slave/slave/slave.srcs/sources_1/new/dht11.v ../../slave/tb_dht11.v
xelab tb_dht11 -s dht11_test
xsim dht11_test -runall
```

The TB uses CLK_HZ=1 MHz with real protocol and waiting durations. Tests cover
frame decoding, checksum failure, no response, stuck LOW, recovery, reset,
completion pulses and busy request rejection.
