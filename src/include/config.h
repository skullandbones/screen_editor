/*==============================================================================
 * CONFIG.H: Global Configuration, Editor Constants, Limits & Keycodes
 *
 * Purpose:
 *   Defines platform-agnostic editor limits, line dimensions, keycodes,
 *   screen modes, confirmation action codes, and configuration defaults.
 *   C semantic equivalent header mirroring src/include/config.inc.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#ifndef SE_CONFIG_H
#define SE_CONFIG_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* CP/M System Addresses & Vectors */
#define BDOS_ENTRY              0x0005
#define DEFAULT_FCB             0x005C
#define DEFAULT_DMA             0x0080
#define CMD_LEN                 0x0080
#define CMD_TAIL                0x0081

/* Buffer & Document Capacity Limits */
#define MAX_LINE                1000
#define MAX_LINE_STRIDE         128
#define MAX_LINE_CHARS          1000
#define MAX_CACHE_LINE_CHARS    250
#define FAR_SLOT_SIZE           128
#define FAR_SLOT_PAYLOAD        126
#define SLOT_TERM               0xFFFF
#define MAX_COPY_LINE_CHARS     120
#define MAX_FAR_BANKS           12
#ifdef __CPM__
#define MAX_ACTIVE_LINE_STRIDE  152
#define MAX_ACTIVE_PAYLOAD      150
#define MAX_INPUT_LINE_CHARS    148
#define CACHE_SIZE_LINES        16
#define MAX_DOC_LINES_16K       16384
#define MAX_DOC_LINES_32K       16384
#define MAX_DOC_LINES           16384
#define MAX_VIRTUAL_SLOTS       2048
#define MAX_ACTIVE_SLOTS        512
#define CLIPBOARD_MAX_CHARS     128
#else
#define MAX_ACTIVE_LINE_STRIDE  1024
#define MAX_ACTIVE_PAYLOAD      1022
#define MAX_INPUT_LINE_CHARS    1000
#define CACHE_SIZE_LINES        40
#define MAX_DOC_LINES_16K       16384
#define MAX_DOC_LINES_32K       32768
#define MAX_DOC_LINES           32768
#define MAX_VIRTUAL_SLOTS       65534
#define MAX_ACTIVE_SLOTS        4096
#define CLIPBOARD_MAX_CHARS     32768
#endif

/* Keyboard Control Codes (WordStar & ANSI Mappings) */
#define KEY_CTRL_A              1   /* Start of line (Home) */
#define KEY_CTRL_B              2   /* Toggle Block Highlighting */
#define KEY_CTRL_C              3   /* Cancel / Copy block */
#define KEY_CTRL_D              4   /* Cursor Right */
#define KEY_CTRL_E              5   /* End of line (End) */
#define KEY_CTRL_F              6   /* Find / Toggle endings in save */
#define KEY_CTRL_G              7   /* Delete character at cursor */
#define KEY_BACKSPACE           8   /* Destructive backspace */
#define KEY_TAB                 9   /* Tab character / Prompt toggle */
#define KEY_CTRL_I              9   /* Synonymous with Tab */
#define KEY_CTRL_K              11  /* Show Editor Mode Keys Screen */
#define KEY_CTRL_L              12  /* Goto Line Number */
#define KEY_ENTER               13  /* Carriage Return / Enter */
#define KEY_CTRL_N              14  /* Find Next */
#define KEY_CTRL_O              15  /* Open File Screen */
#define KEY_CTRL_P              16  /* Context-Aware Plugin Pop-up */
#define KEY_CTRL_Q              17  /* Quick exit / Save changes prompt */
#define KEY_CTRL_R              18  /* Search & Replace */
#define KEY_CTRL_S              19  /* Save current document */
#define KEY_CTRL_T              20  /* Jump to top of document */
#define KEY_CTRL_U              21  /* Page Up */
#define KEY_CTRL_V              22  /* Page Down */
#define KEY_CTRL_W              23  /* Close active file to splash screen */
#define KEY_CTRL_X              24  /* Move solidified block to cursor */
#define KEY_CTRL_Y              25  /* Beautify Block or Document */
#define KEY_CTRL_Z              26  /* Open Plugin Manager Screen */
#define KEY_ESC                 27  /* Escape prefix / Cancel dialog */
#define KEY_DEL                 127 /* Rubout / Delete character */

/* Extended Navigation Keycodes (> 255) */
#define KEY_UP                  256
#define KEY_DOWN                257
#define KEY_LEFT                258
#define KEY_RIGHT               259
#define KEY_HOME                260
#define KEY_END                 261
#define KEY_PGUP                262
#define KEY_PGDN                263
#define KEY_INS                 264
#define KEY_SHIFT_UP            265
#define KEY_SHIFT_DOWN          266
#define KEY_SHIFT_LEFT          267
#define KEY_SHIFT_RIGHT         268

#define ESC_TIMEOUT_LOOPS       5000 /* Escape debounce timeout */

/* Modal Confirmation Action Codes */
#define ACTION_EXIT             0   /* Exit editor to OS prompt */
#define ACTION_CLOSE            1   /* Close document to splash screen */
#define ACTION_NEW              2   /* Start new blank document */
#define ACTION_OPEN             3   /* Open File Screen */

/* Line Ending Modes */
#define FMT_CPM                 0   /* CP/M format: CR/LF (0x0D, 0x0A) */
#define FMT_LINUX               1   /* Linux format: LF only (0x0A) */

/* Screen Geometry Modes */
#define MODE_120X40             0   /* Modern 120 columns x 40 rows */
#define MODE_80X24              1   /* Classic 80 columns x 24 rows */
#define MODE_NATIVE             2   /* Native host terminal dimensions */

/* RAM Drive Modes */
#define RAMDRV_MODE_PROTECTED   0   /* Preserve RAM disk (81h..88h safe) */
#define RAMDRV_MODE_ENABLED     1   /* Overwrite for max RAM buffer */
#define RAMDRV_MODE_HIBERNATE   2   /* Auto-dump to RAMDRV.IMG on disk */
#define RAMDRV_MODE_DISABLED    3   /* RAM drive disabled / none */
#define RAMDRV_START_BANK       0x81
#define RAMDRV_END_BANK         0x88

/* Plugin Subsystem Modes */
#define PLUGIN_MODE_DISABLED    0   /* Subsystem disabled by user */
#define PLUGIN_MODE_AUTOLOAD    1   /* Autoload PLUGIN.PRL at boot */
#define PLUGIN_MODE_ONDEMAND    2   /* Load PLUGIN.PRL on demand */

/* Configuration State Structure */
typedef struct {
    uint8_t tab_width;          /* Tab width in spaces (default: 8) */
    uint8_t lines_mode;         /* 0 = 16K lines, 1 = 32K lines */
    uint8_t screen_mode;        /* MODE_120X40 or MODE_80X24 */
    uint8_t ramdrive_mode;      /* RAMDRV_MODE_* */
    uint8_t plugin_mode;        /* PLUGIN_MODE_* */
    uint8_t save_format;        /* FMT_CPM or FMT_LINUX */
    uint8_t auto_indent;        /* 0 = Off, 1 = On */
    uint8_t show_line_endings;  /* 0 = Hide, 1 = Show */
} editor_config_t;

/* Global Configuration Instance */
extern editor_config_t g_config;
extern uint8_t         g_config_loaded;

/* Function Declarations */
void config_init_defaults(void);
int  config_load_file(const char *filename);
int  config_save_file(const char *filename);
int  config_save(void);

#ifdef __cplusplus
}
#endif

#endif /* SE_CONFIG_H */
