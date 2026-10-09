/*==============================================================================
 * UI_MODAL.C: Core Subsystem - Tier 1/2 Centered Modals & Dialog Engine
 *
 * Purpose:
 *   Implements centered modal dialogues, double-line frame borders,
 *   Tier 1 notifications, and Tier 2 confirmation query pop-ups.
 *   Strictly adheres to docs/UI_UX_DESIGN.md design standards.
 *   C semantic equivalent to src/core/ui_modal.asm.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#include <string.h>
#include <stdio.h>
#include "../include/config.h"
#include "../include/buffer.h"
#include "../include/ui.h"
#include "../include/ui_modal.h"
#include "../include/hal.h"

void modal_draw_frame(uint8_t top, uint8_t left,
                      uint8_t width, uint8_t height,
                      const char *title)
{
    uint8_t r, c;
    uint8_t title_len = (title && *title) ? (uint8_t)strlen(title) : 0;
    uint8_t title_start = 2;

    /* Draw Top Border */
    hal_console_locate(top, left);
    hal_console_putc('+');
    for (c = 1; c < width - 1; c++) {
        if (title_len > 0 && c >= title_start &&
            c < title_start + title_len) {
            hal_console_putc(title[c - title_start]);
        } else {
            hal_console_putc('-');
        }
    }
    hal_console_putc('+');

    /* Draw Side Borders and Clear Interior */
    for (r = 1; r < height - 1; r++) {
        hal_console_locate(top + r, left);
        hal_console_putc('|');
        for (c = 1; c < width - 1; c++) {
            hal_console_putc(' ');
        }
        hal_console_putc('|');
    }

    /* Draw Bottom Border */
    hal_console_locate(top + height - 1, left);
    hal_console_putc('+');
    for (c = 1; c < width - 1; c++) {
        hal_console_putc('-');
    }
    hal_console_putc('+');
}

int modal_alert(const char *title, const char *msg1, const char *msg2)
{
    uint8_t width = 46;
    uint8_t height = 7;
    uint8_t top = (g_active_rows > height) ? (g_active_rows - height) / 2 : 5;
    uint8_t left = (g_active_cols > width) ? (g_active_cols - width) / 2 : 15;

    hal_console_hide_cursor();
    modal_draw_frame(top, left, width, height, title);

    if (msg1) {
        hal_console_locate(top + 2, left + 4);
        hal_console_puts(msg1);
    }
    if (msg2) {
        hal_console_locate(top + 3, left + 4);
        hal_console_puts(msg2);
    }

    /* Draw Centered [ OK ] Button */
    hal_console_locate(top + 5, left + (width - 8) / 2);
    hal_console_inverse_on();
    hal_console_puts("[  OK  ]");
    hal_console_inverse_off();

    hal_console_getkey();
    g_need_screen_render = 1;
    return MODAL_RES_OK;
}

int modal_confirm(const char *title, const char *msg,
                   const char *btn1, const char *btn2)
{
    uint8_t width = 50;
    uint8_t height = 7;
    uint8_t top = (g_active_rows > height) ? (g_active_rows - height) / 2 : 5;
    uint8_t left = (g_active_cols > width) ? (g_active_cols - width) / 2 : 15;
    uint8_t selected = 0;

    hal_console_hide_cursor();
    modal_draw_frame(top, left, width, height, title);

    if (msg) {
        hal_console_locate(top + 2, left + 4);
        hal_console_puts(msg);
    }

    while (1) {
        /* Render Button 1 */
        hal_console_locate(top + 4, left + 10);
        if (selected == 0) hal_console_inverse_on();
        hal_console_puts("[ ");
        hal_console_puts(btn1 ? btn1 : "Yes");
        hal_console_puts(" ]");
        if (selected == 0) hal_console_inverse_off();

        /* Render Button 2 */
        hal_console_locate(top + 4, left + 28);
        if (selected == 1) hal_console_inverse_on();
        hal_console_puts("[ ");
        hal_console_puts(btn2 ? btn2 : "No");
        hal_console_puts(" ]");
        if (selected == 1) hal_console_inverse_off();

        int k = hal_console_getkey();
        if (k == KEY_ENTER || k == ' ') {
            g_need_screen_render = 1;
            return (selected == 0) ? MODAL_RES_YES : MODAL_RES_NO;
        } else if (k == KEY_ESC || k == 'q' || k == 'Q') {
            g_need_screen_render = 1;
            return MODAL_RES_CANCEL;
        } else if (k == KEY_TAB || k == KEY_CTRL_D || k == 0x1B) {
            selected = (selected == 0) ? 1 : 0;
        } else if (k == 'y' || k == 'Y') {
            g_need_screen_render = 1;
            return MODAL_RES_YES;
        } else if (k == 'n' || k == 'N') {
            g_need_screen_render = 1;
            return MODAL_RES_NO;
        }
    }
}

int modal_confirm_3btn(const char *title, const char *msg,
                        const char *btn1, const char *btn2, const char *btn3)
{
    uint8_t width = 56;
    uint8_t height = 7;
    uint8_t top = (g_active_rows > height) ? (g_active_rows - height) / 2 : 5;
    uint8_t left = (g_active_cols > width) ? (g_active_cols - width) / 2 : 12;
    uint8_t selected = 0;

    hal_console_hide_cursor();
    modal_draw_frame(top, left, width, height, title);

    if (msg) {
        hal_console_locate(top + 2, left + 4);
        hal_console_puts(msg);
    }

    while (1) {
        hal_console_locate(top + 4, left + 5);
        if (selected == 0) hal_console_inverse_on();
        hal_console_puts("[ ");
        hal_console_puts(btn1 ? btn1 : "1");
        hal_console_puts(" ]");
        if (selected == 0) hal_console_inverse_off();

        hal_console_locate(top + 4, left + 20);
        if (selected == 1) hal_console_inverse_on();
        hal_console_puts("[ ");
        hal_console_puts(btn2 ? btn2 : "2");
        hal_console_puts(" ]");
        if (selected == 1) hal_console_inverse_off();

        hal_console_locate(top + 4, left + 36);
        if (selected == 2) hal_console_inverse_on();
        hal_console_puts("[ ");
        hal_console_puts(btn3 ? btn3 : "3");
        hal_console_puts(" ]");
        if (selected == 2) hal_console_inverse_off();

        int k = hal_console_getkey();
        if (k == KEY_ENTER || k == ' ') {
            g_need_screen_render = 1;
            if (selected == 0) return MODAL_RES_OK;
            if (selected == 1) return MODAL_RES_NO;
            return MODAL_RES_DISCARD;
        } else if (k == KEY_ESC || k == 'q' || k == 'Q') {
            g_need_screen_render = 1;
            return MODAL_RES_CANCEL;
        } else if (k == KEY_TAB || k == KEY_CTRL_D) {
            selected = (selected + 1) % 3;
        }
    }
}

int modal_prompt_text(const char *title, const char *prompt,
                       char *buffer, size_t max_len)
{
    uint8_t width = 50;
    uint8_t height = 7;
    uint8_t top = (g_active_rows > height) ? (g_active_rows - height) / 2 : 5;
    uint8_t left = (g_active_cols > width) ? (g_active_cols - width) / 2 : 15;
    uint8_t field_len = width - 10;
    size_t cur_len = buffer ? strlen(buffer) : 0;
    size_t i;

    modal_draw_frame(top, left, width, height, title);
    hal_console_locate(top + 2, left + 4);
    hal_console_puts(prompt);

    while (1) {
        hal_console_locate(top + 4, left + 4);
        hal_console_inverse_on();
        for (i = 0; i < field_len; i++) {
            if (i < cur_len) {
                hal_console_putc(buffer[i]);
            } else {
                hal_console_putc(' ');
            }
        }
        hal_console_inverse_off();
        hal_console_locate(top + 4, (uint8_t)(left + 4 + cur_len));
        hal_console_show_cursor();

        int k = hal_console_getkey();
        if (k == KEY_ENTER) {
            g_need_screen_render = 1;
            return MODAL_RES_OK;
        } else if (k == KEY_ESC) {
            g_need_screen_render = 1;
            return MODAL_RES_CANCEL;
        } else if (k == KEY_BACKSPACE || k == KEY_DEL) {
            if (cur_len > 0) {
                cur_len--;
                buffer[cur_len] = '\0';
            }
        } else if (k >= 32 && k <= 126 && cur_len + 1 < max_len &&
                   cur_len < field_len) {
            buffer[cur_len++] = (char)k;
            buffer[cur_len] = '\0';
        }
    }
}

int modal_confirm_save_changes(void)
{
    if (!g_doc_modified) {
        return MODAL_RES_OK;
    }

    return modal_confirm("Unsaved Changes",
                         "Save changes before closing?",
                         "Save", "Don't Save");
}

void modal_show_notification(const char *title, const char *message)
{
    uint8_t width = 50;
    uint8_t height = 7;
    uint8_t top = (uint8_t)(((g_active_rows - height) / 2) + 1);
    uint8_t left = (uint8_t)(((g_active_cols - width) / 2) + 1);
    const char *prompt = "Press any key to continue";
    size_t msg_len, prompt_len, i;

    hal_console_hide_cursor();
    modal_draw_frame(top, left, width, height, title);

    if (message && *message) {
        msg_len = strlen(message);
        if (msg_len > (size_t)(width - 4)) {
            msg_len = width - 4;
        }
        hal_console_locate(top + 2,
                           (uint8_t)(left + ((width - msg_len) / 2)));
        for (i = 0; i < msg_len; i++) {
            hal_console_putc(message[i]);
        }
    }

    prompt_len = strlen(prompt);
    hal_console_locate(top + 4,
                       (uint8_t)(left + ((width - prompt_len) / 2)));
    hal_console_puts(prompt);

    hal_console_getkey();
    g_need_screen_render = 1;
}
