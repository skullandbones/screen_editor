;==============================================================================
; BUFFER.INC: Document Buffer & Line Cache Engine API Specifications
;
; Purpose:
;   Defines data structures, buffer layouts, and function signatures for the
;   document line table, active line workspace, virtual slot allocation,
;   and multi-line cache management.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; Buffer Memory Geometry Equates
;------------------------------------------------------------------------------
LINE_STORAGE_STRIDE	EQU	128	; Cache line record stride (bytes)
LINE_SHIFT_BUF_CAP	EQU	256	; Shift buffer capacity for line inserts
SWAP_IO_BUF_CAP		EQU	128	; Virtual memory disk swap buffer size

;------------------------------------------------------------------------------
; Document Buffer Function Entry Points & Register Contracts
;------------------------------------------------------------------------------
; BUFFER_INIT:
;   Purpose:   Initialize Far RAM line tables, clear slot pools, reset cache.
;   Inputs:    None
;   Outputs:   None
;   Clobbers:  AF, BC, DE, HL
;
; GET_LINE_SLOT:
;   Purpose:   Retrieve 16-bit virtual slot ID for document line BC.
;   Inputs:    BC = Document line index (0-based)
;   Outputs:   HL = 16-bit Slot ID (0xFFFF = empty line)
;              Carry = 0 on success, 1 on out-of-range
;   Clobbers:  AF, DE (preserves BC)
;
; SET_LINE_SLOT:
;   Purpose:   Store 16-bit virtual slot ID HL for document line BC.
;   Inputs:    BC = Document line index (0-based)
;              HL = 16-bit Slot ID
;   Outputs:   Carry = 0 on success, 1 on out-of-range
;   Clobbers:  AF, DE (preserves BC, HL)
;
; FETCH_LINE_TO_BUFFER:
;   Purpose:   Load text for document line BC into destination buffer DE.
;   Inputs:    BC = Document line index (0-based)
;              DE = Destination buffer pointer (1024 bytes)
;   Outputs:   HL = Number of characters in loaded line
;              Carry = 0 on success, 1 on read error
;   Clobbers:  AF, BC, DE
;
; STORE_ACTIVE_LINE:
;   Purpose:   Commit currently active line from ACTIVE_LINE_BUF to Far RAM.
;   Inputs:    ACTIVE_LINE_BUF, ACTIVE_LINE_LEN, CUR_DOC_ROW
;   Outputs:   Carry = 0 on success, 1 on out of memory
;   Clobbers:  AF, BC, DE, HL
;
; INSERT_BLANK_LINE:
;   Purpose:   Shift subsequent line slots down by 1 and insert empty slot.
;   Inputs:    BC = Target document line index (0-based)
;   Outputs:   Carry = 0 on success, 1 on document full (MAX_DOC_LINES)
;   Clobbers:  AF, BC, DE, HL
;
; DELETE_DOC_ROW:
;   Purpose:   Delete line at BC and shift subsequent line slots up by 1.
;   Inputs:    BC = Target document line index (0-based)
;   Outputs:   Carry = 0 on success, 1 on error
;   Clobbers:  AF, BC, DE, HL
;
; FLUSH_DIRTY_CACHE:
;   Purpose:   Write any dirty cache lines back to Far RAM or swap.
;   Inputs:    None
;   Outputs:   None
;   Clobbers:  AF, BC, DE, HL
