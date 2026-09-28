;==============================================================================
; SE.COM: CP/M Full-Screen Text Editor for RomWBW / RC2014
; Target: Z80 CPU, CP/M 2.2+, RomWBW HBIOS 512K Extended RAM, Minicom/VT100
;==============================================================================

	ORG	$0100

;------------------------------------------------------------------------------
; Constants & BDOS Vectors
;------------------------------------------------------------------------------
BDOS_ENTRY	EQU	$0005
DEFAULT_FCB	EQU	$005C
DEFAULT_DMA	EQU	$0080
CMD_LEN		EQU	$0080
CMD_TAIL	EQU	$0081

MAX_LINE_STRIDE	EQU	128		; 128 bytes stride per line buffer in local cache
MAX_LINE_CHARS	EQU	1000		; Maximum visual characters per line in all modes
MAX_INPUT_LINE_CHARS EQU 1000		; Interactive typing limit (up to 1,000 chars)
MAX_CACHE_LINE_CHARS EQU 250		; Limit for local 256-byte scratch line buffers
MAX_ACTIVE_LINE_STRIDE EQU 1024		; 1024 bytes dynamic workspace for active line
MAX_ACTIVE_PAYLOAD EQU	1022		; Max characters in active line payload
MAX_ACTIVE_PAYLOAD_LO EQU 254		; Low byte of 1022
MAX_ACTIVE_PAYLOAD_HI EQU 3		; High byte of 1022
FAR_SLOT_SIZE	EQU	128		; 128 bytes stride per Far-RAM physical slot
FAR_SLOT_PAYLOAD EQU	126		; 126 bytes text payload per Far-RAM slot
SLOT_TERM	EQU	0FFFFH		; 16-bit terminal slot marker in Far-RAM
MAX_COPY_LINE_CHARS EQU	120		; Single-line block copy capacity limit
MAX_FAR_BANKS	EQU	12		; Up to 12 extended 32KB RAM banks for text slots (384 KB)
CACHE_SIZE_LINES EQU	40		; 40 lines in local working cache (5,120 bytes)
MAX_DOC_LINES_16K EQU	16384		; 32KB Far RAM Line Table (16,384 lines * 2 bytes)
MAX_DOC_LINES_32K EQU	32768		; 64KB Far RAM Line Table (32,768 lines * 2 bytes)
MAX_DOC_LINES	EQU	32768		; Absolute ceiling limit for line indices
MAX_VIRTUAL_SLOTS EQU	65534		; Up to 65,534 128-byte virtual slots (~8.3 MB)

KEY_CTRL_B	EQU	2		; Toggle Block Highlighting
KEY_CTRL_C	EQU	3
KEY_CTRL_X	EQU	24		; Move solidified block to cursor
KEY_CTRL_Q	EQU	17
KEY_CTRL_W	EQU	23		; Close file to splash
KEY_CTRL_S	EQU	19
KEY_CTRL_O	EQU	15		; Open File Screen
KEY_CTRL_A	EQU	1		; Start of line (Home)
KEY_CTRL_D	EQU	4		; Cursor Right
KEY_CTRL_E	EQU	5		; End of line (End)
KEY_CTRL_G	EQU	7		; Delete character at cursor

ACTION_EXIT	EQU	0		; Confirmation action: Exit to CP/M
ACTION_CLOSE	EQU	1		; Confirmation action: Close document to splash
ACTION_NEW	EQU	2		; Confirmation action: Start new blank document
ACTION_OPEN	EQU	3		; Confirmation action: Open File Screen
KEY_CTRL_K	EQU	11		; Show Editor Mode Keys Screen
KEY_CTRL_F	EQU	6		; Find in editor / Toggle endings in save
KEY_CTRL_R	EQU	18		; Search & Replace
KEY_CTRL_N	EQU	14		; Find Next
KEY_CTRL_P	EQU	16		; Context-Aware Plugin Pop-up
KEY_CTRL_I	EQU	9		; Tab / Toggle case sensitivity in prompt
KEY_CTRL_U	EQU	21		; Page Up
KEY_CTRL_V	EQU	22		; Page Down
KEY_CTRL_L	EQU	12		; Goto Line Number
KEY_CTRL_Y	EQU	25		; Beautify Block (if active) or Whole File
KEY_CTRL_Z	EQU	26		; Open Plugin Manager Screen

; Context-Aware Plugin Screen IDs
PLUG_CTX_EDITOR		EQU	0
PLUG_CTX_SPLASH		EQU	1
PLUG_CTX_CONFIG		EQU	2
PLUG_CTX_MEM_INFO	EQU	3
PLUG_CTX_PLUGIN_MGR	EQU	4
PLUG_CTX_HELP		EQU	5
PLUG_CTX_ABOUT		EQU	6
KEY_BACKSPACE	EQU	8
KEY_TAB		EQU	9
KEY_ENTER	EQU	13
KEY_ESC		EQU	27
ESC_TIMEOUT_LOOPS EQU	5000		; VT100 escape debounce timeout loops (~15-20ms)
KEY_DEL		EQU	127

SEARCH_BUF_MAX	EQU	64
FIND_POPUP_FIELD_LEN	EQU	29

; Line ending modes
FMT_CPM		EQU	0		; CR/LF (0x0D, 0x0A)
FMT_LINUX	EQU	1		; LF only (0x0A)

; Screen Size Modes
MODE_120X40	EQU	0		; Modern 120 cols x 40 rows (Default)
MODE_80X24	EQU	1		; Classic 80 cols x 24 rows

; RAM Drive Modes
RAMDRV_MODE_PROTECTED	EQU	0	; Preserve RAM disk (banks 0x81..0x88 safe)
RAMDRV_MODE_ENABLED	EQU	1	; Raw overwrite for maximum RAM buffer
RAMDRV_MODE_HIBERNATE	EQU	2	; Automatic dump to RAMDRV.IMG & restore on exit

; Plugin Subsystem Modes
PLUGIN_MODE_DISABLED	EQU	0	; Never load (disabled by user / low RAM)
PLUGIN_MODE_AUTOLOAD	EQU	1	; Autoload PLUGIN.PRL into Far RAM at boot
PLUGIN_MODE_ONDEMAND	EQU	2	; Load PLUGIN.PRL on demand when used

RAMDRV_START_BANK	EQU	081H	; RomWBW MD0:0 starts at bank 0x81
RAMDRV_END_BANK		EQU	088H	; RomWBW MD0:0 ends at bank 0x88 (8 banks, 256KB)

;------------------------------------------------------------------------------
; Main Entry Point
;------------------------------------------------------------------------------
START:
	LD	(SAVED_SP),SP
	LD	SP,LOCAL_STACK

	; Query initial CP/M Version via BDOS 12 (Get Version Number)
	LD	C,12
	CALL	BDOS_ENTRY
	LD	(CPM_VERSION_ID),HL

	; Query initial CP/M user area via BDOS 32 (Get User Number, E=0xFF)
	LD	E,0FFH
	LD	C,32
	CALL	BDOS_ENTRY
	LD	(ORIG_CPM_USER),A
	LD	(CURRENT_DIR_USER),A
	LD	(DOC_USER_NUM),A
	LD	(WORK_FCB_USER),A
	LD	(BLOCK_IO_USER),A

	; Query initial CP/M drive via BDOS 25 (Return Current Disk)
	LD	C,25
	CALL	BDOS_ENTRY
	INC	A			; 0..15 -> 1..16
	LD	(CURRENT_DIR_DRIVE),A
	ADD	A,'A'-1
	LD	(STR_DIR_DRIVE_CHAR),A
	LD	(STR_SAVE_DRIVE_CHAR),A

	; Initialize Direct BIOS Console Vectors
	CALL	INIT_BIOS_JUMPS

	; Initialize Screen Geometry to Default (120x40)
	CALL	SET_MODE_120X40

	; Detect RomWBW RAM drive letter (0=A, 1=B, ..., 0xFF=none)
	CALL	DETECT_RAMDRIVE_LETTER

	; Check if filename was provided in FCB1 (populates WORK_FCB and HAS_FILE_ARG)
	CALL	CHECK_COMMAND_LINE

	; Load configuration from SE.CFG if present (local dir first, then program drive)
	CALL	LOAD_CONFIG

	; Safety check: Prevent hibernation or raw overwrite if target file
	; or active drive is on RAM drive
	CALL	VALIDATE_RAMDRIVE_SAFETY

	; If RAM drive mode is HIBERNATE, dump RAM drive to RAMDRV.IMG
	; before initializing buffer
	LD	A,(CFG_RAMDRIVE_FLAG)
	CP	RAMDRV_MODE_HIBERNATE
	CALL	Z,HIBERNATE_RAMDRIVE

	; Initialize Terminal (Clear Screen & Home)
	CALL	TERM_INIT

	; Query RomWBW User Bank and Initialize Far RAM Banks
	CALL	BUFFER_INIT

	; Initialize search state to defaults (Case-sensitive = 1)
	LD	A,1
	LD	(SEARCH_CASE_SENSITIVE),A
	XOR	A
	LD	(SEARCH_LEN),A
	LD	(REPLACE_LEN),A
	LD	(DOC_MODIFIED),A
	LD	(IN_EDITOR_MODE),A
	LD	(IS_SPLASH_SCREEN),A
	LD	(STATUS_OOM_FLAG),A
	LD	(CONFIRM_ACTION),A
	LD	(DOC_IS_FAT),A
	LD	(PLUGIN_FAR_BANK),A
	LD	(PLUGIN_LOAD_COUNT),A
	DEC	A
	LD	(FAT_DOC_UNIT),A
	XOR	A
	LD	HL,0
	LD	(PLUGIN_STATUS_MSG_PTR),HL
	CALL	INIT_PLUGIN_REGISTRY
	CALL	AUTO_LOAD_PLUGIN_MGR

	; Initialize directory drive from default disk or FCB
	CALL	INIT_DIR_DRIVE

	; If file argument was given, load file and go straight to editor
	LD	A,(HAS_FILE_ARG)
	OR	A
	JR	NZ,DO_AUTO_LOAD

	; Otherwise show splash screen
	JP	SHOW_SPLASH_SCREEN

DO_AUTO_LOAD:
	LD	A,(CMDLINE_IS_FAT)
	OR	A
	JR	NZ,DO_AUTO_LOAD_FAT

	CALL	LOAD_FILE
	JP	C,AUTO_LOAD_NOT_FOUND
	LD	A,1
	LD	(IN_EDITOR_MODE),A

	; Check if command-line specified a target goto line (> 0)
	LD	HL,(CMDLINE_GOTO_LINE)
	LD	A,H
	OR	L
	JR	Z,AUTO_LOAD_LINE_DEFAULT
	CALL	GOTO_LINE_HL
	JR	AUTO_LOAD_RENDER

AUTO_LOAD_LINE_DEFAULT:
	LD	HL,0
	LD	(CUR_DOC_ROW),HL
	LD	(TOP_DOC_ROW),HL
	LD	(CUR_COL),HL
	LD	(TARGET_COL),HL

AUTO_LOAD_RENDER:
	CALL	TERM_INIT
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	CALL	CHECK_FILE_TRUNCATED_POPUP
	CALL	LOCATE_CURSOR
	JP	MAIN_LOOP

DO_AUTO_LOAD_FAT:
	CALL	ENSURE_VFS_PLUGIN_LOADED
	JR	C,ALNF_FAT_PLUGIN_ERR

	; Setup VFS request for loading file
	LD	A,(CMDLINE_FAT_UNIT)
	LD	(VFS_REQ_UNIT),A
	LD	HL,FAT_DOC_PATH
	CALL	VFS_LOAD_FAT_FILE
	JR	C,AUTO_LOAD_FAT_NOT_FOUND

	; File loaded successfully!
	LD	A,1
	LD	(DOC_IS_FAT),A
	LD	(IN_EDITOR_MODE),A
	XOR	A
	LD	(DOC_MODIFIED),A
	CALL	INVALIDATE_ACTIVE_LINE
	CALL	CHECKOUT_ACTIVE_LINE
	CALL	RELOAD_CACHE_WINDOW_FORCE
	JP	AUTO_LOAD_LINE_DEFAULT

AUTO_LOAD_FAT_NOT_FOUND:
	; Target file not found on FAT volume:
	; Open new empty document tagged with DOC_IS_FAT = 1
	CALL	INIT_EMPTY_DOCUMENT
	XOR	A
	LD	(DOC_MODIFIED),A
	LD	A,1
	LD	(DOC_IS_FAT),A
	LD	(IN_EDITOR_MODE),A
	LD	(HAS_FILE_ARG),A
	JP	AUTO_LOAD_LINE_DEFAULT

ALNF_FAT_PLUGIN_ERR:
	LD	A,13
	CALL	PUTC
	LD	A,10
	CALL	PUTC
	LD	DE,STR_FATFS_PRL
	CALL	PRINT_STR
	LD	DE,STR_FILE_NOT_FOUND_SUFFIX
	CALL	PRINT_STR
	CALL	RESTORE_RAMDRIVE
	LD	SP,(SAVED_SP)
	RET

AUTO_LOAD_NOT_FOUND:
	LD	A,(CMDLINE_HAS_DRIVE)
	OR	A
	JR	NZ,ALNF_EXPLICIT_DRIVE

	; Bare filename ("SE <filename>"): open new empty file ready for editing
	CALL	INIT_EMPTY_DOCUMENT
	XOR	A
	LD	(DOC_MODIFIED),A
	LD	A,1
	LD	(IN_EDITOR_MODE),A
	LD	(HAS_FILE_ARG),A
	JP	AUTO_LOAD_LINE_DEFAULT

ALNF_EXPLICIT_DRIVE:
	; Command line specified drive ("SE <n:filename>"): report "<n:filename> file not found" and exit
	CALL	FCB_TO_FILENAME_STR
	LD	A,13
	CALL	PUTC
	LD	A,10
	CALL	PUTC
	LD	DE,INPUT_FILENAME_BUF
	CALL	PRINT_STR
	LD	DE,STR_FILE_NOT_FOUND_SUFFIX
	CALL	PRINT_STR
	CALL	RESTORE_RAMDRIVE
	LD	SP,(SAVED_SP)
	RET

;------------------------------------------------------------------------------
; ENTER_EDITOR: Top-level entry into editor mode from splash screen loop
; Resets stack, initializes or resumes editor document, renders screen and
; status bar, positions cursor, and enters main editor event loop.
;------------------------------------------------------------------------------
ENTER_EDITOR:
	LD	SP,LOCAL_STACK
	CALL	SETUP_EDITOR_STATE
	CALL	RENDER_STATUS_BAR
	CALL	LOCATE_CURSOR
	JP	MAIN_LOOP

;------------------------------------------------------------------------------
; SETUP_EDITOR_STATE: Ensure editor document buffers and viewport are valid
; Initializes empty doc if none open, constrains cursor, and renders screen.
; Preserves return address for callers (e.g. DO_SPLASH_GOTO_LINE,
; RESUME_EDITOR).
;------------------------------------------------------------------------------
SETUP_EDITOR_STATE:
	LD	A,(IN_EDITOR_MODE)
	OR	A
	JR	NZ,RESUME_EDITOR
	LD	A,(DOC_MODIFIED)
	OR	A
	JR	NZ,RESUME_EDITOR
	LD	HL,(DOC_TOTAL_LINES)
	LD	A,H
	OR	L
	JR	NZ,RESUME_EDITOR

	LD	A,1
	LD	(IN_EDITOR_MODE),A
	CALL	INIT_EMPTY_DOCUMENT
	LD	HL,0
	LD	(CUR_DOC_ROW),HL
	LD	(TOP_DOC_ROW),HL
	LD	(CUR_COL),HL
	LD	(TARGET_COL),HL

RESUME_EDITOR:
	LD	A,1
	LD	(IN_EDITOR_MODE),A
	XOR	A
	LD	(IS_SPLASH_SCREEN),A
	CALL	CONSTRAIN_CURSOR_VIEWPORT
	CALL	TERM_INIT
	CALL	RENDER_SCREEN
	RET

;------------------------------------------------------------------------------
; ENTER_EDITOR_WITH_ACTIVE_LINE: Force transition to editor after plugin mutate
; Resets stack, enables editor mode, refreshes cache, and renders editor screen
;------------------------------------------------------------------------------
ENTER_EDITOR_WITH_ACTIVE_LINE:
	LD	SP,LOCAL_STACK
	XOR	A
	LD	(PLUGIN_RET_CODE),A
	INC	A
	LD	(IN_EDITOR_MODE),A
	XOR	A
	LD	(IS_SPLASH_SCREEN),A
	CALL	CHECKOUT_ACTIVE_LINE
	CALL	RELOAD_CACHE_WINDOW_FORCE
	CALL	CONSTRAIN_CURSOR_VIEWPORT
	CALL	TERM_INIT
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	CALL	LOCATE_CURSOR
	JP	MAIN_LOOP

SHOW_SPLASH_SCREEN:
	LD	SP,LOCAL_STACK
	XOR	A
	LD	(BLOCK_ACTIVE),A
	LD	(STATUS_OOM_FLAG),A
SPLASH_START:
	CALL	RENDER_SPLASH

SPLASH_LOOP:
	CALL	GET_KEY

	; Standalone ESC or escape sequence (e.g. arrow keys) -> drain and ignore
	CP	KEY_ESC
	JR	NZ,SPLASH_NOT_ESC
	CALL	DRAIN_ESC_SEQUENCE
	JR	SPLASH_LOOP
SPLASH_NOT_ESC:
	; Command: Ctrl+P -> Context-Aware Plugin Pop-up (Splash)
	CP	KEY_CTRL_P
	JR	NZ,SPLASH_NOT_CTRL_P
	LD	A,PLUG_CTX_SPLASH
	CALL	DO_CONTEXT_PLUGIN_POPUP
	LD	A,(PLUGIN_RET_CODE)
	CP	2
	JP	Z,ENTER_EDITOR_WITH_ACTIVE_LINE
	JP	SPLASH_LOOP
SPLASH_NOT_CTRL_P:

	; Option: 'Q' or 'q' or Ctrl+Q -> Exit
	CP	'q'
	JP	Z,HANDLE_SPLASH_EXIT
	CP	'Q'
	JP	Z,HANDLE_SPLASH_EXIT
	CP	KEY_CTRL_Q
	JP	Z,HANDLE_SPLASH_EXIT

	; Option: 'N' or 'n' -> New File
	CP	'n'
	JP	Z,HANDLE_SPLASH_NEW
	CP	'N'
	JP	Z,HANDLE_SPLASH_NEW

	; Option: 'W' or 'w' or Ctrl+W -> Close File
	CP	'w'
	JP	Z,HANDLE_SPLASH_CLOSE
	CP	'W'
	JP	Z,HANDLE_SPLASH_CLOSE
	CP	KEY_CTRL_W
	JP	Z,HANDLE_SPLASH_CLOSE


	; Option: 'O' or 'o' or Ctrl+O -> Open File Screen
	CP	'o'
	JP	Z,HANDLE_SPLASH_OPEN
	CP	'O'
	JP	Z,HANDLE_SPLASH_OPEN
	CP	KEY_CTRL_O
	JP	Z,HANDLE_SPLASH_OPEN

	; Option: 'S' or 's' -> Save File Screen
	CP	's'
	JP	Z,DO_SPLASH_SAVE
	CP	'S'
	JP	Z,DO_SPLASH_SAVE

	; Option: 'L' or 'l' or Ctrl+L -> Goto Line Screen
	CP	'l'
	JP	Z,DO_SPLASH_GOTO_LINE
	CP	'L'
	JP	Z,DO_SPLASH_GOTO_LINE
	CP	KEY_CTRL_L
	JP	Z,DO_SPLASH_GOTO_LINE

	; Option: 'A' or 'a' -> Show About Screen
	CP	'a'
	JP	Z,DO_ABOUT_SCREEN
	CP	'A'
	JP	Z,DO_ABOUT_SCREEN

	; Option: 'M' or 'm' -> Show Memory Info Screen
	CP	'm'
	JP	Z,DO_MEM_INFO_SCREEN
	CP	'M'
	JP	Z,DO_MEM_INFO_SCREEN

	; Option: 'P' or 'p' -> Show Plugin Manager Screen
	CP	'p'
	JP	Z,DO_SPLASH_PLUGIN_SCREEN
	CP	'P'
	JP	Z,DO_SPLASH_PLUGIN_SCREEN

	; Option: 'C' or 'c' -> Show Configuration Screen
	CP	'c'
	JP	Z,DO_CONFIG_SCREEN
	CP	'C'
	JP	Z,DO_CONFIG_SCREEN

	; Option: '1' -> Modern Screen Mode (120x40)
	CP	'1'
	JP	Z,DO_SET_120X40

	; Option: '2' -> Classic Screen Mode (80x24)
	CP	'2'
	JP	Z,DO_SET_80X24

	; Option: 'E' or 'e' or Enter -> Enter/Resume Editor
	CP	'e'
	JP	Z,ENTER_EDITOR
	CP	'E'
	JP	Z,ENTER_EDITOR
	CP	KEY_ENTER
	JP	Z,ENTER_EDITOR

	JP	SPLASH_LOOP

DO_SET_120X40:
	CALL	SET_MODE_120X40
	JP	SHOW_SPLASH_SCREEN

DO_SET_80X24:
	CALL	SET_MODE_80X24
	JP	SHOW_SPLASH_SCREEN


DO_ABOUT_SCREEN:
	CALL	SHOW_ABOUT_SCREEN
ABT_LOOP:
	CALL	GET_KEY
	CP	KEY_CTRL_P
	JR	NZ,ABT_NOT_CTRL_P
	LD	A,PLUG_CTX_ABOUT
	CALL	DO_CONTEXT_PLUGIN_POPUP
	JR	ABT_LOOP
ABT_NOT_CTRL_P:
	CP	KEY_ESC
	CALL	Z,DRAIN_ESC_SEQUENCE
	JP	SHOW_SPLASH_SCREEN

DO_MEM_INFO_SCREEN:
	CALL	SHOW_MEM_INFO_SCREEN
MIS_LOOP:
	CALL	GET_KEY
	CP	KEY_CTRL_P
	JR	NZ,MIS_NOT_CTRL_P
	LD	A,PLUG_CTX_MEM_INFO
	CALL	DO_CONTEXT_PLUGIN_POPUP
	JR	MIS_LOOP
MIS_NOT_CTRL_P:
	CP	KEY_ESC
	CALL	Z,DRAIN_ESC_SEQUENCE
	JP	SHOW_SPLASH_SCREEN

DO_CONFIG_SCREEN:
	CALL	SHOW_CONFIG_SCREEN
CONFIG_LOOP:
	CALL	GET_KEY

	; Command: Ctrl+P -> Context-Aware Plugin Pop-up (Configuration)
	CP	KEY_CTRL_P
	JR	NZ,CONFIG_NOT_CTRL_P
	LD	A,PLUG_CTX_CONFIG
	CALL	DO_CONTEXT_PLUGIN_POPUP
	JR	CONFIG_LOOP
CONFIG_NOT_CTRL_P:

	; Standalone ESC or escape sequence -> return to splash
	CP	KEY_ESC
	JR	NZ,CONFIG_NOT_ESC
	CALL	DRAIN_ESC_SEQUENCE
	JP	SHOW_SPLASH_SCREEN

CONFIG_NOT_ESC:
	; Option: '1' -> Toggle Screen Mode (80x24 <-> 120x40)
	CP	'1'
	JR	Z,CONFIG_TOGGLE_MODE

	; Option: '2' -> Toggle RAM Drive Memory Blocks
	CP	'2'
	JR	Z,CONFIG_TOGGLE_RAMDRIVE

	; Option: '3' -> Toggle Max Lines (16K <-> 32K)
	CP	'3'
	JP	Z,CONFIG_TOGGLE_LINES

	; Option: '4' -> Toggle Tab Width (4 <-> 8)
	CP	'4'
	JR	Z,CONFIG_TOGGLE_TAB

	; Option: '5' -> Toggle Plugin Manager (Auto <-> Disabled)
	CP	'5'
	JP	Z,CONFIG_TOGGLE_PLUGIN

	; Option: 'S' or 's' -> Save Configuration to local SE.CFG
	CP	's'
	JP	Z,CONFIG_DO_SAVE
	CP	'S'
	JP	Z,CONFIG_DO_SAVE

	; Option: 'Q' or 'q' or Enter -> Return to Splash Screen
	CP	'q'
	JP	Z,SHOW_SPLASH_SCREEN
	CP	'Q'
	JP	Z,SHOW_SPLASH_SCREEN
	CP	KEY_ENTER
	JP	Z,SHOW_SPLASH_SCREEN

	JR	CONFIG_LOOP

CONFIG_TOGGLE_MODE:
	LD	A,(SCREEN_MODE)
	CP	MODE_120X40
	JR	Z,CONFIG_SET_80
	CALL	SET_MODE_120X40
	JR	CONFIG_REDRAW
CONFIG_SET_80:
	CALL	SET_MODE_80X24
CONFIG_REDRAW:
	CALL	SHOW_CONFIG_SCREEN
	JR	CONFIG_LOOP

CONFIG_TOGGLE_RAMDRIVE:
	LD	A,(CFG_RAMDRIVE_FLAG)
	CP	RAMDRV_MODE_PROTECTED
	JR	Z,CTR_SET_HIB
	CP	RAMDRV_MODE_HIBERNATE
	JR	Z,CTR_SET_ENA
	; Currently ENABLED (1) -> switch to PROTECTED (0)
	XOR	A
	LD	(CFG_RAMDRIVE_FLAG),A
	JR	CTR_APPLY
CTR_SET_HIB:
	LD	A,RAMDRV_MODE_HIBERNATE
	LD	(CFG_RAMDRIVE_FLAG),A
	JR	CTR_APPLY
CTR_SET_ENA:
	; Before enabling raw overwrite, ensure active drive is not the RAM drive
	LD	A,(RAMDRIVE_DRIVE_NUM)
	CP	0FFH
	JR	Z,CTR_DO_ENA
	LD	B,A
	LD	A,(CURRENT_DEFAULT_DRIVE)
	CP	B
	JR	Z,CTR_SET_PROT		; Active drive is RAM drive: skip Enabled, wrap to Protected!
CTR_DO_ENA:
	LD	A,RAMDRV_MODE_ENABLED
	LD	(CFG_RAMDRIVE_FLAG),A
	JR	CTR_APPLY

CTR_SET_PROT:
	XOR	A
	LD	(CFG_RAMDRIVE_FLAG),A
	JR	CTR_APPLY
CTR_APPLY:
	CALL	BUFFER_INIT
	CALL	SHOW_CONFIG_SCREEN
	JP	CONFIG_LOOP

CONFIG_TOGGLE_TAB:
	LD	A,(CFG_TAB_WIDTH)
	CP	4
	JR	Z,CTT_SET_8
	LD	A,4
	LD	(CFG_TAB_WIDTH),A
	LD	A,3
	LD	(CFG_TAB_MASK),A
	JR	CTT_DONE
CTT_SET_8:
	LD	A,8
	LD	(CFG_TAB_WIDTH),A
	LD	A,7
	LD	(CFG_TAB_MASK),A
CTT_DONE:
	CALL	SHOW_CONFIG_SCREEN
	JP	CONFIG_LOOP

CONFIG_TOGGLE_LINES:
	LD	A,(CFG_LINES_MODE)
	XOR	1			; Toggle 0 <-> 1
	LD	(CFG_LINES_MODE),A
	CALL	BUFFER_INIT		; Reallocate Far RAM banks
	CALL	SHOW_CONFIG_SCREEN
	JP	CONFIG_LOOP

CONFIG_TOGGLE_PLUGIN:
	; If currently loaded, Far RAM is already verified
	LD	A,(PLUGIN_MGR_LOADED)
	OR	A
	JR	NZ,CTP_FAR_OK

	; Not loaded: check Far RAM availability (>= 2 banks)
	LD	A,(EXT_BANK_COUNT)
	CP	2
	JR	NC,CTP_FAR_OK

	; Insufficient Far RAM: Autoload / On Demand not selectable.
	; User requested: No beeps. Silently keep disabled and ignore.
	XOR	A
	LD	(CFG_AUTOLOAD_PLUGIN_MGR),A
	JP	CONFIG_LOOP

CTP_FAR_OK:
	; Cycle: AUTOLOAD (1) -> ONDEMAND (2) -> DISABLED (0) -> AUTOLOAD (1)
	LD	A,(CFG_AUTOLOAD_PLUGIN_MGR)
	CP	PLUGIN_MODE_AUTOLOAD
	JR	Z,CTP_TO_ONDEMAND
	CP	PLUGIN_MODE_ONDEMAND
	JR	Z,CTP_TO_DISABLED

	; From DISABLED (0) -> AUTOLOAD (1)
	LD	A,PLUGIN_MODE_AUTOLOAD
	LD	(CFG_AUTOLOAD_PLUGIN_MGR),A
	CALL	ENSURE_PLUGIN_MGR_LOADED
	JR	CTP_DONE

CTP_TO_ONDEMAND:
	; From AUTOLOAD (1) -> ONDEMAND (2)
	LD	A,PLUGIN_MODE_ONDEMAND
	LD	(CFG_AUTOLOAD_PLUGIN_MGR),A
	CALL	CTP_UNLOAD_IF_LOADED
	JR	CTP_DONE

CTP_TO_DISABLED:
	; From ONDEMAND (2) -> DISABLED (0)
	XOR	A
	LD	(CFG_AUTOLOAD_PLUGIN_MGR),A
	CALL	CTP_UNLOAD_IF_LOADED
	JR	CTP_DONE

CTP_UNLOAD_IF_LOADED:
	LD	A,(PLUGIN_MGR_LOADED)
	OR	A
	RET	Z
	LD	A,(PLUGIN_MGR_BANK)
	CALL	RELEASE_FAR_BANK
	XOR	A
	LD	(PLUGIN_MGR_LOADED),A
	LD	(PLUGIN_MGR_BANK),A
	RET

CTP_DONE:
	CALL	SHOW_CONFIG_SCREEN
	JP	CONFIG_LOOP

CONFIG_DO_SAVE:
	CALL	SAVE_CONFIG
	CALL	SHOW_CONFIG_SCREEN
	JP	CONFIG_LOOP

DO_SPLASH_SAVE:
	CALL	DO_SAVE_FILE_UI
	JP	SHOW_SPLASH_SCREEN

DO_SPLASH_PLUGIN_SCREEN:
	CALL	DO_PLUGIN_SCREEN
	JP	SHOW_SPLASH_SCREEN

DO_SPLASH_GOTO_LINE:
	LD	SP,LOCAL_STACK
	CALL	SETUP_EDITOR_STATE
	CALL	RENDER_STATUS_BAR
	CALL	DO_GOTO_LINE_UI
	JP	MAIN_LOOP

MAIN_LOOP:
	; If no key is immediately ready in serial buffer, flush deferred render!
	CALL	CHECK_KEY_READY
	JR	NZ,MAIN_LOOP_GET_KEY

	CALL	FLUSH_DEFERRED_RENDER

MAIN_LOOP_GET_KEY:
	CALL	GET_KEY

	; If OOM status was displayed on status bar, revert upon any keypress
	LD	B,A
	LD	A,(STATUS_OOM_FLAG)
	OR	A
	JR	Z,ML_NO_OOM_CLEAR
	XOR	A
	LD	(STATUS_OOM_FLAG),A
	LD	A,1
	LD	(NEED_STATUS_RENDER),A
ML_NO_OOM_CLEAR:
	; If plugin status message was displayed on status bar, clear upon keypress
	LD	HL,(PLUGIN_STATUS_MSG_PTR)
	LD	A,H
	OR	L
	JR	Z,ML_NO_PLUG_CLEAR
	LD	HL,0
	LD	(PLUGIN_STATUS_MSG_PTR),HL
	LD	A,1
	LD	(NEED_STATUS_RENDER),A
ML_NO_PLUG_CLEAR:
	LD	A,B

	; Command: Ctrl+Q -> Exit
	CP	KEY_CTRL_Q
	JP	Z,HANDLE_CTRL_Q

	; Command: Ctrl+W -> Close File to Splash
	CP	KEY_CTRL_W
	JP	Z,HANDLE_CTRL_W

	; Command: Ctrl+F -> Find
	CP	KEY_CTRL_F
	JR	NZ,CHECK_CTRL_R
	CALL	FLUSH_DEFERRED_RENDER
	CALL	DO_FIND_UI
	JP	MAIN_LOOP

CHECK_CTRL_R:
	; Command: Ctrl+R -> Search & Replace
	CP	KEY_CTRL_R
	JR	NZ,CHECK_CTRL_N
	CALL	FLUSH_DEFERRED_RENDER
	CALL	DO_REPLACE_UI
	JP	MAIN_LOOP

CHECK_CTRL_N:
	; Command: Ctrl+N -> Find Next
	CP	KEY_CTRL_N
	JR	NZ,CHECK_CTRL_P
	CALL	FLUSH_DEFERRED_RENDER
	CALL	DO_FIND_NEXT
	JP	MAIN_LOOP

CHECK_CTRL_P:
	; Command: Ctrl+P -> Context-Aware Plugin Pop-up (Editor)
	CP	KEY_CTRL_P
	JR	NZ,CHECK_CTRL_S
	CALL	FLUSH_DEFERRED_RENDER
	LD	A,PLUG_CTX_EDITOR
	CALL	DO_CONTEXT_PLUGIN_POPUP
	JP	MAIN_LOOP

CHECK_CTRL_S:
	; Command: Ctrl+S -> Save File Screen or Block Save File
	CP	KEY_CTRL_S
	JR	NZ,CHECK_CTRL_O
	CALL	FLUSH_DEFERRED_RENDER
	LD	A,(BLOCK_ACTIVE)
	OR	A
	JP	NZ,DO_BLOCK_SAVE_FILE
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
	; Command: Ctrl+O -> Open File Screen or Block Insert File
	CP	KEY_CTRL_O
	JR	NZ,CHECK_CTRL_C
	CALL	FLUSH_DEFERRED_RENDER
	LD	A,(BLOCK_ACTIVE)
	OR	A
	JP	NZ,DO_BLOCK_INSERT_FILE
	JP	HANDLE_CTRL_O

CHECK_CTRL_C:
	; Command: Ctrl+C -> Copy block (solidifies dynamic block first if active)
	CP	KEY_CTRL_C
	JR	NZ,CHECK_CTRL_K
	LD	A,(BLOCK_ACTIVE)
	CP	2
	JR	Z,DO_CTRL_C_COPY
	CP	1
	JR	Z,DO_CTRL_C_IMPLIED_SOLIDIFY_COPY
	JP	MAIN_LOOP		; Ignore if block not active

DO_CTRL_C_IMPLIED_SOLIDIFY_COPY:
	CALL	SOLIDIFY_BLOCK
DO_CTRL_C_COPY:
	CALL	DO_COPY_BLOCK
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
	JR	NZ,CHECK_CTRL_X
	LD	A,(BLOCK_ACTIVE)
	CP	2
	JR	Z,DO_CTRL_D_BLOCK
	CP	1
	JR	Z,DO_CTRL_D_IMPLIED_K_DELETE
	CALL	DO_DELETE_FORWARD
	JP	MAIN_LOOP

DO_CTRL_D_IMPLIED_K_DELETE:
	CALL	SOLIDIFY_BLOCK
DO_CTRL_D_BLOCK:
	CALL	DO_DELETE_BLOCK
	JP	MAIN_LOOP

CHECK_CTRL_X:
	; Command: Ctrl+X -> Move solidified block / solidify dynamic block
	CP	KEY_CTRL_X
	JR	NZ,CHECK_CTRL_Y
	LD	A,(BLOCK_ACTIVE)
	CP	2
	JR	Z,DO_CTRL_X_MOVE
	CP	1
	JR	Z,DO_CTRL_X_SOLIDIFY
	JP	MAIN_LOOP		; Ignore if block not active

DO_CTRL_X_SOLIDIFY:
	CALL	SOLIDIFY_BLOCK
	JP	MAIN_LOOP

DO_CTRL_X_MOVE:
	CALL	DO_MOVE_BLOCK
	JP	MAIN_LOOP

CHECK_CTRL_Y:
	; Command: Ctrl+Y -> Beautify Block (if active) or Whole File (if no block)
	CP	KEY_CTRL_Y
	JR	NZ,CHECK_CTRL_Z
	CALL	FLUSH_DEFERRED_RENDER
	JP	DO_CTRL_Y_BEAUTIFY

CHECK_CTRL_Z:
	; Command: Ctrl+Z -> Open Plugin Manager Screen
	CP	KEY_CTRL_Z
	JR	NZ,CHECK_PAGE_KEYS
	CALL	FLUSH_DEFERRED_RENDER
	JP	DO_EDITOR_PLUGIN_SCREEN

CHECK_PAGE_KEYS:
	; Command: Ctrl+L -> Goto line number
	CP	KEY_CTRL_L
	JR	NZ,CHECK_NAV_KEYS
	CALL	FLUSH_DEFERRED_RENDER
	CALL	DO_GOTO_LINE_UI
	JP	MAIN_LOOP

CHECK_NAV_KEYS:
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
	JR	C,ENTER_INS_DONE
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
ENTER_INS_DONE:
	JP	MAIN_LOOP

DO_ENTER_CANCEL_SETUP:
	CALL	CANCEL_BLOCK
	JP	MAIN_LOOP

CHECK_BACKSPACE:
	CP	KEY_BACKSPACE
	JR	Z,DO_HANDLE_BS
	CP	KEY_DEL
	JR	NZ,CHECK_ESC_SEQ
	LD	A,(BLOCK_ACTIVE)
	CP	2
	JP	Z,DO_CTRL_D_BLOCK
	CP	1
	JP	Z,DO_CTRL_D_IMPLIED_K_DELETE
	CALL	DO_DELETE_FORWARD
	JP	MAIN_LOOP

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

;------------------------------------------------------------------------------
; Exit, Close & New Document Handling with Unsaved Changes Protection
;------------------------------------------------------------------------------
HANDLE_SPLASH_EXIT:
	LD	A,ACTION_EXIT
	LD	(CONFIRM_ACTION),A
	LD	A,(DOC_MODIFIED)
	OR	A
	JP	Z,EXIT_PROGRAM

	; Document modified: switch to editor view and show exit prompt
	LD	A,1
	LD	(IN_EDITOR_MODE),A
	CALL	RESUME_EDITOR
	JP	SHOW_EXIT_PROMPT

HANDLE_CTRL_Q:
	LD	A,ACTION_EXIT
	LD	(CONFIRM_ACTION),A
	LD	A,(DOC_MODIFIED)
	OR	A
	JP	Z,EXIT_PROGRAM
	JP	SHOW_EXIT_PROMPT

HANDLE_CTRL_W:
	LD	A,ACTION_CLOSE
	LD	(CONFIRM_ACTION),A
	LD	A,(DOC_MODIFIED)
	OR	A
	JP	Z,DO_EXEC_CLOSE
	JP	SHOW_EXIT_PROMPT

HANDLE_SPLASH_CLOSE:
	; If no editor session is active, ignore close
	LD	A,(IN_EDITOR_MODE)
	OR	A
	JR	Z,SPLASH_CLOSE_NOP
	LD	A,ACTION_CLOSE
	LD	(CONFIRM_ACTION),A
	LD	A,(DOC_MODIFIED)
	OR	A
	JP	Z,DO_EXEC_CLOSE
	CALL	RESUME_EDITOR
	JP	SHOW_EXIT_PROMPT
SPLASH_CLOSE_NOP:
	JP	SPLASH_LOOP

HANDLE_SPLASH_NEW:
	LD	A,ACTION_NEW
	LD	(CONFIRM_ACTION),A
	LD	A,(DOC_MODIFIED)
	OR	A
	JP	Z,DO_EXEC_NEW
	CALL	RESUME_EDITOR
	JP	SHOW_EXIT_PROMPT

HANDLE_CTRL_O:
	LD	A,ACTION_OPEN
	LD	(CONFIRM_ACTION),A
	LD	A,(DOC_MODIFIED)
	OR	A
	JP	Z,DO_EXEC_OPEN
	JP	SHOW_EXIT_PROMPT

DO_BLOCK_SAVE_FILE:
	CALL	INVALIDATE_ACTIVE_LINE
	CALL	FLUSH_DIRTY_CACHE
	; Implied Ctrl-K: solidify dynamic block selection if state 1
	LD	A,(BLOCK_ACTIVE)
	CP	1
	CALL	Z,SOLIDIFY_BLOCK
	CALL	NORMALIZE_BLOCK_BOUNDS
	LD	A,1
	LD	(IS_BLOCK_SAVE_UI),A
	CALL	DO_SAVE_FILE_UI
	; Clean up UI flags (save completed or user pressed ESC)
	XOR	A
	LD	(IS_BLOCK_SAVE_UI),A
	LD	(IS_SAVE_UI),A
	LD	(IS_SPLASH_SCREEN),A
	; Note: BLOCK_ACTIVE is intentionally retained at 2 (solidified)
	; so the user can subsequently press Del (or Ctrl+D) to delete the block.
	CALL	TERM_INIT
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	XOR	A
	LD	(NEED_SCREEN_RENDER),A
	LD	(NEED_LINE_RENDER),A
	LD	(NEED_STATUS_RENDER),A
	JP	MAIN_LOOP

DO_BLOCK_INSERT_FILE:
	; Implied Ctrl-K: solidify dynamic block selection if state 1
	LD	A,(BLOCK_ACTIVE)
	CP	1
	CALL	Z,SOLIDIFY_BLOCK
	CALL	NORMALIZE_BLOCK_BOUNDS
	LD	A,1
	LD	(IS_BLOCK_INSERT_UI),A
	CALL	DO_OPEN_FILE_UI
	; User pressed ESC in DO_OPEN_FILE_UI -> cancel back to editor
	XOR	A
	LD	(IS_BLOCK_INSERT_UI),A
	LD	(IS_SPLASH_SCREEN),A
	CALL	TERM_INIT
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	JP	MAIN_LOOP

HANDLE_SPLASH_OPEN:
	LD	A,ACTION_OPEN
	LD	(CONFIRM_ACTION),A
	LD	A,(DOC_MODIFIED)
	OR	A
	JR	Z,DO_SPLASH_OPEN_DIRECT
	CALL	RESUME_EDITOR
	JR	SHOW_EXIT_PROMPT

DO_SPLASH_OPEN_DIRECT:
	CALL	DO_OPEN_FILE_UI
	JP	SHOW_SPLASH_SCREEN

SHOW_EXIT_PROMPT:
	CALL	DO_SAVE_CHANGES_POPUP
	JP	C,EXIT_CANCEL
	CP	'y'
	JP	Z,EXIT_SAVE_AND_QUIT
	CP	'Y'
	JP	Z,EXIT_SAVE_AND_QUIT
	JP	EXEC_CONFIRM_ACTION

;------------------------------------------------------------------------------
; DO_SAVE_CHANGES_POPUP:
; Display centered modal pop-up dialog querying user whether to save changes.
; Dimensions: 50 columns wide x 7 rows high.
; Returns:
;   Carry = 0, A = 'Y': User confirmed save
;   Carry = 0, A = 'N': User chose discard / proceed without saving
;   Carry = 1: User cancelled (ESC / Ctrl-C)
;------------------------------------------------------------------------------
DO_SAVE_CHANGES_POPUP:
	; 1. Calculate POPUP_COL = ((ACTIVE_COLS - 50) / 2) + 1
	LD	A,(ACTIVE_COLS)
	SUB	50
	SRL	A
	INC	A
	LD	(POPUP_COL),A

	; 2. Calculate POPUP_ROW = ((ACTIVE_ROWS - 7) / 2) + 1
	LD	A,(ACTIVE_ROWS)
	SUB	7
	SRL	A
	INC	A
	LD	(POPUP_ROW),A
	LD	(POPUP_SAVE_START_ROW),A

	; 3. Render 7-line Pop-Up Box
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	PRINT_STR

	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_SAVE_TITLE
	CALL	PRINT_STR

	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	PRINT_STR

	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_SAVE_MSG1
	CALL	PRINT_STR

	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_SAVE_MSG2
	CALL	PRINT_STR

	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_SAVE_KEYS
	CALL	PRINT_STR

	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	PRINT_STR

	; Position cursor inside popup on prompt line after "Save changes? "
	; Row = POPUP_SAVE_START_ROW + 4, Col = POPUP_COL + 16
	LD	A,(POPUP_SAVE_START_ROW)
	ADD	A,4
	LD	H,A
	LD	A,(POPUP_COL)
	ADD	A,16
	LD	L,A
	CALL	LOCATE_RC
	LD	DE,STR_SHOW_CURSOR
	CALL	PRINT_STR

DSCP_KEY_LOOP:
	CALL	GET_KEY
	CP	'y'
	JR	Z,DSCP_CHOSE_Y
	CP	'Y'
	JR	Z,DSCP_CHOSE_Y

	CP	'n'
	JR	Z,DSCP_CHOSE_N
	CP	'N'
	JR	Z,DSCP_CHOSE_N

	CP	KEY_ESC
	JR	Z,DSCP_CHECK_ESC

	JR	DSCP_KEY_LOOP

DSCP_CHECK_ESC:
	; Check if a character follows ESC within a short timeout
	LD	BC,ESC_TIMEOUT_LOOPS
DSCP_WAIT_ESC:
	CALL	CHECK_KEY_READY
	JR	NZ,DSCP_DRAIN_ESC
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,DSCP_WAIT_ESC
	; Standalone ESC key: cancel
	JR	DSCP_CANCEL

DSCP_DRAIN_ESC:
	CALL	GET_KEY			; Consume '[' or 'O'
DSCP_DRAIN_MORE:
	LD	BC,500
DSCP_DRAIN_WAIT:
	CALL	CHECK_KEY_READY
	JR	NZ,DSCP_DRAIN_BYTE
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,DSCP_DRAIN_WAIT
	; Sequence drained: reposition cursor and resume key loop
	LD	A,(POPUP_SAVE_START_ROW)
	ADD	A,3
	LD	H,A
	LD	A,(POPUP_COL)
	ADD	A,16
	LD	L,A
	CALL	LOCATE_RC
	JR	DSCP_KEY_LOOP

DSCP_DRAIN_BYTE:
	CALL	GET_KEY
	JR	DSCP_DRAIN_MORE

DSCP_CHOSE_Y:
	LD	A,'Y'
	OR	A			; Carry = 0
	RET

DSCP_CHOSE_N:
	LD	A,'N'
	OR	A			; Carry = 0
	RET

DSCP_CANCEL:
	SCF				; Carry = 1
	RET

EXIT_CANCEL:
	XOR	A
	LD	(IS_EXIT_PROMPT),A
	LD	SP,LOCAL_STACK
	CALL	RELOAD_CACHE_WINDOW_FORCE
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	CALL	LOCATE_CURSOR
	XOR	A
	LD	(NEED_SCREEN_RENDER),A
	LD	(NEED_LINE_RENDER),A
	LD	(NEED_STATUS_RENDER),A
	JP	MAIN_LOOP

EXIT_SAVE_AND_QUIT:
	XOR	A
	LD	(IS_EXIT_PROMPT),A
	; Check if document has a known filename
	LD	A,(WORK_FCB+1)
	CP	' '
	JR	Z,EXIT_SAVE_PROMPT_NAME
	CP	0
	JR	Z,EXIT_SAVE_PROMPT_NAME
	LD	A,(HAS_FILE_ARG)
	OR	A
	JR	Z,EXIT_SAVE_PROMPT_NAME

	; Known file: save directly to disk
	CALL	DO_ACTUAL_SAVE
	JP	EXEC_CONFIRM_ACTION

EXIT_SAVE_PROMPT_NAME:
	CALL	DO_SAVE_FILE_UI
	LD	A,(DOC_MODIFIED)
	OR	A
	JP	Z,EXEC_CONFIRM_ACTION	; Save succeeded -> execute action

	; Save was cancelled by user: resume editor
	CALL	TERM_INIT
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	CALL	LOCATE_CURSOR
	XOR	A
	LD	(NEED_SCREEN_RENDER),A
	LD	(NEED_LINE_RENDER),A
	LD	(NEED_STATUS_RENDER),A
	JP	MAIN_LOOP

EXEC_CONFIRM_ACTION:
	XOR	A
	LD	(IS_EXIT_PROMPT),A
	LD	A,(CONFIRM_ACTION)
	CP	ACTION_CLOSE
	JR	Z,DO_EXEC_CLOSE
	CP	ACTION_NEW
	JR	Z,DO_EXEC_NEW
	CP	ACTION_OPEN
	JR	Z,DO_EXEC_OPEN
	JP	EXIT_PROGRAM

DO_EXEC_CLOSE:
	CALL	DO_CLOSE_DOCUMENT
	JP	SHOW_SPLASH_SCREEN

DO_EXEC_NEW:
	CALL	DO_NEW_DOCUMENT
	JP	MAIN_LOOP

DO_EXEC_OPEN:
	XOR	A
	LD	(DOC_MODIFIED),A
	CALL	DO_OPEN_FILE_UI
	CALL	TERM_INIT
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	XOR	A
	LD	(NEED_SCREEN_RENDER),A
	LD	(NEED_LINE_RENDER),A
	LD	(NEED_STATUS_RENDER),A
	JP	MAIN_LOOP

DO_CLOSE_DOCUMENT:
	XOR	A
	LD	(PLUGIN_RET_CODE),A
	CALL	INIT_EMPTY_DOCUMENT
	XOR	A
	LD	(HAS_FILE_ARG),A
	LD	(IN_EDITOR_MODE),A
	LD	(DOC_MODIFIED),A
	LD	(DOC_USER_NUM),A
	LD	(WORK_FCB_USER),A
	CALL	CLEAR_CACHE_DIRTY_FLAGS
	LD	(BLOCK_ACTIVE),A
	; Clear WORK_FCB (36 bytes)
	LD	HL,WORK_FCB
	LD	B,36
CLOSE_FCB_LOOP:
	LD	(HL),0
	INC	HL
	DJNZ	CLOSE_FCB_LOOP
	RET

DO_NEW_DOCUMENT:
	CALL	DO_CLOSE_DOCUMENT
	LD	A,1
	LD	(IN_EDITOR_MODE),A
	CALL	TERM_INIT
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	RET

EXIT_PROGRAM:
	CALL	CLEANUP_SWAP_FILE
	CALL	TERM_INIT
	LD	DE,MSG_EXIT
	CALL	PRINT_STR
	LD	DE,STR_SHOW_CURSOR
	CALL	PRINT_STR

	; Restore original CP/M user area
	LD	A,(ORIG_CPM_USER)
	LD	E,A
	LD	C,32			; BDOS Set User Area
	CALL	BDOS_ENTRY

	CALL	RESTORE_RAMDRIVE

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
	LD	(HOST_API_ROWS),A
	LD	A,120
	LD	(ACTIVE_COLS),A
	LD	(HOST_API_COLS),A
	LD	HL,0
	LD	(VIEW_LEFT_COL),HL
	LD	HL,120
	LD	(VIEW_RIGHT_COL),HL
	RET

SET_MODE_80X24:
	LD	A,MODE_80X24
	LD	(SCREEN_MODE),A
	LD	A,24
	LD	(ACTIVE_ROWS),A
	LD	(HOST_API_ROWS),A
	LD	A,80
	LD	(ACTIVE_COLS),A
	LD	(HOST_API_COLS),A
	LD	HL,0
	LD	(VIEW_LEFT_COL),HL
	LD	HL,80
	LD	(VIEW_RIGHT_COL),HL
	RET

;------------------------------------------------------------------------------
; Terminal / VT100 I/O Routines
;------------------------------------------------------------------------------
TERM_INIT:
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	LD	DE,STR_SHOW_CURSOR
	CALL	PRINT_STR
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
	LD	HL,0
	LD	(CMDLINE_GOTO_LINE),HL
	XOR	A
	LD	(CMDLINE_HAS_DRIVE),A
	LD	(CMDLINE_IS_FAT),A

	; Check DEFAULT_DMA length byte at 0080H
	LD	A,(DEFAULT_DMA)
	OR	A
	JP	Z,NO_FILE_ARG

	; Null-terminate command line tail: DEFAULT_DMA + 1 + length
	LD	E,A
	LD	D,0
	LD	HL,DEFAULT_DMA+1
	ADD	HL,DE
	LD	(HL),0			; Null-terminate

	; Skip leading spaces
	LD	HL,DEFAULT_DMA+1
CCL_SKIP_SP:
	LD	A,(HL)
	CP	' '
	JR	NZ,CCL_CHECK_NONEMPTY
	INC	HL
	JR	CCL_SKIP_SP

CCL_CHECK_NONEMPTY:
	OR	A
	JP	Z,NO_FILE_ARG		; Only spaces -> no file arg

	; We have a command line argument!
	LD	A,1
	LD	(HAS_FILE_ARG),A

	; Check if command-line argument is a FAT path (U: or U<unit>:)
	PUSH	HL
	CALL	PARSE_FAT_PATH		; A = unit, HL = path after ':'
	JR	NC,CCL_NOT_FAT_ARG

	; Command line is a FAT path!
	LD	(CMDLINE_FAT_UNIT),A
	LD	(FAT_DOC_UNIT),A
	LD	A,1
	LD	(CMDLINE_IS_FAT),A
	POP	AF			; Discard saved initial HL

	; Copy path after ':' into FAT_DOC_PATH (prepending '/' if needed)
	LD	DE,FAT_DOC_PATH
	LD	A,(HL)
	CP	'/'
	JR	Z,CCL_COPY_PATH
	LD	A,'/'
	LD	(DE),A
	INC	DE
CCL_COPY_PATH:
	LD	A,(HL)
	OR	A
	JR	Z,CCL_PATH_TERMINATE
	CP	' '
	JR	Z,CCL_PATH_TERMINATE
	LD	(DE),A
	INC	HL
	INC	DE
	JR	CCL_COPY_PATH

CCL_PATH_TERMINATE:
	XOR	A
	LD	(DE),A

	; Extract base filename into FAT_DOC_FNAME
	LD	HL,FAT_DOC_PATH
	CALL	EXTRACT_BASE_FILENAME
	RET

CCL_NOT_FAT_ARG:
	POP	HL

	; Parse optional :<line> suffix from DEFAULT_DMA
	CALL	PARSE_CMDLINE_LINE_NUM

	; Parse command line argument into WORK_FCB and WORK_FCB_USER
	LD	HL,DEFAULT_DMA+1
	CALL	PARSE_STRING_TO_FCB

	; Check if command line had an explicit drive
	LD	A,(PREFIX_DRIVE)
	OR	A
	JR	Z,CCL_CHECK_USER
	LD	A,1
	LD	(CMDLINE_HAS_DRIVE),A

CCL_CHECK_USER:
	; Update DOC_USER_NUM and CURRENT_DIR_USER to match WORK_FCB_USER
	LD	A,(WORK_FCB_USER)
	LD	(DOC_USER_NUM),A
	LD	(CURRENT_DIR_USER),A
	; Update CURRENT_DIR_DRIVE and title strings to match WORK_FCB
	LD	A,(WORK_FCB)
	OR	A
	JR	Z,CCL_DONE
	LD	(CURRENT_DIR_DRIVE),A
	ADD	A,'A'-1
	LD	(STR_DIR_DRIVE_CHAR),A
	LD	(STR_SAVE_DRIVE_CHAR),A
CCL_DONE:
	RET

NO_FILE_ARG:
	XOR	A
	LD	(HAS_FILE_ARG),A
	LD	(CMDLINE_HAS_DRIVE),A

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
; Parse optional :<line> suffix from command line buffer (DEFAULT_DMA = $0080)
; If found, stores 16-bit line number in (CMDLINE_GOTO_LINE).
; Format: [drive:]filename[:line]
;------------------------------------------------------------------------------
PARSE_CMDLINE_LINE_NUM:
	LD	A,(DEFAULT_DMA)		; A = length of command line tail
	OR	A
	RET	Z			; Empty command line

	; HL = pointer to end of command line: DEFAULT_DMA + length
	LD	E,A
	LD	D,0
	LD	HL,DEFAULT_DMA
	ADD	HL,DE			; HL points to last char of tail

	; Trim trailing spaces
TRIM_TRAIL_SPACES:
	LD	A,(HL)
	CP	' '
	JR	NZ,CHECK_TRAIL_DIGITS
	DEC	HL
	DEC	E
	JR	NZ,TRIM_TRAIL_SPACES
	RET				; Only spaces found

CHECK_TRAIL_DIGITS:
	; Last non-space character must be a digit '0'..'9'
	LD	A,(HL)
	CP	'0'
	RET	C
	CP	'9'+1
	RET	NC

	; Scan backwards past all digits to find preceding ':'
SCAN_DIGITS_BACK:
	DEC	HL
	DEC	E
	RET	Z			; Hit start of buffer without ':'
	LD	A,(HL)
	CP	':'
	JR	Z,FOUND_COLON
	CP	'0'
	JR	C,NOT_LINE_NUM
	CP	'9'+1
	JR	C,SCAN_DIGITS_BACK
NOT_LINE_NUM:
	RET

FOUND_COLON:
	; HL points to ':' in DEFAULT_DMA. Check if this colon is inside a drive/user prefix.
	PUSH	HL			; Save colon pointer
	LD	HL,DEFAULT_DMA+1
	CALL	PARSE_DRIVE_USER_PREFIX
	JR	NC,FCLN_IS_LINE		; No prefix at start -> line colon

	; Prefix matched: HL is now past the prefix colon!
	POP	DE			; DE = colon pointer
	PUSH	DE
	LD	A,D
	CP	H
	JR	NZ,FCLN_CMP
	LD	A,E
	CP	L
FCLN_CMP:
	JR	C,FCLN_IS_DRIVE		; DE < HL -> colon is part of prefix!

FCLN_IS_LINE:
	POP	HL			; Restore colon pointer
	INC	HL			; HL points to digits
	CALL	PARSE_DEC_WORD		; DE = 16-bit parsed value
	LD	(CMDLINE_GOTO_LINE),DE
	RET

FCLN_IS_DRIVE:
	POP	HL			; Restore colon pointer
	RET

; Helper: Return Carry=1 if A is 'A'..'Z' or 'a'..'z'
IS_ALPHA_CHAR:
	CP	'A'
	JR	C,NOT_ALPHA
	CP	'Z'+1
	JR	C,IS_ALPHA
	CP	'a'
	JR	C,NOT_ALPHA
	CP	'z'+1
	JR	NC,NOT_ALPHA
IS_ALPHA:
	SCF
	RET
NOT_ALPHA:
	OR	A
	RET

;------------------------------------------------------------------------------
; Splash Screen Renderer (Vim Style)
; Dynamically centered both horizontally and vertically for active screen geometry.
;; Total menu lines: 19
;------------------------------------------------------------------------------
SPLASH_MENU_LINES	EQU	19

;------------------------------------------------------------------------------
; PRINT_TILDE_CRLF: Print '~' followed by CRLF
; Preserves: All registers except AF
;------------------------------------------------------------------------------
PRINT_TILDE_CRLF:
	LD	A,'~'
	CALL	PUTC
	LD	A,13
	CALL	PUTC
	LD	A,10
	CALL	PUTC
	RET

;------------------------------------------------------------------------------
; PRINT_SPLASH_PREFIX: Print '~' followed by geometry-dependent left padding
; Total visual block width: 41 columns.
; 80x24: 19 spaces left padding (19 + 41 = 60 columns).
; 120x40: 39 spaces left padding (39 + 41 = 80 columns).
; Preserves: All registers except AF and BC
;------------------------------------------------------------------------------
PRINT_SPLASH_PREFIX:
	LD	A,'~'
	CALL	PUTC
	LD	A,(SCREEN_MODE)
	CP	MODE_120X40
	JR	NZ,PSP_80X24
	LD	B,39
	JR	PSP_LOOP
PSP_80X24:
	LD	B,19
PSP_LOOP:
	LD	A,' '
	CALL	PUTC
	DJNZ	PSP_LOOP
	RET

RENDER_SPLASH:
	LD	A,1
	LD	(IS_SPLASH_SCREEN),A
	LD	DE,STR_HIDE_CURSOR
	CALL	PRINT_STR
	LD	DE,STR_CLEAR_SCREEN
	CALL	PRINT_STR

	; Calculate vertical top padding: ((ACTIVE_ROWS - 1) - SPLASH_MENU_LINES) / 2
	LD	A,(ACTIVE_ROWS)
	DEC	A			; Text rows available (23 in 80x24, 39 in 120x40)
	SUB	SPLASH_MENU_LINES	; 23 - 17 = 6 (80x24), 39 - 17 = 22
	JR	Z,SPLASH_NO_TOP_PAD
	JR	C,SPLASH_NO_TOP_PAD
	SRL	A			; 2 (80x24), 10 (120x40)
	JR	Z,SPLASH_NO_TOP_PAD
	LD	(SPLASH_TOP_PAD_COUNT),A
	LD	B,A
SPLASH_TOP_PAD_LOOP:
	CALL	PRINT_TILDE_CRLF
	DJNZ	SPLASH_TOP_PAD_LOOP
	JR	SPLASH_CONTENT_START

SPLASH_NO_TOP_PAD:
	XOR	A
	LD	(SPLASH_TOP_PAD_COUNT),A

SPLASH_CONTENT_START:
	; Row 1: Title (centered within 41-col block with 11 spaces)
	CALL	PRINT_SPLASH_PREFIX
	LD	DE,STR_SPLASH_TITLE_PAD
	CALL	PRINT_STR
	LD	DE,STR_SPLASH_TITLE
	CALL	PRINT_STR

	; Row 2: Blank line
	CALL	PRINT_TILDE_CRLF

	; Rows 3..15: 13 Commands
	LD	HL,STR_SPLASH_CMDS
SPLASH_CMDS_LINE:
	LD	A,(HL)
	OR	A
	JR	Z,SPLASH_CMDS_DONE
	CALL	PRINT_SPLASH_PREFIX
SPLASH_CMDS_CHAR:
	LD	A,(HL)
	INC	HL
	CALL	PUTC
	CP	10			; LF reached?
	JR	NZ,SPLASH_CMDS_CHAR
	JR	SPLASH_CMDS_LINE
SPLASH_CMDS_DONE:

	; Row 16: Blank line
	CALL	PRINT_TILDE_CRLF

	; Row 17: Active Screen Mode
	CALL	PRINT_SPLASH_PREFIX
	LD	DE,STR_SPLASH_CUR_MODE
	CALL	PRINT_STR

	LD	A,(SCREEN_MODE)
	CP	MODE_120X40
	JR	NZ,SHOW_SPLASH_80X24
	LD	DE,STR_SPLASH_120X40_LBL
	CALL	PRINT_STR
	JR	RENDER_SPLASH_RAM_STATUS

SHOW_SPLASH_80X24:
	LD	DE,STR_SPLASH_80X24_LBL
	CALL	PRINT_STR

RENDER_SPLASH_RAM_STATUS:
	; Row 18: RAM Drive Status
	CALL	PRINT_SPLASH_PREFIX
	LD	A,(RAMDRIVE_DRIVE_NUM)
	CP	0FFH
	JR	Z,SPLASH_RAM_NONE

	LD	DE,STR_SPLASH_RAM_PRE
	CALL	PRINT_STR

	LD	A,(RAMDRIVE_IS_HIBERNATED)
	OR	A
	JR	NZ,SPLASH_RAM_HIB

	LD	A,(CFG_RAMDRIVE_FLAG)
	CP	RAMDRV_MODE_ENABLED
	JR	Z,SPLASH_RAM_OVW

	LD	DE,STR_SPLASH_RAM_PRESERV
	CALL	PRINT_STR
	JR	RENDER_SPLASH_PLUG_STATUS

SPLASH_RAM_HIB:
	LD	DE,STR_SPLASH_RAM_HIBERN
	CALL	PRINT_STR
	JR	RENDER_SPLASH_PLUG_STATUS

SPLASH_RAM_OVW:
	LD	DE,STR_SPLASH_RAM_OVERWR
	CALL	PRINT_STR
	JR	RENDER_SPLASH_PLUG_STATUS

SPLASH_RAM_NONE:
	LD	DE,STR_SPLASH_RAM_NONE
	CALL	PRINT_STR

RENDER_SPLASH_PLUG_STATUS:
	; Row 19: Plugin System Status
	CALL	PRINT_SPLASH_PREFIX
	LD	DE,STR_SPLASH_PLUG_PRE
	CALL	PRINT_STR

	LD	A,(PLUGIN_MGR_LOADED)
	OR	A
	JR	NZ,SPLASH_PLUG_OPERATIONAL

	; Not loaded: check Far RAM availability (EXT_BANK_COUNT >= 2)
	LD	A,(EXT_BANK_COUNT)
	CP	2
	JR	C,SPLASH_PLUG_DISABLED

	; Far RAM is available: check if disabled in config
	LD	A,(CFG_AUTOLOAD_PLUGIN_MGR)
	OR	A
	JR	Z,SPLASH_PLUG_DISABLED

	; Subsystem enabled (Autoload/On Demand), but not resident -> On Demand
	LD	DE,STR_SPLASH_PLUG_ONDEMAND
	CALL	PRINT_STR
	JR	RENDER_SPLASH_BOTTOM_PAD

SPLASH_PLUG_OPERATIONAL:
	LD	DE,STR_SPLASH_PLUG_OPERATIONAL
	CALL	PRINT_STR
	JR	RENDER_SPLASH_BOTTOM_PAD

SPLASH_PLUG_DISABLED:
	LD	DE,STR_SPLASH_PLUG_DISABLED
	CALL	PRINT_STR

RENDER_SPLASH_BOTTOM_PAD:
	; Bottom padding: (ACTIVE_ROWS - 1) - SPLASH_TOP_PAD_COUNT - SPLASH_MENU_LINES
	LD	A,(ACTIVE_ROWS)
	DEC	A			; Text rows available
	LD	HL,SPLASH_TOP_PAD_COUNT
	SUB	(HL)
	SUB	SPLASH_MENU_LINES
	JR	Z,SPLASH_BOTTOM_DONE
	JR	C,SPLASH_BOTTOM_DONE
	LD	B,A
SPLASH_BOTTOM_LOOP:
	CALL	PRINT_TILDE_CRLF
	DJNZ	SPLASH_BOTTOM_LOOP

SPLASH_BOTTOM_DONE:
	CALL	RENDER_STATUS_BAR
	LD	DE,STR_HOME
	CALL	PRINT_STR
	LD	DE,STR_HIDE_CURSOR
	CALL	PRINT_STR
	RET

;------------------------------------------------------------------------------
; About Screen Renderer
; Dynamically centered both horizontally and vertically for active screen geometry.
; Displays essential project, version, author, tools, and MIT license details.
;------------------------------------------------------------------------------
ABOUT_MENU_LINES	EQU	9

;------------------------------------------------------------------------------
; PRINT_ABOUT_LINE: Print '~', center the string at DE horizontally, then CRLF
; In: DE = pointer to '$' or null-terminated string
; Calculates string length, computes padding = ((ACTIVE_COLS - 1 - length) / 2)
; Emits '~', padding spaces, string, and CRLF
; Preserves: All registers
;------------------------------------------------------------------------------
PRINT_ABOUT_LINE:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL

	PUSH	DE
	POP	HL			; HL = string pointer
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
	CALL	PUTC

	LD	A,(ACTIVE_COLS)
	DEC	A			; Columns remaining after '~'
	SUB	B			; Subtract length in B
	JR	C,PAL_NO_PAD		; If string longer than remaining cols, no pad
	SRL	A			; Divide by 2 for symmetrical left margin
	JR	Z,PAL_NO_PAD
	LD	B,A
PAL_PAD_LOOP:
	LD	A,' '
	CALL	PUTC
	DJNZ	PAL_PAD_LOOP

PAL_NO_PAD:
	CALL	PRINT_STR
	LD	A,13
	CALL	PUTC
	LD	A,10
	CALL	PUTC

	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

SHOW_ABOUT_SCREEN:
	LD	A,1
	LD	(IS_SPLASH_SCREEN),A
	LD	DE,STR_HIDE_CURSOR
	CALL	PRINT_STR
	LD	DE,STR_CLEAR_SCREEN
	CALL	PRINT_STR

	; Calculate vertical top padding: ((ACTIVE_ROWS - 1) - ABOUT_MENU_LINES) / 2
	LD	A,(ACTIVE_ROWS)
	DEC	A			; Text rows available (23 in 80x24, 39 in 120x40)
	SUB	ABOUT_MENU_LINES	; 23 - 9 = 14 (80x24), 39 - 9 = 30 (120x40)
	JR	Z,ABOUT_NO_TOP_PAD
	JR	C,ABOUT_NO_TOP_PAD
	SRL	A			; 7 in 80x24, 15 in 120x40
	JR	Z,ABOUT_NO_TOP_PAD
	LD	(ABOUT_TOP_PAD_COUNT),A
	LD	B,A
ABOUT_TOP_PAD_LOOP:
	CALL	PRINT_TILDE_CRLF
	DJNZ	ABOUT_TOP_PAD_LOOP
	JR	ABOUT_CONTENT_START

ABOUT_NO_TOP_PAD:
	XOR	A
	LD	(ABOUT_TOP_PAD_COUNT),A

ABOUT_CONTENT_START:
	; Row 1: Title
	LD	DE,STR_ABOUT_TITLE
	CALL	PRINT_ABOUT_LINE

	; Row 2: Version
	LD	DE,STR_ABOUT_VERSION
	CALL	PRINT_ABOUT_LINE

	; Row 3: Author
	LD	DE,STR_ABOUT_AUTHOR
	CALL	PRINT_ABOUT_LINE

	; Row 4: Blank line
	CALL	PRINT_TILDE_CRLF

	; Row 5: AI & environment attribution
	LD	DE,STR_ABOUT_AI
	CALL	PRINT_ABOUT_LINE

	; Row 6: Blank line
	CALL	PRINT_TILDE_CRLF

	; Row 7: MIT License
	LD	DE,STR_ABOUT_LICENSE
	CALL	PRINT_ABOUT_LINE

	; Row 8: Blank line
	CALL	PRINT_TILDE_CRLF

	; Row 9: Return prompt
	LD	DE,STR_ABOUT_RETURN
	CALL	PRINT_ABOUT_LINE

	; Bottom padding: (ACTIVE_ROWS - 1) - ABOUT_TOP_PAD_COUNT - ABOUT_MENU_LINES
	LD	A,(ACTIVE_ROWS)
	DEC	A			; Text rows available
	LD	HL,ABOUT_TOP_PAD_COUNT
	SUB	(HL)
	SUB	ABOUT_MENU_LINES
	JR	Z,ABOUT_BOTTOM_DONE
	JR	C,ABOUT_BOTTOM_DONE
	LD	B,A
ABOUT_BOTTOM_LOOP:
	CALL	PRINT_TILDE_CRLF
	DJNZ	ABOUT_BOTTOM_LOOP

ABOUT_BOTTOM_DONE:
	CALL	RENDER_STATUS_BAR
	LD	DE,STR_HOME
	CALL	PRINT_STR
	LD	DE,STR_HIDE_CURSOR
	CALL	PRINT_STR
	RET

;------------------------------------------------------------------------------
; Configuration Screen Renderer
; Displays active screen geometry, config file status, and adjustment commands
;------------------------------------------------------------------------------
;------------------------------------------------------------------------------
; Configuration Screen Renderer (SHOW_CONFIG_SCREEN)
; Dynamically centered both horizontally and vertically for active screen geometry.
; Option order:
;   Config Status (at top, unnumbered status)
;   1. Screen Geometry
;   2. RAM Drive
;   3. Max Doc Lines
;   4. Tab Width
;   5. Plugin Manager
; Total menu lines: 18
;------------------------------------------------------------------------------
CONFIG_MENU_LINES	EQU	18

;------------------------------------------------------------------------------
; PRINT_CONFIG_PREFIX: Print '~' followed by geometry-dependent left padding
; Padding: ((ACTIVE_COLS - 59) / 2) spaces
; 80x24:  10 spaces
; 120x40: 30 spaces
; Preserves: All registers except AF
;------------------------------------------------------------------------------
PRINT_CONFIG_PREFIX:
	PUSH	BC
	LD	A,'~'
	CALL	PUTC
	LD	A,(ACTIVE_COLS)
	SUB	59
	SRL	A
	JR	Z,PCP_DONE
	LD	B,A
PCP_LOOP:
	LD	A,' '
	CALL	PUTC
	DJNZ	PCP_LOOP
PCP_DONE:
	POP	BC
	RET

;------------------------------------------------------------------------------
; PRINT_CONFIG_BLANK_LINE: Print '~' followed by CRLF
; Preserves: All registers except AF
;------------------------------------------------------------------------------
PRINT_CONFIG_BLANK_LINE:
	LD	A,'~'
	CALL	PUTC
	LD	A,13
	CALL	PUTC
	LD	A,10
	CALL	PUTC
	RET

SHOW_CONFIG_SCREEN:
	LD	A,1
	LD	(IS_SPLASH_SCREEN),A
	LD	DE,STR_HIDE_CURSOR
	CALL	PRINT_STR
	LD	DE,STR_CLEAR_SCREEN
	CALL	PRINT_STR

	; Calculate vertical top padding: ((ACTIVE_ROWS - 1) - CONFIG_MENU_LINES) / 2
	LD	A,(ACTIVE_ROWS)
	DEC	A			; Text rows available
	SUB	CONFIG_MENU_LINES
	JR	Z,SCS_NO_TOP_PAD
	JR	C,SCS_NO_TOP_PAD
	SRL	A
	JR	Z,SCS_NO_TOP_PAD
	LD	(SCS_TOP_PAD_COUNT),A
	LD	B,A
SCS_TOP_PAD_LOOP:
	CALL	PRINT_CONFIG_BLANK_LINE
	DJNZ	SCS_TOP_PAD_LOOP
	JR	SCS_MENU_START

SCS_NO_TOP_PAD:
	XOR	A
	LD	(SCS_TOP_PAD_COUNT),A

SCS_MENU_START:
	; Row 1: Title (centered within 58-char block with 13 spaces)
	CALL	PRINT_CONFIG_PREFIX
	LD	DE,STR_CONFIG_TITLE_PAD
	CALL	PRINT_STR
	LD	DE,STR_CONFIG_TITLE
	CALL	PRINT_STR

	; Row 2: Blank line
	CALL	PRINT_CONFIG_BLANK_LINE

	; Row 3: Config Status (at top, unnumbered)
	CALL	PRINT_CONFIG_PREFIX
	LD	DE,STR_CONFIG_STATUS_LBL
	CALL	PRINT_STR
	LD	A,(CONFIG_STATUS_FLAG)
	CP	1
	JR	Z,SCS_STAT_LOCAL
	CP	2
	JR	Z,SCS_STAT_PROG
	CP	3
	JR	Z,SCS_STAT_SAVED
	CP	4
	JR	Z,SCS_STAT_ERR

	; Default / None
	LD	DE,STR_CFG_STAT_NONE
	CALL	PRINT_STR
	JR	SCS_AFTER_STATUS

SCS_STAT_LOCAL:
	LD	DE,STR_CFG_STAT_LOCAL
	CALL	PRINT_STR
	LD	A,(CONFIG_SOURCE_DRIVE)
	ADD	A,'A'
	CALL	PUTC
	LD	DE,STR_CFG_STAT_END
	CALL	PRINT_STR
	JR	SCS_AFTER_STATUS

SCS_STAT_PROG:
	LD	DE,STR_CFG_STAT_PROG
	CALL	PRINT_STR
	LD	A,(CONFIG_SOURCE_DRIVE)
	ADD	A,'A'
	CALL	PUTC
	LD	DE,STR_CFG_STAT_END
	CALL	PRINT_STR
	JR	SCS_AFTER_STATUS

SCS_STAT_SAVED:
	LD	DE,STR_CFG_STAT_SAVED
	CALL	PRINT_STR
	LD	A,(CONFIG_SOURCE_DRIVE)
	ADD	A,'A'
	CALL	PUTC
	LD	DE,STR_CFG_STAT_END
	CALL	PRINT_STR
	JR	SCS_AFTER_STATUS

SCS_STAT_ERR:
	LD	DE,STR_CFG_STAT_ERR
	CALL	PRINT_STR

SCS_AFTER_STATUS:
	; Row 4: Blank line
	CALL	PRINT_CONFIG_BLANK_LINE

	; Row 5: 1. Screen Geometry
	CALL	PRINT_CONFIG_PREFIX
	LD	DE,STR_CONFIG_CUR_MODE
	CALL	PRINT_STR
	LD	A,(SCREEN_MODE)
	CP	MODE_120X40
	JR	NZ,SCS_80X24
	LD	DE,STR_MODE_120X40_LBL
	CALL	PRINT_STR
	JR	SCS_RAM_MODE
SCS_80X24:
	LD	DE,STR_MODE_80X24_LBL
	CALL	PRINT_STR

SCS_RAM_MODE:
	; Row 6: 2. RAM Drive
	CALL	PRINT_CONFIG_PREFIX
	LD	A,(RAMDRIVE_DRIVE_NUM)
	CP	0FFH
	JR	Z,SCS_RAM_NO_LETTER
	LD	DE,STR_CONFIG_RAM_DRV_PRE
	CALL	PRINT_STR
	LD	A,(RAMDRIVE_DRIVE_CHAR)
	CALL	PUTC
	LD	DE,STR_CONFIG_RAM_DRV_POST
	CALL	PRINT_STR
	JR	SCS_RAM_VALUE

SCS_RAM_NO_LETTER:
	LD	DE,STR_CONFIG_RAM_NONE
	CALL	PRINT_STR

SCS_RAM_VALUE:
	LD	A,(CFG_RAMDRIVE_FLAG)
	CP	RAMDRV_MODE_HIBERNATE
	JR	Z,SCS_RAM_HIB
	CP	RAMDRV_MODE_ENABLED
	JR	Z,SCS_RAM_ENABLED
	LD	DE,STR_RAM_PROTECTED_LBL
	CALL	PRINT_STR
	JR	SCS_LINES_MODE
SCS_RAM_HIB:
	LD	DE,STR_RAM_HIBERNATE_LBL
	CALL	PRINT_STR
	JR	SCS_LINES_MODE
SCS_RAM_ENABLED:
	LD	DE,STR_RAM_ENABLED_LBL
	CALL	PRINT_STR

SCS_LINES_MODE:
	; Row 7: 3. Max Doc Lines (grouped with RAM Drive!)
	CALL	PRINT_CONFIG_PREFIX
	LD	DE,STR_CONFIG_LINES_LBL
	CALL	PRINT_STR
	LD	A,(CFG_LINES_MODE)
	CP	1
	JR	Z,SCS_LINES_32K
	LD	DE,STR_LINES_16K_LBL
	CALL	PRINT_STR
	JR	SCS_TAB_MODE
SCS_LINES_32K:
	LD	DE,STR_LINES_32K_LBL
	CALL	PRINT_STR

SCS_TAB_MODE:
	; Row 8: 4. Tab Width (at the bottom!)
	CALL	PRINT_CONFIG_PREFIX
	LD	DE,STR_CONFIG_TAB_LBL
	CALL	PRINT_STR
	LD	A,(CFG_TAB_WIDTH)
	CP	4
	JR	Z,SCS_TAB_4
	LD	DE,STR_TAB_8_LBL
	CALL	PRINT_STR
	JR	SCS_PLUG_MODE
SCS_TAB_4:
	LD	DE,STR_TAB_4_LBL
	CALL	PRINT_STR

SCS_PLUG_MODE:
	; Row 9: 5. Plugin Manager
	CALL	PRINT_CONFIG_PREFIX
	LD	DE,STR_CONFIG_PLUG_LBL
	CALL	PRINT_STR

	; Check Far RAM: if currently loaded, Far RAM was already verified
	LD	A,(PLUGIN_MGR_LOADED)
	OR	A
	JR	NZ,SCS_PLUG_CHECK_MODE

	; Not loaded: check if Far RAM is insufficient (< 2 banks)
	LD	A,(EXT_BANK_COUNT)
	CP	2
	JR	C,SCS_PLUG_NO_FAR

SCS_PLUG_CHECK_MODE:
	LD	A,(CFG_AUTOLOAD_PLUGIN_MGR)
	CP	PLUGIN_MODE_AUTOLOAD
	JR	Z,SCS_PLUG_AUTOLOAD
	CP	PLUGIN_MODE_ONDEMAND
	JR	Z,SCS_PLUG_ONDEMAND

	; Disabled by configuration
	LD	DE,STR_PLUG_DIS_LBL
	CALL	PRINT_STR
	JR	SCS_CMDS_BLOCK

SCS_PLUG_ONDEMAND:
	LD	DE,STR_PLUG_ONDEMAND_LBL
	CALL	PRINT_STR
	JR	SCS_CMDS_BLOCK

SCS_PLUG_NO_FAR:
	LD	DE,STR_PLUG_NO_FAR_LBL
	CALL	PRINT_STR
	JR	SCS_CMDS_BLOCK

SCS_PLUG_AUTOLOAD:
	LD	DE,STR_PLUG_AUTO_LBL
	CALL	PRINT_STR

SCS_CMDS_BLOCK:
	; Blank line
	CALL	PRINT_CONFIG_BLANK_LINE

	; Commands
	CALL	PRINT_CONFIG_PREFIX
	LD	DE,STR_CMD_HEADER
	CALL	PRINT_STR

	CALL	PRINT_CONFIG_PREFIX
	LD	DE,STR_CMD_1
	CALL	PRINT_STR

	CALL	PRINT_CONFIG_PREFIX
	LD	DE,STR_CMD_2
	CALL	PRINT_STR

	CALL	PRINT_CONFIG_PREFIX
	LD	DE,STR_CMD_3
	CALL	PRINT_STR

	CALL	PRINT_CONFIG_PREFIX
	LD	DE,STR_CMD_4
	CALL	PRINT_STR

	CALL	PRINT_CONFIG_PREFIX
	LD	DE,STR_CMD_5
	CALL	PRINT_STR

	CALL	PRINT_CONFIG_PREFIX
	LD	DE,STR_CMD_S
	CALL	PRINT_STR

	CALL	PRINT_CONFIG_PREFIX
	LD	DE,STR_CMD_Q
	CALL	PRINT_STR

	; Calculate bottom padding: (ACTIVE_ROWS - 1) - (SCS_TOP_PAD_COUNT + CONFIG_MENU_LINES)
	LD	A,(SCS_TOP_PAD_COUNT)
	ADD	A,CONFIG_MENU_LINES
	LD	B,A
	LD	A,(ACTIVE_ROWS)
	DEC	A
	SUB	B
	JR	Z,CONFIG_TILDE_DONE
	JR	C,CONFIG_TILDE_DONE
	LD	B,A
CONFIG_TILDE_LOOP:
	CALL	PRINT_CONFIG_BLANK_LINE
	DJNZ	CONFIG_TILDE_LOOP

CONFIG_TILDE_DONE:
	CALL	RENDER_STATUS_BAR
	LD	DE,STR_HOME
	CALL	PRINT_STR
	LD	DE,STR_HIDE_CURSOR
	CALL	PRINT_STR
	RET

;------------------------------------------------------------------------------
; QUERY_MEM_SCREEN_INFO: Dynamic detection of CP/M and HBIOS parameters
; Called prior to rendering the memory information screen.
;------------------------------------------------------------------------------
QUERY_MEM_SCREEN_INFO:
	; 1. Query CP/M Version via BDOS 12
	LD	C,12			; BDOS Get Version Number
	CALL	BDOS_ENTRY
	LD	(CPM_VERSION_ID),HL

	; 2. Check HBIOS presence
	CALL	HBIOS_DETECT
	JR	Z,QMSI_HBIOS_OK
	; Non-HBIOS fallback
	XOR	A
	LD	(HBIOS_PRESENT),A
	RET

QMSI_HBIOS_OK:
	LD	A,1
	LD	(HBIOS_PRESENT),A

	; Query HBIOS Version (BF_SYSVER = 0xF1)
	PUSH	IX
	LD	B,0F1H			; BF_SYSVER
	LD	C,000H
	RST	08H
	POP	IX
	; DE has version in BCD: D = Major << 4 | Minor, E = Update << 4 | Patch
	LD	A,D
	RRCA
	RRCA
	RRCA
	RRCA
	AND	0FH
	LD	(HBIOS_VER_MAJ),A
	LD	A,D
	AND	0FH
	LD	(HBIOS_VER_MIN),A
	LD	A,E
	RRCA
	RRCA
	RRCA
	RRCA
	AND	0FH
	LD	(HBIOS_VER_PATCH),A

	; Query BIOS Bank ID (SYSGET 0xF2)
	PUSH	IX
	LD	B,0F8H
	LD	C,0F2H
	RST	08H
	POP	IX
	LD	A,D
	OR	A
	JR	NZ,QMSI_GOT_BIOS_BANK
	LD	A,080H
QMSI_GOT_BIOS_BANK:
	LD	(HBIOS_BIOS_BANK),A

	; Query App Banks (SYSGET 0xF5)
	PUSH	IX
	LD	B,0F8H
	LD	C,0F5H			; BF_SYSGET_APPBNKS
	RST	08H
	POP	IX
	OR	A
	JR	NZ,QMSI_SAVE_APP_DEFAULT
	LD	A,H
	CP	0FFH
	JR	Z,QMSI_SAVE_APP_DEFAULT
	LD	(HBIOS_APP_BANK),A
	LD	A,L
	LD	(HBIOS_APP_COUNT),A
	RET

QMSI_SAVE_APP_DEFAULT:
	LD	A,089H
	LD	(HBIOS_APP_BANK),A
	LD	A,3
	LD	(HBIOS_APP_COUNT),A
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
PRINT_MEM_PREFIX:
	PUSH	BC
	LD	A,'~'
	CALL	PUTC
	LD	A,(ACTIVE_COLS)
	SUB	74
	JR	C,PMP_DONE
	JR	Z,PMP_DONE
	SRL	A
	JR	Z,PMP_DONE
	LD	B,A
PMP_LOOP:
	LD	A,' '
	CALL	PUTC
	DJNZ	PMP_LOOP
PMP_DONE:
	POP	BC
	RET

MEM_INFO_LINES	EQU	23

SHOW_MEM_INFO_SCREEN:
	CALL	QUERY_MEM_SCREEN_INFO
	LD	A,1
	LD	(IS_SPLASH_SCREEN),A
	LD	DE,STR_HIDE_CURSOR
	CALL	PRINT_STR
	LD	DE,STR_CLEAR_SCREEN
	CALL	PRINT_STR

	; Calculate vertical top padding: ((ACTIVE_ROWS - 1) - MEM_INFO_LINES) / 2
	LD	A,(ACTIVE_ROWS)
	DEC	A			; Text rows available (23 in 80x24, 39 in 120x40)
	SUB	MEM_INFO_LINES		; 23 - 23 = 0 (80x24), 39 - 23 = 16 (120x40)
	JR	Z,MEM_INFO_NO_TOP_PAD
	JR	C,MEM_INFO_NO_TOP_PAD
	SRL	A			; 0 (80x24), 8 (120x40)
	JR	Z,MEM_INFO_NO_TOP_PAD
	LD	(MEM_TOP_PAD_COUNT),A
	LD	B,A
MEM_INFO_TOP_PAD_LOOP:
	CALL	PRINT_TILDE_CRLF
	DJNZ	MEM_INFO_TOP_PAD_LOOP
	JR	MEM_INFO_CONTENT_START

MEM_INFO_NO_TOP_PAD:
	XOR	A
	LD	(MEM_TOP_PAD_COUNT),A

MEM_INFO_CONTENT_START:
	; Line 1: Title (centered within 72-col block)
	CALL	PRINT_MEM_PREFIX
	LD	DE,STR_MEM_TITLE_PAD
	CALL	PRINT_STR
	LD	DE,STR_MEM_INFO_TITLE
	CALL	PRINT_STR

	; Line 2: System Summary Line
	CALL	PRINT_MEM_INFO_SUMMARY

	; Line 3: Blank line with tilde
	CALL	PRINT_TILDE_CRLF

	; Line 4: Table column headers
	CALL	PRINT_MEM_PREFIX
	LD	DE,STR_MEM_TABLE_HDR
	CALL	PRINT_STR

	; Line 5: Table column dividers
	CALL	PRINT_MEM_PREFIX
	LD	DE,STR_MEM_TABLE_DIV
	CALL	PRINT_STR

	; Lines 6..21: The 16 individual bank rows (Banks 00 through 15)
	XOR	A
	LD	(MEM_BANK_LOOP_IDX),A
MEM_BANK_ROW_LOOP:
	CALL	PRINT_MEM_BANK_ROW
	LD	A,(MEM_BANK_LOOP_IDX)
	INC	A
	LD	(MEM_BANK_LOOP_IDX),A
	CP	16
	JR	C,MEM_BANK_ROW_LOOP

	; Line 22: Blank line with tilde
	CALL	PRINT_TILDE_CRLF

	; Line 23: Return prompt (centered within 72-col block)
	CALL	PRINT_MEM_PREFIX
	LD	DE,STR_MEM_PROMPT_PAD
	CALL	PRINT_STR
	LD	DE,STR_MEM_RETURN_PROMPT
	CALL	PRINT_STR

	; Calculate bottom padding: (ACTIVE_ROWS - 1) - MEM_TOP_PAD_COUNT - MEM_INFO_LINES
	LD	A,(ACTIVE_ROWS)
	DEC	A			; Text rows available (23 in 80x24, 39 in 120x40)
	LD	HL,MEM_TOP_PAD_COUNT
	SUB	(HL)
	SUB	MEM_INFO_LINES		; Remaining bottom padding
	JR	Z,MEM_INFO_BOTTOM_DONE
	JR	C,MEM_INFO_BOTTOM_DONE
	LD	B,A
MEM_INFO_BOTTOM_LOOP:
	CALL	PRINT_TILDE_CRLF
	DJNZ	MEM_INFO_BOTTOM_LOOP

MEM_INFO_BOTTOM_DONE:
	CALL	RENDER_STATUS_BAR
	LD	DE,STR_HOME
	CALL	PRINT_STR
	LD	DE,STR_HIDE_CURSOR
	CALL	PRINT_STR
	RET

;------------------------------------------------------------------------------
; PRINT_MEM_INFO_SUMMARY: Print system summary row (HBIOS, OS, RAM, SE RAM)
;------------------------------------------------------------------------------
PRINT_MEM_INFO_SUMMARY:
	CALL	PRINT_MEM_PREFIX
	LD	DE,STR_MEM_SUM_PREFIX
	CALL	PRINT_STR

	LD	A,(HBIOS_PRESENT)
	OR	A
	JR	NZ,PMIS_HBIOS_YES
	LD	DE,STR_MEM_SUM_NONE
	CALL	PRINT_STR
	JR	PMIS_SHOW_OS

PMIS_HBIOS_YES:
	LD	DE,STR_MEM_SUM_ROMWBW
	CALL	PRINT_STR
	LD	A,(HBIOS_VER_MAJ)
	CALL	PRINT_DEC_BYTE
	LD	A,'.'
	CALL	PUTC
	LD	A,(HBIOS_VER_MIN)
	CALL	PRINT_DEC_BYTE

PMIS_SHOW_OS:
	LD	DE,STR_MEM_SUM_OS
	CALL	PRINT_STR

	LD	HL,(CPM_VERSION_ID)
	LD	A,H
	CP	014H
	JR	Z,PMIS_OS_ZSYS
	LD	A,L
	CP	031H
	JR	Z,PMIS_OS_CPM31
	CP	030H
	JR	Z,PMIS_OS_CPM30
	LD	DE,STR_OS_CPM22
	JR	PMIS_PRINT_OS
PMIS_OS_ZSYS:
	LD	DE,STR_OS_ZSYS
	JR	PMIS_PRINT_OS
PMIS_OS_CPM31:
	LD	DE,STR_OS_CPM31
	JR	PMIS_PRINT_OS
PMIS_OS_CPM30:
	LD	DE,STR_OS_CPM30
PMIS_PRINT_OS:
	CALL	PRINT_STR

	LD	DE,STR_MEM_SUM_RAM
	CALL	PRINT_STR

	LD	A,(HBIOS_PRESENT)
	OR	A
	JR	NZ,PMIS_RAM_HBIOS
	LD	DE,STR_MEM_SUM_RAM_BASE
	CALL	PRINT_STR
	JR	PMIS_SHOW_SE

PMIS_RAM_HBIOS:
	LD	A,(RAM_BANK_COUNT)
	LD	L,A
	LD	H,0
	ADD	HL,HL			; x2
	ADD	HL,HL			; x4
	ADD	HL,HL			; x8
	ADD	HL,HL			; x16
	ADD	HL,HL			; x32 (KB)
	CALL	PRINT_DEC_WORD
	LD	DE,STR_MEM_SUM_KB_MID
	CALL	PRINT_STR
	LD	A,(RAM_BANK_COUNT)
	CALL	PRINT_DEC_BYTE
	LD	DE,STR_MEM_SUM_X32K
	CALL	PRINT_STR

PMIS_SHOW_SE:
	LD	DE,STR_MEM_SUM_SE
	CALL	PRINT_STR

	LD	A,(HBIOS_PRESENT)
	OR	A
	JR	NZ,PMIS_SE_HBIOS
	LD	DE,STR_MEM_SUM_64K_END
	CALL	PRINT_STR
	RET

PMIS_SE_HBIOS:
	; Calculate SE RAM: (1 [TPA] + (1 if LINE_TABLE_BANK!=0) + (1 if LINE_TABLE_BANK_1!=0) + EXT_BANK_COUNT) * 32
	LD	A,1
	LD	HL,LINE_TABLE_BANK
	LD	B,(HL)
	INC	B
	DEC	B
	JR	Z,PMIS_NO_LINE_BANK_0
	INC	A			; A = 2
PMIS_NO_LINE_BANK_0:
	LD	HL,LINE_TABLE_BANK_1
	LD	B,(HL)
	INC	B
	DEC	B
	JR	Z,PMIS_NO_LINE_BANK_1
	INC	A			; A = 3
PMIS_NO_LINE_BANK_1:
	LD	HL,PLUGIN_MGR_LOADED
	LD	B,(HL)
	INC	B
	DEC	B
	JR	Z,PMIS_NO_PLUG_BANK
	INC	A
PMIS_NO_PLUG_BANK:
	LD	HL,EXT_BANK_COUNT
	ADD	A,(HL)			; A = total SE 32KB banks
	LD	L,A
	LD	H,0
	ADD	HL,HL			; x2
	ADD	HL,HL			; x4
	ADD	HL,HL			; x8
	ADD	HL,HL			; x16
	ADD	HL,HL			; x32 (KB)
	CALL	PRINT_DEC_WORD
	LD	DE,STR_MEM_SUM_KB_END
	CALL	PRINT_STR
	RET

;------------------------------------------------------------------------------
; PRINT_MEM_BANK_ROW: Print single bank row for MEM_BANK_LOOP_IDX (0..15)
;------------------------------------------------------------------------------
PRINT_MEM_BANK_ROW:
	; Column 0 Tilde and geometry padding
	CALL	PRINT_MEM_PREFIX

	; 2-Digit Decimal Bank Index (00..15)
	LD	A,(MEM_BANK_LOOP_IDX)
	CALL	PRINT_2DIGIT_DEC

	; 4 spaces (align under 'Bank  ')
	LD	DE,STR_MEM_SPACES_4
	CALL	PRINT_STR

	; Physical Bank ID (80h..8Fh)
	LD	A,(MEM_BANK_LOOP_IDX)
	ADD	A,080H
	CALL	PRINT_HEX_BYTE
	LD	A,'h'
	CALL	PUTC

	; 4 spaces (align under 'Phys   ')
	LD	DE,STR_MEM_SPACES_4
	CALL	PRINT_STR

	; Check if bank is installed
	LD	A,(HBIOS_PRESENT)
	OR	A
	JR	NZ,PMBR_CHECK_RAM_COUNT

	; Non-HBIOS check: Only Bank 0 is base memory
	LD	A,(MEM_BANK_LOOP_IDX)
	OR	A
	JP	NZ,PMBR_NOT_INSTALLED
	; Bank 00 non-HBIOS: 64K TPA
	LD	DE,STR_MEM_SIZE_64K
	CALL	PRINT_STR
	LD	DE,STR_MEM_SPACES_3
	CALL	PRINT_STR
	LD	DE,STR_ROLE_TPA_CPM2
	CALL	PRINT_STR
	LD	DE,STR_MEM_SPACES_3
	CALL	PRINT_STR
	LD	DE,STR_USAGE_SE_PROG
	CALL	PRINT_STR
	CALL	PRINT_CRLF
	RET

PMBR_CHECK_RAM_COUNT:
	LD	A,(MEM_BANK_LOOP_IDX)
	LD	HL,RAM_BANK_COUNT
	CP	(HL)
	JP	NC,PMBR_NOT_INSTALLED

	; Bank is installed: print "32K "
	LD	DE,STR_MEM_SIZE_32K
	CALL	PRINT_STR
	LD	DE,STR_MEM_SPACES_3
	CALL	PRINT_STR

	; Determine Role and Usage for installed bank
	; 1. Check if physical bank ID (0x80 + i) is in EXT_BANK_TABLE
	LD	A,(MEM_BANK_LOOP_IDX)
	ADD	A,080H
	LD	E,A			; E = physical bank ID
	LD	A,(EXT_BANK_COUNT)
	OR	A
	JR	Z,PMBR_NOT_IN_EXT
	LD	B,A			; B = EXT_BANK_COUNT
	LD	C,1			; C = 1-based doc bank index (1..14)
	LD	HL,EXT_BANK_TABLE
PMBR_EXT_LOOP:
	LD	A,(HL)
	CP	E
	JR	Z,PMBR_FOUND_IN_EXT
	INC	HL
	INC	C
	DJNZ	PMBR_EXT_LOOP
	JR	PMBR_NOT_IN_EXT

PMBR_FOUND_IN_EXT:
	; Bank E is in EXT_BANK_TABLE as Document Buffer Bank C!
	; Check Role: if E < HBIOS_APP_BANK -> RAM Disk (MD0:), else Application Memory
	LD	A,(HBIOS_APP_BANK)
	CP	E
	JR	C,PMBR_EXT_ROLE_APP	; If HBIOS_APP_BANK < E -> App
	JR	Z,PMBR_EXT_ROLE_APP	; If HBIOS_APP_BANK == E -> App
	LD	DE,STR_ROLE_RAMDISK
	JR	PMBR_EXT_PRINT_ROLE
PMBR_EXT_ROLE_APP:
	LD	DE,STR_ROLE_APP
PMBR_EXT_PRINT_ROLE:
	CALL	PRINT_STR
	LD	DE,STR_MEM_SPACES_3
	CALL	PRINT_STR

	; Usage: "Active: Doc Buffer Bank " + 2-digit C + "  "
	LD	DE,STR_USAGE_DOC_PFX
	CALL	PRINT_STR
	LD	A,C
	CALL	PRINT_2DIGIT_DEC
	LD	DE,STR_USAGE_DOC_SFX
	CALL	PRINT_STR
	CALL	PRINT_CRLF
	RET

PMBR_NOT_IN_EXT:
	; Check if bank is dedicated to PLUGIN.PRL
	LD	A,(MEM_BANK_LOOP_IDX)
	ADD	A,080H
	LD	E,A
	LD	A,(PLUGIN_MGR_LOADED)
	OR	A
	JR	Z,PMBR_CHK_LINE_0
	LD	A,(PLUGIN_MGR_BANK)
	CP	E
	JR	NZ,PMBR_CHK_LINE_0

	; Bank is active PLUGIN.PRL! Determine Role and Usage
	LD	A,(HBIOS_APP_BANK)
	CP	E
	JR	C,PMBR_PLUG_ROLE_APP
	JR	Z,PMBR_PLUG_ROLE_APP
	LD	DE,STR_ROLE_RAMDISK
	JR	PMBR_PLUG_PRINT_ROLE
PMBR_PLUG_ROLE_APP:
	LD	DE,STR_ROLE_APP
PMBR_PLUG_PRINT_ROLE:
	CALL	PRINT_STR
	LD	DE,STR_MEM_SPACES_3
	CALL	PRINT_STR
	LD	DE,STR_USAGE_PLUGIN_MGR
	CALL	PRINT_STR
	CALL	PRINT_CRLF
	RET

PMBR_CHK_LINE_0:
	; 2. Check if E == LINE_TABLE_BANK (and != 0)
	LD	A,(LINE_TABLE_BANK)
	OR	A
	JR	Z,PMBR_CHK_LINE_1
	CP	E
	JR	NZ,PMBR_CHK_LINE_1
	LD	DE,STR_ROLE_APP
	CALL	PRINT_STR
	LD	DE,STR_MEM_SPACES_3
	CALL	PRINT_STR
	; If LINE_TABLE_BANK_1 != 0, print STR_USAGE_LINE_TABLE_0, else STR_USAGE_LINE_TABLE
	LD	A,(LINE_TABLE_BANK_1)
	OR	A
	JR	NZ,PMBR_LT0_SPLIT
	LD	DE,STR_USAGE_LINE_TABLE
	CALL	PRINT_STR
	CALL	PRINT_CRLF
	RET
PMBR_LT0_SPLIT:
	LD	DE,STR_USAGE_LINE_TABLE_0
	CALL	PRINT_STR
	CALL	PRINT_CRLF
	RET

PMBR_CHK_LINE_1:
	; Check if E == LINE_TABLE_BANK_1 (and != 0)
	LD	A,(LINE_TABLE_BANK_1)
	OR	A
	JR	Z,PMBR_CHK_CPM_USER
	CP	E
	JR	NZ,PMBR_CHK_CPM_USER
	LD	DE,STR_ROLE_APP
	CALL	PRINT_STR
	LD	DE,STR_MEM_SPACES_3
	CALL	PRINT_STR
	LD	DE,STR_USAGE_LINE_TABLE_1
	CALL	PRINT_STR
	CALL	PRINT_CRLF
	RET

PMBR_CHK_CPM_USER:
	; 3. Check if E == CPM_USER_BANK
	LD	A,(MEM_BANK_LOOP_IDX)
	ADD	A,080H
	LD	E,A
	LD	A,(CPM_USER_BANK)
	CP	E
	JR	NZ,PMBR_CHK_HBIOS_BIOS
	; Print TPA role according to OS version
	LD	HL,(CPM_VERSION_ID)
	LD	A,H
	CP	014H
	JR	Z,PMBR_TPA_ZSYS
	LD	A,L
	CP	031H
	JR	Z,PMBR_TPA_CPM31
	LD	DE,STR_ROLE_TPA_CPM2
	JR	PMBR_PRINT_TPA_ROLE
PMBR_TPA_ZSYS:
	LD	DE,STR_ROLE_TPA_ZSYS
	JR	PMBR_PRINT_TPA_ROLE
PMBR_TPA_CPM31:
	LD	DE,STR_ROLE_TPA_CPM3
PMBR_PRINT_TPA_ROLE:
	CALL	PRINT_STR
	LD	DE,STR_MEM_SPACES_3
	CALL	PRINT_STR
	LD	DE,STR_USAGE_SE_PROG
	CALL	PRINT_STR
	CALL	PRINT_CRLF
	RET

PMBR_CHK_HBIOS_BIOS:
	; 4. Check if E == HBIOS_BIOS_BANK (e.g. 0x80)
	LD	A,(MEM_BANK_LOOP_IDX)
	ADD	A,080H
	LD	E,A
	LD	A,(HBIOS_BIOS_BANK)
	CP	E
	JR	NZ,PMBR_CHK_RAMDISK_PRESERVED
	LD	DE,STR_ROLE_HBIOS
	CALL	PRINT_STR
	LD	DE,STR_MEM_SPACES_3
	CALL	PRINT_STR
	LD	DE,STR_USAGE_HBIOS
	CALL	PRINT_STR
	CALL	PRINT_CRLF
	RET

PMBR_CHK_RAMDISK_PRESERVED:
	; 5. Check if E < HBIOS_APP_BANK (and not in EXT -> preserved RAM disk)
	LD	A,(MEM_BANK_LOOP_IDX)
	ADD	A,080H
	LD	E,A
	LD	A,(HBIOS_APP_BANK)
	CP	E
	JR	C,PMBR_CHK_OS_BANK	; If HBIOS_APP_BANK < E -> not RAM disk
	JR	Z,PMBR_CHK_OS_BANK	; If HBIOS_APP_BANK == E -> not RAM disk
	; E < HBIOS_APP_BANK: preserved RAM disk
	LD	DE,STR_ROLE_RAMDISK
	CALL	PRINT_STR
	LD	DE,STR_MEM_SPACES_3
	CALL	PRINT_STR
	LD	DE,STR_USAGE_RAMDISK_PRESERVED
	CALL	PRINT_STR
	CALL	PRINT_CRLF
	RET

PMBR_CHK_OS_BANK:
	; 6. Check if E > CPM_USER_BANK (e.g. 0x8F)
	LD	A,(MEM_BANK_LOOP_IDX)
	ADD	A,080H
	LD	E,A
	LD	A,(CPM_USER_BANK)
	CP	E
	JR	NC,PMBR_FREE_APP	; If CPM_USER_BANK >= E -> free app
	; E > CPM_USER_BANK:
	LD	DE,STR_ROLE_OS
	CALL	PRINT_STR
	LD	DE,STR_MEM_SPACES_3
	CALL	PRINT_STR
	LD	DE,STR_USAGE_OS
	CALL	PRINT_STR
	CALL	PRINT_CRLF
	RET

PMBR_FREE_APP:
	; Check if this is CP/M 3.x Buffer Bank (CPM_USER_BANK - 1 = 0x8C)
	LD	A,(CPM_VERSION_ID)
	CP	030H
	JR	C,PMBR_FREE_ACTUAL
	LD	A,(CPM_USER_BANK)
	DEC	A
	CP	E
	JR	NZ,PMBR_FREE_ACTUAL
	; Bank is CP/M 3 Buffers!
	LD	DE,STR_ROLE_OS
	CALL	PRINT_STR
	LD	DE,STR_MEM_SPACES_3
	CALL	PRINT_STR
	LD	DE,STR_USAGE_CPM3_BUFS
	CALL	PRINT_STR
	CALL	PRINT_CRLF
	RET

PMBR_FREE_ACTUAL:
	; 7. Free / Unallocated Application Memory
	LD	DE,STR_ROLE_APP
	CALL	PRINT_STR
	LD	DE,STR_MEM_SPACES_3
	CALL	PRINT_STR
	LD	DE,STR_USAGE_FREE
	CALL	PRINT_STR
	CALL	PRINT_CRLF
	RET

PMBR_NOT_INSTALLED:
	; Bank not installed: Size = " -- ", Role = Not Installed, Usage = Not Present
	LD	DE,STR_MEM_SIZE_NONE
	CALL	PRINT_STR
	LD	DE,STR_MEM_SPACES_3
	CALL	PRINT_STR
	LD	DE,STR_ROLE_NOT_INST
	CALL	PRINT_STR
	LD	DE,STR_MEM_SPACES_3
	CALL	PRINT_STR
	LD	DE,STR_USAGE_NOT_PRES
	CALL	PRINT_STR
	CALL	PRINT_CRLF
	RET

;------------------------------------------------------------------------------
; PRINT_2DIGIT_DEC: Print 2-digit decimal number (00..99) in A
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
PRINT_2DIGIT_DEC:
	PUSH	AF
	CP	10
	JR	NC,P2D_TEN_PLUS
	LD	A,'0'
	CALL	PUTC
	POP	AF
	ADD	A,'0'
	CALL	PUTC
	RET
P2D_TEN_PLUS:
	LD	A,'1'
	CALL	PUTC
	POP	AF
	SUB	10
	ADD	A,'0'
	CALL	PUTC
	RET

;------------------------------------------------------------------------------
; PRINT_CRLF: Print CR, LF
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
PRINT_CRLF:
	LD	A,13
	CALL	PUTC
	LD	A,10
	CALL	PUTC
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
	CP	2
	JR	Z,CANCEL_BLOCK		; Solidified block: Ctrl-B cancels
	CP	1
	JR	Z,TBM_CHECK_MOVED

	; Block inactive (0): activate and anchor at current cursor
START_NEW_BLOCK_AT_CURSOR:
	LD	A,1
	LD	(BLOCK_ACTIVE),A
	LD	HL,(CUR_DOC_ROW)
	LD	(BLOCK_ANCHOR_ROW),HL
	LD	HL,(CUR_COL)
	LD	(BLOCK_ANCHOR_COL),HL
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

TBM_CHECK_MOVED:
	; BLOCK_ACTIVE == 1: check if cursor moved away from anchor
	LD	HL,(BLOCK_ANCHOR_ROW)
	LD	DE,(CUR_DOC_ROW)
	LD	A,H
	CP	D
	JR	NZ,START_NEW_BLOCK_AT_CURSOR
	LD	A,L
	CP	E
	JR	NZ,START_NEW_BLOCK_AT_CURSOR
	LD	HL,(BLOCK_ANCHOR_COL)
	LD	DE,(CUR_COL)
	LD	A,H
	CP	D
	JR	NZ,START_NEW_BLOCK_AT_CURSOR
	LD	A,L
	CP	E
	JR	NZ,START_NEW_BLOCK_AT_CURSOR

	; Cursor did not move: toggle off (cancel)
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
	LD	BC,(BLOCK_ANCHOR_COL)

	; Compare HL (anchor row) and DE (cursor row)
	LD	A,H
	CP	D
	JR	C,NBB_ANCHOR_FIRST
	JR	NZ,NBB_CUR_FIRST
	LD	A,L
	CP	E
	JR	C,NBB_ANCHOR_FIRST
	JR	NZ,NBB_CUR_FIRST

	; Same row: compare BC (anchor col) and (CUR_COL)
	LD	(BLOCK_START_ROW),HL
	LD	(BLOCK_END_ROW),HL
	LD	HL,(CUR_COL)
	; Compare BC with HL:
	LD	A,B
	CP	H
	JR	C,NBB_COL_BC
	JR	NZ,NBB_COL_CB
	LD	A,C
	CP	L
	JR	C,NBB_COL_BC
	JR	Z,NBB_COL_BC

NBB_COL_CB:
	; BC > HL: Cursor is to the left of Anchor (backwards on same row)
	; Cursor at HL is excluded -> BLOCK_START_COL = HL + 1
	; Anchor at BC is included -> BLOCK_END_COL = BC + 1
	INC	HL
	LD	(BLOCK_START_COL),HL
	INC	BC
	LD	(BLOCK_END_COL),BC
	JR	NBB_DONE

NBB_COL_BC:
	; BC <= HL: Forward (or empty) selection on same row
	LD	(BLOCK_START_COL),BC
	LD	(BLOCK_END_COL),HL
	JR	NBB_DONE

NBB_ANCHOR_FIRST:
	LD	(BLOCK_START_ROW),HL
	LD	(BLOCK_START_COL),BC
	LD	(BLOCK_END_ROW),DE
	LD	HL,(CUR_COL)
	LD	(BLOCK_END_COL),HL
	JR	NBB_DONE

NBB_CUR_FIRST:
	; DE (Cursor Row) < HL (Anchor Row): Backwards multi-row selection
	; Cursor at (DE, CUR_COL) is excluded -> START_ROW = DE, START_COL = CUR_COL + 1
	; Anchor at (HL, BC) is included -> END_ROW = HL, END_COL = BC + 1
	LD	(BLOCK_START_ROW),DE
	LD	DE,(CUR_COL)
	INC	DE
	LD	(BLOCK_START_COL),DE
	LD	(BLOCK_END_ROW),HL
	INC	BC
	LD	(BLOCK_END_COL),BC

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
	; If BLOCK_END_COL > 0, end row contributes characters, so INC HL.
	; If BLOCK_END_COL == 0 and end > start, end row is exclusive.
	; If HL == 0 (single line), minimum is 1 line.
	LD	A,(BLOCK_END_COL)
	OR	A
	JR	NZ,GBB_INC_LINE
	LD	A,H
	OR	L
	JR	NZ,GBB_DONE_LINE
GBB_INC_LINE:
	INC	HL
GBB_DONE_LINE:
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
	JR	NZ,GLBR_IS_ACTIVE
	XOR	A
	LD	(LINE_BLK_ACTIVE),A
	SCF
	RET			; Carry = 1: no block active

GLBR_IS_ACTIVE:

	PUSH	BC
	PUSH	HL

	CALL	NORMALIZE_BLOCK_BOUNDS

	; Check if BC < BLOCK_START_ROW
	LD	HL,(BLOCK_START_ROW)
	LD	A,B
	CP	H
	JP	C,GLBR_NONE
	JR	NZ,GLBR_CHECK_MAX
	LD	A,C
	CP	L
	JP	C,GLBR_NONE

GLBR_CHECK_MAX:
	; Check if BC > BLOCK_END_ROW
	LD	HL,(BLOCK_END_ROW)
	LD	A,H
	CP	B
	JP	C,GLBR_NONE
	JR	NZ,GLBR_IN_RANGE
	LD	A,L
	CP	C
	JP	C,GLBR_NONE

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

	; Single-line block: StartCol = BLOCK_START_COL, EndCol = BLOCK_END_COL - 1
	LD	HL,(BLOCK_START_COL)
	LD	DE,(BLOCK_END_COL)
	; Compare HL with DE:
	LD	A,H
	CP	D
	JR	C,GLBR_SINGLE_OK
	JR	NZ,GLBR_NONE
	LD	A,L
	CP	E
	JR	NC,GLBR_NONE		; StartCol >= EndCol -> no highlight

GLBR_SINGLE_OK:
	LD	(LINE_BLK_START),HL
	DEC	DE
	LD	(LINE_BLK_END),DE
	LD	D,L
	LD	E,E
	JR	GLBR_OK

GLBR_START_ONLY:
	; First line of multi-line block: StartCol = BLOCK_START_COL, EndCol = to EOL
	LD	HL,(BLOCK_START_COL)
	LD	(LINE_BLK_START),HL
	LD	HL,0FFFFH
	LD	(LINE_BLK_END),HL
	LD	D,L
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

	; Last line of multi-line block: StartCol = 0, EndCol = BLOCK_END_COL - 1
	LD	DE,(BLOCK_END_COL)
	LD	A,D
	OR	E
	JR	Z,GLBR_NONE		; BLOCK_END_COL == 0 -> no chars on this line!

	DEC	DE
	LD	(LINE_BLK_END),DE
	LD	HL,0
	LD	(LINE_BLK_START),HL
	LD	D,0
	LD	E,E
	JR	GLBR_OK

GLBR_MIDDLE_ROW:
	; Middle full line: StartCol = 0, EndCol = to EOL
	LD	HL,0
	LD	(LINE_BLK_START),HL
	LD	HL,0FFFFH
	LD	(LINE_BLK_END),HL
	LD	D,0
	LD	E,254

GLBR_OK:
	LD	A,1
	LD	(LINE_BLK_ACTIVE),A
	POP	HL
	POP	BC
	OR	A			; Carry = 0: line has block range
	RET

GLBR_NONE:
	XOR	A
	LD	(LINE_BLK_ACTIVE),A
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

	CALL	INVALIDATE_ACTIVE_LINE
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
	CP	MAX_CACHE_LINE_CHARS	; max 250 chars
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
	; Lookup and free slot ID for DEL_BLK_CUR_LINE
	LD	BC,(DEL_BLK_CUR_LINE)
	CALL	GET_LINE_SLOT		; HL = slot ID
	CALL	FREE_LINE_CHAIN

	LD	HL,(DEL_BLK_CUR_LINE)
	INC	HL
	LD	(DEL_BLK_CUR_LINE),HL
	JR	DEL_BLK_FREE_LOOP

DEL_BLK_FREE_DONE:
	; Step 4: Shift line table entries above BLOCK_END_ROW downwards to BLOCK_START_ROW + 1
	; Lines removed: K = BLOCK_END_ROW - BLOCK_START_ROW
	; Number of entries to shift: W = DOC_TOTAL_LINES - (BLOCK_END_ROW + 1)
	LD	HL,(DOC_TOTAL_LINES)
	LD	DE,(BLOCK_END_ROW)
	INC	DE			; DE = BLOCK_END_ROW + 1
	AND	A
	SBC	HL,DE			; HL = W = DOC_TOTAL_LINES - (BLOCK_END_ROW + 1)
	JR	Z,DEL_BLK_NO_SHIFT
	JR	C,DEL_BLK_NO_SHIFT

	; W > 0: shift entries up towards lower line numbers
	LD	B,H
	LD	C,L			; BC = W (word count)
	LD	DE,(BLOCK_START_ROW)
	INC	DE			; DE = destination line = BLOCK_START_ROW + 1
	LD	HL,(BLOCK_END_ROW)
	INC	HL			; HL = source line = BLOCK_END_ROW + 1
	CALL	SHIFT_LINE_SLOTS_UP

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
	CALL	INVALIDATE_ACTIVE_LINE
	CALL	RELOAD_CACHE_WINDOW_FORCE
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	LD	(DOC_MODIFIED),A
	RET

;------------------------------------------------------------------------------
; CHECK_CURSOR_IN_BLOCK: Check if (CUR_DOC_ROW, CUR_COL) is inside solidified block
; Returns: Carry = 1 if cursor is inside block (or on boundary)
;          Carry = 0 if cursor is outside block
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
CHECK_CURSOR_IN_BLOCK:
	PUSH	HL
	PUSH	DE
	PUSH	BC

	; Check if CUR_DOC_ROW < BLOCK_START_ROW
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(BLOCK_START_ROW)
	LD	A,H
	CP	D
	JR	C,CCIB_OUTSIDE
	JR	NZ,CCIB_CHECK_MAX_ROW
	LD	A,L
	CP	E
	JR	C,CCIB_OUTSIDE

CCIB_CHECK_MAX_ROW:
	; Check if CUR_DOC_ROW > BLOCK_END_ROW
	LD	HL,(BLOCK_END_ROW)
	LD	DE,(CUR_DOC_ROW)
	LD	A,H
	CP	D
	JR	C,CCIB_OUTSIDE
	JR	NZ,CCIB_CHECK_COLS
	LD	A,L
	CP	E
	JR	C,CCIB_OUTSIDE

CCIB_CHECK_COLS:
	; CUR_DOC_ROW is within [BLOCK_START_ROW, BLOCK_END_ROW]
	; Check if single-line block
	LD	HL,(BLOCK_START_ROW)
	LD	DE,(BLOCK_END_ROW)
	LD	A,H
	CP	D
	JR	NZ,CCIB_CHECK_MULTI
	LD	A,L
	CP	E
	JR	NZ,CCIB_CHECK_MULTI

	; Single-line block: StartCol = BLOCK_START_COL, EndCol = BLOCK_END_COL (exclusive)
	; Inside only if BLOCK_START_COL <= CUR_COL < BLOCK_END_COL
	LD	HL,(CUR_COL)
	LD	DE,(BLOCK_START_COL)
	AND	A
	SBC	HL,DE
	JR	C,CCIB_OUTSIDE		; CUR_COL < BLOCK_START_COL -> outside!

	LD	HL,(CUR_COL)
	LD	DE,(BLOCK_END_COL)
	AND	A
	SBC	HL,DE
	JR	C,CCIB_INSIDE		; CUR_COL < BLOCK_END_COL -> inside!
	JR	CCIB_OUTSIDE

CCIB_CHECK_MULTI:
	; Multi-line block:
	; Is CUR_DOC_ROW == BLOCK_START_ROW?
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(BLOCK_START_ROW)
	LD	A,H
	CP	D
	JR	NZ,CCIB_CHECK_MULTI_END
	LD	A,L
	CP	E
	JR	NZ,CCIB_CHECK_MULTI_END

	; On BLOCK_START_ROW: inside if CUR_COL >= BLOCK_START_COL
	LD	HL,(CUR_COL)
	LD	DE,(BLOCK_START_COL)
	AND	A
	SBC	HL,DE
	JR	C,CCIB_OUTSIDE		; CUR_COL < BLOCK_START_COL -> outside!
	JR	CCIB_INSIDE

CCIB_CHECK_MULTI_END:
	; Is CUR_DOC_ROW == BLOCK_END_ROW?
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(BLOCK_END_ROW)
	LD	A,H
	CP	D
	JR	NZ,CCIB_INSIDE		; Middle row of multi-line block is always inside!
	LD	A,L
	CP	E
	JR	NZ,CCIB_INSIDE

	; On BLOCK_END_ROW: inside only if CUR_COL < BLOCK_END_COL (exclusive)
	LD	HL,(CUR_COL)
	LD	DE,(BLOCK_END_COL)
	AND	A
	SBC	HL,DE
	JR	C,CCIB_INSIDE
	JR	CCIB_OUTSIDE

CCIB_INSIDE:
	POP	BC
	POP	DE
	POP	HL
	SCF				; Carry = 1: inside block
	RET

CCIB_OUTSIDE:
	POP	BC
	POP	DE
	POP	HL
	OR	A			; Carry = 0: outside block
	RET

;------------------------------------------------------------------------------
; DO_COPY_BLOCK: Copy solidified block (Ctrl+C) to (CUR_DOC_ROW, CUR_COL)
;------------------------------------------------------------------------------
DO_COPY_BLOCK:
	LD	A,(BLOCK_ACTIVE)
	CP	2			; Only solidified blocks can be copied
	RET	NZ

	CALL	NORMALIZE_BLOCK_BOUNDS

	; Check if cursor is inside the block; if so, ignore Ctrl+C!
	CALL	CHECK_CURSOR_IN_BLOCK
	RET	C

	CALL	INVALIDATE_ACTIVE_LINE
	CALL	FLUSH_DIRTY_CACHE

	; Check if single-line or multi-line block
	LD	HL,(BLOCK_START_ROW)
	LD	DE,(BLOCK_END_ROW)
	LD	A,H
	CP	D
	JP	NZ,DO_COPY_BLK_MULTILINE
	LD	A,L
	CP	E
	JP	NZ,DO_COPY_BLK_MULTILINE

	;--------------------------------------------------------------------------
	; CASE 1: Single-Line Block Copy
	;--------------------------------------------------------------------------
DO_COPY_BLK_SINGLE:
	; Read source line BLOCK_START_ROW into SPLIT_LINE_TEMP
	LD	BC,(BLOCK_START_ROW)
	LD	DE,SPLIT_LINE_TEMP
	LD	HL,MAX_ACTIVE_LINE_STRIDE-2	; 1022
	CALL	READ_FAR_LINE_MAX

	; Measure source line length
	LD	HL,SPLIT_LINE_TEMP
	LD	BC,0
COPY_SGL_SRC_LEN:
	LD	A,(HL)
	OR	A
	JR	Z,COPY_SGL_SRC_LEN_DONE
	INC	HL
	INC	BC
	JR	COPY_SGL_SRC_LEN
COPY_SGL_SRC_LEN_DONE:
	; BC = source line length
	; Check if BLOCK_START_COL >= src_len (BC)
	LD	HL,(BLOCK_START_COL)
	AND	A
	SBC	HL,BC
	RET	NC			; BLOCK_START_COL >= src_len -> nothing to copy!

	; Check if BLOCK_END_COL > src_len (BC)
	LD	HL,(BLOCK_END_COL)
	AND	A
	SBC	HL,BC
	JR	C,COPY_SGL_END_COL_OK
	; Clamp BLOCK_END_COL = src_len (BC)
	LD	(BLOCK_END_COL),BC
COPY_SGL_END_COL_OK:

	; Length to copy: BC = BLOCK_END_COL - BLOCK_START_COL
	LD	HL,(BLOCK_END_COL)
	LD	DE,(BLOCK_START_COL)
	AND	A
	SBC	HL,DE
	RET	Z			; If length == 0, nothing to copy!
	LD	(COPY_BLK_LEN),HL
	LD	B,H
	LD	C,L			; BC = length to copy

	; Copy into COPY_BLK_BUF: source = SPLIT_LINE_TEMP + BLOCK_START_COL
	LD	HL,SPLIT_LINE_TEMP
	ADD	HL,DE			; HL = SPLIT_LINE_TEMP + BLOCK_START_COL
	LD	DE,COPY_BLK_BUF
	LDIR
	XOR	A
	LD	(DE),A			; Null-terminate COPY_BLK_BUF

	; Read destination line CUR_DOC_ROW into SPLIT_LINE_TEMP
	LD	BC,(CUR_DOC_ROW)
	LD	DE,SPLIT_LINE_TEMP
	LD	HL,MAX_ACTIVE_LINE_STRIDE-2	; 1022
	CALL	READ_FAR_LINE_MAX

	; Measure destination line length
	LD	HL,SPLIT_LINE_TEMP
	LD	BC,0
COPY_SGL_DEST_LEN:
	LD	A,(HL)
	OR	A
	JR	Z,COPY_SGL_DEST_LEN_DONE
	INC	HL
	INC	BC
	JR	COPY_SGL_DEST_LEN
COPY_SGL_DEST_LEN_DONE:
	LD	(DEST_LINE_LEN),BC

	; Clamp CUR_COL <= DEST_LINE_LEN
	LD	HL,(CUR_COL)
	LD	DE,(DEST_LINE_LEN)
	AND	A
	SBC	HL,DE
	JR	C,COPY_SGL_COL_OK
	JR	Z,COPY_SGL_COL_OK
	LD	(CUR_COL),DE
COPY_SGL_COL_OK:

	; Check line capacity: max MAX_INPUT_LINE_CHARS (1000)
	; Available Space = MAX_INPUT_LINE_CHARS - DEST_LINE_LEN
	LD	HL,MAX_INPUT_LINE_CHARS
	LD	DE,(DEST_LINE_LEN)
	AND	A
	SBC	HL,DE			; HL = available space
	RET	C			; If DEST_LINE_LEN >= MAX_INPUT_LINE_CHARS, can't add anything
	RET	Z

	; If COPY_BLK_LEN > Space, clamp COPY_BLK_LEN = Space
	LD	DE,(COPY_BLK_LEN)
	PUSH	HL			; Save available space
	AND	A
	SBC	HL,DE			; available space - COPY_BLK_LEN
	POP	HL			; HL = available space
	JR	NC,COPY_SGL_SPACE_OK	; Available space >= COPY_BLK_LEN
	LD	(COPY_BLK_LEN),HL	; Clamp COPY_BLK_LEN = available space
COPY_SGL_SPACE_OK:
	LD	HL,(COPY_BLK_LEN)
	LD	A,H
	OR	L
	RET	Z

	; Shift suffix in SPLIT_LINE_TEMP right by COPY_BLK_LEN bytes
	; Number of bytes to shift: (DEST_LINE_LEN - CUR_COL + 1)
	LD	HL,(DEST_LINE_LEN)
	LD	DE,(CUR_COL)
	AND	A
	SBC	HL,DE
	INC	HL
	LD	B,H
	LD	C,L			; BC = bytes to shift

	; HL = SPLIT_LINE_TEMP + DEST_LINE_LEN (source last byte)
	LD	HL,SPLIT_LINE_TEMP
	LD	DE,(DEST_LINE_LEN)
	ADD	HL,DE			; HL = source last byte

	; DE = destination last byte = HL + COPY_BLK_LEN
	LD	DE,(COPY_BLK_LEN)
	PUSH	HL
	ADD	HL,DE
	EX	DE,HL			; DE = destination last byte
	POP	HL			; HL = source last byte
	LDDR				; Shift suffix right

	; Copy COPY_BLK_LEN bytes from COPY_BLK_BUF into SPLIT_LINE_TEMP + CUR_COL
	LD	HL,COPY_BLK_BUF
	LD	DE,SPLIT_LINE_TEMP
	LD	BC,(CUR_COL)
	EX	DE,HL
	ADD	HL,BC
	EX	DE,HL			; DE = SPLIT_LINE_TEMP + CUR_COL
	LD	BC,(COPY_BLK_LEN)
	LDIR

	; Write updated line back to CUR_DOC_ROW
	LD	BC,(CUR_DOC_ROW)
	LD	HL,SPLIT_LINE_TEMP
	CALL	WRITE_FAR_LINE

	; If CUR_DOC_ROW == BLOCK_START_ROW and CUR_COL <= BLOCK_START_COL:
	; The block on this line shifted right by COPY_BLK_LEN!
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(BLOCK_START_ROW)
	LD	A,H
	CP	D
	JR	NZ,COPY_SGL_ADVANCE
	LD	A,L
	CP	E
	JR	NZ,COPY_SGL_ADVANCE

	LD	HL,(CUR_COL)
	LD	DE,(BLOCK_START_COL)
	AND	A
	SBC	HL,DE
	JR	Z,COPY_SGL_SHIFT_BOUNDS
	JR	NC,COPY_SGL_ADVANCE	; CUR_COL > BLOCK_START_COL

COPY_SGL_SHIFT_BOUNDS:
	LD	DE,(COPY_BLK_LEN)
	LD	HL,(BLOCK_START_COL)
	ADD	HL,DE
	LD	(BLOCK_START_COL),HL
	LD	HL,(BLOCK_END_COL)
	ADD	HL,DE
	LD	(BLOCK_END_COL),HL

COPY_SGL_ADVANCE:
	; Advance cursor: CUR_COL += COPY_BLK_LEN
	LD	HL,(CUR_COL)
	LD	DE,(COPY_BLK_LEN)
	ADD	HL,DE
	LD	(CUR_COL),HL
	CALL	CALC_VISUAL_COL
	LD	(TARGET_COL),HL

	CALL	INVALIDATE_ACTIVE_LINE
	CALL	RELOAD_CACHE_WINDOW_FORCE
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	LD	(DOC_MODIFIED),A
	RET

	;--------------------------------------------------------------------------
	; CASE 2: Multi-Line Block Copy
	;--------------------------------------------------------------------------
DO_COPY_BLK_MULTILINE:
	LD	HL,(BLOCK_END_ROW)
	LD	DE,(BLOCK_START_ROW)
	AND	A
	SBC	HL,DE
	LD	(COPY_K_LINES),HL	; K = new lines count

	; Check capacity: DOC_TOTAL_LINES + K <= MAX_DOC_LINES
	LD	HL,(DOC_TOTAL_LINES)
	LD	DE,(COPY_K_LINES)
	ADD	HL,DE
	LD	DE,(MAX_DOC_LINES_LIMIT)
	OR	A
	SBC	HL,DE
	JR	C,COPY_ML_CAP_OK
	JR	Z,COPY_ML_CAP_OK

COPY_ML_CAP_FAIL:
	CALL	SET_OOM_STATUS
	SCF
	RET

COPY_ML_CAP_OK:

	; Pre-extract BLOCK_END_ROW prefix [0 .. BLOCK_END_COL] into COPY_TAIL_BUF
	; (Doing this early prevents corruption if CUR_DOC_ROW == BLOCK_END_ROW)
	; If BLOCK_END_COL == 0, tail prefix is empty
	LD	A,(BLOCK_END_COL)
	OR	A
	JR	Z,COPY_ML_TAIL_EMPTY

	LD	BC,(BLOCK_END_ROW)
	LD	DE,COPY_TAIL_BUF
	CALL	READ_FAR_LINE

	; Truncate COPY_TAIL_BUF at BLOCK_END_COL
	LD	HL,COPY_TAIL_BUF
	LD	C,0			; C = char count
	LD	A,(BLOCK_END_COL)
	LD	B,A			; B = chars count (BLOCK_END_COL)
COPY_ML_TAIL_COUNT:
	LD	A,(HL)
	OR	A
	JR	Z,COPY_ML_TAIL_COUNT_DONE
	INC	HL
	INC	C
	DJNZ	COPY_ML_TAIL_COUNT
COPY_ML_TAIL_COUNT_DONE:
	LD	(HL),0			; Null-terminate COPY_TAIL_BUF
	LD	A,C
	LD	(COPY_TAIL_LEN),A	; Length of tail prefix
	JR	COPY_ML_TAIL_DONE

COPY_ML_TAIL_EMPTY:
	XOR	A
	LD	(COPY_TAIL_BUF),A
	LD	(COPY_TAIL_LEN),A

COPY_ML_TAIL_DONE:

	; Allocate K slots in COPY_SLOTS_BUF
	LD	BC,(COPY_K_LINES)
	LD	IX,COPY_SLOTS_BUF
COPY_ML_ALLOC_LOOP:
	PUSH	BC
	CALL	ALLOC_SLOT
	JR	C,COPY_ML_ALLOC_FAIL
	LD	(IX+0),L
	LD	(IX+1),H
	INC	IX
	INC	IX
	POP	BC
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,COPY_ML_ALLOC_LOOP
	JR	COPY_ML_ALLOC_DONE

COPY_ML_ALLOC_FAIL:
	CALL	SET_OOM_STATUS
	POP	BC
	LD	HL,(COPY_K_LINES)
	AND	A
	SBC	HL,BC			; HL = allocated count
	LD	B,H
	LD	C,L
	LD	A,B
	OR	C
	JR	Z,COPY_ML_ALLOC_FAIL_RET
	LD	IX,COPY_SLOTS_BUF
COPY_ML_ROLLBACK:
	LD	L,(IX+0)
	LD	H,(IX+1)
	PUSH	BC
	CALL	FREE_SLOT
	POP	BC
	INC	IX
	INC	IX
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,COPY_ML_ROLLBACK
COPY_ML_ALLOC_FAIL_RET:
	SCF
	RET

COPY_ML_ALLOC_DONE:
	; Step 1: Destination line at CUR_DOC_ROW
	; Read CUR_DOC_ROW into LOAD_LINE_TEMP
	LD	BC,(CUR_DOC_ROW)
	LD	DE,LOAD_LINE_TEMP
	CALL	READ_FAR_LINE

	; Split LOAD_LINE_TEMP at CUR_COL:
	; Prefix stays in LOAD_LINE_TEMP[0 .. CUR_COL - 1]
	; Suffix copied into SPLIT_LINE_TEMP
	LD	HL,SPLIT_LINE_TEMP
	LD	DE,SPLIT_LINE_TEMP+1
	LD	BC,127
	LD	(HL),0
	LDIR

	LD	HL,LOAD_LINE_TEMP
	LD	A,(CUR_COL)
	LD	E,A
	LD	D,0
	ADD	HL,DE			; HL = split point in LOAD_LINE_TEMP

	LD	DE,SPLIT_LINE_TEMP
COPY_ML_SAVE_SUFFIX:
	LD	A,(HL)
	OR	A
	JR	Z,COPY_ML_SUFFIX_SAVED
	LD	(DE),A
	LD	(HL),0			; Truncate LOAD_LINE_TEMP at CUR_COL
	INC	HL
	INC	DE
	JR	COPY_ML_SAVE_SUFFIX
COPY_ML_SUFFIX_SAVED:

	; Read BLOCK_START_ROW into COPY_BLK_BUF
	LD	BC,(BLOCK_START_ROW)
	LD	DE,COPY_BLK_BUF
	CALL	READ_FAR_LINE

	; Append COPY_BLK_BUF[BLOCK_START_COL .. EOL] to LOAD_LINE_TEMP at CUR_COL
	LD	HL,COPY_BLK_BUF
	LD	A,(BLOCK_START_COL)
	LD	E,A
	LD	D,0
	ADD	HL,DE			; HL = source in COPY_BLK_BUF

	LD	DE,LOAD_LINE_TEMP
	LD	A,(CUR_COL)
	LD	C,A			; C = current length
	PUSH	HL
	LD	HL,LOAD_LINE_TEMP
	LD	E,A
	LD	D,0
	ADD	HL,DE
	EX	DE,HL			; DE = destination in LOAD_LINE_TEMP
	POP	HL

COPY_ML_APPEND_HEAD:
	LD	A,(HL)
	OR	A
	JR	Z,COPY_ML_HEAD_DONE
	LD	A,C
	CP	MAX_CACHE_LINE_CHARS	; max 250 chars
	JR	NC,COPY_ML_HEAD_DONE
	LD	A,(HL)
	LD	(DE),A
	INC	HL
	INC	DE
	INC	C
	JR	COPY_ML_APPEND_HEAD
COPY_ML_HEAD_DONE:
	XOR	A
	LD	(DE),A

	; Write updated head line back to CUR_DOC_ROW
	LD	BC,(CUR_DOC_ROW)
	LD	HL,LOAD_LINE_TEMP
	CALL	WRITE_FAR_LINE

	; Step 2: Intermediate lines (if K > 1)
	LD	IX,COPY_SLOTS_BUF	; Pointer in COPY_SLOTS_BUF
	LD	HL,(COPY_K_LINES)
	DEC	HL			; HL = K - 1
	LD	A,H
	OR	L
	JR	Z,COPY_ML_PROCESS_LAST	; If K == 1, jump directly to last line

	LD	(COPY_SRC_ROW),HL	; Loop counter = K - 1
	LD	HL,(BLOCK_START_ROW)
	INC	HL
	LD	(DEL_BLK_CUR_LINE),HL	; Current source row = BLOCK_START_ROW + 1

COPY_ML_MID_LOOP:
	LD	BC,(DEL_BLK_CUR_LINE)
	LD	DE,LOAD_LINE_TEMP
	CALL	READ_FAR_LINE

	LD	C,(IX+0)
	LD	B,(IX+1)		; BC = slot ID
	LD	HL,LOAD_LINE_TEMP
	CALL	WRITE_FAR_SLOT_LINE

	INC	IX
	INC	IX
	LD	HL,(DEL_BLK_CUR_LINE)
	INC	HL
	LD	(DEL_BLK_CUR_LINE),HL

	LD	HL,(COPY_SRC_ROW)
	DEC	HL
	LD	(COPY_SRC_ROW),HL
	LD	A,H
	OR	L
	JR	NZ,COPY_ML_MID_LOOP

COPY_ML_PROCESS_LAST:
	; IX points to the slot for the last line
	; Build last line: COPY_TAIL_BUF + SPLIT_LINE_TEMP into LOAD_LINE_TEMP
	LD	HL,COPY_TAIL_BUF
	LD	DE,LOAD_LINE_TEMP
	LD	A,(COPY_TAIL_LEN)
	LD	C,A			; C = char count
	OR	A
	JR	Z,COPY_ML_LAST_COPY_SUFFIX
	LD	B,0
	LDIR

COPY_ML_LAST_COPY_SUFFIX:
	; Append Suffix from SPLIT_LINE_TEMP
	LD	HL,SPLIT_LINE_TEMP
COPY_ML_APPEND_SUFFIX:
	LD	A,(HL)
	OR	A
	JR	Z,COPY_ML_SUFFIX_DONE
	LD	A,C
	CP	MAX_CACHE_LINE_CHARS	; max 250 chars
	JR	NC,COPY_ML_SUFFIX_DONE
	LD	A,(HL)
	LD	(DE),A
	INC	HL
	INC	DE
	INC	C
	JR	COPY_ML_APPEND_SUFFIX
COPY_ML_SUFFIX_DONE:
	XOR	A
	LD	(DE),A

	; Write last line to slot (IX+0, IX+1)
	LD	C,(IX+0)
	LD	B,(IX+1)
	LD	HL,LOAD_LINE_TEMP
	CALL	WRITE_FAR_SLOT_LINE

	; Step 3: Shift line slots downward from CUR_DOC_ROW + 1 by K words
	LD	HL,(DOC_TOTAL_LINES)
	LD	DE,(CUR_DOC_ROW)
	INC	DE			; DE = CUR_DOC_ROW + 1
	AND	A
	SBC	HL,DE			; HL = W
	JR	Z,COPY_ML_PLUG_SLOTS
	JR	C,COPY_ML_PLUG_SLOTS

	; Shift W words down by K words
	LD	B,H
	LD	C,L			; BC = W
	LD	HL,(CUR_DOC_ROW)
	INC	HL			; HL = source line = CUR_DOC_ROW + 1
	LD	DE,(COPY_K_LINES)
	ADD	HL,DE
	EX	DE,HL			; DE = dest line = CUR_DOC_ROW + 1 + K
	LD	HL,(CUR_DOC_ROW)
	INC	HL			; HL = source line = CUR_DOC_ROW + 1
	CALL	SHIFT_LINE_SLOTS_DOWN

COPY_ML_PLUG_SLOTS:
	; Plug K new slot IDs into LINE_TABLE_BANK + (CUR_DOC_ROW + 1) * 2
	LD	HL,(CUR_DOC_ROW)
	INC	HL
	LD	B,H
	LD	C,L			; BC = CUR_DOC_ROW + 1
	LD	HL,COPY_SLOTS_BUF	; Source: COPY_SLOTS_BUF
	LD	DE,(COPY_K_LINES)	; DE = K words
	CALL	WRITE_LINE_SLOTS_FROM_RAM

	; Step 4: Update DOC_TOTAL_LINES += K
	LD	HL,(DOC_TOTAL_LINES)
	LD	DE,(COPY_K_LINES)
	ADD	HL,DE
	LD	(DOC_TOTAL_LINES),HL

	; Step 5: If CUR_DOC_ROW < BLOCK_START_ROW, shift block rows down by K
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(BLOCK_START_ROW)
	LD	A,H
	CP	D
	JR	C,COPY_ML_SHIFT_BLOCK
	JR	NZ,COPY_ML_DONE_BLOCK_SHIFT
	LD	A,L
	CP	E
	JR	NC,COPY_ML_DONE_BLOCK_SHIFT

COPY_ML_SHIFT_BLOCK:
	LD	HL,(BLOCK_START_ROW)
	LD	DE,(COPY_K_LINES)
	ADD	HL,DE
	LD	(BLOCK_START_ROW),HL

	LD	HL,(BLOCK_END_ROW)
	ADD	HL,DE
	LD	(BLOCK_END_ROW),HL

COPY_ML_DONE_BLOCK_SHIFT:
	; Step 6: Advance cursor to CUR_DOC_ROW + K, Col = COPY_TAIL_LEN
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(COPY_K_LINES)
	ADD	HL,DE
	LD	(CUR_DOC_ROW),HL

	LD	A,(COPY_TAIL_LEN)
	LD	L,A
	LD	H,0
	LD	(CUR_COL),HL
	CALL	CALC_VISUAL_COL
	LD	(TARGET_COL),HL

	; Adjust TOP_DOC_ROW if scrolled past screen
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(TOP_DOC_ROW)
	AND	A
	SBC	HL,DE
	LD	A,(ACTIVE_ROWS)
	DEC	A
	DEC	A
	CP	L
	JR	NC,COPY_ML_FINISH
	; Scroll viewport so CUR_DOC_ROW is on screen
	LD	HL,(CUR_DOC_ROW)
	LD	E,A
	LD	D,0
	AND	A
	SBC	HL,DE
	LD	(TOP_DOC_ROW),HL

COPY_ML_FINISH:
	CALL	INVALIDATE_ACTIVE_LINE
	CALL	RELOAD_CACHE_WINDOW_FORCE
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	LD	(DOC_MODIFIED),A
	AND	A
	RET

;------------------------------------------------------------------------------
; DO_MOVE_BLOCK: Move solidified block (Ctrl+X) to (CUR_DOC_ROW, CUR_COL)
;------------------------------------------------------------------------------
DO_MOVE_BLOCK:
	LD	A,(BLOCK_ACTIVE)
	CP	2			; Only solidified blocks can be moved
	RET	NZ

	CALL	NORMALIZE_BLOCK_BOUNDS

	; Check if cursor is inside the block; if so, cannot move block into itself!
	CALL	CHECK_CURSOR_IN_BLOCK
	RET	C

	CALL	INVALIDATE_ACTIVE_LINE
	CALL	FLUSH_DIRTY_CACHE

	; Save destination coordinates
	LD	HL,(CUR_DOC_ROW)
	LD	(MOVE_DEST_ROW),HL
	LD	HL,(CUR_COL)
	LD	(MOVE_DEST_COL),HL

	; Save original block coordinates & dimensions
	LD	HL,(BLOCK_START_ROW)
	LD	(MOVE_SRC_START_ROW),HL
	LD	HL,(BLOCK_START_COL)
	LD	(MOVE_SRC_START_COL),HL

	LD	HL,(BLOCK_END_ROW)
	LD	(MOVE_SRC_END_ROW),HL
	LD	HL,(BLOCK_END_COL)
	LD	(MOVE_SRC_END_COL),HL

	; Determine if DEST is BEFORE or AFTER SRC:
	; DEST < SRC_START: MOVE_DEST_IS_BEFORE = 1
	; DEST >= SRC_START: MOVE_DEST_IS_BEFORE = 0
	XOR	A
	LD	(MOVE_DEST_IS_BEFORE),A

	LD	HL,(MOVE_DEST_ROW)
	LD	DE,(MOVE_SRC_START_ROW)
	LD	A,H
	CP	D
	JR	C,MOVE_MARK_BEFORE
	JR	NZ,MOVE_EXEC_COPY
	LD	A,L
	CP	E
	JR	C,MOVE_MARK_BEFORE
	JR	NZ,MOVE_EXEC_COPY

	; Same row: compare columns
	LD	A,(MOVE_DEST_COL)
	LD	HL,MOVE_SRC_START_COL
	CP	(HL)
	JR	NC,MOVE_EXEC_COPY

MOVE_MARK_BEFORE:
	LD	A,1
	LD	(MOVE_DEST_IS_BEFORE),A

MOVE_EXEC_COPY:
	; Step 1: Copy block to destination
	CALL	DO_COPY_BLOCK
	LD	A,(STATUS_OOM_FLAG)
	OR	A
	RET	NZ			; Abort move if copy failed due to OOM!

	; Step 2: Delete original block
	CALL	DO_DELETE_BLOCK

	; Step 3: Compute new coordinates of the moved block and cursor:
	LD	A,(MOVE_DEST_IS_BEFORE)
	OR	A
	JR	NZ,MOVE_CALC_BEFORE

	; DEST was AFTER original block:
	; Check if single-line:
	LD	HL,(MOVE_SRC_START_ROW)
	LD	DE,(MOVE_SRC_END_ROW)
	LD	A,H
	CP	D
	JR	NZ,MOVE_AFTER_MULTI
	LD	A,L
	CP	E
	JR	NZ,MOVE_AFTER_MULTI

	; Single-line block:
	; Was DEST on the same row as SRC?
	LD	HL,(MOVE_DEST_ROW)
	LD	DE,(MOVE_SRC_START_ROW)
	LD	A,H
	CP	D
	JR	NZ,MOVE_AFTER_DIFF_ROW
	LD	A,L
	CP	E
	JR	NZ,MOVE_AFTER_DIFF_ROW

	; Same row after: DEST_COL shifted left by L = SRC_END_COL - SRC_START_COL
	LD	A,(MOVE_SRC_END_COL)
	LD	HL,MOVE_SRC_START_COL
	SUB	(HL)			; A = L
	LD	B,A
	LD	A,(MOVE_DEST_COL)
	SUB	B			; A = DEST_COL - L
	LD	(CUR_COL),A
	LD	HL,(MOVE_DEST_ROW)
	LD	(CUR_DOC_ROW),HL
	JR	MOVE_SET_BLOCK

MOVE_AFTER_DIFF_ROW:
	; Single-line block, but DEST is on a different row (after SRC_START_ROW):
	; Row did not shift, col did not shift!
	LD	HL,(MOVE_DEST_ROW)
	LD	(CUR_DOC_ROW),HL
	LD	A,(MOVE_DEST_COL)
	LD	(CUR_COL),A
	JR	MOVE_SET_BLOCK

MOVE_AFTER_MULTI:
	; Multi-line block:
	; K = MOVE_SRC_END_ROW - MOVE_SRC_START_ROW lines were deleted before DEST!
	; New DEST_ROW = MOVE_DEST_ROW - K
	LD	HL,(MOVE_SRC_END_ROW)
	LD	DE,(MOVE_SRC_START_ROW)
	AND	A
	SBC	HL,DE			; HL = K
	EX	DE,HL			; DE = K
	LD	HL,(MOVE_DEST_ROW)
	AND	A
	SBC	HL,DE			; HL = DEST_ROW - K
	LD	(CUR_DOC_ROW),HL
	LD	A,(MOVE_DEST_COL)
	LD	(CUR_COL),A
	JR	MOVE_SET_BLOCK

MOVE_CALC_BEFORE:
	; DEST was BEFORE original block: coordinates did not shift!
	LD	HL,(MOVE_DEST_ROW)
	LD	(CUR_DOC_ROW),HL
	LD	A,(MOVE_DEST_COL)
	LD	(CUR_COL),A

MOVE_SET_BLOCK:
	; Set new block coordinates around the moved block!
	LD	HL,(CUR_DOC_ROW)
	LD	(BLOCK_START_ROW),HL
	LD	A,(CUR_COL)
	LD	(BLOCK_START_COL),A

	; Check if single-line or multi-line block:
	LD	HL,(MOVE_SRC_START_ROW)
	LD	DE,(MOVE_SRC_END_ROW)
	LD	A,H
	CP	D
	JR	NZ,MOVE_SET_BLK_MULTI
	LD	A,L
	CP	E
	JR	NZ,MOVE_SET_BLK_MULTI

	; Single-line end coordinates:
	LD	HL,(CUR_DOC_ROW)
	LD	(BLOCK_END_ROW),HL
	LD	A,(MOVE_SRC_END_COL)
	LD	HL,MOVE_SRC_START_COL
	SUB	(HL)			; A = L
	LD	HL,CUR_COL
	ADD	A,(HL)			; A = CUR_COL + L
	LD	(BLOCK_END_COL),A
	JR	MOVE_ADJUST_VIEW

MOVE_SET_BLK_MULTI:
	; Multi-line end coordinates:
	LD	HL,(MOVE_SRC_END_ROW)
	LD	DE,(MOVE_SRC_START_ROW)
	AND	A
	SBC	HL,DE			; HL = K
	LD	DE,(CUR_DOC_ROW)
	ADD	HL,DE			; HL = CUR_DOC_ROW + K
	LD	(BLOCK_END_ROW),HL
	LD	A,(MOVE_SRC_END_COL)
	LD	(BLOCK_END_COL),A

MOVE_ADJUST_VIEW:
	; Ensure cursor position is visible on screen
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(TOP_DOC_ROW)
	LD	A,H
	CP	D
	JR	C,MOVE_ADJ_TOP
	JR	NZ,MOVE_CHECK_BOTTOM
	LD	A,L
	CP	E
	JR	NC,MOVE_CHECK_BOTTOM
MOVE_ADJ_TOP:
	LD	(TOP_DOC_ROW),HL
	JR	MOVE_FINISH

MOVE_CHECK_BOTTOM:
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(TOP_DOC_ROW)
	AND	A
	SBC	HL,DE
	LD	A,(ACTIVE_ROWS)
	DEC	A
	DEC	A
	CP	L
	JR	NC,MOVE_FINISH
	; Scroll down so CUR_DOC_ROW is on screen
	LD	HL,(CUR_DOC_ROW)
	LD	E,A
	LD	D,0
	AND	A
	SBC	HL,DE
	LD	(TOP_DOC_ROW),HL

MOVE_FINISH:
	LD	A,2
	LD	(BLOCK_ACTIVE),A	; Solidify block at new location!
	CALL	CALC_VISUAL_COL
	LD	(TARGET_COL),HL
	CALL	INVALIDATE_ACTIVE_LINE
	CALL	RELOAD_CACHE_WINDOW_FORCE
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

;------------------------------------------------------------------------------
; Editor Screen Renderer
;------------------------------------------------------------------------------
RENDER_SCREEN:
	CALL	ADJUST_HORIZ_VIEWPORT
	XOR	A
	LD	(IS_SPLASH_SCREEN),A
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
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

;------------------------------------------------------------------------------
; Check if current character at visual column B is at right screen edge (col 79)
; on an 80-column display, and the line continues beyond it.
; Inputs:
;   B = visual column (0..119)
;   HL = pointer to current character in LINE_STORAGE
; Outputs:
;   Carry flag = 1 if character should be highlighted in inverse video
;   Carry flag = 0 otherwise
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
CHECK_CHAR_CONT_HL:
CHECK_CHAR_CONT_16:
	LD	A,(BLOCK_ACTIVE)
	OR	A
	JR	NZ,CC16_NO
	LD	A,(LINE_BLK_ACTIVE)
	OR	A
	JR	NZ,CC16_NO

	; 1. Left edge continuation: if VIEW_LEFT_COL > 0 and DE == VIEW_LEFT_COL
	LD	A,(VIEW_LEFT_COL+1)
	OR	A
	JR	NZ,CC16_LEFT_NONZERO
	LD	A,(VIEW_LEFT_COL)
	OR	A
	JR	Z,CC16_CHECK_RIGHT
CC16_LEFT_NONZERO:
	LD	A,(VIEW_LEFT_COL+1)
	CP	D
	JR	NZ,CC16_CHECK_RIGHT
	LD	A,(VIEW_LEFT_COL)
	CP	E
	JR	Z,CC16_YES

CC16_CHECK_RIGHT:
	; 2. Right edge continuation: if DE + 1 == VIEW_RIGHT_COL and line continues
	INC	DE
	LD	A,(VIEW_RIGHT_COL+1)
	CP	D
	JR	NZ,CC16_NO_DEC
	LD	A,(VIEW_RIGHT_COL)
	CP	E
CC16_NO_DEC:
	DEC	DE
	JR	NZ,CC16_NO

	; Visual col DE is VIEW_RIGHT_COL - 1. Check if line continues past (HL):
	INC	HL
	LD	A,(HL)
	DEC	HL
	OR	A
	JR	Z,CC16_NO		; Next char is null -> line ends here
CC16_YES:
	SCF
	RET
CC16_NO:
	OR	A
	RET

;------------------------------------------------------------------------------
; Check if current TAB space at visual column DE is at edge of display
; Inputs:
;   DE = visual column (0..1000)
;   (REND_TAB_SPACES) = remaining spaces in tab (1..8)
;   HL = pointer to next character in buffer (already incremented past TAB)
; Outputs:
;   Carry flag = 1 if space should be highlighted in inverse video
;   Carry flag = 0 otherwise
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
CHECK_TAB_CONT_HL:
CHECK_TAB_CONT_16:
	LD	A,(BLOCK_ACTIVE)
	OR	A
	JR	NZ,CT16_NO
	LD	A,(LINE_BLK_ACTIVE)
	OR	A
	JR	NZ,CT16_NO

	; 1. Left edge continuation:
	LD	A,(VIEW_LEFT_COL+1)
	OR	A
	JR	NZ,CT16_LEFT_NONZERO
	LD	A,(VIEW_LEFT_COL)
	OR	A
	JR	Z,CT16_CHECK_RIGHT
CT16_LEFT_NONZERO:
	LD	A,(VIEW_LEFT_COL+1)
	CP	D
	JR	NZ,CT16_CHECK_RIGHT
	LD	A,(VIEW_LEFT_COL)
	CP	E
	JR	Z,CT16_YES

CT16_CHECK_RIGHT:
	; 2. Right edge continuation:
	INC	DE
	LD	A,(VIEW_RIGHT_COL+1)
	CP	D
	JR	NZ,CT16_NO_DEC
	LD	A,(VIEW_RIGHT_COL)
	CP	E
CT16_NO_DEC:
	DEC	DE
	JR	NZ,CT16_NO

	; DE is VIEW_RIGHT_COL - 1.
	; If REND_TAB_SPACES > 1, tab itself continues into next column:
	LD	A,(REND_TAB_SPACES)
	CP	1
	JR	NZ,CT16_YES

	; Last space of tab. Does line continue after tab?
	LD	A,(HL)
	OR	A
	JR	Z,CT16_NO

CT16_YES:
	SCF
	RET
CT16_NO:
	OR	A
	RET

;------------------------------------------------------------------------------
; GET_TAB_SPACES: Compute spaces to next tab stop (1..CFG_TAB_WIDTH)
; Input: A = Visual Column (low byte, 0..255)
; Returns: A = Spaces to advance (1..4 or 1..8)
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
GET_TAB_SPACES:
	PUSH	BC
	CPL
	LD	B,A
	LD	A,(CFG_TAB_MASK)
	AND	B
	INC	A
	POP	BC
	RET

; Fast single line refresh: rewrites current line and restores cursor
RENDER_CURRENT_LINE:
	; Defensive check: ensure CUR_DOC_ROW is within visible viewport bounds
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(TOP_DOC_ROW)
	AND	A
	SBC	HL,DE
	RET	C			; Outside viewport: do not emit out-of-bounds row
	LD	A,(ACTIVE_ROWS)
	SUB	2
	LD	E,A
	LD	D,0
	CALL	CMP_HL_DE
	RET	NC			; Outside viewport: do not emit out-of-bounds row

	; Move to start of current screen line: ESC [ <(CUR_DOC_ROW - TOP_DOC_ROW) + 1> ; 1 H
	LD	A,27
	CALL	PUTC
	LD	A,'['
	CALL	PUTC

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
	XOR	A
	LD	(LINE_IN_INVERSE),A

RCL_LOAD_LINE:
	CALL	CHECKOUT_ACTIVE_LINE	; HL = ACTIVE_LINE_BUF

	LD	A,(HL)
	OR	A
	JR	NZ,RCL_START_CHARS

	; Empty line
	LD	A,(LINE_BLK_ACTIVE)
	OR	A
	JP	Z,PRINT_CUR_LINE_DONE
	LD	HL,(LINE_BLK_START)
	LD	A,H
	OR	L
	JP	NZ,PRINT_CUR_LINE_DONE
	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR
	LD	A,' '
	CALL	PUTC
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	JP	PRINT_CUR_LINE_DONE

RCL_START_CHARS:
	LD	DE,0			; DE = 16-bit visual column accumulator
	LD	BC,0			; BC = 16-bit character index in line

PRINT_CUR_LINE_LOOP:
	LD	A,(HL)
	OR	A
	JP	Z,PRINT_CUR_LINE_DONE

	; Check if DE >= VIEW_RIGHT_COL (past right screen boundary -> done!)
	LD	A,(VIEW_RIGHT_COL+1)
	CP	D
	JP	C,PRINT_CUR_LINE_DONE
	JR	NZ,PCL_CHK_BLK
	LD	A,(VIEW_RIGHT_COL)
	CP	E
	JP	C,PRINT_CUR_LINE_DONE
	JP	Z,PRINT_CUR_LINE_DONE

PCL_CHK_BLK:
	; Check block highlight turn ON:
	LD	A,(LINE_BLK_ACTIVE)
	OR	A
	JR	Z,PCL_NO_BLK_START
	LD	A,(LINE_IN_INVERSE)
	OR	A
	JR	NZ,PCL_NO_BLK_START
	LD	A,(LINE_BLK_START+1)
	CP	B
	JR	NZ,PCL_NO_BLK_START
	LD	A,(LINE_BLK_START)
	CP	C
	JR	NZ,PCL_NO_BLK_START

	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR
	POP	HL
	POP	DE
	POP	BC
	LD	A,1
	LD	(LINE_IN_INVERSE),A

PCL_NO_BLK_START:
	LD	A,(HL)
	CP	KEY_TAB
	JR	Z,PRINT_CUR_TAB

	; Normal character:
	; Check if DE < VIEW_LEFT_COL
	LD	A,(VIEW_LEFT_COL+1)
	CP	D
	JR	C,PCL_DO_EMIT
	JR	NZ,PCL_SKIP_EMIT
	LD	A,(VIEW_LEFT_COL)
	CP	E
	JR	C,PCL_DO_EMIT
	JR	Z,PCL_DO_EMIT

PCL_SKIP_EMIT:
	; DE < VIEW_LEFT_COL: skip char output
	INC	HL
	INC	DE
	JP	PCL_AFTER_CHAR

PCL_DO_EMIT:
	CALL	CHECK_CHAR_CONT_16
	JR	C,PCL_EMIT_CONT
	LD	A,(HL)
	CALL	PUTC
	INC	HL
	INC	DE
	JP	PCL_AFTER_CHAR

PCL_EMIT_CONT:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR
	POP	HL
	POP	DE
	POP	BC
	LD	A,(HL)
	CALL	PUTC
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	POP	HL
	POP	DE
	POP	BC
	INC	HL
	INC	DE
	JP	PCL_AFTER_CHAR

PRINT_CUR_TAB:
	INC	HL
	LD	A,E
	CALL	GET_TAB_SPACES
	LD	(REND_TAB_SPACES),A	; spaces to emit (1..CFG_TAB_WIDTH)

PRINT_CUR_TAB_SPACES:
	; Check if DE >= VIEW_RIGHT_COL
	LD	A,(VIEW_RIGHT_COL+1)
	CP	D
	JP	C,PRINT_CUR_LINE_DONE
	JR	NZ,PCT_CHK_L
	LD	A,(VIEW_RIGHT_COL)
	CP	E
	JP	C,PRINT_CUR_LINE_DONE
	JP	Z,PRINT_CUR_LINE_DONE

PCT_CHK_L:
	; Check if DE < VIEW_LEFT_COL
	LD	A,(VIEW_LEFT_COL+1)
	CP	D
	JR	C,PCT_EMIT_SPACE
	JR	NZ,PCT_SKIP_SPACE
	LD	A,(VIEW_LEFT_COL)
	CP	E
	JR	C,PCT_EMIT_SPACE
	JR	Z,PCT_EMIT_SPACE

PCT_SKIP_SPACE:
	; DE < VIEW_LEFT_COL -> skip space
	INC	DE
	LD	A,(REND_TAB_SPACES)
	DEC	A
	LD	(REND_TAB_SPACES),A
	JP	NZ,PRINT_CUR_TAB_SPACES
	JP	PCL_AFTER_CHAR

PCT_EMIT_SPACE:
	CALL	CHECK_TAB_CONT_16
	JR	C,PCT_SPACE_CONT
	LD	A,' '
	CALL	PUTC
	INC	DE
	LD	A,(REND_TAB_SPACES)
	DEC	A
	LD	(REND_TAB_SPACES),A
	JP	NZ,PRINT_CUR_TAB_SPACES
	JP	PCL_AFTER_CHAR

PCT_SPACE_CONT:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR
	POP	HL
	POP	DE
	POP	BC
	LD	A,' '
	CALL	PUTC
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	POP	HL
	POP	DE
	POP	BC
	INC	DE
	LD	A,(REND_TAB_SPACES)
	DEC	A
	LD	(REND_TAB_SPACES),A
	JP	NZ,PRINT_CUR_TAB_SPACES
	JP	PCL_AFTER_CHAR

PCL_AFTER_CHAR:
	; Check if BC == LINE_BLK_END (turn off inverse after this char)
	LD	A,(LINE_BLK_ACTIVE)
	OR	A
	JR	Z,PCL_NEXT_CHAR
	LD	A,(LINE_IN_INVERSE)
	OR	A
	JR	Z,PCL_NEXT_CHAR

	LD	A,(LINE_BLK_END+1)
	CP	B
	JR	NZ,PCL_NEXT_CHAR
	LD	A,(LINE_BLK_END)
	CP	C
	JR	NZ,PCL_NEXT_CHAR

	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	POP	HL
	POP	DE
	POP	BC
	XOR	A
	LD	(LINE_IN_INVERSE),A

PCL_NEXT_CHAR:
	INC	BC			; Next character index
	JP	PRINT_CUR_LINE_LOOP

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
	CALL	ADJUST_HORIZ_VIEWPORT
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

	; Check if CUR_DOC_ROW is within visible screen bounds:
	; Must have: TOP_DOC_ROW <= CUR_DOC_ROW <= TOP_DOC_ROW + (ACTIVE_ROWS - 2)
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(TOP_DOC_ROW)
	AND	A
	SBC	HL,DE
	JR	C,CDL_FULL_REDRAW
	LD	A,(ACTIVE_ROWS)
	SUB	2
	LD	E,A
	LD	D,0
	CALL	CMP_HL_DE		; Carry=1 if HL < DE
	JR	NC,CDL_FULL_REDRAW	; HL >= ACTIVE_ROWS - 1: outside screen!

	; Current line redraw needed (RENDER_CURRENT_LINE updates status & locates cursor)
	XOR	A
	LD	(NEED_LINE_RENDER),A
	LD	(NEED_STATUS_RENDER),A
	CALL	RENDER_CURRENT_LINE
	RET

CDL_FULL_REDRAW:
	XOR	A
	LD	(NEED_LINE_RENDER),A
	LD	(NEED_STATUS_RENDER),A
	CALL	CONSTRAIN_CURSOR_VIEWPORT
	CALL	RELOAD_CACHE_WINDOW_FORCE
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	CALL	LOCATE_CURSOR
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
	XOR	A
	LD	(LINE_IN_INVERSE),A

RBL_LOAD_LINE:
	; Check if BC == (ACTIVE_LINE_ROW)
	LD	HL,(ACTIVE_LINE_ROW)
	LD	A,B
	CP	H
	JR	NZ,RBL_USE_CACHE
	LD	A,C
	CP	L
	JR	NZ,RBL_USE_CACHE
	LD	HL,ACTIVE_LINE_BUF
	JR	RBL_GOT_LINE_PTR

RBL_USE_CACHE:
	CALL	ENSURE_CACHE_WINDOW	; HL = pointer to line start in LINE_STORAGE

RBL_GOT_LINE_PTR:
	; Check if line is empty (HL == 0)
	LD	A,(HL)
	OR	A
	JR	NZ,RBL_START_CHARS

	; Line is empty
	LD	A,(LINE_BLK_ACTIVE)
	OR	A
	JP	Z,PRINT_LINE_END
	LD	HL,(LINE_BLK_START)
	LD	A,H
	OR	L
	JP	NZ,PRINT_LINE_END
	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR
	LD	A,' '
	CALL	PUTC
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	JP	PRINT_LINE_END

RBL_START_CHARS:
	LD	DE,0			; DE = 16-bit visual column accumulator
	LD	BC,0			; BC = 16-bit character index in line

PRINT_LINE_CHARS:
	LD	A,(HL)
	OR	A
	JP	Z,PRINT_LINE_END

	; Check if DE >= VIEW_RIGHT_COL (past right screen boundary -> done!)
	LD	A,(VIEW_RIGHT_COL+1)
	CP	D
	JP	C,PRINT_LINE_END
	JR	NZ,PLC_CHK_BLK
	LD	A,(VIEW_RIGHT_COL)
	CP	E
	JP	C,PRINT_LINE_END
	JP	Z,PRINT_LINE_END

PLC_CHK_BLK:
	; Check block highlight turn ON:
	LD	A,(LINE_BLK_ACTIVE)
	OR	A
	JR	Z,PLC_NO_BLK_START
	LD	A,(LINE_IN_INVERSE)
	OR	A
	JR	NZ,PLC_NO_BLK_START
	LD	A,(LINE_BLK_START+1)
	CP	B
	JR	NZ,PLC_NO_BLK_START
	LD	A,(LINE_BLK_START)
	CP	C
	JR	NZ,PLC_NO_BLK_START

	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR
	POP	HL
	POP	DE
	POP	BC
	LD	A,1
	LD	(LINE_IN_INVERSE),A

PLC_NO_BLK_START:
	LD	A,(HL)
	CP	KEY_TAB
	JR	Z,PRINT_LINE_TAB

	; Normal character:
	; Check if DE < VIEW_LEFT_COL
	LD	A,(VIEW_LEFT_COL+1)
	CP	D
	JR	C,PLC_DO_EMIT
	JR	NZ,PLC_SKIP_EMIT
	LD	A,(VIEW_LEFT_COL)
	CP	E
	JR	C,PLC_DO_EMIT
	JR	Z,PLC_DO_EMIT

PLC_SKIP_EMIT:
	; DE < VIEW_LEFT_COL: skip char output
	INC	HL
	INC	DE
	JP	PLC_AFTER_CHAR

PLC_DO_EMIT:
	CALL	CHECK_CHAR_CONT_16
	JR	C,PLC_EMIT_CONT
	LD	A,(HL)
	CALL	PUTC
	INC	HL
	INC	DE
	JP	PLC_AFTER_CHAR

PLC_EMIT_CONT:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR
	POP	HL
	POP	DE
	POP	BC
	LD	A,(HL)
	CALL	PUTC
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	POP	HL
	POP	DE
	POP	BC
	INC	HL
	INC	DE
	JP	PLC_AFTER_CHAR

PRINT_LINE_TAB:
	INC	HL
	LD	A,E
	CALL	GET_TAB_SPACES
	LD	(REND_TAB_SPACES),A

PRINT_LINE_TAB_SPACES:
	; Check if DE >= VIEW_RIGHT_COL
	LD	A,(VIEW_RIGHT_COL+1)
	CP	D
	JP	C,PRINT_LINE_END
	JR	NZ,PLT_CHK_L
	LD	A,(VIEW_RIGHT_COL)
	CP	E
	JP	C,PRINT_LINE_END
	JP	Z,PRINT_LINE_END

PLT_CHK_L:
	; Check if DE < VIEW_LEFT_COL
	LD	A,(VIEW_LEFT_COL+1)
	CP	D
	JR	C,PLT_EMIT_SPACE
	JR	NZ,PLT_SKIP_SPACE
	LD	A,(VIEW_LEFT_COL)
	CP	E
	JR	C,PLT_EMIT_SPACE
	JR	Z,PLT_EMIT_SPACE

PLT_SKIP_SPACE:
	; DE < VIEW_LEFT_COL -> skip space
	INC	DE
	LD	A,(REND_TAB_SPACES)
	DEC	A
	LD	(REND_TAB_SPACES),A
	JP	NZ,PRINT_LINE_TAB_SPACES
	JP	PLC_AFTER_CHAR

PLT_EMIT_SPACE:
	CALL	CHECK_TAB_CONT_16
	JR	C,PLT_SPACE_CONT
	LD	A,' '
	CALL	PUTC
	INC	DE
	LD	A,(REND_TAB_SPACES)
	DEC	A
	LD	(REND_TAB_SPACES),A
	JP	NZ,PRINT_LINE_TAB_SPACES
	JP	PLC_AFTER_CHAR

PLT_SPACE_CONT:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR
	POP	HL
	POP	DE
	POP	BC
	LD	A,' '
	CALL	PUTC
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	POP	HL
	POP	DE
	POP	BC
	INC	DE
	LD	A,(REND_TAB_SPACES)
	DEC	A
	LD	(REND_TAB_SPACES),A
	JP	NZ,PRINT_LINE_TAB_SPACES
	JP	PLC_AFTER_CHAR

PLC_AFTER_CHAR:
	; Check if BC == LINE_BLK_END (turn off inverse after this char)
	LD	A,(LINE_BLK_ACTIVE)
	OR	A
	JR	Z,PLC_NEXT_CHAR
	LD	A,(LINE_IN_INVERSE)
	OR	A
	JR	Z,PLC_NEXT_CHAR

	LD	A,(LINE_BLK_END+1)
	CP	B
	JR	NZ,PLC_NEXT_CHAR
	LD	A,(LINE_BLK_END)
	CP	C
	JR	NZ,PLC_NEXT_CHAR

	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	POP	HL
	POP	DE
	POP	BC
	XOR	A
	LD	(LINE_IN_INVERSE),A

PLC_NEXT_CHAR:
	INC	BC			; Next character index
	JP	PRINT_LINE_CHARS

PRINT_LINE_END:
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

STATUS_ENCLOSED_WIDTH	EQU	78
POS_FIELD_WIDTH		EQU	22

RENDER_STATUS_BAR:
	CALL	LOCATE_STATUS_ROW

	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR

	; Symmetrical Left Margin: (ACTIVE_COLS - STATUS_ENCLOSED_WIDTH) / 2
	LD	A,(ACTIVE_COLS)
	SUB	STATUS_ENCLOSED_WIDTH
	SRL	A			; A = 1 (80x24) or 21 (120x40)
	LD	B,A
	OR	A
	JR	Z,STATUS_LEFT_PAD_DONE
STATUS_LEFT_PAD_LOOP:
	LD	A,' '
	CALL	PUTC
	DJNZ	STATUS_LEFT_PAD_LOOP
STATUS_LEFT_PAD_DONE:

	; Extreme Left Enclosure: "| " (2 chars)
	LD	A,'|'
	CALL	PUTC
	LD	A,' '
	CALL	PUTC

	; Field 1: Print filename (17 chars: 14 chars name + " | ")
	CALL	PRINT_STATUS_FILENAME

	; Field 2: Print active geometry (9 chars: " 80x24 | " or "120x40 | ")
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
	; Field 3: Print format (8 chars: "CP/M  | " or "Linux | ")
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
	; Field 4: Print Mode / Keys / Selection / OOM / Memory (18 chars)
	LD	A,(IS_REPLACE_PROMPT)
	OR	A
	JP	NZ,SHOW_STATUS_REPLACE_PROMPT

	LD	A,(IS_LOADING_FILE)
	OR	A
	JP	NZ,SHOW_STATUS_LOADING

	LD	A,(IS_SAVING_FILE)
	OR	A
	JP	NZ,SHOW_STATUS_SAVING

	LD	A,(IS_SPLASH_SCREEN)
	OR	A
	JP	NZ,SHOW_STATUS_SPLASH_MEM

	LD	A,(PLUGIN_IS_FAR_EXEC)
	OR	A
	JP	NZ,SHOW_STATUS_SPLASH_MEM

	LD	HL,(PLUGIN_STATUS_MSG_PTR)
	LD	A,H
	OR	L
	JP	NZ,SHOW_STATUS_PLUGIN_MSG

	LD	A,(STATUS_OOM_FLAG)
	OR	A
	JP	NZ,SHOW_STATUS_OOM

	LD	A,(BLOCK_ACTIVE)
	OR	A
	JP	Z,SHOW_STATUS_NORMAL_KEYS

	CALL	NORMALIZE_BLOCK_BOUNDS

	LD	A,(BLOCK_ACTIVE)
	CP	2
	JR	Z,STATUS_SOLIDIFIED

	; Dynamic selection active: "[SEL: "
	LD	DE,STR_SEL_PREFIX
	CALL	PRINT_STR
	LD	C,6			; 6 chars for "[SEL: "

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
	SUB	(HL)			; A = char count (BLOCK_END_COL - BLOCK_START_COL)
	CALL	PRINT_DEC_BYTE
	INC	C			; at least 1 digit
	CP	10
	JR	C,S_SEL_DIG_DONE
	INC	C
	CP	100
	JR	C,S_SEL_DIG_DONE
	INC	C
S_SEL_DIG_DONE:
	LD	DE,STR_CHAR_SUFFIX	; "c]"
	CALL	PRINT_STR
	INC	C
	INC	C			; + 2 for "c]"
	JR	STATUS_BLOCK_PAD

STATUS_SEL_MULTILINE:
	CALL	GET_BLOCK_BOUNDS	; BC = line count
	LD	L,C
	LD	H,B
	CALL	GET_DEC_WORD_DIGITS	; A = digits (1..5)
	ADD	A,6+2			; 6 ("[SEL: ") + digits + 2 ("L]")
	LD	C,A
	CALL	PRINT_DEC_WORD
	LD	DE,STR_LINE_SUFFIX	; "L]"
	CALL	PRINT_STR
	JR	STATUS_BLOCK_PAD

STATUS_SOLIDIFIED:
	; Solidified block: "[BLK: "
	LD	DE,STR_BLK_PREFIX
	CALL	PRINT_STR
	LD	C,6			; 6 for "[BLK: "

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
	SUB	(HL)			; A = char count (BLOCK_END_COL - BLOCK_START_COL)
	CALL	PRINT_DEC_BYTE
	INC	C			; at least 1 digit
	CP	10
	JR	C,S_SOL_DIG_DONE
	INC	C
	CP	100
	JR	C,S_SOL_DIG_DONE
	INC	C
S_SOL_DIG_DONE:
	LD	DE,STR_CHAR_LOCK_SUFFIX	; "c LOCK]"
	CALL	PRINT_STR
	LD	A,C
	ADD	A,7			; + 7 for "c LOCK]"
	LD	C,A
	JR	STATUS_BLOCK_PAD

STATUS_SOLID_MULTILINE:
	CALL	GET_BLOCK_BOUNDS	; BC = line count
	LD	L,C
	LD	H,B
	CALL	GET_DEC_WORD_DIGITS	; A = digits (1..5)
	ADD	A,6+7			; 6 ("[BLK: ") + digits + 7 ("L LOCK]")
	LD	C,A
	CALL	PRINT_DEC_WORD
	LD	DE,STR_LINE_LOCK_SUFFIX	; "L LOCK]"
	CALL	PRINT_STR

STATUS_BLOCK_PAD:
	LD	A,C
	CP	15
	JR	NC,STATUS_BLOCK_PAD_DONE
	LD	A,' '
	CALL	PUTC
	INC	C
	JR	STATUS_BLOCK_PAD

STATUS_BLOCK_PAD_DONE:
	LD	DE,STR_STATUS_SEP	; " | "
	CALL	PRINT_STR
	JP	SHOW_STATUS_ROWCOL

SHOW_STATUS_PLUGIN_MSG:
	LD	HL,(PLUGIN_STATUS_MSG_PTR)
	LD	B,0			; char count
SSPM_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,SSPM_PAD
	CP	'$'
	JR	Z,SSPM_PAD
	CALL	PUTC
	INC	HL
	INC	B
	LD	A,B
	CP	15
	JR	C,SSPM_LOOP
	JR	SSPM_DONE

SSPM_PAD:
	LD	A,B
	CP	15
	JR	NC,SSPM_DONE
	LD	A,' '
	CALL	PUTC
	INC	B
	JR	SSPM_PAD

SSPM_DONE:
	LD	DE,STR_STATUS_SEP
	CALL	PRINT_STR
	JP	SHOW_STATUS_ROWCOL

SHOW_STATUS_NORMAL_KEYS:
	; Check if viewport is panned horizontally (VIEW_LEFT_COL > 0)
	LD	HL,(VIEW_LEFT_COL)
	LD	A,H
	OR	L
	JR	NZ,SHOW_STATUS_PAN_OFFSET

	LD	A,(INSERT_MODE)
	OR	A
	JR	Z,SHOW_STATUS_OVERWRITE
	LD	DE,STR_STATUS_KEYS
	CALL	PRINT_STR
	JP	SHOW_STATUS_ROWCOL

SHOW_STATUS_OVERWRITE:
	LD	DE,STR_STATUS_OVR
	CALL	PRINT_STR
	JP	SHOW_STATUS_ROWCOL

SHOW_STATUS_PAN_OFFSET:
	; Field 4 total length must be 18 chars (15 text + 3 " | ")
	LD	DE,STR_PAN_PREFIX	; "[Pan +" (6 chars)
	CALL	PRINT_STR
	LD	HL,(VIEW_LEFT_COL)
	CALL	GET_DEC_WORD_DIGITS	; A = digits (1..5)
	LD	C,A
	LD	HL,(VIEW_LEFT_COL)
	CALL	PRINT_DEC_WORD
	LD	A,']'
	CALL	PUTC
	; Pad with (8 - digits) spaces
	LD	A,8
	SUB	C			; A = 8 - digits
	LD	B,A
SSPO_PAD_LOOP:
	LD	A,' '
	CALL	PUTC
	DJNZ	SSPO_PAD_LOOP
	LD	DE,STR_STATUS_SEP	; " | " (3 chars)
	CALL	PRINT_STR
	JR	SHOW_STATUS_ROWCOL

SHOW_STATUS_OOM:
	LD	DE,STR_STATUS_OOM
	CALL	PRINT_STR
	JR	SHOW_STATUS_ROWCOL


SHOW_STATUS_REPLACE_PROMPT:
	; Fields 4 & 5 (combined 40 chars): Print replace prompt followed by 5 spaces
	; STR_REPLACE_CONFIRM is 35 visible characters
	LD	DE,STR_REPLACE_CONFIRM
	CALL	PRINT_STR
	LD	B,5
SSRP_PAD_LOOP:
	LD	A,' '
	CALL	PUTC
	DJNZ	SSRP_PAD_LOOP
	JP	SSRC_POS_DONE

SHOW_STATUS_LOADING:
	LD	DE,STR_STATUS_LOADING
	CALL	PRINT_STR
	JR	SHOW_STATUS_ROWCOL

SHOW_STATUS_SAVING:
	LD	DE,STR_STATUS_SAVING
	CALL	PRINT_STR
	JR	SHOW_STATUS_ROWCOL

SHOW_STATUS_SPLASH_MEM:
	CALL	PRINT_STATUS_FREE_MEM
	JR	SHOW_STATUS_ROWCOL

SHOW_STATUS_ROWCOL:
	; Field 5: Print fixed-position cursor position (POS_FIELD_WIDTH = 22 chars)
	; "Line <cur:4>/<total:4> Col <col:3>"
	LD	A,(IS_LOADING_FILE)
	OR	A
	JR	NZ,SHOW_STATUS_LOADING_POS

	LD	A,(IS_SAVING_FILE)
	OR	A
	JR	NZ,SHOW_STATUS_LOADING_POS

	; 1. Prefix: "Line " (5 chars)
	LD	DE,STR_STATUS_POS	; "Line "
	CALL	PRINT_STR
	JR	SSRC_NORMAL_POS

SHOW_STATUS_LOADING_POS:
	; 1. Prefix: "Line " (5 chars)
	LD	DE,STR_STATUS_POS	; "Line "
	CALL	PRINT_STR

	; 2. Line number: right-justified in 5 chars
	LD	HL,(LOAD_PROGRESS_LINES)
	CALL	GET_DEC_WORD_DIGITS	; A = digits (1..5)
	LD	C,A
	LD	A,5
	SUB	C
	JR	C,SSLP_NUM
	JR	Z,SSLP_NUM
	LD	B,A
SSLP_PAD:
	LD	A,' '
	CALL	PUTC
	DJNZ	SSLP_PAD
SSLP_NUM:
	LD	HL,(LOAD_PROGRESS_LINES)
	CALL	PRINT_DEC_WORD

	; 3. Trailing spaces: POS_FIELD_WIDTH (22) - 10 = 12 spaces
	LD	B,12
SSLP_TRAIL_PAD:
	LD	A,' '
	CALL	PUTC
	DJNZ	SSLP_TRAIL_PAD
	JP	SSRC_POS_DONE

SSRC_NORMAL_POS:

	; 2. Current line: right-justified in 4 chars
	LD	HL,(CUR_DOC_ROW)
	INC	HL
	CALL	GET_DEC_WORD_DIGITS	; A = digits (1..5)
	LD	C,A
	LD	A,4
	SUB	C			; A = 4 - digits
	JR	C,SSRC_CUR_PRINT
	JR	Z,SSRC_CUR_PRINT
	LD	B,A
SSRC_CUR_PAD:
	LD	A,' '
	CALL	PUTC
	DJNZ	SSRC_CUR_PAD
SSRC_CUR_PRINT:
	LD	HL,(CUR_DOC_ROW)
	INC	HL
	CALL	PRINT_DEC_WORD

	; 3. "/" delimiter (1 char at fixed column)
	LD	A,'/'
	CALL	PUTC

	; 4. Max lines: left-justified in 4 chars
	LD	HL,(DOC_TOTAL_LINES)
	CALL	GET_DEC_WORD_DIGITS	; A = digits (1..5)
	LD	C,A
	LD	HL,(DOC_TOTAL_LINES)
	CALL	PRINT_DEC_WORD
	LD	A,4
	SUB	C			; A = 4 - digits
	JR	C,SSRC_TOT_PAD_DONE
	JR	Z,SSRC_TOT_PAD_DONE
	LD	B,A
SSRC_TOT_PAD:
	LD	A,' '
	CALL	PUTC
	DJNZ	SSRC_TOT_PAD
SSRC_TOT_PAD_DONE:

	; 5. " Col " label (5 chars at fixed column)
	LD	DE,STR_STATUS_COL	; " Col "
	CALL	PRINT_STR

	; 6. Column: left-justified in 3 chars
	CALL	CALC_VISUAL_COL		; HL = visual col (0..1000)
	CALL	GET_DEC_WORD_DIGITS	; A = digits (1..5)
	LD	C,A
	PUSH	BC
	CALL	PRINT_DEC_WORD
	POP	BC
	LD	A,3
	SUB	C			; A = 3 - digits
	JR	C,SSRC_COL_PAD_DONE
	JR	Z,SSRC_COL_PAD_DONE
	LD	B,A
SSRC_COL_PAD:
	LD	A,' '
	CALL	PUTC
	DJNZ	SSRC_COL_PAD
SSRC_COL_PAD_DONE:
SSRC_POS_DONE:
	; Extreme Right Enclosure: " |" (2 chars)
	LD	A,' '
	CALL	PUTC
	LD	A,'|'
	CALL	PUTC

	; Symmetrical Right Margin: (ACTIVE_COLS - STATUS_ENCLOSED_WIDTH) / 2
	LD	A,(ACTIVE_COLS)
	SUB	STATUS_ENCLOSED_WIDTH
	SRL	A			; A = 1 (80x24) or 21 (120x40)
	LD	B,A
	OR	A
	JR	Z,SSRC_RIGHT_PAD_DONE
SSRC_RIGHT_PAD:
	LD	A,' '
	CALL	PUTC
	DJNZ	SSRC_RIGHT_PAD
SSRC_RIGHT_PAD_DONE:
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	LD	A,(IS_REPLACE_PROMPT)
	OR	A
	JR	NZ,STATUS_LOCATE_REP_CURSOR
	CALL	LOCATE_CURSOR
	RET

STATUS_LOCATE_REP_CURSOR:
	CALL	LOCATE_REPLACE_PROMPT_CURSOR
	RET

;------------------------------------------------------------------------------
; LOCATE_REPLACE_PROMPT_CURSOR:
; Position cursor on status row immediately after "Replace (...)? "
; Column = ((ACTIVE_COLS - 78) / 2) + 72
; (Col 73 in 80x24, Col 93 in 120x40)
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
LOCATE_REPLACE_PROMPT_CURSOR:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	A,27
	CALL	PUTC
	LD	A,'['
	CALL	PUTC
	LD	A,(ACTIVE_ROWS)
	CALL	PRINT_DEC_BYTE
	LD	A,';'
	CALL	PUTC
	LD	A,(ACTIVE_COLS)
	SUB	STATUS_ENCLOSED_WIDTH	; 80 - 78 = 2,  120 - 78 = 42
	SRL	A			; 1 or 21
	ADD	A,72			; Col 73 (80x24) or Col 93 (120x40)
	CALL	PRINT_DEC_BYTE
	LD	A,'H'
	CALL	PUTC
	POP	HL
	POP	DE
	POP	BC
	RET

MEM_FIELD_WIDTH		EQU	15

;------------------------------------------------------------------------------
; Print Free Memory in Status Bar (Fixed Width: MEM_FIELD_WIDTH = 15 chars)
; Formats as "Free: <N> KB   " followed by " | ".
; Replaces "^K: Editor keys" when rendering status bar on splash screen.
;------------------------------------------------------------------------------
PRINT_STATUS_FREE_MEM:
	CALL	CALC_FREE_MEM_KB	; HL = Free memory in whole KB
	PUSH	HL

	; Calculate character count of "Free: <N> KB"
	; "Free: " = 6 chars, " KB" = 3 chars -> 9 chars + digits
	CALL	GET_DEC_WORD_DIGITS	; A = number of digits (1..5)
	ADD	A,9			; A = total chars before padding
	LD	C,A			; C = characters printed so far

	LD	DE,STR_STATUS_FREE	; "Free: "
	CALL	PRINT_STR

	POP	HL			; HL = Free KB
	CALL	PRINT_DEC_WORD

	LD	DE,STR_STATUS_KB	; " KB"
	CALL	PRINT_STR

PSFM_PAD_LOOP:
	LD	A,C
	CP	MEM_FIELD_WIDTH		; 15
	JR	NC,PSFM_DONE
	LD	A,' '
	CALL	PUTC
	INC	C
	JR	PSFM_PAD_LOOP

PSFM_DONE:
	LD	DE,STR_STATUS_SEP	; " | "
	CALL	PRINT_STR
	RET

;------------------------------------------------------------------------------
; SET_OOM_STATUS: Record Out of Memory condition and update status bar if displayed
;------------------------------------------------------------------------------
SET_OOM_STATUS:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	A,1
	LD	(STATUS_OOM_FLAG),A
	LD	(NEED_STATUS_RENDER),A
	; Only update status bar if in editor mode and not splash screen
	LD	A,(IN_EDITOR_MODE)
	OR	A
	JR	Z,SOS_DONE
	LD	A,(IS_SPLASH_SCREEN)
	OR	A
	JR	NZ,SOS_DONE
	CALL	RENDER_STATUS_BAR
SOS_DONE:
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

;------------------------------------------------------------------------------
; Calculate Free Memory in Whole KB
; Returns: HL = Free Memory in whole KB (slots / 8)
;------------------------------------------------------------------------------
CALC_FREE_MEM_KB:
	PUSH	AF
	PUSH	BC
	PUSH	DE

	LD	A,(EXT_BANK_COUNT)
	LD	H,A
	LD	L,0			; HL = Total slots (EXT_BANK_COUNT * 256)
	LD	A,(IN_EDITOR_MODE)
	OR	A
	JR	Z,CFM_DIV8		; If no active editor document, 0 slots used

	LD	DE,(DOC_TOTAL_LINES)
	AND	A
	SBC	HL,DE			; HL = Total slots - DOC_TOTAL_LINES
	JR	NC,CFM_DIV8
	LD	HL,0			; Clamped to 0
CFM_DIV8:
	SRL	H
	RR	L
	SRL	H
	RR	L
	SRL	H
	RR	L			; HL = Free KB (slots / 8)

	POP	DE
	POP	BC
	POP	AF
	RET

;------------------------------------------------------------------------------
; Count Decimal Digits in 16-bit Word (HL)
; Returns: A = digit count (1..5)
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
GET_DEC_WORD_DIGITS:
	PUSH	DE
	LD	A,1
	LD	DE,10
	CALL	CMP_HL_DE
	JR	C,GDWD_DONE
	INC	A
	LD	DE,100
	CALL	CMP_HL_DE
	JR	C,GDWD_DONE
	INC	A
	LD	DE,1000
	CALL	CMP_HL_DE
	JR	C,GDWD_DONE
	INC	A
	LD	DE,10000
	CALL	CMP_HL_DE
	JR	C,GDWD_DONE
	INC	A
GDWD_DONE:
	POP	DE
	RET

CMP_HL_DE:
	; Compare HL with DE: Carry=1 if HL < DE. Preserves HL, DE.
	PUSH	HL
	OR	A
	SBC	HL,DE
	POP	HL
	RET

FILENAME_FIELD_WIDTH	EQU	14
PSF_MAX_LEN:		DB	14

;------------------------------------------------------------------------------
; Print Filename in Status Bar (Fixed Width: FILENAME_FIELD_WIDTH characters)
; If filename is unknown (HAS_FILE_ARG == 0), prints "(Untitled)" padded.
; If filename is known, prints full filename "Drive letter: filename" padded.
; Takes care not to duplicate drive letter if filename already contains it.
; Always outputs exactly FILENAME_FIELD_WIDTH characters, followed by " | ".
;------------------------------------------------------------------------------
PRINT_STATUS_FILENAME:
	LD	C,0			; C = characters printed so far
	LD	A,FILENAME_FIELD_WIDTH	; Default max chars = 14
	LD	(PSF_MAX_LEN),A

	LD	A,(IS_SAVING_FILE)
	OR	A
	JR	NZ,PSF_LIMIT_SET

	LD	A,(DOC_MODIFIED)
	OR	A
	JR	Z,PSF_LIMIT_SET

	LD	A,FILENAME_FIELD_WIDTH-1 ; If modified, reserve 1 char for '*' (max 13)
	LD	(PSF_MAX_LEN),A

PSF_LIMIT_SET:
	LD	A,(IS_SAVING_FILE)
	OR	A
	JR	NZ,PSF_HAVE_FILE

	LD	A,(HAS_FILE_ARG)
	OR	A
	JR	NZ,PSF_HAVE_FILE

	; Unknown filename: print "(Untitled)"
	LD	DE,STR_NO_NAME
PSF_NO_NAME_LOOP:
	LD	A,(DE)
	OR	A
	JP	Z,PSF_CHECK_MODIFIED
	CALL	PUTC
	INC	DE
	INC	C
	JR	PSF_NO_NAME_LOOP

PSF_HAVE_FILE:
	; Check if active document is a FAT/DOS file
	LD	A,(DOC_IS_FAT)
	OR	A
	JP	NZ,PSF_FAT_FILE

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

	; If DOC_USER_NUM > 0, emit user number digits
	LD	A,(DOC_USER_NUM)
	OR	A
	JR	Z,PSF_EMIT_COLON
	CP	10
	JR	C,PSF_USER_1DIGIT
	PUSH	AF
	LD	A,'1'
	CALL	PUTC
	INC	C
	POP	AF
	SUB	10
PSF_USER_1DIGIT:
	ADD	A,'0'
	CALL	PUTC
	INC	C

PSF_EMIT_COLON:
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
	LD	A,(PSF_MAX_LEN)
	CP	C
	JR	Z,PSF_CHECK_EXT
	JR	C,PSF_CHECK_EXT
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
	JR	Z,PSF_CHECK_MODIFIED
	OR	A
	JR	Z,PSF_CHECK_MODIFIED

	LD	A,(PSF_MAX_LEN)
	CP	C
	JR	Z,PSF_CHECK_MODIFIED
	JR	C,PSF_CHECK_MODIFIED

	LD	A,'.'
	CALL	PUTC
	INC	C

	LD	B,3
PSF_EXT_LOOP:
	LD	A,(HL)
	CP	' '
	JR	Z,PSF_CHECK_MODIFIED
	OR	A
	JR	Z,PSF_CHECK_MODIFIED
	LD	A,(PSF_MAX_LEN)
	CP	C
	JR	Z,PSF_CHECK_MODIFIED
	JR	C,PSF_CHECK_MODIFIED
	LD	A,(HL)
	CALL	PUTC
	INC	C
	INC	HL
	DJNZ	PSF_EXT_LOOP
	JR	PSF_CHECK_MODIFIED

PSF_FAT_FILE:
	; Emit 'U'
	LD	A,'U'
	CALL	PUTC
	INC	C

	; If FAT_DOC_UNIT != 0xFF, emit unit digit (e.g. '2' or '4')
	LD	A,(FAT_DOC_UNIT)
	CP	0FFH
	JR	Z,PFF_EMIT_COLON
	ADD	A,'0'
	CALL	PUTC
	INC	C

PFF_EMIT_COLON:
	LD	A,':'
	CALL	PUTC
	INC	C

	; Print FAT_DOC_FNAME characters up to PSF_MAX_LEN
	LD	HL,FAT_DOC_FNAME
PFF_NAME_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,PSF_CHECK_MODIFIED
	CP	' '
	JR	Z,PSF_CHECK_MODIFIED
	LD	A,(PSF_MAX_LEN)
	CP	C
	JR	Z,PSF_CHECK_MODIFIED
	JR	C,PSF_CHECK_MODIFIED
	LD	A,(HL)
	CALL	PUTC
	INC	C
	INC	HL
	JR	PFF_NAME_LOOP

PSF_CHECK_MODIFIED:
	; Check if document is modified and not currently saving
	LD	A,(IS_SAVING_FILE)
	OR	A
	JR	NZ,PSF_PAD_SPACES

	LD	A,(DOC_MODIFIED)
	OR	A
	JR	Z,PSF_PAD_SPACES

	; Document is modified: print '*' indicator (max 13 chars printed, so space exists)
	LD	A,'*'
	CALL	PUTC
	INC	C

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
; ADJUST_HORIZ_VIEWPORT: Auto-scroll horizontal viewport in 80- and 120-column modes
; Evaluates cursor visual column against VIEW_LEFT_COL and VIEW_RIGHT_COL.
; If viewport shifts, sets NEED_SCREEN_RENDER = 1.
; Preserves: AF, BC, DE, HL
;------------------------------------------------------------------------------
ADJUST_HORIZ_VIEWPORT:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL

	CALL	CALC_VISUAL_COL		; HL = true visual column (0..MAX_LINE_CHARS-1)
	EX	DE,HL			; DE = visual column

	; 1. Check if cursor is off-screen to the left or on left continuation highlight
	LD	HL,(VIEW_LEFT_COL)
	LD	A,H
	OR	L
	JR	Z,AHV_CHECK_RIGHT	; VIEW_LEFT_COL == 0 -> cannot pan left

	; If VIEW_LEFT_COL >= DE (i.e. DE <= VIEW_LEFT_COL), cursor is on/past highlight -> pan left!
	LD	A,L
	SUB	E
	LD	A,H
	SBC	A,D
	JR	NC,AHV_PAN_LEFT		; VIEW_LEFT_COL >= DE -> pan left

AHV_CHECK_RIGHT:
	; 2. Check if cursor is off-screen to the right (DE >= VIEW_RIGHT_COL)
	LD	HL,(VIEW_RIGHT_COL)
	LD	A,E
	SUB	L
	LD	A,D
	SBC	A,H
	JR	NC,AHV_PAN_RIGHT	; DE >= VIEW_RIGHT_COL -> pan right

	; 3. Check if cursor is on right screen edge (DE == VIEW_RIGHT_COL - 1)
	DEC	HL			; HL = VIEW_RIGHT_COL - 1
	LD	A,E
	CP	L
	JR	NZ,AHV_DONE
	LD	A,D
	CP	H
	JR	NZ,AHV_DONE

	; Cursor is at right screen edge: check if line continues past CUR_COL:
	CALL	CHECKOUT_ACTIVE_LINE	; HL = ACTIVE_LINE_BUF
	LD	BC,(CUR_COL)
	ADD	HL,BC			; HL = pointer to char at CUR_COL
	LD	A,(HL)
	OR	A
	JR	Z,AHV_DONE		; At null terminator -> line ends
	INC	HL
	LD	A,(HL)
	OR	A
	JR	Z,AHV_DONE		; Next is null -> last char
	; Line continues beyond right edge -> pan right!
	JR	AHV_PAN_RIGHT

AHV_PAN_LEFT:
	; Pan left: round (DE - 1) down to multiple of 40 so cursor is strictly > new VIEW_LEFT_COL
	LD	HL,0
	LD	A,D
	OR	E
	JR	Z,AHV_UPDATE_HL		; If DE == 0, new VIEW_LEFT_COL = 0
	DEC	DE			; DE = DE - 1
AHV_PL_LOOP:
	LD	A,E
	SUB	40
	LD	B,A
	LD	A,D
	SBC	A,0
	JR	C,AHV_UPDATE_HL
	LD	E,B
	LD	D,A
	LD	BC,40
	ADD	HL,BC
	JR	AHV_PL_LOOP

AHV_PAN_RIGHT:
	LD	HL,(VIEW_LEFT_COL)
AHV_PR_LOOP:
	LD	BC,40
	ADD	HL,BC			; HL += 40
	LD	A,(ACTIVE_COLS)
	LD	C,A
	LD	B,0
	PUSH	HL
	ADD	HL,BC			; HL = candidate VIEW_RIGHT_COL
	LD	A,E
	SUB	L
	LD	A,D
	SBC	A,H
	POP	HL
	JR	C,AHV_UPDATE_HL
	JR	AHV_PR_LOOP

AHV_UPDATE_HL:
	; Check if HL differs from VIEW_LEFT_COL
	LD	DE,(VIEW_LEFT_COL)
	LD	A,L
	CP	E
	JR	NZ,AHV_STORE_NEW
	LD	A,H
	CP	D
	JR	Z,AHV_DONE

AHV_STORE_NEW:
	LD	(VIEW_LEFT_COL),HL
	LD	A,(ACTIVE_COLS)
	LD	E,A
	LD	D,0
	ADD	HL,DE
	LD	(VIEW_RIGHT_COL),HL
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A

AHV_DONE:
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

;------------------------------------------------------------------------------
; CONSTRAIN_CURSOR_VIEWPORT: Ensure cursor row is strictly within active viewport
; When switching screen modes (e.g. 120x40 -> 80x24) or reentering the editor,
; prevents the cursor from being located below the status bar.
; Moves cursor up if out-of-bounds, realigning CUR_COL to TARGET_COL on row change.
; Note: Horizontal position is managed dynamically by ADJUST_HORIZ_VIEWPORT,
; supporting up to 120-char lines without horizontal column truncation.
; Preserves: AF, BC, DE, HL
;------------------------------------------------------------------------------
CONSTRAIN_CURSOR_VIEWPORT:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL

	; Ensure TOP_DOC_ROW < DOC_TOTAL_LINES
	LD	DE,(DOC_TOTAL_LINES)
	LD	A,D
	OR	E
	JR	Z,CCV_CALC_MAX_VIS
	LD	HL,(TOP_DOC_ROW)
	CALL	CMP_HL_DE		; Carry=1 if TOP_DOC_ROW < DOC_TOTAL_LINES
	JR	C,CCV_CALC_MAX_VIS
	; TOP_DOC_ROW >= DOC_TOTAL_LINES: clamp TOP_DOC_ROW = DOC_TOTAL_LINES - 1
	EX	DE,HL
	DEC	HL
	LD	(TOP_DOC_ROW),HL

CCV_CALC_MAX_VIS:
	; 1. Calculate max visible doc row = TOP_DOC_ROW + (ACTIVE_ROWS - 2)
	LD	A,(ACTIVE_ROWS)
	SUB	2			; A = max screen row index (e.g. 22 for 80x24, 38 for 120x40)
	LD	E,A
	LD	D,0
	LD	HL,(TOP_DOC_ROW)
	ADD	HL,DE			; HL = TOP_DOC_ROW + (ACTIVE_ROWS - 2)
	EX	DE,HL			; DE = max visible doc row

	; 2. Clamp DE to DOC_TOTAL_LINES - 1 (if DOC_TOTAL_LINES > 0)
	LD	HL,(DOC_TOTAL_LINES)
	LD	A,H
	OR	L
	JR	Z,CCV_CHECK_CUR_ROW	; If 0 lines, DE remains upper bound
	DEC	HL			; HL = DOC_TOTAL_LINES - 1
	; If DE > HL (last line < DE), clamp DE = HL
	CALL	CMP_HL_DE		; Carry=1 if HL < DE
	JR	NC,CCV_CHECK_CUR_ROW
	EX	DE,HL			; DE = DOC_TOTAL_LINES - 1

CCV_CHECK_CUR_ROW:
	; Now DE is the maximum valid CUR_DOC_ROW for the viewport.
	; Check if CUR_DOC_ROW > DE:
	LD	HL,(CUR_DOC_ROW)
	EX	DE,HL			; HL = max allowed row, DE = CUR_DOC_ROW
	CALL	CMP_HL_DE		; Carry=1 if HL < DE (i.e. max allowed < CUR_DOC_ROW)
	JR	NC,CCV_CHECK_TOP_ROW
	; CUR_DOC_ROW > max allowed row: move cursor UP!
	LD	(CUR_DOC_ROW),HL
	; Row changed: clamp CUR_COL to new line's length matching TARGET_COL
	CALL	ADJUST_COL_TO_TARGET
	JR	CCV_DONE

CCV_CHECK_TOP_ROW:
	; Check if CUR_DOC_ROW < TOP_DOC_ROW:
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(TOP_DOC_ROW)
	CALL	CMP_HL_DE		; Carry=1 if CUR_DOC_ROW < TOP_DOC_ROW
	JR	NC,CCV_DONE
	; CUR_DOC_ROW < TOP_DOC_ROW: move cursor DOWN to TOP_DOC_ROW
	EX	DE,HL
	LD	(CUR_DOC_ROW),HL
	; Row changed: clamp CUR_COL to new line's length matching TARGET_COL
	CALL	ADJUST_COL_TO_TARGET

CCV_DONE:
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

;------------------------------------------------------------------------------
; Calculate Visual Document Column from (CUR_DOC_ROW, CUR_COL)
; Returns: HL = 16-bit Visual Column (0-indexed, 0..MAX_LINE_CHARS-1)
; Preserves: BC, DE
;------------------------------------------------------------------------------
CALC_VISUAL_COL:
	PUSH	BC
	PUSH	DE

	; Ensure current line is checked out in ACTIVE_LINE_BUF
	CALL	CHECKOUT_ACTIVE_LINE	; HL = ACTIVE_LINE_BUF

	LD	DE,(CUR_COL)		; DE = character count to process
	LD	BC,0			; BC = visual column accumulator

CALC_VIS_LOOP:
	LD	A,D
	OR	E
	JR	Z,CALC_VIS_DONE

	LD	A,(HL)
	OR	A
	JR	Z,CALC_VIS_DONE

	CP	KEY_TAB
	JR	Z,CALC_VIS_TAB

	INC	BC
	JR	CALC_VIS_NEXT

CALC_VIS_TAB:
	; Tab advances BC to next tab stop
	LD	A,C
	CALL	GET_TAB_SPACES		; spaces to add (1..CFG_TAB_WIDTH)
	ADD	A,C
	LD	C,A
	JR	NC,CALC_VIS_NEXT
	INC	B

CALC_VIS_NEXT:
	INC	HL
	DEC	DE
	JR	CALC_VIS_LOOP

CALC_VIS_DONE:
	; Check clamp against MAX_LINE_CHARS-1
	LD	HL,MAX_LINE_CHARS-1
	LD	A,C
	SUB	L
	LD	A,B
	SBC	A,H
	JR	C,CALC_VIS_NO_CLAMP
	LD	B,H
	LD	C,L

CALC_VIS_NO_CLAMP:
	LD	H,B
	LD	L,C			; HL = 16-bit visual column
	POP	DE
	POP	BC
	RET

LOCATE_CURSOR:
	; Emit ESC [ <ScreenRow+1> ; <ScreenCol+1> H
	LD	A,27
	CALL	PUTC
	LD	A,'['
	CALL	PUTC

	; Screen Row = CUR_DOC_ROW - TOP_DOC_ROW + 1 (1-indexed for terminal)
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(TOP_DOC_ROW)
	AND	A
	SBC	HL,DE
	JR	NC,LC_ROW_POS
	LD	HL,0			; Clamp to 0 if CUR_DOC_ROW < TOP_DOC_ROW
LC_ROW_POS:
	LD	A,(ACTIVE_ROWS)
	SUB	2			; Max allowed row index (e.g. 22 for 80x24)
	LD	E,A
	LD	D,0
	CALL	CMP_HL_DE		; Carry=1 if HL < DE
	JR	C,LC_ROW_OK
	EX	DE,HL			; Clamp to max row index
LC_ROW_OK:
	LD	A,L
	INC	A
	CALL	PRINT_DEC_BYTE

	LD	A,';'
	CALL	PUTC

	; Screen Column (1-indexed) = (Visual Col - VIEW_LEFT_COL) + 1
	CALL	CALC_VISUAL_COL		; HL = visual column (16-bit)
	LD	DE,(VIEW_LEFT_COL)
	AND	A
	SBC	HL,DE			; HL = Screen Column (0-indexed)
	JR	NC,LC_COL_POS
	LD	HL,0			; Clamp to 0 if Visual Col < VIEW_LEFT_COL
LC_COL_POS:
	LD	A,(ACTIVE_COLS)
	DEC	A			; Max allowed col index (e.g. 79 for 80-col)
	LD	E,A
	LD	D,0
	CALL	CMP_HL_DE		; Carry=1 if HL < DE
	JR	C,LC_COL_OK
	EX	DE,HL			; Clamp to max col index
LC_COL_OK:
	LD	A,L
	INC	A
	CALL	PRINT_DEC_BYTE

	LD	A,'H'
	CALL	PUTC
	RET

;------------------------------------------------------------------------------
; 512KB HBIOS RAM Far-Banking Multi-Bank Document Engine
;------------------------------------------------------------------------------
BUFFER_INIT:
	; Clear LINE_STORAGE with 0
	LD	HL,LINE_STORAGE
	LD	DE,LINE_STORAGE+1
	LD	BC,LINE_STORAGE_SIZE-1
	LD	(HL),0
	LDIR

	; Clear LOAD_LINE_TEMP (256 bytes)
	LD	HL,LOAD_LINE_TEMP
	LD	DE,LOAD_LINE_TEMP+1
	LD	BC,255
	LD	(HL),0
	LDIR

	; Clear FAR_IO_BUF (128 bytes)
	LD	HL,FAR_IO_BUF
	LD	DE,FAR_IO_BUF+1
	LD	BC,127
	LD	(HL),0
	LDIR

	XOR	A
	LD	(NEED_SCREEN_RENDER),A
	LD	(NEED_LINE_RENDER),A
	LD	(NEED_STATUS_RENDER),A
	LD	A,1
	LD	(INSERT_MODE),A

	CALL	INIT_FAR_RAM_BANKS
	CALL	INIT_SLOT_SYSTEM
	CALL	INVALIDATE_ACTIVE_LINE
	CALL	INIT_EMPTY_DOCUMENT
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

	; 3. Query Bank Info to obtain BIOS Bank ID (SYSGET 0xF2)
	; Returns: D = BIOS Bank ID (e.g. 0x80), E = User Bank ID
	PUSH	IX
	LD	B,0F8H
	LD	C,0F2H
	RST	08H
	POP	IX
	; Ensure D is at least 0x80 in case of unexpected return
	LD	A,D
	OR	A
	JR	NZ,IFRB_GOT_BIOS_BANK
	LD	D,080H
IFRB_GOT_BIOS_BANK:

	; Check if RAM drive memory blocks should be used or protected
	; Mode 0 (Protected): Protect banks 0x81..0x88
	; Mode 1 (Enabled): Unconditionally allow banks down to 0x80
	; Mode 2 (Hibernate): Allow banks down to 0x80 ONLY IF RAMDRIVE_IS_HIBERNATED == 1
	LD	A,(CFG_RAMDRIVE_FLAG)
	CP	RAMDRV_MODE_ENABLED
	JR	Z,IFRB_FLOOR_SET	; If 1, use D = 0x80 (allow RAM drive blocks)
	CP	RAMDRV_MODE_HIBERNATE
	JR	NZ,IFRB_PROTECTED_MODE
	LD	A,(RAMDRIVE_IS_HIBERNATED)
	CP	1
	JR	Z,IFRB_FLOOR_SET	; If hibernated, use D = 0x80

IFRB_PROTECTED_MODE:
	; Protected mode (CFG_RAMDRIVE_FLAG == 0 or not hibernated):
	; Query App Banks (SYSGET 0xF5) to find lowest safe App bank (BID_APP0)
	; Returns: H = First App Bank ID (e.g. 0x89), L = App Bank count (e.g. 3)
	PUSH	IX
	LD	B,0F8H
	LD	C,0F5H			; BF_SYSGET_APPBNKS
	RST	08H
	POP	IX
	OR	A			; A = 0 on success
	JR	NZ,IFRB_NO_APP_BANKS
	LD	A,H
	CP	0FFH
	JR	Z,IFRB_NO_APP_BANKS
	LD	A,L
	OR	A
	JR	Z,IFRB_NO_APP_BANKS

	; Safe floor is BID_APP0 - 1 (e.g. 0x89 - 1 = 0x88)
	; Downward allocation stops when bank reaches floor, protecting 0x81..0x88
	DEC	H
	LD	D,H
	JR	IFRB_FLOOR_SET

IFRB_NO_APP_BANKS:
	; No application banks reported; floor = CPM_USER_BANK - 1 (safe fallback: 0 ext banks)
	; In CP/M 3.x, reserve Bank 0x8C (Buffers), so floor = CPM_USER_BANK - 2
	LD	A,(CPM_USER_BANK)
	DEC	A
	PUSH	AF
	LD	A,(CPM_VERSION_ID)
	CP	030H
	JR	C,IFRB_NAB_NOT_CPM3
	POP	AF
	DEC	A
	JR	IFRB_NAB_DONE
IFRB_NAB_NOT_CPM3:
	POP	AF
IFRB_NAB_DONE:
	LD	D,A

IFRB_FLOOR_SET:
	; 4. Allocate Line Table Banks: below CPM_USER_BANK
	LD	A,(CPM_USER_BANK)
	LD	C,A			; C = CPM_USER_BANK (e.g. 0x8E)
	DEC	C			; C = first Far RAM bank (e.g. 0x8D)
	; In CP/M 3.x, Bank 2 (0x8C) is reserved for OS disk buffers & hash.
	; Decrement C once more so Far RAM begins at 0x8B.
	LD	A,(CPM_VERSION_ID)
	CP	030H
	JR	C,IFRB_NOT_CPM3
	DEC	C			; C = 0x8B under CP/M 3
IFRB_NOT_CPM3:
	LD	A,C
	CP	D			; Compare with BIOS Bank ID (D)
	JR	Z,IFRB_NO_BANKS		; No Far RAM available!
	JR	C,IFRB_NO_BANKS
	LD	(LINE_TABLE_BANK),A	; Bank 0 for line slots (0..16383)
	XOR	A
	LD	(LINE_TABLE_BANK_1),A
	LD	HL,MAX_DOC_LINES_16K
	LD	(MAX_DOC_LINES_LIMIT),HL

	; Check if 32K lines mode requested (CFG_LINES_MODE == 1)
	LD	A,(CFG_LINES_MODE)
	OR	A
	JR	Z,IFRB_ALLOC_TEXT_BANKS

	; Check if at least 3 banks available from C down to floor D:
	; (C - D >= 3 guarantees 1 bank for Line 0, 1 bank for Line 1, >= 1 bank for Text)
	LD	A,C
	SUB	D
	CP	3
	JR	C,IFRB_ALLOC_TEXT_BANKS	; Less than 3 banks: fallback to 16K mode!

	; Allocate 2nd line table bank:
	DEC	C			; C = second Far RAM bank (e.g. 0x8C)
	LD	A,C
	LD	(LINE_TABLE_BANK_1),A	; Bank 1 for line slots (16384..32767)
	LD	HL,MAX_DOC_LINES_32K
	LD	(MAX_DOC_LINES_LIMIT),HL

IFRB_ALLOC_TEXT_BANKS:
	; 5. Populate EXT_BANK_TABLE allocating downward from C - 1
	; Stop when bank <= BIOS Bank ID (D, e.g. 0x80) to never overwrite HBIOS
	LD	HL,EXT_BANK_TABLE
	LD	B,0			; Counter for populated text slot banks

POPULATE_BANK_LOOP:
	DEC	C			; Allocate downward: 0x8C, 0x8B...
	LD	A,C
	CP	D			; Compare with BIOS Bank ID (D)
	JR	Z,POPULATE_BANK_DONE	; Stop if C == BIOS Bank ID!
	JR	C,POPULATE_BANK_DONE	; Stop if C < BIOS Bank ID!

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

IFRB_NO_BANKS:
	XOR	A
	LD	(LINE_TABLE_BANK),A
	LD	(LINE_TABLE_BANK_1),A
	LD	(EXT_BANK_COUNT),A
	LD	HL,MAX_DOC_LINES_16K
	LD	(MAX_DOC_LINES_LIMIT),HL
	RET

;==============================================================================
; Far RAM Line Table Subsystem (16,384 Lines in 32KB Far RAM Bank)
;==============================================================================

;------------------------------------------------------------------------------
; GET_LINE_SLOT: Retrieve 16-bit slot ID for document line BC from Far RAM
; Inputs: BC = Document Line Index (0..MAX_DOC_LINES-1)
; Returns: HL = 16-bit physical slot ID
; Preserves: BC, DE
;------------------------------------------------------------------------------
GET_LINE_SLOT:
	PUSH	BC
	PUSH	DE

	; Determine Bank (Bank 0 if BC < 16384, Bank 1 if BC >= 16384)
	BIT	6,B
	JR	NZ,GLS_BANK_1
	LD	A,(LINE_TABLE_BANK)
	JR	GLS_GOT_BANK
GLS_BANK_1:
	LD	A,(LINE_TABLE_BANK_1)
GLS_GOT_BANK:
	LD	E,A			; E = Line Table Bank (Src)

	; Calculate far byte offset = (BC & 0x3FFF) * 2
	LD	L,C
	LD	H,B
	RES	6,H			; Clear bit 14 so HL is 0..16383
	ADD	HL,HL			; HL = far byte offset (0..32766)

	; SYSSETCPY: D = User Bank, E = Line Table Bank, HL = 2 bytes
	PUSH	HL			; Save far offset
	PUSH	DE			; Save E (Line Table Bank)
	PUSH	IX
	LD	B,0F4H			; SYSSETCPY
	LD	A,(CPM_USER_BANK)
	LD	D,A
	; E is already Line Table Bank!
	LD	HL,2
	RST	08H
	POP	IX
	POP	DE
	POP	HL			; Restore far offset into HL

	; SYSBNKCPY: HL = Far Src Addr, DE = Local Dest Addr
	LD	DE,LINE_SLOT_TEMP
	PUSH	IX
	LD	B,0F5H			; SYSBNKCPY
	RST	08H
	POP	IX

	LD	HL,(LINE_SLOT_TEMP)	; HL = 16-bit slot ID

	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; SET_LINE_SLOT: Store 16-bit slot ID for document line BC into Far RAM
; Inputs: BC = Document Line Index (0..MAX_DOC_LINES-1)
;         HL = 16-bit physical slot ID
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
SET_LINE_SLOT:
	PUSH	BC
	PUSH	DE
	PUSH	HL			; Save slot ID

	LD	(LINE_SLOT_TEMP),HL

	; Determine Bank (Bank 0 if BC < 16384, Bank 1 if BC >= 16384)
	BIT	6,B
	JR	NZ,SLS_BANK_1
	LD	A,(LINE_TABLE_BANK)
	JR	SLS_GOT_BANK
SLS_BANK_1:
	LD	A,(LINE_TABLE_BANK_1)
SLS_GOT_BANK:
	LD	D,A			; D = Line Table Bank (Dest)

	; Calculate far byte offset = (BC & 0x3FFF) * 2
	LD	L,C
	LD	H,B
	RES	6,H
	ADD	HL,HL			; HL = far byte offset (0..32766)

	; SYSSETCPY: D = Line Table Bank, E = User Bank, HL = 2 bytes
	PUSH	HL			; Save far destination address
	PUSH	DE			; Save D (Line Table Bank)
	PUSH	IX
	LD	B,0F4H			; SYSSETCPY
	; D is already Line Table Bank!
	LD	A,(CPM_USER_BANK)
	LD	E,A
	LD	HL,2
	RST	08H
	POP	IX
	POP	DE
	POP	HL			; Restore far destination address into HL

	; SYSBNKCPY: HL = Local Src Addr, DE = Far Dest Addr
	EX	DE,HL			; DE = Far Dest Addr
	LD	HL,LINE_SLOT_TEMP	; HL = Local Src Addr
	PUSH	IX
	LD	B,0F5H			; SYSBNKCPY
	RST	08H
	POP	IX

	POP	HL			; Restore HL (slot ID)
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; SHIFT_LINE_SLOTS_UP: Shift W line slots upward from higher to lower line indices
; Inputs: DE = Destination Line Index
;         HL = Source Line Index (DE < HL)
;         BC = Word Count (W lines to shift)
; Preserves: All registers except AF
;------------------------------------------------------------------------------
SHIFT_LINE_SLOTS_UP:
	LD	A,B
	OR	C
	RET	Z

	PUSH	BC
	PUSH	DE
	PUSH	HL

	LD	(SLOT_SHIFT_REM),BC
	LD	(SLOT_SHIFT_SRC),HL
	LD	(SLOT_SHIFT_DEST),DE

SLOTS_UP_LOOP:
	LD	HL,(SLOT_SHIFT_REM)
	LD	A,H
	OR	L
	JP	Z,SLOTS_UP_DONE

	; Candidate chunk = min(128, rem)
	LD	DE,128
	CALL	CMP_HL_DE		; Carry=1 if HL < 128
	JR	C,SLOTS_UP_USE_REM
	EX	DE,HL			; HL = 128
SLOTS_UP_USE_REM:
	LD	(SLOT_SHIFT_CHUNK),HL	; Save candidate chunk

	; Check distance to line 16384 boundary for Source
	LD	DE,(SLOT_SHIFT_SRC)
	BIT	6,D			; Source >= 16384?
	JR	NZ,SLOTS_UP_SRC_OK	; In Bank 1, no boundary ahead
	; Source < 16384: distance = 16384 - Source
	LD	HL,16384
	OR	A
	SBC	HL,DE			; HL = distance
	EX	DE,HL			; DE = distance
	LD	HL,(SLOT_SHIFT_CHUNK)
	CALL	CMP_HL_DE		; Carry=1 if chunk < distance
	JR	C,SLOTS_UP_SRC_OK
	LD	(SLOT_SHIFT_CHUNK),DE	; Clamp chunk to distance
SLOTS_UP_SRC_OK:

	; Check distance to line 16384 boundary for Dest
	LD	DE,(SLOT_SHIFT_DEST)
	BIT	6,D			; Dest >= 16384?
	JR	NZ,SLOTS_UP_DEST_OK	; In Bank 1, no boundary ahead
	; Dest < 16384: distance = 16384 - Dest
	LD	HL,16384
	OR	A
	SBC	HL,DE			; HL = distance
	EX	DE,HL			; DE = distance
	LD	HL,(SLOT_SHIFT_CHUNK)
	CALL	CMP_HL_DE		; Carry=1 if chunk < distance
	JR	C,SLOTS_UP_DEST_OK
	LD	(SLOT_SHIFT_CHUNK),DE	; Clamp chunk to distance
SLOTS_UP_DEST_OK:

	; Determine Source Bank & In-Bank Offset:
	LD	BC,(SLOT_SHIFT_SRC)
	BIT	6,B
	JR	NZ,SLOTS_UP_SRC_B1
	LD	A,(LINE_TABLE_BANK)
	JR	SLOTS_UP_GOT_SBANK
SLOTS_UP_SRC_B1:
	LD	A,(LINE_TABLE_BANK_1)
SLOTS_UP_GOT_SBANK:
	LD	(FAR_SRC_BANK),A

	LD	L,C
	LD	H,B
	RES	6,H
	ADD	HL,HL
	LD	(FAR_SRC_ADDR),HL

	; Determine Dest Bank & In-Bank Offset:
	LD	BC,(SLOT_SHIFT_DEST)
	BIT	6,B
	JR	NZ,SLOTS_UP_DST_B1
	LD	A,(LINE_TABLE_BANK)
	JR	SLOTS_UP_GOT_DBANK
SLOTS_UP_DST_B1:
	LD	A,(LINE_TABLE_BANK_1)
SLOTS_UP_GOT_DBANK:
	LD	(FAR_DEST_BANK),A

	LD	L,C
	LD	H,B
	RES	6,H
	ADD	HL,HL
	LD	(FAR_DEST_ADDR),HL

	; Calculate byte count = chunk * 2
	LD	HL,(SLOT_SHIFT_CHUNK)
	ADD	HL,HL
	LD	(SLOT_SHIFT_BYTES),HL

	; 1. Copy chunk from Far RAM Source Bank to local LINE_SHIFT_BUF
	PUSH	IX
	LD	B,0F4H			; SYSSETCPY
	LD	A,(CPM_USER_BANK)
	LD	D,A			; Dest = User Bank
	LD	A,(FAR_SRC_BANK)
	LD	E,A			; Src = Line Table Source Bank
	LD	HL,(SLOT_SHIFT_BYTES)
	RST	08H
	POP	IX

	PUSH	IX
	LD	B,0F5H			; SYSBNKCPY
	LD	DE,LINE_SHIFT_BUF	; Local Dest
	LD	HL,(FAR_SRC_ADDR)	; Far Src
	RST	08H
	POP	IX

	; 2. Copy chunk from local LINE_SHIFT_BUF to Far RAM Dest Bank
	PUSH	IX
	LD	B,0F4H			; SYSSETCPY
	LD	A,(FAR_DEST_BANK)
	LD	D,A			; Dest = Line Table Dest Bank
	LD	A,(CPM_USER_BANK)
	LD	E,A			; Src = User Bank
	LD	HL,(SLOT_SHIFT_BYTES)
	RST	08H
	POP	IX

	PUSH	IX
	LD	B,0F5H			; SYSBNKCPY
	LD	DE,(FAR_DEST_ADDR)	; Far Dest
	LD	HL,LINE_SHIFT_BUF	; Local Src
	RST	08H
	POP	IX

	; Advance Source and Dest by CHUNK; Decrement Rem by CHUNK
	LD	DE,(SLOT_SHIFT_CHUNK)
	LD	HL,(SLOT_SHIFT_SRC)
	ADD	HL,DE
	LD	(SLOT_SHIFT_SRC),HL

	LD	HL,(SLOT_SHIFT_DEST)
	ADD	HL,DE
	LD	(SLOT_SHIFT_DEST),HL

	LD	HL,(SLOT_SHIFT_REM)
	OR	A
	SBC	HL,DE
	LD	(SLOT_SHIFT_REM),HL

	JP	SLOTS_UP_LOOP

SLOTS_UP_DONE:
	POP	HL
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; SHIFT_LINE_SLOTS_DOWN: Shift W line slots downward from lower to higher indices
; Inputs: DE = Destination Line Index
;         HL = Source Line Index (DE > HL)
;         BC = Word Count (W lines to shift)
; Preserves: All registers except AF
;------------------------------------------------------------------------------
SHIFT_LINE_SLOTS_DOWN:
	LD	A,B
	OR	C
	RET	Z

	PUSH	BC
	PUSH	DE
	PUSH	HL

	LD	(SLOT_SHIFT_REM),BC

	; End Source line = HL + BC
	ADD	HL,BC
	LD	(SLOT_SHIFT_SRC),HL

	; End Dest line = DE + BC
	EX	DE,HL
	ADD	HL,BC
	LD	(SLOT_SHIFT_DEST),HL

SLOTS_DOWN_LOOP:
	LD	HL,(SLOT_SHIFT_REM)
	LD	A,H
	OR	L
	JP	Z,SLOTS_DOWN_DONE

	; Candidate chunk = min(128, rem)
	LD	DE,128
	CALL	CMP_HL_DE		; Carry=1 if HL < 128
	JR	C,SLOTS_DOWN_USE_REM
	EX	DE,HL			; HL = 128
SLOTS_DOWN_USE_REM:
	LD	(SLOT_SHIFT_CHUNK),HL	; Save candidate chunk

	; Check distance down to line 16384 boundary for Source end
	LD	DE,(SLOT_SHIFT_SRC)
	LD	HL,16384
	CALL	CMP_HL_DE		; Carry=1 if 16384 < DE (src_end > 16384)
	JR	NC,SLOTS_DOWN_SRC_OK
	; src_end > 16384: distance = src_end - 16384
	EX	DE,HL			; HL = src_end, DE = 16384
	OR	A
	SBC	HL,DE			; HL = distance
	EX	DE,HL			; DE = distance
	LD	HL,(SLOT_SHIFT_CHUNK)
	CALL	CMP_HL_DE		; Carry=1 if chunk < distance
	JR	C,SLOTS_DOWN_SRC_OK
	LD	(SLOT_SHIFT_CHUNK),DE	; Clamp chunk to distance
SLOTS_DOWN_SRC_OK:

	; Check distance down to line 16384 boundary for Dest end
	LD	DE,(SLOT_SHIFT_DEST)
	LD	HL,16384
	CALL	CMP_HL_DE		; Carry=1 if 16384 < DE (dest_end > 16384)
	JR	NC,SLOTS_DOWN_DEST_OK
	; dest_end > 16384: distance = dest_end - 16384
	EX	DE,HL			; HL = dest_end, DE = 16384
	OR	A
	SBC	HL,DE			; HL = distance
	EX	DE,HL			; DE = distance
	LD	HL,(SLOT_SHIFT_CHUNK)
	CALL	CMP_HL_DE		; Carry=1 if chunk < distance
	JR	C,SLOTS_DOWN_DEST_OK
	LD	(SLOT_SHIFT_CHUNK),DE	; Clamp chunk to distance
SLOTS_DOWN_DEST_OK:

	; Move Source and Dest back by CHUNK to get chunk start lines
	LD	DE,(SLOT_SHIFT_CHUNK)
	LD	HL,(SLOT_SHIFT_SRC)
	OR	A
	SBC	HL,DE
	LD	(SLOT_SHIFT_SRC),HL	; Chunk source start line

	LD	HL,(SLOT_SHIFT_DEST)
	OR	A
	SBC	HL,DE
	LD	(SLOT_SHIFT_DEST),HL	; Chunk dest start line

	; Determine Source Bank & In-Bank Offset:
	LD	BC,(SLOT_SHIFT_SRC)
	BIT	6,B
	JR	NZ,SLOTS_DN_SRC_B1
	LD	A,(LINE_TABLE_BANK)
	JR	SLOTS_DN_GOT_SBANK
SLOTS_DN_SRC_B1:
	LD	A,(LINE_TABLE_BANK_1)
SLOTS_DN_GOT_SBANK:
	LD	(FAR_SRC_BANK),A

	LD	L,C
	LD	H,B
	RES	6,H
	ADD	HL,HL
	LD	(FAR_SRC_ADDR),HL

	; Determine Dest Bank & In-Bank Offset:
	LD	BC,(SLOT_SHIFT_DEST)
	BIT	6,B
	JR	NZ,SLOTS_DN_DST_B1
	LD	A,(LINE_TABLE_BANK)
	JR	SLOTS_DN_GOT_DBANK
SLOTS_DN_DST_B1:
	LD	A,(LINE_TABLE_BANK_1)
SLOTS_DN_GOT_DBANK:
	LD	(FAR_DEST_BANK),A

	LD	L,C
	LD	H,B
	RES	6,H
	ADD	HL,HL
	LD	(FAR_DEST_ADDR),HL

	; Calculate byte count = chunk * 2
	LD	HL,(SLOT_SHIFT_CHUNK)
	ADD	HL,HL
	LD	(SLOT_SHIFT_BYTES),HL

	; 1. Copy chunk from Far RAM Source Bank to local LINE_SHIFT_BUF
	PUSH	IX
	LD	B,0F4H			; SYSSETCPY
	LD	A,(CPM_USER_BANK)
	LD	D,A			; Dest = User Bank
	LD	A,(FAR_SRC_BANK)
	LD	E,A			; Src = Line Table Source Bank
	LD	HL,(SLOT_SHIFT_BYTES)
	RST	08H
	POP	IX

	PUSH	IX
	LD	B,0F5H			; SYSBNKCPY
	LD	DE,LINE_SHIFT_BUF	; Local Dest
	LD	HL,(FAR_SRC_ADDR)	; Far Src
	RST	08H
	POP	IX

	; 2. Copy chunk from local LINE_SHIFT_BUF to Far RAM Dest Bank
	PUSH	IX
	LD	B,0F4H			; SYSSETCPY
	LD	A,(FAR_DEST_BANK)
	LD	D,A			; Dest = Line Table Dest Bank
	LD	A,(CPM_USER_BANK)
	LD	E,A			; Src = User Bank
	LD	HL,(SLOT_SHIFT_BYTES)
	RST	08H
	POP	IX

	PUSH	IX
	LD	B,0F5H			; SYSBNKCPY
	LD	DE,(FAR_DEST_ADDR)	; Far Dest
	LD	HL,LINE_SHIFT_BUF	; Local Src
	RST	08H
	POP	IX

	; Decrement REM by CHUNK
	LD	DE,(SLOT_SHIFT_CHUNK)
	LD	HL,(SLOT_SHIFT_REM)
	OR	A
	SBC	HL,DE
	LD	(SLOT_SHIFT_REM),HL

	JP	SLOTS_DOWN_LOOP

SLOTS_DOWN_DONE:
	POP	HL
	POP	DE
	POP	BC
	RET

; Subroutine: WRITE_SLOTS_TO_ONE_BANK
; Inputs: A = Line Table Bank ID
;         BC = In-Bank Destination Line Index (0..16383)
;         HL = Source Buffer in RAM
;         DE = Line Count (K lines)
; Destroys: AF, BC, DE, HL
WRITE_SLOTS_TO_ONE_BANK:
	LD	(FAR_DEST_BANK),A
	PUSH	HL			; Save Source Buffer address

	; Far Dest Addr = BC * 2
	LD	L,C
	LD	H,B
	ADD	HL,HL
	EX	DE,HL			; DE = Far Dest Addr, HL = Line Count (K)

	; Byte count = K * 2
	ADD	HL,HL			; HL = Byte Count

	; SYSSETCPY: D = Dest Bank, E = User Bank, HL = Byte Count
	PUSH	DE			; Save Far Dest Addr
	PUSH	IX
	LD	B,0F4H			; SYSSETCPY
	LD	A,(FAR_DEST_BANK)
	LD	D,A
	LD	A,(CPM_USER_BANK)
	LD	E,A
	RST	08H
	POP	IX

	; SYSBNKCPY: HL = Local Src Addr, DE = Far Dest Addr
	POP	DE			; DE = Far Dest Addr
	POP	HL			; HL = Local Src Addr
	PUSH	IX
	LD	B,0F5H			; SYSBNKCPY
	RST	08H
	POP	IX
	RET

;------------------------------------------------------------------------------
; WRITE_LINE_SLOTS_FROM_RAM: Copy K words from local RAM buffer into Line Table
; Inputs: BC = Destination Line Index (0..32767)
;         HL = Source Buffer in RAM (e.g. COPY_SLOTS_BUF)
;         DE = Word Count (K lines)
; Preserves: None
;------------------------------------------------------------------------------
WRITE_LINE_SLOTS_FROM_RAM:
	LD	A,D
	OR	E
	RET	Z

	LD	(WLSR_SRC),HL
	LD	(WLSR_K),DE
	LD	(WLSR_DEST),BC

	; Check if destination line BC >= 16384
	BIT	6,B
	JR	NZ,WLSR_BANK_1

	; Destination starts in Bank 0 (BC < 16384).
	; Does BC + DE > 16384?
	LD	H,B
	LD	L,C
	ADD	HL,DE			; HL = End line (BC + DE)
	LD	DE,16384
	OR	A
	SBC	HL,DE
	JR	C,WLSR_BANK_0_ALL	; End line < 16384 -> all in Bank 0
	JR	Z,WLSR_BANK_0_ALL	; End line == 16384 -> all in Bank 0

	; Straddles Bank 0 and Bank 1:
	; K1 = 16384 - BC
	LD	HL,16384
	LD	BC,(WLSR_DEST)
	OR	A
	SBC	HL,BC			; HL = K1
	PUSH	HL			; Save K1

	; Write Part 1: K1 lines to Bank 0 at (WLSR_DEST)
	EX	DE,HL			; DE = K1
	LD	BC,(WLSR_DEST)
	LD	HL,(WLSR_SRC)
	LD	A,(LINE_TABLE_BANK)
	CALL	WRITE_SLOTS_TO_ONE_BANK

	; K2 = WLSR_K - K1
	POP	DE			; DE = K1
	LD	HL,(WLSR_K)
	OR	A
	SBC	HL,DE			; HL = K2 = total K - K1
	EX	DE,HL			; DE = K2, HL = K1

	; RAM buffer advanced by K1 * 2 bytes:
	ADD	HL,HL			; HL = K1 * 2 bytes
	LD	BC,(WLSR_SRC)
	ADD	HL,BC			; HL = WLSR_SRC + K1 * 2

	; Write Part 2: K2 lines to Bank 1 starting at index 0
	LD	BC,0			; In-bank line index = 0
	LD	A,(LINE_TABLE_BANK_1)
	CALL	WRITE_SLOTS_TO_ONE_BANK
	RET

WLSR_BANK_0_ALL:
	LD	A,(LINE_TABLE_BANK)
	LD	BC,(WLSR_DEST)
	LD	HL,(WLSR_SRC)
	LD	DE,(WLSR_K)
	CALL	WRITE_SLOTS_TO_ONE_BANK
	RET

WLSR_BANK_1:
	; BC >= 16384: in-bank line index = BC - 16384 (clear bit 14)
	RES	6,B
	LD	A,(LINE_TABLE_BANK_1)
	LD	HL,(WLSR_SRC)
	LD	DE,(WLSR_K)
	CALL	WRITE_SLOTS_TO_ONE_BANK
	RET

;==============================================================================
; Disk-Backed Virtual Slot Paging Subsystem (Phase 4)
; Transparent 384 KB Far RAM cache backed by $$$SE$$$.SWP via BDOS Random I/O
;==============================================================================

BIT_MASK_TABLE:
	DB	001H, 002H, 004H, 008H, 010H, 020H, 040H, 080H

;------------------------------------------------------------------------------
; TEST_PAGE_ON_DISK: Test if page A has been written to swap file
; Input: A = 8-bit Page Number (0..255)
; Returns: Z flag set if bit is 0 (not on disk), NZ flag set if bit is 1 (on disk)
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
TEST_PAGE_ON_DISK:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	C,A
	AND	7
	LD	E,A
	LD	D,0
	LD	HL,BIT_MASK_TABLE
	ADD	HL,DE
	LD	B,(HL)			; B = bit mask (1, 2, 4, 8...)

	LD	A,C
	RRCA
	RRCA
	RRCA
	AND	01FH			; A = byte offset (0..31)
	LD	E,A
	LD	HL,PAGE_ON_DISK_BITMAP
	ADD	HL,DE
	LD	A,(HL)
	AND	B			; Test bit: Z if 0, NZ if 1
	POP	HL
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; SET_PAGE_ON_DISK: Mark page A as written to swap file in PAGE_ON_DISK_BITMAP
; Input: A = 8-bit Page Number (0..255)
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
SET_PAGE_ON_DISK:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	C,A
	AND	7
	LD	E,A
	LD	D,0
	LD	HL,BIT_MASK_TABLE
	ADD	HL,DE
	LD	B,(HL)			; B = bit mask

	LD	A,C
	RRCA
	RRCA
	RRCA
	AND	01FH
	LD	E,A
	LD	HL,PAGE_ON_DISK_BITMAP
	ADD	HL,DE
	LD	A,(HL)
	OR	B			; Set bit
	LD	(HL),A
	POP	HL
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; CALC_PAGE_SLOT_COUNT: Determine number of active slots in page A
; Input: A = 8-bit Page Number (0..255)
; Returns: Z flag set if 0 slots; NZ set with B = loop count (0 for 256, or 1..255)
; Preserves: DE
;------------------------------------------------------------------------------
CALC_PAGE_SLOT_COUNT:
	PUSH	HL
	LD	HL,(NEXT_FRESH_SLOT)
	CP	H
	JR	C,CPSC_FULL		; Page < H_fresh -> full 256 slots
	JR	NZ,CPSC_EMPTY		; Page > H_fresh -> empty 0 slots
	; Page == H_fresh
	LD	A,L			; A = L_fresh
	OR	A
	JR	Z,CPSC_EMPTY		; If L_fresh == 0, 0 slots
	LD	B,A			; B = L_fresh (1..255)
	POP	HL
	OR	A			; NZ set
	RET

CPSC_FULL:
	LD	B,0			; 0 -> DJNZ executes 256 times
	POP	HL
	LD	A,1			; NZ set
	OR	A
	RET

CPSC_EMPTY:
	POP	HL
	XOR	A			; Z set
	RET

;------------------------------------------------------------------------------
; CREATE_SWAP_FILE: Create temporary swap file $$$SE$$$.SWP on current drive
; Returns: Carry = 0 on success, Carry = 1 on failure
;------------------------------------------------------------------------------
CREATE_SWAP_FILE:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	; Initialize SWAP_FCB with drive matching document (WORK_FCB)
	LD	A,(WORK_FCB)
	LD	(SWAP_FCB),A
	LD	HL,SWAP_FCB+1
	LD	(HL),'$'
	INC	HL
	LD	(HL),'$'
	INC	HL
	LD	(HL),'$'
	INC	HL
	LD	(HL),'S'
	INC	HL
	LD	(HL),'E'
	INC	HL
	LD	(HL),'$'
	INC	HL
	LD	(HL),'$'
	INC	HL
	LD	(HL),'$'
	INC	HL
	LD	(HL),'S'
	INC	HL
	LD	(HL),'W'
	INC	HL
	LD	(HL),'P'
	INC	HL

	; Zero bytes 12..35 (24 bytes)
	LD	B,24
CSF_ZERO1:
	LD	(HL),0
	INC	HL
	DJNZ	CSF_ZERO1

	; Delete any existing $$$SE$$$.SWP (BDOS 19)
	LD	DE,SWAP_FCB
	LD	C,19
	CALL	BDOS_ENTRY

	; Re-zero bytes 12..35 after delete
	LD	HL,SWAP_FCB+12
	LD	B,24
CSF_ZERO2:
	LD	(HL),0
	INC	HL
	DJNZ	CSF_ZERO2

	; Create $$$SE$$$.SWP (BDOS 22)
	LD	DE,SWAP_FCB
	LD	C,22
	CALL	BDOS_ENTRY
	CP	0FFH
	JR	Z,CSF_FAIL

	LD	A,1
	LD	(SWAP_ACTIVE),A

	POP	HL
	POP	DE
	POP	BC
	OR	A			; Carry = 0
	RET

CSF_FAIL:
	POP	HL
	POP	DE
	POP	BC
	SCF				; Carry = 1
	RET

;------------------------------------------------------------------------------
; CLEANUP_SWAP_FILE: Close and delete temporary swap file $$$SE$$$.SWP
;------------------------------------------------------------------------------
CLEANUP_SWAP_FILE:
	LD	A,(SWAP_ACTIVE)
	OR	A
	RET	Z			; Inactive: nothing to do

	PUSH	BC
	PUSH	DE
	PUSH	HL

	; Close SWAP_FCB (BDOS 16)
	LD	DE,SWAP_FCB
	LD	C,16
	CALL	BDOS_ENTRY

	; Delete SWAP_FCB (BDOS 19)
	LD	DE,SWAP_FCB
	LD	C,19
	CALL	BDOS_ENTRY

	XOR	A
	LD	(SWAP_ACTIVE),A

	POP	HL
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; FLUSH_BANK_TO_SWAP: Flush Far RAM bank B to $$$SE$$$.SWP
; Inputs: B = bank index (1..11), SWAP_PAGE_OLD = page number
; Returns: Carry = 0 on success, Carry = 1 on error
;------------------------------------------------------------------------------
FLUSH_BANK_TO_SWAP:
	; Determine Far RAM bank ID
	LD	HL,EXT_BANK_TABLE
	LD	E,B
	LD	D,0
	ADD	HL,DE
	LD	A,(HL)
	LD	(SWAP_BNK_ID),A

	; Calculate number of slots to flush
	LD	A,(SWAP_PAGE_OLD)
	CALL	CALC_PAGE_SLOT_COUNT
	JR	Z,FBTS_DONE_SUCCESS

	; 1. Set BDOS DMA to SWAP_IO_BUF once before loop
	PUSH	BC			; Save B = slot count
	LD	DE,SWAP_IO_BUF
	LD	C,26			; BDOS Set DMA
	CALL	BDOS_ENTRY
	POP	BC			; Restore B

	; 2. Setup SWAP_FCB random record high bytes once before loop
	LD	A,(SWAP_PAGE_OLD)
	LD	(SWAP_FCB+34),A		; r1
	XOR	A
	LD	(SWAP_FCB+35),A		; r2

	LD	C,0			; C = slot index (0..N-1)
	LD	HL,0			; HL = Far RAM source offset (0, 128, 256...)

FBTS_SLOT_LOOP:
	PUSH	BC			; Save B (remaining count), C (slot index)
	PUSH	HL			; Save Far RAM offset

	; Setup SWAP_FCB record r0 = C, r1 = SWAP_PAGE_OLD, r2 = 0
	LD	A,C
	LD	(SWAP_FCB+33),A		; r0
	LD	A,(SWAP_PAGE_OLD)
	LD	(SWAP_FCB+34),A		; r1
	XOR	A
	LD	(SWAP_FCB+35),A		; r2

	; SYSSETCPY: D = CPM_USER_BANK, E = SWAP_BNK_ID, HL = 128
	PUSH	IX
	LD	B,0F4H			; SYSSETCPY
	LD	A,(CPM_USER_BANK)
	LD	D,A
	LD	A,(SWAP_BNK_ID)
	LD	E,A
	LD	HL,FAR_SLOT_SIZE	; 128 bytes
	RST	08H
	POP	IX

	; Copy slot from Far RAM offset HL to local SWAP_IO_BUF
	POP	HL			; HL = Far RAM source offset
	PUSH	HL
	LD	DE,SWAP_IO_BUF
	PUSH	IX
	LD	B,0F5H			; SYSBNKCPY
	RST	08H
	POP	IX

	; BDOS 34 (Write Random)
	LD	DE,SWAP_FCB
	LD	C,34
	CALL	BDOS_ENTRY
	OR	A
	JR	NZ,FBTS_WRITE_ERR

	; Advance Far RAM offset by 128 for next slot
	POP	HL
	LD	DE,FAR_SLOT_SIZE
	ADD	HL,DE

	POP	BC
	INC	C
	DJNZ	FBTS_SLOT_LOOP

	; Flush complete: mark page on disk in bitmap
	LD	A,(SWAP_PAGE_OLD)
	CALL	SET_PAGE_ON_DISK

	; Restore BDOS DMA to DEFAULT_DMA (0x0080)
	LD	DE,DEFAULT_DMA
	LD	C,26
	CALL	BDOS_ENTRY

FBTS_DONE_SUCCESS:
	OR	A			; Carry = 0
	RET

FBTS_WRITE_ERR:
	POP	HL
	POP	BC
	; Restore BDOS DMA to DEFAULT_DMA (0x0080)
	LD	DE,DEFAULT_DMA
	LD	C,26
	CALL	BDOS_ENTRY

	LD	A,1
	LD	(FILE_IS_TRUNCATED),A
	CALL	SET_OOM_STATUS
	SCF				; Carry = 1
	RET

;------------------------------------------------------------------------------
; FETCH_PAGE_FROM_SWAP: Fetch page from $$$SE$$$.SWP into Far RAM bank B
; Inputs: B = bank index (1..11), SWAP_PAGE_NEW = page number
; Returns: Carry = 0 on success, Carry = 1 on error
;------------------------------------------------------------------------------
FETCH_PAGE_FROM_SWAP:
	; Determine Far RAM bank ID
	LD	HL,EXT_BANK_TABLE
	LD	E,B
	LD	D,0
	ADD	HL,DE
	LD	A,(HL)
	LD	(SWAP_BNK_ID),A

	; Calculate number of slots to fetch
	LD	A,(SWAP_PAGE_NEW)
	CALL	CALC_PAGE_SLOT_COUNT
	JP	Z,FPFS_DONE_SUCCESS

	; 1. Set BDOS DMA to SWAP_IO_BUF once before loop
	PUSH	BC
	LD	DE,SWAP_IO_BUF
	LD	C,26
	CALL	BDOS_ENTRY
	POP	BC

	; 2. Setup SWAP_FCB random record high bytes once before loop
	LD	A,(SWAP_PAGE_NEW)
	LD	(SWAP_FCB+34),A		; r1
	XOR	A
	LD	(SWAP_FCB+35),A		; r2

	LD	C,0			; C = slot index (0..N-1)
	LD	HL,0			; HL = Far RAM dest offset (0, 128, 256...)

FPFS_SLOT_LOOP:
	PUSH	BC
	PUSH	HL

	; Setup SWAP_FCB record r0 = C, r1 = SWAP_PAGE_NEW, r2 = 0
	LD	A,C
	LD	(SWAP_FCB+33),A		; r0
	LD	A,(SWAP_PAGE_NEW)
	LD	(SWAP_FCB+34),A		; r1
	XOR	A
	LD	(SWAP_FCB+35),A		; r2

	; BDOS 33 (Read Random)
	LD	DE,SWAP_FCB
	LD	C,33
	CALL	BDOS_ENTRY
	OR	A
	JR	Z,FPFS_READ_OK

	; Unwritten record / EOF: zero-fill buffer
	LD	HL,SWAP_IO_BUF
	LD	(HL),0
	LD	DE,SWAP_IO_BUF+1
	LD	BC,127
	LDIR

FPFS_READ_OK:
	; SYSSETCPY: D = SWAP_BNK_ID, E = CPM_USER_BANK, HL = 128
	PUSH	IX
	LD	B,0F4H			; SYSSETCPY
	LD	A,(SWAP_BNK_ID)
	LD	D,A
	LD	A,(CPM_USER_BANK)
	LD	E,A
	LD	HL,FAR_SLOT_SIZE	; 128 bytes
	RST	08H
	POP	IX

	; Copy slot from SWAP_IO_BUF into Far RAM offset
	POP	DE			; DE = Far RAM dest offset
	PUSH	DE
	LD	HL,SWAP_IO_BUF		; Local source buffer
	PUSH	IX
	LD	B,0F5H			; SYSBNKCPY
	RST	08H
	POP	IX

	; Advance Far RAM offset by 128 for next slot
	POP	HL
	LD	DE,FAR_SLOT_SIZE
	ADD	HL,DE

	POP	BC
	INC	C
	DJNZ	FPFS_SLOT_LOOP

	; Restore BDOS DMA to DEFAULT_DMA (0x0080)
	LD	DE,DEFAULT_DMA
	LD	C,26
	CALL	BDOS_ENTRY

FPFS_DONE_SUCCESS:
	OR	A			; Carry = 0
	RET

;------------------------------------------------------------------------------
; SELECT_VICTIM_BANK: Select victim bank with maximum distance from SWAP_PAGE_TEMP
; Inputs: SWAP_PAGE_TEMP = target page number (0..255)
; Returns: B = victim bank index (1..11)
; Preserves: None
;------------------------------------------------------------------------------
SELECT_VICTIM_BANK:
	LD	C,1			; C = candidate bank index (1 .. EXT_BANK_COUNT-1)
	LD	B,1			; B = best victim bank index
	LD	D,0			; D = max distance found so far
	LD	HL,BANK_PAGE_TABLE+1
SVB_LOOP:
	LD	A,(EXT_BANK_COUNT)
	CP	C
	JR	Z,SVB_DONE
	JR	C,SVB_DONE
	LD	A,(SWAP_PAGE_TEMP)
	SUB	(HL)			; A = target - resident
	JR	NC,SVB_POS
	NEG				; A = abs(target - resident)
SVB_POS:
	CP	D
	JR	C,SVB_NOT_MAX
	JR	Z,SVB_NOT_MAX
	LD	D,A			; New max distance
	LD	B,C			; Best victim bank = C
SVB_NOT_MAX:
	INC	HL
	INC	C
	JR	SVB_LOOP
SVB_DONE:
	RET

;------------------------------------------------------------------------------
; HANDLE_PAGE_FAULT: Evict victim bank if dirty, fetch target page into victim bank
; Input: SWAP_PAGE_TEMP = target page number
; Returns: B = allocated victim bank index (1..11), Carry = 0 on success, Carry = 1 on error
;------------------------------------------------------------------------------
HANDLE_PAGE_FAULT:
	; Check if swap file is active
	LD	A,(SWAP_ACTIVE)
	OR	A
	JR	NZ,HPF_HAVE_SWAP

	CALL	CREATE_SWAP_FILE
	RET	C

HPF_HAVE_SWAP:
	; Select victim bank with maximum distance from SWAP_PAGE_TEMP
	CALL	SELECT_VICTIM_BANK	; Returns B = victim bank index (1..11)

	; Check if victim bank B is dirty
	PUSH	BC
	LD	HL,BANK_DIRTY_TABLE
	LD	E,B
	LD	D,0
	ADD	HL,DE
	LD	A,(HL)
	OR	A
	JR	Z,HPF_SKIP_FLUSH

	; Flush dirty victim bank B
	LD	HL,BANK_PAGE_TABLE
	ADD	HL,DE
	LD	A,(HL)			; A = OLD_PAGE resident in bank B
	LD	(SWAP_PAGE_OLD),A
	CALL	FLUSH_BANK_TO_SWAP
	POP	BC
	RET	C			; Return Carry = 1 if flush error
	JR	HPF_DO_FETCH

HPF_SKIP_FLUSH:
	POP	BC

HPF_DO_FETCH:
	; Check if target page (SWAP_PAGE_TEMP) exists on disk
	PUSH	BC
	LD	A,(SWAP_PAGE_TEMP)
	CALL	TEST_PAGE_ON_DISK
	JR	Z,HPF_SKIP_FETCH	; Bit = 0 -> not on disk, skip fetch!

	LD	A,(SWAP_PAGE_TEMP)
	LD	(SWAP_PAGE_NEW),A
	CALL	FETCH_PAGE_FROM_SWAP
	POP	BC
	RET	C			; Return Carry = 1 if fetch error
	JR	HPF_UPDATE_TBL

HPF_SKIP_FETCH:
	POP	BC

HPF_UPDATE_TBL:
	; Update BANK_PAGE_TABLE[B] = SWAP_PAGE_TEMP
	LD	HL,BANK_PAGE_TABLE
	LD	E,B
	LD	D,0
	ADD	HL,DE
	LD	A,(SWAP_PAGE_TEMP)
	LD	(HL),A

	; Clear dirty flag: BANK_DIRTY_TABLE[B] = 0
	LD	HL,BANK_DIRTY_TABLE
	ADD	HL,DE
	LD	(HL),0

	OR	A			; Carry = 0 (success)
	RET

;------------------------------------------------------------------------------
; ENSURE_PAGE_RESIDENT: Ensure 32KB page A is resident in Far RAM banks
; Input: A = 8-bit Page Number (0..255)
; Returns: A = Far RAM Bank ID (e.g. 0x8C), Carry = 0 on success, Carry = 1 on error
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
ENSURE_PAGE_RESIDENT:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	LD	(SWAP_PAGE_TEMP),A

	; Check if Page 0 (pinned in Bank 0)
	OR	A
	JR	NZ,EPR_NOT_PAGE_0
	XOR	A
	LD	(SWAP_BANK_TEMP),A
	LD	A,(EXT_BANK_TABLE)	; Bank 0 ID
	POP	HL
	POP	DE
	POP	BC
	OR	A			; Carry = 0
	RET

EPR_NOT_PAGE_0:
	; Scan BANK_PAGE_TABLE[1..EXT_BANK_COUNT-1] for Page (SWAP_PAGE_TEMP)
	LD	B,1			; Bank index 1..EXT_BANK_COUNT-1
	LD	HL,BANK_PAGE_TABLE+1
EPR_SCAN_LOOP:
	LD	A,(EXT_BANK_COUNT)
	CP	B
	JR	Z,EPR_PAGE_FAULT
	JR	C,EPR_PAGE_FAULT
	LD	A,(SWAP_PAGE_TEMP)
	CP	(HL)
	JR	Z,EPR_HIT
	INC	HL
	INC	B
	JR	EPR_SCAN_LOOP

EPR_PAGE_FAULT:
	; PAGE FAULT! Page (SWAP_PAGE_TEMP) is NOT resident in any bank.
	CALL	HANDLE_PAGE_FAULT	; Returns B = victim bank index (1..11), Carry on error
	JR	C,EPR_FAULT_ERR

EPR_HIT:
	LD	A,B
	LD	(SWAP_BANK_TEMP),A
	; Lookup Far RAM Bank ID in EXT_BANK_TABLE[B]
	LD	HL,EXT_BANK_TABLE
	LD	E,B
	LD	D,0
	ADD	HL,DE
	LD	A,(HL)			; A = Far RAM Bank ID

	POP	HL
	POP	DE
	POP	BC
	OR	A			; Carry = 0
	RET

EPR_FAULT_ERR:
	POP	HL
	POP	DE
	POP	BC
	SCF				; Carry = 1
	RET

;------------------------------------------------------------------------------
; ENSURE_PAGE_RESIDENT_DIRTY: Ensure page A is resident AND mark its bank dirty
; Input: A = 8-bit Page Number (0..255)
; Returns: A = Far RAM Bank ID, Carry = 0 on success, Carry = 1 on error
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
ENSURE_PAGE_RESIDENT_DIRTY:
	CALL	ENSURE_PAGE_RESIDENT
	RET	C
	PUSH	AF
	PUSH	HL
	PUSH	DE
	; Mark bank SWAP_BANK_TEMP dirty
	LD	A,(SWAP_BANK_TEMP)
	LD	E,A
	LD	D,0
	LD	HL,BANK_DIRTY_TABLE
	ADD	HL,DE
	LD	(HL),1
	POP	DE
	POP	HL
	POP	AF
	OR	A			; Carry = 0
	RET

;------------------------------------------------------------------------------
; INIT_PAGING_SYSTEM: Reset paging tables, bitmap, and clean up swap file
; Preserves: All registers
;------------------------------------------------------------------------------
INIT_PAGING_SYSTEM:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL

	CALL	CLEANUP_SWAP_FILE

	XOR	A
	LD	(SWAP_ACTIVE),A
	INC	A			; A = 1
	LD	(NEXT_VICTIM_BANK),A

	; Clear PAGE_ON_DISK_BITMAP (32 bytes)
	LD	HL,PAGE_ON_DISK_BITMAP
	LD	B,32
IPS_CLEAR_BM:
	LD	(HL),0
	INC	HL
	DJNZ	IPS_CLEAR_BM

	; Initialize BANK_PAGE_TABLE[0..11] = 0..11
	; Initialize BANK_DIRTY_TABLE[0..11] = 0
	LD	B,0			; B = index 0..11
	LD	HL,BANK_PAGE_TABLE
	LD	DE,BANK_DIRTY_TABLE
IPS_INIT_BANKS:
	XOR	A
	LD	(DE),A			; BANK_DIRTY_TABLE[B] = 0
	LD	A,(EXT_BANK_COUNT)
	CP	B
	JR	Z,IPS_BANK_INVALID
	JR	C,IPS_BANK_INVALID
	LD	(HL),B			; BANK_PAGE_TABLE[B] = B
	JR	IPS_NEXT_BANK
IPS_BANK_INVALID:
	LD	A,0FFH
	LD	(HL),A			; BANK_PAGE_TABLE[B] = 0xFF (unmapped)
IPS_NEXT_BANK:
	INC	HL
	INC	DE
	INC	B
	LD	A,B
	CP	MAX_FAR_BANKS
	JR	C,IPS_INIT_BANKS

	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

;------------------------------------------------------------------------------
; WRITE_FAR_SLOT: Write 128-byte line from local memory to physical Far RAM slot
; Inputs: HL = Local Source Address (in CPM_USER_BANK)
;         BC = 16-bit Virtual Slot ID (0..65534)
; Preserves: All registers except AF
;------------------------------------------------------------------------------
WRITE_FAR_SLOT:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	LD	(FAR_LOCAL_ADDR),HL

	; Ensure Page B is resident in Far RAM and marked dirty
	LD	A,B
	CALL	ENSURE_PAGE_RESIDENT_DIRTY
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
	LD	HL,FAR_SLOT_SIZE	; 128 bytes
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
;         BC = 16-bit Virtual Slot ID (0..65534)
; Preserves: All registers except AF
;------------------------------------------------------------------------------
READ_FAR_SLOT:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	LD	(FAR_LOCAL_ADDR),DE

	; Ensure Page B is resident in Far RAM
	LD	A,B
	CALL	ENSURE_PAGE_RESIDENT
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
	LD	HL,FAR_SLOT_SIZE	; 128 bytes
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
; WRITE_FAR_SLOT_LINE: Write single-stride null-terminated line to physical slot BC
; Inputs: HL = Local Source Address (in CPM_USER_BANK)
;         BC = 16-bit Physical Slot ID (0..3583)
; Preserves: IX, BC, DE
;------------------------------------------------------------------------------
WRITE_FAR_SLOT_LINE:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	; Set NEXT_SLOT_ID = 0xFFFF
	LD	DE,0FFFFH
	LD	(FAR_IO_BUF),DE

	; Copy characters from HL to FAR_IO_BUF+2
	LD	DE,FAR_IO_BUF+2
	LD	B,FAR_SLOT_PAYLOAD	; 126
WFSL_COPY:
	LD	A,(HL)
	OR	A
	JR	Z,WFSL_ZERO
	LD	(DE),A
	INC	HL
	INC	DE
	DJNZ	WFSL_COPY
	JR	WFSL_WRITE

WFSL_ZERO:
	XOR	A
	LD	(DE),A

WFSL_WRITE:
	POP	HL
	POP	DE
	POP	BC
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	HL,FAR_IO_BUF
	CALL	WRITE_FAR_SLOT
	POP	HL
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
;------------------------------------------------------------------------------
; WRITE_FAR_LINE: Write null-terminated line from local memory to document line BC
; Inputs: HL = Local Source Address (in CPM_USER_BANK)
;         BC = 16-bit Document Line Index (0..3583)
; Preserves: All registers except AF
;------------------------------------------------------------------------------
WRITE_FAR_LINE:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	LD	(FAR_SRC_LINE_PTR),HL	; Save local source address

	; Lookup head slot ID for line BC
	CALL	GET_LINE_SLOT		; HL = head physical slot ID
	LD	(FAR_CUR_SLOT),HL
	LD	B,H
	LD	C,L			; BC = head physical slot ID

	; Read existing head slot into FAR_IO_BUF to check for existing NEXT_SLOT_ID
	LD	DE,FAR_IO_BUF
	CALL	READ_FAR_SLOT
	LD	HL,(FAR_IO_BUF)
	LD	(FAR_OLD_NEXT_SLOT),HL	; Save previous extension slot ID (or 0xFFFF)

WFL_STRIDE_LOOP:
	; Prepare current stride payload in FAR_IO_BUF+2
	LD	HL,(FAR_SRC_LINE_PTR)
	LD	DE,FAR_IO_BUF+2
	LD	B,FAR_SLOT_PAYLOAD	; 126
WFL_COPY_PAYLOAD:
	LD	A,(HL)
	OR	A
	JR	Z,WFL_STRIDE_EOL
	LD	(DE),A
	INC	HL
	INC	DE
	DJNZ	WFL_COPY_PAYLOAD

	; 126 chars copied! Check if next char in HL is null
	LD	A,(HL)
	OR	A
	JR	Z,WFL_STRIDE_EOL

	; Line continues into next stride!
	LD	(FAR_SRC_LINE_PTR),HL	; Update source line pointer

	; Check if we can reuse FAR_OLD_NEXT_SLOT
	LD	DE,(FAR_OLD_NEXT_SLOT)
	LD	A,D
	AND	E
	INC	A
	JR	NZ,WFL_REUSE_SLOT	; If DE != 0xFFFF, reuse it!

	; Need fresh slot
	PUSH	HL
	CALL	ALLOC_SLOT		; HL = new slot ID, Carry on error
	EX	DE,HL			; DE = new slot ID
	POP	HL
	JR	C,WFL_OOM_TRUNCATE

	; Link and write current stride
	LD	(FAR_IO_BUF),DE		; NEXT_SLOT_ID = new slot ID
	PUSH	DE			; Save new slot ID
	LD	BC,(FAR_CUR_SLOT)
	LD	HL,FAR_IO_BUF
	CALL	WRITE_FAR_SLOT
	POP	DE			; DE = new slot ID

	LD	(FAR_CUR_SLOT),DE	; Advance to new slot
	LD	HL,0FFFFH
	LD	(FAR_OLD_NEXT_SLOT),HL	; Fresh slot has no old next slot
	JR	WFL_STRIDE_LOOP

WFL_OOM_TRUNCATE:
	LD	DE,0FFFFH
	CALL	SET_OOM_STATUS
	JR	WFL_STRIDE_EOL

WFL_REUSE_SLOT:
	; DE is slot ID to reuse.
	; Link and write current stride:
	LD	(FAR_IO_BUF),DE		; NEXT_SLOT_ID = reused slot ID
	PUSH	DE			; Save reused slot ID
	LD	BC,(FAR_CUR_SLOT)
	LD	HL,FAR_IO_BUF
	CALL	WRITE_FAR_SLOT
	POP	BC			; BC = reused slot ID
	LD	(FAR_CUR_SLOT),BC

	; Read this reused slot into FAR_IO_BUF to fetch ITS old next slot!
	LD	DE,FAR_IO_BUF
	CALL	READ_FAR_SLOT
	LD	HL,(FAR_IO_BUF)
	LD	(FAR_OLD_NEXT_SLOT),HL	; Save next extension slot ID
	JR	WFL_STRIDE_LOOP

WFL_STRIDE_EOL:
	XOR	A
	LD	(DE),A			; Null terminate payload in FAR_IO_BUF
	LD	DE,0FFFFH
	LD	(FAR_IO_BUF),DE		; NEXT_SLOT_ID = 0xFFFF

	; Write final stride to Far RAM
	LD	BC,(FAR_CUR_SLOT)
	LD	HL,FAR_IO_BUF
	CALL	WRITE_FAR_SLOT

	; If line previously had further extension slots, free them now!
	LD	HL,(FAR_OLD_NEXT_SLOT)
	LD	A,H
	AND	L
	INC	A
	JR	Z,WFL_ALL_DONE
	CALL	FREE_LINE_CHAIN

WFL_ALL_DONE:
	POP	HL
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; READ_FAR_LINE_MAX: Read line from document line BC into local memory DE
; Inputs: DE = Local Destination Address
;         BC = 16-bit Document Line Index
;         HL = Maximum payload bytes to read (null terminator excluded)
; Preserves: BC, DE
;------------------------------------------------------------------------------
READ_FAR_LINE_MAX:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	LD	(FAR_DEST_LINE_PTR),DE
	LD	(FAR_READ_MAX_BYTES),HL

	; Lookup head slot ID for line BC
	CALL	GET_LINE_SLOT		; HL = head physical slot ID
	LD	(FAR_CUR_SLOT),HL
	LD	B,H
	LD	C,L			; BC = head physical slot ID

RFLM_STRIDE_LOOP:
	; Check if slot ID is 0xFFFF
	LD	A,B
	AND	C
	INC	A
	JR	Z,RFLM_DONE

	; Read slot BC into FAR_IO_BUF
	LD	DE,FAR_IO_BUF
	CALL	READ_FAR_SLOT

	; Next slot ID is in FAR_IO_BUF[0..1]
	LD	HL,(FAR_IO_BUF)
	LD	(FAR_NEW_NEXT_SLOT),HL

	; Copy characters from FAR_IO_BUF+2 to destination
	LD	HL,FAR_IO_BUF+2
	LD	DE,(FAR_DEST_LINE_PTR)
	LD	B,FAR_SLOT_PAYLOAD	; 126
RFLM_COPY_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,RFLM_DONE_EARLY	; Null terminator encountered!
	LD	(DE),A
	INC	HL
	INC	DE
	LD	(FAR_DEST_LINE_PTR),DE

	; Decrement remaining max bytes
	PUSH	HL
	LD	HL,(FAR_READ_MAX_BYTES)
	DEC	HL
	LD	(FAR_READ_MAX_BYTES),HL
	LD	A,H
	OR	L
	POP	HL
	JR	Z,RFLM_DONE_EARLY	; Reached max capacity!
	DJNZ	RFLM_COPY_LOOP

	; Stride exhausted (all 126 bytes copied), advance to next slot
	LD	BC,(FAR_NEW_NEXT_SLOT)
	LD	(FAR_CUR_SLOT),BC
	JR	RFLM_STRIDE_LOOP

RFLM_DONE_EARLY:
RFLM_DONE:
	LD	DE,(FAR_DEST_LINE_PTR)
	XOR	A
	LD	(DE),A			; Guarantee null terminator
	POP	HL
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; READ_FAR_LINE: Read line for local LINE_STORAGE cache slot
; Inputs: DE = Local Destination Address
;         BC = 16-bit Document Line Index
; Preserves: All registers except AF
;------------------------------------------------------------------------------
READ_FAR_LINE:
	PUSH	HL
	LD	HL,MAX_LINE_STRIDE-2	; 254 bytes
	CALL	READ_FAR_LINE_MAX
	POP	HL
	RET

;------------------------------------------------------------------------------
; CHECKOUT_ACTIVE_LINE: Ensure CUR_DOC_ROW is checked out in ACTIVE_LINE_BUF
; Preserves: All registers except AF
; Returns: HL = ACTIVE_LINE_BUF
;------------------------------------------------------------------------------
CHECKOUT_ACTIVE_LINE:
	PUSH	BC
	PUSH	DE

	; Check if CUR_DOC_ROW == ACTIVE_LINE_ROW
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(ACTIVE_LINE_ROW)
	LD	A,H
	CP	D
	JR	NZ,DO_CHECKOUT
	LD	A,L
	CP	E
	JR	Z,CHECKOUT_ALREADY_DONE

DO_CHECKOUT:
	; Row changed! If previous line dirty, commit it first
	CALL	COMMIT_ACTIVE_LINE

	; Set ACTIVE_LINE_ROW = CUR_DOC_ROW
	LD	HL,(CUR_DOC_ROW)
	LD	(ACTIVE_LINE_ROW),HL
	XOR	A
	LD	(ACTIVE_LINE_DIRTY),A

	; Read CUR_DOC_ROW into ACTIVE_LINE_BUF up to 1022 bytes
	LD	BC,(CUR_DOC_ROW)
	LD	DE,ACTIVE_LINE_BUF
	LD	HL,MAX_ACTIVE_LINE_STRIDE-2
	CALL	READ_FAR_LINE_MAX

CHECKOUT_ALREADY_DONE:
	LD	HL,ACTIVE_LINE_BUF
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; COMMIT_ACTIVE_LINE: Write ACTIVE_LINE_BUF to Far RAM if dirty
; Preserves: All registers except AF
;------------------------------------------------------------------------------
COMMIT_ACTIVE_LINE:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	; Check if active line is valid
	LD	HL,(ACTIVE_LINE_ROW)
	LD	A,H
	AND	L
	INC	A
	JR	Z,COMMIT_DONE		; 0xFFFF -> no line checked out

	; Check if active line is dirty
	LD	A,(ACTIVE_LINE_DIRTY)
	OR	A
	JR	Z,COMMIT_DONE		; Not dirty -> nothing to write

	; Clear dirty flag
	XOR	A
	LD	(ACTIVE_LINE_DIRTY),A

	; Write ACTIVE_LINE_BUF to Far RAM for ACTIVE_LINE_ROW
	LD	BC,(ACTIVE_LINE_ROW)
	LD	HL,ACTIVE_LINE_BUF
	CALL	WRITE_FAR_LINE

	; Synchronize first 254 chars to LINE_STORAGE if row is in cache window
	LD	BC,(ACTIVE_LINE_ROW)
	LD	HL,(CACHE_START_ROW)
	; Check BC >= CACHE_START_ROW
	LD	A,B
	CP	H
	JR	C,COMMIT_DONE
	JR	NZ,COMMIT_CHECK_UPPER
	LD	A,C
	CP	L
	JR	C,COMMIT_DONE

COMMIT_CHECK_UPPER:
	LD	A,C
	SUB	L
	LD	E,A
	LD	A,B
	SBC	A,H
	JR	NZ,COMMIT_DONE		; High byte non-zero -> outside cache
	LD	A,E
	CP	CACHE_SIZE_LINES
	JR	NC,COMMIT_DONE		; Index >= 48 -> outside cache

	; Row is in cache! Calculate destination pointer: LINE_STORAGE + (E * 128)
	PUSH	DE
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
	ADD	HL,DE			; HL = target slot in LINE_STORAGE
	EX	DE,HL			; DE = destination in LINE_STORAGE
	LD	HL,ACTIVE_LINE_BUF	; HL = source
	LD	B,MAX_LINE_STRIDE-2	; up to 126 bytes
COMMIT_SYNC_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,COMMIT_SYNC_ZERO
	LD	(DE),A
	INC	HL
	INC	DE
	DJNZ	COMMIT_SYNC_LOOP
COMMIT_SYNC_ZERO:
	XOR	A
	LD	(DE),A			; Null terminate in cache
	POP	DE			; E = local line index (0..47)

	; Mark this cache line clean (since already written to Far RAM)
	LD	HL,CACHE_LINE_DIRTY
	LD	D,0
	ADD	HL,DE
	LD	(HL),0

COMMIT_DONE:
	POP	HL
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; INVALIDATE_ACTIVE_LINE: Commit if dirty, then reset ACTIVE_LINE_ROW to 0xFFFF
; Preserves: All registers except AF
;------------------------------------------------------------------------------
INVALIDATE_ACTIVE_LINE:
	CALL	COMMIT_ACTIVE_LINE
	PUSH	HL
	LD	HL,0FFFFH
	LD	(ACTIVE_LINE_ROW),HL
	XOR	A
	LD	(ACTIVE_LINE_DIRTY),A
	POP	HL
	RET

;------------------------------------------------------------------------------
; INIT_SLOT_SYSTEM: Reset slot allocator and free list
;------------------------------------------------------------------------------
INIT_SLOT_SYSTEM:
	LD	HL,0
	LD	(NEXT_FRESH_SLOT),HL
	LD	HL,0FFFFH
	LD	(FIRST_FREE_SLOT),HL
	CALL	INIT_PAGING_SYSTEM
	RET

;------------------------------------------------------------------------------
; WRITE_SLOT_NEXT_TERM: Write 0xFFFF to first 2 bytes of Far RAM slot BC
; Inputs: BC = 16-bit Virtual Slot ID (0..65534)
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
WRITE_SLOT_NEXT_TERM:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL

	LD	HL,0FFFFH
	LD	(LINE_SLOT_TEMP),HL

	; Ensure Page B is resident and marked dirty
	LD	A,B
	CALL	ENSURE_PAGE_RESIDENT_DIRTY
	LD	D,A			; D = Far RAM Bank ID
	LD	A,(CPM_USER_BANK)
	LD	E,A			; Src Bank = CPM_USER_BANK

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
	EX	DE,HL			; DE = far_offset, H = Dest Bank, L = Src Bank

	; SYSSETCPY: D = Dest Bank, E = Src Bank, HL = 2 bytes
	PUSH	DE
	PUSH	IX
	LD	B,0F4H			; SYSSETCPY
	LD	D,H
	LD	E,L
	LD	HL,2
	RST	08H
	POP	IX

	; SYSBNKCPY: HL = Local Src (LINE_SLOT_TEMP), DE = Far Dest
	POP	DE
	LD	HL,LINE_SLOT_TEMP
	PUSH	IX
	LD	B,0F5H			; SYSBNKCPY
	RST	08H
	POP	IX

	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

;------------------------------------------------------------------------------
; ALLOC_SLOT: Allocate a Virtual Slot ID (0..65534)
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
	LD	DE,FAR_IO_BUF
	CALL	READ_FAR_SLOT		; Read first 128 bytes of slot (contains next ptr)
	LD	HL,(FAR_IO_BUF)		; HL = next free slot ID
	LD	(FIRST_FREE_SLOT),HL
	POP	HL			; Restore allocated slot ID
	LD	B,H
	LD	C,L
	CALL	WRITE_SLOT_NEXT_TERM	; Ensure allocated slot has 0xFFFF next ptr
	POP	BC
	POP	DE
	OR	A			; Carry = 0 (success)
	RET

ALLOC_FRESH_SLOT:
	LD	HL,(NEXT_FRESH_SLOT)
	LD	DE,MAX_VIRTUAL_SLOTS
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
	LD	B,H
	LD	C,L
	CALL	WRITE_SLOT_NEXT_TERM	; Ensure fresh slot has 0xFFFF next ptr
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

	LD	DE,(FIRST_FREE_SLOT)
	; Check if slot is already at top of free list (prevent self-loop)
	LD	A,D
	CP	H
	JR	NZ,FS_PROCEED
	LD	A,E
	CP	L
	JR	Z,FS_DONE

FS_PROCEED:
	LD	(FAR_IO_BUF),DE

	; Write to Far RAM slot HL
	LD	B,H
	LD	C,L			; BC = slot ID
	LD	HL,FAR_IO_BUF
	CALL	WRITE_FAR_SLOT

	; Update FIRST_FREE_SLOT to the newly freed slot ID
	POP	HL
	PUSH	HL
	LD	(FIRST_FREE_SLOT),HL

FS_DONE:
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

;------------------------------------------------------------------------------
; FREE_LINE_CHAIN: Return a Far RAM slot chain to the Extended RAM free list
; Input: HL = 16-bit Head Slot ID (0..3583)
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
FREE_LINE_CHAIN:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	A,16
	LD	(FLC_COUNT),A

FLC_LOOP:
	; Check if HL == 0xFFFF (SLOT_TERM)
	LD	A,H
	AND	L
	INC	A
	JR	Z,FLC_DONE

	; Check if HL is within bounds
	LD	DE,MAX_VIRTUAL_SLOTS
	LD	A,H
	CP	D
	JR	C,FLC_BOUNDS_OK
	JR	NZ,FLC_DONE
	LD	A,L
	CP	E
	JR	NC,FLC_DONE
FLC_BOUNDS_OK:

	; Check iteration count
	LD	A,(FLC_COUNT)
	DEC	A
	LD	(FLC_COUNT),A
	JR	Z,FLC_DONE

	; Read slot into FAR_IO_BUF to get NEXT_SLOT_ID
	PUSH	HL			; Save slot ID being freed
	LD	B,H
	LD	C,L
	LD	DE,FAR_IO_BUF
	CALL	READ_FAR_SLOT
	LD	DE,(FAR_IO_BUF)		; DE = NEXT_SLOT_ID
	POP	HL			; Restore slot ID being freed

	; Check for self-loop (DE == HL)
	LD	A,D
	CP	H
	JR	NZ,FLC_NOT_SELF
	LD	A,E
	CP	L
	JR	Z,FLC_DONE
FLC_NOT_SELF:

	; Free slot HL
	CALL	FREE_SLOT

	; Advance to NEXT_SLOT_ID
	EX	DE,HL			; HL = NEXT_SLOT_ID
	JR	FLC_LOOP

FLC_DONE:
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

;------------------------------------------------------------------------------
; APPEND_LINE_SLOT: Allocate slot and assign to line table in Far RAM
; Returns: Carry=0, BC = allocated slot ID; Carry=1 on out-of-memory
; Preserves: DE
;------------------------------------------------------------------------------
APPEND_LINE_SLOT:
	PUSH	DE
	LD	HL,(DOC_TOTAL_LINES)
	LD	DE,(MAX_DOC_LINES_LIMIT)
	OR	A
	SBC	HL,DE
	POP	DE
	JR	NC,ALS_OOM
	CALL	ALLOC_SLOT		; HL = slot ID
	RET	C
	PUSH	HL			; Save slot ID
	LD	BC,(DOC_TOTAL_LINES)
	CALL	SET_LINE_SLOT		; Store slot ID HL at line BC in Far RAM
	POP	BC			; BC = allocated slot ID
	OR	A			; Carry = 0
	RET
ALS_OOM:
	SCF
	RET

;------------------------------------------------------------------------------
; CLEAR_CACHE_DIRTY_FLAGS: Clear all per-line dirty flags and CACHE_DIRTY
; Preserves: All registers
;------------------------------------------------------------------------------
CLEAR_CACHE_DIRTY_FLAGS:
	PUSH	AF
	PUSH	BC
	PUSH	HL
	XOR	A
	LD	(CACHE_DIRTY),A
	LD	HL,CACHE_LINE_DIRTY
	LD	B,CACHE_SIZE_LINES
CCDF_LOOP:
	LD	(HL),0
	INC	HL
	DJNZ	CCDF_LOOP
	POP	HL
	POP	BC
	POP	AF
	RET

;------------------------------------------------------------------------------
; MARK_LINE_BC_DIRTY: Mark document line BC dirty in local cache
; Preserves: All registers
;------------------------------------------------------------------------------
MARK_LINE_BC_DIRTY:
	PUSH	AF
	PUSH	DE
	PUSH	HL
	LD	A,1
	LD	(CACHE_DIRTY),A
	LD	(DOC_MODIFIED),A
	; Calculate local index = BC - CACHE_START_ROW
	LD	L,C
	LD	H,B
	LD	DE,(CACHE_START_ROW)
	AND	A
	SBC	HL,DE
	LD	A,H
	OR	A
	JR	NZ,MLBD_DONE		; If high byte != 0, outside cache window
	LD	A,L
	CP	CACHE_SIZE_LINES
	JR	NC,MLBD_DONE		; If index >= CACHE_SIZE_LINES, outside cache
	LD	DE,CACHE_LINE_DIRTY
	ADD	HL,DE
	LD	(HL),1
MLBD_DONE:
	POP	HL
	POP	DE
	POP	AF
	RET

;------------------------------------------------------------------------------
; MARK_CURRENT_LINE_DIRTY: Mark line at CUR_DOC_ROW dirty in local cache
; Preserves: All registers
;------------------------------------------------------------------------------
MARK_CURRENT_LINE_DIRTY:
	PUSH	BC
	LD	BC,(CUR_DOC_ROW)
	CALL	MARK_LINE_BC_DIRTY
	POP	BC
	RET

;------------------------------------------------------------------------------
; FLUSH_DIRTY_CACHE: Write modified lines in local cache back to Far RAM banks
;------------------------------------------------------------------------------
FLUSH_DIRTY_CACHE:
	CALL	COMMIT_ACTIVE_LINE
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

	; Check if this local line is dirty
	LD	HL,CACHE_LINE_DIRTY
	LD	E,C
	LD	D,0
	ADD	HL,DE
	LD	A,(HL)
	OR	A
	JR	Z,FLUSH_SKIP_LINE

	; Clear dirty flag for this line
	LD	(HL),0

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

FLUSH_SKIP_LINE:
	INC	C
	JR	FLUSH_CACHE_LOOP

FLUSH_CACHE_DONE:
	CALL	CLEAR_CACHE_DIRTY_FLAGS

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
	CALL	CLEAR_CACHE_DIRTY_FLAGS

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

;------------------------------------------------------------------------------
; Drain Escape Sequence: if characters follow ESC within timeout, drain them
;------------------------------------------------------------------------------
DRAIN_ESC_SEQUENCE:
	LD	BC,ESC_TIMEOUT_LOOPS
DES_WAIT:
	CALL	CHECK_KEY_READY
	JR	NZ,DES_DRAIN_FIRST
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,DES_WAIT
	RET				; Standalone ESC, nothing to drain

DES_DRAIN_FIRST:
	CALL	GET_KEY			; Consume byte following ESC ('[' or 'O' etc.)
DES_DRAIN_MORE:
	LD	BC,500
DES_DRAIN_WAIT:
	CALL	CHECK_KEY_READY
	JR	NZ,DES_DRAIN_BYTE
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,DES_DRAIN_WAIT
	RET				; Sequence drained

DES_DRAIN_BYTE:
	CALL	GET_KEY
	JR	DES_DRAIN_MORE

HANDLE_VT100_ESC:
	; Check if a character follows ESC within a short timeout
	LD	BC,ESC_TIMEOUT_LOOPS	; Timeout loop count
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
	JP	SHOW_SPLASH_SCREEN

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
	LD	(CSI_MODIFIER),A
	CALL	GET_KEY
	CP	'A'			; Up Arrow
	JP	Z,CURSOR_UP
	CP	'B'			; Down Arrow
	JP	Z,CURSOR_DOWN
	CP	'C'			; Right Arrow
	JP	Z,CURSOR_RIGHT
	CP	'D'			; Left Arrow
	JP	Z,CURSOR_LEFT
	CP	'a'			; rxvt Shift+Up
	JP	Z,SHIFT_CURSOR_UP
	CP	'b'			; rxvt Shift+Down
	JP	Z,SHIFT_CURSOR_DOWN
	CP	'c'			; rxvt Shift+Right
	JP	Z,SHIFT_CURSOR_RIGHT
	CP	'd'			; rxvt Shift+Left
	JP	Z,SHIFT_CURSOR_LEFT
	CP	'H'			; Home (ESC [ H)
	JP	Z,CURSOR_HOME
	CP	'F'			; End (ESC [ F)
	JP	Z,CURSOR_END
	CP	'1'			; Home (ESC [ 1 ~) or modifier prefix (ESC [ 1 ; ...)
	JP	Z,HANDLE_CSI_1
	CP	'2'			; Shift+Arrow prefix (ESC [ 2 A..D) or Insert
	JP	Z,HANDLE_CSI_2
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
	CP	'L'			; VT102 Insert key (ESC [ L)
	JP	Z,TOGGLE_INSERT_MODE
	CP	'@'			; ICH Insert character (ESC [ @)
	JP	Z,TOGGLE_INSERT_MODE

	; Check if parameter/modifier digits present (e.g. 1;2A, 1~, 4~)
	CP	'0'
	JP	C,CSI_DONE
	CP	'9'+1
	JP	C,HANDLE_CSI_LOOP_DIGIT
	RET

HANDLE_CSI_1:
	LD	A,'1'
	LD	(CSI_DIGIT_PREFIX),A
	CALL	GET_KEY
	CP	'~'
	JP	Z,CURSOR_HOME
	CP	';'
	JP	Z,HANDLE_CSI_LOOP
	RET

HANDLE_CSI_2:
	LD	A,'2'
	LD	(CSI_MODIFIER),A
	LD	(CSI_DIGIT_PREFIX),A
	CALL	GET_KEY
	CP	'~'			; Insert key (ESC [ 2 ~)
	JP	Z,TOGGLE_INSERT_MODE
	CP	'A'
	JP	Z,SHIFT_CURSOR_UP
	CP	'B'
	JP	Z,SHIFT_CURSOR_DOWN
	CP	'C'
	JP	Z,SHIFT_CURSOR_RIGHT
	CP	'D'
	JP	Z,SHIFT_CURSOR_LEFT
	CP	';'
	JP	Z,HANDLE_CSI_LOOP
	RET

HANDLE_CSI_4:
	LD	A,'4'
	LD	(CSI_DIGIT_PREFIX),A
	CALL	GET_KEY
	CP	'~'
	JP	Z,CURSOR_END
	CP	';'
	JP	Z,HANDLE_CSI_LOOP
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
	JR	Z,DO_CSI_DEL_IMPLIED_K_DELETE
	CALL	DO_DELETE_FORWARD
	RET

DO_CSI_DEL_IMPLIED_K_DELETE:
	CALL	SOLIDIFY_BLOCK
DO_CSI_DEL_BLOCK:
	CALL	DO_DELETE_BLOCK
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

HANDLE_CSI_LOOP_DIGIT:
	LD	(CSI_MODIFIER),A
HANDLE_CSI_LOOP:
	CALL	GET_KEY
	CP	'~'
	JR	Z,HANDLE_CSI_TILDE
	CP	'A'
	JP	Z,HANDLE_CSI_A
	CP	'B'
	JP	Z,HANDLE_CSI_B
	CP	'C'
	JP	Z,HANDLE_CSI_C
	CP	'D'
	JP	Z,HANDLE_CSI_D
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
	JR	C,HANDLE_CSI_LOOP_DIGIT
CSI_DONE:
	RET

CHECK_CSI_SHIFT:
	LD	A,(CSI_MODIFIER)
	CP	'2'
	RET	Z
	CP	'6'
	RET

HANDLE_CSI_A:
	CALL	CHECK_CSI_SHIFT
	JP	Z,SHIFT_CURSOR_UP
	JP	CURSOR_UP

HANDLE_CSI_B:
	CALL	CHECK_CSI_SHIFT
	JP	Z,SHIFT_CURSOR_DOWN
	JP	CURSOR_DOWN

HANDLE_CSI_C:
	CALL	CHECK_CSI_SHIFT
	JP	Z,SHIFT_CURSOR_RIGHT
	JP	CURSOR_RIGHT

HANDLE_CSI_D:
	CALL	CHECK_CSI_SHIFT
	JP	Z,SHIFT_CURSOR_LEFT
	JP	CURSOR_LEFT

SHIFT_CURSOR_UP:
	CALL	START_NEW_BLOCK_AT_CURSOR
	JP	CURSOR_UP

SHIFT_CURSOR_DOWN:
	CALL	START_NEW_BLOCK_AT_CURSOR
	JP	CURSOR_DOWN

SHIFT_CURSOR_RIGHT:
	CALL	START_NEW_BLOCK_AT_CURSOR
	JP	CURSOR_RIGHT

SHIFT_CURSOR_LEFT:
	CALL	START_NEW_BLOCK_AT_CURSOR
	JP	CURSOR_LEFT

HANDLE_CSI_TILDE:
	LD	A,(CSI_DIGIT_PREFIX)
	CP	'1'
	JP	Z,JUMP_FILE_TOP		; ESC [ 1 ; 5 ~ -> Ctrl+Home!
	CP	'4'
	JP	Z,JUMP_FILE_BOTTOM	; ESC [ 4 ; 5 ~ -> Ctrl+End!
	CP	'2'
	JP	Z,TOGGLE_INSERT_MODE	; ESC [ 2 ; <n> ~ -> Insert!
	LD	A,(CSI_MODIFIER)
	CP	'2'
	JP	Z,TOGGLE_INSERT_MODE
	RET

TOGGLE_INSERT_MODE:
	LD	A,(INSERT_MODE)
	XOR	1
	LD	(INSERT_MODE),A
	LD	A,1
	LD	(NEED_STATUS_RENDER),A
	RET

CURSOR_HOME:
	LD	HL,0
	LD	(CUR_COL),HL
	LD	(TARGET_COL),HL
	LD	A,(BLOCK_ACTIVE)
	CP	1
	RET	NZ
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

CURSOR_END:
	CALL	GET_CUR_ROW_LEN		; HL = line start, DE = byte length, BC = visual length
	LD	HL,MAX_INPUT_LINE_CHARS-1 ; 999
	LD	A,E
	SUB	L
	LD	A,D
	SBC	A,H
	JR	C,CE_NOT_FULL
	EX	DE,HL			; Clamp to 999
CE_NOT_FULL:
	LD	(CUR_COL),DE
	CALL	CALC_VISUAL_COL
	LD	(TARGET_COL),HL
	LD	A,(BLOCK_ACTIVE)
	CP	1
	RET	NZ
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

;------------------------------------------------------------------------------
; Get Length of Current Line at CUR_DOC_ROW
; Returns: DE = Byte length (0..1000), BC = Visual length (0..1000), HL = line start
; Preserves: None
;------------------------------------------------------------------------------
GET_CUR_ROW_LEN:
	CALL	CHECKOUT_ACTIVE_LINE	; HL = ACTIVE_LINE_BUF
	PUSH	HL			; Save line start

	LD	DE,0			; DE = byte count
	LD	BC,0			; BC = visual column accumulator
GET_ROW_LEN_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,GET_ROW_LEN_DONE
	CP	KEY_TAB
	JR	Z,GET_ROW_TAB
	INC	DE
	INC	BC
	JR	GET_ROW_NEXT

GET_ROW_TAB:
	INC	DE
	LD	A,C
	CALL	GET_TAB_SPACES		; spaces to add (1..CFG_TAB_WIDTH)
	ADD	A,C
	LD	C,A
	JR	NC,GET_ROW_NEXT
	INC	B

GET_ROW_NEXT:
	INC	HL
	LD	A,E
	CP	MAX_ACTIVE_PAYLOAD_LO
	JR	NZ,GET_ROW_LEN_LOOP
	LD	A,D
	CP	MAX_ACTIVE_PAYLOAD_HI
	JR	NZ,GET_ROW_LEN_LOOP

GET_ROW_LEN_DONE:
	POP	HL			; HL = line start (ACTIVE_LINE_BUF)
	RET

;------------------------------------------------------------------------------
; Adjust CUR_COL to Match Sticky TARGET_COL (Visual Column) on Current Line
; Preserves: TARGET_COL
;------------------------------------------------------------------------------
ADJUST_COL_TO_TARGET:
	CALL	GET_CUR_ROW_LEN		; HL = line start, DE = byte length
	LD	BC,0			; BC = character index (0..DE)
	LD	HL,0
	LD	(ACT_VIS_ACC),HL	; 16-bit visual accumulator = 0

MAP_TARGET_LOOP:
	; Compare BC with DE (character index >= line byte length?)
	LD	A,C
	CP	E
	JR	NZ,MAP_CHECK_LT
	LD	A,B
	CP	D
	JR	Z,SET_TARGET_CHAR_IDX
MAP_CHECK_LT:
	; Check if visual accumulator >= TARGET_COL
	LD	HL,(TARGET_COL)
	PUSH	DE
	LD	DE,(ACT_VIS_ACC)
	LD	A,E
	SUB	L
	LD	A,D
	SBC	A,H
	POP	DE
	JR	NC,SET_TARGET_CHAR_IDX	; ACT_VIS_ACC >= TARGET_COL

	; Peek character at ACTIVE_LINE_BUF + BC
	PUSH	DE
	LD	HL,ACTIVE_LINE_BUF
	ADD	HL,BC
	LD	A,(HL)
	POP	DE

	CP	KEY_TAB
	JR	Z,MAP_TARGET_TAB

	; Normal character: increment visual accumulator
	PUSH	HL
	LD	HL,(ACT_VIS_ACC)
	INC	HL
	LD	(ACT_VIS_ACC),HL
	POP	HL
	INC	BC
	JR	MAP_TARGET_LOOP

MAP_TARGET_TAB:
	PUSH	HL
	LD	HL,(ACT_VIS_ACC)
	LD	A,L
	CALL	GET_TAB_SPACES
	ADD	A,L
	LD	L,A
	JR	NC,MAP_TAB_NO_CY
	INC	H
MAP_TAB_NO_CY:
	LD	(ACT_VIS_ACC),HL
	POP	HL
	INC	BC
	JR	MAP_TARGET_LOOP

SET_TARGET_CHAR_IDX:
	LD	(CUR_COL),BC
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
	LD	HL,(CUR_COL)
	LD	A,H
	OR	L
	JR	Z,CURSOR_LEFT_PREV_LINE
	DEC	HL
	LD	(CUR_COL),HL
	CALL	CALC_VISUAL_COL
	LD	(TARGET_COL),HL		; Horizontal movement updates sticky target visual column
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
	CALL	CHECKOUT_ACTIVE_LINE

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

CL_NO_SCROLL:
	CALL	GET_CUR_ROW_LEN		; DE = prev line length
	LD	(CUR_COL),DE
	CALL	CALC_VISUAL_COL
	LD	(TARGET_COL),HL
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	RET

CURSOR_RIGHT:
	CALL	GET_CUR_ROW_LEN		; DE = current line byte length, BC = visual length
	LD	HL,(CUR_COL)
	; Check if CUR_COL >= DE (at or past EOL)
	LD	A,L
	SUB	E
	LD	A,H
	SBC	A,D
	JR	NC,CURSOR_RIGHT_NEXT_LINE ; If at or past EOL, wrap to next line!

	; Check if visual cursor is already at MAX_LINE_CHARS - 1
	CALL	CALC_VISUAL_COL		; HL = visual column
	LD	DE,MAX_LINE_CHARS-1
	LD	A,L
	CP	E
	JR	NZ,CR_IN_LINE
	LD	A,H
	CP	D
	JR	Z,CURSOR_RIGHT_NEXT_LINE ; If at column MAX_LINE_CHARS-1, wrap!

CR_IN_LINE:
	LD	HL,(CUR_COL)
	INC	HL
	LD	(CUR_COL),HL
	CALL	CALC_VISUAL_COL
	LD	(TARGET_COL),HL		; Horizontal movement updates sticky target visual column
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
	LD	A,E
	SUB	L
	LD	A,D
	SBC	A,H
	RET	NC			; At end of document, cannot wrap

	LD	(CUR_DOC_ROW),DE
	CALL	CHECKOUT_ACTIVE_LINE
	LD	HL,0
	LD	(CUR_COL),HL
	LD	(TARGET_COL),HL

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
	LD	(CUR_COL),HL
	LD	(TARGET_COL),HL
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
	CALL	GET_CUR_ROW_LEN		; DE = byte length, BC = visual length
	LD	(CUR_COL),DE
	LD	(TARGET_COL),BC

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
; Position Cursor and Center Viewport at 1-indexed Line in HL
; Clamps to [1, DOC_TOTAL_LINES].
;------------------------------------------------------------------------------
GOTO_LINE_HL:
	; Clamp lower bound: if HL == 0, set HL = 1
	LD	A,H
	OR	L
	JR	NZ,GOTO_NOT_ZERO
	LD	HL,1
GOTO_NOT_ZERO:
	LD	DE,(DOC_TOTAL_LINES)
	LD	A,D
	OR	E
	JR	NZ,GOTO_HAS_LINES
	; 0 total lines: clamp to 0
	LD	HL,0
	LD	(CUR_DOC_ROW),HL
	LD	(TOP_DOC_ROW),HL
	JR	GOTO_SET_COLS

GOTO_HAS_LINES:
	; Compare HL with DE: carry set if HL < DE, Z set if HL == DE
	OR	A			; Clear carry
	SBC	HL,DE			; HL - DE
	JR	NC,GOTO_CLAMP_EOF	; If HL >= DE, clamp to DE
	ADD	HL,DE			; HL < DE: restore HL
	JR	GOTO_CALC_ROW

GOTO_CLAMP_EOF:
	EX	DE,HL			; HL = DOC_TOTAL_LINES

GOTO_CALC_ROW:
	DEC	HL			; 0-indexed row = HL - 1
	LD	(CUR_DOC_ROW),HL

GOTO_SET_COLS:
	LD	HL,0
	LD	(CUR_COL),HL
	LD	(TARGET_COL),HL

	; Calculate TOP_DOC_ROW for centering:
	; Viewport lines: V = ACTIVE_ROWS - 1
	; Half-height: H = V / 2
	LD	HL,(CUR_DOC_ROW)
	LD	A,(ACTIVE_ROWS)
	DEC	A			; V
	SRL	A			; H = V / 2
	LD	E,A
	LD	D,0			; DE = H

	OR	A
	SBC	HL,DE			; HL = CUR_DOC_ROW - H
	JR	C,GOTO_SET_TOP_ZERO	; If CUR_DOC_ROW < H, TOP = 0
	JR	Z,GOTO_SET_TOP_ZERO	; If CUR_DOC_ROW == H, TOP = 0

	; Proposed TOP is in HL (CUR_DOC_ROW - H)
	; Calculate MAX_TOP = DOC_TOTAL_LINES - V
	PUSH	HL			; Save proposed TOP
	LD	HL,(DOC_TOTAL_LINES)
	LD	A,(ACTIVE_ROWS)
	DEC	A			; V
	LD	E,A
	LD	D,0			; DE = V
	OR	A
	SBC	HL,DE			; HL = DOC_TOTAL_LINES - V
	JR	C,GOTO_POP_TOP_ZERO	; If DOC_TOTAL_LINES < V -> TOP = 0
	JR	Z,GOTO_POP_TOP_ZERO	; If DOC_TOTAL_LINES == V -> TOP = 0

	; HL is MAX_TOP, proposed TOP is on stack
	EX	DE,HL			; DE = MAX_TOP
	POP	HL			; HL = proposed TOP
	OR	A
	SBC	HL,DE			; proposed - MAX_TOP
	JR	NC,GOTO_SET_MAX_TOP	; If proposed >= MAX_TOP, use MAX_TOP
	ADD	HL,DE			; Restore proposed TOP
	LD	(TOP_DOC_ROW),HL
	JR	GOTO_FINISH

GOTO_POP_TOP_ZERO:
	POP	HL			; Discard proposed TOP
GOTO_SET_TOP_ZERO:
	LD	HL,0
	LD	(TOP_DOC_ROW),HL
	JR	GOTO_FINISH

GOTO_SET_MAX_TOP:
	LD	(TOP_DOC_ROW),DE

GOTO_FINISH:
	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	LD	(NEED_STATUS_RENDER),A
	RET

;------------------------------------------------------------------------------
; Parse ASCII Decimal Word
; Input: HL = pointer to ASCII decimal string
; Output: DE = 16-bit unsigned value, HL = pointer to first non-digit char
;------------------------------------------------------------------------------
PARSE_DEC_WORD:
	LD	DE,0
PARSE_DEC_LOOP:
	LD	A,(HL)
	OR	A
	RET	Z
	CP	'0'
	RET	C
	CP	'9'+1
	RET	NC
	SUB	'0'
	PUSH	HL
	LD	H,D
	LD	L,E
	ADD	HL,HL		; * 2
	ADD	HL,HL		; * 4
	ADD	HL,DE		; * 5
	ADD	HL,HL		; * 10
	LD	E,A
	LD	D,0
	ADD	HL,DE		; * 10 + digit
	EX	DE,HL
	POP	HL
	INC	HL
	JR	PARSE_DEC_LOOP

;------------------------------------------------------------------------------
; Interactive Goto Line UI (Ctrl+L in editor, or 'l'/Ctrl+L from splash)
; Prompts for line number on status row.
; Enter -> jumps to line (centered). ESC -> cancels.
;------------------------------------------------------------------------------
DO_GOTO_LINE_UI:
	CALL	CANCEL_BLOCK
	LD	DE,STR_SHOW_CURSOR
	CALL	PRINT_STR

	; Display Goto line prompt on status bar: highlighted query ending in ':'
	CALL	LOCATE_STATUS_ROW
	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR
	LD	DE,STR_GOTO_LINE_PROMPT	; "Goto line:"
	CALL	PRINT_STR
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR

	; Normal video edit box: " [     ]"
	LD	DE,STR_GOTO_LINE_BOX	; " [     ]"
	CALL	PRINT_STR
	LD	DE,STR_CLEAR_EOL
	CALL	PRINT_STR

	; Position cursor inside box at first space (6 backspaces)
	LD	DE,STR_BS_6
	CALL	PRINT_STR

	; Clear buffer
	LD	HL,GOTO_LINE_BUF
	LD	(HL),0
	LD	B,0			; B = digit count (0..5)

GOTO_UI_LOOP:
	CALL	GET_KEY

	; ESC or escape sequence (e.g. cursor keys, PgUp, PgDn)
	CP	KEY_ESC
	JR	Z,GOTO_UI_CHECK_ESC

	; Ctrl+U -> cancel and Page Up
	CP	KEY_CTRL_U
	JR	Z,GOTO_UI_PGUP

	; Ctrl+V -> cancel and Page Down
	CP	KEY_CTRL_V
	JR	Z,GOTO_UI_PGDN

	; Enter -> confirm goto line
	CP	KEY_ENTER
	JP	Z,GOTO_UI_ENTER

	; Backspace / Delete
	CP	KEY_BACKSPACE
	JR	Z,GOTO_UI_BS
	CP	KEY_DEL
	JR	Z,GOTO_UI_BS

	; Check if digit '0'..'9'
	CP	'0'
	JR	C,GOTO_UI_LOOP
	CP	'9'+1
	JR	NC,GOTO_UI_LOOP

	; Check max digits (up to 5 digits)
	LD	C,A			; Save digit in C
	LD	A,B
	CP	5
	JR	NC,GOTO_UI_LOOP

	; Append digit to buffer
	LD	HL,GOTO_LINE_BUF
	LD	E,B
	LD	D,0
	ADD	HL,DE
	LD	(HL),C
	INC	HL
	LD	(HL),0			; Null-terminate
	INC	B

	; Echo digit on screen
	LD	A,C
	CALL	PUTC
	JR	GOTO_UI_LOOP

GOTO_UI_BS:
	LD	A,B
	OR	A
	JR	Z,GOTO_UI_LOOP		; Nothing to backspace

	DEC	B
	LD	HL,GOTO_LINE_BUF
	LD	E,B
	LD	D,0
	ADD	HL,DE
	LD	(HL),0			; Null-terminate at new length

	; Visual backspace: \x08 \x20 \x08
	LD	A,008H
	CALL	PUTC
	LD	A,' '
	CALL	PUTC
	LD	A,008H
	CALL	PUTC
	JR	GOTO_UI_LOOP

GOTO_UI_PGUP:
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	CALL	PAGE_UP
	CALL	FLUSH_DEFERRED_RENDER
	CALL	RENDER_STATUS_BAR
	RET

GOTO_UI_PGDN:
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	CALL	PAGE_DOWN
	CALL	FLUSH_DEFERRED_RENDER
	CALL	RENDER_STATUS_BAR
	RET

GOTO_UI_CHECK_ESC:
	; Check if a character follows ESC within a short timeout
	LD	BC,ESC_TIMEOUT_LOOPS
GOTO_WAIT_ESC:
	CALL	CHECK_KEY_READY
	JR	NZ,GOTO_GOT_ESC_SEQ
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,GOTO_WAIT_ESC

	; Standalone ESC key: cancel prompt without moving cursor
	JR	GOTO_UI_CANCEL

GOTO_GOT_ESC_SEQ:
	; User pressed an escape sequence (e.g. cursor arrow keys, PgUp, PgDn)
	; 1. Cancel inverse video before executing navigation and rendering
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	; 2. Consume escape sequence and execute cursor navigation
	CALL	GOT_ESC_BYTE
	; 3. Refresh screen if scrolled, or redraw status bar and locate cursor
	CALL	FLUSH_DEFERRED_RENDER
	CALL	RENDER_STATUS_BAR
	RET

GOTO_UI_ENTER:
	; If empty (user just pressed enter with no digits), treat as cancel
	LD	A,B
	OR	A
	JR	Z,GOTO_UI_CANCEL

	; Cancel inverse video before parsing and redrawing
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR

	; Parse decimal number from GOTO_LINE_BUF into DE
	LD	HL,GOTO_LINE_BUF
	CALL	PARSE_DEC_WORD		; DE = line number
	EX	DE,HL			; HL = line number
	CALL	GOTO_LINE_HL

	; Redraw editor and status bar smoothly without full screen clear flash
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	RET

GOTO_UI_CANCEL:
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	CALL	RENDER_STATUS_BAR
	RET

;------------------------------------------------------------------------------
; SEARCH AND REPLACE ENGINE
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; DO_FIND_UI: Display centered Tier 2 modal pop-up for Find, read pattern,
; and execute search.
; Dimensions: 50 columns wide x 7 rows high.
; Returns: Carry=0 on match found, Carry=1 on cancel or not found
;------------------------------------------------------------------------------
DO_FIND_UI:
	; Check if starting from an active block
	CALL	CHECK_START_FROM_BLOCK
	; B = character count in SEARCH_INPUT_BUF (0..FIND_POPUP_FIELD_LEN)
	; If B > 0, SEARCH_INPUT_BUF has block text, and (CUR_DOC_ROW, CUR_COL)
	; set to block start

	; Setup prompt and edit box
	CALL	DRAW_FIND_POPUP_FULL

FIND_UI_KEY_LOOP:
	CALL	GET_KEY

	; Check ESC / escape sequence
	CP	KEY_ESC
	JP	Z,FIND_UI_CHECK_ESC

	; Check Enter -> Confirm
	CP	KEY_ENTER
	JP	Z,FIND_UI_ENTER

	; Check Backspace / Delete
	CP	KEY_BACKSPACE
	JR	Z,FIND_UI_BS
	CP	KEY_DEL
	JR	Z,FIND_UI_BS

	; Check Ctrl+I (Tab) -> Toggle case sensitivity
	CP	KEY_CTRL_I
	JR	Z,FIND_UI_TOGGLE_CASE

	; Check printable character (ASCII 32..126)
	CP	' '
	JR	C,FIND_UI_KEY_LOOP
	CP	127
	JR	NC,FIND_UI_KEY_LOOP

	; Check buffer capacity (FIND_POPUP_FIELD_LEN = 29)
	LD	C,A			; Save character
	LD	A,B
	CP	FIND_POPUP_FIELD_LEN
	JR	NC,FIND_UI_KEY_LOOP

	; Append to SEARCH_INPUT_BUF
	LD	HL,SEARCH_INPUT_BUF
	LD	E,B
	LD	D,0
	ADD	HL,DE
	LD	(HL),C
	INC	HL
	LD	(HL),0			; Null terminate
	INC	B

	; Echo character
	LD	A,C
	CALL	PUTC
	JR	FIND_UI_KEY_LOOP

FIND_UI_BS:
	LD	A,B
	OR	A
	JR	Z,FIND_UI_KEY_LOOP	; Nothing to backspace

	DEC	B
	LD	HL,SEARCH_INPUT_BUF
	LD	E,B
	LD	D,0
	ADD	HL,DE
	LD	(HL),0			; Null terminate at new length

	; Visual backspace: \x08 \x20 \x08
	LD	A,008H
	CALL	PUTC
	LD	A,' '
	CALL	PUTC
	LD	A,008H
	CALL	PUTC
	JR	FIND_UI_KEY_LOOP

FIND_UI_TOGGLE_CASE:
	; Toggle SEARCH_CASE_SENSITIVE (0 <-> 1)
	LD	A,(SEARCH_CASE_SENSITIVE)
	XOR	1
	LD	(SEARCH_CASE_SENSITIVE),A

	; Redraw popup dialog
	LD	A,(POPUP_START_ROW)
	LD	(POPUP_ROW),A
	CALL	DRAW_FIND_POPUP_BODY
	JR	FIND_UI_KEY_LOOP

DRAW_FIND_POPUP_FULL:
	; 1. Calculate POPUP_COL = ((ACTIVE_COLS - 50) / 2) + 1
	LD	A,(ACTIVE_COLS)
	SUB	50
	SRL	A
	INC	A
	LD	(POPUP_COL),A

	; 2. Calculate POPUP_ROW = ((ACTIVE_ROWS - 7) / 2) + 1
	LD	A,(ACTIVE_ROWS)
	SUB	7
	SRL	A
	INC	A
	LD	(POPUP_ROW),A
	LD	(POPUP_START_ROW),A

DRAW_FIND_POPUP_BODY:
	LD	DE,STR_HIDE_CURSOR
	CALL	PRINT_STR

	; Line 1: Border
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	PRINT_STR

	; Line 2: Title
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_FIND_POPUP_TITLE
	CALL	PRINT_STR

	; Line 3: Border
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	PRINT_STR

	; Line 4: Prompt and input field
	CALL	POPUP_LOCATE_NEXT
	LD	A,(SEARCH_CASE_SENSITIVE)
	OR	A
	JR	Z,DFP_INSENS
	LD	DE,STR_FIND_POPUP_PROMPT_EXACT
	JR	DFP_PRINT_PFX
DFP_INSENS:
	LD	DE,STR_FIND_POPUP_PROMPT_INSENS
DFP_PRINT_PFX:
	CALL	PRINT_STR
	; Echo prefilled / current SEARCH_INPUT_BUF if B > 0
	LD	A,B
	OR	A
	JR	Z,DFP_PAD_SPACES
	LD	DE,SEARCH_INPUT_BUF
	CALL	PRINT_STR
DFP_PAD_SPACES:
	LD	A,FIND_POPUP_FIELD_LEN
	SUB	B
	JR	Z,DFP_BOX_CLOSE
	LD	C,A
DFP_PAD_LOOP:
	LD	A,' '
	CALL	PUTC
	DEC	C
	JR	NZ,DFP_PAD_LOOP
DFP_BOX_CLOSE:
	LD	DE,STR_FIND_POPUP_BOX_CLOSE
	CALL	PRINT_STR

	; Line 5: Match mode
	CALL	POPUP_LOCATE_NEXT
	LD	A,(SEARCH_CASE_SENSITIVE)
	OR	A
	JR	Z,DFP_MODE_INSENS
	LD	DE,STR_FIND_POPUP_MODE_EXACT
	JR	DFP_PRINT_MODE
DFP_MODE_INSENS:
	LD	DE,STR_FIND_POPUP_MODE_INSENS
DFP_PRINT_MODE:
	CALL	PRINT_STR

	; Line 6: Keys
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_FIND_POPUP_KEYS
	CALL	PRINT_STR

	; Line 7: Border
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	PRINT_STR

	; Position cursor inside popup box at
	; (POPUP_START_ROW + 3, POPUP_COL + 18 + B)
	LD	A,(POPUP_START_ROW)
	ADD	A,3
	LD	H,A
	LD	A,(POPUP_COL)
	ADD	A,18
	ADD	A,B
	LD	L,A
	CALL	LOCATE_RC
	LD	DE,STR_SHOW_CURSOR
	CALL	PRINT_STR
	RET

FIND_UI_CHECK_ESC:
	; Check if escape sequence
	LD	BC,ESC_TIMEOUT_LOOPS
FIND_WAIT_ESC:
	CALL	CHECK_KEY_READY
	JR	NZ,FIND_GOT_ESC_SEQ
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,FIND_WAIT_ESC
	JR	FIND_UI_CANCEL

FIND_GOT_ESC_SEQ:
	CALL	GOT_ESC_BYTE
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	CALL	LOCATE_CURSOR
	SCF
	RET

FIND_UI_CANCEL:
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	CALL	LOCATE_CURSOR
	SCF
	RET

FIND_UI_ENTER:
	; If B > 0, copy SEARCH_INPUT_BUF into SEARCH_BUF
	LD	A,B
	OR	A
	JR	Z,FIND_CHECK_PREV

	; Copy B bytes + null
	LD	(SEARCH_LEN),A
	LD	HL,SEARCH_INPUT_BUF
	LD	DE,SEARCH_BUF
	LD	C,A
	LD	B,0
	INC	BC			; Include null terminator
	LDIR

	; Reset SEARCH_EVER_FOUND for new search pattern
	XOR	A
	LD	(SEARCH_EVER_FOUND),A
	JR	FIND_EXEC_SEARCH

FIND_CHECK_PREV:
	; B == 0: check if existing SEARCH_LEN > 0
	LD	A,(SEARCH_LEN)
	OR	A
	JR	Z,FIND_UI_CANCEL	; No previous pattern, cancel

FIND_EXEC_SEARCH:
	CALL	FIND_STRING_FORWARD
	RET	NC			; Match found: defer render to MAIN_LOOP

	; Search failed: erase popup dialog by redrawing screen
	CALL	RENDER_SCREEN
	LD	A,(SEARCH_EVER_FOUND)
	OR	A
	LD	DE,STR_PATTERN_NOT_FOUND
	JR	Z,FES_PRINT_MSG
	LD	DE,STR_SEARCH_COMPLETED
FES_PRINT_MSG:
	CALL	S_PRINT_MSG
	SCF
	RET


;------------------------------------------------------------------------------
; CHECK_START_FROM_BLOCK: Check if block selection active; if so, populate
; SEARCH_INPUT_BUF with block text and set cursor to block start.
; Implies Ctrl+K if BLOCK_ACTIVE == 1.
; Output: B = count of characters pre-filled in SEARCH_INPUT_BUF (0..64)
;         SEARCH_INPUT_BUF is null-terminated
;------------------------------------------------------------------------------
CHECK_START_FROM_BLOCK:
	LD	HL,SEARCH_INPUT_BUF
	LD	(HL),0
	LD	B,0

	LD	A,(BLOCK_ACTIVE)
	OR	A
	RET	Z			; No block active, return with B=0

	CP	1
	JR	NZ,CSFB_CHECK_SOLID
	; BLOCK_ACTIVE == 1: User is actively in selection mode!
	; Implied Ctrl-K: solidify dynamic selection
	CALL	SOLIDIFY_BLOCK
	JR	CSFB_EXTRACT

CSFB_CHECK_SOLID:
	; BLOCK_ACTIVE == 2: Check if cursor is at or in the block!
	; If cursor has navigated away from the block, cancel block and do normal find!
	CALL	NORMALIZE_BLOCK_BOUNDS

	; Check if CUR_DOC_ROW is within [BLOCK_START_ROW, BLOCK_END_ROW]
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(BLOCK_START_ROW)
	OR	A
	SBC	HL,DE
	JR	C,CSFB_CANCEL_OLD_BLOCK	; CUR_DOC_ROW < BLOCK_START_ROW -> moved away!

	LD	HL,(BLOCK_END_ROW)
	LD	DE,(CUR_DOC_ROW)
	OR	A
	SBC	HL,DE
	JR	C,CSFB_CANCEL_OLD_BLOCK	; CUR_DOC_ROW > BLOCK_END_ROW -> moved away!

	; On row: for single-line block, check if CUR_COL is within [BLOCK_START_COL, BLOCK_END_COL]
	LD	HL,(BLOCK_START_ROW)
	LD	DE,(BLOCK_END_ROW)
	OR	A
	SBC	HL,DE
	JR	NZ,CSFB_EXTRACT		; Multi-line row within range: ok

	; Single-line block:
	LD	A,(CUR_COL)
	LD	HL,BLOCK_START_COL
	CP	(HL)
	JR	C,CSFB_CANCEL_OLD_BLOCK	; CUR_COL < BLOCK_START_COL -> moved away!
	LD	HL,BLOCK_END_COL
	CP	(HL)
	JR	Z,CSFB_EXTRACT		; CUR_COL == BLOCK_END_COL (at end of block): ok!
	JR	C,CSFB_EXTRACT		; CUR_COL < BLOCK_END_COL: ok!
	; CUR_COL > BLOCK_END_COL: moved away!

CSFB_CANCEL_OLD_BLOCK:
	CALL	CANCEL_BLOCK
	RET				; Return with B=0 (empty prompt)

CSFB_EXTRACT:

	; Set cursor to (BLOCK_START_ROW, BLOCK_START_COL)
	LD	HL,(BLOCK_START_ROW)
	LD	(CUR_DOC_ROW),HL
	LD	A,(BLOCK_START_COL)
	LD	(CUR_COL),A
	LD	(TARGET_COL),A

	; Read block text from BLOCK_START_ROW
	LD	BC,(BLOCK_START_ROW)
	CALL	ENSURE_CACHE_WINDOW	; HL = LINE_STORAGE line start

	; Advance HL to BLOCK_START_COL
	LD	A,(BLOCK_START_COL)
	LD	E,A
	LD	D,0
	ADD	HL,DE			; HL = start of block text in line

	; Calculate block length on this row
	; Check if BLOCK_START_ROW == BLOCK_END_ROW
	LD	DE,(BLOCK_END_ROW)
	LD	BC,(BLOCK_START_ROW)
	LD	A,B
	CP	D
	JR	NZ,CSFB_DIFF_ROW
	LD	A,C
	CP	E
	JR	NZ,CSFB_DIFF_ROW

	; Same row: length = BLOCK_END_COL - BLOCK_START_COL
	LD	A,(BLOCK_START_COL)
	LD	C,A
	LD	A,(BLOCK_END_COL)
	SUB	C			; A = BLOCK_END_COL - BLOCK_START_COL
	JR	CSFB_GOT_LEN

CSFB_DIFF_ROW:
	; Spans multiple lines: take up to 29 chars from start line
	LD	A,FIND_POPUP_FIELD_LEN

CSFB_GOT_LEN:
	; A = max chars to copy from block. Limit to FIND_POPUP_FIELD_LEN (29)
	CP	FIND_POPUP_FIELD_LEN+1
	JR	C,CSFB_LEN_OK
	LD	A,FIND_POPUP_FIELD_LEN
CSFB_LEN_OK:
	LD	C,A			; C = max chars
	OR	A
	RET	Z			; 0 chars? Return B=0

	LD	DE,SEARCH_INPUT_BUF
	LD	B,0			; B counts copied chars
CSFB_COPY_LOOP:
	LD	A,(HL)
	CP	' '
	JR	C,CSFB_COPY_DONE	; Stop at null (0) or control chars
	CP	127
	JR	NC,CSFB_COPY_DONE
	LD	(DE),A
	INC	HL
	INC	DE
	INC	B
	LD	A,B
	CP	C
	JR	NC,CSFB_COPY_DONE
	JR	CSFB_COPY_LOOP

CSFB_COPY_DONE:
	XOR	A
	LD	(DE),A			; Null terminate SEARCH_INPUT_BUF
	RET

;------------------------------------------------------------------------------
; DO_FIND_NEXT: Repeat search for SEARCH_BUF forward from (CUR_COL + 1)
; If active block is solidified, start forward from BLOCK_START_COL + 1
;------------------------------------------------------------------------------
DO_FIND_NEXT:
	LD	A,(SEARCH_LEN)
	OR	A
	JP	Z,DO_FIND_UI		; If no search pattern set, open Find UI

	; Save current position in case search fails
	LD	HL,(CUR_DOC_ROW)
	LD	(PREV_START_ROW_TEMP),HL
	LD	A,(CUR_COL)
	LD	(PREV_START_COL_TEMP),A

	; Check if active block is solidified (state 2)
	LD	A,(BLOCK_ACTIVE)
	CP	2
	JR	NZ,DFN_NORMAL_START

	; Solidified block match: wrap limit is BLOCK_START_ROW, BLOCK_START_COL
	LD	HL,(BLOCK_START_ROW)
	LD	(SEARCH_START_ROW),HL
	LD	A,(BLOCK_START_COL)
	LD	(SEARCH_START_COL),A

	; Advance from BLOCK_START_COL by 1
	INC	A
	LD	(CUR_COL),A
	JR	DFN_DO_SEARCH

DFN_NORMAL_START:
	LD	HL,(CUR_DOC_ROW)
	LD	(SEARCH_START_ROW),HL
	LD	A,(CUR_COL)
	LD	(SEARCH_START_COL),A
	INC	A
	LD	(CUR_COL),A

DFN_DO_SEARCH:
	XOR	A
	LD	(SEARCH_WRAPPED),A
	CALL	FIND_STRING_FORWARD_CONT
	RET	NC			; Match found

	; Failed / completed: restore original position
	LD	HL,(PREV_START_ROW_TEMP)
	LD	(CUR_DOC_ROW),HL
	LD	A,(PREV_START_COL_TEMP)
	LD	(CUR_COL),A
	LD	(TARGET_COL),A
	CALL	LOCATE_CURSOR
	RET

;------------------------------------------------------------------------------
; DO_FIND_PREV: Repeat search for SEARCH_BUF backward from (CUR_COL - 1)
; If active block is solidified, step back from BLOCK_START_COL
;------------------------------------------------------------------------------
DO_FIND_PREV:
	LD	A,(SEARCH_LEN)
	OR	A
	JP	Z,DO_FIND_UI		; If no search pattern set, open Find UI

	; Save current position in case search fails
	LD	HL,(CUR_DOC_ROW)
	LD	(PREV_START_ROW_TEMP),HL
	LD	A,(CUR_COL)
	LD	(PREV_START_COL_TEMP),A

	; Check if active block is solidified (state 2)
	LD	A,(BLOCK_ACTIVE)
	CP	2
	JR	NZ,DFP_NORMAL_START

	; Solidified block match: wrap limit is BLOCK_START_ROW, BLOCK_START_COL
	LD	HL,(BLOCK_START_ROW)
	LD	(SEARCH_START_ROW),HL
	LD	A,(BLOCK_START_COL)
	LD	(SEARCH_START_COL),A

	; Step backward from BLOCK_START_COL
	LD	(CUR_COL),A
	CALL	STEP_BACK_ONE_CHAR
	JR	DFP_DO_SEARCH

DFP_NORMAL_START:
	LD	HL,(CUR_DOC_ROW)
	LD	(SEARCH_START_ROW),HL
	LD	A,(CUR_COL)
	LD	(SEARCH_START_COL),A
	CALL	STEP_BACK_ONE_CHAR

DFP_DO_SEARCH:
	XOR	A
	LD	(SEARCH_WRAPPED),A
	CALL	FIND_STRING_BACKWARD_CONT
	RET	NC			; Match found

	; Failed / completed: restore original position
	LD	HL,(PREV_START_ROW_TEMP)
	LD	(CUR_DOC_ROW),HL
	LD	A,(PREV_START_COL_TEMP)
	LD	(CUR_COL),A
	LD	(TARGET_COL),A
	CALL	LOCATE_CURSOR
	RET

;------------------------------------------------------------------------------
; STEP_BACK_ONE_CHAR: Move cursor position back 1 character or wrap to prev line
;------------------------------------------------------------------------------
STEP_BACK_ONE_CHAR:
	LD	A,(CUR_COL)
	OR	A
	JR	Z,SBOC_PREV_LINE
	DEC	A
	LD	(CUR_COL),A
	RET
SBOC_PREV_LINE:
	LD	HL,(CUR_DOC_ROW)
	LD	A,H
	OR	L
	JR	Z,SBOC_WRAP_EOF
	DEC	HL
	LD	(CUR_DOC_ROW),HL
	JR	SBOC_SET_END
SBOC_WRAP_EOF:
	LD	HL,(DOC_TOTAL_LINES)
	DEC	HL
	LD	(CUR_DOC_ROW),HL
SBOC_SET_END:
	LD	A,255
	LD	(CUR_COL),A
	RET

;------------------------------------------------------------------------------
; HIGHLIGHT_FOUND_BLOCK: Solidify block highlighting on found match
; Inputs: (CUR_DOC_ROW, CUR_COL) = match start, SEARCH_LEN = match byte length
; Sets BLOCK_START_ROW/COL, BLOCK_END_ROW/COL, BLOCK_ANCHOR_ROW/COL, BLOCK_ACTIVE=2
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
HIGHLIGHT_FOUND_BLOCK:
	PUSH	HL
	PUSH	AF
	LD	HL,(CUR_DOC_ROW)
	LD	(BLOCK_START_ROW),HL
	LD	(BLOCK_END_ROW),HL
	LD	(BLOCK_ANCHOR_ROW),HL
	LD	A,(CUR_COL)
	LD	(BLOCK_START_COL),A
	LD	(BLOCK_ANCHOR_COL),A
	LD	HL,SEARCH_LEN
	ADD	A,(HL)
	LD	(BLOCK_END_COL),A
	LD	A,2			; State 2 = Solidified / Locked
	LD	(BLOCK_ACTIVE),A
	POP	AF
	POP	HL
	RET

;------------------------------------------------------------------------------
; FIND_STRING_FORWARD: Search forward from (CUR_DOC_ROW, CUR_COL) for SEARCH_BUF
; Wraps around EOF to Line 0 up to original position.
; Returns: Carry=0 on match (CUR_DOC_ROW, CUR_COL updated, screen centered, solidified block set)
;          Carry=1 if pattern not found ("Search completed" or "Pattern not found" shown)
;------------------------------------------------------------------------------
FIND_STRING_FORWARD:
	LD	A,(SEARCH_LEN)
	OR	A
	SCF
	RET	Z			; Cannot search empty string

	; Record starting position for wrap limit detection
	LD	HL,(CUR_DOC_ROW)
	LD	(SEARCH_START_ROW),HL
	LD	A,(CUR_COL)
	LD	(SEARCH_START_COL),A
	XOR	A
	LD	(SEARCH_WRAPPED),A

FIND_STRING_FORWARD_CONT:
	LD	A,1
	LD	(SEARCH_FIRST_LINE),A

SEARCH_LINE_LOOP:
	; Fetch line from cache/Far RAM
	LD	BC,(CUR_DOC_ROW)
	CALL	ENSURE_CACHE_WINDOW	; HL = pointer to line in LINE_STORAGE

	; Calculate line length in bytes (null terminated)
	PUSH	HL
	LD	C,0			; C = byte length
SCAN_LINE_LEN:
	LD	A,(HL)
	OR	A
	JR	Z,SCAN_LINE_LEN_DONE
	INC	HL
	INC	C
	LD	A,C
	CP	MAX_LINE_STRIDE-2
	JR	C,SCAN_LINE_LEN
SCAN_LINE_LEN_DONE:
	POP	HL			; HL = line start
	; Line length is in C (0..120)

	; Check if line length >= SEARCH_LEN
	LD	A,(SEARCH_LEN)
	CP	C
	JR	Z,CAN_MATCH_LEN
	JP	NC,ADVANCE_NEXT_LINE	; If SEARCH_LEN > C, cannot match

CAN_MATCH_LEN:
	; max_col = C - SEARCH_LEN
	LD	A,(SEARCH_LEN)
	LD	E,A
	LD	A,C
	SUB	E
	LD	C,A			; C = max_col (0..119)

	; Determine candidate start column
	LD	A,(SEARCH_FIRST_LINE)
	OR	A
	JR	Z,START_COL_ZERO
	LD	A,(CUR_COL)
	JR	GOT_START_COL
START_COL_ZERO:
	XOR	A
GOT_START_COL:
	LD	B,A			; B = candidate column (cand_col)

	; If cand_col > max_col, no match on this line
	LD	A,C
	CP	B
	JP	C,ADVANCE_NEXT_LINE

SCAN_COL_LOOP:
	; If wrapped and on SEARCH_START_ROW, do not search beyond SEARCH_START_COL
	LD	A,(SEARCH_WRAPPED)
	OR	A
	JR	Z,CHECK_COL_MATCH
	PUSH	HL
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(SEARCH_START_ROW)
	OR	A
	SBC	HL,DE
	POP	HL
	JR	NZ,CHECK_COL_MATCH
	; On SEARCH_START_ROW wrapped:
	LD	A,(SEARCH_EVER_FOUND)
	OR	A
	JR	NZ,SCL_WRAP_EXCLUSIVE

	; Inclusive (initial find): B > SEARCH_START_COL -> not found
	LD	A,(SEARCH_START_COL)
	CP	B
	JP	C,SEARCH_NOT_FOUND
	JR	CHECK_COL_MATCH

SCL_WRAP_EXCLUSIVE:
	; Exclusive (repeat find / replace): B >= SEARCH_START_COL -> search completed
	LD	A,(SEARCH_START_COL)
	LD	E,A
	LD	A,B
	CP	E
	JP	NC,SEARCH_NOT_FOUND
	JR	CHECK_COL_MATCH

CHECK_COL_MATCH:
	; Check match at column B:
	PUSH	BC
	PUSH	HL
	LD	E,B
	LD	D,0
	ADD	HL,DE			; HL = line_start + cand_col
	CALL	MATCH_SUBSTRING
	POP	HL
	POP	BC
	JR	Z,MATCH_FOUND_AT_B

	; Not matched, advance cand_col
	INC	B
	LD	A,C			; C = max_col
	CP	B
	JR	NC,SCAN_COL_LOOP
	JP	ADVANCE_NEXT_LINE

MATCH_FOUND_AT_B:
	LD	A,B
	LD	(CUR_COL),A
	LD	(TARGET_COL),A

	; Check if CUR_DOC_ROW is currently on visible screen
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(TOP_DOC_ROW)
	OR	A
	SBC	HL,DE			; HL = CUR_DOC_ROW - TOP_DOC_ROW
	JR	C,DO_SEARCH_RECENTER
	LD	A,(ACTIVE_ROWS)
	DEC	A
	LD	E,A
	LD	D,0
	OR	A
	SBC	HL,DE
	JR	NC,DO_SEARCH_RECENTER
	JR	SEARCH_POS_OK

DO_SEARCH_RECENTER:
	PUSH	BC
	LD	HL,(CUR_DOC_ROW)
	INC	HL			; 1-indexed for GOTO_LINE_HL
	CALL	GOTO_LINE_HL
	POP	BC
	LD	A,B
	LD	(CUR_COL),A
	LD	(TARGET_COL),A

SEARCH_POS_OK:
	; Mark that at least one match was found
	LD	A,1
	LD	(SEARCH_EVER_FOUND),A

	; Solidify block highlight on match
	CALL	HIGHLIGHT_FOUND_BLOCK

	; Position cursor at the next character position past the end of the block
	LD	A,(BLOCK_END_COL)
	LD	(CUR_COL),A
	CALL	CALC_VISUAL_COL
	LD	(TARGET_COL),A

	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	LD	(NEED_STATUS_RENDER),A
	OR	A			; Clear carry (success)
	RET

ADVANCE_NEXT_LINE:
	XOR	A
	LD	(SEARCH_FIRST_LINE),A
	LD	HL,(CUR_DOC_ROW)
	INC	HL
	LD	(CUR_DOC_ROW),HL
	LD	DE,(DOC_TOTAL_LINES)
	OR	A
	SBC	HL,DE
	JR	C,CHECK_WRAP_LIMIT

	; Reached EOF: wrap around to line 0
	LD	A,(SEARCH_WRAPPED)
	OR	A
	JP	NZ,SEARCH_NOT_FOUND	; Already wrapped once!
	LD	A,1
	LD	(SEARCH_WRAPPED),A
	LD	HL,0
	LD	(CUR_DOC_ROW),HL

CHECK_WRAP_LIMIT:
	LD	A,(SEARCH_WRAPPED)
	OR	A
	JP	Z,SEARCH_LINE_LOOP	; If not wrapped, continue

	; If wrapped, compare CUR_DOC_ROW with SEARCH_START_ROW
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(SEARCH_START_ROW)
	OR	A
	SBC	HL,DE
	JP	C,SEARCH_LINE_LOOP	; CUR_DOC_ROW < SEARCH_START_ROW: continue
	JP	Z,SEARCH_LINE_LOOP	; CUR_DOC_ROW == SEARCH_START_ROW: do wrapped pass
	JP	SEARCH_NOT_FOUND	; CUR_DOC_ROW > SEARCH_START_ROW: done

;------------------------------------------------------------------------------
; FIND_STRING_BACKWARD: Search backward from (CUR_DOC_ROW, CUR_COL) for SEARCH_BUF
; Wraps around line 0 to EOF up to original position.
; Returns: Carry=0 on match (CUR_DOC_ROW, CUR_COL updated, screen centered, solidified block set)
;          Carry=1 if pattern not found ("Search completed" or "Pattern not found" shown)
;------------------------------------------------------------------------------
FIND_STRING_BACKWARD:
	LD	A,(SEARCH_LEN)
	OR	A
	SCF
	RET	Z			; Cannot search empty string

	; Record starting position for wrap limit detection
	LD	HL,(CUR_DOC_ROW)
	LD	(SEARCH_START_ROW),HL
	LD	A,(CUR_COL)
	LD	(SEARCH_START_COL),A
	XOR	A
	LD	(SEARCH_WRAPPED),A

FIND_STRING_BACKWARD_CONT:
	LD	A,1
	LD	(SEARCH_FIRST_LINE),A

SEARCH_BW_LINE_LOOP:
	; Fetch line from cache/Far RAM
	LD	BC,(CUR_DOC_ROW)
	CALL	ENSURE_CACHE_WINDOW	; HL = pointer to line in LINE_STORAGE

	; Calculate line length in bytes (null terminated)
	PUSH	HL
	LD	C,0			; C = byte length
SCAN_BW_LINE_LEN:
	LD	A,(HL)
	OR	A
	JR	Z,SCAN_BW_LINE_LEN_DONE
	INC	HL
	INC	C
	LD	A,C
	CP	MAX_LINE_STRIDE-2
	JR	C,SCAN_BW_LINE_LEN
SCAN_BW_LINE_LEN_DONE:
	POP	HL			; HL = line start
	; Line length is in C (0..120)

	; Check if line length >= SEARCH_LEN
	LD	A,(SEARCH_LEN)
	CP	C
	JR	Z,BW_CAN_MATCH_LEN
	JP	NC,RETREAT_PREV_LINE	; If SEARCH_LEN > C, cannot match

BW_CAN_MATCH_LEN:
	; max_col = C - SEARCH_LEN
	LD	A,(SEARCH_LEN)
	LD	E,A
	LD	A,C
	SUB	E
	LD	E,A			; E = max_col (0..119)

	; Determine candidate start column in B
	LD	A,(SEARCH_FIRST_LINE)
	OR	A
	JR	Z,BW_START_COL_MAX

	; On first line: clamp start col to max_col
	LD	A,(CUR_COL)
	CP	E
	JR	C,BW_GOT_FIRST_COL	; If CUR_COL < max_col, ok
	LD	A,E			; Else clamp to max_col
BW_GOT_FIRST_COL:
	LD	(SEARCH_START_COL),A	; Store clamped start col for wrap limit
	JR	BW_GOT_START_COL

BW_START_COL_MAX:
	LD	A,E			; Start at max_col

BW_GOT_START_COL:
	LD	B,A			; B = candidate column (cand_col)

SCAN_BW_COL_LOOP:
	; If wrapped and on SEARCH_START_ROW, do not search before SEARCH_START_COL
	LD	A,(SEARCH_WRAPPED)
	OR	A
	JR	Z,BW_CHECK_COL_MATCH
	PUSH	HL
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(SEARCH_START_ROW)
	OR	A
	SBC	HL,DE
	POP	HL
	JR	NZ,BW_CHECK_COL_MATCH

	; On SEARCH_START_ROW wrapped:
	LD	A,(SEARCH_EVER_FOUND)
	OR	A
	JR	NZ,BW_WRAP_EXCLUSIVE

	; Inclusive (initial find): B < SEARCH_START_COL -> not found
	LD	A,(SEARCH_START_COL)
	LD	E,A
	LD	A,B
	CP	E
	JP	C,SEARCH_NOT_FOUND
	JR	BW_CHECK_COL_MATCH

BW_WRAP_EXCLUSIVE:
	; Exclusive (repeat find / replace): B <= SEARCH_START_COL -> search completed
	LD	A,(SEARCH_START_COL)
	LD	E,A
	LD	A,B
	CP	E
	JP	Z,SEARCH_NOT_FOUND
	JP	C,SEARCH_NOT_FOUND
	JR	BW_CHECK_COL_MATCH

BW_CHECK_COL_MATCH:
	; Check match at column B:
	PUSH	BC
	PUSH	HL
	LD	E,B
	LD	D,0
	ADD	HL,DE			; HL = line_start + cand_col
	CALL	MATCH_SUBSTRING
	POP	HL
	POP	BC
	JP	Z,MATCH_FOUND_AT_B

	; Not matched: step B backward
	LD	A,B
	OR	A
	JR	Z,RETREAT_PREV_LINE	; Reached col 0: retreat to previous line
	DEC	B
	JR	SCAN_BW_COL_LOOP

RETREAT_PREV_LINE:
	XOR	A
	LD	(SEARCH_FIRST_LINE),A

	; Check if CUR_DOC_ROW == 0
	LD	HL,(CUR_DOC_ROW)
	LD	A,H
	OR	L
	JR	Z,BW_WRAP_EOF

	; Previous line: CUR_DOC_ROW - 1
	DEC	HL
	LD	(CUR_DOC_ROW),HL
	JR	CHECK_BW_WRAP_LIMIT

BW_WRAP_EOF:
	; Wrapped around to end of file
	LD	A,(SEARCH_WRAPPED)
	OR	A
	JP	NZ,SEARCH_NOT_FOUND	; Already wrapped once!
	LD	A,1
	LD	(SEARCH_WRAPPED),A
	LD	HL,(DOC_TOTAL_LINES)
	DEC	HL
	LD	(CUR_DOC_ROW),HL

CHECK_BW_WRAP_LIMIT:
	LD	A,(SEARCH_WRAPPED)
	OR	A
	JP	Z,SEARCH_BW_LINE_LOOP

	; If wrapped, compare CUR_DOC_ROW with SEARCH_START_ROW
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(SEARCH_START_ROW)
	OR	A
	SBC	HL,DE
	JP	NC,SEARCH_BW_LINE_LOOP	; CUR_DOC_ROW >= SEARCH_START_ROW: valid
	JP	SEARCH_NOT_FOUND		; CUR_DOC_ROW < SEARCH_START_ROW: passed origin!

SEARCH_NOT_FOUND:
	; Restore initial cursor position
	LD	HL,(SEARCH_START_ROW)
	LD	(CUR_DOC_ROW),HL
	LD	A,(SEARCH_START_COL)
	LD	(CUR_COL),A
	LD	(TARGET_COL),A

	; Check if pattern was ever found during this search session
	LD	A,(SEARCH_EVER_FOUND)
	OR	A
	JR	NZ,S_SHOW_COMPLETED

	; Never found: cancel block and display " Pattern not found. "
	CALL	CANCEL_BLOCK
	LD	DE,STR_PATTERN_NOT_FOUND
	JR	S_PRINT_MSG

S_SHOW_COMPLETED:
	; Previously found: keep current match highlighted, display " Search completed. "
	LD	DE,STR_SEARCH_COMPLETED

S_PRINT_MSG:
	PUSH	DE
	CALL	LOCATE_STATUS_ROW
	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR
	POP	DE
	CALL	PRINT_STR
	LD	DE,STR_CLEAR_EOL
	CALL	PRINT_STR
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR

	XOR	A
	LD	(NEED_STATUS_RENDER),A	; Keep message visible
	CALL	LOCATE_CURSOR
	SCF				; Set carry (failure)
	RET

;------------------------------------------------------------------------------
; MATCH_SUBSTRING: Compare string at HL with SEARCH_BUF (SEARCH_LEN bytes)
; Respects SEARCH_CASE_SENSITIVE (1 = exact, 0 = case-insensitive)
; Returns: Z set if full match, NZ if mismatch
; Preserves: DE, HL
;------------------------------------------------------------------------------
MATCH_SUBSTRING:
	PUSH	DE
	PUSH	HL
	LD	DE,SEARCH_BUF
	LD	A,(SEARCH_LEN)
	LD	B,A
MATCH_SUB_LOOP:
	LD	A,(DE)			; A = pattern char
	LD	C,(HL)			; C = line char
	LD	A,(SEARCH_CASE_SENSITIVE)
	OR	A
	JR	NZ,MATCH_SUB_EXACT

	; Case insensitive: fold both to uppercase
	LD	A,(DE)
	CALL	TO_UPPER_CHAR
	PUSH	AF
	LD	A,C
	CALL	TO_UPPER_CHAR
	LD	C,A
	POP	AF
	CP	C
	JR	NZ,MATCH_SUB_FAIL
	JR	MATCH_SUB_NEXT

MATCH_SUB_EXACT:
	LD	A,(DE)
	CP	C
	JR	NZ,MATCH_SUB_FAIL

MATCH_SUB_NEXT:
	INC	DE
	INC	HL
	DJNZ	MATCH_SUB_LOOP

	; Full match!
	POP	HL
	POP	DE
	XOR	A			; Set Z flag
	RET

MATCH_SUB_FAIL:
	POP	HL
	POP	DE
	OR	1			; Clear Z flag (NZ)
	RET

TO_UPPER_CHAR:
	CP	'a'
	RET	C
	CP	'z'+1
	RET	NC
	SUB	20H
	RET

;------------------------------------------------------------------------------
; DO_REPLACE_UI: Prompt for Find and Replace strings via Tier 2 modal popups,
; then execute replace loop.
;------------------------------------------------------------------------------
DO_REPLACE_UI:
	; 1. First get search pattern via DO_FIND_UI
	CALL	DO_FIND_UI
	RET	C			; Cancelled or pattern not found

	; Note: DO_FIND_UI already executed first search and positioned at first match!

	; 2. Prompt for replacement string via Tier 2 centered modal popup
	CALL	DRAW_REPLACE_POPUP_FULL

	; Clear replace buffer
	LD	HL,REPLACE_BUF
	LD	(HL),0
	LD	B,0			; B = character count (0..FIND_POPUP_FIELD_LEN)

REPLACE_INPUT_LOOP:
	CALL	GET_KEY

	; ESC -> Cancel replace
	CP	KEY_ESC
	JR	Z,REPLACE_INPUT_CHECK_ESC

	; Enter -> Confirm replacement string
	CP	KEY_ENTER
	JR	Z,REPLACE_INPUT_CONFIRM

	; Backspace / Delete
	CP	KEY_BACKSPACE
	JR	Z,REPLACE_INPUT_BS
	CP	KEY_DEL
	JR	Z,REPLACE_INPUT_BS

	; Printable character (ASCII 32..126)
	CP	' '
	JR	C,REPLACE_INPUT_LOOP
	CP	127
	JR	NC,REPLACE_INPUT_LOOP

	; Check max length
	LD	C,A
	LD	A,B
	CP	FIND_POPUP_FIELD_LEN
	JR	NC,REPLACE_INPUT_LOOP

	LD	HL,REPLACE_BUF
	LD	E,B
	LD	D,0
	ADD	HL,DE
	LD	(HL),C
	INC	HL
	LD	(HL),0
	INC	B

	LD	A,C
	CALL	PUTC
	JR	REPLACE_INPUT_LOOP

REPLACE_INPUT_BS:
	LD	A,B
	OR	A
	JR	Z,REPLACE_INPUT_LOOP

	DEC	B
	LD	HL,REPLACE_BUF
	LD	E,B
	LD	D,0
	ADD	HL,DE
	LD	(HL),0

	LD	A,008H
	CALL	PUTC
	LD	A,' '
	CALL	PUTC
	LD	A,008H
	CALL	PUTC
	JR	REPLACE_INPUT_LOOP

REPLACE_INPUT_CHECK_ESC:
	LD	BC,ESC_TIMEOUT_LOOPS
REP_WAIT_ESC:
	CALL	CHECK_KEY_READY
	JR	NZ,REP_GOT_ESC_SEQ
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,REP_WAIT_ESC
	JR	REPLACE_INPUT_CANCEL

REP_GOT_ESC_SEQ:
	CALL	GOT_ESC_BYTE
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	CALL	LOCATE_CURSOR
	RET

REPLACE_INPUT_CANCEL:
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	CALL	LOCATE_CURSOR
	RET

REPLACE_INPUT_CONFIRM:
	LD	A,B
	LD	(REPLACE_LEN),A

	; Clear replace popup by restoring base screen
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	CALL	LOCATE_CURSOR

	; 3. Initialize replace execution
	XOR	A
	LD	(IS_REPLACE_PROMPT),A
	LD	(REPLACE_ALL_MODE),A
	LD	(SEARCH_DIRECTION),A	; 0 = Forward
	LD	HL,0
	LD	(REPLACE_COUNT),HL

	; Lock search wrap origin for this replace session:
	LD	HL,(BLOCK_START_ROW)
	LD	(SEARCH_START_ROW),HL
	LD	A,(BLOCK_START_COL)
	LD	(SEARCH_START_COL),A
	XOR	A
	LD	(SEARCH_WRAPPED),A

	; Enter the replace loop directly for the current match:
	JP	REPLACE_PROCESS_MATCH

DRAW_REPLACE_POPUP_FULL:
	; 1. Calculate POPUP_COL = ((ACTIVE_COLS - 50) / 2) + 1
	LD	A,(ACTIVE_COLS)
	SUB	50
	SRL	A
	INC	A
	LD	(POPUP_COL),A

	; 2. Calculate POPUP_ROW = ((ACTIVE_ROWS - 7) / 2) + 1
	LD	A,(ACTIVE_ROWS)
	SUB	7
	SRL	A
	INC	A
	LD	(POPUP_ROW),A
	LD	(POPUP_START_ROW),A

	LD	DE,STR_HIDE_CURSOR
	CALL	PRINT_STR

	; Line 1: Border
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	PRINT_STR

	; Line 2: Title
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_REPLACE_POPUP_TITLE
	CALL	PRINT_STR

	; Line 3: Border
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	PRINT_STR

	; Line 4: Prompt and empty input box
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_REPLACE_POPUP_PROMPT
	CALL	PRINT_STR
	; Pad 29 spaces for empty box
	LD	C,FIND_POPUP_FIELD_LEN
DRP_PAD_LOOP:
	LD	A,' '
	CALL	PUTC
	DEC	C
	JR	NZ,DRP_PAD_LOOP
	LD	DE,STR_FIND_POPUP_BOX_CLOSE
	CALL	PRINT_STR

	; Line 5: Instructions
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_REPLACE_POPUP_MSG
	CALL	PRINT_STR

	; Line 6: Keys
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_REPLACE_POPUP_KEYS
	CALL	PRINT_STR

	; Line 7: Border
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	PRINT_STR

	; Position cursor inside replace box at (POPUP_START_ROW + 3, POPUP_COL + 18)
	LD	A,(POPUP_START_ROW)
	ADD	A,3
	LD	H,A
	LD	A,(POPUP_COL)
	ADD	A,18
	LD	L,A
	CALL	LOCATE_RC
	LD	DE,STR_SHOW_CURSOR
	CALL	PRINT_STR
	RET

REPLACE_SEARCH_NEXT:
	; Check current search direction
	LD	A,(SEARCH_DIRECTION)
	OR	A
	JR	NZ,REPLACE_SEARCH_BW

	; Advance search position forward
	CALL	FIND_STRING_FORWARD_CONT
	JP	C,REPLACE_SUMMARY	; No more matches
	JR	REPLACE_PROCESS_MATCH

REPLACE_SEARCH_BW:
	; Advance search position backward
	CALL	FIND_STRING_BACKWARD_CONT
	JP	C,REPLACE_SUMMARY	; No more matches
	JR	REPLACE_PROCESS_MATCH

REPLACE_PROCESS_MATCH:
	; If Replace All mode is active, do substitution directly
	LD	A,(REPLACE_ALL_MODE)
	OR	A
	JP	NZ,REPLACE_EXECUTE_SUBST

	; Render screen to show match to user with prompt in status bar
	LD	A,1
	LD	(IS_REPLACE_PROMPT),A
	CALL	FLUSH_DEFERRED_RENDER
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR

REPLACE_CONFIRM_KEY:
	CALL	GET_KEY
	CP	KEY_ESC
	JP	Z,REPLACE_QUIT

	CP	'r'
	JR	Z,REPLACE_DO_REVERSE
	CP	'R'
	JR	Z,REPLACE_DO_REVERSE
	CP	'p'
	JR	Z,REPLACE_DO_REVERSE
	CP	'P'
	JR	Z,REPLACE_DO_REVERSE

	CP	'n'
	JR	Z,REPLACE_DO_SKIP
	CP	'N'
	JR	Z,REPLACE_DO_SKIP

	CP	'a'
	JR	Z,REPLACE_ACTIVATE_ALL
	CP	'A'
	JR	Z,REPLACE_ACTIVATE_ALL

	CP	'y'
	JP	Z,REPLACE_DO_SUBST
	CP	'Y'
	JP	Z,REPLACE_DO_SUBST
	CP	KEY_ENTER
	JP	Z,REPLACE_DO_SUBST

	CALL	LOCATE_REPLACE_PROMPT_CURSOR
	JR	REPLACE_CONFIRM_KEY

REPLACE_QUIT:
	XOR	A
	LD	(IS_REPLACE_PROMPT),A
	JP	REPLACE_SUMMARY

REPLACE_DO_REVERSE:
	XOR	A
	LD	(IS_REPLACE_PROMPT),A
	JR	REPLACE_REVERSE_DIR

REPLACE_DO_SKIP:
	XOR	A
	LD	(IS_REPLACE_PROMPT),A
	JR	REPLACE_SKIP

REPLACE_DO_SUBST:
	XOR	A
	LD	(IS_REPLACE_PROMPT),A
	JP	REPLACE_EXECUTE_SUBST

REPLACE_REVERSE_DIR:
	; Toggle SEARCH_DIRECTION
	LD	A,(SEARCH_DIRECTION)
	XOR	1
	LD	(SEARCH_DIRECTION),A

	; Step in the new direction
	OR	A
	JR	NZ,REPLACE_REV_TO_BW

	; Reversing to Forward: advance col by 1 from match start
	LD	A,(BLOCK_START_COL)
	INC	A
	LD	(CUR_COL),A
	JP	REPLACE_SEARCH_NEXT

REPLACE_REV_TO_BW:
	; Reversing to Backward: step back 1 char from match start
	LD	A,(BLOCK_START_COL)
	LD	(CUR_COL),A
	CALL	STEP_BACK_ONE_CHAR
	JP	REPLACE_SEARCH_NEXT

REPLACE_ACTIVATE_ALL:
	XOR	A
	LD	(IS_REPLACE_PROMPT),A
	LD	(SEARCH_DIRECTION),A	; Ensure forward direction for Replace All
	LD	A,1
	LD	(REPLACE_ALL_MODE),A
	JP	REPLACE_EXECUTE_SUBST

REPLACE_SKIP:
	; Skip this match: advance in current direction
	LD	A,(SEARCH_DIRECTION)
	OR	A
	JR	NZ,REPLACE_SKIP_BW

	; Forward skip: advance col by 1 from match start
	LD	A,(BLOCK_START_COL)
	INC	A
	LD	(CUR_COL),A
	JP	REPLACE_SEARCH_NEXT

REPLACE_SKIP_BW:
	; Backward skip: step back 1 char from match start
	LD	A,(BLOCK_START_COL)
	LD	(CUR_COL),A
	CALL	STEP_BACK_ONE_CHAR
	JP	REPLACE_SEARCH_NEXT

REPLACE_EXECUTE_SUBST:
	; Set CUR_COL to match start col before substitution
	LD	A,(BLOCK_START_COL)
	LD	(CUR_COL),A
	LD	(REPLACE_MATCH_COL),A

	CALL	APPLY_LINE_REPLACE

	LD	A,(SEARCH_DIRECTION)
	OR	A
	JP	Z,REPLACE_SEARCH_NEXT

	; Backward: restore to match col, then step back 1 char
	LD	A,(REPLACE_MATCH_COL)
	LD	(CUR_COL),A
	CALL	STEP_BACK_ONE_CHAR
	JP	REPLACE_SEARCH_NEXT

REPLACE_SUMMARY:
	; Ensure replace prompt flag is cleared
	XOR	A
	LD	(IS_REPLACE_PROMPT),A

	; Cancel any active block highlight
	CALL	CANCEL_BLOCK

	; Display " Replace done: N replacement(s). "
	CALL	LOCATE_STATUS_ROW
	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR
	LD	DE,STR_REPLACE_DONE_PFX
	CALL	PRINT_STR
	LD	HL,(REPLACE_COUNT)
	CALL	PRINT_DEC_WORD
	LD	DE,STR_REPLACE_DONE_SFX
	CALL	PRINT_STR
	LD	DE,STR_CLEAR_EOL
	CALL	PRINT_STR
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR

	LD	A,1
	LD	(NEED_SCREEN_RENDER),A
	XOR	A
	LD	(NEED_STATUS_RENDER),A	; Keep replace done message visible
	CALL	FLUSH_DEFERRED_RENDER
	CALL	RENDER_SCREEN
	CALL	LOCATE_CURSOR
	RET

;------------------------------------------------------------------------------
; APPLY_LINE_REPLACE: Substitute SEARCH_BUF with REPLACE_BUF at (CUR_DOC_ROW, CUR_COL)
; Enforces 120-character line length limit.
;------------------------------------------------------------------------------
APPLY_LINE_REPLACE:
	LD	BC,(CUR_DOC_ROW)
	CALL	ENSURE_CACHE_WINDOW	; HL = line_start in LINE_STORAGE

	; 1. Calculate line length L
	PUSH	HL
	LD	C,0
ALR_CALC_LEN:
	LD	A,(HL)
	OR	A
	JR	Z,ALR_CALC_LEN_DONE
	INC	HL
	INC	C
	LD	A,C
	CP	MAX_LINE_STRIDE-2
	JR	C,ALR_CALC_LEN
ALR_CALC_LEN_DONE:
	POP	HL			; HL = line_start
	; C = L (current line length in bytes)

	; 2. Check resulting line length: L' = L - S + R
	; S = SEARCH_LEN, R = REPLACE_LEN
	LD	A,(SEARCH_LEN)
	LD	B,A			; B = S
	LD	A,(REPLACE_LEN)
	LD	E,A			; E = R

	; L' = C - B + E
	LD	A,C
	SUB	B
	ADD	A,E			; A = L'
	CP	MAX_LINE_STRIDE-7	; 121 (max 120 chars)
	JR	C,ALR_LENGTH_OK

	; Line would exceed 120 chars: display warning and skip
	CALL	LOCATE_STATUS_ROW
	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR
	LD	DE,STR_LINE_TOO_LONG	; " Line > 120 chars - skipped. "
	CALL	PRINT_STR
	LD	DE,STR_CLEAR_EOL
	CALL	PRINT_STR
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR

	; Advance past match start
	LD	A,(CUR_COL)
	INC	A
	LD	(CUR_COL),A
	RET

ALR_LENGTH_OK:
	; 3. Perform substitution
	; PTR = line_start + CUR_COL
	PUSH	HL			; Save line_start
	LD	A,(CUR_COL)
	LD	E,A
	LD	D,0
	ADD	HL,DE
	LD	(REPLACE_PTR_TEMP),HL	; Pointer to match start in line
	POP	HL			; Restore line_start

	; Calculate TAIL_LEN in C:
	; L is in C. TAIL_LEN = L - (CUR_COL + S)
	LD	A,(CUR_COL)
	LD	E,A
	LD	A,(SEARCH_LEN)
	ADD	A,E			; A = CUR_COL + S
	LD	E,A			; E = CUR_COL + S
	LD	A,C			; A = L
	SUB	E			; A = TAIL_LEN
	LD	C,A			; C = TAIL_LEN

	; Number of bytes to move = TAIL_LEN + 1 (includes null terminator)
	INC	C			; C = BYTES_TO_MOVE (tail + null)
	LD	B,0			; BC = count of tail bytes including null

	; Compare S and R:
	LD	A,(SEARCH_LEN)
	LD	D,A			; D = S
	LD	A,(REPLACE_LEN)
	LD	E,A			; E = R
	CP	D
	JR	Z,ALR_EQUAL_LEN
	JR	C,ALR_SHRINK_LEN

	; Case R > S (line expands):
	; Delta = R - S
	SUB	D
	LD	(REPLACE_DELTA_TEMP),A	; Delta

	; Move tail rightwards by Delta bytes:
	; Source last byte = PTR + S + TAIL_LEN (which is PTR + S + BC - 1)
	; Destination last byte = Source + Delta
	PUSH	BC			; Save tail count
	LD	HL,(REPLACE_PTR_TEMP)
	LD	A,D			; A = S
	LD	E,A
	LD	D,0
	ADD	HL,DE			; HL = PTR + S
	ADD	HL,BC
	DEC	HL			; HL = Source last byte

	LD	A,(REPLACE_DELTA_TEMP)
	LD	E,A
	LD	D,0
	PUSH	HL
	ADD	HL,DE			; HL = HL + Delta (Destination last byte)
	EX	DE,HL			; DE = Destination last byte
	POP	HL			; HL = Source last byte
	POP	BC			; BC = tail count
	LDDR

	; Now copy R bytes from REPLACE_BUF to PTR
	CALL	ALR_COPY_REPLACE_STR
	JR	ALR_SUBST_DONE

ALR_SHRINK_LEN:
	; Case R < S (line shrinks):
	; Delta = S - R
	LD	A,D
	SUB	E
	LD	(REPLACE_DELTA_TEMP),A

	; Copy R bytes from REPLACE_BUF to PTR first
	PUSH	BC
	CALL	ALR_COPY_REPLACE_STR
	POP	BC			; BC = tail count

	; Move tail leftwards by Delta bytes:
	; Source = PTR + S
	; Destination = PTR + R
	LD	HL,(REPLACE_PTR_TEMP)
	LD	A,(SEARCH_LEN)
	LD	E,A
	LD	D,0
	ADD	HL,DE			; HL = Source (PTR + S)

	LD	DE,(REPLACE_PTR_TEMP)
	LD	A,(REPLACE_LEN)
	PUSH	HL
	LD	L,A
	LD	H,0
	ADD	HL,DE
	EX	DE,HL			; DE = Destination (PTR + R)
	POP	HL			; HL = Source (PTR + S)

	LDIR
	JR	ALR_SUBST_DONE

ALR_EQUAL_LEN:
	; Case R == S: simple overwrite of R bytes
	CALL	ALR_COPY_REPLACE_STR
	JR	ALR_SUBST_DONE

ALR_COPY_REPLACE_STR:
	LD	A,(REPLACE_LEN)
	OR	A
	RET	Z			; 0 bytes to copy
	LD	C,A
	LD	B,0
	LD	HL,REPLACE_BUF
	LD	DE,(REPLACE_PTR_TEMP)
	LDIR
	RET

ALR_SUBST_DONE:
	; Mark cache dirty
	CALL	MARK_CURRENT_LINE_DIRTY

	; Increment REPLACE_COUNT
	LD	HL,(REPLACE_COUNT)
	INC	HL
	LD	(REPLACE_COUNT),HL

	; Update CUR_COL = CUR_COL + R
	LD	A,(CUR_COL)
	LD	HL,REPLACE_LEN
	ADD	A,(HL)
	LD	(CUR_COL),A
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
	CALL	CHECKOUT_ACTIVE_LINE	; Ensures line is in ACTIVE_LINE_BUF
	CALL	GET_CUR_ROW_LEN		; HL = ACTIVE_LINE_BUF, DE = byte length, BC = visual length

	; 1. Check byte capacity against MAX_ACTIVE_LINE_STRIDE - 2 (1022)
	LD	HL,MAX_ACTIVE_LINE_STRIDE-2
	LD	A,E
	SUB	L
	LD	A,D
	SBC	A,H
	JR	NC,CHECK_BYTE_CAP_REPLACE ; DE >= 1022
	JR	CHECK_VISUAL_LIMIT

CHECK_BYTE_CAP_REPLACE:
	LD	A,(INSERT_MODE)
	OR	A
	RET	NZ			; Insert mode: buffer full
	LD	HL,(CUR_COL)
	LD	A,L
	SUB	E
	LD	A,H
	SBC	A,D
	RET	NC			; In overwrite mode at or past EOL: cannot append when full!

CHECK_VISUAL_LIMIT:
	; 2. Check visual line length limit (MAX_INPUT_LINE_CHARS = 1000)
	LD	HL,MAX_INPUT_LINE_CHARS
	LD	A,C
	SUB	L
	LD	A,B
	SBC	A,H
	JR	NC,CHECK_AT_EOL_REPLACE	; BC >= 1000

	; If inserting a Tab, check if tab expansion would push visual length > MAX_INPUT_LINE_CHARS
	LD	A,(CHAR_INSERT_TEMP)
	CP	KEY_TAB
	JR	NZ,LINE_LEN_OK
	CALL	CALC_VISUAL_COL		; HL = visual col at CUR_COL
	LD	A,L
	CALL	GET_TAB_SPACES
	DEC	A			; minus 1 for replaced char
	LD	E,A
	LD	D,0
	ADD	HL,DE			; projected visual length
	LD	DE,MAX_INPUT_LINE_CHARS
	LD	A,L
	SUB	E
	LD	A,H
	SBC	A,D
	RET	NC			; Tab would exceed limit!
	JR	LINE_LEN_OK

CHECK_AT_EOL_REPLACE:
	LD	A,(INSERT_MODE)
	OR	A
	RET	NZ			; Insert mode: cannot insert when full!
	LD	A,(CHAR_INSERT_TEMP)
	CP	KEY_TAB
	RET	Z			; Tab might expand: reject when full!
	LD	HL,(CUR_COL)
	LD	A,L
	SUB	E
	LD	A,H
	SBC	A,D
	RET	NC			; At or past EOL: cannot append when full!
	JR	LINE_LEN_OK		; Overwrite existing char in full line: allowed!

LINE_LEN_OK:
	LD	A,1
	LD	(ACTIVE_LINE_DIRTY),A
	LD	(DOC_MODIFIED),A
	LD	(NEED_LINE_RENDER),A

	; 4. Compare CUR_COL with line length (DE)
	LD	HL,(CUR_COL)
	LD	A,L
	SUB	E
	LD	A,H
	SBC	A,D
	JR	NC,DO_PAD_AND_APPEND	; CUR_COL >= DE: pad spaces and append

	; Check Insert vs Overwrite mode
	LD	A,(INSERT_MODE)
	OR	A
	JR	NZ,DO_SHIFT_AND_INSERT

	; Overwrite mode: replace character at ACTIVE_LINE_BUF + CUR_COL in place!
	LD	HL,ACTIVE_LINE_BUF
	LD	DE,(CUR_COL)
	ADD	HL,DE
	LD	A,(CHAR_INSERT_TEMP)
	LD	(HL),A
	JR	ADVANCE_INSERT_CURSOR

DO_SHIFT_AND_INSERT:
	; 5. If CUR_COL < length: shift characters from (ACTIVE_LINE_BUF + DE) down to (ACTIVE_LINE_BUF + CUR_COL)
	PUSH	DE			; Save line length DE
	LD	HL,ACTIVE_LINE_BUF
	ADD	HL,DE			; HL = ACTIVE_LINE_BUF + DE
	LD	D,H
	LD	E,L
	INC	DE			; DE = ACTIVE_LINE_BUF + DE + 1

	POP	BC			; BC = line length
	LD	HL,(CUR_COL)
	LD	A,C
	SUB	L
	LD	C,A
	LD	A,B
	SBC	A,H
	LD	B,A
	INC	BC			; BC = length - CUR_COL + 1

	LD	H,D
	LD	L,E
	DEC	HL			; HL = ACTIVE_LINE_BUF + length

	LDDR
	XOR	A
	LD	(DE),A			; Guarantee null terminator at new end of line

	; Now insert character at ACTIVE_LINE_BUF + CUR_COL
	LD	HL,ACTIVE_LINE_BUF
	LD	DE,(CUR_COL)
	ADD	HL,DE
	LD	A,(CHAR_INSERT_TEMP)
	LD	(HL),A
	JR	ADVANCE_INSERT_CURSOR

DO_PAD_AND_APPEND:
	; Pad from ACTIVE_LINE_BUF + DE up to ACTIVE_LINE_BUF + CUR_COL with spaces
	LD	HL,ACTIVE_LINE_BUF
	ADD	HL,DE			; HL = ACTIVE_LINE_BUF + DE (at old EOL)
	PUSH	HL			; Save old EOL pointer
PAD_SPACES_LOOP:
	LD	HL,(CUR_COL)
	LD	A,E
	CP	L
	JR	NZ,PAD_CONTINUE
	LD	A,D
	CP	H
	JR	Z,PAD_SPACES_DONE
PAD_CONTINUE:
	POP	HL
	LD	(HL),' '
	INC	HL
	PUSH	HL
	INC	DE
	JR	PAD_SPACES_LOOP

PAD_SPACES_DONE:
	POP	HL
	; HL is now at ACTIVE_LINE_BUF + CUR_COL
	LD	A,(CHAR_INSERT_TEMP)
	LD	(HL),A
	INC	HL
	XOR	A
	LD	(HL),A			; Null terminate new end of line

ADVANCE_INSERT_CURSOR:
	CALL	CALC_VISUAL_COL		; HL = visual col before advance
	LD	DE,MAX_INPUT_LINE_CHARS-1 ; 999
	LD	A,L
	CP	E
	JR	NZ,AIC_CHECK_BYTE
	LD	A,H
	CP	D
	RET	Z			; At column 999, do not advance cursor further!

AIC_CHECK_BYTE:
	LD	HL,(CUR_COL)
	LD	DE,MAX_ACTIVE_LINE_STRIDE-2
	LD	A,L
	SUB	E
	LD	A,H
	SBC	A,D
	RET	NC

	INC	HL
	LD	(CUR_COL),HL
	CALL	CALC_VISUAL_COL
	LD	(TARGET_COL),HL		; Sync sticky target visual column on typing
	RET

;------------------------------------------------------------------------------
; Character Deletion at (CUR_DOC_ROW, CUR_COL) - Backspace Handling
;------------------------------------------------------------------------------
DO_DELETE_CHAR:
	LD	HL,(CUR_COL)
	LD	A,H
	OR	L
	RET	Z			; At column 0, nothing to delete on line

	DEC	HL
	LD	(CUR_COL),HL
	CALL	CALC_VISUAL_COL
	LD	(TARGET_COL),HL		; Sync sticky target visual column on Backspace

	LD	A,1
	LD	(ACTIVE_LINE_DIRTY),A
	LD	(DOC_MODIFIED),A
	LD	(NEED_LINE_RENDER),A

	CALL	CHECKOUT_ACTIVE_LINE	; HL = ACTIVE_LINE_BUF
	LD	DE,(CUR_COL)
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
; Forward Character Deletion at (CUR_DOC_ROW, CUR_COL) - Delete Key Handling
;------------------------------------------------------------------------------
DO_DELETE_FORWARD:
	CALL	CHECKOUT_ACTIVE_LINE	; HL = ACTIVE_LINE_BUF
	LD	DE,(CUR_COL)
	ADD	HL,DE			; HL = character under cursor

	LD	A,(HL)
	OR	A
	JR	Z,DO_DEL_FWD_JOIN_NEXT	; At end of line: join NEXT line into current line!

	LD	A,1
	LD	(ACTIVE_LINE_DIRTY),A
	LD	(DOC_MODIFIED),A
	LD	(NEED_LINE_RENDER),A

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
	LD	A,1
	LD	(DOC_MODIFIED),A

	; 1. Free Line 0's slot chain
	LD	BC,0
	CALL	GET_LINE_SLOT		; HL = Line 0's slot ID
	CALL	FREE_LINE_CHAIN

	; 2. Decrement DOC_TOTAL_LINES
	LD	HL,(DOC_TOTAL_LINES)
	DEC	HL
	LD	(DOC_TOTAL_LINES),HL

	; 3. Shift line slots from index 1 down to index 0
	LD	A,H
	OR	L
	JR	Z,DO_BS_ROW0_NO_SHIFT
	LD	B,H
	LD	C,L			; BC = count of lines to shift (new DOC_TOTAL_LINES)
	LD	DE,0			; Destination line = 0
	LD	HL,1			; Source line = 1
	CALL	SHIFT_LINE_SLOTS_UP
DO_BS_ROW0_NO_SHIFT:

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
	RET	C			; If Carry set (combined length > 1000), do nothing

	; Join succeeded: HL = join column offset (original len of previous line)
	LD	(CUR_COL),HL		; Move cursor to join point
	LD	HL,(CUR_DOC_ROW)
	DEC	HL
	LD	(CUR_DOC_ROW),HL	; Move cursor to upper line
	CALL	CHECKOUT_ACTIVE_LINE
	CALL	CALC_VISUAL_COL
	LD	(TARGET_COL),HL

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
; Returns: Carry=0 on success, HL = join column (len of upper line); Carry=1 on failure
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
	CALL	COMMIT_ACTIVE_LINE
	CALL	FLUSH_DIRTY_CACHE

	; 1. Read upper line at (JOIN_DOC_LINE) into ACTIVE_LINE_BUF
	LD	BC,(JOIN_DOC_LINE)
	LD	DE,ACTIVE_LINE_BUF
	LD	HL,MAX_ACTIVE_LINE_STRIDE-2
	CALL	READ_FAR_LINE_MAX

	; Measure upper line length -> DE = len_1
	LD	HL,ACTIVE_LINE_BUF
	LD	DE,0
JOIN_MEASURE_L1:
	LD	A,(HL)
	OR	A
	JR	Z,JOIN_MEASURE_L1_DONE
	INC	HL
	INC	DE
	JR	JOIN_MEASURE_L1

JOIN_MEASURE_L1_DONE:
	LD	(JOIN_COL_SAVED),DE	; Save len_1 (16-bit)

	; 2. Read lower line at (JOIN_DOC_LINE + 1) into SPLIT_LINE_TEMP
	LD	BC,(JOIN_DOC_LINE)
	INC	BC
	LD	DE,SPLIT_LINE_TEMP
	LD	HL,MAX_ACTIVE_LINE_STRIDE-2
	CALL	READ_FAR_LINE_MAX

	; Measure lower line length -> BC = len_2
	LD	HL,SPLIT_LINE_TEMP
	LD	BC,0
JOIN_MEASURE_L2:
	LD	A,(HL)
	OR	A
	JR	Z,JOIN_MEASURE_L2_DONE
	INC	HL
	INC	BC
	JR	JOIN_MEASURE_L2

JOIN_MEASURE_L2_DONE:
	; Check if len_1 + len_2 <= MAX_INPUT_LINE_CHARS (1000)
	LD	HL,(JOIN_COL_SAVED)
	ADD	HL,BC			; HL = len_1 + len_2
	LD	DE,MAX_INPUT_LINE_CHARS
	LD	A,L
	SUB	E
	LD	A,H
	SBC	A,D
	JR	C,JOIN_CAPACITY_OK
	JR	Z,JOIN_CAPACITY_OK

	; Too long to join!
	SCF
	RET

JOIN_CAPACITY_OK:
	; 3. Append lower line (SPLIT_LINE_TEMP) to upper line (ACTIVE_LINE_BUF + len_1)
	LD	HL,ACTIVE_LINE_BUF
	LD	DE,(JOIN_COL_SAVED)
	ADD	HL,DE			; HL = pointer to null in ACTIVE_LINE_BUF
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
	LD	HL,ACTIVE_LINE_BUF
	CALL	WRITE_FAR_LINE

	; 5. Free lower line's slot chain (JOIN_DOC_LINE + 1)
	LD	HL,(JOIN_DOC_LINE)
	INC	HL			; HL = lower line index (P)
	LD	B,H
	LD	C,L
	CALL	GET_LINE_SLOT		; HL = freed slot ID
	CALL	FREE_LINE_CHAIN

	; 6. Decrement DOC_TOTAL_LINES
	LD	HL,(DOC_TOTAL_LINES)
	DEC	HL
	LD	(DOC_TOTAL_LINES),HL

	; 7. Shift line slots from JOIN_DOC_LINE + 2 upwards to JOIN_DOC_LINE + 1
	; Number of entries to shift: W = DOC_TOTAL_LINES - (JOIN_DOC_LINE + 1)
	LD	HL,(DOC_TOTAL_LINES)	; New total lines
	LD	DE,(JOIN_DOC_LINE)
	INC	DE			; DE = P = JOIN_DOC_LINE + 1
	AND	A
	SBC	HL,DE			; HL = W = DOC_TOTAL_LINES - P
	JR	Z,JOIN_SHIFT_DONE
	JR	C,JOIN_SHIFT_DONE

	LD	B,H
	LD	C,L			; BC = W
	LD	HL,(JOIN_DOC_LINE)
	INC	HL
	INC	HL			; HL = source line = P + 1
	; DE is already destination line = P
	CALL	SHIFT_LINE_SLOTS_UP

JOIN_SHIFT_DONE:
	CALL	INVALIDATE_ACTIVE_LINE
	CALL	RELOAD_CACHE_WINDOW_FORCE
	LD	A,1
	LD	(DOC_MODIFIED),A

	LD	HL,(JOIN_COL_SAVED)	; HL = join column offset
	OR	A			; Clear Carry = success!
	RET

;------------------------------------------------------------------------------
; Line Insertion & Splitting at (CUR_DOC_ROW, CUR_COL) - Enter Key Handling
;------------------------------------------------------------------------------
DO_INSERT_LINE:
	; Check max document lines (MAX_DOC_LINES_LIMIT)
	LD	HL,(DOC_TOTAL_LINES)
	LD	DE,(MAX_DOC_LINES_LIMIT)
	OR	A
	SBC	HL,DE
	JR	NC,INS_FAIL
	JR	INS_CAP_OK

INS_FAIL:
	CALL	SET_OOM_STATUS
	SCF
	RET

INS_CAP_OK:
	; Allocate slot for new line
	CALL	ALLOC_SLOT		; HL = new_slot_id (Carry = 1 on error)
	JR	C,INS_FAIL
	PUSH	HL			; Save new_slot_id

	; Ensure current line is checked out in ACTIVE_LINE_BUF
	CALL	CHECKOUT_ACTIVE_LINE

	; Split ACTIVE_LINE_BUF at CUR_COL:
	; Copy text from split point into SPLIT_LINE_TEMP
	LD	HL,ACTIVE_LINE_BUF
	LD	DE,(CUR_COL)
	ADD	HL,DE			; HL = split point in ACTIVE_LINE_BUF
	LD	DE,SPLIT_LINE_TEMP
SPLIT_COPY_LOOP:
	LD	A,(HL)
	LD	(DE),A
	LD	(HL),0			; Truncate current line at split point
	INC	HL
	INC	DE
	OR	A
	JR	NZ,SPLIT_COPY_LOOP

	; Truncated prefix is in ACTIVE_LINE_BUF. Mark dirty and commit it!
	LD	A,1
	LD	(ACTIVE_LINE_DIRTY),A
	LD	(DOC_MODIFIED),A
	CALL	COMMIT_ACTIVE_LINE

	; Shift line slots downwards from CUR_DOC_ROW + 1 to DOC_TOTAL_LINES - 1
	; Number of entries to shift: W = DOC_TOTAL_LINES - (CUR_DOC_ROW + 1)
	LD	HL,(DOC_TOTAL_LINES)
	LD	DE,(CUR_DOC_ROW)
	INC	DE			; DE = P = CUR_DOC_ROW + 1
	AND	A
	SBC	HL,DE			; HL = W = DOC_TOTAL_LINES - P
	JR	Z,NO_SLOT_SHIFT_DOWN
	JR	C,NO_SLOT_SHIFT_DOWN

	LD	B,H
	LD	C,L			; BC = W
	LD	HL,(CUR_DOC_ROW)
	INC	HL			; HL = source line = CUR_DOC_ROW + 1
	LD	DE,(CUR_DOC_ROW)
	INC	DE
	INC	DE			; DE = dest line = CUR_DOC_ROW + 2
	CALL	SHIFT_LINE_SLOTS_DOWN

NO_SLOT_SHIFT_DOWN:
	; Store new_slot_id into line table at CUR_DOC_ROW + 1
	POP	DE			; DE = new_slot_id
	LD	HL,(CUR_DOC_ROW)
	INC	HL
	LD	B,H
	LD	C,L			; BC = CUR_DOC_ROW + 1
	EX	DE,HL			; HL = new_slot_id
	CALL	SET_LINE_SLOT

	; Write split remainder (SPLIT_LINE_TEMP) to CUR_DOC_ROW + 1
	LD	HL,(CUR_DOC_ROW)
	INC	HL
	LD	B,H
	LD	C,L			; BC = CUR_DOC_ROW + 1
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
	LD	HL,0
	LD	(CUR_COL),HL
	LD	(TARGET_COL),HL

	; Invalidate active line and check out new CUR_DOC_ROW
	CALL	INVALIDATE_ACTIVE_LINE
	CALL	CHECKOUT_ACTIVE_LINE
	CALL	RELOAD_CACHE_WINDOW_FORCE

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
	LD	(DOC_MODIFIED),A
	AND	A
	RET

HBIOS_DETECT:
	PUSH	IX
	LD	B,0F8H			; CIOCNT
	LD	C,000H
	RST	08H
	POP	IX
	OR	A
	RET

;==============================================================================
; Configuration File Subsystem (SE.CFG)
; Reads, parses, searches, and saves persistent editor configuration.
; Search order: Local default drive first, then fallback to program drive.
; Save: Always writes to local default drive.
;==============================================================================

; LOAD_CONFIG: Load and parse SE.CFG
LOAD_CONFIG:
	; 1. Query current default drive via BDOS 25
	LD	C,25			; BDOS Get Current Drive
	CALL	BDOS_ENTRY
	LD	(CURRENT_DEFAULT_DRIVE),A
	XOR	A
	LD	(CONFIG_STATUS_FLAG),A
	LD	A,0FFH
	LD	(CONFIG_SOURCE_DRIVE),A

	; 2. Try to open SE.CFG on current default drive (drive byte = 0)
	CALL	INIT_CFG_FCB_LOCAL
	LD	DE,CFG_FCB
	LD	C,15			; BDOS Open File
	CALL	BDOS_ENTRY
	CP	0FFH
	JR	Z,LOAD_CFG_NOT_LOCAL

	; Local SE.CFG found! Read 128 bytes
	CALL	READ_CFG_RECORD
	JR	C,LOAD_CFG_NOT_LOCAL
	LD	A,1
	LD	(CONFIG_STATUS_FLAG),A
	LD	A,(CURRENT_DEFAULT_DRIVE)
	LD	(CONFIG_SOURCE_DRIVE),A
	CALL	PARSE_CONFIG_BUFFER
	RET

LOAD_CFG_NOT_LOCAL:
	; 3. Probe other logged-in drives for SE.COM
	CALL	PROBE_PROGRAM_DRIVE	; Returns A = drive index (0..15) if found, Carry = 0
	RET	C			; Not found on any other drive

	; SE.COM found on drive A! Try opening SE.CFG on that drive
	LD	(CONFIG_SOURCE_DRIVE),A	; Save program drive index (0..15)
	INC	A			; A = FCB drive code (1=A..16=P)
	CALL	INIT_CFG_FCB_DRIVE
	LD	DE,CFG_FCB
	LD	C,15			; BDOS Open File
	CALL	BDOS_ENTRY
	CP	0FFH
	JR	Z,LOAD_CFG_NOT_PROG	; No SE.CFG on program drive

	; SE.CFG found on program drive! Read 128 bytes
	CALL	READ_CFG_RECORD
	JR	C,LOAD_CFG_NOT_PROG
	LD	A,2
	LD	(CONFIG_STATUS_FLAG),A
	CALL	PARSE_CONFIG_BUFFER
	RET

LOAD_CFG_NOT_PROG:
	LD	A,0FFH
	LD	(CONFIG_SOURCE_DRIVE),A
	RET

; PROBE_PROGRAM_DRIVE: Search all logged-in drives for SE.COM (other than current drive)
; Returns: A = Drive index (0..15), Carry = 0 if found; Carry = 1 if not found
PROBE_PROGRAM_DRIVE:
	LD	C,24			; BDOS Return Login Vector
	CALL	BDOS_ENTRY		; HL = 16-bit vector (bit 0=A, bit 1=B...)
	LD	D,0			; D = drive index (0..15)
PPD_LOOP:
	LD	A,D
	CP	16
	JR	NC,PPD_NOT_FOUND

	SRL	H
	RR	L			; Carry = bit D of login vector
	JR	NC,PPD_NEXT		; Drive not logged in!

	; Skip if D == CURRENT_DEFAULT_DRIVE
	LD	A,(CURRENT_DEFAULT_DRIVE)
	CP	D
	JR	Z,PPD_NEXT

	; Drive D is valid and distinct! Probe for SE.COM on drive D+1
	PUSH	HL
	PUSH	DE
	LD	A,D
	INC	A			; 1=A, 2=B...
	CALL	INIT_COM_PROBE_FCB
	LD	DE,COM_PROBE_FCB
	LD	C,15			; BDOS Open File
	CALL	BDOS_ENTRY
	POP	DE
	POP	HL
	CP	0FFH
	JR	Z,PPD_NEXT		; SE.COM not on drive D

	; Found SE.COM on drive D! Close it
	PUSH	DE
	LD	DE,COM_PROBE_FCB
	LD	C,16			; BDOS Close File
	CALL	BDOS_ENTRY
	POP	DE
	LD	A,D			; A = drive index (0..15)
	OR	A			; Carry = 0
	RET

PPD_NEXT:
	INC	D
	JR	PPD_LOOP

PPD_NOT_FOUND:
	SCF				; Carry = 1
	RET

; READ_CFG_RECORD: Read up to 256 bytes from open CFG_FCB into CFG_IO_BUF
; Returns: Carry = 0 on success, Carry = 1 on read error
READ_CFG_RECORD:
	XOR	A
	LD	(CFG_FCB+32),A		; Clear record byte (cr)

	; Clear CFG_IO_BUF with 1AH EOF markers first
	LD	HL,CFG_IO_BUF
	LD	(HL),1AH
	LD	DE,CFG_IO_BUF+1
	LD	BC,255
	LDIR

	; Read record 0
	LD	DE,CFG_IO_BUF
	LD	C,26			; BDOS Set DMA
	CALL	BDOS_ENTRY

	LD	DE,CFG_FCB
	LD	C,20			; BDOS Read Next Record
	CALL	BDOS_ENTRY
	OR	A
	JR	NZ,RCR_ERR

	; Try reading record 1 (if available)
	LD	DE,CFG_IO_BUF+128
	LD	C,26			; BDOS Set DMA
	CALL	BDOS_ENTRY

	LD	DE,CFG_FCB
	LD	C,20			; BDOS Read Next Record
	CALL	BDOS_ENTRY
	; Ignore EOF on record 1 (fine if file has only 1 record)

	LD	DE,CFG_FCB
	LD	C,16			; BDOS Close File
	CALL	BDOS_ENTRY

	LD	DE,DEFAULT_DMA
	LD	C,26			; Restore BDOS DMA
	CALL	BDOS_ENTRY

	OR	A			; Carry = 0
	RET
RCR_ERR:
	LD	DE,CFG_FCB
	LD	C,16			; BDOS Close File
	CALL	BDOS_ENTRY

	LD	DE,DEFAULT_DMA
	LD	C,26			; Restore BDOS DMA
	CALL	BDOS_ENTRY

	SCF				; Carry = 1
	RET

; PARSE_CONFIG_BUFFER: Scan CFG_IO_BUF for configuration parameters
PARSE_CONFIG_BUFFER:
	LD	HL,CFG_IO_BUF
PCB_LINE_START:
	; Check if HL >= CFG_IO_BUF + 256
	LD	DE,CFG_IO_BUF + 256
	LD	A,L
	CP	E
	JR	NZ,PCB_NOT_END
	LD	A,H
	CP	D
	RET	Z			; End of buffer!
PCB_NOT_END:
	LD	A,(HL)
	CP	1AH			; EOF (^Z)
	RET	Z
	OR	A			; Null
	RET	Z

	; Skip leading whitespace (spaces / tabs / CR / LF)
	CP	' '
	JR	Z,PCB_SKIP_CHAR
	CP	9			; Tab
	JR	Z,PCB_SKIP_CHAR
	CP	13			; CR
	JR	Z,PCB_SKIP_CHAR
	CP	10			; LF
	JR	Z,PCB_SKIP_CHAR

	; Check if comment (# or ;)
	CP	'#'
	JR	Z,PCB_SKIP_LINE
	CP	';'
	JR	Z,PCB_SKIP_LINE
	JR	PCB_CHECK_KEYS

PCB_SKIP_CHAR:
	INC	HL
	JP	PCB_LINE_START

PCB_SKIP_LINE:
	; Advance HL until LF, CR, EOF, or HL >= CFG_IO_BUF + 256
	LD	DE,CFG_IO_BUF + 256
	LD	A,L
	CP	E
	JR	NZ,PSL_CHECK_CHR
	LD	A,H
	CP	D
	RET	Z
PSL_CHECK_CHR:
	LD	A,(HL)
	INC	HL
	CP	1AH
	RET	Z
	CP	10			; LF
	JP	Z,PCB_LINE_START
	JR	PCB_SKIP_LINE

PCB_CHECK_KEYS:
	; Check for "SCREEN"
	CALL	MATCH_KEY_SCREEN	; Returns Carry = 0 if matched, HL advanced past '=' and spaces
	JR	NC,PCB_SCREEN_VAL

	; Check for "RAMDRIVE" or "RAMDISK"
	CALL	MATCH_KEY_RAMDRIVE
	JR	NC,PCB_RAMDRIVE_VAL

	; Check for "TAB" or "TABS"
	CALL	MATCH_KEY_TAB
	JP	NC,PCB_TAB_VAL

	; Check for "LINES" or "LINE"
	CALL	MATCH_KEY_LINES
	JP	NC,PCB_LINES_VAL

	; Check for "MAXLINES" or "MAXLINE"
	CALL	MATCH_KEY_MAXLINES
	JP	NC,PCB_LINES_VAL

	; Check for "PLUGIN" or "PLUGINS"
	CALL	MATCH_KEY_PLUGIN
	JP	NC,PCB_PLUGIN_VAL

	JP	PCB_SKIP_LINE

PCB_SCREEN_VAL:
	; HL now points to value after '='
	; Check if starts with "80"
	LD	A,(HL)
	CP	'8'
	JR	NZ,PCB_CHECK_120
	INC	HL
	LD	A,(HL)
	CP	'0'
	JP	NZ,PCB_SKIP_LINE
	PUSH	HL
	CALL	SET_MODE_80X24
	POP	HL
	JP	PCB_SKIP_LINE

PCB_CHECK_120:
	CP	'1'
	JP	NZ,PCB_SKIP_LINE
	INC	HL
	LD	A,(HL)
	CP	'2'
	JP	NZ,PCB_SKIP_LINE
	INC	HL
	LD	A,(HL)
	CP	'0'
	JP	NZ,PCB_SKIP_LINE
	PUSH	HL
	CALL	SET_MODE_120X40
	POP	HL
	JP	PCB_SKIP_LINE

PCB_RAMDRIVE_VAL:
	; HL now points to value after '='
	LD	A,(HL)
	CALL	TO_UPPER
	CP	'H'			; HIBERNATE
	JR	Z,PCB_RAM_SET_HIB
	CP	'A'			; AUTO
	JR	Z,PCB_RAM_SET_HIB
	CP	'2'
	JR	Z,PCB_RAM_SET_HIB
	CP	'O'			; ON, OFF, or OVERWRITE?
	JR	NZ,PCB_RAM_CHECK_YES
	INC	HL
	LD	A,(HL)
	CALL	TO_UPPER
	CP	'N'			; ON
	JR	Z,PCB_RAM_SET_ON
	CP	'V'			; OVERWRITE
	JR	Z,PCB_RAM_SET_ON
	CP	'F'			; OFF
	JR	Z,PCB_RAM_SET_OFF
	JP	PCB_SKIP_LINE

PCB_RAM_CHECK_YES:
	CP	'Y'			; YES
	JR	Z,PCB_RAM_SET_ON
	CP	'1'
	JR	Z,PCB_RAM_SET_ON
	CP	'E'			; ENABLED
	JR	Z,PCB_RAM_SET_ON
	CP	'T'			; TRUE
	JR	Z,PCB_RAM_SET_ON
	CP	'M'			; MAXRAM
	JR	Z,PCB_RAM_SET_ON

	CP	'N'			; NO
	JR	Z,PCB_RAM_SET_OFF
	CP	'0'
	JR	Z,PCB_RAM_SET_OFF
	CP	'P'			; PRESERVE / PROTECTED
	JR	Z,PCB_RAM_SET_OFF
	CP	'F'			; FALSE
	JR	Z,PCB_RAM_SET_OFF
	JP	PCB_SKIP_LINE

PCB_RAM_SET_HIB:
	LD	A,RAMDRV_MODE_HIBERNATE
	LD	(CFG_RAMDRIVE_FLAG),A
	JP	PCB_SKIP_LINE

PCB_RAM_SET_ON:
	LD	A,RAMDRV_MODE_ENABLED
	LD	(CFG_RAMDRIVE_FLAG),A
	JP	PCB_SKIP_LINE

PCB_RAM_SET_OFF:
	XOR	A
	LD	(CFG_RAMDRIVE_FLAG),A
	JP	PCB_SKIP_LINE

PCB_TAB_VAL:
	; HL now points to value after '='
	LD	A,(HL)
	CP	'4'
	JR	NZ,PCB_TAB_CHK_8
	LD	A,4
	LD	(CFG_TAB_WIDTH),A
	LD	A,3
	LD	(CFG_TAB_MASK),A
	JP	PCB_SKIP_LINE

PCB_TAB_CHK_8:
	CP	'8'
	JP	NZ,PCB_SKIP_LINE
	LD	A,8
	LD	(CFG_TAB_WIDTH),A
	LD	A,7
	LD	(CFG_TAB_MASK),A
	JP	PCB_SKIP_LINE

PCB_LINES_VAL:
	; HL now points to value after '='
PCB_LV_WS:
	LD	A,(HL)
	CP	' '
	JR	Z,PCB_LV_WS_INC
	CP	9
	JR	NZ,PCB_LV_CHECK
PCB_LV_WS_INC:
	INC	HL
	JR	PCB_LV_WS
PCB_LV_CHECK:
	LD	A,(HL)
	CP	'3'			; 32K or 32768 or 32
	JR	Z,PCB_LV_SET_32K
	CP	'1'			; 16K or 16384 or 16
	JR	Z,PCB_LV_SET_16K
	JP	PCB_SKIP_LINE

PCB_LV_SET_32K:
	LD	A,1
	LD	(CFG_LINES_MODE),A
	JP	PCB_SKIP_LINE

PCB_LV_SET_16K:
	XOR	A
	LD	(CFG_LINES_MODE),A
	JP	PCB_SKIP_LINE

PCB_PLUGIN_VAL:
	; HL now points to value after '='
PCB_PV_WS:
	LD	A,(HL)
	CP	' '
	JR	Z,PCB_PV_WS_INC
	CP	9
	JR	NZ,PCB_PV_CHECK
PCB_PV_WS_INC:
	INC	HL
	JR	PCB_PV_WS
PCB_PV_CHECK:
	LD	A,(HL)
	CALL	TO_UPPER
	CP	'A'			; AUTOLOAD / AUTO
	JR	Z,PCB_PLUG_SET_AUTO
	CP	'Y'			; YES
	JR	Z,PCB_PLUG_SET_AUTO
	CP	'1'			; 1
	JR	Z,PCB_PLUG_SET_AUTO
	CP	'E'			; ENABLE / ENABLED
	JR	Z,PCB_PLUG_SET_AUTO
	CP	'T'			; TRUE
	JR	Z,PCB_PLUG_SET_AUTO

	CP	'2'			; 2
	JR	Z,PCB_PLUG_SET_ONDEMAND
	CP	'M'			; MANUAL
	JR	Z,PCB_PLUG_SET_ONDEMAND

	CP	'N'			; NO / NONE
	JR	Z,PCB_PLUG_SET_OFF
	CP	'0'			; 0
	JR	Z,PCB_PLUG_SET_OFF
	CP	'F'			; FALSE
	JR	Z,PCB_PLUG_SET_OFF

	CP	'D'			; DEMAND vs DISABLED
	JR	Z,PCB_PV_CHK_D
	CP	'O'			; ONDEMAND vs ON vs OFF
	JR	Z,PCB_PV_CHK_O
	JP	PCB_SKIP_LINE

PCB_PV_CHK_D:
	INC	HL
	LD	A,(HL)
	CALL	TO_UPPER
	CP	'E'			; DEMAND
	JR	Z,PCB_PLUG_SET_ONDEMAND
	JR	PCB_PLUG_SET_OFF	; DISABLED / DISABLE / other

PCB_PV_CHK_O:
	INC	HL
	LD	A,(HL)
	CALL	TO_UPPER
	CP	'F'			; OFF
	JR	Z,PCB_PLUG_SET_OFF
	CP	'N'			; ON or ONDEMAND?
	JP	NZ,PCB_SKIP_LINE
	INC	HL
	LD	A,(HL)
	CALL	TO_UPPER
	CP	'D'			; ONDEMAND
	JR	Z,PCB_PLUG_SET_ONDEMAND
	JR	PCB_PLUG_SET_AUTO	; ON

PCB_PLUG_SET_AUTO:
	LD	A,PLUGIN_MODE_AUTOLOAD
	LD	(CFG_AUTOLOAD_PLUGIN_MGR),A
	JP	PCB_SKIP_LINE

PCB_PLUG_SET_ONDEMAND:
	LD	A,PLUGIN_MODE_ONDEMAND
	LD	(CFG_AUTOLOAD_PLUGIN_MGR),A
	JP	PCB_SKIP_LINE

PCB_PLUG_SET_OFF:
	XOR	A
	LD	(CFG_AUTOLOAD_PLUGIN_MGR),A
	JP	PCB_SKIP_LINE


; MATCH_KEY_SCREEN: Compares text at (HL) with "SCREEN" (case-insensitive)
; Output: Carry = 0 if matched, HL advanced past '=' and trailing spaces
;         Carry = 1 if no match, HL restored to starting position
MATCH_KEY_SCREEN:
	PUSH	HL
	LD	DE,STR_KEY_SCREEN_NAME
	LD	B,6
MKS_LOOP:
	LD	A,(HL)
	CALL	TO_UPPER
	LD	C,A
	LD	A,(DE)
	CP	C
	JR	NZ,MKS_FAIL
	INC	HL
	INC	DE
	DJNZ	MKS_LOOP

	; Skip optional spaces before '='
MKS_WS1:
	LD	A,(HL)
	CP	' '
	JR	Z,MKS_WS1_INC
	CP	9
	JR	NZ,MKS_CHECK_EQ
MKS_WS1_INC:
	INC	HL
	JR	MKS_WS1

MKS_CHECK_EQ:
	CP	'='
	JR	NZ,MKS_FAIL
	INC	HL			; Skip '='

	; Skip optional spaces after '='
MKS_WS2:
	LD	A,(HL)
	CP	' '
	JR	Z,MKS_WS2_INC
	CP	9
	JR	NZ,MKS_OK
MKS_WS2_INC:
	INC	HL
	JR	MKS_WS2

MKS_OK:
	POP	AF			; Discard saved HL
	OR	A			; Carry = 0
	RET

MKS_FAIL:
	POP	HL			; Restore HL
	SCF				; Carry = 1
	RET

; MATCH_KEY_RAMDRIVE: Compares text at (HL) with "RAMD" prefix (case-insensitive)
; Output: Carry = 0 if matched, HL advanced past '=' and trailing spaces
;         Carry = 1 if no match, HL restored to starting position
MATCH_KEY_RAMDRIVE:
	PUSH	HL
	LD	DE,STR_KEY_RAMD_NAME
	LD	B,4
MKR_LOOP:
	LD	A,(HL)
	CALL	TO_UPPER
	LD	C,A
	LD	A,(DE)
	CP	C
	JR	NZ,MKR_FAIL
	INC	HL
	INC	DE
	DJNZ	MKR_LOOP

	; Skip remaining key characters until '=' or whitespace
MKR_SKIP_KEY:
	LD	A,(HL)
	CP	' '
	JR	Z,MKR_WS1
	CP	9
	JR	Z,MKR_WS1
	CP	'='
	JR	Z,MKR_GOT_EQ
	CP	13
	JR	Z,MKR_FAIL
	CP	10
	JR	Z,MKR_FAIL
	CP	1AH
	JR	Z,MKR_FAIL
	INC	HL
	JR	MKR_SKIP_KEY

MKR_WS1:
	LD	A,(HL)
	CP	' '
	JR	Z,MKR_WS1_INC
	CP	9
	JR	NZ,MKR_CHECK_EQ
MKR_WS1_INC:
	INC	HL
	JR	MKR_WS1

MKR_CHECK_EQ:
	CP	'='
	JR	NZ,MKR_FAIL
MKR_GOT_EQ:
	INC	HL			; Skip '='

	; Skip optional spaces after '='
MKR_WS2:
	LD	A,(HL)
	CP	' '
	JR	Z,MKR_WS2_INC
	CP	9
	JR	NZ,MKR_OK
MKR_WS2_INC:
	INC	HL
	JR	MKR_WS2

MKR_OK:
	POP	AF			; Discard saved HL
	OR	A			; Carry = 0
	RET

MKR_FAIL:
	POP	HL
	SCF				; Carry = 1
	RET

; MATCH_KEY_TAB: Compares text at (HL) with "TAB" prefix (case-insensitive)
; Matches "TAB", "TABS", "TABWIDTH"
; Output: Carry = 0 if matched, HL advanced past '=' and trailing spaces
;         Carry = 1 if no match, HL restored to starting position
MATCH_KEY_TAB:
	PUSH	HL
	LD	DE,STR_KEY_TAB_NAME
	LD	B,3
MKT_LOOP:
	LD	A,(HL)
	CALL	TO_UPPER
	LD	C,A
	LD	A,(DE)
	CP	C
	JR	NZ,MKT_FAIL
	INC	HL
	INC	DE
	DJNZ	MKT_LOOP

	; Skip remaining key characters until '=' or whitespace
MKT_SKIP_KEY:
	LD	A,(HL)
	CP	' '
	JR	Z,MKT_WS1
	CP	9
	JR	Z,MKT_WS1
	CP	'='
	JR	Z,MKT_GOT_EQ
	CP	13
	JR	Z,MKT_FAIL
	CP	10
	JR	Z,MKT_FAIL
	CP	1AH
	JR	Z,MKT_FAIL
	INC	HL
	JR	MKT_SKIP_KEY

MKT_WS1:
	LD	A,(HL)
	CP	' '
	JR	Z,MKT_WS1_INC
	CP	9
	JR	NZ,MKT_CHECK_EQ
MKT_WS1_INC:
	INC	HL
	JR	MKT_WS1

MKT_CHECK_EQ:
	CP	'='
	JR	NZ,MKT_FAIL
MKT_GOT_EQ:
	INC	HL			; Skip '='

	; Skip optional spaces after '='
MKT_WS2:
	LD	A,(HL)
	CP	' '
	JR	Z,MKT_WS2_INC
	CP	9
	JR	NZ,MKT_OK
MKT_WS2_INC:
	INC	HL
	JR	MKT_WS2

MKT_OK:
	POP	AF			; Discard saved HL
	OR	A			; Carry = 0
	RET

MKT_FAIL:
	POP	HL
	SCF				; Carry = 1
	RET

; MATCH_KEY_LINES: Compares text at (HL) with "LINE" prefix (case-insensitive)
MATCH_KEY_LINES:
	PUSH	HL
	LD	DE,STR_KEY_LINES_NAME
	LD	B,4
	JR	MKL_SHARED_LOOP

; MATCH_KEY_MAXLINES: Compares text at (HL) with "MAXLINE" prefix (case-insensitive)
MATCH_KEY_MAXLINES:
	PUSH	HL
	LD	DE,STR_KEY_MAXLINES_NAME
	LD	B,7
	JR	MKL_SHARED_LOOP

; MATCH_KEY_PLUGIN: Compare text at (HL) with "PLUGIN" (case-insensitive)
MATCH_KEY_PLUGIN:
	PUSH	HL
	LD	DE,STR_KEY_PLUGIN_NAME
	LD	B,6
	JR	MKL_SHARED_LOOP
MKL_SHARED_LOOP:
MKL_LOOP:
	LD	A,(HL)
	CALL	TO_UPPER
	LD	C,A
	LD	A,(DE)
	CP	C
	JR	NZ,MKL_FAIL
	INC	HL
	INC	DE
	DJNZ	MKL_LOOP

	; Skip remaining key characters until '=' or whitespace
MKL_SKIP_KEY:
	LD	A,(HL)
	CP	' '
	JR	Z,MKL_WS1
	CP	9
	JR	Z,MKL_WS1
	CP	'='
	JR	Z,MKL_GOT_EQ
	CP	13
	JR	Z,MKL_FAIL
	CP	10
	JR	Z,MKL_FAIL
	CP	1AH
	JR	Z,MKL_FAIL
	INC	HL
	JR	MKL_SKIP_KEY

MKL_WS1:
	LD	A,(HL)
	CP	' '
	JR	Z,MKL_WS1_INC
	CP	9
	JR	NZ,MKL_CHECK_EQ
MKL_WS1_INC:
	INC	HL
	JR	MKL_WS1

MKL_CHECK_EQ:
	CP	'='
	JR	NZ,MKL_FAIL
MKL_GOT_EQ:
	INC	HL			; Skip '='

	; Skip optional spaces after '='
MKL_WS2:
	LD	A,(HL)
	CP	' '
	JR	Z,MKL_WS2_INC
	CP	9
	JR	NZ,MKL_OK
MKL_WS2_INC:
	INC	HL
	JR	MKL_WS2

MKL_OK:
	POP	AF			; Discard saved HL
	OR	A			; Carry = 0
	RET

MKL_FAIL:
	POP	HL
	SCF				; Carry = 1
	RET

; SAVE_CONFIG: Save current editor configuration to SE.CFG on current drive
SAVE_CONFIG:
	; Fill CFG_IO_BUF with 256 bytes of 0x1A (EOF)
	LD	HL,CFG_IO_BUF
	LD	(HL),1AH
	LD	DE,CFG_IO_BUF+1
	LD	BC,255
	LDIR

	; Write header to CFG_IO_BUF
	LD	HL,STR_CFG_HDR
	LD	DE,CFG_IO_BUF
	CALL	SC_APPEND_STRING

	; Write "SCREEN="
	LD	HL,STR_KEY_SCREEN_FULL
	CALL	SC_APPEND_STRING

	; Write value: "120x40" or "80x24" + CRLF
	LD	A,(SCREEN_MODE)
	CP	MODE_120X40
	JR	NZ,SC_VAL_80
	LD	HL,STR_VAL_120X40
	JR	SC_PUT_SCREEN
SC_VAL_80:
	LD	HL,STR_VAL_80X24
SC_PUT_SCREEN:
	CALL	SC_APPEND_STRING

	; Write "RAMDRIVE="
	LD	HL,STR_KEY_RAMDRIVE_FULL
	CALL	SC_APPEND_STRING

	; Write value: "PRESERVE\r\n", "HIBERNATE\r\n", or "OVERWRITE\r\n"
	LD	A,(CFG_RAMDRIVE_FLAG)
	CP	RAMDRV_MODE_HIBERNATE
	JR	Z,SC_RAM_VAL_HIB
	CP	RAMDRV_MODE_ENABLED
	JR	Z,SC_RAM_VAL_ON
	LD	HL,STR_VAL_RAMDRIVE_OFF
	JR	SC_PUT_RAM
SC_RAM_VAL_HIB:
	LD	HL,STR_VAL_RAMDRIVE_HIB
	JR	SC_PUT_RAM
SC_RAM_VAL_ON:
	LD	HL,STR_VAL_RAMDRIVE_ON
SC_PUT_RAM:
	CALL	SC_APPEND_STRING

	; Write "TAB="
	LD	HL,STR_KEY_TAB_FULL
	CALL	SC_APPEND_STRING

	; Write value: "8" or "4" + CRLF
	LD	A,(CFG_TAB_WIDTH)
	CP	4
	JR	Z,SC_TAB_VAL_4
	LD	HL,STR_VAL_TAB_8
	JR	SC_PUT_TAB
SC_TAB_VAL_4:
	LD	HL,STR_VAL_TAB_4
SC_PUT_TAB:
	CALL	SC_APPEND_STRING

	; Write "LINES="
	LD	HL,STR_KEY_LINES_FULL
	CALL	SC_APPEND_STRING

	; Write value: "32K\r\n" or "16K\r\n"
	LD	A,(CFG_LINES_MODE)
	CP	1
	JR	Z,SC_LINES_VAL_32K
	LD	HL,STR_VAL_LINES_16K
	JR	SC_PUT_LINES
SC_LINES_VAL_32K:
	LD	HL,STR_VAL_LINES_32K
SC_PUT_LINES:
	CALL	SC_APPEND_STRING

	; Write "PLUGIN="
	LD	HL,STR_KEY_PLUGIN_FULL
	CALL	SC_APPEND_STRING

	; Write value: "AUTOLOAD\r\n", "ONDEMAND\r\n", or "DISABLED\r\n"
	LD	A,(CFG_AUTOLOAD_PLUGIN_MGR)
	CP	PLUGIN_MODE_AUTOLOAD
	JR	Z,SC_PLUG_VAL_AUTO
	CP	PLUGIN_MODE_ONDEMAND
	JR	Z,SC_PLUG_VAL_ONDEMAND
	LD	HL,STR_VAL_PLUG_DIS
	JR	SC_PUT_PLUG
SC_PLUG_VAL_ONDEMAND:
	LD	HL,STR_VAL_PLUG_ONDEMAND
	JR	SC_PUT_PLUG
SC_PLUG_VAL_AUTO:
	LD	HL,STR_VAL_PLUG_AUTO
SC_PUT_PLUG:
	CALL	SC_APPEND_STRING

	; Set BDOS DMA to CFG_IO_BUF (record 0)
	LD	DE,CFG_IO_BUF
	LD	C,26
	CALL	BDOS_ENTRY

	; Prepare local CFG_FCB
	CALL	INIT_CFG_FCB_LOCAL

	; Delete existing SE.CFG on current drive (BDOS 19)
	LD	DE,CFG_FCB
	LD	C,19
	CALL	BDOS_ENTRY

	; Prepare local CFG_FCB again
	CALL	INIT_CFG_FCB_LOCAL

	; Make file on current drive (BDOS 22)
	LD	DE,CFG_FCB
	LD	C,22
	CALL	BDOS_ENTRY
	CP	0FFH
	JR	Z,SC_ERR

	; Write first 128-byte record (BDOS 21)
	LD	DE,CFG_FCB
	LD	C,21
	CALL	BDOS_ENTRY
	OR	A
	JR	NZ,SC_ERR_CLOSE

	; Set BDOS DMA to CFG_IO_BUF + 128 (record 1)
	LD	DE,CFG_IO_BUF + 128
	LD	C,26
	CALL	BDOS_ENTRY

	; Write second 128-byte record (BDOS 21)
	LD	DE,CFG_FCB
	LD	C,21
	CALL	BDOS_ENTRY
	OR	A
	JR	NZ,SC_ERR_CLOSE

	; Close file (BDOS 16)
	LD	DE,CFG_FCB
	LD	C,16
	CALL	BDOS_ENTRY
	CP	0FFH
	JR	Z,SC_ERR

	; Restore DMA
	LD	DE,DEFAULT_DMA
	LD	C,26
	CALL	BDOS_ENTRY

	; Success!
	LD	A,3
	LD	(CONFIG_STATUS_FLAG),A
	LD	A,(CURRENT_DEFAULT_DRIVE)
	LD	(CONFIG_SOURCE_DRIVE),A
	RET

SC_ERR_CLOSE:
	LD	DE,CFG_FCB
	LD	C,16
	CALL	BDOS_ENTRY
SC_ERR:
	LD	DE,DEFAULT_DMA
	LD	C,26
	CALL	BDOS_ENTRY
	LD	A,4
	LD	(CONFIG_STATUS_FLAG),A
	RET

SC_APPEND_STRING:
	LD	A,(HL)
	OR	A
	RET	Z
	LD	(DE),A
	INC	HL
	INC	DE
	JR	SC_APPEND_STRING

INIT_CFG_FCB_LOCAL:
	XOR	A
	JR	INIT_CFG_FCB_COMMON

INIT_CFG_FCB_DRIVE:
	; A = drive code (1=A, 2=B...)
INIT_CFG_FCB_COMMON:
	LD	HL,CFG_FCB
	LD	(HL),A			; Drive byte
	INC	HL
	LD	(HL),'S'
	INC	HL
	LD	(HL),'E'
	INC	HL
	LD	(HL),' '
	INC	HL
	LD	(HL),' '
	INC	HL
	LD	(HL),' '
	INC	HL
	LD	(HL),' '
	INC	HL
	LD	(HL),' '
	INC	HL
	LD	(HL),' '
	INC	HL
	LD	(HL),'C'
	INC	HL
	LD	(HL),'F'
	INC	HL
	LD	(HL),'G'
	INC	HL
	LD	B,24
INIT_CFG_ZERO:
	LD	(HL),0
	INC	HL
	DJNZ	INIT_CFG_ZERO
	RET

INIT_COM_PROBE_FCB:
	; A = drive code (1=A, 2=B...)
	LD	HL,COM_PROBE_FCB
	LD	(HL),A
	INC	HL
	LD	(HL),'S'
	INC	HL
	LD	(HL),'E'
	INC	HL
	LD	(HL),' '
	INC	HL
	LD	(HL),' '
	INC	HL
	LD	(HL),' '
	INC	HL
	LD	(HL),' '
	INC	HL
	LD	(HL),' '
	INC	HL
	LD	(HL),' '
	INC	HL
	LD	(HL),'C'
	INC	HL
	LD	(HL),'O'
	INC	HL
	LD	(HL),'M'
	INC	HL
	LD	B,24
INIT_COM_ZERO:
	LD	(HL),0
	INC	HL
	DJNZ	INIT_COM_ZERO
	RET

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
	LD	HL,(DOC_TOTAL_LINES)
	LD	A,H
	OR	L
	JP	Z,MAIN_LOOP

	; Scan PLUGIN_REGISTRY for "BEAUTIFY"
	LD	B,0
DO_CY_FIND_LOOP:
	PUSH	BC
	CALL	GET_REGISTRY_ENTRY_PTR
	POP	BC
	; Check if slot is loaded (offset 22: SLOT_STATE != 0)
	PUSH	HL
	LD	DE,22
	ADD	HL,DE
	LD	A,(HL)
	POP	HL
	OR	A
	JR	Z,DO_CY_NEXT_SLOT

	; Compare plugin name at (HL) with "BEAUTIFY"
	PUSH	BC
	PUSH	HL
	LD	DE,STR_NAME_BEAUTIFY
	CALL	COMPARE_PLUGIN_NAME
	POP	HL
	POP	BC
	JR	Z,DO_CY_FOUND

DO_CY_NEXT_SLOT:
	INC	B
	LD	A,B
	CP	PLUGIN_MAX_SLOTS
	JR	NZ,DO_CY_FIND_LOOP

	; Not loaded in registry: dynamically load BEAUTIFY from disk
	LD	DE,STR_NAME_BEAUTIFY
	CALL	LOAD_PLUGIN_BY_NAME
	JR	NC,DO_CY_LOADED_OK

	; Failed to load BEAUTIFY.PRL: report missing on status bar
	LD	DE,STR_MSG_PLUG_MISSING
	CALL	HOST_SET_STATUS_MSG
	CALL	RENDER_STATUS_BAR
	CALL	LOCATE_CURSOR
	JP	MAIN_LOOP

DO_CY_LOADED_OK:
	LD	A,(PLUGIN_CUR_SLOT)
	JR	DO_CY_EXEC

DO_CY_FOUND:
	LD	A,B

DO_CY_EXEC:
	PUSH	AF
	CALL	CHECKOUT_ACTIVE_LINE
	CALL	GET_CUR_ROW_LEN
	LD	(ACTIVE_LINE_LEN),DE
	CALL	SAVE_EDITOR_PLUGIN_STATE
	CALL	FLUSH_DIRTY_CACHE
	LD	HL,0FFFFH
	LD	(CACHE_START_ROW),HL
	POP	AF
	CALL	EXEC_PLUGIN_SLOT
	; Clear block mode after beautify
	XOR	A
	LD	(BLOCK_ACTIVE),A
	; Clear plugin status msg ptr so normal status bar is restored
	LD	HL,0
	LD	(PLUGIN_STATUS_MSG_PTR),HL
	CALL	INVALIDATE_ACTIVE_LINE
	CALL	RESTORE_EDITOR_PLUGIN_STATE
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	CALL	LOCATE_CURSOR
	JP	MAIN_LOOP

COMPARE_PLUGIN_NAME:
	LD	A,(DE)
	CP	(HL)
	RET	NZ
	OR	A
	RET	Z
	INC	HL
	INC	DE
	JR	COMPARE_PLUGIN_NAME


;==============================================================================
; RAM Drive Hibernation & Restoration Subsystem
; Dumps RomWBW MD0:0 physical banks (0x81..0x88, 256KB) to RAMDRV.IMG on startup
; and restores them upon exit, unlocking 12 Far RAM banks for the editor buffer.
;==============================================================================

;------------------------------------------------------------------------------
; DETECT_RAMDRIVE_LETTER:
; Detects RomWBW CBIOS RAM drive letter dynamically by inspecting DRVMAP
; and querying HBIOS BF_DIODEVICE (0x17) for unit MD0 (RAM disk, type 0,
; unit 0).
; Output:
;   A = 0-based drive index (0=A, 1=B, ..., 0xFF = none)
;   RAMDRIVE_DRIVE_NUM = 0-based drive index or 0xFF
;   RAMDRIVE_DRIVE_CHAR = drive letter ('A', 'B', ...) or '?'
;   STR_MSG_HIB_DRV_CHAR and STR_MSG_HIB_FILE_CHAR updated with drive letter
;   Carry = 0 if RAM drive detected, Carry = 1 if none / not RomWBW
;------------------------------------------------------------------------------
DETECT_RAMDRIVE_LETTER:
	LD	A,0FFH
	LD	(RAMDRIVE_DRIVE_NUM),A
	LD	A,'?'
	LD	(RAMDRIVE_DRIVE_CHAR),A

	; Check HBIOS presence
	CALL	HBIOS_DETECT
	JP	NZ,DRL_NOT_FOUND

	; Check CP/M version: CP/M 3.x uses BDOS 50 (Direct BIOS Call) + DRVTBL
	LD	A,(CPM_VERSION_ID)
	CP	030H
	JP	NC,DRL_CPM3

	; Check RomWBW CBIOS page zero stamp at 0x0040 ('W') and 0x0041 (~'W' = 0xA8)
	LD	HL,0040H
	LD	A,(HL)
	CP	'W'
	JP	NZ,DRL_NOT_FOUND
	INC	HL
	LD	A,(HL)
	CP	0A8H			; ~'W'
	JP	NZ,DRL_NOT_FOUND

	; Word at 0x0044 is pointer to CBIOS extension (CBX)
	LD	HL,(0044H)
	; DRVMAPADR is at CBX + 2
	INC	HL
	INC	HL
	LD	E,(HL)
	INC	HL
	LD	D,(HL)			; DE = DRVMAPADR
	LD	A,D
	OR	E
	JP	Z,DRL_NOT_FOUND

	; DRVCNT is at DRVMAPADR - 1
	EX	DE,HL			; HL = DRVMAPADR
	DEC	HL
	LD	A,(HL)			; A = DRVCNT
	INC	HL			; HL = DRVMAPADR
	OR	A
	JP	Z,DRL_NOT_FOUND
	CP	17
	JP	NC,DRL_NOT_FOUND

	LD	B,A			; B = loop counter (DRVCNT)
	LD	C,0			; C = CP/M drive index (0 = A:, 1 = B:, ...)

DRL_LOOP:
	LD	A,(HL)			; A = HBIOS Disk Unit (or 0xFF if unassigned)
	INC	HL
	INC	HL
	INC	HL
	INC	HL
	CP	0FFH
	JR	Z,DRL_NEXT

	PUSH	BC
	PUSH	HL
	LD	C,A			; C = HBIOS Disk Unit
	LD	B,17H			; BF_DIODEVICE (0x17)
	PUSH	IX
	RST	08H			; D = Device Type, E = Phys Unit, C = Attributes
	POP	IX
	LD	A,D
	CP	00H			; DIODEV_MD (0x00)
	JR	NZ,DRL_NOT_MD
	LD	A,E
	CP	00H			; Physical Unit 0 = MD0 (RAM disk)
	JR	NZ,DRL_NOT_MD

	; Match found!
	POP	HL
	POP	BC
	LD	A,C			; A = CP/M drive index (0 = A:, 1 = B:, ...)
	LD	(RAMDRIVE_DRIVE_NUM),A
	ADD	A,'A'
	CALL	SET_RAMDRIVE_CHAR
	LD	A,C
	OR	A			; Carry = 0
	RET

DRL_NOT_MD:
	POP	HL
	POP	BC

DRL_NEXT:
	INC	C
	DJNZ	DRL_LOOP
	JP	DRL_NOT_FOUND

DRL_CPM3:
	; Call BDOS 50: BIOS 22 (DRVTBL)
	LD	A,22
	LD	(CPM3_BIOSPB_FUNC),A
	XOR	A
	LD	(CPM3_BIOSPB_A),A
	LD	HL,0
	LD	(CPM3_BIOSPB_BC),HL
	LD	(CPM3_BIOSPB_DE),HL
	LD	(CPM3_BIOSPB_HL),HL
	LD	DE,CPM3_BIOSPB
	LD	C,50
	CALL	BDOS_ENTRY
	; HL = address of DRVTBL (16-word array) in common memory
	LD	A,H
	OR	L
	JR	Z,DRL_NOT_FOUND
	LD	(CPM3_DRVTBL_PTR),HL

	; Query System Bank ID from HBIOS (SYSGET BNKINFO: B=0xF8, C=0xF2)
	PUSH	IX
	LD	B,0F8H
	LD	C,0F2H
	RST	08H
	POP	IX
	; D = BIOS Bank, E = User/System Bank (typically 0x8E)
	LD	A,E
	LD	(CPM3_SYS_BANK),A

	; Query User Bank ID from HBIOS (SYSGETBNK: B=0xF3)
	PUSH	IX
	LD	B,0F3H
	RST	08H
	POP	IX
	LD	A,C
	LD	(CPM_USER_BANK),A

	; Iterate through all 16 drive entries in DRVTBL
	LD	HL,(CPM3_DRVTBL_PTR)
	LD	B,16			; 16 drives A..P
	LD	C,0			; CP/M drive index (0 = A:, 1 = B:, ...)

DRL_CPM3_LOOP:
	PUSH	BC
	PUSH	HL

	; Read 16-bit DPH pointer from (HL)
	LD	E,(HL)
	INC	HL
	LD	D,(HL)			; DE = DPH address
	LD	A,D
	OR	E
	JP	Z,DRL_CPM3_NEXT		; Unassigned drive (0x0000)

	; In System Bank, (DPH - 2) is Disk Unit, (DPH - 1) is Slice
	DEC	DE
	DEC	DE			; DE = DPH - 2
	EX	DE,HL			; HL = DPH - 2 (source in System Bank)

	; Copy 2 bytes from SYS_BANK:(DPH-2) to CPM_USER_BANK:(CPM3_DPH_BUF)
	PUSH	HL
	PUSH	IX
	LD	B,0F4H			; SYSSETCPY
	LD	A,(CPM_USER_BANK)
	LD	D,A			; Dest = User Bank
	LD	A,(CPM3_SYS_BANK)
	LD	E,A			; Src = System Bank
	LD	HL,2
	RST	08H
	POP	IX
	POP	HL

	LD	DE,CPM3_DPH_BUF
	PUSH	IX
	LD	B,0F5H			; SYSBNKCPY
	RST	08H
	POP	IX

	; Query HBIOS BF_DIODEVICE (0x17) with unit in CPM3_DPH_BUF[0]
	LD	A,(CPM3_DPH_BUF)
	LD	C,A			; C = Unit
	LD	B,17H			; BF_DIODEVICE
	PUSH	IX
	RST	08H
	POP	IX
	; D = Device Type, E = Physical Unit
	; DIODEV_MD = 0x00, MD0 = 0x00
	LD	A,D
	OR	A
	JR	NZ,DRL_CPM3_NOT_MD
	LD	A,E
	OR	A
	JR	NZ,DRL_CPM3_NOT_MD

	; Match found!
	POP	HL
	POP	BC
	LD	A,C			; A = drive index (0=A, 1=B...)
	LD	(RAMDRIVE_DRIVE_NUM),A
	ADD	A,'A'
	CALL	SET_RAMDRIVE_CHAR
	LD	A,C
	OR	A			; Carry = 0
	RET

DRL_CPM3_NOT_MD:
DRL_CPM3_NEXT:
	POP	HL
	INC	HL
	INC	HL
	POP	BC
	INC	C
	DEC	B
	JP	NZ,DRL_CPM3_LOOP
	JR	DRL_NOT_FOUND

DRL_NOT_FOUND:
	LD	A,0FFH
	SCF
	RET

;------------------------------------------------------------------------------
; SET_RAMDRIVE_CHAR:
; Sets RAMDRIVE_DRIVE_CHAR and updates all status/message strings containing
; the drive letter.
; Input: A = Drive character ('A'..'P')
; Destroys: None
;------------------------------------------------------------------------------
SET_RAMDRIVE_CHAR:
	LD	(RAMDRIVE_DRIVE_CHAR),A
	LD	(STR_MSG_HIB_DRV_CHAR),A
	LD	(STR_MSG_HIB_FILE_CHAR),A
	LD	(STR_MSG_HIB_LETTER),A
	LD	(STR_MSG_REST_LETTER),A
	LD	(STR_MSG_REST_DONE_LTR),A
	LD	(STR_MSG_ORPHAN_LETTER),A
	LD	(STR_SPLASH_RAM_LTR),A
	RET

;------------------------------------------------------------------------------
; VALIDATE_RAMDRIVE_SAFETY:
; If CFG_RAMDRIVE_FLAG != 0 (Enabled or Hibernate):
; Verifies that the RAM drive memory blocks can be safely repurposed.
; Reverts to Protected mode (CFG_RAMDRIVE_FLAG = 0) if:
;   1. Active default drive is the RAM drive, OR
;   2. Target file to load is on the RAM drive.
; Displays status message if reverting.
;------------------------------------------------------------------------------
VALIDATE_RAMDRIVE_SAFETY:
	LD	A,(CFG_RAMDRIVE_FLAG)
	OR	A
	RET	Z			; Already protected mode -> nothing to do

	LD	A,(RAMDRIVE_DRIVE_NUM)
	CP	0FFH
	JR	NZ,VRS_CHECK_ACTIVE
	; No RAM drive detected! If in Hibernate mode, revert to protected
	LD	A,(CFG_RAMDRIVE_FLAG)
	CP	RAMDRV_MODE_HIBERNATE
	RET	NZ
	XOR	A
	LD	(CFG_RAMDRIVE_FLAG),A
	RET

VRS_CHECK_ACTIVE:
	LD	B,A			; B = RAM drive number (0-based)
	LD	A,(CURRENT_DEFAULT_DRIVE)
	CP	B
	JR	Z,VRS_FAIL_ACTIVE

	; Check if command-line target file is on RAM drive
	LD	A,(HAS_FILE_ARG)
	OR	A
	RET	Z			; No file arg -> safe

	LD	A,(WORK_FCB)
	OR	A
	JR	NZ,VRS_TARGET_EXP
	LD	A,(CURRENT_DEFAULT_DRIVE)
	JR	VRS_TARGET_CMP

VRS_TARGET_EXP:
	DEC	A			; 1->0 (A:), 2->1 (B:), etc.

VRS_TARGET_CMP:
	CP	B
	JR	Z,VRS_FAIL_TARGET
	RET

VRS_FAIL_ACTIVE:
	LD	DE,STR_MSG_HIB_DRV_ERR
	CALL	PRINT_STR
	CALL	DELAY_BRIEF
	XOR	A
	LD	(CFG_RAMDRIVE_FLAG),A
	LD	(RAMDRIVE_IS_HIBERNATED),A
	RET

VRS_FAIL_TARGET:
	LD	DE,STR_MSG_HIB_FILE_ERR
	CALL	PRINT_STR
	CALL	DELAY_BRIEF
	XOR	A
	LD	(CFG_RAMDRIVE_FLAG),A
	LD	(RAMDRIVE_IS_HIBERNATED),A
	RET

;------------------------------------------------------------------------------
; CHECK_TARGET_DRIVE_UNAVAILABLE:
; Checks if 1-based drive in A (1=A..16=P, or 0=CURRENT_DIR_DRIVE) targets
; an unavailable RAM drive (overwritten or hibernated).
; Returns:
;   Carry = 1: Drive is unavailable RAM drive
;   Carry = 0: Drive is available / valid
; Preserves: A, BC, DE, HL
;------------------------------------------------------------------------------
CHECK_TARGET_DRIVE_UNAVAILABLE:
	PUSH	BC
	PUSH	AF
	OR	A
	JR	NZ,CTDU_HAVE_DRV
	LD	A,(CURRENT_DIR_DRIVE)
	OR	A
	JR	NZ,CTDU_HAVE_DRV
	LD	A,(CURRENT_DEFAULT_DRIVE)
	INC	A

CTDU_HAVE_DRV:
	DEC	A			; A = 0-based drive (0=A..15=P)
	LD	B,A
	LD	A,(RAMDRIVE_DRIVE_NUM)
	CP	0FFH
	JR	Z,CTDU_SAFE		; No RAM drive detected -> safe
	CP	B
	JR	NZ,CTDU_SAFE		; Target is not the RAM drive -> safe

	; Target matches RAM drive. Check if hibernated or overwritten:
	LD	A,(RAMDRIVE_IS_HIBERNATED)
	OR	A
	JR	NZ,CTDU_UNAVAIL
	LD	A,(CFG_RAMDRIVE_FLAG)
	CP	RAMDRV_MODE_ENABLED
	JR	NZ,CTDU_SAFE

CTDU_UNAVAIL:
	POP	AF
	POP	BC
	SCF				; Carry = 1 (unavailable!)
	RET

CTDU_SAFE:
	POP	AF
	POP	BC
	OR	A			; Carry = 0 (safe)
	RET

;------------------------------------------------------------------------------
; CHECK_FCB_IS_HIBERNATED:
; Checks if WORK_FCB targets the currently unavailable RAM drive.
; Returns:
;   Carry = 1 if target drive is unavailable RAM drive
;   Carry = 0 if target drive is safe to access
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
CHECK_FCB_IS_HIBERNATED:
	LD	A,(WORK_FCB)
	OR	A
	JR	NZ,CFIH_HAVE_DRV
	LD	A,(CURRENT_DEFAULT_DRIVE)
	INC	A
CFIH_HAVE_DRV:
	JP	CHECK_TARGET_DRIVE_UNAVAILABLE

INIT_RAMDRV_FCB:
	LD	HL,RAMDRV_FCB
	LD	(HL),0			; Drive 0 = current default drive
	INC	HL
	LD	DE,STR_RAMDRV_FILENAME	; "RAMDRV  IMG" (11 bytes)
	LD	B,11
IRF_COPY:
	LD	A,(DE)
	LD	(HL),A
	INC	HL
	INC	DE
	DJNZ	IRF_COPY
	LD	B,24
IRF_ZERO:
	LD	(HL),0
	INC	HL
	DJNZ	IRF_ZERO
	RET

; HIBERNATE_RAMDRIVE:
; Saves physical banks 0x81..0x88 (256 KB) into RAMDRV.IMG on active drive.
HIBERNATE_RAMDRIVE:
	; If already hibernated, nothing to do
	LD	A,(RAMDRIVE_IS_HIBERNATED)
	OR	A
	RET	NZ

	; Safety Check 1: Prohibit hibernating if running from RAM drive
	LD	A,(RAMDRIVE_DRIVE_NUM)
	CP	0FFH
	RET	Z			; No RAM drive detected -> nothing to hibernate
	LD	C,25			; BDOS Get Current Drive
	CALL	BDOS_ENTRY
	LD	(CURRENT_DEFAULT_DRIVE),A
	LD	HL,RAMDRIVE_DRIVE_NUM
	CP	(HL)
	JP	Z,HIB_FAIL_RAMDRV_ACTIVE

	; Safety Check 2: Prohibit hibernating if target file is on RAM drive
	LD	A,(HAS_FILE_ARG)
	OR	A
	JR	Z,HIB_CHECK_SPACE
	LD	A,(WORK_FCB)
	OR	A
	JR	NZ,HIB_TARGET_EXP
	LD	A,(CURRENT_DEFAULT_DRIVE)
	JR	HIB_TARGET_CMP
HIB_TARGET_EXP:
	DEC	A
HIB_TARGET_CMP:
	LD	HL,RAMDRIVE_DRIVE_NUM
	CP	(HL)
	JP	Z,HIB_FAIL_TARGET_ON_RAMDRV

HIB_CHECK_SPACE:
	; Safety Check 3: Pre-check DPB disk size (DSM >= 200 blocks)
	LD	C,31			; BDOS Get DPB
	CALL	BDOS_ENTRY		; HL = DPB address
	; DSM is at offset 5 (little-endian word)
	INC	HL
	INC	HL
	INC	HL
	INC	HL
	INC	HL
	LD	E,(HL)
	INC	HL
	LD	D,(HL)			; DE = DSM
	LD	A,D
	OR	A
	JR	NZ,HIB_SPACE_OK
	LD	A,E
	CP	200
	JP	C,HIB_FAIL_TOO_SMALL

HIB_SPACE_OK:
	; Ensure CPM_USER_BANK is queried and known
	PUSH	IX
	LD	B,0F3H			; SYSGETBNK
	RST	08H
	POP	IX
	LD	A,C
	LD	(CPM_USER_BANK),A

	; Check for orphaned RAMDRV.IMG from previous crash/power failure
	CALL	INIT_RAMDRV_FCB
	LD	DE,RAMDRV_FCB
	LD	C,15			; BDOS Open File
	CALL	BDOS_ENTRY
	CP	0FFH
	JR	Z,HIB_NO_ORPHAN

	; Orphan found! Restore it first to avoid losing data
	LD	DE,STR_MSG_ORPHAN_FOUND
	CALL	PRINT_STR
	CALL	RESTORE_RAMDRIVE_BODY
	JP	C,HIB_WRITE_ERR
	LD	DE,STR_MSG_REST_DONE
	CALL	PRINT_STR

HIB_NO_ORPHAN:
	; Delete any old RAMDRV.IMG file just in case
	CALL	INIT_RAMDRV_FCB
	LD	DE,RAMDRV_FCB
	LD	C,19			; BDOS Delete File
	CALL	BDOS_ENTRY

	; Create new RAMDRV.IMG
	CALL	INIT_RAMDRV_FCB
	LD	DE,RAMDRV_FCB
	LD	C,22			; BDOS Make File
	CALL	BDOS_ENTRY
	CP	0FFH
	JP	Z,HIB_CREATE_ERR

	; Display Hibernating message
	LD	DE,STR_MSG_HIBERNATING
	CALL	PRINT_STR

	; Set BDOS DMA buffer to CFG_IO_BUF
	LD	DE,CFG_IO_BUF
	LD	C,26			; BDOS Set DMA
	CALL	BDOS_ENTRY

	; Outer Loop: Bank 0x81 through 0x88 (8 banks)
	LD	A,RAMDRV_START_BANK
	LD	(HIB_CUR_BANK),A

HIB_BANK_LOOP:
	; Inner Loop: 256 sectors (offset 0x0000 to 0x7F80)
	LD	HL,0
	LD	(HIB_FAR_OFFSET),HL

HIB_SECTOR_LOOP:
	; Set up HBIOS Far copy parameters (Dest = CPM_USER_BANK,
	; Src = HIB_CUR_BANK, Count = 128)
	PUSH	IX
	LD	B,0F4H			; SYSSETCPY
	LD	A,(CPM_USER_BANK)
	LD	D,A			; Dest Bank = CPM_USER_BANK
	LD	A,(HIB_CUR_BANK)
	LD	E,A			; Src Bank = HIB_CUR_BANK
	LD	HL,128			; Byte count = 128
	RST	08H
	POP	IX

	; Copy 128 bytes from Far RAM (HIB_CUR_BANK, HIB_FAR_OFFSET) into CFG_IO_BUF
	LD	HL,(HIB_FAR_OFFSET)	; Src Addr = Far Offset
	LD	DE,CFG_IO_BUF		; Dest Addr = Local Buffer
	PUSH	IX
	LD	B,0F5H			; SYSBNKCPY
	RST	08H
	POP	IX

	; Write sector to disk via BDOS 21 (Write Sequential)
	LD	DE,RAMDRV_FCB
	LD	C,21			; BDOS Write Sequential
	CALL	BDOS_ENTRY
	OR	A
	JR	NZ,HIB_WRITE_ERR

	; Advance HIB_FAR_OFFSET by 128 bytes
	LD	HL,(HIB_FAR_OFFSET)
	LD	DE,128
	ADD	HL,DE
	LD	(HIB_FAR_OFFSET),HL
	LD	A,H
	CP	080H			; Reached 0x8000 (32KB)?
	JR	NZ,HIB_SECTOR_LOOP

	; Advance to next bank
	LD	A,(HIB_CUR_BANK)
	INC	A
	LD	(HIB_CUR_BANK),A
	CP	RAMDRV_END_BANK + 1
	JR	NZ,HIB_BANK_LOOP

	; Close RAMDRV.IMG
	LD	DE,RAMDRV_FCB
	LD	C,16			; BDOS Close File
	CALL	BDOS_ENTRY
	CP	0FFH
	JR	Z,HIB_CREATE_ERR

	; Reset DMA buffer to default
	LD	DE,DEFAULT_DMA
	LD	C,26			; BDOS Set DMA
	CALL	BDOS_ENTRY

	; Mark as hibernated
	LD	A,1
	LD	(RAMDRIVE_IS_HIBERNATED),A

	; Print completion message
	LD	DE,STR_MSG_HIB_DONE
	CALL	PRINT_STR
	RET

HIB_FAIL_RAMDRV_ACTIVE:
	LD	DE,STR_MSG_HIB_DRV_ERR
	CALL	PRINT_STR
	CALL	DELAY_BRIEF
	XOR	A
	LD	(RAMDRIVE_IS_HIBERNATED),A
	LD	(CFG_RAMDRIVE_FLAG),A
	RET

HIB_FAIL_TARGET_ON_RAMDRV:
	LD	DE,STR_MSG_HIB_FILE_ERR
	CALL	PRINT_STR
	CALL	DELAY_BRIEF
	XOR	A
	LD	(RAMDRIVE_IS_HIBERNATED),A
	LD	(CFG_RAMDRIVE_FLAG),A
	RET

HIB_FAIL_TOO_SMALL:
	LD	DE,STR_MSG_HIB_TOO_SMALL
	CALL	PRINT_STR
	XOR	A
	LD	(RAMDRIVE_IS_HIBERNATED),A
	LD	(CFG_RAMDRIVE_FLAG),A
	RET

HIB_WRITE_ERR:
HIB_CREATE_ERR:
	; Cleanup partial file and reset DMA
	LD	DE,RAMDRV_FCB
	LD	C,16			; BDOS Close File
	CALL	BDOS_ENTRY
	CALL	INIT_RAMDRV_FCB
	LD	DE,RAMDRV_FCB
	LD	C,19			; BDOS Delete File
	CALL	BDOS_ENTRY
	LD	DE,DEFAULT_DMA
	LD	C,26			; BDOS Set DMA
	CALL	BDOS_ENTRY
	XOR	A
	LD	(RAMDRIVE_IS_HIBERNATED),A
	LD	(CFG_RAMDRIVE_FLAG),A	; Revert to protected mode
	LD	DE,STR_MSG_HIB_ERR
	CALL	PRINT_STR
	RET

; RESTORE_RAMDRIVE:
; Restores physical banks 0x81..0x88 from RAMDRV.IMG if hibernated.
RESTORE_RAMDRIVE:
	; Only restore if currently marked as hibernated
	LD	A,(RAMDRIVE_IS_HIBERNATED)
	CP	1
	RET	NZ

	; Display Restoring message
	LD	DE,STR_MSG_RESTORING
	CALL	PRINT_STR

	CALL	RESTORE_RAMDRIVE_BODY
	JR	C,REST_FAILED

	; Successfully restored!
	XOR	A
	LD	(RAMDRIVE_IS_HIBERNATED),A
	LD	DE,STR_MSG_REST_DONE
	CALL	PRINT_STR
	RET

REST_FAILED:
	XOR	A
	LD	(RAMDRIVE_IS_HIBERNATED),A
	LD	DE,STR_MSG_REST_ERR
	CALL	PRINT_STR
	RET

; RESTORE_RAMDRIVE_BODY:
; Reads RAMDRV.IMG from disk and writes sectors into Far RAM banks 0x81..0x88.
; Deletes RAMDRV.IMG upon completion.
; Output: Carry = 0 on success, Carry = 1 on failure.
RESTORE_RAMDRIVE_BODY:
	; Set BDOS DMA buffer to CFG_IO_BUF
	LD	DE,CFG_IO_BUF
	LD	C,26			; BDOS Set DMA
	CALL	BDOS_ENTRY

	; Open RAMDRV.IMG
	CALL	INIT_RAMDRV_FCB
	LD	DE,RAMDRV_FCB
	LD	C,15			; BDOS Open File
	CALL	BDOS_ENTRY
	CP	0FFH
	JR	Z,RRB_OPEN_ERR

	; Ensure CR = 0
	XOR	A
	LD	(RAMDRV_FCB + 32),A

	; Outer Loop: Bank 0x81 through 0x88
	LD	A,RAMDRV_START_BANK
	LD	(HIB_CUR_BANK),A

RRB_BANK_LOOP:
	; Inner Loop: 256 sectors
	LD	HL,0
	LD	(HIB_FAR_OFFSET),HL

RRB_SECTOR_LOOP:
	; Read 128 bytes from disk into CFG_IO_BUF
	LD	DE,RAMDRV_FCB
	LD	C,20			; BDOS Read Sequential
	CALL	BDOS_ENTRY
	OR	A
	JR	NZ,RRB_READ_ERR

	; Set up HBIOS Far copy parameters (Dest = HIB_CUR_BANK,
	; Src = CPM_USER_BANK, Count = 128)
	PUSH	IX
	LD	B,0F4H			; SYSSETCPY
	LD	A,(HIB_CUR_BANK)
	LD	D,A			; Dest Bank = HIB_CUR_BANK
	LD	A,(CPM_USER_BANK)
	LD	E,A			; Src Bank = CPM_USER_BANK
	LD	HL,128			; Byte count = 128
	RST	08H
	POP	IX

	; Copy 128 bytes from CFG_IO_BUF into Far RAM (HIB_CUR_BANK, HIB_FAR_OFFSET)
	LD	HL,CFG_IO_BUF		; Src Addr = Local Buffer
	LD	DE,(HIB_FAR_OFFSET)	; Dest Addr = Far Offset
	PUSH	IX
	LD	B,0F5H			; SYSBNKCPY
	RST	08H
	POP	IX

	; Advance HIB_FAR_OFFSET by 128 bytes
	LD	HL,(HIB_FAR_OFFSET)
	LD	DE,128
	ADD	HL,DE
	LD	(HIB_FAR_OFFSET),HL
	LD	A,H
	CP	080H			; Reached 0x8000 (32KB)?
	JR	NZ,RRB_SECTOR_LOOP

	; Advance to next bank
	LD	A,(HIB_CUR_BANK)
	INC	A
	LD	(HIB_CUR_BANK),A
	CP	RAMDRV_END_BANK + 1
	JR	NZ,RRB_BANK_LOOP

	; Close RAMDRV.IMG
	LD	DE,RAMDRV_FCB
	LD	C,16			; BDOS Close File
	CALL	BDOS_ENTRY

	; Delete RAMDRV.IMG to free disk space
	CALL	INIT_RAMDRV_FCB
	LD	DE,RAMDRV_FCB
	LD	C,19			; BDOS Delete File
	CALL	BDOS_ENTRY

	; Reset DMA buffer
	LD	DE,DEFAULT_DMA
	LD	C,26
	CALL	BDOS_ENTRY

	AND	A			; Carry = 0 (success)
	RET

RRB_READ_ERR:
RRB_OPEN_ERR:
	; Close if open
	LD	DE,RAMDRV_FCB
	LD	C,16			; BDOS Close File
	CALL	BDOS_ENTRY

	; Reset DMA buffer
	LD	DE,DEFAULT_DMA
	LD	C,26
	CALL	BDOS_ENTRY

	SCF				; Carry = 1 (error)
	RET

;------------------------------------------------------------------------------
; File Loading: Reads files directly into Far RAM banks
;------------------------------------------------------------------------------
LOAD_FILE:
	XOR	A
	LD	(STATUS_OOM_FLAG),A
	LD	(FILE_IS_TRUNCATED),A
	LD	HL,0
	LD	(FILE_TOTAL_RECORDS),HL
	LD	(FILE_RECORDS_HI),A
	LD	DE,DEFAULT_DMA
	LD	C,26			; BDOS Set DMA
	CALL	BDOS_ENTRY

	; Set BDOS user area to WORK_FCB_USER
	LD	A,(WORK_FCB_USER)
	LD	E,A
	LD	C,32			; BDOS Set User Area
	CALL	BDOS_ENTRY

	; Guard: if target drive is hibernated RAM drive, reject load
	CALL	CHECK_FCB_IS_HIBERNATED
	JP	C,LOAD_FILE_NOT_FOUND

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

	; Probe file size using BDOS Call 35 (Compute File Size)
	LD	DE,WORK_FCB
	LD	C,35			; BDOS Compute File Size
	CALL	BDOS_ENTRY
	LD	HL,(WORK_FCB+33)	; r0, r1
	LD	(FILE_TOTAL_RECORDS),HL
	LD	A,(WORK_FCB+35)		; r2
	LD	(FILE_RECORDS_HI),A

	; Zero FCB extent, s1, s2, rc, and record bytes before open
	LD	HL,WORK_FCB+12
	LD	(HL),0
	LD	DE,WORK_FCB+13
	LD	BC,23
	LDIR

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
	CALL	CLEAR_CACHE_DIRTY_FLAGS
	LD	HL,0
	LD	(VIEW_LEFT_COL),HL
	LD	A,(ACTIVE_COLS)
	LD	L,A
	LD	H,0
	LD	(VIEW_RIGHT_COL),HL

	CALL	INIT_SLOT_SYSTEM

	; Initialize loader state
	LD	HL,0FFFFH
	LD	(LOAD_HEAD_SLOT),HL
	LD	(LOAD_CUR_SLOT),HL
	LD	A,2
	LD	(LOAD_STRIDE_OFF),A

	; Initialize loading UI state & display
	LD	A,1
	LD	(IS_LOADING_FILE),A
	LD	(HAS_FILE_ARG),A
	XOR	A
	LD	(IS_SPLASH_SCREEN),A
	LD	A,100
	LD	(LOAD_PROGRESS_COUNT),A
	LD	HL,0
	LD	(LOAD_PROGRESS_LINES),HL

	CALL	DRAW_LOADING_SCREEN

READ_SECTOR_LOOP:
	LD	DE,DEFAULT_DMA
	LD	C,26			; BDOS Set DMA
	CALL	BDOS_ENTRY

	LD	DE,WORK_FCB
	LD	C,20			; BDOS Read Next Record
	CALL	BDOS_ENTRY
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
	JP	Z,HANDLE_CR

	CP	10			; LF
	JP	Z,HANDLE_LF

	; Normal character (including 0x09 Tab): stream into Far RAM stride chain
	XOR	A
	LD	(SEEN_CR),A

	; Check if head slot already allocated for this line
	LD	DE,(LOAD_HEAD_SLOT)
	LD	A,D
	AND	E
	INC	A			; 0 if DE == 0xFFFF
	JR	NZ,LOAD_HAVE_HEAD

	; Allocate head slot
	PUSH	HL			; Save sector pointer
	PUSH	BC			; Save sector counter (C)
	CALL	APPEND_LINE_SLOT	; BC = allocated slot ID, Carry on OOM
	JR	C,LOAD_LINE_OOM
	LD	(LOAD_HEAD_SLOT),BC
	LD	(LOAD_CUR_SLOT),BC
	LD	HL,0FFFFH
	LD	(FAR_IO_BUF),HL
	LD	A,2
	LD	(LOAD_STRIDE_OFF),A
	POP	BC
	POP	HL

LOAD_HAVE_HEAD:
	; Check if current stride is full (126 chars stored -> LOAD_STRIDE_OFF == 128)
	LD	A,(LOAD_STRIDE_OFF)
	CP	FAR_SLOT_SIZE		; 128
	JR	C,LOAD_STORE_CHAR

	; Stride is full! Allocate an extension slot
	PUSH	HL			; Save sector pointer
	PUSH	BC			; Save sector counter (C)
	CALL	ALLOC_SLOT		; HL = new slot ID, Carry on OOM
	JR	C,LOAD_LINE_OOM_EXT

	; Link current stride to new extension slot
	LD	(FAR_IO_BUF),HL		; NEXT_SLOT_ID = new slot ID
	PUSH	HL			; Save new slot ID

	; Write full current stride to Far RAM
	LD	BC,(LOAD_CUR_SLOT)
	LD	HL,FAR_IO_BUF
	CALL	WRITE_FAR_SLOT

	POP	DE			; DE = new slot ID
	LD	(LOAD_CUR_SLOT),DE

	; Initialize new stride in FAR_IO_BUF
	LD	HL,0FFFFH
	LD	(FAR_IO_BUF),HL
	LD	A,2
	LD	(LOAD_STRIDE_OFF),A

	POP	BC
	POP	HL

LOAD_STORE_CHAR:
	LD	A,(LOAD_STRIDE_OFF)
	LD	E,A
	LD	D,0
	LD	A,(HL)			; Char from sector buffer
	PUSH	HL
	LD	HL,FAR_IO_BUF
	ADD	HL,DE
	LD	(HL),A
	POP	HL

	LD	A,(LOAD_STRIDE_OFF)
	INC	A
	LD	(LOAD_STRIDE_OFF),A
	JP	NEXT_BYTE_IN_SECTOR

LOAD_LINE_OOM_EXT:
	POP	BC
	POP	HL
	LD	A,1
	LD	(FILE_IS_TRUNCATED),A
	JP	NEXT_BYTE_IN_SECTOR

LOAD_LINE_OOM:
	POP	BC
	POP	HL
	LD	A,1
	LD	(FILE_IS_TRUNCATED),A
	JP	FILE_LOAD_DONE

HANDLE_CR:
	LD	A,1
	LD	(SEEN_CR),A
	LD	A,FMT_CPM
	LD	(SAVE_FORMAT),A
	JP	NEXT_BYTE_IN_SECTOR

HANDLE_LF:
	PUSH	HL			; Preserve sector buffer pointer HL!
	PUSH	BC			; Preserve sector counter C!

	; If no preceding CR, detect Linux format
	LD	A,(SEEN_CR)
	OR	A
	JR	NZ,LF_AFTER_CR
	LD	A,FMT_LINUX
	LD	(SAVE_FORMAT),A

LF_AFTER_CR:
	XOR	A
	LD	(SEEN_CR),A

	; Check if a line was open (LOAD_HEAD_SLOT != 0xFFFF)
	LD	HL,(LOAD_HEAD_SLOT)
	LD	A,H
	AND	L
	INC	A
	JR	NZ,LF_CLOSE_LINE

	; Empty line (LOAD_HEAD_SLOT == 0xFFFF): allocate head slot
	CALL	APPEND_LINE_SLOT
	JR	C,LF_OOM_HANDLE
	; Initialize empty line in FAR_IO_BUF: NEXT_SLOT_ID = 0xFFFF, byte 2 = 0
	LD	HL,0FFFFH
	LD	(FAR_IO_BUF),HL
	XOR	A
	LD	(FAR_IO_BUF+2),A
	; Write to Far RAM
	LD	HL,FAR_IO_BUF
	CALL	WRITE_FAR_SLOT
	JR	LF_LINE_COUNT_INC

LF_CLOSE_LINE:
	; Null-terminate current stride in FAR_IO_BUF if not exactly 128
	LD	A,(LOAD_STRIDE_OFF)
	CP	FAR_SLOT_SIZE
	JR	NC,LF_STRIDE_FULL
	LD	E,A
	LD	D,0
	LD	HL,FAR_IO_BUF
	ADD	HL,DE
	LD	(HL),0			; Null terminator

LF_STRIDE_FULL:
	; Ensure NEXT_SLOT_ID is 0xFFFF
	LD	HL,0FFFFH
	LD	(FAR_IO_BUF),HL

	; Write final stride to Far RAM at LOAD_CUR_SLOT
	LD	BC,(LOAD_CUR_SLOT)
	LD	HL,FAR_IO_BUF
	CALL	WRITE_FAR_SLOT

LF_LINE_COUNT_INC:
	LD	HL,(DOC_TOTAL_LINES)
	INC	HL
	LD	(DOC_TOTAL_LINES),HL
	LD	(LOAD_PROGRESS_LINES),HL

	; Check 100-line progress interval
	LD	A,(LOAD_PROGRESS_COUNT)
	DEC	A
	LD	(LOAD_PROGRESS_COUNT),A
	JR	NZ,LPCI_NO_TICK
	LD	A,100
	LD	(LOAD_PROGRESS_COUNT),A
	CALL	UPDATE_LOAD_PROGRESS
LPCI_NO_TICK:

	; Reset line loader state for next line
	LD	HL,0FFFFH
	LD	(LOAD_HEAD_SLOT),HL
	LD	(LOAD_CUR_SLOT),HL
	LD	A,2
	LD	(LOAD_STRIDE_OFF),A

	POP	BC
	POP	HL
	JR	NEXT_BYTE_IN_SECTOR

LF_OOM_HANDLE:
	POP	BC
	POP	HL
	LD	A,1
	LD	(FILE_IS_TRUNCATED),A
	JP	FILE_LOAD_DONE

NEXT_BYTE_IN_SECTOR:
	INC	HL
	DEC	C
	JP	NZ,PARSE_BYTE_LOOP
	JP	READ_SECTOR_LOOP

FILE_LOAD_DONE:
	; If remaining characters in buffer, flush final line
	LD	HL,(LOAD_HEAD_SLOT)
	LD	A,H
	AND	L
	INC	A
	JR	Z,LOAD_FINISH

	LD	A,(LOAD_STRIDE_OFF)
	CP	FAR_SLOT_SIZE
	JR	NC,DONE_STRIDE_FULL
	LD	E,A
	LD	D,0
	LD	HL,FAR_IO_BUF
	ADD	HL,DE
	LD	(HL),0

DONE_STRIDE_FULL:
	LD	HL,0FFFFH
	LD	(FAR_IO_BUF),HL
	LD	BC,(LOAD_CUR_SLOT)
	LD	HL,FAR_IO_BUF
	CALL	WRITE_FAR_SLOT

	LD	HL,(DOC_TOTAL_LINES)
	INC	HL
	LD	(DOC_TOTAL_LINES),HL
	LD	(LOAD_PROGRESS_LINES),HL

LOAD_FINISH:
	; Final progress update to show exact total lines loaded
	CALL	UPDATE_LOAD_PROGRESS
	XOR	A
	LD	(IS_LOADING_FILE),A

	; Update DOC_USER_NUM and CURRENT_DIR_USER to match loaded file
	LD	A,(WORK_FCB_USER)
	LD	(DOC_USER_NUM),A
	LD	(CURRENT_DIR_USER),A

	; Ensure at least 1 line exists
	LD	HL,(DOC_TOTAL_LINES)
	LD	A,H
	OR	L
	JP	NZ,LOAD_INIT_CACHE
	INC	HL
	LD	(DOC_TOTAL_LINES),HL
	; Write empty line to line 0 in Far RAM
	CALL	APPEND_LINE_SLOT
	LD	HL,0FFFFH
	LD	(FAR_IO_BUF),HL
	XOR	A
	LD	(FAR_IO_BUF+2),A
	LD	HL,FAR_IO_BUF
	CALL	WRITE_FAR_SLOT

LOAD_INIT_CACHE:
	XOR	A
	LD	(IS_LOADING_FILE),A
	LD	(BLOCK_ACTIVE),A
	LD	(DOC_MODIFIED),A
	LD	(STATUS_OOM_FLAG),A
	CALL	INVALIDATE_ACTIVE_LINE
	CALL	CHECKOUT_ACTIVE_LINE
	CALL	RELOAD_CACHE_WINDOW_FORCE
	OR	A			; Carry = 0 (success)
	RET

LOAD_FILE_NOT_FOUND:
	; Restore BDOS user area to CURRENT_DIR_USER
	LD	A,(CURRENT_DIR_USER)
	LD	E,A
	LD	C,32			; BDOS Set User Area
	CALL	BDOS_ENTRY
	XOR	A
	LD	(IS_LOADING_FILE),A
	SCF				; Carry = 1 (error: file not found)
	RET

;------------------------------------------------------------------------------
; DRAW_LOADING_SCREEN:
; Clear screen, fill column 0 with tildes '~', and draw initial status bar.
; Preserves: none
;------------------------------------------------------------------------------
DRAW_LOADING_SCREEN:
	; Hide cursor during load
	LD	DE,STR_HIDE_CURSOR
	CALL	PRINT_STR

	; Clear screen (cursor moves to row 1, col 1)
	LD	DE,STR_CLEAR_SCREEN
	CALL	PRINT_STR

	; Fill rows 1 to ACTIVE_ROWS - 1 with '~' in column 0
	LD	A,(ACTIVE_ROWS)
	DEC	A			; A = ACTIVE_ROWS - 1
	LD	B,A
DLS_TILDE_LOOP:
	LD	A,'~'
	CALL	PUTC
	LD	A,13
	CALL	PUTC
	LD	A,10
	CALL	PUTC
	DJNZ	DLS_TILDE_LOOP

	; Render initial status bar on row ACTIVE_ROWS
	CALL	RENDER_STATUS_BAR
	RET

;------------------------------------------------------------------------------
; UPDATE_LOAD_PROGRESS:
; Update line field on status bar during file loading.
; Positions cursor directly to Field 5 and prints "Line <lines:5>" in inverse video.
; Preserves all registers (AF, BC, DE, HL).
;------------------------------------------------------------------------------
UPDATE_LOAD_PROGRESS:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL

	; Locate cursor at (ACTIVE_ROWS, Field 5 Col)
	; ESC [ <ACTIVE_ROWS> ; <Col> H
	LD	A,27
	CALL	PUTC
	LD	A,'['
	CALL	PUTC
	LD	A,(ACTIVE_ROWS)
	CALL	PRINT_DEC_BYTE
	LD	A,';'
	CALL	PUTC
	LD	A,(ACTIVE_COLS)
	SUB	STATUS_ENCLOSED_WIDTH	; 80 - 78 = 2,  120 - 78 = 42
	SRL	A			; 1 or 21
	ADD	A,55			; Col 56 (80x24) or Col 76 (120x40)
	CALL	PRINT_DEC_BYTE
	LD	A,'H'
	CALL	PUTC

	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR

	LD	DE,STR_STATUS_POS	; "Line " (5 chars)
	CALL	PRINT_STR

	LD	HL,(LOAD_PROGRESS_LINES)
	CALL	GET_DEC_WORD_DIGITS	; A = digits (1..5)
	LD	C,A
	LD	A,5
	SUB	C
	JR	C,ULP_NUM
	JR	Z,ULP_NUM
	LD	B,A
ULP_PAD:
	LD	A,' '
	CALL	PUTC
	DJNZ	ULP_PAD
ULP_NUM:
	LD	HL,(LOAD_PROGRESS_LINES)
	CALL	PRINT_DEC_WORD

	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR

	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

;------------------------------------------------------------------------------
; Initialize Empty Document into Far RAM Banks (1 empty line)
;------------------------------------------------------------------------------
INIT_EMPTY_DOCUMENT:
	CALL	INIT_SLOT_SYSTEM
	CALL	ALLOC_SLOT		; HL = 0
	LD	BC,0
	CALL	SET_LINE_SLOT		; Line 0 = slot 0

	LD	HL,1
	LD	(DOC_TOTAL_LINES),HL
	LD	HL,0
	LD	(CUR_DOC_ROW),HL
	LD	(TOP_DOC_ROW),HL
	LD	(CACHE_START_ROW),HL
	LD	(CUR_COL),HL
	LD	(TARGET_COL),HL
	CALL	CLEAR_CACHE_DIRTY_FLAGS
	XOR	A
	LD	(DOC_MODIFIED),A
	LD	(BLOCK_ACTIVE),A
	LD	(STATUS_OOM_FLAG),A
	LD	(FILE_IS_TRUNCATED),A
	LD	HL,0
	LD	(VIEW_LEFT_COL),HL
	LD	A,(ACTIVE_COLS)
	LD	L,A
	LD	H,0
	LD	(VIEW_RIGHT_COL),HL
	LD	A,1
	LD	(INSERT_MODE),A

	; Write empty line to line 0 in Far RAM
	LD	HL,0FFFFH
	LD	(FAR_IO_BUF),HL
	XOR	A
	LD	(FAR_IO_BUF+2),A
	LD	HL,FAR_IO_BUF
	LD	BC,0
	CALL	WRITE_FAR_SLOT

	; Invalidate and force reload local cache window
	CALL	INVALIDATE_ACTIVE_LINE
	CALL	CHECKOUT_ACTIVE_LINE
	CALL	RELOAD_CACHE_WINDOW_FORCE
	RET

;------------------------------------------------------------------------------
; Open File Screen with Sorted Directory Listing & Pagination
;------------------------------------------------------------------------------
DO_OPEN_FILE_UI:
	; Invalidate active line and flush dirty cache before directory collection
	; overlays LINE_STORAGE
	CALL	INVALIDATE_ACTIVE_LINE
	CALL	FLUSH_DIRTY_CACHE
	LD	HL,0FFFFH
	LD	(CACHE_START_ROW),HL

	; Initialize directory layout parameters based on active screen mode
	CALL	INIT_DIR_LAYOUT

	; Initialize active directory drive from default disk or WORK_FCB
	CALL	INIT_DIR_DRIVE

	; Initialize directory user area from current document or plugin user area
	LD	A,(IS_PLUGIN_LOAD_UI)
	OR	A
	JR	Z,IDU_DOC
	LD	A,(PLUGIN_USER_AREA)
	JR	IDU_SET
IDU_DOC:
	LD	A,(DOC_USER_NUM)
IDU_SET:
	LD	(CURRENT_DIR_USER),A

	; Filter defaults to all files shown unless explicitly provided in edit box
	CALL	RESET_DIR_FILTER

	; Preload edit box with known current drive and user area prefix (e.g. "J0:", "A4:")
	CALL	PRELOAD_DRIVE_USER_PREFIX
	LD	HL,0
	LD	(OPEN_GOTO_LINE),HL

REFRESH_OPEN_DIR:
	; 1. Collect Directory Entries from CURRENT_DIR_DRIVE (with Bit-7 strip & dup filter)
	CALL	COLLECT_DIR_ENTRIES

	; 2. Sort Directory Entries Alphabetically
	CALL	SORT_DIR_ENTRIES

	; 3. Calculate Total Pages (using dynamic DIR_PAGE_CAPACITY)
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
	LD	HL,DIR_PAGE_CAPACITY
	LD	C,(HL)
DIV_PAGE_LOOP:
	CP	C
	JR	C,DIV_PAGE_DONE
	SUB	C
	INC	B
	JR	DIV_PAGE_LOOP
DIV_PAGE_DONE:
	INC	B			; Total pages = quotient + 1
	LD	A,B
	LD	(DIR_PAGE_COUNT),A

RENDER_OPEN_PAGE:
	CALL	TERM_INIT
	LD	A,1
	LD	(IS_SPLASH_SCREEN),A
	CALL	RENDER_DIR_TITLE

	; Display Directory Entries for Current Page
	CALL	DISPLAY_DIR_PAGE

	; Display Open Prompt & Page Indicator
	CALL	DISPLAY_OPEN_PROMPT

	; Finish prompt line and fill remaining rows down to status row with '~'
	CALL	FINISH_UI_PAGE_AND_STATUS

	; Read Filename Input (echoes prefilled string if non-empty, e.g. "A:")
	CALL	READ_FILENAME_INPUT_PREFILLED
	JP	C,CHECK_PAGING_OR_CANCEL

	; Check if user typed a FAT specification (U: or U<unit>:)
	CALL	CHECK_FAT_INPUT_OPEN
	JP	C,SHOW_INLINE_OPEN_ERROR
	JP	NZ,HANDLE_OPEN_FAT_DISPATCH

	; Check if user typed a drive specification (e.g. "A:")
	CALL	CHECK_DRIVE_SWITCH
	JP	C,HANDLE_OPEN_DRIVE_SWITCH

	; Check if user typed a filter pattern (e.g. "*.TXT" or "B:*.TXT")
	CALL	CHECK_FILTER_PATTERN
	JP	C,HANDLE_OPEN_FILTER

	; If currently browsing a FAT volume, handle relative navigation/open
	LD	A,(CURRENT_DIR_IS_FAT)
	OR	A
	JP	NZ,HANDLE_OPEN_FAT_RELATIVE

DO_PARSE_AND_LOAD:
	; Backup current WORK_FCB to DIR_TEMP_FCB in case open fails
	LD	HL,WORK_FCB
	LD	DE,DIR_TEMP_FCB
	LD	BC,36
	LDIR

	; Check if this is Block Insert File UI!
	LD	A,(IS_BLOCK_INSERT_UI)
	OR	A
	JP	NZ,DO_PARSE_AND_INSERT

	; Check if this is Plugin Load UI!
	LD	A,(IS_PLUGIN_LOAD_UI)
	OR	A
	JP	NZ,DO_PARSE_AND_LOAD_PLUGIN

	; Parse optional line number from INPUT_FILENAME_BUF
	CALL	PARSE_OPEN_LINE_NUM

	; User entered a filename in INPUT_FILENAME_BUF: parse into WORK_FCB
	LD	DE,INPUT_FILENAME_BUF
	CALL	PARSE_FILENAME_TO_FCB

	; Check if target drive is unavailable RAM drive
	LD	A,(WORK_FCB)
	CALL	CHECK_TARGET_DRIVE_UNAVAILABLE
	JR	C,OPEN_RAMDRV_UNAVAILABLE

	; Load the file into Far RAM
	CALL	LOAD_FILE
	JP	C,OPEN_FILE_NOT_FOUND

	; Reset stack and enter editor mode
	LD	SP,LOCAL_STACK
	LD	A,1
	LD	(HAS_FILE_ARG),A
	LD	(IN_EDITOR_MODE),A
	XOR	A
	LD	(DOC_IS_FAT),A

	; Check if target goto line was specified (> 0)
	LD	HL,(OPEN_GOTO_LINE)
	LD	A,H
	OR	L
	JR	Z,OPEN_LINE_DEFAULT
	CALL	GOTO_LINE_HL
	JR	OPEN_RENDER

OPEN_LINE_DEFAULT:
	LD	HL,0
	LD	(CUR_DOC_ROW),HL
	LD	(TOP_DOC_ROW),HL
	XOR	A
	LD	(CUR_COL),A
	LD	(TARGET_COL),A

OPEN_RENDER:
	CALL	TERM_INIT
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	CALL	CHECK_FILE_TRUNCATED_POPUP
	CALL	LOCATE_CURSOR
	JP	MAIN_LOOP

HANDLE_OPEN_DRIVE_SWITCH:
	; A = new drive (1..16 or 0), C = new user (0..15 or 0xFF)
	PUSH	BC			; Save target user
	OR	A
	JR	Z,HODS_DRIVE_DONE	; Drive unchanged

	CALL	CHECK_TARGET_DRIVE_UNAVAILABLE
	JR	NC,HODS_OK

	; Cannot switch to unavailable RAM drive!
	POP	BC
	JR	OPEN_RAMDRV_UNAVAILABLE

HODS_OK:
	LD	(CURRENT_DIR_DRIVE),A
	ADD	A,'A'-1
	LD	(STR_DIR_DRIVE_CHAR),A
	XOR	A
	LD	(CURRENT_DIR_IS_FAT),A

HODS_DRIVE_DONE:
	POP	BC			; C = target user
	LD	A,C
	CP	0FFH
	JR	Z,HODS_USER_DEFAULT_ZERO
	LD	(CURRENT_DIR_USER),A
	JR	HODS_RESET_FILTER
HODS_USER_DEFAULT_ZERO:
	XOR	A
	LD	(CURRENT_DIR_USER),A

HODS_RESET_FILTER:
	; A drive/user switch without wildcard defaults to all files shown
	CALL	RESET_DIR_FILTER
	XOR	A
	LD	(SHOWING_FNF_MSG),A
	JP	REFRESH_OPEN_DIR

HANDLE_OPEN_FILTER:
	XOR	A
	LD	(SHOWING_FNF_MSG),A
	JP	REFRESH_OPEN_DIR

OPEN_RAMDRV_UNAVAILABLE:
	; Restore previous WORK_FCB from DIR_TEMP_FCB
	LD	HL,DIR_TEMP_FCB
	LD	DE,WORK_FCB
	LD	BC,36
	LDIR
	LD	A,(DOC_USER_NUM)
	LD	(WORK_FCB_USER),A

	; Display inline "  RAM drive not available"
	LD	DE,STR_RAMDRV_UNAVAIL_INLINE
	LD	C,25			; length of message
	JR	SHOW_INLINE_OPEN_ERROR

OPEN_FILE_NOT_FOUND:
	; Restore previous WORK_FCB from DIR_TEMP_FCB
	LD	HL,DIR_TEMP_FCB
	LD	DE,WORK_FCB
	LD	BC,36
	LDIR
	LD	A,(DOC_USER_NUM)
	LD	(WORK_FCB_USER),A

	; Display inline "  File not found"
	LD	DE,STR_FNF_INLINE
	LD	C,16			; length of message

SHOW_INLINE_OPEN_ERROR:
	LD	A,C
	LD	(INLINE_MSG_LEN),A

	; Move cursor past ']' box before printing error message
	LD	A,(INPUT_BUF_LEN)
	LD	B,A
	LD	A,21
	SUB	B
	JR	Z,FNF_FWD_DONE
	LD	B,A			; B = 21 - INPUT_BUF_LEN
FNF_FWD_LOOP:
	PUSH	BC
	PUSH	DE
	LD	DE,STR_CSI_C		; ESC [ C
	CALL	PRINT_STR
	POP	DE
	POP	BC
	DJNZ	FNF_FWD_LOOP
FNF_FWD_DONE:

	; Display inline message right after ']'
	CALL	PRINT_STR

	; Set flag that inline message is currently visible
	LD	A,1
	LD	(SHOWING_FNF_MSG),A

	; Resume input loop without blanking filename in text box
	CALL	RESUME_FILENAME_INPUT
	JP	C,CHECK_PAGING_OR_CANCEL

	; Check if user edited input to a FAT specification (U: or U<unit>:)
	CALL	CHECK_FAT_INPUT_OPEN
	JP	C,SHOW_INLINE_OPEN_ERROR
	JP	NZ,HANDLE_OPEN_FAT_DISPATCH

	; Check if user edited input to a drive specification (e.g. "B:")
	CALL	CHECK_DRIVE_SWITCH
	JP	C,HANDLE_OPEN_DRIVE_SWITCH

	; Check if user edited input to a filter pattern (e.g. "*.TXT")
	CALL	CHECK_FILTER_PATTERN
	JP	C,HANDLE_OPEN_FILTER

	; If currently browsing a FAT volume, handle relative navigation/open
	LD	A,(CURRENT_DIR_IS_FAT)
	OR	A
	JP	NZ,HANDLE_OPEN_FAT_RELATIVE

	JP	DO_PARSE_AND_LOAD

CHECK_PAGING_OR_CANCEL:
	; A = return code: 0 = Cancel (ESC), 1 = Next Page (PgDn), 3 = Prev Page (PgUp)
	CP	1
	JR	Z,DO_NEXT_PAGE
	CP	3
	JR	Z,DO_PREV_PAGE
	XOR	A
	LD	(IS_PLUGIN_LOAD_UI),A
	LD	(IS_SPLASH_SCREEN),A
	CALL	RESTORE_DOC_USER
	LD	HL,0FFFFH
	LD	(CACHE_START_ROW),HL
	SCF				; Carry = 1 (Cancelled)
	RET				; Cancelled -> return to caller

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
; DO_PARSE_AND_LOAD_PLUGIN:
; Load plugin from INPUT_FILENAME_BUF into next available plugin slot.
; Returns to Plugin Manager on success, or displays inline error on failure.
;------------------------------------------------------------------------------
DO_PARSE_AND_LOAD_PLUGIN:
	LD	DE,INPUT_FILENAME_BUF
	CALL	LOAD_PLUGIN_BY_NAME
	JR	C,OPEN_PLUGIN_FAIL

	; Success: clear flags, restore user area, and return to caller
	PUSH	AF			; Preserve return A (slot number) & Carry
	XOR	A
	LD	(IS_PLUGIN_LOAD_UI),A
	LD	(IS_SPLASH_SCREEN),A
	CALL	RESTORE_DOC_USER
	LD	HL,0FFFFH
	LD	(CACHE_START_ROW),HL
	POP	AF			; Restore return A (slot number) & Carry
	RET

OPEN_PLUGIN_FAIL:
	CALL	RESTORE_DOC_USER
	LD	DE,STR_FNF_INLINE
	LD	C,16			; length of message
	JP	SHOW_INLINE_OPEN_ERROR

;------------------------------------------------------------------------------
; Block Insert File UI & Execution Subsystem
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; DO_PARSE_AND_INSERT:
; Parse filename from INPUT_FILENAME_BUF into INSERT_FCB, verify file existence,
; restore document WORK_FCB, perform insertion, and return to editor mode.
;------------------------------------------------------------------------------
DO_PARSE_AND_INSERT:
	; User entered a filename in INPUT_FILENAME_BUF: parse into WORK_FCB
	LD	DE,INPUT_FILENAME_BUF
	CALL	PARSE_FILENAME_TO_FCB

	; Check if target drive is unavailable RAM drive
	LD	A,(WORK_FCB)
	CALL	CHECK_TARGET_DRIVE_UNAVAILABLE
	JP	C,OPEN_RAMDRV_UNAVAILABLE

	; Copy parsed FCB to INSERT_FCB
	LD	HL,WORK_FCB
	LD	DE,INSERT_FCB
	LD	BC,36
	LDIR

	; Save WORK_FCB_USER into BLOCK_IO_USER
	LD	A,(WORK_FCB_USER)
	LD	(BLOCK_IO_USER),A

	; Restore original document WORK_FCB from DIR_TEMP_FCB
	LD	HL,DIR_TEMP_FCB
	LD	DE,WORK_FCB
	LD	BC,36
	LDIR

	; Restore WORK_FCB_USER from DOC_USER_NUM
	LD	A,(DOC_USER_NUM)
	LD	(WORK_FCB_USER),A

	; Set BDOS user area to BLOCK_IO_USER
	LD	A,(BLOCK_IO_USER)
	LD	E,A
	LD	C,32			; BDOS Set User Area
	CALL	BDOS_ENTRY

	; Probe and open INSERT_FCB
	CALL	PROBE_INSERT_FILE
	JR	NC,DPAI_PROBE_OK

	; Probe failed: restore BDOS user area to CURRENT_DIR_USER
	LD	A,(CURRENT_DIR_USER)
	LD	E,A
	LD	C,32			; BDOS Set User Area
	CALL	BDOS_ENTRY
	JP	OPEN_FILE_NOT_FOUND

DPAI_PROBE_OK:
	; Setup loading UI for block insert
	LD	A,(HAS_FILE_ARG)
	LD	(SAVED_HAS_FILE_ARG),A

	; Display inserted file name in status bar
	LD	HL,INSERT_FCB
	LD	DE,WORK_FCB
	LD	BC,36
	LDIR

	LD	A,1
	LD	(HAS_FILE_ARG),A
	LD	(IS_LOADING_FILE),A
	XOR	A
	LD	(IS_SPLASH_SCREEN),A
	LD	(INSERT_LINE_HAD_CHARS),A
	LD	HL,0
	LD	(LOAD_PROGRESS_LINES),HL
	LD	A,100
	LD	(LOAD_PROGRESS_COUNT),A

	CALL	DRAW_LOADING_SCREEN

	; Perform Block Insert
	CALL	DO_PERFORM_BLOCK_INSERT

DPAI_CLEANUP:
	; Restore original document WORK_FCB from DIR_TEMP_FCB
	LD	HL,DIR_TEMP_FCB
	LD	DE,WORK_FCB
	LD	BC,36
	LDIR

	; Restore original HAS_FILE_ARG
	LD	A,(SAVED_HAS_FILE_ARG)
	LD	(HAS_FILE_ARG),A

	; Insertion complete: clear insert flag, loading flag, and splash flag
	XOR	A
	LD	(BLOCK_INSERT_IS_FAT),A
	LD	(IS_BLOCK_INSERT_UI),A
	LD	(IS_LOADING_FILE),A
	LD	(IS_SPLASH_SCREEN),A
	LD	(NEED_SCREEN_RENDER),A
	LD	(NEED_LINE_RENDER),A
	LD	(NEED_STATUS_RENDER),A

	; Restore BDOS user area to CURRENT_DIR_USER
	LD	A,(CURRENT_DIR_USER)
	LD	E,A
	LD	C,32			; BDOS Set User Area
	CALL	BDOS_ENTRY

	; Reset stack and resume editor mode
	LD	SP,LOCAL_STACK
	CALL	TERM_INIT
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	JP	MAIN_LOOP

;------------------------------------------------------------------------------
; PROBE_INSERT_FILE: Check if INSERT_FCB exists and can be opened
; Returns: Carry = 0 on success (INSERT_FCB open, CR initialized to 0)
;          Carry = 1 on failure (file not found or conflict)
;------------------------------------------------------------------------------
PROBE_INSERT_FILE:
	LD	DE,DEFAULT_DMA
	LD	C,26			; BDOS Set DMA (0080H)
	CALL	BDOS_ENTRY

	; Check if INSERT_FCB targets hibernated RAM drive
	LD	A,(RAMDRIVE_IS_HIBERNATED)
	OR	A
	JR	Z,PIF_RAM_OK
	LD	A,(RAMDRIVE_DRIVE_NUM)
	CP	0FFH
	JR	Z,PIF_RAM_OK
	LD	B,A			; B = RAM drive number (0-based)
	LD	A,(INSERT_FCB)
	OR	A
	JR	NZ,PIF_EXPLICIT
	LD	A,(CURRENT_DEFAULT_DRIVE)
	JR	PIF_COMPARE
PIF_EXPLICIT:
	DEC	A			; 1->0, 2->1
PIF_COMPARE:
	CP	B
	JR	NZ,PIF_RAM_OK
	SCF				; Carry = 1: conflict
	RET

PIF_RAM_OK:
	; Check if filename is empty / spaces
	LD	A,(INSERT_FCB+1)
	CP	' '
	SCF
	RET	Z
	OR	A
	SCF
	RET	Z

	; Zero FCB extent, s1, s2, rc, and record bytes
	LD	HL,INSERT_FCB+12
	LD	(HL),0
	LD	DE,INSERT_FCB+13
	LD	BC,23
	LDIR

	; Open file via BDOS 15
	LD	DE,INSERT_FCB
	LD	C,15			; BDOS Open File
	CALL	BDOS_ENTRY
	CP	0FFH
	JR	NZ,PIF_OPEN_OK
	SCF
	RET

PIF_OPEN_OK:
	XOR	A
	LD	(INSERT_FCB+32),A	; Clear CR (Current Record)
	OR	A			; Carry = 0: success
	RET

;------------------------------------------------------------------------------
; DO_PERFORM_BLOCK_INSERT:
; Inserts the contents of INSERT_FCB into the document at the block insertion point.
; If block is non-empty: deletes the block first via DO_DELETE_BLOCK.
; If block is empty: cancels block selection.
; Slices host line at insertion point, streams INSERT_FCB records, concatenates
; lines, and positions cursor immediately after the inserted text.
;------------------------------------------------------------------------------
DO_PERFORM_BLOCK_INSERT:
	; Check if block is empty:
	; BLOCK_START_ROW == BLOCK_END_ROW and BLOCK_START_COL == BLOCK_END_COL
	LD	HL,(BLOCK_START_ROW)
	LD	DE,(BLOCK_END_ROW)
	LD	A,H
	CP	D
	JR	NZ,DPBI_NON_EMPTY
	LD	A,L
	CP	E
	JR	NZ,DPBI_NON_EMPTY
	LD	HL,(BLOCK_START_COL)
	LD	DE,(BLOCK_END_COL)
	LD	A,H
	CP	D
	JR	NZ,DPBI_NON_EMPTY
	LD	A,L
	CP	E
	JR	NZ,DPBI_NON_EMPTY

	; Block is empty: cancel block selection, ensure cursor is at insertion point
	CALL	CANCEL_BLOCK
	LD	HL,(BLOCK_START_ROW)
	LD	(CUR_DOC_ROW),HL
	LD	HL,(BLOCK_START_COL)
	LD	(CUR_COL),HL
	JR	DPBI_SPLIT_HOST

DPBI_NON_EMPTY:
	; Non-empty block: DO_DELETE_BLOCK deletes selected text,
	; clears BLOCK_ACTIVE, and sets (CUR_DOC_ROW, CUR_COL) = (BLOCK_START_ROW, BLOCK_START_COL)
	CALL	DO_DELETE_BLOCK
	LD	HL,(BLOCK_START_ROW)
	LD	(CUR_DOC_ROW),HL
	LD	HL,(BLOCK_START_COL)
	LD	(CUR_COL),HL

DPBI_SPLIT_HOST:
	; Ensure CUR_DOC_ROW is checked out in ACTIVE_LINE_BUF
	CALL	CHECKOUT_ACTIVE_LINE

	; Clamp CUR_COL to line length
	CALL	GET_CUR_ROW_LEN		; DE = line byte length
	LD	HL,(CUR_COL)
	CALL	CMP_HL_DE		; Carry=1 if CUR_COL < DE
	JR	C,DPBI_COL_OK
	LD	(CUR_COL),DE
DPBI_COL_OK:
	; Record insertion start position
	LD	HL,(CUR_DOC_ROW)
	LD	(INSERT_ORIG_START_ROW),HL
	LD	HL,(CUR_COL)
	LD	(INSERT_ORIG_START_COL),HL

	; Split ACTIVE_LINE_BUF at CUR_COL:
	; Copy suffix (from CUR_COL to null) into SPLIT_LINE_TEMP
	LD	HL,ACTIVE_LINE_BUF
	LD	DE,(CUR_COL)
	ADD	HL,DE			; HL = split point in ACTIVE_LINE_BUF
	LD	DE,SPLIT_LINE_TEMP
DPBI_SPLIT_LOOP:
	LD	A,(HL)
	LD	(DE),A
	LD	(HL),0			; Truncate current line at split point
	INC	HL
	INC	DE
	OR	A
	JR	NZ,DPBI_SPLIT_LOOP

	; Host prefix remains in ACTIVE_LINE_BUF with length (CUR_COL)
	LD	HL,(CUR_COL)
	LD	(INSERT_CUR_LEN),HL

	; Detach ACTIVE_LINE_ROW so active line system won't auto-commit scratch buffer
	LD	HL,0FFFFH
	LD	(ACTIVE_LINE_ROW),HL
	XOR	A
	LD	(ACTIVE_LINE_DIRTY),A

	LD	A,1
	LD	(INSERT_IS_FIRST_LINE),A
	XOR	A
	LD	(SEEN_CR),A

	; Stream sectors from INSERT_FCB (or FAT stream)
DPBI_READ_SECTOR:
	LD	A,(BLOCK_INSERT_IS_FAT)
	OR	A
	JR	NZ,DPBI_READ_FAT_CHUNK

	LD	DE,DEFAULT_DMA
	LD	C,26			; BDOS Set DMA (0080H)
	CALL	BDOS_ENTRY

	LD	DE,INSERT_FCB
	LD	C,20			; BDOS Read Next Record
	CALL	BDOS_ENTRY
	OR	A
	JP	NZ,DPBI_HIT_EOF		; EOF or read error

	LD	HL,DEFAULT_DMA
	LD	B,128			; 128 bytes per sector
	JR	DPBI_BYTE_LOOP

DPBI_READ_FAT_CHUNK:
	LD	A,6			; VFS_CMD_READ_CHUNK
	LD	(VFS_REQ_CMD),A
	XOR	A
	LD	(VFS_REQ_STATUS),A
	LD	HL,FAT_CHUNK_BUF
	LD	(VFS_REQ_BUFFER),HL
	LD	HL,128
	LD	(VFS_REQ_BUFSIZE),HL
	CALL	VFS_EXEC_REQUEST
	JR	C,DPBI_FAT_EOF
	LD	A,(VFS_REQ_STATUS)
	CP	6			; VFS_STAT_EOF
	JR	Z,DPBI_FAT_EOF
	OR	A
	JR	NZ,DPBI_FAT_EOF		; Error -> EOF
	LD	HL,(VFS_REQ_COUNT)
	LD	A,L
	OR	H
	JR	Z,DPBI_FAT_EOF
	LD	B,L			; B = bytes read (1..128)
	LD	HL,FAT_CHUNK_BUF
	JR	DPBI_BYTE_LOOP

DPBI_FAT_EOF:
	; Close FAT stream
	LD	A,7			; VFS_CMD_CLOSE_FILE
	LD	(VFS_REQ_CMD),A
	CALL	VFS_EXEC_REQUEST
	JP	DPBI_HIT_EOF
DPBI_BYTE_LOOP:
	PUSH	BC
	PUSH	HL
	LD	A,(HL)

	; Check EOF markers (0 or 26 = ^Z)
	OR	A
	JR	Z,DPBI_POP_AND_EOF
	CP	26			; CP/M ^Z
	JR	Z,DPBI_POP_AND_EOF

	; Check CR (13)
	CP	13
	JR	Z,DPBI_HANDLE_CR

	; Check LF (10)
	CP	10
	JR	Z,DPBI_HANDLE_LF

	; Regular character (including Tab 0x09)
	; If SEEN_CR was 1, we have a bare CR preceding this char!
	PUSH	AF
	LD	A,(SEEN_CR)
	OR	A
	JR	Z,DPBI_NO_BARE_CR
	XOR	A
	LD	(SEEN_CR),A
	CALL	PBI_EMIT_LINE_BREAK
	JR	C,DPBI_POP2_AND_EOF	; OOM on line break
DPBI_NO_BARE_CR:
	POP	AF

	; Append character A to ACTIVE_LINE_BUF
	CALL	PBI_APPEND_CHAR

DPBI_NEXT_BYTE:
	POP	HL
	POP	BC
	INC	HL
	DJNZ	DPBI_BYTE_LOOP
	JP	DPBI_READ_SECTOR

DPBI_POP2_AND_EOF:
	POP	AF
DPBI_POP_AND_EOF:
	POP	HL
	POP	BC
	JP	DPBI_HIT_EOF

DPBI_HANDLE_CR:
	LD	A,(SEEN_CR)
	OR	A
	JR	Z,DPBI_SET_CR
	CALL	PBI_EMIT_LINE_BREAK
	JR	C,DPBI_POP_AND_EOF
DPBI_SET_CR:
	LD	A,1
	LD	(SEEN_CR),A
	JR	DPBI_NEXT_BYTE

DPBI_HANDLE_LF:
	XOR	A
	LD	(SEEN_CR),A
	CALL	PBI_EMIT_LINE_BREAK
	JR	C,DPBI_POP_AND_EOF
	JR	DPBI_NEXT_BYTE

DPBI_HIT_EOF:
	; If SEEN_CR is still 1 at EOF (trailing bare CR), emit line break
	LD	A,(SEEN_CR)
	OR	A
	JR	Z,DPBI_FINISH_EOF
	XOR	A
	LD	(SEEN_CR),A
	CALL	PBI_EMIT_LINE_BREAK

DPBI_FINISH_EOF:
	; Final progress update for inserted file
	LD	A,(INSERT_LINE_HAD_CHARS)
	OR	A
	JR	Z,DPBI_NO_FINAL_INC
	LD	HL,(LOAD_PROGRESS_LINES)
	INC	HL
	LD	(LOAD_PROGRESS_LINES),HL
DPBI_NO_FINAL_INC:
	CALL	UPDATE_LOAD_PROGRESS

	; Record cursor position (column right after inserted text)
	LD	HL,(INSERT_CUR_LEN)
	LD	(INSERT_NEW_CUR_COL),HL

	; Append SPLIT_LINE_TEMP (saved host line suffix) to ACTIVE_LINE_BUF
	LD	DE,SPLIT_LINE_TEMP
DPBI_APPEND_SUFFIX:
	LD	A,(DE)
	OR	A
	JR	Z,DPBI_SUFFIX_DONE
	CALL	PBI_APPEND_CHAR
	INC	DE
	JR	DPBI_APPEND_SUFFIX

DPBI_SUFFIX_DONE:
	; Write final ACTIVE_LINE_BUF to CUR_DOC_ROW
	LD	BC,(CUR_DOC_ROW)
	LD	HL,ACTIVE_LINE_BUF
	CALL	WRITE_FAR_LINE

	; Set cursor column
	LD	HL,(INSERT_NEW_CUR_COL)
	LD	(CUR_COL),HL
	LD	(TARGET_COL),HL

	; Close INSERT_FCB (or FAT stream)
	LD	A,(BLOCK_INSERT_IS_FAT)
	OR	A
	JR	NZ,DPBI_CLOSE_FAT
	LD	DE,INSERT_FCB
	LD	C,16			; BDOS Close File
	CALL	BDOS_ENTRY
	JR	DPBI_SKIP_FCB_CLOSE
DPBI_CLOSE_FAT:
	LD	A,7			; VFS_CMD_CLOSE_FILE
	LD	(VFS_REQ_CMD),A
	CALL	VFS_EXEC_REQUEST
DPBI_SKIP_FCB_CLOSE:

	; Mark document modified
	LD	A,1
	LD	(DOC_MODIFIED),A

	; Invalidate active line and reload cache
	CALL	INVALIDATE_ACTIVE_LINE
	CALL	FLUSH_DIRTY_CACHE
	CALL	RELOAD_CACHE_WINDOW_FORCE
	CALL	CHECKOUT_ACTIVE_LINE
	CALL	CALC_VISUAL_COL
	LD	(TARGET_COL),HL

	; If inserted text is non-empty, solidify block around inserted text
	LD	HL,(INSERT_ORIG_START_ROW)
	LD	DE,(CUR_DOC_ROW)
	LD	A,H
	CP	D
	JR	NZ,DPBI_SET_SOLID_BLOCK
	LD	A,L
	CP	E
	JR	NZ,DPBI_SET_SOLID_BLOCK
	LD	HL,(INSERT_ORIG_START_COL)
	LD	DE,(INSERT_NEW_CUR_COL)
	LD	A,H
	CP	D
	JR	NZ,DPBI_SET_SOLID_BLOCK
	LD	A,L
	CP	E
	JR	Z,DPBI_NO_BLOCK		; Start == End: 0 bytes inserted, no block

DPBI_SET_SOLID_BLOCK:
	LD	HL,(INSERT_ORIG_START_ROW)
	LD	(BLOCK_START_ROW),HL
	LD	(BLOCK_ANCHOR_ROW),HL
	LD	HL,(INSERT_ORIG_START_COL)
	LD	(BLOCK_START_COL),HL
	LD	(BLOCK_ANCHOR_COL),HL
	LD	HL,(CUR_DOC_ROW)
	LD	(BLOCK_END_ROW),HL
	LD	HL,(INSERT_NEW_CUR_COL)
	LD	(BLOCK_END_COL),HL
	LD	A,2
	LD	(BLOCK_ACTIVE),A

DPBI_NO_BLOCK:
	; Adjust viewport (both vertical and horizontal)
	CALL	ADJUST_INSERT_VIEWPORT
	RET

;------------------------------------------------------------------------------
; PBI_APPEND_CHAR:
; Append character in register A to ACTIVE_LINE_BUF if within line limit.
; Updates INSERT_CUR_LEN and maintains null terminator.
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
PBI_APPEND_CHAR:
	PUSH	HL
	PUSH	DE
	LD	HL,(INSERT_CUR_LEN)
	LD	DE,MAX_INPUT_LINE_CHARS - 1	; 999
	OR	A
	SBC	HL,DE
	JR	NC,PAC_DONE			; If >= 999, ignore char
	LD	HL,ACTIVE_LINE_BUF
	LD	DE,(INSERT_CUR_LEN)
	ADD	HL,DE
	LD	(HL),A				; Store char
	INC	HL
	LD	(HL),0				; Maintain null terminator
	LD	HL,(INSERT_CUR_LEN)
	INC	HL
	LD	(INSERT_CUR_LEN),HL
	LD	A,1
	LD	(INSERT_LINE_HAD_CHARS),A
PAC_DONE:
	POP	DE
	POP	HL
	RET

;------------------------------------------------------------------------------
; PBI_EMIT_LINE_BREAK:
; Writes current ACTIVE_LINE_BUF to CUR_DOC_ROW, allocates slot for CUR_DOC_ROW + 1,
; shifts lower slots downwards, advances CUR_DOC_ROW, and resets ACTIVE_LINE_BUF.
; Returns: Carry = 0 on success, Carry = 1 on OOM
; Preserves: BC, DE, HL
;------------------------------------------------------------------------------
PBI_EMIT_LINE_BREAK:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	; Check max document lines
	LD	HL,(DOC_TOTAL_LINES)
	LD	DE,(MAX_DOC_LINES_LIMIT)
	OR	A
	SBC	HL,DE
	JP	NC,PELB_OOM

	; Allocate slot for new line
	CALL	ALLOC_SLOT		; HL = new_slot_id, Carry on OOM
	JP	C,PELB_OOM
	PUSH	HL			; Save new_slot_id

	; Write current line in ACTIVE_LINE_BUF to CUR_DOC_ROW
	LD	BC,(CUR_DOC_ROW)
	LD	HL,ACTIVE_LINE_BUF
	CALL	WRITE_FAR_LINE

	; Shift line slots downwards from CUR_DOC_ROW + 1 to DOC_TOTAL_LINES - 1
	; Number of entries to shift: W = DOC_TOTAL_LINES - (CUR_DOC_ROW + 1)
	LD	HL,(DOC_TOTAL_LINES)
	LD	DE,(CUR_DOC_ROW)
	INC	DE			; DE = P = CUR_DOC_ROW + 1
	AND	A
	SBC	HL,DE			; HL = W = DOC_TOTAL_LINES - P
	JR	Z,PELB_NO_SHIFT
	JR	C,PELB_NO_SHIFT

	LD	B,H
	LD	C,L			; BC = W
	LD	HL,(CUR_DOC_ROW)
	INC	HL			; HL = source line = CUR_DOC_ROW + 1
	LD	DE,(CUR_DOC_ROW)
	INC	DE
	INC	DE			; DE = dest line = CUR_DOC_ROW + 2
	CALL	SHIFT_LINE_SLOTS_DOWN

PELB_NO_SHIFT:
	; Store new_slot_id into line table at CUR_DOC_ROW + 1
	POP	DE			; DE = new_slot_id
	LD	HL,(CUR_DOC_ROW)
	INC	HL
	LD	B,H
	LD	C,L			; BC = CUR_DOC_ROW + 1
	EX	DE,HL			; HL = new_slot_id
	CALL	SET_LINE_SLOT

	; Increment DOC_TOTAL_LINES
	LD	HL,(DOC_TOTAL_LINES)
	INC	HL
	LD	(DOC_TOTAL_LINES),HL

	; Advance CUR_DOC_ROW
	LD	HL,(CUR_DOC_ROW)
	INC	HL
	LD	(CUR_DOC_ROW),HL

	; Reset ACTIVE_LINE_BUF to empty
	XOR	A
	LD	(ACTIVE_LINE_BUF),A
	LD	HL,0
	LD	(INSERT_CUR_LEN),HL
	LD	(INSERT_IS_FIRST_LINE),A
	LD	(INSERT_LINE_HAD_CHARS),A

	; Increment LOAD_PROGRESS_LINES
	LD	HL,(LOAD_PROGRESS_LINES)
	INC	HL
	LD	(LOAD_PROGRESS_LINES),HL

	; Check 100-line progress interval
	LD	A,(LOAD_PROGRESS_COUNT)
	DEC	A
	LD	(LOAD_PROGRESS_COUNT),A
	JR	NZ,PBIL_NO_TICK
	LD	A,100
	LD	(LOAD_PROGRESS_COUNT),A
	CALL	UPDATE_LOAD_PROGRESS
PBIL_NO_TICK:

	POP	HL
	POP	DE
	POP	BC
	OR	A			; Carry = 0
	RET

PELB_OOM:
	CALL	SET_OOM_STATUS
	POP	HL
	POP	DE
	POP	BC
	SCF				; Carry = 1
	RET

;------------------------------------------------------------------------------
; ADJUST_INSERT_VIEWPORT:
; Adjust TOP_DOC_ROW and VIEW_LEFT_COL to keep cursor visible.
;------------------------------------------------------------------------------
ADJUST_INSERT_VIEWPORT:
	; Check if CUR_DOC_ROW < TOP_DOC_ROW
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(TOP_DOC_ROW)
	CALL	CMP_HL_DE		; Carry=1 if CUR_DOC_ROW < TOP_DOC_ROW
	JR	NC,AIV_CHECK_BOTTOM
	LD	HL,(CUR_DOC_ROW)
	LD	(TOP_DOC_ROW),HL
	JR	AIV_CHECK_HORIZ

AIV_CHECK_BOTTOM:
	; Check if CUR_DOC_ROW - TOP_DOC_ROW >= ACTIVE_ROWS - 2
	LD	HL,(CUR_DOC_ROW)
	LD	DE,(TOP_DOC_ROW)
	AND	A
	SBC	HL,DE
	LD	A,H
	OR	A
	JR	NZ,AIV_DO_SCROLL_DOWN
	LD	A,(ACTIVE_ROWS)
	DEC	A
	DEC	A
	CP	L
	JR	NC,AIV_CHECK_HORIZ
AIV_DO_SCROLL_DOWN:
	LD	A,(ACTIVE_ROWS)
	DEC	A
	DEC	A
	LD	E,A
	LD	D,0
	LD	HL,(CUR_DOC_ROW)
	AND	A
	SBC	HL,DE
	LD	(TOP_DOC_ROW),HL

AIV_CHECK_HORIZ:
	CALL	ADJUST_HORIZ_VIEWPORT
	RET

;------------------------------------------------------------------------------
; Show Editor Mode Keys Screen (Ctrl+K)
; Displays summary of all SE editor keys and waits for any key to return.
;------------------------------------------------------------------------------
HELP_LINES	EQU	22

SHOW_HELP_KEYS_UI:
	LD	A,1
	LD	(IS_SPLASH_SCREEN),A
	CALL	RENDER_HELP_SCREEN_STATIC
HELP_KEY_LOOP:
	CALL	GET_KEY
	CP	KEY_CTRL_P
	JR	NZ,HELP_NOT_CTRL_P
	LD	A,PLUG_CTX_HELP
	CALL	DO_CONTEXT_PLUGIN_POPUP
	JR	HELP_KEY_LOOP
HELP_NOT_CTRL_P:
	CP	KEY_ESC
	CALL	Z,DRAIN_ESC_SEQUENCE
	XOR	A
	LD	(IS_SPLASH_SCREEN),A
	RET

RENDER_HELP_SCREEN_STATIC:
	LD	DE,STR_HIDE_CURSOR
	CALL	PRINT_STR
	LD	DE,STR_CLEAR_SCREEN
	CALL	PRINT_STR

	; 1. Row 1: Horizontal Rule
	CALL	PRINT_HR_EQUAL

	; 2. Row 2: Centered Title
	CALL	RENDER_HELP_TITLE

	; 3. Row 3: Horizontal Rule
	CALL	PRINT_HR_EQUAL

	; 4. Rows 4..20: Help Key Descriptions (17 lines)
	LD	DE,STR_HELP_BODY
	CALL	PRINT_STR

	; 5. Row 21: Horizontal Dash Rule
	CALL	PRINT_HR_DASH

	; 6. Row 22: Centered Return Prompt
	CALL	RENDER_HELP_FOOTER

	; Fill remaining rows down to status row with '~'
	LD	A,(ACTIVE_ROWS)
	DEC	A			; A = ACTIVE_ROWS - 1 (last text row)
	SUB	HELP_LINES		; A = remaining rows
	JR	Z,HELP_TILDE_DONE
	JR	C,HELP_TILDE_DONE
	LD	B,A
HELP_TILDE_LOOP:
	LD	A,'~'
	CALL	PUTC
	LD	A,13
	CALL	PUTC
	LD	A,10
	CALL	PUTC
	DJNZ	HELP_TILDE_LOOP

HELP_TILDE_DONE:
	CALL	RENDER_STATUS_BAR
	LD	DE,STR_HOME
	CALL	PRINT_STR
	LD	DE,STR_HIDE_CURSOR
	CALL	PRINT_STR
	RET

;------------------------------------------------------------------------------
; Render Ctrl+K Help Title (Row 2):
; Emits '~' followed by ((ACTIVE_COLS - 25) / 2 - 1) spaces and STR_HELP_TITLE.
;------------------------------------------------------------------------------
RENDER_HELP_TITLE:
	LD	A,'~'
	CALL	PUTC
	LD	A,(ACTIVE_COLS)
	SUB	25
	SRL	A
	DEC	A
	LD	B,A
RHT_PAD_LOOP:
	LD	A,' '
	CALL	PUTC
	DJNZ	RHT_PAD_LOOP
	LD	DE,STR_HELP_TITLE
	CALL	PRINT_STR
	RET

;------------------------------------------------------------------------------
; Render Ctrl+K Help Footer (Row 22):
; Emits '~' followed by ((ACTIVE_COLS - 36) / 2 - 1) spaces and STR_HELP_RETURN_PROMPT.
;------------------------------------------------------------------------------
RENDER_HELP_FOOTER:
	LD	A,'~'
	CALL	PUTC
	LD	A,(ACTIVE_COLS)
	SUB	36
	SRL	A
	DEC	A
	LD	B,A
RHF_PAD_LOOP:
	LD	A,' '
	CALL	PUTC
	DJNZ	RHF_PAD_LOOP
	LD	DE,STR_HELP_RETURN_PROMPT
	CALL	PRINT_STR
	RET

;------------------------------------------------------------------------------
; Save File Screen with Sorted Directory Listing, Pre-filling & Overwrite Check
;------------------------------------------------------------------------------
DO_SAVE_FILE_UI:
	LD	A,(FILE_IS_TRUNCATED)
	OR	A
	JR	Z,DO_SAVE_FILE_OK
	CALL	SHOW_TRUNCATED_SAVE_BLOCKED
	RET

DO_SAVE_FILE_OK:
	; Invalidate active line and flush dirty cache before directory collection
	; overlays LINE_STORAGE
	CALL	INVALIDATE_ACTIVE_LINE
	CALL	FLUSH_DIRTY_CACHE
	LD	HL,0FFFFH
	LD	(CACHE_START_ROW),HL

	LD	A,1
	LD	(IS_SAVE_UI),A
	CALL	DO_SAVE_FILE_UI_IMPL
	XOR	A
	LD	(IS_SAVE_UI),A
	LD	HL,0FFFFH
	LD	(CACHE_START_ROW),HL
	RET

TRUNC_LINES	EQU	12

SHOW_TRUNCATED_SAVE_BLOCKED:
	LD	A,1
	LD	(IS_SPLASH_SCREEN),A
	LD	DE,STR_HIDE_CURSOR
	CALL	PRINT_STR
	LD	DE,STR_CLEAR_SCREEN
	CALL	PRINT_STR
	LD	DE,STR_TRUNC_SAVE_BLOCKED
	CALL	PRINT_STR

	; Fill remaining rows down to status row with '~'
	LD	A,(ACTIVE_ROWS)
	DEC	A			; A = ACTIVE_ROWS - 1
	SUB	TRUNC_LINES
	JR	Z,TRUNC_TILDE_DONE
	JR	C,TRUNC_TILDE_DONE
	LD	B,A
TRUNC_TILDE_LOOP:
	LD	A,'~'
	CALL	PUTC
	LD	A,13
	CALL	PUTC
	LD	A,10
	CALL	PUTC
	DJNZ	TRUNC_TILDE_LOOP

TRUNC_TILDE_DONE:
	CALL	RENDER_STATUS_BAR
	LD	DE,STR_HOME
	CALL	PRINT_STR
	LD	DE,STR_HIDE_CURSOR
	CALL	PRINT_STR
	CALL	GET_KEY
	CP	KEY_ESC
	CALL	Z,DRAIN_ESC_SEQUENCE
	XOR	A
	LD	(IS_SPLASH_SCREEN),A
	RET

;------------------------------------------------------------------------------
; CHECK_FILE_TRUNCATED_POPUP:
; Check if document was truncated on load; if so, display modal popup.
;------------------------------------------------------------------------------
CHECK_FILE_TRUNCATED_POPUP:
	LD	A,(FILE_IS_TRUNCATED)
	OR	A
	RET	Z

;------------------------------------------------------------------------------
; SHOW_FILE_TRUNCATED_POPUP:
; Displays centered modal pop-up alerting user that file was truncated on load.
; Dimensions: 50 columns wide x 7 rows high.
; Waits for any key, then restores screen and status bar.
;------------------------------------------------------------------------------
SHOW_FILE_TRUNCATED_POPUP:
	; 1. Calculate POPUP_COL = ((ACTIVE_COLS - 50) / 2) + 1
	LD	A,(ACTIVE_COLS)
	SUB	50
	SRL	A
	INC	A
	LD	(POPUP_COL),A

	; 2. Calculate POPUP_ROW = ((ACTIVE_ROWS - 7) / 2) + 1
	LD	A,(ACTIVE_ROWS)
	SUB	7
	SRL	A
	INC	A
	LD	(POPUP_ROW),A

	; 3. Hide cursor while drawing popup
	LD	DE,STR_HIDE_CURSOR
	CALL	PRINT_STR

	; 4. Render 7-line Pop-Up Box
	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	PRINT_STR

	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_TRUNC_TITLE
	CALL	PRINT_STR

	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	PRINT_STR

	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_TRUNC_MSG1
	CALL	PRINT_STR

	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_TRUNC_MSG2
	CALL	PRINT_STR

	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_TRUNC_KEY
	CALL	PRINT_STR

	CALL	POPUP_LOCATE_NEXT
	LD	DE,STR_POPUP_BORDER
	CALL	PRINT_STR

	; 5. Wait for any key
	CALL	GET_KEY
	CP	KEY_ESC
	CALL	Z,DRAIN_ESC_SEQUENCE

	; 6. Redraw editor screen and status bar
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	RET


DO_SAVE_FILE_UI_IMPL:
	; Initialize directory layout parameters based on active screen mode
	CALL	INIT_DIR_LAYOUT

	; Initialize active directory drive from default disk or WORK_FCB
	CALL	INIT_DIR_DRIVE

	; Filter defaults to all files shown unless explicitly provided in edit box
	CALL	RESET_DIR_FILTER

	; Initialize directory user area from current document user area
	LD	A,(DOC_USER_NUM)
	LD	(CURRENT_DIR_USER),A

	; Pre-fill filename if known (HAS_FILE_ARG == 1) and not Block Save
	LD	A,(IS_BLOCK_SAVE_UI)
	OR	A
	JR	NZ,DSUI_EMPTY_BUF
	LD	A,(HAS_FILE_ARG)
	OR	A
	JR	Z,DSUI_EMPTY_BUF
	LD	A,(DOC_IS_FAT)
	OR	A
	JR	NZ,DSUI_PREFILL_FAT_FILE
	CALL	FCB_TO_FILENAME_STR

	; Check if prefilled string explicitly contains a user area
	LD	HL,INPUT_FILENAME_BUF
	CALL	PARSE_DRIVE_USER_PREFIX
	JR	NC,DSUI_PREFILL_DONE
	LD	A,(PREFIX_USER)
	CP	0FFH
	JR	Z,DSUI_PREFILL_DONE
	LD	(CURRENT_DIR_USER),A
	JR	DSUI_PREFILL_DONE

DSUI_EMPTY_BUF:
	CALL	PRELOAD_DRIVE_USER_PREFIX
	JR	DSUI_PREFILL_DONE

DSUI_PREFILL_FAT_FILE:
	CALL	PREFILL_FAT_FILENAME_BUF

DSUI_PREFILL_DONE:

REFRESH_SAVE_DIR:
	; 1. Collect Directory Entries from CURRENT_DIR_DRIVE
	CALL	COLLECT_DIR_ENTRIES

	; 2. Sort Directory Entries Alphabetically
	CALL	SORT_DIR_ENTRIES

	; 3. Calculate Total Pages (using dynamic DIR_PAGE_CAPACITY)
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
	LD	HL,DIR_PAGE_CAPACITY
	LD	C,(HL)
DIV_PAGE_SAVE_LOOP:
	CP	C
	JR	C,DIV_PAGE_SAVE_DONE
	SUB	C
	INC	B
	JR	DIV_PAGE_SAVE_LOOP
DIV_PAGE_SAVE_DONE:
	INC	B
	LD	A,B
	LD	(DIR_PAGE_COUNT),A

RENDER_SAVE_PAGE:
	CALL	TERM_INIT
	LD	A,1
	LD	(IS_SPLASH_SCREEN),A
	CALL	RENDER_SAVE_TITLE

	; Display Directory Entries for Current Page
	CALL	DISPLAY_DIR_PAGE

	; Display Save Prompt & Page Indicator
	CALL	DISPLAY_SAVE_PROMPT

	; Finish prompt line and fill remaining rows down to status row with '~'
	CALL	FINISH_UI_PAGE_AND_STATUS

	; Read Filename Input (with prefilled string echoed)
	CALL	READ_FILENAME_INPUT_PREFILLED
	JP	C,CHECK_SAVE_PAGING_OR_CANCEL

	; Check if user typed a FAT specification (U: or U<unit>:)
	CALL	CHECK_FAT_INPUT_SAVE
	JP	C,SHOW_INLINE_SAVE_ERROR
	JP	NZ,HANDLE_SAVE_FAT_DISPATCH

	; Check if user typed a drive specification (e.g. "A:")
	CALL	CHECK_DRIVE_SWITCH
	JP	C,HANDLE_SAVE_DRIVE_SWITCH

	; Check if user typed a filter pattern (e.g. "*.TXT" or "B:*.TXT")
	CALL	CHECK_FILTER_PATTERN
	JP	C,HANDLE_SAVE_FILTER

	; If currently browsing a FAT volume, handle relative navigation/save
	LD	A,(CURRENT_DIR_IS_FAT)
	OR	A
	JP	NZ,HANDLE_SAVE_FAT_RELATIVE

DO_PARSE_AND_SAVE:
	; User entered/confirmed a filename in INPUT_FILENAME_BUF:
	; Save current WORK_FCB to DIR_TEMP_FCB (36 bytes)
	LD	HL,WORK_FCB
	LD	DE,DIR_TEMP_FCB
	LD	BC,36
	LDIR

	; Parse entered filename into WORK_FCB
	CALL	PARSE_FILENAME_TO_FCB

	; Check if target drive is unavailable RAM drive
	LD	A,(WORK_FCB)
	CALL	CHECK_TARGET_DRIVE_UNAVAILABLE
	JR	C,SAVE_RAMDRV_UNAVAILABLE

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
	LD	A,(DOC_USER_NUM)
	LD	(WORK_FCB_USER),A

	LD	DE,STR_SAVE_CANCELLED
	CALL	PRINT_STR
	CALL	DELAY_BRIEF
	RET

DO_OVERWRITE_CONFIRMED:
	CALL	PUTC			; Echo 'y'

DO_ACTUAL_SAVE:
	LD	A,(IS_BLOCK_SAVE_UI)
	OR	A
	JR	NZ,DO_ACTUAL_BLOCK_SAVE

	; Save the file from Far RAM to disk
	CALL	SAVE_FILE
	RET	C			; Save failed / target hibernated -> return

	; Mark filename as known and saved
	LD	A,1
	LD	(HAS_FILE_ARG),A
	XOR	A
	LD	(DOC_MODIFIED),A
	LD	(DOC_IS_FAT),A
	RET

DO_ACTUAL_BLOCK_SAVE:
	CALL	SAVE_BLOCK_FILE
	; Restore original document WORK_FCB from DIR_TEMP_FCB
	LD	HL,DIR_TEMP_FCB
	LD	DE,WORK_FCB
	LD	BC,36
	LDIR
	LD	A,(DOC_USER_NUM)
	LD	(WORK_FCB_USER),A
	RET

SAVE_RAMDRV_UNAVAILABLE:
	; Restore previous WORK_FCB from DIR_TEMP_FCB
	LD	HL,DIR_TEMP_FCB
	LD	DE,WORK_FCB
	LD	BC,36
	LDIR
	LD	A,(DOC_USER_NUM)
	LD	(WORK_FCB_USER),A

	; Display inline "  RAM drive not available"
	LD	DE,STR_RAMDRV_UNAVAIL_INLINE
	LD	A,25

SHOW_INLINE_SAVE_ERROR:
	LD	(INLINE_MSG_LEN),A

	; Move cursor past ']' box before printing error message
	LD	A,(INPUT_BUF_LEN)
	LD	B,A
	LD	A,21
	SUB	B
	JR	Z,SRU_FWD_DONE
	LD	B,A			; B = 21 - INPUT_BUF_LEN
SRU_FWD_LOOP:
	PUSH	BC
	PUSH	DE
	LD	DE,STR_CSI_C		; ESC [ C
	CALL	PRINT_STR
	POP	DE
	POP	BC
	DJNZ	SRU_FWD_LOOP
SRU_FWD_DONE:

	CALL	PRINT_STR

	; Set flag that inline message is currently visible
	LD	A,1
	LD	(SHOWING_FNF_MSG),A

	; Resume input loop without blanking filename in text box
	CALL	RESUME_FILENAME_INPUT
	JP	C,CHECK_SAVE_PAGING_OR_CANCEL

	; Check if user typed a FAT specification (U: or U<unit>:)
	CALL	CHECK_FAT_INPUT_SAVE
	JP	C,SHOW_INLINE_SAVE_ERROR
	JP	NZ,HANDLE_SAVE_FAT_DISPATCH

	; Check if user edited input to a drive specification (e.g. "B:")
	CALL	CHECK_DRIVE_SWITCH
	JR	C,HANDLE_SAVE_DRIVE_SWITCH

	; Check if user edited input to a filter pattern (e.g. "*.TXT")
	CALL	CHECK_FILTER_PATTERN
	JP	C,HANDLE_SAVE_FILTER

	; If currently browsing a FAT volume, handle relative navigation/save
	LD	A,(CURRENT_DIR_IS_FAT)
	OR	A
	JP	NZ,HANDLE_SAVE_FAT_RELATIVE

	JP	DO_PARSE_AND_SAVE

HANDLE_SAVE_DRIVE_SWITCH:
	; A = new drive (1..16 or 0), C = new user (0..15 or 0xFF)
	PUSH	BC			; Save target user
	OR	A
	JR	Z,HSDS_DRIVE_DONE	; Drive unchanged

	CALL	CHECK_TARGET_DRIVE_UNAVAILABLE
	JR	NC,HSDS_DRIVE_OK

	; Cannot switch to unavailable RAM drive!
	POP	BC
	JR	SAVE_RAMDRV_UNAVAILABLE

HSDS_DRIVE_OK:
	LD	(CURRENT_DIR_DRIVE),A
	ADD	A,'A'-1
	LD	(STR_SAVE_DRIVE_CHAR),A
	XOR	A
	LD	(CURRENT_DIR_IS_FAT),A

HSDS_DRIVE_DONE:
	POP	BC			; C = target user
	LD	A,C
	CP	0FFH
	JR	Z,HSDS_USER_DEFAULT_ZERO
	LD	(CURRENT_DIR_USER),A
	JR	HSDS_RESET_FILTER
HSDS_USER_DEFAULT_ZERO:
	XOR	A
	LD	(CURRENT_DIR_USER),A

HSDS_RESET_FILTER:
	; A drive/user switch without wildcard defaults to all files shown
	CALL	RESET_DIR_FILTER
	JP	REFRESH_SAVE_DIR

HANDLE_SAVE_FILTER:
	JP	REFRESH_SAVE_DIR

CHECK_SAVE_PAGING_OR_CANCEL:
	; A = return code: 0 = Cancel (ESC), 1 = Next Page (PgDn), 2 = Format Toggled (Ctrl-F), 3 = Prev Page (PgUp)
	CP	2
	JP	Z,RENDER_SAVE_PAGE	; Redraw save page with new format and prefilled input
	CP	1
	JR	Z,DO_SAVE_NEXT_PAGE
	CP	3
	JR	Z,DO_SAVE_PREV_PAGE
	CALL	RESTORE_DOC_USER
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
	; Set BDOS user area to WORK_FCB_USER before probing
	LD	A,(WORK_FCB_USER)
	LD	E,A
	LD	C,32			; BDOS Set User Area
	CALL	BDOS_ENTRY

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

	; Restore BDOS user area to CURRENT_DIR_USER
	LD	A,(CURRENT_DIR_USER)
	LD	E,A
	LD	C,32			; BDOS Set User Area
	CALL	BDOS_ENTRY

	SCF				; Carry = 1 (file exists)
	RET

FILE_NOT_EXISTS:
	; Restore BDOS user area to CURRENT_DIR_USER
	LD	A,(CURRENT_DIR_USER)
	LD	E,A
	LD	C,32			; BDOS Set User Area
	CALL	BDOS_ENTRY

	OR	A			; Carry = 0 (file does not exist)
	RET

;------------------------------------------------------------------------------
; Initialize directory layout parameters based on active SCREEN_MODE:
;   80x24 mode: 5 columns per row, 60 files per page (12 rows x 5 cols, 15 chars/col)
;  120x40 mode: 7 columns per row, 196 files per page (28 rows x 7 cols, 16 chars/col)
;------------------------------------------------------------------------------
INIT_DIR_LAYOUT:
	LD	A,(SCREEN_MODE)
	CP	MODE_120X40
	JR	Z,IDL_120
	; 80x24 mode
	LD	A,5
	LD	(DIR_COLS_PER_ROW),A
	LD	A,15
	LD	(DIR_COL_WIDTH),A
	LD	A,60
	LD	(DIR_PAGE_CAPACITY),A
	RET
IDL_120:
	; 120x40 mode
	LD	A,7
	LD	(DIR_COLS_PER_ROW),A
	LD	A,16
	LD	(DIR_COL_WIDTH),A
	LD	A,196
	LD	(DIR_PAGE_CAPACITY),A
	RET

;------------------------------------------------------------------------------
; Print Full-Width Horizontal Rule with '=': "~==============..."
; Emits '~' followed by (ACTIVE_COLS - 2) '=' characters and CRLF.
;------------------------------------------------------------------------------
PRINT_HR_EQUAL:
	LD	A,'~'
	CALL	PUTC
	LD	A,(ACTIVE_COLS)
	SUB	2
	LD	B,A
PHE_LOOP:
	LD	A,'='
	CALL	PUTC
	DJNZ	PHE_LOOP
	LD	DE,STR_CRLF
	CALL	PRINT_STR
	RET

;------------------------------------------------------------------------------
; Print Full-Width Horizontal Rule with '-': "~--------------..."
; Emits '~' followed by (ACTIVE_COLS - 2) '-' characters and CRLF.
;------------------------------------------------------------------------------
PRINT_HR_DASH:
	LD	A,'~'
	CALL	PUTC
	LD	A,(ACTIVE_COLS)
	SUB	2
	LD	B,A
PHD_LOOP:
	LD	A,'-'
	CALL	PUTC
	DJNZ	PHD_LOOP
	LD	DE,STR_CRLF
	CALL	PRINT_STR
	RET

;------------------------------------------------------------------------------
; Render Open/Save Screen Header (4 rows):
; Row 1: Full-width "~====..."
; Row 2: Centered title: "~   SE.COM - OPEN/SAVE FILE (DIRECTORY - DRIVE X:)"
; Row 3: Full-width "~====..."
; Row 4: Blank tilde row: "~"
; Sets UI_CUR_ROW = 4.
;------------------------------------------------------------------------------
RENDER_DIR_TITLE:
	LD	A,(IS_BLOCK_INSERT_UI)
	OR	A
	JR	NZ,RDT_IS_INSERT
	LD	A,(IS_PLUGIN_LOAD_UI)
	OR	A
	JR	NZ,RDT_IS_PLUGIN
	LD	DE,STR_TITLE_OPEN_PRE
	LD	A,(STR_DIR_DRIVE_CHAR)
	JR	RENDER_TITLE_COMMON
RDT_IS_INSERT:
	LD	DE,STR_TITLE_INSERT_PRE
	LD	A,(STR_DIR_DRIVE_CHAR)
	JR	RENDER_TITLE_COMMON
RDT_IS_PLUGIN:
	LD	DE,STR_TITLE_PLUG_LOAD_PRE
	LD	A,(STR_DIR_DRIVE_CHAR)
	JR	RENDER_TITLE_COMMON

RENDER_SAVE_TITLE:
	LD	A,(IS_BLOCK_SAVE_UI)
	OR	A
	JR	Z,RST_NORMAL
	LD	DE,STR_TITLE_BLOCK_SAVE_PRE
	LD	A,(STR_SAVE_DRIVE_CHAR)
	JR	RENDER_TITLE_COMMON
RST_NORMAL:
	LD	DE,STR_TITLE_SAVE_PRE
	LD	A,(STR_SAVE_DRIVE_CHAR)

RENDER_TITLE_COMMON:
	PUSH	AF
	PUSH	DE

	; 1. Clear Screen (ESC [ 2 J, ESC [ H)
	LD	DE,STR_CLEAR_SCREEN
	CALL	PRINT_STR

	; 2. Row 1: Horizontal Rule
	CALL	PRINT_HR_EQUAL

	; 3. Row 2: Centered Title
	; Title length: 43 if IS_BLOCK_INSERT_UI or IS_PLUGIN_LOAD_UI,
	; 42 if IS_BLOCK_SAVE_UI, 41 otherwise
	LD	A,(IS_BLOCK_INSERT_UI)
	OR	A
	LD	A,43
	JR	NZ,RTC_BASE_LEN_OK
	LD	A,(IS_PLUGIN_LOAD_UI)
	OR	A
	LD	A,43
	JR	NZ,RTC_BASE_LEN_OK
	LD	A,(IS_BLOCK_SAVE_UI)
	OR	A
	LD	A,42
	JR	NZ,RTC_BASE_LEN_OK
	LD	A,41
RTC_BASE_LEN_OK:
	LD	B,A

	; Check if CURRENT_DIR_IS_FAT == 1
	LD	A,(CURRENT_DIR_IS_FAT)
	OR	A
	JR	Z,RTC_CALC_CPM_USER_LEN
	LD	A,(CURRENT_DIR_FAT_UNIT)
	CP	0FFH
	JR	Z,RTC_CALC_FAT_PATH_LEN
	INC	B			; 1 digit for unit 0..7

RTC_CALC_FAT_PATH_LEN:
	; Calculate length of CURRENT_DIR_FAT_PATH
	; Colon ':' is already counted in base title length (B=41)
	; Plus length of path, plus 1 if trailing '/' needs to be added
	PUSH	BC
	LD	HL,CURRENT_DIR_FAT_PATH
	LD	C,0
RTC_PLEN_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,RTC_PLEN_DONE
	INC	C
	INC	HL
	JR	RTC_PLEN_LOOP
RTC_PLEN_DONE:
	LD	A,C
	OR	A
	JR	Z,RTC_PLEN_EMPTY
	DEC	HL
	LD	A,(HL)
	CP	'/'
	JR	Z,RTC_PLEN_FIN		; Already ends with '/'
	INC	C			; Extra 1 char for trailing '/'
	JR	RTC_PLEN_FIN
RTC_PLEN_EMPTY:
	INC	C			; Empty path will print '/'
RTC_PLEN_FIN:
	POP	BC
	LD	A,B
	ADD	A,C
	LD	B,A
	JR	RTC_CHECK_FILTER_LEN

RTC_CALC_CPM_USER_LEN:
	; Check if CURRENT_DIR_USER > 0: add 1 or 2 to title length
	LD	A,(CURRENT_DIR_USER)
	OR	A
	JR	Z,RTC_CHECK_FILTER_LEN
	CP	10
	JR	C,RTC_U_LEN_1
	INC	B			; 2 digits (10..15): +2 chars
RTC_U_LEN_1:
	INC	B			; 1 digit (1..9): +1 char

RTC_CHECK_FILTER_LEN:
	; Check if custom filter is active
	LD	A,(DIR_FILTER_ACTIVE)
	OR	A
	JR	Z,RTC_CALC_PAD

	; Calculate extra length: length of DIR_FILTER_STR + 3
	PUSH	BC
	LD	HL,DIR_FILTER_STR
	LD	C,3
RTC_FSTR_LEN_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,RTC_FSTR_LEN_DONE
	INC	C
	INC	HL
	JR	RTC_FSTR_LEN_LOOP
RTC_FSTR_LEN_DONE:
	POP	BC
	LD	A,B
	ADD	A,C
	LD	B,A

RTC_CALC_PAD:
	LD	A,'~'
	CALL	PUTC
	LD	A,(ACTIVE_COLS)
	SUB	B
	JR	C,RTC_NO_PAD
	SRL	A
	JR	Z,RTC_NO_PAD
	DEC	A
	JR	Z,RTC_NO_PAD
	LD	B,A
RTC_PAD_LOOP:
	LD	A,' '
	CALL	PUTC
	DJNZ	RTC_PAD_LOOP
RTC_NO_PAD:

	POP	DE
	CALL	PRINT_STR
	POP	AF
	CALL	PUTC

	; If FAT mode, print unit digit; if CP/M mode and user > 0, print user digits
	LD	A,(CURRENT_DIR_IS_FAT)
	OR	A
	JR	NZ,RTC_PRINT_FAT_UNIT

	LD	A,(CURRENT_DIR_USER)
	OR	A
	JR	Z,RTC_USER_DONE
	CP	10
	JR	C,RTC_PRINT_U_1DIGIT
	PUSH	AF
	LD	A,'1'
	CALL	PUTC
	POP	AF
	SUB	10
RTC_PRINT_U_1DIGIT:
	ADD	A,'0'
	CALL	PUTC
	JR	RTC_USER_DONE

RTC_PRINT_FAT_UNIT:
	LD	A,(CURRENT_DIR_FAT_UNIT)
	CP	0FFH
	JR	Z,RTC_FAT_UNIT_DONE
	ADD	A,'0'
	CALL	PUTC

RTC_FAT_UNIT_DONE:
	; FAT mode suffix: print ':', path, optional trailing '/', then filter or ')'
	LD	A,':'
	CALL	PUTC

	LD	HL,CURRENT_DIR_FAT_PATH
	CALL	PRINT_FAT_TITLE_PATH

	LD	A,(DIR_FILTER_ACTIVE)
	OR	A
	JR	NZ,RTC_PRINT_FILTERED

	LD	DE,STR_TITLE_PAREN_CRLF
	CALL	PRINT_STR
	JR	RTC_TITLE_DONE

RTC_USER_DONE:
	LD	A,(DIR_FILTER_ACTIVE)
	OR	A
	JR	NZ,RTC_PRINT_FILTERED

	LD	DE,STR_TITLE_DRIVE_SUF
	CALL	PRINT_STR
	JR	RTC_TITLE_DONE

RTC_PRINT_FILTERED:
	LD	DE,STR_TITLE_FILTER_PRE	; ": ["
	CALL	PRINT_STR
	LD	DE,DIR_FILTER_STR
	CALL	PRINT_STR
	LD	DE,STR_TITLE_FILTER_SUF	; "])", 13, 10
	CALL	PRINT_STR

RTC_TITLE_DONE:

	; 4. Row 3: Horizontal Rule
	CALL	PRINT_HR_EQUAL

	; 5. Row 4: Blank Tilde Row
	LD	DE,STR_TILDE_CRLF
	CALL	PRINT_STR

	; Initialize UI_CUR_ROW = 4
	LD	A,4
	LD	(UI_CUR_ROW),A
	RET

;------------------------------------------------------------------------------
; PRINT_FAT_TITLE_PATH:
; Prints path at HL using PUTC. If path does not end with '/', appends '/'.
;------------------------------------------------------------------------------
PRINT_FAT_TITLE_PATH:
	LD	C,0			; Tracks last character printed
PFTP_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,PFTP_DONE
	CALL	PUTC
	LD	C,A
	INC	HL
	JR	PFTP_LOOP
PFTP_DONE:
	LD	A,C
	CP	'/'
	RET	Z			; Already ended with '/'
	LD	A,'/'
	CALL	PUTC
	RET

;------------------------------------------------------------------------------
; Initialize CURRENT_DIR_DRIVE and title strings
; If WORK_FCB has an explicit drive, uses it; otherwise queries BDOS 25.
;------------------------------------------------------------------------------
INIT_DIR_DRIVE:
	LD	A,(CMDLINE_IS_FAT)
	OR	A
	JR	NZ,IDD_IS_FAT_ARG
	LD	A,(DOC_IS_FAT)
	OR	A
	JR	Z,IDD_NOT_FAT
IDD_IS_FAT_ARG:
	LD	A,1
	LD	(CURRENT_DIR_IS_FAT),A
	LD	A,(FAT_DOC_UNIT)
	LD	(CURRENT_DIR_FAT_UNIT),A
	CALL	SET_DIR_FROM_DOC_PATH
	LD	A,'U'
	LD	(STR_DIR_DRIVE_CHAR),A
	LD	(STR_SAVE_DRIVE_CHAR),A
	RET

IDD_NOT_FAT:
	XOR	A
	LD	(CURRENT_DIR_IS_FAT),A
	LD	A,(IS_PLUGIN_LOAD_UI)
	OR	A
	JR	NZ,IDD_USE_BDOS
	LD	A,(WORK_FCB)
	OR	A
	JR	NZ,IDD_USE_FCB
IDD_USE_BDOS:
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
; Restore BDOS user area and CURRENT_DIR_USER to the active document user area
;------------------------------------------------------------------------------
RESTORE_DOC_USER:
	LD	A,(DOC_USER_NUM)
	LD	(CURRENT_DIR_USER),A
	LD	E,A
	LD	C,32			; BDOS Set User Area
	CALL	BDOS_ENTRY
	RET

;------------------------------------------------------------------------------
; Reset directory filter to default *.* (all files shown)
;------------------------------------------------------------------------------
RESET_DIR_FILTER:
	XOR	A
	LD	(DIR_FILTER_ACTIVE),A
	LD	HL,DIR_FILTER_FCB
	LD	B,11
RDF_LOOP:
	LD	(HL),'?'
	INC	HL
	DJNZ	RDF_LOOP
	LD	HL,DIR_FILTER_STR
	LD	(HL),'*'
	INC	HL
	LD	(HL),'.'
	INC	HL
	LD	(HL),'*'
	INC	HL
	LD	(HL),0
	RET

;------------------------------------------------------------------------------
; Preload INPUT_FILENAME_BUF with current drive and document user area characters
; (e.g. "J0:", "A4:", "C0:", "C1:", "B15:", "U4:")
; Sets INPUT_BUF_LEN and null-terminates the buffer.
; Outputs: INPUT_FILENAME_BUF populated, INPUT_BUF_LEN set
;------------------------------------------------------------------------------
PRELOAD_DRIVE_USER_PREFIX:
	LD	A,(CURRENT_DIR_IS_FAT)
	OR	A
	JR	NZ,PDUP_FAT

	LD	DE,INPUT_FILENAME_BUF
	LD	C,0			; Length counter

	; Emit drive letter (CURRENT_DIR_DRIVE)
	LD	A,(CURRENT_DIR_DRIVE)
	OR	A
	JR	NZ,PDUP_HAS_DRV
	LD	A,1			; Fallback drive A if 0
PDUP_HAS_DRV:
	ADD	A,'A'-1
	LD	(DE),A
	INC	DE
	INC	C

	; Emit user area digits (CURRENT_DIR_USER)
	LD	A,(CURRENT_DIR_USER)
	CP	10
	JR	C,PDUP_U_1DIGIT
	PUSH	AF
	LD	A,'1'
	LD	(DE),A
	INC	DE
	INC	C
	POP	AF
	SUB	10
PDUP_U_1DIGIT:
	ADD	A,'0'
	LD	(DE),A
	INC	DE
	INC	C

	; Emit ':'
	LD	A,':'
	LD	(DE),A
	INC	DE
	INC	C

	; Null-terminate buffer
	XOR	A
	LD	(DE),A
	LD	A,C
	LD	(INPUT_BUF_LEN),A
	RET

PDUP_FAT:
	LD	DE,INPUT_FILENAME_BUF
	LD	A,'U'
	LD	(DE),A
	INC	DE
	LD	C,1
	LD	A,(CURRENT_DIR_FAT_UNIT)
	CP	0FFH
	JR	Z,PDUP_FAT_NO_UNIT
	ADD	A,'0'
	LD	(DE),A
	INC	DE
	INC	C
PDUP_FAT_NO_UNIT:
	LD	A,':'
	LD	(DE),A
	INC	DE
	INC	C
	XOR	A
	LD	(DE),A
	LD	A,C
	LD	(INPUT_BUF_LEN),A
	RET

;------------------------------------------------------------------------------
; Helper: Check if character in A is a valid drive letter 'A'..'P' / 'a'..'p'
; Returns: Carry = 1 and A = drive code 1..16 (1=A, 2=B, etc.)
;          Carry = 0 if not a drive letter
;------------------------------------------------------------------------------
IS_DRIVE_LETTER:
	CALL	TO_UPPER
	CP	'A'
	JR	C,IDL_NOT_DRV
	CP	'P'+1
	JR	NC,IDL_NOT_DRV
	SUB	'A'-1			; 'A' -> 1, ..., 'P' -> 16
	SCF
	RET
IDL_NOT_DRV:
	OR	A			; Carry = 0
	RET

;------------------------------------------------------------------------------
; Helper: Check if character in A is a digit '0'..'9'
; Returns: Carry = 1 and A = digit value 0..9
;          Carry = 0 if not a digit
;------------------------------------------------------------------------------
IS_DIGIT_CHAR:
	CP	'0'
	JR	C,IDC_NOT_DIG
	CP	'9'+1
	JR	NC,IDC_NOT_DIG
	SUB	'0'			; 0..9
	SCF
	RET
IDC_NOT_DIG:
	OR	A
	RET

;------------------------------------------------------------------------------
; Helper: Parse 2-digit user number from ASCII digits in D (tens) and E (units)
; Returns: Carry = 1 and A = user number (0..15)
;          Carry = 0 if user number > 15
;------------------------------------------------------------------------------
PARSE_2DIGIT_USER:
	LD	A,D
	CP	'0'
	JR	Z,P2U_TENS_ZERO
	CP	'1'
	JR	NZ,P2U_INVALID		; Tens > 1 -> invalid (> 19)
	; Tens is '1'
	LD	A,E
	CP	'5'+1
	JR	NC,P2U_INVALID		; Units > '5' -> invalid (> 15)
	SUB	'0'
	ADD	A,10			; 10..15
	SCF
	RET
P2U_TENS_ZERO:
	LD	A,E
	SUB	'0'			; 0..9
	SCF
	RET
P2U_INVALID:
	OR	A
	RET

;------------------------------------------------------------------------------
; PARSE_DRIVE_USER_PREFIX:
; Parses CP/M drive and/or user area prefix at HL:
;   "C:"   -> Drive C, User unchanged
;   "1:"   -> Drive unchanged, User 1
;   "C1:"  -> Drive C, User 1
;   "1C:"  -> Drive C, User 1
;   "C15:" -> Drive C, User 15
;   "15C:" -> Drive C, User 15
;   "15:"  -> Drive unchanged, User 15
; Returns:
;   Carry = 1: Valid prefix matched.
;              HL advanced past ':'.
;              A = Target Drive (1..16 if specified, or 0 if unchanged).
;              C = Target User (0..15 if specified, or 0xFF if unchanged).
;              Also stored in (PREFIX_DRIVE) and (PREFIX_USER).
;   Carry = 0: No valid prefix.
;              HL preserved.
;------------------------------------------------------------------------------
PARSE_DRIVE_USER_PREFIX:
	PUSH	HL
PDUP_SKIP_SPACES:
	LD	A,(HL)
	CP	' '
	JR	NZ,PDUP_CHECK_COLON
	INC	HL
	JR	PDUP_SKIP_SPACES

PDUP_CHECK_COLON:
	; Look for ':' at HL+1, HL+2, or HL+3
	INC	HL
	LD	A,(HL)
	CP	':'
	JR	Z,PDUP_LEN1		; ':' at HL+1 -> 1 char before colon

	INC	HL
	LD	A,(HL)
	CP	':'
	JP	Z,PDUP_LEN2		; ':' at HL+2 -> 2 chars before colon

	INC	HL
	LD	A,(HL)
	CP	':'
	JP	Z,PDUP_LEN3		; ':' at HL+3 -> 3 chars before colon

PDUP_FAIL:
	POP	HL			; Restore original HL
	OR	A			; Carry = 0
	RET

; Length 1 before colon: (HL-1)
PDUP_LEN1:
	DEC	HL			; HL points to Char 0
	LD	A,(HL)
	CALL	IS_DRIVE_LETTER
	JR	C,PDUP_L1_DRIVE
	LD	A,(HL)
	CALL	IS_DIGIT_CHAR
	JR	C,PDUP_L1_USER
	JP	PDUP_FAIL

PDUP_L1_DRIVE:
	LD	(PREFIX_DRIVE),A
	LD	A,0FFH
	LD	(PREFIX_USER),A
	INC	HL			; past Char 0
	INC	HL			; past ':'
	JP	PDUP_SUCCESS

PDUP_L1_USER:
	LD	(PREFIX_USER),A
	XOR	A
	LD	(PREFIX_DRIVE),A
	INC	HL			; past Char 0
	INC	HL			; past ':'
	JP	PDUP_SUCCESS

; Length 2 before colon: (HL-2), (HL-1)
PDUP_LEN2:
	DEC	HL
	DEC	HL			; HL points to Char 0
	LD	A,(HL)
	CALL	IS_DRIVE_LETTER
	JR	C,PDUP_L2_LETTER_FIRST
	LD	A,(HL)
	CALL	IS_DIGIT_CHAR
	JR	C,PDUP_L2_DIGIT_FIRST
	JP	PDUP_FAIL

PDUP_L2_LETTER_FIRST:
	LD	(PREFIX_DRIVE),A
	INC	HL			; Char 1
	LD	A,(HL)
	CALL	IS_DIGIT_CHAR
	JP	NC,PDUP_FAIL
	LD	(PREFIX_USER),A
	INC	HL			; past Char 1
	INC	HL			; past ':'
	JP	PDUP_SUCCESS

PDUP_L2_DIGIT_FIRST:
	INC	HL			; Char 1
	LD	A,(HL)
	CALL	IS_DRIVE_LETTER
	JR	C,PDUP_L2_DIGIT_LETTER

	LD	A,(HL)
	CALL	IS_DIGIT_CHAR
	JP	NC,PDUP_FAIL

	DEC	HL			; Char 0
	LD	D,(HL)
	INC	HL			; Char 1
	LD	E,(HL)
	CALL	PARSE_2DIGIT_USER
	JP	NC,PDUP_FAIL
	LD	(PREFIX_USER),A
	XOR	A
	LD	(PREFIX_DRIVE),A
	INC	HL			; past Char 1
	INC	HL			; past ':'
	JP	PDUP_SUCCESS

PDUP_L2_DIGIT_LETTER:
	LD	(PREFIX_DRIVE),A
	DEC	HL			; Char 0
	LD	A,(HL)
	SUB	'0'
	LD	(PREFIX_USER),A
	INC	HL			; Char 1
	INC	HL			; past Char 1
	INC	HL			; past ':'
	JP	PDUP_SUCCESS

; Length 3 before colon: (HL-3), (HL-2), (HL-1)
PDUP_LEN3:
	DEC	HL
	DEC	HL
	DEC	HL			; HL points to Char 0
	LD	A,(HL)
	CALL	IS_DRIVE_LETTER
	JR	C,PDUP_L3_LETTER_FIRST
	LD	A,(HL)
	CALL	IS_DIGIT_CHAR
	JR	C,PDUP_L3_DIGIT_FIRST
	JP	PDUP_FAIL

PDUP_L3_LETTER_FIRST:
	LD	(PREFIX_DRIVE),A
	INC	HL			; Char 1
	LD	D,(HL)
	INC	HL			; Char 2
	LD	E,(HL)
	CALL	PARSE_2DIGIT_USER
	JP	NC,PDUP_FAIL
	LD	(PREFIX_USER),A
	INC	HL			; past Char 2
	INC	HL			; past ':'
	JP	PDUP_SUCCESS

PDUP_L3_DIGIT_FIRST:
	LD	D,(HL)			; Char 0
	INC	HL
	LD	E,(HL)			; Char 1
	INC	HL
	LD	A,(HL)			; Char 2
	CALL	IS_DRIVE_LETTER
	JP	NC,PDUP_FAIL
	LD	(PREFIX_DRIVE),A
	CALL	PARSE_2DIGIT_USER
	JP	NC,PDUP_FAIL
	LD	(PREFIX_USER),A
	INC	HL			; past Char 2
	INC	HL			; past ':'
	JP	PDUP_SUCCESS

PDUP_SUCCESS:
	POP	AF			; Discard saved initial HL
	LD	A,(PREFIX_DRIVE)
	LD	C,A
	LD	A,(PREFIX_USER)
	EX	AF,AF'
	LD	A,C
	EX	AF,AF'
	LD	C,A
	EX	AF,AF'
	SCF
	RET

;------------------------------------------------------------------------------
; Check if INPUT_FILENAME_BUF contains a drive/user specification (e.g. "C:", "C1:", "1C:", "1:")
; Returns:
;   Carry = 1 -> Drive/user switch requested:
;                A = drive code (1..16, or 0 if unchanged)
;                C = user code (0..15, or 0xFF if unchanged)
;   Carry = 0 -> Not a bare drive/user switch
;------------------------------------------------------------------------------
CHECK_DRIVE_SWITCH:
	LD	HL,INPUT_FILENAME_BUF
	CALL	PARSE_DRIVE_USER_PREFIX
	RET	NC			; No prefix -> Carry = 0

	; Check that remainder after ':' is empty (only null or spaces)
CDS_CHECK_REM:
	LD	A,(HL)
	OR	A
	JR	Z,CDS_IS_SWITCH
	CP	' '
	JR	NZ,CDS_NOT_SWITCH
	INC	HL
	JR	CDS_CHECK_REM

CDS_IS_SWITCH:
	LD	A,(PREFIX_DRIVE)
	LD	C,A
	LD	A,(PREFIX_USER)
	EX	AF,AF'
	LD	A,C
	EX	AF,AF'
	LD	C,A
	EX	AF,AF'
	SCF
	RET

CDS_NOT_SWITCH:
	OR	A			; Carry = 0
	RET

;------------------------------------------------------------------------------
; Check if INPUT_FILENAME_BUF contains a wildcard filter pattern (e.g. "*.TXT" or "J:*.TXT")
; If so, parses drive (if specified) and pattern into DIR_FILTER_FCB and DIR_FILTER_STR.
; Returns:
;   Carry = 1 -> Filter pattern processed
;   Carry = 0 -> Not a filter pattern
;------------------------------------------------------------------------------
CHECK_FILTER_PATTERN:
	LD	A,(INPUT_BUF_LEN)
	OR	A
	RET	Z			; Empty buffer -> Carry = 0

	; Scan buffer for '*' or '?'
	LD	B,A
	LD	HL,INPUT_FILENAME_BUF
CFP_SCAN_LOOP:
	LD	A,(HL)
	CP	'*'
	JR	Z,CFP_FOUND_WC
	CP	'?'
	JR	Z,CFP_FOUND_WC
	INC	HL
	DJNZ	CFP_SCAN_LOOP
	OR	A			; Carry = 0
	RET

CFP_FOUND_WC:
	LD	HL,INPUT_FILENAME_BUF
	CALL	PARSE_DRIVE_USER_PREFIX
	JR	NC,CFP_NO_DRIVE_PREFIX

	; Prefix was found! Check if drive was specified
	LD	A,(PREFIX_DRIVE)
	OR	A
	JR	Z,CFP_CHECK_USER_PRE
	LD	C,A			; C = target drive (1..16)

	; Guard: if target drive matches hibernated RAM drive, reject switch
	LD	A,(RAMDRIVE_IS_HIBERNATED)
	OR	A
	JR	Z,CFP_DRIVE_OK
	LD	A,(RAMDRIVE_DRIVE_NUM)
	CP	0FFH
	JR	Z,CFP_DRIVE_OK
	INC	A
	CP	C
	JR	Z,CFP_CHECK_USER_PRE

CFP_DRIVE_OK:
	LD	A,C
	LD	(CURRENT_DIR_DRIVE),A
	ADD	A,'A'-1
	LD	(STR_DIR_DRIVE_CHAR),A
	LD	(STR_SAVE_DRIVE_CHAR),A

CFP_CHECK_USER_PRE:
	LD	A,(PREFIX_USER)
	CP	0FFH
	JR	Z,CFP_USER_DEFAULT_ZERO
	LD	(CURRENT_DIR_USER),A
	JR	CFP_PARSE_START
CFP_USER_DEFAULT_ZERO:
	XOR	A
	LD	(CURRENT_DIR_USER),A
	JR	CFP_PARSE_START

CFP_NO_DRIVE_PREFIX:
	XOR	A
	LD	(CURRENT_DIR_USER),A
	LD	HL,INPUT_FILENAME_BUF

CFP_PARSE_START:
	; Copy uppercase pattern to DIR_FILTER_STR (max 12 chars null-terminated)
	PUSH	HL
	LD	DE,DIR_FILTER_STR
	LD	B,12
CFP_COPY_STR:
	LD	A,(HL)
	OR	A
	JR	Z,CFP_COPY_END
	CALL	TO_UPPER
	LD	(DE),A
	INC	HL
	INC	DE
	DJNZ	CFP_COPY_STR
CFP_COPY_END:
	XOR	A
	LD	(DE),A			; Null-terminate
	POP	HL

	; Clear DIR_FILTER_FCB with 11 spaces
	PUSH	HL
	LD	HL,DIR_FILTER_FCB
	LD	B,11
CFP_CLR_FCB:
	LD	(HL),' '
	INC	HL
	DJNZ	CFP_CLR_FCB
	POP	HL

	; Parse filename part (bytes 0..7 of DIR_FILTER_FCB)
	LD	DE,DIR_FILTER_FCB
	LD	B,8
CFP_NAME_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,CFP_NAME_END_NODOT
	CP	' '
	JR	Z,CFP_NAME_END_NODOT
	CP	'.'
	JR	Z,CFP_NAME_DOT
	CP	'*'
	JR	Z,CFP_NAME_STAR
	CALL	TO_UPPER
	LD	(DE),A
	INC	DE
	INC	HL
	DJNZ	CFP_NAME_LOOP

	; Consumed 8 chars of name -> skip until '.' or end
CFP_SKIP_NAME_REST:
	LD	A,(HL)
	OR	A
	JR	Z,CFP_NAME_END_NODOT
	CP	' '
	JR	Z,CFP_NAME_END_NODOT
	CP	'.'
	JR	Z,CFP_NAME_DOT
	INC	HL
	JR	CFP_SKIP_NAME_REST

CFP_NAME_STAR:
	; Fill remaining name bytes with '?'
	LD	A,'?'
CFP_STAR_NAME_PAD:
	LD	(DE),A
	INC	DE
	DJNZ	CFP_STAR_NAME_PAD
	INC	HL
CFP_SKIP_STAR_REST:
	LD	A,(HL)
	OR	A
	JR	Z,CFP_NAME_END_NODOT
	CP	' '
	JR	Z,CFP_NAME_END_NODOT
	CP	'.'
	JR	Z,CFP_NAME_DOT
	INC	HL
	JR	CFP_SKIP_STAR_REST

CFP_NAME_DOT:
	INC	HL			; Skip '.'
	JR	CFP_PARSE_EXT

CFP_NAME_END_NODOT:
	; No '.' in input (e.g. '*' or 'A*') -> fill ext with '?'
	LD	DE,DIR_FILTER_FCB+8
	LD	A,'?'
	LD	(DE),A
	INC	DE
	LD	(DE),A
	INC	DE
	LD	(DE),A
	JR	CFP_CHECK_ACTIVE

CFP_PARSE_EXT:
	LD	DE,DIR_FILTER_FCB+8
	LD	B,3
CFP_EXT_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,CFP_CHECK_ACTIVE
	CP	' '
	JR	Z,CFP_CHECK_ACTIVE
	CP	'*'
	JR	Z,CFP_EXT_STAR
	CALL	TO_UPPER
	LD	(DE),A
	INC	DE
	INC	HL
	DJNZ	CFP_EXT_LOOP
	JR	CFP_CHECK_ACTIVE

CFP_EXT_STAR:
	LD	A,'?'
CFP_STAR_EXT_PAD:
	LD	(DE),A
	INC	DE
	DJNZ	CFP_STAR_EXT_PAD

CFP_CHECK_ACTIVE:
	; Check if DIR_FILTER_FCB is all '?' (meaning *.*)
	LD	HL,DIR_FILTER_FCB
	LD	B,11
CFP_CHK_QM:
	LD	A,(HL)
	CP	'?'
	JR	NZ,CFP_SET_ACTIVE
	INC	HL
	DJNZ	CFP_CHK_QM

	; All 11 chars are '?' -> Inactive (standard *.*)
	XOR	A
	LD	(DIR_FILTER_ACTIVE),A
	LD	HL,DIR_FILTER_STR
	LD	(HL),'*'
	INC	HL
	LD	(HL),'.'
	INC	HL
	LD	(HL),'*'
	INC	HL
	LD	(HL),0
	SCF
	RET

CFP_SET_ACTIVE:
	LD	A,1
	LD	(DIR_FILTER_ACTIVE),A
	SCF
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
	JR	NZ,FCB_HAS_DRV
	LD	A,(CURRENT_DIR_DRIVE)
	OR	A
	JR	NZ,FCB_HAS_DRV
	LD	A,1			; Fallback drive A if 0
FCB_HAS_DRV:
	; Explicit drive 1..16
	ADD	A,'A'-1
	LD	(DE),A
	INC	DE
	INC	C

FCB_CHECK_USER:
	; Always emit user area digits (DOC_USER_NUM), including 0
	LD	A,(DOC_USER_NUM)
	CP	10
	JR	C,FCB_U_1DIGIT
	PUSH	AF
	LD	A,'1'
	LD	(DE),A
	INC	DE
	INC	C
	POP	AF
	SUB	10
FCB_U_1DIGIT:
	ADD	A,'0'
	LD	(DE),A
	INC	DE
	INC	C

FCB_EMIT_COLON:
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
	LD	HL,UI_CUR_ROW
	INC	(HL)
	CALL	PRINT_HR_DASH
	INC	(HL)
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
	CALL	PRINT_SAVE_FMT_INFO
	JR	DISP_SAVE_PROMPT_BODY

DISP_SINGLE_SAVE_PROMPT:
	LD	HL,UI_CUR_ROW
	INC	(HL)
	CALL	PRINT_HR_DASH
	CALL	PRINT_SAVE_FMT_INFO

DISP_SAVE_PROMPT_BODY:
	LD	HL,UI_CUR_ROW
	INC	(HL)			; For STR_ESC_CANCEL
	INC	(HL)			; For Prompt line itself!
	LD	DE,STR_ESC_CANCEL
	CALL	PRINT_STR
	LD	DE,STR_TILDE_INDENT
	CALL	PRINT_STR
	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR
	LD	DE,STR_SAVE_PROMPT_TXT	; "Enter filename to save:"
	CALL	PRINT_STR
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	CALL	DRAW_FILENAME_BOX
	RET

PRINT_SAVE_FMT_INFO:
	LD	HL,UI_CUR_ROW
	INC	(HL)
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

	; Check if active directory mode is FAT volume
	LD	A,(CURRENT_DIR_IS_FAT)
	OR	A
	JP	NZ,COLLECT_FAT_DIR_ENTRIES

	; Guard: if RAM drive is hibernated and CURRENT_DIR_DRIVE matches, return empty directory
	LD	A,(RAMDRIVE_IS_HIBERNATED)
	OR	A
	JR	Z,CDE_DRIVE_OK
	LD	A,(RAMDRIVE_DRIVE_NUM)
	CP	0FFH
	JR	Z,CDE_DRIVE_OK
	INC	A
	LD	B,A
	LD	A,(CURRENT_DIR_DRIVE)
	CP	B
	RET	Z			; Hibernated drive -> return empty
CDE_DRIVE_OK:
	; Set DMA address to RAW_SECTOR_BUF (128 bytes)
	LD	DE,RAW_SECTOR_BUF
	LD	C,26			; BDOS Set DMA
	CALL	BDOS_ENTRY

	; Prepare DIR_SEARCH_FCB: Drive = CURRENT_DIR_DRIVE, 11 filter bytes, rest 0
	LD	HL,DIR_SEARCH_FCB
	LD	A,(CURRENT_DIR_DRIVE)
	LD	(HL),A			; Active directory drive (1=A, 2=B, etc.)
	INC	HL
	EX	DE,HL
	LD	HL,DIR_FILTER_FCB
	LD	BC,11
	LDIR
	EX	DE,HL
	LD	B,24
SET_SEARCH_ZEROS:
	LD	(HL),0
	INC	HL
	DJNZ	SET_SEARCH_ZEROS

	; Set BDOS user area to CURRENT_DIR_USER
	LD	A,(CURRENT_DIR_USER)
	LD	E,A
	LD	C,32			; BDOS Set User Area
	CALL	BDOS_ENTRY

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
	LD	B,A
	LD	A,(CURRENT_DIR_USER)
	CP	B
	JR	NZ,DIR_NEXT_ENTRY	; Non-matching user entry

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

	; Filter out temporary swap files ($$$SE$$$.SWP or $$$*.SWP)
	CALL	CHECK_DIR_SWAP_FILE
	JR	C,DIR_NEXT_ENTRY	; Swap file -> skip

	; In Plugin Load UI, filter for .PRL and .OVL files
	; unless a custom wildcard filter is active
	LD	A,(IS_PLUGIN_LOAD_UI)
	OR	A
	JR	Z,CDE_NOT_PLUGIN_UI
	LD	A,(DIR_FILTER_ACTIVE)
	OR	A
	JR	NZ,CDE_NOT_PLUGIN_UI
	CALL	CHECK_PLUGIN_EXT
	JR	NC,DIR_NEXT_ENTRY	; Not a plugin file -> skip
CDE_NOT_PLUGIN_UI:

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
	JP	DIR_COLLECT_LOOP

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
; CHECK_DIR_SWAP_FILE: Check if DIR_TEMP_ENTRY is a swap file
; Matches $$$SE$$$.SWP or any generic $$$*.SWP
; Returns: Carry = 1 if swap file (skip), Carry = 0 if regular file
;------------------------------------------------------------------------------
CHECK_DIR_SWAP_FILE:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	; 1. Check exact match with $$$SE$$$.SWP (12 characters)
	LD	HL,DIR_TEMP_ENTRY
	LD	DE,STR_SWAP_FILE_MATCH
	LD	B,12
CDSF_MATCH_LOOP:
	LD	A,(DE)
	CP	(HL)
	JR	NZ,CDSF_CHECK_GENERIC
	INC	HL
	INC	DE
	DJNZ	CDSF_MATCH_LOOP
	SCF				; Carry = 1: matches $$$SE$$$.SWP
	JR	CDSF_DONE

CDSF_CHECK_GENERIC:
	; 2. Check generic swap pattern: starts with "$$$" and extension "SWP"
	LD	HL,DIR_TEMP_ENTRY
	LD	A,(HL)
	CP	'$'
	JR	NZ,CDSF_NOT_SWAP
	INC	HL
	LD	A,(HL)
	CP	'$'
	JR	NZ,CDSF_NOT_SWAP
	INC	HL
	LD	A,(HL)
	CP	'$'
	JR	NZ,CDSF_NOT_SWAP
	; Extension is at DIR_TEMP_ENTRY+9 (3 bytes: 'S', 'W', 'P')
	LD	HL,DIR_TEMP_ENTRY+9
	LD	A,(HL)
	CP	'S'
	JR	NZ,CDSF_NOT_SWAP
	INC	HL
	LD	A,(HL)
	CP	'W'
	JR	NZ,CDSF_NOT_SWAP
	INC	HL
	LD	A,(HL)
	CP	'P'
	JR	NZ,CDSF_NOT_SWAP
	SCF				; Carry = 1: matches $$$*.SWP
	JR	CDSF_DONE

CDSF_NOT_SWAP:
	OR	A			; Carry = 0: normal file
CDSF_DONE:
	POP	HL
	POP	DE
	POP	BC
	RET

STR_SWAP_FILE_MATCH:
	DB	"$$$SE$$$.SWP",0

;------------------------------------------------------------------------------
; CHECK_PLUGIN_EXT: Check if DIR_TEMP_ENTRY extension is "PRL" or "OVL"
; Returns: Carry = 1 if match, Carry = 0 if not match
;------------------------------------------------------------------------------
CHECK_PLUGIN_EXT:
	LD	HL,DIR_TEMP_ENTRY + 9
	LD	A,(HL)
	CP	'P'
	JR	NZ,CPE_CHECK_OVL
	INC	HL
	LD	A,(HL)
	CP	'R'
	JR	NZ,CPE_FAIL
	INC	HL
	LD	A,(HL)
	CP	'L'
	JR	NZ,CPE_FAIL
	SCF
	RET
CPE_CHECK_OVL:
	CP	'O'
	JR	NZ,CPE_FAIL
	INC	HL
	LD	A,(HL)
	CP	'V'
	JR	NZ,CPE_FAIL
	INC	HL
	LD	A,(HL)
	CP	'L'
	JR	NZ,CPE_FAIL
	SCF
	RET
CPE_FAIL:
	OR	A
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
	LD	HL,UI_CUR_ROW
	INC	(HL)
	INC	(HL)
	LD	DE,STR_NO_FILES_FOUND
	CALL	PRINT_STR
	RET

DO_SHOW_PAGE:
	; Calculate start file index: DIR_START_FILE = DIR_PAGE_INDEX * DIR_PAGE_CAPACITY
	LD	A,(DIR_PAGE_INDEX)
	OR	A
	JR	Z,DSP_START_ZERO
	LD	B,A
	LD	A,(DIR_PAGE_CAPACITY)
	LD	C,A
	XOR	A
DSP_START_LOOP:
	ADD	A,C
	DJNZ	DSP_START_LOOP
DSP_START_ZERO:
	LD	(DIR_START_FILE),A

	; Calculate number of files on this page:
	; Count = min(DIR_PAGE_CAPACITY, DIR_FILE_COUNT - DIR_START_FILE)
	LD	A,(DIR_FILE_COUNT)
	LD	HL,DIR_START_FILE
	SUB	(HL)
	LD	HL,DIR_PAGE_CAPACITY
	CP	(HL)
	JR	C,HAVE_PAGE_COUNT
	LD	A,(HL)
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

	; If first column of row, emit "~  " prefix
	LD	A,(DIR_COL_COUNT)
	OR	A
	JR	NZ,DPL_NOT_FIRST_COL
	LD	DE,STR_TILDE_INDENT
	CALL	PRINT_STR
DPL_NOT_FIRST_COL:

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

	; Check if byte 8 is '/' (subdirectory indicator from VFS_CMD_LIST_DIR)
	LD	A,(HL)
	CP	'/'
	JR	NZ,DPL_NOT_SUBDIR
	; Subdirectory: emit '/' and pad column
	LD	(DE),A
	INC	DE
	INC	HL			; skip byte 8 ('/')
	INC	HL			; skip byte 9
	INC	HL			; skip byte 10
	INC	HL			; skip byte 11
	JR	PAD_COLUMN

DPL_NOT_SUBDIR:
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
	; Pad with spaces up to DIR_COL_WIDTH characters
	LD	C,A
	LD	A,(DIR_COL_WIDTH)
	SUB	C			; A = DIR_COL_WIDTH - char_count
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

	; Print column (null-terminated; avoids early '$' stop in PRINT_STR)
	CALL	PRINT_DIR_COL_ENTRY

	; Increment column counter
	LD	A,(DIR_COL_COUNT)
	INC	A
	LD	(DIR_COL_COUNT),A
	LD	HL,DIR_COLS_PER_ROW
	CP	(HL)			; Wrap at DIR_COLS_PER_ROW (5 on 80x24, 7 on 120x40)
	JR	NZ,NO_ROW_WRAP
	XOR	A
	LD	(DIR_COL_COUNT),A
	LD	HL,UI_CUR_ROW
	INC	(HL)
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
	LD	HL,UI_CUR_ROW
	INC	(HL)
	LD	DE,STR_CRLF
	CALL	PRINT_STR

DISP_PAGE_DONE:
	LD	HL,UI_CUR_ROW
	INC	(HL)
	LD	DE,STR_TILDE_CRLF
	CALL	PRINT_STR
	RET

;------------------------------------------------------------------------------
; PRINT_DIR_COL_ENTRY: Print null-terminated column from LOAD_LINE_TEMP
; Does not terminate on '$' so filenames with '$' render cleanly
;------------------------------------------------------------------------------
PRINT_DIR_COL_ENTRY:
	PUSH	HL
	LD	HL,LOAD_LINE_TEMP
PDCE_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,PDCE_DONE
	CALL	PUTC
	INC	HL
	JR	PDCE_LOOP
PDCE_DONE:
	POP	HL
	RET

;------------------------------------------------------------------------------
; Display Open Prompt & Page Indicator
;------------------------------------------------------------------------------
DISPLAY_OPEN_PROMPT:
	LD	A,(DIR_PAGE_COUNT)
	CP	2
	JR	C,DISP_SINGLE_PROMPT

	; Multi-page prompt
	LD	HL,UI_CUR_ROW
	INC	(HL)
	CALL	PRINT_HR_DASH
	INC	(HL)
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
	JR	DISP_OPEN_PROMPT_BODY

DISP_SINGLE_PROMPT:
	LD	HL,UI_CUR_ROW
	INC	(HL)
	CALL	PRINT_HR_DASH

DISP_OPEN_PROMPT_BODY:
	LD	HL,UI_CUR_ROW
	INC	(HL)			; For STR_ESC_CANCEL
	INC	(HL)			; For Prompt line itself!
	LD	DE,STR_ESC_CANCEL
	CALL	PRINT_STR
	LD	DE,STR_TILDE_INDENT
	CALL	PRINT_STR
	LD	DE,STR_INVERSE_ON
	CALL	PRINT_STR
	LD	A,(IS_BLOCK_INSERT_UI)
	OR	A
	JR	NZ,DOP_SHOW_INSERT
	LD	A,(IS_PLUGIN_LOAD_UI)
	OR	A
	JR	NZ,DOP_SHOW_PLUGIN
	LD	DE,STR_OPEN_PROMPT_TXT	; "Enter filename to open:"
	JR	DOP_SHOW_TXT
DOP_SHOW_INSERT:
	LD	DE,STR_INSERT_PROMPT_TXT ; "Enter filename to insert:"
	JR	DOP_SHOW_TXT
DOP_SHOW_PLUGIN:
	LD	DE,STR_PLUG_LOAD_PROMPT_TXT ; "Load Plugin (.PRL/.OVL):"
DOP_SHOW_TXT:
	CALL	PRINT_STR
	LD	DE,STR_INVERSE_OFF
	CALL	PRINT_STR
	CALL	DRAW_FILENAME_BOX
	RET

;------------------------------------------------------------------------------
; DRAW_FILENAME_BOX: Draws " [                    ]" with INPUT_FILENAME_BUF
; prefilled and positions cursor right after prefilled text.
;------------------------------------------------------------------------------
DRAW_FILENAME_BOX:
	LD	A,' '
	CALL	PUTC
	LD	A,'['
	CALL	PUTC

	; Check if any prefilled text in INPUT_FILENAME_BUF
	LD	A,(INPUT_BUF_LEN)
	LD	(INPUT_CURSOR_POS),A
	LD	B,A			; B = length of prefilled text (0..20)
	OR	A
	JR	Z,DFB_PAD_SPACES
	LD	HL,INPUT_FILENAME_BUF
DFB_PRINT_LOOP:
	LD	A,(HL)
	CALL	PUTC
	INC	HL
	DJNZ	DFB_PRINT_LOOP

DFB_PAD_SPACES:
	; Pad (20 - INPUT_BUF_LEN) spaces
	LD	A,20
	LD	HL,INPUT_BUF_LEN
	SUB	(HL)
	JR	Z,DFB_CLOSE_BOX
	LD	B,A
DFB_SPACE_LOOP:
	LD	A,' '
	CALL	PUTC
	DJNZ	DFB_SPACE_LOOP

DFB_CLOSE_BOX:
	LD	A,']'
	CALL	PUTC

	; Move cursor back (21 - INPUT_BUF_LEN) positions to sit on next space after prefilled text
	LD	A,21
	LD	HL,INPUT_BUF_LEN
	SUB	(HL)
	LD	B,A
DFB_BS_LOOP:
	LD	A,008H
	CALL	PUTC
	DJNZ	DFB_BS_LOOP
	RET

;------------------------------------------------------------------------------
; Finish Open/Save Screen rendering:
; 1. End prompt line with CRLF
; 2. Pad remaining rows down to ACTIVE_ROWS - 1 with '~' in column 0
; 3. Render status bar on row ACTIVE_ROWS
; 4. Reposition cursor inside filename input box on UI_CUR_ROW
;------------------------------------------------------------------------------
FINISH_UI_PAGE_AND_STATUS:
	; Print CRLF after the prompt box
	LD	A,13
	CALL	PUTC
	LD	A,10
	CALL	PUTC

	; Fill remaining rows down to ACTIVE_ROWS - 1 with '~'
	LD	A,(ACTIVE_ROWS)
	DEC	A			; A = ACTIVE_ROWS - 1 (last content row)
	LD	HL,UI_CUR_ROW
	SUB	(HL)
	JR	Z,FUPS_STATUS
	JR	C,FUPS_STATUS
	LD	B,A
FUPS_TILDE_LOOP:
	LD	A,'~'
	CALL	PUTC
	LD	A,13
	CALL	PUTC
	LD	A,10
	CALL	PUTC
	DJNZ	FUPS_TILDE_LOOP

FUPS_STATUS:
	CALL	RENDER_STATUS_BAR

	; Reposition cursor inside filename input box on UI_CUR_ROW
	; Col = Base + INPUT_BUF_LEN (31 insert, 30 plugin, 29 open)
	LD	A,(IS_BLOCK_INSERT_UI)
	OR	A
	LD	A,31
	JR	NZ,FUPS_BOX_COL
	LD	A,(IS_PLUGIN_LOAD_UI)
	OR	A
	LD	A,30
	JR	NZ,FUPS_BOX_COL
	LD	A,29
FUPS_BOX_COL:
	LD	HL,INPUT_BUF_LEN
	ADD	A,(HL)
	LD	L,A
	LD	A,(UI_CUR_ROW)
	LD	H,A
	CALL	LOCATE_RC
	LD	DE,STR_SHOW_CURSOR
	CALL	PRINT_STR
	RET

;------------------------------------------------------------------------------
; LOCATE_RC: Move cursor to Row H, Col L (1-indexed for terminal)
; Format: ESC [ <H> ; <L> H
; Preserves BC, DE, HL
;------------------------------------------------------------------------------
LOCATE_RC:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	; Clamp Row H to [1 .. ACTIVE_ROWS]
	LD	A,H
	OR	A
	JR	NZ,LRC_ROW_MIN_OK
	INC	H			; H = 1 if 0
LRC_ROW_MIN_OK:
	LD	A,(ACTIVE_ROWS)
	CP	H			; Carry=1 if ACTIVE_ROWS < H
	JR	NC,LRC_ROW_OK
	LD	H,A			; Clamp H = ACTIVE_ROWS
LRC_ROW_OK:

	; Clamp Col L to [1 .. ACTIVE_COLS]
	LD	A,L
	OR	A
	JR	NZ,LRC_COL_MIN_OK
	INC	L			; L = 1 if 0
LRC_COL_MIN_OK:
	LD	A,(ACTIVE_COLS)
	CP	L			; Carry=1 if ACTIVE_COLS < L
	JR	NC,LRC_COL_OK
	LD	L,A			; Clamp L = ACTIVE_COLS
LRC_COL_OK:

	LD	A,27
	CALL	PUTC
	LD	A,'['
	CALL	PUTC
	LD	A,H
	CALL	PRINT_DEC_BYTE
	LD	A,';'
	CALL	PUTC
	LD	A,L
	CALL	PRINT_DEC_BYTE
	LD	A,'H'
	CALL	PUTC
	POP	HL
	POP	DE
	POP	BC
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
	LD	(INPUT_CURSOR_POS),A
	LD	(SHOWING_FNF_MSG),A
	LD	HL,INPUT_FILENAME_BUF
	LD	(HL),0
	JR	INPUT_CHAR_LOOP

RESUME_FILENAME_INPUT:
	JR	INPUT_CHAR_LOOP

READ_FILENAME_INPUT_PREFILLED:
	XOR	A
	LD	(SHOWING_FNF_MSG),A
	LD	A,(INPUT_BUF_LEN)
	LD	(INPUT_CURSOR_POS),A
	JR	INPUT_CHAR_LOOP

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
	JP	NZ,INPUT_CHECK_PAGE_KEYS

	; Check if character follows ESC within a short timeout
	LD	BC,ESC_TIMEOUT_LOOPS
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
	CP	'D'			; Left Arrow (ESC [ D)
	JP	Z,INPUT_CURSOR_LEFT
	CP	'C'			; Right Arrow (ESC [ C)
	JP	Z,INPUT_CURSOR_RIGHT
	CP	'H'			; Home (ESC [ H)
	JP	Z,INPUT_CURSOR_HOME
	CP	'F'			; End (ESC [ F)
	JP	Z,INPUT_CURSOR_END
	CP	'1'			; Home (ESC [ 1 ~)
	JR	Z,INPUT_CSI_HOME_TILDE
	CP	'4'			; End (ESC [ 4 ~)
	JR	Z,INPUT_CSI_END_TILDE
	CP	'7'			; Home (ESC [ 7 ~)
	JR	Z,INPUT_CSI_HOME_TILDE
	CP	'8'			; End (ESC [ 8 ~)
	JR	Z,INPUT_CSI_END_TILDE
	CP	'3'			; Delete key (ESC [ 3 ~)
	JR	Z,INPUT_CSI_DEL
	CP	'2'			; Insert key (ESC [ 2 ~)
	JR	Z,INPUT_CSI_INS
	CP	'5'			; Page Up (ESC [ 5 ~)
	JR	Z,INPUT_CSI_PGUP
	CP	'6'			; Page Down (ESC [ 6 ~)
	JR	Z,INPUT_CSI_PGDN
	CP	'I'			; Page Up (VT alt)
	JR	Z,INPUT_DO_PGUP
	CP	'G'			; Page Down (VT alt)
	JR	Z,INPUT_DO_PGDN
	CP	'L'			; VT102 Insert line
	JP	Z,INPUT_CHAR_LOOP
	CP	'@'			; ICH Insert char
	JP	Z,INPUT_CHAR_LOOP
	JP	INPUT_CHAR_LOOP

INPUT_CSI_HOME_TILDE:
	CALL	GET_KEY			; Consume trailing '~'
	JP	INPUT_CURSOR_HOME

INPUT_CSI_END_TILDE:
	CALL	GET_KEY			; Consume trailing '~'
	JP	INPUT_CURSOR_END

INPUT_CSI_DEL:
	CALL	GET_KEY			; Consume trailing '~'
	JP	INPUT_DEL_CHAR

INPUT_CSI_INS:
	CALL	GET_KEY			; Consume trailing '~'
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

INPUT_HANDLE_SS3:
	CALL	GET_KEY
	CP	'D'			; Left Arrow (ESC O D)
	JP	Z,INPUT_CURSOR_LEFT
	CP	'C'			; Right Arrow (ESC O C)
	JP	Z,INPUT_CURSOR_RIGHT
	CP	'H'			; Home (ESC O H)
	JP	Z,INPUT_CURSOR_HOME
	CP	'F'			; End (ESC O F)
	JP	Z,INPUT_CURSOR_END
	JP	INPUT_CHAR_LOOP

INPUT_CHECK_PAGE_KEYS:
	; Ctrl+U or Ctrl+B -> Page Up
	CP	KEY_CTRL_U
	JR	Z,INPUT_DO_PGUP
	CP	KEY_CTRL_B
	JR	Z,INPUT_DO_PGUP

	; Ctrl+V -> Page Down
	CP	KEY_CTRL_V
	JR	Z,INPUT_DO_PGDN

	; WordStar navigation keys
	CP	KEY_CTRL_A		; Ctrl+A -> Home
	JP	Z,INPUT_CURSOR_HOME
	CP	KEY_CTRL_E		; Ctrl+E -> End
	JP	Z,INPUT_CURSOR_END
	CP	KEY_CTRL_S		; Ctrl+S -> Cursor Left
	JP	Z,INPUT_CURSOR_LEFT
	CP	KEY_CTRL_D		; Ctrl+D -> Cursor Right
	JP	Z,INPUT_CURSOR_RIGHT
	CP	KEY_CTRL_G		; Ctrl+G -> Delete char at cursor
	JP	Z,INPUT_DEL_CHAR

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
	LD	(INPUT_CHAR_TEMP),A
	LD	A,(INPUT_BUF_LEN)
	CP	20
	JP	NC,INPUT_CHAR_LOOP

	; Check if cursor is at end of string or inside text
	LD	A,(INPUT_CURSOR_POS)
	LD	HL,INPUT_BUF_LEN
	CP	(HL)
	JR	NZ,INPUT_INSERT_MIDDLE

	; Appending at end:
	LD	HL,INPUT_FILENAME_BUF
	LD	E,A
	LD	D,0
	ADD	HL,DE
	LD	A,(INPUT_CHAR_TEMP)
	LD	(HL),A
	INC	HL
	LD	(HL),0			; Null-terminate

	LD	HL,INPUT_BUF_LEN
	INC	(HL)
	LD	HL,INPUT_CURSOR_POS
	INC	(HL)

	; Echo character
	LD	A,(INPUT_CHAR_TEMP)
	CALL	PUTC
	JP	INPUT_CHAR_LOOP

INPUT_INSERT_MIDDLE:
	; Shift bytes right from INPUT_CURSOR_POS to INPUT_BUF_LEN
	; Source end: HL = INPUT_FILENAME_BUF + INPUT_BUF_LEN
	; Dest end:   DE = INPUT_FILENAME_BUF + INPUT_BUF_LEN + 1
	; Count:      BC = INPUT_BUF_LEN - INPUT_CURSOR_POS + 1
	LD	A,(INPUT_BUF_LEN)
	LD	E,A
	LD	D,0
	LD	HL,INPUT_FILENAME_BUF
	ADD	HL,DE			; HL = Source end
	LD	D,H
	LD	E,L
	INC	DE			; DE = Dest end: HL + 1

	LD	A,(INPUT_BUF_LEN)
	LD	C,A
	LD	A,(INPUT_CURSOR_POS)
	SUB	C			; A = P - L
	NEG				; A = L - P
	INC	A			; +1 for null byte
	LD	C,A
	LD	B,0
	LDDR

	; Store character at INPUT_FILENAME_BUF + INPUT_CURSOR_POS
	LD	A,(INPUT_CURSOR_POS)
	LD	E,A
	LD	D,0
	LD	HL,INPUT_FILENAME_BUF
	ADD	HL,DE
	LD	A,(INPUT_CHAR_TEMP)
	LD	(HL),A

	; Increment length and cursor position
	LD	HL,INPUT_BUF_LEN
	INC	(HL)
	LD	HL,INPUT_CURSOR_POS
	INC	(HL)

	; Echo character (screen cursor moves to new INPUT_CURSOR_POS)
	LD	A,(INPUT_CHAR_TEMP)
	CALL	PUTC

	; Refresh remaining box from new cursor position
	CALL	REFRESH_BOX_FROM_CURSOR
	JP	INPUT_CHAR_LOOP

INPUT_CURSOR_LEFT:
	LD	A,(INPUT_CURSOR_POS)
	OR	A
	JP	Z,INPUT_CHAR_LOOP	; At col 0 -> ignore

	DEC	A
	LD	(INPUT_CURSOR_POS),A
	LD	A,008H
	CALL	PUTC
	JP	INPUT_CHAR_LOOP

INPUT_CURSOR_RIGHT:
	LD	A,(INPUT_CURSOR_POS)
	LD	HL,INPUT_BUF_LEN
	CP	(HL)
	JP	NC,INPUT_CHAR_LOOP	; At end -> ignore

	; Advance cursor on screen by printing current character
	LD	HL,INPUT_FILENAME_BUF
	LD	E,A
	LD	D,0
	ADD	HL,DE
	LD	A,(HL)
	CALL	PUTC

	LD	HL,INPUT_CURSOR_POS
	INC	(HL)
	JP	INPUT_CHAR_LOOP

INPUT_CURSOR_HOME:
	LD	A,(INPUT_CURSOR_POS)
	OR	A
	JP	Z,INPUT_CHAR_LOOP

	LD	B,A
	XOR	A
	LD	(INPUT_CURSOR_POS),A
ICH_BS_LOOP:
	LD	A,008H
	CALL	PUTC
	DJNZ	ICH_BS_LOOP
	JP	INPUT_CHAR_LOOP

INPUT_CURSOR_END:
	CALL	INPUT_MOVE_CURSOR_TO_END
	JP	INPUT_CHAR_LOOP

INPUT_DEL_CHAR:
	LD	A,(INPUT_CURSOR_POS)
	LD	HL,INPUT_BUF_LEN
	CP	(HL)
	JP	NC,INPUT_CHAR_LOOP	; Nothing at/past cursor to delete

DO_DELETE_CHAR_AT_CURSOR:
	; Decrement INPUT_BUF_LEN
	LD	HL,INPUT_BUF_LEN
	DEC	(HL)

	; Shift bytes left from (INPUT_CURSOR_POS + 1) to INPUT_BUF_LEN
	; Dest:   DE = INPUT_FILENAME_BUF + INPUT_CURSOR_POS
	; Source: HL = INPUT_FILENAME_BUF + INPUT_CURSOR_POS + 1
	; Count:  BC = INPUT_BUF_LEN - INPUT_CURSOR_POS + 1 (null included)
	LD	A,(INPUT_CURSOR_POS)
	LD	E,A
	LD	D,0
	LD	HL,INPUT_FILENAME_BUF
	ADD	HL,DE
	EX	DE,HL			; DE = Dest
	LD	H,D
	LD	L,E
	INC	HL			; HL = Source (DE + 1)

	LD	A,(INPUT_BUF_LEN)
	LD	C,A
	LD	A,(INPUT_CURSOR_POS)
	SUB	C			; A = P - L
	NEG				; A = L - P
	INC	A			; +1 for null byte
	LD	C,A
	LD	B,0
	LDIR

	; Redraw box from cursor position
	CALL	REFRESH_BOX_FROM_CURSOR
	JP	INPUT_CHAR_LOOP

INPUT_BS:
	LD	A,(INPUT_CURSOR_POS)
	OR	A
	JP	Z,INPUT_CHAR_LOOP	; At col 0 -> nothing to backspace

	DEC	A
	LD	(INPUT_CURSOR_POS),A

	; Move terminal cursor left 1 column
	LD	A,008H
	CALL	PUTC

	; Fall through to delete character at updated INPUT_CURSOR_POS
	JR	DO_DELETE_CHAR_AT_CURSOR

;------------------------------------------------------------------------------
; REFRESH_BOX_FROM_CURSOR:
; Redraws edit box from INPUT_CURSOR_POS to col 20, then backspaces to
; INPUT_CURSOR_POS. Assumes terminal cursor is currently at INPUT_CURSOR_POS.
; Preserves BC, DE.
;------------------------------------------------------------------------------
REFRESH_BOX_FROM_CURSOR:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	; 1. Print characters from INPUT_CURSOR_POS to INPUT_BUF_LEN
	LD	A,(INPUT_CURSOR_POS)
	LD	E,A
	LD	D,0
	LD	HL,INPUT_FILENAME_BUF
	ADD	HL,DE			; HL = pointer to current char
	LD	A,(INPUT_BUF_LEN)
	SUB	E			; A = INPUT_BUF_LEN - INPUT_CURSOR_POS
	JR	Z,RBFC_SPACES		; If past text, jump to spaces
	LD	B,A
RBFC_CHAR_LOOP:
	LD	A,(HL)
	CALL	PUTC
	INC	HL
	DJNZ	RBFC_CHAR_LOOP

RBFC_SPACES:
	; 2. Print spaces from INPUT_BUF_LEN to 20: (20 - INPUT_BUF_LEN)
	LD	A,20
	LD	HL,INPUT_BUF_LEN
	SUB	(HL)			; A = 20 - INPUT_BUF_LEN
	JR	Z,RBFC_MOVE_BACK
	LD	B,A
RBFC_SPACE_LOOP:
	LD	A,' '
	CALL	PUTC
	DJNZ	RBFC_SPACE_LOOP

RBFC_MOVE_BACK:
	; 3. Emit (20 - INPUT_CURSOR_POS) backspaces to return to cursor
	LD	A,20
	LD	HL,INPUT_CURSOR_POS
	SUB	(HL)			; A = 20 - INPUT_CURSOR_POS
	JR	Z,RBFC_DONE
	LD	B,A
RBFC_BS_LOOP:
	LD	A,008H
	CALL	PUTC
	DJNZ	RBFC_BS_LOOP

RBFC_DONE:
	POP	HL
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; Advance cursor on screen from INPUT_CURSOR_POS to INPUT_BUF_LEN
;------------------------------------------------------------------------------
INPUT_MOVE_CURSOR_TO_END:
	LD	A,(INPUT_CURSOR_POS)
	LD	HL,INPUT_BUF_LEN
	CP	(HL)
	RET	NC			; Already at/past end

	LD	B,(HL)
	SUB	B
	NEG				; A = INPUT_BUF_LEN - INPUT_CURSOR_POS
	LD	B,A
	LD	A,(INPUT_CURSOR_POS)
	LD	HL,INPUT_FILENAME_BUF
	LD	E,A
	LD	D,0
	ADD	HL,DE
IMCTE_LOOP:
	LD	A,(HL)
	CALL	PUTC
	INC	HL
	DJNZ	IMCTE_LOOP
	LD	A,(INPUT_BUF_LEN)
	LD	(INPUT_CURSOR_POS),A
	RET

;------------------------------------------------------------------------------
; Clear "  File not found" inline message if currently visible
; Preserves AF and BC
;------------------------------------------------------------------------------
CHECK_CLEAR_FNF:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	A,(SHOWING_FNF_MSG)
	OR	A
	JR	Z,CLEAR_FNF_DONE

	XOR	A
	LD	(SHOWING_FNF_MSG),A

	; Erase inline message: B backspaces, B spaces, B backspaces
	LD	A,(INLINE_MSG_LEN)
	LD	B,A
ERASE_FNF_BS1:
	LD	A,008H
	CALL	PUTC
	DJNZ	ERASE_FNF_BS1

	LD	A,(INLINE_MSG_LEN)
	LD	B,A
ERASE_FNF_SP:
	LD	A,' '
	CALL	PUTC
	DJNZ	ERASE_FNF_SP

	LD	A,(INLINE_MSG_LEN)
	LD	B,A
ERASE_FNF_BS2:
	LD	A,008H
	CALL	PUTC
	DJNZ	ERASE_FNF_BS2

	; Reset INLINE_MSG_LEN to default 16
	LD	A,16
	LD	(INLINE_MSG_LEN),A

	; Move cursor from after ']' box back inside to INPUT_BUF_LEN:
	; Emit (21 - INPUT_BUF_LEN) backspaces
	LD	A,(INPUT_BUF_LEN)
	LD	B,A
	LD	A,21
	SUB	B
	JR	Z,CLEAR_FNF_DONE
	LD	B,A
ERASE_FNF_RET_BOX:
	LD	A,008H
	CALL	PUTC
	DJNZ	ERASE_FNF_RET_BOX

CLEAR_FNF_DONE:
	POP	HL
	POP	DE
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

	; Non-empty string: advance cursor to end of text
	CALL	INPUT_MOVE_CURSOR_TO_END
	OR	A			; Carry = 0 (success)
	RET

INPUT_ENTER_EMPTY:
	JP	INPUT_CANCEL

;------------------------------------------------------------------------------
; Parse optional :<line> suffix from INPUT_FILENAME_BUF
; If found, stores 16-bit line number in (OPEN_GOTO_LINE).
; Format: [drive:]filename[:line]
;------------------------------------------------------------------------------
PARSE_OPEN_LINE_NUM:
	LD	HL,0
	LD	(OPEN_GOTO_LINE),HL

	LD	A,(INPUT_BUF_LEN)
	OR	A
	RET	Z			; Empty buffer

	; HL = pointer to end of input buffer: INPUT_FILENAME_BUF + length - 1
	LD	E,A
	LD	D,0
	LD	HL,INPUT_FILENAME_BUF
	ADD	HL,DE
	DEC	HL			; HL points to last char of input

	; Trim trailing spaces
POLN_TRIM_SPACES:
	LD	A,(HL)
	CP	' '
	JR	NZ,POLN_CHECK_DIGITS
	DEC	HL
	DEC	E
	JR	NZ,POLN_TRIM_SPACES
	RET				; Only spaces found

POLN_CHECK_DIGITS:
	; Last non-space character must be a digit '0'..'9'
	LD	A,(HL)
	CP	'0'
	RET	C
	CP	'9'+1
	RET	NC

	; Scan backwards past all digits to find preceding ':'
POLN_SCAN_BACK:
	DEC	HL
	DEC	E
	RET	Z			; Hit start of buffer without ':'
	LD	A,(HL)
	CP	':'
	JR	Z,POLN_FOUND_COLON
	CP	'0'
	JR	C,POLN_NOT_NUM
	CP	'9'+1
	JR	C,POLN_SCAN_BACK
POLN_NOT_NUM:
	RET

POLN_FOUND_COLON:
	; HL points to ':' in INPUT_FILENAME_BUF. Check if this colon is inside a drive/user prefix.
	PUSH	HL			; Save colon pointer
	LD	HL,INPUT_FILENAME_BUF
	CALL	PARSE_DRIVE_USER_PREFIX
	JR	NC,POLN_IS_LINE_COLON	; No prefix at start -> line colon

	; Prefix matched: HL is now past the prefix colon!
	POP	DE			; DE = colon pointer
	PUSH	DE
	LD	A,D
	CP	H
	JR	NZ,POLN_CMP
	LD	A,E
	CP	L
POLN_CMP:
	JR	C,POLN_IS_DRIVE_COLON	; DE < HL -> colon is part of prefix!

POLN_IS_LINE_COLON:
	POP	HL			; Restore colon pointer
	INC	HL			; HL points to digits
	CALL	PARSE_DEC_WORD		; DE = 16-bit parsed value
	LD	(OPEN_GOTO_LINE),DE
	RET

POLN_IS_DRIVE_COLON:
	POP	HL			; Restore colon pointer
	RET

;------------------------------------------------------------------------------
; Parse Filename String (e.g. "C1:TEST.DAT", "1C:TEST.DAT", "1:TEST.DAT", "TEST.DAT")
; PARSE_FILENAME_TO_FCB: parses INPUT_FILENAME_BUF
; PARSE_STRING_TO_FCB: parses string pointed to by HL
; Outputs: WORK_FCB populated, WORK_FCB_USER populated
;------------------------------------------------------------------------------
PARSE_FILENAME_TO_FCB:
	LD	HL,INPUT_FILENAME_BUF

PARSE_STRING_TO_FCB:
	PUSH	HL

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

	POP	HL

	; Skip leading spaces
PARSE_SKIP_SPACES:
	LD	A,(HL)
	CP	' '
	JR	NZ,PARSE_CHECK_PREFIX
	INC	HL
	JR	PARSE_SKIP_SPACES

PARSE_CHECK_PREFIX:
	CALL	PARSE_DRIVE_USER_PREFIX
	JR	NC,PARSE_NO_PREFIX

	; Prefix matched!
	; Check drive
	LD	A,(PREFIX_DRIVE)
	OR	A
	JR	NZ,PSTF_USE_PDRIVE
	LD	A,(CURRENT_DIR_DRIVE)
PSTF_USE_PDRIVE:
	LD	(WORK_FCB),A

	; Check user
	LD	A,(PREFIX_USER)
	CP	0FFH
	JR	NZ,PSTF_USE_PUSER
	LD	A,(CURRENT_DIR_USER)
PSTF_USE_PUSER:
	LD	(WORK_FCB_USER),A
	JR	PARSE_NAME_START

PARSE_NO_PREFIX:
	LD	A,(CURRENT_DIR_DRIVE)
	LD	(WORK_FCB),A
	LD	A,(CURRENT_DIR_USER)
	LD	(WORK_FCB_USER),A

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
	CP	':'
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
	CP	':'
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
	CP	':'
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
; SAVE_BLOCK_FILE: Streams active solidified block text to disk (WORK_FCB)
; Formats line endings according to SAVE_FORMAT (CRLF or LF).
;------------------------------------------------------------------------------
SAVE_BLOCK_FILE:
	; Guard: if target drive is hibernated RAM drive, reject save
	CALL	CHECK_FCB_IS_HIBERNATED
	JR	NC,SAVE_BLK_DRIVE_OK
	SCF
	RET

SAVE_BLK_DRIVE_OK:
	; Set BDOS user area to WORK_FCB_USER
	LD	A,(WORK_FCB_USER)
	LD	E,A
	LD	C,32			; BDOS Set User Area
	CALL	BDOS_ENTRY

	; Flush local cache dirty lines first
	CALL	FLUSH_DIRTY_CACHE

	LD	A,(WORK_FCB+1)
	CP	' '
	JP	NZ,DO_SAVE_BLK_EXISTING

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

DO_SAVE_BLK_EXISTING:
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
	JR	NZ,MAKE_BLK_FILE_OK

	; Restore BDOS user area to CURRENT_DIR_USER
	LD	A,(CURRENT_DIR_USER)
	LD	E,A
	LD	C,32			; BDOS Set User Area
	CALL	BDOS_ENTRY
	SCF
	RET

MAKE_BLK_FILE_OK:
	CALL	INIT_SAVE_PROGRESS

	; Prepare DMA write pointer
	LD	DE,DEFAULT_DMA
	LD	(CUR_DMA_PTR),DE
	LD	A,128
	LD	(DMA_BYTES_LEFT),A

	; Check if block is empty:
	; BLOCK_START_ROW == BLOCK_END_ROW and BLOCK_START_COL == BLOCK_END_COL
	LD	HL,(BLOCK_START_ROW)
	LD	DE,(BLOCK_END_ROW)
	LD	A,H
	CP	D
	JR	NZ,SBF_NON_EMPTY
	LD	A,L
	CP	E
	JR	NZ,SBF_NON_EMPTY
	LD	HL,(BLOCK_START_COL)
	LD	DE,(BLOCK_END_COL)
	LD	A,H
	CP	D
	JR	NZ,SBF_NON_EMPTY
	LD	A,L
	CP	E
	JR	NZ,SBF_NON_EMPTY
	; Block is completely empty -> flush and close (0 bytes written)
	JP	SAVE_FLUSH_REMAINDER

SBF_NON_EMPTY:
	; Check if single-line or multi-line
	LD	HL,(BLOCK_START_ROW)
	LD	DE,(BLOCK_END_ROW)
	LD	A,H
	CP	D
	JP	NZ,SBF_MULTILINE
	LD	A,L
	CP	E
	JP	NZ,SBF_MULTILINE

	;--------------------------------------------------------------------------
	; Single-Line Block
	;--------------------------------------------------------------------------
	LD	BC,(BLOCK_START_ROW)
	LD	DE,SPLIT_LINE_TEMP
	LD	HL,MAX_ACTIVE_LINE_STRIDE-2
	CALL	READ_FAR_LINE_MAX

	; Advance HL in SPLIT_LINE_TEMP to BLOCK_START_COL
	LD	HL,SPLIT_LINE_TEMP
	LD	BC,(BLOCK_START_COL)
SBF_SGL_ADV:
	LD	A,B
	OR	C
	JR	Z,SBF_SGL_AT_START
	LD	A,(HL)
	OR	A
	JP	Z,SAVE_FLUSH_REMAINDER	; Line ended before BLOCK_START_COL
	INC	HL
	DEC	BC
	JR	SBF_SGL_ADV

SBF_SGL_AT_START:
	; Number of chars to stream: BC = BLOCK_END_COL - BLOCK_START_COL
	LD	DE,(BLOCK_START_COL)
	LD	BC,(BLOCK_END_COL)
	LD	A,C
	SUB	E
	LD	C,A
	LD	A,B
	SBC	A,D
	LD	B,A
	JP	C,SAVE_FLUSH_REMAINDER
	OR	C
	JP	Z,SAVE_FLUSH_REMAINDER

SBF_SGL_STREAM:
	LD	A,B
	OR	C
	JR	Z,SBF_SGL_DONE
	LD	A,(HL)
	OR	A
	JR	Z,SBF_SGL_DONE		; Line ended before BLOCK_END_COL
	CALL	WRITE_BYTE_TO_DMA
	INC	HL
	DEC	BC
	JR	SBF_SGL_STREAM

SBF_SGL_DONE:
	CALL	WRITE_SAVE_LINE_ENDING
	CALL	TICK_SAVE_PROGRESS
	JP	SAVE_FLUSH_REMAINDER

	;--------------------------------------------------------------------------
	; Multi-Line Block
	;--------------------------------------------------------------------------
SBF_MULTILINE:
	; Step 1: Head row (BLOCK_START_ROW), from BLOCK_START_COL to end of line
	LD	BC,(BLOCK_START_ROW)
	LD	DE,SPLIT_LINE_TEMP
	LD	HL,MAX_ACTIVE_LINE_STRIDE-2
	CALL	READ_FAR_LINE_MAX

	LD	HL,SPLIT_LINE_TEMP
	LD	BC,(BLOCK_START_COL)
SBF_ML_HEAD_ADV:
	LD	A,B
	OR	C
	JR	Z,SBF_ML_HEAD_STREAM
	LD	A,(HL)
	OR	A
	JR	Z,SBF_ML_HEAD_DONE
	INC	HL
	DEC	BC
	JR	SBF_ML_HEAD_ADV

SBF_ML_HEAD_STREAM:
	LD	A,(HL)
	OR	A
	JR	Z,SBF_ML_HEAD_DONE
	CALL	WRITE_BYTE_TO_DMA
	INC	HL
	JR	SBF_ML_HEAD_STREAM

SBF_ML_HEAD_DONE:
	CALL	WRITE_SAVE_LINE_ENDING
	CALL	TICK_SAVE_PROGRESS

	; Step 2: Middle rows: from (BLOCK_START_ROW + 1) to (BLOCK_END_ROW - 1)
	LD	BC,(BLOCK_START_ROW)
	INC	BC
SBF_ML_MID_LOOP:
	LD	HL,(BLOCK_END_ROW)
	LD	A,H
	CP	B
	JR	NZ,SBF_ML_MID_COMPARE
	LD	A,L
	CP	C
	JR	Z,SBF_ML_TAIL
SBF_ML_MID_COMPARE:
	PUSH	BC
	LD	DE,SPLIT_LINE_TEMP
	LD	HL,MAX_ACTIVE_LINE_STRIDE-2
	CALL	READ_FAR_LINE_MAX

	LD	HL,SPLIT_LINE_TEMP
SBF_ML_MID_STREAM:
	LD	A,(HL)
	OR	A
	JR	Z,SBF_ML_MID_LINE_DONE
	CALL	WRITE_BYTE_TO_DMA
	INC	HL
	JR	SBF_ML_MID_STREAM

SBF_ML_MID_LINE_DONE:
	CALL	WRITE_SAVE_LINE_ENDING
	CALL	TICK_SAVE_PROGRESS
	POP	BC
	INC	BC
	JR	SBF_ML_MID_LOOP

	; Step 3: Tail row (BLOCK_END_ROW)
SBF_ML_TAIL:
	LD	HL,(BLOCK_END_COL)
	LD	A,H
	OR	L
	JP	Z,SAVE_FLUSH_REMAINDER

	LD	BC,(BLOCK_END_ROW)
	LD	DE,SPLIT_LINE_TEMP
	LD	HL,MAX_ACTIVE_LINE_STRIDE-2
	CALL	READ_FAR_LINE_MAX

	LD	HL,SPLIT_LINE_TEMP
	LD	BC,(BLOCK_END_COL)
SBF_ML_TAIL_STREAM:
	LD	A,B
	OR	C
	JR	Z,SBF_ML_TAIL_DONE
	LD	A,(HL)
	OR	A
	JR	Z,SBF_ML_TAIL_DONE
	CALL	WRITE_BYTE_TO_DMA
	INC	HL
	DEC	BC
	JR	SBF_ML_TAIL_STREAM

SBF_ML_TAIL_DONE:
	CALL	WRITE_SAVE_LINE_ENDING
	CALL	TICK_SAVE_PROGRESS
	JP	SAVE_FLUSH_REMAINDER

WRITE_SAVE_LINE_ENDING:
	LD	A,(SAVE_FORMAT)
	CP	FMT_CPM
	JR	NZ,WSLE_LF_ONLY
	LD	A,13
	CALL	WRITE_BYTE_TO_DMA
WSLE_LF_ONLY:
	LD	A,10
	CALL	WRITE_BYTE_TO_DMA
	RET

;------------------------------------------------------------------------------
; Save Progress Indicator Routines
;------------------------------------------------------------------------------
INIT_SAVE_PROGRESS:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	DE,STR_HIDE_CURSOR
	CALL	PRINT_STR
	LD	A,1
	LD	(IS_SAVING_FILE),A
	LD	HL,0
	LD	(LOAD_PROGRESS_LINES),HL
	LD	A,100
	LD	(LOAD_PROGRESS_COUNT),A
	CALL	RENDER_STATUS_BAR
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

TICK_SAVE_PROGRESS:
	PUSH	AF
	PUSH	HL
	LD	HL,(LOAD_PROGRESS_LINES)
	INC	HL
	LD	(LOAD_PROGRESS_LINES),HL
	LD	HL,LOAD_PROGRESS_COUNT
	DEC	(HL)
	JR	NZ,TSP_DONE
	LD	(HL),100
	CALL	UPDATE_LOAD_PROGRESS
TSP_DONE:
	POP	HL
	POP	AF
	RET

FINISH_SAVE_PROGRESS:
	PUSH	AF
	PUSH	DE
	CALL	UPDATE_LOAD_PROGRESS
	JR	CSP_COMMON

CLEANUP_SAVE_PROGRESS:
	PUSH	AF
	PUSH	DE
CSP_COMMON:
	XOR	A
	LD	(IS_SAVING_FILE),A
	LD	DE,STR_SHOW_CURSOR
	CALL	PRINT_STR
	POP	DE
	POP	AF
	RET

;------------------------------------------------------------------------------
; File Saving: Streams lines directly from Far RAM banks to disk
;------------------------------------------------------------------------------
SAVE_FILE:
	; Guard: if target drive is hibernated RAM drive, reject save
	CALL	CHECK_FCB_IS_HIBERNATED
	JR	NC,SAVE_DRIVE_OK
	SCF
	RET

SAVE_DRIVE_OK:
	; Set BDOS user area to WORK_FCB_USER
	LD	A,(WORK_FCB_USER)
	LD	E,A
	LD	C,32			; BDOS Set User Area
	CALL	BDOS_ENTRY

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
	JR	NZ,MAKE_FILE_OK
	; Restore BDOS user area to CURRENT_DIR_USER
	LD	A,(CURRENT_DIR_USER)
	LD	E,A
	LD	C,32			; BDOS Set User Area
	CALL	BDOS_ENTRY
	SCF
	RET

MAKE_FILE_OK:
	CALL	INIT_SAVE_PROGRESS

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
	PUSH	BC			; BC = document line index

	; Lookup head slot ID: line BC in Far RAM line table
	CALL	GET_LINE_SLOT		; HL = head slot ID
	LD	B,H
	LD	C,L			; BC = head slot ID

SAVE_STRIDE_LOOP:
	; Check if slot ID is 0xFFFF (SLOT_TERM)
	LD	A,B
	AND	C
	INC	A
	JR	Z,SAVE_LINE_END

	; Read slot BC into FAR_IO_BUF
	LD	DE,FAR_IO_BUF
	CALL	READ_FAR_SLOT

	; Next slot ID is in FAR_IO_BUF[0..1]
	LD	HL,(FAR_IO_BUF)
	LD	(SAVE_NEXT_SLOT),HL

	; Stream payload from FAR_IO_BUF+2
	LD	HL,FAR_IO_BUF+2
	LD	B,FAR_SLOT_PAYLOAD	; 126 bytes max
SAVE_PAYLOAD_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,SAVE_LINE_END		; Null terminator reached: this line is complete!
	CALL	WRITE_BYTE_TO_DMA
	INC	HL
	DJNZ	SAVE_PAYLOAD_LOOP

	; Stride exhausted (all 126 bytes emitted): advance to next slot in chain
	LD	BC,(SAVE_NEXT_SLOT)
	JR	SAVE_STRIDE_LOOP

SAVE_LINE_END:
	CALL	WRITE_SAVE_LINE_ENDING
	CALL	TICK_SAVE_PROGRESS
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
	CP	0FFH
	JR	NZ,CLOSE_FILE_OK
	CALL	CLEANUP_SAVE_PROGRESS
	; Restore BDOS user area to CURRENT_DIR_USER
	LD	A,(CURRENT_DIR_USER)
	LD	E,A
	LD	C,32			; BDOS Set User Area
	CALL	BDOS_ENTRY
	SCF
	RET
CLOSE_FILE_OK:
	CALL	FINISH_SAVE_PROGRESS
	; If this was NOT a block save, update DOC_USER_NUM and CURRENT_DIR_USER
	LD	A,(IS_BLOCK_SAVE_UI)
	OR	A
	JR	NZ,CFO_IS_BLK
	LD	A,(WORK_FCB_USER)
	LD	(DOC_USER_NUM),A
	LD	(CURRENT_DIR_USER),A
CFO_IS_BLK:
	; Restore BDOS user area to CURRENT_DIR_USER
	LD	A,(CURRENT_DIR_USER)
	LD	E,A
	LD	C,32			; BDOS Set User Area
	CALL	BDOS_ENTRY
	OR	A			; Carry = 0 (success)
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

;==============================================================================
; Plugin Subsystem (CP/M 3 PRL & OVL Modular Architecture)
; Modular 4K/16K/32K Slots, Dynamic Multi-Bank Far RAM Allocation, TPA Overlay
;==============================================================================
PLUGIN_ENTRY_SIZE	EQU	32		; 32-byte registry entries
PLUGIN_MAX_SLOTS	EQU	8		; 8 slots
PLUGIN_UI_LINES		EQU	17

; Capabilities bitflags
CAP_TPA_EXEC		EQU	0001H
CAP_FAR_EXEC		EQU	0002H
CAP_DOC_MUTATE		EQU	0004H
CAP_MODAL_UI		EQU	0008H
CAP_HAS_ABOUT		EQU	0010H
CAP_HAS_CONFIG		EQU	0020H
CAP_SIZE_4K		EQU	0000H
CAP_SIZE_8K		EQU	0040H
CAP_SIZE_16K		EQU	0080H
CAP_SIZE_32K		EQU	00C0H
CAP_SIZE_MASK		EQU	00C0H

INIT_PLUGIN_REGISTRY:
	LD	HL,PLUGIN_REGISTRY
	LD	(HL),0
	LD	DE,PLUGIN_REGISTRY+1
	LD	BC,(PLUGIN_MAX_SLOTS * PLUGIN_ENTRY_SIZE) - 1
	LDIR
	XOR	A
	LD	(PLUGIN_LOAD_COUNT),A
	LD	(BORROWED_BANKS_CNT),A
	RET

BORROW_NEW_FAR_BANK:
	LD	A,(EXT_BANK_COUNT)
	OR	A
	JR	Z,BNFB_FAIL		; No banks left in EXT_BANK_TABLE
	CP	2
	JR	NC,BNFB_OK		; >= 2 banks left: always safe to borrow!
	; Exactly 1 bank left. Only allow borrowing if not actively editing a document
	LD	A,(IN_EDITOR_MODE)
	OR	A
	JR	NZ,BNFB_FAIL		; Active document in editor: protect bank 0!
BNFB_OK:
	LD	A,(EXT_BANK_COUNT)
	DEC	A
	LD	(EXT_BANK_COUNT),A	; Decrement available document banks
	LD	E,A
	LD	D,0
	LD	HL,EXT_BANK_TABLE
	ADD	HL,DE
	LD	A,(HL)			; A = Stolen Far RAM Bank ID

	; Record in BORROWED_BANKS_TBL
	PUSH	AF
	LD	HL,BORROWED_BANKS_CNT
	LD	C,(HL)
	INC	(HL)
	LD	B,0
	LD	HL,BORROWED_BANKS_TBL
	ADD	HL,BC
	POP	AF
	LD	(HL),A			; Store bank ID in table

	OR	A			; Carry = 0
	RET
BNFB_FAIL:
	SCF				; Carry = 1
	RET

RELEASE_FAR_BANK:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL

	LD	C,A			; C = Bank ID to release

	; 1. Remove from BORROWED_BANKS_TBL
	LD	A,(BORROWED_BANKS_CNT)
	OR	A
	JR	Z,RFB_RETURN_TO_EXT
	LD	B,A
	LD	HL,BORROWED_BANKS_TBL
RFB_FIND_LOOP:
	LD	A,(HL)
	CP	C
	JR	Z,RFB_FOUND
	INC	HL
	DJNZ	RFB_FIND_LOOP
	JR	RFB_RETURN_TO_EXT

RFB_FOUND:
	DEC	B
	JR	Z,RFB_DEC_CNT
	LD	D,H
	LD	E,L
	INC	HL
RFB_SHIFT_LOOP:
	LD	A,(HL)
	LD	(DE),A
	INC	DE
	INC	HL
	DJNZ	RFB_SHIFT_LOOP
RFB_DEC_CNT:
	LD	HL,BORROWED_BANKS_CNT
	DEC	(HL)

RFB_RETURN_TO_EXT:
	; 2. Add bank back to EXT_BANK_TABLE
	LD	A,(EXT_BANK_COUNT)
	LD	E,A
	LD	D,0
	LD	HL,EXT_BANK_TABLE
	ADD	HL,DE
	LD	(HL),C			; Put bank C back
	LD	HL,EXT_BANK_COUNT
	INC	(HL)

RFB_DONE:
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

IS_RANGE_FREE_IN_BANK:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	; Guard: If target bank is PLUGIN_MGR_BANK, it is dedicated to PLUGIN.PRL
	LD	HL,PLUGIN_MGR_BANK
	CP	(HL)
	JR	Z,IRFIB_OVERLAP_DED

	; Candidate range: [C, C + E) in Bank A
	LD	(IRF_TARGET_BANK),A
	LD	A,C
	ADD	A,E
	LD	(IRF_CAND_EC),A

	; Scan slots 0..7
	LD	B,0
IRFIB_LOOP:
	PUSH	BC
	CALL	GET_REGISTRY_ENTRY_PTR
	POP	BC

	; Check SLOT_STATE at HL+22
	PUSH	HL
	LD	DE,22
	ADD	HL,DE
	LD	A,(HL)
	OR	A
	JR	Z,IRFIB_POP_NEXT

	; Check FAR_BANK at HL+24
	INC	HL
	INC	HL
	LD	A,(IRF_TARGET_BANK)
	CP	(HL)			; Compare with Target Bank
	JR	NZ,IRFIB_POP_NEXT

	; Slot is in the same bank. Get Sj (at HL+25) and Pj (at HL+27)
	INC	HL			; HL points to +25 (BASE_PAGE)
	LD	E,(HL)			; E = Sj
	INC	HL
	INC	HL			; HL points to +27 (PAGE_COUNT)
	LD	D,(HL)			; D = Pj
	POP	HL			; Restore HL = entry ptr

	; Calculate Ej = Sj + Pj
	LD	A,E			; A = Sj
	ADD	A,D			; A = Ej

	; Overlap: (Sc < Ej) AND (Sj < Ec)
	; 1. If Sc >= Ej (i.e. Ej <= Sc), no overlap
	CP	C
	JR	Z,IRFIB_NEXT_SLOT
	JR	C,IRFIB_NEXT_SLOT

	; 2. If Sj >= Ec (i.e. Ec <= Sj), no overlap
	LD	A,(IRF_CAND_EC)
	CP	E
	JR	Z,IRFIB_NEXT_SLOT
	JR	C,IRFIB_NEXT_SLOT

	; Overlap detected!
	SCF
	JR	IRFIB_DONE

IRFIB_POP_NEXT:
	POP	HL
IRFIB_NEXT_SLOT:
	INC	B
	LD	A,B
	CP	PLUGIN_MAX_SLOTS
	JR	NZ,IRFIB_LOOP

	; No active slot overlapped: range is free!
	OR	A			; Carry = 0
IRFIB_DONE:
	POP	HL
	POP	DE
	POP	BC
	RET

IRFIB_OVERLAP_DED:
	POP	HL
	POP	DE
	POP	BC
	SCF				; Carry = 1 (bank is reserved/occupied)
	RET

ALLOC_FAR_PLUGIN_SLOT:
	; Input: A = SIZE_CLASS (0=4K, 1=16K, 2=32K)
	; Output: Carry=0 on success, A=FAR_BANK, C=BASE_PAGE, E=PAGE_COUNT
	;         Carry=1 on failure
	LD	(ALLOC_SIZE_CLASS),A
	OR	A
	JR	NZ,AFPS_DEDICATED_BANK

	; --- 4KB Plugin Allocation (Sub-allocated in 4KB slots) ---
	LD	E,16			; 4K: 16 pages
	LD	A,E
	LD	(ALLOC_PAGE_COUNT),A

	; Search existing borrowed banks for a free 4K page range
	LD	A,(BORROWED_BANKS_CNT)
	OR	A
	JR	Z,AFPS_NEED_NEW_BANK

	LD	B,A
	LD	HL,BORROWED_BANKS_TBL
AFPS_BANK_LOOP:
	PUSH	BC
	PUSH	HL
	LD	A,(HL)			; A = bank ID
	LD	(ALLOC_TEMP_BANK),A

	; Candidates for 4K: 0x00, 0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70
	LD	C,0
	LD	B,8
AFPS_CAND_4K_LOOP:
	PUSH	BC
	LD	A,(ALLOC_TEMP_BANK)
	LD	E,16
	CALL	IS_RANGE_FREE_IN_BANK
	POP	BC
	JR	NC,AFPS_FOUND_IN_BANK
	LD	A,C
	ADD	A,16
	LD	C,A
	DJNZ	AFPS_CAND_4K_LOOP

	POP	HL
	POP	BC
	INC	HL
	DJNZ	AFPS_BANK_LOOP
	JR	AFPS_NEED_NEW_BANK

	; --- 8K / 16K / 32K Dedicated Bank Allocation (Always BASE_PAGE = 0) ---
AFPS_DEDICATED_BANK:
	CP	1
	JR	NZ,AFPS_NOT_8K
	LD	E,32			; 8K: 32 pages
	JR	AFPS_GOT_DED_PAGES
AFPS_NOT_8K:
	CP	2
	JR	NZ,AFPS_IS_32K
	LD	E,64			; 16K: 64 pages
	JR	AFPS_GOT_DED_PAGES
AFPS_IS_32K:
	LD	E,128			; 32K: 128 pages
AFPS_GOT_DED_PAGES:
	LD	A,E
	LD	(ALLOC_PAGE_COUNT),A

	; Check if any existing borrowed bank is completely free (C=0, E=128)
	LD	A,(BORROWED_BANKS_CNT)
	OR	A
	JR	Z,AFPS_NEED_NEW_BANK

	LD	B,A
	LD	HL,BORROWED_BANKS_TBL
AFPS_DED_LOOP:
	PUSH	BC
	PUSH	HL
	LD	A,(HL)			; A = bank ID
	LD	(ALLOC_TEMP_BANK),A
	LD	C,0
	LD	E,128
	CALL	IS_RANGE_FREE_IN_BANK
	JR	NC,AFPS_FOUND_IN_BANK
	POP	HL
	POP	BC
	INC	HL
	DJNZ	AFPS_DED_LOOP
	JR	AFPS_NEED_NEW_BANK

AFPS_NEED_NEW_BANK:
	CALL	BORROW_NEW_FAR_BANK
	JR	C,AFPS_FAIL

	; New bank always has 0x00 free
	PUSH	AF			; Preserve new bank ID
	LD	C,0
	LD	HL,ALLOC_PAGE_COUNT
	LD	E,(HL)
	POP	AF			; Restore new bank ID
	OR	A			; Carry = 0
	RET

AFPS_FOUND_IN_BANK:
	LD	A,C			; Preserve candidate start page
	POP	HL
	POP	BC
	LD	C,A			; Restore candidate start page into C
	LD	HL,ALLOC_PAGE_COUNT
	LD	E,(HL)
	LD	A,(ALLOC_TEMP_BANK)
	OR	A			; Carry = 0
	RET

AFPS_FAIL:
	SCF				; Carry = 1
	RET

CALC_FAR_SLOT_ADDR:
	LD	B,A
	CALL	GET_REGISTRY_ENTRY_PTR
	LD	DE,25
	ADD	HL,DE
	LD	A,(HL)
	LD	H,A
	LD	L,0
	RET

GET_REGISTRY_ENTRY_PTR:
	LD	A,B
	AND	07H
	LD	L,A
	LD	H,0
	ADD	HL,HL			; * 2
	ADD	HL,HL			; * 4
	ADD	HL,HL			; * 8
	ADD	HL,HL			; * 16
	ADD	HL,HL			; * 32
	LD	DE,PLUGIN_REGISTRY
	ADD	HL,DE
	RET

LOAD_PLUGIN_BY_NAME:
	PUSH	DE			; Preserve filename string pointer

	; Find free slot in PLUGIN_REGISTRY
	LD	B,0
LPBN_FIND_FREE:
	PUSH	BC
	CALL	GET_REGISTRY_ENTRY_PTR
	LD	DE,22
	ADD	HL,DE
	LD	A,(HL)
	POP	BC
	OR	A
	JR	Z,LPBN_FOUND_FREE
	INC	B
	LD	A,B
	CP	PLUGIN_MAX_SLOTS
	JR	NZ,LPBN_FIND_FREE

LPBN_NO_FREE_SLOT:
	POP	DE
	SCF				; All slots full
	RET

LPBN_FOUND_FREE:
	LD	A,B
	LD	(PLUGIN_CUR_SLOT),A

	POP	HL			; HL = filename string pointer
	CALL	PARSE_STRING_TO_PLUGIN_FCB

	; Query current BDOS user area (BDOS 32, E=0xFF) into PLUGIN_ORIG_USER
	LD	E,0FFH
	LD	C,32
	CALL	BDOS_ENTRY
	LD	(PLUGIN_ORIG_USER),A

	; Switch BDOS user area to target user area (PLUGIN_USER_AREA)
	LD	A,(PLUGIN_USER_AREA)
	LD	E,A
	LD	C,32
	CALL	BDOS_ENTRY

	; Check if extension in PLUGIN_FCB is blank ("   ")
	LD	A,(PLUGIN_FCB+9)
	CP	' '
	JR	NZ,LPBN_DO_OPEN_DIRECT

	; Auto-try .PRL extension first
	LD	HL,PLUGIN_FCB+9
	LD	(HL),'P'
	INC	HL
	LD	(HL),'R'
	INC	HL
	LD	(HL),'L'
	LD	DE,PLUGIN_FCB
	LD	C,15			; BDOS Open File
	CALL	BDOS_ENTRY
	CP	0FFH
	JR	NZ,LPBN_OPEN_OK

	; .PRL not found -> try .OVL extension
	LD	HL,PLUGIN_FCB+9
	LD	(HL),'O'
	INC	HL
	LD	(HL),'V'
	INC	HL
	LD	(HL),'L'
	; Reset extent/record fields before re-open
	XOR	A
	LD	(PLUGIN_FCB+12),A	; EX = 0
	LD	(PLUGIN_FCB+13),A	; S1 = 0
	LD	(PLUGIN_FCB+14),A	; S2 = 0
	LD	(PLUGIN_FCB+15),A	; RC = 0
	LD	(PLUGIN_FCB+32),A	; CR = 0
	LD	DE,PLUGIN_FCB
	LD	C,15			; BDOS Open File
	CALL	BDOS_ENTRY
	CP	0FFH
	JR	NZ,LPBN_OPEN_OK
	JP	LPBN_NOT_FOUND

LPBN_DO_OPEN_DIRECT:
	LD	DE,PLUGIN_FCB
	LD	C,15			; BDOS Open File
	CALL	BDOS_ENTRY
	CP	0FFH
	JP	Z,LPBN_NOT_FOUND

LPBN_OPEN_OK:

	; Set BDOS DMA to scratch buffer at LINE_STORAGE + 4096
	LD	DE,LINE_STORAGE + 4096
	LD	C,26
	CALL	BDOS_ENTRY

	; Read first 2 sectors (256-byte header)
	LD	DE,PLUGIN_FCB
	LD	C,20
	CALL	BDOS_ENTRY
	OR	A
	JP	NZ,LPBN_READ_ERR

	LD	DE,LINE_STORAGE + 4096 + 128
	LD	C,26
	CALL	BDOS_ENTRY

	LD	DE,PLUGIN_FCB
	LD	C,20
	CALL	BDOS_ENTRY
	OR	A
	JP	NZ,LPBN_READ_ERR

	; Parse Capabilities & Size Class from Header
	; Capabilities word at offset 1Ch (LINE_STORAGE + 4096 + 28)
	LD	A,(LINE_STORAGE + 4096 + 28)
	AND	CAP_SIZE_MASK		; Bits 7..6

	; Map size bits to SIZE_CLASS (0=4K, 1=8K, 2=16K, 3=32K)
	OR	A
	JR	NZ,LPBN_CHK_8K
	XOR	A
	LD	(LOAD_SIZE_CLASS),A
	; Check PROG_SIZE <= 4096
	LD	HL,(LINE_STORAGE + 4096 + 1)
	LD	DE,4097
	CALL	CMP_HL_DE
	JP	NC,LPBN_TOO_LARGE
	JR	LPBN_SIZE_OK

LPBN_CHK_8K:
	CP	CAP_SIZE_8K
	JR	NZ,LPBN_CHK_16K
	LD	A,1
	LD	(LOAD_SIZE_CLASS),A
	; Check PROG_SIZE <= 8192
	LD	HL,(LINE_STORAGE + 4096 + 1)
	LD	DE,8193
	CALL	CMP_HL_DE
	JP	NC,LPBN_TOO_LARGE
	; Check TPA restriction: bit 0 of capabilities MUST NOT be set
	LD	A,(LINE_STORAGE + 4096 + 28)
	BIT	0,A
	JP	NZ,LPBN_TOO_LARGE
	JR	LPBN_SIZE_OK

LPBN_CHK_16K:
	CP	CAP_SIZE_16K
	JR	NZ,LPBN_CHK_32K
	LD	A,2
	LD	(LOAD_SIZE_CLASS),A
	; Check PROG_SIZE <= 16384
	LD	HL,(LINE_STORAGE + 4096 + 1)
	LD	DE,16385
	CALL	CMP_HL_DE
	JP	NC,LPBN_TOO_LARGE
	; Check TPA restriction: bit 0 of capabilities MUST NOT be set
	LD	A,(LINE_STORAGE + 4096 + 28)
	BIT	0,A
	JP	NZ,LPBN_TOO_LARGE
	JR	LPBN_SIZE_OK

LPBN_CHK_32K:
	LD	A,3
	LD	(LOAD_SIZE_CLASS),A
	; Check PROG_SIZE <= 32768
	LD	HL,(LINE_STORAGE + 4096 + 1)
	LD	DE,8001H
	CALL	CMP_HL_DE
	JP	NC,LPBN_TOO_LARGE
	; Check TPA restriction: bit 0 of capabilities MUST NOT be set
	LD	A,(LINE_STORAGE + 4096 + 28)
	BIT	0,A
	JP	NZ,LPBN_TOO_LARGE

LPBN_SIZE_OK:
	; Allocate Far RAM slot for this plugin
	LD	A,(LOAD_SIZE_CLASS)
	CALL	ALLOC_FAR_PLUGIN_SLOT
	JP	C,LPBN_ALLOC_FAIL

	; ALLOC_FAR_PLUGIN_SLOT returned A=FAR_BANK, C=BASE_PAGE, E=PAGE_COUNT
	LD	(LOAD_FAR_BANK),A
	LD	A,C
	LD	(LOAD_BASE_PAGE),A
	LD	A,E
	LD	(LOAD_PAGE_COUNT),A

	; Slot base address: H = BASE_PAGE, L = 0
	LD	A,(LOAD_BASE_PAGE)
	LD	H,A
	LD	L,0
	LD	(FAR_SLOT_BASE_ADDR),HL

	; Copy 256-byte header to LOAD_FAR_BANK at FAR_SLOT_BASE_ADDR
	PUSH	IX
	LD	B,0F4H
	LD	A,(LOAD_FAR_BANK)
	LD	D,A
	LD	A,(CPM_USER_BANK)
	LD	E,A
	LD	HL,256
	RST	08H
	POP	IX

	PUSH	IX
	LD	B,0F5H
	LD	HL,LINE_STORAGE + 4096
	LD	DE,(FAR_SLOT_BASE_ADDR)
	RST	08H
	POP	IX

	CALL	REGISTER_SLOT_METADATA

	; Calculate sectors for code + relocation bitmap
	LD	HL,(LINE_STORAGE + 4096 + 1)	; PROG_SIZE
	LD	DE,(LINE_STORAGE + 4096 + 7)	; LOAD_ADDR
	LD	A,D
	OR	E
	JR	NZ,LPBN_PAYLOAD_OVL

	; 16K/32K Far plugins strictly run in Far RAM; skip trailing bitmap
	LD	A,(LOAD_SIZE_CLASS)
	OR	A
	JR	NZ,LPBN_PAYLOAD_OVL

	; PRL bitmap size: (PROG_SIZE + 7) / 8
	PUSH	HL
	LD	DE,7
	ADD	HL,DE
	SRL	H
	RR	L
	SRL	H
	RR	L
	SRL	H
	RR	L
	POP	DE
	ADD	HL,DE				; PROG_SIZE + bitmap
LPBN_PAYLOAD_OVL:
	LD	DE,127
	ADD	HL,DE
	SRL	H
	RR	L
	SRL	H
	RR	L
	SRL	H
	RR	L
	SRL	H
	RR	L
	SRL	H
	RR	L
	SRL	H
	RR	L
	SRL	H
	RR	L
	LD	(PAYLOAD_SECTORS_REMAIN),HL	; 16-bit sector count (0..256)

	LD	HL,(FAR_SLOT_BASE_ADDR)
	INC	H				; + 256 bytes
	LD	(FAR_SECT_DEST),HL

LPBN_SECTOR_LOOP:
	LD	HL,(PAYLOAD_SECTORS_REMAIN)
	LD	A,H
	OR	L
	JR	Z,LPBN_SECTORS_DONE
	DEC	HL
	LD	(PAYLOAD_SECTORS_REMAIN),HL

	LD	DE,LINE_STORAGE + 4096
	LD	C,26
	CALL	BDOS_ENTRY

	LD	DE,PLUGIN_FCB
	LD	C,20
	CALL	BDOS_ENTRY
	OR	A
	JR	NZ,LPBN_SECTOR_EOF

	PUSH	IX
	LD	B,0F4H
	LD	A,(LOAD_FAR_BANK)
	LD	D,A
	LD	A,(CPM_USER_BANK)
	LD	E,A
	LD	HL,128
	RST	08H
	POP	IX

	PUSH	IX
	LD	B,0F5H
	LD	HL,LINE_STORAGE + 4096
	LD	DE,(FAR_SECT_DEST)
	RST	08H
	POP	IX

	LD	HL,(FAR_SECT_DEST)
	LD	DE,128
	ADD	HL,DE
	LD	(FAR_SECT_DEST),HL

	; Guard: prevent Far RAM writes crossing into Common RAM (>= 8000h)
	LD	A,H
	CP	080H
	JR	NC,LPBN_SECTORS_DONE

	JR	LPBN_SECTOR_LOOP

LPBN_SECTOR_EOF:
LPBN_SECTORS_DONE:
	LD	DE,PLUGIN_FCB
	LD	C,16
	CALL	BDOS_ENTRY

	; Restore BDOS user area to PLUGIN_ORIG_USER
	LD	A,(PLUGIN_ORIG_USER)
	LD	E,A
	LD	C,32
	CALL	BDOS_ENTRY

	LD	DE,0080H
	LD	C,26
	CALL	BDOS_ENTRY

	LD	A,(PLUGIN_CUR_SLOT)
	OR	A
	RET

LPBN_READ_ERR:
	LD	A,(PLUGIN_CUR_SLOT)
	CALL	UNLOAD_PLUGIN_SLOT
LPBN_NOT_FOUND:
LPBN_TOO_LARGE:
LPBN_ALLOC_FAIL:
	; Restore BDOS user area to PLUGIN_ORIG_USER
	LD	A,(PLUGIN_ORIG_USER)
	LD	E,A
	LD	C,32
	CALL	BDOS_ENTRY

	LD	DE,0080H
	LD	C,26
	CALL	BDOS_ENTRY
	SCF
	RET

REGISTER_SLOT_METADATA:
	LD	A,(PLUGIN_CUR_SLOT)
	LD	B,A
	CALL	GET_REGISTRY_ENTRY_PTR
	PUSH	HL

	; Copy Name (16 bytes)
	LD	DE,LINE_STORAGE + 4096 + 12
	EX	DE,HL
	LD	BC,16
	LDIR

	; PROG_SIZE (word)
	LD	HL,(LINE_STORAGE + 4096 + 1)
	LD	A,L
	LD	(DE),A
	INC	DE
	LD	A,H
	LD	(DE),A
	INC	DE

	; LOAD_ADDR (word)
	LD	HL,(LINE_STORAGE + 4096 + 7)
	LD	A,L
	LD	(DE),A
	INC	DE
	LD	A,H
	LD	(DE),A
	INC	DE

	; CAPABILITIES (word)
	LD	HL,(LINE_STORAGE + 4096 + 28)
	LD	A,L
	LD	(DE),A
	INC	DE
	LD	A,H
	LD	(DE),A
	INC	DE

	; SLOT_STATE = 1
	LD	A,1
	LD	(DE),A
	INC	DE

	; EXEC_MODE:
	; If SIZE_CLASS != 0 (16K or 32K) -> Always FAR (1)
	LD	A,(LOAD_SIZE_CLASS)
	OR	A
	JR	NZ,RSM_MODE_FAR

	; 4K plugin: FAR if CAP_FAR_EXEC and (BASE_PAGE == 0 or LOAD_ADDR != 0)
	LD	A,(LINE_STORAGE + 4096 + 28)
	AND	02H			; Bit 1: FAR_EXEC
	JR	Z,RSM_MODE_TPA
	LD	HL,(LINE_STORAGE + 4096 + 7)	; LOAD_ADDR
	LD	A,H
	OR	L
	JR	NZ,RSM_MODE_FAR		; OVL with non-zero base -> FAR
	LD	A,(LOAD_BASE_PAGE)
	OR	A
	JR	Z,RSM_MODE_FAR		; Base page 0 -> FAR
RSM_MODE_TPA:
	XOR	A
	JR	RSM_SAVE_MODE
RSM_MODE_FAR:
	LD	A,1
RSM_SAVE_MODE:
	LD	(DE),A
	INC	DE

	; +24: FAR_BANK
	LD	A,(LOAD_FAR_BANK)
	LD	(DE),A
	INC	DE

	; +25: BASE_PAGE
	LD	A,(LOAD_BASE_PAGE)
	LD	(DE),A
	INC	DE

	; +26: SIZE_CLASS
	LD	A,(LOAD_SIZE_CLASS)
	LD	(DE),A
	INC	DE

	; +27: PAGE_COUNT
	LD	A,(LOAD_PAGE_COUNT)
	LD	(DE),A
	INC	DE

	; +28: File type ('P' = PRL, 'O' = OVL)
	LD	A,(PLUGIN_FCB+9)
	LD	(DE),A

	POP	HL
	LD	HL,PLUGIN_LOAD_COUNT
	INC	(HL)
	LD	A,(PLUGIN_CUR_SLOT)
	OR	A			; Clear Carry
	RET

UNLOAD_PLUGIN_SLOT:
	LD	B,A
	CALL	GET_REGISTRY_ENTRY_PTR
	PUSH	HL
	LD	DE,22
	ADD	HL,DE
	LD	A,(HL)			; SLOT_STATE
	POP	HL
	OR	A
	RET	Z			; Already free

	; If unloading PLUGIN_MGR_SLOT, reset PLUGIN_MGR_SLOT to 0xFF
	LD	A,(PLUGIN_MGR_SLOT)
	CP	B
	JR	NZ,UPS_NOT_MGR
	LD	A,0FFH
	LD	(PLUGIN_MGR_SLOT),A
	LD	(HOST_API_MGR_SLOT),A
UPS_NOT_MGR:

	; Read slot's FAR_BANK at offset +24
	PUSH	HL
	LD	DE,24
	ADD	HL,DE
	LD	C,(HL)			; C = slot's FAR_BANK
	POP	HL

	; Clear 32-byte entry
	PUSH	BC
	LD	(HL),0
	LD	D,H
	LD	E,L
	INC	DE
	LD	BC,PLUGIN_ENTRY_SIZE - 1
	LDIR
	LD	HL,PLUGIN_LOAD_COUNT
	DEC	(HL)
	POP	BC			; C = released slot's FAR_BANK

	; Check if any remaining active slot still uses bank C
	LD	A,C
	OR	A
	RET	Z			; Bank 0: nothing to release
	LD	B,0
UPS_CHECK_BANK_LOOP:
	PUSH	BC
	CALL	GET_REGISTRY_ENTRY_PTR
	LD	DE,22
	ADD	HL,DE
	LD	A,(HL)			; SLOT_STATE
	POP	BC
	OR	A
	JR	Z,UPS_CHECK_NEXT
	INC	HL
	INC	HL			; Points to offset +24 (FAR_BANK)
	LD	A,(HL)
	CP	C
	RET	Z			; Another active slot uses bank C! Do not release.
UPS_CHECK_NEXT:
	INC	B
	LD	A,B
	CP	PLUGIN_MAX_SLOTS
	JR	NZ,UPS_CHECK_BANK_LOOP

	; No active slot uses bank C: release bank C back to EXT_BANK_TABLE
	LD	A,C
	CALL	RELEASE_FAR_BANK
	RET

EXEC_PLUGIN_SLOT:
	LD	C,0			; Action 0: Main Execution
	; Fall through to EXEC_PLUGIN_SLOT_ACTION

EXEC_PLUGIN_SLOT_ACTION:
	LD	(PLUGIN_CUR_SLOT),A
	LD	A,C
	LD	(PLUGIN_ACTION_INDEX),A
	XOR	A
	LD	(PLUGIN_RET_CODE),A
	; Synchronize screen dimensions and context in Host API (+14, +15, +16, +17)
	LD	A,(ACTIVE_COLS)
	LD	(HOST_API_COLS),A
	LD	A,(POPUP_CONTEXT_ID)
	LD	(HOST_API_CONTEXT),A
	LD	A,(ACTIVE_ROWS)
	LD	(HOST_API_ROWS),A
	LD	A,(PLUGIN_MGR_SLOT)
	LD	(HOST_API_MGR_SLOT),A
	LD	A,(PLUGIN_CUR_SLOT)
	LD	B,A
	CALL	GET_REGISTRY_ENTRY_PTR
	LD	DE,22
	ADD	HL,DE
	LD	A,(HL)
	OR	A
	RET	Z			; Empty slot

	INC	HL			; Offset +23: EXEC_MODE
	LD	A,(HL)
	OR	A
	JR	NZ,EPS_DO_FAR
	LD	A,(PLUGIN_CUR_SLOT)
	JP	EXEC_PLUGIN_TPA
EPS_DO_FAR:
	LD	A,(PLUGIN_CUR_SLOT)
	JP	EXEC_PLUGIN_FAR

EXEC_PLUGIN_TPA:
	XOR	A
	LD	(PLUGIN_IS_FAR_EXEC),A

	; Read slot's Far RAM bank and base address
	LD	A,(PLUGIN_CUR_SLOT)
	LD	B,A
	CALL	GET_REGISTRY_ENTRY_PTR
	PUSH	HL
	LD	DE,24
	ADD	HL,DE
	LD	A,(HL)			; A = FAR_BANK
	LD	(EP_TPA_FAR_BANK),A
	INC	HL
	LD	A,(HL)			; A = BASE_PAGE
	LD	H,A
	LD	L,0
	LD	(FAR_SLOT_BASE_ADDR),HL
	POP	HL

	CALL	FLUSH_DIRTY_CACHE
	LD	HL,0FFFFH
	LD	(CACHE_START_ROW),HL

	CALL	GET_CUR_ROW_LEN
	LD	(ACTIVE_LINE_LEN),DE

	; Copy up to LINE_STORAGE_SIZE bytes from Far RAM to LINE_STORAGE (code + PRL bitmap)
	PUSH	IX
	LD	B,0F4H
	LD	A,(CPM_USER_BANK)
	LD	D,A
	LD	A,(EP_TPA_FAR_BANK)
	LD	E,A
	LD	HL,LINE_STORAGE_SIZE
	RST	08H
	POP	IX

	PUSH	IX
	LD	B,0F5H
	LD	HL,(FAR_SLOT_BASE_ADDR)
	LD	DE,LINE_STORAGE
	RST	08H
	POP	IX

	; Check if relocation needed (LOAD_ADDR == 0)
	LD	HL,(LINE_STORAGE + 7)
	LD	A,H
	OR	L
	JR	NZ,EPT_CALL_ENTRY

	; Target page = high_byte(LINE_STORAGE + 256)
	LD	HL,LINE_STORAGE + 256
	LD	A,H
	DEC	A			; Bias = Target Page - 1
	LD	(RELOC_BIAS),A

	LD	HL,LINE_STORAGE + 256
	LD	DE,(LINE_STORAGE + 1)	; PROG_SIZE
	PUSH	HL
	ADD	HL,DE
	EX	DE,HL			; DE = bitmap ptr
	POP	HL			; HL = code ptr
	LD	BC,(LINE_STORAGE + 1)
	CALL	RELOCATE_PRL_LOOP

EPT_CALL_ENTRY:
	LD	IX,PLUGIN_HOST_API
	LD	IY,PLUGIN_HOST_API
	LD	HL,LINE_STORAGE + 256
	LD	A,(PLUGIN_ACTION_INDEX)
	OR	A
	JR	Z,EPT_NO_OFFSET
	LD	C,A
	ADD	A,A
	ADD	A,C
	LD	C,A
	LD	B,0
	ADD	HL,BC
EPT_NO_OFFSET:
	CALL	CALL_HL_ENTRY

	PUSH	AF
	CALL	RELOAD_CACHE_WINDOW_FORCE
	POP	AF

	LD	(PLUGIN_RET_CODE),A
	CP	1
	JR	Z,EPT_LINE_DIRTY
	CP	2
	JR	Z,EPT_DOC_DIRTY
	OR	A
	RET

EPT_LINE_DIRTY:
	LD	A,1
	LD	(DOC_MODIFIED),A
	LD	(ACTIVE_LINE_DIRTY),A
	CALL	COMMIT_ACTIVE_LINE
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	OR	A
	RET

EPT_DOC_DIRTY:
	LD	A,1
	LD	(DOC_MODIFIED),A
	LD	(IN_EDITOR_MODE),A
	XOR	A
	LD	(IS_SPLASH_SCREEN),A
	LD	HL,0FFFFH
	LD	(ACTIVE_LINE_ROW),HL
	LD	(ACTIVE_LINE_DIRTY),A
	CALL	CHECKOUT_ACTIVE_LINE
	CALL	RELOAD_CACHE_WINDOW_FORCE
	CALL	CONSTRAIN_CURSOR_VIEWPORT
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	OR	A
	RET

CALL_HL_ENTRY:
	JP	(HL)

EXEC_PLUGIN_FAR:
	LD	A,1
	LD	(PLUGIN_IS_FAR_EXEC),A
	CALL	GET_CUR_ROW_LEN
	LD	(ACTIVE_LINE_LEN),DE

	LD	A,(PLUGIN_CUR_SLOT)
	LD	B,A
	CALL	GET_REGISTRY_ENTRY_PTR
	LD	DE,24
	ADD	HL,DE
	LD	A,(HL)			; A = FAR_BANK
	LD	(PLUGIN_FAR_BANK),A	; Set current bank for host trampolines
	INC	HL
	LD	A,(HL)			; A = BASE_PAGE
	INC	A			; +1 page for header
	LD	H,A
	LD	L,0

	LD	A,(PLUGIN_ACTION_INDEX)
	OR	A
	JR	Z,EPF_NO_OFFSET
	LD	C,A
	ADD	A,A
	ADD	A,C
	LD	C,A
	LD	B,0
	ADD	HL,BC
EPF_NO_OFFSET:
	PUSH	HL
	POP	IX			; IX = entry point
	LD	IY,PLUGIN_HOST_API
	LD	A,(PLUGIN_FAR_BANK)
	DI
	CALL	0FFF9H			; HB_BNKCALL at 0xFFF9
	EI

	PUSH	AF
	XOR	A
	LD	(PLUGIN_IS_FAR_EXEC),A
	POP	AF

	LD	(PLUGIN_RET_CODE),A
	CP	1
	JP	Z,EPT_LINE_DIRTY
	CP	2
	JP	Z,EPT_DOC_DIRTY
	OR	A
	RET

RELOCATE_PRL_LOOP:
	LD	A,B
	OR	C
	RET	Z
	LD	A,(DE)
	INC	DE
	LD	(RELOC_CUR_BYTE),A
	LD	A,8
RPL_BIT:
	PUSH	AF
	LD	A,(RELOC_CUR_BYTE)
	RLA
	LD	(RELOC_CUR_BYTE),A
	JR	NC,RPL_SKIP
	LD	A,(RELOC_BIAS)
	ADD	A,(HL)
	LD	(HL),A
RPL_SKIP:
	INC	HL
	DEC	BC
	LD	A,B
	OR	C
	JR	Z,RPL_DONE
	POP	AF
	DEC	A
	JR	NZ,RPL_BIT
	JR	RELOCATE_PRL_LOOP
RPL_DONE:
	POP	AF
	RET

PARSE_STRING_TO_PLUGIN_FCB:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	HL,WORK_FCB
	LD	DE,PLUGIN_FCB
	LD	BC,36
	LDIR
	POP	HL
	PUSH	HL
	CALL	PARSE_STRING_TO_FCB
	LD	A,(WORK_FCB_USER)
	LD	(PLUGIN_USER_AREA),A
	LD	A,(DOC_USER_NUM)
	LD	(WORK_FCB_USER),A
	LD	HL,PLUGIN_FCB
	LD	DE,WORK_FCB
	LD	B,36
PSTPF_SWAP:
	LD	A,(DE)
	LD	C,(HL)
	LD	(DE),C
	LD	(HL),A
	INC	DE
	INC	HL
	DJNZ	PSTPF_SWAP
	POP	HL
	POP	DE
	POP	BC
	RET

DO_PLUGIN_SCREEN:
	XOR	A
	LD	(PLUGIN_RET_CODE),A
	CALL	ENSURE_PLUGIN_MGR_LOADED
	JR	C,DPS_MISSING
DPS_LOOP:
	LD	C,0			; Action 0: Plugin Manager
	CALL	EXEC_PLUGIN_MGR_ACTION
	JR	C,DPS_DISMISS		; Carry = 1: user pressed Q or ESC

	; Carry = 0: user ran a slot or selected about/config
	; A = slot number (0..7), C = action index (0..2)
	LD	B,A
	LD	A,C
	OR	A
	JR	Z,DPS_NO_CLEAR
	PUSH	BC
	LD	DE,STR_CLEAR_SCREEN
	CALL	PRINT_STR
	POP	BC
DPS_NO_CLEAR:
	LD	A,B
	CALL	EXEC_PLUGIN_SLOT_ACTION
	LD	A,(PLUGIN_RET_CODE)
	CP	2
	JP	Z,ENTER_EDITOR_WITH_ACTIVE_LINE
	CP	1
	JR	NZ,DPS_LOOP
	LD	A,(IN_EDITOR_MODE)
	OR	A
	JR	NZ,DPS_DISMISS
	JR	DPS_LOOP

DPS_DISMISS:
	RET

DPS_MISSING:
	LD	DE,STR_MSG_NEED_PLUGIN_MGR
	CALL	HOST_SET_STATUS_MSG
	RET

SAVE_EDITOR_PLUGIN_STATE:
	LD	HL,(CUR_DOC_ROW)
	LD	(PLUGIN_SAVED_DOC_ROW),HL
	LD	HL,(CUR_COL)
	LD	(PLUGIN_SAVED_COL),HL
	LD	HL,(TARGET_COL)
	LD	(PLUGIN_SAVED_TARGET_COL),HL
	LD	HL,(TOP_DOC_ROW)
	LD	(PLUGIN_SAVED_TOP_ROW),HL
	LD	HL,(VIEW_LEFT_COL)
	LD	(PLUGIN_SAVED_VIEW_LEFT),HL
	RET

RESTORE_EDITOR_PLUGIN_STATE:
	LD	HL,(PLUGIN_SAVED_DOC_ROW)
	LD	(CUR_DOC_ROW),HL
	LD	HL,(PLUGIN_SAVED_COL)
	LD	(CUR_COL),HL
	LD	HL,(PLUGIN_SAVED_TARGET_COL)
	LD	(TARGET_COL),HL
	LD	HL,(PLUGIN_SAVED_TOP_ROW)
	LD	(TOP_DOC_ROW),HL
	LD	HL,(PLUGIN_SAVED_VIEW_LEFT)
	LD	(VIEW_LEFT_COL),HL
	CALL	CONSTRAIN_CURSOR_VIEWPORT
	CALL	CHECKOUT_ACTIVE_LINE
	CALL	GET_CUR_ROW_LEN
	LD	(ACTIVE_LINE_LEN),DE
	CALL	RELOAD_CACHE_WINDOW_FORCE
	RET

DO_EDITOR_PLUGIN_SCREEN:
	CALL	CHECKOUT_ACTIVE_LINE
	CALL	GET_CUR_ROW_LEN
	LD	(ACTIVE_LINE_LEN),DE
	CALL	SAVE_EDITOR_PLUGIN_STATE
	CALL	FLUSH_DIRTY_CACHE
	LD	HL,0FFFFH
	LD	(CACHE_START_ROW),HL
	CALL	DO_PLUGIN_SCREEN
	LD	A,(PLUGIN_RET_CODE)
	OR	A
	JR	NZ,DEPS_DOC_MODIFIED
	CALL	RESTORE_EDITOR_PLUGIN_STATE
	JR	DEPS_RENDER
DEPS_DOC_MODIFIED:
	CALL	CHECKOUT_ACTIVE_LINE
	CALL	GET_CUR_ROW_LEN
	LD	(ACTIVE_LINE_LEN),DE
	CALL	CONSTRAIN_CURSOR_VIEWPORT
	CALL	RELOAD_CACHE_WINDOW_FORCE
DEPS_RENDER:
	CALL	TERM_INIT
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	CALL	LOCATE_CURSOR
	JP	MAIN_LOOP



;==============================================================================
; Context-Aware Plugin Pop-up Modal Subsystem
;==============================================================================

DO_CONTEXT_PLUGIN_POPUP:
	LD	(POPUP_CONTEXT_ID),A
	LD	(HOST_API_CONTEXT),A

	; If in editor mode, flush dirty cache lines to Far RAM and save state
	LD	A,(IN_EDITOR_MODE)
	OR	A
	JR	Z,DCPP_PROBE
	CALL	SAVE_EDITOR_PLUGIN_STATE
	CALL	FLUSH_DIRTY_CACHE

DCPP_PROBE:
	CALL	ENSURE_PLUGIN_MGR_LOADED
	JR	C,DCPP_MISSING

DCPP_LOOP:
	LD	C,1			; Action 1: Context Pop-up
	CALL	EXEC_PLUGIN_MGR_ACTION
	JR	C,DCPP_DISMISS		; Carry = 1: dismissed (ESC, Ctrl+P, Q)

	; Carry = 0: user selected slot A with action C
	; If C != 0 (About or Config) or plugin has CAP_MODAL_UI,
	; mark action as modal and pre-clear base screen.
	LD	B,A			; Save slot number in B
	LD	A,C
	OR	A
	JR	NZ,DCPP_MARK_MODAL
	PUSH	BC
	CALL	GET_REGISTRY_ENTRY_PTR
	LD	DE,20			; Offset +20: CAPABILITIES (word)
	ADD	HL,DE
	LD	A,(HL)
	AND	CAP_MODAL_UI		; 08h
	POP	BC
	JR	Z,DCPP_NOT_MODAL

DCPP_MARK_MODAL:
	LD	A,1
	JR	DCPP_SET_MODAL

DCPP_NOT_MODAL:
	XOR	A

DCPP_SET_MODAL:
	LD	(POPUP_ACTION_MODAL),A
	OR	A
	JR	Z,DCPP_EXEC
	PUSH	BC
	CALL	REDRAW_BASE_SCREEN
	POP	BC

DCPP_EXEC:
	LD	A,B			; A = slot number
	CALL	EXEC_PLUGIN_SLOT_ACTION
	LD	A,(POPUP_ACTION_MODAL)
	OR	A
	JR	Z,DCPP_DISMISS		; Non-modal Action 0: dismiss back to caller
	; Modal Action: Redraw base screen & return to Ctrl+P menu
	CALL	REDRAW_BASE_SCREEN
	JR	DCPP_LOOP

DCPP_DISMISS:
	LD	A,(PLUGIN_RET_CODE)
	CP	2
	JP	Z,ENTER_EDITOR_WITH_ACTIVE_LINE
	CALL	REDRAW_BASE_SCREEN
	RET

DCPP_MISSING:
	LD	DE,STR_MSG_NEED_PLUGIN_MGR
	CALL	HOST_SET_STATUS_MSG
	LD	A,(IN_EDITOR_MODE)
	OR	A
	JR	NZ,DCPM_ED
	CALL	REDRAW_BASE_SCREEN
	RET
DCPM_ED:
	CALL	RENDER_STATUS_BAR
	RET


POPUP_LOCATE_NEXT:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	A,(POPUP_ROW)
	LD	H,A
	LD	A,(POPUP_COL)
	LD	L,A
	CALL	LOCATE_RC
	LD	HL,POPUP_ROW
	INC	(HL)
	POP	HL
	POP	DE
	POP	BC
	RET



REDRAW_BASE_SCREEN:
	LD	A,(POPUP_CONTEXT_ID)
	CP	PLUG_CTX_EDITOR
	JR	NZ,PDR_NOT_EDITOR
	LD	A,(PLUGIN_RET_CODE)
	OR	A
	JR	NZ,RBS_DOC_MODIFIED
	CALL	RESTORE_EDITOR_PLUGIN_STATE
	JR	RBS_RENDER
RBS_DOC_MODIFIED:
	CALL	CHECKOUT_ACTIVE_LINE
	CALL	GET_CUR_ROW_LEN
	LD	(ACTIVE_LINE_LEN),DE
	CALL	CONSTRAIN_CURSOR_VIEWPORT
	CALL	RELOAD_CACHE_WINDOW_FORCE
RBS_RENDER:
	XOR	A
	LD	(NEED_SCREEN_RENDER),A
	LD	(NEED_LINE_RENDER),A
	LD	(NEED_STATUS_RENDER),A
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	CALL	LOCATE_CURSOR
	RET
PDR_NOT_EDITOR:
	CP	PLUG_CTX_SPLASH
	JR	NZ,PDR_NOT_SPLASH
	CALL	RENDER_SPLASH
	RET
PDR_NOT_SPLASH:
	CP	PLUG_CTX_CONFIG
	JR	NZ,PDR_NOT_CONFIG
	CALL	SHOW_CONFIG_SCREEN
	RET
PDR_NOT_CONFIG:
	CP	PLUG_CTX_MEM_INFO
	JR	NZ,PDR_NOT_MEM_INFO
	CALL	SHOW_MEM_INFO_SCREEN
	RET
PDR_NOT_MEM_INFO:
	CP	PLUG_CTX_HELP
	JR	NZ,PDR_NOT_HELP
	CALL	RENDER_HELP_SCREEN_STATIC
	RET
PDR_NOT_HELP:
	CP	PLUG_CTX_ABOUT
	JR	NZ,PDR_NOT_ABOUT
	CALL	SHOW_ABOUT_SCREEN
	RET
PDR_NOT_ABOUT:
	; Context is PLUG_CTX_PLUGIN_MGR
	LD	A,(PLUGIN_MGR_LOADED)
	OR	A
	RET	Z
	LD	C,0
	CALL	EXEC_PLUGIN_MGR_ACTION
	RET

;==============================================================================
; FAT Filesystem & Headless VFS Subsystem (Phase 2)
;==============================================================================

;------------------------------------------------------------------------------
; VFS_FIND_PLUGIN:
; Scans PLUGIN_REGISTRY (slots 0..7) for a loaded plugin with CAP_HAS_VFS.
; Returns:
;   Carry = 0: Plugin found.
;              A = Slot index (0..7)
;              HL = Pointer to 32-byte registry entry
;   Carry = 1: Plugin not loaded.
;------------------------------------------------------------------------------
VFS_FIND_PLUGIN:
	PUSH	BC
	PUSH	DE
	LD	B,0
VFP_LOOP:
	PUSH	BC
	CALL	GET_REGISTRY_ENTRY_PTR
	POP	BC
	; Check SLOT_STATE at HL+22
	PUSH	HL
	LD	DE,22
	ADD	HL,DE
	LD	A,(HL)
	POP	HL
	OR	A
	JR	Z,VFP_NEXT_SLOT

	; Check CAPABILITIES word at HL+20 (CAP_HAS_VFS = 0x0100)
	; Byte +20 is low byte, byte +21 is high byte.
	; Bit 8 (0x0100) is bit 0 of high byte (+21).
	PUSH	HL
	LD	DE,21
	ADD	HL,DE
	LD	A,(HL)
	POP	HL
	AND	01H			; Test bit 8 of CAPABILITIES
	JR	NZ,VFP_FOUND

VFP_NEXT_SLOT:
	INC	B
	LD	A,B
	CP	PLUGIN_MAX_SLOTS
	JR	NZ,VFP_LOOP

	; Not found
	POP	DE
	POP	BC
	SCF
	RET

VFP_FOUND:
	LD	A,B			; A = Slot index
	POP	DE
	POP	BC
	OR	A			; Carry = 0
	RET

;------------------------------------------------------------------------------
; VFS_EXEC_REQUEST:
; Dispatches a VFS request to FATFS.PRL via Action 3 (ENTRY + 9).
; Input:
;   DE = Pointer to 16-byte FatVfsRequest packet in Upper Common RAM
; Output:
;   A = Status code (0 = VFS_STAT_OK)
;   Carry = 0: Success
;   Carry = 1: Error (plugin not loaded, or VFS operation failed)
;------------------------------------------------------------------------------
VFS_EXEC_REQUEST:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	PUSH	IX
	PUSH	IY

	; Check if VFS plugin is loaded
	CALL	VFS_FIND_PLUGIN
	JR	C,VER_NOT_LOADED

	; HL = registry entry pointer
	; Read FAR_BANK at HL+24
	LD	BC,24
	ADD	HL,BC
	LD	A,(HL)			; A = FAR_BANK
	LD	(PLUGIN_FAR_BANK),A	; Set current bank for host callbacks
	INC	HL			; HL points to BASE_PAGE (+25)
	LD	A,(HL)			; A = BASE_PAGE
	INC	A			; +1 page for header
	LD	H,A
	LD	L,9			; Entry point = (BASE_PAGE+1)*256 + 9
	PUSH	HL
	POP	IX			; IX = Action 3 entry vector

	LD	IY,PLUGIN_HOST_API	; IY = Host API table pointer
	LD	DE,VFS_REQ_PKT		; DE = Request packet pointer
	LD	A,1
	LD	(PLUGIN_IS_FAR_EXEC),A
	LD	A,(PLUGIN_FAR_BANK)	; A = Target Bank for HB_BNKCALL

	; Interrupts disabled during inter-bank call
	DI
	CALL	0FFF9H			; HB_BNKCALL at 0xFFF9
	EI

	PUSH	AF
	XOR	A
	LD	(PLUGIN_IS_FAR_EXEC),A
	POP	AF

	; A now contains VFS return code, CY set on error
	POP	IY
	POP	IX
	POP	HL
	POP	DE
	POP	BC
	RET

VER_NOT_LOADED:
	POP	IY
	POP	IX
	POP	HL
	POP	DE
	POP	BC
	LD	A,0FFH			; VFS_STAT_UNSUPPORTED
	SCF
	RET

;------------------------------------------------------------------------------
; PARSE_FAT_PATH:
; Checks if string at HL starts with "U:" or "U<unit>:" (case-insensitive).
; Output:
;   Carry = 1: FAT path prefix matched.
;              A = Unit index (0..7, or 0xFF if default unit requested)
;              HL = Pointer to path string immediately after ':'
;   Carry = 0: Not a FAT path prefix.
;              HL preserved.
;------------------------------------------------------------------------------
PARSE_FAT_PATH:
	PUSH	HL
	; Skip leading spaces
PFP_SKIP_SPACES:
	LD	A,(HL)
	CP	' '
	JR	NZ,PFP_CHECK_U
	INC	HL
	JR	PFP_SKIP_SPACES

PFP_CHECK_U:
	CALL	TO_UPPER
	CP	'U'
	JR	NZ,PFP_NOT_FAT

	INC	HL
	LD	A,(HL)
	CP	':'
	JR	Z,PFP_DEFAULT_UNIT

	; Check if next char is digit '0'..'7'
	CP	'0'
	JR	C,PFP_NOT_FAT
	CP	'7'+1
	JR	NC,PFP_NOT_FAT

	; Got digit! Save unit digit
	SUB	'0'
	LD	C,A			; C = unit 0..7
	INC	HL
	LD	A,(HL)
	CP	':'
	JR	NZ,PFP_NOT_FAT

	; Form: U<unit>:
	INC	HL			; Advance past ':'
	POP	AF			; Discard saved initial HL
	LD	A,C			; A = unit 0..7
	SCF
	RET

PFP_DEFAULT_UNIT:
	; Form: U:
	INC	HL			; Advance past ':'
	POP	AF			; Discard saved initial HL
	LD	A,0FFH			; 0xFF = default unit
	SCF
	RET

PFP_NOT_FAT:
	POP	HL
	XOR	A			; Carry = 0, Z = 1
	RET

;------------------------------------------------------------------------------
; EXTRACT_BASE_FILENAME:
; Extracts the base 8.3 filename from a DOS path at HL into FAT_DOC_FNAME.
; Finds the last '/' separator, then copies up to 12 chars + null terminator.
; Input:
;   HL = Pointer to null-terminated DOS path
; Output:
;   FAT_DOC_FNAME populated
;------------------------------------------------------------------------------
EXTRACT_BASE_FILENAME:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	LD	DE,FAT_DOC_FNAME
	; BC tracks candidate pointer to base filename start
	LD	B,H
	LD	C,L

EBF_SCAN_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,EBF_FOUND_END
	CP	'/'
	JR	NZ,EBF_NOT_SLASH
	; Found a slash. Next char is candidate for base filename start
	INC	HL
	LD	B,H
	LD	C,L
	JR	EBF_SCAN_LOOP

EBF_NOT_SLASH:
	INC	HL
	JR	EBF_SCAN_LOOP

EBF_FOUND_END:
	; HL = pointer to candidate base filename
	LD	H,B
	LD	L,C

	; Copy up to 12 chars to FAT_DOC_FNAME, terminating with 0
	LD	B,12
EBF_COPY_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,EBF_COPY_DONE
	CP	' '
	JR	Z,EBF_COPY_DONE
	CALL	TO_UPPER
	LD	(DE),A
	INC	HL
	INC	DE
	DJNZ	EBF_COPY_LOOP

EBF_COPY_DONE:
	XOR	A
	LD	(DE),A			; Null terminate

	POP	HL
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; ENSURE_VFS_PLUGIN_LOADED:
; Checks if FATFS.PRL is resident in Far RAM. If not, attempts to load it.
; Returns:
;   Carry = 0: Plugin loaded and ready
;   Carry = 1: Plugin could not be loaded
;------------------------------------------------------------------------------
ENSURE_VFS_PLUGIN_LOADED:
	CALL	VFS_FIND_PLUGIN
	RET	NC			; Already resident
	LD	DE,STR_FATFS_PRL
	CALL	LOAD_PLUGIN_BY_NAME
	RET

;------------------------------------------------------------------------------
; CHECK_FAT_INPUT_OPEN:
; Inspects INPUT_FILENAME_BUF in Open dialog.
; Returns:
;   Carry = 1: FAT path detected, but FATFS.PRL is NOT loaded.
;              DE = STR_FAT_NO_PLUGIN_INLINE, C = 28.
;   Carry = 0, NZ: FAT path detected, and FATFS.PRL IS loaded!
;   Carry = 0, Z:  Not a FAT path.
;------------------------------------------------------------------------------
CHECK_FAT_INPUT_OPEN:
	LD	A,(IS_PLUGIN_LOAD_UI)
	OR	A
	JR	NZ,CFIO_NOT_FAT

	LD	HL,INPUT_FILENAME_BUF
	CALL	PARSE_FAT_PATH
	JR	NC,CFIO_NOT_FAT

	; FAT path detected! Check if plugin is loaded
	CALL	VFS_FIND_PLUGIN
	JR	C,CFIO_NO_PLUGIN

	; Plugin is loaded! Return Carry=0, NZ
	XOR	A
	INC	A			; A = 1 -> NZ, Carry = 0
	RET

CFIO_NOT_FAT:
	XOR	A			; Carry = 0, Z = 1
	RET

CFIO_NO_PLUGIN:
	LD	DE,STR_FAT_NO_PLUGIN_INLINE
	LD	C,28			; Message length
	SCF				; Carry = 1
	RET

;------------------------------------------------------------------------------
; CHECK_FAT_INPUT_SAVE:
; Inspects INPUT_FILENAME_BUF in Save dialog.
; Returns:
;   Carry = 1: FAT path detected, but FATFS.PRL is NOT loaded.
;              DE = STR_FAT_NO_PLUGIN_INLINE, A = 28.
;   Carry = 0, NZ: FAT path detected, and FATFS.PRL IS loaded!
;   Carry = 0, Z:  Not a FAT path.
;------------------------------------------------------------------------------
CHECK_FAT_INPUT_SAVE:
	LD	HL,INPUT_FILENAME_BUF
	CALL	PARSE_FAT_PATH
	JR	NC,CFIS_NOT_FAT

	; FAT path detected! Check if plugin is loaded
	CALL	VFS_FIND_PLUGIN
	JR	C,CFIS_NO_PLUGIN

	; Plugin is loaded! Return Carry=0, NZ
	XOR	A
	INC	A			; A = 1 -> NZ, Carry = 0
	RET

CFIS_NOT_FAT:
	XOR	A			; Carry = 0, Z = 1
	RET

CFIS_NO_PLUGIN:
	LD	DE,STR_FAT_NO_PLUGIN_INLINE
	LD	A,28			; Message length
	SCF				; Carry = 1
	RET

;------------------------------------------------------------------------------
; HANDLE_OPEN_FAT_DISPATCH:
; Dispatches confirmed explicit FAT input (e.g. "U4:" or "U4:FILE") in Open.
;------------------------------------------------------------------------------
HANDLE_OPEN_FAT_DISPATCH:
	LD	HL,INPUT_FILENAME_BUF
	CALL	PARSE_FAT_PATH		; A = unit, HL = path after ':'
	LD	(VFS_REQ_UNIT),A
	LD	(FAT_DOC_UNIT),A

	; Check if remainder after ':' is empty or just spaces
HOFD_CHECK_EMPTY:
	LD	A,(HL)
	OR	A
	JR	Z,HANDLE_OPEN_FAT_DRIVE_SWITCH
	CP	' '
	JR	NZ,HOFD_NOT_EMPTY
	INC	HL
	JR	HOFD_CHECK_EMPTY

HOFD_NOT_EMPTY:
	; Remainder is non-empty. Check if it's "/" alone
	CP	'/'
	JR	NZ,HOFD_CHECK_DESCENT
	INC	HL
	LD	A,(HL)
	OR	A
	JR	Z,HANDLE_OPEN_FAT_DRIVE_SWITCH
	CP	' '
	JR	Z,HANDLE_OPEN_FAT_DRIVE_SWITCH
	DEC	HL			; Point back to '/'

HOFD_CHECK_DESCENT:
	; Check if input path ends with '/'
	CALL	CHECK_HL_ENDS_WITH_SLASH
	JR	C,HANDLE_OPEN_FAT_SUBDIR_SWITCH

	; Check if this is Block Insert UI
	LD	A,(IS_BLOCK_INSERT_UI)
	OR	A
	JP	NZ,HANDLE_BLOCK_INSERT_FAT_FILE
	JP	HANDLE_OPEN_FAT_FILE

;------------------------------------------------------------------------------
; HANDLE_OPEN_FAT_SUBDIR_SWITCH:
; Switches active directory view to target FAT unit and subdirectory.
;------------------------------------------------------------------------------
HANDLE_OPEN_FAT_SUBDIR_SWITCH:
	LD	A,1
	LD	(CURRENT_DIR_IS_FAT),A
	LD	A,(VFS_REQ_UNIT)
	LD	(CURRENT_DIR_FAT_UNIT),A
	CALL	SET_DIR_FROM_PATH_HL
	LD	A,'U'
	LD	(STR_DIR_DRIVE_CHAR),A
	LD	(STR_SAVE_DRIVE_CHAR),A
	CALL	RESET_DIR_FILTER
	XOR	A
	LD	(SHOWING_FNF_MSG),A
	JP	REFRESH_OPEN_DIR

;------------------------------------------------------------------------------
; HANDLE_OPEN_FAT_DRIVE_SWITCH:
; Switches active directory view to target FAT unit root and reloads directory.
;------------------------------------------------------------------------------
HANDLE_OPEN_FAT_DRIVE_SWITCH:
	LD	A,1
	LD	(CURRENT_DIR_IS_FAT),A
	LD	A,(VFS_REQ_UNIT)
	LD	(CURRENT_DIR_FAT_UNIT),A
	CALL	FAT_PATH_SET_ROOT
	LD	A,'U'
	LD	(STR_DIR_DRIVE_CHAR),A
	LD	(STR_SAVE_DRIVE_CHAR),A
	CALL	RESET_DIR_FILTER
	XOR	A
	LD	(SHOWING_FNF_MSG),A
	JP	REFRESH_OPEN_DIR

;------------------------------------------------------------------------------
; HANDLE_OPEN_FAT_RELATIVE:
; Handles input when CURRENT_DIR_IS_FAT == 1 without explicit drive prefix.
; Checks for navigation (.., /, DIRNAME/, DIRNAME) or opens relative file.
;------------------------------------------------------------------------------
HANDLE_OPEN_FAT_RELATIVE:
	CALL	CHECK_AND_HANDLE_FAT_NAV
	JR	NC,HOFR_NOT_NAV
	CALL	RESET_DIR_FILTER
	XOR	A
	LD	(SHOWING_FNF_MSG),A
	JP	REFRESH_OPEN_DIR

HOFR_NOT_NAV:
	CALL	BUILD_RELATIVE_FAT_PATH
	LD	A,(CURRENT_DIR_FAT_UNIT)
	LD	(VFS_REQ_UNIT),A
	LD	(FAT_DOC_UNIT),A

	; Check if Block Insert UI
	LD	A,(IS_BLOCK_INSERT_UI)
	OR	A
	JP	Z,HOFF_DO_LOAD

	; Block insert relative FAT file
	LD	HL,FAT_DOC_PATH
	LD	DE,FAT_INSERT_PATH
	LD	BC,64
	LDIR
	JP	HBIF_DO_STREAM_OPEN

;------------------------------------------------------------------------------
; HANDLE_BLOCK_INSERT_FAT_FILE:
; Invoked when user confirms an explicit FAT file during Block Insert.
;------------------------------------------------------------------------------
HANDLE_BLOCK_INSERT_FAT_FILE:
	LD	HL,INPUT_FILENAME_BUF
	CALL	PARSE_FAT_PATH		; A = unit, HL = path after ':'
	LD	(VFS_REQ_UNIT),A

	; Copy path after ':' into FAT_INSERT_PATH (prepending '/' if needed)
	LD	DE,FAT_INSERT_PATH
	LD	A,(HL)
	CP	'/'
	JR	Z,HBIF_COPY_PATH
	LD	A,'/'
	LD	(DE),A
	INC	DE
HBIF_COPY_PATH:
	LD	A,(HL)
	OR	A
	JR	Z,HBIF_PATH_DONE
	CP	' '
	JR	Z,HBIF_PATH_DONE
	LD	(DE),A
	INC	HL
	INC	DE
	JR	HBIF_COPY_PATH
HBIF_PATH_DONE:
	XOR	A
	LD	(DE),A

HBIF_DO_STREAM_OPEN:
	; Open file stream via VFS_CMD_OPEN_FILE (5)
	LD	A,5			; VFS_CMD_OPEN_FILE
	LD	(VFS_REQ_CMD),A
	XOR	A
	LD	(VFS_REQ_FLAGS),A
	LD	(VFS_REQ_STATUS),A
	LD	HL,FAT_INSERT_PATH
	LD	(VFS_REQ_PATH),HL
	CALL	VFS_EXEC_REQUEST
	JR	C,HBIF_FAIL
	LD	A,(VFS_REQ_STATUS)
	OR	A
	JR	NZ,HBIF_FAIL

	; File opened! Set BLOCK_INSERT_IS_FAT = 1
	LD	A,1
	LD	(BLOCK_INSERT_IS_FAT),A

	; Setup loading UI for block insert
	LD	A,(HAS_FILE_ARG)
	LD	(SAVED_HAS_FILE_ARG),A
	LD	A,1
	LD	(HAS_FILE_ARG),A
	LD	(IS_LOADING_FILE),A
	XOR	A
	LD	(IS_SPLASH_SCREEN),A
	LD	(INSERT_LINE_HAD_CHARS),A
	LD	HL,0
	LD	(LOAD_PROGRESS_LINES),HL
	LD	A,100
	LD	(LOAD_PROGRESS_COUNT),A

	CALL	DRAW_LOADING_SCREEN

	; Perform Block Insert
	CALL	DO_PERFORM_BLOCK_INSERT

	; Finish block insert and return to editor
	JP	DPAI_CLEANUP

HBIF_FAIL:
	JP	OPEN_FILE_NOT_FOUND

;------------------------------------------------------------------------------
; HANDLE_OPEN_FAT_FILE:
; Invoked when user confirms an explicit FAT file in Open dialog.
;------------------------------------------------------------------------------
HANDLE_OPEN_FAT_FILE:
	LD	HL,INPUT_FILENAME_BUF
	CALL	PARSE_FAT_PATH		; A = unit, HL = path after ':'
	LD	(VFS_REQ_UNIT),A
	LD	(FAT_DOC_UNIT),A

	; Copy path after ':' into FAT_DOC_PATH (prepending '/' if needed)
	LD	DE,FAT_DOC_PATH
	LD	A,(HL)
	CP	'/'
	JR	Z,HOFF_COPY_PATH
	LD	A,'/'
	LD	(DE),A
	INC	DE
HOFF_COPY_PATH:
	LD	A,(HL)
	OR	A
	JR	Z,HOFF_PATH_DONE
	CP	' '
	JR	Z,HOFF_PATH_DONE
	LD	(DE),A
	INC	HL
	INC	DE
	JR	HOFF_COPY_PATH
HOFF_PATH_DONE:
	XOR	A
	LD	(DE),A

HOFF_DO_LOAD:
	; Extract base filename into FAT_DOC_FNAME
	LD	HL,FAT_DOC_PATH
	CALL	EXTRACT_BASE_FILENAME

	; Update CURRENT_DIR_FAT_PATH from FAT_DOC_PATH
	CALL	SET_DIR_FROM_DOC_PATH

	; Attempt to load the file via VFS
	LD	HL,FAT_DOC_PATH
	CALL	VFS_LOAD_FAT_FILE
	JR	C,HOFF_LOAD_FAIL

	; Success! Set flags and enter editor
	LD	SP,LOCAL_STACK
	LD	A,1
	LD	(DOC_IS_FAT),A
	LD	(HAS_FILE_ARG),A
	LD	(IN_EDITOR_MODE),A
	XOR	A
	LD	(DOC_MODIFIED),A

	; Default view to line 0
	LD	HL,0
	LD	(CUR_DOC_ROW),HL
	LD	(TOP_DOC_ROW),HL
	LD	(CUR_COL),HL
	LD	(TARGET_COL),HL

	CALL	INVALIDATE_ACTIVE_LINE
	CALL	CHECKOUT_ACTIVE_LINE
	CALL	RELOAD_CACHE_WINDOW_FORCE

	CALL	TERM_INIT
	CALL	RENDER_SCREEN
	CALL	RENDER_STATUS_BAR
	CALL	CHECK_FILE_TRUNCATED_POPUP
	CALL	LOCATE_CURSOR
	JP	MAIN_LOOP

HOFF_LOAD_FAIL:
	; File not found / disk error: show inline "  File not found"
	LD	DE,STR_FNF_INLINE
	LD	C,16
	JP	SHOW_INLINE_OPEN_ERROR

;------------------------------------------------------------------------------
; HANDLE_SAVE_FAT_DISPATCH:
; Dispatches confirmed explicit FAT input in Save dialog.
;------------------------------------------------------------------------------
HANDLE_SAVE_FAT_DISPATCH:
	LD	HL,INPUT_FILENAME_BUF
	CALL	PARSE_FAT_PATH		; A = unit, HL = path after ':'
	LD	(VFS_REQ_UNIT),A
	LD	(FAT_DOC_UNIT),A

HSFD_CHECK_EMPTY:
	LD	A,(HL)
	OR	A
	JR	Z,HANDLE_SAVE_FAT_DRIVE_SWITCH
	CP	' '
	JR	NZ,HSFD_NOT_EMPTY
	INC	HL
	JR	HSFD_CHECK_EMPTY

HSFD_NOT_EMPTY:
	CP	'/'
	JR	NZ,HSFD_CHECK_DESCENT
	INC	HL
	LD	A,(HL)
	OR	A
	JR	Z,HANDLE_SAVE_FAT_DRIVE_SWITCH
	CP	' '
	JR	Z,HANDLE_SAVE_FAT_DRIVE_SWITCH
	DEC	HL

HSFD_CHECK_DESCENT:
	CALL	CHECK_HL_ENDS_WITH_SLASH
	JR	C,HANDLE_SAVE_FAT_SUBDIR_SWITCH

	JP	HANDLE_SAVE_FAT_FILE

;------------------------------------------------------------------------------
; HANDLE_SAVE_FAT_SUBDIR_SWITCH:
; Switches active directory view to target FAT unit and subdirectory in Save.
;------------------------------------------------------------------------------
HANDLE_SAVE_FAT_SUBDIR_SWITCH:
	LD	A,1
	LD	(CURRENT_DIR_IS_FAT),A
	LD	A,(VFS_REQ_UNIT)
	LD	(CURRENT_DIR_FAT_UNIT),A
	CALL	SET_DIR_FROM_PATH_HL
	LD	A,'U'
	LD	(STR_SAVE_DRIVE_CHAR),A
	LD	(STR_DIR_DRIVE_CHAR),A
	CALL	RESET_DIR_FILTER
	XOR	A
	LD	(SHOWING_FNF_MSG),A
	JP	REFRESH_SAVE_DIR

;------------------------------------------------------------------------------
; HANDLE_SAVE_FAT_DRIVE_SWITCH:
; Switches active directory view to target FAT unit root in Save dialog.
;------------------------------------------------------------------------------
HANDLE_SAVE_FAT_DRIVE_SWITCH:
	LD	A,1
	LD	(CURRENT_DIR_IS_FAT),A
	LD	A,(VFS_REQ_UNIT)
	LD	(CURRENT_DIR_FAT_UNIT),A
	CALL	FAT_PATH_SET_ROOT
	LD	A,'U'
	LD	(STR_SAVE_DRIVE_CHAR),A
	LD	(STR_DIR_DRIVE_CHAR),A
	CALL	RESET_DIR_FILTER
	XOR	A
	LD	(SHOWING_FNF_MSG),A
	JP	REFRESH_SAVE_DIR

;------------------------------------------------------------------------------
; HANDLE_SAVE_FAT_RELATIVE:
; Handles save input when CURRENT_DIR_IS_FAT == 1 without explicit drive prefix.
;------------------------------------------------------------------------------
HANDLE_SAVE_FAT_RELATIVE:
	CALL	CHECK_AND_HANDLE_FAT_NAV
	JR	NC,HSFR_NOT_NAV
	CALL	RESET_DIR_FILTER
	XOR	A
	LD	(SHOWING_FNF_MSG),A
	JP	REFRESH_SAVE_DIR

HSFR_NOT_NAV:
	CALL	BUILD_RELATIVE_FAT_PATH
	LD	A,(CURRENT_DIR_FAT_UNIT)
	LD	(VFS_REQ_UNIT),A
	LD	(FAT_DOC_UNIT),A
	JR	HSFF_DO_SAVE

;------------------------------------------------------------------------------
; HANDLE_SAVE_FAT_FILE:
; Invoked when user confirms an explicit FAT file in Save dialog.
;------------------------------------------------------------------------------
HANDLE_SAVE_FAT_FILE:
	LD	HL,INPUT_FILENAME_BUF
	CALL	PARSE_FAT_PATH		; A = unit, HL = path after ':'
	LD	(VFS_REQ_UNIT),A
	LD	(FAT_DOC_UNIT),A

	; Copy path after ':' into FAT_DOC_PATH (prepending '/' if needed)
	LD	DE,FAT_DOC_PATH
	LD	A,(HL)
	CP	'/'
	JR	Z,HSFF_COPY_PATH
	LD	A,'/'
	LD	(DE),A
	INC	DE
HSFF_COPY_PATH:
	LD	A,(HL)
	OR	A
	JR	Z,HSFF_PATH_DONE
	CP	' '
	JR	Z,HSFF_PATH_DONE
	LD	(DE),A
	INC	HL
	INC	DE
	JR	HSFF_COPY_PATH
HSFF_PATH_DONE:
	XOR	A
	LD	(DE),A

HSFF_DO_SAVE:
	; Extract base filename into FAT_DOC_FNAME
	LD	HL,FAT_DOC_PATH
	CALL	EXTRACT_BASE_FILENAME

	; Update CURRENT_DIR_FAT_PATH from FAT_DOC_PATH
	CALL	SET_DIR_FROM_DOC_PATH

	; Call VFS save
	CALL	VFS_SAVE_FAT_FILE
	JR	C,HSFF_SAVE_FAIL

	; If not block save, mark document as FAT file and clean
	LD	A,(IS_BLOCK_SAVE_UI)
	OR	A
	RET	NZ

	LD	A,1
	LD	(DOC_IS_FAT),A
	LD	(HAS_FILE_ARG),A
	XOR	A
	LD	(DOC_MODIFIED),A
	RET

HSFF_SAVE_FAIL:
	LD	DE,STR_FNF_INLINE
	LD	C,16
	JP	SHOW_INLINE_SAVE_ERROR

;------------------------------------------------------------------------------
; CHECK_AND_HANDLE_FAT_NAV:
; Checks if INPUT_FILENAME_BUF specifies subdirectory navigation.
; Returns:
;   Carry = 1: Navigation action performed
;   Carry = 0: Not navigation (it is a filename)
;------------------------------------------------------------------------------
CHECK_AND_HANDLE_FAT_NAV:
	LD	HL,INPUT_FILENAME_BUF
CAHFN_SKIP_SP:
	LD	A,(HL)
	CP	' '
	JR	NZ,CAHFN_START
	INC	HL
	JR	CAHFN_SKIP_SP

CAHFN_START:
	OR	A
	RET	Z			; Empty string -> Carry = 0

	; Check for "/" alone
	CP	'/'
	JR	NZ,CAHFN_CHECK_DOT
	INC	HL
	LD	A,(HL)
	OR	A
	JR	Z,CAHFN_DO_ROOT
	CP	' '
	JR	Z,CAHFN_DO_ROOT
	DEC	HL
	JR	CAHFN_CHECK_TRAILING_SLASH

CAHFN_DO_ROOT:
	CALL	FAT_PATH_SET_ROOT
	SCF
	RET

CAHFN_CHECK_DOT:
	CP	'.'
	JR	NZ,CAHFN_CHECK_TRAILING_SLASH
	INC	HL
	LD	A,(HL)
	CP	'.'
	JR	Z,CAHFN_DOT_DOT
	; Single dot: '.' or './'
	OR	A
	JR	Z,CAHFN_DO_SAME_DIR
	CP	' '
	JR	Z,CAHFN_DO_SAME_DIR
	CP	'/'
	JR	NZ,CAHFN_NOT_DOT_CMD
	INC	HL
	LD	A,(HL)
	OR	A
	JR	Z,CAHFN_DO_SAME_DIR
	CP	' '
	JR	Z,CAHFN_DO_SAME_DIR
CAHFN_NOT_DOT_CMD:
	DEC	HL
	JR	CAHFN_CHECK_TRAILING_SLASH

CAHFN_DO_SAME_DIR:
	SCF
	RET

CAHFN_DOT_DOT:
	; Got ".."
	INC	HL
	LD	A,(HL)
	OR	A
	JR	Z,CAHFN_DO_POP
	CP	' '
	JR	Z,CAHFN_DO_POP
	CP	'/'
	JR	NZ,CAHFN_NOT_DOTDOT_CMD
	INC	HL
	LD	A,(HL)
	OR	A
	JR	Z,CAHFN_DO_POP
	CP	' '
	JR	Z,CAHFN_DO_POP
CAHFN_NOT_DOTDOT_CMD:
	DEC	HL
	DEC	HL
	JR	CAHFN_CHECK_TRAILING_SLASH

CAHFN_DO_POP:
	CALL	FAT_PATH_POP_DIR
	SCF
	RET

CAHFN_CHECK_TRAILING_SLASH:
	LD	HL,INPUT_FILENAME_BUF
	CALL	CHECK_HL_ENDS_WITH_SLASH
	JR	NC,CAHFN_CHECK_DIR_ENTRY

	; Input ends with '/' -> descend into directory
	LD	HL,INPUT_FILENAME_BUF
	CALL	FAT_PATH_PUSH_DIR
	SCF
	RET

CAHFN_CHECK_DIR_ENTRY:
	CALL	CHECK_INPUT_IS_DIR_ENTRY
	RET	NC			; Carry = 0: not a directory entry

	; Matches a directory entry in grid!
	LD	HL,INPUT_FILENAME_BUF
	CALL	FAT_PATH_PUSH_DIR
	SCF
	RET

;------------------------------------------------------------------------------
; CHECK_INPUT_IS_DIR_ENTRY:
; Checks if INPUT_FILENAME_BUF matches a DIR_NAMES_BUF dir (byte 8 == '/')
; Returns:
;   Carry = 1 if matched a directory entry
;   Carry = 0 if no match
;------------------------------------------------------------------------------
CHECK_INPUT_IS_DIR_ENTRY:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	LD	A,(DIR_FILE_COUNT)
	OR	A
	JR	Z,CIIDE_NO_MATCH

	LD	B,A			; B = entry count
	LD	HL,DIR_NAMES_BUF

CIIDE_ENTRY_LOOP:
	; Check if byte 8 of entry is '/'
	PUSH	HL
	LD	DE,8
	ADD	HL,DE
	LD	A,(HL)
	POP	HL
	CP	'/'
	JR	NZ,CIIDE_NEXT_ENTRY	; Not a directory entry

	; HL points to entry (8-char name at HL..HL+7)
	; Compare with INPUT_FILENAME_BUF
	PUSH	BC
	PUSH	HL
	LD	DE,INPUT_FILENAME_BUF

CIIDE_SKIP_SP:
	LD	A,(DE)
	CP	' '
	JR	NZ,CIIDE_CMP_START
	INC	DE
	JR	CIIDE_SKIP_SP

CIIDE_CMP_START:
	LD	C,8			; 8 characters in name field
CIIDE_CHAR_LOOP:
	LD	A,(DE)			; Character from input
	OR	A
	JR	Z,CIIDE_INPUT_ENDED
	CP	' '
	JR	Z,CIIDE_INPUT_ENDED
	CP	'/'
	JR	Z,CIIDE_INPUT_ENDED

	CALL	TO_UPPER
	CP	(HL)			; Compare with entry char
	JR	NZ,CIIDE_MISMATCH
	INC	DE
	INC	HL
	DEC	C
	JR	NZ,CIIDE_CHAR_LOOP

	; Input matched all 8 characters.
	; Next char in input must be 0, space, or '/'
	LD	A,(DE)
	OR	A
	JR	Z,CIIDE_MATCH_FOUND
	CP	' '
	JR	Z,CIIDE_MATCH_FOUND
	CP	'/'
	JR	Z,CIIDE_MATCH_FOUND
	JR	CIIDE_MISMATCH

CIIDE_INPUT_ENDED:
	; Input ended before 8 chars.
	; Remaining chars in entry name must be spaces (' ')
CIIDE_PAD_CHECK:
	LD	A,(HL)
	CP	' '
	JR	NZ,CIIDE_MISMATCH
	INC	HL
	DEC	C
	JR	NZ,CIIDE_PAD_CHECK

CIIDE_MATCH_FOUND:
	POP	HL
	POP	BC
	POP	HL
	POP	DE
	POP	BC
	SCF				; Carry = 1 (match!)
	RET

CIIDE_MISMATCH:
	POP	HL
	POP	BC

CIIDE_NEXT_ENTRY:
	LD	DE,13
	ADD	HL,DE
	DJNZ	CIIDE_ENTRY_LOOP

CIIDE_NO_MATCH:
	POP	HL
	POP	DE
	POP	BC
	OR	A			; Carry = 0
	RET

;------------------------------------------------------------------------------
; CHECK_HL_ENDS_WITH_SLASH:
; Returns Carry = 1 if the last non-space character in string at HL is '/'.
;------------------------------------------------------------------------------
CHECK_HL_ENDS_WITH_SLASH:
	PUSH	HL
	LD	C,0			; Tracks last non-space char
CHLE_SCAN:
	LD	A,(HL)
	OR	A
	JR	Z,CHLE_DONE
	CP	' '
	JR	Z,CHLE_NEXT
	LD	C,A
CHLE_NEXT:
	INC	HL
	JR	CHLE_SCAN
CHLE_DONE:
	POP	HL
	LD	A,C
	CP	'/'
	JR	NZ,CHLE_NOT_SLASH
	SCF
	RET
CHLE_NOT_SLASH:
	OR	A
	RET

;------------------------------------------------------------------------------
; BUILD_RELATIVE_FAT_PATH:
; Constructs full DOS path in FAT_DOC_PATH from CURRENT_DIR_FAT_PATH
; and INPUT_FILENAME_BUF.
; Output:
;   FAT_DOC_PATH populated (null-terminated)
;------------------------------------------------------------------------------
BUILD_RELATIVE_FAT_PATH:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	LD	HL,INPUT_FILENAME_BUF
BRFP_SKIP_SP:
	LD	A,(HL)
	CP	' '
	JR	NZ,BRFP_START
	INC	HL
	JR	BRFP_SKIP_SP

BRFP_START:
	; If input starts with '/', copy directly to FAT_DOC_PATH
	CP	'/'
	JR	Z,BRFP_COPY_ABSOLUTE

	; Copy CURRENT_DIR_FAT_PATH to FAT_DOC_PATH
	LD	DE,CURRENT_DIR_FAT_PATH
	LD	BC,FAT_DOC_PATH
BRFP_COPY_CUR:
	LD	A,(DE)
	OR	A
	JR	Z,BRFP_CHECK_CUR_SLASH
	LD	(BC),A
	INC	DE
	INC	BC
	JR	BRFP_COPY_CUR

BRFP_CHECK_CUR_SLASH:
	DEC	BC
	LD	A,(BC)
	INC	BC
	CP	'/'
	JR	Z,BRFP_APPEND_NAME
	LD	A,'/'
	LD	(BC),A
	INC	BC

BRFP_APPEND_NAME:
	LD	A,(HL)
	OR	A
	JR	Z,BRFP_FINISH
	CP	' '
	JR	Z,BRFP_FINISH
	CALL	TO_UPPER
	LD	(BC),A
	INC	HL
	INC	BC
	JR	BRFP_APPEND_NAME

BRFP_COPY_ABSOLUTE:
	LD	BC,FAT_DOC_PATH
BRFP_ABS_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,BRFP_FINISH
	CP	' '
	JR	Z,BRFP_FINISH
	CALL	TO_UPPER
	LD	(BC),A
	INC	HL
	INC	BC
	JR	BRFP_ABS_LOOP

BRFP_FINISH:
	XOR	A
	LD	(BC),A			; Null terminate
	POP	HL
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; SET_DIR_FROM_PATH_HL:
; Copies path at HL into CURRENT_DIR_FAT_PATH. Prepend '/' if needed, convert
; to upper case, and strip trailing '/' unless at root ("/").
;------------------------------------------------------------------------------
SET_DIR_FROM_PATH_HL:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	DE,CURRENT_DIR_FAT_PATH

SDFP_SKIP_SP:
	LD	A,(HL)
	CP	' '
	JR	NZ,SDFP_CHECK_ROOT
	INC	HL
	JR	SDFP_SKIP_SP

SDFP_CHECK_ROOT:
	CP	'/'
	JR	Z,SDFP_COPY_LOOP
	LD	A,'/'
	LD	(DE),A
	INC	DE

SDFP_COPY_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,SDFP_FINISH
	CP	' '
	JR	Z,SDFP_FINISH
	CALL	TO_UPPER
	LD	(DE),A
	INC	HL
	INC	DE
	JR	SDFP_COPY_LOOP

SDFP_FINISH:
	XOR	A
	LD	(DE),A			; Null terminate

	; Strip trailing slash if path length > 1
	LD	HL,CURRENT_DIR_FAT_PATH
	INC	HL
	LD	A,(HL)
	OR	A
	JR	Z,SDFP_DONE		; Length 1 ("/") -> done

	DEC	DE
	LD	A,(DE)
	CP	'/'
	JR	NZ,SDFP_DONE
	XOR	A
	LD	(DE),A			; Strip trailing slash

SDFP_DONE:
	POP	HL
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; SET_DIR_FROM_DOC_PATH:
; Updates CURRENT_DIR_FAT_PATH from FAT_DOC_PATH.
; Finds the last '/' in FAT_DOC_PATH:
; - If last '/' is at index 0 (or path empty) -> sets root ("/")
; - If last '/' is at index > 0 -> copies up to last '/'
;------------------------------------------------------------------------------
SET_DIR_FROM_DOC_PATH:
	PUSH	BC
	PUSH	DE
	PUSH	HL

	LD	HL,FAT_DOC_PATH
	LD	A,(HL)
	OR	A
	JR	Z,SDFDP_SET_ROOT	; Empty -> set root

	; BC tracks candidate pointer to last slash
	LD	B,H
	LD	C,L
SDFDP_SCAN:
	LD	A,(HL)
	OR	A
	JR	Z,SDFDP_END
	CP	'/'
	JR	NZ,SDFDP_NEXT
	LD	B,H
	LD	C,L
SDFDP_NEXT:
	INC	HL
	JR	SDFDP_SCAN

SDFDP_END:
	; BC points to the last slash in FAT_DOC_PATH
	LD	HL,FAT_DOC_PATH
	LD	A,B
	CP	H
	JR	NZ,SDFDP_HAS_SUBDIR
	LD	A,C
	CP	L
	JR	NZ,SDFDP_HAS_SUBDIR

SDFDP_SET_ROOT:
	CALL	FAT_PATH_SET_ROOT
	POP	HL
	POP	DE
	POP	BC
	RET

SDFDP_HAS_SUBDIR:
	; Copy from FAT_DOC_PATH up to BC into CURRENT_DIR_FAT_PATH
	LD	DE,CURRENT_DIR_FAT_PATH
SDFDP_COPY:
	LD	A,H
	CP	B
	JR	NZ,SDFDP_COPY_CHAR
	LD	A,L
	CP	C
	JR	Z,SDFDP_DONE
SDFDP_COPY_CHAR:
	LD	A,(HL)
	LD	(DE),A
	INC	HL
	INC	DE
	JR	SDFDP_COPY

SDFDP_DONE:
	XOR	A
	LD	(DE),A
	POP	HL
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; FAT_PATH_SET_ROOT:
; Resets CURRENT_DIR_FAT_PATH to "/".
;------------------------------------------------------------------------------
FAT_PATH_SET_ROOT:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	HL,STR_SLASH
	LD	DE,CURRENT_DIR_FAT_PATH
	LD	BC,2
	LDIR
	POP	HL
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; FAT_PATH_POP_DIR:
; Ascends one directory level in CURRENT_DIR_FAT_PATH.
;------------------------------------------------------------------------------
FAT_PATH_POP_DIR:
	PUSH	DE
	PUSH	HL

	LD	HL,CURRENT_DIR_FAT_PATH
	LD	A,(HL)
	OR	A
	JR	Z,FPPD_RESET		; Empty -> set root
	INC	HL
	LD	A,(HL)
	OR	A
	JR	Z,FPPD_DONE		; Length 1 ("/") -> already at root

	DEC	HL			; Back to start
FPPD_FIND_END:
	LD	A,(HL)
	OR	A
	JR	Z,FPPD_AT_END
	INC	HL
	JR	FPPD_FIND_END

FPPD_AT_END:
	DEC	HL
	LD	A,(HL)
	CP	'/'
	JR	NZ,FPPD_SCAN_PREV_SLASH
	DEC	HL

FPPD_SCAN_PREV_SLASH:
	LD	DE,CURRENT_DIR_FAT_PATH
	LD	A,H
	CP	D
	JR	NZ,FPPD_CHECK_CHAR
	LD	A,L
	CP	E
	JR	Z,FPPD_RESET		; Reached start -> reset to root

FPPD_CHECK_CHAR:
	LD	A,(HL)
	CP	'/'
	JR	Z,FPPD_FOUND_SLASH
	DEC	HL
	JR	FPPD_SCAN_PREV_SLASH

FPPD_FOUND_SLASH:
	LD	A,H
	CP	D
	JR	NZ,FPPD_TRUNCATE
	LD	A,L
	CP	E
	JR	NZ,FPPD_TRUNCATE
	INC	HL
	XOR	A
	LD	(HL),A
	JR	FPPD_DONE

FPPD_TRUNCATE:
	XOR	A
	LD	(HL),A
	JR	FPPD_DONE

FPPD_RESET:
	CALL	FAT_PATH_SET_ROOT

FPPD_DONE:
	POP	HL
	POP	DE
	RET

;------------------------------------------------------------------------------
; FAT_PATH_PUSH_DIR:
; Appends directory segment from HL to CURRENT_DIR_FAT_PATH.
;------------------------------------------------------------------------------
FAT_PATH_PUSH_DIR:
	PUSH	BC
	PUSH	DE
	PUSH	HL

FP_PUSH_SKIP_SP:
	LD	A,(HL)
	CP	' '
	JR	NZ,FP_PUSH_START
	INC	HL
	JR	FP_PUSH_SKIP_SP

FP_PUSH_START:
	OR	A
	JR	Z,FP_PUSH_EXIT		; Empty -> do nothing

	CP	'/'
	JR	NZ,FP_PUSH_RELATIVE
	CALL	FAT_PATH_SET_ROOT
	INC	HL
	LD	A,(HL)
	OR	A
	JR	Z,FP_PUSH_EXIT
	CP	' '
	JR	Z,FP_PUSH_EXIT

FP_PUSH_RELATIVE:
	LD	DE,CURRENT_DIR_FAT_PATH
FP_PUSH_FIND_END:
	LD	A,(DE)
	OR	A
	JR	Z,FP_PUSH_AT_END
	INC	DE
	JR	FP_PUSH_FIND_END

FP_PUSH_AT_END:
	LD	A,(CURRENT_DIR_FAT_PATH)
	OR	A
	JR	Z,FP_PUSH_ADD_SLASH
	DEC	DE
	LD	A,(DE)
	INC	DE
	CP	'/'
	JR	Z,FP_PUSH_COPY_CHARS
FP_PUSH_ADD_SLASH:
	LD	A,'/'
	LD	(DE),A
	INC	DE

FP_PUSH_COPY_CHARS:
	LD	A,(HL)
	OR	A
	JR	Z,FP_PUSH_FINISH
	CP	' '
	JR	Z,FP_PUSH_FINISH
	CP	'/'
	JR	NZ,FP_PUSH_REG_CHAR
	INC	HL
	LD	A,(HL)
	DEC	HL
	OR	A
	JR	Z,FP_PUSH_FINISH
	CP	' '
	JR	Z,FP_PUSH_FINISH
	LD	A,'/'
	JR	FP_PUSH_STORE_CHAR

FP_PUSH_REG_CHAR:
	CALL	TO_UPPER
FP_PUSH_STORE_CHAR:
	LD	(DE),A
	INC	DE
	INC	HL
	JR	FP_PUSH_COPY_CHARS

FP_PUSH_FINISH:
	XOR	A
	LD	(DE),A

FP_PUSH_EXIT:
	POP	HL
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; COLLECT_FAT_DIR_ENTRIES:
; Collect directory entries from active FAT volume via VFS_CMD_LIST_DIR (1)
; Populates DIR_NAMES_BUF with 13-byte formatted records.
; If DIR_FILTER_ACTIVE != 0, filters files in-place preserving subdirectories.
;------------------------------------------------------------------------------
COLLECT_FAT_DIR_ENTRIES:
	LD	A,1			; VFS_CMD_LIST_DIR
	LD	(VFS_REQ_CMD),A
	LD	A,(CURRENT_DIR_FAT_UNIT)
	LD	(VFS_REQ_UNIT),A
	XOR	A
	LD	(VFS_REQ_FLAGS),A
	LD	(VFS_REQ_STATUS),A
	LD	HL,CURRENT_DIR_FAT_PATH
	LD	(VFS_REQ_PATH),HL
	LD	HL,DIR_NAMES_BUF
	LD	(VFS_REQ_BUFFER),HL
	LD	HL,255			; Buffer capacity (max entries)
	LD	(VFS_REQ_BUFSIZE),HL
	CALL	VFS_EXEC_REQUEST
	JR	C,CFDE_EMPTY
	LD	A,(VFS_REQ_STATUS)
	OR	A
	JR	NZ,CFDE_EMPTY
	LD	HL,(VFS_REQ_COUNT)
	LD	A,L
	LD	(DIR_FILE_COUNT),A

	; Check if custom filter is active
	LD	A,(DIR_FILTER_ACTIVE)
	OR	A
	RET	Z			; No filter -> done

	; In-place filter DIR_NAMES_BUF against DIR_FILTER_FCB
	CALL	FILTER_FAT_DIR_ENTRIES
	RET

CFDE_EMPTY:
	XOR	A
	LD	(DIR_FILE_COUNT),A
	RET

;------------------------------------------------------------------------------
; FILTER_FAT_DIR_ENTRIES:
; Filters DIR_NAMES_BUF in-place against DIR_FILTER_FCB (8 name + 3 ext).
; Directory entries (where byte 8 == '/') are ALWAYS preserved.
;------------------------------------------------------------------------------
FILTER_FAT_DIR_ENTRIES:
	LD	A,(DIR_FILE_COUNT)
	OR	A
	RET	Z			; Nothing to filter

	LD	B,A			; B = entries remaining to check
	LD	C,0			; C = kept entries count
	LD	HL,DIR_NAMES_BUF	; HL = read pointer
	LD	DE,DIR_NAMES_BUF	; DE = write pointer

FFDE_LOOP:
	; Check if entry is a directory (byte 8 == '/')
	PUSH	HL
	LD	A,8
	ADD	A,L
	LD	L,A
	LD	A,0
	ADC	A,H
	LD	H,A
	LD	A,(HL)
	POP	HL
	CP	'/'
	JR	Z,FFDE_KEEP_ENTRY	; Directories always kept

	; It's a file: compare 8-byte name with DIR_FILTER_FCB+0..7
	PUSH	BC
	PUSH	DE
	PUSH	HL

	LD	DE,DIR_FILTER_FCB
	LD	B,8
FFDE_MATCH_NAME:
	LD	A,(DE)
	CP	'?'
	JR	Z,FFDE_NAME_CHAR_OK
	CP	(HL)
	JR	NZ,FFDE_MISMATCH
FFDE_NAME_CHAR_OK:
	INC	HL
	INC	DE
	DJNZ	FFDE_MATCH_NAME

	; Name matched. HL now points to byte 8 ('.'). Skip it.
	INC	HL

	; Compare 3-byte extension with DIR_FILTER_FCB+8..10
	LD	B,3
FFDE_MATCH_EXT:
	LD	A,(DE)
	CP	'?'
	JR	Z,FFDE_EXT_CHAR_OK
	CP	(HL)
	JR	NZ,FFDE_MISMATCH
FFDE_EXT_CHAR_OK:
	INC	HL
	INC	DE
	DJNZ	FFDE_MATCH_EXT

	; Both name and extension matched!
	POP	HL
	POP	DE
	POP	BC
	JR	FFDE_KEEP_ENTRY

FFDE_MISMATCH:
	POP	HL
	POP	DE
	POP	BC
	; Skip this entry: advance read pointer HL by 13
	LD	A,13
	ADD	A,L
	LD	L,A
	LD	A,0
	ADC	A,H
	LD	H,A
	DEC	B
	JR	NZ,FFDE_LOOP
	JR	FFDE_ALL_DONE

FFDE_KEEP_ENTRY:
	; Check if HL == DE (entry already in place)
	LD	A,H
	CP	D
	JR	NZ,FFDE_DO_COPY
	LD	A,L
	CP	E
	JR	Z,FFDE_ALREADY_IN_PLACE

FFDE_DO_COPY:
	PUSH	BC
	LD	BC,13
	LDIR
	POP	BC
	JR	FFDE_ENTRY_KEPT

FFDE_ALREADY_IN_PLACE:
	; Advance both HL and DE by 13
	LD	A,13
	ADD	A,L
	LD	L,A
	LD	A,0
	ADC	A,H
	LD	H,A
	LD	D,H
	LD	E,L

FFDE_ENTRY_KEPT:
	INC	C			; One more entry kept
	DEC	B
	JR	NZ,FFDE_LOOP

FFDE_ALL_DONE:
	LD	A,C
	LD	(DIR_FILE_COUNT),A
	RET

;------------------------------------------------------------------------------
; VFS_LOAD_FAT_FILE:
; Loads text file from FAT media into editor.
; Input:
;   (VFS_REQ_UNIT) = HBIOS unit (0..7 or 0xFF)
;   HL = Pointer to null-terminated DOS path
; Output:
;   Carry = 0: Success
;   Carry = 1: Failure (file not found or disk error)
;------------------------------------------------------------------------------
VFS_LOAD_FAT_FILE:
	LD	A,2			; VFS_CMD_LOAD_FILE
	LD	(VFS_REQ_CMD),A
	XOR	A
	LD	(VFS_REQ_FLAGS),A
	LD	(VFS_REQ_STATUS),A
	LD	(VFS_REQ_PATH),HL
	LD	DE,0
	LD	(VFS_REQ_BUFFER),DE
	LD	(VFS_REQ_BUFSIZE),DE
	LD	DE,VFS_REQ_PKT
	CALL	VFS_EXEC_REQUEST
	RET	C			; Return carry if error

	; Update FAT_DOC_UNIT with unit returned by VFS (in case it was 0xFF)
	LD	A,(VFS_REQ_UNIT)
	LD	(FAT_DOC_UNIT),A
	OR	A			; Carry = 0
	RET

;------------------------------------------------------------------------------
; VFS_SAVE_FAT_FILE:
; Exports editor document (or line range for block save) to FAT media.
; Input:
;   (VFS_REQ_UNIT) = HBIOS unit
;   FAT_DOC_PATH = null-terminated DOS path
; Output:
;   Carry = 0: Success
;   Carry = 1: Failure
;------------------------------------------------------------------------------
VFS_SAVE_FAT_FILE:
	LD	A,(IS_BLOCK_SAVE_UI)
	OR	A
	JR	NZ,VSFF_BLOCK_SAVE

	LD	A,3			; VFS_CMD_SAVE_FILE
	LD	(VFS_REQ_CMD),A
	JR	VSFF_DO_SAVE

VSFF_BLOCK_SAVE:
	LD	A,4			; VFS_CMD_SAVE_RANGE
	LD	(VFS_REQ_CMD),A
	LD	HL,(BLOCK_START_ROW)
	LD	(VFS_REQ_START_LINE),HL
	LD	HL,(BLOCK_END_ROW)
	LD	(VFS_REQ_END_LINE),HL

VSFF_DO_SAVE:
	XOR	A
	LD	(VFS_REQ_FLAGS),A
	LD	(VFS_REQ_STATUS),A
	LD	HL,FAT_DOC_PATH
	LD	(VFS_REQ_PATH),HL
	LD	DE,0
	LD	(VFS_REQ_BUFFER),DE
	LD	(VFS_REQ_BUFSIZE),DE
	LD	DE,VFS_REQ_PKT
	CALL	VFS_EXEC_REQUEST
	RET	C

	LD	A,(VFS_REQ_UNIT)
	LD	(FAT_DOC_UNIT),A
	OR	A
	RET

;------------------------------------------------------------------------------
; PREFILL_FAT_FILENAME_BUF:
; Pre-fills INPUT_FILENAME_BUF with "U<unit>:<path>" or "U:<path>"
;------------------------------------------------------------------------------
PREFILL_FAT_FILENAME_BUF:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	DE,INPUT_FILENAME_BUF
	LD	C,0			; Length counter

	LD	A,'U'
	LD	(DE),A
	INC	DE
	INC	C

	LD	A,(FAT_DOC_UNIT)
	CP	0FFH
	JR	Z,PFFB_COLON
	ADD	A,'0'
	LD	(DE),A
	INC	DE
	INC	C

PFFB_COLON:
	LD	A,':'
	LD	(DE),A
	INC	DE
	INC	C

	; Copy FAT_DOC_PATH
	LD	HL,FAT_DOC_PATH
PFFB_PATH_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,PFFB_DONE
	LD	(DE),A
	INC	HL
	INC	DE
	INC	C
	JR	PFFB_PATH_LOOP

PFFB_DONE:
	XOR	A
	LD	(DE),A			; Null terminate
	LD	A,C
	LD	(INPUT_BUF_LEN),A
	LD	(INPUT_CURSOR_POS),A
	POP	HL
	POP	DE
	POP	BC
	RET

; Context Plugin Pop-up String Constants
STR_POPUP_BORDER:		DB	"+------------------------------------------------+", 0

; Save Changes Modal Pop-up Strings (50 cols x 7 rows)
STR_POPUP_SAVE_TITLE:
	DB	"|             Unsaved Modifications              |", 0
STR_POPUP_SAVE_MSG1:
	DB	"| Any unsaved edits will be lost if discarded.   |", 0
STR_POPUP_SAVE_MSG2:
	DB	"| Save changes?                                  |", 0
STR_POPUP_SAVE_KEYS:
	DB	"|          [Y]es / [N]o / [ESC]=Cancel           |", 0

; File Truncated Modal Pop-up Strings (50 cols x 7 rows)
STR_POPUP_TRUNC_TITLE:
	DB	"|                 File Truncated                 |", 0
STR_POPUP_TRUNC_MSG1:
	DB	"| File exceeded capacity and has been truncated. |", 0
STR_POPUP_TRUNC_MSG2:
	DB	"| Save is disabled to protect data on disk.      |", 0
STR_POPUP_TRUNC_KEY:
	DB	"|           Press any key to continue            |", 0

; Find Modal Pop-up Strings (50 cols x 7 rows)
STR_FIND_POPUP_TITLE:
	DB	"|                   Find Text                    |", 0
STR_FIND_POPUP_PROMPT_EXACT:
	DB	"| Find (Exact):  [", 0
STR_FIND_POPUP_PROMPT_INSENS:
	DB	"| Find (Insens): [", 0
STR_FIND_POPUP_BOX_CLOSE:
	DB	"] |", 0
STR_FIND_POPUP_MODE_EXACT:
	DB	"| Match:   [Case Sensitive  ]                    |", 0
STR_FIND_POPUP_MODE_INSENS:
	DB	"| Match:   [Case Insensitive]                    |", 0
STR_FIND_POPUP_KEYS:
	DB	"| Enter:Find       Tab:Toggle Case    ESC:Cancel |", 0

; Replace Modal Pop-up Strings (50 cols x 7 rows)
STR_REPLACE_POPUP_TITLE:
	DB	"|                  Replace Text                  |", 0
STR_REPLACE_POPUP_PROMPT:
	DB	"| Replace with:  [", 0
STR_REPLACE_POPUP_MSG:
	DB	"| Enter replacement text to substitute for match |", 0
STR_REPLACE_POPUP_KEYS:
	DB	"| Enter:Confirm                       ESC:Cancel |", 0
STR_DEF_PLUGIN_MGR:	DB	"PLUGIN.PRL", 0
STR_MSG_NEED_PLUGIN_MGR: DB	"Feature requires PLUGIN.PRL", "$"
STR_NAME_BEAUTIFY:	DB	"BEAUTIFY", 0
STR_MSG_PLUG_MISSING:	DB	"[Plugin Missing]$", 0

;------------------------------------------------------------------------------
; String Constants & Data
;------------------------------------------------------------------------------
STR_CLEAR_SCREEN:	DB	27,"[2J",27,"[H","$"

STR_HOME:	DB	27,"[H","$"

STR_GOTO_ROW_24:	DB	27,"[24;1H","$"

STR_GOTO_ROW_40:	DB	27,"[40;1H","$"

STR_CLEAR_EOL:	DB	27,"[K","$"

STR_INVERSE_ON:	DB	27,"[7m","$"

STR_INVERSE_OFF:	DB	27,"[0m","$"

STR_HIDE_CURSOR:	DB	27,"[?25l","$"

STR_SHOW_CURSOR:	DB	27,"[?25h","$"

STR_CRLF:	DB	13,10,"$"

STR_SPLASH_TITLE_PAD:	DB	"           ", "$"
STR_SPLASH_TITLE:	DB	"SE - Screen Editor", 13, 10, "$"

STR_SPLASH_CMDS:
	DB	"  type   e  or  <Enter>   to edit",13,10
	DB	"  type   n                to new file",13,10
	DB	"  type   o                to open file",13,10
	DB	"  type   s                to save file",13,10
	DB	"  type   w  or  ^W        to close file",13,10
	DB	"  type   l  or  ^L        to goto line",13,10
	DB	"  type   a                for about",13,10
	DB	"  type   m                for memory info",13,10
	DB	"  type   p                for plugins",13,10
	DB	"  type   c                to configure",13,10
	DB	"  type   1                set 120x40",13,10
	DB	"  type   2                set 80x24",13,10
	DB	"  type   q  or  ^Q        to exit",13,10
	DB	0

STR_SPLASH_CUR_MODE:	DB	"Active Screen: [$"
STR_SPLASH_120X40_LBL:	DB	"120x40 (Modern Default)]",13,10,"$"
STR_SPLASH_80X24_LBL:	DB	"80x24 (Classic Terminal)] ",13,10,"$"

STR_SPLASH_RAM_PRE:	DB	"RAM Drive ("
STR_SPLASH_RAM_LTR:	DB	"A:): [$"
STR_SPLASH_RAM_NONE:	DB	"RAM Drive     : [None Detected]",13,10,"$"
STR_SPLASH_RAM_PRESERV:	DB	"Preserved (Active)]",13,10,"$"
STR_SPLASH_RAM_OVERWR:	DB	"Overwritten (Max RAM)]",13,10,"$"
STR_SPLASH_RAM_HIBERN:	DB	"Hibernated (Temp Image)]",13,10,"$"
STR_SPLASH_PLUG_PRE:		DB	"Plugin System : [", "$"
STR_SPLASH_PLUG_OPERATIONAL:	DB	"Operational]", 13, 10, "$"
STR_SPLASH_PLUG_ONDEMAND:	DB	"On Demand]", 13, 10, "$"
STR_SPLASH_PLUG_DISABLED:	DB	"Disabled]", 13, 10, "$"

STR_MODE_120X40_LBL:	DB	"120x40 (Modern Default)]           ",13,10,"$"

STR_MODE_80X24_LBL:	DB	"80x24 (Classic Terminal)]          ",13,10,"$"

STR_CONFIG_TITLE_PAD:	DB	"             ", "$"
STR_CONFIG_TITLE:	DB	"SE - Screen Editor Configuration",13,10,"$"

STR_CONFIG_STATUS_LBL:	DB	"Config Status      : [", "$"

STR_CONFIG_CUR_MODE:	DB	"1. Screen Geometry : [", "$"
STR_CONFIG_RAM_DRV_PRE:	DB	"2. RAM Drive (", "$"
STR_CONFIG_RAM_DRV_POST:DB	":)  : [", "$"
STR_CONFIG_RAM_NONE:	DB	"2. RAM Drive       : [", "$"
STR_RAM_PROTECTED_LBL:	DB	"Preserve (RAM Drive Active, 128KB)]",13,10,"$"
STR_RAM_HIBERNATE_LBL:	DB	"Hibernate (Backup/Restore, 384KB)] ",13,10,"$"
STR_RAM_ENABLED_LBL:	DB	"Overwrite (Sacrifice Drive, 384KB)]",13,10,"$"

STR_CONFIG_LINES_LBL:	DB	"3. Max Doc Lines   : [", "$"
STR_LINES_16K_LBL:	DB	"16K (16,384 Lines)]                ",13,10,"$"
STR_LINES_32K_LBL:	DB	"32K (32,768 Lines)]                ",13,10,"$"

STR_CONFIG_TAB_LBL:	DB	"4. Tab Width       : [", "$"
STR_TAB_8_LBL:		DB	"8 Spaces (Default)]                ",13,10,"$"
STR_TAB_4_LBL:		DB	"4 Spaces]                          ",13,10,"$"
STR_CONFIG_PLUG_LBL:	DB	"5. Plugin Manager  : [", "$"
STR_PLUG_AUTO_LBL:	DB	"Autoload (Startup Load)]           ",13,10,"$"
STR_PLUG_ONDEMAND_LBL:	DB	"On Demand (Load When Used)]        ",13,10,"$"
STR_PLUG_DIS_LBL:	DB	"Disabled (Do Not Load)]            ",13,10,"$"
STR_PLUG_NO_FAR_LBL:	DB	"Disabled (No Far RAM)]             ",13,10,"$"


STR_CFG_STAT_NONE:	DB	"Default (No SE.CFG found)]         ",13,10,"$"
STR_CFG_STAT_LOCAL:	DB	"Loaded from local drive ($"
STR_CFG_STAT_PROG:	DB	"Loaded from program drive ($"
STR_CFG_STAT_SAVED:	DB	"Saved to local drive ($"
STR_CFG_STAT_END:	DB	":SE.CFG)]          ",13,10,"$"
STR_CFG_STAT_ERR:	DB	"ERROR writing SE.CFG]              ",13,10,"$"

STR_CMD_HEADER:		DB	"Commands:                                                   ",13,10,"$"
STR_CMD_1:		DB	"  type   1                toggle 80x24 <-> 120x40           ",13,10,"$"
STR_CMD_2:		DB	"  type   2                toggle RAM drive memory blocks    ",13,10,"$"
STR_CMD_3:		DB	"  type   3                toggle Max lines (16K <-> 32K)    ",13,10,"$"
STR_CMD_4:		DB	"  type   4                toggle Tab width (4 <-> 8)        ",13,10,"$"
STR_CMD_5:
	DB	"  type   5                "
	DB	"toggle Plugin Mgr (Auto/Demand/Dis)",13,10,"$"
STR_CMD_S:		DB	"  type   s                save config to local SE.CFG       ",13,10,"$"
STR_CMD_Q:		DB	"  type   q  or  <ESC>     return to splash screen           ",13,10,"$"

STR_CFG_HDR:		DB	"# SE.CFG - Screen Editor Configuration",13,10,0
STR_KEY_SCREEN_NAME:	DB	"SCREEN",0
STR_KEY_SCREEN_FULL:	DB	"SCREEN=",0
STR_VAL_120X40:		DB	"120x40",13,10,0
STR_VAL_80X24:		DB	"80x24",13,10,0
STR_KEY_RAMD_NAME:	DB	"RAMD",0
STR_KEY_RAMDRIVE_FULL:	DB	"RAMDRIVE=",0
STR_VAL_RAMDRIVE_OFF:	DB	"PRESERVE",13,10,0
STR_VAL_RAMDRIVE_ON:	DB	"OVERWRITE",13,10,0
STR_VAL_RAMDRIVE_HIB:	DB	"HIBERNATE",13,10,0
STR_KEY_TAB_NAME:	DB	"TAB",0
STR_KEY_TAB_FULL:	DB	"TAB=",0
STR_VAL_TAB_8:		DB	"8",13,10,0
STR_VAL_TAB_4:		DB	"4",13,10,0
STR_KEY_LINES_NAME:	DB	"LINE",0
STR_KEY_MAXLINES_NAME:	DB	"MAXLINE",0
STR_KEY_LINES_FULL:	DB	"LINES=",0
STR_VAL_LINES_16K:	DB	"16K",13,10,0
STR_VAL_LINES_32K:	DB	"32K",13,10,0
STR_KEY_PLUGIN_NAME:	DB	"PLUGIN",0
STR_KEY_PLUGIN_FULL:	DB	"PLUGIN=",0
STR_VAL_PLUG_AUTO:	DB	"AUTOLOAD",13,10,0
STR_VAL_PLUG_ONDEMAND:	DB	"ONDEMAND",13,10,0
STR_VAL_PLUG_DIS:	DB	"DISABLED",13,10,0


STR_RAMDRV_FILENAME:	DB	"RAMDRV  IMG"
STR_MSG_HIBERNATING:	DB	13,10,"[SE] Hibernating RAM drive ("
STR_MSG_HIB_LETTER:	DB	"A:) to RAMDRV.IMG... $"
STR_MSG_HIB_DONE:	DB	"[Done: 256 KB preserved]",13,10,"$"
STR_MSG_RESTORING:	DB	13,10,"[SE] Restoring RAM drive ("
STR_MSG_REST_LETTER:	DB	"A:) from RAMDRV.IMG... $"
STR_MSG_REST_DONE:	DB	"[Done: RAM drive ("
STR_MSG_REST_DONE_LTR:	DB	"A:) restored]",13,10,"$"
STR_MSG_ORPHAN_FOUND:
	DB	13,10,"[SE] Existing RAMDRV.IMG found! Restoring RAM drive ("
STR_MSG_ORPHAN_LETTER:	DB	"A:)... $"
STR_MSG_HIB_DRV_ERR:	DB	13,10,"[SE] Active drive is RAM drive ("
STR_MSG_HIB_DRV_CHAR:	DB	"A:). RAM drive protected.",13,10,"$"
STR_MSG_HIB_FILE_ERR:	DB	13,10,"[SE] Target file is on RAM drive ("
STR_MSG_HIB_FILE_CHAR:	DB	"A:). RAM drive protected.",13,10,"$"
STR_MSG_HIB_TOO_SMALL:
	DB	13,10,"[SE] Active drive has insufficient space (<256KB). "
	DB	"RAM drive protected.",13,10,"$"
STR_MSG_HIB_ERR:
	DB	13,10,"[Error] Hibernation failed. RAM drive protected."
	DB	13,10,"$"
STR_MSG_REST_ERR:	DB	13,10,"[Error] RAM drive restoration incomplete.",13,10,"$"

;------------------------------------------------------------------------------
; About Screen Strings
;------------------------------------------------------------------------------
STR_ABOUT_TITLE:	DB	"SE - Screen Editor", "$"
STR_ABOUT_VERSION:	DB	"version 0.9.8 (2026-09-25)", "$"
STR_ABOUT_AUTHOR:	DB	"by Dean Jenkins", "$"
STR_ABOUT_AI:		DB	"Google Antigravity 2.16.0 & Gemini FLASH 3.8 high", "$"
STR_ABOUT_LICENSE:	DB	"Open source software under the MIT License", "$"
STR_ABOUT_RETURN:	DB	"Press any key to return to splash...", "$"

;------------------------------------------------------------------------------
; Memory Information Screen Strings
;------------------------------------------------------------------------------
STR_MEM_TITLE_PAD:
	DB	"                      ","$"	; 22 spaces to center within 72 columns
STR_MEM_INFO_TITLE:
	DB	"SE.COM - Extended Memory Map",13,10,"$"
STR_MEM_INFO_BLANK:
	DB	"~",13,10,"$"
STR_MEM_TABLE_HDR:
	DB	"Bank  Phys   Size   System / OS Role        SE.COM Usage",13,10,"$"
STR_MEM_TABLE_DIV:
	DB	"----  ----   ----   ---------------------   ----------------------------",13,10,"$"
STR_MEM_PROMPT_PAD:
	DB	"              ","$"		; 14 spaces to center within 72 columns
STR_MEM_RETURN_PROMPT:
	DB	"Press any key to return to splash screen...",13,10,"$"

STR_MEM_SUM_PREFIX:	DB	"HBIOS: ","$"
STR_MEM_SUM_NONE:	DB	"None","$"
STR_MEM_SUM_ROMWBW:	DB	"RomWBW v","$"
STR_MEM_SUM_OS:		DB	" | OS: ","$"
STR_MEM_SUM_RAM:	DB	" | RAM: ","$"
STR_MEM_SUM_RAM_BASE:	DB	"64 KB Base","$"
STR_MEM_SUM_KB_MID:	DB	" KB (","$"
STR_MEM_SUM_X32K:	DB	"x32K)","$"
STR_MEM_SUM_SE:		DB	" | SE: ","$"
STR_MEM_SUM_KB_END:	DB	" KB",13,10,"$"
STR_MEM_SUM_64K_END:	DB	"64 KB",13,10,"$"

STR_OS_ZSYS:		DB	"Z-System","$"
STR_OS_CPM31:		DB	"CP/M 3.1","$"
STR_OS_CPM30:		DB	"CP/M 3.0","$"
STR_OS_CPM22:		DB	"CP/M 2.2","$"

STR_ROLE_HBIOS:		DB	"HBIOS System Firmware","$"
STR_ROLE_RAMDISK:	DB	"RAM Disk (MD0:)      ","$"
STR_ROLE_APP:		DB	"Application Memory   ","$"
STR_ROLE_TPA_CPM2:	DB	"CP/M 2.2 TPA & Base  ","$"
STR_ROLE_TPA_CPM3:	DB	"CP/M 3.1 TPA & Base  ","$"
STR_ROLE_TPA_ZSYS:	DB	"Z-System TPA & Base  ","$"
STR_ROLE_OS:		DB	"Operating System Bank","$"
STR_ROLE_NOT_INST:	DB	"Not Installed        ","$"

STR_USAGE_HBIOS:	DB	"Reserved: Protected HBIOS   ","$"
STR_USAGE_RAMDISK_PRESERVED:
			DB	"Preserved: RAM Disk Active  ","$"
STR_USAGE_SE_PROG:	DB	"Active: SE Program & Cache  ","$"
STR_USAGE_LINE_TABLE:	DB	"Active: 16K Line Slot Table ","$"
STR_USAGE_LINE_TABLE_0:	DB	"Active: Line Slots (0..16K) ","$"
STR_USAGE_LINE_TABLE_1:	DB	"Active: Line Slots (16K..32K)","$"
STR_USAGE_PLUGIN_MGR:	DB	"Active: PLUGIN.PRL Subsystem","$"
STR_USAGE_DOC_PFX:	DB	"Active: Doc Buffer Bank ","$"
STR_USAGE_DOC_SFX:	DB	"  ","$"
STR_USAGE_OS:		DB	"Reserved: Operating System  ","$"
STR_USAGE_CPM3_BUFS:	DB	"Reserved: CP/M 3 Buffers    ","$"
STR_USAGE_FREE:		DB	"Free / Unallocated          ","$"
STR_USAGE_NOT_PRES:	DB	"Not Present                 ","$"

STR_MEM_SIZE_32K:	DB	"32K ","$"
STR_MEM_SIZE_NONE:	DB	" -- ","$"
STR_MEM_SIZE_64K:	DB	"64K ","$"
STR_MEM_SPACES_4:	DB	"    ","$"
STR_MEM_SPACES_3:	DB	"   ","$"
STR_MEM_SPACES_2:	DB	"  ","$"
STR_MEM_ROW_PREFIX:	DB	"~   ","$"


STR_STATUS_PREFIX:	DB	" SE v0.9.8 | ","$"

STR_STATUS_120X40:	DB	"120x40 | ","$"

STR_STATUS_80X24:	DB	" 80x24 | ","$"

STR_FMT_CPM:	DB	"CP/M  | ","$"

STR_FMT_LINUX:	DB	"Linux | ","$"

STR_STATUS_KEYS:	DB	"^K: Editor keys | ","$"
STR_STATUS_OVR:		DB	"Overwrite mode  | ","$"
STR_STATUS_LOADING:	DB	"Loading...      | ","$"
STR_STATUS_SAVING:	DB	"Saving...       | ","$"
STR_PAN_PREFIX:		DB	"[Pan +","$"

STR_STATUS_OOM:		DB	"Out of memory   | ","$"

STR_TRUNC_SAVE_BLOCKED:
	DB	"~",13,10
	DB	"~  =============================================================",13,10
	DB	"~                 ERROR: SAVE DISABLED (PROTECTION)             ",13,10
	DB	"~  =============================================================",13,10
	DB	"~  This file was truncated upon loading because it exceeds the  ",13,10
	DB	"~  editor's current RAM capacity.                               ",13,10
	DB	"~",13,10
	DB	"~  Saving has been blocked to protect the unread portion of the ",13,10
	DB	"~  file from being overwritten and permanently lost on disk.    ",13,10
	DB	"~",13,10
	DB	"~  Press any key to return to the editor...                     ",13,10
	DB	"~  =============================================================",13,10,"$"

STR_STATUS_FREE:	DB	"Free: ","$"

STR_STATUS_KB:		DB	" KB","$"

STR_SEL_PREFIX:	DB	"[SEL: ","$"

STR_BLK_PREFIX:	DB	"[BLK: ","$"

STR_CHAR_SUFFIX:	DB	"c]","$"

STR_LINE_SUFFIX:	DB	"L]","$"

STR_CHAR_LOCK_SUFFIX:	DB	"c LOCK]","$"

STR_LINE_LOCK_SUFFIX:	DB	"L LOCK]","$"

STR_HELP_TITLE:		DB	"SE.COM - EDITOR MODE KEYS",13,10,"$"

STR_HELP_BODY:
	DB	"~  FILE & SYSTEM:",13,10
	DB	"~    Ctrl+O           Open file screen        Ctrl+S          Save file screen",13,10
	DB	"~    Ctrl+W           Close file to splash    Ctrl+Q          Quit to CP/M",13,10
	DB	"~    Ctrl+K           Help / Solidify block   Ctrl+P          Plugins pop-up",13,10
	DB	"~  NAVIGATION & SEARCH:",13,10
	DB	"~    Arrow Keys       Move Up/Down/Left/Right Ctrl+A / Home   Start of line",13,10
	DB	"~    Ctrl+U / PgUp    Page Up                 Ctrl+E / End    End of line",13,10
	DB	"~    Ctrl+V / PgDn    Page Down               Ctrl+T / ^Home  Top of file",13,10
	DB	"~    Ctrl+L           Goto line number        Ctrl+G / ^End   Bottom of file",13,10
	DB	"~    Ctrl+F           Find text               Ctrl+N          Find next",13,10
	DB	"~    Ctrl+R           Search and Replace      Ctrl+I / Tab    Toggle find case",13,10
	DB	"~  EDITING & BLOCK:",13,10
	DB	"~    Insert           Toggle Insert/Overwrite Enter           New line",13,10
	DB	"~    ASCII 32..126    Insert/Overwrite text   Backspace       Delete left / join",13,10
	DB	"~    Delete / Ctrl+D  Delete char or block    Ctrl+B          Start/Toggle block",13,10
	DB	"~    Ctrl+C           Copy solidified block   Ctrl+K          Solidify block",13,10
	DB	"~    Ctrl+X           Move solidified block   ESC             Clear block",13,10,"$"

STR_HELP_RETURN_PROMPT:	DB	"Press any key to return to editor...",13,10,"$"

STR_STATUS_SEP:	DB	" | ","$"

STR_NO_NAME:	DB	"(Untitled)",0

STR_STATUS_POS:	DB	"Line ","$"

STR_STATUS_COL:	DB	" Col ","$"

MSG_EXIT:	DB	13,10,"Exiting SE.COM. Returned to CP/M.",13,10,"$"

STR_TITLE_OPEN_PRE:	DB	"SE.COM - OPEN FILE (DIRECTORY - DRIVE ","$"
STR_DIR_DRIVE_CHAR:	DB	"A"
STR_TITLE_SAVE_PRE:	DB	"SE.COM - SAVE FILE (DIRECTORY - DRIVE ","$"
STR_SAVE_DRIVE_CHAR:	DB	"A"
STR_TITLE_BLOCK_SAVE_PRE: DB	"SE.COM - SAVE BLOCK (DIRECTORY - DRIVE ","$"
STR_TITLE_DRIVE_SUF:	DB	":)",13,10,"$"
STR_TITLE_FILTER_PRE:	DB	": [","$"
STR_TITLE_FILTER_SUF:	DB	"])",13,10,"$"

STR_OPEN_PROMPT_TXT:	DB	"Enter filename to open:","$"
STR_TITLE_INSERT_PRE:	DB	"SE.COM - INSERT FILE (DIRECTORY - DRIVE ","$"
STR_INSERT_PROMPT_TXT:	DB	"Enter filename to insert:","$"
STR_TITLE_PLUG_LOAD_PRE: DB	"SE.COM - LOAD PLUGIN (DIRECTORY - DRIVE ","$"
STR_PLUG_LOAD_PROMPT_TXT: DB	"Load Plugin (.PRL/.OVL):","$"

STR_PAGE_PREFIX:	DB	"~  [Page ","$"

STR_PAGE_MID:		DB	"/","$"

STR_PAGE_SUFFIX:	DB	"]  <PgUp>/<PgDn>=Page",13,10,"$"

STR_NO_FILES_FOUND:	DB	"~  [No files found on current drive]",13,10
			DB	"~",13,10,"$"

DEFAULT_FCB_NAME:	DB	0,"OUTPUT  TXT",0,0,0,0

STR_SAVE_FMT_PREFIX:	DB	"~  Format: [","$"

STR_SAVE_FMT_CPM:	DB	"CP/M","$"

STR_SAVE_FMT_LINUX:	DB	"Linux","$"

STR_SAVE_FMT_SUFFIX:	DB	"]  (^F: toggle format)",13,10,"$"

STR_SAVE_PROMPT_TXT:	DB	"Enter filename to save:","$"

STR_ESC_CANCEL:		DB	"~  <ESC>=Cancel  Enter [d:][u:][pattern] to list (e.g. B:, C1:, 1C:, *.TXT)",13,10,"$"

STR_OVERWRITE_WARN:	DB	13,10,"~  File already exists. Overwrite? (",27,"[4m","Y",27,"[24m","es/",27,"[4m","N",27,"[24m","o): ","$"

STR_SAVE_CANCELLED:	DB	13,10,"~  Save cancelled.",13,10,"$"

STR_TILDE_INDENT:	DB	"~  ","$"
STR_TILDE_CRLF:		DB	"~",13,10,"$"

STR_FILE_NOT_FOUND:	DB	13,10,"File not found.",13,10,"$"
STR_FILE_NOT_FOUND_SUFFIX:	DB	" file not found",13,10,"$"

STR_CSI_C:		DB	27,"[C","$"
STR_FNF_INLINE:		DB	"  File not found","$"
STR_RAMDRV_UNAVAIL_INLINE:	DB	"  RAM drive not available","$"
STR_FAT_NO_PLUGIN_INLINE:	DB	"  feature requires FATFS.PRL","$"
STR_GOTO_LINE_PROMPT:	DB	"Goto line:","$"
STR_GOTO_LINE_BOX:	DB	" [     ]","$"
STR_BS_6:		DB	8,8,8,8,8,8,"$"
STR_REPLACE_CONFIRM:	DB	"Replace (",27,"[4m","Y",27,"[24m","es/",27,"[4m","N",27,"[24m","o/",27,"[4m","A",27,"[24m","ll/",27,"[4m","Q",27,"[24m","uit/",27,"[4m","R",27,"[24m","everse)? ","$"
STR_SAVE_CHANGES_PROMPT:DB	"Save changes? ",27,"[4m","Y",27,"[24m","es/",27,"[4m","N",27,"[24m","o/ESC:","$"
STR_PATTERN_NOT_FOUND:	DB	" Pattern not found. ","$"
STR_SEARCH_COMPLETED:	DB	" Search completed. ","$"
STR_REPLACE_DONE_PFX:	DB	" Replace done: ","$"
STR_REPLACE_DONE_SFX:	DB	" replacement(s). ","$"
STR_LINE_TOO_LONG:	DB	" Line > 120 chars - skipped. ","$"

;------------------------------------------------------------------------------
; Variables & Stack Area
;------------------------------------------------------------------------------
SAVED_SP:	DW	0
SHOWING_FNF_MSG:	DB	0		; 1 if "  File not found" inline message is visible
UI_CUR_ROW:	DB	0		; Current screen row tracking for Open/Save UI
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
VIEW_LEFT_COL:	DW	0		; Horizontal viewport left column offset (0..1000)
VIEW_RIGHT_COL:	DW	120		; Cached right column bound (VIEW_LEFT_COL + ACTIVE_COLS)

; Screen cursor coordinates use "row" (0..ACTIVE_ROWS-2) internally for terminal
; positioning (LOCATE_CURSOR: Screen Row = CUR_DOC_ROW - TOP_DOC_ROW + 1).
; Document line indices in buffer/file use "line" (0..DOC_TOTAL_LINES-1) and are
; rendered on the status line as "Line <cur>/<total>".
CUR_DOC_ROW:	DW	0		; 16-bit document line index (0..3583)
CUR_COL:	DW	0		; 16-bit character byte index in line (0..1000)
TARGET_COL:	DW	0		; Sticky visual column (0..1000)
TOP_DOC_ROW:	DW	0		; 16-bit top visible document line on screen
DOC_TOTAL_LINES:	DW	1		; 16-bit total document lines count (default 1 empty line)
HAS_FILE_ARG:	DB	0
CMDLINE_HAS_DRIVE:	DB	0
CMDLINE_GOTO_LINE:	DW	0		; 16-bit line number from command line (0 = start)
OPEN_GOTO_LINE:		DW	0		; 16-bit line number from open file UI (0 = start)
GOTO_LINE_BUF:	DS	8
SEARCH_BUF:		DS	65
SEARCH_LEN:		DB	0
SEARCH_CASE_SENSITIVE:	DB	1		; Default 1 = Exact (case-sensitive)
SEARCH_EVER_FOUND:	DB	0		; 1 if pattern was ever found during session
SEARCH_DIRECTION:	DB	0		; 0 = Forward, 1 = Backward
REPLACE_MATCH_COL:	DW	0		; Saved column during interactive replace
PREV_START_ROW_TEMP:	DW	0		; Saved row before Find Next/Prev
PREV_START_COL_TEMP:	DW	0		; Saved col before Find Next/Prev
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
FILE_IS_TRUNCATED:	DB	0		; 1 if file was truncated on load (Save protected)
FILE_TOTAL_RECORDS:	DW	0		; Total 128-byte records computed by BDOS 35
FILE_RECORDS_HI:	DB	0		; High byte of 24-bit record count
SAVE_FORMAT:	DB	FMT_CPM		; Default format is CP/M (CR/LF)
IS_SAVE_UI:		DB	0		; 1 if currently in Save File Screen
IS_BLOCK_INSERT_UI:	DB	0		; 1 if currently in Block Insert File Screen
IS_BLOCK_SAVE_UI:	DB	0		; 1 if currently in Block Save File Screen
IS_PLUGIN_LOAD_UI:	DB	0	; 1 if in Plugin Load Screen
IS_LOADING_FILE:	DB	0		; 1 if currently loading file
IS_SAVING_FILE:		DB	0		; 1 if currently saving file
LOAD_PROGRESS_COUNT:	DB	100		; Progress interval down-counter (100 lines)
LOAD_PROGRESS_LINES:	DW	0		; Lines read counter for loading status bar
SAVED_HAS_FILE_ARG:	DB	0		; Saved HAS_FILE_ARG during block insert
INSERT_LINE_HAD_CHARS:	DB	0		; 1 if current line of inserted file had chars
IS_EXIT_PROMPT:		DB	0		; 1 if currently in Save Changes Exit Prompt
IS_REPLACE_PROMPT:	DB	0		; 1 if currently in Search & Replace prompt
INSERT_FCB:		DS	36		; Dedicated FCB for block insert file
INSERT_CUR_LEN:		DW	0		; Streaming insert current line length
INSERT_NEW_CUR_COL:	DW	0		; Cursor column position after insert
INSERT_IS_FIRST_LINE:	DB	0		; 1 while processing line 1 of inserted file
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
BLOCK_ACTIVE:	DB	0		; 0 = inactive, 1 = selecting, 2 = solidified
BLOCK_ANCHOR_ROW:	DW	0		; 16-bit document row where block started
BLOCK_ANCHOR_COL:	DW	0		; 16-bit character column where block started
BLOCK_START_ROW:	DW	0		; Normalized start row
BLOCK_START_COL:	DW	0		; Normalized start col
BLOCK_END_ROW:	DW	0		; Normalized end row
BLOCK_END_COL:	DW	0		; Normalized end col

LINE_BLK_ACTIVE:	DB	0		; 1 if rendered line is in block
LINE_BLK_START:	DW	0		; Start character column of highlight on line
LINE_BLK_END:	DW	0		; End character column of highlight on line
LINE_IN_INVERSE:	DB	0		; 1 if terminal currently has inverse video ON

NEED_SCREEN_RENDER:	DB	0	; 1 if full screen redraw pending
NEED_LINE_RENDER:	DB	0	; 1 if current line redraw pending
NEED_STATUS_RENDER:	DB	0	; 1 if status bar redraw / cursor restore pending
INSERT_MODE:		DB	1	; 1 = Insert mode (default), 0 = Overwrite mode

CACHE_START_ROW:	DW	0		; 16-bit doc row index at LINE_STORAGE[0]
CACHE_DIRTY:	DB	0		; 1 if local cache has unsaved modifications
CACHE_LINE_DIRTY:	DS	CACHE_SIZE_LINES ; 1 byte per local cache line (0=clean, 1=dirty)
DOC_MODIFIED:	DB	0		; 1 if document has unsaved modifications
CONFIRM_ACTION:	DB	0		; 0=Exit, 1=Close, 2=New
EXT_BANK_COUNT:	DB	0		; Number of available far RAM banks (up to 14)
EXT_BANK_TABLE:	DS	14		; Table of far RAM bank IDs
LINE_TABLE_BANK:	DB	0		; Far RAM Bank dedicated to 16K line slots table (Bank 0)
LINE_TABLE_BANK_1:	DB	0		; Far RAM Bank dedicated to 16K..32K line slots table (Bank 1)
CFG_LINES_MODE:		DB	0		; 0 = 16K lines (default), 1 = 32K lines
MAX_DOC_LINES_LIMIT:	DW	MAX_DOC_LINES_16K ; Dynamic max document lines (16384 or 32768)
LINE_SLOT_TEMP:		DW	0		; 2-byte transfer buffer for GET/SET_LINE_SLOT
SLOT_SHIFT_SRC:		DW	0		; Far RAM source line for block slot shifts
SLOT_SHIFT_DEST:	DW	0		; Far RAM dest line for block slot shifts
SLOT_SHIFT_REM:		DW	0		; Remaining lines to shift
SLOT_SHIFT_CHUNK:	DW	0		; Current chunk size in lines (up to 128)
SLOT_SHIFT_BYTES:	DW	0		; Current chunk size in bytes (up to 256)
WLSR_K:			DW	0		; Temporary K for WRITE_LINE_SLOTS_FROM_RAM
WLSR_SRC:		DW	0		; Temporary Source for WRITE_LINE_SLOTS_FROM_RAM
WLSR_DEST:		DW	0		; Temporary Dest for WRITE_LINE_SLOTS_FROM_RAM

FAR_DEST_BANK:	DB	0
FAR_SRC_BANK:	DB	0
FAR_DEST_ADDR:	DW	0
FAR_SRC_ADDR:	DW	0
FAR_LOCAL_ADDR:	DW	0
SLOT_TEMP:	DB	0
NEXT_FRESH_SLOT:	DW	0
FIRST_FREE_SLOT:	DW	0FFFFH
DEC_WORD_BUF:	DS	6		; Buffer for PRINT_DEC_WORD (5 digits + null)

SWAP_ACTIVE:		DB	0		; 1 if $$$SE$$$.SWP is active, 0 if RAM-only
SWAP_FCB:		DS	36		; FCB for temporary swap file
BANK_PAGE_TABLE:	DS	12		; Virtual page number (0..255) resident in Bank 0..11
BANK_DIRTY_TABLE:	DS	12		; 1 if bank has unsaved modifications, 0 if clean
NEXT_VICTIM_BANK:	DB	1		; Round-robin victim pointer (1..11; Bank 0 is pinned)
PAGE_ON_DISK_BITMAP:	DS	32		; 256 bits: 1 bit per page (1 if written to swap)
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


ACTIVE_LINE_ROW:	DW	0FFFFH		; Document row checked out in ACTIVE_LINE_BUF
ACTIVE_LINE_DIRTY:	DB	0		; 1 if ACTIVE_LINE_BUF has unsaved modifications
REND_LINE_PTR:		DW	0
REND_VIS_COL:		DW	0
REND_CHAR_IDX:		DW	0
REND_TAB_SPACES:	DB	0
ACT_VIS_ACC:		DW	0

FAR_IO_BUF:		DS	128		; 128-byte scratch buffer for physical Far RAM transfers
LOAD_LINE_TEMP:		DS	256		; 256-byte scratch line for local operations
SPLIT_LINE_TEMP:	DS	1024		; 1024-byte scratch line for line splits
ACTIVE_LINE_LEN:	DW	0		; 16-bit byte length of line in ACTIVE_LINE_BUF
ACTIVE_LINE_BUF:	DS	1024		; 1024-byte dynamic workspace for active line
CUR_DMA_PTR:	DW	0
DMA_BYTES_LEFT:	DB	0


WORK_FCB:	DS	36
DIR_TEMP_FCB:	DS	36

CURRENT_DIR_DRIVE:	DB	0		; Active directory drive (1=A:, 2=B:, 3=C:, etc.)
CURRENT_DIR_USER:	DB	0		; Active directory user area (0..15)
ORIG_CPM_USER:		DB	0		; CP/M user area on entry (0..15)
DOC_USER_NUM:		DB	0		; User area for currently loaded document (0..15)
WORK_FCB_USER:		DB	0		; User area for pending WORK_FCB operation (0..15)
BLOCK_IO_USER:		DB	0		; User area for Block Insert / Block Save (0..15)
PREFIX_DRIVE:		DB	0		; Parsed prefix drive (1..16 or 0)
PREFIX_USER:		DB	0FFH		; Parsed prefix user (0..15 or 0xFF)
; Consolidated transient CP/M File Control Block (36 bytes)
; Shared across sequential operations: dir search, raw disk, config, ramdrv
SHARED_TEMP_FCB:	DS	36
DIR_SEARCH_FCB		EQU	SHARED_TEMP_FCB
RAW_TEST_FCB		EQU	SHARED_TEMP_FCB
CFG_FCB			EQU	SHARED_TEMP_FCB
COM_PROBE_FCB		EQU	SHARED_TEMP_FCB
RAMDRV_FCB		EQU	SHARED_TEMP_FCB
DIR_FILE_COUNT:	DB	0
DIR_PAGE_INDEX:	DB	0
DIR_PAGE_COUNT:	DB	0
DIR_START_FILE:	DB	0
DIR_COL_COUNT:		DB	0
DIR_COLS_PER_ROW:	DB	5
DIR_COL_WIDTH:		DB	15
DIR_PAGE_CAPACITY:	DB	60
DIR_TEMP_ENTRY:		DS	16
INPUT_BUF_LEN:		DB	0
INPUT_CURSOR_POS:	DB	0
INPUT_CHAR_TEMP:	DB	0
INLINE_MSG_LEN:		DB	16
INPUT_FILENAME_BUF:	DS	32
DIR_FILTER_FCB:		DB	"???????????"	; 11-byte FCB wildcard pattern (8 name + 3 ext)
DIR_FILTER_STR:		DB	"*.*",0,0,0,0,0,0,0,0,0 ; Display string for active filter (null-terminated)
DIR_FILTER_ACTIVE:	DB	0		; 0 = *.* (all files), 1 = custom filter active

; Transient FCBs and buffers moved to SHARED_TEMP_FCB and LINE_STORAGE
CURRENT_DEFAULT_DRIVE:	DB	0		; Active CP/M default drive (0=A, 1=B, etc.)
CONFIG_SOURCE_DRIVE:	DB	0FFH		; Drive where config was loaded from (0xFF = none)
CONFIG_STATUS_FLAG:	DB	0		; 0=none/default, 1=loaded local, 2=loaded program, 3=saved local, 4=save error
SCS_TOP_PAD_COUNT:	DB	0		; Number of top padding rows on config screen
SPLASH_TOP_PAD_COUNT:	DB	0		; Number of top padding rows on splash screen
MEM_TOP_PAD_COUNT:	DB	0		; Number of top padding rows on memory screen
ABOUT_TOP_PAD_COUNT:	DB	0		; Number of top padding rows on about screen
CFG_RAMDRIVE_FLAG:	DB	0		; 0=protected, 1=enabled, 2=hibernate
CFG_TAB_WIDTH:		DB	8		; Tab width: 4 or 8 (default 8)
CFG_TAB_MASK:		DB	7		; Tab mask: 3 or 7 (default 7)
RAMDRIVE_IS_HIBERNATED:	DB	0		; 0=not hibernated, 1=hibernated to RAMDRV.IMG
RAMDRIVE_DRIVE_NUM:	DB	0FFH		; Detected RomWBW RAM drive (0=A, 1=B, ..., 0xFF=none)
RAMDRIVE_DRIVE_CHAR:	DB	'?'		; Character representation ('A', 'B', etc. or '?')
HIB_CUR_BANK:		DB	0		; Current bank being dumped/restored (0x81..0x88)
HIB_FAR_OFFSET:		DW	0		; Current Far RAM offset (0x0000..0x7F80)
CPM3_BIOSPB:
CPM3_BIOSPB_FUNC:	DB	0
CPM3_BIOSPB_A:		DB	0
CPM3_BIOSPB_BC:		DW	0
CPM3_BIOSPB_DE:		DW	0
CPM3_BIOSPB_HL:		DW	0
CPM3_DRVTBL_PTR:	DW	0
CPM3_SYS_BANK:		DB	0
CPM3_DPH_BUF:		DB	0,0

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
ALLOC_TEMP_BANK:	DB	0
IRF_TARGET_BANK:	DB	0
IRF_CAND_EC:		DB	0
PAYLOAD_SECTORS_REMAIN:	DW	0
EP_TPA_FAR_BANK:	DB	0
PLUGIN_FAR_BANK:	DB	0
PLUGIN_LOAD_COUNT:	DB	0
PLUGIN_CUR_SLOT:	DB	0
PLUGIN_ACTION_INDEX:	DB	0
PLUGIN_IS_FAR_EXEC:	DB	0
PLUGIN_RET_CODE:	DB	0
PLUGIN_STATUS_MSG_PTR:	DW	0
PLUGIN_STATUS_MSG_BUF:	DS	16
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
CURRENT_DIR_FAT_UNIT:	DB	0FFH		; FAT browsing unit (0..7, 0xFF=default)
CURRENT_DIR_FAT_PATH:	DS	64		; Active directory path (e.g. "/")
BLOCK_INSERT_IS_FAT:	DB	0		; 1 during FAT block insertion
FAT_INSERT_PATH:	DS	64		; Buffer for block insertion path
CMDLINE_IS_FAT:		DB	0		; 1 if startup argument was FAT file
CMDLINE_FAT_UNIT:	DB	0FFH		; Unit from command line argument
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
FAT_CHUNK_BUF:		DS	128		; FAT stream buffer (Common RAM)

;==============================================================================
; Upper Memory Host API Trampoline & Vector Table
; Physically situated in Upper 32KB (> 8000h) so it is resident across all banks.
;==============================================================================
ALIGN 4
PLUGIN_HOST_API:
	DB	"SE"			; +0:  Magic
	DW	0098H			; +2:  Host version (v0.9.8)
	DW	ACTIVE_LINE_BUF		; +4:  Pointer to ACTIVE_LINE_BUF
	DW	ACTIVE_LINE_LEN		; +6:  Pointer to ACTIVE_LINE_LEN
	DW	CUR_DOC_ROW		; +8:  Pointer to CUR_DOC_ROW
	DW	DOC_TOTAL_LINES		; +10: Pointer to DOC_TOTAL_LINES
	DW	CUR_COL			; +12: Pointer to CUR_COL
HOST_API_COLS:
	DB	80			; +14: Screen cols (80 or 120)
HOST_API_CONTEXT:
	DB	0			; +15: Screen Context ID (0..6)
HOST_API_ROWS:
	DB	24			; +16: Screen rows (24 or 40)
HOST_API_MGR_SLOT:
	DB	0FFH			; +17: Plugin Manager Slot (0..7 or 0xFF)
	JP	TRAMP_CHECKOUT_LINE	; +18: Call HOST_CHECKOUT_LINE
	JP	TRAMP_COMMIT_LINE	; +21: Call HOST_COMMIT_LINE
	JP	TRAMP_PUTC		; +24: Call PUTC
	JP	TRAMP_PRINT_STR		; +27: Call PRINT_STR
	JP	TRAMP_GET_KEY		; +30: Call GET_KEY
	JP	TRAMP_SET_STATUS_MSG	; +33: Call SET_STATUS_MSG
	DW	BLOCK_ACTIVE		; +36: Pointer to BLOCK_ACTIVE
	DW	BLOCK_START_ROW		; +38: Pointer to BLOCK_START_ROW
	DW	BLOCK_END_ROW		; +40: Pointer to BLOCK_END_ROW
	DW	CFG_TAB_WIDTH		; +42: Pointer to CFG_TAB_WIDTH
	DW	PLUGIN_REGISTRY		; +44: Pointer to PLUGIN_REGISTRY (256 bytes)
	JP	TRAMP_CHECK_KEY		; +46: Call CHECK_KEY_READY
	JP	TRAMP_CLEAR_DOCUMENT	; +49: Call HOST_CLEAR_DOCUMENT
	JP	TRAMP_LOCATE_RC		; +52: Call LOCATE_RC (H=Row, L=Col)
	JP	TRAMP_LOAD_PLUGIN	; +55: Call LOAD_PLUGIN_BY_NAME (DE=filename)
	JP	TRAMP_UNLOAD_SLOT	; +58: Call UNLOAD_PLUGIN_SLOT (A=slot 0..7)
	JP	TRAMP_REDRAW_BASE	; +61: Call REDRAW_BASE_SCREEN (A=context 0..6)
	JP	TRAMP_OPEN_PLUGIN_UI	; +64: Call DO_OPEN_FILE_UI (plugin mode)
	JP	TRAMP_SAVE_PLUGIN_CFG	; +67: Call HOST_SAVE_PLUGIN_CFG
	JP	TRAMP_LOAD_PLUGIN_CFG	; +70: Call HOST_LOAD_PLUGIN_CFG
	JP	TRAMP_RENDER_STATUS_BAR	; +73: Call RENDER_STATUS_BAR

TRAMP_CHECKOUT_LINE:
	LD	A,(PLUGIN_IS_FAR_EXEC)
	OR	A
	JP	Z,HOST_CHECKOUT_LINE
	PUSH	AF
	LD	A,(CPM_USER_BANK)
	CALL	0FFF3H
	CALL	HOST_CHECKOUT_LINE
	LD	A,(PLUGIN_FAR_BANK)
	CALL	0FFF3H
	POP	AF
	RET

TRAMP_COMMIT_LINE:
	LD	A,(PLUGIN_IS_FAR_EXEC)
	OR	A
	JP	Z,HOST_COMMIT_LINE
	PUSH	AF
	LD	A,(CPM_USER_BANK)
	CALL	0FFF3H
	CALL	HOST_COMMIT_LINE
	LD	A,(PLUGIN_FAR_BANK)
	CALL	0FFF3H
	POP	AF
	RET

TRAMP_PUTC:
	PUSH	AF
	LD	A,(PLUGIN_IS_FAR_EXEC)
	OR	A
	JR	Z,TPC_DIRECT
	LD	A,(CPM_USER_BANK)
	CALL	0FFF3H
	EI
	POP	AF
	PUSH	AF
	CALL	PUTC
	DI
	LD	A,(PLUGIN_FAR_BANK)
	CALL	0FFF3H
	POP	AF
	RET
TPC_DIRECT:
	POP	AF
	JP	PUTC

TRAMP_PRINT_STR:
	LD	A,(PLUGIN_IS_FAR_EXEC)
	OR	A
	JP	Z,PRINT_STR
	PUSH	BC
	PUSH	DE
	PUSH	HL
	EX	DE,HL			; HL = pointer in Far RAM
TPS_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,TPS_DONE
	CP	'$'
	JR	Z,TPS_DONE
	PUSH	HL
	CALL	TRAMP_PUTC
	POP	HL
	INC	HL
	JR	TPS_LOOP
TPS_DONE:
	POP	HL
	POP	DE
	POP	BC
	RET

TRAMP_GET_KEY:
	LD	A,(PLUGIN_IS_FAR_EXEC)
	OR	A
	JP	Z,GET_KEY
	LD	HL,GET_KEY
	JP	TRAMP_FAR_CALL

TRAMP_SET_STATUS_MSG:
	JP	HOST_SET_STATUS_MSG

TRAMP_CHECK_KEY:
	LD	A,(PLUGIN_IS_FAR_EXEC)
	OR	A
	JP	Z,CHECK_KEY_READY
	LD	HL,CHECK_KEY_READY
	JP	TRAMP_FAR_CALL

TRAMP_CLEAR_DOCUMENT:
	LD	A,(PLUGIN_IS_FAR_EXEC)
	OR	A
	JP	Z,HOST_CLEAR_DOCUMENT
	LD	HL,HOST_CLEAR_DOCUMENT
	JP	TRAMP_FAR_CALL

TRAMP_LOCATE_RC:
	LD	A,(PLUGIN_IS_FAR_EXEC)
	OR	A
	JP	Z,LOCATE_RC
	PUSH	AF
	LD	A,(CPM_USER_BANK)
	CALL	0FFF3H
	EI
	CALL	LOCATE_RC
	DI
	LD	A,(PLUGIN_FAR_BANK)
	CALL	0FFF3H
	POP	AF
	RET

TRAMP_LOAD_PLUGIN:
	; Input: DE = pointer to null-terminated ASCII filename
	; Returns: Carry=0 on success, A=slot number; Carry=1 on error
	LD	A,(PLUGIN_IS_FAR_EXEC)
	OR	A
	JP	Z,LOAD_PLUGIN_BY_NAME
	PUSH	BC
	PUSH	HL
	LD	HL,TRAMP_NAME_BUF
	LD	B,15			; Bound filename to 15 chars + null
TLP_CPY:
	LD	A,(DE)
	OR	A
	JR	Z,TLP_CPY_DONE
	LD	(HL),A
	INC	DE
	INC	HL
	DJNZ	TLP_CPY
TLP_CPY_DONE:
	XOR	A
	LD	(HL),A			; Guarantee null terminator
	POP	HL
	POP	BC
	LD	HL,HOST_LOAD_PLUGIN_FAR
	JR	TRAMP_FAR_CALL

HOST_LOAD_PLUGIN_FAR:
	LD	DE,TRAMP_NAME_BUF
	JP	LOAD_PLUGIN_BY_NAME

TRAMP_UNLOAD_SLOT:
	; Input: A = slot number (0..7)
	LD	C,A
	LD	A,(PLUGIN_IS_FAR_EXEC)
	OR	A
	JR	Z,TUS_DIRECT
	LD	A,C
	LD	HL,UNLOAD_PLUGIN_SLOT
	JR	TRAMP_FAR_CALL
TUS_DIRECT:
	LD	A,C
	JP	UNLOAD_PLUGIN_SLOT

TRAMP_REDRAW_BASE:
	; Input: A = Context ID (0..6)
	LD	C,A
	LD	A,(PLUGIN_IS_FAR_EXEC)
	OR	A
	JR	Z,TRB_DIRECT
	LD	A,C
	LD	HL,HOST_REDRAW_BASE_FAR
	JR	TRAMP_FAR_CALL
TRB_DIRECT:
	LD	(POPUP_CONTEXT_ID),A
	JP	REDRAW_BASE_SCREEN

HOST_REDRAW_BASE_FAR:
	LD	(POPUP_CONTEXT_ID),A
	JP	REDRAW_BASE_SCREEN

TRAMP_OPEN_PLUGIN_UI:
	; Interactive file selector for plugin files (.PRL/.OVL)
	; Returns Carry=0, A=slot on success; Carry=1 on cancel
	LD	A,(PLUGIN_IS_FAR_EXEC)
	OR	A
	JR	Z,TOPU_DIRECT
	LD	HL,HOST_OPEN_PLUGIN_UI_FAR
	JR	TRAMP_FAR_CALL
TOPU_DIRECT:
	LD	A,1
	LD	(IS_PLUGIN_LOAD_UI),A
	JP	DO_OPEN_FILE_UI

HOST_OPEN_PLUGIN_UI_FAR:
	LD	A,1
	LD	(IS_PLUGIN_LOAD_UI),A
	JP	DO_OPEN_FILE_UI

TRAMP_SAVE_PLUGIN_CFG:
	; Input: DE = pointer to 128-byte buffer
	LD	HL,CFG_IO_BUF
	EX	DE,HL			; HL = user buffer, DE = CFG_IO_BUF
	LD	BC,128
	LDIR
	LD	HL,HOST_SAVE_PLUGIN_CFG_DISK
	JR	TRAMP_FAR_CALL

TRAMP_LOAD_PLUGIN_CFG:
	; Input: DE = pointer to 128-byte buffer
	PUSH	DE			; Preserve destination
	LD	HL,HOST_LOAD_PLUGIN_CFG_DISK
	CALL	TRAMP_FAR_CALL
	POP	DE
	RET	C			; On read error, return Carry = 1
	LD	HL,CFG_IO_BUF
	LD	BC,128
	LDIR
	OR	A
	RET

TRAMP_RENDER_STATUS_BAR:
	LD	A,(PLUGIN_IS_FAR_EXEC)
	OR	A
	JP	Z,RENDER_STATUS_BAR
	LD	HL,RENDER_STATUS_BAR
	JP	TRAMP_FAR_CALL

TRAMP_FAR_CALL:
	PUSH	AF			; Preserve input AF (parameters)
	LD	A,(CPM_USER_BANK)
	CALL	0FFF3H
	EI
	POP	AF			; Restore input AF
	CALL	CALL_HL			; Call target function with original AF, BC, DE
	PUSH	AF			; Preserve return AF (results & Carry)
	DI
	LD	A,(PLUGIN_FAR_BANK)
	CALL	0FFF3H
	POP	AF			; Restore return AF
	RET

EXEC_PLUGIN_MGR_ACTION:
	; Input: C = Action index (0 = Plugin Manager, 1 = Context Popup, 2 = About)
	; Output: Returns Carry and registers from PLUGIN.PRL
	LD	A,1
	LD	(PLUGIN_IS_FAR_EXEC),A
	; Synchronize screen geometry and context in Host API (+14, +15, +16, +17)
	LD	A,(ACTIVE_COLS)
	LD	(HOST_API_COLS),A
	LD	A,(POPUP_CONTEXT_ID)
	LD	(HOST_API_CONTEXT),A
	LD	A,(ACTIVE_ROWS)
	LD	(HOST_API_ROWS),A
	LD	A,0FFH
	LD	(HOST_API_MGR_SLOT),A

	; Calculate entry address: 0x0100 + C * 3
	LD	HL,0100H
	LD	A,C
	OR	A
	JR	Z,EPMA_ENTRY
	ADD	A,A			; C * 2
	ADD	A,C			; C * 3
	LD	C,A
	LD	B,0
	ADD	HL,BC
EPMA_ENTRY:
	PUSH	HL
	POP	IX			; IX = entry point (0x0100, 0x0103, 0x0106)
	LD	IY,PLUGIN_HOST_API
	LD	A,(PLUGIN_MGR_BANK)
	LD	(PLUGIN_FAR_BANK),A	; In case host trampolines need PLUGIN_FAR_BANK
	DI
	CALL	0FFF9H			; HB_BNKCALL
	EI
	PUSH	AF
	XOR	A
	LD	(PLUGIN_IS_FAR_EXEC),A
	POP	AF
	RET

BORROW_PLUGIN_MGR_BANK:
	LD	A,(EXT_BANK_COUNT)
	CP	2
	JR	C,BPMB_FAIL		; Keep at least 1 bank for document
	DEC	A
	LD	(EXT_BANK_COUNT),A	; Decrement available document banks
	LD	E,A
	LD	D,0
	LD	HL,EXT_BANK_TABLE
	ADD	HL,DE
	LD	A,(HL)			; A = Stolen Far RAM Bank ID
	OR	A			; Carry = 0
	RET
BPMB_FAIL:
	SCF
	RET

ENSURE_PLUGIN_MGR_LOADED:
	LD	A,(PLUGIN_MGR_LOADED)
	OR	A
	RET	NZ			; Already loaded! Carry = 0

	; Check if plugin manager autoload is disabled in config
	LD	A,(CFG_AUTOLOAD_PLUGIN_MGR)
	OR	A
	JP	Z,EPML_FAIL

	; Check if Far RAM is available (at least 2 banks: 1 for doc, 1 for plugin mgr)
	LD	A,(EXT_BANK_COUNT)
	CP	2
	JP	C,EPML_FAIL

	; Borrow a dedicated Far RAM bank for PLUGIN.PRL (not in BORROWED_BANKS_TBL)
	CALL	BORROW_PLUGIN_MGR_BANK
	JP	C,EPML_FAIL
	LD	(PLUGIN_MGR_BANK),A

	; Open PLUGIN.PRL
	LD	HL,STR_DEF_PLUGIN_MGR
	CALL	PARSE_STRING_TO_PLUGIN_FCB

	; Query current user
	LD	E,0FFH
	LD	C,32
	CALL	BDOS_ENTRY
	LD	(PLUGIN_ORIG_USER),A

	; Target user
	LD	A,(PLUGIN_USER_AREA)
	LD	E,A
	LD	C,32
	CALL	BDOS_ENTRY

	; Open file
	LD	DE,PLUGIN_FCB
	LD	C,15
	CALL	BDOS_ENTRY
	CP	0FFH
	JP	Z,EPML_FILE_ERR

	; Set BDOS DMA to LINE_STORAGE + 4096
	LD	DE,LINE_STORAGE + 4096
	LD	C,26
	CALL	BDOS_ENTRY

	; Read first 2 sectors (256-byte header)
	LD	DE,PLUGIN_FCB
	LD	C,20
	CALL	BDOS_ENTRY
	OR	A
	JP	NZ,EPML_READ_ERR

	LD	DE,LINE_STORAGE + 4096 + 128
	LD	C,26
	CALL	BDOS_ENTRY

	LD	DE,PLUGIN_FCB
	LD	C,20
	CALL	BDOS_ENTRY
	OR	A
	JP	NZ,EPML_READ_ERR

	; Copy 256-byte header to PLUGIN_MGR_BANK at 0x0000
	PUSH	IX
	LD	B,0F4H
	LD	A,(PLUGIN_MGR_BANK)
	LD	D,A
	LD	A,(CPM_USER_BANK)
	LD	E,A
	LD	HL,256
	RST	08H
	POP	IX

	PUSH	IX
	LD	B,0F5H
	LD	HL,LINE_STORAGE + 4096
	LD	DE,0000H
	RST	08H
	POP	IX

	; Calculate sector count from PROG_SIZE at (LINE_STORAGE + 4096 + 1)
	LD	HL,(LINE_STORAGE + 4096 + 1)	; PROG_SIZE
	LD	DE,127
	ADD	HL,DE
	SRL	H
	RR	L
	SRL	H
	RR	L
	SRL	H
	RR	L
	SRL	H
	RR	L
	SRL	H
	RR	L
	SRL	H
	RR	L
	SRL	H
	RR	L
	LD	(PAYLOAD_SECTORS_REMAIN),HL

	LD	HL,0100H			; Code destination in PLUGIN_MGR_BANK
	LD	(FAR_SECT_DEST),HL

EPML_SECTOR_LOOP:
	LD	HL,(PAYLOAD_SECTORS_REMAIN)
	LD	A,H
	OR	L
	JR	Z,EPML_SECTORS_DONE
	DEC	HL
	LD	(PAYLOAD_SECTORS_REMAIN),HL

	LD	DE,LINE_STORAGE + 4096
	LD	C,26
	CALL	BDOS_ENTRY

	LD	DE,PLUGIN_FCB
	LD	C,20
	CALL	BDOS_ENTRY
	OR	A
	JP	NZ,EPML_READ_ERR

	PUSH	IX
	LD	B,0F4H
	LD	A,(PLUGIN_MGR_BANK)
	LD	D,A
	LD	A,(CPM_USER_BANK)
	LD	E,A
	LD	HL,128
	RST	08H
	POP	IX

	PUSH	IX
	LD	B,0F5H
	LD	HL,LINE_STORAGE + 4096
	LD	DE,(FAR_SECT_DEST)
	RST	08H
	POP	IX

	LD	HL,(FAR_SECT_DEST)
	LD	DE,128
	ADD	HL,DE
	LD	(FAR_SECT_DEST),HL
	JR	EPML_SECTOR_LOOP

EPML_SECTORS_DONE:
	; Close FCB
	LD	DE,PLUGIN_FCB
	LD	C,16
	CALL	BDOS_ENTRY

	; Restore original user area
	LD	A,(PLUGIN_ORIG_USER)
	LD	E,A
	LD	C,32
	CALL	BDOS_ENTRY

	; Restore DMA to 0080H
	LD	DE,0080H
	LD	C,26
	CALL	BDOS_ENTRY

	LD	A,1
	LD	(PLUGIN_MGR_LOADED),A
	LD	C,3			; Action 3: Autoload from PLUGIN.CFG
	CALL	EXEC_PLUGIN_MGR_ACTION
	OR	A				; Carry = 0
	RET

EPML_READ_ERR:
	; Close FCB
	LD	DE,PLUGIN_FCB
	LD	C,16
	CALL	BDOS_ENTRY

EPML_FILE_ERR:
	; Restore original user area
	LD	A,(PLUGIN_ORIG_USER)
	LD	E,A
	LD	C,32
	CALL	BDOS_ENTRY

	; Restore DMA to 0080H
	LD	DE,0080H
	LD	C,26
	CALL	BDOS_ENTRY

	; Release bank
	LD	A,(PLUGIN_MGR_BANK)
	CALL	RELEASE_FAR_BANK

EPML_FAIL:
	XOR	A
	LD	(PLUGIN_MGR_LOADED),A
	SCF					; Carry = 1
	RET

AUTO_LOAD_PLUGIN_MGR:
	LD	A,(EXT_BANK_COUNT)
	CP	2
	JR	NC,ALPM_CHK_CFG
	XOR	A
	LD	(CFG_AUTOLOAD_PLUGIN_MGR),A
	RET
ALPM_CHK_CFG:
	LD	A,(CFG_AUTOLOAD_PLUGIN_MGR)
	CP	PLUGIN_MODE_AUTOLOAD
	RET	NZ
	CALL	ENSURE_PLUGIN_MGR_LOADED
	RET

;==============================================================================
; Plugin Configuration File Management (PLUGIN.CFG)
;==============================================================================
STR_PLUGIN_CFG_NAME:	DB	"PLUGIN  CFG"

INIT_PLUGIN_CFG_FCB:
	LD	DE,CFG_FCB
	XOR	A
	LD	(DE),A			; Default drive (0)
	INC	DE
	LD	HL,STR_PLUGIN_CFG_NAME
	LD	BC,11
	LDIR
	EX	DE,HL			; HL = CFG_FCB + 12
	LD	B,24
	JP	INIT_CFG_ZERO

BDOS_CFG_FCB:
	LD	DE,CFG_FCB
	JP	BDOS_ENTRY

BDOS_CFG_DMA:
	LD	DE,CFG_IO_BUF
	LD	C,26
	JP	BDOS_ENTRY

BDOS_RESTORE_DMA:
	LD	DE,DEFAULT_DMA
	LD	C,26
	JP	BDOS_ENTRY

HOST_SAVE_PLUGIN_CFG_DISK:
	CALL	BDOS_CFG_DMA
	CALL	INIT_PLUGIN_CFG_FCB
	LD	C,19			; Delete existing PLUGIN.CFG
	CALL	BDOS_CFG_FCB
	CALL	INIT_PLUGIN_CFG_FCB
	LD	C,22			; Make PLUGIN.CFG
	CALL	BDOS_CFG_FCB
	INC	A
	JR	Z,HSPC_ERR
	LD	C,21			; Write record
	CALL	BDOS_CFG_FCB
	OR	A
	JR	NZ,HSPC_ERR_CLOSE
	LD	C,16			; Close file
	CALL	BDOS_CFG_FCB
	INC	A
	JR	Z,HSPC_ERR
	CALL	BDOS_RESTORE_DMA
	OR	A			; Carry = 0 (Success)
	RET

HSPC_ERR_CLOSE:
	LD	C,16
	CALL	BDOS_CFG_FCB
HSPC_ERR:
	CALL	BDOS_RESTORE_DMA
	SCF				; Carry = 1 (Error)
	RET

HOST_LOAD_PLUGIN_CFG_DISK:
	CALL	BDOS_CFG_DMA
	CALL	INIT_PLUGIN_CFG_FCB
	LD	C,15			; Open
	CALL	BDOS_CFG_FCB
	INC	A
	JR	Z,HLPC_NOT_FOUND

	; Pre-fill CFG_IO_BUF with 1AH (CP/M EOF)
	LD	HL,CFG_IO_BUF
	LD	(HL),1AH
	LD	DE,CFG_IO_BUF+1
	LD	BC,127
	LDIR

	LD	C,20			; Read
	CALL	BDOS_CFG_FCB
	OR	A
	JR	NZ,HLPC_READ_ERR
	LD	C,16			; Close
	CALL	BDOS_CFG_FCB
	CALL	BDOS_RESTORE_DMA
	OR	A			; Carry = 0 (Success)
	RET

HLPC_READ_ERR:
	LD	C,16			; Close
	CALL	BDOS_CFG_FCB
	CALL	BDOS_RESTORE_DMA
	SCF				; Carry = 1 (Error)
	RET
HLPC_NOT_FOUND:
	CALL	BDOS_RESTORE_DMA
	SCF				; Carry = 1 (File not found)
	RET

HOST_CLEAR_DOCUMENT:
	CALL	INIT_SLOT_SYSTEM
	LD	HL,0
	LD	(DOC_TOTAL_LINES),HL
	LD	(CUR_DOC_ROW),HL
	LD	(TOP_DOC_ROW),HL
	LD	(CACHE_START_ROW),HL
	LD	(CUR_COL),HL
	LD	(TARGET_COL),HL
	LD	(VIEW_LEFT_COL),HL
	CALL	CLEAR_CACHE_DIRTY_FLAGS
	XOR	A
	LD	(ACTIVE_LINE_DIRTY),A
	LD	HL,0FFFFH
	LD	(ACTIVE_LINE_ROW),HL
	XOR	A
	LD	(DOC_MODIFIED),A
	LD	(DOC_IS_FAT),A
	DEC	A
	LD	(FAT_DOC_UNIT),A
	XOR	A
	LD	(BLOCK_ACTIVE),A
	LD	(STATUS_OOM_FLAG),A
	LD	(FILE_IS_TRUNCATED),A
	LD	(ACTIVE_LINE_BUF),A
	LD	HL,0
	LD	(ACTIVE_LINE_LEN),HL
	RET

HOST_CHECKOUT_LINE:
	LD	(CUR_DOC_ROW),HL
	CALL	CHECKOUT_ACTIVE_LINE
	CALL	GET_CUR_ROW_LEN
	LD	(ACTIVE_LINE_LEN),DE
	LD	B,D
	LD	C,E			; BC = line length
	RET

HOST_COMMIT_LINE:
	; Inputs:
	; HL = line number
	; DE = buffer pointer (must be in Common RAM)
	; BC = line length
	PUSH	AF
	PUSH	HL
	PUSH	DE
	EX	DE,HL
	ADD	HL,BC
	LD	(HL),0			; Defensively ensure null termination
	POP	DE
	LD	HL,(ACTIVE_LINE_ROW)
	LD	A,H
	AND	L
	INC	A
	POP	HL
	JR	NZ,HCL_ACTIVE_RESTORE	; ACTIVE_LINE_ROW != 0xFFFF

	; ACTIVE_LINE_ROW == 0xFFFF. Compare HL with DOC_TOTAL_LINES
	PUSH	BC
	PUSH	DE
	LD	DE,(DOC_TOTAL_LINES)
	LD	A,H
	CP	D
	JR	NZ,HCL_NOT_EQUAL
	LD	A,L
	CP	E
	JR	NZ,HCL_NOT_EQUAL

	; HL == DOC_TOTAL_LINES -> Append mode
	POP	DE			; Restore buffer pointer
	POP	BC			; Restore length
	POP	AF			; Clean stack
	CALL	APPEND_LINE_SLOT	; BC = allocated slot ID, Carry on OOM
	RET	C
	LD	BC,(DOC_TOTAL_LINES)	; BC = line index
	EX	DE,HL			; HL = buffer pointer
	CALL	WRITE_FAR_LINE
	LD	HL,(DOC_TOTAL_LINES)
	INC	HL
	LD	(DOC_TOTAL_LINES),HL
	OR	A
	RET

HCL_NOT_EQUAL:
	; Check if HL < DOC_TOTAL_LINES
	EX	DE,HL			; HL = DOC_TOTAL_LINES, DE = line_num
	OR	A
	SBC	HL,DE			; If line_num < DOC_TOTAL_LINES, Carry = 0, NZ
	EX	DE,HL			; HL = line_num
	JR	C,HCL_OUT_OF_BOUNDS	; line_num > DOC_TOTAL_LINES
	; HL < DOC_TOTAL_LINES -> Overwrite mode
	POP	DE			; Restore buffer pointer
	POP	BC			; Restore length
	POP	AF			; Clean stack
	LD	B,H
	LD	C,L			; BC = line index
	EX	DE,HL			; HL = buffer pointer
	CALL	WRITE_FAR_LINE
	OR	A
	RET

HCL_OUT_OF_BOUNDS:
	POP	DE
	POP	BC
HCL_ACTIVE_RESTORE:
	POP	AF
HCL_ACTIVE:
	LD	A,1
	LD	(ACTIVE_LINE_DIRTY),A
	CALL	COMMIT_ACTIVE_LINE
	OR	A
	RET

HOST_SET_STATUS_MSG:
	LD	A,D
	OR	E
	JR	NZ,HSSM_COPY
	LD	(PLUGIN_STATUS_MSG_PTR),DE
	RET
HSSM_COPY:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
	EX	DE,HL			; HL = source string
	LD	DE,PLUGIN_STATUS_MSG_BUF
	LD	B,15
HSSM_LOOP:
	LD	A,(HL)
	OR	A
	JR	Z,HSSM_PAD
	CP	'$'
	JR	Z,HSSM_PAD
	LD	(DE),A
	INC	HL
	INC	DE
	DJNZ	HSSM_LOOP
HSSM_PAD:
	XOR	A
	LD	(DE),A			; Zero terminate
	LD	HL,PLUGIN_STATUS_MSG_BUF
	LD	(PLUGIN_STATUS_MSG_PTR),HL
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET

LOCAL_STACK_TOP:
	DS	256
LOCAL_STACK:

;==============================================================================
; Runtime Uninitialized BSS (Not emitted into SE.COM on disk)
; Allocated in RAM immediately following LOCAL_STACK (Page-Aligned)
;==============================================================================
ALIGN 256
BSS_START:

; 40 lines x 128 bytes stride local working cache in TPA (5,120 bytes)
LINE_STORAGE_SIZE EQU	CACHE_SIZE_LINES * 128
LINE_STORAGE	EQU	BSS_START

; Overlay directory entries buffer onto LINE_STORAGE (mutually exclusive with editor)
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

BSS_END		EQU	LINE_STORAGE + LINE_STORAGE_SIZE
