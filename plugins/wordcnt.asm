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

ENTRY:
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
	LD	DE,STR_BOX_TOP
	CALL	CALL_HOST_PRINT
	LD	DE,STR_BOX_LINES
	CALL	CALL_HOST_PRINT
	LD	DE,STR_BOX_WORDS
	CALL	CALL_HOST_PRINT
	LD	DE,STR_BOX_CHARS
	CALL	CALL_HOST_PRINT
	LD	DE,STR_BOX_BOT
	CALL	CALL_HOST_PRINT

	; Wait for any keypress via HOST_GET_KEY (IX+28)
	CALL	CALL_HOST_GETKEY

	LD	A,0			; A = 0: Clean, document unmodified
	OR	A
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

STR_BOX_TOP:
	DB	13,10,"  +------------------------------------+",13,10
	DB	"  |       Document Statistics          |",13,10
	DB	"  +------------------------------------+",13,10,"$"

STR_BOX_LINES:
	DB	"  |  Total Lines      : "
STR_BOX_LINES_VAL:
	DB	"     "
	DB	"          |",13,10,"$"

STR_BOX_WORDS:
	DB	"  |  Total Words      : "
STR_BOX_WORDS_VAL:
	DB	"     "
	DB	"          |",13,10,"$"

STR_BOX_CHARS:
	DB	"  |  Total Characters : "
STR_BOX_CHARS_VAL:
	DB	"     "
	DB	"          |",13,10,"$"

STR_BOX_BOT:
	DB	"  +------------------------------------+",13,10
	DB	"  |     [Press any key to continue]    |",13,10
	DB	"  +------------------------------------+",13,10,"$"
