/**
 * $Id: calib.h 881 2013-12-16 05:37:34Z rp_jmenart $
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
 * v2.2.17: the structure is no longer a copy of the EEPROM bytes. rp_read_calib_params() decodes the calibration
 * formats of the EEPROM (old 125-14 layout, dataStructureId 1 or no header, and the universal formats 5 / 6 of the
 * OS 2.x and of the STEMlab 125-14 Gen2 boards) into these fields, in the units of the old layout.
 */

#ifndef __CALIB_H
#define __CALIB_H

#include <stdint.h>

/** @defgroup calib_h Calibration
 * @{
 */

/** Where the calibration in use comes from (rp_calib_params_t.source, read-only param calib_status of the page) */
#define RP_CALIB_SRC_USER     0   /**< user zone of the EEPROM (0x0000), as the official library */
#define RP_CALIB_SRC_FACTORY  1   /**< user zone not valid: factory zone (0x1c00) */
#define RP_CALIB_SRC_NOMINAL  2   /**< no valid calibration: nominal values (1 V / 20 V, offsets 0, DAC 1 V or 2 V) */

/** Calibration parameters (units of the old EEPROM layout of 2013)
 *
 * - Full scales (fs): volts * 2^32 / 100 (1 V = 42949672). LV = "hi" (high gain, jumpers LV), HV = "lo" (jumpers HV).
 * - ADC offsets (v2.2.17): CORRECTION ADDED to the raw counts, i.e. minus the offset of the EEPROM. The official
 *   library subtracts the stored offset (convert.hpp, cmn_CalibCntsSigned(): m -= offset); fpga.c / worker.c add
 *   these fields (the code of apps-free/scope), so they hold -offset. Before v2.2.17 the stored offset was added.
 * - fe_chX_dc_offs is the offset of the HV range, fe_chX_dc_offs_lv the one of the LV range (before v2.2.17 the
 *   HV field was used for both).
 * - DAC: be_chX_fs is the output voltage of 8192 counts (old units), be_chX_dc_offs counts added to the output
 *   (same sign as the official library, generate.cpp: n = round(V*gain*8192/FS) + offset).
 */
typedef struct rp_osc_calib_params_s {
    uint32_t fe_ch1_fs_g_hi;            /**< High gain (LV) front end full scale voltage, channel 1 */
    uint32_t fe_ch2_fs_g_hi;            /**< High gain (LV) front end full scale voltage, channel 2 */
    uint32_t fe_ch1_fs_g_lo;            /**< Low gain (HV) front end full scale voltage, channel 1  */
    uint32_t fe_ch2_fs_g_lo;            /**< Low gain (HV) front end full scale voltage, channel 2  */
    int32_t  fe_ch1_dc_offs;            /**< Front end DC offset correction (added), HV, channel 1  */
    int32_t  fe_ch2_dc_offs;            /**< Front end DC offset correction (added), HV, channel 2  */
    uint32_t be_ch1_fs;                 /**< Back end full scale voltage, channel 1  */
    uint32_t be_ch2_fs;                 /**< Back end full scale voltage, channel 2  */
    int32_t  be_ch1_dc_offs;            /**< Back end DC offset, channel 1 */
    int32_t  be_ch2_dc_offs;            /**< Back end DC offset, on channel 2 */
    /* v2.2.17 */
    int32_t  fe_ch1_dc_offs_lv;         /**< Front end DC offset correction (added), LV, channel 1  */
    int32_t  fe_ch2_dc_offs_lv;         /**< Front end DC offset correction (added), LV, channel 2  */
    int      source;                    /**< RP_CALIB_SRC_USER / _FACTORY / _NOMINAL */
    int      format;                    /**< dataStructureId of the zone used (1, 5, 6; other: old layout), -1 nominal */
    int      gen2;                      /**< 1: hw_rev of the EEPROM is a v2.0 board (STEMlab 125-14 Gen2, DAC 2 V) */
    char     hw_rev[48];                /**< hw_rev of the U-Boot environment of the EEPROM ("" if not found) */
} rp_calib_params_t;

/** @} */

/* Reads the calibration of the board (/sys/bus/i2c/devices/0-0050/eeprom, read only). Never fails: without a valid
 * calibration it fills nominal values. Returns 0 with a calibration of the EEPROM (user or factory zone), -1 with
 * nominal values. One line on stderr with what was used. */
int rp_read_calib_params(rp_calib_params_t *calib_params);

/* Same, from another file (offline tests: an image of the EEPROM) */
int rp_read_calib_params_file(const char *path, rp_calib_params_t *calib_params);

/* Nominal values (v2.2.17: 1 V / 20 V, offsets 0, DAC 1 V; they were the 0.6543 V / 14.56 V of apps-free 0.9x) */
int rp_default_calib_params(rp_calib_params_t *calib_params);

/* ADC offset correction (added to the raw counts) of input 1 or 2 (0 for any other value, e.g. an internal signal on
 * the scope), LV (hv = 0) or HV (hv != 0) */
int32_t rp_calib_adc_offs(const rp_calib_params_t *calib_params, int input, int hv);

#endif //__CALIB_H
