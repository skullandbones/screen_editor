;==============================================================================
; HELP.ASM - Editor Mode Keys Help Screen Overlay for SE.COM
; Digital Research CP/M 3 Overlay / PRL Format (Target: 4KB TPA Execution)
;
; Displays summary of all SE editor keys, handles Ctrl+P plugin popup requests,
; and returns to editor upon any keypress.
;
; Entry:
;   IX = Pointer to PLUGIN_HOST_API vector table
; Returns:
;   A  = Return code:
;        KEY_CTRL_P (16) if user requested context plugin popup
;        0 for normal exit to editor
;   CY = 0 (Success)
;==============================================================================

	ORG	0100H

;------------------------------------------------------------------------------
; Constants & Control Characters
;------------------------------------------------------------------------------
KEY_ESC			EQU	27
KEY_CTRL_P		EQU	16
HELP_LINES		EQU	22

;------------------------------------------------------------------------------
; Standard 3-Entry Jump Table
;------------------------------------------------------------------------------
ENTRY:
	JP	DO_HELP_EXECUTE		; +0: Action 0 (Main Execution)
	JP	DO_HELP_ABOUT		; +3: Action 1 (About Screen)
	JP	DO_HELP_CONFIG		; +6: Action 2 (Config Screen)

;------------------------------------------------------------------------------
; Action 0: Main Execution (Display Editor Keys Help Screen)
;------------------------------------------------------------------------------
DO_HELP_EXECUTE:
	; Verify Host API Magic "SE"
	LD	A,(IX+0)
	CP	'S'
	JR	Z,API_OK
	PUSH	IY
	POP	IX
	LD	A,(IX+0)
	CP	'S'
	JR	NZ,INIT_FALLBACK
API_OK:
	LD	A,(IX+1)
	CP	'E'
	JR	NZ,INIT_FALLBACK

	; Read screen dimensions from Host API
	LD	A,(IX+14)		; Screen cols (80 or 120)
	OR	A
	JR	Z,USE_DEFAULT_COLS
	LD	(HELP_COLS),A
	JR	COLS_SET
USE_DEFAULT_COLS:
	LD	A,80
	LD	(HELP_COLS),A
COLS_SET:
	LD	A,(IX+16)		; Screen rows (24 or 40)
	OR	A
	JR	Z,USE_DEFAULT_ROWS
	LD	(HELP_ROWS),A
	JR	ROWS_SET
USE_DEFAULT_ROWS:
	LD	A,24
	LD	(HELP_ROWS),A
ROWS_SET:
	CALL	RENDER_HELP_SCREEN

HELP_KEY_LOOP:
	CALL	API_GET_KEY
	CP	KEY_CTRL_P
	JR	Z,HELP_RET_CTRL_P
	CP	KEY_ESC
	JR	NZ,HELP_RET_NORMAL

	; Standalone ESC or escape sequence -> drain extra keys
HELP_DRAIN_ESC:
	CALL	API_CHECK_KEY
	OR	A
	JR	Z,HELP_RET_NORMAL
	CALL	API_GET_KEY
	JR	HELP_DRAIN_ESC

HELP_RET_CTRL_P:
	LD	A,KEY_CTRL_P
	OR	A			; Carry = 0
	RET

HELP_RET_NORMAL:
	XOR	A			; A = 0, Carry = 0
	RET

INIT_FALLBACK:
	LD	A,80
	LD	(HELP_COLS),A
	LD	A,24
	LD	(HELP_ROWS),A
	CALL	RENDER_HELP_SCREEN
	JR	HELP_KEY_LOOP

;------------------------------------------------------------------------------
; Action 1 & 2: Stubs
;------------------------------------------------------------------------------
DO_HELP_ABOUT:
DO_HELP_CONFIG:
	XOR	A
	RET

;------------------------------------------------------------------------------
; Screen Rendering Routines
;------------------------------------------------------------------------------
RENDER_HELP_SCREEN:
	; Calculate vertical top padding: ((HELP_ROWS - 1) - HELP_LINES) / 2
	LD	A,(HELP_ROWS)
	DEC	A			; Text rows available (23 in 80x24, 39 in 120x40)
	SUB	HELP_LINES		; 23 - 22 = 1 (80x24), 39 - 22 = 17 (120x40)
	JR	Z,RHS_NO_TOP_PAD
	JR	C,RHS_NO_TOP_PAD
	SRL	A			; 0 in 80x24, 8 in 120x40
	LD	(HELP_TOP_PAD_COUNT),A
	JR	RHS_TOP_PAD_DONE
RHS_NO_TOP_PAD:
	XOR	A
	LD	(HELP_TOP_PAD_COUNT),A
RHS_TOP_PAD_DONE:

	; Calculate horizontal left padding for help body table:
	; ((HELP_COLS - 80) / 2)
	LD	A,(HELP_COLS)
	SUB	80
	JR	Z,RHS_NO_LEFT_PAD
	JR	C,RHS_NO_LEFT_PAD
	SRL	A			; 0 in 80x24, 20 in 120x40
	LD	(HELP_LEFT_PAD),A
	JR	RHS_LEFT_PAD_DONE
RHS_NO_LEFT_PAD:
	XOR	A
	LD	(HELP_LEFT_PAD),A
RHS_LEFT_PAD_DONE:

	LD	DE,STR_HIDE_CURSOR
	CALL	API_PRINT_STR
	LD	DE,STR_CLEAR_SCREEN
	CALL	API_PRINT_STR

	; 1. Top margin blank tildes (if any)
	LD	A,(HELP_TOP_PAD_COUNT)
	OR	A
	JR	Z,RHS_TOP_PADDING_DONE
	LD	B,A
RHS_TOP_PADDING_LOOP:
	CALL	PRINT_TILDE_CRLF
	DJNZ	RHS_TOP_PADDING_LOOP
RHS_TOP_PADDING_DONE:

	; 2. Content Block Row 1: Horizontal Rule ('=')
	CALL	PRINT_HR_EQUAL

	; 3. Content Block Row 2: Centered Title
	CALL	RENDER_HELP_TITLE

	; 4. Content Block Row 3: Horizontal Rule ('=')
	CALL	PRINT_HR_EQUAL

	; 5. Content Block Rows 4..20: Help Key Descriptions (17 lines)
	CALL	RENDER_HELP_BODY

	; 6. Content Block Row 21: Horizontal Dash Rule ('-')
	CALL	PRINT_HR_DASH

	; 7. Content Block Row 22: Centered Return Prompt
	CALL	RENDER_HELP_FOOTER

	; 8. Bottom margin blank tildes:
	; (HELP_ROWS - 1) - HELP_TOP_PAD_COUNT - HELP_LINES
	LD	A,(HELP_ROWS)
	DEC	A			; Text rows available
	LD	HL,HELP_TOP_PAD_COUNT
	SUB	(HL)
	SUB	HELP_LINES
	JR	Z,RHS_BOTTOM_DONE
	JR	C,RHS_BOTTOM_DONE
	LD	B,A
RHS_BOTTOM_LOOP:
	CALL	PRINT_TILDE_CRLF
	DJNZ	RHS_BOTTOM_LOOP
RHS_BOTTOM_DONE:

	; 9. Row HELP_ROWS: Status Bar
	CALL	API_RENDER_STATUS_BAR
	LD	DE,STR_HOME
	CALL	API_PRINT_STR
	LD	DE,STR_HIDE_CURSOR
	CALL	API_PRINT_STR
	RET

; Print '~' followed by CRLF
PRINT_TILDE_CRLF:
	LD	A,'~'
	CALL	API_PUTC
	LD	A,13
	CALL	API_PUTC
	LD	A,10
	CALL	API_PUTC
	RET

; Render Rows 4..20: Help Key Descriptions (17 lines)
; Prefixes each line with '~' in column 0, followed by HELP_LEFT_PAD spaces,
; followed by the line text, followed by CRLF.
RENDER_HELP_BODY:
	LD	HL,STR_HELP_BODY
RHB_LINE_START:
	LD	A,(HL)
	CP	'$'
	RET	Z			; End of help body

	; Column 0: '~'
	LD	A,'~'
	CALL	API_PUTC

	; Left horizontal padding spaces (if any)
	LD	A,(HELP_LEFT_PAD)
	OR	A
	JR	Z,RHB_CHAR_LOOP
	LD	B,A
RHB_PAD_LOOP:
	LD	A,' '
	CALL	API_PUTC
	DJNZ	RHB_PAD_LOOP

RHB_CHAR_LOOP:
	LD	A,(HL)
	INC	HL
	CALL	API_PUTC
	CP	10			; Line Feed ends current line
	JR	NZ,RHB_CHAR_LOOP
	JR	RHB_LINE_START


; Render Row 1 & 3: Horizontal Rule of '=' across HELP_COLS
PRINT_HR_EQUAL:
	LD	A,'~'
	CALL	API_PUTC
	LD	A,(HELP_COLS)
	DEC	A
	LD	B,A
PHE_LOOP:
	LD	A,'='
	CALL	API_PUTC
	DJNZ	PHE_LOOP
	LD	A,13
	CALL	API_PUTC
	LD	A,10
	CALL	API_PUTC
	RET

; Render Row 21: Horizontal Dash Rule of '-' across HELP_COLS
PRINT_HR_DASH:
	LD	A,'~'
	CALL	API_PUTC
	LD	A,(HELP_COLS)
	DEC	A
	LD	B,A
PHD_LOOP:
	LD	A,'-'
	CALL	API_PUTC
	DJNZ	PHD_LOOP
	LD	A,13
	CALL	API_PUTC
	LD	A,10
	CALL	API_PUTC
	RET

; Render Row 2: Centered Title
RENDER_HELP_TITLE:
	LD	A,'~'
	CALL	API_PUTC
	LD	A,(HELP_COLS)
	SUB	25			; Length of STR_HELP_TITLE without CRLF
	SRL	A
	DEC	A
	LD	B,A
RHT_PAD_LOOP:
	LD	A,' '
	CALL	API_PUTC
	DJNZ	RHT_PAD_LOOP
	LD	DE,STR_HELP_TITLE
	CALL	API_PRINT_STR
	RET

; Render Row 22: Centered Footer
RENDER_HELP_FOOTER:
	LD	A,'~'
	CALL	API_PUTC
	LD	A,(HELP_COLS)
	SUB	33			; Length of STR_HELP_RETURN_PROMPT without CRLF
	SRL	A
	DEC	A
	LD	B,A
RHF_PAD_LOOP:
	LD	A,' '
	CALL	API_PUTC
	DJNZ	RHF_PAD_LOOP
	LD	DE,STR_HELP_RETURN_PROMPT
	CALL	API_PRINT_STR
	RET

;------------------------------------------------------------------------------
; Host API Wrappers
;------------------------------------------------------------------------------
API_PUTC:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	C,24			; Offset +24: TRAMP_PUTC
	CALL	CALL_IX_OFFSET
	POP	HL
	POP	DE
	POP	BC
	RET

API_PRINT_STR:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	C,27			; Offset +27: TRAMP_PRINT_STR
	CALL	CALL_IX_OFFSET
	POP	HL
	POP	DE
	POP	BC
	RET

API_GET_KEY:
	LD	C,30			; Offset +30: TRAMP_GET_KEY
	JP	CALL_IX_OFFSET

API_CHECK_KEY:
	LD	C,46			; Offset +46: TRAMP_CHECK_KEY
	JP	CALL_IX_OFFSET

API_RENDER_STATUS_BAR:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	C,73			; Offset +73: TRAMP_RENDER_STATUS_BAR
	CALL	CALL_IX_OFFSET
	POP	HL
	POP	DE
	POP	BC
	RET

CALL_IX_OFFSET:
	PUSH	IX
	POP	HL
	LD	B,0
	ADD	HL,BC
	JP	(HL)

;------------------------------------------------------------------------------
; Text Strings & Escape Sequences
;------------------------------------------------------------------------------
STR_HIDE_CURSOR:	DB	27,"[?25l","$"
STR_CLEAR_SCREEN:	DB	27,"[2J",27,"[H","$"
STR_HOME:		DB	27,"[H","$"

STR_HELP_TITLE:		DB	"SE.COM - EDITOR MODE KEYS",13,10,"$"

STR_HELP_BODY:
	DB	"  FILE & SYSTEM:",13,10
	DB	"    Ctrl+O           Open file screen        "
	DB	"Ctrl+S          Save file screen",13,10
	DB	"    Ctrl+W           Close file to splash    "
	DB	"Ctrl+Q          Quit to CP/M",13,10
	DB	"    Ctrl+K           Help / Solidify block   "
	DB	"Ctrl+P          Plugins pop-up",13,10
	DB	"  NAVIGATION & SEARCH:",13,10
	DB	"    Arrow Keys       Move Up/Down/Left/Right "
	DB	"Ctrl+A / Home   Start of line",13,10
	DB	"    Ctrl+U / PgUp    Page Up                 "
	DB	"Ctrl+E / End    End of line",13,10
	DB	"    Ctrl+V / PgDn    Page Down               "
	DB	"Ctrl+T / ^Home  Top of file",13,10
	DB	"    Ctrl+L           Goto line number        "
	DB	"Ctrl+G / ^End   Bottom of file",13,10
	DB	"    Ctrl+F           Find text               "
	DB	"Ctrl+N          Find next",13,10
	DB	"    Ctrl+R           Search and Replace      "
	DB	"Ctrl+I / Tab    Toggle find case",13,10
	DB	"  EDITING & BLOCK:",13,10
	DB	"    Insert           Toggle Insert/Overwrite "
	DB	"Enter           New line",13,10
	DB	"    ASCII 32..126    Insert/Overwrite text   "
	DB	"Backspace       Delete left / join",13,10
	DB	"    Delete / Ctrl+D  Delete char or block    "
	DB	"Ctrl+B          Start/Toggle block",13,10
	DB	"    Ctrl+C           Copy solidified block   "
	DB	"Ctrl+K          Solidify block",13,10
	DB	"    Ctrl+X           Move solidified block   "
	DB	"ESC             Clear block",13,10,"$"

STR_HELP_RETURN_PROMPT:	DB	"Press any key to return to editor",13,10,"$"

HELP_COLS:		DB	80
HELP_ROWS:		DB	24
HELP_TOP_PAD_COUNT:	DB	0
HELP_LEFT_PAD:		DB	0
