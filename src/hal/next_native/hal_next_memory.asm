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
	; Set CPM_USER_BANK to 0xFF (so user bank never collides with 0..11)
	LD A,0FFH
	LD (CPM_USER_BANK),A

	; Configure Line Table banks (Banks 0 and 1 = 64KB line table)
	XOR A
	LD (LINE_TABLE_BANK),A		; Bank 0: lines 0..16383
	INC A
	LD (LINE_TABLE_BANK_1),A	; Bank 1: lines 16384..32767

	; Configure document line limit: 32,768 lines
	LD HL,MAX_DOC_LINES_32K
	LD (MAX_DOC_LINES_LIMIT),HL

	; Populate EXT_BANK_TABLE with text slot banks 2..11 (10 banks)
	LD HL,EXT_BANK_TABLE
	LD B,10
	LD A,2
NMI_BANK_LOOP:
	LD (HL),A
	INC HL
	INC A
	DJNZ NMI_BANK_LOOP

	LD A,10
	LD (EXT_BANK_COUNT),A
	OR A				; Clear carry (success)
	RET

;------------------------------------------------------------------------------
; NEXT_SYSSETCPY: Setup source/destination banks and length for Next bank copy
;
; Inputs:
;   D = Destination Bank ID
;   E = Source Bank ID
;   HL = Byte Count to copy
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
NEXT_SYSSETCPY:
	PUSH AF
	LD A,D
	LD (NEXT_CPY_DEST_BNK),A
	LD A,E
	LD (NEXT_CPY_SRC_BNK),A
	LD (NEXT_CPY_LEN),HL
	POP AF
	RET

;------------------------------------------------------------------------------
; NEXT_SYSBNKCPY: Copy memory between Local RAM and Next MMU Far RAM Slot 1
;
; Purpose:
;   Maps target Far RAM 8KB page into MMU Slot 1 ($2000-$3FFF) via NextReg 0x51,
;   executes atomic LDIR with interrupts disabled, and restores original Slot 1.
;
; Inputs:
;   HL = Source Address
;   DE = Destination Address
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
NEXT_SYSBNKCPY:
	LD A,(NEXT_CPY_SRC_BNK)
	LD B,A
	LD A,(CPM_USER_BANK)
	CP B
	JR Z,NSB_SRC_IS_USER

	; Case 1: Source is Far RAM Bank (B), Destination is Local RAM (DE)
	; Compute physical 8KB page: 32 + (Bank * 4) + (H >> 5)
	LD A,B				; Bank ID (0..11)
	ADD A,A				; *2
	ADD A,A				; *4
	LD C,A

	LD A,H
	RLCA
	RLCA
	RLCA
	AND 07H				; H >> 5 (0..3)
	ADD A,C
	ADD A,NEXT_FAR_RAM_BASE_PAGE	; A = Physical 8KB page
	LD (NEXT_TARGET_FAR_PAGE),A

	; Adjust Far Source Address to Slot 1 ($2000..$3FFF)
	LD A,H
	AND 01FH
	OR 020H
	LD H,A
	JR NSB_DO_TRANSFER

NSB_SRC_IS_USER:
	; Case 2: Source is Local RAM (HL), Destination is Far RAM Bank
	LD A,(NEXT_CPY_DEST_BNK)
	LD B,A
	LD A,(CPM_USER_BANK)
	CP B
	JR Z,NSB_LOCAL_TO_LOCAL		; Both are user bank

	; Compute physical 8KB page: 32 + (Bank * 4) + (D >> 5)
	LD A,B
	ADD A,A
	ADD A,A
	LD C,A

	LD A,D
	RLCA
	RLCA
	RLCA
	AND 07H				; D >> 5 (0..3)
	ADD A,C
	ADD A,NEXT_FAR_RAM_BASE_PAGE	; A = Physical 8KB page
	LD (NEXT_TARGET_FAR_PAGE),A

	; Adjust Far Destination Address to Slot 1 ($2000..$3FFF)
	LD A,D
	AND 01FH
	OR 020H
	LD D,A

NSB_DO_TRANSFER:
	DI
	; Save current Slot 1 page and map Far Page into Slot 1
	LD BC,NEXT_PORT_REG_SELECT
	LD A,051H			; NextReg 0x51 = MMU Slot 1
	OUT (C),A
	LD BC,NEXT_PORT_REG_DATA
	IN A,(C)			; Read current Slot 1 page
	LD (NEXT_SAVED_SLOT1_PAGE),A
	LD A,(NEXT_TARGET_FAR_PAGE)
	OUT (C),A			; Map target page into Slot 1

	; Perform atomic transfer
	LD BC,(NEXT_CPY_LEN)
	LDIR

	; Restore original Slot 1 page
	LD BC,NEXT_PORT_REG_SELECT
	LD A,051H
	OUT (C),A
	LD BC,NEXT_PORT_REG_DATA
	LD A,(NEXT_SAVED_SLOT1_PAGE)
	OUT (C),A
	EI
	RET

NSB_LOCAL_TO_LOCAL:
	LD BC,(NEXT_CPY_LEN)
	LDIR
	RET

;------------------------------------------------------------------------------
; HAL_MEM_SET_BANK: Map target Far RAM bank into CPU address space
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

;------------------------------------------------------------------------------
; Far Memory Transfer State Variables
;------------------------------------------------------------------------------
NEXT_CPY_DEST_BNK:	DB	0
NEXT_CPY_SRC_BNK:	DB	0
NEXT_CPY_LEN:		DW	0
NEXT_SAVED_SLOT1_PAGE:	DB	0
NEXT_TARGET_FAR_PAGE:	DB	0

; End of HAL_NEXT_MEMORY.ASM
