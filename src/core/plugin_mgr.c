/*==============================================================================
 * PLUGIN_MGR.C: Core Subsystem - Far RAM Plugin Manager & Host API Bridge
 *
 * Purpose:
 *   Implements the plugin registry table, dynamic PRL/OVL slot allocation,
 *   Host API vector registration, and Plugin Manager user interface.
 *   C semantic equivalent to src/core/plugin_mgr.asm.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#include <string.h>
#include <stdio.h>
#include "../include/config.h"
#include "../include/buffer.h"
#include "../include/ui.h"
#include "../include/ui_modal.h"
#include "../include/plugin.h"
#include "../include/editor.h"
#include "../include/beautify.h"
#include "../include/hal.h"

static plugin_entry_t s_plugin_registry[PLUGIN_MAX_SLOTS];
static uint8_t        s_plugin_count = 0;

void plugin_init_registry(void)
{
    memset(s_plugin_registry, 0, sizeof(s_plugin_registry));
    s_plugin_count = 0;
}

const plugin_entry_t *plugin_get_entry(uint8_t slot)
{
    if (slot < PLUGIN_MAX_SLOTS && s_plugin_registry[slot].active) {
        return &s_plugin_registry[slot];
    }
    return NULL;
}

int plugin_load_by_name(const char *filename)
{
    uint8_t slot;

    if (!filename || filename[0] == '\0') {
        return -1;
    }

    for (slot = 0; slot < PLUGIN_MAX_SLOTS; slot++) {
        if (!s_plugin_registry[slot].active) {
            strncpy(s_plugin_registry[slot].name, filename, 8);
            s_plugin_registry[slot].slot_id = slot;
            s_plugin_registry[slot].active = 1;
            s_plugin_registry[slot].capabilities = CAP_FAR_EXEC |
                                                   CAP_DOC_MUTATE;
            s_plugin_count++;
            return slot;
        }
    }
    return -1;
}

void plugin_unload_slot(uint8_t slot)
{
    if (slot < PLUGIN_MAX_SLOTS && s_plugin_registry[slot].active) {
        s_plugin_registry[slot].active = 0;
        if (s_plugin_count > 0) {
            s_plugin_count--;
        }
    }
}

int plugin_exec_slot(uint8_t slot, uint8_t action)
{
    if (slot >= PLUGIN_MAX_SLOTS || !s_plugin_registry[slot].active) {
        return -1;
    }
    (void)action;
    /* Dispatch action to plugin */
    return 0;
}

void plugin_manager_ui(void)
{
    uint8_t width = 60;
    uint8_t height = 16;
    uint8_t top = (uint8_t)(((g_active_rows - height) / 2) + 1);
    uint8_t left = (uint8_t)(((g_active_cols - width) / 2) + 1);
    uint8_t i;

    hal_console_hide_cursor();
    modal_draw_frame(top, left, width, height, "Plugin Manager");

    modal_draw_row_left(top + 3, left, width,
                        "   Slot  Name      Status      Capabilities");

    for (i = 0; i < PLUGIN_MAX_SLOTS; i++) {
        char buf[64];
        if (s_plugin_registry[i].active) {
            snprintf(buf, sizeof(buf),
                     "   [%u]   %-8.8s  Active      Far RAM Exec",
                     (unsigned)i, s_plugin_registry[i].name);
        } else {
            snprintf(buf, sizeof(buf), "   [%u]   --------  (empty)     ---",
                     (unsigned)i);
        }
        modal_draw_row_left(top + 4 + i, left, width, buf);
    }

    modal_draw_row_centered(top + 13, left, width,
                            "[Q]/[ESC]=Return");
    while (1) {
        int k = hal_console_getkey();
        if (k == KEY_ESC || k == 'q' || k == 'Q') {
            break;
        }
    }
    g_need_screen_render = 1;
}

static void exec_rot13(void)
{
    uint16_t i;
    for (i = 0; i < g_active_line_len; i++) {
        char c = g_active_line_buf[i];
        if (c >= 'a' && c <= 'z') {
            g_active_line_buf[i] = (char)('a' + (c - 'a' + 13) % 26);
        } else if (c >= 'A' && c <= 'Z') {
            g_active_line_buf[i] = (char)('A' + (c - 'A' + 13) % 26);
        }
    }
    g_doc_modified = 1;
}

static void exec_wordcnt(void)
{
    uint16_t r;
    uint16_t words = 0;
    uint16_t chars = 0;
    char *lbuf = g_scratch_line_buf;
    char msg1[48];
    char msg2[48];

    commit_active_line();
    for (r = 0; r < g_doc_total_lines; r++) {
        uint16_t len = fetch_line_to_buffer(r, lbuf, MAX_ACTIVE_PAYLOAD);
        const char *p = lbuf;
        int in_word = 0;
        chars += len;
        while (*p) {
            if ((unsigned char)*p > ' ') {
                if (!in_word) {
                    words++;
                    in_word = 1;
                }
            } else {
                in_word = 0;
            }
            p++;
        }
    }
    snprintf(msg1, sizeof(msg1), "Lines: %u    Words: %u",
             (unsigned)g_doc_total_lines, (unsigned)words);
    snprintf(msg2, sizeof(msg2), "Characters: %u", (unsigned)chars);
    modal_alert("Word Count", msg1, msg2);
}

typedef struct {
    const char *name;
    const char *desc;
} palette_item_t;

static const palette_item_t s_palette_items[3] = {
    {"ROT13", "Rotate letters by 13"},
    {"WORDCNT", "Document word, line, count"},
    {"BEAUTIFY", "Align Z80 assembly labels"}
};

void show_plugin_palette(void)
{
    uint8_t num_items = 3;
    uint8_t selected = 0;
    uint8_t width = 50;
    uint8_t height = 9;
    uint8_t top, left;
    uint8_t i;

    top = (uint8_t)(((g_active_rows - height) / 2) + 1);
    left = (uint8_t)(((g_active_cols - width) / 2) + 1);

    hal_console_hide_cursor();

    while (1) {
        modal_draw_frame(top, left, width, height, "Plugin Palette");
        modal_draw_row_centered(top + 3, left, width,
                                "Select a plugin to execute:");

        for (i = 0; i < num_items; i++) {
            char line_buf[60];
            snprintf(line_buf, sizeof(line_buf), "  %s%u. %-8s - %s",
                     (i == selected) ? "> " : "  ",
                     (unsigned)(i + 1),
                     s_palette_items[i].name,
                     s_palette_items[i].desc);
            modal_draw_row_left(top + 4 + i, left, width, line_buf);
        }

        modal_draw_row_centered(top + 4 + num_items, left, width,
            "[Up/Down]=Select   [Enter]=Run   [ESC]=Cancel");

        int k;
        while ((k = hal_console_getkey()) <= 0) {
            /* Wait for key */
        }

        if (k == KEY_ESC) {
            break;
        }
        if (k >= '1' && k <= '3') {
            selected = (uint8_t)(k - '1');
            k = KEY_ENTER;
        }
        if (k == KEY_ENTER || k == '\r' || k == '\n') {
            clear_screen();
            g_need_screen_render = 1;
            if (selected == 0) {
                exec_rot13();
            } else if (selected == 1) {
                exec_wordcnt();
            } else if (selected == 2) {
                do_ctrl_y_beautify();
            }
            break;
        }
        if (k == KEY_UP) {
            selected = (selected == 0) ? (num_items - 1) : (selected - 1);
        } else if (k == KEY_DOWN) {
            selected = (selected + 1) % num_items;
        }
    }

    clear_screen();
    g_need_screen_render = 1;
}
