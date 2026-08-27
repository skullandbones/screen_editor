#include <stdio.h>
#include <string.h>
#include "editor.h"
#include "buffer.h"

bool editor_load_file(const char *filename) {
    FILE *fp;
    char line_buf[MAX_LINE_LEN];
    uint16_t row = 0;

    if (!filename || !filename[0]) {
        return false;
    }

    fp = fopen(filename, "r");
    if (!fp) {
        snprintf(g_app.status_msg, sizeof(g_app.status_msg), "New file: %s", filename);
        return false;
    }

    /* Reset buffer for new file */
    g_buf.total_lines = 0;

    while (fgets(line_buf, sizeof(line_buf), fp)) {
        size_t len = strlen(line_buf);
        /* Strip CR/LF */
        while (len > 0 && (line_buf[len - 1] == '\r' || line_buf[len - 1] == '\n')) {
            line_buf[--len] = '\0';
        }
        buffer_insert_line(row++, line_buf, (uint16_t)len);
    }

    fclose(fp);

    if (g_buf.total_lines == 0) {
        buffer_insert_line(0, "", 0);
    }

    g_buf.modified = false;
    snprintf(g_app.status_msg, sizeof(g_app.status_msg), "Loaded %u lines from %s", g_buf.total_lines, filename);
    return true;
}

bool editor_save_file(const char *filename) {
    FILE *fp;
    uint16_t row;
    char line_buf[MAX_LINE_LEN];
    uint16_t len;

    if (!filename || !filename[0]) {
        snprintf(g_app.status_msg, sizeof(g_app.status_msg), "Error: No filename specified");
        return false;
    }

    fp = fopen(filename, "w");
    if (!fp) {
        snprintf(g_app.status_msg, sizeof(g_app.status_msg), "Error: Could not write %s", filename);
        return false;
    }

    for (row = 0; row < g_buf.total_lines; row++) {
        buffer_get_line(row, line_buf, &len);
        fputs(line_buf, fp);
        fputc('\r', fp);
        fputc('\n', fp);
    }

    fclose(fp);
    g_buf.modified = false;
    snprintf(g_app.status_msg, sizeof(g_app.status_msg), "Saved %u lines to %s", g_buf.total_lines, filename);
    return true;
}
