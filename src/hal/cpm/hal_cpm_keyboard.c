/*==============================================================================
 * HAL_CPM_KEYBOARD.C: CP/M HAL - Keyboard & VT100 Decoder
 *
 * Purpose:
 *   Implements BDOS console status polling, direct console character read,
 *   and ANSI/VT100 escape sequence decoding (arrow keys, Home/End, PgUp/PgDn).
 *   Strictly adheres to docs/UI_UX_DESIGN.md.
 *
 * Part of SE.COM / CP/M C Semantic Equivalent Profile (SEC.COM)
 *============================================================================*/

#include <cpm.h>
#include <stdint.h>
#include "../../include/config.h"
#include "../../include/hal.h"

static int bios_const(void)
{
#asm
    push ix
    push iy
    push bc
    push de
    ld hl,(0x0001)
    inc hl
    inc hl
    inc hl
    call bios_call_hl_const
    pop de
    pop bc
    pop iy
    pop ix
    ld l,a
    ld h,0
    ret
bios_call_hl_const:
    jp (hl)
#endasm
}

static int bios_conin(void)
{
#asm
    push ix
    push iy
    push bc
    push de
    ld hl,(0x0001)
    ld de,6
    add hl,de
    call bios_call_hl_conin
    pop de
    pop bc
    pop iy
    pop ix
    ld l,a
    ld h,0
    ret
bios_call_hl_conin:
    jp (hl)
#endasm
}

int hal_console_check_key(void)
{
    return (bios_const() != 0);
}

int hal_console_getkey(void)
{
    unsigned char c = (unsigned char)bios_conin();

    /* Handle ESC and ANSI Escape Sequences */
    if (c == 27) {
        unsigned char seq[8];
        int seq_len = 0;
        uint16_t timeout_loops;

        while (seq_len < 6) {
            int found = 0;
            for (timeout_loops = 0; timeout_loops < 3000; timeout_loops++) {
                if (bios_const()) {
                    seq[seq_len++] = (unsigned char)bios_conin();
                    found = 1;
                    break;
                }
            }
            if (!found) {
                break;
            }
        }

        if (seq_len == 0) {
            return KEY_ESC;
        }

        /* CSI sequence: \033[... */
        if (seq[0] == '[') {
            if (seq_len == 2) {
                switch (seq[1]) {
                case 'A': return KEY_UP;
                case 'B': return KEY_DOWN;
                case 'C': return KEY_RIGHT;
                case 'D': return KEY_LEFT;
                case 'H': return KEY_HOME;
                case 'F': return KEY_END;
                default: break;
                }
            } else if (seq_len >= 3 && seq[2] == '~') {
                switch (seq[1]) {
                case '1': return KEY_HOME;
                case '2': return KEY_INS;
                case '3': return KEY_DEL;
                case '4': return KEY_END;
                case '5': return KEY_PGUP;
                case '6': return KEY_PGDN;
                default: break;
                }
            }
        } else if (seq[0] == 'O') {
            /* SS3 sequence: \033O... */
            switch (seq[1]) {
            case 'A': return KEY_UP;
            case 'B': return KEY_DOWN;
            case 'C': return KEY_RIGHT;
            case 'D': return KEY_LEFT;
            case 'H': return KEY_HOME;
            case 'F': return KEY_END;
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
