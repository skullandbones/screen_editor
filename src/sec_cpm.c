/*==============================================================================
 * SEC_CPM.C: Top-Level Coordinator - CP/M Screen Editor Executable (SEC.COM)
 *
 * Purpose:
 *   Entry point for the C semantic equivalent CP/M build (SEC.COM).
 *   Initializes configuration, CP/M HAL, virtual buffers, and the event loop.
 *   Provides complete black-box parity with SE.COM on CP/M systems.
 *
 * Part of SE.COM / CP/M C Semantic Equivalent Profile
 *============================================================================*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "include/config.h"
#include "include/buffer.h"
#include "include/editor.h"
#include "include/ui.h"
#include "include/file_io.h"
#include "include/hal.h"

static int parse_target_filename(char *out_buf, size_t max_len,
                                 int argc, char **argv)
{
    uint8_t cpm_cmd_len;
    const char *tail;
    uint8_t i = 0;
    uint8_t out_idx = 0;

    out_buf[0] = '\0';
    if (argc > 1 && argv[1][0] != '\0') {
        strncpy(out_buf, argv[1], max_len - 1);
        out_buf[max_len - 1] = '\0';
        return 1;
    }

    cpm_cmd_len = *(const uint8_t *)CMD_LEN;
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
    static char target_file[32];
    int has_target = parse_target_filename(target_file, sizeof(target_file),
                                           argc, argv);

    if (has_target) {
        if (strcmp(target_file, "-h") == 0 ||
            strcmp(target_file, "--help") == 0) {
            hal_console_puts("Usage: SEC [filename]\r\n");
            hal_console_puts("SE Screen Editor - CP/M C Profile (v1.1.4)\r\n");
            return 0;
        }
    }

    config_init_defaults();
    config_load_file("SE.CFG");

    buffer_init();
    ui_init();
    editor_init();

    if (has_target) {
        if (file_load(target_file) != 0) {
            uint8_t drv = 0, usr = 0xFF;
            if (cpm_parse_prefix(target_file, &drv, &usr) > target_file) {
                cpm_format_doc_filename(&g_cpm_fcb, g_target_user);
                hal_console_puts("\r\n");
                hal_console_puts(g_current_filename);
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
