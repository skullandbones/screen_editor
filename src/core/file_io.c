/*==============================================================================
 * FILE_IO.C: Core Subsystem - Document File Load, Save & Export Engine
 *
 * Purpose:
 *   Implements document loading from storage, file saving with configurable
 *   line endings (CRLF for CP/M, LF for Linux), and block file exporting.
 *   C semantic equivalent to high-level routines in src/core/ui_browser.asm.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "../include/config.h"
#include "../include/buffer.h"
#include "../include/memory.h"
#include "../include/editor.h"
#include "../include/block.h"
#include "../include/file_io.h"
#include "../include/ui.h"
#include "../include/ui_modal.h"
#include "../include/hal.h"

/* Global File Filename and Format State */
uint8_t g_is_loading_file = 0;
#ifdef __CPM__
char    g_current_filename[32];
uint8_t g_file_format = FMT_CPM;
#else
char    g_current_filename[256];
uint8_t g_file_format = FMT_LINUX;
#endif

#ifdef __CPM__
#include <cpm.h>
uint8_t   g_doc_drive = 0;
uint8_t   g_doc_user = 0;
uint8_t   g_target_user = 0;
#define s_cpm_sec_buf g_cpm_dma_buf
#define s_cpm_io_fcb  g_cpm_fcb
#endif

const char *cpm_parse_prefix(const char *path, uint8_t *out_drv,
                             uint8_t *out_usr)
{
    const char *p = path;
    const char *colon;
    const char *q;
    uint8_t drv = 0;
    uint8_t usr = 0xFF;

    if (out_drv) *out_drv = 0;
    if (out_usr) *out_usr = 0xFF;
    if (!p) return path;

    while (*p == ' ') p++;
    colon = strchr(p, ':');
    if (!colon || colon == p || (colon - p) > 3) return p;

    for (q = p; q < colon; q++) {
        char ch = *q;
        if (ch >= 'a' && ch <= 'z') ch = (char)(ch - 32);
        if (ch >= 'A' && ch <= 'P') {
            if (drv != 0) return p;
            drv = (uint8_t)(ch - 'A' + 1);
        } else if (ch >= '0' && ch <= '9') {
            uint8_t d = (uint8_t)(ch - '0');
            if (usr == 0xFF) {
                usr = d;
            } else if (q > p && *(q - 1) >= '0' && *(q - 1) <= '9') {
                usr = (uint8_t)(usr * 10 + d);
            } else {
                return p;
            }
        } else {
            return p;
        }
    }
    if ((usr != 0xFF && usr > 15) || (drv == 0 && usr == 0xFF)) return p;
    if (out_drv) *out_drv = drv;
    if (out_usr) *out_usr = usr;
    return colon + 1;
}

static void fill_fcb_field(char *dst, const char *src, uint8_t len)
{
    uint8_t i;
    for (i = 0; i < len && src[i] && src[i] != '.' &&
                src[i] != ':' && src[i] != ' '; i++) {
        char c = src[i];
        if (c == '*') {
            while (i < len) dst[i++] = '?';
            break;
        }
        if (c >= 'a' && c <= 'z') c = (char)(c - 32);
        dst[i] = c;
    }
}

void file_populate_fcb(const char *path, cpm_fcb_t *fcb)
{
    uint8_t drv = 0, usr = 0xFF;
    const char *p;
    const char *dot;
    const char *col;

    if (!fcb) return;
    memset(fcb, 0, sizeof(cpm_fcb_t));
    memset(fcb->name, ' ', 11);
    if (!path) return;

    p = cpm_parse_prefix(path, &drv, &usr);
    fcb->drive = drv;
#ifdef __CPM__
    g_target_user = (usr != 0xFF) ? usr : g_doc_user;
#endif
    fill_fcb_field(fcb->name, p, 8);
    dot = strchr(p, '.');
    col = strchr(p, ':');
    if (dot && (!col || dot < col)) {
        fill_fcb_field(fcb->ext, dot + 1, 3);
    }
}

int file_check_hibernated(const char *path)
{
    (void)path;
    return 0;
}

#ifdef __CPM__
static void cpm_format_doc_filename(const cpm_fcb_t *fcb, uint8_t user)
{
    char *dst = g_current_filename;
    const char *raw = fcb->name;
    uint8_t i;

    *dst++ = (char)('A' + (fcb->drive ? (fcb->drive - 1) : bdos(25, 0)));
    if (user >= 10) {
        *dst++ = '1';
        *dst++ = (char)('0' + (user - 10));
    } else if (user > 0) {
        *dst++ = (char)('0' + user);
    }
    *dst++ = ':';
    for (i = 0; i < 11; i++) {
        char c = (char)(raw[i] & 0x7F);
        if (i == 8) *dst++ = '.';
        if (c != ' ' && c != 0) *dst++ = c;
    }
    if (dst[-1] == '.') dst--;
    *dst = '\0';
}

static void cpm_commit_loaded_line(uint16_t row, uint16_t col)
{
    uint16_t slot_id = SLOT_TERM;
    g_scratch_line_buf[col] = '\0';
    if (col > 0) {
        mem_write_line(&slot_id, g_scratch_line_buf, col);
    }
    set_line_slot(row, slot_id);
}

static void draw_progress_tick(uint16_t lines)
{
    char lbuf[16];
    uint8_t top = (uint8_t)(((g_active_rows - 7) / 2) + 1);
    uint8_t left = (uint8_t)(((g_active_cols - 50) / 2) + 1);
    snprintf(lbuf, sizeof(lbuf), "Line %5u", (unsigned)lines);
    modal_draw_row_centered(top + 4, left, 50, lbuf);
}

static void draw_progress_modal(const char *title, uint8_t is_loading)
{
    char *fbuf = g_scratch_line_buf;
    uint8_t top = (uint8_t)(((g_active_rows - 7) / 2) + 1);
    uint8_t left = (uint8_t)(((g_active_cols - 50) / 2) + 1);
    uint8_t r;

    hal_console_hide_cursor();
    if (is_loading) {
        hal_console_clear();
        for (r = 1; r < g_active_rows; r++) {
            hal_console_puts("~\r\n");
        }
    }
    render_status_bar();
    modal_draw_frame(top, left, 50, 7, title);
    snprintf(fbuf, 36, "File: %s",
             g_current_filename[0] ? g_current_filename : "(Untitled)");
    modal_draw_row_centered(top + 3, left, 50, fbuf);
    draw_progress_tick(is_loading ? 1 : 0);
    modal_draw_row_centered(top + 5, left, 50, "Please wait...");
}

static int file_read_op(const char *filename, uint8_t is_insert)
{
    char *line_buf;
    char saved_fname[32];
    uint16_t row;
    uint16_t col = 0;
    uint16_t target_line = 0;
    uint16_t orig_row = 0, orig_col = 0;
    uint16_t suffix_slot = SLOT_TERM, suffix_len = 0;
    uint16_t prog_lines = 0;
    uint8_t prog_cnt = 100;
    uint8_t saved_mod = g_doc_modified;
    int i;
    int done = 0;
    int orig_user;
    const char *lcol;

    if (!filename || filename[0] == '\0') {
        return -1;
    }

    lcol = strchr(cpm_parse_prefix(filename, NULL, NULL), ':');
    if (lcol && lcol[1] >= '0' && lcol[1] <= '9') {
        target_line = (uint16_t)atoi(lcol + 1);
    }

    file_populate_fcb(filename, &s_cpm_io_fcb);
    if (s_cpm_io_fcb.drive == 0) {
        s_cpm_io_fcb.drive = g_doc_drive ? g_doc_drive
                                         : (uint8_t)(bdos(25, 0) + 1);
    }
    orig_user = bdos(32, 0xFF);
    bdos(32, g_target_user);

    if ((uint8_t)bdos(15, (int)&s_cpm_io_fcb) == 0xFF) {
        bdos(32, orig_user);
        modal_alert_file_not_found(filename);
        return -1;
    }

    if (!is_insert) {
        uint8_t saved_drv = s_cpm_io_fcb.drive;
        uint8_t saved_usr = g_target_user;
        buffer_init();
        s_cpm_io_fcb.drive = saved_drv;
        g_target_user = saved_usr;
        g_doc_drive = saved_drv;
        g_doc_user = saved_usr;
        cpm_format_doc_filename(&s_cpm_io_fcb, g_doc_user);
        g_file_format = FMT_LINUX;
        row = 0;
        line_buf = g_scratch_line_buf;
    } else {
        strcpy(saved_fname, g_current_filename);
        cpm_format_doc_filename(&s_cpm_io_fcb, g_target_user);
        if (g_block_mode != BLOCK_MODE_OFF) {
            normalize_block_bounds();
            if (g_norm_start_row != g_norm_end_row ||
                g_norm_start_col != g_norm_end_col) {
                do_delete_block();
            } else {
                cancel_block();
                g_cur_doc_row = g_norm_start_row;
                g_cur_col = g_norm_start_col;
            }
        }
        checkout_active_line(g_cur_doc_row);
        if (g_cur_col > g_active_line_len) {
            g_cur_col = g_active_line_len;
        }
        orig_row = g_cur_doc_row;
        orig_col = g_cur_col;
        suffix_len = g_active_line_len - orig_col;
        if (suffix_len > 0) {
            mem_write_line(&suffix_slot, g_active_line_buf + orig_col,
                           suffix_len);
        }
        g_active_line_len = orig_col;
        g_active_line_buf[orig_col] = '\0';
        row = orig_row;
        col = orig_col;
        line_buf = g_active_line_buf;
    }

    g_doc_modified = 0;
    g_is_loading_file = 1;
    draw_progress_modal(is_insert ? "Inserting File" : "Opening File", 1);

    bdos(26, (int)s_cpm_sec_buf);

    while (!done) {
        if ((uint8_t)bdos(20, (int)&s_cpm_io_fcb) != 0) {
            break;
        }
        for (i = 0; i < 128; i++) {
            uint8_t c = s_cpm_sec_buf[i];
            if (c == 0x1A || c == 0) {
                done = 1;
                break;
            }
            if (c == '\r') {
                if (!is_insert) g_file_format = FMT_CPM;
                continue;
            }
            if (c == '\n') {
                if (!is_insert) {
                    cpm_commit_loaded_line(row, col);
                    row++;
                    col = 0;
                } else {
                    g_active_line_len = col;
                    g_active_line_buf[col] = '\0';
                    commit_active_line();
                    insert_blank_line(row + 1);
                    row++;
                    checkout_active_line(row);
                    col = 0;
                }
                prog_lines++;
                if (--prog_cnt == 0) {
                    prog_cnt = 100;
                    draw_progress_tick(prog_lines);
                }
                continue;
            }
            if (col + 1 < MAX_INPUT_LINE_CHARS) {
                line_buf[col++] = (char)c;
            }
        }
    }

    if (!is_insert && (col > 0 || row == 0)) {
        cpm_commit_loaded_line(row, col);
        row++;
        prog_lines++;
    } else if (is_insert) {
        uint16_t end_row = row;
        uint16_t end_col = col;
        prog_lines++;
        if (suffix_slot != SLOT_TERM) {
            uint16_t slen = mem_read_line(suffix_slot, g_scratch_line_buf,
                                          MAX_INPUT_LINE_CHARS);
            mem_free_line_chain(suffix_slot);
            if (col + slen >= MAX_INPUT_LINE_CHARS) {
                slen = (MAX_INPUT_LINE_CHARS - 1) - col;
            }
            memcpy(g_active_line_buf + col, g_scratch_line_buf, slen);
            col += slen;
        }
        g_active_line_len = col;
        g_active_line_buf[col] = '\0';
        commit_active_line();
        g_cur_doc_row = end_row;
        g_cur_col = end_col;
        if (orig_row != end_row || orig_col != end_col) {
            g_block_anchor_row = g_norm_start_row = orig_row;
            g_block_anchor_col = g_norm_start_col = orig_col;
            g_block_active_row = g_norm_end_row = end_row;
            g_block_active_col = g_norm_end_col = end_col;
            g_block_mode = BLOCK_MODE_SOLIDIFIED;
        }
    }
    draw_progress_tick(prog_lines ? prog_lines : 1);
    g_is_loading_file = 0;

    bdos(16, (int)&s_cpm_io_fcb);
    bdos(26, DEFAULT_DMA);
    bdos(32, orig_user);

    if (!is_insert) {
        g_doc_total_lines = row ? row : 1;
        g_cur_doc_row = 0;
        g_cur_col = 0;
        g_top_doc_row = 0;
        g_doc_modified = 0;
        g_active_line_valid = 0;
    } else {
        strcpy(g_current_filename, saved_fname);
        g_doc_modified = 1;
        (void)saved_mod;
    }

    checkout_active_line(g_cur_doc_row);
    g_target_col = calc_visual_col(g_active_line_buf, g_cur_col);
    if (!is_insert && target_line > 0) {
        goto_line(target_line);
    }
    g_need_screen_render = 1;
    return 0;
}

static int cpm_write_byte(uint8_t b, uint8_t *sec_pos, uint16_t *rec_num)
{
    s_cpm_sec_buf[(*sec_pos)++] = b;
    if (*sec_pos == 128) {
        s_cpm_io_fcb.random_r0 = (uint8_t)(*rec_num & 0xFF);
        s_cpm_io_fcb.random_r1 = (uint8_t)((*rec_num >> 8) & 0xFF);
        s_cpm_io_fcb.random_r2 = 0;
        if ((uint8_t)bdos(34, (int)&s_cpm_io_fcb) != 0) {
            return -1;
        }
        (*rec_num)++;
        *sec_pos = 0;
    }
    return 0;
}

static int file_write_op(const char *filename, uint16_t start_row,
                         uint16_t end_row, uint8_t format, uint8_t is_block)
{
    uint16_t row;
    char *line_buf = g_scratch_line_buf;
    char saved_fname[32];
    uint16_t rec_num = 0;
    uint16_t prog_lines = 0;
    uint8_t prog_cnt = 100;
    uint8_t sec_pos = 0;
    uint8_t saved_mod = g_doc_modified;
    uint16_t i, len;
    int orig_user;

    if (!filename || filename[0] == '\0') {
        return -1;
    }

    commit_active_line();

    file_populate_fcb(filename, &s_cpm_io_fcb);
    if (s_cpm_io_fcb.drive == 0) {
        s_cpm_io_fcb.drive = g_doc_drive ? g_doc_drive
                                         : (uint8_t)(bdos(25, 0) + 1);
    }

    strcpy(saved_fname, g_current_filename);
    cpm_format_doc_filename(&s_cpm_io_fcb, g_target_user);
    g_doc_modified = 0;
    draw_progress_modal("Saving File", 0);

    orig_user = bdos(32, 0xFF);
    bdos(32, g_target_user);

    bdos(19, (int)&s_cpm_io_fcb);
    if ((uint8_t)bdos(22, (int)&s_cpm_io_fcb) == 0xFF) {
        bdos(32, orig_user);
        strcpy(g_current_filename, saved_fname);
        g_doc_modified = saved_mod;
        g_need_screen_render = 1;
        return -1;
    }

    bdos(26, (int)s_cpm_sec_buf);

    for (row = start_row; row <= end_row && row < g_doc_total_lines; row++) {
        uint16_t c_start = 0;
        uint16_t c_end;
        if (is_block && start_row != end_row && row == end_row &&
            g_norm_end_col == 0) {
            break;
        }
        len = fetch_line_to_buffer(row, line_buf, MAX_ACTIVE_PAYLOAD);
        c_end = len;
        if (is_block) {
            if (row == start_row && g_norm_start_col < c_end) {
                c_start = g_norm_start_col;
            } else if (row == start_row) {
                c_start = c_end;
            }
            if (row == end_row && g_norm_end_col < c_end) {
                c_end = g_norm_end_col;
            }
        }
        for (i = c_start; i < c_end; i++) {
            if (cpm_write_byte((uint8_t)line_buf[i], &sec_pos, &rec_num) != 0) {
                goto write_err;
            }
        }
        if (format == FMT_CPM) {
            if (cpm_write_byte('\r', &sec_pos, &rec_num) != 0) {
                goto write_err;
            }
        }
        if (cpm_write_byte('\n', &sec_pos, &rec_num) != 0) {
            goto write_err;
        }
        prog_lines++;
        if (--prog_cnt == 0) {
            prog_cnt = 100;
            draw_progress_tick(prog_lines);
        }
    }
    draw_progress_tick(prog_lines);

    while (sec_pos != 0) {
        if (cpm_write_byte(0x1A, &sec_pos, &rec_num) != 0) {
            goto write_err;
        }
    }

    bdos(16, (int)&s_cpm_io_fcb);
    bdos(26, DEFAULT_DMA);
    bdos(32, orig_user);

    if (is_block) {
        strcpy(g_current_filename, saved_fname);
        g_doc_modified = saved_mod;
    }
    checkout_active_line(g_cur_doc_row);
    g_need_screen_render = 1;
    g_need_status_render = 1;
    return 0;

write_err:
    strcpy(g_current_filename, saved_fname);
    g_doc_modified = saved_mod;
    bdos(16, (int)&s_cpm_io_fcb);
    bdos(26, DEFAULT_DMA);
    bdos(32, orig_user);
    return -1;
}
#else
#include <dirent.h>
#include <strings.h>

void resolve_linux_path(const char *raw, char *out_path, size_t max_len,
                        uint16_t *out_line)
{
    const char *p;
    const char *lcol;
    size_t n;
    DIR *d;
    struct dirent *de;

    if (out_line) {
        *out_line = 0;
    }
    if (!raw || !out_path || max_len == 0) {
        if (out_path && max_len > 0) out_path[0] = '\0';
        return;
    }

    p = cpm_parse_prefix(raw, NULL, NULL);
    lcol = strchr(p, ':');
    if (lcol && lcol[1] >= '0' && lcol[1] <= '9') {
        if (out_line) {
            *out_line = (uint16_t)atoi(lcol + 1);
        }
        n = (size_t)(lcol - p);
    } else {
        n = strlen(p);
    }
    if (n >= max_len) {
        n = max_len - 1;
    }
    memcpy(out_path, p, n);
    out_path[n] = '\0';

    if (strchr(out_path, '/') == NULL) {
        FILE *tf = fopen(out_path, "rb");
        if (tf) {
            fclose(tf);
            return;
        }
        d = opendir(".");
        if (d) {
            while ((de = readdir(d)) != NULL) {
                if (strcasecmp(de->d_name, out_path) == 0) {
                    strncpy(out_path, de->d_name, max_len - 1);
                    out_path[max_len - 1] = '\0';
                    break;
                }
            }
            closedir(d);
        }
    }
}

static int file_read_op(const char *filename, uint8_t is_insert)
{
    FILE *fp;
    char *line_buf = g_scratch_line_buf;
    char clean_name[256];
    uint16_t target_line = 0;
    uint16_t row;
    int c;
    uint16_t col = 0;

    if (!filename || filename[0] == '\0') {
        return -1;
    }

    resolve_linux_path(filename, clean_name, sizeof(clean_name), &target_line);

    fp = fopen(clean_name, "rb");
    if (!fp) {
        modal_alert_file_not_found(clean_name);
        return -1;
    }

    if (!is_insert) {
        buffer_init();
        g_file_format = FMT_LINUX;
        row = 0;
    } else {
        commit_active_line();
        row = g_cur_doc_row;
    }

    while ((c = fgetc(fp)) != EOF) {
        if (c == 0x1A || c == 0) {
            break;
        }
        if (c == '\r') {
            if (!is_insert) g_file_format = FMT_CPM;
            continue;
        }
        if (c == '\n') {
            line_buf[col] = '\0';
            if (!is_insert && row == 0) {
                checkout_active_line(0);
            } else {
                insert_blank_line(row);
                checkout_active_line(row);
            }
            memcpy(g_active_line_buf, line_buf, col + 1);
            g_active_line_len = col;
            commit_active_line();
            row++;
            col = 0;
            continue;
        }
        if (col < MAX_INPUT_LINE_CHARS) {
            line_buf[col++] = (char)c;
        }
    }

    if (col > 0 || (!is_insert && row == 0)) {
        line_buf[col] = '\0';
        if (!is_insert && row == 0) {
            checkout_active_line(0);
        } else {
            insert_blank_line(row);
            checkout_active_line(row);
        }
        memcpy(g_active_line_buf, line_buf, col + 1);
        g_active_line_len = col;
        commit_active_line();
        row++;
    }

    fclose(fp);

    if (!is_insert) {
        strncpy(g_current_filename, clean_name,
                sizeof(g_current_filename) - 1);
        g_current_filename[sizeof(g_current_filename) - 1] = '\0';
        g_doc_total_lines = row ? row : 1;
        g_cur_doc_row = 0;
        g_cur_col = 0;
        g_top_doc_row = 0;
        g_doc_modified = 0;
    } else {
        g_doc_modified = 1;
    }

    checkout_active_line(g_cur_doc_row);
    if (!is_insert && target_line > 0) {
        goto_line(target_line);
    }
    g_need_screen_render = 1;
    return 0;
}

static int file_write_op(const char *filename, uint16_t start_row,
                         uint16_t end_row, uint8_t format, uint8_t is_block)
{
    FILE *fp;
    uint16_t row;
    char *line_buf = g_scratch_line_buf;
    char clean_name[256];
    (void)is_block;

    if (!filename || filename[0] == '\0') {
        return -1;
    }

    resolve_linux_path(filename, clean_name, sizeof(clean_name), NULL);

    commit_active_line();

    fp = fopen(clean_name, "wb");
    if (!fp) {
        return -1;
    }

    for (row = start_row; row <= end_row && row < g_doc_total_lines; row++) {
        uint16_t len = fetch_line_to_buffer(row, line_buf, MAX_ACTIVE_PAYLOAD);
        if (len > 0) {
            fwrite(line_buf, 1, len, fp);
        }
        if (format == FMT_CPM) {
            fputc('\r', fp);
            fputc('\n', fp);
        } else {
            fputc('\n', fp);
        }
    }

    fclose(fp);
    checkout_active_line(g_cur_doc_row);
    g_need_screen_render = 1;
    return 0;
}
#endif

int file_load(const char *filename)
{
    return file_read_op(filename, 0);
}

int file_insert(const char *filename)
{
    return file_read_op(filename, 1);
}

int file_save(const char *filename, uint8_t format)
{
    const char *target = filename ? filename : g_current_filename;
    uint16_t last_row = g_doc_total_lines ? (g_doc_total_lines - 1) : 0;
    int res = file_write_op(target, 0, last_row, format, 0);
    if (res == 0) {
#ifdef __CPM__
        g_doc_drive = s_cpm_io_fcb.drive;
        g_doc_user = g_target_user;
        cpm_format_doc_filename(&s_cpm_io_fcb, g_doc_user);
#else
        if (filename && filename != g_current_filename) {
            resolve_linux_path(filename, g_current_filename,
                               sizeof(g_current_filename), NULL);
        }
#endif
        g_doc_modified = 0;
#ifndef __CPM__
        modal_show_notification("Save Complete", g_current_filename);
#endif
    }
    return res;
}

int file_save_block(const char *filename, uint16_t start_row,
                    uint16_t end_row, uint8_t format)
{
    int res = file_write_op(filename, start_row, end_row, format, 1);
#ifndef __CPM__
    if (res == 0) {
        modal_show_notification("Save Complete", filename);
    }
#endif
    return res;
}
