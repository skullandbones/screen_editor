/*==============================================================================
 * BLOCK.H: Block Selection, Clipboard & Multi-Line Editing API
 *
 * Purpose:
 *   Defines block highlighting modes, boundary coordinates, clipboard buffer
 *   capacities, and block cut/copy/paste/indentation function signatures.
 *   C semantic equivalent header mirroring src/include/block.inc.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#ifndef SE_BLOCK_H
#define SE_BLOCK_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "config.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Block State Modes */
#define BLOCK_MODE_OFF          0   /* No block selection active */
#define BLOCK_MODE_SELECTING    1   /* Block actively anchoring from cursor */
#define BLOCK_MODE_SOLIDIFIED   2   /* Block solidified (anchor frozen) */

/* Global Block State Variables */
extern uint8_t  g_block_mode;
extern uint16_t g_block_anchor_row;
extern uint16_t g_block_anchor_col;
extern uint16_t g_block_active_row;
extern uint16_t g_block_active_col;
extern uint16_t g_norm_start_row;
extern uint16_t g_norm_start_col;
extern uint16_t g_norm_end_row;
extern uint16_t g_norm_end_col;

/* Block Subsystem Function Entry Points */
void toggle_block_mode(void);
void cancel_block(void);
void solidify_block(void);
int  do_block_menu_popup(void);
void normalize_block_bounds(void);
int  do_delete_block(void);
int  do_copy_block(void);
int  do_move_block(void);
int  check_cursor_in_block(uint16_t row, uint16_t col);
int  get_line_block_range(uint16_t row, uint16_t *start_col, uint16_t *end_col);
void start_new_block_at_cursor(void);
void update_block_selection(void);
uint16_t    get_clipboard_len(void);
const char *get_clipboard_buffer(void);
int         do_paste_block(void);
int         do_cut_block(void);

#ifdef __cplusplus
}
#endif

#endif /* SE_BLOCK_H */
