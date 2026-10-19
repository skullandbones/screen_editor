/*==============================================================================
 * HAL_LINUX_CONSOLE.C: Linux POSIX HAL - Terminal Console & ANSI Driver
 *
 * Purpose:
 *   Implements ANSI terminal escape sequences, termios raw mode configuration,
 *   signal-driven SIGWINCH terminal resizing, and inverse video styling.
 *   Strictly adheres to docs/UI_UX_DESIGN.md.
 *
 * Part of SE.COM / Linux Native Profile (x86_64 and AArch64)
 *============================================================================*/

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <termios.h>
#include <signal.h>
#include <sys/ioctl.h>
#include "../../include/config.h"
#include "../../include/buffer.h"
#include "../../include/editor.h"
#include "../../include/ui.h"
#include "../../include/hal.h"

static struct termios s_orig_termios;
static int            s_raw_mode_active = 0;

static void restore_termios_on_exit(void)
{
    if (s_raw_mode_active) {
        /* Reset attributes and show cursor */
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &s_orig_termios);
        hal_console_show_cursor();
        hal_console_inverse_off();
        s_raw_mode_active = 0;
    }
}

static void sigwinch_handler(int sig)
{
    struct winsize ws;
    (void)sig;

    if (g_config.screen_mode == MODE_NATIVE &&
        ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0) {
        uint8_t view_rows;
        if (ws.ws_col >= SCREEN_COLS_80 && ws.ws_row >= SCREEN_ROWS_24) {
            g_active_cols = (uint8_t)(ws.ws_col > 255 ? 255 : ws.ws_col);
            g_active_rows = (uint8_t)(ws.ws_row > 255 ? 255 : ws.ws_row);
        } else {
            g_active_cols = SCREEN_COLS_80;
            g_active_rows = SCREEN_ROWS_24;
        }
        view_rows = (uint8_t)(g_active_rows - 1);
        if (g_cur_doc_row >= g_top_doc_row + view_rows) {
            g_top_doc_row = (uint16_t)(g_cur_doc_row - view_rows + 1);
        }
        update_horizontal_pan();
        g_need_screen_render = 1;
    }
}

int hal_console_get_native_size(uint8_t *cols, uint8_t *rows)
{
    struct winsize ws;

    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0 &&
        ws.ws_row > 0) {
        if (cols) {
            *cols = (uint8_t)(ws.ws_col > 255 ? 255 : ws.ws_col);
        }
        if (rows) {
            *rows = (uint8_t)(ws.ws_row > 255 ? 255 : ws.ws_row);
        }
        return 0;
    }
    return -1;
}

void hal_console_init(void)
{
    struct termios raw;
    struct winsize ws;

    if (!s_raw_mode_active) {
        if (tcgetattr(STDIN_FILENO, &s_orig_termios) == 0) {
            raw = s_orig_termios;
            /* Disable echo, canonical mode, extended input, signals */
            raw.c_iflag &= (tcflag_t)~(BRKINT | ICRNL | INPCK | ISTRIP |
                                       IXON);
            raw.c_oflag &= (tcflag_t)~(OPOST);
            raw.c_cflag |= (tcflag_t)(CS8);
            raw.c_lflag &= (tcflag_t)~(ECHO | ICANON | IEXTEN | ISIG);
            raw.c_cc[VMIN] = 0;   /* Non-blocking read */
            raw.c_cc[VTIME] = 1;  /* 100ms timeout */

            tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw);
            s_raw_mode_active = 1;
            atexit(restore_termios_on_exit);
        }
    }

    /* Set up window resize signal */
    signal(SIGWINCH, sigwinch_handler);

    if (g_config.screen_mode == MODE_NATIVE) {
        if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 &&
            ws.ws_col >= SCREEN_COLS_80 && ws.ws_row >= SCREEN_ROWS_24) {
            g_active_cols = (uint8_t)(ws.ws_col > 255 ? 255 : ws.ws_col);
            g_active_rows = (uint8_t)(ws.ws_row > 255 ? 255 : ws.ws_row);
        } else {
            g_active_cols = SCREEN_COLS_80;
            g_active_rows = SCREEN_ROWS_24;
        }
    } else if (g_config.screen_mode == MODE_120X40) {
        g_active_cols = SCREEN_COLS_120;
        g_active_rows = SCREEN_ROWS_40;
    } else {
        g_active_cols = SCREEN_COLS_80;
        g_active_rows = SCREEN_ROWS_24;
    }

    /* Emit canonical TERM_INIT: reset attributes, show cursor, clear & home */
    fputs("\033[0m\033[?25h\033[2J\033[H", stdout);
    fflush(stdout);
}

void hal_console_putc(char c)
{
    putchar(c);
    fflush(stdout);
}

void hal_console_puts(const char *s)
{
    if (s) {
        fputs(s, stdout);
        fflush(stdout);
    }
}

void hal_console_locate(uint8_t row, uint8_t col)
{
    printf("\033[%u;%uH", (unsigned)row, (unsigned)col);
    fflush(stdout);
}

void hal_console_inverse_on(void)
{
    fputs("\033[7m", stdout);
    fflush(stdout);
}

void hal_console_inverse_off(void)
{
    fputs("\033[0m", stdout);
    fflush(stdout);
}

void hal_console_clear(void)
{
    fputs("\033[2J\033[H", stdout);
    fflush(stdout);
}

void hal_console_clear_eol(void)
{
    fputs("\033[K", stdout);
    fflush(stdout);
}

void hal_console_hide_cursor(void)
{
    fputs("\033[?25l", stdout);
    fflush(stdout);
}

void hal_console_show_cursor(void)
{
    fputs("\033[?25h", stdout);
    fflush(stdout);
}
