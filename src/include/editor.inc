;==============================================================================
; EDITOR.INC: Core Editor Engine, Cursor Navigation & Edit Primitives API
;
; Purpose:
;   Defines editor state variables, coordinate conventions, key dispatchers,
;   and text manipulation primitive signatures.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; Editor Function Entry Points & Register Contracts
;------------------------------------------------------------------------------
; MAIN_LOOP:
;   Purpose:   Central interactive event loop. Reads keys and dispatches.
;   Inputs:    None
;   Outputs:   Does not return (exits via EXIT_PROGRAM or splash return)
;   Clobbers:  All registers
;
; DO_CHAR_INSERT:
;   Purpose:   Insert character in A at current cursor position (CUR_COL).
;   Inputs:    A = ASCII character to insert
;   Outputs:   Carry = 0 on success, 1 on line overflow (> 1000 chars)
;   Clobbers:  AF, BC, DE, HL
;
; DO_BACKSPACE:
;   Purpose:   Delete character to left of cursor; join lines if at col 0.
;   Inputs:    None
;   Outputs:   None
;   Clobbers:  AF, BC, DE, HL
;
; DO_DELETE:
;   Purpose:   Delete character under cursor; pull up next line if at EOL.
;   Inputs:    None
;   Outputs:   None
;   Clobbers:  AF, BC, DE, HL
;
; DO_ENTER:
;   Purpose:   Split current line at cursor and advance to next line.
;   Inputs:    None
;   Outputs:   None
;   Clobbers:  AF, BC, DE, HL
;
; GOTO_LINE_HL:
;   Purpose:   Navigate cursor and viewport directly to line HL (1-based).
;   Inputs:    HL = Target line number (1..DOC_TOTAL_LINES)
;   Outputs:   None
;   Clobbers:  AF, BC, DE, HL
;
; CALC_VISUAL_COL:
;   Purpose:   Calculate 0-based visual column accounting for TAB expansion.
;   Inputs:    ACTIVE_LINE_BUF, CUR_COL
;   Outputs:   HL = Visual column (0..1000)
;   Clobbers:  AF, BC, DE (preserves HL as result)
;
; LOCATE_CURSOR:
;   Purpose:   Reposition hardware/terminal cursor to match document cursor.
;   Inputs:    CUR_DOC_ROW, TOP_DOC_ROW, CUR_COL, HORIZ_PAN_OFFSET
;   Outputs:   None
;   Clobbers:  AF, BC, DE, HL
