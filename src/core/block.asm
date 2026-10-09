;==============================================================================
; BLOCK.ASM: Core Subsystem - Block Selection, Clipboard & Highlight Engine
;
; Purpose:
;   Implements block selection modes, boundary calculation, clipboard
;   operations (cut, copy, delete, move), and the block action popup menu.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
;------------------------------------------------------------------------------
; Block Selection & Highlighting Engine (Hybrid Character & Line Blocking)
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; TOGGLE_BLOCK_MODE: Toggle block selection on/off at current cursor position
;
; Purpose:
;   Toggles visual block selection between inactive (0) and dynamic marking
;   (state 1), anchoring selection at (CUR_DOC_ROW, CUR_COL). If block is
;   already active (state 1 or 2), cancels block selection.
;
; Call Usage / Protocol:
;   Called via CALL from MAIN_LOOP when user presses Ctrl+B.
;
; Inputs:
;   BLOCK_ACTIVE, CUR_DOC_ROW, CUR_COL.
;
; Outputs:
;   BLOCK_ACTIVE updated (0 or 1); NEED_SCREEN_RENDER set to 1.
;
; Preserves / Modifies:
;   Preserves BC, DE; clobbers AF, HL.
;------------------------------------------------------------------------------
TOGGLE_BLOCK_MODE:
	LD A,(BLOCK_ACTIVE)
	OR A
	JR NZ,CANCEL_BLOCK		; Active (1 or 2): Ctrl-B cancels/clears

	; Block inactive (0): activate and anchor at current cursor
START_NEW_BLOCK_AT_CURSOR:
	LD A,1
	LD (BLOCK_ACTIVE),A
	LD HL,(CUR_DOC_ROW)
	LD (BLOCK_ANCHOR_ROW),HL
	LD HL,(CUR_COL)
	LD (BLOCK_ANCHOR_COL),HL
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	RET

;------------------------------------------------------------------------------
; CANCEL_BLOCK: Cancel active block selection and refresh screen
;
; Purpose:
;   Resets BLOCK_ACTIVE state to 0 and flags screen for re-rendering,
;   clearing visual highlight attributes.
;
; Call Usage / Protocol:
;   Called via CALL on typing, navigation, ESC keys, or clear commands.
;
; Inputs:
;   BLOCK_ACTIVE.
;
; Outputs:
;   BLOCK_ACTIVE = 0; NEED_SCREEN_RENDER = 1.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
CANCEL_BLOCK:
	LD A,(BLOCK_ACTIVE)
	OR A
	RET Z
	XOR A
	LD (BLOCK_ACTIVE),A
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	RET

;------------------------------------------------------------------------------
; SOLIDIFY_BLOCK: Lock and freeze dynamic block selection coordinates
;
; Purpose:
;   Transitions active block selection from dynamic tracking (state 1) to
;   locked/solidified (state 2). Normalizes anchor and cursor coordinates
;   into immutable START and END boundaries.
;
; Call Usage / Protocol:
;   Called via CALL from Ctrl+K menu or before copy, move, delete, and save.
;
; Inputs:
;   BLOCK_ACTIVE (only acts if value is 1).
;
; Outputs:
;   BLOCK_ACTIVE = 2; NEED_SCREEN_RENDER = 1; block bounds normalized.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
SOLIDIFY_BLOCK:
	LD A,(BLOCK_ACTIVE)
	CP 1
	RET NZ			; Only dynamic selection can be solidified
	CALL NORMALIZE_BLOCK_BOUNDS
	LD A,2
	LD (BLOCK_ACTIVE),A		; State 2 = Solidified / Locked
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	RET

;------------------------------------------------------------------------------
; DO_BLOCK_MENU_POPUP: Centered modal dialog for block operations (Ctrl+K)
;
; Purpose:
;   Flushes deferred rendering, normalizes block bounds, centers and draws
;   50x7 modal pop-up box displaying selection metrics, action shortcuts
;   (Lock, Copy, Move, Del, Save, Clear), and dispatches user key commands.
;
; Call Usage / Protocol:
;   Jumped to from MAIN_LOOP on Ctrl+K when BLOCK_ACTIVE is non-zero.
;
; Inputs:
;   ACTIVE_COLS, ACTIVE_ROWS, BLOCK_ACTIVE.
;
; Outputs:
;   Executes selected block operation and resumes editor.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_BLOCK_MENU_POPUP:
	CALL FLUSH_DEFERRED_RENDER
	CALL NORMALIZE_BLOCK_BOUNDS

	; Calculate centering: POPUP_COL = ((ACTIVE_COLS - 50) / 2) + 1
	LD A,(ACTIVE_COLS)
	SUB 50
	SRL A
	INC A
	LD (POPUP_COL),A

	; POPUP_ROW = ((ACTIVE_ROWS - 7) / 2) + 1
	LD A,(ACTIVE_ROWS)
	SUB 7
	SRL A
	INC A
	LD (POPUP_ROW),A

	CALL TERM_HIDE_CURSOR

	; Line 1: Top border
	CALL POPUP_PRINT_BORDER

	; Line 2: Title
	CALL POPUP_LOCATE_NEXT
	LD DE,STR_BLOCK_POPUP_TITLE
	CALL PRINT_STR

	; Line 3: Separator border
	CALL POPUP_PRINT_BORDER

	; Line 4: Dynamic Selection / Block count
	CALL FORMAT_BLOCK_POPUP_LINE4
	CALL POPUP_LOCATE_NEXT
	LD DE,BLOCK_POPUP_LINE4_BUF
	CALL PRINT_STR

	; Line 5: Primary Actions (Dynamic vs Solidified)
	CALL POPUP_LOCATE_NEXT
	LD A,(BLOCK_ACTIVE)
	CP 2
	JR Z,BMP_DRAW_SOLID_LINE5
	LD DE,STR_BLOCK_POPUP_KEYS_SEL
	JR BMP_DRAW_LINE5
BMP_DRAW_SOLID_LINE5:
	LD DE,STR_BLOCK_POPUP_KEYS_BLK
BMP_DRAW_LINE5:
	CALL PRINT_STR

	; Line 6: Commands
	CALL POPUP_LOCATE_NEXT
	LD DE,STR_BLOCK_POPUP_CMDS
	CALL PRINT_STR

	; Line 7: Bottom border
	CALL POPUP_PRINT_BORDER

BMP_KEY_LOOP:
	CALL GET_KEY
	CP KEY_ESC
	JR Z,BMP_ESC
	CP KEY_ENTER
	JR Z,BMP_ENTER
	CP KEY_CTRL_B
	JR Z,BMP_CLEAR
	CP 'b'
	JR Z,BMP_CLEAR
	CP 'B'
	JR Z,BMP_CLEAR
	CP KEY_CTRL_C
	JR Z,BMP_COPY
	CP 'c'
	JR Z,BMP_COPY
	CP 'C'
	JR Z,BMP_COPY
	CP KEY_CTRL_X
	JR Z,BMP_MOVE
	CP 'x'
	JR Z,BMP_MOVE
	CP 'X'
	JR Z,BMP_MOVE
	CP KEY_CTRL_D
	JR Z,BMP_DEL
	CP 'd'
	JR Z,BMP_DEL
	CP 'D'
	JR Z,BMP_DEL
	CP KEY_DEL
	JR Z,BMP_DEL
	CP KEY_CTRL_S
	JR Z,BMP_SAVE
	CP 's'
	JR Z,BMP_SAVE
	CP 'S'
	JR Z,BMP_SAVE
	JR BMP_KEY_LOOP

BMP_ESC:
	CALL DRAIN_ESC_SEQUENCE
	CALL BMP_RESTORE_SCREEN
	JP MAIN_LOOP

BMP_CLEAR:
	CALL CANCEL_BLOCK
	CALL BMP_RESTORE_SCREEN
	JP MAIN_LOOP

BMP_ENTER:
	CALL SOLIDIFY_BLOCK
	CALL BMP_RESTORE_SCREEN
	JP MAIN_LOOP

BMP_COPY:
	CALL SOLIDIFY_BLOCK
	CALL BMP_RESTORE_SCREEN
	CALL DO_COPY_BLOCK
	JP MAIN_LOOP

BMP_MOVE:
	CALL SOLIDIFY_BLOCK
	CALL BMP_RESTORE_SCREEN
	CALL DO_MOVE_BLOCK
	JP MAIN_LOOP

BMP_DEL:
	CALL SOLIDIFY_BLOCK
	CALL BMP_RESTORE_SCREEN
	CALL DO_DELETE_BLOCK
	JP MAIN_LOOP

BMP_SAVE:
	CALL SOLIDIFY_BLOCK
	CALL DO_BLOCK_SAVE_FILE
	JP MAIN_LOOP

;------------------------------------------------------------------------------
; BMP_RESTORE_SCREEN: Restore editor screen and cursor after block modal exit
;
; Purpose:
;   Reinitializes terminal attributes, redraws editor viewport and status
;   bar, restores cursor visibility, and positions cursor at active text column.
;
; Call Usage / Protocol:
;   Called via CALL upon dismissing or executing actions in DO_BLOCK_MENU_POPUP.
;
; Inputs:
;   None.
;
; Outputs:
;   Screen repainted and cursor positioned.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
BMP_RESTORE_SCREEN:
	CALL TERM_INIT
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	CALL TERM_SHOW_CURSOR
	CALL LOCATE_CURSOR
	XOR A
	LD (NEED_SCREEN_RENDER),A
	LD (NEED_LINE_RENDER),A
	LD (NEED_STATUS_RENDER),A
	RET

;------------------------------------------------------------------------------
; FORMAT_BLOCK_POPUP_LINE4: Format selection status line for block modal dialog
;
; Purpose:
;   Constructs centered message string for row 4 of the block menu dialog
;   (e.g. "| Selection: 5 lines |" or "| Marked Block: 12 chars |"), centered
;   symmetrically within the 50-column dialog box frame.
;
; Call Usage / Protocol:
;   Called via CALL from DO_BLOCK_MENU_POPUP.
;
; Inputs:
;   BLOCK_ACTIVE, normalized block bounds.
;
; Outputs:
;   BLOCK_POPUP_LINE4_BUF populated with 50 characters plus null terminator.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
FORMAT_BLOCK_POPUP_LINE4:
	PUSH BC
	PUSH DE
	PUSH IX

	; 1. Pre-fill BLOCK_POPUP_LINE4_BUF with '|', 48 spaces, '|', 0
	LD HL,BLOCK_POPUP_LINE4_BUF
	LD (HL),'|'
	INC HL
	LD B,48
	LD A,' '
FBPL_FILL:
	LD (HL),A
	INC HL
	DJNZ FBPL_FILL
	LD (HL),'|'
	INC HL
	LD (HL),0

	; 2. Check if single-line or multi-line
	CALL NORMALIZE_BLOCK_BOUNDS
	LD HL,(BLOCK_START_ROW)
	LD DE,(BLOCK_END_ROW)
	LD A,H
	CP D
	JR NZ,FBPL_MULTILINE
	LD A,L
	CP E
	JR NZ,FBPL_MULTILINE

	; Single line: char count = BLOCK_END_COL - BLOCK_START_COL
	LD A,(BLOCK_END_COL)
	LD HL,BLOCK_START_COL
	SUB (HL)				; A = char count
	LD L,A
	LD H,0
	PUSH HL					; Save count on stack
	CALL GET_DEC_WORD_DIGITS		; A = digits (1..5)
	LD B,A					; B = digits
	; Suffix: if count == 1, " char" (5 chars); else " chars" (6 chars)
	POP HL					; HL = count
	PUSH HL					; Keep count on stack
	LD A,H
	OR A
	JR NZ,FBPL_CHARS
	LD A,L
	CP 1
	JR NZ,FBPL_CHARS
	LD IY,STR_STAT_CHAR_S			; " char"
	LD E,5					; suffix len in E
	JR FBPL_GET_PREFIX
FBPL_CHARS:
	LD IY,STR_STAT_CHARS_S			; " chars"
	LD E,6					; suffix len in E
	JR FBPL_GET_PREFIX

FBPL_MULTILINE:
	CALL GET_BLOCK_BOUNDS			; BC = line count
	LD L,C
	LD H,B
	PUSH HL					; Save count on stack
	CALL GET_DEC_WORD_DIGITS		; A = digits (1..5)
	LD B,A					; B = digits
	; Suffix: if count == 1, " line" (5 chars); else " lines" (6 chars)
	POP HL					; HL = count
	PUSH HL					; Keep count on stack
	LD A,H
	OR A
	JR NZ,FBPL_LINES
	LD A,L
	CP 1
	JR NZ,FBPL_LINES
	LD IY,STR_STAT_LINE_S			; " line"
	LD E,5					; suffix len in E
	JR FBPL_GET_PREFIX
FBPL_LINES:
	LD IY,STR_STAT_LINES_S			; " lines"
	LD E,6					; suffix len in E

FBPL_GET_PREFIX:
	; 3. Determine prefix pointer and length (safe after GET_BLOCK_BOUNDS)
	LD A,(BLOCK_ACTIVE)
	CP 2
	JR Z,FBPL_PRE_BLK
	LD IX,STR_BLOCK_POPUP_SEL_PRE		; "Selection: "
	LD C,11					; prefix len in C
	JR FBPL_CALC_LEN
FBPL_PRE_BLK:
	LD IX,STR_BLOCK_POPUP_BLK_PRE		; "Marked Block: "
	LD C,14					; prefix len in C

FBPL_CALC_LEN:
	; Total length L = C (prefix) + B (digits) + E (suffix)
	LD A,C
	ADD A,B
	ADD A,E					; A = total text length L
	; Left spaces = (48 - L) / 2
	LD D,A					; D = L
	LD A,48
	SUB D					; A = 48 - L
	SRL A					; A = (48 - L) / 2
	INC A					; + 1 for initial '|'
	; Target destination in HL = BLOCK_POPUP_LINE4_BUF + A
	LD HL,BLOCK_POPUP_LINE4_BUF
	LD D,0
	LD E,A
	ADD HL,DE				; HL = target destination

	; 4. Copy prefix (C chars from IX to HL)
	PUSH BC					; Save B=digits, C=prefix len
	LD B,C
FBPL_CPY_PRE:
	LD A,(IX)
	LD (HL),A
	INC IX
	INC HL
	DJNZ FBPL_CPY_PRE
	POP BC					; Restore B=digits

	; 5. Format digits and copy to HL
	EX DE,HL				; DE = dest
	POP HL					; HL = count (from stack)
	PUSH DE					; Save dest on stack
	CALL FORMAT_DEC_WORD_RAM		; DE = pointer to first digit
	POP HL					; HL = dest
FBPL_CPY_DIG:
	LD A,(DE)
	LD (HL),A
	INC DE
	INC HL
	DJNZ FBPL_CPY_DIG

	; 6. Copy suffix from IY until '$' or 0
FBPL_CPY_SUF:
	LD A,(IY)
	CP '$'
	JR Z,FBPL_DONE
	OR A
	JR Z,FBPL_DONE
	LD (HL),A
	INC IY
	INC HL
	JR FBPL_CPY_SUF

FBPL_DONE:
	POP IX
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; NORMALIZE_BLOCK_BOUNDS: Normalize block coordinates into canonical START/END
;
; Purpose:
;   Ensures (BLOCK_START_ROW, BLOCK_START_COL) precedes (BLOCK_END_ROW,
;   BLOCK_END_COL) in document reading order, accounting for both forward
;   and backward cursor selection across single or multiple lines.
;
; Call Usage / Protocol:
;   Called via CALL prior to block operations, rendering, and dialog queries.
;
; Inputs:
;   BLOCK_ANCHOR_ROW, BLOCK_ANCHOR_COL, CUR_DOC_ROW, CUR_COL.
;
; Outputs:
;   BLOCK_START_ROW, BLOCK_START_COL, BLOCK_END_ROW, BLOCK_END_COL populated.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
NORMALIZE_BLOCK_BOUNDS:
	LD A,(BLOCK_ACTIVE)
	OR A
	RET Z				; No block active
	CP 2
	RET Z				; Already solidified, bounds locked

	PUSH BC
	PUSH DE
	PUSH HL

	LD HL,(BLOCK_ANCHOR_ROW)
	LD DE,(CUR_DOC_ROW)
	LD BC,(BLOCK_ANCHOR_COL)

	; Compare HL (anchor row) and DE (cursor row)
	LD A,H
	CP D
	JR C,NBB_ANCHOR_FIRST
	JR NZ,NBB_CUR_FIRST
	LD A,L
	CP E
	JR C,NBB_ANCHOR_FIRST
	JR NZ,NBB_CUR_FIRST

	; Same row: compare BC (anchor col) and (CUR_COL)
	LD (BLOCK_START_ROW),HL
	LD (BLOCK_END_ROW),HL
	LD HL,(CUR_COL)
	; Compare BC with HL:
	LD A,B
	CP H
	JR C,NBB_COL_BC
	JR NZ,NBB_COL_CB
	LD A,C
	CP L
	JR C,NBB_COL_BC
	JR Z,NBB_COL_BC

NBB_COL_CB:
	; BC > HL: Cursor is to the left of Anchor (backwards on same row)
	; Cursor at HL is excluded -> BLOCK_START_COL = HL + 1
	; Anchor at BC is included -> BLOCK_END_COL = BC + 1
	INC HL
	LD (BLOCK_START_COL),HL
	INC BC
	LD (BLOCK_END_COL),BC
	JR NBB_DONE

NBB_COL_BC:
	; BC <= HL: Forward (or empty) selection on same row
	LD (BLOCK_START_COL),BC
	LD (BLOCK_END_COL),HL
	JR NBB_DONE

NBB_ANCHOR_FIRST:
	LD (BLOCK_START_ROW),HL
	LD (BLOCK_START_COL),BC
	LD (BLOCK_END_ROW),DE
	LD HL,(CUR_COL)
	LD (BLOCK_END_COL),HL
	JR NBB_DONE

NBB_CUR_FIRST:
	; DE (Cursor Row) < HL (Anchor Row): Backwards multi-row selection
	; Cursor at (DE, CUR_COL) is excluded -> START_ROW = DE, START_COL =
	; CUR_COL + 1
	; Anchor at (HL, BC) is included -> END_ROW = HL, END_COL = BC + 1
	LD (BLOCK_START_ROW),DE
	LD DE,(CUR_COL)
	INC DE
	LD (BLOCK_START_COL),DE
	LD (BLOCK_END_ROW),HL
	INC BC
	LD (BLOCK_END_COL),BC

NBB_DONE:
	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; GET_BLOCK_BOUNDS: Retrieve normalized boundaries and line count of block
;
; Purpose:
;   Returns starting and ending document row indices along with total number
;   of lines spanned by the active block selection.
;
; Call Usage / Protocol:
;   Called via CALL by block formatting and manipulation routines.
;
; Inputs:
;   BLOCK_ACTIVE.
;
; Outputs:
;   Carry = 0, HL = start doc row, DE = end doc row, BC = line count;
;   Carry = 1 if no block active.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
GET_BLOCK_BOUNDS:
	LD A,(BLOCK_ACTIVE)
	OR A
	SCF
	RET Z

	CALL NORMALIZE_BLOCK_BOUNDS

	LD HL,(BLOCK_START_ROW)
	LD DE,(BLOCK_END_ROW)
	PUSH DE
	EX DE,HL			; DE = start, HL = end
	AND A
	SBC HL,DE			; HL = end - start
	; If BLOCK_END_COL > 0, end row contributes characters, so INC HL.
	; If BLOCK_END_COL == 0 and end > start, end row is exclusive.
	; If HL == 0 (single line), minimum is 1 line.
	LD A,(BLOCK_END_COL)
	OR A
	JR NZ,GBB_INC_LINE
	LD A,H
	OR L
	JR NZ,GBB_DONE_LINE
GBB_INC_LINE:
	INC HL
GBB_DONE_LINE:
	LD B,H
	LD C,L				; BC = line count
	POP DE				; DE = end
	EX DE,HL			; HL = start, DE = end
	OR A				; Carry = 0 (success)
	RET

;------------------------------------------------------------------------------
; GET_LINE_BLOCK_RANGE: Compute character highlight column span for document row
;
; Purpose:
;   Determines whether document row BC intersects active visual block, and
;   if so, computes the first and last character columns that must be drawn
;   with reverse video highlighting.
;
; Call Usage / Protocol:
;   Called via CALL by line rendering loops and single-line block delete.
;
; Inputs:
;   BC = 16-bit Document Line Index (0..3583).
;
; Outputs:
;   Carry = 0: D = start char col, E = end char col (254 = to end of line);
;   Carry = 1: row contains no highlighted characters.
;
; Preserves / Modifies:
;   Preserves BC, HL; clobbers AF, DE.
;------------------------------------------------------------------------------
GET_LINE_BLOCK_RANGE:
	LD A,(BLOCK_ACTIVE)
	OR A
	JR NZ,GLBR_IS_ACTIVE
	XOR A
	LD (LINE_BLK_ACTIVE),A
	SCF
	RET			; Carry = 1: no block active

GLBR_IS_ACTIVE:

	PUSH BC
	PUSH HL

	CALL NORMALIZE_BLOCK_BOUNDS

	; Check if BC < BLOCK_START_ROW
	LD HL,(BLOCK_START_ROW)
	LD A,B
	CP H
	JP C,GLBR_NONE
	JR NZ,GLBR_CHECK_MAX
	LD A,C
	CP L
	JP C,GLBR_NONE

GLBR_CHECK_MAX:
	; Check if BC > BLOCK_END_ROW
	LD HL,(BLOCK_END_ROW)
	LD A,H
	CP B
	JP C,GLBR_NONE
	JR NZ,GLBR_IN_RANGE
	LD A,L
	CP C
	JP C,GLBR_NONE

GLBR_IN_RANGE:
	; BC is within [BLOCK_START_ROW, BLOCK_END_ROW]
	; Check if BC == BLOCK_START_ROW
	LD HL,(BLOCK_START_ROW)
	LD A,B
	CP H
	JR NZ,GLBR_NOT_START_ROW
	LD A,C
	CP L
	JR NZ,GLBR_NOT_START_ROW

	; BC == BLOCK_START_ROW!
	; Check if it is also BLOCK_END_ROW (single line block)
	LD HL,(BLOCK_END_ROW)
	LD A,B
	CP H
	JR NZ,GLBR_START_ONLY
	LD A,C
	CP L
	JR NZ,GLBR_START_ONLY

	; Single-line block: StartCol = BLOCK_START_COL, EndCol = BLOCK_END_COL
	; - 1
	LD HL,(BLOCK_START_COL)
	LD DE,(BLOCK_END_COL)
	; Compare HL with DE:
	LD A,H
	CP D
	JR C,GLBR_SINGLE_OK
	JR NZ,GLBR_NONE
	LD A,L
	CP E
	JR NC,GLBR_NONE			; StartCol >= EndCol -> no highlight

GLBR_SINGLE_OK:
	LD (LINE_BLK_START),HL
	DEC DE
	LD (LINE_BLK_END),DE
	LD D,L
	LD E,E
	JR GLBR_OK

GLBR_START_ONLY:
	; First line of multi-line block: StartCol = BLOCK_START_COL, EndCol =
	; to EOL
	LD HL,(BLOCK_START_COL)
	LD (LINE_BLK_START),HL
	LD HL,0FFFFH
	LD (LINE_BLK_END),HL
	LD D,L
	LD E,254
	JR GLBR_OK

GLBR_NOT_START_ROW:
	; BC > BLOCK_START_ROW. Check if BC == BLOCK_END_ROW
	LD HL,(BLOCK_END_ROW)
	LD A,B
	CP H
	JR NZ,GLBR_MIDDLE_ROW
	LD A,C
	CP L
	JR NZ,GLBR_MIDDLE_ROW

	; Last line of multi-line block: StartCol = 0, EndCol = BLOCK_END_COL -
	; 1
	LD DE,(BLOCK_END_COL)
	LD A,D
	OR E
	JR Z,GLBR_NONE		; BLOCK_END_COL == 0 -> no chars on this line!

	DEC DE
	LD (LINE_BLK_END),DE
	LD HL,0
	LD (LINE_BLK_START),HL
	LD D,0
	LD E,E
	JR GLBR_OK

GLBR_MIDDLE_ROW:
	; Middle full line: StartCol = 0, EndCol = to EOL
	LD HL,0
	LD (LINE_BLK_START),HL
	LD HL,0FFFFH
	LD (LINE_BLK_END),HL
	LD D,0
	LD E,254

GLBR_OK:
	LD A,1
	LD (LINE_BLK_ACTIVE),A
	POP HL
	POP BC
	OR A				; Carry = 0: line has block range
	RET

GLBR_NONE:
	XOR A
	LD (LINE_BLK_ACTIVE),A
	POP HL
	POP BC
	SCF				; Carry = 1: no block on this line
	RET

;------------------------------------------------------------------------------
; GLBR_CHECK_TAB_END: If character at EndCol (E) is a TAB, exclude it from
; highlight
; Inputs: BC = doc row, D = StartCol, E = EndCol
; Returns: Carry = 0: E adjusted (or unchanged)
; Carry = 1: line has no highlight left (EndCol decremented below StartCol)
; Preserves: BC, D
;------------------------------------------------------------------------------
GLBR_CHECK_TAB_END:
	PUSH BC
	PUSH DE
	; HL = pointer to line start in LINE_STORAGE
	CALL ENSURE_CACHE_WINDOW
	POP DE
	POP BC

	PUSH HL
	PUSH DE
	LD D,0
	ADD HL,DE			; HL = line_start + EndCol
	LD A,(HL)
	POP DE
	POP HL

	CP KEY_TAB			; Is character at EndCol a TAB?
	JR Z,GCTE_IS_TAB
	OR A				; Carry = 0
	RET

GCTE_IS_TAB:
	LD A,E
	CP D
	JR Z,GCTE_NO_CHARS
	DEC E
	OR A				; Carry = 0
	RET

GCTE_NO_CHARS:
	SCF				; Carry = 1: no highlight on this line
	RET

;------------------------------------------------------------------------------
; DO_DELETE_BLOCK: Delete text within solidified block selection
;
; Purpose:
;   Deletes highlighted block (state 2). For single-line blocks, shifts
;   trailing characters left. For multi-line blocks, truncates start row,
;   concatenates end row tail, frees intermediate line slots, shifts line
;   table entries downwards, adjusts total lines, and updates cursor.
;
; Call Usage / Protocol:
;   Called via CALL from block pop-up or on Ctrl+D / Del key.
;
; Inputs:
;   BLOCK_ACTIVE (must be 2), normalized block bounds.
;
; Outputs:
;   Block deleted; BLOCK_ACTIVE = 0; DOC_MODIFIED = 1; cursor updated.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_DELETE_BLOCK:
	LD A,(BLOCK_ACTIVE)
	CP 2				; Only solidified blocks can be deleted
	RET NZ

	CALL INVALIDATE_ACTIVE_LINE
	CALL FLUSH_DIRTY_CACHE
	CALL NORMALIZE_BLOCK_BOUNDS

	; Check if single-line or multi-line block
	LD HL,(BLOCK_START_ROW)
	LD DE,(BLOCK_END_ROW)
	LD A,H
	CP D
	JR NZ,DO_DEL_BLK_MULTILINE
	LD A,L
	CP E
	JR NZ,DO_DEL_BLK_MULTILINE

	;---------------------------------------------------------------------
	; CASE 1: Single-Line Block Deletion
	;---------------------------------------------------------------------
DO_DEL_BLK_SINGLE:
	LD BC,(BLOCK_START_ROW)
	CALL GET_LINE_BLOCK_RANGE	; Carry=0: D = StartCol, E = EndCol
	JP C,DO_DEL_BLK_FINISH	; If Carry=1, no characters in block range

	PUSH DE				; D = StartCol, E = EndCol

	; Read the line into LOAD_LINE_TEMP
	LD BC,(BLOCK_START_ROW)
	LD DE,LOAD_LINE_TEMP
	CALL READ_FAR_LINE

	POP BC				; B = StartCol, C = EndCol

	; Source pointer: HL = LOAD_LINE_TEMP + EndCol + 1
	LD HL,LOAD_LINE_TEMP
	LD A,C
	INC A
	LD E,A
	LD D,0
	ADD HL,DE		; HL = LOAD_LINE_TEMP + EndCol + 1 (source)

	; Destination pointer: DE = LOAD_LINE_TEMP + StartCol
	LD DE,LOAD_LINE_TEMP
	LD A,B
	LD C,A
	LD B,0
	EX DE,HL
	ADD HL,BC
	EX DE,HL			; DE = destination

	; Shift characters left from HL into DE until null terminator
DEL_BLK_SINGLE_SHIFT:
	LD A,(HL)
	LD (DE),A
	INC HL
	INC DE
	OR A
	JR NZ,DEL_BLK_SINGLE_SHIFT

	; Write updated line back to Far RAM
	LD BC,(BLOCK_START_ROW)
	LD HL,LOAD_LINE_TEMP
	CALL WRITE_FAR_LINE

	; Update cursor position to (BLOCK_START_ROW, BLOCK_START_COL)
	LD HL,(BLOCK_START_ROW)
	LD (CUR_DOC_ROW),HL
	LD A,(BLOCK_START_COL)
	LD (CUR_COL),A
	CALL CALC_VISUAL_COL
	LD (TARGET_COL),A

	JP DO_DEL_BLK_FINISH

	;---------------------------------------------------------------------
	; CASE 2: Multi-Line Block Deletion
	;---------------------------------------------------------------------
DO_DEL_BLK_MULTILINE:
	; Step 1: Process head of first line (BLOCK_START_ROW)
	; Read first line into LOAD_LINE_TEMP
	LD BC,(BLOCK_START_ROW)
	LD DE,LOAD_LINE_TEMP
	CALL READ_FAR_LINE

	; Truncate at StartCol by writing null terminator
	LD HL,LOAD_LINE_TEMP
	LD A,(BLOCK_START_COL)
	LD E,A
	LD D,0
	ADD HL,DE
	LD (HL),0			; Truncate head

	; Step 2: Process tail of last line (BLOCK_END_ROW)
	LD BC,(BLOCK_END_ROW)
	; Carry=0: D=0, E=EndCol. Carry=1: no highlight
	CALL GET_LINE_BLOCK_RANGE
	JR C,DEL_BLK_TAIL_WHOLE

	; Save E (EndCol)
	LD A,E
	PUSH AF

	; Read last line into SPLIT_LINE_TEMP
	LD BC,(BLOCK_END_ROW)
	LD DE,SPLIT_LINE_TEMP
	CALL READ_FAR_LINE

	POP AF				; A = EndCol
	INC A
	LD E,A
	LD D,0
	LD HL,SPLIT_LINE_TEMP
	ADD HL,DE		; HL = pointer to tail in SPLIT_LINE_TEMP
	JR DEL_BLK_CONCAT_TAIL

DEL_BLK_TAIL_WHOLE:
	; Whole last line is kept (tail starts at offset 0)
	LD BC,(BLOCK_END_ROW)
	LD DE,SPLIT_LINE_TEMP
	CALL READ_FAR_LINE
	LD HL,SPLIT_LINE_TEMP		; HL = pointer to tail (offset 0)

DEL_BLK_CONCAT_TAIL:
	; HL = tail in SPLIT_LINE_TEMP.
	; Append tail to LOAD_LINE_TEMP starting at BLOCK_START_COL
	PUSH HL				; Save tail pointer
	LD HL,LOAD_LINE_TEMP
	LD A,(BLOCK_START_COL)
	LD E,A
	LD D,0
	ADD HL,DE			; HL = destination in LOAD_LINE_TEMP
	POP DE				; DE = source tail pointer

	LD A,(BLOCK_START_COL)
	LD C,A				; C = current length
DEL_BLK_APPEND_LOOP:
	LD A,(DE)
	OR A
	JR Z,DEL_BLK_APPEND_DONE
	LD A,C
	CP MAX_CACHE_LINE_CHARS		; max 250 chars
	JR NC,DEL_BLK_APPEND_DONE	; Stop if capacity reached
	LD A,(DE)
	LD (HL),A
	INC DE
	INC HL
	INC C
	JR DEL_BLK_APPEND_LOOP

DEL_BLK_APPEND_DONE:
	LD (HL),0			; Null-terminate merged line

	; Write merged line back to BLOCK_START_ROW
	LD BC,(BLOCK_START_ROW)
	LD HL,LOAD_LINE_TEMP
	CALL WRITE_FAR_LINE

	; Step 3: Free slots for lines (BLOCK_START_ROW + 1) through
	; (BLOCK_END_ROW)
	LD HL,(BLOCK_START_ROW)
	INC HL
	LD (DEL_BLK_CUR_LINE),HL

DEL_BLK_FREE_LOOP:
	; Compare DEL_BLK_CUR_LINE with BLOCK_END_ROW
	LD HL,(BLOCK_END_ROW)
	LD DE,(DEL_BLK_CUR_LINE)
	; If DE > HL, done freeing
	LD A,H
	CP D
	JR C,DEL_BLK_FREE_DONE
	JR NZ,DO_FREE_CUR_SLOT
	LD A,L
	CP E
	JR C,DEL_BLK_FREE_DONE

DO_FREE_CUR_SLOT:
	; Lookup and free slot ID for DEL_BLK_CUR_LINE
	LD BC,(DEL_BLK_CUR_LINE)
	CALL GET_LINE_SLOT		; HL = slot ID
	CALL FREE_LINE_CHAIN

	LD HL,(DEL_BLK_CUR_LINE)
	INC HL
	LD (DEL_BLK_CUR_LINE),HL
	JR DEL_BLK_FREE_LOOP

DEL_BLK_FREE_DONE:
	; Step 4: Shift line table entries above BLOCK_END_ROW downwards to
	; BLOCK_START_ROW + 1
	; Lines removed: K = BLOCK_END_ROW - BLOCK_START_ROW
	; Number of entries to shift: W = DOC_TOTAL_LINES - (BLOCK_END_ROW + 1)
	LD HL,(DOC_TOTAL_LINES)
	LD DE,(BLOCK_END_ROW)
	INC DE				; DE = BLOCK_END_ROW + 1
	AND A
	SBC HL,DE		; HL = W = DOC_TOTAL_LINES - (BLOCK_END_ROW + 1)
	JR Z,DEL_BLK_NO_SHIFT
	JR C,DEL_BLK_NO_SHIFT

	; W > 0: shift entries up towards lower line numbers
	LD B,H
	LD C,L				; BC = W (word count)
	LD DE,(BLOCK_START_ROW)
	INC DE			; DE = destination line = BLOCK_START_ROW + 1
	LD HL,(BLOCK_END_ROW)
	INC HL				; HL = source line = BLOCK_END_ROW + 1
	CALL SHIFT_LINE_SLOTS_UP

DEL_BLK_NO_SHIFT:
	; Update DOC_TOTAL_LINES = DOC_TOTAL_LINES - (BLOCK_END_ROW -
	; BLOCK_START_ROW)
	LD HL,(BLOCK_END_ROW)
	LD DE,(BLOCK_START_ROW)
	AND A
	SBC HL,DE			; HL = K
	EX DE,HL			; DE = K
	LD HL,(DOC_TOTAL_LINES)
	AND A
	SBC HL,DE			; HL = DOC_TOTAL_LINES - K
	LD A,H
	OR L
	JR NZ,DEL_BLK_TOTAL_SET
	INC HL				; Minimum 1 line!
DEL_BLK_TOTAL_SET:
	LD (DOC_TOTAL_LINES),HL

	; Step 5: Update cursor position to (BLOCK_START_ROW, BLOCK_START_COL)
	LD HL,(BLOCK_START_ROW)
	LD (CUR_DOC_ROW),HL
	LD A,(BLOCK_START_COL)
	LD (CUR_COL),A
	CALL CALC_VISUAL_COL
	LD (TARGET_COL),A

	; Step 6: Ensure TOP_DOC_ROW does not scroll past EOF
	LD HL,(CUR_DOC_ROW)
	LD DE,(TOP_DOC_ROW)
	LD A,H
	CP D
	JR C,DEL_BLK_ADJ_TOP
	JR NZ,DO_DEL_BLK_FINISH
	LD A,L
	CP E
	JR NC,DO_DEL_BLK_FINISH
DEL_BLK_ADJ_TOP:
	LD (TOP_DOC_ROW),HL

DO_DEL_BLK_FINISH:
	XOR A
	LD (BLOCK_ACTIVE),A		; Deactivate block mode!
	CALL INVALIDATE_ACTIVE_LINE
	CALL RELOAD_CACHE_WINDOW_FORCE
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	LD (DOC_MODIFIED),A
	RET

;------------------------------------------------------------------------------
; CHECK_CURSOR_IN_BLOCK: Test if cursor coordinates lie within active block
;
; Purpose:
;   Compares (CUR_DOC_ROW, CUR_COL) against normalized block bounds to detect
;   whether cursor is situated inside the selection (or on its boundary).
;
; Call Usage / Protocol:
;   Called via CALL before DO_COPY_BLOCK and DO_MOVE_BLOCK to prevent
;   illegal insertion into the block itself.
;
; Inputs:
;   CUR_DOC_ROW, CUR_COL, normalized block bounds.
;
; Outputs:
;   Carry = 1 if cursor is inside block; Carry = 0 if cursor is outside.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; modifies AF (flags).
;------------------------------------------------------------------------------
CHECK_CURSOR_IN_BLOCK:
	PUSH HL
	PUSH DE
	PUSH BC

	; Check if CUR_DOC_ROW < BLOCK_START_ROW
	LD HL,(CUR_DOC_ROW)
	LD DE,(BLOCK_START_ROW)
	LD A,H
	CP D
	JR C,CCIB_OUTSIDE
	JR NZ,CCIB_CHECK_MAX_ROW
	LD A,L
	CP E
	JR C,CCIB_OUTSIDE

CCIB_CHECK_MAX_ROW:
	; Check if CUR_DOC_ROW > BLOCK_END_ROW
	LD HL,(BLOCK_END_ROW)
	LD DE,(CUR_DOC_ROW)
	LD A,H
	CP D
	JR C,CCIB_OUTSIDE
	JR NZ,CCIB_CHECK_COLS
	LD A,L
	CP E
	JR C,CCIB_OUTSIDE

CCIB_CHECK_COLS:
	; CUR_DOC_ROW is within [BLOCK_START_ROW, BLOCK_END_ROW]
	; Check if single-line block
	LD HL,(BLOCK_START_ROW)
	LD DE,(BLOCK_END_ROW)
	LD A,H
	CP D
	JR NZ,CCIB_CHECK_MULTI
	LD A,L
	CP E
	JR NZ,CCIB_CHECK_MULTI

	; Single-line block: StartCol = BLOCK_START_COL, EndCol = BLOCK_END_COL
	; (exclusive)
	; Inside only if BLOCK_START_COL <= CUR_COL < BLOCK_END_COL
	LD HL,(CUR_COL)
	LD DE,(BLOCK_START_COL)
	AND A
	SBC HL,DE
	JR C,CCIB_OUTSIDE		; CUR_COL < BLOCK_START_COL -> outside!

	LD HL,(CUR_COL)
	LD DE,(BLOCK_END_COL)
	AND A
	SBC HL,DE
	JR C,CCIB_INSIDE		; CUR_COL < BLOCK_END_COL -> inside!
	JR CCIB_OUTSIDE

CCIB_CHECK_MULTI:
	; Multi-line block:
	; Is CUR_DOC_ROW == BLOCK_START_ROW?
	LD HL,(CUR_DOC_ROW)
	LD DE,(BLOCK_START_ROW)
	LD A,H
	CP D
	JR NZ,CCIB_CHECK_MULTI_END
	LD A,L
	CP E
	JR NZ,CCIB_CHECK_MULTI_END

	; On BLOCK_START_ROW: inside if CUR_COL >= BLOCK_START_COL
	LD HL,(CUR_COL)
	LD DE,(BLOCK_START_COL)
	AND A
	SBC HL,DE
	JR C,CCIB_OUTSIDE		; CUR_COL < BLOCK_START_COL -> outside!
	JR CCIB_INSIDE

CCIB_CHECK_MULTI_END:
	; Is CUR_DOC_ROW == BLOCK_END_ROW?
	LD HL,(CUR_DOC_ROW)
	LD DE,(BLOCK_END_ROW)
	LD A,H
	CP D
	; Middle row of multi-line block is always inside!
	JR NZ,CCIB_INSIDE
	LD A,L
	CP E
	JR NZ,CCIB_INSIDE

	; On BLOCK_END_ROW: inside only if CUR_COL < BLOCK_END_COL (exclusive)
	LD HL,(CUR_COL)
	LD DE,(BLOCK_END_COL)
	AND A
	SBC HL,DE
	JR C,CCIB_INSIDE
	JR CCIB_OUTSIDE

CCIB_INSIDE:
	POP BC
	POP DE
	POP HL
	SCF				; Carry = 1: inside block
	RET

CCIB_OUTSIDE:
	POP BC
	POP DE
	POP HL
	OR A				; Carry = 0: outside block
	RET

;------------------------------------------------------------------------------
; DO_COPY_BLOCK: Copy solidified block selection to current cursor position
;
; Purpose:
;   Copies selected text to current cursor location (CUR_DOC_ROW, CUR_COL).
;   Supports single-line insertion or multi-line block expansion, allocating
;   new Far RAM line slots and shifting line table entries upwards as needed.
;
; Call Usage / Protocol:
;   Called via CALL on Ctrl+C when block is solidified (state 2).
;
; Inputs:
;   BLOCK_ACTIVE = 2, CUR_DOC_ROW, CUR_COL.
;
; Outputs:
;   Block copied into document; DOC_MODIFIED = 1; cursor updated.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_COPY_BLOCK:
	LD A,(BLOCK_ACTIVE)
	CP 2				; Only solidified blocks can be copied
	RET NZ

	CALL NORMALIZE_BLOCK_BOUNDS

	; Check if cursor is inside the block; if so, ignore Ctrl+C!
	CALL CHECK_CURSOR_IN_BLOCK
	RET C

	CALL INVALIDATE_ACTIVE_LINE
	CALL FLUSH_DIRTY_CACHE

	; Check if single-line or multi-line block
	LD HL,(BLOCK_START_ROW)
	LD DE,(BLOCK_END_ROW)
	LD A,H
	CP D
	JP NZ,DO_COPY_BLK_MULTILINE
	LD A,L
	CP E
	JP NZ,DO_COPY_BLK_MULTILINE

	;---------------------------------------------------------------------
	; CASE 1: Single-Line Block Copy
	;---------------------------------------------------------------------
DO_COPY_BLK_SINGLE:
	; Read source line BLOCK_START_ROW into SPLIT_LINE_TEMP
	LD BC,(BLOCK_START_ROW)
	LD DE,SPLIT_LINE_TEMP
	LD HL,MAX_ACTIVE_LINE_STRIDE-2		; 1022
	CALL READ_FAR_LINE_MAX

	; Measure source line length
	LD HL,SPLIT_LINE_TEMP
	LD BC,0
COPY_SGL_SRC_LEN:
	LD A,(HL)
	OR A
	JR Z,COPY_SGL_SRC_LEN_DONE
	INC HL
	INC BC
	JR COPY_SGL_SRC_LEN
COPY_SGL_SRC_LEN_DONE:
	; BC = source line length
	; Check if BLOCK_START_COL >= src_len (BC)
	LD HL,(BLOCK_START_COL)
	AND A
	SBC HL,BC
	RET NC			; BLOCK_START_COL >= src_len -> nothing to copy!

	; Check if BLOCK_END_COL > src_len (BC)
	LD HL,(BLOCK_END_COL)
	AND A
	SBC HL,BC
	JR C,COPY_SGL_END_COL_OK
	; Clamp BLOCK_END_COL = src_len (BC)
	LD (BLOCK_END_COL),BC
COPY_SGL_END_COL_OK:

	; Length to copy: BC = BLOCK_END_COL - BLOCK_START_COL
	LD HL,(BLOCK_END_COL)
	LD DE,(BLOCK_START_COL)
	AND A
	SBC HL,DE
	RET Z				; If length == 0, nothing to copy!
	LD (COPY_BLK_LEN),HL
	LD B,H
	LD C,L				; BC = length to copy

	; Copy into COPY_BLK_BUF: source = SPLIT_LINE_TEMP + BLOCK_START_COL
	LD HL,SPLIT_LINE_TEMP
	ADD HL,DE			; HL = SPLIT_LINE_TEMP + BLOCK_START_COL
	LD DE,COPY_BLK_BUF
	LDIR
	XOR A
	LD (DE),A			; Null-terminate COPY_BLK_BUF

	; Read destination line CUR_DOC_ROW into SPLIT_LINE_TEMP
	LD BC,(CUR_DOC_ROW)
	LD DE,SPLIT_LINE_TEMP
	LD HL,MAX_ACTIVE_LINE_STRIDE-2		; 1022
	CALL READ_FAR_LINE_MAX

	; Measure destination line length
	LD HL,SPLIT_LINE_TEMP
	LD BC,0
COPY_SGL_DEST_LEN:
	LD A,(HL)
	OR A
	JR Z,COPY_SGL_DEST_LEN_DONE
	INC HL
	INC BC
	JR COPY_SGL_DEST_LEN
COPY_SGL_DEST_LEN_DONE:
	LD (DEST_LINE_LEN),BC

	; Clamp CUR_COL <= DEST_LINE_LEN
	LD HL,(CUR_COL)
	LD DE,(DEST_LINE_LEN)
	AND A
	SBC HL,DE
	JR C,COPY_SGL_COL_OK
	JR Z,COPY_SGL_COL_OK
	LD (CUR_COL),DE
COPY_SGL_COL_OK:

	; Check line capacity: max MAX_INPUT_LINE_CHARS (1000)
	; Available Space = MAX_INPUT_LINE_CHARS - DEST_LINE_LEN
	LD HL,MAX_INPUT_LINE_CHARS
	LD DE,(DEST_LINE_LEN)
	AND A
	SBC HL,DE			; HL = available space
	RET C	; If DEST_LINE_LEN >= MAX_INPUT_LINE_CHARS, can't add anything
	RET Z

	; If COPY_BLK_LEN > Space, clamp COPY_BLK_LEN = Space
	LD DE,(COPY_BLK_LEN)
	PUSH HL				; Save available space
	AND A
	SBC HL,DE			; available space - COPY_BLK_LEN
	POP HL				; HL = available space
	JR NC,COPY_SGL_SPACE_OK		; Available space >= COPY_BLK_LEN
	LD (COPY_BLK_LEN),HL		; Clamp COPY_BLK_LEN = available space
COPY_SGL_SPACE_OK:
	LD HL,(COPY_BLK_LEN)
	LD A,H
	OR L
	RET Z

	; Shift suffix in SPLIT_LINE_TEMP right by COPY_BLK_LEN bytes
	; Number of bytes to shift: (DEST_LINE_LEN - CUR_COL + 1)
	LD HL,(DEST_LINE_LEN)
	LD DE,(CUR_COL)
	AND A
	SBC HL,DE
	INC HL
	LD B,H
	LD C,L				; BC = bytes to shift

	; HL = SPLIT_LINE_TEMP + DEST_LINE_LEN (source last byte)
	LD HL,SPLIT_LINE_TEMP
	LD DE,(DEST_LINE_LEN)
	ADD HL,DE			; HL = source last byte

	; DE = destination last byte = HL + COPY_BLK_LEN
	LD DE,(COPY_BLK_LEN)
	PUSH HL
	ADD HL,DE
	EX DE,HL			; DE = destination last byte
	POP HL				; HL = source last byte
	LDDR				; Shift suffix right

	; Copy COPY_BLK_LEN bytes from COPY_BLK_BUF into SPLIT_LINE_TEMP +
	; CUR_COL
	LD HL,COPY_BLK_BUF
	LD DE,SPLIT_LINE_TEMP
	LD BC,(CUR_COL)
	EX DE,HL
	ADD HL,BC
	EX DE,HL			; DE = SPLIT_LINE_TEMP + CUR_COL
	LD BC,(COPY_BLK_LEN)
	LDIR

	; Write updated line back to CUR_DOC_ROW
	LD BC,(CUR_DOC_ROW)
	LD HL,SPLIT_LINE_TEMP
	CALL WRITE_FAR_LINE

	; If CUR_DOC_ROW == BLOCK_START_ROW and CUR_COL <= BLOCK_START_COL:
	; The block on this line shifted right by COPY_BLK_LEN!
	LD HL,(CUR_DOC_ROW)
	LD DE,(BLOCK_START_ROW)
	LD A,H
	CP D
	JR NZ,COPY_SGL_ADVANCE
	LD A,L
	CP E
	JR NZ,COPY_SGL_ADVANCE

	LD HL,(CUR_COL)
	LD DE,(BLOCK_START_COL)
	AND A
	SBC HL,DE
	JR Z,COPY_SGL_SHIFT_BOUNDS
	JR NC,COPY_SGL_ADVANCE		; CUR_COL > BLOCK_START_COL

COPY_SGL_SHIFT_BOUNDS:
	LD DE,(COPY_BLK_LEN)
	LD HL,(BLOCK_START_COL)
	ADD HL,DE
	LD (BLOCK_START_COL),HL
	LD HL,(BLOCK_END_COL)
	ADD HL,DE
	LD (BLOCK_END_COL),HL

COPY_SGL_ADVANCE:
	; Advance cursor: CUR_COL += COPY_BLK_LEN
	LD HL,(CUR_COL)
	LD DE,(COPY_BLK_LEN)
	ADD HL,DE
	LD (CUR_COL),HL
	CALL CALC_VISUAL_COL
	LD (TARGET_COL),HL

	CALL INVALIDATE_ACTIVE_LINE
	CALL RELOAD_CACHE_WINDOW_FORCE
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	LD (DOC_MODIFIED),A
	RET

	;---------------------------------------------------------------------
	; CASE 2: Multi-Line Block Copy
	;---------------------------------------------------------------------
DO_COPY_BLK_MULTILINE:
	LD HL,(BLOCK_END_ROW)
	LD DE,(BLOCK_START_ROW)
	AND A
	SBC HL,DE
	LD (COPY_K_LINES),HL		; K = new lines count

	; Check capacity: DOC_TOTAL_LINES + K <= MAX_DOC_LINES
	LD HL,(DOC_TOTAL_LINES)
	LD DE,(COPY_K_LINES)
	ADD HL,DE
	LD DE,(MAX_DOC_LINES_LIMIT)
	OR A
	SBC HL,DE
	JR C,COPY_ML_CAP_OK
	JR Z,COPY_ML_CAP_OK

COPY_ML_CAP_FAIL:
	CALL SET_OOM_STATUS
	SCF
	RET

COPY_ML_CAP_OK:

	; Pre-extract BLOCK_END_ROW prefix [0 .. BLOCK_END_COL] into
	; COPY_TAIL_BUF
	; (Doing this early prevents corruption if CUR_DOC_ROW == BLOCK_END_ROW)
	; If BLOCK_END_COL == 0, tail prefix is empty
	LD A,(BLOCK_END_COL)
	OR A
	JR Z,COPY_ML_TAIL_EMPTY

	LD BC,(BLOCK_END_ROW)
	LD DE,COPY_TAIL_BUF
	CALL READ_FAR_LINE

	; Truncate COPY_TAIL_BUF at BLOCK_END_COL
	LD HL,COPY_TAIL_BUF
	LD C,0				; C = char count
	LD A,(BLOCK_END_COL)
	LD B,A				; B = chars count (BLOCK_END_COL)
COPY_ML_TAIL_COUNT:
	LD A,(HL)
	OR A
	JR Z,COPY_ML_TAIL_COUNT_DONE
	INC HL
	INC C
	DJNZ COPY_ML_TAIL_COUNT
COPY_ML_TAIL_COUNT_DONE:
	LD (HL),0			; Null-terminate COPY_TAIL_BUF
	LD A,C
	LD (COPY_TAIL_LEN),A		; Length of tail prefix
	JR COPY_ML_TAIL_DONE

COPY_ML_TAIL_EMPTY:
	XOR A
	LD (COPY_TAIL_BUF),A
	LD (COPY_TAIL_LEN),A

COPY_ML_TAIL_DONE:

	; Allocate K slots in COPY_SLOTS_BUF
	LD BC,(COPY_K_LINES)
	LD IX,COPY_SLOTS_BUF
COPY_ML_ALLOC_LOOP:
	PUSH BC
	CALL ALLOC_SLOT
	JR C,COPY_ML_ALLOC_FAIL
	LD (IX+0),L
	LD (IX+1),H
	INC IX
	INC IX
	POP BC
	DEC BC
	LD A,B
	OR C
	JR NZ,COPY_ML_ALLOC_LOOP
	JR COPY_ML_ALLOC_DONE

COPY_ML_ALLOC_FAIL:
	CALL SET_OOM_STATUS
	POP BC
	LD HL,(COPY_K_LINES)
	AND A
	SBC HL,BC			; HL = allocated count
	LD B,H
	LD C,L
	LD A,B
	OR C
	JR Z,COPY_ML_ALLOC_FAIL_RET
	LD IX,COPY_SLOTS_BUF
COPY_ML_ROLLBACK:
	LD L,(IX+0)
	LD H,(IX+1)
	PUSH BC
	CALL FREE_SLOT
	POP BC
	INC IX
	INC IX
	DEC BC
	LD A,B
	OR C
	JR NZ,COPY_ML_ROLLBACK
COPY_ML_ALLOC_FAIL_RET:
	SCF
	RET

COPY_ML_ALLOC_DONE:
	; Step 1: Destination line at CUR_DOC_ROW
	; Read CUR_DOC_ROW into LOAD_LINE_TEMP
	LD BC,(CUR_DOC_ROW)
	LD DE,LOAD_LINE_TEMP
	CALL READ_FAR_LINE

	; Split LOAD_LINE_TEMP at CUR_COL:
	; Prefix stays in LOAD_LINE_TEMP[0 .. CUR_COL - 1]
	; Suffix copied into SPLIT_LINE_TEMP
	LD HL,SPLIT_LINE_TEMP
	LD DE,SPLIT_LINE_TEMP+1
	LD BC,127
	LD (HL),0
	LDIR

	LD HL,LOAD_LINE_TEMP
	LD A,(CUR_COL)
	LD E,A
	LD D,0
	ADD HL,DE			; HL = split point in LOAD_LINE_TEMP

	LD DE,SPLIT_LINE_TEMP
COPY_ML_SAVE_SUFFIX:
	LD A,(HL)
	OR A
	JR Z,COPY_ML_SUFFIX_SAVED
	LD (DE),A
	LD (HL),0			; Truncate LOAD_LINE_TEMP at CUR_COL
	INC HL
	INC DE
	JR COPY_ML_SAVE_SUFFIX
COPY_ML_SUFFIX_SAVED:

	; Read BLOCK_START_ROW into COPY_BLK_BUF
	LD BC,(BLOCK_START_ROW)
	LD DE,COPY_BLK_BUF
	CALL READ_FAR_LINE

	; Append COPY_BLK_BUF[BLOCK_START_COL .. EOL] to LOAD_LINE_TEMP at
	; CUR_COL
	LD HL,COPY_BLK_BUF
	LD A,(BLOCK_START_COL)
	LD E,A
	LD D,0
	ADD HL,DE			; HL = source in COPY_BLK_BUF

	LD DE,LOAD_LINE_TEMP
	LD A,(CUR_COL)
	LD C,A				; C = current length
	PUSH HL
	LD HL,LOAD_LINE_TEMP
	LD E,A
	LD D,0
	ADD HL,DE
	EX DE,HL			; DE = destination in LOAD_LINE_TEMP
	POP HL

COPY_ML_APPEND_HEAD:
	LD A,(HL)
	OR A
	JR Z,COPY_ML_HEAD_DONE
	LD A,C
	CP MAX_CACHE_LINE_CHARS		; max 250 chars
	JR NC,COPY_ML_HEAD_DONE
	LD A,(HL)
	LD (DE),A
	INC HL
	INC DE
	INC C
	JR COPY_ML_APPEND_HEAD
COPY_ML_HEAD_DONE:
	XOR A
	LD (DE),A

	; Write updated head line back to CUR_DOC_ROW
	LD BC,(CUR_DOC_ROW)
	LD HL,LOAD_LINE_TEMP
	CALL WRITE_FAR_LINE

	; Step 2: Intermediate lines (if K > 1)
	LD IX,COPY_SLOTS_BUF		; Pointer in COPY_SLOTS_BUF
	LD HL,(COPY_K_LINES)
	DEC HL				; HL = K - 1
	LD A,H
	OR L
	JR Z,COPY_ML_PROCESS_LAST	; If K == 1, jump directly to last line

	LD (COPY_SRC_ROW),HL		; Loop counter = K - 1
	LD HL,(BLOCK_START_ROW)
	INC HL
	; Current source row = BLOCK_START_ROW + 1
	LD (DEL_BLK_CUR_LINE),HL

COPY_ML_MID_LOOP:
	LD BC,(DEL_BLK_CUR_LINE)
	LD DE,LOAD_LINE_TEMP
	CALL READ_FAR_LINE

	LD C,(IX+0)
	LD B,(IX+1)			; BC = slot ID
	LD HL,LOAD_LINE_TEMP
	CALL WRITE_FAR_SLOT_LINE

	INC IX
	INC IX
	LD HL,(DEL_BLK_CUR_LINE)
	INC HL
	LD (DEL_BLK_CUR_LINE),HL

	LD HL,(COPY_SRC_ROW)
	DEC HL
	LD (COPY_SRC_ROW),HL
	LD A,H
	OR L
	JR NZ,COPY_ML_MID_LOOP

COPY_ML_PROCESS_LAST:
	; IX points to the slot for the last line
	; Build last line: COPY_TAIL_BUF + SPLIT_LINE_TEMP into LOAD_LINE_TEMP
	LD HL,COPY_TAIL_BUF
	LD DE,LOAD_LINE_TEMP
	LD A,(COPY_TAIL_LEN)
	LD C,A				; C = char count
	OR A
	JR Z,COPY_ML_LAST_COPY_SUFFIX
	LD B,0
	LDIR

COPY_ML_LAST_COPY_SUFFIX:
	; Append Suffix from SPLIT_LINE_TEMP
	LD HL,SPLIT_LINE_TEMP
COPY_ML_APPEND_SUFFIX:
	LD A,(HL)
	OR A
	JR Z,COPY_ML_SUFFIX_DONE
	LD A,C
	CP MAX_CACHE_LINE_CHARS		; max 250 chars
	JR NC,COPY_ML_SUFFIX_DONE
	LD A,(HL)
	LD (DE),A
	INC HL
	INC DE
	INC C
	JR COPY_ML_APPEND_SUFFIX
COPY_ML_SUFFIX_DONE:
	XOR A
	LD (DE),A

	; Write last line to slot (IX+0, IX+1)
	LD C,(IX+0)
	LD B,(IX+1)
	LD HL,LOAD_LINE_TEMP
	CALL WRITE_FAR_SLOT_LINE

	; Step 3: Shift line slots downward from CUR_DOC_ROW + 1 by K words
	LD HL,(DOC_TOTAL_LINES)
	LD DE,(CUR_DOC_ROW)
	INC DE				; DE = CUR_DOC_ROW + 1
	AND A
	SBC HL,DE			; HL = W
	JR Z,COPY_ML_PLUG_SLOTS
	JR C,COPY_ML_PLUG_SLOTS

	; Shift W words down by K words
	LD B,H
	LD C,L				; BC = W
	LD HL,(CUR_DOC_ROW)
	INC HL				; HL = source line = CUR_DOC_ROW + 1
	LD DE,(COPY_K_LINES)
	ADD HL,DE
	EX DE,HL			; DE = dest line = CUR_DOC_ROW + 1 + K
	LD HL,(CUR_DOC_ROW)
	INC HL				; HL = source line = CUR_DOC_ROW + 1
	CALL SHIFT_LINE_SLOTS_DOWN

COPY_ML_PLUG_SLOTS:
	; Plug K new slot IDs into LINE_TABLE_BANK + (CUR_DOC_ROW + 1) * 2
	LD HL,(CUR_DOC_ROW)
	INC HL
	LD B,H
	LD C,L				; BC = CUR_DOC_ROW + 1
	LD HL,COPY_SLOTS_BUF		; Source: COPY_SLOTS_BUF
	LD DE,(COPY_K_LINES)		; DE = K words
	CALL WRITE_LINE_SLOTS_FROM_RAM

	; Step 4: Update DOC_TOTAL_LINES += K
	LD HL,(DOC_TOTAL_LINES)
	LD DE,(COPY_K_LINES)
	ADD HL,DE
	LD (DOC_TOTAL_LINES),HL

	; Step 5: If CUR_DOC_ROW < BLOCK_START_ROW, shift block rows down by K
	LD HL,(CUR_DOC_ROW)
	LD DE,(BLOCK_START_ROW)
	LD A,H
	CP D
	JR C,COPY_ML_SHIFT_BLOCK
	JR NZ,COPY_ML_DONE_BLOCK_SHIFT
	LD A,L
	CP E
	JR NC,COPY_ML_DONE_BLOCK_SHIFT

COPY_ML_SHIFT_BLOCK:
	LD HL,(BLOCK_START_ROW)
	LD DE,(COPY_K_LINES)
	ADD HL,DE
	LD (BLOCK_START_ROW),HL

	LD HL,(BLOCK_END_ROW)
	ADD HL,DE
	LD (BLOCK_END_ROW),HL

COPY_ML_DONE_BLOCK_SHIFT:
	; Step 6: Advance cursor to CUR_DOC_ROW + K, Col = COPY_TAIL_LEN
	LD HL,(CUR_DOC_ROW)
	LD DE,(COPY_K_LINES)
	ADD HL,DE
	LD (CUR_DOC_ROW),HL

	LD A,(COPY_TAIL_LEN)
	LD L,A
	LD H,0
	LD (CUR_COL),HL
	CALL CALC_VISUAL_COL
	LD (TARGET_COL),HL

	; Adjust TOP_DOC_ROW if scrolled past screen
	LD HL,(CUR_DOC_ROW)
	LD DE,(TOP_DOC_ROW)
	AND A
	SBC HL,DE
	LD A,(ACTIVE_ROWS)
	DEC A
	DEC A
	CP L
	JR NC,COPY_ML_FINISH
	; Scroll viewport so CUR_DOC_ROW is on screen
	LD HL,(CUR_DOC_ROW)
	LD E,A
	LD D,0
	AND A
	SBC HL,DE
	LD (TOP_DOC_ROW),HL

COPY_ML_FINISH:
	CALL INVALIDATE_ACTIVE_LINE
	CALL RELOAD_CACHE_WINDOW_FORCE
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	LD (DOC_MODIFIED),A
	AND A
	RET

;------------------------------------------------------------------------------
; DO_MOVE_BLOCK: Move solidified block selection to current cursor position
;
; Purpose:
;   Relocates selected text to current cursor position (CUR_DOC_ROW, CUR_COL).
;   Copies block to destination, deletes original block, computes shifted
;   coordinates, and updates block selection around newly moved text.
;
; Call Usage / Protocol:
;   Called via CALL on Ctrl+X when block is solidified (state 2).
;
; Inputs:
;   BLOCK_ACTIVE = 2, CUR_DOC_ROW, CUR_COL.
;
; Outputs:
;   Block text relocated; block bounds updated around destination;
;   DOC_MODIFIED = 1.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_MOVE_BLOCK:
	LD A,(BLOCK_ACTIVE)
	CP 2				; Only solidified blocks can be moved
	RET NZ

	CALL NORMALIZE_BLOCK_BOUNDS

	; Check if cursor is inside the block; if so, cannot move block into
	; itself!
	CALL CHECK_CURSOR_IN_BLOCK
	RET C

	CALL INVALIDATE_ACTIVE_LINE
	CALL FLUSH_DIRTY_CACHE

	; Save destination coordinates
	LD HL,(CUR_DOC_ROW)
	LD (MOVE_DEST_ROW),HL
	LD HL,(CUR_COL)
	LD (MOVE_DEST_COL),HL

	; Save original block coordinates & dimensions
	LD HL,(BLOCK_START_ROW)
	LD (MOVE_SRC_START_ROW),HL
	LD HL,(BLOCK_START_COL)
	LD (MOVE_SRC_START_COL),HL

	LD HL,(BLOCK_END_ROW)
	LD (MOVE_SRC_END_ROW),HL
	LD HL,(BLOCK_END_COL)
	LD (MOVE_SRC_END_COL),HL

	; Determine if DEST is BEFORE or AFTER SRC:
	; DEST < SRC_START: MOVE_DEST_IS_BEFORE = 1
	; DEST >= SRC_START: MOVE_DEST_IS_BEFORE = 0
	XOR A
	LD (MOVE_DEST_IS_BEFORE),A

	LD HL,(MOVE_DEST_ROW)
	LD DE,(MOVE_SRC_START_ROW)
	LD A,H
	CP D
	JR C,MOVE_MARK_BEFORE
	JR NZ,MOVE_EXEC_COPY
	LD A,L
	CP E
	JR C,MOVE_MARK_BEFORE
	JR NZ,MOVE_EXEC_COPY

	; Same row: compare columns
	LD A,(MOVE_DEST_COL)
	LD HL,MOVE_SRC_START_COL
	CP (HL)
	JR NC,MOVE_EXEC_COPY

MOVE_MARK_BEFORE:
	LD A,1
	LD (MOVE_DEST_IS_BEFORE),A

MOVE_EXEC_COPY:
	; Step 1: Copy block to destination
	CALL DO_COPY_BLOCK
	LD A,(STATUS_OOM_FLAG)
	OR A
	RET NZ				; Abort move if copy failed due to OOM!

	; Step 2: Delete original block
	CALL DO_DELETE_BLOCK

	; Step 3: Compute new coordinates of the moved block and cursor:
	LD A,(MOVE_DEST_IS_BEFORE)
	OR A
	JR NZ,MOVE_CALC_BEFORE

	; DEST was AFTER original block:
	; Check if single-line:
	LD HL,(MOVE_SRC_START_ROW)
	LD DE,(MOVE_SRC_END_ROW)
	LD A,H
	CP D
	JR NZ,MOVE_AFTER_MULTI
	LD A,L
	CP E
	JR NZ,MOVE_AFTER_MULTI

	; Single-line block:
	; Was DEST on the same row as SRC?
	LD HL,(MOVE_DEST_ROW)
	LD DE,(MOVE_SRC_START_ROW)
	LD A,H
	CP D
	JR NZ,MOVE_AFTER_DIFF_ROW
	LD A,L
	CP E
	JR NZ,MOVE_AFTER_DIFF_ROW

	; Same row after: DEST_COL shifted left by L = SRC_END_COL -
	; SRC_START_COL
	LD A,(MOVE_SRC_END_COL)
	LD HL,MOVE_SRC_START_COL
	SUB (HL)			; A = L
	LD B,A
	LD A,(MOVE_DEST_COL)
	SUB B				; A = DEST_COL - L
	LD (CUR_COL),A
	LD HL,(MOVE_DEST_ROW)
	LD (CUR_DOC_ROW),HL
	JR MOVE_SET_BLOCK

MOVE_AFTER_DIFF_ROW:
	; Single-line block, but DEST is on a different row (after
	; SRC_START_ROW):
	; Row did not shift, col did not shift!
	LD HL,(MOVE_DEST_ROW)
	LD (CUR_DOC_ROW),HL
	LD A,(MOVE_DEST_COL)
	LD (CUR_COL),A
	JR MOVE_SET_BLOCK

MOVE_AFTER_MULTI:
	; Multi-line block:
	; K = MOVE_SRC_END_ROW - MOVE_SRC_START_ROW lines were deleted before
	; DEST!
	; New DEST_ROW = MOVE_DEST_ROW - K
	LD HL,(MOVE_SRC_END_ROW)
	LD DE,(MOVE_SRC_START_ROW)
	AND A
	SBC HL,DE			; HL = K
	EX DE,HL			; DE = K
	LD HL,(MOVE_DEST_ROW)
	AND A
	SBC HL,DE			; HL = DEST_ROW - K
	LD (CUR_DOC_ROW),HL
	LD A,(MOVE_DEST_COL)
	LD (CUR_COL),A
	JR MOVE_SET_BLOCK

MOVE_CALC_BEFORE:
	; DEST was BEFORE original block: coordinates did not shift!
	LD HL,(MOVE_DEST_ROW)
	LD (CUR_DOC_ROW),HL
	LD A,(MOVE_DEST_COL)
	LD (CUR_COL),A

MOVE_SET_BLOCK:
	; Set new block coordinates around the moved block!
	LD HL,(CUR_DOC_ROW)
	LD (BLOCK_START_ROW),HL
	LD A,(CUR_COL)
	LD (BLOCK_START_COL),A

	; Check if single-line or multi-line block:
	LD HL,(MOVE_SRC_START_ROW)
	LD DE,(MOVE_SRC_END_ROW)
	LD A,H
	CP D
	JR NZ,MOVE_SET_BLK_MULTI
	LD A,L
	CP E
	JR NZ,MOVE_SET_BLK_MULTI

	; Single-line end coordinates:
	LD HL,(CUR_DOC_ROW)
	LD (BLOCK_END_ROW),HL
	LD A,(MOVE_SRC_END_COL)
	LD HL,MOVE_SRC_START_COL
	SUB (HL)			; A = L
	LD HL,CUR_COL
	ADD A,(HL)			; A = CUR_COL + L
	LD (BLOCK_END_COL),A
	JR MOVE_ADJUST_VIEW

MOVE_SET_BLK_MULTI:
	; Multi-line end coordinates:
	LD HL,(MOVE_SRC_END_ROW)
	LD DE,(MOVE_SRC_START_ROW)
	AND A
	SBC HL,DE			; HL = K
	LD DE,(CUR_DOC_ROW)
	ADD HL,DE			; HL = CUR_DOC_ROW + K
	LD (BLOCK_END_ROW),HL
	LD A,(MOVE_SRC_END_COL)
	LD (BLOCK_END_COL),A

MOVE_ADJUST_VIEW:
	; Ensure cursor position is visible on screen
	LD HL,(CUR_DOC_ROW)
	LD DE,(TOP_DOC_ROW)
	LD A,H
	CP D
	JR C,MOVE_ADJ_TOP
	JR NZ,MOVE_CHECK_BOTTOM
	LD A,L
	CP E
	JR NC,MOVE_CHECK_BOTTOM
MOVE_ADJ_TOP:
	LD (TOP_DOC_ROW),HL
	JR MOVE_FINISH

MOVE_CHECK_BOTTOM:
	LD HL,(CUR_DOC_ROW)
	LD DE,(TOP_DOC_ROW)
	AND A
	SBC HL,DE
	LD A,(ACTIVE_ROWS)
	DEC A
	DEC A
	CP L
	JR NC,MOVE_FINISH
	; Scroll down so CUR_DOC_ROW is on screen
	LD HL,(CUR_DOC_ROW)
	LD E,A
	LD D,0
	AND A
	SBC HL,DE
	LD (TOP_DOC_ROW),HL

MOVE_FINISH:
	LD A,2
	LD (BLOCK_ACTIVE),A		; Solidify block at new location!
	CALL CALC_VISUAL_COL
	LD (TARGET_COL),HL
	CALL INVALIDATE_ACTIVE_LINE
	CALL RELOAD_CACHE_WINDOW_FORCE
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	RET

