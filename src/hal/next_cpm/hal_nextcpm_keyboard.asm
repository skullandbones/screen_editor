;==============================================================================
; HAL_NEXTCPM_KEYBOARD.ASM: Hardware Abstraction Layer - NextCPM Keyboard
;
; Purpose:
;   Implements keyboard translation, extended key decoding, and Next-specific
;   keyboard mapping for Profile 2 (CP/M on ZX Spectrum Next).
;   Handles dedicated arrow keys, Edit (ESC), Break (Ctrl+C), and Symbol Shift.
;   Disambiguates arrow keys from text editing control codes by scanning the
;   underlying hardware keyboard matrix (port 0x00FE).
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

; Hardware ULA Keyboard Port
KEY_PORT_ULA		EQU	000FEH	; ULA keyboard row port

; Escape sequence generator buffer for dedicated arrow keys
KEY_SEQ_BUF:		DB	0, 0
KEY_SEQ_LEN:		DB	0
KEY_SEQ_PTR:		DW	KEY_SEQ_BUF

;------------------------------------------------------------------------------
; HAL_KEYBOARD_INIT: Initialize NextCPM keyboard scanner
;
; Purpose:
;   Ensures console keyboard sequence buffer is clear and ready for input.
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
	LD (KEY_SEQ_LEN),A
	RET

;------------------------------------------------------------------------------
; HAL_KEYBOARD_TRANSLATE: Translate NextCPM raw scan code to editor keycode
;
; Purpose:
;   Normalizes NextCPM keyboard codes into editor internal control codes.
;   Preserves NEXT_KEY_DELETE (0x7F / KEY_DEL) without normalizing to
;   Backspace (0x08), enabling forward deletion and block deletion.
;   Detects directional arrow keys returned as CP/M line editing or WordStar
;   control codes (0x06=Right, 0x01=Left, 0x05=Up, 0x18=Down, 0x1F=Up,
;   0x1E=Down, 0x0B=Up) and translates them into standard ANSI CSI escape
;   sequences (ESC [ A/B/C/D) via KEY_SEQ_BUF.
;   Disambiguates directional control codes from genuine Ctrl key combinations
;   (Ctrl+F, Ctrl+A, Ctrl+E, Ctrl+X) by sampling ULA matrix port 0x00FE.
;
; Inputs:
;   A = Raw ASCII character / scan code from GET_KEY.
;
; Outputs:
;   A = Normalized keycode or KEY_ESC if sequence queued.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; modifies AF.
;------------------------------------------------------------------------------
HAL_KEYBOARD_TRANSLATE:
	PUSH BC
	PUSH DE
	PUSH HL
	LD D,A				; Save raw BIOS keycode in D

	; Check if Symbol Shift (EXTEND) is held: Row 7 (port $7FFE), bit 1
	; If Symbol Shift is NOT held (bit 1 == 1), check dedicated Caps Shift
	; keys: True Video (CS+3 -> Tab), Inv Video (CS+4 -> PgUp), and
	; Graph (CS+9 -> PgDn).
	LD BC,07FFEH
	IN A,(C)
	BIT 1,A
	JR Z,HKT_DISPATCH_RAW		; Symbol Shift held (EXTEND) -> skip CS

	; Check if Caps Shift is held: Row 0 (port $FEFE), bit 0
	LD BC,0FEFEH
	IN A,(C)
	BIT 0,A
	JR NZ,HKT_DISPATCH_RAW		; Caps Shift not held -> normal dispatch

	; Caps Shift held without Symbol Shift: check Row 3 ($F7FE) for '3'/'4'
	LD BC,0F7FEH
	IN A,(C)
	BIT 2,A
	JR Z,HKT_RET_TAB		; CS + '3' (True Video) -> Tab (0x09)
	BIT 3,A
	JR Z,HKT_RET_PGUP		; CS + '4' (Inv Video) -> PgUp (0x15)

	; Check Row 4 ($EFFE) for '9' (Graph)
	LD BC,0EFFEH
	IN A,(C)
	BIT 1,A
	JR Z,HKT_RET_PGDN		; CS + '9' (Graph) -> PgDn (0x16)

HKT_DISPATCH_RAW:
	LD A,D				; Restore raw BIOS keycode

	; Preserve 0x7F (Delete) for forward and block deletion
	CP NEXT_KEY_DELETE
	JR Z,HKT_DONE_EARLY

	; Check True Video (Tab) / Ctrl+S (0x13)
	CP 013H
	JR Z,HKT_CHECK_TRUE_VID

	; Check Inv Video (PgUp) / Ctrl+T (0x14)
	CP 014H
	JR Z,HKT_CHECK_INV_VID

	; Check Graph (PgDn) / Ctrl+G (0x07)
	CP 007H
	JR Z,HKT_CHECK_GRAPH

	; Check Right Arrow / Ctrl+F (0x06)
	CP 006H
	JR Z,HKT_CHECK_RIGHT

	; Check Left Arrow / Ctrl+A (0x01)
	CP 001H
	JR Z,HKT_CHECK_LEFT

	; Check Left Arrow / Backspace (0x08)
	CP 008H
	JR Z,HKT_CHECK_BS

	; Check Up Arrow (0x1F XBIOS)
	CP 01FH
	JP Z,HKT_SET_UP

	; Check Up Arrow / Ctrl+E (0x05)
	CP 005H
	JP Z,HKT_CHECK_UP

	; Check Ctrl+K / Up Arrow (0x0B)
	CP 00BH
	JP Z,HKT_CHECK_CTRL_K

	; Check Down Arrow: 0x1E (XBIOS)
	CP 01EH
	JP Z,HKT_SET_DOWN

	; Check Down Arrow / Ctrl+X (0x18)
	CP 018H
	JP Z,HKT_CHECK_DOWN

	; Check Down Arrow / Line Feed (0x0A)
	CP 00AH
	JP Z,HKT_CHECK_LF

HKT_DONE_EARLY:
	JR HKT_DONE

HKT_CHECK_TRUE_VID:
	; Is key 'S' physically pressed? Row 1 (port $FDFE), bit 1
	LD BC,0FDFEH
	IN A,(C)
	BIT 1,A
	JR Z,HKT_IS_CTRL_S		; 'S' pressed (bit 1 == 0) -> Ctrl+S
HKT_RET_TAB:
	LD A,009H			; True Video -> Tab (0x09)
	JR HKT_DONE
HKT_IS_CTRL_S:
	LD A,013H			; Normal Ctrl+S (Save File)
	JR HKT_DONE

HKT_CHECK_INV_VID:
	; Is key 'T' physically pressed? Row 2 (port $FBFE), bit 4
	LD BC,0FBFEH
	IN A,(C)
	BIT 4,A
	JR Z,HKT_IS_CTRL_T		; 'T' pressed (bit 4 == 0) -> Ctrl+T
HKT_RET_PGUP:
	LD A,KEY_CTRL_U			; Inv Video -> Page Up (0x15)
	JR HKT_DONE
HKT_IS_CTRL_T:
	LD A,014H			; Normal Ctrl+T (Top of File)
	JR HKT_DONE

HKT_CHECK_GRAPH:
	; Is key 'G' physically pressed? Row 1 (port $FDFE), bit 4
	LD BC,0FDFEH
	IN A,(C)
	BIT 4,A
	JR Z,HKT_IS_CTRL_G		; 'G' pressed (bit 4 == 0) -> Ctrl+G
HKT_RET_PGDN:
	LD A,KEY_CTRL_V			; Graph -> Page Down (0x16)
	JR HKT_DONE
HKT_IS_CTRL_G:
	LD A,007H			; Normal Ctrl+G (Bottom of File)
	JR HKT_DONE

HKT_CHECK_RIGHT:
	; Is key 'F' physically pressed? Row 1 (port $FDFE), bit 3
	LD BC,0FDFEH
	IN A,(C)
	BIT 3,A
	JR Z,HKT_IS_CTRL_F		; 'F' pressed (bit 3 == 0) -> Ctrl+F
HKT_SET_RIGHT:
	LD A,'C'			; Right Arrow -> ESC [ C
	JR HKT_QUEUE_CSI
HKT_IS_CTRL_F:
	LD A,006H
	JR HKT_DONE

HKT_CHECK_LEFT:
	; Is key 'A' physically pressed? Row 1 (port $FDFE), bit 0
	LD BC,0FDFEH
	IN A,(C)
	BIT 0,A
	JR Z,HKT_IS_CTRL_A		; 'A' pressed (bit 0 == 0) -> Ctrl+A
HKT_SET_LEFT:
	LD A,'D'			; Left Arrow -> ESC [ D
	JR HKT_QUEUE_CSI
HKT_IS_CTRL_A:
	LD A,001H
	JR HKT_DONE

HKT_CHECK_BS:
	; Is key '5' physically pressed? Row 3 (port $F7FE), bit 4
	LD BC,0F7FEH
	IN A,(C)
	BIT 4,A
	JR Z,HKT_SET_LEFT		; '5' pressed (bit 4 == 0) -> Left Arrow
	LD A,008H			; Normal Backspace
	JR HKT_DONE

HKT_CHECK_UP:
	; Is key 'E' physically pressed? Row 2 (port $FBFE), bit 2
	LD BC,0FBFEH
	IN A,(C)
	BIT 2,A
	JR Z,HKT_IS_CTRL_E		; 'E' pressed (bit 2 == 0) -> Ctrl+E
HKT_SET_UP:
	LD A,'A'			; Up Arrow -> ESC [ A
	JR HKT_QUEUE_CSI
HKT_IS_CTRL_E:
	LD A,005H

HKT_DONE:
	POP HL
	POP DE
	POP BC
	RET

HKT_QUEUE_CSI:
	; Queue '[' and directional character in sequence buffer
	LD (KEY_SEQ_BUF+1),A
	LD A,'['
	LD (KEY_SEQ_BUF),A
	LD A,2
	LD (KEY_SEQ_LEN),A
	LD HL,KEY_SEQ_BUF
	LD (KEY_SEQ_PTR),HL
	LD A,NEXT_KEY_EDIT		; Return ESC (0x1B)
	JR HKT_DONE

HKT_CHECK_CTRL_K:
	; Is key 'K' physically pressed? Row 6 (port $BFFE), bit 2
	LD BC,0BFFEH
	IN A,(C)
	BIT 2,A
	JR Z,HKT_IS_CTRL_K		; 'K' pressed (bit 2 == 0) -> Ctrl+K
	; Is key '7' (Up) physically pressed? Row 4 (port $EFFE), bit 3
	LD BC,0EFFEH
	IN A,(C)
	BIT 3,A
	JR Z,HKT_SET_UP			; '7' pressed (bit 3 == 0) -> Up Arrow
HKT_IS_CTRL_K:
	LD A,00BH			; Normal Ctrl+K (Help / Block Menu)
	JR HKT_DONE

HKT_CHECK_DOWN:
	; Is key 'X' physically pressed? Row 0 (port $FEFE), bit 2
	LD BC,0FEFEH
	IN A,(C)
	BIT 2,A
	JR Z,HKT_IS_CTRL_X		; 'X' pressed (bit 2 == 0) -> Ctrl+X
HKT_SET_DOWN:
	LD A,'B'			; Down Arrow -> ESC [ B
	JR HKT_QUEUE_CSI
HKT_IS_CTRL_X:
	LD A,018H
	JR HKT_DONE

HKT_CHECK_LF:
	; Is key '6' physically pressed? Row 4 (port $EFFE), bit 4
	LD BC,0EFFEH
	IN A,(C)
	BIT 4,A
	JR Z,HKT_SET_DOWN		; '6' pressed (bit 4 == 0) -> Down Arrow
	LD A,00AH			; Normal Line Feed
	JR HKT_DONE



