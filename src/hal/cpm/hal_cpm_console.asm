;==============================================================================
; HAL_CPM_CONSOLE.ASM: Hardware Abstraction Layer - CP/M & VT100 Console Driver
;
; Purpose:
;   Implements standard ANSI / VT100 console terminal escape sequences,
;   direct BIOS character input and output, and screen attribute management
;   for Profile 1 (Standard CP/M 2.2 / 3.0 / RomWBW).
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; HAL Console Entry Point Aliases & Vectors
;------------------------------------------------------------------------------
HAL_CONSOLE_POLLKEY	EQU	CHECK_KEY_READY
HAL_CONSOLE_LOCATE	EQU	LOCATE_RC

; TERM_INIT: Initialize terminal display attributes and clear screen
;
; Purpose:
;   Disables reverse video, restores cursor visibility, and clears screen.
;
; Call Usage / Protocol:
;   Called via CALL before repainting screen views.
;
; Inputs:
;   None
;
; Outputs:
;   Terminal attributes reset; screen cleared; cursor at (1,1).
;
; Preserves / Modifies:
;   Preserves BC, HL; clobbers AF, DE.
;------------------------------------------------------------------------------
HAL_CONSOLE_INIT:
TERM_INIT:
	CALL TERM_INVERSE_OFF
	CALL TERM_SHOW_CURSOR
	JP TERM_CLEAR_SCREEN

;------------------------------------------------------------------------------
; Centralized ANSI Terminal Escape Sequences
; Preserves all registers except AF (matching PRINT_STR conventions)
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; TERM_INVERSE_ON: Enable reverse video text attribute
;
; Purpose:
;   Transmits ANSI escape sequence ESC[7m to enable reverse video mode.
;
; Call Usage / Protocol:
;   Called via CALL before rendering status bar or highlighted elements.
;
; Inputs:
;   None
;
; Outputs:
;   Terminal attribute changed to inverse video.
;
; Preserves / Modifies:
;   Preserves BC, HL; clobbers AF, DE.
;------------------------------------------------------------------------------
HAL_CONSOLE_INVERSE_ON:
TERM_INVERSE_ON:
	LD DE,STR_INVERSE_ON
	JP PRINT_STR

;------------------------------------------------------------------------------
; TERM_INVERSE_OFF: Disable reverse video text attribute
;
; Purpose:
;   Transmits ANSI escape sequence ESC[0m to restore normal video attributes.
;
; Call Usage / Protocol:
;   Called via CALL after rendering status bar or highlighted elements.
;
; Inputs:
;   None
;
; Outputs:
;   Terminal attributes reset to normal.
;
; Preserves / Modifies:
;   Preserves BC, HL; clobbers AF, DE.
;------------------------------------------------------------------------------
HAL_CONSOLE_INVERSE_OFF:
TERM_INVERSE_OFF:
	LD DE,STR_INVERSE_OFF
	JP PRINT_STR

;------------------------------------------------------------------------------
; TERM_HIDE_CURSOR: Hide hardware terminal cursor
;
; Purpose:
;   Transmits ANSI escape sequence ESC[?25l to hide the hardware cursor
;   during screen updates and dialog rendering to eliminate cursor flicker.
;
; Call Usage / Protocol:
;   Called via CALL before redrawing screen regions or modal pop-ups.
;
; Inputs:
;   None
;
; Outputs:
;   Hardware cursor hidden.
;
; Preserves / Modifies:
;   Preserves BC, HL; clobbers AF, DE.
;------------------------------------------------------------------------------
HAL_CONSOLE_HIDE_CURSOR:
TERM_HIDE_CURSOR:
	LD DE,STR_HIDE_CURSOR
	JP PRINT_STR

;------------------------------------------------------------------------------
; TERM_SHOW_CURSOR: Restore hardware terminal cursor visibility
;
; Purpose:
;   Transmits ANSI escape sequence ESC[?25h to re-enable hardware cursor
;   visibility after screen redraw operations are complete.
;
; Call Usage / Protocol:
;   Called via CALL after completing screen updates.
;
; Inputs:
;   None
;
; Outputs:
;   Hardware cursor visible.
;
; Preserves / Modifies:
;   Preserves BC, HL; clobbers AF, DE.
;------------------------------------------------------------------------------
HAL_CONSOLE_SHOW_CURSOR:
TERM_SHOW_CURSOR:
	LD DE,STR_SHOW_CURSOR
	JP PRINT_STR

;------------------------------------------------------------------------------
; TERM_CLEAR_SCREEN: Clear entire terminal display screen
;
; Purpose:
;   Transmits ANSI escape sequence ESC[2J to erase the entire terminal screen.
;
; Call Usage / Protocol:
;   Called via CALL when performing complete full-screen repaints.
;
; Inputs:
;   None
;
; Outputs:
;   Terminal screen cleared.
;
; Preserves / Modifies:
;   Preserves BC, HL; clobbers AF, DE.
;------------------------------------------------------------------------------
HAL_CONSOLE_CLEAR:
TERM_CLEAR_SCREEN:
	LD DE,STR_CLEAR_SCREEN
	JP PRINT_STR

;------------------------------------------------------------------------------
; TERM_CLEAR_EOL: Clear from cursor position to end of current line
;
; Purpose:
;   Transmits ANSI escape sequence ESC[K to clear characters from the current
;   cursor column to the right margin of the terminal row.
;
; Call Usage / Protocol:
;   Called via CALL during line rendering and dialog line clearing.
;
; Inputs:
;   None
;
; Outputs:
;   Remainder of current terminal row erased.
;
; Preserves / Modifies:
;   Preserves BC, HL; clobbers AF, DE.
;------------------------------------------------------------------------------
HAL_CONSOLE_CLEAR_EOL:
TERM_CLEAR_EOL:
	LD DE,STR_CLEAR_EOL
	JP PRINT_STR

;------------------------------------------------------------------------------
; TERM_HOME: Position cursor at top-left home position (row 1, col 1)
;
; Purpose:
;   Transmits ANSI escape sequence ESC[H to place cursor at row 1, col 1.
;
; Call Usage / Protocol:
;   Called via CALL prior to sequential top-down screen rendering.
;
; Inputs:
;   None
;
; Outputs:
;   Hardware cursor relocated to home position.
;
; Preserves / Modifies:
;   Preserves BC, HL; clobbers AF, DE.
;------------------------------------------------------------------------------
TERM_HOME:
	LD DE,STR_HOME
	JP PRINT_STR

;------------------------------------------------------------------------------
; INIT_BIOS_JUMPS: Resolve direct CP/M BIOS console jump table vectors
;
; Purpose:
;   Queries CP/M BIOS warm boot vector at 0001H to compute base addresses
;   for direct BIOS console routines (CONST=+6, CONIN=+9, CONOUT=+12),
;   bypassing BDOS console overhead and control-character filtering.
;
; Call Usage / Protocol:
;   Called via CALL once during START initialization.
;
; Inputs:
;   Memory address 0001H (pointer to BIOS WBOOT).
;
; Outputs:
;   BIOS_CONST_VEC, BIOS_CONIN_VEC, BIOS_CONOUT_VEC initialized.
;
; Preserves / Modifies:
;   Preserves BC; clobbers AF, DE, HL.
;------------------------------------------------------------------------------
INIT_BIOS_JUMPS:
	LD HL,(0001H)			; HL = Address of BIOS WBOOT (+3)
	DEC HL
	DEC HL
	DEC HL				; HL = BIOS Base (BOOT, +0)
	LD DE,6
	ADD HL,DE			; HL = BIOS CONST (+6)
	LD (BIOS_CONST_VEC),HL
	INC HL
	INC HL
	INC HL				; HL = BIOS CONIN (+9)
	LD (BIOS_CONIN_VEC),HL
	INC HL
	INC HL
	INC HL				; HL = BIOS CONOUT (+12)
	LD (BIOS_CONOUT_VEC),HL
	RET

;------------------------------------------------------------------------------
; PRINT_STR: Print null-terminated or '$'-terminated string to console
;
; Purpose:
;   Iterates through string pointed to by DE, outputting characters via PUTC
;   until encountering a null (0x00) or '$' character.
;
; Call Usage / Protocol:
;   Standard string printing routine invoked throughout SE.COM.
;
; Inputs:
;   DE = Pointer to null-terminated or '$'-terminated ASCII string.
;
; Outputs:
;   String emitted to console.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
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
; PUTC: Emit single character to console via direct BIOS CONOUT
;
; Purpose:
;   Sends byte in register A directly to BIOS CONOUT jump vector.
;
; Call Usage / Protocol:
;   Fundamental character output primitive called throughout SE.COM.
;
; Inputs:
;   A = ASCII character byte to output.
;
; Outputs:
;   Character transmitted to console.
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
	LD C,A				; C = character for BIOS CONOUT
	LD HL,(BIOS_CONOUT_VEC)
	CALL CALL_HL
	POP HL
	POP DE
	POP BC
	POP AF
	RET

;------------------------------------------------------------------------------
; GET_KEY: Wait for and read single keystroke from console via direct BIOS CONIN
;
; Purpose:
;   Invokes BIOS CONIN jump vector, blocking until a key is pressed.
;
; Call Usage / Protocol:
;   Fundamental blocking keyboard input primitive.
;
; Inputs:
;   None
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
;
; Purpose:
;   Performs JP (HL) to execute a subroutine whose address is loaded in HL.
;   Allows callers using CALL CALL_HL to effectively perform CALL (HL).
;
; Call Usage / Protocol:
;   Called via CALL CALL_HL.
;
; Inputs:
;   HL = Target subroutine entry address.
;
; Outputs:
;   Returns whatever target subroutine produces.
;
; Preserves / Modifies:
;   Stack return address preserved; registers modified per target subroutine.
;------------------------------------------------------------------------------
CALL_HL:
	JP (HL)

