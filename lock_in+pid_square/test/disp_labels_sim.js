#!/usr/bin/env node
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

console.log('=== ' + nchk + ' checks, ' + nfail + ' failed ===');
process.exit(nfail ? 1 : 0);
