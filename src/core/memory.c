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

/* Fixed Slot Pool Buffer */
#define MAX_ACTIVE_SLOTS        4096

static far_slot_t s_slot_pool[MAX_ACTIVE_SLOTS];
static uint8_t    s_slot_allocated[MAX_ACTIVE_SLOTS];
static uint16_t   s_free_slot_hint = 0;
static uint32_t   s_total_allocations = 0;

void mem_init_paging(void)
{
    memset(s_slot_allocated, 0, sizeof(s_slot_allocated));
    memset(s_slot_pool, 0, sizeof(s_slot_pool));
    s_free_slot_hint = 0;
    s_total_allocations = 0;
    hal_mem_init();
}

uint16_t mem_alloc_slot(void)
{
    uint16_t i;
    for (i = 0; i < MAX_ACTIVE_SLOTS; i++) {
        uint16_t idx = (s_free_slot_hint + i) % MAX_ACTIVE_SLOTS;
        if (!s_slot_allocated[idx]) {
            s_slot_allocated[idx] = 1;
            s_slot_pool[idx].next_slot = SLOT_TERM;
            memset(s_slot_pool[idx].payload, 0, FAR_SLOT_PAYLOAD);
            s_free_slot_hint = (idx + 1) % MAX_ACTIVE_SLOTS;
            s_total_allocations++;
            return idx;
        }
    }
    return SLOT_TERM;
}

void mem_free_slot(uint16_t slot_id)
{
    if (slot_id < MAX_ACTIVE_SLOTS && s_slot_allocated[slot_id]) {
        s_slot_allocated[slot_id] = 0;
        s_slot_pool[slot_id].next_slot = SLOT_TERM;
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

    while (cur != SLOT_TERM && cur < MAX_ACTIVE_SLOTS && guard < 65535) {
        next = s_slot_pool[cur].next_slot;
        mem_free_slot(cur);
        cur = next;
        guard++;
    }
}

int mem_write_slot(uint16_t slot_id, const uint8_t *src)
{
    if (slot_id >= MAX_ACTIVE_SLOTS || !s_slot_allocated[slot_id] || !src) {
        return -1;
    }
    memcpy(&s_slot_pool[slot_id], src, sizeof(far_slot_t));
    return 0;
}

int mem_read_slot(uint16_t slot_id, uint8_t *dest)
{
    if (slot_id >= MAX_ACTIVE_SLOTS || !s_slot_allocated[slot_id] || !dest) {
        return -1;
    }
    memcpy(dest, &s_slot_pool[slot_id], sizeof(far_slot_t));
    return 0;
}

int mem_write_line(uint16_t *start_slot, const char *text, uint16_t len)
{
    uint16_t bytes_remaining = len;
    uint16_t offset = 0;
    uint16_t prev_slot = SLOT_TERM;
    uint16_t first_slot = SLOT_TERM;

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
            s_slot_pool[prev_slot].next_slot = cur_slot;
        }

        chunk_len = bytes_remaining;
        if (chunk_len > FAR_SLOT_PAYLOAD) {
            chunk_len = FAR_SLOT_PAYLOAD;
        }

        memcpy(s_slot_pool[cur_slot].payload, text + offset, chunk_len);
        if (chunk_len < FAR_SLOT_PAYLOAD) {
            memset(s_slot_pool[cur_slot].payload + chunk_len, 0,
                   FAR_SLOT_PAYLOAD - chunk_len);
        }
        s_slot_pool[cur_slot].next_slot = SLOT_TERM;

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

    if (!dest || max_len == 0) {
        return 0;
    }

    dest[0] = '\0';

    while (cur_slot != SLOT_TERM && cur_slot < MAX_ACTIVE_SLOTS &&
           guard < 65535) {
        uint16_t chunk_len = FAR_SLOT_PAYLOAD;
        uint16_t actual_len;

        for (actual_len = 0; actual_len < chunk_len; actual_len++) {
            if (s_slot_pool[cur_slot].payload[actual_len] == '\0') {
                break;
            }
        }

        if (bytes_copied + actual_len > max_len) {
            actual_len = max_len - bytes_copied;
        }

        if (actual_len > 0) {
            memcpy(dest + bytes_copied, s_slot_pool[cur_slot].payload,
                   actual_len);
            bytes_copied += actual_len;
        }

        if (bytes_copied >= max_len) {
            break;
        }

        cur_slot = s_slot_pool[cur_slot].next_slot;
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
