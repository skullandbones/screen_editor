/*==============================================================================
 * BUFFER.C: Core Subsystem - Document Buffer, Line Table & Cache Engine
 *
 * Purpose:
 *   Implements virtual line slot tables, active line editing workspace,
 *   document line cache management, and line insertion/deletion primitives.
 *   C semantic equivalent to src/core/buffer.asm.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#include <string.h>
#include <stdio.h>
#include "../include/config.h"
#include "../include/buffer.h"
#include "../include/memory.h"
#include "../include/file_io.h"

/* Document Line Slots Array (Maps document row -> 16-bit Far Slot ID) */
static uint16_t s_line_slots[MAX_DOC_LINES];

/* Global Active Line Buffer & Document State */
char     g_active_line_buf[MAX_ACTIVE_LINE_STRIDE];
char     g_scratch_line_buf[MAX_ACTIVE_LINE_STRIDE];
uint16_t g_active_line_len = 0;
uint16_t g_active_line_row = 0;
uint8_t  g_active_line_valid = 0;
uint16_t g_cur_doc_row = 0;
uint16_t g_doc_total_lines = 0;
uint8_t  g_doc_modified = 0;

void buffer_init(void)
{
    uint16_t i;

    memset(g_active_line_buf, 0, sizeof(g_active_line_buf));
    memset(g_scratch_line_buf, 0, sizeof(g_scratch_line_buf));
    g_active_line_len = 0;
    g_active_line_row = 0;
    g_active_line_valid = 0;
    g_cur_doc_row = 0;
    g_doc_total_lines = 0;
    g_doc_modified = 0;

    for (i = 0; i < MAX_DOC_LINES; i++) {
        s_line_slots[i] = SLOT_TERM;
    }

    mem_init_paging();
    init_empty_document();
}

void init_empty_document(void)
{
    g_doc_total_lines = 1;
    g_cur_doc_row = 0;
    s_line_slots[0] = SLOT_TERM;
    g_active_line_valid = 1;
    g_active_line_row = 0;
    g_active_line_len = 0;
    g_active_line_buf[0] = '\0';
    g_doc_modified = 0;
#ifdef __CPM__
    g_file_format = FMT_CPM;
#else
    g_file_format = FMT_LINUX;
#endif
}

uint16_t get_line_slot(uint16_t line_idx, int *err)
{
    if (line_idx >= MAX_DOC_LINES) {
        if (err) *err = 1;
        return SLOT_TERM;
    }
    if (err) *err = 0;
    return s_line_slots[line_idx];
}

int set_line_slot(uint16_t line_idx, uint16_t slot_id)
{
    if (line_idx >= MAX_DOC_LINES) {
        return -1;
    }
    s_line_slots[line_idx] = slot_id;
    return 0;
}

void checkout_active_line(uint16_t line_idx)
{
    if (g_active_line_valid && g_active_line_row == line_idx) {
        return;
    }

    if (g_active_line_valid) {
        commit_active_line();
    }

    g_active_line_row = line_idx;
    g_active_line_len = fetch_line_to_buffer(line_idx, g_active_line_buf,
                                             MAX_ACTIVE_PAYLOAD);
    g_active_line_buf[g_active_line_len] = '\0';
    g_active_line_valid = 1;
}

void commit_active_line(void)
{
    uint16_t slot_id;

    if (!g_active_line_valid) {
        return;
    }

    if (g_active_line_row >= g_doc_total_lines) {
        g_active_line_valid = 0;
        return;
    }

    slot_id = s_line_slots[g_active_line_row];
    if (g_active_line_len == 0) {
        if (slot_id != SLOT_TERM) {
            mem_free_line_chain(slot_id);
            s_line_slots[g_active_line_row] = SLOT_TERM;
        }
    } else {
        mem_write_line(&slot_id, g_active_line_buf, g_active_line_len);
        s_line_slots[g_active_line_row] = slot_id;
    }

    g_active_line_valid = 0;
}

void invalidate_active_line(void)
{
    g_active_line_valid = 0;
    g_active_line_len = 0;
    g_active_line_buf[0] = '\0';
}

uint16_t fetch_line_to_buffer(uint16_t line_idx, char *dest, size_t max_len)
{
    uint16_t slot_id;

    if (line_idx >= g_doc_total_lines || dest == NULL || max_len == 0) {
        if (dest && max_len > 0) dest[0] = '\0';
        return 0;
    }

    if (g_active_line_valid && g_active_line_row == line_idx) {
        size_t copy_len = g_active_line_len;
        if (copy_len >= max_len) {
            copy_len = max_len - 1;
        }
        memcpy(dest, g_active_line_buf, copy_len);
        dest[copy_len] = '\0';
        return (uint16_t)copy_len;
    }

    slot_id = s_line_slots[line_idx];
    if (slot_id == SLOT_TERM) {
        dest[0] = '\0';
        return 0;
    }

    return mem_read_line(slot_id, dest, (uint16_t)(max_len - 1));
}

int store_active_line(void)
{
    commit_active_line();
    checkout_active_line(g_cur_doc_row);
    return 0;
}

void shift_line_slots_up(uint16_t start_idx, uint16_t count)
{
    uint16_t i;
    for (i = start_idx; i + count < g_doc_total_lines; i++) {
        s_line_slots[i] = s_line_slots[i + count];
    }
    for (; i < g_doc_total_lines; i++) {
        s_line_slots[i] = SLOT_TERM;
    }
}

void shift_line_slots_down(uint16_t start_idx, uint16_t count)
{
    uint16_t i = g_doc_total_lines;
    while (i > start_idx) {
        i--;
        if (i + count < MAX_DOC_LINES) {
            s_line_slots[i + count] = s_line_slots[i];
        }
    }
    for (i = 0; i < count && (start_idx + i) < MAX_DOC_LINES; i++) {
        s_line_slots[start_idx + i] = SLOT_TERM;
    }
}

int insert_blank_line(uint16_t line_idx)
{
    if (g_doc_total_lines >= MAX_DOC_LINES) {
        return -1;
    }

    commit_active_line();
    shift_line_slots_down(line_idx, 1);
    s_line_slots[line_idx] = SLOT_TERM;
    g_doc_total_lines++;
    g_doc_modified = 1;
    return 0;
}

int delete_doc_row(uint16_t line_idx)
{
    uint16_t slot_id;

    if (g_doc_total_lines <= 1 || line_idx >= g_doc_total_lines) {
        return -1;
    }

    commit_active_line();
    slot_id = s_line_slots[line_idx];
    if (slot_id != SLOT_TERM) {
        mem_free_line_chain(slot_id);
    }

    shift_line_slots_up(line_idx, 1);
    g_doc_total_lines--;
    g_doc_modified = 1;

    if (g_cur_doc_row >= g_doc_total_lines) {
        g_cur_doc_row = g_doc_total_lines - 1;
    }
    return 0;
}

void flush_dirty_cache(void)
{
    commit_active_line();
}
