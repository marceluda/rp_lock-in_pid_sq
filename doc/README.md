# RP Square Lock-in+PID — documentation

Documentation of `lock_in+pid_square` ("Square Lock-in+PID") **v2.0.4** (branch `master`, Ecosystem 2.0, FPGA built
with Vivado 2020.1), derived from `lock_in+pid_harmonic` v2.3.18 (tag `v2.0.0`, commit `9e7b4a9`) with the later fixes
of that App ported up to its v2.3.24. All the pages describe this App;
data measured on the board come from the tests of 2026-10-12 (builds 2.0.0-5 and 2.0.0-6) and the screenshots of
2026-10-16 (2.0.4-13), and the values inherited
from the harmonic App that were not measured again say so. Back to the [project README](../README.md) ·
[CHANGELOG](../CHANGELOG.md).

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
