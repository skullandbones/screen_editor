;==============================================================================
; WORDCNT.ASM - Word & Character Count Plugin for SE.COM
; Digital Research CP/M 3 Overlay / PRL Format
;
; Iterates through all document lines using Host API, calculates
; total lines, words, and characters, and displays a modal summary dialog.
;
; Entry:
;   IX = Pointer to PLUGIN_HOST_API vector
; Returns:
;   A  = 2 (Redraw screen on return)
;   CY = 0 (Success)
;==============================================================================

	ORG	0100H

;------------------------------------------------------------------------------
; Standard 3-Entry Jump Table
;------------------------------------------------------------------------------
ENTRY:
	JP	DO_WORDCNT_EXECUTE	; +0: Action 0 (Main Execution)
	JP	DO_WORDCNT_ABOUT	; +3: Action 1 (About Screen)
	JP	DO_WORDCNT_CONFIG	; +6: Action 2 (Config Screen)

;------------------------------------------------------------------------------
; Action 0: Main Execution (Document Statistics Summary)
;------------------------------------------------------------------------------
DO_WORDCNT_EXECUTE:
	; Verify Host API Magic "SE" (check IX or IY)
	LD	A,(IX+0)
	CP	'S'
	JR	Z,API_OK
	PUSH	IY
	POP	IX
	LD	A,(IX+0)
	CP	'S'
	JP	NZ,INIT_ERR
API_OK:
	LD	A,(IX+1)
	CP	'E'
	JP	NZ,INIT_ERR

	; Reset counters
	LD	HL,0
	LD	(TOTAL_LINES_CNT),HL
	LD	(TOTAL_WORDS_CNT),HL
	LD	(TOTAL_CHARS_CNT),HL

	; Read DOC_TOTAL_LINES pointer from IX+10
	LD	L,(IX+10)
	LD	H,(IX+11)
	LD	E,(HL)
	INC	HL
	LD	D,(HL)			; DE = DOC_TOTAL_LINES
	LD	(TOTAL_LINES_CNT),DE

	LD	A,D
	OR	E
	JR	Z,SHOW_DIALOG		; 0 lines

	; Iterate HL = 0 .. (DOC_TOTAL_LINES - 1)
	LD	HL,0
	LD	(CUR_ROW_IDX),HL

LINE_ITER_LOOP:
	; Call HOST_CHECKOUT_LINE at IX+16
	; Input: HL = Row Index
	LD	HL,(CUR_ROW_IDX)
	CALL	CALL_HOST_CHECKOUT

	; Get ACTIVE_LINE_BUF and ACTIVE_LINE_LEN
	LD	L,(IX+6)
	LD	H,(IX+7)
	LD	C,(HL)
	INC	HL
	LD	B,(HL)			; BC = Line length

	; Accumulate character count
	LD	HL,(TOTAL_CHARS_CNT)
	ADD	HL,BC
	LD	(TOTAL_CHARS_CNT),HL

	; If line length is 0, skip word counting for this line
	LD	A,B
	OR	C
	JR	Z,ADVANCE_LINE

	; Scan words in ACTIVE_LINE_BUF
	LD	L,(IX+4)
	LD	H,(IX+5)		; HL = ACTIVE_LINE_BUF
	XOR	A
	LD	(IN_WORD_STATE),A

SCAN_CHARS_LOOP:
	LD	A,(HL)
	CP	' '+1
	JR	C,CHAR_IS_SPACE		; <= ' ' (space, tab, cr, lf)

	; Character is non-whitespace
	LD	A,(IN_WORD_STATE)
	OR	A
	JR	NZ,SCAN_NEXT_CHAR	; Already in a word

	; Start of a new word!
	LD	A,1
	LD	(IN_WORD_STATE),A
	PUSH	HL
	LD	HL,(TOTAL_WORDS_CNT)
	INC	HL
	LD	(TOTAL_WORDS_CNT),HL
	POP	HL
	JR	SCAN_NEXT_CHAR

CHAR_IS_SPACE:
	XOR	A
	LD	(IN_WORD_STATE),A

SCAN_NEXT_CHAR:
	INC	HL
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,SCAN_CHARS_LOOP

ADVANCE_LINE:
	LD	HL,(CUR_ROW_IDX)
	INC	HL
	LD	(CUR_ROW_IDX),HL
	LD	DE,(TOTAL_LINES_CNT)
	CALL	CMP_HL_DE
	JR	C,LINE_ITER_LOOP

SHOW_DIALOG:
	; Format numbers into box strings directly
	LD	HL,(TOTAL_LINES_CNT)
	LD	DE,STR_BOX_LINES_VAL
	CALL	FORMAT_DEC_5

	LD	HL,(TOTAL_WORDS_CNT)
	LD	DE,STR_BOX_WORDS_VAL
	CALL	FORMAT_DEC_5

	LD	HL,(TOTAL_CHARS_CNT)
	LD	DE,STR_BOX_CHARS_VAL
	CALL	FORMAT_DEC_5

	; Print modal statistics box
	LD	HL,WORDCNT_STAT_TABLE
	LD	B,9
	LD	C,38
	CALL	RENDER_CENTERED_BOX

	; Wait for any keypress via HOST_GET_KEY (IX+30)
	CALL	CALL_HOST_GETKEY

	LD	A,0			; A = 0: Clean, document unmodified
	OR	A
	RET

;------------------------------------------------------------------------------
; Action 1: Modal About Screen
;------------------------------------------------------------------------------
DO_WORDCNT_ABOUT:
	; Verify Host API Magic "SE" (check IX or IY)
	LD	A,(IX+0)
	CP	'S'
	JR	Z,ABT_API_OK
	PUSH	IY
	POP	IX
	LD	A,(IX+0)
	CP	'S'
	JP	NZ,INIT_ERR
ABT_API_OK:
	LD	A,(IX+1)
	CP	'E'
	JP	NZ,INIT_ERR

	LD	HL,WORDCNT_ABT_TABLE
	LD	B,11
	LD	C,38
	CALL	RENDER_CENTERED_BOX
	CALL	CALL_HOST_GETKEY

	XOR	A			; A = 0: Clean, document unmodified
	OR	A			; Clear Carry (CY=0)
	RET

;------------------------------------------------------------------------------
; Action 2: Interactive Configuration Screen
;------------------------------------------------------------------------------
DO_WORDCNT_CONFIG:
	; Verify Host API Magic "SE" (check IX or IY)
	LD	A,(IX+0)
	CP	'S'
	JR	Z,CFG_API_OK
	PUSH	IY
	POP	IX
	LD	A,(IX+0)
	CP	'S'
	JP	NZ,INIT_ERR
CFG_API_OK:
	LD	A,(IX+1)
	CP	'E'
	JP	NZ,INIT_ERR

	; Save initial config state for ESC cancel
	LD	A,(CFG_COUNT_BLANK)
	LD	(SAVED_COUNT_BLANK),A
	LD	A,(CFG_COUNT_WS)
	LD	(SAVED_COUNT_WS),A

CFG_DISPLAY_LOOP:
	LD	A,(CFG_COUNT_BLANK)
	OR	A
	JR	Z,SET_BLANK_NO
	LD	HL,STR_VAL_YES
	JR	PUT_BLANK_STR
SET_BLANK_NO:
	LD	HL,STR_VAL_NO
PUT_BLANK_STR:
	LD	DE,STR_CFG_BLANK_VAL
	LD	BC,3
	LDIR

	LD	A,(CFG_COUNT_WS)
	OR	A
	JR	Z,SET_WS_NO
	LD	HL,STR_VAL_YES
	JR	PUT_WS_STR
SET_WS_NO:
	LD	HL,STR_VAL_NO
PUT_WS_STR:
	LD	DE,STR_CFG_WS_VAL
	LD	BC,3
	LDIR

	LD	HL,WORDCNT_CFG_TABLE
	LD	B,8
	LD	C,38
	CALL	RENDER_CENTERED_BOX
	CALL	CALL_HOST_GETKEY

	CP	'1'
	JR	Z,TOGGLE_BLANK
	CP	'2'
	JR	Z,TOGGLE_WS
	CP	13			; CR: Save & Exit
	JR	Z,CFG_DONE
	CP	27			; ESC: Cancel
	JR	Z,CFG_CANCEL
	JR	CFG_DISPLAY_LOOP

TOGGLE_BLANK:
	LD	A,(CFG_COUNT_BLANK)
	XOR	1
	LD	(CFG_COUNT_BLANK),A
	JR	CFG_DISPLAY_LOOP

TOGGLE_WS:
	LD	A,(CFG_COUNT_WS)
	XOR	1
	LD	(CFG_COUNT_WS),A
	JR	CFG_DISPLAY_LOOP

CFG_CANCEL:
	LD	A,(SAVED_COUNT_BLANK)
	LD	(CFG_COUNT_BLANK),A
	LD	A,(SAVED_COUNT_WS)
	LD	(CFG_COUNT_WS),A

CFG_DONE:
	XOR	A			; A = 0: Clean, document unmodified
	OR	A			; Clear Carry
	RET

INIT_ERR:
	LD	A,0FFH
	SCF
	RET

;------------------------------------------------------------------------------
; CMP_HL_DE: Compare 16-bit HL and DE
; Returns: Carry set if HL < DE, Zero set if HL == DE
;------------------------------------------------------------------------------
CMP_HL_DE:
	LD	A,H
	CP	D
	RET	NZ
	LD	A,L
	CP	E
	RET

;------------------------------------------------------------------------------
; FORMAT_DEC_5: Format HL into exactly 5-char ASCII at DE
;------------------------------------------------------------------------------
FORMAT_DEC_5:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	LD	BC,-10000
	CALL	FMT_DIGIT
	LD	BC,-1000
	CALL	FMT_DIGIT
	LD	BC,-100
	CALL	FMT_DIGIT
	LD	BC,-10
	CALL	FMT_DIGIT
	LD	A,L
	ADD	A,'0'
	LD	(DE),A

	POP	HL
	POP	DE
	POP	BC
	RET

FMT_DIGIT:
	LD	A,'0'-1
FMT_LOOP:
	INC	A
	ADD	HL,BC
	JR	C,FMT_LOOP
	SBC	HL,BC
	LD	(DE),A
	INC	DE
	RET

;------------------------------------------------------------------------------
; Host API Call Wrappers
;------------------------------------------------------------------------------
CALL_HOST_CHECKOUT:
	PUSH	IX
	POP	BC
	PUSH	HL
	LD	HL,18
	ADD	HL,BC
	EX	(SP),HL			; Jump target on stack
	RET

CALL_HOST_PRINT:
	PUSH	IX
	POP	HL
	LD	BC,27
	ADD	HL,BC
	JP	(HL)

CALL_HOST_GETKEY:
	PUSH	IX
	POP	HL
	LD	BC,30
	ADD	HL,BC
	JP	(HL)

CALL_HOST_LOCATE:
	PUSH	IX
	EX	(SP),HL
	PUSH	BC
	LD	BC,52			; Offset +52: LOCATE_RC (H=Row, L=Col)
	ADD	HL,BC
	POP	BC
	EX	(SP),HL
	RET

;------------------------------------------------------------------------------
; Centered Modal Box Renderer
;------------------------------------------------------------------------------
RENDER_CENTERED_BOX:
	; B = line count, C = box width, HL = table of line string addresses
	LD	A,(IX+16)
	SUB	B
	SRL	A
	INC	A
	LD	D,A			; D = StartRow

	LD	A,(IX+14)
	SUB	C
	SRL	A
	INC	A
	LD	E,A			; E = StartCol

RCB_LOOP:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	LD	H,D
	LD	L,E
	CALL	CALL_HOST_LOCATE

	POP	HL
	LD	E,(HL)
	INC	HL
	LD	D,(HL)
	INC	HL
	PUSH	HL

	CALL	CALL_HOST_PRINT

	POP	HL
	POP	DE
	INC	D
	POP	BC
	DJNZ	RCB_LOOP
	RET

;------------------------------------------------------------------------------
; Data Variables
;------------------------------------------------------------------------------
CUR_ROW_IDX:		DW	0
TOTAL_LINES_CNT:	DW	0
TOTAL_WORDS_CNT:	DW	0
TOTAL_CHARS_CNT:	DW	0
IN_WORD_STATE:		DB	0

STR_NUM_LINES:		DB	"     ", 0
STR_NUM_WORDS:		DB	"     ", 0
STR_NUM_CHARS:		DB	"     ", 0

STR_WORDCNT_BORDER:	DB	"+------------------------------------+", 0

; Statistics Dialog Table
WORDCNT_STAT_TABLE:
	DW	STR_WORDCNT_BORDER
	DW	STR_BOX_TITLE
	DW	STR_WORDCNT_BORDER
	DW	STR_BOX_LINES
	DW	STR_BOX_WORDS
	DW	STR_BOX_CHARS
	DW	STR_WORDCNT_BORDER
	DW	STR_BOX_CONT
	DW	STR_WORDCNT_BORDER

STR_BOX_TITLE:		DB	"|       Document Statistics          |", 0
STR_BOX_LINES:		DB	"|  Total Lines      : "
STR_BOX_LINES_VAL:	DB	"     "
			DB	"          |", 0
STR_BOX_WORDS:		DB	"|  Total Words      : "
STR_BOX_WORDS_VAL:	DB	"     "
			DB	"          |", 0
STR_BOX_CHARS:		DB	"|  Total Characters : "
STR_BOX_CHARS_VAL:	DB	"     "
			DB	"          |", 0
STR_BOX_CONT:		DB	"|     [Press any key to continue]    |", 0

; About Dialog Table
WORDCNT_ABT_TABLE:
	DW	STR_WORDCNT_BORDER
	DW	STR_WCA_L2
	DW	STR_WORDCNT_BORDER
	DW	STR_WCA_L4
	DW	STR_WCA_L5
	DW	STR_WCA_L6
	DW	STR_WCA_L7
	DW	STR_WCA_L8
	DW	STR_WORDCNT_BORDER
	DW	STR_WCA_L10
	DW	STR_WORDCNT_BORDER

STR_WCA_L2:		DB	"|   Word & Character Count Plugin    |", 0
STR_WCA_L4:		DB	"| Version: v0.1.0 (2026-09-23)       |", 0
STR_WCA_L5:		DB	"| Compatible with SE.COM >= v0.9.7   |", 0
STR_WCA_L6:		DB	"| Mode   : TPA Overlay / Far RAM     |", 0
STR_WCA_L7:		DB	"| Scope  : Full Document Scanner     |", 0
STR_WCA_L8:		DB	"| Metrics: Lines, Words, Characters  |", 0
STR_WCA_L10:		DB	"|     [Press any key to return]      |", 0

; Configuration Dialog Table
WORDCNT_CFG_TABLE:
	DW	STR_WORDCNT_BORDER
	DW	STR_WCC_L2
	DW	STR_WORDCNT_BORDER
	DW	STR_WCC_L4
	DW	STR_WCC_L5
	DW	STR_WORDCNT_BORDER
	DW	STR_WCC_L7
	DW	STR_WORDCNT_BORDER

STR_WCC_L2:		DB	"|     Word Count Configuration       |", 0
STR_WCC_L4:		DB	"|  1. Count Blank Lines  : ["
STR_CFG_BLANK_VAL:	DB	"YES]     |", 0
STR_WCC_L5:		DB	"|  2. Count Whitespace   : ["
STR_CFG_WS_VAL:		DB	"YES]       |", 0
STR_WCC_L7:		DB	"| [Enter]=Save & Exit   [ESC]=Cancel |", 0

CFG_COUNT_BLANK:	DB	1
CFG_COUNT_WS:		DB	1
SAVED_COUNT_BLANK:	DB	1
SAVED_COUNT_WS:		DB	1
STR_VAL_YES:		DB	"YES"
STR_VAL_NO:		DB	"NO "
