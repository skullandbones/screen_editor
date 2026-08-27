#include <stdio.h>
#include <string.h>
#include "terminal.h"
#include "buffer.h"
#include "editor.h"

/*
 * Low-level BDOS console character output (Function 2)
 */
void term_putc(char ch) {
    putchar(ch);
}

void term_puts(const char *str) {
    while (*str) {
        putchar(*str++);
    }
}

/*
 * Low-level unbuffered BDOS Direct Console I/O (Function 6)
 */
static int raw_getch(void) {
    int ch;
    /* In standard CP/M, direct I/O polls non-blocking or blocking depending on call */
    ch = getchar();
    return ch;
}

void term_init(void) {
    /* Hide cursor or enable VT100 wrap */
    term_puts("\x1b[?7h");
}

void term_restore(void) {
    term_move_cursor(SCREEN_ROWS, 1);
    term_set_inverse(false);
    term_puts("\x1b[0m\r\n");
}

void term_clear_screen(void) {
    term_puts("\x1b[2J\x1b[H");
}

void term_move_cursor(uint8_t row, uint8_t col) {
    char buf[16];
    sprintf(buf, "\x1b[%d;%dH", row, col);
    term_puts(buf);
}

void term_clear_to_eol(void) {
    term_puts("\x1b[K");
}

void term_set_inverse(bool enable) {
    if (enable) {
        term_puts("\x1b[7m");
    } else {
        term_puts("\x1b[0m");
    }
}

/*
 * Parse multi-byte ANSI / Minicom escape sequences
 */
int term_read_key(void) {
    int c = raw_getch();
    if (c == KEY_ESC) {
        int c2 = raw_getch();
        if (c2 == '[' || c2 == 'O') {
            int c3 = raw_getch();
            switch (c3) {
                case 'A': return KEY_ARROW_UP;
                case 'B': return KEY_ARROW_DOWN;
                case 'C': return KEY_ARROW_RIGHT;
                case 'D': return KEY_ARROW_LEFT;
                case 'H': return KEY_HOME;
                case 'F': return KEY_END;
                case '1':
                case '2':
                case '3':
                case '4':
                case '5':
                case '6': {
                    int c4 = raw_getch(); /* Eat trailing '~' */
                    if (c3 == '3' && c4 == '~') return KEY_DELETE_KEY;
                    if (c3 == '5' && c4 == '~') return KEY_PAGE_UP;
                    if (c3 == '6' && c4 == '~') return KEY_PAGE_DOWN;
                    break;
                }
            }
        }
        return KEY_ESC;
    }
    return c;
}

/*
 * Render editor viewport with tab expansions
 */
void term_render_screen(void) {
    uint8_t screen_row;
    char line_text[MAX_LINE_LEN];
    uint16_t line_len;

    for (screen_row = 1; screen_row <= SCREEN_ROWS - 1; screen_row++) {
        uint16_t buf_row = g_buf.top_line + (screen_row - 1);
        term_move_cursor(screen_row, 1);
        term_clear_to_eol();

        if (buf_row < g_buf.total_lines) {
            uint16_t i;
            uint16_t vcol = 0;
            buffer_get_line(buf_row, line_text, &line_len);

            for (i = 0; i < line_len && vcol < SCREEN_COLS; i++) {
                if (line_text[i] == '\t') {
                    uint16_t next_tab = (vcol / g_buf.tab_size + 1) * g_buf.tab_size;
                    while (vcol < next_tab && vcol < SCREEN_COLS) {
                        term_putc(' ');
                        vcol++;
                    }
                } else {
                    term_putc(line_text[i]);
                    vcol++;
                }
            }
        } else {
            term_puts("~");
        }
    }

    term_render_status(g_app.filename, g_app.status_msg);

    /* Position cursor on screen */
    {
        uint8_t cur_srow = (g_buf.cursor_row - g_buf.top_line) + 1;
        uint16_t cur_scol;
        buffer_get_line(g_buf.cursor_row, line_text, &line_len);
        cur_scol = buffer_calc_visual_col(line_text, g_buf.cursor_col, g_buf.tab_size) + 1;
        term_move_cursor(cur_srow, (uint8_t)cur_scol);
    }
}

void term_render_status(const char *filename, const char *status_msg) {
    char status[SCREEN_COLS + 1];
    term_move_cursor(SCREEN_ROWS, 1);
    term_set_inverse(true);

    snprintf(status, sizeof(status), " SE v%s | File: %s %s | Ln %u/%u Col %u | ^S:Save ^Q:Quit",
             EDITOR_VERSION,
             (filename && filename[0]) ? filename : "[No Name]",
             g_buf.modified ? "[+]" : "",
             g_buf.cursor_row + 1,
             g_buf.total_lines,
             g_buf.cursor_col + 1);

    term_puts(status);
    /* Pad remaining columns with inverse space */
    {
        size_t len = strlen(status);
        while (len < SCREEN_COLS) {
            term_putc(' ');
            len++;
        }
    }
    term_set_inverse(false);
}
