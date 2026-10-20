/*==============================================================================
 * UI_RENDER.C: Core Subsystem - Screen Drawing, Status Bar & Tilde Discipline
 *
 * Purpose:
 *   Implements full document window repaints, line rendering with tab
 *   expansion and horizontal panning, column 0 tilde margin discipline,
 *   and inverse video status bar rendering matching docs/UI_UX_DESIGN.md.
 *   C semantic equivalent to src/core/ui_render.asm.
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
#include "../include/memory.h"
#include "../include/file_io.h"
#include "../include/ui.h"
#include "../include/ui_modal.h"
#include "../include/ui_browser.h"
#include "../include/plugin.h"
#include "../include/hal.h"
#ifdef __CPM__
#include <cpm.h>
#endif

/* Global Display State Variables */
uint8_t g_active_cols = SCREEN_COLS_80;
uint8_t g_active_rows = SCREEN_ROWS_24;
uint8_t g_is_splash_screen = 0;
uint8_t g_need_screen_render = 1;
uint8_t g_need_line_render = 0;
uint8_t g_need_status_render = 1;
#ifdef __CPM__
char    g_status_msg[32];
#else
char    g_status_msg[80];
#endif

void ui_init(void)
{
    if (g_config.screen_mode == MODE_120X40) {
        g_active_cols = SCREEN_COLS_120;
        g_active_rows = SCREEN_ROWS_40;
#ifndef __CPM__
    } else if (g_config.screen_mode == MODE_NATIVE) {
        uint8_t ncols = 0, nrows = 0;
        if (hal_console_get_native_size(&ncols, &nrows) == 0 &&
            ncols >= SCREEN_COLS_80 && nrows >= SCREEN_ROWS_24) {
            g_active_cols = ncols;
            g_active_rows = nrows;
        } else {
            g_active_cols = SCREEN_COLS_80;
            g_active_rows = SCREEN_ROWS_24;
        }
#endif
    } else {
        g_active_cols = SCREEN_COLS_80;
        g_active_rows = SCREEN_ROWS_24;
    }
    hal_console_init();
    clear_screen();
}

void clear_screen(void)
{
    hal_console_clear();
}

void set_status_msg(const char *msg)
{
    g_status_msg[0] = '\0';
    if (msg && *msg) {
        modal_show_notification("Notice", msg);
    }
}

static void render_row_content(uint8_t screen_row, uint16_t doc_row)
{
    char *line_buf = g_scratch_line_buf;
    uint16_t len;
    uint16_t vis_col = 0;
    uint16_t i;
    uint8_t tab_w = g_config.tab_width ? g_config.tab_width : 8;
    uint8_t max_content_cols = g_active_cols;

    hal_console_locate(screen_row, 1);

    if (doc_row >= g_doc_total_lines) {
        /* Beyond EOF: Column 0 Tilde Margin Discipline */
        hal_console_putc('~');
        hal_console_clear_eol();
        return;
    }

    len = fetch_line_to_buffer(doc_row, line_buf, MAX_ACTIVE_PAYLOAD);

    {
        uint8_t in_inv = 0;
        for (i = 0; i < len && vis_col < g_horiz_pan_offset + max_content_cols;
             i++) {
            char c = line_buf[i];
            int in_blk = check_cursor_in_block(doc_row, i);
            if (c == '\t') {
                uint16_t next_tab = (uint16_t)((vis_col / tab_w + 1) * tab_w);
                while (vis_col < next_tab &&
                       vis_col < g_horiz_pan_offset + max_content_cols) {
                    if (vis_col >= g_horiz_pan_offset) {
                        int cont_hl = (g_block_mode == BLOCK_MODE_OFF &&
                                       vis_col + 1 == g_horiz_pan_offset +
                                                      max_content_cols &&
                                       (vis_col + 1 < next_tab || i + 1 < len));
                        uint8_t want_inv = (uint8_t)(in_blk || cont_hl);
                        if (want_inv != in_inv) {
                            if (want_inv) hal_console_inverse_on();
                            else hal_console_inverse_off();
                            in_inv = want_inv;
                        }
                        hal_console_putc(' ');
                    }
                    vis_col++;
                }
            } else {
                if (vis_col >= g_horiz_pan_offset) {
                    int cont_hl = (g_block_mode == BLOCK_MODE_OFF &&
                                   vis_col + 1 == g_horiz_pan_offset +
                                                  max_content_cols &&
                                   i + 1 < len);
                    uint8_t want_inv = (uint8_t)(in_blk || cont_hl);
                    if (want_inv != in_inv) {
                        if (want_inv) hal_console_inverse_on();
                        else hal_console_inverse_off();
                        in_inv = want_inv;
                    }
                    hal_console_putc(c);
                }
                vis_col++;
            }
        }
        if (in_inv) {
            hal_console_inverse_off();
        }
    }
    hal_console_clear_eol();
}

void render_screen(void)
{
    uint8_t r;
    uint8_t text_rows = g_active_rows - 1;

    hal_console_hide_cursor();
    for (r = 1; r <= text_rows; r++) {
        uint16_t doc_row = g_top_doc_row + (r - 1);
        render_row_content(r, doc_row);
    }
    render_status_bar();
    hal_console_show_cursor();
}

void render_current_line(void)
{
    if (g_cur_doc_row >= g_top_doc_row &&
        g_cur_doc_row < g_top_doc_row + (g_active_rows - 1)) {
        uint8_t screen_row = (uint8_t)((g_cur_doc_row - g_top_doc_row) + 1);
        hal_console_hide_cursor();
        render_row_content(screen_row, g_cur_doc_row);
        hal_console_show_cursor();
    }
}

void render_buffer_line(uint16_t row)
{
    if (row >= g_top_doc_row &&
        row < g_top_doc_row + (g_active_rows - 1)) {
        uint8_t screen_row = (uint8_t)((row - g_top_doc_row) + 1);
        hal_console_hide_cursor();
        render_row_content(screen_row, row);
        hal_console_show_cursor();
    }
}

#ifdef __CPM__
void render_status_bar(void)
{
    char raw_name[24];
    char sbuf[20];
    char core[84];
    const char *f4 = "^K: Editor keys";
    uint8_t pad, right_pad, i;
    uint16_t vis_col = 0;

    if (!g_current_filename[0]) {
        strcpy(raw_name, "(Untitled)");
    } else if (!strchr(g_current_filename, ':')) {
        snprintf(raw_name, sizeof(raw_name), "%c:%s",
                 (char)('A' + bdos(25, 0)), g_current_filename);
    } else {
        strncpy(raw_name, g_current_filename, sizeof(raw_name) - 2);
        raw_name[sizeof(raw_name) - 2] = '\0';
    }
    i = (uint8_t)strlen(raw_name);
    if (i > 13) {
        i = 13;
    }
    raw_name[i] = g_doc_modified ? '*' : ' ';
    raw_name[i + 1] = '\0';

    if (g_is_splash_screen) {
        uint16_t free_kb = 320;
        if (g_doc_total_lines > 1) {
            uint16_t slots = (10 * 256 > g_doc_total_lines) ?
                             (10 * 256 - g_doc_total_lines) : 0;
            free_kb = slots >> 3;
        }
        snprintf(sbuf, sizeof(sbuf), "Free: %u KB", (unsigned)free_kb);
        f4 = sbuf;
    } else if (g_block_mode == BLOCK_MODE_SELECTING ||
               g_block_mode == BLOCK_MODE_SOLIDIFIED) {
        uint8_t is_sel = (g_block_mode == BLOCK_MODE_SELECTING);
        uint16_t cnt;
        const char *unit;
        normalize_block_bounds();
        if (g_norm_start_row == g_norm_end_row) {
            cnt = (g_norm_end_col >= g_norm_start_col) ?
                (g_norm_end_col - g_norm_start_col) : 0;
            unit = (!is_sel && cnt >= 100) ? "c" :
                   ((cnt == 1) ? " char" : " chars");
        } else {
            cnt = (g_norm_end_row >= g_norm_start_row) ?
                (g_norm_end_row - g_norm_start_row +
                 ((g_norm_end_col > 0) ? 1 : 0)) : 1;
            unit = (!is_sel && cnt >= 100) ? "L" :
                   ((cnt == 1) ? " line" : " lines");
        }
        snprintf(sbuf, sizeof(sbuf), "%s: %u%s",
                 is_sel ? "Sel" : "Block", (unsigned)cnt, unit);
        f4 = sbuf;
    } else if (g_status_msg[0] != '\0') {
        f4 = g_status_msg;
    } else if (g_horiz_pan_offset > 0) {
        snprintf(sbuf, sizeof(sbuf), "[Pan +%u]",
                 (unsigned)g_horiz_pan_offset);
        f4 = sbuf;
    } else if (!g_insert_mode) {
        f4 = "Overwrite mode";
    }

    if (g_doc_total_lines > 0 && g_cur_doc_row < g_doc_total_lines) {
        checkout_active_line(g_cur_doc_row);
        vis_col = calc_visual_col(g_active_line_buf, g_cur_col);
    }

    snprintf(core, sizeof(core),
             "| %-14.14s | %s | %s | %-15.15s | Line %4u/%-4u Col %-3u |",
             raw_name,
             (g_active_cols == SCREEN_COLS_120) ? "120x40" : " 80x24",
             (g_file_format == FMT_CPM) ? "CP/M " : "Linux",
             f4,
             (unsigned)(g_cur_doc_row + 1),
             (unsigned)g_doc_total_lines,
             (unsigned)vis_col);

    pad = (g_active_cols > 78) ? (uint8_t)((g_active_cols - 78) / 2) : 1;
    right_pad = (g_active_cols > (78 + pad)) ?
                (uint8_t)(g_active_cols - 78 - pad) : 1;

    hal_console_locate(g_active_rows, 1);
    hal_console_inverse_on();
    for (i = 0; i < pad; i++) {
        hal_console_putc(' ');
    }
    hal_console_puts(core);
    for (i = 0; i < right_pad; i++) {
        hal_console_putc(' ');
    }
    hal_console_inverse_off();
}
#else
void render_status_bar(void)
{
    char raw_name[260];
    char sbuf[20];
    char geom_buf[16];
    const char *fname;
    const char *fmt_str;
    const char *f4 = "^K: Editor keys";
    char core[256];
    char full_bar[256];
    size_t core_len;
    size_t i, idx;
    uint16_t vis_col = 0;

    fname = g_current_filename[0] ? g_current_filename : "(Untitled)";
    strncpy(raw_name, fname, sizeof(raw_name) - 2);
    raw_name[sizeof(raw_name) - 2] = '\0';
    i = strlen(raw_name);
    if (i > 13) {
        i = 13;
    }
    raw_name[i] = g_doc_modified ? '*' : ' ';
    raw_name[i + 1] = '\0';

    if (g_active_cols == SCREEN_COLS_80 && g_active_rows == SCREEN_ROWS_24) {
        strcpy(geom_buf, " 80x24");
    } else if (g_active_cols == SCREEN_COLS_120 &&
               g_active_rows == SCREEN_ROWS_40) {
        strcpy(geom_buf, "120x40");
    } else {
        snprintf(geom_buf, sizeof(geom_buf), "%ux%u",
                 (unsigned)g_active_cols, (unsigned)g_active_rows);
    }

    fmt_str = (g_file_format == FMT_CPM) ? "CP/M " : "Linux";

    if (g_is_splash_screen) {
        f4 = "";
    } else if (g_block_mode == BLOCK_MODE_SELECTING ||
               g_block_mode == BLOCK_MODE_SOLIDIFIED) {
        uint8_t is_sel = (g_block_mode == BLOCK_MODE_SELECTING);
        uint16_t cnt;
        const char *unit;
        normalize_block_bounds();
        if (g_norm_start_row == g_norm_end_row) {
            cnt = (g_norm_end_col >= g_norm_start_col) ?
                (g_norm_end_col - g_norm_start_col) : 0;
            unit = (!is_sel && cnt >= 100) ? "c" :
                   ((cnt == 1) ? " char" : " chars");
        } else {
            cnt = (g_norm_end_row >= g_norm_start_row) ?
                (g_norm_end_row - g_norm_start_row +
                 ((g_norm_end_col > 0) ? 1 : 0)) : 1;
            unit = (!is_sel && cnt >= 100) ? "L" :
                   ((cnt == 1) ? " line" : " lines");
        }
        snprintf(sbuf, sizeof(sbuf), "%s: %u%s",
                 is_sel ? "Sel" : "Block", (unsigned)cnt, unit);
        f4 = sbuf;
    } else if (g_horiz_pan_offset > 0) {
        snprintf(sbuf, sizeof(sbuf), "[Pan +%u]",
                 (unsigned)g_horiz_pan_offset);
        f4 = sbuf;
    } else if (!g_insert_mode) {
        f4 = "Overwrite mode";
    }

    if (g_doc_total_lines > 0 && g_cur_doc_row < g_doc_total_lines) {
        checkout_active_line(g_cur_doc_row);
        vis_col = calc_visual_col(g_active_line_buf, g_cur_col);
    }

    snprintf(core, sizeof(core),
             "| %-14.14s | %-6s | %s | %-15.15s | Line %4u/%-4u Col %-3u |",
             raw_name,
             geom_buf,
             fmt_str,
             f4,
             (unsigned)(g_cur_doc_row + 1),
             (unsigned)g_doc_total_lines,
             (unsigned)vis_col);
    core_len = strlen(core);

    if (core_len < g_active_cols) {
        size_t pad = g_active_cols - core_len;
        size_t left_pad = pad / 2;
        size_t right_pad = pad - left_pad;
        idx = 0;
        for (i = 0; i < left_pad && idx + 1 < sizeof(full_bar); i++) {
            full_bar[idx++] = ' ';
        }
        for (i = 0; i < core_len && idx + 1 < sizeof(full_bar); i++) {
            full_bar[idx++] = core[i];
        }
        for (i = 0; i < right_pad && idx + 1 < sizeof(full_bar); i++) {
            full_bar[idx++] = ' ';
        }
        full_bar[idx] = '\0';
    } else {
        size_t copy_len = (size_t)g_active_cols;
        if (copy_len >= sizeof(full_bar)) {
            copy_len = sizeof(full_bar) - 1;
        }
        memcpy(full_bar, core, copy_len);
        full_bar[copy_len] = '\0';
    }

    hal_console_locate(g_active_rows, 1);
    hal_console_inverse_on();
    hal_console_puts(full_bar);
    hal_console_inverse_off();
}
#endif

static void render_tier1_workspace_screen(const char **lines,
                                          size_t count,
                                          size_t content_width)
{
    uint8_t avail_rows;
    uint8_t top_row;
    uint8_t left_col;
    uint8_t r;
    size_t line_idx;

    clear_screen();
    avail_rows = (g_active_rows > 1) ? (g_active_rows - 1) : 23;
    top_row = (avail_rows > count)
              ? (uint8_t)(((avail_rows - count) / 2) + 1)
              : 1;
    left_col = (g_active_cols > content_width)
               ? (uint8_t)(((g_active_cols - content_width) / 2) + 1)
               : 2;
    if (left_col < 2) {
        left_col = 2;
    }

    /* Column 0 Tilde Margin Discipline for all rows 1..avail_rows */
    for (r = 1; r <= avail_rows; r++) {
        hal_console_locate(r, 1);
        hal_console_putc('~');
        if (r >= top_row && r < top_row + count) {
            line_idx = r - top_row;
            if (lines[line_idx][0] != '\0') {
                hal_console_locate(r, left_col);
                hal_console_puts(lines[line_idx]);
            }
        }
        hal_console_clear_eol();
    }

    /* Universal Status Bar presence on Row HOST_ROWS */
    render_status_bar();
}

#ifdef __CPM__
extern char g_ramdrive_char;
#endif

void show_splash_screen(void)
{
    const char *splash_lines[22];
    size_t n;
    int k;
    char dlg_fname[32];
    uint8_t need_render = 1;

    hal_console_hide_cursor();
    g_is_splash_screen = 1;

    while (1) {
        n = 0;
        splash_lines[n++] = "           SE - Screen Editor";
        splash_lines[n++] = "";
        splash_lines[n++] = "  type   [E]  or  [Enter] to edit";
        splash_lines[n++] = "  type   [N]              to new file";
        splash_lines[n++] = "  type   [O]  or  [^O]    to open file";
        splash_lines[n++] = "  type   [S]  or  [^S]    to save file";
        splash_lines[n++] = "  type   [W]  or  [^W]    to close file";
        splash_lines[n++] = "  type   [L]  or  [^L]    to goto line";
        splash_lines[n++] = "  type   [A]              for about";
        splash_lines[n++] = "  type   [M]              for memory info";
        splash_lines[n++] = "  type   [P]              for plugins";
        splash_lines[n++] = "  type   [^P]             for context plugin menu";
        splash_lines[n++] = "  type   [C]              to configure";
        splash_lines[n++] = "  type   [1]              set 80x24";
        splash_lines[n++] = "  type   [2]              set 120x40";
#ifndef __CPM__
        splash_lines[n++] = "  type   [3]              set native";
#endif
        splash_lines[n++] = "  type   [Q]  or  [^Q]    to exit";
        splash_lines[n++] = "";
        if (g_config.screen_mode == MODE_120X40) {
            splash_lines[n++] =
                "Active Screen : [120x40 (Modern Default)]";
#ifndef __CPM__
        } else if (g_config.screen_mode == MODE_NATIVE) {
            splash_lines[n++] =
                "Active Screen : [Native (Dynamic Console)]";
#endif
        } else {
            splash_lines[n++] =
                "Active Screen : [80x24 (Classic Terminal)]";
        }
#ifdef __CPM__
        if (!g_ramdrive_char) {
            splash_lines[n++] =
                "RAM Drive     : [None Detected]";
        } else if (g_config.ramdrive_mode == RAMDRV_MODE_DISABLED) {
            splash_lines[n++] =
                "RAM Drive     : [None Detected]";
        } else if (g_config.ramdrive_mode == RAMDRV_MODE_ENABLED) {
            splash_lines[n++] =
                "RAM Drive (A:): [Overwritten (Max RAM)]";
        } else if (g_config.ramdrive_mode == RAMDRV_MODE_HIBERNATE) {
            splash_lines[n++] =
                "RAM Drive (A:): [Hibernated (Temp Image)]";
        } else {
            splash_lines[n++] =
                "RAM Drive (A:): [Preserved (Active)]";
        }
        if (g_ramdrive_char &&
            g_config.ramdrive_mode != RAMDRV_MODE_DISABLED) {
            ((char *)splash_lines[n - 1])[11] = g_ramdrive_char;
        }
#else
        splash_lines[n++] = "RAM Drive     : [None Detected]";
#endif
#ifdef __CPM__
        if (g_config.plugin_mode == PLUGIN_MODE_DISABLED) {
            splash_lines[n++] = "Plugin System : [Disabled]";
        } else if (g_config.plugin_mode == PLUGIN_MODE_ONDEMAND) {
            splash_lines[n++] = "Plugin System : [On Demand]";
        } else {
            splash_lines[n++] = "Plugin System : [Operational]";
        }
#else
        splash_lines[n++] = "Plugin System : [Builtin]";
#endif
        splash_lines[n++] = (g_config.lines_mode == 1) ?
            "Max Lines     : [32,768 lines]" :
            "Max Lines     : [16,384 lines]";

        if (need_render) {
            render_tier1_workspace_screen(splash_lines, n, 40);
            need_render = 0;
        }
        while ((k = hal_console_getkey()) <= 0) {
            /* Wait for user keystroke */
        }

        if (k == 'q' || k == 'Q' || k == KEY_CTRL_Q) {
            if (g_doc_modified) {
                g_is_splash_screen = 0;
                clear_screen();
                render_screen();
                if (modal_confirm_save_changes() != MODAL_RES_OK) {
                    break;
                }
            }
            g_editor_exit_flag = 1;
            break;
        } else if (k == 'e' || k == 'E' || k == KEY_ENTER) {
            break;
        } else if (k == 'n' || k == 'N') {
            if (g_doc_modified) {
                g_is_splash_screen = 0;
                clear_screen();
                render_screen();
                if (modal_confirm_save_changes() != MODAL_RES_OK) {
                    break;
                }
            }
            init_empty_document();
            g_current_filename[0] = '\0';
            break;
        } else if (k == 'o' || k == 'O' || k == KEY_CTRL_O) {
            if (g_doc_modified) {
                g_is_splash_screen = 0;
                clear_screen();
                render_screen();
                if (modal_confirm_save_changes() != MODAL_RES_OK) {
                    break;
                }
                dlg_fname[0] = '\0';
                if (ui_browser_open_dialog(dlg_fname, sizeof(dlg_fname)) ==
                    MODAL_RES_OK && dlg_fname[0]) {
                    file_load(dlg_fname);
                }
                break;
            }
            dlg_fname[0] = '\0';
            if (ui_browser_open_dialog(dlg_fname, sizeof(dlg_fname)) ==
                MODAL_RES_OK && dlg_fname[0]) {
                file_load(dlg_fname);
                break;
            }
            need_render = 1;
        } else if (k == 's' || k == 'S' || k == KEY_CTRL_S) {
            strncpy(dlg_fname, g_current_filename, sizeof(dlg_fname) - 1);
            dlg_fname[sizeof(dlg_fname) - 1] = '\0';
            if (ui_browser_save_dialog(dlg_fname, sizeof(dlg_fname)) ==
                MODAL_RES_OK && dlg_fname[0]) {
                file_save(dlg_fname, g_file_format);
            }
            need_render = 1;
        } else if (k == 'w' || k == 'W' || k == KEY_CTRL_W) {
            if (g_doc_modified) {
                g_is_splash_screen = 0;
                clear_screen();
                render_screen();
                if (modal_confirm_save_changes() != MODAL_RES_OK) {
                    break;
                }
                g_is_splash_screen = 1;
            }
            init_empty_document();
            g_current_filename[0] = '\0';
            need_render = 1;
        } else if (k == 'l' || k == 'L' || k == KEY_CTRL_L) {
            dlg_fname[0] = '\0';
            if (modal_goto_line(dlg_fname, 16) == MODAL_RES_OK &&
                dlg_fname[0]) {
                int line_num = atoi(dlg_fname);
                if (line_num > 0) {
                    goto_line((uint16_t)line_num);
                    break;
                }
            }
            need_render = 1;
        } else if (k == 'c' || k == 'C') {
            show_config_screen();
            need_render = 1;
        } else if (k == 'a' || k == 'A') {
            show_about_screen();
            need_render = 1;
        } else if (k == 'm' || k == 'M') {
            show_mem_info_screen();
            need_render = 1;
        } else if (k == 'p' || k == 'P') {
            plugin_manager_ui();
            need_render = 1;
        } else if (k == KEY_CTRL_P) {
            show_plugin_palette();
            need_render = 1;
        } else if (k == '1') {
            clear_screen();
            g_config.screen_mode = MODE_80X24;
            g_active_cols = SCREEN_COLS_80;
            g_active_rows = SCREEN_ROWS_24;
            if (g_cur_doc_row >= g_top_doc_row + 23) {
                g_cur_doc_row = (uint16_t)(g_top_doc_row + 22);
                checkout_active_line(g_cur_doc_row);
            }
            need_render = 1;
        } else if (k == '2') {
            clear_screen();
            g_config.screen_mode = MODE_120X40;
            g_active_cols = SCREEN_COLS_120;
            g_active_rows = SCREEN_ROWS_40;
            need_render = 1;
#ifndef __CPM__
        } else if (k == '3') {
            uint8_t ncols = 0, nrows = 0;
            clear_screen();
            g_config.screen_mode = MODE_NATIVE;
            if (hal_console_get_native_size(&ncols, &nrows) == 0 &&
                ncols >= SCREEN_COLS_80 && nrows >= SCREEN_ROWS_24) {
                g_active_cols = ncols;
                g_active_rows = nrows;
            } else {
                g_active_cols = SCREEN_COLS_80;
                g_active_rows = SCREEN_ROWS_24;
            }
            need_render = 1;
#endif
        }
    }
    if (!g_editor_exit_flag) {
        clear_screen();
        hal_console_show_cursor();
    }
    g_is_splash_screen = 0;
    g_need_screen_render = 1;
}

static const char s_help_eq[] =
    "========================================"
    "======================================";
static const char s_help_dash[] =
    "----------------------------------------"
    "--------------------------------------";

static const char *s_help_lines[22] = {
  s_help_eq,
  "                               EDITOR MODE KEYS",
  s_help_eq,
  "  FILE & SYSTEM:",
  "    Ctrl+O           Open file screen      Ctrl+S         Save file screen",
#ifdef __CPM__
  "    Ctrl+W           Close file to splash  Ctrl+Q         Quit to CP/M",
#else
  "    Ctrl+W           Close file to splash  Ctrl+Q         Quit to OS",
#endif
  "    Ctrl+K           Help / Solidify block Ctrl+P         Plugins pop-up",
  "  NAVIGATION & SEARCH:",
  "    Arrow Keys      Move cursor            Ctrl+A / Home  Start of line",
  "    Ctrl+U / PgUp   Page Up                Ctrl+E / End   End of line",
  "    Ctrl+V / PgDn   Page Down              Ctrl+T / ^Home Top of file",
  "    Ctrl+L          Goto line number       Ctrl+G / ^End  Bottom of file",
  "    Ctrl+F          Find text              Ctrl+N         Find next",
  "    Ctrl+R          Search and Replace     Ctrl+I / Tab   Toggle find case",
  "  EDITING & BLOCK:",
  "    Insert          Toggle Insert/Ovr      Enter          New line",
  "    ASCII 32..126   Insert/Overwrite text  Backspace      Delete left/join",
  "    Delete / Ctrl+D Delete char or block   Ctrl+B         Start/Toggle blk",
  "    Ctrl+C          Copy solidified block  Ctrl+K         Solidify block",
  "    Ctrl+X          Move solidified block  ESC            Clear block",
  s_help_dash,
  "                          Press any key to continue"
};

void show_help_screen(void)
{
    int k;
    uint8_t prev_splash = g_is_splash_screen;
    g_is_splash_screen = 1;
    hal_console_hide_cursor();
    while (1) {
        render_tier1_workspace_screen(s_help_lines, 22, 78);
        while ((k = hal_console_getkey()) <= 0) {
            /* Wait for user keystroke */
        }
        if (k == KEY_CTRL_P) {
            show_plugin_palette();
            continue;
        }
        break;
    }
    clear_screen();
    g_is_splash_screen = prev_splash;
    if (!g_is_splash_screen) {
        hal_console_show_cursor();
    }
    g_need_screen_render = 1;
}

void show_about_screen(void)
{
    static const char *s_about_lines[9] = {
        "               SE - Screen Editor",
        "         version 1.1.4 (2026-10-18) (C)",
        "                 by Dean Jenkins",
        "",
        "Google Antigravity 2.23.0 & Gemini 4 Argon Medium",
        "",
        "   Open source software under the MIT License",
        "",
        "            Press any key to continue"
    };
    int k;
    uint8_t prev_splash = g_is_splash_screen;
    g_is_splash_screen = 1;
    hal_console_hide_cursor();
    while (1) {
        render_tier1_workspace_screen(s_about_lines, 9, 48);
        while ((k = hal_console_getkey()) <= 0) {
            /* Wait for user keystroke */
        }
        if (k == KEY_CTRL_P) {
            show_plugin_palette();
            continue;
        }
        break;
    }
    clear_screen();
    g_is_splash_screen = prev_splash;
    if (!g_is_splash_screen) {
        hal_console_show_cursor();
    }
    g_need_screen_render = 1;
}

void show_config_screen(void)
{
    const char *cfg_lines[11];
    int k;
    uint8_t need_render = 1;
    uint8_t prev_splash = g_is_splash_screen;

    g_is_splash_screen = 1;
    hal_console_hide_cursor();

    while (1) {
        cfg_lines[0] = "            SE - Configuration Manager";
        cfg_lines[1] = "";
        cfg_lines[2] = g_config_loaded ?
            "         Config Status: Loaded from SE.CFG" :
            "         Config Status: Defaults";
        cfg_lines[3] = "";
        if (g_config.screen_mode == MODE_120X40) {
            cfg_lines[4] = "         1. Screen Geometry  : 120x40 (Wide)";
#ifndef __CPM__
        } else if (g_config.screen_mode == MODE_NATIVE) {
            cfg_lines[4] = "         1. Screen Geometry  : Native";
#endif
        } else {
            cfg_lines[4] = "         1. Screen Geometry  : 80x24 (Classic)";
        }
        if (g_config.ramdrive_mode == RAMDRV_MODE_ENABLED) {
            cfg_lines[5] = "         2. RAM Drive Mode   : Enabled";
        } else if (g_config.ramdrive_mode == RAMDRV_MODE_HIBERNATE) {
            cfg_lines[5] = "         2. RAM Drive Mode   : Hibernate";
        } else {
            cfg_lines[5] = "         2. RAM Drive Mode   : Protected";
        }
        cfg_lines[6] = (g_config.lines_mode == 1) ?
            "         3. Max Doc Lines    : 32K" :
            "         3. Max Doc Lines    : 16K";
        cfg_lines[7] = (g_config.tab_width == 8) ?
            "         4. Tab Width        : 8" :
            "         4. Tab Width        : 4";
#ifdef __CPM__
        if (g_config.plugin_mode == PLUGIN_MODE_ONDEMAND) {
            cfg_lines[8] = "         5. Plugin Manager   : Demand";
        } else if (g_config.plugin_mode == PLUGIN_MODE_DISABLED) {
            cfg_lines[8] = "         5. Plugin Manager   : Disabled";
        } else {
            cfg_lines[8] = "         5. Plugin Manager   : Autoload";
        }
#else
        cfg_lines[8] = "         5. Plugin Manager   : Builtin";
#endif
        cfg_lines[9] = "";
        cfg_lines[10] = "  [1-5]=Toggle Option  [S]=Save Config  [ESC]=Exit";

        if (need_render) {
            render_tier1_workspace_screen(cfg_lines, 11, 50);
            need_render = 0;
        }

        while ((k = hal_console_getkey()) <= 0) {
            /* Wait for user keystroke */
        }

        if (k == KEY_ESC || k == KEY_ENTER || k == 'q' || k == 'Q') {
            break;
        } else if (k == '1') {
            clear_screen();
            if (g_config.screen_mode == MODE_80X24) {
                g_config.screen_mode = MODE_120X40;
                g_active_cols = SCREEN_COLS_120;
                g_active_rows = SCREEN_ROWS_40;
#ifndef __CPM__
            } else if (g_config.screen_mode == MODE_120X40) {
                uint8_t ncols = 0, nrows = 0;
                g_config.screen_mode = MODE_NATIVE;
                if (hal_console_get_native_size(&ncols, &nrows) == 0 &&
                    ncols >= SCREEN_COLS_80 && nrows >= SCREEN_ROWS_24) {
                    g_active_cols = ncols;
                    g_active_rows = nrows;
                } else {
                    g_active_cols = SCREEN_COLS_80;
                    g_active_rows = SCREEN_ROWS_24;
                }
#endif
            } else {
                g_config.screen_mode = MODE_80X24;
                g_active_cols = SCREEN_COLS_80;
                g_active_rows = SCREEN_ROWS_24;
            }
            need_render = 1;
        } else if (k == '2') {
            if (g_config.ramdrive_mode == RAMDRV_MODE_PROTECTED) {
                g_config.ramdrive_mode = RAMDRV_MODE_ENABLED;
            } else if (g_config.ramdrive_mode == RAMDRV_MODE_ENABLED) {
                g_config.ramdrive_mode = RAMDRV_MODE_HIBERNATE;
            } else {
                g_config.ramdrive_mode = RAMDRV_MODE_PROTECTED;
            }
            need_render = 1;
        } else if (k == '3') {
            g_config.lines_mode = (g_config.lines_mode == 0) ? 1 : 0;
            need_render = 1;
        } else if (k == '4') {
            g_config.tab_width = (g_config.tab_width == 4) ? 8 : 4;
            need_render = 1;
#ifdef __CPM__
        } else if (k == '5') {
            if (g_config.plugin_mode == PLUGIN_MODE_AUTOLOAD) {
                g_config.plugin_mode = PLUGIN_MODE_ONDEMAND;
            } else if (g_config.plugin_mode == PLUGIN_MODE_ONDEMAND) {
                g_config.plugin_mode = PLUGIN_MODE_DISABLED;
            } else {
                g_config.plugin_mode = PLUGIN_MODE_AUTOLOAD;
            }
            need_render = 1;
#endif
        } else if (k == 's' || k == 'S') {
            config_save();
            need_render = 1;
        }
    }
    clear_screen();
    g_is_splash_screen = prev_splash;
    if (!g_is_splash_screen) {
        hal_console_show_cursor();
    }
    g_need_screen_render = 1;
}

void show_mem_info_screen(void)
{
    char line1[44];
    char line2[44];
    const char *mem_lines[6];
    int k;
    uint8_t prev_splash = g_is_splash_screen;

    g_is_splash_screen = 1;
    hal_console_hide_cursor();
    snprintf(line1, sizeof(line1), "       Free Virtual Slots: %u",
             (unsigned)mem_get_free_slots());
    snprintf(line2, sizeof(line2), "       Free Document Buffer: %u KB",
             (unsigned)mem_get_free_kb());
    mem_lines[0] = "          SE - Extended Memory Map";
    mem_lines[1] = "";
    mem_lines[2] = line1;
    mem_lines[3] = line2;
    mem_lines[4] = "";
    mem_lines[5] = "          Press any key to continue";

    while (1) {
        render_tier1_workspace_screen(mem_lines, 6, 46);
        while ((k = hal_console_getkey()) <= 0) {
            /* Wait for user keystroke */
        }
        if (k == KEY_CTRL_P) {
            show_plugin_palette();
            continue;
        }
        break;
    }
    clear_screen();
    g_is_splash_screen = prev_splash;
    if (!g_is_splash_screen) {
        hal_console_show_cursor();
    }
    g_need_screen_render = 1;
}
