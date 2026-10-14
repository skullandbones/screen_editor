;==============================================================================
; PLUGIN_TRAMP.ASM: Core Subsystem - Upper Memory Host API Trampolines
;
; Purpose:
;   Provides Upper Memory (> 8000h) resident jump vectors and Host API
;   trampolines accessible across all Far RAM banked contexts, and PLUGIN.CFG
;   configuration persistence routines.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;==============================================================================
; Plugin Subsystem High-Memory Variables & Registry
;==============================================================================
BORROWED_BANKS_CNT:	DB	0
BORROWED_BANKS_TBL:	DS	8
LOAD_FAR_BANK:		DB	0
LOAD_BASE_PAGE:		DB	0
LOAD_SIZE_CLASS:	DB	0
LOAD_PAGE_COUNT:	DB	0
ALLOC_SIZE_CLASS:	DB	0
ALLOC_PAGE_COUNT:	DB	0
ALLOC_SUBALLOC_FLAG:	DB	0
ALLOC_TEMP_BANK:	DB	0
IRF_TARGET_BANK:	DB	0
IRF_CAND_EC:		DB	0
PAYLOAD_SECTORS_REMAIN:	DW	0
EP_TPA_FAR_BANK:	DB	0
EP_TPA_COPY_LEN:	DW	0
PLUGIN_FAR_BANK:	DB	0
PLUGIN_LOAD_COUNT:	DB	0
PLUGIN_CUR_SLOT:	DB	0
PLUGIN_ACTION_INDEX:	DB	0
PLUGIN_IS_FAR_EXEC:	DB	0
PLUGIN_RET_CODE:	DB	0
PLUGIN_STATUS_MSG_PTR:	DW	0
PLUGIN_POPUP_MSG_BUF	EQU	FNF_POPUP_MSG1
PLUGIN_ORIG_USER:	DB	0
PLUGIN_USER_AREA:	DB	0
PLUGIN_FCB:		DS	36
FAR_SLOT_BASE_ADDR:	DW	0
FAR_SECT_DEST:		DW	0
RELOC_BIAS:		DB	0
RELOC_CUR_BYTE:		DB	0
PLUGIN_REGISTRY:	DS	8 * 32
POPUP_CONTEXT_ID:	DB	0
POPUP_ROW:		DB	0
POPUP_COL:		DB	0
POPUP_START_ROW:	DB	0
POPUP_SAVE_START_ROW:	DB	0
POPUP_ACTION_MODAL:	DB	0
PLUGIN_MGR_SLOT:	DB	0FFH
PLUGIN_MGR_BANK:	DB	0
PLUGIN_MGR_LOADED:	DB	0
TRAMP_NAME_BUF:		DS	16
CFG_AUTOLOAD_PLUGIN_MGR: DB	1
PLUGIN_SAVED_DOC_ROW:	DW	0
PLUGIN_SAVED_COL:	DW	0
PLUGIN_SAVED_TARGET_COL: DW	0
PLUGIN_SAVED_TOP_ROW:	DW	0
PLUGIN_SAVED_VIEW_LEFT:	DW	0

;------------------------------------------------------------------------------
; FAT VFS Subsystem State (Phase 2)
; Located in Upper Common RAM (> 8000h)
;------------------------------------------------------------------------------
DOC_IS_FAT:		DB	0		; 1 if active doc is FAT file
FAT_DOC_UNIT:		DB	0FFH		; HBIOS unit (0..7, 0xFF=def)
FAT_DOC_PATH:		DS	128		; Full null-terminated DOS path
FAT_DOC_FNAME:		DS	13		; Base 8.3 fname + null
FAT_ACTIVE_UNIT:	DB	0FFH		; Active browsing unit
FAT_ACTIVE_DIR:		DS	128		; Active directory path
FAT_INPUT_MATCHED:	DB	0		; Match flag during input check
CURRENT_DIR_IS_FAT:	DB	0		; 0=CP/M drive, 1=FAT volume
CURRENT_DIR_FAT_UNIT:	DB	0FFH	; FAT browsing unit (0..7, 0xFF=default)
CURRENT_DIR_FAT_PATH:	DS	64	; Active directory path (e.g. "/")
BLOCK_INSERT_IS_FAT:	DB	0		; 1 during FAT block insertion
; Buffer for block insertion path (64B overlaid on CFG_IO_BUF)
FAT_INSERT_PATH		EQU	CFG_IO_BUF
CMDLINE_IS_FAT:		DB	0	; 1 if startup argument was FAT file
CMDLINE_FAT_UNIT:	DB	0FFH	; Unit from command line argument
STR_SLASH:		DB	"/",0
STR_FATFS_PRL:		DB	"FATFS.PRL",0	; Plugin filename for auto-load
STR_TITLE_PAREN_CRLF:	DB	")",13,10,0	; Title closing parenthesis

ALIGN 2
VFS_REQ_PKT:
VFS_REQ_CMD:		DB	0		; +0: Command opcode (VFS_CMD_*)
VFS_REQ_UNIT:		DB	0FFH		; +1: Disk unit (0..7, 0xFF=def)
VFS_REQ_STATUS:		DB	0		; +2: Output status (VFS_STAT_*)
VFS_REQ_FLAGS:		DB	0		; +3: Option flags
VFS_REQ_PATH:		DW	0		; +4: Pointer to DOS path
VFS_REQ_BUFFER:		DW	0		; +6: Pointer to data buffer
VFS_REQ_BUFSIZE:	DW	0		; +8: Buffer capacity
VFS_REQ_COUNT:		DW	0		; +10: Output count
VFS_REQ_START_LINE:	DW	0		; +12: Start line for block save
VFS_REQ_END_LINE:	DW	0		; +14: End line for block save
; FAT stream buffer in Common RAM (128B overlaid on CFG_IO_BUF + 64)
FAT_CHUNK_BUF		EQU	CFG_IO_BUF + 64

;==============================================================================
; Upper Memory Host API Trampoline & Vector Table
; Physically situated in Upper 32KB (> 8000h) so it is resident across all
; banks.
;==============================================================================
ALIGN 4
PLUGIN_HOST_API:
	DB "SE"				; +0:  Magic
	DW 0111H			; +2:  Host version (v1.1.1)
	DW ACTIVE_LINE_BUF		; +4:  Pointer to ACTIVE_LINE_BUF

	DW ACTIVE_LINE_LEN		; +6:  Pointer to ACTIVE_LINE_LEN
	DW CUR_DOC_ROW			; +8:  Pointer to CUR_DOC_ROW
	DW DOC_TOTAL_LINES		; +10: Pointer to DOC_TOTAL_LINES
	DW CUR_COL			; +12: Pointer to CUR_COL
HOST_API_COLS:
	DB 80				; +14: Screen cols (80 or 120)
HOST_API_CONTEXT:
	DB 0				; +15: Screen Context ID (0..6)
HOST_API_ROWS:
	DB 24				; +16: Screen rows (24 or 40)
HOST_API_MGR_SLOT:
	DB 0FFH			; +17: Plugin Manager Slot (0..7 or 0xFF)
	JP TRAMP_CHECKOUT_LINE		; +18: Call HOST_CHECKOUT_LINE
	JP TRAMP_COMMIT_LINE		; +21: Call HOST_COMMIT_LINE
	JP TRAMP_PUTC			; +24: Call PUTC
	JP TRAMP_PRINT_STR		; +27: Call PRINT_STR
	JP TRAMP_GET_KEY		; +30: Call GET_KEY
	JP TRAMP_SET_STATUS_MSG		; +33: Call SET_STATUS_MSG
	DW BLOCK_ACTIVE			; +36: Pointer to BLOCK_ACTIVE
	DW BLOCK_START_ROW		; +38: Pointer to BLOCK_START_ROW
	DW BLOCK_END_ROW		; +40: Pointer to BLOCK_END_ROW
	DW CFG_TAB_WIDTH		; +42: Pointer to CFG_TAB_WIDTH
	DW PLUGIN_REGISTRY	; +44: Pointer to PLUGIN_REGISTRY (256 bytes)
	JP TRAMP_CHECK_KEY		; +46: Call CHECK_KEY_READY
	JP TRAMP_CLEAR_DOCUMENT		; +49: Call HOST_CLEAR_DOCUMENT
	JP TRAMP_LOCATE_RC		; +52: Call LOCATE_RC (H=Row, L=Col)
	JP TRAMP_LOAD_PLUGIN	; +55: Call LOAD_PLUGIN_BY_NAME (DE=filename)
	JP TRAMP_UNLOAD_SLOT	; +58: Call UNLOAD_PLUGIN_SLOT (A=slot 0..7)
	JP TRAMP_REDRAW_BASE	; +61: Call REDRAW_BASE_SCREEN (A=context 0..6)
	JP TRAMP_OPEN_PLUGIN_UI	; +64: Call DO_OPEN_FILE_UI (plugin mode)
	JP TRAMP_SAVE_PLUGIN_CFG	; +67: Call HOST_SAVE_PLUGIN_CFG
	JP TRAMP_LOAD_PLUGIN_CFG	; +70: Call HOST_LOAD_PLUGIN_CFG
	JP TRAMP_RENDER_STATUS_BAR	; +73: Call RENDER_STATUS_BAR

;------------------------------------------------------------------------------
; TRAMP_CHECKOUT_LINE: Host API trampoline for line checkout across memory banks
;
; Purpose:
;   If calling plugin executes in Far RAM, switches to CPM_USER_BANK, invokes
;   HOST_CHECKOUT_LINE, and restores PLUGIN_FAR_BANK before returning.
;
; Call Usage / Protocol:
;   Called via PLUGIN_HOST_API jump vector (+18) by running plugins.
;
; Inputs:
;   HL = Target document line number (0-based).
;
; Outputs:
;   ACTIVE_LINE_BUF populated, BC = Line length.
;
; Preserves / Modifies:
;   Preserves caller bank context.
;------------------------------------------------------------------------------
TRAMP_CHECKOUT_LINE:
	LD A,(PLUGIN_IS_FAR_EXEC)
	OR A
	JP Z,HOST_CHECKOUT_LINE
	PUSH AF
	LD A,(CPM_USER_BANK)
	CALL 0FFF3H
	CALL HOST_CHECKOUT_LINE
	LD A,(PLUGIN_FAR_BANK)
	CALL 0FFF3H
	POP AF
	RET

;------------------------------------------------------------------------------
; TRAMP_COMMIT_LINE: Host API trampoline for line commit across memory banks
;
; Purpose:
;   If calling plugin executes in Far RAM, switches to CPM_USER_BANK, invokes
;   HOST_COMMIT_LINE, and restores PLUGIN_FAR_BANK before returning.
;
; Call Usage / Protocol:
;   Called via PLUGIN_HOST_API jump vector (+21) by running plugins.
;
; Inputs:
;   HL = Line number, DE = Buffer pointer, BC = Line length.
;
; Outputs:
;   Line committed to far RAM line table.
;
; Preserves / Modifies:
;   Preserves caller bank context.
;------------------------------------------------------------------------------
TRAMP_COMMIT_LINE:
	LD A,(PLUGIN_IS_FAR_EXEC)
	OR A
	JP Z,HOST_COMMIT_LINE
	PUSH AF
	LD A,(CPM_USER_BANK)
	CALL 0FFF3H
	CALL HOST_COMMIT_LINE
	LD A,(PLUGIN_FAR_BANK)
	CALL 0FFF3H
	POP AF
	RET

;------------------------------------------------------------------------------
; TRAMP_PUTC: Host API trampoline for character output across memory banks
;
; Purpose:
;   Emits character in A to terminal screen via PUTC, switching memory banks
;   between Far RAM and Bank 0 if calling plugin runs in Far RAM.
;
; Call Usage / Protocol:
;   Called via PLUGIN_HOST_API jump vector (+24).
;
; Inputs:
;   A = Character to emit.
;
; Outputs:
;   Character printed to terminal.
;
; Preserves / Modifies:
;   Preserves AF, BC, DE, HL across bank switch.
;------------------------------------------------------------------------------
TRAMP_PUTC:
	PUSH AF
	LD A,(PLUGIN_IS_FAR_EXEC)
	OR A
	JR Z,TPC_DIRECT
	LD A,(CPM_USER_BANK)
	CALL 0FFF3H
	EI
	POP AF
	PUSH AF
	CALL PUTC
	DI
	LD A,(PLUGIN_FAR_BANK)
	CALL 0FFF3H
	POP AF
	RET
TPC_DIRECT:
	POP AF
	JP PUTC

;------------------------------------------------------------------------------
; TRAMP_PRINT_STR: Host API trampoline for string printing from Far RAM
;
; Purpose:
;   Iterates through characters of string in Far RAM or Bank 0 at DE, emitting
;   each character via TRAMP_PUTC until terminating null or '$' is reached.
;
; Call Usage / Protocol:
;   Called via PLUGIN_HOST_API jump vector (+27).
;
; Inputs:
;   DE = Pointer to null- or '$'-terminated string.
;
; Outputs:
;   String printed to terminal.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL.
;------------------------------------------------------------------------------
TRAMP_PRINT_STR:
	LD A,(PLUGIN_IS_FAR_EXEC)
	OR A
	JP Z,PRINT_STR
	PUSH BC
	PUSH DE
	PUSH HL
	EX DE,HL			; HL = pointer in Far RAM
TPS_LOOP:
	LD A,(HL)
	OR A
	JR Z,TPS_DONE
	CP '$'
	JR Z,TPS_DONE
	PUSH HL
	CALL TRAMP_PUTC
	POP HL
	INC HL
	JR TPS_LOOP
TPS_DONE:
	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; TRAMP_GET_KEY: Host API trampoline for blocking keyboard input across banks
;
; Purpose:
;   Calls GET_KEY across banks via TRAMP_FAR_CALL to retrieve next keystroke.
;
; Call Usage / Protocol:
;   Called via PLUGIN_HOST_API jump vector (+30).
;
; Inputs:
;   None.
;
; Outputs:
;   A = ASCII character or escape sequence code.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL.
;------------------------------------------------------------------------------
TRAMP_GET_KEY:
	LD A,(PLUGIN_IS_FAR_EXEC)
	OR A
	JP Z,GET_KEY
	LD HL,GET_KEY
	JP TRAMP_FAR_CALL

;------------------------------------------------------------------------------
; TRAMP_SET_STATUS_MSG: Host API trampoline to display popup status notification
;
; Purpose:
;   Dispatches to HOST_SET_STATUS_MSG to format and display plugin notification
;   inside centered Tier 2 modal popup dialog.
;
; Call Usage / Protocol:
;   Called via PLUGIN_HOST_API jump vector (+33).
;
; Inputs:
;   DE = Pointer to null-terminated status message string.
;
; Outputs:
;   Popup notification displayed on terminal.
;
; Preserves / Modifies:
;   Preserves all registers.
;------------------------------------------------------------------------------
TRAMP_SET_STATUS_MSG:
	JP HOST_SET_STATUS_MSG

;------------------------------------------------------------------------------
; TRAMP_CHECK_KEY: Host API trampoline for non-blocking key check across banks
;
; Purpose:
;   Calls CHECK_KEY_READY across banks via TRAMP_FAR_CALL to test if keystroke
;   is available in terminal input buffer.
;
; Call Usage / Protocol:
;   Called via PLUGIN_HOST_API jump vector (+46).
;
; Inputs:
;   None.
;
; Outputs:
;   Zero flag (Z) set if no key ready; NZ if key available.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL.
;------------------------------------------------------------------------------
TRAMP_CHECK_KEY:
	LD A,(PLUGIN_IS_FAR_EXEC)
	OR A
	JP Z,CHECK_KEY_READY
	LD HL,CHECK_KEY_READY
	JP TRAMP_FAR_CALL

;------------------------------------------------------------------------------
; TRAMP_CLEAR_DOCUMENT: Host API trampoline to clear document across banks
;
; Purpose:
;   Calls HOST_CLEAR_DOCUMENT across memory banks via TRAMP_FAR_CALL.
;
; Call Usage / Protocol:
;   Called via PLUGIN_HOST_API jump vector (+49).
;
; Inputs:
;   None.
;
; Outputs:
;   Document lines cleared; state reset.
;
; Preserves / Modifies:
;   Preserves caller bank context.
;------------------------------------------------------------------------------
TRAMP_CLEAR_DOCUMENT:
	LD A,(PLUGIN_IS_FAR_EXEC)
	OR A
	JP Z,HOST_CLEAR_DOCUMENT
	LD HL,HOST_CLEAR_DOCUMENT
	JP TRAMP_FAR_CALL

;------------------------------------------------------------------------------
; TRAMP_LOCATE_RC: Host API trampoline for cursor positioning across banks
;
; Purpose:
;   Calls LOCATE_RC across memory banks to position terminal hardware cursor
;   at row B and column C.
;
; Call Usage / Protocol:
;   Called via PLUGIN_HOST_API jump vector (+52).
;
; Inputs:
;   B = Row (0-based).
;   C = Column (0-based).
;
; Outputs:
;   Hardware cursor repositioned.
;
; Preserves / Modifies:
;   Preserves caller bank context.
;------------------------------------------------------------------------------
TRAMP_LOCATE_RC:
	LD A,(PLUGIN_IS_FAR_EXEC)
	OR A
	JP Z,LOCATE_RC
	PUSH AF
	LD A,(CPM_USER_BANK)
	CALL 0FFF3H
	EI
	CALL LOCATE_RC
	DI
	LD A,(PLUGIN_FAR_BANK)
	CALL 0FFF3H
	POP AF
	RET

;------------------------------------------------------------------------------
; TRAMP_LOAD_PLUGIN: Host API trampoline to load external plugin across banks
;
; Purpose:
;   Copies filename string into TRAMP_NAME_BUF in Bank 0 and invokes
;   LOAD_PLUGIN_BY_NAME via TRAMP_FAR_CALL.
;
; Call Usage / Protocol:
;   Called via PLUGIN_HOST_API jump vector (+55).
;
; Inputs:
;   DE = Pointer to null-terminated plugin filename string.
;
; Outputs:
;   Carry = 0 and A = slot index on success; Carry = 1 on error.
;
; Preserves / Modifies:
;   Preserves caller bank context.
;------------------------------------------------------------------------------
TRAMP_LOAD_PLUGIN:
	; Input: DE = pointer to null-terminated ASCII filename
	; Returns: Carry=0 on success, A=slot number; Carry=1 on error
	LD A,(PLUGIN_IS_FAR_EXEC)
	OR A
	JP Z,LOAD_PLUGIN_BY_NAME
	PUSH BC
	PUSH HL
	LD HL,TRAMP_NAME_BUF
	LD B,15				; Bound filename to 15 chars + null
TLP_CPY:
	LD A,(DE)
	OR A
	JR Z,TLP_CPY_DONE
	LD (HL),A
	INC DE
	INC HL
	DJNZ TLP_CPY
TLP_CPY_DONE:
	XOR A
	LD (HL),A			; Guarantee null terminator
	POP HL
	POP BC
	LD HL,HOST_LOAD_PLUGIN_FAR
	JR TRAMP_FAR_CALL

HOST_LOAD_PLUGIN_FAR:
	LD DE,TRAMP_NAME_BUF
	JP LOAD_PLUGIN_BY_NAME

;------------------------------------------------------------------------------
; TRAMP_UNLOAD_SLOT: Host API trampoline to unload plugin slot across banks
;
; Purpose:
;   Calls UNLOAD_PLUGIN_SLOT across memory banks to unregister slot A (0..7).
;
; Call Usage / Protocol:
;   Called via PLUGIN_HOST_API jump vector (+58).
;
; Inputs:
;   A = Slot number (0..7).
;
; Outputs:
;   Slot unloaded.
;
; Preserves / Modifies:
;   Preserves caller bank context.
;------------------------------------------------------------------------------
TRAMP_UNLOAD_SLOT:
	; Input: A = slot number (0..7)
	LD C,A
	LD A,(PLUGIN_IS_FAR_EXEC)
	OR A
	JR Z,TUS_DIRECT
	LD A,C
	LD HL,UNLOAD_PLUGIN_SLOT
	JR TRAMP_FAR_CALL
TUS_DIRECT:
	LD A,C
	JP UNLOAD_PLUGIN_SLOT

;------------------------------------------------------------------------------
; TRAMP_REDRAW_BASE: Host API trampoline to repaint underlying screen context
;
; Purpose:
;   Calls REDRAW_BASE_SCREEN across memory banks to repaint screen context A.
;
; Call Usage / Protocol:
;   Called via PLUGIN_HOST_API jump vector (+61).
;
; Inputs:
;   A = Context ID (0..6).
;
; Outputs:
;   Screen repainted.
;
; Preserves / Modifies:
;   Preserves caller bank context.
;------------------------------------------------------------------------------
TRAMP_REDRAW_BASE:
	; Input: A = Context ID (0..6)
	LD C,A
	LD A,(PLUGIN_IS_FAR_EXEC)
	OR A
	JR Z,TRB_DIRECT
	LD A,C
	LD HL,HOST_REDRAW_BASE_FAR
	JR TRAMP_FAR_CALL
TRB_DIRECT:
	LD (POPUP_CONTEXT_ID),A
	JP REDRAW_BASE_SCREEN

HOST_REDRAW_BASE_FAR:
	LD (POPUP_CONTEXT_ID),A
	JP REDRAW_BASE_SCREEN

;------------------------------------------------------------------------------
; TRAMP_OPEN_PLUGIN_UI: Host API trampoline for interactive plugin file selector
;
; Purpose:
;   Sets IS_PLUGIN_LOAD_UI flag and invokes DO_OPEN_FILE_UI across memory banks
;   to present plugin file browsing modal dialog.
;
; Call Usage / Protocol:
;   Called via PLUGIN_HOST_API jump vector (+64).
;
; Inputs:
;   None.
;
; Outputs:
;   Carry = 0 and A = loaded slot on success; Carry = 1 on cancellation.
;
; Preserves / Modifies:
;   Preserves caller bank context.
;------------------------------------------------------------------------------
TRAMP_OPEN_PLUGIN_UI:
	; Interactive file selector for plugin files (.PRL/.OVL)
	; Returns Carry=0, A=slot on success; Carry=1 on cancel
	LD A,(PLUGIN_IS_FAR_EXEC)
	OR A
	JR Z,TOPU_DIRECT
	LD HL,HOST_OPEN_PLUGIN_UI_FAR
	JR TRAMP_FAR_CALL
TOPU_DIRECT:
	LD A,1
	LD (IS_PLUGIN_LOAD_UI),A
	JP DO_OPEN_FILE_UI

HOST_OPEN_PLUGIN_UI_FAR:
	LD A,1
	LD (IS_PLUGIN_LOAD_UI),A
	JP DO_OPEN_FILE_UI

;------------------------------------------------------------------------------
; TRAMP_SAVE_PLUGIN_CFG: Host API trampoline to save plugin config to disk
;
; Purpose:
;   Copies 128 bytes from DE to CFG_IO_BUF and calls HOST_SAVE_PLUGIN_CFG_DISK
;   across memory banks to write PLUGIN.CFG.
;
; Call Usage / Protocol:
;   Called via PLUGIN_HOST_API jump vector (+67).
;
; Inputs:
;   DE = Pointer to 128-byte configuration buffer.
;
; Outputs:
;   Carry = 0 on success, Carry = 1 on disk error.
;
; Preserves / Modifies:
;   Preserves caller bank context.
;------------------------------------------------------------------------------
TRAMP_SAVE_PLUGIN_CFG:
	; Input: DE = pointer to 128-byte buffer
	LD HL,CFG_IO_BUF
	EX DE,HL			; HL = user buffer, DE = CFG_IO_BUF
	LD BC,128
	LDIR
	LD HL,HOST_SAVE_PLUGIN_CFG_DISK
	JR TRAMP_FAR_CALL

;------------------------------------------------------------------------------
; TRAMP_LOAD_PLUGIN_CFG: Host API trampoline to load plugin config from disk
;
; Purpose:
;   Calls HOST_LOAD_PLUGIN_CFG_DISK across memory banks and copies 128 bytes
;   from CFG_IO_BUF into caller's buffer at DE.
;
; Call Usage / Protocol:
;   Called via PLUGIN_HOST_API jump vector (+70).
;
; Inputs:
;   DE = Pointer to destination 128-byte buffer.
;
; Outputs:
;   Carry = 0 on success, Carry = 1 on read error or file not found.
;
; Preserves / Modifies:
;   Preserves caller bank context.
;------------------------------------------------------------------------------
TRAMP_LOAD_PLUGIN_CFG:
	; Input: DE = pointer to 128-byte buffer
	PUSH DE				; Preserve destination
	LD HL,HOST_LOAD_PLUGIN_CFG_DISK
	CALL TRAMP_FAR_CALL
	POP DE
	RET C				; On read error, return Carry = 1
	LD HL,CFG_IO_BUF
	LD BC,128
	LDIR
	OR A
	RET

;------------------------------------------------------------------------------
; TRAMP_RENDER_STATUS_BAR: Host API trampoline to redraw editor status bar
;
; Purpose:
;   Calls RENDER_STATUS_BAR across memory banks to refresh status line.
;
; Call Usage / Protocol:
;   Called via PLUGIN_HOST_API jump vector (+73).
;
; Inputs:
;   None.
;
; Outputs:
;   Status bar updated on terminal.
;
; Preserves / Modifies:
;   Preserves caller bank context.
;------------------------------------------------------------------------------
TRAMP_RENDER_STATUS_BAR:
	LD A,(PLUGIN_IS_FAR_EXEC)
	OR A
	JP Z,RENDER_STATUS_BAR
	LD HL,RENDER_STATUS_BAR
	JP TRAMP_FAR_CALL

;------------------------------------------------------------------------------
; TRAMP_FAR_CALL: Core cross-bank subroutine invocation trampoline
;
; Purpose:
;   Switches from calling Far RAM bank to CPM_USER_BANK, calls Bank 0 function
;   at HL, preserves return status and flags, and restores Far RAM bank.
;
; Call Usage / Protocol:
;   Called via CALL from Host API trampolines.
;
; Inputs:
;   HL = Target function address in Bank 0.
;   AF, BC, DE passed as arguments to target function.
;
; Outputs:
;   Target return values returned in AF, BC, DE, HL; caller bank restored.
;
; Preserves / Modifies:
;   Preserves return flags from target function.
;------------------------------------------------------------------------------
TRAMP_FAR_CALL:
	PUSH AF				; Preserve input AF (parameters)
	LD A,(CPM_USER_BANK)
	CALL 0FFF3H
	EI
	POP AF				; Restore input AF
	CALL CALL_HL		; Call target function with original AF, BC, DE
	PUSH AF				; Preserve return AF (results & Carry)
	DI
	LD A,(PLUGIN_FAR_BANK)
	CALL 0FFF3H
	POP AF				; Restore return AF
	RET

;------------------------------------------------------------------------------
; EXEC_PLUGIN_MGR_ACTION: Execute specific entry point of PLUGIN.PRL via HBIOS
;
; Purpose:
;   Sets Host API geometry and context fields, sets IX to entry point
;   0x0100 + C * 3, sets IY to PLUGIN_HOST_API, sets Far RAM bank, and invokes
;   HBIOS HB_BNKCALL (0xFFF9).
;
; Call Usage / Protocol:
;   Called via CALL to launch Plugin Manager actions (0..3).
;
; Inputs:
;   C = Action index (0 = Manager UI, 1 = Popup, 2 = About, 3 = Autoload).
;
; Outputs:
;   Returns registers and Carry flag from PLUGIN.PRL.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
EXEC_PLUGIN_MGR_ACTION:
	; Input: C = Action index (0 = Plugin Manager, 1 = Context Popup, 2 =
	; About)
	; Output: Returns Carry and registers from PLUGIN.PRL
	LD A,1
	LD (PLUGIN_IS_FAR_EXEC),A
	; Synchronize screen geometry and context in Host API (+14, +15, +16,
	; +17)
	LD A,(ACTIVE_COLS)
	LD (HOST_API_COLS),A
	LD A,(POPUP_CONTEXT_ID)
	LD (HOST_API_CONTEXT),A
	LD A,(ACTIVE_ROWS)
	LD (HOST_API_ROWS),A
	LD A,0FFH
	LD (HOST_API_MGR_SLOT),A

	; Calculate entry address: 0x0100 + C * 3
	LD HL,0100H
	LD A,C
	OR A
	JR Z,EPMA_ENTRY
	ADD A,A				; C * 2
	ADD A,C				; C * 3
	LD C,A
	LD B,0
	ADD HL,BC
EPMA_ENTRY:
	PUSH HL
	POP IX			; IX = entry point (0x0100, 0x0103, 0x0106)
	LD IY,PLUGIN_HOST_API
	LD A,(PLUGIN_MGR_BANK)
	LD (PLUGIN_FAR_BANK),A	; In case host trampolines need PLUGIN_FAR_BANK
	DI
	CALL 0FFF9H			; HB_BNKCALL
	EI
	PUSH AF
	XOR A
	LD (PLUGIN_IS_FAR_EXEC),A
	POP AF
	RET

;------------------------------------------------------------------------------
; BORROW_PLUGIN_MGR_BANK: Reserve dedicated Far RAM bank for PLUGIN.PRL
;
; Purpose:
;   Decrements EXT_BANK_COUNT (requiring >= 2 banks) and allocates a dedicated
;   Far RAM bank for hosting PLUGIN.PRL permanently in memory.
;
; Call Usage / Protocol:
;   Called via CALL from ENSURE_PLUGIN_MGR_LOADED.
;
; Inputs:
;   EXT_BANK_COUNT, EXT_BANK_TABLE.
;
; Outputs:
;   Carry = 0, A = allocated Far RAM bank ID; Carry = 1 if insufficient banks.
;
; Preserves / Modifies:
;   Clobbers AF, DE, HL; preserves BC.
;------------------------------------------------------------------------------
BORROW_PLUGIN_MGR_BANK:
	LD A,(EXT_BANK_COUNT)
	CP 2
	JR C,BPMB_FAIL			; Keep at least 1 bank for document
	DEC A
	LD (EXT_BANK_COUNT),A		; Decrement available document banks
	LD E,A
	LD D,0
	LD HL,EXT_BANK_TABLE
	ADD HL,DE
	LD A,(HL)			; A = Stolen Far RAM Bank ID
	OR A				; Carry = 0
	RET
BPMB_FAIL:
	SCF
	RET

;------------------------------------------------------------------------------
; ENSURE_PLUGIN_MGR_LOADED: Ensure PLUGIN.PRL is loaded into dedicated bank
;
; Purpose:
;   Checks PLUGIN_MGR_LOADED flag. If not loaded, verifies Far RAM bank count,
;   borrows bank, reads PLUGIN.PRL via BDOS, copies payload to Far RAM bank,
;   and executes Action 3 (Autoload plugins from PLUGIN.CFG).
;
; Call Usage / Protocol:
;   Called via CALL on editor startup and when opening Plugin Manager.
;
; Inputs:
;   None.
;
; Outputs:
;   Carry = 0 if loaded; Carry = 1 on file open or read error.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
ENSURE_PLUGIN_MGR_LOADED:
	LD A,(PLUGIN_MGR_LOADED)
	OR A
	RET NZ				; Already loaded! Carry = 0

	; Check if plugin manager autoload is disabled in config
	LD A,(CFG_AUTOLOAD_PLUGIN_MGR)
	OR A
	JP Z,EPML_FAIL

	; Check if Far RAM is available (at least 2 banks: 1 for doc, 1 for
	; plugin mgr)
	LD A,(EXT_BANK_COUNT)
	CP 2
	JP C,EPML_FAIL

	; Borrow a dedicated Far RAM bank for PLUGIN.PRL (not in
	; BORROWED_BANKS_TBL)
	CALL BORROW_PLUGIN_MGR_BANK
	JP C,EPML_FAIL
	LD (PLUGIN_MGR_BANK),A

	; Open PLUGIN.PRL
	LD HL,STR_DEF_PLUGIN_MGR
	CALL PARSE_STRING_TO_PLUGIN_FCB

	; Query current user
	LD E,0FFH
	LD C,32
	CALL BDOS_ENTRY
	LD (PLUGIN_ORIG_USER),A

	; Target user
	LD A,(PLUGIN_USER_AREA)
	LD E,A
	LD C,32
	CALL BDOS_ENTRY

	; Open file
	LD DE,PLUGIN_FCB
	LD C,15
	CALL BDOS_ENTRY
	CP 0FFH
	JP Z,EPML_FILE_ERR

	; Set BDOS DMA to LINE_STORAGE + 4096
	LD DE,LINE_STORAGE + 4096
	LD C,26
	CALL BDOS_ENTRY

	; Read first 2 sectors (256-byte header)
	LD DE,PLUGIN_FCB
	LD C,20
	CALL BDOS_ENTRY
	OR A
	JP NZ,EPML_READ_ERR

	LD DE,LINE_STORAGE + 4096 + 128
	LD C,26
	CALL BDOS_ENTRY

	LD DE,PLUGIN_FCB
	LD C,20
	CALL BDOS_ENTRY
	OR A
	JP NZ,EPML_READ_ERR

	; Copy 256-byte header to PLUGIN_MGR_BANK at 0x0000
	PUSH IX
	LD B,0F4H
	LD A,(PLUGIN_MGR_BANK)
	LD D,A
	LD A,(CPM_USER_BANK)
	LD E,A
	LD HL,256
	IFDEF TARGET_NEXT
	CALL NEXT_SYSSETCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	PUSH IX
	LD B,0F5H
	LD HL,LINE_STORAGE + 4096
	LD DE,0000H
	IFDEF TARGET_NEXT
	CALL NEXT_SYSBNKCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	; Calculate sector count from PROG_SIZE at (LINE_STORAGE + 4096 + 1)
	LD HL,(LINE_STORAGE + 4096 + 1)		; PROG_SIZE
	LD DE,127
	ADD HL,DE
	SRL H
	RR L
	SRL H
	RR L
	SRL H
	RR L
	SRL H
	RR L
	SRL H
	RR L
	SRL H
	RR L
	SRL H
	RR L
	LD (PAYLOAD_SECTORS_REMAIN),HL

	LD HL,0100H			; Code destination in PLUGIN_MGR_BANK
	LD (FAR_SECT_DEST),HL

EPML_SECTOR_LOOP:
	LD HL,(PAYLOAD_SECTORS_REMAIN)
	LD A,H
	OR L
	JR Z,EPML_SECTORS_DONE
	DEC HL
	LD (PAYLOAD_SECTORS_REMAIN),HL

	LD DE,LINE_STORAGE + 4096
	LD C,26
	CALL BDOS_ENTRY

	LD DE,PLUGIN_FCB
	LD C,20
	CALL BDOS_ENTRY
	OR A
	JP NZ,EPML_READ_ERR

	PUSH IX
	LD B,0F4H
	LD A,(PLUGIN_MGR_BANK)
	LD D,A
	LD A,(CPM_USER_BANK)
	LD E,A
	LD HL,128
	IFDEF TARGET_NEXT
	CALL NEXT_SYSSETCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	PUSH IX
	LD B,0F5H
	LD HL,LINE_STORAGE + 4096
	LD DE,(FAR_SECT_DEST)
	IFDEF TARGET_NEXT
	CALL NEXT_SYSBNKCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	LD HL,(FAR_SECT_DEST)
	LD DE,128
	ADD HL,DE
	LD (FAR_SECT_DEST),HL
	JR EPML_SECTOR_LOOP

EPML_SECTORS_DONE:
	; Close FCB
	LD DE,PLUGIN_FCB
	LD C,16
	CALL BDOS_ENTRY

	; Restore original user area
	LD A,(PLUGIN_ORIG_USER)
	LD E,A
	LD C,32
	CALL BDOS_ENTRY

	; Restore DMA to 0080H
	LD DE,0080H
	LD C,26
	CALL BDOS_ENTRY

	LD A,1
	LD (PLUGIN_MGR_LOADED),A
	LD C,3				; Action 3: Autoload from PLUGIN.CFG
	CALL EXEC_PLUGIN_MGR_ACTION
	OR A					; Carry = 0
	RET

EPML_READ_ERR:
	; Close FCB
	LD DE,PLUGIN_FCB
	LD C,16
	CALL BDOS_ENTRY

EPML_FILE_ERR:
	; Restore original user area
	LD A,(PLUGIN_ORIG_USER)
	LD E,A
	LD C,32
	CALL BDOS_ENTRY

	; Restore DMA to 0080H
	LD DE,0080H
	LD C,26
	CALL BDOS_ENTRY

	; Release bank
	LD A,(PLUGIN_MGR_BANK)
	CALL RELEASE_FAR_BANK

EPML_FAIL:
	XOR A
	LD (PLUGIN_MGR_LOADED),A
	SCF					; Carry = 1
	RET

;------------------------------------------------------------------------------
; AUTO_LOAD_PLUGIN_MGR: Probe and autoload Plugin Manager on editor startup
;
; Purpose:
;   Checks CFG_AUTOLOAD_PLUGIN_MGR setting and Far RAM availability; if enabled,
;   invokes ENSURE_PLUGIN_MGR_LOADED to pre-load plugins from PLUGIN.CFG.
;
; Call Usage / Protocol:
;   Called via CALL from START during initial program boot.
;
; Inputs:
;   CFG_AUTOLOAD_PLUGIN_MGR, EXT_BANK_COUNT.
;
; Outputs:
;   None.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
AUTO_LOAD_PLUGIN_MGR:
	LD A,(EXT_BANK_COUNT)
	CP 2
	JR NC,ALPM_CHK_CFG
	XOR A
	LD (CFG_AUTOLOAD_PLUGIN_MGR),A
	RET
ALPM_CHK_CFG:
	LD A,(CFG_AUTOLOAD_PLUGIN_MGR)
	CP PLUGIN_MODE_AUTOLOAD
	RET NZ
	CALL ENSURE_PLUGIN_MGR_LOADED
	RET

;==============================================================================
; Plugin Configuration File Management (PLUGIN.CFG)
;==============================================================================
STR_PLUGIN_CFG_NAME:	DB	"PLUGIN  CFG"

;------------------------------------------------------------------------------
; INIT_PLUGIN_CFG_FCB: Initialize CFG_FCB with "PLUGIN  CFG" filename
;
; Purpose:
;   Sets default drive (0), copies "PLUGIN  CFG" into CFG_FCB, and clears
;   extent and record count fields.
;
; Call Usage / Protocol:
;   Called via CALL before opening or creating PLUGIN.CFG.
;
; Inputs:
;   None.
;
; Outputs:
;   CFG_FCB initialized.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
INIT_PLUGIN_CFG_FCB:
	LD DE,CFG_FCB
	XOR A
	LD (DE),A			; Default drive (0)
	INC DE
	LD HL,STR_PLUGIN_CFG_NAME
	LD BC,11
	LDIR
	EX DE,HL			; HL = CFG_FCB + 12
	LD B,24
	JP INIT_CFG_ZERO

;------------------------------------------------------------------------------
; BDOS_CFG_FCB: Helper to execute BDOS file operation on CFG_FCB
;
; Purpose:
;   Sets DE = CFG_FCB and jumps directly to BDOS_ENTRY.
;
; Call Usage / Protocol:
;   Called via CALL for PLUGIN.CFG operations.
;
; Inputs:
;   C = BDOS function code.
;
; Outputs:
;   A = BDOS return status.
;
; Preserves / Modifies:
;   Clobbers AF, DE.
;------------------------------------------------------------------------------
BDOS_CFG_FCB:
	LD DE,CFG_FCB
	JP BDOS_ENTRY

;------------------------------------------------------------------------------
; BDOS_CFG_DMA: Set BDOS DMA transfer address to CFG_IO_BUF
;
; Purpose:
;   Sets DE = CFG_IO_BUF and calls BDOS Set DMA (function 26).
;
; Call Usage / Protocol:
;   Called via CALL prior to reading or writing PLUGIN.CFG records.
;
; Inputs:
;   None.
;
; Outputs:
;   DMA address configured to CFG_IO_BUF.
;
; Preserves / Modifies:
;   Clobbers AF, DE.
;------------------------------------------------------------------------------
BDOS_CFG_DMA:
	LD DE,CFG_IO_BUF
	LD C,26
	JP BDOS_ENTRY

;------------------------------------------------------------------------------
; BDOS_RESTORE_DMA: Restore default BDOS DMA transfer address (0080H)
;
; Purpose:
;   Sets DE = DEFAULT_DMA (0080H) and calls BDOS Set DMA (function 26).
;
; Call Usage / Protocol:
;   Called via CALL following completion of PLUGIN.CFG I/O.
;
; Inputs:
;   None.
;
; Outputs:
;   DMA address restored to 0080H.
;
; Preserves / Modifies:
;   Clobbers AF, DE.
;------------------------------------------------------------------------------
BDOS_RESTORE_DMA:
	LD DE,DEFAULT_DMA
	LD C,26
	JP BDOS_ENTRY

;------------------------------------------------------------------------------
; HOST_SAVE_PLUGIN_CFG_DISK: Write 128-byte configuration to PLUGIN.CFG file
;
; Purpose:
;   Sets DMA to CFG_IO_BUF, deletes existing PLUGIN.CFG, creates new file,
;   writes 128-byte record from CFG_IO_BUF, closes file, and restores DMA.
;
; Call Usage / Protocol:
;   Called via CALL or JP from TRAMP_SAVE_PLUGIN_CFG.
;
; Inputs:
;   CFG_IO_BUF populated with 128 bytes of configuration data.
;
; Outputs:
;   Carry = 0 on success, Carry = 1 on disk error.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HOST_SAVE_PLUGIN_CFG_DISK:
	CALL BDOS_CFG_DMA
	CALL INIT_PLUGIN_CFG_FCB
	LD C,19				; Delete existing PLUGIN.CFG
	CALL BDOS_CFG_FCB
	CALL INIT_PLUGIN_CFG_FCB
	LD C,22				; Make PLUGIN.CFG
	CALL BDOS_CFG_FCB
	INC A
	JR Z,HSPC_ERR
	LD C,21				; Write record
	CALL BDOS_CFG_FCB
	OR A
	JR NZ,HSPC_ERR_CLOSE
	LD C,16				; Close file
	CALL BDOS_CFG_FCB
	INC A
	JR Z,HSPC_ERR
	CALL BDOS_RESTORE_DMA
	OR A				; Carry = 0 (Success)
	RET

HSPC_ERR_CLOSE:
	LD C,16
	CALL BDOS_CFG_FCB
HSPC_ERR:
	CALL BDOS_RESTORE_DMA
	SCF				; Carry = 1 (Error)
	RET

;------------------------------------------------------------------------------
; HOST_LOAD_PLUGIN_CFG_DISK: Read 128-byte configuration from PLUGIN.CFG file
;
; Purpose:
;   Sets DMA to CFG_IO_BUF, opens PLUGIN.CFG, reads 128-byte record into
;   CFG_IO_BUF, closes file, and restores DMA to 0080H.
;
; Call Usage / Protocol:
;   Called via CALL or JP from TRAMP_LOAD_PLUGIN_CFG.
;
; Inputs:
;   None.
;
; Outputs:
;   Carry = 0 on success; Carry = 1 on file not found or read error.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HOST_LOAD_PLUGIN_CFG_DISK:
	CALL BDOS_CFG_DMA
	CALL INIT_PLUGIN_CFG_FCB
	LD C,15				; Open
	CALL BDOS_CFG_FCB
	INC A
	JR Z,HLPC_NOT_FOUND

	; Pre-fill CFG_IO_BUF with 1AH (CP/M EOF)
	LD HL,CFG_IO_BUF
	LD (HL),1AH
	LD DE,CFG_IO_BUF+1
	LD BC,127
	LDIR

	LD C,20				; Read
	CALL BDOS_CFG_FCB
	OR A
	JR NZ,HLPC_READ_ERR
	LD C,16				; Close
	CALL BDOS_CFG_FCB
	CALL BDOS_RESTORE_DMA
	OR A				; Carry = 0 (Success)
	RET

HLPC_READ_ERR:
	LD C,16				; Close
	CALL BDOS_CFG_FCB
	CALL BDOS_RESTORE_DMA
	SCF				; Carry = 1 (Error)
	RET
HLPC_NOT_FOUND:
	CALL BDOS_RESTORE_DMA
	SCF				; Carry = 1 (File not found)
	RET

;------------------------------------------------------------------------------
; HOST_CLEAR_DOCUMENT: Reset editor state and line table to empty document
;
; Purpose:
;   Initializes slot allocation table, resets line counts and cursor coordinates
;   to zero, clears cache dirty flags, and resets document modification flags.
;
; Call Usage / Protocol:
;   Called via CALL or JP from TRAMP_CLEAR_DOCUMENT.
;
; Inputs:
;   None.
;
; Outputs:
;   Document initialized to empty state.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HOST_CLEAR_DOCUMENT:
	CALL INIT_SLOT_SYSTEM
	LD HL,0
	LD (DOC_TOTAL_LINES),HL
	LD (CUR_DOC_ROW),HL
	LD (TOP_DOC_ROW),HL
	LD (CACHE_START_ROW),HL
	LD (CUR_COL),HL
	LD (TARGET_COL),HL
	LD (VIEW_LEFT_COL),HL
	CALL CLEAR_CACHE_DIRTY_FLAGS
	XOR A
	LD (ACTIVE_LINE_DIRTY),A
	LD HL,0FFFFH
	LD (ACTIVE_LINE_ROW),HL
	XOR A
	LD (DOC_MODIFIED),A
	LD (DOC_IS_FAT),A
	DEC A
	LD (FAT_DOC_UNIT),A
	XOR A
	LD (BLOCK_ACTIVE),A
	LD (STATUS_OOM_FLAG),A
	LD (FILE_IS_TRUNCATED),A
	LD (ACTIVE_LINE_BUF),A
	LD HL,0
	LD (ACTIVE_LINE_LEN),HL
	RET

;------------------------------------------------------------------------------
; HOST_CHECKOUT_LINE: Checkout line HL into ACTIVE_LINE_BUF and return length
;
; Purpose:
;   Sets CUR_DOC_ROW to HL, checks out line from far RAM into ACTIVE_LINE_BUF,
;   measures line length, and returns length in BC and ACTIVE_LINE_LEN.
;
; Call Usage / Protocol:
;   Called via CALL or JP from TRAMP_CHECKOUT_LINE.
;
; Inputs:
;   HL = Line index to checkout.
;
; Outputs:
;   ACTIVE_LINE_BUF populated, BC = Line length.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HOST_CHECKOUT_LINE:
	LD (CUR_DOC_ROW),HL
	CALL CHECKOUT_ACTIVE_LINE
	CALL GET_CUR_ROW_LEN
	LD (ACTIVE_LINE_LEN),DE
	LD B,D
	LD C,E				; BC = line length
	RET

;------------------------------------------------------------------------------
; HOST_COMMIT_LINE: Commit line buffer at DE to document line table at row HL
;
; Purpose:
;   Ensures null termination of line buffer at DE, checks whether line index HL
;   appends to end of document (HL == DOC_TOTAL_LINES) or overwrites existing
;   line (HL < DOC_TOTAL_LINES), and writes line data to far RAM storage.
;
; Call Usage / Protocol:
;   Called via CALL or JP from TRAMP_COMMIT_LINE.
;
; Inputs:
;   HL = Target line number.
;   DE = Pointer to line buffer (must reside in common RAM).
;   BC = Line length.
;
; Outputs:
;   Line committed to far RAM; Carry = 1 on out-of-memory.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HOST_COMMIT_LINE:
	; Inputs:
	; HL = line number
	; DE = buffer pointer (must be in Common RAM)
	; BC = line length
	PUSH AF
	PUSH HL
	PUSH DE
	EX DE,HL
	ADD HL,BC
	LD (HL),0			; Defensively ensure null termination
	POP DE
	LD HL,(ACTIVE_LINE_ROW)
	LD A,H
	AND L
	INC A
	POP HL
	JR NZ,HCL_ACTIVE_RESTORE	; ACTIVE_LINE_ROW != 0xFFFF

	; ACTIVE_LINE_ROW == 0xFFFF. Compare HL with DOC_TOTAL_LINES
	PUSH BC
	PUSH DE
	LD DE,(DOC_TOTAL_LINES)
	LD A,H
	CP D
	JR NZ,HCL_NOT_EQUAL
	LD A,L
	CP E
	JR NZ,HCL_NOT_EQUAL

	; HL == DOC_TOTAL_LINES -> Append mode
	POP DE				; Restore buffer pointer
	POP BC				; Restore length
	POP AF				; Clean stack
	CALL APPEND_LINE_SLOT		; BC = allocated slot ID, Carry on OOM
	RET C
	LD BC,(DOC_TOTAL_LINES)		; BC = line index
	EX DE,HL			; HL = buffer pointer
	CALL WRITE_FAR_LINE
	LD HL,(DOC_TOTAL_LINES)
	INC HL
	LD (DOC_TOTAL_LINES),HL
	OR A
	RET

HCL_NOT_EQUAL:
	; Check if HL < DOC_TOTAL_LINES
	EX DE,HL			; HL = DOC_TOTAL_LINES, DE = line_num
	OR A
	SBC HL,DE		; If line_num < DOC_TOTAL_LINES, Carry = 0, NZ
	EX DE,HL			; HL = line_num
	JR C,HCL_OUT_OF_BOUNDS		; line_num > DOC_TOTAL_LINES
	; HL < DOC_TOTAL_LINES -> Overwrite mode
	POP DE				; Restore buffer pointer
	POP BC				; Restore length
	POP AF				; Clean stack
	LD B,H
	LD C,L				; BC = line index
	EX DE,HL			; HL = buffer pointer
	CALL WRITE_FAR_LINE
	OR A
	RET

HCL_OUT_OF_BOUNDS:
	POP DE
	POP BC
HCL_ACTIVE_RESTORE:
	POP AF
HCL_ACTIVE:
	LD A,1
	LD (ACTIVE_LINE_DIRTY),A
	CALL COMMIT_ACTIVE_LINE
	OR A
	RET

;------------------------------------------------------------------------------
; HOST_SET_STATUS_MSG: Display status message in Tier 2 modal popup
;
; Purpose:
;   Tests if message pointer DE is non-null; if valid, invokes
;   SHOW_PLUGIN_STATUS_POPUP while preserving all working registers.
;
; Call Usage / Protocol:
;   Called via CALL or JP from TRAMP_SET_STATUS_MSG.
;
; Inputs:
;   DE = Pointer to null-terminated status message string.
;
; Outputs:
;   Modal popup displayed.
;
; Preserves / Modifies:
;   Preserves all registers (AF, BC, DE, HL).
;------------------------------------------------------------------------------
HOST_SET_STATUS_MSG:
	LD A,D
	OR E
	RET Z
	; Display plugin notification in centered Tier 2 modal pop-up
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL
	CALL SHOW_PLUGIN_STATUS_POPUP
	POP HL
	POP DE
	POP BC
	POP AF
	RET

;------------------------------------------------------------------------------
; SHOW_PLUGIN_STATUS_POPUP: Center message and display modal status popup
;
; Purpose:
;   Initializes 50-character popup line buffer with border bars, calculates
;   centering padding, copies message text from DE into buffer, and invokes
;   SHOW_STATUS_EVENT_POPUP to render centered modal dialog box.
;
; Call Usage / Protocol:
;   Called via CALL from HOST_SET_STATUS_MSG.
;
; Inputs:
;   DE = Pointer to null-terminated status string.
;
; Outputs:
;   Popup dialog rendered on terminal.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SHOW_PLUGIN_STATUS_POPUP:
	; DE = pointer to plugin status string
	; Copy and center inside PLUGIN_POPUP_MSG_BUF (50 chars: "| ... |", 0)
	PUSH DE

	; 1. Initialize buffer with spaces enclosed in '|'
	LD HL,PLUGIN_POPUP_MSG_BUF
	LD (HL),'|'
	INC HL
	LD B,48
SPSP_INIT_SPACE:
	LD (HL),' '
	INC HL
	DJNZ SPSP_INIT_SPACE
	LD (HL),'|'
	INC HL
	LD (HL),0

	; 2. Measure string length in DE (max 46 chars)
	POP HL				; HL = source string
	PUSH HL
	LD C,0
SPSP_LEN_LOOP:
	LD A,(HL)
	OR A
	JR Z,SPSP_LEN_DONE
	CP '$'
	JR Z,SPSP_LEN_DONE
	INC HL
	INC C
	LD A,C
	CP 46
	JR C,SPSP_LEN_LOOP
SPSP_LEN_DONE:
	LD A,C
	OR A
	JR NZ,SPSP_CALC_PAD
	INC C				; at least 1
SPSP_CALC_PAD:
	; Calculate left offset: ((48 - C) / 2) + 1
	LD A,48
	SUB C
	SRL A
	INC A
	LD E,A
	LD D,0
	LD HL,PLUGIN_POPUP_MSG_BUF
	ADD HL,DE			; HL = target in buffer
	POP DE				; DE = source string
	LD B,C
SPSP_COPY_LOOP:
	LD A,(DE)
	LD (HL),A
	INC DE
	INC HL
	DJNZ SPSP_COPY_LOOP

	; 3. Invoke Tier 2 status event pop-up
	LD DE,STR_POPUP_PLUGIN_TITLE
	LD HL,PLUGIN_POPUP_MSG_BUF
	LD BC,STR_POPUP_BLANK_ROW
	CALL SHOW_STATUS_EVENT_POPUP
	RET

LOCAL_STACK_TOP:
	DS 128
LOCAL_STACK:

