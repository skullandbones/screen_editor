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
char    g_current_filename[64] = {0};
uint8_t g_file_format = FMT_CPM;

void file_populate_fcb(const char *path, cpm_fcb_t *fcb)
{
    int i;
    const char *p = path;
    const char *dot;

    if (!fcb) return;
    memset(fcb, 0, sizeof(cpm_fcb_t));
    memset(fcb->name, ' ', 8);
    memset(fcb->ext, ' ', 3);

    if (p[0] && p[1] == ':') {
        char drive_letter = p[0];
        if (drive_letter >= 'a' && drive_letter <= 'p') {
            fcb->drive = (uint8_t)(drive_letter - 'a' + 1);
        } else if (drive_letter >= 'A' && drive_letter <= 'P') {
            fcb->drive = (uint8_t)(drive_letter - 'A' + 1);
        }
        p += 2;
    }

    dot = strchr(p, '.');
    for (i = 0; i < 8 && p[i] && p[i] != '.'; i++) {
        char c = p[i];
        if (c >= 'a' && c <= 'z') c = (char)(c - 'a' + 'A');
        fcb->name[i] = c;
    }

    if (dot) {
        dot++;
        for (i = 0; i < 3 && dot[i]; i++) {
            char c = dot[i];
            if (c >= 'a' && c <= 'z') c = (char)(c - 'a' + 'A');
            fcb->ext[i] = c;
        }
    }
}

int file_check_hibernated(const char *path)
{
    (void)path;
    return 0;
}

int file_load(const char *filename)
{
    FILE *fp;
    char line_buf[MAX_ACTIVE_LINE_STRIDE];
    uint16_t row = 0;
    int c;
    uint16_t col = 0;

    if (!filename || filename[0] == '\0') {
        return -1;
    }

    fp = fopen(filename, "rb");
    if (!fp) {
        return -1;
    }

    buffer_init();
    g_file_format = FMT_LINUX;

    while ((c = fgetc(fp)) != EOF) {
        if (c == 0x1A) { /* CP/M EOF marker */
            break;
        }
        if (c == '\r') {
            g_file_format = FMT_CPM;
            continue;
        }
        if (c == '\n') {
            line_buf[col] = '\0';
            if (row == 0) {
                checkout_active_line(0);
                snprintf(g_active_line_buf, sizeof(g_active_line_buf),
                         "%s", line_buf);
                g_active_line_len = col;
                commit_active_line();
            } else {
                insert_blank_line(row);
                checkout_active_line(row);
                snprintf(g_active_line_buf, sizeof(g_active_line_buf),
                         "%s", line_buf);
                g_active_line_len = col;
                commit_active_line();
            }
            row++;
            col = 0;
            continue;
        }
        if (col + 1 < MAX_INPUT_LINE_CHARS) {
            line_buf[col++] = (char)c;
        }
    }

    /* Final line if file did not end with newline */
    if (col > 0 || row == 0) {
        line_buf[col] = '\0';
        if (row == 0) {
            checkout_active_line(0);
            snprintf(g_active_line_buf, sizeof(g_active_line_buf),
                     "%s", line_buf);
            g_active_line_len = col;
            commit_active_line();
        } else {
            insert_blank_line(row);
            checkout_active_line(row);
            snprintf(g_active_line_buf, sizeof(g_active_line_buf),
                     "%s", line_buf);
            g_active_line_len = col;
            commit_active_line();
        }
        row++;
    }

    fclose(fp);

    strncpy(g_current_filename, filename, sizeof(g_current_filename) - 1);
    g_current_filename[sizeof(g_current_filename) - 1] = '\0';

    g_doc_total_lines = row ? row : 1;
    g_cur_doc_row = 0;
    g_cur_col = 0;
    g_top_doc_row = 0;
    g_doc_modified = 0;
    checkout_active_line(0);
    g_need_screen_render = 1;
    return 0;
}

int file_save(const char *filename, uint8_t format)
{
    FILE *fp;
    uint16_t row;
    char line_buf[MAX_ACTIVE_LINE_STRIDE];
    const char *target = filename ? filename : g_current_filename;

    if (!target || target[0] == '\0') {
        return -1;
    }

    commit_active_line();

    fp = fopen(target, "wb");
    if (!fp) {
        return -1;
    }

    for (row = 0; row < g_doc_total_lines; row++) {
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

    if (filename && filename != g_current_filename) {
        strncpy(g_current_filename, filename, sizeof(g_current_filename) - 1);
        g_current_filename[sizeof(g_current_filename) - 1] = '\0';
    }

    g_doc_modified = 0;
    checkout_active_line(g_cur_doc_row);
    modal_show_notification("Save Complete",
                            filename ? filename : g_current_filename);
    return 0;
}

int file_save_block(const char *filename,
                     uint16_t start_row, uint16_t end_row,
                     uint8_t format)
{
    FILE *fp;
    uint16_t row;
    char line_buf[MAX_ACTIVE_LINE_STRIDE];

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
    modal_show_notification("Export Complete", filename);
    return 0;
}
