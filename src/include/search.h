/*==============================================================================
 * SEARCH.H: Text Search, Forward Find & Replace Engine API
 *
 * Purpose:
 *   Defines search pattern buffer capacities, case sensitivity flags, modal
 *   field dimensions, and string matching entry point contracts.
 *   C semantic equivalent header mirroring src/include/search.inc.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#ifndef SE_SEARCH_H
#define SE_SEARCH_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "config.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Search Buffer Capacities & Modal Field Lengths */
#define SEARCH_BUF_MAX          64
#define FIND_POPUP_FIELD_LEN    28
#define REPLACE_POPUP_FIELD_LEN 29

/* Global Search State Variables */
extern char     g_search_buf[SEARCH_BUF_MAX];
extern uint16_t g_search_len;
extern char     g_replace_buf[SEARCH_BUF_MAX];
extern uint16_t g_replace_len;
extern uint8_t  g_search_case_sensitive;

/* Search Subsystem Function Entry Points */
int  do_ctrl_f_find(void);
int  do_ctrl_r_replace(void);
int  do_ctrl_n_find_next(void);
int  do_find_prev(void);
int  execute_find_forward(void);
int  execute_find_backward(void);
int  find_string_in_line(const char *pattern, uint16_t pat_len,
                         const char *line, uint16_t line_len,
                         uint16_t *match_col);
void show_popup_not_found(void);
void show_popup_search_completed(void);
void show_popup_replace_done(uint16_t count);

#ifdef __cplusplus
}
#endif

#endif /* SE_SEARCH_H */
