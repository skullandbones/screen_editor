;==============================================================================
; HAL_NEXT_CONSOLE.ASM: Hardware Abstraction Layer - Native Next Console Driver
;
; Purpose:
;   Implements direct hardware screen management, ANSI terminal emulation, and
;   console character I/O for Profile 3 (Native ZX Spectrum Next / NextZXOS).
;   Controls NextReg Turbo speed (28 MHz), hardware text layers, and Sinclair
;   screen stream channels.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; ZX Spectrum Next Hardware Register Ports & Constants
;------------------------------------------------------------------------------
NEXT_REG_TURBO_MODE	EQU	007H	; NextReg 0x07: CPU Turbo Mode (0..3)
NEXT_TURBO_28MHZ	EQU	003H	; 28 MHz CPU clock frequency setting
NEXT_TURBO_14MHZ	EQU	002H	; 14 MHz CPU clock frequency setting

; Sinclair / NextZXOS Console Restart Vectors
ZX_RST_PRINT_CHAR	EQU	0010H	; RST 10H: Output char in A to screen

;------------------------------------------------------------------------------
; HAL Console Entry Point Aliases & Vectors
;------------------------------------------------------------------------------
HAL_CONSOLE_POLLKEY	EQU	CHECK_KEY_READY
HAL_CONSOLE_LOCATE	EQU	LOCATE_RC

;------------------------------------------------------------------------------
; HAL_CONSOLE_INIT / TERM_INIT: Initialize Next hardware console and screen mode
;
; Purpose:
;   Accelerates CPU to 28 MHz via NextReg 0x07 for instantaneous redraws.
;   Initializes direct console vectors, enables normal video attributes,
;   restores cursor visibility, and clears the display.
;
; Inputs:
;   None.
;
; Outputs:
;   Screen cleared; cursor at (1,1); CPU at 28 MHz.
;
; Preserves / Modifies:
;   Preserves BC, HL; clobbers AF, DE.
;------------------------------------------------------------------------------
HAL_CONSOLE_INIT:
TERM_INIT:
	; Set CPU speed to 28 MHz for maximum performance
	PUSH BC
	LD BC,NEXT_PORT_REG_SELECT
	LD A,NEXT_REG_TURBO_MODE
	OUT (C),A
	LD BC,NEXT_PORT_REG_DATA
	LD A,NEXT_TURBO_28MHZ
	OUT (C),A
	POP BC

	; Initialize console vectors
	CALL INIT_BIOS_JUMPS

	; Reset terminal state
	CALL TERM_INVERSE_OFF
	CALL TERM_SHOW_CURSOR
	JP TERM_CLEAR_SCREEN

;------------------------------------------------------------------------------
; Centralized ANSI Terminal Escape Sequences for Native ZX Spectrum Next
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; HAL_CONSOLE_INVERSE_ON / TERM_INVERSE_ON: Enable reverse video
;------------------------------------------------------------------------------
HAL_CONSOLE_INVERSE_ON:
TERM_INVERSE_ON:
	LD DE,STR_INVERSE_ON
	JP PRINT_STR

;------------------------------------------------------------------------------
; HAL_CONSOLE_INVERSE_OFF / TERM_INVERSE_OFF: Disable reverse video
;------------------------------------------------------------------------------
HAL_CONSOLE_INVERSE_OFF:
TERM_INVERSE_OFF:
	LD DE,STR_INVERSE_OFF
	JP PRINT_STR

;------------------------------------------------------------------------------
; HAL_CONSOLE_HIDE_CURSOR / TERM_HIDE_CURSOR: Hide hardware terminal cursor
;------------------------------------------------------------------------------
HAL_CONSOLE_HIDE_CURSOR:
TERM_HIDE_CURSOR:
	LD DE,STR_HIDE_CURSOR
	JP PRINT_STR

;------------------------------------------------------------------------------
; HAL_CONSOLE_SHOW_CURSOR / TERM_SHOW_CURSOR: Show hardware terminal cursor
;------------------------------------------------------------------------------
HAL_CONSOLE_SHOW_CURSOR:
TERM_SHOW_CURSOR:
	LD DE,STR_SHOW_CURSOR
	JP PRINT_STR

;------------------------------------------------------------------------------
; HAL_CONSOLE_CLEAR / TERM_CLEAR_SCREEN: Erase entire display
;------------------------------------------------------------------------------
HAL_CONSOLE_CLEAR:
TERM_CLEAR_SCREEN:
	LD DE,STR_CLEAR_SCREEN
	JP PRINT_STR

;------------------------------------------------------------------------------
; HAL_CONSOLE_CLEAR_EOL / TERM_CLEAR_TO_EOL: Clear to end of line
;------------------------------------------------------------------------------
HAL_CONSOLE_CLEAR_EOL:
TERM_CLEAR_EOL:
	LD DE,STR_CLEAR_EOL
	JP PRINT_STR

;------------------------------------------------------------------------------
; TERM_HOME: Position cursor at top-left home position (row 1, col 1)
;------------------------------------------------------------------------------
TERM_HOME:
	LD DE,STR_HOME
	JP PRINT_STR

;------------------------------------------------------------------------------
; INIT_BIOS_JUMPS: Initialize native console jump table vectors
;
; Purpose:
;   Under Native NextZXOS, redirects BIOS console vectors to internal native
;   driver routines (NATIVE_CONST, NATIVE_CONIN, NATIVE_CONOUT).
;------------------------------------------------------------------------------
INIT_BIOS_JUMPS:
	LD HL,NATIVE_CONST
	LD (BIOS_CONST_VEC),HL
	LD HL,NATIVE_CONIN
	LD (BIOS_CONIN_VEC),HL
	LD HL,NATIVE_CONOUT
	LD (BIOS_CONOUT_VEC),HL
	RET

;------------------------------------------------------------------------------
; NATIVE_CONOUT: Emit character to native Next screen stream
;
; Inputs:
;   C = Character to emit.
;
; Outputs:
;   None.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; modifies AF.
;------------------------------------------------------------------------------
NATIVE_CONOUT:
	LD A,C
	RST ZX_RST_PRINT_CHAR
	RET

;------------------------------------------------------------------------------
; NATIVE_CONST: Poll native console keyboard status
;
; Outputs:
;   A = 0xFF and Z=0 if key ready; A = 0x00 and Z=1 if no key.
;------------------------------------------------------------------------------
NATIVE_CONST:
	JP HAL_KEYBOARD_POLL

;------------------------------------------------------------------------------
; NATIVE_CONIN: Wait for and read single keystroke from native keyboard
;
; Outputs:
;   A = Character or translated keycode.
;------------------------------------------------------------------------------
NATIVE_CONIN:
	JP HAL_KEYBOARD_GETKEY

;------------------------------------------------------------------------------
; HAL_CONSOLE_PUTS / PRINT_STR: Print string to native Next console
;
; Inputs:
;   DE = Pointer to '$'-terminated or null-terminated string.
;
; Outputs:
;   String transmitted to console.
;
; Preserves / Modifies:
;   Preserves BC; clobbers AF, DE, HL.
;------------------------------------------------------------------------------
HAL_CONSOLE_PUTS:
PRINT_STR:
	PUSH BC
	PUSH DE
	PUSH HL
	EX DE,HL			; HL = pointer to string
PRINT_STR_LOOP:
	LD A,(HL)
	OR A
	JR Z,PRINT_STR_DONE
	CP '$'
	JR Z,PRINT_STR_DONE
	CALL PUTC
	INC HL
	JR PRINT_STR_LOOP
PRINT_STR_DONE:
	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; HAL_CONSOLE_PUTC / PUTC: Emit single character to native Next console
;
; Inputs:
;   A = ASCII character to transmit.
;
; Outputs:
;   Character displayed on screen.
;
; Preserves / Modifies:
;   Preserves all registers: AF, BC, DE, HL.
;------------------------------------------------------------------------------
HAL_CONSOLE_PUTC:
PUTC:
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL
	LD C,A				; C = character
	LD HL,(BIOS_CONOUT_VEC)
	CALL CALL_HL
	POP HL
	POP DE
	POP BC
	POP AF
	RET

;------------------------------------------------------------------------------
; HAL_CONSOLE_GETKEY / GET_KEY: Read single keystroke from native keyboard
;
; Outputs:
;   A = ASCII character or scan code byte received.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
HAL_CONSOLE_GETKEY:
GET_KEY:
	PUSH BC
	PUSH DE
	PUSH HL
	LD HL,(BIOS_CONIN_VEC)
	CALL CALL_HL			; Returns A = character
	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; CALL_HL: Indirect subroutine call helper
;------------------------------------------------------------------------------
CALL_HL:
	JP (HL)

; End of HAL_NEXT_CONSOLE.ASM
