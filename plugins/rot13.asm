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

ENTRY:
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
	; Set status message using Host API callback at IX+31
	; Notice: MSG_SUCCESS address requires PRL page relocation!
	LD	DE,MSG_SUCCESS
	CALL	CALL_HOST_STATUS

	LD	A,1			; A = 1: Active line modified
	OR	A			; Clear Carry (CY=0)
	RET

INIT_ERR:
	LD	A,0FFH			; A = 0xFF: Error
	SCF				; Set Carry (CY=1)
	RET

;------------------------------------------------------------------------------
; Helper: Call HOST_SET_STATUS_MSG at IX+31
; In: DE = Pointer to '$'-terminated status message
;------------------------------------------------------------------------------
CALL_HOST_STATUS:
	PUSH	IX
	POP	HL
	LD	BC,33
	ADD	HL,BC			; HL = &HOST_SET_STATUS_MSG vector
	JP	(HL)

;------------------------------------------------------------------------------
; Relocatable Data
;------------------------------------------------------------------------------
MSG_SUCCESS:
	DB	"[ROT13 Applied]$", 0
