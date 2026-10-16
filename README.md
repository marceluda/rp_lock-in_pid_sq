# Red Pitaya Square Lock-in+PID Application (SQUARE modulation up to 31.25 MHz)

"Square Lock-in+PID" (`lock_in+pid_square`) is the [Harmonic Lock-in+PID](https://github.com/marceluda/rp_lock-in_pid_h)
App (v2.3.18, branch `devel2.0`) with the harmonic modulation replaced by **square modulation** like the one of the
original [Lock-in+PID](https://github.com/marceluda/rp_lock-in_pid) App: a square local oscillator with reference
and quadrature outputs up to **31.25 MHz** (125 MHz / 4) and a square lock-in (multiplication by ±1), while keeping
every feature of the harmonic App: modulation added to the control signals (`ctrl_A` / `ctrl_B` on OUT1 / OUT2),
two PIDs, ramp, lock control run by the FPGA, Capture Lock, oscilloscope of the Ecosystem 2.0, streaming and HTTP
remote control.

It is an application for the [Red Pitaya STEMlab 125-14](https://www.redpitaya.com/) board (RP): a set of
instruments built in the FPGA (oscilloscope, square lock-in amplifier, two PIDs, ramp generator and
automatic lock control) to measure a system with modulation techniques and stabilize it with a feedback
loop, controlled from a web page or remotely over HTTP.

![Lock captured with the square lock-in at 50 kHz: ctrl_A (blue) and error = sqYo (red), t = 0 at the lock (v2.0.0)](.README/sq_lock_captured_v2.0.0.jpg)

**Repository:** https://github.com/marceluda/rp_lock-in_pid_sq (branch `master`; tags `v2.0.0`, `v2.0.1`, `v2.0.2`).


## Version 2.0.0 (Ecosystem 2.0)

Current version: **2.0.4** (branch `master`). The major number 2 marks, as in the 2.x series of the other Apps
(lock_in+pid 2.2.x, lock_in+pid_harmonic 2.3.x, lock_in+pid_harmonic2 2.4.x), the version for the Red Pitaya
**Ecosystem 2.0** (e.g. `RedPitaya_OS_2.04`), with the FPGA built in Vivado 2020.1 (project structure of
[RedPitaya-FPGA](https://github.com/RedPitaya/RedPitaya-FPGA)). There is no version for the 0.9x / 1.0 ecosystems.

- Square generator (`lock/gen_mod_sq.v`): f = 125 MHz / (2·(`gen_mod_sqp`+1)), from 0.029 Hz to 31.25 MHz with
  `sq_ref` / `sq_quad` exactly in quadrature (odd `gen_mod_sqp`; 62.5 MHz without quadrature), and `sq_phas`
  delayed by `gen_mod_phase_sq` ticks.
- Square lock-in: sqX, sqY (shared filter and gain, R and φ in the web page) and sqF, two-stage low-pass filters
  from 64 ns to 8.6 s, gains ×1 .. ×32k.
- Modulation added to the outputs: OUT1 ± `mod_out1`/2 with `sq_ref`, OUT2 ± `mod_out2`/2 with `sq_quad`.
- Everything else as lock_in+pid_harmonic v2.3.18 (see its history in the [CHANGELOG](CHANGELOG.md)). The register
  map changes from `0x054` on: see [doc/FPGA.md](doc/FPGA.md).
- 2.0.3 (from lock_in+pid_harmonic 2.3.21–2.3.23): **Reset zoom** sets the scope to one period of the ramp (Ext Trig =
  Scan floor / Scan ceil), one period of the square modulation (Square mod., 2·(`gen_mod_sqp`+1) ticks) or one whole
  memory at the current Dec, and Y to −1 … 1 V (raw mode −8192 … 8192); it ends a lock capture first, and Raw Mode
  rescales Y. **Mouse wheel on the scope**: no key zooms both axes, **SHIFT** only time (cursor ↔), **ALT** only the
  Y axes (cursor ↕). **Slow scans** (windows ≥ 1.5 s, e.g. a 30 s ramp): no samples of an older lap of the scope
  memory, Capture Lock with long histories, Reset zoom at 0.98 × the period; (FPGA) a time trigger armed after the
  ramp was stopped waits for the next scan floor.
- 2.0.4 (from lock_in+pid_harmonic 2.3.24): **scope presets** below Ext Trig: `in1|in2`, `in1|ctrl`,
  `sqX|sqY` (sqXo, sqYo), `in1|err`, `ctrl|err` and `usr` (a pair of the user: double click to choose it; saved in the browser
  and in the configs). They change only OscA/OscB (not the zoom nor the trigger). Picking an **Ext Trig** other than
  None sets the Trigger panel to External + Normal.

Tested on a STEMlab 125-14 with RedPitaya_OS 2.04-35 (2.0.0-5 and 2.0.0-6): generator exact to the tick at 31.25 MHz
and 50 kHz, lock-in at 50 kHz equal to the correlation computed from the scope, **real locks at 50 kHz and at
31.25 MHz** against a simulated peak (50 kHz: 5/5, same lock point as the harmonic App; 31.25 MHz: 4/4, 70 s locked
with Time and Level trigger, same point of the peak; it needs a system under test with enough bandwidth, see
[doc/Usage.md](doc/Usage.md#5-working-at-3125-mhz)), HTTP remote control (`example_usage.py` 15/15), streaming
at 976 kS/s. The FPGA timing does not close in paths inherited from the harmonic
App (WNS −9.3 ns), while the new square blocks do; the App works. The icon is provisional (the harmonic one).
Details: [doc/App.md](doc/App.md) and the [CHANGELOG](CHANGELOG.md).


## Features

- Square lock-in amplifier
- in-phase and quadrature demodulation (sqX, sqY), and demodulation with an adjustable delay (sqF)
- Square modulation from 0.029 Hz to 31.25 MHz (reference and quadrature), added to the outputs
- Two PID filters, for loop back stabilization
- Ramp/Scan controller for response analysis
- Lock control for automatic scan-stop / PID start (time, level or immediate trigger, run by the FPGA)
- Two-channel oscilloscope on any internal signal, triggered by internal events (scan floor, lock, ...)
- Streaming system for continued acquisition of two channels
- Remote control through HTTP API

**Decimation values**

| dec    | max oscilloscope length |
|--------|-------------------------|
|      1 |             0.131072 ms |
|      8 |             1.048576 ms |
|     64 |             8.388608 ms |
|    128 |            16.777216 ms |
|    256 |            33.554432 ms |
|    512 |            67.108864 ms |
|   1024 |           134.217728 ms |
|   8192 |           1.073741824 s |
|  65536 |           8.589934592 s |
| 524288 |          68.719476736 s |


## Documentation

| Document | Contents |
|---|---|
| [doc/App.md](doc/App.md) | Instruments and technical data |
| [doc/Usage.md](doc/Usage.md) | Web interface and procedures (scan, lock-in, lock), with screenshots |
| [doc/Structure.md](doc/Structure.md) | Web page ↔ server ↔ FPGA, block diagrams |
| [doc/FPGA.md](doc/FPGA.md) | Register map |
| [doc/Remote.md](doc/Remote.md) | Remote control over HTTP, Python examples |
| [doc/Devel.md](doc/Devel.md) | Building, modifying and testing |
| [CHANGELOG.md](CHANGELOG.md) | Changes by version |

The concepts of the instruments are also explained in the documentation of the original App:
https://marceluda.github.io/rp_lock-in_pid/


## Installation

If you have a RP board you can install the **Square Lock-in+PID** application
by copying the `lock_in+pid_square` folder (that comes with this tar/zip file) to the
`/opt/redpitaya/www/apps` folder (inside the RP).

The packages are built in `archive/` (`lock_in+pid_square-<version>-<build>-devbuild.{zip,tar.gz}`).
UnZip / UnTar the package and execute from terminal:

```bash
./upload_app.sh rp-XXXXXX.local
```

Replace `rp-XXXXXX.local` by your RP localname or IP address. Also, you can use your own SSH client and
upload the `lock_in+pid_square` folder to the RedPitaya folder `/opt/redpitaya/www/apps` (file system in
read-write mode, `fpga.sh` executable). Then open `http://rp-XXXXXX.local/lock_in+pid_square/`.

For more information about installing procedure, refer to:
https://marceluda.github.io/rp_lock-in_pid/TheApp/install/ and [doc/Devel.md](doc/Devel.md#installing-on-the-board).


## Building

To build or modify the App you need a linux development environment with:
  - Vivado 2015.2 (only because `settings.sh` sources it for the C controller / web App build)
  - gcc-linaro-4.9-2015.02-3-x86_64_arm-linux-gnueabihf (installed on `/opt/linaro/gcc-linaro-4.9-2015.02-3-x86_64_arm-linux-gnueabihf/`)
  - Vivado 2020.1 (for the FPGA design), in `/tools/Xilinx/Vivado/2020.1`

The App was based on code from project:
https://github.com/RedPitaya/RedPitaya/tree/release-v0.95/apps-free/scope

Run on terminal:

```bash
source settings.sh
LANG=C make          # controller, c/ tools, FPGA (if changed) and packages in archive/
```

Parts (from the root folder):

```bash
make -C lock_in+pid_square app        # C controller + c/ tools (cross compiled)
make -C lock_in+pid_square c_tools    # only the c/ tools (lock, osc, streaming)
make -C lock_in+pid_square fpga       # FPGA with Vivado 2020.1 (red_pitaya.bit, fpga.bit.bin)
make clean                              # clean all (also: clean_app, clean_fpga in lock_in+pid_square)
```

The FPGA can also be built from `lock_in+pid_square/fpga` (`make`, `make project`, `make clean`); its
Makefile loads Vivado 2020.1 by itself. Requirements, all the targets, tests and details:
[doc/Devel.md](doc/Devel.md).


## License and citation

GPL-3.0 (see [LICENSE](LICENSE)). If you use this software, please cite it (see [CITATION.cff](CITATION.cff)):
M. A. Luda, doi [10.1063/1.5080345](https://doi.org/10.1063/1.5080345).
