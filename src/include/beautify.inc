;==============================================================================
; BEAUTIFY.INC: Z80 Assembly Beautifier & Column Alignment Subsystem API
;
; Purpose:
;   Defines assembly column formatting metrics, token alignment guidelines,
;   configuration flags, and beautifier execution function signatures.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; Standard Assembly Column Alignment Positions
;------------------------------------------------------------------------------
COL_LABEL_POS		EQU	0	; Column 0: Labels (left-aligned)
COL_OPCODE_POS		EQU	8	; Column 8: Instructions & Directives
COL_OPERAND_POS		EQU	16	; Column 16: Operands & Arguments
COL_COMMENT_POS		EQU	32	; Column 32: Trailing comments

;------------------------------------------------------------------------------
; Beautifier Subsystem Function Entry Points & Register Contracts
;------------------------------------------------------------------------------
; DO_CTRL_Y_BEAUTIFY:
;   Purpose:   Main entry point for Beautifier subsystem (Ctrl+Y).
;              If a block is active, beautifies only lines in selected block.
;              If no block is active, beautifies entire open document.
;              Dispatches to BEAUTIFY.PRL plugin if loaded or loads from disk.
;   Inputs:    None
;   Outputs:   Carry = 0 on success, 1 on error / missing plugin
;   Clobbers:  All registers
;
; BEAUTIFY_DOCUMENT:
;   Purpose:   Format all lines in open document into aligned columns.
;   Inputs:    DOC_TOTAL_LINES
;   Outputs:   Document lines updated in Far RAM buffer
;   Clobbers:  All registers
;
; BEAUTIFY_BLOCK:
;   Purpose:   Format only lines within BLOCK_START_ROW .. BLOCK_END_ROW.
;   Inputs:    BLOCK_START_ROW, BLOCK_END_ROW
;   Outputs:   Block lines updated in Far RAM buffer
;   Clobbers:  All registers
;
; PARSE_ASM_LINE:
;   Purpose:   Tokenize Z80 assembly source line into component fields.
;   Inputs:    HL = Pointer to null-terminated source line
;   Outputs:   Pointers to Label, Mnemonic, Operand, and Comment tokens
;   Clobbers:  AF, BC, DE, HL
;
; ALIGN_COLUMNS:
;   Purpose:   Reconstruct formatted line with tab/space alignment.
;   Inputs:    DE = Destination buffer pointer
;   Outputs:   DE = Pointer to end of formatted string
;   Clobbers:  AF, BC, DE, HL
