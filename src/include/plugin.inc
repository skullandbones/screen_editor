;==============================================================================
; PLUGIN.INC: Far RAM Plugin Manager, Host API Jump Vector & PRL/OVL Interface
;
; Purpose:
;   Defines plugin registry structures, capability bitmasks, Upper Memory
;   resident Host API vectors, execution modes, and plugin loader contracts.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; Plugin Registry Limits & Geometry
;------------------------------------------------------------------------------
PLUGIN_ENTRY_SIZE	EQU	32	; 32 bytes per plugin descriptor record
PLUGIN_MAX_SLOTS	EQU	8	; Up to 8 concurrent plugin slots
PLUGIN_UI_LINES		EQU	17	; Plugin Manager interactive menu height

;------------------------------------------------------------------------------
; Plugin Capability Bitflags (Word at Offset +20 in Descriptor)
;------------------------------------------------------------------------------
CAP_TPA_EXEC		EQU	0001H	; Runs in Base TPA (Overlays SE.COM)
CAP_FAR_EXEC		EQU	0002H	; Runs in Far RAM banked memory
CAP_DOC_MUTATE		EQU	0004H	; Can modify active document contents
CAP_MODAL_UI		EQU	0008H	; Provides full interactive screen UI
CAP_HAS_ABOUT		EQU	0010H	; Exports Action 1 (About Screen)
CAP_HAS_CONFIG		EQU	0020H	; Exports Action 2 (Config Screen)
CAP_SIZE_4K		EQU	0000H	; Size class: up to 4 KB
CAP_SIZE_8K		EQU	0040H	; Size class: up to 8 KB
CAP_SIZE_16K		EQU	0080H	; Size class: up to 16 KB
CAP_SIZE_32K		EQU	00C0H	; Size class: up to 32 KB
CAP_SIZE_MASK		EQU	00C0H	; Mask for size class bits

;------------------------------------------------------------------------------
; Context-Aware Plugin Screen IDs
;------------------------------------------------------------------------------
PLUG_CTX_EDITOR		EQU	0	; Active text editing screen
PLUG_CTX_SPLASH		EQU	1	; Main splash / command keys screen
PLUG_CTX_CONFIG		EQU	2	; Global editor settings dialog
PLUG_CTX_MEM_INFO	EQU	3	; Hardware and Far RAM info display
PLUG_CTX_PLUGIN_MGR	EQU	4	; Plugin Manager manager screen
PLUG_CTX_HELP		EQU	5	; Online help and keybindings screen
PLUG_CTX_ABOUT		EQU	6	; About SE.COM dialog

;------------------------------------------------------------------------------
; Upper Memory Host API Vector Offsets (Base = PLUGIN_HOST_API in Upper RAM)
;------------------------------------------------------------------------------
HOST_API_OFF_MAGIC	EQU	0	; "SE" signature (2 bytes)
HOST_API_OFF_VERSION	EQU	2	; Host version word (0114H = v1.1.4)
HOST_API_OFF_LINE_BUF	EQU	4	; Pointer to ACTIVE_LINE_BUF

HOST_API_OFF_LINE_LEN	EQU	6	; Pointer to ACTIVE_LINE_LEN
HOST_API_OFF_CUR_ROW	EQU	8	; Pointer to CUR_DOC_ROW
HOST_API_OFF_TOTAL_LINES EQU	10	; Pointer to DOC_TOTAL_LINES
HOST_API_OFF_CUR_COL	EQU	12	; Pointer to CUR_COL
HOST_API_OFF_COLS	EQU	14	; Active screen columns (80 or 120)
HOST_API_OFF_CONTEXT	EQU	15	; Active screen context ID (0..6)
HOST_API_OFF_ROWS	EQU	16	; Active screen rows (24 or 40)
HOST_API_OFF_MGR_SLOT	EQU	17	; Plugin Manager slot (0..7 or 0xFF)
HOST_API_OFF_CHECKOUT	EQU	18	; JP to HOST_CHECKOUT_LINE
HOST_API_OFF_COMMIT	EQU	21	; JP to HOST_COMMIT_LINE
HOST_API_OFF_PUTC	EQU	24	; JP to PUTC
HOST_API_OFF_PRINT_STR	EQU	27	; JP to PRINT_STR
HOST_API_OFF_GET_KEY	EQU	30	; JP to GET_KEY
HOST_API_OFF_SET_STATUS	EQU	33	; JP to SET_STATUS_MSG
HOST_API_OFF_BLOCK_ACT	EQU	36	; Pointer to BLOCK_ACTIVE
HOST_API_OFF_BLOCK_START EQU	38	; Pointer to BLOCK_START_ROW
HOST_API_OFF_BLOCK_END	EQU	40	; Pointer to BLOCK_END_ROW
HOST_API_OFF_TAB_WIDTH	EQU	42	; Pointer to CFG_TAB_WIDTH
HOST_API_OFF_PLUGIN_REG	EQU	44	; Pointer to PLUGIN_REGISTRY (256 bytes)
HOST_API_OFF_CHECK_KEY	EQU	46	; JP to CHECK_KEY_READY
HOST_API_OFF_CLEAR_DOC	EQU	49	; JP to HOST_CLEAR_DOCUMENT
HOST_API_OFF_LOCATE_RC	EQU	52	; JP to LOCATE_RC (H=Row, L=Col)
HOST_API_OFF_LOAD_PLUGIN EQU	55	; JP to LOAD_PLUGIN_BY_NAME
HOST_API_OFF_UNLOAD_SLOT EQU	58	; JP to UNLOAD_PLUGIN_SLOT
HOST_API_OFF_REDRAW_BASE EQU	61	; JP to REDRAW_BASE_SCREEN
HOST_API_OFF_OPEN_UI	EQU	64	; JP to DO_OPEN_FILE_UI (plugin mode)
HOST_API_OFF_SAVE_CFG	EQU	67	; JP to HOST_SAVE_PLUGIN_CFG
HOST_API_OFF_LOAD_CFG	EQU	70	; JP to HOST_LOAD_PLUGIN_CFG
HOST_API_OFF_RENDER_STAT EQU	73	; JP to RENDER_STATUS_BAR
HOST_API_OFF_HIDE_CUR	EQU	76	; JP to TERM_HIDE_CURSOR
HOST_API_OFF_SHOW_CUR	EQU	79	; JP to TERM_SHOW_CURSOR

;------------------------------------------------------------------------------
; Plugin Subsystem Function Entry Points & Register Contracts
;------------------------------------------------------------------------------
; INIT_PLUGIN_REGISTRY:
;   Purpose:   Initialize registry table, reset load counters.
;   Inputs:    None
;   Outputs:   PLUGIN_REGISTRY zeroed, PLUGIN_LOAD_COUNT = 0
;   Clobbers:  AF, BC, DE, HL
;
; LOAD_PLUGIN_BY_NAME:
;   Purpose:   Load PRL or OVL plugin by ASCII name in DE into free slot.
;   Inputs:    DE = Pointer to null-terminated plugin filename
;   Outputs:   Carry = 0 on success (A = slot index), 1 on error
;   Clobbers:  AF, BC, DE, HL
;
; UNLOAD_PLUGIN_SLOT:
;   Purpose:   Release slot A and free Far RAM bank if no longer needed.
;   Inputs:    A = Slot index (0..7)
;   Outputs:   None
;   Clobbers:  AF, BC, DE, HL
;
; EXEC_PLUGIN_SLOT:
;   Purpose:   Execute action in C (0=Main, 1=About, 2=Config) on slot A.
;   Inputs:    A = Slot index (0..7), C = Action code (0..2)
;   Outputs:   A = Return status code, Carry flag set on error
;   Clobbers:  All registers
;
; GET_REGISTRY_ENTRY_PTR:
;   Purpose:   Calculate memory address of 32-byte descriptor for slot B.
;   Inputs:    B = Slot index (0..7)
;   Outputs:   HL = Pointer to entry in PLUGIN_REGISTRY
;   Clobbers:  AF, DE (preserves B)
