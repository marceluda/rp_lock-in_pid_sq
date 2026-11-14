# RP Square Lock-in+PID — documentation

Documentation of `lock_in+pid_square` ("Square Lock-in+PID") **v2.0.11** (package 2.0.11-21, branch `master`,
Ecosystem 2.0, FPGA built with Vivado 2020.1; the FPGA is the one of v2.0.3 … v2.0.9, v2.0.10 and v2.0.11 change only
the web page), derived from `lock_in+pid_harmonic` v2.3.18 (tag `v2.0.0`, commit `9e7b4a9`) with the later changes of
that App ported up to its v2.3.32. All the pages describe this App;
data measured on the board come from the tests of 2026-10-12 (builds 2.0.0-5 and 2.0.0-6), the screenshots of
2026-10-16 (2.0.4-13) and the test of 2026-11-13 (2.0.10-20), and the values inherited
from the harmonic App that were not measured again say so. Back to the [project README](../README.md) ·
[CHANGELOG](../CHANGELOG.md).

New in v2.0.10 (the Ramp Controller of `lock_in+pid_plus` 2.2.0, through `lock_in+pid_harmonic` 2.3.31): the *Ramp
Controller* of the web page sets the ramp by period (steps, or the whole period in `s` / `ms`) or by frequency /
amplitude / offset, and *Lock osc. screen* shows the rising half of a triangle (one period of a sawtooth) and turns a
time zoom of the scope into new ramp limits: [Usage.md](Usage.md#ramp-controller), formulas in
[App.md](App.md#ramp-generator-scan). *Reset zoom* with Scan floor and a triangle alternates whole period / rising half
(with Square mod. it still gives one period of the modulation;
[Usage.md](Usage.md#reset-zoom-whole-period--rising-half)); the *Force X* of the server is applied once
([Structure.md](Structure.md#time-window-of-the-plot-and-force-x)).

New in v2.0.11 (from `lock_in+pid_plus` 2.2.1): a POST retried after a timeout of nginx no longer undoes a time window
set meanwhile (the second click of *Reset zoom*), the page checks that the server took the window it sent and sends it
again if not, and a value changed back during a POST in flight is kept
([Structure.md](Structure.md#a-post-retried-after-a-timeout-and-a-window-that-the-server-does-not-take-v2011)).

| Document | Contents |
|---|---|
| [App.md](App.md) | The instruments of the App and their technical data: frequencies, filters, gains, ranges, time spans, measured lock performance |
| [Usage.md](Usage.md) | The web interface panel by panel, and the procedures: scan, lock-in, close and check a lock, configs |
| [Structure.md](Structure.md) | How the web page, the server (nginx + `controllerhf.so`) and the FPGA work together; block diagrams of the FPGA |
| [FPGA.md](FPGA.md) | Register map of the lock module and of the oscilloscope, bit fields and selector values |
| [Remote.md](Remote.md) | Remote control over HTTP (`/lock`, `/osc`, `/data`) with Python (`control_finn.py`) examples; known issue of `POST /data`; tools and scripts on the board |
| [Devel.md](Devel.md) | Source tree, requirements, building (C, `c/` tools, FPGA), tests, installation |

Design notes kept with the sources (`lock_in+pid_square/doc/`):

- [`lock_control.md`](../lock_in+pid_square/doc/lock_control.md): the lock control of v2.3.13
  (`lock_control` / `lock_status`, state machine in the FPGA, locking from Python).
- [`lock_capture.md`](../lock_in+pid_square/doc/lock_capture.md): *Capture Lock* and *Fire on click* (v2.3.14).

The register table that this file had before (a copy of `lock_in+pid_square/c/lock.txt`) is now
[FPGA.md](FPGA.md), checked against the RTL.

Screenshots of the web interface are in the hidden folder `.Usage/` (this App, except a few dialogs shared with
lock_in+pid_harmonic, marked in their captions), and the figures of the remote control in `.Remote/` (taken with
lock_in+pid_harmonic).
