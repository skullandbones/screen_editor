/*==============================================================================
 * UI_BROWSER.H: File Selection, Directory Browser & Pagination Modals
 *
 * Purpose:
 *   Defines interface contracts for full-screen and pop-up directory
 *   enumeration, file picker modal dialogs, and pagination controls.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#ifndef SE_UI_BROWSER_H
#define SE_UI_BROWSER_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "config.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Maximum Browser Entries & Layout */
#ifdef __CPM__
#define MAX_BROWSER_FILES       32
#else
#define MAX_BROWSER_FILES       256
#endif
#define BROWSER_PAGE_SIZE       16

/* Directory File Entry */
typedef struct {
    char     filename[16];      /* 8.3 formatted name or path */
    uint32_t size_bytes;        /* File size in bytes */
    uint8_t  is_dir;            /* 1 if directory / folder */
    uint8_t  drive;             /* Drive number (0=A, 1=B, etc.) */
    uint8_t  user;              /* User area (0..15) */
} browser_entry_t;

/* Browser Subsystem Function Entry Points */
int  ui_browser_open_dialog(char *selected_filename, size_t max_len);
int  ui_browser_save_dialog(char *selected_filename, size_t max_len);
void ui_browser_refresh_directory(const char *mask);
int  ui_browser_get_file_count(void);
const browser_entry_t *ui_browser_get_entry(int index);

#ifdef __cplusplus
}
#endif

#endif /* SE_UI_BROWSER_H */
