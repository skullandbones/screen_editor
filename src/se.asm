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
MAX_FAR_BANKS	.EQU	14		; Up to 14 extended 32KB RAM banks (448 KB)
CACHE_SIZE_LINES .EQU	48		; 48 lines in local working cache (6 KB)
MAX_DOC_LINES	.EQU	3584		; 14 banks * 256 lines = 3584 total lines

KEY_CTRL_B	.EQU	2		; Toggle Block Highlighting
KEY_CTRL_C	.EQU	3
KEY_CTRL_Q	.EQU	17
KEY_CTRL_S	.EQU	19
KEY_CTRL_O	.EQU	15		; Open File Screen
KEY_CTRL_K	.EQU	11		; Show Editor Mode Keys Screen
KEY_CTRL_F	.EQU	6		; Toggle CP/M <-> Linux line endings
KEY_CTRL_U	.EQU	21		; Page Up
KEY_CTRL_V	.EQU	22		; Page Down
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

	; Query RomWBW User Bank and Initialize Far RAM Banks
	CALL	BUFFER_INIT

	; Check if filename was provided in FCB1
	CALL	CHECK_COMMAND_LINE

	; Initialize directory drive from default disk or FCB
	CALL	INIT_DIR_DRIVE

	; If file argument was given, load file and go straight to editor
	LD	A,(HAS_FILE_ARG)
	OR	A
	JR	NZ,DO_AUTO_LOAD

	; Otherwise show splash screen
	CALL	SHOW_SPLASH_SCREEN
	CALL	RENDER_STATUS_BAR
	JP	MAIN_LOOP

DO_AUTO_LOAD:
	CALL	LOAD_FILE
	JR	C,AUTO_LOAD_NOT_FOUND
	LD	A,1
	LD	(IN_EDITOR_MODE),A
	LD	HL,0
	LD	(CUR_DOC_ROW),HL
	LD	(TOP_DOC_ROW),HL
	XOR	A
	LD	(CUR_COL),A
	LD	(TARGET_COL),A
	CALL	TERM_INIT
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	JP	MAIN_LOOP

AUTO_LOAD_NOT_FOUND:
	LD	DE,STR_FILE_NOT_FOUND
	CALL	PRINT_STR
	LD	SP,(SAVED_SP)
	RET

ENTER_EDITOR:
	LD	A,(IN_EDITOR_MODE)
	OR	A
	JR	NZ,RESUME_EDITOR

	LD	A,1
	LD	(IN_EDITOR_MODE),A
	CALL	INIT_EMPTY_DOCUMENT
	LD	HL,0
	LD	(CUR_DOC_ROW),HL
	LD	(TOP_DOC_ROW),HL
	XOR	A
	LD	(CUR_COL),A
	LD	(TARGET_COL),A

RESUME_EDITOR:
	CALL	TERM_INIT
	CALL	RENDER_SCREEN
	RET

SHOW_SPLASH_SCREEN:
	XOR	A
	LD	(BLOCK_ACTIVE),A
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

	; Option: 'F' or 'f' -> Run Multi-Sector File I/O Test
	CP	'f'
	JR	Z,DO_FILE_TEST
	CP	'F'
	JR	Z,DO_FILE_TEST

	; Option: 'O' or 'o' -> Open File Screen
	CP	'o'
	JR	Z,DO_SPLASH_OPEN
	CP	'O'
	JR	Z,DO_SPLASH_OPEN

	; Option: 'S' or 's' -> Save File Screen
	CP	's'
	JR	Z,DO_SPLASH_SAVE
	CP	'S'
	JR	Z,DO_SPLASH_SAVE

	; Option: '1' -> Modern Screen Mode (120x40)
	CP	'1'
	JR	Z,DO_SET_120X40

	; Option: '2' -> Classic Screen Mode (80x24)
	CP	'2'
	JR	Z,DO_SET_80X24

	; Option: 'E' or 'e' or Enter -> Enter/Resume Editor
	CP	'e'
	JR	Z,ENTER_EDITOR
	CP	'E'
	JR	Z,ENTER_EDITOR
	CP	KEY_ENTER
	JR	Z,ENTER_EDITOR

	JR	SPLASH_LOOP

DO_SET_120X40:
	CALL	SET_MODE_120X40
	JR	SHOW_SPLASH_SCREEN

DO_SET_80X24:
	CALL	SET_MODE_80X24
	JR	SHOW_SPLASH_SCREEN

DO_MEM_TEST:
	CALL	RUN_MEM_TEST
	CALL	GET_KEY
	JR	SHOW_SPLASH_SCREEN

DO_FILE_TEST:
	CALL	RUN_FILE_TEST
	CALL	GET_KEY
	JR	SHOW_SPLASH_SCREEN

DO_SPLASH_OPEN:
	CALL	DO_OPEN_FILE_UI
	JR	SHOW_SPLASH_SCREEN

DO_SPLASH_SAVE:
	CALL	DO_SAVE_FILE_UI
	JR	SHOW_SPLASH_SCREEN

MAIN_LOOP:
	; If no key is immediately ready in serial buffer, flush deferred render!
	CALL	CHECK_KEY_READY
	JR	NZ,MAIN_LOOP_GET_KEY

	CALL	FLUSH_DEFERRED_RENDER

MAIN_LOOP_GET_KEY:
	CALL	GET_KEY

	; Command: Ctrl+Q -> Exit
	CP	KEY_CTRL_Q
	JP	Z,EXIT_PROGRAM

	; Command: Ctrl+S -> Save File Screen
	CP	KEY_CTRL_S
	JR	NZ,CHECK_CTRL_O
	CALL	FLUSH_DEFERRED_RENDER
	CALL	DO_SAVE_FILE_UI
	CALL	TERM_INIT
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	XOR	A
	LD	(NEED_SCREEN_RENDER),A
	LD	(NEED_LINE_RENDER),A
	LD	(NEED_STATUS_RENDER),A
	JP	MAIN_LOOP

CHECK_CTRL_O:
	; Command: Ctrl+O -> Open File Screen (ESC returns without opening)
	CP	KEY_CTRL_O
	JR	NZ,CHECK_CTRL_K
	CALL	FLUSH_DEFERRED_RENDER
	CALL	DO_OPEN_FILE_UI
	CALL	TERM_INIT
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	XOR	A
	LD	(NEED_SCREEN_RENDER),A
	LD	(NEED_LINE_RENDER),A
	LD	(NEED_STATUS_RENDER),A
	JP	MAIN_LOOP

CHECK_CTRL_K:
	CP	KEY_CTRL_K
	JR	NZ,CHECK_CTRL_D

	LD	A,(BLOCK_ACTIVE)
	CP	1			; Is dynamic block selection active?
	JR	NZ,DO_HELP_SCREEN	; If not in selection mode, show help screen!

	; Solidify active block
	CALL	SOLIDIFY_BLOCK
	JP	MAIN_LOOP

DO_HELP_SCREEN:
	CALL	FLUSH_DEFERRED_RENDER
	CALL	SHOW_HELP_KEYS_UI
	CALL	TERM_INIT
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	XOR	A
	LD	(NEED_SCREEN_RENDER),A
	LD	(NEED_LINE_RENDER),A
	LD	(NEED_STATUS_RENDER),A
	JP	MAIN_LOOP

CHECK_CTRL_D:
	; Command: Ctrl+D -> Delete character under cursor (Forward Delete)
	CP	4
	JR	NZ,CHECK_PAGE_KEYS
	LD	A,(BLOCK_ACTIVE)
	CP	2
	JR	Z,DO_CTRL_D_BLOCK
	CP	1
	JR	Z,DO_CTRL_D_CANCEL_SETUP
	CALL	DO_DELETE_FORWARD
	JP	MAIN_LOOP

DO_CTRL_D_BLOCK:
	CALL	DO_DELETE_BLOCK
	JP	MAIN_LOOP

DO_CTRL_D_CANCEL_SETUP:
	CALL	CANCEL_BLOCK
	JP	MAIN_LOOP

CHECK_PAGE_KEYS:
	; Command: Ctrl+A -> Home (start of line)
	CP	1			; Ctrl+A
	JR	Z,DO_HOME_KEY

	; Command: Ctrl+E -> End (end of line)
	CP	5			; Ctrl+E
	JR	Z,DO_END_KEY

	; Command: Ctrl+T -> Jump to Top of File
	CP	20			; Ctrl+T
	JR	Z,DO_JUMP_TOP

	; Command: Ctrl+G -> Jump to Bottom of File
	CP	7			; Ctrl+G
	JR	Z,DO_JUMP_BOTTOM

	; Command: Ctrl+B -> Toggle Block Highlighting
	CP	KEY_CTRL_B		; Ctrl+B
	JR	Z,DO_TOGGLE_BLOCK

	; Command: Ctrl+U -> Page Up
	CP	KEY_CTRL_U		; Ctrl+U
	JR	Z,DO_PAGE_UP

	; Command: Ctrl+V -> Page Down
	CP	22			; Ctrl+V
	JR	Z,DO_PAGE_DOWN

	JR	CHECK_ENTER

DO_HOME_KEY:
	CALL	CURSOR_HOME
	LD	A,1
	LD	(NEED_STATUS_RENDER),A
	JP	MAIN_LOOP

DO_END_KEY:
	CALL	CURSOR_END
	LD	A,1
	LD	(NEED_STATUS_RENDER),A
	JP	MAIN_LOOP

DO_JUMP_TOP:
	CALL	JUMP_FILE_TOP
	JP	MAIN_LOOP

DO_JUMP_BOTTOM:
	CALL	JUMP_FILE_BOTTOM
	JP	MAIN_LOOP

DO_TOGGLE_BLOCK:
	CALL	TOGGLE_BLOCK_MODE
	JP	MAIN_LOOP

DO_PAGE_UP:
	CALL	PAGE_UP
	JP	MAIN_LOOP

DO_PAGE_DOWN:
	CALL	PAGE_DOWN
	JP	MAIN_LOOP

CHECK_ENTER:
	; Enter -> Insert new line at CUR_ROW+1
	CP	KEY_ENTER
	JR	NZ,CHECK_BACKSPACE
	LD	A,(BLOCK_ACTIVE)
	CP	1
	JR	Z,DO_ENTER_CANCEL_SETUP
	CALL	CANCEL_BLOCK
	CALL	DO_INSERT_LINE
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	JP	MAIN_LOOP

DO_ENTER_CANCEL_SETUP:
	CALL	CANCEL_BLOCK
	JP	MAIN_LOOP

CHECK_BACKSPACE:
	CP	KEY_BACKSPACE
	JR	Z,DO_HANDLE_BS
	CP	KEY_DEL
	JR	NZ,CHECK_ESC_SEQ

DO_HANDLE_BS:
	LD	A,(BLOCK_ACTIVE)
	CP	1
	JR	Z,DO_BS_CANCEL_SETUP
	CALL	CANCEL_BLOCK

	LD	A,(CUR_COL)
	OR	A
	JR	Z,DO_HANDLE_BS_COL0

	; Normal character deletion on current line (CUR_COL > 0)
	CALL	DO_DELETE_CHAR
	LD	A,1
	LD	(NEED_LINE_RENDER),A
	JP	MAIN_LOOP

DO_BS_CANCEL_SETUP:
	CALL	CANCEL_BLOCK
	JP	MAIN_LOOP

DO_HANDLE_BS_COL0:
	; Backspace at column 0: delete line if blank / join lines
	CALL	DO_DELETE_BLANK_LINE
	JP	MAIN_LOOP

CHECK_ESC_SEQ:
	; Check for VT100 Escape sequences (Arrow keys)
	CP	KEY_ESC
	JR	NZ,CHECK_PRINTABLE_CHAR
	CALL	HANDLE_VT100_ESC
	LD	A,1
	LD	(NEED_STATUS_RENDER),A
	JP	MAIN_LOOP

CHECK_PRINTABLE_CHAR:
	; Check if Tab key is pressed (expand to 8-character tab stops)
	CP	KEY_TAB			; 9
	JR	NZ,CHECK_PRINTABLE_REGULAR
	LD	A,(BLOCK_ACTIVE)
	CP	1
	JR	Z,DO_TAB_CANCEL_SETUP
	CALL	CANCEL_BLOCK
	CALL	DO_TAB_INSERT
	LD	A,1
	LD	(NEED_LINE_RENDER),A
	JP	MAIN_LOOP

DO_TAB_CANCEL_SETUP:
	CALL	CANCEL_BLOCK
	JP	MAIN_LOOP

CHECK_PRINTABLE_REGULAR:
	CP	' '
	JP	C,MAIN_LOOP
	CP	127
	JP	NC,MAIN_LOOP

DO_INSERT_CHAR:
	LD	B,A
	LD	A,(BLOCK_ACTIVE)
	CP	1
	JR	Z,DO_CHAR_CANCEL_SETUP
	CALL	CANCEL_BLOCK
	LD	A,B
	CALL	DO_CHAR_INSERT
	LD	A,1
	LD	(NEED_LINE_RENDER),A
	JP	MAIN_LOOP

DO_CHAR_CANCEL_SETUP:
	CALL	CANCEL_BLOCK
	JP	MAIN_LOOP

;------------------------------------------------------------------------------
; Tab Key Insertion at (CUR_ROW, CUR_COL) - Inserts real ASCII 0x09 TAB byte
;------------------------------------------------------------------------------
DO_TAB_INSERT:
	LD	A,KEY_TAB		; Insert literal ASCII 0x09 Tab byte
	CALL	DO_CHAR_INSERT
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

	; Copy drive + filename + ext (12 bytes)
	LD	HL,DEFAULT_FCB
	LD	DE,WORK_FCB
	LD	BC,12
	LDIR

	; Zero remaining FCB bytes (12..35)
	LD	HL,WORK_FCB+12
	LD	(HL),0
	LD	DE,WORK_FCB+13
	LD	BC,23
	LDIR
	RET

NO_FILE_ARG:
	XOR	A
	LD	(HAS_FILE_ARG),A

	; Zero entire WORK_FCB (36 bytes)
	LD	HL,WORK_FCB
	LD	(HL),0
	LD	DE,WORK_FCB+1
	LD	BC,35
	LDIR

	; Set default filename to OUTPUT.TXT
	LD	HL,DEFAULT_FCB_NAME
	LD	DE,WORK_FCB
	LD	BC,12
	LDIR
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
; 512KB Extended Memory Diagnostic Suite (RomWBW HBIOS RST 08H)
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

	; 1. Query System Memory Configuration (SYSGET 0xF1)
	PUSH	IX
	LD	B,0F8H
	LD	C,0F1H
	RST	08H
	POP	IX

	LD	A,D
	LD	(ROM_BANK_COUNT),A
	LD	A,E
	LD	(RAM_BANK_COUNT),A

	; Print Total RAM Banks
	LD	DE,STR_TEST_RAM_BANKS
	CALL	PRINT_STR
	LD	A,(RAM_BANK_COUNT)
	CALL	PRINT_DEC_BYTE
	LD	DE,STR_TEST_RAM_BANKS_END
	CALL	PRINT_STR

	; Print Active CP/M User Bank
	LD	DE,STR_TEST_CUR_BANK
	CALL	PRINT_STR
	LD	A,(CPM_USER_BANK)
	CALL	PRINT_HEX_BYTE
	LD	DE,STR_CRLF
	CALL	PRINT_STR

	; Initialize and Discover Far RAM Banks
	CALL	INIT_FAR_RAM_BANKS

	; Print Discovered Far RAM Banks list
	LD	DE,STR_TEST_DISCOVERED
	CALL	PRINT_STR
	LD	A,(EXT_BANK_COUNT)
	CALL	PRINT_DEC_BYTE
	LD	DE,STR_TEST_BANKS_LIST
	CALL	PRINT_STR

	; Print Bank IDs
	LD	A,(EXT_BANK_COUNT)
	OR	A
	JP	Z,TEST_NO_FAR_BANKS
	LD	B,A
	LD	HL,EXT_BANK_TABLE
PRINT_FAR_BANKS_LOOP:
	LD	A,(HL)
	CALL	PRINT_HEX_BYTE
	LD	A,' '
	CALL	PUTC
	INC	HL
	DJNZ	PRINT_FAR_BANKS_LOOP
	LD	DE,STR_CRLF
	CALL	PRINT_STR

	LD	DE,STR_TEST_CAPACITY
	CALL	PRINT_STR

	; -------------------------------------------------------------------------
	; TEST 1: Direct Inter-Bank DMA Copy (SYSBNKCPY 0xF5)
	; -------------------------------------------------------------------------
	LD	DE,STR_TEST1_TITLE
	CALL	PRINT_STR

	; Prepare 2-byte test pattern in local memory
	LD	HL,TEST_PATTERN
	LD	(HL),0AAH
	INC	HL
	LD	(HL),055H

	; SYSSETCPY: Copy local pattern to EXT_BANK_TABLE[0] at offset 0x1000
	PUSH	IX
	LD	B,0F4H			; SYSSETCPY
	LD	A,(EXT_BANK_TABLE)
	LD	D,A			; Dest Bank = Target Far RAM Bank
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

	; Clear readback buffer
	LD	HL,TEST_READBACK
	LD	(HL),0
	INC	HL
	LD	(HL),0

	; SYSSETCPY: Copy from Far RAM back to local buffer
	PUSH	IX
	LD	B,0F4H			; SYSSETCPY
	LD	A,(CPM_USER_BANK)
	LD	D,A			; Dest Bank = User Bank
	LD	A,(EXT_BANK_TABLE)
	LD	E,A			; Src Bank = Far RAM Bank
	LD	HL,2
	RST	08H
	POP	IX

	PUSH	IX
	LD	B,0F5H			; SYSBNKCPY
	LD	DE,TEST_READBACK
	LD	HL,01000H
	RST	08H
	POP	IX

	; Verify pattern matches
	LD	A,(TEST_READBACK)
	CP	0AAH
	JP	NZ,TEST_FAIL
	LD	A,(TEST_READBACK+1)
	CP	055H
	JP	NZ,TEST_FAIL

	LD	DE,STR_TEST1_PASS
	CALL	PRINT_STR

	; -------------------------------------------------------------------------
	; TEST 2: Multi-Bank Line I/O Engine (WRITE_FAR_LINE / READ_FAR_LINE)
	; Writes unique signatures across ALL discovered Far RAM banks
	; -------------------------------------------------------------------------
	LD	DE,STR_TEST2_TITLE
	CALL	PRINT_STR

	; Write unique signature to Line 0 of each bank
	LD	C,0			; Current bank index
TEST2_WRITE_LOOP:
	PUSH	BC
	; Prepare 128-byte line pattern in LOAD_LINE_TEMP
	CALL	CLEAR_LOAD_TEMP
	LD	HL,LOAD_LINE_TEMP
	LD	(HL),05AH		; Magic signature byte 0
	INC	HL
	LD	(HL),C			; Bank index in byte 1
	INC	HL
	; Bank ID in byte 2
	LD	E,C
	LD	D,0
	LD	IY,EXT_BANK_TABLE
	ADD	IY,DE
	LD	A,(IY+0)
	LD	(HL),A
	INC	HL
	LD	(HL),0A5H		; Magic signature byte 3

	; Write to doc line: BC_doc = (C_bank << 8) | 0
	LD	B,C
	LD	C,0
	LD	HL,LOAD_LINE_TEMP
	CALL	WRITE_FAR_SLOT
	POP	BC
	INC	C
	LD	A,(EXT_BANK_COUNT)
	CP	C
	JR	NZ,TEST2_WRITE_LOOP

	; Read back and verify all banks
	LD	C,0
TEST2_READ_LOOP:
	PUSH	BC
	CALL	CLEAR_LOAD_TEMP
	LD	B,C
	LD	C,0
	LD	DE,LOAD_LINE_TEMP
	CALL	READ_FAR_SLOT
	POP	BC

	; Verify signature
	LD	HL,LOAD_LINE_TEMP
	LD	A,(HL)
	CP	05AH
	JP	NZ,TEST_FAIL
	INC	HL
	LD	A,(HL)
	CP	C
	JP	NZ,TEST_FAIL
	INC	HL
	LD	E,C
	LD	D,0
	LD	IY,EXT_BANK_TABLE
	ADD	IY,DE
	LD	A,(IY+0)
	CP	(HL)
	JP	NZ,TEST_FAIL
	INC	HL
	LD	A,(HL)
	CP	0A5H
	JP	NZ,TEST_FAIL

	INC	C
	LD	A,(EXT_BANK_COUNT)
	CP	C
	JR	NZ,TEST2_READ_LOOP

	LD	DE,STR_TEST2_PASS_PRE
	CALL	PRINT_STR
	LD	A,(EXT_BANK_COUNT)
	CALL	PRINT_DEC_BYTE
	LD	DE,STR_TEST2_PASS_POST
	CALL	PRINT_STR

	; -------------------------------------------------------------------------
	; TEST 3: Bank Boundary & 32KB Stride Test (Offsets 0x0000 & 0x7F80)
	; -------------------------------------------------------------------------
	LD	DE,STR_TEST3_TITLE
	CALL	PRINT_STR

	; Bank 0, Line 0 (offset 0x0000)
	CALL	CLEAR_LOAD_TEMP
	LD	HL,LOAD_LINE_TEMP
	LD	(HL),011H
	INC	HL
	LD	(HL),022H
	LD	BC,0
	LD	HL,LOAD_LINE_TEMP
	CALL	WRITE_FAR_SLOT

	; Bank 0, Line 255 (offset 0x7F80)
	CALL	CLEAR_LOAD_TEMP
	LD	HL,LOAD_LINE_TEMP
	LD	(HL),055H
	INC	HL
	LD	(HL),066H
	LD	BC,000FFH		; Line 255 (Bank 0, line 255)
	LD	HL,LOAD_LINE_TEMP
	CALL	WRITE_FAR_SLOT

	; Bank 1, Line 256 (offset 0x0000)
	CALL	CLEAR_LOAD_TEMP
	LD	HL,LOAD_LINE_TEMP
	LD	(HL),099H
	INC	HL
	LD	(HL),0AAH
	LD	BC,00100H		; Line 256 (Bank 1, line 0)
	LD	HL,LOAD_LINE_TEMP
	CALL	WRITE_FAR_SLOT

	; Bank 1, Line 511 (offset 0x7F80)
	CALL	CLEAR_LOAD_TEMP
	LD	HL,LOAD_LINE_TEMP
	LD	(HL),0DDH
	INC	HL
	LD	(HL),0EEH
	LD	BC,001FFH		; Line 511 (Bank 1, line 255)
	LD	HL,LOAD_LINE_TEMP
	CALL	WRITE_FAR_SLOT

	; Verify all 4 boundaries
	; Line 0
	CALL	CLEAR_LOAD_TEMP
	LD	BC,0
	LD	DE,LOAD_LINE_TEMP
	CALL	READ_FAR_SLOT
	LD	A,(LOAD_LINE_TEMP)
	CP	011H
	JP	NZ,TEST_FAIL
	LD	A,(LOAD_LINE_TEMP+1)
	CP	022H
	JP	NZ,TEST_FAIL

	; Line 255
	CALL	CLEAR_LOAD_TEMP
	LD	BC,000FFH
	LD	DE,LOAD_LINE_TEMP
	CALL	READ_FAR_SLOT
	LD	A,(LOAD_LINE_TEMP)
	CP	055H
	JP	NZ,TEST_FAIL
	LD	A,(LOAD_LINE_TEMP+1)
	CP	066H
	JP	NZ,TEST_FAIL

	; Line 256
	CALL	CLEAR_LOAD_TEMP
	LD	BC,00100H
	LD	DE,LOAD_LINE_TEMP
	CALL	READ_FAR_SLOT
	LD	A,(LOAD_LINE_TEMP)
	CP	099H
	JP	NZ,TEST_FAIL
	LD	A,(LOAD_LINE_TEMP+1)
	CP	0AAH
	JP	NZ,TEST_FAIL

	; Line 511
	CALL	CLEAR_LOAD_TEMP
	LD	BC,001FFH
	LD	DE,LOAD_LINE_TEMP
	CALL	READ_FAR_SLOT
	LD	A,(LOAD_LINE_TEMP)
	CP	0DDH
	JP	NZ,TEST_FAIL
	LD	A,(LOAD_LINE_TEMP+1)
	CP	0EEH
	JP	NZ,TEST_FAIL

	LD	DE,STR_TEST3_PASS
	CALL	PRINT_STR

	; -------------------------------------------------------------------------
	; TEST 4: Sliding Window Cache (16KB / 128 Lines) & Dirty Line Flush
	; -------------------------------------------------------------------------
	LD	DE,STR_TEST4_TITLE
	CALL	PRINT_STR

	; Initialize slot table with 1-to-1 mapping for 600 lines
	CALL	INIT_SLOT_SYSTEM
	LD	BC,600
	LD	HL,0
TEST4_SLOT_INIT:
	PUSH	BC
	PUSH	HL
	CALL	ALLOC_SLOT		; HL = slot ID
	EX	DE,HL			; DE = slot ID
	POP	HL			; HL = line index
	PUSH	HL
	ADD	HL,HL			; * 2
	LD	BC,DOC_LINE_SLOTS
	ADD	HL,BC
	LD	(HL),E
	INC	HL
	LD	(HL),D
	POP	HL
	INC	HL
	POP	BC
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,TEST4_SLOT_INIT

	; Set large document total lines
	LD	HL,600
	LD	(DOC_TOTAL_LINES),HL

	; Access Line 0 through cache
	LD	BC,0
	CALL	ENSURE_CACHE_WINDOW	; HL = pointer in LINE_STORAGE
	LD	(HL),'C'
	INC	HL
	LD	(HL),'A'
	INC	HL
	LD	(HL),'0'
	LD	A,1
	LD	(CACHE_DIRTY),A

	; Slide window across bank boundary to Line 300 (Bank 1)
	LD	BC,300
	CALL	ENSURE_CACHE_WINDOW	; Flushes Line 0 to Far RAM Bank 0, loads Bank 1
	LD	(HL),'C'
	INC	HL
	LD	(HL),'B'
	INC	HL
	LD	(HL),'1'
	LD	A,1
	LD	(CACHE_DIRTY),A

	; Flush dirty lines to Far RAM
	CALL	FLUSH_DIRTY_CACHE

	; Clear local LINE_STORAGE memory completely to prove reload works from Far RAM
	LD	HL,LINE_STORAGE
	LD	DE,LINE_STORAGE+1
	LD	BC,6143
	LD	(HL),0
	LDIR

	; Invalidate cache pointer
	LD	HL,0FFFFH
	LD	(CACHE_START_ROW),HL

	; Reload Window at Line 0
	LD	BC,0
	CALL	ENSURE_CACHE_WINDOW
	LD	A,(HL)
	CP	'C'
	JP	NZ,TEST4_FAIL_L0
	INC	HL
	LD	A,(HL)
	CP	'A'
	JP	NZ,TEST4_FAIL_L0
	INC	HL
	LD	A,(HL)
	CP	'0'
	JP	NZ,TEST4_FAIL_L0

	; Reload Window at Line 300
	LD	BC,300
	CALL	ENSURE_CACHE_WINDOW
	LD	A,(HL)
	CP	'C'
	JP	NZ,TEST4_FAIL_L300
	INC	HL
	LD	A,(HL)
	CP	'B'
	JP	NZ,TEST4_FAIL_L300
	INC	HL
	LD	A,(HL)
	CP	'1'
	JP	NZ,TEST4_FAIL_L300

	LD	DE,STR_TEST4_PASS
	CALL	PRINT_STR

	; -------------------------------------------------------------------------
	; Restore Empty Document State & Display Final Success
	; -------------------------------------------------------------------------
	CALL	INIT_EMPTY_DOCUMENT

	LD	DE,STR_TEST_ALL_PASSED
	CALL	PRINT_STR
	JR	TEST_END

TEST4_FAIL_L0:
	PUSH	AF
	LD	DE,STR_TEST4_FAIL_L0_MSG
	CALL	PRINT_STR
	POP	AF
	CALL	PRINT_HEX_BYTE
	LD	DE,STR_CRLF
	CALL	PRINT_STR
	JP	TEST_FAIL

TEST4_FAIL_L300:
	PUSH	AF
	LD	DE,STR_TEST4_FAIL_L300_MSG
	CALL	PRINT_STR
	POP	AF
	CALL	PRINT_HEX_BYTE
	LD	DE,STR_CRLF
	CALL	PRINT_STR
	JP	TEST_FAIL

TEST_NO_FAR_BANKS:
	LD	DE,STR_TEST_NO_BANKS
	CALL	PRINT_STR
	JR	TEST_END

TEST_FAIL:
	CALL	INIT_EMPTY_DOCUMENT
	LD	DE,STR_TEST_FAILED
	CALL	PRINT_STR

TEST_END:
	LD	DE,STR_TEST_PROMPT
	CALL	PRINT_STR
	RET

;------------------------------------------------------------------------------
; Multi-Sector File I/O & Raw Data Validation Suite (30.TXT)
;------------------------------------------------------------------------------
RUN_FILE_TEST:
	LD	DE,STR_CLEAR_SCREEN
	CALL	PRINT_STR

	LD	DE,STR_FILE_TEST_TITLE
	CALL	PRINT_STR

	; 1. Prepare FCB for 30.TXT
	LD	HL,RAW_TEST_FCB
	LD	(HL),0			; Drive 0 (Default / C:)
	INC	HL
	LD	(HL),'3'
	INC	HL
	LD	(HL),'0'
	INC	HL
	LD	B,6
PAD_FT_NAME:
	LD	(HL),' '
	INC	HL
	DJNZ	PAD_FT_NAME
	LD	(HL),'T'
	INC	HL
	LD	(HL),'X'
	INC	HL
	LD	(HL),'T'
	INC	HL
	LD	B,24
CLR_FT_REM:
	LD	(HL),0
	INC	HL
	DJNZ	CLR_FT_REM

	; 2. Set DMA Buffer
	LD	DE,RAW_SECTOR_BUF
	LD	C,26			; BDOS Set DMA
	CALL	BDOS_ENTRY

	; 3. Open 30.TXT
	LD	DE,RAW_TEST_FCB
	LD	C,15			; BDOS Open File
	CALL	BDOS_ENTRY
	CP	0FFH
	JP	Z,FILE_TEST_NOT_FOUND

	LD	DE,STR_FILE_TEST_OPEN_OK
	CALL	PRINT_STR

	; 4. Initialize counters and pointers
	XOR	A
	LD	(RAW_TEST_FCB+32),A	; Clear Current Record (CR)
	LD	(RAW_SEEN_CR),A
	LD	(RAW_FORMAT_TYPE),A	; FMT_CPM = 0
	LD	HL,0
	LD	(RAW_SECTORS_READ),HL
	LD	(RAW_BYTES_COUNT),HL
	LD	(RAW_LINES_COUNT),HL

	LD	HL,RAW_DATA_BUFFER
	LD	(RAW_DATA_PTR),HL
	LD	(HL),0

	; 5. Multi-Sector Sequential Read Loop
READ_RAW_SECTOR_LOOP:
	LD	DE,RAW_TEST_FCB
	LD	C,20			; BDOS Read Next Record
	CALL	BDOS_ENTRY
	OR	A
	JP	NZ,RAW_READ_EOF

	; Increment sector counter
	LD	HL,(RAW_SECTORS_READ)
	INC	HL
	LD	(RAW_SECTORS_READ),HL

	; Process 128 bytes in RAW_SECTOR_BUF
	LD	HL,RAW_SECTOR_BUF
	LD	C,128

RAW_BYTE_PARSE_LOOP:
	LD	A,(HL)
	CP	26			; CP/M EOF (^Z)
	JP	Z,RAW_READ_EOF
	OR	A			; NULL padding after text
	JP	Z,RAW_READ_EOF

	; Count valid data byte
	PUSH	HL
	LD	HL,(RAW_BYTES_COUNT)
	INC	HL
	LD	(RAW_BYTES_COUNT),HL
	POP	HL

	; Copy byte to RAW_DATA_BUFFER if within buffer size (2040 bytes)
	PUSH	HL
	PUSH	BC
	LD	HL,(RAW_DATA_PTR)
	LD	DE,RAW_DATA_BUFFER+2040
	LD	A,H
	CP	D
	JR	C,STORE_RAW_BYTE
	JR	NZ,SKIP_STORE_RAW
	LD	A,L
	CP	E
	JR	NC,SKIP_STORE_RAW

STORE_RAW_BYTE:
	POP	BC
	POP	HL
	LD	A,(HL)
	PUSH	HL
	LD	HL,(RAW_DATA_PTR)
	LD	(HL),A
	INC	HL
	LD	(HL),0			; Keep null-terminated
	LD	(RAW_DATA_PTR),HL
	POP	HL
	JR	CHECK_RAW_CRLF

SKIP_STORE_RAW:
	POP	BC
	POP	HL

CHECK_RAW_CRLF:
	LD	A,(HL)
	CP	13			; CR
	JR	NZ,CHECK_RAW_LF
	LD	A,1
	LD	(RAW_SEEN_CR),A
	JR	RAW_NEXT_BYTE

CHECK_RAW_LF:
	CP	10			; LF
	JR	NZ,CHECK_RAW_NORMAL

	; LF detected -> increment line counter
	PUSH	HL
	LD	HL,(RAW_LINES_COUNT)
	INC	HL
	LD	(RAW_LINES_COUNT),HL
	POP	HL

	LD	A,(RAW_SEEN_CR)
	OR	A
	JR	NZ,RAW_LF_AFTER_CR
	LD	A,FMT_LINUX
	LD	(RAW_FORMAT_TYPE),A
RAW_LF_AFTER_CR:
	XOR	A
	LD	(RAW_SEEN_CR),A
	JR	RAW_NEXT_BYTE

CHECK_RAW_NORMAL:
	XOR	A
	LD	(RAW_SEEN_CR),A

RAW_NEXT_BYTE:
	INC	HL
	DEC	C
	JP	NZ,RAW_BYTE_PARSE_LOOP
	JP	READ_RAW_SECTOR_LOOP

RAW_READ_EOF:
	; Restore DMA buffer to DEFAULT_DMA
	LD	DE,DEFAULT_DMA
	LD	C,26
	CALL	BDOS_ENTRY

	; If bytes ended without trailing newline, count final line
	LD	HL,(RAW_BYTES_COUNT)
	LD	A,H
	OR	L
	JR	Z,SHOW_RAW_METRICS

	; Check if last byte was newline or if lines count is 0
	LD	HL,(RAW_LINES_COUNT)
	LD	A,H
	OR	L
	JR	NZ,SHOW_RAW_METRICS
	INC	HL
	LD	(RAW_LINES_COUNT),HL

SHOW_RAW_METRICS:
	; Print Sectors Read
	LD	DE,STR_RAW_SECTORS_LBL
	CALL	PRINT_STR
	LD	HL,(RAW_SECTORS_READ)
	CALL	PRINT_DEC_WORD
	LD	DE,STR_RAW_SECTORS_TAIL
	CALL	PRINT_STR

	; Print Bytes Count
	LD	DE,STR_RAW_BYTES_LBL
	CALL	PRINT_STR
	LD	HL,(RAW_BYTES_COUNT)
	CALL	PRINT_DEC_WORD
	LD	DE,STR_RAW_BYTES_TAIL
	CALL	PRINT_STR

	; Print Lines Count
	LD	DE,STR_RAW_LINES_LBL
	CALL	PRINT_STR
	LD	HL,(RAW_LINES_COUNT)
	CALL	PRINT_DEC_WORD
	LD	DE,STR_RAW_LINES_TAIL
	CALL	PRINT_STR

	; Print Format Detected
	LD	DE,STR_RAW_FMT_LBL
	CALL	PRINT_STR
	LD	A,(RAW_FORMAT_TYPE)
	CP	FMT_CPM
	JR	NZ,SHOW_RAW_FMT_LINUX
	LD	DE,STR_RAW_FMT_CPM
	CALL	PRINT_STR
	JR	SHOW_LINE_PREVIEWS

SHOW_RAW_FMT_LINUX:
	LD	DE,STR_RAW_FMT_LINUX
	CALL	PRINT_STR

SHOW_LINE_PREVIEWS:
	; First line preview
	LD	DE,STR_RAW_FIRST_LINE_LBL
	CALL	PRINT_STR
	LD	HL,RAW_DATA_BUFFER
	CALL	PRINT_RAW_LINE_PREVIEW
	LD	DE,STR_QUOTE_CRLF
	CALL	PRINT_STR

	; Last line preview
	LD	DE,STR_RAW_LAST_LINE_LBL
	CALL	PRINT_STR
	CALL	FIND_LAST_RAW_LINE	; Returns HL = pointer to start of last line
	CALL	PRINT_RAW_LINE_PREVIEW
	LD	DE,STR_QUOTE_CRLF
	CALL	PRINT_STR

	; Validation Assertions:
	; Sectors > 1 AND Lines == 30
	LD	HL,(RAW_SECTORS_READ)
	LD	A,H
	OR	A
	JR	NZ,CHECK_LINES_COUNT
	LD	A,L
	CP	2
	JP	C,FILE_TEST_FAIL

CHECK_LINES_COUNT:
	LD	HL,(RAW_LINES_COUNT)
	LD	A,H
	OR	A
	JP	NZ,FILE_TEST_FAIL
	LD	A,L
	CP	30
	JP	NZ,FILE_TEST_FAIL

	LD	DE,STR_FILE_TEST_PASSED
	CALL	PRINT_STR
	JR	FILE_TEST_DONE

FILE_TEST_NOT_FOUND:
	LD	DE,STR_FILE_TEST_NOT_FOUND
	CALL	PRINT_STR
	JR	FILE_TEST_DONE

FILE_TEST_FAIL:
	LD	DE,STR_FILE_TEST_FAILED
	CALL	PRINT_STR

FILE_TEST_DONE:
	LD	DE,STR_TEST_PROMPT
	CALL	PRINT_STR
	RET

PRINT_RAW_LINE_PREVIEW:
	LD	B,50			; Max 50 characters preview
PRLP_LOOP:
	LD	A,(HL)
	OR	A
	RET	Z
	CP	13			; CR
	RET	Z
	CP	10			; LF
	RET	Z
	CALL	PUTC
	INC	HL
	DJNZ	PRLP_LOOP
	RET

FIND_LAST_RAW_LINE:
	LD	HL,RAW_DATA_BUFFER
	LD	DE,RAW_DATA_BUFFER
FLRL_SCAN:
	LD	A,(HL)
	OR	A
	JR	Z,FLRL_DONE
	CP	10			; LF
	JR	NZ,FLRL_NEXT
	; Next char after LF is new line start
	INC	HL
	LD	A,(HL)
	OR	A
	JR	Z,FLRL_DONE
	LD	D,H
	LD	E,L
	JR	FLRL_SCAN
FLRL_NEXT:
	INC	HL
	JR	FLRL_SCAN
FLRL_DONE:
	EX	DE,HL
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
;------------------------------------------------------------------------------
; Block Selection & Highlighting Engine (Hybrid Character & Line Blocking)
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; TOGGLE_BLOCK_MODE: Toggle block selection on/off at (CUR_DOC_ROW, CUR_COL)
;------------------------------------------------------------------------------
TOGGLE_BLOCK_MODE:
	LD	A,(BLOCK_ACTIVE)
	OR	A
	JR	NZ,TBM_DEACTIVATE

	; Block activated: anchor at current document row & column
	LD	A,1
	LD	(BLOCK_ACTIVE),A
	LD	HL,(CUR_DOC_ROW)
	LD	(BLOCK_ANCHOR_ROW),HL
	LD	A,(CUR_COL)
	LD	(BLOCK_ANCHOR_COL),A
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

TBM_DEACTIVATE:
	; Block deactivated: clear highlight
	JR	CANCEL_BLOCK

;------------------------------------------------------------------------------
; CANCEL_BLOCK: Cancel active block selection (state 1 or 2), refresh screen
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
CANCEL_BLOCK:
	LD	A,(BLOCK_ACTIVE)
	OR	A
	RET	Z
	XOR	A
	LD	(BLOCK_ACTIVE),A
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

;------------------------------------------------------------------------------
; SOLIDIFY_BLOCK: Lock/freeze active block selection coordinates with Ctrl+K
;------------------------------------------------------------------------------
SOLIDIFY_BLOCK:
	LD	A,(BLOCK_ACTIVE)
	CP	1
	RET	NZ			; Only dynamic selection can be solidified
	CALL	NORMALIZE_BLOCK_BOUNDS
	LD	A,2
	LD	(BLOCK_ACTIVE),A	; State 2 = Solidified / Locked
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

;------------------------------------------------------------------------------
; NORMALIZE_BLOCK_BOUNDS: Normalize (anchor, cursor) into (START, END) bounds
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
NORMALIZE_BLOCK_BOUNDS:
	LD	A,(BLOCK_ACTIVE)
	OR	A
	RET	Z			; No block active
	CP	2
	RET	Z			; Already solidified, bounds locked

	PUSH	BC
	PUSH	DE
	PUSH	HL

	LD	HL,(BLOCK_ANCHOR_ROW)
	LD	DE,(CUR_DOC_ROW)
	LD	A,(BLOCK_ANCHOR_COL)
	LD	B,A
	LD	A,(CUR_COL)
	LD	C,A

	; Compare HL and DE
	LD	A,H
	CP	D
	JR	C,NBB_ANCHOR_FIRST
	JR	NZ,NBB_CUR_FIRST
	LD	A,L
	CP	E
	JR	C,NBB_ANCHOR_FIRST
	JR	NZ,NBB_CUR_FIRST

	; Same row: compare B and C
	LD	(BLOCK_START_ROW),HL
	LD	(BLOCK_END_ROW),HL
	LD	A,B
	CP	C
	JR	C,NBB_COL_BC
	JR	Z,NBB_COL_BC
	; B > C
	LD	A,C
	LD	(BLOCK_START_COL),A
	LD	A,B
	LD	(BLOCK_END_COL),A
	JR	NBB_DONE

NBB_COL_BC:
	LD	A,B
	LD	(BLOCK_START_COL),A
	LD	A,C
	LD	(BLOCK_END_COL),A
	JR	NBB_DONE

NBB_ANCHOR_FIRST:
	LD	(BLOCK_START_ROW),HL
	LD	A,B
	LD	(BLOCK_START_COL),A
	LD	(BLOCK_END_ROW),DE
	LD	A,C
	LD	(BLOCK_END_COL),A
	JR	NBB_DONE

NBB_CUR_FIRST:
	LD	(BLOCK_START_ROW),DE
	LD	A,C
	LD	(BLOCK_START_COL),A
	LD	(BLOCK_END_ROW),HL
	LD	A,B
	LD	(BLOCK_END_COL),A

NBB_DONE:
	POP	HL
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; GET_BLOCK_BOUNDS: Return normalized bounds and line count of active block
; Returns: Carry=0, HL = start doc line, DE = end doc line, BC = line count
;          Carry=1 if no block active
; Preserves: None
;------------------------------------------------------------------------------
GET_BLOCK_BOUNDS:
	LD	A,(BLOCK_ACTIVE)
	OR	A
	SCF
	RET	Z

	CALL	NORMALIZE_BLOCK_BOUNDS

	LD	HL,(BLOCK_START_ROW)
	LD	DE,(BLOCK_END_ROW)
	PUSH	DE
	EX	DE,HL			; DE = start, HL = end
	AND	A
	SBC	HL,DE			; HL = end - start
	INC	HL			; HL = line count
	LD	B,H
	LD	C,L			; BC = line count
	POP	DE			; DE = end
	EX	DE,HL			; HL = start, DE = end
	OR	A			; Carry = 0 (success)
	RET

;------------------------------------------------------------------------------
; GET_LINE_BLOCK_RANGE: Compute character highlight range for document row BC
; Inputs: BC = 16-bit Document Line Index (0..3583)
; Returns: Carry=0: D = start character col, E = end character col (254=to EOL)
;          Carry=1: no highlight on this line
; Preserves: BC, HL
;------------------------------------------------------------------------------
GET_LINE_BLOCK_RANGE:
	LD	A,(BLOCK_ACTIVE)
	OR	A
	SCF
	RET	Z			; Carry = 1: no block active

	PUSH	BC
	PUSH	HL

	CALL	NORMALIZE_BLOCK_BOUNDS

	; Check if BC < BLOCK_START_ROW
	LD	HL,(BLOCK_START_ROW)
	LD	A,B
	CP	H
	JR	C,GLBR_NONE
	JR	NZ,GLBR_CHECK_MAX
	LD	A,C
	CP	L
	JR	C,GLBR_NONE

GLBR_CHECK_MAX:
	; Check if BC > BLOCK_END_ROW
	LD	HL,(BLOCK_END_ROW)
	LD	A,H
	CP	B
	JR	C,GLBR_NONE
	JR	NZ,GLBR_IN_RANGE
	LD	A,L
	CP	C
	JR	C,GLBR_NONE

GLBR_IN_RANGE:
	; BC is within [BLOCK_START_ROW, BLOCK_END_ROW]
	; Check if BC == BLOCK_START_ROW
	LD	HL,(BLOCK_START_ROW)
	LD	A,B
	CP	H
	JR	NZ,GLBR_NOT_START_ROW
	LD	A,C
	CP	L
	JR	NZ,GLBR_NOT_START_ROW

	; BC == BLOCK_START_ROW!
	; Check if it is also BLOCK_END_ROW (single line block)
	LD	HL,(BLOCK_END_ROW)
	LD	A,B
	CP	H
	JR	NZ,GLBR_START_ONLY
	LD	A,C
	CP	L
	JR	NZ,GLBR_START_ONLY

	; Single-line block: StartCol = BLOCK_START_COL, EndCol = BLOCK_END_COL
	LD	A,(BLOCK_START_COL)
	LD	D,A
	LD	A,(BLOCK_END_COL)
	LD	E,A
	CP	D
	JR	Z,GLBR_OK
	CALL	GLBR_CHECK_TAB_END
	JR	C,GLBR_NONE
	JR	GLBR_OK

GLBR_START_ONLY:
	; First line of multi-line block: StartCol = BLOCK_START_COL, EndCol = 254
	LD	A,(BLOCK_START_COL)
	LD	D,A
	LD	E,254
	JR	GLBR_OK

GLBR_NOT_START_ROW:
	; BC > BLOCK_START_ROW. Check if BC == BLOCK_END_ROW
	LD	HL,(BLOCK_END_ROW)
	LD	A,B
	CP	H
	JR	NZ,GLBR_MIDDLE_ROW
	LD	A,C
	CP	L
	JR	NZ,GLBR_MIDDLE_ROW

	; Last line of multi-line block: StartCol = 0, EndCol = BLOCK_END_COL
	LD	D,0
	LD	A,(BLOCK_END_COL)
	LD	E,A
	CALL	GLBR_CHECK_TAB_END
	JR	C,GLBR_NONE
	JR	GLBR_OK

GLBR_MIDDLE_ROW:
	; Middle full line: StartCol = 0, EndCol = 254
	LD	D,0
	LD	E,254

GLBR_OK:
	POP	HL
	POP	BC
	OR	A			; Carry = 0: line has block range [D, E]
	RET

GLBR_NONE:
	POP	HL
	POP	BC
	SCF				; Carry = 1: no block on this line
	RET

;------------------------------------------------------------------------------
; GLBR_CHECK_TAB_END: If character at EndCol (E) is a TAB, exclude it from highlight
; Inputs: BC = doc row, D = StartCol, E = EndCol
; Returns: Carry = 0: E adjusted (or unchanged)
;          Carry = 1: line has no highlight left (EndCol decremented below StartCol)
; Preserves: BC, D
;------------------------------------------------------------------------------
GLBR_CHECK_TAB_END:
	PUSH	BC
	PUSH	DE
	CALL	ENSURE_CACHE_WINDOW	; HL = pointer to line start in LINE_STORAGE
	POP	DE
	POP	BC

	PUSH	HL
	PUSH	DE
	LD	D,0
	ADD	HL,DE			; HL = line_start + EndCol
	LD	A,(HL)
	POP	DE
	POP	HL

	CP	KEY_TAB			; Is character at EndCol a TAB?
	JR	Z,GCTE_IS_TAB
	OR	A			; Carry = 0
	RET

GCTE_IS_TAB:
	LD	A,E
	CP	D
	JR	Z,GCTE_NO_CHARS
	DEC	E
	OR	A			; Carry = 0
	RET

GCTE_NO_CHARS:
	SCF				; Carry = 1: no highlight on this line
	RET

;------------------------------------------------------------------------------
; DO_DELETE_BLOCK: Delete solidified block selection
;------------------------------------------------------------------------------
DO_DELETE_BLOCK:
	LD	A,(BLOCK_ACTIVE)
	CP	2			; Only solidified blocks can be deleted
	RET	NZ

	CALL	FLUSH_DIRTY_CACHE
	CALL	NORMALIZE_BLOCK_BOUNDS

	; Check if single-line or multi-line block
	LD	HL,(BLOCK_START_ROW)
	LD	DE,(BLOCK_END_ROW)
	LD	A,H
	CP	D
	JR	NZ,DO_DEL_BLK_MULTILINE
	LD	A,L
	CP	E
	JR	NZ,DO_DEL_BLK_MULTILINE

	;--------------------------------------------------------------------------
	; CASE 1: Single-Line Block Deletion
	;--------------------------------------------------------------------------
DO_DEL_BLK_SINGLE:
	LD	BC,(BLOCK_START_ROW)
	CALL	GET_LINE_BLOCK_RANGE	; Carry=0: D = StartCol, E = EndCol
	JP	C,DO_DEL_BLK_FINISH	; If Carry=1, no characters in block range

	PUSH	DE			; D = StartCol, E = EndCol

	; Read the line into LOAD_LINE_TEMP
	LD	BC,(BLOCK_START_ROW)
	LD	DE,LOAD_LINE_TEMP
	CALL	READ_FAR_LINE

	POP	BC			; B = StartCol, C = EndCol

	; Source pointer: HL = LOAD_LINE_TEMP + EndCol + 1
	LD	HL,LOAD_LINE_TEMP
	LD	A,C
	INC	A
	LD	E,A
	LD	D,0
	ADD	HL,DE			; HL = LOAD_LINE_TEMP + EndCol + 1 (source)

	; Destination pointer: DE = LOAD_LINE_TEMP + StartCol
	LD	DE,LOAD_LINE_TEMP
	LD	A,B
	LD	C,A
	LD	B,0
	EX	DE,HL
	ADD	HL,BC
	EX	DE,HL			; DE = destination

	; Shift characters left from HL into DE until null terminator
DEL_BLK_SINGLE_SHIFT:
	LD	A,(HL)
	LD	(DE),A
	INC	HL
	INC	DE
	OR	A
	JR	NZ,DEL_BLK_SINGLE_SHIFT

	; Write updated line back to Far RAM
	LD	BC,(BLOCK_START_ROW)
	LD	HL,LOAD_LINE_TEMP
	CALL	WRITE_FAR_LINE

	; Update cursor position to (BLOCK_START_ROW, BLOCK_START_COL)
	LD	HL,(BLOCK_START_ROW)
	LD	(CUR_DOC_ROW),HL
	LD	A,(BLOCK_START_COL)
	LD	(CUR_COL),A
	CALL	CALC_VISUAL_COL
	LD	(TARGET_COL),A

	JP	DO_DEL_BLK_FINISH

	;--------------------------------------------------------------------------
	; CASE 2: Multi-Line Block Deletion
	;--------------------------------------------------------------------------
DO_DEL_BLK_MULTILINE:
	; Step 1: Process head of first line (BLOCK_START_ROW)
	; Read first line into LOAD_LINE_TEMP
	LD	BC,(BLOCK_START_ROW)
	LD	DE,LOAD_LINE_TEMP
	CALL	READ_FAR_LINE

	; Truncate at StartCol by writing null terminator
	LD	HL,LOAD_LINE_TEMP
	LD	A,(BLOCK_START_COL)
	LD	E,A
	LD	D,0
	ADD	HL,DE
	LD	(HL),0			; Truncate head

	; Step 2: Process tail of last line (BLOCK_END_ROW)
	LD	BC,(BLOCK_END_ROW)
	CALL	GET_LINE_BLOCK_RANGE	; Carry=0: D=0, E=EndCol. Carry=1: no highlight
	JR	C,DEL_BLK_TAIL_WHOLE

	; Save E (EndCol)
	LD	A,E
	PUSH	AF

	; Read last line into SPLIT_LINE_TEMP
	LD	BC,(BLOCK_END_ROW)
	LD	DE,SPLIT_LINE_TEMP
	CALL	READ_FAR_LINE

	POP	AF			; A = EndCol
	INC	A
	LD	E,A
	LD	D,0
	LD	HL,SPLIT_LINE_TEMP
	ADD	HL,DE			; HL = pointer to tail in SPLIT_LINE_TEMP
	JR	DEL_BLK_CONCAT_TAIL

DEL_BLK_TAIL_WHOLE:
	; Whole last line is kept (tail starts at offset 0)
	LD	BC,(BLOCK_END_ROW)
	LD	DE,SPLIT_LINE_TEMP
	CALL	READ_FAR_LINE
	LD	HL,SPLIT_LINE_TEMP	; HL = pointer to tail (offset 0)

DEL_BLK_CONCAT_TAIL:
	; HL = tail in SPLIT_LINE_TEMP.
	; Append tail to LOAD_LINE_TEMP starting at BLOCK_START_COL
	PUSH	HL			; Save tail pointer
	LD	HL,LOAD_LINE_TEMP
	LD	A,(BLOCK_START_COL)
	LD	E,A
	LD	D,0
	ADD	HL,DE			; HL = destination in LOAD_LINE_TEMP
	POP	DE			; DE = source tail pointer

	LD	A,(BLOCK_START_COL)
	LD	C,A			; C = current length
DEL_BLK_APPEND_LOOP:
	LD	A,(DE)
	OR	A
	JR	Z,DEL_BLK_APPEND_DONE
	LD	A,C
	CP	MAX_LINE_STRIDE-7	; 121 (max 120 chars)
	JR	NC,DEL_BLK_APPEND_DONE	; Stop if capacity reached
	LD	A,(DE)
	LD	(HL),A
	INC	DE
	INC	HL
	INC	C
	JR	DEL_BLK_APPEND_LOOP

DEL_BLK_APPEND_DONE:
	LD	(HL),0			; Null-terminate merged line

	; Write merged line back to BLOCK_START_ROW
	LD	BC,(BLOCK_START_ROW)
	LD	HL,LOAD_LINE_TEMP
	CALL	WRITE_FAR_LINE

	; Step 3: Free slots for lines (BLOCK_START_ROW + 1) through (BLOCK_END_ROW)
	LD	HL,(BLOCK_START_ROW)
	INC	HL
	LD	(DEL_BLK_CUR_LINE),HL

DEL_BLK_FREE_LOOP:
	; Compare DEL_BLK_CUR_LINE with BLOCK_END_ROW
	LD	HL,(BLOCK_END_ROW)
	LD	DE,(DEL_BLK_CUR_LINE)
	; If DE > HL, done freeing
	LD	A,H
	CP	D
	JR	C,DEL_BLK_FREE_DONE
	JR	NZ,DO_FREE_CUR_SLOT
	LD	A,L
	CP	E
	JR	C,DEL_BLK_FREE_DONE

DO_FREE_CUR_SLOT:
	; Slot address in DOC_LINE_SLOTS = DOC_LINE_SLOTS + DEL_BLK_CUR_LINE * 2
	LD	HL,(DEL_BLK_CUR_LINE)
	ADD	HL,HL
	LD	DE,DOC_LINE_SLOTS
	ADD	HL,DE
	LD	E,(HL)
	INC	HL
	LD	D,(HL)			; DE = slot ID
	EX	DE,HL			; HL = slot ID
	CALL	FREE_SLOT

	LD	HL,(DEL_BLK_CUR_LINE)
	INC	HL
	LD	(DEL_BLK_CUR_LINE),HL
	JR	DEL_BLK_FREE_LOOP

DEL_BLK_FREE_DONE:
	; Step 4: Shift DOC_LINE_SLOTS entries above BLOCK_END_ROW downwards
	; Lines removed: K = BLOCK_END_ROW - BLOCK_START_ROW
	; Number of entries to shift: W = DOC_TOTAL_LINES - (BLOCK_END_ROW + 1)
	LD	HL,(DOC_TOTAL_LINES)
	LD	DE,(BLOCK_END_ROW)
	INC	DE			; DE = BLOCK_END_ROW + 1
	AND	A
	SBC	HL,DE			; HL = W = DOC_TOTAL_LINES - (BLOCK_END_ROW + 1)
	JR	Z,DEL_BLK_NO_SHIFT
	JR	C,DEL_BLK_NO_SHIFT

	; W > 0: shift entries down using LDIR
	PUSH	HL			; Save W (word count)

	; Destination: DE = DOC_LINE_SLOTS + (BLOCK_START_ROW + 1) * 2
	LD	HL,(BLOCK_START_ROW)
	INC	HL
	ADD	HL,HL
	LD	DE,DOC_LINE_SLOTS
	ADD	HL,DE
	EX	DE,HL			; DE = destination

	; Source: HL = DOC_LINE_SLOTS + (BLOCK_END_ROW + 1) * 2
	LD	HL,(BLOCK_END_ROW)
	INC	HL
	ADD	HL,HL
	LD	BC,DOC_LINE_SLOTS
	ADD	HL,BC			; HL = source

	POP	BC			; BC = W
	SLA	C
	RL	B			; BC = W * 2 (byte count)
	LDIR

DEL_BLK_NO_SHIFT:
	; Update DOC_TOTAL_LINES = DOC_TOTAL_LINES - (BLOCK_END_ROW - BLOCK_START_ROW)
	LD	HL,(BLOCK_END_ROW)
	LD	DE,(BLOCK_START_ROW)
	AND	A
	SBC	HL,DE			; HL = K
	EX	DE,HL			; DE = K
	LD	HL,(DOC_TOTAL_LINES)
	AND	A
	SBC	HL,DE			; HL = DOC_TOTAL_LINES - K
	LD	A,H
	OR	L
	JR	NZ,DEL_BLK_TOTAL_SET
	INC	HL			; Minimum 1 line!
DEL_BLK_TOTAL_SET:
	LD	(DOC_TOTAL_LINES),HL

	; Step 5: Update cursor position to (BLOCK_START_ROW, BLOCK_START_COL)
	LD	HL,(BLOCK_START_ROW)
	LD	(CUR_DOC_ROW),HL
	LD	A,(BLOCK_START_COL)
	LD	(CUR_COL),A
	CALL	CALC_VISUAL_COL
	LD	(TARGET_COL),A

	; Step 6: Ensure TOP_DOC_ROW does not scroll past EOF
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(TOP_DOC_ROW)
	LD	A,H
	CP	D
	JR	C,DEL_BLK_ADJ_TOP
	JR	NZ,DO_DEL_BLK_FINISH
	LD	A,L
	CP	E
	JR	NC,DO_DEL_BLK_FINISH
DEL_BLK_ADJ_TOP:
	LD	(TOP_DOC_ROW),HL

DO_DEL_BLK_FINISH:
	XOR	A
	LD	(BLOCK_ACTIVE),A	; Deactivate block mode!
	CALL	RELOAD_CACHE_WINDOW_FORCE
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
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
	; Calculate buffer line to render: doc_line = TOP_DOC_ROW + C
	LD	HL,(TOP_DOC_ROW)
	LD	E,C
	LD	D,0
	ADD	HL,DE			; HL = target doc_line
	LD	B,H
	LD	C,L			; BC = target doc_line

	; Check if doc_line < DOC_TOTAL_LINES
	LD	HL,(DOC_TOTAL_LINES)
	LD	A,H
	CP	B
	JR	C,RENDER_TILDE_ROW
	JR	NZ,DO_RENDER_DOC_ROW
	LD	A,L
	CP	C
	JR	Z,RENDER_TILDE_ROW
	JR	C,RENDER_TILDE_ROW

DO_RENDER_DOC_ROW:
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

; Fast single line refresh: rewrites current line and restores cursor
RENDER_CURRENT_LINE:
	; Move to start of current screen line: ESC [ <(CUR_DOC_ROW - TOP_DOC_ROW) + 1> ; 1 H
	LD	A,27
	CALL	PUTC
	LD	A,'['
	CALL	PUTC

	LD	HL,(CUR_DOC_ROW)
	LD	DE,(TOP_DOC_ROW)
	AND	A
	SBC	HL,DE
	LD	A,L
	INC	A			; Screen row (1-indexed for terminal)
	CALL	PRINT_DEC_BYTE

	LD	A,';'
	CALL	PUTC
	LD	A,'1'
	CALL	PUTC
	LD	A,'H'
	CALL	PUTC

	; Clear to EOL
	LD	DE,STR_CLEAR_EOL
	CALL	PRINT_STR

	LD	BC,(CUR_DOC_ROW)
	CALL	GET_LINE_BLOCK_RANGE
	JR	C,RCL_NO_BLOCK_LINE

	LD	A,1
	LD	(LINE_BLK_ACTIVE),A
	LD	A,D
	LD	(LINE_BLK_START),A
	LD	A,E
	LD	(LINE_BLK_END),A
	XOR	A
	LD	(LINE_IN_INVERSE),A
	JR	RCL_LOAD_LINE

RCL_NO_BLOCK_LINE:
	XOR	A
	LD	(LINE_BLK_ACTIVE),A
	LD	(LINE_IN_INVERSE),A

RCL_LOAD_LINE:
	LD	BC,(CUR_DOC_ROW)
	CALL	ENSURE_CACHE_WINDOW	; HL = pointer to line start in LINE_STORAGE

	LD	A,(HL)
	OR	A
	JR	NZ,RCL_START_CHARS

	; Empty line
	LD	A,(LINE_BLK_ACTIVE)
	OR	A
	JP	Z,PRINT_CUR_LINE_DONE
	LD	A,(LINE_BLK_START)
	OR	A
	JP	NZ,PRINT_CUR_LINE_DONE
	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR
	LD	A,' '
	CALL	PUTC
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	JP	PRINT_CUR_LINE_DONE

RCL_START_CHARS:
	LD	B,0			; B = visual column accumulator
	LD	D,0			; D = character index in line

PRINT_CUR_LINE_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,PRINT_CUR_LINE_DONE

	LD	A,(LINE_BLK_ACTIVE)
	OR	A
	JR	Z,PCL_PRINT_CHAR

	LD	A,(LINE_BLK_START)
	CP	D
	JR	NZ,PCL_PRINT_CHAR
	PUSH	DE
	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR
	POP	DE
	LD	A,1
	LD	(LINE_IN_INVERSE),A

PCL_PRINT_CHAR:
	LD	A,(HL)
	CP	KEY_TAB
	JR	Z,PRINT_CUR_TAB
	CALL	PUTC
	INC	HL
	INC	B
	JR	PCL_AFTER_CHAR

PRINT_CUR_TAB:
	INC	HL
	LD	A,B
	AND	7
	LD	C,A
	LD	A,8
	SUB	C			; A = spaces to emit (1..8)
	LD	C,A
PRINT_CUR_TAB_SPACES:
	LD	A,(ACTIVE_COLS)
	CP	B
	JR	Z,PRINT_CUR_LINE_DONE
	LD	A,' '
	CALL	PUTC
	INC	B
	DEC	C
	JR	NZ,PRINT_CUR_TAB_SPACES

PCL_AFTER_CHAR:
	LD	A,(LINE_BLK_ACTIVE)
	OR	A
	JR	Z,PCL_NEXT_CHAR
	LD	A,(LINE_IN_INVERSE)
	OR	A
	JR	Z,PCL_NEXT_CHAR
	LD	A,(LINE_BLK_END)
	CP	D
	JR	NZ,PCL_NEXT_CHAR
	PUSH	DE
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	POP	DE
	XOR	A
	LD	(LINE_IN_INVERSE),A

PCL_NEXT_CHAR:
	INC	D
	LD	A,(ACTIVE_COLS)
	CP	B
	JR	Z,PRINT_CUR_LINE_DONE
	JR	PRINT_CUR_LINE_LOOP

PRINT_CUR_LINE_DONE:
	LD	A,(LINE_IN_INVERSE)
	OR	A
	JR	Z,RCL_DONE_RESTORE
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	XOR	A
	LD	(LINE_IN_INVERSE),A

RCL_DONE_RESTORE:
	CALL	RENDER_STATUS_BAR
	RET

;------------------------------------------------------------------------------
; Flush any pending deferred screen, line, or status bar rendering
;------------------------------------------------------------------------------
FLUSH_DEFERRED_RENDER:
	LD	A,(NEED_SCREEN_RENDER)
	OR	A
	JR	Z,CHECK_DEFERRED_LINE

	; Full screen redraw needed (RENDER_SCREEN also updates status & locates cursor)
	XOR	A
	LD	(NEED_SCREEN_RENDER),A
	LD	(NEED_LINE_RENDER),A
	LD	(NEED_STATUS_RENDER),A
	CALL	RENDER_SCREEN
	RET

CHECK_DEFERRED_LINE:
	LD	A,(NEED_LINE_RENDER)
	OR	A
	JR	Z,CHECK_DEFERRED_STATUS

	; Current line redraw needed (RENDER_CURRENT_LINE updates status & locates cursor)
	XOR	A
	LD	(NEED_LINE_RENDER),A
	LD	(NEED_STATUS_RENDER),A
	CALL	RENDER_CURRENT_LINE
	RET

CHECK_DEFERRED_STATUS:
	LD	A,(NEED_STATUS_RENDER)
	OR	A
	RET	Z

	; Only status bar / cursor restore needed
	XOR	A
	LD	(NEED_STATUS_RENDER),A
	CALL	RENDER_STATUS_BAR
	RET


RENDER_BUFFER_LINE:
	LD	DE,STR_CLEAR_EOL
	CALL	PRINT_STR

	; BC has target doc_line
	CALL	GET_LINE_BLOCK_RANGE
	JR	C,RBL_NO_BLOCK_LINE

	; Line is in block
	LD	A,1
	LD	(LINE_BLK_ACTIVE),A
	LD	A,D
	LD	(LINE_BLK_START),A
	LD	A,E
	LD	(LINE_BLK_END),A
	XOR	A
	LD	(LINE_IN_INVERSE),A
	JR	RBL_LOAD_LINE

RBL_NO_BLOCK_LINE:
	XOR	A
	LD	(LINE_BLK_ACTIVE),A
	LD	(LINE_IN_INVERSE),A

RBL_LOAD_LINE:
	CALL	ENSURE_CACHE_WINDOW	; HL = pointer to line start in LINE_STORAGE

	; Check if line is empty (HL == 0)
	LD	A,(HL)
	OR	A
	JR	NZ,RBL_START_CHARS

	; Line is empty
	LD	A,(LINE_BLK_ACTIVE)
	OR	A
	JP	Z,PRINT_LINE_END
	; Empty line in block: if start_col == 0, print an inverted space indicator
	LD	A,(LINE_BLK_START)
	OR	A
	JP	NZ,PRINT_LINE_END
	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR
	LD	A,' '
	CALL	PUTC
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	JP	PRINT_LINE_END

RBL_START_CHARS:
	LD	B,0			; B = visual column accumulator
	LD	D,0			; D = character index in line

PRINT_LINE_CHARS:
	LD	A,(HL)
	OR	A
	JR	Z,PRINT_LINE_END

	; Check block highlight attribute transitions
	LD	A,(LINE_BLK_ACTIVE)
	OR	A
	JR	Z,PLC_PRINT_CHAR

	; Check if D == LINE_BLK_START
	LD	A,(LINE_BLK_START)
	CP	D
	JR	NZ,PLC_PRINT_CHAR
	; Start highlight
	PUSH	DE
	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR
	POP	DE
	LD	A,1
	LD	(LINE_IN_INVERSE),A

PLC_PRINT_CHAR:
	LD	A,(HL)
	CP	KEY_TAB
	JR	Z,PRINT_LINE_TAB
	CALL	PUTC
	INC	HL
	INC	B
	JR	PLC_AFTER_CHAR

PRINT_LINE_TAB:
	INC	HL
	LD	A,B
	AND	7
	LD	C,A
	LD	A,8
	SUB	C
	LD	C,A
PRINT_LINE_TAB_SPACES:
	LD	A,(ACTIVE_COLS)
	CP	B
	JR	Z,PRINT_LINE_END
	LD	A,' '
	CALL	PUTC
	INC	B
	DEC	C
	JR	NZ,PRINT_LINE_TAB_SPACES

PLC_AFTER_CHAR:
	; Check if D == LINE_BLK_END (turn off inverse after this char)
	LD	A,(LINE_BLK_ACTIVE)
	OR	A
	JR	Z,PLC_NEXT_CHAR
	LD	A,(LINE_IN_INVERSE)
	OR	A
	JR	Z,PLC_NEXT_CHAR
	LD	A,(LINE_BLK_END)
	CP	D
	JR	NZ,PLC_NEXT_CHAR
	; Turn off inverse video
	PUSH	DE
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	POP	DE
	XOR	A
	LD	(LINE_IN_INVERSE),A

PLC_NEXT_CHAR:
	INC	D			; Next character index
	LD	A,(ACTIVE_COLS)
	CP	B
	JR	Z,PRINT_LINE_END
	JR	PRINT_LINE_CHARS

PRINT_LINE_END:
	; If inverse video was left on (e.g. EndCol = 254), turn it off
	LD	A,(LINE_IN_INVERSE)
	OR	A
	JR	Z,RBL_DONE_CRLF
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	XOR	A
	LD	(LINE_IN_INVERSE),A

RBL_DONE_CRLF:
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

	; Print filename if known (HAS_FILE_ARG != 0)
	CALL	PRINT_STATUS_FILENAME

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
	LD	A,(BLOCK_ACTIVE)
	OR	A
	JR	Z,SHOW_STATUS_NORMAL_KEYS

	CALL	NORMALIZE_BLOCK_BOUNDS

	LD	A,(BLOCK_ACTIVE)
	CP	2
	JR	Z,STATUS_SOLIDIFIED

	; Dynamic selection active: "[SEL: "
	LD	DE,STR_SEL_PREFIX
	CALL	PRINT_STR

	; Check if single-line or multi-line
	LD	HL,(BLOCK_START_ROW)
	LD	DE,(BLOCK_END_ROW)
	LD	A,H
	CP	D
	JR	NZ,STATUS_SEL_MULTILINE
	LD	A,L
	CP	E
	JR	NZ,STATUS_SEL_MULTILINE

	; Single-line selection: chars count
	LD	A,(BLOCK_END_COL)
	LD	HL,BLOCK_START_COL
	SUB	(HL)
	INC	A			; A = char count
	CALL	PRINT_DEC_BYTE
	LD	DE,STR_CHAR_SUFFIX	; "c] | "
	CALL	PRINT_STR
	JR	SHOW_STATUS_ROWCOL

STATUS_SEL_MULTILINE:
	CALL	GET_BLOCK_BOUNDS	; BC = line count
	LD	L,C
	LD	H,B
	CALL	PRINT_DEC_WORD
	LD	DE,STR_LINE_SUFFIX	; "L] | "
	CALL	PRINT_STR
	JR	SHOW_STATUS_ROWCOL

STATUS_SOLIDIFIED:
	; Solidified block: "[BLK: "
	LD	DE,STR_BLK_PREFIX
	CALL	PRINT_STR

	LD	HL,(BLOCK_START_ROW)
	LD	DE,(BLOCK_END_ROW)
	LD	A,H
	CP	D
	JR	NZ,STATUS_SOLID_MULTILINE
	LD	A,L
	CP	E
	JR	NZ,STATUS_SOLID_MULTILINE

	; Single-line solidified: chars count
	LD	A,(BLOCK_END_COL)
	LD	HL,BLOCK_START_COL
	SUB	(HL)
	INC	A			; A = char count
	CALL	PRINT_DEC_BYTE
	LD	DE,STR_CHAR_LOCK_SUFFIX	; "c LOCK] | "
	CALL	PRINT_STR
	JR	SHOW_STATUS_ROWCOL

STATUS_SOLID_MULTILINE:
	CALL	GET_BLOCK_BOUNDS	; BC = line count
	LD	L,C
	LD	H,B
	CALL	PRINT_DEC_WORD
	LD	DE,STR_LINE_LOCK_SUFFIX	; "L LOCK] | "
	CALL	PRINT_STR
	JR	SHOW_STATUS_ROWCOL

SHOW_STATUS_NORMAL_KEYS:
	LD	DE,STR_STATUS_KEYS
	CALL	PRINT_STR

SHOW_STATUS_ROWCOL:
	; Print dynamic cursor position: Row <cur>/<total>, Col <col>
	LD	DE,STR_STATUS_POS
	CALL	PRINT_STR
	LD	HL,(CUR_DOC_ROW)
	INC	HL			; 1-indexed document row
	CALL	PRINT_DEC_WORD		; Print 16-bit current row number
	LD	A,'/'
	CALL	PUTC
	LD	HL,(DOC_TOTAL_LINES)
	CALL	PRINT_DEC_WORD		; Print 16-bit total rows of file
	LD	DE,STR_STATUS_COL
	CALL	PRINT_STR
	CALL	CALC_VISUAL_COL		; A = Visual column (0-indexed, 0..ACTIVE_COLS-1)
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

FILENAME_FIELD_WIDTH	.EQU	14

;------------------------------------------------------------------------------
; Print Filename in Status Bar (Fixed Width: FILENAME_FIELD_WIDTH characters)
; If filename is unknown (HAS_FILE_ARG == 0), prints "[No Name]" padded.
; If filename is known, prints full filename "Drive letter: filename" padded.
; Takes care not to duplicate drive letter if filename already contains it.
; Always outputs exactly FILENAME_FIELD_WIDTH characters, followed by " | ".
;------------------------------------------------------------------------------
PRINT_STATUS_FILENAME:
	LD	C,0			; C = characters printed so far

	LD	A,(HAS_FILE_ARG)
	OR	A
	JR	NZ,PSF_HAVE_FILE

	; Unknown filename: print "[No Name]"
	LD	DE,STR_NO_NAME
PSF_NO_NAME_LOOP:
	LD	A,(DE)
	OR	A
	JR	Z,PSF_PAD_SPACES
	CALL	PUTC
	INC	DE
	INC	C
	JR	PSF_NO_NAME_LOOP

PSF_HAVE_FILE:
	; Check if WORK_FCB+1..8 already contains a drive letter (e.g. "C:")
	LD	A,(WORK_FCB+2)
	CP	':'
	JR	Z,PSF_NO_DRIVE_PREFIX

	; Determine drive letter
	LD	A,(WORK_FCB)
	OR	A
	JR	NZ,PSF_USE_FCB_DRIVE

	; WORK_FCB has 0 -> Query current default drive via BDOS 25
	PUSH	BC
	LD	C,25
	CALL	BDOS_ENTRY
	POP	BC
	ADD	A,'A'
	JR	PSF_EMIT_DRIVE

PSF_USE_FCB_DRIVE:
	ADD	A,'A'-1			; 1 -> 'A', 2 -> 'B', etc.

PSF_EMIT_DRIVE:
	CALL	PUTC
	INC	C
	LD	A,':'
	CALL	PUTC
	INC	C

PSF_NO_DRIVE_PREFIX:
	; Print up to 8 characters of filename (WORK_FCB+1..8)
	LD	HL,WORK_FCB+1
	LD	B,8
PSF_NAME_LOOP:
	LD	A,(HL)
	CP	' '
	JR	Z,PSF_CHECK_EXT
	OR	A
	JR	Z,PSF_CHECK_EXT
	LD	A,C
	CP	FILENAME_FIELD_WIDTH
	JR	NC,PSF_CHECK_EXT
	LD	A,(HL)
	CALL	PUTC
	INC	C
	INC	HL
	DJNZ	PSF_NAME_LOOP

PSF_CHECK_EXT:
	; Print extension if present (WORK_FCB+9..11)
	LD	HL,WORK_FCB+9
	LD	A,(HL)
	CP	' '
	JR	Z,PSF_PAD_SPACES
	OR	A
	JR	Z,PSF_PAD_SPACES

	LD	A,C
	CP	FILENAME_FIELD_WIDTH
	JR	NC,PSF_PAD_SPACES

	LD	A,'.'
	CALL	PUTC
	INC	C

	LD	B,3
PSF_EXT_LOOP:
	LD	A,(HL)
	CP	' '
	JR	Z,PSF_PAD_SPACES
	OR	A
	JR	Z,PSF_PAD_SPACES
	LD	A,C
	CP	FILENAME_FIELD_WIDTH
	JR	NC,PSF_PAD_SPACES
	LD	A,(HL)
	CALL	PUTC
	INC	C
	INC	HL
	DJNZ	PSF_EXT_LOOP

PSF_PAD_SPACES:
	; Pad remaining characters with spaces up to FILENAME_FIELD_WIDTH
	LD	A,C
	CP	FILENAME_FIELD_WIDTH
	JR	NC,PSF_DONE
	LD	A,' '
	CALL	PUTC
	INC	C
	JR	PSF_PAD_SPACES

PSF_DONE:
	LD	DE,STR_STATUS_SEP
	CALL	PRINT_STR
	RET

;------------------------------------------------------------------------------
; Calculate Visual Screen Column from (CUR_DOC_ROW, CUR_COL)
; Returns: A = Visual Column (0-indexed, 0..ACTIVE_COLS-1)
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
CALC_VISUAL_COL:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	; Get pointer to current line in cache
	LD	BC,(CUR_DOC_ROW)
	CALL	ENSURE_CACHE_WINDOW	; HL = line start in LINE_STORAGE

	LD	A,(CUR_COL)
	LD	C,A			; C = character count to process
	LD	B,0			; B = visual column accumulator
	OR	A
	JR	Z,CALC_VIS_DONE

CALC_VIS_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,CALC_VIS_DONE
	CP	KEY_TAB
	JR	Z,CALC_VIS_TAB
	INC	B
	JR	CALC_VIS_NEXT

CALC_VIS_TAB:
	LD	A,B
	AND	7
	LD	E,A
	LD	A,8
	SUB	E			; A = spaces to add
	ADD	A,B
	LD	B,A

CALC_VIS_NEXT:
	INC	HL
	DEC	C
	JR	NZ,CALC_VIS_LOOP

CALC_VIS_DONE:
	LD	A,(ACTIVE_COLS)
	DEC	A			; A = max visual column (ACTIVE_COLS - 1: 119 or 79)
	CP	B
	JR	C,CLAMP_VIS_COL
	LD	A,B
	JR	EXIT_CALC_VIS
CLAMP_VIS_COL:
	; A is already ACTIVE_COLS - 1
EXIT_CALC_VIS:
	POP	HL
	POP	DE
	POP	BC
	RET

LOCATE_CURSOR:
	; Emit ESC [ <ScreenRow+1> ; <VisualCol+1> H
	LD	A,27
	CALL	PUTC
	LD	A,'['
	CALL	PUTC

	; Screen Row = CUR_DOC_ROW - TOP_DOC_ROW + 1 (1-indexed for terminal)
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(TOP_DOC_ROW)
	AND	A
	SBC	HL,DE
	LD	A,L
	INC	A
	CALL	PRINT_DEC_BYTE

	LD	A,';'
	CALL	PUTC

	; Visual Column (1-indexed)
	CALL	CALC_VISUAL_COL		; A = visual column (0-indexed)
	INC	A
	CALL	PRINT_DEC_BYTE

	LD	A,'H'
	CALL	PUTC
	RET

;------------------------------------------------------------------------------
; 512KB HBIOS RAM Far-Banking Multi-Bank Document Engine
;------------------------------------------------------------------------------
BUFFER_INIT:
	; Clear LINE_STORAGE (6,144 bytes) with 0
	LD	HL,LINE_STORAGE
	LD	DE,LINE_STORAGE+1
	LD	BC,6143
	LD	(HL),0
	LDIR

	; Clear LOAD_LINE_TEMP (128 bytes)
	LD	HL,LOAD_LINE_TEMP
	LD	DE,LOAD_LINE_TEMP+1
	LD	BC,127
	LD	(HL),0
	LDIR

	XOR	A
	LD	(NEED_SCREEN_RENDER),A
	LD	(NEED_LINE_RENDER),A
	LD	(NEED_STATUS_RENDER),A

	CALL	INIT_SLOT_SYSTEM
	CALL	INIT_FAR_RAM_BANKS
	RET

INIT_FAR_RAM_BANKS:
	; 1. Query CP/M Active User Bank
	PUSH	IX
	LD	B,0F3H			; SYSGETBNK
	RST	08H
	POP	IX
	LD	A,C
	LD	(CPM_USER_BANK),A

	; 2. Query Total RAM Banks (SYSGET 0xF1)
	PUSH	IX
	LD	B,0F8H
	LD	C,0F1H
	RST	08H
	POP	IX
	LD	A,E
	LD	(RAM_BANK_COUNT),A
	LD	A,D
	LD	(ROM_BANK_COUNT),A

	; 3. Populate EXT_BANK_TABLE allocating downward from CPM_USER_BANK - 1
	LD	HL,EXT_BANK_TABLE
	LD	B,0			; Counter for populated banks
	LD	A,(CPM_USER_BANK)
	LD	C,A			; C = CPM_USER_BANK (e.g. 0x8F)

POPULATE_BANK_LOOP:
	DEC	C			; Allocate downward: 0x8E, 0x8D, 0x8C...
	LD	A,C
	CP	080H
	JR	C,POPULATE_BANK_DONE	; Stop if below 0x80

	LD	(HL),C
	INC	HL
	INC	B
	LD	A,B
	CP	MAX_FAR_BANKS
	JR	Z,POPULATE_BANK_DONE
	JR	POPULATE_BANK_LOOP

POPULATE_BANK_DONE:
	LD	A,B
	LD	(EXT_BANK_COUNT),A
	RET

;------------------------------------------------------------------------------
; WRITE_FAR_SLOT: Write 128-byte line from local memory to physical Far RAM slot
; Inputs: HL = Local Source Address (in CPM_USER_BANK)
;         BC = 16-bit Physical Slot ID (0..3583)
; Preserves: All registers except AF
;------------------------------------------------------------------------------
WRITE_FAR_SLOT:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	LD	(FAR_LOCAL_ADDR),HL

	; bank_idx = B (high byte = slot / 256)
	LD	A,B
	LD	HL,EXT_BANK_TABLE
	ADD	A,L
	LD	L,A
	JR	NC,WFL_NO_CY
	INC	H
WFL_NO_CY:
	LD	A,(HL)			; A = Destination RAM Bank ID
	LD	(FAR_DEST_BANK),A

	; far_offset = C * 128 = (C << 7)
	LD	L,C
	LD	H,0
	ADD	HL,HL			; *2
	ADD	HL,HL			; *4
	ADD	HL,HL			; *8
	ADD	HL,HL			; *16
	ADD	HL,HL			; *32
	ADD	HL,HL			; *64
	ADD	HL,HL			; *128
	LD	(FAR_DEST_ADDR),HL

	; SYSSETCPY: D = Dest Bank, E = Src Bank, HL = 128
	PUSH	IX
	LD	B,0F4H			; SYSSETCPY
	LD	A,(FAR_DEST_BANK)
	LD	D,A
	LD	A,(CPM_USER_BANK)
	LD	E,A
	LD	HL,MAX_LINE_STRIDE	; 128 bytes
	RST	08H
	POP	IX

	; SYSBNKCPY: HL = Src Addr, DE = Dest Addr
	LD	HL,(FAR_LOCAL_ADDR)
	LD	DE,(FAR_DEST_ADDR)
	PUSH	IX
	LD	B,0F5H			; SYSBNKCPY
	RST	08H
	POP	IX

	POP	HL
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; READ_FAR_SLOT: Read 128-byte line from physical Far RAM slot into local memory
; Inputs: DE = Local Destination Address (in CPM_USER_BANK)
;         BC = 16-bit Physical Slot ID (0..3583)
; Preserves: All registers except AF
;------------------------------------------------------------------------------
READ_FAR_SLOT:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	LD	(FAR_LOCAL_ADDR),DE

	; bank_idx = B (high byte = slot / 256)
	LD	A,B
	LD	HL,EXT_BANK_TABLE
	ADD	A,L
	LD	L,A
	JR	NC,RFL_NO_CY
	INC	H
RFL_NO_CY:
	LD	A,(HL)			; A = Source RAM Bank ID
	LD	(FAR_SRC_BANK),A

	; far_offset = C * 128
	LD	L,C
	LD	H,0
	ADD	HL,HL			; *2
	ADD	HL,HL			; *4
	ADD	HL,HL			; *8
	ADD	HL,HL			; *16
	ADD	HL,HL			; *32
	ADD	HL,HL			; *64
	ADD	HL,HL			; *128
	LD	(FAR_SRC_ADDR),HL

	; SYSSETCPY: D = Dest Bank (CPM_USER_BANK), E = Src Bank, HL = 128
	PUSH	IX
	LD	B,0F4H			; SYSSETCPY
	LD	A,(CPM_USER_BANK)
	LD	D,A
	LD	A,(FAR_SRC_BANK)
	LD	E,A
	LD	HL,MAX_LINE_STRIDE	; 128 bytes
	RST	08H
	POP	IX

	; SYSBNKCPY: HL = Far Src Addr, DE = Local Dest Addr
	LD	HL,(FAR_SRC_ADDR)
	LD	DE,(FAR_LOCAL_ADDR)
	PUSH	IX
	LD	B,0F5H			; SYSBNKCPY
	RST	08H
	POP	IX

	POP	HL
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; WRITE_FAR_LINE: Write 128-byte line to document line BC via DOC_LINE_SLOTS
; Inputs: HL = Local Source Address (in CPM_USER_BANK)
;         BC = 16-bit Document Line Index (0..3583)
; Preserves: All registers except AF
;------------------------------------------------------------------------------
WRITE_FAR_LINE:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	; Lookup slot ID: DOC_LINE_SLOTS[BC]
	LD	L,C
	LD	H,B
	ADD	HL,HL			; HL = BC * 2
	LD	DE,DOC_LINE_SLOTS
	ADD	HL,DE
	LD	C,(HL)
	INC	HL
	LD	B,(HL)			; BC = physical slot ID

	POP	HL			; Restore Local Source Address
	CALL	WRITE_FAR_SLOT
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; READ_FAR_LINE: Read 128-byte line from document line BC via DOC_LINE_SLOTS
; Inputs: DE = Local Destination Address (in CPM_USER_BANK)
;         BC = 16-bit Document Line Index (0..3583)
; Preserves: All registers except AF
;------------------------------------------------------------------------------
READ_FAR_LINE:
	PUSH	BC
	PUSH	HL

	; Lookup slot ID: DOC_LINE_SLOTS[BC]
	LD	L,C
	LD	H,B
	ADD	HL,HL			; HL = BC * 2
	LD	BC,DOC_LINE_SLOTS
	ADD	HL,BC
	LD	C,(HL)
	INC	HL
	LD	B,(HL)			; BC = physical slot ID

	POP	HL
	CALL	READ_FAR_SLOT
	POP	BC
	RET

;------------------------------------------------------------------------------
; INIT_SLOT_SYSTEM: Reset slot allocator and free list
;------------------------------------------------------------------------------
INIT_SLOT_SYSTEM:
	LD	HL,0
	LD	(NEXT_FRESH_SLOT),HL
	LD	HL,0FFFFH
	LD	(FIRST_FREE_SLOT),HL
	RET

;------------------------------------------------------------------------------
; ALLOC_SLOT: Allocate a physical Far RAM slot ID (0..3583)
; Returns: Carry=0, HL = 16-bit slot ID; Carry=1 on out-of-memory
; Preserves: BC, DE
;------------------------------------------------------------------------------
ALLOC_SLOT:
	PUSH	DE
	PUSH	BC

	; Check if any recycled slot is available in FIRST_FREE_SLOT
	LD	HL,(FIRST_FREE_SLOT)
	LD	A,H
	AND	L
	INC	A			; If HL == 0xFFFF, A is 0 (Z set)
	JR	Z,ALLOC_FRESH_SLOT

	; Pop slot from free list in Extended RAM
	; HL = slot ID to allocate
	PUSH	HL			; Save slot ID
	LD	B,H
	LD	C,L			; BC = slot ID
	LD	DE,LOAD_LINE_TEMP
	CALL	READ_FAR_SLOT		; Read first 128 bytes of slot (contains next ptr)
	LD	HL,(LOAD_LINE_TEMP)	; HL = next free slot ID
	LD	(FIRST_FREE_SLOT),HL
	POP	HL			; Restore allocated slot ID
	POP	BC
	POP	DE
	OR	A			; Carry = 0 (success)
	RET

ALLOC_FRESH_SLOT:
	LD	HL,(NEXT_FRESH_SLOT)
	LD	DE,MAX_DOC_LINES	; 3584
	LD	A,H
	CP	D
	JR	C,ALLOC_FRESH_OK
	JR	NZ,ALLOC_FAIL
	LD	A,L
	CP	E
	JR	NC,ALLOC_FAIL

ALLOC_FRESH_OK:
	PUSH	HL
	INC	HL
	LD	(NEXT_FRESH_SLOT),HL
	POP	HL			; HL = allocated slot ID
	POP	BC
	POP	DE
	OR	A			; Carry = 0 (success)
	RET

ALLOC_FAIL:
	POP	BC
	POP	DE
	SCF				; Carry = 1 (error: no free slots)
	RET

;------------------------------------------------------------------------------
; FREE_SLOT: Return a Far RAM slot ID to the Extended RAM free list
; Input: HL = 16-bit Physical Slot ID (0..3583)
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
FREE_SLOT:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL

	; Prepare LOAD_LINE_TEMP: first 2 bytes = current FIRST_FREE_SLOT
	LD	DE,(FIRST_FREE_SLOT)
	LD	(LOAD_LINE_TEMP),DE

	; Write to Far RAM slot HL
	LD	B,H
	LD	C,L			; BC = slot ID
	LD	HL,LOAD_LINE_TEMP
	CALL	WRITE_FAR_SLOT

	; Update FIRST_FREE_SLOT to the newly freed slot ID
	POP	HL
	PUSH	HL
	LD	(FIRST_FREE_SLOT),HL

	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

;------------------------------------------------------------------------------
; APPEND_LINE_SLOT: Allocate slot and assign to DOC_LINE_SLOTS[DOC_TOTAL_LINES]
; Returns: Carry=0, BC = allocated slot ID; Carry=1 on out-of-memory
; Preserves: DE
;------------------------------------------------------------------------------
APPEND_LINE_SLOT:
	CALL	ALLOC_SLOT		; HL = slot ID
	RET	C
	PUSH	HL			; Save slot ID
	LD	BC,(DOC_TOTAL_LINES)
	LD	L,C
	LD	H,B
	ADD	HL,HL			; * 2
	LD	BC,DOC_LINE_SLOTS
	ADD	HL,BC
	POP	BC			; BC = slot ID
	LD	(HL),C
	INC	HL
	LD	(HL),B
	OR	A			; Carry = 0
	RET

;------------------------------------------------------------------------------
; FLUSH_DIRTY_CACHE: Write modified lines in local cache back to Far RAM banks
;------------------------------------------------------------------------------
FLUSH_DIRTY_CACHE:
	LD	A,(CACHE_DIRTY)
	OR	A
	RET	Z			; Cache is clean, nothing to flush

	PUSH	BC
	PUSH	DE
	PUSH	HL

	XOR	A
	LD	(CACHE_DIRTY),A		; Clear dirty flag before flush

	LD	C,0			; Local cache line counter (0..CACHE_SIZE_LINES-1)
FLUSH_CACHE_LOOP:
	LD	A,C
	CP	CACHE_SIZE_LINES
	JR	NC,FLUSH_CACHE_DONE

	; Calculate doc_line = CACHE_START_ROW + C
	LD	HL,(CACHE_START_ROW)
	LD	E,C
	LD	D,0
	ADD	HL,DE			; HL = doc_line
	LD	B,H
	LD	C,L			; BC = doc_line

	; Check if doc_line < DOC_TOTAL_LINES
	LD	HL,(DOC_TOTAL_LINES)
	LD	A,H
	CP	B
	JR	C,FLUSH_CACHE_DONE
	JR	NZ,DO_FLUSH_LINE
	LD	A,L
	CP	C
	JR	Z,FLUSH_CACHE_DONE
	JR	C,FLUSH_CACHE_DONE

DO_FLUSH_LINE:
	; Calculate local source pointer: LINE_STORAGE + (C_local * 128)
	LD	A,E			; E was local C index
	LD	(SLOT_TEMP),A
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
	ADD	HL,DE			; HL = Local source line pointer

	CALL	WRITE_FAR_LINE
	LD	A,(SLOT_TEMP)		; Restore local index
	LD	C,A
	INC	C
	JR	FLUSH_CACHE_LOOP

FLUSH_CACHE_DONE:
	POP	HL
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; ENSURE_CACHE_WINDOW: Ensure doc_line BC is in local LINE_STORAGE cache
; Inputs: BC = 16-bit Document Line Index (0..3583)
; Returns: HL = Pointer to line start in LINE_STORAGE
; Preserves: BC, DE
;------------------------------------------------------------------------------
ENSURE_CACHE_WINDOW:
	PUSH	BC
	PUSH	DE

	; Check if BC >= (CACHE_START_ROW) AND BC < (CACHE_START_ROW) + CACHE_SIZE_LINES
	LD	HL,(CACHE_START_ROW)
	; Check BC >= CACHE_START_ROW
	LD	A,B
	CP	H
	JR	C,RELOAD_CACHE_WINDOW
	JR	NZ,CHECK_UPPER_BOUND
	LD	A,C
	CP	L
	JR	C,RELOAD_CACHE_WINDOW

CHECK_UPPER_BOUND:
	; Calculate offset = BC - CACHE_START_ROW
	LD	A,C
	SUB	L
	LD	E,A
	LD	A,B
	SBC	A,H
	JR	NZ,RELOAD_CACHE_WINDOW	; High byte must be 0
	LD	A,E
	CP	CACHE_SIZE_LINES
	JR	NC,RELOAD_CACHE_WINDOW	; Outside cache range

	; Inside cache! Offset is in E (0..CACHE_SIZE_LINES-1)
	JR	CALC_CACHE_LINE_PTR

RELOAD_CACHE_WINDOW:
	; Flush old dirty cache if modified
	CALL	FLUSH_DIRTY_CACHE

	; Calculate new CACHE_START_ROW = max(0, BC - (CACHE_SIZE_LINES / 2))
	LD	HL,CACHE_SIZE_LINES / 2
	LD	A,C
	SUB	L
	LD	E,A
	LD	A,B
	SBC	A,H
	JR	C,SET_START_ZERO
	LD	D,A
	LD	(CACHE_START_ROW),DE
	JR	LOAD_CACHE_LINES

SET_START_ZERO:
	LD	DE,0
	LD	(CACHE_START_ROW),DE

LOAD_CACHE_LINES:
	; Load CACHE_SIZE_LINES from Far RAM into LINE_STORAGE
	LD	C,0			; Local cache slot 0..CACHE_SIZE_LINES-1
LOAD_SLOT_LOOP:
	LD	A,C
	CP	CACHE_SIZE_LINES
	JR	NC,LOAD_CACHE_DONE

	; Calculate doc_line = CACHE_START_ROW + C
	LD	HL,(CACHE_START_ROW)
	LD	E,C
	LD	D,0
	ADD	HL,DE			; HL = target doc_line
	LD	B,H
	LD	A,L
	LD	L,C			; Save local slot in L
	LD	C,A			; BC = target doc_line

	; Calculate local destination address: LINE_STORAGE + (local_slot * 128)
	LD	A,L
	LD	(SLOT_TEMP),A
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
	LD	D,H
	LD	E,L			; DE = Local destination address

	; Check if doc_line < DOC_TOTAL_LINES
	LD	HL,(DOC_TOTAL_LINES)
	LD	A,H
	CP	B
	JR	C,FILL_EMPTY_SLOT
	JR	NZ,DO_FETCH_SLOT
	LD	A,L
	CP	C
	JR	Z,FILL_EMPTY_SLOT
	JR	C,FILL_EMPTY_SLOT

DO_FETCH_SLOT:
	CALL	READ_FAR_LINE
	JR	NEXT_SLOT

FILL_EMPTY_SLOT:
	; Zero fill empty slot
	EX	DE,HL			; HL = line start
	LD	(HL),0

NEXT_SLOT:
	LD	A,(SLOT_TEMP)
	LD	C,A
	INC	C
	JR	LOAD_SLOT_LOOP

LOAD_CACHE_DONE:
	XOR	A
	LD	(CACHE_DIRTY),A

	; Calculate offset for requested line: (BC_orig - CACHE_START_ROW)
	POP	DE
	POP	BC
	PUSH	BC
	PUSH	DE

	LD	HL,(CACHE_START_ROW)
	LD	A,C
	SUB	L
	LD	E,A			; E = local line index (0..CACHE_SIZE_LINES-1)

CALC_CACHE_LINE_PTR:
	LD	L,E
	LD	H,0
	ADD	HL,HL			; *2
	ADD	HL,HL			; *4
	ADD	HL,HL			; *8
	ADD	HL,HL			; *16
	ADD	HL,HL			; *32
	ADD	HL,HL			; *64
	ADD	HL,HL			; *128
	LD	DE,LINE_STORAGE
	ADD	HL,DE			; HL = pointer to line start in LINE_STORAGE

	POP	DE
	POP	BC
	RET

RELOAD_CACHE_WINDOW_FORCE:
	PUSH	HL
	PUSH	BC
	LD	HL,0FFFFH
	LD	(CACHE_START_ROW),HL
	LD	BC,(CUR_DOC_ROW)
	CALL	ENSURE_CACHE_WINDOW
	POP	BC
	POP	HL
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
	; Timeout: Standalone ESC key pressed
	LD	A,(BLOCK_ACTIVE)
	OR	A
	JR	Z,ESC_TO_SPLASH
	; Block selection active: cancel block highlight instead of exiting to splash
	CALL	CANCEL_BLOCK
	RET

ESC_TO_SPLASH:
	CALL	SHOW_SPLASH_SCREEN
	RET

GOT_ESC_BYTE:
	CALL	GET_KEY
	CP	'['
	JR	Z,HANDLE_CSI
	CP	'O'
	JR	Z,HANDLE_SS3
	CP	'<'
	JR	Z,DO_ESC_TOP
	CP	't'
	JR	Z,DO_ESC_TOP
	CP	'T'
	JR	Z,DO_ESC_TOP
	CP	'>'
	JR	Z,DO_ESC_BOTTOM
	CP	'b'
	JR	Z,DO_ESC_BOTTOM
	CP	'B'
	JR	Z,DO_ESC_BOTTOM
	CP	KEY_ESC
	JR	Z,HANDLE_VT100_ESC
	RET

DO_ESC_TOP:
	CALL	JUMP_FILE_TOP
	RET

DO_ESC_BOTTOM:
	CALL	JUMP_FILE_BOTTOM
	RET

HANDLE_SS3:
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
	RET

HANDLE_CSI:
	XOR	A
	LD	(CSI_DIGIT_PREFIX),A
	CALL	GET_KEY
	CP	'A'			; Up Arrow
	JP	Z,CURSOR_UP
	CP	'B'			; Down Arrow
	JP	Z,CURSOR_DOWN
	CP	'C'			; Right Arrow
	JP	Z,CURSOR_RIGHT
	CP	'D'			; Left Arrow
	JP	Z,CURSOR_LEFT
	CP	'H'			; Home (ESC [ H)
	JP	Z,CURSOR_HOME
	CP	'F'			; End (ESC [ F)
	JP	Z,CURSOR_END
	CP	'1'			; Home (ESC [ 1 ~) or modifier prefix (ESC [ 1 ; ...)
	JP	Z,HANDLE_CSI_1
	CP	'4'			; End (ESC [ 4 ~) or modifier prefix (ESC [ 4 ; ...)
	JP	Z,HANDLE_CSI_4
	CP	'7'			; Home (ESC [ 7 ~) / Ctrl+Home (ESC [ 7 ^)
	JP	Z,HANDLE_CSI_7
	CP	'8'			; End (ESC [ 8 ~) / Ctrl+End (ESC [ 8 ^)
	JP	Z,HANDLE_CSI_8
	CP	'3'			; Delete Key (ESC [ 3 ~)
	JP	Z,HANDLE_CSI_DEL
	CP	'5'			; Page Up (ESC [ 5 ~)
	JP	Z,HANDLE_CSI_PGUP
	CP	'6'			; Page Down (ESC [ 6 ~)
	JP	Z,HANDLE_CSI_PGDN
	CP	'I'			; Page Up (VT alternative)
	JP	Z,PAGE_UP
	CP	'G'			; Page Down (VT alternative)
	JP	Z,PAGE_DOWN

	; Check if parameter/modifier digits present (e.g. 1;2A, 1~, 4~)
	CP	'0'
	JP	C,CSI_DONE
	CP	'9'+1
	JR	C,HANDLE_CSI_LOOP
	RET

HANDLE_CSI_1:
	LD	A,'1'
	LD	(CSI_DIGIT_PREFIX),A
	CALL	GET_KEY
	CP	'~'
	JP	Z,CURSOR_HOME
	CP	';'
	JR	Z,HANDLE_CSI_LOOP
	RET

HANDLE_CSI_4:
	LD	A,'4'
	LD	(CSI_DIGIT_PREFIX),A
	CALL	GET_KEY
	CP	'~'
	JP	Z,CURSOR_END
	CP	';'
	JR	Z,HANDLE_CSI_LOOP
	RET

HANDLE_CSI_7:
	CALL	GET_KEY
	CP	'^'
	JP	Z,JUMP_FILE_TOP		; rxvt Ctrl+Home (ESC [ 7 ^)
	JP	CURSOR_HOME

HANDLE_CSI_8:
	CALL	GET_KEY
	CP	'^'
	JP	Z,JUMP_FILE_BOTTOM	; rxvt Ctrl+End (ESC [ 8 ^)
	JP	CURSOR_END

HANDLE_CSI_DEL:
	; Consume trailing '~'
	CALL	GET_KEY
	LD	A,(BLOCK_ACTIVE)
	CP	2
	JR	Z,DO_CSI_DEL_BLOCK
	CP	1
	JR	Z,DO_CSI_DEL_CANCEL_SETUP
	CALL	DO_DELETE_FORWARD
	RET

DO_CSI_DEL_BLOCK:
	CALL	DO_DELETE_BLOCK
	RET

DO_CSI_DEL_CANCEL_SETUP:
	CALL	CANCEL_BLOCK
	RET

HANDLE_CSI_PGUP:
	; Consume trailing '~'
	CALL	GET_KEY
	CALL	PAGE_UP
	RET

HANDLE_CSI_PGDN:
	; Consume trailing '~'
	CALL	GET_KEY
	CALL	PAGE_DOWN
	RET

HANDLE_CSI_LOOP:
	CALL	GET_KEY
	CP	'~'
	JR	Z,HANDLE_CSI_TILDE
	CP	'A'
	JP	Z,CURSOR_UP
	CP	'B'
	JP	Z,CURSOR_DOWN
	CP	'C'
	JP	Z,CURSOR_RIGHT
	CP	'D'
	JP	Z,CURSOR_LEFT
	CP	'H'
	JP	Z,JUMP_FILE_TOP		; Modified CSI: ESC [ 1 ; 5 H -> Ctrl+Home!
	CP	'F'
	JP	Z,JUMP_FILE_BOTTOM	; Modified CSI: ESC [ 1 ; 5 F -> Ctrl+End!
	CP	'I'
	JP	Z,PAGE_UP
	CP	'G'
	JP	Z,PAGE_DOWN
	CP	';'
	JR	Z,HANDLE_CSI_LOOP
	CP	'0'
	JR	C,CSI_DONE
	CP	'9'+1
	JR	C,HANDLE_CSI_LOOP
CSI_DONE:
	RET

HANDLE_CSI_TILDE:
	LD	A,(CSI_DIGIT_PREFIX)
	CP	'1'
	JP	Z,JUMP_FILE_TOP		; ESC [ 1 ; 5 ~ -> Ctrl+Home!
	CP	'4'
	JP	Z,JUMP_FILE_BOTTOM	; ESC [ 4 ; 5 ~ -> Ctrl+End!
	RET

CURSOR_HOME:
	XOR	A
	LD	(CUR_COL),A
	LD	(TARGET_COL),A
	LD	A,(BLOCK_ACTIVE)
	CP	1
	RET	NZ
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

CURSOR_END:
	CALL	GET_CUR_ROW_LEN
	LD	A,B
	LD	(CUR_COL),A
	LD	A,C
	LD	(TARGET_COL),A
	LD	A,(BLOCK_ACTIVE)
	CP	1
	RET	NZ
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

;;------------------------------------------------------------------------------
; Get Length of Current Line at CUR_DOC_ROW
; Returns: B = Byte length (0..126), C = Visual length (0..ACTIVE_COLS), HL = line start
; Preserves: DE
;------------------------------------------------------------------------------
GET_CUR_ROW_LEN:
	LD	BC,(CUR_DOC_ROW)
	CALL	ENSURE_CACHE_WINDOW	; HL = line start in LINE_STORAGE
	PUSH	HL			; Save line start

	LD	B,0			; B = byte count
	LD	C,0			; C = visual column accumulator
GET_ROW_LEN_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,GET_ROW_LEN_DONE
	CP	KEY_TAB
	JR	Z,GET_ROW_TAB
	INC	B
	INC	C
	JR	GET_ROW_NEXT

GET_ROW_TAB:
	INC	B
	LD	A,C
	AND	7
	LD	E,A
	LD	A,8
	SUB	E			; spaces to add
	ADD	A,C
	LD	C,A

GET_ROW_NEXT:
	INC	HL
	LD	A,B
	CP	MAX_LINE_STRIDE-2
	JR	NC,GET_ROW_LEN_DONE
	JR	GET_ROW_LEN_LOOP

GET_ROW_LEN_DONE:
	POP	HL			; HL = line start
	RET

;------------------------------------------------------------------------------
; Adjust CUR_COL to Match Sticky TARGET_COL (Visual Column) on Current Line
; Preserves: TARGET_COL
;------------------------------------------------------------------------------
ADJUST_COL_TO_TARGET:
	CALL	GET_CUR_ROW_LEN		; HL = line start, B = byte length
	LD	C,0			; C = character index (0..B)
	LD	E,0			; E = visual column accumulator

MAP_TARGET_LOOP:
	LD	A,C
	CP	B
	JR	NC,SET_TARGET_CHAR_IDX	; At end of line, use max char index (B)

	; Peek character at line_start + C
	PUSH	HL
	PUSH	BC
	LD	B,0
	ADD	HL,BC
	LD	A,(HL)
	POP	BC
	POP	HL

	; Calculate next visual column
	CP	KEY_TAB
	JR	Z,MAP_TARGET_TAB
	INC	E
	JR	MAP_TARGET_CHECK

MAP_TARGET_TAB:
	LD	A,E
	AND	7
	LD	D,A
	LD	A,8
	SUB	D
	ADD	A,E
	LD	E,A

MAP_TARGET_CHECK:
	; If next visual column > TARGET_COL, current C is the closest character!
	LD	A,(TARGET_COL)
	CP	E
	JR	C,SET_TARGET_CHAR_IDX
	INC	C
	JR	MAP_TARGET_LOOP

SET_TARGET_CHAR_IDX:
	LD	A,C
	LD	(CUR_COL),A
	RET

CURSOR_UP:
	LD	HL,(CUR_DOC_ROW)
	LD	A,H
	OR	L
	RET	Z			; If at doc row 0, cannot move up

	DEC	HL
	LD	(CUR_DOC_ROW),HL

	; Check if CUR_DOC_ROW < TOP_DOC_ROW
	LD	DE,(TOP_DOC_ROW)
	LD	A,H
	CP	D
	JR	C,C_UP_SCROLL
	JR	NZ,CUR_UP_NO_SCROLL
	LD	A,L
	CP	E
	JR	NC,CUR_UP_NO_SCROLL

C_UP_SCROLL:
	LD	(TOP_DOC_ROW),HL
	CALL	ADJUST_COL_TO_TARGET
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

CUR_UP_NO_SCROLL:
	CALL	ADJUST_COL_TO_TARGET
	LD	A,(BLOCK_ACTIVE)
	OR	A
	RET	Z
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

CURSOR_DOWN:
	LD	HL,(DOC_TOTAL_LINES)
	LD	A,H
	OR	L
	RET	Z			; 0 lines

	DEC	HL			; Max valid doc row = DOC_TOTAL_LINES - 1
	LD	DE,(CUR_DOC_ROW)
	; If CUR_DOC_ROW >= max valid row, cannot move down
	LD	A,D
	CP	H
	JR	C,C_DOWN_MOVE
	JR	NZ,CUR_DOWN_NO_MOVE
	LD	A,E
	CP	L
	JR	NC,CUR_DOWN_NO_MOVE

C_DOWN_MOVE:
	INC	DE
	LD	(CUR_DOC_ROW),DE

	; Check if CUR_DOC_ROW - TOP_DOC_ROW >= ACTIVE_ROWS - 1
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(TOP_DOC_ROW)
	AND	A
	SBC	HL,DE			; HL = screen row index
	LD	A,(ACTIVE_ROWS)
	DEC	A
	DEC	A			; A = max screen row index (ACTIVE_ROWS - 2)
	CP	L
	JR	NC,CUR_DOWN_NO_SCROLL	; Screen row <= max, no scroll

	; Scroll down by 1 line
	LD	HL,(TOP_DOC_ROW)
	INC	HL
	LD	(TOP_DOC_ROW),HL
	CALL	ADJUST_COL_TO_TARGET
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

CUR_DOWN_NO_SCROLL:
	CALL	ADJUST_COL_TO_TARGET
	LD	A,(BLOCK_ACTIVE)
	OR	A
	RET	Z
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

CUR_DOWN_NO_MOVE:
	RET

CURSOR_LEFT:
	LD	A,(CUR_COL)
	OR	A
	JR	Z,CURSOR_LEFT_PREV_LINE
	DEC	A
	LD	(CUR_COL),A
	CALL	CALC_VISUAL_COL
	LD	(TARGET_COL),A		; Horizontal movement updates sticky target visual column
	LD	A,(BLOCK_ACTIVE)
	CP	1
	RET	NZ
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

CURSOR_LEFT_PREV_LINE:
	; Wrap to end of previous line if CUR_DOC_ROW > 0
	LD	HL,(CUR_DOC_ROW)
	LD	A,H
	OR	L
	RET	Z			; At line 0, cannot wrap back
	DEC	HL
	LD	(CUR_DOC_ROW),HL

	; Check if scrolled above top of viewport
	LD	DE,(TOP_DOC_ROW)
	LD	A,H
	CP	D
	JR	C,CL_SCROLL
	JR	NZ,CL_NO_SCROLL
	LD	A,L
	CP	E
	JR	NC,CL_NO_SCROLL

CL_SCROLL:
	LD	(TOP_DOC_ROW),HL
	CALL	GET_CUR_ROW_LEN		; B = prev line length
	LD	A,B
	LD	(CUR_COL),A
	CALL	CALC_VISUAL_COL
	LD	(TARGET_COL),A
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

CL_NO_SCROLL:
	CALL	GET_CUR_ROW_LEN		; B = prev line length
	LD	A,B
	LD	(CUR_COL),A
	CALL	CALC_VISUAL_COL
	LD	(TARGET_COL),A
	LD	A,(BLOCK_ACTIVE)
	OR	A
	RET	Z
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

CURSOR_RIGHT:
	CALL	GET_CUR_ROW_LEN		; B = current line byte length, C = visual length
	LD	A,(CUR_COL)
	CP	B
	JR	NC,CURSOR_RIGHT_NEXT_LINE ; If at or past EOL, wrap to next line!

	; Check if visual cursor is already at ACTIVE_COLS - 1 (col 119 or 79)
	CALL	CALC_VISUAL_COL
	LD	D,A
	LD	A,(ACTIVE_COLS)
	DEC	A
	CP	D
	JR	Z,CURSOR_RIGHT_NEXT_LINE ; If at column 119, wrap to next line!
	JR	C,CURSOR_RIGHT_NEXT_LINE

	LD	A,(CUR_COL)
	INC	A
	LD	(CUR_COL),A
	CALL	CALC_VISUAL_COL
	LD	(TARGET_COL),A		; Horizontal movement updates sticky target visual column
	LD	A,(BLOCK_ACTIVE)
	CP	1
	RET	NZ
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

CURSOR_RIGHT_NEXT_LINE:
	; Wrap to start of next line if CUR_DOC_ROW + 1 < DOC_TOTAL_LINES
	LD	HL,(DOC_TOTAL_LINES)
	LD	DE,(CUR_DOC_ROW)
	INC	DE			; Next doc row
	LD	A,D
	CP	H
	JR	C,CR_WRAP_OK
	JR	NZ,CR_WRAP_FAIL
	LD	A,E
	CP	L
	JR	NC,CR_WRAP_FAIL

CR_WRAP_OK:
	LD	(CUR_DOC_ROW),DE
	XOR	A
	LD	(CUR_COL),A
	LD	(TARGET_COL),A

	; Check if scrolled past bottom of screen window
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(TOP_DOC_ROW)
	AND	A
	SBC	HL,DE
	LD	A,(ACTIVE_ROWS)
	DEC	A
	DEC	A
	CP	L
	JR	NC,CR_NO_SCROLL_BLOCK_CHECK

	LD	HL,(TOP_DOC_ROW)
	INC	HL
	LD	(TOP_DOC_ROW),HL
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

CR_NO_SCROLL_BLOCK_CHECK:
	LD	A,(BLOCK_ACTIVE)
	OR	A
	RET	Z
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

CR_WRAP_FAIL:
	RET

;------------------------------------------------------------------------------
; Page Up Navigation: Scroll viewport and cursor up by one page
;------------------------------------------------------------------------------
PAGE_UP:
	LD	HL,(CUR_DOC_ROW)
	LD	A,H
	OR	L
	JR	NZ,PGUP_CAN_MOVE
	LD	HL,(TOP_DOC_ROW)
	LD	A,H
	OR	L
	RET	Z			; Already at line 0, nothing to move

PGUP_CAN_MOVE:
	CALL	GET_PAGE_STEP		; DE = PAGE_STEP (ACTIVE_ROWS - 2)
	LD	HL,(CUR_DOC_ROW)
	AND	A
	SBC	HL,DE
	JR	NC,PGUP_CUR_OK
	LD	HL,0			; Clamped to doc row 0
PGUP_CUR_OK:
	LD	(CUR_DOC_ROW),HL

	CALL	GET_PAGE_STEP		; DE = PAGE_STEP
	LD	HL,(TOP_DOC_ROW)
	AND	A
	SBC	HL,DE
	JR	NC,PGUP_TOP_OK
	LD	HL,0			; Clamped to top row 0
PGUP_TOP_OK:
	; Ensure TOP_DOC_ROW <= CUR_DOC_ROW
	LD	DE,(CUR_DOC_ROW)
	LD	A,H
	CP	D
	JR	C,PGUP_TOP_SAVED
	JR	NZ,PGUP_TOP_ADJUST
	LD	A,L
	CP	E
	JR	C,PGUP_TOP_SAVED
PGUP_TOP_ADJUST:
	EX	DE,HL			; HL = CUR_DOC_ROW
PGUP_TOP_SAVED:
	LD	(TOP_DOC_ROW),HL

	CALL	ADJUST_COL_TO_TARGET
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

;------------------------------------------------------------------------------
; Page Down Navigation: Scroll viewport and cursor down by one page
;------------------------------------------------------------------------------
PAGE_DOWN:
	LD	HL,(DOC_TOTAL_LINES)
	LD	A,H
	OR	L
	RET	Z			; 0 lines

	DEC	HL			; HL = max_valid_row (DOC_TOTAL_LINES - 1)
	LD	DE,(CUR_DOC_ROW)
	; Compare CUR_DOC_ROW (DE) with max_valid_row (HL)
	LD	A,D
	CP	H
	JR	C,PGDN_CAN_MOVE
	JR	NZ,PGDN_NO_MOVE
	LD	A,E
	CP	L
	JR	NC,PGDN_NO_MOVE		; Already at or past last line

PGDN_CAN_MOVE:
	PUSH	HL			; Save max_valid_row
	CALL	GET_PAGE_STEP		; DE = PAGE_STEP
	LD	HL,(CUR_DOC_ROW)
	ADD	HL,DE			; HL = target CUR_DOC_ROW
	POP	DE			; DE = max_valid_row

	; Clamp target CUR_DOC_ROW (HL) to max_valid_row (DE)
	LD	A,H
	CP	D
	JR	C,PGDN_CUR_OK
	JR	NZ,PGDN_CUR_CLAMP
	LD	A,L
	CP	E
	JR	C,PGDN_CUR_OK
PGDN_CUR_CLAMP:
	EX	DE,HL			; HL = max_valid_row
PGDN_CUR_OK:
	LD	(CUR_DOC_ROW),HL	; Save clamped CUR_DOC_ROW

	; Check if all lines fit on screen (DOC_TOTAL_LINES <= ACTIVE_ROWS - 1)
	LD	HL,(DOC_TOTAL_LINES)
	LD	A,(ACTIVE_ROWS)
	DEC	A			; Viewport height (e.g. 23 or 39)
	LD	E,A
	LD	D,0
	LD	A,H
	OR	A
	JR	NZ,PGDN_CALC_TOP
	LD	A,L
	CP	E
	JR	C,PGDN_KEEP_TOP_ZERO
	JR	Z,PGDN_KEEP_TOP_ZERO

PGDN_CALC_TOP:
	; Advance TOP_DOC_ROW by PAGE_STEP
	CALL	GET_PAGE_STEP		; DE = PAGE_STEP
	LD	HL,(TOP_DOC_ROW)
	ADD	HL,DE			; HL = target TOP_DOC_ROW

	; Ensure TOP_DOC_ROW <= CUR_DOC_ROW
	LD	DE,(CUR_DOC_ROW)
	LD	A,H
	CP	D
	JR	C,PGDN_TOP_OK
	JR	NZ,PGDN_TOP_CLAMP
	LD	A,L
	CP	E
	JR	C,PGDN_TOP_OK
PGDN_TOP_CLAMP:
	EX	DE,HL			; HL = CUR_DOC_ROW
PGDN_TOP_OK:
	LD	(TOP_DOC_ROW),HL
	JR	PGDN_FINISH

PGDN_KEEP_TOP_ZERO:
	LD	HL,0
	LD	(TOP_DOC_ROW),HL

PGDN_FINISH:
	CALL	ADJUST_COL_TO_TARGET
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

PGDN_NO_MOVE:
	RET

;------------------------------------------------------------------------------
; Calculate Page Step Size: DE = ACTIVE_ROWS - 2 (e.g. 38 for 40 rows, 22 for 24 rows)
;------------------------------------------------------------------------------
GET_PAGE_STEP:
	LD	A,(ACTIVE_ROWS)
	DEC	A
	DEC	A
	LD	E,A
	LD	D,0
	RET

;------------------------------------------------------------------------------
; Jump to Top of Document (Line 1, Col 0)
;------------------------------------------------------------------------------
JUMP_FILE_TOP:
	LD	HL,0
	LD	(CUR_DOC_ROW),HL
	LD	(TOP_DOC_ROW),HL
	XOR	A
	LD	(CUR_COL),A
	LD	(TARGET_COL),A
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

;------------------------------------------------------------------------------
; Jump to End/Bottom of Document (Last Line, End of Line)
;------------------------------------------------------------------------------
JUMP_FILE_BOTTOM:
	LD	HL,(DOC_TOTAL_LINES)
	LD	A,H
	OR	L
	JR	NZ,JUMP_BOT_HAS_LINES
	LD	HL,0
	JR	JUMP_BOT_SET_CUR

JUMP_BOT_HAS_LINES:
	DEC	HL			; HL = max_valid_row (DOC_TOTAL_LINES - 1)
JUMP_BOT_SET_CUR:
	LD	(CUR_DOC_ROW),HL
	CALL	GET_CUR_ROW_LEN		; B = byte length, C = visual length
	LD	A,B
	LD	(CUR_COL),A
	LD	A,C
	LD	(TARGET_COL),A

	; Calculate TOP_DOC_ROW so the bottom line is visible at bottom of screen
	; Viewport height: E = ACTIVE_ROWS - 1
	LD	HL,(DOC_TOTAL_LINES)
	LD	A,(ACTIVE_ROWS)
	DEC	A
	LD	E,A
	LD	D,0

	; Compare DOC_TOTAL_LINES (HL) with viewport height (DE)
	LD	A,H
	OR	A
	JR	NZ,JUMP_BOT_SCROLL_TOP
	LD	A,L
	CP	E
	JR	C,JUMP_BOT_TOP_ZERO
	JR	Z,JUMP_BOT_TOP_ZERO

JUMP_BOT_SCROLL_TOP:
	; TOP_DOC_ROW = DOC_TOTAL_LINES - (ACTIVE_ROWS - 1)
	LD	HL,(DOC_TOTAL_LINES)
	AND	A
	SBC	HL,DE
	LD	(TOP_DOC_ROW),HL
	JR	JUMP_BOT_FINISH

JUMP_BOT_TOP_ZERO:
	LD	HL,0
	LD	(TOP_DOC_ROW),HL

JUMP_BOT_FINISH:
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

;------------------------------------------------------------------------------
; Character Insertion at (CUR_DOC_ROW, CUR_COL)
;------------------------------------------------------------------------------
DO_CHAR_INSERT:
	LD	(CHAR_INSERT_TEMP),A	; Save character to insert

	; Ensure DOC_TOTAL_LINES >= CUR_DOC_ROW + 1
	LD	HL,(DOC_TOTAL_LINES)
	LD	DE,(CUR_DOC_ROW)
	LD	A,E
	CP	L
	LD	A,D
	SBC	A,H
	JR	C,ROW_IN_BOUNDS
	INC	DE
	LD	(DOC_TOTAL_LINES),DE

ROW_IN_BOUNDS:
	CALL	GET_CUR_ROW_LEN		; HL = line start, B = byte length, C = visual length

	; 1. Check buffer byte capacity limit (126 bytes)
	LD	A,MAX_LINE_STRIDE-2
	CP	B
	RET	C
	RET	Z

	; 2. Check visual screen width limit (ACTIVE_COLS: 120 or 80)
	LD	A,(ACTIVE_COLS)
	CP	C
	JR	Z,CHECK_AT_EOL_REPLACE
	JR	C,CHECK_AT_EOL_REPLACE

	; If inserting a Tab, check if tab expansion would push visual length > ACTIVE_COLS
	LD	A,(CHAR_INSERT_TEMP)
	CP	KEY_TAB
	JR	NZ,LINE_LEN_OK
	CALL	CALC_VISUAL_COL		; A = visual col at CUR_COL
	AND	7
	LD	E,A
	LD	A,8
	SUB	E			; spaces added (1..8)
	ADD	A,C			; projected visual length
	DEC	A			; minus 1 for replaced slot
	LD	E,A
	LD	A,(ACTIVE_COLS)
	CP	E
	RET	C			; Tab would exceed screen width!
	JR	LINE_LEN_OK

CHECK_AT_EOL_REPLACE:
	; Visual line is already at maximum capacity (>= ACTIVE_COLS)
	RET

LINE_LEN_OK:
	LD	A,1
	LD	(CACHE_DIRTY),A		; Mark local cache dirty

	; 4. Compare CUR_COL with line length (B)
	LD	A,(CUR_COL)
	CP	B
	JR	NC,DO_PAD_AND_APPEND	; If CUR_COL >= length: pad spaces and append

	; 5. If CUR_COL < length: shift characters from (line_start + B) down to (line_start + CUR_COL)
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
	; Check if visual cursor is already at or past ACTIVE_COLS - 1 (col 119 or 79)
	CALL	CALC_VISUAL_COL		; A = visual col before advance
	LD	B,A
	LD	A,(ACTIVE_COLS)
	DEC	A			; 119 or 79
	CP	B
	RET	C
	RET	Z			; At column 119, cannot advance cursor further!

	LD	A,(CUR_COL)
	CP	MAX_LINE_STRIDE-2
	RET	NC

	INC	A
	LD	(CUR_COL),A
	CALL	CALC_VISUAL_COL
	LD	(TARGET_COL),A		; Sync sticky target visual column on typing
	RET

;------------------------------------------------------------------------------
; Character Deletion at (CUR_DOC_ROW, CUR_COL) - Backspace Handling
;------------------------------------------------------------------------------
DO_DELETE_CHAR:
	LD	A,(CUR_COL)
	OR	A
	RET	Z			; At column 0, nothing to delete on line

	DEC	A
	LD	(CUR_COL),A
	CALL	CALC_VISUAL_COL
	LD	(TARGET_COL),A		; Sync sticky target visual column on Backspace

	LD	A,1
	LD	(CACHE_DIRTY),A		; Mark cache dirty

	; Calculate delete target in cache
	LD	BC,(CUR_DOC_ROW)
	CALL	ENSURE_CACHE_WINDOW	; HL = line start
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
;------------------------------------------------------------------------------
; Forward Character Deletion at (CUR_DOC_ROW, CUR_COL) - Delete Key Handling
;------------------------------------------------------------------------------
DO_DELETE_FORWARD:
	LD	BC,(CUR_DOC_ROW)
	CALL	ENSURE_CACHE_WINDOW	; HL = line start in LINE_STORAGE
	LD	A,(CUR_COL)
	LD	E,A
	LD	D,0
	ADD	HL,DE			; HL = character under cursor

	LD	A,(HL)
	OR	A
	JR	Z,DO_DEL_FWD_JOIN_NEXT	; At end of line: join NEXT line into current line!

	LD	A,1
	LD	(CACHE_DIRTY),A		; Mark cache dirty

	; Shift characters left from HL+1 into HL until null
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
	LD	A,1
	LD	(NEED_LINE_RENDER),A
	RET

DO_DEL_FWD_JOIN_NEXT:
	; Check if CUR_DOC_ROW + 1 < DOC_TOTAL_LINES
	LD	HL,(DOC_TOTAL_LINES)
	LD	DE,(CUR_DOC_ROW)
	INC	DE
	LD	A,D
	CP	H
	JR	C,DO_DEL_JOIN_OK
	JR	NZ,DO_DEL_JOIN_FAIL
	LD	A,E
	CP	L
	JR	NC,DO_DEL_JOIN_FAIL

DO_DEL_JOIN_OK:
	; Join CUR_DOC_ROW and CUR_DOC_ROW + 1
	LD	BC,(CUR_DOC_ROW)	; BC = upper line (CUR_DOC_ROW)
	CALL	JOIN_TWO_LINES
	JR	C,DO_DEL_JOIN_FAIL	; If combined length > 120, reject

	; Join succeeded: cursor remains at CUR_DOC_ROW, CUR_COL
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

DO_DEL_JOIN_FAIL:
	RET

;------------------------------------------------------------------------------
; Backspace at Column 0 Handling: Joins current line with previous line
;------------------------------------------------------------------------------
DO_DELETE_BLANK_LINE:
	LD	HL,(CUR_DOC_ROW)
	LD	A,H
	OR	L
	JR	NZ,DO_BS_JOIN_PREV

	; At Row 0, Col 0: check if line 0 is empty and DOC_TOTAL_LINES > 1
	LD	HL,(DOC_TOTAL_LINES)
	LD	A,H
	OR	A
	JR	NZ,DO_BS_ROW0_CHECK
	LD	A,L
	CP	2
	JR	C,DO_BS_ROW0_DONE	; Only 1 line total, nothing to delete

DO_BS_ROW0_CHECK:
	; Check if Line 0 is empty
	LD	BC,0
	CALL	ENSURE_CACHE_WINDOW
	LD	A,(HL)
	OR	A
	JR	NZ,DO_BS_ROW0_DONE	; Line 0 has text, do not delete

	; Delete empty Line 0
	CALL	FLUSH_DIRTY_CACHE

	; 1. Free Line 0's slot
	LD	HL,(DOC_LINE_SLOTS)
	CALL	FREE_SLOT

	; 2. Decrement DOC_TOTAL_LINES
	LD	HL,(DOC_TOTAL_LINES)
	DEC	HL
	LD	(DOC_TOTAL_LINES),HL

	; 3. Shift DOC_LINE_SLOTS from index 1 down to index 0
	ADD	HL,HL			; * 2 = byte count
	LD	B,H
	LD	C,L
	LD	DE,DOC_LINE_SLOTS	; Destination
	LD	HL,DOC_LINE_SLOTS+2	; Source
	LDIR

	CALL	RELOAD_CACHE_WINDOW_FORCE
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
DO_BS_ROW0_DONE:
	RET

DO_BS_JOIN_PREV:
	; Join CUR_DOC_ROW with previous line (CUR_DOC_ROW - 1)
	LD	HL,(CUR_DOC_ROW)
	DEC	HL
	LD	B,H
	LD	C,L			; BC = upper line index (CUR_DOC_ROW - 1)
	CALL	JOIN_TWO_LINES
	RET	C			; If Carry set (combined length > 120), do nothing

	; Join succeeded: B = join column offset (original len of previous line)
	LD	HL,(CUR_DOC_ROW)
	DEC	HL
	LD	(CUR_DOC_ROW),HL	; Move cursor to upper line
	LD	A,B
	LD	(CUR_COL),A		; Move cursor to join point
	CALL	CALC_VISUAL_COL
	LD	(TARGET_COL),A

	; Check if CUR_DOC_ROW < TOP_DOC_ROW
	LD	DE,(TOP_DOC_ROW)
	LD	A,H
	CP	D
	JR	C,DO_BS_JOIN_SCROLL_UP
	JR	NZ,DO_BS_JOIN_RENDER
	LD	A,L
	CP	E
	JR	NC,DO_BS_JOIN_RENDER
DO_BS_JOIN_SCROLL_UP:
	LD	(TOP_DOC_ROW),HL

DO_BS_JOIN_RENDER:
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

;------------------------------------------------------------------------------
; Join Two Lines: Line BC (upper) and Line BC+1 (lower)
; Returns: Carry=0 on success, B = join column (len of upper line); Carry=1 on failure
;------------------------------------------------------------------------------
JOIN_TWO_LINES:
	LD	(JOIN_DOC_LINE),BC	; Save upper document line index

	; Check if DOC_TOTAL_LINES >= 2
	LD	HL,(DOC_TOTAL_LINES)
	LD	A,H
	OR	A
	JR	NZ,JOIN_DOC_LEN_OK
	LD	A,L
	CP	2
	JR	NC,JOIN_DOC_LEN_OK
	SCF
	RET

JOIN_DOC_LEN_OK:
	CALL	FLUSH_DIRTY_CACHE

	; 1. Read upper line at (JOIN_DOC_LINE) into LOAD_LINE_TEMP
	LD	BC,(JOIN_DOC_LINE)
	LD	DE,LOAD_LINE_TEMP
	CALL	READ_FAR_LINE

	; Measure upper line length -> B = len_1
	LD	HL,LOAD_LINE_TEMP
	LD	B,0
JOIN_MEASURE_L1:
	LD	A,(HL)
	OR	A
	JR	Z,JOIN_MEASURE_L1_DONE
	INC	HL
	INC	B
	JR	JOIN_MEASURE_L1

JOIN_MEASURE_L1_DONE:
	LD	A,B
	LD	(JOIN_COL_SAVED),A	; Save len_1

	; 2. Read lower line at (JOIN_DOC_LINE + 1) into SPLIT_LINE_TEMP
	LD	BC,(JOIN_DOC_LINE)
	INC	BC
	LD	DE,SPLIT_LINE_TEMP
	CALL	READ_FAR_LINE

	; Measure lower line length -> C = len_2
	LD	HL,SPLIT_LINE_TEMP
	LD	C,0
JOIN_MEASURE_L2:
	LD	A,(HL)
	OR	A
	JR	Z,JOIN_MEASURE_L2_DONE
	INC	HL
	INC	C
	JR	JOIN_MEASURE_L2

JOIN_MEASURE_L2_DONE:
	; Check if len_1 + len_2 <= 120 chars
	LD	A,(JOIN_COL_SAVED)
	ADD	A,C
	CP	MAX_LINE_STRIDE-7	; 128 - 7 = 121 (max length 120 chars)
	JR	C,JOIN_CAPACITY_OK

	; Too long to join!
	SCF
	RET

JOIN_CAPACITY_OK:
	; 3. Append lower line (SPLIT_LINE_TEMP) to upper line (LOAD_LINE_TEMP + len_1)
	LD	HL,LOAD_LINE_TEMP
	LD	A,(JOIN_COL_SAVED)
	LD	E,A
	LD	D,0
	ADD	HL,DE			; HL = pointer to null in LOAD_LINE_TEMP
	LD	DE,SPLIT_LINE_TEMP
JOIN_APPEND_LOOP:
	LD	A,(DE)
	LD	(HL),A
	INC	DE
	INC	HL
	OR	A
	JR	NZ,JOIN_APPEND_LOOP

	; 4. Write merged line back to Far RAM at (JOIN_DOC_LINE)
	LD	BC,(JOIN_DOC_LINE)
	LD	HL,LOAD_LINE_TEMP
	CALL	WRITE_FAR_LINE

	; 5. Free lower line's slot (JOIN_DOC_LINE + 1)
	LD	HL,(JOIN_DOC_LINE)
	INC	HL			; HL = lower line index (P)
	ADD	HL,HL			; * 2
	LD	BC,DOC_LINE_SLOTS
	ADD	HL,BC
	LD	E,(HL)
	INC	HL
	LD	D,(HL)			; DE = freed slot ID
	EX	DE,HL			; HL = freed slot ID
	CALL	FREE_SLOT

	; 6. Decrement DOC_TOTAL_LINES
	LD	HL,(DOC_TOTAL_LINES)
	DEC	HL
	LD	(DOC_TOTAL_LINES),HL

	; 7. Shift DOC_LINE_SLOTS from JOIN_DOC_LINE + 2 upwards to JOIN_DOC_LINE + 1
	; Number of entries to shift: W = DOC_TOTAL_LINES - (JOIN_DOC_LINE + 1)
	LD	HL,(DOC_TOTAL_LINES)	; New total lines
	LD	DE,(JOIN_DOC_LINE)
	INC	DE			; DE = P = JOIN_DOC_LINE + 1
	AND	A
	SBC	HL,DE			; HL = W = DOC_TOTAL_LINES - P
	JR	Z,JOIN_SHIFT_DONE
	JR	C,JOIN_SHIFT_DONE

	; Words W > 0: shift using LDIR
	ADD	HL,HL
	LD	B,H
	LD	C,L			; BC = byte count

	; Destination: DE = DOC_LINE_SLOTS + P * 2
	EX	DE,HL			; HL = P
	ADD	HL,HL			; HL = P * 2
	LD	DE,DOC_LINE_SLOTS
	ADD	HL,DE
	EX	DE,HL			; DE = destination

	; Source: HL = destination + 2
	LD	L,E
	LD	H,D
	INC	HL
	INC	HL

	LDIR

JOIN_SHIFT_DONE:
	CALL	RELOAD_CACHE_WINDOW_FORCE

	LD	A,(JOIN_COL_SAVED)
	LD	B,A			; B = join column offset
	OR	A			; Clear Carry = success!
	RET

;------------------------------------------------------------------------------
; Line Insertion & Splitting at (CUR_DOC_ROW, CUR_COL) - Enter Key Handling
;------------------------------------------------------------------------------
DO_INSERT_LINE:
	; Check max document lines (3584)
	LD	HL,(DOC_TOTAL_LINES)
	LD	DE,MAX_DOC_LINES
	LD	A,H
	CP	D
	JR	C,INS_CAP_OK
	JR	NZ,INS_FAIL
	LD	A,L
	CP	E
	JR	NC,INS_FAIL

INS_CAP_OK:
	; Allocate slot for new line
	CALL	ALLOC_SLOT		; HL = new_slot_id (Carry = 1 on error)
	JR	C,INS_FAIL
	PUSH	HL			; Save new_slot_id

	; Flush dirty cache to Far RAM first
	CALL	FLUSH_DIRTY_CACHE

	; Shift DOC_LINE_SLOTS downwards from CUR_DOC_ROW + 1 to DOC_TOTAL_LINES - 1
	; Number of entries to shift: W = DOC_TOTAL_LINES - (CUR_DOC_ROW + 1)
	LD	HL,(DOC_TOTAL_LINES)
	LD	DE,(CUR_DOC_ROW)
	INC	DE			; DE = P = CUR_DOC_ROW + 1
	AND	A
	SBC	HL,DE			; HL = W = DOC_TOTAL_LINES - P
	JR	Z,NO_SLOT_SHIFT_DOWN
	JR	C,NO_SLOT_SHIFT_DOWN

	; Words W > 0: shift using LDDR
	ADD	HL,HL
	LD	B,H
	LD	C,L			; BC = byte count

	; Destination last byte: DE = DOC_LINE_SLOTS + N * 2 + 1
	LD	HL,(DOC_TOTAL_LINES)
	ADD	HL,HL
	LD	DE,DOC_LINE_SLOTS + 1
	ADD	HL,DE
	EX	DE,HL			; DE = destination last byte

	; Source last byte: HL = DE - 2
	LD	L,E
	LD	H,D
	DEC	HL
	DEC	HL

	LDDR

NO_SLOT_SHIFT_DOWN:
	; Store new_slot_id into DOC_LINE_SLOTS[CUR_DOC_ROW + 1]
	POP	DE			; DE = new_slot_id
	LD	HL,(CUR_DOC_ROW)
	INC	HL			; HL = CUR_DOC_ROW + 1
	ADD	HL,HL			; * 2
	LD	BC,DOC_LINE_SLOTS
	ADD	HL,BC
	LD	(HL),E
	INC	HL
	LD	(HL),D

	; Read current line at CUR_DOC_ROW into LOAD_LINE_TEMP
	LD	BC,(CUR_DOC_ROW)
	LD	DE,LOAD_LINE_TEMP
	CALL	READ_FAR_LINE
	JR	DO_SPLIT_TEXT

INS_FAIL:
	RET

DO_SPLIT_TEXT:

	; Clear SPLIT_LINE_TEMP
	LD	HL,SPLIT_LINE_TEMP
	LD	DE,SPLIT_LINE_TEMP+1
	LD	BC,127
	LD	(HL),0
	LDIR

	; Split LOAD_LINE_TEMP at CUR_COL
	LD	HL,LOAD_LINE_TEMP
	LD	A,(CUR_COL)
	LD	E,A
	LD	D,0
	ADD	HL,DE			; HL = split point in LOAD_LINE_TEMP

	; Copy text from split point into SPLIT_LINE_TEMP
	LD	DE,SPLIT_LINE_TEMP
SPLIT_COPY_REMAINDER:
	LD	A,(HL)
	OR	A
	JR	Z,SPLIT_COPY_REMAINDER_DONE
	LD	(DE),A
	LD	(HL),0			; Truncate current line at split point
	INC	HL
	INC	DE
	JR	SPLIT_COPY_REMAINDER

SPLIT_COPY_REMAINDER_DONE:
	; Write truncated current line back to CUR_DOC_ROW
	LD	BC,(CUR_DOC_ROW)
	LD	HL,LOAD_LINE_TEMP
	CALL	WRITE_FAR_LINE

	; Write split remainder to CUR_DOC_ROW + 1
	INC	BC
	LD	HL,SPLIT_LINE_TEMP
	CALL	WRITE_FAR_LINE

	; Increment DOC_TOTAL_LINES
	LD	HL,(DOC_TOTAL_LINES)
	INC	HL
	LD	(DOC_TOTAL_LINES),HL

	; Advance cursor to CUR_DOC_ROW + 1, Col 0
	LD	HL,(CUR_DOC_ROW)
	INC	HL
	LD	(CUR_DOC_ROW),HL
	XOR	A
	LD	(CUR_COL),A
	LD	(TARGET_COL),A

	; Check if scrolled past bottom of screen window
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(TOP_DOC_ROW)
	AND	A
	SBC	HL,DE
	LD	A,(ACTIVE_ROWS)
	DEC	A
	DEC	A
	CP	L
	JR	NC,SPLIT_NO_SCROLL

	LD	HL,(TOP_DOC_ROW)
	INC	HL
	LD	(TOP_DOC_ROW),HL

SPLIT_NO_SCROLL:
	CALL	RELOAD_CACHE_WINDOW_FORCE
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
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
; File Loading: Reads files directly into Far RAM banks
;------------------------------------------------------------------------------
LOAD_FILE:
	LD	DE,DEFAULT_DMA
	LD	C,26			; BDOS Set DMA
	CALL	BDOS_ENTRY

	; Zero FCB extent, s1, s2, rc, and record bytes
	LD	HL,WORK_FCB+12
	LD	(HL),0
	LD	DE,WORK_FCB+13
	LD	BC,23
	LDIR

	; Check if filename is empty / spaces
	LD	A,(WORK_FCB+1)
	CP	' '
	JP	Z,LOAD_FILE_NOT_FOUND
	OR	A
	JP	Z,LOAD_FILE_NOT_FOUND

	LD	DE,WORK_FCB
	LD	C,15			; BDOS Open File
	CALL	BDOS_ENTRY
	CP	0FFH
	JP	Z,LOAD_FILE_NOT_FOUND

	XOR	A
	LD	(WORK_FCB+32),A		; Clear current record (CR)
	LD	(SEEN_CR),A
	LD	HL,0
	LD	(DOC_TOTAL_LINES),HL
	LD	(CUR_DOC_ROW),HL
	LD	(TOP_DOC_ROW),HL
	LD	(CACHE_START_ROW),HL
	LD	(CACHE_DIRTY),A

	CALL	INIT_SLOT_SYSTEM

	; Clear LOAD_LINE_TEMP
	CALL	CLEAR_LOAD_TEMP
	LD	B,0			; Line character counter

READ_SECTOR_LOOP:
	PUSH	BC			; Preserve line character count B
	LD	DE,WORK_FCB
	LD	C,20			; BDOS Read Next Record
	CALL	BDOS_ENTRY
	POP	BC			; Restore line character count B
	OR	A
	JP	NZ,FILE_LOAD_DONE

	LD	HL,DEFAULT_DMA
	LD	C,128			; 128 bytes per sector

PARSE_BYTE_LOOP:
	LD	A,(HL)
	OR	A			; NULL padding at EOF
	JP	Z,FILE_LOAD_DONE

	CP	26			; CP/M EOF (^Z)
	JP	Z,FILE_LOAD_DONE

	CP	13			; CR
	JR	Z,HANDLE_CR

	CP	10			; LF
	JR	Z,HANDLE_LF

	; Normal character (including 0x09 Tab): store in LOAD_LINE_TEMP
	XOR	A
	LD	(SEEN_CR),A

	LD	A,B
	CP	MAX_LINE_STRIDE-2
	JR	NC,SKIP_LINE_OVERFLOW

	LD	A,(HL)
	PUSH	HL
	LD	HL,LOAD_LINE_TEMP
	LD	E,B
	LD	D,0
	ADD	HL,DE
	LD	(HL),A
	POP	HL
	INC	B

SKIP_LINE_OVERFLOW:
	JR	NEXT_BYTE_IN_SECTOR

HANDLE_CR:
	LD	A,1
	LD	(SEEN_CR),A
	LD	A,FMT_CPM
	LD	(SAVE_FORMAT),A
	JR	NEXT_BYTE_IN_SECTOR

HANDLE_LF:
	PUSH	HL			; Preserve sector buffer pointer HL!

	; If no preceding CR, detect Linux format
	LD	A,(SEEN_CR)
	OR	A
	JR	NZ,LF_AFTER_CR
	LD	A,FMT_LINUX
	LD	(SAVE_FORMAT),A

LF_AFTER_CR:
	XOR	A
	LD	(SEEN_CR),A

	; Terminate line in LOAD_LINE_TEMP
	LD	HL,LOAD_LINE_TEMP
	LD	E,B
	LD	D,0
	ADD	HL,DE
	LD	(HL),0

	; Allocate slot and write line to Far RAM
	PUSH	BC
	CALL	APPEND_LINE_SLOT
	LD	HL,LOAD_LINE_TEMP
	CALL	WRITE_FAR_SLOT

	LD	HL,(DOC_TOTAL_LINES)
	INC	HL
	LD	(DOC_TOTAL_LINES),HL
	POP	BC

	; Reset line buffer
	CALL	CLEAR_LOAD_TEMP
	LD	B,0

	POP	HL			; Restore sector buffer pointer HL!

	; Check max lines (3584 = 14 banks * 256)
	PUSH	HL
	LD	HL,(DOC_TOTAL_LINES)
	LD	A,H
	CP	00EH
	POP	HL
	JP	NC,FILE_LOAD_DONE

NEXT_BYTE_IN_SECTOR:
	INC	HL
	DEC	C
	JP	NZ,PARSE_BYTE_LOOP
	JP	READ_SECTOR_LOOP

FILE_LOAD_DONE:
	; If remaining characters in buffer, flush final line
	LD	A,B
	OR	A
	JP	Z,LOAD_FINISH

	LD	HL,LOAD_LINE_TEMP
	LD	E,B
	LD	D,0
	ADD	HL,DE
	LD	(HL),0

	CALL	APPEND_LINE_SLOT
	LD	HL,LOAD_LINE_TEMP
	CALL	WRITE_FAR_SLOT

	LD	HL,(DOC_TOTAL_LINES)
	INC	HL
	LD	(DOC_TOTAL_LINES),HL

LOAD_FINISH:
	; Ensure at least 1 line exists
	LD	HL,(DOC_TOTAL_LINES)
	LD	A,H
	OR	L
	JP	NZ,LOAD_INIT_CACHE
	INC	HL
	LD	(DOC_TOTAL_LINES),HL
	; Write empty line to line 0 in Far RAM
	CALL	CLEAR_LOAD_TEMP
	CALL	APPEND_LINE_SLOT
	LD	HL,LOAD_LINE_TEMP
	CALL	WRITE_FAR_SLOT

LOAD_INIT_CACHE:
	XOR	A
	LD	(BLOCK_ACTIVE),A
	CALL	RELOAD_CACHE_WINDOW_FORCE
	OR	A			; Carry = 0 (success)
	RET

LOAD_FILE_NOT_FOUND:
	SCF				; Carry = 1 (error: file not found)
	RET

;------------------------------------------------------------------------------
; Initialize Empty Document into Far RAM Banks (1 empty line)
;------------------------------------------------------------------------------
INIT_EMPTY_DOCUMENT:
	CALL	INIT_SLOT_SYSTEM
	CALL	ALLOC_SLOT		; HL = 0
	LD	(DOC_LINE_SLOTS),HL	; DOC_LINE_SLOTS[0] = 0

	LD	HL,1
	LD	(DOC_TOTAL_LINES),HL
	LD	HL,0
	LD	(CUR_DOC_ROW),HL
	LD	(TOP_DOC_ROW),HL
	LD	(CACHE_START_ROW),HL
	XOR	A
	LD	(CUR_COL),A
	LD	(TARGET_COL),A
	LD	(CACHE_DIRTY),A
	LD	(BLOCK_ACTIVE),A

	; Write empty line to line 0 in Far RAM
	CALL	CLEAR_LOAD_TEMP
	LD	HL,LOAD_LINE_TEMP
	LD	BC,0
	CALL	WRITE_FAR_SLOT

	; Invalidate and force reload local cache window
	CALL	RELOAD_CACHE_WINDOW_FORCE
	RET

;------------------------------------------------------------------------------
; Open File Screen with Sorted Directory Listing & Pagination
;------------------------------------------------------------------------------
DO_OPEN_FILE_UI:
	; Initialize active directory drive from default disk or WORK_FCB
	CALL	INIT_DIR_DRIVE

	; Clear INPUT_FILENAME_BUF for initial prompt
	XOR	A
	LD	(INPUT_BUF_LEN),A
	LD	(INPUT_FILENAME_BUF),A

REFRESH_OPEN_DIR:
	; 1. Collect Directory Entries from CURRENT_DIR_DRIVE (with Bit-7 strip & dup filter)
	CALL	COLLECT_DIR_ENTRIES

	; 2. Sort Directory Entries Alphabetically
	CALL	SORT_DIR_ENTRIES

	; 3. Calculate Total Pages (48 files per page: 12 rows x 4 cols)
	XOR	A
	LD	(DIR_PAGE_INDEX),A

	LD	A,(DIR_FILE_COUNT)
	OR	A
	JR	NZ,CALC_PAGES
	LD	A,1
	LD	(DIR_PAGE_COUNT),A
	JR	RENDER_OPEN_PAGE

CALC_PAGES:
	DEC	A			; A = N - 1
	LD	B,0			; B = quotient
DIV_48_LOOP:
	CP	48
	JR	C,DIV_48_DONE
	SUB	48
	INC	B
	JR	DIV_48_LOOP
DIV_48_DONE:
	INC	B			; Total pages = quotient + 1
	LD	A,B
	LD	(DIR_PAGE_COUNT),A

RENDER_OPEN_PAGE:
	CALL	TERM_INIT
	LD	DE,STR_DIR_TITLE
	CALL	PRINT_STR

	; Display Directory Entries for Current Page
	CALL	DISPLAY_DIR_PAGE

	; Display Open Prompt & Page Indicator
	CALL	DISPLAY_OPEN_PROMPT

	; Read Filename Input (echoes prefilled string if non-empty, e.g. "A:")
	CALL	READ_FILENAME_INPUT_PREFILLED
	JR	C,CHECK_PAGING_OR_CANCEL

	; Check if user typed a drive specification (e.g. "A:")
	CALL	CHECK_DRIVE_SWITCH
	JR	C,HANDLE_OPEN_DRIVE_SWITCH

DO_PARSE_AND_LOAD:
	; Backup current WORK_FCB to DIR_TEMP_FCB in case open fails
	LD	HL,WORK_FCB
	LD	DE,DIR_TEMP_FCB
	LD	BC,36
	LDIR

	; User entered a filename in INPUT_FILENAME_BUF: parse into WORK_FCB
	LD	DE,INPUT_FILENAME_BUF
	CALL	PARSE_FILENAME_TO_FCB

	; Load the file into Far RAM
	CALL	LOAD_FILE
	JR	C,OPEN_FILE_NOT_FOUND

	; Reset stack and enter editor mode
	LD	SP,LOCAL_STACK
	LD	A,1
	LD	(HAS_FILE_ARG),A
	LD	(IN_EDITOR_MODE),A
	LD	HL,0
	LD	(CUR_DOC_ROW),HL
	LD	(TOP_DOC_ROW),HL
	XOR	A
	LD	(CUR_COL),A
	LD	(TARGET_COL),A

	CALL	TERM_INIT
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	JP	MAIN_LOOP

HANDLE_OPEN_DRIVE_SWITCH:
	; A = new drive (1..16)
	LD	(CURRENT_DIR_DRIVE),A
	ADD	A,'A'-1
	LD	(STR_DIR_DRIVE_CHAR),A
	JP	REFRESH_OPEN_DIR

OPEN_FILE_NOT_FOUND:
	; Restore previous WORK_FCB from DIR_TEMP_FCB
	LD	HL,DIR_TEMP_FCB
	LD	DE,WORK_FCB
	LD	BC,36
	LDIR

	; Display inline "  File not found" right after bad filename
	LD	DE,STR_FNF_INLINE
	CALL	PRINT_STR

	; Set flag that "  File not found" is currently visible
	LD	A,1
	LD	(SHOWING_FNF_MSG),A

	; Resume input loop without blanking filename in text box
	CALL	RESUME_FILENAME_INPUT
	JR	C,CHECK_PAGING_OR_CANCEL

	; Check if user edited input to a drive specification (e.g. "B:")
	CALL	CHECK_DRIVE_SWITCH
	JR	C,HANDLE_OPEN_DRIVE_SWITCH

	JP	DO_PARSE_AND_LOAD

CHECK_PAGING_OR_CANCEL:
	; A = return code: 0 = Cancel (ESC), 1 = Next Page (PgDn), 3 = Prev Page (PgUp)
	CP	1
	JR	Z,DO_NEXT_PAGE
	CP	3
	JR	Z,DO_PREV_PAGE
	RET				; Cancelled -> return to splash

DO_PREV_PAGE:
	LD	A,(DIR_PAGE_INDEX)
	OR	A
	JR	Z,DO_PREV_PAGE_WRAP
	DEC	A
	JR	SET_NEXT_PAGE
DO_PREV_PAGE_WRAP:
	LD	A,(DIR_PAGE_COUNT)
	DEC	A
	JR	SET_NEXT_PAGE

DO_NEXT_PAGE:
	LD	A,(DIR_PAGE_INDEX)
	INC	A
	LD	HL,DIR_PAGE_COUNT
	CP	(HL)
	JR	C,SET_NEXT_PAGE
	XOR	A			; Wrap around to page 0
SET_NEXT_PAGE:
	LD	(DIR_PAGE_INDEX),A
	JP	RENDER_OPEN_PAGE

;------------------------------------------------------------------------------
; Show Editor Mode Keys Screen (Ctrl+K)
; Displays summary of all SE editor keys and waits for any key to return.
;------------------------------------------------------------------------------
SHOW_HELP_KEYS_UI:
	LD	DE,STR_HELP_SCREEN
	CALL	PRINT_STR
	CALL	GET_KEY
	RET

;------------------------------------------------------------------------------
; Save File Screen with Sorted Directory Listing, Pre-filling & Overwrite Check
;------------------------------------------------------------------------------
DO_SAVE_FILE_UI:
	LD	A,1
	LD	(IS_SAVE_UI),A
	CALL	DO_SAVE_FILE_UI_IMPL
	XOR	A
	LD	(IS_SAVE_UI),A
	RET

DO_SAVE_FILE_UI_IMPL:
	; Initialize active directory drive from default disk or WORK_FCB
	CALL	INIT_DIR_DRIVE

	; Pre-fill filename if known (HAS_FILE_ARG == 1)
	CALL	FCB_TO_FILENAME_STR

REFRESH_SAVE_DIR:
	; 1. Collect Directory Entries from CURRENT_DIR_DRIVE
	CALL	COLLECT_DIR_ENTRIES

	; 2. Sort Directory Entries Alphabetically
	CALL	SORT_DIR_ENTRIES

	; 3. Calculate Total Pages (48 files per page: 12 rows x 4 cols)
	XOR	A
	LD	(DIR_PAGE_INDEX),A

	LD	A,(DIR_FILE_COUNT)
	OR	A
	JR	NZ,CALC_SAVE_PAGES
	LD	A,1
	LD	(DIR_PAGE_COUNT),A
	JR	RENDER_SAVE_PAGE

CALC_SAVE_PAGES:
	DEC	A			; A = N - 1
	LD	B,0
DIV_48_SAVE_LOOP:
	CP	48
	JR	C,DIV_48_SAVE_DONE
	SUB	48
	INC	B
	JR	DIV_48_SAVE_LOOP
DIV_48_SAVE_DONE:
	INC	B
	LD	A,B
	LD	(DIR_PAGE_COUNT),A

RENDER_SAVE_PAGE:
	CALL	TERM_INIT
	LD	DE,STR_SAVE_TITLE
	CALL	PRINT_STR

	; Display Directory Entries for Current Page
	CALL	DISPLAY_DIR_PAGE

	; Display Save Prompt & Page Indicator
	CALL	DISPLAY_SAVE_PROMPT

	; Read Filename Input (with prefilled string echoed)
	CALL	READ_FILENAME_INPUT_PREFILLED
	JR	C,CHECK_SAVE_PAGING_OR_CANCEL

	; Check if user typed a drive specification (e.g. "A:")
	CALL	CHECK_DRIVE_SWITCH
	JR	C,HANDLE_SAVE_DRIVE_SWITCH

	; User entered/confirmed a filename in INPUT_FILENAME_BUF:
	; Save current WORK_FCB to DIR_TEMP_FCB (36 bytes)
	LD	HL,WORK_FCB
	LD	DE,DIR_TEMP_FCB
	LD	BC,36
	LDIR

	; Parse entered filename into WORK_FCB
	CALL	PARSE_FILENAME_TO_FCB

	; Check if file already exists on disk
	CALL	CHECK_FILE_EXISTS
	JR	NC,DO_ACTUAL_SAVE	; Does not exist -> save directly

	; File already exists! Prompt warning
	LD	DE,STR_OVERWRITE_WARN
	CALL	PRINT_STR

OVERWRITE_KEY_LOOP:
	CALL	GET_KEY
	CP	'y'
	JR	Z,DO_OVERWRITE_CONFIRMED
	CP	'Y'
	JR	Z,DO_OVERWRITE_CONFIRMED

	; Any other key cancels overwrite: restore original WORK_FCB
	CALL	PUTC			; Echo typed char
	LD	HL,DIR_TEMP_FCB
	LD	DE,WORK_FCB
	LD	BC,36
	LDIR

	LD	DE,STR_SAVE_CANCELLED
	CALL	PRINT_STR
	CALL	DELAY_BRIEF
	RET

DO_OVERWRITE_CONFIRMED:
	CALL	PUTC			; Echo 'y'

DO_ACTUAL_SAVE:
	; Save the file from Far RAM to disk
	CALL	SAVE_FILE

	; Mark filename as known and saved
	LD	A,1
	LD	(HAS_FILE_ARG),A
	RET

HANDLE_SAVE_DRIVE_SWITCH:
	; A = new drive (1..16)
	LD	(CURRENT_DIR_DRIVE),A
	ADD	A,'A'-1
	LD	(STR_SAVE_DRIVE_CHAR),A
	JP	REFRESH_SAVE_DIR

CHECK_SAVE_PAGING_OR_CANCEL:
	; A = return code: 0 = Cancel (ESC), 1 = Next Page (PgDn), 2 = Format Toggled (Ctrl-F), 3 = Prev Page (PgUp)
	CP	2
	JP	Z,RENDER_SAVE_PAGE	; Redraw save page with new format and prefilled input
	CP	1
	JR	Z,DO_SAVE_NEXT_PAGE
	CP	3
	JR	Z,DO_SAVE_PREV_PAGE
	RET				; Cancelled -> return

DO_SAVE_PREV_PAGE:
	LD	A,(DIR_PAGE_INDEX)
	OR	A
	JR	Z,DO_SAVE_PREV_WRAP
	DEC	A
	JR	SET_SAVE_NEXT_PAGE
DO_SAVE_PREV_WRAP:
	LD	A,(DIR_PAGE_COUNT)
	DEC	A
	JR	SET_SAVE_NEXT_PAGE

DO_SAVE_NEXT_PAGE:
	LD	A,(DIR_PAGE_INDEX)
	INC	A
	LD	HL,DIR_PAGE_COUNT
	CP	(HL)
	JR	C,SET_SAVE_NEXT_PAGE
	XOR	A			; Wrap around to page 0
SET_SAVE_NEXT_PAGE:
	LD	(DIR_PAGE_INDEX),A
	JP	RENDER_SAVE_PAGE

;------------------------------------------------------------------------------
; Check if file in WORK_FCB already exists on disk
; Returns: Carry = 1 if file exists, Carry = 0 if file does not exist
;------------------------------------------------------------------------------
CHECK_FILE_EXISTS:
	; Set DMA address to RAW_SECTOR_BUF
	LD	DE,RAW_SECTOR_BUF
	LD	C,26			; BDOS Set DMA
	CALL	BDOS_ENTRY

	; Copy WORK_FCB to RAW_TEST_FCB
	LD	HL,WORK_FCB
	LD	DE,RAW_TEST_FCB
	LD	BC,36
	LDIR

	; Clear extent and record bytes (bytes 12..35) in RAW_TEST_FCB
	LD	HL,RAW_TEST_FCB+12
	LD	(HL),0
	LD	DE,RAW_TEST_FCB+13
	LD	BC,23
	LDIR

	; Try to open file (BDOS 15)
	LD	DE,RAW_TEST_FCB
	LD	C,15
	CALL	BDOS_ENTRY
	CP	0FFH
	JR	Z,FILE_NOT_EXISTS

	; File exists! Close it (BDOS 16)
	LD	DE,RAW_TEST_FCB
	LD	C,16
	CALL	BDOS_ENTRY
	SCF				; Carry = 1 (file exists)
	RET

FILE_NOT_EXISTS:
	OR	A			; Carry = 0 (file does not exist)
	RET

;------------------------------------------------------------------------------
; Initialize CURRENT_DIR_DRIVE and title strings
; If WORK_FCB has an explicit drive, uses it; otherwise queries BDOS 25.
;------------------------------------------------------------------------------
INIT_DIR_DRIVE:
	LD	A,(WORK_FCB)
	OR	A
	JR	NZ,IDD_USE_FCB
	LD	C,25			; BDOS Return Current Disk
	CALL	BDOS_ENTRY
	INC	A			; 0..15 -> 1..16
IDD_USE_FCB:
	LD	(CURRENT_DIR_DRIVE),A
	ADD	A,'A'-1
	LD	(STR_DIR_DRIVE_CHAR),A
	LD	(STR_SAVE_DRIVE_CHAR),A
	RET

;------------------------------------------------------------------------------
; Check if INPUT_FILENAME_BUF contains a drive specification (e.g. "A:")
; Returns:
;   Carry = 1 -> Drive switch requested; A = drive code 1..16 (1=A, 2=B, etc.)
;   Carry = 0 -> Not a drive switch
;------------------------------------------------------------------------------
CHECK_DRIVE_SWITCH:
	LD	A,(INPUT_BUF_LEN)
	CP	2
	RET	NZ			; Not length 2 -> Carry = 0

	LD	A,(INPUT_FILENAME_BUF+1)
	CP	':'
	JR	NZ,CDS_NO		; Second character not ':' -> Carry = 0

	LD	A,(INPUT_FILENAME_BUF)
	CALL	TO_UPPER
	CP	'A'
	JR	C,CDS_NO
	CP	'P'+1
	JR	NC,CDS_NO

	; Valid drive letter 'A'..'P'
	LD	(INPUT_FILENAME_BUF),A	; Normalize buffer to uppercase letter
	SUB	'A'-1			; 'A' -> 1, 'B' -> 2, etc.
	SCF				; Carry = 1
	RET

CDS_NO:
	OR	A			; Carry = 0
	RET

;------------------------------------------------------------------------------
; Convert WORK_FCB to null-terminated ASCII string in INPUT_FILENAME_BUF
; Sets INPUT_BUF_LEN accordingly.
; If HAS_FILE_ARG == 0, clears buffer (length 0).
;------------------------------------------------------------------------------
FCB_TO_FILENAME_STR:
	LD	A,(HAS_FILE_ARG)
	OR	A
	JR	NZ,DO_CONVERT_FCB

	; No file argument -> empty buffer
	XOR	A
	LD	(INPUT_BUF_LEN),A
	LD	HL,INPUT_FILENAME_BUF
	LD	(HL),0
	RET

DO_CONVERT_FCB:
	LD	DE,INPUT_FILENAME_BUF
	LD	C,0			; C = length counter

	; Check drive (WORK_FCB+0)
	LD	A,(WORK_FCB)
	OR	A
	JR	Z,FCB_NO_DRIVE
	; Explicit drive 1..16
	ADD	A,'A'-1
	LD	(DE),A
	INC	DE
	INC	C
	LD	A,':'
	LD	(DE),A
	INC	DE
	INC	C

FCB_NO_DRIVE:
	; Copy up to 8 characters of filename (WORK_FCB+1..8)
	LD	HL,WORK_FCB+1
	LD	B,8
FCB_NAME_LOOP:
	LD	A,(HL)
	CP	' '
	JR	Z,FCB_NAME_DONE
	OR	A
	JR	Z,FCB_NAME_DONE
	LD	(DE),A
	INC	DE
	INC	HL
	INC	C
	DJNZ	FCB_NAME_LOOP

FCB_NAME_DONE:
	; Check extension (WORK_FCB+9..11)
	LD	HL,WORK_FCB+9
	LD	A,(HL)
	CP	' '
	JR	Z,FCB_CONV_DONE
	OR	A
	JR	Z,FCB_CONV_DONE

	; Has extension: add '.'
	LD	A,'.'
	LD	(DE),A
	INC	DE
	INC	C

	LD	B,3
FCB_EXT_LOOP:
	LD	A,(HL)
	CP	' '
	JR	Z,FCB_CONV_DONE
	OR	A
	JR	Z,FCB_CONV_DONE
	LD	(DE),A
	INC	DE
	INC	HL
	INC	C
	DJNZ	FCB_EXT_LOOP

FCB_CONV_DONE:
	XOR	A
	LD	(DE),A			; Null-terminate
	LD	A,C
	LD	(INPUT_BUF_LEN),A
	RET

;------------------------------------------------------------------------------
; Display Save Prompt & Page Indicator with Format Info
;------------------------------------------------------------------------------
DISPLAY_SAVE_PROMPT:
	LD	A,(DIR_PAGE_COUNT)
	CP	2
	JR	C,DISP_SINGLE_SAVE_PROMPT

	; Multi-page prompt
	LD	DE,STR_SAVE_PAGE_PREFIX
	CALL	PRINT_STR

	LD	A,(DIR_PAGE_INDEX)
	INC	A
	LD	L,A
	LD	H,0
	CALL	PRINT_DEC_WORD

	LD	DE,STR_PAGE_MID
	CALL	PRINT_STR

	LD	A,(DIR_PAGE_COUNT)
	LD	L,A
	LD	H,0
	CALL	PRINT_DEC_WORD

	LD	DE,STR_SAVE_PAGE_SUFFIX
	CALL	PRINT_STR
	CALL	PRINT_SAVE_FMT_INFO
	LD	DE,STR_SAVE_PAGE_PROMPT
	CALL	PRINT_STR
	RET

DISP_SINGLE_SAVE_PROMPT:
	LD	DE,STR_SAVE_SEP_LINE
	CALL	PRINT_STR
	CALL	PRINT_SAVE_FMT_INFO
	LD	DE,STR_SAVE_ENTER_PROMPT
	CALL	PRINT_STR
	RET

PRINT_SAVE_FMT_INFO:
	LD	DE,STR_SAVE_FMT_PREFIX
	CALL	PRINT_STR
	LD	A,(SAVE_FORMAT)
	CP	FMT_CPM
	JR	NZ,PRINT_SAVE_FMT_LINUX
	LD	DE,STR_SAVE_FMT_CPM
	CALL	PRINT_STR
	JR	PRINT_SAVE_FMT_END
PRINT_SAVE_FMT_LINUX:
	LD	DE,STR_SAVE_FMT_LINUX
	CALL	PRINT_STR
PRINT_SAVE_FMT_END:
	LD	DE,STR_SAVE_FMT_SUFFIX
	CALL	PRINT_STR
	RET

;------------------------------------------------------------------------------
; Brief delay (~0.5s) for reading status messages
;------------------------------------------------------------------------------
DELAY_BRIEF:
	PUSH	BC
	LD	B,0
DELAY_OUTER:
	LD	C,0
DELAY_INNER:
	DEC	C
	JR	NZ,DELAY_INNER
	DJNZ	DELAY_OUTER
	POP	BC
	RET

;------------------------------------------------------------------------------
; Collect Directory Entries from CP/M Default Drive into DIR_NAMES_BUF
; - Strips Bit 7 (AND 07FH) on all characters
; - Works across standard CP/M, host/Linux drives, and FAT filesystems
; - Filters duplicate multi-extent entries via CHECK_DIR_DUPLICATE
;------------------------------------------------------------------------------
COLLECT_DIR_ENTRIES:
	XOR	A
	LD	(DIR_FILE_COUNT),A

	; Set DMA address to RAW_SECTOR_BUF (128 bytes)
	LD	DE,RAW_SECTOR_BUF
	LD	C,26			; BDOS Set DMA
	CALL	BDOS_ENTRY

	; Prepare DIR_SEARCH_FCB: Drive = CURRENT_DIR_DRIVE, 11 '?' wildcards, rest 0
	LD	HL,DIR_SEARCH_FCB
	LD	A,(CURRENT_DIR_DRIVE)
	LD	(HL),A			; Active directory drive (1=A, 2=B, etc.)
	INC	HL
	LD	B,11
SET_SEARCH_QM:
	LD	(HL),'?'
	INC	HL
	DJNZ	SET_SEARCH_QM
	LD	B,24
SET_SEARCH_ZEROS:
	LD	(HL),0
	INC	HL
	DJNZ	SET_SEARCH_ZEROS

	; Search First (BDOS 17)
	LD	DE,DIR_SEARCH_FCB
	LD	C,17
	CALL	BDOS_ENTRY
	CP	0FFH
	RET	Z			; No files on drive

DIR_COLLECT_LOOP:
	; A = directory entry index (0..3) in RAW_SECTOR_BUF
	; Calculate entry address: RAW_SECTOR_BUF + (A * 32)
	LD	L,A
	LD	H,0
	ADD	HL,HL			; *2
	ADD	HL,HL			; *4
	ADD	HL,HL			; *8
	ADD	HL,HL			; *16
	ADD	HL,HL			; *32
	LD	DE,RAW_SECTOR_BUF
	ADD	HL,DE			; HL = pointer to 32-byte directory entry

	; Check user number / deleted status (byte 0):
	LD	A,(HL)
	CP	0E5H
	JR	Z,DIR_NEXT_ENTRY	; Deleted entry
	CP	020H
	JR	NC,DIR_NEXT_ENTRY	; Non-user entry (> 31)

	; Check that filename is not blank (first char != space and != 0, with bit 7 stripped)
	INC	HL			; HL = pointer to filename (bytes 1..8)
	LD	A,(HL)
	AND	07FH
	CP	' '
	JR	Z,DIR_NEXT_ENTRY
	OR	A
	JR	Z,DIR_NEXT_ENTRY

	; Format entry into DIR_TEMP_ENTRY (13 bytes: 8 name + '.' + 3 ext + 0)
	LD	DE,DIR_TEMP_ENTRY
	LD	B,8
COPY_NAME_TEMP:
	LD	A,(HL)
	AND	07FH
	LD	(DE),A
	INC	HL
	INC	DE
	DJNZ	COPY_NAME_TEMP

	LD	A,'.'
	LD	(DE),A
	INC	DE

	LD	B,3
COPY_EXT_TEMP:
	LD	A,(HL)
	AND	07FH
	LD	(DE),A
	INC	HL
	INC	DE
	DJNZ	COPY_EXT_TEMP

	XOR	A
	LD	(DE),A

	; Check if this filename is already in DIR_NAMES_BUF (duplicate extent filter)
	CALL	CHECK_DIR_DUPLICATE
	JR	C,DIR_NEXT_ENTRY	; Already collected -> skip duplicate

	; Not a duplicate: append DIR_TEMP_ENTRY into DIR_NAMES_BUF
	LD	A,(DIR_FILE_COUNT)
	LD	L,A
	LD	H,0
	; HL = A * 13
	LD	D,H
	LD	E,L			; DE = A
	ADD	HL,HL			; *2
	ADD	HL,HL			; *4
	ADD	HL,DE			; *5
	ADD	HL,HL			; *10
	ADD	HL,DE			; *11
	ADD	HL,DE			; *12
	ADD	HL,DE			; *13
	LD	DE,DIR_NAMES_BUF
	ADD	HL,DE
	EX	DE,HL			; DE = Destination in DIR_NAMES_BUF

	LD	HL,DIR_TEMP_ENTRY
	LD	BC,13
	LDIR

	; Increment DIR_FILE_COUNT
	LD	A,(DIR_FILE_COUNT)
	INC	A
	LD	(DIR_FILE_COUNT),A
	CP	255			; Max 255 entries
	RET	NC

DIR_NEXT_ENTRY:
	; Search Next (BDOS 18)
	LD	DE,DIR_SEARCH_FCB
	LD	C,18
	CALL	BDOS_ENTRY
	CP	0FFH
	RET	Z
	JR	DIR_COLLECT_LOOP

;------------------------------------------------------------------------------
; Check if DIR_TEMP_ENTRY matches any already collected entry in DIR_NAMES_BUF
; Returns: Carry = 1 if duplicate found, Carry = 0 if unique
;------------------------------------------------------------------------------
CHECK_DIR_DUPLICATE:
	LD	A,(DIR_FILE_COUNT)
	OR	A
	RET	Z			; 0 entries -> cannot be duplicate (NC)

	LD	B,A			; B = number of entries to check
	LD	HL,DIR_NAMES_BUF

CHECK_DUP_ENTRY_LOOP:
	PUSH	BC
	PUSH	HL			; Save entry pointer in DIR_NAMES_BUF
	LD	DE,DIR_TEMP_ENTRY
	LD	C,12			; Compare 12 bytes (8 name + '.' + 3 ext)

CHECK_DUP_BYTE_LOOP:
	LD	A,(DE)
	CP	(HL)
	JR	NZ,CHECK_DUP_NO_MATCH
	INC	HL
	INC	DE
	DEC	C
	JR	NZ,CHECK_DUP_BYTE_LOOP

	; Found identical 12-byte filename match!
	POP	HL
	POP	BC
	SCF				; Carry = 1 (duplicate)
	RET

CHECK_DUP_NO_MATCH:
	POP	HL			; Restore entry pointer
	LD	DE,13
	ADD	HL,DE			; Advance to next entry
	POP	BC
	DJNZ	CHECK_DUP_ENTRY_LOOP

	OR	A			; Carry = 0 (not duplicate)
	RET

;------------------------------------------------------------------------------
; Sort Directory Entries Alphabetically (Bubble Sort)
;------------------------------------------------------------------------------
SORT_DIR_ENTRIES:
	LD	A,(DIR_FILE_COUNT)
	CP	2
	RET	C			; 0 or 1 files: already sorted

	LD	B,A
	DEC	B			; B = outer loop count (N-1)

SORT_OUTER_LOOP:
	PUSH	BC
	LD	HL,DIR_NAMES_BUF	; HL = entry j
	LD	C,B			; C = inner loop count

SORT_INNER_LOOP:
	PUSH	BC
	PUSH	HL			; Save entry j pointer
	LD	DE,13
	ADD	HL,DE
	EX	DE,HL			; DE = entry j+1 pointer
	POP	HL			; HL = entry j pointer
	PUSH	HL			; Save entry j pointer again

	; Compare entry j (HL) and entry j+1 (DE) (12 bytes)
	LD	B,12
COMPARE_ENTRY_LOOP:
	LD	A,(DE)
	CP	(HL)
	JR	NZ,COMPARE_FOUND_DIFF
	INC	HL
	INC	DE
	DJNZ	COMPARE_ENTRY_LOOP
	JR	NO_SWAP_NEEDED		; Exactly identical

COMPARE_FOUND_DIFF:
	JR	NC,NO_SWAP_NEEDED	; (DE) >= (HL): already in alphabetical order!

	; Swap entry j and entry j+1 (13 bytes)
	POP	HL			; HL = entry j pointer
	PUSH	HL
	LD	DE,13
	ADD	HL,DE
	EX	DE,HL			; DE = entry j+1 pointer
	POP	HL			; HL = entry j pointer
	PUSH	HL

	; Copy entry j into DIR_TEMP_ENTRY
	PUSH	DE
	PUSH	HL
	LD	DE,DIR_TEMP_ENTRY
	LD	BC,13
	LDIR
	POP	HL
	POP	DE

	; Copy entry j+1 (DE) into entry j (HL)
	PUSH	DE
	PUSH	HL
	EX	DE,HL
	LD	BC,13
	LDIR
	POP	HL
	POP	DE

	; Copy DIR_TEMP_ENTRY into entry j+1 (DE)
	PUSH	HL
	LD	HL,DIR_TEMP_ENTRY
	LD	BC,13
	LDIR
	POP	HL

NO_SWAP_NEEDED:
	POP	HL			; HL = entry j pointer
	LD	DE,13
	ADD	HL,DE			; Advance HL to entry j+1
	POP	BC			; Restore inner loop count C
	DEC	C
	JR	NZ,SORT_INNER_LOOP

	POP	BC			; Restore outer loop count B
	DJNZ	SORT_OUTER_LOOP
	RET

;------------------------------------------------------------------------------
; Display Directory Entries for Current Page (48 entries: 12 rows x 4 cols)
;------------------------------------------------------------------------------
DISPLAY_DIR_PAGE:
	LD	A,(DIR_FILE_COUNT)
	OR	A
	JR	NZ,DO_SHOW_PAGE
	LD	DE,STR_NO_FILES_FOUND
	CALL	PRINT_STR
	RET

DO_SHOW_PAGE:
	; Calculate start file index: DIR_START_FILE = DIR_PAGE_INDEX * 48
	LD	A,(DIR_PAGE_INDEX)
	LD	L,A
	LD	H,0
	ADD	HL,HL			; *2
	ADD	HL,HL			; *4
	ADD	HL,HL			; *8
	ADD	HL,HL			; *16
	LD	D,H
	LD	E,L			; DE = A * 16
	ADD	HL,HL			; *32
	ADD	HL,DE			; HL = A * 48
	LD	A,L
	LD	(DIR_START_FILE),A

	; Calculate number of files on this page:
	; Count = min(48, DIR_FILE_COUNT - DIR_START_FILE)
	LD	A,(DIR_FILE_COUNT)
	LD	HL,DIR_START_FILE
	SUB	(HL)
	CP	48
	JR	C,HAVE_PAGE_COUNT
	LD	A,48
HAVE_PAGE_COUNT:
	LD	B,A			; B = number of files to display on this page

	; Calculate pointer in DIR_NAMES_BUF: DIR_NAMES_BUF + (DIR_START_FILE * 13)
	LD	A,(DIR_START_FILE)
	LD	L,A
	LD	H,0
	LD	D,H
	LD	E,L
	ADD	HL,HL			; *2
	ADD	HL,HL			; *4
	ADD	HL,DE			; *5
	ADD	HL,HL			; *10
	ADD	HL,DE			; *11
	ADD	HL,DE			; *12
	ADD	HL,DE			; *13
	LD	DE,DIR_NAMES_BUF
	ADD	HL,DE			; HL = pointer to start entry on this page

	XOR	A
	LD	(DIR_COL_COUNT),A

DISPLAY_PAGE_LOOP:
	PUSH	BC
	PUSH	HL			; Save entry pointer

	; Format entry into a clean 16-char padded column:
	; e.g. "DIGIT5  .ASM" -> "DIGIT5.ASM      "
	LD	DE,LOAD_LINE_TEMP
	LD	B,8
COPY_DISP_NAME:
	LD	A,(HL)
	CP	' '
	JR	Z,SKIP_NAME_SPACE
	LD	(DE),A
	INC	DE
SKIP_NAME_SPACE:
	INC	HL
	DJNZ	COPY_DISP_NAME

	; Check extension (3 chars) at HL+1
	INC	HL			; Skip '.'
	LD	A,(HL)
	CP	' '
	JR	Z,NO_DISP_EXT
	; Has extension: append '.' and extension chars (trimmed)
	DEC	HL			; Point back to '.'
	LD	A,'.'
	LD	(DE),A
	INC	DE
	INC	HL
	LD	B,3
COPY_DISP_EXT:
	LD	A,(HL)
	CP	' '
	JR	Z,SKIP_EXT_SPACE
	LD	(DE),A
	INC	DE
SKIP_EXT_SPACE:
	INC	HL
	DJNZ	COPY_DISP_EXT
	JR	PAD_COLUMN

NO_DISP_EXT:
	INC	HL
	INC	HL
	INC	HL

PAD_COLUMN:
	; Calculate printed length in LOAD_LINE_TEMP
	LD	HL,LOAD_LINE_TEMP
	LD	A,E
	SUB	L			; A = character count in line
	; Pad with spaces up to 16 characters
	LD	C,A
	LD	A,16
	SUB	C			; A = 16 - char_count
	JR	Z,DISP_COL_TERMINATE
	JR	C,DISP_COL_TERMINATE
	LD	B,A
PAD_COL_SPACES:
	LD	A,' '
	LD	(DE),A
	INC	DE
	DJNZ	PAD_COL_SPACES

DISP_COL_TERMINATE:
	XOR	A
	LD	(DE),A			; Null-terminate LOAD_LINE_TEMP

	; Print the 16-character column
	LD	DE,LOAD_LINE_TEMP
	CALL	PRINT_STR

	; Increment column counter
	LD	A,(DIR_COL_COUNT)
	INC	A
	LD	(DIR_COL_COUNT),A
	CP	4			; Wrap at 4 columns (64 chars <= 80 cols)
	JR	NZ,NO_ROW_WRAP
	XOR	A
	LD	(DIR_COL_COUNT),A
	LD	DE,STR_CRLF
	CALL	PRINT_STR

NO_ROW_WRAP:
	POP	HL			; Restore entry pointer
	LD	DE,13
	ADD	HL,DE			; Next entry
	POP	BC
	DEC	B
	JP	NZ,DISPLAY_PAGE_LOOP

	; If row didn't end on a newline, print CRLF
	LD	A,(DIR_COL_COUNT)
	OR	A
	JR	Z,DISP_PAGE_DONE
	LD	DE,STR_CRLF
	CALL	PRINT_STR

DISP_PAGE_DONE:
	LD	DE,STR_CRLF
	CALL	PRINT_STR
	RET

;------------------------------------------------------------------------------
; Display Open Prompt & Page Indicator
;------------------------------------------------------------------------------
DISPLAY_OPEN_PROMPT:
	LD	A,(DIR_PAGE_COUNT)
	CP	2
	JR	C,DISP_SINGLE_PROMPT

	; Multi-page prompt: "[Page X/Y]  <Space>=Next Page, <ESC>=Cancel\r\nEnter filename to open: "
	LD	DE,STR_PAGE_PREFIX
	CALL	PRINT_STR

	LD	A,(DIR_PAGE_INDEX)
	INC	A
	LD	L,A
	LD	H,0
	CALL	PRINT_DEC_WORD

	LD	DE,STR_PAGE_MID
	CALL	PRINT_STR

	LD	A,(DIR_PAGE_COUNT)
	LD	L,A
	LD	H,0
	CALL	PRINT_DEC_WORD

	LD	DE,STR_PAGE_SUFFIX
	CALL	PRINT_STR
	RET

DISP_SINGLE_PROMPT:
	LD	DE,STR_OPEN_PROMPT
	CALL	PRINT_STR
	RET

;------------------------------------------------------------------------------
; Read Filename String with Interactive Line Editing & Paging
; Returns:
;   Carry = 0 -> Valid filename entered in INPUT_FILENAME_BUF
;   Carry = 1, A = 0 -> Cancelled (ESC or empty Enter on single page)
;   Carry = 1, A = 1 -> Next Page (Space or empty Enter on multi-page)
;------------------------------------------------------------------------------
READ_FILENAME_INPUT:
	XOR	A
	LD	(INPUT_BUF_LEN),A
	LD	(SHOWING_FNF_MSG),A
	LD	HL,INPUT_FILENAME_BUF
	LD	(HL),0
	JR	INPUT_CHAR_LOOP

RESUME_FILENAME_INPUT:
	JR	INPUT_CHAR_LOOP

READ_FILENAME_INPUT_PREFILLED:
	XOR	A
	LD	(SHOWING_FNF_MSG),A
	; Echo prefilled string if non-empty
	LD	A,(INPUT_BUF_LEN)
	OR	A
	JR	Z,INPUT_CHAR_LOOP
	LD	DE,INPUT_FILENAME_BUF
	CALL	PRINT_STR

INPUT_CHAR_LOOP:
	CALL	GET_KEY
	CALL	CHECK_CLEAR_FNF

	; Ctrl-F -> Toggle Save Format (Save Screen only)
	CP	KEY_CTRL_F
	JR	NZ,CHECK_ESC_KEY
	LD	A,(IS_SAVE_UI)
	OR	A
	JR	Z,INPUT_CHAR_LOOP	; Ignore Ctrl-F in Open Screen
	LD	A,(SAVE_FORMAT)
	XOR	1			; Toggle between FMT_CPM (0) and FMT_LINUX (1)
	LD	(SAVE_FORMAT),A
	LD	A,2			; A = 2 (Format toggled)
	SCF				; Carry = 1 (special action)
	RET

CHECK_ESC_KEY:
	CP	KEY_ESC
	JR	NZ,INPUT_CHECK_PAGE_KEYS

	; Check if character follows ESC within a short timeout
	LD	BC,1000
INPUT_WAIT_ESC:
	CALL	CHECK_KEY_READY
	JR	NZ,INPUT_GOT_ESC_BYTE
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,INPUT_WAIT_ESC

	; Standalone ESC key -> Cancel
	JP	INPUT_CANCEL

INPUT_GOT_ESC_BYTE:
	CALL	GET_KEY
	CP	'['
	JR	Z,INPUT_HANDLE_CSI
	CP	'O'
	JR	Z,INPUT_HANDLE_SS3
	JP	INPUT_CHAR_LOOP

INPUT_HANDLE_CSI:
	CALL	GET_KEY
	CP	'5'			; Page Up (ESC [ 5 ~)
	JR	Z,INPUT_CSI_PGUP
	CP	'6'			; Page Down (ESC [ 6 ~)
	JR	Z,INPUT_CSI_PGDN
	CP	'I'			; Page Up (VT alt)
	JR	Z,INPUT_DO_PGUP
	CP	'G'			; Page Down (VT alt)
	JR	Z,INPUT_DO_PGDN
	CP	'3'			; Delete key (ESC [ 3 ~)
	JR	Z,INPUT_CSI_DEL
	JP	INPUT_CHAR_LOOP

INPUT_CSI_PGUP:
	CALL	GET_KEY			; Consume trailing '~'
INPUT_DO_PGUP:
	LD	A,3			; A = 3 (Previous Page / PgUp)
	SCF				; Carry = 1
	RET

INPUT_CSI_PGDN:
	CALL	GET_KEY			; Consume trailing '~'
INPUT_DO_PGDN:
	LD	A,1			; A = 1 (Next Page / PgDn)
	SCF				; Carry = 1
	RET

INPUT_CSI_DEL:
	CALL	GET_KEY			; Consume trailing '~'
	JP	INPUT_BS		; Treat Delete as Backspace

INPUT_HANDLE_SS3:
	CALL	GET_KEY			; Consume char
	JP	INPUT_CHAR_LOOP

INPUT_CHECK_PAGE_KEYS:
	; Ctrl+U or Ctrl+B -> Page Up
	CP	KEY_CTRL_U
	JR	Z,INPUT_DO_PGUP
	CP	2			; Ctrl+B
	JR	Z,INPUT_DO_PGUP

	; Ctrl+V -> Page Down
	CP	KEY_CTRL_V
	JR	Z,INPUT_DO_PGDN

CHECK_ENTER_KEY:
	; Enter -> Finish input or advance page if empty
	CP	KEY_ENTER
	JP	Z,INPUT_ENTER

	; Backspace / Delete
	CP	KEY_BACKSPACE
	JP	Z,INPUT_BS
	CP	KEY_DEL
	JP	Z,INPUT_BS

	; Printable character (0x20..0x7E)
	CP	' '
	JP	C,INPUT_CHAR_LOOP
	CP	07FH
	JP	NC,INPUT_CHAR_LOOP

	; Check buffer capacity (max 20 chars)
	LD	B,A			; Save char in B
	LD	A,(INPUT_BUF_LEN)
	CP	20
	JP	NC,INPUT_CHAR_LOOP

	; Store character
	LD	HL,INPUT_FILENAME_BUF
	LD	E,A
	LD	D,0
	ADD	HL,DE
	LD	(HL),B
	INC	HL
	LD	(HL),0			; Null-terminate

	LD	A,(INPUT_BUF_LEN)
	INC	A
	LD	(INPUT_BUF_LEN),A

	; Echo character
	LD	A,B
	CALL	PUTC
	JP	INPUT_CHAR_LOOP

INPUT_BS:
	LD	A,(INPUT_BUF_LEN)
	OR	A
	JP	Z,INPUT_CHAR_LOOP	; Nothing to backspace

	DEC	A
	LD	(INPUT_BUF_LEN),A
	LD	HL,INPUT_FILENAME_BUF
	LD	E,A
	LD	D,0
	ADD	HL,DE
	LD	(HL),0			; Null-terminate at new end

	; Visual backspace: \x08 \x08
	LD	A,008H
	CALL	PUTC
	LD	A,' '
	CALL	PUTC
	LD	A,008H
	CALL	PUTC
	JP	INPUT_CHAR_LOOP

;------------------------------------------------------------------------------
; Clear "  File not found" inline message if currently visible
; Preserves AF and BC
;------------------------------------------------------------------------------
CHECK_CLEAR_FNF:
	PUSH	AF
	PUSH	BC
	LD	A,(SHOWING_FNF_MSG)
	OR	A
	JR	Z,CLEAR_FNF_DONE

	XOR	A
	LD	(SHOWING_FNF_MSG),A

	; Erase 16 chars of "  File not found": 16 backspaces, 16 spaces, 16 backspaces
	LD	B,16
ERASE_FNF_BS1:
	LD	A,008H
	CALL	PUTC
	DJNZ	ERASE_FNF_BS1

	LD	B,16
ERASE_FNF_SP:
	LD	A,' '
	CALL	PUTC
	DJNZ	ERASE_FNF_SP

	LD	B,16
ERASE_FNF_BS2:
	LD	A,008H
	CALL	PUTC
	DJNZ	ERASE_FNF_BS2

CLEAR_FNF_DONE:
	POP	BC
	POP	AF
	RET

INPUT_CANCEL:
	XOR	A			; A = 0 (cancel)
	LD	(SHOWING_FNF_MSG),A
	SCF				; Carry = 1
	RET

INPUT_ENTER:
	LD	A,(INPUT_BUF_LEN)
	OR	A
	JR	Z,INPUT_ENTER_EMPTY	; Empty string on Enter

	; Non-empty string: success
	OR	A			; Carry = 0 (success)
	RET

INPUT_ENTER_EMPTY:
	JP	INPUT_CANCEL

;------------------------------------------------------------------------------
; Parse Filename String (e.g. "30.TXT" or "A:TEST.DAT") into WORK_FCB
;------------------------------------------------------------------------------
PARSE_FILENAME_TO_FCB:
	; Clear WORK_FCB (36 bytes of 0)
	LD	HL,WORK_FCB
	LD	(HL),0
	LD	DE,WORK_FCB+1
	LD	BC,35
	LDIR

	; Fill filename (bytes 1..8) and ext (bytes 9..11) with spaces
	LD	HL,WORK_FCB+1
	LD	B,11
FILL_FCB_SPACES:
	LD	(HL),' '
	INC	HL
	DJNZ	FILL_FCB_SPACES

	LD	HL,INPUT_FILENAME_BUF

	; Skip leading spaces
PARSE_SKIP_SPACES:
	LD	A,(HL)
	CP	' '
	JR	NZ,PARSE_CHECK_DRIVE
	INC	HL
	JR	PARSE_SKIP_SPACES

PARSE_CHECK_DRIVE:
	; Check if byte 1 is ':' (e.g. "A:FILE.TXT")
	INC	HL
	LD	A,(HL)
	DEC	HL
	CP	':'
	JR	NZ,PARSE_DEFAULT_DRIVE

	; Drive letter in (HL)
	LD	A,(HL)
	CALL	TO_UPPER
	SUB	'A'-1			; 'A' -> 1, 'B' -> 2
	LD	(WORK_FCB),A
	INC	HL			; Skip drive letter
	INC	HL			; Skip ':'
	JR	PARSE_NAME_START

PARSE_DEFAULT_DRIVE:
	; If no explicit drive, default to CURRENT_DIR_DRIVE (if non-zero)
	LD	A,(CURRENT_DIR_DRIVE)
	OR	A
	JR	Z,PARSE_NAME_START
	LD	(WORK_FCB),A

PARSE_NAME_START:
	; Read up to 8 characters of filename into WORK_FCB+1 .. WORK_FCB+8
	LD	DE,WORK_FCB+1
	LD	B,8
PARSE_NAME_LOOP:
	LD	A,(HL)
	OR	A
	RET	Z			; End of string
	CP	' '
	RET	Z
	CP	'.'
	JR	Z,PARSE_EXT_START
	CALL	TO_UPPER
	LD	(DE),A
	INC	HL
	INC	DE
	DJNZ	PARSE_NAME_LOOP

	; If more than 8 chars before '.', skip to '.'
PARSE_SKIP_TO_DOT:
	LD	A,(HL)
	OR	A
	RET	Z
	CP	' '
	RET	Z
	CP	'.'
	JR	Z,PARSE_EXT_START
	INC	HL
	JR	PARSE_SKIP_TO_DOT

PARSE_EXT_START:
	INC	HL			; Skip '.'
	LD	DE,WORK_FCB+9
	LD	B,3
PARSE_EXT_LOOP:
	LD	A,(HL)
	OR	A
	RET	Z
	CP	' '
	RET	Z
	CALL	TO_UPPER
	LD	(DE),A
	INC	HL
	INC	DE
	DJNZ	PARSE_EXT_LOOP
	RET

TO_UPPER:
	CP	'a'
	RET	C
	CP	'z'+1
	RET	NC
	SUB	020H
	RET

CLEAR_LOAD_TEMP:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	HL,LOAD_LINE_TEMP
	LD	DE,LOAD_LINE_TEMP+1
	LD	BC,127
	LD	(HL),0
	LDIR
	POP	HL
	POP	DE
	POP	BC
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
; File Saving: Streams lines directly from Far RAM banks to disk
;------------------------------------------------------------------------------
SAVE_FILE:
	; Flush local cache dirty lines first
	CALL	FLUSH_DIRTY_CACHE

	LD	A,(WORK_FCB+1)
	CP	' '
	JP	NZ,DO_SAVE_EXISTING

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

	; Stream lines from Far RAM banks to disk
	LD	BC,0			; BC = document line counter
SAVE_LINE_LOOP:
	LD	HL,(DOC_TOTAL_LINES)
	LD	A,H
	CP	B
	JP	C,SAVE_FLUSH_REMAINDER
	JP	NZ,DO_SAVE_LINE
	LD	A,L
	CP	C
	JP	Z,SAVE_FLUSH_REMAINDER
	JP	C,SAVE_FLUSH_REMAINDER

DO_SAVE_LINE:
	PUSH	BC
	; Read line from Far RAM into LOAD_LINE_TEMP
	LD	DE,LOAD_LINE_TEMP
	CALL	READ_FAR_LINE

	LD	HL,LOAD_LINE_TEMP
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
	INC	BC
	JP	SAVE_LINE_LOOP

SAVE_FLUSH_REMAINDER:
	; Pad remaining bytes in sector with ^Z (0x1A)
PAD_SECTOR_LOOP:
	LD	A,(DMA_BYTES_LEFT)
	CP	128
	JP	Z,CLOSE_OUTPUT_FILE
	LD	A,26
	CALL	WRITE_BYTE_TO_DMA
	JP	PAD_SECTOR_LOOP

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
; Print 16-bit Word in Decimal (HL)
;------------------------------------------------------------------------------
PRINT_DEC_WORD:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	DE,DEC_WORD_BUF+5
	LD	A,'$'
	LD	(DE),A			; '$' terminator for PRINT_STR
DEC_WORD_LOOP:
	CALL	DIV_HL_10		; HL = HL / 10, A = HL % 10
	ADD	A,'0'
	DEC	DE
	LD	(DE),A
	LD	A,H
	OR	L
	JR	NZ,DEC_WORD_LOOP
	CALL	PRINT_STR
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

DIV_HL_10:
	PUSH	BC
	LD	B,16
	XOR	A
DIV_HL_10_LOOP:
	ADD	HL,HL
	RLA
	CP	10
	JR	C,DIV_HL_10_NEXT
	SUB	10
	INC	L
DIV_HL_10_NEXT:
	DJNZ	DIV_HL_10_LOOP
	POP	BC
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
	.DB	"                  ~                version 0.7.1                ",13,10
	.DB	"                  ~              by Dean Jenkins                ",13,10
	.DB	"                  ~                                             ",13,10
	.DB	"                  ~       SE is open source and freely usable   ",13,10
	.DB	"                  ~                                             ",13,10
	.DB	"                  ~       type   :e  or  <Enter>   to edit      ",13,10
	.DB	"                  ~       type   :o                to open file ",13,10
	.DB	"                  ~       type   :s                to save file ",13,10
	.DB	"                  ~       type   :t                for mem test ",13,10
	.DB	"                  ~       type   :f                for file test",13,10
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
	.DB	27,"[H",27,"[2J"
	.DB	"============================================================",13,10
	.DB	"        SE.COM 512KB EXTENDED MEMORY DIAGNOSTIC SUITE       ",13,10
	.DB	"============================================================",13,10,13,10,"$"

STR_TEST_HBIOS_OK:
	.DB	"[+] RomWBW HBIOS API (RST 08H): DETECTED",13,10,"$"

STR_TEST_NO_HBIOS:
	.DB	"[-] RomWBW HBIOS API NOT DETECTED.",13,10,"$"

STR_TEST_RAM_BANKS:
	.DB	"[*] Installed System RAM Banks: $"

STR_TEST_RAM_BANKS_END:
	.DB	" x 32KB (512KB Total RAM)",13,10,"$"

STR_TEST_CUR_BANK:
	.DB	"[*] Active CP/M User RAM Bank:  0x$"

STR_TEST_DISCOVERED:
	.DB	"[*] Usable Far RAM Banks (32K): $"

STR_TEST_BANKS_LIST:
	.DB	"): ","$"

STR_TEST_CAPACITY:
	.DB	"[*] Far Document Storage:       3,584 Lines (448 KB Extended RAM)",13,10,13,10,"$"

STR_TEST_NO_BANKS:
	.DB	"[-] No Far RAM banks available for extended storage.",13,10,13,10,"$"

STR_TEST1_TITLE:
	.DB	"[*] Test 1: Direct Inter-Bank DMA Copy (SYSBNKCPY 0xF5)...",13,10,"$"

STR_TEST1_PASS:
	.DB	"    --> [PASS] 2-byte DMA pattern (0xAA55) verified.",13,10,13,10,"$"

STR_TEST2_TITLE:
	.DB	"[*] Test 2: Multi-Bank Far Line Engine (WRITE/READ FAR LINE)...",13,10,"$"

STR_TEST2_PASS_PRE:
	.DB	"    --> [PASS] Verified across all $"

STR_TEST2_PASS_POST:
	.DB	" Far RAM Banks (128-byte line I/O).",13,10,13,10,"$"

STR_TEST3_TITLE:
	.DB	"[*] Test 3: Bank Boundary & 32KB Stride (Offsets 0x0000 & 0x7F80)...",13,10,"$"

STR_TEST3_PASS:
	.DB	"    --> [PASS] Offsets 0x0000 (top) & 0x7F80 (bottom) verified without overlap.",13,10,13,10,"$"

STR_TEST4_TITLE:
	.DB	"[*] Test 4: Sliding Window Cache (16KB / 128 Lines) & Dirty Flush...",13,10,"$"

STR_TEST4_PASS:
	.DB	"    --> [PASS] Transparent window sliding and Far RAM sync verified.",13,10,13,10,"$"

STR_TEST4_FAIL_L0_MSG:
	.DB	"    [-] Test 4 Line 0 Reload Mismatch! Expected 'C' (0x43), Got: 0x$"

STR_TEST4_FAIL_L300_MSG:
	.DB	"    [-] Test 4 Line 300 Reload Mismatch! Expected 'C' (0x43), Got: 0x$"

STR_TEST_ALL_PASSED:
	.DB	"============================================================",13,10
	.DB	"[+] ALL 512KB EXTENDED MEMORY TESTS PASSED SUCCESSFULLY!",13,10
	.DB	"============================================================",13,10,13,10,"$"

STR_TEST_FAILED:
	.DB	13,10,"[-] EXTENDED MEMORY TEST FAILED (Data verification mismatch)",13,10,13,10,"$"

STR_TEST_PROMPT:
	.DB	"Press any key to return to Splash Screen...$"

STR_FILE_TEST_TITLE:
	.DB	27,"[H",27,"[2J"
	.DB	"============================================================",13,10
	.DB	"        SE.COM MULTI-SECTOR FILE I/O VALIDATION TEST        ",13,10
	.DB	"============================================================",13,10,13,10,"$"

STR_FILE_TEST_OPEN_OK:
	.DB	"[+] BDOS Open File ('30.TXT'): SUCCESS",13,10,"$"

STR_RAW_SECTORS_LBL:
	.DB	"[*] Total Sectors Read:       $"
STR_RAW_SECTORS_TAIL:
	.DB	" sectors (128 bytes/sector)",13,10,"$"

STR_RAW_BYTES_LBL:
	.DB	"[*] Total Data Bytes:         $"
STR_RAW_BYTES_TAIL:
	.DB	" bytes",13,10,"$"

STR_RAW_LINES_LBL:
	.DB	"[*] Total Text Lines Parsed:  $"
STR_RAW_LINES_TAIL:
	.DB	" lines",13,10,"$"

STR_RAW_FMT_LBL:
	.DB	"[*] Line Ending Format:       $"
STR_RAW_FMT_CPM:
	.DB	"CP/M [CRLF]",13,10,"$"
STR_RAW_FMT_LINUX:
	.DB	"Linux [LF]",13,10,"$"

STR_RAW_FIRST_LINE_LBL:
	.DB	"[*] First Line Content:       \"",$"
STR_RAW_LAST_LINE_LBL:
	.DB	"[*] Last Line Content:        \"",$"
STR_QUOTE_CRLF:
	.DB	"\"",13,10,"$"

STR_FILE_TEST_PASSED:
	.DB	13,10
	.DB	"============================================================",13,10
	.DB	"[+] MULTI-SECTOR FILE VALIDATION: ALL TESTS PASSED!",13,10
	.DB	"============================================================",13,10,"$"

STR_FILE_TEST_NOT_FOUND:
	.DB	"[-] Error: Test file '30.TXT' not found on CP/M drive!",13,10,"$"

STR_FILE_TEST_FAILED:
	.DB	"[-] Error: Multi-sector file validation FAILED!",13,10,"$"

STR_STATUS_PREFIX:
	.DB	" SE v0.7.1 | ","$"

STR_STATUS_120X40:
	.DB	"120x40 | ","$"

STR_STATUS_80X24:
	.DB	"80x24 | ","$"

STR_FMT_CPM:
	.DB	"CP/M | ","$"

STR_FMT_LINUX:
	.DB	"Linux | ","$"

STR_STATUS_KEYS:
	.DB	"^K: Editor keys | ","$"

STR_SEL_PREFIX:
	.DB	"[SEL: ","$"

STR_BLK_PREFIX:
	.DB	"[BLK: ","$"

STR_CHAR_SUFFIX:
	.DB	"c] | ","$"

STR_LINE_SUFFIX:
	.DB	"L] | ","$"

STR_CHAR_LOCK_SUFFIX:
	.DB	"c LOCK] | ","$"

STR_LINE_LOCK_SUFFIX:
	.DB	"L LOCK] | ","$"

STR_HELP_SCREEN:
	.DB	27,"[H",27,"[2J"
	.DB	"================================================================================",13,10
	.DB	"                          SE.COM - EDITOR MODE KEYS                             ",13,10
	.DB	"================================================================================",13,10
	.DB	"  FILE & SYSTEM:",13,10
	.DB	"    Ctrl+O           Open file screen        Ctrl+S          Save file screen",13,10
	.DB	"    Ctrl+Q           Quit to CP/M            ESC             Splash / Clear block",13,10
	.DB	"    Ctrl+K           Help / Solidify block",13,10,13,10
	.DB	"  NAVIGATION:",13,10
	.DB	"    Arrow Keys       Move Up/Down/Left/Right Ctrl+A / Home   Start of line",13,10
	.DB	"    Ctrl+U / PgUp    Page Up                 Ctrl+E / End    End of line",13,10
	.DB	"    Ctrl+V / PgDn    Page Down               Ctrl+T / ^Home  Top of file",13,10
	.DB	"                                             Ctrl+G / ^End   Bottom of file",13,10,13,10
	.DB	"  EDITING & BLOCK:",13,10
	.DB	"    ASCII 32..126    Insert characters       Enter           New line",13,10
	.DB	"    Backspace        Delete left / join up   Ctrl+D / Delete Delete / join dn",13,10
	.DB	"    Ctrl+B           Start/Toggle block      Ctrl+K          Solidify block",13,10
	.DB	"    Delete / Ctrl+D  Delete solidified block ESC             Clear block",13,10
	.DB	"================================================================================",13,10
	.DB	"                      Press any key to return to editor...",13,10,"$"

STR_STATUS_SEP:
	.DB	" | ","$"

STR_NO_NAME:
	.DB	"[No Name]",0

STR_STATUS_POS:
	.DB	"Row ","$"

STR_STATUS_COL:
	.DB	", Col ","$"

MSG_EXIT:
	.DB	13,10,"Exiting SE.COM. Returned to CP/M.",13,10,"$"

STR_DIR_TITLE:
	.DB	27,"[H",27,"[2J"
	.DB	"============================================================",13,10
	.DB	"           SE.COM - OPEN FILE (DIRECTORY - DRIVE "
STR_DIR_DRIVE_CHAR:
	.DB	"A:)        ",13,10
	.DB	"============================================================",13,10,13,10,"$"

STR_OPEN_PROMPT:
	.DB	"------------------------------------------------------------",13,10
	.DB	"Enter filename to open (<ESC>=Cancel): ","$"

STR_PAGE_PREFIX:
	.DB	"------------------------------------------------------------",13,10
	.DB	"[Page ","$"

STR_PAGE_MID:
	.DB	"/","$"

STR_PAGE_SUFFIX:
	.DB	"]  <PgUp>/<PgDn>=Page, <ESC>=Cancel",13,10
	.DB	"Enter filename to open: ","$"

STR_NO_FILES_FOUND:
	.DB	"  [No files found on current drive]",13,10,13,10,"$"

DEFAULT_FCB_NAME:
	.DB	0,"OUTPUT  TXT",0,0,0,0

STR_SAVE_TITLE:
	.DB	27,"[H",27,"[2J"
	.DB	"============================================================",13,10
	.DB	"           SE.COM - SAVE FILE (DIRECTORY - DRIVE "
STR_SAVE_DRIVE_CHAR:
	.DB	"A:)        ",13,10
	.DB	"============================================================",13,10,13,10,"$"

STR_SAVE_FMT_PREFIX:
	.DB	"Format: [","$"

STR_SAVE_FMT_CPM:
	.DB	"CP/M","$"

STR_SAVE_FMT_LINUX:
	.DB	"Linux","$"

STR_SAVE_FMT_SUFFIX:
	.DB	"]  (^F: toggle format)",13,10,"$"

STR_SAVE_SEP_LINE:
	.DB	"------------------------------------------------------------",13,10,"$"

STR_SAVE_ENTER_PROMPT:
	.DB	"Enter filename to save (or <Enter>/<ESC> to cancel): ","$"

STR_SAVE_PAGE_PREFIX:
	.DB	"------------------------------------------------------------",13,10
	.DB	"[Page ","$"

STR_SAVE_PAGE_SUFFIX:
	.DB	"]  <PgUp>/<PgDn>=Page, <ESC>=Cancel",13,10,"$"

STR_SAVE_PAGE_PROMPT:
	.DB	"Enter filename to save: ","$"

STR_OVERWRITE_WARN:
	.DB	13,10,"File already exists. Overwrite? (y/n): ","$"

STR_SAVE_CANCELLED:
	.DB	13,10,"Save cancelled.",13,10,"$"

STR_FILE_NOT_FOUND:
	.DB	13,10,"File not found.",13,10,"$"

STR_FNF_INLINE:
	.DB	"  File not found","$"

;------------------------------------------------------------------------------
; Variables & Stack Area
;------------------------------------------------------------------------------
SAVED_SP:	.DW	0
SHOWING_FNF_MSG:.DB	0		; 1 if "  File not found" inline message is visible
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

CUR_DOC_ROW:	.DW	0		; 16-bit document cursor row (0..3583)
CUR_COL:	.DB	0		; 8-bit character byte index in line (0..126)
TARGET_COL:	.DB	0		; Sticky visual column (0..119)
TOP_DOC_ROW:	.DW	0		; 16-bit top visible document line on screen
DOC_TOTAL_LINES:.DW	1		; 16-bit total document lines count (default 1 empty line)
HAS_FILE_ARG:	.DB	0
IN_EDITOR_MODE:	.DB	0
SAVE_FORMAT:	.DB	FMT_CPM		; Default format is CP/M (CR/LF)
IS_SAVE_UI:	.DB	0		; 1 if currently in Save File Screen
SEEN_CR:	.DB	0		; Line format auto-detection state
CHAR_INSERT_TEMP:.DB	0
CSI_DIGIT_PREFIX:.DB	0
JOIN_COL_SAVED:	.DB	0
JOIN_DOC_LINE:	.DW	0
DEL_BLK_CUR_LINE:.DW	0
BLOCK_ACTIVE:	.DB	0		; 0 = inactive, 1 = selecting, 2 = solidified
BLOCK_ANCHOR_ROW:.DW	0		; 16-bit document row where block started
BLOCK_ANCHOR_COL:.DB	0		; 8-bit character column where block started
BLOCK_START_ROW:.DW	0		; Normalized start row
BLOCK_START_COL:.DB	0		; Normalized start col
BLOCK_END_ROW:	.DW	0		; Normalized end row
BLOCK_END_COL:	.DB	0		; Normalized end col

LINE_BLK_ACTIVE:.DB	0		; 1 if rendered line is in block
LINE_BLK_START:	.DB	0		; Start character column of highlight on line
LINE_BLK_END:	.DB	0		; End character column of highlight on line
LINE_IN_INVERSE:.DB	0		; 1 if terminal currently has inverse video ON

NEED_SCREEN_RENDER:	.DB	0	; 1 if full screen redraw pending
NEED_LINE_RENDER:	.DB	0	; 1 if current line redraw pending
NEED_STATUS_RENDER:	.DB	0	; 1 if status bar redraw / cursor restore pending

CACHE_START_ROW:.DW	0		; 16-bit doc row index at LINE_STORAGE[0]
CACHE_DIRTY:	.DB	0		; 1 if local cache has unsaved modifications
EXT_BANK_COUNT:	.DB	0		; Number of available far RAM banks (up to 14)
EXT_BANK_TABLE:	.DS	14		; Table of far RAM bank IDs

FAR_DEST_BANK:	.DB	0
FAR_SRC_BANK:	.DB	0
FAR_DEST_ADDR:	.DW	0
FAR_SRC_ADDR:	.DW	0
FAR_LOCAL_ADDR:	.DW	0
SLOT_TEMP:	.DB	0
DEC_WORD_BUF:	.DS	6		; Buffer for PRINT_DEC_WORD (5 digits + null)

LOAD_LINE_TEMP:	.DS	128		; 128-byte scratch line for I/O and Far RAM transfers
SPLIT_LINE_TEMP:.DS	128		; 128-byte scratch line for line splits
CUR_DMA_PTR:	.DW	0
DMA_BYTES_LEFT:	.DB	0

TEST_PATTERN:	.DB	0,0
TEST_READBACK:	.DB	0,0

WORK_FCB:	.DS	36
DIR_TEMP_FCB:	.DS	36

CURRENT_DIR_DRIVE:	.DB	0		; Active directory drive (1=A:, 2=B:, 3=C:, etc.)
DIR_SEARCH_FCB:		.DS	36
DIR_FILE_COUNT:		.DB	0
DIR_PAGE_INDEX:		.DB	0
DIR_PAGE_COUNT:		.DB	0
DIR_START_FILE:		.DB	0
DIR_COL_COUNT:		.DB	0
DIR_TEMP_ENTRY:		.DS	16
INPUT_BUF_LEN:		.DB	0
INPUT_FILENAME_BUF:	.DS	32
DIR_NAMES_BUF:		.DS	3328	; 256 entries * 13 bytes

RAW_TEST_FCB:		.DS	36
RAW_SECTOR_BUF:		.DS	128
RAW_SECTORS_READ:	.DW	0
RAW_BYTES_COUNT:	.DW	0
RAW_LINES_COUNT:	.DW	0
RAW_SEEN_CR:		.DB	0
RAW_FORMAT_TYPE:	.DB	0
RAW_DATA_PTR:		.DW	0
RAW_DATA_BUFFER:	.DS	2048

		.DS	512
LOCAL_STACK:

; 48 lines x 128 bytes stride local working cache in TPA (6,144 bytes)
LINE_STORAGE:	.DS	6144

; Line Slot Indirection Table (3,584 lines * 2 bytes = 7,168 bytes)
DOC_LINE_SLOTS:	.DS	7168

NEXT_FRESH_SLOT:	.DW	0
FIRST_FREE_SLOT:	.DW	0FFFFH

	.END
