/*==============================================================================
 * MEMORY.H: Virtual Slot Allocator, Paging Engine & Far RAM Abstraction API
 *
 * Purpose:
 *   Defines virtual slot management, Far RAM banking structures, disk swap
 *   subsystem, and line read/write primitives for multi-megabyte documents.
 *   C semantic equivalent header mirroring virtual memory subsystems.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#ifndef SE_MEMORY_H
#define SE_MEMORY_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "config.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Memory Bank & Slot Metrics */
#define SLOTS_PER_BANK          256 /* 128 bytes per slot * 256 = 32KB bank */
#define MAX_SWAP_PAGES          256 /* Max pages backed by swap disk file */

/* Slot Record Layout */
typedef struct {
    uint16_t next_slot;     /* Chained continuation slot (or SLOT_TERM) */
    uint8_t  payload[FAR_SLOT_PAYLOAD]; /* Text payload chunk */
} far_slot_t;

/* Far Memory Subsystem Function Declarations */
void     mem_init_paging(void);
uint16_t mem_alloc_slot(void);
void     mem_free_slot(uint16_t slot_id);
void     mem_free_line_chain(uint16_t slot_id);
int      mem_write_slot(uint16_t slot_id, const uint8_t *src);
int      mem_read_slot(uint16_t slot_id, uint8_t *dest);
int      mem_write_line(uint16_t *start_slot, const char *text, uint16_t len);
uint16_t mem_read_line(uint16_t start_slot, char *dest, uint16_t max_len);
int      mem_ensure_page_resident(uint16_t page_id);
void     mem_cleanup_swap(void);
uint16_t mem_get_free_slots(void);
uint32_t mem_get_free_kb(void);

#ifdef __cplusplus
}
#endif

#endif /* SE_MEMORY_H */
