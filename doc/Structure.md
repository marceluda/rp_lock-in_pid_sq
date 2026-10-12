# Internal structure

How `lock_in+pid_square` v2.0.0 is built: the three layers (web page, server, FPGA), how they talk, and
how the instruments are connected inside the FPGA. Registers: [FPGA.md](FPGA.md). Specifications:
[App.md](App.md). Source tree and build: [Devel.md](Devel.md).

This App is `lock_in+pid_harmonic` v2.3.18 with the harmonic generator and lock-in replaced by a square generator
and a square lock-in. The software layers (web page, C controller, Lua endpoints) are the same; the FPGA differs in
the generator, the lock-in, the selectors and the register offsets from `0x054` on.

- [Layers](#layers)
- [Web page ↔ server](#web-page--server)
- [Server ↔ FPGA: the C controller](#server--fpga-the-c-controller)
- [Inside the FPGA](#inside-the-fpga)
  - [Top level](#top-level)
  - [Signal flow of the lock module](#signal-flow-of-the-lock-module)
  - [Lock control](#lock-control)
  - [Scope and streaming](#scope-and-streaming)
- [Parameters, registers and `config_tool.py`](#parameters-registers-and-config_toolpy)

## Layers

As described for the original [Lock-in+PID](https://marceluda.github.io/rp_lock-in_pid/TheApp/instruments/instruments_01_intro/),
the App has a client-server structure on top of a programmable circuit:

```mermaid
flowchart LR
  subgraph PC["Computer"]
    B["Browser<br/>index.html + JS"]
    P["Python / scripts<br/>control_finn.py"]
  end
  subgraph RP["Red Pitaya (Linux, Ecosystem 2.0)"]
    N["nginx<br/>Red Pitaya module"]
    C["controllerhf.so<br/>(C controller + scope worker thread)"]
    L["Lua endpoints<br/>nginx.conf"]
    T["c/lock, c/osc,<br/>c/streaming"]
    PY["py/*.py<br/>(hugo.py)"]
    F["FPGA<br/>fpga.bit.bin"]
  end
  B -- "GET/POST /data (JSON)<br/>/bazaar, /get_client_id" --> N
  N --> C
  B -- "GET /lock_in+pid_square/lock, /osc, ..." --> L
  P -- "GET /lock, /osc" --> L
  P -- "POST /data<br/>(trig_mode only)" --> N
  L --> T
  C -- "/dev/mem (mmap)" --> F
  T -- "/dev/mem" --> F
  PY -- "/dev/mem" --> F
  T -- "TCP stream" --> PC
```

- **Client**: `index.html` (HTML + jQuery + Flot, all in one file) runs in the browser. It polls the
  server, draws the scope and sends parameter changes.
- **Server**: the nginx of the Red Pitaya Ecosystem loads `controllerhf.so` (the App controller) when the
  App is started with `/bazaar?start=lock_in+pid_square`; on Ecosystem 2.0 the FPGA image `fpga.bit.bin`
  is loaded at the start by `fpga.sh` (`fpgautil`). The App also adds its own HTTP endpoints, written in
  Lua inside `nginx.conf`, which run the small C tools of `c/`.
- **Hardware**: the FPGA (`lock.v` and the Red Pitaya scope) does all the real-time processing. The
  software only reads and writes registers; changing a function means changing a register, not the circuit.

## Web page ↔ server

| Endpoint | Method | Who | What |
|---|---|---|---|
| `/bazaar?start=lock_in+pid_square` / `?stop=` | GET | page at start / Restart | start the App (controller + FPGA) / stop the loaded App |
| `/data` | GET | page, polling (~50 ms; 500 ms with a frozen capture) | parameters (JSON `datasets.params`) and the two scope traces (`datasets.signals`, 1024 points) |
| `/data` | POST | page, on each change; `control_finn.py` (`trig_mode` only) | changed parameters only, in chunks of at most 600 bytes, with retries (Ecosystem 2.0 hangs with large bodies). The handler only reads a body that arrives with the headers, and every POST leaves a CLOSE-WAIT connection in nginx ([Remote.md](Remote.md#known-issue-of-the-ecosystem-post-data-leaves-connections-open)) |
| `/get_client_id`, `/set_client_id` | GET/POST | page | claim the board like the factory Apps; detect another client |
| `/lock_in+pid_square/lock?…` | GET | page (streaming IP), Python | run `c/lock`: read/write lock registers ([Remote.md](Remote.md)) |
| `/lock_in+pid_square/osc?…` | GET | Python | run `c/osc`: read/write scope registers (with `TrgUnlock` since v2.3.15), dump the scope memory |
| `/lock_in+pid_square/get_ip` | GET | page (IP button) | IP of the client |
| `/lock_in+pid_square/calib` | GET | Python | output of `calib -rv` (calibration of the board) |
| `/lock_in+pid_square/streaming` | GET | page (Prepare Streaming) | start `c/streaming` detached (`c/stream_start.sh`) |
| `/lock_in+pid_square/check_streaming` | GET | page | 0 if `c/streaming` is running, 1 if not |
| `/lock_in+pid_square/restart_server` | GET | — | `systemctl restart redpitaya_nginx` |
| `/lock_in+pid_square/reload_fpga` | GET | — | 0.9x only; on 2.0 answers HTTP 501 and does not touch the FPGA |

The page keeps three copies of the parameters (`params.orig` from the server, `params.local` edited, the
unsent changes) and sends only what changed. Read-only values (lock-in outputs, `lock_status`, monitor)
are never sent. The page state is saved per tab (`sessionStorage`) and restored after a Restart; configs are
saved in `localStorage` (key `lockConfig_lock_in+pid_square`). A Config → load sends the whole config
(`send_all`, 5-9 chunks) except the time-scale values derived by the server (`send_all_skip`: `forcex_flag`,
`time_units`, `time_range`, `gui_xmin`, `gui_xmax`), and takes the window and units of the answer of the last
chunk (`configLoadApplyX()`, v2.3.17).

## Server ↔ FPGA: the C controller

`src/` builds `controllerhf.so`, the standard interface of a Red Pitaya App (`rp_app_init`,
`rp_app_exit`, `rp_set_params`, `rp_get_params`, `rp_get_signals`):

```mermaid
flowchart TB
  POST["POST /data"] --> SP["rp_set_params()<br/>main.c"]
  GET["GET /data"] --> GP["rp_get_params()<br/>rp_get_signals()"]
  SP -->|scope params| W["scope worker thread<br/>worker.c + fpga.c"]
  SP -->|"lock_* params<br/>lock_update()"| LK["lock.c + fpga_lock.c"]
  GP -->|"lock_update_status()<br/>lock_update_main()"| LK
  W -->|"arm, trigger unlock (0x94),<br/>read 16384 samples, decimate to 1024"| SCOPE["scope 0x40100000"]
  LK -->|"write / read registers"| LOCK["lock 0x40600000"]
  W -->|traces| GP
```

- **Parameter table**: `src/main.c` `rp_main_params[]` (198 parameters, `PARAMS_NUM` in `src/main.h`): the scope
  (0-41), the AWG and PID of the original scope App (42-80, unused by this FPGA), and the lock module (81-197,
  generated by `config_tool.py` between `[MAINDEF DOCK]` markers, `src/main.c` l. 310-430).
  Most `lock_*` parameters map one to one to a register; some are fields of a register
  (`lock_lpf_sq_tau`/`_order` → `lpf_sq`, `lock_lpf_sqF_tau`/`_order` → `lpf_sqF`, as `order << 5 | tau`; `lock_ctrl_aux_*` → `lock_control`; `lock_osc1/2_filt_off` →
  `osc_ctrl`; `lock_pidA_irst/freeze/ifreeze` → `pidA_ctrl`; `lock_rl_*` → `rl_config`; `lock_sf_*` → `sf_config`).
- **`lock_update()`** (`src/lock.c` l. 139) writes the lock registers from the parameters; `lock_control`
  only when the value composed from `lock_ctrl_aux_*` changes (v2.3.13).
- **Full 32-bit registers** written from the page through float parameters: `lock_trig_time`, `lock_trig_val`,
  `lock_trig_sw` (v2.3.18) and, in this App, the square generator `gen_mod_sqp` and `gen_mod_phase_sq`
  (`src/lock.c` l. 68-73 and 213-228, `lock_sq_known`): they are written **only when the parameter changes**, and a
  value written from outside (`/lock`, Python) is copied to the parameter and kept, so a value above 2²⁴ written
  exactly from Python is not replaced by its float32 rounding when the user changes another parameter in the page
  (tested on the board: `gen_mod_sqp` = 16789561 kept after changing the phase and the gain in the page).
- **`lock_update_main()` / `lock_update_status()`** (l. 328, 465) read the registers back (read-only values,
  `lock_status`, the square lock-in outputs `sqX_28`..`sqF_28`, and changes made from outside, e.g. Python) into the
  parameters, on every request.
- **Scope worker** (`src/worker.c`): a thread that arms the scope, waits for the trigger (on 2.0, it unlocks
  the trigger at 0x94 before each acquisition and detects the end with `conf` bit 4), reads both buffers and
  decimates them to 1024 points; it also runs the auto-set (AUTO) and the measurements. Since v2.3.14 a POST
  without scope changes does not reset it, and a lock request that arms a Single waits until the scope is
  armed (`rp_osc_worker_wait_armed()`), which makes *Capture Lock* deterministic
  ([`lock_capture.md`](../lock_in+pid_square/doc/lock_capture.md) §3.2).
- **`trig_mode` = 2 (Single)** puts the worker in its idle state: it resets and configures the scope once and
  then does not arm it (`src/main.c` `rp_set_params()`, `src/worker.c`). After `bazaar?start` the worker runs in
  Auto even with no page open; `control_finn.py` sets Single through `POST /data` before acquiring through
  `/osc` (v2.3.16, [Remote.md](Remote.md#oscilloscope-acquisitions)).

## Inside the FPGA

### Top level

`fpga/prj/v0.94/rtl/red_pitaya_top.sv` (RedPitaya-FPGA v0.94 adapted to behave like the 2015.2 design
of the App):

```mermaid
flowchart LR
  ADC["ADC IN1, IN2<br/>(14 bit, 125 MS/s)"] --> LOCK
  DIO0["DIO0_P"] -- external_trigger --> LOCK
  PS["Zynq PS<br/>(Linux, /dev/mem)"] -- "sys bus [6]<br/>0x40600000" --> LOCK["lock.v"]
  PS -- "sys bus [1]<br/>0x40100000" --> SCOPE["rp_scope_com<br/>(2.0 scope, 20-bit dec.)"]
  LOCK -- "out1, out2" --> DAC["DAC OUT1, OUT2"]
  LOCK -- "osc1, osc2" --> SCOPE
  LOCK -- "trigger → trig_ext_i" --> SCOPE
  LOCK -- "osc_ctrl_w<br/>(filter bypass, streaming dec.)" --> SCOPE
  LOCK -- "pwm_cfg_a..d" --> PWM["PWM AO0-AO3<br/>(not driven, see FPGA.md)"]
  LOCK -- "ramp_direction_out" --> DIO6["DIO6_N"]
  LOCK -- "digital_modulation = sq_ref" --> DIO7["DIO7_N"]
  STUB["ASG, PID: stubs<br/>(0x40200000, 0x40300000)"]
```

The DACs are driven only by the lock module and the scope only sees the two signals chosen inside it
(`oscA_sw`, `oscB_sw`), never the raw ADC.

### Signal flow of the lock module

`fpga/prj/v0.94/rtl/lock.v` and `lock/*.v`. Selectors are drawn as `[sel]` with the register name; the
values of each selector are in [FPGA.md](FPGA.md#selector-values). This is the "instruments" view of the
published documentation, applied to this App.

```mermaid
flowchart LR
  IN1([in1]) & IN2([in2]) --> SUB["in1 − in2<br/>(sat 14)"]

  subgraph GEN["Square generator (gen_mod_sq)"]
    HP["gen_mod_sqp<br/>P = 2·(sqp+1) ticks"] --> CNT["period counter<br/>3-stage pipeline"]
    PH["gen_mod_phase_sq"] --> CNT
    CNT --> REF["sq_ref, sq_quad (P/4 later),<br/>sq_phas (phase later)<br/>±4096"]
    CNT --> STRIG["square_trig"]
  end

  subgraph LI["Square lock-in"]
    SIG["[signal_sw]<br/>signal_i"] --> MUL["× ±1<br/>(registered)"] --> LPF["LPF A+B<br/>LP_filter_sq<br/>(lpf_sq, lpf_sqF)"] --> AMP["× 2^sg_amp_sq / sg_amp_sqF<br/>sat 14"]
    AMP --> XY["sqXo, sqYo, sqFo"]
  end

  IN1 & IN2 & SUB & AUX([aux_A]) & RA2([Ramp A]) --> SIG
  REF --> SIG
  REF --> MUL

  XY --> ERR["[error_sw] − error_offset<br/>= error"]
  IN1 & IN2 & SUB --> ERR

  subgraph PIDS["PIDs"]
    PA["[pidA_sw] → PID A"]
    PB["[pidB_sw] → PID B"]
  end
  ERR --> PA & PB
  XY --> PA & PB

  subgraph RAMP["Ramp (gen_ramp)"]
    RA["Ramp A"]
    RB["Ramp B = A·factor/4096"]
  end

  subgraph LC["Lock control (lock_ctrl)"]
    SM["IDLE / ARMED / LOCKED"]
  end
  LTS["[lock_trig_sw]<br/>level trigger signal"] --> SM
  RA -. "scan floor" .-> SM
  SM -- "enables" --> RAMP
  SM -- "enables" --> PA & PB

  PA --> CA["ctrl_A = PID A + Ramp A + jump A"]
  RA --> CA
  PB --> CB["ctrl_B = PID B + Ramp B + jump B"]
  RB --> CB

  CA & CB & ERR & REF & XY & AUX & IN1 & IN2 --> O1["[out1_sw] ± mod_out1/2 (sign of sq_ref)"] --> OUT1([OUT1])
  CA & CB & ERR & REF & XY & AUX & IN1 & IN2 --> O2["[out2_sw] ± mod_out2/2 (sign of sq_quad)"] --> OUT2([OUT2])
  REF -- "sq_ref" --> DIO7([DIO7_N])

  CA & CB & ERR & XY & REF & RA & RB & PA & PB --> SC["[oscA_sw], [oscB_sw]"] --> OSC([scope ch 1, ch 2])
  STRIG & RA -. "trigger events" .-> TS["[trig_sw]"] -.-> OSC
```

Main points (with the lines of `lock.v`):

- **Square generator** (l. 560-582, `lock/gen_mod_sq.v`): one counter over the period P = 2·(`gen_mod_sqp` + 1)
  ticks; `sq_ref` is 1 in the first half, `sq_quad` is `sq_ref` delayed by floor(P/4) (90° for odd `gen_mod_sqp`),
  `sq_phas` is delayed by `gen_mod_phase_sq` (≥ P → P−1); the three come out of the same 3-stage pipeline, so their
  relative timing is exact. They are 1-bit signals turned into ±4096 (`{~b, 1, 12'b0}`, l. 576-578); `sq_ref` also
  drives DIO7_N (l. 581) and the start of each period is the "Square mod." trigger.
- **Lock-in** (l. 699-774): `signal_i` and the three references are registered, `signal_i` is multiplied by ±1
  (a sign change, no multiplier) with each reference, scaled to 28 bits (`<< 13`), filtered by two cascaded
  first-order stages per line (`LP_filter_sq`, τ = 8 ns·2^(n+3), order 0/1/2), shifted by 2^`sg_amp` and saturated
  to 14 bits in two registered steps. sqX (from `sq_ref`) and sqY (from `sq_quad`) share `lpf_sq`/`sg_amp_sq`; sqF
  (from `sq_phas`) has `lpf_sqF`/`sg_amp_sqF`. All this chain is registered and meets timing.
- **Error** (l. 528-554): one of 0, sqXo, sqYo, sqFo, signal_i, in2, in1, in1−in2, minus `error_offset`; its mean
  and square are accumulated over 2²⁷ ticks for the Monitor.
- **PIDs** (l. 856-945): each PID takes a signal (`pidX_sw`), computes P, I, D (`lock_pid_block.v`) and its
  output is forced to 0 (and the integrator reset) when the lock control disables it.
- **Control signals** (l. 262-270): `ctrl_A = pidA_out + ramp_A + jumpA`, `ctrl_B = pidB_out + ramp_B + jumpB`,
  saturated.
- **Outputs** (l. 357-422): any of 16 signals, plus the square modulation (±`mod_out1`/2 with the sign of `sq_ref`
  on OUT1, ±`mod_out2`/2 with the sign of `sq_quad` on OUT2) when `mod_outX ≥ 0`, saturated. No multiplier: the
  same peak amplitude as the harmonic modulation of lock_in+pid_harmonic for the same `mod_out`.
- **Scope** (l. 272-325): two 21-input selectors; external trigger from `trig_sw` (l. 327-355).
- **Bus interface** (`[FPGA MEMORY DOCK]`, l. 949-1230): registers written by the PS and the read multiplexer.
  The read-only signals are read from registered copies (`*_rd`, l. 830-848, including `sq_ref`/`sq_quad`/`sq_phas`)
  and `sys_rdata` is loaded only during a read and then held (v2.3.17), because the PS side of the bus
  (`sys_bus_cdc`) takes it asynchronously some cycles later; the copies are not used by the real-time loop
  ([FPGA.md](FPGA.md#lock-module-0x40600000)).

Compared with lock_in+pid_harmonic: `gen_mod_h.v` and its ROM tables `data_*.dat` were removed; the five
references (`cos_ref`, `sin_ref`, `cos_1f..3f`) and five lock-in lines (X, Y, F1..F3, DSP multipliers, `LP_filter3`)
became three square references and three lines; the selectors were rebuilt (21 scope signals instead of 25) and
the offsets of the registers from `0x054` on moved (91 registers instead of 99).

### Lock control

The state machine of `lock/lock_ctrl.v`, configured and commanded by `lock_control` and observed in
`lock_status`. Full description: [`lock_control.md`](../lock_in+pid_square/doc/lock_control.md).

```mermaid
stateDiagram-v2
  [*] --> IDLE
  IDLE --> ARMED: launch_lock 0→1 (bit 1)
  IDLE --> LOCKED: lock_now 0→1 (bit 0)
  ARMED --> LOCKED: trigger (time / level / level+time) or lock_now 0→1
  ARMED --> IDLE: request bits 1-0 = 00
  LOCKED --> IDLE: request bits 1-0 = 00, or a manual enable (bits 4-2) changed
  note right of LOCKED
    enables = lock_control bits 7-5
    one-tick pulse "lock_ctrl_trig" on entry
    lock count + 1
  end note
  note left of IDLE
    enables = lock_control bits 4-2 (manual)
  end note
```

The time trigger counts ticks from the last scan floor of the ramp (`ramp_floor_trig`); the level trigger
watches the signal selected by `lock_trig_sw`. On entering LOCKED the FPGA emits `lock_ctrl_trig`, which is
bit 7 of `trig_sw` ("Lock control trig"): the web page arms a Single acquisition on it to capture the lock
(*Capture Lock*, [`lock_capture.md`](../lock_in+pid_square/doc/lock_capture.md)).

The sequence of a lock request from the page with Capture Lock:

```mermaid
sequenceDiagram
  participant UI as index.html
  participant C as controllerhf.so
  participant W as scope worker
  participant F as FPGA
  UI->>C: POST 1: Single, External, Ext Trig 128, window
  C->>W: new scope params
  UI->>C: POST 2: single_btn=1 + launch_lock_trig=1 (when idle)
  C->>W: arm Single
  W->>F: unlock trigger (0x94), arm, set source
  W-->>C: armed (rp_osc_worker_wait_armed)
  C->>F: lock_control bit 1 = 1 (ARMED)
  F->>F: trigger → LOCKED, ramp stops, PID on, lock_ctrl_trig
  F-->>W: scope triggered by the lock
  UI->>C: GET /data
  C-->>UI: capture (t = 0 = lock), frozen until Auto/Single
```

Times measured on the board with lock_in+pid_harmonic (same code): POST 2 → ARMED 17 ms, ARMED → LOCKED 16.9 ms (first sweep). With this App the sequence was checked with Time, Level and Fire on click (LOCKED 5/5, `reportes/lock-in_pid_sq.md`).

### Scope and streaming

- The scope (`fpga/rtl/rtl/classic/rp_scope_com.v`) samples `osc1`/`osc2` of the lock module, with a
  20-bit decimation. `osc_ctrl_w` of the lock module can bypass the equalization filters and, while
  streaming, impose the decimation `stream_rate` (`rp_scope_com.v` l. 194-207).
- Streaming: `c/streaming` waits for `stream_cmd = 1`, then `c/stream_tcp_osc_cmd` reads the circular
  buffers of the scope following the write pointer and sends the samples over TCP. The offsets of `stream_ip`,
  `stream_port`, `stream_rate`, `stream_cmd` (0x15C..0x168 in this App) are not hardcoded: `c/Makefile` generates
  `c/lock_offsets.h` from `c/lock.txt`. The web page must not
  read the scope meanwhile (the worker leaves the scope alone while `stream_cmd = 1`).

## Parameters, registers and `config_tool.py`

The same register list exists in several places: `lock.v` (registers and bus decoder), `src/fpga_lock.h`
(C struct), `src/lock.c` (writes/reads), `src/main.c`/`main.h` (parameters), `index.html` (fields and
selectors), `c/lock.c` / `c/osc.c` and `c/lock.txt` / `c/osc.txt` (tools), `py/hugo.py`.
`resources/config_tool.py` holds the table and regenerates the blocks marked by "docks" in those files
(`// [WIREREG DOCK]`, `// [FPGA MEMORY DOCK]`, `// [LOCKREGS DOCK]`, `[MAINDEFH DOCK]`, …). See
[Devel.md](Devel.md#registers-and-config_toolpy).
