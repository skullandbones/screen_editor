/*==============================================================================
 * SEARCH.C: Core Subsystem - Text Search, Find Next & Interactive Replace Loop
 *
 * Purpose:
 *   Implements forward/backward string searching, case matching options,
 *   interactive search/replace dialogues, and search status notifications.
 *   C semantic equivalent to src/core/search.asm.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#include <string.h>
#include <ctype.h>
#include <stdio.h>
#include "../include/config.h"
#include "../include/buffer.h"
#include "../include/editor.h"
#include "../include/block.h"
#include "../include/search.h"
#include "../include/ui.h"
#include "../include/ui_modal.h"
#include "../include/hal.h"
#ifndef __CPM__
#include <unistd.h>
#endif

/* Global Search State Variables */
char     g_search_buf[SEARCH_BUF_MAX];
uint16_t g_search_len = 0;
char     g_replace_buf[SEARCH_BUF_MAX];
uint16_t g_replace_len = 0;
uint8_t  g_search_case_sensitive = 1;

static uint16_t s_search_start_row = 0;
static uint16_t s_search_start_col = 0;
static uint8_t  s_search_ever_found = 0;
static uint8_t  s_replace_active = 0;

static void restore_editor_screen(void)
{
    hal_console_hide_cursor();
    g_need_screen_render = 1;
    g_need_status_render = 1;
    render_screen();
    render_status_bar();
    locate_cursor();
}

static void step_back_one_char(void)
{
    if (g_cur_col > 0) {
        g_cur_col--;
    } else {
        if (g_cur_doc_row > 0) {
            g_cur_doc_row--;
        } else {
            g_cur_doc_row = g_doc_total_lines - 1;
        }
        g_cur_col = 255;
    }
}

static int apply_search_match(uint16_t row, uint16_t col)
{
    commit_active_line();
    g_cur_doc_row = row;
    g_block_anchor_row = g_norm_start_row = row;
    g_block_active_row = g_norm_end_row = row;
    g_block_anchor_col = g_norm_start_col = col;
    g_block_active_col = g_norm_end_col = col + g_search_len;
    g_block_mode = BLOCK_MODE_SOLIDIFIED;
    g_cur_col = g_norm_end_col;
    g_target_col = g_cur_col;
    s_search_ever_found = 1;
    checkout_active_line(row);
    if (row < g_top_doc_row ||
        row >= g_top_doc_row + (uint16_t)(g_active_rows - 1)) {
        g_top_doc_row = (row > 5) ? (row - 5) : 0;
    }
    restore_editor_screen();
    return 0;
}

static int handle_search_not_found(void)
{
    g_cur_doc_row = s_search_start_row;
    g_cur_col = s_search_start_col;
    g_target_col = g_cur_col;
    if (!s_replace_active) {
        if (!s_search_ever_found) {
            cancel_block();
            show_popup_not_found();
        } else {
            show_popup_search_completed();
        }
    }
    return -1;
}

static int match_pattern_at(const char *s)
{
    uint16_t i;
    for (i = 0; i < g_search_len; i++) {
        char a = s[i];
        char b = g_search_buf[i];
        if (!g_search_case_sensitive) {
            a = (char)tolower((unsigned char)a);
            b = (char)tolower((unsigned char)b);
        }
        if (a != b) {
            return 0;
        }
    }
    return 1;
}

#ifndef __CPM__
int find_string_in_line(const char *pattern, uint16_t pat_len,
                         const char *line, uint16_t line_len,
                         uint16_t *match_col)
{
    uint16_t start;

    if (!pattern || !line || pat_len == 0 || pat_len > line_len) {
        return -1;
    }

    for (start = 0; start <= line_len - pat_len; start++) {
        uint16_t i;
        int matched = 1;

        for (i = 0; i < pat_len; i++) {
            char a = line[start + i];
            char b = pattern[i];
            if (!g_search_case_sensitive) {
                a = (char)tolower((unsigned char)a);
                b = (char)tolower((unsigned char)b);
            }
            if (a != b) {
                matched = 0;
                break;
            }
        }
        if (matched) {
            if (match_col) {
                *match_col = start;
            }
            return 0;
        }
    }
    return -1;
}
#endif

static const char s_find_mode_sens[] =
    "Search Pattern: [Case Sensitive  ]";
static const char s_find_mode_insens[] =
    "Search Pattern: [Case Insensitive]";

static int find_string_forward_cont(void)
{
    uint16_t row = g_cur_doc_row;
    uint8_t first_line = 1;
    uint8_t wrapped = 0;
    char *line_buf = g_scratch_line_buf;

    if (g_search_len == 0) {
        return -1;
    }

    while (1) {
        uint16_t len = fetch_line_to_buffer(row, line_buf, MAX_ACTIVE_PAYLOAD);
        if (len >= g_search_len) {
            uint16_t max_col = len - g_search_len;
            uint16_t cand_col = first_line ? g_cur_col : 0;
            while (cand_col <= max_col) {
                if (wrapped && row == s_search_start_row) {
                    if (s_search_ever_found ?
                        (cand_col >= s_search_start_col) :
                        (cand_col > s_search_start_col)) {
                        return handle_search_not_found();
                    }
                }
                if (match_pattern_at(&line_buf[cand_col])) {
                    return apply_search_match(row, cand_col);
                }
                cand_col++;
            }
        }
        first_line = 0;
        row++;
        if (row >= g_doc_total_lines) {
            if (wrapped) {
                return handle_search_not_found();
            }
            wrapped = 1;
            row = 0;
        }
        if (wrapped && row > s_search_start_row) {
            return handle_search_not_found();
        }
    }
}

int execute_find_forward(void)
{
    s_search_start_row = g_cur_doc_row;
    s_search_start_col = g_cur_col;
    return find_string_forward_cont();
}

static int find_string_backward_cont(void)
{
    uint16_t row = g_cur_doc_row;
    uint8_t first_line = 1;
    uint8_t wrapped = 0;
    char *line_buf = g_scratch_line_buf;

    if (g_search_len == 0) {
        return -1;
    }

    while (1) {
        uint16_t len = fetch_line_to_buffer(row, line_buf, MAX_ACTIVE_PAYLOAD);
        if (len >= g_search_len) {
            uint16_t max_col = len - g_search_len;
            uint16_t cand_col = max_col;
            if (first_line) {
                if (g_cur_col < max_col) {
                    cand_col = g_cur_col;
                }
                s_search_start_col = cand_col;
            }
            while (1) {
                if (wrapped && row == s_search_start_row) {
                    if (s_search_ever_found ?
                        (cand_col <= s_search_start_col) :
                        (cand_col < s_search_start_col)) {
                        return handle_search_not_found();
                    }
                }
                if (match_pattern_at(&line_buf[cand_col])) {
                    return apply_search_match(row, cand_col);
                }
                if (cand_col == 0) {
                    break;
                }
                cand_col--;
            }
        }
        first_line = 0;
        if (row == 0) {
            if (wrapped) {
                return handle_search_not_found();
            }
            wrapped = 1;
            row = g_doc_total_lines - 1;
        } else {
            row--;
        }
        if (wrapped && row < s_search_start_row) {
            return handle_search_not_found();
        }
    }
}

int execute_find_backward(void)
{
    s_search_start_row = g_cur_doc_row;
    s_search_start_col = g_cur_col;
    return find_string_backward_cont();
}

static uint8_t check_start_from_block(char *input)
{
    if (g_block_mode == BLOCK_MODE_OFF) return 0;
    if (g_block_mode == BLOCK_MODE_SELECTING) solidify_block();
    normalize_block_bounds();
    if (g_cur_doc_row < g_norm_start_row || g_cur_doc_row > g_norm_end_row ||
        (g_norm_start_row == g_norm_end_row &&
         (g_cur_col < g_norm_start_col || g_cur_col > g_norm_end_col))) {
        cancel_block();
        return 0;
    }
    g_cur_doc_row = g_norm_start_row;
    g_cur_col = g_norm_start_col;
    g_target_col = g_cur_col;
    {
        uint16_t len = fetch_line_to_buffer(g_cur_doc_row, g_scratch_line_buf,
                                            MAX_ACTIVE_PAYLOAD);
        if (g_norm_start_col < len) {
            uint16_t n = (g_norm_start_row == g_norm_end_row) ?
                (g_norm_end_col - g_norm_start_col) :
                (len - g_norm_start_col);
            if (n > FIND_POPUP_FIELD_LEN) n = FIND_POPUP_FIELD_LEN;
            memcpy(input, &g_scratch_line_buf[g_norm_start_col], n);
            input[n] = '\0';
            return (uint8_t)n;
        }
    }
    return 0;
}

static int prompt_search_box(uint8_t is_rep, char *input, uint8_t cur_len)
{
    uint8_t top, left;
    uint8_t flen = is_rep ? REPLACE_POPUP_FIELD_LEN : FIND_POPUP_FIELD_LEN;
    uint8_t col;
    uint8_t i;
    int k;
#ifndef __CPM__
    uint8_t cur_pos = cur_len;
#endif

    modal_init_7row(&top, &left, is_rep ? "Replace Text" : "Find Text");
    col = left + (is_rep ? 17 : 14);
    modal_draw_row_centered(top + 3, left, 50,
                            is_rep ?
                            "Enter replacement text to substitute for match" :
                            (g_search_case_sensitive ?
                             s_find_mode_sens : s_find_mode_insens));
    hal_console_locate(top + 4, left);
    hal_console_puts(is_rep ? "|  Replace with: [" : "|      Find: [");
    for (i = 0; i < flen; i++) {
        hal_console_putc((i < cur_len) ? input[i] : ' ');
    }
    hal_console_puts(is_rep ? "] |" : "]      |");
    modal_draw_row_centered(top + 5, left, 50,
                            is_rep ?
                            "[Enter]=Replace  [Tab]=Toggle Case  [ESC]=Cancel" :
                            "[Enter]=Find   [Tab]=Toggle Case   [ESC]=Cancel");
    hal_console_locate(top + 4, (uint8_t)(col + cur_len));
    hal_console_show_cursor();

    while (1) {
        while ((k = hal_console_getkey()) <= 0) {
#ifndef __CPM__
            usleep(5000);
#endif
        }
        if (k == KEY_ESC) {
#ifndef __CPM__
            while (hal_console_getkey() > 0) {
                /* Drain trailing escape sequence bytes */
            }
#endif
            restore_editor_screen();
            return -1;
        }
        if (k == KEY_ENTER) {
            restore_editor_screen();
            return (int)cur_len;
        }
        if (k == KEY_TAB || k == KEY_CTRL_I) {
            g_search_case_sensitive ^= 1;
            if (!is_rep) {
                modal_draw_row_centered(top + 3, left, 50,
                                        g_search_case_sensitive ?
                                        s_find_mode_sens : s_find_mode_insens);
            }
#ifdef __CPM__
            hal_console_locate(top + 4, (uint8_t)(col + cur_len));
#else
            hal_console_locate(top + 4, (uint8_t)(col + cur_pos));
#endif
            continue;
        }
#ifdef __CPM__
        if (k == KEY_BACKSPACE || k == 8 || k == KEY_DEL) {
            if (cur_len > 0) {
                cur_len--;
                input[cur_len] = '\0';
                hal_console_puts("\b \b");
            }
            continue;
        }
        if (k >= 32 && k <= 126) {
            if (cur_len < flen) {
                input[cur_len++] = (char)k;
                input[cur_len] = '\0';
                hal_console_putc((char)k);
            }
            continue;
        }
#else
        if (k == KEY_LEFT || k == KEY_CTRL_S) {
            if (cur_pos > 0) cur_pos--;
        } else if (k == KEY_RIGHT) {
            if (cur_pos < cur_len) cur_pos++;
        } else if (k == KEY_HOME || k == KEY_CTRL_A) {
            cur_pos = 0;
        } else if (k == KEY_END || k == KEY_CTRL_E) {
            cur_pos = cur_len;
        } else if (k == KEY_BACKSPACE || k == 8) {
            if (cur_pos > 0) {
                memmove(&input[cur_pos - 1], &input[cur_pos],
                        cur_len - cur_pos + 1);
                cur_pos--;
                cur_len--;
            }
        } else if (k == KEY_DEL || k == KEY_CTRL_D || k == KEY_CTRL_G) {
            if (cur_pos < cur_len) {
                memmove(&input[cur_pos], &input[cur_pos + 1],
                        cur_len - cur_pos);
                cur_len--;
            }
        } else if (k >= 32 && k <= 126 && cur_len < flen) {
            memmove(&input[cur_pos + 1], &input[cur_pos],
                    cur_len - cur_pos + 1);
            input[cur_pos++] = (char)k;
            cur_len++;
        }
        hal_console_locate(top + 4, col);
        for (i = 0; i < flen; i++) {
            hal_console_putc((i < cur_len) ? input[i] : ' ');
        }
        hal_console_locate(top + 4, (uint8_t)(col + cur_pos));
#endif
    }
}

int do_ctrl_f_find(void)
{
    char input[32];
    int len;

    input[0] = '\0';
    len = prompt_search_box(0, input, check_start_from_block(input));
    if (len < 0) {
        return -1;
    }
    if (len > 0) {
        strncpy(g_search_buf, input, sizeof(g_search_buf) - 1);
        g_search_buf[sizeof(g_search_buf) - 1] = '\0';
        g_search_len = (uint16_t)len;
        s_search_ever_found = 0;
    } else if (g_search_len == 0) {
        return -1;
    }
    return execute_find_forward();
}

int do_ctrl_n_find_next(void)
{
    uint16_t prev_row = g_cur_doc_row;
    uint16_t prev_col = g_cur_col;

    if (g_search_len == 0) {
        return do_ctrl_f_find();
    }
    if (g_block_mode == BLOCK_MODE_SOLIDIFIED) {
        s_search_start_row = g_norm_start_row;
        s_search_start_col = g_norm_start_col;
        g_cur_col = g_norm_start_col + 1;
    } else {
        s_search_start_row = g_cur_doc_row;
        s_search_start_col = g_cur_col;
        g_cur_col++;
    }
    if (find_string_forward_cont() == 0) {
        return 0;
    }
    g_cur_doc_row = prev_row;
    g_cur_col = prev_col;
    g_target_col = prev_col;
    locate_cursor();
    return -1;
}

#ifndef __CPM__
int do_find_prev(void)
{
    uint16_t prev_row = g_cur_doc_row;
    uint16_t prev_col = g_cur_col;

    if (g_search_len == 0) {
        return do_ctrl_f_find();
    }
    if (g_block_mode == BLOCK_MODE_SOLIDIFIED) {
        s_search_start_row = g_norm_start_row;
        s_search_start_col = g_norm_start_col;
        g_cur_doc_row = g_norm_start_row;
        g_cur_col = g_norm_start_col;
    } else {
        s_search_start_row = g_cur_doc_row;
        s_search_start_col = g_cur_col;
    }
    step_back_one_char();
    if (find_string_backward_cont() == 0) {
        return 0;
    }
    g_cur_doc_row = prev_row;
    g_cur_col = prev_col;
    g_target_col = prev_col;
    locate_cursor();
    return -1;
}
#endif

int do_ctrl_r_replace(void)
{
    char input[32];
    uint16_t replaced_count = 0;
    uint8_t replace_all = 0;
    uint8_t search_dir = 0;
    int len;

    if (do_ctrl_f_find() < 0) {
        return 0;
    }

    input[0] = '\0';
    len = prompt_search_box(1, input, 0);
    if (len < 0) {
        return 0;
    }
    strncpy(g_replace_buf, input, sizeof(g_replace_buf) - 1);
    g_replace_buf[sizeof(g_replace_buf) - 1] = '\0';
    g_replace_len = (uint16_t)len;
    s_replace_active = 1;
    s_search_start_row = g_norm_start_row;
    s_search_start_col = g_norm_start_col;

    while (1) {
        int ans = MODAL_RES_YES;
        if (!replace_all) {
            uint8_t top, left;
            modal_init_7row(&top, &left, "Replace Confirmation");
            modal_draw_row_centered(top + 3, left, 50,
                                    "Pattern matched");
            modal_draw_row_centered(top + 4, left, 50,
                                    "Replace this occurrence?");
            modal_draw_row_centered(
                top + 5, left, 50,
                "[Y]es  [N]o  [A]ll  [R]everse   [ESC]=Cancel");
            hal_console_locate(top + 4, (uint8_t)(left + 36));
            hal_console_show_cursor();
            while (1) {
                int k;
                while ((k = hal_console_getkey()) <= 0) {
#ifndef __CPM__
                    usleep(5000);
#endif
                }
                if (k >= 'a' && k <= 'z') k -= 32;
                if (k == KEY_ESC) {
#ifndef __CPM__
                    while (hal_console_getkey() > 0) {}
#endif
                    ans = MODAL_RES_CANCEL;
                    break;
                }
                if (k == 'Y' || k == KEY_ENTER) {
                    ans = MODAL_RES_YES;
                    break;
                }
                if (k == 'N') {
                    ans = MODAL_RES_NO;
                    break;
                }
                if (k == 'A') {
                    search_dir = 0;
                    replace_all = 1;
                    ans = MODAL_RES_YES;
                    break;
                }
                if (k == 'R' || k == 'P') {
                    search_dir ^= 1;
                    ans = MODAL_RES_NO;
                    break;
                }
            }
        }
        if (ans == MODAL_RES_CANCEL) {
            break;
        }
        if (ans == MODAL_RES_YES) {
            uint16_t i;
            uint16_t match_col = g_norm_start_col;
            do_delete_block();
            for (i = 0; i < g_replace_len; i++) {
                do_char_insert(g_replace_buf[i]);
            }
            replaced_count++;
            if (search_dir) {
                g_cur_col = match_col;
                step_back_one_char();
            }
        } else {
            g_cur_col = g_norm_start_col;
            if (search_dir) {
                step_back_one_char();
            } else {
                g_cur_col++;
            }
        }
        if ((search_dir ? find_string_backward_cont() :
             find_string_forward_cont()) != 0) {
            break;
        }
    }

    s_replace_active = 0;
    cancel_block();
    show_popup_replace_done(replaced_count);
    restore_editor_screen();
    return 0;
}

void show_popup_not_found(void)
{
    modal_alert("Pattern Not Found", "Pattern not found.", NULL);
}

void show_popup_search_completed(void)
{
    modal_alert("Search Completed", "Search completed.", NULL);
}

void show_popup_replace_done(uint16_t count)
{
    char *p = g_scratch_line_buf + 64;
    strcpy(p, "Replace done: ");
    p = se_append_u16(p + 14, count);
    strcpy(p, " replacement(s).");
    modal_alert("Replace Done", g_scratch_line_buf + 64, NULL);
}
