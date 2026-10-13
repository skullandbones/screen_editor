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
char    g_status_msg[32] = {0};
#else
char    g_status_msg[80] = {0};
#endif

void ui_init(void)
{
    if (g_config.screen_mode == MODE_120X40) {
        g_active_cols = SCREEN_COLS_120;
        g_active_rows = SCREEN_ROWS_40;
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
    char line_buf[MAX_ACTIVE_LINE_STRIDE];
    uint16_t len;
    uint16_t vis_col = 0;
    uint16_t i;
    uint8_t tab_w = g_config.tab_width ? g_config.tab_width : 4;
    uint8_t max_content_cols = g_active_cols;

    hal_console_locate(screen_row, 1);

    if (doc_row >= g_doc_total_lines) {
        /* Beyond EOF: Column 0 Tilde Margin Discipline */
        hal_console_putc('~');
        hal_console_clear_eol();
        return;
    }

    len = fetch_line_to_buffer(doc_row, line_buf, MAX_ACTIVE_PAYLOAD);

    for (i = 0; i < len && vis_col < g_horiz_pan_offset + max_content_cols;
         i++) {
        char c = line_buf[i];
        if (c == '\t') {
            uint16_t next_tab = (uint16_t)((vis_col / tab_w + 1) * tab_w);
            while (vis_col < next_tab &&
                   vis_col < g_horiz_pan_offset + max_content_cols) {
                if (vis_col >= g_horiz_pan_offset) {
                    hal_console_putc(' ');
                }
                vis_col++;
            }
        } else {
            if (vis_col >= g_horiz_pan_offset) {
                int in_blk = check_cursor_in_block(doc_row, i);
                if (in_blk) hal_console_inverse_on();
                hal_console_putc(c);
                if (in_blk) hal_console_inverse_off();
            }
            vis_col++;
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
    char raw_name[32];
    char field1[32];
    char field2[16];
    char field3[16];
    char field4[32];
    char field5[40];
    const char *fname;
    char core[128];
    char full_bar[160];
    size_t pad, right_pad;
    size_t i, idx;
    uint16_t vis_col = 0;

    fname = g_current_filename[0] ? g_current_filename : "(Untitled)";
    char cpm_disp_name[64];
    if (g_current_filename[0] != '\0' && g_current_filename[1] != ':') {
        char drv = (char)('A' + bdos(25, 0));
        snprintf(cpm_disp_name, sizeof(cpm_disp_name), "%c:%s",
                 drv, g_current_filename);
        fname = cpm_disp_name;
    }
    snprintf(raw_name, sizeof(raw_name), "%s%c", fname,
             g_doc_modified ? '*' : ' ');
    snprintf(field1, sizeof(field1), "| %-14.14s | ", raw_name);

    if (g_active_cols == SCREEN_COLS_80 && g_active_rows == SCREEN_ROWS_24) {
        strcpy(field2, " 80x24 | ");
    } else if (g_active_cols == SCREEN_COLS_120 &&
               g_active_rows == SCREEN_ROWS_40) {
        strcpy(field2, "120x40 | ");
    } else {
        snprintf(field2, sizeof(field2), "%3ux%-2u | ",
                 (unsigned)g_active_cols, (unsigned)g_active_rows);
    }

    strcpy(field3, (g_file_format == FMT_CPM) ? "CP/M  | " : "Linux | ");

    if (g_is_splash_screen) {
        uint16_t free_kb = 320;
        if (g_doc_total_lines > 1) {
            uint16_t slots = (10 * 256 > g_doc_total_lines) ?
                             (10 * 256 - g_doc_total_lines) : 0;
            free_kb = slots / 8;
        }
        snprintf(field4, sizeof(field4), "Free: %u KB    | ",
                 (unsigned)free_kb);
    } else if (g_block_mode == BLOCK_MODE_SELECTING) {
        normalize_block_bounds();
        if (g_norm_start_row == g_norm_end_row) {
            uint16_t b_chars = (g_norm_end_col >= g_norm_start_col) ?
                (g_norm_end_col - g_norm_start_col) : 0;
            char sbuf[24];
            snprintf(sbuf, sizeof(sbuf), "Sel: %u chars", (unsigned)b_chars);
            snprintf(field4, sizeof(field4), "%-15s | ", sbuf);
        } else {
            uint16_t b_lines = (g_norm_end_row >= g_norm_start_row) ?
                (g_norm_end_row - g_norm_start_row + 1) : 1;
            char sbuf[16];
            snprintf(sbuf, sizeof(sbuf), "Sel: %u lines", (unsigned)b_lines);
            snprintf(field4, sizeof(field4), "%-15s | ", sbuf);
        }
    } else if (g_block_mode == BLOCK_MODE_SOLIDIFIED) {
        normalize_block_bounds();
        if (g_norm_start_row == g_norm_end_row) {
            uint16_t b_chars = (g_norm_end_col >= g_norm_start_col) ?
                (g_norm_end_col - g_norm_start_col) : 0;
            char sbuf[24];
            snprintf(sbuf, sizeof(sbuf), "Block: %u chars", (unsigned)b_chars);
            snprintf(field4, sizeof(field4), "%-15s | ", sbuf);
        } else {
            uint16_t b_lines = (g_norm_end_row >= g_norm_start_row) ?
                (g_norm_end_row - g_norm_start_row + 1) : 1;
            char sbuf[16];
            snprintf(sbuf, sizeof(sbuf), "Block: %u lines", (unsigned)b_lines);
            snprintf(field4, sizeof(field4), "%-15s | ", sbuf);
        }
    } else if (g_status_msg[0] != '\0') {
        snprintf(field4, sizeof(field4), "%-15s | ", g_status_msg);
    } else if (g_horiz_pan_offset > 0) {
        char pbuf[16];
        snprintf(pbuf, sizeof(pbuf), "[Pan +%u]", (unsigned)g_horiz_pan_offset);
        snprintf(field4, sizeof(field4), "%-15s | ", pbuf);
    } else if (!g_insert_mode) {
        strcpy(field4, "Overwrite mode  | ");
    } else {
        strcpy(field4, "^K: Editor keys | ");
    }

    if (g_doc_total_lines > 0 && g_cur_doc_row < g_doc_total_lines) {
        checkout_active_line(g_cur_doc_row);
        vis_col = calc_visual_col(g_active_line_buf, g_cur_col);
    }
    snprintf(field5, sizeof(field5), "Line %4u/%-4u Col %-3u |",
             (unsigned)(g_cur_doc_row + 1),
             (unsigned)g_doc_total_lines,
             (unsigned)vis_col);

    strcpy(core, field1);
    strcat(core, field2);
    strcat(core, field3);
    strcat(core, field4);
    strcat(core, field5);

    pad = (g_active_cols > 78) ? (g_active_cols - 78) / 2 : 1;
    right_pad = (g_active_cols > (78 + pad)) ? (g_active_cols - 78 - pad) : 1;

    idx = 0;
    for (i = 0; i < pad && idx + 1 < sizeof(full_bar); i++) {
        full_bar[idx++] = ' ';
    }
    for (i = 0; i < 78 && core[i] != '\0' && idx + 1 < sizeof(full_bar); i++) {
        full_bar[idx++] = core[i];
    }
    for (i = 0; i < right_pad && idx + 1 < sizeof(full_bar); i++) {
        full_bar[idx++] = ' ';
    }
    full_bar[idx] = '\0';

    hal_console_locate(g_active_rows, 1);
    hal_console_inverse_on();
    hal_console_puts(full_bar);
    hal_console_inverse_off();
}
#else
void render_status_bar(void)
{
    char raw_name[80];
    char field1[32];
    char field2[16];
    char field3[16];
    char field4[32];
    char field5[80];
    const char *fname;
    const char *fmt_str;
    char core[256];
    char full_bar[256];
    size_t core_len;
    size_t i, idx;

    fname = g_current_filename[0] ? g_current_filename : "(Untitled)";
    snprintf(raw_name, sizeof(raw_name), "%s%c", fname,
             g_doc_modified ? '*' : ' ');
    snprintf(field1, sizeof(field1), "| %-14.14s |", raw_name);

    if (g_active_cols == SCREEN_COLS_80 && g_active_rows == SCREEN_ROWS_24) {
        snprintf(field2, sizeof(field2), " 80x24 |");
    } else if (g_active_cols == SCREEN_COLS_120 &&
               g_active_rows == SCREEN_ROWS_40) {
        snprintf(field2, sizeof(field2), " 120x40 |");
    } else {
        snprintf(field2, sizeof(field2), " %ux%u |",
                 (unsigned)g_active_cols, (unsigned)g_active_rows);
    }

    fmt_str = (g_file_format == FMT_CPM) ? "CPM  " : "Linux";
    snprintf(field3, sizeof(field3), " %s |", fmt_str);

    snprintf(field4, sizeof(field4), " ^K: Editor keys |");

    {
        uint16_t vis_col = 0;
        char mode_flags[32];
        mode_flags[0] = '\0';

        if (g_doc_total_lines > 0 && g_cur_doc_row < g_doc_total_lines) {
            checkout_active_line(g_cur_doc_row);
            vis_col = calc_visual_col(g_active_line_buf, g_cur_col);
        }

        if (g_horiz_pan_offset > 0) {
            char pan_buf[16];
            snprintf(pan_buf, sizeof(pan_buf), " [Pan +%u]",
                     (unsigned)g_horiz_pan_offset);
            strncat(mode_flags, pan_buf,
                    sizeof(mode_flags) - strlen(mode_flags) - 1);
        }
        if (g_block_mode == BLOCK_MODE_SELECTING) {
            strncat(mode_flags, " [SEL]",
                    sizeof(mode_flags) - strlen(mode_flags) - 1);
        } else if (g_block_mode == BLOCK_MODE_SOLIDIFIED) {
            strncat(mode_flags, " [BLK LOCK]",
                    sizeof(mode_flags) - strlen(mode_flags) - 1);
        }

        snprintf(field5, sizeof(field5), " Line %4u/%-4u Col %-3u%s |",
                 (unsigned)(g_cur_doc_row + 1),
                 (unsigned)g_doc_total_lines,
                 (unsigned)vis_col,
                 mode_flags);

        snprintf(core, sizeof(core), "%s%s%s%s%s",
                 field1, field2, field3, field4, field5);
        core_len = strlen(core);

        if (core_len > g_active_cols && mode_flags[0] != '\0') {
            snprintf(field5, sizeof(field5), " Line %u/%u Col %u%s |",
                     (unsigned)(g_cur_doc_row + 1),
                     (unsigned)g_doc_total_lines,
                     (unsigned)vis_col,
                     mode_flags);
            snprintf(core, sizeof(core), "%s%s%s%s%s",
                     field1, field2, field3, field4, field5);
            core_len = strlen(core);
        }
    }

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
            hal_console_locate(r, left_col);
            hal_console_puts(lines[line_idx]);
        }
        hal_console_clear_eol();
    }

    /* Universal Status Bar presence on Row HOST_ROWS */
    render_status_bar();
}

void show_splash_screen(void)
{
    const char *splash_lines[24];
    size_t line_count;
    const char *screen_lbl;
    const char *ram_lbl;
    const char *plug_lbl;
    const char *lines_lbl;
    int k;
    char dlg_fname[32];
    uint8_t need_render = 1;

    g_is_splash_screen = 1;
    while (1) {
        if (need_render) {
            line_count = 0;
            splash_lines[line_count++] =
                "                  SE - Screen Editor                  ";
            splash_lines[line_count++] =
                "                                                      ";
            splash_lines[line_count++] =
                "        type   [E]  or  [Enter] to edit               ";
            splash_lines[line_count++] =
                "        type   [N]              to new file           ";
            splash_lines[line_count++] =
                "        type   [O]              to open file          ";
            splash_lines[line_count++] =
                "        type   [S]              to save file          ";
            splash_lines[line_count++] =
                "        type   [W]  or  [^W]    to close file         ";
            splash_lines[line_count++] =
                "        type   [L]  or  [^L]    to goto line          ";
            splash_lines[line_count++] =
                "        type   [A]              for about             ";
            splash_lines[line_count++] =
                "        type   [M]              for memory info       ";
            splash_lines[line_count++] =
                "        type   [P]              for plugins           ";
            splash_lines[line_count++] =
                "        type   [^P]             for context plugin menu";
            splash_lines[line_count++] =
                "        type   [C]              to configure          ";
            splash_lines[line_count++] =
                "        type   [1]              set 80x24             ";
            splash_lines[line_count++] =
                "        type   [2]              set 120x40            ";
#ifndef __CPM__
            splash_lines[line_count++] =
                "        type   [3]              set native            ";
#endif
            splash_lines[line_count++] =
                "        type   [Q]  or  [^Q]    to exit               ";
            splash_lines[line_count++] =
                "                                                      ";

            /* Dynamic system metadata rows per docs/UI_UX_DESIGN.md §7.2 */
            if (g_config.screen_mode == MODE_120X40) {
                screen_lbl =
                    "        Active Screen : [120x40 (Modern Default)]     ";
            } else if (g_config.screen_mode == MODE_NATIVE) {
                screen_lbl =
                    "        Active Screen : [Native (Dynamic Mode)]       ";
            } else {
                screen_lbl =
                    "        Active Screen : [80x24 (Classic Terminal)]    ";
            }
            splash_lines[line_count++] = screen_lbl;

            if (g_config.ramdrive_mode == RAMDRV_MODE_ENABLED) {
                ram_lbl =
                    "        RAM Drive (A:): [Overwritten (Max RAM)]       ";
            } else if (g_config.ramdrive_mode == RAMDRV_MODE_HIBERNATE) {
                ram_lbl =
                    "        RAM Drive (A:): [Hibernated (Temp Image)]     ";
            } else {
                ram_lbl =
                    "        RAM Drive (A:): [Preserved (Active)]          ";
            }
            splash_lines[line_count++] = ram_lbl;

            if (g_config.plugin_mode == PLUGIN_MODE_DISABLED) {
                plug_lbl =
                    "        Plugin System : [Disabled]                    ";
            } else if (g_config.plugin_mode == PLUGIN_MODE_ONDEMAND) {
                plug_lbl =
                    "        Plugin System : [On Demand]                   ";
            } else {
                plug_lbl =
                    "        Plugin System : [Operational]                 ";
            }
            splash_lines[line_count++] = plug_lbl;

            if (g_config.lines_mode == 1) {
                lines_lbl =
                    "        Max Lines     : [32,768 lines]                ";
            } else {
                lines_lbl =
                    "        Max Lines     : [16,384 lines]                ";
            }
            splash_lines[line_count++] = lines_lbl;
            splash_lines[line_count++] =
                "                                                      ";

            render_tier1_workspace_screen(splash_lines, line_count, 54);
            need_render = 0;
        }
        while ((k = hal_console_getkey()) <= 0) {
            /* Wait for user keystroke */
        }
        if (k == ':') {
            int next_k = 0;
            while ((next_k = hal_console_getkey()) <= 0) {
                /* Wait for following char */
            }
            k = next_k;
        }

        if (k == 'q' || k == 'Q' || k == KEY_CTRL_Q) {
            g_editor_exit_flag = 1;
            break;
        } else if (k == 'e' || k == 'E' || k == KEY_ENTER) {
            break;
        } else if (k == 'n' || k == 'N') {
            init_empty_document();
            g_current_filename[0] = '\0';
            break;
        } else if (k == 'o' || k == 'O' || k == KEY_CTRL_O) {
            dlg_fname[0] = '\0';
            if (ui_browser_open_dialog(dlg_fname, sizeof(dlg_fname)) ==
                MODAL_RES_OK && dlg_fname[0]) {
                file_load(dlg_fname);
                break;
            }
            need_render = 1;
        } else if (k == 's' || k == 'S' || k == KEY_CTRL_S) {
            dlg_fname[0] = '\0';
            if (ui_browser_save_dialog(dlg_fname, sizeof(dlg_fname)) ==
                MODAL_RES_OK && dlg_fname[0]) {
                file_save(dlg_fname, g_config.save_format);
            }
            need_render = 1;
        } else if (k == 'w' || k == 'W' || k == KEY_CTRL_W) {
            if (modal_confirm_save_changes() == MODAL_RES_OK) {
                init_empty_document();
                g_current_filename[0] = '\0';
            }
            need_render = 1;
        } else if (k == 'l' || k == 'L' || k == KEY_CTRL_L) {
            char lbuf[16] = {0};
            if (modal_goto_line(lbuf, sizeof(lbuf)) == MODAL_RES_OK &&
                lbuf[0]) {
                int line_num = atoi(lbuf);
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
        } else if (k == 'p' || k == 'P' || k == KEY_CTRL_P) {
            plugin_manager_ui();
            need_render = 1;
        } else if (k == '?' || k == 'h' || k == 'H' || k == KEY_CTRL_K) {
            show_help_screen();
            need_render = 1;
        } else if (k == '1') {
            clear_screen();
            g_config.screen_mode = MODE_80X24;
            g_active_cols = SCREEN_COLS_80;
            g_active_rows = SCREEN_ROWS_24;
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
    clear_screen();
    g_is_splash_screen = 0;
    g_need_screen_render = 1;
}

static const char *s_help_lines[22] = {
  "==========================================================================",
  "                    SE.COM - EDITOR MODE KEYS                             ",
  "==========================================================================",
  "  FILE & SYSTEM:                                                          ",
  "    Ctrl+O           Open file screen      Ctrl+S         Save file screen",
  "    Ctrl+W          Close file to splash   Ctrl+Q         Quit to CP/M    ",
  "    Ctrl+K          Help / Solidify block  Ctrl+P         Plugins pop-up  ",
  "  NAVIGATION & SEARCH:                                                    ",
  "    Arrow Keys      Move cursor            Ctrl+A / Home  Start of line   ",
  "    Ctrl+U / PgUp   Page Up                Ctrl+E / End   End of line     ",
  "    Ctrl+V / PgDn   Page Down              Ctrl+T / ^Home Top of file     ",
  "    Ctrl+L          Goto line number       Ctrl+G / ^End  Bottom of file  ",
  "    Ctrl+F          Find text              Ctrl+N         Find next       ",
  "    Ctrl+R          Search and Replace     Ctrl+I / Tab   Toggle find case",
  "  EDITING & BLOCK:                                                        ",
  "    Insert          Toggle Insert/Ovr      Enter          New line        ",
  "    ASCII 32..126   Insert/Overwrite text  Backspace      Delete left/join",
  "    Delete / Ctrl+D Delete char or block   Ctrl+B         Start/Toggle blk",
  "    Ctrl+C          Copy solidified block  Ctrl+K         Solidify block  ",
  "    Ctrl+X          Move solidified block  ESC            Clear block     ",
  "--------------------------------------------------------------------------",
  "                          Press any key to continue                       "
};

void show_help_screen(void)
{
    render_tier1_workspace_screen(s_help_lines, 22, 74);
    while (hal_console_getkey() <= 0) {
        /* Wait for user keystroke */
    }
    clear_screen();
    g_need_screen_render = 1;
}

void show_about_screen(void)
{
    static const char *s_about_lines[9] = {
        "                 SE - Screen Editor                   ",
        "           version 1.1.0 (2026-10-09) (C)             ",
        "                  by Dean Jenkins                     ",
        "                                                      ",
        "   Google Antigravity 2.19.1 & Gemini FLASH 3.8 high  ",
        "      Open source software under the MIT License      ",
        "                                                      ",
        "              Press any key to continue               ",
        "                                                      "
    };
    render_tier1_workspace_screen(s_about_lines, 9, 54);
    while (hal_console_getkey() <= 0) {
        /* Wait for user keystroke */
    }
    clear_screen();
    g_need_screen_render = 1;
}

void show_config_screen(void)
{
    char line_geom[64];
    char line_ram[64];
    char line_lines[64];
    char line_tab[64];
    char line_plug[64];
    const char *cfg_lines[10];
    const char *geom_str;
    const char *ram_str;
    const char *lines_str;
    const char *tab_str;
    const char *plug_str;
    int k;
    uint8_t need_render = 1;

    hal_console_hide_cursor();
    while (1) {
        if (g_config.screen_mode == MODE_120X40) {
            geom_str = "120x40 (Wide)";
        } else if (g_config.screen_mode == MODE_NATIVE) {
            geom_str = "Native";
        } else {
            geom_str = "80x24 (Classic)";
        }

        if (g_config.ramdrive_mode == RAMDRV_MODE_ENABLED) {
            ram_str = "Enabled";
        } else if (g_config.ramdrive_mode == RAMDRV_MODE_HIBERNATE) {
            ram_str = "Hibernate";
        } else {
            ram_str = "Protected";
        }

        if (g_config.lines_mode == 1) {
            lines_str = "32K (32,768 Lines)";
        } else {
            lines_str = "16K (16,384 Lines)";
        }

        if (g_config.tab_width == 4) {
            tab_str = "4 Spaces";
        } else {
            tab_str = "8 Spaces (Default)";
        }

        if (g_config.plugin_mode == PLUGIN_MODE_DISABLED) {
            plug_str = "Disabled";
        } else if (g_config.plugin_mode == PLUGIN_MODE_ONDEMAND) {
            plug_str = "On Demand";
        } else {
            plug_str = "Autoload";
        }

        snprintf(line_geom, sizeof(line_geom),
                 "         1. Screen Geometry  : %-22s ", geom_str);
        snprintf(line_ram, sizeof(line_ram),
                 "         2. RAM Drive Mode   : %-22s ", ram_str);
        snprintf(line_lines, sizeof(line_lines),
                 "         3. Max Doc Lines    : %-22s ", lines_str);
        snprintf(line_tab, sizeof(line_tab),
                 "         4. Tab Width        : %-22s ", tab_str);
        snprintf(line_plug, sizeof(line_plug),
                 "         5. Plugin Manager   : %-22s ", plug_str);

        cfg_lines[0] =
            "                  SE - Configuration Manager                  ";
        cfg_lines[1] = "                                                      ";
        cfg_lines[2] = line_geom;
        cfg_lines[3] = line_ram;
        cfg_lines[4] = line_lines;
        cfg_lines[5] = line_tab;
        cfg_lines[6] = line_plug;
        cfg_lines[7] = "                                                      ";
        cfg_lines[8] = " [1-5]=Toggle Option   [S]=Save Config   [ESC]=Exit  ";
        cfg_lines[9] = "                                                      ";

        if (need_render) {
            render_tier1_workspace_screen(cfg_lines, 10, 54);
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
        } else if (k == '5') {
            if (g_config.plugin_mode == PLUGIN_MODE_AUTOLOAD) {
                g_config.plugin_mode = PLUGIN_MODE_ONDEMAND;
            } else if (g_config.plugin_mode == PLUGIN_MODE_ONDEMAND) {
                g_config.plugin_mode = PLUGIN_MODE_DISABLED;
            } else {
                g_config.plugin_mode = PLUGIN_MODE_AUTOLOAD;
            }
            need_render = 1;
        } else if (k == 's' || k == 'S') {
            config_save();
            need_render = 1;
        }
    }
    clear_screen();
    g_need_screen_render = 1;
}

void show_mem_info_screen(void)
{
    char line1[64];
    char line2[64];
    const char *mem_lines[5];

    snprintf(line1, sizeof(line1), "      Free Virtual Slots: %-6u        ",
             (unsigned)mem_get_free_slots());
    snprintf(line2, sizeof(line2), "      Free Document Buffer: %-4u KB    ",
             (unsigned)mem_get_free_kb());
    mem_lines[0] = "    === Virtual Memory & Banking Status ===   ";
    mem_lines[1] = "                                              ";
    mem_lines[2] = line1;
    mem_lines[3] = line2;
    mem_lines[4] = "          Press any key to return...          ";

    render_tier1_workspace_screen(mem_lines, 5, 46);
    hal_console_getkey();
    clear_screen();
    g_need_screen_render = 1;
}
