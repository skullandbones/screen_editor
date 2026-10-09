;==============================================================================
; SE_NEXT_CPM.ASM: Full-Screen Text Editor for CP/M on ZX Spectrum Next
; Target: Z80 CPU, NextCPM 80-Column Display, Next MMU Banked Memory
;
; Copyright Dean Jenkins. Source code created by Antigravity AI.
; View file using 8 'spaces' per tab.
;==============================================================================

	ORG $0100

TARGET_NEXT		EQU	1
TARGET_NEXT_CPM		EQU	1

;------------------------------------------------------------------------------
; Subsystem Interface Headers & Constants
;------------------------------------------------------------------------------
	INCLUDE "include/config.inc"
	INCLUDE "include/hal.inc"
	INCLUDE "include/buffer.inc"
	INCLUDE "include/editor.inc"
	INCLUDE "include/block.inc"
	INCLUDE "include/search.inc"
	INCLUDE "include/ui.inc"
	INCLUDE "include/file_io.inc"
	INCLUDE "include/plugin.inc"
	INCLUDE "include/beautify.inc"

; Hardware Abstraction Layer (Profile 1: Standard CP/M 2.2 / 3.0 / RomWBW)
	INCLUDE "hal/next_cpm/hal_nextcpm_memory.asm"
	INCLUDE "hal/next_cpm/hal_nextcpm_storage.asm"
	INCLUDE "hal/next_cpm/hal_nextcpm_keyboard.asm"

;------------------------------------------------------------------------------
; Main Entry Point
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; START: Main program entry point from CP/M console
;
; Purpose:
;   Initializes runtime environment, local stack, direct BIOS console vectors,
;   and terminal geometry. Queries CP/M version, user number, and current
;   drive. Parses command line parameters, loads configuration from SE.CFG,
;   detects and configures RAM drive via HIBERN.OVL, probes memory banking,
;   and dispatches to either CLI file autoload or splash screen.
;
; Call Usage / Protocol:
;   Executed directly by CP/M transient program loader at TPA address $0100.
;   Never called via CALL; exits to CP/M via JP 0000H (or EXIT_PROGRAM).
;
; Inputs:
;   Default DMA buffer at 0080H (command tail), FCB1 at 005CH.
;
; Outputs:
;   None (transfers control to DO_AUTO_LOAD or SHOW_SPLASH_SCREEN).
;
; Preserves / Modifies:
;   Initializes SP to LOCAL_STACK; clobbers all working registers.
;------------------------------------------------------------------------------
START:
	LD (SAVED_SP),SP
	LD SP,LOCAL_STACK

	; Query initial CP/M Version via BDOS 12 (Get Version Number)
	LD C,12
	CALL BDOS_ENTRY
	LD (CPM_VERSION_ID),HL

	; Query initial CP/M user area via BDOS 32 (Get User Number, E=0xFF)
	LD E,0FFH
	LD C,32
	CALL BDOS_ENTRY
	LD (ORIG_CPM_USER),A
	LD (CURRENT_DIR_USER),A
	LD (DOC_USER_NUM),A
	LD (WORK_FCB_USER),A
	LD (BLOCK_IO_USER),A

	; Query initial CP/M drive via BDOS 25 (Return Current Disk)
	LD C,25
	CALL BDOS_ENTRY
	LD (CURRENT_DEFAULT_DRIVE),A
	INC A				; 0..15 -> 1..16
	LD (CURRENT_DIR_DRIVE),A
	ADD A,'A'-1
	LD (STR_DIR_DRIVE_CHAR),A
	LD (STR_SAVE_DRIVE_CHAR),A

	; Initialize Direct BIOS Console Vectors
	CALL INIT_BIOS_JUMPS

	; Initialize Screen Geometry to Default (120x40)
	CALL SET_MODE_120X40

	; Check if filename was provided in FCB1 (populates WORK_FCB and
	; HAS_FILE_ARG)
	CALL CHECK_COMMAND_LINE

	; Load config from SE.CFG if present (local dir first, then program
	; drive)
	CALL LOAD_CONFIG

	; Process RAM drive via HIBERN.OVL
	LD A,(CFG_RAMDRIVE_FLAG)
	OR A
	JR Z,START_RAMDRV_DETECT
	; Mode 1 or 2: Detect, Validate safety & Hibernate if requested
	LD B,A			; B = requested mode (1=ENABLE, 2=HIBERNATE)
	LD A,1				; Action 1
	CALL RUN_HIBERN_STARTUP
	JR START_RAMDRV_DONE
START_RAMDRV_DETECT:
	; Mode 0: Detect RAM drive letter only
	XOR A				; Action 0
	CALL RUN_HIBERN_STARTUP
START_RAMDRV_DONE:

	; Initialize Terminal (Clear Screen & Home)
	CALL TERM_INIT

	; Query RomWBW User Bank and Initialize Far RAM Banks
	CALL BUFFER_INIT

	; Initialize search state to defaults (Case-sensitive = 1)
	LD A,1
	LD (SEARCH_CASE_SENSITIVE),A
	XOR A
	LD (SEARCH_LEN),A
	LD (REPLACE_LEN),A
	LD (DOC_MODIFIED),A
	LD (IN_EDITOR_MODE),A
	LD (IS_SPLASH_SCREEN),A
	LD (STATUS_OOM_FLAG),A
	LD (CONFIRM_ACTION),A
	LD (DOC_IS_FAT),A
	LD (PLUGIN_FAR_BANK),A
	LD (PLUGIN_LOAD_COUNT),A
	DEC A
	LD (FAT_DOC_UNIT),A
	XOR A
	LD HL,0
	LD (PLUGIN_STATUS_MSG_PTR),HL
	CALL INIT_PLUGIN_REGISTRY
	CALL AUTO_LOAD_PLUGIN_MGR

	; Initialize directory drive from default disk or FCB
	CALL INIT_DIR_DRIVE

	; If file argument was given, load file and go straight to editor
	LD A,(HAS_FILE_ARG)
	OR A
	JR NZ,DO_AUTO_LOAD

	; Otherwise show splash screen
	JP SHOW_SPLASH_SCREEN

;------------------------------------------------------------------------------
; DO_AUTO_LOAD: Load document file specified on command line
;
; Purpose:
;   Loads target file specified on the CLI into memory (handling either
;   native CP/M filesystem or VFS FAT filesystem), transitions to editor
;   mode, positions cursor at requested goto line if specified, renders
;   initial screen, and jumps to MAIN_LOOP.
;
; Call Usage / Protocol:
;   Jumped to from START when HAS_FILE_ARG is non-zero.
;
; Inputs:
;   WORK_FCB / FAT_DOC_PATH populated by CHECK_COMMAND_LINE.
;   CMDLINE_GOTO_LINE = target line number (0 if default line 1).
;
; Outputs:
;   Document loaded into Far RAM line table / cache; enters MAIN_LOOP.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
DO_AUTO_LOAD:
	LD A,(CMDLINE_IS_FAT)
	OR A
	JR NZ,DO_AUTO_LOAD_FAT

	CALL LOAD_FILE
	JP C,AUTO_LOAD_NOT_FOUND
	LD A,1
	LD (IN_EDITOR_MODE),A

	; Check if command-line specified a target goto line (> 0)
	LD HL,(CMDLINE_GOTO_LINE)
	LD A,H
	OR L
	JR Z,AUTO_LOAD_LINE_DEFAULT
	CALL GOTO_LINE_HL
	JR AUTO_LOAD_RENDER

;------------------------------------------------------------------------------
; AUTO_LOAD_LINE_DEFAULT: Initialize cursor to line 1 for autoloaded file
;
; Purpose:
;   Sets document row and column positions to top-left (0,0) when no
;   explicit line number was supplied on the command line.
;
; Call Usage / Protocol:
;   Jumped to from DO_AUTO_LOAD when CMDLINE_GOTO_LINE is 0.
;
; Inputs:
;   None
;
; Outputs:
;   CUR_DOC_ROW, TOP_DOC_ROW, CUR_COL, TARGET_COL initialized to 0.
;
; Preserves / Modifies:
;   Clobbers HL.
;------------------------------------------------------------------------------
AUTO_LOAD_LINE_DEFAULT:
	LD HL,0
	LD (CUR_DOC_ROW),HL
	LD (TOP_DOC_ROW),HL
	LD (CUR_COL),HL
	LD (TARGET_COL),HL

AUTO_LOAD_RENDER:
	CALL TERM_INIT
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	CALL CHECK_FILE_TRUNCATED_POPUP
	CALL LOCATE_CURSOR
	JP MAIN_LOOP

DO_AUTO_LOAD_FAT:
	CALL ENSURE_VFS_PLUGIN_LOADED
	JR C,ALNF_FAT_PLUGIN_ERR

	; Setup VFS request for loading file
	LD A,(CMDLINE_FAT_UNIT)
	LD (VFS_REQ_UNIT),A
	LD HL,FAT_DOC_PATH
	CALL VFS_LOAD_FAT_FILE
	JR C,AUTO_LOAD_FAT_NOT_FOUND

	; File loaded successfully!
	LD A,1
	LD (DOC_IS_FAT),A
	LD (IN_EDITOR_MODE),A
	XOR A
	LD (DOC_MODIFIED),A
	CALL INVALIDATE_ACTIVE_LINE
	CALL CHECKOUT_ACTIVE_LINE
	CALL RELOAD_CACHE_WINDOW_FORCE
	JP AUTO_LOAD_LINE_DEFAULT

AUTO_LOAD_FAT_NOT_FOUND:
	; Target file not found on FAT volume:
	; Open new empty document tagged with DOC_IS_FAT = 1
	CALL INIT_EMPTY_DOCUMENT
	XOR A
	LD (DOC_MODIFIED),A
	LD A,1
	LD (DOC_IS_FAT),A
	LD (IN_EDITOR_MODE),A
	LD (HAS_FILE_ARG),A
	JP AUTO_LOAD_LINE_DEFAULT

ALNF_FAT_PLUGIN_ERR:
	LD A,13
	CALL PUTC
	LD A,10
	CALL PUTC
	LD DE,STR_FATFS_PRL
	CALL PRINT_STR
	LD DE,STR_FILE_NOT_FOUND_SUFFIX
	CALL PRINT_STR
	CALL RESTORE_RAMDRIVE
	LD SP,(SAVED_SP)
	RET

AUTO_LOAD_NOT_FOUND:
	LD A,(CMDLINE_HAS_DRIVE)
	OR A
	JR NZ,ALNF_EXPLICIT_DRIVE

	; Bare filename ("SE <filename>"): open new empty file ready for editing
	CALL INIT_EMPTY_DOCUMENT
	XOR A
	LD (DOC_MODIFIED),A
	LD A,1
	LD (IN_EDITOR_MODE),A
	LD (HAS_FILE_ARG),A
	JP AUTO_LOAD_LINE_DEFAULT

ALNF_EXPLICIT_DRIVE:
	; Command line specified drive ("SE <n:filename>"): report "<n:filename>
	; file not found" and exit
	CALL FCB_TO_FILENAME_STR
	LD A,13
	CALL PUTC
	LD A,10
	CALL PUTC
	LD DE,INPUT_FILENAME_BUF
	CALL PRINT_STR
	LD DE,STR_FILE_NOT_FOUND_SUFFIX
	CALL PRINT_STR
	CALL RESTORE_RAMDRIVE
	LD SP,(SAVED_SP)
	RET

;------------------------------------------------------------------------------
; ENTER_EDITOR: Top-level entry into editor mode from splash screen loop
;
; Purpose:
;   Resets stack pointer to LOCAL_STACK, ensures document structures and
;   viewport are initialized, renders screen and status bar, positions
;   cursor, and enters main editor event loop.
;
; Call Usage / Protocol:
;   Jumped to from SPLASH_LOOP when user selects 'E' (Edit).
;
; Inputs:
;   None
;
; Outputs:
;   Transitions directly into MAIN_LOOP; does not return.
;
; Preserves / Modifies:
;   Resets SP to LOCAL_STACK; clobbers all working registers.
;------------------------------------------------------------------------------
ENTER_EDITOR:
	LD SP,LOCAL_STACK
	CALL SETUP_EDITOR_STATE
	CALL RENDER_STATUS_BAR
	CALL LOCATE_CURSOR
	JP MAIN_LOOP

;------------------------------------------------------------------------------
; SETUP_EDITOR_STATE: Ensure editor document buffers and viewport are valid
;
; Purpose:
;   Checks if an active document exists; if not, initializes a new empty
;   document. Constrains cursor within document bounds, clears splash screen
;   flag, and renders initial editor viewport.
;
; Call Usage / Protocol:
;   Called via CALL from ENTER_EDITOR, RESUME_EDITOR, DO_SPLASH_GOTO_LINE.
;
; Inputs:
;   IN_EDITOR_MODE, DOC_MODIFIED, DOC_TOTAL_LINES.
;
; Outputs:
;   IN_EDITOR_MODE set to 1; document initialized and viewport rendered.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
SETUP_EDITOR_STATE:
	LD A,(IN_EDITOR_MODE)
	OR A
	JR NZ,RESUME_EDITOR
	LD A,(DOC_MODIFIED)
	OR A
	JR NZ,RESUME_EDITOR
	LD HL,(DOC_TOTAL_LINES)
	LD A,H
	OR L
	JR NZ,RESUME_EDITOR

	LD A,1
	LD (IN_EDITOR_MODE),A
	CALL INIT_EMPTY_DOCUMENT
	LD HL,0
	LD (CUR_DOC_ROW),HL
	LD (TOP_DOC_ROW),HL
	LD (CUR_COL),HL
	LD (TARGET_COL),HL

;------------------------------------------------------------------------------
; RESUME_EDITOR: Return to active editor mode from modal/auxiliary screens
;
; Purpose:
;   Re-activates editor mode without re-initializing document content.
;   Clears splash flag, constrains cursor to active viewport, reinitializes
;   terminal display, and renders current editor view.
;
; Call Usage / Protocol:
;   Called via CALL or jumped to from modal dialog dismissals or pop-ups.
;
; Inputs:
;   None (uses current editor session state).
;
; Outputs:
;   IN_EDITOR_MODE = 1, IS_SPLASH_SCREEN = 0; screen repainted.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
RESUME_EDITOR:
	LD A,1
	LD (IN_EDITOR_MODE),A
	XOR A
	LD (IS_SPLASH_SCREEN),A
	CALL CONSTRAIN_CURSOR_VIEWPORT
	CALL TERM_INIT
	CALL RENDER_SCREEN
	RET

;------------------------------------------------------------------------------
; ENTER_EDITOR_WITH_ACTIVE_LINE: Force transition to editor after plugin mutate
;
; Purpose:
;   Resets stack pointer, checks out active line buffer, forces working
;   cache window reload, constrains viewport, and renders complete editor
;   screen and status bar following external plugin mutation.
;
; Call Usage / Protocol:
;   Jumped to from plugin execution return path when plugin modified text.
;
; Inputs:
;   CUR_LINE_IDX = active line number.
;
; Outputs:
;   Transitions into MAIN_LOOP; does not return.
;
; Preserves / Modifies:
;   Resets SP to LOCAL_STACK; clobbers all working registers.
;------------------------------------------------------------------------------
ENTER_EDITOR_WITH_ACTIVE_LINE:
	LD SP,LOCAL_STACK
	XOR A
	LD (PLUGIN_RET_CODE),A
	INC A
	LD (IN_EDITOR_MODE),A
	XOR A
	LD (IS_SPLASH_SCREEN),A
	CALL CHECKOUT_ACTIVE_LINE
	CALL RELOAD_CACHE_WINDOW_FORCE
	CALL CONSTRAIN_CURSOR_VIEWPORT
	CALL TERM_INIT
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	CALL LOCATE_CURSOR
	JP MAIN_LOOP

;------------------------------------------------------------------------------
; SHOW_SPLASH_SCREEN: Reset UI state and display splash screen
;
; Purpose:
;   Resets stack pointer to LOCAL_STACK, clears block selection and OOM
;   flags, renders full splash screen banner, and enters SPLASH_LOOP.
;
; Call Usage / Protocol:
;   Jumped to from START (when no file arg), or when returning from close,
;   modal dismissals, or auxiliary tools.
;
; Inputs:
;   None
;
; Outputs:
;   Transitions into SPLASH_LOOP; does not return.
;
; Preserves / Modifies:
;   Resets SP to LOCAL_STACK; clobbers all working registers.
;------------------------------------------------------------------------------
SHOW_SPLASH_SCREEN:
	LD SP,LOCAL_STACK
	XOR A
	LD (BLOCK_ACTIVE),A
	LD (STATUS_OOM_FLAG),A
SPLASH_START:
	CALL RENDER_SPLASH

;------------------------------------------------------------------------------
; SPLASH_LOOP: Interactive event loop for splash screen
;
; Purpose:
;   Polls console keyboard input and dispatches single-key commands:
;   'E'=Edit, 'N'=New, 'O'=Open, 'S'=Save, 'C'=Config, 'M'=Memory Info,
;   'A'=About, 'H'=Help, 'P'=Plugins, 'X'/'Q'=Exit.
;
; Call Usage / Protocol:
;   Entered directly following SHOW_SPLASH_SCREEN. Runs indefinitely until
;   user selects an action or exits.
;
; Inputs:
;   None
;
; Outputs:
;   Dispatches to corresponding command handler.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
SPLASH_LOOP:
	CALL GET_KEY

	; Standalone ESC or escape sequence (e.g. arrow keys) -> drain and
	; ignore
	CP KEY_ESC
	JR NZ,SPLASH_NOT_ESC
	CALL DRAIN_ESC_SEQUENCE
	JR SPLASH_LOOP
SPLASH_NOT_ESC:
	; Command: Ctrl+P -> Context-Aware Plugin Pop-up (Splash)
	CP KEY_CTRL_P
	JR NZ,SPLASH_NOT_CTRL_P
	LD A,PLUG_CTX_SPLASH
	CALL DO_CONTEXT_PLUGIN_POPUP
	LD A,(PLUGIN_RET_CODE)
	CP 2
	JP Z,ENTER_EDITOR_WITH_ACTIVE_LINE
	JP SPLASH_LOOP
SPLASH_NOT_CTRL_P:

	; Option: 'Q' or 'q' or Ctrl+Q -> Exit
	CP 'q'
	JP Z,HANDLE_SPLASH_EXIT
	CP 'Q'
	JP Z,HANDLE_SPLASH_EXIT
	CP KEY_CTRL_Q
	JP Z,HANDLE_SPLASH_EXIT

	; Option: 'N' or 'n' -> New File
	CP 'n'
	JP Z,HANDLE_SPLASH_NEW
	CP 'N'
	JP Z,HANDLE_SPLASH_NEW

	; Option: 'W' or 'w' or Ctrl+W -> Close File
	CP 'w'
	JP Z,HANDLE_SPLASH_CLOSE
	CP 'W'
	JP Z,HANDLE_SPLASH_CLOSE
	CP KEY_CTRL_W
	JP Z,HANDLE_SPLASH_CLOSE


	; Option: 'O' or 'o' or Ctrl+O -> Open File Screen
	CP 'o'
	JP Z,HANDLE_SPLASH_OPEN
	CP 'O'
	JP Z,HANDLE_SPLASH_OPEN
	CP KEY_CTRL_O
	JP Z,HANDLE_SPLASH_OPEN

	; Option: 'S' or 's' -> Save File Screen
	CP 's'
	JP Z,DO_SPLASH_SAVE
	CP 'S'
	JP Z,DO_SPLASH_SAVE

	; Option: 'L' or 'l' or Ctrl+L -> Goto Line Screen
	CP 'l'
	JP Z,DO_SPLASH_GOTO_LINE
	CP 'L'
	JP Z,DO_SPLASH_GOTO_LINE
	CP KEY_CTRL_L
	JP Z,DO_SPLASH_GOTO_LINE

	; Option: 'A' or 'a' -> Show About Screen
	CP 'a'
	JP Z,DO_ABOUT_SCREEN
	CP 'A'
	JP Z,DO_ABOUT_SCREEN

	; Option: 'M' or 'm' -> Show Memory Info Screen
	CP 'm'
	JP Z,DO_MEM_INFO_SCREEN
	CP 'M'
	JP Z,DO_MEM_INFO_SCREEN

	; Option: 'P' or 'p' -> Show Plugin Manager Screen
	CP 'p'
	JP Z,DO_SPLASH_PLUGIN_SCREEN
	CP 'P'
	JP Z,DO_SPLASH_PLUGIN_SCREEN

	; Option: 'C' or 'c' -> Show Configuration Screen
	CP 'c'
	JP Z,DO_CONFIG_SCREEN
	CP 'C'
	JP Z,DO_CONFIG_SCREEN

	; Option: '1' -> Modern Screen Mode (120x40)
	CP '1'
	JP Z,DO_SET_120X40

	; Option: '2' -> Classic Screen Mode (80x24)
	CP '2'
	JP Z,DO_SET_80X24

	; Option: 'E' or 'e' or Enter -> Enter/Resume Editor
	CP 'e'
	JP Z,ENTER_EDITOR
	CP 'E'
	JP Z,ENTER_EDITOR
	CP KEY_ENTER
	JP Z,ENTER_EDITOR

	JP SPLASH_LOOP

DO_SET_120X40:
	CALL SET_MODE_120X40
	JP SHOW_SPLASH_SCREEN

DO_SET_80X24:
	CALL SET_MODE_80X24
	JP SHOW_SPLASH_SCREEN


DO_ABOUT_SCREEN:
	CALL SHOW_ABOUT_SCREEN
ABT_LOOP:
	CALL GET_KEY
	CP KEY_CTRL_P
	JR NZ,ABT_NOT_CTRL_P
	LD A,PLUG_CTX_ABOUT
	CALL DO_CONTEXT_PLUGIN_POPUP
	JR ABT_LOOP
ABT_NOT_CTRL_P:
	CP KEY_ESC
	CALL Z,DRAIN_ESC_SEQUENCE
	JP SHOW_SPLASH_SCREEN

DO_MEM_INFO_SCREEN:
	CALL SHOW_MEM_INFO_SCREEN
MIS_LOOP:
	CALL GET_KEY
	CP KEY_CTRL_P
	JR NZ,MIS_NOT_CTRL_P
	LD A,PLUG_CTX_MEM_INFO
	CALL DO_CONTEXT_PLUGIN_POPUP
	JR MIS_LOOP
MIS_NOT_CTRL_P:
	CP KEY_ESC
	CALL Z,DRAIN_ESC_SEQUENCE
	JP SHOW_SPLASH_SCREEN

;------------------------------------------------------------------------------
; DO_CONFIG_SCREEN: Render configuration manager and enter event loop
;
; Purpose:
;   Displays configuration options screen and transitions into CONFIG_LOOP.
;
; Call Usage / Protocol:
;   Jumped to from SPLASH_LOOP when user selects 'C' (Config).
;
; Inputs:
;   None
;
; Outputs:
;   Transitions into CONFIG_LOOP; does not return directly.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_CONFIG_SCREEN:
	CALL SHOW_CONFIG_SCREEN

;------------------------------------------------------------------------------
; CONFIG_LOOP: Interactive event loop for configuration manager
;
; Purpose:
;   Processes user options in configuration screen:
;   '1'=Screen geometry (80x24 / 120x40), '2'=RAM drive mode,
;   '3'=Max lines (16K / 32K), '4'=Tab size (4 / 8), '5'=Plugin Manager mode,
;   'S'=Save config to SE.CFG, 'Q'/Enter/ESC=Return to splash.
;
; Call Usage / Protocol:
;   Entered from DO_CONFIG_SCREEN. Loops until user exits or toggles setting.
;
; Inputs:
;   None
;
; Outputs:
;   Updates configuration variables; returns to SHOW_SPLASH_SCREEN on exit.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
CONFIG_LOOP:
	CALL GET_KEY

	; Command: Ctrl+P -> Context-Aware Plugin Pop-up (Configuration)
	CP KEY_CTRL_P
	JR NZ,CONFIG_NOT_CTRL_P
	LD A,PLUG_CTX_CONFIG
	CALL DO_CONTEXT_PLUGIN_POPUP
	JR CONFIG_LOOP
CONFIG_NOT_CTRL_P:

	; Standalone ESC or escape sequence -> return to splash
	CP KEY_ESC
	JR NZ,CONFIG_NOT_ESC
	CALL DRAIN_ESC_SEQUENCE
	JP SHOW_SPLASH_SCREEN

CONFIG_NOT_ESC:
	; Option: '1' -> Toggle Screen Mode (80x24 <-> 120x40)
	CP '1'
	JR Z,CONFIG_TOGGLE_MODE

	; Option: '2' -> Toggle RAM Drive Memory Blocks
	CP '2'
	JR Z,CONFIG_TOGGLE_RAMDRIVE

	; Option: '3' -> Toggle Max Lines (16K <-> 32K)
	CP '3'
	JP Z,CONFIG_TOGGLE_LINES

	; Option: '4' -> Toggle Tab Width (4 <-> 8)
	CP '4'
	JR Z,CONFIG_TOGGLE_TAB

	; Option: '5' -> Toggle Plugin Manager (Auto <-> Disabled)
	CP '5'
	JP Z,CONFIG_TOGGLE_PLUGIN

	; Option: 'S' or 's' -> Save Configuration to local SE.CFG
	CP 's'
	JP Z,CONFIG_DO_SAVE
	CP 'S'
	JP Z,CONFIG_DO_SAVE

	; Option: 'Q' or 'q' or Enter -> Return to Splash Screen
	CP 'q'
	JP Z,SHOW_SPLASH_SCREEN
	CP 'Q'
	JP Z,SHOW_SPLASH_SCREEN
	CP KEY_ENTER
	JP Z,SHOW_SPLASH_SCREEN

	JR CONFIG_LOOP

CONFIG_TOGGLE_MODE:
	LD A,(SCREEN_MODE)
	CP MODE_120X40
	JR Z,CONFIG_SET_80
	CALL SET_MODE_120X40
	JR CONFIG_REDRAW
CONFIG_SET_80:
	CALL SET_MODE_80X24
CONFIG_REDRAW:
	CALL SHOW_CONFIG_SCREEN
	JR CONFIG_LOOP

CONFIG_TOGGLE_RAMDRIVE:
	LD A,(CFG_RAMDRIVE_FLAG)
	CP RAMDRV_MODE_PROTECTED
	JR Z,CTR_SET_HIB
	CP RAMDRV_MODE_HIBERNATE
	JR Z,CTR_SET_ENA
	; Currently ENABLED (1) -> switch to PROTECTED (0)
	XOR A
	LD (CFG_RAMDRIVE_FLAG),A
	JR CTR_APPLY
CTR_SET_HIB:
	LD A,RAMDRV_MODE_HIBERNATE
	LD (CFG_RAMDRIVE_FLAG),A
	JR CTR_APPLY
CTR_SET_ENA:
	; Before enabling raw overwrite, ensure active drive is not the RAM
	; drive
	LD A,(RAMDRIVE_DRIVE_NUM)
	CP 0FFH
	JR Z,CTR_DO_ENA
	LD B,A
	LD A,(CURRENT_DEFAULT_DRIVE)
	CP B
	; Active drive is RAM drive: skip Enabled, wrap to Protected!
	JR Z,CTR_SET_PROT
CTR_DO_ENA:
	LD A,RAMDRV_MODE_ENABLED
	LD (CFG_RAMDRIVE_FLAG),A
	JR CTR_APPLY

CTR_SET_PROT:
	XOR A
	LD (CFG_RAMDRIVE_FLAG),A
	JR CTR_APPLY
CTR_APPLY:
	CALL BUFFER_INIT
	CALL SHOW_CONFIG_SCREEN
	JP CONFIG_LOOP

CONFIG_TOGGLE_TAB:
	LD A,(CFG_TAB_WIDTH)
	CP 4
	JR Z,CTT_SET_8
	LD A,4
	LD (CFG_TAB_WIDTH),A
	LD A,3
	LD (CFG_TAB_MASK),A
	JR CTT_DONE
CTT_SET_8:
	LD A,8
	LD (CFG_TAB_WIDTH),A
	LD A,7
	LD (CFG_TAB_MASK),A
CTT_DONE:
	CALL SHOW_CONFIG_SCREEN
	JP CONFIG_LOOP

CONFIG_TOGGLE_LINES:
	LD A,(CFG_LINES_MODE)
	XOR 1				; Toggle 0 <-> 1
	LD (CFG_LINES_MODE),A
	CALL BUFFER_INIT		; Reallocate Far RAM banks
	CALL SHOW_CONFIG_SCREEN
	JP CONFIG_LOOP

CONFIG_TOGGLE_PLUGIN:
	; If currently loaded, Far RAM is already verified
	LD A,(PLUGIN_MGR_LOADED)
	OR A
	JR NZ,CTP_FAR_OK

	; Not loaded: check Far RAM availability (>= 2 banks)
	LD A,(EXT_BANK_COUNT)
	CP 2
	JR NC,CTP_FAR_OK

	; Insufficient Far RAM: Autoload / On Demand not selectable.
	; User requested: No beeps. Silently keep disabled and ignore.
	XOR A
	LD (CFG_AUTOLOAD_PLUGIN_MGR),A
	JP CONFIG_LOOP

CTP_FAR_OK:
	; Cycle: AUTOLOAD (1) -> ONDEMAND (2) -> DISABLED (0) -> AUTOLOAD (1)
	LD A,(CFG_AUTOLOAD_PLUGIN_MGR)
	CP PLUGIN_MODE_AUTOLOAD
	JR Z,CTP_TO_ONDEMAND
	CP PLUGIN_MODE_ONDEMAND
	JR Z,CTP_TO_DISABLED

	; From DISABLED (0) -> AUTOLOAD (1)
	LD A,PLUGIN_MODE_AUTOLOAD
	LD (CFG_AUTOLOAD_PLUGIN_MGR),A
	CALL ENSURE_PLUGIN_MGR_LOADED
	JR CTP_DONE

CTP_TO_ONDEMAND:
	; From AUTOLOAD (1) -> ONDEMAND (2)
	LD A,PLUGIN_MODE_ONDEMAND
	LD (CFG_AUTOLOAD_PLUGIN_MGR),A
	CALL CTP_UNLOAD_IF_LOADED
	JR CTP_DONE

CTP_TO_DISABLED:
	; From ONDEMAND (2) -> DISABLED (0)
	XOR A
	LD (CFG_AUTOLOAD_PLUGIN_MGR),A
	CALL CTP_UNLOAD_IF_LOADED
	JR CTP_DONE

;------------------------------------------------------------------------------
; CTP_UNLOAD_IF_LOADED: Unload Plugin Manager if currently resident in RAM
;
; Purpose:
;   Checks if the Plugin Manager overlay is currently resident in Far RAM.
;   If resident, releases its allocated Far RAM bank and clears loaded flags.
;
; Call Usage / Protocol:
;   Called via CALL from CONFIG_LOOP when disabling Plugin Manager.
;
; Inputs:
;   PLUGIN_MGR_LOADED flag, PLUGIN_MGR_BANK ID.
;
; Outputs:
;   PLUGIN_MGR_LOADED set to 0, bank released.
;
; Preserves / Modifies:
;   Clobbers AF. Preserves BC, DE, HL.
;------------------------------------------------------------------------------
CTP_UNLOAD_IF_LOADED:
	LD A,(PLUGIN_MGR_LOADED)
	OR A
	RET Z
	LD A,(PLUGIN_MGR_BANK)
	CALL RELEASE_FAR_BANK
	XOR A
	LD (PLUGIN_MGR_LOADED),A
	LD (PLUGIN_MGR_BANK),A
	RET

CTP_DONE:
	CALL SHOW_CONFIG_SCREEN
	JP CONFIG_LOOP

CONFIG_DO_SAVE:
	CALL SAVE_CONFIG
	CALL SHOW_CONFIG_SCREEN
	JP CONFIG_LOOP

;------------------------------------------------------------------------------
; DO_SPLASH_SAVE: Handle Save File command from splash screen
;
; Purpose:
;   Invokes Save File modal UI from splash screen, then returns to splash.
;
; Call Usage / Protocol:
;   Jumped to from SPLASH_LOOP on 'S' key.
;
; Inputs:
;   None
;
; Outputs:
;   Returns to SHOW_SPLASH_SCREEN.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_SPLASH_SAVE:
	CALL DO_SAVE_FILE_UI
	JP SHOW_SPLASH_SCREEN

;------------------------------------------------------------------------------
; DO_SPLASH_PLUGIN_SCREEN: Handle Plugin screen command from splash screen
;
; Purpose:
;   Invokes plugin manager / plugin selection UI from splash screen,
;   then returns to splash screen.
;
; Call Usage / Protocol:
;   Jumped to from SPLASH_LOOP on 'P' key.
;
; Inputs:
;   None
;
; Outputs:
;   Returns to SHOW_SPLASH_SCREEN.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_SPLASH_PLUGIN_SCREEN:
	CALL DO_PLUGIN_SCREEN
	JP SHOW_SPLASH_SCREEN

;------------------------------------------------------------------------------
; DO_SPLASH_GOTO_LINE: Handle Goto Line command from splash screen
;
; Purpose:
;   Switches from splash screen into editor mode, prompts user for target
;   line number via modal pop-up, navigates to target line, and enters
;   MAIN_LOOP.
;
; Call Usage / Protocol:
;   Jumped to from SPLASH_LOOP on 'G' key.
;
; Inputs:
;   None
;
; Outputs:
;   Transitions into MAIN_LOOP.
;
; Preserves / Modifies:
;   Resets SP to LOCAL_STACK; clobbers all working registers.
;------------------------------------------------------------------------------
DO_SPLASH_GOTO_LINE:
	LD SP,LOCAL_STACK
	CALL SETUP_EDITOR_STATE
	CALL RENDER_STATUS_BAR
	CALL DO_GOTO_LINE_UI
	JP MAIN_LOOP

;------------------------------------------------------------------------------
; MAIN_LOOP: Central interactive editor event loop
;
; Purpose:
;   Core editor processing loop. Checks serial buffer for pending keystrokes;
;   flushes deferred screen rendering when idle; reads keystrokes and
;   dispatches typing, cursor movements, paging, editing actions, block
;   marking, search/replace, and modal pop-ups.
;
; Call Usage / Protocol:
;   Jumped to after editor initialization or returning from command execution.
;   Runs continuously until exit or mode switch.
;
; Inputs:
;   Current editor state (CUR_ROW, CUR_COL, TOP_DOC_ROW, etc.).
;
; Outputs:
;   None (loops indefinitely).
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
MAIN_LOOP:
	; If no key is immediately ready in serial buffer, flush deferred
	; render!
	CALL CHECK_KEY_READY
	JR NZ,MAIN_LOOP_GET_KEY

	CALL FLUSH_DEFERRED_RENDER

MAIN_LOOP_GET_KEY:
	CALL GET_KEY

	; If OOM flag was set during operation, clear upon any keypress
	LD B,A
	LD A,(STATUS_OOM_FLAG)
	OR A
	JR Z,ML_NO_OOM_CLEAR
	XOR A
	LD (STATUS_OOM_FLAG),A
ML_NO_OOM_CLEAR:
	LD A,B

	; Command: Ctrl+Q -> Exit
	CP KEY_CTRL_Q
	JP Z,HANDLE_CTRL_Q

	; Command: Ctrl+W -> Close File to Splash
	CP KEY_CTRL_W
	JP Z,HANDLE_CTRL_W

	; Command: Ctrl+F -> Find
	CP KEY_CTRL_F
	JR NZ,CHECK_CTRL_R
	CALL FLUSH_DEFERRED_RENDER
	CALL DO_FIND_UI
	JP MAIN_LOOP

CHECK_CTRL_R:
	; Command: Ctrl+R -> Search & Replace
	CP KEY_CTRL_R
	JR NZ,CHECK_CTRL_N
	CALL FLUSH_DEFERRED_RENDER
	CALL DO_REPLACE_UI
	JP MAIN_LOOP

CHECK_CTRL_N:
	; Command: Ctrl+N -> Find Next
	CP KEY_CTRL_N
	JR NZ,CHECK_CTRL_P
	CALL FLUSH_DEFERRED_RENDER
	CALL DO_FIND_NEXT
	JP MAIN_LOOP

CHECK_CTRL_P:
	; Command: Ctrl+P -> Context-Aware Plugin Pop-up (Editor)
	CP KEY_CTRL_P
	JR NZ,CHECK_CTRL_S
	CALL FLUSH_DEFERRED_RENDER
	LD A,PLUG_CTX_EDITOR
	CALL DO_CONTEXT_PLUGIN_POPUP
	JP MAIN_LOOP

CHECK_CTRL_S:
	; Command: Ctrl+S -> Save File Screen or Block Save File
	CP KEY_CTRL_S
	JR NZ,CHECK_CTRL_O
	CALL FLUSH_DEFERRED_RENDER
	LD A,(BLOCK_ACTIVE)
	OR A
	JP NZ,DO_BLOCK_SAVE_FILE
	CALL DO_SAVE_FILE_UI
	CALL TERM_INIT
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	XOR A
	LD (NEED_SCREEN_RENDER),A
	LD (NEED_LINE_RENDER),A
	LD (NEED_STATUS_RENDER),A
	JP MAIN_LOOP

CHECK_CTRL_O:
	; Command: Ctrl+O -> Open File Screen or Block Insert File
	CP KEY_CTRL_O
	JR NZ,CHECK_CTRL_C
	CALL FLUSH_DEFERRED_RENDER
	LD A,(BLOCK_ACTIVE)
	OR A
	JP NZ,DO_BLOCK_INSERT_FILE
	JP HANDLE_CTRL_O

CHECK_CTRL_C:
	; Command: Ctrl+C -> Copy block (solidifies dynamic block first if
	; active)
	CP KEY_CTRL_C
	JR NZ,CHECK_CTRL_K
	LD A,(BLOCK_ACTIVE)
	CP 2
	JR Z,DO_CTRL_C_COPY
	CP 1
	JR Z,DO_CTRL_C_IMPLIED_SOLIDIFY_COPY
	JP MAIN_LOOP			; Ignore if block not active

DO_CTRL_C_IMPLIED_SOLIDIFY_COPY:
	CALL SOLIDIFY_BLOCK
DO_CTRL_C_COPY:
	CALL DO_COPY_BLOCK
	JP MAIN_LOOP

CHECK_CTRL_K:
	CP KEY_CTRL_K
	JR NZ,CHECK_CTRL_D

	LD A,(BLOCK_ACTIVE)
	OR A
	JP NZ,DO_BLOCK_MENU_POPUP	; Block active: show block modal!
	JP DO_HELP_SCREEN		; Inactive: show help screen!

;------------------------------------------------------------------------------
; DO_HELP_SCREEN: Display editor help and keybindings screen
;
; Purpose:
;   Flushes deferred rendering and dirty cache lines, loads HELP.OVL overlay
;   into transient execution memory, and runs the help viewer. Restores
;   editor state and cache window upon dismissal.
;
; Call Usage / Protocol:
;   Jumped to from MAIN_LOOP on Ctrl+K (when no block is active).
;
; Inputs:
;   None
;
; Outputs:
;   Returns to MAIN_LOOP.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_HELP_SCREEN:
	CALL FLUSH_DEFERRED_RENDER
	CALL INVALIDATE_ACTIVE_LINE
	CALL FLUSH_DIRTY_CACHE
	LD HL,0FFFFH
	LD (CACHE_START_ROW),HL

	LD A,1
	LD (IS_SPLASH_SCREEN),A		; Prevent cursor / dirty updates

DHS_RETRY:
	CALL LOAD_HELP_OVERLAY
	JR NC,DHS_RUN

	; Help overlay missing or failed to load -> display status modal
	XOR A
	LD (IS_SPLASH_SCREEN),A
	CALL RELOAD_CACHE_WINDOW_FORCE
	CALL SHOW_POPUP_HELP_MISSING
	XOR A
	LD (NEED_SCREEN_RENDER),A
	LD (NEED_LINE_RENDER),A
	LD (NEED_STATUS_RENDER),A
	JP MAIN_LOOP

DHS_RUN:
	LD IX,PLUGIN_HOST_API
	LD IY,PLUGIN_HOST_API
	CALL LINE_STORAGE + 256		; Entry point of HELP.OVL

	; If HELP.OVL returned A == KEY_CTRL_P, run context popup and re-run
	CP KEY_CTRL_P
	JR NZ,DHS_RESTORE
	LD A,PLUG_CTX_HELP
	CALL DO_CONTEXT_PLUGIN_POPUP
	JR DHS_RETRY

DHS_RESTORE:
	XOR A
	LD (IS_SPLASH_SCREEN),A

DHS_EXIT:
	CALL RELOAD_CACHE_WINDOW_FORCE
	CALL TERM_INIT
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	XOR A
	LD (NEED_SCREEN_RENDER),A
	LD (NEED_LINE_RENDER),A
	LD (NEED_STATUS_RENDER),A
	JP MAIN_LOOP

CHECK_CTRL_D:
	; Command: Ctrl+D -> Delete character under cursor (Forward Delete)
	CP 4
	JR NZ,CHECK_CTRL_X
	LD A,(BLOCK_ACTIVE)
	CP 2
	JR Z,DO_CTRL_D_BLOCK
	CP 1
	JR Z,DO_CTRL_D_IMPLIED_K_DELETE
	CALL DO_DELETE_FORWARD
	JP MAIN_LOOP

DO_CTRL_D_IMPLIED_K_DELETE:
	CALL SOLIDIFY_BLOCK
DO_CTRL_D_BLOCK:
	CALL DO_DELETE_BLOCK
	JP MAIN_LOOP

CHECK_CTRL_X:
	; Command: Ctrl+X -> Move solidified block / solidify dynamic block
	CP KEY_CTRL_X
	JR NZ,CHECK_CTRL_Y
	LD A,(BLOCK_ACTIVE)
	CP 2
	JR Z,DO_CTRL_X_MOVE
	CP 1
	JR Z,DO_CTRL_X_SOLIDIFY
	JP MAIN_LOOP			; Ignore if block not active

DO_CTRL_X_SOLIDIFY:
	CALL SOLIDIFY_BLOCK
	JP MAIN_LOOP

DO_CTRL_X_MOVE:
	CALL DO_MOVE_BLOCK
	JP MAIN_LOOP

CHECK_CTRL_Y:
	; Command: Ctrl+Y -> Beautify Block (if active) or Whole File (if no
	; block)
	CP KEY_CTRL_Y
	JR NZ,CHECK_CTRL_Z
	CALL FLUSH_DEFERRED_RENDER
	JP DO_CTRL_Y_BEAUTIFY

CHECK_CTRL_Z:
	; Command: Ctrl+Z -> Open Plugin Manager Screen
	CP KEY_CTRL_Z
	JR NZ,CHECK_PAGE_KEYS
	CALL FLUSH_DEFERRED_RENDER
	JP DO_EDITOR_PLUGIN_SCREEN

CHECK_PAGE_KEYS:
	; Command: Ctrl+L -> Goto line number
	CP KEY_CTRL_L
	JR NZ,CHECK_NAV_KEYS
	CALL FLUSH_DEFERRED_RENDER
	CALL DO_GOTO_LINE_UI
	JP MAIN_LOOP

CHECK_NAV_KEYS:
	; Command: Ctrl+A -> Home (start of line)
	CP 1				; Ctrl+A
	JR Z,DO_HOME_KEY

	; Command: Ctrl+E -> End (end of line)
	CP 5				; Ctrl+E
	JR Z,DO_END_KEY

	; Command: Ctrl+T -> Jump to Top of File
	CP 20				; Ctrl+T
	JR Z,DO_JUMP_TOP

	; Command: Ctrl+G -> Jump to Bottom of File
	CP 7				; Ctrl+G
	JR Z,DO_JUMP_BOTTOM

	; Command: Ctrl+B -> Toggle Block Highlighting
	CP KEY_CTRL_B			; Ctrl+B
	JR Z,DO_TOGGLE_BLOCK

	; Command: Ctrl+U -> Page Up
	CP KEY_CTRL_U			; Ctrl+U
	JR Z,DO_PAGE_UP

	; Command: Ctrl+V -> Page Down
	CP 22				; Ctrl+V
	JR Z,DO_PAGE_DOWN

	JR CHECK_ENTER

DO_HOME_KEY:
	CALL CURSOR_HOME
	LD A,1
	LD (NEED_STATUS_RENDER),A
	JP MAIN_LOOP

DO_END_KEY:
	CALL CURSOR_END
	LD A,1
	LD (NEED_STATUS_RENDER),A
	JP MAIN_LOOP

DO_JUMP_TOP:
	CALL JUMP_FILE_TOP
	JP MAIN_LOOP

DO_JUMP_BOTTOM:
	CALL JUMP_FILE_BOTTOM
	JP MAIN_LOOP

DO_TOGGLE_BLOCK:
	CALL TOGGLE_BLOCK_MODE
	JP MAIN_LOOP

DO_PAGE_UP:
	CALL PAGE_UP
	JP MAIN_LOOP

DO_PAGE_DOWN:
	CALL PAGE_DOWN
	JP MAIN_LOOP

CHECK_ENTER:
	; Enter -> Solidify selection if dynamic, else insert new line
	CP KEY_ENTER
	JR NZ,CHECK_BACKSPACE
	LD A,(BLOCK_ACTIVE)
	CP 1
	JR Z,DO_ENTER_SOLIDIFY_SETUP
	CALL CANCEL_BLOCK
	CALL DO_INSERT_LINE
	JR C,ENTER_INS_DONE
	LD A,1
	LD (NEED_SCREEN_RENDER),A
ENTER_INS_DONE:
	JP MAIN_LOOP

DO_ENTER_SOLIDIFY_SETUP:
	CALL SOLIDIFY_BLOCK
	JP MAIN_LOOP

CHECK_BACKSPACE:
	CP KEY_BACKSPACE
	JR Z,DO_HANDLE_BS
	CP KEY_DEL
	JR NZ,CHECK_ESC_SEQ
	LD A,(BLOCK_ACTIVE)
	CP 2
	JP Z,DO_CTRL_D_BLOCK
	CP 1
	JP Z,DO_CTRL_D_IMPLIED_K_DELETE
	CALL DO_DELETE_FORWARD
	JP MAIN_LOOP

DO_HANDLE_BS:
	LD A,(BLOCK_ACTIVE)
	CP 1
	JR Z,DO_BS_CANCEL_SETUP
	CALL CANCEL_BLOCK

	LD A,(CUR_COL)
	OR A
	JR Z,DO_HANDLE_BS_COL0

	; Normal character deletion on current line (CUR_COL > 0)
	CALL DO_DELETE_CHAR
	LD A,1
	LD (NEED_LINE_RENDER),A
	JP MAIN_LOOP

DO_BS_CANCEL_SETUP:
	CALL CANCEL_BLOCK
	JP MAIN_LOOP

DO_HANDLE_BS_COL0:
	; Backspace at column 0: delete line if blank / join lines
	CALL DO_DELETE_BLANK_LINE
	JP MAIN_LOOP

CHECK_ESC_SEQ:
	; Check for VT100 Escape sequences (Arrow keys)
	CP KEY_ESC
	JR NZ,CHECK_PRINTABLE_CHAR
	CALL HANDLE_VT100_ESC
	LD A,1
	LD (NEED_STATUS_RENDER),A
	JP MAIN_LOOP

CHECK_PRINTABLE_CHAR:
	; Check if Tab key is pressed (expand to 8-character tab stops)
	CP KEY_TAB			; 9
	JR NZ,CHECK_PRINTABLE_REGULAR
	LD A,(BLOCK_ACTIVE)
	CP 1
	JR Z,DO_TAB_CANCEL_SETUP
	CALL CANCEL_BLOCK
	CALL DO_TAB_INSERT
	LD A,1
	LD (NEED_LINE_RENDER),A
	JP MAIN_LOOP

DO_TAB_CANCEL_SETUP:
	CALL CANCEL_BLOCK
	JP MAIN_LOOP

CHECK_PRINTABLE_REGULAR:
	CP ' '
	JP C,MAIN_LOOP
	CP 127
	JP NC,MAIN_LOOP

DO_INSERT_CHAR:
	LD B,A
	LD A,(BLOCK_ACTIVE)
	CP 1
	JR Z,DO_CHAR_CANCEL_SETUP
	CALL CANCEL_BLOCK
	LD A,B
	CALL DO_CHAR_INSERT
	LD A,1
	LD (NEED_LINE_RENDER),A
	JP MAIN_LOOP

DO_CHAR_CANCEL_SETUP:
	CALL CANCEL_BLOCK
	JP MAIN_LOOP

;------------------------------------------------------------------------------
; DO_TAB_INSERT: Insert ASCII Tab character at cursor position
;
; Purpose:
;   Inserts literal ASCII 0x09 TAB byte into active line buffer at current
;   cursor column and advances cursor accordingly.
;
; Call Usage / Protocol:
;   Called via CALL from MAIN_LOOP when user presses Tab key (0x09).
;
; Inputs:
;   ACTIVE_LINE_BUF, CUR_COL.
;
; Outputs:
;   Active line buffer updated; DIRTY_ACTIVE_LINE set; cursor updated.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
DO_TAB_INSERT:
	LD A,KEY_TAB			; Insert literal ASCII 0x09 Tab byte
	CALL DO_CHAR_INSERT
	RET

;------------------------------------------------------------------------------
; Exit, Close & New Document Handling with Unsaved Changes Protection
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; HANDLE_SPLASH_EXIT: Process exit request from splash screen
;
; Purpose:
;   Checks if active document has unsaved modifications. If clean, exits
;   immediately to CP/M. If modified, switches to editor and displays
;   save confirmation modal dialog.
;
; Call Usage / Protocol:
;   Jumped to from SPLASH_LOOP on 'X' or 'Q'.
;
; Inputs:
;   DOC_MODIFIED flag.
;
; Outputs:
;   Exits program or prompts user.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HANDLE_SPLASH_EXIT:
	LD A,ACTION_EXIT
	LD (CONFIRM_ACTION),A
	LD A,(DOC_MODIFIED)
	OR A
	JP Z,EXIT_PROGRAM

	; Document modified: switch to editor view and show exit prompt
	LD A,1
	LD (IN_EDITOR_MODE),A
	CALL RESUME_EDITOR
	JP SHOW_EXIT_PROMPT

;------------------------------------------------------------------------------
; HANDLE_CTRL_Q: Process exit request from editor mode (Ctrl+Q)
;
; Purpose:
;   Checks if active document has unsaved modifications. If clean, exits
;   immediately to CP/M. If modified, displays save confirmation pop-up.
;
; Call Usage / Protocol:
;   Jumped to from MAIN_LOOP on Ctrl+Q.
;
; Inputs:
;   DOC_MODIFIED flag.
;
; Outputs:
;   Exits program or displays prompt.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HANDLE_CTRL_Q:
	LD A,ACTION_EXIT
	LD (CONFIRM_ACTION),A
	LD A,(DOC_MODIFIED)
	OR A
	JP Z,EXIT_PROGRAM
	JP SHOW_EXIT_PROMPT

;------------------------------------------------------------------------------
; HANDLE_CTRL_W: Process close document request from editor mode (Ctrl+W)
;
; Purpose:
;   Checks if active document has unsaved modifications. If clean, closes
;   document and returns to splash. If modified, prompts user to save.
;
; Call Usage / Protocol:
;   Jumped to from MAIN_LOOP on Ctrl+W.
;
; Inputs:
;   DOC_MODIFIED flag.
;
; Outputs:
;   Closes document or prompts user.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HANDLE_CTRL_W:
	LD A,ACTION_CLOSE
	LD (CONFIRM_ACTION),A
	LD A,(DOC_MODIFIED)
	OR A
	JP Z,DO_EXEC_CLOSE
	JP SHOW_EXIT_PROMPT

;------------------------------------------------------------------------------
; HANDLE_SPLASH_CLOSE: Process close document request from splash screen ('W')
;
; Purpose:
;   If editor session is active, checks for unsaved modifications and closes
;   document (prompting user if modified). If no session active, ignores.
;
; Call Usage / Protocol:
;   Jumped to from SPLASH_LOOP on 'W'.
;
; Inputs:
;   IN_EDITOR_MODE, DOC_MODIFIED flags.
;
; Outputs:
;   Closes document or returns to splash loop.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HANDLE_SPLASH_CLOSE:
	; If no editor session is active, ignore close
	LD A,(IN_EDITOR_MODE)
	OR A
	JR Z,SPLASH_CLOSE_NOP
	LD A,ACTION_CLOSE
	LD (CONFIRM_ACTION),A
	LD A,(DOC_MODIFIED)
	OR A
	JP Z,DO_EXEC_CLOSE
	CALL RESUME_EDITOR
	JP SHOW_EXIT_PROMPT
SPLASH_CLOSE_NOP:
	JP SPLASH_LOOP

;------------------------------------------------------------------------------
; HANDLE_SPLASH_NEW: Process new document request from splash screen ('N')
;
; Purpose:
;   Checks if existing document has unsaved modifications (prompting if needed),
;   then initializes an empty document and switches to editor.
;
; Call Usage / Protocol:
;   Jumped to from SPLASH_LOOP on 'N'.
;
; Inputs:
;   DOC_MODIFIED flag.
;
; Outputs:
;   Initializes new document and enters editor.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HANDLE_SPLASH_NEW:
	LD A,ACTION_NEW
	LD (CONFIRM_ACTION),A
	LD A,(DOC_MODIFIED)
	OR A
	JP Z,DO_EXEC_NEW
	CALL RESUME_EDITOR
	JP SHOW_EXIT_PROMPT

;------------------------------------------------------------------------------
; HANDLE_CTRL_O: Process open file request from editor mode (Ctrl+O)
;
; Purpose:
;   Checks if active document has unsaved modifications. If clean, opens
;   file dialog. If modified, prompts user to save before proceeding.
;
; Call Usage / Protocol:
;   Jumped to from MAIN_LOOP on Ctrl+O.
;
; Inputs:
;   DOC_MODIFIED flag.
;
; Outputs:
;   Opens file dialog or prompts user.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HANDLE_CTRL_O:
	LD A,ACTION_OPEN
	LD (CONFIRM_ACTION),A
	LD A,(DOC_MODIFIED)
	OR A
	JP Z,DO_EXEC_OPEN
	JP SHOW_EXIT_PROMPT

;------------------------------------------------------------------------------
; DO_BLOCK_SAVE_FILE: Save highlighted visual block to disk file
;
; Purpose:
;   Flushes active line and cache, solidifies dynamic block selection,
;   normalizes block boundaries, displays save file modal UI, and writes
;   block text to selected file.
;
; Call Usage / Protocol:
;   Called via CALL from block pop-up menu or shortcut (Ctrl+K S).
;
; Inputs:
;   BLOCK_ACTIVE, BLOCK_START_ROW, BLOCK_START_COL, BLOCK_END_ROW,
;   BLOCK_END_COL.
;
; Outputs:
;   Block written to disk; redraws editor viewport and status bar.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_BLOCK_SAVE_FILE:
	CALL INVALIDATE_ACTIVE_LINE
	CALL FLUSH_DIRTY_CACHE
	; Implied Ctrl-K: solidify dynamic block selection if state 1
	LD A,(BLOCK_ACTIVE)
	CP 1
	CALL Z,SOLIDIFY_BLOCK
	CALL NORMALIZE_BLOCK_BOUNDS
	LD A,1
	LD (IS_BLOCK_SAVE_UI),A
	CALL DO_SAVE_FILE_UI
	; Clean up UI flags (save completed or user pressed ESC)
	XOR A
	LD (IS_BLOCK_SAVE_UI),A
	LD (IS_SAVE_UI),A
	LD (IS_SPLASH_SCREEN),A
	; Note: BLOCK_ACTIVE is intentionally retained at 2 (solidified)
	; so the user can subsequently press Del (or Ctrl+D) to delete the
	; block.
	CALL TERM_INIT
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	XOR A
	LD (NEED_SCREEN_RENDER),A
	LD (NEED_LINE_RENDER),A
	LD (NEED_STATUS_RENDER),A
	JP MAIN_LOOP

;------------------------------------------------------------------------------
; DO_BLOCK_INSERT_FILE: Insert disk file contents into document at cursor
;
; Purpose:
;   Solidifies and normalizes any active block, displays open file dialog
;   in insert mode, and inserts disk file lines at cursor position.
;
; Call Usage / Protocol:
;   Jumped to or called from block menu or shortcut (Ctrl+K R).
;
; Inputs:
;   Current cursor position (CUR_DOC_ROW, CUR_COL).
;
; Outputs:
;   File contents inserted into document; redraws editor screen.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_BLOCK_INSERT_FILE:
	; Implied Ctrl-K: solidify dynamic block selection if state 1
	LD A,(BLOCK_ACTIVE)
	CP 1
	CALL Z,SOLIDIFY_BLOCK
	CALL NORMALIZE_BLOCK_BOUNDS
	LD A,1
	LD (IS_BLOCK_INSERT_UI),A
	CALL DO_OPEN_FILE_UI
	; User pressed ESC in DO_OPEN_FILE_UI -> cancel back to editor
	XOR A
	LD (IS_BLOCK_INSERT_UI),A
	LD (IS_SPLASH_SCREEN),A
	CALL TERM_INIT
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	JP MAIN_LOOP

;------------------------------------------------------------------------------
; HANDLE_SPLASH_OPEN: Process open file request from splash screen ('O')
;
; Purpose:
;   Checks if active document has unsaved modifications. If clean, opens
;   file dialog directly. If modified, resumes editor and prompts user.
;
; Call Usage / Protocol:
;   Jumped to from SPLASH_LOOP on 'O'.
;
; Inputs:
;   DOC_MODIFIED flag.
;
; Outputs:
;   Opens file dialog or prompts user.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HANDLE_SPLASH_OPEN:
	LD A,ACTION_OPEN
	LD (CONFIRM_ACTION),A
	LD A,(DOC_MODIFIED)
	OR A
	JR Z,DO_SPLASH_OPEN_DIRECT
	CALL RESUME_EDITOR
	JR SHOW_EXIT_PROMPT

;------------------------------------------------------------------------------
; DO_SPLASH_OPEN_DIRECT: Invoke open file dialog directly from splash screen
;
; Purpose:
;   Displays Open File modal dialog and returns to splash screen when done.
;
; Call Usage / Protocol:
;   Jumped to from HANDLE_SPLASH_OPEN when document is not modified.
;
; Inputs:
;   None
;
; Outputs:
;   Returns to SHOW_SPLASH_SCREEN.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_SPLASH_OPEN_DIRECT:
	CALL DO_OPEN_FILE_UI
	JP SHOW_SPLASH_SCREEN

;------------------------------------------------------------------------------
; SHOW_EXIT_PROMPT: Display unsaved modifications confirmation pop-up
;
; Purpose:
;   Renders modal dialog asking user whether to save changes before exit,
;   close, or new document action. Dispatches based on response ('Y', 'N', ESC).
;
; Call Usage / Protocol:
;   Jumped to from exit/close/open handlers when DOC_MODIFIED is non-zero.
;
; Inputs:
;   CONFIRM_ACTION indicates pending operation (ACTION_EXIT/CLOSE/NEW/OPEN).
;
; Outputs:
;   Executes confirmed action, saves file, or cancels back to editor.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SHOW_EXIT_PROMPT:
	CALL DO_SAVE_CHANGES_POPUP
	JP C,EXIT_CANCEL
	CP 'y'
	JP Z,EXIT_SAVE_AND_QUIT
	CP 'Y'
	JP Z,EXIT_SAVE_AND_QUIT
	JP EXEC_CONFIRM_ACTION

;------------------------------------------------------------------------------
; DO_SAVE_CHANGES_POPUP: Centered modal dialog querying user to save changes
;
; Purpose:
;   Displays 50x7 centered modal pop-up box with message:
;     "Save modified document before proceeding?"
;     "[Y]es      [N]o      [ESC]=Cancel"
;   Waits for valid keystroke and drains multi-byte escape sequences.
;
; Call Usage / Protocol:
;   Called via CALL from SHOW_EXIT_PROMPT.
;
; Inputs:
;   ACTIVE_COLS, ACTIVE_ROWS (for dialog centering).
;
; Outputs:
;   Carry = 0, A = 'Y': User confirmed save.
;   Carry = 0, A = 'N': User chose discard / proceed without saving.
;   Carry = 1: User cancelled (ESC).
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
DO_SAVE_CHANGES_POPUP:
	CALL TERM_HIDE_CURSOR

	; 1. Calculate POPUP_COL = ((ACTIVE_COLS - 50) / 2) + 1
	LD A,(ACTIVE_COLS)
	SUB 50
	SRL A
	INC A
	LD (POPUP_COL),A

	; 2. Calculate POPUP_ROW = ((ACTIVE_ROWS - 7) / 2) + 1
	LD A,(ACTIVE_ROWS)
	SUB 7
	SRL A
	INC A
	LD (POPUP_ROW),A
	LD (POPUP_SAVE_START_ROW),A

	; 3. Render 7-line Pop-Up Box
	CALL POPUP_PRINT_BORDER

	CALL POPUP_LOCATE_NEXT
	LD DE,STR_POPUP_SAVE_TITLE
	CALL PRINT_STR

	CALL POPUP_PRINT_BORDER

	CALL POPUP_LOCATE_NEXT
	LD DE,STR_POPUP_SAVE_MSG1
	CALL PRINT_STR

	CALL POPUP_LOCATE_NEXT
	LD DE,STR_POPUP_SAVE_MSG2
	CALL PRINT_STR

	CALL POPUP_LOCATE_NEXT
	LD DE,STR_POPUP_SAVE_KEYS
	CALL PRINT_STR

	CALL POPUP_PRINT_BORDER

DSCP_KEY_LOOP:
	CALL GET_KEY
	CP 'y'
	JR Z,DSCP_CHOSE_Y
	CP 'Y'
	JR Z,DSCP_CHOSE_Y

	CP 'n'
	JR Z,DSCP_CHOSE_N
	CP 'N'
	JR Z,DSCP_CHOSE_N

	CP KEY_ESC
	JR Z,DSCP_CHECK_ESC

	JR DSCP_KEY_LOOP

DSCP_CHECK_ESC:
	; Check if a character follows ESC within a short timeout
	LD BC,ESC_TIMEOUT_LOOPS
DSCP_WAIT_ESC:
	CALL CHECK_KEY_READY
	JR NZ,DSCP_DRAIN_ESC
	DEC BC
	LD A,B
	OR C
	JR NZ,DSCP_WAIT_ESC
	; Standalone ESC key: cancel
	JR DSCP_CANCEL

DSCP_DRAIN_ESC:
	CALL GET_KEY			; Consume '[' or 'O'
DSCP_DRAIN_MORE:
	LD BC,500
DSCP_DRAIN_WAIT:
	CALL CHECK_KEY_READY
	JR NZ,DSCP_DRAIN_BYTE
	DEC BC
	LD A,B
	OR C
	JR NZ,DSCP_DRAIN_WAIT
	; Sequence drained: resume key loop
	JR DSCP_KEY_LOOP

DSCP_DRAIN_BYTE:
	CALL GET_KEY
	JR DSCP_DRAIN_MORE

DSCP_CHOSE_Y:
	LD A,'Y'
	OR A				; Carry = 0
	RET

DSCP_CHOSE_N:
	LD A,'N'
	OR A				; Carry = 0
	RET

DSCP_CANCEL:
	SCF				; Carry = 1
	RET

;------------------------------------------------------------------------------
; EXIT_CANCEL: Cancel exit/close prompt and return to active editor
;
; Purpose:
;   Restores stack pointer, forces cache reload, re-renders screen and status
;   bar, locates cursor, and resumes MAIN_LOOP after user presses ESC in prompt.
;
; Call Usage / Protocol:
;   Jumped to from SHOW_EXIT_PROMPT when DO_SAVE_CHANGES_POPUP returns Carry=1.
;
; Inputs:
;   None
;
; Outputs:
;   Returns to MAIN_LOOP.
;
; Preserves / Modifies:
;   Resets SP to LOCAL_STACK; clobbers all working registers.
;------------------------------------------------------------------------------
EXIT_CANCEL:
	XOR A
	LD (IS_EXIT_PROMPT),A
	LD SP,LOCAL_STACK
	CALL RELOAD_CACHE_WINDOW_FORCE
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	CALL LOCATE_CURSOR
	XOR A
	LD (NEED_SCREEN_RENDER),A
	LD (NEED_LINE_RENDER),A
	LD (NEED_STATUS_RENDER),A
	JP MAIN_LOOP

;------------------------------------------------------------------------------
; EXIT_SAVE_AND_QUIT: Save document changes and execute pending action
;
; Purpose:
;   Saves modified document to disk (prompting for filename if unnamed),
;   then proceeds to execute confirmed action (exit, close, new, or open).
;
; Call Usage / Protocol:
;   Jumped to from SHOW_EXIT_PROMPT when user answers 'Y'.
;
; Inputs:
;   WORK_FCB, HAS_FILE_ARG, CONFIRM_ACTION.
;
; Outputs:
;   Saves file and jumps to EXEC_CONFIRM_ACTION.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
EXIT_SAVE_AND_QUIT:
	XOR A
	LD (IS_EXIT_PROMPT),A
	; Check if document has a known filename
	LD A,(WORK_FCB+1)
	CP ' '
	JR Z,EXIT_SAVE_PROMPT_NAME
	CP 0
	JR Z,EXIT_SAVE_PROMPT_NAME
	LD A,(HAS_FILE_ARG)
	OR A
	JR Z,EXIT_SAVE_PROMPT_NAME

	; Known file: save directly to disk
	CALL DO_ACTUAL_SAVE
	JP EXEC_CONFIRM_ACTION

EXIT_SAVE_PROMPT_NAME:
	CALL DO_SAVE_FILE_UI
	LD A,(DOC_MODIFIED)
	OR A
	JP Z,EXEC_CONFIRM_ACTION	; Save succeeded -> execute action

	; Save was cancelled by user: resume editor
	CALL TERM_INIT
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	CALL LOCATE_CURSOR
	XOR A
	LD (NEED_SCREEN_RENDER),A
	LD (NEED_LINE_RENDER),A
	LD (NEED_STATUS_RENDER),A
	JP MAIN_LOOP

;------------------------------------------------------------------------------
; EXEC_CONFIRM_ACTION: Dispatch confirmed exit/close/new/open action
;
; Purpose:
;   Dispatches execution based on value in CONFIRM_ACTION:
;   ACTION_CLOSE -> DO_EXEC_CLOSE, ACTION_NEW -> DO_EXEC_NEW,
;   ACTION_OPEN -> DO_EXEC_OPEN, otherwise -> EXIT_PROGRAM.
;
; Call Usage / Protocol:
;   Jumped to after unsaved changes prompt is satisfied or bypassed.
;
; Inputs:
;   CONFIRM_ACTION (ACTION_EXIT, ACTION_CLOSE, ACTION_NEW, ACTION_OPEN).
;
; Outputs:
;   Transfers control to appropriate action handler.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
EXEC_CONFIRM_ACTION:
	XOR A
	LD (IS_EXIT_PROMPT),A
	LD A,(CONFIRM_ACTION)
	CP ACTION_CLOSE
	JR Z,DO_EXEC_CLOSE
	CP ACTION_NEW
	JR Z,DO_EXEC_NEW
	CP ACTION_OPEN
	JR Z,DO_EXEC_OPEN
	JP EXIT_PROGRAM

DO_EXEC_CLOSE:
	CALL DO_CLOSE_DOCUMENT
	JP SHOW_SPLASH_SCREEN

DO_EXEC_NEW:
	CALL DO_NEW_DOCUMENT
	JP MAIN_LOOP

DO_EXEC_OPEN:
	XOR A
	LD (DOC_MODIFIED),A
	CALL DO_OPEN_FILE_UI
	CALL TERM_INIT
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	XOR A
	LD (NEED_SCREEN_RENDER),A
	LD (NEED_LINE_RENDER),A
	LD (NEED_STATUS_RENDER),A
	JP MAIN_LOOP

;------------------------------------------------------------------------------
; DO_CLOSE_DOCUMENT: Close active document and free associated resources
;
; Purpose:
;   Re-initializes empty document state, clears filename, modification flags,
;   cache dirty flags, block selection, and zero-fills WORK_FCB.
;
; Call Usage / Protocol:
;   Called via CALL from DO_EXEC_CLOSE or DO_NEW_DOCUMENT.
;
; Inputs:
;   None
;
; Outputs:
;   Document reset; WORK_FCB cleared.
;
; Preserves / Modifies:
;   Clobbers AF, B, HL. Preserves C, DE.
;------------------------------------------------------------------------------
DO_CLOSE_DOCUMENT:
	XOR A
	LD (PLUGIN_RET_CODE),A
	CALL INIT_EMPTY_DOCUMENT
	XOR A
	LD (HAS_FILE_ARG),A
	LD (IN_EDITOR_MODE),A
	LD (DOC_MODIFIED),A
	LD (DOC_USER_NUM),A
	LD (WORK_FCB_USER),A
	CALL CLEAR_CACHE_DIRTY_FLAGS
	LD (BLOCK_ACTIVE),A
	; Clear WORK_FCB (36 bytes)
	LD HL,WORK_FCB
	LD B,36
CLOSE_FCB_LOOP:
	LD (HL),0
	INC HL
	DJNZ CLOSE_FCB_LOOP
	RET

;------------------------------------------------------------------------------
; DO_NEW_DOCUMENT: Create a fresh empty document and initialize editor view
;
; Purpose:
;   Closes any active document, sets editor mode flag, clears screen,
;   and renders empty editor workspace with status bar.
;
; Call Usage / Protocol:
;   Called via CALL from DO_EXEC_NEW.
;
; Inputs:
;   None
;
; Outputs:
;   IN_EDITOR_MODE = 1; fresh workspace rendered.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
DO_NEW_DOCUMENT:
	CALL DO_CLOSE_DOCUMENT
	LD A,1
	LD (IN_EDITOR_MODE),A
	CALL TERM_INIT
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	RET

;------------------------------------------------------------------------------
; EXIT_PROGRAM: Clean up system state and exit cleanly to CP/M
;
; Purpose:
;   Deletes temporary swap file from disk, resets terminal video attributes,
;   restores cursor visibility, displays exit message, restores original
;   CP/M user number, unmounts/restores RAM drive if modified, restores
;   initial stack pointer, and returns to CP/M CCP.
;
; Call Usage / Protocol:
;   Jumped to when terminating application.
;
; Inputs:
;   SAVED_SP, ORIG_CPM_USER.
;
; Outputs:
;   Returns to CP/M CCP via RET with restored SP.
;
; Preserves / Modifies:
;   Restores entry SP; clobbers working registers.
;------------------------------------------------------------------------------
EXIT_PROGRAM:
	CALL CLEANUP_SWAP_FILE
	CALL TERM_INIT
	LD DE,MSG_EXIT
	CALL PRINT_STR
	CALL TERM_SHOW_CURSOR

	; Restore original CP/M user area
	LD A,(ORIG_CPM_USER)
	LD E,A
	LD C,32				; BDOS Set User Area
	CALL BDOS_ENTRY

	CALL RESTORE_RAMDRIVE

	LD SP,(SAVED_SP)
	RET

;------------------------------------------------------------------------------
; Screen Geometry Setup
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; SET_MODE_120X40: Configure display geometry for 120 columns x 40 rows
;
; Purpose:
;   Configures screen geometry variables to 120 columns by 40 rows,
;   setting horizontal viewport bounds to [0..120].
;
; Call Usage / Protocol:
;   Called via CALL during startup initialization or from configuration menu.
;
; Inputs:
;   None
;
; Outputs:
;   SCREEN_MODE = MODE_120X40, ACTIVE_ROWS = 40, ACTIVE_COLS = 120,
;   VIEW_LEFT_COL = 0, VIEW_RIGHT_COL = 120.
;
; Preserves / Modifies:
;   Preserves BC, DE; clobbers AF, HL.
;------------------------------------------------------------------------------
SET_MODE_120X40:
	LD A,MODE_120X40
	LD (SCREEN_MODE),A
	LD A,40
	LD (ACTIVE_ROWS),A
	LD (HOST_API_ROWS),A
	LD A,120
	LD (ACTIVE_COLS),A
	LD (HOST_API_COLS),A
	LD HL,0
	LD (VIEW_LEFT_COL),HL
	LD HL,120
	LD (VIEW_RIGHT_COL),HL
	RET

;------------------------------------------------------------------------------
; SET_MODE_80X24: Configure display geometry for 80 columns x 24 rows
;
; Purpose:
;   Configures screen geometry variables to 80 columns by 24 rows,
;   setting horizontal viewport bounds to [0..80].
;
; Call Usage / Protocol:
;   Called via CALL during startup or from configuration menu.
;
; Inputs:
;   None
;
; Outputs:
;   SCREEN_MODE = MODE_80X24, ACTIVE_ROWS = 24, ACTIVE_COLS = 80,
;   VIEW_LEFT_COL = 0, VIEW_RIGHT_COL = 80.
;
; Preserves / Modifies:
;   Preserves BC, DE; clobbers AF, HL.
;------------------------------------------------------------------------------
SET_MODE_80X24:
	LD A,MODE_80X24
	LD (SCREEN_MODE),A
	LD A,24
	LD (ACTIVE_ROWS),A
	LD (HOST_API_ROWS),A
	LD A,80
	LD (ACTIVE_COLS),A
	LD (HOST_API_COLS),A
	LD HL,0
	LD (VIEW_LEFT_COL),HL
	LD HL,80
	LD (VIEW_RIGHT_COL),HL
	RET

;------------------------------------------------------------------------------
; Hardware Abstraction Layer - Console Driver (Profile 2: NextCPM)
;------------------------------------------------------------------------------
	INCLUDE "hal/next_cpm/hal_nextcpm_console.asm"

;------------------------------------------------------------------------------
; Command Line & FCB Initialization
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; CHECK_COMMAND_LINE: Parse CP/M command line buffer into WORK_FCB
;
; Purpose:
;   Examines default DMA buffer at 0080H. If an argument is present, parses
;   optional FAT path prefix, drive/user prefix, and optional :<line> goto
;   suffix, populating WORK_FCB, DOC_USER_NUM, and CMDLINE_GOTO_LINE.
;   If empty, defaults WORK_FCB to "OUTPUT.TXT".
;
; Call Usage / Protocol:
;   Called via CALL once during START initialization.
;
; Inputs:
;   Default DMA buffer at 0080H.
;
; Outputs:
;   HAS_FILE_ARG = 0 or 1; WORK_FCB populated; CMDLINE_GOTO_LINE set.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
CHECK_COMMAND_LINE:
	LD HL,0
	LD (CMDLINE_GOTO_LINE),HL
	XOR A
	LD (CMDLINE_HAS_DRIVE),A
	LD (CMDLINE_IS_FAT),A

	; Check DEFAULT_DMA length byte at 0080H
	LD A,(DEFAULT_DMA)
	OR A
	JP Z,NO_FILE_ARG

	; Null-terminate command line tail: DEFAULT_DMA + 1 + length
	LD E,A
	LD D,0
	LD HL,DEFAULT_DMA+1
	ADD HL,DE
	LD (HL),0			; Null-terminate

	; Skip leading spaces
	LD HL,DEFAULT_DMA+1
CCL_SKIP_SP:
	LD A,(HL)
	CP ' '
	JR NZ,CCL_CHECK_NONEMPTY
	INC HL
	JR CCL_SKIP_SP

CCL_CHECK_NONEMPTY:
	OR A
	JP Z,NO_FILE_ARG		; Only spaces -> no file arg

	; We have a command line argument!
	LD A,1
	LD (HAS_FILE_ARG),A

	; Check if command-line argument is a FAT path (U: or U<unit>:)
	PUSH HL
	CALL PARSE_FAT_PATH		; A = unit, HL = path after ':'
	JR NC,CCL_NOT_FAT_ARG

	; Command line is a FAT path!
	LD (CMDLINE_FAT_UNIT),A
	LD (FAT_DOC_UNIT),A
	LD A,1
	LD (CMDLINE_IS_FAT),A
	POP AF				; Discard saved initial HL

	; Copy path after ':' into FAT_DOC_PATH (prepending '/' if needed)
	LD DE,FAT_DOC_PATH
	LD A,(HL)
	CP '/'
	JR Z,CCL_COPY_PATH
	LD A,'/'
	LD (DE),A
	INC DE
CCL_COPY_PATH:
	LD A,(HL)
	OR A
	JR Z,CCL_PATH_TERMINATE
	CP ' '
	JR Z,CCL_PATH_TERMINATE
	LD (DE),A
	INC HL
	INC DE
	JR CCL_COPY_PATH

CCL_PATH_TERMINATE:
	XOR A
	LD (DE),A

	; Extract base filename into FAT_DOC_FNAME
	LD HL,FAT_DOC_PATH
	CALL EXTRACT_BASE_FILENAME
	RET

CCL_NOT_FAT_ARG:
	POP HL

	; Parse optional :<line> suffix from DEFAULT_DMA
	CALL PARSE_CMDLINE_LINE_NUM

	; Parse command line argument into WORK_FCB and WORK_FCB_USER
	LD HL,DEFAULT_DMA+1
	CALL PARSE_STRING_TO_FCB

	; Check if command line had an explicit drive
	LD A,(PREFIX_DRIVE)
	OR A
	JR Z,CCL_CHECK_USER
	LD A,1
	LD (CMDLINE_HAS_DRIVE),A

CCL_CHECK_USER:
	; Update DOC_USER_NUM and CURRENT_DIR_USER to match WORK_FCB_USER
	LD A,(WORK_FCB_USER)
	LD (DOC_USER_NUM),A
	LD (CURRENT_DIR_USER),A
	; Update CURRENT_DIR_DRIVE and title strings to match WORK_FCB
	LD A,(WORK_FCB)
	OR A
	JR Z,CCL_DONE
	LD (CURRENT_DIR_DRIVE),A
	ADD A,'A'-1
	LD (STR_DIR_DRIVE_CHAR),A
	LD (STR_SAVE_DRIVE_CHAR),A
CCL_DONE:
	RET

NO_FILE_ARG:
	XOR A
	LD (HAS_FILE_ARG),A
	LD (CMDLINE_HAS_DRIVE),A

	; Zero entire WORK_FCB (36 bytes)
	LD HL,WORK_FCB
	LD (HL),0
	LD DE,WORK_FCB+1
	LD BC,35
	LDIR

	; Set default filename to OUTPUT.TXT
	LD HL,DEFAULT_FCB_NAME
	LD DE,WORK_FCB
	LD BC,12
	LDIR
	RET

;------------------------------------------------------------------------------
; PARSE_CMDLINE_LINE_NUM: Parse optional :<line> suffix from command line tail
;
; Purpose:
;   Scans backward from end of command line in DEFAULT_DMA to detect trailing
;   numeric line argument (e.g. "FILE.TXT:150"). Differentiates from drive/user
;   prefix colon. If found, stores 16-bit line number in CMDLINE_GOTO_LINE.
;
; Call Usage / Protocol:
;   Called via CALL from CHECK_COMMAND_LINE.
;
; Inputs:
;   DEFAULT_DMA buffer at 0080H.
;
; Outputs:
;   CMDLINE_GOTO_LINE updated with parsed integer value (or left unchanged).
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
PARSE_CMDLINE_LINE_NUM:
	LD A,(DEFAULT_DMA)		; A = length of command line tail
	OR A
	RET Z				; Empty command line

	; HL = pointer to end of command line: DEFAULT_DMA + length
	LD E,A
	LD D,0
	LD HL,DEFAULT_DMA
	ADD HL,DE			; HL points to last char of tail

	; Trim trailing spaces
TRIM_TRAIL_SPACES:
	LD A,(HL)
	CP ' '
	JR NZ,CHECK_TRAIL_DIGITS
	DEC HL
	DEC E
	JR NZ,TRIM_TRAIL_SPACES
	RET				; Only spaces found

CHECK_TRAIL_DIGITS:
	; Last non-space character must be a digit '0'..'9'
	LD A,(HL)
	CP '0'
	RET C
	CP '9'+1
	RET NC

	; Scan backwards past all digits to find preceding ':'
SCAN_DIGITS_BACK:
	DEC HL
	DEC E
	RET Z				; Hit start of buffer without ':'
	LD A,(HL)
	CP ':'
	JR Z,FOUND_COLON
	CP '0'
	JR C,NOT_LINE_NUM
	CP '9'+1
	JR C,SCAN_DIGITS_BACK
NOT_LINE_NUM:
	RET

FOUND_COLON:
	; HL points to ':' in DEFAULT_DMA. Check if this colon is inside a
	; drive/user prefix.
	PUSH HL				; Save colon pointer
	LD HL,DEFAULT_DMA+1
	CALL PARSE_DRIVE_USER_PREFIX
	JR NC,FCLN_IS_LINE		; No prefix at start -> line colon

	; Prefix matched: HL is now past the prefix colon!
	POP DE				; DE = colon pointer
	PUSH DE
	LD A,D
	CP H
	JR NZ,FCLN_CMP
	LD A,E
	CP L
FCLN_CMP:
	JR C,FCLN_IS_DRIVE		; DE < HL -> colon is part of prefix!

FCLN_IS_LINE:
	POP HL				; Restore colon pointer
	INC HL				; HL points to digits
	CALL PARSE_DEC_WORD		; DE = 16-bit parsed value
	LD (CMDLINE_GOTO_LINE),DE
	RET

FCLN_IS_DRIVE:
	POP HL				; Restore colon pointer
	RET

;------------------------------------------------------------------------------
; IS_ALPHA_CHAR: Test if character in A is alphabetic ('A'..'Z' or 'a'..'z')
;
; Purpose:
;   Validates whether ASCII byte in register A is an uppercase or lowercase
;   alphabetic character.
;
; Call Usage / Protocol:
;   Called via CALL from command line and FCB parsers.
;
; Inputs:
;   A = Character byte to test.
;
; Outputs:
;   Carry = 1 if alphabetic ('A'..'Z' or 'a'..'z'); Carry = 0 otherwise.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; modifies AF (flags).
;------------------------------------------------------------------------------
IS_ALPHA_CHAR:
	CP 'A'
	JR C,NOT_ALPHA
	CP 'Z'+1
	JR C,IS_ALPHA
	CP 'a'
	JR C,NOT_ALPHA
	CP 'z'+1
	JR NC,NOT_ALPHA
IS_ALPHA:
	SCF
	RET
NOT_ALPHA:
	OR A
	RET

;------------------------------------------------------------------------------
; Splash Screen Renderer (Vim Style)
; Dynamically centered both horizontally and vertically for active screen
; geometry.
; Total menu lines: 20
; SPLASH_MENU_LINES is defined in include/ui.inc

;------------------------------------------------------------------------------
; PRINT_TILDE_CRLF: Output '~' character followed by carriage return and newline
;
; Purpose:
;   Prints "~" followed by CR (0x0D) and LF (0x0A) to indicate empty lines
;   beyond end of document or in splash top margin.
;
; Call Usage / Protocol:
;   Called via CALL during screen viewport rendering.
;
; Inputs:
;   None
;
; Outputs:
;   "~<CR><LF>" transmitted to console.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
PRINT_TILDE_CRLF:
	LD A,'~'
	CALL PUTC
	LD A,13
	CALL PUTC
	LD A,10
	CALL PUTC
	RET

;------------------------------------------------------------------------------
; PRINT_SPLASH_PREFIX: Print '~' followed by geometry-dependent left padding
;
; Purpose:
;   Outputs "~" in column 0 followed by horizontal centering spaces budgeted
;   for splash/about screens (19 spaces in 80x24, 39 spaces in 120x40).
;
; Call Usage / Protocol:
;   Called via CALL before printing each line of splash, about, or config.
;
; Inputs:
;   SCREEN_MODE (MODE_80X24 or MODE_120X40).
;
; Outputs:
;   Centering prefix emitted to console.
;
; Preserves / Modifies:
;   Preserves DE, HL; clobbers AF, BC.
;------------------------------------------------------------------------------
PRINT_SPLASH_PREFIX:
	LD A,'~'
	CALL PUTC
	LD A,(SCREEN_MODE)
	CP MODE_120X40
	JR NZ,PSP_80X24
	LD B,39
	JR PSP_LOOP
PSP_80X24:
	LD B,19
PSP_LOOP:
	LD A,' '
	CALL PUTC
	DJNZ PSP_LOOP
	RET

;------------------------------------------------------------------------------
; RENDER_SPLASH: Draw splash screen logo, version info, and menu options
;
; Purpose:
;   Hides cursor, clears screen, calculates vertical top padding to center
;   content vertically, renders title logo, memory capacity, loaded plugins,
;   and menu shortcut guide.
;
; Call Usage / Protocol:
;   Called via CALL from SHOW_SPLASH_SCREEN.
;
; Inputs:
;   ACTIVE_ROWS, ACTIVE_COLS, SCREEN_MODE.
;
; Outputs:
;   Splash screen rendered on terminal.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
RENDER_SPLASH:
	LD A,1
	LD (IS_SPLASH_SCREEN),A
	CALL TERM_HIDE_CURSOR
	CALL TERM_CLEAR_SCREEN

	; Calculate vertical top padding: ((ACTIVE_ROWS - 1) -
	; SPLASH_MENU_LINES) / 2
	LD A,(ACTIVE_ROWS)
	DEC A		; Text rows available (23 in 80x24, 39 in 120x40)
	SUB SPLASH_MENU_LINES	; 23 - 21 = 2 (80x24), 39 - 21 = 18 (120x40)
	JR Z,SPLASH_NO_TOP_PAD
	JR C,SPLASH_NO_TOP_PAD
	SRL A				; 1 (80x24), 9 (120x40)
	JR Z,SPLASH_NO_TOP_PAD
	LD (SPLASH_TOP_PAD_COUNT),A
	LD B,A
SPLASH_TOP_PAD_LOOP:
	CALL PRINT_TILDE_CRLF
	DJNZ SPLASH_TOP_PAD_LOOP
	JR SPLASH_CONTENT_START

SPLASH_NO_TOP_PAD:
	XOR A
	LD (SPLASH_TOP_PAD_COUNT),A

SPLASH_CONTENT_START:
	; Row 1: Title (centered within 41-col block with 11 spaces)
	CALL PRINT_SPLASH_PREFIX
	LD DE,STR_SPLASH_TITLE_PAD
	CALL PRINT_STR
	LD DE,STR_SPLASH_TITLE
	CALL PRINT_STR

	; Row 2: Blank line
	CALL PRINT_TILDE_CRLF

	; Rows 3..16: 14 Commands
	LD HL,STR_SPLASH_CMDS
SPLASH_CMDS_LINE:
	LD A,(HL)
	OR A
	JR Z,SPLASH_CMDS_DONE
	CALL PRINT_SPLASH_PREFIX
SPLASH_CMDS_CHAR:
	LD A,(HL)
	INC HL
	CALL PUTC
	CP 10				; LF reached?
	JR NZ,SPLASH_CMDS_CHAR
	JR SPLASH_CMDS_LINE
SPLASH_CMDS_DONE:

	; Row 17: Blank line
	CALL PRINT_TILDE_CRLF

	; Row 17: Active Screen Mode
	CALL PRINT_SPLASH_PREFIX
	LD DE,STR_SPLASH_CUR_MODE
	CALL PRINT_STR

	LD A,(SCREEN_MODE)
	CP MODE_120X40
	JR NZ,SHOW_SPLASH_80X24
	LD DE,STR_SPLASH_120X40_LBL
	CALL PRINT_STR
	JR RENDER_SPLASH_RAM_STATUS

SHOW_SPLASH_80X24:
	LD DE,STR_SPLASH_80X24_LBL
	CALL PRINT_STR

RENDER_SPLASH_RAM_STATUS:
	; Row 18: RAM Drive Status
	CALL PRINT_SPLASH_PREFIX
	LD A,(RAMDRIVE_DRIVE_NUM)
	CP 0FFH
	JR Z,SPLASH_RAM_NONE

	LD DE,STR_SPLASH_RAM_PRE
	CALL PRINT_STR

	LD A,(RAMDRIVE_IS_HIBERNATED)
	OR A
	JR NZ,SPLASH_RAM_HIB

	LD A,(CFG_RAMDRIVE_FLAG)
	CP RAMDRV_MODE_ENABLED
	JR Z,SPLASH_RAM_OVW

	LD DE,STR_SPLASH_RAM_PRESERV
	CALL PRINT_STR
	JR RENDER_SPLASH_PLUG_STATUS

SPLASH_RAM_HIB:
	LD DE,STR_SPLASH_RAM_HIBERN
	CALL PRINT_STR
	JR RENDER_SPLASH_PLUG_STATUS

SPLASH_RAM_OVW:
	LD DE,STR_SPLASH_RAM_OVERWR
	CALL PRINT_STR
	JR RENDER_SPLASH_PLUG_STATUS

SPLASH_RAM_NONE:
	LD DE,STR_SPLASH_RAM_NONE
	CALL PRINT_STR

RENDER_SPLASH_PLUG_STATUS:
	; Row 19: Plugin System Status
	CALL PRINT_SPLASH_PREFIX
	LD DE,STR_SPLASH_PLUG_PRE
	CALL PRINT_STR

	LD A,(PLUGIN_MGR_LOADED)
	OR A
	JR NZ,SPLASH_PLUG_OPERATIONAL

	; Not loaded: check Far RAM availability (EXT_BANK_COUNT >= 2)
	LD A,(EXT_BANK_COUNT)
	CP 2
	JR C,SPLASH_PLUG_DISABLED

	; Far RAM is available: check if disabled in config
	LD A,(CFG_AUTOLOAD_PLUGIN_MGR)
	OR A
	JR Z,SPLASH_PLUG_DISABLED

	; Subsystem enabled (Autoload/On Demand), but not resident -> On Demand
	LD DE,STR_SPLASH_PLUG_ONDEMAND
	CALL PRINT_STR
	JR RENDER_SPLASH_LINES_STATUS

SPLASH_PLUG_OPERATIONAL:
	LD DE,STR_SPLASH_PLUG_OPERATIONAL
	CALL PRINT_STR
	JR RENDER_SPLASH_LINES_STATUS

SPLASH_PLUG_DISABLED:
	LD DE,STR_SPLASH_PLUG_DISABLED
	CALL PRINT_STR

RENDER_SPLASH_LINES_STATUS:
	; Row 20: Max Document Lines Status
	CALL PRINT_SPLASH_PREFIX
	LD DE,STR_SPLASH_LINES_PRE
	CALL PRINT_STR

	; Check if paging active: EXT_BANK_COUNT >= 2
	LD A,(EXT_BANK_COUNT)
	CP 2
	JR C,SPLASH_LINES_RAM

	; Paging active: check MAX_DOC_LINES_LIMIT (high byte of 32768 is 0x80)
	LD A,(MAX_DOC_LINES_LIMIT+1)
	CP 80H
	JR Z,SPLASH_LINES_32K

	LD DE,STR_SPLASH_LINES_16K
	CALL PRINT_STR
	JR RENDER_SPLASH_BOTTOM_PAD

SPLASH_LINES_32K:
	LD DE,STR_SPLASH_LINES_32K
	CALL PRINT_STR
	JR RENDER_SPLASH_BOTTOM_PAD

SPLASH_LINES_RAM:
	LD DE,STR_SPLASH_LINES_RAM
	CALL PRINT_STR

RENDER_SPLASH_BOTTOM_PAD:
	; Bottom padding: (ACTIVE_ROWS - 1) - SPLASH_TOP_PAD_COUNT -
	; SPLASH_MENU_LINES
	LD A,(ACTIVE_ROWS)
	DEC A				; Text rows available
	LD HL,SPLASH_TOP_PAD_COUNT
	SUB (HL)
	SUB SPLASH_MENU_LINES
	JR Z,SPLASH_BOTTOM_DONE
	JR C,SPLASH_BOTTOM_DONE
	LD B,A
SPLASH_BOTTOM_LOOP:
	CALL PRINT_TILDE_CRLF
	DJNZ SPLASH_BOTTOM_LOOP

SPLASH_BOTTOM_DONE:
	CALL RENDER_STATUS_BAR
	CALL TERM_HOME
	CALL TERM_HIDE_CURSOR
	RET

;------------------------------------------------------------------------------
; About Screen Renderer
; Dynamically centered both horizontally and vertically for active screen
; geometry.
; Displays essential project, version, author, tools, and MIT license details.
; ABOUT_MENU_LINES is defined in include/ui.inc

;------------------------------------------------------------------------------
; PRINT_ABOUT_LINE: Print string horizontally centered with column 0 tilde
;
; Purpose:
;   Measures length of string pointed to by DE, outputs '~' in column 0,
;   computes and emits symmetrical left margin spaces, prints string via
;   PRINT_STR, and emits CRLF.
;
; Call Usage / Protocol:
;   Called via CALL from SHOW_ABOUT_SCREEN for each text row.
;
; Inputs:
;   DE = Pointer to null-terminated or '$'-terminated string.
;
; Outputs:
;   Centered line with '~' margin emitted to console.
;
; Preserves / Modifies:
;   Preserves all registers: AF, BC, DE, HL.
;------------------------------------------------------------------------------
PRINT_ABOUT_LINE:
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL

	PUSH DE
	POP HL				; HL = string pointer
	LD B,0
PAL_LEN:
	LD A,(HL)
	OR A
	JR Z,PAL_LEN_DONE
	CP '$'
	JR Z,PAL_LEN_DONE
	INC HL
	INC B
	JR PAL_LEN
PAL_LEN_DONE:
	LD A,'~'
	CALL PUTC

	LD A,(ACTIVE_COLS)
	DEC A				; Columns remaining after '~'
	SUB B				; Subtract length in B
	JR C,PAL_NO_PAD		; If string longer than remaining cols, no pad
	SRL A			; Divide by 2 for symmetrical left margin
	JR Z,PAL_NO_PAD
	LD B,A
PAL_PAD_LOOP:
	LD A,' '
	CALL PUTC
	DJNZ PAL_PAD_LOOP

PAL_NO_PAD:
	CALL PRINT_STR
	LD A,13
	CALL PUTC
	LD A,10
	CALL PUTC

	POP HL
	POP DE
	POP BC
	POP AF
	RET

;------------------------------------------------------------------------------
; SHOW_ABOUT_SCREEN: Render About information screen
;
; Purpose:
;   Hides cursor, clears screen, computes vertical top padding to center
;   content vertically, renders title, version, author, AI attribution,
;   license, return prompt, status bar, and homes cursor.
;
; Call Usage / Protocol:
;   Called via CALL from SPLASH_LOOP when user selects 'A' (About).
;
; Inputs:
;   ACTIVE_ROWS, ACTIVE_COLS.
;
; Outputs:
;   About screen rendered on console.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SHOW_ABOUT_SCREEN:
	LD A,1
	LD (IS_SPLASH_SCREEN),A
	CALL TERM_HIDE_CURSOR
	CALL TERM_CLEAR_SCREEN

	; Calculate vertical top padding: ((ACTIVE_ROWS - 1) - ABOUT_MENU_LINES)
	; / 2
	LD A,(ACTIVE_ROWS)
	DEC A		; Text rows available (23 in 80x24, 39 in 120x40)
	SUB ABOUT_MENU_LINES	; 23 - 9 = 14 (80x24), 39 - 9 = 30 (120x40)
	JR Z,ABOUT_NO_TOP_PAD
	JR C,ABOUT_NO_TOP_PAD
	SRL A				; 7 in 80x24, 15 in 120x40
	JR Z,ABOUT_NO_TOP_PAD
	LD (ABOUT_TOP_PAD_COUNT),A
	LD B,A
ABOUT_TOP_PAD_LOOP:
	CALL PRINT_TILDE_CRLF
	DJNZ ABOUT_TOP_PAD_LOOP
	JR ABOUT_CONTENT_START

ABOUT_NO_TOP_PAD:
	XOR A
	LD (ABOUT_TOP_PAD_COUNT),A

ABOUT_CONTENT_START:
	; Row 1: Title
	LD DE,STR_ABOUT_TITLE
	CALL PRINT_ABOUT_LINE

	; Row 2: Version
	LD DE,STR_ABOUT_VERSION
	CALL PRINT_ABOUT_LINE

	; Row 3: Author
	LD DE,STR_ABOUT_AUTHOR
	CALL PRINT_ABOUT_LINE

	; Row 4: Blank line
	CALL PRINT_TILDE_CRLF

	; Row 5: AI & environment attribution
	LD DE,STR_ABOUT_AI
	CALL PRINT_ABOUT_LINE

	; Row 6: Blank line
	CALL PRINT_TILDE_CRLF

	; Row 7: MIT License
	LD DE,STR_ABOUT_LICENSE
	CALL PRINT_ABOUT_LINE

	; Row 8: Blank line
	CALL PRINT_TILDE_CRLF

	; Row 9: Return prompt
	LD DE,STR_ABOUT_RETURN
	CALL PRINT_ABOUT_LINE

	; Bottom padding: (ACTIVE_ROWS - 1) - ABOUT_TOP_PAD_COUNT -
	; ABOUT_MENU_LINES
	LD A,(ACTIVE_ROWS)
	DEC A				; Text rows available
	LD HL,ABOUT_TOP_PAD_COUNT
	SUB (HL)
	SUB ABOUT_MENU_LINES
	JR Z,ABOUT_BOTTOM_DONE
	JR C,ABOUT_BOTTOM_DONE
	LD B,A
ABOUT_BOTTOM_LOOP:
	CALL PRINT_TILDE_CRLF
	DJNZ ABOUT_BOTTOM_LOOP

ABOUT_BOTTOM_DONE:
	CALL RENDER_STATUS_BAR
	CALL TERM_HOME
	CALL TERM_HIDE_CURSOR
	RET

;------------------------------------------------------------------------------
; Configuration Screen Renderer
; Displays active screen geometry, config file status, and adjustment commands
;------------------------------------------------------------------------------
;------------------------------------------------------------------------------
; Configuration Screen Renderer (SHOW_CONFIG_SCREEN)
; Dynamically centered both horizontally and vertically for active screen
; geometry.
; Option order:
;   Config Status (at top, unnumbered status)
;   1. Screen Geometry
;   2. RAM Drive
;   3. Max Doc Lines
;   4. Tab Width
;   5. Plugin Manager
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; PRINT_CONFIG_PREFIX: Print '~' followed by config menu left padding
;
; Purpose:
;   Outputs '~' in column 0 followed by ((ACTIVE_COLS - 59) / 2) spaces
;   (10 spaces in 80x24 mode, 30 spaces in 120x40 mode) to horizontally
;   center the configuration options block.
;
; Call Usage / Protocol:
;   Called via CALL before each option row in SHOW_CONFIG_SCREEN.
;
; Inputs:
;   ACTIVE_COLS.
;
; Outputs:
;   Centering prefix emitted to console.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
PRINT_CONFIG_PREFIX:
	PUSH BC
	LD A,'~'
	CALL PUTC
	LD A,(ACTIVE_COLS)
	SUB 59
	SRL A
	JR Z,PCP_DONE
	LD B,A
PCP_LOOP:
	LD A,' '
	CALL PUTC
	DJNZ PCP_LOOP
PCP_DONE:
	POP BC
	RET

;------------------------------------------------------------------------------
; PRINT_CONFIG_BLANK_LINE: Output '~' followed by CRLF for config screen
;
; Purpose:
;   Emits "~" followed by CR (0x0D) and LF (0x0A) for empty margin lines.
;
; Call Usage / Protocol:
;   Called via CALL during configuration screen vertical padding.
;
; Inputs:
;   None
;
; Outputs:
;   "~<CR><LF>" emitted to console.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
PRINT_CONFIG_BLANK_LINE:
	LD A,'~'
	CALL PUTC
	LD A,13
	CALL PUTC
	LD A,10
	CALL PUTC
	RET

; CONFIG_MENU_LINES is defined in include/ui.inc

;------------------------------------------------------------------------------
; SHOW_CONFIG_SCREEN: Render Configuration Manager screen
;
; Purpose:
;   Hides cursor, clears screen, computes vertical top padding, renders
;   current configuration settings (geometry, RAM drive, max lines, tab width,
;   plugin manager mode), option key legend, and status bar.
;
; Call Usage / Protocol:
;   Called via CALL from DO_CONFIG_SCREEN and CONFIG_LOOP.
;
; Inputs:
;   ACTIVE_ROWS, ACTIVE_COLS, configuration variables.
;
; Outputs:
;   Configuration screen displayed on console.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SHOW_CONFIG_SCREEN:
	LD A,1
	LD (IS_SPLASH_SCREEN),A
	CALL TERM_HIDE_CURSOR
	CALL TERM_CLEAR_SCREEN

	; Calculate vertical top padding: ((ACTIVE_ROWS - 1) -
	; CONFIG_MENU_LINES) / 2
	LD A,(ACTIVE_ROWS)
	DEC A		; Text rows available (23 in 80x24, 39 in 120x40)
	SUB CONFIG_MENU_LINES	; 23 - 11 = 12 (80x24), 39 - 11 = 28 (120x40)
	JR Z,CONFIG_NO_TOP_PAD
	JR C,CONFIG_NO_TOP_PAD
	SRL A				; 6 in 80x24, 14 in 120x40
	JR Z,CONFIG_NO_TOP_PAD
	LD (CONFIG_TOP_PAD_COUNT),A
	LD B,A
CONFIG_TOP_PAD_LOOP:
	CALL PRINT_CONFIG_BLANK_LINE
	DJNZ CONFIG_TOP_PAD_LOOP
	JR CONFIG_CONTENT_START

CONFIG_NO_TOP_PAD:
	XOR A
	LD (CONFIG_TOP_PAD_COUNT),A

CONFIG_CONTENT_START:
	; Row 1: Header (centered title)
	LD DE,STR_CONFIG_TITLE
	CALL PRINT_ABOUT_LINE

	; Row 2: Blank line
	CALL PRINT_CONFIG_BLANK_LINE

	; Row 3: Config Status (at top, unnumbered)
	CALL PRINT_CONFIG_PREFIX
	LD DE,STR_CONFIG_STATUS_LBL
	CALL PRINT_STR
	LD A,(CONFIG_STATUS_FLAG)
	CP 1
	JR Z,SCS_STAT_LOCAL
	CP 2
	JR Z,SCS_STAT_PROG
	CP 3
	JR Z,SCS_STAT_SAVED
	CP 4
	JR Z,SCS_STAT_ERR

	; Default / None
	LD DE,STR_CFG_STAT_NONE
	CALL PRINT_STR
	JR SCS_AFTER_STATUS

SCS_STAT_LOCAL:
	LD DE,STR_CFG_STAT_LOCAL
	CALL PRINT_STR
	LD A,(CONFIG_SOURCE_DRIVE)
	ADD A,'A'
	CALL PUTC
	LD DE,STR_CFG_STAT_END
	CALL PRINT_STR
	JR SCS_AFTER_STATUS

SCS_STAT_PROG:
	LD DE,STR_CFG_STAT_PROG
	CALL PRINT_STR
	LD A,(CONFIG_SOURCE_DRIVE)
	ADD A,'A'
	CALL PUTC
	LD DE,STR_CFG_STAT_END
	CALL PRINT_STR
	JR SCS_AFTER_STATUS

SCS_STAT_SAVED:
	LD DE,STR_CFG_STAT_SAVED
	CALL PRINT_STR
	LD A,(CONFIG_SOURCE_DRIVE)
	ADD A,'A'
	CALL PUTC
	LD DE,STR_CFG_STAT_END
	CALL PRINT_STR
	JR SCS_AFTER_STATUS

SCS_STAT_ERR:
	LD DE,STR_CFG_STAT_ERR
	CALL PRINT_STR

SCS_AFTER_STATUS:
	; Row 4: Blank line
	CALL PRINT_CONFIG_BLANK_LINE

	; Row 5: 1. Screen Geometry
	CALL PRINT_CONFIG_PREFIX
	LD DE,STR_CONFIG_CUR_MODE
	CALL PRINT_STR
	LD A,(SCREEN_MODE)
	CP MODE_120X40
	JR NZ,SCS_80X24
	LD DE,STR_MODE_120X40_LBL
	CALL PRINT_STR
	JR SCS_RAM_MODE
SCS_80X24:
	LD DE,STR_MODE_80X24_LBL
	CALL PRINT_STR

SCS_RAM_MODE:
	; Row 6: 2. RAM Drive
	CALL PRINT_CONFIG_PREFIX
	LD A,(RAMDRIVE_DRIVE_NUM)
	CP 0FFH
	JR Z,SCS_RAM_NO_LETTER
	LD DE,STR_CONFIG_RAM_DRV_PRE
	CALL PRINT_STR
	LD A,(RAMDRIVE_DRIVE_CHAR)
	CALL PUTC
	LD DE,STR_CONFIG_RAM_DRV_POST
	CALL PRINT_STR
	JR SCS_RAM_VALUE

SCS_RAM_NO_LETTER:
	LD DE,STR_CONFIG_RAM_NONE
	CALL PRINT_STR

SCS_RAM_VALUE:
	LD A,(CFG_RAMDRIVE_FLAG)
	CP RAMDRV_MODE_HIBERNATE
	JR Z,SCS_RAM_HIB
	CP RAMDRV_MODE_ENABLED
	JR Z,SCS_RAM_ENABLED
	LD DE,STR_RAM_PROTECTED_LBL
	CALL PRINT_STR
	JR SCS_LINES_MODE
SCS_RAM_HIB:
	LD DE,STR_RAM_HIBERNATE_LBL
	CALL PRINT_STR
	JR SCS_LINES_MODE
SCS_RAM_ENABLED:
	LD DE,STR_RAM_ENABLED_LBL
	CALL PRINT_STR

SCS_LINES_MODE:
	; Row 7: 3. Max Doc Lines (grouped with RAM Drive!)
	CALL PRINT_CONFIG_PREFIX
	LD DE,STR_CONFIG_LINES_LBL
	CALL PRINT_STR
	LD A,(CFG_LINES_MODE)
	CP 1
	JR Z,SCS_LINES_32K
	LD DE,STR_LINES_16K_LBL
	CALL PRINT_STR
	JR SCS_TAB_MODE
SCS_LINES_32K:
	LD DE,STR_LINES_32K_LBL
	CALL PRINT_STR

SCS_TAB_MODE:
	; Row 8: 4. Tab Width (at the bottom!)
	CALL PRINT_CONFIG_PREFIX
	LD DE,STR_CONFIG_TAB_LBL
	CALL PRINT_STR
	LD A,(CFG_TAB_WIDTH)
	CP 4
	JR Z,SCS_TAB_4
	LD DE,STR_TAB_8_LBL
	CALL PRINT_STR
	JR SCS_PLUG_MODE
SCS_TAB_4:
	LD DE,STR_TAB_4_LBL
	CALL PRINT_STR

SCS_PLUG_MODE:
	; Row 9: 5. Plugin Manager
	CALL PRINT_CONFIG_PREFIX
	LD DE,STR_CONFIG_PLUG_LBL
	CALL PRINT_STR

	; Check Far RAM: if currently loaded, Far RAM was already verified
	LD A,(PLUGIN_MGR_LOADED)
	OR A
	JR NZ,SCS_PLUG_CHECK_MODE

	; Not loaded: check if Far RAM is insufficient (< 2 banks)
	LD A,(EXT_BANK_COUNT)
	CP 2
	JR C,SCS_PLUG_NO_FAR

SCS_PLUG_CHECK_MODE:
	LD A,(CFG_AUTOLOAD_PLUGIN_MGR)
	CP PLUGIN_MODE_AUTOLOAD
	JR Z,SCS_PLUG_AUTOLOAD
	CP PLUGIN_MODE_ONDEMAND
	JR Z,SCS_PLUG_ONDEMAND

	; Disabled by configuration
	LD DE,STR_PLUG_DIS_LBL
	CALL PRINT_STR
	JR SCS_AFTER_SETTINGS

SCS_PLUG_ONDEMAND:
	LD DE,STR_PLUG_ONDEMAND_LBL
	CALL PRINT_STR
	JR SCS_AFTER_SETTINGS

SCS_PLUG_NO_FAR:
	LD DE,STR_PLUG_NO_FAR_LBL
	CALL PRINT_STR
	JR SCS_AFTER_SETTINGS

SCS_PLUG_AUTOLOAD:
	LD DE,STR_PLUG_AUTO_LBL
	CALL PRINT_STR

SCS_AFTER_SETTINGS:
	; Row 10: Blank line before footer
	CALL PRINT_CONFIG_BLANK_LINE

	; Row 11: Footer command summary line
	LD DE,STR_CONFIG_FOOTER
	CALL PRINT_ABOUT_LINE

	; Bottom padding: (ACTIVE_ROWS - 1) - CONFIG_TOP_PAD_COUNT -
	; CONFIG_MENU_LINES
	LD A,(ACTIVE_ROWS)
	DEC A				; Text rows available
	LD HL,CONFIG_TOP_PAD_COUNT
	SUB (HL)
	SUB CONFIG_MENU_LINES
	JR Z,SCS_FOOTER_DONE
	JR C,SCS_FOOTER_DONE
	LD B,A
SCS_MARGIN_LOOP:
	CALL PRINT_CONFIG_BLANK_LINE
	DJNZ SCS_MARGIN_LOOP

SCS_FOOTER_DONE:
	; Row ACTIVE_ROWS: Status bar
	CALL RENDER_STATUS_BAR
	CALL TERM_HOME
	CALL TERM_HIDE_CURSOR
	RET


;------------------------------------------------------------------------------
; QUERY_MEM_SCREEN_INFO: Detect CP/M version and RomWBW HBIOS memory parameters
;
; Purpose:
;   Queries CP/M version via BDOS function 12, probes HBIOS presence via
;   HBIOS_DETECT, and if present queries HBIOS version (BF_SYSVER), system
;   BIOS bank (SYSGET 0xF2), and available application banks (SYSGET 0xF5).
;
; Call Usage / Protocol:
;   Called via CALL from SHOW_MEM_INFO_SCREEN prior to rendering table.
;
; Inputs:
;   None
;
; Outputs:
;   CPM_VERSION_ID, HBIOS_PRESENT, HBIOS_VER_MAJ/MIN/PATCH,
;   HBIOS_BIOS_BANK, HBIOS_APP_BANK, HBIOS_APP_COUNT populated.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL. Preserves IX, IY.
;------------------------------------------------------------------------------
QUERY_MEM_SCREEN_INFO:
	; 1. Query CP/M Version via BDOS 12
	LD C,12				; BDOS Get Version Number
	CALL BDOS_ENTRY
	LD (CPM_VERSION_ID),HL

	; 2. Check HBIOS presence
	CALL HBIOS_DETECT
	JR Z,QMSI_HBIOS_OK
	; Non-HBIOS fallback
	XOR A
	LD (HBIOS_PRESENT),A
	RET

QMSI_HBIOS_OK:
	LD A,1
	LD (HBIOS_PRESENT),A

	; Query HBIOS Version (BF_SYSVER = 0xF1)
	PUSH IX
	LD B,0F1H			; BF_SYSVER
	LD C,000H
	RST 08H
	POP IX
	; DE has version in BCD: D = Major << 4 | Minor, E = Update << 4 | Patch
	LD A,D
	RRCA
	RRCA
	RRCA
	RRCA
	AND 0FH
	LD (HBIOS_VER_MAJ),A
	LD A,D
	AND 0FH
	LD (HBIOS_VER_MIN),A
	LD A,E
	RRCA
	RRCA
	RRCA
	RRCA
	AND 0FH
	LD (HBIOS_VER_PATCH),A

	; Query BIOS Bank ID (SYSGET 0xF2)
	PUSH IX
	LD B,0F8H
	LD C,0F2H
	RST 08H
	POP IX
	LD A,D
	OR A
	JR NZ,QMSI_GOT_BIOS_BANK
	LD A,080H
QMSI_GOT_BIOS_BANK:
	LD (HBIOS_BIOS_BANK),A

	; Query App Banks (SYSGET 0xF5)
	PUSH IX
	LD B,0F8H
	LD C,0F5H			; BF_SYSGET_APPBNKS
	RST 08H
	POP IX
	OR A
	JR NZ,QMSI_SAVE_APP_DEFAULT
	LD A,H
	CP 0FFH
	JR Z,QMSI_SAVE_APP_DEFAULT
	LD (HBIOS_APP_BANK),A
	LD A,L
	LD (HBIOS_APP_COUNT),A
	RET

QMSI_SAVE_APP_DEFAULT:
	LD A,089H
	LD (HBIOS_APP_BANK),A
	LD A,3
	LD (HBIOS_APP_COUNT),A
	RET

;------------------------------------------------------------------------------
; Memory Information Screen Renderer
; Displays dynamic 16-row 32KB extended memory allocation map & system summary
;------------------------------------------------------------------------------
;------------------------------------------------------------------------------
; PRINT_MEM_PREFIX: Print '~' followed by geometry-dependent left padding
; Table content width is 72 columns (excluding col 0 '~').
; Padding: ((ACTIVE_COLS - 74) / 2) spaces
; 80x24:   3 spaces (1 +  3 + 72 +  4 = 80)
; 120x40: 23 spaces (1 + 23 + 72 + 24 = 120)
; Preserves: All registers except AF
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; PRINT_MEM_PREFIX: Print '~' followed by left padding for 72-column table
;
; Purpose:
;   Outputs '~' in column 0 followed by ((ACTIVE_COLS - 74) / 2) spaces
;   (3 spaces in 80x24 mode, 23 spaces in 120x40 mode) to horizontally
;   center the 72-column memory information table.
;
; Call Usage / Protocol:
;   Called via CALL before each row of the memory screen table.
;
; Inputs:
;   ACTIVE_COLS.
;
; Outputs:
;   Centering prefix emitted to console.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
PRINT_MEM_PREFIX:
	PUSH BC
	LD A,'~'
	CALL PUTC
	LD A,(ACTIVE_COLS)
	SUB 74
	JR C,PMP_DONE
	JR Z,PMP_DONE
	SRL A
	JR Z,PMP_DONE
	LD B,A
PMP_LOOP:
	LD A,' '
	CALL PUTC
	DJNZ PMP_LOOP
PMP_DONE:
	POP BC
	RET
; MEM_INFO_LINES is defined in include/ui.inc

;------------------------------------------------------------------------------
; SHOW_MEM_INFO_SCREEN: Render 16-row 32KB memory bank map and system summary
;
; Purpose:
;   Queries memory configuration, hides cursor, clears screen, calculates
;   vertical top padding, displays title, summary line, 16 individual bank
;   rows detailing physical bank IDs, roles, and usages, return prompt,
;   and status bar.
;
; Call Usage / Protocol:
;   Called via CALL from SPLASH_LOOP on 'M' (Memory Info).
;
; Inputs:
;   ACTIVE_ROWS, ACTIVE_COLS.
;
; Outputs:
;   Memory information screen rendered on console.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SHOW_MEM_INFO_SCREEN:
	CALL QUERY_MEM_SCREEN_INFO
	LD A,1
	LD (IS_SPLASH_SCREEN),A
	CALL TERM_HIDE_CURSOR
	CALL TERM_CLEAR_SCREEN

	; Calculate vertical top padding: ((ACTIVE_ROWS - 1) - MEM_INFO_LINES) /
	; 2
	LD A,(ACTIVE_ROWS)
	DEC A		; Text rows available (23 in 80x24, 39 in 120x40)
	SUB MEM_INFO_LINES	; 23 - 23 = 0 (80x24), 39 - 23 = 16 (120x40)
	JR Z,MEM_INFO_NO_TOP_PAD
	JR C,MEM_INFO_NO_TOP_PAD
	SRL A				; 0 (80x24), 8 (120x40)
	JR Z,MEM_INFO_NO_TOP_PAD
	LD (MEM_TOP_PAD_COUNT),A
	LD B,A
MEM_INFO_TOP_PAD_LOOP:
	CALL PRINT_TILDE_CRLF
	DJNZ MEM_INFO_TOP_PAD_LOOP
	JR MEM_INFO_CONTENT_START

MEM_INFO_NO_TOP_PAD:
	XOR A
	LD (MEM_TOP_PAD_COUNT),A

MEM_INFO_CONTENT_START:
	; Line 1: Title (centered within 72-col block)
	CALL PRINT_MEM_PREFIX
	LD DE,STR_MEM_TITLE_PAD
	CALL PRINT_STR
	LD DE,STR_MEM_INFO_TITLE
	CALL PRINT_STR

	; Line 2: System Summary Line
	CALL PRINT_MEM_INFO_SUMMARY

	; Line 3: Blank line with tilde
	CALL PRINT_TILDE_CRLF

	; Line 4: Table column headers
	CALL PRINT_MEM_PREFIX
	LD DE,STR_MEM_TABLE_HDR
	CALL PRINT_STR

	; Line 5: Table column dividers
	CALL PRINT_MEM_PREFIX
	LD DE,STR_MEM_TABLE_DIV
	CALL PRINT_STR

	; Lines 6..21: The 16 individual bank rows (Banks 00 through 15)
	XOR A
	LD (MEM_BANK_LOOP_IDX),A
MEM_BANK_ROW_LOOP:
	CALL PRINT_MEM_BANK_ROW
	LD A,(MEM_BANK_LOOP_IDX)
	INC A
	LD (MEM_BANK_LOOP_IDX),A
	CP 16
	JR C,MEM_BANK_ROW_LOOP

	; Line 22: Blank line with tilde
	CALL PRINT_TILDE_CRLF

	; Line 23: Return prompt (centered within 72-col block)
	CALL PRINT_MEM_PREFIX
	LD DE,STR_MEM_PROMPT_PAD
	CALL PRINT_STR
	LD DE,STR_MEM_RETURN_PROMPT
	CALL PRINT_STR

	; Calculate bottom padding: (ACTIVE_ROWS - 1) - MEM_TOP_PAD_COUNT -
	; MEM_INFO_LINES
	LD A,(ACTIVE_ROWS)
	DEC A		; Text rows available (23 in 80x24, 39 in 120x40)
	LD HL,MEM_TOP_PAD_COUNT
	SUB (HL)
	SUB MEM_INFO_LINES		; Remaining bottom padding
	JR Z,MEM_INFO_BOTTOM_DONE
	JR C,MEM_INFO_BOTTOM_DONE
	LD B,A
MEM_INFO_BOTTOM_LOOP:
	CALL PRINT_TILDE_CRLF
	DJNZ MEM_INFO_BOTTOM_LOOP

MEM_INFO_BOTTOM_DONE:
	CALL RENDER_STATUS_BAR
	CALL TERM_HOME
	CALL TERM_HIDE_CURSOR
	RET

;------------------------------------------------------------------------------
; PRINT_MEM_INFO_SUMMARY: Print memory screen system summary row
;
; Purpose:
;   Outputs prefix followed by formatted summary line containing RomWBW
;   HBIOS version, operating system name (CP/M 2.2 / CP/M 3.0 / CP/M 3.1 /
;   Z-System), total hardware RAM capacity, and SE RAM allocation total.
;
; Call Usage / Protocol:
;   Called via CALL from SHOW_MEM_INFO_SCREEN.
;
; Inputs:
;   HBIOS_PRESENT, CPM_VERSION_ID, RAM_BANK_COUNT, EXT_BANK_COUNT.
;
; Outputs:
;   Summary line emitted to console.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
PRINT_MEM_INFO_SUMMARY:
	CALL PRINT_MEM_PREFIX
	LD DE,STR_MEM_SUM_PREFIX
	CALL PRINT_STR

	LD A,(HBIOS_PRESENT)
	OR A
	JR NZ,PMIS_HBIOS_YES
	LD DE,STR_MEM_SUM_NONE
	CALL PRINT_STR
	JR PMIS_SHOW_OS

PMIS_HBIOS_YES:
	LD DE,STR_MEM_SUM_ROMWBW
	CALL PRINT_STR
	LD A,(HBIOS_VER_MAJ)
	CALL PRINT_DEC_BYTE
	LD A,'.'
	CALL PUTC
	LD A,(HBIOS_VER_MIN)
	CALL PRINT_DEC_BYTE

PMIS_SHOW_OS:
	LD DE,STR_MEM_SUM_OS
	CALL PRINT_STR

	LD HL,(CPM_VERSION_ID)
	LD A,H
	CP 014H
	JR Z,PMIS_OS_ZSYS
	LD A,L
	CP 031H
	JR Z,PMIS_OS_CPM31
	CP 030H
	JR Z,PMIS_OS_CPM30
	LD DE,STR_OS_CPM22
	JR PMIS_PRINT_OS
PMIS_OS_ZSYS:
	LD DE,STR_OS_ZSYS
	JR PMIS_PRINT_OS
PMIS_OS_CPM31:
	LD DE,STR_OS_CPM31
	JR PMIS_PRINT_OS
PMIS_OS_CPM30:
	LD DE,STR_OS_CPM30
PMIS_PRINT_OS:
	CALL PRINT_STR

	LD DE,STR_MEM_SUM_RAM
	CALL PRINT_STR

	LD A,(HBIOS_PRESENT)
	OR A
	JR NZ,PMIS_RAM_HBIOS
	LD DE,STR_MEM_SUM_RAM_BASE
	CALL PRINT_STR
	JR PMIS_SHOW_SE

PMIS_RAM_HBIOS:
	LD A,(RAM_BANK_COUNT)
	LD L,A
	LD H,0
	ADD HL,HL			; x2
	ADD HL,HL			; x4
	ADD HL,HL			; x8
	ADD HL,HL			; x16
	ADD HL,HL			; x32 (KB)
	CALL PRINT_DEC_WORD
	LD DE,STR_MEM_SUM_KB_MID
	CALL PRINT_STR
	LD A,(RAM_BANK_COUNT)
	CALL PRINT_DEC_BYTE
	LD DE,STR_MEM_SUM_X32K
	CALL PRINT_STR

PMIS_SHOW_SE:
	LD DE,STR_MEM_SUM_SE
	CALL PRINT_STR

	LD A,(HBIOS_PRESENT)
	OR A
	JR NZ,PMIS_SE_HBIOS
	LD DE,STR_MEM_SUM_64K_END
	CALL PRINT_STR
	RET

PMIS_SE_HBIOS:
	; Calculate SE RAM: (1 [TPA] + (1 if LINE_TABLE_BANK!=0) + (1 if
	; LINE_TABLE_BANK_1!=0) + EXT_BANK_COUNT) * 32
	LD A,1
	LD HL,LINE_TABLE_BANK
	LD B,(HL)
	INC B
	DEC B
	JR Z,PMIS_NO_LINE_BANK_0
	INC A				; A = 2
PMIS_NO_LINE_BANK_0:
	LD HL,LINE_TABLE_BANK_1
	LD B,(HL)
	INC B
	DEC B
	JR Z,PMIS_NO_LINE_BANK_1
	INC A				; A = 3
PMIS_NO_LINE_BANK_1:
	LD HL,PLUGIN_MGR_LOADED
	LD B,(HL)
	INC B
	DEC B
	JR Z,PMIS_NO_PLUG_BANK
	INC A
PMIS_NO_PLUG_BANK:
	LD HL,BORROWED_BANKS_CNT
	ADD A,(HL)
	LD HL,EXT_BANK_COUNT
	ADD A,(HL)			; A = total SE 32KB banks
	LD L,A
	LD H,0
	ADD HL,HL			; x2
	ADD HL,HL			; x4
	ADD HL,HL			; x8
	ADD HL,HL			; x16
	ADD HL,HL			; x32 (KB)
	CALL PRINT_DEC_WORD
	LD DE,STR_MEM_SUM_KB_END
	CALL PRINT_STR
	RET

;------------------------------------------------------------------------------
; PRINT_MEM_BANK_ROW: Print single 32KB memory bank status row (0..15)
;
; Purpose:
;   Formats and prints bank index (00..15), physical bank address (80h..8Fh),
;   size (32K/64K/--), architectural role (HBIOS, CP/M, RAM Disk, App RAM),
;   and specific SE or system usage (Document Buffer, Far Plugins, etc.).
;
; Call Usage / Protocol:
;   Called via CALL in a loop (0..15) from SHOW_MEM_INFO_SCREEN.
;
; Inputs:
;   MEM_BANK_LOOP_IDX = bank index (0..15).
;
; Outputs:
;   Formatted table row emitted to console.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
PRINT_MEM_BANK_ROW:
	; Column 0 Tilde and geometry padding
	CALL PRINT_MEM_PREFIX

	; 2-Digit Decimal Bank Index (00..15)
	LD A,(MEM_BANK_LOOP_IDX)
	CALL PRINT_2DIGIT_DEC

	; 4 spaces (align under 'Bank  ')
	LD DE,STR_MEM_SPACES_4
	CALL PRINT_STR

	; Physical Bank ID (80h..8Fh)
	LD A,(MEM_BANK_LOOP_IDX)
	ADD A,080H
	CALL PRINT_HEX_BYTE
	LD A,'h'
	CALL PUTC

	; 4 spaces (align under 'Phys   ')
	LD DE,STR_MEM_SPACES_4
	CALL PRINT_STR

	; Check if bank is installed
	LD A,(HBIOS_PRESENT)
	OR A
	JR NZ,PMBR_CHECK_RAM_COUNT

	; Non-HBIOS check: Only Bank 0 is base memory
	LD A,(MEM_BANK_LOOP_IDX)
	OR A
	JP NZ,PMBR_NOT_INSTALLED
	; Bank 00 non-HBIOS: 64K TPA
	LD DE,STR_MEM_SIZE_64K
	CALL PRINT_STR
	LD DE,STR_MEM_SPACES_3
	CALL PRINT_STR
	LD DE,STR_ROLE_TPA_CPM2
	CALL PRINT_STR
	LD DE,STR_MEM_SPACES_3
	CALL PRINT_STR
	LD DE,STR_USAGE_SE_PROG
	CALL PRINT_STR
	CALL PRINT_CRLF
	RET

PMBR_CHECK_RAM_COUNT:
	LD A,(MEM_BANK_LOOP_IDX)
	LD HL,RAM_BANK_COUNT
	CP (HL)
	JP NC,PMBR_NOT_INSTALLED

	; Bank is installed: print "32K "
	LD DE,STR_MEM_SIZE_32K
	CALL PRINT_STR
	LD DE,STR_MEM_SPACES_3
	CALL PRINT_STR

	; Determine Role and Usage for installed bank
	; 1. Check if physical bank ID (0x80 + i) is in EXT_BANK_TABLE
	LD A,(MEM_BANK_LOOP_IDX)
	ADD A,080H
	LD E,A				; E = physical bank ID
	LD A,(EXT_BANK_COUNT)
	OR A
	JR Z,PMBR_NOT_IN_EXT
	LD B,A				; B = EXT_BANK_COUNT
	LD C,1				; C = 1-based doc bank index (1..14)
	LD HL,EXT_BANK_TABLE
PMBR_EXT_LOOP:
	LD A,(HL)
	CP E
	JR Z,PMBR_FOUND_IN_EXT
	INC HL
	INC C
	DJNZ PMBR_EXT_LOOP
	JR PMBR_NOT_IN_EXT

PMBR_FOUND_IN_EXT:
	; Bank E is in EXT_BANK_TABLE as Document Buffer Bank C!
	; Check Role: if E < HBIOS_APP_BANK -> RAM Disk (MD0:), else Application
	; Memory
	LD A,(HBIOS_APP_BANK)
	CP E
	JR C,PMBR_EXT_ROLE_APP		; If HBIOS_APP_BANK < E -> App
	JR Z,PMBR_EXT_ROLE_APP		; If HBIOS_APP_BANK == E -> App
	LD DE,STR_ROLE_RAMDISK
	JR PMBR_EXT_PRINT_ROLE
PMBR_EXT_ROLE_APP:
	LD DE,STR_ROLE_APP
PMBR_EXT_PRINT_ROLE:
	CALL PRINT_STR
	LD DE,STR_MEM_SPACES_3
	CALL PRINT_STR

	; Usage: "Active: Doc Buffer Bank " + 2-digit C + "  "
	LD DE,STR_USAGE_DOC_PFX
	CALL PRINT_STR
	LD A,C
	CALL PRINT_2DIGIT_DEC
	LD DE,STR_MEM_SPACES_2
	CALL PRINT_STR
	CALL PRINT_CRLF
	RET

PMBR_NOT_IN_EXT:
	; Check if bank is dedicated to PLUGIN.PRL
	LD A,(MEM_BANK_LOOP_IDX)
	ADD A,080H
	LD E,A
	LD A,(PLUGIN_MGR_LOADED)
	OR A
	JR Z,PMBR_CHK_PLUGINS
	LD A,(PLUGIN_MGR_BANK)
	CP E
	JR NZ,PMBR_CHK_PLUGINS

	; Bank is active PLUGIN.PRL! Determine Role and Usage
	LD BC,STR_USAGE_PLUGIN_MGR
	JR PMBR_PRINT_PLUG_BANK

PMBR_CHK_PLUGINS:
	; Check if bank E is borrowed for loaded plugins
	LD A,(BORROWED_BANKS_CNT)
	OR A
	JR Z,PMBR_CHK_LINE_0
	LD B,A
	LD HL,BORROWED_BANKS_TBL
PMBR_BORROW_LOOP:
	LD A,(HL)
	CP E
	JR Z,PMBR_BORROW_FOUND
	INC HL
	DJNZ PMBR_BORROW_LOOP
	JR PMBR_CHK_LINE_0

PMBR_BORROW_FOUND:
	LD BC,STR_USAGE_FAR_PLUGINS

PMBR_PRINT_PLUG_BANK:
	PUSH BC				; Save usage string pointer
	LD A,(HBIOS_APP_BANK)
	CP E
	JR C,PMBR_PLUG_ROLE_APP
	JR Z,PMBR_PLUG_ROLE_APP
	LD DE,STR_ROLE_RAMDISK
	JR PMBR_PLUG_PRINT_ROLE
PMBR_PLUG_ROLE_APP:
	LD DE,STR_ROLE_APP
PMBR_PLUG_PRINT_ROLE:
	CALL PRINT_STR
	LD DE,STR_MEM_SPACES_3
	CALL PRINT_STR
	POP DE				; DE = usage string pointer
	CALL PRINT_STR
	CALL PRINT_CRLF
	RET

PMBR_CHK_LINE_0:
	; 2. Check if E == LINE_TABLE_BANK (and != 0)
	LD A,(LINE_TABLE_BANK)
	OR A
	JR Z,PMBR_CHK_LINE_1
	CP E
	JR NZ,PMBR_CHK_LINE_1
	LD DE,STR_ROLE_APP
	CALL PRINT_STR
	LD DE,STR_MEM_SPACES_3
	CALL PRINT_STR
	; If LINE_TABLE_BANK_1 != 0, print STR_USAGE_LINE_TABLE_0, else
	; STR_USAGE_LINE_TABLE
	LD A,(LINE_TABLE_BANK_1)
	OR A
	JR NZ,PMBR_LT0_SPLIT
	LD DE,STR_USAGE_LINE_TABLE
	CALL PRINT_STR
	CALL PRINT_CRLF
	RET
PMBR_LT0_SPLIT:
	LD DE,STR_USAGE_LINE_TABLE_0
	CALL PRINT_STR
	CALL PRINT_CRLF
	RET

PMBR_CHK_LINE_1:
	; Check if E == LINE_TABLE_BANK_1 (and != 0)
	LD A,(LINE_TABLE_BANK_1)
	OR A
	JR Z,PMBR_CHK_CPM_USER
	CP E
	JR NZ,PMBR_CHK_CPM_USER
	LD DE,STR_ROLE_APP
	CALL PRINT_STR
	LD DE,STR_MEM_SPACES_3
	CALL PRINT_STR
	LD DE,STR_USAGE_LINE_TABLE_1
	CALL PRINT_STR
	CALL PRINT_CRLF
	RET

PMBR_CHK_CPM_USER:
	; 3. Check if E == CPM_USER_BANK
	LD A,(MEM_BANK_LOOP_IDX)
	ADD A,080H
	LD E,A
	LD A,(CPM_USER_BANK)
	CP E
	JR NZ,PMBR_CHK_HBIOS_BIOS
	; Print TPA role according to OS version
	LD HL,(CPM_VERSION_ID)
	LD A,H
	CP 014H
	JR Z,PMBR_TPA_ZSYS
	LD A,L
	CP 031H
	JR Z,PMBR_TPA_CPM31
	LD DE,STR_ROLE_TPA_CPM2
	JR PMBR_PRINT_TPA_ROLE
PMBR_TPA_ZSYS:
	LD DE,STR_ROLE_TPA_ZSYS
	JR PMBR_PRINT_TPA_ROLE
PMBR_TPA_CPM31:
	LD DE,STR_ROLE_TPA_CPM3
PMBR_PRINT_TPA_ROLE:
	CALL PRINT_STR
	LD DE,STR_MEM_SPACES_3
	CALL PRINT_STR
	LD DE,STR_USAGE_SE_PROG
	CALL PRINT_STR
	CALL PRINT_CRLF
	RET

PMBR_CHK_HBIOS_BIOS:
	; 4. Check if E == HBIOS_BIOS_BANK (e.g. 0x80)
	LD A,(MEM_BANK_LOOP_IDX)
	ADD A,080H
	LD E,A
	LD A,(HBIOS_BIOS_BANK)
	CP E
	JR NZ,PMBR_CHK_RAMDISK_PRESERVED
	LD DE,STR_ROLE_HBIOS
	CALL PRINT_STR
	LD DE,STR_MEM_SPACES_3
	CALL PRINT_STR
	LD DE,STR_USAGE_HBIOS
	CALL PRINT_STR
	CALL PRINT_CRLF
	RET

PMBR_CHK_RAMDISK_PRESERVED:
	; 5. Check if E < HBIOS_APP_BANK (and not in EXT -> preserved RAM disk)
	LD A,(MEM_BANK_LOOP_IDX)
	ADD A,080H
	LD E,A
	LD A,(HBIOS_APP_BANK)
	CP E
	JR C,PMBR_CHK_OS_BANK		; If HBIOS_APP_BANK < E -> not RAM disk
	JR Z,PMBR_CHK_OS_BANK		; If HBIOS_APP_BANK == E -> not RAM disk
	; E < HBIOS_APP_BANK: preserved RAM disk
	LD DE,STR_ROLE_RAMDISK
	CALL PRINT_STR
	LD DE,STR_MEM_SPACES_3
	CALL PRINT_STR
	LD DE,STR_USAGE_RAMDISK_PRESERVED
	CALL PRINT_STR
	CALL PRINT_CRLF
	RET

PMBR_CHK_OS_BANK:
	; 6. Check if E > CPM_USER_BANK (e.g. 0x8F)
	LD A,(MEM_BANK_LOOP_IDX)
	ADD A,080H
	LD E,A
	LD A,(CPM_USER_BANK)
	CP E
	JR NC,PMBR_FREE_APP		; If CPM_USER_BANK >= E -> free app
	; E > CPM_USER_BANK:
	LD DE,STR_ROLE_OS
	CALL PRINT_STR
	LD DE,STR_MEM_SPACES_3
	CALL PRINT_STR
	LD DE,STR_USAGE_OS
	CALL PRINT_STR
	CALL PRINT_CRLF
	RET

PMBR_FREE_APP:
	; Check if this is CP/M 3.x Buffer Bank (CPM_USER_BANK - 1 = 0x8C)
	LD A,(CPM_VERSION_ID)
	CP 030H
	JR C,PMBR_FREE_ACTUAL
	LD A,(CPM_USER_BANK)
	DEC A
	CP E
	JR NZ,PMBR_FREE_ACTUAL
	; Bank is CP/M 3 Buffers!
	LD DE,STR_ROLE_OS
	CALL PRINT_STR
	LD DE,STR_MEM_SPACES_3
	CALL PRINT_STR
	LD DE,STR_USAGE_CPM3_BUFS
	CALL PRINT_STR
	CALL PRINT_CRLF
	RET

PMBR_FREE_ACTUAL:
	; 7. Free / Unallocated Application Memory
	LD DE,STR_ROLE_APP
	CALL PRINT_STR
	LD DE,STR_MEM_SPACES_3
	CALL PRINT_STR
	LD DE,STR_USAGE_FREE
	CALL PRINT_STR
	CALL PRINT_CRLF
	RET

PMBR_NOT_INSTALLED:
	; Bank not installed: Size = " -- ", Role = Not Installed, Usage = Not
	; Present
	LD DE,STR_MEM_SIZE_NONE
	CALL PRINT_STR
	LD DE,STR_MEM_SPACES_3
	CALL PRINT_STR
	LD DE,STR_ROLE_NOT_INST
	CALL PRINT_STR
	LD DE,STR_MEM_SPACES_3
	CALL PRINT_STR
	LD DE,STR_USAGE_NOT_PRES
	CALL PRINT_STR
	CALL PRINT_CRLF
	RET

;------------------------------------------------------------------------------
; PRINT_2DIGIT_DEC: Print 2-digit decimal number (00..99) in register A
;
; Purpose:
;   Prints unsigned value in A as two decimal digits with leading zero
;   if < 10.
;
; Call Usage / Protocol:
;   Called via CALL for line numbers, bank indices, and table counts.
;
; Inputs:
;   A = Unsigned integer (0..99).
;
; Outputs:
;   Two ASCII digits emitted via PUTC.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
PRINT_2DIGIT_DEC:
	PUSH AF
	CP 10
	JR NC,P2D_TEN_PLUS
	LD A,'0'
	CALL PUTC
	POP AF
	ADD A,'0'
	CALL PUTC
	RET
P2D_TEN_PLUS:
	LD A,'1'
	CALL PUTC
	POP AF
	SUB 10
	ADD A,'0'
	CALL PUTC
	RET

;------------------------------------------------------------------------------
; PRINT_CRLF: Output carriage return and line feed to console
;
; Purpose:
;   Emits ASCII CR (0x0D) followed by LF (0x0A) via PUTC.
;
; Call Usage / Protocol:
;   Called via CALL across table and screen formatting routines.
;
; Inputs:
;   None
;
; Outputs:
;   CRLF sequence emitted to console.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
PRINT_CRLF:
	LD A,13
	CALL PUTC
	LD A,10
	CALL PUTC
	RET





;------------------------------------------------------------------------------
; PRINT_DEC_BYTE: Print 8-bit unsigned integer in decimal (0..255)
;
; Purpose:
;   Decomposes byte in register A into hundreds, tens, and units digits,
;   suppressing leading zeroes.
;
; Call Usage / Protocol:
;   Called via CALL for version numbers, line counts, and memory sizes.
;
; Inputs:
;   A = Unsigned 8-bit integer (0..255).
;
; Outputs:
;   1 to 3 decimal digits emitted via PUTC.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
PRINT_DEC_BYTE:
	PUSH AF
	PUSH BC
	PUSH DE
	LD E,A				; E = input value

	; Check hundreds (100)
	LD C,0
HUNDREDS_LOOP:
	LD A,E
	CP 100
	JR C,DONE_HUNDREDS
	SUB 100
	LD E,A
	INC C
	JR HUNDREDS_LOOP

DONE_HUNDREDS:
	; Check tens (10)
	LD B,0
TENS_LOOP:
	LD A,E
	CP 10
	JR C,DONE_TENS
	SUB 10
	LD E,A
	INC B
	JR TENS_LOOP

DONE_TENS:
	; Print Hundreds if non-zero
	LD A,C
	OR A
	JR Z,CHECK_TENS_OUTPUT
	ADD A,'0'
	CALL PUTC
	; If hundreds was printed, tens MUST be printed even if 0
	LD A,B
	ADD A,'0'
	CALL PUTC
	JR PRINT_ONES_DIGIT

CHECK_TENS_OUTPUT:
	; Print Tens if non-zero
	LD A,B
	OR A
	JR Z,PRINT_ONES_DIGIT
	ADD A,'0'
	CALL PUTC

PRINT_ONES_DIGIT:
	; Print Units (E)
	LD A,E
	ADD A,'0'
	CALL PUTC

	POP DE
	POP BC
	POP AF
	RET

;------------------------------------------------------------------------------
; PRINT_HEX_BYTE: Print 8-bit byte as two hexadecimal digits
;
; Purpose:
;   Outputs high nibble and low nibble of register A as ASCII hex digits.
;
; Call Usage / Protocol:
;   Called via CALL for bank numbers, memory addresses, and debug dumps.
;
; Inputs:
;   A = 8-bit value to display.
;
; Outputs:
;   Two hex digits ('0'..'9', 'A'..'F') emitted to console.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
PRINT_HEX_BYTE:
	PUSH AF
	RRA
	RRA
	RRA
	RRA
	CALL PRINT_NIBBLE
	POP AF

;------------------------------------------------------------------------------
; PRINT_NIBBLE: Print lower 4 bits of register A as single hexadecimal digit
;
; Purpose:
;   Masks lower 4 bits of A and converts to ASCII hex ('0'..'9', 'A'..'F').
;
; Call Usage / Protocol:
;   Called via CALL from PRINT_HEX_BYTE.
;
; Inputs:
;   A = Lower 4 bits contain nibble to display (0x0..0xF).
;
; Outputs:
;   Single ASCII digit emitted via PUTC.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
PRINT_NIBBLE:
	AND 0FH
	CP 10
	JR C,PRINT_DIGIT
	ADD A,'A'-10
	CALL PUTC
	RET

;------------------------------------------------------------------------------
; PRINT_DIGIT: Print single decimal digit (0..9) in register A
;
; Purpose:
;   Adds ASCII '0' to value in register A and transmits via PUTC.
;
; Call Usage / Protocol:
;   Called via CALL from number formatting routines.
;
; Inputs:
;   A = Integer value (0..9).
;
; Outputs:
;   Single ASCII digit emitted to console.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
PRINT_DIGIT:
	ADD A,'0'
	CALL PUTC
	RET

INCLUDE "core/block.asm"

INCLUDE "core/ui_render.asm"

INCLUDE "core/buffer.asm"

INCLUDE "core/editor.asm"

INCLUDE "core/config.asm"

INCLUDE "core/beautify.asm"

INCLUDE "core/ui_browser.asm"

INCLUDE "core/plugin_mgr.asm"

;------------------------------------------------------------------------------
; Variables & Stack Area
;------------------------------------------------------------------------------
SAVED_SP:	DW	0
; 1 if " File not found" inline message is visible
SHOWING_FNF_MSG:	DB	0
UI_CUR_ROW:	DB	0	; Current screen row tracking for Open/Save UI
BIOS_CONST_VEC:	DW	0
BIOS_CONIN_VEC:	DW	0
BIOS_CONOUT_VEC:	DW	0
CPM_USER_BANK:	DB	0
TARGET_RAM_BANK:	DB	0
RAM_BANK_COUNT:	DB	0
ROM_BANK_COUNT:	DB	0
HBIOS_PRESENT:		DB	0
HBIOS_BIOS_BANK:	DB	080H
HBIOS_APP_BANK:		DB	089H
HBIOS_APP_COUNT:	DB	0
HBIOS_VER_MAJ:		DB	0
HBIOS_VER_MIN:		DB	0
HBIOS_VER_PATCH:	DB	0
CPM_VERSION_ID:		DW	0
MEM_BANK_LOOP_IDX:	DB	0

SCREEN_MODE:	DB	MODE_120X40	; Default to 120x40
ACTIVE_ROWS:	DB	40		; Default 40 rows
ACTIVE_COLS:	DB	120		; Default 120 cols
; Horizontal viewport left column offset (0..1000)
VIEW_LEFT_COL:	DW	0
; Cached right column bound (VIEW_LEFT_COL + ACTIVE_COLS)
VIEW_RIGHT_COL:	DW	120

; Screen cursor coordinates use "row" (0..ACTIVE_ROWS-2) internally for terminal
; positioning (LOCATE_CURSOR: Screen Row = CUR_DOC_ROW - TOP_DOC_ROW + 1).
; Document line indices in buffer/file use "line" (0..DOC_TOTAL_LINES-1) and are
; rendered on the status line as "Line <cur>/<total>".
CUR_DOC_ROW:	DW	0		; 16-bit document line index (0..3583)
CUR_COL:	DW	0	; 16-bit character byte index in line (0..1000)
TARGET_COL:	DW	0		; Sticky visual column (0..1000)
TOP_DOC_ROW:	DW	0	; 16-bit top visible document line on screen
; 16-bit total document lines count (default 1 empty line)
DOC_TOTAL_LINES:	DW	1
HAS_FILE_ARG:	DB	0
CMDLINE_HAS_DRIVE:	DB	0
; 16-bit line number from command line (0 = start)
CMDLINE_GOTO_LINE:	DW	0
; 16-bit line number from open file UI (0 = start)
OPEN_GOTO_LINE:		DW	0
GOTO_LINE_BUF:	DS	8
SEARCH_BUF:		DS	65
SEARCH_LEN:		DB	0
SEARCH_CASE_SENSITIVE:	DB	1	; Default 1 = Exact (case-sensitive)
; 1 if pattern was ever found during session
SEARCH_EVER_FOUND:	DB	0
SEARCH_DIRECTION:	DB	0		; 0 = Forward, 1 = Backward
; Saved column during interactive replace
REPLACE_MATCH_COL:	DW	0
PREV_START_ROW_TEMP:	DW	0	; Saved row before Find Next/Prev
PREV_START_COL_TEMP:	DW	0	; Saved col before Find Next/Prev
REPLACE_BUF:		DS	65
REPLACE_LEN:		DB	0
REPLACE_ALL_MODE:	DB	0
REPLACE_COUNT:		DW	0
SEARCH_START_ROW:	DW	0
SEARCH_START_COL:	DW	0
SEARCH_WRAPPED:		DB	0
SEARCH_FIRST_LINE:	DB	0
SEARCH_INPUT_BUF:	DS	65
REPLACE_PTR_TEMP:	DW	0
REPLACE_DELTA_TEMP:	DB	0
IN_EDITOR_MODE:	DB	0
IS_SPLASH_SCREEN:	DB	0
STATUS_OOM_FLAG:	DB	0
; 1 if file was truncated on load (Save protected)
FILE_IS_TRUNCATED:	DB	0
; Total 128-byte records computed by BDOS 35
FILE_TOTAL_RECORDS:	DW	0
FILE_RECORDS_HI:	DB	0	; High byte of 24-bit record count
SAVE_FORMAT:	DB	FMT_CPM		; Default format is CP/M (CR/LF)
IS_SAVE_UI:		DB	0	; 1 if currently in Save File Screen
; 1 if currently in Block Insert File Screen
IS_BLOCK_INSERT_UI:	DB	0
; 1 if currently in Block Save File Screen
IS_BLOCK_SAVE_UI:	DB	0
PREV_DOC_IS_FAT:	DB	0	; Saved DOC_IS_FAT during Open UI
IS_PLUGIN_LOAD_UI:	DB	0	; 1 if in Plugin Load Screen
IS_LOADING_FILE:	DB	0		; 1 if currently loading file
IS_SAVING_FILE:		DB	0		; 1 if currently saving file
; Progress interval down-counter (100 lines)
LOAD_PROGRESS_COUNT:	DB	100
; Lines read counter for loading status bar
LOAD_PROGRESS_LINES:	DW	0
SAVED_HAS_FILE_ARG:	DB	0	; Saved HAS_FILE_ARG during block insert
; 1 if current line of inserted file had chars
INSERT_LINE_HAD_CHARS:	DB	0
; 1 if currently in Save Changes Exit Prompt
IS_EXIT_PROMPT:		DB	0
REPLACE_ACTIVE:		DB	0	; 1 during active Search & Replace loop
; 50-col Msg2 buffer for Replace Done popup
REPLACE_DONE_POPUP_MSG2: DS	51
BLOCK_POPUP_LINE4_BUF:	DS	51	; 50-col Line 4 buffer for Block modal
INSERT_FCB:		DS	36	; Dedicated FCB for block insert file
INSERT_CUR_LEN:		DW	0	; Streaming insert current line length
INSERT_NEW_CUR_COL:	DW	0	; Cursor column position after insert
; 1 while processing line 1 of inserted file
INSERT_IS_FIRST_LINE:	DB	0
INSERT_ORIG_START_ROW:	DW	0		; Block start row backup
INSERT_ORIG_START_COL:	DW	0		; Block start col backup
SEEN_CR:	DB	0		; Line format auto-detection state
CHAR_INSERT_TEMP:	DB	0
CSI_DIGIT_PREFIX:	DB	0
CSI_MODIFIER:		DB	0
JOIN_COL_SAVED:	DW	0
JOIN_DOC_LINE:	DW	0
DEL_BLK_CUR_LINE:	DW	0
COPY_K_LINES:	DW	0
COPY_SRC_ROW:	DW	0
COPY_BLK_LEN:	DW	0
COPY_TAIL_LEN:	DB	0
DEST_LINE_LEN:	DW	0
COPY_BLK_BUF:	DS	1024
COPY_TAIL_BUF:	DS	256
COPY_SLOTS_BUF:	DS	256
MOVE_DEST_ROW:		DW	0
MOVE_DEST_COL:		DW	0
MOVE_SRC_START_ROW:	DW	0
MOVE_SRC_START_COL:	DW	0
MOVE_SRC_END_ROW:	DW	0
MOVE_SRC_END_COL:	DW	0
MOVE_DEST_IS_BEFORE:	DB	0
BLOCK_ACTIVE:	DB	0	; 0 = inactive, 1 = selecting, 2 = solidified
; 16-bit document row where block started
BLOCK_ANCHOR_ROW:	DW	0
; 16-bit character column where block started
BLOCK_ANCHOR_COL:	DW	0
BLOCK_START_ROW:	DW	0		; Normalized start row
BLOCK_START_COL:	DW	0		; Normalized start col
BLOCK_END_ROW:	DW	0		; Normalized end row
BLOCK_END_COL:	DW	0		; Normalized end col

LINE_BLK_ACTIVE:	DB	0		; 1 if rendered line is in block
LINE_BLK_START:	DW	0	; Start character column of highlight on line
LINE_BLK_END:	DW	0	; End character column of highlight on line
; 1 if terminal currently has inverse video ON
LINE_IN_INVERSE:	DB	0

NEED_SCREEN_RENDER:	DB	0	; 1 if full screen redraw pending
NEED_LINE_RENDER:	DB	0	; 1 if current line redraw pending
; 1 if status bar redraw / cursor restore pending
NEED_STATUS_RENDER:	DB	0
; 1 = Insert mode (default), 0 = Overwrite mode
INSERT_MODE:		DB	1

; 16-bit doc row index at LINE_STORAGE[0]
CACHE_START_ROW:	DW	0
CACHE_DIRTY:	DB	0	; 1 if local cache has unsaved modifications
; 1 byte per local cache line (0=clean, 1=dirty)
CACHE_LINE_DIRTY:	DS	CACHE_SIZE_LINES
DOC_MODIFIED:	DB	0	; 1 if document has unsaved modifications
CONFIRM_ACTION:	DB	0		; 0=Exit, 1=Close, 2=New
EXT_BANK_COUNT:	DB	0	; Number of available far RAM banks (up to 14)
EXT_BANK_TABLE:	DS	14		; Table of far RAM bank IDs
; Far RAM Bank dedicated to 16K line slots table (Bank 0)
LINE_TABLE_BANK:	DB	0
; Far RAM Bank dedicated to 16K..32K line slots table (Bank 1)
LINE_TABLE_BANK_1:	DB	0
CFG_LINES_MODE:		DB	0	; 0 = 16K lines (default), 1 = 32K lines
; Dynamic max document lines (16384 or 32768)
MAX_DOC_LINES_LIMIT:	DW	MAX_DOC_LINES_16K
; 2-byte transfer buffer for GET/SET_LINE_SLOT
LINE_SLOT_TEMP:		DW	0
; Far RAM source line for block slot shifts
SLOT_SHIFT_SRC:		DW	0
; Far RAM dest line for block slot shifts
SLOT_SHIFT_DEST:	DW	0
SLOT_SHIFT_REM:		DW	0		; Remaining lines to shift
; Current chunk size in lines (up to 128)
SLOT_SHIFT_CHUNK:	DW	0
; Current chunk size in bytes (up to 256)
SLOT_SHIFT_BYTES:	DW	0
; Temporary K for WRITE_LINE_SLOTS_FROM_RAM
WLSR_K:			DW	0
; Temporary Source for WRITE_LINE_SLOTS_FROM_RAM
WLSR_SRC:		DW	0
; Temporary Dest for WRITE_LINE_SLOTS_FROM_RAM
WLSR_DEST:		DW	0

FAR_DEST_BANK:	DB	0
FAR_SRC_BANK:	DB	0
FAR_DEST_ADDR:	DW	0
FAR_SRC_ADDR:	DW	0
FAR_LOCAL_ADDR:	DW	0
SLOT_TEMP:	DB	0
NEXT_FRESH_SLOT:	DW	0
FIRST_FREE_SLOT:	DW	0FFFFH
DEC_WORD_BUF:	DS	6	; Buffer for PRINT_DEC_WORD (5 digits + null)

; 1 if $$$SE$$$.SWP is active, 0 if RAM-only
SWAP_ACTIVE:		DB	0
SWAP_FCB:		DS	36		; FCB for temporary swap file
; Virtual page number (0..255) resident in Bank 0..11
BANK_PAGE_TABLE:	DS	12
; 1 if bank has unsaved modifications, 0 if clean
BANK_DIRTY_TABLE:	DS	12
; Round-robin victim pointer (1..11; Bank 0 is pinned)
NEXT_VICTIM_BANK:	DB	1
; 256 bits: 1 bit per page (1 if written to swap)
PAGE_ON_DISK_BITMAP:	DS	32
SWAP_PAGE_TEMP:		DB	0		; Target virtual page number
SWAP_BANK_TEMP:		DB	0		; Target bank index (0..11)
SWAP_BNK_ID:		DB	0		; Target Far RAM bank ID
SWAP_PAGE_OLD:		DB	0		; Evicted virtual page number
SWAP_PAGE_NEW:		DB	0		; Fetched virtual page number

FAR_SRC_LINE_PTR:	DW	0
FAR_DEST_LINE_PTR:	DW	0
FAR_HEAD_SLOT:		DW	0
FAR_CUR_SLOT:		DW	0
FAR_OLD_NEXT_SLOT:	DW	0
FAR_NEW_NEXT_SLOT:	DW	0
FAR_READ_MAX_BYTES:	DW	0
LOAD_HEAD_SLOT:		DW	0
LOAD_CUR_SLOT:		DW	0
LOAD_STRIDE_OFF:	DB	2
SAVE_NEXT_SLOT:		DW	0
FLC_COUNT:		DB	0


; Document row checked out in ACTIVE_LINE_BUF
ACTIVE_LINE_ROW:	DW	0FFFFH
; 1 if ACTIVE_LINE_BUF has unsaved modifications
ACTIVE_LINE_DIRTY:	DB	0
REND_LINE_PTR:		DW	0
REND_VIS_COL:		DW	0
REND_CHAR_IDX:		DW	0
REND_TAB_SPACES:	DB	0
ACT_VIS_ACC:		DW	0

; 128-byte scratch buffer for physical Far RAM transfers
FAR_IO_BUF:		DS	128
; 256-byte scratch line for local operations
LOAD_LINE_TEMP:		DS	256
SPLIT_LINE_TEMP:	DS	1024	; 1024-byte scratch line for line splits
; 16-bit byte length of line in ACTIVE_LINE_BUF
ACTIVE_LINE_LEN:	DW	0
; 1024-byte dynamic workspace for active line
ACTIVE_LINE_BUF:	DS	1024
CUR_DMA_PTR:	DW	0
DMA_BYTES_LEFT:	DB	0
SAVE_RECORD_NUM: DW	0


WORK_FCB:	DS	36
DIR_TEMP_FCB:	DS	36

; Active directory drive (1=A:, 2=B:, 3=C:, etc.)
CURRENT_DIR_DRIVE:	DB	0
CURRENT_DIR_USER:	DB	0	; Active directory user area (0..15)
ORIG_CPM_USER:		DB	0	; CP/M user area on entry (0..15)
; User area for currently loaded document (0..15)
DOC_USER_NUM:		DB	0
; User area for pending WORK_FCB operation (0..15)
WORK_FCB_USER:		DB	0
; User area for Block Insert / Block Save (0..15)
BLOCK_IO_USER:		DB	0
PREFIX_DRIVE:		DB	0	; Parsed prefix drive (1..16 or 0)
PREFIX_USER:		DB	0FFH	; Parsed prefix user (0..15 or 0xFF)
; Consolidated transient CP/M File Control Block (36 bytes)
; Shared across sequential operations: dir search, raw disk, config, ramdrv
SHARED_TEMP_FCB:	DS	36
DIR_SEARCH_FCB		EQU	SHARED_TEMP_FCB
RAW_TEST_FCB		EQU	SHARED_TEMP_FCB
CFG_FCB			EQU	SHARED_TEMP_FCB
COM_PROBE_FCB		EQU	SHARED_TEMP_FCB
HIB_FCB			EQU	SHARED_TEMP_FCB
DIR_FILE_COUNT:	DB	0
DIR_PAGE_INDEX:	DB	0
DIR_PAGE_COUNT:	DB	0
DIR_START_FILE:	DB	0
DIR_COL_COUNT:		DB	0
DIR_COLS_PER_ROW:	DB	5
DIR_COL_WIDTH:		DB	15
DIR_PAGE_CAPACITY:	DB	60
DIR_LEFT_PAD:		DB	2
DIR_TOP_PAD_COUNT:	DB	0
DIR_TEMP_ENTRY:		DS	16
INPUT_BUF_LEN:		DB	0
INPUT_CURSOR_POS:	DB	0
INPUT_CHAR_TEMP:	DB	0
INLINE_MSG_LEN:		DB	16
INPUT_FILENAME_BUF:	DS	32
; 11-byte FCB wildcard pattern (8 name + 3 ext)
DIR_FILTER_FCB:		DB	"???????????"
; Display string for active filter (null-terminated)
DIR_FILTER_STR:		DB	"*.*",0,0,0,0,0,0,0,0,0
; 0 = *.* (all files), 1 = custom filter active
DIR_FILTER_ACTIVE:	DB	0

; Transient FCBs and buffers moved to SHARED_TEMP_FCB and LINE_STORAGE
; Active CP/M default drive (0=A, 1=B, etc.)
CURRENT_DEFAULT_DRIVE:	DB	0
; Drive where config was loaded from (0xFF = none)
CONFIG_SOURCE_DRIVE:	DB	0FFH
; 0=none/default, 1=loaded local, 2=loaded program, 3=saved local, 4=save error
CONFIG_STATUS_FLAG:	DB	0
; Number of top padding rows on splash screen
SPLASH_TOP_PAD_COUNT:	DB	0
; Number of top padding rows on memory screen
MEM_TOP_PAD_COUNT:	DB	0
; Number of top padding rows on about screen
ABOUT_TOP_PAD_COUNT:	DB	0
; Number of top padding rows on config screen
CONFIG_TOP_PAD_COUNT:	DB	0
CFG_RAMDRIVE_FLAG:	DB	0	; 0=protected, 1=enabled, 2=hibernate
CFG_TAB_WIDTH:		DB	8		; Tab width: 4 or 8 (default 8)
CFG_TAB_MASK:		DB	7		; Tab mask: 3 or 7 (default 7)
; 0=not hibernated, 1=hibernated to RAMDRV.IMG
RAMDRIVE_IS_HIBERNATED:	DB	0
; Detected RomWBW RAM drive (0=A, 1=B, ..., 0xFF=none)
RAMDRIVE_DRIVE_NUM:	DB	0FFH
; Character representation ('A', 'B', etc. or '?')
RAMDRIVE_DRIVE_CHAR:	DB	'?'

INCLUDE "core/plugin_tramp.asm"

;==============================================================================
; Runtime Uninitialized BSS (Not emitted into SE.COM on disk)
; Allocated in RAM immediately following LOCAL_STACK (Page-Aligned)
;==============================================================================
ALIGN 256
BSS_START:

; 40 lines x 128 bytes stride local working cache in TPA (5,120 bytes)
LINE_STORAGE_SIZE EQU	CACHE_SIZE_LINES * 128
LINE_STORAGE	EQU	BSS_START

; Overlay directory entries buffer onto LINE_STORAGE (mutually exclusive with
; editor)
DIR_NAMES_BUF	EQU	LINE_STORAGE

; Overlay 4KB TPA plugin execution slot onto LINE_STORAGE (0 extra bytes)
PLUGIN_TPA_SLOT	EQU	LINE_STORAGE

; Overlay transient config and sector buffers onto LINE_STORAGE beyond plugin
CFG_IO_BUF		EQU	LINE_STORAGE + 4096
RAW_SECTOR_BUF		EQU	LINE_STORAGE + 4096 + 256

; Bounce buffer for Far RAM Line Table block shifts (256 bytes)
; Overlaid on upper half of SPLIT_LINE_TEMP to keep BSS strictly below CCP
LINE_SHIFT_BUF_SIZE EQU	256
LINE_SHIFT_BUF	EQU	SPLIT_LINE_TEMP + 512

; Dedicated bounce buffer for swap file BDOS random I/O (128 bytes)
; Overlaid on upper half of SPLIT_LINE_TEMP to keep BSS strictly below CCP
SWAP_IO_BUF_SIZE EQU	128
SWAP_IO_BUF	EQU	SPLIT_LINE_TEMP + 768

; Scratch buffers for Tier 2 progress modal target filename
; Overlaid on top 128 bytes of SPLIT_LINE_TEMP to keep binary within page
PROGRESS_FILENAME_STR	EQU	SPLIT_LINE_TEMP + 896
STR_POPUP_PROGRESS_FILE	EQU	SPLIT_LINE_TEMP + 928
FNF_POPUP_MSG1		EQU	SPLIT_LINE_TEMP + 928

BSS_END		EQU	LINE_STORAGE + LINE_STORAGE_SIZE
