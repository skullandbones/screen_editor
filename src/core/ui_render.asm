;==============================================================================
; UI_RENDER.ASM: Core Subsystem - Screen Repaint Engine & Status Bar
;
; Purpose:
;   Implements screen repainting, tab expansion, viewport horizontal panning,
;   status bar rendering, and hardware cursor positioning.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; Editor Screen Renderer
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; RENDER_SCREEN: Full editor screen and status bar redraw
;
; Purpose:
;   Adjusts horizontal viewport, clears splash flag, disables inverse video,
;   homes cursor, iterates through all visible rows (0..ACTIVE_ROWS-2) drawing
;   cached document lines or empty line tildes, updates status bar, and
;   relocates hardware cursor.
;
; Call Usage / Protocol:
;   Called via CALL when initiating editor or after full-screen operations.
;
; Inputs:
;   TOP_DOC_ROW, DOC_TOTAL_LINES, ACTIVE_ROWS, ACTIVE_COLS.
;
; Outputs:
;   Full workspace rendered; NEED_SCREEN_RENDER set to 0.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
RENDER_SCREEN:
	CALL ADJUST_HORIZ_VIEWPORT
	XOR A
	LD (IS_SPLASH_SCREEN),A
	CALL TERM_INVERSE_OFF
	CALL TERM_HOME

	LD C,0				; Screen row index (0 .. ACTIVE_ROWS-2)
RENDER_ROW_LOOP:
	PUSH BC
	; Calculate buffer line to render: doc_line = TOP_DOC_ROW + C
	LD HL,(TOP_DOC_ROW)
	LD E,C
	LD D,0
	ADD HL,DE			; HL = target doc_line
	LD B,H
	LD C,L				; BC = target doc_line

	; Check if doc_line < DOC_TOTAL_LINES
	LD HL,(DOC_TOTAL_LINES)
	LD A,H
	CP B
	JR C,RENDER_TILDE_ROW
	JR NZ,DO_RENDER_DOC_ROW
	LD A,L
	CP C
	JR Z,RENDER_TILDE_ROW
	JR C,RENDER_TILDE_ROW

DO_RENDER_DOC_ROW:
	CALL RENDER_BUFFER_LINE
	JR RENDER_ROW_NEXT

RENDER_TILDE_ROW:
	CALL TERM_CLEAR_EOL
	LD A,'~'
	CALL PUTC
	LD A,13
	CALL PUTC
	LD A,10
	CALL PUTC

RENDER_ROW_NEXT:
	POP BC
	INC C
	LD A,(ACTIVE_ROWS)
	DEC A				; Text rows = ACTIVE_ROWS - 1
	CP C
	JR NZ,RENDER_ROW_LOOP

	CALL RENDER_STATUS_BAR
	CALL LOCATE_CURSOR
	RET

;------------------------------------------------------------------------------
; Check if current character at visual column B is at right screen edge (col 79)
; on an 80-column display, and the line continues beyond it.
; Inputs:
;   B = visual column (0..119)
;   HL = pointer to current character in LINE_STORAGE
; Outputs:
;   Carry flag = 1 if character should be highlighted in inverse video
;   Carry flag = 0 otherwise
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
CHECK_CHAR_CONT_HL:
CHECK_CHAR_CONT_16:
	LD A,(BLOCK_ACTIVE)
	OR A
	JR NZ,CC16_NO
	LD A,(LINE_BLK_ACTIVE)
	OR A
	JR NZ,CC16_NO

	; 1. Left edge continuation: if VIEW_LEFT_COL > 0 and DE ==
	; VIEW_LEFT_COL
	LD A,(VIEW_LEFT_COL+1)
	OR A
	JR NZ,CC16_LEFT_NONZERO
	LD A,(VIEW_LEFT_COL)
	OR A
	JR Z,CC16_CHECK_RIGHT
CC16_LEFT_NONZERO:
	LD A,(VIEW_LEFT_COL+1)
	CP D
	JR NZ,CC16_CHECK_RIGHT
	LD A,(VIEW_LEFT_COL)
	CP E
	JR Z,CC16_YES

CC16_CHECK_RIGHT:
	; 2. Right edge continuation: if DE + 1 == VIEW_RIGHT_COL and line
	; continues
	INC DE
	LD A,(VIEW_RIGHT_COL+1)
	CP D
	JR NZ,CC16_NO_DEC
	LD A,(VIEW_RIGHT_COL)
	CP E
CC16_NO_DEC:
	DEC DE
	JR NZ,CC16_NO

	; Visual col DE is VIEW_RIGHT_COL - 1. Check if line continues past
	; (HL):
	INC HL
	LD A,(HL)
	DEC HL
	OR A
	JR Z,CC16_NO			; Next char is null -> line ends here
CC16_YES:
	SCF
	RET
CC16_NO:
	OR A
	RET

;------------------------------------------------------------------------------
; Check if current TAB space at visual column DE is at edge of display
; Inputs:
;   DE = visual column (0..1000)
;   (REND_TAB_SPACES) = remaining spaces in tab (1..8)
;   HL = pointer to next character in buffer (already incremented past TAB)
; Outputs:
;   Carry flag = 1 if space should be highlighted in inverse video
;   Carry flag = 0 otherwise
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
CHECK_TAB_CONT_HL:
CHECK_TAB_CONT_16:
	LD A,(BLOCK_ACTIVE)
	OR A
	JR NZ,CT16_NO
	LD A,(LINE_BLK_ACTIVE)
	OR A
	JR NZ,CT16_NO

	; 1. Left edge continuation:
	LD A,(VIEW_LEFT_COL+1)
	OR A
	JR NZ,CT16_LEFT_NONZERO
	LD A,(VIEW_LEFT_COL)
	OR A
	JR Z,CT16_CHECK_RIGHT
CT16_LEFT_NONZERO:
	LD A,(VIEW_LEFT_COL+1)
	CP D
	JR NZ,CT16_CHECK_RIGHT
	LD A,(VIEW_LEFT_COL)
	CP E
	JR Z,CT16_YES

CT16_CHECK_RIGHT:
	; 2. Right edge continuation:
	INC DE
	LD A,(VIEW_RIGHT_COL+1)
	CP D
	JR NZ,CT16_NO_DEC
	LD A,(VIEW_RIGHT_COL)
	CP E
CT16_NO_DEC:
	DEC DE
	JR NZ,CT16_NO

	; DE is VIEW_RIGHT_COL - 1.
	; If REND_TAB_SPACES > 1, tab itself continues into next column:
	LD A,(REND_TAB_SPACES)
	CP 1
	JR NZ,CT16_YES

	; Last space of tab. Does line continue after tab?
	LD A,(HL)
	OR A
	JR Z,CT16_NO

CT16_YES:
	SCF
	RET
CT16_NO:
	OR A
	RET

;------------------------------------------------------------------------------
; GET_TAB_SPACES: Compute spaces needed to advance to next tab stop
;
; Purpose:
;   Calculates number of space characters (1..CFG_TAB_WIDTH) required to
;   advance from visual column in register A to the next tab stop.
;
; Call Usage / Protocol:
;   Called via CALL during line rendering and visual column calculation.
;
; Inputs:
;   A = Visual column index (0..255).
;
; Outputs:
;   A = Number of spaces to next tab stop (1..4 or 1..8).
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
GET_TAB_SPACES:
	PUSH BC
	CPL
	LD B,A
	LD A,(CFG_TAB_MASK)
	AND B
	INC A
	POP BC
	RET

;------------------------------------------------------------------------------
; RENDER_CURRENT_LINE: Fast single-line refresh for active document row
;
; Purpose:
;   Verifies CUR_DOC_ROW is within visible viewport, positions cursor at
;   start of screen row, clears row to EOL, renders line characters from
;   ACTIVE_LINE_BUF with visual block highlighting and tab expansion,
;   and updates status bar.
;
; Call Usage / Protocol:
;   Called via CALL after character insertion, deletion, or in-line typing.
;
; Inputs:
;   CUR_DOC_ROW, TOP_DOC_ROW, ACTIVE_LINE_BUF, ACTIVE_ROWS.
;
; Outputs:
;   Current screen row repainted; status bar refreshed.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
RENDER_CURRENT_LINE:
	; Defensive check: ensure CUR_DOC_ROW is within visible viewport bounds
	LD HL,(CUR_DOC_ROW)
	LD DE,(TOP_DOC_ROW)
	AND A
	SBC HL,DE
	RET C		; Outside viewport: do not emit out-of-bounds row
	LD A,(ACTIVE_ROWS)
	SUB 2
	LD E,A
	LD D,0
	CALL CMP_HL_DE
	RET NC		; Outside viewport: do not emit out-of-bounds row

	; Move to start of current screen line and clear to EOL
	LD A,L
	INC A				; Screen row (1-indexed for terminal)
	LD H,A
	LD L,1
	CALL LOCATE_RC
	CALL TERM_CLEAR_EOL

	LD BC,(CUR_DOC_ROW)
	CALL GET_LINE_BLOCK_RANGE
	XOR A
	LD (LINE_IN_INVERSE),A

RCL_LOAD_LINE:
	CALL CHECKOUT_ACTIVE_LINE	; HL = ACTIVE_LINE_BUF

	LD A,(HL)
	OR A
	JR NZ,RCL_START_CHARS

	; Empty line
	LD A,(LINE_BLK_ACTIVE)
	OR A
	JP Z,PRINT_CUR_LINE_DONE
	LD HL,(LINE_BLK_START)
	LD A,H
	OR L
	JP NZ,PRINT_CUR_LINE_DONE
	CALL TERM_INVERSE_ON
	LD A,' '
	CALL PUTC
	CALL TERM_INVERSE_OFF
	JP PRINT_CUR_LINE_DONE

RCL_START_CHARS:
	LD DE,0				; DE = 16-bit visual column accumulator
	LD BC,0				; BC = 16-bit character index in line

PRINT_CUR_LINE_LOOP:
	LD A,(HL)
	OR A
	JP Z,PRINT_CUR_LINE_DONE

	; Check if DE >= VIEW_RIGHT_COL (past right screen boundary -> done!)
	LD A,(VIEW_RIGHT_COL+1)
	CP D
	JP C,PRINT_CUR_LINE_DONE
	JR NZ,PCL_CHK_BLK
	LD A,(VIEW_RIGHT_COL)
	CP E
	JP C,PRINT_CUR_LINE_DONE
	JP Z,PRINT_CUR_LINE_DONE

PCL_CHK_BLK:
	; Check block highlight turn ON:
	LD A,(LINE_BLK_ACTIVE)
	OR A
	JR Z,PCL_NO_BLK_START
	LD A,(LINE_IN_INVERSE)
	OR A
	JR NZ,PCL_NO_BLK_START
	LD A,(LINE_BLK_START+1)
	CP B
	JR NZ,PCL_NO_BLK_START
	LD A,(LINE_BLK_START)
	CP C
	JR NZ,PCL_NO_BLK_START

	PUSH BC
	PUSH DE
	PUSH HL
	CALL TERM_INVERSE_ON
	POP HL
	POP DE
	POP BC
	LD A,1
	LD (LINE_IN_INVERSE),A

PCL_NO_BLK_START:
	LD A,(HL)
	CP KEY_TAB
	JR Z,PRINT_CUR_TAB

	; Normal character:
	; Check if DE < VIEW_LEFT_COL
	LD A,(VIEW_LEFT_COL+1)
	CP D
	JR C,PCL_DO_EMIT
	JR NZ,PCL_SKIP_EMIT
	LD A,(VIEW_LEFT_COL)
	CP E
	JR C,PCL_DO_EMIT
	JR Z,PCL_DO_EMIT

PCL_SKIP_EMIT:
	; DE < VIEW_LEFT_COL: skip char output
	INC HL
	INC DE
	JP PCL_AFTER_CHAR

PCL_DO_EMIT:
	CALL CHECK_CHAR_CONT_16
	JR C,PCL_EMIT_CONT
	LD A,(HL)
	CALL PUTC
	INC HL
	INC DE
	JP PCL_AFTER_CHAR

PCL_EMIT_CONT:
	PUSH BC
	PUSH DE
	PUSH HL
	CALL TERM_INVERSE_ON
	POP HL
	POP DE
	POP BC
	LD A,(HL)
	CALL PUTC
	PUSH BC
	PUSH DE
	PUSH HL
	CALL TERM_INVERSE_OFF
	POP HL
	POP DE
	POP BC
	INC HL
	INC DE
	JP PCL_AFTER_CHAR

PRINT_CUR_TAB:
	INC HL
	LD A,E
	CALL GET_TAB_SPACES
	LD (REND_TAB_SPACES),A		; spaces to emit (1..CFG_TAB_WIDTH)

PRINT_CUR_TAB_SPACES:
	; Check if DE >= VIEW_RIGHT_COL
	LD A,(VIEW_RIGHT_COL+1)
	CP D
	JP C,PRINT_CUR_LINE_DONE
	JR NZ,PCT_CHK_L
	LD A,(VIEW_RIGHT_COL)
	CP E
	JP C,PRINT_CUR_LINE_DONE
	JP Z,PRINT_CUR_LINE_DONE

PCT_CHK_L:
	; Check if DE < VIEW_LEFT_COL
	LD A,(VIEW_LEFT_COL+1)
	CP D
	JR C,PCT_EMIT_SPACE
	JR NZ,PCT_SKIP_SPACE
	LD A,(VIEW_LEFT_COL)
	CP E
	JR C,PCT_EMIT_SPACE
	JR Z,PCT_EMIT_SPACE

PCT_SKIP_SPACE:
	; DE < VIEW_LEFT_COL -> skip space
	INC DE
	LD A,(REND_TAB_SPACES)
	DEC A
	LD (REND_TAB_SPACES),A
	JP NZ,PRINT_CUR_TAB_SPACES
	JP PCL_AFTER_CHAR

PCT_EMIT_SPACE:
	CALL CHECK_TAB_CONT_16
	JR C,PCT_SPACE_CONT
	LD A,' '
	CALL PUTC
	INC DE
	LD A,(REND_TAB_SPACES)
	DEC A
	LD (REND_TAB_SPACES),A
	JP NZ,PRINT_CUR_TAB_SPACES
	JP PCL_AFTER_CHAR

PCT_SPACE_CONT:
	PUSH BC
	PUSH DE
	PUSH HL
	CALL TERM_INVERSE_ON
	POP HL
	POP DE
	POP BC
	LD A,' '
	CALL PUTC
	PUSH BC
	PUSH DE
	PUSH HL
	CALL TERM_INVERSE_OFF
	POP HL
	POP DE
	POP BC
	INC DE
	LD A,(REND_TAB_SPACES)
	DEC A
	LD (REND_TAB_SPACES),A
	JP NZ,PRINT_CUR_TAB_SPACES
	JP PCL_AFTER_CHAR

PCL_AFTER_CHAR:
	; Check if BC == LINE_BLK_END (turn off inverse after this char)
	LD A,(LINE_BLK_ACTIVE)
	OR A
	JR Z,PCL_NEXT_CHAR
	LD A,(LINE_IN_INVERSE)
	OR A
	JR Z,PCL_NEXT_CHAR

	LD A,(LINE_BLK_END+1)
	CP B
	JR NZ,PCL_NEXT_CHAR
	LD A,(LINE_BLK_END)
	CP C
	JR NZ,PCL_NEXT_CHAR

	PUSH BC
	PUSH DE
	PUSH HL
	CALL TERM_INVERSE_OFF
	POP HL
	POP DE
	POP BC
	XOR A
	LD (LINE_IN_INVERSE),A

PCL_NEXT_CHAR:
	INC BC				; Next character index
	JP PRINT_CUR_LINE_LOOP

PRINT_CUR_LINE_DONE:
	LD A,(LINE_IN_INVERSE)
	OR A
	JR Z,RCL_DONE_RESTORE
	CALL TERM_INVERSE_OFF
	XOR A
	LD (LINE_IN_INVERSE),A

RCL_DONE_RESTORE:
	CALL RENDER_STATUS_BAR
	RET

;------------------------------------------------------------------------------
; FLUSH_DEFERRED_RENDER: Flush pending deferred screen, line, or status updates
;
; Purpose:
;   Evaluates deferred render flags (NEED_SCREEN_RENDER, NEED_LINE_RENDER,
;   NEED_STATUS_RENDER). If keyboard buffer is idle, executes the minimal
;   necessary redraw action to keep screen display synchronized.
;
; Call Usage / Protocol:
;   Called via CALL at start of MAIN_LOOP and before opening modal dialogs.
;
; Inputs:
;   NEED_SCREEN_RENDER, NEED_LINE_RENDER, NEED_STATUS_RENDER flags.
;
; Outputs:
;   Executes required redraw and clears corresponding flags.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
FLUSH_DEFERRED_RENDER:
	CALL ADJUST_HORIZ_VIEWPORT
	LD A,(NEED_SCREEN_RENDER)
	OR A
	JR Z,CHECK_DEFERRED_LINE

	; Full screen redraw needed (RENDER_SCREEN also updates status & locates
	; cursor)
	XOR A
	LD (NEED_SCREEN_RENDER),A
	LD (NEED_LINE_RENDER),A
	LD (NEED_STATUS_RENDER),A
	CALL RENDER_SCREEN
	RET

CHECK_DEFERRED_LINE:
	LD A,(NEED_LINE_RENDER)
	OR A
	JR Z,CHECK_DEFERRED_STATUS

	; Check if CUR_DOC_ROW is within visible screen bounds:
	; Must have: TOP_DOC_ROW <= CUR_DOC_ROW <= TOP_DOC_ROW + (ACTIVE_ROWS -
	; 2)
	LD HL,(CUR_DOC_ROW)
	LD DE,(TOP_DOC_ROW)
	AND A
	SBC HL,DE
	JR C,CDL_FULL_REDRAW
	LD A,(ACTIVE_ROWS)
	SUB 2
	LD E,A
	LD D,0
	CALL CMP_HL_DE			; Carry=1 if HL < DE
	JR NC,CDL_FULL_REDRAW		; HL >= ACTIVE_ROWS - 1: outside screen!

	; Current line redraw needed (RENDER_CURRENT_LINE updates status &
	; locates cursor)
	XOR A
	LD (NEED_LINE_RENDER),A
	LD (NEED_STATUS_RENDER),A
	CALL RENDER_CURRENT_LINE
	RET

CDL_FULL_REDRAW:
	XOR A
	LD (NEED_LINE_RENDER),A
	LD (NEED_STATUS_RENDER),A
	CALL CONSTRAIN_CURSOR_VIEWPORT
	CALL RELOAD_CACHE_WINDOW_FORCE
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	CALL LOCATE_CURSOR
	RET

CHECK_DEFERRED_STATUS:
	LD A,(NEED_STATUS_RENDER)
	OR A
	RET Z

	; Only status bar / cursor restore needed
	XOR A
	LD (NEED_STATUS_RENDER),A
	CALL RENDER_STATUS_BAR
	RET


;------------------------------------------------------------------------------
; RENDER_BUFFER_LINE: Render individual document row with block highlighting
;
; Purpose:
;   Clears current terminal row to EOL, queries block highlight range for
;   doc line BC, checks out line from ACTIVE_LINE_BUF or working cache,
;   and emits characters with tab expansion and reverse video styling.
;
; Call Usage / Protocol:
;   Called via CALL for each row in RENDER_SCREEN loop.
;
; Inputs:
;   BC = 16-bit document row index.
;
; Outputs:
;   Document line rendered on screen followed by CRLF.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
RENDER_BUFFER_LINE:
	CALL TERM_CLEAR_EOL

	; BC has target doc_line
	CALL GET_LINE_BLOCK_RANGE
	XOR A
	LD (LINE_IN_INVERSE),A

RBL_LOAD_LINE:
	; Check if BC == (ACTIVE_LINE_ROW)
	LD HL,(ACTIVE_LINE_ROW)
	LD A,B
	CP H
	JR NZ,RBL_USE_CACHE
	LD A,C
	CP L
	JR NZ,RBL_USE_CACHE
	LD HL,ACTIVE_LINE_BUF
	JR RBL_GOT_LINE_PTR

RBL_USE_CACHE:
	; HL = pointer to line start in LINE_STORAGE
	CALL ENSURE_CACHE_WINDOW

RBL_GOT_LINE_PTR:
	; Check if line is empty (HL == 0)
	LD A,(HL)
	OR A
	JR NZ,RBL_START_CHARS

	; Line is empty
	LD A,(LINE_BLK_ACTIVE)
	OR A
	JP Z,PRINT_LINE_END
	LD HL,(LINE_BLK_START)
	LD A,H
	OR L
	JP NZ,PRINT_LINE_END
	CALL TERM_INVERSE_ON
	LD A,' '
	CALL PUTC
	CALL TERM_INVERSE_OFF
	JP PRINT_LINE_END

RBL_START_CHARS:
	LD DE,0				; DE = 16-bit visual column accumulator
	LD BC,0				; BC = 16-bit character index in line

PRINT_LINE_CHARS:
	LD A,(HL)
	OR A
	JP Z,PRINT_LINE_END

	; Check if DE >= VIEW_RIGHT_COL (past right screen boundary -> done!)
	LD A,(VIEW_RIGHT_COL+1)
	CP D
	JP C,PRINT_LINE_END
	JR NZ,PLC_CHK_BLK
	LD A,(VIEW_RIGHT_COL)
	CP E
	JP C,PRINT_LINE_END
	JP Z,PRINT_LINE_END

PLC_CHK_BLK:
	; Check block highlight turn ON:
	LD A,(LINE_BLK_ACTIVE)
	OR A
	JR Z,PLC_NO_BLK_START
	LD A,(LINE_IN_INVERSE)
	OR A
	JR NZ,PLC_NO_BLK_START
	LD A,(LINE_BLK_START+1)
	CP B
	JR NZ,PLC_NO_BLK_START
	LD A,(LINE_BLK_START)
	CP C
	JR NZ,PLC_NO_BLK_START

	PUSH BC
	PUSH DE
	PUSH HL
	CALL TERM_INVERSE_ON
	POP HL
	POP DE
	POP BC
	LD A,1
	LD (LINE_IN_INVERSE),A

PLC_NO_BLK_START:
	LD A,(HL)
	CP KEY_TAB
	JR Z,PRINT_LINE_TAB

	; Normal character:
	; Check if DE < VIEW_LEFT_COL
	LD A,(VIEW_LEFT_COL+1)
	CP D
	JR C,PLC_DO_EMIT
	JR NZ,PLC_SKIP_EMIT
	LD A,(VIEW_LEFT_COL)
	CP E
	JR C,PLC_DO_EMIT
	JR Z,PLC_DO_EMIT

PLC_SKIP_EMIT:
	; DE < VIEW_LEFT_COL: skip char output
	INC HL
	INC DE
	JP PLC_AFTER_CHAR

PLC_DO_EMIT:
	CALL CHECK_CHAR_CONT_16
	JR C,PLC_EMIT_CONT
	LD A,(HL)
	CALL PUTC
	INC HL
	INC DE
	JP PLC_AFTER_CHAR

PLC_EMIT_CONT:
	PUSH BC
	PUSH DE
	PUSH HL
	CALL TERM_INVERSE_ON
	POP HL
	POP DE
	POP BC
	LD A,(HL)
	CALL PUTC
	PUSH BC
	PUSH DE
	PUSH HL
	CALL TERM_INVERSE_OFF
	POP HL
	POP DE
	POP BC
	INC HL
	INC DE
	JP PLC_AFTER_CHAR

PRINT_LINE_TAB:
	INC HL
	LD A,E
	CALL GET_TAB_SPACES
	LD (REND_TAB_SPACES),A

PRINT_LINE_TAB_SPACES:
	; Check if DE >= VIEW_RIGHT_COL
	LD A,(VIEW_RIGHT_COL+1)
	CP D
	JP C,PRINT_LINE_END
	JR NZ,PLT_CHK_L
	LD A,(VIEW_RIGHT_COL)
	CP E
	JP C,PRINT_LINE_END
	JP Z,PRINT_LINE_END

PLT_CHK_L:
	; Check if DE < VIEW_LEFT_COL
	LD A,(VIEW_LEFT_COL+1)
	CP D
	JR C,PLT_EMIT_SPACE
	JR NZ,PLT_SKIP_SPACE
	LD A,(VIEW_LEFT_COL)
	CP E
	JR C,PLT_EMIT_SPACE
	JR Z,PLT_EMIT_SPACE

PLT_SKIP_SPACE:
	; DE < VIEW_LEFT_COL -> skip space
	INC DE
	LD A,(REND_TAB_SPACES)
	DEC A
	LD (REND_TAB_SPACES),A
	JP NZ,PRINT_LINE_TAB_SPACES
	JP PLC_AFTER_CHAR

PLT_EMIT_SPACE:
	CALL CHECK_TAB_CONT_16
	JR C,PLT_SPACE_CONT
	LD A,' '
	CALL PUTC
	INC DE
	LD A,(REND_TAB_SPACES)
	DEC A
	LD (REND_TAB_SPACES),A
	JP NZ,PRINT_LINE_TAB_SPACES
	JP PLC_AFTER_CHAR

PLT_SPACE_CONT:
	PUSH BC
	PUSH DE
	PUSH HL
	CALL TERM_INVERSE_ON
	POP HL
	POP DE
	POP BC
	LD A,' '
	CALL PUTC
	PUSH BC
	PUSH DE
	PUSH HL
	CALL TERM_INVERSE_OFF
	POP HL
	POP DE
	POP BC
	INC DE
	LD A,(REND_TAB_SPACES)
	DEC A
	LD (REND_TAB_SPACES),A
	JP NZ,PRINT_LINE_TAB_SPACES
	JP PLC_AFTER_CHAR

PLC_AFTER_CHAR:
	; Check if BC == LINE_BLK_END (turn off inverse after this char)
	LD A,(LINE_BLK_ACTIVE)
	OR A
	JR Z,PLC_NEXT_CHAR
	LD A,(LINE_IN_INVERSE)
	OR A
	JR Z,PLC_NEXT_CHAR

	LD A,(LINE_BLK_END+1)
	CP B
	JR NZ,PLC_NEXT_CHAR
	LD A,(LINE_BLK_END)
	CP C
	JR NZ,PLC_NEXT_CHAR

	PUSH BC
	PUSH DE
	PUSH HL
	CALL TERM_INVERSE_OFF
	POP HL
	POP DE
	POP BC
	XOR A
	LD (LINE_IN_INVERSE),A

PLC_NEXT_CHAR:
	INC BC				; Next character index
	JP PRINT_LINE_CHARS

PRINT_LINE_END:
	LD A,(LINE_IN_INVERSE)
	OR A
	JR Z,RBL_DONE_CRLF
	CALL TERM_INVERSE_OFF
	XOR A
	LD (LINE_IN_INVERSE),A

RBL_DONE_CRLF:
	LD A,13
	CALL PUTC
	LD A,10
	CALL PUTC
	RET

;------------------------------------------------------------------------------
; LOCATE_STATUS_ROW: Position cursor at column 1 of bottom status bar row
;
; Purpose:
;   Loads ACTIVE_ROWS into row coordinate and 1 into column coordinate,
;   then jumps to LOCATE_RC to position hardware cursor at status row.
;
; Call Usage / Protocol:
;   Called via CALL prior to rendering status bar.
;
; Inputs:
;   ACTIVE_ROWS.
;
; Outputs:
;   Hardware cursor positioned at row ACTIVE_ROWS, col 1.
;
; Preserves / Modifies:
;   Preserves BC, DE; clobbers AF, HL.
;------------------------------------------------------------------------------
LOCATE_STATUS_ROW:
	LD A,(ACTIVE_ROWS)
	LD H,A
	LD L,1
	JP LOCATE_RC
; STATUS_ENCLOSED_WIDTH and POS_FIELD_WIDTH are defined in include/ui.inc

;------------------------------------------------------------------------------
; RENDER_STATUS_BAR: Render complete reverse-video status bar on bottom row
;
; Purpose:
;   Enables reverse video, emits symmetrical left margin padding, filename,
;   screen geometry (80x24 / 120x40), file format (CP/M / Linux), edit mode
;   or block selection metrics or pan offset or free memory, line and column
;   indices, right margin padding, disables reverse video, and restores cursor.
;
; Call Usage / Protocol:
;   Called via CALL across editing operations, modals, and screen redraws.
;
; Inputs:
;   Editor session and configuration variables.
;
; Outputs:
;   Bottom status bar emitted to terminal; cursor restored.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
RENDER_STATUS_BAR:
	CALL LOCATE_STATUS_ROW

	CALL TERM_INVERSE_ON

	; Symmetrical Left Margin: (ACTIVE_COLS - STATUS_ENCLOSED_WIDTH) / 2
	LD A,(ACTIVE_COLS)
	SUB STATUS_ENCLOSED_WIDTH
	SRL A				; A = 1 (80x24) or 21 (120x40)
	LD B,A
	OR A
	JR Z,STATUS_LEFT_PAD_DONE
STATUS_LEFT_PAD_LOOP:
	LD A,' '
	CALL PUTC
	DJNZ STATUS_LEFT_PAD_LOOP
STATUS_LEFT_PAD_DONE:

	; Extreme Left Enclosure: "| " (2 chars)
	LD A,'|'
	CALL PUTC
	LD A,' '
	CALL PUTC

	; Field 1: Print filename (17 chars: 14 chars name + " | ")
	CALL PRINT_STATUS_FILENAME

	; Field 2: Print active geometry (9 chars: " 80x24 | " or "120x40 | ")
	LD A,(SCREEN_MODE)
	CP MODE_120X40
	JR NZ,SHOW_STATUS_80X24
	LD DE,STR_STATUS_120X40
	CALL PRINT_STR
	JR SHOW_STATUS_FORMAT

SHOW_STATUS_80X24:
	LD DE,STR_STATUS_80X24
	CALL PRINT_STR

SHOW_STATUS_FORMAT:
	; Field 3: Print format (8 chars: "CP/M  | " or "Linux | ")
	LD A,(IS_LOADING_FILE)
	OR A
	JR Z,SHOW_STATUS_FMT_KNOWN
	LD DE,STR_FMT_BLANK
	CALL PRINT_STR
	JR SHOW_STATUS_REST

SHOW_STATUS_FMT_KNOWN:
	LD A,(SAVE_FORMAT)
	CP FMT_CPM
	JR NZ,SHOW_LINUX_FMT
	LD DE,STR_FMT_CPM
	CALL PRINT_STR
	JR SHOW_STATUS_REST

SHOW_LINUX_FMT:
	LD DE,STR_FMT_LINUX
	CALL PRINT_STR

SHOW_STATUS_REST:
	; Field 4: Print Mode / Keys / Selection / Memory (18 chars)
	LD A,(IS_SPLASH_SCREEN)
	OR A
	JP NZ,SHOW_STATUS_SPLASH_MEM

	LD A,(PLUGIN_IS_FAR_EXEC)
	OR A
	JP NZ,SHOW_STATUS_SPLASH_MEM

	LD A,(BLOCK_ACTIVE)
	OR A
	JP Z,SHOW_STATUS_NORMAL_KEYS

	CALL NORMALIZE_BLOCK_BOUNDS

	LD A,(BLOCK_ACTIVE)
	CP 2
	JR Z,STATUS_SOLIDIFIED

	; Dynamic selection active: "Sel: " (5 chars)
	LD DE,STR_SEL_PREFIX
	CALL PRINT_STR
	LD C,5				; 5 chars for "Sel: "

	; Check if single-line or multi-line
	LD HL,(BLOCK_START_ROW)
	LD DE,(BLOCK_END_ROW)
	LD A,H
	CP D
	JR NZ,STATUS_SEL_MULTILINE
	LD A,L
	CP E
	JR NZ,STATUS_SEL_MULTILINE

	; Single-line selection: chars count
	LD A,(BLOCK_END_COL)
	LD HL,BLOCK_START_COL
	SUB (HL)			; A = char count (0..120)
	PUSH AF
	CALL PRINT_DEC_BYTE
	POP AF
	INC C				; at least 1 digit
	CP 10
	JR C,S_SEL_DIG_DONE
	INC C
	CP 100
	JR C,S_SEL_DIG_DONE
	INC C
S_SEL_DIG_DONE:
	CP 1
	JR NZ,S_SEL_CHARS
	LD DE,STR_STAT_CHAR_S		; " char"
	CALL PRINT_STR
	LD A,C
	ADD A,5
	LD C,A
	JP STATUS_BLOCK_PAD
S_SEL_CHARS:
	LD DE,STR_STAT_CHARS_S		; " chars"
	CALL PRINT_STR
	LD A,C
	ADD A,6
	LD C,A
	JP STATUS_BLOCK_PAD

STATUS_SEL_MULTILINE:
	CALL GET_BLOCK_BOUNDS		; BC = line count
	LD L,C
	LD H,B
	CALL GET_DEC_WORD_DIGITS	; A = digits (1..5)
	ADD A,5				; A = digits + 5 ("Sel: ")
	LD C,A
	PUSH HL				; Save line count
	CALL PRINT_DEC_WORD
	POP HL				; Restore line count
	; Check if line count is 1
	LD A,H
	OR A
	JR NZ,S_SEL_LINES
	LD A,L
	CP 1
	JR NZ,S_SEL_LINES
	LD DE,STR_STAT_LINE_S		; " line"
	CALL PRINT_STR
	LD A,C
	ADD A,5
	LD C,A
	JP STATUS_BLOCK_PAD
S_SEL_LINES:
	LD DE,STR_STAT_LINES_S		; " lines"
	CALL PRINT_STR
	LD A,C
	ADD A,6
	LD C,A
	JP STATUS_BLOCK_PAD

STATUS_SOLIDIFIED:
	; Solidified block: "Block: " (7 chars)
	LD DE,STR_BLK_PREFIX
	CALL PRINT_STR
	LD C,7				; 7 for "Block: "

	LD HL,(BLOCK_START_ROW)
	LD DE,(BLOCK_END_ROW)
	LD A,H
	CP D
	JR NZ,STATUS_SOLID_MULTILINE
	LD A,L
	CP E
	JR NZ,STATUS_SOLID_MULTILINE

	; Single-line solidified: chars count
	LD A,(BLOCK_END_COL)
	LD HL,BLOCK_START_COL
	SUB (HL)			; A = char count
	PUSH AF
	CALL PRINT_DEC_BYTE
	POP AF
	INC C				; at least 1 digit
	CP 10
	JR C,S_SOL_DIG_DONE
	INC C
	CP 100
	JR C,S_SOL_DIG_DONE
	INC C
S_SOL_DIG_DONE:
	CP 1
	JR NZ,S_SOL_CHARS
	LD DE,STR_STAT_CHAR_S		; " char"
	CALL PRINT_STR
	LD A,C
	ADD A,5
	LD C,A
	JP STATUS_BLOCK_PAD
S_SOL_CHARS:
	CP 100
	JR NC,S_SOL_C_SFX
	LD DE,STR_STAT_CHARS_S		; " chars"
	CALL PRINT_STR
	LD A,C
	ADD A,6
	LD C,A
	JP STATUS_BLOCK_PAD
S_SOL_C_SFX:
	LD DE,STR_STAT_C_SUFFIX		; "c"
	CALL PRINT_STR
	INC C
	JP STATUS_BLOCK_PAD

STATUS_SOLID_MULTILINE:
	CALL GET_BLOCK_BOUNDS		; BC = line count
	LD L,C
	LD H,B
	CALL GET_DEC_WORD_DIGITS	; A = digits (1..5)
	ADD A,7				; A = digits + 7 ("Block: ")
	LD C,A
	PUSH HL				; Save line count
	CALL PRINT_DEC_WORD
	POP HL				; Restore line count
	LD A,H
	OR A
	JR NZ,S_SOL_L_SFX		; >= 256 lines -> "L"
	LD A,L
	CP 100
	JR NC,S_SOL_L_SFX		; >= 100 lines -> "L"
	CP 1
	JR NZ,S_SOL_LINES
	LD DE,STR_STAT_LINE_S		; " line"
	CALL PRINT_STR
	LD A,C
	ADD A,5
	LD C,A
	JP STATUS_BLOCK_PAD
S_SOL_LINES:
	LD DE,STR_STAT_LINES_S		; " lines"
	CALL PRINT_STR
	LD A,C
	ADD A,6
	LD C,A
	JP STATUS_BLOCK_PAD
S_SOL_L_SFX:
	LD DE,STR_STAT_L_SUFFIX		; "L"
	CALL PRINT_STR
	INC C
	JR STATUS_BLOCK_PAD

STATUS_BLOCK_PAD:
	LD A,C
	CP 15
	JR NC,STATUS_BLOCK_PAD_DONE
	LD A,' '
	CALL PUTC
	INC C
	JR STATUS_BLOCK_PAD

STATUS_BLOCK_PAD_DONE:
	LD DE,STR_STATUS_SEP		; " | "
	CALL PRINT_STR
	JP SHOW_STATUS_ROWCOL

SHOW_STATUS_NORMAL_KEYS:
	; Check if viewport is panned horizontally (VIEW_LEFT_COL > 0)
	LD HL,(VIEW_LEFT_COL)
	LD A,H
	OR L
	JR NZ,SHOW_STATUS_PAN_OFFSET

	LD A,(INSERT_MODE)
	OR A
	JR Z,SHOW_STATUS_OVERWRITE
	LD DE,STR_STATUS_KEYS
	CALL PRINT_STR
	JP SHOW_STATUS_ROWCOL

SHOW_STATUS_OVERWRITE:
	LD DE,STR_STATUS_OVR
	CALL PRINT_STR
	JP SHOW_STATUS_ROWCOL

SHOW_STATUS_PAN_OFFSET:
	; Field 4 total length must be 18 chars (15 text + 3 " | ")
	LD DE,STR_PAN_PREFIX		; "[Pan +" (6 chars)
	CALL PRINT_STR
	LD HL,(VIEW_LEFT_COL)
	CALL GET_DEC_WORD_DIGITS	; A = digits (1..5)
	LD C,A
	LD HL,(VIEW_LEFT_COL)
	CALL PRINT_DEC_WORD
	LD A,']'
	CALL PUTC
	; Pad with (8 - digits) spaces
	LD A,8
	SUB C				; A = 8 - digits
	LD B,A
SSPO_PAD_LOOP:
	LD A,' '
	CALL PUTC
	DJNZ SSPO_PAD_LOOP
	LD DE,STR_STATUS_SEP		; " | " (3 chars)
	CALL PRINT_STR
	JR SHOW_STATUS_ROWCOL

SHOW_STATUS_SPLASH_MEM:
	CALL PRINT_STATUS_FREE_MEM
	JR SHOW_STATUS_ROWCOL

SHOW_STATUS_ROWCOL:
	; Field 5: Print fixed-position cursor position (POS_FIELD_WIDTH = 22
	; chars)
	; "Line <cur:4>/<total:4> Col <col:3>"
	LD A,(IS_LOADING_FILE)
	OR A
	JR Z,SSRC_NOT_LOADING
	LD DE,STR_STATUS_LOADING_POS
	CALL PRINT_STR
	JP SSRC_POS_DONE

SSRC_NOT_LOADING:
	; 1. Prefix: "Line " (5 chars)
	LD DE,STR_STATUS_POS		; "Line "
	CALL PRINT_STR

SSRC_NORMAL_POS:

	; 2. Current line: right-justified in 4 chars
	LD HL,(CUR_DOC_ROW)
	INC HL
	CALL GET_DEC_WORD_DIGITS	; A = digits (1..5)
	LD C,A
	LD A,4
	SUB C				; A = 4 - digits
	JR C,SSRC_CUR_PRINT
	JR Z,SSRC_CUR_PRINT
	LD B,A
SSRC_CUR_PAD:
	LD A,' '
	CALL PUTC
	DJNZ SSRC_CUR_PAD
SSRC_CUR_PRINT:
	LD HL,(CUR_DOC_ROW)
	INC HL
	CALL PRINT_DEC_WORD

	; 3. "/" delimiter (1 char at fixed column)
	LD A,'/'
	CALL PUTC

	; 4. Max lines: left-justified in 4 chars
	LD HL,(DOC_TOTAL_LINES)
	CALL GET_DEC_WORD_DIGITS	; A = digits (1..5)
	LD C,A
	LD HL,(DOC_TOTAL_LINES)
	CALL PRINT_DEC_WORD
	LD A,4
	SUB C				; A = 4 - digits
	JR C,SSRC_TOT_PAD_DONE
	JR Z,SSRC_TOT_PAD_DONE
	LD B,A
SSRC_TOT_PAD:
	LD A,' '
	CALL PUTC
	DJNZ SSRC_TOT_PAD
SSRC_TOT_PAD_DONE:

	; 5. " Col " label (5 chars at fixed column)
	LD DE,STR_STATUS_COL		; " Col "
	CALL PRINT_STR

	; 6. Column: left-justified in 3 chars
	CALL CALC_VISUAL_COL		; HL = visual col (0..1000)
	CALL GET_DEC_WORD_DIGITS	; A = digits (1..5)
	LD C,A
	PUSH BC
	CALL PRINT_DEC_WORD
	POP BC
	LD A,3
	SUB C				; A = 3 - digits
	JR C,SSRC_COL_PAD_DONE
	JR Z,SSRC_COL_PAD_DONE
	LD B,A
SSRC_COL_PAD:
	LD A,' '
	CALL PUTC
	DJNZ SSRC_COL_PAD
SSRC_COL_PAD_DONE:
SSRC_POS_DONE:
	; Extreme Right Enclosure: " |" (2 chars)
	LD A,' '
	CALL PUTC
	LD A,'|'
	CALL PUTC

	; Symmetrical Right Margin: (ACTIVE_COLS - STATUS_ENCLOSED_WIDTH) / 2
	LD A,(ACTIVE_COLS)
	SUB STATUS_ENCLOSED_WIDTH
	SRL A				; A = 1 (80x24) or 21 (120x40)
	LD B,A
	OR A
	JR Z,SSRC_RIGHT_PAD_DONE
SSRC_RIGHT_PAD:
	LD A,' '
	CALL PUTC
	DJNZ SSRC_RIGHT_PAD
SSRC_RIGHT_PAD_DONE:
	CALL TERM_INVERSE_OFF
	CALL LOCATE_CURSOR
	RET
; MEM_FIELD_WIDTH is defined in include/ui.inc

;------------------------------------------------------------------------------
; PRINT_STATUS_FREE_MEM: Format free memory field for status bar on splash
;
; Purpose:
;   Calculates free document memory in whole KB and emits formatted string
;   "Free: <N> KB" padded to 15 columns, followed by field separator " | ".
;
; Call Usage / Protocol:
;   Called via CALL from RENDER_STATUS_BAR on splash screen or Far plugin run.
;
; Inputs:
;   None.
;
; Outputs:
;   Free memory field emitted to console.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
PRINT_STATUS_FREE_MEM:
	CALL CALC_FREE_MEM_KB		; HL = Free memory in whole KB
	PUSH HL

	; Calculate character count of "Free: <N> KB"
	; "Free: " = 6 chars, " KB" = 3 chars -> 9 chars + digits
	CALL GET_DEC_WORD_DIGITS	; A = number of digits (1..5)
	ADD A,9				; A = total chars before padding
	LD C,A				; C = characters printed so far

	LD DE,STR_STATUS_FREE		; "Free: "
	CALL PRINT_STR

	POP HL				; HL = Free KB
	CALL PRINT_DEC_WORD

	LD DE,STR_STATUS_KB		; " KB"
	CALL PRINT_STR

PSFM_PAD_LOOP:
	LD A,C
	CP MEM_FIELD_WIDTH		; 15
	JR NC,PSFM_DONE
	LD A,' '
	CALL PUTC
	INC C
	JR PSFM_PAD_LOOP

PSFM_DONE:
	LD DE,STR_STATUS_SEP		; " | "
	CALL PRINT_STR
	RET

;------------------------------------------------------------------------------
; SET_OOM_STATUS: Flag out-of-memory condition and display error modal
;
; Purpose:
;   Sets STATUS_OOM_FLAG to 1 and, if currently in active editor mode,
;   displays a centered modal pop-up error box notifying the user that
;   available RAM capacity has been exhausted.
;
; Call Usage / Protocol:
;   Called via CALL when memory allocation or line insertion fails.
;
; Inputs:
;   IN_EDITOR_MODE, IS_SPLASH_SCREEN.
;
; Outputs:
;   STATUS_OOM_FLAG = 1; modal pop-up rendered if in editor.
;
; Preserves / Modifies:
;   Preserves all registers: AF, BC, DE, HL.
;------------------------------------------------------------------------------
SET_OOM_STATUS:
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL
	LD A,1
	LD (STATUS_OOM_FLAG),A
	; Only display modal pop-up if in editor mode and not splash screen
	LD A,(IN_EDITOR_MODE)
	OR A
	JR Z,SOS_DONE
	LD A,(IS_SPLASH_SCREEN)
	OR A
	JR NZ,SOS_DONE
	CALL SHOW_OOM_POPUP
SOS_DONE:
	POP HL
	POP DE
	POP BC
	POP AF
	RET

;------------------------------------------------------------------------------
; SHOW_OOM_POPUP: Display centered Out of Memory modal pop-up
;
; Purpose:
;   Sets up title and message pointers and invokes SHOW_STATUS_EVENT_POPUP
;   to present an Out of Memory alert dialog.
;
; Call Usage / Protocol:
;   Called via CALL from SET_OOM_STATUS.
;
; Inputs:
;   None.
;
; Outputs:
;   Modal dialog rendered on screen.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SHOW_OOM_POPUP:
	LD DE,STR_POPUP_OOM_TITLE
	LD HL,STR_POPUP_OOM_MSG1
	LD BC,STR_POPUP_OOM_MSG2
	JP SHOW_STATUS_EVENT_POPUP

;------------------------------------------------------------------------------
; CALC_FREE_MEM_KB: Calculate available document memory in whole kilobytes
;
; Purpose:
;   Computes total Far RAM slot capacity (EXT_BANK_COUNT * 256), subtracts
;   currently allocated document lines, and divides by 8 to obtain whole
;   kilobytes of remaining text storage capacity.
;
; Call Usage / Protocol:
;   Called via CALL by status bar and memory summary routines.
;
; Inputs:
;   EXT_BANK_COUNT, DOC_TOTAL_LINES, IN_EDITOR_MODE.
;
; Outputs:
;   HL = Free memory in whole KB (slots / 8).
;
; Preserves / Modifies:
;   Preserves AF, BC, DE; returns value in HL.
;------------------------------------------------------------------------------
CALC_FREE_MEM_KB:
	PUSH AF
	PUSH BC
	PUSH DE

	LD A,(EXT_BANK_COUNT)
	LD H,A
	LD L,0			; HL = Total slots (EXT_BANK_COUNT * 256)
	LD A,(IN_EDITOR_MODE)
	OR A
	JR Z,CFM_DIV8		; If no active editor document, 0 slots used

	LD DE,(DOC_TOTAL_LINES)
	AND A
	SBC HL,DE			; HL = Total slots - DOC_TOTAL_LINES
	JR NC,CFM_DIV8
	LD HL,0				; Clamped to 0
CFM_DIV8:
	SRL H
	RR L
	SRL H
	RR L
	SRL H
	RR L				; HL = Free KB (slots / 8)

	POP DE
	POP BC
	POP AF
	RET

;------------------------------------------------------------------------------
; GET_DEC_WORD_DIGITS: Count decimal digits needed for 16-bit value in HL
;
; Purpose:
;   Compares 16-bit integer in HL against decimal threshold magnitudes
;   (10, 100, 1000, 10000) to determine number of decimal digits (1..5).
;
; Call Usage / Protocol:
;   Called via CALL by status bar, dialog formatters, and line number printers.
;
; Inputs:
;   HL = 16-bit unsigned integer (0..65535).
;
; Outputs:
;   A = Number of decimal digits (1..5).
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; modifies AF.
;------------------------------------------------------------------------------
GET_DEC_WORD_DIGITS:
	PUSH DE
	LD A,1
	LD DE,10
	CALL CMP_HL_DE
	JR C,GDWD_DONE
	INC A
	LD DE,100
	CALL CMP_HL_DE
	JR C,GDWD_DONE
	INC A
	LD DE,1000
	CALL CMP_HL_DE
	JR C,GDWD_DONE
	INC A
	LD DE,10000
	CALL CMP_HL_DE
	JR C,GDWD_DONE
	INC A
GDWD_DONE:
	POP DE
	RET

;------------------------------------------------------------------------------
; CMP_HL_DE: Compare 16-bit unsigned word in HL with DE
;
; Purpose:
;   Performs unsigned subtraction (HL - DE) to set processor condition flags
;   without modifying either register operand.
;
; Call Usage / Protocol:
;   General 16-bit comparison primitive called throughout SE.COM.
;
; Inputs:
;   HL, DE = 16-bit values to compare.
;
; Outputs:
;   Carry = 1 if HL < DE; Carry = 0, Zero = 1 if HL == DE;
;   Carry = 0, Zero = 0 if HL > DE.
;
; Preserves / Modifies:
;   Preserves HL, DE; modifies AF (flags).
;------------------------------------------------------------------------------
CMP_HL_DE:
	; Compare HL with DE: Carry=1 if HL < DE. Preserves HL, DE.
	PUSH HL
	OR A
	SBC HL,DE
	POP HL
	RET
; FILENAME_FIELD_WIDTH is defined in include/ui.inc
PSF_MAX_LEN:		DB	14

;------------------------------------------------------------------------------
; PRINT_STATUS_FILENAME: Format and print document filename in status bar
;
; Purpose:
;   Outputs active file specification (or "(Untitled)") padded to exactly
;   14 characters, followed by " | ". Handles CP/M drive prefix, user area,
;   and VFS FAT path display without duplicate drive letters.
;
; Call Usage / Protocol:
;   Called via CALL from RENDER_STATUS_BAR.
;
; Inputs:
;   WORK_FCB, HAS_FILE_ARG, DOC_IS_FAT, DOC_USER_NUM.
;
; Outputs:
;   14-character filename field + " | " emitted to console.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
PRINT_STATUS_FILENAME:
	LD C,0				; C = characters printed so far
	LD A,FILENAME_FIELD_WIDTH	; Default max chars = 14
	LD (PSF_MAX_LEN),A

	LD A,(IS_SAVING_FILE)
	OR A
	JR NZ,PSF_LIMIT_SET

	LD A,(DOC_MODIFIED)
	OR A
	JR Z,PSF_LIMIT_SET

	; If modified, reserve 1 char for '*' (max 13)
	LD A,FILENAME_FIELD_WIDTH-1
	LD (PSF_MAX_LEN),A

PSF_LIMIT_SET:
	LD A,(IS_SAVING_FILE)
	OR A
	JR NZ,PSF_HAVE_FILE

	LD A,(HAS_FILE_ARG)
	OR A
	JR NZ,PSF_HAVE_FILE

	; Unknown filename: print "(Untitled)"
	LD DE,STR_NO_NAME
PSF_NO_NAME_LOOP:
	LD A,(DE)
	OR A
	JP Z,PSF_CHECK_MODIFIED
	CALL PUTC
	INC DE
	INC C
	JR PSF_NO_NAME_LOOP

PSF_HAVE_FILE:
	; Check if active document is a FAT/DOS file
	LD A,(DOC_IS_FAT)
	OR A
	JP NZ,PSF_FAT_FILE

	; Check if WORK_FCB+1..8 already contains a drive letter (e.g. "C:")
	LD A,(WORK_FCB+2)
	CP ':'
	JR Z,PSF_NO_DRIVE_PREFIX

	; Determine drive letter
	LD A,(WORK_FCB)
	OR A
	JR NZ,PSF_USE_FCB_DRIVE

	; WORK_FCB has 0 -> Query current default drive via BDOS 25
	PUSH BC
	LD C,25
	CALL BDOS_ENTRY
	POP BC
	ADD A,'A'
	JR PSF_EMIT_DRIVE

PSF_USE_FCB_DRIVE:
	ADD A,'A'-1			; 1 -> 'A', 2 -> 'B', etc.

PSF_EMIT_DRIVE:
	CALL PUTC
	INC C

	; If DOC_USER_NUM > 0, emit user number digits
	LD A,(DOC_USER_NUM)
	OR A
	JR Z,PSF_EMIT_COLON
	CP 10
	JR C,PSF_USER_1DIGIT
	PUSH AF
	LD A,'1'
	CALL PUTC
	INC C
	POP AF
	SUB 10
PSF_USER_1DIGIT:
	ADD A,'0'
	CALL PUTC
	INC C

PSF_EMIT_COLON:
	LD A,':'
	CALL PUTC
	INC C

PSF_NO_DRIVE_PREFIX:
	; Print up to 8 characters of filename (WORK_FCB+1..8)
	LD HL,WORK_FCB+1
	LD B,8
PSF_NAME_LOOP:
	LD A,(HL)
	CP ' '
	JR Z,PSF_CHECK_EXT
	OR A
	JR Z,PSF_CHECK_EXT
	LD A,(PSF_MAX_LEN)
	CP C
	JR Z,PSF_CHECK_EXT
	JR C,PSF_CHECK_EXT
	LD A,(HL)
	CALL PUTC
	INC C
	INC HL
	DJNZ PSF_NAME_LOOP

PSF_CHECK_EXT:
	; Print extension if present (WORK_FCB+9..11)
	LD HL,WORK_FCB+9
	LD A,(HL)
	CP ' '
	JR Z,PSF_CHECK_MODIFIED
	OR A
	JR Z,PSF_CHECK_MODIFIED

	LD A,(PSF_MAX_LEN)
	CP C
	JR Z,PSF_CHECK_MODIFIED
	JR C,PSF_CHECK_MODIFIED

	LD A,'.'
	CALL PUTC
	INC C

	LD B,3
PSF_EXT_LOOP:
	LD A,(HL)
	CP ' '
	JR Z,PSF_CHECK_MODIFIED
	OR A
	JR Z,PSF_CHECK_MODIFIED
	LD A,(PSF_MAX_LEN)
	CP C
	JR Z,PSF_CHECK_MODIFIED
	JR C,PSF_CHECK_MODIFIED
	LD A,(HL)
	CALL PUTC
	INC C
	INC HL
	DJNZ PSF_EXT_LOOP
	JR PSF_CHECK_MODIFIED

PSF_FAT_FILE:
	; Emit 'U'
	LD A,'U'
	CALL PUTC
	INC C

	; If FAT_DOC_UNIT != 0xFF, emit unit digit (e.g. '2' or '4')
	LD A,(FAT_DOC_UNIT)
	CP 0FFH
	JR Z,PFF_EMIT_COLON
	ADD A,'0'
	CALL PUTC
	INC C

PFF_EMIT_COLON:
	LD A,':'
	CALL PUTC
	INC C

	; Print FAT_DOC_FNAME characters up to PSF_MAX_LEN
	LD HL,FAT_DOC_FNAME
PFF_NAME_LOOP:
	LD A,(HL)
	OR A
	JR Z,PSF_CHECK_MODIFIED
	CP ' '
	JR Z,PSF_CHECK_MODIFIED
	LD A,(PSF_MAX_LEN)
	CP C
	JR Z,PSF_CHECK_MODIFIED
	JR C,PSF_CHECK_MODIFIED
	LD A,(HL)
	CALL PUTC
	INC C
	INC HL
	JR PFF_NAME_LOOP

PSF_CHECK_MODIFIED:
	; Check if document is modified and not currently saving
	LD A,(IS_SAVING_FILE)
	OR A
	JR NZ,PSF_PAD_SPACES

	LD A,(DOC_MODIFIED)
	OR A
	JR Z,PSF_PAD_SPACES

	; Document is modified: print '*' indicator (max 13 chars printed, so
	; space exists)
	LD A,'*'
	CALL PUTC
	INC C

PSF_PAD_SPACES:
	; Pad remaining characters with spaces up to FILENAME_FIELD_WIDTH
	LD A,C
	CP FILENAME_FIELD_WIDTH
	JR NC,PSF_DONE
	LD A,' '
	CALL PUTC
	INC C
	JR PSF_PAD_SPACES

PSF_DONE:
	LD DE,STR_STATUS_SEP
	CALL PRINT_STR
	RET

;------------------------------------------------------------------------------
; ADJUST_HORIZ_VIEWPORT: Auto-scroll horizontal viewport in 40-column steps
;
; Purpose:
;   Compares cursor visual column against current viewport window bounds
;   (VIEW_LEFT_COL and VIEW_RIGHT_COL). Pans horizontal viewport left or right
;   in 40-column increments when cursor moves past margins.
;
; Call Usage / Protocol:
;   Called via CALL before rendering and during cursor navigation.
;
; Inputs:
;   CUR_COL, VIEW_LEFT_COL, VIEW_RIGHT_COL, ACTIVE_COLS.
;
; Outputs:
;   VIEW_LEFT_COL, VIEW_RIGHT_COL updated; sets NEED_SCREEN_RENDER if panned.
;
; Preserves / Modifies:
;   Preserves all registers: AF, BC, DE, HL.
;------------------------------------------------------------------------------
ADJUST_HORIZ_VIEWPORT:
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL

	CALL CALC_VISUAL_COL	; HL = true visual column (0..MAX_LINE_CHARS-1)
	EX DE,HL			; DE = visual column

	; 1. Check if cursor is off-screen to the left or on left continuation
	; highlight
	LD HL,(VIEW_LEFT_COL)
	LD A,H
	OR L
	JR Z,AHV_CHECK_RIGHT		; VIEW_LEFT_COL == 0 -> cannot pan left

	; If VIEW_LEFT_COL >= DE (i.e. DE <= VIEW_LEFT_COL), cursor is on/past
	; highlight -> pan left!
	LD A,L
	SUB E
	LD A,H
	SBC A,D
	JR NC,AHV_PAN_LEFT		; VIEW_LEFT_COL >= DE -> pan left

AHV_CHECK_RIGHT:
	; 2. Check if cursor is off-screen to the right (DE >= VIEW_RIGHT_COL)
	LD HL,(VIEW_RIGHT_COL)
	LD A,E
	SUB L
	LD A,D
	SBC A,H
	JR NC,AHV_PAN_RIGHT		; DE >= VIEW_RIGHT_COL -> pan right

	; 3. Check if cursor is on right screen edge (DE == VIEW_RIGHT_COL - 1)
	DEC HL				; HL = VIEW_RIGHT_COL - 1
	LD A,E
	CP L
	JR NZ,AHV_DONE
	LD A,D
	CP H
	JR NZ,AHV_DONE

	; Cursor is at right screen edge: check if line continues past CUR_COL:
	CALL CHECKOUT_ACTIVE_LINE	; HL = ACTIVE_LINE_BUF
	LD BC,(CUR_COL)
	ADD HL,BC			; HL = pointer to char at CUR_COL
	LD A,(HL)
	OR A
	JR Z,AHV_DONE			; At null terminator -> line ends
	INC HL
	LD A,(HL)
	OR A
	JR Z,AHV_DONE			; Next is null -> last char
	; Line continues beyond right edge -> pan right!
	JR AHV_PAN_RIGHT

AHV_PAN_LEFT:
	; Pan left: round (DE - 1) down to multiple of 40 so cursor is strictly
	; > new VIEW_LEFT_COL
	LD HL,0
	LD A,D
	OR E
	JR Z,AHV_UPDATE_HL		; If DE == 0, new VIEW_LEFT_COL = 0
	DEC DE				; DE = DE - 1
AHV_PL_LOOP:
	LD A,E
	SUB 40
	LD B,A
	LD A,D
	SBC A,0
	JR C,AHV_UPDATE_HL
	LD E,B
	LD D,A
	LD BC,40
	ADD HL,BC
	JR AHV_PL_LOOP

AHV_PAN_RIGHT:
	LD HL,(VIEW_LEFT_COL)
AHV_PR_LOOP:
	LD BC,40
	ADD HL,BC			; HL += 40
	LD A,(ACTIVE_COLS)
	LD C,A
	LD B,0
	PUSH HL
	ADD HL,BC			; HL = candidate VIEW_RIGHT_COL
	LD A,E
	SUB L
	LD A,D
	SBC A,H
	POP HL
	JR C,AHV_UPDATE_HL
	JR AHV_PR_LOOP

AHV_UPDATE_HL:
	; Check if HL differs from VIEW_LEFT_COL
	LD DE,(VIEW_LEFT_COL)
	LD A,L
	CP E
	JR NZ,AHV_STORE_NEW
	LD A,H
	CP D
	JR Z,AHV_DONE

AHV_STORE_NEW:
	LD (VIEW_LEFT_COL),HL
	LD A,(ACTIVE_COLS)
	LD E,A
	LD D,0
	ADD HL,DE
	LD (VIEW_RIGHT_COL),HL
	LD A,1
	LD (NEED_SCREEN_RENDER),A

AHV_DONE:
	POP HL
	POP DE
	POP BC
	POP AF
	RET

;------------------------------------------------------------------------------
; CONSTRAIN_CURSOR_VIEWPORT: Constrain cursor row within active viewport bounds
;
; Purpose:
;   Prevents cursor from pointing outside visible document area or below the
;   status bar when switching geometries (120x40 <-> 80x24) or loading files.
;   Adjusts CUR_DOC_ROW, TOP_DOC_ROW, and realigns CUR_COL to TARGET_COL.
;
; Call Usage / Protocol:
;   Called via CALL when switching geometries, resizing, or switching modes.
;
; Inputs:
;   CUR_DOC_ROW, TOP_DOC_ROW, ACTIVE_ROWS, DOC_TOTAL_LINES.
;
; Outputs:
;   CUR_DOC_ROW and TOP_DOC_ROW constrained within valid screen bounds.
;
; Preserves / Modifies:
;   Preserves all registers: AF, BC, DE, HL.
;------------------------------------------------------------------------------
CONSTRAIN_CURSOR_VIEWPORT:
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL

	; Ensure TOP_DOC_ROW < DOC_TOTAL_LINES
	LD DE,(DOC_TOTAL_LINES)
	LD A,D
	OR E
	JR Z,CCV_CALC_MAX_VIS
	LD HL,(TOP_DOC_ROW)
	CALL CMP_HL_DE		; Carry=1 if TOP_DOC_ROW < DOC_TOTAL_LINES
	JR C,CCV_CALC_MAX_VIS
	; TOP_DOC_ROW >= DOC_TOTAL_LINES: clamp TOP_DOC_ROW = DOC_TOTAL_LINES -
	; 1
	EX DE,HL
	DEC HL
	LD (TOP_DOC_ROW),HL

CCV_CALC_MAX_VIS:
	; 1. Calculate max visible doc row = TOP_DOC_ROW + (ACTIVE_ROWS - 2)
	LD A,(ACTIVE_ROWS)
	SUB 2	; A = max screen row index (e.g. 22 for 80x24, 38 for 120x40)
	LD E,A
	LD D,0
	LD HL,(TOP_DOC_ROW)
	ADD HL,DE			; HL = TOP_DOC_ROW + (ACTIVE_ROWS - 2)
	EX DE,HL			; DE = max visible doc row

	; 2. Clamp DE to DOC_TOTAL_LINES - 1 (if DOC_TOTAL_LINES > 0)
	LD HL,(DOC_TOTAL_LINES)
	LD A,H
	OR L
	JR Z,CCV_CHECK_CUR_ROW		; If 0 lines, DE remains upper bound
	DEC HL				; HL = DOC_TOTAL_LINES - 1
	; If DE > HL (last line < DE), clamp DE = HL
	CALL CMP_HL_DE			; Carry=1 if HL < DE
	JR NC,CCV_CHECK_CUR_ROW
	EX DE,HL			; DE = DOC_TOTAL_LINES - 1

CCV_CHECK_CUR_ROW:
	; Now DE is the maximum valid CUR_DOC_ROW for the viewport.
	; Check if CUR_DOC_ROW > DE:
	LD HL,(CUR_DOC_ROW)
	EX DE,HL			; HL = max allowed row, DE = CUR_DOC_ROW
	CALL CMP_HL_DE	; Carry=1 if HL < DE (i.e. max allowed < CUR_DOC_ROW)
	JR NC,CCV_CHECK_TOP_ROW
	; CUR_DOC_ROW > max allowed row: move cursor UP!
	LD (CUR_DOC_ROW),HL
	; Row changed: clamp CUR_COL to new line's length matching TARGET_COL
	CALL ADJUST_COL_TO_TARGET
	JR CCV_DONE

CCV_CHECK_TOP_ROW:
	; Check if CUR_DOC_ROW < TOP_DOC_ROW:
	LD HL,(CUR_DOC_ROW)
	LD DE,(TOP_DOC_ROW)
	CALL CMP_HL_DE			; Carry=1 if CUR_DOC_ROW < TOP_DOC_ROW
	JR NC,CCV_DONE
	; CUR_DOC_ROW < TOP_DOC_ROW: move cursor DOWN to TOP_DOC_ROW
	EX DE,HL
	LD (CUR_DOC_ROW),HL
	; Row changed: clamp CUR_COL to new line's length matching TARGET_COL
	CALL ADJUST_COL_TO_TARGET

CCV_DONE:
	POP HL
	POP DE
	POP BC
	POP AF
	RET

;------------------------------------------------------------------------------
; CALC_VISUAL_COL: Calculate visual display column from character offset
;
; Purpose:
;   Scans characters in ACTIVE_LINE_BUF from column 0 up to CUR_COL, expanding
;   tab characters according to CFG_TAB_WIDTH, to compute the true 0-indexed
;   visual terminal column.
;
; Call Usage / Protocol:
;   Called via CALL for cursor positioning, status bar, and viewport panning.
;
; Inputs:
;   CUR_COL, ACTIVE_LINE_BUF.
;
; Outputs:
;   HL = 16-bit Visual Column (0-indexed, 0..MAX_LINE_CHARS-1).
;
; Preserves / Modifies:
;   Preserves BC, DE; clobbers AF; returns value in HL.
;------------------------------------------------------------------------------
CALC_VISUAL_COL:
	PUSH BC
	PUSH DE

	; Ensure current line is checked out in ACTIVE_LINE_BUF
	CALL CHECKOUT_ACTIVE_LINE	; HL = ACTIVE_LINE_BUF

	LD DE,(CUR_COL)			; DE = character count to process
	LD BC,0				; BC = visual column accumulator

CALC_VIS_LOOP:
	LD A,D
	OR E
	JR Z,CALC_VIS_DONE

	LD A,(HL)
	OR A
	JR Z,CALC_VIS_DONE

	CP KEY_TAB
	JR Z,CALC_VIS_TAB

	INC BC
	JR CALC_VIS_NEXT

CALC_VIS_TAB:
	; Tab advances BC to next tab stop
	LD A,C
	CALL GET_TAB_SPACES		; spaces to add (1..CFG_TAB_WIDTH)
	ADD A,C
	LD C,A
	JR NC,CALC_VIS_NEXT
	INC B

CALC_VIS_NEXT:
	INC HL
	DEC DE
	JR CALC_VIS_LOOP

CALC_VIS_DONE:
	; Check clamp against MAX_LINE_CHARS-1
	LD HL,MAX_LINE_CHARS-1
	LD A,C
	SUB L
	LD A,B
	SBC A,H
	JR C,CALC_VIS_NO_CLAMP
	LD B,H
	LD C,L

CALC_VIS_NO_CLAMP:
	LD H,B
	LD L,C				; HL = 16-bit visual column
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; LOCATE_CURSOR: Reposition hardware terminal cursor at current editor position
;
; Purpose:
;   Computes 1-indexed terminal screen row (CUR_DOC_ROW - TOP_DOC_ROW + 1)
;   and 1-indexed terminal screen column (Visual Col - VIEW_LEFT_COL + 1),
;   clamping to visible bounds, and repositions hardware cursor via LOCATE_RC.
;
; Call Usage / Protocol:
;   Called via CALL at end of editing operations and screen redraws.
;
; Inputs:
;   CUR_DOC_ROW, TOP_DOC_ROW, CUR_COL, VIEW_LEFT_COL, ACTIVE_ROWS, ACTIVE_COLS.
;
; Outputs:
;   Hardware cursor located at active text position.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
LOCATE_CURSOR:
	; Screen Row = CUR_DOC_ROW - TOP_DOC_ROW + 1 (1-indexed for terminal)
	LD HL,(CUR_DOC_ROW)
	LD DE,(TOP_DOC_ROW)
	AND A
	SBC HL,DE
	JR NC,LC_ROW_POS
	LD HL,0			; Clamp to 0 if CUR_DOC_ROW < TOP_DOC_ROW
LC_ROW_POS:
	LD A,(ACTIVE_ROWS)
	SUB 2			; Max allowed row index (e.g. 22 for 80x24)
	LD E,A
	LD D,0
	CALL CMP_HL_DE			; Carry=1 if HL < DE
	JR C,LC_ROW_OK
	EX DE,HL			; Clamp to max row index
LC_ROW_OK:
	LD A,L
	INC A
	PUSH AF				; Save Screen Row on stack

	; Screen Column (1-indexed) = (Visual Col - VIEW_LEFT_COL) + 1
	CALL CALC_VISUAL_COL		; HL = visual column (16-bit)
	LD DE,(VIEW_LEFT_COL)
	AND A
	SBC HL,DE			; HL = Screen Column (0-indexed)
	JR NC,LC_COL_POS
	LD HL,0			; Clamp to 0 if Visual Col < VIEW_LEFT_COL
LC_COL_POS:
	LD A,(ACTIVE_COLS)
	DEC A			; Max allowed col index (e.g. 79 for 80-col)
	LD E,A
	LD D,0
	CALL CMP_HL_DE			; Carry=1 if HL < DE
	JR C,LC_COL_OK
	EX DE,HL			; Clamp to max col index
LC_COL_OK:
	LD A,L
	INC A
	LD L,A				; L = Screen Column (1-indexed)
	POP AF
	LD H,A				; H = Screen Row (1-indexed)
	JP LOCATE_RC

