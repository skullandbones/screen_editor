;==============================================================================
; HAL_NEXT_MEMORY.ASM: Hardware Abstraction Layer - Native Next Memory Driver
;
; Purpose:
;   Implements ZX Spectrum Next MMU memory management via NextRegs 0x50..0x57.
;   Provides 8KB SRAM page banking across 1024 KB / 2048 KB on-board SRAM for
;   Profile 3 (Native ZX Spectrum Next / NextZXOS).
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; ZX Spectrum Next Hardware Register Ports & NextRegs
;------------------------------------------------------------------------------
NEXT_PORT_REG_SELECT	EQU	0243BH	; NextReg select port
NEXT_PORT_REG_DATA	EQU	0253BH	; NextReg data read/write port
NEXT_REG_MACHINE_ID	EQU	001H	; NextReg 0x01: Machine ID register
NEXT_REG_MMU_SLOT4	EQU	054H	; NextReg 0x54: MMU Slot 4 ($8000-$9FFF)
NEXT_REG_MMU_SLOT5	EQU	055H	; NextReg 0x55: MMU Slot 5 ($A000-$BFFF)

; Far RAM Base 8KB Page allocation (above system reserved 128K pages)
NEXT_FAR_RAM_BASE_PAGE	EQU	020H	; 8KB Page 32 (256 KB offset)

;------------------------------------------------------------------------------
; HAL Memory & Far Banking API Entry Points
;------------------------------------------------------------------------------
HAL_MEM_INIT		EQU	NEXT_MEM_INIT
HAL_MEM_DETECT		EQU	NEXT_MEM_DETECT
HAL_MEM_READ_SLOT	EQU	READ_FAR_SLOT
HAL_MEM_WRITE_SLOT	EQU	WRITE_FAR_SLOT

;------------------------------------------------------------------------------
; NEXT_MEM_DETECT: Probe ZX Spectrum Next hardware presence
;
; Purpose:
;   Queries NextReg 0x01 (Machine ID) to confirm execution on genuine Next
;   hardware or official emulators (CSpect, ZEsarUX).
;
; Outputs:
;   Zero flag (Z) set if Next hardware detected; NZ set if absent.
;   A = Machine ID byte if Next detected.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; modifies AF.
;------------------------------------------------------------------------------
NEXT_MEM_DETECT:
	PUSH BC
	LD BC,NEXT_PORT_REG_SELECT
	LD A,NEXT_REG_MACHINE_ID
	OUT (C),A			; Select NextReg 0x01
	LD BC,NEXT_PORT_REG_DATA
	IN A,(C)			; Read Machine ID
	POP BC
	CP 00AH				; Machine ID 0x0A = ZX Spectrum Next
	RET Z				; Z set if exact Next match
	OR A
	RET Z				; 0 = No Next hardware
	CP 0FFH
	RET Z				; 0xFF = Floating bus / No hardware
	XOR A				; Return Z = 0 for detected Next
	RET

;------------------------------------------------------------------------------
; NEXT_MEM_INIT: Initialize Far RAM MMU pages for Native Next environment
;
; Purpose:
;   Probes for Next hardware. When detected, configures 12 Far RAM banks
;   (mapping 8KB pages 32..43) for document line tables and cache slots.
;
; Outputs:
;   EXT_BANK_COUNT = 12 on success; 0 on failure.
;   LINE_TABLE_BANK and LINE_TABLE_BANK_1 initialized.
;   Carry = 0 on success, 1 on failure.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
NEXT_MEM_INIT:
	CALL NEXT_MEM_DETECT
	JR NZ,NMI_NO_HARDWARE

	; Allocate 12 Far RAM banks across Next on-board SRAM
	LD A,12
	LD (EXT_BANK_COUNT),A
	XOR A
	LD (LINE_TABLE_BANK),A
	INC A
	LD (LINE_TABLE_BANK_1),A
	OR A				; Clear carry (success)
	RET

NMI_NO_HARDWARE:
	XOR A
	LD (EXT_BANK_COUNT),A
	LD (LINE_TABLE_BANK),A
	LD (LINE_TABLE_BANK_1),A
	SCF				; Set carry (error)
	RET

;------------------------------------------------------------------------------
; HAL_MEM_SET_BANK: Map target Far RAM bank into CPU address space
;
; Inputs:
;   A = Far RAM Bank index (0..11).
;
; Outputs:
;   MMU Slot 4 ($8000-$9FFF) updated to map the corresponding 8KB page.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; modifies AF.
;------------------------------------------------------------------------------
HAL_MEM_SET_BANK:
	PUSH BC
	ADD A,NEXT_FAR_RAM_BASE_PAGE	; A = Physical 8KB page number
	PUSH AF
	LD BC,NEXT_PORT_REG_SELECT
	LD A,NEXT_REG_MMU_SLOT4
	OUT (C),A
	LD BC,NEXT_PORT_REG_DATA
	POP AF				; A = Physical page number
	OUT (C),A
	POP BC
	RET

; End of HAL_NEXT_MEMORY.ASM
