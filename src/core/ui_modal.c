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
#include "../include/editor.h"
#include "../include/ui.h"
#include "../include/ui_modal.h"
#include "../include/ui_browser.h"
#include "../include/file_io.h"
#include "../include/hal.h"
#ifndef __CPM__
#include <unistd.h>
#endif

#define MODAL_BOX_WIDTH   50

#ifndef __CPM__
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
#endif

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

#ifndef __CPM__
void modal_draw_row_left(uint8_t row, uint8_t left,
                         uint8_t width, const char *str)
{
    size_t len = str ? strlen(str) : 0;
    uint8_t interior_w = (width > 2) ? (width - 2) : 0;
    size_t i;

    if (len > interior_w) {
        len = interior_w;
    }
    hal_console_locate(row, left);
    hal_console_putc('|');
    for (i = 0; i < len; i++) {
        hal_console_putc(str[i]);
    }
    for (i = len; i < interior_w; i++) {
        hal_console_putc(' ');
    }
    hal_console_putc('|');
}
#endif

static void draw_horiz_border(uint8_t row, uint8_t left, uint8_t width)
{
    uint8_t c;
    hal_console_locate(row, left);
    hal_console_putc('+');
    for (c = 1; c < width - 1; c++) {
        hal_console_putc('-');
    }
    hal_console_putc('+');
}

void modal_draw_frame(uint8_t top, uint8_t left,
                      uint8_t width, uint8_t height,
                      const char *title)
{
    uint8_t r;

    draw_horiz_border(top, left, width);
    modal_draw_row_centered(top + 1, left, width, title ? title : "");
    draw_horiz_border(top + 2, left, width);
    for (r = 3; r < height - 1; r++) {
        modal_draw_row_centered(top + r, left, width, "");
    }
    draw_horiz_border(top + height - 1, left, width);
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

    {
        int k;
        while ((k = hal_console_getkey()) <= 0) {
#ifndef __CPM__
            usleep(5000);
#endif
        }
        if (k == KEY_ESC) {
#ifndef __CPM__
            while (hal_console_getkey() > 0) {
                /* Drain trailing escape sequence bytes */
            }
#endif
        }
    }
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

    hal_console_hide_cursor();
    modal_draw_frame(top, left, width, height, title);

    if (msg && *msg) {
        modal_draw_row_centered(top + 3, left, width, msg);
    }
    modal_draw_row_centered(top + 4, left, width,
                            btn1 ? btn1 : "Save changes?");
    modal_draw_row_centered(top + 5, left, width,
                            "[Y]es      [N]o      [ESC]=Cancel");

    if (btn2) {
        hal_console_locate(top + 4, (uint8_t)(left + 40));
        hal_console_show_cursor();
    }

    while (1) {
        int k;
        while ((k = hal_console_getkey()) <= 0) {
#ifndef __CPM__
            usleep(5000);
#endif
        }
        if (k == KEY_ESC) {
            /* Cancelable solely by ESC (not Ctrl+C or q) */
#ifndef __CPM__
            while (hal_console_getkey() > 0) {
                /* Drain trailing escape sequence bytes */
            }
#endif
            hal_console_hide_cursor();
            g_need_screen_render = 1;
            return MODAL_RES_CANCEL;
        } else if (k == 'y' || k == 'Y' || k == KEY_ENTER) {
            hal_console_hide_cursor();
            g_need_screen_render = 1;
            return MODAL_RES_YES;
        } else if (k == 'n' || k == 'N') {
            hal_console_hide_cursor();
            g_need_screen_render = 1;
            return MODAL_RES_NO;
        }
    }
}

#ifndef __CPM__
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
#endif

#ifndef __CPM__
int modal_prompt_text(const char *title, const char *prompt,
                      char *buffer, size_t max_len)
{
    uint8_t width = MODAL_BOX_WIDTH;
    uint8_t height = 7;
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
    modal_puts_centered(top + 5, left, width,
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
            usleep(5000);
        }
        if (k == KEY_ENTER) {
            hal_console_hide_cursor();
            g_need_screen_render = 1;
            return MODAL_RES_OK;
        } else if (k == KEY_ESC) {
            hal_console_hide_cursor();
            g_need_screen_render = 1;
            return MODAL_RES_CANCEL;
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
#endif

int modal_goto_line(char *buffer, size_t max_len)
{
    uint8_t width = 50;
    uint8_t height = 7;
    uint8_t top = (uint8_t)(((g_active_rows - height) / 2) + 1);
    uint8_t left = (uint8_t)(((g_active_cols - width) / 2) + 1);
    size_t len = 0;
    int k;

    if (!buffer || max_len < 2) {
        return MODAL_RES_CANCEL;
    }
    buffer[0] = '\0';

    hal_console_hide_cursor();
    modal_draw_frame(top, left, width, height, "Goto Line");
    modal_draw_row_centered(top + 3, left, width,
                            "Enter line number to jump to");
    modal_draw_row_centered(top + 4, left, width,
                            "Goto line: [     ]");
    modal_draw_row_centered(top + 5, left, width,
                            "[Enter]=Goto Line     [ESC]=Cancel");

    /* Position cursor at first digit inside brackets: left + 28 */
    hal_console_locate(top + 4, (uint8_t)(left + 28));
    hal_console_show_cursor();

    while (1) {
        k = hal_console_getkey();
        if (k <= 0) {
            continue;
        }

        if (k == KEY_ENTER) {
            hal_console_hide_cursor();
            g_need_screen_render = 1;
            if (len == 0) {
                return MODAL_RES_CANCEL;
            }
            return MODAL_RES_OK;
        } else if (k == KEY_ESC) {
#ifndef __CPM__
            while (hal_console_getkey() > 0) {
                /* Drain trailing escape sequence bytes */
            }
#endif
            hal_console_hide_cursor();
            g_need_screen_render = 1;
            return MODAL_RES_CANCEL;
        } else if (k == KEY_BACKSPACE || k == 8 || k == 127) {
            if (len > 0) {
                len--;
                buffer[len] = '\0';
                hal_console_puts("\x08 \x08");
            }
        } else if (k >= '0' && k <= '9') {
            if (len < 5 && len + 1 < max_len) {
                buffer[len] = (char)k;
                len++;
                buffer[len] = '\0';
                hal_console_putc((char)k);
            }
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
                        "Save changes?", NULL);
    if (res == MODAL_RES_YES) {
        if (!g_current_filename[0]) {
#ifdef __CPM__
            extern char g_editor_fname[24];
#define dlg_fname g_editor_fname
#else
            char dlg_fname[32];
#endif
            dlg_fname[0] = '\0';
            if (ui_browser_save_dialog(dlg_fname, 24) !=
                MODAL_RES_OK || !dlg_fname[0]) {
                return MODAL_RES_CANCEL;
            }
            if (file_save(dlg_fname, g_file_format) != 0) {
                return MODAL_RES_CANCEL;
            }
        } else {
            if (file_save(NULL, g_file_format) != 0) {
                return MODAL_RES_CANCEL;
            }
        }
        return MODAL_RES_OK;
    } else if (res == MODAL_RES_NO) {
        init_empty_document();
        g_current_filename[0] = '\0';
        return MODAL_RES_OK;
    }
    return MODAL_RES_CANCEL;
}

int modal_confirm_overwrite(void)
{
    int res = modal_confirm("Overwrite File",
                            "Existing file contents will be lost",
                            "File already exists. Overwrite?",
                            (const char *)1);
    return (res == MODAL_RES_YES) ? MODAL_RES_OK : res;
}

#ifndef __CPM__
void modal_show_notification(const char *title, const char *message)
{
    modal_alert(title, message, NULL);
}
#endif

void modal_alert_file_not_found(const char *fname)
{
    char msg[48];

    msg[0] = '\'';
    strncpy(msg + 1, fname ? fname : "FILE", 26);
    msg[27] = '\0';
    strcat(msg, "' was not found.");
    modal_alert("File Not Found", msg,
                "Specified file not found on disk.");
}
