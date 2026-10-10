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

static char s_cpm_cmd_buf[64];

static const char *parse_target_filename(int argc, char **argv)
{
    uint8_t cpm_cmd_len;
    const char *tail;
    uint8_t i = 0;
    uint8_t out_idx = 0;

    if (argc > 1 && argv[1][0] != '\0') {
        return argv[1];
    }

    cpm_cmd_len = *(const uint8_t *)CMD_LEN;
    if (cpm_cmd_len == 0) {
        return NULL;
    }

    tail = (const char *)CMD_TAIL;
    while (i < cpm_cmd_len && tail[i] == ' ') {
        i++;
    }
    while (i < cpm_cmd_len && tail[i] > ' ' &&
           out_idx + 1 < sizeof(s_cpm_cmd_buf)) {
        s_cpm_cmd_buf[out_idx++] = tail[i++];
    }
    s_cpm_cmd_buf[out_idx] = '\0';

    return (out_idx > 0) ? s_cpm_cmd_buf : NULL;
}

int main(int argc, char **argv)
{
    const char *target_file = parse_target_filename(argc, argv);

    if (target_file) {
        if (strcmp(target_file, "-h") == 0 ||
            strcmp(target_file, "--help") == 0) {
            printf("Usage: SEC [filename]\n");
            printf("SE Screen Editor - CP/M C Profile (v1.1.0)\n");
            return 0;
        }
    }

    config_init_defaults();
    config_load_file("SE.CFG");

    buffer_init();
    ui_init();
    editor_init();

    if (target_file && target_file[0] != '\0') {
        if (file_load(target_file) != 0) {
            /* Create new document under this name */
            init_empty_document();
            strncpy(g_current_filename, target_file,
                    sizeof(g_current_filename) - 1);
            g_current_filename[sizeof(g_current_filename) - 1] = '\0';
        }
    } else {
        show_splash_screen();
    }

    editor_main_loop();

    /* Clean exit: Clear screen and restore terminal */
    hal_console_clear();
    hal_console_locate(1, 1);
    hal_console_show_cursor();
    return 0;
}
