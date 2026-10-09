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
#include "../include/search.h"
#include "../include/ui.h"
#include "../include/ui_modal.h"

/* Global Search State Variables */
char     g_search_buf[SEARCH_BUF_MAX] = {0};
uint16_t g_search_len = 0;
char     g_replace_buf[SEARCH_BUF_MAX] = {0};
uint16_t g_replace_len = 0;
uint8_t  g_search_case_sensitive = 0;

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

int execute_find_forward(void)
{
    uint16_t row;
    char line_buf[MAX_ACTIVE_LINE_STRIDE];

    if (g_search_len == 0) {
        return -1;
    }

    for (row = g_cur_doc_row; row < g_doc_total_lines; row++) {
        uint16_t len = fetch_line_to_buffer(row, line_buf, MAX_ACTIVE_PAYLOAD);
        uint16_t match_col = 0;
        const char *search_ptr = line_buf;
        uint16_t search_len = len;

        if (row == g_cur_doc_row) {
            uint16_t skip = g_cur_col + 1;
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
            if (row == g_cur_doc_row && search_ptr != line_buf) {
                g_cur_col = (g_cur_col + 1) + match_col;
            } else {
                g_cur_col = match_col;
            }
            checkout_active_line(g_cur_doc_row);
            if (g_cur_doc_row < g_top_doc_row ||
                g_cur_doc_row >= g_top_doc_row + 20) {
                g_top_doc_row = (g_cur_doc_row > 5) ? (g_cur_doc_row - 5) : 0;
            }
            g_need_screen_render = 1;
            return 0;
        }
    }
    show_popup_not_found();
    return -1;
}

int execute_find_backward(void)
{
    int32_t row;
    char line_buf[MAX_ACTIVE_LINE_STRIDE];

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
            checkout_active_line(g_cur_doc_row);
            g_need_screen_render = 1;
            return 0;
        }
    }
    show_popup_not_found();
    return -1;
}

int do_ctrl_f_find(void)
{
    char input[SEARCH_BUF_MAX] = {0};
    if (g_search_len > 0) {
        snprintf(input, sizeof(input), "%s", g_search_buf);
    }

    if (modal_prompt_text("Find Text", "Search for:",
                          input, FIND_POPUP_FIELD_LEN) == MODAL_RES_OK) {
        if (input[0] != '\0') {
            snprintf(g_search_buf, sizeof(g_search_buf), "%s", input);
            g_search_len = (uint16_t)strlen(g_search_buf);
            return execute_find_forward();
        }
    }
    return 0;
}

int do_ctrl_n_find_next(void)
{
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
    modal_alert("Search Result", "String not found in document.", NULL);
}

void show_popup_search_completed(void)
{
    modal_alert("Search Result", "Search reached end of document.", NULL);
}

void show_popup_replace_done(uint16_t count)
{
    char msg[64];
    snprintf(msg, sizeof(msg), "Replaced %u occurrences.", (unsigned)count);
    modal_alert("Replace Complete", msg, NULL);
}
