;==============================================================================
; HALFPLUG.ASM - 16KB Reference Far RAM Plugin for SE.COM
; Digital Research CP/M 3 Page-Relocatable (.PRL) Format
;
; Demonstrates 16KB Far RAM slot dynamic allocation and execution.
;
; Entry:
;   IX = Pointer to PLUGIN_HOST_API vector (Upper Common RAM)
; Returns:
;   A  = 0 (Clean return, document unmodified)
;   CY = 0 (Success)
;==============================================================================

	ORG	0100H

;------------------------------------------------------------------------------
; Standard 3-Entry Jump Table
;------------------------------------------------------------------------------
ENTRY:
	JP	DO_HALFPLUG_EXECUTE	; +0: Action 0 (Main Execution)
	JP	DO_HALFPLUG_ABOUT	; +3: Action 1 (About Screen)
	SCF				; +6: Action 2 (Config - Not Supported)
	RET
	NOP

;------------------------------------------------------------------------------
; Action 0: Main Execution
;------------------------------------------------------------------------------
DO_HALFPLUG_EXECUTE:
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

	; Print modal 16KB execution banner
	LD	HL,HALF_EXEC_TABLE
	LD	B,8
	LD	C,38
	CALL	RENDER_CENTERED_BOX

	; Wait for keypress
	CALL	CALL_HOST_GETKEY

	XOR	A			; A = 0: Clean, document unmodified
	OR	A			; CY = 0
	RET

INIT_ERR:
	SCF				; CY = 1
	RET

;------------------------------------------------------------------------------
; Action 1: Modal About Screen
;------------------------------------------------------------------------------
DO_HALFPLUG_ABOUT:
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

	LD	HL,HALF_ABT_TABLE
	LD	B,9
	LD	C,38
	CALL	RENDER_CENTERED_BOX
	CALL	CALL_HOST_GETKEY

	XOR	A			; A = 0: Clean
	OR	A			; CY = 0
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
; UI Strings & Dialog Boxes
;------------------------------------------------------------------------------
STR_HALF_BORDER:	DB	"+------------------------------------+", 0

; Execution Dialog Table
HALF_EXEC_TABLE:
	DW	STR_HALF_BORDER
	DW	STR_HALF_EXEC_L2
	DW	STR_HALF_BORDER
	DW	STR_HALF_EXEC_L4
	DW	STR_HALF_EXEC_L5
	DW	STR_HALF_BORDER
	DW	STR_HALF_EXEC_L7
	DW	STR_HALF_BORDER

STR_HALF_EXEC_L2:	DB	"|      HALFPLUG (16KB Far RAM Plugin)|", 0
STR_HALF_EXEC_L4:	DB	"| Mode   : Far RAM Direct Execution  |", 0
STR_HALF_EXEC_L5:	DB	"| Size   : 16KB Modular Slot Class   |", 0
STR_HALF_EXEC_L7:	DB	"|     Press any key to continue      |", 0

; About Dialog Table
HALF_ABT_TABLE:
	DW	STR_HALF_BORDER
	DW	STR_HALF_ABT_L2
	DW	STR_HALF_BORDER
	DW	STR_HALF_ABT_L4
	DW	STR_HALF_ABT_L5
	DW	STR_HALF_ABT_L6
	DW	STR_HALF_BORDER
	DW	STR_HALF_ABT_L8
	DW	STR_HALF_BORDER

STR_HALF_ABT_L2:	DB	"|   HALFPLUG 16KB Reference Plugin   |", 0
STR_HALF_ABT_L4:	DB	"| Version: v0.1.0 (2026-09-24)       |", 0
STR_HALF_ABT_L5:	DB	"| Size   : 16KB Far RAM Slot Class   |", 0
STR_HALF_ABT_L6:	DB	"| Mode   : Far RAM Direct Execution  |", 0
STR_HALF_ABT_L8:	DB	"|      Press any key to return       |", 0

;------------------------------------------------------------------------------
; 16KB Slot Padding Payload (> 8192 bytes and <= 16384 bytes)
;------------------------------------------------------------------------------
HALFPLUG_PAYLOAD:
	DS	10000
