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

/* Global Search State Variables */
char     g_search_buf[SEARCH_BUF_MAX];
uint16_t g_search_len = 0;
char     g_replace_buf[SEARCH_BUF_MAX];
uint16_t g_replace_len = 0;
uint8_t  g_search_case_sensitive = 1;

static int match_char(char a, char b, uint8_t case_sensitive)
{
    if (case_sensitive) {
        return a == b;
    }
    return tolower((unsigned char)a) == tolower((unsigned char)b);
}

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
            if (!match_char(line[start + i], pattern[i],
                            g_search_case_sensitive)) {
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

static const char s_find_mode_sens[] =
    "Search Pattern: [Case Sensitive  ]";
static const char s_find_mode_insens[] =
    "Search Pattern: [Case Insensitive]";

static void restore_editor_screen(void)
{
    hal_console_hide_cursor();
    g_need_screen_render = 1;
    g_need_status_render = 1;
    render_screen();
    render_status_bar();
    locate_cursor();
}

static void draw_search_field(uint8_t top, uint8_t left, uint8_t is_rep,
                              const char *input, uint8_t cur_len,
                              uint8_t cursor_pos)
{
    uint8_t i;
    uint8_t flen = is_rep ? REPLACE_POPUP_FIELD_LEN : FIND_POPUP_FIELD_LEN;
    uint8_t col = left + (is_rep ? 17 : 14);
    hal_console_locate(top + 4, col);
    for (i = 0; i < flen; i++) {
        hal_console_putc((i < cur_len) ? input[i] : ' ');
    }
    hal_console_puts(is_rep ? "] |" : "]      |");
    hal_console_locate(top + 4, (uint8_t)(col + cursor_pos));
}

int execute_find_forward(void)
{
    uint16_t row;
    char *line_buf = g_scratch_line_buf;
    uint16_t orig_row = g_cur_doc_row;
    uint16_t orig_col = g_cur_col;

    if (g_search_len == 0) {
        return -1;
    }

    for (row = orig_row; row < g_doc_total_lines; row++) {
        uint16_t len = fetch_line_to_buffer(row, line_buf, MAX_ACTIVE_PAYLOAD);
        uint16_t match_col = 0;
        const char *search_ptr = line_buf;
        uint16_t search_len = len;

        if (row == orig_row) {
            uint16_t skip = orig_col;
            if (skip < len) {
                search_ptr += skip;
                search_len -= skip;
            } else {
                continue;
            }
        }

        if (find_string_in_line(g_search_buf, g_search_len,
                                search_ptr, search_len,
                                &match_col) == 0) {
            commit_active_line();
            g_cur_doc_row = row;
            if (row == orig_row) {
                g_cur_col = orig_col + match_col;
            } else {
                g_cur_col = match_col;
            }
            g_target_col = g_cur_col;
            checkout_active_line(g_cur_doc_row);
            if (g_cur_doc_row < g_top_doc_row ||
                g_cur_doc_row >= g_top_doc_row + 20) {
                g_top_doc_row = (g_cur_doc_row > 5) ? (g_cur_doc_row - 5) : 0;
            }
            restore_editor_screen();
            return 0;
        }
    }
    show_popup_not_found();
    return -1;
}

int execute_find_backward(void)
{
    uint16_t r = g_cur_doc_row + 1;
    char *line_buf = g_scratch_line_buf;

    if (g_search_len == 0) {
        return -1;
    }

    while (r > 0) {
        uint16_t len;
        uint16_t match_col = 0;

        r--;
        len = fetch_line_to_buffer(r, line_buf, MAX_ACTIVE_PAYLOAD);
        if (find_string_in_line(g_search_buf, g_search_len,
                                line_buf, len, &match_col) == 0) {
            commit_active_line();
            g_cur_doc_row = r;
            g_cur_col = match_col;
            g_target_col = g_cur_col;
            checkout_active_line(g_cur_doc_row);
            restore_editor_screen();
            return 0;
        }
    }
    show_popup_not_found();
    return -1;
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
        char blk[64];
        uint16_t len = fetch_line_to_buffer(g_cur_doc_row, blk, sizeof(blk));
        if (g_norm_start_col < len) {
            uint16_t n = (g_norm_start_row == g_norm_end_row) ?
                (g_norm_end_col - g_norm_start_col) :
                (len - g_norm_start_col);
            if (n > FIND_POPUP_FIELD_LEN) n = FIND_POPUP_FIELD_LEN;
            memcpy(input, &blk[g_norm_start_col], n);
            input[n] = '\0';
            return (uint8_t)n;
        }
    }
    return 0;
}

static int prompt_search_box(uint8_t is_rep, char *input, uint8_t cur_len)
{
    uint8_t top = (uint8_t)(((g_active_rows - 7) / 2) + 1);
    uint8_t left = (uint8_t)(((g_active_cols - 50) / 2) + 1);
    uint8_t flen = is_rep ? REPLACE_POPUP_FIELD_LEN : FIND_POPUP_FIELD_LEN;
    uint8_t col = left + (is_rep ? 17 : 14);
    uint8_t cursor_pos = cur_len;
    int k;

    hal_console_hide_cursor();
    modal_draw_frame(top, left, 50, 7, is_rep ? "Replace Text" : "Find Text");
    modal_draw_row_centered(top + 3, left, 50,
                            is_rep ?
                            "Enter replacement text to substitute for match" :
                            (g_search_case_sensitive ?
                             s_find_mode_sens : s_find_mode_insens));
    hal_console_locate(top + 4, left);
    hal_console_puts(is_rep ? "|  Replace with: [" : "|      Find: [");
    draw_search_field(top, left, is_rep, input, cur_len, cursor_pos);
    modal_draw_row_centered(top + 5, left, 50,
                            is_rep ?
                            "[Enter]=Replace  [Tab]=Toggle Case  [ESC]=Cancel" :
                            "[Enter]=Find   [Tab]=Toggle Case   [ESC]=Cancel");
    hal_console_locate(top + 4, (uint8_t)(col + cursor_pos));
    hal_console_show_cursor();

    while (1) {
        k = hal_console_getkey();
        if (k == KEY_ESC) {
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
            hal_console_locate(top + 4, (uint8_t)(col + cursor_pos));
            continue;
        }
        if (k == KEY_LEFT) {
            if (cursor_pos > 0) {
                cursor_pos--;
                hal_console_locate(top + 4, (uint8_t)(col + cursor_pos));
            }
            continue;
        }
        if (k == KEY_RIGHT) {
            if (cursor_pos < cur_len) {
                cursor_pos++;
                hal_console_locate(top + 4, (uint8_t)(col + cursor_pos));
            }
            continue;
        }
        if (k == KEY_HOME || k == KEY_CTRL_A) {
            cursor_pos = 0;
            hal_console_locate(top + 4, (uint8_t)(col + cursor_pos));
            continue;
        }
        if (k == KEY_END || k == KEY_CTRL_E) {
            cursor_pos = cur_len;
            hal_console_locate(top + 4, (uint8_t)(col + cursor_pos));
            continue;
        }
        if (k == KEY_BACKSPACE || k == 8) {
            if (cursor_pos > 0) {
                memmove(input + cursor_pos - 1, input + cursor_pos,
                        cur_len - cursor_pos + 1);
                cur_len--;
                cursor_pos--;
                input[cur_len] = '\0';
                draw_search_field(top, left, is_rep, input,
                                  cur_len, cursor_pos);
            }
            continue;
        }
        if (k == KEY_DEL || k == KEY_CTRL_D) {
            if (cursor_pos < cur_len) {
                memmove(input + cursor_pos, input + cursor_pos + 1,
                        cur_len - cursor_pos);
                cur_len--;
                input[cur_len] = '\0';
                draw_search_field(top, left, is_rep, input,
                                  cur_len, cursor_pos);
            }
            continue;
        }
        if (k >= 32 && k <= 126) {
            if (cur_len < flen) {
                memmove(input + cursor_pos + 1, input + cursor_pos,
                        cur_len - cursor_pos + 1);
                input[cursor_pos] = (char)k;
                cur_len++;
                cursor_pos++;
                input[cur_len] = '\0';
                draw_search_field(top, left, is_rep, input,
                                  cur_len, cursor_pos);
            }
            continue;
        }
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
    } else if (g_search_len == 0) {
        return -1;
    }
    return execute_find_forward();
}

int do_ctrl_n_find_next(void)
{
    if (g_search_len == 0) {
        return -1;
    }
    g_cur_col++;
    return execute_find_forward();
}

int do_find_prev(void)
{
    return execute_find_backward();
}

int do_ctrl_r_replace(void)
{
    char input[32];
    uint16_t replaced_count = 0;
    uint8_t replace_all = 0;
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

    while (1) {
        int ans = MODAL_RES_YES;
        if (!replace_all) {
            uint8_t top = (uint8_t)(((g_active_rows - 7) / 2) + 1);
            uint8_t left = (uint8_t)(((g_active_cols - 50) / 2) + 1);
            hal_console_hide_cursor();
            modal_draw_frame(top, left, 50, 7, "Replace Confirmation");
            modal_draw_row_centered(top + 3, left, 50,
                                    "Match found for search pattern in text");
            modal_draw_row_centered(top + 4, left, 50,
                                    "Replace this occurrence?");
            modal_draw_row_centered(top + 5, left, 50,
                                    "[Y]es  [N]o  [A]ll   [ESC]=Cancel");
            hal_console_locate(top + 4, (uint8_t)(left + 36));
            hal_console_show_cursor();
            while (1) {
                int k = hal_console_getkey();
                if (k == KEY_ESC) {
                    ans = MODAL_RES_CANCEL;
                    break;
                }
                if (k == 'y' || k == 'Y' || k == KEY_ENTER) {
                    ans = MODAL_RES_YES;
                    break;
                }
                if (k == 'n' || k == 'N') {
                    ans = MODAL_RES_NO;
                    break;
                }
                if (k == 'a' || k == 'A') {
                    replace_all = 1;
                    ans = MODAL_RES_YES;
                    break;
                }
            }
        }
        if (ans == MODAL_RES_CANCEL) {
            break;
        }
        if (ans == MODAL_RES_YES) {
            uint16_t i;
            checkout_active_line(g_cur_doc_row);
            for (i = 0; i < g_search_len; i++) {
                do_delete();
            }
            for (i = 0; i < g_replace_len; i++) {
                do_char_insert(g_replace_buf[i]);
            }
            replaced_count++;
        } else {
            g_cur_col++;
        }
        if (execute_find_forward() != 0) {
            break;
        }
    }

    show_popup_replace_done(replaced_count);
    restore_editor_screen();
    return 0;
}

void show_popup_not_found(void)
{
    modal_alert("Pattern Not Found", "Pattern not found.",
                "Search pattern not found in file.");
}

void show_popup_search_completed(void)
{
    modal_alert("Search Completed", "Search completed.",
                "No further occurrences found.");
}

void show_popup_replace_done(uint16_t count)
{
    char msg[64];
    snprintf(msg, sizeof(msg), "Replace done: %u replacement(s).",
             (unsigned)count);
    modal_alert("Replace Done", "Search and replace completed.", msg);
}
