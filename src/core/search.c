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
char     g_search_buf[SEARCH_BUF_MAX] = {0};
uint16_t g_search_len = 0;
char     g_replace_buf[SEARCH_BUF_MAX] = {0};
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

static const char s_border_50[] =
    "+------------------------------------------------+";
static const char s_find_title[] =
    "|                   Find Text                    |";
static const char s_find_mode_sens[] =
    "|       Search Pattern: [Case Sensitive  ]       |";
static const char s_find_mode_insens[] =
    "|       Search Pattern: [Case Insensitive]       |";
static const char s_find_keys[] =
    "| [Enter]=Find   [Tab]=Toggle Case   [ESC]=Cancel |";
static const char s_find_close[] =
    "]      |";

static void restore_editor_screen(void)
{
    hal_console_hide_cursor();
    g_need_screen_render = 1;
    g_need_status_render = 1;
    render_screen();
    render_status_bar();
    locate_cursor();
}

static void draw_find_field(uint8_t top, uint8_t left,
                            const char *input, uint8_t cur_len)
{
    uint8_t i;
    hal_console_locate(top + 4, (uint8_t)(left + 14));
    for (i = 0; i < FIND_POPUP_FIELD_LEN; i++) {
        hal_console_putc((i < cur_len) ? input[i] : ' ');
    }
    hal_console_puts(s_find_close);
    hal_console_locate(top + 4, (uint8_t)(left + 14 + cur_len));
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
    int32_t row;
    char *line_buf = g_scratch_line_buf;

    if (g_search_len == 0) {
        return -1;
    }

    for (row = (int32_t)g_cur_doc_row; row >= 0; row--) {
        uint16_t len = fetch_line_to_buffer((uint16_t)row, line_buf,
                                            MAX_ACTIVE_PAYLOAD);
        uint16_t match_col = 0;

        if (find_string_in_line(g_search_buf, g_search_len,
                                line_buf, len, &match_col) == 0) {
            commit_active_line();
            g_cur_doc_row = (uint16_t)row;
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

int do_ctrl_f_find(void)
{
    char input[SEARCH_BUF_MAX] = {0};
    uint8_t top = (uint8_t)(((g_active_rows - 7) / 2) + 1);
    uint8_t left = (uint8_t)(((g_active_cols - 50) / 2) + 1);
    uint8_t cur_len = check_start_from_block(input);
    uint8_t row;
    int k;

    hal_console_hide_cursor();

    /* Draw 50x7 Find Text popup frame */
    for (row = 0; row < 7; row++) {
        hal_console_locate((uint8_t)(top + row), left);
        if (row == 0 || row == 2 || row == 6) {
            hal_console_puts(s_border_50);
        } else if (row == 1) {
            hal_console_puts(s_find_title);
        } else if (row == 3) {
            hal_console_puts(g_search_case_sensitive ?
                             s_find_mode_sens : s_find_mode_insens);
        } else if (row == 4) {
            hal_console_puts("|      Find: [");
            draw_find_field(top, left, input, cur_len);
        } else {
            hal_console_puts(s_find_keys);
        }
    }

    hal_console_locate(top + 4, (uint8_t)(left + 14 + cur_len));
    hal_console_show_cursor();

    while (1) {
        k = hal_console_getkey();
        if (k == KEY_ESC) {
            restore_editor_screen();
            return -1;
        }
        if (k == KEY_ENTER) {
            if (cur_len > 0) {
                snprintf(g_search_buf, sizeof(g_search_buf), "%s", input);
                g_search_len = (uint16_t)cur_len;
            } else if (g_search_len == 0) {
                restore_editor_screen();
                return -1;
            }
            restore_editor_screen();
            return execute_find_forward();
        }
        if (k == KEY_TAB || k == KEY_CTRL_I) {
            g_search_case_sensitive ^= 1;
            hal_console_locate(top + 3, left);
            hal_console_puts(g_search_case_sensitive ?
                             s_find_mode_sens : s_find_mode_insens);
            hal_console_locate(top + 4, (uint8_t)(left + 14 + cur_len));
            continue;
        }
        if (k == KEY_BACKSPACE || k == KEY_DEL) {
            if (cur_len > 0) {
                cur_len--;
                input[cur_len] = '\0';
                draw_find_field(top, left, input, cur_len);
            }
            continue;
        }
        if (k >= 32 && k <= 126) {
            if (cur_len < FIND_POPUP_FIELD_LEN) {
                input[cur_len++] = (char)k;
                input[cur_len] = '\0';
                draw_find_field(top, left, input, cur_len);
            }
            continue;
        }
    }
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
    char find_input[SEARCH_BUF_MAX] = {0};
    char repl_input[SEARCH_BUF_MAX] = {0};
    uint16_t replaced_count = 0;

    if (modal_prompt_text("Replace Text", "Search for:",
                          find_input, REPLACE_POPUP_FIELD_LEN) !=
        MODAL_RES_OK) {
        return 0;
    }
    if (find_input[0] == '\0') {
        return 0;
    }

    if (modal_prompt_text("Replace Text", "Replace with:",
                          repl_input, REPLACE_POPUP_FIELD_LEN) !=
        MODAL_RES_OK) {
        return 0;
    }

    snprintf(g_search_buf, sizeof(g_search_buf), "%s", find_input);
    g_search_len = (uint16_t)strlen(g_search_buf);
    snprintf(g_replace_buf, sizeof(g_replace_buf), "%s", repl_input);
    g_replace_len = (uint16_t)strlen(g_replace_buf);

    while (execute_find_forward() == 0) {
        int ans = modal_confirm("Replace Match?",
                                "Replace this occurrence?",
                                "Replace", "Skip");
        if (ans == MODAL_RES_OK) {
            uint16_t i;
            checkout_active_line(g_cur_doc_row);
            for (i = 0; i < g_search_len; i++) {
                do_delete();
            }
            for (i = 0; i < g_replace_len; i++) {
                do_char_insert(g_replace_buf[i]);
            }
            replaced_count++;
        } else if (ans == MODAL_RES_CANCEL) {
            break;
        }
    }

    show_popup_replace_done(replaced_count);
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
