#ifndef _BUFFER_H_
#define _BUFFER_H_

#include <stdint.h>
#include <stdbool.h>
#include "hbios.h"

#define MAX_LINES           8192    /* Up to 8K lines in index table */
#define MAX_LINE_LEN        256     /* Maximum columns per line */
#define DEFAULT_TAB_SIZE    8       /* Default tab stop columns for ASM */
#define EXT_BLOCK_SIZE      32768   /* 32KB page size for extended banks */

/*
 * Line reference in 512KB far memory
 */
typedef struct {
    FarPtr   storage;       /* Bank and address in 512KB RAM */
    uint16_t length;        /* Line length in bytes (excluding newline) */
} LineRef;

/*
 * In-memory editor buffer state
 */
typedef struct {
    LineRef  lines[MAX_LINES];      /* Far line pointer table */
    uint16_t total_lines;           /* Total lines currently loaded */
    uint16_t cursor_row;            /* 0-indexed row position */
    uint16_t cursor_col;            /* 0-indexed character column */
    uint16_t visual_col;            /* 0-indexed visual screen column */
    uint16_t top_line;              /* Current viewport top line */
    uint16_t left_col;              /* Current viewport horizontal scroll */
    bool     modified;              /* Has buffer changed since save? */
    uint8_t  tab_size;              /* Tab width (4 or 8) */
    char     current_line[MAX_LINE_LEN]; /* Active line cache in TPA */
} EditorBuffer;

extern EditorBuffer g_buf;

/* Buffer management prototypes */
void buffer_init(uint8_t tab_size);
bool buffer_insert_line(uint16_t row, const char *text, uint16_t len);
bool buffer_delete_line(uint16_t row);
bool buffer_get_line(uint16_t row, char *out_text, uint16_t *out_len);
bool buffer_set_line(uint16_t row, const char *text, uint16_t len);
uint16_t buffer_calc_visual_col(const char *text, uint16_t char_col, uint8_t tab_size);

#endif /* _BUFFER_H_ */
