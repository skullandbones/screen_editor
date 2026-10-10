/*==============================================================================
 * UI_BROWSER.C: Core Subsystem - File Browser, Selection & Pagination Modals
 *
 * Purpose:
 *   Implements interactive directory browser screens, file list pagination,
 *   drive/user area switching, and Open/Save file dialogs.
 *   C semantic equivalent to src/core/ui_browser.asm.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <strings.h>
#include <fnmatch.h>
#ifndef FNM_CASEFOLD
#define FNM_CASEFOLD 0
#endif
#include "../include/config.h"
#include "../include/buffer.h"
#include "../include/ui.h"
#include "../include/ui_modal.h"
#include "../include/ui_browser.h"
#include "../include/file_io.h"
#include "../include/hal.h"

static browser_entry_t s_browser_files[MAX_BROWSER_FILES];
static int             s_browser_count = 0;

void ui_browser_clear_entries(void)
{
    s_browser_count = 0;
}

int ui_browser_add_entry(const char *name, uint32_t size, uint8_t is_dir)
{
    if (s_browser_count >= MAX_BROWSER_FILES) {
        return -1;
    }
    strncpy(s_browser_files[s_browser_count].filename, name,
            sizeof(s_browser_files[s_browser_count].filename) - 1);
    s_browser_files[s_browser_count].filename[
        sizeof(s_browser_files[s_browser_count].filename) - 1] = '\0';
    s_browser_files[s_browser_count].size_bytes = size;
    s_browser_files[s_browser_count].is_dir = is_dir;
    s_browser_files[s_browser_count].drive = 0;
    s_browser_files[s_browser_count].user = 0;
    s_browser_count++;
    return 0;
}

static int compare_entries(const void *a, const void *b)
{
    const browser_entry_t *ea = (const browser_entry_t *)a;
    const browser_entry_t *eb = (const browser_entry_t *)b;
    if (ea->is_dir != eb->is_dir) {
        return eb->is_dir - ea->is_dir;
    }
    return strcasecmp(ea->filename, eb->filename);
}

void ui_browser_refresh_directory(const char *mask)
{
    ui_browser_clear_entries();
#ifdef __linux__
    hal_linux_scan_directory(".");
#endif
    if (mask && mask[0] != '\0' && (strchr(mask, '*') || strchr(mask, '?'))) {
        int i, write_idx = 0;
        for (i = 0; i < s_browser_count; i++) {
            if (fnmatch(mask, s_browser_files[i].filename, FNM_CASEFOLD) == 0) {
                if (write_idx != i) {
                    s_browser_files[write_idx] = s_browser_files[i];
                }
                write_idx++;
            }
        }
        s_browser_count = write_idx;
    }
    if (s_browser_count == 0) {
        ui_browser_add_entry("README.TXT", 2048, 0);
    }
    qsort(s_browser_files, s_browser_count, sizeof(browser_entry_t),
          compare_entries);
}

int ui_browser_get_file_count(void)
{
    return s_browser_count;
}

const browser_entry_t *ui_browser_get_entry(int index)
{
    if (index >= 0 && index < s_browser_count) {
        return &s_browser_files[index];
    }
    return NULL;
}

static int ui_browser_workspace(int mode, char *selected_filename,
                                size_t max_len)
{
    char input_buf[64] = {0};
    size_t cursor_pos = 0;
    int cur_page = 0;
    int selected_idx = 0;
    const char *title;
    const char *prompt_lbl;

    if (mode == BROWSER_MODE_OPEN) {
        title = "OPEN FILE (DIRECTORY)";
        prompt_lbl = "  Enter filename to open: [ ";
    } else if (mode == BROWSER_MODE_INSERT) {
        title = "INSERT FILE (DIRECTORY)";
        prompt_lbl = "  Enter filename to insert: [ ";
    } else if (mode == BROWSER_MODE_SAVE_BLOCK) {
        title = "SAVE BLOCK (DIRECTORY)";
        prompt_lbl = "  Enter filename to save: [ ";
    } else {
        title = "SAVE FILE (DIRECTORY)";
        prompt_lbl = "  Enter filename to save: [ ";
    }

    if (selected_filename && selected_filename[0] != '\0') {
        strncpy(input_buf, selected_filename, sizeof(input_buf) - 1);
        cursor_pos = strlen(input_buf);
    }

    ui_browser_refresh_directory(NULL);

    while (1) {
        int num_cols = (g_active_cols >= 120) ? 7 : 5;
        int col_width = (g_active_cols >= 120) ? 16 : 14;
        int num_rows = (g_active_rows >= 40) ? 28 : 12;
        int files_per_page = num_cols * num_rows;
        int total_pages = (s_browser_count > 0)
            ? ((s_browser_count + files_per_page - 1) / files_per_page) : 1;
        int content_width = (g_active_cols >= 120) ? 114 : 70;
        int page_start;
        int r, col, c;
        uint8_t screen_row;
        uint8_t prompt_row;
        uint8_t prompt_col;
        int k;

        if (cur_page >= total_pages) cur_page = total_pages - 1;
        if (cur_page < 0) cur_page = 0;
        page_start = cur_page * files_per_page;

        /* Row 1: Header double rule */
        hal_console_locate(1, 1);
        hal_console_putc('~');
        for (c = 2; c <= content_width; c++) hal_console_putc('=');
        hal_console_clear_eol();

        /* Row 2: Centered Title */
        hal_console_locate(2, 1);
        hal_console_putc('~');
        size_t tlen = strlen(title);
        uint8_t tleft = (content_width > (int)tlen)
            ? (uint8_t)(((content_width - (int)tlen) / 2) + 1) : 2;
        hal_console_locate(2, tleft);
        hal_console_puts(title);
        hal_console_clear_eol();

        /* Row 3: Header bottom rule */
        hal_console_locate(3, 1);
        hal_console_putc('~');
        for (c = 2; c <= content_width; c++) hal_console_putc('=');
        hal_console_clear_eol();

        /* Rows 4..(3 + num_rows): File Grid */
        for (r = 0; r < num_rows; r++) {
            screen_row = (uint8_t)(4 + r);
            hal_console_locate(screen_row, 1);
            hal_console_putc('~');
            hal_console_puts("  ");
            for (col = 0; col < num_cols; col++) {
                int entry_idx = page_start + (r * num_cols) + col;
                char cell[32];
                if (entry_idx < s_browser_count) {
                    snprintf(cell, sizeof(cell), "%-*.*s",
                             col_width, col_width,
                             s_browser_files[entry_idx].filename);
                    if (entry_idx == selected_idx) {
                        hal_console_inverse_on();
                    }
                    hal_console_puts(cell);
                    if (entry_idx == selected_idx) {
                        hal_console_inverse_off();
                    }
                } else {
                    snprintf(cell, sizeof(cell), "%*s", col_width, "");
                    hal_console_puts(cell);
                }
            }
            hal_console_clear_eol();
        }

        /* Blank row after grid */
        screen_row = (uint8_t)(4 + num_rows);
        hal_console_locate(screen_row, 1);
        hal_console_putc('~');
        hal_console_clear_eol();

        /* Page indicator or Format toggle row */
        screen_row++;
        hal_console_locate(screen_row, 1);
        hal_console_putc('~');
        if (mode == BROWSER_MODE_SAVE || mode == BROWSER_MODE_SAVE_BLOCK) {
            char fmt_buf[64];
            const char *fmt_name = (g_config.save_format == FMT_CPM)
                ? "CP/M" : "Linux";
            snprintf(fmt_buf, sizeof(fmt_buf),
                     "  Format: [%s]   [^F]=Toggle Format", fmt_name);
            hal_console_puts(fmt_buf);
        } else {
            char page_buf[64];
            snprintf(page_buf, sizeof(page_buf),
                     "  [Page %d/%d]  <PgUp>/<PgDn>=Page",
                     cur_page + 1, total_pages);
            hal_console_puts(page_buf);
        }
        hal_console_clear_eol();

        /* Divider rule */
        screen_row++;
        hal_console_locate(screen_row, 1);
        hal_console_putc('~');
        for (c = 2; c <= content_width; c++) hal_console_putc('-');
        hal_console_clear_eol();

        /* Guide options */
        screen_row++;
        hal_console_locate(screen_row, 1);
        hal_console_putc('~');
        hal_console_puts("  [ESC]=Cancel  [pattern] to list (e.g. *.TXT)");
        hal_console_clear_eol();

        /* Prompt line */
        screen_row++;
        prompt_row = screen_row;
        hal_console_locate(prompt_row, 1);
        hal_console_putc('~');
        hal_console_puts(prompt_lbl);
        hal_console_puts(input_buf);
        int rem = 30 - (int)strlen(input_buf);
        if (rem < 0) rem = 0;
        for (c = 0; c < rem; c++) hal_console_putc(' ');
        hal_console_puts(" ]");
        hal_console_clear_eol();

        /* Empty margin rows up to HOST_ROWS - 1 */
        for (r = prompt_row + 1; r < g_active_rows; r++) {
            hal_console_locate((uint8_t)r, 1);
            hal_console_putc('~');
            hal_console_clear_eol();
        }

        /* Status Bar at Row HOST_ROWS */
        render_status_bar();

        /* Position terminal cursor in filename prompt */
        prompt_col = (uint8_t)(1 + strlen(prompt_lbl) + cursor_pos);
        hal_console_locate(prompt_row, prompt_col);
        hal_console_show_cursor();

        k = hal_console_getkey();
        if (k == KEY_ESC) {
            g_need_screen_render = 1;
            return MODAL_RES_CANCEL;
        } else if (k == KEY_ENTER || k == '\n' || k == '\r') {
            g_need_screen_render = 1;
            if (input_buf[0] != '\0') {
                if (strchr(input_buf, '*') || strchr(input_buf, '?')) {
                    ui_browser_refresh_directory(input_buf);
                    cur_page = 0;
                    selected_idx = 0;
                    input_buf[0] = '\0';
                    cursor_pos = 0;
                    continue;
                }
                if (input_buf[strlen(input_buf) - 1] == '/') {
                    hal_linux_scan_directory(input_buf);
                    cur_page = 0;
                    selected_idx = 0;
                    input_buf[0] = '\0';
                    cursor_pos = 0;
                    continue;
                }
                strncpy(selected_filename, input_buf, max_len - 1);
                selected_filename[max_len - 1] = '\0';
                return MODAL_RES_OK;
            } else if (selected_idx >= 0 && selected_idx < s_browser_count) {
                strncpy(selected_filename,
                        s_browser_files[selected_idx].filename,
                        max_len - 1);
                selected_filename[max_len - 1] = '\0';
                return MODAL_RES_OK;
            }
        } else if (k == KEY_CTRL_F) {
            if (mode == BROWSER_MODE_SAVE || mode == BROWSER_MODE_SAVE_BLOCK) {
                g_config.save_format = (g_config.save_format == FMT_CPM)
                    ? FMT_LINUX : FMT_CPM;
                g_file_format = g_config.save_format;
            }
        } else if (k == KEY_PGUP || k == KEY_CTRL_R) {
            if (cur_page > 0) {
                cur_page--;
                selected_idx = cur_page * files_per_page;
                if (s_browser_count > 0) {
                    strncpy(input_buf, s_browser_files[selected_idx].filename,
                            sizeof(input_buf) - 1);
                    input_buf[sizeof(input_buf) - 1] = '\0';
                    cursor_pos = strlen(input_buf);
                }
            }
        } else if (k == KEY_PGDN || k == KEY_CTRL_C) {
            if (cur_page + 1 < total_pages) {
                cur_page++;
                selected_idx = cur_page * files_per_page;
                if (selected_idx >= s_browser_count) {
                    selected_idx = s_browser_count - 1;
                }
                if (s_browser_count > 0 && selected_idx >= 0) {
                    strncpy(input_buf, s_browser_files[selected_idx].filename,
                            sizeof(input_buf) - 1);
                    input_buf[sizeof(input_buf) - 1] = '\0';
                    cursor_pos = strlen(input_buf);
                }
            }
        } else if (k == KEY_UP || k == KEY_CTRL_E) {
            if (s_browser_count > 0) {
                if (selected_idx >= num_cols) {
                    selected_idx -= num_cols;
                } else {
                    selected_idx = 0;
                }
                cur_page = selected_idx / files_per_page;
                strncpy(input_buf, s_browser_files[selected_idx].filename,
                        sizeof(input_buf) - 1);
                input_buf[sizeof(input_buf) - 1] = '\0';
                cursor_pos = strlen(input_buf);
            }
        } else if (k == KEY_DOWN || k == KEY_CTRL_X) {
            if (s_browser_count > 0) {
                if (selected_idx + num_cols < s_browser_count) {
                    selected_idx += num_cols;
                } else {
                    selected_idx = s_browser_count - 1;
                }
                cur_page = selected_idx / files_per_page;
                strncpy(input_buf, s_browser_files[selected_idx].filename,
                        sizeof(input_buf) - 1);
                input_buf[sizeof(input_buf) - 1] = '\0';
                cursor_pos = strlen(input_buf);
            }
        } else if (k == KEY_BACKSPACE || k == '\b' || k == 127 || k == 8) {
            if (cursor_pos > 0) {
                memmove(&input_buf[cursor_pos - 1], &input_buf[cursor_pos],
                        strlen(&input_buf[cursor_pos]) + 1);
                cursor_pos--;
            }
        } else if (k == KEY_LEFT) {
            if (cursor_pos > 0) {
                cursor_pos--;
            }
        } else if (k == KEY_RIGHT) {
            if (cursor_pos < strlen(input_buf)) {
                cursor_pos++;
            }
        } else if (k == KEY_HOME || k == KEY_CTRL_A) {
            cursor_pos = 0;
        } else if (k == KEY_END) {
            cursor_pos = strlen(input_buf);
        } else if (k >= 32 && k <= 126) {
            size_t in_len = strlen(input_buf);
            if (in_len + 1 < sizeof(input_buf) - 1) {
                memmove(&input_buf[cursor_pos + 1], &input_buf[cursor_pos],
                        in_len - cursor_pos + 1);
                input_buf[cursor_pos] = (char)k;
                cursor_pos++;
            }
        }
    }
}

int ui_browser_open_dialog(char *selected_filename, size_t max_len)
{
    return ui_browser_workspace(BROWSER_MODE_OPEN, selected_filename, max_len);
}

int ui_browser_save_dialog(char *selected_filename, size_t max_len)
{
    return ui_browser_workspace(BROWSER_MODE_SAVE, selected_filename, max_len);
}

int ui_browser_insert_dialog(char *selected_filename, size_t max_len)
{
    return ui_browser_workspace(BROWSER_MODE_INSERT, selected_filename,
                                max_len);
}

int ui_browser_save_block_dialog(char *selected_filename, size_t max_len)
{
    return ui_browser_workspace(BROWSER_MODE_SAVE_BLOCK, selected_filename,
                                max_len);
}
