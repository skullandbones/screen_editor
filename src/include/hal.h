/*==============================================================================
 * HAL.H: Hardware Abstraction Layer (HAL) API Interface Specifications
 *
 * Purpose:
 *   Defines standard function prototypes and calling conventions for Console,
 *   Memory Banking, and Storage sub-systems across supported platforms:
 *     - Standard CP/M (8080 / Z80 / HBIOS)
 *     - ZX Spectrum Next (NextCPM / NextZXOS)
 *     - Native Linux (POSIX x86_64 / AArch64)
 *     - CP/M-86 (8086 / BDOS)
 *   C semantic equivalent header mirroring src/include/hal.inc.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#ifndef SE_HAL_H
#define SE_HAL_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* HAL Console Sub-system Interface */
void hal_console_init(void);
void hal_console_putc(char c);
void hal_console_puts(const char *s);
int  hal_console_getkey(void);
int  hal_console_check_key(void);
void hal_console_locate(uint8_t row, uint8_t col);
void hal_console_inverse_on(void);
void hal_console_inverse_off(void);
void hal_console_clear(void);
void hal_console_clear_eol(void);
void hal_console_hide_cursor(void);
void hal_console_show_cursor(void);

/* HAL Memory & Far Banking Sub-system Interface */
int  hal_mem_init(void);
int  hal_mem_read_slot(uint16_t slot_id, uint8_t *dest);
int  hal_mem_write_slot(uint16_t slot_id, const uint8_t *src);
void hal_mem_set_bank(uint8_t bank);

/* HAL Storage & File I/O Sub-system Interface */
int  hal_storage_open(const char *path, void *handle);
int  hal_storage_make(const char *path, void *handle);
int  hal_storage_close(void *handle);
int  hal_storage_read_sec(void *handle, uint8_t *buf);
int  hal_storage_write_sec(void *handle, const uint8_t *buf);
void hal_linux_scan_directory(const char *dir_path);

#ifdef __cplusplus
}
#endif

#endif /* SE_HAL_H */
