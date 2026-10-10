/*==============================================================================
 * HAL_CPM_CONSOLE.C: CP/M Hardware Abstraction Layer - Console & ANSI Driver
 *
 * Purpose:
 *   Implements ANSI/VT100 console terminal escape sequences, inverse video,
 *   cursor positioning, screen clearing, and cursor visibility management
 *   for CP/M 2.2 / 3.0 / RomWBW environments.
 *   Strictly adheres to docs/UI_UX_DESIGN.md.
 *
 * Part of SE.COM / CP/M C Semantic Equivalent Profile (SEC.COM)
 *============================================================================*/

#include <stdio.h>
#include <stdint.h>
#include "../../include/config.h"
#include "../../include/ui.h"
#include "../../include/hal.h"

static void bios_conout(char c)
{
#asm
    pop hl
    pop de
    push de
    push hl
    ld c, e
    push ix
    push iy
    push bc
    push de
    ld hl, (0x0001)
    ld de, 9
    add hl, de
    call bios_call_hl_conout
    pop de
    pop bc
    pop iy
    pop ix
    ret
bios_call_hl_conout:
    jp (hl)
#endasm
}

void hal_console_init(void)
{
    g_active_cols = SCREEN_COLS_80;
    g_active_rows = SCREEN_ROWS_24;
    hal_console_inverse_off();
    hal_console_show_cursor();
}

void hal_console_putc(char c)
{
    bios_conout(c);
}

void hal_console_puts(const char *s)
{
    if (s) {
        while (*s) {
            bios_conout(*s++);
        }
    }
}

static void print_uint(uint8_t val)
{
    if (val >= 100) {
        bios_conout((char)('0' + (val / 100)));
        val %= 100;
        bios_conout((char)('0' + (val / 10)));
        val %= 10;
    } else if (val >= 10) {
        bios_conout((char)('0' + (val / 10)));
        val %= 10;
    }
    bios_conout((char)('0' + val));
}

void hal_console_locate(uint8_t row, uint8_t col)
{
    hal_console_puts("\033[");
    print_uint(row);
    bios_conout(';');
    print_uint(col);
    bios_conout('H');
}

void hal_console_inverse_on(void)
{
    hal_console_puts("\033[7m");
}

void hal_console_inverse_off(void)
{
    hal_console_puts("\033[0m");
}

void hal_console_clear(void)
{
    hal_console_puts("\033[H\033[2J");
}

void hal_console_clear_eol(void)
{
    hal_console_puts("\033[K");
}

void hal_console_hide_cursor(void)
{
    hal_console_puts("\033[?25l");
}

void hal_console_show_cursor(void)
{
    hal_console_puts("\033[?25h");
}
