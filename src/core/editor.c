/*==============================================================================
 * EDITOR.C: Core Subsystem - Interactive Key Dispatch & Edit Primitives
 *
 * Purpose:
 *   Implements the interactive editor key dispatch loop, cursor navigation,
 *   character insertion, line splitting, line joining, and visual coordinates.
 *   C semantic equivalent to src/core/editor.asm.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include "../include/config.h"
#include "../include/buffer.h"
#include "../include/editor.h"
#include "../include/block.h"
#include "../include/search.h"
#include "../include/ui.h"
#include "../include/ui_modal.h"
#include "../include/ui_browser.h"
#include "../include/file_io.h"
#include "../include/beautify.h"
#include "../include/plugin.h"
#include "../include/hal.h"

/* Global Editor Navigation & State Variables */
uint16_t g_cur_col = 0;
uint16_t g_target_col = 0;
uint16_t g_top_doc_row = 0;
uint16_t g_horiz_pan_offset = 0;
uint8_t  g_insert_mode = 1;
uint8_t  g_editor_exit_flag = 0;
uint8_t  g_action_code = ACTION_EXIT;
static char s_editor_fname[32];

void editor_init(void)
{
    g_cur_col = 0;
    g_target_col = 0;
    g_top_doc_row = 0;
    g_horiz_pan_offset = 0;
    g_insert_mode = 1;
    g_editor_exit_flag = 0;
    g_action_code = ACTION_EXIT;
    checkout_active_line(0);
}

uint16_t calc_visual_col(const char *buf, uint16_t char_col)
{
    uint16_t vis_col = 0;
    uint16_t i;
    uint8_t tab_w = g_config.tab_width ? g_config.tab_width : 8;

    if (!buf) {
        return 0;
    }

    for (i = 0; i < char_col && buf[i] != '\0'; i++) {
        if (buf[i] == '\t') {
            vis_col = (uint16_t)((vis_col / tab_w + 1) * tab_w);
        } else {
            vis_col++;
        }
    }
    return vis_col;
}

void update_horizontal_pan(void)
{
    uint16_t vis_col;
    uint16_t old_pan = g_horiz_pan_offset;
    uint16_t view_width = g_active_cols ? g_active_cols : SCREEN_COLS_80;
    uint16_t view_right;

    vis_col = calc_visual_col(g_active_line_buf, g_cur_col);
    view_right = g_horiz_pan_offset + view_width;

    /* Canonical lookahead edge trigger per Section 6.6:
     * When vis_col == VIEW_RIGHT_COL - 1 and active line continues beyond
     * CUR_COL (character at CUR_COL and next character are non-null),
     * pan viewport right by 40 columns.
     */
    if (vis_col == (view_right - 1) &&
        g_cur_col < g_active_line_len &&
        g_active_line_buf[g_cur_col] != '\0' &&
        (g_cur_col + 1) < g_active_line_len &&
        g_active_line_buf[g_cur_col + 1] != '\0') {
        g_horiz_pan_offset += 40;
        view_right = g_horiz_pan_offset + view_width;
    }

    /* Pan right: shift by +40 quanta until viewport contains vis_col */
    while (vis_col >= view_right) {
        g_horiz_pan_offset += 40;
        view_right = g_horiz_pan_offset + view_width;
    }

    /* Pan left: retreat to multiple of 40 when cursor steps <= pan offset */
    if (g_horiz_pan_offset > 0 && vis_col <= g_horiz_pan_offset) {
        if (vis_col > 0) {
            g_horiz_pan_offset = (uint16_t)(((vis_col - 1) / 40) * 40);
        } else {
            g_horiz_pan_offset = 0;
        }
    }

    if (g_horiz_pan_offset != old_pan) {
        g_need_screen_render = 1;
        g_need_status_render = 1;
    }
}

void locate_cursor(void)
{
    uint16_t screen_row;
    uint16_t vis_col;
    uint8_t  screen_col;

    if (g_cur_doc_row < g_top_doc_row) {
        g_top_doc_row = g_cur_doc_row;
    }

    screen_row = (g_cur_doc_row - g_top_doc_row) + 1;
    vis_col = calc_visual_col(g_active_line_buf, g_cur_col);

    if (vis_col >= g_horiz_pan_offset) {
        vis_col -= g_horiz_pan_offset;
    } else {
        vis_col = 0;
    }

    /* Screen coordinates are 1-based; text starts at screen col 1 */
    screen_col = (uint8_t)(vis_col + 1);
    if (screen_col > g_active_cols) {
        screen_col = g_active_cols;
    }
    hal_console_locate((uint8_t)screen_row, screen_col);
}

int do_char_insert(char c)
{
    uint16_t i;

    checkout_active_line(g_cur_doc_row);

    if (g_cur_col >= MAX_INPUT_LINE_CHARS ||
        g_active_line_len >= MAX_INPUT_LINE_CHARS) {
        return -1;
    }

    /* If cursor beyond current line length, pad with spaces */
    if (g_cur_col > g_active_line_len) {
        for (i = g_active_line_len; i < g_cur_col; i++) {
            g_active_line_buf[i] = ' ';
        }
        g_active_line_len = g_cur_col;
    }

    if (g_insert_mode) {
        for (i = g_active_line_len; i > g_cur_col; i--) {
            g_active_line_buf[i] = g_active_line_buf[i - 1];
        }
        g_active_line_buf[g_cur_col] = c;
        g_active_line_len++;
    } else {
        g_active_line_buf[g_cur_col] = c;
        if (g_cur_col >= g_active_line_len) {
            g_active_line_len = g_cur_col + 1;
        }
    }

    g_active_line_buf[g_active_line_len] = '\0';
    g_cur_col++;
    g_target_col = calc_visual_col(g_active_line_buf, g_cur_col);
    g_doc_modified = 1;
    g_need_line_render = 1;
    g_need_status_render = 1;
    return 0;
}

void do_backspace(void)
{
    uint16_t i;

    if (g_block_mode == BLOCK_MODE_SELECTING) {
        cancel_block();
        g_need_status_render = 1;
        return;
    }

    checkout_active_line(g_cur_doc_row);

    if (g_cur_col > 0) {
        if (g_cur_col <= g_active_line_len) {
            for (i = g_cur_col - 1; i + 1 <= g_active_line_len; i++) {
                g_active_line_buf[i] = g_active_line_buf[i + 1];
            }
            g_active_line_len--;
            g_active_line_buf[g_active_line_len] = '\0';
        }
        g_cur_col--;
        g_target_col = calc_visual_col(g_active_line_buf, g_cur_col);
        g_doc_modified = 1;
        g_need_line_render = 1;
        g_need_status_render = 1;
    } else if (g_cur_doc_row > 0) {
        /* Join current line with previous line */
        char prev_buf[MAX_ACTIVE_LINE_STRIDE];
        uint16_t prev_len = fetch_line_to_buffer(g_cur_doc_row - 1,
                                                 prev_buf,
                                                 MAX_ACTIVE_PAYLOAD);
        uint16_t join_col = prev_len;

        if (prev_len + g_active_line_len <= MAX_INPUT_LINE_CHARS) {
            memcpy(prev_buf + prev_len, g_active_line_buf, g_active_line_len);
            prev_len += g_active_line_len;
            prev_buf[prev_len] = '\0';

            uint16_t target_row = g_cur_doc_row - 1;
            invalidate_active_line();
            delete_doc_row(g_cur_doc_row);
            g_cur_doc_row = target_row;
            checkout_active_line(g_cur_doc_row);

            memcpy(g_active_line_buf, prev_buf, prev_len + 1);
            g_active_line_len = prev_len;
            g_cur_col = join_col;

            if (g_cur_doc_row < g_top_doc_row) {
                g_top_doc_row = g_cur_doc_row;
            }

            g_target_col = calc_visual_col(g_active_line_buf, g_cur_col);
            g_doc_modified = 1;
            g_need_screen_render = 1;
            g_need_status_render = 1;
        }
    }
}

void do_delete(void)
{
    uint16_t i;

    if (g_block_mode != BLOCK_MODE_OFF) {
        if (g_block_mode == BLOCK_MODE_SELECTING) {
            solidify_block();
        }
        do_delete_block();
        g_target_col = calc_visual_col(g_active_line_buf, g_cur_col);
        return;
    }

    checkout_active_line(g_cur_doc_row);

    if (g_cur_col < g_active_line_len) {
        for (i = g_cur_col; i + 1 <= g_active_line_len; i++) {
            g_active_line_buf[i] = g_active_line_buf[i + 1];
        }
        g_active_line_len--;
        g_active_line_buf[g_active_line_len] = '\0';
        g_target_col = calc_visual_col(g_active_line_buf, g_cur_col);
        g_doc_modified = 1;
        g_need_line_render = 1;
        g_need_status_render = 1;
    } else if (g_cur_doc_row + 1 < g_doc_total_lines) {
        /* Pull up next line and join */
        char next_buf[MAX_ACTIVE_LINE_STRIDE];
        uint16_t next_len = fetch_line_to_buffer(g_cur_doc_row + 1,
                                                 next_buf,
                                                 MAX_ACTIVE_PAYLOAD);

        if (g_active_line_len + next_len <= MAX_INPUT_LINE_CHARS) {
            memcpy(g_active_line_buf + g_active_line_len, next_buf, next_len);
            g_active_line_len += next_len;
            g_active_line_buf[g_active_line_len] = '\0';

            delete_doc_row(g_cur_doc_row + 1);
            g_target_col = calc_visual_col(g_active_line_buf, g_cur_col);
            g_doc_modified = 1;
            g_need_screen_render = 1;
        }
    }
}

void do_enter(void)
{
    char tail_buf[MAX_ACTIVE_LINE_STRIDE];
    uint16_t tail_len = 0;

    if (g_block_mode == BLOCK_MODE_SELECTING) {
        solidify_block();
        g_need_status_render = 1;
        return;
    }

    checkout_active_line(g_cur_doc_row);

    if (g_cur_col < g_active_line_len) {
        tail_len = g_active_line_len - g_cur_col;
        memcpy(tail_buf, g_active_line_buf + g_cur_col, tail_len);
        tail_buf[tail_len] = '\0';

        g_active_line_len = g_cur_col;
        g_active_line_buf[g_cur_col] = '\0';
    }

    commit_active_line();
    insert_blank_line(g_cur_doc_row + 1);
    g_cur_doc_row++;
    checkout_active_line(g_cur_doc_row);

    if (tail_len > 0) {
        memcpy(g_active_line_buf, tail_buf, tail_len);
        g_active_line_len = tail_len;
        g_active_line_buf[tail_len] = '\0';
    }

    g_cur_col = 0;
    g_target_col = 0;
    g_doc_modified = 1;
    g_need_screen_render = 1;
}

void cursor_up(void)
{
    if (g_cur_doc_row > 0) {
        commit_active_line();
        g_cur_doc_row--;
        checkout_active_line(g_cur_doc_row);
        adjust_col_to_target(g_target_col);
        if (g_cur_doc_row < g_top_doc_row) {
            g_top_doc_row = g_cur_doc_row;
            g_need_screen_render = 1;
        }
    }
    g_need_status_render = 1;
}

void cursor_down(void)
{
    if (g_cur_doc_row + 1 < g_doc_total_lines) {
        uint8_t vis_lines = g_active_rows ? (g_active_rows - 1) : 23;
        commit_active_line();
        g_cur_doc_row++;
        checkout_active_line(g_cur_doc_row);
        adjust_col_to_target(g_target_col);
        if (g_cur_doc_row >= g_top_doc_row + vis_lines) {
            g_top_doc_row = g_cur_doc_row - vis_lines + 1;
            g_need_screen_render = 1;
        }
    }
    g_need_status_render = 1;
}

void cursor_left(void)
{
    if (g_cur_col > 0) {
        g_cur_col--;
        g_target_col = calc_visual_col(g_active_line_buf, g_cur_col);
    } else if (g_cur_doc_row > 0) {
        commit_active_line();
        g_cur_doc_row--;
        checkout_active_line(g_cur_doc_row);
        g_cur_col = g_active_line_len;
        g_target_col = calc_visual_col(g_active_line_buf, g_cur_col);
        if (g_cur_doc_row < g_top_doc_row) {
            g_top_doc_row = g_cur_doc_row;
            g_need_screen_render = 1;
        }
    }
    g_need_status_render = 1;
}

void cursor_right(void)
{
    checkout_active_line(g_cur_doc_row);
    if (g_cur_col < g_active_line_len) {
        g_cur_col++;
        g_target_col = calc_visual_col(g_active_line_buf, g_cur_col);
    } else if (g_cur_doc_row + 1 < g_doc_total_lines) {
        uint8_t vis_lines = g_active_rows ? (g_active_rows - 1) : 23;
        commit_active_line();
        g_cur_doc_row++;
        checkout_active_line(g_cur_doc_row);
        g_cur_col = 0;
        g_target_col = 0;
        if (g_cur_doc_row >= g_top_doc_row + vis_lines) {
            g_top_doc_row = g_cur_doc_row - vis_lines + 1;
            g_need_screen_render = 1;
        }
    }
    g_need_status_render = 1;
}

void cursor_home(void)
{
    g_cur_col = 0;
    g_target_col = 0;
    g_need_status_render = 1;
}

void cursor_end(void)
{
    checkout_active_line(g_cur_doc_row);
    g_cur_col = g_active_line_len;
    g_target_col = calc_visual_col(g_active_line_buf, g_cur_col);
    g_need_status_render = 1;
}

void page_up(void)
{
    uint8_t page_step = g_active_rows ? (g_active_rows - 2) : 22;
    if (g_cur_doc_row > page_step) {
        g_cur_doc_row -= page_step;
    } else {
        g_cur_doc_row = 0;
    }
    if (g_top_doc_row > page_step) {
        g_top_doc_row -= page_step;
    } else {
        g_top_doc_row = 0;
    }
    checkout_active_line(g_cur_doc_row);
    adjust_col_to_target(g_target_col);
    g_need_screen_render = 1;
}

void page_down(void)
{
    uint8_t page_step = g_active_rows ? (g_active_rows - 2) : 22;
    if (g_cur_doc_row + page_step < g_doc_total_lines) {
        g_cur_doc_row += page_step;
    } else if (g_doc_total_lines > 0) {
        g_cur_doc_row = g_doc_total_lines - 1;
    }
    g_top_doc_row += page_step;
    if (g_top_doc_row >= g_doc_total_lines) {
        g_top_doc_row = (g_doc_total_lines > 1) ? g_doc_total_lines - 1 : 0;
    }
    checkout_active_line(g_cur_doc_row);
    adjust_col_to_target(g_target_col);
    g_need_screen_render = 1;
}

void jump_file_top(void)
{
    g_cur_doc_row = 0;
    g_top_doc_row = 0;
    g_cur_col = 0;
    g_target_col = 0;
    checkout_active_line(0);
    g_need_screen_render = 1;
}

void jump_file_bottom(void)
{
    if (g_doc_total_lines > 0) {
        g_cur_doc_row = g_doc_total_lines - 1;
    } else {
        g_cur_doc_row = 0;
    }
    checkout_active_line(g_cur_doc_row);
    g_cur_col = 0;
    g_target_col = 0;
    g_need_screen_render = 1;
}

void toggle_insert_mode(void)
{
    g_insert_mode = !g_insert_mode;
    g_need_status_render = 1;
}

void adjust_col_to_target(uint16_t target_vis_col)
{
    uint16_t char_idx = 0;
    uint16_t vis_acc = 0;
    uint8_t tab_w = g_config.tab_width ? g_config.tab_width : 8;

    checkout_active_line(g_cur_doc_row);

    while (char_idx < g_active_line_len && vis_acc < target_vis_col) {
        if (g_active_line_buf[char_idx] == '\t') {
            uint16_t spaces = (uint16_t)(tab_w - (vis_acc % tab_w));
            vis_acc += spaces;
            char_idx++;
        } else {
            vis_acc++;
            char_idx++;
        }
    }
    g_cur_col = char_idx;
}

void goto_line(uint16_t target_line)
{
    if (target_line == 0) {
        target_line = 1;
    }
    if (target_line > g_doc_total_lines) {
        target_line = g_doc_total_lines;
    }
    commit_active_line();
    g_cur_doc_row = target_line - 1;
    checkout_active_line(g_cur_doc_row);
    g_cur_col = 0;
    g_target_col = 0;
    if (g_cur_doc_row < g_top_doc_row ||
        g_cur_doc_row >= g_top_doc_row + 20) {
        g_top_doc_row = (g_cur_doc_row > 10) ? (g_cur_doc_row - 10) : 0;
    }
    g_need_screen_render = 1;
}

int editor_handle_key(int key)
{
    switch (key) {
    case KEY_UP: cursor_up(); break;
    case KEY_DOWN: cursor_down(); break;
    case KEY_LEFT: cursor_left(); break;
    case KEY_RIGHT: cursor_right(); break;
    case KEY_HOME: cursor_home(); break;
    case KEY_END: cursor_end(); break;
    case KEY_PGUP: page_up(); break;
    case KEY_PGDN: page_down(); break;
    case KEY_INS: toggle_insert_mode(); break;
    case KEY_DEL: do_delete(); break;
    case KEY_CTRL_A: cursor_home(); break;
    case KEY_CTRL_E: cursor_end(); break;
    case KEY_CTRL_D: do_delete(); break;
    case KEY_CTRL_G: jump_file_bottom(); break;
    case KEY_CTRL_T: jump_file_top(); break;
    case KEY_BACKSPACE: do_backspace(); break;
    case KEY_ENTER: do_enter(); break;
    case KEY_CTRL_B: toggle_block_mode(); break;
    case KEY_CTRL_C:
        if (g_block_mode != BLOCK_MODE_OFF) {
            do_copy_block();
        }
        break;
    case KEY_CTRL_F: do_ctrl_f_find(); break;
    case KEY_CTRL_R: do_ctrl_r_replace(); break;
    case KEY_CTRL_S:
        if (g_block_mode != BLOCK_MODE_OFF) {
            if (g_block_mode == BLOCK_MODE_SELECTING) {
                solidify_block();
            }
            normalize_block_bounds();
            s_editor_fname[0] = '\0';
            if (ui_browser_save_block_dialog(s_editor_fname,
                                             sizeof(s_editor_fname)) ==
                MODAL_RES_OK && s_editor_fname[0]) {
                file_save_block(s_editor_fname, g_norm_start_row,
                                g_norm_end_row, g_file_format);
            }
            g_need_screen_render = 1;
            break;
        }
#ifdef __CPM__
        strncpy(s_editor_fname, g_current_filename,
                sizeof(s_editor_fname) - 1);
        s_editor_fname[sizeof(s_editor_fname) - 1] = '\0';
        if (ui_browser_save_dialog(s_editor_fname,
                                   sizeof(s_editor_fname)) ==
            MODAL_RES_OK && s_editor_fname[0]) {
            file_save(s_editor_fname, g_file_format);
        }
#else
        if (g_current_filename[0] == '\0') {
            s_editor_fname[0] = '\0';
            if (ui_browser_save_dialog(s_editor_fname,
                                       sizeof(s_editor_fname)) ==
                MODAL_RES_OK && s_editor_fname[0]) {
                file_save(s_editor_fname, g_file_format);
            }
        } else {
            file_save(NULL, g_file_format);
        }
#endif
        g_need_screen_render = 1;
        g_need_status_render = 1;
        break;
    case KEY_CTRL_L: {
        char buf[16] = {0};
        if (modal_goto_line(buf, sizeof(buf)) == MODAL_RES_OK && buf[0]) {
            int line_num = atoi(buf);
            if (line_num > 0) {
                goto_line((uint16_t)line_num);
            }
        }
        break;
    }
    case KEY_CTRL_O: {
        if (g_block_mode != BLOCK_MODE_OFF) {
            if (g_block_mode == BLOCK_MODE_SELECTING) {
                solidify_block();
            }
            s_editor_fname[0] = '\0';
            if (ui_browser_insert_dialog(s_editor_fname,
                                         sizeof(s_editor_fname)) ==
                MODAL_RES_OK && s_editor_fname[0]) {
                file_insert(s_editor_fname);
                cancel_block();
                g_need_screen_render = 1;
            }
            break;
        }
        if (modal_confirm_save_changes() != MODAL_RES_OK) {
            break;
        }
        s_editor_fname[0] = '\0';
        if (ui_browser_open_dialog(s_editor_fname,
                                   sizeof(s_editor_fname)) == MODAL_RES_OK &&
            s_editor_fname[0]) {
            file_load(s_editor_fname);
        }
        g_need_screen_render = 1;
        break;
    }
    case KEY_CTRL_P: show_plugin_palette(); break;
    case KEY_CTRL_W:
        if (modal_confirm_save_changes() == MODAL_RES_OK) {
            init_empty_document();
            show_splash_screen();
        }
        break;
    case KEY_CTRL_Y: do_ctrl_y_beautify(); break;
    case KEY_CTRL_Z: plugin_manager_ui(); break;
    case KEY_CTRL_K:
        if (g_block_mode != BLOCK_MODE_OFF) {
            do_block_menu_popup();
        } else {
            show_help_screen();
        }
        break;
    case KEY_ESC:
        if (g_block_mode != BLOCK_MODE_OFF) {
            cancel_block();
            g_need_status_render = 1;
        } else {
            show_splash_screen();
        }
        break;
    case KEY_CTRL_X:
        if (g_block_mode == BLOCK_MODE_SOLIDIFIED) {
            do_move_block();
        } else if (g_block_mode == BLOCK_MODE_SELECTING) {
            solidify_block();
            g_need_status_render = 1;
        }
        break;
    case KEY_CTRL_Q:
        if (modal_confirm_save_changes() == MODAL_RES_OK) {
            g_editor_exit_flag = 1;
        }
        break;
    default:
        if ((key >= 32 && key <= 126) || key == '\t' || key == KEY_TAB) {
            if (g_block_mode == BLOCK_MODE_SELECTING) {
                cancel_block();
                g_need_status_render = 1;
                return 0;
            }
            if (g_block_mode == BLOCK_MODE_SOLIDIFIED) {
                cancel_block();
                g_need_status_render = 1;
            }
            if (key == '\t' || key == KEY_TAB) {
                do_char_insert('\t');
            } else {
                do_char_insert((char)key);
            }
        }
        break;
    }
    if (g_block_mode == BLOCK_MODE_SELECTING) {
        update_block_selection();
    }
    return 0;
}

void editor_main_loop(void)
{
    while (!g_editor_exit_flag) {
        int key;

        if (!hal_console_check_key()) {
            if (g_need_screen_render || g_need_line_render ||
                g_need_status_render) {
                update_horizontal_pan();
                if (g_need_screen_render) {
                    render_screen();
                    g_need_screen_render = 0;
                    g_need_line_render = 0;
                    g_need_status_render = 0;
                } else {
                    if (g_need_line_render) {
                        render_current_line();
                        g_need_line_render = 0;
                    }
                    if (g_need_status_render) {
                        render_status_bar();
                        g_need_status_render = 0;
                    }
                }
                locate_cursor();
            }
        }

        key = hal_console_getkey();
        if (key > 0) {
            editor_handle_key(key);
        }
    }
}
