/*==============================================================================
 * BEAUTIFY.H: Z80 Assembly Beautifier & Column Alignment Subsystem API
 *
 * Purpose:
 *   Defines assembly column formatting metrics, token alignment guidelines,
 *   configuration flags, and beautifier execution function signatures.
 *   C semantic equivalent header mirroring src/include/beautify.inc.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#ifndef SE_BEAUTIFY_H
#define SE_BEAUTIFY_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "config.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Standard Assembly Column Alignment Positions */
#define COL_LABEL_POS           0   /* Column 0: Labels (left-aligned) */
#define COL_OPCODE_POS          8   /* Column 8: Instructions & Directives */
#define COL_OPERAND_POS         16  /* Column 16: Operands & Arguments */
#define COL_COMMENT_POS         32  /* Column 32: Trailing comments */

/* Beautifier Subsystem Function Entry Points */
int  do_ctrl_y_beautify(void);
void beautify_document(void);
void beautify_block(uint16_t start_row, uint16_t end_row);
void parse_asm_line(const char *src,
                    char *label, size_t label_max,
                    char *mnemonic, size_t mnem_max,
                    char *operands, size_t op_max,
                    char *comment, size_t comm_max);
void align_columns(char *dest, size_t max_len,
                   const char *label,
                   const char *mnemonic,
                   const char *operands,
                   const char *comment);

#ifdef __cplusplus
}
#endif

#endif /* SE_BEAUTIFY_H */
