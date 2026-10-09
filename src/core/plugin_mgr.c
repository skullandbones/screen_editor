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
    uint8_t top = (g_active_rows > height) ? (g_active_rows - height) / 2 : 4;
    uint8_t left = (g_active_cols > width) ? (g_active_cols - width) / 2 : 10;
    uint8_t i;

    hal_console_hide_cursor();
    modal_draw_frame(top, left, width, height, "Plugin Manager");

    hal_console_locate(top + 2, left + 4);
    hal_console_puts("Slot  Name      Status      Capabilities");

    for (i = 0; i < PLUGIN_MAX_SLOTS; i++) {
        char buf[64];
        if (s_plugin_registry[i].active) {
            snprintf(buf, sizeof(buf), "[%u]   %-8s  Active      Far RAM Exec",
                     (unsigned)i, s_plugin_registry[i].name);
        } else {
            snprintf(buf, sizeof(buf), "[%u]   --------  (empty)     ---",
                     (unsigned)i);
        }
        hal_console_locate(top + 4 + i, left + 4);
        hal_console_puts(buf);
    }

    hal_console_locate(top + 13, left + 4);
    hal_console_puts("Press Esc or Q to return to editor...");
    while (1) {
        int k = hal_console_getkey();
        if (k == KEY_ESC || k == 'q' || k == 'Q') {
            break;
        }
    }
    g_need_screen_render = 1;
}
