;==============================================================================
; ROT13.ASM - ROT13 Text Transform Plugin for SE.COM
; Digital Research CP/M 3 Page-Relocatable (.PRL) Format
;
; Transforms text in the currently active line using ROT13 cipher.
; Demonstrates Host API interaction and PRL on-the-fly relocation.
;
; Entry:
;   IX = Pointer to PLUGIN_HOST_API vector
; Returns:
;   A  = 1 (Active line modified)
;   CY = 0 (Success)
;==============================================================================

	ORG	0100H

;------------------------------------------------------------------------------
; Standard 3-Entry Jump Table
;------------------------------------------------------------------------------
ENTRY:
	JP	DO_ROT13_EXECUTE	; +0: Action 0 (Main Execution)
	JP	DO_ROT13_ABOUT		; +3: Action 1 (About Screen)
	SCF				; +6: Action 2 (Config - Not Supported)
	RET
	NOP

;------------------------------------------------------------------------------
; Action 0: Main ROT13 Cipher Execution
;------------------------------------------------------------------------------
DO_ROT13_EXECUTE:
	; Verify Host API Magic "SE" (check IX or IY)
	LD	A,(IX+0)
	CP	'S'
	JR	Z,API_OK
	PUSH	IY
	POP	IX
	LD	A,(IX+0)
	CP	'S'
	JR	NZ,INIT_ERR
API_OK:
	LD	A,(IX+1)
	CP	'E'
	JR	NZ,INIT_ERR

	; Obtain ACTIVE_LINE_BUF pointer into HL
	LD	L,(IX+4)
	LD	H,(IX+5)

	; Obtain ACTIVE_LINE_LEN pointer into DE
	LD	E,(IX+6)
	LD	D,(IX+7)

	; Read 16-bit line length into BC
	EX	DE,HL			; HL = &ACTIVE_LINE_LEN, DE = &ACTIVE_LINE_BUF
	LD	C,(HL)
	INC	HL
	LD	B,(HL)			; BC = Line Length
	EX	DE,HL			; HL = &ACTIVE_LINE_BUF

	; If line length is zero, finish immediately
	LD	A,B
	OR	C
	JR	Z,FINISH_SUCCESS

ROT13_LOOP:
	LD	A,(HL)

	; Check uppercase 'A'..'Z'
	CP	'A'
	JR	C,CHECK_LOWER
	CP	'Z'+1
	JR	NC,CHECK_LOWER
	ADD	A,13
	CP	'Z'+1
	JR	C,SAVE_CHAR
	SUB	26
	JR	SAVE_CHAR

CHECK_LOWER:
	; Check lowercase 'a'..'z'
	CP	'a'
	JR	C,NEXT_BYTE
	CP	'z'+1
	JR	NC,NEXT_BYTE
	ADD	A,13
	CP	'z'+1
	JR	C,SAVE_CHAR
	SUB	26

SAVE_CHAR:
	LD	(HL),A

NEXT_BYTE:
	INC	HL
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,ROT13_LOOP

FINISH_SUCCESS:
	; Display Tier 2 modal completion pop-up
	LD	HL,ROT13_DONE_TABLE
	LD	B,7
	LD	C,38
	CALL	RENDER_CENTERED_BOX
	CALL	CALL_HOST_GETKEY

	LD	A,1			; A = 1: Active line modified
	OR	A			; Clear Carry (CY=0)
	RET

INIT_ERR:
	LD	A,0FFH			; A = 0xFF: Error
	SCF				; Set Carry (CY=1)
	RET

;------------------------------------------------------------------------------
; Action 1: Modal About Screen
;------------------------------------------------------------------------------
DO_ROT13_ABOUT:
	; Verify Host API Magic "SE"
	LD	A,(IX+0)
	CP	'S'
	JR	Z,ABT_API_OK
	PUSH	IY
	POP	IX
	LD	A,(IX+0)
	CP	'S'
	JR	NZ,INIT_ERR
ABT_API_OK:
	LD	A,(IX+1)
	CP	'E'
	JR	NZ,INIT_ERR

	LD	HL,ROT13_ABT_TABLE
	LD	B,11
	LD	C,38
	CALL	RENDER_CENTERED_BOX
	CALL	CALL_HOST_GETKEY

	XOR	A			; A = 0: Clean, document unmodified
	OR	A			; Clear Carry (CY=0)
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
; Host API Callback Helpers (via IX)
;------------------------------------------------------------------------------
CALL_HOST_PRINT:
	PUSH	IX
	POP	HL
	LD	BC,27			; Offset +27: PRINT_STR
	ADD	HL,BC
	JP	(HL)

CALL_HOST_GETKEY:
	PUSH	IX
	POP	HL
	LD	BC,30			; Offset +30: GET_KEY
	ADD	HL,BC
	JP	(HL)

CALL_HOST_STATUS:
	PUSH	IX
	POP	HL
	LD	BC,33			; Offset +33: SET_STATUS_MSG
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
; Relocatable Data
;------------------------------------------------------------------------------
ROT13_DONE_TABLE:
	DW	STR_ROT13_BORDER
	DW	STR_ROT13_L2
	DW	STR_ROT13_BORDER
	DW	STR_ROT13_DONE_MSG
	DW	STR_ROT13_DONE_BLANK
	DW	STR_ROT13_L10
	DW	STR_ROT13_BORDER

ROT13_ABT_TABLE:
	DW	STR_ROT13_BORDER
	DW	STR_ROT13_L2
	DW	STR_ROT13_BORDER
	DW	STR_ROT13_L4
	DW	STR_ROT13_L5
	DW	STR_ROT13_L6
	DW	STR_ROT13_L7
	DW	STR_ROT13_L8
	DW	STR_ROT13_BORDER
	DW	STR_ROT13_L10
	DW	STR_ROT13_BORDER

STR_ROT13_BORDER: DB	"+------------------------------------+", 0
STR_ROT13_L2:	DB	"|       ROT13 Text Cipher Plugin     |", 0
STR_ROT13_DONE_MSG:
	DB	"|      ROT13 Cipher Applied          |", 0
STR_ROT13_DONE_BLANK:
	DB	"|                                    |", 0
STR_ROT13_L4:	DB	"| Version: v0.1.0 (2026-09-23)       |", 0
STR_ROT13_L5:	DB	"| Compatible with SE.COM >= v0.9.7   |", 0
STR_ROT13_L6:	DB	"| Mode   : 4KB TPA Overlaid Slot     |", 0
STR_ROT13_L7:	DB	"| Scope  : Current Editor Line       |", 0
STR_ROT13_L8:	DB	"| Action : Reversible 13-Char Shift  |", 0
STR_ROT13_L10:	DB	"|     Press any key to continue      |", 0
