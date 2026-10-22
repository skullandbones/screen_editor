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
#include "../include/plugin.h"
#include "../include/hal.h"

#ifndef __CPM__
static browser_entry_t s_browser_files[MAX_BROWSER_FILES];
#endif
static int             s_browser_count = 0;

void ui_browser_clear_entries(void)
{
    s_browser_count = 0;
}

#ifndef __CPM__
int ui_browser_add_entry(const char *name, uint32_t size, uint8_t is_dir)
{
    if (s_browser_count >= MAX_BROWSER_FILES) {
        return -1;
    }
    strncpy(s_browser_files[s_browser_count].filename, name,
            BROWSER_FILENAME_LEN - 1);
    s_browser_files[s_browser_count].filename[
        BROWSER_FILENAME_LEN - 1] = '\0';
    s_browser_files[s_browser_count].size_bytes = size;
    s_browser_files[s_browser_count].drive = 0;
    s_browser_files[s_browser_count].user = 0;
    s_browser_files[s_browser_count].is_dir = is_dir;
    s_browser_count++;
    return 0;
}
#endif

#ifndef __CPM__
static int compare_entries(const void *a, const void *b)
{
    const browser_entry_t *ea = (const browser_entry_t *)a;
    const browser_entry_t *eb = (const browser_entry_t *)b;
    if (ea->is_dir != eb->is_dir) {
        return eb->is_dir - ea->is_dir;
    }
    return strcasecmp(ea->filename, eb->filename);
}
#endif

#ifdef __CPM__
extern char g_ramdrive_char;
#define s_dir_dma g_cpm_dma_buf
#define s_dir_fcb ((uint8_t *)&g_cpm_fcb)
static char    s_browser_drive = 'C';
static uint8_t s_browser_user = 0;
static char    s_browser_filter[14];
static uint8_t s_browser_is_fat = 0;
static uint8_t s_browser_fat_unit = 0xFF;
static char    s_browser_fat_path[32] = "/";

static const char *set_browser_filter(const char *src)
{
    uint8_t fi = 0;
    while (src[fi] && src[fi] != ' ' && fi + 1 < sizeof(s_browser_filter)) {
        char ch = src[fi];
        if (ch >= 'a' && ch <= 'z') ch = (char)(ch - 32);
        s_browser_filter[fi++] = ch;
    }
    s_browser_filter[fi] = '\0';
    if (strcmp(s_browser_filter, "*.*") == 0) {
        s_browser_filter[0] = '\0';
        return NULL;
    }
    return s_browser_filter;
}

static void format_drv_usr_str(char *dst, char drv, uint8_t usr,
                               const char *str)
{
    *dst++ = drv;
    if (usr >= 10) {
        *dst++ = '1';
        *dst++ = (char)('0' + (usr - 10));
    } else if (usr > 0) {
        *dst++ = (char)('0' + usr);
    }
    *dst++ = ':';
    strcpy(dst, str);
}

static void browser_insert_entry_sorted(const char *name)
{
    char cur[16];
    int lo = 0, hi = s_browser_count - 1;
    while (lo <= hi) {
        int mid = (lo + hi) >> 1;
        int cmp;
        hal_dir_entry_get((uint8_t)mid, cur);
        cmp = strcmp(name, cur);
        if (cmp == 0) {
            return;
        }
        if (cmp < 0) {
            hi = mid - 1;
        } else {
            lo = mid + 1;
        }
    }
    if (lo < MAX_BROWSER_FILES) {
        if (s_browser_count < MAX_BROWSER_FILES) {
            s_browser_count++;
        }
        if (s_browser_count - 1 > lo) {
            hal_dir_entry_shift((uint8_t)lo,
                                (uint8_t)(s_browser_count - 1 - lo));
        }
        hal_dir_entry_set((uint8_t)lo, name);
    }
}

static void scan_cpm_directory(char drive, uint8_t user, const char *mask)
{
    int orig_user;
    int res;

    file_populate_fcb((mask && *mask) ? mask : "*.*",
                      (cpm_fcb_t *)s_dir_fcb);
    s_dir_fcb[0] = (uint8_t)(drive - 'A' + 1);

    bdos(26, (int)s_dir_dma);
    orig_user = bdos(32, 0xFF);
    bdos(32, user);

    res = bdos(17, (int)s_dir_fcb);
    while (res != 0xFF && res >= 0 && res <= 3) {
        uint8_t *entry = &s_dir_dma[res * 32];
        if (entry[0] == user) {
            char name[16];
            uint8_t ni = 0;
            uint8_t j;
            for (j = 1; j <= 11; j++) {
                char c = (char)(entry[j] & 0x7F);
                if (j == 9) name[ni++] = '.';
                if (c != ' ' && c != 0) name[ni++] = c;
            }
            if (ni > 0 && name[ni - 1] == '.') ni--;
            name[ni] = '\0';

            if (ni > 0 && !(name[0] == '$' && name[1] == '$' &&
                            name[2] == '$')) {
                browser_insert_entry_sorted(name);
            }
        }
        res = bdos(18, (int)s_dir_fcb);
    }
    bdos(26, DEFAULT_DMA);
    bdos(32, orig_user);
}

static void scan_fat_directory(uint8_t unit, const char *path,
                               const char *mask)
{
    char filt_fcb[11];
    char *raw = g_active_line_buf;
    int fetched;
    uint16_t idx;
    uint8_t has_filter = 0;

    if (plugin_ensure_vfs() < 0) {
        return;
    }

    if (mask && mask[0] != '\0') {
        file_populate_fcb(mask, (cpm_fcb_t *)s_dir_fcb);
        memcpy(filt_fcb, ((cpm_fcb_t *)s_dir_fcb)->name, 11);
        has_filter = 1;
    }

    if (g_active_line_valid) {
        commit_active_line();
        g_active_line_valid = 0;
    }

    fetched = plugin_vfs_exec_cmd(VFS_CMD_LIST_DIR, unit,
                                  (path && path[0]) ? path : "/",
                                  g_active_line_buf,
                                  (uint16_t)(sizeof(g_active_line_buf) / 13),
                                  0, 0);
    if (fetched < 0) {
        return;
    }

    for (idx = 0; idx < (uint16_t)fetched; idx++, raw += 13) {
        uint8_t is_dir = (uint8_t)(raw[8] == '/');
        char disp_name[16];
        uint8_t ni = 0, j;

        if (is_dir) {
            if (raw[0] == '.' && raw[1] == '.') {
                browser_insert_entry_sorted("../");
                continue;
            }
        } else if (has_filter) {
            uint8_t match = 1;
            for (j = 0; j < 11; j++) {
                char fc = filt_fcb[j];
                char rc = (j < 8) ? raw[j] : raw[j + 1];
                if (fc != '?' && fc != rc) {
                    match = 0;
                    break;
                }
            }
            if (!match) {
                continue;
            }
        }

        for (j = 0; j < 8 && raw[j] != ' '; j++) {
            disp_name[ni++] = raw[j];
        }
        if (is_dir) {
            disp_name[ni++] = '/';
        } else if (raw[9] != ' ') {
            disp_name[ni++] = '.';
            for (j = 9; j < 12 && raw[j] != ' '; j++) {
                disp_name[ni++] = raw[j];
            }
        }
        disp_name[ni] = '\0';
        if (ni > 0) {
            browser_insert_entry_sorted(disp_name);
        }
    }
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
    if (s_browser_is_fat) {
        scan_fat_directory(s_browser_fat_unit, s_browser_fat_path, mask);
    } else {
        scan_cpm_directory(s_browser_drive, s_browser_user, mask);
    }
#endif
#ifndef __CPM__
    qsort(s_browser_files, s_browser_count, sizeof(browser_entry_t),
          compare_entries);
#endif
}

#ifndef __CPM__
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
#endif

#ifdef __CPM__
static const char *get_entry_name(int idx)
{
    char *s_fn = g_scratch_line_buf + 112;
    hal_dir_entry_get((uint8_t)idx, s_fn);
    return s_fn;
}
#else
#define get_entry_name(idx) (s_browser_files[(idx)].filename)
#endif

/* Shared browser layout and interaction state */
static uint8_t s_left_pad;
static uint8_t s_num_cols;
static uint8_t s_col_width;
static uint8_t s_rule_width;
static uint8_t s_top_pad;
static uint8_t s_prompt_row;
static uint8_t s_box_col;
static uint8_t s_hl_active;
static uint8_t s_hl_index;
static uint8_t s_hl_auto_mode;
static uint8_t s_cursor_pos;
static uint8_t s_is_save;
static int     s_page_start;
static int     s_page_files;
static int     s_cur_page;
static int     s_total_pages;
static int     s_files_per_page;

#ifdef __CPM__
static char s_in_buf[32];
#define s_title_buf (g_scratch_line_buf)
#define s_page_buf  (g_scratch_line_buf + 64)
#define IN_BUF_CAP  32
#else
static char s_in_buf[256];
static char s_title_buf[80];
static char s_page_buf[64];
#define IN_BUF_CAP  256
#endif

static void draw_tilde_row(uint8_t row)
{
    hal_console_locate(row, 1);
    hal_console_putc('~');
}

static void draw_tilde_eol(uint8_t row)
{
    draw_tilde_row(row);
    hal_console_clear_eol();
}

static void emit_left_pad(uint8_t row)
{
    uint8_t i;
    draw_tilde_row(row);
    for (i = 0; i < s_left_pad; i++) {
        hal_console_putc(' ');
    }
}

static void draw_rule_row(uint8_t row, char ch)
{
    uint8_t c;
    draw_tilde_row(row);
    for (c = 0; c < s_rule_width; c++) {
        hal_console_putc(ch);
    }
    hal_console_clear_eol();
}

static void puts_padded(const char *s, uint8_t width)
{
    uint8_t n = 0;
    while (*s && n < width) {
        hal_console_putc(*s++);
        n++;
    }
    while (n < width) {
        hal_console_putc(' ');
        n++;
    }
}

static void locate_input_cursor(void)
{
    uint8_t vis_pos = (s_cursor_pos > 20) ? 20 : s_cursor_pos;
    hal_console_locate(s_prompt_row, (uint8_t)(s_box_col + vis_pos));
    hal_console_show_cursor();
}

static void refresh_browser_box(void)
{
    hal_console_locate(s_prompt_row, s_box_col);
    puts_padded(s_in_buf, 20);
    if (!s_hl_active) {
        locate_input_cursor();
    }
}

static void draw_tab_mode_hint(void)
{
    hal_console_locate(s_prompt_row, (uint8_t)(s_box_col + 20));
    hal_console_puts(s_hl_active
                     ? "]  [TAB]=Edit Name  [Enter]=OK"
                     : "]  [TAB]=Select File          ");
    hal_console_clear_eol();
}

static void draw_save_fmt_row(uint8_t row)
{
    emit_left_pad(row);
    hal_console_puts("Format: [");
    hal_console_puts((g_file_format == FMT_CPM) ? "CP/M" : "Linux");
    hal_console_puts("]   [^F]=Toggle Format");
    hal_console_clear_eol();
}

static void render_browser_prompt(const char *prompt_txt)
{
    emit_left_pad(s_prompt_row);
    hal_console_inverse_on();
    hal_console_puts(prompt_txt);
    hal_console_inverse_off();
    hal_console_puts(" [");
    puts_padded(s_in_buf, 20);
    draw_tab_mode_hint();
    if (!s_hl_active) {
        locate_input_cursor();
    }
}

static void draw_hl_cell(uint8_t inverse)
{
    uint8_t r = s_hl_index / s_num_cols;
    uint8_t col = s_hl_index % s_num_cols;
    uint8_t srow = (uint8_t)(s_top_pad + 4 + r);
    uint8_t scol = (uint8_t)(s_left_pad + 2 + col * s_col_width);

    hal_console_locate(srow, scol);
    if (inverse) {
        hal_console_inverse_on();
    }
    puts_padded(get_entry_name(s_page_start + s_hl_index), 12);
    if (inverse) {
        hal_console_inverse_off();
    }
}

static void apply_hl_to_box(void)
{
    const char *fn = get_entry_name(s_page_start + s_hl_index);
#ifdef __CPM__
    if (s_browser_is_fat) {
        strncpy(s_in_buf, fn, IN_BUF_CAP - 1);
        s_in_buf[IN_BUF_CAP - 1] = '\0';
    } else {
        format_drv_usr_str(s_in_buf, s_browser_drive, s_browser_user, fn);
    }
#else
    strncpy(s_in_buf, fn, IN_BUF_CAP - 1);
    s_in_buf[IN_BUF_CAP - 1] = '\0';
#endif
    s_cursor_pos = (uint8_t)strlen(s_in_buf);
    hal_console_locate(s_prompt_row, s_box_col);
    puts_padded(s_in_buf, 20);
}

static void activate_hl_at(uint8_t idx)
{
    s_hl_active = 1;
    s_hl_index = idx;
    hal_console_hide_cursor();
    draw_hl_cell(1);
    apply_hl_to_box();
    draw_tab_mode_hint();
}

#ifdef __CPM__
static void format_fat_selection(char *dst, const char *src)
{
    char *p = dst;
    *p++ = 'U';
    if (s_browser_fat_unit != 0xFF) {
        *p++ = (char)('0' + s_browser_fat_unit);
    }
    *p++ = ':';
    if (src[0] != '/') {
        strcpy(p, s_browser_fat_path);
        p += strlen(p);
        if (*(p - 1) != '/') *p++ = '/';
    }
    strcpy(p, src);
}

static void reset_browser_input_prefix(void)
{
#ifdef __CPM__
    if (s_browser_is_fat) {
        s_in_buf[0] = 'U';
        s_in_buf[1] = (char)('0' + s_browser_fat_unit);
        s_in_buf[2] = ':';
        s_in_buf[3] = '\0';
    } else {
        format_drv_usr_str(s_in_buf, s_browser_drive, s_browser_user, "");
    }
    s_cursor_pos = (uint8_t)strlen(s_in_buf);
#else
    s_in_buf[0] = '\0';
    s_cursor_pos = 0;
#endif
}

static int handle_fat_nav(const char *fat_p)
{
    const char *filt = NULL;
    size_t len;
    if (!fat_p || *fat_p == '\0' || (fat_p[0] == '/' && fat_p[1] == '\0')) {
        strcpy(s_browser_fat_path, "/");
    } else if (fat_p[0] == '.' && fat_p[1] == '.' &&
               (fat_p[2] == '\0' || (fat_p[2] == '/' && fat_p[3] == '\0'))) {
        char *ls = strrchr(s_browser_fat_path, '/');
        if (ls && ls != s_browser_fat_path) {
            *ls = '\0';
        } else {
            strcpy(s_browser_fat_path, "/");
        }
    } else if (strchr(fat_p, '*') || strchr(fat_p, '?')) {
        filt = set_browser_filter(fat_p);
    } else if ((len = strlen(fat_p)) > 0 && fat_p[len - 1] == '/') {
        if (fat_p[0] == '/') {
            strncpy(s_browser_fat_path, fat_p, 31);
        } else {
            size_t plen = strlen(s_browser_fat_path);
            if (plen == 0 || s_browser_fat_path[plen - 1] != '/') {
                strcat(s_browser_fat_path, "/");
            }
            strncat(s_browser_fat_path, fat_p,
                    31 - strlen(s_browser_fat_path));
        }
        s_browser_fat_path[31] = '\0';
        len = strlen(s_browser_fat_path);
        if (len > 1 && s_browser_fat_path[len - 1] == '/') {
            s_browser_fat_path[len - 1] = '\0';
        }
    } else {
        return 0;
    }

    if (!filt) {
        s_browser_filter[0] = '\0';
    }
    ui_browser_refresh_directory(filt);
    return 1;
}
#endif

static void format_browser_title(char *buf, const char *op_str)
{
#ifdef __CPM__
    char *p = buf;
    while (*op_str) *p++ = *op_str++;
    strcpy(p, " (DIRECTORY - DRIVE ");
    p += 20;
    if (s_browser_is_fat) {
        *p++ = 'U';
        if (s_browser_fat_unit != 0xFF) {
            *p++ = (char)('0' + s_browser_fat_unit);
        }
        *p++ = ':';
        strcpy(p, s_browser_fat_path);
        p += strlen(p);
        if (*(p - 1) != '/') {
            *p++ = '/';
        }
    } else {
        *p++ = s_browser_drive;
        if (s_browser_user >= 10) {
            *p++ = '1';
            *p++ = (char)('0' + (s_browser_user - 10));
        } else if (s_browser_user > 0) {
            *p++ = (char)('0' + s_browser_user);
        }
        *p++ = ':';
    }
    if (s_browser_filter[0]) {
        *p++ = ' ';
        *p++ = '[';
        strcpy(p, s_browser_filter);
        p += strlen(p);
        *p++ = ']';
    }
    *p++ = ')';
    *p = '\0';
#else
    snprintf(buf, 80, "%s (DIRECTORY)", op_str);
#endif
}

static void render_browser_screen(const char *op_str, const char *prompt_txt)
{
    uint8_t grid_rows, file_rows, prompt_rows, body_rows;
    uint8_t r, col, screen_row, tlen, title_spaces;
    int avail;

    hal_console_hide_cursor();
    format_browser_title(s_title_buf, op_str);

    if (s_cur_page >= s_total_pages) s_cur_page = s_total_pages - 1;
    if (s_cur_page < 0) s_cur_page = 0;
    s_page_start = s_cur_page * s_files_per_page;
    s_page_files = s_browser_count - s_page_start;
    if (s_page_files < 0) s_page_files = 0;
    if (s_page_files > s_files_per_page) {
        s_page_files = s_files_per_page;
    }

    grid_rows = (s_page_files > 0)
        ? (uint8_t)((s_page_files + s_num_cols - 1) / s_num_cols) : 0;
    file_rows = (s_page_files == 0) ? 2 : (uint8_t)(grid_rows + 1);
    prompt_rows = (uint8_t)(3 + ((s_total_pages >= 2) ? 1 : 0) +
                            (s_is_save ? 1 : 0));
    body_rows = (uint8_t)(file_rows + prompt_rows);
    avail = (int)g_active_rows - 4 - (int)body_rows;
    s_top_pad = (avail > 0) ? (uint8_t)(avail / 2) : 0;

    for (r = 1; r <= s_top_pad; r++) {
        draw_tilde_eol(r);
    }

    screen_row = (uint8_t)(s_top_pad + 1);
    draw_rule_row(screen_row, '=');

    screen_row++;
    draw_tilde_row(screen_row);
    tlen = (uint8_t)strlen(s_title_buf);
    title_spaces = (g_active_cols > tlen + 2)
        ? (uint8_t)(((g_active_cols - tlen) / 2) - 1) : 1;
    for (r = 0; r < title_spaces; r++) hal_console_putc(' ');
    hal_console_puts(s_title_buf);
    hal_console_clear_eol();

    screen_row++;
    draw_rule_row(screen_row, '=');

    if (s_page_files == 0) {
        screen_row++;
        emit_left_pad(screen_row);
#ifdef __CPM__
        hal_console_puts("[No files found on current drive]");
#else
        hal_console_puts("[No files found in directory]");
#endif
        hal_console_clear_eol();
    } else {
        uint8_t idx = 0;
        for (r = 0; r < grid_rows; r++) {
            screen_row++;
            emit_left_pad(screen_row);
            for (col = 0; col < s_num_cols; col++) {
                if (idx < (uint8_t)s_page_files) {
                    puts_padded(get_entry_name(s_page_start + idx),
                                s_col_width);
                    idx++;
                }
            }
            hal_console_clear_eol();
        }
    }

    screen_row++;
    draw_tilde_eol(screen_row);

    screen_row++;
    draw_rule_row(screen_row, '-');

    if (s_total_pages >= 2) {
        screen_row++;
        emit_left_pad(screen_row);
#ifdef __CPM__
        {
            char *p = s_page_buf;
            strcpy(p, "[Page "); p += 6;
            p = se_append_u16(p, (uint16_t)(s_cur_page + 1));
            *p++ = '/';
            p = se_append_u16(p, (uint16_t)s_total_pages);
            strcpy(p, "]  <PgUp>/<PgDn>=Page");
        }
#else
        snprintf(s_page_buf, 40,
                 "[Page %d/%d]  <PgUp>/<PgDn>=Page",
                 (int)(uint8_t)(s_cur_page + 1),
                 (int)(uint8_t)s_total_pages);
#endif
        hal_console_puts(s_page_buf);
        hal_console_clear_eol();
    }

    if (s_is_save) {
        screen_row++;
        draw_save_fmt_row(screen_row);
    }

    screen_row++;
    emit_left_pad(screen_row);
#ifdef __CPM__
    hal_console_puts(
        "[ESC]=Cancel  Enter [d:][u:][pattern] to list "
        "(e.g. B:, C1:, 1C:, *.TXT)");
#else
    hal_console_puts(
        "[ESC]=Cancel  Enter [path/][pattern] to list "
        "(e.g. src/, *.c, *.txt)");
#endif
    hal_console_clear_eol();

    screen_row++;
    s_prompt_row = screen_row;
    render_browser_prompt(prompt_txt);

    for (r = (uint8_t)(s_prompt_row + 1); r < g_active_rows; r++) {
        draw_tilde_eol(r);
    }

    render_status_bar();

    if (s_hl_auto_mode != 0 && s_page_files > 0) {
        uint8_t target = (s_hl_auto_mode == 1)
            ? 0 : (uint8_t)(s_page_files - 1);
        s_hl_auto_mode = 0;
        activate_hl_at(target);
    } else if (s_hl_active && s_page_files > 0) {
        if (s_hl_index >= (uint8_t)s_page_files) {
            s_hl_index = (uint8_t)(s_page_files - 1);
        }
        hal_console_hide_cursor();
        draw_hl_cell(1);
    } else {
        s_hl_active = 0;
        s_hl_auto_mode = 0;
        locate_input_cursor();
    }
}

static int browser_handle_enter(int mode, char *selected_filename,
                                size_t max_len)
{
#ifdef __CPM__
    uint8_t u_unit = 0xFF;
    const char *fat_p = cpm_parse_fat_path(s_in_buf, &u_unit);
    if (fat_p != NULL) {
        if (plugin_find_vfs() < 0) {
            plugin_alert_fat_missing();
            return -1;
        }
        while (*fat_p == ' ') fat_p++;
        s_browser_is_fat = 1;
        if (u_unit != 0xFF) s_browser_fat_unit = u_unit;
    } else if (s_browser_is_fat) {
        uint8_t cpm_drv = 0, cpm_usr = 0xFF;
        const char *cpm_rest = cpm_parse_prefix(s_in_buf, &cpm_drv, &cpm_usr);
        if (cpm_rest > s_in_buf && cpm_drv != 0) {
            s_browser_is_fat = 0;
            s_browser_drive = (char)('A' + cpm_drv - 1);
            s_browser_user = (cpm_usr != 0xFF) ? cpm_usr : 0;
            s_browser_filter[0] = '\0';
            ui_browser_refresh_directory(NULL);
            return -2;
        }
        fat_p = s_in_buf;
    }

    if (s_browser_is_fat && fat_p != NULL) {
        if (handle_fat_nav(fat_p)) {
            return -2;
        }
        format_fat_selection(selected_filename, fat_p);
        return 1;
    }

    {
        uint8_t drv = 0, usr = 0xFF;
        const char *rest = cpm_parse_prefix(s_in_buf, &drv, &usr);
        int orig_u;
        uint8_t exists;

        while (*rest == ' ') rest++;
        if (rest > s_in_buf) {
            if (drv != 0) s_browser_drive = (char)('A' + drv - 1);
            if (usr != 0xFF) s_browser_user = usr;
        }

        if (g_ramdrive_char != 0 &&
            g_config.ramdrive_mode != RAMDRV_MODE_PROTECTED &&
            s_browser_drive == g_ramdrive_char) {
            modal_alert("RAM Drive Unavailable",
                        "Drive is used for editor memory.", NULL);
            return -1;
        }

        if (*rest == '\0') {
            if (rest > s_in_buf) {
                s_browser_filter[0] = '\0';
                ui_browser_refresh_directory(NULL);
                return -2;
            }
            return 0;
        }

        if (strchr(rest, '*') || strchr(rest, '?')) {
            ui_browser_refresh_directory(set_browser_filter(rest));
            return -2;
        }

        if (mode == BROWSER_MODE_LOAD_PLUGIN) {
            char plug_fn[24];
            int slot;
            format_drv_usr_str(plug_fn, s_browser_drive, s_browser_user, rest);
            slot = plugin_load_by_name(plug_fn);
            if (slot < 0) {
                modal_alert_file_not_found(rest);
                return -1;
            }
            return slot;
        }

        file_populate_fcb(rest, (cpm_fcb_t *)s_dir_fcb);
        s_dir_fcb[0] = (uint8_t)(s_browser_drive - 'A' + 1);
        orig_u = bdos(32, 0xFF);
        bdos(32, s_browser_user);
        exists = (uint8_t)bdos(15, (int)s_dir_fcb);
        if (exists != 0xFF) {
            bdos(16, (int)s_dir_fcb);
        }
        bdos(32, orig_u);

        if (mode == BROWSER_MODE_OPEN || mode == BROWSER_MODE_INSERT) {
            if (exists == 0xFF) {
                modal_alert_file_not_found(rest);
                return -1;
            }
        } else if (exists != 0xFF) {
            if (modal_confirm_overwrite() != MODAL_RES_OK) {
                return 0;
            }
        }

        format_drv_usr_str(selected_filename, s_browser_drive, s_browser_user,
                           rest);
        (void)max_len;
        return 1;
    }
#else
    if (strchr(s_in_buf, '*') || strchr(s_in_buf, '?')) {
        ui_browser_refresh_directory(s_in_buf);
        return -1;
    }
#ifdef __linux__
    if (s_in_buf[strlen(s_in_buf) - 1] == '/') {
        hal_linux_scan_directory(s_in_buf);
        s_in_buf[0] = '\0';
        return -1;
    }
#endif
    {
        char check_path[256];
        resolve_linux_path(s_in_buf, check_path, sizeof(check_path), NULL);
        if (mode == BROWSER_MODE_OPEN || mode == BROWSER_MODE_INSERT) {
            FILE *fp_check = fopen(check_path, "rb");
            if (!fp_check) {
                modal_alert_file_not_found(check_path);
                return -1;
            }
            fclose(fp_check);
        } else {
            FILE *fp_check = fopen(check_path, "rb");
            if (fp_check) {
                fclose(fp_check);
                if (modal_confirm_overwrite() != MODAL_RES_OK) {
                    return -1;
                }
            }
        }
    }
    strncpy(selected_filename, s_in_buf, max_len - 1);
    selected_filename[max_len - 1] = '\0';
    return 1;
#endif
}

static int ui_browser_workspace(int mode, char *selected_filename,
                                size_t max_len)
{
    uint8_t prev_splash = g_is_splash_screen;
    const char *op_str;
    const char *prompt_txt;
    uint8_t need_full_render = 1;
    int k;

    memset(s_in_buf, 0, IN_BUF_CAP);
    s_cursor_pos = 0;
    s_cur_page = 0;
    s_hl_active = 0;
    s_hl_index = 0;
    s_hl_auto_mode = 0;
    s_is_save = (uint8_t)(mode == BROWSER_MODE_SAVE ||
                          mode == BROWSER_MODE_SAVE_BLOCK);
    g_is_splash_screen = 1;

    {
        static const char *s_mode_ops[] = {
            "OPEN FILE", "INSERT FILE", "SAVE FILE",
            "SAVE BLOCK", "LOAD PLUGIN"
        };
        op_str = s_mode_ops[mode];
        prompt_txt = (mode == BROWSER_MODE_OPEN)
            ? "Enter filename to open:"
            : ((mode == BROWSER_MODE_INSERT)
               ? "Enter filename to insert:"
               : ((mode == BROWSER_MODE_LOAD_PLUGIN)
                  ? "Load Plugin (.PRL/.OVL):"
                  : "Enter filename to save:"));
    }

#ifdef __CPM__
    if (g_doc_is_fat) {
        char *last_slash;
        s_browser_is_fat = 1;
        s_browser_fat_unit = g_doc_fat_unit;
        strcpy(s_browser_fat_path, g_doc_fat_path);
        last_slash = strrchr(s_browser_fat_path, '/');
        if (last_slash && last_slash != s_browser_fat_path) {
            *(last_slash + 1) = '\0';
        } else {
            strcpy(s_browser_fat_path, "/");
        }
    } else {
        s_browser_is_fat = 0;
        s_browser_fat_unit = 0xFF;
        strcpy(s_browser_fat_path, "/");
    }
    s_browser_drive = g_doc_drive ? (char)('A' + g_doc_drive - 1)
                                  : (char)('A' + bdos(25, 0));
    s_browser_user = g_doc_drive ? g_doc_user : (uint8_t)bdos(32, 0xFF);
    s_browser_filter[0] = '\0';
    if (s_browser_is_fat) {
        if (mode == BROWSER_MODE_SAVE && g_doc_is_fat &&
            g_doc_fat_path[0] != '\0') {
            s_in_buf[0] = 'U';
            s_in_buf[1] = (char)('0' + g_doc_fat_unit);
            s_in_buf[2] = ':';
            strncpy(s_in_buf + 3, g_doc_fat_path, IN_BUF_CAP - 4);
            s_in_buf[IN_BUF_CAP - 1] = '\0';
        } else {
            reset_browser_input_prefix();
        }
    } else {
        const char *bare = "";
        if (mode == BROWSER_MODE_SAVE && g_current_filename[0] != '\0') {
            const char *col = strchr(g_current_filename, ':');
            bare = col ? (col + 1) : g_current_filename;
        }
        format_drv_usr_str(s_in_buf, s_browser_drive, s_browser_user, bare);
    }
    s_cursor_pos = (uint8_t)strlen(s_in_buf);
#else
    if (selected_filename && selected_filename[0] != '\0') {
        snprintf(s_in_buf, IN_BUF_CAP, "%s", selected_filename);
    } else if (mode == BROWSER_MODE_SAVE && g_current_filename[0] != '\0') {
        snprintf(s_in_buf, IN_BUF_CAP, "%s", g_current_filename);
    }
    s_cursor_pos = (uint8_t)strlen(s_in_buf);
#endif

    ui_browser_refresh_directory(NULL);

    s_num_cols = (g_active_cols >= 120) ? 7 : 5;
    s_col_width = (g_active_cols >= 120) ? 16 : 15;
    s_left_pad = (g_active_cols >= 120) ? 3 : 2;
    s_files_per_page = (int)s_num_cols * ((g_active_rows >= 40) ? 28 : 12);
    s_rule_width = (uint8_t)(g_active_cols - 2);
    s_box_col = (uint8_t)(s_left_pad + strlen(prompt_txt) + 4);

    while (1) {
        s_total_pages = (s_browser_count > 0)
            ? ((s_browser_count + s_files_per_page - 1) / s_files_per_page)
            : 1;

        if (need_full_render) {
            render_browser_screen(op_str, prompt_txt);
            need_full_render = 0;
        }

        while ((k = hal_console_getkey()) <= 0) {
#ifndef __CPM__
            usleep(5000);
#endif
        }

        if (k == KEY_ESC) {
            hal_console_show_cursor();
            g_need_screen_render = 1;
            g_is_splash_screen = prev_splash;
            return MODAL_RES_CANCEL;
        } else if (k == KEY_CTRL_F) {
            if (s_is_save) {
                g_file_format = (g_file_format == FMT_CPM)
                    ? FMT_LINUX : FMT_CPM;
                hal_console_hide_cursor();
                draw_save_fmt_row((uint8_t)(s_prompt_row - 2));
                render_status_bar();
                locate_input_cursor();
            }
        } else if (k == KEY_TAB || k == '\t') {
            if (!s_hl_active) {
                if (s_page_files > 0) {
                    activate_hl_at(0);
                }
            } else {
                draw_hl_cell(0);
                s_hl_active = 0;
                draw_tab_mode_hint();
                locate_input_cursor();
            }
        } else if (k == KEY_PGUP || k == KEY_CTRL_U) {
            if (s_total_pages >= 2) {
                if (s_hl_active) s_hl_auto_mode = 2;
                s_cur_page = (s_cur_page > 0) ? (s_cur_page - 1)
                                              : (s_total_pages - 1);
                need_full_render = 1;
            }
        } else if (k == KEY_PGDN || k == KEY_CTRL_V) {
            if (s_total_pages >= 2) {
                if (s_hl_active) s_hl_auto_mode = 1;
                s_cur_page = (s_cur_page + 1 < s_total_pages)
                    ? (s_cur_page + 1) : 0;
                need_full_render = 1;
            }
        } else if (k == KEY_ENTER || k == '\n' || k == '\r') {
            int res;
            hal_console_show_cursor();
            g_need_screen_render = 1;
            if (s_in_buf[0] == '\0') {
                g_is_splash_screen = prev_splash;
                return MODAL_RES_CANCEL;
            }
            res = browser_handle_enter(mode, selected_filename, max_len);
            if (res >= 0) {
                g_is_splash_screen = prev_splash;
                return (res == 1) ? MODAL_RES_OK :
                       ((res == 0) ? MODAL_RES_CANCEL : res);
            }
            if (res == -2) {
                reset_browser_input_prefix();
            }
            s_cur_page = 0;
            s_hl_active = 0;
            s_hl_index = 0;
            s_hl_auto_mode = 0;
            s_cursor_pos = (uint8_t)strlen(s_in_buf);
            need_full_render = 1;
            continue;
        } else if (s_hl_active) {
            uint8_t new_idx = s_hl_index;
            if (k == KEY_LEFT && s_hl_index > 0) {
                new_idx = (uint8_t)(s_hl_index - 1);
            } else if (k == KEY_RIGHT &&
                       (int)(s_hl_index + 1) < s_page_files) {
                new_idx = (uint8_t)(s_hl_index + 1);
            } else if (k == KEY_UP && s_hl_index >= s_num_cols) {
                new_idx = (uint8_t)(s_hl_index - s_num_cols);
            } else if (k == KEY_DOWN &&
                       (int)(s_hl_index + s_num_cols) < s_page_files) {
                new_idx = (uint8_t)(s_hl_index + s_num_cols);
            }
            if (new_idx != s_hl_index) {
                draw_hl_cell(0);
                s_hl_index = new_idx;
                draw_hl_cell(1);
                apply_hl_to_box();
            }
        } else if (k == KEY_BACKSPACE || k == '\b' || k == 8) {
            if (s_cursor_pos > 0) {
                s_cursor_pos--;
                strcpy(&s_in_buf[s_cursor_pos], &s_in_buf[s_cursor_pos + 1]);
                refresh_browser_box();
            }
        } else if (k == KEY_DEL || k == KEY_CTRL_D || k == KEY_CTRL_G) {
            if (s_in_buf[s_cursor_pos]) {
                strcpy(&s_in_buf[s_cursor_pos], &s_in_buf[s_cursor_pos + 1]);
                refresh_browser_box();
            }
        } else if (k == KEY_LEFT || k == KEY_CTRL_S) {
            if (s_cursor_pos > 0) {
                s_cursor_pos--;
                locate_input_cursor();
            }
        } else if (k == KEY_RIGHT) {
            if (s_in_buf[s_cursor_pos]) {
                s_cursor_pos++;
                locate_input_cursor();
            }
        } else if (k == KEY_HOME || k == KEY_CTRL_A) {
            s_cursor_pos = 0;
            locate_input_cursor();
        } else if (k == KEY_END || k == KEY_CTRL_E) {
            s_cursor_pos = (uint8_t)strlen(s_in_buf);
            locate_input_cursor();
        } else if (k >= 32 && k <= 126) {
            uint8_t in_len = (uint8_t)strlen(s_in_buf);
            if (in_len < 20) {
                if (s_cursor_pos == in_len) {
                    s_in_buf[s_cursor_pos++] = (char)k;
                    s_in_buf[s_cursor_pos] = '\0';
                    hal_console_putc((char)k);
                } else {
                    memmove(&s_in_buf[s_cursor_pos + 1],
                            &s_in_buf[s_cursor_pos],
                            (size_t)(in_len - s_cursor_pos + 1));
                    s_in_buf[s_cursor_pos++] = (char)k;
                    refresh_browser_box();
                }
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

int ui_browser_load_plugin_dialog(void)
{
    char fn[24];
    fn[0] = '\0';
    return ui_browser_workspace(BROWSER_MODE_LOAD_PLUGIN, fn, sizeof(fn));
}
