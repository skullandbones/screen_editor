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
#include "../include/editor.h"
#include "../include/block.h"
#include "../include/file_io.h"
#include "../include/ui.h"
#include "../include/ui_modal.h"

/* Global File Filename and Format State */
#ifdef __CPM__
char    g_current_filename[32];
uint8_t g_file_format = FMT_CPM;
#else
char    g_current_filename[256];
uint8_t g_file_format = FMT_LINUX;
#endif

#ifdef __CPM__
#include <cpm.h>
uint8_t   g_cpm_dma_buf[128];
cpm_fcb_t g_cpm_fcb;
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

static void cpm_commit_loaded_line(uint16_t row, uint16_t col,
                                   uint8_t is_insert)
{
    g_scratch_line_buf[col] = '\0';
    if (!is_insert && row == 0) {
        checkout_active_line(0);
    } else {
        insert_blank_line(row);
        checkout_active_line(row);
    }
    memcpy(g_active_line_buf, g_scratch_line_buf, col + 1);
    g_active_line_len = col;
    commit_active_line();
}

static int file_read_op(const char *filename, uint8_t is_insert)
{
    char *line_buf = g_scratch_line_buf;
    uint16_t row;
    uint16_t col = 0;
    uint16_t target_line = 0;
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
        g_file_format = FMT_LINUX;
        row = 0;
    } else {
        commit_active_line();
        row = g_cur_doc_row;
    }

    bdos(26, (int)s_cpm_sec_buf);

    while (!done) {
        if (bdos(20, (int)&s_cpm_io_fcb) != 0) {
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
                cpm_commit_loaded_line(row, col, is_insert);
                row++;
                col = 0;
                continue;
            }
            if (col + 1 < MAX_INPUT_LINE_CHARS) {
                line_buf[col++] = (char)c;
            }
        }
    }

    if (col > 0 || (!is_insert && row == 0)) {
        cpm_commit_loaded_line(row, col, is_insert);
        row++;
    }

    bdos(16, (int)&s_cpm_io_fcb);
    bdos(26, DEFAULT_DMA);
    bdos(32, orig_user);

    if (!is_insert) {
        g_doc_drive = s_cpm_io_fcb.drive;
        g_doc_user = g_target_user;
        cpm_format_doc_filename(&s_cpm_io_fcb, g_doc_user);
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

static int cpm_write_byte(uint8_t b, uint8_t *sec_pos, uint16_t *rec_num)
{
    s_cpm_sec_buf[(*sec_pos)++] = b;
    if (*sec_pos == 128) {
        s_cpm_io_fcb.random_r0 = (uint8_t)(*rec_num & 0xFF);
        s_cpm_io_fcb.random_r1 = (uint8_t)((*rec_num >> 8) & 0xFF);
        s_cpm_io_fcb.random_r2 = 0;
        if (bdos(34, (int)&s_cpm_io_fcb) != 0) {
            return -1;
        }
        (*rec_num)++;
        *sec_pos = 0;
    }
    return 0;
}

static int file_write_op(const char *filename, uint16_t start_row,
                         uint16_t end_row, uint8_t format)
{
    uint16_t row;
    char *line_buf = g_scratch_line_buf;
    uint16_t rec_num = 0;
    uint8_t sec_pos = 0;
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
    orig_user = bdos(32, 0xFF);
    bdos(32, g_target_user);

    bdos(19, (int)&s_cpm_io_fcb);
    if ((uint8_t)bdos(22, (int)&s_cpm_io_fcb) == 0xFF) {
        bdos(32, orig_user);
        return -1;
    }

    bdos(26, (int)s_cpm_sec_buf);

    for (row = start_row; row <= end_row && row < g_doc_total_lines; row++) {
        len = fetch_line_to_buffer(row, line_buf, MAX_ACTIVE_PAYLOAD);
        for (i = 0; i < len; i++) {
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
    }

    while (sec_pos != 0) {
        if (cpm_write_byte(0x1A, &sec_pos, &rec_num) != 0) {
            goto write_err;
        }
    }

    bdos(16, (int)&s_cpm_io_fcb);
    bdos(26, DEFAULT_DMA);
    bdos(32, orig_user);

    checkout_active_line(g_cur_doc_row);
    g_need_screen_render = 1;
    return 0;

write_err:
    bdos(16, (int)&s_cpm_io_fcb);
    bdos(26, DEFAULT_DMA);
    bdos(32, orig_user);
    return -1;
}
#else
static int file_read_op(const char *filename, uint8_t is_insert)
{
    FILE *fp;
    char *line_buf = g_scratch_line_buf;
    uint16_t row;
    int c;
    uint16_t col = 0;

    if (!filename || filename[0] == '\0') {
        return -1;
    }

    fp = fopen(filename, "rb");
    if (!fp) {
        modal_alert_file_not_found(filename);
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
        strncpy(g_current_filename, filename, sizeof(g_current_filename) - 1);
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
    g_need_screen_render = 1;
    return 0;
}

static int file_write_op(const char *filename, uint16_t start_row,
                         uint16_t end_row, uint8_t format)
{
    FILE *fp;
    uint16_t row;
    char *line_buf = g_scratch_line_buf;

    if (!filename || filename[0] == '\0') {
        return -1;
    }

    commit_active_line();

    fp = fopen(filename, "wb");
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
    int res = file_write_op(target, 0, last_row, format);
    if (res == 0) {
#ifdef __CPM__
        g_doc_drive = s_cpm_io_fcb.drive;
        g_doc_user = g_target_user;
        cpm_format_doc_filename(&s_cpm_io_fcb, g_doc_user);
#else
        if (filename && filename != g_current_filename) {
            strncpy(g_current_filename, filename,
                    sizeof(g_current_filename) - 1);
            g_current_filename[sizeof(g_current_filename) - 1] = '\0';
        }
#endif
        g_doc_modified = 0;
#ifndef __CPM__
        modal_show_notification("Save Complete",
                                filename ? filename : g_current_filename);
#endif
    }
    return res;
}

int file_save_block(const char *filename, uint16_t start_row,
                    uint16_t end_row, uint8_t format)
{
    int res = file_write_op(filename, start_row, end_row, format);
#ifndef __CPM__
    if (res == 0) {
        modal_show_notification("Save Complete", filename);
    }
#endif
    return res;
}
