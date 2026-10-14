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
#define BROWSER_FILENAME_LEN    13
#else
#define MAX_BROWSER_FILES       256
#define BROWSER_FILENAME_LEN    32
#endif
#define BROWSER_PAGE_SIZE       16

/* Browser Modes */
#define BROWSER_MODE_OPEN       0
#define BROWSER_MODE_INSERT     1
#define BROWSER_MODE_SAVE       2
#define BROWSER_MODE_SAVE_BLOCK 3

/* Directory File Entry */
typedef struct {
    char     filename[BROWSER_FILENAME_LEN];      /* Entry name */
#ifndef __CPM__
    uint32_t size_bytes;        /* File size in bytes */
#endif
    uint8_t  is_dir;            /* 1 if directory / folder */
    uint8_t  drive;             /* Drive number (0=A, 1=B, etc.) */
    uint8_t  user;              /* User area (0..15) */
} browser_entry_t;

/* Browser Subsystem Function Entry Points */
int  ui_browser_open_dialog(char *selected_filename, size_t max_len);
int  ui_browser_save_dialog(char *selected_filename, size_t max_len);
int  ui_browser_insert_dialog(char *selected_filename, size_t max_len);
int  ui_browser_save_block_dialog(char *selected_filename, size_t max_len);
void ui_browser_refresh_directory(const char *mask);
int  ui_browser_get_file_count(void);
const browser_entry_t *ui_browser_get_entry(int index);
void ui_browser_clear_entries(void);
int  ui_browser_add_entry(const char *name, uint32_t size, uint8_t is_dir);

#ifdef __cplusplus
}
#endif

#endif /* SE_UI_BROWSER_H */
