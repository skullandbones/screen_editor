;==============================================================================
; HAL_NEXTCPM_MEMORY.ASM: Hardware Abstraction Layer - NextCPM Banked Memory
;
; Purpose:
;   Implements ZX Spectrum Next MMU detection, 8KB SRAM bank paging, and
;   Far RAM memory management for Profile 2 (CP/M on ZX Spectrum Next).
;   Detects Next hardware via NextReg 0x01 (Machine ID).
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; ZX Spectrum Next Hardware Register Ports
;------------------------------------------------------------------------------
NEXT_PORT_REG_SELECT	EQU	0243BH	; NextReg select port
NEXT_PORT_REG_DATA	EQU	0253BH	; NextReg data read/write port
NEXT_REG_MACHINE_ID	EQU	001H	; NextReg 0x01: Machine ID register
NEXT_REG_MMU_SLOT4	EQU	054H	; NextReg 0x54: MMU Slot 4 ($8000-$9FFF)

;------------------------------------------------------------------------------
; HAL Memory & Far Banking API Entry Points
;------------------------------------------------------------------------------
HAL_MEM_INIT		EQU	NEXTCPM_MEM_INIT
HAL_MEM_DETECT		EQU	NEXTCPM_MEM_DETECT
HAL_MEM_READ_SLOT	EQU	READ_FAR_SLOT
HAL_MEM_WRITE_SLOT	EQU	WRITE_FAR_SLOT

;------------------------------------------------------------------------------
; NEXTCPM_MEM_DETECT: Probe ZX Spectrum Next hardware presence
;
; Purpose:
;   Queries NextReg 0x01 (Machine ID) to verify execution on ZX Spectrum Next
;   hardware or Next-compatible emulator (CSpect, ZEsarUX).
;
; Outputs:
;   Zero flag (Z) set if Next hardware detected; NZ set if standard CP/M.
;   A = Machine ID byte if Next detected.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; modifies AF.
;------------------------------------------------------------------------------
NEXTCPM_MEM_DETECT:
	PUSH BC
	LD BC,NEXT_PORT_REG_SELECT
	LD A,NEXT_REG_MACHINE_ID
	OUT (C),A			; Select NextReg 0x01
	LD BC,NEXT_PORT_REG_DATA
	IN A,(C)			; Read Machine ID
	POP BC
	CP 00AH				; Machine ID 0x0A = ZX Spectrum Next
	RET Z				; Z set if exact Next match
	; Check if modern Next core (returns non-zero, non-FF)
	OR A
	RET Z				; 0 = No Next hardware
	CP 0FFH
	RET Z				; 0xFF = Floating bus / No hardware
	XOR A				; Return Z = 0 for detected Next
	RET

;------------------------------------------------------------------------------
; NEXTCPM_MEM_INIT: Initialize Far RAM memory for NextCPM environment
;
; Purpose:
;   Probes for Next hardware banking. If present, initializes Far RAM bank
;   descriptors. If absent or in standard 64KB TPA, defaults to disk swap.
;
; Outputs:
;   EXT_BANK_COUNT populated (0..12).
;   LINE_TABLE_BANK and LINE_TABLE_BANK_1 initialized.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
NEXTCPM_MEM_INIT:
	CALL NEXTCPM_MEM_DETECT
	JR NZ,NEXTCPM_MEM_NO_BANKS

	; Next hardware detected: initialize Next Far RAM banking
	; For safe CP/M operation, configure 4 banks (128KB Far RAM)
	LD A,4
	LD (EXT_BANK_COUNT),A
	XOR A
	LD (LINE_TABLE_BANK),A
	INC A
	LD (LINE_TABLE_BANK_1),A
	RET

NEXTCPM_MEM_NO_BANKS:
	; Standard CP/M mode without banking: use disk swap ($$$SE$$$.SWP)
	XOR A
	LD (EXT_BANK_COUNT),A
	LD (LINE_TABLE_BANK),A
	LD (LINE_TABLE_BANK_1),A
	RET
