# The App: instruments and specifications

`lock_in+pid_square` ("Square Lock-in+PID") **v2.0.0** for the Red Pitaya STEMlab 125-14,
Ecosystem 2.0 (RedPitaya_OS 2.04-35). Branch `devel2.0`.

It is `lock_in+pid_harmonic` v2.3.18 (rp_lock-in_pid_h) with the harmonic modulation generator and lock-in
replaced by a **square** generator and lock-in like the square part of the original
[Lock-in+PID](https://github.com/marceluda/rp_lock-in_pid) App (`gen_mod2`, `sq_ref`/`sq_quad`/`sq_phas`,
sqX/sqY/sqF), with the reference and quadrature pair up to **31.25 MHz** (125 MHz / 4). Everything else
(oscilloscope, PIDs, ramp, lock control in the FPGA, Capture Lock, bus fixes, streaming, HTTP remote control)
is the one of v2.3.18. The measured values quoted below for the common instruments come from the tests of
lock_in+pid_harmonic; the square generator and lock-in are verified in simulation (to be tested on the board).

This page describes what the App contains and its technical data. How to use it from the web page is in
[Usage.md](Usage.md); how the parts are connected in [Structure.md](Structure.md); the registers in
[FPGA.md](FPGA.md).

- [The instruments](#the-instruments)
- [General data](#general-data)
- [Oscilloscope](#oscilloscope)
- [Inputs and outputs](#inputs-and-outputs)
- [Square modulation generator](#square-modulation-generator)
- [Square lock-in amplifier](#square-lock-in-amplifier)
- [Ramp generator (scan)](#ramp-generator-scan)
- [Error signal and PIDs](#error-signal-and-pids)
- [Lock control (auto-lock)](#lock-control-auto-lock)
- [Re-lock and step response](#re-lock-and-step-response)
- [Monitor](#monitor)
- [Streaming](#streaming)
- [Remote control](#remote-control)

## The instruments

Like the [Lock-in+PID](https://marceluda.github.io/rp_lock-in_pid/TheApp/instruments/instruments_01_intro/)
App it comes from, this App is a set of "instruments" built inside the FPGA. They are not isolated
blocks: they are a logical division of one circuit (`lock.v`), whose signals can be routed to each other
with selectors, so that a measurement or a feedback loop is configured instead of wired.

| Instrument | What it does | Main registers |
|---|---|---|
| **Oscilloscope** | Two channels, any of 21 internal signals, 16384 samples, time spans from 131 µs to 68.7 s, external trigger from internal events | scope block 0x40100000, `oscA_sw`, `oscB_sw`, `trig_sw` |
| **Inputs / outputs** | Routing of 16 signals to the fast outputs OUT1/OUT2, with optional square modulation added (e.g. OUT1 = ctrl_A + modulation) | `out1_sw`, `out2_sw`, `mod_out1`, `mod_out2` |
| **Square modulation generator** | Square local oscillator: `sq_ref`, `sq_quad` (90°) and `sq_phas` (adjustable delay), 0.029 Hz – 31.25 MHz with quadrature (62.5 MHz without) | `gen_mod_sqp`, `gen_mod_phase_sq` |
| **Square lock-in** | Demodulation of one input with the three square references (sqX, sqY, sqF: ±1 multiplication), 1st/2nd order low-pass filters from 64 ns to 8.6 s and gains | `signal_sw`, `lpf_sq`, `lpf_sqF`, `sg_amp_sq`, `sg_amp_sqF` |
| **Ramp generator** | Triangle or sawtooth scan on two outputs with a fixed ratio (A and B) | `ramp_*` |
| **Two PIDs** | PID A and PID B, wide range of gains and time constants, integrator saturation, freeze and reset | `pidA_*`, `pidB_*`, `error_sw`, `error_offset` |
| **Lock control** | Automatic transition from scan (open loop) to lock (closed loop) at a time, a level or immediately, executed by the FPGA in one clock | `lock_control`, `lock_status`, `lock_trig_*` |
| **Re-lock / step response** | Out-of-lock detection; a step added to the control signals to measure the loop response | `rl_*`, `sf_*` |
| **Monitor** | Mean and standard deviation of the error over ~1 s | `error_mean`, `error_std` |
| **Streaming** | Continuous transfer of the two scope channels to a computer over TCP | `stream_*` |
| **Remote control** | HTTP API to read and write all the registers, make scope acquisitions and run the lock (Python client `control_finn.py`) | `/lock`, `/osc`, `/data` |

The two control signals of the App are:

```
ctrl_A = PID A out + Ramp A (+ jump A)     → usually sent to OUT1
ctrl_B = PID B out + Ramp B (+ jump B)     → usually sent to OUT2
```

## General data

| Item | Value | Source |
|---|---|---|
| Board | STEMlab 125-14 (Zynq 7010, model Z10) | `fpga/README.md` |
| Ecosystem | 2.0 (RedPitaya_OS 2.04-35 tested); FPGA loaded by `fpga.sh` with `fpgautil` | `fpga.sh`, test reports |
| FPGA clock | 125 MHz (8 ns) | `src/fpga.c` l. 50, top |
| ADC / DAC | 14 bit, 125 MS/s; signals are 14-bit signed, 8192 counts = 1 V | `lock.v`, `index.html` |
| FPGA timing | does not close (as lock_in+pid_harmonic: long paths of the loop, PID → scope muxes / outputs; see the CHANGELOG of v2.0.0 for the WNS of this design), works in practice in the harmonic App. Bus reads of the lock module are exact ([FPGA.md](FPGA.md#lock-module-0x40600000)) | CHANGELOG, `devAgent.md` |

## Oscilloscope

The Red Pitaya 2.0 scope, fed by two internal signals chosen with `oscA_sw`/`oscB_sw` (not directly by
the ADCs). See [FPGA.md](FPGA.md#oscilloscope-0x40100000).

| Item | Value |
|---|---|
| Channels | 2 (any of: 0, in1, in2, error, ctrl_A, ctrl_B, Ramp A/B, pidA/B_in, PID A/B out, sq_ref, sq_quad, sq_phas, sqXo, sqYo, sqFo, signal_i, out1, out2) |
| Memory | 16384 samples per channel; the web page gets 1024 points (`SIGNAL_LENGTH`, `src/main.h`) |
| Decimations (time range) | 1 (131 µs), 8 (1.05 ms), 64 (8.4 ms), 128 (16.8 ms), 256 (33.6 ms), 512 (67.1 ms), 1024 (134 ms), 8192 (1.07 s), 65536 (8.6 s), 524288 (68.7 s) — `src/fpga.c` l. 509-545; 20-bit decimation in the FPGA of this App |
| Trigger sources | Channel 1, Channel 2, External; modes Auto, Normal, Single; edge rising/falling |
| External trigger | Any of: pin DIO0_P, scan floor, scan ceil, start of the square modulation period, out of lock, jump (step response), lock event ("Lock control trig") — `trig_sw` |
| Other | Averaging at decimation, anti-aliasing (equalization) filter bypass per channel, Raw mode (values in counts), save data as Python / Matlab / CSV |

The time span of the 68.7 s range was verified on the board (v2.3.10, `reportes/lock-in_pid_h.md`).

## Inputs and outputs

| Item | Value |
|---|---|
| Fast inputs IN1, IN2 | 14 bit; ±1 V (LV jumper) or ±20 V (HV); the gain setting of the UI only changes the scale of the display |
| Fast outputs OUT1, OUT2 | 14 bit, ±1 V, 8192 counts = 1 V; any of 0, in1, in2, in1−in2, error, sq_ref, sq_quad, sq_phas, sqXo, sqYo, PID A out, PID B out, ctrl_A, ctrl_B, aux_A, aux_B |
| Modulation added to the outputs | OUT1 ± `mod_out1 / 2` with `sq_ref`, OUT2 ± `mod_out2 / 2` with `sq_quad`, saturated to 14 bits; off with a negative `mod_out*`. Same peak amplitude as the harmonic modulation of lock_in+pid_harmonic for the same value. Typical use: OUT1 = `ctrl_A` (PID A + ramp) + modulation |
| `in1 − in2` | difference saturated to 14 bits |
| `aux_A`, `aux_B` | two constants (−8192..8191) usable as signals |
| Slow outputs AO0-AO3 | **not driven by the lock module in this version** (the UI shows four selectors that have no effect). See [FPGA.md](FPGA.md#other-blocks) |
| Digital I/O | DIO0_P: trigger input; DIO6_N: ramp direction output; DIO7_N: digital modulation = `sq_ref` (TTL reference, as in lock_in+pid) |

## Square modulation generator

`lock/gen_mod_sq.v` (v2.0.0, square part of `gen_mod2.v` of lock_in+pid written again). One counter runs over the
whole period of P = 2·(`gen_mod_sqp` + 1) ticks; the three outputs are computed from the same counter value in a
3-stage pipeline, so their relative timing is exact.

| Item | Value |
|---|---|
| Frequency | f = 125 MHz / (2·(`gen_mod_sqp` + 1)) |
| Range | `gen_mod_sqp` = 1 → **31.25 MHz** (P = 4 ticks); 0 → 62.5 MHz (no quadrature); 1249 → 50 kHz; 2³²−1 → 0.029 Hz |
| `sq_ref` | 1 (+4096) during the first half of the period, 0 (−4096) during the second |
| `sq_quad` | `sq_ref` delayed by floor(P/4) ticks: **exactly 90° when `gen_mod_sqp` is odd** (P multiple of 4); with an even value the delay is rounded down (`gen_mod_sqp` = 2: 60°) |
| `sq_phas` | `sq_ref` delayed by `gen_mod_phase_sq` ticks, 0..P−1 (360°·n/P; at 31.25 MHz steps of 90°); larger values act as P−1 |
| Amplitude of the references | ±4096 counts (≈ ±0.5 V) |
| Trigger | "Square mod." (`trig_sw` = 8): one pulse per period, at the rising edge of `sq_ref` |
| Modulation on an output | ±`mod_out`/2 counts (square), max `mod_out` = 8191 → ±0.5 V |
| Digital output | `sq_ref` on DIO7_N |

At 31.25 MHz the DAC samples of `sq_ref` (+A, +A, −A, −A) are exactly those of a sinusoid of amplitude √2·A at
fs/4, so the analog output is a sine wave (≈ 1.27·A after the DAC sample-and-hold), not a square wave.

The web UI accepts the half period as a number, a frequency ("50 kHz", "31.25 MHz") or a period ("20 us") and the
phase as ticks, an angle ("90 deg", "0.5 pi") or a delay; below the fields it shows f, T, the number of ticks per
period, the quadrature angle and the phase in degrees.

## Square lock-in amplifier

`lock.v` ("Signal Processing"), `lock/LP_filter_sq.v`.

```
signal_i ─┬─ ×(±1, sq_ref ) ─ LPF(lpf_sq ) ─ sqX_28 ─ ×2^sg_amp_sq  ─ sat ─ sqXo
          ├─ ×(±1, sq_quad) ─ LPF(lpf_sq ) ─ sqY_28 ─ ×2^sg_amp_sq  ─ sat ─ sqYo
          └─ ×(±1, sq_phas) ─ LPF(lpf_sqF) ─ sqF_28 ─ ×2^sg_amp_sqF ─ sat ─ sqFo
```

| Item | Value |
|---|---|
| Input `signal_i` | in1, in2, in1−in2, sq_ref, sq_quad, sq_phas, aux_A, Ramp A |
| Outputs | `sqXo`, `sqYo` (reference and quadrature), `sqFo` (reference delayed by `gen_mod_phase_sq`); 14-bit, saturated |
| Scale | `sq?_28 = mean(±signal_i)·2^13`; with gain ×1 `sq?o` = mean(±signal_i) in counts: a square input of amplitude A in phase with the reference gives `sqXo = A`; a sinusoidal input of amplitude A and phase φ gives `sqXo = (2/π)·A·cos φ`, `sqYo = (2/π)·A·sin φ` |
| Gains | `sg_amp_sq` (sqXo, sqYo) and `sg_amp_sqF` (sqFo): ×1 .. ×32k |
| Low-pass filters | 2 independent: sqX & sqY share `lpf_sq`, sqF uses `lpf_sqF`. Order 0 (off), 1 or 2 (cascade of identical 1st-order stages) |
| Time constants | τ = 8 ns · 2^(n+3), n = 0..27: 64 ns .. 8.59 s (cut-off 2.49 MHz .. 18.5 mHz) |
| Latency | 2 ticks from `sq_ref` to OUT1 and back to the product (simulation, out1 looped to in1 inside the FPGA); the analog path adds its delay: at 31.25 MHz each 8 ns is 90° |
| R and φ | computed in the web page from sqX and sqY: R = √(X² + Y²), φ = atan2(Y, X) |

At 31.25 MHz the product of a sinusoid with the square reference has components at DC and at 62.5 MHz (fs/2,
alternating sign): a filter of a few hundred ns already removes it, so the loop bandwidth can be much larger than
with the harmonic App (whose maximum modulation was 49.6 kHz). At low frequency the square reference also
demodulates the odd harmonics of the input (3f with weight 1/3, 5f with 1/5...).

To use the phase with fine resolution at 31.25 MHz (only 4 ticks per period), combine sqX and sqY (R|Phase
display) or choose sqXo / sqYo / sqFo and the sign of the PID gains: for locking to the centre of a peak the
position of the zero crossing does not depend on the phase, only the slope does.

## Ramp generator (scan)

`lock/gen_ramp.v`.

| Item | Value |
|---|---|
| Shape | triangle (`ramp_sawtooth` = 0) or sawtooth (1); starting direction / direction of the sawtooth with `ramp_direction` |
| Limits | `ramp_low_lim` .. `ramp_hig_lim`, −8192..8191 (±1 V); default ±5000 (±610 mV) |
| Step | one count every `ramp_step + 1` ticks |
| Period | T = (hig − low) · (`ramp_step` + 1) · 8 ns · (2 − sawtooth); e.g. ±5000, `ramp_step` = 200000 sawtooth → 16.0 s (seen on the board, [panel](Usage.md#ramp-controller)) |
| Second output | `ramp_B = ramp_A · ramp_B_factor / 4096` (factor −4096..4096 in the UI, i.e. −1..1) |
| Triggers | "Scan floor" (low limit reached) and "Scan ceil" (high limit), for the scope and for the time trigger of the lock |
| Enable | runs while `ramp_enable` (Ramp panel, "Scan enable" checkbox) **and** the ramp enable of the lock control ("Scan enable" button) are on; `ramp_reset` holds it at 0 |
| Digital output | ramp direction on DIO6_N |

## Error signal and PIDs

`lock.v` l. 538-563 and 907-997, `lock/lock_pid_block.v`.

The **error** is one of 0, sqXo, sqYo, sqFo, signal_i, in2, in1, in1−in2, minus `error_offset`. Each PID can take
the error or one of 15 other signals (`pidX_sw`).

PID equation, with e = `sp − in` (the sign of the gains selects the sign of the feedback):

```
out = kp·e / 2^P  +  Σ(ki·e) / 2^I  +  kd·(slope of e) / 2^6
```

| Item | Value | Notes |
|---|---|---|
| `kp`, `ki`, `kd`, `sp` | −8192..8191 | 14-bit signed |
| Proportional divider P (PSR) | /1, /8, /64, /1024, /4096 | default /1024 (`kp` = 1024 → gain 1) |
| Integrator (ISR) | 2^I, I = 0,3,6,10,13,16,20,23,26,30 → UI labels 8 ns, 64 ns, 512 ns, 8 us, 65 us, 524 us, 8 ms, 67 ms, 537 ms, 9 s (the "65 us" label said "6 us" up to v2.3.14) | characteristic time τ_i = 8 ns · 2^I / |ki|; default I = 26 (537 ms) |
| Derivative (DSR) | slope over averages of 2^D samples, D = 0,3,6,10,13,16 → UI 7.5 ns .. 491.5 µs | τ_d = 7.5 ns · 2^D · |kd| (UI formula) |
| Integrator saturation (SAT) | integral term limited to ±2^SAT counts: ±122 µV (0) .. ±1 V (13) | default 13 |
| Output | sum saturated to 14 bits (±1 V) | |
| Controls | integrator reset, freeze output, freeze integrator (`pidX_ctrl`) | also frozen during a step (`sf_config`) |
| Enable | the output is forced to 0 and the integrator reset while the PID is disabled by the lock control | `lock.v` l. 953 |

Example (test configuration `lock_mode`): PID A, kp = −500 with /1024 → −0.488; ki = −20 with 537 ms →
τ_i = 26.8 ms (seen in the [PID panel](Usage.md#pids-modules)).

## Lock control (auto-lock)

The lock sequence runs in the FPGA (`lock/lock_ctrl.v`, since v2.3.13). Full design:
[`lock_control.md`](../lock_in+pid_square/doc/lock_control.md).

| Item | Value |
|---|---|
| States | OFF (IDLE) → ARMED → LOCKED |
| In IDLE / ARMED | ramp, PID A, PID B follow the manual enables ("Scan enable", "PID A enable", "PID B enable") |
| In LOCKED | they follow the "config" enables (usually: ramp off, PID A on) |
| Requests | Lock Now (immediate), Trigger Lock (arm, lock on the trigger) |
| Triggers | **Time**: `lock_trig_time` ticks (8 ns) after the scan floor, 0..2³²−1 (up to 34.36 s; 32-bit counter since v2.3.15, it was 17.18 s); **Level**: a signal crosses `lock_trig_val` upwards or downwards; **Level+time**: level crossing after the time |
| Latency | the change happens in the same clock tick as the trigger (8 ns) |
| Status | `lock_status`: armed, locked, effective enables, count of locks |
| Capture | the lock event is a scope trigger source ("Lock control trig"); the web page uses it to capture the closing of the loop ([`lock_capture.md`](../lock_in+pid_square/doc/lock_capture.md)) |

Measured on the board against a simulated peak (`dummy_simulator` on a second Red Pitaya, LOCK MODE
procedure of `test_files/lock_test.md`, v2.3.11 to v2.3.17; `reportes/lock-in_pid_h_lock_test/`):

| Metric | Value |
|---|---|
| Time from the request (POST) to ARMED | 17 ms (the controller waits for the scope to be armed) |
| ARMED → LOCKED | 5-47 ms (first sweep after arming, time trigger at 16.58 ms; 16.9 ms in v2.3.14, 26 / 47 ms in v2.3.17) |
| Captures of the lock in the scope with Capture Lock | 16/16 |
| Signal at the lock point | IN1 = 1.01–1.03 × the peak |
| Error while locked | mean ≈ 0, std ≈ 7–8 mV |
| Longest lock observed | 4 h 10 min without losses (level trigger) |

## Re-lock and step response

- **Re-lock** (`rl_*`): "out of lock" = `|error| > rl_error_threshold` and/or `signal < rl_signal_threshold`
  (signal: in1, in2, in1−in2, aux_A, aux_B), debounced (`lock/lock_debounce.v`). It is a scope trigger
  source, and with re-lock enabled the ramp generator switches to a search around the current point
  (`lock/gen_ramp_relock.v`). `rl_state` is not implemented (reads 0). The behaviour of the search has not
  been tested on the 2.0 version: **a confirmar**.
- **Step response** (`sf_*`): "Start Step Responce" adds `sf_jumpA`/`sf_jumpB` to `ctrl_A`/`ctrl_B`
  2¹⁶ ticks (524 µs) after the start (`jump_control`, N = 16), and can freeze the outputs or integrators
  of the PIDs during the step. "Jump trigger" is a scope trigger source. Not tested on 2.0: **a confirmar**.

## Monitor

`error_mean` and `error_std` are computed in the FPGA over 2²⁷ ticks (1.074 s) and shown in the Monitor
panel in counts (`src/lock.c` l. 320-322).

## Streaming

`c/streaming` (started by the "Prepare Streaming" button) waits for `stream_cmd = 1` and then runs
`c/stream_tcp_osc_cmd`, which reads the scope memory continuously and sends both channels to
`stream_ip:stream_port` over TCP. A receiver is in `resources/streaming/` (instructions in
`resources/README.md`).

| Rate (`stream_rate` = decimation) | Result on the board (v2.3.10) |
|---|---|
| 64 (1.95 MS/s) | not sustainable: 1.63 MS/s, ~17 % of the samples lost (counted) |
| 128 (0.98 MS/s) | 976.5 kS/s, 0 duplicates in 311 M samples (318 s) |
| 256 .. 65536 | sustainable |

## Remote control

- **HTTP** (recommended): `http://rp-XXXXXX.local/lock_in+pid_square/lock` and `.../osc` read and write
  the registers of the lock module and of the scope, and read the scope memory; `POST /data` stops or restarts
  the scope of the C controller. Python client `resources/remote_control/http_version/control_finn.py`
  (v2.3.15-2.3.17: triggered acquisitions on the 2.0 scope, PID / ramp / lock-in / lock helpers, host name
  resolved once, minimal `POST /data`). See [Remote.md](Remote.md).
- **On the board**: `c/lock`, `c/osc` and the Python scripts of `py/` (e.g. `lock_from_registers.py`).
- **SSH** version (`resources/remote_control/shh_version`): deprecated, kept for specific cases.
