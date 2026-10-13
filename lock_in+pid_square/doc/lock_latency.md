# Pipeline registers of v2.0.1 (FPGA timing) — added latencies

Port of the timing work of `lock_in+pid_harmonic` v2.3.19 (its `doc/lock_latency.md` explains the method; the user
allowed adding latency on 2026-10-12). Up to v2.0.0 the FPGA did not meet timing at 125 MHz because of long
combinational chains of the loop (PID sum → ctrl → out mux → + modulation → DAC / scope muxes / lock control). v2.0.1 registers those chains. **The behaviour is the one of v2.0.0 except
for the latencies below** (checked bit by bit in simulation, `test/lock_latency_sim.sh`).

## Latency of each signal with respect to v2.0.0

| Signal | Added | ns |
|---|---|---|
| Square generator (`sq_ref/sq_quad/sq_phas`, `square_trig`) | 0 (already registered) | 0 |
| References into the square lock-in | +1 | 8 |
| `sqXo`, `sqYo`, `sqFo`, `sqX_28..sqF_28` (the square lock-in already met timing: not changed) | 0 | 0 |
| PID outputs (`pidA_out`, `pidB_out`), from the PID input | +1 | 8 |
| `out1`, `out2` (DAC), for everything that goes out (out mux and square modulation, both registered before the sum) | +1 | 8 |
| LOCK MODE loop `in1` → sqY → PID A → `ctrl_A` → `out1` | +2 | 16 |

**Phase of the lock-in.** The square generator was already registered and the square lock-in already met timing
(v2.0.0): neither is changed. The outputs to the DACs (out mux and square modulation, both registered before the
sum) come 1 clock later, and the references reach the lock-in 1 clock later too (one more register, `ref_X0..F0`),
so the phase measured through DAC → system → ADC **does not change** (without it the phase would move by
−360° · f · 8 ns: −90° at 31.25 MHz). `test/sq_lockin_sim.sh` (loop OUT1 → IN1 inside the testbench) still measures a
loop latency of 2 ticks and the same X/Y/F at every frequency and delay.

Blocks rewritten without latency (same values): `sat14` (mask instead of barrel shifter), integrator of the PID
(ISR shift in parallel with the saturation). The PID derivative with `DSR` > 0 samples a delayed input at other
points (same behaviour, other sampling phase).

## Verification

`test/lock_latency_sim.sh` (xsim, the `lock.v` of the working tree side by side with the one of v2.0.0): all checks
bit exact; `test/lock_bus_read_sim.sh`, `test/lock_ctrl_sim.sh` and `test/sq_lockin_sim.sh` (OUT1/OUT2 compared
with the references of the clock before) pass.

## Timing (Vivado 2020.1, post-route)

| | v2.0.0 | v2.0.1 |
|---|---|---|
| WNS | -9.308 ns | -0.657 ns |
| TNS | -5094.830 ns | -58.751 ns |
| Failing endpoints | 3409 | 301 |

Worst slack per group (ns):

| Group | v2.0.0 | v2.0.1 |
|---|---|---|
| scope muxes | -9.308 | -0.321 |
| DAC registers | -9.144 | > 0 |
| adc_dat (digital loop / scope input) | -9.064 | -0.477 |
| bus copies *_rd | -9.269 | > 0 |
| PID A | -6.364 | -0.657 |
| PID B | -5.808 | -0.645 |
| lock_ctrl | -5.735 | -0.144 |
| rest of the lock module | -4.827 | -0.216 |
| ramp | -2.094 | > 0 |
| oscilloscope | -2.789 | > 0 |
| bus read (sys_rdata) | -2.129 | > 0 |
| other | -1.209 | -0.162 |

What still fails is small: the recursive loops of the LPF and of the PID integrator (they cannot be pipelined
without changing the filter), the input path `in1` → PID mux → set point subtraction → multiplier, quasi-static
configuration registers, and paths of the oscilloscope outside the lock module.
