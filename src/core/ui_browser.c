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
#ifndef __CPM__
#include <strings.h>
#include <unistd.h>
#include <fnmatch.h>
#ifndef FNM_CASEFOLD
#define FNM_CASEFOLD 0
#endif
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
            BROWSER_FILENAME_LEN - 1);
    s_browser_files[s_browser_count].filename[
        BROWSER_FILENAME_LEN - 1] = '\0';
#ifndef __CPM__
    s_browser_files[s_browser_count].size_bytes = size;
#else
    (void)size;
#endif
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
#ifdef __CPM__
    return strcmp(ea->filename, eb->filename);
#else
    return strcasecmp(ea->filename, eb->filename);
#endif
}

#ifdef __CPM__
#define s_dir_dma g_cpm_dma_buf
#define s_dir_fcb ((uint8_t *)&g_cpm_fcb)
static char    s_browser_drive = 'C';
static uint8_t s_browser_user = 0;
static char    s_browser_filter[16] = {0};
static char    s_browser_title[80];
static char    s_browser_input[64];

static void format_mask_to_fcb(const char *mask, uint8_t *fcb)
{
    int i;
    const char *p = mask;
    if (p && p[0] && p[1] == ':') {
        p += 2;
    }
    memset(&fcb[1], ' ', 11);
    if (!p || *p == '\0') {
        memset(&fcb[1], '?', 11);
        return;
    }
    for (i = 1; i <= 8 && *p && *p != '.'; ) {
        if (*p == '*') {
            while (i <= 8) fcb[i++] = '?';
            p++;
            break;
        } else {
            char ch = *p++;
            if (ch >= 'a' && ch <= 'z') ch -= 32;
            fcb[i++] = (uint8_t)ch;
        }
    }
    while (*p && *p != '.') p++;
    if (*p == '.') p++;
    for (i = 9; i <= 11 && *p; ) {
        if (*p == '*') {
            while (i <= 11) fcb[i++] = '?';
            p++;
            break;
        } else {
            char ch = *p++;
            if (ch >= 'a' && ch <= 'z') ch -= 32;
            fcb[i++] = (uint8_t)ch;
        }
    }
    while (i <= 11) {
        fcb[i++] = ' ';
    }
}

static void scan_cpm_directory(char drive, uint8_t user, const char *mask)
{
    int orig_user;
    int res;
    uint8_t drv_num;

    if (drive >= 'a' && drive <= 'p') {
        drv_num = (uint8_t)(drive - 'a' + 1);
    } else if (drive >= 'A' && drive <= 'P') {
        drv_num = (uint8_t)(drive - 'A' + 1);
    } else {
        drv_num = 0;
    }

    memset(&g_cpm_fcb, 0, sizeof(cpm_fcb_t));
    s_dir_fcb[0] = drv_num;
    format_mask_to_fcb(mask, s_dir_fcb);

    bdos(26, (int)s_dir_dma);
    orig_user = bdos(32, 0xFF);
    bdos(32, user);

    res = bdos(17, (int)s_dir_fcb);
    while (res != 0xFF && res >= 0 && res <= 3) {
        uint8_t *entry = &s_dir_dma[res * 32];
        if (entry[0] == user) {
            char name[16];
            int ni = 0;
            int j;
            for (j = 1; j <= 8; j++) {
                char c = (char)(entry[j] & 0x7F);
                if (c != ' ' && c != 0) {
                    name[ni++] = c;
                }
            }
            if (ni > 0 && !(name[0] == '$' && name[1] == '$' &&
                           name[2] == '$')) {
                int has_ext = 0;
                for (j = 9; j <= 11; j++) {
                    char c = (char)(entry[j] & 0x7F);
                    if (c != ' ' && c != 0) {
                        has_ext = 1;
                        break;
                    }
                }
                if (has_ext) {
                    name[ni++] = '.';
                    for (j = 9; j <= 11; j++) {
                        char c = (char)(entry[j] & 0x7F);
                        if (c != ' ' && c != 0) {
                            name[ni++] = c;
                        }
                    }
                }
                name[ni] = '\0';

                {
                    int dup = 0;
                    int k;
                    for (k = 0; k < s_browser_count; k++) {
                        if (strcmp(s_browser_files[k].filename, name) == 0) {
                            dup = 1;
                            break;
                        }
                    }
                    if (!dup && s_browser_count < MAX_BROWSER_FILES) {
                        ui_browser_add_entry(name, 128, 0);
                    }
                }
            }
        }
        res = bdos(18, (int)s_dir_fcb);
    }
    bdos(26, DEFAULT_DMA);
    bdos(32, orig_user);
}
#endif

void ui_browser_refresh_directory(const char *mask)
{
    ui_browser_clear_entries();
#ifdef __linux__
    hal_linux_scan_directory(".");
    if (mask && mask[0] != '\0' && (strchr(mask, '*') || strchr(mask, '?'))) {
        int i, write_idx = 0;
        for (i = 0; i < s_browser_count; i++) {
            if (fnmatch(mask, s_browser_files[i].filename,
                        FNM_CASEFOLD) == 0) {
                if (write_idx != i) {
                    s_browser_files[write_idx] = s_browser_files[i];
                }
                write_idx++;
            }
        }
        s_browser_count = write_idx;
    }
#elif defined(__CPM__)
    scan_cpm_directory(s_browser_drive, s_browser_user, mask);
#endif
#ifdef __CPM__
    {
        int i, j;
        browser_entry_t temp;
        for (i = 1; i < s_browser_count; i++) {
            temp = s_browser_files[i];
            j = i - 1;
            while (j >= 0 && compare_entries(&s_browser_files[j], &temp) > 0) {
                s_browser_files[j + 1] = s_browser_files[j];
                j--;
            }
            s_browser_files[j + 1] = temp;
        }
    }
#else
    qsort(s_browser_files, s_browser_count, sizeof(browser_entry_t),
          compare_entries);
#endif
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

static void render_browser_prompt(uint8_t prompt_row, const char *prompt_lbl,
                                  const char *input_buf, size_t cursor_pos)
{
    int c;
    int rem;
    uint8_t prompt_col;

    hal_console_locate(prompt_row, 1);
    hal_console_putc('~');
    hal_console_puts(prompt_lbl);
    hal_console_puts(input_buf);
    rem = 20 - (int)strlen(input_buf);
    if (rem < 0) {
        rem = 0;
    }
    for (c = 0; c < rem; c++) {
        hal_console_putc(' ');
    }
    hal_console_putc(']');
    hal_console_clear_eol();
    prompt_col = (uint8_t)(1 + strlen(prompt_lbl) + cursor_pos);
    hal_console_locate(prompt_row, prompt_col);
    hal_console_show_cursor();
}

static int ui_browser_workspace(int mode, char *selected_filename,
                                size_t max_len)
{
#ifdef __CPM__
#define input_buf s_browser_input
#define title_buf s_browser_title
    memset(s_browser_input, 0, sizeof(s_browser_input));
    memset(s_browser_title, 0, sizeof(s_browser_title));
#else
    char input_buf[64] = {0};
    char title_buf[80];
#endif
    size_t cursor_pos = 0;
    int cur_page = 0;
    int selected_idx = 0;
    const char *op_str;
    const char *prompt_lbl;
    int num_cols;
    int col_width;
    int num_rows;
    int files_per_page;
    int content_width;
    uint8_t prompt_row;
    int need_full_render = 1;

#ifdef __CPM__
    s_browser_drive = (char)('A' + bdos(25, 0));
    s_browser_user = (uint8_t)bdos(32, 0xFF);
    s_browser_filter[0] = '\0';
#endif

    if (mode == BROWSER_MODE_OPEN) {
        op_str = "OPEN FILE";
        prompt_lbl = "  Enter filename to open: [";
    } else if (mode == BROWSER_MODE_INSERT) {
        op_str = "INSERT FILE";
        prompt_lbl = "  Enter filename to insert: [";
    } else if (mode == BROWSER_MODE_SAVE_BLOCK) {
        op_str = "SAVE BLOCK";
        prompt_lbl = "  Enter filename to save: [";
    } else {
        op_str = "SAVE FILE";
        prompt_lbl = "  Enter filename to save: [";
    }

    if (selected_filename && selected_filename[0] != '\0') {
        strncpy(input_buf, selected_filename, sizeof(input_buf) - 1);
        cursor_pos = strlen(input_buf);
    }

    ui_browser_refresh_directory(NULL);

    num_cols = (g_active_cols >= 120) ? 7 : 5;
    col_width = (g_active_cols >= 120) ? 16 : 14;
    num_rows = (g_active_rows >= 40) ? 28 : 12;
    files_per_page = num_cols * num_rows;
    content_width = (g_active_cols >= 120) ? 114 : 70;
    prompt_row = (uint8_t)(8 + num_rows);

    int k = 0;

    while (1) {
        int total_pages = (s_browser_count > 0)
            ? ((s_browser_count + files_per_page - 1) / files_per_page) : 1;
        uint8_t prompt_col;

        if (need_full_render) {
            int page_start;
            int r, col, c;
            uint8_t screen_row;
            size_t tlen;
            uint8_t tleft;

#ifdef __CPM__
            if (s_browser_filter[0] != '\0') {
                if (s_browser_user > 0) {
                    snprintf(title_buf, sizeof(title_buf),
                             "%s (DIRECTORY - DRIVE %c%u: [%s])",
                             op_str, s_browser_drive, (unsigned)s_browser_user,
                             s_browser_filter);
                } else {
                    snprintf(title_buf, sizeof(title_buf),
                             "%s (DIRECTORY - DRIVE %c: [%s])",
                             op_str, s_browser_drive, s_browser_filter);
                }
            } else {
                if (s_browser_user > 0) {
                    snprintf(title_buf, sizeof(title_buf),
                             "%s (DIRECTORY - DRIVE %c%u:)",
                             op_str, s_browser_drive, (unsigned)s_browser_user);
                } else {
                    snprintf(title_buf, sizeof(title_buf),
                             "%s (DIRECTORY - DRIVE %c:)",
                             op_str, s_browser_drive);
                }
            }
#else
            snprintf(title_buf, sizeof(title_buf), "%s (DIRECTORY)", op_str);
#endif

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
            tlen = strlen(title_buf);
            tleft = (content_width > (int)tlen)
                ? (uint8_t)(((content_width - (int)tlen) / 2) + 1) : 2;
            hal_console_locate(2, tleft);
            hal_console_puts(title_buf);
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
                    if (entry_idx < s_browser_count) {
                        const char *fn = s_browser_files[entry_idx].filename;
                        size_t fn_len = strlen(fn);
                        int p;
                        if (entry_idx == selected_idx) {
                            hal_console_inverse_on();
                        }
                        hal_console_puts(fn);
                        for (p = (int)fn_len; p < col_width; p++) {
                            hal_console_putc(' ');
                        }
                        if (entry_idx == selected_idx) {
                            hal_console_inverse_off();
                        }
                    } else {
                        int p;
                        for (p = 0; p < col_width; p++) {
                            hal_console_putc(' ');
                        }
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
                hal_console_puts("  Format: [");
                hal_console_puts((g_config.save_format == FMT_CPM)
                                 ? "CP/M" : "Linux");
                hal_console_puts("]   [^F]=Toggle Format");
            } else if (total_pages > 1) {
                char pbuf[48];
                snprintf(pbuf, sizeof(pbuf),
                         "  [Page %d/%d]  <PgUp>/<PgDn>=Page",
                         cur_page + 1, total_pages);
                hal_console_puts(pbuf);
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
            hal_console_puts(
                "  [ESC]=Cancel  [d:][u:][pattern] to list (e.g. B:, *.TXT)");
            hal_console_clear_eol();

            /* Prompt line */
            render_browser_prompt(prompt_row, prompt_lbl, input_buf,
                                  cursor_pos);

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

            need_full_render = 0;
        }

        while ((k = hal_console_getkey()) <= 0) {
#ifndef __CPM__
            usleep(5000);
#endif
        }
        if (k == KEY_ESC) {
            g_need_screen_render = 1;
            return MODAL_RES_CANCEL;
        } else if (k == KEY_ENTER || k == '\n' || k == '\r') {
            g_need_screen_render = 1;
            if (input_buf[0] != '\0') {
#ifdef __CPM__
                size_t in_len = strlen(input_buf);
                if (in_len >= 2 && input_buf[in_len - 1] == ':') {
                    int is_switch = 1;
                    char new_drv = 0;
                    int new_usr = -1;
                    size_t idx;
                    for (idx = 0; idx < in_len - 1; idx++) {
                        char ch = input_buf[idx];
                        if ((ch >= 'A' && ch <= 'P') ||
                            (ch >= 'a' && ch <= 'p')) {
                            if (new_drv != 0) { is_switch = 0; break; }
                            new_drv = (ch >= 'a') ? (char)(ch - 32) : ch;
                        } else if (ch >= '0' && ch <= '9') {
                            if (new_usr < 0) new_usr = ch - '0';
                            else new_usr = new_usr * 10 + (ch - '0');
                        } else {
                            is_switch = 0;
                            break;
                        }
                    }
                    if (is_switch && (new_drv != 0 || new_usr >= 0)) {
                        if (new_drv != 0) s_browser_drive = new_drv;
                        if (new_usr >= 0 && new_usr <= 15) {
                            s_browser_user = (uint8_t)new_usr;
                        }
                        ui_browser_refresh_directory(s_browser_filter);
                        cur_page = 0;
                        selected_idx = 0;
                        cursor_pos = strlen(input_buf);
                        need_full_render = 1;
                        continue;
                    }
                }
#endif
                if (strchr(input_buf, '*') || strchr(input_buf, '?')) {
#ifdef __CPM__
                    strncpy(s_browser_filter, input_buf,
                            sizeof(s_browser_filter) - 1);
                    s_browser_filter[sizeof(s_browser_filter) - 1] = '\0';
#endif
                    ui_browser_refresh_directory(input_buf);
                    cur_page = 0;
                    selected_idx = 0;
                    input_buf[0] = '\0';
                    cursor_pos = 0;
                    need_full_render = 1;
                    continue;
                }
#ifdef __linux__
                if (input_buf[strlen(input_buf) - 1] == '/') {
                    hal_linux_scan_directory(input_buf);
                    cur_page = 0;
                    selected_idx = 0;
                    input_buf[0] = '\0';
                    cursor_pos = 0;
                    need_full_render = 1;
                    continue;
                }
#endif
                if (mode == BROWSER_MODE_OPEN ||
                    mode == BROWSER_MODE_INSERT) {
#ifdef __CPM__
                    memset(&g_cpm_fcb, 0, sizeof(cpm_fcb_t));
                    format_mask_to_fcb(input_buf, s_dir_fcb);
                    if (input_buf[1] == ':') {
                        char d = input_buf[0];
                        if (d >= 'a' && d <= 'p') {
                            s_dir_fcb[0] = (uint8_t)(d - 'a' + 1);
                        } else if (d >= 'A' && d <= 'P') {
                            s_dir_fcb[0] = (uint8_t)(d - 'A' + 1);
                        }
                    } else {
                        s_dir_fcb[0] = (uint8_t)(s_browser_drive - 'A' + 1);
                    }
                    if ((uint8_t)bdos(15, (int)s_dir_fcb) == 0xFF) {
                        modal_alert_file_not_found(input_buf);
                        need_full_render = 1;
                        continue;
                    }
                    bdos(16, (int)s_dir_fcb);
#else
                    char check_path[64];
                    if (input_buf[1] == ':') {
                        snprintf(check_path, sizeof(check_path), "%s",
                                 input_buf);
                    } else {
                        snprintf(check_path, sizeof(check_path), "%s",
                                 input_buf);
                    }
                    {
                        FILE *fp_check = fopen(check_path, "rb");
                        if (!fp_check) {
                            modal_alert_file_not_found(input_buf);
                            need_full_render = 1;
                            continue;
                        }
                        fclose(fp_check);
                    }
#endif
                }
                if (mode == BROWSER_MODE_SAVE ||
                    mode == BROWSER_MODE_SAVE_BLOCK) {
#ifdef __CPM__
                    memset(&g_cpm_fcb, 0, sizeof(cpm_fcb_t));
                    format_mask_to_fcb(input_buf, s_dir_fcb);
                    if (input_buf[1] == ':') {
                        char d = input_buf[0];
                        if (d >= 'a' && d <= 'p') {
                            s_dir_fcb[0] = (uint8_t)(d - 'a' + 1);
                        } else if (d >= 'A' && d <= 'P') {
                            s_dir_fcb[0] = (uint8_t)(d - 'A' + 1);
                        }
                    } else {
                        s_dir_fcb[0] = (uint8_t)(s_browser_drive - 'A' + 1);
                    }
                    int res = bdos(15, (int)s_dir_fcb);
                    if (res >= 0 && res <= 3) {
                        bdos(16, (int)s_dir_fcb);
                        if (modal_confirm_overwrite() != MODAL_RES_OK) {
                            need_full_render = 1;
                            continue;
                        }
                    }
#else
                    char check_path[64];
                    if (input_buf[1] == ':') {
                        snprintf(check_path, sizeof(check_path), "%s",
                                 input_buf);
                    } else {
                        snprintf(check_path, sizeof(check_path), "%s",
                                 input_buf);
                    }
                    {
                        FILE *fp_check = fopen(check_path, "rb");
                        if (fp_check) {
                            fclose(fp_check);
                            if (modal_confirm_overwrite() != MODAL_RES_OK) {
                                need_full_render = 1;
                                continue;
                            }
                        }
                    }
#endif
                }
                strncpy(selected_filename, input_buf, max_len - 1);
                selected_filename[max_len - 1] = '\0';
                return MODAL_RES_OK;
            } else if (selected_idx >= 0 && selected_idx < s_browser_count) {
                if (mode == BROWSER_MODE_SAVE ||
                    mode == BROWSER_MODE_SAVE_BLOCK) {
                    if (modal_confirm_overwrite() != MODAL_RES_OK) {
                        need_full_render = 1;
                        continue;
                    }
                }
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
                need_full_render = 1;
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
                need_full_render = 1;
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
                need_full_render = 1;
            }
        } else if (k == KEY_UP) {
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
                need_full_render = 1;
            }
        } else if (k == KEY_DOWN) {
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
                need_full_render = 1;
            }
        } else if (k == KEY_BACKSPACE || k == '\b' || k == 127 || k == 8) {
            if (cursor_pos > 0) {
                memmove(&input_buf[cursor_pos - 1], &input_buf[cursor_pos],
                        strlen(&input_buf[cursor_pos]) + 1);
                cursor_pos--;
                render_browser_prompt(prompt_row, prompt_lbl, input_buf,
                                      cursor_pos);
            }
        } else if (k == KEY_DEL) {
            if (cursor_pos < strlen(input_buf)) {
                memmove(&input_buf[cursor_pos], &input_buf[cursor_pos + 1],
                        strlen(&input_buf[cursor_pos + 1]) + 1);
                render_browser_prompt(prompt_row, prompt_lbl, input_buf,
                                      cursor_pos);
            }
        } else if (k == KEY_LEFT) {
            if (cursor_pos > 0) {
                cursor_pos--;
                prompt_col = (uint8_t)(1 + strlen(prompt_lbl) + cursor_pos);
                hal_console_locate(prompt_row, prompt_col);
            }
        } else if (k == KEY_RIGHT) {
            if (cursor_pos < strlen(input_buf)) {
                cursor_pos++;
                prompt_col = (uint8_t)(1 + strlen(prompt_lbl) + cursor_pos);
                hal_console_locate(prompt_row, prompt_col);
            }
        } else if (k == KEY_HOME || k == KEY_CTRL_A) {
            cursor_pos = 0;
            prompt_col = (uint8_t)(1 + strlen(prompt_lbl) + cursor_pos);
            hal_console_locate(prompt_row, prompt_col);
        } else if (k == KEY_END || k == KEY_CTRL_E) {
            cursor_pos = strlen(input_buf);
            prompt_col = (uint8_t)(1 + strlen(prompt_lbl) + cursor_pos);
            hal_console_locate(prompt_row, prompt_col);
        } else if (k >= 32 && k <= 126) {
            size_t in_len = strlen(input_buf);
            if (in_len < 20 && in_len + 1 < sizeof(input_buf) - 1) {
                if (cursor_pos == in_len) {
                    input_buf[cursor_pos] = (char)k;
                    input_buf[cursor_pos + 1] = '\0';
                    cursor_pos++;
                    hal_console_putc((char)k);
                } else {
                    memmove(&input_buf[cursor_pos + 1], &input_buf[cursor_pos],
                            in_len - cursor_pos + 1);
                    input_buf[cursor_pos] = (char)k;
                    cursor_pos++;
                    render_browser_prompt(prompt_row, prompt_lbl, input_buf,
                                          cursor_pos);
                }
            }
        }
    }
}
#ifdef __CPM__
#undef input_buf
#undef title_buf
#endif

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
