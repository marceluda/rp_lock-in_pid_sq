/* v2.3.14: test only. Force-included (gcc -include) before every source of src/ when they are compiled
 * natively by run.sh: /dev/mem becomes plain memory, so the real controller code (main.c, worker.c,
 * lock.c, fpga*.c ...) runs on the PC. harness.c plays the scope FPGA on that memory. */
#ifndef FAKE_HW_H
#define FAKE_HW_H
#include <stddef.h>
#include <sys/types.h>
int   fake_open(const char *path, int flags, ...);
int   fake_close(int fd);
void *fake_mmap(void *addr, size_t len, int prot, int flags, int fd, off_t off);
int   fake_munmap(void *addr, size_t len);
#define open   fake_open
#define close  fake_close
#define mmap   fake_mmap
#define munmap fake_munmap
/* v2.0.12: the EEPROM (src/calib.c) is an image written by harness.c (old layout, the apps-free defaults of 2.3.32:
 * 0.6543 V / 14.56 V, offset correction +585), so that the tests keep a calibration offset and a full scale != 1 V */
#include <stdio.h>
FILE *fake_fopen(const char *path, const char *mode);
#define fopen  fake_fopen
#endif
