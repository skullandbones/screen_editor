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
#ifndef __CPM__
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

#ifndef __CPM__
void set_status_msg(const char *msg)
{
    g_status_msg[0] = '\0';
    if (msg && *msg) {
        modal_show_notification("Notice", msg);
    }
}
#endif

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

#ifndef __CPM__
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
#endif

char *se_append_u16(char *p, uint16_t val)
{
    char tmp[6];
    uint8_t n = 0;
    if (val == 0) {
        *p++ = '0';
        *p = '\0';
        return p;
    }
    while (val > 0) {
        tmp[n++] = (char)('0' + (val % 10));
        val /= 10;
    }
    while (n > 0) {
        *p++ = tmp[--n];
    }
    *p = '\0';
    return p;
}

#ifdef __CPM__
#define append_u16 se_append_u16

static char *copy_padded(char *dst, const char *src, uint8_t width)
{
    uint8_t n = 0;
    while (*src && n < width) {
        *dst++ = *src++;
        n++;
    }
    while (n < width) {
        *dst++ = ' ';
        n++;
    }
    return dst;
}

void render_status_bar(void)
{
    char *raw_name = g_scratch_line_buf + 32;
    char *sbuf = g_scratch_line_buf + 50;
    char *core = g_scratch_line_buf + 68;
    const char *f4 = "^K: Editor keys";
    uint8_t pad, right_pad, i;
    uint16_t vis_col = 0;
    char *p;

    if (g_doc_total_lines > 0 && g_cur_doc_row < g_doc_total_lines) {
        checkout_active_line(g_cur_doc_row);
        vis_col = calc_visual_col(g_active_line_buf, g_cur_col);
    }

    if (!g_current_filename[0]) {
        strcpy(raw_name, "(Untitled)");
    } else if (!strchr(g_current_filename, ':')) {
        raw_name[0] = (char)('A' + bdos(25, 0));
        raw_name[1] = ':';
        strncpy(raw_name + 2, g_current_filename, 14);
        raw_name[16] = '\0';
    } else {
        strncpy(raw_name, g_current_filename, 16);
        raw_name[16] = '\0';
    }
    i = (uint8_t)strlen(raw_name);
    if (g_doc_modified) {
        if (i > 13) {
            i = 13;
        }
        raw_name[i] = '*';
        raw_name[i + 1] = '\0';
    } else if (i > 14) {
        raw_name[14] = '\0';
    }

    if (g_is_splash_screen) {
        uint16_t free_kb = 320;
        if (g_doc_total_lines > 1) {
            uint16_t slots = (10 * 256 > g_doc_total_lines) ?
                             (10 * 256 - g_doc_total_lines) : 0;
            free_kb = slots >> 3;
        }
        strcpy(sbuf, "Free: ");
        p = append_u16(sbuf + 6, free_kb);
        strcpy(p, " KB");
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
        strcpy(sbuf, is_sel ? "Sel: " : "Block: ");
        p = append_u16(sbuf + strlen(sbuf), cnt);
        strcpy(p, unit);
        f4 = sbuf;
    } else if (g_horiz_pan_offset > 0) {
        strcpy(sbuf, "[Pan +");
        p = append_u16(sbuf + 6, g_horiz_pan_offset);
        strcpy(p, "]");
        f4 = sbuf;
    } else if (!g_insert_mode) {
        f4 = "Overwrite mode";
    }

    p = core;
    *p++ = '|';
    *p++ = ' ';
    p = copy_padded(p, raw_name, 14);
    memcpy(p, (g_active_cols == SCREEN_COLS_120) ? " | 120x40 | "
                                                 : " |  80x24 | ", 12);
    p += 12;
    if (g_is_loading_file) {
        memcpy(p, "      | ", 8);
        p += 8;
        p = copy_padded(p, f4, 15);
        strcpy(p, " | Line    1/---- Col 0   |");
    } else {
        char nbuf[8];
        uint8_t nl;
        memcpy(p, (g_file_format == FMT_CPM) ? "CP/M  | " : "Linux | ", 8);
        p += 8;
        p = copy_padded(p, f4, 15);
        memcpy(p, " | Line ", 8);
        p += 8;
        append_u16(nbuf, (uint16_t)(g_cur_doc_row + 1));
        nl = (uint8_t)strlen(nbuf);
        while (nl < 4) {
            *p++ = ' ';
            nl++;
        }
        strcpy(p, nbuf);
        p += strlen(nbuf);
        *p++ = '/';
        append_u16(nbuf, g_doc_total_lines);
        p = copy_padded(p, nbuf, 4);
        memcpy(p, " Col ", 5);
        p += 5;
        append_u16(nbuf, vis_col);
        p = copy_padded(p, nbuf, 3);
        strcpy(p, " |");
    }

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
    if (g_doc_modified) {
        if (i > 13) {
            i = 13;
        }
        raw_name[i] = '*';
        raw_name[i + 1] = '\0';
    } else if (i > 14) {
        raw_name[14] = '\0';
    }

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

static uint8_t s_cfg_saved_flag = 0;

static const char *s_splash_lines[] = {
    "           SE - Screen Editor",
    "",
    "  type   [E]  or  [Enter] to edit",
    "  type   [N]              to new file",
    "  type   [O]  or  [^O]    to open file",
    "  type   [S]  or  [^S]    to save file",
    "  type   [W]  or  [^W]    to close file",
    "  type   [L]  or  [^L]    to goto line",
    "  type   [A]              for about",
    "  type   [M]              for memory info",
    "  type   [P]              for plugins",
    "  type   [^P]             for context plugin menu",
    "  type   [C]              to configure",
    "  type   [1]              set 80x24",
    "  type   [2]              set 120x40",
#ifndef __CPM__
    "  type   [3]              set native",
#endif
    "  type   [Q]  or  [^Q]    to exit",
    "",
    NULL,
    NULL,
    NULL,
    NULL
};

static void render_splash_content(void)
{
#ifdef __CPM__
    const size_t base = 17;
#else
    const size_t base = 18;
#endif
    if (g_config.screen_mode == MODE_120X40) {
        s_splash_lines[base] = "Active Screen : [120x40 (Modern Default)]";
#ifndef __CPM__
    } else if (g_config.screen_mode == MODE_NATIVE) {
        s_splash_lines[base] = "Active Screen : [Native (Dynamic Console)]";
#endif
    } else {
        s_splash_lines[base] = "Active Screen : [80x24 (Classic Terminal)]";
    }
#ifdef __CPM__
    if (!g_ramdrive_char || g_config.ramdrive_mode == RAMDRV_MODE_DISABLED) {
        s_splash_lines[base + 1] = "RAM Drive     : [None Detected]";
    } else if (g_config.ramdrive_mode == RAMDRV_MODE_ENABLED) {
        s_splash_lines[base + 1] = "RAM Drive (A:): [Overwritten (Max RAM)]";
    } else if (g_config.ramdrive_mode == RAMDRV_MODE_HIBERNATE) {
        s_splash_lines[base + 1] = "RAM Drive (A:): [Hibernated (Temp Image)]";
    } else {
        s_splash_lines[base + 1] = "RAM Drive (A:): [Preserved (Active)]";
    }
    if (g_ramdrive_char && g_config.ramdrive_mode != RAMDRV_MODE_DISABLED) {
        ((char *)s_splash_lines[base + 1])[11] = g_ramdrive_char;
    }
    if (g_config.plugin_mode == PLUGIN_MODE_DISABLED) {
        s_splash_lines[base + 2] = "Plugin System : [Disabled]";
    } else if (g_config.plugin_mode == PLUGIN_MODE_ONDEMAND) {
        s_splash_lines[base + 2] = "Plugin System : [On Demand]";
    } else {
        s_splash_lines[base + 2] = "Plugin System : [Operational]";
    }
#else
    s_splash_lines[base + 1] = "RAM Drive     : [None Detected]";
    s_splash_lines[base + 2] = "Plugin System : [Builtin]";
#endif
    s_splash_lines[base + 3] = (g_config.lines_mode == 1) ?
        "Max Lines     : [32,768 lines]" :
        "Max Lines     : [16,384 lines]";

    render_tier1_workspace_screen(s_splash_lines, base + 4, 40);
}

void show_splash_screen(void)
{
    int k;
#ifdef __CPM__
    extern char g_editor_fname[24];
#define dlg_fname g_editor_fname
#else
    char dlg_fname[32];
#endif
    uint8_t need_render = 1;

    hal_console_hide_cursor();
    g_is_splash_screen = 1;

    while (1) {
        if (need_render) {
            render_splash_content();
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
                if (ui_browser_open_dialog(dlg_fname, 24) ==
                    MODAL_RES_OK && dlg_fname[0]) {
                    file_load(dlg_fname);
                }
                break;
            }
            dlg_fname[0] = '\0';
            if (ui_browser_open_dialog(dlg_fname, 24) ==
                MODAL_RES_OK && dlg_fname[0]) {
                file_load(dlg_fname);
                break;
            }
            need_render = 1;
        } else if (k == 's' || k == 'S' || k == KEY_CTRL_S) {
            strcpy(dlg_fname, g_current_filename);
            if (ui_browser_save_dialog(dlg_fname, 24) ==
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
            if (!g_is_splash_screen) {
                break;
            }
            need_render = 1;
        } else if (k == KEY_CTRL_P) {
            show_plugin_palette_ctx(PLUG_CTX_SPLASH);
            if (!g_is_splash_screen) {
                break;
            }
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
  "    Ctrl+K           Help / Solidify block Ctrl+P          Plugins pop-up",
#else
  "    Ctrl+W           Close file to splash  Ctrl+Q         Quit to OS",
  "    Ctrl+K           Help / Solidify block Ctrl+P         Plugins pop-up",
#endif
  "    Ctrl+Z           Plugin Manager        Ctrl+Y         Beautify text",
  "  NAVIGATION & SEARCH:",
  "    Arrow Keys      Move cursor            Ctrl+A / Home  Start of line",
  "    Ctrl+U / PgUp   Page Up                Ctrl+E / End   End of line",
  "    Ctrl+V / PgDn   Page Down              Ctrl+T / ^Home Top of file",
  "    Ctrl+L          Goto line number       Ctrl+G / ^End  Bottom of file",
  "    Ctrl+F          Find text              Ctrl+N         Find next",
  "    Ctrl+R          Search and Replace     Ctrl+I / Tab   Toggle find case",
  "  EDITING & BLOCK:",
  "    Insert          Toggle Insert/Ovr      Enter          New line / Lock",
  "    ASCII 32..126   Insert/Overwrite text  Backspace      Delete left/join",
  "    Delete / Ctrl+D Delete char or block   Ctrl+B         Start/Toggle blk",
  "    Ctrl+C / Ctrl+X Copy / Move block      ESC            Clear block",
  s_help_dash,
  "                          Press any key to continue"
};

static const char *s_about_lines[9] = {
    "               SE - Screen Editor",
    "         version 1.1.5 (2026-10-21) (C)",
    "                 by Dean Jenkins",
    "",
    "Google Antigravity 2.23.0 & Gemini 4 Argon Medium",
    "",
    "   Open source software under the MIT License",
    "",
    "            Press any key to continue"
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
            show_plugin_palette_ctx(PLUG_CTX_HELP);
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
            show_plugin_palette_ctx(PLUG_CTX_ABOUT);
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

static const char *s_cfg_lines[11] = {
#ifdef __CPM__
    "            SE - Screen Editor Configuration",
#else
    "            SE - Configuration Manager",
#endif
    "",
    NULL,
    "",
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    "",
    "  [1-5]=Toggle Option  [S]=Save Config  [ESC]=Exit"
};

static void render_config_content(void)
{
    s_cfg_lines[2] = s_cfg_saved_flag ?
        "         Config Status: Saved to local drive" :
        (g_config_loaded ?
         "         Config Status: Loaded from SE.CFG" :
         "         Config Status: Defaults");
    if (g_config.screen_mode == MODE_120X40) {
        s_cfg_lines[4] = "         1. Screen Geometry  : 120x40 (Wide)";
#ifndef __CPM__
    } else if (g_config.screen_mode == MODE_NATIVE) {
        s_cfg_lines[4] = "         1. Screen Geometry  : Native";
#endif
    } else {
        s_cfg_lines[4] = "         1. Screen Geometry  : 80x24 (Classic)";
    }
    if (g_config.ramdrive_mode == RAMDRV_MODE_ENABLED) {
        s_cfg_lines[5] = "         2. RAM Drive Mode   : "
                         "[Overwrite (Sacrifice Drive, 384KB)]";
    } else if (g_config.ramdrive_mode == RAMDRV_MODE_HIBERNATE) {
        s_cfg_lines[5] = "         2. RAM Drive Mode   : "
                         "[Hibernate (Backup/Restore, 384KB)]";
    } else {
        s_cfg_lines[5] = "         2. RAM Drive Mode   : "
                         "[Preserve (RAM Drive Active, 128KB)]";
    }
    s_cfg_lines[6] = (g_config.lines_mode == 1) ?
        "         3. Max Doc Lines    : 32K" :
        "         3. Max Doc Lines    : 16K";
    s_cfg_lines[7] = (g_config.tab_width == 8) ?
        "         4. Tab Width        : 8" :
        "         4. Tab Width        : 4";
#ifdef __CPM__
    if (g_config.plugin_mode == PLUGIN_MODE_ONDEMAND) {
        s_cfg_lines[8] = "         5. Plugin Manager   : Demand";
    } else if (g_config.plugin_mode == PLUGIN_MODE_DISABLED) {
        s_cfg_lines[8] = "         5. Plugin Manager   : Disabled";
    } else {
        s_cfg_lines[8] = "         5. Plugin Manager   : Autoload";
    }
#else
    s_cfg_lines[8] = "         5. Plugin Manager   : Builtin";
#endif
    render_tier1_workspace_screen(s_cfg_lines, 11, 50);
}

void show_config_screen(void)
{
    int k;
    uint8_t need_render = 1;
    uint8_t prev_splash = g_is_splash_screen;

    s_cfg_saved_flag = 0;
    g_is_splash_screen = 1;
    hal_console_hide_cursor();

    while (1) {
        if (need_render) {
            render_config_content();
            need_render = 0;
        }

        while ((k = hal_console_getkey()) <= 0) {
            /* Wait for user keystroke */
        }

        if (k == KEY_ESC || k == KEY_ENTER || k == 'q' || k == 'Q') {
            break;
        } else if (k == KEY_CTRL_P) {
            show_plugin_palette_ctx(PLUG_CTX_CONFIG);
            if (!g_is_splash_screen) {
                return;
            }
            need_render = 1;
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
                    g_active_rows = nrows;
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
                g_config.ramdrive_mode = RAMDRV_MODE_HIBERNATE;
            } else if (g_config.ramdrive_mode == RAMDRV_MODE_HIBERNATE) {
                g_config.ramdrive_mode = RAMDRV_MODE_ENABLED;
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
            s_cfg_saved_flag = 1;
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

static void render_mem_info_content(void)
{
#ifdef __CPM__
    uint8_t r;
    clear_screen();
    hal_console_puts(
        "~\r\n"
        "~                         SE.COM - Extended Memory Map\r\n"
        "~   HBIOS: RomWBW v3.4  |  OS: CP/M 2.2  |  "
        "RAM: 512 KB (16x32K)  |  SE: 192 KB\r\n"
        "~\r\n"
        "~   Bank  Phys   Size   System / OS Role        "
        "SE.COM Usage\r\n"
        "~   00    80h    32K    HBIOS System Firmware   "
        "Reserved: Protected HBIOS\r\n"
        "~   01    81h    32K    RAM Disk (MD0:)         "
        "Preserved: RAM Disk Active\r\n"
        "~   13    8Dh    32K    Application Memory      "
        "Active: 16K Line Slot Table\r\n"
        "~   14    8Eh    32K    CP/M 2.2 TPA & Base     "
        "Active: SE Program & Cache\r\n");
    for (r = 0; r < 13; r++) {
        hal_console_puts("~\r\n");
    }
    hal_console_puts(
        "~                          Press any key to continue\r\n");
    render_status_bar();
#else
    char line1[44];
    char line2[44];
    const char *mem_lines[6];
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
    render_tier1_workspace_screen(mem_lines, 6, 46);
#endif
}

void show_mem_info_screen(void)
{
    int k;
    uint8_t prev_splash = g_is_splash_screen;

    g_is_splash_screen = 1;
    hal_console_hide_cursor();

    while (1) {
        render_mem_info_content();
        while ((k = hal_console_getkey()) <= 0) {
            /* Wait for user keystroke */
        }
        if (k == KEY_CTRL_P) {
            show_plugin_palette_ctx(PLUG_CTX_MEM_INFO);
            if (!g_is_splash_screen) {
                return;
            }
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

void redraw_base_screen(uint8_t ctx)
{
    if (ctx == PLUG_CTX_EDITOR) {
        g_need_screen_render = 0;
        g_need_line_render = 0;
        g_need_status_render = 0;
        render_screen();
        locate_cursor();
    } else if (ctx == PLUG_CTX_SPLASH) {
        render_splash_content();
    } else if (ctx == PLUG_CTX_CONFIG) {
        render_config_content();
    } else if (ctx == PLUG_CTX_MEM_INFO) {
        render_mem_info_content();
    } else if (ctx == PLUG_CTX_HELP) {
        render_tier1_workspace_screen(s_help_lines, 22, 78);
    } else if (ctx == PLUG_CTX_ABOUT) {
        render_tier1_workspace_screen(s_about_lines, 9, 48);
    }
}
