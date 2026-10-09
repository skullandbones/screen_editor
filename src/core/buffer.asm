;==============================================================================
; BUFFER.ASM: Core Subsystem - Document Buffer, Line Table & Cache Engine
;
; Purpose:
;   Implements Far RAM line tables, active line editing workspace, slot
;   allocation/deallocation, and working line cache window management.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; 512KB HBIOS RAM Far-Banking Multi-Bank Document Engine
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; BUFFER_INIT: Initialize document buffers, Far RAM banking, and empty document
;
; Purpose:
;   Clears working cache (LINE_STORAGE), temporary line buffer (LOAD_LINE_TEMP),
;   and Far RAM I/O buffer (FAR_IO_BUF). Probes memory banking via
;   INIT_FAR_RAM_BANKS, resets slot allocator via INIT_SLOT_SYSTEM,
;   invalidates active line buffer, and creates initial empty document.
;
; Call Usage / Protocol:
;   Called via CALL during START initialization.
;
; Inputs:
;   None.
;
; Outputs:
;   Buffer memory cleared, Far RAM banks configured, empty doc ready.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
BUFFER_INIT:
	; Clear LINE_STORAGE with 0
	LD HL,LINE_STORAGE
	LD DE,LINE_STORAGE+1
	LD BC,LINE_STORAGE_SIZE-1
	LD (HL),0
	LDIR

	; Clear LOAD_LINE_TEMP (256 bytes)
	LD HL,LOAD_LINE_TEMP
	LD DE,LOAD_LINE_TEMP+1
	LD BC,255
	LD (HL),0
	LDIR

	; Clear FAR_IO_BUF (128 bytes)
	LD HL,FAR_IO_BUF
	LD DE,FAR_IO_BUF+1
	LD BC,127
	LD (HL),0
	LDIR

	XOR A
	LD (NEED_SCREEN_RENDER),A
	LD (NEED_LINE_RENDER),A
	LD (NEED_STATUS_RENDER),A
	LD A,1
	LD (INSERT_MODE),A

	CALL INIT_FAR_RAM_BANKS
	CALL INIT_SLOT_SYSTEM
	CALL INVALIDATE_ACTIVE_LINE
	CALL INIT_EMPTY_DOCUMENT
	RET

;------------------------------------------------------------------------------
; INIT_FAR_RAM_BANKS: Probe RomWBW HBIOS banking and allocate Far RAM banks
;
; Purpose:
;   Queries RomWBW HBIOS for active CP/M bank, total RAM banks, and BIOS bank.
;   Determines safe RAM banking boundaries respecting protected or hibernated
;   RAM drives. Allocates 1 or 2 Line Table banks (for 16K or 32K doc lines)
;   and populates EXT_BANK_TABLE with available Far RAM text banks.
;
; Call Usage / Protocol:
;   Called via CALL from BUFFER_INIT.
;
; Inputs:
;   CFG_RAMDRIVE_FLAG, CFG_LINES_MODE.
;
; Outputs:
;   LINE_TABLE_BANK, LINE_TABLE_BANK_1, EXT_BANK_TABLE, EXT_BANK_COUNT.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
INIT_FAR_RAM_BANKS:
	IFDEF TARGET_NEXT
	CALL NEXT_MEM_INIT
	RET
	ELSE
	; 1. Query CP/M Active User Bank
	PUSH IX
	LD B,0F3H			; SYSGETBNK
	RST 08H
	POP IX
	LD A,C
	LD (CPM_USER_BANK),A

	; 2. Query Total RAM Banks (SYSGET 0xF1)
	PUSH IX
	LD B,0F8H
	LD C,0F1H
	RST 08H
	POP IX
	LD A,E
	LD (RAM_BANK_COUNT),A
	LD A,D
	LD (ROM_BANK_COUNT),A

	; 3. Query Bank Info to obtain BIOS Bank ID (SYSGET 0xF2)
	; Returns: D = BIOS Bank ID (e.g. 0x80), E = User Bank ID
	PUSH IX
	LD B,0F8H
	LD C,0F2H
	RST 08H
	POP IX
	; Ensure D is at least 0x80 in case of unexpected return
	LD A,D
	OR A
	JR NZ,IFRB_GOT_BIOS_BANK
	LD D,080H
IFRB_GOT_BIOS_BANK:

	; Check if RAM drive memory blocks should be used or protected
	; Mode 0 (Protected): Protect banks 0x81..0x88
	; Mode 1 (Enabled): Unconditionally allow banks down to 0x80
	; Mode 2 (Hibernate): Allow banks down to 0x80 ONLY IF
	; RAMDRIVE_IS_HIBERNATED == 1
	LD A,(CFG_RAMDRIVE_FLAG)
	CP RAMDRV_MODE_ENABLED
	JR Z,IFRB_FLOOR_SET	; If 1, use D = 0x80 (allow RAM drive blocks)
	CP RAMDRV_MODE_HIBERNATE
	JR NZ,IFRB_PROTECTED_MODE
	LD A,(RAMDRIVE_IS_HIBERNATED)
	CP 1
	JR Z,IFRB_FLOOR_SET		; If hibernated, use D = 0x80

IFRB_PROTECTED_MODE:
	; Protected mode (CFG_RAMDRIVE_FLAG == 0 or not hibernated):
	; Query App Banks (SYSGET 0xF5) to find lowest safe App bank (BID_APP0)
	; Returns: H = First App Bank ID (e.g. 0x89), L = App Bank count (e.g.
	; 3)
	PUSH IX
	LD B,0F8H
	LD C,0F5H			; BF_SYSGET_APPBNKS
	RST 08H
	POP IX
	OR A				; A = 0 on success
	JR NZ,IFRB_NO_APP_BANKS
	LD A,H
	CP 0FFH
	JR Z,IFRB_NO_APP_BANKS
	LD A,L
	OR A
	JR Z,IFRB_NO_APP_BANKS

	; Safe floor is BID_APP0 - 1 (e.g. 0x89 - 1 = 0x88)
	; Downward allocation stops when bank reaches floor, protecting
	; 0x81..0x88
	DEC H
	LD D,H
	JR IFRB_FLOOR_SET

IFRB_NO_APP_BANKS:
	; No application banks reported; floor = CPM_USER_BANK - 1 (safe
	; fallback: 0 ext banks)
	; In CP/M 3.x, reserve Bank 0x8C (Buffers), so floor = CPM_USER_BANK - 2
	LD A,(CPM_USER_BANK)
	DEC A
	PUSH AF
	LD A,(CPM_VERSION_ID)
	CP 030H
	JR C,IFRB_NAB_NOT_CPM3
	POP AF
	DEC A
	JR IFRB_NAB_DONE
IFRB_NAB_NOT_CPM3:
	POP AF
IFRB_NAB_DONE:
	LD D,A

IFRB_FLOOR_SET:
	; 4. Allocate Line Table Banks: below CPM_USER_BANK
	LD A,(CPM_USER_BANK)
	LD C,A				; C = CPM_USER_BANK (e.g. 0x8E)
	DEC C				; C = first Far RAM bank (e.g. 0x8D)
	; In CP/M 3.x, Bank 2 (0x8C) is reserved for OS disk buffers & hash.
	; Decrement C once more so Far RAM begins at 0x8B.
	LD A,(CPM_VERSION_ID)
	CP 030H
	JR C,IFRB_NOT_CPM3
	DEC C				; C = 0x8B under CP/M 3
IFRB_NOT_CPM3:
	LD A,C
	CP D				; Compare with BIOS Bank ID (D)
	JR Z,IFRB_NO_BANKS		; No Far RAM available!
	JR C,IFRB_NO_BANKS
	LD (LINE_TABLE_BANK),A		; Bank 0 for line slots (0..16383)
	XOR A
	LD (LINE_TABLE_BANK_1),A
	LD HL,MAX_DOC_LINES_16K
	LD (MAX_DOC_LINES_LIMIT),HL

	; Check if 32K lines mode requested (CFG_LINES_MODE == 1)
	LD A,(CFG_LINES_MODE)
	OR A
	JR Z,IFRB_ALLOC_TEXT_BANKS

	; Check if at least 3 banks available from C down to floor D:
	; (C - D >= 3 guarantees 1 bank for Line 0, 1 bank for Line 1, >= 1 bank
	; for Text)
	LD A,C
	SUB D
	CP 3
	; Less than 3 banks: fallback to 16K mode!
	JR C,IFRB_ALLOC_TEXT_BANKS

	; Allocate 2nd line table bank:
	DEC C				; C = second Far RAM bank (e.g. 0x8C)
	LD A,C
	LD (LINE_TABLE_BANK_1),A	; Bank 1 for line slots (16384..32767)
	LD HL,MAX_DOC_LINES_32K
	LD (MAX_DOC_LINES_LIMIT),HL

IFRB_ALLOC_TEXT_BANKS:
	; 5. Populate EXT_BANK_TABLE allocating downward from C - 1
	; Stop when bank <= BIOS Bank ID (D, e.g. 0x80) to never overwrite HBIOS
	LD HL,EXT_BANK_TABLE
	LD B,0				; Counter for populated text slot banks

POPULATE_BANK_LOOP:
	DEC C				; Allocate downward: 0x8C, 0x8B...
	LD A,C
	CP D				; Compare with BIOS Bank ID (D)
	JR Z,POPULATE_BANK_DONE		; Stop if C == BIOS Bank ID!
	JR C,POPULATE_BANK_DONE		; Stop if C < BIOS Bank ID!

	LD (HL),C
	INC HL
	INC B
	LD A,B
	CP MAX_FAR_BANKS
	JR Z,POPULATE_BANK_DONE
	JR POPULATE_BANK_LOOP

POPULATE_BANK_DONE:
	LD A,B
	LD (EXT_BANK_COUNT),A
	RET

IFRB_NO_BANKS:
	XOR A
	LD (LINE_TABLE_BANK),A
	LD (LINE_TABLE_BANK_1),A
	LD (EXT_BANK_COUNT),A
	LD HL,MAX_DOC_LINES_16K
	LD (MAX_DOC_LINES_LIMIT),HL
	RET
	ENDIF

;==============================================================================
; Far RAM Line Table Subsystem (16,384 Lines in 32KB Far RAM Bank)
;==============================================================================

;------------------------------------------------------------------------------
; GET_LINE_SLOT: Retrieve 16-bit slot ID for document line BC from Far RAM
;
; Purpose:
;   Retrieves the 16-bit physical slot ID associated with document line BC
;   from the Far RAM Line Table. Handles bank selection (Bank 0 for lines
;   0..16383, Bank 1 for lines 16384..32767).
;
; Call Usage / Protocol:
;   Fundamental line table lookup called across line retrieval and editing.
;
; Inputs:
;   BC = 16-bit Document Line Index (0..MAX_DOC_LINES-1).
;
; Outputs:
;   HL = 16-bit physical slot ID.
;
; Preserves / Modifies:
;   Preserves BC, DE; returns value in HL; clobbers AF.
;------------------------------------------------------------------------------
GET_LINE_SLOT:
	PUSH BC
	PUSH DE

	; Determine Bank (Bank 0 if BC < 16384, Bank 1 if BC >= 16384)
	BIT 6,B
	JR NZ,GLS_BANK_1
	LD A,(LINE_TABLE_BANK)
	JR GLS_GOT_BANK
GLS_BANK_1:
	LD A,(LINE_TABLE_BANK_1)
GLS_GOT_BANK:
	LD E,A				; E = Line Table Bank (Src)

	; Calculate far byte offset = (BC & 0x3FFF) * 2
	LD L,C
	LD H,B
	RES 6,H				; Clear bit 14 so HL is 0..16383
	ADD HL,HL			; HL = far byte offset (0..32766)

	; SYSSETCPY: D = User Bank, E = Line Table Bank, HL = 2 bytes
	PUSH HL				; Save far offset
	PUSH DE				; Save E (Line Table Bank)
	PUSH IX
	LD B,0F4H			; SYSSETCPY
	LD A,(CPM_USER_BANK)
	LD D,A
	; E is already Line Table Bank!
	LD HL,2
	IFDEF TARGET_NEXT
	CALL NEXT_SYSSETCPY
	ELSE
	RST 08H
	ENDIF
	POP IX
	POP DE
	POP HL				; Restore far offset into HL

	; SYSBNKCPY: HL = Far Src Addr, DE = Local Dest Addr
	LD DE,LINE_SLOT_TEMP
	PUSH IX
	LD B,0F5H			; SYSBNKCPY
	IFDEF TARGET_NEXT
	CALL NEXT_SYSBNKCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	LD HL,(LINE_SLOT_TEMP)		; HL = 16-bit slot ID

	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; SET_LINE_SLOT: Store 16-bit slot ID for document line BC into Far RAM
;
; Purpose:
;   Stores 16-bit physical slot ID HL into the Far RAM Line Table at document
;   line index BC. Dispatches to Bank 0 or Bank 1 according to line index.
;
; Call Usage / Protocol:
;   Called when allocating, reassigning, or clearing line slots.
;
; Inputs:
;   BC = 16-bit Document Line Index; HL = 16-bit physical slot ID.
;
; Outputs:
;   Line table entry updated in Far RAM.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
SET_LINE_SLOT:
	PUSH BC
	PUSH DE
	PUSH HL				; Save slot ID

	LD (LINE_SLOT_TEMP),HL

	; Determine Bank (Bank 0 if BC < 16384, Bank 1 if BC >= 16384)
	BIT 6,B
	JR NZ,SLS_BANK_1
	LD A,(LINE_TABLE_BANK)
	JR SLS_GOT_BANK
SLS_BANK_1:
	LD A,(LINE_TABLE_BANK_1)
SLS_GOT_BANK:
	LD D,A				; D = Line Table Bank (Dest)

	; Calculate far byte offset = (BC & 0x3FFF) * 2
	LD L,C
	LD H,B
	RES 6,H
	ADD HL,HL			; HL = far byte offset (0..32766)

	; SYSSETCPY: D = Line Table Bank, E = User Bank, HL = 2 bytes
	PUSH HL				; Save far destination address
	PUSH DE				; Save D (Line Table Bank)
	PUSH IX
	LD B,0F4H			; SYSSETCPY
	; D is already Line Table Bank!
	LD A,(CPM_USER_BANK)
	LD E,A
	LD HL,2
	IFDEF TARGET_NEXT
	CALL NEXT_SYSSETCPY
	ELSE
	RST 08H
	ENDIF
	POP IX
	POP DE
	POP HL			; Restore far destination address into HL

	; SYSBNKCPY: HL = Local Src Addr, DE = Far Dest Addr
	EX DE,HL			; DE = Far Dest Addr
	LD HL,LINE_SLOT_TEMP		; HL = Local Src Addr
	PUSH IX
	LD B,0F5H			; SYSBNKCPY
	IFDEF TARGET_NEXT
	CALL NEXT_SYSBNKCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	POP HL				; Restore HL (slot ID)
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; SHIFT_LINE_SLOTS_UP: Shift W line slots upward from higher to lower lines
;
; Purpose:
;   Shifts W consecutive line slot entries upward from higher to lower line
;   indices (DE < HL), copying in 128-entry chunks across the 16K line boundary
;   between Far RAM Bank 0 and Bank 1.
;
; Call Usage / Protocol:
;   Called when deleting document lines or visual blocks.
;
; Inputs:
;   DE = Destination Line Index, HL = Source Line Index, BC = Word Count (W).
;
; Outputs:
;   Line table entries shifted.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
SHIFT_LINE_SLOTS_UP:
	LD A,B
	OR C
	RET Z

	PUSH BC
	PUSH DE
	PUSH HL

	LD (SLOT_SHIFT_REM),BC
	LD (SLOT_SHIFT_SRC),HL
	LD (SLOT_SHIFT_DEST),DE

SLOTS_UP_LOOP:
	LD HL,(SLOT_SHIFT_REM)
	LD A,H
	OR L
	JP Z,SLOTS_UP_DONE

	; Candidate chunk = min(128, rem)
	LD DE,128
	CALL CMP_HL_DE			; Carry=1 if HL < 128
	JR C,SLOTS_UP_USE_REM
	EX DE,HL			; HL = 128
SLOTS_UP_USE_REM:
	LD (SLOT_SHIFT_CHUNK),HL	; Save candidate chunk

	; Check distance to line 16384 boundary for Source
	LD DE,(SLOT_SHIFT_SRC)
	BIT 6,D				; Source >= 16384?
	JR NZ,SLOTS_UP_SRC_OK		; In Bank 1, no boundary ahead
	; Source < 16384: distance = 16384 - Source
	LD HL,16384
	OR A
	SBC HL,DE			; HL = distance
	EX DE,HL			; DE = distance
	LD HL,(SLOT_SHIFT_CHUNK)
	CALL CMP_HL_DE			; Carry=1 if chunk < distance
	JR C,SLOTS_UP_SRC_OK
	LD (SLOT_SHIFT_CHUNK),DE	; Clamp chunk to distance
SLOTS_UP_SRC_OK:

	; Check distance to line 16384 boundary for Dest
	LD DE,(SLOT_SHIFT_DEST)
	BIT 6,D				; Dest >= 16384?
	JR NZ,SLOTS_UP_DEST_OK		; In Bank 1, no boundary ahead
	; Dest < 16384: distance = 16384 - Dest
	LD HL,16384
	OR A
	SBC HL,DE			; HL = distance
	EX DE,HL			; DE = distance
	LD HL,(SLOT_SHIFT_CHUNK)
	CALL CMP_HL_DE			; Carry=1 if chunk < distance
	JR C,SLOTS_UP_DEST_OK
	LD (SLOT_SHIFT_CHUNK),DE	; Clamp chunk to distance
SLOTS_UP_DEST_OK:

	; Determine Source Bank & In-Bank Offset:
	LD BC,(SLOT_SHIFT_SRC)
	BIT 6,B
	JR NZ,SLOTS_UP_SRC_B1
	LD A,(LINE_TABLE_BANK)
	JR SLOTS_UP_GOT_SBANK
SLOTS_UP_SRC_B1:
	LD A,(LINE_TABLE_BANK_1)
SLOTS_UP_GOT_SBANK:
	LD (FAR_SRC_BANK),A

	LD L,C
	LD H,B
	RES 6,H
	ADD HL,HL
	LD (FAR_SRC_ADDR),HL

	; Determine Dest Bank & In-Bank Offset:
	LD BC,(SLOT_SHIFT_DEST)
	BIT 6,B
	JR NZ,SLOTS_UP_DST_B1
	LD A,(LINE_TABLE_BANK)
	JR SLOTS_UP_GOT_DBANK
SLOTS_UP_DST_B1:
	LD A,(LINE_TABLE_BANK_1)
SLOTS_UP_GOT_DBANK:
	LD (FAR_DEST_BANK),A

	LD L,C
	LD H,B
	RES 6,H
	ADD HL,HL
	LD (FAR_DEST_ADDR),HL

	; Calculate byte count = chunk * 2
	LD HL,(SLOT_SHIFT_CHUNK)
	ADD HL,HL
	LD (SLOT_SHIFT_BYTES),HL

	; 1. Copy chunk from Far RAM Source Bank to local LINE_SHIFT_BUF
	PUSH IX
	LD B,0F4H			; SYSSETCPY
	LD A,(CPM_USER_BANK)
	LD D,A				; Dest = User Bank
	LD A,(FAR_SRC_BANK)
	LD E,A				; Src = Line Table Source Bank
	LD HL,(SLOT_SHIFT_BYTES)
	IFDEF TARGET_NEXT
	CALL NEXT_SYSSETCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	PUSH IX
	LD B,0F5H			; SYSBNKCPY
	LD DE,LINE_SHIFT_BUF		; Local Dest
	LD HL,(FAR_SRC_ADDR)		; Far Src
	IFDEF TARGET_NEXT
	CALL NEXT_SYSBNKCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	; 2. Copy chunk from local LINE_SHIFT_BUF to Far RAM Dest Bank
	PUSH IX
	LD B,0F4H			; SYSSETCPY
	LD A,(FAR_DEST_BANK)
	LD D,A				; Dest = Line Table Dest Bank
	LD A,(CPM_USER_BANK)
	LD E,A				; Src = User Bank
	LD HL,(SLOT_SHIFT_BYTES)
	IFDEF TARGET_NEXT
	CALL NEXT_SYSSETCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	PUSH IX
	LD B,0F5H			; SYSBNKCPY
	LD DE,(FAR_DEST_ADDR)		; Far Dest
	LD HL,LINE_SHIFT_BUF		; Local Src
	IFDEF TARGET_NEXT
	CALL NEXT_SYSBNKCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	; Advance Source and Dest by CHUNK; Decrement Rem by CHUNK
	LD DE,(SLOT_SHIFT_CHUNK)
	LD HL,(SLOT_SHIFT_SRC)
	ADD HL,DE
	LD (SLOT_SHIFT_SRC),HL

	LD HL,(SLOT_SHIFT_DEST)
	ADD HL,DE
	LD (SLOT_SHIFT_DEST),HL

	LD HL,(SLOT_SHIFT_REM)
	OR A
	SBC HL,DE
	LD (SLOT_SHIFT_REM),HL

	JP SLOTS_UP_LOOP

SLOTS_UP_DONE:
	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; SHIFT_LINE_SLOTS_DOWN: Shift W line slots downward from lower to higher lines
;
; Purpose:
;   Shifts W consecutive line slot entries downward from lower to higher line
;   indices (DE > HL), copying backwards in 128-entry chunks across the 16K
;   line boundary between Bank 0 and Bank 1.
;
; Call Usage / Protocol:
;   Called when inserting lines or inserting blocks into document.
;
; Inputs:
;   DE = Destination Line Index, HL = Source Line Index, BC = Word Count (W).
;
; Outputs:
;   Line table entries shifted.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
SHIFT_LINE_SLOTS_DOWN:
	LD A,B
	OR C
	RET Z

	PUSH BC
	PUSH DE
	PUSH HL

	LD (SLOT_SHIFT_REM),BC

	; End Source line = HL + BC
	ADD HL,BC
	LD (SLOT_SHIFT_SRC),HL

	; End Dest line = DE + BC
	EX DE,HL
	ADD HL,BC
	LD (SLOT_SHIFT_DEST),HL

SLOTS_DOWN_LOOP:
	LD HL,(SLOT_SHIFT_REM)
	LD A,H
	OR L
	JP Z,SLOTS_DOWN_DONE

	; Candidate chunk = min(128, rem)
	LD DE,128
	CALL CMP_HL_DE			; Carry=1 if HL < 128
	JR C,SLOTS_DOWN_USE_REM
	EX DE,HL			; HL = 128
SLOTS_DOWN_USE_REM:
	LD (SLOT_SHIFT_CHUNK),HL	; Save candidate chunk

	; Check distance down to line 16384 boundary for Source end
	LD DE,(SLOT_SHIFT_SRC)
	LD HL,16384
	CALL CMP_HL_DE		; Carry=1 if 16384 < DE (src_end > 16384)
	JR NC,SLOTS_DOWN_SRC_OK
	; src_end > 16384: distance = src_end - 16384
	EX DE,HL			; HL = src_end, DE = 16384
	OR A
	SBC HL,DE			; HL = distance
	EX DE,HL			; DE = distance
	LD HL,(SLOT_SHIFT_CHUNK)
	CALL CMP_HL_DE			; Carry=1 if chunk < distance
	JR C,SLOTS_DOWN_SRC_OK
	LD (SLOT_SHIFT_CHUNK),DE	; Clamp chunk to distance
SLOTS_DOWN_SRC_OK:

	; Check distance down to line 16384 boundary for Dest end
	LD DE,(SLOT_SHIFT_DEST)
	LD HL,16384
	CALL CMP_HL_DE		; Carry=1 if 16384 < DE (dest_end > 16384)
	JR NC,SLOTS_DOWN_DEST_OK
	; dest_end > 16384: distance = dest_end - 16384
	EX DE,HL			; HL = dest_end, DE = 16384
	OR A
	SBC HL,DE			; HL = distance
	EX DE,HL			; DE = distance
	LD HL,(SLOT_SHIFT_CHUNK)
	CALL CMP_HL_DE			; Carry=1 if chunk < distance
	JR C,SLOTS_DOWN_DEST_OK
	LD (SLOT_SHIFT_CHUNK),DE	; Clamp chunk to distance
SLOTS_DOWN_DEST_OK:

	; Move Source and Dest back by CHUNK to get chunk start lines
	LD DE,(SLOT_SHIFT_CHUNK)
	LD HL,(SLOT_SHIFT_SRC)
	OR A
	SBC HL,DE
	LD (SLOT_SHIFT_SRC),HL		; Chunk source start line

	LD HL,(SLOT_SHIFT_DEST)
	OR A
	SBC HL,DE
	LD (SLOT_SHIFT_DEST),HL		; Chunk dest start line

	; Determine Source Bank & In-Bank Offset:
	LD BC,(SLOT_SHIFT_SRC)
	BIT 6,B
	JR NZ,SLOTS_DN_SRC_B1
	LD A,(LINE_TABLE_BANK)
	JR SLOTS_DN_GOT_SBANK
SLOTS_DN_SRC_B1:
	LD A,(LINE_TABLE_BANK_1)
SLOTS_DN_GOT_SBANK:
	LD (FAR_SRC_BANK),A

	LD L,C
	LD H,B
	RES 6,H
	ADD HL,HL
	LD (FAR_SRC_ADDR),HL

	; Determine Dest Bank & In-Bank Offset:
	LD BC,(SLOT_SHIFT_DEST)
	BIT 6,B
	JR NZ,SLOTS_DN_DST_B1
	LD A,(LINE_TABLE_BANK)
	JR SLOTS_DN_GOT_DBANK
SLOTS_DN_DST_B1:
	LD A,(LINE_TABLE_BANK_1)
SLOTS_DN_GOT_DBANK:
	LD (FAR_DEST_BANK),A

	LD L,C
	LD H,B
	RES 6,H
	ADD HL,HL
	LD (FAR_DEST_ADDR),HL

	; Calculate byte count = chunk * 2
	LD HL,(SLOT_SHIFT_CHUNK)
	ADD HL,HL
	LD (SLOT_SHIFT_BYTES),HL

	; 1. Copy chunk from Far RAM Source Bank to local LINE_SHIFT_BUF
	PUSH IX
	LD B,0F4H			; SYSSETCPY
	LD A,(CPM_USER_BANK)
	LD D,A				; Dest = User Bank
	LD A,(FAR_SRC_BANK)
	LD E,A				; Src = Line Table Source Bank
	LD HL,(SLOT_SHIFT_BYTES)
	IFDEF TARGET_NEXT
	CALL NEXT_SYSSETCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	PUSH IX
	LD B,0F5H			; SYSBNKCPY
	LD DE,LINE_SHIFT_BUF		; Local Dest
	LD HL,(FAR_SRC_ADDR)		; Far Src
	IFDEF TARGET_NEXT
	CALL NEXT_SYSBNKCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	; 2. Copy chunk from local LINE_SHIFT_BUF to Far RAM Dest Bank
	PUSH IX
	LD B,0F4H			; SYSSETCPY
	LD A,(FAR_DEST_BANK)
	LD D,A				; Dest = Line Table Dest Bank
	LD A,(CPM_USER_BANK)
	LD E,A				; Src = User Bank
	LD HL,(SLOT_SHIFT_BYTES)
	IFDEF TARGET_NEXT
	CALL NEXT_SYSSETCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	PUSH IX
	LD B,0F5H			; SYSBNKCPY
	LD DE,(FAR_DEST_ADDR)		; Far Dest
	LD HL,LINE_SHIFT_BUF		; Local Src
	IFDEF TARGET_NEXT
	CALL NEXT_SYSBNKCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	; Decrement REM by CHUNK
	LD DE,(SLOT_SHIFT_CHUNK)
	LD HL,(SLOT_SHIFT_REM)
	OR A
	SBC HL,DE
	LD (SLOT_SHIFT_REM),HL

	JP SLOTS_DOWN_LOOP

SLOTS_DOWN_DONE:
	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; WRITE_SLOTS_TO_ONE_BANK: Copy K slot values from local RAM to single bank
;
; Purpose:
;   Copies K 16-bit line slot values from local memory buffer HL to Far RAM
;   Line Table bank A starting at in-bank line index BC.
;
; Call Usage / Protocol:
;   Internal helper called by WRITE_LINE_SLOTS_FROM_RAM.
;
; Inputs:
;   A = Line Table Bank ID, BC = In-Bank Destination Line Index (0..16383),
;   HL = Source buffer in RAM, DE = Line count (K).
;
; Outputs:
;   K words copied to Far RAM Line Table bank.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
WRITE_SLOTS_TO_ONE_BANK:
	LD (FAR_DEST_BANK),A
	PUSH HL				; Save Source Buffer address

	; Far Dest Addr = BC * 2
	LD L,C
	LD H,B
	ADD HL,HL
	EX DE,HL		; DE = Far Dest Addr, HL = Line Count (K)

	; Byte count = K * 2
	ADD HL,HL			; HL = Byte Count

	; SYSSETCPY: D = Dest Bank, E = User Bank, HL = Byte Count
	PUSH DE				; Save Far Dest Addr
	PUSH IX
	LD B,0F4H			; SYSSETCPY
	LD A,(FAR_DEST_BANK)
	LD D,A
	LD A,(CPM_USER_BANK)
	LD E,A
	IFDEF TARGET_NEXT
	CALL NEXT_SYSSETCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	; SYSBNKCPY: HL = Local Src Addr, DE = Far Dest Addr
	POP DE				; DE = Far Dest Addr
	POP HL				; HL = Local Src Addr
	PUSH IX
	LD B,0F5H			; SYSBNKCPY
	IFDEF TARGET_NEXT
	CALL NEXT_SYSBNKCPY
	ELSE
	RST 08H
	ENDIF
	POP IX
	RET

;------------------------------------------------------------------------------
; WRITE_LINE_SLOTS_FROM_RAM: Copy K line slots from local RAM into Line Table
;
; Purpose:
;   Transfers a block of K 16-bit line slots from local RAM into the Far RAM
;   Line Table starting at destination line BC, splitting across Bank 0 and
;   Bank 1 boundaries if the range crosses line 16384.
;
; Call Usage / Protocol:
;   Called when pasting multi-line clipboard blocks.
;
; Inputs:
;   BC = Destination Line Index, HL = Source buffer in RAM, DE = Line count (K).
;
; Outputs:
;   Slots written to Far RAM Line Table.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
WRITE_LINE_SLOTS_FROM_RAM:
	LD A,D
	OR E
	RET Z

	LD (WLSR_SRC),HL
	LD (WLSR_K),DE
	LD (WLSR_DEST),BC

	; Check if destination line BC >= 16384
	BIT 6,B
	JR NZ,WLSR_BANK_1

	; Destination starts in Bank 0 (BC < 16384).
	; Does BC + DE > 16384?
	LD H,B
	LD L,C
	ADD HL,DE			; HL = End line (BC + DE)
	LD DE,16384
	OR A
	SBC HL,DE
	JR C,WLSR_BANK_0_ALL		; End line < 16384 -> all in Bank 0
	JR Z,WLSR_BANK_0_ALL		; End line == 16384 -> all in Bank 0

	; Straddles Bank 0 and Bank 1:
	; K1 = 16384 - BC
	LD HL,16384
	LD BC,(WLSR_DEST)
	OR A
	SBC HL,BC			; HL = K1
	PUSH HL				; Save K1

	; Write Part 1: K1 lines to Bank 0 at (WLSR_DEST)
	EX DE,HL			; DE = K1
	LD BC,(WLSR_DEST)
	LD HL,(WLSR_SRC)
	LD A,(LINE_TABLE_BANK)
	CALL WRITE_SLOTS_TO_ONE_BANK

	; K2 = WLSR_K - K1
	POP DE				; DE = K1
	LD HL,(WLSR_K)
	OR A
	SBC HL,DE			; HL = K2 = total K - K1
	EX DE,HL			; DE = K2, HL = K1

	; RAM buffer advanced by K1 * 2 bytes:
	ADD HL,HL			; HL = K1 * 2 bytes
	LD BC,(WLSR_SRC)
	ADD HL,BC			; HL = WLSR_SRC + K1 * 2

	; Write Part 2: K2 lines to Bank 1 starting at index 0
	LD BC,0				; In-bank line index = 0
	LD A,(LINE_TABLE_BANK_1)
	CALL WRITE_SLOTS_TO_ONE_BANK
	RET

WLSR_BANK_0_ALL:
	LD A,(LINE_TABLE_BANK)
	LD BC,(WLSR_DEST)
	LD HL,(WLSR_SRC)
	LD DE,(WLSR_K)
	CALL WRITE_SLOTS_TO_ONE_BANK
	RET

WLSR_BANK_1:
	; BC >= 16384: in-bank line index = BC - 16384 (clear bit 14)
	RES 6,B
	LD A,(LINE_TABLE_BANK_1)
	LD HL,(WLSR_SRC)
	LD DE,(WLSR_K)
	CALL WRITE_SLOTS_TO_ONE_BANK
	RET


INCLUDE "core/memory.asm"

;------------------------------------------------------------------------------
; CHECKOUT_ACTIVE_LINE: Ensure CUR_DOC_ROW is checked out in ACTIVE_LINE_BUF
;
; Purpose:
;   Checks out document line CUR_DOC_ROW into ACTIVE_LINE_BUF (up to 1022
;   bytes). If a different row was previously checked out and marked dirty,
;   commits it to Far RAM first.
;
; Call Usage / Protocol:
;   Called before in-line editing, typing, or line rendering.
;
; Inputs:
;   CUR_DOC_ROW.
;
; Outputs:
;   HL = ACTIVE_LINE_BUF, line loaded and ready for edits.
;
; Preserves / Modifies:
;   Preserves BC, DE; returns buffer pointer in HL.
;------------------------------------------------------------------------------
CHECKOUT_ACTIVE_LINE:
	PUSH BC
	PUSH DE

	; Check if CUR_DOC_ROW == ACTIVE_LINE_ROW
	LD HL,(CUR_DOC_ROW)
	LD DE,(ACTIVE_LINE_ROW)
	LD A,H
	CP D
	JR NZ,DO_CHECKOUT
	LD A,L
	CP E
	JR Z,CHECKOUT_ALREADY_DONE

DO_CHECKOUT:
	; Row changed! If previous line dirty, commit it first
	CALL COMMIT_ACTIVE_LINE

	; Set ACTIVE_LINE_ROW = CUR_DOC_ROW
	LD HL,(CUR_DOC_ROW)
	LD (ACTIVE_LINE_ROW),HL
	XOR A
	LD (ACTIVE_LINE_DIRTY),A

	; Read CUR_DOC_ROW into ACTIVE_LINE_BUF up to 1022 bytes
	LD BC,(CUR_DOC_ROW)
	LD DE,ACTIVE_LINE_BUF
	LD HL,MAX_ACTIVE_LINE_STRIDE-2
	CALL READ_FAR_LINE_MAX

CHECKOUT_ALREADY_DONE:
	LD HL,ACTIVE_LINE_BUF
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; COMMIT_ACTIVE_LINE: Write ACTIVE_LINE_BUF to Far RAM if dirty
;
; Purpose:
;   If ACTIVE_LINE_DIRTY is set, writes ACTIVE_LINE_BUF back to Far RAM line
;   chain for ACTIVE_LINE_ROW and synchronizes with local LINE_STORAGE cache
;   if row falls within cache window.
;
; Call Usage / Protocol:
;   Called before navigating away from active row, saving, or checking out.
;
; Inputs:
;   ACTIVE_LINE_ROW, ACTIVE_LINE_DIRTY, ACTIVE_LINE_BUF.
;
; Outputs:
;   Line committed to Far RAM; ACTIVE_LINE_DIRTY cleared to 0.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
COMMIT_ACTIVE_LINE:
	PUSH BC
	PUSH DE
	PUSH HL

	; Check if active line is valid
	LD HL,(ACTIVE_LINE_ROW)
	LD A,H
	AND L
	INC A
	JR Z,COMMIT_DONE		; 0xFFFF -> no line checked out

	; Check if active line is dirty
	LD A,(ACTIVE_LINE_DIRTY)
	OR A
	JR Z,COMMIT_DONE		; Not dirty -> nothing to write

	; Clear dirty flag
	XOR A
	LD (ACTIVE_LINE_DIRTY),A

	; Write ACTIVE_LINE_BUF to Far RAM for ACTIVE_LINE_ROW
	LD BC,(ACTIVE_LINE_ROW)
	LD HL,ACTIVE_LINE_BUF
	CALL WRITE_FAR_LINE

	; Synchronize first 254 chars to LINE_STORAGE if row is in cache window
	LD BC,(ACTIVE_LINE_ROW)
	LD HL,(CACHE_START_ROW)
	; Check BC >= CACHE_START_ROW
	LD A,B
	CP H
	JR C,COMMIT_DONE
	JR NZ,COMMIT_CHECK_UPPER
	LD A,C
	CP L
	JR C,COMMIT_DONE

COMMIT_CHECK_UPPER:
	LD A,C
	SUB L
	LD E,A
	LD A,B
	SBC A,H
	JR NZ,COMMIT_DONE		; High byte non-zero -> outside cache
	LD A,E
	CP CACHE_SIZE_LINES
	JR NC,COMMIT_DONE		; Index >= 48 -> outside cache

	; Row is in cache! Calculate destination pointer: LINE_STORAGE + (E *
	; 128)
	PUSH DE
	LD L,E
	LD H,0
	ADD HL,HL			; *2
	ADD HL,HL			; *4
	ADD HL,HL			; *8
	ADD HL,HL			; *16
	ADD HL,HL			; *32
	ADD HL,HL			; *64
	ADD HL,HL			; *128
	LD DE,LINE_STORAGE
	ADD HL,DE			; HL = target slot in LINE_STORAGE
	EX DE,HL			; DE = destination in LINE_STORAGE
	LD HL,ACTIVE_LINE_BUF		; HL = source
	LD B,MAX_LINE_STRIDE-2		; up to 126 bytes
COMMIT_SYNC_LOOP:
	LD A,(HL)
	OR A
	JR Z,COMMIT_SYNC_ZERO
	LD (DE),A
	INC HL
	INC DE
	DJNZ COMMIT_SYNC_LOOP
COMMIT_SYNC_ZERO:
	XOR A
	LD (DE),A			; Null terminate in cache
	POP DE				; E = local line index (0..47)

	; Mark this cache line clean (since already written to Far RAM)
	LD HL,CACHE_LINE_DIRTY
	LD D,0
	ADD HL,DE
	LD (HL),0

COMMIT_DONE:
	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; INVALIDATE_ACTIVE_LINE: Commit if dirty, then reset ACTIVE_LINE_ROW to 0xFFFF
;
; Purpose:
;   Commits active line buffer if dirty, then resets ACTIVE_LINE_ROW to
;   0xFFFF and clears ACTIVE_LINE_DIRTY flag.
;
; Call Usage / Protocol:
;   Called before modal dialogs, search/replace, and document close.
;
; Inputs:
;   None.
;
; Outputs:
;   Active line committed and invalidated (ACTIVE_LINE_ROW = 0xFFFF).
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
INVALIDATE_ACTIVE_LINE:
	CALL COMMIT_ACTIVE_LINE
	PUSH HL
	LD HL,0FFFFH
	LD (ACTIVE_LINE_ROW),HL
	XOR A
	LD (ACTIVE_LINE_DIRTY),A
	POP HL
	RET

;------------------------------------------------------------------------------
; INIT_SLOT_SYSTEM: Reset slot allocator and free list
;
; Purpose:
;   Resets slot allocation counters (NEXT_FRESH_SLOT = 0, FIRST_FREE_SLOT =
;   0xFFFF) and reinitializes virtual paging subsystem.
;
; Call Usage / Protocol:
;   Called via CALL from BUFFER_INIT and document resets.
;
; Inputs:
;   None.
;
; Outputs:
;   Slot allocator and free lists reset.
;
; Preserves / Modifies:
;   Preserves all registers: AF, BC, DE, HL.
;------------------------------------------------------------------------------
INIT_SLOT_SYSTEM:
	LD HL,0
	LD (NEXT_FRESH_SLOT),HL
	LD HL,0FFFFH
	LD (FIRST_FREE_SLOT),HL
	CALL INIT_PAGING_SYSTEM
	RET

;------------------------------------------------------------------------------
; WRITE_SLOT_NEXT_TERM: Write 0xFFFF termination to slot BC link header
;
; Purpose:
;   Writes 0xFFFF to the first 2 bytes (NEXT_SLOT_ID) of Far RAM slot BC,
;   terminating slot chain.
;
; Call Usage / Protocol:
;   Called when allocating fresh or recycled slots.
;
; Inputs:
;   BC = 16-bit Virtual Slot ID (0..65534).
;
; Outputs:
;   Slot termination link written to Far RAM.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
WRITE_SLOT_NEXT_TERM:
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL

	LD HL,0FFFFH
	LD (LINE_SLOT_TEMP),HL

	; Ensure Page B is resident and marked dirty
	LD A,B
	CALL ENSURE_PAGE_RESIDENT_DIRTY
	JR C,WSNT_ERR
	LD D,A				; D = Far RAM Bank ID
	LD A,(CPM_USER_BANK)
	LD E,A				; Src Bank = CPM_USER_BANK

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
	EX DE,HL		; DE = far_offset, H = Dest Bank, L = Src Bank

	; SYSSETCPY: D = Dest Bank, E = Src Bank, HL = 2 bytes
	PUSH DE
	PUSH IX
	LD B,0F4H			; SYSSETCPY
	LD D,H
	LD E,L
	LD HL,2
	IFDEF TARGET_NEXT
	CALL NEXT_SYSSETCPY
	ELSE
	RST 08H
	ENDIF
	POP IX

	; SYSBNKCPY: HL = Local Src (LINE_SLOT_TEMP), DE = Far Dest
	POP DE
	LD HL,LINE_SLOT_TEMP
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
	POP AF
	OR A				; Carry = 0
	RET

WSNT_ERR:
	POP HL
	POP DE
	POP BC
	POP AF
	SCF				; Carry = 1
	RET

;------------------------------------------------------------------------------
; ALLOC_SLOT: Allocate a Virtual Slot ID (0..65534)
;
; Purpose:
;   Allocates a 16-bit slot ID. Pops from recycled free list FIRST_FREE_SLOT
;   if available, otherwise allocates a fresh sequential slot from
;   NEXT_FRESH_SLOT.
;
; Call Usage / Protocol:
;   Called when adding new lines or extending long lines.
;
; Inputs:
;   None.
;
; Outputs:
;   Carry = 0, HL = 16-bit slot ID; Carry = 1 on out-of-memory.
;
; Preserves / Modifies:
;   Preserves BC, DE; returns slot ID in HL.
;------------------------------------------------------------------------------
ALLOC_SLOT:
	PUSH DE
	PUSH BC

	; Check if any recycled slot is available in FIRST_FREE_SLOT
	LD HL,(FIRST_FREE_SLOT)
	LD A,H
	AND L
	INC A				; If HL == 0xFFFF, A is 0 (Z set)
	JR Z,ALLOC_FRESH_SLOT

	; Pop slot from free list in Extended RAM
	; HL = slot ID to allocate
	PUSH HL				; Save slot ID
	LD B,H
	LD C,L				; BC = slot ID
	LD DE,FAR_IO_BUF
	; Read first 128 bytes of slot (contains next ptr)
	CALL READ_FAR_SLOT
	LD HL,(FAR_IO_BUF)		; HL = next free slot ID
	LD (FIRST_FREE_SLOT),HL
	POP HL				; Restore allocated slot ID
	LD B,H
	LD C,L
	; Ensure allocated slot has 0xFFFF next ptr
	CALL WRITE_SLOT_NEXT_TERM
	JR C,ALLOC_FAIL
	POP BC
	POP DE
	OR A				; Carry = 0 (success)
	RET

ALLOC_FRESH_SLOT:
	LD HL,(NEXT_FRESH_SLOT)
	; Check if Far RAM banks are constrained (< 2 banks)
	LD A,(EXT_BANK_COUNT)
	CP 2
	JR NC,AFS_MULTI_BANK
	; When EXT_BANK_COUNT < 2, slots are limited to Bank 0 (max 256 slots)
	LD D,A
	LD E,0
	JR AFS_CHECK_LIMIT
AFS_MULTI_BANK:
	LD DE,MAX_VIRTUAL_SLOTS
AFS_CHECK_LIMIT:
	LD A,H
	CP D
	JR C,ALLOC_FRESH_OK
	JR NZ,ALLOC_FAIL
	LD A,L
	CP E
	JR NC,ALLOC_FAIL

ALLOC_FRESH_OK:
	PUSH HL
	INC HL
	LD (NEXT_FRESH_SLOT),HL
	POP HL				; HL = allocated slot ID
	LD B,H
	LD C,L
	CALL WRITE_SLOT_NEXT_TERM	; Ensure fresh slot has 0xFFFF next ptr
	JR C,ALLOC_FAIL
	POP BC
	POP DE
	OR A				; Carry = 0 (success)
	RET

ALLOC_FAIL:
	POP BC
	POP DE
	SCF				; Carry = 1 (error: no free slots)
	RET

;------------------------------------------------------------------------------
; FREE_SLOT: Return a Far RAM slot ID to the Extended RAM free list
;
; Purpose:
;   Pushes Far RAM slot HL onto the recycled free list in Extended RAM,
;   updating FIRST_FREE_SLOT.
;
; Call Usage / Protocol:
;   Called when deleting or truncating line slots.
;
; Inputs:
;   HL = 16-bit Physical Slot ID (0..3583).
;
; Outputs:
;   Slot returned to free list.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
FREE_SLOT:
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL

	LD DE,(FIRST_FREE_SLOT)
	; Check if slot is already at top of free list (prevent self-loop)
	LD A,D
	CP H
	JR NZ,FS_PROCEED
	LD A,E
	CP L
	JR Z,FS_DONE

FS_PROCEED:
	LD (FAR_IO_BUF),DE

	; Write to Far RAM slot HL
	LD B,H
	LD C,L				; BC = slot ID
	LD HL,FAR_IO_BUF
	CALL WRITE_FAR_SLOT

	; Update FIRST_FREE_SLOT to the newly freed slot ID
	POP HL
	PUSH HL
	LD (FIRST_FREE_SLOT),HL

FS_DONE:
	POP HL
	POP DE
	POP BC
	POP AF
	RET

;------------------------------------------------------------------------------
; FREE_LINE_CHAIN: Return a Far RAM slot chain to the Extended RAM free list
;
; Purpose:
;   Traverses and frees an entire chain of linked Far RAM slots starting
;   at head slot HL, returning all slots to the free list.
;
; Call Usage / Protocol:
;   Called when deleting lines or overwriting lines with shorter content.
;
; Inputs:
;   HL = 16-bit Head Slot ID (0..3583).
;
; Outputs:
;   All slots in chain returned to free list.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; clobbers AF.
;------------------------------------------------------------------------------
FREE_LINE_CHAIN:
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL
	LD A,16
	LD (FLC_COUNT),A

FLC_LOOP:
	; Check if HL == 0xFFFF (SLOT_TERM)
	LD A,H
	AND L
	INC A
	JR Z,FLC_DONE

	; Check if HL is within bounds
	LD DE,MAX_VIRTUAL_SLOTS
	LD A,H
	CP D
	JR C,FLC_BOUNDS_OK
	JR NZ,FLC_DONE
	LD A,L
	CP E
	JR NC,FLC_DONE
FLC_BOUNDS_OK:

	; Check iteration count
	LD A,(FLC_COUNT)
	DEC A
	LD (FLC_COUNT),A
	JR Z,FLC_DONE

	; Read slot into FAR_IO_BUF to get NEXT_SLOT_ID
	PUSH HL				; Save slot ID being freed
	LD B,H
	LD C,L
	LD DE,FAR_IO_BUF
	CALL READ_FAR_SLOT
	LD DE,(FAR_IO_BUF)		; DE = NEXT_SLOT_ID
	POP HL				; Restore slot ID being freed

	; Check for self-loop (DE == HL)
	LD A,D
	CP H
	JR NZ,FLC_NOT_SELF
	LD A,E
	CP L
	JR Z,FLC_DONE
FLC_NOT_SELF:

	; Free slot HL
	CALL FREE_SLOT

	; Advance to NEXT_SLOT_ID
	EX DE,HL			; HL = NEXT_SLOT_ID
	JR FLC_LOOP

FLC_DONE:
	POP HL
	POP DE
	POP BC
	POP AF
	RET

;------------------------------------------------------------------------------
; APPEND_LINE_SLOT: Allocate slot and assign to line table in Far RAM
;
; Purpose:
;   Allocates a fresh slot and assigns it to the Far RAM Line Table at the
;   end of the document (DOC_TOTAL_LINES).
;
; Call Usage / Protocol:
;   Called when loading files or appending new blank lines.
;
; Inputs:
;   DOC_TOTAL_LINES, MAX_DOC_LINES_LIMIT.
;
; Outputs:
;   Carry = 0, BC = allocated slot ID; Carry = 1 on out-of-memory.
;
; Preserves / Modifies:
;   Preserves DE; returns slot ID in BC.
;------------------------------------------------------------------------------
APPEND_LINE_SLOT:
	PUSH DE
	LD HL,(DOC_TOTAL_LINES)
	LD DE,(MAX_DOC_LINES_LIMIT)
	OR A
	SBC HL,DE
	POP DE
	JR NC,ALS_OOM
	CALL ALLOC_SLOT			; HL = slot ID
	RET C
	PUSH HL				; Save slot ID
	LD BC,(DOC_TOTAL_LINES)
	CALL SET_LINE_SLOT		; Store slot ID HL at line BC in Far RAM
	POP BC				; BC = allocated slot ID
	OR A				; Carry = 0
	RET
ALS_OOM:
	SCF
	RET

;------------------------------------------------------------------------------
; CLEAR_CACHE_DIRTY_FLAGS: Reset all line cache dirty flags to clean (0)
;
; Purpose:
;   Clears all CACHE_SIZE_LINES (48) entries in CACHE_LINE_DIRTY table to 0,
;   indicating no cached lines contain uncommitted edits.
;
; Call Usage / Protocol:
;   Called via CALL on document initialization, close, or cache reset.
;
; Inputs:
;   None.
;
; Outputs:
;   CACHE_LINE_DIRTY table zeroed.
;
; Preserves / Modifies:
;   Preserves all registers: AF, BC, DE, HL.
;------------------------------------------------------------------------------
CLEAR_CACHE_DIRTY_FLAGS:
	PUSH AF
	PUSH BC
	PUSH HL
	XOR A
	LD (CACHE_DIRTY),A
	LD HL,CACHE_LINE_DIRTY
	LD B,CACHE_SIZE_LINES
CCDF_LOOP:
	LD (HL),0
	INC HL
	DJNZ CCDF_LOOP
	POP HL
	POP BC
	POP AF
	RET

;------------------------------------------------------------------------------
; MARK_LINE_BC_DIRTY: Mark document line BC dirty in local line cache
;
; Purpose:
;   Tests if document line BC falls within currently resident cache window
;   [CACHE_START_ROW .. CACHE_START_ROW + CACHE_SIZE_LINES - 1]. If resident,
;   sets corresponding dirty flag in CACHE_LINE_DIRTY.
;
; Call Usage / Protocol:
;   Called via CALL after modifying text in a line.
;
; Inputs:
;   BC = 16-bit Document Line Index (0..3583).
;
; Outputs:
;   CACHE_LINE_DIRTY entry set to 1 if line is in cache.
;
; Preserves / Modifies:
;   Preserves all registers: AF, BC, DE, HL.
;------------------------------------------------------------------------------
MARK_LINE_BC_DIRTY:
	PUSH AF
	PUSH DE
	PUSH HL
	LD A,1
	LD (CACHE_DIRTY),A
	LD (DOC_MODIFIED),A
	; Calculate local index = BC - CACHE_START_ROW
	LD L,C
	LD H,B
	LD DE,(CACHE_START_ROW)
	AND A
	SBC HL,DE
	LD A,H
	OR A
	JR NZ,MLBD_DONE		; If high byte != 0, outside cache window
	LD A,L
	CP CACHE_SIZE_LINES
	JR NC,MLBD_DONE		; If index >= CACHE_SIZE_LINES, outside cache
	LD DE,CACHE_LINE_DIRTY
	ADD HL,DE
	LD (HL),1
MLBD_DONE:
	POP HL
	POP DE
	POP AF
	RET

;------------------------------------------------------------------------------
; MARK_CURRENT_LINE_DIRTY: Mark active document row dirty in cache
;
; Purpose:
;   Loads CUR_DOC_ROW into BC and invokes MARK_LINE_BC_DIRTY to flag the
;   current line as modified.
;
; Call Usage / Protocol:
;   Called via CALL during character insertions, deletions, and replacements.
;
; Inputs:
;   CUR_DOC_ROW.
;
; Outputs:
;   Current line flagged dirty in cache.
;
; Preserves / Modifies:
;   Preserves all registers: AF, BC, DE, HL.
;------------------------------------------------------------------------------
MARK_CURRENT_LINE_DIRTY:
	PUSH BC
	LD BC,(CUR_DOC_ROW)
	CALL MARK_LINE_BC_DIRTY
	POP BC
	RET

;------------------------------------------------------------------------------
; FLUSH_DIRTY_CACHE: Write modified lines in local cache back to Far RAM banks
;
; Purpose:
;   Scans all 48 cache slots. For each slot marked dirty in CACHE_LINE_DIRTY,
;   writes the text line back to its Far RAM slot chain via WRITE_FAR_LINE
;   and clears the dirty flag.
;
; Call Usage / Protocol:
;   Called via CALL before cache window shifts, saving, or modal transitions.
;
; Inputs:
;   CACHE_START_ROW, CACHE_LINE_DIRTY, LINE_STORAGE.
;
; Outputs:
;   Dirty cache lines written to Far RAM; all dirty flags cleared.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
FLUSH_DIRTY_CACHE:
	CALL COMMIT_ACTIVE_LINE
	LD A,(CACHE_DIRTY)
	OR A
	RET Z				; Cache is clean, nothing to flush

	PUSH BC
	PUSH DE
	PUSH HL

	XOR A
	LD (CACHE_DIRTY),A		; Clear dirty flag before flush

	LD C,0		; Local cache line counter (0..CACHE_SIZE_LINES-1)
FLUSH_CACHE_LOOP:
	LD A,C
	CP CACHE_SIZE_LINES
	JR NC,FLUSH_CACHE_DONE

	; Check if this local line is dirty
	LD HL,CACHE_LINE_DIRTY
	LD E,C
	LD D,0
	ADD HL,DE
	LD A,(HL)
	OR A
	JR Z,FLUSH_SKIP_LINE

	; Clear dirty flag for this line
	LD (HL),0

	; Calculate doc_line = CACHE_START_ROW + C
	LD HL,(CACHE_START_ROW)
	LD E,C
	LD D,0
	ADD HL,DE			; HL = doc_line
	LD B,H
	LD C,L				; BC = doc_line

	; Check if doc_line < DOC_TOTAL_LINES
	LD HL,(DOC_TOTAL_LINES)
	LD A,H
	CP B
	JR C,FLUSH_CACHE_DONE
	JR NZ,DO_FLUSH_LINE
	LD A,L
	CP C
	JR Z,FLUSH_CACHE_DONE
	JR C,FLUSH_CACHE_DONE

DO_FLUSH_LINE:
	; Calculate local source pointer: LINE_STORAGE + (C_local * 128)
	LD A,E				; E was local C index
	LD (SLOT_TEMP),A
	LD L,A
	LD H,0
	ADD HL,HL			; *2
	ADD HL,HL			; *4
	ADD HL,HL			; *8
	ADD HL,HL			; *16
	ADD HL,HL			; *32
	ADD HL,HL			; *64
	ADD HL,HL			; *128
	LD DE,LINE_STORAGE
	ADD HL,DE			; HL = Local source line pointer

	CALL WRITE_FAR_LINE
	LD A,(SLOT_TEMP)		; Restore local index
	LD C,A

FLUSH_SKIP_LINE:
	INC C
	JR FLUSH_CACHE_LOOP

FLUSH_CACHE_DONE:
	CALL CLEAR_CACHE_DIRTY_FLAGS

	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; ENSURE_CACHE_WINDOW: Ensure document line BC is resident in local LINE_STORAGE
;
; Purpose:
;   Tests if document line BC is within active cache window. If resident,
;   computes and returns pointer to line start in LINE_STORAGE. If outside,
;   flushes dirty cache lines and loads a new window of lines starting from BC.
;
; Call Usage / Protocol:
;   Called via CALL whenever accessing line text from cache.
;
; Inputs:
;   BC = 16-bit Document Line Index (0..3583).
;
; Outputs:
;   HL = Pointer to line start in LINE_STORAGE.
;
; Preserves / Modifies:
;   Preserves BC, DE; returns line pointer in HL; clobbers AF.
;------------------------------------------------------------------------------
ENSURE_CACHE_WINDOW:
	PUSH BC
	PUSH DE

	; Check if BC >= (CACHE_START_ROW) AND BC < (CACHE_START_ROW) +
	; CACHE_SIZE_LINES
	LD HL,(CACHE_START_ROW)
	; Check BC >= CACHE_START_ROW
	LD A,B
	CP H
	JR C,RELOAD_CACHE_WINDOW
	JR NZ,CHECK_UPPER_BOUND
	LD A,C
	CP L
	JR C,RELOAD_CACHE_WINDOW

CHECK_UPPER_BOUND:
	; Calculate offset = BC - CACHE_START_ROW
	LD A,C
	SUB L
	LD E,A
	LD A,B
	SBC A,H
	JR NZ,RELOAD_CACHE_WINDOW	; High byte must be 0
	LD A,E
	CP CACHE_SIZE_LINES
	JR NC,RELOAD_CACHE_WINDOW	; Outside cache range

	; Inside cache! Offset is in E (0..CACHE_SIZE_LINES-1)
	JR CALC_CACHE_LINE_PTR

RELOAD_CACHE_WINDOW:
	; Flush old dirty cache if modified
	CALL FLUSH_DIRTY_CACHE

	; Calculate new CACHE_START_ROW = max(0, BC - (CACHE_SIZE_LINES / 2))
	LD HL,CACHE_SIZE_LINES / 2
	LD A,C
	SUB L
	LD E,A
	LD A,B
	SBC A,H
	JR C,SET_START_ZERO
	LD D,A
	LD (CACHE_START_ROW),DE
	JR LOAD_CACHE_LINES

SET_START_ZERO:
	LD DE,0
	LD (CACHE_START_ROW),DE

LOAD_CACHE_LINES:
	; Load CACHE_SIZE_LINES from Far RAM into LINE_STORAGE
	LD C,0				; Local cache slot 0..CACHE_SIZE_LINES-1
LOAD_SLOT_LOOP:
	LD A,C
	CP CACHE_SIZE_LINES
	JR NC,LOAD_CACHE_DONE

	; Calculate doc_line = CACHE_START_ROW + C
	LD HL,(CACHE_START_ROW)
	LD E,C
	LD D,0
	ADD HL,DE			; HL = target doc_line
	LD B,H
	LD A,L
	LD L,C				; Save local slot in L
	LD C,A				; BC = target doc_line

	; Calculate local destination address: LINE_STORAGE + (local_slot * 128)
	LD A,L
	LD (SLOT_TEMP),A
	LD H,0
	ADD HL,HL			; *2
	ADD HL,HL			; *4
	ADD HL,HL			; *8
	ADD HL,HL			; *16
	ADD HL,HL			; *32
	ADD HL,HL			; *64
	ADD HL,HL			; *128
	LD DE,LINE_STORAGE
	ADD HL,DE
	LD D,H
	LD E,L				; DE = Local destination address

	; Check if doc_line < DOC_TOTAL_LINES
	LD HL,(DOC_TOTAL_LINES)
	LD A,H
	CP B
	JR C,FILL_EMPTY_SLOT
	JR NZ,DO_FETCH_SLOT
	LD A,L
	CP C
	JR Z,FILL_EMPTY_SLOT
	JR C,FILL_EMPTY_SLOT

DO_FETCH_SLOT:
	CALL READ_FAR_LINE
	JR NEXT_SLOT

FILL_EMPTY_SLOT:
	; Zero fill empty slot
	EX DE,HL			; HL = line start
	LD (HL),0

NEXT_SLOT:
	LD A,(SLOT_TEMP)
	LD C,A
	INC C
	JR LOAD_SLOT_LOOP

LOAD_CACHE_DONE:
	CALL CLEAR_CACHE_DIRTY_FLAGS

	; Calculate offset for requested line: (BC_orig - CACHE_START_ROW)
	POP DE
	POP BC
	PUSH BC
	PUSH DE

	LD HL,(CACHE_START_ROW)
	LD A,C
	SUB L
	LD E,A			; E = local line index (0..CACHE_SIZE_LINES-1)

CALC_CACHE_LINE_PTR:
	LD L,E
	LD H,0
	ADD HL,HL			; *2
	ADD HL,HL			; *4
	ADD HL,HL			; *8
	ADD HL,HL			; *16
	ADD HL,HL			; *32
	ADD HL,HL			; *64
	ADD HL,HL			; *128
	LD DE,LINE_STORAGE
	ADD HL,DE		; HL = pointer to line start in LINE_STORAGE

	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; RELOAD_CACHE_WINDOW_FORCE: Invalidate and immediately reload local line cache
;
; Purpose:
;   Sets CACHE_START_ROW to 0xFFFF and loads a fresh cache window starting
;   from TOP_DOC_ROW.
;
; Call Usage / Protocol:
;   Called via CALL after external mutations, block operations, or file loads.
;
; Inputs:
;   TOP_DOC_ROW.
;
; Outputs:
;   Line cache window refreshed from Far RAM.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
RELOAD_CACHE_WINDOW_FORCE:
	PUSH HL
	PUSH BC
	LD HL,0FFFFH
	LD (CACHE_START_ROW),HL
	LD BC,(CUR_DOC_ROW)
	CALL ENSURE_CACHE_WINDOW
	POP BC
	POP HL
	RET

