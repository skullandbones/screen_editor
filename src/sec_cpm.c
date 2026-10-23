/*==============================================================================
 * SEC_CPM.C: Top-Level Coordinator - CP/M Screen Editor Executable (SEC.COM)
 *
 * Purpose:
 *   Entry point for the C semantic equivalent CP/M build (SEC.COM).
 *   Initializes configuration, CP/M HAL, virtual buffers, and the event loop.
 *   Provides complete black-box parity with SE.COM on CP/M systems.
 *
 * Part of SE.COM / CP/M C Semantic Equivalent Profile (v1.1.5)
 *============================================================================*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "include/config.h"
#include "include/buffer.h"
#include "include/editor.h"
#include "include/ui.h"
#include "include/search.h"
#include "include/file_io.h"
#include "include/plugin.h"
#include "include/hal.h"

static int parse_target_filename(char *out_buf, size_t max_len)
{
    uint8_t cpm_cmd_len = *(const uint8_t *)CMD_LEN;
    const char *tail;
    uint8_t i = 0;
    uint8_t out_idx = 0;

    out_buf[0] = '\0';
    if (cpm_cmd_len == 0) {
        return 0;
    }

    tail = (const char *)CMD_TAIL;
    while (i < cpm_cmd_len && tail[i] == ' ') {
        i++;
    }
    while (i < cpm_cmd_len && tail[i] > ' ' &&
           out_idx + 1 < max_len) {
        out_buf[out_idx++] = tail[i++];
    }
    out_buf[out_idx] = '\0';

    return (out_idx > 0) ? 1 : 0;
}

int main(int argc, char **argv)
{
    char *target_file = g_search_buf;
    int has_target = parse_target_filename(target_file, sizeof(g_search_buf));
    (void)argc;
    (void)argv;



    config_init_defaults();
    config_load_file("SE.CFG");

    buffer_init();
    ui_init();
    editor_init();
    plugin_init_registry();
    plugin_autoload_mgr();

    if (has_target) {
        uint8_t fat_u = 0xFF;
        const char *fat_p = cpm_parse_fat_path(target_file, &fat_u);
        if (fat_p != NULL) {
            if (plugin_ensure_vfs() < 0) {
                hal_console_puts("\r\nFATFS.PRL file not found\r\n");
                goto clean_exit_sp;
            }
        }
        if (file_load(target_file) != 0) {
            uint8_t drv = 0, usr = 0xFF;
            if (fat_p != NULL ||
                cpm_parse_prefix(target_file, &drv, &usr) > target_file) {
                const char *fn = target_file;
                if (fat_p == NULL) {
                    cpm_format_doc_filename(&g_cpm_fcb, g_target_user);
                    fn = g_current_filename;
                }
                hal_console_puts("\r\n");
                hal_console_puts(fn);
                hal_console_puts(" file not found\r\n");
                goto clean_exit_sp;
            }
            /* Create new document under this name */
            drv = g_cpm_fcb.drive;
            usr = g_target_user;
            init_empty_document();
            g_doc_drive = drv;
            g_doc_user = usr;
            cpm_format_doc_filename(&g_cpm_fcb, g_doc_user);
        }
    } else {
        show_splash_screen();
    }

    g_search_buf[0] = '\0';
    editor_main_loop();

    /* Clean exit: Clear screen and restore terminal */
    hal_console_clear();
    hal_console_locate(1, 1);
    hal_console_show_cursor();
    hal_console_puts("\r\nExiting SE.COM. Returned to CP/M.\r\n");
clean_exit_sp:
#asm
    extern __restore_sp_onexit
    ld sp, (__restore_sp_onexit + 1)
    ret
#endasm
    return 0;
}
