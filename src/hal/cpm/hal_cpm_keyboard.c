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

int bios_const(void)
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

int bios_conin(void)
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

static int cpm_read_byte_timeout(uint16_t max_loops)
{
    uint16_t i;
    for (i = 0; i < max_loops; i++) {
        if (bios_const()) {
            return (int)(unsigned char)bios_conin();
        }
    }
    return -1;
}

static const uint16_t s_arrow_keys[4] = {
    KEY_UP, KEY_DOWN, KEY_RIGHT, KEY_LEFT
};

int hal_console_getkey(void)
{
    unsigned char c = (unsigned char)bios_conin();

    /* Handle ESC and ANSI Escape Sequences */
    if (c == 27) {
        int b1 = cpm_read_byte_timeout(10000);
        if (b1 < 0) {
            return KEY_ESC;
        }

        /* CSI sequence: \033[... */
        if (b1 == '[') {
            int b = cpm_read_byte_timeout(20000);
            int prefix = 0;
            int modifier = 0;
            int in_modifier = 0;

            if (b < 0) {
                return 0; /* Incomplete sequence: discard cleanly */
            }

            /* Parse parameter bytes: 0-9 and ; */
            while (b >= 0 && (b == ';' || (b >= '0' && b <= '9'))) {
                if (b == ';') {
                    in_modifier = 1;
                } else if (!in_modifier) {
                    prefix = prefix * 10 + (b - '0');
                } else {
                    modifier = modifier * 10 + (b - '0');
                }
                b = cpm_read_byte_timeout(20000);
            }

            /* Drain any intermediate or private CSI bytes (0x20..0x3F) */
            while (b >= 0x20 && b <= 0x3F) {
                b = cpm_read_byte_timeout(20000);
            }

            if (b < 0) {
                return 0;
            }

            /* Terminal character dispatch */
            if (b >= 'a' && b <= 'd') {
                return s_arrow_keys[b - 'a'] + 9;
            }
            if (b >= 'A' && b <= 'D') {
                return s_arrow_keys[b - 'A'] + ((modifier == 2) ? 9 : 0);
            }
            if (b == 'H') return (modifier == 5) ? KEY_CTRL_T : KEY_HOME;
            if (b == 'F') return (modifier == 5) ? KEY_CTRL_G : KEY_END;
            if (b == 'I') return KEY_PGUP;
            if (b == 'G') return KEY_PGDN;
            if (b == 'L' || b == '@') return KEY_INS;

            if (b == '~') {
                if (modifier == 5 && (prefix == 1 || prefix == 7)) {
                    return KEY_CTRL_T;
                }
                if (modifier == 5 && (prefix == 4 || prefix == 8)) {
                    return KEY_CTRL_G;
                }
                if (prefix == 1 || prefix == 7) return KEY_HOME;
                if (prefix == 4 || prefix == 8) return KEY_END;
                if (prefix == 2) return KEY_INS;
                if (prefix == 3) return KEY_DEL;
                if (prefix == 5) return KEY_PGUP;
                if (prefix == 6) return KEY_PGDN;
                return 0;
            }

            if (b == '^') {
                if (prefix == 7) return KEY_CTRL_T;
                if (prefix == 8) return KEY_CTRL_G;
                return 0;
            }

            /* Discard any trailing CSI bytes */
            while (cpm_read_byte_timeout(1000) >= 0);
            return 0;
        } else if (b1 == 'O') {
            /* SS3 sequence: \033O... */
            int b2 = cpm_read_byte_timeout(20000);
            if (b2 >= 'A' && b2 <= 'D') {
                return s_arrow_keys[b2 - 'A'];
            }
            if (b2 == 'H') return KEY_HOME;
            if (b2 == 'F') return KEY_END;
            return 0;
        } else if (b1 == '<' || b1 == 't' || b1 == 'T') {
            return KEY_CTRL_T;
        } else if (b1 == '>' || b1 == 'b' || b1 == 'B') {
            return KEY_CTRL_G;
        }

        /* Discard any trailing escape bytes */
        while (cpm_read_byte_timeout(1000) >= 0);
        return 0;
    }

    /* Translate Enter */
    if (c == 10 || c == 13) {
        return KEY_ENTER;
    }

    /* Translate Backspace and Rubout/Delete */
    if (c == 8) {
        return KEY_BACKSPACE;
    }
    if (c == 127) {
        return KEY_DEL;
    }

    return (int)c;
}
