#!/usr/bin/env node
// v2.0.12 (port of lock_in+pid_harmonic 2.3.33 = lock_in+pid 2.2.17 builds 34-36, with the selectors of the square lock-in of
//      this App): calibration in the display of the page ([CALIB DISPLAY] block of index.html) and Raw Mode. Final rule of the user (lock_in+pid build 35): in1 / in2 input calibration; in1-in2
//      mean input; lock-in displays (sqX, sqY, R, sqF) the input calibration of the lock-in input; ctrl_A / ctrl_B and
//      (only in this App) the scope signals out1 / out2 the DAC; everything else nominal (8192 counts = 1 V), also the
//      PID inputs in1 / in2 / in1-in2 (one-line switch calib_pid_in_calib / RP_SIG_PID_IN_CALIB, pending decision: both
//      positions tested, page = C) and the square references sq_ref, sq_quad, sq_phas.
//   1. calibSigScale(): scale of each kind of signal with no calibration params (old controller: 8192 counts = 1 V),
//      with the calibration of RP2 (Gen1, format 1) and of a Gen2 Pro v2.0 (format 6), the values of test/calib_test.c.
//   2. The same table as the controller (src/sig_scale.h, compiled with gcc: test/sig_scale_dump.c): 800 cases
//      (selector codes of this App), with the switch of the PID inputs in its position (0) and in the other one (1).
//   3. Parsers with units (Level trigger, click on the plot, Amp. p-p / Offset of the Ramp Controller): the integer
//      that the FPGA gets gives back the voltage typed (V = (n + c) k / 8192).
//   4. Labels of the page (real lock_ramp_step_update(), lock_pidA_update(), lock_ctrl_update(), rampFreqText() with a
//      mocked jQuery): mV calibrated with Raw Mode off, the integers ("counts") with Raw Mode on, nominal without the
//      calibration params.
//   5. Static checks of the C: Measure without offset in Raw Mode, scales of the scope from sig_scale.h, the read-only
//      calib_* params.
//
// Usage:  node test/calib_display_sim.js [index.html]   (sources in ../src; exit code 1 on failure)
'use strict';
const fs = require('fs'), vm = require('vm'), path = require('path'), cp = require('child_process'), os = require('os');

const args = process.argv.slice(2);
const file = args.find(a => !a.startsWith('--')) || path.join(__dirname, '..', 'index.html');
const html = fs.readFileSync(file, 'utf8');
const js = [...html.matchAll(/<script(?![^>]*src=)[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[1]).join('\n');
const srcDir = path.join(__dirname, '..', 'src');
const readSrc = n => { try { return fs.readFileSync(path.join(srcDir, n), 'utf8'); } catch(e) { return ''; } };

function braceFrom(i) {
  let d = 0;
  for(let k = js.indexOf('{', i); k < js.length; k++) {
    if(js[k] == '{') d++;
    else if(js[k] == '}' && --d == 0) return js.slice(i, k + 1);
  }
  return '';
}
function fnSrc(name) { const i = js.indexOf('function ' + name + '('); return i < 0 ? '' : braceFrom(i); }
function blockSrc(tag) {
  const a = js.indexOf('// [' + tag + ' BEGIN]'), b = js.indexOf('// [' + tag + ' END]');
  return (a < 0 || b < 0) ? '' : js.slice(a, b);
}
function varSrc(name) {
  const m = new RegExp('var ' + name + '\\s*=\\s*').exec(js);
  if(!m) return '';
  const j = m.index + m[0].length;
  if(js[j] == '{') return braceFrom(m.index) + ';';
  return js.slice(m.index, js.indexOf(';', j) + 1);
}

let fails = 0, n = 0;
function check(name, cond, extra) {
  n++;
  console.log((cond ? 'ok   ' : 'FAIL ') + name + (extra !== undefined ? '  [' + extra + ']' : ''));
  if(!cond) fails++;
}
const near = (a, b, tol) => Math.abs(a - b) <= (tol === undefined ? 1e-9 : tol);
const plain = s => String(s).replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ');

// calibration params of the page (read-only params of the controller, src/main.c)
const GEN1 = { calib_in1_lv: 1, calib_in1_hv: 20, calib_in2_lv: 1, calib_in2_hv: 20, calib_in1_offs_lv: 210, calib_in1_offs_hv: 0,
               calib_in2_offs_lv: -20, calib_in2_offs_hv: 0, calib_out1_fs: 1.0489, calib_out2_fs: 1.0489, calib_out1_offs: 0,
               calib_out2_offs: 0 };
const GEN2 = { calib_in1_lv: 1.14665, calib_in1_hv: 28.9156, calib_in2_lv: 1.14637, calib_in2_hv: 28.9116, calib_in1_offs_lv: 0,
               calib_in1_offs_hv: -1, calib_in2_offs_lv: 6, calib_in2_offs_hv: 5, calib_out1_fs: 2.3210, calib_out2_fs: 2.3234,
               calib_out1_offs: 290, calib_out2_offs: 301 };
const BASE = { lock_osc_raw_mode: 0, gain_ch1: 0, gain_ch2: 0, prb_att_ch1: 0, prb_att_ch2: 0, lock_out1_sw: 12, lock_out2_sw: 13,
               lock_pidA_sw: 0, lock_pidB_sw: 0, lock_lock_trig_sw: 0 };
const P = (cal, extra) => Object.assign({}, BASE, cal || {}, extra || {});

// ---- pure functions ---------------------------------------------------------------------------------------------
const blk = blockSrc('CALIB DISPLAY');
check('0.1 [CALIB DISPLAY] block in the page', blk.length > 0);
const ctx = { Math, Number, String, isFinite, parseFloat, console };
vm.createContext(ctx);
vm.runInContext(fnSrc('toFixedNz') + '\n' + blk + '\n' + varSrc('lock_trig_level_units') + '\n' +
                ['parseUnitValue', 'parseTrigLevel', 'clickToTrigLevel', 'parseRampCounts'].map(fnSrc).join('\n') +
                '\nthis.__get = function(e) { return eval(e); };', ctx);
const G = e => ctx.__get(e);
const S = (p, sig) => G('calibSigScale')(p, sig);
const osc = sw => G('calibSigOfOsc')(sw);

// ---- 1. scales --------------------------------------------------------------------------------------------------
{
  const nom = P(null);
  const all = ['in1', 'in2', 'int', 'in1_in2', 'lockin', 'ctrl_A', 'ramp_A', 'pidA_out', 'aux_A', 'ctrl_B', 'ramp_B', 'pidB_out', 'aux_B',
               'sq_ref', 'pidA_in', 'pidB_in', 'zero'];
  check('1.1 no calib params (older controller): every signal 8192 counts = 1 V, offset 0',
        all.every(s => S(nom, s).k === 1 && S(nom, s).c === 0));
  const nomAll = (p, list) => list.every(s => S(p, s).k === 1 && S(p, s).c === 0 && S(p, s).kind === 'nom');
  const others = ['int', 'zero', 'ramp_A', 'pidA_out', 'aux_A', 'ramp_B', 'pidB_out', 'aux_B', 'sq_ref', 'sq_quad', 'sq_phas',
                  'pidA_in', 'pidB_in'];
  const g1 = P(GEN1);
  check('1.2 Gen1 RP2: in1 LV k 1, c +210; in2 LV k 1, c -20', S(g1, 'in1').k === 1 && S(g1, 'in1').c === 210 &&
        S(g1, 'in2').k === 1 && S(g1, 'in2').c === -20);
  check('1.3 Gen1 RP2: ctrl_A / ctrl_B k 1.0489 c 0 (OUT1 / OUT2 offsets 0); error, Ramp, PID out, aux, refs, PID inputs nominal',
        ['ctrl_A', 'ctrl_B'].every(s => S(g1, s).k === 1.0489 && S(g1, s).c === 0 && S(g1, s).kind === 'out') && nomAll(g1, others));
  const g2 = P(GEN2);
  check('1.4 Gen2: in1-in2 = mean of LV (1.14651), c 0; error / sqXo / sqFo / signal_i / 0 (scope 3, 15, 17, 18, 21) nominal',
        near(S(g2, 'in1_in2').k, (1.14665 + 1.14637) / 2) && S(g2, 'in1_in2').c === 0 && S(g2, 'in1_in2').kind === 'mean' &&
        nomAll(g2, [osc(3), osc(15), osc(17), osc(18), osc(21)]));
  check('1.5 Gen2: in1 / in2 LV with their own full scale and correction', S(g2, 'in1').k === 1.14665 && S(g2, 'in1').c === 0 &&
        S(g2, 'in2').k === 1.14637 && S(g2, 'in2').c === 6);
  const g2h = P(GEN2, { gain_ch1: 1, gain_ch2: 1 });
  check('1.6 Gen2 HV both: in1 28.9156 c -1, in1-in2 mean of HV (28.9136)', S(g2h, 'in1').k === 28.9156 && S(g2h, 'in1').c === -1 &&
        near(S(g2h, 'in1_in2').k, (28.9156 + 28.9116) / 2));
  const g2m = P(GEN2, { gain_ch1: 1, gain_ch2: 0 });
  check('1.7 Gen2 IN1 HV / IN2 LV: in1-in2 = mean of LV (approximate rule), in1 HV, in2 LV',
        near(S(g2m, 'in1_in2').k, (1.14665 + 1.14637) / 2) && S(g2m, 'in1').k === 28.9156 && S(g2m, 'in2').k === 1.14637);
  const g2a = P(GEN2, { prb_att_ch1: 1, prb_att_ch2: 1 });
  const g2am = P(GEN2, { prb_att_ch1: 1, prb_att_ch2: 0 });
  check('1.8 probe x10 on both: in1-in2 x10; only on IN1: in1 x10, in1-in2 LV x1',
        near(S(g2a, 'in1_in2').k, 11.4651, 1e-9) && near(S(g2am, 'in1').k, 11.4665, 1e-9) && near(S(g2am, 'in1_in2').k, 1.14651, 1e-9));
  const L = (extra) => S(P(GEN2, extra), 'lockin');
  check('1.9 lock-in displays X .. F3 (Gen2): input in1 -> IN1 LV 1.14665 c 0 (no ADC offset), in2 HV x10 -> 289.116 c 0, in1-in2 -> mean, ' +
        'sq_ref / sq_quad / sq_phas / aux_A / Ramp A (3 .. 7) -> nominal',
        L({ lock_signal_sw: 0 }).k === 1.14665 && L({ lock_signal_sw: 0 }).c === 0 && L({ lock_signal_sw: 0 }).kind === 'input' &&
        near(L({ lock_signal_sw: 1, gain_ch2: 1, prb_att_ch2: 1 }).k, 289.116, 1e-9) && L({ lock_signal_sw: 1, gain_ch2: 1 }).c === 0 &&
        near(L({ lock_signal_sw: 2 }).k, 1.14651) && L({ lock_signal_sw: 2 }).kind === 'mean' &&
        [3, 4, 5, 6, 7].every(sw => L({ lock_signal_sw: sw }).k === 1 && L({ lock_signal_sw: sw }).kind === 'nom'));
  check('1.10 Gen2, ctrl_A on OUT1 / ctrl_B on OUT2: ctrl_A k 2.3210 c -290, ctrl_B k 2.3234 c -301; the rest of the chains nominal',
        S(g2, 'ctrl_A').k === 2.321 && S(g2, 'ctrl_A').c === -290 && S(g2, 'ctrl_B').k === 2.3234 && S(g2, 'ctrl_B').c === -301 &&
        nomAll(g2, others));
  const g2o = P(GEN2, { lock_out1_sw: 0, lock_out2_sw: 12 });
  check('1.11 Gen2, ctrl_A on OUT2 (OUT1 off): ctrl_A k 2.3234 c -301, Ramp A nominal', S(g2o, 'ctrl_A').k === 2.3234 && S(g2o, 'ctrl_A').c === -301 &&
        nomAll(g2o, ['ramp_A']));
  const g2p = P(GEN2, { lock_out1_sw: 10, lock_out2_sw: 15 });
  check('1.12 Gen2, PID A out on OUT1, aux_B on OUT2 (ctrl not routed): ctrl_A DAC 1 / ctrl_B DAC 2 without offset; PID A out, aux_B nominal',
        S(g2p, 'ctrl_A').k === 2.321 && S(g2p, 'ctrl_A').c === 0 && S(g2p, 'ctrl_B').k === 2.3234 && S(g2p, 'ctrl_B').c === 0 &&
        nomAll(g2p, ['pidA_out', 'aux_B', 'ramp_A']));
  const g2n = P(GEN2, { lock_out1_sw: 13, lock_out2_sw: 2 });
  check('1.13 Gen2, ctrl_B on OUT1, ctrl_A nowhere: ctrl_B DAC 1 c -290; ctrl_A default OUT1 c 0',
        S(g2n, 'ctrl_B').k === 2.321 && S(g2n, 'ctrl_B').c === -290 && S(g2n, 'ctrl_A').k === 2.321 && S(g2n, 'ctrl_A').c === 0);
  const g2r = P(GEN2, { lock_out1_sw: 9, lock_out2_sw: 5 });
  check('1.14 Gen2, sqYo on OUT1 and sq_ref on OUT2 (routed) and sq_quad / sq_phas (not): all nominal', nomAll(g2r, ['int', 'sq_ref', 'sq_quad', 'sq_phas']) &&
        G('calibSigOfOut')(1, 9) === 'int' && G('calibSigOfOut')(2, 5) === 'sq_ref');
  const g2i = P(GEN2, { lock_pidA_sw: 5, lock_pidB_sw: 3 });
  const g2j = P(GEN2, { lock_pidA_sw: 9, lock_pidB_sw: 0 });
  check('1.14b PID inputs (Ramp A, sqFo, aux_A, error): nominal', nomAll(g2i, ['pidA_in', 'pidB_in']) && nomAll(g2j, ['pidA_in', 'pidB_in']));
  const g2k = P(GEN2, { lock_pidA_sw: 7, lock_pidB_sw: 8 }), g2l = P(GEN2, { lock_pidA_sw: 6, lock_pidB_sw: 11 });
  check('1.14c PID inputs in1 / in2 (7 / 8), in1-in2 (6), sq_ref (11): nominal (PID inputs and set points, as lock_in+pid; switch off)',
        G('calib_pid_in_calib') === false && nomAll(g2k, ['pidA_in', 'pidB_in']) && nomAll(g2l, ['pidA_in', 'pidB_in']));
  const sw0 = ctx.calib_pid_in_calib;
  ctx.calib_pid_in_calib = true;   // the other position of the one-line switch (as lock_in+pid_plus)
  const sw1 = [S(g2k, 'pidA_in'), S(g2k, 'pidB_in'), S(g2l, 'pidA_in'), S(g2l, 'pidB_in'), S(g2i, 'pidA_in')];
  ctx.calib_pid_in_calib = sw0;
  check('1.14e switch calib_pid_in_calib = true: PID input in1 -> IN1 LV 1.14665 c 0, in2 -> 1.14637 c 6, in1-in2 -> mean, sq_ref / Ramp A nominal',
        sw1[0].k === 1.14665 && sw1[0].c === 0 && sw1[0].kind === 'input' && sw1[1].k === 1.14637 && sw1[1].c === 6 &&
        sw1[2].kind === 'mean' && sw1[3].kind === 'nom' && sw1[4].kind === 'nom', JSON.stringify(sw1.map(x => x.kind)));
  const g2x = P(GEN2, { lock_out1_sw: 0, lock_out2_sw: 1 });
  check('1.14d scope out1 / out2 (19 / 20 in this App): the DAC of that output with its offset, whatever is routed ' +
        '(Gen2 2.3210 c -290 / 2.3234 c -301; Gen1 1.0489 c 0)',
        osc(19) === 'out1' && osc(20) === 'out2' && [g2, g2x].every(p => S(p, 'out1').k === 2.321 && S(p, 'out1').c === -290 &&
        S(p, 'out1').kind === 'out' && S(p, 'out2').k === 2.3234 && S(p, 'out2').c === -301) &&
        S(g1, 'out1').k === 1.0489 && S(g1, 'out1').c === 0 && S(g1, 'out2').dac === 2);
  check('1.15 selectors: scope 1 in1, 4 ctrl_A, 6 ramp_A, 8 pidA_in, 12 sq_ref, 15 (sqXo) / 18 (signal_i) int, 21 zero; lock trig 7 in1, 9 in1_in2, 5 ramp_A, ' +
        '12 / 13 ctrl_A / ctrl_B (DAC), 14 ramp_B, 0 int',
        osc(1) === 'in1' && osc(4) === 'ctrl_A' && osc(6) === 'ramp_A' && osc(8) === 'pidA_in' && osc(12) === 'sq_ref' && osc(15) === 'int' &&
        osc(18) === 'int' && osc(21) === 'zero' &&
        G('calibSigOfTrig')(7) === 'in1' && G('calibSigOfTrig')(9) === 'in1_in2' && G('calibSigOfTrig')(5) === 'ramp_A' && G('calibSigOfTrig')(0) === 'int' &&
        G('calibSigOfTrig')(12) === 'ctrl_A' && S(g2, G('calibSigOfTrig')(13)).kind === 'out' && G('calibSigOfTrig')(14) === 'ramp_B');
  check('1.16 raw flag follows lock_osc_raw_mode', S(P(GEN2, { lock_osc_raw_mode: 1 }), 'in1').raw === true && S(g2, 'in1').raw === false);
}

// ---- 2. same table as the controller (src/sig_scale.h) -----------------------------------------------------------
// sw: position of the one-line switch of the PID inputs (C: -DRP_SIG_PID_IN_CALIB=sw, page: calib_pid_in_calib)
function dumpCompare(sw) {
  let out = null, why = '';
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'sigscale_'));
  try {
    const exe = path.join(tmp, 'dump');
    cp.execFileSync('gcc', ['-Wall', '-Werror', '-I' + srcDir].concat(sw === null ? [] : ['-DRP_SIG_PID_IN_CALIB=' + sw]).concat(
                          ['-o', exe, path.join(__dirname, 'sig_scale_dump.c'), path.join(srcDir, 'calib.c'), '-lm']), { stdio: 'pipe' });
    out = cp.execFileSync(exe, { encoding: 'utf8' });
  } catch(e) { why = String(e.message).split('\n')[0]; }
  try { fs.rmSync(tmp, { recursive: true, force: true }); } catch(e) {}
  if(out === null) return { err: why };
  let bad = 0, cnt = 0, first = '', cswitch = null;
  const kinds = { input: 0, mean: 1, out: 2, nom: 3 };
  const save = ctx.calib_pid_in_calib;
  for(const line of out.trim().split('\n')) {
    const v = line.trim().split(/\s+/).map(Number);
    cswitch = v[14];
    if(sw !== null) ctx.calib_pid_in_calib = !!sw;
    const p = P(v[0] ? GEN2 : GEN1, { gain_ch1: v[2], gain_ch2: v[3], prb_att_ch1: v[4], prb_att_ch2: v[5], lock_out1_sw: v[6],
                                       lock_out2_sw: v[7], lock_pidA_sw: v[8], lock_pidB_sw: v[9], lock_signal_sw: v[13] });
    const s = S(p, v[1] === 25 ? 'lockin' : v[1] === 26 ? 'in1_in2' : osc(v[1]));
    ctx.calib_pid_in_calib = save;
    cnt++;
    // full scales: the C stores them as V * 2^32 / 100 (rounded): relative 1e-6
    if(!(Math.abs(s.k - v[10]) <= 1e-6 * v[10] + 1e-7) || s.c !== v[11] || kinds[s.kind] !== v[12]) {
      bad++;
      if(!first) first = line + ' -> page ' + JSON.stringify(s);
    }
  }
  return { cnt, bad, first, cswitch };
}
{
  const r0 = dumpCompare(null);
  if(r0.err !== undefined) check('2.0 gcc + test/sig_scale_dump.c', false, r0.err);
  else {
    check('2.1 page = controller (sig_scale.h) for ' + r0.cnt + ' cases (Gen1 / Gen2, random settings, scope signals incl. out1 / out2, lock-in displays, in1-in2)',
          r0.cnt === 800 && r0.bad === 0, r0.bad ? r0.bad + ' differ, e.g. ' + r0.first : '');
    check('2.2 one-line switch of the PID inputs in the same position in the page and in the C (calib_pid_in_calib = RP_SIG_PID_IN_CALIB = 0)',
          r0.cswitch === (G('calib_pid_in_calib') ? 1 : 0) && r0.cswitch === 0, 'C ' + r0.cswitch + ', page ' + G('calib_pid_in_calib'));
    const r1 = dumpCompare(1);
    check('2.3 the other position of the switch (C -DRP_SIG_PID_IN_CALIB=1, page calib_pid_in_calib = true): page = controller for ' + r1.cnt + ' cases',
          r1.err === undefined && r1.cnt === 800 && r1.bad === 0 && r1.cswitch === 1, r1.err || (r1.bad ? r1.bad + ' differ, e.g. ' + r1.first : ''));
  }
}

// ---- 3. parsers --------------------------------------------------------------------------------------------------
{
  const g2 = P(GEN2), sr = S(g2, 'ramp_A'), si = S(g2, 'in1_in2'), s1 = S(P(GEN1), 'in1');
  const ptl = (str, s) => G('parseTrigLevel')(str, s);
  check('3.1 Level trigger, in1-in2 Gen2 (mean 1.14651 V): "0.1 V" -> 715, "100 mV" -> 715, "100" / "100 counts" / "1e2" -> 100',
        ptl('0.1 V', si) === 715 && ptl('100 mV', si) === 715 && ptl('100', si) === 100 && ptl('100 counts', si) === 100 && ptl('1e2', si) === 100,
        [ptl('0.1 V', si), ptl('100 mV', si), ptl('100', si), ptl('100 counts', si), ptl('1e2', si)].join(' '));
  check('3.2 Level trigger, in1 Gen1 (correction +210): "0 V" -> -210, without scale (old sims) "0.1 V" -> 819',
        ptl('0 V', s1) === -210 && ptl('0.1 V') === 819, ptl('0 V', s1) + ' ' + ptl('0.1 V'));
  const sc = S(g2, 'ctrl_A');
  const n = ptl('1 V', sc), back = G('calibToV')(n, sc);
  check('3.3 Level trigger with the ctrl_A scale (Gen2, OUT1, pure function): "1 V" -> 3820, and back 1 V (within half a count)',
        n === 3820 && Math.abs(back - 1) <= 0.5 * sc.k / 8192, n + ' -> ' + back.toFixed(6) + ' V');
  check('3.3b Level trigger on Ramp A (nominal since build 35): "0.5 V" -> 4096, "1 V" -> 8191 (limit)', ptl('0.5 V', sr) === 4096 && ptl('1 V', sr) === 8191,
        ptl('0.5 V', sr) + ' ' + ptl('1 V', sr));
  const ctl = G('clickToTrigLevel');
  check('3.4 click on the plot: 0.1 V in1-in2 Gen2 -> 715, raw 1234.4 -> 1234, no scale 0.6207 -> 5085',
        ctl(0.1, 0, si) === 715 && ctl(1234.4, 1, si) === 1234 && ctl(0.6207, 0) === 5085);
  const prc = G('parseRampCounts');
  check('3.5 Ramp Controller Gen2 (Ramp A nominal since build 35): Offset "0.5 V" -> 4096, Amp. p-p "0.5 V" -> 4096, "500" -> 500; ctrl_A scale: Offset "1 V" -> 3820, Amp "1 V" -> 3530',
        prc('0.5 V', sr) === 4096 && prc('0.5 V', sr, true) === 4096 && prc('500', sr) === 500 && prc('500 mV') === 4096 &&
        prc('1 V', sc) === 3820 && prc('1 V', sc, true) === 3530,
        [prc('0.5 V', sr), prc('0.5 V', sr, true), prc('500', sr), prc('500 mV'), prc('1 V', sc), prc('1 V', sc, true)].join(' '));
  const g1r = S(P(GEN1), 'ramp_A'), g1c = S(P(GEN1), 'ctrl_A');
  check('3.6 Gen1: Ramp "0.5 V" -> 4096 (nominal; build 34: 3905), ctrl_A scale "0.5 V" -> 3905', prc('0.5 V', g1r) === 4096 && prc('0.5 V', g1c) === 3905,
        prc('0.5 V', g1r) + ' ' + prc('0.5 V', g1c));
  const txt = G('calibMvText');
  check('3.7 calibMvText: Gen1 ctrl_A 5000 -> "640 mV", Ramp 5000 -> "610 mV"; Raw -> "5000 counts", half -> "0.5 counts"; Gen2 ctrl_A -290 -> -164 mV, span -82 mV',
        plain(txt(5000, g1c, 0)) === '640 mV' && plain(txt(5000, g1r, 0)) === '610 mV' && plain(txt(5000, Object.assign({}, g1c, { raw: true }), 0)) === '5000 counts' &&
        plain(txt(0.5, Object.assign({}, g1c, { raw: true }), 1)) === '0.5 counts' && plain(txt(-290, sc, 0)) === '-164 mV' &&
        plain(txt(-290, sc, 0, true)) === '-82 mV', [txt(5000, g1c, 0), txt(5000, g1r, 0), txt(-290, sc, 0), txt(-290, sc, 0, true)].map(plain).join(' | '));
}

// ---- 4. labels of the page ---------------------------------------------------------------------------------------
const elems = {};
function E(id) {
  if(!elems[id]) elems[id] = { id, value: '', html: '', prop: {}, data: {}, cls: {} };
  return elems[id];
}
function jq(sel) {
  const id = String(sel).replace(/^#/, '');
  const e = E(id);
  const o = {
    0: e, length: 1,
    val(v) { if(v === undefined) return e.value; e.value = String(v); return o; },
    html(v) { if(v === undefined) return e.html; e.html = String(v); return o; },
    text(v) { if(v === undefined) return e.html; e.html = String(v); return o; },
    prop(k, v) { if(v === undefined) return e.prop[k]; e.prop[k] = v; return o; },
    data(k) { return e.data[k]; },
    addClass() { return o; }, removeClass() { return o; }, toggle() { return o; }, show() { return o; }, hide() { return o; },
    is() { return false; }, blur() { return o; }, css() { return o; }, attr() { return o; }, hasClass() { return false; },
  };
  return o;
}
jq.isNumeric = v => !isNaN(parseFloat(v)) && isFinite(v);
jq.inArray = (v, a) => a.indexOf(v);
function uiCtx(local, withCalib) {
  const c = { $: jq, console, Math, Number, parseFloat, parseInt, isNaN, isFinite, String, Object,
              params: { local: local, original: local },
              parseLocalFloat: v => parseFloat(String(v).replace(',', '.')) };
  vm.createContext(c);
  let src = varSrc('units') + '\n' + varSrc('magni') + '\n' + varSrc('lock_trig_time_units') + '\n' + varSrc('ramp_fclk') + '\n' + varSrc('ramp_step_max') + '\n' + varSrc('lock_trig_level_units') + '\n';
  src += 'var ramp_step, lock_ramp_low_lim, lock_ramp_hig_lim, lock_ramp_B_factor, lock_ramp_sawtooth, period, oom, val, txt, mult, sgn_tag, tau;\n';
  src += 'var pidA_sp, pidA_kp, pidA_ki, pidA_kd, pidB_sp, pidB_kp, pidB_ki, pidB_kd, setpoint, timeval, lock_ctrl_aux_trig_type;\n';
  src += 'var lock_ramp_step_arr, lock_ramp_low_lim_arr, lock_ramp_hig_lim_arr, lock_ramp_B_factor_arr, ramp_step_arr;\n';
  src += 'var lock_pidA_sp_arr, lock_pidA_kp_arr, lock_pidA_ki_arr, lock_pidA_kd_arr;\n';
  src += 'var trig_time, trig_val, aux_trig_type;\n';
  for(const f of ['toFixedNz', 'rampPeriodCycles', 'rampStepsPerPeriod', 'rampStepForPeriod', 'rampParseStep', 'lock_ramp_step_update',
                  'lock_pidA_update', 'parseUnitValue', 'parseTrigTime', 'parseTrigLevel', 'lockTrigScale', 'lock_ctrl_update'])
    src += fnSrc(f) + '\n';
  if(withCalib) src += blockSrc('CALIB DISPLAY') + '\n';
  src += 'function trigFromGraphMsg() {}\nfunction lockQuickBtns() {}\n';
  src += 'this.__get = function(e) { return eval(e); };';
  vm.runInContext(src, c);
  return c;
}
function setFields(v) { for(const k in v) E(k).value = String(v[k]); }
{
  const fields = { lock_ramp_step: 400, lock_ramp_low_lim: -5000, lock_ramp_hig_lim: 5000, lock_ramp_B_factor: 4096,
                   lock_pidA_sp: 1000, lock_pidA_kp: 100, lock_pidA_ki: 0, lock_pidA_kd: 0, lock_pidA_PSR: 3, lock_pidA_ISR: 8,
                   lock_pidA_DSR: 0, lock_pidA_SAT: 13, lock_lock_trig_val: 0, lock_lock_trig_time_val: 0, lock_ctrl_aux_trig_type: 2 };
  const run = (local, withCalib) => {
    setFields(fields);
    for(const id of ['lock_ramp_low_lim_text', 'lock_ramp_hig_lim_text', 'lock_ramp_text', 'lock_pidA_sp_text', 'lock_lock_trig_val_text'])
      E(id).html = '';
    const c = uiCtx(local, withCalib);
    let err = '';
    try { c.__get('lock_ramp_step_update')(); } catch(e) { err += 'ramp: ' + e.message + ' '; }
    try { c.__get('lock_pidA_update')(); } catch(e) { err += 'pidA: ' + e.message + ' '; }
    try { c.__get('lock_ctrl_update')(); } catch(e) { err += 'ctrl: ' + e.message + ' '; }
    return { lo: plain(E('lock_ramp_low_lim_text').html), hi: plain(E('lock_ramp_hig_lim_text').html),
             ramp: plain(E('lock_ramp_text').html), sp: plain(E('lock_pidA_sp_text').html), trg: plain(E('lock_lock_trig_val_text').html), err };
  };
  const PL = (cal, extra) => Object.assign({ lock_ramp_sawtooth: 0, lock_pidA_PSR: 3, lock_pidA_ISR: 8, lock_pidA_DSR: 0, lock_pidA_SAT: 13 },
                                           P(cal, extra));
  const r0 = run(PL(null), false);
  check('4.1 without [CALIB DISPLAY] (as the other node sims): labels as 2.0.11 (-610 / 610 mV, 1221 mVpp, 122.09 mV, 0 mV)',
        !r0.err && r0.lo === '-610 mV' && r0.hi === '610 mV' && /1221 mVpp/.test(r0.ramp) && r0.sp === '122.09 mV' && r0.trg === 'Vtrg = 0 mV',
        JSON.stringify(r0));
  const rn = run(PL(null), true);
  check('4.2 with the block, no calib params (older controller): the same mV (setpoint / 8192: 122.07 mV, it was / 8191: 122.09)',
        !rn.err && rn.lo === '-610 mV' && rn.hi === '610 mV' && /1221 mVpp/.test(rn.ramp) && rn.sp === '122.07 mV', JSON.stringify(rn));
  const r1 = run(PL(GEN1), true);
  check('4.3 Gen1 RP2: Ramp -610 / 610 mV, 1221 mVpp (nominal since build 35; build 34: DAC 1.0489 V, 640 mV); setpoint 122.07 mV; Vtrg 0 mV (error)',
        !r1.err && r1.lo === '-610 mV' && r1.hi === '610 mV' && /1221 mVpp/.test(r1.ramp) && r1.sp === '122.07 mV' && r1.trg === 'Vtrg = 0 mV',
        JSON.stringify(r1));
  const r1t = run(PL(GEN1, { lock_lock_trig_sw: 7 }), true);
  check('4.4 Gen1 RP2, level trigger on in1 (LV correction +210): 0 counts = 26 mV', !r1t.err && r1t.trg === 'Vtrg = 26 mV', JSON.stringify(r1t));
  const r2 = run(PL(GEN2), true);
  check('4.5 Gen2, ctrl_A on OUT1: Ramp -610 / 610 mV, 1221 mVpp, 0.0 mVdc (nominal since build 35; build 34: -1499 / 1334 mV); setpoint 122.07 mV (nominal; build 34: 139.95 mV)',
        !r2.err && r2.lo === '-610 mV' && r2.hi === '610 mV' && /1221 mVpp/.test(r2.ramp) && /0\.0 mVdc/.test(r2.ramp) && r2.sp === '122.07 mV',
        JSON.stringify(r2));
  const rr = run(PL(GEN2, { lock_osc_raw_mode: 1, lock_lock_trig_sw: 7 }), true);
  // build 36: a space before pp / dc in Raw Mode (it was "10000 countspp", "0 countsdc")
  check('4.6 Raw Mode (Gen2): the integers, no scale, no offset: -5000 / 5000 counts, 10000 counts pp, 0 counts dc, 1000, 0',
        !rr.err && rr.lo === '-5000 counts' && rr.hi === '5000 counts' && /10000 counts pp/.test(rr.ramp) && /0 counts dc/.test(rr.ramp) &&
        rr.sp === '1000 counts' && rr.trg === 'Vtrg = 0 counts', JSON.stringify(rr));
  // a voltage typed in the ramp limit is converted with the calibration (Gen2, ctrl_A on OUT1)
  fields.lock_ramp_hig_lim = '0.5 V';
  const rv = run(PL(GEN2), true);
  check('4.7 Gen2: "0.5 V" typed in Ramp hig lim -> 4096 counts (nominal; build 34 with "1 V": 3820), label 500 mV', E('lock_ramp_hig_lim').value === '4096' && rv.hi === '500 mV',
        E('lock_ramp_hig_lim').value + ' ' + rv.hi);
  fields.lock_ramp_hig_lim = 5000;
  fields.lock_pidA_sp = '0.5 V';
  const rs = run(PL(GEN1), true);
  check('4.8 "0.5 V" typed in PID A setpoint (Gen1, error): 4096 counts, label 500.00 mV (parseInt gave 0 before)',
        E('lock_pidA_sp').value === '4096' && rs.sp === '500.00 mV', E('lock_pidA_sp').value + ' ' + rs.sp);
  // units rule (build 35): with units -> calibrated conversion, also in Raw Mode; without units -> the integer as it is
  fields.lock_pidA_sp = '0.5 V'; fields.lock_ramp_hig_lim = '0.5 V'; fields.lock_lock_trig_val = '0.1 V';
  run(PL(GEN2, { lock_osc_raw_mode: 1, lock_lock_trig_sw: 7 }), true);
  const rawV = [E('lock_pidA_sp').value, E('lock_ramp_hig_lim').value];
  fields.lock_pidA_sp = '1234'; fields.lock_ramp_hig_lim = '4321'; fields.lock_lock_trig_val = '-77';
  run(PL(GEN2, { lock_osc_raw_mode: 0 }), true);
  const offN = [E('lock_pidA_sp').value, E('lock_ramp_hig_lim').value, E('lock_lock_trig_val').value];
  run(PL(GEN2, { lock_osc_raw_mode: 1 }), true);
  const rawN = [E('lock_pidA_sp').value, E('lock_ramp_hig_lim').value, E('lock_lock_trig_val').value];
  check('4.8b units rule, Gen2: Raw Mode on, "0.5 V" in PID A setpoint and Ramp hig lim -> 4096 (nominal); ' +
        'no units -> the integer unchanged with Raw Mode off and on',
        rawV[0] === '4096' && rawV[1] === '4096' && offN.join() === '1234,4321,-77' && rawN.join() === '1234,4321,-77',
        rawV.join() + ' | ' + offN.join() + ' | ' + rawN.join());
  fields.lock_pidA_sp = 1000; fields.lock_ramp_hig_lim = 5000; fields.lock_lock_trig_val = 0;
}

// ---- 4b. lock-in display and Y range ----------------------------------------------------------------------------
{
  const d = fnSrc('display_update');
  check('4.9 display_update(): sqX, sqY, R, sqF in V with the scale of the lock-in input (\'lockin\') / 8192 / 8192; Raw Mode: the integers (scl = 1); ' +
        'calibDisplayKey() follows lock_signal_sw',
        /calibSigScale\(params\.local, 'lockin'\)\.k \/ 8192 \/ 8192/.test(d) && /if\(set_raw\) scl = 1;/.test(d) &&
        G('calibDisplayKey')(P(GEN2, { lock_signal_sw: 0 })) !== G('calibDisplayKey')(P(GEN2, { lock_signal_sw: 1 })));
  const u = fnSrc('updateRanges');
  check('4.10 updateRanges(): Raw Mode in counts (no mV / V)', /yunit = 'counts'/.test(u) && /yrange < 1 && !yraw/.test(u));
  check('4.11 calib_* are read-only keys (not sent, not saved in a config)', /'calib_in1_lv,calib_in1_hv/.test(js) &&
        /calib_out1_offs,calib_out2_offs'\)\.split/.test(js));
  check('4.12 loadParams(): labels written again when calibDisplayKey() changes', /cdk !== calib_display_key/.test(fnSrc('loadParams')));
}

// ---- 5. C --------------------------------------------------------------------------------------------------------
{
  const w = readSrc('worker.c'), m = readSrc('main.c'), h = readSrc('main.h');
  const mc = w.slice(w.indexOf('int rp_osc_meas_convert('));
  check('5.1 worker.c rp_osc_meas_convert(): no calibration offset in Raw Mode',
        /LOCK_OSC_RAW_MODE\]\.value > 0\)\s*\n\s*cal_dc_offs = 0;/.test(mc.slice(0, 800)));
  check('5.2 worker.c: channel full scales and offsets from sig_scale.h', /rp_sig_osc_scale\(rp_calib_params, curr_params, 0, &ch1_max_adc_v/.test(w) &&
        /rp_sig_osc_scale\(rp_calib_params, rp_osc_params, 0, NULL, cha_offs\)/.test(w) && !/fe_fsg1/.test(w));
  check('5.3 main.c get_scales() from sig_scale.h; routing / PID inputs update the worker', /rp_sig_osc_scale\(&rp_main_calib_params, p, 0/.test(m) &&
        /p_idx == LOCK_OUT1_SW\) \|\| \(p_idx == LOCK_OUT2_SW\)/.test(m));
  const names = ['calib_in1_lv', 'calib_in1_hv', 'calib_in2_lv', 'calib_in2_hv', 'calib_in1_offs_lv', 'calib_in1_offs_hv', 'calib_in2_offs_lv',
                 'calib_in2_offs_hv', 'calib_out1_fs', 'calib_out2_fs', 'calib_out1_offs', 'calib_out2_offs'];
  check('5.4 main.c: 12 read-only calib_* params after calib_status, PARAMS_NUM 215',
        names.every(k => new RegExp('"' + k + '"\\s*,[^}]*, 0, 1,').test(m)) && /#define PARAMS_NUM\s+215/.test(h));
}

console.log('=== ' + n + ' checks, ' + fails + ' failed ===');
process.exit(fails ? 1 : 0);
