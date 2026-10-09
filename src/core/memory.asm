;==============================================================================
; MEMORY.ASM: Core Subsystem - Virtual Memory Paging & Swap Engine
;
; Purpose:
;   Implements disk-backed virtual memory paging ($$$SE$$$.SWP), Far RAM bank
;   page allocation, LRU victim selection, page fault handling, and slot I/O.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;==============================================================================
; Disk-Backed Virtual Slot Paging Subsystem (Phase 4)
; Transparent 384 KB Far RAM cache backed by $$$SE$$$.SWP via BDOS Random I/O
;==============================================================================

BIT_MASK_TABLE:
	DB 001H, 002H, 004H, 008H, 010H, 020H, 040H, 080H

;------------------------------------------------------------------------------
; TEST_PAGE_ON_DISK: Test if virtual page A has been written to swap file
;
; Purpose:
;   Tests whether virtual swap page A has already been committed to the swap
;   file ($$$SE$$$.SWP) by checking bit A in PAGE_ON_DISK_BITMAP.
;
; Call Usage / Protocol:
;   Called by virtual swap engine before issuing swap reads.
;
; Inputs:
;   A = 8-bit Page Number (0..255).
;
; Outputs:
;   Zero flag set if bit is 0 (not on disk); Non-zero if bit is 1 (on disk).
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; modifies AF (flags).
;------------------------------------------------------------------------------
TEST_PAGE_ON_DISK:
	PUSH BC
	PUSH DE
	PUSH HL
	LD C,A
	AND 7
	LD E,A
	LD D,0
	LD HL,BIT_MASK_TABLE
	ADD HL,DE
	LD B,(HL)			; B = bit mask (1, 2, 4, 8...)

	LD A,C
	RRCA
	RRCA
	RRCA
	AND 01FH			; A = byte offset (0..31)
	LD E,A
	LD HL,PAGE_ON_DISK_BITMAP
	ADD HL,DE
	LD A,(HL)
	AND B				; Test bit: Z if 0, NZ if 1
	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; SET_PAGE_ON_DISK: Mark page A as written to swap file in bitmap
;
; Purpose:
;   Marks virtual swap page A as written to disk by setting bit A in
;   PAGE_ON_DISK_BITMAP.
;
; Call Usage / Protocol:
;   Called after writing a virtual page to $$$SE$$$.SWP.
;
; Inputs:
;   A = 8-bit Page Number (0..255).
;
; Outputs:
;   Bitmap updated.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; modifies AF.
;------------------------------------------------------------------------------
SET_PAGE_ON_DISK:
	PUSH BC
	PUSH DE
	PUSH HL
	LD C,A
	AND 7
	LD E,A
	LD D,0
	LD HL,BIT_MASK_TABLE
	ADD HL,DE
	LD B,(HL)			; B = bit mask

	LD A,C
	RRCA
	RRCA
	RRCA
	AND 01FH
	LD E,A
	LD HL,PAGE_ON_DISK_BITMAP
	ADD HL,DE
	LD A,(HL)
	OR B				; Set bit
	LD (HL),A
	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; CALC_PAGE_SLOT_COUNT: Determine number of active 128-byte slots in page A
;
; Purpose:
;   Computes the number of active 128-byte slots in virtual page A based on
;   NEXT_FRESH_SLOT high and low bytes.
;
; Call Usage / Protocol:
;   Called before swapping a bank to disk or fetching from disk.
;
; Inputs:
;   A = 8-bit Page Number (0..255).
;
; Outputs:
;   Zero flag set if 0 slots; NZ set with B = loop count (0 for 256, 1..255).
;
; Preserves / Modifies:
;   Preserves DE; clobbers AF, BC, HL.
;------------------------------------------------------------------------------
CALC_PAGE_SLOT_COUNT:
	PUSH HL
	LD HL,(NEXT_FRESH_SLOT)
	CP H
	JR C,CPSC_FULL			; Page < H_fresh -> full 256 slots
	JR NZ,CPSC_EMPTY		; Page > H_fresh -> empty 0 slots
	; Page == H_fresh
	LD A,L				; A = L_fresh
	OR A
	JR Z,CPSC_EMPTY			; If L_fresh == 0, 0 slots
	LD B,A				; B = L_fresh (1..255)
	POP HL
	OR A				; NZ set
	RET

CPSC_FULL:
	LD B,0				; 0 -> DJNZ executes 256 times
	POP HL
	LD A,1				; NZ set
	OR A
	RET

CPSC_EMPTY:
	POP HL
	XOR A				; Z set
	RET

;------------------------------------------------------------------------------
; CREATE_SWAP_FILE: Create temporary virtual swap file $$$SE$$$.SWP on disk
;
; Purpose:
;   Initializes SWAP_FCB on active document drive, deletes any preexisting
;   temporary swap file, and creates a fresh $$$SE$$$.SWP via BDOS function 22.
;
; Call Usage / Protocol:
;   Called when first virtual page fault occurs.
;
; Inputs:
;   WORK_FCB (determines target drive).
;
; Outputs:
;   Carry = 0 on success (SWAP_ACTIVE = 1); Carry = 1 on error.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
CREATE_SWAP_FILE:
	PUSH BC
	PUSH DE
	PUSH HL

	; Initialize SWAP_FCB with drive matching document (WORK_FCB)
	LD A,(WORK_FCB)
	LD (SWAP_FCB),A
	LD HL,SWAP_FCB+1
	LD (HL),'$'
	INC HL
	LD (HL),'$'
	INC HL
	LD (HL),'$'
	INC HL
	LD (HL),'S'
	INC HL
	LD (HL),'E'
	INC HL
	LD (HL),'$'
	INC HL
	LD (HL),'$'
	INC HL
	LD (HL),'$'
	INC HL
	LD (HL),'S'
	INC HL
	LD (HL),'W'
	INC HL
	LD (HL),'P'
	INC HL

	; Zero bytes 12..35 (24 bytes)
	LD B,24
CSF_ZERO1:
	LD (HL),0
	INC HL
	DJNZ CSF_ZERO1

	; Delete any existing $$$SE$$$.SWP (BDOS 19)
	LD DE,SWAP_FCB
	LD C,19
	CALL BDOS_ENTRY

	; Re-zero bytes 12..35 after delete
	LD HL,SWAP_FCB+12
	LD B,24
CSF_ZERO2:
	LD (HL),0
	INC HL
	DJNZ CSF_ZERO2

	; Create $$$SE$$$.SWP (BDOS 22)
	LD DE,SWAP_FCB
	LD C,22
	CALL BDOS_ENTRY
	CP 0FFH
	JR Z,CSF_FAIL

	LD A,1
	LD (SWAP_ACTIVE),A

	POP HL
	POP DE
	POP BC
	OR A				; Carry = 0
	RET

CSF_FAIL:
	POP HL
	POP DE
	POP BC
	SCF				; Carry = 1
	RET

;------------------------------------------------------------------------------
; CLEANUP_SWAP_FILE: Close and delete temporary swap file $$$SE$$$.SWP
;
; Purpose:
;   Closes and deletes temporary virtual swap file $$$SE$$$.SWP via BDOS
;   functions 16 and 19 if swap is active.
;
; Call Usage / Protocol:
;   Called on exit, close document, or paging initialization.
;
; Inputs:
;   SWAP_ACTIVE.
;
; Outputs:
;   Swap file deleted; SWAP_ACTIVE cleared to 0.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
CLEANUP_SWAP_FILE:
	LD A,(SWAP_ACTIVE)
	OR A
	RET Z				; Inactive: nothing to do

	PUSH BC
	PUSH DE
	PUSH HL

	; Close SWAP_FCB (BDOS 16)
	LD DE,SWAP_FCB
	LD C,16
	CALL BDOS_ENTRY

	; Delete SWAP_FCB (BDOS 19)
	LD DE,SWAP_FCB
	LD C,19
	CALL BDOS_ENTRY

	XOR A
	LD (SWAP_ACTIVE),A

	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; FLUSH_BANK_TO_SWAP: Flush Far RAM bank B to $$$SE$$$.SWP on disk
;
; Purpose:
;   Flushes all active 128-byte slots from Far RAM bank B to temporary swap
;   file $$$SE$$$.SWP using BDOS Random Write (function 34).
;
; Call Usage / Protocol:
;   Called by page fault handler when evicting a dirty bank.
;
; Inputs:
;   B = bank index (1..11), SWAP_PAGE_OLD = page number.
;
; Outputs:
;   Carry = 0 on success; Carry = 1 on write error (triggers OOM).
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
FLUSH_BANK_TO_SWAP:
	; Determine Far RAM bank ID
	LD HL,EXT_BANK_TABLE
	LD E,B
	LD D,0
	ADD HL,DE
	LD A,(HL)
	LD (SWAP_BNK_ID),A

	; Calculate number of slots to flush
	LD A,(SWAP_PAGE_OLD)
	CALL CALC_PAGE_SLOT_COUNT
	JR Z,FBTS_DONE_SUCCESS

	; 1. Set BDOS DMA to SWAP_IO_BUF once before loop
	PUSH BC				; Save B = slot count
	LD DE,SWAP_IO_BUF
	LD C,26				; BDOS Set DMA
	CALL BDOS_ENTRY
	POP BC				; Restore B

	; 2. Setup SWAP_FCB random record high bytes once before loop
	LD A,(SWAP_PAGE_OLD)
	LD (SWAP_FCB+34),A		; r1
	XOR A
	LD (SWAP_FCB+35),A		; r2

	LD C,0				; C = slot index (0..N-1)
	LD HL,0			; HL = Far RAM source offset (0, 128, 256...)

FBTS_SLOT_LOOP:
	PUSH BC			; Save B (remaining count), C (slot index)
	PUSH HL				; Save Far RAM offset

	; Setup SWAP_FCB record r0 = C, r1 = SWAP_PAGE_OLD, r2 = 0
	LD A,C
	LD (SWAP_FCB+33),A		; r0
	LD A,(SWAP_PAGE_OLD)
	LD (SWAP_FCB+34),A		; r1
	XOR A
	LD (SWAP_FCB+35),A		; r2

	; SYSSETCPY: D = CPM_USER_BANK, E = SWAP_BNK_ID, HL = 128
	PUSH IX
	LD B,0F4H			; SYSSETCPY
	LD A,(CPM_USER_BANK)
	LD D,A
	LD A,(SWAP_BNK_ID)
	LD E,A
	LD HL,FAR_SLOT_SIZE		; 128 bytes
	IFDEF TARGET_NEXT
	CALL NEXT_SYSSETCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	; Copy slot from Far RAM offset HL to local SWAP_IO_BUF
	POP HL				; HL = Far RAM source offset
	PUSH HL
	LD DE,SWAP_IO_BUF
	PUSH IX
	LD B,0F5H			; SYSBNKCPY
	IFDEF TARGET_NEXT
	CALL NEXT_SYSBNKCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	; BDOS 34 (Write Random)
	LD DE,SWAP_FCB
	LD C,34
	CALL BDOS_ENTRY
	OR A
	JR NZ,FBTS_WRITE_ERR

	; Advance Far RAM offset by 128 for next slot
	POP HL
	LD DE,FAR_SLOT_SIZE
	ADD HL,DE

	POP BC
	INC C
	DJNZ FBTS_SLOT_LOOP

	; Flush complete: mark page on disk in bitmap
	LD A,(SWAP_PAGE_OLD)
	CALL SET_PAGE_ON_DISK

	; Restore BDOS DMA to DEFAULT_DMA (0x0080)
	LD DE,DEFAULT_DMA
	LD C,26
	CALL BDOS_ENTRY

FBTS_DONE_SUCCESS:
	OR A				; Carry = 0
	RET

FBTS_WRITE_ERR:
	POP HL
	POP BC
	; Restore BDOS DMA to DEFAULT_DMA (0x0080)
	LD DE,DEFAULT_DMA
	LD C,26
	CALL BDOS_ENTRY

	LD A,1
	LD (FILE_IS_TRUNCATED),A
	CALL SET_OOM_STATUS
	SCF				; Carry = 1
	RET

;------------------------------------------------------------------------------
; FETCH_PAGE_FROM_SWAP: Read page from $$$SE$$$.SWP into Far RAM bank B
;
; Purpose:
;   Reads 128-byte slots from temporary swap file $$$SE$$$.SWP into Far RAM
;   bank B using BDOS Random Read (function 33).
;
; Call Usage / Protocol:
;   Called by page fault handler when paging in an on-disk page.
;
; Inputs:
;   B = bank index (1..11), SWAP_PAGE_NEW = page number.
;
; Outputs:
;   Carry = 0 on success; Carry = 1 on read error.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
FETCH_PAGE_FROM_SWAP:
	; Determine Far RAM bank ID
	LD HL,EXT_BANK_TABLE
	LD E,B
	LD D,0
	ADD HL,DE
	LD A,(HL)
	LD (SWAP_BNK_ID),A

	; Calculate number of slots to fetch
	LD A,(SWAP_PAGE_NEW)
	CALL CALC_PAGE_SLOT_COUNT
	JP Z,FPFS_DONE_SUCCESS

	; 1. Set BDOS DMA to SWAP_IO_BUF once before loop
	PUSH BC
	LD DE,SWAP_IO_BUF
	LD C,26
	CALL BDOS_ENTRY
	POP BC

	; 2. Setup SWAP_FCB random record high bytes once before loop
	LD A,(SWAP_PAGE_NEW)
	LD (SWAP_FCB+34),A		; r1
	XOR A
	LD (SWAP_FCB+35),A		; r2

	LD C,0				; C = slot index (0..N-1)
	LD HL,0			; HL = Far RAM dest offset (0, 128, 256...)

FPFS_SLOT_LOOP:
	PUSH BC
	PUSH HL

	; Setup SWAP_FCB record r0 = C, r1 = SWAP_PAGE_NEW, r2 = 0
	LD A,C
	LD (SWAP_FCB+33),A		; r0
	LD A,(SWAP_PAGE_NEW)
	LD (SWAP_FCB+34),A		; r1
	XOR A
	LD (SWAP_FCB+35),A		; r2

	; BDOS 33 (Read Random)
	LD DE,SWAP_FCB
	LD C,33
	CALL BDOS_ENTRY
	OR A
	JR Z,FPFS_READ_OK

	; Unwritten record / EOF: zero-fill buffer
	LD HL,SWAP_IO_BUF
	LD (HL),0
	LD DE,SWAP_IO_BUF+1
	LD BC,127
	LDIR

FPFS_READ_OK:
	; SYSSETCPY: D = SWAP_BNK_ID, E = CPM_USER_BANK, HL = 128
	PUSH IX
	LD B,0F4H			; SYSSETCPY
	LD A,(SWAP_BNK_ID)
	LD D,A
	LD A,(CPM_USER_BANK)
	LD E,A
	LD HL,FAR_SLOT_SIZE		; 128 bytes
	IFDEF TARGET_NEXT
	CALL NEXT_SYSSETCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	; Copy slot from SWAP_IO_BUF into Far RAM offset
	POP DE				; DE = Far RAM dest offset
	PUSH DE
	LD HL,SWAP_IO_BUF		; Local source buffer
	PUSH IX
	LD B,0F5H			; SYSBNKCPY
	IFDEF TARGET_NEXT
	CALL NEXT_SYSBNKCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	; Advance Far RAM offset by 128 for next slot
	POP HL
	LD DE,FAR_SLOT_SIZE
	ADD HL,DE

	POP BC
	INC C
	DJNZ FPFS_SLOT_LOOP

	; Restore BDOS DMA to DEFAULT_DMA (0x0080)
	LD DE,DEFAULT_DMA
	LD C,26
	CALL BDOS_ENTRY

FPFS_DONE_SUCCESS:
	OR A				; Carry = 0
	RET

;------------------------------------------------------------------------------
; SELECT_VICTIM_BANK: Select resident bank with maximum distance from target
;
; Purpose:
;   Selects a resident Far RAM bank (1..EXT_BANK_COUNT-1) to evict, choosing
;   the bank whose resident page has maximum numerical distance from target
;   page. Bank 0 is pinned and never evicted.
;
; Call Usage / Protocol:
;   Called by page fault handler.
;
; Inputs:
;   SWAP_PAGE_TEMP = target page number (0..255).
;
; Outputs:
;   B = selected victim bank index (1..11).
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
SELECT_VICTIM_BANK:
	LD A,(EXT_BANK_COUNT)
	CP 2
	JR C,SVB_FAIL
	LD C,1		; C = candidate bank index (1 .. EXT_BANK_COUNT-1)
	LD B,1				; B = best victim bank index
	LD D,0				; D = max distance found so far
	LD HL,BANK_PAGE_TABLE+1
SVB_LOOP:
	LD A,(EXT_BANK_COUNT)
	CP C
	JR Z,SVB_DONE
	JR C,SVB_DONE
	LD A,(SWAP_PAGE_TEMP)
	SUB (HL)			; A = target - resident
	JR NC,SVB_POS
	NEG				; A = abs(target - resident)
SVB_POS:
	CP D
	JR C,SVB_NOT_MAX
	JR Z,SVB_NOT_MAX
	LD D,A				; New max distance
	LD B,C				; Best victim bank = C
SVB_NOT_MAX:
	INC HL
	INC C
	JR SVB_LOOP
SVB_DONE:
	RET

SVB_FAIL:
	LD B,0
	RET

;------------------------------------------------------------------------------
; HANDLE_PAGE_FAULT: Resolve virtual page fault by evicting and loading page
;
; Purpose:
;   Handles a page fault for non-resident virtual page SWAP_PAGE_TEMP.
;   Ensures swap file exists, selects a victim bank, flushes victim bank
;   if dirty, reads target page from disk if present, and updates tables.
;
; Call Usage / Protocol:
;   Called from ENSURE_PAGE_RESIDENT on cache miss.
;
; Inputs:
;   SWAP_PAGE_TEMP = target page number.
;
; Outputs:
;   B = allocated victim bank index (1..11), Carry = 0 on success,
;   Carry = 1 on error.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
HANDLE_PAGE_FAULT:
	; Paging requires at least 2 Far RAM banks (Bank 0 is pinned)
	LD A,(EXT_BANK_COUNT)
	CP 2
	JR C,HPF_FAIL

	; Check if swap file is active
	LD A,(SWAP_ACTIVE)
	OR A
	JR NZ,HPF_HAVE_SWAP

	CALL CREATE_SWAP_FILE
	RET C

HPF_HAVE_SWAP:
	; Select victim bank with maximum distance from SWAP_PAGE_TEMP
	CALL SELECT_VICTIM_BANK		; Returns B = victim bank index (1..11)

	; Check if victim bank B is dirty
	PUSH BC
	LD HL,BANK_DIRTY_TABLE
	LD E,B
	LD D,0
	ADD HL,DE
	LD A,(HL)
	OR A
	JR Z,HPF_SKIP_FLUSH

	; Flush dirty victim bank B
	LD HL,BANK_PAGE_TABLE
	ADD HL,DE
	LD A,(HL)			; A = OLD_PAGE resident in bank B
	LD (SWAP_PAGE_OLD),A
	CALL FLUSH_BANK_TO_SWAP
	POP BC
	RET C				; Return Carry = 1 if flush error
	JR HPF_DO_FETCH

HPF_SKIP_FLUSH:
	POP BC

HPF_DO_FETCH:
	; Check if target page (SWAP_PAGE_TEMP) exists on disk
	PUSH BC
	LD A,(SWAP_PAGE_TEMP)
	CALL TEST_PAGE_ON_DISK
	JR Z,HPF_SKIP_FETCH		; Bit = 0 -> not on disk, skip fetch!

	LD A,(SWAP_PAGE_TEMP)
	LD (SWAP_PAGE_NEW),A
	CALL FETCH_PAGE_FROM_SWAP
	POP BC
	RET C				; Return Carry = 1 if fetch error
	JR HPF_UPDATE_TBL

HPF_SKIP_FETCH:
	POP BC

HPF_UPDATE_TBL:
	; Update BANK_PAGE_TABLE[B] = SWAP_PAGE_TEMP
	LD HL,BANK_PAGE_TABLE
	LD E,B
	LD D,0
	ADD HL,DE
	LD A,(SWAP_PAGE_TEMP)
	LD (HL),A

	; Clear dirty flag: BANK_DIRTY_TABLE[B] = 0
	LD HL,BANK_DIRTY_TABLE
	ADD HL,DE
	LD (HL),0

	OR A				; Carry = 0 (success)
	RET

HPF_FAIL:
	SCF				; Carry = 1 (paging unavailable)
	RET

;------------------------------------------------------------------------------
; ENSURE_PAGE_RESIDENT: Ensure 32KB virtual page A is resident in Far RAM
;
; Purpose:
;   Ensures 32KB virtual page A is mapped into a physical Far RAM bank.
;   Page 0 is permanently pinned in Bank 0. If non-zero page is not resident,
;   triggers page fault resolution.
;
; Call Usage / Protocol:
;   Called before accessing Far RAM slots.
;
; Inputs:
;   A = 8-bit Page Number (0..255).
;
; Outputs:
;   A = Far RAM Bank ID, Carry = 0 on success, Carry = 1 on error.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; returns bank ID in A.
;------------------------------------------------------------------------------
ENSURE_PAGE_RESIDENT:
	PUSH BC
	PUSH DE
	PUSH HL

	LD (SWAP_PAGE_TEMP),A

	; Check if Page 0 (pinned in Bank 0)
	OR A
	JR NZ,EPR_NOT_PAGE_0
	XOR A
	LD (SWAP_BANK_TEMP),A
	LD A,(EXT_BANK_TABLE)		; Bank 0 ID
	POP HL
	POP DE
	POP BC
	OR A				; Carry = 0
	RET

EPR_NOT_PAGE_0:
	; Guard: Non-zero pages require at least 2 Far RAM banks
	LD A,(EXT_BANK_COUNT)
	CP 2
	JR C,EPR_FAULT_ERR

	; Scan BANK_PAGE_TABLE[1..EXT_BANK_COUNT-1] for Page (SWAP_PAGE_TEMP)
	LD B,1				; Bank index 1..EXT_BANK_COUNT-1
	LD HL,BANK_PAGE_TABLE+1
EPR_SCAN_LOOP:
	LD A,(EXT_BANK_COUNT)
	CP B
	JR Z,EPR_PAGE_FAULT
	JR C,EPR_PAGE_FAULT
	LD A,(SWAP_PAGE_TEMP)
	CP (HL)
	JR Z,EPR_HIT
	INC HL
	INC B
	JR EPR_SCAN_LOOP

EPR_PAGE_FAULT:
	; PAGE FAULT! Page (SWAP_PAGE_TEMP) is NOT resident in any bank.
	; Returns B = victim bank index (1..11), Carry on error
	CALL HANDLE_PAGE_FAULT
	JR C,EPR_FAULT_ERR

EPR_HIT:
	LD A,B
	LD (SWAP_BANK_TEMP),A
	; Lookup Far RAM Bank ID in EXT_BANK_TABLE[B]
	LD HL,EXT_BANK_TABLE
	LD E,B
	LD D,0
	ADD HL,DE
	LD A,(HL)			; A = Far RAM Bank ID

	POP HL
	POP DE
	POP BC
	OR A				; Carry = 0
	RET

EPR_FAULT_ERR:
	POP HL
	POP DE
	POP BC
	SCF				; Carry = 1
	RET

;------------------------------------------------------------------------------
; ENSURE_PAGE_RESIDENT_DIRTY: Ensure page A is resident and mark bank dirty
;
; Purpose:
;   Ensures virtual page A is resident in Far RAM and marks its host bank
;   dirty in BANK_DIRTY_TABLE so changes will be flushed if evicted.
;
; Call Usage / Protocol:
;   Called before writing data to Far RAM slots.
;
; Inputs:
;   A = 8-bit Page Number (0..255).
;
; Outputs:
;   A = Far RAM Bank ID, Carry = 0 on success, Carry = 1 on error.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; returns bank ID in A.
;------------------------------------------------------------------------------
ENSURE_PAGE_RESIDENT_DIRTY:
	CALL ENSURE_PAGE_RESIDENT
	RET C
	PUSH AF
	PUSH HL
	PUSH DE
	; Mark bank SWAP_BANK_TEMP dirty
	LD A,(SWAP_BANK_TEMP)
	LD E,A
	LD D,0
	LD HL,BANK_DIRTY_TABLE
	ADD HL,DE
	LD (HL),1
	POP DE
	POP HL
	POP AF
	OR A				; Carry = 0
	RET

;------------------------------------------------------------------------------
; INIT_PAGING_SYSTEM: Reset paging tables, bitmap, and clean up swap file
;
; Purpose:
;   Cleans up swap file, clears swap active flag, resets victim pointer,
;   zeroes PAGE_ON_DISK_BITMAP, and initializes BANK_PAGE_TABLE and
;   BANK_DIRTY_TABLE.
;
; Call Usage / Protocol:
;   Called via CALL from INIT_SLOT_SYSTEM.
;
; Inputs:
;   None.
;
; Outputs:
;   Paging subsystem reset.
;
; Preserves / Modifies:
;   Preserves all registers: AF, BC, DE, HL.
;------------------------------------------------------------------------------
INIT_PAGING_SYSTEM:
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL

	CALL CLEANUP_SWAP_FILE

	XOR A
	LD (SWAP_ACTIVE),A
	INC A				; A = 1
	LD (NEXT_VICTIM_BANK),A

	; Clear PAGE_ON_DISK_BITMAP (32 bytes)
	LD HL,PAGE_ON_DISK_BITMAP
	LD B,32
IPS_CLEAR_BM:
	LD (HL),0
	INC HL
	DJNZ IPS_CLEAR_BM

	; Initialize BANK_PAGE_TABLE[0..11] = 0..11
	; Initialize BANK_DIRTY_TABLE[0..11] = 0
	LD B,0				; B = index 0..11
	LD HL,BANK_PAGE_TABLE
	LD DE,BANK_DIRTY_TABLE
IPS_INIT_BANKS:
	XOR A
	LD (DE),A			; BANK_DIRTY_TABLE[B] = 0
	LD A,(EXT_BANK_COUNT)
	CP B
	JR Z,IPS_BANK_INVALID
	JR C,IPS_BANK_INVALID
	LD (HL),B			; BANK_PAGE_TABLE[B] = B
	JR IPS_NEXT_BANK
IPS_BANK_INVALID:
	LD A,0FFH
	LD (HL),A			; BANK_PAGE_TABLE[B] = 0xFF (unmapped)
IPS_NEXT_BANK:
	INC HL
	INC DE
	INC B
	LD A,B
	CP MAX_FAR_BANKS
	JR C,IPS_INIT_BANKS

	POP HL
	POP DE
	POP BC
	POP AF
	RET

;------------------------------------------------------------------------------
; WRITE_FAR_SLOT: Write 128-byte line from local memory to Far RAM slot
;
; Purpose:
;   Copies 128 bytes from local user memory HL into Far RAM slot BC.
;   Ensures target virtual page is resident and marked dirty, computes
;   in-bank offset, and invokes HBIOS SYSBNKCPY.
;
; Call Usage / Protocol:
;   Low-level slot writer called by text and line management routines.
;
; Inputs:
;   HL = Local Source Address (in CPM_USER_BANK), BC = 16-bit Virtual Slot ID.
;
; Outputs:
;   Carry = 0 on success, Carry = 1 on paging/memory error.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
WRITE_FAR_SLOT:
	PUSH BC
	PUSH DE
	PUSH HL

	LD (FAR_LOCAL_ADDR),HL

	; Ensure Page B is resident in Far RAM and marked dirty
	LD A,B
	CALL ENSURE_PAGE_RESIDENT_DIRTY
	JR C,WFS_ERR
	LD (FAR_DEST_BANK),A

	; far_offset = C * 128 = (C << 7)
	LD L,C
	LD H,0
	ADD HL,HL			; *2
	ADD HL,HL			; *4
	ADD HL,HL			; *8
	ADD HL,HL			; *16
	ADD HL,HL			; *32
	ADD HL,HL			; *64
	ADD HL,HL			; *128
	LD (FAR_DEST_ADDR),HL

	; SYSSETCPY: D = Dest Bank, E = Src Bank, HL = 128
	PUSH IX
	LD B,0F4H			; SYSSETCPY
	LD A,(FAR_DEST_BANK)
	LD D,A
	LD A,(CPM_USER_BANK)
	LD E,A
	LD HL,FAR_SLOT_SIZE		; 128 bytes
	IFDEF TARGET_NEXT
	CALL NEXT_SYSSETCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	; SYSBNKCPY: HL = Src Addr, DE = Dest Addr
	LD HL,(FAR_LOCAL_ADDR)
	LD DE,(FAR_DEST_ADDR)
	PUSH IX
	LD B,0F5H			; SYSBNKCPY
	IFDEF TARGET_NEXT
	CALL NEXT_SYSBNKCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	POP HL
	POP DE
	POP BC
	OR A				; Carry = 0
	RET

WFS_ERR:
	POP HL
	POP DE
	POP BC
	SCF				; Carry = 1
	RET

;------------------------------------------------------------------------------
; READ_FAR_SLOT: Read 128-byte line from Far RAM slot into local memory
;
; Purpose:
;   Copies 128 bytes from Far RAM slot BC into local user memory DE.
;   Ensures target virtual page is resident in Far RAM and invokes
;   HBIOS SYSBNKCPY.
;
; Call Usage / Protocol:
;   Low-level slot reader called by line management routines.
;
; Inputs:
;   DE = Local Destination Address (in CPM_USER_BANK), BC = 16-bit Slot ID.
;
; Outputs:
;   Carry = 0 on success, Carry = 1 on paging/memory error.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
READ_FAR_SLOT:
	PUSH BC
	PUSH DE
	PUSH HL

	LD (FAR_LOCAL_ADDR),DE

	; Ensure Page B is resident in Far RAM
	LD A,B
	CALL ENSURE_PAGE_RESIDENT
	JR C,RFS_ERR
	LD (FAR_SRC_BANK),A

	; far_offset = C * 128
	LD L,C
	LD H,0
	ADD HL,HL			; *2
	ADD HL,HL			; *4
	ADD HL,HL			; *8
	ADD HL,HL			; *16
	ADD HL,HL			; *32
	ADD HL,HL			; *64
	ADD HL,HL			; *128
	LD (FAR_SRC_ADDR),HL

	; SYSSETCPY: D = Dest Bank (CPM_USER_BANK), E = Src Bank, HL = 128
	PUSH IX
	LD B,0F4H			; SYSSETCPY
	LD A,(CPM_USER_BANK)
	LD D,A
	LD A,(FAR_SRC_BANK)
	LD E,A
	LD HL,FAR_SLOT_SIZE		; 128 bytes
	IFDEF TARGET_NEXT
	CALL NEXT_SYSSETCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	; SYSBNKCPY: HL = Far Src Addr, DE = Local Dest Addr
	LD HL,(FAR_SRC_ADDR)
	LD DE,(FAR_LOCAL_ADDR)
	PUSH IX
	LD B,0F5H			; SYSBNKCPY
	IFDEF TARGET_NEXT
	CALL NEXT_SYSBNKCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	POP HL
	POP DE
	POP BC
	OR A				; Carry = 0
	RET

RFS_ERR:
	POP HL
	POP DE
	POP BC
	SCF				; Carry = 1
	RET


;------------------------------------------------------------------------------
; WRITE_FAR_SLOT_LINE: Write single-stride null-terminated line to slot BC
;
; Purpose:
;   Writes a single-stride null-terminated text line to physical slot BC
;   with NEXT_SLOT_ID initialized to 0xFFFF.
;
; Call Usage / Protocol:
;   Called when storing single-slot lines.
;
; Inputs:
;   HL = Local Source Address, BC = 16-bit Physical Slot ID.
;
; Outputs:
;   Slot written in Far RAM.
;
; Preserves / Modifies:
;   Preserves BC, DE, IX; clobbers AF, HL.
;------------------------------------------------------------------------------
WRITE_FAR_SLOT_LINE:
	PUSH BC
	PUSH DE
	PUSH HL

	; Set NEXT_SLOT_ID = 0xFFFF
	LD DE,0FFFFH
	LD (FAR_IO_BUF),DE

	; Copy characters from HL to FAR_IO_BUF+2
	LD DE,FAR_IO_BUF+2
	LD B,FAR_SLOT_PAYLOAD		; 126
WFSL_COPY:
	LD A,(HL)
	OR A
	JR Z,WFSL_ZERO
	LD (DE),A
	INC HL
	INC DE
	DJNZ WFSL_COPY
	JR WFSL_WRITE

WFSL_ZERO:
	XOR A
	LD (DE),A

WFSL_WRITE:
	POP HL
	POP DE
	POP BC
	PUSH BC
	PUSH DE
	PUSH HL
	LD HL,FAR_IO_BUF
	CALL WRITE_FAR_SLOT
	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; WRITE_FAR_LINE: Write null-terminated line to document line BC slot chain
;
; Purpose:
;   Writes null-terminated text line from local memory HL to document line
;   BC. Chains multiple 126-byte payload slots if line exceeds single slot,
;   reusing existing extension slots or allocating fresh ones, and frees
;   trailing unused slots.
;
; Call Usage / Protocol:
;   Primary line storage writer called when saving or committing lines.
;
; Inputs:
;   HL = Local Source Address, BC = 16-bit Document Line Index.
;
; Outputs:
;   Line written to Far RAM slot chain.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
WRITE_FAR_LINE:
	PUSH BC
	PUSH DE
	PUSH HL

	LD (FAR_SRC_LINE_PTR),HL	; Save local source address

	; Lookup head slot ID for line BC
	CALL GET_LINE_SLOT		; HL = head physical slot ID
	LD (FAR_CUR_SLOT),HL
	LD B,H
	LD C,L				; BC = head physical slot ID

	; Read existing head slot into FAR_IO_BUF to check for existing
	; NEXT_SLOT_ID
	LD DE,FAR_IO_BUF
	CALL READ_FAR_SLOT
	LD HL,(FAR_IO_BUF)
	; Save previous extension slot ID (or 0xFFFF)
	LD (FAR_OLD_NEXT_SLOT),HL

WFL_STRIDE_LOOP:
	; Prepare current stride payload in FAR_IO_BUF+2
	LD HL,(FAR_SRC_LINE_PTR)
	LD DE,FAR_IO_BUF+2
	LD B,FAR_SLOT_PAYLOAD		; 126
WFL_COPY_PAYLOAD:
	LD A,(HL)
	OR A
	JR Z,WFL_STRIDE_EOL
	LD (DE),A
	INC HL
	INC DE
	DJNZ WFL_COPY_PAYLOAD

	; 126 chars copied! Check if next char in HL is null
	LD A,(HL)
	OR A
	JR Z,WFL_STRIDE_EOL

	; Line continues into next stride!
	LD (FAR_SRC_LINE_PTR),HL	; Update source line pointer

	; Check if we can reuse FAR_OLD_NEXT_SLOT
	LD DE,(FAR_OLD_NEXT_SLOT)
	LD A,D
	AND E
	INC A
	JR NZ,WFL_REUSE_SLOT		; If DE != 0xFFFF, reuse it!

	; Need fresh slot
	PUSH HL
	CALL ALLOC_SLOT			; HL = new slot ID, Carry on error
	EX DE,HL			; DE = new slot ID
	POP HL
	JR C,WFL_OOM_TRUNCATE

	; Link and write current stride
	LD (FAR_IO_BUF),DE		; NEXT_SLOT_ID = new slot ID
	PUSH DE				; Save new slot ID
	LD BC,(FAR_CUR_SLOT)
	LD HL,FAR_IO_BUF
	CALL WRITE_FAR_SLOT
	POP DE				; DE = new slot ID

	LD (FAR_CUR_SLOT),DE		; Advance to new slot
	LD HL,0FFFFH
	LD (FAR_OLD_NEXT_SLOT),HL	; Fresh slot has no old next slot
	JR WFL_STRIDE_LOOP

WFL_OOM_TRUNCATE:
	LD DE,0FFFFH
	CALL SET_OOM_STATUS
	JR WFL_STRIDE_EOL

WFL_REUSE_SLOT:
	; DE is slot ID to reuse.
	; Link and write current stride:
	LD (FAR_IO_BUF),DE		; NEXT_SLOT_ID = reused slot ID
	PUSH DE				; Save reused slot ID
	LD BC,(FAR_CUR_SLOT)
	LD HL,FAR_IO_BUF
	CALL WRITE_FAR_SLOT
	POP BC				; BC = reused slot ID
	LD (FAR_CUR_SLOT),BC

	; Read this reused slot into FAR_IO_BUF to fetch ITS old next slot!
	LD DE,FAR_IO_BUF
	CALL READ_FAR_SLOT
	LD HL,(FAR_IO_BUF)
	LD (FAR_OLD_NEXT_SLOT),HL	; Save next extension slot ID
	JR WFL_STRIDE_LOOP

WFL_STRIDE_EOL:
	XOR A
	LD (DE),A			; Null terminate payload in FAR_IO_BUF
	LD DE,0FFFFH
	LD (FAR_IO_BUF),DE		; NEXT_SLOT_ID = 0xFFFF

	; Write final stride to Far RAM
	LD BC,(FAR_CUR_SLOT)
	LD HL,FAR_IO_BUF
	CALL WRITE_FAR_SLOT

	; If line previously had further extension slots, free them now!
	LD HL,(FAR_OLD_NEXT_SLOT)
	LD A,H
	AND L
	INC A
	JR Z,WFL_ALL_DONE
	CALL FREE_LINE_CHAIN

WFL_ALL_DONE:
	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; READ_FAR_LINE_MAX: Read line from document line BC up to HL max bytes
;
; Purpose:
;   Reads characters from document line BC's Far RAM slot chain into local
;   memory buffer DE up to HL maximum payload bytes, traversing slot
;   extension links and null-terminating destination.
;
; Call Usage / Protocol:
;   Primary line reader for cache, clipboard, and active buffer.
;
; Inputs:
;   DE = Local Destination Address, BC = Document Line Index, HL = Max bytes.
;
; Outputs:
;   Text line loaded into DE and null-terminated.
;
; Preserves / Modifies:
;   Preserves BC, DE; clobbers AF, HL.
;------------------------------------------------------------------------------
READ_FAR_LINE_MAX:
	PUSH BC
	PUSH DE
	PUSH HL

	LD (FAR_DEST_LINE_PTR),DE
	LD (FAR_READ_MAX_BYTES),HL

	; Lookup head slot ID for line BC
	CALL GET_LINE_SLOT		; HL = head physical slot ID
	LD (FAR_CUR_SLOT),HL
	LD B,H
	LD C,L				; BC = head physical slot ID

RFLM_STRIDE_LOOP:
	; Check if slot ID is 0xFFFF
	LD A,B
	AND C
	INC A
	JR Z,RFLM_DONE

	; Read slot BC into FAR_IO_BUF
	LD DE,FAR_IO_BUF
	CALL READ_FAR_SLOT

	; Next slot ID is in FAR_IO_BUF[0..1]
	LD HL,(FAR_IO_BUF)
	LD (FAR_NEW_NEXT_SLOT),HL

	; Copy characters from FAR_IO_BUF+2 to destination
	LD HL,FAR_IO_BUF+2
	LD DE,(FAR_DEST_LINE_PTR)
	LD B,FAR_SLOT_PAYLOAD		; 126
RFLM_COPY_LOOP:
	LD A,(HL)
	OR A
	JR Z,RFLM_DONE_EARLY		; Null terminator encountered!
	LD (DE),A
	INC HL
	INC DE
	LD (FAR_DEST_LINE_PTR),DE

	; Decrement remaining max bytes
	PUSH HL
	LD HL,(FAR_READ_MAX_BYTES)
	DEC HL
	LD (FAR_READ_MAX_BYTES),HL
	LD A,H
	OR L
	POP HL
	JR Z,RFLM_DONE_EARLY		; Reached max capacity!
	DJNZ RFLM_COPY_LOOP

	; Stride exhausted (all 126 bytes copied), advance to next slot
	LD BC,(FAR_NEW_NEXT_SLOT)
	LD (FAR_CUR_SLOT),BC
	JR RFLM_STRIDE_LOOP

RFLM_DONE_EARLY:
RFLM_DONE:
	LD DE,(FAR_DEST_LINE_PTR)
	XOR A
	LD (DE),A			; Guarantee null terminator
	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; READ_FAR_LINE: Read line for local LINE_STORAGE cache slot
;
; Purpose:
;   Wrapper for READ_FAR_LINE_MAX that reads up to 254 bytes into destination
;   DE for standard LINE_STORAGE cache slots.
;
; Call Usage / Protocol:
;   Called by cache window manager.
;
; Inputs:
;   DE = Local Destination Address, BC = 16-bit Document Line Index.
;
; Outputs:
;   Line loaded into DE.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
READ_FAR_LINE:
	PUSH HL
	LD HL,MAX_LINE_STRIDE-2		; 254 bytes
	CALL READ_FAR_LINE_MAX
	POP HL
	RET

