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
#include "../include/config.h"
#include "../include/buffer.h"
#include "../include/editor.h"
#include "../include/block.h"
#include "../include/memory.h"
#include "../include/file_io.h"
#include "../include/ui.h"
#include "../include/ui_modal.h"
#include "../include/hal.h"

/* Global Display State Variables */
uint8_t g_active_cols = SCREEN_COLS_80;
uint8_t g_active_rows = SCREEN_ROWS_24;
uint8_t g_need_screen_render = 1;
uint8_t g_need_line_render = 0;
uint8_t g_need_status_render = 1;
char    g_status_msg[80] = {0};

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
    uint8_t tab_w = g_config.tab_width ? g_config.tab_width : 8;
    uint8_t max_content_cols = g_active_cols - 2;

    hal_console_locate(screen_row, 1);

    if (doc_row >= g_doc_total_lines) {
        /* Beyond EOF: Column 0 Tilde Margin Discipline */
        hal_console_putc('~');
        hal_console_clear_eol();
        return;
    }

    /* Column 0 Margin: Space or Block Marker */
    hal_console_putc(' ');

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

void render_status_bar(void)
{
    char raw_name[80];
    char field1[32];
    char field2[16];
    char field3[16];
    char field4[32];
    char field5[64];
    char pan_str[16];
    const char *blk_str;
    const char *fname;
    const char *geom_str;
    const char *fmt_str;
    char core[256];
    char full_bar[256];
    size_t core_len;
    size_t i, idx;

    fname = g_current_filename[0] ? g_current_filename : "(Untitled)";
    snprintf(raw_name, sizeof(raw_name), "%s%c", fname,
             g_doc_modified ? '*' : ' ');
    snprintf(field1, sizeof(field1), "| %-14.14s |", raw_name);

    geom_str = (g_config.screen_mode == MODE_120X40) ? "120x40" : "80x24";
    snprintf(field2, sizeof(field2), " %s |", geom_str);

    fmt_str = (g_file_format == FMT_CPM) ? "CPM  " : "Linux";
    snprintf(field3, sizeof(field3), " %s |", fmt_str);

    snprintf(field4, sizeof(field4), " ^K: Editor keys |");

    pan_str[0] = '\0';
    if (g_horiz_pan_offset > 0) {
        snprintf(pan_str, sizeof(pan_str), " [Pan +%u]",
                 (unsigned)g_horiz_pan_offset);
    }

    blk_str = "";
    if (g_block_mode == BLOCK_MODE_SELECTING) {
        blk_str = " [SEL]";
    } else if (g_block_mode == BLOCK_MODE_SOLIDIFIED) {
        blk_str = " [BLK LOCK]";
    }

    if (pan_str[0] != '\0' || blk_str[0] != '\0') {
        snprintf(field5, sizeof(field5), " Line %u/%u Col %u%s%s |",
                 (unsigned)(g_cur_doc_row + 1),
                 (unsigned)g_doc_total_lines,
                 (unsigned)g_cur_col,
                 pan_str, blk_str);
    } else {
        snprintf(field5, sizeof(field5), " Line %4u/%-4u Col %-3u |",
                 (unsigned)(g_cur_doc_row + 1),
                 (unsigned)g_doc_total_lines,
                 (unsigned)g_cur_col);
    }

    snprintf(core, sizeof(core), "%s%s%s%s%s",
             field1, field2, field3, field4, field5);
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
        strncpy(full_bar, core, g_active_cols);
        full_bar[g_active_cols] = '\0';
    }

    hal_console_locate(g_active_rows, 1);
    hal_console_inverse_on();
    hal_console_puts(full_bar);
    hal_console_inverse_off();
}

void show_splash_screen(void)
{
    clear_screen();
    render_status_bar();
    hal_console_locate(2, 25);
    hal_console_puts("========================================");
    hal_console_locate(3, 25);
    hal_console_puts("     SE.COM - Full Screen Editor        ");
    hal_console_locate(4, 25);
    hal_console_puts("            Version 1.1.0               ");
    hal_console_locate(5, 25);
    hal_console_puts("========================================");
    hal_console_locate(7, 20);
    hal_console_puts("Ctrl+O : Open File        Ctrl+S : Save Document");
    hal_console_locate(8, 20);
    hal_console_puts("Ctrl+Q : Quick Exit       Ctrl+F : Find Text    ");
    hal_console_locate(9, 20);
    hal_console_puts("Ctrl+R : Search & Replace Ctrl+B : Block Select ");
    hal_console_locate(10, 20);
    hal_console_puts("Ctrl+Y : Beautify Code    Ctrl+K : Mode Guide   ");
    hal_console_locate(13, 25);
    hal_console_puts("Press any key to start editing...");
    hal_console_getkey();
    clear_screen();
    g_need_screen_render = 1;
}

void show_about_screen(void)
{
    clear_screen();
    render_status_bar();
    hal_console_locate(5, 25);
    hal_console_puts("========================================");
    hal_console_locate(6, 25);
    hal_console_puts("    SE.COM - Multi-Platform Editor      ");
    hal_console_locate(7, 25);
    hal_console_puts("             Version 1.1.0              ");
    hal_console_locate(8, 25);
    hal_console_puts("       CP/M, ZX Spectrum Next, Linux    ");
    hal_console_locate(9, 25);
    hal_console_puts("========================================");
    hal_console_locate(12, 28);
    hal_console_puts("Press any key to return...");
    hal_console_getkey();
    clear_screen();
    g_need_screen_render = 1;
}

void show_config_screen(void)
{
    /* Render configuration options dialog */
    show_about_screen();
}

void show_mem_info_screen(void)
{
    char buf[64];
    clear_screen();
    render_status_bar();
    hal_console_locate(4, 25);
    hal_console_puts("=== Virtual Memory & Banking Status ===");
    snprintf(buf, sizeof(buf), "Free Virtual Slots: %u",
             (unsigned)mem_get_free_slots());
    hal_console_locate(6, 25);
    hal_console_puts(buf);
    snprintf(buf, sizeof(buf), "Free Document Buffer: %u KB",
             (unsigned)mem_get_free_kb());
    hal_console_locate(7, 25);
    hal_console_puts(buf);
    hal_console_locate(10, 28);
    hal_console_puts("Press any key to return...");
    hal_console_getkey();
    clear_screen();
    g_need_screen_render = 1;
}
