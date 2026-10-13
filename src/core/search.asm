;==============================================================================
; SEARCH.ASM: Core Subsystem - Text Search, Find & Replace Engine
;
; Purpose:
;   Implements interactive Find modal dialog (Ctrl+F), Find Next (Ctrl+N),
;   Find Previous, forward and backward pattern matching, and Search &
;   Replace (Ctrl+R) with interactive confirmation.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; SEARCH AND REPLACE ENGINE
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; DO_FIND_UI: Centered modal pop-up dialog for Find Text command (Ctrl+F)
;
; Purpose:
;   Displays centered 50x7 modal query dialog prompting for search pattern.
;   Supports pattern text input, Backspace, Tab (case sensitivity toggle),
;   and Enter to execute forward search.
;
; Call Usage / Protocol:
;   Jumped to from MAIN_LOOP on Ctrl+F.
;
; Inputs:
;   ACTIVE_COLS, ACTIVE_ROWS.
;
; Outputs:
;   Carry = 0 on match found; Carry = 1 on cancel or not found.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_FIND_UI:
	; Check if starting from an active block
	CALL CHECK_START_FROM_BLOCK
	; B = character count in SEARCH_INPUT_BUF (0..FIND_POPUP_FIELD_LEN)
	; If B > 0, SEARCH_INPUT_BUF has block text, and (CUR_DOC_ROW, CUR_COL)
	; set to block start

	; Setup prompt and edit box
	CALL DRAW_FIND_POPUP_FULL

FIND_UI_KEY_LOOP:
	CALL GET_KEY

	; Check ESC / escape sequence
	CP KEY_ESC
	JP Z,FIND_UI_CHECK_ESC

	; Check Enter -> Confirm
	CP KEY_ENTER
	JP Z,FIND_UI_ENTER

	; Check Backspace / Delete
	CP KEY_BACKSPACE
	JR Z,FIND_UI_BS
	CP KEY_DEL
	JR Z,FIND_UI_BS

	; Check Ctrl+I (Tab) -> Toggle case sensitivity
	CP KEY_CTRL_I
	JR Z,FIND_UI_TOGGLE_CASE

	; Check printable character (ASCII 32..126)
	CP ' '
	JR C,FIND_UI_KEY_LOOP
	CP 127
	JR NC,FIND_UI_KEY_LOOP

	; Check buffer capacity (FIND_POPUP_FIELD_LEN = 29)
	LD C,A				; Save character
	LD A,B
	CP FIND_POPUP_FIELD_LEN
	JR NC,FIND_UI_KEY_LOOP

	; Append to SEARCH_INPUT_BUF
	LD HL,SEARCH_INPUT_BUF
	LD E,B
	LD D,0
	ADD HL,DE
	LD (HL),C
	INC HL
	LD (HL),0			; Null terminate
	INC B

	; Echo character
	LD A,C
	CALL PUTC
	JR FIND_UI_KEY_LOOP

FIND_UI_BS:
	LD A,B
	OR A
	JR Z,FIND_UI_KEY_LOOP		; Nothing to backspace

	DEC B
	LD HL,SEARCH_INPUT_BUF
	LD E,B
	LD D,0
	ADD HL,DE
	LD (HL),0			; Null terminate at new length

	; Visual backspace: \x08 \x20 \x08
	LD A,008H
	CALL PUTC
	LD A,' '
	CALL PUTC
	LD A,008H
	CALL PUTC
	JR FIND_UI_KEY_LOOP

FIND_UI_TOGGLE_CASE:
	; Toggle SEARCH_CASE_SENSITIVE (0 <-> 1)
	LD A,(SEARCH_CASE_SENSITIVE)
	XOR 1
	LD (SEARCH_CASE_SENSITIVE),A

	; Redraw popup dialog
	LD A,(POPUP_START_ROW)
	LD (POPUP_ROW),A
	CALL DRAW_FIND_POPUP_BODY
	JR FIND_UI_KEY_LOOP

DRAW_FIND_POPUP_FULL:
	; 1. Calculate POPUP_COL = ((ACTIVE_COLS - 50) / 2) + 1
	LD A,(ACTIVE_COLS)
	SUB 50
	SRL A
	INC A
	LD (POPUP_COL),A

	; 2. Calculate POPUP_ROW = ((ACTIVE_ROWS - 7) / 2) + 1
	LD A,(ACTIVE_ROWS)
	SUB 7
	SRL A
	INC A
	LD (POPUP_ROW),A
	LD (POPUP_START_ROW),A

DRAW_FIND_POPUP_BODY:
	CALL TERM_HIDE_CURSOR

	; Line 1: Border
	CALL POPUP_PRINT_BORDER

	; Line 2: Title
	CALL POPUP_LOCATE_NEXT
	LD DE,STR_FIND_POPUP_TITLE
	CALL PRINT_STR

	; Line 3: Border
	CALL POPUP_PRINT_BORDER

	; Line 4: Match mode (Description)
	CALL POPUP_LOCATE_NEXT
	LD A,(SEARCH_CASE_SENSITIVE)
	OR A
	JR Z,DFP_MODE_INSENS
	LD DE,STR_FIND_POPUP_MODE_EXACT
	JR DFP_PRINT_MODE
DFP_MODE_INSENS:
	LD DE,STR_FIND_POPUP_MODE_INSENS
DFP_PRINT_MODE:
	CALL PRINT_STR

	; Line 5: Prompt and input field (Query Line)
	CALL POPUP_LOCATE_NEXT
	LD DE,STR_FIND_POPUP_PROMPT
	CALL PRINT_STR
	; Echo prefilled / current SEARCH_INPUT_BUF if B > 0
	LD A,B
	OR A
	JR Z,DFP_PAD_SPACES
	LD DE,SEARCH_INPUT_BUF
	CALL PRINT_STR
DFP_PAD_SPACES:
	LD A,FIND_POPUP_FIELD_LEN
	SUB B
	JR Z,DFP_BOX_CLOSE
	LD C,A
DFP_PAD_LOOP:
	LD A,' '
	CALL PUTC
	DEC C
	JR NZ,DFP_PAD_LOOP
DFP_BOX_CLOSE:
	LD DE,STR_FIND_POPUP_BOX_CLOSE
	CALL PRINT_STR

	; Line 6: Keys
	CALL POPUP_LOCATE_NEXT
	LD DE,STR_FIND_POPUP_KEYS
	CALL PRINT_STR

	; Line 7: Border
	CALL POPUP_PRINT_BORDER

	; Position cursor inside popup box at
	; (POPUP_START_ROW + 4, POPUP_COL + 14 + B)
	LD A,(POPUP_START_ROW)
	ADD A,4
	LD H,A
	LD A,(POPUP_COL)
	ADD A,14
	ADD A,B
	LD L,A
	CALL LOCATE_RC
	CALL TERM_SHOW_CURSOR
	RET

FIND_UI_CHECK_ESC:
	; Check if escape sequence
	PUSH BC
	LD BC,ESC_TIMEOUT_LOOPS
FIND_WAIT_ESC:
	CALL CHECK_KEY_READY
	JR NZ,FIND_GOT_ESC_SEQ
	DEC BC
	LD A,B
	OR C
	JR NZ,FIND_WAIT_ESC
	POP BC
	JR FIND_UI_CANCEL

FIND_GOT_ESC_SEQ:
	CALL DRAIN_ESC_SEQUENCE
	POP BC
	JP FIND_UI_KEY_LOOP

FIND_UI_CANCEL:
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	CALL LOCATE_CURSOR
	SCF
	RET

FIND_UI_ENTER:
	; If B > 0, copy SEARCH_INPUT_BUF into SEARCH_BUF
	LD A,B
	OR A
	JR Z,FIND_CHECK_PREV

	; Copy B bytes + null
	LD (SEARCH_LEN),A
	LD HL,SEARCH_INPUT_BUF
	LD DE,SEARCH_BUF
	LD C,A
	LD B,0
	INC BC				; Include null terminator
	LDIR

	; Reset SEARCH_EVER_FOUND for new search pattern
	XOR A
	LD (SEARCH_EVER_FOUND),A
	JR FIND_EXEC_SEARCH

FIND_CHECK_PREV:
	; B == 0: check if existing SEARCH_LEN > 0
	LD A,(SEARCH_LEN)
	OR A
	JR Z,FIND_UI_CANCEL		; No previous pattern, cancel

FIND_EXEC_SEARCH:
	; Erase find popup dialog before running search so screen is clean
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	CALL FIND_STRING_FORWARD
	RET


;------------------------------------------------------------------------------
; CHECK_START_FROM_BLOCK: Set initial search coordinates based on active block
;
; Purpose:
;   If an active block selection exists, aligns search start position with
;   the block boundary rather than current cursor position.
;
; Call Usage / Protocol:
;   Called via CALL prior to executing search.
;
; Inputs:
;   BLOCK_ACTIVE, normalized block bounds.
;
; Outputs:
;   Search starting coordinates set.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
CHECK_START_FROM_BLOCK:
	LD HL,SEARCH_INPUT_BUF
	LD (HL),0
	LD B,0

	LD A,(BLOCK_ACTIVE)
	OR A
	RET Z				; No block active, return with B=0

	CP 1
	JR NZ,CSFB_CHECK_SOLID
	; BLOCK_ACTIVE == 1: User is actively in selection mode!
	; Implied Ctrl-K: solidify dynamic selection
	CALL SOLIDIFY_BLOCK
	JR CSFB_EXTRACT

CSFB_CHECK_SOLID:
	; BLOCK_ACTIVE == 2: Check if cursor is at or in the block!
	; If cursor has navigated away from the block, cancel block and do
	; normal find!
	CALL NORMALIZE_BLOCK_BOUNDS

	; Check if CUR_DOC_ROW is within [BLOCK_START_ROW, BLOCK_END_ROW]
	LD HL,(CUR_DOC_ROW)
	LD DE,(BLOCK_START_ROW)
	OR A
	SBC HL,DE
	; CUR_DOC_ROW < BLOCK_START_ROW -> moved away!
	JR C,CSFB_CANCEL_OLD_BLOCK

	LD HL,(BLOCK_END_ROW)
	LD DE,(CUR_DOC_ROW)
	OR A
	SBC HL,DE
	; CUR_DOC_ROW > BLOCK_END_ROW -> moved away!
	JR C,CSFB_CANCEL_OLD_BLOCK

	; On row: for single-line block, check if CUR_COL is within
	; [BLOCK_START_COL, BLOCK_END_COL]
	LD HL,(BLOCK_START_ROW)
	LD DE,(BLOCK_END_ROW)
	OR A
	SBC HL,DE
	JR NZ,CSFB_EXTRACT		; Multi-line row within range: ok

	; Single-line block:
	LD A,(CUR_COL)
	LD HL,BLOCK_START_COL
	CP (HL)
	; CUR_COL < BLOCK_START_COL -> moved away!
	JR C,CSFB_CANCEL_OLD_BLOCK
	LD HL,BLOCK_END_COL
	CP (HL)
	; CUR_COL == BLOCK_END_COL (at end of block): ok!
	JR Z,CSFB_EXTRACT
	JR C,CSFB_EXTRACT		; CUR_COL < BLOCK_END_COL: ok!
	; CUR_COL > BLOCK_END_COL: moved away!

CSFB_CANCEL_OLD_BLOCK:
	CALL CANCEL_BLOCK
	RET				; Return with B=0 (empty prompt)

CSFB_EXTRACT:

	; Set cursor to (BLOCK_START_ROW, BLOCK_START_COL)
	LD HL,(BLOCK_START_ROW)
	LD (CUR_DOC_ROW),HL
	LD A,(BLOCK_START_COL)
	LD (CUR_COL),A
	LD (TARGET_COL),A

	; Read block text from BLOCK_START_ROW
	LD BC,(BLOCK_START_ROW)
	CALL ENSURE_CACHE_WINDOW	; HL = LINE_STORAGE line start

	; Advance HL to BLOCK_START_COL
	LD A,(BLOCK_START_COL)
	LD E,A
	LD D,0
	ADD HL,DE			; HL = start of block text in line

	; Calculate block length on this row
	; Check if BLOCK_START_ROW == BLOCK_END_ROW
	LD DE,(BLOCK_END_ROW)
	LD BC,(BLOCK_START_ROW)
	LD A,B
	CP D
	JR NZ,CSFB_DIFF_ROW
	LD A,C
	CP E
	JR NZ,CSFB_DIFF_ROW

	; Same row: length = BLOCK_END_COL - BLOCK_START_COL
	LD A,(BLOCK_START_COL)
	LD C,A
	LD A,(BLOCK_END_COL)
	SUB C				; A = BLOCK_END_COL - BLOCK_START_COL
	JR CSFB_GOT_LEN

CSFB_DIFF_ROW:
	; Spans multiple lines: take up to 29 chars from start line
	LD A,FIND_POPUP_FIELD_LEN

CSFB_GOT_LEN:
	; A = max chars to copy from block. Limit to FIND_POPUP_FIELD_LEN (29)
	CP FIND_POPUP_FIELD_LEN+1
	JR C,CSFB_LEN_OK
	LD A,FIND_POPUP_FIELD_LEN
CSFB_LEN_OK:
	LD C,A				; C = max chars
	OR A
	RET Z				; 0 chars? Return B=0

	LD DE,SEARCH_INPUT_BUF
	LD B,0				; B counts copied chars
CSFB_COPY_LOOP:
	LD A,(HL)
	CP ' '
	JR C,CSFB_COPY_DONE		; Stop at null (0) or control chars
	CP 127
	JR NC,CSFB_COPY_DONE
	LD (DE),A
	INC HL
	INC DE
	INC B
	LD A,B
	CP C
	JR NC,CSFB_COPY_DONE
	JR CSFB_COPY_LOOP

CSFB_COPY_DONE:
	XOR A
	LD (DE),A			; Null terminate SEARCH_INPUT_BUF
	RET

;------------------------------------------------------------------------------
; DO_FIND_NEXT: Search forward for next occurrence of search pattern (F3 / ^N)
;
; Purpose:
;   Advances cursor by one character past current match and searches forward
;   for SEARCH_INPUT_BUF, wrapping around EOF if necessary.
;
; Call Usage / Protocol:
;   Called via CALL from MAIN_LOOP on F3 or Ctrl+N.
;
; Inputs:
;   SEARCH_INPUT_BUF, CUR_DOC_ROW, CUR_COL.
;
; Outputs:
;   Cursor moved to match and highlighted; status pop-up if not found.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_FIND_NEXT:
	LD A,(SEARCH_LEN)
	OR A
	JP Z,DO_FIND_UI			; If no search pattern set, open Find UI

	; Save current position in case search fails
	LD HL,(CUR_DOC_ROW)
	LD (PREV_START_ROW_TEMP),HL
	LD A,(CUR_COL)
	LD (PREV_START_COL_TEMP),A

	; Check if active block is solidified (state 2)
	LD A,(BLOCK_ACTIVE)
	CP 2
	JR NZ,DFN_NORMAL_START

	; Solidified block match: wrap limit is BLOCK_START_ROW, BLOCK_START_COL
	LD HL,(BLOCK_START_ROW)
	LD (SEARCH_START_ROW),HL
	LD A,(BLOCK_START_COL)
	LD (SEARCH_START_COL),A

	; Advance from BLOCK_START_COL by 1
	INC A
	LD (CUR_COL),A
	JR DFN_DO_SEARCH

DFN_NORMAL_START:
	LD HL,(CUR_DOC_ROW)
	LD (SEARCH_START_ROW),HL
	LD A,(CUR_COL)
	LD (SEARCH_START_COL),A
	INC A
	LD (CUR_COL),A

DFN_DO_SEARCH:
	XOR A
	LD (SEARCH_WRAPPED),A
	CALL FIND_STRING_FORWARD_CONT
	RET NC				; Match found

	; Failed / completed: restore original position
	LD HL,(PREV_START_ROW_TEMP)
	LD (CUR_DOC_ROW),HL
	LD A,(PREV_START_COL_TEMP)
	LD (CUR_COL),A
	LD (TARGET_COL),A
	CALL LOCATE_CURSOR
	RET

;------------------------------------------------------------------------------
; DO_FIND_PREV: Search backward for previous occurrence of pattern (Shift+F3)
;
; Purpose:
;   Steps cursor back one character and searches backward through document
;   lines for SEARCH_INPUT_BUF, wrapping around top if necessary.
;
; Call Usage / Protocol:
;   Called via CALL from MAIN_LOOP on Shift+F3.
;
; Inputs:
;   SEARCH_INPUT_BUF, CUR_DOC_ROW, CUR_COL.
;
; Outputs:
;   Cursor moved to match and highlighted; status pop-up if not found.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_FIND_PREV:
	LD A,(SEARCH_LEN)
	OR A
	JP Z,DO_FIND_UI			; If no search pattern set, open Find UI

	; Save current position in case search fails
	LD HL,(CUR_DOC_ROW)
	LD (PREV_START_ROW_TEMP),HL
	LD A,(CUR_COL)
	LD (PREV_START_COL_TEMP),A

	; Check if active block is solidified (state 2)
	LD A,(BLOCK_ACTIVE)
	CP 2
	JR NZ,DFP_NORMAL_START

	; Solidified block match: wrap limit is BLOCK_START_ROW, BLOCK_START_COL
	LD HL,(BLOCK_START_ROW)
	LD (SEARCH_START_ROW),HL
	LD A,(BLOCK_START_COL)
	LD (SEARCH_START_COL),A

	; Step backward from BLOCK_START_COL
	LD (CUR_COL),A
	CALL STEP_BACK_ONE_CHAR
	JR DFP_DO_SEARCH

DFP_NORMAL_START:
	LD HL,(CUR_DOC_ROW)
	LD (SEARCH_START_ROW),HL
	LD A,(CUR_COL)
	LD (SEARCH_START_COL),A
	CALL STEP_BACK_ONE_CHAR

DFP_DO_SEARCH:
	XOR A
	LD (SEARCH_WRAPPED),A
	CALL FIND_STRING_BACKWARD_CONT
	RET NC				; Match found

	; Failed / completed: restore original position
	LD HL,(PREV_START_ROW_TEMP)
	LD (CUR_DOC_ROW),HL
	LD A,(PREV_START_COL_TEMP)
	LD (CUR_COL),A
	LD (TARGET_COL),A
	CALL LOCATE_CURSOR
	RET

;------------------------------------------------------------------------------
; STEP_BACK_ONE_CHAR: Move cursor back one character or wrap to preceding row
;
; Purpose:
;   Decrements CUR_COL if > 0; otherwise moves to preceding row and positions
;   at end of that line.
;
; Call Usage / Protocol:
;   Called via CALL by reverse search routines.
;
; Inputs:
;   CUR_DOC_ROW, CUR_COL.
;
; Outputs:
;   CUR_DOC_ROW and CUR_COL updated.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
STEP_BACK_ONE_CHAR:
	LD A,(CUR_COL)
	OR A
	JR Z,SBOC_PREV_LINE
	DEC A
	LD (CUR_COL),A
	RET
SBOC_PREV_LINE:
	LD HL,(CUR_DOC_ROW)
	LD A,H
	OR L
	JR Z,SBOC_WRAP_EOF
	DEC HL
	LD (CUR_DOC_ROW),HL
	JR SBOC_SET_END
SBOC_WRAP_EOF:
	LD HL,(DOC_TOTAL_LINES)
	DEC HL
	LD (CUR_DOC_ROW),HL
SBOC_SET_END:
	LD A,255
	LD (CUR_COL),A
	RET

;------------------------------------------------------------------------------
; HIGHLIGHT_FOUND_BLOCK: Activate visual block highlight around matched text
;
; Purpose:
;   Sets BLOCK_ACTIVE = 2 (solidified), anchor row/col at match start,
;   and end row/col at match end, visually highlighting found text.
;
; Call Usage / Protocol:
;   Called via CALL when search locates a pattern match.
;
; Inputs:
;   CUR_DOC_ROW, CUR_COL, SEARCH_LEN.
;
; Outputs:
;   Block highlight markers set; screen flagged for redraw.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
HIGHLIGHT_FOUND_BLOCK:
	PUSH HL
	PUSH AF
	LD HL,(CUR_DOC_ROW)
	LD (BLOCK_START_ROW),HL
	LD (BLOCK_END_ROW),HL
	LD (BLOCK_ANCHOR_ROW),HL
	LD A,(CUR_COL)
	LD (BLOCK_START_COL),A
	LD (BLOCK_ANCHOR_COL),A
	LD HL,SEARCH_LEN
	ADD A,(HL)
	LD (BLOCK_END_COL),A
	LD A,2				; State 2 = Solidified / Locked
	LD (BLOCK_ACTIVE),A
	POP AF
	POP HL
	RET

;------------------------------------------------------------------------------
; FIND_STRING_FORWARD: Search forward through document for pattern string
;
; Purpose:
;   Iterates forward through document lines from current position searching
;   for SEARCH_INPUT_BUF. Wraps to line 0 at EOF and terminates when full
;   cycle completes.
;
; Call Usage / Protocol:
;   Called via CALL by DO_FIND_UI, DO_FIND_NEXT, and DO_REPLACE_UI.
;
; Inputs:
;   SEARCH_INPUT_BUF, CUR_DOC_ROW, CUR_COL, SEARCH_CASE_SENSITIVE.
;
; Outputs:
;   Carry = 0 on match found; Carry = 1 if pattern not found.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
FIND_STRING_FORWARD:
	LD A,(SEARCH_LEN)
	OR A
	SCF
	RET Z				; Cannot search empty string

	; Record starting position for wrap limit detection
	LD HL,(CUR_DOC_ROW)
	LD (SEARCH_START_ROW),HL
	LD A,(CUR_COL)
	LD (SEARCH_START_COL),A
	XOR A
	LD (SEARCH_WRAPPED),A

FIND_STRING_FORWARD_CONT:
	LD A,1
	LD (SEARCH_FIRST_LINE),A

SEARCH_LINE_LOOP:
	; Fetch line from cache/Far RAM
	LD BC,(CUR_DOC_ROW)
	CALL ENSURE_CACHE_WINDOW	; HL = pointer to line in LINE_STORAGE

	; Calculate line length in bytes (null terminated)
	PUSH HL
	LD C,0				; C = byte length
SCAN_LINE_LEN:
	LD A,(HL)
	OR A
	JR Z,SCAN_LINE_LEN_DONE
	INC HL
	INC C
	LD A,C
	CP MAX_LINE_STRIDE-2
	JR C,SCAN_LINE_LEN
SCAN_LINE_LEN_DONE:
	POP HL				; HL = line start
	; Line length is in C (0..120)

	; Check if line length >= SEARCH_LEN
	LD A,(SEARCH_LEN)
	CP C
	JR Z,CAN_MATCH_LEN
	JP NC,ADVANCE_NEXT_LINE		; If SEARCH_LEN > C, cannot match

CAN_MATCH_LEN:
	; max_col = C - SEARCH_LEN
	LD A,(SEARCH_LEN)
	LD E,A
	LD A,C
	SUB E
	LD C,A				; C = max_col (0..119)

	; Determine candidate start column
	LD A,(SEARCH_FIRST_LINE)
	OR A
	JR Z,START_COL_ZERO
	LD A,(CUR_COL)
	JR GOT_START_COL
START_COL_ZERO:
	XOR A
GOT_START_COL:
	LD B,A				; B = candidate column (cand_col)

	; If cand_col > max_col, no match on this line
	LD A,C
	CP B
	JP C,ADVANCE_NEXT_LINE

SCAN_COL_LOOP:
	; If wrapped and on SEARCH_START_ROW, do not search beyond
	; SEARCH_START_COL
	LD A,(SEARCH_WRAPPED)
	OR A
	JR Z,CHECK_COL_MATCH
	PUSH HL
	LD HL,(CUR_DOC_ROW)
	LD DE,(SEARCH_START_ROW)
	OR A
	SBC HL,DE
	POP HL
	JR NZ,CHECK_COL_MATCH
	; On SEARCH_START_ROW wrapped:
	LD A,(SEARCH_EVER_FOUND)
	OR A
	JR NZ,SCL_WRAP_EXCLUSIVE

	; Inclusive (initial find): B > SEARCH_START_COL -> not found
	LD A,(SEARCH_START_COL)
	CP B
	JP C,SEARCH_NOT_FOUND
	JR CHECK_COL_MATCH

SCL_WRAP_EXCLUSIVE:
	; Exclusive (repeat find / replace): B >= SEARCH_START_COL -> search
	; completed
	LD A,(SEARCH_START_COL)
	LD E,A
	LD A,B
	CP E
	JP NC,SEARCH_NOT_FOUND
	JR CHECK_COL_MATCH

CHECK_COL_MATCH:
	; Check match at column B:
	PUSH BC
	PUSH HL
	LD E,B
	LD D,0
	ADD HL,DE			; HL = line_start + cand_col
	CALL MATCH_SUBSTRING
	POP HL
	POP BC
	JR Z,MATCH_FOUND_AT_B

	; Not matched, advance cand_col
	INC B
	LD A,C				; C = max_col
	CP B
	JR NC,SCAN_COL_LOOP
	JP ADVANCE_NEXT_LINE

MATCH_FOUND_AT_B:
	LD A,B
	LD (CUR_COL),A
	LD (TARGET_COL),A

	; Check if CUR_DOC_ROW is currently on visible screen
	LD HL,(CUR_DOC_ROW)
	LD DE,(TOP_DOC_ROW)
	OR A
	SBC HL,DE			; HL = CUR_DOC_ROW - TOP_DOC_ROW
	JR C,DO_SEARCH_RECENTER
	LD A,(ACTIVE_ROWS)
	DEC A
	LD E,A
	LD D,0
	OR A
	SBC HL,DE
	JR NC,DO_SEARCH_RECENTER
	JR SEARCH_POS_OK

DO_SEARCH_RECENTER:
	PUSH BC
	LD HL,(CUR_DOC_ROW)
	INC HL				; 1-indexed for GOTO_LINE_HL
	CALL GOTO_LINE_HL
	POP BC
	LD A,B
	LD (CUR_COL),A
	LD (TARGET_COL),A

SEARCH_POS_OK:
	; Mark that at least one match was found
	LD A,1
	LD (SEARCH_EVER_FOUND),A

	; Solidify block highlight on match
	CALL HIGHLIGHT_FOUND_BLOCK

	; Position cursor at the next character position past the end of the
	; block
	LD A,(BLOCK_END_COL)
	LD (CUR_COL),A
	CALL CALC_VISUAL_COL
	LD (TARGET_COL),A

	LD A,1
	LD (NEED_SCREEN_RENDER),A
	LD (NEED_STATUS_RENDER),A
	OR A				; Clear carry (success)
	RET

ADVANCE_NEXT_LINE:
	XOR A
	LD (SEARCH_FIRST_LINE),A
	LD HL,(CUR_DOC_ROW)
	INC HL
	LD (CUR_DOC_ROW),HL
	LD DE,(DOC_TOTAL_LINES)
	OR A
	SBC HL,DE
	JR C,CHECK_WRAP_LIMIT

	; Reached EOF: wrap around to line 0
	LD A,(SEARCH_WRAPPED)
	OR A
	JP NZ,SEARCH_NOT_FOUND		; Already wrapped once!
	LD A,1
	LD (SEARCH_WRAPPED),A
	LD HL,0
	LD (CUR_DOC_ROW),HL

CHECK_WRAP_LIMIT:
	LD A,(SEARCH_WRAPPED)
	OR A
	JP Z,SEARCH_LINE_LOOP		; If not wrapped, continue

	; If wrapped, compare CUR_DOC_ROW with SEARCH_START_ROW
	LD HL,(CUR_DOC_ROW)
	LD DE,(SEARCH_START_ROW)
	OR A
	SBC HL,DE
	JP C,SEARCH_LINE_LOOP	; CUR_DOC_ROW < SEARCH_START_ROW: continue
	; CUR_DOC_ROW == SEARCH_START_ROW: do wrapped pass
	JP Z,SEARCH_LINE_LOOP
	JP SEARCH_NOT_FOUND		; CUR_DOC_ROW > SEARCH_START_ROW: done

;------------------------------------------------------------------------------
; FIND_STRING_BACKWARD: Search backward through document for pattern string
;
; Purpose:
;   Iterates backward through document lines from current position searching
;   for SEARCH_INPUT_BUF. Wraps to last line at top and terminates when full
;   cycle completes.
;
; Call Usage / Protocol:
;   Called via CALL by DO_FIND_PREV.
;
; Inputs:
;   SEARCH_INPUT_BUF, CUR_DOC_ROW, CUR_COL, SEARCH_CASE_SENSITIVE.
;
; Outputs:
;   Carry = 0 on match found; Carry = 1 if pattern not found.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
FIND_STRING_BACKWARD:
	LD A,(SEARCH_LEN)
	OR A
	SCF
	RET Z				; Cannot search empty string

	; Record starting position for wrap limit detection
	LD HL,(CUR_DOC_ROW)
	LD (SEARCH_START_ROW),HL
	LD A,(CUR_COL)
	LD (SEARCH_START_COL),A
	XOR A
	LD (SEARCH_WRAPPED),A

FIND_STRING_BACKWARD_CONT:
	LD A,1
	LD (SEARCH_FIRST_LINE),A

SEARCH_BW_LINE_LOOP:
	; Fetch line from cache/Far RAM
	LD BC,(CUR_DOC_ROW)
	CALL ENSURE_CACHE_WINDOW	; HL = pointer to line in LINE_STORAGE

	; Calculate line length in bytes (null terminated)
	PUSH HL
	LD C,0				; C = byte length
SCAN_BW_LINE_LEN:
	LD A,(HL)
	OR A
	JR Z,SCAN_BW_LINE_LEN_DONE
	INC HL
	INC C
	LD A,C
	CP MAX_LINE_STRIDE-2
	JR C,SCAN_BW_LINE_LEN
SCAN_BW_LINE_LEN_DONE:
	POP HL				; HL = line start
	; Line length is in C (0..120)

	; Check if line length >= SEARCH_LEN
	LD A,(SEARCH_LEN)
	CP C
	JR Z,BW_CAN_MATCH_LEN
	JP NC,RETREAT_PREV_LINE		; If SEARCH_LEN > C, cannot match

BW_CAN_MATCH_LEN:
	; max_col = C - SEARCH_LEN
	LD A,(SEARCH_LEN)
	LD E,A
	LD A,C
	SUB E
	LD E,A				; E = max_col (0..119)

	; Determine candidate start column in B
	LD A,(SEARCH_FIRST_LINE)
	OR A
	JR Z,BW_START_COL_MAX

	; On first line: clamp start col to max_col
	LD A,(CUR_COL)
	CP E
	JR C,BW_GOT_FIRST_COL		; If CUR_COL < max_col, ok
	LD A,E				; Else clamp to max_col
BW_GOT_FIRST_COL:
	LD (SEARCH_START_COL),A		; Store clamped start col for wrap limit
	JR BW_GOT_START_COL

BW_START_COL_MAX:
	LD A,E				; Start at max_col

BW_GOT_START_COL:
	LD B,A				; B = candidate column (cand_col)

SCAN_BW_COL_LOOP:
	; If wrapped and on SEARCH_START_ROW, do not search before
	; SEARCH_START_COL
	LD A,(SEARCH_WRAPPED)
	OR A
	JR Z,BW_CHECK_COL_MATCH
	PUSH HL
	LD HL,(CUR_DOC_ROW)
	LD DE,(SEARCH_START_ROW)
	OR A
	SBC HL,DE
	POP HL
	JR NZ,BW_CHECK_COL_MATCH

	; On SEARCH_START_ROW wrapped:
	LD A,(SEARCH_EVER_FOUND)
	OR A
	JR NZ,BW_WRAP_EXCLUSIVE

	; Inclusive (initial find): B < SEARCH_START_COL -> not found
	LD A,(SEARCH_START_COL)
	LD E,A
	LD A,B
	CP E
	JP C,SEARCH_NOT_FOUND
	JR BW_CHECK_COL_MATCH

BW_WRAP_EXCLUSIVE:
	; Exclusive (repeat find / replace): B <= SEARCH_START_COL -> search
	; completed
	LD A,(SEARCH_START_COL)
	LD E,A
	LD A,B
	CP E
	JP Z,SEARCH_NOT_FOUND
	JP C,SEARCH_NOT_FOUND
	JR BW_CHECK_COL_MATCH

BW_CHECK_COL_MATCH:
	; Check match at column B:
	PUSH BC
	PUSH HL
	LD E,B
	LD D,0
	ADD HL,DE			; HL = line_start + cand_col
	CALL MATCH_SUBSTRING
	POP HL
	POP BC
	JP Z,MATCH_FOUND_AT_B

	; Not matched: step B backward
	LD A,B
	OR A
	JR Z,RETREAT_PREV_LINE	; Reached col 0: retreat to previous line
	DEC B
	JR SCAN_BW_COL_LOOP

RETREAT_PREV_LINE:
	XOR A
	LD (SEARCH_FIRST_LINE),A

	; Check if CUR_DOC_ROW == 0
	LD HL,(CUR_DOC_ROW)
	LD A,H
	OR L
	JR Z,BW_WRAP_EOF

	; Previous line: CUR_DOC_ROW - 1
	DEC HL
	LD (CUR_DOC_ROW),HL
	JR CHECK_BW_WRAP_LIMIT

BW_WRAP_EOF:
	; Wrapped around to end of file
	LD A,(SEARCH_WRAPPED)
	OR A
	JP NZ,SEARCH_NOT_FOUND		; Already wrapped once!
	LD A,1
	LD (SEARCH_WRAPPED),A
	LD HL,(DOC_TOTAL_LINES)
	DEC HL
	LD (CUR_DOC_ROW),HL

CHECK_BW_WRAP_LIMIT:
	LD A,(SEARCH_WRAPPED)
	OR A
	JP Z,SEARCH_BW_LINE_LOOP

	; If wrapped, compare CUR_DOC_ROW with SEARCH_START_ROW
	LD HL,(CUR_DOC_ROW)
	LD DE,(SEARCH_START_ROW)
	OR A
	SBC HL,DE
	JP NC,SEARCH_BW_LINE_LOOP	; CUR_DOC_ROW >= SEARCH_START_ROW: valid
	JP SEARCH_NOT_FOUND	; CUR_DOC_ROW < SEARCH_START_ROW: passed origin!

SEARCH_NOT_FOUND:
	; Restore initial cursor position
	LD HL,(SEARCH_START_ROW)
	LD (CUR_DOC_ROW),HL
	LD A,(SEARCH_START_COL)
	LD (CUR_COL),A
	LD (TARGET_COL),A

	; Check if replace is currently active
	LD A,(REPLACE_ACTIVE)
	OR A
	JR NZ,SNF_RETURN_CARRY

	; Check if pattern was ever found during this search session
	LD A,(SEARCH_EVER_FOUND)
	OR A
	JR NZ,S_SHOW_COMPLETED

	; Never found: cancel block and display Pattern Not Found popup
	CALL CANCEL_BLOCK
	CALL SHOW_POPUP_NOT_FOUND
	SCF
	RET

S_SHOW_COMPLETED:
	; Previously found: keep match highlighted, display Search Completed
	; popup
	CALL SHOW_POPUP_SEARCH_COMPLETED
	SCF
	RET

SNF_RETURN_CARRY:
	SCF
	RET

;------------------------------------------------------------------------------
; SHOW_STATUS_EVENT_POPUP: Centered modal status notification dialog (Tier 2)
;
; Purpose:
;   Displays 50x7 centered modal pop-up box with title DE, message 1 in HL,
;   message 2 in BC, and "[ Press any key to continue ]", waiting for any key.
;
; Call Usage / Protocol:
;   Standard notification pop-up called for errors, status events, and alerts.
;
; Inputs:
;   DE = Title string pointer, HL = Message 1 pointer, BC = Message 2 pointer.
;
; Outputs:
;   Displays modal, waits for key, restores screen, returns Carry = 1.
;
; Preserves / Modifies:
;   Clobbers all working registers; returns Carry = 1.
;------------------------------------------------------------------------------
SHOW_STATUS_EVENT_POPUP:
	CALL SHOW_STATUS_EVENT_POPUP_MODAL

	; 5. Restore screen & persistent status bar
	LD A,(IN_EDITOR_MODE)
	OR A
	JR Z,SSEP_NOT_EDITOR
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	CALL TERM_SHOW_CURSOR
	CALL LOCATE_CURSOR
	SCF
	RET

SSEP_NOT_EDITOR:
	CALL REDRAW_BASE_SCREEN
	SCF
	RET

;------------------------------------------------------------------------------
; SHOW_STATUS_EVENT_POPUP_MODAL: Render modal box interior and await dismissal
;
; Purpose:
;   Emits modal box borders, centered title, messages, and key wait prompt.
;
; Call Usage / Protocol:
;   Internal helper called by SHOW_STATUS_EVENT_POPUP.
;
; Inputs:
;   DE, HL, BC string pointers.
;
; Outputs:
;   Pop-up rendered; waits for keypress.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SHOW_STATUS_EVENT_POPUP_MODAL:
	PUSH BC				; Msg2
	PUSH HL				; Msg1
	PUSH DE				; Title

	; 1. Calculate POPUP_COL = ((ACTIVE_COLS - 50) / 2) + 1
	LD A,(ACTIVE_COLS)
	SUB 50
	SRL A
	INC A
	LD (POPUP_COL),A

	; 2. Calculate POPUP_ROW = ((ACTIVE_ROWS - 7) / 2) + 1
	LD A,(ACTIVE_ROWS)
	SUB 7
	SRL A
	INC A
	LD (POPUP_ROW),A

	; 3. Hide cursor
	CALL TERM_HIDE_CURSOR

	; Line 1: Top Border
	CALL POPUP_PRINT_BORDER

	; Line 2: Title
	CALL POPUP_LOCATE_NEXT
	POP DE				; DE = Title
	CALL PRINT_STR

	; Line 3: Separator Border
	CALL POPUP_PRINT_BORDER

	; Line 4: Msg1
	CALL POPUP_LOCATE_NEXT
	POP DE				; DE = Msg1
	CALL PRINT_STR

	; Line 5: Msg2
	CALL POPUP_LOCATE_NEXT
	POP DE				; DE = Msg2
	CALL PRINT_STR

	; Line 6: Keys
	CALL POPUP_LOCATE_NEXT
	LD DE,STR_POPUP_TRUNC_KEY
	CALL PRINT_STR

	; Line 7: Bottom Border
	CALL POPUP_PRINT_BORDER

	; 4. Wait for any key to dismiss
	CALL GET_KEY
	CP KEY_ESC
	CALL Z,DRAIN_ESC_SEQUENCE
	SCF
	RET

;------------------------------------------------------------------------------
; SHOW_POPUP_NOT_FOUND: Display 'Pattern Not Found' modal pop-up
;
; Purpose:
;   Presents centered modal alert informing user that search pattern was
;   not found in the document.
;
; Call Usage / Protocol:
;   Called via CALL from search routines on failure.
;
; Inputs:
;   None.
;
; Outputs:
;   Modal dialog displayed.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SHOW_POPUP_NOT_FOUND:
	LD DE,STR_POPUP_NOT_FOUND_TITLE
	LD HL,STR_POPUP_NOT_FOUND_MSG1
	LD BC,STR_POPUP_NOT_FOUND_MSG2
	JP SHOW_STATUS_EVENT_POPUP

;------------------------------------------------------------------------------
; SHOW_POPUP_SEARCH_COMPLETED: Display 'Search Completed' modal pop-up
;
; Purpose:
;   Presents centered modal dialog indicating search wrapped around document
;   without finding additional occurrences.
;
; Call Usage / Protocol:
;   Called via CALL from search routines on wrap-around termination.
;
; Inputs:
;   None.
;
; Outputs:
;   Modal dialog displayed.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SHOW_POPUP_SEARCH_COMPLETED:
	LD DE,STR_POPUP_SEARCH_COMP_TITLE
	LD HL,STR_POPUP_SEARCH_COMP_MSG1
	LD BC,STR_POPUP_SEARCH_COMP_MSG2
	JP SHOW_STATUS_EVENT_POPUP

;------------------------------------------------------------------------------
; SHOW_POPUP_LINE_TOO_LONG: Display 'Line Too Long' error modal pop-up
;
; Purpose:
;   Presents centered modal alert notifying user that operation would exceed
;   the maximum allowed line length (120 characters).
;
; Call Usage / Protocol:
;   Called via CALL from line join, replace, or insertion operations.
;
; Inputs:
;   None.
;
; Outputs:
;   Modal dialog displayed.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SHOW_POPUP_LINE_TOO_LONG:
	LD DE,STR_POPUP_TOO_LONG_TITLE
	LD HL,STR_POPUP_TOO_LONG_MSG1
	LD BC,STR_POPUP_TOO_LONG_MSG2
	JP SHOW_STATUS_EVENT_POPUP

;------------------------------------------------------------------------------
; SHOW_POPUP_REPLACE_DONE: Display replace completion summary modal pop-up
;
; Purpose:
;   Formats total number of replacements performed and presents summary modal.
;
; Call Usage / Protocol:
;   Called via CALL at end of DO_REPLACE_UI.
;
; Inputs:
;   REPLACE_COUNT (16-bit word).
;
; Outputs:
;   Modal dialog displayed.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SHOW_POPUP_REPLACE_DONE:
	LD DE,STR_POPUP_REP_DONE_TITLE
	LD HL,STR_POPUP_REP_DONE_MSG1
	LD BC,REPLACE_DONE_POPUP_MSG2
	JP SHOW_STATUS_EVENT_POPUP

;------------------------------------------------------------------------------
; SHOW_POPUP_NEED_PLUGIN_MGR: Display 'Plugin Manager Required' modal pop-up
;
; Purpose:
;   Presents modal alert informing user that the requested feature requires
;   the Plugin Manager to be enabled in configuration.
;
; Call Usage / Protocol:
;   Called via CALL when plugin invocation is attempted with manager disabled.
;
; Inputs:
;   None.
;
; Outputs:
;   Modal dialog displayed.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SHOW_POPUP_NEED_PLUGIN_MGR:
	LD DE,STR_POPUP_NEED_PLUG_TITLE
	LD HL,STR_POPUP_NEED_PLUG_MSG1
	LD BC,STR_POPUP_NEED_PLUG_MSG2
	JP SHOW_STATUS_EVENT_POPUP

;------------------------------------------------------------------------------
; SHOW_POPUP_PLUG_MISSING: Display 'Plugin File Missing' modal pop-up
;
; Purpose:
;   Presents centered modal alert notifying user that requested plugin binary
;   was not found on disk.
;
; Call Usage / Protocol:
;   Called via CALL on plugin load failure.
;
; Inputs:
;   None.
;
; Outputs:
;   Modal dialog displayed.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SHOW_POPUP_PLUG_MISSING:
	LD DE,STR_POPUP_PLUG_MISS_TITLE
	LD HL,STR_POPUP_PLUG_MISS_MSG1
	LD BC,STR_POPUP_PLUG_MISS_MSG2
	JP SHOW_STATUS_EVENT_POPUP

;------------------------------------------------------------------------------
; SHOW_POPUP_HELP_MISSING: Display 'HELP.OVL Not Found' modal pop-up
;
; Purpose:
;   Presents centered modal alert notifying user that HELP.OVL is missing.
;
; Call Usage / Protocol:
;   Called via CALL from DO_HELP_SCREEN when overlay cannot be loaded.
;
; Inputs:
;   None.
;
; Outputs:
;   Modal dialog displayed.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SHOW_POPUP_HELP_MISSING:
	LD DE,STR_POPUP_HELP_MISS_TITLE
	LD HL,STR_POPUP_HELP_MISS_MSG1
	LD BC,STR_POPUP_HELP_MISS_MSG2
	JP SHOW_STATUS_EVENT_POPUP

;------------------------------------------------------------------------------
; SHOW_POPUP_FILE_NOT_FOUND: Display 'File Not Found' modal pop-up with filename
;
; Purpose:
;   Formats target filename dynamically inside single quotes and presents
;   centered modal alert informing user that file was not found on disk.
;
; Call Usage / Protocol:
;   Called via CALL from file open, load, and insert failures.
;
; Inputs:
;   Target filename in WORK_FCB / INPUT_FILENAME_BUF.
;
; Outputs:
;   Modal dialog displayed with formatted filename.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SHOW_POPUP_FILE_NOT_FOUND:
	CALL FORMAT_FNF_MSG1
	LD DE,STR_POPUP_FNF_TITLE
	LD BC,STR_POPUP_FNF_MSG2
	JP SHOW_STATUS_EVENT_POPUP_MODAL

;------------------------------------------------------------------------------
; SHOW_POPUP_RAMDRV_UNAVAIL: Display 'RAM Drive Unavailable' modal pop-up
;
; Purpose:
;   Presents modal alert informing user that RomWBW RAM drive is not installed.
;
; Call Usage / Protocol:
;   Called via CALL from RAM drive menu handlers.
;
; Inputs:
;   None.
;
; Outputs:
;   Modal dialog displayed.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SHOW_POPUP_RAMDRV_UNAVAIL:
	LD DE,STR_POPUP_RAMDRV_TITLE
	LD HL,STR_POPUP_RAMDRV_MSG1
	LD BC,STR_POPUP_RAMDRV_MSG2
	JP SHOW_STATUS_EVENT_POPUP_MODAL

;------------------------------------------------------------------------------
; SHOW_POPUP_FAT_NO_PLUGIN: Display 'FATFS Plugin Missing' modal pop-up
;
; Purpose:
;   Presents modal alert informing user that FAT filesystem access requires
;   FATFS.PRL plugin which could not be loaded.
;
; Call Usage / Protocol:
;   Called via CALL when FAT path access fails.
;
; Inputs:
;   None.
;
; Outputs:
;   Modal dialog displayed.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SHOW_POPUP_FAT_NO_PLUGIN:
	LD DE,STR_POPUP_FAT_MISS_TITLE
	LD HL,STR_POPUP_FAT_MISS_MSG1
	LD BC,STR_POPUP_FAT_MISS_MSG2
	JP SHOW_STATUS_EVENT_POPUP_MODAL

;------------------------------------------------------------------------------
; FORMAT_FNF_MSG1: Format centered "'FILENAME' was not found." message string
;
; Purpose:
;   Extracts filename, encloses in single quotes, appends " was not found.",
;   and centers symmetrically within a 48-column interior pop-up line buffer.
;
; Call Usage / Protocol:
;   Called via CALL from SHOW_POPUP_FILE_NOT_FOUND.
;
; Inputs:
;   Target filename in WORK_FCB or INPUT_FILENAME_BUF.
;
; Outputs:
;   POPUP_FNF_MSG1_BUF populated with formatted, centered text.
;
; Preserves / Modifies:
;   Preserves BC, DE, IX; clobbers AF, HL.
;------------------------------------------------------------------------------
FORMAT_FNF_MSG1:
	PUSH BC
	PUSH DE
	PUSH IX

	; Step 1: Scan INPUT_FILENAME_BUF skipping leading spaces
	LD HL,INPUT_FILENAME_BUF
FFNF_SKIP_SP:
	LD A,(HL)
	CP ' '
	JR NZ,FFNF_CHECK_EMPTY
	INC HL
	JR FFNF_SKIP_SP

FFNF_CHECK_EMPTY:
	OR A
	JR Z,FFNF_FALLBACK		; Empty buffer -> use static template

	; Save pointer to start of filename in IX
	PUSH HL
	POP IX

	; Check for drive/user prefix in INPUT_FILENAME_BUF
	LD HL,INPUT_FILENAME_BUF
	CALL PARSE_DRIVE_USER_PREFIX
	JR C,FFNF_PREFIX_OK
	; No prefix matched: any colon is a line colon
	LD DE,0
	JR FFNF_PREFIX_DONE
FFNF_PREFIX_OK:
	; Prefix matched: HL points past drive colon (DE = pointer past colon)
	EX DE,HL
FFNF_PREFIX_DONE:

	; Now scan from IX to determine length L (max 28 chars)
	PUSH IX
	POP HL				; HL = start of filename
	LD B,0				; B = length counter

FFNF_SCAN_LOOP:
	LD A,(HL)
	OR A
	JR Z,FFNF_SCAN_DONE		; Null terminator -> end of filename
	CP ' '
	JR Z,FFNF_SCAN_DONE		; Space -> end of filename
	CP ':'
	JR NZ,FFNF_CHAR_OK

	; Colon found: check if HL < DE (part of prefix) or HL >= DE (line
	; colon)
	CALL CMP_HL_DE
	JR C,FFNF_CHAR_OK		; Colon is part of prefix!
	JR FFNF_SCAN_DONE	; Colon is at or after DE -> line colon! Stop.

FFNF_CHAR_OK:
	INC B
	INC HL
	LD A,B
	CP 28				; Limit filename to 28 chars
	JR C,FFNF_SCAN_LOOP

FFNF_SCAN_DONE:
	LD A,B
	OR A
	JR Z,FFNF_FALLBACK		; 0 chars scanned -> fallback

	; Length L is in B (1..28)
	LD C,B				; C = L

	; Step 2: Initialize FNF_POPUP_MSG1 buffer with '|', 48 spaces, '|', 0
	LD HL,FNF_POPUP_MSG1
	LD (HL),'|'
	INC HL
	LD B,48
	LD A,' '
FFNF_FILL_SP:
	LD (HL),A
	INC HL
	DJNZ FFNF_FILL_SP
	LD (HL),'|'
	INC HL
	LD (HL),0

	; Step 3: Compute centering offset
	; Total text length T = 1 ("'") + C (filename) + 16 ("' was not found.")
	; T = C + 17
	; Remaining spaces = 48 - (C + 17) = 31 - C
	; Left spaces = (31 - C) / 2
	LD A,31
	SUB C
	SRL A				; A = left spaces

	; Target pointer in buffer = FNF_POPUP_MSG1 + 1 + left spaces
	LD HL,FNF_POPUP_MSG1 + 1
	LD E,A
	LD D,0
	ADD HL,DE			; HL = destination in FNF_POPUP_MSG1

	; Step 4: Write opening quote "'" (ASCII 39)
	LD (HL),39
	INC HL

	; Step 5: Copy C characters from IX to HL, converting to upper
	PUSH IX
	POP DE				; DE = source filename
	LD B,C				; B = character count
FFNF_COPY_NAME:
	LD A,(DE)
	CALL TO_UPPER
	LD (HL),A
	INC DE
	INC HL
	DJNZ FFNF_COPY_NAME

	; Step 6: Copy 16 characters of suffix ("' was not found.")
	LD DE,STR_FNF_MSG1_SFX
	LD B,16
FFNF_COPY_SFX:
	LD A,(DE)
	LD (HL),A
	INC DE
	INC HL
	DJNZ FFNF_COPY_SFX

	; Return HL = FNF_POPUP_MSG1
	LD HL,FNF_POPUP_MSG1
	POP IX
	POP DE
	POP BC
	RET

FFNF_FALLBACK:
	LD HL,STR_POPUP_FNF_MSG1
	POP IX
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; FORMAT_REPLACE_DONE_MSG2: Format replace summary count line for modal pop-up
;
; Purpose:
;   Formats REPLACE_COUNT as decimal and centers message (e.g.
;   "|          Replaced 14 occurrences.               |") within 50-col frame.
;
; Call Usage / Protocol:
;   Called via CALL from SHOW_POPUP_REPLACE_DONE.
;
; Inputs:
;   REPLACE_COUNT (16-bit word).
;
; Outputs:
;   REPLACE_DONE_MSG2_BUF populated with formatted string.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
FORMAT_REPLACE_DONE_MSG2:
	PUSH BC
	PUSH DE
	PUSH HL

	; 1. Initialize buffer with 50 spaces and borders:
	; "|                                                |"
	LD HL,REPLACE_DONE_POPUP_MSG2
	LD (HL),'|'
	INC HL
	LD B,48
	LD A,' '
FRDM_FILL_SPACES:
	LD (HL),A
	INC HL
	DJNZ FRDM_FILL_SPACES
	LD (HL),'|'
	INC HL
	LD (HL),0			; Null terminator

	; 2. Determine number of digits for REPLACE_COUNT
	LD HL,(REPLACE_COUNT)
	CALL GET_DEC_WORD_DIGITS	; A = digits D (1..5)
	; Total text length = 14 ("Replace done: ") + D + 16 ("
	; replacement(s).")
	; = 30 + D chars
	; Remaining spaces inside 48 chars = 48 - (30 + D) = 18 - D
	; Left spaces = (18 - D) / 2
	LD C,A				; C = D (digit count)
	LD A,18
	SUB C				; A = 18 - D
	SRL A				; A = (18 - D) / 2 = left spaces
	INC A				; +1 for leading '|' at index 0

	; HL = pointer to start of text in REPLACE_DONE_POPUP_MSG2
	LD HL,REPLACE_DONE_POPUP_MSG2
	LD E,A
	LD D,0
	ADD HL,DE			; HL = target position

	; 3. Copy "Replace done: " (14 chars)
	LD DE,STR_REP_DONE_TXT_PFX
	LD B,14
FRDM_CPY_PFX:
	LD A,(DE)
	LD (HL),A
	INC DE
	INC HL
	DJNZ FRDM_CPY_PFX

	; 4. Format decimal count digits into buffer at HL
	PUSH HL				; Save target position in buffer
	LD HL,(REPLACE_COUNT)
	CALL FORMAT_DEC_WORD_RAM	; DE = pointer to first digit
	POP HL				; Restore target position in buffer
	LD B,C				; B = digit count
FRDM_CPY_DIGITS:
	LD A,(DE)
	LD (HL),A
	INC DE
	INC HL
	DJNZ FRDM_CPY_DIGITS

	; 5. Copy " replacement(s)." (16 chars)
	LD DE,STR_REP_DONE_TXT_SFX
	LD B,16
FRDM_CPY_SFX:
	LD A,(DE)
	LD (HL),A
	INC DE
	INC HL
	DJNZ FRDM_CPY_SFX

	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; FORMAT_DEC_WORD_RAM: Format 16-bit word in HL as decimal ASCII digits in RAM
;
; Purpose:
;   Converts 16-bit unsigned integer in HL to ASCII decimal digits stored
;   in a local buffer, returning pointer to first digit in DE and count in B.
;
; Call Usage / Protocol:
;   Called via CALL by dialog formatters.
;
; Inputs:
;   HL = 16-bit unsigned integer (0..65535).
;
; Outputs:
;   DE = Pointer to first ASCII digit; B = Number of digits.
;
; Preserves / Modifies:
;   Preserves HL; returns DE, B; clobbers AF, C.
;------------------------------------------------------------------------------
FORMAT_DEC_WORD_RAM:
	LD DE,DEC_WORD_BUF+5
	LD A,0
	LD (DE),A
FDWR_LOOP:
	CALL DIV_HL_10
	ADD A,'0'
	DEC DE
	LD (DE),A
	LD A,H
	OR L
	JR NZ,FDWR_LOOP
	RET

;------------------------------------------------------------------------------
; MATCH_SUBSTRING: Test if search pattern matches line text at current offset
;
; Purpose:
;   Compares characters starting at HL against pattern in SEARCH_INPUT_BUF,
;   respecting SEARCH_CASE_SENSITIVE flag.
;
; Call Usage / Protocol:
;   Called via CALL by FIND_STRING_FORWARD and FIND_STRING_BACKWARD.
;
; Inputs:
;   HL = Pointer to text in line, SEARCH_INPUT_BUF, SEARCH_CASE_SENSITIVE.
;
; Outputs:
;   Zero flag set if match; NZ flag set if mismatch.
;
; Preserves / Modifies:
;   Preserves DE, HL; modifies AF (flags).
;------------------------------------------------------------------------------
MATCH_SUBSTRING:
	PUSH DE
	PUSH HL
	LD DE,SEARCH_BUF
	LD A,(SEARCH_LEN)
	LD B,A
MATCH_SUB_LOOP:
	LD A,(DE)			; A = pattern char
	LD C,(HL)			; C = line char
	LD A,(SEARCH_CASE_SENSITIVE)
	OR A
	JR NZ,MATCH_SUB_EXACT

	; Case insensitive: fold both to uppercase
	LD A,(DE)
	CALL TO_UPPER_CHAR
	PUSH AF
	LD A,C
	CALL TO_UPPER_CHAR
	LD C,A
	POP AF
	CP C
	JR NZ,MATCH_SUB_FAIL
	JR MATCH_SUB_NEXT

MATCH_SUB_EXACT:
	LD A,(DE)
	CP C
	JR NZ,MATCH_SUB_FAIL

MATCH_SUB_NEXT:
	INC DE
	INC HL
	DJNZ MATCH_SUB_LOOP

	; Full match!
	POP HL
	POP DE
	XOR A				; Set Z flag
	RET

MATCH_SUB_FAIL:
	POP HL
	POP DE
	OR 1				; Clear Z flag (NZ)
	RET

;------------------------------------------------------------------------------
; TO_UPPER_CHAR: Convert lowercase ASCII character in A to uppercase
;
; Purpose:
;   If character in register A is between 'a' and 'z', subtracts 32 to convert
;   to uppercase; otherwise leaves unchanged.
;
; Call Usage / Protocol:
;   Called via CALL by case-insensitive comparisons and command parsing.
;
; Inputs:
;   A = ASCII character byte.
;
; Outputs:
;   A = Uppercase ASCII character byte.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; modifies AF.
;------------------------------------------------------------------------------
TO_UPPER_CHAR:
	CP 'a'
	RET C
	CP 'z'+1
	RET NC
	SUB 20H
	RET

;------------------------------------------------------------------------------
; DO_REPLACE_UI: Centered modal dialog and engine for Search & Replace (Ctrl+R)
;
; Purpose:
;   Displays Search & Replace configuration dialog, inputs find and replace
;   strings, and enters interactive replacement confirmation loop
;   ([Y]es, [N]o, [A]ll, [R]everse, [ESC]=Cancel).
;
; Call Usage / Protocol:
;   Jumped to from MAIN_LOOP on Ctrl+R.
;
; Inputs:
;   ACTIVE_COLS, ACTIVE_ROWS.
;
; Outputs:
;   Executes replacements and displays completion summary.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_REPLACE_UI:
	; 1. First get search pattern via DO_FIND_UI
	CALL DO_FIND_UI
	RET C				; Cancelled or pattern not found

	; Note: DO_FIND_UI already executed first search and positioned at first
	; match!

	; 2. Prompt for replacement string via Tier 2 centered modal popup
	CALL DRAW_REPLACE_POPUP_FULL

	; Clear replace buffer
	LD HL,REPLACE_BUF
	LD (HL),0
	LD B,0			; B = character count (0..FIND_POPUP_FIELD_LEN)

REPLACE_INPUT_LOOP:
	CALL GET_KEY

	; ESC -> Cancel replace
	CP KEY_ESC
	JR Z,REPLACE_INPUT_CHECK_ESC

	; Enter -> Confirm replacement string
	CP KEY_ENTER
	JR Z,REPLACE_INPUT_CONFIRM

	; Backspace / Delete
	CP KEY_BACKSPACE
	JR Z,REPLACE_INPUT_BS
	CP KEY_DEL
	JR Z,REPLACE_INPUT_BS

	; Printable character (ASCII 32..126)
	CP ' '
	JR C,REPLACE_INPUT_LOOP
	CP 127
	JR NC,REPLACE_INPUT_LOOP

	; Check max length
	LD C,A
	LD A,B
	CP REPLACE_POPUP_FIELD_LEN
	JR NC,REPLACE_INPUT_LOOP

	LD HL,REPLACE_BUF
	LD E,B
	LD D,0
	ADD HL,DE
	LD (HL),C
	INC HL
	LD (HL),0
	INC B

	LD A,C
	CALL PUTC
	JR REPLACE_INPUT_LOOP

REPLACE_INPUT_BS:
	LD A,B
	OR A
	JR Z,REPLACE_INPUT_LOOP

	DEC B
	LD HL,REPLACE_BUF
	LD E,B
	LD D,0
	ADD HL,DE
	LD (HL),0

	LD A,008H
	CALL PUTC
	LD A,' '
	CALL PUTC
	LD A,008H
	CALL PUTC
	JR REPLACE_INPUT_LOOP

REPLACE_INPUT_CHECK_ESC:
	PUSH BC
	LD BC,ESC_TIMEOUT_LOOPS
REP_WAIT_ESC:
	CALL CHECK_KEY_READY
	JR NZ,REP_GOT_ESC_SEQ
	DEC BC
	LD A,B
	OR C
	JR NZ,REP_WAIT_ESC
	POP BC
	JR REPLACE_INPUT_CANCEL

REP_GOT_ESC_SEQ:
	CALL DRAIN_ESC_SEQUENCE
	POP BC
	JP REPLACE_INPUT_LOOP

REPLACE_INPUT_CANCEL:
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	CALL LOCATE_CURSOR
	RET

REPLACE_INPUT_CONFIRM:
	LD A,B
	LD (REPLACE_LEN),A

	; Clear replace popup by restoring base screen
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	CALL LOCATE_CURSOR

	; 3. Initialize replace execution
	XOR A
	LD (REPLACE_ALL_MODE),A
	LD (SEARCH_DIRECTION),A		; 0 = Forward
	LD HL,0
	LD (REPLACE_COUNT),HL
	LD A,1
	LD (REPLACE_ACTIVE),A

	; Lock search wrap origin for this replace session:
	LD HL,(BLOCK_START_ROW)
	LD (SEARCH_START_ROW),HL
	LD A,(BLOCK_START_COL)
	LD (SEARCH_START_COL),A
	XOR A
	LD (SEARCH_WRAPPED),A

	; Enter the replace loop directly for the current match:
	JP REPLACE_PROCESS_MATCH

;------------------------------------------------------------------------------
; DRAW_REPLACE_POPUP_FULL: Render Search & Replace setup dialog box
;
; Purpose:
;   Draws 50x9 centered modal pop-up box with find and replace input fields.
;
; Call Usage / Protocol:
;   Called via CALL from DO_REPLACE_UI.
;
; Inputs:
;   POPUP_COL, POPUP_ROW.
;
; Outputs:
;   Dialog frame rendered on terminal.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DRAW_REPLACE_POPUP_FULL:
	; 1. Calculate POPUP_COL = ((ACTIVE_COLS - 50) / 2) + 1
	LD A,(ACTIVE_COLS)
	SUB 50
	SRL A
	INC A
	LD (POPUP_COL),A

	; 2. Calculate POPUP_ROW = ((ACTIVE_ROWS - 7) / 2) + 1
	LD A,(ACTIVE_ROWS)
	SUB 7
	SRL A
	INC A
	LD (POPUP_ROW),A
	LD (POPUP_START_ROW),A

	CALL TERM_HIDE_CURSOR

	; Line 1: Border
	CALL POPUP_PRINT_BORDER

	; Line 2: Title
	CALL POPUP_LOCATE_NEXT
	LD DE,STR_REPLACE_POPUP_TITLE
	CALL PRINT_STR

	; Line 3: Border
	CALL POPUP_PRINT_BORDER

	; Line 4: Instructions (Description)
	CALL POPUP_LOCATE_NEXT
	LD DE,STR_REPLACE_POPUP_MSG
	CALL PRINT_STR

	; Line 5: Prompt and empty input box (Query Line)
	CALL POPUP_LOCATE_NEXT
	LD DE,STR_REPLACE_POPUP_PROMPT
	CALL PRINT_STR
	; Pad 29 spaces for empty box
	LD C,REPLACE_POPUP_FIELD_LEN
DRP_PAD_LOOP:
	LD A,' '
	CALL PUTC
	DEC C
	JR NZ,DRP_PAD_LOOP
	LD DE,STR_REPLACE_POPUP_BOX_CLOSE
	CALL PRINT_STR

	; Line 6: Keys
	CALL POPUP_LOCATE_NEXT
	LD DE,STR_REPLACE_POPUP_KEYS
	CALL PRINT_STR

	; Line 7: Border
	CALL POPUP_PRINT_BORDER

	; Position cursor inside replace box at (POPUP_START_ROW + 4, POPUP_COL
	; + 18)
	LD A,(POPUP_START_ROW)
	ADD A,4
	LD H,A
	LD A,(POPUP_COL)
	ADD A,18
	LD L,A
	CALL LOCATE_RC
	CALL TERM_SHOW_CURSOR
	RET

;------------------------------------------------------------------------------
; DRAW_REPLACE_CONFIRM_POPUP: Render interactive Replace confirmation prompt
;
; Purpose:
;   Draws 50x7 modal pop-up prompting user whether to replace matched string:
;   "[Y]es  [N]o  [A]ll  [R]everse  [ESC]=Cancel".
;
; Call Usage / Protocol:
;   Called via CALL upon each match in DO_REPLACE_UI.
;
; Inputs:
;   POPUP_COL, POPUP_ROW.
;
; Outputs:
;   Confirmation pop-up rendered on terminal.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DRAW_REPLACE_CONFIRM_POPUP:
	; 1. Calculate POPUP_COL = ((ACTIVE_COLS - 50) / 2) + 1
	LD A,(ACTIVE_COLS)
	SUB 50
	SRL A
	INC A
	LD (POPUP_COL),A

	; 2. Calculate POPUP_ROW = ((ACTIVE_ROWS - 7) / 2) + 1
	LD A,(ACTIVE_ROWS)
	SUB 7
	SRL A
	INC A
	LD (POPUP_ROW),A
	LD (POPUP_START_ROW),A

	; Line 1: Border
	CALL POPUP_PRINT_BORDER

	; Line 2: Title
	CALL POPUP_LOCATE_NEXT
	LD DE,STR_REP_CONFIRM_TITLE
	CALL PRINT_STR

	; Line 3: Border
	CALL POPUP_PRINT_BORDER

	; Line 4: Description
	CALL POPUP_LOCATE_NEXT
	LD DE,STR_REP_CONFIRM_MSG1
	CALL PRINT_STR

	; Line 5: Query Prompt
	CALL POPUP_LOCATE_NEXT
	LD DE,STR_REP_CONFIRM_MSG2
	CALL PRINT_STR

	; Line 6: Keys
	CALL POPUP_LOCATE_NEXT
	LD DE,STR_REP_CONFIRM_KEYS
	CALL PRINT_STR

	; Line 7: Border
	CALL POPUP_PRINT_BORDER

	; Position cursor inside popup on prompt line after "Replace this
	; occurrence? "
	CALL LOCATE_REPLACE_CONFIRM_CURSOR
	CALL TERM_SHOW_CURSOR
	RET

;------------------------------------------------------------------------------
; LOCATE_REPLACE_CONFIRM_CURSOR: Position cursor inside replace confirm prompt
;
; Purpose:
;   Locates hardware cursor on action option line in replace prompt dialog.
;
; Call Usage / Protocol:
;   Called via CALL before reading user confirmation key in DO_REPLACE_UI.
;
; Inputs:
;   POPUP_COL, POPUP_ROW.
;
; Outputs:
;   Cursor located inside dialog box.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
LOCATE_REPLACE_CONFIRM_CURSOR:
	LD A,(POPUP_START_ROW)
	ADD A,4
	LD H,A
	LD A,(POPUP_COL)
	ADD A,36
	LD L,A
	CALL LOCATE_RC
	RET

REPLACE_SEARCH_NEXT:
	; Check current search direction
	LD A,(SEARCH_DIRECTION)
	OR A
	JR NZ,REPLACE_SEARCH_BW

	; Advance search position forward
	CALL FIND_STRING_FORWARD_CONT
	JP C,REPLACE_SUMMARY		; No more matches
	JR REPLACE_PROCESS_MATCH

REPLACE_SEARCH_BW:
	; Advance search position backward
	CALL FIND_STRING_BACKWARD_CONT
	JP C,REPLACE_SUMMARY		; No more matches
	JR REPLACE_PROCESS_MATCH

REPLACE_PROCESS_MATCH:
	; If Replace All mode is active, do substitution directly
	LD A,(REPLACE_ALL_MODE)
	OR A
	JP NZ,REPLACE_EXECUTE_SUBST

	; Render screen to show match to user with persistent status bar
	CALL FLUSH_DEFERRED_RENDER
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR

	; Render centered Tier 2 modal pop-up box
	CALL DRAW_REPLACE_CONFIRM_POPUP

REPLACE_CONFIRM_KEY:
	CALL GET_KEY
	CP KEY_ESC
	JP Z,REPLACE_QUIT

	CP 'r'
	JR Z,REPLACE_DO_REVERSE
	CP 'R'
	JR Z,REPLACE_DO_REVERSE
	CP 'p'
	JR Z,REPLACE_DO_REVERSE
	CP 'P'
	JR Z,REPLACE_DO_REVERSE

	CP 'n'
	JR Z,REPLACE_DO_SKIP
	CP 'N'
	JR Z,REPLACE_DO_SKIP

	CP 'a'
	JR Z,REPLACE_ACTIVATE_ALL
	CP 'A'
	JR Z,REPLACE_ACTIVATE_ALL

	CP 'y'
	JP Z,REPLACE_DO_SUBST
	CP 'Y'
	JP Z,REPLACE_DO_SUBST
	CP KEY_ENTER
	JP Z,REPLACE_DO_SUBST

	CALL LOCATE_REPLACE_CONFIRM_CURSOR
	JR REPLACE_CONFIRM_KEY

REPLACE_QUIT:
	JP REPLACE_SUMMARY

REPLACE_DO_REVERSE:
	JR REPLACE_REVERSE_DIR

REPLACE_DO_SKIP:
	JR REPLACE_SKIP

REPLACE_DO_SUBST:
	JP REPLACE_EXECUTE_SUBST

REPLACE_REVERSE_DIR:
	; Toggle SEARCH_DIRECTION
	LD A,(SEARCH_DIRECTION)
	XOR 1
	LD (SEARCH_DIRECTION),A

	; Step in the new direction
	OR A
	JR NZ,REPLACE_REV_TO_BW

	; Reversing to Forward: advance col by 1 from match start
	LD A,(BLOCK_START_COL)
	INC A
	LD (CUR_COL),A
	JP REPLACE_SEARCH_NEXT

REPLACE_REV_TO_BW:
	; Reversing to Backward: step back 1 char from match start
	LD A,(BLOCK_START_COL)
	LD (CUR_COL),A
	CALL STEP_BACK_ONE_CHAR
	JP REPLACE_SEARCH_NEXT

REPLACE_ACTIVATE_ALL:
	XOR A
	LD (SEARCH_DIRECTION),A	; Ensure forward direction for Replace All
	LD A,1
	LD (REPLACE_ALL_MODE),A
	JP REPLACE_EXECUTE_SUBST

REPLACE_SKIP:
	; Skip this match: advance in current direction
	LD A,(SEARCH_DIRECTION)
	OR A
	JR NZ,REPLACE_SKIP_BW

	; Forward skip: advance col by 1 from match start
	LD A,(BLOCK_START_COL)
	INC A
	LD (CUR_COL),A
	JP REPLACE_SEARCH_NEXT

REPLACE_SKIP_BW:
	; Backward skip: step back 1 char from match start
	LD A,(BLOCK_START_COL)
	LD (CUR_COL),A
	CALL STEP_BACK_ONE_CHAR
	JP REPLACE_SEARCH_NEXT

REPLACE_EXECUTE_SUBST:
	; Set CUR_COL to match start col before substitution
	LD A,(BLOCK_START_COL)
	LD (CUR_COL),A
	LD (REPLACE_MATCH_COL),A

	CALL APPLY_LINE_REPLACE

	LD A,(SEARCH_DIRECTION)
	OR A
	JP Z,REPLACE_SEARCH_NEXT

	; Backward: restore to match col, then step back 1 char
	LD A,(REPLACE_MATCH_COL)
	LD (CUR_COL),A
	CALL STEP_BACK_ONE_CHAR
	JP REPLACE_SEARCH_NEXT

REPLACE_SUMMARY:
	XOR A
	LD (REPLACE_ACTIVE),A

	; Cancel any active block highlight
	CALL CANCEL_BLOCK

	; Format dynamic replacement count into modal Msg2 line
	CALL FORMAT_REPLACE_DONE_MSG2

	; Display centered Tier 2 Replace Done modal pop-up
	CALL SHOW_POPUP_REPLACE_DONE

	LD A,1
	LD (NEED_SCREEN_RENDER),A
	CALL FLUSH_DEFERRED_RENDER
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	CALL LOCATE_CURSOR
	RET

;------------------------------------------------------------------------------
; APPLY_LINE_REPLACE: Substitute pattern with replacement string in active line
;
; Purpose:
;   Replaces matched pattern substring in ACTIVE_LINE_BUF with replacement
;   string. Checks that resulting line length does not exceed 1000 characters.
;
; Call Usage / Protocol:
;   Called via CALL when user confirms replacement in DO_REPLACE_UI.
;
; Inputs:
;   CUR_COL, SEARCH_LEN, REPLACE_LEN, ACTIVE_LINE_BUF.
;
; Outputs:
;   Carry = 0 on success; Carry = 1 if line would exceed 1000 chars.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
APPLY_LINE_REPLACE:
	CALL CHECKOUT_ACTIVE_LINE	; HL = ACTIVE_LINE_BUF

	; 1. Calculate line length L (16-bit)
	PUSH HL
	LD BC,0
ALR_CALC_LEN:
	LD A,(HL)
	OR A
	JR Z,ALR_CALC_LEN_DONE
	INC HL
	INC BC
	JR ALR_CALC_LEN
ALR_CALC_LEN_DONE:
	POP HL				; HL = ACTIVE_LINE_BUF
	; BC = L (current line length in bytes)

	; 2. Check resulting line length: L' = L - S + R
	; S = SEARCH_LEN, R = REPLACE_LEN
	LD H,B
	LD L,C				; HL = L
	LD A,(SEARCH_LEN)
	LD E,A
	LD D,0
	OR A
	SBC HL,DE			; HL = L - S
	LD A,(REPLACE_LEN)
	LD E,A
	LD D,0
	ADD HL,DE			; HL = L' = L - S + R

	; 16-bit comparison against MAX_INPUT_LINE_CHARS (1000)
	LD DE,MAX_INPUT_LINE_CHARS	; 1000
	LD A,L
	SUB E
	LD A,H
	SBC A,D
	JR C,ALR_LENGTH_OK
	JR Z,ALR_LENGTH_OK

	; Line would exceed 1000 chars: display warning modal and skip
	CALL SHOW_POPUP_LINE_TOO_LONG

	; Advance past match start
	LD HL,(CUR_COL)
	INC HL
	LD (CUR_COL),HL
	RET

ALR_LENGTH_OK:
	; 3. Perform substitution
	; PTR = ACTIVE_LINE_BUF + CUR_COL
	LD HL,ACTIVE_LINE_BUF
	LD DE,(CUR_COL)
	ADD HL,DE
	LD (REPLACE_PTR_TEMP),HL	; Pointer to match start in line

	; Calculate TAIL_LEN in BC:
	; L is in BC. TAIL_LEN = L - (CUR_COL + S)
	LD DE,(CUR_COL)
	LD A,(SEARCH_LEN)
	LD L,A
	LD H,0
	ADD HL,DE			; HL = CUR_COL + S
	; BC - HL:
	LD A,C
	SUB L
	LD C,A
	LD A,B
	SBC A,H
	LD B,A				; BC = TAIL_LEN

	; Number of bytes to move = TAIL_LEN + 1 (includes null terminator)
	INC BC				; BC = tail bytes including null

	; Compare S and R:
	LD A,(SEARCH_LEN)
	LD D,A				; D = S
	LD A,(REPLACE_LEN)
	LD E,A				; E = R
	CP D
	JR Z,ALR_EQUAL_LEN
	JR C,ALR_SHRINK_LEN

	; Case R > S (line expands):
	; Delta = R - S
	SUB D
	LD (REPLACE_DELTA_TEMP),A	; Delta

	; Move tail rightwards by Delta bytes:
	; Source last byte = PTR + S + TAIL_LEN (which is PTR + S + BC - 1)
	; Destination last byte = Source + Delta
	PUSH BC				; Save tail count
	LD HL,(REPLACE_PTR_TEMP)
	LD A,D				; A = S
	LD E,A
	LD D,0
	ADD HL,DE			; HL = PTR + S
	ADD HL,BC
	DEC HL				; HL = Source last byte

	LD A,(REPLACE_DELTA_TEMP)
	LD E,A
	LD D,0
	PUSH HL
	ADD HL,DE		; HL = HL + Delta (Destination last byte)
	EX DE,HL			; DE = Destination last byte
	POP HL				; HL = Source last byte
	POP BC				; BC = tail count
	LDDR

	; Now copy R bytes from REPLACE_BUF to PTR
	CALL ALR_COPY_REPLACE_STR
	JR ALR_SUBST_DONE

ALR_SHRINK_LEN:
	; Case R < S (line shrinks):
	; Delta = S - R
	LD A,D
	SUB E
	LD (REPLACE_DELTA_TEMP),A

	; Copy R bytes from REPLACE_BUF to PTR first
	PUSH BC
	CALL ALR_COPY_REPLACE_STR
	POP BC				; BC = tail count

	; Move tail leftwards by Delta bytes:
	; Source = PTR + S
	; Destination = PTR + R
	LD HL,(REPLACE_PTR_TEMP)
	LD A,(SEARCH_LEN)
	LD E,A
	LD D,0
	ADD HL,DE			; HL = Source (PTR + S)

	LD DE,(REPLACE_PTR_TEMP)
	LD A,(REPLACE_LEN)
	PUSH HL
	LD L,A
	LD H,0
	ADD HL,DE
	EX DE,HL			; DE = Destination (PTR + R)
	POP HL				; HL = Source (PTR + S)

	LDIR
	JR ALR_SUBST_DONE

ALR_EQUAL_LEN:
	; Case R == S: simple overwrite of R bytes
	CALL ALR_COPY_REPLACE_STR
	JR ALR_SUBST_DONE

ALR_COPY_REPLACE_STR:
	LD A,(REPLACE_LEN)
	OR A
	RET Z				; 0 bytes to copy
	LD C,A
	LD B,0
	LD HL,REPLACE_BUF
	LD DE,(REPLACE_PTR_TEMP)
	LDIR
	RET

ALR_SUBST_DONE:
	; Mark active line dirty and commit to Far RAM + cache sync
	LD A,1
	LD (ACTIVE_LINE_DIRTY),A
	LD (DOC_MODIFIED),A
	CALL COMMIT_ACTIVE_LINE

	; Increment REPLACE_COUNT
	LD HL,(REPLACE_COUNT)
	INC HL
	LD (REPLACE_COUNT),HL

	; Update CUR_COL = CUR_COL + R
	LD HL,(CUR_COL)
	LD A,(REPLACE_LEN)
	LD E,A
	LD D,0
	ADD HL,DE
	LD (CUR_COL),HL
	RET

