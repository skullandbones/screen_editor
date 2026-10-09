;==============================================================================
; HAL_NEXT_KEYBOARD.ASM: Hardware Abstraction Layer - Native Next Keyboard
;
; Purpose:
;   Implements keyboard scanning, key status polling, and scan code translation
;   for Profile 3 (Native ZX Spectrum Next / NextZXOS).
;   Supports dedicated arrow keys, Edit (ESC), Break (Ctrl+C), Delete, and
;   Next keyboard layouts.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; ZX Spectrum System Variables & Keyboard Equates
;------------------------------------------------------------------------------
SYSVAR_LAST_K		EQU	05C08H	; Spectrum sysvar: last pressed key
KEY_PORT_ULA		EQU	000FEH	; ULA keyboard row port

; Editor Key Definitions (matching WordStar control conventions)
KEY_WORDSTAR_UP		EQU	005H	; Ctrl+E (Cursor Up)
KEY_WORDSTAR_DOWN	EQU	018H	; Ctrl+X (Cursor Down)
KEY_WORDSTAR_LEFT	EQU	013H	; Ctrl+S (Cursor Left)
KEY_WORDSTAR_RIGHT	EQU	004H	; Ctrl+D (Cursor Right)
KEY_WORDSTAR_DEL	EQU	007H	; Ctrl+G (Delete character under cursor)
KEY_ESCAPE		EQU	01BH	; ESC (ASCII 27)

; Next Keyboard Raw Control Codes
NEXT_RAW_EDIT		EQU	007H	; Sinclair Edit (Caps Shift + 1)
NEXT_RAW_LEFT		EQU	008H	; Sinclair Left (Caps Shift + 5)
NEXT_RAW_DOWN		EQU	00AH	; Sinclair Down (Caps Shift + 6)
NEXT_RAW_UP		EQU	00BH	; Sinclair Up (Caps Shift + 7)
NEXT_RAW_RIGHT		EQU	009H	; Sinclair Right (Caps Shift + 8)
NEXT_RAW_DELETE		EQU	00CH	; Sinclair Delete (Caps Shift + 0)

;------------------------------------------------------------------------------
; HAL_KEYBOARD_INIT: Initialize native keyboard subsystem
;
; Purpose:
;   Resets last key buffer variable to ensure no stale keystrokes are pending.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
HAL_KEYBOARD_INIT:
	XOR A
	LD (SYSVAR_LAST_K),A
	RET

;------------------------------------------------------------------------------
; HAL_KEYBOARD_POLL: Non-blocking check for keyboard input
;
; Outputs:
;   A = 0xFF and Z=0 if key ready; A = 0x00 and Z=1 if no key.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; modifies AF.
;------------------------------------------------------------------------------
HAL_KEYBOARD_POLL:
	LD A,(SYSVAR_LAST_K)
	OR A
	JR NZ,HKP_KEY_READY

	; Quick scan across all keyboard rows via port $FE
	XOR A
	IN A,(KEY_PORT_ULA)
	CPL
	AND 01FH
	JR NZ,HKP_KEY_READY

	; No key pressed
	XOR A
	RET

HKP_KEY_READY:
	LD A,0FFH
	OR A
	RET

;------------------------------------------------------------------------------
; HAL_KEYBOARD_GETKEY: Blocking keyboard read primitive
;
; Outputs:
;   A = Normalized editor keycode.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
HAL_KEYBOARD_GETKEY:
HKG_WAIT_LOOP:
	CALL HAL_KEYBOARD_POLL
	JR Z,HKG_WAIT_LOOP

	LD A,(SYSVAR_LAST_K)
	OR A
	JR Z,HKG_WAIT_LOOP

	PUSH BC
	LD B,A
	XOR A
	LD (SYSVAR_LAST_K),A		; Acknowledge key
	LD A,B
	POP BC

	; Translate key into editor internal representation
	CALL HAL_KEYBOARD_TRANSLATE
	RET

;------------------------------------------------------------------------------
; HAL_KEYBOARD_TRANSLATE: Translate raw Spectrum Next keycode to editor command
;
; Inputs:
;   A = Raw ASCII character / scan code.
;
; Outputs:
;   A = Normalized editor keycode.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; modifies AF.
;------------------------------------------------------------------------------
HAL_KEYBOARD_TRANSLATE:
	CP NEXT_RAW_LEFT
	JR NZ,HKT_NOT_LEFT
	LD A,KEY_WORDSTAR_LEFT
	RET

HKT_NOT_LEFT:
	CP NEXT_RAW_RIGHT
	JR NZ,HKT_NOT_RIGHT
	LD A,KEY_WORDSTAR_RIGHT
	RET

HKT_NOT_RIGHT:
	CP NEXT_RAW_UP
	JR NZ,HKT_NOT_UP
	LD A,KEY_WORDSTAR_UP
	RET

HKT_NOT_UP:
	CP NEXT_RAW_DOWN
	JR NZ,HKT_NOT_DOWN
	LD A,KEY_WORDSTAR_DOWN
	RET

HKT_NOT_DOWN:
	CP NEXT_RAW_EDIT
	JR NZ,HKT_NOT_EDIT
	LD A,KEY_ESCAPE
	RET

HKT_NOT_EDIT:
	CP NEXT_RAW_DELETE
	JR NZ,HKT_NOT_DELETE
	LD A,KEY_WORDSTAR_DEL
	RET

HKT_NOT_DELETE:
	CP 07FH				; Standard ASCII Delete
	RET NZ
	LD A,KEY_BACKSPACE
	RET

; End of HAL_NEXT_KEYBOARD.ASM
