#!/usr/bin/env node
// Bug 11 (checks 11.1-11.3, 2026-11-26; testAgent, lock_in+pid_harmonic 2.3.33-75): the real format_oom() of the page
//   through the real display_update(): no exponential notation in any lock-in display (in2 in HV gave "1.2e+2 uV").
// v2.0.12 (port of lock_in+pid_harmonic 2.3.33 / lock_in+pid 2.2.17 build 36), bug 10 of lock_in+pid: titles of the lock-in displays after Raw Mode on -> off. The real display_update() of
// index.html runs with a mocked jQuery, Raw Mode switched on and off several times:
//   Raw Mode on : "sqX [int]", "sqY [int]", "R [int]", "ϕ [deg]", "sqF [int]" and the values as plain integers
//   Raw Mode off: "sqX", "sqY", "R", "ϕ", "sqF" again, values in V.
// Up to v2.0.11 (and lock_in+pid build 35) the titles stayed "X [int]" after Raw Mode off: last_disp_units read $('#btn_disp_units').data('checked'),
// a button that does not exist in this page (undefined), so the branch that restores the titles never ran.
//
// Usage:  node test/disp_labels_sim.js [index.html]      (exit code 1 if a check fails; v2.0.11 fails)
'use strict';
const fs = require('fs'), vm = require('vm'), path = require('path');

const args = process.argv.slice(2);
const file = args.find(a => !a.startsWith('--')) || path.join(__dirname, '..', 'index.html');
const html = fs.readFileSync(file, 'utf8');
const js = [...html.matchAll(/<script(?![^>]*src=)[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[1]).join('\n');

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

let nfail = 0, nchk = 0;
function check(name, ok, info) {
  nchk++;
  if(!ok) nfail++;
  console.log((ok ? 'ok   ' : 'FAIL ') + name + (info !== undefined ? '  [' + info + ']' : ''));
}

// ---- mocked jQuery: elements by selector (#id or label[for="id"]) ----------------------------------------------
const el = {};
function E(sel) {
  if(!el[sel]) el[sel] = { html: '', data: {}, cls: {} };
  return el[sel];
}
// titles as in the page (index.html <label for="disp_x">...)
function htmlLabel(id) {
  const m = html.match(new RegExp('<label[^>]*for="' + id + '"[^>]*>([\\s\\S]*?)</label>'));
  return m ? m[1].trim() : '?';
}
const ids = ['disp_x', 'disp_y', 'disp_r', 'disp_fi', 'disp_F'];
for(const id of ids) E('label[for="' + id + '"]').html = htmlLabel(id);
const initial = ids.map(id => E('label[for="' + id + '"]').html);
E('#slow_lock_in_display').cls.in = true;
E('#fast_lock_in_display').cls.in = true;

function $(sel) {
  const e = E(sel);
  const o = {
    html(v) { if(v === undefined) return e.html; e.html = String(v); return o; },
    data(k) { return e.data[k]; },
    hasClass(c) { return !!e.cls[c]; },
  };
  return o;
}

const ctx = { $, Math, Number, String, isNaN, console: { log() {} }, Date,
              params: { local: { lock_sqX: 8192 * 8192, lock_sqY: -4096 * 8192, lock_sqF: 300, lock_error_mean: 0, lock_error_std: 0, lock_osc_raw_mode: 0 } },
              set_bar() {}, format_oom: (v, u) => Number(v).toPrecision(4) + ' ' + u };
vm.createContext(ctx);
// the page globals (last_disp_units=false; lasttsp=...) are at the top level of the script
const glob = (js.match(/^\s*last_disp_units\s*=.*$/m) || ['last_disp_units=false;'])[0];
vm.runInContext(blockSrc('CALIB DISPLAY') + '\n' + fnSrc('toFixedNz') + '\n' + fnSrc('display_val') + '\n' +
                fnSrc('display_update') + '\n' + glob + '\nlasttsp = 0; fixn = 0;\nthis.__get = function(e){return eval(e)};', ctx);
const upd = ctx.__get('display_update');

function step(raw) {
  E('#lock_osc_raw_mode').data.checked = raw;
  ctx.params.local.lock_osc_raw_mode = raw ? 1 : 0;
  upd();
  return { labels: ids.map(id => E('label[for="' + id + '"]').html), x: E('#disp_x').html };
}

console.log('--- titles of the lock-in displays with Raw Mode off / on / off / on / off');
check('0 page titles (no Raw Mode): sqX, sqY, R, ϕ, sqF', initial.join() === 'sqX,sqY,R,ϕ,sqF', initial.join());
let r = step(false);
check('1 Raw Mode off (first update): titles unchanged, value in V', r.labels.join() === 'sqX,sqY,R,ϕ,sqF' && / V$/.test(r.x), r.labels.join() + ' | ' + r.x);
r = step(true);
check('2 Raw Mode on: sqX [int] .. ϕ [deg] .. sqF [int], value a plain integer',
      r.labels.join() === 'sqX [int],sqY [int],R [int],ϕ [deg],sqF [int]' && r.x === String(8192 * 8192), r.labels.join() + ' | ' + r.x);
r = step(true);
check('3 Raw Mode still on (next update): the same titles', r.labels.join() === 'sqX [int],sqY [int],R [int],ϕ [deg],sqF [int]', r.labels.join());
r = step(false);
check('4 Raw Mode off (bug 10: they stayed "sqX [int]"): sqX, sqY, R, ϕ, sqF again, value in V',
      r.labels.join() === 'sqX,sqY,R,ϕ,sqF' && / V$/.test(r.x), r.labels.join() + ' | ' + r.x);
r = step(true);
const on2 = r.labels.join();
r = step(false);
check('5 on -> off a second time: [int] and back', on2 === 'sqX [int],sqY [int],R [int],ϕ [deg],sqF [int]' &&
      r.labels.join() === 'sqX,sqY,R,ϕ,sqF', on2 + ' | ' + r.labels.join());
check('6 static: display_update() does not read #btn_disp_units (no such button in the page)',
      !/btn_disp_units/.test(fnSrc('display_update').replace(/\/\/.*$/gm, '')));

// ---- bug 11 (testAgent, lock_in+pid_harmonic 2.3.33-75, 2026-11-26): no exponential notation in the lock-in displays
// The real format_oom() and units of the page (the checks above use a stub) through the real display_update(). Lock-in
// input in2 with Channel 2 HV (x20): F2 = 97 counts = 115.7 uV gave "1.2e+2 uV" (format_oom() got pre = 2, the digits
// of the integer 97, and toPrecision(2) of 115.7 is exponential).
{
  console.log('--- bug 11: real format_oom(), no exponential notation');
  const um = js.match(/var\s+units\s*=\s*\{[^}]*\}\s*;/);
  const c2 = { $, console: { log() {} }, params: { local: {} }, set_bar() {}, lia_pll_display() {} };
  vm.createContext(c2);
  vm.runInContext((um ? um[0] : '') + '\n' + blockSrc('CALIB DISPLAY') + '\n' + fnSrc('toFixedNz') + '\n' + fnSrc('display_val') + '\n' +
                  fnSrc('format_oom') + '\n' + fnSrc('display_update') + '\n' + glob +
                  '\nlasttsp = 0; fixn = 0;\nthis.__get = function(e){return eval(e)};', c2);
  const fo = c2.__get('format_oom'), upd2 = c2.__get('display_update');
  const expo = s => /[0-9]e[-+]?[0-9]/i.test(s) || /NaN|undefined|Infinity/.test(s);
  const d = fnSrc('display_update');
  const keys = [...new Set([...d.matchAll(/display_val\('(lock_[A-Za-z0-9_]+)'\)/g)].map(m => m[1]))]
               .filter(k => !/^lock_(error_|stream_)/.test(k));
  const dispIds = () => Object.keys(el).filter(s => /^#disp_/.test(s) && !/^#disp_(error_|stream_)/.test(s));
  function run(vals, extra) {
    for(const s of dispIds()) el[s].html = '';
    E('#lock_osc_raw_mode').data.checked = false;
    c2.params.local = Object.assign({ lock_error_mean: 0, lock_error_std: 0, lock_osc_raw_mode: 0 }, vals, extra);
    upd2();
    const out = {};
    for(const s of dispIds()) if(el[s].html !== '') out[s] = el[s].html;
    return out;
  }
  const f1 = fo(97 * 20 / 2047 / 8192, 'V', 2), f2 = fo(-115.7e-6, 'V', 2), f3 = fo(99.96e-6, 'V', 2), f4 = fo(999.96e-6, 'V', 3),
        f5 = fo(0.5, 'V', 3), f6 = fo(NaN, 'V', 3), f7 = fo(0, 'V', 2), f8 = fo(99.97, 'deg');
  check('11.1 format_oom(): 97 counts x20 (115.7 uV, pre 2) -> "116 uV", -115.7 uV -> "-116 uV", 99.96 uV (pre 2) -> "100 uV", ' +
        '999.96 uV (pre 3) -> "1.00 mV", 0.5 V -> "500 mV", 0 -> "0.0", 99.97 deg -> "100 deg", NaN -> "---"',
        f1 === '116&nbsp;uV' && f2 === '-116&nbsp;uV' && f3 === '100&nbsp;uV' && f4 === '1.00&nbsp;mV' && f5 === '500&nbsp;mV' &&
        f7 === '0.0&nbsp;&nbsp;V' && f8 === '100&nbsp;&nbsp;deg' && /^---/.test(f6), [f1, f2, f3, f4, f5, f6, f7, f8].join(' | '));
  // the case of the board: every lock-in register = 97, Lock-in input in2, Channel 2 HV
  const v97 = {};
  for(const k of keys) v97[k] = 97;
  const o97 = run(v97, { lock_signal_sw: 1, gain_ch2: 1 });
  const ids97 = Object.keys(o97);
  const plain = s => /^-?[0-9]+(\.[0-9]+)?&nbsp;/.test(s);
  check('11.2 display_update(), Lock-in input in2 + Channel 2 HV, all registers 97: every label a plain decimal number, no exponential (' + keys.join(', ') + ')',
        ids97.length >= 4 && ids97.every(s => plain(o97[s]) && !expo(o97[s])),
        ids97.map(s => s.slice(6) + '=' + o97[s].replace(/&nbsp;/g, ' ')).join(', '));
  // sweep: integers of 1 .. 2^27 digits, both signs, scales x1 (LV), x20 (HV), x200 (HV, probe x10), nominal (other
  // lock-in input), in1 / in2 / in1-in2
  const ints = [1, 2, 5, 9, 10, 11, 42, 97, 99, 100, 101, 409, 410, 999, 1000, 1001, 4095, 4096, 9999, 10000, 12345, 99999,
                100000, 409500, 999999, 1000000, 2047 * 8192, 9999999, 2047 * 8192 * 4, 99999999, 134217727];
  let seed = 7;
  const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
  for(let i = 0; i < 300; i++) ints.push(Math.round(Math.pow(10, rnd() * 8.1)));
  const setups = [];
  for(const sw of [0, 1, 2, 3]) for(const g of [[0, 0], [1, 0], [1, 1]])
    setups.push({ lock_signal_sw: sw, lock_signal2_sw: sw, lock_signal_sw_2: sw, gain_ch1: g[0], gain_ch2: g[0], prb_att_ch1: g[1], prb_att_ch2: g[1] });
  let nlab = 0, bad = [];
  for(const st of setups) for(const n of ints) for(const sg of [1, -1]) {
    const vals = {};
    keys.forEach((k, j) => { vals[k] = sg * (j % 2 ? n : Math.max(1, Math.round(n / (j + 1)))); });
    const o = run(vals, st);
    for(const s in o) { nlab++; if((expo(o[s]) || !plain(o[s])) && bad.length < 5) bad.push(s + '=' + o[s] + ' (n ' + sg * n + ', ' + JSON.stringify(st) + ')'); }
  }
  check('11.3 sweep of ' + ints.length + ' integers x 2 signs x ' + setups.length + ' scales (LV, HV, HV x10 probe; in1 / in2 / in1-in2 / ' +
        'nominal): ' + nlab + ' labels, none exponential / NaN', nlab > 1000 && bad.length === 0, bad.join('; '));
}

console.log('=== ' + nchk + ' checks, ' + nfail + ' failed ===');
process.exit(nfail ? 1 : 0);
