/*==============================================================================
 * CONFIG.C: Core Subsystem - Global Configuration & SE.CFG File Parser
 *
 * Purpose:
 *   Implements configuration defaults initialization, persistent SE.CFG
 *   parameter parsing, and configuration serialization to storage.
 *   C semantic equivalent to src/core/config.asm.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "../include/config.h"

/* Global Configuration Instance */
editor_config_t g_config;

void config_init_defaults(void)
{
    g_config.tab_width = 8;
    g_config.lines_mode = 0;             /* 16K lines */
    g_config.screen_mode = MODE_80X24;   /* Classic 80x24 */
    g_config.ramdrive_mode = RAMDRV_MODE_PROTECTED;
    g_config.plugin_mode = PLUGIN_MODE_AUTOLOAD;
    g_config.save_format = FMT_CPM;
    g_config.auto_indent = 1;
    g_config.show_line_endings = 0;
}

int config_load_file(const char *filename)
{
    FILE *fp;
    char line[128];

    config_init_defaults();

    if (!filename) {
        filename = "SE.CFG";
    }

    fp = fopen(filename, "r");
    if (!fp) {
        return -1;
    }

    while (fgets(line, sizeof(line), fp)) {
        char *eq = strchr(line, '=');
        if (!eq) continue;
        *eq = '\0';
        char *key = line;
        char *val = eq + 1;

        /* Strip trailing newlines */
        char *nl = strchr(val, '\r');
        if (nl) *nl = '\0';
        nl = strchr(val, '\n');
        if (nl) *nl = '\0';

        if (strcmp(key, "TAB_WIDTH") == 0) {
            g_config.tab_width = (uint8_t)atoi(val);
        } else if (strcmp(key, "LINES_MODE") == 0) {
            g_config.lines_mode = (uint8_t)atoi(val);
        } else if (strcmp(key, "SCREEN_MODE") == 0) {
            if (strcmp(val, "120X40") == 0) {
                g_config.screen_mode = MODE_120X40;
            } else {
                g_config.screen_mode = MODE_80X24;
            }
        } else if (strcmp(key, "RAMDRIVE") == 0) {
            g_config.ramdrive_mode = (uint8_t)atoi(val);
        } else if (strcmp(key, "PLUGIN_MODE") == 0) {
            g_config.plugin_mode = (uint8_t)atoi(val);
        } else if (strcmp(key, "SAVE_FMT") == 0) {
            if (strcmp(val, "LINUX") == 0) {
                g_config.save_format = FMT_LINUX;
            } else {
                g_config.save_format = FMT_CPM;
            }
        } else if (strcmp(key, "AUTO_INDENT") == 0) {
            g_config.auto_indent = (uint8_t)atoi(val);
        }
    }

    fclose(fp);
    return 0;
}

int config_save_file(const char *filename)
{
    FILE *fp;

    if (!filename) {
        filename = "SE.CFG";
    }

    fp = fopen(filename, "w");
    if (!fp) {
        return -1;
    }

    fprintf(fp, "# SE.COM Configuration File\n");
    fprintf(fp, "TAB_WIDTH=%u\n", (unsigned)g_config.tab_width);
    fprintf(fp, "LINES_MODE=%u\n", (unsigned)g_config.lines_mode);
    fprintf(fp, "SCREEN_MODE=%s\n",
            g_config.screen_mode == MODE_120X40 ? "120X40" : "80X24");
    fprintf(fp, "RAMDRIVE=%u\n", (unsigned)g_config.ramdrive_mode);
    fprintf(fp, "PLUGIN_MODE=%u\n", (unsigned)g_config.plugin_mode);
    fprintf(fp, "SAVE_FMT=%s\n",
            g_config.save_format == FMT_LINUX ? "LINUX" : "CPM");
    fprintf(fp, "AUTO_INDENT=%u\n", (unsigned)g_config.auto_indent);

    fclose(fp);
    return 0;
}
