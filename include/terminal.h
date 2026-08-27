#ifndef _TERMINAL_H_
#define _TERMINAL_H_

#include <stdint.h>
#include <stdbool.h>

/* Screen Geometry */
#define SCREEN_ROWS         24
#define SCREEN_COLS         80

/* Special Keys and Control Codes */
#define KEY_CTRL_A         1
#define KEY_CTRL_C         3
#define KEY_CTRL_E         5
#define KEY_CTRL_G         7
#define KEY_BACKSPACE      8
#define KEY_TAB            9
#define KEY_ENTER          13
#define KEY_CTRL_K         11
#define KEY_CTRL_L         12
#define KEY_CTRL_N         14
#define KEY_CTRL_O         15
#define KEY_CTRL_Q         17
#define KEY_CTRL_R         18
#define KEY_CTRL_S         19
#define KEY_CTRL_U         21
#define KEY_CTRL_V         22
#define KEY_CTRL_W         23
#define KEY_CTRL_X         24
#define KEY_CTRL_Z         26
#define KEY_ESC            27
#define KEY_DEL            127

/* Decoded Multi-byte ANSI Escape Keys */
#define KEY_ARROW_UP       1001
#define KEY_ARROW_DOWN     1002
#define KEY_ARROW_RIGHT    1003
#define KEY_ARROW_LEFT     1004
#define KEY_HOME           1005
#define KEY_END            1006
#define KEY_PAGE_UP        1007
#define KEY_PAGE_DOWN      1008
#define KEY_DELETE_KEY     1009

/* Terminal API */
void term_init(void);
void term_restore(void);
void term_clear_screen(void);
void term_move_cursor(uint8_t row, uint8_t col);
void term_clear_to_eol(void);
void term_set_inverse(bool enable);
void term_putc(char ch);
void term_puts(const char *str);
int  term_read_key(void);
void term_render_screen(void);
void term_render_status(const char *filename, const char *status_msg);

#endif /* _TERMINAL_H_ */
