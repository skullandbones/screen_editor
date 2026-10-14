/*==============================================================================
 * BEAUTIFY.C: Core Subsystem - Z80 Assembly Beautifier & Column Alignment
 *
 * Purpose:
 *   Tokenizes Z80 assembly source lines and reconstructs formatted output
 *   with standard column alignments for labels (col 0), opcodes (col 8),
 *   operands (col 16), and comments (col 32).
 *   C semantic equivalent to src/core/beautify.asm.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#include <string.h>
#include <ctype.h>
#include <stdio.h>
#include "../include/config.h"
#include "../include/buffer.h"
#include "../include/block.h"
#include "../include/beautify.h"
#include "../include/ui.h"
#include "../include/ui_modal.h"

void parse_asm_line(const char *src,
                    char *label, size_t label_max,
                    char *mnemonic, size_t mnem_max,
                    char *operands, size_t op_max,
                    char *comment, size_t comm_max)
{
    const char *p = src;

    if (label && label_max > 0) label[0] = '\0';
    if (mnemonic && mnem_max > 0) mnemonic[0] = '\0';
    if (operands && op_max > 0) operands[0] = '\0';
    if (comment && comm_max > 0) comment[0] = '\0';

    if (!src) return;

    /* Check for leading whole-line comment */
    while (*p == ' ' || *p == '\t') p++;
    if (*p == ';') {
        if (comment) {
            strncpy(comment, p, comm_max - 1);
            comment[comm_max - 1] = '\0';
        }
        return;
    }

    p = src;
    /* 1. Parse Label (if starting at column 0 and not whitespace) */
    if (*p != ' ' && *p != '\t' && *p != ';' && *p != '\0') {
        size_t idx = 0;
        while (*p && *p != ' ' && *p != '\t' && *p != ';') {
            if (label && idx + 1 < label_max) {
                label[idx++] = *p;
            }
            if (*p == ':') {
                p++;
                break;
            }
            p++;
        }
        if (label && idx < label_max) label[idx] = '\0';
    }

    /* 2. Skip whitespace to Mnemonic */
    while (*p == ' ' || *p == '\t') p++;

    /* Check for comment before mnemonic */
    if (*p == ';') {
        if (comment) {
            strncpy(comment, p, comm_max - 1);
            comment[comm_max - 1] = '\0';
        }
        return;
    }

    /* Parse Mnemonic */
    if (*p) {
        size_t idx = 0;
        while (*p && *p != ' ' && *p != '\t' && *p != ';') {
            if (mnemonic && idx + 1 < mnem_max) {
                mnemonic[idx++] = (char)toupper((unsigned char)*p);
            }
            p++;
        }
        if (mnemonic && idx < mnem_max) mnemonic[idx] = '\0';
    }

    /* 3. Skip whitespace to Operands */
    while (*p == ' ' || *p == '\t') p++;

    /* Parse Operands */
    if (*p && *p != ';') {
        size_t idx = 0;
        while (*p && *p != ';') {
            if (operands && idx + 1 < op_max) {
                operands[idx++] = *p;
            }
            p++;
        }
        /* Trim trailing spaces from operands */
        while (idx > 0 && (operands[idx - 1] == ' ' ||
                           operands[idx - 1] == '\t')) {
            idx--;
        }
        if (operands && idx < op_max) operands[idx] = '\0';
    }

    /* 4. Parse Comment */
    while (*p == ' ' || *p == '\t') p++;
    if (*p == ';') {
        if (comment) {
            strncpy(comment, p, comm_max - 1);
            comment[comm_max - 1] = '\0';
        }
    }
}

void align_columns(char *dest, size_t max_len,
                   const char *label,
                   const char *mnemonic,
                   const char *operands,
                   const char *comment)
{
    size_t col = 0;
    dest[0] = '\0';

    /* If it's a standalone comment, output as-is */
    if ((!label || !*label) && (!mnemonic || !*mnemonic) &&
        (!operands || !*operands) && comment && *comment) {
        strncpy(dest, comment, max_len - 1);
        dest[max_len - 1] = '\0';
        return;
    }

    /* Output Label */
    if (label && *label) {
        size_t l_len = strlen(label);
        if (l_len < max_len) {
            strcat(dest, label);
            col += l_len;
        }
    }

    /* Pad to Opcode column */
    if (mnemonic && *mnemonic) {
        while (col < COL_OPCODE_POS && col + 1 < max_len) {
            dest[col++] = '\t';
            dest[col] = '\0';
            break;
        }
        strcat(dest, mnemonic);
        col = strlen(dest);
    }

    /* Pad to Operands column */
    if (operands && *operands) {
        while (col < COL_OPERAND_POS && col + 1 < max_len) {
            dest[col++] = '\t';
            dest[col] = '\0';
            break;
        }
        strcat(dest, operands);
        col = strlen(dest);
    }

    /* Pad to Comment column */
    if (comment && *comment) {
        if (col > 0) {
            dest[col++] = '\t';
            dest[col] = '\0';
        }
        strncat(dest, comment, max_len - col - 1);
    }
}

static void beautify_line(uint16_t row)
{
    char label[24], mnem[16], ops[48], comm[80];
    uint16_t len;

    len = fetch_line_to_buffer(row, g_scratch_line_buf, MAX_ACTIVE_PAYLOAD);
    if (len == 0) return;

    parse_asm_line(g_scratch_line_buf, label, sizeof(label),
                   mnem, sizeof(mnem), ops, sizeof(ops),
                   comm, sizeof(comm));

    checkout_active_line(row);
    align_columns(g_active_line_buf, sizeof(g_active_line_buf),
                  label, mnem, ops, comm);
    g_active_line_len = (uint16_t)strlen(g_active_line_buf);
    commit_active_line();
}

void beautify_document(void)
{
    uint16_t r;
    for (r = 0; r < g_doc_total_lines; r++) {
        beautify_line(r);
    }
    g_doc_modified = 1;
    g_need_screen_render = 1;
}

void beautify_block(uint16_t start_row, uint16_t end_row)
{
    uint16_t r;
    for (r = start_row; r <= end_row && r < g_doc_total_lines; r++) {
        beautify_line(r);
    }
    g_doc_modified = 1;
    g_need_screen_render = 1;
}

int do_ctrl_y_beautify(void)
{
    if (g_block_mode != BLOCK_MODE_OFF) {
        normalize_block_bounds();
        beautify_block(g_norm_start_row, g_norm_end_row);
    } else {
        beautify_document();
    }
    modal_show_notification("Beautify Complete",
                            "Assembly formatting applied.");
    return 0;
}
