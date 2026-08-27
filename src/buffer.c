#include <stdio.h>
#include <string.h>
#include "buffer.h"
#include "hbios.h"

EditorBuffer g_buf;

/* Next available location in extended memory pool */
static uint8_t  s_alloc_bank = 1;      /* Start using upper RAM bank 1 */
static uint16_t s_alloc_offset = 0x0000;
static uint8_t  s_cpm_user_bank = 0;   /* Active CP/M user bank */

void buffer_init(uint8_t tab_size) {
    memset(&g_buf, 0, sizeof(EditorBuffer));
    g_buf.tab_size = (tab_size == 4) ? 4 : DEFAULT_TAB_SIZE;
    g_buf.total_lines = 0;
    g_buf.cursor_row = 0;
    g_buf.cursor_col = 0;
    g_buf.visual_col = 0;
    g_buf.top_line = 0;
    g_buf.left_col = 0;
    g_buf.modified = false;

    s_alloc_bank = 1;
    s_alloc_offset = 0x0000;
    s_cpm_user_bank = hbios_get_bank();

    /* Create initial empty line */
    buffer_insert_line(0, "", 0);
}

/*
 * Allocate storage for line text in 512KB far memory
 */
static FarPtr buffer_alloc_far(uint16_t len) {
    FarPtr ptr;
    if (len == 0) {
        ptr.bank = 0;
        ptr.offset = 0;
        return ptr;
    }

    /* If block exceeds 32KB page boundary, advance to next bank */
    if ((uint32_t)s_alloc_offset + len >= EXT_BLOCK_SIZE) {
        s_alloc_bank++;
        s_alloc_offset = 0x0000;
    }

    ptr.bank = s_alloc_bank;
    ptr.offset = s_alloc_offset;
    s_alloc_offset += len;
    return ptr;
}

bool buffer_insert_line(uint16_t row, const char *text, uint16_t len) {
    uint16_t i;
    FarPtr ptr;

    if (g_buf.total_lines >= MAX_LINES) {
        return false;
    }
    if (row > g_buf.total_lines) {
        row = g_buf.total_lines;
    }

    /* Shift lines down */
    for (i = g_buf.total_lines; i > row; i--) {
        g_buf.lines[i] = g_buf.lines[i - 1];
    }

    ptr = buffer_alloc_far(len);
    if (len > 0) {
        hbios_copy(ptr.bank, (void *)ptr.offset, s_cpm_user_bank, text, len);
    }

    g_buf.lines[row].storage = ptr;
    g_buf.lines[row].length = len;
    g_buf.total_lines++;
    g_buf.modified = true;
    return true;
}

bool buffer_delete_line(uint16_t row) {
    uint16_t i;
    if (row >= g_buf.total_lines || g_buf.total_lines <= 1) {
        return false;
    }

    /* Shift lines up */
    for (i = row; i < g_buf.total_lines - 1; i++) {
        g_buf.lines[i] = g_buf.lines[i + 1];
    }

    g_buf.total_lines--;
    g_buf.modified = true;
    return true;
}

bool buffer_get_line(uint16_t row, char *out_text, uint16_t *out_len) {
    LineRef *ref;
    if (row >= g_buf.total_lines) {
        *out_len = 0;
        out_text[0] = '\0';
        return false;
    }

    ref = &g_buf.lines[row];
    *out_len = ref->length;

    if (ref->length == 0) {
        out_text[0] = '\0';
        return true;
    }

    /* Copy from extended 512K bank into local TPA line buffer */
    hbios_copy(s_cpm_user_bank, out_text, ref->storage.bank, (const void *)ref->storage.offset, ref->length);
    out_text[ref->length] = '\0';
    return true;
}

bool buffer_set_line(uint16_t row, const char *text, uint16_t len) {
    FarPtr ptr;
    if (row >= g_buf.total_lines) {
        return false;
    }

    ptr = buffer_alloc_far(len);
    if (len > 0) {
        hbios_copy(ptr.bank, (void *)ptr.offset, s_cpm_user_bank, text, len);
    }

    g_buf.lines[row].storage = ptr;
    g_buf.lines[row].length = len;
    g_buf.modified = true;
    return true;
}

uint16_t buffer_calc_visual_col(const char *text, uint16_t char_col, uint8_t tab_size) {
    uint16_t vcol = 0;
    uint16_t i;
    for (i = 0; i < char_col && text[i] != '\0'; i++) {
        if (text[i] == '\t') {
            vcol = (vcol / tab_size + 1) * tab_size;
        } else {
            vcol++;
        }
    }
    return vcol;
}
