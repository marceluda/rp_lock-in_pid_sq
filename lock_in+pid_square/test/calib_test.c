/*
 * v2.2.17: host test of the calibration reader of src/calib.c (formats 1 / 5 / 6 of the EEPROM, sanity check, factory
 * zone and nominal fall-backs), on EEPROM images built from real dumps:
 *
 *  - Gen2: STEMlab 125-14 Pro v2.0, OS 2.07-48, format 6 in both zones (save_lolo/reportes_externos/rp_diag_PID_app.txt,
 *    od of 0x0000 and 0x1c00; calib -ru: gainCalc 1.14665 / 1.14637 LV, 1.44578 / 1.44558 HV, DAC 0.8617 / 0.8608).
 *    The U-Boot environment was not dumped: a synthetic one with its hw_rev (STEM_125-14_Pro_v2.0).
 *  - RP2: STEMlab 125-14 v1.0 (Gen1), OS 2.04-35, format 1 with magic in the user zone, old layout without magic in the
 *    factory zone (test_logs/gen2_diag_RP2_20261125_1040.log).
 *  - garbage, erased and corrupt images: nominal values (or the factory zone) and the flag.
 *
 * It also checks, linked with the real src/fpga.c, that the scope conversion with the decoded values
 * (osc_fpga_cnv_cnt_to_v(): counts + correction, * full scale / 8192) gives the voltage of the official library
 * (convert.hpp: (raw - offset) * gainCalc * 1 V / 8192 * (1 | 20)).
 *
 *   gcc -Wall -Werror -Isrc -o /tmp/calib_test test/calib_test.c src/calib.c src/fpga.c -lm && /tmp/calib_test [dir]
 *   (from the App folder; the images are written to dir, default /tmp; exit code 1 on failure)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "calib.h"
#include "fpga.h"

#define EE_SIZE 8192

static int fails = 0, checks = 0;
static char dir[512] = "/tmp";

#define CHECK(cond, ...) do { checks++; if(!(cond)) { fails++; printf("  FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while(0)

static double fs_v(uint32_t fs) { return fs / 4294967296.0 * 100.0; }

/* od -A x -t x1z lines ("001c10 38 01 93 3c ...  >...<") into the image */
static void put_od(unsigned char *img, const char *const *lines)
{
    for(; *lines; lines++) {
        const char *s = *lines;
        char *e;
        long addr = strtol(s, &e, 16);
        int k;
        for(k = 0; k < 16; k++) {
            long v = strtol(e, &e, 16);
            img[addr + k] = (unsigned char)v;
        }
    }
}

static void put_env(unsigned char *img, const char *hw_rev)
{
    char env[256];
    int n = snprintf(env, sizeof(env), "baudrate=115200%chw_rev=%s%cethaddr=00:26:32:f0:00:00%c%c", 0, hw_rev, 0, 0, 0);
    memset(&img[0x1800], 0, 4);                           /* CRC (not checked) */
    memcpy(&img[0x1804], env, n);
}

static const char *write_img(const unsigned char *img, size_t len, const char *name)
{
    static char path[600];
    FILE *fp;
    snprintf(path, sizeof(path), "%s/calib_test_%s.bin", dir, name);
    fp = fopen(path, "wb");
    if(!fp || fwrite(img, 1, len, fp) != len) {
        printf("  can not write %s\n", path);
        exit(2);
    }
    fclose(fp);
    return path;
}

/* --- Gen2 Pro v2.0 (rp_diag_PID_app.txt), user zone 0x0000 and factory zone 0x1c00 (identical) --- */
static const char *const gen2_user[] = {
    "000000 06 0d 1c 00 01 00 00 00 01 00 93 4b 23 00 02 00",
    "000010 22 01 00 00 03 00 23 42 23 00 04 00 2d 01 00 00",
    "000020 09 00 7e f7 2e 00 0a 00 00 00 00 00 0b 00 8e f4",
    "000030 2e 00 0c 00 fa ff ff ff 11 00 19 38 3b 00 12 00",
    "000040 01 00 00 00 13 00 00 36 3b 00 14 00 fb ff ff ff",
    "000050 21 00 00 00 00 00 22 00 00 00 00 00 23 00 00 00",
    "000060 00 00 24 00 ff ff ff 00 25 00 00 00 00 00 26 00",
    "000070 00 00 00 00 27 00 00 00 00 00 28 00 ff ff ff 00",
    "000080 31 00 00 00 00 00 32 00 00 00 00 00 33 00 00 00",
    "000090 00 00 34 00 ff ff ff 00 35 00 00 00 00 00 36 00",
    "0000a0 00 00 00 00 37 00 00 00 00 00 38 00 ff ff ff 00",
    NULL };
static const char *const gen2_factory[] = {
    "001c00 06 0d 1c 00 01 00 00 00 01 00 93 4b 23 00 02 00",
    "001c10 22 01 00 00 03 00 23 42 23 00 04 00 2d 01 00 00",
    "001c20 09 00 7e f7 2e 00 0a 00 00 00 00 00 0b 00 8e f4",
    "001c30 2e 00 0c 00 fa ff ff ff 11 00 19 38 3b 00 12 00",
    "001c40 01 00 00 00 13 00 00 36 3b 00 14 00 fb ff ff ff",
    "001c50 21 00 00 00 00 00 22 00 00 00 00 00 23 00 00 00",
    "001c60 00 00 24 00 ff ff ff 00 25 00 00 00 00 00 26 00",
    "001c70 00 00 00 00 27 00 00 00 00 00 28 00 ff ff ff 00",
    "001c80 31 00 00 00 00 00 32 00 00 00 00 00 33 00 00 00",
    "001c90 00 00 34 00 ff ff ff 00 35 00 00 00 00 00 36 00",
    "001ca0 00 00 00 00 37 00 00 00 00 00 38 00 ff ff ff 00",
    NULL };

/* --- RP2 (Gen1 v1.0, OS 2.04-35), gen2_diag_RP2_20261125_1040.log --- */
static const char *const rp2_user[] = {
    "000000 01 01 00 00 00 00 00 00 28 5c 8f 02 28 5c 8f 02",
    "000010 33 33 33 33 33 33 33 33 00 00 00 00 00 00 00 00",
    "000020 48 67 af 02 48 67 af 02 00 00 00 00 00 00 00 00",
    "000030 dd cc bb aa 2e ff ff ff 14 00 00 00 93 7d 00 00",
    "000040 c7 37 04 00 66 26 00 00 9a 99 d9 00 93 7d 00 00",
    "000050 c7 37 04 00 66 26 00 00 9a 99 d9 00 05 42 00 00",
    "000060 8b f3 02 00 66 26 00 00 9a 99 d9 00 05 42 00 00",
    "000070 8b f3 02 00 66 26 00 00 9a 99 d9 00 ff ff ff ff",
    NULL };
static const char *const rp2_factory[] = {
    "001c00 01 00 00 00 00 00 00 00 d7 ed bb 02 d7 ed bb 02",
    "001c10 38 01 93 3c 38 01 93 3c 4e 00 00 00 19 00 00 00",
    "001c20 03 65 8c 02 03 65 8c 02 6a ff ff ff 6a ff ff ff",
    NULL };

static void build(unsigned char *img, const char *const *user, const char *const *factory, const char *hw_rev)
{
    memset(img, 0xff, EE_SIZE);
    if(user)    put_od(img, user);
    if(factory) put_od(img, factory);
    if(hw_rev)  put_env(img, hw_rev);
}

static int near(double a, double b, double tol) { return fabs(a - b) <= tol; }

static void print_p(const rp_calib_params_t *p)
{
    printf("    source %d format %d gen2 %d hw_rev '%s': LV %.5f/%.5f V corr %d/%d, HV %.4f/%.4f V corr %d/%d, "
           "OUT %.4f/%.4f V offs %d/%d\n", p->source, p->format, p->gen2, p->hw_rev,
           fs_v(p->fe_ch1_fs_g_hi), fs_v(p->fe_ch2_fs_g_hi), p->fe_ch1_dc_offs_lv, p->fe_ch2_dc_offs_lv,
           fs_v(p->fe_ch1_fs_g_lo), fs_v(p->fe_ch2_fs_g_lo), p->fe_ch1_dc_offs, p->fe_ch2_dc_offs,
           fs_v(p->be_ch1_fs), fs_v(p->be_ch2_fs), p->be_ch1_dc_offs, p->be_ch2_dc_offs);
}

/* the official conversion (convert.hpp + acq_handler.cpp) vs the one of the App (fpga.c) with the decoded values */
static void check_conversion(const rp_calib_params_t *p, const double gain[4], const int offs[4], const char *what)
{
    int ch, hv, raw, n = 0, clipped = 0;
    double maxd = 0;
    for(ch = 0; ch < 2; ch++)
        for(hv = 0; hv < 2; hv++) {
            uint32_t fs = hv ? (ch ? p->fe_ch2_fs_g_lo : p->fe_ch1_fs_g_lo) : (ch ? p->fe_ch2_fs_g_hi : p->fe_ch1_fs_g_hi);
            float max_v = osc_fpga_calc_adc_max_v(fs, 0);
            int corr = rp_calib_adc_offs(p, ch + 1, hv);
            for(raw = -8000; raw <= 8000; raw += 7) {
                double off = offs[hv * 2 + ch];
                if(raw + corr > 8192 || raw + corr < -8192) {
                    clipped++;              /* the App saturates the corrected counts at +-8192 (fpga.c) */
                    continue;
                }
                n++;
                double v_off = (raw - off) * gain[hv * 2 + ch] * 1.0 / 8192.0 * (hv ? 20 : 1);
                double v_app = osc_fpga_cnv_cnt_to_v(raw, max_v, corr, 0);
                double d = fabs(v_off - v_app) / (hv ? 20 : 1);
                if(d > maxd) maxd = d;
            }
        }
    CHECK(maxd < 2e-6, "%s: scope conversion differs from the official one by %g V (per V of range)", what, maxd);
    printf("    %s: scope volts = official volts (max difference %.2g V per volt of range, %d counts in 4 ranges; "
           "%d beyond +-8192 with the correction, saturated by the App)\n", what, maxd, n, clipped);
}

int main(int argc, char **argv)
{
    static unsigned char img[EE_SIZE];
    rp_calib_params_t p;
    const char *path;
    int ret;

    if(argc > 1)
        snprintf(dir, sizeof(dir), "%s", argv[1]);

    printf("1. Gen2 Pro v2.0, format 6 (user zone):\n");
    build(img, gen2_user, gen2_factory, "STEM_125-14_Pro_v2.0");
    path = write_img(img, EE_SIZE, "gen2");
    ret = rp_read_calib_params_file(path, &p);
    print_p(&p);
    CHECK(ret == 0 && p.source == RP_CALIB_SRC_USER && p.format == 6 && p.gen2 == 1, "Gen2: source/format/gen2");
    CHECK(strcmp(p.hw_rev, "STEM_125-14_Pro_v2.0") == 0, "Gen2: hw_rev '%s'", p.hw_rev);
    CHECK(near(fs_v(p.fe_ch1_fs_g_hi), 1.14665, 5e-5) && near(fs_v(p.fe_ch2_fs_g_hi), 1.14637, 5e-5), "Gen2 LV FS");
    CHECK(near(fs_v(p.fe_ch1_fs_g_lo), 28.9156, 5e-4) && near(fs_v(p.fe_ch2_fs_g_lo), 28.9116, 5e-4), "Gen2 HV FS");
    CHECK(p.fe_ch1_fs_g_hi == 16u * 3078014 && p.fe_ch2_fs_g_lo == 320u * 3880448, "Gen2: 16 / 320 x calibValue");
    /* official offsets LV 0 / -6, HV 1 / -5 (subtracted) -> corrections 0 / +6, -1 / +5 (added) */
    CHECK(p.fe_ch1_dc_offs_lv == 0 && p.fe_ch2_dc_offs_lv == 6, "Gen2 LV offset corrections %d/%d",
          p.fe_ch1_dc_offs_lv, p.fe_ch2_dc_offs_lv);
    CHECK(p.fe_ch1_dc_offs == -1 && p.fe_ch2_dc_offs == 5, "Gen2 HV offset corrections %d/%d",
          p.fe_ch1_dc_offs, p.fe_ch2_dc_offs);
    CHECK(near(fs_v(p.be_ch1_fs), 2.0 / 0.8617, 1e-3) && near(fs_v(p.be_ch2_fs), 2.0 / 0.8608, 1e-3), "Gen2 DAC FS");
    CHECK(p.be_ch1_dc_offs == 290 && p.be_ch2_dc_offs == 301, "Gen2 DAC offsets");
    {
        const double g[4] = { 3078014 / 2684354.56, 3077262 / 2684354.56, 3880985 / 2684354.56, 3880448 / 2684354.56 };
        const int    o[4] = { 0, -6, 1, -5 };
        float v;
        check_conversion(&p, g, o, "Gen2");
        v = osc_fpga_cnv_cnt_to_v(3570, osc_fpga_calc_adc_max_v(p.fe_ch1_fs_g_hi, 0), rp_calib_adc_offs(&p, 1, 0), 0);
        CHECK(near(v, 0.4997, 2e-4), "Gen2: 3570 counts on IN1 LV = %.4f V", v);
        printf("    IN1 LV 3570 counts -> %.4f V (gen2_resultados.md: ~3570 counts at +0.5 V)\n", v);
    }

    printf("2. Gen2, user zone erased (0xff): factory zone:\n");
    build(img, NULL, gen2_factory, "STEM_125-14_Pro_v2.0");
    path = write_img(img, EE_SIZE, "gen2_factory");
    ret = rp_read_calib_params_file(path, &p);
    print_p(&p);
    CHECK(ret == 0 && p.source == RP_CALIB_SRC_FACTORY && p.format == 6, "Gen2 factory: source/format");
    CHECK(near(fs_v(p.fe_ch1_fs_g_hi), 1.14665, 5e-5) && p.fe_ch2_dc_offs == 5 && p.be_ch2_dc_offs == 301,
          "Gen2 factory: values");

    printf("3. Gen2 calibration with a Gen1 hw_rev (DAC 1 V):\n");
    build(img, gen2_user, gen2_factory, "STEM_125-14_v1.1");
    path = write_img(img, EE_SIZE, "gen2_hwrev_v1");
    ret = rp_read_calib_params_file(path, &p);
    print_p(&p);
    CHECK(ret == 0 && p.gen2 == 0 && near(fs_v(p.be_ch1_fs), 1.0 / 0.8617, 1e-3), "DAC FS follows hw_rev");

    printf("4. RP2 (Gen1 v1.0), format 1 with magic (user zone):\n");
    build(img, rp2_user, rp2_factory, "STEM_125-14_v1.0");
    path = write_img(img, EE_SIZE, "rp2");
    ret = rp_read_calib_params_file(path, &p);
    print_p(&p);
    CHECK(ret == 0 && p.source == RP_CALIB_SRC_USER && p.format == 1 && p.gen2 == 0, "RP2: source/format/gen2");
    CHECK(p.fe_ch1_fs_g_hi == 42949672 && p.fe_ch2_fs_g_hi == 42949672, "RP2 LV FS (as before)");
    CHECK(p.fe_ch1_fs_g_lo == 858993459 && p.fe_ch2_fs_g_lo == 858993459, "RP2 HV FS (as before)");
    CHECK(p.be_ch1_fs == 45049672 && p.be_ch2_fs == 45049672, "RP2 DAC FS (as before) %u", p.be_ch1_fs);
    CHECK(p.be_ch1_dc_offs == 0 && p.be_ch2_dc_offs == 0, "RP2 DAC offsets (as before)");
    CHECK(p.fe_ch1_dc_offs == 0 && p.fe_ch2_dc_offs == 0, "RP2 HV corrections (lo_offs 0 / 0)");
    /* CHANGED: LV offset from hi_offs (0x34 / 0x38: -210 / 20), subtracted -> corrections +210 / -20 (before: 0 / 0) */
    CHECK(p.fe_ch1_dc_offs_lv == 210 && p.fe_ch2_dc_offs_lv == -20, "RP2 LV corrections %d/%d",
          p.fe_ch1_dc_offs_lv, p.fe_ch2_dc_offs_lv);
    {
        /* what 2.2.16 read: 40 bytes at 0x0008 (fields added as they are, the HV offset also in LV) */
        int32_t old[10];
        memcpy(old, &img[8], sizeof(old));
        printf("    2.2.16 read: LV %.4f/%.4f V, HV %.3f/%.3f V, offset (added, LV and HV) %d/%d, OUT %.4f/%.4f V "
               "offs %d/%d\n", fs_v(old[0]), fs_v(old[1]), fs_v(old[2]), fs_v(old[3]), old[4], old[5],
               fs_v(old[6]), fs_v(old[7]), old[8], old[9]);
        CHECK((uint32_t)old[0] == p.fe_ch1_fs_g_hi && (uint32_t)old[2] == p.fe_ch1_fs_g_lo &&
              (uint32_t)old[6] == p.be_ch1_fs && old[4] == p.fe_ch1_dc_offs, "RP2: unchanged fields");
        printf("    changes vs 2.2.16: IN1 LV %+d counts (%+.2f mV), IN2 LV %+d counts (%+.2f mV); HV, full scales "
               "and DAC unchanged\n", p.fe_ch1_dc_offs_lv - old[4], (p.fe_ch1_dc_offs_lv - old[4]) / 8.192,
               p.fe_ch2_dc_offs_lv - old[5], (p.fe_ch2_dc_offs_lv - old[5]) / 8.192);
    }
    {
        const double g[4] = { 1, 1, 1, 1 };
        const int    o[4] = { -210, 20, 0, 0 };
        check_conversion(&p, g, o, "RP2");
    }

    printf("5. RP2, user zone erased: factory zone (old layout without magic, one offset for LV and HV):\n");
    build(img, NULL, rp2_factory, "STEM_125-14_v1.0");
    path = write_img(img, EE_SIZE, "rp2_factory");
    ret = rp_read_calib_params_file(path, &p);
    print_p(&p);
    CHECK(ret == 0 && p.source == RP_CALIB_SRC_FACTORY && p.format == 1, "RP2 factory: source");
    CHECK(p.fe_ch1_fs_g_hi == 45870551 && p.fe_ch1_fs_g_lo == 1016267064 && p.be_ch1_fs == 42755331,
          "RP2 factory: full scales");
    CHECK(p.fe_ch1_dc_offs == -78 && p.fe_ch2_dc_offs == -25 && p.fe_ch1_dc_offs_lv == -78 &&
          p.fe_ch2_dc_offs_lv == -25 && p.be_ch1_dc_offs == -150, "RP2 factory: offsets");

    printf("6. Garbage / erased / corrupt images: nominal values + flag:\n");
    {
        int i;
        srand(12345);
        for(i = 0; i < EE_SIZE; i++)
            img[i] = rand() & 0xff;
        path = write_img(img, EE_SIZE, "random");
        ret = rp_read_calib_params_file(path, &p);
        print_p(&p);
        CHECK(ret == -1 && p.source == RP_CALIB_SRC_NOMINAL && p.format == -1, "random: nominal");
        CHECK(p.fe_ch1_fs_g_hi == 42949672 && p.fe_ch2_fs_g_lo == 858993459 && p.fe_ch1_dc_offs == 0 &&
              p.fe_ch2_dc_offs_lv == 0 && p.be_ch1_fs == 42949672 && p.be_ch1_dc_offs == 0, "random: nominal values");

        memset(img, 0x00, EE_SIZE);
        path = write_img(img, EE_SIZE, "zeros");
        ret = rp_read_calib_params_file(path, &p);
        CHECK(ret == -1 && p.source == RP_CALIB_SRC_NOMINAL, "zeros: nominal");

        build(img, NULL, NULL, "STEM_125-14_v2.0");
        path = write_img(img, EE_SIZE, "erased_gen2");
        ret = rp_read_calib_params_file(path, &p);
        print_p(&p);
        CHECK(ret == -1 && p.source == RP_CALIB_SRC_NOMINAL && p.gen2 == 1 && near(fs_v(p.be_ch1_fs), 2.0, 1e-6),
              "erased Gen2: nominal, DAC 2 V");

        /* 2.2.16 garbage: the Gen2 image read as v1 (both zones) must not pass the sanity check */
        build(img, gen2_user, gen2_factory, "STEM_125-14_Pro_v2.0");
        img[0] = 1; img[0x1c00] = 1;
        path = write_img(img, EE_SIZE, "gen2_as_v1");
        ret = rp_read_calib_params_file(path, &p);
        CHECK(ret == -1 && p.source == RP_CALIB_SRC_NOMINAL, "Gen2 image read as format 1: nominal");

        /* universal: count too big / gain missing / offset out of range -> factory zone */
        build(img, gen2_user, gen2_factory, "STEM_125-14_Pro_v2.0");
        img[2] = 0xff; img[3] = 0xff;
        path = write_img(img, EE_SIZE, "uni_count");
        ret = rp_read_calib_params_file(path, &p);
        CHECK(ret == 0 && p.source == RP_CALIB_SRC_FACTORY, "count 65535: factory zone");

        build(img, gen2_user, gen2_factory, "STEM_125-14_Pro_v2.0");
        img[0x20] = 0x63;                                 /* id 9 -> 99: LV gain of IN1 missing */
        path = write_img(img, EE_SIZE, "uni_missing");
        ret = rp_read_calib_params_file(path, &p);
        CHECK(ret == 0 && p.source == RP_CALIB_SRC_FACTORY, "missing gain: factory zone");

        build(img, gen2_user, gen2_factory, "STEM_125-14_Pro_v2.0");
        img[0x28] = 0x88; img[0x29] = 0x13;              /* id 10 (IN1 LV offset) = 5000 */
        path = write_img(img, EE_SIZE, "uni_offs");
        ret = rp_read_calib_params_file(path, &p);
        CHECK(ret == 0 && p.source == RP_CALIB_SRC_FACTORY && p.fe_ch1_dc_offs_lv == 0, "offset 5000: factory zone");

        img[0x1c28] = 0x88; img[0x1c29] = 0x13;          /* both zones */
        path = write_img(img, EE_SIZE, "uni_offs_both");
        ret = rp_read_calib_params_file(path, &p);
        CHECK(ret == -1 && p.source == RP_CALIB_SRC_NOMINAL && p.gen2 == 1, "offset 5000 in both zones: nominal");

        /* short image (only the user zone) */
        build(img, gen2_user, NULL, NULL);
        path = write_img(img, 256, "short");
        ret = rp_read_calib_params_file(path, &p);
        CHECK(ret == 0 && p.source == RP_CALIB_SRC_USER && p.gen2 == 0 && p.hw_rev[0] == '\0', "256-byte image");

        snprintf((char *)img, 600, "%s/calib_test_does_not_exist.bin", dir);
        ret = rp_read_calib_params_file((char *)img, &p);
        CHECK(ret == -1 && p.source == RP_CALIB_SRC_NOMINAL, "missing file: nominal");
    }
    CHECK(rp_calib_adc_offs(&p, 0, 0) == 0 && rp_calib_adc_offs(&p, 3, 1) == 0, "internal signals: no offset");

    printf("%s: %d checks, %d failures\n", fails ? "FAIL" : "PASS", checks, fails);
    return fails ? 1 : 0;
}
