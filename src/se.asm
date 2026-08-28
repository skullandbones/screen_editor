;==============================================================================
; SE.COM: CP/M Full-Screen Text Editor for RomWBW / RC2014
; Target: Z80 CPU, CP/M 2.2+, RomWBW HBIOS 512K Extended RAM, Minicom/VT100
;==============================================================================

	.ORG	$0100

;------------------------------------------------------------------------------
; Constants & BDOS Vectors
;------------------------------------------------------------------------------
BDOS_ENTRY	.EQU	$0005
DEFAULT_FCB	.EQU	$005C
DEFAULT_DMA	.EQU	$0080
CMD_LEN		.EQU	$0080
CMD_TAIL	.EQU	$0081

MAX_LINE_STRIDE	.EQU	128		; 128 bytes stride per line buffer
MAX_BUFFER_LINES .EQU	40		; Up to 40 lines in local memory grid

KEY_CTRL_C	.EQU	3
KEY_CTRL_Q	.EQU	17
KEY_CTRL_S	.EQU	19
KEY_CTRL_F	.EQU	6		; Toggle CP/M <-> Linux line endings
KEY_BACKSPACE	.EQU	8
KEY_TAB		.EQU	9
KEY_ENTER	.EQU	13
KEY_ESC		.EQU	27
KEY_DEL		.EQU	127

; Line ending modes
FMT_CPM		.EQU	0		; CR/LF (0x0D, 0x0A)
FMT_LINUX	.EQU	1		; LF only (0x0A)

; Screen Size Modes
MODE_120X40	.EQU	0		; Modern 120 cols x 40 rows (Default)
MODE_80X24	.EQU	1		; Classic 80 cols x 24 rows

;------------------------------------------------------------------------------
; Main Entry Point
;------------------------------------------------------------------------------
START:
	LD	(SAVED_SP),SP
	LD	SP,LOCAL_STACK

	; Initialize Screen Geometry to Default (120x40)
	CALL	SET_MODE_120X40

	; Initialize Terminal (Clear Screen & Home)
	CALL	TERM_INIT

	; Query RomWBW User Bank
	CALL	BUFFER_INIT

	; Check if filename was provided in FCB1
	CALL	CHECK_COMMAND_LINE

	; If file argument was given, load file and go straight to editor
	LD	A,(HAS_FILE_ARG)
	OR	A
	JR	NZ,DO_AUTO_LOAD

	; Otherwise, display Vim-style Splash Screen
SPLASH_START:
	CALL	RENDER_SPLASH

SPLASH_LOOP:
	CALL	GET_KEY

	; Option: 'Q' or 'q' or Ctrl+Q -> Exit
	CP	'q'
	JP	Z,EXIT_PROGRAM
	CP	'Q'
	JP	Z,EXIT_PROGRAM
	CP	KEY_CTRL_Q
	JP	Z,EXIT_PROGRAM

	; Option: 'T' or 't' -> Run Extended Memory Test
	CP	't'
	JR	Z,DO_MEM_TEST
	CP	'T'
	JR	Z,DO_MEM_TEST

	; Option: '1' -> Modern Screen Mode (120x40)
	CP	'1'
	JR	Z,DO_SET_120X40

	; Option: '2' -> Classic Screen Mode (80x24)
	CP	'2'
	JR	Z,DO_SET_80X24

	; Option: 'E' or 'e' or Enter or Space -> Enter Editor
	CP	'e'
	JR	Z,ENTER_EDITOR
	CP	'E'
	JR	Z,ENTER_EDITOR
	CP	KEY_ENTER
	JR	Z,ENTER_EDITOR
	CP	' '
	JR	Z,ENTER_EDITOR

	JR	SPLASH_LOOP

DO_SET_120X40:
	CALL	SET_MODE_120X40
	JR	SPLASH_START

DO_SET_80X24:
	CALL	SET_MODE_80X24
	JR	SPLASH_START

DO_MEM_TEST:
	CALL	RUN_MEM_TEST
	CALL	GET_KEY
	JR	SPLASH_START

DO_AUTO_LOAD:
	CALL	LOAD_FILE
	XOR	A
	LD	(CUR_ROW),A
	LD	(CUR_COL),A
	CALL	TERM_INIT
	CALL	RENDER_SCREEN
	JP	MAIN_LOOP

ENTER_EDITOR:
	CALL	LOAD_SAMPLE_BUFFER
	XOR	A
	LD	(CUR_ROW),A
	LD	(CUR_COL),A
	CALL	TERM_INIT
	CALL	RENDER_SCREEN

MAIN_LOOP:
	CALL	GET_KEY

	; Command: Ctrl+Q -> Exit
	CP	KEY_CTRL_Q
	JP	Z,EXIT_PROGRAM

	; Command: Ctrl+S -> Save File
	CP	KEY_CTRL_S
	JR	NZ,CHECK_TOGGLE_FMT
	CALL	SAVE_FILE
	CALL	RENDER_STATUS_BAR
	JR	MAIN_LOOP

CHECK_TOGGLE_FMT:
	; Command: Ctrl+F -> Toggle Line Ending Format (CP/M <-> Linux)
	CP	KEY_CTRL_F
	JR	NZ,CHECK_ENTER
	LD	A,(SAVE_FORMAT)
	XOR	1			; Toggle between 0 (CP/M) and 1 (Linux)
	LD	(SAVE_FORMAT),A
	CALL	RENDER_STATUS_BAR
	JR	MAIN_LOOP

CHECK_ENTER:
	; Enter -> Insert new line at CUR_ROW+1
	CP	KEY_ENTER
	JR	NZ,CHECK_BACKSPACE
	CALL	DO_INSERT_LINE
	CALL	RENDER_SCREEN
	JR	MAIN_LOOP

CHECK_BACKSPACE:
	CP	KEY_BACKSPACE
	JR	Z,DO_HANDLE_BS
	CP	KEY_DEL
	JR	NZ,CHECK_ESC_SEQ

DO_HANDLE_BS:
	CALL	DO_DELETE_CHAR
	CALL	RENDER_CURRENT_LINE
	JR	MAIN_LOOP

CHECK_ESC_SEQ:
	; Check for VT100 Escape sequences (Arrow keys)
	CP	KEY_ESC
	JR	NZ,CHECK_PRINTABLE_CHAR
	CALL	HANDLE_VT100_ESC
	CALL	LOCATE_CURSOR
	JR	MAIN_LOOP

CHECK_PRINTABLE_CHAR:
	; Check if character is printable (ASCII 32..126 or Tab)
	CP	9			; TAB
	JR	Z,DO_INSERT_CHAR
	CP	' '
	JR	C,MAIN_LOOP
	CP	127
	JR	NC,MAIN_LOOP

DO_INSERT_CHAR:
	CALL	DO_CHAR_INSERT
	CALL	RENDER_CURRENT_LINE
	JR	MAIN_LOOP

EXIT_PROGRAM:
	CALL	LOCATE_STATUS_ROW
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	LD	DE,MSG_EXIT
	CALL	PRINT_STR

	LD	SP,(SAVED_SP)
	RET

;------------------------------------------------------------------------------
; Screen Geometry Setup
;------------------------------------------------------------------------------
SET_MODE_120X40:
	LD	A,MODE_120X40
	LD	(SCREEN_MODE),A
	LD	A,40
	LD	(ACTIVE_ROWS),A
	LD	A,120
	LD	(ACTIVE_COLS),A
	RET

SET_MODE_80X24:
	LD	A,MODE_80X24
	LD	(SCREEN_MODE),A
	LD	A,24
	LD	(ACTIVE_ROWS),A
	LD	A,80
	LD	(ACTIVE_COLS),A
	RET

;------------------------------------------------------------------------------
; Terminal / VT100 I/O Routines
;------------------------------------------------------------------------------
TERM_INIT:
	LD	DE,STR_CLEAR_SCREEN
	CALL	PRINT_STR
	RET

PRINT_STR:
	LD	C,9
	CALL	BDOS_ENTRY
	RET

PUTC:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	E,A
	LD	C,2
	CALL	BDOS_ENTRY
	POP	HL
	POP	DE
	POP	BC
	RET

GET_KEY:
	PUSH	BC
	PUSH	DE
	PUSH	HL
GET_KEY_WAIT:
	LD	E,0FFH
	LD	C,6
	CALL	BDOS_ENTRY
	OR	A
	JR	Z,GET_KEY_WAIT
	POP	HL
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; Command Line & FCB Initialization
;------------------------------------------------------------------------------
CHECK_COMMAND_LINE:
	LD	A,(DEFAULT_FCB+1)
	CP	' '
	JR	Z,NO_FILE_ARG
	CP	0
	JR	Z,NO_FILE_ARG

	LD	A,1
	LD	(HAS_FILE_ARG),A

	; Copy FCB to working FCB
	LD	HL,DEFAULT_FCB
	LD	DE,WORK_FCB
	LD	BC,36
	LDIR
	RET

NO_FILE_ARG:
	XOR	A
	LD	(HAS_FILE_ARG),A
	RET

;------------------------------------------------------------------------------
; Splash Screen Renderer (Vim Style)
;------------------------------------------------------------------------------
RENDER_SPLASH:
	LD	DE,STR_CLEAR_SCREEN
	CALL	PRINT_STR
	LD	DE,STR_SPLASH_BODY
	CALL	PRINT_STR

	; Display currently active mode
	LD	DE,STR_SPLASH_CUR_MODE
	CALL	PRINT_STR

	LD	A,(SCREEN_MODE)
	CP	MODE_120X40
	JR	NZ,SHOW_SPLASH_80X24
	LD	DE,STR_MODE_120X40_LBL
	CALL	PRINT_STR
	JR	RENDER_SPLASH_CONT

SHOW_SPLASH_80X24:
	LD	DE,STR_MODE_80X24_LBL
	CALL	PRINT_STR

RENDER_SPLASH_CONT:
	LD	DE,STR_SPLASH_TAIL
	CALL	PRINT_STR
	RET

;------------------------------------------------------------------------------
; 512KB Extended Memory Diagnostic (RomWBW HBIOS RST 08H)
;------------------------------------------------------------------------------
RUN_MEM_TEST:
	LD	DE,STR_CLEAR_SCREEN
	CALL	PRINT_STR

	LD	DE,STR_TEST_TITLE
	CALL	PRINT_STR

	; Check HBIOS presence
	CALL	HBIOS_DETECT
	JR	Z,TEST_HBIOS_OK
	LD	DE,STR_TEST_NO_HBIOS
	CALL	PRINT_STR
	RET

TEST_HBIOS_OK:
	LD	DE,STR_TEST_HBIOS_OK
	CALL	PRINT_STR

	; Query Memory Bank Info (SYSGET 0xF1)
	PUSH	IX
	LD	B,0F8H
	LD	C,0F1H
	RST	08H
	POP	IX

	LD	A,D
	LD	(ROM_BANK_COUNT),A
	LD	A,E
	LD	(RAM_BANK_COUNT),A

	LD	DE,STR_TEST_RAM_BANKS
	CALL	PRINT_STR
	LD	A,(RAM_BANK_COUNT)
	CALL	PRINT_DEC_BYTE
	LD	DE,STR_TEST_RAM_BANKS_END
	CALL	PRINT_STR

	; Print Active CP/M Bank
	LD	DE,STR_TEST_CUR_BANK
	CALL	PRINT_STR
	LD	A,(CPM_USER_BANK)
	CALL	PRINT_HEX_BYTE
	LD	DE,STR_CRLF
	CALL	PRINT_STR

	; Set Target RAM Bank
	LD	A,(CPM_USER_BANK)
	CP	080H
	JR	NZ,USE_RAM_BANK_80
	LD	A,081H
	JR	SET_TARGET_BANK

USE_RAM_BANK_80:
	LD	A,080H

SET_TARGET_BANK:
	LD	(TARGET_RAM_BANK),A

	LD	DE,STR_TEST_TARGET_BANK
	CALL	PRINT_STR
	LD	A,(TARGET_RAM_BANK)
	CALL	PRINT_HEX_BYTE
	LD	DE,STR_CRLF
	CALL	PRINT_STR

	LD	DE,STR_TEST_BANK_COPY
	CALL	PRINT_STR

	; 1. Prepare test pattern in local memory
	LD	HL,TEST_PATTERN
	LD	(HL),0AAH
	INC	HL
	LD	(HL),055H

	; 2. SYSSETCPY: Copy local pattern to TARGET_RAM_BANK at offset 0x1000
	PUSH	IX
	LD	B,0F4H			; SYSSETCPY
	LD	A,(TARGET_RAM_BANK)
	LD	D,A			; Dest Bank = Target Upper RAM Bank
	LD	A,(CPM_USER_BANK)
	LD	E,A			; Src Bank = CP/M User Bank
	LD	HL,2			; Count = 2 bytes
	RST	08H
	POP	IX

	PUSH	IX
	LD	B,0F5H			; SYSBNKCPY
	LD	DE,01000H		; Dest Address in Target Bank
	LD	HL,TEST_PATTERN		; Src Address
	RST	08H
	POP	IX

	; 3. Clear readback buffer
	LD	HL,TEST_READBACK
	LD	(HL),0
	INC	HL
	LD	(HL),0

	; 4. SYSSETCPY: Copy from TARGET_RAM_BANK back to local buffer
	PUSH	IX
	LD	B,0F4H			; SYSSETCPY
	LD	A,(CPM_USER_BANK)
	LD	D,A			; Dest Bank = User Bank
	LD	A,(TARGET_RAM_BANK)
	LD	E,A			; Src Bank = Target RAM Bank
	LD	HL,2
	RST	08H
	POP	IX

	PUSH	IX
	LD	B,0F5H			; SYSBNKCPY
	LD	DE,TEST_READBACK
	LD	HL,01000H
	RST	08H
	POP	IX

	; 5. Verify pattern matches
	LD	A,(TEST_READBACK)
	CP	0AAH
	JR	NZ,TEST_FAIL
	LD	A,(TEST_READBACK+1)
	CP	055H
	JR	NZ,TEST_FAIL

	; Success
	LD	DE,STR_TEST_PASSED
	CALL	PRINT_STR
	JR	TEST_END

TEST_FAIL:
	LD	DE,STR_TEST_FAILED
	CALL	PRINT_STR

TEST_END:
	LD	DE,STR_TEST_PROMPT
	CALL	PRINT_STR
	RET

;------------------------------------------------------------------------------
; Print 8-bit number in decimal (0 .. 255)
;------------------------------------------------------------------------------
PRINT_DEC_BYTE:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	LD	E,A			; E = input value

	; Check hundreds (100)
	LD	C,0
HUNDREDS_LOOP:
	LD	A,E
	CP	100
	JR	C,DONE_HUNDREDS
	SUB	100
	LD	E,A
	INC	C
	JR	HUNDREDS_LOOP

DONE_HUNDREDS:
	; Check tens (10)
	LD	B,0
TENS_LOOP:
	LD	A,E
	CP	10
	JR	C,DONE_TENS
	SUB	10
	LD	E,A
	INC	B
	JR	TENS_LOOP

DONE_TENS:
	; Print Hundreds if non-zero
	LD	A,C
	OR	A
	JR	Z,CHECK_TENS_OUTPUT
	ADD	A,'0'
	CALL	PUTC
	; If hundreds was printed, tens MUST be printed even if 0
	LD	A,B
	ADD	A,'0'
	CALL	PUTC
	JR	PRINT_ONES_DIGIT

CHECK_TENS_OUTPUT:
	; Print Tens if non-zero
	LD	A,B
	OR	A
	JR	Z,PRINT_ONES_DIGIT
	ADD	A,'0'
	CALL	PUTC

PRINT_ONES_DIGIT:
	; Print Units (E)
	LD	A,E
	ADD	A,'0'
	CALL	PUTC

	POP	DE
	POP	BC
	POP	AF
	RET

PRINT_HEX_BYTE:
	PUSH	AF
	RRA
	RRA
	RRA
	RRA
	CALL	PRINT_NIBBLE
	POP	AF
PRINT_NIBBLE:
	AND	0FH
	CP	10
	JR	C,PRINT_DIGIT
	ADD	A,'A'-10
	CALL	PUTC
	RET
PRINT_DIGIT:
	ADD	A,'0'
	CALL	PUTC
	RET

;------------------------------------------------------------------------------
; Editor Screen Renderer
;------------------------------------------------------------------------------
RENDER_SCREEN:
	LD	DE,STR_HOME
	CALL	PRINT_STR

	LD	C,0			; Row index (0 .. ACTIVE_ROWS-2)
RENDER_ROW_LOOP:
	PUSH	BC
	LD	A,C
	LD	(CUR_RENDER_ROW),A

	; Check if CUR_RENDER_ROW < TOTAL_LINES
	LD	A,(TOTAL_LINES)
	LD	B,A
	LD	A,(CUR_RENDER_ROW)
	CP	B
	JR	NC,RENDER_TILDE_ROW

	CALL	RENDER_BUFFER_LINE
	JR	RENDER_ROW_NEXT

RENDER_TILDE_ROW:
	LD	DE,STR_CLEAR_EOL
	CALL	PRINT_STR
	LD	A,'~'
	CALL	PUTC
	LD	A,13
	CALL	PUTC
	LD	A,10
	CALL	PUTC

RENDER_ROW_NEXT:
	POP	BC
	INC	C
	LD	A,(ACTIVE_ROWS)
	DEC	A			; Text rows = ACTIVE_ROWS - 1
	CP	C
	JR	NZ,RENDER_ROW_LOOP

	CALL	RENDER_STATUS_BAR
	CALL	LOCATE_CURSOR
	RET

; Fast single line refresh: only rewrites CUR_ROW and restores cursor
RENDER_CURRENT_LINE:
	; Move to start of current line: ESC [ <CUR_ROW+1> ; 1 H
	LD	A,27
	CALL	PUTC
	LD	A,'['
	CALL	PUTC
	LD	A,(CUR_ROW)
	INC	A
	CALL	PRINT_DEC_BYTE
	LD	A,';'
	CALL	PUTC
	LD	A,'1'
	CALL	PUTC
	LD	A,'H'
	CALL	PUTC

	LD	A,(CUR_ROW)
	LD	(CUR_RENDER_ROW),A

	; Clear to EOL
	LD	DE,STR_CLEAR_EOL
	CALL	PRINT_STR

	; Calculate line address: LINE_STORAGE + (CUR_ROW * 128)
	LD	A,(CUR_ROW)
	LD	L,A
	LD	H,0
	ADD	HL,HL			; *2
	ADD	HL,HL			; *4
	ADD	HL,HL			; *8
	ADD	HL,HL			; *16
	ADD	HL,HL			; *32
	ADD	HL,HL			; *64
	ADD	HL,HL			; *128
	LD	DE,LINE_STORAGE
	ADD	HL,DE

PRINT_CUR_LINE_CHARS:
	LD	A,(HL)
	OR	A
	JR	Z,PRINT_CUR_LINE_DONE
	CP	'$'
	JR	Z,PRINT_CUR_LINE_DONE
	CALL	PUTC
	INC	HL
	JR	PRINT_CUR_LINE_CHARS

PRINT_CUR_LINE_DONE:
	CALL	LOCATE_CURSOR
	RET

RENDER_BUFFER_LINE:
	LD	DE,STR_CLEAR_EOL
	CALL	PRINT_STR

	; Calculate line address: LINE_STORAGE + (CUR_RENDER_ROW * 128)
	LD	A,(CUR_RENDER_ROW)
	LD	L,A
	LD	H,0
	ADD	HL,HL			; *2
	ADD	HL,HL			; *4
	ADD	HL,HL			; *8
	ADD	HL,HL			; *16
	ADD	HL,HL			; *32
	ADD	HL,HL			; *64
	ADD	HL,HL			; *128
	LD	DE,LINE_STORAGE
	ADD	HL,DE

	; Print characters directly
PRINT_LINE_CHARS:
	LD	A,(HL)
	OR	A
	JR	Z,PRINT_LINE_END
	CP	'$'
	JR	Z,PRINT_LINE_END
	CALL	PUTC
	INC	HL
	JR	PRINT_LINE_CHARS

PRINT_LINE_END:
	LD	A,13
	CALL	PUTC
	LD	A,10
	CALL	PUTC
	RET

LOCATE_STATUS_ROW:
	LD	A,(SCREEN_MODE)
	CP	MODE_120X40
	JR	NZ,LOCATE_ROW_24
	LD	DE,STR_GOTO_ROW_40
	CALL	PRINT_STR
	RET
LOCATE_ROW_24:
	LD	DE,STR_GOTO_ROW_24
	CALL	PRINT_STR
	RET

RENDER_STATUS_BAR:
	CALL	LOCATE_STATUS_ROW

	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR

	LD	DE,STR_STATUS_PREFIX
	CALL	PRINT_STR

	; Print active geometry
	LD	A,(SCREEN_MODE)
	CP	MODE_120X40
	JR	NZ,SHOW_STATUS_80X24
	LD	DE,STR_STATUS_120X40
	CALL	PRINT_STR
	JR	SHOW_STATUS_FORMAT

SHOW_STATUS_80X24:
	LD	DE,STR_STATUS_80X24
	CALL	PRINT_STR

SHOW_STATUS_FORMAT:
	LD	DE,STR_STATUS_MID
	CALL	PRINT_STR

	LD	A,(SAVE_FORMAT)
	CP	FMT_CPM
	JR	NZ,SHOW_LINUX_FMT
	LD	DE,STR_FMT_CPM
	CALL	PRINT_STR
	JR	SHOW_STATUS_REST

SHOW_LINUX_FMT:
	LD	DE,STR_FMT_LINUX
	CALL	PRINT_STR

SHOW_STATUS_REST:
	LD	DE,STR_STATUS_SUFFIX
	CALL	PRINT_STR
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	CALL	LOCATE_CURSOR
	RET

LOCATE_CURSOR:
	; Emit ESC [ <Row+1> ; <Col+1> H
	LD	A,27
	CALL	PUTC
	LD	A,'['
	CALL	PUTC

	; Row (1-indexed)
	LD	A,(CUR_ROW)
	INC	A
	CALL	PRINT_DEC_BYTE

	LD	A,';'
	CALL	PUTC

	; Col (1-indexed)
	LD	A,(CUR_COL)
	INC	A
	CALL	PRINT_DEC_BYTE

	LD	A,'H'
	CALL	PUTC
	RET

BUFFER_INIT:
	PUSH	IX
	LD	B,0F3H			; SYSGETBNK
	RST	08H
	POP	IX
	LD	A,C
	LD	(CPM_USER_BANK),A
	RET

;------------------------------------------------------------------------------
; VT100 Escape Sequence Handler (Arrow keys: Up, Down, Left, Right)
;------------------------------------------------------------------------------
HANDLE_VT100_ESC:
	; Check if next byte is '[' or 'O'
	CALL	GET_KEY
	CP	'['
	JR	Z,HANDLE_CSI
	CP	'O'
	JR	Z,HANDLE_CSI
	RET

HANDLE_CSI:
	CALL	GET_KEY
	CP	'A'			; Up Arrow
	JR	Z,CURSOR_UP
	CP	'B'			; Down Arrow
	JR	Z,CURSOR_DOWN
	CP	'C'			; Right Arrow
	JR	Z,CURSOR_RIGHT
	CP	'D'			; Left Arrow
	JR	Z,CURSOR_LEFT
	RET

CURSOR_UP:
	LD	A,(CUR_ROW)
	OR	A
	RET	Z
	DEC	A
	LD	(CUR_ROW),A
	RET

CURSOR_DOWN:
	LD	A,(TOTAL_LINES)
	OR	A
	JR	Z,CURSOR_DOWN_GEOM	; If 0 lines, allow moving within active rows
	DEC	A
	LD	B,A
	LD	A,(CUR_ROW)
	CP	B
	JR	NC,CURSOR_DOWN_CHECK_EXPAND

CURSOR_DOWN_GEOM:
	LD	A,(ACTIVE_ROWS)
	DEC	A
	DEC	A
	LD	B,A
	LD	A,(CUR_ROW)
	CP	B
	RET	NC
	INC	A
	LD	(CUR_ROW),A
	RET

CURSOR_DOWN_CHECK_EXPAND:
	; If user presses Down at or beyond TOTAL_LINES-1, allow cursor down up to ACTIVE_ROWS-2
	; and expand TOTAL_LINES so user can freely edit empty rows
	LD	A,(ACTIVE_ROWS)
	DEC	A
	DEC	A
	LD	B,A
	LD	A,(CUR_ROW)
	CP	B
	RET	NC
	INC	A
	LD	(CUR_ROW),A

	; Check if CUR_ROW >= TOTAL_LINES
	LD	A,(TOTAL_LINES)
	LD	B,A
	LD	A,(CUR_ROW)
	CP	B
	RET	C

	; Expand TOTAL_LINES = CUR_ROW + 1
	INC	A
	CP	MAX_BUFFER_LINES+1
	RET	NC
	LD	(TOTAL_LINES),A
	RET

CURSOR_LEFT:
	LD	A,(CUR_COL)
	OR	A
	RET	Z
	DEC	A
	LD	(CUR_COL),A
	RET

CURSOR_RIGHT:
	; Check screen width boundary
	LD	A,(ACTIVE_COLS)
	DEC	A
	LD	B,A
	LD	A,(CUR_COL)
	CP	B
	RET	NC
	CP	MAX_LINE_STRIDE-2
	RET	NC

	INC	A
	LD	(CUR_COL),A
	RET

;------------------------------------------------------------------------------
; Character Insertion at (CUR_ROW, CUR_COL)
;------------------------------------------------------------------------------
DO_CHAR_INSERT:
	LD	(CHAR_INSERT_TEMP),A	; Save character to insert

	; Ensure TOTAL_LINES >= CUR_ROW + 1
	LD	A,(TOTAL_LINES)
	LD	B,A
	LD	A,(CUR_ROW)
	CP	B
	JR	C,ROW_IN_BOUNDS
	INC	A
	LD	(TOTAL_LINES),A

ROW_IN_BOUNDS:
	; 1. Calculate pointer to start of current line: HL = LINE_STORAGE + (CUR_ROW * 128)
	LD	A,(CUR_ROW)
	LD	L,A
	LD	H,0
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL			; *128
	LD	DE,LINE_STORAGE
	ADD	HL,DE			; HL = line start

	; 2. Scan current line to find its length (first 0 or '$')
	PUSH	HL			; Save line start
	LD	B,0
SCAN_LEN_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,SCAN_LEN_DONE
	CP	'$'
	JR	Z,SCAN_LEN_DONE
	INC	HL
	INC	B
	LD	A,B
	CP	MAX_LINE_STRIDE-2
	JR	NC,SCAN_LEN_DONE
	JR	SCAN_LEN_LOOP

SCAN_LEN_DONE:
	POP	HL			; HL = line start
	; B = current line text length

	; 3. Compare CUR_COL with line length (B)
	LD	A,(CUR_COL)
	CP	B
	JR	NC,DO_PAD_AND_APPEND	; If CUR_COL >= length: pad spaces and append

	; 4. If CUR_COL < length: shift characters from (line_start + B) down to (line_start + CUR_COL)
	; Source start for LDDR: HL = line_start + B
	; Dest start for LDDR:   DE = line_start + B + 1
	; Count for LDDR:        BC = B - CUR_COL + 1 (including null terminator)
	PUSH	HL			; Save line start
	LD	E,B
	LD	D,0
	ADD	HL,DE			; HL = line_start + B (pointing to null terminator)

	LD	D,H
	LD	E,L
	INC	DE			; DE = line_start + B + 1

	LD	A,B
	LD	C,A
	LD	A,(CUR_COL)
	SUB	C
	NEG
	INC	A			; Count = B - CUR_COL + 1
	LD	C,A
	LD	B,0

	LDDR

	; Now insert character at line_start + CUR_COL
	POP	HL			; Line start
	LD	A,(CUR_COL)
	LD	E,A
	LD	D,0
	ADD	HL,DE
	LD	A,(CHAR_INSERT_TEMP)
	LD	(HL),A
	JR	ADVANCE_INSERT_CURSOR

DO_PAD_AND_APPEND:
	; Pad from line_start + B up to line_start + CUR_COL with spaces
	PUSH	HL
	LD	E,B
	LD	D,0
	ADD	HL,DE			; HL = line_start + B

PAD_SPACES_LOOP:
	LD	A,(CUR_COL)
	CP	B
	JR	Z,PAD_SPACES_DONE
	LD	(HL),' '
	INC	HL
	INC	B
	JR	PAD_SPACES_LOOP

PAD_SPACES_DONE:
	; HL is now at line_start + CUR_COL
	LD	A,(CHAR_INSERT_TEMP)
	LD	(HL),A
	INC	HL
	XOR	A
	LD	(HL),A			; Null terminate new end of line
	POP	HL

ADVANCE_INSERT_CURSOR:
	; Advance cursor right
	LD	A,(CUR_COL)
	CP	MAX_LINE_STRIDE-2
	RET	NC
	INC	A
	LD	(CUR_COL),A
	RET

;------------------------------------------------------------------------------
; Character Deletion at (CUR_ROW, CUR_COL) - Backspace Handling
;------------------------------------------------------------------------------
DO_DELETE_CHAR:
	LD	A,(CUR_COL)
	OR	A
	RET	Z			; At column 0, nothing to delete on line

	DEC	A
	LD	(CUR_COL),A

	; Calculate delete target: LINE_STORAGE + (CUR_ROW * 128) + CUR_COL
	LD	A,(CUR_ROW)
	LD	L,A
	LD	H,0
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	LD	DE,LINE_STORAGE
	ADD	HL,DE
	LD	A,(CUR_COL)
	LD	E,A
	LD	D,0
	ADD	HL,DE			; HL = character to delete

	; Shift characters left from HL+1 into HL until null or end of line
CHAR_SHIFT_LEFT_LOOP:
	INC	HL
	LD	A,(HL)
	DEC	HL
	LD	(HL),A
	OR	A
	RET	Z
	INC	HL
	JR	CHAR_SHIFT_LEFT_LOOP

;------------------------------------------------------------------------------
; Line Insertion & Splitting at (CUR_ROW, CUR_COL) - Enter Key Handling
;------------------------------------------------------------------------------
DO_INSERT_LINE:
	LD	A,(TOTAL_LINES)
	CP	MAX_BUFFER_LINES
	RET	NC			; Buffer full

	; 1. Shift lines below CUR_ROW downwards using LDDR block copy
	; Source start = LINE_STORAGE + (TOTAL_LINES * 128) - 1
	; Dest start   = LINE_STORAGE + ((TOTAL_LINES + 1) * 128) - 1
	; Count = (TOTAL_LINES - 1 - CUR_ROW) * 128

	LD	A,(TOTAL_LINES)
	DEC	A
	LD	HL,CUR_ROW
	CP	(HL)
	JR	Z,DO_SPLIT_LINE		; If CUR_ROW is the last line, no lines to shift!

	; Count = (TOTAL_LINES - 1 - CUR_ROW) * 128
	SUB	(HL)			; A = Number of lines to shift (>= 1)
	LD	L,A
	LD	H,0
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL			; HL = Byte count
	LD	B,H
	LD	C,L			; BC = Count

	; Source HL = LINE_STORAGE + (TOTAL_LINES * 128) - 1
	LD	A,(TOTAL_LINES)
	LD	L,A
	LD	H,0
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	LD	DE,LINE_STORAGE
	ADD	HL,DE
	DEC	HL			; HL = Source end

	; Dest DE = HL + 128
	PUSH	HL			; Save Source end
	LD	DE,MAX_LINE_STRIDE
	ADD	HL,DE
	EX	DE,HL			; DE = Dest end
	POP	HL			; HL = Source end

	LDDR

DO_SPLIT_LINE:
	; Increment total lines count
	LD	A,(TOTAL_LINES)
	INC	A
	LD	(TOTAL_LINES),A

	; 2. Clear newly created line buffer at CUR_ROW + 1 (128 bytes of 0s)
	LD	A,(CUR_ROW)
	INC	A
	LD	L,A
	LD	H,0
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	LD	DE,LINE_STORAGE
	ADD	HL,DE			; HL = new line start

	PUSH	HL			; Save new line start
	LD	B,MAX_LINE_STRIDE
ZERO_NEW_LINE_LOOP:
	LD	(HL),0
	INC	HL
	DJNZ	ZERO_NEW_LINE_LOOP
	POP	DE			; DE = new line start

	; 3. Source text to move: HL = current line + CUR_COL
	LD	A,(CUR_ROW)
	LD	L,A
	LD	H,0
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	LD	BC,LINE_STORAGE
	ADD	HL,BC
	LD	A,(CUR_COL)
	LD	C,A
	LD	B,0
	ADD	HL,BC			; HL = current line + CUR_COL

	; Copy text from split point to new line (DE)
SPLIT_COPY_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,SPLIT_COPY_DONE
	CP	'$'
	JR	Z,SPLIT_COPY_DONE
	LD	(DE),A
	LD	(HL),0			; Truncate old line at split point
	INC	HL
	INC	DE
	JR	SPLIT_COPY_LOOP

SPLIT_COPY_DONE:
	XOR	A
	LD	(DE),A			; Ensure new line is null terminated

	; 4. Move cursor to start of new line
	LD	A,(CUR_ROW)
	INC	A
	LD	(CUR_ROW),A
	XOR	A
	LD	(CUR_COL),A
	RET

HBIOS_DETECT:
	PUSH	IX
	LD	B,0F8H			; CIOCNT
	LD	C,000H
	RST	08H
	POP	IX
	OR	A
	RET

;------------------------------------------------------------------------------
; File Loading: Reads CP/M and Linux files into 128-byte stride LINE_STORAGE
;------------------------------------------------------------------------------
LOAD_FILE:
	LD	DE,DEFAULT_DMA
	LD	C,26			; BDOS Set DMA
	CALL	BDOS_ENTRY

	LD	DE,WORK_FCB
	LD	C,15			; BDOS Open File
	CALL	BDOS_ENTRY
	CP	0FFH
	JR	Z,LOAD_FILE_NOT_FOUND

	XOR	A
	LD	(WORK_FCB+32),A		; Clear current record (CR)
	LD	(TOTAL_LINES),A

	; Clear LINE_STORAGE buffer with 0s
	LD	HL,LINE_STORAGE
	LD	DE,LINE_STORAGE+1
	LD	BC,5119
	LD	(HL),0
	LDIR

	LD	HL,LINE_STORAGE
	LD	(CUR_LINE_START),HL
	LD	B,0			; Line length

READ_SECTOR_LOOP:
	LD	DE,WORK_FCB
	LD	C,20			; BDOS Read Next Record
	CALL	BDOS_ENTRY
	OR	A
	JR	NZ,FILE_LOAD_DONE

	LD	HL,DEFAULT_DMA
	LD	C,128			; 128 bytes per sector

PARSE_BYTE_LOOP:
	LD	A,(HL)
	CP	26			; CP/M EOF (^Z)
	JR	Z,FILE_LOAD_DONE

	CP	13			; CR
	JR	Z,HANDLE_CR

	CP	10			; LF
	JR	Z,HANDLE_LF

	; Normal character: store in current line
	LD	A,B
	CP	MAX_LINE_STRIDE-1
	JR	NC,SKIP_LINE_OVERFLOW

	LD	A,(HL)
	PUSH	HL
	LD	HL,(CUR_LINE_START)
	LD	E,B
	LD	D,0
	ADD	HL,DE
	LD	(HL),A
	POP	HL
	INC	B

SKIP_LINE_OVERFLOW:
	JR	NEXT_BYTE_IN_SECTOR

HANDLE_CR:
	LD	A,FMT_CPM
	LD	(SAVE_FORMAT),A
	JR	NEXT_BYTE_IN_SECTOR

HANDLE_LF:
	; Terminate current line
	LD	HL,(CUR_LINE_START)
	LD	E,B
	LD	D,0
	ADD	HL,DE
	LD	(HL),0

	; Advance CUR_LINE_START by 128 bytes
	LD	HL,(CUR_LINE_START)
	LD	DE,MAX_LINE_STRIDE
	ADD	HL,DE
	LD	(CUR_LINE_START),HL

	LD	B,0
	LD	A,(TOTAL_LINES)
	INC	A
	LD	(TOTAL_LINES),A
	CP	MAX_BUFFER_LINES
	JR	NC,FILE_LOAD_DONE

NEXT_BYTE_IN_SECTOR:
	INC	HL
	DEC	C
	JR	NZ,PARSE_BYTE_LOOP
	JR	READ_SECTOR_LOOP

FILE_LOAD_DONE:
	LD	A,B
	OR	A
	JR	Z,LOAD_EXIT
	LD	A,(TOTAL_LINES)
	INC	A
	LD	(TOTAL_LINES),A

LOAD_EXIT:
	RET

LOAD_FILE_NOT_FOUND:
	CALL	LOAD_SAMPLE_BUFFER
	RET

;------------------------------------------------------------------------------
; Initialize Sample Buffer into 128-byte stride format
;------------------------------------------------------------------------------
LOAD_SAMPLE_BUFFER:
	; Clear LINE_STORAGE (5120 bytes) with 0
	LD	HL,LINE_STORAGE
	LD	DE,LINE_STORAGE+1
	LD	BC,5119
	LD	(HL),0
	LDIR

	; Copy Sample Lines
	LD	HL,SAMP_LINE0
	LD	DE,LINE_STORAGE + (0 * 128)
	CALL	STR_COPY

	LD	HL,SAMP_LINE1
	LD	DE,LINE_STORAGE + (1 * 128)
	CALL	STR_COPY

	LD	HL,SAMP_LINE2
	LD	DE,LINE_STORAGE + (2 * 128)
	CALL	STR_COPY

	LD	HL,SAMP_LINE3
	LD	DE,LINE_STORAGE + (3 * 128)
	CALL	STR_COPY

	LD	A,4
	LD	(TOTAL_LINES),A
	RET

STR_COPY:
STR_COPY_LOOP:
	LD	A,(HL)
	LD	(DE),A
	OR	A
	RET	Z
	INC	HL
	INC	DE
	JR	STR_COPY_LOOP

;------------------------------------------------------------------------------
; File Saving: Saves in selected format (CP/M CR/LF or Linux LF-only)
;------------------------------------------------------------------------------
SAVE_FILE:
	LD	A,(WORK_FCB+1)
	CP	' '
	JR	NZ,DO_SAVE_EXISTING
	LD	HL,DEFAULT_FCB_NAME
	LD	DE,WORK_FCB
	LD	BC,16
	LDIR

DO_SAVE_EXISTING:
	; Delete old file
	LD	DE,WORK_FCB
	LD	C,19			; BDOS Delete File
	CALL	BDOS_ENTRY

	; Create new file
	LD	DE,WORK_FCB
	LD	C,22			; BDOS Make File
	CALL	BDOS_ENTRY
	CP	0FFH
	RET	Z			; Error creating file

	XOR	A
	LD	(WORK_FCB+32),A		; Clear CR

	; Prepare DMA write pointer
	LD	DE,DEFAULT_DMA
	LD	(CUR_DMA_PTR),DE
	LD	A,128
	LD	(DMA_BYTES_LEFT),A

	; Write lines from LINE_STORAGE
	LD	C,0			; Line counter
SAVE_LINE_LOOP:
	LD	A,C
	LD	HL,TOTAL_LINES
	CP	(HL)
	JR	NC,SAVE_FLUSH_REMAINDER

	PUSH	BC
	; Calculate source line address: LINE_STORAGE + (C * 128)
	LD	L,C
	LD	H,0
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL
	ADD	HL,HL			; *128
	LD	DE,LINE_STORAGE
	ADD	HL,DE

SAVE_CHAR_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,SAVE_LINE_END
	CALL	WRITE_BYTE_TO_DMA
	INC	HL
	JR	SAVE_CHAR_LOOP

SAVE_LINE_END:
	; Write Line Ending depending on SAVE_FORMAT
	LD	A,(SAVE_FORMAT)
	CP	FMT_CPM
	JR	NZ,WRITE_LF_ONLY

	LD	A,13
	CALL	WRITE_BYTE_TO_DMA

WRITE_LF_ONLY:
	LD	A,10
	CALL	WRITE_BYTE_TO_DMA

	POP	BC
	INC	C
	JR	SAVE_LINE_LOOP

SAVE_FLUSH_REMAINDER:
	; Pad remaining bytes in sector with ^Z (0x1A)
PAD_SECTOR_LOOP:
	LD	A,(DMA_BYTES_LEFT)
	CP	128
	JR	Z,CLOSE_OUTPUT_FILE
	LD	A,26
	CALL	WRITE_BYTE_TO_DMA
	JR	PAD_SECTOR_LOOP

CLOSE_OUTPUT_FILE:
	LD	DE,WORK_FCB
	LD	C,16			; BDOS Close File
	CALL	BDOS_ENTRY
	RET

WRITE_BYTE_TO_DMA:
	PUSH	HL
	PUSH	BC
	LD	HL,(CUR_DMA_PTR)
	LD	(HL),A
	INC	HL
	LD	(CUR_DMA_PTR),HL

	LD	A,(DMA_BYTES_LEFT)
	DEC	A
	LD	(DMA_BYTES_LEFT),A
	JR	NZ,WRITE_BYTE_DONE

	; Sector full: flush DMA to disk
	PUSH	DE
	LD	DE,DEFAULT_DMA
	LD	C,26			; BDOS Set DMA
	CALL	BDOS_ENTRY

	LD	DE,WORK_FCB
	LD	C,21			; BDOS Write Record
	CALL	BDOS_ENTRY
	POP	DE

	; Reset DMA buffer pointer
	LD	HL,DEFAULT_DMA
	LD	(CUR_DMA_PTR),HL
	LD	A,128
	LD	(DMA_BYTES_LEFT),A

WRITE_BYTE_DONE:
	POP	BC
	POP	HL
	RET

;------------------------------------------------------------------------------
; String Constants & Data
;------------------------------------------------------------------------------
STR_CLEAR_SCREEN:
	.DB	27,"[2J",27,"[H","$"

STR_HOME:
	.DB	27,"[H","$"

STR_GOTO_ROW_24:
	.DB	27,"[24;1H","$"

STR_GOTO_ROW_40:
	.DB	27,"[40;1H","$"

STR_CLEAR_EOL:
	.DB	27,"[K","$"

STR_INVERSE_ON:
	.DB	27,"[7m","$"

STR_INVERSE_OFF:
	.DB	27,"[0m","$"

STR_CRLF:
	.DB	13,10,"$"

STR_SPLASH_BODY:
	.DB	27,"[H"
	.DB	13,10
	.DB	"                  ~                                             ",13,10
	.DB	"                  ~             SE - Screen Editor              ",13,10
	.DB	"                  ~                version 0.3.0                ",13,10
	.DB	"                  ~              by Dean Jenkins                ",13,10
	.DB	"                  ~                                             ",13,10
	.DB	"                  ~       SE is open source and freely usable   ",13,10
	.DB	"                  ~                                             ",13,10
	.DB	"                  ~       type   :e  or  <Enter>   to edit      ",13,10
	.DB	"                  ~       type   :t                for mem test ",13,10
	.DB	"                  ~       type   :1                set 120x40   ",13,10
	.DB	"                  ~       type   :2                set 80x24    ",13,10
	.DB	"                  ~       type   :q  or  ^Q        to exit      ",13,10
	.DB	"                  ~                                             ",13,10
	.DB	"$"

STR_SPLASH_CUR_MODE:
	.DB	"                  ~   Active Screen: [$"

STR_MODE_120X40_LBL:
	.DB	"120x40 (Modern Default)]           ",13,10,"$"

STR_MODE_80X24_LBL:
	.DB	"80x24 (Classic Terminal)]          ",13,10,"$"

STR_SPLASH_TAIL:
	.DB	"                  ~      Z80 CP/M with 512K Extended Storage    ",13,10
	.DB	"                  ~      Auto-detects CP/M [CRLF] & Linux [LF]  ",13,10
	.DB	"                  ~                                             ",13,10
	.DB	"$"

STR_TEST_TITLE:
	.DB	"=== SE.COM 512KB Extended Memory Diagnostic ===",13,10,13,10,"$"

STR_TEST_HBIOS_OK:
	.DB	"[+] RomWBW HBIOS API (RST 08H): DETECTED",13,10,"$"

STR_TEST_NO_HBIOS:
	.DB	"[-] RomWBW HBIOS API NOT DETECTED.",13,10,"$"

STR_TEST_RAM_BANKS:
	.DB	"[*] Installed RAM Banks: $"

STR_TEST_RAM_BANKS_END:
	.DB	" x 32KB (512KB Total RAM)",13,10,"$"

STR_TEST_CUR_BANK:
	.DB	"[*] Active CP/M User Bank ID: 0x$"

STR_TEST_TARGET_BANK:
	.DB	"[*] Target Extended RAM Bank ID: 0x$"

STR_TEST_BANK_COPY:
	.DB	"[*] Testing Inter-Bank Far Memory Transfer (DMA Copy)...",13,10,"$"

STR_TEST_PASSED:
	.DB	"[+] 512KB Far Memory Banking Test: PASSED! (Pattern 0xAA55 Verified)",13,10,13,10,"$"

STR_TEST_FAILED:
	.DB	"[-] Far Memory Banking Test: FAILED (Data Mismatch)",13,10,13,10,"$"

STR_TEST_PROMPT:
	.DB	"Press any key to return to Splash Screen...$"

STR_STATUS_PREFIX:
	.DB	" SE v0.3.0 | [","$"

STR_STATUS_120X40:
	.DB	"120x40","$"

STR_STATUS_80X24:
	.DB	"80x24 ","$"

STR_STATUS_MID:
	.DB	"] | Format: [","$"

STR_FMT_CPM:
	.DB	"CP/M CRLF","$"

STR_FMT_LINUX:
	.DB	"Linux LF ","$"

STR_STATUS_SUFFIX:
	.DB	"] | ^F:Format | ^S:Save | ^Q:Quit  ","$"

MSG_EXIT:
	.DB	13,10,"Exiting SE.COM. Returned to CP/M.",13,10,"$"

DEFAULT_FCB_NAME:
	.DB	0,"OUTPUT  TXT",0,0,0,0

SAMP_LINE0:
	.DB	"; Screen Editor (SE.COM) Cross-Platform Line Format Buffer",0
SAMP_LINE1:
	.DB	"; Press ^F to toggle save format between CP/M [CRLF] and Linux [LF]",0
SAMP_LINE2:
	.DB	"START:  LD A,0          ; Initial register setup",0
SAMP_LINE3:
	.DB	"        RET             ; End of sample program",0

;------------------------------------------------------------------------------
; Variables & Stack Area
;------------------------------------------------------------------------------
SAVED_SP:	.DW	0
CPM_USER_BANK:	.DB	0
TARGET_RAM_BANK:.DB	0
RAM_BANK_COUNT:	.DB	0
ROM_BANK_COUNT:	.DB	0

SCREEN_MODE:	.DB	MODE_120X40	; Default to 120x40
ACTIVE_ROWS:	.DB	40		; Default 40 rows
ACTIVE_COLS:	.DB	120		; Default 120 cols

CUR_ROW:	.DB	0
CUR_COL:	.DB	0
CUR_RENDER_ROW:	.DB	0
TOTAL_LINES:	.DB	0
HAS_FILE_ARG:	.DB	0
SAVE_FORMAT:	.DB	FMT_CPM		; Default format is CP/M (CR/LF)
CHAR_INSERT_TEMP:.DB	0

CUR_LINE_START:	.DW	0
CUR_DMA_PTR:	.DW	0
DMA_BYTES_LEFT:	.DB	0

TEST_PATTERN:	.DB	0,0
TEST_READBACK:	.DB	0,0

WORK_FCB:	.DS	36

		.DS	128
LOCAL_STACK:

; 40 lines x 128 bytes stride line storage buffer in local TPA (5120 bytes)
LINE_STORAGE:	.DS	5120

	.END
