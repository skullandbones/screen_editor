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

; Far RAM Base 8KB Page allocation (above system reserved 128K pages)
NEXT_FAR_RAM_BASE_PAGE	EQU	020H	; 8KB Page 32 (256 KB offset)

NEXT_MEM_INIT		EQU	NEXTCPM_MEM_INIT

;------------------------------------------------------------------------------
; NEXTCPM_MEM_INIT: Initialize Far RAM memory for NextCPM environment
;
; Purpose:
;   Initializes 12 Far RAM banks across Next on-board SRAM for document
;   storage under NextCPM.
;
; Outputs:
;   EXT_BANK_COUNT = 10, LINE_TABLE_BANK = 0, LINE_TABLE_BANK_1 = 1.
;   Carry = 0 on success.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
NEXTCPM_MEM_INIT:
	; Set CPM_USER_BANK to 0xFF (so user bank never collides with 0..11)
	LD A,0FFH
	LD (CPM_USER_BANK),A

	; Configure Line Table banks according to CFG_LINES_MODE (0=16K, 1=32K)
	XOR A
	LD (LINE_TABLE_BANK),A		; Bank 0: lines 0..16383
	LD A,(CFG_LINES_MODE)
	OR A
	JR NZ,NCMI_MODE_32K
	LD (LINE_TABLE_BANK_1),A	; 16K mode: LINE_TABLE_BANK_1 = 0
	LD HL,MAX_DOC_LINES_16K
	JR NCMI_SET_LIMIT
NCMI_MODE_32K:
	LD A,1
	LD (LINE_TABLE_BANK_1),A	; Bank 1: lines 16384..32767
	LD HL,MAX_DOC_LINES_32K
NCMI_SET_LIMIT:
	LD (MAX_DOC_LINES_LIMIT),HL

	; Populate EXT_BANK_TABLE with text slot banks 2..11 (10 banks)
	LD HL,EXT_BANK_TABLE
	LD B,10
	LD A,2
NCMI_BANK_LOOP:
	LD (HL),A
	INC HL
	INC A
	DJNZ NCMI_BANK_LOOP

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
	JR Z,NCSB_SRC_IS_USER

	; Case 1: Source is Far RAM Bank (B), Destination is Local RAM (DE)
	; Compute physical 8KB page: 32 + (Bank * 4) + (H >> 5)
	LD A,B
	ADD A,A
	ADD A,A
	LD C,A

	LD A,H
	RLCA
	RLCA
	RLCA
	AND 07H
	ADD A,C
	ADD A,NEXT_FAR_RAM_BASE_PAGE
	LD (NEXT_TARGET_FAR_PAGE),A

	; Adjust Far Source Address to Slot 1 ($2000..$3FFF)
	LD A,H
	AND 01FH
	OR 020H
	LD H,A
	JR NCSB_DO_TRANSFER

NCSB_SRC_IS_USER:
	; Case 2: Source is Local RAM (HL), Destination is Far RAM Bank
	LD A,(NEXT_CPY_DEST_BNK)
	LD B,A
	LD A,(CPM_USER_BANK)
	CP B
	JR Z,NCSB_LOCAL_TO_LOCAL

	; Compute physical 8KB page: 32 + (Bank * 4) + (D >> 5)
	LD A,B
	ADD A,A
	ADD A,A
	LD C,A

	LD A,D
	RLCA
	RLCA
	RLCA
	AND 07H
	ADD A,C
	ADD A,NEXT_FAR_RAM_BASE_PAGE
	LD (NEXT_TARGET_FAR_PAGE),A

	; Adjust Far Destination Address to Slot 1 ($2000..$3FFF)
	LD A,D
	AND 01FH
	OR 020H
	LD D,A

NCSB_DO_TRANSFER:
	DI
	; Save current Slot 1 page and map Far Page into Slot 1
	LD BC,NEXT_PORT_REG_SELECT
	LD A,051H
	OUT (C),A
	LD BC,NEXT_PORT_REG_DATA
	IN A,(C)
	LD (NEXT_SAVED_SLOT1_PAGE),A
	LD A,(NEXT_TARGET_FAR_PAGE)
	OUT (C),A

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

NCSB_LOCAL_TO_LOCAL:
	LD BC,(NEXT_CPY_LEN)
	LDIR
	RET

;------------------------------------------------------------------------------
; Far Memory Transfer State Variables
;------------------------------------------------------------------------------
NEXT_CPY_DEST_BNK:	DB	0
NEXT_CPY_SRC_BNK:	DB	0
NEXT_CPY_LEN:		DW	0
NEXT_SAVED_SLOT1_PAGE:	DB	0
NEXT_TARGET_FAR_PAGE:	DB	0

; End of HAL_NEXTCPM_MEMORY.ASM
