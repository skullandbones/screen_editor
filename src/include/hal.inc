;==============================================================================
; HAL.INC: Hardware Abstraction Layer (HAL) API Interface Specifications
;
; Purpose:
;   Defines standard function entry points, vector calling conventions, and
;   register contracts for Console, Memory Banking, and Storage sub-systems.
;   Implemented by platform-specific HAL drivers:
;     - hal/cpm/        (Standard CP/M 2.2 / 3.0 / RomWBW HBIOS)
;     - hal/next_cpm/   (NextCPM on ZX Spectrum Next)
;     - hal/next_native/(Native NextZXOS / ESXDOS / Hardware Layer)
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; HAL Console Sub-system Interface
;------------------------------------------------------------------------------
; HAL_CONSOLE_INIT:
;   Inputs:    None
;   Outputs:   None
;   Clobbers:  AF, BC, DE, HL
;
; HAL_CONSOLE_PUTC:
;   Inputs:    A = ASCII character to transmit
;   Outputs:   None
;   Clobbers:  AF (preserves BC, DE, HL)
;
; HAL_CONSOLE_PUTS:
;   Inputs:    DE = Pointer to '$'-terminated or null-terminated string
;   Outputs:   None
;   Clobbers:  AF, DE (preserves BC, HL)
;
; HAL_CONSOLE_GETKEY:
;   Inputs:    None
;   Outputs:   A = Keycode (0 if non-blocking and no key pending)
;   Clobbers:  AF (preserves BC, DE, HL)
;
; HAL_CONSOLE_LOCATE:
;   Inputs:    H = Row (1-based, 1..ACTIVE_ROWS)
;              L = Column (1-based, 1..ACTIVE_COLS)
;   Outputs:   None
;   Clobbers:  AF, DE (preserves BC, HL)
;
; HAL_CONSOLE_INVERSE_ON:
;   Inputs:    None
;   Outputs:   None
;   Clobbers:  AF, DE (preserves BC, HL)
;
; HAL_CONSOLE_INVERSE_OFF:
;   Inputs:    None
;   Outputs:   None
;   Clobbers:  AF, DE (preserves BC, HL)
;
; HAL_CONSOLE_CLEAR:
;   Inputs:    None
;   Outputs:   None
;   Clobbers:  AF, DE (preserves BC, HL)
;
; HAL_CONSOLE_CLEAR_EOL:
;   Inputs:    None
;   Outputs:   None
;   Clobbers:  AF, DE (preserves BC, HL)
;
; HAL_CONSOLE_HIDE_CURSOR:
;   Inputs:    None
;   Outputs:   None
;   Clobbers:  AF, DE (preserves BC, HL)
;
; HAL_CONSOLE_SHOW_CURSOR:
;   Inputs:    None
;   Outputs:   None
;   Clobbers:  AF, DE (preserves BC, HL)

;------------------------------------------------------------------------------
; HAL Memory & Far Banking Sub-system Interface
;------------------------------------------------------------------------------
; HAL_MEM_INIT:
;   Inputs:    None
;   Outputs:   A = Number of available Far RAM banks (0..12)
;              Carry = 0 on success, 1 on failure
;   Clobbers:  AF, BC, DE, HL
;
; HAL_MEM_READ_SLOT:
;   Inputs:    BC = Physical Slot ID (0..MAX_VIRTUAL_SLOTS)
;              DE = Destination buffer pointer (128 bytes)
;   Outputs:   Carry = 0 on success, 1 on error
;   Clobbers:  AF, BC, DE, HL
;
; HAL_MEM_WRITE_SLOT:
;   Inputs:    BC = Physical Slot ID (0..MAX_VIRTUAL_SLOTS)
;              DE = Source buffer pointer (128 bytes)
;   Outputs:   Carry = 0 on success, 1 on error
;   Clobbers:  AF, BC, DE, HL
;
; HAL_MEM_SET_BANK:
;   Inputs:    A = Far RAM Bank index to page in (0..11)
;   Outputs:   None
;   Clobbers:  AF, BC (preserves DE, HL)

;------------------------------------------------------------------------------
; HAL Storage & File I/O Sub-system Interface
;------------------------------------------------------------------------------
; HAL_STORAGE_OPEN:
;   Inputs:    DE = Pointer to FCB (CP/M) or Path string (NextZXOS)
;   Outputs:   Carry = 0 on success, 1 if file not found
;   Clobbers:  AF, BC, DE, HL
;
; HAL_STORAGE_MAKE:
;   Inputs:    DE = Pointer to FCB or Path string
;   Outputs:   Carry = 0 on success, 1 on disk full or directory error
;   Clobbers:  AF, BC, DE, HL
;
; HAL_STORAGE_CLOSE:
;   Inputs:    DE = Pointer to FCB or File handle
;   Outputs:   Carry = 0 on success, 1 on error
;   Clobbers:  AF, BC, DE, HL
;
; HAL_STORAGE_READ_SEC:
;   Inputs:    DE = Pointer to FCB or File handle
;   Outputs:   A = 0 on success, non-zero on EOF or error
;   Clobbers:  AF, BC, DE, HL
;
; HAL_STORAGE_WRITE_SEC:
;   Inputs:    DE = Pointer to FCB or File handle
;   Outputs:   A = 0 on success, non-zero on disk full or error
;   Clobbers:  AF, BC, DE, HL
