#!/usr/bin/env node
// lock_in+pid_square v2.0.0: simulation of the square generator / lock-in part of the web page, with functions
// taken from index.html and a mocked jQuery/DOM:
//   1. parseSqPeriod(): half period field in ticks, frequency (Hz, kHz, MHz) or period (s, ms, us, ns)
//   2. parseSqPhase(): phase field in ticks, angle (deg, rad, pi) or delay, with the period of the field
//   3. lock_modulation_update(): f / T / quadrature text and the phase text (degrees, ticks, limit P-1)
//   4. numberInputBlur(): "50 kHz" -> field rewritten as 1249 and sent as lock_gen_mod_sqp = 1249; invalid text
//      not sent and restored; the phase in degrees is converted with the period
//   5. lpf_update(): the four square filter selects are copied to params.local and sent
//   6. display_update(): sqX/sqY/sqF/R/phi of the "Square Lock-in" panel (scale sq?_28 = counts * 8192)
//   7. HTML: the selects/inputs of the square panel exist and the harmonic ids are gone
//
// Usage:  node test/sq_modulation_ui_sim.js [index.html]      (exit code 1 if a check fails)
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
function fnSrc(name) { const i = js.indexOf('function ' + name + '('); if(i < 0) throw new Error('not found: ' + name); return braceFrom(i); }
function varSrc(name) {
  const m = new RegExp('var ' + name + '\\s*=\\s*').exec(js);
  if(!m) throw new Error('not found: var ' + name);
  const j = m.index + m[0].length;
  if(js[j] == '{') return braceFrom(m.index) + ';';
  return js.slice(m.index, js.indexOf(';', j) + 1);
}

let n = 0, fails = 0;
function check(name, ok, info) {
  n++; if(!ok) fails++;
  console.log((ok ? 'ok   ' : 'FAIL ') + name + (info !== undefined ? '  [' + info + ']' : ''));
}

// ---- mocked DOM / jQuery ---------------------------------------------------------------------------------
const elems = {};
function E(id) { return elems[id] || (elems[id] = { id, value: '', html: '', cls: new Set(), data: {}, nodeType: 'mock' }); }
function jq(sel) {
  if(sel && sel.nodeType === 'mock') sel = '#' + sel.id;
  const m = String(sel).match(/^label\[for="([^"]+)"\]$/);
  const ids = m ? ['label_' + m[1]] : String(sel).split(',').map(s => s.trim().replace(/^#/, ''));
  const es = ids.map(E);
  const o = {
    0: es[0],
    val(v) { if(v === undefined) return es[0].value; es.forEach(e => e.value = String(v)); return o; },
    html(v) { if(v === undefined) return es[0].html; es.forEach(e => e.html = String(v)); return o; },
    text(v) { return o.html(v); },
    addClass(c) { es.forEach(e => String(c).split(' ').forEach(x => e.cls.add(x))); return o; },
    removeClass(c) { es.forEach(e => String(c).split(' ').forEach(x => e.cls.delete(x))); return o; },
    hasClass(c) { return es[0].cls.has(c); },
    data(k) { return es[0].data[k]; },
    css() { return o; }, attr() { return o; }, parent() { return o; }, blur() { return o; },
  };
  return o;
}
jq.isNumeric = v => !isNaN(parseFloat(v)) && isFinite(v);
jq.inArray = (v, a) => a.indexOf(v);

let sent = [];
const ctx = {
  $: jq, console, Math, Number, String, Object, isNaN, isFinite, parseInt, parseFloat, Date,
  document: { activeElement: null },
  setTimeout() { return 0; }, clearTimeout() {},
  sendParams() { sent.push(Object.assign({}, ctx.params.local)); },
  params: { local: { lock_gen_mod_sqp: 1, lock_gen_mod_phase_sq: 0 }, original: {} },
  user_editing: false, text_param_editor: '', lasttsp: 0, last_disp_units: false,
};
vm.createContext(ctx);
let src = 'var edit_timers = {};\n' + varSrc('units') + '\n' + varSrc('lock_trig_time_units') + '\n' +
          varSrc('lock_trig_level_units') + '\n';
for(const f of ['getLocalDecimalSeparator', 'parseLocalFloat', 'parseUnitValue', 'parseTrigTime', 'parseTrigLevel',
                'numberInputValue', 'editTimerCancel', 'editRefocusCheck', 'numberInputBlur', 'isSendable', 'lpf_update',
                'display_val', 'format_oom', 'display_update'])
  src += fnSrc(f) + '\n';
src += varSrc('input_unit_parsers') + '\n';
// the square block of the page (tables, parsers, registration, lock_modulation_update)
{
  const a = js.indexOf('  var sq_freq_units');
  const b = js.indexOf('function lock_modulation_update(');
  src += js.slice(a, b) + braceFrom(b) + '\n';
}
src += 'function lock_ctrl_update() {}\nfunction set_bar(id, v) { bars[id] = v; }\nvar bars = {};\n';
vm.runInContext(src, ctx);
const P = s => ctx.parseSqPeriod(s), F = s => ctx.parseSqPhase(s);

// ---- 1. period ---------------------------------------------------------------------------------------------
check('1.1 ticks: "1" -> 1, "0" -> 0, "1249" -> 1249', P('1') === 1 && P('0') === 0 && P('1249') === 1249);
check('1.2 frequency: "31.25 MHz" -> 1, "50 kHz" -> 1249, "1kHz" -> 62499, "62.5 MHz" -> 0',
      P('31.25 MHz') === 1 && P('50 kHz') === 1249 && P('1kHz') === 62499 && P('62.5 MHz') === 0,
      [P('31.25 MHz'), P('50 kHz'), P('1kHz'), P('62.5 MHz')].join(','));
check('1.3 period: "20 us" -> 1249, "32 ns" -> 1, "1 s" -> 62499999', P('20 us') === 1249 && P('32 ns') === 1 && P('1 s') === 62499999,
      [P('20 us'), P('32 ns'), P('1 s')].join(','));
check('1.4 above 62.5 MHz -> 0; very low frequency -> 2^32-1; invalid -> NaN',
      P('100 MHz') === 0 && P('0.001 Hz') === 4294967295 && isNaN(P('abc')) && isNaN(P('')) && isNaN(P('5 V')) && isNaN(P('-3')),
      [P('100 MHz'), P('0.001 Hz'), P('abc'), P('-3')].join(','));

// ---- 2. phase ----------------------------------------------------------------------------------------------
E('lock_gen_mod_sqp').value = '1249';      // P = 2500 ticks
check('2.1 ticks: "625" -> 625', F('625') === 625);
check('2.2 angle with P = 2500: "90 deg" -> 625, "180°" -> 1250, "0.5 pi" -> 625, "-90 deg" -> 1875, "450 deg" -> 625',
      F('90 deg') === 625 && F('180°') === 1250 && F('0.5 pi') === 625 && F('-90 deg') === 1875 && F('450 deg') === 625,
      [F('90 deg'), F('180°'), F('0.5 pi'), F('-90 deg'), F('450 deg')].join(','));
check('2.3 rad and delay: "3.14159265 rad" -> 1250, "5 us" -> 625', F('3.14159265 rad') === 1250 && F('5 us') === 625);
E('lock_gen_mod_sqp').value = '31.25 MHz';  // P = 4
check('2.4 at 31.25 MHz (P = 4): "90 deg" -> 1, "270 deg" -> 3, "8 ns" -> 1', F('90 deg') === 1 && F('270 deg') === 3 && F('8 ns') === 1);
E('lock_gen_mod_sqp').value = 'xx';         // invalid field: period from params.local (1 -> P = 4)
check('2.5 invalid period field: P from params.local (sqp 1): "180 deg" -> 2', F('180 deg') === 2);

// ---- 3. texts ----------------------------------------------------------------------------------------------
const plain = s => s.replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').replace(/&deg;/g, '°').replace(/&pi;/g, 'π');
E('lock_gen_mod_sqp').value = '1'; E('lock_gen_mod_phase_sq').value = '1';
ctx.lock_modulation_update();
let t1 = plain(E('lock_gen_mod_sqp_text').html), t2 = plain(E('lock_gen_mod_phase_sq_text').html);
check('3.1 sqp 1: f = 31.250 MHz, T = 32.000 ns, 4 ticks, quadrature 90°', /f = 31\.250 MHz/.test(t1) && /T = 32\.000 ns/.test(t1) && /4 ticks/.test(t1) && /90°/.test(t1), t1);
check('3.2 phase 1 of 4: 90.0 deg', /90\.0 deg/.test(t2) && /1 of 4 ticks/.test(t2), t2);
E('lock_gen_mod_sqp').value = '2'; ctx.lock_modulation_update();
t1 = plain(E('lock_gen_mod_sqp_text').html);
check('3.3 sqp 2: 20.833 MHz, quadrature 60.0° with the advice to use an odd value', /20\.833 MHz/.test(t1) && /60\.0°/.test(t1) && /odd/.test(t1), t1);
E('lock_gen_mod_sqp').value = '0'; E('lock_gen_mod_phase_sq').value = '7'; ctx.lock_modulation_update();
t1 = plain(E('lock_gen_mod_sqp_text').html); t2 = plain(E('lock_gen_mod_phase_sq_text').html);
check('3.4 sqp 0: 62.5 MHz without quadrature; phase 7 limited to P-1 = 1', /62\.500 MHz/.test(t1) && /none/.test(t1) && /1 of 2 ticks/.test(t2) && /limited/.test(t2), t1 + ' | ' + t2);
E('lock_gen_mod_sqp').value = '50 kHz'; E('lock_gen_mod_phase_sq').value = '90 deg'; ctx.lock_modulation_update();
t1 = plain(E('lock_gen_mod_sqp_text').html); t2 = plain(E('lock_gen_mod_phase_sq_text').html);
check('3.5 "50 kHz" while typing: f = 50.000 kHz, T = 20.000 us; "90 deg": 625 of 2500 ticks', /50\.000 kHz/.test(t1) && /20\.000 us/.test(t1) && /625 of 2500/.test(t2), t1 + ' | ' + t2);
E('lock_gen_mod_sqp').value = '16777218'; ctx.lock_modulation_update();
t1 = plain(E('lock_gen_mod_sqp_text').html);
check('3.7 sqp above 2^24 (float32 echo, even): no "odd value" warning', /90°/.test(t1) && !/odd/.test(t1), t1);
E('lock_gen_mod_sqp').value = '1000000'; ctx.lock_modulation_update();
t1 = plain(E('lock_gen_mod_sqp_text').html);
check('3.8 even sqp below 2^24: warning kept', /odd/.test(t1), t1);
E('lock_gen_mod_sqp').value = '50 kV'; ctx.lock_modulation_update();
check('3.6 invalid text: error message', /\?/.test(plain(E('lock_gen_mod_sqp_text').html)));

// ---- 4. blur (end of edit) ---------------------------------------------------------------------------------
sent = [];
E('lock_gen_mod_sqp').value = '50 kHz';
ctx.numberInputBlur(E('lock_gen_mod_sqp'), {});
check('4.1 "50 kHz" + Enter: field 1249, sent lock_gen_mod_sqp = 1249', E('lock_gen_mod_sqp').value === '1249' && sent.length == 1 && sent[0].lock_gen_mod_sqp === 1249,
      E('lock_gen_mod_sqp').value + ' / ' + JSON.stringify(sent.map(s => s.lock_gen_mod_sqp)));
E('lock_gen_mod_phase_sq').value = '90 deg';
ctx.numberInputBlur(E('lock_gen_mod_phase_sq'), {});
check('4.2 phase "90 deg" with P = 2500: field 625, sent 625', E('lock_gen_mod_phase_sq').value === '625' && sent.length == 2 && sent[1].lock_gen_mod_phase_sq === 625,
      E('lock_gen_mod_phase_sq').value);
E('lock_gen_mod_sqp').value = '12 parsecs';
ctx.numberInputBlur(E('lock_gen_mod_sqp'), {});
check('4.3 invalid text: not sent, last value restored', sent.length == 2 && E('lock_gen_mod_sqp').value == '1249', E('lock_gen_mod_sqp').value);
check('4.4 the f/T text follows the restored value', /50\.000 kHz/.test(plain(E('lock_gen_mod_sqp_text').html)));

// ---- 5. lpf_update -----------------------------------------------------------------------------------------
sent = [];
E('lock_lpf_sq_tau').value = '4'; E('lock_lpf_sq_order').value = '1'; E('lock_lpf_sqF_tau').value = '27'; E('lock_lpf_sqF_order').value = '0';
ctx.lpf_update();
const l = sent[0] || {};
check('5.1 lpf_update(): the 4 square filter selects are sent', sent.length == 1 && l.lock_lpf_sq_tau === 4 && l.lock_lpf_sq_order === 1 &&
      l.lock_lpf_sqF_tau === 27 && l.lock_lpf_sqF_order === 0, JSON.stringify(l));

// ---- 6. display ----------------------------------------------------------------------------------------------
E('slow_lock_in_display').cls.add('in');
E('lock_osc_raw_mode').data.checked = true;
Object.assign(ctx.params.local, { lock_sqX: 1000 * 8192, lock_sqY: -1000 * 8192, lock_sqF: 500 * 8192, lock_error_mean: 0, lock_error_std: 0 });
ctx.display_update();
check('6.1 raw mode: sqX 1000, sqY -1000, R 1414.214, phi -45 deg, sqF 500 (counts)',
      E('disp_x').html === '1000.000' && E('disp_y').html === '-1000.000' && E('disp_r').html === '1414.214' &&
      Math.abs(parseFloat(E('disp_fi').html) + 45) < 1e-6 && E('disp_F').html === '500.000',
      [E('disp_x').html, E('disp_y').html, E('disp_r').html, E('disp_fi').html, E('disp_F').html].join(' '));
E('lock_osc_raw_mode').data.checked = false;
ctx.display_update();
check('6.2 volts: sqX = 1000 counts -> 122 mV', /122/.test(E('disp_x').html) && /mV/.test(plain(E('disp_x').html)), plain(E('disp_x').html));

// ---- 7. HTML -------------------------------------------------------------------------------------------------
const ids = ['lock_gen_mod_sqp', 'lock_gen_mod_phase_sq', 'lock_lpf_sq_tau', 'lock_lpf_sq_order', 'lock_lpf_sqF_tau',
             'lock_lpf_sqF_order', 'lock_sg_amp_sq', 'lock_sg_amp_sqF', 'disp_F', 'tab_XY_body', 'tab_F_body'];
const missing = ids.filter(id => !new RegExp('id="' + id + '"').test(html));
check('7.1 square panel elements present', missing.length == 0, missing.join(','));
const old = ['lock_gen_mod_hp', 'lock_lpf_F0', 'lock_sg_amp0', 'lock_mod_harmonic_on', "'lock_X'", 'disp_F1', 'HarmonicParams', 'tab_F0'];
const left = old.filter(k => html.indexOf(k) >= 0);
check('7.2 no harmonic ids left in the page', left.length == 0, left.join(','));
const tau = (html.match(/<select id="lock_lpf_sq_tau"[\s\S]*?<\/select>/) || [''])[0];
check('7.3 filter: 28 time constants, 64 ns .. 9 s, default 8 us (7)', (tau.match(/<option/g) || []).length == 28 &&
      /value="0">\s*64 ns/.test(tau) && /value="27">\s*9\s+s/.test(tau) && /value="7" selected="selected">\s*8 us/.test(tau));
check('7.4 square fields are text inputs (units)', /type="text"[^>]*id="lock_gen_mod_sqp"/.test(html) && /type="text"[^>]*id="lock_gen_mod_phase_sq"/.test(html));
const trig = (html.match(/<select id="lock_trig_sw"[\s\S]*?<\/select>/) || [''])[0];
check('7.5 Ext Trig: "Square mod." = 8, no harmonic entry', /value="8">Square mod\./.test(trig) && !/harmonic/i.test(trig));

console.log(`${n - fails}/${n} ok`);
process.exit(fails ? 1 : 0);
