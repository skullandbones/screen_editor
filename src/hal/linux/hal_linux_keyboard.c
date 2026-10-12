/*==============================================================================
 * HAL_LINUX_KEYBOARD.C: Linux POSIX HAL - Keyboard Input & Escape Decoding
 *
 * Purpose:
 *   Implements non-blocking POSIX stdin polling, VT100/ANSI escape sequence
 *   decoding (arrow keys, function keys, PageUp/Down), and WordStar mapping.
 *   Discretely tokenizes escape sequences to prevent burst input clumping.
 *   Strictly adheres to docs/UI_UX_DESIGN.md.
 *
 * Part of SE.COM / Linux Native Profile (x86_64 and AArch64)
 *============================================================================*/

#include <stdio.h>
#include <unistd.h>
#include <poll.h>
#include "../../include/config.h"
#include "../../include/hal.h"

#define RAW_BUF_SIZE 256

static unsigned char s_raw_buf[RAW_BUF_SIZE];
static int s_buf_head = 0;
static int s_buf_tail = 0;

static int get_raw_byte(int timeout_ms)
{
    if (s_buf_tail < s_buf_head) {
        return (int)s_raw_buf[s_buf_tail++];
    }

    s_buf_head = 0;
    s_buf_tail = 0;

    if (timeout_ms > 0) {
        struct pollfd pfd;
        pfd.fd = STDIN_FILENO;
        pfd.events = POLLIN;
        pfd.revents = 0;
        if (poll(&pfd, 1, timeout_ms) <= 0) {
            return -1;
        }
    }

    ssize_t n = read(STDIN_FILENO, s_raw_buf, sizeof(s_raw_buf));
    if (n > 0) {
        s_buf_head = (int)n;
        return (int)s_raw_buf[s_buf_tail++];
    }
    return -1;
}

static void unget_raw_byte(int byte_val)
{
    if (s_buf_tail > 0) {
        s_buf_tail--;
        s_raw_buf[s_buf_tail] = (unsigned char)byte_val;
    }
}

int hal_console_check_key(void)
{
    if (s_buf_tail < s_buf_head) {
        return 1;
    }
    struct pollfd pfd;
    pfd.fd = STDIN_FILENO;
    pfd.events = POLLIN;
    pfd.revents = 0;
    return poll(&pfd, 1, 0) > 0;
}

int hal_console_getkey(void)
{
    int c = get_raw_byte(0);
    if (c < 0) {
        return 0;
    }

    /* Handle ESC and ANSI Escape Sequences */
    if (c == 27) {
        int b1 = get_raw_byte(30);
        if (b1 < 0) {
            return KEY_ESC;
        }

        /* CSI Sequences: ESC [ ... */
        if (b1 == '[') {
            int b2 = get_raw_byte(30);
            if (b2 < 0) {
                return KEY_ESC;
            }
            switch (b2) {
            case 'A': return KEY_UP;    /* Up */
            case 'B': return KEY_DOWN;  /* Down */
            case 'C': return KEY_RIGHT; /* Right */
            case 'D': return KEY_LEFT;  /* Left */
            case 'H': return KEY_HOME;  /* Home */
            case 'F': return KEY_END;   /* End */
            default: break;
            }

            if (b2 >= '0' && b2 <= '9') {
                int code = b2 - '0';
                int b3 = get_raw_byte(30);
                while (b3 >= '0' && b3 <= '9') {
                    code = code * 10 + (b3 - '0');
                    b3 = get_raw_byte(30);
                }
                if (b3 == '~') {
                    switch (code) {
                    case 1: return KEY_HOME;  /* Home */
                    case 2: return KEY_INS;   /* Insert */
                    case 3: return KEY_DEL;   /* Delete */
                    case 4: return KEY_END;   /* End */
                    case 5: return KEY_PGUP;  /* Page Up */
                    case 6: return KEY_PGDN;  /* Page Down */
                    default: break;
                    }
                }
            }
            return KEY_ESC;
        }

        /* SS3 Sequences: ESC O ... */
        if (b1 == 'O') {
            int b2 = get_raw_byte(30);
            if (b2 < 0) {
                return KEY_ESC;
            }
            switch (b2) {
            case 'A': return KEY_UP;    /* Up */
            case 'B': return KEY_DOWN;  /* Down */
            case 'C': return KEY_RIGHT; /* Right */
            case 'D': return KEY_LEFT;  /* Left */
            case 'H': return KEY_HOME;  /* Home */
            case 'F': return KEY_END;   /* End */
            default: break;
            }
            return KEY_ESC;
        }

        /* Not a recognized escape sequence prefix: unget and return ESC */
        unget_raw_byte(b1);
        return KEY_ESC;
    }

    /* Translate Enter */
    if (c == 10 || c == 13) {
        return KEY_ENTER;
    }

    /* Translate Backspace */
    if (c == 127 || c == 8) {
        return KEY_BACKSPACE;
    }

    return c;
}
