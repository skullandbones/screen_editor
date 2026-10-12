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
#include "../include/file_io.h"
#include "../include/hal.h"
#ifndef __CPM__
#include <unistd.h>
#endif

#ifdef __CPM__
#define MODAL_BOX_WIDTH   50
#else
#define MODAL_BOX_WIDTH   52
#endif

void modal_puts_centered(uint8_t row, uint8_t left,
                        uint8_t width, const char *str)
{
    size_t len = str ? strlen(str) : 0;
    uint8_t interior_w = width - 2;
    uint8_t pad;
    size_t i;

    if (len > interior_w) {
        len = interior_w;
    }
    pad = (uint8_t)((interior_w - len) / 2);
    hal_console_locate(row, left + 1 + pad);
    for (i = 0; i < len; i++) {
        hal_console_putc(str[i]);
    }
}

void modal_draw_row_centered(uint8_t row, uint8_t left,
                             uint8_t width, const char *str)
{
    size_t len = str ? strlen(str) : 0;
    uint8_t interior_w = (width > 2) ? (width - 2) : 0;
    uint8_t pad, i;

    if (len > interior_w) {
        len = interior_w;
    }
    pad = (uint8_t)((interior_w - len) / 2);
    hal_console_locate(row, left);
    hal_console_putc('|');
    for (i = 0; i < pad; i++) {
        hal_console_putc(' ');
    }
    for (i = 0; i < len; i++) {
        hal_console_putc(str[i]);
    }
    for (i = pad + (uint8_t)len; i < interior_w; i++) {
        hal_console_putc(' ');
    }
    hal_console_putc('|');
}

void modal_draw_frame(uint8_t top, uint8_t left,
                      uint8_t width, uint8_t height,
                      const char *title)
{
    uint8_t r, c;

    /* Row 0: Top Border */
    hal_console_locate(top, left);
    hal_console_putc('+');
    for (c = 1; c < width - 1; c++) {
        hal_console_putc('-');
    }
    hal_console_putc('+');

    /* Row 1: Title Row */
    modal_draw_row_centered(top + 1, left, width, title ? title : "");

    /* Row 2: Title Separator Divider (+---+) */
    hal_console_locate(top + 2, left);
    hal_console_putc('+');
    for (c = 1; c < width - 1; c++) {
        hal_console_putc('-');
    }
    hal_console_putc('+');

    /* Rows 3..height-2: Interior Clear */
    for (r = 3; r < height - 1; r++) {
        hal_console_locate(top + r, left);
        hal_console_putc('|');
        for (c = 1; c < width - 1; c++) {
            hal_console_putc(' ');
        }
        hal_console_putc('|');
    }

    /* Row height-1: Bottom Border */
    hal_console_locate(top + height - 1, left);
    hal_console_putc('+');
    for (c = 1; c < width - 1; c++) {
        hal_console_putc('-');
    }
    hal_console_putc('+');
}

int modal_alert(const char *title, const char *msg1, const char *msg2)
{
    uint8_t width = MODAL_BOX_WIDTH;
    uint8_t height = 7;
    uint8_t top = (uint8_t)(((g_active_rows - height) / 2) + 1);
    uint8_t left = (uint8_t)(((g_active_cols - width) / 2) + 1);

    hal_console_hide_cursor();
    modal_draw_frame(top, left, width, height, title);

    if (msg1 && *msg1) {
        modal_draw_row_centered(top + 3, left, width, msg1);
    }
    if (msg2 && *msg2) {
        modal_draw_row_centered(top + 4, left, width, msg2);
    }
    modal_draw_row_centered(top + 5, left, width, "Press any key to continue");

    hal_console_getkey();
    g_need_screen_render = 1;
    return MODAL_RES_OK;
}

int modal_confirm(const char *title, const char *msg,
                  const char *btn1, const char *btn2)
{
    uint8_t width = MODAL_BOX_WIDTH;
    uint8_t height = 7;
    uint8_t top = (uint8_t)(((g_active_rows - height) / 2) + 1);
    uint8_t left = (uint8_t)(((g_active_cols - width) / 2) + 1);
    uint8_t selected = 0;
    (void)btn1;
    (void)btn2;

    hal_console_hide_cursor();
    modal_draw_frame(top, left, width, height, title);

    if (msg && *msg) {
        modal_draw_row_centered(top + 3, left, width, msg);
    }
    modal_draw_row_centered(top + 4, left, width,
                            btn1 ? btn1 : "Save changes?");

    while (1) {
        /* Render Options: [Y]es      [N]o      [ESC]=Cancel */
        hal_console_locate(top + 5, left);
#ifdef __CPM__
        hal_console_puts("|        ");
#else
        hal_console_puts("|         ");
#endif
        if (selected == 0) hal_console_inverse_on();
        hal_console_puts("[Y]es");
        if (selected == 0) hal_console_inverse_off();

        hal_console_puts("      ");
        if (selected == 1) hal_console_inverse_on();
        hal_console_puts("[N]o");
        if (selected == 1) hal_console_inverse_off();

#ifdef __CPM__
        hal_console_puts("      [ESC]=Cancel       |");
#else
        hal_console_puts("      [ESC]=Cancel        |");
#endif

        int k;
        while ((k = hal_console_getkey()) <= 0) {
#ifndef __CPM__
            usleep(5000);
#endif
        }
        if (k == KEY_ENTER || k == ' ') {
            g_need_screen_render = 1;
            return (selected == 0) ? MODAL_RES_YES : MODAL_RES_NO;
        } else if (k == KEY_ESC) {
            /* Cancelable solely by ESC (not Ctrl+C or q) */
            g_need_screen_render = 1;
            return MODAL_RES_CANCEL;
        } else if (k == KEY_TAB || k == KEY_LEFT || k == KEY_RIGHT) {
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
    uint8_t height = 8;
    uint8_t top = (uint8_t)(((g_active_rows - height) / 2) + 1);
    uint8_t left = (uint8_t)(((g_active_cols - width) / 2) + 1);
    uint8_t selected = 0;

    hal_console_hide_cursor();
    modal_draw_frame(top, left, width, height, title);

    if (msg && *msg) {
        modal_puts_centered(top + 3, left, width, msg);
    }
    modal_puts_centered(top + 6, left, width,
                        "[Tab]=Select   [Enter]=Run   [ESC]=Cancel");

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
        } else if (k == KEY_ESC) {
            g_need_screen_render = 1;
            return MODAL_RES_CANCEL;
        } else if (k == KEY_TAB || k == KEY_RIGHT) {
            selected = (selected + 1) % 3;
        } else if (k == KEY_LEFT) {
            selected = (selected + 2) % 3;
        }
    }
}

int modal_prompt_text(const char *title, const char *prompt,
                      char *buffer, size_t max_len)
{
    uint8_t width = MODAL_BOX_WIDTH;
    uint8_t height = 8;
    uint8_t top = (uint8_t)(((g_active_rows - height) / 2) + 1);
    uint8_t left = (uint8_t)(((g_active_cols - width) / 2) + 1);
    uint8_t field_len = 30;
    size_t cur_len = buffer ? strlen(buffer) : 0;
    size_t cursor_pos = cur_len;
    uint8_t input_left;
    size_t i;

    modal_draw_frame(top, left, width, height, title);
    if (prompt && *prompt) {
        modal_puts_centered(top + 3, left, width, prompt);
    }
    modal_puts_centered(top + 6, left, width,
                        "[Enter]=Confirm      [ESC]=Cancel");

    /* Centered Bracket Framing: [ text ] */
    input_left = left + (uint8_t)((width - (field_len + 4)) / 2);

    while (1) {
        hal_console_locate(top + 4, input_left);
        hal_console_puts("[ ");
        hal_console_inverse_on();
        for (i = 0; i < field_len; i++) {
            if (i < cur_len) {
                hal_console_putc(buffer[i]);
            } else {
                hal_console_putc(' ');
            }
        }
        hal_console_inverse_off();
        hal_console_puts(" ]");

        /* Terminal cursor placed directly inside bracket field */
        hal_console_locate(top + 4, (uint8_t)(input_left + 2 + cursor_pos));
        hal_console_show_cursor();

        int k;
        while ((k = hal_console_getkey()) <= 0) {
#ifndef __CPM__
            usleep(5000);
#endif
        }
        if (k == KEY_ENTER) {
            hal_console_hide_cursor();
            g_need_screen_render = 1;
            return MODAL_RES_OK;
        } else if (k == KEY_ESC) {
            hal_console_hide_cursor();
            g_need_screen_render = 1;
            return MODAL_RES_CANCEL;
        } else if (k == KEY_DOWN || k == KEY_UP ||
                   k == KEY_PGDN || k == KEY_CTRL_V ||
                   k == KEY_PGUP || k == KEY_CTRL_U) {
            hal_console_hide_cursor();
            g_need_screen_render = 1;
            return k;
        } else if (k == KEY_LEFT) {
            if (cursor_pos > 0) {
                cursor_pos--;
            }
        } else if (k == KEY_RIGHT) {
            if (cursor_pos < cur_len) {
                cursor_pos++;
            }
        } else if (k == KEY_HOME || k == KEY_CTRL_A) {
            cursor_pos = 0;
        } else if (k == KEY_END || k == KEY_CTRL_E) {
            cursor_pos = cur_len;
        } else if (k == KEY_BACKSPACE || k == 8 || k == 127) {
            if (cursor_pos > 0) {
                memmove(buffer + cursor_pos - 1, buffer + cursor_pos,
                        cur_len - cursor_pos + 1);
                cur_len--;
                cursor_pos--;
                buffer[cur_len] = '\0';
            }
        } else if (k == KEY_DEL || k == KEY_CTRL_D) {
            if (cursor_pos < cur_len) {
                memmove(buffer + cursor_pos, buffer + cursor_pos + 1,
                        cur_len - cursor_pos);
                cur_len--;
                buffer[cur_len] = '\0';
            }
        } else if (k >= 32 && k <= 126 && cur_len + 1 < max_len &&
                   cur_len < field_len) {
            memmove(buffer + cursor_pos + 1, buffer + cursor_pos,
                    cur_len - cursor_pos + 1);
            buffer[cursor_pos] = (char)k;
            cur_len++;
            cursor_pos++;
            buffer[cur_len] = '\0';
        }
    }
}

int modal_confirm_save_changes(void)
{
    int res;

    if (!g_doc_modified) {
        return MODAL_RES_OK;
    }

    res = modal_confirm("Unsaved Modifications",
                        "Any unsaved edits will be lost if discarded.",
                        "Yes", "No");
    if (res == MODAL_RES_YES) {
        file_save(NULL, g_config.save_format);
        return MODAL_RES_OK;
    } else if (res == MODAL_RES_NO) {
        return MODAL_RES_OK;
    }
    return MODAL_RES_CANCEL;
}

int modal_confirm_overwrite(void)
{
    return modal_confirm("Overwrite File",
                         "Existing file contents will be lost",
                         "File already exists. Overwrite?",
                         NULL);
}

void modal_show_notification(const char *title, const char *message)
{
    uint8_t width = 50;
    uint8_t height = 7;
    uint8_t top = (uint8_t)(((g_active_rows - height) / 2) + 1);
    uint8_t left = (uint8_t)(((g_active_cols - width) / 2) + 1);

    hal_console_hide_cursor();
    modal_draw_frame(top, left, width, height, title);

    if (message && *message) {
        modal_draw_row_centered(top + 3, left, width, message);
    }
    modal_draw_row_centered(top + 5, left, width, "Press any key to continue");

    while (hal_console_getkey() <= 0) {
        /* Wait for user keystroke */
    }
    g_need_screen_render = 1;
}

void modal_alert_file_not_found(const char *fname)
{
    uint8_t width = 50;
    uint8_t height = 7;
    uint8_t top = (uint8_t)(((g_active_rows - height) / 2) + 1);
    uint8_t left = (uint8_t)(((g_active_cols - width) / 2) + 1);
    char msg[64];

    snprintf(msg, sizeof(msg), "'%s' was not found.",
             fname ? fname : "FILE");

    hal_console_hide_cursor();
    modal_draw_frame(top, left, width, height, "File Not Found");
    modal_draw_row_centered(top + 3, left, width, msg);
    modal_draw_row_centered(top + 4, left, width,
                            "Specified file not found on disk.");
    modal_draw_row_centered(top + 5, left, width,
                            "Press any key to continue");

    while (hal_console_getkey() <= 0) {
#ifndef __CPM__
        usleep(5000);
#endif
    }
    g_need_screen_render = 1;
}
