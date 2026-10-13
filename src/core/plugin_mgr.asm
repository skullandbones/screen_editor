;==============================================================================
; PLUGIN_MGR.ASM: Core Subsystem - Far RAM Plugin Manager & VFS Subsystem
;
; Purpose:
;   Manages PRL/OVL plugin binary loading, relocation, slot registration,
;   context-aware plugin pop-up dialogs, and FAT filesystem VFS requests.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;==============================================================================
; Plugin Subsystem (CP/M 3 PRL & OVL Modular Architecture)
; Modular 4K/16K/32K Slots, Dynamic Multi-Bank Far RAM Allocation, TPA Overlay
;==============================================================================
; Plugin limits and capabilities are defined in include/plugin.inc

;------------------------------------------------------------------------------
; INIT_PLUGIN_REGISTRY: Initialize 256-byte plugin registry table and counters
;
; Purpose:
;   Zeros the entire 256-byte plugin registry array (8 slots x 32 bytes) and
;   resets active plugin count (PLUGIN_LOAD_COUNT) and borrowed Far RAM bank
;   counter (BORROWED_BANKS_CNT) to zero.
;
; Call Usage / Protocol:
;   Called via CALL from START during initial editor boot.
;
; Inputs:
;   None.
;
; Outputs:
;   PLUGIN_REGISTRY zeroed, PLUGIN_LOAD_COUNT = 0, BORROWED_BANKS_CNT = 0.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
INIT_PLUGIN_REGISTRY:
	LD HL,PLUGIN_REGISTRY
	LD (HL),0
	LD DE,PLUGIN_REGISTRY+1
	LD BC,(PLUGIN_MAX_SLOTS * PLUGIN_ENTRY_SIZE) - 1
	LDIR
	XOR A
	LD (PLUGIN_LOAD_COUNT),A
	LD (BORROWED_BANKS_CNT),A
	RET

;------------------------------------------------------------------------------
; BORROW_NEW_FAR_BANK: Borrow dedicated Far RAM bank for plugin execution
;
; Purpose:
;   Allocates a Far RAM bank from EXT_BANK_TABLE to store Far RAM plugins.
;   Protects bank 0 if actively editing a document by requiring >= 2 available
;   banks before borrowing.
;
; Call Usage / Protocol:
;   Called via CALL from ALLOC_FAR_PLUGIN_SLOT when no free space in banks.
;
; Inputs:
;   EXT_BANK_COUNT, EXT_BANK_TABLE, IN_EDITOR_MODE.
;
; Outputs:
;   Carry = 0 and A = allocated bank ID; Carry = 1 if no banks available.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
BORROW_NEW_FAR_BANK:
	LD A,(EXT_BANK_COUNT)
	OR A
	JR Z,BNFB_FAIL			; No banks left in EXT_BANK_TABLE
	CP 2
	JR NC,BNFB_OK		; >= 2 banks left: always safe to borrow!
	; Exactly 1 bank left. Only allow borrowing if not actively editing a
	; document
	LD A,(IN_EDITOR_MODE)
	OR A
	JR NZ,BNFB_FAIL		; Active document in editor: protect bank 0!
BNFB_OK:
	LD A,(EXT_BANK_COUNT)
	DEC A
	LD (EXT_BANK_COUNT),A		; Decrement available document banks
	LD E,A
	LD D,0
	LD HL,EXT_BANK_TABLE
	ADD HL,DE
	LD A,(HL)			; A = Stolen Far RAM Bank ID

	; Record in BORROWED_BANKS_TBL
	PUSH AF
	LD HL,BORROWED_BANKS_CNT
	LD C,(HL)
	INC (HL)
	LD B,0
	LD HL,BORROWED_BANKS_TBL
	ADD HL,BC
	POP AF
	LD (HL),A			; Store bank ID in table

	OR A				; Carry = 0
	RET
BNFB_FAIL:
	SCF				; Carry = 1
	RET

;------------------------------------------------------------------------------
; RELEASE_FAR_BANK: Release borrowed Far RAM bank back to document pool
;
; Purpose:
;   Removes bank ID from BORROWED_BANKS_TBL and restores it to EXT_BANK_TABLE,
;   incrementing EXT_BANK_COUNT so document line storage can reclaim it.
;
; Call Usage / Protocol:
;   Called via CALL from UNLOAD_PLUGIN_SLOT when all slots in bank freed.
;
; Inputs:
;   A = Far RAM bank ID to release.
;
; Outputs:
;   Bank returned to pool; BORROWED_BANKS_CNT decremented.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
RELEASE_FAR_BANK:
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL

	LD C,A				; C = Bank ID to release

	; 1. Remove from BORROWED_BANKS_TBL
	LD A,(BORROWED_BANKS_CNT)
	OR A
	JR Z,RFB_RETURN_TO_EXT
	LD B,A
	LD HL,BORROWED_BANKS_TBL
RFB_FIND_LOOP:
	LD A,(HL)
	CP C
	JR Z,RFB_FOUND
	INC HL
	DJNZ RFB_FIND_LOOP
	JR RFB_RETURN_TO_EXT

RFB_FOUND:
	DEC B
	JR Z,RFB_DEC_CNT
	LD D,H
	LD E,L
	INC HL
RFB_SHIFT_LOOP:
	LD A,(HL)
	LD (DE),A
	INC DE
	INC HL
	DJNZ RFB_SHIFT_LOOP
RFB_DEC_CNT:
	LD HL,BORROWED_BANKS_CNT
	DEC (HL)

RFB_RETURN_TO_EXT:
	; 2. Add bank back to EXT_BANK_TABLE
	LD A,(EXT_BANK_COUNT)
	LD E,A
	LD D,0
	LD HL,EXT_BANK_TABLE
	ADD HL,DE
	LD (HL),C			; Put bank C back
	LD HL,EXT_BANK_COUNT
	INC (HL)

RFB_DONE:
	POP HL
	POP DE
	POP BC
	POP AF
	RET

;------------------------------------------------------------------------------
; IS_RANGE_FREE_IN_BANK: Test if candidate page range is unoccupied in bank
;
; Purpose:
;   Iterates through all registered plugin slots using specified Far RAM bank,
;   testing whether candidate range [C .. C + D - 1] overlaps any active slot.
;
; Call Usage / Protocol:
;   Called via CALL from ALLOC_FAR_PLUGIN_SLOT slot sub-allocator loop.
;
; Inputs:
;   A = Far RAM bank ID.
;   C = Candidate base page index.
;   D = Required page count.
;
; Outputs:
;   Zero flag (Z) set if range is completely free; NZ if range conflicts.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
IS_RANGE_FREE_IN_BANK:
	PUSH BC
	PUSH DE
	PUSH HL

	; Guard: If target bank is PLUGIN_MGR_BANK, it is dedicated to
	; PLUGIN.PRL
	LD HL,PLUGIN_MGR_BANK
	CP (HL)
	JR Z,IRFIB_OVERLAP_DED

	; Candidate range: [C, C + E) in Bank A
	LD (IRF_TARGET_BANK),A
	LD A,C
	ADD A,E
	LD (IRF_CAND_EC),A

	; Scan slots 0..7
	LD B,0
IRFIB_LOOP:
	PUSH BC
	CALL GET_REGISTRY_ENTRY_PTR
	POP BC

	; Check SLOT_STATE at HL+22
	PUSH HL
	LD DE,22
	ADD HL,DE
	LD A,(HL)
	OR A
	JR Z,IRFIB_POP_NEXT

	; Check FAR_BANK at HL+24
	INC HL
	INC HL
	LD A,(IRF_TARGET_BANK)
	CP (HL)				; Compare with Target Bank
	JR NZ,IRFIB_POP_NEXT

	; Slot is in the same bank. Get Sj (at HL+25) and Pj (at HL+27)
	INC HL				; HL points to +25 (BASE_PAGE)
	LD E,(HL)			; E = Sj
	INC HL
	INC HL				; HL points to +27 (PAGE_COUNT)
	LD D,(HL)			; D = Pj
	POP HL				; Restore HL = entry ptr

	; Calculate Ej = Sj + Pj
	LD A,E				; A = Sj
	ADD A,D				; A = Ej

	; Overlap: (Sc < Ej) AND (Sj < Ec)
	; 1. If Sc >= Ej (i.e. Ej <= Sc), no overlap
	CP C
	JR Z,IRFIB_NEXT_SLOT
	JR C,IRFIB_NEXT_SLOT

	; 2. If Sj >= Ec (i.e. Ec <= Sj), no overlap
	LD A,(IRF_CAND_EC)
	CP E
	JR Z,IRFIB_NEXT_SLOT
	JR C,IRFIB_NEXT_SLOT

	; Overlap detected!
	SCF
	JR IRFIB_DONE

IRFIB_POP_NEXT:
	POP HL
IRFIB_NEXT_SLOT:
	INC B
	LD A,B
	CP PLUGIN_MAX_SLOTS
	JR NZ,IRFIB_LOOP

	; No active slot overlapped: range is free!
	OR A				; Carry = 0
IRFIB_DONE:
	POP HL
	POP DE
	POP BC
	RET

IRFIB_OVERLAP_DED:
	POP HL
	POP DE
	POP BC
	SCF				; Carry = 1 (bank is reserved/occupied)
	RET

;------------------------------------------------------------------------------
; ALLOC_FAR_PLUGIN_SLOT: Allocate contiguous page range in Far RAM for plugin
;
; Purpose:
;   Attempts to find contiguous free pages within already borrowed Far RAM
;   banks; if none found, attempts to borrow a new bank via BORROW_NEW_FAR_BANK.
;
; Call Usage / Protocol:
;   Called via CALL from LOAD_PLUGIN_BY_NAME for Far RAM execution plugins.
;
; Inputs:
;   D = Required page count.
;
; Outputs:
;   Carry = 0, A = Far RAM bank ID, C = Base page index; Carry = 1 on failure.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
ALLOC_FAR_PLUGIN_SLOT:
	; Input: A = CAN_SUBALLOC (1 = sub-allocate in shared Far RAM bank;
	;                          0 = dedicated bank at BASE_PAGE = 0)
	;        E = PAGE_COUNT needed (e.g. 18 for Beautify, 5 for ROT13)
	; Output: Carry=0 on success, A=FAR_BANK, C=BASE_PAGE, E=PAGE_COUNT
	;         Carry=1 on failure
	LD (ALLOC_SUBALLOC_FLAG),A
	LD A,E
	LD (ALLOC_PAGE_COUNT),A

	LD A,(ALLOC_SUBALLOC_FLAG)
	OR A
	JR Z,AFPS_DEDICATED_BANK

	; --- Sub-allocated Plugin Allocation (Shared banks) ---
	; Search existing borrowed banks for a free contiguous page range of
	; length E
	LD A,(BORROWED_BANKS_CNT)
	OR A
	JR Z,AFPS_NEED_NEW_BANK

	LD B,A
	LD HL,BORROWED_BANKS_TBL
AFPS_BANK_LOOP:
	PUSH BC
	PUSH HL
	LD A,(HL)			; A = bank ID
	LD (ALLOC_TEMP_BANK),A

	; Candidate search in bank: test C = 0, 1, 2, ... while C + PAGE_COUNT
	; <= 128
	LD C,0
AFPS_CAND_LOOP:
	PUSH BC
	LD A,(ALLOC_TEMP_BANK)
	LD HL,ALLOC_PAGE_COUNT
	LD E,(HL)
	CALL IS_RANGE_FREE_IN_BANK
	POP BC
	JR NC,AFPS_FOUND_IN_BANK
	INC C
	LD A,(ALLOC_PAGE_COUNT)
	ADD A,C				; A = C + PAGE_COUNT
	CP 129				; Must be <= 128
	JR C,AFPS_CAND_LOOP

	POP HL
	POP BC
	INC HL
	DJNZ AFPS_BANK_LOOP
	JR AFPS_NEED_NEW_BANK

	; --- Dedicated Bank Allocation (Always BASE_PAGE = 0) ---
AFPS_DEDICATED_BANK:
	; Search for any existing borrowed bank that is completely free (C=0,
	; E=128)
	LD A,(BORROWED_BANKS_CNT)
	OR A
	JR Z,AFPS_NEED_NEW_BANK

	LD B,A
	LD HL,BORROWED_BANKS_TBL
AFPS_DED_LOOP:
	PUSH BC
	PUSH HL
	LD A,(HL)			; A = bank ID
	LD (ALLOC_TEMP_BANK),A
	LD C,0
	LD E,128
	CALL IS_RANGE_FREE_IN_BANK
	JR NC,AFPS_FOUND_IN_BANK
	POP HL
	POP BC
	INC HL
	DJNZ AFPS_DED_LOOP
	JR AFPS_NEED_NEW_BANK

AFPS_NEED_NEW_BANK:
	CALL BORROW_NEW_FAR_BANK
	JR C,AFPS_FAIL

	; New bank always has page 0x00 free
	PUSH AF				; Preserve new bank ID
	LD C,0
	LD HL,ALLOC_PAGE_COUNT
	LD E,(HL)
	POP AF				; Restore new bank ID
	OR A				; Carry = 0
	RET

AFPS_FOUND_IN_BANK:
	LD A,C				; Preserve candidate start page
	POP HL
	POP BC
	LD C,A				; Restore candidate start page into C
	LD HL,ALLOC_PAGE_COUNT
	LD E,(HL)
	LD A,(ALLOC_TEMP_BANK)
	OR A				; Carry = 0
	RET

AFPS_FAIL:
	SCF				; Carry = 1
	RET

CALC_FAR_SLOT_ADDR:
	LD B,A
	CALL GET_REGISTRY_ENTRY_PTR
	LD DE,25
	ADD HL,DE
	LD A,(HL)
	LD H,A
	LD L,0
	RET

;------------------------------------------------------------------------------
; GET_REGISTRY_ENTRY_PTR: Compute pointer to 32-byte plugin registry descriptor
;
; Purpose:
;   Multiplies slot index in B (0..7) by 32 (PLUGIN_ENTRY_SIZE) and adds base
;   address of PLUGIN_REGISTRY table.
;
; Call Usage / Protocol:
;   Called via CALL across plugin management and dispatching routines.
;
; Inputs:
;   B = Plugin slot index (0..7).
;
; Outputs:
;   HL = Pointer to slot descriptor (PLUGIN_REGISTRY + B * 32).
;
; Preserves / Modifies:
;   Clobbers AF, DE, HL; preserves BC.
;------------------------------------------------------------------------------
GET_REGISTRY_ENTRY_PTR:
	LD A,B
	AND 07H
	LD L,A
	LD H,0
	ADD HL,HL			; * 2
	ADD HL,HL			; * 4
	ADD HL,HL			; * 8
	ADD HL,HL			; * 16
	ADD HL,HL			; * 32
	LD DE,PLUGIN_REGISTRY
	ADD HL,DE
	RET

;------------------------------------------------------------------------------
; LOAD_PLUGIN_BY_NAME: Load, relocate, and register PRL/OVL plugin binary
;
; Purpose:
;   Locates free slot in PLUGIN_REGISTRY, opens file via BDOS, reads 256-byte
;   PRL header, validates signature, allocates Far RAM pages or TPA slot, reads
;   code payload, applies relocation bitmap, and populates slot descriptor.
;
; Call Usage / Protocol:
;   Called via CALL from DO_PARSE_AND_LOAD_PLUGIN and Host API trampolines.
;
; Inputs:
;   DE = Pointer to null-terminated plugin filename string.
;
; Outputs:
;   Carry = 0 and A = allocated slot index on success; Carry = 1 on error.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
LOAD_PLUGIN_BY_NAME:
	PUSH DE				; Preserve filename string pointer

	; Find free slot in PLUGIN_REGISTRY
	LD B,0
LPBN_FIND_FREE:
	PUSH BC
	CALL GET_REGISTRY_ENTRY_PTR
	LD DE,22
	ADD HL,DE
	LD A,(HL)
	POP BC
	OR A
	JR Z,LPBN_FOUND_FREE
	INC B
	LD A,B
	CP PLUGIN_MAX_SLOTS
	JR NZ,LPBN_FIND_FREE

LPBN_NO_FREE_SLOT:
	POP DE
	SCF				; All slots full
	RET

LPBN_FOUND_FREE:
	LD A,B
	LD (PLUGIN_CUR_SLOT),A

	POP HL				; HL = filename string pointer
	CALL PARSE_STRING_TO_PLUGIN_FCB

	; Query current BDOS user area (BDOS 32, E=0xFF) into PLUGIN_ORIG_USER
	LD E,0FFH
	LD C,32
	CALL BDOS_ENTRY
	LD (PLUGIN_ORIG_USER),A

	; Switch BDOS user area to target user area (PLUGIN_USER_AREA)
	LD A,(PLUGIN_USER_AREA)
	LD E,A
	LD C,32
	CALL BDOS_ENTRY

	; Check if extension in PLUGIN_FCB is blank ("   ")
	LD A,(PLUGIN_FCB+9)
	CP ' '
	JR NZ,LPBN_DO_OPEN_DIRECT

	; Auto-try .PRL extension first
	LD HL,PLUGIN_FCB+9
	LD (HL),'P'
	INC HL
	LD (HL),'R'
	INC HL
	LD (HL),'L'
	LD DE,PLUGIN_FCB
	LD C,15				; BDOS Open File
	CALL BDOS_ENTRY
	CP 0FFH
	JR NZ,LPBN_OPEN_OK

	; .PRL not found -> try .OVL extension
	LD HL,PLUGIN_FCB+9
	LD (HL),'O'
	INC HL
	LD (HL),'V'
	INC HL
	LD (HL),'L'
	; Reset extent/record fields before re-open
	XOR A
	LD (PLUGIN_FCB+12),A		; EX = 0
	LD (PLUGIN_FCB+13),A		; S1 = 0
	LD (PLUGIN_FCB+14),A		; S2 = 0
	LD (PLUGIN_FCB+15),A		; RC = 0
	LD (PLUGIN_FCB+32),A		; CR = 0
	LD DE,PLUGIN_FCB
	LD C,15				; BDOS Open File
	CALL BDOS_ENTRY
	CP 0FFH
	JR NZ,LPBN_OPEN_OK
	JP LPBN_NOT_FOUND

LPBN_DO_OPEN_DIRECT:
	LD DE,PLUGIN_FCB
	LD C,15				; BDOS Open File
	CALL BDOS_ENTRY
	CP 0FFH
	JP Z,LPBN_NOT_FOUND

LPBN_OPEN_OK:

	; Set BDOS DMA to scratch buffer at LINE_STORAGE + 4096
	LD DE,LINE_STORAGE + 4096
	LD C,26
	CALL BDOS_ENTRY

	; Read first 2 sectors (256-byte header)
	LD DE,PLUGIN_FCB
	LD C,20
	CALL BDOS_ENTRY
	OR A
	JP NZ,LPBN_READ_ERR

	LD DE,LINE_STORAGE + 4096 + 128
	LD C,26
	CALL BDOS_ENTRY

	LD DE,PLUGIN_FCB
	LD C,20
	CALL BDOS_ENTRY
	OR A
	JP NZ,LPBN_READ_ERR

	; Parse Capabilities & Size Class from Header
	; Capabilities word at offset 1Ch (LINE_STORAGE + 4096 + 28)
	LD A,(LINE_STORAGE + 4096 + 28)
	AND CAP_SIZE_MASK		; Bits 7..6

	; Map size bits to SIZE_CLASS (0=4K, 1=8K, 2=16K, 3=32K)
	OR A
	JR NZ,LPBN_CHK_8K
	XOR A
	LD (LOAD_SIZE_CLASS),A
	; Check PROG_SIZE <= 4096
	LD HL,(LINE_STORAGE + 4096 + 1)
	LD DE,4097
	CALL CMP_HL_DE
	JP NC,LPBN_TOO_LARGE
	JP LPBN_CALC_PAYLOAD

LPBN_CHK_8K:
	CP CAP_SIZE_8K
	JR NZ,LPBN_CHK_16K
	LD A,1
	LD (LOAD_SIZE_CLASS),A
	; Check PROG_SIZE <= 8192
	LD HL,(LINE_STORAGE + 4096 + 1)
	LD DE,8193
	CALL CMP_HL_DE
	JP NC,LPBN_TOO_LARGE
	; Check TPA restriction: if bit 0 set, footprint must fit in
	; LINE_STORAGE_SIZE
	LD A,(LINE_STORAGE + 4096 + 28)
	BIT 0,A
	JR Z,LPBN_CALC_PAYLOAD		; Pure Far 8K plugin -> proceed

	; 8K plugin with TPA: verify total TPA footprint <= LINE_STORAGE_SIZE
	; (5120)
	LD HL,(LINE_STORAGE + 4096 + 1)		; PROG_SIZE
	LD DE,(LINE_STORAGE + 4096 + 7)		; LOAD_ADDR
	LD A,D
	OR E
	JR NZ,LPBN_8K_NO_BM
	; PRL: include bitmap (PROG_SIZE + 7) / 8
	PUSH HL
	LD DE,7
	ADD HL,DE
	SRL H
	RR L
	SRL H
	RR L
	SRL H
	RR L
	POP DE
	ADD HL,DE				; PROG_SIZE + bitmap
LPBN_8K_NO_BM:
	LD DE,(LINE_STORAGE + 4096 + 4)		; BSS_SIZE
	ADD HL,DE
	INC H					; + 256 bytes for header
	LD DE,LINE_STORAGE_SIZE + 1
	CALL CMP_HL_DE
	JP NC,LPBN_TOO_LARGE
	JP LPBN_CALC_PAYLOAD

LPBN_CHK_16K:
	CP CAP_SIZE_16K
	JR NZ,LPBN_CHK_32K
	LD A,2
	LD (LOAD_SIZE_CLASS),A
	; Check PROG_SIZE <= 16384
	LD HL,(LINE_STORAGE + 4096 + 1)
	LD DE,16385
	CALL CMP_HL_DE
	JP NC,LPBN_TOO_LARGE
	; Check TPA restriction: bit 0 of capabilities MUST NOT be set
	LD A,(LINE_STORAGE + 4096 + 28)
	BIT 0,A
	JP NZ,LPBN_TOO_LARGE
	JR LPBN_CALC_PAYLOAD

LPBN_CHK_32K:
	LD A,3
	LD (LOAD_SIZE_CLASS),A
	; Check PROG_SIZE <= 32768
	LD HL,(LINE_STORAGE + 4096 + 1)
	LD DE,8001H
	CALL CMP_HL_DE
	JP NC,LPBN_TOO_LARGE
	; Check TPA restriction: bit 0 of capabilities MUST NOT be set
	LD A,(LINE_STORAGE + 4096 + 28)
	BIT 0,A
	JP NZ,LPBN_TOO_LARGE

LPBN_CALC_PAYLOAD:
	; Calculate sectors for code + relocation bitmap
	LD HL,(LINE_STORAGE + 4096 + 1)		; PROG_SIZE
	LD DE,(LINE_STORAGE + 4096 + 7)		; LOAD_ADDR
	LD A,D
	OR E
	JR NZ,LPBN_PAYLOAD_OVL

	; If purely Far RAM execution (no TPA), skip trailing bitmap
	LD A,(LINE_STORAGE + 4096 + 28)
	BIT 0,A
	JR Z,LPBN_PAYLOAD_OVL

	; PRL bitmap size: (PROG_SIZE + 7) / 8
	PUSH HL
	LD DE,7
	ADD HL,DE
	SRL H
	RR L
	SRL H
	RR L
	SRL H
	RR L
	POP DE
	ADD HL,DE				; PROG_SIZE + bitmap
LPBN_PAYLOAD_OVL:
	LD DE,127
	ADD HL,DE
	SRL H
	RR L
	SRL H
	RR L
	SRL H
	RR L
	SRL H
	RR L
	SRL H
	RR L
	SRL H
	RR L
	SRL H
	RR L
	LD (PAYLOAD_SECTORS_REMAIN),HL		; 16-bit sector count (0..256)

	; Determine sub-allocation vs dedicated bank:
	; Sub-allocated if bit 0 of capabilities (CAP_TPA_EXEC) is set
	LD A,(LINE_STORAGE + 4096 + 28)
	BIT 0,A
	JR Z,LPBN_DEDICATED_PAGES

	; Sub-allocated: PAGE_COUNT = (PAYLOAD_SECTORS_REMAIN + 2 + 1) / 2
	LD HL,(PAYLOAD_SECTORS_REMAIN)
	INC HL
	INC HL
	INC HL
	SRL H
	RR L
	LD E,L					; E = PAGE_COUNT
	LD A,1					; A = CAN_SUBALLOC (1)
	JR LPBN_DO_ALLOC

LPBN_DEDICATED_PAGES:
	LD A,(LOAD_SIZE_CLASS)
	CP 1
	JR NZ,LPBN_DED_NOT_8K
	LD E,32					; 8K: 32 pages
	JR LPBN_DED_GOT_PAGES
LPBN_DED_NOT_8K:
	CP 2
	JR NZ,LPBN_DED_IS_32K
	LD E,64					; 16K: 64 pages
	JR LPBN_DED_GOT_PAGES
LPBN_DED_IS_32K:
	LD E,128				; 32K: 128 pages
LPBN_DED_GOT_PAGES:
	XOR A					; A = CAN_SUBALLOC (0)

LPBN_DO_ALLOC:
	CALL ALLOC_FAR_PLUGIN_SLOT
	JP C,LPBN_ALLOC_FAIL

	; ALLOC_FAR_PLUGIN_SLOT returned A=FAR_BANK, C=BASE_PAGE, E=PAGE_COUNT
	LD (LOAD_FAR_BANK),A
	LD A,C
	LD (LOAD_BASE_PAGE),A
	LD A,E
	LD (LOAD_PAGE_COUNT),A

	; Slot base address: H = BASE_PAGE, L = 0
	LD A,(LOAD_BASE_PAGE)
	LD H,A
	LD L,0
	LD (FAR_SLOT_BASE_ADDR),HL

	; Copy 256-byte header to LOAD_FAR_BANK at FAR_SLOT_BASE_ADDR
	PUSH IX
	LD B,0F4H
	LD A,(LOAD_FAR_BANK)
	LD D,A
	LD A,(CPM_USER_BANK)
	LD E,A
	LD HL,256
	IFDEF TARGET_NEXT
	CALL NEXT_SYSSETCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	PUSH IX
	LD B,0F5H
	LD HL,LINE_STORAGE + 4096
	LD DE,(FAR_SLOT_BASE_ADDR)
	IFDEF TARGET_NEXT
	CALL NEXT_SYSBNKCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	CALL REGISTER_SLOT_METADATA

	LD HL,(FAR_SLOT_BASE_ADDR)
	INC H					; + 256 bytes
	LD (FAR_SECT_DEST),HL

LPBN_SECTOR_LOOP:
	LD HL,(PAYLOAD_SECTORS_REMAIN)
	LD A,H
	OR L
	JR Z,LPBN_SECTORS_DONE
	DEC HL
	LD (PAYLOAD_SECTORS_REMAIN),HL

	LD DE,LINE_STORAGE + 4096
	LD C,26
	CALL BDOS_ENTRY

	LD DE,PLUGIN_FCB
	LD C,20
	CALL BDOS_ENTRY
	OR A
	JR NZ,LPBN_SECTOR_EOF

	PUSH IX
	LD B,0F4H
	LD A,(LOAD_FAR_BANK)
	LD D,A
	LD A,(CPM_USER_BANK)
	LD E,A
	LD HL,128
	IFDEF TARGET_NEXT
	CALL NEXT_SYSSETCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	PUSH IX
	LD B,0F5H
	LD HL,LINE_STORAGE + 4096
	LD DE,(FAR_SECT_DEST)
	IFDEF TARGET_NEXT
	CALL NEXT_SYSBNKCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	LD HL,(FAR_SECT_DEST)
	LD DE,128
	ADD HL,DE
	LD (FAR_SECT_DEST),HL

	; Guard: prevent Far RAM writes crossing into Common RAM (>= 8000h)
	LD A,H
	CP 080H
	JR NC,LPBN_SECTORS_DONE

	JR LPBN_SECTOR_LOOP

LPBN_SECTOR_EOF:
LPBN_SECTORS_DONE:
	LD DE,PLUGIN_FCB
	LD C,16
	CALL BDOS_ENTRY

	; Restore BDOS user area to PLUGIN_ORIG_USER
	LD A,(PLUGIN_ORIG_USER)
	LD E,A
	LD C,32
	CALL BDOS_ENTRY

	LD DE,0080H
	LD C,26
	CALL BDOS_ENTRY

	LD A,(PLUGIN_CUR_SLOT)
	OR A
	RET

LPBN_READ_ERR:
	LD A,(PLUGIN_CUR_SLOT)
	CALL UNLOAD_PLUGIN_SLOT
LPBN_NOT_FOUND:
LPBN_TOO_LARGE:
LPBN_ALLOC_FAIL:
	; Restore BDOS user area to PLUGIN_ORIG_USER
	LD A,(PLUGIN_ORIG_USER)
	LD E,A
	LD C,32
	CALL BDOS_ENTRY

	LD DE,0080H
	LD C,26
	CALL BDOS_ENTRY
	SCF
	RET

;------------------------------------------------------------------------------
; REGISTER_SLOT_METADATA: Populate 32-byte plugin descriptor in registry
;
; Purpose:
;   Copies plugin name, capabilities bitmask, execution mode, Far RAM bank ID,
;   base page, size class, and page count into PLUGIN_REGISTRY entry for slot B.
;
; Call Usage / Protocol:
;   Called via CALL from LOAD_PLUGIN_BY_NAME after successful payload read.
;
; Inputs:
;   B = Slot index (0..7), plus staged metadata variables.
;
; Outputs:
;   Registry entry initialized; PLUGIN_LOAD_COUNT incremented.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
REGISTER_SLOT_METADATA:
	LD A,(PLUGIN_CUR_SLOT)
	LD B,A
	CALL GET_REGISTRY_ENTRY_PTR
	PUSH HL

	; Copy Name (16 bytes)
	LD DE,LINE_STORAGE + 4096 + 12
	EX DE,HL
	LD BC,16
	LDIR

	; PROG_SIZE (word)
	LD HL,(LINE_STORAGE + 4096 + 1)
	LD A,L
	LD (DE),A
	INC DE
	LD A,H
	LD (DE),A
	INC DE

	; LOAD_ADDR (word)
	LD HL,(LINE_STORAGE + 4096 + 7)
	LD A,L
	LD (DE),A
	INC DE
	LD A,H
	LD (DE),A
	INC DE

	; CAPABILITIES (word)
	LD HL,(LINE_STORAGE + 4096 + 28)
	LD A,L
	LD (DE),A
	INC DE
	LD A,H
	LD (DE),A
	INC DE

	; SLOT_STATE = 1
	LD A,1
	LD (DE),A
	INC DE

	; EXEC_MODE:
	; Plugin runs in FAR RAM if CAP_FAR_EXEC (bit 1) is set AND:
	;   - either LOAD_ADDR != 0 (OVL with target address)
	;   - or BASE_PAGE == 0 (PRL at origin 0100H)
	LD A,(LINE_STORAGE + 4096 + 28)
	AND 02H				; Bit 1: FAR_EXEC
	JR Z,RSM_MODE_TPA

	LD HL,(LINE_STORAGE + 4096 + 7)		; LOAD_ADDR
	LD A,H
	OR L
	JR NZ,RSM_MODE_FAR		; OVL with non-zero base -> FAR
	LD A,(LOAD_BASE_PAGE)
	OR A
	JR Z,RSM_MODE_FAR		; Base page 0 -> FAR
RSM_MODE_TPA:
	XOR A
	JR RSM_SAVE_MODE
RSM_MODE_FAR:
	LD A,1
RSM_SAVE_MODE:
	LD (DE),A
	INC DE

	; +24: FAR_BANK
	LD A,(LOAD_FAR_BANK)
	LD (DE),A
	INC DE

	; +25: BASE_PAGE
	LD A,(LOAD_BASE_PAGE)
	LD (DE),A
	INC DE

	; +26: SIZE_CLASS
	LD A,(LOAD_SIZE_CLASS)
	LD (DE),A
	INC DE

	; +27: PAGE_COUNT
	LD A,(LOAD_PAGE_COUNT)
	LD (DE),A
	INC DE

	; +28: File type ('P' = PRL, 'O' = OVL)
	LD A,(PLUGIN_FCB+9)
	LD (DE),A

	POP HL
	LD HL,PLUGIN_LOAD_COUNT
	INC (HL)
	LD A,(PLUGIN_CUR_SLOT)
	OR A				; Clear Carry
	RET

;------------------------------------------------------------------------------
; UNLOAD_PLUGIN_SLOT: Unregister plugin and release resources for slot A
;
; Purpose:
;   Marks registry entry for slot A as inactive, decrements PLUGIN_LOAD_COUNT,
;   and checks if the hosting Far RAM bank has no other active slots; if empty,
;   releases the bank back to document storage via RELEASE_FAR_BANK.
;
; Call Usage / Protocol:
;   Called via CALL from Plugin Manager and Host API TRAMP_UNLOAD_SLOT.
;
; Inputs:
;   A = Slot number (0..7).
;
; Outputs:
;   Slot freed; hosting bank released if unused.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
UNLOAD_PLUGIN_SLOT:
	LD B,A
	CALL GET_REGISTRY_ENTRY_PTR
	PUSH HL
	LD DE,22
	ADD HL,DE
	LD A,(HL)			; SLOT_STATE
	POP HL
	OR A
	RET Z				; Already free

	; If unloading PLUGIN_MGR_SLOT, reset PLUGIN_MGR_SLOT to 0xFF
	LD A,(PLUGIN_MGR_SLOT)
	CP B
	JR NZ,UPS_NOT_MGR
	LD A,0FFH
	LD (PLUGIN_MGR_SLOT),A
	LD (HOST_API_MGR_SLOT),A
UPS_NOT_MGR:

	; Read slot's FAR_BANK at offset +24
	PUSH HL
	LD DE,24
	ADD HL,DE
	LD C,(HL)			; C = slot's FAR_BANK
	POP HL

	; Clear 32-byte entry
	PUSH BC
	LD (HL),0
	LD D,H
	LD E,L
	INC DE
	LD BC,PLUGIN_ENTRY_SIZE - 1
	LDIR
	LD HL,PLUGIN_LOAD_COUNT
	DEC (HL)
	POP BC				; C = released slot's FAR_BANK

	; Check if any remaining active slot still uses bank C
	LD A,C
	OR A
	RET Z				; Bank 0: nothing to release
	LD B,0
UPS_CHECK_BANK_LOOP:
	PUSH BC
	CALL GET_REGISTRY_ENTRY_PTR
	LD DE,22
	ADD HL,DE
	LD A,(HL)			; SLOT_STATE
	POP BC
	OR A
	JR Z,UPS_CHECK_NEXT
	INC HL
	INC HL				; Points to offset +24 (FAR_BANK)
	LD A,(HL)
	CP C
	RET Z		; Another active slot uses bank C! Do not release.
UPS_CHECK_NEXT:
	INC B
	LD A,B
	CP PLUGIN_MAX_SLOTS
	JR NZ,UPS_CHECK_BANK_LOOP

	; No active slot uses bank C: release bank C back to EXT_BANK_TABLE
	LD A,C
	CALL RELEASE_FAR_BANK
	RET

;------------------------------------------------------------------------------
; EXEC_PLUGIN_SLOT: Execute main action (Action 0) of registered plugin
;
; Purpose:
;   Sets action index C = 0 and falls through into EXEC_PLUGIN_SLOT_ACTION.
;
; Call Usage / Protocol:
;   Called via CALL to execute primary entry point of plugin in slot A.
;
; Inputs:
;   A = Slot number (0..7).
;
; Outputs:
;   Plugin return code in A; flags set according to execution result.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
EXEC_PLUGIN_SLOT:
	LD C,0				; Action 0: Main Execution
	; Fall through to EXEC_PLUGIN_SLOT_ACTION

;------------------------------------------------------------------------------
; EXEC_PLUGIN_SLOT_ACTION: Execute specified action index for plugin in slot A
;
; Purpose:
;   Synchronizes screen geometry and context in Host API table, checks plugin
;   execution mode (TPA vs Far RAM), and dispatches to EXEC_PLUGIN_TPA or
;   EXEC_PLUGIN_FAR.
;
; Call Usage / Protocol:
;   Called via CALL from EXEC_PLUGIN_SLOT, popup menus, and about screens.
;
; Inputs:
;   A = Slot number (0..7).
;   C = Action index (0 = Main, 1 = Config/About, 2 = Context Popup).
;
; Outputs:
;   Plugin return code in A (0 = Clean, 1 = Active line dirty, 2 = Doc dirty).
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
EXEC_PLUGIN_SLOT_ACTION:
	LD (PLUGIN_CUR_SLOT),A
	LD A,C
	LD (PLUGIN_ACTION_INDEX),A
	XOR A
	LD (PLUGIN_RET_CODE),A
	; Synchronize screen dimensions and context in Host API (+14, +15, +16,
	; +17)
	LD A,(ACTIVE_COLS)
	LD (HOST_API_COLS),A
	LD A,(POPUP_CONTEXT_ID)
	LD (HOST_API_CONTEXT),A
	LD A,(ACTIVE_ROWS)
	LD (HOST_API_ROWS),A
	LD A,(PLUGIN_MGR_SLOT)
	LD (HOST_API_MGR_SLOT),A
	LD A,(PLUGIN_CUR_SLOT)
	LD B,A
	CALL GET_REGISTRY_ENTRY_PTR
	LD DE,22
	ADD HL,DE
	LD A,(HL)
	OR A
	RET Z				; Empty slot

	INC HL				; Offset +23: EXEC_MODE
	LD A,(HL)
	OR A
	JR NZ,EPS_DO_FAR
	LD A,(PLUGIN_CUR_SLOT)
	JP EXEC_PLUGIN_TPA
EPS_DO_FAR:
	LD A,(PLUGIN_CUR_SLOT)
	JP EXEC_PLUGIN_FAR

;------------------------------------------------------------------------------
; EXEC_PLUGIN_TPA: Execute plugin via TPA overlay at LINE_STORAGE (0x0100)
;
; Purpose:
;   Flushes dirty cache, copies plugin pages from Far RAM staging storage into
;   TPA at LINE_STORAGE, passes Host API pointer in IY, calls entry point at
;   0x0100 + C * 3, and processes returned dirty flags upon completion.
;
; Call Usage / Protocol:
;   Called via JP from EXEC_PLUGIN_SLOT_ACTION for TPA-mode plugins.
;
; Inputs:
;   PLUGIN_CUR_SLOT, PLUGIN_ACTION_INDEX.
;
; Outputs:
;   Plugin return code in A.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
EXEC_PLUGIN_TPA:
	XOR A
	LD (PLUGIN_IS_FAR_EXEC),A

	; Read slot's Far RAM bank, base address, and page count
	LD A,(PLUGIN_CUR_SLOT)
	LD B,A
	CALL GET_REGISTRY_ENTRY_PTR
	PUSH HL
	LD DE,24
	ADD HL,DE
	LD A,(HL)			; A = FAR_BANK
	LD (EP_TPA_FAR_BANK),A
	INC HL				; Offset +25: BASE_PAGE
	LD C,(HL)			; C = BASE_PAGE
	INC HL				; Offset +26: SIZE_CLASS
	INC HL				; Offset +27: PAGE_COUNT
	LD D,(HL)			; D = PAGE_COUNT
	LD E,0
	LD (EP_TPA_COPY_LEN),DE		; DE = PAGE_COUNT * 256
	LD H,C				; H = BASE_PAGE
	LD L,0
	LD (FAR_SLOT_BASE_ADDR),HL	; HL = BASE_PAGE * 256
	POP HL

	CALL FLUSH_DIRTY_CACHE
	LD HL,0FFFFH
	LD (CACHE_START_ROW),HL

	CALL GET_CUR_ROW_LEN
	LD (ACTIVE_LINE_LEN),DE

	; Copy exact PAGE_COUNT pages from Far RAM to LINE_STORAGE
	PUSH IX
	LD B,0F4H
	LD A,(CPM_USER_BANK)
	LD D,A
	LD A,(EP_TPA_FAR_BANK)
	LD E,A
	LD HL,(EP_TPA_COPY_LEN)
	IFDEF TARGET_NEXT
	CALL NEXT_SYSSETCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	PUSH IX
	LD B,0F5H
	LD HL,(FAR_SLOT_BASE_ADDR)
	LD DE,LINE_STORAGE
	IFDEF TARGET_NEXT
	CALL NEXT_SYSBNKCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	; Check if relocation needed (LOAD_ADDR == 0)
	LD HL,(LINE_STORAGE + 7)
	LD A,H
	OR L
	JR NZ,EPT_CALL_ENTRY

	; Target page = high_byte(LINE_STORAGE + 256)
	LD HL,LINE_STORAGE + 256
	LD A,H
	DEC A				; Bias = Target Page - 1
	LD (RELOC_BIAS),A

	LD HL,LINE_STORAGE + 256
	LD DE,(LINE_STORAGE + 1)	; PROG_SIZE
	PUSH HL
	ADD HL,DE
	EX DE,HL			; DE = bitmap ptr
	POP HL				; HL = code ptr
	LD BC,(LINE_STORAGE + 1)
	CALL RELOCATE_PRL_LOOP

EPT_CALL_ENTRY:
	LD IX,PLUGIN_HOST_API
	LD IY,PLUGIN_HOST_API
	LD HL,LINE_STORAGE + 256
	LD A,(PLUGIN_ACTION_INDEX)
	OR A
	JR Z,EPT_NO_OFFSET
	LD C,A
	ADD A,A
	ADD A,C
	LD C,A
	LD B,0
	ADD HL,BC
EPT_NO_OFFSET:
	CALL CALL_HL_ENTRY

	PUSH AF
	CALL RELOAD_CACHE_WINDOW_FORCE
	POP AF

	LD (PLUGIN_RET_CODE),A
	CP 1
	JR Z,EPT_LINE_DIRTY
	CP 2
	JR Z,EPT_DOC_DIRTY
	OR A
	RET

EPT_LINE_DIRTY:
	LD A,1
	LD (DOC_MODIFIED),A
	LD (ACTIVE_LINE_DIRTY),A
	CALL COMMIT_ACTIVE_LINE
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	OR A
	RET

EPT_DOC_DIRTY:
	LD A,1
	LD (DOC_MODIFIED),A
	LD (IN_EDITOR_MODE),A
	XOR A
	LD (IS_SPLASH_SCREEN),A
	LD HL,0FFFFH
	LD (ACTIVE_LINE_ROW),HL
	LD (ACTIVE_LINE_DIRTY),A
	CALL CHECKOUT_ACTIVE_LINE
	CALL RELOAD_CACHE_WINDOW_FORCE
	CALL CONSTRAIN_CURSOR_VIEWPORT
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	OR A
	RET

;------------------------------------------------------------------------------
; CALL_HL_ENTRY: Indirect jump helper to address in HL
;
; Purpose:
;   Executes JP (HL) to jump to indirect subroutine or entry point.
;
; Call Usage / Protocol:
;   Called via CALL to invoke dynamically computed entry points.
;
; Inputs:
;   HL = Target entry address.
;
; Outputs:
;   Returns results from called target function.
;
; Preserves / Modifies:
;   Depends on called function.
;------------------------------------------------------------------------------
CALL_HL_ENTRY:
	JP (HL)

;------------------------------------------------------------------------------
; EXEC_PLUGIN_FAR: Execute Far RAM resident plugin via HBIOS HB_BNKCALL
;
; Purpose:
;   Sets PLUGIN_IS_FAR_EXEC flag, initializes entry address in IX, sets IY to
;   PLUGIN_HOST_API, sets Far RAM bank ID in A, and invokes HBIOS bank-call
;   at 0xFFF9 (HB_BNKCALL).
;
; Call Usage / Protocol:
;   Called via JP from EXEC_PLUGIN_SLOT_ACTION for Far RAM plugins.
;
; Inputs:
;   PLUGIN_CUR_SLOT, PLUGIN_ACTION_INDEX.
;
; Outputs:
;   Plugin return code in A.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
EXEC_PLUGIN_FAR:
	LD A,1
	LD (PLUGIN_IS_FAR_EXEC),A
	CALL GET_CUR_ROW_LEN
	LD (ACTIVE_LINE_LEN),DE

	LD A,(PLUGIN_CUR_SLOT)
	LD B,A
	CALL GET_REGISTRY_ENTRY_PTR
	LD DE,24
	ADD HL,DE
	LD A,(HL)			; A = FAR_BANK
	LD (PLUGIN_FAR_BANK),A		; Set current bank for host trampolines
	INC HL
	LD A,(HL)			; A = BASE_PAGE
	INC A				; +1 page for header
	LD H,A
	LD L,0

	LD A,(PLUGIN_ACTION_INDEX)
	OR A
	JR Z,EPF_NO_OFFSET
	LD C,A
	ADD A,A
	ADD A,C
	LD C,A
	LD B,0
	ADD HL,BC
EPF_NO_OFFSET:
	PUSH HL
	POP IX				; IX = entry point
	LD IY,PLUGIN_HOST_API
	LD A,(PLUGIN_FAR_BANK)
	DI
	CALL 0FFF9H			; HB_BNKCALL at 0xFFF9
	EI

	PUSH AF
	XOR A
	LD (PLUGIN_IS_FAR_EXEC),A
	POP AF

	LD (PLUGIN_RET_CODE),A
	CP 1
	JP Z,EPT_LINE_DIRTY
	CP 2
	JP Z,EPT_DOC_DIRTY
	OR A
	RET

;------------------------------------------------------------------------------
; RELOCATE_PRL_LOOP: Apply CP/M 3 PRL relocation bitmap to code payload
;
; Purpose:
;   Iterates through bitmask in DE bit-by-bit; for each '1' bit, adds base page
;   offset (RELOC_BIAS) to the word/byte pointed to by HL in payload code.
;
; Call Usage / Protocol:
;   Called via CALL from LOAD_PLUGIN_BY_NAME during PRL file loading.
;
; Inputs:
;   HL = Pointer to payload code in memory.
;   DE = Pointer to relocation bitmap stream.
;   BC = Payload byte count.
;   RELOC_BIAS = Relocation page offset to add.
;
; Outputs:
;   Payload code relocated in-place.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
RELOCATE_PRL_LOOP:
	LD A,B
	OR C
	RET Z
	LD A,(DE)
	INC DE
	LD (RELOC_CUR_BYTE),A
	LD A,8
RPL_BIT:
	PUSH AF
	LD A,(RELOC_CUR_BYTE)
	RLA
	LD (RELOC_CUR_BYTE),A
	JR NC,RPL_SKIP
	LD A,(RELOC_BIAS)
	ADD A,(HL)
	LD (HL),A
RPL_SKIP:
	INC HL
	DEC BC
	LD A,B
	OR C
	JR Z,RPL_DONE
	POP AF
	DEC A
	JR NZ,RPL_BIT
	JR RELOCATE_PRL_LOOP
RPL_DONE:
	POP AF
	RET

;------------------------------------------------------------------------------
; PARSE_STRING_TO_PLUGIN_FCB: Parse filename string into PLUGIN_FCB
;
; Purpose:
;   Copies default WORK_FCB template to PLUGIN_FCB, calls PARSE_STRING_TO_FCB
;   to parse filename and user prefix at HL, and stores parsed user area.
;
; Call Usage / Protocol:
;   Called via CALL before opening plugin binaries from disk.
;
; Inputs:
;   HL = Pointer to null-terminated plugin filename string.
;
; Outputs:
;   PLUGIN_FCB initialized; PLUGIN_USER_AREA populated.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
PARSE_STRING_TO_PLUGIN_FCB:
	PUSH BC
	PUSH DE
	PUSH HL
	LD HL,WORK_FCB
	LD DE,PLUGIN_FCB
	LD BC,36
	LDIR
	POP HL
	PUSH HL
	CALL PARSE_STRING_TO_FCB
	LD A,(WORK_FCB_USER)
	LD (PLUGIN_USER_AREA),A
	LD A,(DOC_USER_NUM)
	LD (WORK_FCB_USER),A
	LD HL,PLUGIN_FCB
	LD DE,WORK_FCB
	LD B,36
PSTPF_SWAP:
	LD A,(DE)
	LD C,(HL)
	LD (DE),C
	LD (HL),A
	INC DE
	INC HL
	DJNZ PSTPF_SWAP
	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; DO_PLUGIN_SCREEN: Display Plugin Manager interface or run plugin screen
;
; Purpose:
;   Initializes screen context for plugin manager, ensures PLUGIN.PRL is loaded,
;   invokes action 0 (Manager UI) of PLUGIN.PRL, and handles returned status.
;
; Call Usage / Protocol:
;   Called via CALL from editor command handlers (Ctrl+P / F4).
;
; Inputs:
;   None.
;
; Outputs:
;   Plugin UI executed; returns to caller.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_PLUGIN_SCREEN:
	XOR A
	LD (PLUGIN_RET_CODE),A
	CALL ENSURE_PLUGIN_MGR_LOADED
	JR C,DPS_MISSING
DPS_LOOP:
	LD C,0				; Action 0: Plugin Manager
	CALL EXEC_PLUGIN_MGR_ACTION
	JR C,DPS_DISMISS		; Carry = 1: user pressed Q or ESC

	; Carry = 0: user selected slot A with action C (about/config)
	CALL EXEC_PLUGIN_SLOT_ACTION
	LD A,(PLUGIN_RET_CODE)
	CP 2
	JP Z,ENTER_EDITOR_WITH_ACTIVE_LINE
	CP 1
	JR NZ,DPS_LOOP
	LD A,(IN_EDITOR_MODE)
	OR A
	JR NZ,DPS_DISMISS
	JR DPS_LOOP

DPS_DISMISS:
	RET

DPS_MISSING:
	CALL SHOW_POPUP_NEED_PLUGIN_MGR
	RET

;------------------------------------------------------------------------------
; SAVE_EDITOR_PLUGIN_STATE: Preserve editor cursor and line state before plugin
;
; Purpose:
;   Saves CUR_DOC_ROW, CUR_COL, and ACTIVE_LINE_ROW to backup variables so
;   editor state can be restored if plugin does not alter document structure.
;
; Call Usage / Protocol:
;   Called via CALL prior to launching plugin modal screens.
;
; Inputs:
;   Active editor variables.
;
; Outputs:
;   Backup variables populated.
;
; Preserves / Modifies:
;   Clobbers AF, HL.
;------------------------------------------------------------------------------
SAVE_EDITOR_PLUGIN_STATE:
	LD HL,(CUR_DOC_ROW)
	LD (PLUGIN_SAVED_DOC_ROW),HL
	LD HL,(CUR_COL)
	LD (PLUGIN_SAVED_COL),HL
	LD HL,(TARGET_COL)
	LD (PLUGIN_SAVED_TARGET_COL),HL
	LD HL,(TOP_DOC_ROW)
	LD (PLUGIN_SAVED_TOP_ROW),HL
	LD HL,(VIEW_LEFT_COL)
	LD (PLUGIN_SAVED_VIEW_LEFT),HL
	RET

;------------------------------------------------------------------------------
; RESTORE_EDITOR_PLUGIN_STATE: Restore editor cursor and line state after plugin
;
; Purpose:
;   Restores CUR_DOC_ROW, CUR_COL, and ACTIVE_LINE_ROW from backup variables
;   after plugin modal execution finishes.
;
; Call Usage / Protocol:
;   Called via CALL after plugin execution.
;
; Inputs:
;   Backup variables.
;
; Outputs:
;   Active editor variables restored.
;
; Preserves / Modifies:
;   Clobbers AF, HL.
;------------------------------------------------------------------------------
RESTORE_EDITOR_PLUGIN_STATE:
	LD HL,(PLUGIN_SAVED_DOC_ROW)
	LD (CUR_DOC_ROW),HL
	LD HL,(PLUGIN_SAVED_COL)
	LD (CUR_COL),HL
	LD HL,(PLUGIN_SAVED_TARGET_COL)
	LD (TARGET_COL),HL
	LD HL,(PLUGIN_SAVED_TOP_ROW)
	LD (TOP_DOC_ROW),HL
	LD HL,(PLUGIN_SAVED_VIEW_LEFT)
	LD (VIEW_LEFT_COL),HL
	CALL CONSTRAIN_CURSOR_VIEWPORT
	CALL CHECKOUT_ACTIVE_LINE
	CALL GET_CUR_ROW_LEN
	LD (ACTIVE_LINE_LEN),DE
	CALL RELOAD_CACHE_WINDOW_FORCE
	RET

;------------------------------------------------------------------------------
; DO_EDITOR_PLUGIN_SCREEN: Run Plugin Manager while preserving editor state
;
; Purpose:
;   Wraps DO_PLUGIN_SCREEN with SAVE_EDITOR_PLUGIN_STATE and
;   RESTORE_EDITOR_PLUGIN_STATE, repainting the editor screen upon exit.
;
; Call Usage / Protocol:
;   Called via CALL from editor key dispatcher on Plugin Manager shortcut.
;
; Inputs:
;   None.
;
; Outputs:
;   Editor screen refreshed and state restored.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_EDITOR_PLUGIN_SCREEN:
	CALL CHECKOUT_ACTIVE_LINE
	CALL GET_CUR_ROW_LEN
	LD (ACTIVE_LINE_LEN),DE
	CALL SAVE_EDITOR_PLUGIN_STATE
	CALL FLUSH_DIRTY_CACHE
	LD HL,0FFFFH
	LD (CACHE_START_ROW),HL
	CALL DO_PLUGIN_SCREEN
	LD A,(PLUGIN_RET_CODE)
	OR A
	JR NZ,DEPS_DOC_MODIFIED
	CALL RESTORE_EDITOR_PLUGIN_STATE
	JR DEPS_RENDER
DEPS_DOC_MODIFIED:
	CALL CHECKOUT_ACTIVE_LINE
	CALL GET_CUR_ROW_LEN
	LD (ACTIVE_LINE_LEN),DE
	CALL CONSTRAIN_CURSOR_VIEWPORT
	CALL RELOAD_CACHE_WINDOW_FORCE
DEPS_RENDER:
	CALL TERM_INIT
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	CALL LOCATE_CURSOR
	JP MAIN_LOOP



;==============================================================================
; Context-Aware Plugin Pop-up Modal Subsystem
;==============================================================================

;------------------------------------------------------------------------------
; DO_CONTEXT_PLUGIN_POPUP: Scan and display context-aware plugin modal popup
;
; Purpose:
;   Iterates through registered plugins matching active POPUP_CONTEXT_ID,
;   formats popup menu frame and choices, handles selection, and executes
;   action 2 (Context Action) of selected plugin.
;
; Call Usage / Protocol:
;   Called via CALL when user requests context menu.
;
; Inputs:
;   POPUP_CONTEXT_ID (0..6).
;
; Outputs:
;   Selected plugin action executed; screen redrawn.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_CONTEXT_PLUGIN_POPUP:
	LD (POPUP_CONTEXT_ID),A
	LD (HOST_API_CONTEXT),A

	; If in editor mode, flush dirty cache lines to Far RAM and save state
	LD A,(IN_EDITOR_MODE)
	OR A
	JR Z,DCPP_PROBE
	CALL SAVE_EDITOR_PLUGIN_STATE
	CALL FLUSH_DIRTY_CACHE

DCPP_PROBE:
	CALL ENSURE_PLUGIN_MGR_LOADED
	JR C,DCPP_MISSING

DCPP_LOOP:
	LD C,1				; Action 1: Context Pop-up
	CALL EXEC_PLUGIN_MGR_ACTION
	JR C,DCPP_DISMISS		; Carry = 1: dismissed (ESC, Ctrl+P, Q)

	; Carry = 0: user selected slot A with action C
	; If C != 0 (About or Config) or plugin has CAP_MODAL_UI,
	; mark action as modal and pre-clear base screen.
	LD B,A				; Save slot number in B
	LD A,C
	OR A
	JR NZ,DCPP_MARK_MODAL
	PUSH BC
	CALL GET_REGISTRY_ENTRY_PTR
	LD DE,20			; Offset +20: CAPABILITIES (word)
	ADD HL,DE
	LD A,(HL)
	AND CAP_MODAL_UI		; 08h
	POP BC
	JR Z,DCPP_NOT_MODAL

DCPP_MARK_MODAL:
	LD A,1
	JR DCPP_SET_MODAL

DCPP_NOT_MODAL:
	XOR A

DCPP_SET_MODAL:
	LD (POPUP_ACTION_MODAL),A
	OR A
	JR Z,DCPP_EXEC
	PUSH BC
	CALL REDRAW_BASE_SCREEN
	POP BC

DCPP_EXEC:
	LD A,B				; A = slot number
	CALL EXEC_PLUGIN_SLOT_ACTION
	LD A,(POPUP_ACTION_MODAL)
	OR A
	JR Z,DCPP_DISMISS	; Non-modal Action 0: dismiss back to caller
	; Modal Action: Redraw base screen & return to Ctrl+P menu
	CALL REDRAW_BASE_SCREEN
	JR DCPP_LOOP

DCPP_DISMISS:
	LD A,(PLUGIN_RET_CODE)
	CP 2
	JP Z,ENTER_EDITOR_WITH_ACTIVE_LINE
	CALL REDRAW_BASE_SCREEN
	RET

DCPP_MISSING:
	CALL SHOW_POPUP_NEED_PLUGIN_MGR
	RET


;------------------------------------------------------------------------------
; POPUP_LOCATE_NEXT: Move cursor to next row within popup modal border
;
; Purpose:
;   Increments popup row counter and emits VT100 cursor positioning escape
;   sequence to start of next line inside popup frame.
;
; Call Usage / Protocol:
;   Called via CALL during modal popup frame construction.
;
; Inputs:
;   None.
;
; Outputs:
;   Hardware cursor repositioned.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
POPUP_LOCATE_NEXT:
	PUSH BC
	PUSH DE
	PUSH HL
	LD A,(POPUP_ROW)
	LD H,A
	LD A,(POPUP_COL)
	LD L,A
	CALL LOCATE_RC
	LD HL,POPUP_ROW
	INC (HL)
	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; POPUP_PRINT_BORDER: Print formatted horizontal border line for popup
;
; Purpose:
;   Emits horizontal border sequence string pointed to by DE to terminal.
;
; Call Usage / Protocol:
;   Called via CALL during popup dialog frame rendering.
;
; Inputs:
;   DE = Pointer to border character string.
;
; Outputs:
;   Border characters emitted to terminal.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
POPUP_PRINT_BORDER:
	CALL POPUP_LOCATE_NEXT
	LD DE,STR_POPUP_BORDER
	JP PRINT_STR



;------------------------------------------------------------------------------
; REDRAW_BASE_SCREEN: Repaint underlying screen context after dismissing popup
;
; Purpose:
;   Examines Context ID in A: redraws editor text screen (0), Open File UI (1),
;   Save File UI (2), or custom screens, restoring terminal display state.
;
; Call Usage / Protocol:
;   Called via CALL from popup cleanup and Host API TRAMP_REDRAW_BASE.
;
; Inputs:
;   A = Context ID (0..6).
;
; Outputs:
;   Underlying screen context redrawn.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
REDRAW_BASE_SCREEN:
	LD A,(POPUP_CONTEXT_ID)
	CP PLUG_CTX_EDITOR
	JR NZ,PDR_NOT_EDITOR
	LD A,(PLUGIN_RET_CODE)
	OR A
	JR NZ,RBS_DOC_MODIFIED
	CALL RESTORE_EDITOR_PLUGIN_STATE
	JR RBS_RENDER
RBS_DOC_MODIFIED:
	CALL CHECKOUT_ACTIVE_LINE
	CALL GET_CUR_ROW_LEN
	LD (ACTIVE_LINE_LEN),DE
	CALL CONSTRAIN_CURSOR_VIEWPORT
	CALL RELOAD_CACHE_WINDOW_FORCE
RBS_RENDER:
	XOR A
	LD (NEED_SCREEN_RENDER),A
	LD (NEED_LINE_RENDER),A
	LD (NEED_STATUS_RENDER),A
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	CALL LOCATE_CURSOR
	RET
PDR_NOT_EDITOR:
	CP PLUG_CTX_SPLASH
	JR NZ,PDR_NOT_SPLASH
	CALL RENDER_SPLASH
	RET
PDR_NOT_SPLASH:
	CP PLUG_CTX_CONFIG
	JR NZ,PDR_NOT_CONFIG
	CALL SHOW_CONFIG_SCREEN
	RET
PDR_NOT_CONFIG:
	CP PLUG_CTX_MEM_INFO
	JR NZ,PDR_NOT_MEM_INFO
	CALL SHOW_MEM_INFO_SCREEN
	RET
PDR_NOT_MEM_INFO:
	CP PLUG_CTX_HELP
	JR NZ,PDR_NOT_HELP
	RET				; Help screen rendered by HELP.OVL
PDR_NOT_HELP:
	CP PLUG_CTX_ABOUT
	JR NZ,PDR_NOT_ABOUT
	CALL SHOW_ABOUT_SCREEN
	RET
PDR_NOT_ABOUT:
	; Context is PLUG_CTX_PLUGIN_MGR
	LD A,(PLUGIN_MGR_LOADED)
	OR A
	RET Z
	LD C,0
	CALL EXEC_PLUGIN_MGR_ACTION
	RET

;==============================================================================
; FAT Filesystem & Headless VFS Subsystem (Phase 2)
;==============================================================================

;------------------------------------------------------------------------------
; VFS_FIND_PLUGIN: Search plugin registry for active VFS filesystem driver
;
; Purpose:
;   Scans all 8 slots in PLUGIN_REGISTRY looking for plugin matching name
;   "FATVFS" or "FAT" with filesystem capabilities flag set.
;
; Call Usage / Protocol:
;   Called via CALL before dispatching any VFS filesystem operation.
;
; Inputs:
;   None.
;
; Outputs:
;   Carry = 0 and A = slot number if found; Carry = 1 if driver not loaded.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
VFS_FIND_PLUGIN:
	PUSH BC
	PUSH DE
	LD B,0
VFP_LOOP:
	PUSH BC
	CALL GET_REGISTRY_ENTRY_PTR
	POP BC
	; Check SLOT_STATE at HL+22
	PUSH HL
	LD DE,22
	ADD HL,DE
	LD A,(HL)
	POP HL
	OR A
	JR Z,VFP_NEXT_SLOT

	; Check CAPABILITIES word at HL+20 (CAP_HAS_VFS = 0x0100)
	; Byte +20 is low byte, byte +21 is high byte.
	; Bit 8 (0x0100) is bit 0 of high byte (+21).
	PUSH HL
	LD DE,21
	ADD HL,DE
	LD A,(HL)
	POP HL
	AND 01H				; Test bit 8 of CAPABILITIES
	JR NZ,VFP_FOUND

VFP_NEXT_SLOT:
	INC B
	LD A,B
	CP PLUGIN_MAX_SLOTS
	JR NZ,VFP_LOOP

	; Not found
	POP DE
	POP BC
	SCF
	RET

VFP_FOUND:
	LD A,B				; A = Slot index
	POP DE
	POP BC
	OR A				; Carry = 0
	RET

;------------------------------------------------------------------------------
; VFS_EXEC_REQUEST: Dispatch filesystem request packet to VFS driver plugin
;
; Purpose:
;   Locates VFS driver plugin via VFS_FIND_PLUGIN, passes VFS_REQ_PKT pointer
;   to driver, executes driver action, and inspects returned status code.
;
; Call Usage / Protocol:
;   Called via CALL for all high-level FAT operations (directory, load, save).
;
; Inputs:
;   VFS_REQ_PKT populated with command, unit, path, and buffer pointers.
;
; Outputs:
;   Carry = 0 on success; Carry = 1 on error (with VFS_REQ_STATUS error code).
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
VFS_EXEC_REQUEST:
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH IX
	PUSH IY

	; Check if VFS plugin is loaded
	CALL VFS_FIND_PLUGIN
	JR C,VER_NOT_LOADED

	; HL = registry entry pointer
	; Read FAR_BANK at HL+24
	LD BC,24
	ADD HL,BC
	LD A,(HL)			; A = FAR_BANK
	LD (PLUGIN_FAR_BANK),A		; Set current bank for host callbacks
	INC HL				; HL points to BASE_PAGE (+25)
	LD A,(HL)			; A = BASE_PAGE
	INC A				; +1 page for header
	LD H,A
	LD L,9				; Entry point = (BASE_PAGE+1)*256 + 9
	PUSH HL
	POP IX				; IX = Action 3 entry vector

	LD IY,PLUGIN_HOST_API		; IY = Host API table pointer
	LD DE,VFS_REQ_PKT		; DE = Request packet pointer
	LD A,1
	LD (PLUGIN_IS_FAR_EXEC),A
	LD A,(PLUGIN_FAR_BANK)		; A = Target Bank for HB_BNKCALL

	; Interrupts disabled during inter-bank call
	DI
	CALL 0FFF9H			; HB_BNKCALL at 0xFFF9
	EI

	PUSH AF
	XOR A
	LD (PLUGIN_IS_FAR_EXEC),A
	POP AF

	; A now contains VFS return code, CY set on error
	POP IY
	POP IX
	POP HL
	POP DE
	POP BC
	RET

VER_NOT_LOADED:
	POP IY
	POP IX
	POP HL
	POP DE
	POP BC
	LD A,0FFH			; VFS_STAT_UNSUPPORTED
	SCF
	RET

;------------------------------------------------------------------------------
; PARSE_FAT_PATH: Parse FAT volume prefix ("U<unit>:") from input string
;
; Purpose:
;   Checks if string at HL begins with 'U' or 'u' followed by decimal digit
;   ('0'..'9') and a colon ':'. If matched, returns unit number and pointer
;   to remainder of path after colon.
;
; Call Usage / Protocol:
;   Called via CALL when evaluating user input for FAT filesystem paths.
;
; Inputs:
;   HL = Pointer to input string.
;
; Outputs:
;   Carry = 0, A = unit number (0..9), HL points past colon; Carry = 1 if not
;   a valid FAT path prefix.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE; advances HL.
;------------------------------------------------------------------------------
PARSE_FAT_PATH:
	PUSH HL
	; Skip leading spaces
PFP_SKIP_SPACES:
	LD A,(HL)
	CP ' '
	JR NZ,PFP_CHECK_U
	INC HL
	JR PFP_SKIP_SPACES

PFP_CHECK_U:
	CALL TO_UPPER
	CP 'U'
	JR NZ,PFP_NOT_FAT

	INC HL
	LD A,(HL)
	CP ':'
	JR Z,PFP_DEFAULT_UNIT

	; Check if next char is digit '0'..'7'
	CP '0'
	JR C,PFP_NOT_FAT
	CP '7'+1
	JR NC,PFP_NOT_FAT

	; Got digit! Save unit digit
	SUB '0'
	LD C,A				; C = unit 0..7
	INC HL
	LD A,(HL)
	CP ':'
	JR NZ,PFP_NOT_FAT

	; Form: U<unit>:
	INC HL				; Advance past ':'
	POP AF				; Discard saved initial HL
	LD A,C				; A = unit 0..7
	SCF
	RET

PFP_DEFAULT_UNIT:
	; Form: U:
	INC HL				; Advance past ':'
	POP AF				; Discard saved initial HL
	LD A,0FFH			; 0xFF = default unit
	SCF
	RET

PFP_NOT_FAT:
	POP HL
	XOR A				; Carry = 0, Z = 1
	RET

;------------------------------------------------------------------------------
; EXTRACT_BASE_FILENAME: Locate base filename component within path string
;
; Purpose:
;   Scans null-terminated string at HL for the last occurrence of '/' or ':'.
;   Returns pointer to the first character following the last delimiter.
;
; Call Usage / Protocol:
;   Called via CALL for title bar, FCB formatting, and status displays.
;
; Inputs:
;   HL = Pointer to null-terminated path string.
;
; Outputs:
;   HL = Pointer to base filename component within string.
;
; Preserves / Modifies:
;   Clobbers AF; preserves BC, DE.
;------------------------------------------------------------------------------
EXTRACT_BASE_FILENAME:
	PUSH BC
	PUSH DE
	PUSH HL

	LD DE,FAT_DOC_FNAME
	; BC tracks candidate pointer to base filename start
	LD B,H
	LD C,L

EBF_SCAN_LOOP:
	LD A,(HL)
	OR A
	JR Z,EBF_FOUND_END
	CP '/'
	JR NZ,EBF_NOT_SLASH
	; Found a slash. Next char is candidate for base filename start
	INC HL
	LD B,H
	LD C,L
	JR EBF_SCAN_LOOP

EBF_NOT_SLASH:
	INC HL
	JR EBF_SCAN_LOOP

EBF_FOUND_END:
	; HL = pointer to candidate base filename
	LD H,B
	LD L,C

	; Copy up to 12 chars to FAT_DOC_FNAME, terminating with 0
	LD B,12
EBF_COPY_LOOP:
	LD A,(HL)
	OR A
	JR Z,EBF_COPY_DONE
	CP ' '
	JR Z,EBF_COPY_DONE
	CALL TO_UPPER
	LD (DE),A
	INC HL
	INC DE
	DJNZ EBF_COPY_LOOP

EBF_COPY_DONE:
	XOR A
	LD (DE),A			; Null terminate

	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; ENSURE_VFS_PLUGIN_LOADED: Verify or autoload FAT VFS filesystem driver
;
; Purpose:
;   Calls VFS_FIND_PLUGIN. If not loaded, attempts to load "FATVFS.PRL"
;   from default drive into next free plugin slot.
;
; Call Usage / Protocol:
;   Called via CALL prior to performing FAT filesystem operations.
;
; Inputs:
;   None.
;
; Outputs:
;   Carry = 0 if VFS driver is ready; Carry = 1 if driver cannot be loaded.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
ENSURE_VFS_PLUGIN_LOADED:
	CALL VFS_FIND_PLUGIN
	RET NC				; Already resident
	LD DE,STR_FATFS_PRL
	CALL LOAD_PLUGIN_BY_NAME
	RET

;------------------------------------------------------------------------------
; CHECK_FAT_INPUT_OPEN: Check if Open File input specifies a FAT path
;
; Purpose:
;   Checks if INPUT_FILENAME_BUF matches FAT prefix ("U<n>:"). If so, verifies
;   VFS plugin availability via ENSURE_VFS_PLUGIN_LOADED.
;
; Call Usage / Protocol:
;   Called via CALL from DO_OPEN_FILE_UI on Enter key press.
;
; Inputs:
;   INPUT_FILENAME_BUF.
;
; Outputs:
;   Carry = 0 and NZ if FAT path confirmed; Carry = 0 and Z if standard CP/M;
;   Carry = 1 if FAT path entered but VFS plugin failed to load.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
CHECK_FAT_INPUT_OPEN:
	LD A,(IS_PLUGIN_LOAD_UI)
	OR A
	JR NZ,CFIO_NOT_FAT

	LD HL,INPUT_FILENAME_BUF
	CALL PARSE_FAT_PATH
	JR NC,CFIO_NOT_FAT

	; FAT path detected! Check if plugin is loaded
	CALL VFS_FIND_PLUGIN
	JR C,CFIO_NO_PLUGIN

	; Plugin is loaded! Return Carry=0, NZ
	XOR A
	INC A				; A = 1 -> NZ, Carry = 0
	RET

CFIO_NOT_FAT:
	XOR A				; Carry = 0, Z = 1
	RET

CFIO_NO_PLUGIN:
	SCF				; Carry = 1
	RET

;------------------------------------------------------------------------------
; CHECK_FAT_INPUT_SAVE: Check if Save File input specifies a FAT path
;
; Purpose:
;   Checks if INPUT_FILENAME_BUF matches FAT prefix ("U<n>:"). If so, verifies
;   VFS plugin availability via ENSURE_VFS_PLUGIN_LOADED.
;
; Call Usage / Protocol:
;   Called via CALL from DO_SAVE_FILE_UI on Enter key press.
;
; Inputs:
;   INPUT_FILENAME_BUF.
;
; Outputs:
;   Carry = 0 and NZ if FAT path confirmed; Carry = 0 and Z if standard CP/M;
;   Carry = 1 if FAT path entered but VFS plugin failed to load.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
CHECK_FAT_INPUT_SAVE:
	LD HL,INPUT_FILENAME_BUF
	CALL PARSE_FAT_PATH
	JR NC,CFIS_NOT_FAT

	; FAT path detected! Check if plugin is loaded
	CALL VFS_FIND_PLUGIN
	JR C,CFIS_NO_PLUGIN

	; Plugin is loaded! Return Carry=0, NZ
	XOR A
	INC A				; A = 1 -> NZ, Carry = 0
	RET

CFIS_NOT_FAT:
	XOR A				; Carry = 0, Z = 1
	RET

CFIS_NO_PLUGIN:
	SCF				; Carry = 1
	RET

;------------------------------------------------------------------------------
; HANDLE_OPEN_FAT_DISPATCH: Dispatch confirmed FAT input path in Open File UI
;
; Purpose:
;   Parses FAT unit and path from INPUT_FILENAME_BUF, checking whether input
;   represents unit root ("U4:"), subdir descent ("U4:DIR/"), or file open,
;   branching to the appropriate navigation or file load handler.
;
; Call Usage / Protocol:
;   Called via CALL or JP from Open File input handler.
;
; Inputs:
;   INPUT_FILENAME_BUF.
;
; Outputs:
;   None.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HANDLE_OPEN_FAT_DISPATCH:
	LD HL,INPUT_FILENAME_BUF
	CALL PARSE_FAT_PATH		; A = unit, HL = path after ':'
	LD (VFS_REQ_UNIT),A
	LD (FAT_DOC_UNIT),A

	; Check if remainder after ':' is empty or just spaces
HOFD_CHECK_EMPTY:
	LD A,(HL)
	OR A
	JR Z,HANDLE_OPEN_FAT_DRIVE_SWITCH
	CP ' '
	JR NZ,HOFD_NOT_EMPTY
	INC HL
	JR HOFD_CHECK_EMPTY

HOFD_NOT_EMPTY:
	; Remainder is non-empty. Check if it's "/" alone
	CP '/'
	JR NZ,HOFD_CHECK_DESCENT
	INC HL
	LD A,(HL)
	OR A
	JR Z,HANDLE_OPEN_FAT_DRIVE_SWITCH
	CP ' '
	JR Z,HANDLE_OPEN_FAT_DRIVE_SWITCH
	DEC HL				; Point back to '/'

HOFD_CHECK_DESCENT:
	; Check if input path ends with '/'
	CALL CHECK_HL_ENDS_WITH_SLASH
	JR C,HANDLE_OPEN_FAT_SUBDIR_SWITCH

	; Check if this is Block Insert UI
	LD A,(IS_BLOCK_INSERT_UI)
	OR A
	JP NZ,HANDLE_BLOCK_INSERT_FAT_FILE
	JP HANDLE_OPEN_FAT_FILE

;------------------------------------------------------------------------------
; HANDLE_OPEN_FAT_SUBDIR_SWITCH: Switch Open directory view to FAT subdirectory
;
; Purpose:
;   Sets CURRENT_DIR_IS_FAT=1, updates CURRENT_DIR_FAT_UNIT and FAT_ACTIVE_DIR,
;   resets wildcard filter to "*.*", and refreshes directory page.
;
; Call Usage / Protocol:
;   Jumped to from HANDLE_OPEN_FAT_DISPATCH when path ends with '/'.
;
; Inputs:
;   VFS_REQ_UNIT, HL = Subdirectory path string.
;
; Outputs:
;   Active directory view switched; directory refreshed.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HANDLE_OPEN_FAT_SUBDIR_SWITCH:
	LD A,1
	LD (CURRENT_DIR_IS_FAT),A
	LD A,(VFS_REQ_UNIT)
	LD (CURRENT_DIR_FAT_UNIT),A
	CALL SET_DIR_FROM_PATH_HL
	LD A,'U'
	LD (STR_DIR_DRIVE_CHAR),A
	LD (STR_SAVE_DRIVE_CHAR),A
	CALL RESET_DIR_FILTER
	XOR A
	LD (SHOWING_FNF_MSG),A
	JP REFRESH_OPEN_DIR

;------------------------------------------------------------------------------
; HANDLE_OPEN_FAT_DRIVE_SWITCH: Switch Open directory view to FAT volume root
;
; Purpose:
;   Sets CURRENT_DIR_IS_FAT = 1, sets FAT_ACTIVE_DIR to root ("/"), and
;   refreshes directory page for target unit.
;
; Call Usage / Protocol:
;   Jumped to from HANDLE_OPEN_FAT_DISPATCH when input is unit root ("U4:").
;
; Inputs:
;   VFS_REQ_UNIT.
;
; Outputs:
;   Active directory switched to root; page refreshed.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HANDLE_OPEN_FAT_DRIVE_SWITCH:
	LD A,1
	LD (CURRENT_DIR_IS_FAT),A
	LD A,(VFS_REQ_UNIT)
	LD (CURRENT_DIR_FAT_UNIT),A
	CALL FAT_PATH_SET_ROOT
	LD A,'U'
	LD (STR_DIR_DRIVE_CHAR),A
	LD (STR_SAVE_DRIVE_CHAR),A
	CALL RESET_DIR_FILTER
	XOR A
	LD (SHOWING_FNF_MSG),A
	JP REFRESH_OPEN_DIR

;------------------------------------------------------------------------------
; HANDLE_OPEN_FAT_RELATIVE: Resolve relative path against active FAT directory
;
; Purpose:
;   Concatenates relative input path to CURRENT_DIR_FAT_UNIT and FAT_ACTIVE_DIR,
;   branching to subdirectory switch or file load.
;
; Call Usage / Protocol:
;   Jumped to from HANDLE_OPEN_FAT_DISPATCH on relative paths.
;
; Inputs:
;   Relative path string in INPUT_FILENAME_BUF.
;
; Outputs:
;   Directory switched or file load initiated.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HANDLE_OPEN_FAT_RELATIVE:
	CALL CHECK_AND_HANDLE_FAT_NAV
	JR NC,HOFR_NOT_NAV
	CALL RESET_DIR_FILTER
	XOR A
	LD (SHOWING_FNF_MSG),A
	JP REFRESH_OPEN_DIR

HOFR_NOT_NAV:
	CALL BUILD_RELATIVE_FAT_PATH
	LD A,(CURRENT_DIR_FAT_UNIT)
	LD (VFS_REQ_UNIT),A
	LD (FAT_DOC_UNIT),A

	; Check if Block Insert UI
	LD A,(IS_BLOCK_INSERT_UI)
	OR A
	JP Z,HOFF_DO_LOAD

	; Block insert relative FAT file
	LD HL,FAT_DOC_PATH
	LD DE,FAT_INSERT_PATH
	LD BC,64
	LDIR
	JP HBIF_DO_STREAM_OPEN

;------------------------------------------------------------------------------
; HANDLE_BLOCK_INSERT_FAT_FILE: Insert text from FAT file at editor cursor
;
; Purpose:
;   Streams file content from FAT volume via VFS stream read request, parses
;   lines, and inserts text at current cursor coordinates in document.
;
; Call Usage / Protocol:
;   Jumped to from HANDLE_OPEN_FAT_DISPATCH during Block Insert mode.
;
; Inputs:
;   Target FAT file path in INPUT_FILENAME_BUF.
;
; Outputs:
;   Text inserted into document; editor view updated.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HANDLE_BLOCK_INSERT_FAT_FILE:
	LD HL,INPUT_FILENAME_BUF
	CALL PARSE_FAT_PATH		; A = unit, HL = path after ':'
	LD (VFS_REQ_UNIT),A

	; Copy path after ':' into FAT_INSERT_PATH (prepending '/' if needed)
	LD DE,FAT_INSERT_PATH
	LD A,(HL)
	CP '/'
	JR Z,HBIF_COPY_PATH
	LD A,'/'
	LD (DE),A
	INC DE
HBIF_COPY_PATH:
	LD A,(HL)
	OR A
	JR Z,HBIF_PATH_DONE
	CP ' '
	JR Z,HBIF_PATH_DONE
	LD (DE),A
	INC HL
	INC DE
	JR HBIF_COPY_PATH
HBIF_PATH_DONE:
	XOR A
	LD (DE),A

HBIF_DO_STREAM_OPEN:
	; Open file stream via VFS_CMD_OPEN_FILE (5)
	LD A,5				; VFS_CMD_OPEN_FILE
	LD (VFS_REQ_CMD),A
	XOR A
	LD (VFS_REQ_FLAGS),A
	LD (VFS_REQ_STATUS),A
	LD HL,FAT_INSERT_PATH
	LD (VFS_REQ_PATH),HL
	CALL VFS_EXEC_REQUEST
	JR C,HBIF_FAIL
	LD A,(VFS_REQ_STATUS)
	OR A
	JR NZ,HBIF_FAIL

	; File opened! Set BLOCK_INSERT_IS_FAT = 1
	LD A,1
	LD (BLOCK_INSERT_IS_FAT),A

	; Extract base filename into FAT_DOC_FNAME for progress display
	LD HL,FAT_INSERT_PATH
	CALL EXTRACT_BASE_FILENAME

	; Setup loading UI for block insert
	LD A,(HAS_FILE_ARG)
	LD (SAVED_HAS_FILE_ARG),A
	LD A,1
	LD (HAS_FILE_ARG),A
	LD (IS_LOADING_FILE),A
	XOR A
	LD (IS_SPLASH_SCREEN),A
	LD (INSERT_LINE_HAD_CHARS),A
	LD HL,0
	LD (LOAD_PROGRESS_LINES),HL
	LD A,100
	LD (LOAD_PROGRESS_COUNT),A

	CALL DRAW_LOADING_SCREEN

	; Perform Block Insert
	CALL DO_PERFORM_BLOCK_INSERT

	; Finish block insert and return to editor
	JP DPAI_CLEANUP

HBIF_FAIL:
	JP OPEN_FILE_NOT_FOUND

;------------------------------------------------------------------------------
; HANDLE_OPEN_FAT_FILE: Load document file from FAT volume into editor
;
; Purpose:
;   Draws loading modal dialog, reads file records from FAT volume via VFS
;   driver into far RAM line storage, sets document FAT metadata, and resumes.
;
; Call Usage / Protocol:
;   Jumped to from HANDLE_OPEN_FAT_DISPATCH when opening a document.
;
; Inputs:
;   Target FAT file path.
;
; Outputs:
;   Document loaded; editor refreshed.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HANDLE_OPEN_FAT_FILE:
	LD HL,INPUT_FILENAME_BUF
	CALL PARSE_FAT_PATH		; A = unit, HL = path after ':'
	LD (VFS_REQ_UNIT),A
	LD (FAT_DOC_UNIT),A

	; Copy path after ':' into FAT_DOC_PATH (prepending '/' if needed)
	LD DE,FAT_DOC_PATH
	LD A,(HL)
	CP '/'
	JR Z,HOFF_COPY_PATH
	LD A,'/'
	LD (DE),A
	INC DE
HOFF_COPY_PATH:
	LD A,(HL)
	OR A
	JR Z,HOFF_PATH_DONE
	CP ' '
	JR Z,HOFF_PATH_DONE
	LD (DE),A
	INC HL
	INC DE
	JR HOFF_COPY_PATH
HOFF_PATH_DONE:
	XOR A
	LD (DE),A

HOFF_DO_LOAD:
	; Extract base filename into FAT_DOC_FNAME
	LD HL,FAT_DOC_PATH
	CALL EXTRACT_BASE_FILENAME

	; Update CURRENT_DIR_FAT_PATH from FAT_DOC_PATH
	CALL SET_DIR_FROM_DOC_PATH

	; Attempt to load the file via VFS
	LD HL,FAT_DOC_PATH
	CALL VFS_LOAD_FAT_FILE
	JR C,HOFF_LOAD_FAIL

	; Success! Set flags and enter editor
	LD SP,LOCAL_STACK
	LD A,1
	LD (DOC_IS_FAT),A
	LD (HAS_FILE_ARG),A
	LD (IN_EDITOR_MODE),A
	XOR A
	LD (DOC_MODIFIED),A

	; Default view to line 0
	LD HL,0
	LD (CUR_DOC_ROW),HL
	LD (TOP_DOC_ROW),HL
	LD (CUR_COL),HL
	LD (TARGET_COL),HL

	CALL INVALIDATE_ACTIVE_LINE
	CALL CHECKOUT_ACTIVE_LINE
	CALL RELOAD_CACHE_WINDOW_FORCE

	CALL TERM_INIT
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	CALL CHECK_FILE_TRUNCATED_POPUP
	CALL LOCATE_CURSOR
	JP MAIN_LOOP

HOFF_LOAD_FAIL:
	CALL SHOW_POPUP_FILE_NOT_FOUND
	JP RENDER_OPEN_PAGE

;------------------------------------------------------------------------------
; HANDLE_SAVE_FAT_DISPATCH: Dispatch confirmed FAT input path in Save dialog
;
; Purpose:
;   Parses FAT unit and path from INPUT_FILENAME_BUF in Save As dialog,
;   branching to unit switch, subdirectory change, or file write.
;
; Call Usage / Protocol:
;   Called via CALL or JP from Save File input handler.
;
; Inputs:
;   INPUT_FILENAME_BUF.
;
; Outputs:
;   None.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HANDLE_SAVE_FAT_DISPATCH:
	LD HL,INPUT_FILENAME_BUF
	CALL PARSE_FAT_PATH		; A = unit, HL = path after ':'
	LD (VFS_REQ_UNIT),A
	LD (FAT_DOC_UNIT),A

HSFD_CHECK_EMPTY:
	LD A,(HL)
	OR A
	JR Z,HANDLE_SAVE_FAT_DRIVE_SWITCH
	CP ' '
	JR NZ,HSFD_NOT_EMPTY
	INC HL
	JR HSFD_CHECK_EMPTY

HSFD_NOT_EMPTY:
	CP '/'
	JR NZ,HSFD_CHECK_DESCENT
	INC HL
	LD A,(HL)
	OR A
	JR Z,HANDLE_SAVE_FAT_DRIVE_SWITCH
	CP ' '
	JR Z,HANDLE_SAVE_FAT_DRIVE_SWITCH
	DEC HL

HSFD_CHECK_DESCENT:
	CALL CHECK_HL_ENDS_WITH_SLASH
	JR C,HANDLE_SAVE_FAT_SUBDIR_SWITCH

	JP HANDLE_SAVE_FAT_FILE

;------------------------------------------------------------------------------
; HANDLE_SAVE_FAT_SUBDIR_SWITCH: Switch Save directory view to FAT subdirectory
;
; Purpose:
;   Updates CURRENT_DIR_FAT_UNIT and FAT_ACTIVE_DIR for Save dialog view and
;   refreshes directory listing.
;
; Call Usage / Protocol:
;   Jumped to from HANDLE_SAVE_FAT_DISPATCH when path ends with '/'.
;
; Inputs:
;   VFS_REQ_UNIT, HL = Subdirectory path.
;
; Outputs:
;   Save directory view updated; page refreshed.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HANDLE_SAVE_FAT_SUBDIR_SWITCH:
	LD A,1
	LD (CURRENT_DIR_IS_FAT),A
	LD A,(VFS_REQ_UNIT)
	LD (CURRENT_DIR_FAT_UNIT),A
	CALL SET_DIR_FROM_PATH_HL
	LD A,'U'
	LD (STR_SAVE_DRIVE_CHAR),A
	LD (STR_DIR_DRIVE_CHAR),A
	CALL RESET_DIR_FILTER
	XOR A
	LD (SHOWING_FNF_MSG),A
	JP REFRESH_SAVE_DIR

;------------------------------------------------------------------------------
; HANDLE_SAVE_FAT_DRIVE_SWITCH: Switch Save directory view to FAT volume root
;
; Purpose:
;   Resets Save dialog FAT directory to root ("/") on target unit.
;
; Call Usage / Protocol:
;   Jumped to from HANDLE_SAVE_FAT_DISPATCH when input is unit root ("U4:").
;
; Inputs:
;   VFS_REQ_UNIT.
;
; Outputs:
;   Save view switched to root; page refreshed.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HANDLE_SAVE_FAT_DRIVE_SWITCH:
	LD A,1
	LD (CURRENT_DIR_IS_FAT),A
	LD A,(VFS_REQ_UNIT)
	LD (CURRENT_DIR_FAT_UNIT),A
	CALL FAT_PATH_SET_ROOT
	LD A,'U'
	LD (STR_SAVE_DRIVE_CHAR),A
	LD (STR_DIR_DRIVE_CHAR),A
	CALL RESET_DIR_FILTER
	XOR A
	LD (SHOWING_FNF_MSG),A
	JP REFRESH_SAVE_DIR

;------------------------------------------------------------------------------
; HANDLE_SAVE_FAT_RELATIVE: Resolve relative save path against active FAT dir
;
; Purpose:
;   Combines relative input path with active FAT directory and executes save
;   or directory navigation.
;
; Call Usage / Protocol:
;   Jumped to from HANDLE_SAVE_FAT_DISPATCH on relative paths.
;
; Inputs:
;   Relative path string.
;
; Outputs:
;   Document saved or directory view updated.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HANDLE_SAVE_FAT_RELATIVE:
	CALL CHECK_AND_HANDLE_FAT_NAV
	JR NC,HSFR_NOT_NAV
	CALL RESET_DIR_FILTER
	XOR A
	LD (SHOWING_FNF_MSG),A
	JP REFRESH_SAVE_DIR

HSFR_NOT_NAV:
	CALL BUILD_RELATIVE_FAT_PATH
	LD A,(CURRENT_DIR_FAT_UNIT)
	LD (VFS_REQ_UNIT),A
	LD (FAT_DOC_UNIT),A
	JR HSFF_DO_SAVE

;------------------------------------------------------------------------------
; HANDLE_SAVE_FAT_FILE: Write active document lines to FAT volume file
;
; Purpose:
;   Displays save progress dialog, streams document lines from far RAM to FAT
;   volume via VFS write request, updates FAT metadata, and clears modified.
;
; Call Usage / Protocol:
;   Jumped to from HANDLE_SAVE_FAT_DISPATCH upon confirmed save filename.
;
; Inputs:
;   Target FAT file path.
;
; Outputs:
;   Document saved to FAT filesystem; editor resumed.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
HANDLE_SAVE_FAT_FILE:
	LD HL,INPUT_FILENAME_BUF
	CALL PARSE_FAT_PATH		; A = unit, HL = path after ':'
	LD (VFS_REQ_UNIT),A
	LD (FAT_DOC_UNIT),A

	; Copy path after ':' into FAT_DOC_PATH (prepending '/' if needed)
	LD DE,FAT_DOC_PATH
	LD A,(HL)
	CP '/'
	JR Z,HSFF_COPY_PATH
	LD A,'/'
	LD (DE),A
	INC DE
HSFF_COPY_PATH:
	LD A,(HL)
	OR A
	JR Z,HSFF_PATH_DONE
	CP ' '
	JR Z,HSFF_PATH_DONE
	LD (DE),A
	INC HL
	INC DE
	JR HSFF_COPY_PATH
HSFF_PATH_DONE:
	XOR A
	LD (DE),A

HSFF_DO_SAVE:
	; Extract base filename into FAT_DOC_FNAME
	LD HL,FAT_DOC_PATH
	CALL EXTRACT_BASE_FILENAME

	; Update CURRENT_DIR_FAT_PATH from FAT_DOC_PATH
	CALL SET_DIR_FROM_DOC_PATH

	; Call VFS save
	CALL VFS_SAVE_FAT_FILE
	JR C,HSFF_SAVE_FAIL

	; If not block save, mark document as FAT file and clean
	LD A,(IS_BLOCK_SAVE_UI)
	OR A
	RET NZ

	LD A,1
	LD (DOC_IS_FAT),A
	LD (HAS_FILE_ARG),A
	XOR A
	LD (DOC_MODIFIED),A
	RET

HSFF_SAVE_FAIL:
	CALL SHOW_POPUP_FILE_NOT_FOUND
	JP RENDER_SAVE_PAGE

;------------------------------------------------------------------------------
; CHECK_AND_HANDLE_FAT_NAV: Process directory nav shortcuts in FAT browser
;
; Purpose:
;   Tests if entered string in file dialog matches navigation commands ("..",
;   "/", or listed subdirectory name). If so, updates directory and refreshes.
;
; Call Usage / Protocol:
;   Called via CALL on Enter key in file modal dialogs.
;
; Inputs:
;   INPUT_FILENAME_BUF.
;
; Outputs:
;   Carry = 0 if directory navigation handled; Carry = 1 if regular filename.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
CHECK_AND_HANDLE_FAT_NAV:
	LD HL,INPUT_FILENAME_BUF
CAHFN_SKIP_SP:
	LD A,(HL)
	CP ' '
	JR NZ,CAHFN_START
	INC HL
	JR CAHFN_SKIP_SP

CAHFN_START:
	OR A
	RET Z				; Empty string -> Carry = 0

	; Check for "/" alone
	CP '/'
	JR NZ,CAHFN_CHECK_DOT
	INC HL
	LD A,(HL)
	OR A
	JR Z,CAHFN_DO_ROOT
	CP ' '
	JR Z,CAHFN_DO_ROOT
	DEC HL
	JR CAHFN_CHECK_TRAILING_SLASH

CAHFN_DO_ROOT:
	CALL FAT_PATH_SET_ROOT
	SCF
	RET

CAHFN_CHECK_DOT:
	CP '.'
	JR NZ,CAHFN_CHECK_TRAILING_SLASH
	INC HL
	LD A,(HL)
	CP '.'
	JR Z,CAHFN_DOT_DOT
	; Single dot: '.' or './'
	OR A
	JR Z,CAHFN_DO_SAME_DIR
	CP ' '
	JR Z,CAHFN_DO_SAME_DIR
	CP '/'
	JR NZ,CAHFN_NOT_DOT_CMD
	INC HL
	LD A,(HL)
	OR A
	JR Z,CAHFN_DO_SAME_DIR
	CP ' '
	JR Z,CAHFN_DO_SAME_DIR
CAHFN_NOT_DOT_CMD:
	DEC HL
	JR CAHFN_CHECK_TRAILING_SLASH

CAHFN_DO_SAME_DIR:
	SCF
	RET

CAHFN_DOT_DOT:
	; Got ".."
	INC HL
	LD A,(HL)
	OR A
	JR Z,CAHFN_DO_POP
	CP ' '
	JR Z,CAHFN_DO_POP
	CP '/'
	JR NZ,CAHFN_NOT_DOTDOT_CMD
	INC HL
	LD A,(HL)
	OR A
	JR Z,CAHFN_DO_POP
	CP ' '
	JR Z,CAHFN_DO_POP
CAHFN_NOT_DOTDOT_CMD:
	DEC HL
	DEC HL
	JR CAHFN_CHECK_TRAILING_SLASH

CAHFN_DO_POP:
	CALL FAT_PATH_POP_DIR
	SCF
	RET

CAHFN_CHECK_TRAILING_SLASH:
	LD HL,INPUT_FILENAME_BUF
	CALL CHECK_HL_ENDS_WITH_SLASH
	JR NC,CAHFN_CHECK_DIR_ENTRY

	; Input ends with '/' -> descend into directory
	LD HL,INPUT_FILENAME_BUF
	CALL FAT_PATH_PUSH_DIR
	SCF
	RET

CAHFN_CHECK_DIR_ENTRY:
	CALL CHECK_INPUT_IS_DIR_ENTRY
	RET NC				; Carry = 0: not a directory entry

	; Matches a directory entry in grid!
	LD HL,INPUT_FILENAME_BUF
	CALL FAT_PATH_PUSH_DIR
	SCF
	RET

;------------------------------------------------------------------------------
; CHECK_INPUT_IS_DIR_ENTRY: Check if input matches listed directory name
;
; Purpose:
;   Compares INPUT_FILENAME_BUF against entries in DIR_NAMES_BUF to see if user
;   selected a folder displayed in the active directory view.
;
; Call Usage / Protocol:
;   Called via CALL from CHECK_AND_HANDLE_FAT_NAV.
;
; Inputs:
;   INPUT_FILENAME_BUF.
;
; Outputs:
;   Carry = 0 if entry matches a listed directory; Carry = 1 if not a directory.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
CHECK_INPUT_IS_DIR_ENTRY:
	PUSH BC
	PUSH DE
	PUSH HL

	LD A,(DIR_FILE_COUNT)
	OR A
	JR Z,CIIDE_NO_MATCH

	LD B,A				; B = entry count
	LD HL,DIR_NAMES_BUF

CIIDE_ENTRY_LOOP:
	; Check if byte 8 of entry is '/'
	PUSH HL
	LD DE,8
	ADD HL,DE
	LD A,(HL)
	POP HL
	CP '/'
	JR NZ,CIIDE_NEXT_ENTRY		; Not a directory entry

	; HL points to entry (8-char name at HL..HL+7)
	; Compare with INPUT_FILENAME_BUF
	PUSH BC
	PUSH HL
	LD DE,INPUT_FILENAME_BUF

CIIDE_SKIP_SP:
	LD A,(DE)
	CP ' '
	JR NZ,CIIDE_CMP_START
	INC DE
	JR CIIDE_SKIP_SP

CIIDE_CMP_START:
	LD C,8				; 8 characters in name field
CIIDE_CHAR_LOOP:
	LD A,(DE)			; Character from input
	OR A
	JR Z,CIIDE_INPUT_ENDED
	CP ' '
	JR Z,CIIDE_INPUT_ENDED
	CP '/'
	JR Z,CIIDE_INPUT_ENDED

	CALL TO_UPPER
	CP (HL)				; Compare with entry char
	JR NZ,CIIDE_MISMATCH
	INC DE
	INC HL
	DEC C
	JR NZ,CIIDE_CHAR_LOOP

	; Input matched all 8 characters.
	; Next char in input must be 0, space, or '/'
	LD A,(DE)
	OR A
	JR Z,CIIDE_MATCH_FOUND
	CP ' '
	JR Z,CIIDE_MATCH_FOUND
	CP '/'
	JR Z,CIIDE_MATCH_FOUND
	JR CIIDE_MISMATCH

CIIDE_INPUT_ENDED:
	; Input ended before 8 chars.
	; Remaining chars in entry name must be spaces (' ')
CIIDE_PAD_CHECK:
	LD A,(HL)
	CP ' '
	JR NZ,CIIDE_MISMATCH
	INC HL
	DEC C
	JR NZ,CIIDE_PAD_CHECK

CIIDE_MATCH_FOUND:
	POP HL
	POP BC
	POP HL
	POP DE
	POP BC
	SCF				; Carry = 1 (match!)
	RET

CIIDE_MISMATCH:
	POP HL
	POP BC

CIIDE_NEXT_ENTRY:
	LD DE,13
	ADD HL,DE
	DJNZ CIIDE_ENTRY_LOOP

CIIDE_NO_MATCH:
	POP HL
	POP DE
	POP BC
	OR A				; Carry = 0
	RET

;------------------------------------------------------------------------------
; CHECK_HL_ENDS_WITH_SLASH: Check if string at HL ends with forward slash ('/')
;
; Purpose:
;   Finds terminating null byte of string at HL and tests if preceding non-space
;   character is '/'.
;
; Call Usage / Protocol:
;   Called via CALL during FAT path parsing.
;
; Inputs:
;   HL = Pointer to null-terminated string.
;
; Outputs:
;   Carry = 1 if string ends with '/'; Carry = 0 otherwise.
;
; Preserves / Modifies:
;   Clobbers AF; preserves BC, DE, HL.
;------------------------------------------------------------------------------
CHECK_HL_ENDS_WITH_SLASH:
	PUSH HL
	LD C,0				; Tracks last non-space char
CHLE_SCAN:
	LD A,(HL)
	OR A
	JR Z,CHLE_DONE
	CP ' '
	JR Z,CHLE_NEXT
	LD C,A
CHLE_NEXT:
	INC HL
	JR CHLE_SCAN
CHLE_DONE:
	POP HL
	LD A,C
	CP '/'
	JR NZ,CHLE_NOT_SLASH
	SCF
	RET
CHLE_NOT_SLASH:
	OR A
	RET

;------------------------------------------------------------------------------
; BUILD_RELATIVE_FAT_PATH: Concatenate relative component to active directory
;
; Purpose:
;   Appends relative path or filename in DE to active directory path in HL,
;   ensuring exactly one separating '/' between components.
;
; Call Usage / Protocol:
;   Called via CALL during FAT path normalization.
;
; Inputs:
;   HL = Destination buffer with base path.
;   DE = Pointer to relative path component.
;
; Outputs:
;   Combined path in destination buffer.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
BUILD_RELATIVE_FAT_PATH:
	PUSH BC
	PUSH DE
	PUSH HL

	LD HL,INPUT_FILENAME_BUF
BRFP_SKIP_SP:
	LD A,(HL)
	CP ' '
	JR NZ,BRFP_START
	INC HL
	JR BRFP_SKIP_SP

BRFP_START:
	; If input starts with '/', copy directly to FAT_DOC_PATH
	CP '/'
	JR Z,BRFP_COPY_ABSOLUTE

	; Copy CURRENT_DIR_FAT_PATH to FAT_DOC_PATH
	LD DE,CURRENT_DIR_FAT_PATH
	LD BC,FAT_DOC_PATH
BRFP_COPY_CUR:
	LD A,(DE)
	OR A
	JR Z,BRFP_CHECK_CUR_SLASH
	LD (BC),A
	INC DE
	INC BC
	JR BRFP_COPY_CUR

BRFP_CHECK_CUR_SLASH:
	DEC BC
	LD A,(BC)
	INC BC
	CP '/'
	JR Z,BRFP_APPEND_NAME
	LD A,'/'
	LD (BC),A
	INC BC

BRFP_APPEND_NAME:
	LD A,(HL)
	OR A
	JR Z,BRFP_FINISH
	CP ' '
	JR Z,BRFP_FINISH
	CALL TO_UPPER
	LD (BC),A
	INC HL
	INC BC
	JR BRFP_APPEND_NAME

BRFP_COPY_ABSOLUTE:
	LD BC,FAT_DOC_PATH
BRFP_ABS_LOOP:
	LD A,(HL)
	OR A
	JR Z,BRFP_FINISH
	CP ' '
	JR Z,BRFP_FINISH
	CALL TO_UPPER
	LD (BC),A
	INC HL
	INC BC
	JR BRFP_ABS_LOOP

BRFP_FINISH:
	XOR A
	LD (BC),A			; Null terminate
	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; SET_DIR_FROM_PATH_HL: Copy normalized directory path at HL to FAT_ACTIVE_DIR
;
; Purpose:
;   Copies directory path string from HL into FAT_ACTIVE_DIR, ensuring leading
;   slash and stripping redundant trailing slashes.
;
; Call Usage / Protocol:
;   Called via CALL when updating active FAT directory.
;
; Inputs:
;   HL = Pointer to source directory path string.
;
; Outputs:
;   FAT_ACTIVE_DIR updated.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SET_DIR_FROM_PATH_HL:
	PUSH BC
	PUSH DE
	PUSH HL
	LD DE,CURRENT_DIR_FAT_PATH

SDFP_SKIP_SP:
	LD A,(HL)
	CP ' '
	JR NZ,SDFP_CHECK_ROOT
	INC HL
	JR SDFP_SKIP_SP

SDFP_CHECK_ROOT:
	CP '/'
	JR Z,SDFP_COPY_LOOP
	LD A,'/'
	LD (DE),A
	INC DE

SDFP_COPY_LOOP:
	LD A,(HL)
	OR A
	JR Z,SDFP_FINISH
	CP ' '
	JR Z,SDFP_FINISH
	CALL TO_UPPER
	LD (DE),A
	INC HL
	INC DE
	JR SDFP_COPY_LOOP

SDFP_FINISH:
	XOR A
	LD (DE),A			; Null terminate

	; Strip trailing slash if path length > 1
	LD HL,CURRENT_DIR_FAT_PATH
	INC HL
	LD A,(HL)
	OR A
	JR Z,SDFP_DONE			; Length 1 ("/") -> done

	DEC DE
	LD A,(DE)
	CP '/'
	JR NZ,SDFP_DONE
	XOR A
	LD (DE),A			; Strip trailing slash

SDFP_DONE:
	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; SET_DIR_FROM_DOC_PATH: Initialize active FAT directory from document path
;
; Purpose:
;   Copies parent directory path from FAT_DOC_PATH into FAT_ACTIVE_DIR so file
;   browser opens in the same directory as active document.
;
; Call Usage / Protocol:
;   Called via CALL when opening file dialog on an open FAT document.
;
; Inputs:
;   FAT_DOC_PATH.
;
; Outputs:
;   FAT_ACTIVE_DIR initialized.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SET_DIR_FROM_DOC_PATH:
	PUSH BC
	PUSH DE
	PUSH HL

	LD HL,FAT_DOC_PATH
	LD A,(HL)
	OR A
	JR Z,SDFDP_SET_ROOT		; Empty -> set root

	; BC tracks candidate pointer to last slash
	LD B,H
	LD C,L
SDFDP_SCAN:
	LD A,(HL)
	OR A
	JR Z,SDFDP_END
	CP '/'
	JR NZ,SDFDP_NEXT
	LD B,H
	LD C,L
SDFDP_NEXT:
	INC HL
	JR SDFDP_SCAN

SDFDP_END:
	; BC points to the last slash in FAT_DOC_PATH
	LD HL,FAT_DOC_PATH
	LD A,B
	CP H
	JR NZ,SDFDP_HAS_SUBDIR
	LD A,C
	CP L
	JR NZ,SDFDP_HAS_SUBDIR

SDFDP_SET_ROOT:
	CALL FAT_PATH_SET_ROOT
	POP HL
	POP DE
	POP BC
	RET

SDFDP_HAS_SUBDIR:
	; Copy from FAT_DOC_PATH up to BC into CURRENT_DIR_FAT_PATH
	LD DE,CURRENT_DIR_FAT_PATH
SDFDP_COPY:
	LD A,H
	CP B
	JR NZ,SDFDP_COPY_CHAR
	LD A,L
	CP C
	JR Z,SDFDP_DONE
SDFDP_COPY_CHAR:
	LD A,(HL)
	LD (DE),A
	INC HL
	INC DE
	JR SDFDP_COPY

SDFDP_DONE:
	XOR A
	LD (DE),A
	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; FAT_PATH_SET_ROOT: Set active FAT directory buffer to root ("/")
;
; Purpose:
;   Writes "/" followed by null terminator to FAT_ACTIVE_DIR.
;
; Call Usage / Protocol:
;   Called via CALL when navigating to volume root.
;
; Inputs:
;   None.
;
; Outputs:
;   FAT_ACTIVE_DIR set to "/".
;
; Preserves / Modifies:
;   Clobbers AF, HL.
;------------------------------------------------------------------------------
FAT_PATH_SET_ROOT:
	PUSH BC
	PUSH DE
	PUSH HL
	LD HL,STR_SLASH
	LD DE,CURRENT_DIR_FAT_PATH
	LD BC,2
	LDIR
	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; FAT_PATH_POP_DIR: Navigate up one directory level in FAT path buffer
;
; Purpose:
;   Locates last forward slash in FAT_ACTIVE_DIR and truncates string there,
;   effectively moving up to parent directory ("cd ..").
;
; Call Usage / Protocol:
;   Called via CALL when navigating to parent directory.
;
; Inputs:
;   None.
;
; Outputs:
;   FAT_ACTIVE_DIR truncated to parent path.
;
; Preserves / Modifies:
;   Clobbers AF, HL.
;------------------------------------------------------------------------------
FAT_PATH_POP_DIR:
	PUSH DE
	PUSH HL

	LD HL,CURRENT_DIR_FAT_PATH
	LD A,(HL)
	OR A
	JR Z,FPPD_RESET			; Empty -> set root
	INC HL
	LD A,(HL)
	OR A
	JR Z,FPPD_DONE			; Length 1 ("/") -> already at root

	DEC HL				; Back to start
FPPD_FIND_END:
	LD A,(HL)
	OR A
	JR Z,FPPD_AT_END
	INC HL
	JR FPPD_FIND_END

FPPD_AT_END:
	DEC HL
	LD A,(HL)
	CP '/'
	JR NZ,FPPD_SCAN_PREV_SLASH
	DEC HL

FPPD_SCAN_PREV_SLASH:
	LD DE,CURRENT_DIR_FAT_PATH
	LD A,H
	CP D
	JR NZ,FPPD_CHECK_CHAR
	LD A,L
	CP E
	JR Z,FPPD_RESET			; Reached start -> reset to root

FPPD_CHECK_CHAR:
	LD A,(HL)
	CP '/'
	JR Z,FPPD_FOUND_SLASH
	DEC HL
	JR FPPD_SCAN_PREV_SLASH

FPPD_FOUND_SLASH:
	LD A,H
	CP D
	JR NZ,FPPD_TRUNCATE
	LD A,L
	CP E
	JR NZ,FPPD_TRUNCATE
	INC HL
	XOR A
	LD (HL),A
	JR FPPD_DONE

FPPD_TRUNCATE:
	XOR A
	LD (HL),A
	JR FPPD_DONE

FPPD_RESET:
	CALL FAT_PATH_SET_ROOT

FPPD_DONE:
	POP HL
	POP DE
	RET

;------------------------------------------------------------------------------
; FAT_PATH_PUSH_DIR: Append subdirectory to active FAT directory path buffer
;
; Purpose:
;   Appends '/' and subdirectory name at DE to FAT_ACTIVE_DIR ("cd <dir>").
;
; Call Usage / Protocol:
;   Called via CALL when descending into child subdirectory.
;
; Inputs:
;   DE = Pointer to subdirectory name string.
;
; Outputs:
;   FAT_ACTIVE_DIR updated with child directory path.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
FAT_PATH_PUSH_DIR:
	PUSH BC
	PUSH DE
	PUSH HL

FP_PUSH_SKIP_SP:
	LD A,(HL)
	CP ' '
	JR NZ,FP_PUSH_START
	INC HL
	JR FP_PUSH_SKIP_SP

FP_PUSH_START:
	OR A
	JR Z,FP_PUSH_EXIT		; Empty -> do nothing

	CP '/'
	JR NZ,FP_PUSH_RELATIVE
	CALL FAT_PATH_SET_ROOT
	INC HL
	LD A,(HL)
	OR A
	JR Z,FP_PUSH_EXIT
	CP ' '
	JR Z,FP_PUSH_EXIT

FP_PUSH_RELATIVE:
	LD DE,CURRENT_DIR_FAT_PATH
FP_PUSH_FIND_END:
	LD A,(DE)
	OR A
	JR Z,FP_PUSH_AT_END
	INC DE
	JR FP_PUSH_FIND_END

FP_PUSH_AT_END:
	LD A,(CURRENT_DIR_FAT_PATH)
	OR A
	JR Z,FP_PUSH_ADD_SLASH
	DEC DE
	LD A,(DE)
	INC DE
	CP '/'
	JR Z,FP_PUSH_COPY_CHARS
FP_PUSH_ADD_SLASH:
	LD A,'/'
	LD (DE),A
	INC DE

FP_PUSH_COPY_CHARS:
	LD A,(HL)
	OR A
	JR Z,FP_PUSH_FINISH
	CP ' '
	JR Z,FP_PUSH_FINISH
	CP '/'
	JR NZ,FP_PUSH_REG_CHAR
	INC HL
	LD A,(HL)
	DEC HL
	OR A
	JR Z,FP_PUSH_FINISH
	CP ' '
	JR Z,FP_PUSH_FINISH
	LD A,'/'
	JR FP_PUSH_STORE_CHAR

FP_PUSH_REG_CHAR:
	CALL TO_UPPER
FP_PUSH_STORE_CHAR:
	LD (DE),A
	INC DE
	INC HL
	JR FP_PUSH_COPY_CHARS

FP_PUSH_FINISH:
	XOR A
	LD (DE),A

FP_PUSH_EXIT:
	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; COLLECT_FAT_DIR_ENTRIES: Query directory listing from FAT volume via VFS
;
; Purpose:
;   Sends VFS directory read request packet to driver plugin, storing returned
;   directory entries into DIR_NAMES_BUF and sorting results alphabetically.
;
; Call Usage / Protocol:
;   Called via CALL or JP from COLLECT_DIR_ENTRIES when active drive is FAT.
;
; Inputs:
;   CURRENT_DIR_FAT_UNIT, FAT_ACTIVE_DIR.
;
; Outputs:
;   DIR_NAMES_BUF populated with sorted entries; DIR_FILE_COUNT set.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
COLLECT_FAT_DIR_ENTRIES:
	LD A,1				; VFS_CMD_LIST_DIR
	LD (VFS_REQ_CMD),A
	LD A,(CURRENT_DIR_FAT_UNIT)
	LD (VFS_REQ_UNIT),A
	XOR A
	LD (VFS_REQ_FLAGS),A
	LD (VFS_REQ_STATUS),A
	LD HL,CURRENT_DIR_FAT_PATH
	LD (VFS_REQ_PATH),HL
	LD HL,DIR_NAMES_BUF
	LD (VFS_REQ_BUFFER),HL
	LD HL,255			; Buffer capacity (max entries)
	LD (VFS_REQ_BUFSIZE),HL
	CALL VFS_EXEC_REQUEST
	JR C,CFDE_EMPTY
	LD A,(VFS_REQ_STATUS)
	OR A
	JR NZ,CFDE_EMPTY
	LD HL,(VFS_REQ_COUNT)
	LD A,L
	LD (DIR_FILE_COUNT),A

	; Check if custom filter is active
	LD A,(DIR_FILTER_ACTIVE)
	OR A
	RET Z				; No filter -> done

	; In-place filter DIR_NAMES_BUF against DIR_FILTER_FCB
	CALL FILTER_FAT_DIR_ENTRIES
	RET

CFDE_EMPTY:
	XOR A
	LD (DIR_FILE_COUNT),A
	RET

;------------------------------------------------------------------------------
; FILTER_FAT_DIR_ENTRIES: Filter collected FAT directory entries by wildcard
;
; Purpose:
;   Iterates through entries in DIR_NAMES_BUF, removing entries that do not
;   match DIR_FILTER_BUF pattern and compacting remaining entries in-place.
;
; Call Usage / Protocol:
;   Called via CALL following COLLECT_FAT_DIR_ENTRIES.
;
; Inputs:
;   DIR_FILTER_BUF, DIR_FILE_COUNT.
;
; Outputs:
;   DIR_FILE_COUNT updated with matching count.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
FILTER_FAT_DIR_ENTRIES:
	LD A,(DIR_FILE_COUNT)
	OR A
	RET Z				; Nothing to filter

	LD B,A				; B = entries remaining to check
	LD C,0				; C = kept entries count
	LD HL,DIR_NAMES_BUF		; HL = read pointer
	LD DE,DIR_NAMES_BUF		; DE = write pointer

FFDE_LOOP:
	; Check if entry is a directory (byte 8 == '/')
	PUSH HL
	LD A,8
	ADD A,L
	LD L,A
	LD A,0
	ADC A,H
	LD H,A
	LD A,(HL)
	POP HL
	CP '/'
	JR Z,FFDE_KEEP_ENTRY		; Directories always kept

	; It's a file: compare 8-byte name with DIR_FILTER_FCB+0..7
	PUSH BC
	PUSH DE
	PUSH HL

	LD DE,DIR_FILTER_FCB
	LD B,8
FFDE_MATCH_NAME:
	LD A,(DE)
	CP '?'
	JR Z,FFDE_NAME_CHAR_OK
	CP (HL)
	JR NZ,FFDE_MISMATCH
FFDE_NAME_CHAR_OK:
	INC HL
	INC DE
	DJNZ FFDE_MATCH_NAME

	; Name matched. HL now points to byte 8 ('.'). Skip it.
	INC HL

	; Compare 3-byte extension with DIR_FILTER_FCB+8..10
	LD B,3
FFDE_MATCH_EXT:
	LD A,(DE)
	CP '?'
	JR Z,FFDE_EXT_CHAR_OK
	CP (HL)
	JR NZ,FFDE_MISMATCH
FFDE_EXT_CHAR_OK:
	INC HL
	INC DE
	DJNZ FFDE_MATCH_EXT

	; Both name and extension matched!
	POP HL
	POP DE
	POP BC
	JR FFDE_KEEP_ENTRY

FFDE_MISMATCH:
	POP HL
	POP DE
	POP BC
	; Skip this entry: advance read pointer HL by 13
	LD A,13
	ADD A,L
	LD L,A
	LD A,0
	ADC A,H
	LD H,A
	DEC B
	JR NZ,FFDE_LOOP
	JR FFDE_ALL_DONE

FFDE_KEEP_ENTRY:
	; Check if HL == DE (entry already in place)
	LD A,H
	CP D
	JR NZ,FFDE_DO_COPY
	LD A,L
	CP E
	JR Z,FFDE_ALREADY_IN_PLACE

FFDE_DO_COPY:
	PUSH BC
	LD BC,13
	LDIR
	POP BC
	JR FFDE_ENTRY_KEPT

FFDE_ALREADY_IN_PLACE:
	; Advance both HL and DE by 13
	LD A,13
	ADD A,L
	LD L,A
	LD A,0
	ADC A,H
	LD H,A
	LD D,H
	LD E,L

FFDE_ENTRY_KEPT:
	INC C				; One more entry kept
	DEC B
	JR NZ,FFDE_LOOP

FFDE_ALL_DONE:
	LD A,C
	LD (DIR_FILE_COUNT),A
	RET

;------------------------------------------------------------------------------
; VFS_LOAD_FAT_FILE: Stream file data from FAT volume into far RAM storage
;
; Purpose:
;   Issues VFS open and read requests to driver plugin, reading file chunks,
;   splitting lines, and allocating line table entries in far RAM banks.
;
; Call Usage / Protocol:
;   Called via CALL from HANDLE_OPEN_FAT_FILE.
;
; Inputs:
;   Target FAT file path in VFS_REQ_PKT.
;
; Outputs:
;   Document lines loaded into far RAM; Carry = 0 on success, 1 on error.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
VFS_LOAD_FAT_FILE:
	LD A,2				; VFS_CMD_LOAD_FILE
	LD (VFS_REQ_CMD),A
	XOR A
	LD (VFS_REQ_FLAGS),A
	LD (VFS_REQ_STATUS),A
	LD (VFS_REQ_PATH),HL
	LD DE,0
	LD (VFS_REQ_BUFFER),DE
	LD (VFS_REQ_BUFSIZE),DE
	LD DE,VFS_REQ_PKT
	CALL VFS_EXEC_REQUEST
	RET C				; Return carry if error

	; Update FAT_DOC_UNIT with unit returned by VFS (in case it was 0xFF)
	LD A,(VFS_REQ_UNIT)
	LD (FAT_DOC_UNIT),A
	OR A				; Carry = 0
	RET

;------------------------------------------------------------------------------
; VFS_SAVE_FAT_FILE: Stream document lines from far RAM to FAT volume file
;
; Purpose:
;   Issues VFS create and write requests to driver plugin, writing lines from
;   far RAM line storage to destination FAT file.
;
; Call Usage / Protocol:
;   Called via CALL from HANDLE_SAVE_FAT_FILE.
;
; Inputs:
;   Target FAT file path in VFS_REQ_PKT; document lines in far RAM.
;
; Outputs:
;   File written; Carry = 0 on success, Carry = 1 on write error.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
VFS_SAVE_FAT_FILE:
	LD A,(IS_BLOCK_SAVE_UI)
	OR A
	JR NZ,VSFF_BLOCK_SAVE

	LD A,3				; VFS_CMD_SAVE_FILE
	LD (VFS_REQ_CMD),A
	JR VSFF_DO_SAVE

VSFF_BLOCK_SAVE:
	LD A,4				; VFS_CMD_SAVE_RANGE
	LD (VFS_REQ_CMD),A
	LD HL,(BLOCK_START_ROW)
	LD (VFS_REQ_START_LINE),HL
	LD HL,(BLOCK_END_ROW)
	LD (VFS_REQ_END_LINE),HL

VSFF_DO_SAVE:
	XOR A
	LD (VFS_REQ_FLAGS),A
	LD (VFS_REQ_STATUS),A
	LD HL,FAT_DOC_PATH
	LD (VFS_REQ_PATH),HL
	LD DE,0
	LD (VFS_REQ_BUFFER),DE
	LD (VFS_REQ_BUFSIZE),DE
	LD DE,VFS_REQ_PKT
	CALL VFS_EXEC_REQUEST
	RET C

	LD A,(VFS_REQ_UNIT)
	LD (FAT_DOC_UNIT),A
	OR A
	RET

;------------------------------------------------------------------------------
; PREFILL_FAT_FILENAME_BUF: Prefill filename box with FAT unit, path, and name
;
; Purpose:
;   Formats "U<unit>:<path>/<filename>" into INPUT_FILENAME_BUF for Save As
;   when current document is hosted on a FAT volume.
;
; Call Usage / Protocol:
;   Called via CALL when opening Save As dialog on a FAT file.
;
; Inputs:
;   FAT_DOC_UNIT, FAT_DOC_PATH, FAT_DOC_FNAME.
;
; Outputs:
;   INPUT_FILENAME_BUF prefilled.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
PREFILL_FAT_FILENAME_BUF:
	PUSH BC
	PUSH DE
	PUSH HL
	LD DE,INPUT_FILENAME_BUF
	LD C,0				; Length counter

	LD A,'U'
	LD (DE),A
	INC DE
	INC C

	LD A,(FAT_DOC_UNIT)
	CP 0FFH
	JR Z,PFFB_COLON
	ADD A,'0'
	LD (DE),A
	INC DE
	INC C

PFFB_COLON:
	LD A,':'
	LD (DE),A
	INC DE
	INC C

	; Copy FAT_DOC_PATH
	LD HL,FAT_DOC_PATH
PFFB_PATH_LOOP:
	LD A,(HL)
	OR A
	JR Z,PFFB_DONE
	LD (DE),A
	INC HL
	INC DE
	INC C
	JR PFFB_PATH_LOOP

PFFB_DONE:
	XOR A
	LD (DE),A			; Null terminate
	LD A,C
	LD (INPUT_BUF_LEN),A
	LD (INPUT_CURSOR_POS),A
	POP HL
	POP DE
	POP BC
	RET

; Context Plugin Pop-up String Constants
STR_POPUP_BORDER:
	DB	"+------------------------------------------------+", 0

; Save Changes Modal Pop-up Strings (50 cols x 7 rows)
STR_POPUP_SAVE_TITLE:
	DB "|             Unsaved Modifications              |", 0
STR_POPUP_SAVE_MSG1:
	DB "|  Any unsaved edits will be lost if discarded.  |", 0
STR_POPUP_SAVE_MSG2:
	DB "|                 Save changes?                  |", 0
STR_POPUP_SAVE_KEYS:
	DB "|        [Y]es      [N]o      [ESC]=Cancel       |", 0

; File Truncated Modal Pop-up Strings (50 cols x 7 rows)
STR_POPUP_TRUNC_TITLE:
	DB "|                 File Truncated                 |", 0
STR_POPUP_TRUNC_MSG1:
	DB "| File exceeded capacity and has been truncated. |", 0
STR_POPUP_TRUNC_MSG2:
	DB "|   Save is disabled to protect data on disk.    |", 0
STR_POPUP_TRUNC_KEY:
	DB "|           Press any key to continue            |", 0

; Out of Memory Modal Pop-up Strings (50 cols x 7 rows)
STR_POPUP_OOM_TITLE:
	DB "|                 Out of Memory                  |", 0
STR_POPUP_OOM_MSG1:
	DB "|      Not enough memory for this operation      |", 0
STR_POPUP_OOM_MSG2:
	DB "|      Free memory or reduce document size       |", 0

; File Opening Modal Pop-up Strings (50 cols x 7 rows)
STR_POPUP_OPEN_TITLE:
	DB "|                  Opening File                  |", 0
STR_POPUP_LOAD_TITLE	EQU	STR_POPUP_OPEN_TITLE

; File Inserting Modal Pop-up Strings (50 cols x 7 rows)
STR_POPUP_INSERT_TITLE:
	DB "|                 Inserting File                 |", 0

; File Saving Modal Pop-up Strings (50 cols x 7 rows)
STR_POPUP_SAVING_TITLE:
	DB "|                  Saving File                   |", 0
STR_POPUP_PROGRESS_PFX:
	DB "File: ", 0

; Progress Modal Common Strings (50 cols x 7 rows)
STR_PROGRESS_LINE_LBL:
	DB "Line ", 0
STR_POPUP_PROGRESS_LINE:
	DB "|                   Line     0                   |", 0
STR_POPUP_PROGRESS_SUB:
	DB "|           Please wait for completion           |", 0

; Plugin Notification Modal Pop-up Strings (50 cols x 7 rows)
STR_POPUP_PLUGIN_TITLE:
	DB "|              Plugin Notification               |", 0
STR_POPUP_BLANK_ROW:
	DB "|                                                |", 0

; Find Modal Pop-up Strings (50 cols x 7 rows)
STR_FIND_POPUP_TITLE:
	DB "|                   Find Text                    |", 0
STR_FIND_POPUP_MODE_EXACT:
	DB "|       Search Pattern: [Case Sensitive  ]       |", 0
STR_FIND_POPUP_MODE_INSENS:
	DB "|       Search Pattern: [Case Insensitive]       |", 0
STR_FIND_POPUP_PROMPT:
	DB "|      Find: [", 0
STR_FIND_POPUP_BOX_CLOSE:
	DB "]      |", 0
STR_FIND_POPUP_KEYS:
	DB "| [Enter]=Find   [Tab]=Toggle Case   [ESC]=Cancel |", 0

; Replace Modal Pop-up Strings (50 cols x 7 rows)
STR_REPLACE_POPUP_TITLE:
	DB "|                  Replace Text                  |", 0
STR_REPLACE_POPUP_PROMPT:
	DB "|  Replace with: [", 0
STR_REPLACE_POPUP_BOX_CLOSE:
	DB "] |", 0
STR_REPLACE_POPUP_MSG:
	DB "| Enter replacement text to substitute for match |", 0
STR_REPLACE_POPUP_KEYS:
	DB "|        [Enter]=Confirm     [ESC]=Cancel        |", 0

; Replace Confirmation Modal Pop-up Strings (50 cols x 7 rows)
STR_REP_CONFIRM_TITLE:
	DB "|              Replace Confirmation              |", 0
STR_REP_CONFIRM_MSG1:
	DB "|     Match found for search pattern in text     |", 0
STR_REP_CONFIRM_MSG2:
	DB "|            Replace this occurrence?            |", 0
STR_REP_CONFIRM_KEYS:
	DB "|  [Y]es  [N]o  [A]ll  [R]everse   [ESC]=Cancel  |", 0

; Pattern Not Found Modal Pop-up Strings (50 cols x 7 rows)
STR_POPUP_NOT_FOUND_TITLE:
	DB "|               Pattern Not Found                |", 0
STR_POPUP_NOT_FOUND_MSG1:
	DB "|               Pattern not found.               |", 0
STR_POPUP_NOT_FOUND_MSG2:
	DB "|       Search pattern not found in file.        |", 0

; Search Completed Modal Pop-up Strings (50 cols x 7 rows)
STR_POPUP_SEARCH_COMP_TITLE:
	DB "|                Search Completed                |", 0
STR_POPUP_SEARCH_COMP_MSG1:
	DB "|               Search completed.                |", 0
STR_POPUP_SEARCH_COMP_MSG2:
	DB "|          No further occurrences found.         |", 0

; Line Too Long Modal Pop-up Strings (50 cols x 7 rows)
STR_POPUP_TOO_LONG_TITLE:
	DB "|                 Line Too Long                  |", 0
STR_POPUP_TOO_LONG_MSG1:
	DB "|          Line > 120 chars - skipped.           |", 0
STR_POPUP_TOO_LONG_MSG2:
	DB "|     Line length limit exceeded on replace.     |", 0

; Replace Done Modal Pop-up Strings (50 cols x 7 rows)
STR_POPUP_REP_DONE_TITLE:
	DB "|                  Replace Done                  |", 0
STR_POPUP_REP_DONE_MSG1:
	DB "|         Search and replace completed.          |", 0
STR_REP_DONE_TXT_PFX:
	DB "Replace done: "
STR_REP_DONE_TXT_SFX:
	DB " replacement(s)."

; Goto Line Modal Pop-up Strings (50 cols x 7 rows)
STR_GOTO_POPUP_TITLE:
	DB "|                   Goto Line                    |", 0
STR_GOTO_POPUP_PROMPT:
	DB "|               Goto line: [", 0
STR_GOTO_POPUP_BOX_CLOSE:
	DB "]               |", 0
STR_GOTO_POPUP_MSG:
	DB "|          Enter line number to jump to          |", 0
STR_GOTO_POPUP_KEYS:
	DB "|       [Enter]=Goto Line     [ESC]=Cancel       |", 0

; Overwrite Modal Pop-up Strings (50 cols x 7 rows)
STR_OVERWRITE_POPUP_TITLE:
	DB "|                 Overwrite File                 |", 0
STR_OVERWRITE_POPUP_MSG1:
	DB "|       Existing file contents will be lost      |", 0
STR_OVERWRITE_POPUP_MSG2:
	DB "|        File already exists. Overwrite?         |", 0
STR_DEF_PLUGIN_MGR:	DB	"PLUGIN.PRL", 0
STR_NAME_BEAUTIFY:	DB	"BEAUTIFY", 0

; Plugin Manager Missing Modal Pop-up Strings (50 cols x 7 rows)
STR_POPUP_NEED_PLUG_TITLE:
	DB "|             Plugin Manager Missing             |", 0
STR_POPUP_NEED_PLUG_MSG1:
	DB "|          Feature requires PLUGIN.PRL.          |", 0
STR_POPUP_NEED_PLUG_MSG2:
	DB "|        Unable to load plugin subsystem.        |", 0

; Plugin Missing Modal Pop-up Strings (50 cols x 7 rows)
STR_POPUP_PLUG_MISS_TITLE:
	DB "|                 Plugin Missing                 |", 0
STR_POPUP_PLUG_MISS_MSG1:
	DB "|         Required plugin was not found.         |", 0
STR_POPUP_PLUG_MISS_MSG2:
	DB "|      Unable to execute requested command.      |", 0

; Help Missing Modal Pop-up Strings (50 cols x 7 rows)
STR_POPUP_HELP_MISS_TITLE:
	DB "|                  Help Missing                  |", 0
STR_POPUP_HELP_MISS_MSG1:
	DB "|             HELP.OVL was not found.            |", 0
STR_POPUP_HELP_MISS_MSG2:
	DB "|       Unable to load online help screen.       |", 0

; File Not Found Modal Pop-up Strings (50 cols x 7 rows)
STR_POPUP_FNF_TITLE:
	DB "|                 File Not Found                 |", 0
STR_POPUP_FNF_MSG1:
	DB "|               File was not found.              |", 0
STR_POPUP_FNF_MSG2:
	DB "|        Specified file not found on disk.       |", 0
STR_FNF_MSG1_SFX:
	DB "' was not found.", 0

; RAM Drive Unavailable Modal Pop-up Strings (50 cols x 7 rows)
STR_POPUP_RAMDRV_TITLE:
	DB "|              RAM Drive Unavailable             |", 0
STR_POPUP_RAMDRV_MSG1:
	DB "|      RAM drive is not currently available.     |", 0
STR_POPUP_RAMDRV_MSG2:
	DB "|   Select a valid disk drive (e.g. A: or B:).   |", 0

; FAT Subsystem Missing Modal Pop-up Strings (50 cols x 7 rows)
STR_POPUP_FAT_MISS_TITLE:
	DB "|              FAT Subsystem Missing             |", 0
STR_POPUP_FAT_MISS_MSG1:
	DB "|           Feature requires FATFS.PRL.          |", 0
STR_POPUP_FAT_MISS_MSG2:
	DB "|      FAT filesystem plugin is not loaded.      |", 0

; Block Operations Modal Pop-up Strings (50 cols x 7 rows)
STR_BLOCK_POPUP_TITLE:
	DB "|                Block Operations                |", 0
STR_BLOCK_POPUP_SEL_PRE:
	DB "Selection: "
STR_BLOCK_POPUP_BLK_PRE:
	DB "Marked Block: "
STR_BLOCK_POPUP_KEYS_SEL:
	DB "|  [Enter]=Lock/Set    [^C]=Copy    [^X]=Move    |", 0
STR_BLOCK_POPUP_KEYS_BLK:
	DB "|      [^C]=Copy Block      [^X]=Move Block      |", 0
STR_BLOCK_POPUP_CMDS:
	DB "|  [^D]=Del  [^S]=Save  [^B]=Clear  [ESC]=Close  |", 0

;------------------------------------------------------------------------------
; String Constants & Data
;------------------------------------------------------------------------------
STR_CLEAR_SCREEN:	DB	27,"[2J",27,"[H","$"

STR_HOME:	DB	27,"[H","$"


STR_CLEAR_EOL:	DB	27,"[K","$"

STR_INVERSE_ON:	DB	27,"[7m","$"

STR_INVERSE_OFF:	DB	27,"[0m","$"

STR_HIDE_CURSOR:	DB	27,"[?25l","$"

STR_SHOW_CURSOR:	DB	27,"[?25h","$"

STR_CRLF:	DB	13,10,"$"

STR_SPLASH_TITLE_PAD:	DB	"           ", "$"
STR_SPLASH_TITLE:	DB	"SE - Screen Editor", 13, 10, "$"

STR_SPLASH_CMDS:
	DB "  type   [E]  or  [Enter] to edit",13,10
	DB "  type   [N]              to new file",13,10
	DB "  type   [O]              to open file",13,10
	DB "  type   [S]              to save file",13,10
	DB "  type   [W]  or  [^W]    to close file",13,10
	DB "  type   [L]  or  [^L]    to goto line",13,10
	DB "  type   [A]              for about",13,10
	DB "  type   [M]              for memory info",13,10
	DB "  type   [P]              for plugins",13,10
	DB "  type   [^P]             for context plugin menu",13,10
	DB "  type   [C]              to configure",13,10
	IFDEF TARGET_NEXT
	DB "  type   [1]              set 80x24",13,10
	DB 13,10
	ELSE
	DB "  type   [1]              set 120x40",13,10
	DB "  type   [2]              set 80x24",13,10
	ENDIF
	DB "  type   [Q]  or  [^Q]    to exit",13,10
	DB 0

STR_SPLASH_CUR_MODE:	DB	"Active Screen : [$"
STR_SPLASH_120X40_LBL:	DB	"120x40 (Modern Default)]",13,10,"$"
STR_SPLASH_80X24_LBL:	DB	"80x24 (Classic Terminal)] ",13,10,"$"

STR_SPLASH_RAM_PRE:	DB	"RAM Drive ("
STR_SPLASH_RAM_LTR:	DB	"A:): [$"
STR_SPLASH_RAM_NONE:	DB	"RAM Drive     : [None Detected]",13,10,"$"
STR_SPLASH_RAM_PRESERV:	DB	"Preserved (Active)]",13,10,"$"
STR_SPLASH_RAM_OVERWR:	DB	"Overwritten (Max RAM)]",13,10,"$"
STR_SPLASH_RAM_HIBERN:	DB	"Hibernated (Temp Image)]",13,10,"$"
STR_SPLASH_PLUG_PRE:		DB	"Plugin System : [", "$"
STR_SPLASH_PLUG_OPERATIONAL:	DB	"Operational]", 13, 10, "$"
STR_SPLASH_PLUG_ONDEMAND:	DB	"On Demand]", 13, 10, "$"
STR_SPLASH_PLUG_DISABLED:	DB	"Disabled]", 13, 10, "$"
STR_SPLASH_LINES_PRE:		DB	"Max Lines     : [", "$"
STR_SPLASH_LINES_RAM:		DB	"256 lines (RAM)]", 13, 10, "$"
STR_SPLASH_LINES_16K:		DB	"16,384 lines]", 13, 10, "$"
STR_SPLASH_LINES_32K:		DB	"32,768 lines]", 13, 10, "$"

STR_MODE_120X40_LBL:	DB	"120x40 (Modern Default)]           ",13,10,"$"

STR_MODE_80X24_LBL:	DB	"80x24 (Classic Terminal)]          ",13,10,"$"

STR_CONFIG_TITLE:	DB	"SE - Screen Editor Configuration", "$"

STR_CONFIG_STATUS_LBL:	DB	"Config Status      : [", "$"

STR_CONFIG_CUR_MODE:	DB	"1. Screen Geometry : [", "$"
STR_CONFIG_RAM_DRV_PRE:	DB	"2. RAM Drive (", "$"
STR_CONFIG_RAM_DRV_POST:DB	":)  : [", "$"
STR_CONFIG_RAM_NONE:	DB	"2. RAM Drive       : [", "$"
STR_RAM_PROTECTED_LBL:	DB	"Preserve (RAM Drive Active, 128KB)]",13,10,"$"
STR_RAM_HIBERNATE_LBL:	DB	"Hibernate (Backup/Restore, 384KB)] ",13,10,"$"
STR_RAM_ENABLED_LBL:	DB	"Overwrite (Sacrifice Drive, 384KB)]",13,10,"$"

STR_CONFIG_LINES_LBL:	DB	"3. Max Doc Lines   : [", "$"
STR_LINES_16K_LBL:	DB	"16K (16,384 Lines)]                ",13,10,"$"
STR_LINES_32K_LBL:	DB	"32K (32,768 Lines)]                ",13,10,"$"

STR_CONFIG_TAB_LBL:	DB	"4. Tab Width       : [", "$"
STR_TAB_8_LBL:		DB	"8 Spaces (Default)]                ",13,10,"$"
STR_TAB_4_LBL:		DB	"4 Spaces]                          ",13,10,"$"
STR_CONFIG_PLUG_LBL:	DB	"5. Plugin Manager  : [", "$"
STR_PLUG_AUTO_LBL:	DB	"Autoload (Startup Load)]           ",13,10,"$"
STR_PLUG_ONDEMAND_LBL:	DB	"On Demand (Load When Used)]        ",13,10,"$"
STR_PLUG_DIS_LBL:	DB	"Disabled (Do Not Load)]            ",13,10,"$"
STR_PLUG_NO_FAR_LBL:	DB	"Disabled (No Far RAM)]             ",13,10,"$"


STR_CFG_STAT_NONE:	DB	"Default (No SE.CFG found)]         ",13,10,"$"
STR_CFG_STAT_LOCAL:	DB	"Loaded from local drive ($"
STR_CFG_STAT_PROG:	DB	"Loaded from program drive ($"
STR_CFG_STAT_SAVED:	DB	"Saved to local drive ($"
STR_CFG_STAT_END:	DB	":SE.CFG)]          ",13,10,"$"
STR_CFG_STAT_ERR:	DB	"ERROR writing SE.CFG]              ",13,10,"$"

STR_CONFIG_FOOTER:
	DB "[1-5]=Toggle Option   [S]=Save Config   [ESC]=Exit", "$"

STR_CFG_HDR:		DB	"# SE.CFG - Screen Editor Configuration",13,10,0
STR_KEY_SCREEN_NAME:	DB	"SCREEN",0
STR_KEY_SCREEN_FULL:	DB	"SCREEN=",0
STR_VAL_120X40:		DB	"120x40",13,10,0
STR_VAL_80X24:		DB	"80x24",13,10,0
STR_KEY_RAMD_NAME:	DB	"RAMD",0
STR_KEY_RAMDRIVE_FULL:	DB	"RAMDRIVE=",0
STR_VAL_RAMDRIVE_OFF:	DB	"PRESERVE",13,10,0
STR_VAL_RAMDRIVE_ON:	DB	"OVERWRITE",13,10,0
STR_VAL_RAMDRIVE_HIB:	DB	"HIBERNATE",13,10,0
STR_KEY_TAB_NAME:	DB	"TAB",0
STR_KEY_TAB_FULL:	DB	"TAB=",0
STR_VAL_TAB_8:		DB	"8",13,10,0
STR_VAL_TAB_4:		DB	"4",13,10,0
STR_KEY_LINES_NAME:	DB	"LINE",0
STR_KEY_MAXLINES_NAME:	DB	"MAXLINE",0
STR_KEY_LINES_FULL:	DB	"LINES=",0
STR_VAL_LINES_16K:	DB	"16K",13,10,0
STR_VAL_LINES_32K:	DB	"32K",13,10,0
STR_KEY_PLUGIN_NAME:	DB	"PLUGIN",0
STR_KEY_PLUGIN_FULL:	DB	"PLUGIN=",0
STR_VAL_PLUG_AUTO:	DB	"AUTOLOAD",13,10,0
STR_VAL_PLUG_ONDEMAND:	DB	"ONDEMAND",13,10,0
STR_VAL_PLUG_DIS:	DB	"DISABLED",13,10,0


;------------------------------------------------------------------------------
; About Screen Strings
;------------------------------------------------------------------------------
STR_ABOUT_TITLE:	DB	"SE - Screen Editor", "$"
	IFDEF TARGET_NEXT
STR_ABOUT_VERSION:	DB	"version 1.1.0 (2026-10-09) (Z80 Assembly)", "$"
	ELSE
STR_ABOUT_VERSION:	DB	"version 1.1.0 (2026-10-09)", "$"
	ENDIF
STR_ABOUT_AUTHOR:	DB	"by Dean Jenkins", "$"

STR_ABOUT_AI:
	DB	"Google Antigravity 2.19.1 & Gemini FLASH 3.8 high", "$"
STR_ABOUT_LICENSE:
	DB	"Open source software under the MIT License", "$"
STR_ABOUT_RETURN:	DB	"Press any key to continue", "$"

;------------------------------------------------------------------------------
; Memory Information Screen Strings
;------------------------------------------------------------------------------
STR_MEM_TITLE_PAD:
	DB "                      ","$"	; 22 spaces to center within 72 columns
STR_MEM_INFO_TITLE:
	DB "SE.COM - Extended Memory Map",13,10,"$"
STR_MEM_INFO_BLANK:
	DB "~",13,10,"$"
STR_MEM_TABLE_HDR:
	DB "Bank  Phys   Size   System / OS Role        SE.COM Usage",13,10,"$"
STR_MEM_TABLE_DIV:
	DB "----  ----   ----   ---------------------   "
	DB "----------------------------",13,10,"$"
; 23 spaces to center within 72 columns
STR_MEM_PROMPT_PAD:
	DB "                       ","$"
STR_MEM_RETURN_PROMPT:
	DB "Press any key to continue",13,10,"$"

STR_MEM_SUM_PREFIX:	DB	"HBIOS: ","$"
STR_MEM_SUM_NONE:	DB	"None","$"
STR_MEM_SUM_ROMWBW:	DB	"RomWBW v","$"
STR_MEM_SUM_OS:		DB	" | OS: ","$"
STR_MEM_SUM_RAM:	DB	" | RAM: ","$"
STR_MEM_SUM_RAM_BASE:	DB	"64 KB Base","$"
STR_MEM_SUM_KB_MID:	DB	" KB (","$"
STR_MEM_SUM_X32K:	DB	"x32K)","$"
STR_MEM_SUM_SE:		DB	" | SE: ","$"
STR_MEM_SUM_KB_END:	DB	" KB",13,10,"$"
STR_MEM_SUM_64K_END:	DB	"64 KB",13,10,"$"

STR_OS_ZSYS:		DB	"Z-System","$"
STR_OS_CPM31:		DB	"CP/M 3.1","$"
STR_OS_CPM30:		DB	"CP/M 3.0","$"
STR_OS_CPM22:		DB	"CP/M 2.2","$"

STR_ROLE_HBIOS:		DB	"HBIOS System Firmware","$"
STR_ROLE_RAMDISK:	DB	"RAM Disk (MD0:)      ","$"
STR_ROLE_APP:		DB	"Application Memory   ","$"
STR_ROLE_TPA_CPM2:	DB	"CP/M 2.2 TPA & Base  ","$"
STR_ROLE_TPA_CPM3:	DB	"CP/M 3.1 TPA & Base  ","$"
STR_ROLE_TPA_ZSYS:	DB	"Z-System TPA & Base  ","$"
STR_ROLE_OS:		DB	"Operating System Bank","$"
STR_ROLE_NOT_INST:	DB	"Not Installed        ","$"

STR_USAGE_HBIOS:	DB	"Reserved: Protected HBIOS   ","$"
STR_USAGE_RAMDISK_PRESERVED:
			DB "Preserved: RAM Disk Active  ","$"
STR_USAGE_SE_PROG:	DB	"Active: SE Program & Cache  ","$"
STR_USAGE_LINE_TABLE:	DB	"Active: 16K Line Slot Table ","$"
STR_USAGE_LINE_TABLE_0:	DB	"Active: Line Slots (0..16K) ","$"
STR_USAGE_LINE_TABLE_1:	DB	"Active: Line Slots (16K..32K)","$"
STR_USAGE_PLUGIN_MGR:	DB	"Active: PLUGIN.PRL Subsystem","$"
STR_USAGE_FAR_PLUGINS:	DB	"Active: Far RAM Plugins     ","$"
STR_USAGE_DOC_PFX:	DB	"Active: Doc Buffer Bank ","$"
STR_USAGE_OS:		DB	"Reserved: Operating System  ","$"
STR_USAGE_CPM3_BUFS:	DB	"Reserved: CP/M 3 Buffers    ","$"
STR_USAGE_FREE:		DB	"Free / Unallocated          ","$"
STR_USAGE_NOT_PRES:	DB	"Not Present                 ","$"

STR_MEM_SIZE_32K:	DB	"32K ","$"
STR_MEM_SIZE_NONE:	DB	" -- ","$"
STR_MEM_SIZE_64K:	DB	"64K ","$"
STR_MEM_SPACES_4:	DB	' '
STR_MEM_SPACES_3:	DB	' '
STR_MEM_SPACES_2:	DB	' ', ' ', '$'


STR_STATUS_PREFIX:	DB	" SE v1.1.0 | ","$"


STR_STATUS_120X40:	DB	"120x40 | ","$"

STR_STATUS_80X24:	DB	" 80x24 | ","$"

STR_FMT_CPM:	DB	"CP/M  | ","$"

STR_FMT_LINUX:	DB	"Linux | ","$"

STR_FMT_BLANK:	DB	"      | ","$"

STR_STATUS_KEYS:	DB	"^K: Editor keys | ","$"
STR_STATUS_OVR:		DB	"Overwrite mode  | ","$"
STR_PAN_PREFIX:		DB	"[Pan +","$"

STR_STATUS_FREE:	DB	"Free: ","$"

STR_STATUS_KB:		DB	" KB","$"

STR_SEL_PREFIX:		DB	"Sel: ","$"
STR_BLK_PREFIX:		DB	"Block: ","$"
STR_STAT_LINE_S:	DB	" line","$"
STR_STAT_LINES_S:	DB	" lines","$"
STR_STAT_CHAR_S:	DB	" char","$"
STR_STAT_CHARS_S:	DB	" chars","$"
STR_STAT_L_SUFFIX:	DB	"L","$"
STR_STAT_C_SUFFIX:	DB	"c","$"

STR_STATUS_SEP:	DB	" | ","$"

STR_NO_NAME:	DB	"(Untitled)",0

STR_STATUS_POS:	DB	"Line ","$"

STR_STATUS_LOADING_POS:
	DB	"Line    1/---- Col   0","$"

STR_STATUS_COL:	DB	" Col ","$"

MSG_EXIT:	DB	13,10,"Exiting SE.COM. Returned to CP/M.",13,10,"$"

STR_TITLE_OPEN_PRE:	DB	"OPEN FILE (DIRECTORY - DRIVE ","$"
STR_DIR_DRIVE_CHAR:	DB	"A"
STR_TITLE_SAVE_PRE:	DB	"SAVE FILE (DIRECTORY - DRIVE ","$"
STR_SAVE_DRIVE_CHAR:	DB	"A"
STR_TITLE_BLOCK_SAVE_PRE: DB	"SAVE BLOCK (DIRECTORY - DRIVE ","$"
STR_TITLE_DRIVE_SUF:	DB	":)",13,10,"$"
STR_TITLE_FILTER_PRE:	DB	": [","$"
STR_TITLE_FILTER_SUF:	DB	"])",13,10,"$"

STR_OPEN_PROMPT_TXT:	DB	"Enter filename to open:","$"
STR_TITLE_INSERT_PRE:	DB	"INSERT FILE (DIRECTORY - DRIVE ","$"
STR_INSERT_PROMPT_TXT:	DB	"Enter filename to insert:","$"
STR_TITLE_PLUG_LOAD_PRE: DB	"LOAD PLUGIN (DIRECTORY - DRIVE ","$"
STR_PLUG_LOAD_PROMPT_TXT: DB	"Load Plugin (.PRL/.OVL):","$"

STR_PAGE_PREFIX_TXT:	DB	"[Page ","$"
STR_PAGE_PREFIX:	DB	"~  [Page ","$"

STR_PAGE_MID:		DB	"/","$"

STR_PAGE_SUFFIX:	DB	"]  <PgUp>/<PgDn>=Page",13,10,"$"

STR_NO_FILES_FOUND_TXT:	DB	"[No files found on current drive]",13,10
			DB "~",13,10,"$"
STR_NO_FILES_FOUND:	DB	"~  [No files found on current drive]",13,10
			DB "~",13,10,"$"

DEFAULT_FCB_NAME:	DB	0,"OUTPUT  TXT",0,0,0,0

STR_SAVE_FMT_PREFIX_TXT: DB	"Format: [","$"
STR_SAVE_FMT_PREFIX:	DB	"~  Format: [","$"

STR_SAVE_FMT_CPM:	DB	"CP/M","$"

STR_SAVE_FMT_LINUX:	DB	"Linux","$"

STR_SAVE_FMT_SUFFIX:	DB	"]   [^F]=Toggle Format",13,10,"$"

STR_SAVE_PROMPT_TXT:	DB	"Enter filename to save:","$"

	IFDEF TARGET_NEXT_NATIVE
STR_ESC_CANCEL_TXT:
	DB "[ESC]=Cancel  Enter [path][pattern] to list "
	DB "(e.g. /dot/, *.TXT)",13,10,"$"
STR_ESC_CANCEL:
	DB "~  [ESC]=Cancel  Enter [path][pattern] to list "
	DB "(e.g. /dot/, *.TXT)",13,10,"$"
	ELSE
STR_ESC_CANCEL_TXT:
	DB "[ESC]=Cancel  Enter [d:][u:][pattern] to list "
	DB "(e.g. B:, C1:, 1C:, *.TXT)",13,10,"$"
STR_ESC_CANCEL:
	DB "~  [ESC]=Cancel  Enter [d:][u:][pattern] to list "
	DB "(e.g. B:, C1:, 1C:, *.TXT)",13,10,"$"
	ENDIF

STR_TILDE_INDENT:	DB	"~  ","$"
STR_TILDE_CRLF:		DB	"~",13,10,"$"

STR_FILE_NOT_FOUND:	DB	13,10,"File not found.",13,10,"$"
STR_FILE_NOT_FOUND_SUFFIX:	DB	" file not found",13,10,"$"

