/*==============================================================================
 * EDITOR.H: Core Editor Engine, Cursor Navigation & Edit Primitives API
 *
 * Purpose:
 *   Defines editor state variables, coordinate conventions, key dispatchers,
 *   and text manipulation primitive signatures.
 *   C semantic equivalent header mirroring src/include/editor.inc.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#ifndef SE_EDITOR_H
#define SE_EDITOR_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "config.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Global Editor Navigation & State Variables */
extern uint16_t g_cur_col;             /* Document character column (0-based) */
extern uint16_t g_top_doc_row;         /* Top visible document row */
extern uint16_t g_horiz_pan_offset;    /* Horizontal scroll offset in cols */
extern uint8_t  g_insert_mode;         /* 1 = Insert mode, 0 = Overwrite */
extern uint8_t  g_editor_exit_flag;    /* 1 = Exit loop requested */
extern uint8_t  g_action_code;         /* Exit action code (ACTION_*) */

/* Editor Entry Points & Key Dispatch */
void     editor_init(void);
void     editor_main_loop(void);
int      editor_handle_key(int key);
int      do_char_insert(char c);
void     do_backspace(void);
void     do_delete(void);
void     do_enter(void);
void     goto_line(uint16_t target_line);
uint16_t calc_visual_col(const char *buf, uint16_t char_col);
void     locate_cursor(void);
void     update_horizontal_pan(void);

/* Cursor Navigation Primitives */
void     cursor_up(void);
void     cursor_down(void);
void     cursor_left(void);
void     cursor_right(void);
void     cursor_home(void);
void     cursor_end(void);
void     page_up(void);
void     page_down(void);
void     jump_file_top(void);
void     jump_file_bottom(void);
void     toggle_insert_mode(void);
void     adjust_col_to_target(uint16_t target_vis_col);

#ifdef __cplusplus
}
#endif

#endif /* SE_EDITOR_H */
