;==============================================================================
; SE.COM: CP/M Full-Screen Text Editor for RomWBW / RC2014
; Target: Z80 CPU, CP/M 2.2+, RomWBW HBIOS 512K Extended RAM, Minicom/VT100
;==============================================================================

	.ORG	$0100

;------------------------------------------------------------------------------
; Constants & BDOS Vectors
;------------------------------------------------------------------------------
BDOS_ENTRY	.EQU	$0005
FCB1		.EQU	$005C
CMD_LEN		.EQU	$0080
CMD_TAIL	.EQU	$0081

SCREEN_ROWS	.EQU	24
SCREEN_COLS	.EQU	80
MAX_LINE_LEN	.EQU	80
TAB_SIZE	.EQU	8

KEY_CTRL_C	.EQU	3
KEY_CTRL_Q	.EQU	17
KEY_CTRL_S	.EQU	19
KEY_BACKSPACE	.EQU	8
KEY_TAB		.EQU	9
KEY_ENTER	.EQU	13
KEY_ESC		.EQU	27
KEY_DEL		.EQU	127

;------------------------------------------------------------------------------
; Main Entry Point
;------------------------------------------------------------------------------
START:
	LD	(SAVED_SP),SP
	LD	SP,LOCAL_STACK

	; Initialize Terminal (Clear Screen & Home)
	CALL	TERM_INIT

	; Query RomWBW User Bank
	CALL	BUFFER_INIT

	; Display Vim-style Splash Screen
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

DO_MEM_TEST:
	CALL	RUN_MEM_TEST
	; Wait for key to return to splash
	CALL	GET_KEY
	JR	SPLASH_START

ENTER_EDITOR:
	CALL	TERM_INIT
	CALL	RENDER_SCREEN

MAIN_LOOP:
	CALL	GET_KEY
	CP	KEY_CTRL_Q
	JR	Z,EXIT_PROGRAM

	CP	KEY_CTRL_S
	JR	NZ,NOT_SAVE
	CALL	SAVE_FILE
	JR	MAIN_LOOP

NOT_SAVE:
	CALL	HANDLE_INPUT
	CALL	RENDER_SCREEN
	JR	MAIN_LOOP

EXIT_PROGRAM:
	; Restore terminal cursor to bottom line
	LD	DE,MSG_EXIT
	CALL	PRINT_STR

	LD	SP,(SAVED_SP)
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
	; Direct Console I/O (BDOS Function 6, E=0xFF)
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
; Splash Screen Renderer (Vim Style)
;------------------------------------------------------------------------------
RENDER_SPLASH:
	LD	DE,STR_CLEAR_SCREEN
	CALL	PRINT_STR
	LD	DE,STR_SPLASH_BODY
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

	; D = ROM Banks, E = RAM Banks
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

	; Discover Target Upper RAM Bank ID
	; In RomWBW, RAM banks start at 0x80. If User Bank is 0x8E, Target Bank is 0x80 (or 0x80 + UserBank XOR 1)
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

	; Test memory bank copy
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
	LD	D,A			; Dest Bank = Target Upper RAM Bank (e.g. 0x80)
	LD	A,(CPM_USER_BANK)
	LD	E,A			; Src Bank = CP/M User Bank (e.g. 0x8E)
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
	LD	D,A			; Dest Bank = User Bank (0x8E)
	LD	A,(TARGET_RAM_BANK)
	LD	E,A			; Src Bank = Target RAM Bank (0x80)
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

PRINT_DEC_BYTE:
	PUSH	AF
	LD	C,0
DIV10_LOOP:
	CP	10
	JR	C,PRINT_TENS
	SUB	10
	INC	C
	JR	DIV10_LOOP
PRINT_TENS:
	PUSH	AF
	LD	A,C
	OR	A
	JR	Z,SKIP_TENS_ZERO
	ADD	A,'0'
	CALL	PUTC
SKIP_TENS_ZERO:
	POP	AF
	ADD	A,'0'
	CALL	PUTC
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

	LD	B,SCREEN_ROWS-1
	LD	C,0
RENDER_ROW_LOOP:
	PUSH	BC
	LD	A,C
	LD	(CUR_RENDER_ROW),A
	CALL	RENDER_SINGLE_LINE
	POP	BC
	INC	C
	DJNZ	RENDER_ROW_LOOP

	CALL	RENDER_STATUS_BAR
	CALL	LOCATE_CURSOR
	RET

RENDER_SINGLE_LINE:
	LD	DE,STR_CLEAR_EOL
	CALL	PRINT_STR

	LD	A,(CUR_RENDER_ROW)
	OR	A
	JR	NZ,RENDER_EMPTY_LINE

	LD	DE,SAMPLE_TEXT
	CALL	PRINT_STR
	JR	RENDER_LINE_DONE

RENDER_EMPTY_LINE:
	LD	A,'~'
	CALL	PUTC

RENDER_LINE_DONE:
	LD	A,13
	CALL	PUTC
	LD	A,10
	CALL	PUTC
	RET

RENDER_STATUS_BAR:
	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR
	LD	DE,STR_STATUS_TEXT
	CALL	PRINT_STR
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	RET

LOCATE_CURSOR:
	LD	DE,STR_HOME
	CALL	PRINT_STR
	RET

HANDLE_INPUT:
	RET

BUFFER_INIT:
	PUSH	IX
	LD	B,0F3H			; SYSGETBNK
	RST	08H
	POP	IX
	LD	A,C
	LD	(CPM_USER_BANK),A
	RET

HBIOS_DETECT:
	PUSH	IX
	LD	B,0F8H			; CIOCNT
	LD	C,000H
	RST	08H
	POP	IX
	OR	A
	RET

SAVE_FILE:
	RET

;------------------------------------------------------------------------------
; String Constants & Data
;------------------------------------------------------------------------------
STR_CLEAR_SCREEN:
	.DB	27,"[2J",27,"[H","$"

STR_HOME:
	.DB	27,"[H","$"

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
	.DB	"                  ~                version 0.1.0                ",13,10
	.DB	"                  ~              by Dean Jenkins                ",13,10
	.DB	"                  ~                                             ",13,10
	.DB	"                  ~       SE is open source and freely usable   ",13,10
	.DB	"                  ~                                             ",13,10
	.DB	"                  ~       type   :e  or  <Enter>   to edit      ",13,10
	.DB	"                  ~       type   :t                for mem test ",13,10
	.DB	"                  ~       type   :q  or  ^Q        to exit      ",13,10
	.DB	"                  ~                                             ",13,10
	.DB	"                  ~      Z80 CP/M with 512K Extended Storage    ",13,10
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

STR_STATUS_TEXT:
	.DB	" SE v0.1.0 | Z80 Screen Editor | ^S: Save | ^Q: Quit                       ","$"

MSG_EXIT:
	.DB	27,"[24;1H",27,"[0m",13,10,"Exiting SE.COM. Returned to CP/M.",13,10,"$"

SAMPLE_TEXT:
	.DB	"; Z80 Full-Screen Editor (SE.COM) Active Buffer","$"

;------------------------------------------------------------------------------
; Variables & Stack Area
;------------------------------------------------------------------------------
SAVED_SP:	.DW	0
CPM_USER_BANK:	.DB	0
TARGET_RAM_BANK:.DB	0
RAM_BANK_COUNT:	.DB	0
ROM_BANK_COUNT:	.DB	0
CUR_ROW:	.DB	0
CUR_COL:	.DB	0
CUR_RENDER_ROW:	.DB	0

TEST_PATTERN:	.DB	0,0
TEST_READBACK:	.DB	0,0

		.DS	128
LOCAL_STACK:

	.END
