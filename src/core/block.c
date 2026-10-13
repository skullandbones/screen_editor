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
#include "../include/ui_browser.h"
#include "../include/file_io.h"
#include "../include/hal.h"

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

static int copy_block_to_clipboard(void)
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

int do_copy_block(void)
{
    uint16_t orig_cur_row;
    uint16_t orig_cur_col;
    uint16_t lines_added = 0;
    uint16_t i;

    if (g_block_mode == BLOCK_MODE_OFF) {
        return -1;
    }
    if (g_block_mode == BLOCK_MODE_SELECTING) {
        solidify_block();
    }
    normalize_block_bounds();

    /* If cursor is inside block: ignore copy! */
    if (check_cursor_in_block(g_cur_doc_row, g_cur_col)) {
        return 0;
    }

    if (copy_block_to_clipboard() != 0 || s_clipboard_len == 0) {
        return 0;
    }

    for (i = 0; i < s_clipboard_len; i++) {
        if (s_clipboard_buf[i] == '\n') {
            lines_added++;
        }
    }

    orig_cur_row = g_cur_doc_row;
    orig_cur_col = g_cur_col;

    /* Paste the extracted block at current cursor */
    for (i = 0; i < s_clipboard_len; i++) {
        if (s_clipboard_buf[i] == '\n') {
            do_enter();
        } else {
            do_char_insert(s_clipboard_buf[i]);
        }
    }

    /* If copied before or on the block, adjust block coordinates */
    if (lines_added > 0) {
        if (orig_cur_row < g_norm_start_row) {
            g_block_anchor_row += lines_added;
            g_block_active_row += lines_added;
            normalize_block_bounds();
        }
    } else {
        /* Single-line block */
        if (orig_cur_row == g_norm_start_row &&
            orig_cur_col <= g_norm_start_col) {
            g_block_anchor_col += s_clipboard_len;
            g_block_active_col += s_clipboard_len;
            normalize_block_bounds();
        }
    }

    g_doc_modified = 1;
    g_need_screen_render = 1;
    g_need_status_render = 1;
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
                commit_active_line();
            }
        }
    } else {
        /* Multi-line deletion */
        char tail_buf[MAX_ACTIVE_PAYLOAD];
        uint16_t tail_len = fetch_line_to_buffer(g_norm_end_row, tail_buf,
                                                 sizeof(tail_buf));
        uint16_t tail_start = g_norm_end_col;
        if (tail_start > tail_len) tail_start = tail_len;

        for (row = g_norm_end_row; row > g_norm_start_row; row--) {
            delete_doc_row(row);
        }
        checkout_active_line(g_norm_start_row);
        if (g_norm_start_col < g_active_line_len) {
            g_active_line_len = g_norm_start_col;
        }
        if (tail_len > tail_start) {
            uint16_t copy_cnt = tail_len - tail_start;
            if (g_active_line_len + copy_cnt < MAX_INPUT_LINE_CHARS) {
                memcpy(g_active_line_buf + g_active_line_len,
                       tail_buf + tail_start, copy_cnt);
                g_active_line_len += copy_cnt;
            }
        }
        g_active_line_buf[g_active_line_len] = '\0';
        commit_active_line();
    }

    cancel_block();
    g_cur_doc_row = g_norm_start_row;
    g_cur_col = g_norm_start_col;
    g_doc_modified = 1;
    g_need_screen_render = 1;
    g_need_status_render = 1;
    return 0;
}

uint16_t get_clipboard_len(void)
{
    return s_clipboard_len;
}

const char *get_clipboard_buffer(void)
{
    return s_clipboard_buf;
}

int do_paste_block(void)
{
    uint16_t i;

    if (s_clipboard_len == 0) {
        return 0;
    }
    cancel_block();
    for (i = 0; i < s_clipboard_len; i++) {
        if (s_clipboard_buf[i] == '\n') {
            do_enter();
        } else {
            do_char_insert(s_clipboard_buf[i]);
        }
    }
    g_doc_modified = 1;
    g_need_screen_render = 1;
    g_need_status_render = 1;
    return 0;
}

int do_cut_block(void)
{
    if (copy_block_to_clipboard() < 0) {
        return -1;
    }
    return do_delete_block();
}

int do_move_block(void)
{
    uint16_t move_dest_row;
    uint16_t move_dest_col;
    uint16_t src_start_row;
    uint16_t src_start_col;
    uint16_t src_end_row;
    uint16_t src_end_col;
    uint8_t  dest_is_before = 0;

    if (g_block_mode != BLOCK_MODE_SOLIDIFIED) {
        return -1;
    }
    normalize_block_bounds();

    /* Cannot move block into itself */
    if (check_cursor_in_block(g_cur_doc_row, g_cur_col)) {
        return 0;
    }

    move_dest_row = g_cur_doc_row;
    move_dest_col = g_cur_col;

    src_start_row = g_norm_start_row;
    src_start_col = g_norm_start_col;
    src_end_row = g_norm_end_row;
    src_end_col = g_norm_end_col;

    if (move_dest_row < src_start_row ||
        (move_dest_row == src_start_row && move_dest_col < src_start_col)) {
        dest_is_before = 1;
    }

    /* 1. Copy block to destination */
    if (do_copy_block() != 0) {
        return -1;
    }

    /* 2. Delete original block */
    if (dest_is_before) {
        do_delete_block();
        g_cur_doc_row = move_dest_row;
        g_cur_col = move_dest_col;
    } else {
        g_block_anchor_row = src_start_row;
        g_block_anchor_col = src_start_col;
        g_block_active_row = src_end_row;
        g_block_active_col = src_end_col;
        g_block_mode = BLOCK_MODE_SOLIDIFIED;
        normalize_block_bounds();
        do_delete_block();

        if (src_start_row == src_end_row) {
            if (move_dest_row == src_start_row) {
                uint16_t blk_len = src_end_col - src_start_col;
                g_cur_doc_row = move_dest_row;
                g_cur_col = (move_dest_col >= blk_len) ?
                            (move_dest_col - blk_len) : 0;
            } else {
                g_cur_doc_row = move_dest_row;
                g_cur_col = move_dest_col;
            }
        } else {
            uint16_t k = src_end_row - src_start_row;
            g_cur_doc_row = (move_dest_row >= k) ?
                            (move_dest_row - k) : 0;
            g_cur_col = move_dest_col;
        }
    }

    /* Restore solidified block around the moved text */
    g_block_mode = BLOCK_MODE_SOLIDIFIED;
    g_block_anchor_row = g_cur_doc_row;
    g_block_anchor_col = g_cur_col;
    if (src_start_row == src_end_row) {
        g_block_active_row = g_cur_doc_row;
        g_block_active_col = g_cur_col + (src_end_col - src_start_col);
    } else {
        uint16_t k = src_end_row - src_start_row;
        g_block_active_row = g_cur_doc_row + k;
        g_block_active_col = src_end_col;
    }
    normalize_block_bounds();

    g_target_col = g_cur_col;
    g_doc_modified = 1;
    g_need_screen_render = 1;
    g_need_status_render = 1;
    return 0;
}

int do_block_menu_popup(void)
{
    uint8_t width = 50;
    uint8_t height = 7;
    uint8_t top = (uint8_t)(((g_active_rows - height) / 2) + 1);
    uint8_t left = (uint8_t)(((g_active_cols - width) / 2) + 1);
    char line4[52];
    char metrics[32];
    const char *pre;
    size_t mlen;
    int pad;
    int key;
    uint8_t c;

    normalize_block_bounds();

    hal_console_hide_cursor();

    /* Line 1: Top border */
    hal_console_locate(top, left);
    hal_console_putc('+');
    for (c = 1; c < width - 1; c++) {
        hal_console_putc('-');
    }
    hal_console_putc('+');

    /* Line 2: Title */
    hal_console_locate(top + 1, left);
    hal_console_puts("|                Block Operations                |");

    /* Line 3: Separator border */
    hal_console_locate(top + 2, left);
    hal_console_putc('+');
    for (c = 1; c < width - 1; c++) {
        hal_console_putc('-');
    }
    hal_console_putc('+');

    /* Line 4: Dynamic Selection / Block count */
    pre = (g_block_mode == BLOCK_MODE_SOLIDIFIED) ?
          "Marked Block: " : "Selection: ";
    if (g_norm_start_row == g_norm_end_row) {
        uint16_t chars = (g_norm_end_col >= g_norm_start_col) ?
                         (g_norm_end_col - g_norm_start_col) : 0;
        snprintf(metrics, sizeof(metrics), "%s%u %s",
                 pre, (unsigned)chars, (chars == 1) ? "char" : "chars");
    } else {
        uint16_t lines = g_norm_end_row - g_norm_start_row + 1;
        snprintf(metrics, sizeof(metrics), "%s%u %s",
                 pre, (unsigned)lines, (lines == 1) ? "line" : "lines");
    }
    mlen = strlen(metrics);
    pad = (48 - (int)mlen) / 2;
    if (pad < 0) {
        pad = 0;
    }
    line4[0] = '|';
    memset(line4 + 1, ' ', 48);
    memcpy(line4 + 1 + pad, metrics, mlen);
    line4[49] = '|';
    line4[50] = '\0';
    hal_console_locate(top + 3, left);
    hal_console_puts(line4);

    /* Line 5: Primary Actions (Dynamic vs Solidified) */
    hal_console_locate(top + 4, left);
    if (g_block_mode == BLOCK_MODE_SOLIDIFIED) {
        hal_console_puts(
            "|      [^C]=Copy Block      [^X]=Move Block      |"
        );
    } else {
        hal_console_puts(
            "|  [Enter]=Lock/Set    [^C]=Copy    [^X]=Move    |"
        );
    }

    /* Line 6: Commands */
    hal_console_locate(top + 5, left);
    hal_console_puts(
        "|  [^D]=Del  [^S]=Save  [^B]=Clear  [ESC]=Close  |"
    );

    /* Line 7: Bottom border */
    hal_console_locate(top + 6, left);
    hal_console_putc('+');
    for (c = 1; c < width - 1; c++) {
        hal_console_putc('-');
    }
    hal_console_putc('+');

    while (1) {
        key = hal_console_getkey();
        if (key == KEY_ESC) {
            break;
        } else if (key == KEY_ENTER) {
            solidify_block();
            break;
        } else if (key == KEY_CTRL_B || key == 'b' || key == 'B') {
            cancel_block();
            break;
        } else if (key == KEY_CTRL_C || key == 'c' || key == 'C') {
            solidify_block();
            do_copy_block();
            break;
        } else if (key == KEY_CTRL_X || key == 'x' || key == 'X' ||
                   key == 'm' || key == 'M') {
            solidify_block();
            do_move_block();
            break;
        } else if (key == KEY_CTRL_D || key == 'd' || key == 'D' ||
                   key == KEY_DEL) {
            solidify_block();
            do_delete_block();
            break;
        } else if (key == KEY_CTRL_S || key == 's' || key == 'S') {
            char fname[128];
            solidify_block();
            normalize_block_bounds();
            fname[0] = '\0';
            if (ui_browser_save_block_dialog(fname, sizeof(fname)) ==
                MODAL_RES_OK && fname[0]) {
                file_save_block(fname, g_norm_start_row,
                                g_norm_end_row, g_config.save_format);
            }
            break;
        } else if (key == KEY_CTRL_O || key == 'r' || key == 'R') {
            char fname[128];
            solidify_block();
            fname[0] = '\0';
            if (ui_browser_insert_dialog(fname, sizeof(fname)) ==
                MODAL_RES_OK && fname[0]) {
                file_insert(fname);
                cancel_block();
            }
            break;
        }
    }

    g_need_screen_render = 1;
    g_need_status_render = 1;
    render_screen();
    render_status_bar();
    hal_console_show_cursor();
    locate_cursor();
    return 0;
}
