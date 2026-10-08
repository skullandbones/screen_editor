;==============================================================================
; HAL_NEXTCPM_KEYBOARD.ASM: Hardware Abstraction Layer - NextCPM Keyboard
;
; Purpose:
;   Implements keyboard translation, extended key decoding, and Next-specific
;   keyboard mapping for Profile 2 (CP/M on ZX Spectrum Next).
;   Handles dedicated arrow keys, Edit (ESC), Break (Ctrl+C), and Symbol Shift.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; NextCPM Extended Keyboard Code Equates
;------------------------------------------------------------------------------
NEXT_KEY_EDIT		EQU	01BH	; Next Edit key generates ESC
NEXT_KEY_BREAK		EQU	003H	; Next Break key generates Ctrl+C
NEXT_KEY_DELETE		EQU	07FH	; Next Delete key generates 0x7F
NEXT_KEY_BS		EQU	008H	; Next Backspace generates 0x08

;------------------------------------------------------------------------------
; HAL_KEYBOARD_INIT: Initialize NextCPM keyboard scanner
;
; Purpose:
;   Ensures console keyboard state is clear and ready for input processing.
;
; Inputs:
;   None.
;
; Outputs:
;   None.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
HAL_KEYBOARD_INIT:
	XOR A
	RET

;------------------------------------------------------------------------------
; HAL_KEYBOARD_TRANSLATE: Translate NextCPM raw scan code to editor keycode
;
; Purpose:
;   Normalizes NextCPM keyboard codes into editor internal control codes
;   (e.g. mapping Delete to destructive Backspace or Delete forward).
;
; Inputs:
;   A = Raw ASCII character / scan code from GET_KEY.
;
; Outputs:
;   A = Normalized keycode.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; modifies AF.
;------------------------------------------------------------------------------
HAL_KEYBOARD_TRANSLATE:
	CP NEXT_KEY_DELETE
	RET NZ
	; Normalize 0x7F (Delete) to 0x08 (Backspace) if desired
	LD A,KEY_BACKSPACE
	RET
