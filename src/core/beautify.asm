;==============================================================================
; BEAUTIFY.ASM: Core Subsystem - Z80 Assembly Beautifier & Column Alignment
;
; Purpose:
;   Formats labels, mnemonics, operands, and comments into aligned columns.
;   If BLOCK_ACTIVE != 0: beautifies only lines in selected block.
;   If BLOCK_ACTIVE == 0: beautifies entire open document.
;   If FMT_ANIMATE != 0: provides real-time animated visual tracking.
;   If FMT_ANIMATE == 0: runs fast batch in Far-RAM at full CPU speed.
;   Dispatches execution to BEAUTIFY.PRL plugin in Far RAM or loads from disk.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;==============================================================================
; Z80 Source Code Beautifier Subsystem (Ctrl+Y)
; Formats labels, mnemonics, operands, and comments into aligned columns.
; If BLOCK_ACTIVE != 0: beautifies only lines in selected block.
; If BLOCK_ACTIVE == 0: beautifies entire open document.
; If FMT_ANIMATE != 0: provides real-time animated visual tracking on terminal.
; If FMT_ANIMATE == 0: runs fast batch in Far-RAM at full CPU speed.
;==============================================================================

DO_CTRL_Y_BEAUTIFY:
	; Check if document is empty
	LD HL,(DOC_TOTAL_LINES)
	LD A,H
	OR L
	JP Z,MAIN_LOOP

	; Scan PLUGIN_REGISTRY for "BEAUTIFY"
	LD B,0
DO_CY_FIND_LOOP:
	PUSH BC
	CALL GET_REGISTRY_ENTRY_PTR
	POP BC
	; Check if slot is loaded (offset 22: SLOT_STATE != 0)
	PUSH HL
	LD DE,22
	ADD HL,DE
	LD A,(HL)
	POP HL
	OR A
	JR Z,DO_CY_NEXT_SLOT

	; Compare plugin name at (HL) with "BEAUTIFY"
	PUSH BC
	PUSH HL
	LD DE,STR_NAME_BEAUTIFY
	CALL COMPARE_PLUGIN_NAME
	POP HL
	POP BC
	JR Z,DO_CY_FOUND

DO_CY_NEXT_SLOT:
	INC B
	LD A,B
	CP PLUGIN_MAX_SLOTS
	JR NZ,DO_CY_FIND_LOOP

	; Not loaded in registry: dynamically load BEAUTIFY from disk
	LD DE,STR_NAME_BEAUTIFY
	CALL LOAD_PLUGIN_BY_NAME
	JR NC,DO_CY_LOADED_OK

	; Failed to load BEAUTIFY.PRL: display Tier 2 status event pop-up
	CALL SHOW_POPUP_PLUG_MISSING
	JP MAIN_LOOP

DO_CY_LOADED_OK:
	LD A,(PLUGIN_CUR_SLOT)
	JR DO_CY_EXEC

DO_CY_FOUND:
	LD A,B

DO_CY_EXEC:
	PUSH AF
	CALL CHECKOUT_ACTIVE_LINE
	CALL GET_CUR_ROW_LEN
	LD (ACTIVE_LINE_LEN),DE
	CALL SAVE_EDITOR_PLUGIN_STATE
	CALL FLUSH_DIRTY_CACHE
	LD HL,0FFFFH
	LD (CACHE_START_ROW),HL
	POP AF
	CALL EXEC_PLUGIN_SLOT
	; Clear block mode after beautify
	XOR A
	LD (BLOCK_ACTIVE),A
	; Clear plugin status msg ptr so normal status bar is restored
	LD HL,0
	LD (PLUGIN_STATUS_MSG_PTR),HL
	CALL INVALIDATE_ACTIVE_LINE
	CALL RESTORE_EDITOR_PLUGIN_STATE
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	CALL LOCATE_CURSOR
	JP MAIN_LOOP

;------------------------------------------------------------------------------
; COMPARE_PLUGIN_NAME: Compare two null-terminated strings for equality
;
; Purpose:
;   Performs character-by-character string comparison between null-terminated
;   strings pointed to by HL and DE (typically comparing a registered plugin
;   name against a target query string).
;
; Call Usage / Protocol:
;   Called via CALL or JR from plugin search and registry lookup routines.
;
; Inputs:
;   HL = Pointer to first null-terminated string.
;   DE = Pointer to second null-terminated string.
;
; Outputs:
;   Zero flag (Z) set if strings match; NZ if characters differ.
;
; Preserves / Modifies:
;   HL, DE advance to point of difference or terminating null; clobbers AF.
;   Preserves BC.
;------------------------------------------------------------------------------
COMPARE_PLUGIN_NAME:
	LD A,(DE)
	CP (HL)
	RET NZ
	OR A
	RET Z
	INC HL
	INC DE
	JR COMPARE_PLUGIN_NAME


