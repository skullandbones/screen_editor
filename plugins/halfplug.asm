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
	LD	DE,STR_BOX_TOP
	CALL	CALL_HOST_PRINT
	LD	DE,STR_BOX_BODY1
	CALL	CALL_HOST_PRINT
	LD	DE,STR_BOX_BODY2
	CALL	CALL_HOST_PRINT
	LD	DE,STR_BOX_BOT
	CALL	CALL_HOST_PRINT

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

	LD	DE,STR_HALF_ABOUT
	CALL	CALL_HOST_PRINT
	CALL	CALL_HOST_GETKEY

	XOR	A			; A = 0: Clean
	OR	A			; CY = 0
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

;------------------------------------------------------------------------------
; UI Strings & Dialog Boxes
;------------------------------------------------------------------------------
STR_BOX_TOP:
	DB	13,10,"~ +------------------------------------+",13,10
	DB	"~ |      HALFPLUG (16KB Far RAM Plugin)|",13,10
	DB	"~ +------------------------------------+",13,10,"$"

STR_BOX_BODY1:
	DB	"~ | Mode   : Far RAM Direct Execution  |",13,10,"$"

STR_BOX_BODY2:
	DB	"~ | Size   : 16KB Modular Slot Class   |",13,10,"$"

STR_BOX_BOT:
	DB	"~ +------------------------------------+",13,10
	DB	"~ |     [Press any key to continue]    |",13,10
	DB	"~ +------------------------------------+",13,10,"$"

STR_HALF_ABOUT:
	DB	13,10,"~ +------------------------------------+"
	DB	13,10,"~ |   HALFPLUG 16KB Reference Plugin   |"
	DB	13,10,"~ +------------------------------------+"
	DB	13,10,"~ | Version: v0.1.0 (2026-09-24)       |"
	DB	13,10,"~ | Size   : 16KB Far RAM Slot Class   |"
	DB	13,10,"~ | Mode   : Far RAM Direct Execution  |"
	DB	13,10,"~ +------------------------------------+"
	DB	13,10,"~ |     [Press any key to return]      |"
	DB	13,10,"~ +------------------------------------+",13,10,"$"

;------------------------------------------------------------------------------
; 16KB Slot Padding Payload (> 4096 bytes and <= 16384 bytes)
;------------------------------------------------------------------------------
HALFPLUG_PAYLOAD:
	DS	6000
