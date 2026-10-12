/*==============================================================================
 * MEMORY.C: Virtual Slot Allocator, Paging Engine & Far RAM Abstraction
 *
 * Purpose:
 *   Implements virtual slot allocation, Far RAM banking abstraction,
 *   line chaining, and memory metrics calculation.
 *   C semantic equivalent to src/core/memory.asm.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "../include/config.h"
#include "../include/memory.h"
#include "../include/hal.h"

/* Fixed Slot Allocation Bitmap/Tracking Table */
#ifndef MAX_ACTIVE_SLOTS
#define MAX_ACTIVE_SLOTS        4096
#endif

#define SLOT_BITMAP_BYTES       ((MAX_ACTIVE_SLOTS + 7) / 8)
static uint8_t    s_slot_bitmap[SLOT_BITMAP_BYTES];
static uint16_t   s_free_slot_hint = 0;
static uint16_t   s_total_allocations = 0;
static const uint8_t s_bit_mask[8] = {
    0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80
};

static int is_slot_allocated(uint16_t id)
{
    return (s_slot_bitmap[id >> 3] & s_bit_mask[id & 7]) != 0;
}

static void set_slot_allocated(uint16_t id)
{
    s_slot_bitmap[id >> 3] |= s_bit_mask[id & 7];
}

static void clear_slot_allocated(uint16_t id)
{
    s_slot_bitmap[id >> 3] &= (uint8_t)~s_bit_mask[id & 7];
}

void mem_init_paging(void)
{
    memset(s_slot_bitmap, 0, sizeof(s_slot_bitmap));
    s_free_slot_hint = 0;
    s_total_allocations = 0;
    hal_mem_init();
}

uint16_t mem_alloc_slot(void)
{
    uint16_t i;
    for (i = 0; i < MAX_ACTIVE_SLOTS; i++) {
        uint16_t idx = (s_free_slot_hint + i) % MAX_ACTIVE_SLOTS;
        if (!is_slot_allocated(idx)) {
            far_slot_t slot_init;
            set_slot_allocated(idx);
            slot_init.next_slot = SLOT_TERM;
            memset(slot_init.payload, 0, FAR_SLOT_PAYLOAD);
            hal_mem_write_slot(idx, (const uint8_t *)&slot_init);
            s_free_slot_hint = (idx + 1) % MAX_ACTIVE_SLOTS;
            s_total_allocations++;
            return idx;
        }
    }
    return SLOT_TERM;
}

void mem_free_slot(uint16_t slot_id)
{
    if (slot_id < MAX_ACTIVE_SLOTS && is_slot_allocated(slot_id)) {
        clear_slot_allocated(slot_id);
        if (s_total_allocations > 0) {
            s_total_allocations--;
        }
        if (slot_id < s_free_slot_hint) {
            s_free_slot_hint = slot_id;
        }
    }
}

void mem_free_line_chain(uint16_t slot_id)
{
    uint16_t cur = slot_id;
    uint16_t next;
    uint16_t guard = 0;
    far_slot_t slot_buf;

    while (cur != SLOT_TERM && cur < MAX_ACTIVE_SLOTS && guard < 65535) {
        if (hal_mem_read_slot(cur, (uint8_t *)&slot_buf) != 0) {
            break;
        }
        next = slot_buf.next_slot;
        mem_free_slot(cur);
        cur = next;
        guard++;
    }
}

int mem_write_slot(uint16_t slot_id, const uint8_t *src)
{
    if (slot_id >= MAX_ACTIVE_SLOTS || !is_slot_allocated(slot_id) || !src) {
        return -1;
    }
    return hal_mem_write_slot(slot_id, src);
}

int mem_read_slot(uint16_t slot_id, uint8_t *dest)
{
    if (slot_id >= MAX_ACTIVE_SLOTS || !is_slot_allocated(slot_id) || !dest) {
        return -1;
    }
    return hal_mem_read_slot(slot_id, dest);
}

int mem_write_line(uint16_t *start_slot, const char *text, uint16_t len)
{
    uint16_t bytes_remaining = len;
    uint16_t offset = 0;
    uint16_t prev_slot = SLOT_TERM;
    uint16_t first_slot = SLOT_TERM;
    far_slot_t cur_slot_data;
    far_slot_t prev_slot_data;

    if (!start_slot || !text) {
        return -1;
    }

    if (*start_slot != SLOT_TERM) {
        mem_free_line_chain(*start_slot);
        *start_slot = SLOT_TERM;
    }

    if (len == 0) {
        *start_slot = SLOT_TERM;
        return 0;
    }

    while (bytes_remaining > 0) {
        uint16_t cur_slot = mem_alloc_slot();
        uint16_t chunk_len;

        if (cur_slot == SLOT_TERM) {
            if (first_slot != SLOT_TERM) {
                mem_free_line_chain(first_slot);
            }
            *start_slot = SLOT_TERM;
            return -1;
        }

        if (first_slot == SLOT_TERM) {
            first_slot = cur_slot;
        }
        if (prev_slot != SLOT_TERM) {
            if (hal_mem_read_slot(prev_slot,
                                  (uint8_t *)&prev_slot_data) == 0) {
                prev_slot_data.next_slot = cur_slot;
                hal_mem_write_slot(prev_slot,
                                   (const uint8_t *)&prev_slot_data);
            }
        }

        chunk_len = bytes_remaining;
        if (chunk_len > FAR_SLOT_PAYLOAD) {
            chunk_len = FAR_SLOT_PAYLOAD;
        }

        memset(&cur_slot_data, 0, sizeof(far_slot_t));
        cur_slot_data.next_slot = SLOT_TERM;
        memcpy(cur_slot_data.payload, text + offset, chunk_len);
        hal_mem_write_slot(cur_slot, (const uint8_t *)&cur_slot_data);

        bytes_remaining -= chunk_len;
        offset += chunk_len;
        prev_slot = cur_slot;
    }

    *start_slot = first_slot;
    return 0;
}

uint16_t mem_read_line(uint16_t start_slot, char *dest, uint16_t max_len)
{
    uint16_t cur_slot = start_slot;
    uint16_t bytes_copied = 0;
    uint16_t guard = 0;
    far_slot_t cur_slot_data;

    if (!dest || max_len == 0) {
        return 0;
    }

    dest[0] = '\0';

    while (cur_slot != SLOT_TERM && cur_slot < MAX_ACTIVE_SLOTS &&
           guard < 65535) {
        uint16_t chunk_len = FAR_SLOT_PAYLOAD;
        uint16_t actual_len;

        if (hal_mem_read_slot(cur_slot, (uint8_t *)&cur_slot_data) != 0) {
            break;
        }

        for (actual_len = 0; actual_len < chunk_len; actual_len++) {
            if (cur_slot_data.payload[actual_len] == '\0') {
                break;
            }
        }

        if (bytes_copied + actual_len > max_len) {
            actual_len = max_len - bytes_copied;
        }

        if (actual_len > 0) {
            memcpy(dest + bytes_copied, cur_slot_data.payload,
                   actual_len);
            bytes_copied += actual_len;
        }

        if (bytes_copied >= max_len) {
            break;
        }

        cur_slot = cur_slot_data.next_slot;
        guard++;
    }

    dest[bytes_copied] = '\0';
    return bytes_copied;
}

int mem_ensure_page_resident(uint16_t page_id)
{
    (void)page_id;
    return 0;
}

void mem_cleanup_swap(void)
{
    /* Clean up any temporary swap artifacts */
}

uint16_t mem_get_free_slots(void)
{
    if (s_total_allocations >= MAX_ACTIVE_SLOTS) {
        return 0;
    }
    return (uint16_t)(MAX_ACTIVE_SLOTS - s_total_allocations);
}

uint32_t mem_get_free_kb(void)
{
    uint32_t free_slots = mem_get_free_slots();
    return (free_slots * FAR_SLOT_SIZE) / 1024;
}
