/*==============================================================================
 * UI.H: Terminal Display, Menu Screens, Modal Popups & Status Bar Metrics
 *
 * Purpose:
 *   Defines screen dimension constants, status bar metric widths, menu
 *   line counts, popup tiers, box frame styling, and UI drawing signatures.
 *   C semantic equivalent header mirroring src/include/ui.inc.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#ifndef SE_UI_H
#define SE_UI_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "config.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Screen Dimensions & Display Metrics */
#define SCREEN_COLS_80          80
#define SCREEN_COLS_120         120
#define SCREEN_ROWS_24          24
#define SCREEN_ROWS_40          40

/* Status Bar Field Metrics */
#define STATUS_ENCLOSED_WIDTH   78
#define POS_FIELD_WIDTH         22
#define MEM_FIELD_WIDTH         15
#define FILENAME_FIELD_WIDTH    14

/* Static Menu Screen Line Counts */
#define SPLASH_MENU_LINES       21
#define ABOUT_MENU_LINES        9
#define CONFIG_MENU_LINES       11
#define MEM_INFO_LINES          23

/* Global Display State Variables */
extern uint8_t  g_active_cols;
extern uint8_t  g_active_rows;
extern uint8_t  g_is_splash_screen;
extern uint8_t  g_need_screen_render;
extern uint8_t  g_need_line_render;
extern uint8_t  g_need_status_render;
extern char     g_status_msg[80];

/* UI Subsystem Function Entry Points */
void ui_init(void);
void render_screen(void);
void render_status_bar(void);
void clear_screen(void);
void show_splash_screen(void);
void show_help_screen(void);
void show_about_screen(void);
void show_config_screen(void);
void show_mem_info_screen(void);
void render_current_line(void);
void render_buffer_line(uint16_t row);
void set_status_msg(const char *msg);
void adjust_horiz_viewport(void);
void constrain_cursor_viewport(void);

#ifdef __cplusplus
}
#endif

#endif /* SE_UI_H */
