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

	; Check for RomWBW HBIOS Presence
	CALL	HBIOS_DETECT
	JR	Z,INIT_SUCCESS

	; Not HBIOS warning
	LD	DE,MSG_NO_HBIOS
	CALL	PRINT_STR

INIT_SUCCESS:
	; Initialize Buffer
	CALL	BUFFER_INIT

	; Render Initial Screen
	CALL	RENDER_SCREEN

MAIN_LOOP:
	CALL	GET_KEY
	CP	KEY_CTRL_Q
	JR	Z,EXIT_PROGRAM

	CP	KEY_CTRL_S
	JR	NZ,NOT_SAVE
	; Save trigger
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
; Screen Renderer
;------------------------------------------------------------------------------
RENDER_SCREEN:
	; Move cursor home
	LD	DE,STR_HOME
	CALL	PRINT_STR

	; Render lines
	LD	B,SCREEN_ROWS-1
	LD	C,0			; Row counter
RENDER_ROW_LOOP:
	PUSH	BC
	LD	A,C
	LD	(CUR_RENDER_ROW),A
	CALL	RENDER_SINGLE_LINE
	POP	BC
	INC	C
	DJNZ	RENDER_ROW_LOOP

	; Render Status Bar (Row 24)
	CALL	RENDER_STATUS_BAR

	; Move cursor to current editing position (ROW, COL)
	CALL	LOCATE_CURSOR
	RET

RENDER_SINGLE_LINE:
	; Clear to End of Line
	LD	DE,STR_CLEAR_EOL
	CALL	PRINT_STR

	LD	A,(CUR_RENDER_ROW)
	LD	HL,SAMPLE_TEXT
	OR	A
	JR	NZ,RENDER_EMPTY_LINE

	; Print sample line
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
	; Inverse video
	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR
	LD	DE,STR_STATUS_TEXT
	CALL	PRINT_STR
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	RET

LOCATE_CURSOR:
	; Cursor at Row 1, Col 1
	LD	DE,STR_HOME
	CALL	PRINT_STR
	RET

;------------------------------------------------------------------------------
; Input Handler
;------------------------------------------------------------------------------
HANDLE_INPUT:
	RET

;------------------------------------------------------------------------------
; Buffer & RomWBW HBIOS Far Memory Banking
;------------------------------------------------------------------------------
BUFFER_INIT:
	; Query current user bank
	LD	B,0F3H			; SYSGETBNK
	RST	08H
	LD	A,C
	LD	(CPM_USER_BANK),A
	RET

HBIOS_DETECT:
	LD	B,0F8H			; CIOCNT
	LD	C,000H
	RST	08H
	OR	A			; A=0 on success
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

STR_STATUS_TEXT:
	.DB	" SE v0.1.0 | RomWBW Z80 Screen Editor | ^S: Save | ^Q: Quit               ","$"

MSG_NO_HBIOS:
	.DB	"Notice: RomWBW HBIOS not detected.",13,10,"$"

MSG_EXIT:
	.DB	27,"[24;1H",27,"[0m",13,10,"Exiting SE.COM. Returned to CP/M.",13,10,"$"

SAMPLE_TEXT:
	.DB	"; RomWBW Full-Screen Editor (SE.COM) Active Buffer",0

;------------------------------------------------------------------------------
; Variables & Stack Area
;------------------------------------------------------------------------------
SAVED_SP:	.DW	0
CPM_USER_BANK:	.DB	0
CUR_ROW:	.DB	0
CUR_COL:	.DB	0
CUR_RENDER_ROW:	.DB	0

		.DS	128
LOCAL_STACK:

	.END
