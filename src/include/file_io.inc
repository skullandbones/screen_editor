;==============================================================================
; FILE_IO.INC: High-Level Document File I/O, FCB Definitions & Directory API
;
; Purpose:
;   Defines CP/M File Control Block (FCB) field offsets, file transfer
;   batch counters, and high-level file load/save/export function signatures.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; CP/M File Control Block (FCB) Offsets
;------------------------------------------------------------------------------
FCB_DRIVE		EQU	0	; Drive code (0=default, 1=A:, 2=B:)
FCB_NAME		EQU	1	; File name (8 characters ASCII)
FCB_EXT			EQU	9	; File extension (3 characters ASCII)
FCB_EX			EQU	12	; Current extent number
FCB_S1			EQU	13	; Reserved for CP/M internal use
FCB_S2			EQU	14	; Reserved / Extent high byte
FCB_RC			EQU	15	; Record count in current extent
FCB_AL			EQU	16	; Disk allocation map (16 bytes)
FCB_CR			EQU	32	; Current sequential record (0..127)
FCB_R0			EQU	33	; Random access record number (low byte)
FCB_R1			EQU	34	; Random access record number (mid byte)
FCB_R2			EQU	35	; Random access record (high byte)


;------------------------------------------------------------------------------
; File I/O Subsystem Function Entry Points & Register Contracts
;------------------------------------------------------------------------------
; LOAD_FILE:
;   Purpose:   Open file at WORK_FCB and load lines into Far RAM buffer.
;   Inputs:    WORK_FCB, WORK_FCB_USER
;   Outputs:   Carry = 0 on success, 1 on file not found or memory full
;   Clobbers:  AF, BC, DE, HL
;
; SAVE_FILE:
;   Purpose:   Write open document to disk according to SAVE_FORMAT.
;   Inputs:    WORK_FCB, WORK_FCB_USER, SAVE_FORMAT (FMT_CPM / FMT_LINUX)
;   Outputs:   Carry = 0 on success, 1 on disk full or write error
;   Clobbers:  AF, BC, DE, HL
;
; SAVE_BLOCK_FILE:
;   Purpose:   Export highlighted block lines to specified disk file.
;   Inputs:    WORK_FCB, BLOCK_START_ROW, BLOCK_END_ROW
;   Outputs:   Carry = 0 on success, 1 on write error
;   Clobbers:  AF, BC, DE, HL
;
; DO_OPEN_FILE_UI:
;   Purpose:   Display interactive file picker with directory enumeration.
;   Inputs:    None
;   Outputs:   Carry = 0 on file selected and loaded, 1 if cancelled
;   Clobbers:  AF, BC, DE, HL
;
; DO_SAVE_FILE_UI:
;   Purpose:   Display interactive save/export modal dialog.
;   Inputs:    None
;   Outputs:   Carry = 0 on save complete, 1 if cancelled
;   Clobbers:  AF, BC, DE, HL
;
; POPULATE_FCB:
;   Purpose:   Parse ASCII path/filename string into 36-byte CP/M FCB.
;   Inputs:    HL = Source ASCII string pointer, DE = Destination FCB pointer
;   Outputs:   Carry = 0 on valid filename, 1 on invalid characters
;   Clobbers:  AF, BC, DE, HL
;
; CHECK_FCB_IS_HIBERNATED:
;   Purpose:   Check if target drive corresponds to active hibernated RAM disk.
;   Inputs:    DE = Target FCB pointer
;   Outputs:   Carry = 0 if valid/safe, 1 if blocked (hibernated drive)
;   Clobbers:  AF, BC, DE, HL
