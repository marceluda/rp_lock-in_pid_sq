/*
 * v2.0.12 (port of lock_in+pid_harmonic 2.3.33 = lock_in+pid 2.2.17): table of the display scales of src/sig_scale.h (what the controller uses for the scope traces,
 * Measure and trigger), for test/calib_display_sim.js, which compares it with the [CALIB DISPLAY] block of the page.
 *
 *   gcc -Wall -Werror -Isrc -o /tmp/sig_scale_dump test/sig_scale_dump.c src/calib.c -lm && /tmp/sig_scale_dump
 *
 * One line per case: "set osc_sw gain1 gain2 att1 att2 out1_sw out2_sw pidA_sw pidB_sw  fs offs kind  signal_sw pid_in_calib"
 * (pid_in_calib = RP_SIG_PID_IN_CALIB; the sim also builds this with -DRP_SIG_PID_IN_CALIB=1, the other position);
 * osc_sw 0..24 = scope selector (19 / 20 out1 / out2, 21..24 0), 25 = the lock-in displays (RP_SIG_LOCKIN), 26 = in1-in2; set 0 = Gen1 RP2
 * (format 1), set 1 = Gen2 Pro v2.0 (format 6), the values of test/calib_test.c. The cases are a fixed pseudo-random
 * walk (same in the sim, which only reads this output). kind: 0 input, 1 mean input, 2 DAC (ctrl_A / ctrl_B, out1 /
 * out2), 3 nominal (everything else, build 35 of lock_in+pid).
 */
#include <stdio.h>
#include <string.h>
#include "sig_scale.h"

/* volts -> old units (V * 2^32 / 100) */
static uint32_t fs_of(double v) { return (uint32_t)(v / 100.0 * 4294967296.0 + 0.5); }

static void calib_set(rp_calib_params_t *c, int set)
{
    memset(c, 0, sizeof(*c));
    if(set == 0) {     /* RP2, Gen1, format 1: LV 1 / 1 V, HV 20 / 20 V, LV corrections +210 / -20, DAC 1.0489 V */
        c->fe_ch1_fs_g_hi = fs_of(1.0);      c->fe_ch2_fs_g_hi = fs_of(1.0);
        c->fe_ch1_fs_g_lo = fs_of(20.0);     c->fe_ch2_fs_g_lo = fs_of(20.0);
        c->fe_ch1_dc_offs_lv = 210;          c->fe_ch2_dc_offs_lv = -20;
        c->fe_ch1_dc_offs = 0;               c->fe_ch2_dc_offs = 0;
        c->be_ch1_fs = fs_of(1.0489);        c->be_ch2_fs = fs_of(1.0489);
        c->be_ch1_dc_offs = 0;               c->be_ch2_dc_offs = 0;
    } else {           /* Gen2 Pro v2.0, format 6 */
        c->fe_ch1_fs_g_hi = fs_of(1.14665);  c->fe_ch2_fs_g_hi = fs_of(1.14637);
        c->fe_ch1_fs_g_lo = fs_of(28.9156);  c->fe_ch2_fs_g_lo = fs_of(28.9116);
        c->fe_ch1_dc_offs_lv = 0;            c->fe_ch2_dc_offs_lv = 6;
        c->fe_ch1_dc_offs = -1;              c->fe_ch2_dc_offs = 5;
        c->be_ch1_fs = fs_of(2.3210);        c->be_ch2_fs = fs_of(2.3234);
        c->be_ch1_dc_offs = 290;             c->be_ch2_dc_offs = 301;
    }
}

int main(void)
{
    unsigned int seed = 12345;
    int set, i;
#define RND(n) ((seed = seed * 1103515245u + 12345u), (int)((seed >> 16) % (unsigned)(n)))
    for(set = 0; set < 2; set++) {
        rp_calib_params_t c;
        calib_set(&c, set);
        for(i = 0; i < 400; i++) {
            rp_sig_sel_t s;
            double fs;
            int32_t offs;
            int osc = RND(27), k, sig;
            s.gain1 = RND(2); s.gain2 = RND(2); s.att1 = RND(2); s.att2 = RND(2);
            s.out1_sw = RND(16); s.out2_sw = RND(16); s.pidA_sw = RND(16); s.pidB_sw = RND(16); s.signal_sw = RND(9);
            if(i % 4 == 0) { s.gain2 = s.gain1; s.att2 = s.att1; }   /* same settings more often */
            sig = (osc == 25) ? RP_SIG_LOCKIN : (osc == 26) ? RP_SIG_IN1_IN2 : rp_sig_of_osc_sw(osc);
            k = rp_sig_scale(&c, &s, sig, &fs, &offs);
            printf("%d %d %d %d %d %d %d %d %d %d %.7f %d %d %d %d\n", set, osc, s.gain1, s.gain2, s.att1, s.att2,
                   s.out1_sw, s.out2_sw, s.pidA_sw, s.pidB_sw, fs, (int)offs, k, s.signal_sw, RP_SIG_PID_IN_CALIB);
        }
    }
    return 0;
}
