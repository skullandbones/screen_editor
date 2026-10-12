/*==============================================================================
 * BUFFER.H: Document Buffer & Line Cache Engine API Specifications
 *
 * Purpose:
 *   Defines data structures, buffer layouts, and function signatures for the
 *   document line table, active line workspace, virtual slot allocation,
 *   and multi-line cache management.
 *   C semantic equivalent header mirroring src/include/buffer.inc.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#ifndef SE_BUFFER_H
#define SE_BUFFER_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "config.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Buffer Memory Geometry Equates */
#define LINE_STORAGE_STRIDE     128 /* Cache line record stride (bytes) */
#define LINE_SHIFT_BUF_CAP      256 /* Shift buffer capacity for line inserts */
#define SWAP_IO_BUF_CAP         128 /* Virtual memory disk swap buffer size */

/* Cache Line Record Structure */
typedef struct {
    uint16_t doc_row;       /* Document line index mapped to this slot */
    uint8_t  dirty;         /* Non-zero if modified and uncommitted */
    uint8_t  in_use;        /* Non-zero if slot currently holds line data */
    char     data[LINE_STORAGE_STRIDE]; /* Null-padded line payload */
} cache_line_t;

/* Global Document Buffer State Variables */
extern char     g_active_line_buf[MAX_ACTIVE_LINE_STRIDE];
extern char     g_scratch_line_buf[MAX_ACTIVE_LINE_STRIDE];
extern uint16_t g_active_line_len;
extern uint16_t g_active_line_row;
extern uint8_t  g_active_line_valid;
extern uint16_t g_cur_doc_row;
extern uint16_t g_doc_total_lines;
extern uint8_t  g_doc_modified;

/* Document Buffer Function Entry Points */
void     buffer_init(void);
uint16_t get_line_slot(uint16_t line_idx, int *err);
int      set_line_slot(uint16_t line_idx, uint16_t slot_id);
uint16_t fetch_line_to_buffer(uint16_t line_idx, char *dest, size_t max_len);
int      store_active_line(void);
int      insert_blank_line(uint16_t line_idx);
int      delete_doc_row(uint16_t line_idx);
void     flush_dirty_cache(void);
void     checkout_active_line(uint16_t line_idx);
void     commit_active_line(void);
void     invalidate_active_line(void);
void     shift_line_slots_up(uint16_t start_idx, uint16_t count);
void     shift_line_slots_down(uint16_t start_idx, uint16_t count);
void     init_empty_document(void);

#ifdef __cplusplus
}
#endif

#endif /* SE_BUFFER_H */
