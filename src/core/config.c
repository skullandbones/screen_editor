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

static const editor_config_t s_default_config = {
    8, 0, MODE_80X24, RAMDRV_MODE_PROTECTED, PLUGIN_MODE_AUTOLOAD,
#ifdef __CPM__
    FMT_CPM,
#else
    FMT_LINUX,
#endif
    1, 0
};

void config_init_defaults(void)
{
    g_config_loaded = 0;
    memcpy(&g_config, &s_default_config, sizeof(editor_config_t));
}

static void parse_config_line(char *line)
{
    char *eq;
    char *key;
    char *val;
    char *p = line;

    while (*p == ' ' || *p == '\t') p++;
    if (*p == '#' || *p == ';' || *p == '\r' || *p == '\n' || *p == '\0') {
        return;
    }

    eq = strchr(p, '=');
    if (!eq) {
        return;
    }

    *eq = '\0';
    key = trim_whitespace(p);
    val = trim_whitespace(eq + 1);
#ifdef __CPM__
    for (p = key; *p; p++) {
        if (*p >= 'a' && *p <= 'z') *p = (char)(*p - 32);
    }
    for (p = val; *p; p++) {
        if (*p >= 'a' && *p <= 'z') *p = (char)(*p - 32);
    }
    if (key[0] == 'S') {
        g_config.screen_mode = (val[0] == '1' && val[1] == '2') ?
                               MODE_120X40 : MODE_80X24;
    } else if (key[0] == 'T') {
        g_config.tab_width = (val[0] == '8') ? 8 : 4;
    } else if (key[0] == 'L') {
        g_config.lines_mode = (val[0] == '3') ? 1 : 0;
    } else if (key[0] == 'R') {
        if (val[0] == 'O' && val[1] != 'F') {
            g_config.ramdrive_mode = RAMDRV_MODE_ENABLED;
        } else if (val[0] == 'H' || val[0] == '2') {
            g_config.ramdrive_mode = RAMDRV_MODE_HIBERNATE;
        } else if (val[0] == 'D' || val[0] == '3') {
            g_config.ramdrive_mode = RAMDRV_MODE_DISABLED;
        } else {
            g_config.ramdrive_mode = RAMDRV_MODE_PROTECTED;
        }
    } else if (key[0] == 'P') {
        if (val[0] == 'D' || val[0] == '2') {
            g_config.plugin_mode = PLUGIN_MODE_ONDEMAND;
        } else if (val[0] == 'O' || val[0] == '0') {
            g_config.plugin_mode = PLUGIN_MODE_DISABLED;
        } else {
            g_config.plugin_mode = PLUGIN_MODE_AUTOLOAD;
        }
    } else if (key[0] == 'A') {
        g_config.auto_indent = (val[0] == '0' || val[0] == 'O' ||
                                val[0] == 'N') ? 0 : 1;
    }
#else
#define CFG_EQ(a, b) (strcasecmp((a), (b)) == 0)
    if (CFG_EQ(key, "SCREEN") ||
        CFG_EQ(key, "SCREEN_MODE")) {
        if (CFG_EQ(val, "80X24") || CFG_EQ(val, "1")) {
            g_config.screen_mode = MODE_80X24;
        } else if (CFG_EQ(val, "120X40") ||
                   CFG_EQ(val, "0")) {
            g_config.screen_mode = MODE_120X40;
        } else if (CFG_EQ(val, "NATIVE") ||
                   CFG_EQ(val, "2")) {
            g_config.screen_mode = MODE_NATIVE;
        }
    } else if (CFG_EQ(key, "TAB") ||
               CFG_EQ(key, "TABS") ||
               CFG_EQ(key, "TAB_WIDTH")) {
        int w = atoi(val);
        if (w == 4 || w == 8) {
            g_config.tab_width = (uint8_t)w;
        }
    } else if (CFG_EQ(key, "LINES") ||
               CFG_EQ(key, "MAXLINES") ||
               CFG_EQ(key, "LINES_MODE")) {
        if (CFG_EQ(val, "32K") || CFG_EQ(val, "1")) {
            g_config.lines_mode = 1;
        } else if (CFG_EQ(val, "16K") || CFG_EQ(val, "0")) {
            g_config.lines_mode = 0;
        }
    } else if (CFG_EQ(key, "RAMDRIVE") ||
               CFG_EQ(key, "RAMDISK")) {
        if (CFG_EQ(val, "PRESERVE") ||
            CFG_EQ(val, "OFF") ||
            CFG_EQ(val, "0")) {
            g_config.ramdrive_mode = RAMDRV_MODE_PROTECTED;
        } else if (CFG_EQ(val, "ON") ||
                   CFG_EQ(val, "OVERWRITE") ||
                   CFG_EQ(val, "ENABLED") ||
                   CFG_EQ(val, "1")) {
            g_config.ramdrive_mode = RAMDRV_MODE_ENABLED;
        } else if (CFG_EQ(val, "HIB") ||
                   CFG_EQ(val, "HIBERNATE") ||
                   CFG_EQ(val, "2")) {
            g_config.ramdrive_mode = RAMDRV_MODE_HIBERNATE;
        } else if (CFG_EQ(val, "DISABLED") ||
                   CFG_EQ(val, "NONE") ||
                   CFG_EQ(val, "3")) {
            g_config.ramdrive_mode = RAMDRV_MODE_DISABLED;
        }
    } else if (CFG_EQ(key, "PLUGIN") ||
               CFG_EQ(key, "PLUGINS") ||
               CFG_EQ(key, "PLUGIN_MODE")) {
        (void)val;
        g_config.plugin_mode = PLUGIN_MODE_AUTOLOAD;
    } else if (CFG_EQ(key, "AUTO_INDENT")) {
        if (CFG_EQ(val, "OFF") || CFG_EQ(val, "NO") ||
            CFG_EQ(val, "0")) {
            g_config.auto_indent = 0;
        } else {
            g_config.auto_indent = 1;
        }
    }
#endif
}

#ifdef __CPM__
#include <cpm.h>
#include "../include/buffer.h"
#include "../include/file_io.h"

#define s_cfg_fcb g_cpm_fcb
#define s_cfg_dma g_cpm_dma_buf

int config_load_file(const char *filename)
{
    int i;
    char *line = g_scratch_line_buf;
    uint8_t line_len = 0;

    config_init_defaults();

    if (!filename) {
        filename = "SE.CFG";
    }

    file_populate_fcb(filename, &s_cfg_fcb);
    if ((uint8_t)bdos(15, (int)&s_cfg_fcb) == 0xFF) {
        if (s_cfg_fcb.drive != 0) {
            return -1;
        }
        file_populate_fcb("A:SE.CFG", &s_cfg_fcb);
        if ((uint8_t)bdos(15, (int)&s_cfg_fcb) == 0xFF) {
            return -1;
        }
    }

    bdos(26, (int)s_cfg_dma);
    while (bdos(20, (int)&s_cfg_fcb) == 0) {
        for (i = 0; i < 128; i++) {
            uint8_t c = s_cfg_dma[i];
            if (c == 0x1A || c == 0) {
                goto cfg_load_done;
            }
            if (c == '\r') {
                continue;
            }
            if (c == '\n') {
                line[line_len] = '\0';
                parse_config_line(line);
                line_len = 0;
                continue;
            }
            if (line_len + 1 < 64) {
                line[line_len++] = (char)c;
            }
        }
    }

cfg_load_done:
    if (line_len > 0) {
        line[line_len] = '\0';
        parse_config_line(line);
    }
    bdos(16, (int)&s_cfg_fcb);
    bdos(26, DEFAULT_DMA);
    g_config_loaded = 1;
    return 0;
}

static char *cfg_put(char *p, const char *s)
{
    while (*s) {
        *p++ = *s++;
    }
    return p;
}

int config_save_file(const char *filename)
{
    const char *ramdrv_str;
    const char *plugin_str;
    char *p = (char *)s_cfg_dma;

    if (!filename) {
        filename = "SE.CFG";
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

    memset(s_cfg_dma, 0x1A, sizeof(s_cfg_dma));

    p = cfg_put(p, "# SE.COM Configuration File\r\nSCREEN=");
    p = cfg_put(p, (g_config.screen_mode == MODE_120X40) ?
                   "120X40\r\n" : "80X24\r\n");
    p = cfg_put(p, (g_config.tab_width == 4) ? "TAB=4\r\n" : "TAB=8\r\n");
    p = cfg_put(p, g_config.lines_mode ? "LINES=32K\r\n" : "LINES=16K\r\n");
    p = cfg_put(p, "RAMDRIVE=");
    p = cfg_put(p, ramdrv_str);
    p = cfg_put(p, "\r\nPLUGIN=");
    p = cfg_put(p, plugin_str);
    p = cfg_put(p, "\r\nAUTO_INDENT=");
    cfg_put(p, g_config.auto_indent ? "1\r\n" : "0\r\n");

    file_populate_fcb(filename, &s_cfg_fcb);
    bdos(19, (int)&s_cfg_fcb);
    if ((uint8_t)bdos(22, (int)&s_cfg_fcb) == 0xFF) {
        return -1;
    }

    bdos(26, (int)s_cfg_dma);
    s_cfg_fcb.random_r0 = 0;
    s_cfg_fcb.random_r1 = 0;
    s_cfg_fcb.random_r2 = 0;
    bdos(34, (int)&s_cfg_fcb);
    bdos(16, (int)&s_cfg_fcb);
    bdos(26, DEFAULT_DMA);
    g_config_loaded = 1;
    return 0;
}
#else
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
        parse_config_line(line);
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
#endif

int config_save(void)
{
    return config_save_file("SE.CFG");
}
