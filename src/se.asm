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
MAX_BUFFER_LINES .EQU	200		; Up to 200 lines in local memory buffer (25.6 KB)

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

	; Initialize Direct BIOS Console Vectors
	CALL	INIT_BIOS_JUMPS

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
	LD	(TARGET_COL),A
	LD	(TOP_LINE),A
	CALL	TERM_INIT
	CALL	RENDER_SCREEN
	JP	MAIN_LOOP

ENTER_EDITOR:
	CALL	LOAD_SAMPLE_BUFFER
	XOR	A
	LD	(CUR_ROW),A
	LD	(CUR_COL),A
	LD	(TARGET_COL),A
	LD	(TOP_LINE),A
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
	JR	NZ,CHECK_CTRL_D
	LD	A,(SAVE_FORMAT)
	XOR	1			; Toggle between 0 (CP/M) and 1 (Linux)
	LD	(SAVE_FORMAT),A
	CALL	RENDER_STATUS_BAR
	JR	MAIN_LOOP

CHECK_CTRL_D:
	; Command: Ctrl+D -> Delete character under cursor (Forward Delete)
	CP	4
	JR	NZ,CHECK_ENTER
	CALL	DO_DELETE_FORWARD
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
	LD	A,(CUR_COL)
	OR	A
	JR	Z,DO_HANDLE_BS_COL0

	; Normal character deletion on current line (CUR_COL > 0)
	CALL	DO_DELETE_CHAR
	CALL	RENDER_CURRENT_LINE
	JR	MAIN_LOOP

DO_HANDLE_BS_COL0:
	; Backspace at column 0: delete line if blank
	CALL	DO_DELETE_BLANK_LINE
	JR	MAIN_LOOP

CHECK_ESC_SEQ:
	; Check for VT100 Escape sequences (Arrow keys)
	CP	KEY_ESC
	JR	NZ,CHECK_PRINTABLE_CHAR
	CALL	HANDLE_VT100_ESC
	CALL	RENDER_STATUS_BAR
	JR	MAIN_LOOP

CHECK_PRINTABLE_CHAR:
	; Check if Tab key is pressed (expand to 8-character tab stops)
	CP	KEY_TAB			; 9
	JR	NZ,CHECK_PRINTABLE_REGULAR
	CALL	DO_TAB_INSERT
	CALL	RENDER_CURRENT_LINE
	JR	MAIN_LOOP

CHECK_PRINTABLE_REGULAR:
	CP	' '
	JR	C,MAIN_LOOP
	CP	127
	JR	NC,MAIN_LOOP

DO_INSERT_CHAR:
	CALL	DO_CHAR_INSERT
	CALL	RENDER_CURRENT_LINE
	JR	MAIN_LOOP

;------------------------------------------------------------------------------
; Tab Key Insertion at (CUR_ROW, CUR_COL) - Expands to 8-column tab stops
;------------------------------------------------------------------------------
DO_TAB_INSERT:
	; Calculate K = 8 - (CUR_COL & 7)
	LD	A,(CUR_COL)
	AND	7
	LD	C,A
	LD	A,8
	SUB	C			; A = K (1..8 spaces to insert)
	LD	B,A			; B = loop counter

TAB_INSERT_SPACE_LOOP:
	PUSH	BC
	LD	A,' '			; Insert a single space using proven DO_CHAR_INSERT
	CALL	DO_CHAR_INSERT
	POP	BC
	DJNZ	TAB_INSERT_SPACE_LOOP
	RET

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

INIT_BIOS_JUMPS:
	LD	HL,(0001H)		; HL = Address of BIOS WBOOT (+3)
	DEC	HL
	DEC	HL
	DEC	HL			; HL = BIOS Base (BOOT, +0)
	LD	DE,6
	ADD	HL,DE			; HL = BIOS CONST (+6)
	LD	(BIOS_CONST_VEC),HL
	INC	HL
	INC	HL
	INC	HL			; HL = BIOS CONIN (+9)
	LD	(BIOS_CONIN_VEC),HL
	INC	HL
	INC	HL
	INC	HL			; HL = BIOS CONOUT (+12)
	LD	(BIOS_CONOUT_VEC),HL
	RET

PRINT_STR:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	EX	DE,HL			; HL = pointer to string
PRINT_STR_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,PRINT_STR_DONE
	CP	'$'
	JR	Z,PRINT_STR_DONE
	CALL	PUTC
	INC	HL
	JR	PRINT_STR_LOOP
PRINT_STR_DONE:
	POP	HL
	POP	DE
	POP	BC
	RET

PUTC:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	C,A			; C = character for BIOS CONOUT
	LD	HL,(BIOS_CONOUT_VEC)
	CALL	CALL_HL
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

GET_KEY:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	HL,(BIOS_CONIN_VEC)
	CALL	CALL_HL			; Returns A = character
	POP	HL
	POP	DE
	POP	BC
	RET

CALL_HL:
	JP	(HL)

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

	LD	C,0			; Screen row index (0 .. ACTIVE_ROWS-2)
RENDER_ROW_LOOP:
	PUSH	BC
	; Calculate buffer line to render: CUR_RENDER_ROW = TOP_LINE + C
	LD	A,(TOP_LINE)
	ADD	A,C
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
	; Move to start of current screen line: ESC [ <(CUR_ROW - TOP_LINE) + 1> ; 1 H
	LD	A,27
	CALL	PUTC
	LD	A,'['
	CALL	PUTC

	LD	A,(TOP_LINE)
	LD	B,A
	LD	A,(CUR_ROW)
	SUB	B
	INC	A			; Screen row (1-indexed for terminal)
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
	LD	B,0
PRINT_CUR_LINE_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,PRINT_CUR_LINE_DONE
	CALL	PUTC
	INC	HL
	INC	B
	LD	A,(ACTIVE_COLS)
	CP	B
	JR	Z,PRINT_CUR_LINE_DONE
	JR	PRINT_CUR_LINE_LOOP

PRINT_CUR_LINE_DONE:
	CALL	RENDER_STATUS_BAR
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
	LD	B,0
PRINT_LINE_CHARS:
	LD	A,(HL)
	OR	A
	JR	Z,PRINT_LINE_END
	CALL	PUTC
	INC	HL
	INC	B
	LD	A,(ACTIVE_COLS)
	CP	B
	JR	Z,PRINT_LINE_END
	JR	PRINT_LINE_CHARS

PRINT_LINE_END:
	LD	A,13
	CALL	PUTC
	LD	A,10
	CALL	PUTC
	RET

LOCATE_STATUS_ROW:
	; Move cursor to status row: ESC [ <ACTIVE_ROWS> ; 1 H
	LD	A,27
	CALL	PUTC
	LD	A,'['
	CALL	PUTC
	LD	A,(ACTIVE_ROWS)
	CALL	PRINT_DEC_BYTE
	LD	A,';'
	CALL	PUTC
	LD	A,'1'
	CALL	PUTC
	LD	A,'H'
	CALL	PUTC
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

	; Print dynamic cursor position: Row, Col
	LD	DE,STR_STATUS_POS
	CALL	PRINT_STR
	LD	A,(CUR_ROW)
	INC	A			; 1-indexed
	CALL	PRINT_DEC_BYTE
	LD	DE,STR_STATUS_COL
	CALL	PRINT_STR
	LD	A,(CUR_COL)		; 0-indexed
	CALL	PRINT_DEC_BYTE
	LD	A,' '
	CALL	PUTC

	; Clear remainder of status line to EOL in inverse video
	LD	DE,STR_CLEAR_EOL
	CALL	PRINT_STR

	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	CALL	LOCATE_CURSOR
	RET

LOCATE_CURSOR:
	; Emit ESC [ <ScreenRow+1> ; <Col+1> H
	LD	A,27
	CALL	PUTC
	LD	A,'['
	CALL	PUTC

	; Screen Row = CUR_ROW - TOP_LINE (1-indexed for terminal)
	LD	A,(TOP_LINE)
	LD	B,A
	LD	A,(CUR_ROW)
	SUB	B
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
CHECK_KEY_READY:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	HL,(BIOS_CONST_VEC)
	CALL	CALL_HL			; Returns A = 0xFF if char ready, 0x00 if not
	POP	HL
	POP	DE
	POP	BC
	OR	A
	RET

HANDLE_VT100_ESC:
	; Check if a character follows ESC within a short timeout
	LD	BC,1000			; Timeout loop count
WAIT_ESC_BYTE:
	CALL	CHECK_KEY_READY
	JR	NZ,GOT_ESC_BYTE
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,WAIT_ESC_BYTE
	; Timeout: Standalone ESC key pressed (do not block or discard future keys)
	RET

GOT_ESC_BYTE:
	CALL	GET_KEY
	CP	'['
	JR	Z,HANDLE_CSI
	CP	'O'
	JR	Z,HANDLE_CSI
	CP	KEY_ESC
	JR	Z,HANDLE_VT100_ESC
	RET

HANDLE_CSI:
	CALL	GET_KEY
	CP	'A'			; Up Arrow
	JP	Z,CURSOR_UP
	CP	'B'			; Down Arrow
	JP	Z,CURSOR_DOWN
	CP	'C'			; Right Arrow
	JP	Z,CURSOR_RIGHT
	CP	'D'			; Left Arrow
	JP	Z,CURSOR_LEFT
	CP	'H'			; Home
	JP	Z,CURSOR_HOME
	CP	'F'			; End
	JP	Z,CURSOR_END
	CP	'3'			; Delete Key (ESC [ 3 ~)
	JP	Z,HANDLE_CSI_DEL

	; Check if parameter/modifier digits present (e.g. 1;2A, 1~, 4~)
	CP	'0'
	JR	C,CSI_DONE
	CP	'9'+1
	JR	C,HANDLE_CSI_LOOP
	RET

HANDLE_CSI_DEL:
	; Consume trailing '~'
	CALL	GET_KEY
	CALL	DO_DELETE_FORWARD
	RET

HANDLE_CSI_LOOP:
	CALL	GET_KEY
	CP	'~'
	RET	Z
	CP	'A'
	JP	Z,CURSOR_UP
	CP	'B'
	JP	Z,CURSOR_DOWN
	CP	'C'
	JP	Z,CURSOR_RIGHT
	CP	'D'
	JP	Z,CURSOR_LEFT
	CP	'H'
	JP	Z,CURSOR_HOME
	CP	'F'
	JP	Z,CURSOR_END
	CP	';'
	JR	Z,HANDLE_CSI_LOOP
	CP	'0'
	JR	C,CSI_DONE
	CP	'9'+1
	JR	C,HANDLE_CSI_LOOP
CSI_DONE:
	RET

CURSOR_HOME:
	XOR	A
	LD	(CUR_COL),A
	LD	(TARGET_COL),A
	RET

CURSOR_END:
	CALL	GET_CUR_ROW_LEN
	LD	A,B
	LD	(CUR_COL),A
	LD	(TARGET_COL),A
	RET

;------------------------------------------------------------------------------
; Get Length of Current Line at CUR_ROW
; Returns: B = Line length (0..120), HL = Pointer to start of line
; Preserves: DE
;------------------------------------------------------------------------------
GET_CUR_ROW_LEN:
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
	ADD	HL,DE			; HL = line start
	PUSH	HL			; Save line start
	LD	B,0
GET_ROW_LEN_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,GET_ROW_LEN_DONE
	INC	HL
	INC	B
	LD	A,B
	CP	MAX_LINE_STRIDE-2
	JR	NC,GET_ROW_LEN_DONE
	JR	GET_ROW_LEN_LOOP
GET_ROW_LEN_DONE:
	POP	HL			; HL = line start
	RET

;------------------------------------------------------------------------------
; Adjust CUR_COL to Sticky TARGET_COL Clamped to Current Line Length
; Preserves: TARGET_COL
;------------------------------------------------------------------------------
ADJUST_COL_TO_TARGET:
	CALL	GET_CUR_ROW_LEN		; B = line length
	LD	A,(ACTIVE_COLS)
	DEC	A
	CP	B
	JR	C,ACT_USE_ACTIVE
	LD	A,B			; Max column = min(line_length, ACTIVE_COLS - 1)
ACT_USE_ACTIVE:
	LD	C,A			; C = max valid column for this line
	LD	A,(TARGET_COL)		; A = desired sticky column
	CP	C
	JR	C,ACT_SET_COL		; If TARGET_COL < max valid, use TARGET_COL
	LD	A,C			; Otherwise clamp to max valid column
ACT_SET_COL:
	LD	(CUR_COL),A
	RET

CURSOR_UP:
	LD	A,(CUR_ROW)
	OR	A
	RET	Z			; If already at top line of document, cannot move up
	DEC	A
	LD	(CUR_ROW),A
	; Check if CUR_ROW < TOP_LINE (scrolled past top of screen window)
	LD	HL,TOP_LINE
	CP	(HL)
	JR	NC,CUR_UP_NO_SCROLL
	; Scrolled up: TOP_LINE = CUR_ROW
	LD	(HL),A
	CALL	ADJUST_COL_TO_TARGET
	CALL	RENDER_SCREEN
	RET

CUR_UP_NO_SCROLL:
	CALL	ADJUST_COL_TO_TARGET
	RET

CURSOR_DOWN:
	LD	A,(TOTAL_LINES)
	OR	A
	RET	Z			; If 0 lines, cannot move down
	DEC	A			; Max valid row index = TOTAL_LINES - 1
	LD	B,A
	LD	A,(CUR_ROW)
	CP	B
	RET	NC			; If CUR_ROW >= TOTAL_LINES - 1, do not go past text
	INC	A
	LD	(CUR_ROW),A

	; Check if CUR_ROW moved past bottom of screen window
	LD	A,(TOP_LINE)
	LD	B,A
	LD	A,(CUR_ROW)
	SUB	B			; A = screen row (0 .. )
	LD	C,A
	LD	A,(ACTIVE_ROWS)
	DEC	A
	DEC	A			; A = max screen row index (ACTIVE_ROWS - 2)
	CP	C
	JR	NC,CUR_DOWN_NO_SCROLL	; If screen_row <= max screen row index, no scroll
	; Scrolled down: TOP_LINE = TOP_LINE + 1
	LD	A,(TOP_LINE)
	INC	A
	LD	(TOP_LINE),A
	CALL	ADJUST_COL_TO_TARGET
	CALL	RENDER_SCREEN
	RET

CUR_DOWN_NO_SCROLL:
	CALL	ADJUST_COL_TO_TARGET
	RET

CURSOR_LEFT:
	LD	A,(CUR_COL)
	OR	A
	JR	Z,CURSOR_LEFT_PREV_LINE
	DEC	A
	LD	(CUR_COL),A
	LD	(TARGET_COL),A		; Horizontal movement updates sticky target column
	RET

CURSOR_LEFT_PREV_LINE:
	; Wrap to end of previous line if CUR_ROW > 0
	LD	A,(CUR_ROW)
	OR	A
	RET	Z			; If at line 0, cannot wrap back
	DEC	A
	LD	(CUR_ROW),A
	; Check if scrolled above top of viewport
	LD	HL,TOP_LINE
	CP	(HL)
	JR	NC,CL_NO_SCROLL
	LD	(HL),A
	CALL	GET_CUR_ROW_LEN		; B = prev line length
	LD	A,B
	LD	(CUR_COL),A
	LD	(TARGET_COL),A
	CALL	RENDER_SCREEN
	RET

CL_NO_SCROLL:
	CALL	GET_CUR_ROW_LEN		; B = prev line length
	LD	A,B
	LD	(CUR_COL),A
	LD	(TARGET_COL),A
	RET

CURSOR_RIGHT:
	CALL	GET_CUR_ROW_LEN		; B = current line length
	LD	A,(ACTIVE_COLS)
	DEC	A
	CP	B
	JR	C,CR_USE_ACTIVE
	LD	A,B			; Max column = min(line_length, ACTIVE_COLS - 1)
CR_USE_ACTIVE:
	LD	C,A
	LD	A,(CUR_COL)
	CP	C
	JR	NC,CURSOR_RIGHT_NEXT_LINE ; If at or past EOL, wrap to next line!
	INC	A
	LD	(CUR_COL),A
	LD	(TARGET_COL),A		; Horizontal movement updates sticky target column
	RET

CURSOR_RIGHT_NEXT_LINE:
	; Wrap to start of next line if CUR_ROW + 1 < TOTAL_LINES
	LD	A,(TOTAL_LINES)
	OR	A
	RET	Z
	DEC	A			; Max valid row = TOTAL_LINES - 1
	LD	B,A
	LD	A,(CUR_ROW)
	CP	B
	RET	NC			; If on last line, cannot wrap forward
	INC	A
	LD	(CUR_ROW),A
	XOR	A
	LD	(CUR_COL),A
	LD	(TARGET_COL),A

	; Check if scrolled past bottom of screen window
	LD	A,(TOP_LINE)
	LD	B,A
	LD	A,(CUR_ROW)
	SUB	B			; A = screen row
	LD	C,A
	LD	A,(ACTIVE_ROWS)
	DEC	A
	DEC	A			; A = max screen row index (ACTIVE_ROWS - 2)
	CP	C
	RET	NC			; If screen row <= max, no scroll
	LD	A,(TOP_LINE)
	INC	A
	LD	(TOP_LINE),A
	CALL	RENDER_SCREEN
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
	CALL	GET_CUR_ROW_LEN		; HL = line start, B = current line text length

	; 3. Check screen width limit: Prevent line from exceeding ACTIVE_COLS (120 chars)
	LD	A,(ACTIVE_COLS)
	CP	B
	JR	Z,CHECK_AT_EOL_REPLACE
	JR	C,CHECK_AT_EOL_REPLACE
	JR	LINE_LEN_OK

CHECK_AT_EOL_REPLACE:
	; Line is already at maximum capacity (>= ACTIVE_COLS).
	; Only allow replacing the rightmost character at CUR_COL == ACTIVE_COLS - 1
	LD	A,(ACTIVE_COLS)
	DEC	A
	LD	C,A
	LD	A,(CUR_COL)
	CP	C
	RET	NZ			; If not at rightmost column, cannot insert into full line!

	; Replace character at CUR_COL (ACTIVE_COLS - 1)
	PUSH	HL
	LD	E,C
	LD	D,0
	ADD	HL,DE			; HL = line_start + ACTIVE_COLS - 1
	LD	A,(CHAR_INSERT_TEMP)
	LD	(HL),A
	INC	HL
	XOR	A
	LD	(HL),A			; Null terminate at ACTIVE_COLS
	POP	HL
	RET

LINE_LEN_OK:
	; 4. Compare CUR_COL with line length (B)
	LD	A,(CUR_COL)
	CP	B
	JR	NC,DO_PAD_AND_APPEND	; If CUR_COL >= length: pad spaces and append

	; 5. If CUR_COL < length: shift characters from (line_start + B) down to (line_start + CUR_COL)
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

	PUSH	DE			; Save line_start + B + 1
	LDDR
	POP	DE			; DE = line_start + B + 1
	XOR	A
	LD	(DE), A			; Guarantee null terminator at new end of line

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
	LD	(TARGET_COL),A		; Sync sticky target column on typing
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
	LD	(TARGET_COL),A		; Sync sticky target column on Backspace

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
; Forward Character Deletion at (CUR_ROW, CUR_COL) - Delete Key Handling
;------------------------------------------------------------------------------
DO_DELETE_FORWARD:
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
	ADD	HL,DE			; HL = line_start

	; Check if (line_start + CUR_COL) is at or beyond end of line (0)
	PUSH	HL
	LD	A,(CUR_COL)
	LD	E,A
	LD	D,0
	ADD	HL,DE			; HL = character to delete under cursor
	LD	A,(HL)
	OR	A
	JR	Z,DEL_FWD_AT_EOL

	; Character exists under cursor: shift characters left from HL+1 into HL
DEL_FWD_SHIFT_LOOP:
	INC	HL
	LD	A,(HL)
	DEC	HL
	LD	(HL),A
	OR	A
	JR	Z,DEL_FWD_DONE
	INC	HL
	JR	DEL_FWD_SHIFT_LOOP

DEL_FWD_DONE:
	POP	HL
	CALL	RENDER_CURRENT_LINE
	RET

DEL_FWD_AT_EOL:
	POP	HL
	RET

;------------------------------------------------------------------------------
; Delete Blank Line at (CUR_ROW, 0) - Backspace at Column 0 Handling
;------------------------------------------------------------------------------
DO_DELETE_BLANK_LINE:
	; Check if TOTAL_LINES <= 1 and CUR_ROW == 0
	LD	A,(TOTAL_LINES)
	CP	2
	JR	C,DEL_BLANK_SINGLE_LINE

	; 1. Calculate pointer to current line: HL = LINE_STORAGE + (CUR_ROW * 128)
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
	ADD	HL,DE			; HL = current line start

	; 2. Check if current line is blank (only spaces or null)
	PUSH	HL
	LD	B,0
CHECK_BLANK_SCAN:
	LD	A,(HL)
	OR	A
	JR	Z,LINE_CONFIRMED_BLANK
	CP	' '
	JR	NZ,LINE_HAS_TEXT
	INC	HL
	INC	B
	LD	A,B
	CP	MAX_LINE_STRIDE-2
	JR	NC,LINE_CONFIRMED_BLANK
	JR	CHECK_BLANK_SCAN

LINE_HAS_TEXT:
	POP	HL
	RET				; Non-blank line: do not delete!

LINE_CONFIRMED_BLANK:
	POP	DE			; DE = current line start (destination for LDIR)

	; 3. Check if there are lines below CUR_ROW to shift up
	; Number of lines below = TOTAL_LINES - 1 - CUR_ROW
	LD	A,(TOTAL_LINES)
	DEC	A
	LD	HL,CUR_ROW
	CP	(HL)
	JR	Z,DEL_BLANK_LAST_LINE	; If CUR_ROW == TOTAL_LINES - 1, no lines below!

	; Count in lines = TOTAL_LINES - 1 - CUR_ROW
	SUB	(HL)			; A = number of lines to shift (>= 1)
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
	LD	C,L			; BC = Byte count

	; Source HL = DE + 128 (next line start)
	PUSH	DE			; Save dest start
	EX	DE,HL			; HL = dest start
	LD	DE,MAX_LINE_STRIDE
	ADD	HL,DE			; HL = source start (dest + 128)
	POP	DE			; DE = dest start

	LDIR				; Shift lines below upwards!

DEL_BLANK_LAST_LINE:
	; Decrement TOTAL_LINES
	LD	A,(TOTAL_LINES)
	DEC	A
	LD	(TOTAL_LINES),A

	; Clear the newly freed line buffer at TOTAL_LINES (128 bytes of 0s)
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
	ADD	HL,DE			; HL = freed line buffer

	PUSH	HL
	LD	B,MAX_LINE_STRIDE
CLEAR_FREED_LINE_LOOP:
	LD	(HL),0
	INC	HL
	DJNZ	CLEAR_FREED_LINE_LOOP
	POP	HL

	; If CUR_ROW > 0, move cursor up to previous line and set CUR_COL to end of line
	LD	A,(CUR_ROW)
	OR	A
	JR	Z,DEL_BLANK_AT_ROW0
	DEC	A
	LD	(CUR_ROW),A
	; Check if CUR_ROW < TOP_LINE
	LD	HL,TOP_LINE
	CP	(HL)
	JR	NC,DEL_BLANK_NO_SCROLL
	LD	(HL),A
DEL_BLANK_NO_SCROLL:

	; Calculate previous line length to set CUR_COL
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
	ADD	HL,DE			; HL = previous line start

	LD	B,0
PREV_LINE_LEN_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,PREV_LINE_LEN_DONE
	INC	HL
	INC	B
	LD	A,(ACTIVE_COLS)
	DEC	A
	CP	B
	JR	C,PREV_LINE_LEN_DONE
	JR	PREV_LINE_LEN_LOOP

PREV_LINE_LEN_DONE:
	LD	A,B
	LD	(CUR_COL),A
	LD	(TARGET_COL),A

DEL_BLANK_AT_ROW0:
	CALL	RENDER_SCREEN
	RET

DEL_BLANK_SINGLE_LINE:
	; When only 1 line exists, just ensure it is cleared
	LD	HL,LINE_STORAGE
	LD	B,MAX_LINE_STRIDE
CLEAR_SINGLE_LOOP:
	LD	(HL),0
	INC	HL
	DJNZ	CLEAR_SINGLE_LOOP
	XOR	A
	LD	(CUR_ROW),A
	LD	(CUR_COL),A
	LD	(TARGET_COL),A
	LD	(TOP_LINE),A
	LD	A,1
	LD	(TOTAL_LINES),A
	CALL	RENDER_SCREEN
	RET

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

	; 3. Source text to move: Check if CUR_COL < line length before splitting
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
	ADD	HL,BC			; HL = current line start

	; Scan current line length
	PUSH	HL
	LD	B,0
INSERT_SCAN_LEN:
	LD	A,(HL)
	OR	A
	JR	Z,INSERT_SCAN_DONE
	INC	HL
	INC	B
	LD	A,B
	CP	MAX_LINE_STRIDE-2
	JR	NC,INSERT_SCAN_DONE
	JR	INSERT_SCAN_LEN

INSERT_SCAN_DONE:
	POP	HL			; HL = current line start
	; B = current line length

	LD	A,(CUR_COL)
	CP	B
	JR	NC,SPLIT_COPY_DONE	; If CUR_COL >= line length, new line is completely blank!

	; CUR_COL < line length: copy text from (current line + CUR_COL) to new line (DE)
	LD	A,(CUR_COL)
	LD	C,A
	LD	B,0
	ADD	HL,BC			; HL = current line + CUR_COL

	; Copy text from split point to new line (DE)
SPLIT_COPY_LOOP:
	LD	A,(HL)
	OR	A
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
	LD	(TARGET_COL),A

	; Check if new line scrolled past bottom of screen window
	LD	A,(TOP_LINE)
	LD	B,A
	LD	A,(CUR_ROW)
	SUB	B			; A = screen row
	LD	C,A
	LD	A,(ACTIVE_ROWS)
	DEC	A
	DEC	A			; A = max screen row index (ACTIVE_ROWS - 2)
	CP	C
	RET	NC			; If screen row <= max, no scroll
	LD	A,(TOP_LINE)
	INC	A
	LD	(TOP_LINE),A
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

	CP	KEY_TAB			; TAB (expand to 8-space tab stops)
	JR	Z,HANDLE_LOAD_TAB

	; Normal character: store in current line
	LD	A,(ACTIVE_COLS)
	CP	B
	JR	Z,SKIP_LINE_OVERFLOW
	JR	C,SKIP_LINE_OVERFLOW

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

HANDLE_LOAD_TAB:
	; Calculate number of spaces to pad: 8 - (B & 7)
	LD	A,B
	AND	7
	LD	E,A
	LD	A,8
	SUB	E			; A = spaces count (1..8)
	LD	E,A			; E = loop counter
LOAD_TAB_PAD_LOOP:
	LD	A,(ACTIVE_COLS)
	CP	B
	JR	Z,NEXT_BYTE_IN_SECTOR
	JR	C,NEXT_BYTE_IN_SECTOR
	PUSH	HL
	LD	HL,(CUR_LINE_START)
	LD	A,B
	PUSH	DE
	LD	E,A
	LD	D,0
	ADD	HL,DE
	LD	(HL),' '
	POP	DE
	POP	HL
	INC	B
	DEC	E
	JR	NZ,LOAD_TAB_PAD_LOOP
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
	; Clear LINE_STORAGE (25600 bytes = 200 lines * 128) with 0
	LD	HL,LINE_STORAGE
	LD	DE,LINE_STORAGE+1
	LD	BC,25599
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

	; Zero entire WORK_FCB (36 bytes)
	LD	HL,WORK_FCB
	LD	(HL),0
	LD	DE,WORK_FCB+1
	LD	BC,35
	LDIR

	; Copy default filename (0, "OUTPUT  TXT")
	LD	HL,DEFAULT_FCB_NAME
	LD	DE,WORK_FCB
	LD	BC,12
	LDIR

DO_SAVE_EXISTING:
	; Zero FCB extent and record bytes (bytes 12..35)
	LD	HL,WORK_FCB+12
	LD	(HL),0
	LD	DE,WORK_FCB+13
	LD	BC,23
	LDIR

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
	.DB	"                  ~                version 0.4.0                ",13,10
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
	.DB	" SE v0.4.0 | ","$"

STR_STATUS_120X40:
	.DB	"120x40 | ","$"

STR_STATUS_80X24:
	.DB	"80x24 | ","$"

STR_FMT_CPM:
	.DB	"CP/M | ","$"

STR_FMT_LINUX:
	.DB	"Linux | ","$"

STR_STATUS_SUFFIX:
	.DB	"^F:Fmt ^S:Save ^Q:Quit | ","$"

STR_STATUS_POS:
	.DB	"Row ","$"

STR_STATUS_COL:
	.DB	", Col ","$"

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
BIOS_CONST_VEC:	.DW	0
BIOS_CONIN_VEC:	.DW	0
BIOS_CONOUT_VEC:.DW	0
CPM_USER_BANK:	.DB	0
TARGET_RAM_BANK:.DB	0
RAM_BANK_COUNT:	.DB	0
ROM_BANK_COUNT:	.DB	0

SCREEN_MODE:	.DB	MODE_120X40	; Default to 120x40
ACTIVE_ROWS:	.DB	40		; Default 40 rows
ACTIVE_COLS:	.DB	120		; Default 120 cols

CUR_ROW:	.DB	0
CUR_COL:	.DB	0
TARGET_COL:	.DB	0		; Sticky column for vertical (Up/Down) movement
TOP_LINE:	.DB	0		; Top visible buffer line index on screen
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

		.DS	512
LOCAL_STACK:

; 200 lines x 128 bytes stride line storage buffer in local TPA (25,600 bytes)
LINE_STORAGE:	.DS	25600

	.END
