#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "editor.h"
#include "buffer.h"
#include "terminal.h"
#include "hbios.h"

EditorApp g_app;

void editor_init(const char *filename) {
    memset(&g_app, 0, sizeof(EditorApp));
    g_app.running = true;

    if (filename && filename[0]) {
        strncpy(g_app.filename, filename, sizeof(g_app.filename) - 1);
    } else {
        g_app.filename[0] = '\0';
    }

    buffer_init(DEFAULT_TAB_SIZE);

    if (g_app.filename[0]) {
        editor_load_file(g_app.filename);
    } else {
        snprintf(g_app.status_msg, sizeof(g_app.status_msg), "SE v%s Ready", EDITOR_VERSION);
    }
}

static void handle_key(int key) {
    char line_buf[MAX_LINE_LEN];
    uint16_t line_len;

    buffer_get_line(g_buf.cursor_row, line_buf, &line_len);

    switch (key) {
        case KEY_CTRL_Q:
            g_app.running = false;
            break;

        case KEY_CTRL_S:
            if (g_app.filename[0]) {
                editor_save_file(g_app.filename);
            }
            break;

        case KEY_ARROW_UP:
            if (g_buf.cursor_row > 0) {
                g_buf.cursor_row--;
                if (g_buf.cursor_row < g_buf.top_line) {
                    g_buf.top_line = g_buf.cursor_row;
                }
            }
            break;

        case KEY_ARROW_DOWN:
            if (g_buf.cursor_row + 1 < g_buf.total_lines) {
                g_buf.cursor_row++;
                if (g_buf.cursor_row >= g_buf.top_line + (SCREEN_ROWS - 1)) {
                    g_buf.top_line = g_buf.cursor_row - (SCREEN_ROWS - 2);
                }
            }
            break;

        case KEY_ARROW_LEFT:
            if (g_buf.cursor_col > 0) {
                g_buf.cursor_col--;
            }
            break;

        case KEY_ARROW_RIGHT:
            if (g_buf.cursor_col < line_len) {
                g_buf.cursor_col++;
            }
            break;

        case KEY_HOME:
            g_buf.cursor_col = 0;
            break;

        case KEY_END:
            g_buf.cursor_col = line_len;
            break;

        case KEY_ENTER: {
            /* Split line at cursor position */
            char rest[MAX_LINE_LEN];
            uint16_t rest_len = 0;

            if (g_buf.cursor_col < line_len) {
                strcpy(rest, &line_buf[g_buf.cursor_col]);
                rest_len = line_len - g_buf.cursor_col;
                line_buf[g_buf.cursor_col] = '\0';
                buffer_set_line(g_buf.cursor_row, line_buf, g_buf.cursor_col);
            }
            buffer_insert_line(g_buf.cursor_row + 1, rest, rest_len);
            g_buf.cursor_row++;
            g_buf.cursor_col = 0;
            if (g_buf.cursor_row >= g_buf.top_line + (SCREEN_ROWS - 1)) {
                g_buf.top_line = g_buf.cursor_row - (SCREEN_ROWS - 2);
            }
            break;
        }

        case KEY_BACKSPACE:
        case KEY_DEL:
            if (g_buf.cursor_col > 0) {
                memmove(&line_buf[g_buf.cursor_col - 1],
                        &line_buf[g_buf.cursor_col],
                        line_len - g_buf.cursor_col + 1);
                g_buf.cursor_col--;
                buffer_set_line(g_buf.cursor_row, line_buf, line_len - 1);
            } else if (g_buf.cursor_row > 0) {
                /* Merge with previous line */
                char prev_line[MAX_LINE_LEN];
                uint16_t prev_len;
                buffer_get_line(g_buf.cursor_row - 1, prev_line, &prev_len);

                if (prev_len + line_len < MAX_LINE_LEN) {
                    strcat(prev_line, line_buf);
                    buffer_set_line(g_buf.cursor_row - 1, prev_line, prev_len + line_len);
                    buffer_delete_line(g_buf.cursor_row);
                    g_buf.cursor_row--;
                    g_buf.cursor_col = prev_len;
                }
            }
            break;

        case KEY_TAB:
            if (line_len < MAX_LINE_LEN - 1) {
                memmove(&line_buf[g_buf.cursor_col + 1],
                        &line_buf[g_buf.cursor_col],
                        line_len - g_buf.cursor_col + 1);
                line_buf[g_buf.cursor_col++] = '\t';
                buffer_set_line(g_buf.cursor_row, line_buf, line_len + 1);
            }
            break;

        default:
            if (key >= 32 && key <= 126 && line_len < MAX_LINE_LEN - 1) {
                memmove(&line_buf[g_buf.cursor_col + 1],
                        &line_buf[g_buf.cursor_col],
                        line_len - g_buf.cursor_col + 1);
                line_buf[g_buf.cursor_col++] = (char)key;
                buffer_set_line(g_buf.cursor_row, line_buf, line_len + 1);
            }
            break;
    }
}

void editor_run(void) {
    term_clear_screen();
    while (g_app.running) {
        int key;
        term_render_screen();
        key = term_read_key();
        handle_key(key);
    }
    term_restore();
}

int main(int argc, char *argv[]) {
    const char *target_file = (argc > 1) ? argv[1] : NULL;

    term_init();
    editor_init(target_file);
    editor_run();

    return 0;
}
