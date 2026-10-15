;==============================================================================
; HAL_NEXTCPM_CONSOLE.ASM: Hardware Abstraction Layer - NextCPM Console Driver
;
; Purpose:
;   Implements console terminal escape sequences, direct BIOS character I/O,
;   and 80-column display management for Profile 2 (CP/M on ZX Spectrum Next).
;   Utilizes NextCPM ANSI/VT52 terminal emulation and fast console vectors.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; HAL Console Entry Point Aliases & Vectors
;------------------------------------------------------------------------------
HAL_CONSOLE_POLLKEY	EQU	CHECK_KEY_READY
HAL_CONSOLE_LOCATE	EQU	LOCATE_RC

;------------------------------------------------------------------------------
; HAL_CONSOLE_INIT / TERM_INIT: Initialize NextCPM console and screen mode
;
; Purpose:
;   Restores normal attributes, shows cursor, and clears screen to prepare
;   NextCPM 80-column display for editor viewports.
;
; Inputs:
;   None.
;
; Outputs:
;   Screen cleared, cursor at (1,1), inverse video disabled.
;
; Preserves / Modifies:
;   Preserves BC, HL; clobbers AF, DE.
;------------------------------------------------------------------------------
HAL_CONSOLE_INIT:
TERM_INIT:
	CALL HAL_KEYBOARD_INIT
	CALL TERM_INVERSE_OFF
	CALL TERM_SHOW_CURSOR
	JP TERM_CLEAR_SCREEN

;------------------------------------------------------------------------------
; Centralized ANSI Terminal Escape Sequences for NextCPM
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
;
; The NextCPM console emulates a Zenith Z-19 terminal plus the Locomotive
; Spectrum +3 extensions. It does NOT implement the DEC private mode
; sequence ESC [ ? 25 l, so the +3 sequence ESC f (disable cursor blob) is
; used instead (Bug 2.2.15).
;------------------------------------------------------------------------------
HAL_CONSOLE_HIDE_CURSOR:
TERM_HIDE_CURSOR:
	LD DE,STR_NEXTCPM_HIDE_CURSOR
	JP PRINT_STR

;------------------------------------------------------------------------------
; HAL_CONSOLE_SHOW_CURSOR / TERM_SHOW_CURSOR: Show hardware terminal cursor
;
; Uses the Spectrum +3 sequence ESC e (enable cursor blob) supported by the
; NextCPM console instead of the unsupported ESC [ ? 25 h (Bug 2.2.15).
;------------------------------------------------------------------------------
HAL_CONSOLE_SHOW_CURSOR:
TERM_SHOW_CURSOR:
	LD DE,STR_NEXTCPM_SHOW_CURSOR
	JP PRINT_STR

STR_NEXTCPM_HIDE_CURSOR:	DB	27,"f","$"
STR_NEXTCPM_SHOW_CURSOR:	DB	27,"e","$"

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
; INIT_BIOS_JUMPS: Resolve direct NextCPM BIOS console jump table vectors
;
; Purpose:
;   Queries CP/M BIOS warm boot vector at 0001H to compute base addresses
;   for direct BIOS console routines (CONST=+6, CONIN=+9, CONOUT=+12).
;   Redirects BIOS_CONST_VEC and BIOS_CONIN_VEC through NEXTCPM_CONST and
;   NEXTCPM_CONIN to support multi-byte escape sequence buffering for
;   arrow keys.
;------------------------------------------------------------------------------
INIT_BIOS_JUMPS:
	LD HL,(0001H)			; HL = Address of BIOS WBOOT (+3)
	DEC HL
	DEC HL
	DEC HL				; HL = BIOS Base (BOOT, +0)
	LD DE,6
	ADD HL,DE			; HL = BIOS CONST (+6)
	LD (REAL_BIOS_CONST_VEC),HL
	INC HL
	INC HL
	INC HL				; HL = BIOS CONIN (+9)
	LD (REAL_BIOS_CONIN_VEC),HL
	INC HL
	INC HL
	INC HL				; HL = BIOS CONOUT (+12)
	LD (BIOS_CONOUT_VEC),HL

	; Redirect console input vectors through sequence buffer translator
	LD HL,NEXTCPM_CONST
	LD (BIOS_CONST_VEC),HL
	LD HL,NEXTCPM_CONIN
	LD (BIOS_CONIN_VEC),HL
	RET

;------------------------------------------------------------------------------
; NEXTCPM_CONST: Check input readiness including pending sequence buffer
;
; Outputs:
;   A = 0xFF, Z=0 if key available; A = 0x00, Z=1 if no key.
;------------------------------------------------------------------------------
NEXTCPM_CONST:
	; Check if escape sequence buffer has pending bytes
	LD A,(KEY_SEQ_LEN)
	OR A
	JR Z,NCC_CHECK_BIOS
	LD A,0FFH
	OR A
	RET

NCC_CHECK_BIOS:
	LD HL,(REAL_BIOS_CONST_VEC)
	CALL CALL_HL			; A = 0xFF if char ready, 0x00 if not
	OR A
	RET

;------------------------------------------------------------------------------
; NEXTCPM_CONIN: Read next character from sequence buffer or BIOS console
;
; Outputs:
;   A = character / normalized keycode.
;------------------------------------------------------------------------------
NEXTCPM_CONIN:
	; Check if escape sequence buffer has pending bytes
	LD A,(KEY_SEQ_LEN)
	OR A
	JR Z,NCC_READ_BIOS

	; Consume next pending escape sequence byte
	PUSH HL
	LD HL,(KEY_SEQ_PTR)
	LD A,(HL)
	INC HL
	LD (KEY_SEQ_PTR),HL
	LD HL,KEY_SEQ_LEN
	DEC (HL)
	POP HL
	RET

NCC_READ_BIOS:
	LD HL,(REAL_BIOS_CONIN_VEC)
	CALL CALL_HL			; Returns A = character
	CALL HAL_KEYBOARD_TRANSLATE
	RET

;------------------------------------------------------------------------------
; HAL_CONSOLE_PUTS / PRINT_STR: Print string to NextCPM console
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
; HAL_CONSOLE_PUTC / PUTC: Emit single character to NextCPM console
;------------------------------------------------------------------------------
HAL_CONSOLE_PUTC:
PUTC:
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL
	LD C,A				; C = character for BIOS CONOUT
	LD HL,(BIOS_CONOUT_VEC)
	CALL CALL_HL
	POP HL
	POP DE
	POP BC
	POP AF
	RET



;------------------------------------------------------------------------------
; HAL_CONSOLE_GETKEY / GET_KEY: Read single keystroke from NextCPM console
;------------------------------------------------------------------------------
HAL_CONSOLE_GETKEY:
GET_KEY:
	PUSH BC
	PUSH DE
	PUSH HL
	CALL NEXTCPM_CONIN
	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; CALL_HL: Indirect subroutine call helper
;------------------------------------------------------------------------------
CALL_HL:
	JP (HL)

;------------------------------------------------------------------------------
; Variables for Raw CP/M BIOS Vectors
;------------------------------------------------------------------------------
REAL_BIOS_CONST_VEC:	DW	0
REAL_BIOS_CONIN_VEC:	DW	0
