/**
 * $Id: calib.c 881 2013-12-16 05:37:34Z rp_jmenart $
 *
 * @brief Red Pitaya Oscilloscope Calibration Module.
 *
 * @Author Jure Menart <juremenart@gmail.com>
 *
 * (c) Red Pitaya  http://www.redpitaya.com
 *
 * This part of code is written in C programming language.
 * Please visit http://en.wikipedia.org/wiki/C_(programming_language)
 * for more details on the language used herein.
 *
 * v2.2.17 (lock_in+pid): reads the calibration formats of the EEPROM (read only, the EEPROM is never written).
 *
 * Until 2.2.16 the App read 40 bytes at 0x0008 with the layout of apps-free/scope (2013), whatever the format. The
 * OS 2.x (and every STEMlab 125-14 Gen2 from the factory) store the "universal" format 5 / 6: with it IN1 read a
 * constant > 30 V and IN2 ~0 V (reportes/gen2_resultados.md). Layout of the EEPROM (24c64, 8 KiB), as in the official
 * library (RedPitaya Release-2025.2, rp-api/api-hw-calib/src/{calib.cpp, calib_common.cpp, calib_universal.cpp,
 * calib_structs.h}, include/rp_hw_calib.h; rp-api/api-hw-profiles/src/common.cpp):
 *
 *   0x0000  user calibration      byte 0 = dataStructureId
 *   0x1800  U-Boot environment    "hw_rev=STEM_125-14_v1.0" / "hw_rev=STEM_125-14_Pro_v2.0" ... (from 0x1804)
 *   0x1c00  factory calibration   same formats as the user zone
 *
 * Formats (little endian):
 *   1 (or no header, apps-free 0.9x): rp_calib_params_v1_t: 8 bytes of header, then at 0x08 fe_ch1/2_fs_g_hi (LV),
 *     fe_ch1/2_fs_g_lo (HV), fe_ch1/2_lo_offs (0x18), be_ch1/2_fs, be_ch1/2_dc_offs, magic (0x30), fe_ch1/2_hi_offs
 *     (0x34). Full scales in V * 2^32 / 100. With a valid magic (0xAABBCCDD / 0xDDCCBBAA) the offset of the LV range
 *     is hi_offs (0x34 / 0x38) and lo_offs (0x18 / 0x1c) is the one of the HV range; without it (0.9x) the single
 *     offset at 0x18 is used for both ranges.
 *   5, 6: rp_eepromUniData_t: id (u8), wpCheck (u8), count (u16), 4 reserved bytes, then count items of 6 bytes
 *     {u16 id; i32 value}, searched by id (getParameter()): 1 / 3 DAC gain, 2 / 4 DAC offset, 9 / 11 ADC gain 1:1
 *     (LV), 10 / 12 ADC offset 1:1, 17 / 19 ADC gain 1:20 (HV), 18 / 20 ADC offset 1:20 (channel 1 / 2).
 *     gainCalc = value / (2^28 / 100) (baseScale 1); ADC: V = (raw - offset) * gainCalc * 1 V / 8192 * (1 | 20)
 *     (convert.hpp, acq_handler.cpp); DAC: counts = round(V * gainCalc * 8192 / FS_DAC) + offset (generate.cpp),
 *     FS_DAC = 2 V on the Gen2 boards (hw_rev "..._v2.0"), 1 V on Gen1.
 *     In the units of this App: fs_g_hi = 16 * value (LV), fs_g_lo = 320 * value (HV) (exact: 2^32 / 2^28 = 16),
 *     DAC full scale FS_DAC / gainCalc, ADC offset correction -offset, DAC offset +offset.
 *
 * As the official library, the user zone is used. If it is not valid (unknown or corrupt format, or a full scale /
 * offset out of the sanity limits below), the factory zone is tried (the official library would take its defaults);
 * if that one is not valid either, nominal values. The source is kept in calib_params->source (read-only param
 * calib_status of the page, which shows a warning).
 */

#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <math.h>

#include "calib.h"

const char eeprom_device[]="/sys/bus/i2c/devices/0-0050/eeprom";
const int  eeprom_calib_off=0x0008;           /* old layout: fields from here (0x0000 + 8 bytes of header) */

#define EE_USER_OFF      0x0000
#define EE_FACTORY_OFF   0x1c00
#define EE_ENV_OFF       0x1800
#define EE_ENV_LEN       0x0400
#define EE_V1_LEN        0x3c                 /* header + 10 fields + magic + 2 LV offsets */
#define EE_UNI_MAX_ITEMS 512                  /* MAX_UNIVERSAL_ITEMS_COUNT of the official library */
#define CALIB_MAGIC        0xAABBCCDDu
#define CALIB_MAGIC_FILTER 0xDDCCBBAAu

/* 1 V in the units of the old layout (V * 2^32 / 100), as calibBaseScaleFromVoltage(1, false) of the library */
#define FS_1V            42949672u

/* Sanity limits (option B of reportes/gen2_diferencias.md) */
#define LV_FS_MIN   0.5
#define LV_FS_MAX   2.0
#define HV_FS_MIN  10.0
#define HV_FS_MAX  40.0
#define DAC_FS_MIN  0.5
#define DAC_FS_MAX  3.0
#define OFFS_MAX   1000

static uint32_t rd_u32(const unsigned char *b) { return b[0] | (b[1] << 8) | (b[2] << 16) | ((uint32_t)b[3] << 24); }
static int32_t  rd_i32(const unsigned char *b) { return (int32_t)rd_u32(b); }
static unsigned rd_u16(const unsigned char *b) { return b[0] | (b[1] << 8); }

static double fs_to_v(uint32_t fs) { return fs / 4294967296.0 * 100.0; }
static uint32_t v_to_fs(double v)  { return (uint32_t)floor(v / 100.0 * 4294967296.0 + 0.5); }

/* n bytes at off; returns the number of bytes read */
static size_t ee_read(FILE *fp, long off, unsigned char *buf, size_t n)
{
    if(fseek(fp, off, SEEK_SET) < 0)
        return 0;
    return fread(buf, 1, n, fp);
}

/* hw_rev of the U-Boot environment (strings "name=value" separated by '\0' after a 4-byte CRC) */
static void read_hw_rev(FILE *fp, rp_calib_params_t *p)
{
    unsigned char env[EE_ENV_LEN + 1];
    size_t n = ee_read(fp, EE_ENV_OFF, env, EE_ENV_LEN);
    size_t i, k;

    p->hw_rev[0] = '\0';
    p->gen2 = 0;
    if(n < 8)
        return;
    env[n] = '\0';
    for(i = 0; i + 7 < n; i++) {
        if(memcmp(&env[i], "hw_rev=", 7) == 0) {
            for(k = 0; k + 1 < sizeof(p->hw_rev) && i + 7 + k < n; k++) {
                unsigned char c = env[i + 7 + k];
                if(c < 0x20 || c > 0x7e)
                    break;
                p->hw_rev[k] = c;
            }
            p->hw_rev[k] = '\0';
            break;
        }
    }
    p->gen2 = (strstr(p->hw_rev, "_v2.0") != NULL);
}

/* Checks the decoded values; returns NULL if they are plausible, else the reason */
static const char *sanity(const rp_calib_params_t *p, char *why, size_t why_len)
{
    const uint32_t fs_lv[2] = { p->fe_ch1_fs_g_hi, p->fe_ch2_fs_g_hi };
    const uint32_t fs_hv[2] = { p->fe_ch1_fs_g_lo, p->fe_ch2_fs_g_lo };
    const uint32_t fs_be[2] = { p->be_ch1_fs, p->be_ch2_fs };
    const int32_t  offs[8]  = { p->fe_ch1_dc_offs_lv, p->fe_ch2_dc_offs_lv, p->fe_ch1_dc_offs, p->fe_ch2_dc_offs,
                                p->be_ch1_dc_offs, p->be_ch2_dc_offs, 0, 0 };
    static const char *offs_name[6] = { "IN1 LV offset", "IN2 LV offset", "IN1 HV offset", "IN2 HV offset",
                                        "OUT1 offset", "OUT2 offset" };
    int i;
    for(i = 0; i < 2; i++) {
        double v = fs_to_v(fs_lv[i]);
        if(!(v >= LV_FS_MIN && v <= LV_FS_MAX)) {
            snprintf(why, why_len, "IN%d LV full scale %.4g V", i + 1, v);
            return why;
        }
        v = fs_to_v(fs_hv[i]);
        if(!(v >= HV_FS_MIN && v <= HV_FS_MAX)) {
            snprintf(why, why_len, "IN%d HV full scale %.4g V", i + 1, v);
            return why;
        }
        v = fs_to_v(fs_be[i]);
        if(!(v >= DAC_FS_MIN && v <= DAC_FS_MAX)) {
            snprintf(why, why_len, "OUT%d full scale %.4g V", i + 1, v);
            return why;
        }
    }
    for(i = 0; i < 6; i++) {
        if(offs[i] > OFFS_MAX || offs[i] < -OFFS_MAX) {
            snprintf(why, why_len, "%s %d counts", offs_name[i], (int)offs[i]);
            return why;
        }
    }
    return NULL;
}

/* Decodes one zone (user or factory) into p (fields of the calibration only). Returns NULL if it is valid, else the
 * reason. dac_fs_v: full scale of the DAC chip (1 V Gen1, 2 V Gen2). */
static const char *read_zone(FILE *fp, long base, double dac_fs_v, rp_calib_params_t *p, char *why, size_t why_len)
{
    unsigned char hdr[8];
    if(ee_read(fp, base, hdr, sizeof(hdr)) != sizeof(hdr)) {
        snprintf(why, why_len, "can not read the header");
        return why;
    }
    p->format = hdr[0];

    if(hdr[0] == 5 || hdr[0] == 6) {
        /* universal format */
        unsigned count = rd_u16(&hdr[2]);
        unsigned char items[EE_UNI_MAX_ITEMS * 6];
        int32_t  val[21];
        int      have[21];
        unsigned i;
        static const int need[6] = { 1, 3, 9, 11, 17, 19 };   /* gains; a missing offset is 0 */

        if(count == 0 || count > EE_UNI_MAX_ITEMS) {
            snprintf(why, why_len, "format %d with %u items", hdr[0], count);
            return why;
        }
        if(ee_read(fp, base + 8, items, count * 6) != count * 6) {
            snprintf(why, why_len, "format %d: can not read %u items", hdr[0], count);
            return why;
        }
        memset(val, 0, sizeof(val));
        memset(have, 0, sizeof(have));
        for(i = 0; i < count; i++) {
            unsigned id = rd_u16(&items[i * 6]);
            if(id >= 1 && id <= 20 && !have[id]) {    /* the first one, as getParameter() */
                val[id]  = rd_i32(&items[i * 6 + 2]);
                have[id] = 1;
            }
        }
        for(i = 0; i < 6; i++) {
            if(!have[need[i]] || val[need[i]] <= 0) {
                snprintf(why, why_len, "format %d: gain id %d missing or not positive", hdr[0], need[i]);
                return why;
            }
        }
        /* ADC: 16 * value (LV), 320 * value (HV), in V * 2^32 / 100; values above 2^32 / 320 are out of any range */
        if(val[9] > 0x0ccccccc || val[11] > 0x0ccccccc || val[17] > 0x00cccccc || val[19] > 0x00cccccc) {
            snprintf(why, why_len, "format %d: ADC gain out of range", hdr[0]);
            return why;
        }
        p->fe_ch1_fs_g_hi    = 16u  * (uint32_t)val[9];
        p->fe_ch2_fs_g_hi    = 16u  * (uint32_t)val[11];
        p->fe_ch1_fs_g_lo    = 320u * (uint32_t)val[17];
        p->fe_ch2_fs_g_lo    = 320u * (uint32_t)val[19];
        p->fe_ch1_dc_offs_lv = -val[10];
        p->fe_ch2_dc_offs_lv = -val[12];
        p->fe_ch1_dc_offs    = -val[18];
        p->fe_ch2_dc_offs    = -val[20];
        /* DAC: 8192 counts give FS_DAC / gainCalc volts, gainCalc = value / (2^28 / 100) */
        p->be_ch1_fs = v_to_fs(fmin(dac_fs_v / (val[1] / (268435456.0 / 100.0)), 99.0));
        p->be_ch2_fs = v_to_fs(fmin(dac_fs_v / (val[3] / (268435456.0 / 100.0)), 99.0));
        p->be_ch1_dc_offs = val[2];
        p->be_ch2_dc_offs = val[4];
    } else {
        /* old 125-14 layout (format 1, or no header: apps-free 0.9x) */
        unsigned char b[EE_V1_LEN];
        uint32_t magic;
        if(ee_read(fp, base, b, sizeof(b)) != sizeof(b)) {
            snprintf(why, why_len, "format %d: can not read the old layout", hdr[0]);
            return why;
        }
        magic = rd_u32(&b[0x30]);
        p->fe_ch1_fs_g_hi = rd_u32(&b[0x08]);
        p->fe_ch2_fs_g_hi = rd_u32(&b[0x0c]);
        p->fe_ch1_fs_g_lo = rd_u32(&b[0x10]);
        p->fe_ch2_fs_g_lo = rd_u32(&b[0x14]);
        p->fe_ch1_dc_offs = -rd_i32(&b[0x18]);
        p->fe_ch2_dc_offs = -rd_i32(&b[0x1c]);
        /* the DAC full scale of the old layout is the one of a 1 V DAC (Gen1): with a 2 V DAC (Gen2 board with the
         * old format, e.g. after calib -o) the output of 8192 counts is FS_DAC times it */
        p->be_ch1_fs = v_to_fs(fmin(fs_to_v(rd_u32(&b[0x20])) * dac_fs_v, 99.0));
        p->be_ch2_fs = v_to_fs(fmin(fs_to_v(rd_u32(&b[0x24])) * dac_fs_v, 99.0));
        p->be_ch1_dc_offs = rd_i32(&b[0x28]);
        p->be_ch2_dc_offs = rd_i32(&b[0x2c]);
        if(magic == CALIB_MAGIC || magic == CALIB_MAGIC_FILTER) {
            p->fe_ch1_dc_offs_lv = -rd_i32(&b[0x34]);
            p->fe_ch2_dc_offs_lv = -rd_i32(&b[0x38]);
        } else {
            p->fe_ch1_dc_offs_lv = p->fe_ch1_dc_offs;
            p->fe_ch2_dc_offs_lv = p->fe_ch2_dc_offs;
        }
        /* an erased zone (0xff) gives 100 V full scales: rejected by sanity() */
    }
    return sanity(p, why, why_len);
}

static void print_calib(const rp_calib_params_t *p, const char *zone)
{
    fprintf(stderr, "Calibration: %s (format %d), hw_rev %s (%s, DAC %d V): "
            "IN1/IN2 LV %.4f/%.4f V offs %d/%d, HV %.3f/%.3f V offs %d/%d, OUT1/OUT2 %.4f/%.4f V offs %d/%d\n",
            zone, p->format, p->hw_rev[0] ? p->hw_rev : "unknown", p->gen2 ? "Gen2" : "Gen1", p->gen2 ? 2 : 1,
            fs_to_v(p->fe_ch1_fs_g_hi), fs_to_v(p->fe_ch2_fs_g_hi),
            (int)-p->fe_ch1_dc_offs_lv, (int)-p->fe_ch2_dc_offs_lv,
            fs_to_v(p->fe_ch1_fs_g_lo), fs_to_v(p->fe_ch2_fs_g_lo),
            (int)-p->fe_ch1_dc_offs, (int)-p->fe_ch2_dc_offs,
            fs_to_v(p->be_ch1_fs), fs_to_v(p->be_ch2_fs), (int)p->be_ch1_dc_offs, (int)p->be_ch2_dc_offs);
}

/*----------------------------------------------------------------------------*/
/**
 * @brief Read calibration parameters from an EEPROM image (the device or a file).
 *
 * @param[in]    path          EEPROM device or image file
 * @param[out]   calib_params  Pointer to destination buffer.
 * @retval       0 Calibration of the EEPROM (user or factory zone)
 * @retval      -1 No valid calibration: nominal values (message on stderr)
 */
int rp_read_calib_params_file(const char *path, rp_calib_params_t *calib_params)
{
    FILE *fp;
    rp_calib_params_t p;
    char why_user[96], why_fact[96];
    const char *err;
    double dac_fs_v;

    /* sanity check */
    if(calib_params == NULL) {
        fprintf(stderr, "rp_read_calib_params(): input structure "
                "not initialized\n");
        return -1;
    }
    rp_default_calib_params(calib_params);

    /* open eeprom device (read only) */
    fp = fopen(path, "rb");
    if(fp == NULL) {
        fprintf(stderr, "rp_read_calib_params(): Can not open EEPROM device %s: %s; "
                "calibration not recognised, using nominal values\n", path, strerror(errno));
        print_calib(calib_params, "nominal values");
        return -1;
    }

    read_hw_rev(fp, calib_params);
    dac_fs_v = calib_params->gen2 ? 2.0 : 1.0;
    /* nominal DAC full scale of this board (1 V Gen1, 2 V Gen2) */
    calib_params->be_ch1_fs = calib_params->be_ch2_fs = (uint32_t)(FS_1V * dac_fs_v);

    p = *calib_params;
    err = read_zone(fp, EE_USER_OFF, dac_fs_v, &p, why_user, sizeof(why_user));
    if(err == NULL) {
        fclose(fp);
        p.source = RP_CALIB_SRC_USER;
        *calib_params = p;
        print_calib(calib_params, "user zone");
        return 0;
    }

    p = *calib_params;
    err = read_zone(fp, EE_FACTORY_OFF, dac_fs_v, &p, why_fact, sizeof(why_fact));
    fclose(fp);
    if(err == NULL) {
        p.source = RP_CALIB_SRC_FACTORY;
        *calib_params = p;
        fprintf(stderr, "rp_read_calib_params(): user calibration not valid (%s): using the factory zone\n", why_user);
        print_calib(calib_params, "factory zone");
        return 0;
    }

    fprintf(stderr, "rp_read_calib_params(): calibration not recognised (user zone: %s; factory zone: %s): "
            "using nominal values\n", why_user, why_fact);
    print_calib(calib_params, "nominal values");
    return -1;
}

/*----------------------------------------------------------------------------*/
/**
 * @brief Read calibration parameters from EEPROM device.
 *
 * Function reads calibration parameters from EEPROM device and stores them to the
 * specified buffer. Communication to the EEPROM device is taken place through
 * appropriate system driver accessed through the file system device
 * /sys/bus/i2c/devices/0-0050/eeprom.
 *
 * @param[out]   calib_params  Pointer to destination buffer.
 * @retval       0 Success
 * @retval      -1 Failure (nominal values), error message is put on stderr device
 *
 */
int rp_read_calib_params(rp_calib_params_t *calib_params)
{
    (void)eeprom_calib_off;
    return rp_read_calib_params_file(eeprom_device, calib_params);
}


/*----------------------------------------------------------------------------*/
/**
 * Initialize calibration parameters to default values.
 *
 * v2.2.17: nominal values (1 V / 20 V, offsets 0, DAC 1 V); before, the defaults of apps-free 0.9x
 * (0.6543 V / 14.56 V, offset 585, DAC offset 0x3eac), far from any board.
 *
 * @param[out] calib_params  Pointer to target buffer to be initialized.
 * @retval 0 Success, could never fail.
 */

int rp_default_calib_params(rp_calib_params_t *calib_params)
{
    memset(calib_params, 0, sizeof(*calib_params));
    calib_params->fe_ch1_fs_g_hi = FS_1V;          /* 1 [V] */
    calib_params->fe_ch2_fs_g_hi = FS_1V;          /* 1 [V] */
    calib_params->fe_ch1_fs_g_lo = 858993459;      /* 20 [V] */
    calib_params->fe_ch2_fs_g_lo = 858993459;      /* 20 [V] */
    calib_params->fe_ch1_dc_offs = 0;
    calib_params->fe_ch2_dc_offs = 0;
    calib_params->fe_ch1_dc_offs_lv = 0;
    calib_params->fe_ch2_dc_offs_lv = 0;
    calib_params->be_ch1_fs = FS_1V;               /* 1 [V] */
    calib_params->be_ch2_fs = FS_1V;               /* 1 [V] */
    calib_params->be_ch1_dc_offs = 0;
    calib_params->be_ch2_dc_offs = 0;
    calib_params->source = RP_CALIB_SRC_NOMINAL;
    calib_params->format = -1;
    calib_params->gen2   = 0;
    calib_params->hw_rev[0] = '\0';

    return 0;
}


int32_t rp_calib_adc_offs(const rp_calib_params_t *calib_params, int input, int hv)
{
    if(calib_params == NULL)
        return 0;
    if(input == 1)
        return hv ? calib_params->fe_ch1_dc_offs : calib_params->fe_ch1_dc_offs_lv;
    if(input == 2)
        return hv ? calib_params->fe_ch2_dc_offs : calib_params->fe_ch2_dc_offs_lv;
    return 0;
}
