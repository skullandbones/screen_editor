/*==============================================================================
 * UI_MODAL.H: Tier 1/2 Centered Modal Popups, Alerts & Dialog Engine
 *
 * Purpose:
 *   Defines interface contracts for centered dialog boxes, frame drawing,
 *   Tier 1 notifications, and Tier 2 confirmation query modals.
 *   Strictly adheres to docs/UI_UX_DESIGN.md standards.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#ifndef SE_UI_MODAL_H
#define SE_UI_MODAL_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "config.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Modal Return Codes */
#define MODAL_RES_CANCEL        0
#define MODAL_RES_OK            1
#define MODAL_RES_YES           1
#define MODAL_RES_NO            2
#define MODAL_RES_DISCARD       3

/* Modal Drawing & Interaction Functions */
void modal_init_7row(uint8_t *top, uint8_t *left, const char *title);
void modal_draw_frame(uint8_t top, uint8_t left,
                      uint8_t width, uint8_t height,
                      const char *title);
void modal_draw_row_centered(uint8_t row, uint8_t left,
                            uint8_t width, const char *str);
void modal_draw_row_left(uint8_t row, uint8_t left,
                        uint8_t width, const char *str);
void modal_puts_centered(uint8_t row, uint8_t left,
                        uint8_t width, const char *str);
int  modal_alert(const char *title, const char *msg1, const char *msg2);
int  modal_confirm(const char *title, const char *msg,
                   const char *btn1, const char *btn2);
#ifndef __CPM__
int  modal_confirm_3btn(const char *title, const char *msg,
                        const char *btn1, const char *btn2, const char *btn3);
int  modal_prompt_text(const char *title, const char *prompt,
                       char *buffer, size_t max_len);
#endif
int  modal_goto_line(char *buffer, size_t max_len);
int  modal_confirm_save_changes(void);
int  modal_confirm_overwrite(void);
void modal_show_notification(const char *title, const char *message);
void modal_alert_file_not_found(const char *fname);

#ifdef __cplusplus
}
#endif

#endif /* SE_UI_MODAL_H */
