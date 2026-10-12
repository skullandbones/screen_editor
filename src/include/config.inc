;==============================================================================
; CONFIG.INC: Global Configuration, Editor Constants, Limits & Keycodes
;
; Purpose:
;   Defines platform-agnostic editor limits, line dimensions, keycodes,
;   screen modes, confirmation action codes, and configuration defaults.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; CP/M System Addresses & Vectors
;------------------------------------------------------------------------------
	IFNDEF BDOS_ENTRY
BDOS_ENTRY		EQU	$0005	; BDOS call entry vector
	ENDIF
	IFNDEF DEFAULT_DMA
DEFAULT_FCB		EQU	$005C	; Default FCB 1 in CP/M base page
DEFAULT_DMA		EQU	$0080	; Default DMA buffer in base page
CMD_LEN			EQU	$0080	; Command tail length byte
CMD_TAIL		EQU	$0081	; Command tail ASCII string
	ENDIF

;------------------------------------------------------------------------------
; Buffer & Document Capacity Limits
;------------------------------------------------------------------------------
MAX_LINE_STRIDE		EQU	128	; 128 bytes stride per cache line slot
MAX_LINE_CHARS		EQU	1000	; Max visual characters per line
MAX_INPUT_LINE_CHARS	EQU	1000	; Interactive typing length limit
MAX_CACHE_LINE_CHARS EQU	250	; Limit for 256B scratch line buffers
MAX_ACTIVE_LINE_STRIDE	EQU	1024	; Dynamic workspace for active line
MAX_ACTIVE_PAYLOAD	EQU	1022	; Max payload characters in active line
MAX_ACTIVE_PAYLOAD_LO	EQU	254	; Low byte of 1022
MAX_ACTIVE_PAYLOAD_HI	EQU	3	; High byte of 1022
FAR_SLOT_SIZE		EQU	128	; 128 bytes stride per Far RAM slot
FAR_SLOT_PAYLOAD	EQU	126	; 126 bytes text payload per Far slot
SLOT_TERM		EQU	0FFFFH	; 16-bit terminal slot marker in Far RAM
MAX_COPY_LINE_CHARS	EQU	120	; Single-line block copy capacity limit
MAX_FAR_BANKS		EQU	12	; Up to 12 Far RAM banks (384KB)
CACHE_SIZE_LINES	EQU	40	; 40 lines in local working cache (5KB)
MAX_DOC_LINES_16K	EQU	16384	; 16,384 lines table limit
MAX_DOC_LINES_32K	EQU	32768	; 32,768 lines table limit
MAX_DOC_LINES		EQU	32768	; Ceiling for document line indices
MAX_VIRTUAL_SLOTS	EQU	65534	; Up to 65,534 128B slots (~8.3 MB)

;------------------------------------------------------------------------------
; Keyboard Control Codes (WordStar & ANSI Mappings)
;------------------------------------------------------------------------------
KEY_CTRL_A		EQU	1	; Start of line (Home)
KEY_CTRL_B		EQU	2	; Toggle Block Highlighting
KEY_CTRL_C		EQU	3	; Cancel / Copy block
KEY_CTRL_D		EQU	4	; Cursor Right
KEY_CTRL_E		EQU	5	; End of line (End)
KEY_CTRL_F		EQU	6	; Find / Toggle endings in save
KEY_CTRL_G		EQU	7	; Delete character at cursor
KEY_BACKSPACE		EQU	8	; Destructive backspace
KEY_TAB			EQU	9	; Tab character / Prompt toggle
KEY_CTRL_I		EQU	9	; Synonymous with Tab
KEY_CTRL_K		EQU	11	; Show Editor Mode Keys Screen
KEY_CTRL_L		EQU	12	; Goto Line Number
KEY_ENTER		EQU	13	; Carriage Return / Enter
KEY_CTRL_N		EQU	14	; Find Next
KEY_CTRL_O		EQU	15	; Open File Screen
KEY_CTRL_P		EQU	16	; Context-Aware Plugin Pop-up
KEY_CTRL_Q		EQU	17	; Quick exit / Save changes prompt
KEY_CTRL_R		EQU	18	; Search & Replace
KEY_CTRL_S		EQU	19	; Save current document
KEY_CTRL_U		EQU	21	; Page Up
KEY_CTRL_V		EQU	22	; Page Down
KEY_CTRL_W		EQU	23	; Close active file to splash screen
KEY_CTRL_X		EQU	24	; Move solidified block to cursor
KEY_CTRL_Y		EQU	25	; Beautify Block or Document
KEY_CTRL_Z		EQU	26	; Open Plugin Manager Screen
KEY_ESC			EQU	27	; Escape prefix / Cancel dialog
KEY_DEL			EQU	127	; Rubout / Delete character

ESC_TIMEOUT_LOOPS	EQU	5000	; Escape debounce timeout (~15-20ms)

;------------------------------------------------------------------------------
; Modal Confirmation Action Codes
;------------------------------------------------------------------------------
ACTION_EXIT		EQU	0	; Exit editor to OS prompt
ACTION_CLOSE		EQU	1	; Close document to splash screen
ACTION_NEW		EQU	2	; Start new blank document
ACTION_OPEN		EQU	3	; Open File Screen

;------------------------------------------------------------------------------
; Line Ending Modes
;------------------------------------------------------------------------------
FMT_CPM			EQU	0	; CP/M format: CR/LF (0x0D, 0x0A)
FMT_LINUX		EQU	1	; Linux format: LF only (0x0A)

;------------------------------------------------------------------------------
; Screen Geometry Modes
;------------------------------------------------------------------------------
MODE_120X40		EQU	0	; Modern 120 columns x 40 rows (Default)
MODE_80X24		EQU	1	; Classic 80 columns x 24 rows

;------------------------------------------------------------------------------
; RAM Drive Modes
;------------------------------------------------------------------------------
RAMDRV_MODE_PROTECTED	EQU	0	; Preserve RAM disk (81h..88h safe)
RAMDRV_MODE_ENABLED	EQU	1	; Overwrite for max RAM buffer (384KB)
RAMDRV_MODE_HIBERNATE	EQU	2	; Auto-dump to RAMDRV.IMG on disk
RAMDRV_START_BANK	EQU	081H	; RomWBW MD0:0 starts at bank 0x81
RAMDRV_END_BANK		EQU	088H	; RomWBW MD0:0 ends at bank 0x88 (256KB)

;------------------------------------------------------------------------------
; Plugin Subsystem Modes
;------------------------------------------------------------------------------
PLUGIN_MODE_DISABLED	EQU	0	; Subsystem disabled by user or low RAM
PLUGIN_MODE_AUTOLOAD	EQU	1	; Autoload PLUGIN.PRL at boot
PLUGIN_MODE_ONDEMAND	EQU	2	; Load PLUGIN.PRL on demand when used
