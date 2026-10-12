;==============================================================================
; HAL_NEXT_KEYBOARD.ASM: Hardware Abstraction Layer - Native Next Keyboard
;
; Purpose:
;   Implements direct keyboard scanning, key status polling, and scan code
;   translation for Profile 3 (Native ZX Spectrum Next / NextZXOS).
;   Directly scans the 8x5 Sinclair keyboard matrix (ports 0xFEFE..0x7FFE)
;   without relying on Sinclair ROM system variables or interrupts.
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
HKI_WAIT_RELEASE:
	CALL HAL_KEYBOARD_POLL
	JR NZ,HKI_WAIT_RELEASE
	RET

;------------------------------------------------------------------------------
; HAL_KEYBOARD_POLL: Non-blocking check for keyboard input
;
; Purpose:
;   Directly reads port 0x00FE to test if any key is pressed across all
;   matrix rows simultaneously. If any key is down, confirms a non-modifier
;   key is pressed.
;
; Outputs:
;   A = 0xFF and Z=0 if non-modifier key ready; A = 0x00 and Z=1 if no key.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; modifies AF.
;------------------------------------------------------------------------------
HAL_KEYBOARD_POLL:
	XOR A
	IN A,(KEY_PORT_ULA)		; Select all 8 rows simultaneously
	CPL
	AND 01FH			; Any key in bits 0..4?
	RET Z				; Zero flag set = no key pressed

	; Key detected. Filter out standalone modifier keys (Caps/Sym Shift)
	PUSH BC
	LD BC,0FEFEH			; Row 0: CapsShift (bit 0), Z, X, C, V
	IN A,(C)
	CPL
	AND 01EH			; Check Z, X, C, V only
	JR NZ,HKP_KEY_READY

	LD BC,07FFEH		; Row 7: Space, SymShift (bit 1), M, N, B
	IN A,(C)
	CPL
	AND 01DH			; Check Space, M, N, B only
	JR NZ,HKP_KEY_READY

	; Check rows 1..6 (all 5 bits are characters/numbers)
	LD BC,0FDFEH			; Row 1: A, S, D, F, G
	IN A,(C)
	CPL
	AND 01FH
	JR NZ,HKP_KEY_READY

	LD BC,0FBFEH			; Row 2: Q, W, E, R, T
	IN A,(C)
	CPL
	AND 01FH
	JR NZ,HKP_KEY_READY

	LD BC,0F7FEH			; Row 3: 1, 2, 3, 4, 5
	IN A,(C)
	CPL
	AND 01FH
	JR NZ,HKP_KEY_READY

	LD BC,0EFFEH			; Row 4: 0, 9, 8, 7, 6
	IN A,(C)
	CPL
	AND 01FH
	JR NZ,HKP_KEY_READY

	LD BC,0DFFEH			; Row 5: P, O, I, U, Y
	IN A,(C)
	CPL
	AND 01FH
	JR NZ,HKP_KEY_READY

	LD BC,0BFFEH			; Row 6: Enter, L, K, J, H
	IN A,(C)
	CPL
	AND 01FH
	JR NZ,HKP_KEY_READY

	; Only a shift key was held
	POP BC
	XOR A
	RET

HKP_KEY_READY:
	POP BC
	LD A,0FFH
	OR A
	RET

;------------------------------------------------------------------------------
; HAL_KEYBOARD_GETKEY: Blocking keyboard read primitive
;
; Purpose:
;   Waits for a non-modifier key to be pressed, samples shift states,
;   decodes the 8x5 matrix position into an ASCII or control code,
;   and waits for key release with debounce.
;
; Outputs:
;   A = Normalized editor keycode.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
HAL_KEYBOARD_GETKEY:
	PUSH BC
	PUSH DE
	PUSH HL

HKG_WAIT_LOOP:
	CALL HAL_KEYBOARD_POLL
	JR Z,HKG_WAIT_LOOP

	; Check Caps Shift (Row 0, bit 0 == 0)
	LD BC,0FEFEH
	IN A,(C)
	RRA
	LD D,0				; D = Caps Shift flag
	JR C,HKG_NO_CAPS
	LD D,1
HKG_NO_CAPS:

	; Check Symbol Shift (Row 7, bit 1 == 0)
	LD BC,07FFEH
	IN A,(C)
	BIT 1,A
	LD E,0				; E = Symbol Shift flag
	JR NZ,HKG_NO_SYM
	LD E,1
HKG_NO_SYM:

	; Find which row and bit is pressed
	LD HL,MATRIX_ROW_TABLE
	LD B,8				; 8 rows
	LD C,0				; Row counter (0..7)
HKG_ROW_LOOP:
	PUSH BC
	LD B,(HL)			; High byte of port
	LD C,0FEH			; Port $FE
	IN A,(C)
	CPL
	AND 01FH
	POP BC
	PUSH AF
	LD A,C
	OR A
	JR NZ,HKG_NOT_ROW0
	POP AF
	AND 01EH			; Mask out Caps Shift (bit 0)
	JR HKG_CHECK_BITS
HKG_NOT_ROW0:
	CP 7				; Row 7?
	JR NZ,HKG_NOT_ROW7
	POP AF
	AND 01DH			; Mask out Symbol Shift (bit 1)
	JR HKG_CHECK_BITS
HKG_NOT_ROW7:
	POP AF
HKG_CHECK_BITS:
	OR A
	JR NZ,HKG_FOUND_ROW
	INC HL
	INC C
	DJNZ HKG_ROW_LOOP

	; If no character key found on this pass, re-poll
	JR HKG_WAIT_LOOP

HKG_FOUND_ROW:
	; A has bits 0..4 with pressed key bit set (1).
	; C has row index (0..7).
	; Find bit index (0..4) in A:
	LD B,0				; Bit counter
HKG_BIT_LOOP:
	RRA
	JR C,HKG_BIT_FOUND
	INC B
	JR HKG_BIT_LOOP

HKG_BIT_FOUND:
	; Key index = C * 5 + B (0..39)
	LD A,C
	ADD A,A				; * 2
	ADD A,A				; * 4
	ADD A,C				; * 5
	ADD A,B				; + B -> 0..39

	; Select table:
	; If E != 0: Symbol shifted table
	; Else if D != 0: Caps shifted table
	; Else: Unshifted table
	LD HL,KEY_TABLE_UNSHIFTED
	LD C,A
	LD B,0
	LD A,E
	OR A
	JR Z,HKG_CHECK_CAPS_TABLE
	LD HL,KEY_TABLE_SYMBOL
	JR HKG_LOOKUP
HKG_CHECK_CAPS_TABLE:
	LD A,D
	OR A
	JR Z,HKG_LOOKUP
	LD HL,KEY_TABLE_CAPS
HKG_LOOKUP:
	ADD HL,BC
	LD A,(HL)			; A = decoded keycode

	; Save decoded key in stack temp
	PUSH AF

	; Wait for key release (debounce)
HKG_RELEASE_WAIT:
	CALL HAL_KEYBOARD_POLL
	JR NZ,HKG_RELEASE_WAIT

	POP AF
	POP HL
	POP DE
	POP BC
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
	RET

;------------------------------------------------------------------------------
; Keyboard Row Port Table & Key Mapping Lookup Tables (40 keys each)
;------------------------------------------------------------------------------
MATRIX_ROW_TABLE:
	DB	0FEH, 0FDH, 0FBH, 0F7H, 0EFH, 0DFH, 0BFH, 07FH

; Unshifted table (40 bytes)
KEY_TABLE_UNSHIFTED:
	; Row 0: Caps, Z, X, C, V
	DB	0, 'z', 'x', 'c', 'v'
	; Row 1: A, S, D, F, G
	DB	'a', 's', 'd', 'f', 'g'
	; Row 2: Q, W, E, R, T
	DB	'q', 'w', 'e', 'r', 't'
	; Row 3: 1, 2, 3, 4, 5
	DB	'1', '2', '3', '4', '5'
	; Row 4: 0, 9, 8, 7, 6
	DB	'0', '9', '8', '7', '6'
	; Row 5: P, O, I, U, Y
	DB	'p', 'o', 'i', 'u', 'y'
	; Row 6: Enter, L, K, J, H
	DB	13, 'l', 'k', 'j', 'h'
	; Row 7: Space, Sym, M, N, B
	DB	' ', 0, 'm', 'n', 'b'

; Caps Shifted table (40 bytes)
KEY_TABLE_CAPS:
	; Row 0: Caps, Z, X, C, V
	DB	0, 'Z', 'X', 'C', 'V'
	; Row 1: A, S, D, F, G
	DB	'A', 'S', 'D', 'F', 'G'
	; Row 2: Q, W, E, R, T
	DB	'Q', 'W', 'E', 'R', 'T'
	; Row 3: Edit(ESC), CapsLock, TrueVid, InvVid, Left(WordStar Left)
	DB	KEY_ESCAPE, '2', '3', '4', KEY_WORDSTAR_LEFT
	; Row 4: Delete(Del), Graph, Right, Up, Down
	DB	KEY_WORDSTAR_DEL, '9', KEY_WORDSTAR_RIGHT
	DB	KEY_WORDSTAR_UP, KEY_WORDSTAR_DOWN
	; Row 5: P, O, I, U, Y
	DB	'P', 'O', 'I', 'U', 'Y'
	; Row 6: Enter, L, K, J, H
	DB	13, 'L', 'K', 'J', 'H'
	; Row 7: Break(Ctrl+C), Sym, M, N, B
	DB	KEY_CTRL_C, 0, 'M', 'N', 'B'

; Symbol Shifted table (40 bytes)
KEY_TABLE_SYMBOL:
	; Row 0: Caps, :, Ctrl+X, Ctrl+C, /
	DB	0, ':', KEY_WORDSTAR_DOWN, KEY_CTRL_C, '/'
	; Row 1: ~, |, \, {, }
	DB	'~', '|', '\\', '{', '}'
	; Row 2: Ctrl+Q, Ctrl+W, Ctrl+E, <, >
	DB	KEY_CTRL_Q, KEY_CTRL_W, KEY_WORDSTAR_UP, '<', '>'
	; Row 3: !, @, #, $, %
	DB	'!', '@', '#', '$', '%'
	; Row 4: _, ), (, 39, '&'
	DB	'_', ')', '(', 39, '&'
	; Row 5: ", ;, Tab, ], [
	DB	'"', ';', KEY_TAB, ']', '['
	; Row 6: Enter, =, +, -, ^
	DB	13, '=', '+', '-', '^'
	; Row 7: Space, Sym, ., ,, *
	DB	' ', 0, '.', ',', '*'

; End of HAL_NEXT_KEYBOARD.ASM
