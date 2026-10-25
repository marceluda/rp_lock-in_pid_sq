# Changelog of Square Lock-in+PID (`lock_in+pid_square`)

## Origin

`lock_in+pid_square` ("Square Lock-in+PID", repository `rp_lock-in_pid_sq`) was created on 2026-10-11 as a copy of
[`rp_lock-in_pid_h`](https://github.com/marceluda/rp_lock-in_pid_h) ("Harmonic Lock-in+PID", App
`lock_in+pid_harmonic`), branch `devel2.0`, **v2.3.18** (commit `5e3e748`), with its whole git history. The goal is
an App with all the features of the harmonic App but with **square modulation signals** like the ones of the
original [`rp_lock-in_pid`](https://github.com/marceluda/rp_lock-in_pid) App (`gen_mod2`, `sq_ref`, `sq_quad`,
`sq_phas`, square lock-in sqX/sqY/sqF), with the reference / quadrature pair running up to ~31 MHz, and the
modulation that can be added to `ctrl_A` / `ctrl_B` on the outputs.

The history of the code before 2.0.0 is the one of `lock_in+pid_harmonic`: see its CHANGELOG (v0.3.x for the
0.9x/1.0 ecosystems, v2.3.10 to v2.3.18 for the Ecosystem 2.0) in that repository or in the git history of this
one (`git show 5e3e748:CHANGELOG.md`). The comments "v2.3.x" in the sources refer to those versions.

Versioning: the major number 2 is the Ecosystem 2.0 version, as in the 2.x series of the other Apps
(lock_in+pid 2.2.x, lock_in+pid_harmonic 2.3.x, lock_in+pid_harmonic2 2.4.x); minor and patch start again
because this is a new App (the 0.x / 1.x numbers would suggest a version for the old ecosystems, which does not
exist for this App).


## v2.0.9 - 2026-10-24 - AUTO trigger level at the middle of the signal with a calibration offset or a full scale other than 1 V; Raw Mode half counts (C controller; page: version and comments only; no FPGA change; as lock_in+pid_harmonic 2.3.30)

Port of lock_in+pid_harmonic 2.3.30 (same code in this App). Issues of the AUTO found in the review of v2.0.8 (the half
count was seen on RP2 by testAgent, 2026-10-24 21:44; the other two do not show on RP1 / RP2).

- FIXED (C controller): **AUTO in volts with a calibration offset** (`fe_chX_dc_offs` of the input, from the EEPROM;
  RP2's are 0): the AUTO measures the signal with samples corrected by the offset, but the threshold registers compare
  raw samples. The threshold of its period search added the offset a second time (one offset **above** the middle),
  and the level it left had no offset at all (threshold and page line one offset **below** the middle of the trace).
  Now both are the middle of the signal in raw counts, and the level is the normalized voltage that the acquisition
  path turns into that threshold (`osc_fpga_cnv_cnt_to_trig_v()` with the calibration and user offsets): the *Level*
  shown by the page is the middle of the trace. Its period search compares raw samples with raw limits (a signal
  smaller than the offset gave no period) and its Y range no longer mixes raw and corrected counts.
- FIXED (C controller): **AUTO in volts with a normalized full scale other than 1 V** (`fe_ch1_fs_g_hi` of the EEPROM;
  RP1 / RP2 have exactly 1 V, a typical factory calibration ~1.07 V): the level and the Y range were stored as
  counts / 8192, but a normalized value is counts × full scale / 8192 (the acquisition converts the level with that
  full scale, the page multiplies by chX full scale / that full scale): both were scaled by 1 / full scale (~7 %).
- With offsets 0 and a full scale of 1 V (RP1 / RP2) the volts AUTO gives the same result as before.
- FIXED (C controller): **Raw Mode, half counts**: the AUTO left a level of half a count (e.g. −2.5) that the page
  showed as −2 (`Math.round`) while the controller wrote −3 (`roundf`). Now the AUTO gives a whole count rounded as the
  page, and `osc_fpga_cnv_cnt_to_trig_v()` rounds a level with a fraction (e.g. from a remote client) the same way
  (`floor(x + 0.5)`): the Level field and the threshold register always agree.
- Tests: `test/auto_set_c_sim` section 12, new checks 12.10-12.16 (calibration offset 585 and normalized full scale
  0.6543 V of the harness: volts AUTO threshold of the search and of the acquisitions that follow at the middle, level
  shown by the page = middle of the trace, Y range in V, Raw AUTO with a middle of −2.5 → −2 in level and register,
  half counts from a remote client; with the sources of v2.0.8, 6 fail: 12.13 already passed);
  `test/trig_level_test.c`: levels with a fraction (±0.25, ±0.5, ±0.75) give the count the page shows (with the
  `src/fpga.c` of v2.0.8, 64004 fail); `test/raw_trigger_sim.js`: section 9 (page and controller round half counts
  the same way) and code checks 8.4, 8.6-8.9 (53 checks; with the sources of v2.0.8, 5 fail).

## v2.0.8 - 2026-10-24 - Raw Mode: scope trigger level in ADC counts (C controller + web page, no FPGA change; as lock_in+pid_harmonic 2.3.29)

Port of lock_in+pid_harmonic 2.3.29 (same code in this App). Bug found in `rp_dummy2` (which inherited this code),
present in all earlier versions: with **Raw Mode** on, the *Level* of the scope trigger did not work.
- FIXED (C controller): in Raw Mode the page sends the level in ADC counts, but the controller passed it to
  `osc_fpga_update_params()`, which converts **volts** to counts: 100 counts were taken as 100 V and the threshold
  saturated (8191 minus the calibration offset; −3000 even wrapped to a positive threshold), so Normal / Single never
  triggered for a level other than 0. Now `rp_osc_trig_level_v()` (`src/worker.c`) turns the counts into the voltage
  that `osc_fpga_cnv_v_to_cnt()` maps back to exactly those counts (`osc_fpga_cnv_cnt_to_trig_v()`, `src/fpga.c`, with
  the calibration offset of the input selected by OscA / OscB and the user offset). A level beyond 8191 − calibration
  offset saturates there, as in volts mode.
- FIXED (C controller): AUTO in Raw Mode: the level of its search left the calibration offset out, its result (counts)
  was then applied as volts, and its Y range (counts) was scaled and clipped to ±1000 (`min_y` / `max_y` (`_norm`)
  limits, now ±20000; not scaled in Raw Mode). Volts mode unchanged.
- FIXED (web page): *Level* field, slider (and its drag) and trigger line in counts in Raw Mode (whole counts,
  −8192 … 8191; they used the volts scale and ±1), in V otherwise (± full scale); out-of-range values limited before
  sending; unit `counts` / `V` next to the field. The **Raw Mode** button converts the level (counts = V × 8192 / full
  scale at gain 1). *Config → load* of a config with the other Raw Mode sets Y to the Reset zoom range of its mode
  once (its level is not converted). The page opened in Raw Mode starts with Y ±8192 (it was ±1 count).
- Tests: new `test/raw_trigger_sim.js` (45 checks; the page of 2.0.7 fails 31) and `test/trig_level_test.c` (real
  `src/fpga.c`); `test/auto_set_c_sim` section 12 (thresholds written by the real controller in Raw Mode, AUTO in Raw
  Mode; the sources of 2.0.7 fail 6 of its 10 checks); `lock_capture_ui_sim.js`, `lock_ctrl_ui_sim.js`,
  `osc_presets_sim.js` load the new `[RAW TRIGGER]` block.

## v2.0.7 - 2026-10-20 - Quick trigger buttons time / level / time+level in Lock Control; fixed lost time/level and re-lock with a POST in flight (as lock_in+pid_harmonic 2.3.28)

Port of lock_in+pid_harmonic 2.3.28 (web page only, no FPGA / C change; same code, the lock trigger options and
the Choose from graph / Fire on click code of this App are the same as there). Requested by the user (2026-10-20).
- ADDED: **Lock Control**: three small buttons stacked between **Trigger Lock** and **Lock Now**: **time** (orange),
  **level** (blue), **time+level** (purple). A click on one of them sets the lock trigger type (Time trigger / Level
  Trigger / Level+time Trigger) and waits for a click on the graph, as *Choose from graph* (the *config* section is not
  opened): the button stays filled, the cursor over the scope is a crosshair and a short message
  (`#lock_quick_trig_msg`) is drawn over the rows below (state label, checkboxes) without moving the panel. The click
  on the graph sets the type and the time (from the scan floor) and / or the level and fires **Trigger Lock** at once
  (whatever *Fire on click* says), with **Capture Lock** if it is checked. Nothing is sent while waiting (an ARMED /
  LOCKED lock is kept until the click, then released and armed again). A 2nd click on the same button, Esc or
  *Choose from graph* cancel; another of the three buttons changes the type.
- CHANGED: layout of that row: *Trigger Lock*, the column of the three buttons and *Lock Now* are one centered flex row
  (column as tall as the big buttons, which are a bit larger: 16 px font, 60 px high); a container query makes all of
  them a bit smaller in a narrow left column (row < 235 px, e.g. 1366 px wide windows).
- FIXED: a click with *Choose from graph* + *Fire on click* while another POST was in flight lost the new time / level
  (`loadParams()`, `trigger_just_set`, wrote them as already sent; Trigger Lock fired with the old values). Now only
  the values already sent are protected; pending ones are sent after that POST.
- FIXED: with the lock LOCKED and a POST in flight at the click on the graph, neither the release nor the new request
  was sent (the send queued during a POST runs 100 ms after its answer and `lockWhenIdle()` did not wait for it). Now
  it is kept in `send_que_timer` and `lockWhenIdle()` waits for it: the release goes first, then the request.
- Tests: new `test/lock_quick_trig_sim.js` (57 checks, harness of `lock_capture_ui_sim.js`; the page of 2.0.6 fails 51).
  The other node tests unchanged and passing.

## v2.0.6 (2026-10-20) - "Load last config on init", Load last config / Reset to defaults; Lock Control below Outputs (as lock_in+pid_harmonic 2.3.27)

Port of lock_in+pid_harmonic 2.3.27 (web page only, no FPGA / C change). Requested by the user (2026-10-20): the App
opened with the parameters of a previous session; the user wants to choose.
- CHANGED: **Lock Control** panel moved right below **Outputs** in the left column (Oscilloscope, Outputs, Lock Control, Lock-in modules, Ramp Controller, PIDs modules, Streaming).
- CHANGED: the state that the page saves automatically (`saveState()`, every ~2 s and after each POST) is now also kept in
  **localStorage** (`lockin_last_state_lock_in+pid_square`, shared by the tabs, survives closing the browser): the **last config**.
  The tab state (`sessionStorage`, used by *Restart*) is kept as before.
- ADDED (Config dialog) checkbox **Load last config on init** (`#load_last_on_init`), **checked by default**, saved in
  localStorage (`lockin_load_last_on_init_lock_in+pid_square`). When the page starts the App (main menu, new tab, F5): checked, the
  last config is restored; unchecked, only `def_params` are sent (defaults of `src/main.c`). Ramp / PIDs of a restored
  config follow *Don't turn on PIDs and Ramp on config loading*; lock requests are never restored.
- ADDED (Config dialog) buttons **Load last config** and **Reset to defaults**: they close the dialog and restart the App
  (reload; stopped and started as when it is opened, FPGA reloaded) with the last config / with the defaults, whatever
  the checkbox says. Reset to defaults = a fresh App (no table of defaults in the page), lock open, no lock request.
- ADDED hold (`lockin_last_hold_lock_in+pid_square`): opened with the defaults, the last config is kept until the user changes a
  parameter (time window / Y axis alone do not count), so *Load last config* brings it back.
- *Restart* (took control, error dialogs) and the automatic restarts still restore the tab state; an App already running
  when the page opens keeps its state (stopped and started for Load last config / Reset to defaults).
- Tests: new `test/last_config_sim.js` (35 checks; the page of 2.0.5 fails). The other node tests unchanged and passing.

## v2.0.5 (2026-10-19) - Auto waits for the trigger (Scan floor report); "Don't turn on PIDs and Ramp on config loading" unchecked by default (as lock_in+pid_harmonic 2.3.26)

Requested by the user (2026-10-19): loading a config switched the scan off; it should start scanning if it was
scanning when the config was saved. This change is in the web page only.

### Changed (web page)
- The option **Don't turn on PIDs and Ramp on config loading** (Config dialog, `#load_config_block_start`) is kept
  but is now **unchecked by default** (it was checked). Unchecked, *Config → load* (and *Load file*, which goes through
  the same load) and the restore of the tab state after a start / *Restart* (`restoreState()`) set
  `lock_ctrl_aux_ramp_enable_ctrl`, `lock_ctrl_aux_pidA_enable_ctrl`, `lock_ctrl_aux_pidB_enable_ctrl` and
  `lock_ramp_enable` (*Scan enable*) as saved. Checked, they are set to 0 as before. The lock requests
  (`lock_ctrl_aux_lock_now`, `lock_ctrl_aux_launch_lock_trig`) and the other transient commands
  (`state_transient_zero`) are never loaded, with or without the option.
- The option is not saved (configs, tab state, localStorage): every page load starts unchecked. The checkbox has
  `autocomplete="off"` (a browser that restores form fields on reload, e.g. Firefox on F5, could otherwise show a
  state different from the variable)
  and the variable is synced from the checkbox when the handlers are set.

### Tests
- New `test/config_load_block_sim.js` (10 checks: default unchecked, Config load and Restart restore ramp / Scan enable
  / PIDs as saved, checked keeps them off, lock requests always 0). With the page of 2.0.4 6 of them fail.
  The other node tests unchanged (they set the option explicitly).

### Changed (controller, `src/worker.c`; web page): Auto waits for the trigger
Reported by testAgent (2026-10-19, lock_in+pid_square 2.0.3/2.0.4 on RP2; `reportes/lock-in_pid_sq.md`): with Ext Trig =
Scan floor the trace sometimes started at the ceiling of the scan. Cause: in **Auto** the scope triggered at once
(`osc_fpga_cnv_trig_source(trig_imm = 1)` = manual trigger source in `src/fpga.c`), so t = 0 fell on any phase of the
scan; the Ext Trig (and the level of a channel) only worked in Normal / Single. The config of the user had Auto.
- Auto now arms the real trigger source (as Normal) and the worker forces the acquisition (manual trigger source)
  only if no trigger came within a time limit counted from the moment the trigger is enabled
  (`rp_osc_auto_timeout_us()`): max(0.25 s, 1.1 x window + 50 ms, 1.1 x period of the Ext Trig + 50 ms), at most 80 s.
  The period is known for Scan floor / Scan ceil when the scan runs (Scan enable on, not in reset, effective ramp
  enable of `lock_ctrl.v` = `lock_status` bit 4; same formula as `rampPeriodCycles()` of the page) and for Square mod. (2 x (sqp+1) cycles, as `sqPeriodCycles()`).
  Choice of the values: 0.25 s keeps the free view (no trigger) at ~4 traces per second and is longer than the default
  64 ms scan; 1.1 x window lets a signal whose period fits in the window always trigger in time; 1.1 x period makes a
  slow scan behave as Normal (30 s scan, window 0..29.4 s: limit 33.05 s; the next floor comes ~0.6 s after the
  re-arm, so every scan is acquired from its floor); a stopped scan (or LOCKED with the ramp off) gives no period term,
  so Auto does not wait a whole period for a floor that will not come. 80 s > the longest window (68.7 s).
- Unchanged: Normal and Single (never forced), the Auto window (from the trigger, t = 0 .. xmax, no pre-trigger, as
  `src/main.c` sets it for Auto), the resume of an acquisition across POSTs that do not change it (the limit is
  recomputed and keeps counting from the same moment), the long acquisitions of 2.3.23 (forced or not, the reader
  starts at the trigger), Capture Lock (Single + Ext Trig 128) and AUTO (its own immediate acquisitions).
  `scope_acq_state` is 2 (armed) while Auto waits and 3 after the (real or forced) trigger.
- Page: the trigger *Level* field, its line and slider are enabled in Auto too (they were only for Normal); the
  "Choose from graph" warning no longer asks for Normal/Single (Auto + External + Scan floor gives t = 0 at the floor).

### Tests (Auto)
- `test/auto_set_c_sim/harness.c` section 11 (`SIM_AUTO=1 test/auto_set_c_sim/run.sh` runs only it): 11.1 Auto + Scan floor
  every 3 s, window 0..2.94 s: every trace from a floor, none forced; 11.2 scan stopped, window 0..0.1 s: forced every
  ~0.40 s (0.25 s + the acquisition); 11.3 3 s scan seen in 0..0.1 s: only floors (period term); 11.4 Normal without
  trigger: nothing. With the `src/` of 2.0.4: 11.1-11.3 fail (immediate triggers). 6.1 runs 9 s (Auto without trigger
  waits 2.25 s now) and section 8 waits 0.6 s for an Auto trace in ms. (Section 10 of this harness is the square generator.)

### Also
- The `<title>` and page title of the source `index.html` said v2.0.3; now v2.0.5.

## v2.0.4 (2026-10-16) - Scope presets (OscA|OscB) and Ext Trig sets the Trigger panel (port of lock_in+pid_harmonic 2.3.24)

Port of lock_in+pid_harmonic v2.3.24 (web page only: no FPGA, no controller change; comments "v2.0.4" in
`index.html` mark the port). This App has only the square lock-in, so the third preset is labelled `sqX|sqY` (the names of the signals in the selects, sqXo/sqYo) instead of `X|Y`.

- Added (page): **presets of the scope signals**: six small buttons in the *Oscilloscope* panel, below *Ext Trig*
  (row *Presets*, two rows of three, 42x20 px, label in one line, 10 px bold). Blue: `in1|in2`, `in1|ctrl` (in1,
  ctrl_A), `sqX|sqY` (sqXo, sqYo, mux 15, 16); green: `in1|err` (in1, error), `ctrl|err` (ctrl_A, error) and `usr`. A click sets OscA/OscB
  (mux values 1, 2, 3, 4, 15, 16, read from the options of the selects) through the same path as the two selects: one POST
  with only `lock_oscA_sw` / `lock_oscB_sw` (plus the usual `single_btn`/`xmin`/`xmax` with their current values);
  the zoom, the trigger (Mode, Source, Edge, Level, Ext Trig) and a Capture Lock are not touched. The title of each
  button names its two signals.
- Added (page): **`usr` preset**, a pair chosen by the user. Double click (or a click while it is not configured,
  dashed border) opens a dialog with two selects (all the options of OscA/OscB; the first time OscA = PID A out (10),
  OscB = error (3)); *Accept* saves the pair in the browser (`localStorage`, key `oscUsrPreset_lock_in+pid_square`) and shows
  it. It is saved in the configs (*Config* save and download json, in `ui.ui_osc_usr_a` / `ui.ui_osc_usr_b`, never
  sent to the server); a *Config load* of a config that has it takes it, configs without it keep the current pair.
- Changed (page): **Ext Trig sets the Trigger panel**: when the user picks in *Ext Trig* a value different from the
  current one and not *None*, the *Trigger* panel goes to *Source* = External and *Mode* = Normal in the same POST
  (from *Single* the page polls again). *None* changes nothing else. *Config load*, the restore at the end of a
  Capture Lock, *Reset zoom* and *AUTO* do not apply it. During a Capture Lock the change ends it and the restore and
  the new values go in one POST.
- Tests: new `test/osc_presets_sim.js` (37 checks; the page of 2.0.3 fails 32); `test/config_load_window_sim.js`:
  stub of `oscUsrConfigLoad()`.

## v2.0.3 (2026-10-16) - Reset zoom, mouse wheel on the scope and slow scans (port of lock_in+pid_harmonic 2.3.21-2.3.23)

Port of lock_in+pid_harmonic v2.3.21 (Reset zoom), v2.3.22 (mouse wheel) and v2.3.23 (slow scans, FPGA `lock_ctrl.v`);
see its CHANGELOG for the details and the board tests. New FPGA image. Comments "v2.3.2x" refer to lock_in+pid_harmonic.

- Added (page): **Reset zoom** sets X from t = 0 to one period of the ramp (Ext Trig = Scan floor / Scan ceil:
  sawtooth (high−low+1)·(step+1), triangle 2·(high−low)·(step+1) ticks), one period of the **square modulation**
  (Ext Trig = Square mod.: 2·(`gen_mod_sqp`+1) ticks, `gen_mod_sq.v`) or one whole memory at the current Dec (other
  Ext Trig); periods ≥ 1.5 s: 0.98 × the period (at least 50 ms before the next trigger). Y to −1 … 1 V (raw mode
  −8192 … 8192). During a lock capture it first ends it (as AUTO); the Raw Mode button rescales Y. The trigger menu
  has no "harmonic mod." (removed in v2.0.0).
- Added (page): **mouse wheel on the scope**: no key zooms both axes, SHIFT only time (cursor ↔), ALT only the Y axes
  (cursor ↕, no POST); X window 20 ns … 68.7 s; local zoom during a lock capture; xmin/xmax sent without rounding to 2
  decimals (a fast zoom from s to ms sent 0/0).
- Fixed (controller, page): **slow scans** (windows ≥ 1.5 s): new long-acquisition reader in `src/worker.c`
  (`rp_osc_long_rd_*`: never a sample of an older lap of the scope memory or from before the history, `adc_we_cnt`
  register 0x2C, OK only when complete, ends at the window of the user); Capture Lock holds the lock request until the
  scope has enabled its trigger (`lock_request_*` in `src/lock.c`, the POST answers at once); read-only params
  `scope_gen`, `scope_acq_state`, `scope_acq_gen`, `sig_gen` (`PARAMS_NUM` 198 -> 202); page: capture recognised by
  `sig_gen`, partial traces drawn, banners, real "LOCKED but not captured"; Reset zoom clears stale traces.
- Fixed (FPGA, `lock_ctrl.v`, same file as lock_in+pid_harmonic 2.3.23): the time trigger counter is valid (`cnt_ok`)
  only from a floor of a ramp that has been running since then (new input `ramp_run` = `ramp_enable & ~ramp_reset`),
  and it saturates instead of wrapping every 34.4 s: a time (or level+time) request armed after a stop fires at the
  next floor + time, never mid-scan. With the ramp running nothing changes.
- `example_usage.py`: note about `time` / `timeout` for slow ramps.
- Tests: new `test/reset_zoom_sim.js` (31, square periods), `test/plot_wheel_sim.js` (59), `test/ramp_mod_period_sim.sh`
  (ramps and `gen_mod_sq` periods, 11); `lock_capture_ui_sim.js` section 8 (slow scan; the square-App section 8 of
  v2.0.0 is now 9), `auto_set_c_sim` sections 6-9 (the square registers section 6 of v2.0.0 is now 10), `lock_ctrl_tb.v`
  cases 16-19.


## v2.0.2 (2026-10-15) - App icon

- New App icon and logo provided by the user (`resources/icon.png`, `resources/logo.png`, `resources/logo.svg`);
  `lock_in+pid_square/info/icon.png` is now that icon (it was the icon of `lock_in+pid_harmonic`).
- No FPGA, C or page logic changes (same bitstream as v2.0.1).


## v2.0.1 (2026-10-13) - FPGA timing: pipeline registers in the PIDs and the outputs

Port of the timing work of `lock_in+pid_harmonic` v2.3.19 (the user allowed adding latency): **WNS -9.308 -> -0.657 ns,
TNS -5095 -> -59 ns, 3409 -> 301 failing endpoints** (adc_clk -> dac_clk_1x +1.819 ns). Same behaviour except for the
latencies, checked bit by bit in simulation against v2.0.0. Details: `lock_in+pid_square/doc/lock_latency.md`.

- Changed (FPGA, added latency, 8 ns per clock): PID outputs +1 (`lock_pid_block` output registered, enable delayed
  with it); `out1`/`out2` +1 for everything that goes to the DACs (out mux and square modulation registered before
  the sum). LOCK MODE loop +16 ns. The square generator and the square lock-in are not changed.
- Changed (FPGA): the references reach the square lock-in 1 clock later (`ref_X0..F0`), so the phase measured through
  DAC -> system -> ADC does not change (without it: -90 deg at 31.25 MHz).
- Changed (FPGA, same values): `sat14` without barrel shifter, PID integrator with the ISR shift in parallel.
- Changed: page title (`h2.page-title`) and `<title>` get the version of `info/info.json` at build time (Makefile).
- Added `test/lock_latency_sim.sh` + `test/lock_latency_tb.sv` (xsim, 338 checks against v2.0.0);
  `test/sq_lockin_tb.v` compares OUT1/OUT2 with the references of the clock before.

## v2.0.0 (2026-10-11)

First version. Built from `lock_in+pid_harmonic` v2.3.18 (tag `v2.0.0`, commit `9e7b4a9`). Tested on the board
with builds 5 and 6 (see Notes).

### Notes

- Board tests (RP2, RedPitaya_OS 2.04-35, `dummy_simulator` on a second board; testAgent 2026-10-12): generator
  exact to the tick (period 4 ticks and quadrature 1 tick at 31.25 MHz, 2500 / 625 at 50 kHz, phase 0..P−1,
  "Square mod." trigger stable); lock-in at 50 kHz equal to the correlation from the scope (sqX 204.6 / sqY 567.6
  vs 207 / 562 counts; sqF follows the phase); real lock at 50 kHz with error = sqYo by time, level and Fire on click
  (5/5, ctrl_A 8.5–8.8 mV, the same point as lock_in+pid_harmonic); HTTP remote control (`example_usage.py` 15/15,
  exact `gen_mod_sqp` above 2^24 kept); streaming 976 kS/s, overrun 0; Config save/load without read-only keys;
  unit fields; Restart. Test configuration: `test_files/lock_in+pid_square__lock_mode.json` (Apps folder).
- Lock at **31.25 MHz** on the board (build 6, testAgent 2026-10-12 14:00, input filter of `dummy_simulator` turned
  off): `gen_mod_sqp` 1, A Out1 200, ×2, `lpf_sq` 262 µs, error = sqYo with phase 0, kp −250 / ki −20; 4/4 locks
  (Time and Level, HTTP and web page), 70 s locked, error −1.0 ± 3.8 counts, ctrl_A 8.9 mV (same point of the peak as
  at 50 kHz). A beat of ≈ 2.1 kHz between the clocks of the two boards is removed by the 262 µs filter. Test
  configuration: `test_files/lock_in+pid_square__lock_mode_31MHz.json`. The reference `lock_mode` configurations use
  kp −250 since 2026-10-12 (it was −500).
- Not tested yet: re-lock, step response, DIO7_N output, the SSH client and the `py/` scripts other than `lock_from_registers.py`.
- FPGA timing (build 4): WNS −9.308 ns / TNS −5095 ns in the paths inherited from lock_in+pid_harmonic; every path
  of the new square generator / lock-in has positive slack.
- Documentation (2026-10-12, docAgent): `README.md` and `doc/` written for this App: `App.md` and `FPGA.md` reviewed
  against the RTL and completed with the board results; `Usage.md` (square panels, unit fields, procedures with the
  test configuration and screenshots of this App in `doc/.Usage/sq_*`), `Structure.md` (Mermaid diagram of the square
  generator / lock-in), `Remote.md` (square helpers of `control_finn.py`, recipes) and `Devel.md` (sources, tests,
  timing, versioning) rewritten from the pages inherited from lock_in+pid_harmonic.

### Fixes after the first test on the board (2.0.0-5, testAgent 2026-10-12), same 2.0.0 (build 6, FPGA unchanged)

- `c/streaming.c`: end of streaming with `fprintf(stderr, ...)` instead of `perror()` (the log said ": Success"),
  as lock_in+pid_harmonic_hf / harmonic2.
- `py/lock_from_registers.py --help`: "Square Lock-in+PID, lock_in+pid_square v2.0.0 or later" (it said
  "lock_in+pid_square v2.3.13").
- Half period above 2^24: the page shows the float32 echo of the register (even, rounded) and warned "use an odd
  value for 90°" although the register may be odd: no warning above 2^24 (quadrature error < 1e-6°).
- Page in "Single" after `acquire()` + `scope_auto()` from Python (server in Auto): not reproduced. The page adopts
  the `trig_mode` of the server in every GET /data as lock_in+pid_harmonic 2.3.18 (same `loadParams()` code); new
  checks 8.1-8.4 of `test/lock_capture_ui_sim.js`: Single while Python acquires, Auto after `scope_auto()` (also from
  Single), but **not while a field of the page is in edit mode (focus)**: then it is applied when the edit ends.
  That (or a POST of the page in flight) is the likely cause; pressing AUTO or clicking outside the field fixes it.

### Renamed

- App folder `lock_in+pid_harmonic` → `lock_in+pid_square` (the other Apps use full words in the folder:
  `lock_in+pid_harmonic` for `rp_lock-in_pid_h`), name "Square Lock-in+PID" (`info/info.json`, title of the
  page), nginx locations `/lock_in+pid_square/...`, `app_id`, paths of `fpga.sh`, `fpga.conf`, `c/load_bit.sh`,
  `c/stream_start.sh`, `c/streaming.c`, `src/main.c`, `upload_app.sh`, Makefiles, `.gitignore`,
  `resources/config_tool.py`, `control_finn.py`, the scripts of `resources/` and the documentation.
- Saved configs: own localStorage key `lockConfig_lock_in+pid_square`; the configs of the shared key
  `lockConfig` (lock_in+pid / old lock_in+pid_harmonic) are not imported (other lock-in parameters).
- Icon: the one of lock_in+pid_harmonic (to be replaced).

### FPGA (`lock.v`, Vivado 2020.1)

- New square generator `lock/gen_mod_sq.v` (replaces `gen_mod_h.v` and its ROM tables `data_*.dat`): one
  counter over the period P = 2·(`gen_mod_sqp`+1) ticks, f = 125 MHz / P: **31.25 MHz** with `gen_mod_sqp` = 1,
  62.5 MHz with 0 (no quadrature), down to 0.029 Hz. `sq_ref` (first half of the period), `sq_quad` = `sq_ref`
  delayed by floor(P/4) ticks (exactly 90° for odd `gen_mod_sqp`), `sq_phas` = `sq_ref` delayed by
  `gen_mod_phase_sq` ticks (values ≥ P act as P−1), a trigger at the start of each period ("Square mod.",
  `trig_sw` = 8). The three outputs come from the same counter value through a 3-stage pipeline (same latency).
  `sq_ref` is also the digital modulation output DIO7_N (it was 0), as in lock_in+pid.
- New square lock-in: `signal_i` multiplied by ±1 with `sq_ref` / `sq_quad` / `sq_phas` (registered), two
  cascaded first-order low-pass stages `lock/LP_filter_sq.v` (τ = 8 ns·2^(n+3), n = 0..27: 64 ns .. 8.6 s; order
  0/1/2; registered input and a two-step registered shift in the feedback, so neither the bypass mux nor the
  variable shift is in the clock of the 64-bit accumulator; accumulator reset by a local copy of `rst`),
  gain 2^n (0..15) and saturation to 14 bits (two registers). `signal_i` and the references are registered
  before the ±1 product; the other datapath registers have no reset (timing: the paths of the reset net to the
  R pins failed). sqX and sqY share filter (`lpf_sq`) and gain
  (`sg_amp_sq`); sqF has `lpf_sqF` and `sg_amp_sqF`. Scale: `sq?_28 = mean(±signal_i)·2^13`.
- Modulation added to the outputs: OUT1 ± `mod_out1`/2 with `sq_ref`, OUT2 ± `mod_out2`/2 with `sq_quad`
  (negative: off). Same peak amplitude as the harmonic modulation for the same value; no multiplier.
- Selectors: scope (21 signals: ..., `sq_ref`, `sq_quad`, `sq_phas`, `sqXo`, `sqYo`, `sqFo`, `signal_i`, out1,
  out2), outputs (`sq_ref`, `sq_quad`, `sq_phas`, `sqXo`, `sqYo` instead of the harmonic references), lock-in
  input, error (0, sqXo, sqYo, sqFo, signal_i, in2, in1, in1−in2), PID inputs, lock trigger signal (0 error,
  1-3 sqXo/sqYo/sqFo, ..., 11 PID B out, 12 ctrl_A, 13 ctrl_B, 14 Ramp B, 15 aux_B), re-lock signal (5-7 sqXo,
  sqYo, sqFo). See `doc/FPGA.md`.
- Register map (generated by `resources/config_tool.py`): `sg_amp0..3`, `lpf_F0..3`, `gen_mod_phase`,
  `gen_mod_hp`, `sin_ref`, `cos_ref`, `cos_1f..3f`, `X_28`, `Y_28`, `F1_28..F3_28` replaced by `sg_amp_sq`,
  `sg_amp_sqF`, `lpf_sq`, `lpf_sqF` (7 bits: `[6:5]` order, `[4:0]` tau), `gen_mod_sqp`, `gen_mod_phase_sq`
  (32 bits), `sq_ref`, `sq_quad`, `sq_phas`, `sqX_28`, `sqY_28`, `sqF_28`. **The offsets from 0x054 on change**
  (e.g. `in1` 0xBC, `pidA_kp` 0x104, `stream_ip` 0x15C); 0x000-0x050 (scope, outputs, lock control, `signal_sw`,
  `signal_i`) are the same as in lock_in+pid_harmonic. 91 registers (0x000-0x168).
- Unchanged from v2.3.18: lock control FSM (`lock_ctrl.v`, registered inputs, `lock_status`), bus reads from
  registered copies held during `sys_ren` with the multicycle constraint (CDC fix of v2.3.17), PIDs, ramp,
  re-lock and step response, 20-bit scope decimation, streaming control.
- `red_pitaya_vivado_Z10.tcl`: no `.dat` files (an `add_files` of an empty glob is an error in Vivado).
- Timing: see the build of v2.0.0 in `devAgent.md` (WNS, as in the harmonic App, does not close in the long
  paths of the loop; the new lock-in chain is fully registered).

### C controller, `c/` tools, Python

- `src/`: docks regenerated (FPGAUPDATE, PARAMSUPDATE, FPGARESET, FPGAREG, MAINDEF, MAINDEFH; 198 parameters).
  `gen_mod_sqp` and `gen_mod_phase_sq` are full uint32 registers: written only when the value derived from the
  parameter changes, and a value written from outside (c/lock, Python) is copied to the parameter and kept
  exact, as the lock trigger registers of v2.3.18 (`lock_sq_known`, `lock_update_status()`). The v2.3.18 block
  of the lock trigger registers is now produced by `config_tool.py` (it was hand-written in the dock and would
  have been lost when regenerating).
- `c/lock.txt`, `c/osc.txt`, `c/lock.c` regenerated. `c/streaming.c` and `c/stream_tcp_osc_cmd.c`: offsets of
  `stream_ip/port/rate/cmd` from `c/lock_offsets.h`, generated by `c/Makefile` from `c/lock.txt` (as
  lock_in+pid_harmonic2 v2.4.3); they were hardcoded with the offsets of lock_in+pid_harmonic.
- `py/hugo.py` (REGSET dock) regenerated; `py/lock_from_registers.py`: `--sw` list of this App.
- `resources/config_tool.py`: square registers, `lpf_*` encoding, UI lists (28 time constants, gains,
  `trig_sw` without "harmonic mod."), `folder` also found when the repository has another name, the hand-written
  unit fields (`lock_lock_trig_time_val`, `lock_lock_trig_val`, `lock_gen_mod_sqp`, `lock_gen_mod_phase_sq`) are
  not regenerated, the lock control buttons are not put in `input_buttons`, no trailing spaces / indented empty
  lines in the generated JS.

### Web page (`index.html`)

- "Square lock-in" panel instead of "Harmonic lock-in": *Square oscillator* with **Half period** (number, a
  frequency `50 kHz` / `31.25 MHz` or a period `20 us`; the text shows f, T, ticks per period and the quadrature
  angle, with a warning for even values) and **Phase** (ticks, `90 deg`, `0.5 pi`, `rad` or a delay; shown in
  degrees and ticks, limited to P−1); *Demodulation* tabs "sqX & sqY" and "sqF" with filter (time constant and
  order) and gain.
- "Square Lock-in" display: sqX, sqY, R, φ and sqF (scale `sq?_28 / 2^13` counts).
- "Square Modulation Amplitude" (A Out1 / A Out2) with the meaning of the values.
- Selectors regenerated from `lock.v` (scope, outputs, error, PIDs, lock trigger, re-lock, Ext Trig).

### Remote control

- `control_finn.py`: `reg_labels` from the selectors of the page; `set_freq()` / `set_freq_hz(freq,
  quadrature=True)` (nearest odd `gen_mod_sqp`), `get_freq()`, `get_period()`, `set_phase(val, units='ticks' |
  'deg' | 'rad')`, `set_lpf(tau_exponent 3..30, order, line='xy' | 'f' | 'all')`, `get_lpf()`, `set_gain('xy' |
  'f', ...)`, `get_XY()` (sqX, sqY [, sqF]), `set_modulation_amplitud()` (square, same values).
- `example_usage.py`: square signals and the lock-in calls of this App (CRLF kept).

### Tests (new / adapted)

- `test/sq_lockin_sim.sh` + `test/sq_lockin_tb.v` (xsim): generator period / duty / quadrature / phase / trigger
  for several `gen_mod_sqp`, and the whole lock module with OUT1 looped back to IN1: sqX/sqY/sqF against the
  correlation of the references at 31.25 MHz, 20.8 MHz and 625 kHz, gains and saturation, OUT1/OUT2 modulation,
  filter OFF and first-order time constant.
- `test/sq_modulation_ui_sim.js` (node): unit parsers of the square fields, texts, blur/send, `lpf_update()`,
  display, HTML.
- `test/lock_bus_read_tb.sv`: addresses of this map. `test/minor_ui_sim.js`: labels of this App.
  `test/auto_set_c_sim/harness.c`: part 6, square registers.


## Pending

- Icon of the App (provisional: the one of lock_in+pid_harmonic).
- GitHub repository `rp_lock-in_pid_sq`: published 2026-10-15 (branch `master`).
- Screenshots still missing in `doc/`: Square Lock-in display opened, sqF tab, Auxiliar / Square Modulation
  Amplitude, Outputs and Oscilloscope panels of this App, a scan with sqXo / sqYo.
