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
    static const char *s_splash_lines[14] = {
        "              SE.COM — Screen Editor              ",
        "              Version v1.1.0 (Linux)              ",
        "                                                  ",
        "       Free Memory: [Dynamic Heap]   Lines: [32K] ",
        "                                                  ",
        "                     :e to edit                   ",
        "                     :o to open file              ",
        "                     :s to save file              ",
        "                     :c for config                ",
        "                     :p for plugins               ",
        "                     :? for help                  ",
        "                     :q to quit                   ",
        "                                                  ",
        "                   Enter choice: _                "
    };
    int k;

    render_tier1_workspace_screen(s_splash_lines, 14, 50);
    while ((k = hal_console_getkey()) <= 0) {
        /* Wait for user keystroke */
    }
    if (k == 'q' || k == 'Q' || k == KEY_CTRL_Q) {
        g_editor_exit_flag = 1;
    }
    clear_screen();
    g_need_screen_render = 1;
}

static const char *s_help_lines[17] = {
    "                       SE.COM — EDITOR MODE KEYS                      ",
    "                                                                      ",
    "  Cursor Navigation:                 Block Operations:                ",
    "    Arrows / WordStar (^S,^D,^E,^X)     Ctrl+B: Toggle Block          ",
    "    Ctrl+A / Ctrl+E: Home / End         Ctrl+C: Copy Block            ",
    "    Ctrl+T / Ctrl+G: Top / Bottom       Ctrl+X: Cut Block             ",
    "    Ctrl+U / Ctrl+V: Page Up / Down     Ctrl+V: Paste Block           ",
    "                                                                      ",
    "  Search & Replace:                  File & System:                   ",
    "    Ctrl+F: Find Text                   Ctrl+S: Save File             ",
    "    Ctrl+N: Find Next                   Ctrl+O: Open File             ",
    "    Ctrl+R: Search and Replace          Ctrl+Q: Safe Quit             ",
    "    Ctrl+L: Goto Line Number            Ctrl+P: Plugin Palette        ",
    "    Ctrl+Y: Beautify Source Code        ESC   : Splash Screen         ",
    "                                                                      ",
    "                   Press any key to return to editor                  ",
    "                                                                      "
};

void show_help_screen(void)
{
    render_tier1_workspace_screen(s_help_lines, 17, 70);
    while (hal_console_getkey() <= 0) {
        /* Wait for user keystroke */
    }
    clear_screen();
    g_need_screen_render = 1;
}

void show_about_screen(void)
{
    static const char *s_about_lines[6] = {
        "        SE.COM — Screen Editor (Linux)        ",
        "                Version v1.1.0                ",
        "                                              ",
        "        CP/M, ZX Spectrum Next, Linux         ",
        "                                              ",
        "          Press any key to return...          "
    };
    render_tier1_workspace_screen(s_about_lines, 6, 46);
    while (hal_console_getkey() <= 0) {
        /* Wait for user keystroke */
    }
    clear_screen();
    g_need_screen_render = 1;
}

void show_config_screen(void)
{
    static const char *s_config_lines[11] = {
        "            SE — Configuration Manager            ",
        "                                                  ",
        "         1. Screen Geometry  : 80x24              ",
        "         2. Tab Width        : 8                  ",
        "         3. Max Line Capacity: 32K                ",
        "         4. RAM Drive Mode   : Disabled           ",
        "                                                  ",
        "   [S] Save to SE.CFG    [ESC]/[Enter] Return     ",
        "                                                  ",
        "                Enter option: _                   ",
        "                                                  "
    };
    render_tier1_workspace_screen(s_config_lines, 11, 50);
    hal_console_getkey();
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
