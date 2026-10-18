;==============================================================================
; UI.INC: Terminal Display, Menu Screens, Modal Popups & Status Bar Metrics
;
; Purpose:
;   Defines screen dimension constants, status bar metric widths, menu
;   line counts, popup tiers, box frame styling, and UI drawing signatures.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; Screen Dimensions & Display Metrics
;------------------------------------------------------------------------------
SCREEN_COLS_80		EQU	80	; Standard 80-column display width
SCREEN_COLS_120		EQU	120	; Extended 120-column display width
SCREEN_ROWS_24		EQU	24	; Standard 24-row display height
SCREEN_ROWS_40		EQU	40	; Extended 40-row display height

;------------------------------------------------------------------------------
; Status Bar Field Metrics (Bottom Line Enclosure)
;------------------------------------------------------------------------------
STATUS_ENCLOSED_WIDTH	EQU	78	; Inner content width of status bar
POS_FIELD_WIDTH		EQU	22	; "Ln XXXXX, Col XXX" width
MEM_FIELD_WIDTH		EQU	15	; "Free: XXXX KB" width
FILENAME_FIELD_WIDTH	EQU	14	; Filename field width

;------------------------------------------------------------------------------
; Static Menu Screen Line Counts
;------------------------------------------------------------------------------
	IFDEF TARGET_NEXT
SPLASH_MENU_LINES	EQU	20	; Splash & Commands screen line count
	ELSE
SPLASH_MENU_LINES	EQU	21	; Splash & Commands screen line count
	ENDIF
ABOUT_MENU_LINES	EQU	9	; About dialog line count
CONFIG_MENU_LINES	EQU	11	; Configuration dialog line count
MEM_INFO_LINES		EQU	23	; Extended memory info screen line count

;------------------------------------------------------------------------------
; UI Subsystem Function Entry Points & Register Contracts
;------------------------------------------------------------------------------
; RENDER_SCREEN:
;   Purpose:   Full screen refresh (document lines + status bar).
;   Inputs:    None
;   Outputs:   None
;   Clobbers:  AF, BC, DE, HL
;
; RENDER_STATUS_BAR:
;   Purpose:   Render status bar on bottom row of active display.
;   Inputs:    None
;   Outputs:   None
;   Clobbers:  AF, BC, DE, HL
;
; CLEAR_SCREEN:
;   Purpose:   Clear screen and home cursor.
;   Inputs:    None
;   Outputs:   None
;   Clobbers:  AF, BC, DE, HL
;
; SHOW_SPLASH_SCREEN:
;   Purpose:   Display startup splash / command guide menu.
;   Inputs:    None
;   Outputs:   None
;   Clobbers:  AF, BC, DE, HL
;
; SHOW_ABOUT_SCREEN:
;   Purpose:   Display editor version and author information.
;   Inputs:    None
;   Outputs:   None
;   Clobbers:  AF, BC, DE, HL
;
; SHOW_CONFIG_SCREEN:
;   Purpose:   Display and edit persistent editor options.
;   Inputs:    None
;   Outputs:   None
;   Clobbers:  AF, BC, DE, HL
;
; SHOW_MEM_INFO_SCREEN:
;   Purpose:   Display Far RAM banks, TPA memory map, and slot status.
;   Inputs:    None
;   Outputs:   None
;   Clobbers:  AF, BC, DE, HL
