/*==============================================================================
 * HAL_LINUX_KEYBOARD.C: Linux POSIX HAL - Keyboard Input & Escape Decoding
 *
 * Purpose:
 *   Implements non-blocking POSIX stdin polling, VT100/ANSI escape sequence
 *   decoding (arrow keys, function keys, PageUp/Down), and WordStar mapping.
 *   Strictly adheres to docs/UI_UX_DESIGN.md.
 *
 * Part of SE.COM / Linux Native Profile (x86_64 and AArch64)
 *============================================================================*/

#include <stdio.h>
#include <unistd.h>
#include <poll.h>
#include "../../include/config.h"
#include "../../include/hal.h"

int hal_console_check_key(void)
{
    struct pollfd pfd;
    pfd.fd = STDIN_FILENO;
    pfd.events = POLLIN;
    pfd.revents = 0;
    return poll(&pfd, 1, 0) > 0;
}

int hal_console_getkey(void)
{
    unsigned char c;
    ssize_t n;

    n = read(STDIN_FILENO, &c, 1);
    if (n <= 0) {
        return 0;
    }

    /* Handle ESC and ANSI Escape Sequences */
    if (c == 27) {
        struct pollfd pfd;
        unsigned char seq[8];
        int seq_len = 0;

        pfd.fd = STDIN_FILENO;
        pfd.events = POLLIN;

        /* If no bytes follow within 30ms, treat as standalone ESC key */
        while (poll(&pfd, 1, 30) > 0 && seq_len < 6) {
            if (read(STDIN_FILENO, &seq[seq_len], 1) > 0) {
                seq_len++;
            }
        }

        if (seq_len == 0) {
            return KEY_ESC;
        }

        /* CSI: \033[... */
        if (seq[0] == '[') {
            if (seq_len == 2) {
                switch (seq[1]) {
                case 'A': return KEY_UP;    /* Up */
                case 'B': return KEY_DOWN;  /* Down */
                case 'C': return KEY_RIGHT; /* Right */
                case 'D': return KEY_LEFT;  /* Left */
                case 'H': return KEY_HOME;  /* Home */
                case 'F': return KEY_END;   /* End */
                default: break;
                }
            } else if (seq_len >= 3 && seq[2] == '~') {
                switch (seq[1]) {
                case '1': return KEY_HOME;  /* Home */
                case '2': return KEY_INS;   /* Insert */
                case '3': return KEY_DEL;   /* Delete */
                case '4': return KEY_END;   /* End */
                case '5': return KEY_PGUP;  /* Page Up */
                case '6': return KEY_PGDN;  /* Page Down */
                default: break;
                }
            }
        } else if (seq[0] == 'O') {
            /* SS3 sequences */
            switch (seq[1]) {
            case 'A': return KEY_UP;    /* Up */
            case 'B': return KEY_DOWN;  /* Down */
            case 'C': return KEY_RIGHT; /* Right */
            case 'D': return KEY_LEFT;  /* Left */
            case 'H': return KEY_HOME;  /* Home */
            case 'F': return KEY_END;   /* End */
            default: break;
            }
        }
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

    return (int)c;
}
