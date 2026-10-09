/*==============================================================================
 * HAL_LINUX_MEMORY.C: Linux POSIX HAL - Dynamic Heap & Far Memory Driver
 *
 * Purpose:
 *   Implements Linux memory abstraction, dynamic heap buffers replacing 64KB
 *   Z80 banking while preserving slot allocation semantics and line limits.
 *
 * Part of SE.COM / Linux Native Profile (x86_64 and AArch64)
 *============================================================================*/

#include <stdlib.h>
#include <string.h>
#include "../../include/config.h"
#include "../../include/hal.h"

#define LINUX_HEAP_SLOTS 65534

static uint8_t *s_slot_heap = NULL;
static uint8_t  s_active_bank = 0;

int hal_mem_init(void)
{
    if (!s_slot_heap) {
        s_slot_heap = (uint8_t *)calloc(LINUX_HEAP_SLOTS, FAR_SLOT_SIZE);
        if (!s_slot_heap) {
            return -1;
        }
    }
    s_active_bank = 0;
    return 12; /* Report 12 virtual 32KB banks (384KB) */
}

int hal_mem_read_slot(uint16_t slot_id, uint8_t *dest)
{
    if (!s_slot_heap || slot_id >= LINUX_HEAP_SLOTS || !dest) {
        return -1;
    }
    memcpy(dest, s_slot_heap + ((size_t)slot_id * FAR_SLOT_SIZE),
           FAR_SLOT_SIZE);
    return 0;
}

int hal_mem_write_slot(uint16_t slot_id, const uint8_t *src)
{
    if (!s_slot_heap || slot_id >= LINUX_HEAP_SLOTS || !src) {
        return -1;
    }
    memcpy(s_slot_heap + ((size_t)slot_id * FAR_SLOT_SIZE), src,
           FAR_SLOT_SIZE);
    return 0;
}

void hal_mem_set_bank(uint8_t bank)
{
    s_active_bank = bank;
}
