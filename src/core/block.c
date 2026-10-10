/*==============================================================================
 * BLOCK.C: Core Subsystem - Block Highlighting, Clipboard & Manipulation
 *
 * Purpose:
 *   Implements block selection state machine (Off -> Selecting -> Solidified),
 *   boundary normalization, copy/move/delete primitives, and menu popup.
 *   C semantic equivalent to src/core/block.asm.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#include <string.h>
#include <stdio.h>
#include "../include/config.h"
#include "../include/buffer.h"
#include "../include/editor.h"
#include "../include/block.h"
#include "../include/ui.h"
#include "../include/ui_modal.h"

/* Global Block State Variables */
uint8_t  g_block_mode = BLOCK_MODE_OFF;
uint16_t g_block_anchor_row = 0;
uint16_t g_block_anchor_col = 0;
uint16_t g_block_active_row = 0;
uint16_t g_block_active_col = 0;
uint16_t g_norm_start_row = 0;
uint16_t g_norm_start_col = 0;
uint16_t g_norm_end_row = 0;
uint16_t g_norm_end_col = 0;

/* Clipboard Storage */
#ifndef CLIPBOARD_MAX_CHARS
#define CLIPBOARD_MAX_CHARS 32768
#endif
static char     s_clipboard_buf[CLIPBOARD_MAX_CHARS];
static uint16_t s_clipboard_len = 0;

void start_new_block_at_cursor(void)
{
    g_block_mode = BLOCK_MODE_SELECTING;
    g_block_anchor_row = g_cur_doc_row;
    g_block_anchor_col = g_cur_col;
    g_block_active_row = g_cur_doc_row;
    g_block_active_col = g_cur_col;
    normalize_block_bounds();
    g_need_screen_render = 1;
}

void cancel_block(void)
{
    g_block_mode = BLOCK_MODE_OFF;
    g_need_screen_render = 1;
}

void solidify_block(void)
{
    if (g_block_mode == BLOCK_MODE_SELECTING) {
        g_block_mode = BLOCK_MODE_SOLIDIFIED;
        g_block_active_row = g_cur_doc_row;
        g_block_active_col = g_cur_col;
        normalize_block_bounds();
        g_need_screen_render = 1;
    }
}

void toggle_block_mode(void)
{
    if (g_block_mode != BLOCK_MODE_OFF) {
        cancel_block();
    } else {
        start_new_block_at_cursor();
    }
    g_need_status_render = 1;
}

void normalize_block_bounds(void)
{
    if (g_block_mode == BLOCK_MODE_SELECTING) {
        g_block_active_row = g_cur_doc_row;
        g_block_active_col = g_cur_col;
    }
    if (g_block_anchor_row < g_block_active_row) {
        g_norm_start_row = g_block_anchor_row;
        g_norm_start_col = g_block_anchor_col;
        g_norm_end_row = g_block_active_row;
        g_norm_end_col = g_block_active_col;
    } else if (g_block_anchor_row > g_block_active_row) {
        g_norm_start_row = g_block_active_row;
        g_norm_start_col = g_block_active_col;
        g_norm_end_row = g_block_anchor_row;
        g_norm_end_col = g_block_anchor_col;
    } else {
        g_norm_start_row = g_block_anchor_row;
        g_norm_end_row = g_block_anchor_row;
        if (g_block_anchor_col <= g_block_active_col) {
            g_norm_start_col = g_block_anchor_col;
            g_norm_end_col = g_block_active_col;
        } else {
            g_norm_start_col = g_block_active_col;
            g_norm_end_col = g_block_anchor_col;
        }
    }
}

void update_block_selection(void)
{
    if (g_block_mode == BLOCK_MODE_SELECTING) {
        g_block_active_row = g_cur_doc_row;
        g_block_active_col = g_cur_col;
        normalize_block_bounds();
        g_need_screen_render = 1;
        g_need_status_render = 1;
    }
}

int check_cursor_in_block(uint16_t row, uint16_t col)
{
    if (g_block_mode == BLOCK_MODE_OFF) {
        return 0;
    }
    normalize_block_bounds();
    if (row < g_norm_start_row || row > g_norm_end_row) {
        return 0;
    }
    if (g_norm_start_row == g_norm_end_row) {
        return (col >= g_norm_start_col && col < g_norm_end_col);
    }
    if (row == g_norm_start_row) {
        return (col >= g_norm_start_col);
    }
    if (row == g_norm_end_row) {
        return (col < g_norm_end_col);
    }
    return 1;
}

int get_line_block_range(uint16_t row, uint16_t *start_col, uint16_t *end_col)
{
    if (g_block_mode == BLOCK_MODE_OFF || !start_col || !end_col) {
        return 0;
    }
    normalize_block_bounds();
    if (row < g_norm_start_row || row > g_norm_end_row) {
        return 0;
    }
    if (g_norm_start_row == g_norm_end_row) {
        *start_col = g_norm_start_col;
        *end_col = g_norm_end_col;
        return 1;
    }
    if (row == g_norm_start_row) {
        *start_col = g_norm_start_col;
        *end_col = 0xFFFF;
        return 1;
    }
    if (row == g_norm_end_row) {
        *start_col = 0;
        *end_col = g_norm_end_col;
        return 1;
    }
    *start_col = 0;
    *end_col = 0xFFFF;
    return 1;
}

int do_copy_block(void)
{
    uint16_t row;
    char line_buf[MAX_ACTIVE_LINE_STRIDE];

    if (g_block_mode == BLOCK_MODE_OFF) {
        return -1;
    }
    normalize_block_bounds();
    s_clipboard_len = 0;

    for (row = g_norm_start_row; row <= g_norm_end_row; row++) {
        uint16_t len = fetch_line_to_buffer(row, line_buf, MAX_ACTIVE_PAYLOAD);
        uint16_t c_start = 0;
        uint16_t c_end = len;

        if (row == g_norm_start_row) {
            c_start = g_norm_start_col;
            if (c_start > len) c_start = len;
        }
        if (row == g_norm_end_row) {
            c_end = g_norm_end_col;
            if (c_end > len) c_end = len;
        }

        if (c_end > c_start) {
            uint16_t span = c_end - c_start;
            if (s_clipboard_len + span + 2 < CLIPBOARD_MAX_CHARS) {
                memcpy(s_clipboard_buf + s_clipboard_len,
                       line_buf + c_start, span);
                s_clipboard_len += span;
            }
        }
        if (row < g_norm_end_row &&
            s_clipboard_len + 1 < CLIPBOARD_MAX_CHARS) {
            s_clipboard_buf[s_clipboard_len++] = '\n';
        }
    }
    s_clipboard_buf[s_clipboard_len] = '\0';
    return 0;
}

int do_delete_block(void)
{
    uint16_t row;

    if (g_block_mode == BLOCK_MODE_OFF) {
        return -1;
    }
    normalize_block_bounds();

    if (g_norm_start_row == g_norm_end_row) {
        checkout_active_line(g_norm_start_row);
        if (g_norm_start_col < g_active_line_len) {
            uint16_t cut_end = g_norm_end_col;
            if (cut_end > g_active_line_len) cut_end = g_active_line_len;
            if (cut_end > g_norm_start_col) {
                uint16_t shift_len = g_active_line_len - cut_end;
                memmove(g_active_line_buf + g_norm_start_col,
                        g_active_line_buf + cut_end, shift_len);
                g_active_line_len -= (cut_end - g_norm_start_col);
                g_active_line_buf[g_active_line_len] = '\0';
            }
        }
    } else {
        /* Multi-line deletion */
        for (row = g_norm_end_row; row > g_norm_start_row; row--) {
            delete_doc_row(row);
        }
        checkout_active_line(g_norm_start_row);
        if (g_norm_start_col < g_active_line_len) {
            g_active_line_len = g_norm_start_col;
            g_active_line_buf[g_active_line_len] = '\0';
        }
    }

    cancel_block();
    g_cur_doc_row = g_norm_start_row;
    g_cur_col = g_norm_start_col;
    g_doc_modified = 1;
    g_need_screen_render = 1;
    return 0;
}

int do_move_block(void)
{
    if (do_copy_block() < 0) {
        return -1;
    }
    do_delete_block();
    /* Paste clipboard at cursor */
    if (s_clipboard_len > 0) {
        uint16_t i;
        for (i = 0; i < s_clipboard_len; i++) {
            if (s_clipboard_buf[i] == '\n') {
                do_enter();
            } else {
                do_char_insert(s_clipboard_buf[i]);
            }
        }
    }
    return 0;
}

int do_block_menu_popup(void)
{
    const char *title = "Block Menu";
    const char *msg = "Choose block operation:";
    int res = modal_confirm_3btn(title, msg, "Copy", "Move", "Delete");

    if (res == MODAL_RES_OK) {
        do_copy_block();
    } else if (res == MODAL_RES_NO) {
        do_move_block();
    } else if (res == MODAL_RES_DISCARD) {
        do_delete_block();
    }
    return 0;
}
