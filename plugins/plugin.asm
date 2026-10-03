;==============================================================================
; PLUGIN.ASM - Far RAM Plugin Manager & Context Pop-up Subsystem for SE.COM
; Digital Research CP/M 3 Page-Relocatable (.PRL) Format
;
; Implements:
;   Action 0: Interactive Full-Screen Plugin Manager (SHOW_PLUGIN_SCREEN)
;             Slot table (0..7), size classes, exec modes, dynamic load/unload
;   Action 1: Context-Aware Pop-up Engine (DO_CONTEXT_POPUP for Ctrl+P)
;             Dynamic capability filtering, 50-col centered modal box
;   Action 2: Modal About Screen for PLUGIN.PRL
;
; Entry:
;   IX = Pointer to PLUGIN_HOST_API vector (or IY if Far RAM bankcall)
; Returns:
;   CY = 0: Action selected: A = Slot number (0..7), C = Action index (0..2)
;   CY = 1: Cancelled / dismissed / exit
;==============================================================================

	ORG	0100H

; Context Identifiers (synchronized with SE.COM)
PLUG_CTX_EDITOR		EQU	0
PLUG_CTX_SPLASH		EQU	1
PLUG_CTX_CONFIG		EQU	2
PLUG_CTX_MEM_INFO	EQU	3
PLUG_CTX_PLUGIN_MGR	EQU	4
PLUG_CTX_HELP		EQU	5
PLUG_CTX_ABOUT		EQU	6

;------------------------------------------------------------------------------
; Standard Jump Table
;------------------------------------------------------------------------------
ENTRY:
	JP	DO_PLUGIN_MANAGER	; +0: Action 0 (Full-Screen Plugin Manager)
	JP	DO_CONTEXT_POPUP	; +3: Action 1 (Context-Aware Pop-up Modal)
	JP	DO_PLUGIN_ABOUT		; +6: Action 2 (Plugin Manager About Dialog)
	JP	DO_AUTOLOAD_PLUGINS	; +9: Action 3 (Autoload from PLUGIN.CFG)

DO_AUTOLOAD_PLUGINS:
	CALL	INIT_HOST_API
	RET	C

	LD	A,(AUTOLOAD_DONE)
	OR	A
	RET	NZ
	LD	A,1
	LD	(AUTOLOAD_DONE),A

	; Guarantee null sentinel at end of buffer
	XOR	A
	LD	(CFG_BUF_SENTINEL),A

	; Call HOST_LOAD_PLUGIN_CFG with DE = PLUGIN_CFG_BUF
	LD	DE,PLUGIN_CFG_BUF
	CALL	HOST_LOAD_PLUGIN_CFG
	RET	C			; If file not found or read error, done

	; Parse lines in PLUGIN_CFG_BUF
	LD	HL,PLUGIN_CFG_BUF
	JR	DAP_LINE_LOOP

DAP_SKIP_CHAR:
	INC	HL
DAP_LINE_LOOP:
	LD	A,(HL)
	OR	A
	RET	Z			; Null byte = end of buffer
	CP	1AH
	RET	Z			; CP/M EOF = end of buffer
	CP	13			; CR
	JR	Z,DAP_SKIP_CHAR
	CP	10			; LF
	JR	Z,DAP_SKIP_CHAR
	CP	' '
	JR	Z,DAP_SKIP_CHAR
	CP	9			; Tab
	JR	Z,DAP_SKIP_CHAR

	; Check if line begins with "SLOT" or "slot"
	CP	'S'
	JR	Z,DAP_CHECK_SLOT
	CP	's'
	JR	NZ,DAP_PARSE_NAME

DAP_CHECK_SLOT:
	PUSH	HL			; Save line start
	INC	HL
	LD	A,(HL)
	CP	'L'
	JR	Z,DAP_CS_1
	CP	'l'
	JR	NZ,DAP_NOT_SLOT
DAP_CS_1:
	INC	HL
	LD	A,(HL)
	CP	'O'
	JR	Z,DAP_CS_2
	CP	'o'
	JR	NZ,DAP_NOT_SLOT
DAP_CS_2:
	INC	HL
	LD	A,(HL)
	CP	'T'
	JR	Z,DAP_CS_3
	CP	't'
	JR	NZ,DAP_NOT_SLOT
DAP_CS_3:
	INC	HL
	; Optional slot digit '0'..'7'
	LD	A,(HL)
	CP	'0'
	JR	C,DAP_CS_EQ
	CP	'8'
	JR	NC,DAP_CS_EQ
	INC	HL
DAP_CS_EQ:
	LD	A,(HL)
	CP	'='
	JR	NZ,DAP_NOT_SLOT
	INC	HL			; Skip '='
	POP	AF			; Discard saved line start
	JP	DAP_LINE_LOOP

DAP_NOT_SLOT:
	POP	HL			; Restore line start

DAP_PARSE_NAME:
	; HL points to start of plugin filename
	LD	A,(HL)
	CP	13
	JR	Z,DAP_SKIP_CHAR
	CP	10
	JR	Z,DAP_SKIP_CHAR
	CP	1AH
	RET	Z
	OR	A
	RET	Z

	; Non-empty filename found! DE = HL
	LD	DE,HL
DAP_SCAN_NAME_END:
	LD	A,(HL)
	OR	A
	JR	Z,DAP_NAME_DELIM
	CP	1AH
	JR	Z,DAP_NAME_DELIM
	CP	13
	JR	Z,DAP_NAME_DELIM
	CP	10
	JR	Z,DAP_NAME_DELIM
	CP	' '
	JR	Z,DAP_NAME_DELIM
	CP	9
	JR	Z,DAP_NAME_DELIM
	INC	HL
	JR	DAP_SCAN_NAME_END

DAP_NAME_DELIM:
	LD	B,(HL)
	XOR	A
	LD	(HL),A			; Null-terminate filename
	LD	A,B
	OR	A
	JR	Z,DAP_LOAD_ENTRY
	CP	1AH
	JR	Z,DAP_LOAD_ENTRY
	INC	HL

DAP_LOAD_ENTRY:
	PUSH	HL			; Preserve buffer pointer
	CALL	HOST_LOAD_PLUGIN	; DE = filename
	POP	HL
	JP	DAP_LINE_LOOP

DO_SAVE_PLUGIN_CFG:
	; Clear local PLUGIN_CFG_BUF (128 bytes) with 1AH (EOF)
	LD	HL,PLUGIN_CFG_BUF
	LD	(HL),1AH
	LD	DE,PLUGIN_CFG_BUF+1
	LD	BC,127
	LDIR
	LD	DE,PLUGIN_CFG_BUF	; DE = destination write pointer

	; Get pointer to PLUGIN_REGISTRY (HOST_API + 44)
	LD	HL,(HOST_API_PTR)
	LD	BC,44
	ADD	HL,BC
	LD	A,(HL)
	INC	HL
	LD	H,(HL)
	LD	L,A			; HL = PLUGIN_REGISTRY
	LD	(PLUG_REG_PTR),HL

	; Loop over slots 0..7
	LD	B,0			; B = slot 0..7
DSP_SLOT_LOOP:
	PUSH	BC

	; Write "SLOT"
	LD	A,'S'
	LD	(DE),A
	INC	DE
	LD	A,'L'
	LD	(DE),A
	INC	DE
	LD	A,'O'
	LD	(DE),A
	INC	DE
	LD	A,'T'
	LD	(DE),A
	INC	DE

	; Write slot digit '0'..'7'
	LD	A,B
	ADD	A,'0'
	LD	(DE),A
	INC	DE

	; Write '='
	LD	A,'='
	LD	(DE),A
	INC	DE

	; Calculate slot ptr: PLUG_REG_PTR + B * 32
	LD	HL,(PLUG_REG_PTR)
	LD	A,B
	ADD	A,A			; * 2
	ADD	A,A			; * 4
	ADD	A,A			; * 8
	ADD	A,A			; * 16
	ADD	A,A			; * 32
	LD	C,A
	LD	B,0
	ADD	HL,BC			; HL = slot entry ptr

	; Check if slot is loaded: offset 22 (SLOT_STATE != 0)
	PUSH	HL
	LD	BC,22
	ADD	HL,BC
	LD	A,(HL)
	POP	HL
	OR	A
	JR	Z,DSP_EMIT_EOL		; If empty, jump straight to emitting CRLF

	; Copy plugin name (up to 8 chars or until null/space)
	PUSH	HL
	LD	B,8
DSP_NAME_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,DSP_NAME_END
	CP	' '
	JR	Z,DSP_NAME_END
	LD	(DE),A
	INC	DE
	INC	HL
	DJNZ	DSP_NAME_LOOP
DSP_NAME_END:
	POP	HL
	LD	A,'.'
	LD	(DE),A
	INC	DE

	; Determine extension (.OVL or .PRL)
	PUSH	HL
	LD	BC,28
	ADD	HL,BC
	LD	A,(HL)			; Extension char at +28
	CP	'O'
	JR	Z,DSP_EXT_OVL
	POP	HL
	PUSH	HL
	LD	BC,18
	ADD	HL,BC
	LD	A,(HL)
	INC	HL
	OR	(HL)
	JR	NZ,DSP_EXT_OVL
	POP	HL
	LD	A,'P'
	LD	(DE),A
	INC	DE
	LD	A,'R'
	LD	(DE),A
	INC	DE
	JR	DSP_EXT_COMMON
DSP_EXT_OVL:
	POP	HL
	LD	A,'O'
	LD	(DE),A
	INC	DE
	LD	A,'V'
	LD	(DE),A
	INC	DE
DSP_EXT_COMMON:
	LD	A,'L'
	LD	(DE),A
	INC	DE

DSP_EMIT_EOL:
	LD	A,13
	LD	(DE),A
	INC	DE
	LD	A,10
	LD	(DE),A
	INC	DE

DSP_NEXT_SLOT:
	POP	BC
	INC	B
	LD	A,B
	CP	8
	JP	NZ,DSP_SLOT_LOOP

	; Call HOST_SAVE_PLUGIN_CFG with DE = PLUGIN_CFG_BUF
	LD	DE,PLUGIN_CFG_BUF
	CALL	HOST_SAVE_PLUGIN_CFG
	RET

;==============================================================================
; Action 0: Full-Screen Interactive Plugin Manager
;==============================================================================
DO_PLUGIN_MANAGER:
	CALL	INIT_HOST_API
	JP	C,INIT_ERR

	; Preserve SELECTED_SLOT if valid (< 8) across internal action returns
	LD	A,(SELECTED_SLOT)
	CP	8
	JR	C,DPM_SLOT_OK
	XOR	A
	LD	(SELECTED_SLOT),A
DPM_SLOT_OK:

DO_PLUG_REDRAW:
	CALL	RENDER_PLUGIN_SCREEN

PLUG_KEY_LOOP:
	CALL	HOST_GET_KEY
	CP	27			; ESC
	JP	Z,PLUG_HANDLE_ESC

	; Command: Ctrl+P -> Open Context Pop-up inside Plugin Manager
	CP	16			; Ctrl+P
	JR	NZ,PKL_NOT_CTRL_P
	LD	A,PLUG_CTX_PLUGIN_MGR
	LD	(HOST_CONTEXT_ID),A
	CALL	DO_CONTEXT_POPUP_INTERNAL
	JR	C,DO_PLUG_REDRAW	; If cancelled, redraw Plugin Manager
	; Child action selected: return slot in A, action in C, CY=0
	OR	A
	RET

PKL_NOT_CTRL_P:
	CP	5			; Ctrl+E (Up)
	JP	Z,PLUG_PREV_SLOT
	CP	24			; Ctrl+X (Down)
	JP	Z,PLUG_NEXT_SLOT
	CP	13			; Enter
	JP	Z,PLUG_DO_ENTER

	; Convert lowercase to uppercase for letter commands
	CP	'a'
	JR	C,PKL_NOT_LOWER
	CP	'z'+1
	JR	NC,PKL_NOT_LOWER
	SUB	32
PKL_NOT_LOWER:
	CP	'K'
	JP	Z,PLUG_PREV_SLOT
	CP	'J'
	JP	Z,PLUG_NEXT_SLOT
	CP	'Q'
	JP	Z,PKL_EXIT
	CP	'A'
	JP	Z,PLUG_DO_ABOUT
	CP	'C'
	JP	Z,PLUG_DO_CONFIG
	CP	'L'
	JP	Z,PKL_DO_L
	CP	'U'
	JP	Z,PKL_DO_U
	CP	'S'
	JP	Z,PKL_DO_S

	; Slot action: '0'..'7'
	CP	'0'
	JR	C,PLUG_KEY_LOOP
	CP	'8'
	JR	NC,PLUG_KEY_LOOP
	SUB	'0'
	LD	(SELECTED_SLOT),A
	JP	PLUG_DO_ENTER

PKL_DO_L:
	LD	A,(FPSL_LOADED_CNT)
	CP	8
	JR	NZ,PKL_DO_L_OPEN
	LD	DE,STR_PLUG_FULL_TITLE
	LD	HL,STR_PLUG_FULL_MSG
	CALL	SHOW_ALERT_POPUP
	JP	DO_PLUG_REDRAW

PKL_DO_L_OPEN:
	CALL	PROMPT_LOAD_PLUGIN
	JP	DO_PLUG_REDRAW

PKL_DO_U:
	LD	A,(SELECTED_SLOT)
	CALL	GET_SLOT_ENTRY_PTR
	LD	DE,22
	ADD	HL,DE
	LD	A,(HL)			; SLOT_STATE
	OR	A
	JP	Z,PLUG_KEY_LOOP		; Slot empty -> ignore
	CALL	CONFIRM_UNLOAD_SLOT
	JP	DO_PLUG_REDRAW

PLUG_DO_ENTER:
	LD	A,(SELECTED_SLOT)
	CALL	GET_SLOT_ENTRY_PTR
	LD	DE,22
	ADD	HL,DE
	LD	A,(HL)			; SLOT_STATE: 0 = Free, 1 = Ready
	OR	A
	JR	NZ,PDE_OCCUPIED

	; Free slot -> Load plugin
	CALL	PROMPT_LOAD_PLUGIN
	JP	DO_PLUG_REDRAW

PDE_OCCUPIED:
	; Occupied slot -> Confirm Unload
	CALL	CONFIRM_UNLOAD_SLOT
	JP	DO_PLUG_REDRAW

PKL_DO_S:
	CALL	DO_SAVE_PLUGIN_CFG
	CALL	SHOW_SAVE_CFG_POPUP
	CP	27			; ESC?
	JR	NZ,PKL_S_NOT_ESC
	CALL	DRAIN_ESC_SEQUENCE
	JP	DO_PLUG_REDRAW
PKL_S_NOT_ESC:
	CP	'q'
	JP	Z,PKL_EXIT
	CP	'Q'
	JP	Z,PKL_EXIT
	JP	DO_PLUG_REDRAW

PLUG_PREV_SLOT:
	LD	A,(SELECTED_SLOT)
	DEC	A
	AND	07H
	LD	(SELECTED_SLOT),A
	JP	DO_PLUG_REDRAW

PLUG_NEXT_SLOT:
	LD	A,(SELECTED_SLOT)
	INC	A
	AND	07H
	LD	(SELECTED_SLOT),A
	JP	DO_PLUG_REDRAW

PLUG_HANDLE_ESC:
	LD	BC,1000
PHE_WAIT:
	CALL	HOST_CHECK_KEY
	JR	NZ,PHE_GOT_BYTE
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,PHE_WAIT
	JP	PKL_EXIT

PHE_GOT_BYTE:
	CALL	HOST_GET_KEY
	CP	'['
	JR	Z,PHE_CSI
	CP	'O'
	JR	Z,PHE_CSI
	CALL	DRAIN_ESC_SEQUENCE
	JP	PLUG_KEY_LOOP

PHE_CSI:
	CALL	HOST_GET_KEY
	CP	'A'			; Up Arrow
	JP	Z,PLUG_PREV_SLOT
	CP	'B'			; Down Arrow
	JP	Z,PLUG_NEXT_SLOT
	CALL	DRAIN_ESC_SEQUENCE
	JP	PLUG_KEY_LOOP

PLUG_DO_ABOUT:
	LD	A,(SELECTED_SLOT)
	CALL	GET_SLOT_ENTRY_PTR
	LD	DE,22
	ADD	HL,DE
	LD	A,(HL)
	OR	A
	JP	Z,PLUG_KEY_LOOP		; Empty slot

	; If selected slot is PLUGIN.PRL itself, display local about
	LD	A,(HOST_MGR_SLOT)
	LD	B,A
	LD	A,(SELECTED_SLOT)
	CP	B
	JR	NZ,PDA_CHECK_CAP
	CALL	DO_PLUGIN_ABOUT
	JP	DO_PLUG_REDRAW

PDA_CHECK_CAP:
	DEC	HL
	DEC	HL			; HL = offset +20 (Capabilities low byte)
	LD	A,(HL)
	BIT	4,A			; CAP_HAS_ABOUT (bit 4 = 0x10)
	JR	Z,PLUG_NO_ABOUT

	LD	A,(SELECTED_SLOT)
	LD	C,1			; Action 1: About
	OR	A			; Clear Carry (CY=0)
	RET

PLUG_NO_ABOUT:
	LD	DE,STR_PLUG_NO_ABT_TITLE
	LD	HL,STR_PLUG_NO_ABT_MSG
	CALL	SHOW_ALERT_POPUP
	JP	DO_PLUG_REDRAW

PLUG_DO_CONFIG:
	LD	A,(SELECTED_SLOT)
	CALL	GET_SLOT_ENTRY_PTR
	LD	DE,22
	ADD	HL,DE
	LD	A,(HL)
	OR	A
	JP	Z,PLUG_KEY_LOOP		; Empty slot

	DEC	HL
	DEC	HL			; HL = offset +20 (Capabilities low byte)
	LD	A,(HL)
	BIT	5,A			; CAP_HAS_CONFIG (bit 5 = 0x20)
	JR	Z,PLUG_NO_CONFIG

	LD	A,(SELECTED_SLOT)
	LD	C,2			; Action 2: Config
	OR	A			; Clear Carry (CY=0)
	RET

PLUG_NO_CONFIG:
	LD	DE,STR_PLUG_NO_CFG_TITLE
	LD	HL,STR_PLUG_NO_CFG_MSG
	CALL	SHOW_ALERT_POPUP
	JP	DO_PLUG_REDRAW

PKL_EXIT:
	XOR	A
	LD	(SELECTED_SLOT),A
	SCF				; Carry = 1 (Exit / dismissed)
	RET

;------------------------------------------------------------------------------
; Render Full Plugin Manager Screen
;------------------------------------------------------------------------------
RENDER_PLUGIN_SCREEN:
	LD	DE,STR_HIDE_CURSOR
	CALL	HOST_PRINT_STR
	LD	DE,STR_CLEAR_SCREEN
	CALL	HOST_PRINT_STR

	; Row 1: Fixed centered Header
	LD	DE,STR_PLUG_TITLE
	CALL	PRINT_ABOUT_LINE

	; Row 2: Blank line
	CALL	PRINT_TILDE_CRLF

	; Row 3: System information line
	CALL	FORMAT_PLUGIN_SYS_LINE
	LD	DE,SCRATCH_BUF
	CALL	PRINT_ABOUT_LINE

	; Row 4: Blank line
	CALL	PRINT_TILDE_CRLF

	; Row 5: Table Header
	LD	DE,STR_PLUG_HDR
	CALL	PRINT_ABOUT_LINE

	; Row 6: Table Separator
	LD	DE,STR_PLUG_SEP
	CALL	PRINT_ABOUT_LINE

	; Rows 7..14: Slot Rows 0..7
	LD	B,0
RPS_ROW_LOOP:
	PUSH	BC
	CALL	FORMAT_PLUGIN_SLOT_ROW
	LD	DE,SCRATCH_BUF
	CALL	PRINT_ABOUT_LINE
	POP	BC
	INC	B
	LD	A,B
	CP	8
	JR	NZ,RPS_ROW_LOOP

	; Pad margin rows down to HOST_ROWS - 2
	; Rows 1..14 are header and body (14 rows)
	; Footer is on row HOST_ROWS - 1, Status bar on row HOST_ROWS
	; Number of margin rows = (HOST_ROWS - 2) - 14 = HOST_ROWS - 16
	LD	A,(HOST_ROWS)
	SUB	16
	JR	Z,RPS_FOOTER
	JR	C,RPS_FOOTER
	LD	B,A
RPS_MARGIN_LOOP:
	CALL	PRINT_TILDE_CRLF
	DJNZ	RPS_MARGIN_LOOP

RPS_FOOTER:
	; Row HOST_ROWS - 1: Fixed Footer command summary line
	CALL	FORMAT_PLUGIN_FOOTER
	CALL	PRINT_ABOUT_LINE

	; Row HOST_ROWS: Persistent Status bar
	CALL	HOST_RENDER_STATUS_BAR
	RET

LOCATE_STATUS_ROW:
	LD	A,(HOST_ROWS)
	LD	H,A
	LD	L,1
	CALL	HOST_LOCATE_RC
	RET

;------------------------------------------------------------------------------
; Format Footer Line for Selected Slot
;------------------------------------------------------------------------------
FORMAT_PLUGIN_FOOTER:
	LD	A,(SELECTED_SLOT)
	CALL	GET_SLOT_ENTRY_PTR
	LD	BC,22
	ADD	HL,BC
	LD	A,(HL)
	OR	A
	JR	NZ,FPF_LOADED

	; Slot empty
	LD	HL,STR_PLUG_CMDS_EMPTY
	JR	FPF_FINISH

FPF_LOADED:
	DEC	HL
	DEC	HL			; HL = offset +20 (Capabilities low byte)
	LD	A,(HL)
	BIT	4,A			; CAP_HAS_ABOUT
	JR	Z,FPF_NO_ABOUT

	BIT	5,A			; CAP_HAS_CONFIG
	JR	Z,FPF_ABOUT_ONLY

	LD	HL,STR_PLUG_CMDS_BOTH
	JR	FPF_FINISH

FPF_ABOUT_ONLY:
	LD	HL,STR_PLUG_CMDS_ABOUT
	JR	FPF_FINISH

FPF_NO_ABOUT:
	BIT	5,A			; CAP_HAS_CONFIG
	JR	Z,FPF_NEITHER
	LD	HL,STR_PLUG_CMDS_CONFIG
	JR	FPF_FINISH

FPF_NEITHER:
	LD	HL,STR_PLUG_CMDS_PLAIN

FPF_FINISH:
	PUSH	HL			; Preserve selected context string
	LD	DE,SCRATCH_BUF
	LD	HL,STR_PLUG_CMDS_PRE
	CALL	COPY_STR_Z
	POP	HL			; Restore selected context string
	CALL	COPY_STR_Z
	XOR	A
	LD	(DE),A
	LD	DE,SCRATCH_BUF
	RET

;------------------------------------------------------------------------------
; Format System Info Line
;------------------------------------------------------------------------------
FORMAT_PLUGIN_SYS_LINE:
	LD	DE,SCRATCH_BUF
	LD	HL,STR_PLUG_SYS_PRE
	CALL	COPY_STR_Z

	; Scan registry for any active Far RAM bank and count loaded slots
	LD	B,0
	LD	C,0			; C = loaded count
	XOR	A
	LD	(FPSL_BANK_FOUND),A

FPSL_SCAN_LOOP:
	PUSH	BC
	LD	A,B
	CALL	GET_SLOT_ENTRY_PTR
	LD	DE,22
	ADD	HL,DE
	LD	A,(HL)			; SLOT_STATE
	OR	A
	JR	Z,FPSL_NEXT_SLOT

	POP	BC
	INC	C			; loaded count++
	PUSH	BC

	INC	HL
	INC	HL			; HL = offset +24 (FAR_BANK)
	LD	A,(HL)
	OR	A
	JR	Z,FPSL_NEXT_SLOT
	LD	(FPSL_BANK_FOUND),A

FPSL_NEXT_SLOT:
	POP	BC
	INC	B
	LD	A,B
	CP	8
	JR	NZ,FPSL_SCAN_LOOP

	LD	A,C
	LD	(FPSL_LOADED_CNT),A

	; Check if bank found
	LD	DE,SCRATCH_BUF+10	; after "Far RAM: ["
	LD	A,(FPSL_BANK_FOUND)
	OR	A
	JR	NZ,FPSL_HAS_BANK

	LD	HL,STR_PLUG_SYS_DYN
	CALL	COPY_STR_Z
	JR	FPSL_EMIT_COUNT

FPSL_HAS_BANK:
	LD	HL,STR_PLUG_SYS_BNK
	CALL	COPY_STR_Z
	LD	A,(FPSL_BANK_FOUND)
	CALL	FORMAT_HEX_BYTE_DE
	LD	HL,STR_PLUG_SYS_MID
	CALL	COPY_STR_Z

FPSL_EMIT_COUNT:
	LD	A,(FPSL_LOADED_CNT)
	ADD	A,'0'
	LD	(DE),A
	INC	DE
	LD	HL,STR_PLUG_SYS_POST
	CALL	COPY_STR_Z
	XOR	A
	LD	(DE),A
	RET

;------------------------------------------------------------------------------
; Format Slot Row B (0..7)
;------------------------------------------------------------------------------
FORMAT_PLUGIN_SLOT_ROW:
	LD	A,B
	CALL	GET_SLOT_ENTRY_PTR
	PUSH	HL

	LD	DE,SCRATCH_BUF
	LD	A,(SELECTED_SLOT)
	CP	B
	LD	A,' '
	JR	NZ,FPSR_NOT_SELECTED
	LD	A,'>'
FPSR_NOT_SELECTED:
	LD	(DE),A
	INC	DE
	LD	A,'['
	LD	(DE),A
	INC	DE
	LD	A,B
	ADD	A,'0'
	LD	(DE),A
	INC	DE
	LD	A,']'
	LD	(DE),A
	INC	DE
	LD	A,' '
	LD	(DE),A
	INC	DE

FPSR_SLOT_DONE:
	POP	HL
	PUSH	HL
	LD	BC,22
	ADD	HL,BC
	LD	A,(HL)
	OR	A
	JR	NZ,FPSR_LOADED

	POP	HL
	LD	HL,STR_PLUG_EMPTY_ROW
	CALL	COPY_STR_Z
	XOR	A
	LD	(DE),A
	RET

FPSR_LOADED:
	POP	HL
	PUSH	HL

	; Name (16 chars)
	LD	B,16
FPSR_NAME_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,FPSR_NAME_PAD
	LD	(DE),A
	INC	HL
	INC	DE
	DJNZ	FPSR_NAME_LOOP
	JR	FPSR_NAME_DONE
FPSR_NAME_PAD:
	LD	A,' '
	LD	(DE),A
	INC	DE
	DJNZ	FPSR_NAME_PAD
FPSR_NAME_DONE:
	LD	A,' '
	LD	(DE),A
	INC	DE

	; Type
	POP	HL
	PUSH	HL
	LD	BC,18
	ADD	HL,BC
	LD	A,(HL)
	INC	HL
	OR	(HL)
	JR	NZ,FPSR_TYPE_OVL
	LD	HL,STR_PLUG_TYPE_PRL
	CALL	COPY_STR_Z
	JR	FPSR_TYPE_DONE
FPSR_TYPE_OVL:
	LD	HL,STR_PLUG_TYPE_OVL
	CALL	COPY_STR_Z
FPSR_TYPE_DONE:
	LD	A,' '
	LD	(DE),A
	INC	DE

	; Size
	POP	HL
	PUSH	HL
	LD	BC,16
	ADD	HL,BC
	LD	C,(HL)
	INC	HL
	LD	B,(HL)
	LD	L,C
	LD	H,B
	CALL	FORMAT_DEC_WORD_BUF
	LD	A,'B'
	LD	(DE),A
	INC	DE
	LD	A,' '
	LD	(DE),A
	INC	DE
	LD	(DE),A
	INC	DE

	; Exec Mode
	POP	HL
	PUSH	HL
	LD	BC,23
	ADD	HL,BC
	LD	A,(HL)			; Offset +23: EXEC_MODE (0=TPA, 1=FAR)
	OR	A
	JR	NZ,FPSR_MODE_FAR_SZ
	LD	HL,STR_PLUG_MODE_TPA4
	CALL	COPY_STR_Z
	JR	FPSR_MODE_DONE
FPSR_MODE_FAR_SZ:
	INC	HL
	INC	HL
	INC	HL			; Offset +26: SIZE_CLASS
	LD	A,(HL)
	OR	A
	JR	NZ,FPSR_FAR_NOT_4K
	LD	HL,STR_PLUG_MODE_FAR4
	CALL	COPY_STR_Z
	JR	FPSR_MODE_DONE
FPSR_FAR_NOT_4K:
	CP	1
	JR	NZ,FPSR_FAR_NOT_8K
	LD	HL,STR_PLUG_MODE_FAR8
	CALL	COPY_STR_Z
	JR	FPSR_MODE_DONE
FPSR_FAR_NOT_8K:
	CP	2
	JR	NZ,FPSR_FAR_32K
	LD	HL,STR_PLUG_MODE_FAR16
	CALL	COPY_STR_Z
	JR	FPSR_MODE_DONE
FPSR_FAR_32K:
	LD	HL,STR_PLUG_MODE_FAR32
	CALL	COPY_STR_Z
FPSR_MODE_DONE:
	LD	A,' '
	LD	(DE),A
	INC	DE

	; Capabilities
	POP	HL
	PUSH	HL
	LD	BC,20
	ADD	HL,BC
	LD	A,(HL)
	BIT	3,A			; CAP_MODAL_UI
	JR	Z,FPSR_NOT_MODAL
	LD	HL,STR_CAP_MODAL_FAR
	CALL	COPY_STR_Z
	JR	FPSR_CAPS_DONE
FPSR_NOT_MODAL:
	BIT	2,A			; CAP_DOC_MUTATE
	JR	Z,FPSR_NOT_MUTATE
	LD	HL,STR_CAP_MUTATE_TPA
	CALL	COPY_STR_Z
	JR	FPSR_CAPS_DONE
FPSR_NOT_MUTATE:
	LD	HL,STR_CAP_DEFAULT
	CALL	COPY_STR_Z
FPSR_CAPS_DONE:
	LD	A,' '
	LD	(DE),A
	INC	DE

	LD	HL,STR_PLUG_STAT_READY
	CALL	COPY_STR_Z

	POP	HL
	XOR	A
	LD	(DE),A
	RET

;------------------------------------------------------------------------------
; Prompt: Load Plugin via Host Open File UI
;------------------------------------------------------------------------------
PROMPT_LOAD_PLUGIN:
	CALL	HOST_OPEN_PLUGIN_UI
	RET	C			; Cancelled -> retain selection
	LD	(SELECTED_SLOT),A	; Highlight newly loaded slot
	RET

;------------------------------------------------------------------------------
; Modal Pop-up: Confirmation to Unload Selected Slot
;------------------------------------------------------------------------------
CONFIRM_UNLOAD_SLOT:
	LD	DE,STR_HIDE_CURSOR
	CALL	HOST_PRINT_STR

	; Center 7-line dialog box vertically: ((HOST_ROWS - 7) / 2) + 1
	LD	A,(HOST_ROWS)
	SUB	7
	SRL	A
	INC	A
	LD	(POPUP_ROW),A

	; Center 50-col box horizontally: ((HOST_COLS - 50) / 2) + 1
	LD	A,(HOST_COLS)
	SUB	50
	SRL	A
	INC	A
	LD	(POPUP_COL),A

	; Line 1: Border
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	HOST_PRINT_STR

	; Line 2: Title
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_UNLOAD_TITLE
	CALL	HOST_PRINT_STR

	; Line 3: Border
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	HOST_PRINT_STR

	; Line 4: Description
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_UNLOAD_DESC
	CALL	HOST_PRINT_STR

	; Line 5: Confirmation prompt with slot number
	CALL	POPUP_LOCATE_NEXT
	CALL	FORMAT_UNLOAD_PROMPT
	LD	DE,SCRATCH_BUF
	CALL	HOST_PRINT_STR

	; Line 6: Instructions / Keys
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_UNLOAD_KEYS
	CALL	HOST_PRINT_STR

	; Line 7: Border
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	HOST_PRINT_STR

	; Position cursor inside popup on prompt line after "Unload Slot N? "
	; Row = (POPUP_ROW) - 3, Col = (POPUP_COL) + 32
	LD	A,(POPUP_ROW)
	SUB	3
	LD	H,A
	LD	A,(POPUP_COL)
	ADD	A,32
	LD	L,A
	CALL	HOST_LOCATE_RC
	LD	DE,STR_SHOW_CURSOR
	CALL	HOST_PRINT_STR

CUS_KEY_LOOP:
	CALL	HOST_GET_KEY
	CP	27			; ESC
	JR	NZ,CUS_NOT_ESC
	CALL	DRAIN_ESC_SEQUENCE
	LD	DE,STR_HIDE_CURSOR
	CALL	HOST_PRINT_STR
	RET
CUS_NOT_ESC:
	CP	'y'
	JR	Z,CUS_CONFIRMED
	CP	'Y'
	JR	Z,CUS_CONFIRMED
	CP	13			; Enter confirms
	JR	Z,CUS_CONFIRMED
	CP	'n'
	JR	Z,CUS_CANCELLED
	CP	'N'
	JR	Z,CUS_CANCELLED
	JR	CUS_KEY_LOOP

CUS_CANCELLED:
	LD	DE,STR_HIDE_CURSOR
	CALL	HOST_PRINT_STR
	RET

CUS_CONFIRMED:
	LD	DE,STR_HIDE_CURSOR
	CALL	HOST_PRINT_STR
	LD	A,(SELECTED_SLOT)
	CALL	HOST_UNLOAD_SLOT
	RET

FORMAT_UNLOAD_PROMPT:
	LD	DE,SCRATCH_BUF
	LD	HL,STR_UNLOAD_PROMPT_PRE
	CALL	COPY_STR_Z
	LD	A,(SELECTED_SLOT)
	ADD	A,'0'
	LD	(DE),A
	INC	DE
	LD	HL,STR_UNLOAD_PROMPT_POST
	CALL	COPY_STR_Z
	XOR	A
	LD	(DE),A
	RET

;==============================================================================
; Action 1: Context-Aware Pop-up Modal Subsystem
;==============================================================================
DO_CONTEXT_POPUP:
	CALL	INIT_HOST_API
	JP	C,INIT_ERR

DO_CONTEXT_POPUP_INTERNAL:
	; Reset match count
	XOR	A
	LD	(POPUP_MATCH_COUNT),A

	; Scan PLUGIN_REGISTRY slots 0..7
	LD	B,0
DCPP_SCAN_LOOP:
	; If slot B is HOST_MGR_SLOT, skip it!
	LD	A,(HOST_MGR_SLOT)
	CP	B
	JR	Z,DCPP_NEXT_SLOT

	LD	A,B
	CALL	GET_SLOT_ENTRY_PTR
	LD	DE,22
	ADD	HL,DE
	LD	A,(HL)			; SLOT_STATE (0=free, 1=loaded)
	OR	A
	JR	Z,DCPP_NEXT_SLOT

	DEC	HL
	DEC	HL
	LD	C,(HL)			; C = Capabilities low byte (Offset +20)

	LD	A,(HOST_CONTEXT_ID)
	CP	0			; PLUG_CTX_EDITOR
	JR	NZ,DCPP_CHK_CONFIG
	; Editor screen: CAP_DOC_MUTATE (04h) or CAP_MODAL_UI (08h)
	LD	A,C
	AND	0CH
	JR	Z,DCPP_NEXT_SLOT
	JR	DCPP_RECORD_SLOT

DCPP_CHK_CONFIG:
	CP	2			; PLUG_CTX_CONFIG
	JR	NZ,DCPP_CHK_MEM
	; Config screen: CAP_HAS_CONFIG (20h)
	LD	A,C
	AND	20H
	JR	Z,DCPP_NEXT_SLOT
	JR	DCPP_RECORD_SLOT

DCPP_CHK_MEM:
	CP	3			; PLUG_CTX_MEM_INFO
	JR	NZ,DCPP_CHK_HELP
	; Mem Info screen: CAP_FAR_EXEC (02h)
	LD	A,C
	AND	02H
	JR	Z,DCPP_NEXT_SLOT
	JR	DCPP_RECORD_SLOT

DCPP_CHK_HELP:
	CP	PLUG_CTX_HELP
	JR	Z,DCPP_IS_HELP
	CP	PLUG_CTX_ABOUT
	JR	NZ,DCPP_RECORD_SLOT	; Splash (1) / Plugin Mgr (4) -> matches all
DCPP_IS_HELP:
	; Help / About screen: CAP_HAS_ABOUT (10h)
	LD	A,C
	AND	10H
	JR	Z,DCPP_NEXT_SLOT

DCPP_RECORD_SLOT:
	LD	A,(POPUP_MATCH_COUNT)
	LD	E,A
	LD	D,0
	LD	HL,POPUP_MATCH_SLOTS
	ADD	HL,DE
	LD	(HL),B
	INC	A
	LD	(POPUP_MATCH_COUNT),A

DCPP_NEXT_SLOT:
	INC	B
	LD	A,B
	CP	8
	JR	C,DCPP_SCAN_LOOP

	; Calculate layout coordinates
	; 1. POPUP_COL = ((HOST_COLS - 50) / 2) + 1
	LD	A,(HOST_COLS)
	SUB	50
	SRL	A
	INC	A
	LD	(POPUP_COL),A

	; 2. Total Lines: (MATCH_COUNT == 0) ? 6 : 6 + MATCH_COUNT
	LD	A,(POPUP_MATCH_COUNT)
	OR	A
	JR	NZ,DCPP_HAS_LINES
	LD	A,6
	JR	DCPP_CALC_ROW
DCPP_HAS_LINES:
	ADD	A,6
DCPP_CALC_ROW:
	; POPUP_ROW = ((HOST_ROWS - TotalLines) / 2) + 1
	LD	B,A
	LD	A,(HOST_ROWS)
	SUB	B
	SRL	A
	INC	A
	LD	(POPUP_TOP_ROW),A
	LD	(POPUP_ROW),A

	XOR	A
	LD	(POPUP_SELECTED_INDEX),A

DCPP_DRAW_BOX:
	; Render Modal Box
	LD	DE,STR_HIDE_CURSOR
	CALL	HOST_PRINT_STR

	; Line 1: Top Border
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	HOST_PRINT_STR

	; Line 2: Title Line
	CALL	GET_POPUP_TITLE_PTR
	CALL	PRINT_POPUP_BOXED_LINE

	; Line 3: Top Separator
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	HOST_PRINT_STR

	; Lines 4..: Items or No Match Message
	LD	A,(POPUP_MATCH_COUNT)
	OR	A
	JR	NZ,DCPP_RENDER_ITEMS

	; No matches found
	LD	DE,STR_POPUP_NO_MATCH
	CALL	PRINT_POPUP_BOXED_LINE

	LD	DE,STR_POPUP_PROMPT_NOMATCH
	CALL	PRINT_POPUP_BOXED_LINE

	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	HOST_PRINT_STR

CPK_NOMATCH_KEY_LOOP:
	CALL	HOST_GET_KEY
	CP	27			; ESC
	JR	NZ,CPK_NM_NOT_ESC
	CALL	DRAIN_ESC_SEQUENCE
CPK_NM_NOT_ESC:
	JP	CPKL_DISMISS

DCPP_RENDER_ITEMS:
	LD	C,0			; Match index 0..MATCH_COUNT-1
DCPP_ITEM_LOOP:
	LD	E,C
	LD	D,0
	LD	HL,POPUP_MATCH_SLOTS
	ADD	HL,DE
	LD	A,(HL)			; A = slot number
	PUSH	BC
	CALL	RENDER_POPUP_ITEM_LINE
	POP	BC
	INC	C
	LD	A,(POPUP_MATCH_COUNT)
	CP	C
	JR	NZ,DCPP_ITEM_LOOP

	; Separator after items
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	HOST_PRINT_STR

	; Prompt Line
	LD	DE,STR_POPUP_PROMPT_MATCH
	CALL	PRINT_POPUP_BOXED_LINE

	; Bottom Border
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	HOST_PRINT_STR

CPK_KEY_LOOP:
	CALL	HOST_GET_KEY
	CP	27			; ESC
	JP	Z,CPK_HANDLE_ESC

	CP	16			; Ctrl+P
	JP	Z,CPKL_DISMISS
	CP	5			; Ctrl+E (Up)
	JP	Z,CPK_PREV_ITEM
	CP	24			; Ctrl+X (Down)
	JP	Z,CPK_NEXT_ITEM
	CP	13			; Enter (Execute selected)
	JP	Z,CPK_EXECUTE_CURRENT

	; Lowercase to uppercase
	CP	'a'
	JR	C,CPKL_NOT_LOWER
	CP	'z'+1
	JR	NC,CPKL_NOT_LOWER
	SUB	32
CPKL_NOT_LOWER:
	CP	'K'			; Vi Up
	JP	Z,CPK_PREV_ITEM
	CP	'J'			; Vi Down
	JP	Z,CPK_NEXT_ITEM

	; Digit '0'..'7' selection
	CP	'0'
	JR	C,CPK_KEY_LOOP
	CP	'8'
	JR	NC,CPK_KEY_LOOP

	SUB	'0'
	LD	C,A			; C = slot number
	LD	A,(POPUP_MATCH_COUNT)
	OR	A
	JP	Z,CPK_KEY_LOOP
	LD	B,A
	LD	HL,POPUP_MATCH_SLOTS
	LD	E,0			; E = match index
CPKL_CHK_SLOT:
	LD	A,(HL)
	CP	C
	JR	Z,CPKL_FOUND_SLOT_DIGIT
	INC	HL
	INC	E
	DJNZ	CPKL_CHK_SLOT
	JP	CPK_KEY_LOOP		; Digit not in match list -> ignore

CPKL_FOUND_SLOT_DIGIT:
	LD	A,E
	LD	(POPUP_SELECTED_INDEX),A
	JP	CPK_REDRAW

CPK_PREV_ITEM:
	LD	A,(POPUP_MATCH_COUNT)
	OR	A
	JP	Z,CPK_KEY_LOOP
	LD	B,A			; B = MATCH_COUNT
	LD	A,(POPUP_SELECTED_INDEX)
	OR	A
	JR	NZ,CPI_DEC
	LD	A,B			; Wrap to MATCH_COUNT
CPI_DEC:
	DEC	A
	LD	(POPUP_SELECTED_INDEX),A
	JP	CPK_REDRAW

CPK_NEXT_ITEM:
	LD	A,(POPUP_MATCH_COUNT)
	OR	A
	JP	Z,CPK_KEY_LOOP
	LD	B,A			; B = MATCH_COUNT
	LD	A,(POPUP_SELECTED_INDEX)
	INC	A
	CP	B
	JR	C,CPI_SET_NEXT
	XOR	A			; Wrap to 0
CPI_SET_NEXT:
	LD	(POPUP_SELECTED_INDEX),A
	JP	CPK_REDRAW

CPK_REDRAW:
	LD	A,(POPUP_TOP_ROW)
	LD	(POPUP_ROW),A
	JP	DCPP_DRAW_BOX

CPK_EXECUTE_CURRENT:
	LD	A,(POPUP_MATCH_COUNT)
	OR	A
	JP	Z,CPK_KEY_LOOP
	LD	A,(POPUP_SELECTED_INDEX)
	LD	E,A
	LD	D,0
	LD	HL,POPUP_MATCH_SLOTS
	ADD	HL,DE
	LD	C,(HL)			; C = slot number
	JP	CPKL_FOUND_MATCH

CPKL_DISMISS:
	SCF				; Carry = 1 (dismissed)
	RET

CPK_HANDLE_ESC:
	LD	BC,1000
CPHE_WAIT:
	CALL	HOST_CHECK_KEY
	JR	NZ,CPHE_GOT_BYTE
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,CPHE_WAIT
	JP	CPKL_DISMISS

CPHE_GOT_BYTE:
	CALL	HOST_GET_KEY
	CP	'['
	JR	Z,CPHE_CSI
	CP	'O'
	JR	Z,CPHE_CSI
	CALL	DRAIN_ESC_SEQUENCE
	JP	CPK_KEY_LOOP

CPHE_CSI:
	CALL	HOST_GET_KEY
	CP	'A'			; Up Arrow
	JP	Z,CPK_PREV_ITEM
	CP	'B'			; Down Arrow
	JP	Z,CPK_NEXT_ITEM
	CALL	DRAIN_ESC_SEQUENCE
	JP	CPK_KEY_LOOP

CPKL_FOUND_MATCH:
	; Slot C selected! Determine Action Index (0, 1, or 2)
	LD	A,C
	PUSH	AF			; Save slot number
	LD	A,(HOST_CONTEXT_ID)
	CP	PLUG_CTX_CONFIG
	JR	NZ,CPEF_NOT_CONFIG
	LD	C,2			; Action 2: Config
	JR	CPEF_RETURN
CPEF_NOT_CONFIG:
	CP	PLUG_CTX_HELP
	JR	Z,CPEF_DO_ABOUT
	CP	PLUG_CTX_ABOUT
	JR	NZ,CPEF_NOT_ABOUT
CPEF_DO_ABOUT:
	LD	C,1			; Action 1: About
	JR	CPEF_RETURN
CPEF_NOT_ABOUT:
	LD	C,0			; Action 0: Main Execution
CPEF_RETURN:
	POP	AF			; A = slot number
	OR	A			; Clear Carry (CY=0)
	RET

POPUP_LOCATE_NEXT:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	A,(POPUP_ROW)
	LD	H,A
	LD	A,(POPUP_COL)
	LD	L,A
	CALL	HOST_LOCATE_RC
	LD	HL,POPUP_ROW
	INC	(HL)
	POP	HL
	POP	DE
	POP	BC
	RET

PRINT_POPUP_BOXED_LINE:
	CALL	POPUP_LOCATE_NEXT
	LD	A,'|'
	CALL	HOST_PUTC
	CALL	HOST_PRINT_STR
	LD	A,'|'
	JP	HOST_PUTC

GET_POPUP_TITLE_PTR:
	LD	A,(HOST_CONTEXT_ID)
	CP	PLUG_CTX_EDITOR
	JR	NZ,GPTP_NOT_EDITOR
	LD	DE,STR_TITLE_EDITOR
	RET
GPTP_NOT_EDITOR:
	CP	PLUG_CTX_SPLASH
	JR	NZ,GPTP_NOT_SPLASH
	LD	DE,STR_TITLE_SPLASH
	RET
GPTP_NOT_SPLASH:
	CP	PLUG_CTX_CONFIG
	JR	NZ,GPTP_NOT_CONFIG
	LD	DE,STR_TITLE_CONFIG
	RET
GPTP_NOT_CONFIG:
	CP	PLUG_CTX_MEM_INFO
	JR	NZ,GPTP_NOT_MEM
	LD	DE,STR_TITLE_MEM_INFO
	RET
GPTP_NOT_MEM:
	CP	PLUG_CTX_HELP
	JR	Z,GPTP_HELP
	CP	PLUG_CTX_ABOUT
	JR	Z,GPTP_HELP
	LD	DE,STR_TITLE_PLUGIN_MGR
	RET
GPTP_HELP:
	LD	DE,STR_TITLE_HELP
	RET

RENDER_POPUP_ITEM_LINE:
	LD	(POPUP_SLOT_SAVED),A	; Slot number (0..7)
	CALL	GET_SLOT_ENTRY_PTR
	PUSH	HL			; Save registry entry pointer

	LD	DE,SCRATCH_BUF

	; 1. Write selection cursor or space: '>' or ' '
	LD	A,(POPUP_SELECTED_INDEX)
	CP	C
	LD	A,' '
	JR	NZ,RPIL_NOT_SEL
	LD	A,'>'
RPIL_NOT_SEL:
	LD	(DE),A
	INC	DE
	LD	A,'['
	LD	(DE),A
	INC	DE

	; 2. Write slot digit
	LD	A,(POPUP_SLOT_SAVED)
	ADD	A,'0'
	LD	(DE),A
	INC	DE

	; 3. Write "] "
	LD	A,']'
	LD	(DE),A
	INC	DE
	LD	A,' '
	LD	(DE),A
	INC	DE

	; 4. Copy Plugin Name (12 characters, padded with spaces)
	POP	HL
	PUSH	HL
	LD	B,12
RPIL_NAME_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,RPIL_NAME_PAD
	CP	' '
	JR	Z,RPIL_NAME_PAD
	LD	(DE),A
	INC	HL
	INC	DE
	DJNZ	RPIL_NAME_LOOP
	JR	RPIL_NAME_DONE
RPIL_NAME_PAD:
	LD	A,' '
RPIL_PAD_L:
	LD	(DE),A
	INC	DE
	DJNZ	RPIL_PAD_L
RPIL_NAME_DONE:
	LD	A,' '
	LD	(DE),A
	INC	DE

	; 5. Description (29 characters)
	POP	IY			; IY = entry pointer
	CALL	GET_ITEM_DESC_PTR	; Returns HL = pointer to 29-char string
	LD	B,29
RPIL_DESC_LOOP:
	LD	A,(HL)
	LD	(DE),A
	INC	HL
	INC	DE
	DJNZ	RPIL_DESC_LOOP

	; 6. Space at end
	LD	A,' '
	LD	(DE),A
	INC	DE

	; 7. Terminate string with 0
	XOR	A
	LD	(DE),A

	; 8. Print formatted line boxed with '|' on each side
	LD	DE,SCRATCH_BUF
	JP	PRINT_POPUP_BOXED_LINE

GET_ITEM_DESC_PTR:
	LD	A,(HOST_CONTEXT_ID)
	CP	PLUG_CTX_CONFIG
	JR	NZ,GIDP_NOT_CONFIG
	LD	HL,STR_DESC_CONFIG
	RET
GIDP_NOT_CONFIG:
	CP	PLUG_CTX_HELP
	JR	Z,GIDP_ABOUT
	CP	PLUG_CTX_ABOUT
	JR	NZ,GIDP_NOT_ABOUT
GIDP_ABOUT:
	LD	HL,STR_DESC_ABOUT
	RET
GIDP_NOT_ABOUT:
	CP	PLUG_CTX_MEM_INFO
	JR	NZ,GIDP_NOT_MEM
	LD	HL,STR_DESC_FAR
	RET
GIDP_NOT_MEM:
	; For Editor, Splash, and Plugin Mgr, choose description based on capabilities
	LD	A,(IY+20)		; Capabilities low byte
	AND	04H			; CAP_DOC_MUTATE
	JR	Z,GIDP_CHECK_MODAL
	LD	HL,STR_DESC_MUTATE
	RET
GIDP_CHECK_MODAL:
	LD	A,(IY+20)
	AND	08H			; CAP_MODAL_UI
	JR	Z,GIDP_CHECK_FAR
	LD	HL,STR_DESC_MODAL
	RET
GIDP_CHECK_FAR:
	LD	A,(IY+20)
	AND	02H			; CAP_FAR_EXEC
	JR	Z,GIDP_TOOL
	LD	HL,STR_DESC_FAR
	RET
GIDP_TOOL:
	LD	HL,STR_DESC_TOOL
	RET

;==============================================================================
; Action 2: Plugin Manager Modal About Dialog
;==============================================================================
DO_PLUGIN_ABOUT:
	CALL	INIT_HOST_API
	JP	C,INIT_ERR

	LD	DE,STR_HIDE_CURSOR
	CALL	HOST_PRINT_STR

	; Center 9-line dialog box vertically: ((HOST_ROWS - 9) / 2) + 1
	LD	A,(HOST_ROWS)
	SUB	9
	SRL	A
	INC	A
	LD	(POPUP_ROW),A

	; Center 50-col box horizontally: ((HOST_COLS - 50) / 2) + 1
	LD	A,(HOST_COLS)
	SUB	50
	SRL	A
	INC	A
	LD	(POPUP_COL),A

	LD	HL,ABT_LINES_TABLE
	LD	B,9
DPA_LOOP:
	PUSH	BC
	LD	E,(HL)
	INC	HL
	LD	D,(HL)
	INC	HL
	PUSH	HL
	CALL	POPUP_LOCATE_NEXT
	CALL	HOST_PRINT_STR
	POP	HL
	POP	BC
	DJNZ	DPA_LOOP

	CALL	HOST_GET_KEY

	XOR	A
	OR	A			; A = 0, Carry = 0
	RET

ABT_LINES_TABLE:
	DW	STR_POPUP_BORDER
	DW	STR_ABT_LINE1
	DW	STR_POPUP_BORDER
	DW	STR_ABT_LINE2
	DW	STR_ABT_LINE3
	DW	STR_ABT_LINE4
	DW	STR_POPUP_BORDER
	DW	STR_ABT_LINE5
	DW	STR_POPUP_BORDER

STR_ABT_LINE1:	DB	"|   SE.COM Far RAM Plugin Manager (PLUGIN.PRL)   |", 0
STR_ABT_LINE2:	DB	"| Version: v1.0.0 (2026-09-25)                   |", 0
STR_ABT_LINE3:	DB	"| Mode   : 16KB Far RAM Modular Plugin (PRL)    |", 0
STR_ABT_LINE4:	DB	"| Role   : Dynamic Slot Management & Pop-up UI   |", 0
STR_ABT_LINE5:	DB	"|            Press any key to return             |", 0

;==============================================================================
; Modal Pop-up: Save Plugin Configuration Confirmation
;==============================================================================
SHOW_SAVE_CFG_POPUP:
	PUSH	AF			; Preserve Carry flag (save status)

	LD	DE,STR_HIDE_CURSOR
	CALL	HOST_PRINT_STR

	; Center 7-line dialog box vertically: ((HOST_ROWS - 7) / 2) + 1
	LD	A,(HOST_ROWS)
	SUB	7
	SRL	A
	INC	A
	LD	(POPUP_ROW),A

	; Center 50-col box horizontally: ((HOST_COLS - 50) / 2) + 1
	LD	A,(HOST_COLS)
	SUB	50
	SRL	A
	INC	A
	LD	(POPUP_COL),A

	; Line 1: Border
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	HOST_PRINT_STR

	; Line 2: Title
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_SAVE_CFG_TITLE
	CALL	HOST_PRINT_STR

	; Line 3: Border
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	HOST_PRINT_STR

	; Line 4: Blank line
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_SAVE_CFG_BLANK
	CALL	HOST_PRINT_STR

	; Line 5: Result status
	CALL	POPUP_LOCATE_NEXT
	POP	AF			; Restore Carry
	JR	C,SSCP_ERR
	LD	DE,STR_SAVE_CFG_OK
	JR	SSCP_PRINT_MSG
SSCP_ERR:
	LD	DE,STR_SAVE_CFG_FAIL
SSCP_PRINT_MSG:
	CALL	HOST_PRINT_STR

	; Line 6: Instructions / Prompt
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_SAVE_CFG_KEY
	CALL	HOST_PRINT_STR

	; Line 7: Border
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	HOST_PRINT_STR

	; Wait for keypress to dismiss
	CALL	HOST_GET_KEY
	RET

;------------------------------------------------------------------------------
; SHOW_ALERT_POPUP:
; Render centered 50x7 Tier 2 alert modal pop-up; wait for any key to dismiss.
; Input: DE = Title string (50 cols), HL = Msg string (50 cols)
; Preserves: none
;------------------------------------------------------------------------------
SHOW_ALERT_POPUP:
	PUSH	HL			; Save Msg pointer
	PUSH	DE			; Save Title pointer

	LD	DE,STR_HIDE_CURSOR
	CALL	HOST_PRINT_STR

	; Center 7-line dialog box vertically: ((HOST_ROWS - 7) / 2) + 1
	LD	A,(HOST_ROWS)
	SUB	7
	SRL	A
	INC	A
	LD	(POPUP_ROW),A

	; Center 50-col box horizontally: ((HOST_COLS - 50) / 2) + 1
	LD	A,(HOST_COLS)
	SUB	50
	SRL	A
	INC	A
	LD	(POPUP_COL),A

	; Line 1: Border
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	HOST_PRINT_STR

	; Line 2: Title
	CALL	POPUP_LOCATE_NEXT
	POP	DE			; DE = Title
	CALL	HOST_PRINT_STR

	; Line 3: Border
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	HOST_PRINT_STR

	; Line 4: Blank line
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_SAVE_CFG_BLANK
	CALL	HOST_PRINT_STR

	; Line 5: Msg
	CALL	POPUP_LOCATE_NEXT
	POP	DE			; DE = Msg
	CALL	HOST_PRINT_STR

	; Line 6: Instructions
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_SAVE_CFG_KEY
	CALL	HOST_PRINT_STR

	; Line 7: Border
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	HOST_PRINT_STR

	; Wait for keypress to dismiss
	CALL	HOST_GET_KEY
	CP	27
	JR	NZ,SAP_NOT_ESC
	CALL	DRAIN_ESC_SEQUENCE
SAP_NOT_ESC:
	RET

;==============================================================================
; Helper Routines & String Formatting
;==============================================================================

INIT_HOST_API:
	; Verify Host API Magic "SE" (check IX or IY)
	LD	A,(IX+0)
	CP	'S'
	JR	Z,IHA_OK
	PUSH	IY
	POP	IX
	LD	A,(IX+0)
	CP	'S'
	JR	NZ,INIT_ERR
IHA_OK:
	LD	A,(IX+1)
	CP	'E'
	JR	NZ,INIT_ERR

	LD	(HOST_API_PTR),IX

	; Calculate vector for HOST_LOCATE_RC trampoline (IX + 52)
	PUSH	IX
	POP	HL
	LD	BC,52
	ADD	HL,BC
	LD	(VEC_LOCATE_RC),HL

	; Pointer to PLUGIN_REGISTRY (256 bytes) at IX+44
	LD	L,(IX+44)
	LD	H,(IX+45)
	LD	(HOST_REGISTRY_PTR),HL

	; Screen geometry and context
	LD	A,(IX+14)
	LD	(HOST_COLS),A
	LD	A,(IX+15)
	LD	(HOST_CONTEXT_ID),A
	LD	A,(IX+16)
	LD	(HOST_ROWS),A
	LD	A,(IX+17)
	LD	(HOST_MGR_SLOT),A

	OR	A			; Carry = 0
	RET

INIT_ERR:
	SCF				; Carry = 1
	RET

; Get pointer to slot entry A (0..7) in PLUGIN_REGISTRY
; Returns HL = pointer to 32-byte slot record
GET_SLOT_ENTRY_PTR:
	AND	07H
	LD	L,A
	LD	H,0
	ADD	HL,HL			; *2
	ADD	HL,HL			; *4
	ADD	HL,HL			; *8
	ADD	HL,HL			; *16
	ADD	HL,HL			; *32
	LD	DE,(HOST_REGISTRY_PTR)
	ADD	HL,DE
	RET

; PRINT_ABOUT_LINE: Print '~', center the string at DE horizontally, then CRLF
PRINT_ABOUT_LINE:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL

	PUSH	DE
	POP	HL
	LD	B,0
PAL_LEN:
	LD	A,(HL)
	OR	A
	JR	Z,PAL_LEN_DONE
	CP	'$'
	JR	Z,PAL_LEN_DONE
	INC	HL
	INC	B
	JR	PAL_LEN
PAL_LEN_DONE:
	LD	A,'~'
	CALL	HOST_PUTC

	LD	A,(HOST_COLS)
	DEC	A			; Columns remaining after '~'
	SUB	B			; Subtract length in B
	JR	C,PAL_NO_PAD
	SRL	A
	JR	Z,PAL_NO_PAD
	LD	B,A
PAL_PAD_LOOP:
	LD	A,' '
	CALL	HOST_PUTC
	DJNZ	PAL_PAD_LOOP

PAL_NO_PAD:
	CALL	HOST_PRINT_STR
	LD	A,13
	CALL	HOST_PUTC
	LD	A,10
	CALL	HOST_PUTC

	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

PRINT_TILDE_CRLF:
	LD	A,'~'
	CALL	HOST_PUTC
	LD	A,13
	CALL	HOST_PUTC
	LD	A,10
	JP	HOST_PUTC

FORMAT_DEC_WORD_BUF:
	PUSH	BC
	PUSH	HL
	XOR	A
	LD	(FMT_LEAD_ZERO),A
	LD	BC,-10000
	CALL	FMT_DW_DIG
	LD	BC,-1000
	CALL	FMT_DW_DIG
	LD	BC,-100
	CALL	FMT_DW_DIG
	LD	BC,-10
	CALL	FMT_DW_DIG
	LD	A,L
	ADD	A,'0'
	LD	(DE),A
	INC	DE
	POP	HL
	POP	BC
	RET

FMT_DW_DIG:
	LD	A,'0'-1
FMT_DW_LOOP:
	INC	A
	ADD	HL,BC
	JR	C,FMT_DW_LOOP
	SBC	HL,BC
	PUSH	AF
	LD	A,(FMT_LEAD_ZERO)
	OR	A
	JR	NZ,FDW_EMIT_DIG
	POP	AF
	CP	'0'
	JR	Z,FDW_EMIT_SPACE
	PUSH	AF
	LD	A,1
	LD	(FMT_LEAD_ZERO),A
FDW_EMIT_DIG:
	POP	AF
	LD	(DE),A
	INC	DE
	RET
FDW_EMIT_SPACE:
	LD	A,' '
	LD	(DE),A
	INC	DE
	RET

FORMAT_HEX_BYTE_DE:
	PUSH	AF
	RRCA
	RRCA
	RRCA
	RRCA
	CALL	NIBBLE_TO_HEX
	LD	(DE),A
	INC	DE
	POP	AF
	CALL	NIBBLE_TO_HEX
	LD	(DE),A
	INC	DE
	RET

NIBBLE_TO_HEX:
	AND	0FH
	ADD	A,'0'
	CP	'9'+1
	RET	C
	ADD	A,7
	RET

COPY_STR_Z:
	LD	A,(HL)
	OR	A
	RET	Z
	LD	(DE),A
	INC	HL
	INC	DE
	JR	COPY_STR_Z

DRAIN_ESC_SEQUENCE:
	LD	BC,500
DES_LOOP:
	CALL	HOST_CHECK_KEY
	JR	Z,DES_DONE
	CALL	HOST_GET_KEY
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,DES_LOOP
DES_DONE:
	RET

;------------------------------------------------------------------------------
; Host API Trampoline Wrappers (via HOST_API_PTR in Upper Common RAM)
;------------------------------------------------------------------------------
HOST_PUTC:
	PUSH	HL
	LD	HL,(HOST_API_PTR)
	PUSH	BC
	LD	BC,24			; Offset +24: PUTC
	ADD	HL,BC
	POP	BC
	EX	(SP),HL
	RET

HOST_PRINT_STR:
	PUSH	HL
	LD	HL,(HOST_API_PTR)
	PUSH	BC
	LD	BC,27			; Offset +27: PRINT_STR
	ADD	HL,BC
	POP	BC
	EX	(SP),HL
	RET

HOST_GET_KEY:
	PUSH	HL
	LD	HL,(HOST_API_PTR)
	PUSH	BC
	LD	BC,30			; Offset +30: GET_KEY
	ADD	HL,BC
	POP	BC
	EX	(SP),HL
	RET

HOST_CHECK_KEY:
	PUSH	BC
	PUSH	HL
	LD	HL,(HOST_API_PTR)
	LD	BC,46			; Offset +46: CHECK_KEY_READY
	ADD	HL,BC
	CALL	CALL_HL
	POP	HL
	POP	BC
	RET

CALL_HL:
	JP	(HL)

HOST_LOCATE_RC:
	PUSH	HL
	LD	HL,(VEC_LOCATE_RC)
	EX	(SP),HL
	RET

HOST_LOAD_PLUGIN:
	PUSH	HL
	LD	HL,(HOST_API_PTR)
	PUSH	BC
	LD	BC,55			; Offset +55: LOAD_PLUGIN_BY_NAME
	ADD	HL,BC
	POP	BC
	EX	(SP),HL
	RET

HOST_UNLOAD_SLOT:
	PUSH	HL
	LD	HL,(HOST_API_PTR)
	PUSH	BC
	LD	BC,58			; Offset +58: UNLOAD_PLUGIN_SLOT
	ADD	HL,BC
	POP	BC
	EX	(SP),HL
	RET

HOST_REDRAW_BASE:
	PUSH	HL
	LD	HL,(HOST_API_PTR)
	PUSH	BC
	LD	BC,61			; Offset +61: REDRAW_BASE_SCREEN
	ADD	HL,BC
	POP	BC
	EX	(SP),HL
	RET

HOST_OPEN_PLUGIN_UI:
	PUSH	HL
	LD	HL,(HOST_API_PTR)
	PUSH	BC
	LD	BC,64			; Offset +64: OPEN_PLUGIN_UI
	ADD	HL,BC
	POP	BC
	EX	(SP),HL
	RET

HOST_SAVE_PLUGIN_CFG:
	PUSH	HL
	LD	HL,(HOST_API_PTR)
	PUSH	BC
	LD	BC,67			; Offset +67: SAVE_PLUGIN_CFG
	ADD	HL,BC
	POP	BC
	EX	(SP),HL
	RET

HOST_LOAD_PLUGIN_CFG:
	PUSH	HL
	LD	HL,(HOST_API_PTR)
	PUSH	BC
	LD	BC,70			; Offset +70: LOAD_PLUGIN_CFG
	ADD	HL,BC
	POP	BC
	EX	(SP),HL
	RET

HOST_RENDER_STATUS_BAR:
	PUSH	HL
	LD	HL,(HOST_API_PTR)
	PUSH	BC
	LD	BC,73			; Offset +73: RENDER_STATUS_BAR
	ADD	HL,BC
	POP	BC
	EX	(SP),HL
	RET

;==============================================================================
; Static Strings & Data
;==============================================================================
STR_CLEAR_SCREEN:	DB	27,"[2J",27,"[H","$"
STR_CLEAR_EOL:		DB	27,"[K","$"
STR_HIDE_CURSOR:	DB	27,"[?25l","$"
STR_SHOW_CURSOR:	DB	27,"[?25h","$"

STR_POPUP_BORDER:	DB	"+------------------------------------------------+", 0

STR_TITLE_EDITOR:	DB	"        Plugins for Editor (Run Plugin)         ", 0
STR_TITLE_SPLASH:	DB	"          All Available Installed Plugins       ", 0
STR_TITLE_CONFIG:	DB	"       Plugins with Configurable Settings       ", 0
STR_TITLE_MEM_INFO:	DB	"        Plugins with Far RAM Memory Usage       ", 0
STR_TITLE_PLUGIN_MGR:	DB	"            Installed Plugin Catalog            ", 0
STR_TITLE_HELP:		DB	"       Plugins with Embedded Documentation      ", 0

STR_POPUP_NO_MATCH:	DB	"    No plugins found for this screen context    ", 0
STR_POPUP_PROMPT_NOMATCH:
	DB	"            Press any key to dismiss            ", 0
STR_POPUP_PROMPT_MATCH:
	DB	" [Up]   [Down]=Select  [Enter]=Exec  [ESC]=Exit ", 0

STR_DESC_CONFIG:	DB	"Embedded Plugin Settings     ", 0
STR_DESC_ABOUT:		DB	"Modal About & Info Dialog    ", 0
STR_DESC_FAR:		DB	"Far RAM Resident (Bank 89h)  ", 0
STR_DESC_MODAL:		DB	"Modal Dialog Summary         ", 0
STR_DESC_MUTATE:	DB	"Mutates Active Document      ", 0
STR_DESC_TOOL:		DB	"Standalone Plugin Tool       ", 0

STR_PLUG_TITLE:		DB	"SE - Plugin Manager (4K/8K/16K/32K Dynamic Far RAM)", 0
STR_PLUG_SYS_PRE:	DB	"Far RAM: [", 0
STR_PLUG_SYS_DYN:	DB	"Dynamic On-Demand]    ", 0
STR_PLUG_SYS_BNK:	DB	"Bank ", 0
STR_PLUG_SYS_MID:	DB	"h (32KB)]    Loaded: [", 0
STR_PLUG_SYS_POST:	DB	"/8]    TPA Slot: [4KB Overlaid]", 0
STR_PLUG_HDR:		DB	"Slot Plugin Name      Type   Size    Exec Mode  Capabilities     Status ", 0
STR_PLUG_SEP:		DB	"----+----------------+------+-------+----------+---------------+--------", 0

STR_PLUG_CMDS_PRE:	DB	"[Up]   [Down]=Select  ", 0
STR_PLUG_CMDS_BOTH:
	DB	"[Enter]=Unload [A]=About [C]=Config [S]=Save [ESC]=Exit", 0
STR_PLUG_CMDS_ABOUT:
	DB	"[Enter]=Unload  [A]=About  [S]=Save  [ESC]=Exit", 0
STR_PLUG_CMDS_CONFIG:
	DB	"[Enter]=Unload  [C]=Config  [S]=Save  [ESC]=Exit", 0
STR_PLUG_CMDS_PLAIN:
	DB	"[Enter]=Unload  [S]=Save  [ESC]=Exit", 0
STR_PLUG_CMDS_EMPTY:
	DB	"[Enter]=Load  [S]=Save  [ESC]=Exit", 0

STR_PLUG_NO_ABT_TITLE:
	DB	"|               Plugin Information               |", 0
STR_PLUG_NO_ABT_MSG:
	DB	"|        This plugin has no about dialog         |", 0
STR_PLUG_NO_CFG_TITLE:
	DB	"|              Plugin Configuration              |", 0
STR_PLUG_NO_CFG_MSG:
	DB	"|    This plugin has no configuration screen     |", 0
STR_PLUG_FULL_TITLE:
	DB	"|               Plugin Load Error                |", 0
STR_PLUG_FULL_MSG:
	DB	"|      All plugin slots are currently full       |", 0
STR_SAVE_CFG_TITLE:	DB	"|           Save Plugin Configuration            |", 0
STR_SAVE_CFG_BLANK:	DB	"|                                                |", 0
STR_SAVE_CFG_OK:	DB	"|             [Saved to PLUGIN.CFG]              |", 0
STR_SAVE_CFG_FAIL:	DB	"|           [Error saving PLUGIN.CFG]            |", 0
STR_SAVE_CFG_KEY:	DB	"|           Press any key to continue            |", 0
STR_UNLOAD_TITLE:	DB	"|                 Unload Plugin                  |", 0
STR_UNLOAD_DESC:	DB	"|      Unloading plugin frees Far RAM slot       |", 0
STR_UNLOAD_PROMPT_PRE:	DB	"|                 Unload Slot ", 0
STR_UNLOAD_PROMPT_POST:	DB	"?                 |", 0
STR_UNLOAD_KEYS:	DB	"|        [Y]es      [N]o      [ESC]=Cancel       |", 0

STR_PLUG_EMPTY_ROW:	DB	"(empty slot)     --     --      --         --               [Free] ", 0
STR_PLUG_TYPE_PRL:	DB	"PRL   ", 0
STR_PLUG_TYPE_OVL:	DB	"OVL   ", 0

STR_PLUG_MODE_TPA4:	DB	"TPA (4KB) ", 0
STR_PLUG_MODE_FAR4:	DB	"FAR (4KB) ", 0
STR_PLUG_MODE_FAR8:	DB	"FAR (8KB) ", 0
STR_PLUG_MODE_FAR16:	DB	"FAR (16KB)", 0
STR_PLUG_MODE_FAR32:	DB	"FAR (32KB)", 0

STR_CAP_MODAL_FAR:	DB	"Modal, Far     ", 0
STR_CAP_MUTATE_TPA:	DB	"Mutate, TPA    ", 0
STR_CAP_DEFAULT:	DB	"Standard       ", 0
STR_PLUG_STAT_READY:	DB	"[Ready] ", 0
AUTOLOAD_DONE:		DB	0

;==============================================================================
; Uninitialized Variables (BSS - zero binary footprint, defined via EQU)
;==============================================================================
BSS_START:
HOST_API_PTR		EQU	BSS_START
HOST_REGISTRY_PTR	EQU	BSS_START + 2
HOST_COLS		EQU	BSS_START + 4
HOST_ROWS		EQU	BSS_START + 5
HOST_CONTEXT_ID		EQU	BSS_START + 6
HOST_MGR_SLOT		EQU	BSS_START + 7
SELECTED_SLOT		EQU	BSS_START + 8
POPUP_ROW		EQU	BSS_START + 9
POPUP_COL		EQU	BSS_START + 10
POPUP_MATCH_COUNT	EQU	BSS_START + 11
FMT_LEAD_ZERO		EQU	BSS_START + 12
POPUP_SLOT_SAVED	EQU	BSS_START + 13
FPSL_BANK_FOUND		EQU	BSS_START + 14
FPSL_LOADED_CNT		EQU	BSS_START + 15
POPUP_MATCH_SLOTS	EQU	BSS_START + 16	; 8 bytes
VEC_LOCATE_RC		EQU	BSS_START + 24	; 2 bytes: LOCATE_RC vector
POPUP_TOP_ROW		EQU	BSS_START + 26	; 1 byte: Top row for redraw
POPUP_SELECTED_INDEX	EQU	BSS_START + 27	; 1 byte: Selected item index
SCRATCH_BUF		EQU	BSS_START + 28	; 128 bytes scratch buffer
PLUG_REG_PTR		EQU	SCRATCH_BUF + 128 ; 2 bytes: pointer to registry
PLUGIN_CFG_BUF		EQU	PLUG_REG_PTR + 2 ; 128 bytes: cfg I/O buffer
CFG_BUF_SENTINEL	EQU	PLUGIN_CFG_BUF + 128 ; 1 byte: null sentinel
BSS_END			EQU	CFG_BUF_SENTINEL + 1
BSS_SIZE		EQU	BSS_END - BSS_START
