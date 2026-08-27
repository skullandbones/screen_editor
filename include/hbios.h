#ifndef _HBIOS_H_
#define _HBIOS_H_

#include <stdint.h>
#include <stdbool.h>

/*
 * RomWBW HBIOS System API Function Codes (invoked via RST 08H)
 */
#define HBIOS_SYSGETBNK   0xF3    /* Get current active bank ID */
#define HBIOS_SYSSETCPY   0xF4    /* Prepare inter-bank copy parameters */
#define HBIOS_SYSBNKCPY   0xF5    /* Execute inter-bank block memory copy */
#define HBIOS_SYSALLOC    0xF6    /* Allocate block from HBIOS heap */
#define HBIOS_SYSFREE     0xF7    /* Free block from HBIOS heap */
#define HBIOS_SYSGET      0xF8    /* Get system information */

/*
 * HBIOS Far Pointer structure for addressing extended memory
 */
typedef struct {
    uint8_t  bank;      /* Bank ID (1..15) */
    uint16_t offset;    /* Offset within bank (0x0000..0xFFFF) */
} FarPtr;

/*
 * Low-level HBIOS assembly interface functions
 */
extern uint8_t hbios_get_bank(void);
extern uint8_t hbios_copy(uint8_t dst_bank, void *dst_addr,
                          uint8_t src_bank, const void *src_addr,
                          uint16_t count);
extern bool hbios_detect(void);

#endif /* _HBIOS_H_ */
