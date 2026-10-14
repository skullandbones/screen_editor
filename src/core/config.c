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
#include <strings.h>
#include "../include/config.h"

/* Global Configuration Instance */
editor_config_t g_config;
uint8_t         g_config_loaded = 0;

static char *trim_whitespace(char *str)
{
    char *end;
    while (*str == ' ' || *str == '\t' || *str == '\r' || *str == '\n') {
        str++;
    }
    if (*str == '\0') {
        return str;
    }
    end = str + strlen(str) - 1;
    while (end > str &&
           (*end == ' ' || *end == '\t' || *end == '\r' || *end == '\n')) {
        *end = '\0';
        end--;
    }
    return str;
}

void config_init_defaults(void)
{
    g_config_loaded = 0;
    g_config.tab_width = 4;
    g_config.lines_mode = 0;             /* 16K lines */
    g_config.screen_mode = MODE_80X24;  /* Canonical 80x24 (Section 13.2) */
    g_config.ramdrive_mode = RAMDRV_MODE_PROTECTED;
    g_config.plugin_mode = PLUGIN_MODE_AUTOLOAD;
#ifdef __CPM__
    g_config.save_format = FMT_CPM;
#else
    g_config.save_format = FMT_LINUX;
#endif
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
        char *eq;
        char *key;
        char *val;
        char *p = line;

        /* Skip leading whitespace */
        while (*p == ' ' || *p == '\t') p++;

        /* Ignore comments (# or ;) and blank lines */
        if (*p == '#' || *p == ';' || *p == '\r' || *p == '\n' ||
            *p == '\0') {
            continue;
        }

        eq = strchr(p, '=');
        if (!eq) {
            continue;
        }

        *eq = '\0';
        key = trim_whitespace(p);
        val = trim_whitespace(eq + 1);

        if (strcasecmp(key, "SCREEN") == 0 ||
            strcasecmp(key, "SCREEN_MODE") == 0) {
            if (strcasecmp(val, "80X24") == 0 || strcasecmp(val, "1") == 0) {
                g_config.screen_mode = MODE_80X24;
            } else if (strcasecmp(val, "120X40") == 0 ||
                       strcasecmp(val, "0") == 0) {
                g_config.screen_mode = MODE_120X40;
            } else if (strcasecmp(val, "NATIVE") == 0 ||
                       strcasecmp(val, "2") == 0) {
                g_config.screen_mode = MODE_NATIVE;
            }
        } else if (strcasecmp(key, "TAB") == 0 ||
                   strcasecmp(key, "TABS") == 0 ||
                   strcasecmp(key, "TAB_WIDTH") == 0) {
            int w = atoi(val);
            if (w == 4 || w == 8) {
                g_config.tab_width = (uint8_t)w;
            }
        } else if (strcasecmp(key, "LINES") == 0 ||
                   strcasecmp(key, "MAXLINES") == 0 ||
                   strcasecmp(key, "LINES_MODE") == 0) {
            if (strcasecmp(val, "32K") == 0 || strcmp(val, "1") == 0) {
                g_config.lines_mode = 1;
            } else if (strcasecmp(val, "16K") == 0 || strcmp(val, "0") == 0) {
                g_config.lines_mode = 0;
            }
        } else if (strcasecmp(key, "RAMDRIVE") == 0 ||
                   strcasecmp(key, "RAMDISK") == 0) {
            if (strcasecmp(val, "PRESERVE") == 0 || strcmp(val, "0") == 0) {
                g_config.ramdrive_mode = RAMDRV_MODE_PROTECTED;
            } else if (strcasecmp(val, "ON") == 0 || strcmp(val, "1") == 0) {
                g_config.ramdrive_mode = RAMDRV_MODE_ENABLED;
            } else if (strcasecmp(val, "HIB") == 0 ||
                       strcasecmp(val, "HIBERNATE") == 0 ||
                       strcmp(val, "2") == 0) {
                g_config.ramdrive_mode = RAMDRV_MODE_HIBERNATE;
            } else if (strcasecmp(val, "OFF") == 0 ||
                       strcasecmp(val, "DISABLED") == 0) {
                g_config.ramdrive_mode = RAMDRV_MODE_PROTECTED;
            }
        } else if (strcasecmp(key, "PLUGIN") == 0 ||
                   strcasecmp(key, "PLUGINS") == 0 ||
                   strcasecmp(key, "PLUGIN_MODE") == 0) {
            if (strcasecmp(val, "AUTO") == 0 ||
                strcasecmp(val, "AUTOLOAD") == 0 ||
                strcmp(val, "1") == 0) {
                g_config.plugin_mode = PLUGIN_MODE_AUTOLOAD;
            } else if (strcasecmp(val, "DEMAND") == 0 ||
                       strcasecmp(val, "ONDEMAND") == 0 ||
                       strcmp(val, "2") == 0) {
                g_config.plugin_mode = PLUGIN_MODE_ONDEMAND;
            } else if (strcasecmp(val, "OFF") == 0 ||
                       strcasecmp(val, "DISABLED") == 0 ||
                       strcmp(val, "0") == 0) {
                g_config.plugin_mode = PLUGIN_MODE_DISABLED;
            }
        } else if (strcasecmp(key, "AUTO_INDENT") == 0) {
            if (strcasecmp(val, "OFF") == 0 || strcasecmp(val, "NO") == 0 ||
                strcmp(val, "0") == 0) {
                g_config.auto_indent = 0;
            } else {
                g_config.auto_indent = 1;
            }
        }
    }

    fclose(fp);
    g_config_loaded = 1;
    return 0;
}

int config_save_file(const char *filename)
{
    FILE *fp;
    const char *ramdrv_str;
    const char *plugin_str;

    if (!filename) {
        filename = "SE.CFG";
    }

    fp = fopen(filename, "wb");
    if (!fp) {
        return -1;
    }

    if (g_config.ramdrive_mode == RAMDRV_MODE_ENABLED) {
        ramdrv_str = "ON";
    } else if (g_config.ramdrive_mode == RAMDRV_MODE_HIBERNATE) {
        ramdrv_str = "HIB";
    } else {
        ramdrv_str = "PRESERVE";
    }

    if (g_config.plugin_mode == PLUGIN_MODE_ONDEMAND) {
        plugin_str = "DEMAND";
    } else if (g_config.plugin_mode == PLUGIN_MODE_DISABLED) {
        plugin_str = "OFF";
    } else {
        plugin_str = "AUTOLOAD";
    }

    fprintf(fp, "# SE.COM Configuration File\r\n");
    fprintf(fp, "SCREEN=%s\r\n",
            (g_config.screen_mode == MODE_NATIVE) ? "NATIVE" :
            ((g_config.screen_mode == MODE_120X40) ? "120X40" : "80X24"));
    fprintf(fp, "TAB=%u\r\n", (unsigned)g_config.tab_width);
    fprintf(fp, "LINES=%s\r\n",
            (g_config.lines_mode == 1) ? "32K" : "16K");
    fprintf(fp, "RAMDRIVE=%s\r\n", ramdrv_str);
    fprintf(fp, "PLUGIN=%s\r\n", plugin_str);
    fprintf(fp, "AUTO_INDENT=%u\r\n", (unsigned)g_config.auto_indent);

    fclose(fp);
    g_config_loaded = 1;
    return 0;
}

int config_save(void)
{
    return config_save_file("SE.CFG");
}
