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

	; Reset ANSI decoder state
	XOR A
	LD (ANSI_STATE),A
	LD (ANSI_PARAM1),A
	LD (ANSI_PARAM2),A
	LD (ANSI_PARAM_IDX),A
	LD (ANSI_IS_PRIV),A
	LD A,038H
	LD (CURRENT_ATTR),A

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
; ANSI Terminal Sequence Parser State Definitions & Variables
;------------------------------------------------------------------------------
ANSI_STATE_NORMAL	EQU	0
ANSI_STATE_ESC		EQU	1
ANSI_STATE_CSI		EQU	2

;------------------------------------------------------------------------------
; NATIVE_CONOUT: Emit character to native Next screen stream with ANSI decoding
;
; Purpose:
;   Parses ANSI escape sequences emitted by the editor core (clear screen,
;   cursor positioning, reverse video, clear to EOL) and translates them into
;   direct hardware operations and Sinclair screen driver control codes.
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
	PUSH BC
	PUSH DE
	PUSH HL

	IFDEF TEST_UART_BRIDGE
	; Mirror raw console stream character to Next hardware UART
	CALL HAL_NEXT_UART_TX
	ENDIF

	; Keep Sinclair ROM scroll counter at 255 to prevent "scroll?" prompt
	LD A,0FFH
	LD (05C8CH),A

	LD A,(ANSI_STATE)
	CP ANSI_STATE_ESC
	JR Z,ACO_STATE_ESC
	CP ANSI_STATE_CSI
	JP Z,ACO_STATE_CSI

	;----------------------------------------------------------------------
	; ANSI_STATE_NORMAL
	;----------------------------------------------------------------------
	LD A,C
	CP 27				; ESC byte?
	JR NZ,ACO_NORMAL_CHAR

	LD A,ANSI_STATE_ESC
	LD (ANSI_STATE),A
	JP ACO_DONE

ACO_NORMAL_CHAR:
	; Prevent Sinclair ROM scroll overflow at bottom-right of display.
	; In Sinclair sysvars (05C88H): High = 24 - row, Low = 33 - col
	LD A,(05C89H)			; High byte (24 - row)
	DEC A				; If row == 23 (bottom row), DEC A -> 0
	JR NZ,ACO_DO_PRINT

	LD A,(05C88H)			; Low byte (33 - col)
	CP 3				; If col >= 31 (low <= 2), drop char
	JP C,ACO_DONE

ACO_DO_PRINT:
	LD A,C
	RST ZX_RST_PRINT_CHAR
	JP ACO_DONE

	;----------------------------------------------------------------------
	; ANSI_STATE_ESC: Expecting '['
	;----------------------------------------------------------------------
ACO_STATE_ESC:
	LD A,C
	CP '['				; CSI intro?
	JR NZ,ACO_RESET_STATE

	LD A,ANSI_STATE_CSI
	LD (ANSI_STATE),A
	XOR A
	LD (ANSI_PARAM1),A
	LD (ANSI_PARAM2),A
	LD (ANSI_PARAM_IDX),A
	LD (ANSI_IS_PRIV),A
	JP ACO_DONE

	;----------------------------------------------------------------------
	; ANSI_STATE_CSI: Parameter parsing & command dispatch
	;----------------------------------------------------------------------
ACO_STATE_CSI:
	LD A,C
	CP '?'				; Private mode prefix (e.g. ?25h)
	JR NZ,ACO_CSI_NOT_PRIV
	LD A,1
	LD (ANSI_IS_PRIV),A
	JP ACO_DONE

ACO_CSI_NOT_PRIV:
	CP ';'				; Parameter separator
	JR NZ,ACO_CSI_NOT_SEMI
	LD A,1
	LD (ANSI_PARAM_IDX),A
	JP ACO_DONE

ACO_CSI_NOT_SEMI:
	CP '0'
	JR C,ACO_CSI_CMD
	CP '9'+1
	JR NC,ACO_CSI_CMD

	; Numeric digit: param = param * 10 + digit
	SUB '0'
	LD D,A
	LD A,(ANSI_PARAM_IDX)
	OR A
	JR NZ,ACO_ACCUM_P2

	LD A,(ANSI_PARAM1)
	LD E,A
	ADD A,A				; * 2
	ADD A,A				; * 4
	ADD A,E				; * 5
	ADD A,A				; * 10
	ADD A,D
	LD (ANSI_PARAM1),A
	JP ACO_DONE

ACO_ACCUM_P2:
	LD A,(ANSI_PARAM2)
	LD E,A
	ADD A,A				; * 2
	ADD A,A				; * 4
	ADD A,E				; * 5
	ADD A,A				; * 10
	ADD A,D
	LD (ANSI_PARAM2),A
	JP ACO_DONE

ACO_CSI_CMD:
	CP 'H'				; Cursor position: ESC [ r ; c H
	JP Z,ACO_CMD_LOCATE
	CP 'f'
	JP Z,ACO_CMD_LOCATE
	CP 'J'				; Erase display: ESC [ 2 J
	JP Z,ACO_CMD_CLEAR
	CP 'K'				; Clear line to EOL: ESC [ K
	JP Z,ACO_CMD_CLEAR_EOL
	CP 'm'				; Graphic rendition: ESC [ 7 m / 0 m
	JP Z,ACO_CMD_SGR
	CP 'l'				; Reset mode
	JR Z,ACO_RESET_STATE
	CP 'h'				; Set mode
	JR Z,ACO_RESET_STATE

ACO_RESET_STATE:
	XOR A
	LD (ANSI_STATE),A
	JP ACO_DONE

;------------------------------------------------------------------------------
; ACO_CMD_LOCATE: Position cursor via Sinclair AT code (22, row, col)
;------------------------------------------------------------------------------
ACO_CMD_LOCATE:
	XOR A
	LD (ANSI_STATE),A

	; Row (1-based, default 1) -> Sinclair 0-based row (0..23)
	LD A,(ANSI_PARAM1)
	OR A
	JR NZ,ACL_R_NZ
	INC A
ACL_R_NZ:
	DEC A
	CP 24
	JR C,ACL_R_OK
	LD A,23
ACL_R_OK:
	LD D,A				; D = Sinclair Row

	; Col (1-based, default 1) -> Sinclair 0-based col (0..31)
	LD A,(ANSI_PARAM2)
	OR A
	JR NZ,ACL_C_NZ
	INC A
ACL_C_NZ:
	DEC A
	CP 32
	JR C,ACL_C_OK
	LD A,31
ACL_C_OK:
	LD E,A				; E = Sinclair Col

	LD A,22
	RST ZX_RST_PRINT_CHAR
	LD A,D
	RST ZX_RST_PRINT_CHAR
	LD A,E
	RST ZX_RST_PRINT_CHAR
	JP ACO_DONE

;------------------------------------------------------------------------------
; ACO_CMD_CLEAR: Clear entire screen display and home cursor
;------------------------------------------------------------------------------
ACO_CMD_CLEAR:
	XOR A
	LD (ANSI_STATE),A

	; Clear 6144-byte ULA pixel bitmap
	LD HL,04000H
	LD (HL),0
	LD DE,04001H
	LD BC,017FFH
	LDIR

	; Set 768-byte ULA attribute cells
	LD A,(CURRENT_ATTR)
	LD (HL),A
	LD BC,002FFH
	LDIR

	; Reset Sinclair ROM scroll counter and home cursor
	LD A,0FFH
	LD (05C8CH),A
	LD HL,01821H			; Line 24, Col 33 -> Sinclair (0, 0)
	LD (05C88H),HL
	LD HL,04000H
	LD (05C84H),HL
	JP ACO_DONE

;------------------------------------------------------------------------------
; ACO_CMD_CLEAR_EOL: Clear to end of line from current column
;------------------------------------------------------------------------------
ACO_CMD_CLEAR_EOL:
	XOR A
	LD (ANSI_STATE),A

	; S_POSN: L = 33 - col, H = 24 - row
	LD HL,(05C88H)
	LD A,L
	DEC A
	JP Z,ACO_DONE
	JP C,ACO_DONE

	PUSH HL
	LD B,A
ACE_SP_LOOP:
	PUSH BC
	LD A,' '
	RST ZX_RST_PRINT_CHAR
	POP BC
	DJNZ ACE_SP_LOOP

	; Restore original cursor row & col
	POP HL
	LD A,24
	SUB H
	LD D,A
	LD A,33
	SUB L
	LD E,A
	LD A,22
	RST ZX_RST_PRINT_CHAR
	LD A,D
	RST ZX_RST_PRINT_CHAR
	LD A,E
	RST ZX_RST_PRINT_CHAR
	JP ACO_DONE

;------------------------------------------------------------------------------
; ACO_CMD_SGR: Select Graphic Rendition (Inverse / Normal)
;------------------------------------------------------------------------------
ACO_CMD_SGR:
	XOR A
	LD (ANSI_STATE),A

	LD A,(ANSI_PARAM1)
	CP 7				; Inverse ON
	JR Z,ACS_INVERSE_ON
	CP 1				; Bold / Bright ON
	JR Z,ACS_BRIGHT_ON

	; Normal video (Inverse OFF)
	LD A,20
	RST ZX_RST_PRINT_CHAR
	XOR A
	RST ZX_RST_PRINT_CHAR
	LD A,038H			; White paper (7), black ink (0)
	LD (CURRENT_ATTR),A
	JP ACO_DONE

ACS_INVERSE_ON:
	LD A,20
	RST ZX_RST_PRINT_CHAR
	LD A,1
	RST ZX_RST_PRINT_CHAR
	LD A,007H			; Black paper (0), white ink (7)
	LD (CURRENT_ATTR),A
	JP ACO_DONE

ACS_BRIGHT_ON:
	LD A,19
	RST ZX_RST_PRINT_CHAR
	LD A,1
	RST ZX_RST_PRINT_CHAR
	JP ACO_DONE

ACO_DONE:
	POP HL
	POP DE
	POP BC
	RET

	IFDEF TEST_UART_BRIDGE
;------------------------------------------------------------------------------
; HAL_NEXT_UART_TX: Transmit character in C to Next hardware UART (Port $133B)
;
; Inputs:
;   C = Character byte to transmit.
;
; Preserves:
;   BC, DE, HL, AF.
;------------------------------------------------------------------------------
HAL_NEXT_UART_TX:
	PUSH AF
	PUSH BC
	PUSH DE
	LD D,100			; Bounded poll timeout
HNUT_WAIT:
	LD BC,0133BH			; UART TX / Status port
	IN A,(C)
	BIT 1,A				; Bit 1: TX busy (1 = busy, 0 = ready)
	JR Z,HNUT_SEND
	DEC D
	JR NZ,HNUT_WAIT
	JR HNUT_DONE
HNUT_SEND:
	LD A,C
	OUT (C),A			; Transmit byte to UART TX
HNUT_DONE:
	POP DE
	POP BC
	POP AF
	RET
	ENDIF

; Working storage for ANSI parser
ANSI_STATE:		DB	0
ANSI_PARAM1:		DB	0
ANSI_PARAM2:		DB	0
ANSI_PARAM_IDX:		DB	0
ANSI_IS_PRIV:		DB	0
CURRENT_ATTR:		DB	038H

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
