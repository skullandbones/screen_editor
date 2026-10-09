/*==============================================================================
 * FILE_IO.H: High-Level Document File I/O, FCB Definitions & Directory API
 *
 * Purpose:
 *   Defines CP/M File Control Block (FCB) field offsets, file transfer
 *   batch counters, and high-level file load/save/export function signatures.
 *   C semantic equivalent header mirroring src/include/file_io.inc.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#ifndef SE_FILE_IO_H
#define SE_FILE_IO_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "config.h"

#ifdef __cplusplus
extern "C" {
#endif

/* CP/M File Control Block (FCB) Layout */
typedef struct {
    uint8_t  drive;             /* 0=default, 1=A:, 2=B:, ... */
    char     name[8];           /* File name padded with spaces */
    char     ext[3];            /* File extension padded with spaces */
    uint8_t  extent;            /* Current extent number */
    uint8_t  s1;                /* Reserved */
    uint8_t  s2;                /* Reserved / Extent high byte */
    uint8_t  record_count;      /* Record count in current extent */
    uint8_t  allocation[16];    /* Allocation block map */
    uint8_t  current_record;    /* Current record within extent */
    uint8_t  random_r0;         /* Random record byte 0 (low) */
    uint8_t  random_r1;         /* Random record byte 1 (mid) */
    uint8_t  random_r2;         /* Random record byte 2 (high) */
} cpm_fcb_t;

/* Global Document Filename State */
extern char     g_current_filename[64];
extern uint8_t  g_file_format;

/* File I/O Subsystem Function Entry Points */
int  file_load(const char *filename);
int  file_save(const char *filename, uint8_t format);
int  file_save_block(const char *filename,
                     uint16_t start_row, uint16_t end_row,
                     uint8_t format);
void file_populate_fcb(const char *path, cpm_fcb_t *fcb);
int  file_check_hibernated(const char *path);

#ifdef __cplusplus
}
#endif

#endif /* SE_FILE_IO_H */
