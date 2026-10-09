;==============================================================================
; SEARCH.INC: Text Search, Forward Find & Replace Engine API
;
; Purpose:
;   Defines search pattern buffer capacities, case sensitivity flags, modal
;   field dimensions, and string matching entry point contracts.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; Search Buffer Capacities & Modal Field Lengths
;------------------------------------------------------------------------------
SEARCH_BUF_MAX		EQU	64	; Max search / replace string characters
FIND_POPUP_FIELD_LEN	EQU	28	; Visible text input width in Find modal
REPLACE_POPUP_FIELD_LEN	EQU	29	; Input width in Search & Replace modal

;------------------------------------------------------------------------------
; Search Function Entry Points & Register Contracts
;------------------------------------------------------------------------------
; DO_CTRL_F_FIND:
;   Purpose:   Display Find modal dialog, collect search string, run search.
;   Inputs:    None
;   Outputs:   Carry = 0 on string found, 1 if not found or cancelled
;   Clobbers:  AF, BC, DE, HL
;
; DO_CTRL_R_REPLACE:
;   Purpose:   Display Replace modal dialog, prompt for strings, run loop.
;   Inputs:    None
;   Outputs:   Carry = 0 on completion, 1 if cancelled
;   Clobbers:  AF, BC, DE, HL
;
; DO_CTRL_N_FIND_NEXT:
;   Purpose:   Repeat previous search forward from current cursor position.
;   Inputs:    SEARCH_BUF (pre-populated search pattern)
;   Outputs:   Carry = 0 on match found, 1 if not found
;   Clobbers:  AF, BC, DE, HL
;
; EXECUTE_FIND_FORWARD:
;   Purpose:   Scan document lines from CUR_DOC_ROW down to DOC_TOTAL_LINES.
;   Inputs:    SEARCH_BUF, SEARCH_LEN, SEARCH_CASE_SENSITIVE
;   Outputs:   Carry = 0 on match (cursor updated), 1 on EOF
;   Clobbers:  AF, BC, DE, HL
;
; FIND_STRING_IN_LINE:
;   Purpose:   Search for pattern in DE (length B) within line HL (length C).
;   Inputs:    DE = Pattern pointer, B = Pattern length
;              HL = Text buffer pointer, C = Text length
;              SEARCH_CASE_SENSITIVE (0 = ignore case, 1 = exact match)
;   Outputs:   Carry = 0 on match found (HL = match start pointer)
;              Carry = 1 on no match
;   Clobbers:  AF, BC, DE, HL
