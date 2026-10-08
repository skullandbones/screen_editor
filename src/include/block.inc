;==============================================================================
; BLOCK.INC: Block Selection, Clipboard & Multi-Line Editing API
;
; Purpose:
;   Defines block highlighting modes, boundary coordinates, clipboard buffer
;   capacities, and block cut/copy/paste/indentation function signatures.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; Block State Modes
;------------------------------------------------------------------------------
BLOCK_MODE_OFF		EQU	0	; No block selection active
BLOCK_MODE_SELECTING	EQU	1	; Block actively anchoring from cursor
BLOCK_MODE_SOLIDIFIED	EQU	2	; Block solidified (anchor frozen)

;------------------------------------------------------------------------------
; Block Function Entry Points & Register Contracts
;------------------------------------------------------------------------------
; TOGGLE_BLOCK_MODE:
;   Purpose:   Cycle block mode: Off -> Selecting -> Solidified -> Off.
;   Inputs:    BLOCK_MODE, CUR_DOC_ROW, CUR_COL
;   Outputs:   None
;   Clobbers:  AF, BC, DE, HL
;
; CANCEL_BLOCK:
;   Purpose:   Clear active block selection and redraw affected screen rows.
;   Inputs:    None
;   Outputs:   None
;   Clobbers:  AF, BC, DE, HL
;
; SOLIDIFY_BLOCK:
;   Purpose:   Freeze block boundaries; anchor remains fixed when cursor moves.
;   Inputs:    None
;   Outputs:   None
;   Clobbers:  AF, BC, DE, HL
;
; DO_BLOCK_MENU_POPUP:
;   Purpose:   Display block action menu (Copy, Cut, Delete, Indent, Unindent).
;   Inputs:    None
;   Outputs:   Carry = 0 on selection executed, 1 if cancelled
;   Clobbers:  AF, BC, DE, HL
;
; NORMALIZE_BLOCK_BOUNDS:
;   Purpose:   Ensure Start Row/Col is top-left and End Row/Col is bottom-right.
;   Inputs:    BLOCK_ANCHOR_ROW/COL, BLOCK_ACTIVE_ROW/COL
;   Outputs:   NORM_START_ROW/COL, NORM_END_ROW/COL populated
;   Clobbers:  AF, BC, DE, HL
;
; DO_DELETE_BLOCK:
;   Purpose:   Delete text within normalized block bounds from document.
;   Inputs:    None
;   Outputs:   Carry = 0 on success, 1 on error
;   Clobbers:  AF, BC, DE, HL
;
; DO_COPY_BLOCK:
;   Purpose:   Copy text within block bounds to clipboard buffers.
;   Inputs:    None
;   Outputs:   Carry = 0 on success, 1 on clipboard overflow
;   Clobbers:  AF, BC, DE, HL
;
; DO_MOVE_BLOCK:
;   Purpose:   Move text in clipboard / solidified block to cursor position.
;   Inputs:    None
;   Outputs:   Carry = 0 on success, 1 on error
;   Clobbers:  AF, BC, DE, HL
;
; CHECK_CURSOR_IN_BLOCK:
;   Purpose:   Test if cursor position (CUR_DOC_ROW, CUR_COL) lies in block.
;   Inputs:    CUR_DOC_ROW, CUR_COL
;   Outputs:   Zero flag = 1 if inside block, 0 if outside
;   Clobbers:  AF, BC, DE, HL
