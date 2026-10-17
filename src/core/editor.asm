;==============================================================================
; EDITOR.ASM: Core Subsystem - Interactive Key Loop, Cursor & Edit Primitives
;
; Purpose:
;   Implements console key polling, VT100 escape sequence decoding, cursor
;   positioning, page up/down navigation, goto line dialog, character
;   insertion/deletion, line splitting/joining, and search engine integration.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; VT100 Escape Sequence Handler (Arrow keys: Up, Down, Left, Right)
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; CHECK_KEY_READY: Non-blocking check for console keyboard input
;
; Purpose:
;   Calls direct BIOS CONST jump vector to check if character is available in
;   serial input buffer without blocking execution.
;
; Call Usage / Protocol:
;   Called via CALL in MAIN_LOOP and ESC timeout drain loops.
;
; Inputs:
;   None.
;
; Outputs:
;   Z flag set if no key is ready; NZ set if key is available (A != 0).
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; modifies AF (flags).
;------------------------------------------------------------------------------
CHECK_KEY_READY:
	PUSH BC
	PUSH DE
	PUSH HL
	LD HL,(BIOS_CONST_VEC)
	CALL CALL_HL		; Returns A = 0xFF if char ready, 0x00 if not
	POP HL
	POP DE
	POP BC
	OR A
	RET

;------------------------------------------------------------------------------
; DRAIN_ESC_SEQUENCE: Discard pending escape sequence characters
;
; Purpose:
;   If characters follow an initial ESC byte within a timeout window,
;   reads and discards them to prevent stray control sequences from leaking
;   into text buffers.
;
; Call Usage / Protocol:
;   Called via CALL upon encountering ESC in modal loops or splash screen.
;
; Inputs:
;   None.
;
; Outputs:
;   Pending escape sequence consumed from serial buffer.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
DRAIN_ESC_SEQUENCE:
	PUSH BC
	LD BC,ESC_TIMEOUT_LOOPS
DES_WAIT:
	CALL CHECK_KEY_READY
	JR NZ,DES_DRAIN_FIRST
	DEC BC
	LD A,B
	OR C
	JR NZ,DES_WAIT
	POP BC
	RET				; Standalone ESC, nothing to drain

DES_DRAIN_FIRST:
	CALL GET_KEY		; Consume byte following ESC ('[' or 'O' etc.)
	CP '['
	JR Z,DES_DRAIN_TAIL
	CP 'O'
	JR Z,DES_DRAIN_TAIL
	POP BC
	RET

DES_DRAIN_TAIL:
	CALL DCT_DRAIN_LOOP
	POP BC
	RET

;------------------------------------------------------------------------------
; DRAIN_INPUT_BUFFER: Flush all pending keystrokes from console input buffer
;
; Purpose:
;   Polls CHECK_KEY_READY, discarding characters until buffer is empty.
;
; Call Usage / Protocol:
;   Called via CALL before critical modal dialogs or error notifications.
;
; Inputs:
;   None.
;
; Outputs:
;   Console buffer emptied.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DRAIN_INPUT_BUFFER:
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL
DIB_LOOP:
	CALL CHECK_KEY_READY
	JR Z,DIB_DONE
	CALL GET_KEY
	JR DIB_LOOP
DIB_DONE:
	POP HL
	POP DE
	POP BC
	POP AF
	RET

;------------------------------------------------------------------------------
; HANDLE_VT100_ESC: Decode ANSI/VT100 escape sequences into editor navigation
;
; Purpose:
;   Parses multi-byte ANSI sequences (arrow keys, PgUp, PgDn, Home, End, Del,
;   F1..F4) received after ESC and dispatches corresponding editor actions.
;
; Call Usage / Protocol:
;   Jumped to from MAIN_LOOP when ESC character is encountered.
;
; Inputs:
;   None (reads subsequent sequence bytes from console).
;
; Outputs:
;   Executes corresponding editor movement or editing command.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HANDLE_VT100_ESC:
	; Check if a character follows ESC within a short timeout
	LD BC,ESC_TIMEOUT_LOOPS		; Timeout loop count
WAIT_ESC_BYTE:
	CALL CHECK_KEY_READY
	JR NZ,GOT_ESC_BYTE
	DEC BC
	LD A,B
	OR C
	JR NZ,WAIT_ESC_BYTE
	; Timeout: Standalone ESC key pressed
	LD A,(BLOCK_ACTIVE)
	OR A
	JR Z,ESC_TO_SPLASH
	; Block selection active: cancel block highlight instead of exiting to
	; splash
	CALL CANCEL_BLOCK
	RET

ESC_TO_SPLASH:
	JP SHOW_SPLASH_SCREEN

GOT_ESC_BYTE:
	CALL GET_KEY
	CP '['
	JR Z,HANDLE_CSI
	CP 'O'
	JR Z,HANDLE_SS3
	CP '<'
	JR Z,DO_ESC_TOP
	CP 't'
	JR Z,DO_ESC_TOP
	CP 'T'
	JR Z,DO_ESC_TOP
	CP '>'
	JR Z,DO_ESC_BOTTOM
	CP 'b'
	JR Z,DO_ESC_BOTTOM
	CP 'B'
	JR Z,DO_ESC_BOTTOM
	CP KEY_ESC
	JR Z,HANDLE_VT100_ESC
	RET

DO_ESC_TOP:
	CALL JUMP_FILE_TOP
	RET

DO_ESC_BOTTOM:
	CALL JUMP_FILE_BOTTOM
	RET

HANDLE_SS3:
	CALL GET_KEY
	CP 'A'				; Up Arrow
	JP Z,CURSOR_UP
	CP 'B'				; Down Arrow
	JP Z,CURSOR_DOWN
	CP 'C'				; Right Arrow
	JP Z,CURSOR_RIGHT
	CP 'D'				; Left Arrow
	JP Z,CURSOR_LEFT
	CP 'H'				; Home
	JP Z,CURSOR_HOME
	CP 'F'				; End
	JP Z,CURSOR_END
	JP DRAIN_CSI_TAIL

HANDLE_CSI:
	XOR A
	LD (CSI_DIGIT_PREFIX),A
	LD (CSI_MODIFIER),A
	CALL GET_KEY
	CP 'A'				; Up Arrow
	JP Z,CURSOR_UP
	CP 'B'				; Down Arrow
	JP Z,CURSOR_DOWN
	CP 'C'				; Right Arrow
	JP Z,CURSOR_RIGHT
	CP 'D'				; Left Arrow
	JP Z,CURSOR_LEFT
	CP 'a'				; rxvt Shift+Up
	JP Z,SHIFT_CURSOR_UP
	CP 'b'				; rxvt Shift+Down
	JP Z,SHIFT_CURSOR_DOWN
	CP 'c'				; rxvt Shift+Right
	JP Z,SHIFT_CURSOR_RIGHT
	CP 'd'				; rxvt Shift+Left
	JP Z,SHIFT_CURSOR_LEFT
	CP 'H'				; Home (ESC [ H)
	JP Z,CURSOR_HOME
	CP 'F'				; End (ESC [ F)
	JP Z,CURSOR_END
	CP '1'		; Home (ESC [ 1 ~) or modifier prefix (ESC [ 1 ; ...)
	JP Z,HANDLE_CSI_1
	CP '2'			; Shift+Arrow prefix (ESC [ 2 A..D) or Insert
	JP Z,HANDLE_CSI_2
	CP '4'		; End (ESC [ 4 ~) or modifier prefix (ESC [ 4 ; ...)
	JP Z,HANDLE_CSI_4
	CP '7'			; Home (ESC [ 7 ~) / Ctrl+Home (ESC [ 7 ^)
	JP Z,HANDLE_CSI_7
	CP '8'				; End (ESC [ 8 ~) / Ctrl+End (ESC [ 8 ^)
	JP Z,HANDLE_CSI_8
	CP '3'				; Delete Key (ESC [ 3 ~)
	JP Z,HANDLE_CSI_DEL
	CP '5'				; Page Up (ESC [ 5 ~)
	JP Z,HANDLE_CSI_PGUP
	CP '6'				; Page Down (ESC [ 6 ~)
	JP Z,HANDLE_CSI_PGDN
	CP 'I'				; Page Up (VT alternative)
	JP Z,PAGE_UP
	CP 'G'				; Page Down (VT alternative)
	JP Z,PAGE_DOWN
	CP 'L'				; VT102 Insert key (ESC [ L)
	JP Z,TOGGLE_INSERT_MODE
	CP '@'				; ICH Insert character (ESC [ @)
	JP Z,TOGGLE_INSERT_MODE

	; Check if parameter/modifier digits present (e.g. 1;2A, 1~, 4~)
	CP '0'
	JP C,CSI_DONE
	CP '9'+1
	JP C,HANDLE_CSI_LOOP_DIGIT
	IFDEF TARGET_NEXT
	JP DRAIN_REMAINING_CSI
	ELSE
	JP DRAIN_CSI_TAIL
	ENDIF

HANDLE_CSI_1:
	LD A,'1'
	LD (CSI_DIGIT_PREFIX),A
	CALL GET_KEY
	CP '~'
	JP Z,CURSOR_HOME
	CP ';'
	JP Z,HANDLE_CSI_LOOP
	IFDEF TARGET_NEXT
	JP DRAIN_REMAINING_CSI
	ELSE
	JP DRAIN_CSI_TAIL
	ENDIF

HANDLE_CSI_2:
	LD A,'2'
	LD (CSI_MODIFIER),A
	LD (CSI_DIGIT_PREFIX),A
	CALL GET_KEY
	CP '~'				; Insert key (ESC [ 2 ~)
	JP Z,TOGGLE_INSERT_MODE
	CP 'A'
	JP Z,SHIFT_CURSOR_UP
	CP 'B'
	JP Z,SHIFT_CURSOR_DOWN
	CP 'C'
	JP Z,SHIFT_CURSOR_RIGHT
	CP 'D'
	JP Z,SHIFT_CURSOR_LEFT
	CP ';'
	JP Z,HANDLE_CSI_LOOP
	IFDEF TARGET_NEXT
	JP DRAIN_REMAINING_CSI
	ELSE
	JP DRAIN_CSI_TAIL
	ENDIF

HANDLE_CSI_4:
	LD A,'4'
	LD (CSI_DIGIT_PREFIX),A
	CALL GET_KEY
	CP '~'
	JP Z,CURSOR_END
	CP ';'
	JP Z,HANDLE_CSI_LOOP
	IFDEF TARGET_NEXT
	JP DRAIN_REMAINING_CSI
	ELSE
	JP DRAIN_CSI_TAIL
	ENDIF

HANDLE_CSI_7:
	CALL GET_KEY
	CP '^'
	JP Z,JUMP_FILE_TOP		; rxvt Ctrl+Home (ESC [ 7 ^)
	CP '~'
	JP Z,CURSOR_HOME
	JP DRAIN_CSI_TAIL

HANDLE_CSI_8:
	CALL GET_KEY
	CP '^'
	JP Z,JUMP_FILE_BOTTOM		; rxvt Ctrl+End (ESC [ 8 ^)
	CP '~'
	JP Z,CURSOR_END
	JP DRAIN_CSI_TAIL

HANDLE_CSI_DEL:
	; Consume trailing '~'
	CALL GET_KEY
	CP '~'
	CALL NZ,DRAIN_CSI_TAIL
	LD A,(BLOCK_ACTIVE)
	CP 2
	JR Z,DO_CSI_DEL_BLOCK
	CP 1
	JR Z,DO_CSI_DEL_IMPLIED_K_DELETE
	CALL DO_DELETE_FORWARD
	RET

DO_CSI_DEL_IMPLIED_K_DELETE:
	CALL SOLIDIFY_BLOCK
DO_CSI_DEL_BLOCK:
	CALL DO_DELETE_BLOCK
	RET

HANDLE_CSI_PGUP:
	; Consume trailing '~'
	CALL GET_KEY
	CP '~'
	CALL NZ,DRAIN_CSI_TAIL
	CALL PAGE_UP
	RET

HANDLE_CSI_PGDN:
	; Consume trailing '~'
	CALL GET_KEY
	CP '~'
	CALL NZ,DRAIN_CSI_TAIL
	CALL PAGE_DOWN
	RET

HANDLE_CSI_LOOP_DIGIT:
	LD (CSI_MODIFIER),A
HANDLE_CSI_LOOP:
	CALL GET_KEY
	CP '~'
	JP Z,HANDLE_CSI_TILDE
	CP 'A'
	JP Z,HANDLE_CSI_A
	CP 'B'
	JP Z,HANDLE_CSI_B
	CP 'C'
	JP Z,HANDLE_CSI_C
	CP 'D'
	JP Z,HANDLE_CSI_D
	CP 'H'
	JP Z,JUMP_FILE_TOP	; Modified CSI: ESC [ 1 ; 5 H -> Ctrl+Home!
	CP 'F'
	JP Z,JUMP_FILE_BOTTOM	; Modified CSI: ESC [ 1 ; 5 F -> Ctrl+End!
	CP 'I'
	JP Z,PAGE_UP
	CP 'G'
	JP Z,PAGE_DOWN
	CP ';'
	JR Z,HANDLE_CSI_LOOP
	CP '0'
	JR C,CSI_DONE
	CP '9'+1
	JR C,HANDLE_CSI_LOOP_DIGIT
CSI_DONE:
	IFDEF TARGET_NEXT
	JP DRAIN_REMAINING_CSI
	ELSE
	JP DRAIN_CSI_TAIL
	ENDIF

;------------------------------------------------------------------------------
; DRAIN_CSI_TAIL: Drain unhandled CSI parameters and terminating byte
;
; Purpose:
;   Drains trailing bytes of unhandled or extended multi-byte escape sequences
;   until terminating character ('~', 'A'..'Z', 'a'..'z') or timeout.
;------------------------------------------------------------------------------
DRAIN_CSI_TAIL:
	CP '~'
	RET Z
	CP 'A'
	JR C,DCT_DRAIN_LOOP
	CP 'Z'+1
	RET C
	CP 'a'
	JR C,DCT_DRAIN_LOOP
	CP 'z'+1
	RET C

DCT_DRAIN_LOOP:
	LD BC,ESC_TIMEOUT_LOOPS
DCT_WAIT:
	CALL CHECK_KEY_READY
	JR NZ,DCT_GOT_BYTE
	DEC BC
	LD A,B
	OR C
	JR NZ,DCT_WAIT
	RET

DCT_GOT_BYTE:
	CALL GET_KEY
	CP '~'
	RET Z
	CP 'A'
	JR C,DCT_DRAIN_LOOP
	CP 'Z'+1
	RET C
	CP 'a'
	JR C,DCT_DRAIN_LOOP
	CP 'z'+1
	RET C
	JR DCT_DRAIN_LOOP

CHECK_CSI_SHIFT:
	LD A,(CSI_MODIFIER)
	CP '2'
	RET Z
	CP '6'
	RET

HANDLE_CSI_A:
	CALL CHECK_CSI_SHIFT
	JP Z,SHIFT_CURSOR_UP
	JP CURSOR_UP

HANDLE_CSI_B:
	CALL CHECK_CSI_SHIFT
	JP Z,SHIFT_CURSOR_DOWN
	JP CURSOR_DOWN

HANDLE_CSI_C:
	CALL CHECK_CSI_SHIFT
	JP Z,SHIFT_CURSOR_RIGHT
	JP CURSOR_RIGHT

HANDLE_CSI_D:
	CALL CHECK_CSI_SHIFT
	JP Z,SHIFT_CURSOR_LEFT
	JP CURSOR_LEFT

SHIFT_CURSOR_UP:
	CALL START_NEW_BLOCK_AT_CURSOR
	JP CURSOR_UP

SHIFT_CURSOR_DOWN:
	CALL START_NEW_BLOCK_AT_CURSOR
	JP CURSOR_DOWN

SHIFT_CURSOR_RIGHT:
	CALL START_NEW_BLOCK_AT_CURSOR
	JP CURSOR_RIGHT

SHIFT_CURSOR_LEFT:
	CALL START_NEW_BLOCK_AT_CURSOR
	JP CURSOR_LEFT

HANDLE_CSI_TILDE:
	LD A,(CSI_DIGIT_PREFIX)
	CP '1'
	JP Z,JUMP_FILE_TOP		; ESC [ 1 ; 5 ~ -> Ctrl+Home!
	CP '4'
	JP Z,JUMP_FILE_BOTTOM		; ESC [ 4 ; 5 ~ -> Ctrl+End!
	CP '2'
	JP Z,TOGGLE_INSERT_MODE		; ESC [ 2 ; <n> ~ -> Insert!
	LD A,(CSI_MODIFIER)
	CP '2'
	JP Z,TOGGLE_INSERT_MODE
	RET

TOGGLE_INSERT_MODE:
	LD A,(INSERT_MODE)
	XOR 1
	LD (INSERT_MODE),A
	LD A,1
	LD (NEED_STATUS_RENDER),A
	RET

CURSOR_HOME:
	LD HL,0
	LD (CUR_COL),HL
	LD (TARGET_COL),HL
	LD A,(BLOCK_ACTIVE)
	CP 1
	RET NZ
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	RET

CURSOR_END:
	; HL = line start, DE = byte length, BC = visual length
	CALL GET_CUR_ROW_LEN
	LD HL,MAX_INPUT_LINE_CHARS-1	; 999
	LD A,E
	SUB L
	LD A,D
	SBC A,H
	JR C,CE_NOT_FULL
	EX DE,HL			; Clamp to 999
CE_NOT_FULL:
	LD (CUR_COL),DE
	CALL CALC_VISUAL_COL
	LD (TARGET_COL),HL
	LD A,(BLOCK_ACTIVE)
	CP 1
	RET NZ
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	RET

;------------------------------------------------------------------------------
; GET_CUR_ROW_LEN: Measure character length of active document line
;
; Purpose:
;   Ensures CUR_DOC_ROW is checked out in ACTIVE_LINE_BUF and counts characters
;   up to the terminating null byte.
;
; Call Usage / Protocol:
;   Called via CALL by cursor navigation and column clamping routines.
;
; Inputs:
;   CUR_DOC_ROW.
;
; Outputs:
;   BC = 16-bit character count; HL = 16-bit character count.
;
; Preserves / Modifies:
;   Preserves DE; returns count in BC and HL; clobbers AF.
;------------------------------------------------------------------------------
GET_CUR_ROW_LEN:
	CALL CHECKOUT_ACTIVE_LINE	; HL = ACTIVE_LINE_BUF
	PUSH HL				; Save line start

	LD DE,0				; DE = byte count
	LD BC,0				; BC = visual column accumulator
GET_ROW_LEN_LOOP:
	LD A,(HL)
	OR A
	JR Z,GET_ROW_LEN_DONE
	CP KEY_TAB
	JR Z,GET_ROW_TAB
	INC DE
	INC BC
	JR GET_ROW_NEXT

GET_ROW_TAB:
	INC DE
	LD A,C
	CALL GET_TAB_SPACES		; spaces to add (1..CFG_TAB_WIDTH)
	ADD A,C
	LD C,A
	JR NC,GET_ROW_NEXT
	INC B

GET_ROW_NEXT:
	INC HL
	LD A,E
	CP MAX_ACTIVE_PAYLOAD_LO
	JR NZ,GET_ROW_LEN_LOOP
	LD A,D
	CP MAX_ACTIVE_PAYLOAD_HI
	JR NZ,GET_ROW_LEN_LOOP

GET_ROW_LEN_DONE:
	POP HL				; HL = line start (ACTIVE_LINE_BUF)
	RET

;------------------------------------------------------------------------------
; ADJUST_COL_TO_TARGET: Clamp CUR_COL to active line length matching TARGET_COL
;
; Purpose:
;   Measures active line length and clamps CUR_COL to min(TARGET_COL, length),
;   preserving horizontal column alignment during vertical cursor movement.
;
; Call Usage / Protocol:
;   Called via CALL on vertical cursor movements (Up, Down, PgUp, PgDn).
;
; Inputs:
;   TARGET_COL, CUR_DOC_ROW.
;
; Outputs:
;   CUR_COL clamped to valid range [0..line_length].
;
; Preserves / Modifies:
;   Preserves TARGET_COL, BC, DE; clobbers AF, HL.
;------------------------------------------------------------------------------
ADJUST_COL_TO_TARGET:
	CALL GET_CUR_ROW_LEN		; HL = line start, DE = byte length
	LD BC,0				; BC = character index (0..DE)
	LD HL,0
	LD (ACT_VIS_ACC),HL		; 16-bit visual accumulator = 0

MAP_TARGET_LOOP:
	; Compare BC with DE (character index >= line byte length?)
	LD A,C
	CP E
	JR NZ,MAP_CHECK_LT
	LD A,B
	CP D
	JR Z,SET_TARGET_CHAR_IDX
MAP_CHECK_LT:
	; Check if visual accumulator >= TARGET_COL
	LD HL,(TARGET_COL)
	PUSH DE
	LD DE,(ACT_VIS_ACC)
	LD A,E
	SUB L
	LD A,D
	SBC A,H
	POP DE
	JR NC,SET_TARGET_CHAR_IDX	; ACT_VIS_ACC >= TARGET_COL

	; Peek character at ACTIVE_LINE_BUF + BC
	PUSH DE
	LD HL,ACTIVE_LINE_BUF
	ADD HL,BC
	LD A,(HL)
	POP DE

	CP KEY_TAB
	JR Z,MAP_TARGET_TAB

	; Normal character: increment visual accumulator
	PUSH HL
	LD HL,(ACT_VIS_ACC)
	INC HL
	LD (ACT_VIS_ACC),HL
	POP HL
	INC BC
	JR MAP_TARGET_LOOP

MAP_TARGET_TAB:
	PUSH HL
	LD HL,(ACT_VIS_ACC)
	LD A,L
	CALL GET_TAB_SPACES
	ADD A,L
	LD L,A
	JR NC,MAP_TAB_NO_CY
	INC H
MAP_TAB_NO_CY:
	LD (ACT_VIS_ACC),HL
	POP HL
	INC BC
	JR MAP_TARGET_LOOP

SET_TARGET_CHAR_IDX:
	LD (CUR_COL),BC
	RET

CURSOR_UP:
	LD HL,(CUR_DOC_ROW)
	LD A,H
	OR L
	RET Z				; If at doc row 0, cannot move up

	DEC HL
	LD (CUR_DOC_ROW),HL

	; Check if CUR_DOC_ROW < TOP_DOC_ROW
	LD DE,(TOP_DOC_ROW)
	LD A,H
	CP D
	JR C,C_UP_SCROLL
	JR NZ,CUR_UP_NO_SCROLL
	LD A,L
	CP E
	JR NC,CUR_UP_NO_SCROLL

C_UP_SCROLL:
	LD (TOP_DOC_ROW),HL
	CALL ADJUST_COL_TO_TARGET
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	RET

CUR_UP_NO_SCROLL:
	CALL ADJUST_COL_TO_TARGET
	LD A,(BLOCK_ACTIVE)
	OR A
	RET Z
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	RET

CURSOR_DOWN:
	LD HL,(DOC_TOTAL_LINES)
	LD A,H
	OR L
	RET Z				; 0 lines

	DEC HL			; Max valid doc row = DOC_TOTAL_LINES - 1
	LD DE,(CUR_DOC_ROW)
	; If CUR_DOC_ROW >= max valid row, cannot move down
	LD A,D
	CP H
	JR C,C_DOWN_MOVE
	JR NZ,CUR_DOWN_NO_MOVE
	LD A,E
	CP L
	JR NC,CUR_DOWN_NO_MOVE

C_DOWN_MOVE:
	INC DE
	LD (CUR_DOC_ROW),DE

	; Check if CUR_DOC_ROW - TOP_DOC_ROW >= ACTIVE_ROWS - 1
	LD HL,(CUR_DOC_ROW)
	LD DE,(TOP_DOC_ROW)
	AND A
	SBC HL,DE			; HL = screen row index
	LD A,(ACTIVE_ROWS)
	DEC A
	DEC A			; A = max screen row index (ACTIVE_ROWS - 2)
	CP L
	JR NC,CUR_DOWN_NO_SCROLL	; Screen row <= max, no scroll

	; Scroll down by 1 line
	LD HL,(TOP_DOC_ROW)
	INC HL
	LD (TOP_DOC_ROW),HL
	CALL ADJUST_COL_TO_TARGET
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	RET

CUR_DOWN_NO_SCROLL:
	CALL ADJUST_COL_TO_TARGET
	LD A,(BLOCK_ACTIVE)
	OR A
	RET Z
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	RET

CUR_DOWN_NO_MOVE:
	RET

CURSOR_LEFT:
	LD HL,(CUR_COL)
	LD A,H
	OR L
	JR Z,CURSOR_LEFT_PREV_LINE
	DEC HL
	LD (CUR_COL),HL
	CALL CALC_VISUAL_COL
	; Horizontal movement updates sticky target visual column
	LD (TARGET_COL),HL
	LD A,(BLOCK_ACTIVE)
	CP 1
	RET NZ
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	RET

CURSOR_LEFT_PREV_LINE:
	; Wrap to end of previous line if CUR_DOC_ROW > 0
	LD HL,(CUR_DOC_ROW)
	LD A,H
	OR L
	RET Z				; At line 0, cannot wrap back
	DEC HL
	LD (CUR_DOC_ROW),HL
	CALL CHECKOUT_ACTIVE_LINE

	; Check if scrolled above top of viewport
	LD DE,(TOP_DOC_ROW)
	LD A,H
	CP D
	JR C,CL_SCROLL
	JR NZ,CL_NO_SCROLL
	LD A,L
	CP E
	JR NC,CL_NO_SCROLL

CL_SCROLL:
	LD (TOP_DOC_ROW),HL

CL_NO_SCROLL:
	CALL GET_CUR_ROW_LEN		; DE = prev line length
	LD (CUR_COL),DE
	CALL CALC_VISUAL_COL
	LD (TARGET_COL),HL
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	RET

CURSOR_RIGHT:
	; DE = current line byte length, BC = visual length
	CALL GET_CUR_ROW_LEN
	LD HL,(CUR_COL)
	; Check if CUR_COL >= DE (at or past EOL)
	LD A,L
	SUB E
	LD A,H
	SBC A,D
	JR NC,CURSOR_RIGHT_NEXT_LINE	; If at or past EOL, wrap to next line!

	; Check if visual cursor is already at MAX_LINE_CHARS - 1
	CALL CALC_VISUAL_COL		; HL = visual column
	LD DE,MAX_LINE_CHARS-1
	LD A,L
	CP E
	JR NZ,CR_IN_LINE
	LD A,H
	CP D
	JR Z,CURSOR_RIGHT_NEXT_LINE	; If at column MAX_LINE_CHARS-1, wrap!

CR_IN_LINE:
	LD HL,(CUR_COL)
	INC HL
	LD (CUR_COL),HL
	CALL CALC_VISUAL_COL
	; Horizontal movement updates sticky target visual column
	LD (TARGET_COL),HL
	LD A,(BLOCK_ACTIVE)
	CP 1
	RET NZ
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	RET

CURSOR_RIGHT_NEXT_LINE:
	; Wrap to start of next line if CUR_DOC_ROW + 1 < DOC_TOTAL_LINES
	LD HL,(DOC_TOTAL_LINES)
	LD DE,(CUR_DOC_ROW)
	INC DE				; Next doc row
	LD A,E
	SUB L
	LD A,D
	SBC A,H
	RET NC				; At end of document, cannot wrap

	LD (CUR_DOC_ROW),DE
	CALL CHECKOUT_ACTIVE_LINE
	LD HL,0
	LD (CUR_COL),HL
	LD (TARGET_COL),HL

	; Check if scrolled past bottom of screen window
	LD HL,(CUR_DOC_ROW)
	LD DE,(TOP_DOC_ROW)
	AND A
	SBC HL,DE
	LD A,(ACTIVE_ROWS)
	DEC A
	DEC A
	CP L
	JR NC,CR_NO_SCROLL_BLOCK_CHECK

	LD HL,(TOP_DOC_ROW)
	INC HL
	LD (TOP_DOC_ROW),HL
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	RET

CR_NO_SCROLL_BLOCK_CHECK:
	LD A,(BLOCK_ACTIVE)
	OR A
	RET Z
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	RET

;------------------------------------------------------------------------------
; PAGE_UP: Scroll viewport and cursor up by one screen page
;
; Purpose:
;   Subtracts page step size (ACTIVE_ROWS - 2) from CUR_DOC_ROW and TOP_DOC_ROW,
;   clamping to row 0, and adjusts horizontal column to TARGET_COL.
;
; Call Usage / Protocol:
;   Called via CALL on PgUp key press or ANSI sequence.
;
; Inputs:
;   CUR_DOC_ROW, TOP_DOC_ROW, ACTIVE_ROWS.
;
; Outputs:
;   CUR_DOC_ROW and TOP_DOC_ROW updated; screen flagged for redraw.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
PAGE_UP:
	LD HL,(CUR_DOC_ROW)
	LD A,H
	OR L
	JR NZ,PGUP_CAN_MOVE
	LD HL,(TOP_DOC_ROW)
	LD A,H
	OR L
	RET Z				; Already at line 0, nothing to move

PGUP_CAN_MOVE:
	CALL GET_PAGE_STEP		; DE = PAGE_STEP (ACTIVE_ROWS - 2)
	LD HL,(CUR_DOC_ROW)
	AND A
	SBC HL,DE
	JR NC,PGUP_CUR_OK
	LD HL,0				; Clamped to doc row 0
PGUP_CUR_OK:
	LD (CUR_DOC_ROW),HL

	CALL GET_PAGE_STEP		; DE = PAGE_STEP
	LD HL,(TOP_DOC_ROW)
	AND A
	SBC HL,DE
	JR NC,PGUP_TOP_OK
	LD HL,0				; Clamped to top row 0
PGUP_TOP_OK:
	; Ensure TOP_DOC_ROW <= CUR_DOC_ROW
	LD DE,(CUR_DOC_ROW)
	LD A,H
	CP D
	JR C,PGUP_TOP_SAVED
	JR NZ,PGUP_TOP_ADJUST
	LD A,L
	CP E
	JR C,PGUP_TOP_SAVED
PGUP_TOP_ADJUST:
	EX DE,HL			; HL = CUR_DOC_ROW
PGUP_TOP_SAVED:
	LD (TOP_DOC_ROW),HL

	CALL ADJUST_COL_TO_TARGET
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	RET

;------------------------------------------------------------------------------
; PAGE_DOWN: Scroll viewport and cursor down by one screen page
;
; Purpose:
;   Adds page step size (ACTIVE_ROWS - 2) to CUR_DOC_ROW and TOP_DOC_ROW,
;   clamping to document total lines, and adjusts column to TARGET_COL.
;
; Call Usage / Protocol:
;   Called via CALL on PgDn key press or ANSI sequence.
;
; Inputs:
;   CUR_DOC_ROW, TOP_DOC_ROW, ACTIVE_ROWS, DOC_TOTAL_LINES.
;
; Outputs:
;   CUR_DOC_ROW and TOP_DOC_ROW updated; screen flagged for redraw.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
PAGE_DOWN:
	LD HL,(DOC_TOTAL_LINES)
	LD A,H
	OR L
	RET Z				; 0 lines

	DEC HL			; HL = max_valid_row (DOC_TOTAL_LINES - 1)
	LD DE,(CUR_DOC_ROW)
	; Compare CUR_DOC_ROW (DE) with max_valid_row (HL)
	LD A,D
	CP H
	JR C,PGDN_CAN_MOVE
	JR NZ,PGDN_NO_MOVE
	LD A,E
	CP L
	JR NC,PGDN_NO_MOVE		; Already at or past last line

PGDN_CAN_MOVE:
	PUSH HL				; Save max_valid_row
	CALL GET_PAGE_STEP		; DE = PAGE_STEP
	LD HL,(CUR_DOC_ROW)
	ADD HL,DE			; HL = target CUR_DOC_ROW
	POP DE				; DE = max_valid_row

	; Clamp target CUR_DOC_ROW (HL) to max_valid_row (DE)
	LD A,H
	CP D
	JR C,PGDN_CUR_OK
	JR NZ,PGDN_CUR_CLAMP
	LD A,L
	CP E
	JR C,PGDN_CUR_OK
PGDN_CUR_CLAMP:
	EX DE,HL			; HL = max_valid_row
PGDN_CUR_OK:
	LD (CUR_DOC_ROW),HL		; Save clamped CUR_DOC_ROW

	; Check if all lines fit on screen (DOC_TOTAL_LINES <= ACTIVE_ROWS - 1)
	LD HL,(DOC_TOTAL_LINES)
	LD A,(ACTIVE_ROWS)
	DEC A				; Viewport height (e.g. 23 or 39)
	LD E,A
	LD D,0
	LD A,H
	OR A
	JR NZ,PGDN_CALC_TOP
	LD A,L
	CP E
	JR C,PGDN_KEEP_TOP_ZERO
	JR Z,PGDN_KEEP_TOP_ZERO

PGDN_CALC_TOP:
	; Advance TOP_DOC_ROW by PAGE_STEP
	CALL GET_PAGE_STEP		; DE = PAGE_STEP
	LD HL,(TOP_DOC_ROW)
	ADD HL,DE			; HL = target TOP_DOC_ROW

	; Ensure TOP_DOC_ROW <= CUR_DOC_ROW
	LD DE,(CUR_DOC_ROW)
	LD A,H
	CP D
	JR C,PGDN_TOP_OK
	JR NZ,PGDN_TOP_CLAMP
	LD A,L
	CP E
	JR C,PGDN_TOP_OK
PGDN_TOP_CLAMP:
	EX DE,HL			; HL = CUR_DOC_ROW
PGDN_TOP_OK:
	LD (TOP_DOC_ROW),HL
	JR PGDN_FINISH

PGDN_KEEP_TOP_ZERO:
	LD HL,0
	LD (TOP_DOC_ROW),HL

PGDN_FINISH:
	CALL ADJUST_COL_TO_TARGET
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	RET

PGDN_NO_MOVE:
	RET

;------------------------------------------------------------------------------
; GET_PAGE_STEP: Calculate vertical page scroll step size in lines
;
; Purpose:
;   Computes DE = ACTIVE_ROWS - 2 (e.g. 22 lines in 80x24, 38 lines in 120x40).
;
; Call Usage / Protocol:
;   Called via CALL by PAGE_UP and PAGE_DOWN.
;
; Inputs:
;   ACTIVE_ROWS.
;
; Outputs:
;   DE = 16-bit page step size.
;
; Preserves / Modifies:
;   Preserves BC, HL; returns step in DE; clobbers AF.
;------------------------------------------------------------------------------
GET_PAGE_STEP:
	LD A,(ACTIVE_ROWS)
	DEC A
	DEC A
	LD E,A
	LD D,0
	RET

;------------------------------------------------------------------------------
; JUMP_FILE_TOP: Move cursor to beginning of document (Line 1, Col 0)
;
; Purpose:
;   Sets CUR_DOC_ROW = 0, TOP_DOC_ROW = 0, CUR_COL = 0, TARGET_COL = 0,
;   and flags screen and status bar for re-rendering.
;
; Call Usage / Protocol:
;   Called via CALL on Ctrl+Home or Ctrl+PgUp.
;
; Inputs:
;   None.
;
; Outputs:
;   Cursor relocated to top-left of document.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
JUMP_FILE_TOP:
	LD HL,0
	LD (CUR_DOC_ROW),HL
	LD (TOP_DOC_ROW),HL
	LD (CUR_COL),HL
	LD (TARGET_COL),HL
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	RET

;------------------------------------------------------------------------------
; JUMP_FILE_BOTTOM: Move cursor to end of document (last line, last column)
;
; Purpose:
;   Positions cursor on last document line (DOC_TOTAL_LINES - 1) at end of
;   line and adjusts viewport window so bottom rows are visible.
;
; Call Usage / Protocol:
;   Called via CALL on Ctrl+End or Ctrl+PgDn.
;
; Inputs:
;   DOC_TOTAL_LINES, ACTIVE_ROWS.
;
; Outputs:
;   Cursor located at end of document; viewport adjusted.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
JUMP_FILE_BOTTOM:
	LD HL,(DOC_TOTAL_LINES)
	LD A,H
	OR L
	JR NZ,JUMP_BOT_HAS_LINES
	LD HL,0
	JR JUMP_BOT_SET_CUR

JUMP_BOT_HAS_LINES:
	DEC HL			; HL = max_valid_row (DOC_TOTAL_LINES - 1)
JUMP_BOT_SET_CUR:
	LD (CUR_DOC_ROW),HL
	CALL GET_CUR_ROW_LEN		; DE = byte length, BC = visual length
	LD (CUR_COL),DE
	LD (TARGET_COL),BC

	; Calculate TOP_DOC_ROW so the bottom line is visible at bottom of
	; screen
	; Viewport height: E = ACTIVE_ROWS - 1
	LD HL,(DOC_TOTAL_LINES)
	LD A,(ACTIVE_ROWS)
	DEC A
	LD E,A
	LD D,0

	; Compare DOC_TOTAL_LINES (HL) with viewport height (DE)
	LD A,H
	OR A
	JR NZ,JUMP_BOT_SCROLL_TOP
	LD A,L
	CP E
	JR C,JUMP_BOT_TOP_ZERO
	JR Z,JUMP_BOT_TOP_ZERO

JUMP_BOT_SCROLL_TOP:
	; TOP_DOC_ROW = DOC_TOTAL_LINES - (ACTIVE_ROWS - 1)
	LD HL,(DOC_TOTAL_LINES)
	AND A
	SBC HL,DE
	LD (TOP_DOC_ROW),HL
	JR JUMP_BOT_FINISH

JUMP_BOT_TOP_ZERO:
	LD HL,0
	LD (TOP_DOC_ROW),HL

JUMP_BOT_FINISH:
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	RET

;------------------------------------------------------------------------------
; GOTO_LINE_HL: Navigate directly to 1-indexed document line number in HL
;
; Purpose:
;   Clamps HL to valid range [1..DOC_TOTAL_LINES], converts to 0-indexed row,
;   centers target line within screen viewport, and positions cursor at col 0.
;
; Call Usage / Protocol:
;   Called via CALL from CLI line parser and DO_GOTO_LINE_UI.
;
; Inputs:
;   HL = 1-indexed line number.
;
; Outputs:
;   CUR_DOC_ROW and TOP_DOC_ROW updated; screen flagged for redraw.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
GOTO_LINE_HL:
	; Clamp lower bound: if HL == 0, set HL = 1
	LD A,H
	OR L
	JR NZ,GOTO_NOT_ZERO
	LD HL,1
GOTO_NOT_ZERO:
	LD DE,(DOC_TOTAL_LINES)
	LD A,D
	OR E
	JR NZ,GOTO_HAS_LINES
	; 0 total lines: clamp to 0
	LD HL,0
	LD (CUR_DOC_ROW),HL
	LD (TOP_DOC_ROW),HL
	JR GOTO_SET_COLS

GOTO_HAS_LINES:
	; Compare HL with DE: carry set if HL < DE, Z set if HL == DE
	OR A				; Clear carry
	SBC HL,DE			; HL - DE
	JR NC,GOTO_CLAMP_EOF		; If HL >= DE, clamp to DE
	ADD HL,DE			; HL < DE: restore HL
	JR GOTO_CALC_ROW

GOTO_CLAMP_EOF:
	EX DE,HL			; HL = DOC_TOTAL_LINES

GOTO_CALC_ROW:
	DEC HL				; 0-indexed row = HL - 1
	LD (CUR_DOC_ROW),HL

GOTO_SET_COLS:
	LD HL,0
	LD (CUR_COL),HL
	LD (TARGET_COL),HL

	; Calculate TOP_DOC_ROW for centering:
	; Viewport lines: V = ACTIVE_ROWS - 1
	; Half-height: H = V / 2
	LD HL,(CUR_DOC_ROW)
	LD A,(ACTIVE_ROWS)
	DEC A				; V
	SRL A				; H = V / 2
	LD E,A
	LD D,0				; DE = H

	OR A
	SBC HL,DE			; HL = CUR_DOC_ROW - H
	JR C,GOTO_SET_TOP_ZERO		; If CUR_DOC_ROW < H, TOP = 0
	JR Z,GOTO_SET_TOP_ZERO		; If CUR_DOC_ROW == H, TOP = 0

	; Proposed TOP is in HL (CUR_DOC_ROW - H)
	; Calculate MAX_TOP = DOC_TOTAL_LINES - V
	PUSH HL				; Save proposed TOP
	LD HL,(DOC_TOTAL_LINES)
	LD A,(ACTIVE_ROWS)
	DEC A				; V
	LD E,A
	LD D,0				; DE = V
	OR A
	SBC HL,DE			; HL = DOC_TOTAL_LINES - V
	JR C,GOTO_POP_TOP_ZERO		; If DOC_TOTAL_LINES < V -> TOP = 0
	JR Z,GOTO_POP_TOP_ZERO		; If DOC_TOTAL_LINES == V -> TOP = 0

	; HL is MAX_TOP, proposed TOP is on stack
	EX DE,HL			; DE = MAX_TOP
	POP HL				; HL = proposed TOP
	OR A
	SBC HL,DE			; proposed - MAX_TOP
	JR NC,GOTO_SET_MAX_TOP		; If proposed >= MAX_TOP, use MAX_TOP
	ADD HL,DE			; Restore proposed TOP
	LD (TOP_DOC_ROW),HL
	JR GOTO_FINISH

GOTO_POP_TOP_ZERO:
	POP HL				; Discard proposed TOP
GOTO_SET_TOP_ZERO:
	LD HL,0
	LD (TOP_DOC_ROW),HL
	JR GOTO_FINISH

GOTO_SET_MAX_TOP:
	LD (TOP_DOC_ROW),DE

GOTO_FINISH:
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	LD (NEED_STATUS_RENDER),A
	RET

;------------------------------------------------------------------------------
; PARSE_DEC_WORD: Parse 16-bit unsigned decimal integer from ASCII string
;
; Purpose:
;   Iterates through ASCII characters starting at HL, accumulating decimal
;   digits into 16-bit register DE until encountering a non-digit character.
;
; Call Usage / Protocol:
;   Called via CALL by command-line parsers and modal input dialogs.
;
; Inputs:
;   HL = Pointer to string buffer containing decimal ASCII digits.
;
; Outputs:
;   DE = 16-bit unsigned parsed value; HL points to first non-digit char.
;
; Preserves / Modifies:
;   Preserves BC; returns value in DE; clobbers AF.
;------------------------------------------------------------------------------
PARSE_DEC_WORD:
	LD DE,0
PARSE_DEC_LOOP:
	LD A,(HL)
	OR A
	RET Z
	CP '0'
	RET C
	CP '9'+1
	RET NC
	SUB '0'
	PUSH HL
	LD H,D
	LD L,E
	ADD HL,HL		; * 2
	ADD HL,HL		; * 4
	ADD HL,DE		; * 5
	ADD HL,HL		; * 10
	LD E,A
	LD D,0
	ADD HL,DE		; * 10 + digit
	EX DE,HL
	POP HL
	INC HL
	JR PARSE_DEC_LOOP

;------------------------------------------------------------------------------
; DO_GOTO_LINE_UI: Centered modal pop-up dialog for Goto Line command
;
; Purpose:
;   Displays 50x7 centered modal query dialog prompting user for line number.
;   Reads numeric input with editing (Backspace, ESC), parses line number,
;   and navigates to target line.
;
; Call Usage / Protocol:
;   Called via CALL from MAIN_LOOP on Ctrl+L.
;
; Inputs:
;   ACTIVE_COLS, ACTIVE_ROWS.
;
; Outputs:
;   Navigates to line if confirmed; restores editor view.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_GOTO_LINE_UI:
	CALL CANCEL_BLOCK

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

	CALL DRAW_GOTO_POPUP_BODY

	; Clear buffer
	LD HL,GOTO_LINE_BUF
	LD (HL),0
	LD B,0				; B = digit count (0..5)

GOTO_UI_LOOP:
	CALL GET_KEY

	; ESC or escape sequence (e.g. cursor keys, PgUp, PgDn)
	CP KEY_ESC
	JR Z,GOTO_UI_CHECK_ESC

	; Enter -> confirm goto line
	CP KEY_ENTER
	JP Z,GOTO_UI_ENTER

	; Backspace / Delete
	CP KEY_BACKSPACE
	JR Z,GOTO_UI_BS
	CP KEY_DEL
	JR Z,GOTO_UI_BS

	; Check if digit '0'..'9'
	CP '0'
	JR C,GOTO_UI_LOOP
	CP '9'+1
	JR NC,GOTO_UI_LOOP

	; Check max digits (up to 5 digits)
	LD C,A				; Save digit in C
	LD A,B
	CP 5
	JR NC,GOTO_UI_LOOP

	; Append digit to buffer
	LD HL,GOTO_LINE_BUF
	LD E,B
	LD D,0
	ADD HL,DE
	LD (HL),C
	INC HL
	LD (HL),0			; Null-terminate
	INC B

	; Echo digit on screen
	LD A,C
	CALL PUTC
	JR GOTO_UI_LOOP

GOTO_UI_BS:
	LD A,B
	OR A
	JR Z,GOTO_UI_LOOP		; Nothing to backspace

	DEC B
	LD HL,GOTO_LINE_BUF
	LD E,B
	LD D,0
	ADD HL,DE
	LD (HL),0			; Null-terminate at new length

	; Visual backspace: \x08 \x20 \x08
	LD A,008H
	CALL PUTC
	LD A,' '
	CALL PUTC
	LD A,008H
	CALL PUTC
	JR GOTO_UI_LOOP

GOTO_UI_CHECK_ESC:
	; Check if a character follows ESC within a short timeout
	IFDEF TARGET_NEXT
	LD BC,ESC_TIMEOUT_LOOPS
	ELSE
	PUSH BC
	LD BC,ESC_TIMEOUT_LOOPS
	ENDIF
GOTO_WAIT_ESC:
	CALL CHECK_KEY_READY
	JR NZ,GOTO_GOT_ESC_SEQ
	DEC BC
	LD A,B
	OR C
	JR NZ,GOTO_WAIT_ESC

	; Standalone ESC key: cancel prompt without moving cursor
	IFNDEF TARGET_NEXT
	POP BC
	ENDIF
	JR GOTO_UI_CANCEL

GOTO_GOT_ESC_SEQ:
	IFDEF TARGET_NEXT
	CALL DRAIN_ESCAPE_SEQUENCE
	JP GOTO_UI_LOOP
	ELSE
	; Unexpected escape sequence (e.g. cursor keys, PgUp, PgDn)
	CALL DRAIN_ESC_SEQUENCE
	POP BC
	JP GOTO_UI_LOOP
	ENDIF

GOTO_UI_ENTER:
	; If empty (user just pressed enter with no digits), treat as cancel
	LD A,B
	OR A
	JR Z,GOTO_UI_CANCEL

	; Parse decimal number from GOTO_LINE_BUF into DE
	LD HL,GOTO_LINE_BUF
	CALL PARSE_DEC_WORD		; DE = line number
	EX DE,HL			; HL = line number
	CALL GOTO_LINE_HL

	; Redraw editor and status bar smoothly without full screen clear flash
GOTO_UI_CANCEL:
	JP RENDER_SCREEN

DRAW_GOTO_POPUP_BODY:
	CALL TERM_HIDE_CURSOR

	; Line 1: Border
	CALL POPUP_PRINT_BORDER

	; Line 2: Title
	CALL POPUP_LOCATE_NEXT
	LD DE,STR_GOTO_POPUP_TITLE
	CALL PRINT_STR

	; Line 3: Border
	CALL POPUP_PRINT_BORDER

	; Line 4: Description
	CALL POPUP_LOCATE_NEXT
	LD DE,STR_GOTO_POPUP_MSG
	CALL PRINT_STR

	; Line 5: Prompt and input field
	CALL POPUP_LOCATE_NEXT
	LD DE,STR_GOTO_POPUP_PROMPT
	CALL PRINT_STR
	; Pad 5 spaces for input field
	LD C,5
DGP_PAD_LOOP:
	LD A,' '
	CALL PUTC
	DEC C
	JR NZ,DGP_PAD_LOOP
	LD DE,STR_GOTO_POPUP_BOX_CLOSE
	CALL PRINT_STR

	; Line 6: Keys
	CALL POPUP_LOCATE_NEXT
	LD DE,STR_GOTO_POPUP_KEYS
	CALL PRINT_STR

	; Line 7: Border
	CALL POPUP_PRINT_BORDER

	; Position cursor inside popup box at (POPUP_START_ROW + 4, POPUP_COL +
	; 28)
	LD A,(POPUP_START_ROW)
	ADD A,4
	LD H,A
	LD A,(POPUP_COL)
	ADD A,28
	LD L,A
	CALL LOCATE_RC
	CALL TERM_SHOW_CURSOR
	RET


INCLUDE "core/search.asm"

;------------------------------------------------------------------------------
; Character Insertion at (CUR_DOC_ROW, CUR_COL)
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; DO_CHAR_INSERT: Insert single ASCII character into active line at cursor
;
; Purpose:
;   Inserts character in register A into ACTIVE_LINE_BUF at CUR_COL.
;   If in insert mode, shifts trailing characters right (enforcing max 120
;   chars). If cursor is past line end, pads with spaces before appending.
;   Advances cursor column and flags line dirty.
;
; Call Usage / Protocol:
;   Primary character typing handler called from MAIN_LOOP.
;
; Inputs:
;   A = Character byte to insert, CUR_COL, INSERT_MODE.
;
; Outputs:
;   Character inserted; CUR_COL incremented; ACTIVE_LINE_DIRTY = 1.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_CHAR_INSERT:
	LD (CHAR_INSERT_TEMP),A		; Save character to insert

	; Ensure DOC_TOTAL_LINES >= CUR_DOC_ROW + 1
	LD HL,(DOC_TOTAL_LINES)
	LD DE,(CUR_DOC_ROW)
	LD A,E
	CP L
	LD A,D
	SBC A,H
	JR C,ROW_IN_BOUNDS
	INC DE
	LD (DOC_TOTAL_LINES),DE

ROW_IN_BOUNDS:
	CALL CHECKOUT_ACTIVE_LINE	; Ensures line is in ACTIVE_LINE_BUF
	; HL = ACTIVE_LINE_BUF, DE = len, BC = visual len
	CALL GET_CUR_ROW_LEN

	; 1. Check byte capacity against MAX_ACTIVE_LINE_STRIDE - 2 (1022)
	LD HL,MAX_ACTIVE_LINE_STRIDE-2
	LD A,E
	SUB L
	LD A,D
	SBC A,H
	JR NC,CHECK_BYTE_CAP_REPLACE	; DE >= 1022
	JR CHECK_VISUAL_LIMIT

CHECK_BYTE_CAP_REPLACE:
	LD A,(INSERT_MODE)
	OR A
	RET NZ				; Insert mode: buffer full
	LD HL,(CUR_COL)
	LD A,L
	SUB E
	LD A,H
	SBC A,D
	RET NC	; In overwrite mode at or past EOL: cannot append when full!

CHECK_VISUAL_LIMIT:
	; 2. Check visual line length limit (MAX_INPUT_LINE_CHARS = 1000)
	LD HL,MAX_INPUT_LINE_CHARS
	LD A,C
	SUB L
	LD A,B
	SBC A,H
	JR NC,CHECK_AT_EOL_REPLACE	; BC >= 1000

	; If inserting a Tab, check if tab expansion would push visual length >
	; MAX_INPUT_LINE_CHARS
	LD A,(CHAR_INSERT_TEMP)
	CP KEY_TAB
	JR NZ,LINE_LEN_OK
	CALL CALC_VISUAL_COL		; HL = visual col at CUR_COL
	LD A,L
	CALL GET_TAB_SPACES
	DEC A				; minus 1 for replaced char
	LD E,A
	LD D,0
	ADD HL,DE			; projected visual length
	LD DE,MAX_INPUT_LINE_CHARS
	LD A,L
	SUB E
	LD A,H
	SBC A,D
	RET NC				; Tab would exceed limit!
	JR LINE_LEN_OK

CHECK_AT_EOL_REPLACE:
	LD A,(INSERT_MODE)
	OR A
	RET NZ				; Insert mode: cannot insert when full!
	LD A,(CHAR_INSERT_TEMP)
	CP KEY_TAB
	RET Z				; Tab might expand: reject when full!
	LD HL,(CUR_COL)
	LD A,L
	SUB E
	LD A,H
	SBC A,D
	RET NC			; At or past EOL: cannot append when full!
	JR LINE_LEN_OK		; Overwrite existing char in full line: allowed!

LINE_LEN_OK:
	LD A,1
	LD (ACTIVE_LINE_DIRTY),A
	LD (DOC_MODIFIED),A
	LD (NEED_LINE_RENDER),A

	; 4. Compare CUR_COL with line length (DE)
	LD HL,(CUR_COL)
	LD A,L
	SUB E
	LD A,H
	SBC A,D
	JR NC,DO_PAD_AND_APPEND		; CUR_COL >= DE: pad spaces and append

	; Check Insert vs Overwrite mode
	LD A,(INSERT_MODE)
	OR A
	JR NZ,DO_SHIFT_AND_INSERT

	; Overwrite mode: replace character at ACTIVE_LINE_BUF + CUR_COL in
	; place!
	LD HL,ACTIVE_LINE_BUF
	LD DE,(CUR_COL)
	ADD HL,DE
	LD A,(CHAR_INSERT_TEMP)
	LD (HL),A
	JR ADVANCE_INSERT_CURSOR

DO_SHIFT_AND_INSERT:
	; 5. If CUR_COL < length: shift characters from (ACTIVE_LINE_BUF + DE)
	; down to (ACTIVE_LINE_BUF + CUR_COL)
	PUSH DE				; Save line length DE
	LD HL,ACTIVE_LINE_BUF
	ADD HL,DE			; HL = ACTIVE_LINE_BUF + DE
	LD D,H
	LD E,L
	INC DE				; DE = ACTIVE_LINE_BUF + DE + 1

	POP BC				; BC = line length
	LD HL,(CUR_COL)
	LD A,C
	SUB L
	LD C,A
	LD A,B
	SBC A,H
	LD B,A
	INC BC				; BC = length - CUR_COL + 1

	LD H,D
	LD L,E
	DEC HL				; HL = ACTIVE_LINE_BUF + length

	LDDR
	XOR A
	LD (DE),A		; Guarantee null terminator at new end of line

	; Now insert character at ACTIVE_LINE_BUF + CUR_COL
	LD HL,ACTIVE_LINE_BUF
	LD DE,(CUR_COL)
	ADD HL,DE
	LD A,(CHAR_INSERT_TEMP)
	LD (HL),A
	JR ADVANCE_INSERT_CURSOR

DO_PAD_AND_APPEND:
	; Pad from ACTIVE_LINE_BUF + DE up to ACTIVE_LINE_BUF + CUR_COL with
	; spaces
	LD HL,ACTIVE_LINE_BUF
	ADD HL,DE			; HL = ACTIVE_LINE_BUF + DE (at old EOL)
	PUSH HL				; Save old EOL pointer
PAD_SPACES_LOOP:
	LD HL,(CUR_COL)
	LD A,E
	CP L
	JR NZ,PAD_CONTINUE
	LD A,D
	CP H
	JR Z,PAD_SPACES_DONE
PAD_CONTINUE:
	POP HL
	LD (HL),' '
	INC HL
	PUSH HL
	INC DE
	JR PAD_SPACES_LOOP

PAD_SPACES_DONE:
	POP HL
	; HL is now at ACTIVE_LINE_BUF + CUR_COL
	LD A,(CHAR_INSERT_TEMP)
	LD (HL),A
	INC HL
	XOR A
	LD (HL),A			; Null terminate new end of line

ADVANCE_INSERT_CURSOR:
	CALL CALC_VISUAL_COL		; HL = visual col before advance
	LD DE,MAX_INPUT_LINE_CHARS-1	; 999
	LD A,L
	CP E
	JR NZ,AIC_CHECK_BYTE
	LD A,H
	CP D
	RET Z			; At column 999, do not advance cursor further!

AIC_CHECK_BYTE:
	LD HL,(CUR_COL)
	LD DE,MAX_ACTIVE_LINE_STRIDE-2
	LD A,L
	SUB E
	LD A,H
	SBC A,D
	RET NC

	INC HL
	LD (CUR_COL),HL
	CALL CALC_VISUAL_COL
	LD (TARGET_COL),HL	; Sync sticky target visual column on typing
	RET

;------------------------------------------------------------------------------
; Character Deletion at (CUR_DOC_ROW, CUR_COL) - Backspace Handling
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; DO_DELETE_CHAR: Delete character immediately left of cursor (Backspace key)
;
; Purpose:
;   If CUR_COL > 0, shifts all characters starting at CUR_COL left by 1 byte
;   in ACTIVE_LINE_BUF, decrements CUR_COL, and marks dirty. If CUR_COL == 0,
;   dispatches to DO_DELETE_BLANK_LINE to join with previous row.
;
; Call Usage / Protocol:
;   Called via CALL from MAIN_LOOP on Backspace key (0x08 / 0x7F).
;
; Inputs:
;   CUR_COL, CUR_DOC_ROW, ACTIVE_LINE_BUF.
;
; Outputs:
;   Character deleted; CUR_COL decremented; ACTIVE_LINE_DIRTY = 1.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_DELETE_CHAR:
	LD HL,(CUR_COL)
	LD A,H
	OR L
	RET Z				; At column 0, nothing to delete on line

	DEC HL
	LD (CUR_COL),HL
	CALL CALC_VISUAL_COL
	LD (TARGET_COL),HL	; Sync sticky target visual column on Backspace

	LD A,1
	LD (ACTIVE_LINE_DIRTY),A
	LD (DOC_MODIFIED),A
	LD (NEED_LINE_RENDER),A

	CALL CHECKOUT_ACTIVE_LINE	; HL = ACTIVE_LINE_BUF
	LD DE,(CUR_COL)
	ADD HL,DE			; HL = character to delete

	; Shift characters left from HL+1 into HL until null or end of line
CHAR_SHIFT_LEFT_LOOP:
	INC HL
	LD A,(HL)
	DEC HL
	LD (HL),A
	OR A
	RET Z
	INC HL
	JR CHAR_SHIFT_LEFT_LOOP

;------------------------------------------------------------------------------
; Forward Character Deletion at (CUR_DOC_ROW, CUR_COL) - Delete Key Handling
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; DO_DELETE_FORWARD: Delete character under cursor (Delete key)
;
; Purpose:
;   If cursor is before end of line, shifts trailing characters left by 1 byte
;   over current character. If cursor is at or past end of line, joins current
;   line with subsequent document line.
;
; Call Usage / Protocol:
;   Called via CALL from MAIN_LOOP on Delete key / Ctrl+G.
;
; Inputs:
;   CUR_COL, CUR_DOC_ROW, ACTIVE_LINE_BUF.
;
; Outputs:
;   Character deleted or lines joined; ACTIVE_LINE_DIRTY = 1.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_DELETE_FORWARD:
	CALL CHECKOUT_ACTIVE_LINE	; HL = ACTIVE_LINE_BUF
	LD DE,(CUR_COL)
	ADD HL,DE			; HL = character under cursor

	LD A,(HL)
	OR A
	; At end of line: join NEXT line into current line!
	JR Z,DO_DEL_FWD_JOIN_NEXT

	LD A,1
	LD (ACTIVE_LINE_DIRTY),A
	LD (DOC_MODIFIED),A
	LD (NEED_LINE_RENDER),A

	; Shift characters left from HL+1 into HL until null
DEL_FWD_SHIFT_LOOP:
	INC HL
	LD A,(HL)
	DEC HL
	LD (HL),A
	OR A
	JR Z,DEL_FWD_DONE
	INC HL
	JR DEL_FWD_SHIFT_LOOP

DEL_FWD_DONE:
	LD A,1
	LD (NEED_LINE_RENDER),A
	RET

DO_DEL_FWD_JOIN_NEXT:
	; Check if CUR_DOC_ROW + 1 < DOC_TOTAL_LINES
	LD HL,(DOC_TOTAL_LINES)
	LD DE,(CUR_DOC_ROW)
	INC DE
	LD A,D
	CP H
	JR C,DO_DEL_JOIN_OK
	JR NZ,DO_DEL_JOIN_FAIL
	LD A,E
	CP L
	JR NC,DO_DEL_JOIN_FAIL

DO_DEL_JOIN_OK:
	; Join CUR_DOC_ROW and CUR_DOC_ROW + 1
	LD BC,(CUR_DOC_ROW)		; BC = upper line (CUR_DOC_ROW)
	CALL JOIN_TWO_LINES
	JR C,DO_DEL_JOIN_FAIL		; If combined length > 1000, reject

	; Join succeeded: cursor remains at CUR_DOC_ROW, CUR_COL
	CALL CHECKOUT_ACTIVE_LINE
	CALL CALC_VISUAL_COL
	LD (TARGET_COL),HL
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	RET

DO_DEL_JOIN_FAIL:
	RET

;------------------------------------------------------------------------------
; Backspace at Column 0 Handling: Joins current line with previous line
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; DO_DELETE_BLANK_LINE: Handle Backspace at Column 0 by joining lines
;
; Purpose:
;   When Backspace is pressed at column 0, joins current line CUR_DOC_ROW
;   with previous line CUR_DOC_ROW - 1, moving cursor to join position.
;
; Call Usage / Protocol:
;   Called via CALL from DO_DELETE_CHAR when CUR_COL == 0.
;
; Inputs:
;   CUR_DOC_ROW.
;
; Outputs:
;   Lines joined; cursor placed at join point; line table updated.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_DELETE_BLANK_LINE:
	LD HL,(CUR_DOC_ROW)
	LD A,H
	OR L
	JR NZ,DO_BS_JOIN_PREV

	; At Row 0, Col 0: check if line 0 is empty and DOC_TOTAL_LINES > 1
	LD HL,(DOC_TOTAL_LINES)
	LD A,H
	OR A
	JR NZ,DO_BS_ROW0_CHECK
	LD A,L
	CP 2
	JR C,DO_BS_ROW0_DONE		; Only 1 line total, nothing to delete

DO_BS_ROW0_CHECK:
	; Check if Line 0 is empty
	LD BC,0
	CALL ENSURE_CACHE_WINDOW
	LD A,(HL)
	OR A
	JR NZ,DO_BS_ROW0_DONE		; Line 0 has text, do not delete

	; Delete empty Line 0
	CALL FLUSH_DIRTY_CACHE
	LD A,1
	LD (DOC_MODIFIED),A

	; 1. Free Line 0's slot chain
	LD BC,0
	CALL GET_LINE_SLOT		; HL = Line 0's slot ID
	CALL FREE_LINE_CHAIN

	; 2. Decrement DOC_TOTAL_LINES
	LD HL,(DOC_TOTAL_LINES)
	DEC HL
	LD (DOC_TOTAL_LINES),HL

	; 3. Shift line slots from index 1 down to index 0
	LD A,H
	OR L
	JR Z,DO_BS_ROW0_NO_SHIFT
	LD B,H
	LD C,L		; BC = count of lines to shift (new DOC_TOTAL_LINES)
	LD DE,0				; Destination line = 0
	LD HL,1				; Source line = 1
	CALL SHIFT_LINE_SLOTS_UP
DO_BS_ROW0_NO_SHIFT:

	CALL RELOAD_CACHE_WINDOW_FORCE
	LD A,1
	LD (NEED_SCREEN_RENDER),A
DO_BS_ROW0_DONE:
	RET

DO_BS_JOIN_PREV:
	; Join CUR_DOC_ROW with previous line (CUR_DOC_ROW - 1)
	LD HL,(CUR_DOC_ROW)
	DEC HL
	LD B,H
	LD C,L			; BC = upper line index (CUR_DOC_ROW - 1)
	CALL JOIN_TWO_LINES
	RET C		; If Carry set (combined length > 1000), do nothing

	; Join succeeded: HL = join column offset (original len of previous
	; line)
	LD (CUR_COL),HL			; Move cursor to join point
	LD HL,(CUR_DOC_ROW)
	DEC HL
	LD (CUR_DOC_ROW),HL		; Move cursor to upper line
	CALL CHECKOUT_ACTIVE_LINE
	CALL CALC_VISUAL_COL
	LD (TARGET_COL),HL

	; Check if CUR_DOC_ROW < TOP_DOC_ROW
	LD DE,(TOP_DOC_ROW)
	LD A,H
	CP D
	JR C,DO_BS_JOIN_SCROLL_UP
	JR NZ,DO_BS_JOIN_RENDER
	LD A,L
	CP E
	JR NC,DO_BS_JOIN_RENDER
DO_BS_JOIN_SCROLL_UP:
	LD (TOP_DOC_ROW),HL

DO_BS_JOIN_RENDER:
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	RET

;------------------------------------------------------------------------------
; JOIN_TWO_LINES: Concatenate document line BC with preceding line BC-1
;
; Purpose:
;   Appends text of line BC to line BC-1 if combined length <= 120 characters.
;   Frees line BC's slots, shifts subsequent line table entries upward,
;   decrements DOC_TOTAL_LINES, and marks document modified.
;
; Call Usage / Protocol:
;   Called via CALL by DO_DELETE_FORWARD and DO_DELETE_BLANK_LINE.
;
; Inputs:
;   BC = 16-bit document line index of lower line to merge.
;
; Outputs:
;   Carry = 0 on success, HL = join column; Carry = 1 if merged length > 120.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
JOIN_TWO_LINES:
	LD (JOIN_DOC_LINE),BC		; Save upper document line index

	; Check if DOC_TOTAL_LINES >= 2
	LD HL,(DOC_TOTAL_LINES)
	LD A,H
	OR A
	JR NZ,JOIN_DOC_LEN_OK
	LD A,L
	CP 2
	JR NC,JOIN_DOC_LEN_OK
	SCF
	RET

JOIN_DOC_LEN_OK:
	CALL COMMIT_ACTIVE_LINE
	CALL FLUSH_DIRTY_CACHE

	; 1. Read upper line at (JOIN_DOC_LINE) into ACTIVE_LINE_BUF
	LD BC,(JOIN_DOC_LINE)
	LD DE,ACTIVE_LINE_BUF
	LD HL,MAX_ACTIVE_LINE_STRIDE-2
	CALL READ_FAR_LINE_MAX

	; Measure upper line length -> DE = len_1
	LD HL,ACTIVE_LINE_BUF
	LD DE,0
JOIN_MEASURE_L1:
	LD A,(HL)
	OR A
	JR Z,JOIN_MEASURE_L1_DONE
	INC HL
	INC DE
	JR JOIN_MEASURE_L1

JOIN_MEASURE_L1_DONE:
	LD (JOIN_COL_SAVED),DE		; Save len_1 (16-bit)

	; 2. Read lower line at (JOIN_DOC_LINE + 1) into SPLIT_LINE_TEMP
	LD BC,(JOIN_DOC_LINE)
	INC BC
	LD DE,SPLIT_LINE_TEMP
	LD HL,MAX_ACTIVE_LINE_STRIDE-2
	CALL READ_FAR_LINE_MAX

	; Measure lower line length -> BC = len_2
	LD HL,SPLIT_LINE_TEMP
	LD BC,0
JOIN_MEASURE_L2:
	LD A,(HL)
	OR A
	JR Z,JOIN_MEASURE_L2_DONE
	INC HL
	INC BC
	JR JOIN_MEASURE_L2

JOIN_MEASURE_L2_DONE:
	; Check if len_1 + len_2 <= MAX_INPUT_LINE_CHARS (1000)
	LD HL,(JOIN_COL_SAVED)
	ADD HL,BC			; HL = len_1 + len_2
	LD DE,MAX_INPUT_LINE_CHARS
	LD A,L
	SUB E
	LD A,H
	SBC A,D
	JR C,JOIN_CAPACITY_OK
	JR Z,JOIN_CAPACITY_OK

	; Too long to join!
	SCF
	RET

JOIN_CAPACITY_OK:
	; 3. Append lower line (SPLIT_LINE_TEMP) to upper line (ACTIVE_LINE_BUF
	; + len_1)
	LD HL,ACTIVE_LINE_BUF
	LD DE,(JOIN_COL_SAVED)
	ADD HL,DE		; HL = pointer to null in ACTIVE_LINE_BUF
	LD DE,SPLIT_LINE_TEMP
JOIN_APPEND_LOOP:
	LD A,(DE)
	LD (HL),A
	INC DE
	INC HL
	OR A
	JR NZ,JOIN_APPEND_LOOP

	; 4. Write merged line back to Far RAM at (JOIN_DOC_LINE)
	LD BC,(JOIN_DOC_LINE)
	LD HL,ACTIVE_LINE_BUF
	CALL WRITE_FAR_LINE

	; 5. Free lower line's slot chain (JOIN_DOC_LINE + 1)
	LD HL,(JOIN_DOC_LINE)
	INC HL				; HL = lower line index (P)
	LD B,H
	LD C,L
	CALL GET_LINE_SLOT		; HL = freed slot ID
	CALL FREE_LINE_CHAIN

	; 6. Decrement DOC_TOTAL_LINES
	LD HL,(DOC_TOTAL_LINES)
	DEC HL
	LD (DOC_TOTAL_LINES),HL

	; 7. Shift line slots from JOIN_DOC_LINE + 2 upwards to JOIN_DOC_LINE +
	; 1
	; Number of entries to shift: W = DOC_TOTAL_LINES - (JOIN_DOC_LINE + 1)
	LD HL,(DOC_TOTAL_LINES)		; New total lines
	LD DE,(JOIN_DOC_LINE)
	INC DE				; DE = P = JOIN_DOC_LINE + 1
	AND A
	SBC HL,DE			; HL = W = DOC_TOTAL_LINES - P
	JR Z,JOIN_SHIFT_DONE
	JR C,JOIN_SHIFT_DONE

	LD B,H
	LD C,L				; BC = W
	LD HL,(JOIN_DOC_LINE)
	INC HL
	INC HL				; HL = source line = P + 1
	; DE is already destination line = P
	CALL SHIFT_LINE_SLOTS_UP

JOIN_SHIFT_DONE:
	CALL INVALIDATE_ACTIVE_LINE
	CALL RELOAD_CACHE_WINDOW_FORCE
	LD A,1
	LD (DOC_MODIFIED),A

	LD HL,(JOIN_COL_SAVED)		; HL = join column offset
	OR A				; Clear Carry = success!
	RET

;------------------------------------------------------------------------------
; Line Insertion & Splitting at (CUR_DOC_ROW, CUR_COL) - Enter Key Handling
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; DO_INSERT_LINE: Split active line at cursor on Enter key press
;
; Purpose:
;   Splits text in ACTIVE_LINE_BUF at CUR_COL into two separate lines.
;   Truncates current line at CUR_COL, allocates fresh Far RAM slot for new
;   line, shifts subsequent line table entries down by 1, writes trailing text
;   to new line, increments DOC_TOTAL_LINES, and advances cursor to next row.
;
; Call Usage / Protocol:
;   Called via CALL from MAIN_LOOP on Enter key (0x0D).
;
; Inputs:
;   CUR_DOC_ROW, CUR_COL, ACTIVE_LINE_BUF.
;
; Outputs:
;   Line split into two; CUR_DOC_ROW incremented; CUR_COL = 0; DOC_MODIFIED = 1.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_INSERT_LINE:
	; Check max document lines (MAX_DOC_LINES_LIMIT)
	LD HL,(DOC_TOTAL_LINES)
	LD DE,(MAX_DOC_LINES_LIMIT)
	OR A
	SBC HL,DE
	JR NC,INS_FAIL
	JR INS_CAP_OK

INS_FAIL:
	CALL SET_OOM_STATUS
	SCF
	RET

INS_CAP_OK:
	; Allocate slot for new line
	CALL ALLOC_SLOT			; HL = new_slot_id (Carry = 1 on error)
	JR C,INS_FAIL
	PUSH HL				; Save new_slot_id

	; Ensure current line is checked out in ACTIVE_LINE_BUF
	CALL CHECKOUT_ACTIVE_LINE

	; Split ACTIVE_LINE_BUF at CUR_COL:
	; Copy text from split point into SPLIT_LINE_TEMP
	LD HL,ACTIVE_LINE_BUF
	LD DE,(CUR_COL)
	ADD HL,DE			; HL = split point in ACTIVE_LINE_BUF
	LD DE,SPLIT_LINE_TEMP
SPLIT_COPY_LOOP:
	LD A,(HL)
	LD (DE),A
	LD (HL),0			; Truncate current line at split point
	INC HL
	INC DE
	OR A
	JR NZ,SPLIT_COPY_LOOP

	; Truncated prefix is in ACTIVE_LINE_BUF. Mark dirty and commit it!
	LD A,1
	LD (ACTIVE_LINE_DIRTY),A
	LD (DOC_MODIFIED),A
	CALL COMMIT_ACTIVE_LINE

	; Shift line slots downwards from CUR_DOC_ROW + 1 to DOC_TOTAL_LINES - 1
	; Number of entries to shift: W = DOC_TOTAL_LINES - (CUR_DOC_ROW + 1)
	LD HL,(DOC_TOTAL_LINES)
	LD DE,(CUR_DOC_ROW)
	INC DE				; DE = P = CUR_DOC_ROW + 1
	AND A
	SBC HL,DE			; HL = W = DOC_TOTAL_LINES - P
	JR Z,NO_SLOT_SHIFT_DOWN
	JR C,NO_SLOT_SHIFT_DOWN

	LD B,H
	LD C,L				; BC = W
	LD HL,(CUR_DOC_ROW)
	INC HL				; HL = source line = CUR_DOC_ROW + 1
	LD DE,(CUR_DOC_ROW)
	INC DE
	INC DE				; DE = dest line = CUR_DOC_ROW + 2
	CALL SHIFT_LINE_SLOTS_DOWN

NO_SLOT_SHIFT_DOWN:
	; Store new_slot_id into line table at CUR_DOC_ROW + 1
	POP DE				; DE = new_slot_id
	LD HL,(CUR_DOC_ROW)
	INC HL
	LD B,H
	LD C,L				; BC = CUR_DOC_ROW + 1
	EX DE,HL			; HL = new_slot_id
	CALL SET_LINE_SLOT

	; Write split remainder (SPLIT_LINE_TEMP) to CUR_DOC_ROW + 1
	LD HL,(CUR_DOC_ROW)
	INC HL
	LD B,H
	LD C,L				; BC = CUR_DOC_ROW + 1
	LD HL,SPLIT_LINE_TEMP
	CALL WRITE_FAR_LINE

	; Increment DOC_TOTAL_LINES
	LD HL,(DOC_TOTAL_LINES)
	INC HL
	LD (DOC_TOTAL_LINES),HL

	; Advance cursor to CUR_DOC_ROW + 1, Col 0
	LD HL,(CUR_DOC_ROW)
	INC HL
	LD (CUR_DOC_ROW),HL
	LD HL,0
	LD (CUR_COL),HL
	LD (TARGET_COL),HL

	; Invalidate active line and check out new CUR_DOC_ROW
	CALL INVALIDATE_ACTIVE_LINE
	CALL CHECKOUT_ACTIVE_LINE
	CALL RELOAD_CACHE_WINDOW_FORCE

	; Check if scrolled past bottom of screen window
	LD HL,(CUR_DOC_ROW)
	LD DE,(TOP_DOC_ROW)
	AND A
	SBC HL,DE
	LD A,(ACTIVE_ROWS)
	DEC A
	DEC A
	CP L
	JR NC,SPLIT_NO_SCROLL

	LD HL,(TOP_DOC_ROW)
	INC HL
	LD (TOP_DOC_ROW),HL

SPLIT_NO_SCROLL:
	CALL RELOAD_CACHE_WINDOW_FORCE
	LD A,1
	LD (NEED_SCREEN_RENDER),A
	LD (DOC_MODIFIED),A
	AND A
	RET

;------------------------------------------------------------------------------
; HBIOS_DETECT: Probe RomWBW HBIOS hardware environment presence
;
; Purpose:
;   Inspects memory vector table and queries RomWBW HBIOS SYSVER (0xF1) to
;   determine if running under RomWBW firmware.
;
; Call Usage / Protocol:
;   Called via CALL during startup and memory info query.
;
; Inputs:
;   None.
;
; Outputs:
;   Zero flag set if HBIOS present; NZ set if standard CP/M (non-HBIOS).
;
; Preserves / Modifies:
;   Clobbers AF. Preserves BC, DE, HL.
;------------------------------------------------------------------------------
HBIOS_DETECT:
	IFDEF TARGET_NEXT
	OR 0FFH				; NZ (not HBIOS)
	RET
	ELSE
	PUSH IX
	LD B,0F8H			; CIOCNT
	LD C,000H
	RST 08H
	POP IX
	OR A
	RET
	ENDIF

	IFDEF TARGET_NEXT
;------------------------------------------------------------------------------
; DRAIN_REMAINING_CSI: Consume trailing bytes of unhandled escape sequence
;
; Purpose:
;   Drains pending sequence bytes from console buffer until terminating
;   final byte (0x40..0x7E, e.g. '~', 'A'..'Z', 'a'..'z') or timeout,
;   preventing stray bytes from leaking into the document text buffer.
;------------------------------------------------------------------------------
DRAIN_REMAINING_CSI:
DRC_CHECK:
	CP 040H				; Final bytes in CSI are 0x40..0x7E
	JR C,DRC_NEXT
	CP 07FH
	RET C				; Final byte consumed; drain done
DRC_NEXT:
	LD BC,ESC_TIMEOUT_LOOPS
DRC_WAIT:
	CALL CHECK_KEY_READY
	JR NZ,DRC_READ
	DEC BC
	LD A,B
	OR C
	JR NZ,DRC_WAIT
	RET				; Timeout
DRC_READ:
	CALL GET_KEY
	JR DRC_CHECK

;------------------------------------------------------------------------------
; DRAIN_ESCAPE_SEQUENCE: Consume entire pending escape sequence after ESC (0x1B)
;
; Purpose:
;   Drains pending CSI, SS3, or multi-byte escape sequence from console
;   buffer without executing actions or altering screen/cursor state.
;   Used by modal dialog input loops to absorb unexpected keystrokes.
;
; Preserves:
;   BC, DE, HL
;------------------------------------------------------------------------------
DRAIN_ESCAPE_SEQUENCE:
	PUSH BC
	PUSH DE
	PUSH HL
	CALL GET_KEY
	CP '['
	JR NZ,DES_NOT_CSI
	CALL GET_KEY
	CALL DRAIN_REMAINING_CSI
	JR DES_DONE
DES_NOT_CSI:
	CP 'O'
	JR NZ,DES_DONE
	CALL GET_KEY
DES_DONE:
	POP HL
	POP DE
	POP BC
	RET
	ENDIF

