;==============================================================================
; HAL_NEXTCPM_STORAGE.ASM: Hardware Abstraction Layer - NextCPM File Storage
;
; Purpose:
;   Implements file operations, sequential/random FCB record I/O, and DMA
;   transfers for Profile 2 (CP/M on ZX Spectrum Next / NextCPM).
;   Utilizes CP/M BDOS services operating over NextCPM SD card drive images,
;   and provides BIOS USERF gate resolution and drive classification for
;   NextZXOS native host drive access (FAT32 SD card C:, RAM drive M:, etc.).
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; HAL Storage & File I/O API Entry Points
;------------------------------------------------------------------------------
HAL_STORAGE_OPEN	EQU	LOAD_FILE
HAL_STORAGE_MAKE	EQU	CREATE_SWAP_FILE
HAL_STORAGE_CLOSE	EQU	CLEANUP_SWAP_FILE

;------------------------------------------------------------------------------
; NEXTCPM_CALL_USERF: Indirect jump to NextCPM BIOS USERF function
; Inputs:
;   Registers prepared according to USERF function ID in C
;------------------------------------------------------------------------------
NEXTCPM_CALL_USERF:
	LD	HL,(NEXTCPM_USERF_VEC)
	JP	(HL)

;------------------------------------------------------------------------------
; NEXTCPM_INIT_DRV_TABLES: Query dynamic drive mapping tables via USERF C=2
; Outputs:
;   NEXTCPM_CPM_TO_NEXT, NEXTCPM_NEXT_TO_CPM populated.
;------------------------------------------------------------------------------
NEXTCPM_INIT_DRV_TABLES:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	C,2			; USERF C=2: Drive mapping tables
	CALL	NEXTCPM_CALL_USERF
	LD	(NEXTCPM_CPM_TO_NEXT),HL
	LD	(NEXTCPM_NEXT_TO_CPM),BC
	POP	HL
	POP	DE
	POP	BC
	RET

;------------------------------------------------------------------------------
; NEXTCPM_CLASSIFY_DRIVE: Check if drive is a NextZXOS native host drive
;
; Purpose:
;   Queries the NextZXOS -> CP/M drive mapping table returned by USERF C=2.
;   If the entry for the specified drive is 0xFF, it is a NextZXOS native
;   drive (e.g. FAT32 SD card C:, RAM drive M:).
;
; Inputs:
;   A = Drive byte (0=default, 1=A, 2=B... or 0..15 or 'A'..'P' or 'a'..'p')
;
; Outputs:
;   Carry = 1: Drive is a NextZXOS native drive (access via VFS / NEXTFS.PRL).
;   Carry = 0: Drive is a CP/M container drive or unmapped.
;   A = 0-based drive index (0=A..15=P) if Carry=1.
;
; Preserves / Modifies:
;   Modifies AF; preserves BC, DE, HL.
;------------------------------------------------------------------------------
NEXTCPM_CLASSIFY_DRIVE:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	; Check if A is 'a'..'p'
	CP	'a'
	JR	C,NCD_NOT_LOWER
	CP	'p'+1
	JR	NC,NCD_NOT_LOWER
	SUB	'a'
	JR	NCD_GOT_INDEX

NCD_NOT_LOWER:
	; Check if A is 'A'..'P'
	CP	'A'
	JR	C,NCD_NOT_UPPER
	CP	'P'+1
	JR	NC,NCD_NOT_UPPER
	SUB	'A'
	JR	NCD_GOT_INDEX

NCD_NOT_UPPER:
	; Check if 1-based (1..16)
	CP	17
	JR	NC,NCD_NOT_VALID
	OR	A
	JR	Z,NCD_GOT_INDEX
	DEC	A

NCD_GOT_INDEX:
	CP	16
	JR	NC,NCD_NOT_VALID
	LD	C,A			; C = 0-based drive index (0..15)
	LD	HL,(NEXTCPM_NEXT_TO_CPM)
	LD	A,H
	OR	L
	JR	Z,NCD_NOT_VALID		; Mapping table not yet initialized
	LD	E,C
	LD	D,0
	ADD	HL,DE
	LD	A,(HL)
	CP	0FFH
	JR	NZ,NCD_NOT_VALID

	; Entry 0xFF -> Native NextZXOS host drive!
	LD	A,C			; A = 0-based drive index (0=A..15=P)
	POP	HL
	POP	DE
	POP	BC
	SCF				; Carry = 1 (NextZXOS native drive)
	RET

NCD_NOT_VALID:
	POP	HL
	POP	DE
	POP	BC
	OR	A			; Carry = 0 (CP/M drive or invalid)
	RET

;------------------------------------------------------------------------------
; NextCPM BIOS USERF Vector & Mapping Table Pointers
;------------------------------------------------------------------------------
NEXTCPM_USERF_VEC:	DW	0
NEXTCPM_CPM_TO_NEXT:	DW	0
NEXTCPM_NEXT_TO_CPM:	DW	0
