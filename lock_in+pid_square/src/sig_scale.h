/**
 * @brief lock_in+pid_square: display scale of the signals (v2.0.12, port of lock_in+pid_harmonic 2.3.33 = lock_in+pid
 *        2.2.17 builds 34-36: the final rule of the user, build 35 of lock_in+pid), with the selectors of the square
 *        lock-in of this App (fpga lock.v)
 *
 * What one count of a signal of the FPGA is in volts, for the display only (scope traces, Measure table, scope
 * trigger level in volts; the page also for its mV labels, the lock-in displays and the V / mV typed in the fields).
 * The FPGA always gets the same integers: nothing here changes a register. Raw Mode (lock_osc_raw_mode) does not use
 * this: everything is shown as the plain integers.
 *
 * A signal is shown as  V = (n + c) * fs / 8192,  n the integer of the FPGA, fs the voltage of 8192 counts and c a
 * correction in counts (rp_sig_scale()). The rules (the page uses the same ones, block [CALIB DISPLAY] of index.html):
 *
 *  - in1 / in2 (direct input readings): full scale of that input in its range (gain_ch1 / gain_ch2 = jumper of IN1 /
 *    IN2: 0 LV, 1 HV), times the probe attenuation of that input (prb_att_ch1 / prb_att_ch2), and the ADC offset
 *    correction of that input and range (calib.h). Kind INPUT.
 *  - in1-in2 (the only pure combination of the two inputs; level trigger 14, out_sw 3): the mean of the IN1 and IN2
 *    full scales of the range in use (times the probe attenuation); IN1 and IN2 with different range or probe: the
 *    mean of the LV full scales without probe factor (approximate). c = 0. Kind MEAN.
 *  - lock-in displays of the page (sqX, sqY, R and sqF of the square lock-in; RP_SIG_LOCKIN): the input calibration
 *    of the lock-in input (lock_signal_sw): in1 -> IN1 full scale (range x probe), in2 -> IN2, in1-in2 -> the mean
 *    above; c = 0 (demodulated values). Other sources (sq_ref, sq_quad, sq_phas, aux_A, Ramp A): nominal. Not used
 *    by the controller.
 *  - ctrl_A / ctrl_B: full scale of the DAC (be_chX_fs = FS_DAC / gainCalc) of the output they go to. Routed directly
 *    by out1_sw / out2_sw (12 / 13; first OUT1, then OUT2): that DAC and its offset (c = -be_chX_dc_offs, official
 *    library: n = V*8192/FS + offset), the volts at the connector. Not routed: the DAC where another signal of its
 *    chain is routed (chain A = ctrl_A, Ramp A, PID A out, aux_A; chain B the same with B), else OUT1 for ctrl_A and
 *    OUT2 for ctrl_B, c = 0. Kind OUT.
 *  - out1 / out2 (scope selector 19 / 20 in this App: the integer of the DAC of OUT1 / OUT2, whatever is routed
 *    there): the full scale and the offset of that DAC (c = -be_chX_dc_offs), the volts at the connector. Kind OUT.
 *  - Everything else (error, sqXo, sqYo, sqFo and signal_i traces, PID inputs and set points (also a PID input in1 / in2 /
 *    in1-in2, see the switch below), Ramp A / B, PID A / B out, aux_A / aux_B, the square references sq_ref, sq_quad,
 *    sq_phas routed or not, "0"): the NOMINAL factory conversion, 8192 counts = 1 V, c = 0, the same on every board.
 *    Kind NOM.
 *    Consequence: ctrl = ramp + PID out holds in counts, not exactly in volts (ctrl with the DAC full scale and offset,
 *    ramp and PID out with 1 V / 8192): V(ctrl) = (V(ramp) + V(pid out)) * fs_DAC / 1 V + c * fs_DAC / 8192.
 *
 *  - PID inputs fed directly by in1 / in2 / in1-in2 (lock_pidA_sw / lock_pidB_sw 7 / 8 / 6 in this App): nominal for
 *    now, as lock_in+pid and lock_in+pid_harmonic (lock_in+pid_plus gives them the input calibration). PENDING
 *    DECISION of the user: ONE-LINE SWITCH RP_SIG_PID_IN_CALIB below (0 nominal, 1 input calibration with the ADC
 *    offset, as plus); the page has the same switch (calib_pid_in_calib of [CALIB DISPLAY]): change both
 *    (test/calib_display_sim.js checks that they agree).
 *
 * History (lock_in+pid 2.2.17): build 34 gave the DAC scale to the whole output chain (and the DAC offset to the ramp of a routed ctrl), the
 * references routed the DAC scale, and the internal signals (error, Xo .., signal_i, references not routed) the mean
 * input factor.
 *
 * Header only (static inline): used by main.c (scale_ch1/2), worker.c (traces, Measure, trigger) and the host
 * tests (test/sig_scale_dump.c, compared with the page by test/calib_display_sim.js).
 */
#ifndef __SIG_SCALE_H
#define __SIG_SCALE_H

#include <stdint.h>
#include "calib.h"

/* ONE-LINE SWITCH (pending decision of the user): PID inputs in1 / in2 / in1-in2 with the input calibration (1) or
 * nominal (0, current rule). The page: calib_pid_in_calib of [CALIB DISPLAY] (index.html), the same value. */
#ifndef RP_SIG_PID_IN_CALIB
#define RP_SIG_PID_IN_CALIB 0
#endif

/* signals (not FPGA codes: the selectors map their codes to these) */
enum {
    RP_SIG_ZERO = 0, RP_SIG_IN1, RP_SIG_IN2, RP_SIG_INT,
    RP_SIG_CTRL_A, RP_SIG_RAMP_A, RP_SIG_PIDA_OUT, RP_SIG_AUX_A,
    RP_SIG_CTRL_B, RP_SIG_RAMP_B, RP_SIG_PIDB_OUT, RP_SIG_AUX_B,
    RP_SIG_SQ_REF, RP_SIG_SQ_QUAD, RP_SIG_SQ_PHAS,   /* square references (scope 12 .. 14) */
    RP_SIG_PIDA_IN, RP_SIG_PIDB_IN,
    RP_SIG_OUT1, RP_SIG_OUT2,  /* integer of the DAC of OUT1 / OUT2 (scope selector 19 / 20) */
    RP_SIG_IN1_IN2,            /* in1-in2 */
    RP_SIG_LOCKIN,             /* lock-in displays sqX, sqY, R, sqF (scale of the lock-in input, lock_signal_sw) */
    RP_SIG_N
};

/* kind of scale (rp_sig_scale()) */
#define RP_SIG_KIND_INPUT  0   /* calibration of one input (in1 / in2; lock-in displays of in1 / in2 without offset) */
#define RP_SIG_KIND_MEAN   1   /* mean of the IN1 / IN2 full scales (in1-in2), no offset */
#define RP_SIG_KIND_OUT    2   /* DAC (ctrl_A / ctrl_B, out1 / out2) */
#define RP_SIG_KIND_NOM    3   /* everything else: nominal 8192 counts = 1 V, offset 0 */

/* settings that choose the scale */
typedef struct rp_sig_sel_s {
    int gain1, gain2;          /* gain_ch1 / gain_ch2: 0 LV, 1 HV */
    int att1, att2;            /* prb_att_ch1 / prb_att_ch2: 0 x1, 1 x10 */
    int out1_sw, out2_sw;      /* lock_out1_sw / lock_out2_sw */
    int pidA_sw, pidB_sw;      /* lock_pidA_sw / lock_pidB_sw */
    int signal_sw;             /* lock_signal_sw: input of the lock-in (0 in1, 1 in2, 2 in1-in2, 3.. sq_ref, ..) */
} rp_sig_sel_t;

/* voltage of a full scale field (old units: V * 2^32 / 100) */
static inline double rp_sig_fs_v(uint32_t fs)
{
    return fs / 4294967296.0 * 100.0;
}

/* scope selector (lock_oscA_sw / lock_oscB_sw; fpga lock.v i_muxer5_scope1/2) -> signal */
static inline int rp_sig_of_osc_sw(int sw)
{
    static const int t[] = {
        RP_SIG_ZERO, RP_SIG_IN1, RP_SIG_IN2, RP_SIG_INT /* error */,
        RP_SIG_CTRL_A, RP_SIG_CTRL_B, RP_SIG_RAMP_A, RP_SIG_RAMP_B, RP_SIG_PIDA_IN, RP_SIG_PIDB_IN,
        RP_SIG_PIDA_OUT, RP_SIG_PIDB_OUT, RP_SIG_SQ_REF, RP_SIG_SQ_QUAD, RP_SIG_SQ_PHAS,
        RP_SIG_INT, RP_SIG_INT, RP_SIG_INT /* 15..17 sqXo, sqYo, sqFo */, RP_SIG_INT /* 18 signal_i */,
        RP_SIG_OUT1, RP_SIG_OUT2,
        RP_SIG_ZERO, RP_SIG_ZERO, RP_SIG_ZERO, RP_SIG_ZERO, RP_SIG_ZERO, RP_SIG_ZERO, RP_SIG_ZERO, RP_SIG_ZERO,
        RP_SIG_ZERO, RP_SIG_ZERO, RP_SIG_ZERO /* 21..31 0 */ };
    if(sw >= 0 && sw < (int)(sizeof(t) / sizeof(t[0])))
        return t[sw];
    return RP_SIG_INT;
}

/* PID input selector (lock_pidA_sw / lock_pidB_sw; lock.v pidA / pidB muxers) -> signal. The PID inputs are nominal
 * (rule of the top); in1, in2 and in1-in2 (7, 8, 6) by the switch RP_SIG_PID_IN_CALIB (0: nominal, as lock_in+pid and
 * lock_in+pid_harmonic) */
static inline int rp_sig_of_pid_sw(int sw)
{
    switch(sw) {
    case 5:  return RP_SIG_RAMP_A;
    case 6:  return RP_SIG_PID_IN_CALIB ? RP_SIG_IN1_IN2 : RP_SIG_INT;
    case 7:  return RP_SIG_PID_IN_CALIB ? RP_SIG_IN1 : RP_SIG_INT;
    case 8:  return RP_SIG_PID_IN_CALIB ? RP_SIG_IN2 : RP_SIG_INT;
    case 9:  return RP_SIG_AUX_A;
    case 10: return RP_SIG_AUX_B;
    case 11: return RP_SIG_SQ_REF;
    case 12: return RP_SIG_SQ_QUAD;
    case 13: return RP_SIG_SQ_PHAS;
    case 14: case 15: return RP_SIG_ZERO;
    default: return RP_SIG_INT;   /* 0 error, 1..3 sqXo, sqYo, sqFo, 4 signal_i */
    }
}

/* output selector (lock_out1_sw: dac 1, lock_out2_sw: dac 2; lock.v out1_sw_m / out2_sw_m, the same list for both)
 * -> signal that is the integer of the DAC */
static inline int rp_sig_of_out_sw(int dac, int sw)
{
    (void)dac;
    switch(sw) {
    case 0:  return RP_SIG_ZERO;
    case 1:  return RP_SIG_IN1;
    case 2:  return RP_SIG_IN2;
    case 3:  return RP_SIG_IN1_IN2;
    case 5:  return RP_SIG_SQ_REF;
    case 6:  return RP_SIG_SQ_QUAD;
    case 7:  return RP_SIG_SQ_PHAS;
    case 10: return RP_SIG_PIDA_OUT;
    case 11: return RP_SIG_PIDB_OUT;
    case 12: return RP_SIG_CTRL_A;
    case 13: return RP_SIG_CTRL_B;
    case 14: return RP_SIG_AUX_A;
    case 15: return RP_SIG_AUX_B;
    default: return RP_SIG_INT;   /* 4 error, 8 sqXo, 9 sqYo */
    }
}

/* output chain of a signal: 1 (A), 2 (B), 0 none */
static inline int rp_sig_chain(int sig)
{
    if(sig >= RP_SIG_CTRL_A && sig <= RP_SIG_AUX_A) return 1;
    if(sig >= RP_SIG_CTRL_B && sig <= RP_SIG_AUX_B) return 2;
    return 0;
}

/* lock-in input selector (lock_signal_sw) -> signal (only in1, in2, in1-in2 matter: the others are nominal) */
static inline int rp_sig_of_signal_sw(int sw)
{
    switch(sw) {
    case 0:  return RP_SIG_IN1;
    case 1:  return RP_SIG_IN2;
    case 2:  return RP_SIG_IN1_IN2;
    default: return RP_SIG_INT;   /* 3 sq_ref, 4 sq_quad, 5 sq_phas, 6 aux_A, 7 Ramp A */
    }
}

/* full scale [V] of input 1 / 2 in LV (hv = 0) or HV */
static inline double rp_sig_in_fs(const rp_calib_params_t *c, int input, int hv)
{
    if(input == 1)
        return rp_sig_fs_v(hv ? c->fe_ch1_fs_g_lo : c->fe_ch1_fs_g_hi);
    return rp_sig_fs_v(hv ? c->fe_ch2_fs_g_lo : c->fe_ch2_fs_g_hi);
}

/* mean input full scale (in1-in2, see the top) */
static inline double rp_sig_in_common_fs(const rp_calib_params_t *c, const rp_sig_sel_t *s)
{
    int hv1 = (s->gain1 != 0), hv2 = (s->gain2 != 0), a1 = (s->att1 > 0), a2 = (s->att2 > 0);
    if(hv1 == hv2 && a1 == a2)
        return (rp_sig_in_fs(c, 1, hv1) + rp_sig_in_fs(c, 2, hv1)) / 2.0 * (a1 ? 10.0 : 1.0);
    return (rp_sig_in_fs(c, 1, 0) + rp_sig_in_fs(c, 2, 0)) / 2.0;
}

/* scale of a signal: *fs_v voltage of 8192 counts, *offs correction in counts (V = (n + offs) * fs_v / 8192),
 * returns the kind (RP_SIG_KIND_*) */
static inline int rp_sig_scale(const rp_calib_params_t *c, const rp_sig_sel_t *s, int sig, double *fs_v, int32_t *offs)
{
    int d, lockin = 0;
    if(sig == RP_SIG_PIDA_IN) sig = rp_sig_of_pid_sw(s->pidA_sw);   /* (all nominal unless RP_SIG_PID_IN_CALIB) */
    if(sig == RP_SIG_PIDB_IN) sig = rp_sig_of_pid_sw(s->pidB_sw);
    if(sig == RP_SIG_LOCKIN) { sig = rp_sig_of_signal_sw(s->signal_sw); lockin = 1; }

    if(sig == RP_SIG_IN1 || sig == RP_SIG_IN2) {
        int in = (sig == RP_SIG_IN1) ? 1 : 2;
        int hv = ((in == 1 ? s->gain1 : s->gain2) != 0);
        int att = ((in == 1 ? s->att1 : s->att2) > 0);
        *fs_v = rp_sig_in_fs(c, in, hv) * (att ? 10.0 : 1.0);
        *offs = lockin ? 0 : rp_calib_adc_offs(c, in, hv);   /* demodulated values: no offset */
        return RP_SIG_KIND_INPUT;
    }
    if(sig == RP_SIG_IN1_IN2) {
        *fs_v = rp_sig_in_common_fs(c, s);
        *offs = 0;
        return RP_SIG_KIND_MEAN;
    }
    if(sig == RP_SIG_OUT1 || sig == RP_SIG_OUT2) {   /* the DAC of that output, with its offset */
        d = (sig == RP_SIG_OUT2);
        *fs_v = rp_sig_fs_v(d ? c->be_ch2_fs : c->be_ch1_fs);
        *offs = -(d ? c->be_ch2_dc_offs : c->be_ch1_dc_offs);
        return RP_SIG_KIND_OUT;
    }
    if(sig == RP_SIG_CTRL_A || sig == RP_SIG_CTRL_B) {
        int direct[2], dac;
        direct[0] = rp_sig_of_out_sw(1, s->out1_sw);
        direct[1] = rp_sig_of_out_sw(2, s->out2_sw);
        for(d = 0; d < 2; d++) {
            if(direct[d] == sig) {     /* routed: that DAC, with its offset */
                *fs_v = rp_sig_fs_v(d ? c->be_ch2_fs : c->be_ch1_fs);
                *offs = -(d ? c->be_ch2_dc_offs : c->be_ch1_dc_offs);
                return RP_SIG_KIND_OUT;
            }
        }
        dac = rp_sig_chain(sig) - 1;    /* default: ctrl_A -> OUT1, ctrl_B -> OUT2 */
        for(d = 0; d < 2; d++)
            if(rp_sig_chain(direct[d]) == rp_sig_chain(sig)) { dac = d; break; }
        *fs_v = rp_sig_fs_v(dac ? c->be_ch2_fs : c->be_ch1_fs);
        *offs = 0;
        return RP_SIG_KIND_OUT;
    }
    *fs_v = 1.0;    /* everything else: nominal 8192 counts = 1 V (build 35) */
    *offs = 0;
    return RP_SIG_KIND_NOM;
}

#ifdef LOCK_OSCA_SW
/* settings of a parameter table of the controller (main.h) */
static inline void rp_sig_sel_of_params(rp_sig_sel_t *s, const rp_app_params_t *p)
{
    s->gain1   = (int)p[GAIN_CH1].value;
    s->gain2   = (int)p[GAIN_CH2].value;
    s->att1    = (int)p[PRB_ATT_CH1].value;
    s->att2    = (int)p[PRB_ATT_CH2].value;
    s->out1_sw = (int)p[LOCK_OUT1_SW].value;
    s->out2_sw = (int)p[LOCK_OUT2_SW].value;
    s->pidA_sw = (int)p[LOCK_PIDA_SW].value;
    s->pidB_sw = (int)p[LOCK_PIDB_SW].value;
    s->signal_sw = (int)p[LOCK_SIGNAL_SW].value;
}

/* scale of the signal shown on scope channel A (ch 0) or B (ch 1) */
static inline int rp_sig_osc_scale(const rp_calib_params_t *c, const rp_app_params_t *p, int ch,
                                   float *fs_v, int32_t *offs)
{
    rp_sig_sel_t s;
    double fs = 1;
    int32_t o = 0;
    int k;
    rp_sig_sel_of_params(&s, p);
    k = rp_sig_scale(c, &s, rp_sig_of_osc_sw((int)p[ch ? LOCK_OSCB_SW : LOCK_OSCA_SW].value), &fs, &o);
    if(fs_v) *fs_v = (float)fs;
    if(offs) *offs = o;
    return k;
}
#endif

#endif /* __SIG_SCALE_H */
