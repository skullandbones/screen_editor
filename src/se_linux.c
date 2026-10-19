/*==============================================================================
 * SE_LINUX.C: Top-Level Coordinator - Native Linux Screen Editor Executable
 *
 * Purpose:
 *   Entry point for the standalone native Linux build of SE.
 *   Initializes configuration, POSIX HAL, virtual buffers, and the event loop.
 *   Supports both PC x86_64 and Raspberry Pi 4/5 (AArch64) architectures.
 *
 * Part of SE.COM / Linux Native Profile
 *============================================================================*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "include/config.h"
#include "include/buffer.h"
#include "include/editor.h"
#include "include/ui.h"
#include "include/file_io.h"
#include "include/hal.h"

int main(int argc, char **argv)
{
    const char *target_file = NULL;

    if (argc > 1) {
        if (strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0) {
            printf("Usage: %s [filename]\n", argv[0]);
            printf("SE Screen Editor - Linux Native Profile (v1.1.4)\n");
            return 0;
        }
        target_file = argv[1];
    }

    config_init_defaults();
    config_load_file("SE.CFG");

    buffer_init();
    ui_init();
    editor_init();

    if (target_file) {
        char clean_name[256];
        FILE *tf;
        resolve_linux_path(target_file, clean_name, sizeof(clean_name), NULL);
        tf = fopen(clean_name, "rb");
        if (tf) {
            fclose(tf);
            file_load(target_file);
        } else {
            /* Create new document under this name */
            init_empty_document();
            strncpy(g_current_filename, clean_name,
                    sizeof(g_current_filename) - 1);
            g_current_filename[sizeof(g_current_filename) - 1] = '\0';
        }
    } else {
        show_splash_screen();
    }

    editor_main_loop();

    /* Clean exit: Clear screen via TERM_INIT and emit canonical exit banner */
    hal_console_puts("\033[0m\033[?25h\033[2J\033[H");
    hal_console_puts("\r\nExiting SE. Returned to OS prompt.\r\n");
    hal_console_show_cursor();
    return 0;
}
