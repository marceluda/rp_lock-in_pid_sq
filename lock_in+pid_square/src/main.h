/**
 * $Id: main.h 881 2013-12-16 05:37:34Z rp_jmenart $
 *
 * @brief Red Pitaya Oscilloscope main module.
 *
 * @Author Jure Menart <juremenart@gmail.com>
 *
 * (c) Red Pitaya  http://www.redpitaya.com
 *
 * This part of code is written in C programming language.
 * Please visit http://en.wikipedia.org/wiki/C_(programming_language)
 * for more details on the language used herein.
 */

#ifndef __MAIN_H
#define __MAIN_H

// #define DEBUG 1


#ifdef DEBUG
#  define TRACE(args...) fprintf(stderr, args)
#else
#  define TRACE(args...) {}
#endif

/* Parameters description structure - must be the same for all RP controllers */
typedef struct rp_app_params_s {
    char  *name;
    float  value;
    int    fpga_update;
    int    read_only;
    float  min_val;
    float  max_val;
} rp_app_params_t;

/* Signal measurement results structure - filled in worker and updated when
 * also measurement signal is stored from worker
 */
typedef struct rp_osc_meas_res_s {
    float min;
    float max;
    float amp;
    float avg;
    float freq;
    float period;
} rp_osc_meas_res_t;

/* Parameters indexes - these defines should be in the same order as
 * rp_app_params_t structure defined in main.c */
//define PARAMS_NUM        81
#define PARAMS_NUM        198
#define MIN_GUI_PARAM     0
#define MAX_GUI_PARAM     1
#define TRIG_MODE_PARAM   2
#define TRIG_SRC_PARAM    3
#define TRIG_EDGE_PARAM   4
#define TRIG_DLY_PARAM    5
#define TRIG_LEVEL_PARAM  6
#define SINGLE_BUT_PARAM  7
#define TIME_RANGE_PARAM  8
#define TIME_UNIT_PARAM   9
#define EN_AVG_AT_DEC     10
#define AUTO_FLAG_PARAM   11
#define MIN_Y_PARAM       12
#define MAX_Y_PARAM       13
#define FORCEX_FLAG_PARAM 14
#define MEAS_MIN_CH1      15
#define MEAS_MAX_CH1      16
#define MEAS_AMP_CH1      17
#define MEAS_AVG_CH1      18
#define MEAS_FREQ_CH1     19
#define MEAS_PER_CH1      20
#define MEAS_MIN_CH2      21
#define MEAS_MAX_CH2      22
#define MEAS_AMP_CH2      23
#define MEAS_AVG_CH2      24
#define MEAS_FREQ_CH2     25
#define MEAS_PER_CH2      26
#define PRB_ATT_CH1       27
#define GAIN_CH1          28
#define PRB_ATT_CH2       29
#define GAIN_CH2          30
#define GUI_RST_Y_RANGE   31
#define GEN_DC_OFFS_1     32
#define GEN_DC_OFFS_2     33
#define GUI_XMIN          34
#define GUI_XMAX          35
#define MIN_Y_NORM        36
#define MAX_Y_NORM        37
#define GEN_DC_NORM_1     38
#define GEN_DC_NORM_2     39
#define SCALE_CH1         40
#define SCALE_CH2         41
/* AWG parameters */
#define GEN_TRIG_MODE_CH1 42
#define GEN_SIG_TYPE_CH1  43
#define GEN_ENABLE_CH1    44
#define GEN_SINGLE_CH1    45
#define GEN_SIG_AMP_CH1   46
#define GEN_SIG_FREQ_CH1  47
#define GEN_SIG_DCOFF_CH1 48
#define GEN_TRIG_MODE_CH2 49
#define GEN_SIG_TYPE_CH2  50
#define GEN_ENABLE_CH2    51
#define GEN_SINGLE_CH2    52
#define GEN_SIG_AMP_CH2   53
#define GEN_SIG_FREQ_CH2  54
#define GEN_SIG_DCOFF_CH2 55
#define GEN_AWG_REFRESH   56
/* PID parameters */
#define PID_11_ENABLE     57
#define PID_11_RESET      58
#define PID_11_SP         59
#define PID_11_KP         60
#define PID_11_KI         61
#define PID_11_KD         62
#define PID_12_ENABLE     63
#define PID_12_RESET      64
#define PID_12_SP         65
#define PID_12_KP         66
#define PID_12_KI         67
#define PID_12_KD         68
#define PID_21_ENABLE     69
#define PID_21_RESET      70
#define PID_21_SP         71
#define PID_21_KP         72
#define PID_21_KI         73
#define PID_21_KD         74
#define PID_22_ENABLE     75
#define PID_22_RESET      76
#define PID_22_SP         77
#define PID_22_KP         78
#define PID_22_KI         79
#define PID_22_KD         80

// [MAINDEFH DOCK]

#define LOCK_OSCA_SW                    81
#define LOCK_OSCB_SW                    82
#define LOCK_OSC1_FILT_OFF              83
#define LOCK_OSC2_FILT_OFF              84
#define LOCK_OSC_RAW_MODE               85
#define LOCK_OSC_LOCKIN_MODE            86
#define LOCK_TRIG_SW                    87
#define LOCK_OUT1_SW                    88
#define LOCK_OUT2_SW                    89
#define LOCK_LOCK_CONTROL               90
#define LOCK_LOCK_STATUS                91
#define LOCK_LOCK_TRIG_VAL              92
#define LOCK_LOCK_TRIG_TIME_VAL         93
#define LOCK_LOCK_TRIG_SW               94
#define LOCK_RL_ERROR_THRESHOLD         95
#define LOCK_RL_SIGNAL_SW               96
#define LOCK_RL_SIGNAL_THRESHOLD        97
#define LOCK_RL_ERROR_ENABLE            98
#define LOCK_RL_SIGNAL_ENABLE           99
#define LOCK_RL_RESET                   100
#define LOCK_RL_STATE                   101
#define LOCK_SF_JUMPA                   102
#define LOCK_SF_JUMPB                   103
#define LOCK_SF_START                   104
#define LOCK_SF_AFRZO                   105
#define LOCK_SF_AFRZI                   106
#define LOCK_SF_BFRZO                   107
#define LOCK_SF_BFRZI                   108
#define LOCK_SIGNAL_SW                  109
#define LOCK_SIGNAL_I                   110
#define LOCK_SG_AMP_SQ                  111
#define LOCK_SG_AMP_SQF                 112
#define LOCK_LPF_SQ_TAU                 113
#define LOCK_LPF_SQ_ORDER               114
#define LOCK_LPF_SQF_TAU                115
#define LOCK_LPF_SQF_ORDER              116
#define LOCK_ERROR_SW                   117
#define LOCK_ERROR_OFFSET               118
#define LOCK_ERROR                      119
#define LOCK_ERROR_MEAN                 120
#define LOCK_ERROR_STD                  121
#define LOCK_MOD_OUT1                   122
#define LOCK_MOD_OUT2                   123
#define LOCK_GEN_MOD_SQP                124
#define LOCK_GEN_MOD_PHASE_SQ           125
#define LOCK_RAMP_A                     126
#define LOCK_RAMP_B                     127
#define LOCK_RAMP_STEP                  128
#define LOCK_RAMP_LOW_LIM               129
#define LOCK_RAMP_HIG_LIM               130
#define LOCK_RAMP_RESET                 131
#define LOCK_RAMP_ENABLE                132
#define LOCK_RAMP_DIRECTION             133
#define LOCK_RAMP_SAWTOOTH              134
#define LOCK_RAMP_B_FACTOR              135
#define LOCK_SQ_REF                     136
#define LOCK_SQ_QUAD                    137
#define LOCK_SQ_PHAS                    138
#define LOCK_IN1                        139
#define LOCK_IN2                        140
#define LOCK_OUT1                       141
#define LOCK_OUT2                       142
#define LOCK_OSCA                       143
#define LOCK_OSCB                       144
#define LOCK_SQX_28                     145
#define LOCK_SQY_28                     146
#define LOCK_SQF_28                     147
#define LOCK_CNT_CLK                    148
#define LOCK_CNT_CLK2                   149
#define LOCK_READ_CTRL                  150
#define LOCK_PIDA_SW                    151
#define LOCK_PIDA_PSR                   152
#define LOCK_PIDA_ISR                   153
#define LOCK_PIDA_DSR                   154
#define LOCK_PIDA_SAT                   155
#define LOCK_PIDA_SP                    156
#define LOCK_PIDA_KP                    157
#define LOCK_PIDA_KI                    158
#define LOCK_PIDA_KD                    159
#define LOCK_PIDA_IN                    160
#define LOCK_PIDA_OUT                   161
#define LOCK_PIDA_IRST                  162
#define LOCK_PIDA_FREEZE                163
#define LOCK_PIDA_IFREEZE               164
#define LOCK_CTRL_A                     165
#define LOCK_PIDB_SW                    166
#define LOCK_PIDB_PSR                   167
#define LOCK_PIDB_ISR                   168
#define LOCK_PIDB_DSR                   169
#define LOCK_PIDB_SAT                   170
#define LOCK_PIDB_SP                    171
#define LOCK_PIDB_KP                    172
#define LOCK_PIDB_KI                    173
#define LOCK_PIDB_KD                    174
#define LOCK_PIDB_IN                    175
#define LOCK_PIDB_OUT                   176
#define LOCK_PIDB_IRST                  177
#define LOCK_PIDB_FREEZE                178
#define LOCK_PIDB_IFREEZE               179
#define LOCK_CTRL_B                     180
#define LOCK_AUX_A                      181
#define LOCK_AUX_B                      182
#define LOCK_STREAM_IP                  183
#define LOCK_STREAM_PORT                184
#define LOCK_STREAM_RATE                185
#define LOCK_STREAM_CMD                 186
#define LOCK_CTRL_AUX_LOCK_NOW          187
#define LOCK_CTRL_AUX_LAUNCH_LOCK_TRIG  188
#define LOCK_CTRL_AUX_PIDB_ENABLE_CTRL  189
#define LOCK_CTRL_AUX_PIDA_ENABLE_CTRL  190
#define LOCK_CTRL_AUX_RAMP_ENABLE_CTRL  191
#define LOCK_CTRL_AUX_SET_PIDB_ENABLE   192
#define LOCK_CTRL_AUX_SET_PIDA_ENABLE   193
#define LOCK_CTRL_AUX_SET_RAMP_ENABLE   194
#define LOCK_CTRL_AUX_TRIG_TYPE         195
#define LOCK_CTRL_AUX_LOCK_TRIG_RISE    196
#define LOCK_MOD_SQ_ON                  197

// [MAINDEFH DOCK END]


/* Defines from which parameters on are AWG parameters (used in set_param() to
 * trigger update only on needed part - either Oscilloscope, AWG or PID */
#define PARAMS_AWG_PARAMS 42

/* Defines from which parameters on are PID parameters (used in set_param() to
 * trigger update only on needed part - either Oscilloscope, AWG or PID */
#define PARAMS_PID_PARAMS 57
#define PARAMS_PER_PID     6

/* Defines from which parameters on are LOCK parameters (used in set_param() to
 * trigger update only on needed part - either Oscilloscope, AWG or PID */
#define PARAMS_LOCK_PARAMS 81



/* Output signals */
#define SIGNAL_LENGTH (1024) /* Must be 2^n! */
#define SIGNALS_NUM   3


/* module entry points */
int rp_app_init(void);
int rp_app_exit(void);
int rp_set_params(rp_app_params_t *p, int len);
int rp_get_params(rp_app_params_t **p);
int rp_get_signals(float ***s, int *sig_num, int *sig_len);

/* Internal helper functions */
int  rp_create_signals(float ***a_signals);
void rp_cleanup_signals(float ***a_signals);

/* copies parameters from src to dst - if dst does not exists, it creates it */
int rp_copy_params(rp_app_params_t *src, rp_app_params_t **dst);

/* cleans up memory of parameters structure */
int rp_clean_params(rp_app_params_t *params);

/* End of the auto-set: copies the scope parameters computed by the auto-set (v2.3.14: only those,
 * see auto_set_params[] in main.c) to the main parameters and applies them (this also changes the
 * worker state machine).
 */
int rp_update_main_params(rp_app_params_t *params);
/* v2.3.14: auto-set aborted by another state: clears auto_flag, copies nothing back */
void rp_auto_set_aborted(void);
void get_scales(rp_app_params_t *p, float *scale1, float *scale2, float *maxv);
void transform_to_iface_units(rp_app_params_t *p);
void transform_from_iface_units(rp_app_params_t *p);

/* sets the measurement data to output parameters structure - these parameters
 * are read-only for the client and there is no need to update them internally
 * in the application
 */
int rp_update_meas_data(rp_osc_meas_res_t ch1_meas, rp_osc_meas_res_t ch2_meas);

/* Waveform generator frequency limiter. */
float rp_gen_limit_freq(float freq, float gen_type);

/* v2.3.10: number of c/stream_tcp_osc_cmd processes of this App alive (main.c) */
int stream_tcp_alive(void);

#endif /*  __MAIN_H */
