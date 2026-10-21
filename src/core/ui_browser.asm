;==============================================================================
; UI_BROWSER.ASM: Core Subsystem - File Selection UI & Directory Browser
;
; Purpose:
;   Implements interactive Open File (Ctrl+O) and Save File (Ctrl+W) screens,
;   directory collection, sorting, paging, user area switching, filename input
;   editing, file loading/saving, and RAM drive overlay helpers.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;==============================================================================
; RAM Drive Helper Routines
;==============================================================================

;------------------------------------------------------------------------------
; SET_RAMDRIVE_CHAR: Configure RAM drive letter and update splash screen
;
; Purpose:
;   Stores the configured RAM drive letter ('A'..'P') into RAMDRIVE_DRIVE_CHAR
;   and updates the corresponding placeholder character in the splash screen
;   string (STR_SPLASH_RAM_LTR).
;
; Call Usage / Protocol:
;   Called via CALL from RAM drive detection and configuration parsers.
;
; Inputs:
;   A = Drive character ('A'..'P').
;
; Outputs:
;   RAMDRIVE_DRIVE_CHAR and STR_SPLASH_RAM_LTR updated.
;
; Preserves / Modifies:
;   Preserves all registers (BC, DE, HL, AF).
;------------------------------------------------------------------------------
SET_RAMDRIVE_CHAR:
	LD (RAMDRIVE_DRIVE_CHAR),A
	LD (STR_SPLASH_RAM_LTR),A
	RET

;------------------------------------------------------------------------------
; CHECK_TARGET_DRIVE_UNAVAILABLE: Verify target drive accessibility
;
; Purpose:
;   Examines the target drive index or FCB drive byte. If the target drive
;   matches the configured RAM drive but RAM drive support is unavailable,
;   sets Carry flag to prevent invalid I/O.
;
; Call Usage / Protocol:
;   Called via CALL from file open, save, insert, and directory routines.
;
; Inputs:
;   A = CP/M drive byte (0 = default/current, 1 = A:, 2 = B:, etc.).
;
; Outputs:
;   Carry = 0 if target drive is accessible; Carry = 1 if unavailable RAM drive.
;
; Preserves / Modifies:
;   Clobbers AF; preserves BC, DE, HL.
;------------------------------------------------------------------------------
CHECK_TARGET_DRIVE_UNAVAILABLE:
	PUSH BC
	PUSH AF
	OR A
	JR NZ,CTDU_HAVE_DRV
	LD A,(CURRENT_DIR_DRIVE)
	OR A
	JR NZ,CTDU_HAVE_DRV
	LD A,(CURRENT_DEFAULT_DRIVE)
	INC A

CTDU_HAVE_DRV:
	DEC A				; A = 0-based drive (0=A..15=P)
	LD B,A
	LD A,(RAMDRIVE_DRIVE_NUM)
	CP 0FFH
	JR Z,CTDU_SAFE			; No RAM drive detected -> safe
	CP B
	JR NZ,CTDU_SAFE			; Target is not the RAM drive -> safe

	; Target matches RAM drive. Check if hibernated or overwritten:
	LD A,(RAMDRIVE_IS_HIBERNATED)
	OR A
	JR NZ,CTDU_UNAVAIL
	LD A,(CFG_RAMDRIVE_FLAG)
	CP RAMDRV_MODE_ENABLED
	JR NZ,CTDU_SAFE

CTDU_UNAVAIL:
	POP AF
	POP BC
	SCF				; Carry = 1 (unavailable!)
	RET

CTDU_SAFE:
	POP AF
	POP BC
	OR A				; Carry = 0 (safe)
	RET

;------------------------------------------------------------------------------
; CHECK_FCB_IS_HIBERNATED: Test if target file is a hibernated session file
;
; Purpose:
;   Compares the filename in target FCB against the predefined hibernation file
;   name (SEHIBERN.$$$, etc.) to detect whether opening it requires resume.
;
; Call Usage / Protocol:
;   Called via CALL from file load and open dispatchers.
;
; Inputs:
;   HL = Pointer to target FCB.
;
; Outputs:
;   Zero flag (Z) set if file matches hibernate filename; NZ otherwise.
;
; Preserves / Modifies:
;   Clobbers AF; preserves BC, DE, HL.
;------------------------------------------------------------------------------
CHECK_FCB_IS_HIBERNATED:
	LD A,(WORK_FCB)
	OR A
	JR NZ,CFIH_HAVE_DRV
	LD A,(CURRENT_DEFAULT_DRIVE)
	INC A
CFIH_HAVE_DRV:
	JP CHECK_TARGET_DRIVE_UNAVAILABLE


;------------------------------------------------------------------------------
; RESTORE_RAMDRIVE: Restore CP/M default drive and user area after RAM drive I/O
;
; Purpose:
;   Restores the default logged-in CP/M drive and active user area back to the
;   saved working context after temporary operations on the RAM drive.
;
; Call Usage / Protocol:
;   Called via CALL following RAM drive overlay load or directory query.
;
; Inputs:
;   None.
;
; Outputs:
;   Default drive and user area restored via BDOS.
;
; Preserves / Modifies:
;   Clobbers AF; preserves BC, DE, HL.
;------------------------------------------------------------------------------
RESTORE_RAMDRIVE:
	LD A,(RAMDRIVE_IS_HIBERNATED)
	OR A
	RET Z				; Not hibernated -> nothing to do

	CALL LOAD_HIBERN_OVERLAY
	RET C				; Failed to load overlay

	CALL LINE_STORAGE + 256 + 6	; Action 2: Restore
	XOR A
	LD (RAMDRIVE_IS_HIBERNATED),A
	RET


STR_HIBERN_OVL_NAME:
	DB "HIBERN  OVL"
STR_HELP_OVL_NAME:
	IFDEF TARGET_NEXT_CPM
	DB "HELPNEXTOVL"
	ELSE
	DB "HELP    OVL"
	ENDIF

;------------------------------------------------------------------------------
; INIT_OVERLAY_FCB: Initialize OVERLAY_FCB with overlay file name
;
; Purpose:
;   Copies an 11-byte 8.3 filename string into OVERLAY_FCB, sets the drive code
;   to default (0), and clears extent and record count fields.
;
; Call Usage / Protocol:
;   Called via CALL before calling LOAD_OVERLAY_FILE.
;
; Inputs:
;   HL = Pointer to 11-byte filename string ("SEHIBERNOVL", etc.).
;
; Outputs:
;   OVERLAY_FCB prepared for BDOS file open.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
INIT_OVERLAY_FCB:
	PUSH DE
	LD HL,SHARED_TEMP_FCB
	LD (HL),A			; Drive byte (0 = default, 1 = A...)
	INC HL
	LD B,11
IOF_COPY:
	LD A,(DE)
	LD (HL),A
	INC HL
	INC DE
	DJNZ IOF_COPY
	LD B,24
IOF_ZERO:
	LD (HL),0
	INC HL
	DJNZ IOF_ZERO
	POP DE
	RET

;------------------------------------------------------------------------------
; LOAD_OVERLAY_FILE: Load overlay file from disk/RAM drive into TPA buffer
;
; Purpose:
;   Opens the file specified in OVERLAY_FCB and sequentially reads 128-byte
;   records into the memory buffer pointed to by HL until EOF is reached.
;
; Call Usage / Protocol:
;   Called via CALL from LOAD_HIBERN_OVERLAY and LOAD_HELP_OVERLAY.
;
; Inputs:
;   HL = Target memory destination address for overlay payload.
;   OVERLAY_FCB = Initialized with target overlay filename.
;
; Outputs:
;   Carry = 0 on successful load; Carry = 1 on open or read error.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
LOAD_OVERLAY_FILE:
	PUSH DE
	XOR A
	CALL INIT_OVERLAY_FCB
	POP DE
	PUSH DE
	LD DE,SHARED_TEMP_FCB
	LD C,15				; BDOS Open File
	CALL BDOS_ENTRY
	POP DE
	CP 0FFH
	JR NZ,LOF_OPEN_OK

	; Try program drive if known
	LD A,(CONFIG_SOURCE_DRIVE)
	CP 0FFH
	JP Z,LOF_ERR
	INC A				; 1-based drive
	PUSH DE
	CALL INIT_OVERLAY_FCB
	POP DE
	LD DE,SHARED_TEMP_FCB
	LD C,15				; BDOS Open File
	CALL BDOS_ENTRY
	CP 0FFH
	JP Z,LOF_ERR

LOF_OPEN_OK:
	; Clear record byte (cr)
	XOR A
	LD (SHARED_TEMP_FCB + 32),A

	; Read up to 32 records (4096 bytes) into LINE_STORAGE
	LD HL,LINE_STORAGE
	LD B,32

LOF_READ_LOOP:
	PUSH BC
	PUSH HL
	EX DE,HL			; DE = current buffer ptr
	LD C,26				; BDOS Set DMA
	CALL BDOS_ENTRY
	LD DE,SHARED_TEMP_FCB
	LD C,20				; BDOS Read Next Record
	CALL BDOS_ENTRY
	POP HL
	POP BC
	OR A
	JR NZ,LOF_READ_EOF		; EOF or read error
	LD DE,128
	ADD HL,DE
	DJNZ LOF_READ_LOOP

LOF_READ_EOF:
	; Close overlay file
	LD DE,SHARED_TEMP_FCB
	LD C,16				; BDOS Close File
	CALL BDOS_ENTRY

	; Restore default DMA
	LD DE,DEFAULT_DMA
	LD C,26				; BDOS Set DMA
	CALL BDOS_ENTRY

	; Check if relocation needed (LOAD_ADDR == 0 at offset 7)
	LD HL,(LINE_STORAGE + 7)
	LD A,H
	OR L
	JR NZ,LOF_DONE

	; Relocate PRL in LINE_STORAGE
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

LOF_DONE:
	OR A				; Carry = 0 (success)
	RET

LOF_ERR:
	SCF				; Carry = 1 (error)
	RET

;------------------------------------------------------------------------------
; LOAD_HIBERN_OVERLAY: Load hibernation overlay (SEHIBERN.OVL) into TPA memory
;
; Purpose:
;   Initializes OVERLAY_FCB with STR_HIBERN_OVL_NAME and loads the overlay code
;   into OVERLAY_EXEC_ADDR for session suspend or resume execution.
;
; Call Usage / Protocol:
;   Called via CALL from hibernation command handler or startup recovery.
;
; Inputs:
;   None.
;
; Outputs:
;   Carry = 0 if loaded successfully; Carry = 1 on failure.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
LOAD_HIBERN_OVERLAY:
	LD DE,STR_HIBERN_OVL_NAME
	JP LOAD_OVERLAY_FILE

;------------------------------------------------------------------------------
; LOAD_HELP_OVERLAY: Load interactive help overlay (SEHELP.OVL) into TPA memory
;
; Purpose:
;   Initializes OVERLAY_FCB with STR_HELP_OVL_NAME and loads help overlay into
;   OVERLAY_EXEC_ADDR to display interactive help screens.
;
; Call Usage / Protocol:
;   Called via CALL when user requests Help (F1 or Ctrl+Q H).
;
; Inputs:
;   None.
;
; Outputs:
;   Carry = 0 if loaded successfully; Carry = 1 on failure.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
LOAD_HELP_OVERLAY:
	LD DE,STR_HELP_OVL_NAME
	JP LOAD_OVERLAY_FILE

;------------------------------------------------------------------------------
; RUN_HIBERN_STARTUP: Probe and resume hibernated editor session on startup
;
; Purpose:
;   Checks if a valid hibernation state file exists on the default or RAM
;   drive. If found, prompts user or automatically loads SEHIBERN.OVL to
;   restore editor memory, open files, cursor position, and far RAM banks.
;
; Call Usage / Protocol:
;   Called via CALL from START during initial program boot.
;
; Inputs:
;   None.
;
; Outputs:
;   If session restored, jumps directly to main editor loop; otherwise returns.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
RUN_HIBERN_STARTUP:
	PUSH AF
	PUSH BC
	CALL LOAD_HIBERN_OVERLAY
	JR C,RHS_LOAD_ERR

	POP BC
	POP AF
	OR A
	JR NZ,RHS_ACTION_HIB

	; Action 0: Detect only
	CALL LINE_STORAGE + 256 + 0
	JR C,RHS_LOAD_ERR
	LD A,B
	LD (RAMDRIVE_DRIVE_NUM),A
	LD A,C
	CALL SET_RAMDRIVE_CHAR
	RET

RHS_ACTION_HIB:
	; Action 1: Detect, Validate & Hibernate
	LD A,(CURRENT_DEFAULT_DRIVE)
	LD DE,WORK_FCB
	LD HL,HAS_FILE_ARG
	LD C,(HL)
	; B already contains requested mode
	CALL LINE_STORAGE + 256 + 3
	LD (RAMDRIVE_IS_HIBERNATED),A
	LD A,D
	LD (CFG_RAMDRIVE_FLAG),A
	LD A,B
	LD (RAMDRIVE_DRIVE_NUM),A
	LD A,C
	CALL SET_RAMDRIVE_CHAR
	RET

RHS_LOAD_ERR:
	POP BC
	POP AF
	LD A,0FFH
	LD (RAMDRIVE_DRIVE_NUM),A
	LD A,'?'
	CALL SET_RAMDRIVE_CHAR
	XOR A
	LD (CFG_RAMDRIVE_FLAG),A
	LD (RAMDRIVE_IS_HIBERNATED),A
	RET

;------------------------------------------------------------------------------
; LOAD_FILE: Read text file from disk into far RAM line storage subsystem
;
; Purpose:
;   Opens file in WORK_FCB, sets up progress modal, sequentially reads 128-byte
;   sectors via BDOS Read Sequential, parses CRLF/LF/CR line breaks, handles tab
;   expansion, stores lines into far RAM banks, and builds line pointer table.
;
; Call Usage / Protocol:
;   Called via CALL from START (CLI filename) and DO_OPEN_FILE_UI.
;
; Inputs:
;   WORK_FCB = Populated with target filename and drive.
;
; Outputs:
;   Document line table initialized; LINE_COUNT set; Carry = 0 on success;
;   Carry = 1 on open failure or out-of-memory.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
LOAD_FILE:
	XOR A
	LD (STATUS_OOM_FLAG),A
	LD (FILE_IS_TRUNCATED),A
	LD (DOC_IS_FAT),A
	LD HL,0
	LD (FILE_TOTAL_RECORDS),HL
	LD (FILE_RECORDS_HI),A

	; Reset save format to default CP/M (CR/LF)
	LD A,FMT_CPM
	LD (SAVE_FORMAT),A

	; Synchronize document user area to target file before loading screen
	LD A,(WORK_FCB_USER)
	LD (DOC_USER_NUM),A
	LD (CURRENT_DIR_USER),A
	LD E,A
	LD C,32				; BDOS Set User Area
	CALL BDOS_ENTRY

	LD DE,DEFAULT_DMA
	LD C,26				; BDOS Set DMA
	CALL BDOS_ENTRY

	; Guard: if target drive is hibernated RAM drive, reject load
	CALL CHECK_FCB_IS_HIBERNATED
	JP C,LOAD_FILE_NOT_FOUND

	; Zero FCB extent, s1, s2, rc, and record bytes
	LD HL,WORK_FCB+12
	LD (HL),0
	LD DE,WORK_FCB+13
	LD BC,23
	LDIR

	; Check if filename is empty / spaces
	LD A,(WORK_FCB+1)
	CP ' '
	JP Z,LOAD_FILE_NOT_FOUND
	OR A
	JP Z,LOAD_FILE_NOT_FOUND

	; Probe file size using BDOS Call 35 (Compute File Size)
	LD DE,WORK_FCB
	LD C,35				; BDOS Compute File Size
	CALL BDOS_ENTRY
	LD HL,(WORK_FCB+33)		; r0, r1
	LD (FILE_TOTAL_RECORDS),HL
	LD A,(WORK_FCB+35)		; r2
	LD (FILE_RECORDS_HI),A

	; Zero FCB extent, s1, s2, rc, and record bytes before open
	LD HL,WORK_FCB+12
	LD (HL),0
	LD DE,WORK_FCB+13
	LD BC,23
	LDIR

	LD DE,WORK_FCB
	LD C,15				; BDOS Open File
	CALL BDOS_ENTRY
	CP 0FFH
	JP Z,LOAD_FILE_NOT_FOUND

	XOR A
	LD (WORK_FCB+32),A		; Clear current record (CR)
	LD (SEEN_CR),A
	LD HL,0
	LD (DOC_TOTAL_LINES),HL
	LD (CUR_DOC_ROW),HL
	LD (TOP_DOC_ROW),HL
	LD (CACHE_START_ROW),HL
	CALL CLEAR_CACHE_DIRTY_FLAGS
	LD HL,0
	LD (VIEW_LEFT_COL),HL
	LD A,(ACTIVE_COLS)
	LD L,A
	LD H,0
	LD (VIEW_RIGHT_COL),HL

	CALL INIT_SLOT_SYSTEM

	; Initialize loader state
	LD HL,0FFFFH
	LD (LOAD_HEAD_SLOT),HL
	LD (LOAD_CUR_SLOT),HL
	LD A,2
	LD (LOAD_STRIDE_OFF),A

	; Initialize loading UI state & display
	LD A,1
	LD (IS_LOADING_FILE),A
	LD (HAS_FILE_ARG),A
	XOR A
	LD (IS_SPLASH_SCREEN),A
	LD A,100
	LD (LOAD_PROGRESS_COUNT),A
	LD HL,0
	LD (LOAD_PROGRESS_LINES),HL

	CALL DRAW_LOADING_SCREEN

READ_SECTOR_LOOP:
	LD DE,DEFAULT_DMA
	LD C,26				; BDOS Set DMA
	CALL BDOS_ENTRY

	LD DE,WORK_FCB
	LD C,20				; BDOS Read Next Record
	CALL BDOS_ENTRY
	OR A
	JP NZ,FILE_LOAD_DONE

	LD HL,DEFAULT_DMA
	LD C,128			; 128 bytes per sector

PARSE_BYTE_LOOP:
	LD A,(HL)
	OR A				; NULL padding at EOF
	JP Z,FILE_LOAD_DONE

	CP 26				; CP/M EOF (^Z)
	JP Z,FILE_LOAD_DONE

	CP 13				; CR
	JP Z,HANDLE_CR

	CP 10				; LF
	JP Z,HANDLE_LF

	; Normal character (including 0x09 Tab): stream into Far RAM stride
	; chain
	XOR A
	LD (SEEN_CR),A

	; Check if head slot already allocated for this line
	LD DE,(LOAD_HEAD_SLOT)
	LD A,D
	AND E
	INC A				; 0 if DE == 0xFFFF
	JR NZ,LOAD_HAVE_HEAD

	; Allocate head slot
	PUSH HL				; Save sector pointer
	PUSH BC				; Save sector counter (C)
	CALL APPEND_LINE_SLOT		; BC = allocated slot ID, Carry on OOM
	JR C,LOAD_LINE_OOM
	LD (LOAD_HEAD_SLOT),BC
	LD (LOAD_CUR_SLOT),BC
	LD HL,0FFFFH
	LD (FAR_IO_BUF),HL
	LD A,2
	LD (LOAD_STRIDE_OFF),A
	POP BC
	POP HL

LOAD_HAVE_HEAD:
	; Check if current stride is full (126 chars stored -> LOAD_STRIDE_OFF
	; == 128)
	LD A,(LOAD_STRIDE_OFF)
	CP FAR_SLOT_SIZE		; 128
	JR C,LOAD_STORE_CHAR

	; Stride is full! Allocate an extension slot
	PUSH HL				; Save sector pointer
	PUSH BC				; Save sector counter (C)
	CALL ALLOC_SLOT			; HL = new slot ID, Carry on OOM
	JR C,LOAD_LINE_OOM_EXT

	; Link current stride to new extension slot
	LD (FAR_IO_BUF),HL		; NEXT_SLOT_ID = new slot ID
	PUSH HL				; Save new slot ID

	; Write full current stride to Far RAM
	LD BC,(LOAD_CUR_SLOT)
	LD HL,FAR_IO_BUF
	CALL WRITE_FAR_SLOT

	POP DE				; DE = new slot ID
	LD (LOAD_CUR_SLOT),DE

	; Initialize new stride in FAR_IO_BUF
	LD HL,0FFFFH
	LD (FAR_IO_BUF),HL
	LD A,2
	LD (LOAD_STRIDE_OFF),A

	POP BC
	POP HL

LOAD_STORE_CHAR:
	LD A,(LOAD_STRIDE_OFF)
	LD E,A
	LD D,0
	LD A,(HL)			; Char from sector buffer
	PUSH HL
	LD HL,FAR_IO_BUF
	ADD HL,DE
	LD (HL),A
	POP HL

	LD A,(LOAD_STRIDE_OFF)
	INC A
	LD (LOAD_STRIDE_OFF),A
	JP NEXT_BYTE_IN_SECTOR

LOAD_LINE_OOM_EXT:
	POP BC
	POP HL
	LD A,1
	LD (FILE_IS_TRUNCATED),A
	JP NEXT_BYTE_IN_SECTOR

LOAD_LINE_OOM:
	POP BC
	POP HL
	LD A,1
	LD (FILE_IS_TRUNCATED),A
	JP FILE_LOAD_DONE

HANDLE_CR:
	LD A,1
	LD (SEEN_CR),A
	LD A,FMT_CPM
	LD (SAVE_FORMAT),A
	JP NEXT_BYTE_IN_SECTOR

HANDLE_LF:
	PUSH HL				; Preserve sector buffer pointer HL!
	PUSH BC				; Preserve sector counter C!

	; If no preceding CR, detect Linux format
	LD A,(SEEN_CR)
	OR A
	JR NZ,LF_AFTER_CR
	LD A,FMT_LINUX
	LD (SAVE_FORMAT),A

LF_AFTER_CR:
	XOR A
	LD (SEEN_CR),A

	; Check if a line was open (LOAD_HEAD_SLOT != 0xFFFF)
	LD HL,(LOAD_HEAD_SLOT)
	LD A,H
	AND L
	INC A
	JR NZ,LF_CLOSE_LINE

	; Empty line (LOAD_HEAD_SLOT == 0xFFFF): allocate head slot
	CALL APPEND_LINE_SLOT
	JR C,LF_OOM_HANDLE
	; Initialize empty line in FAR_IO_BUF: NEXT_SLOT_ID = 0xFFFF, byte 2 = 0
	LD HL,0FFFFH
	LD (FAR_IO_BUF),HL
	XOR A
	LD (FAR_IO_BUF+2),A
	; Write to Far RAM
	LD HL,FAR_IO_BUF
	CALL WRITE_FAR_SLOT
	JR LF_LINE_COUNT_INC

LF_CLOSE_LINE:
	; Null-terminate current stride in FAR_IO_BUF if not exactly 128
	LD A,(LOAD_STRIDE_OFF)
	CP FAR_SLOT_SIZE
	JR NC,LF_STRIDE_FULL
	LD E,A
	LD D,0
	LD HL,FAR_IO_BUF
	ADD HL,DE
	LD (HL),0			; Null terminator

LF_STRIDE_FULL:
	; Ensure NEXT_SLOT_ID is 0xFFFF
	LD HL,0FFFFH
	LD (FAR_IO_BUF),HL

	; Write final stride to Far RAM at LOAD_CUR_SLOT
	LD BC,(LOAD_CUR_SLOT)
	LD HL,FAR_IO_BUF
	CALL WRITE_FAR_SLOT

LF_LINE_COUNT_INC:
	LD HL,(DOC_TOTAL_LINES)
	INC HL
	LD (DOC_TOTAL_LINES),HL
	LD (LOAD_PROGRESS_LINES),HL

	; Check 100-line progress interval
	LD A,(LOAD_PROGRESS_COUNT)
	DEC A
	LD (LOAD_PROGRESS_COUNT),A
	JR NZ,LPCI_NO_TICK
	LD A,100
	LD (LOAD_PROGRESS_COUNT),A
	CALL UPDATE_LOAD_PROGRESS
LPCI_NO_TICK:

	; Reset line loader state for next line
	LD HL,0FFFFH
	LD (LOAD_HEAD_SLOT),HL
	LD (LOAD_CUR_SLOT),HL
	LD A,2
	LD (LOAD_STRIDE_OFF),A

	POP BC
	POP HL
	JR NEXT_BYTE_IN_SECTOR

LF_OOM_HANDLE:
	POP BC
	POP HL
	LD A,1
	LD (FILE_IS_TRUNCATED),A
	JP FILE_LOAD_DONE

NEXT_BYTE_IN_SECTOR:
	INC HL
	DEC C
	JP NZ,PARSE_BYTE_LOOP
	JP READ_SECTOR_LOOP

FILE_LOAD_DONE:
	; If remaining characters in buffer, flush final line
	LD HL,(LOAD_HEAD_SLOT)
	LD A,H
	AND L
	INC A
	JR Z,LOAD_FINISH

	LD A,(LOAD_STRIDE_OFF)
	CP FAR_SLOT_SIZE
	JR NC,DONE_STRIDE_FULL
	LD E,A
	LD D,0
	LD HL,FAR_IO_BUF
	ADD HL,DE
	LD (HL),0

DONE_STRIDE_FULL:
	LD HL,0FFFFH
	LD (FAR_IO_BUF),HL
	LD BC,(LOAD_CUR_SLOT)
	LD HL,FAR_IO_BUF
	CALL WRITE_FAR_SLOT

	LD HL,(DOC_TOTAL_LINES)
	INC HL
	LD (DOC_TOTAL_LINES),HL
	LD (LOAD_PROGRESS_LINES),HL

LOAD_FINISH:
	; Final progress update to show exact total lines loaded
	CALL UPDATE_LOAD_PROGRESS
	XOR A
	LD (IS_LOADING_FILE),A

	; Update DOC_USER_NUM and CURRENT_DIR_USER to match loaded file
	LD A,(WORK_FCB_USER)
	LD (DOC_USER_NUM),A
	LD (CURRENT_DIR_USER),A

	; Ensure at least 1 line exists
	LD HL,(DOC_TOTAL_LINES)
	LD A,H
	OR L
	JP NZ,LOAD_INIT_CACHE
	INC HL
	LD (DOC_TOTAL_LINES),HL
	; Write empty line to line 0 in Far RAM
	CALL APPEND_LINE_SLOT
	LD HL,0FFFFH
	LD (FAR_IO_BUF),HL
	XOR A
	LD (FAR_IO_BUF+2),A
	LD HL,FAR_IO_BUF
	CALL WRITE_FAR_SLOT

LOAD_INIT_CACHE:
	XOR A
	LD (IS_LOADING_FILE),A
	LD (BLOCK_ACTIVE),A
	LD (DOC_MODIFIED),A
	LD (STATUS_OOM_FLAG),A
	CALL DRAIN_INPUT_BUFFER
	CALL INVALIDATE_ACTIVE_LINE
	CALL CHECKOUT_ACTIVE_LINE
	CALL RELOAD_CACHE_WINDOW_FORCE
	OR A				; Carry = 0 (success)
	RET

LOAD_FILE_NOT_FOUND:
	; Restore BDOS user area to CURRENT_DIR_USER
	LD A,(CURRENT_DIR_USER)
	LD E,A
	LD C,32				; BDOS Set User Area
	CALL BDOS_ENTRY
	XOR A
	LD (IS_LOADING_FILE),A
	CALL DRAIN_INPUT_BUFFER
	SCF				; Carry = 1 (error: file not found)
	RET

;------------------------------------------------------------------------------
; DRAW_LOADING_SCREEN: Render loading file progress modal dialog frame
;
; Purpose:
;   Draws centered modal box border, displays "Loading..." title, formats
;   filename, drive, and user area info, and renders initial progress bar.
;
; Call Usage / Protocol:
;   Called via CALL from LOAD_FILE before reading file data.
;
; Inputs:
;   WORK_FCB = Target file FCB.
;
; Outputs:
;   Terminal screen updated with modal dialog box.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DRAW_LOADING_SCREEN:
	; Hide cursor during load
	CALL TERM_HIDE_CURSOR

	; Clear screen (cursor moves to row 1, col 1)
	CALL TERM_CLEAR_SCREEN

	; Fill rows 1 to ACTIVE_ROWS - 1 with '~' in column 0
	LD A,(ACTIVE_ROWS)
	DEC A				; A = ACTIVE_ROWS - 1
	LD B,A
DLS_TILDE_LOOP:
	LD A,'~'
	CALL PUTC
	LD A,13
	CALL PUTC
	LD A,10
	CALL PUTC
	DJNZ DLS_TILDE_LOOP

	; Render initial status bar on row ACTIVE_ROWS
	CALL RENDER_STATUS_BAR

	; Determine modal title: "Inserting File" if block insert, else "Opening
	; File"
	LD DE,STR_POPUP_OPEN_TITLE
	LD A,(IS_BLOCK_INSERT_UI)
	OR A
	JR Z,DLS_SHOW_MODAL
	LD DE,STR_POPUP_INSERT_TITLE
DLS_SHOW_MODAL:
	JP DRAW_PROGRESS_MODAL

;------------------------------------------------------------------------------
; DRAW_PROGRESS_MODAL: Draw generic progress dialog modal frame
;
; Purpose:
;   Renders top border, title line, blank padding lines, progress bar frame,
;   and bottom border centered horizontally and vertically on screen.
;
; Call Usage / Protocol:
;   Called via CALL from DRAW_LOADING_SCREEN and INIT_SAVE_PROGRESS.
;
; Inputs:
;   DE = Pointer to null-terminated modal title string.
;
; Outputs:
;   Modal dialog frame emitted to terminal.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DRAW_PROGRESS_MODAL:
	PUSH DE				; Save title pointer

	; 1. Calculate POPUP_COL = ((ACTIVE_COLS - 50) / 2) + 1
	LD A,(ACTIVE_COLS)
	SUB 50
	SRL A
	INC A
	LD (POPUP_COL),A

	; 2. Calculate POPUP_ROW = ((ACTIVE_ROWS - 7) / 2) + 1
	LD A,(ACTIVE_ROWS)
	SUB 7
	SRL A
	INC A
	LD (POPUP_ROW),A
	LD (POPUP_START_ROW),A

	; Line 1: Top Border
	CALL POPUP_PRINT_BORDER

	; Line 2: Title
	CALL POPUP_LOCATE_NEXT
	POP DE				; DE = title pointer
	CALL PRINT_STR

	; Line 3: Separator Border
	CALL POPUP_PRINT_BORDER

	; Line 4: Target Filename (centered "File: <NAME>")
	CALL POPUP_LOCATE_NEXT
	CALL FORMAT_PROGRESS_FILE_LINE
	EX DE,HL			; DE = STR_POPUP_PROGRESS_FILE
	CALL PRINT_STR

	; Line 5: Progress Line
	CALL POPUP_LOCATE_NEXT
	LD DE,STR_POPUP_PROGRESS_LINE
	CALL PRINT_STR

	; Line 6: Subtext
	CALL POPUP_LOCATE_NEXT
	LD DE,STR_POPUP_PROGRESS_SUB
	CALL PRINT_STR

	; Line 7: Bottom Border
	JP POPUP_PRINT_BORDER

;------------------------------------------------------------------------------
; FORMAT_PROGRESS_FILE_LINE: Format file path and info for progress dialog
;
; Purpose:
;   Formats drive letter, user area prefix (if non-zero), 8.3 filename, and
;   file size into destination text buffer for display in modal progress box.
;
; Call Usage / Protocol:
;   Called via CALL from DRAW_PROGRESS_MODAL helper routines.
;
; Inputs:
;   HL = Pointer to FCB.
;   DE = Pointer to destination string buffer.
;
; Outputs:
;   Formatted null-terminated string in buffer.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
FORMAT_PROGRESS_FILE_LINE:
	; Step 1: Format "File: <TARGET>" into PROGRESS_FILENAME_STR
	LD DE,PROGRESS_FILENAME_STR
	LD HL,STR_POPUP_PROGRESS_PFX		; "File: "
	LD C,6					; C = length counter

FPFL_CPY_PFX:
	LD A,(HL)
	OR A
	JR Z,FPFL_PFX_DONE
	LD (DE),A
	INC DE
	INC HL
	JR FPFL_CPY_PFX

FPFL_PFX_DONE:
	; Check if FAT file (block insert or document)
	LD A,(BLOCK_INSERT_IS_FAT)
	OR A
	JR NZ,FPFL_FAT_INS
	LD A,(DOC_IS_FAT)
	OR A
	JR Z,FPFL_CPM_FILE
	LD A,(FAT_DOC_UNIT)
	JR FPFL_FAT_FMT
FPFL_FAT_INS:
	LD A,(VFS_REQ_UNIT)
FPFL_FAT_FMT:
	PUSH AF
	LD A,'U'
	LD (DE),A
	INC DE
	INC C
	POP AF
	CP 0FFH
	JR Z,FPFL_FAT_COLON
	ADD A,'0'
	LD (DE),A
	INC DE
	INC C

FPFL_FAT_COLON:
	LD A,':'
	LD (DE),A
	INC DE
	INC C
	LD HL,FAT_DOC_FNAME
FPFL_FAT_NAME_LOOP:
	LD A,(HL)
	OR A
	JR Z,FPFL_STR_DONE
	CP ' '
	JR Z,FPFL_STR_DONE
	LD (DE),A
	INC DE
	INC HL
	INC C
	LD A,C
	CP 44					; Keep within 48 max
	JR C,FPFL_FAT_NAME_LOOP
	JR FPFL_STR_DONE

FPFL_CPM_FILE:
	; CP/M file: check if filename is empty / Untitled
	LD A,(WORK_FCB+1)
	CP ' '
	JR Z,FPFL_UNTITLED
	OR A
	JR Z,FPFL_UNTITLED

	; Determine drive letter
	LD A,(WORK_FCB)
	OR A
	JR NZ,FPFL_USE_DRIVE
	LD A,(CURRENT_DIR_DRIVE)
FPFL_USE_DRIVE:
	ADD A,'A'-1
	LD (DE),A
	INC DE
	INC C

	; Check user area in WORK_FCB_USER
	LD A,(WORK_FCB_USER)
	OR A
	JR Z,FPFL_EMIT_COLON
	CP 10
	JR C,FPFL_USER_1DIGIT
	PUSH AF
	LD A,'1'
	LD (DE),A
	INC DE
	INC C
	POP AF
	SUB 10
FPFL_USER_1DIGIT:
	ADD A,'0'
	LD (DE),A
	INC DE
	INC C

FPFL_EMIT_COLON:
	LD A,':'
	LD (DE),A
	INC DE
	INC C

	; Copy filename (WORK_FCB+1..8)
	LD HL,WORK_FCB+1
	LD B,8
	CALL FPFL_COPY_FCB_FIELD

	; Check extension (WORK_FCB+9..11)
	LD HL,WORK_FCB+9
	LD A,(HL)
	CP ' '
	JR Z,FPFL_STR_DONE
	OR A
	JR Z,FPFL_STR_DONE

	LD A,'.'
	LD (DE),A
	INC DE
	INC C

	LD B,3
	CALL FPFL_COPY_FCB_FIELD
	JR FPFL_STR_DONE

;------------------------------------------------------------------------------
; FPFL_COPY_FCB_FIELD: Copy and space-trim FCB filename or extension field
;
; Purpose:
;   Copies up to B characters from FCB at HL to buffer at DE, stripping
;   trailing spaces.
;
; Call Usage / Protocol:
;   Called via CALL from FORMAT_PROGRESS_FILE_LINE.
;
; Inputs:
;   HL = Source character pointer in FCB.
;   DE = Destination buffer pointer.
;   B  = Maximum field length (8 for name, 3 for extension).
;
; Outputs:
;   HL and DE advanced; copied non-space characters written.
;
; Preserves / Modifies:
;   Clobbers AF, B; advances DE and HL.
;------------------------------------------------------------------------------
FPFL_COPY_FCB_FIELD:
	LD A,(HL)
	CP ' '
	RET Z
	OR A
	RET Z
	LD (DE),A
	INC DE
	INC HL
	INC C
	DJNZ FPFL_COPY_FCB_FIELD
	RET

FPFL_UNTITLED:
	LD HL,STR_NO_NAME			; "(Untitled)"
FPFL_UNTITLED_LOOP:
	LD A,(HL)
	OR A
	JR Z,FPFL_STR_DONE
	LD (DE),A
	INC DE
	INC HL
	INC C
	JR FPFL_UNTITLED_LOOP

FPFL_STR_DONE:
	XOR A
	LD (DE),A				; Null terminate string

	; Step 2: Initialize STR_POPUP_PROGRESS_FILE with '|', 48 spaces, '|', 0
	LD HL,STR_POPUP_PROGRESS_FILE
	LD (HL),'|'
	INC HL
	LD B,48
	LD A,' '
FPFL_FILL_SPACES:
	LD (HL),A
	INC HL
	DJNZ FPFL_FILL_SPACES
	LD (HL),'|'
	INC HL
	LD (HL),0

	; Step 3: Compute centering offset: left_spaces = (48 - C) / 2
	LD A,C
	CP 48
	JR C,FPFL_CALC_PAD
	LD A,48
	LD C,A
FPFL_CALC_PAD:
	LD A,48
	SUB C
	SRL A					; A = left spaces

	; Target offset = STR_POPUP_PROGRESS_FILE + 1 + left spaces
	LD HL,STR_POPUP_PROGRESS_FILE+1
	LD E,A
	LD D,0
	ADD HL,DE				; HL = destination in buffer

	; Step 4: Copy C characters from PROGRESS_FILENAME_STR into HL
	LD DE,PROGRESS_FILENAME_STR
	LD B,C
FPFL_COPY_TEXT:
	LD A,(DE)
	LD (HL),A
	INC DE
	INC HL
	DJNZ FPFL_COPY_TEXT

	; Return HL = STR_POPUP_PROGRESS_FILE
	LD HL,STR_POPUP_PROGRESS_FILE
	RET

;------------------------------------------------------------------------------
; UPDATE_LOAD_PROGRESS: Increment and redraw file loading progress indicator
;
; Purpose:
;   Tracks processed record count during LOAD_FILE, calculating percentage and
;   updating the visual progress bar fill characters inside modal dialog.
;
; Call Usage / Protocol:
;   Called via CALL after each 128-byte sector read in LOAD_FILE.
;
; Inputs:
;   None.
;
; Outputs:
;   Progress indicator refreshed on terminal.
;
; Preserves / Modifies:
;   Clobbers AF; preserves BC, DE, HL.
;------------------------------------------------------------------------------
UPDATE_LOAD_PROGRESS:
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL

	; Locate cursor inside popup box at (POPUP_START_ROW + 4, POPUP_COL +
	; 20)
	LD A,(POPUP_START_ROW)
	ADD A,4
	LD H,A
	LD A,(POPUP_COL)
	ADD A,20
	LD L,A
	CALL LOCATE_RC

	LD DE,STR_PROGRESS_LINE_LBL
	CALL PRINT_STR

	; Print line number right-justified in 5 chars
	LD HL,(LOAD_PROGRESS_LINES)
	CALL GET_DEC_WORD_DIGITS	; A = digits (1..5)
	LD C,A
	LD A,5
	SUB C
	JR C,ULP_NUM
	JR Z,ULP_NUM
	LD B,A
ULP_PAD:
	LD A,' '
	CALL PUTC
	DJNZ ULP_PAD
ULP_NUM:
	LD HL,(LOAD_PROGRESS_LINES)
	CALL PRINT_DEC_WORD

	POP HL
	POP DE
	POP BC
	POP AF
	RET

;------------------------------------------------------------------------------
; INIT_EMPTY_DOCUMENT: Initialize blank editor document state
;
; Purpose:
;   Clears far RAM line tables, resets LINE_COUNT to 0, sets cursor to (0,0),
;   resets viewport scroll offsets, marks document as unmodified, and clears
;   WORK_FCB for a new empty buffer.
;
; Call Usage / Protocol:
;   Called via CALL on editor startup without file, New Document, or load error.
;
; Inputs:
;   None.
;
; Outputs:
;   Clean document state initialized.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
INIT_EMPTY_DOCUMENT:
	CALL INIT_SLOT_SYSTEM
	CALL ALLOC_SLOT			; HL = 0
	LD BC,0
	CALL SET_LINE_SLOT		; Line 0 = slot 0

	LD HL,1
	LD (DOC_TOTAL_LINES),HL
	LD HL,0
	LD (CUR_DOC_ROW),HL
	LD (TOP_DOC_ROW),HL
	LD (CACHE_START_ROW),HL
	LD (CUR_COL),HL
	LD (TARGET_COL),HL
	CALL CLEAR_CACHE_DIRTY_FLAGS
	XOR A
	LD (DOC_MODIFIED),A
	LD (BLOCK_ACTIVE),A
	LD (STATUS_OOM_FLAG),A
	LD (FILE_IS_TRUNCATED),A
	LD HL,0
	LD (VIEW_LEFT_COL),HL
	LD A,(ACTIVE_COLS)
	LD L,A
	LD H,0
	LD (VIEW_RIGHT_COL),HL
	LD A,1
	LD (INSERT_MODE),A

	; Write empty line to line 0 in Far RAM
	LD HL,0FFFFH
	LD (FAR_IO_BUF),HL
	XOR A
	LD (FAR_IO_BUF+2),A
	LD HL,FAR_IO_BUF
	LD BC,0
	CALL WRITE_FAR_SLOT

	; Invalidate and force reload local cache window
	CALL INVALIDATE_ACTIVE_LINE
	CALL CHECKOUT_ACTIVE_LINE
	CALL RELOAD_CACHE_WINDOW_FORCE
	RET

;------------------------------------------------------------------------------
; DO_OPEN_FILE_UI: Interactive Open File modal dialog and directory browser
;
; Purpose:
;   Displays full-screen modal browser listing files on current drive/user,
;   provides interactive filename input box with editing/history, handles
;   drive/user switching, and loads selected file into editor upon Enter.
;
; Call Usage / Protocol:
;   Called via CALL when user requests Open File (Ctrl+O).
;
; Inputs:
;   None.
;
; Outputs:
;   Target file loaded into editor, or cancelled if user presses Esc.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_OPEN_FILE_UI:
	; Backup active document FAT flag on entry to open UI
	LD A,(DOC_IS_FAT)
	LD (PREV_DOC_IS_FAT),A

	; Invalidate active line and flush dirty cache before directory
	; collection
	; overlays LINE_STORAGE
	CALL INVALIDATE_ACTIVE_LINE
	CALL FLUSH_DIRTY_CACHE
	LD HL,0FFFFH
	LD (CACHE_START_ROW),HL

	; Initialize directory layout parameters based on active screen mode
	CALL INIT_DIR_LAYOUT

	; Initialize active directory drive from default disk or WORK_FCB
	CALL INIT_DIR_DRIVE

	; Initialize directory user area from current document or plugin user
	; area
	LD A,(IS_PLUGIN_LOAD_UI)
	OR A
	JR Z,IDU_DOC
	LD A,(PLUGIN_USER_AREA)
	JR IDU_SET
IDU_DOC:
	LD A,(DOC_USER_NUM)
IDU_SET:
	LD (CURRENT_DIR_USER),A

	; Filter defaults to all files shown unless explicitly provided in edit
	; box
	CALL RESET_DIR_FILTER

	; Preload edit box with known current drive and user area prefix (e.g.
	; "J0:", "A4:")
	CALL PRELOAD_DRIVE_USER_PREFIX
	LD HL,0
	LD (OPEN_GOTO_LINE),HL

REFRESH_OPEN_DIR:
	; 1. Collect Directory Entries from CURRENT_DIR_DRIVE (with Bit-7 strip
	; & dup filter)
	CALL COLLECT_DIR_ENTRIES

	; 2. Sort Directory Entries Alphabetically
	CALL SORT_DIR_ENTRIES

	; 3. Calculate Total Pages (using dynamic DIR_PAGE_CAPACITY)
	CALL CALC_DIR_PAGES

RENDER_OPEN_PAGE:
	CALL TERM_INIT
	LD A,1
	LD (IS_SPLASH_SCREEN),A
	CALL RENDER_DIR_TITLE

	; Display Directory Entries for Current Page
	CALL DISPLAY_DIR_PAGE

	; Display Open Prompt & Page Indicator
	CALL DISPLAY_OPEN_PROMPT

	; Finish prompt line and fill remaining rows down to status row with '~'
	CALL FINISH_UI_PAGE_AND_STATUS

	; Read Filename Input (echoes prefilled string if non-empty, e.g. "A:")
	CALL READ_FILENAME_INPUT_PREFILLED
	JP C,CHECK_PAGING_OR_CANCEL

	; Check if user typed a FAT specification (U: or U<unit>:)
	CALL CHECK_FAT_INPUT_OPEN
	JR NC,CFIO_DISPATCH_CHECK
	CALL SHOW_POPUP_FAT_NO_PLUGIN
	JP RENDER_OPEN_PAGE
CFIO_DISPATCH_CHECK:
	JP NZ,HANDLE_OPEN_FAT_DISPATCH

	; Check if user typed a drive specification (e.g. "A:")
	CALL CHECK_DRIVE_SWITCH
	JP C,HANDLE_OPEN_DRIVE_SWITCH

	; Check if user typed a filter pattern (e.g. "*.TXT" or "B:*.TXT")
	CALL CHECK_FILTER_PATTERN
	JP C,HANDLE_OPEN_FILTER

	; If currently browsing a FAT volume, handle relative navigation/open
	LD A,(CURRENT_DIR_IS_FAT)
	OR A
	JP NZ,HANDLE_OPEN_FAT_RELATIVE

DO_PARSE_AND_LOAD:
	; Backup current WORK_FCB to DIR_TEMP_FCB in case open fails
	LD HL,WORK_FCB
	LD DE,DIR_TEMP_FCB
	LD BC,36
	LDIR

	; Check if this is Block Insert File UI!
	LD A,(IS_BLOCK_INSERT_UI)
	OR A
	JP NZ,DO_PARSE_AND_INSERT

	; Check if this is Plugin Load UI!
	LD A,(IS_PLUGIN_LOAD_UI)
	OR A
	JP NZ,DO_PARSE_AND_LOAD_PLUGIN

	; Parse optional line number from INPUT_FILENAME_BUF
	CALL PARSE_OPEN_LINE_NUM

	; User entered a filename in INPUT_FILENAME_BUF: parse into WORK_FCB
	LD DE,INPUT_FILENAME_BUF
	CALL PARSE_FILENAME_TO_FCB

	; Check if target drive is unavailable RAM drive
	LD A,(WORK_FCB)
	CALL CHECK_TARGET_DRIVE_UNAVAILABLE
	JR C,OPEN_RAMDRV_UNAVAILABLE

	; Clear FAT document flag before loading CP/M file
	XOR A
	LD (DOC_IS_FAT),A

	; Load the file into Far RAM
	CALL LOAD_FILE
	JP C,OPEN_FILE_NOT_FOUND

	; Reset stack and enter editor mode
	LD SP,LOCAL_STACK
	LD A,1
	LD (HAS_FILE_ARG),A
	LD (IN_EDITOR_MODE),A
	XOR A
	LD (DOC_IS_FAT),A

	; Check if target goto line was specified (> 0)
	LD HL,(OPEN_GOTO_LINE)
	LD A,H
	OR L
	JR Z,OPEN_LINE_DEFAULT
	CALL GOTO_LINE_HL
	JR OPEN_RENDER

OPEN_LINE_DEFAULT:
	LD HL,0
	LD (CUR_DOC_ROW),HL
	LD (TOP_DOC_ROW),HL
	XOR A
	LD (CUR_COL),A
	LD (TARGET_COL),A

OPEN_RENDER:
	CALL TERM_INIT
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	CALL CHECK_FILE_TRUNCATED_POPUP
	CALL LOCATE_CURSOR
	JP MAIN_LOOP

HANDLE_OPEN_DRIVE_SWITCH:
	; A = new drive (1..16 or 0), C = new user (0..15 or 0xFF)
	PUSH BC				; Save target user
	OR A
	JR Z,HODS_DRIVE_DONE		; Drive unchanged

	CALL CHECK_TARGET_DRIVE_UNAVAILABLE
	JR NC,HODS_OK

	; Cannot switch to unavailable RAM drive!
	POP BC
	JR OPEN_RAMDRV_UNAVAILABLE

HODS_OK:
	LD (CURRENT_DIR_DRIVE),A
	ADD A,'A'-1
	LD (STR_DIR_DRIVE_CHAR),A
	XOR A
	LD (CURRENT_DIR_IS_FAT),A

HODS_DRIVE_DONE:
	POP BC				; C = target user
	LD A,C
	CP 0FFH
	JR Z,HODS_USER_DEFAULT_ZERO
	LD (CURRENT_DIR_USER),A
	JR HODS_RESET_FILTER
HODS_USER_DEFAULT_ZERO:
	XOR A
	LD (CURRENT_DIR_USER),A

HODS_RESET_FILTER:
	; A drive/user switch without wildcard defaults to all files shown
	CALL RESET_DIR_FILTER
	XOR A
	LD (SHOWING_FNF_MSG),A
	JP REFRESH_OPEN_DIR

HANDLE_OPEN_FILTER:
	XOR A
	LD (SHOWING_FNF_MSG),A
	JP REFRESH_OPEN_DIR

OPEN_RAMDRV_UNAVAILABLE:
	CALL RESTORE_WORK_FCB_FROM_TEMP
	LD A,(PREV_DOC_IS_FAT)
	LD (DOC_IS_FAT),A
	CALL SHOW_POPUP_RAMDRV_UNAVAIL
	JP RENDER_OPEN_PAGE

OPEN_FILE_NOT_FOUND:
	CALL RESTORE_WORK_FCB_FROM_TEMP
	LD A,(PREV_DOC_IS_FAT)
	LD (DOC_IS_FAT),A
	CALL SHOW_POPUP_FILE_NOT_FOUND
	JP RENDER_OPEN_PAGE

CHECK_PAGING_OR_CANCEL:
	; A = return code: 0 = Cancel (ESC), 1 = Next Page (PgDn), 3 = Prev Page
	; (PgUp)
	CP 1
	JR Z,DO_NEXT_PAGE
	CP 3
	JR Z,DO_PREV_PAGE
	XOR A
	LD (IS_PLUGIN_LOAD_UI),A
	LD (IS_SPLASH_SCREEN),A
	CALL RESTORE_DOC_USER
	LD A,(PREV_DOC_IS_FAT)
	LD (DOC_IS_FAT),A
	LD HL,0FFFFH
	LD (CACHE_START_ROW),HL
	SCF				; Carry = 1 (Cancelled)
	RET				; Cancelled -> return to caller

DO_PREV_PAGE:
	LD A,(DIR_PAGE_INDEX)
	OR A
	JR Z,DO_PREV_PAGE_WRAP
	DEC A
	JR SET_NEXT_PAGE
DO_PREV_PAGE_WRAP:
	LD A,(DIR_PAGE_COUNT)
	DEC A
	JR SET_NEXT_PAGE

DO_NEXT_PAGE:
	LD A,(DIR_PAGE_INDEX)
	INC A
	LD HL,DIR_PAGE_COUNT
	CP (HL)
	JR C,SET_NEXT_PAGE
	XOR A				; Wrap around to page 0
SET_NEXT_PAGE:
	LD (DIR_PAGE_INDEX),A
	JP RENDER_OPEN_PAGE

;------------------------------------------------------------------------------
; DO_PARSE_AND_LOAD_PLUGIN: Parse filename and load plugin into registry slot
;
; Purpose:
;   Parses plugin filename from INPUT_FILENAME_BUF, locates free slot in
;   plugin registry, loads PRL/OVL binary into far RAM or TPA, and initializes
;   plugin descriptor metadata.
;
; Call Usage / Protocol:
;   Jumped to from DO_OPEN_FILE_UI when IS_PLUGIN_LOAD_UI flag is active.
;
; Inputs:
;   INPUT_FILENAME_BUF = Contains entered plugin filename.
;
; Outputs:
;   Plugin loaded into registry; returns to caller.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_PARSE_AND_LOAD_PLUGIN:
	LD DE,INPUT_FILENAME_BUF
	CALL LOAD_PLUGIN_BY_NAME
	JR C,OPEN_PLUGIN_FAIL

	; Success: clear flags, restore user area, and return to caller
	PUSH AF			; Preserve return A (slot number) & Carry
	XOR A
	LD (IS_PLUGIN_LOAD_UI),A
	LD (IS_SPLASH_SCREEN),A
	CALL RESTORE_DOC_USER
	LD HL,0FFFFH
	LD (CACHE_START_ROW),HL
	POP AF				; Restore return A (slot number) & Carry
	RET

OPEN_PLUGIN_FAIL:
	CALL RESTORE_DOC_USER
	CALL SHOW_POPUP_FILE_NOT_FOUND
	JP RENDER_OPEN_PAGE

;------------------------------------------------------------------------------
; Block Insert File UI & Execution Subsystem
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; DO_PARSE_AND_INSERT: Parse filename and insert file at cursor position
;
; Purpose:
;   Parses external filename from INPUT_FILENAME_BUF into INSERT_FCB, verifies
;   file existence and accessibility, preserves document WORK_FCB, streams file
;   text into editor at current cursor row/col, and refreshes screen.
;
; Call Usage / Protocol:
;   Jumped to from DO_OPEN_FILE_UI when IS_BLOCK_INSERT flag is active.
;
; Inputs:
;   INPUT_FILENAME_BUF = Contains entered filename.
;   ACTIVE_ROW, ACTIVE_COL = Insertion coordinates.
;
; Outputs:
;   File text inserted into document; viewport adjusted.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_PARSE_AND_INSERT:
	; User entered a filename in INPUT_FILENAME_BUF: parse into WORK_FCB
	LD DE,INPUT_FILENAME_BUF
	CALL PARSE_FILENAME_TO_FCB

	; Check if target drive is unavailable RAM drive
	LD A,(WORK_FCB)
	CALL CHECK_TARGET_DRIVE_UNAVAILABLE
	JP C,OPEN_RAMDRV_UNAVAILABLE

	; Copy parsed FCB to INSERT_FCB
	LD HL,WORK_FCB
	LD DE,INSERT_FCB
	LD BC,36
	LDIR

	; Save WORK_FCB_USER into BLOCK_IO_USER
	LD A,(WORK_FCB_USER)
	LD (BLOCK_IO_USER),A

	CALL RESTORE_WORK_FCB_FROM_TEMP

	; Set BDOS user area to BLOCK_IO_USER
	LD A,(BLOCK_IO_USER)
	LD E,A
	LD C,32				; BDOS Set User Area
	CALL BDOS_ENTRY

	; Probe and open INSERT_FCB
	CALL PROBE_INSERT_FILE
	JR NC,DPAI_PROBE_OK

	; Probe failed: restore BDOS user area to CURRENT_DIR_USER
	LD A,(CURRENT_DIR_USER)
	LD E,A
	LD C,32				; BDOS Set User Area
	CALL BDOS_ENTRY
	JP OPEN_FILE_NOT_FOUND

DPAI_PROBE_OK:
	; Setup loading UI for block insert
	LD A,(HAS_FILE_ARG)
	LD (SAVED_HAS_FILE_ARG),A

	; Display inserted file name in status bar
	LD HL,INSERT_FCB
	LD DE,WORK_FCB
	LD BC,36
	LDIR

	LD A,(BLOCK_IO_USER)
	LD (WORK_FCB_USER),A

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

DPAI_CLEANUP:
	CALL RESTORE_WORK_FCB_FROM_TEMP

	; Restore original HAS_FILE_ARG
	LD A,(SAVED_HAS_FILE_ARG)
	LD (HAS_FILE_ARG),A

	; Insertion complete: clear insert flag, loading flag, and splash flag
	XOR A
	LD (BLOCK_INSERT_IS_FAT),A
	LD (IS_BLOCK_INSERT_UI),A
	LD (IS_LOADING_FILE),A
	LD (IS_SPLASH_SCREEN),A
	LD (NEED_SCREEN_RENDER),A
	LD (NEED_LINE_RENDER),A
	LD (NEED_STATUS_RENDER),A

	; Restore BDOS user area to CURRENT_DIR_USER
	LD A,(CURRENT_DIR_USER)
	LD E,A
	LD C,32				; BDOS Set User Area
	CALL BDOS_ENTRY

	; Reset stack and resume editor mode
	LD SP,LOCAL_STACK
	CALL TERM_INIT
	CALL RENDER_SCREEN
	CALL RENDER_STATUS_BAR
	JP MAIN_LOOP

;------------------------------------------------------------------------------
; PROBE_INSERT_FILE: Verify accessibility and size of file for block insert
;
; Purpose:
;   Attempts to open target insert file in INSERT_FCB via BDOS, verifies that
;   it exists and has readable records, and closes FCB before insertion.
;
; Call Usage / Protocol:
;   Called via CALL from DO_PARSE_AND_INSERT.
;
; Inputs:
;   INSERT_FCB = Target file FCB.
;
; Outputs:
;   Carry = 0 if file exists and is accessible; Carry = 1 on failure.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
PROBE_INSERT_FILE:
	LD DE,DEFAULT_DMA
	LD C,26				; BDOS Set DMA (0080H)
	CALL BDOS_ENTRY

	; Check if INSERT_FCB targets hibernated RAM drive
	LD A,(RAMDRIVE_IS_HIBERNATED)
	OR A
	JR Z,PIF_RAM_OK
	LD A,(RAMDRIVE_DRIVE_NUM)
	CP 0FFH
	JR Z,PIF_RAM_OK
	LD B,A				; B = RAM drive number (0-based)
	LD A,(INSERT_FCB)
	OR A
	JR NZ,PIF_EXPLICIT
	LD A,(CURRENT_DEFAULT_DRIVE)
	JR PIF_COMPARE
PIF_EXPLICIT:
	DEC A				; 1->0, 2->1
PIF_COMPARE:
	CP B
	JR NZ,PIF_RAM_OK
	SCF				; Carry = 1: conflict
	RET

PIF_RAM_OK:
	; Check if filename is empty / spaces
	LD A,(INSERT_FCB+1)
	CP ' '
	SCF
	RET Z
	OR A
	SCF
	RET Z

	; Zero FCB extent, s1, s2, rc, and record bytes
	LD HL,INSERT_FCB+12
	LD (HL),0
	LD DE,INSERT_FCB+13
	LD BC,23
	LDIR

	; Open file via BDOS 15
	LD DE,INSERT_FCB
	LD C,15				; BDOS Open File
	CALL BDOS_ENTRY
	CP 0FFH
	JR NZ,PIF_OPEN_OK
	SCF
	RET

PIF_OPEN_OK:
	XOR A
	LD (INSERT_FCB+32),A		; Clear CR (Current Record)
	OR A				; Carry = 0: success
	RET

;------------------------------------------------------------------------------
; DO_PERFORM_BLOCK_INSERT: Stream external file lines into active document
;
; Purpose:
;   Reads external file sequentially via BDOS, splits text into lines at CRLF,
;   inserts characters into active line or creates new lines at cursor position
;   using far RAM line table manipulation, and adjusts total line count.
;
; Call Usage / Protocol:
;   Called via CALL from DO_PARSE_AND_INSERT after file probe succeeds.
;
; Inputs:
;   INSERT_FCB = Openable FCB for source file.
;
; Outputs:
;   Document updated with inserted text; Carry = 0 on success, Carry = 1 on OOM.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_PERFORM_BLOCK_INSERT:
	; Check if block is empty:
	; BLOCK_START_ROW == BLOCK_END_ROW and BLOCK_START_COL == BLOCK_END_COL
	LD HL,(BLOCK_START_ROW)
	LD DE,(BLOCK_END_ROW)
	LD A,H
	CP D
	JR NZ,DPBI_NON_EMPTY
	LD A,L
	CP E
	JR NZ,DPBI_NON_EMPTY
	LD HL,(BLOCK_START_COL)
	LD DE,(BLOCK_END_COL)
	LD A,H
	CP D
	JR NZ,DPBI_NON_EMPTY
	LD A,L
	CP E
	JR NZ,DPBI_NON_EMPTY

	; Block is empty: cancel block selection, ensure cursor is at insertion
	; point
	CALL CANCEL_BLOCK
	LD HL,(BLOCK_START_ROW)
	LD (CUR_DOC_ROW),HL
	LD HL,(BLOCK_START_COL)
	LD (CUR_COL),HL
	JR DPBI_SPLIT_HOST

DPBI_NON_EMPTY:
	; Non-empty block: DO_DELETE_BLOCK deletes selected text,
	; clears BLOCK_ACTIVE, and sets (CUR_DOC_ROW, CUR_COL) =
	; (BLOCK_START_ROW, BLOCK_START_COL)
	CALL DO_DELETE_BLOCK
	LD HL,(BLOCK_START_ROW)
	LD (CUR_DOC_ROW),HL
	LD HL,(BLOCK_START_COL)
	LD (CUR_COL),HL

DPBI_SPLIT_HOST:
	; Ensure CUR_DOC_ROW is checked out in ACTIVE_LINE_BUF
	CALL CHECKOUT_ACTIVE_LINE

	; Clamp CUR_COL to line length
	CALL GET_CUR_ROW_LEN		; DE = line byte length
	LD HL,(CUR_COL)
	CALL CMP_HL_DE			; Carry=1 if CUR_COL < DE
	JR C,DPBI_COL_OK
	LD (CUR_COL),DE
DPBI_COL_OK:
	; Record insertion start position
	LD HL,(CUR_DOC_ROW)
	LD (INSERT_ORIG_START_ROW),HL
	LD HL,(CUR_COL)
	LD (INSERT_ORIG_START_COL),HL

	; Split ACTIVE_LINE_BUF at CUR_COL:
	; Copy suffix (from CUR_COL to null) into SPLIT_LINE_TEMP
	LD HL,ACTIVE_LINE_BUF
	LD DE,(CUR_COL)
	ADD HL,DE			; HL = split point in ACTIVE_LINE_BUF
	LD DE,SPLIT_LINE_TEMP
DPBI_SPLIT_LOOP:
	LD A,(HL)
	LD (DE),A
	LD (HL),0			; Truncate current line at split point
	INC HL
	INC DE
	OR A
	JR NZ,DPBI_SPLIT_LOOP

	; Host prefix remains in ACTIVE_LINE_BUF with length (CUR_COL)
	LD HL,(CUR_COL)
	LD (INSERT_CUR_LEN),HL

	; Detach ACTIVE_LINE_ROW so active line system won't auto-commit scratch
	; buffer
	LD HL,0FFFFH
	LD (ACTIVE_LINE_ROW),HL
	XOR A
	LD (ACTIVE_LINE_DIRTY),A

	LD A,1
	LD (INSERT_IS_FIRST_LINE),A
	XOR A
	LD (SEEN_CR),A

	; Stream sectors from INSERT_FCB (or FAT stream)
DPBI_READ_SECTOR:
	LD A,(BLOCK_INSERT_IS_FAT)
	OR A
	JR NZ,DPBI_READ_FAT_CHUNK

	LD DE,DEFAULT_DMA
	LD C,26				; BDOS Set DMA (0080H)
	CALL BDOS_ENTRY

	LD DE,INSERT_FCB
	LD C,20				; BDOS Read Next Record
	CALL BDOS_ENTRY
	OR A
	JP NZ,DPBI_HIT_EOF		; EOF or read error

	LD HL,DEFAULT_DMA
	LD B,128			; 128 bytes per sector
	JR DPBI_BYTE_LOOP

DPBI_READ_FAT_CHUNK:
	LD A,6				; VFS_CMD_READ_CHUNK
	LD (VFS_REQ_CMD),A
	XOR A
	LD (VFS_REQ_STATUS),A
	LD HL,FAT_CHUNK_BUF
	LD (VFS_REQ_BUFFER),HL
	LD HL,128
	LD (VFS_REQ_BUFSIZE),HL
	CALL VFS_EXEC_REQUEST
	JR C,DPBI_FAT_EOF
	LD A,(VFS_REQ_STATUS)
	CP 6				; VFS_STAT_EOF
	JR Z,DPBI_FAT_EOF
	OR A
	JR NZ,DPBI_FAT_EOF		; Error -> EOF
	LD HL,(VFS_REQ_COUNT)
	LD A,L
	OR H
	JR Z,DPBI_FAT_EOF
	LD B,L				; B = bytes read (1..128)
	LD HL,FAT_CHUNK_BUF
	JR DPBI_BYTE_LOOP

DPBI_FAT_EOF:
	; Close FAT stream
	LD A,7				; VFS_CMD_CLOSE_FILE
	LD (VFS_REQ_CMD),A
	CALL VFS_EXEC_REQUEST
	JP DPBI_HIT_EOF
DPBI_BYTE_LOOP:
	PUSH BC
	PUSH HL
	LD A,(HL)

	; Check EOF markers (0 or 26 = ^Z)
	OR A
	JR Z,DPBI_POP_AND_EOF
	CP 26				; CP/M ^Z
	JR Z,DPBI_POP_AND_EOF

	; Check CR (13)
	CP 13
	JR Z,DPBI_HANDLE_CR

	; Check LF (10)
	CP 10
	JR Z,DPBI_HANDLE_LF

	; Regular character (including Tab 0x09)
	; If SEEN_CR was 1, we have a bare CR preceding this char!
	PUSH AF
	LD A,(SEEN_CR)
	OR A
	JR Z,DPBI_NO_BARE_CR
	XOR A
	LD (SEEN_CR),A
	CALL PBI_EMIT_LINE_BREAK
	JR C,DPBI_POP2_AND_EOF		; OOM on line break
DPBI_NO_BARE_CR:
	POP AF

	; Append character A to ACTIVE_LINE_BUF
	CALL PBI_APPEND_CHAR

DPBI_NEXT_BYTE:
	POP HL
	POP BC
	INC HL
	DJNZ DPBI_BYTE_LOOP
	JP DPBI_READ_SECTOR

DPBI_POP2_AND_EOF:
	POP AF
DPBI_POP_AND_EOF:
	POP HL
	POP BC
	JP DPBI_HIT_EOF

DPBI_HANDLE_CR:
	LD A,(SEEN_CR)
	OR A
	JR Z,DPBI_SET_CR
	CALL PBI_EMIT_LINE_BREAK
	JR C,DPBI_POP_AND_EOF
DPBI_SET_CR:
	LD A,1
	LD (SEEN_CR),A
	JR DPBI_NEXT_BYTE

DPBI_HANDLE_LF:
	XOR A
	LD (SEEN_CR),A
	CALL PBI_EMIT_LINE_BREAK
	JR C,DPBI_POP_AND_EOF
	JR DPBI_NEXT_BYTE

DPBI_HIT_EOF:
	; If SEEN_CR is still 1 at EOF (trailing bare CR), emit line break
	LD A,(SEEN_CR)
	OR A
	JR Z,DPBI_FINISH_EOF
	XOR A
	LD (SEEN_CR),A
	CALL PBI_EMIT_LINE_BREAK

DPBI_FINISH_EOF:
	; Final progress update for inserted file
	LD A,(INSERT_LINE_HAD_CHARS)
	OR A
	JR Z,DPBI_NO_FINAL_INC
	LD HL,(LOAD_PROGRESS_LINES)
	INC HL
	LD (LOAD_PROGRESS_LINES),HL
DPBI_NO_FINAL_INC:
	CALL UPDATE_LOAD_PROGRESS

	; Record cursor position (column right after inserted text)
	LD HL,(INSERT_CUR_LEN)
	LD (INSERT_NEW_CUR_COL),HL

	; Append SPLIT_LINE_TEMP (saved host line suffix) to ACTIVE_LINE_BUF
	LD DE,SPLIT_LINE_TEMP
DPBI_APPEND_SUFFIX:
	LD A,(DE)
	OR A
	JR Z,DPBI_SUFFIX_DONE
	CALL PBI_APPEND_CHAR
	INC DE
	JR DPBI_APPEND_SUFFIX

DPBI_SUFFIX_DONE:
	; Write final ACTIVE_LINE_BUF to CUR_DOC_ROW
	LD BC,(CUR_DOC_ROW)
	LD HL,ACTIVE_LINE_BUF
	CALL WRITE_FAR_LINE

	; Set cursor column
	LD HL,(INSERT_NEW_CUR_COL)
	LD (CUR_COL),HL
	LD (TARGET_COL),HL

	; Close INSERT_FCB (or FAT stream)
	LD A,(BLOCK_INSERT_IS_FAT)
	OR A
	JR NZ,DPBI_CLOSE_FAT
	LD DE,INSERT_FCB
	LD C,16				; BDOS Close File
	CALL BDOS_ENTRY
	JR DPBI_SKIP_FCB_CLOSE
DPBI_CLOSE_FAT:
	LD A,7				; VFS_CMD_CLOSE_FILE
	LD (VFS_REQ_CMD),A
	CALL VFS_EXEC_REQUEST
DPBI_SKIP_FCB_CLOSE:

	; Mark document modified
	LD A,1
	LD (DOC_MODIFIED),A

	; Invalidate active line and reload cache
	CALL INVALIDATE_ACTIVE_LINE
	CALL FLUSH_DIRTY_CACHE
	CALL RELOAD_CACHE_WINDOW_FORCE
	CALL CHECKOUT_ACTIVE_LINE
	CALL CALC_VISUAL_COL
	LD (TARGET_COL),HL

	; If inserted text is non-empty, solidify block around inserted text
	LD HL,(INSERT_ORIG_START_ROW)
	LD DE,(CUR_DOC_ROW)
	LD A,H
	CP D
	JR NZ,DPBI_SET_SOLID_BLOCK
	LD A,L
	CP E
	JR NZ,DPBI_SET_SOLID_BLOCK
	LD HL,(INSERT_ORIG_START_COL)
	LD DE,(INSERT_NEW_CUR_COL)
	LD A,H
	CP D
	JR NZ,DPBI_SET_SOLID_BLOCK
	LD A,L
	CP E
	JR Z,DPBI_NO_BLOCK	; Start == End: 0 bytes inserted, no block

DPBI_SET_SOLID_BLOCK:
	LD HL,(INSERT_ORIG_START_ROW)
	LD (BLOCK_START_ROW),HL
	LD (BLOCK_ANCHOR_ROW),HL
	LD HL,(INSERT_ORIG_START_COL)
	LD (BLOCK_START_COL),HL
	LD (BLOCK_ANCHOR_COL),HL
	LD HL,(CUR_DOC_ROW)
	LD (BLOCK_END_ROW),HL
	LD HL,(INSERT_NEW_CUR_COL)
	LD (BLOCK_END_COL),HL
	LD A,2
	LD (BLOCK_ACTIVE),A

DPBI_NO_BLOCK:
	; Adjust viewport (both vertical and horizontal)
	CALL ADJUST_INSERT_VIEWPORT
	RET

;------------------------------------------------------------------------------
; PBI_APPEND_CHAR: Append character to staging line buffer during block insert
;
; Purpose:
;   Stores character in A into temporary insert line staging buffer, checking
;   for line stride overflow and advancing character count.
;
; Call Usage / Protocol:
;   Called via CALL from DO_PERFORM_BLOCK_INSERT character streaming loop.
;
; Inputs:
;   A = Character to append.
;
; Outputs:
;   Character appended to buffer; length counter updated.
;
; Preserves / Modifies:
;   Clobbers AF; preserves BC, DE, HL.
;------------------------------------------------------------------------------
PBI_APPEND_CHAR:
	PUSH HL
	PUSH DE
	LD HL,(INSERT_CUR_LEN)
	LD DE,MAX_INPUT_LINE_CHARS - 1		; 999
	OR A
	SBC HL,DE
	JR NC,PAC_DONE				; If >= 999, ignore char
	LD HL,ACTIVE_LINE_BUF
	LD DE,(INSERT_CUR_LEN)
	ADD HL,DE
	LD (HL),A				; Store char
	INC HL
	LD (HL),0				; Maintain null terminator
	LD HL,(INSERT_CUR_LEN)
	INC HL
	LD (INSERT_CUR_LEN),HL
	LD A,1
	LD (INSERT_LINE_HAD_CHARS),A
PAC_DONE:
	POP DE
	POP HL
	RET

;------------------------------------------------------------------------------
; PBI_EMIT_LINE_BREAK: Commit staged line and insert new line in document
;
; Purpose:
;   Flushes accumulated staging line buffer to document line table at cursor
;   position, allocates new line in far RAM, increments document line count,
;   and advances insertion cursor row.
;
; Call Usage / Protocol:
;   Called via CALL from DO_PERFORM_BLOCK_INSERT upon encountering CRLF/LF.
;
; Inputs:
;   Staging line buffer populated.
;
; Outputs:
;   New line inserted into document; cursor row advanced.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
PBI_EMIT_LINE_BREAK:
	PUSH BC
	PUSH DE
	PUSH HL

	; Check max document lines
	LD HL,(DOC_TOTAL_LINES)
	LD DE,(MAX_DOC_LINES_LIMIT)
	OR A
	SBC HL,DE
	JP NC,PELB_OOM

	; Allocate slot for new line
	CALL ALLOC_SLOT			; HL = new_slot_id, Carry on OOM
	JP C,PELB_OOM
	PUSH HL				; Save new_slot_id

	; Write current line in ACTIVE_LINE_BUF to CUR_DOC_ROW
	LD BC,(CUR_DOC_ROW)
	LD HL,ACTIVE_LINE_BUF
	CALL WRITE_FAR_LINE

	; Shift line slots downwards from CUR_DOC_ROW + 1 to DOC_TOTAL_LINES - 1
	; Number of entries to shift: W = DOC_TOTAL_LINES - (CUR_DOC_ROW + 1)
	LD HL,(DOC_TOTAL_LINES)
	LD DE,(CUR_DOC_ROW)
	INC DE				; DE = P = CUR_DOC_ROW + 1
	AND A
	SBC HL,DE			; HL = W = DOC_TOTAL_LINES - P
	JR Z,PELB_NO_SHIFT
	JR C,PELB_NO_SHIFT

	LD B,H
	LD C,L				; BC = W
	LD HL,(CUR_DOC_ROW)
	INC HL				; HL = source line = CUR_DOC_ROW + 1
	LD DE,(CUR_DOC_ROW)
	INC DE
	INC DE				; DE = dest line = CUR_DOC_ROW + 2
	CALL SHIFT_LINE_SLOTS_DOWN

PELB_NO_SHIFT:
	; Store new_slot_id into line table at CUR_DOC_ROW + 1
	POP DE				; DE = new_slot_id
	LD HL,(CUR_DOC_ROW)
	INC HL
	LD B,H
	LD C,L				; BC = CUR_DOC_ROW + 1
	EX DE,HL			; HL = new_slot_id
	CALL SET_LINE_SLOT

	; Increment DOC_TOTAL_LINES
	LD HL,(DOC_TOTAL_LINES)
	INC HL
	LD (DOC_TOTAL_LINES),HL

	; Advance CUR_DOC_ROW
	LD HL,(CUR_DOC_ROW)
	INC HL
	LD (CUR_DOC_ROW),HL

	; Reset ACTIVE_LINE_BUF to empty
	XOR A
	LD (ACTIVE_LINE_BUF),A
	LD HL,0
	LD (INSERT_CUR_LEN),HL
	LD (INSERT_IS_FIRST_LINE),A
	LD (INSERT_LINE_HAD_CHARS),A

	; Increment LOAD_PROGRESS_LINES
	LD HL,(LOAD_PROGRESS_LINES)
	INC HL
	LD (LOAD_PROGRESS_LINES),HL

	; Check 100-line progress interval
	LD A,(LOAD_PROGRESS_COUNT)
	DEC A
	LD (LOAD_PROGRESS_COUNT),A
	JR NZ,PBIL_NO_TICK
	LD A,100
	LD (LOAD_PROGRESS_COUNT),A
	CALL UPDATE_LOAD_PROGRESS
PBIL_NO_TICK:

	POP HL
	POP DE
	POP BC
	OR A				; Carry = 0
	RET

PELB_OOM:
	CALL SET_OOM_STATUS
	POP HL
	POP DE
	POP BC
	SCF				; Carry = 1
	RET

;------------------------------------------------------------------------------
; ADJUST_INSERT_VIEWPORT: Re-align screen viewport following block insert
;
; Purpose:
;   Calculates new VIEWPORT_ROW and VIEWPORT_COL so that the cursor and newly
;   inserted text remain cleanly visible within the active editing window.
;
; Call Usage / Protocol:
;   Called via CALL after DO_PERFORM_BLOCK_INSERT finishes.
;
; Inputs:
;   ACTIVE_ROW, ACTIVE_COL.
;
; Outputs:
;   VIEWPORT_ROW, VIEWPORT_COL updated.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
ADJUST_INSERT_VIEWPORT:
	; Check if CUR_DOC_ROW < TOP_DOC_ROW
	LD HL,(CUR_DOC_ROW)
	LD DE,(TOP_DOC_ROW)
	CALL CMP_HL_DE			; Carry=1 if CUR_DOC_ROW < TOP_DOC_ROW
	JR NC,AIV_CHECK_BOTTOM
	LD HL,(CUR_DOC_ROW)
	LD (TOP_DOC_ROW),HL
	JR AIV_CHECK_HORIZ

AIV_CHECK_BOTTOM:
	; Check if CUR_DOC_ROW - TOP_DOC_ROW >= ACTIVE_ROWS - 2
	LD HL,(CUR_DOC_ROW)
	LD DE,(TOP_DOC_ROW)
	AND A
	SBC HL,DE
	LD A,H
	OR A
	JR NZ,AIV_DO_SCROLL_DOWN
	LD A,(ACTIVE_ROWS)
	DEC A
	DEC A
	CP L
	JR NC,AIV_CHECK_HORIZ
AIV_DO_SCROLL_DOWN:
	LD A,(ACTIVE_ROWS)
	DEC A
	DEC A
	LD E,A
	LD D,0
	LD HL,(CUR_DOC_ROW)
	AND A
	SBC HL,DE
	LD (TOP_DOC_ROW),HL

AIV_CHECK_HORIZ:
	CALL ADJUST_HORIZ_VIEWPORT
	RET

;------------------------------------------------------------------------------
; DO_SAVE_FILE_UI: Interactive Save / Save As modal dialog
;
; Purpose:
;   Displays modal dialog showing directory listing, provides prefilled
;   filename input box, prompts for confirmation before overwriting existing
;   files, and writes document lines to disk/RAM drive upon Enter.
;
; Call Usage / Protocol:
;   Called via CALL on Save File (Ctrl+S) or Save As (Ctrl+W).
;
; Inputs:
;   None.
;
; Outputs:
;   Document saved to disk, or cancelled if user presses Esc.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_SAVE_FILE_UI:
	LD A,(FILE_IS_TRUNCATED)
	OR A
	JR Z,DO_SAVE_FILE_OK
	CALL SHOW_FILE_TRUNCATED_POPUP
	RET

DO_SAVE_FILE_OK:
	; Invalidate active line and flush dirty cache before directory
	; collection
	; overlays LINE_STORAGE
	CALL INVALIDATE_ACTIVE_LINE
	CALL FLUSH_DIRTY_CACHE
	LD HL,0FFFFH
	LD (CACHE_START_ROW),HL

	LD A,1
	LD (IS_SAVE_UI),A
	CALL DO_SAVE_FILE_UI_IMPL
	XOR A
	LD (IS_SAVE_UI),A
	LD HL,0FFFFH
	LD (CACHE_START_ROW),HL
	RET

;------------------------------------------------------------------------------
; CHECK_FILE_TRUNCATED_POPUP: Warn user if lines exceed max stride before saving
;
; Purpose:
;   Checks HAS_TRUNCATED_LINES flag. If set, invokes SHOW_FILE_TRUNCATED_POPUP
;   to warn the user that saving will write truncated lines to disk.
;
; Call Usage / Protocol:
;   Called via CALL from DO_SAVE_FILE_UI before initiating save.
;
; Inputs:
;   HAS_TRUNCATED_LINES flag.
;
; Outputs:
;   Carry = 0 if safe to continue save; Carry = 1 if user cancelled.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
CHECK_FILE_TRUNCATED_POPUP:
	LD A,(FILE_IS_TRUNCATED)
	OR A
	RET Z

;------------------------------------------------------------------------------
; SHOW_FILE_TRUNCATED_POPUP: Display line truncation warning modal dialog
;
; Purpose:
;   Renders centered popup warning: "Document has truncated lines! Save anyway?
;   (Y/N)", waiting for user keypress to confirm or abort save operation.
;
; Call Usage / Protocol:
;   Called via CALL from CHECK_FILE_TRUNCATED_POPUP.
;
; Inputs:
;   None.
;
; Outputs:
;   Carry = 0 if user pressed 'Y'/'y'; Carry = 1 if user aborted ('N'/'n'/Esc).
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SHOW_FILE_TRUNCATED_POPUP:
	LD DE,STR_POPUP_TRUNC_TITLE
	LD HL,STR_POPUP_TRUNC_MSG1
	LD BC,STR_POPUP_TRUNC_MSG2
	JP SHOW_STATUS_EVENT_POPUP


;------------------------------------------------------------------------------
; DO_SAVE_FILE_UI_IMPL: Main implementation loop for Save File dialog
;
; Purpose:
;   Collects directory entries, initializes layout geometry, displays directory
;   page and Save prompt, preloads current filename, and runs input loop.
;
; Call Usage / Protocol:
;   Called via CALL or JP from DO_SAVE_FILE_UI.
;
; Inputs:
;   None.
;
; Outputs:
;   None.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_SAVE_FILE_UI_IMPL:
	; Initialize directory layout parameters based on active screen mode
	CALL INIT_DIR_LAYOUT

	; Initialize active directory drive from default disk or WORK_FCB
	CALL INIT_DIR_DRIVE

	; Filter defaults to all files shown unless explicitly provided in edit
	; box
	CALL RESET_DIR_FILTER

	; Initialize directory user area from current document user area
	LD A,(DOC_USER_NUM)
	LD (CURRENT_DIR_USER),A

	; Pre-fill filename if known (HAS_FILE_ARG == 1) and not Block Save
	LD A,(IS_BLOCK_SAVE_UI)
	OR A
	JR NZ,DSUI_EMPTY_BUF
	LD A,(HAS_FILE_ARG)
	OR A
	JR Z,DSUI_EMPTY_BUF
	LD A,(DOC_IS_FAT)
	OR A
	JR NZ,DSUI_PREFILL_FAT_FILE
	CALL FCB_TO_FILENAME_STR

	; Check if prefilled string explicitly contains a user area
	LD HL,INPUT_FILENAME_BUF
	CALL PARSE_DRIVE_USER_PREFIX
	JR NC,DSUI_PREFILL_DONE
	LD A,(PREFIX_USER)
	CP 0FFH
	JR Z,DSUI_PREFILL_DONE
	LD (CURRENT_DIR_USER),A
	JR DSUI_PREFILL_DONE

DSUI_EMPTY_BUF:
	CALL PRELOAD_DRIVE_USER_PREFIX
	JR DSUI_PREFILL_DONE

DSUI_PREFILL_FAT_FILE:
	CALL PREFILL_FAT_FILENAME_BUF

DSUI_PREFILL_DONE:

REFRESH_SAVE_DIR:
	; 1. Collect Directory Entries from CURRENT_DIR_DRIVE
	CALL COLLECT_DIR_ENTRIES

	; 2. Sort Directory Entries Alphabetically
	CALL SORT_DIR_ENTRIES

	; 3. Calculate Total Pages (using dynamic DIR_PAGE_CAPACITY)
	CALL CALC_DIR_PAGES

RENDER_SAVE_PAGE:
	CALL TERM_INIT
	LD A,1
	LD (IS_SPLASH_SCREEN),A
	CALL RENDER_SAVE_TITLE

	; Display Directory Entries for Current Page
	CALL DISPLAY_DIR_PAGE

	; Display Save Prompt & Page Indicator
	CALL DISPLAY_SAVE_PROMPT

	; Finish prompt line and fill remaining rows down to status row with '~'
	CALL FINISH_UI_PAGE_AND_STATUS

	; Read Filename Input (with prefilled string echoed)
	CALL READ_FILENAME_INPUT_PREFILLED
	JP C,CHECK_SAVE_PAGING_OR_CANCEL

	; Check if user typed a FAT specification (U: or U<unit>:)
	CALL CHECK_FAT_INPUT_SAVE
	JR NC,CFIS_DISPATCH_CHECK
	CALL SHOW_POPUP_FAT_NO_PLUGIN
	JP RENDER_SAVE_PAGE
CFIS_DISPATCH_CHECK:
	JP NZ,HANDLE_SAVE_FAT_DISPATCH

	; Check if user typed a drive specification (e.g. "A:")
	CALL CHECK_DRIVE_SWITCH
	JP C,HANDLE_SAVE_DRIVE_SWITCH

	; Check if user typed a filter pattern (e.g. "*.TXT" or "B:*.TXT")
	CALL CHECK_FILTER_PATTERN
	JP C,HANDLE_SAVE_FILTER

	; If currently browsing a FAT volume, handle relative navigation/save
	LD A,(CURRENT_DIR_IS_FAT)
	OR A
	JP NZ,HANDLE_SAVE_FAT_RELATIVE

DO_PARSE_AND_SAVE:
	; User entered/confirmed a filename in INPUT_FILENAME_BUF:
	; Save current WORK_FCB to DIR_TEMP_FCB (36 bytes)
	LD HL,WORK_FCB
	LD DE,DIR_TEMP_FCB
	LD BC,36
	LDIR

	; Parse entered filename into WORK_FCB
	CALL PARSE_FILENAME_TO_FCB

	; Check if target drive is unavailable RAM drive
	LD A,(WORK_FCB)
	CALL CHECK_TARGET_DRIVE_UNAVAILABLE
	JP C,SAVE_RAMDRV_UNAVAILABLE

	; Check if file already exists on disk
	CALL CHECK_FILE_EXISTS
	JR NC,DO_ACTUAL_SAVE		; Does not exist -> save directly

	; File already exists! Render Tier 2 centered modal warning popup
	CALL DRAW_OVERWRITE_POPUP

OVERWRITE_KEY_LOOP:
	CALL GET_KEY
	CP 'y'
	JR Z,DO_OVERWRITE_CONFIRMED
	CP 'Y'
	JR Z,DO_OVERWRITE_CONFIRMED

	CP 'n'
	JR Z,DO_OVERWRITE_CANCELLED
	CP 'N'
	JR Z,DO_OVERWRITE_CANCELLED

	CP KEY_ESC
	JR Z,OVERWRITE_CHECK_ESC

	JR OVERWRITE_KEY_LOOP

OVERWRITE_CHECK_ESC:
	LD BC,ESC_TIMEOUT_LOOPS
OW_WAIT_ESC:
	CALL CHECK_KEY_READY
	JR NZ,OW_DRAIN_ESC
	DEC BC
	LD A,B
	OR C
	JR NZ,OW_WAIT_ESC
	; Standalone ESC key: cancel
	JR DO_OVERWRITE_CANCELLED

OW_DRAIN_ESC:
	CALL GET_KEY			; Consume '[' or 'O'
OW_DRAIN_MORE:
	LD BC,500
OW_DRAIN_WAIT:
	CALL CHECK_KEY_READY
	JR NZ,OW_DRAIN_BYTE
	DEC BC
	LD A,B
	OR C
	JR NZ,OW_DRAIN_WAIT
	; Sequence drained: reposition cursor and resume key loop
	LD A,(POPUP_START_ROW)
	ADD A,4
	LD H,A
	LD A,(POPUP_COL)
	ADD A,40
	LD L,A
	CALL LOCATE_RC
	JR OVERWRITE_KEY_LOOP

OW_DRAIN_BYTE:
	CALL GET_KEY
	JR OW_DRAIN_MORE

DO_OVERWRITE_CANCELLED:
	CALL RESTORE_WORK_FCB_FROM_TEMP
	CALL RESTORE_DOC_USER
	RET

DO_OVERWRITE_CONFIRMED:

;------------------------------------------------------------------------------
; DO_ACTUAL_SAVE: Verify overwrite permission and execute file save
;
; Purpose:
;   Checks if target file exists on destination drive/user. If it exists and
;   differs from original document file, prompts with DRAW_OVERWRITE_POPUP;
;   on confirmation, executes SAVE_FILE.
;
; Call Usage / Protocol:
;   Called via CALL or JP when filename is confirmed in Save File UI.
;
; Inputs:
;   WORK_FCB = Target file FCB.
;
; Outputs:
;   File written to disk; returns to editor.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DO_ACTUAL_SAVE:
	LD A,(IS_BLOCK_SAVE_UI)
	OR A
	JR NZ,DO_ACTUAL_BLOCK_SAVE

	; Save the file from Far RAM to disk
	CALL SAVE_FILE
	RET C			; Save failed / target hibernated -> return

	; Mark filename as known and saved
	LD A,1
	LD (HAS_FILE_ARG),A
	XOR A
	LD (DOC_MODIFIED),A
	LD (DOC_IS_FAT),A
	RET

DO_ACTUAL_BLOCK_SAVE:
	CALL SAVE_BLOCK_FILE
	JP RESTORE_WORK_FCB_FROM_TEMP

;------------------------------------------------------------------------------
; DRAW_OVERWRITE_POPUP: Display overwrite confirmation modal dialog
;
; Purpose:
;   Displays modal warning box: "File exists! Overwrite? (Y/N)", waiting for
;   user confirmation before replacing existing file on disk.
;
; Call Usage / Protocol:
;   Called via CALL from DO_ACTUAL_SAVE when target file already exists.
;
; Inputs:
;   None.
;
; Outputs:
;   Carry = 0 if confirmed ('Y'/'y'); Carry = 1 if aborted ('N'/'n'/Esc).
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DRAW_OVERWRITE_POPUP:
	; 1. Calculate POPUP_COL = ((ACTIVE_COLS - 50) / 2) + 1
	LD A,(ACTIVE_COLS)
	SUB 50
	SRL A
	INC A
	LD (POPUP_COL),A

	; 2. Calculate POPUP_ROW = ((ACTIVE_ROWS - 7) / 2) + 1
	LD A,(ACTIVE_ROWS)
	SUB 7
	SRL A
	INC A
	LD (POPUP_ROW),A
	LD (POPUP_START_ROW),A

	; 3. Render 7-line Pop-Up Box
	CALL POPUP_PRINT_BORDER

	CALL POPUP_LOCATE_NEXT
	LD DE,STR_OVERWRITE_POPUP_TITLE
	CALL PRINT_STR

	CALL POPUP_PRINT_BORDER

	CALL POPUP_LOCATE_NEXT
	LD DE,STR_OVERWRITE_POPUP_MSG1
	CALL PRINT_STR

	CALL POPUP_LOCATE_NEXT
	LD DE,STR_OVERWRITE_POPUP_MSG2
	CALL PRINT_STR

	CALL POPUP_LOCATE_NEXT
	LD DE,STR_POPUP_SAVE_KEYS
	CALL PRINT_STR

	CALL POPUP_PRINT_BORDER

	; Position cursor inside popup on prompt line after "Overwrite? "
	; Row = POPUP_START_ROW + 4, Col = POPUP_COL + 40
	LD A,(POPUP_START_ROW)
	ADD A,4
	LD H,A
	LD A,(POPUP_COL)
	ADD A,40
	LD L,A
	CALL LOCATE_RC
	CALL TERM_SHOW_CURSOR
	RET

SAVE_RAMDRV_UNAVAILABLE:
	CALL RESTORE_WORK_FCB_FROM_TEMP
	CALL SHOW_POPUP_RAMDRV_UNAVAIL
	JP RENDER_SAVE_PAGE

HANDLE_SAVE_DRIVE_SWITCH:
	; A = new drive (1..16 or 0), C = new user (0..15 or 0xFF)
	PUSH BC				; Save target user
	OR A
	JR Z,HSDS_DRIVE_DONE		; Drive unchanged

	CALL CHECK_TARGET_DRIVE_UNAVAILABLE
	JR NC,HSDS_DRIVE_OK

	; Cannot switch to unavailable RAM drive!
	POP BC
	JR SAVE_RAMDRV_UNAVAILABLE

HSDS_DRIVE_OK:
	LD (CURRENT_DIR_DRIVE),A
	ADD A,'A'-1
	LD (STR_SAVE_DRIVE_CHAR),A
	XOR A
	LD (CURRENT_DIR_IS_FAT),A

HSDS_DRIVE_DONE:
	POP BC				; C = target user
	LD A,C
	CP 0FFH
	JR Z,HSDS_USER_DEFAULT_ZERO
	LD (CURRENT_DIR_USER),A
	JR HSDS_RESET_FILTER
HSDS_USER_DEFAULT_ZERO:
	XOR A
	LD (CURRENT_DIR_USER),A

HSDS_RESET_FILTER:
	; A drive/user switch without wildcard defaults to all files shown
	CALL RESET_DIR_FILTER
	JP REFRESH_SAVE_DIR

HANDLE_SAVE_FILTER:
	JP REFRESH_SAVE_DIR

CHECK_SAVE_PAGING_OR_CANCEL:
	; A = return code: 0 = Cancel (ESC), 1 = Next Page (PgDn), 2 = Format
	; Toggled (Ctrl-F), 3 = Prev Page (PgUp)
	CP 2
	; Redraw save page with new format and prefilled input
	JP Z,RENDER_SAVE_PAGE
	CP 1
	JR Z,DO_SAVE_NEXT_PAGE
	CP 3
	JR Z,DO_SAVE_PREV_PAGE
	CALL RESTORE_DOC_USER
	RET				; Cancelled -> return

DO_SAVE_PREV_PAGE:
	LD A,(DIR_PAGE_INDEX)
	OR A
	JR Z,DO_SAVE_PREV_WRAP
	DEC A
	JR SET_SAVE_NEXT_PAGE
DO_SAVE_PREV_WRAP:
	LD A,(DIR_PAGE_COUNT)
	DEC A
	JR SET_SAVE_NEXT_PAGE

DO_SAVE_NEXT_PAGE:
	LD A,(DIR_PAGE_INDEX)
	INC A
	LD HL,DIR_PAGE_COUNT
	CP (HL)
	JR C,SET_SAVE_NEXT_PAGE
	XOR A				; Wrap around to page 0
SET_SAVE_NEXT_PAGE:
	LD (DIR_PAGE_INDEX),A
	JP RENDER_SAVE_PAGE

;------------------------------------------------------------------------------
; CHECK_FILE_EXISTS: Test if target FCB exists on disk via BDOS Search First
;
; Purpose:
;   Invokes BDOS Search First (function 17) for candidate FCB pointed to by DE.
;   Returns Carry = 0 if directory entry found (0..3), Carry = 1 if not found.
;
; Call Usage / Protocol:
;   Called via CALL before opening or saving files to verify existence.
;
; Inputs:
;   DE = Pointer to target FCB.
;
; Outputs:
;   Carry = 0 if file exists; Carry = 1 if file does not exist.
;
; Preserves / Modifies:
;   Clobbers AF, DE; preserves BC, HL.
;------------------------------------------------------------------------------
CHECK_FILE_EXISTS:
	; Set BDOS user area to WORK_FCB_USER before probing
	LD A,(WORK_FCB_USER)
	LD E,A
	LD C,32				; BDOS Set User Area
	CALL BDOS_ENTRY

	; Set DMA address to RAW_SECTOR_BUF
	LD DE,RAW_SECTOR_BUF
	LD C,26				; BDOS Set DMA
	CALL BDOS_ENTRY

	; Copy WORK_FCB to RAW_TEST_FCB
	LD HL,WORK_FCB
	LD DE,RAW_TEST_FCB
	LD BC,36
	LDIR

	; Clear extent and record bytes (bytes 12..35) in RAW_TEST_FCB
	LD HL,RAW_TEST_FCB+12
	LD (HL),0
	LD DE,RAW_TEST_FCB+13
	LD BC,23
	LDIR

	; Try to open file (BDOS 15)
	LD DE,RAW_TEST_FCB
	LD C,15
	CALL BDOS_ENTRY
	CP 0FFH
	JR Z,FILE_NOT_EXISTS

	; File exists! Close it (BDOS 16)
	LD DE,RAW_TEST_FCB
	LD C,16
	CALL BDOS_ENTRY

	; Restore BDOS user area to CURRENT_DIR_USER
	LD A,(CURRENT_DIR_USER)
	LD E,A
	LD C,32				; BDOS Set User Area
	CALL BDOS_ENTRY

	SCF				; Carry = 1 (file exists)
	RET

FILE_NOT_EXISTS:
	; Restore BDOS user area to CURRENT_DIR_USER
	LD A,(CURRENT_DIR_USER)
	LD E,A
	LD C,32				; BDOS Set User Area
	CALL BDOS_ENTRY

	OR A				; Carry = 0 (file does not exist)
	RET

;------------------------------------------------------------------------------
; INIT_DIR_LAYOUT: Calculate directory modal geometry from terminal dimensions
;
; Purpose:
;   Calculates number of directory rows, columns per row, column width, and top
;   vertical padding based on ACTIVE_ROWS and ACTIVE_COLS terminal dimensions.
;
; Call Usage / Protocol:
;   Called via CALL prior to rendering directory browser page.
;
; Inputs:
;   ACTIVE_ROWS, ACTIVE_COLS.
;
; Outputs:
;   DIR_BODY_ROWS, DIR_COLS_PER_ROW, DIR_COL_WIDTH, DIR_TOP_PAD configured.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
INIT_DIR_LAYOUT:
	LD A,(SCREEN_MODE)
	CP MODE_120X40
	JR Z,IDL_120
	; 80x24 mode
	LD A,5
	LD (DIR_COLS_PER_ROW),A
	LD A,15
	LD (DIR_COL_WIDTH),A
	LD A,60
	LD (DIR_PAGE_CAPACITY),A
	LD A,2
	LD (DIR_LEFT_PAD),A
	RET
IDL_120:
	; 120x40 mode
	LD A,7
	LD (DIR_COLS_PER_ROW),A
	LD A,16
	LD (DIR_COL_WIDTH),A
	LD A,196
	LD (DIR_PAGE_CAPACITY),A
	LD A,3
	LD (DIR_LEFT_PAD),A
	RET

;------------------------------------------------------------------------------
; PRINT_HR_EQUAL: Print full-width horizontal rule with '=' characters
;
; Purpose:
;   Emits '~' followed by (ACTIVE_COLS - 2) '=' characters and a CRLF sequence
;   to draw outer borders of modal dialog boxes.
;
; Call Usage / Protocol:
;   Called via CALL during modal dialog rendering.
;
; Inputs:
;   ACTIVE_COLS.
;
; Outputs:
;   Border rule emitted to terminal.
;
; Preserves / Modifies:
;   Clobbers AF, B.
;------------------------------------------------------------------------------
PRINT_HR_EQUAL:
	LD A,'~'
	CALL PUTC
	LD A,(ACTIVE_COLS)
	SUB 2
	LD B,A
PHE_LOOP:
	LD A,'='
	CALL PUTC
	DJNZ PHE_LOOP
	CALL PRINT_CRLF
	RET

;------------------------------------------------------------------------------
; PRINT_HR_DASH: Print full-width horizontal rule with '-' characters
;
; Purpose:
;   Emits '~' followed by (ACTIVE_COLS - 2) '-' characters and a CRLF sequence
;   to draw internal section dividers in modal dialog boxes.
;
; Call Usage / Protocol:
;   Called via CALL during modal dialog rendering.
;
; Inputs:
;   ACTIVE_COLS.
;
; Outputs:
;   Divider rule emitted to terminal.
;
; Preserves / Modifies:
;   Clobbers AF, B.
;------------------------------------------------------------------------------
PRINT_HR_DASH:
	LD A,'~'
	CALL PUTC
	LD A,(ACTIVE_COLS)
	SUB 2
	LD B,A
PHD_LOOP:
	LD A,'-'
	CALL PUTC
	DJNZ PHD_LOOP
	CALL PRINT_CRLF
	RET

;------------------------------------------------------------------------------
; PRINT_DIR_PREFIX: Print directory line prefix and optional left margin padding
;
; Purpose:
;   Emits "~ " prefix at the beginning of each directory body line to maintain
;   dialog border alignment.
;
; Call Usage / Protocol:
;   Called via CALL at the start of each directory row.
;
; Inputs:
;   None.
;
; Outputs:
;   Prefix emitted to terminal.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
PRINT_DIR_PREFIX:
	PUSH AF
	PUSH BC
	LD A,'~'
	CALL PUTC
	LD A,(DIR_LEFT_PAD)
	OR A
	JR Z,PDP_DONE
	LD B,A
PDP_LOOP:
	LD A,' '
	CALL PUTC
	DJNZ PDP_LOOP
PDP_DONE:
	POP BC
	POP AF
	RET

;------------------------------------------------------------------------------
; CALC_DIR_START_FILE: Compute first file index for current directory page
;
; Purpose:
;   Multiplies DIR_PAGE_NUM by files per page to determine starting file index
;   in DIR_NAMES_BUF for the active page display.
;
; Call Usage / Protocol:
;   Called via CALL before rendering directory entries.
;
; Inputs:
;   DIR_PAGE_NUM, DIR_BODY_ROWS, DIR_COLS_PER_ROW.
;
; Outputs:
;   HL = Index of first file on page (0-based).
;
; Preserves / Modifies:
;   Clobbers AF, BC, HL; preserves DE.
;------------------------------------------------------------------------------
CALC_DIR_START_FILE:
	PUSH BC
	LD A,(DIR_PAGE_INDEX)
	OR A
	JR Z,CDSF_ZERO
	LD B,A
	LD A,(DIR_PAGE_CAPACITY)
	LD C,A
	XOR A
CDSF_LOOP:
	ADD A,C
	DJNZ CDSF_LOOP
CDSF_ZERO:
	LD (DIR_START_FILE),A
	POP BC
	RET

;------------------------------------------------------------------------------
; CALC_DIR_BODY_ROWS: Determine available body rows for directory listing
;
; Purpose:
;   Subtracts fixed header, prompt, and border rows from ACTIVE_ROWS to compute
;   maximum vertical lines available for directory entries.
;
; Call Usage / Protocol:
;   Called via CALL from INIT_DIR_LAYOUT.
;
; Inputs:
;   ACTIVE_ROWS.
;
; Outputs:
;   A = Number of directory body rows.
;
; Preserves / Modifies:
;   Clobbers AF, B; preserves DE, HL.
;------------------------------------------------------------------------------
CALC_DIR_BODY_ROWS:
	CALL CALC_DIR_START_FILE

	; 1. Calculate file_rows
	LD A,(DIR_FILE_COUNT)
	OR A
	JR NZ,CDBR_HAS_FILES
	; Zero files: 2 rows (STR_NO_FILES_FOUND + blank tilde)
	LD B,2
	JR CDBR_CALC_PROMPT

CDBR_HAS_FILES:
	; Files on page = min(DIR_PAGE_CAPACITY, DIR_FILE_COUNT -
	; DIR_START_FILE)
	LD HL,DIR_START_FILE
	SUB (HL)
	LD HL,DIR_PAGE_CAPACITY
	CP (HL)
	JR C,CDBR_PAGE_FILES_OK
	LD A,(HL)
CDBR_PAGE_FILES_OK:
	; A = files on page (> 0)
	; file_rows = ((A + DIR_COLS_PER_ROW - 1) / DIR_COLS_PER_ROW) + 1
	LD HL,DIR_COLS_PER_ROW
	LD C,(HL)
	DEC C
	ADD A,C				; A = files + cols - 1
	LD B,0				; Quotient (row count)
	LD C,(HL)
CDBR_DIV_LOOP:
	SUB C
	JR C,CDBR_DIV_DONE
	INC B
	JR CDBR_DIV_LOOP
CDBR_DIV_DONE:
	INC B				; Plus 1 for trailing blank tilde

CDBR_CALC_PROMPT:
	; B = file_rows
	; Base prompt rows = 3
	LD C,3
	LD A,(DIR_PAGE_COUNT)
	CP 2
	JR C,CDBR_CHECK_SAVE
	INC C				; Multi-page: +1 row
CDBR_CHECK_SAVE:
	LD A,(IS_SAVE_UI)
	OR A
	JR Z,CDBR_PROMPT_DONE
	INC C				; Save format info: +1 row
CDBR_PROMPT_DONE:
	LD A,B				; A = file_rows
	ADD A,C				; A = file_rows + prompt_rows
	RET

;------------------------------------------------------------------------------
; CALC_DIR_TOP_PAD: Calculate top vertical padding to center modal dialog
;
; Purpose:
;   Computes number of blank lines to emit before modal box top border so the
;   dialog is vertically centered on the terminal screen.
;
; Call Usage / Protocol:
;   Called via CALL from INIT_DIR_LAYOUT.
;
; Inputs:
;   ACTIVE_ROWS, DIR_BODY_ROWS.
;
; Outputs:
;   A = Number of blank padding lines.
;
; Preserves / Modifies:
;   Clobbers AF, B; preserves DE, HL.
;------------------------------------------------------------------------------
CALC_DIR_TOP_PAD:
	CALL CALC_DIR_BODY_ROWS		; A = BodyRows
	LD B,A				; B = BodyRows
	LD A,(ACTIVE_ROWS)
	SUB 4				; A = TOTAL_AVAIL
	SUB B				; A = TOTAL_AVAIL - BodyRows
	JR Z,CDTP_ZERO
	JR C,CDTP_ZERO
	SRL A				; A = EXTRA / 2
	LD (DIR_TOP_PAD_COUNT),A
	RET
CDTP_ZERO:
	XOR A
	LD (DIR_TOP_PAD_COUNT),A
	RET

;------------------------------------------------------------------------------
; RENDER_DIR_TITLE: Render title bar for Open File modal dialog
;
; Purpose:
;   Emits title header line: "~  Open File: <Drive><User>: [<Filter>]"
;   with active drive letter, user area, and wildcard filter pattern.
;
; Call Usage / Protocol:
;   Called via CALL from RENDER_OPEN_PAGE.
;
; Inputs:
;   DIR_DRIVE, DIR_USER, DIR_FILTER_BUF.
;
; Outputs:
;   Title header line printed to terminal.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
RENDER_DIR_TITLE:
	LD A,(IS_BLOCK_INSERT_UI)
	OR A
	JR NZ,RDT_IS_INSERT
	LD A,(IS_PLUGIN_LOAD_UI)
	OR A
	JR NZ,RDT_IS_PLUGIN
	LD DE,STR_TITLE_OPEN_PRE
	LD A,(STR_DIR_DRIVE_CHAR)
	JR RENDER_TITLE_COMMON
RDT_IS_INSERT:
	LD DE,STR_TITLE_INSERT_PRE
	LD A,(STR_DIR_DRIVE_CHAR)
	JR RENDER_TITLE_COMMON
RDT_IS_PLUGIN:
	LD DE,STR_TITLE_PLUG_LOAD_PRE
	LD A,(STR_DIR_DRIVE_CHAR)
	JR RENDER_TITLE_COMMON

;------------------------------------------------------------------------------
; RENDER_SAVE_TITLE: Render title bar for Save File modal dialog
;
; Purpose:
;   Emits title header line: "~  Save File: <Drive><User>: [<Filter>]"
;   with active drive letter, user area, and wildcard filter pattern.
;
; Call Usage / Protocol:
;   Called via CALL from RENDER_SAVE_PAGE.
;
; Inputs:
;   DIR_DRIVE, DIR_USER, DIR_FILTER_BUF.
;
; Outputs:
;   Title header line printed to terminal.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
RENDER_SAVE_TITLE:
	LD A,(IS_BLOCK_SAVE_UI)
	OR A
	JR Z,RST_NORMAL
	LD DE,STR_TITLE_BLOCK_SAVE_PRE
	LD A,(STR_SAVE_DRIVE_CHAR)
	JR RENDER_TITLE_COMMON
RST_NORMAL:
	LD DE,STR_TITLE_SAVE_PRE
	LD A,(STR_SAVE_DRIVE_CHAR)

RENDER_TITLE_COMMON:
	PUSH AF
	PUSH DE

	; 1. Clear Screen (ESC [ 2 J, ESC [ H)
	CALL TERM_CLEAR_SCREEN

	; Calculate vertical top padding for directory/file screen
	CALL CALC_DIR_TOP_PAD

	; 2. Print top margin blank tilde rows before title block (if any)
	LD A,(DIR_TOP_PAD_COUNT)
	OR A
	JR Z,RTC_TOP_PAD_DONE
	LD B,A
RTC_TOP_PAD_LOOP:
	CALL PRINT_TILDE_CRLF
	DJNZ RTC_TOP_PAD_LOOP
RTC_TOP_PAD_DONE:

	; 3. Row DIR_TOP_PAD_COUNT + 1: Horizontal Rule
	CALL PRINT_HR_EQUAL

	; 3. Row 2: Centered Title
	; Title length: 34 if IS_BLOCK_INSERT_UI or IS_PLUGIN_LOAD_UI,
	; 33 if IS_BLOCK_SAVE_UI, 32 otherwise
	LD A,(IS_BLOCK_INSERT_UI)
	OR A
	LD A,34
	JR NZ,RTC_BASE_LEN_OK
	LD A,(IS_PLUGIN_LOAD_UI)
	OR A
	LD A,34
	JR NZ,RTC_BASE_LEN_OK
	LD A,(IS_BLOCK_SAVE_UI)
	OR A
	LD A,33
	JR NZ,RTC_BASE_LEN_OK
	LD A,32
RTC_BASE_LEN_OK:
	LD B,A

	; Check if CURRENT_DIR_IS_FAT == 1
	LD A,(CURRENT_DIR_IS_FAT)
	OR A
	JR Z,RTC_CALC_CPM_USER_LEN
	LD A,(CURRENT_DIR_FAT_UNIT)
	CP 0FFH
	JR Z,RTC_CALC_FAT_PATH_LEN
	INC B				; 1 digit for unit 0..7

RTC_CALC_FAT_PATH_LEN:
	; Calculate length of CURRENT_DIR_FAT_PATH
	; Colon ':' is already counted in base title length (B=41)
	; Plus length of path, plus 1 if trailing '/' needs to be added
	PUSH BC
	LD HL,CURRENT_DIR_FAT_PATH
	LD C,0
RTC_PLEN_LOOP:
	LD A,(HL)
	OR A
	JR Z,RTC_PLEN_DONE
	INC C
	INC HL
	JR RTC_PLEN_LOOP
RTC_PLEN_DONE:
	LD A,C
	OR A
	JR Z,RTC_PLEN_EMPTY
	DEC HL
	LD A,(HL)
	CP '/'
	JR Z,RTC_PLEN_FIN		; Already ends with '/'
	INC C				; Extra 1 char for trailing '/'
	JR RTC_PLEN_FIN
RTC_PLEN_EMPTY:
	INC C				; Empty path will print '/'
RTC_PLEN_FIN:
	POP BC
	LD A,B
	ADD A,C
	LD B,A
	JR RTC_CHECK_FILTER_LEN

RTC_CALC_CPM_USER_LEN:
	; Check if CURRENT_DIR_USER > 0: add 1 or 2 to title length
	LD A,(CURRENT_DIR_USER)
	OR A
	JR Z,RTC_CHECK_FILTER_LEN
	CP 10
	JR C,RTC_U_LEN_1
	INC B				; 2 digits (10..15): +2 chars
RTC_U_LEN_1:
	INC B				; 1 digit (1..9): +1 char

RTC_CHECK_FILTER_LEN:
	; Check if custom filter is active
	LD A,(DIR_FILTER_ACTIVE)
	OR A
	JR Z,RTC_CALC_PAD

	; Calculate extra length: length of DIR_FILTER_STR + 3
	PUSH BC
	LD HL,DIR_FILTER_STR
	LD C,3
RTC_FSTR_LEN_LOOP:
	LD A,(HL)
	OR A
	JR Z,RTC_FSTR_LEN_DONE
	INC C
	INC HL
	JR RTC_FSTR_LEN_LOOP
RTC_FSTR_LEN_DONE:
	POP BC
	LD A,B
	ADD A,C
	LD B,A

RTC_CALC_PAD:
	LD A,'~'
	CALL PUTC
	LD A,(ACTIVE_COLS)
	SUB B
	JR C,RTC_NO_PAD
	SRL A
	JR Z,RTC_NO_PAD
	DEC A
	JR Z,RTC_NO_PAD
	LD B,A
RTC_PAD_LOOP:
	LD A,' '
	CALL PUTC
	DJNZ RTC_PAD_LOOP
RTC_NO_PAD:

	POP DE
	CALL PRINT_STR
	POP AF
	CALL PUTC

	; If FAT mode, print unit digit; if CP/M mode and user > 0, print user
	; digits
	LD A,(CURRENT_DIR_IS_FAT)
	OR A
	JR NZ,RTC_PRINT_FAT_UNIT

	LD A,(CURRENT_DIR_USER)
	OR A
	JR Z,RTC_USER_DONE
	CP 10
	JR C,RTC_PRINT_U_1DIGIT
	PUSH AF
	LD A,'1'
	CALL PUTC
	POP AF
	SUB 10
RTC_PRINT_U_1DIGIT:
	ADD A,'0'
	CALL PUTC
	JR RTC_USER_DONE

RTC_PRINT_FAT_UNIT:
	LD A,(CURRENT_DIR_FAT_UNIT)
	CP 0FFH
	JR Z,RTC_FAT_UNIT_DONE
	ADD A,'0'
	CALL PUTC

RTC_FAT_UNIT_DONE:
	; FAT mode suffix: print ':', path, optional trailing '/', then filter
	; or ')'
	LD A,':'
	CALL PUTC

	LD HL,CURRENT_DIR_FAT_PATH
	CALL PRINT_FAT_TITLE_PATH

	LD A,(DIR_FILTER_ACTIVE)
	OR A
	JR NZ,RTC_PRINT_FILTERED

	LD DE,STR_TITLE_PAREN_CRLF
	CALL PRINT_STR
	JR RTC_TITLE_DONE

RTC_USER_DONE:
	LD A,(DIR_FILTER_ACTIVE)
	OR A
	JR NZ,RTC_PRINT_FILTERED

	LD DE,STR_TITLE_DRIVE_SUF
	CALL PRINT_STR
	JR RTC_TITLE_DONE

RTC_PRINT_FILTERED:
	LD DE,STR_TITLE_FILTER_PRE	; ": ["
	CALL PRINT_STR
	LD DE,DIR_FILTER_STR
	CALL PRINT_STR
	LD DE,STR_TITLE_FILTER_SUF	; "])", 13, 10
	CALL PRINT_STR

RTC_TITLE_DONE:

	; Row DIR_TOP_PAD_COUNT + 3: Horizontal Rule
	CALL PRINT_HR_EQUAL

	; Initialize UI_CUR_ROW = 3 + DIR_TOP_PAD_COUNT
	LD A,(DIR_TOP_PAD_COUNT)
	ADD A,3
	LD (UI_CUR_ROW),A
	RET

;------------------------------------------------------------------------------
; PRINT_FAT_TITLE_PATH: Print FAT filesystem path in modal dialog title
;
; Purpose:
;   Emits FAT volume letter and current directory path string when browsing
;   a mounted RomWBW FAT filesystem volume.
;
; Call Usage / Protocol:
;   Called via CALL from RENDER_DIR_TITLE and RENDER_SAVE_TITLE.
;
; Inputs:
;   None.
;
; Outputs:
;   FAT path string printed to terminal.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
PRINT_FAT_TITLE_PATH:
	LD C,0				; Tracks last character printed
PFTP_LOOP:
	LD A,(HL)
	OR A
	JR Z,PFTP_DONE
	CALL PUTC
	LD C,A
	INC HL
	JR PFTP_LOOP
PFTP_DONE:
	LD A,C
	CP '/'
	RET Z				; Already ended with '/'
	LD A,'/'
	CALL PUTC
	RET

;------------------------------------------------------------------------------
; INIT_DIR_DRIVE: Initialize directory browser drive and user area
;
; Purpose:
;   Sets DIR_DRIVE and DIR_USER to match the current document's drive and user
;   area, or default CP/M logged drive/user if no file is open.
;
; Call Usage / Protocol:
;   Called via CALL at commencement of Open or Save file dialogs.
;
; Inputs:
;   None.
;
; Outputs:
;   DIR_DRIVE, DIR_USER initialized.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
INIT_DIR_DRIVE:
	LD A,(CMDLINE_IS_FAT)
	OR A
	JR NZ,IDD_IS_FAT_ARG
	LD A,(DOC_IS_FAT)
	OR A
	JR Z,IDD_NOT_FAT
IDD_IS_FAT_ARG:
	LD A,1
	LD (CURRENT_DIR_IS_FAT),A
	LD A,(FAT_DOC_UNIT)
	LD (CURRENT_DIR_FAT_UNIT),A
	CALL SET_DIR_FROM_DOC_PATH
	LD A,'U'
	LD (STR_DIR_DRIVE_CHAR),A
	LD (STR_SAVE_DRIVE_CHAR),A
	RET

IDD_NOT_FAT:
	XOR A
	LD (CURRENT_DIR_IS_FAT),A
	LD A,(IS_PLUGIN_LOAD_UI)
	OR A
	JR NZ,IDD_USE_BDOS
	LD A,(WORK_FCB)
	OR A
	JR NZ,IDD_USE_FCB
IDD_USE_BDOS:
	LD C,25				; BDOS Return Current Disk
	CALL BDOS_ENTRY
	INC A				; 0..15 -> 1..16
IDD_USE_FCB:
	LD (CURRENT_DIR_DRIVE),A
	ADD A,'A'-1
	LD (STR_DIR_DRIVE_CHAR),A
	LD (STR_SAVE_DRIVE_CHAR),A
	RET

;------------------------------------------------------------------------------
; RESTORE_DOC_USER: Restore active CP/M user area to document context
;
; Purpose:
;   Calls BDOS Set User Area (function 32) using DOC_USER_NUM to ensure the
;   underlying document user context is restored after browsing other areas.
;
; Call Usage / Protocol:
;   Called via CALL when exiting file dialogs or before file operations.
;
; Inputs:
;   DOC_USER_NUM.
;
; Outputs:
;   Active CP/M user area restored.
;
; Preserves / Modifies:
;   Clobbers AF, DE.
;------------------------------------------------------------------------------
RESTORE_DOC_USER:
	LD A,(DOC_USER_NUM)
	LD (CURRENT_DIR_USER),A
	LD E,A
	LD C,32				; BDOS Set User Area
	CALL BDOS_ENTRY
	RET

;------------------------------------------------------------------------------
; RESET_DIR_FILTER: Reset directory wildcard filter string to "*.*"
;
; Purpose:
;   Clears DIR_FILTER_BUF and writes default pattern "*.*" with terminating
;   null byte so all files match.
;
; Call Usage / Protocol:
;   Called via CALL when switching drives, user areas, or opening dialogs.
;
; Inputs:
;   None.
;
; Outputs:
;   DIR_FILTER_BUF set to "*.*".
;
; Preserves / Modifies:
;   Clobbers AF, HL.
;------------------------------------------------------------------------------
RESET_DIR_FILTER:
	XOR A
	LD (DIR_FILTER_ACTIVE),A
	LD HL,DIR_FILTER_FCB
	LD B,11
RDF_LOOP:
	LD (HL),'?'
	INC HL
	DJNZ RDF_LOOP
	LD HL,DIR_FILTER_STR
	LD (HL),'*'
	INC HL
	LD (HL),'.'
	INC HL
	LD (HL),'*'
	INC HL
	LD (HL),0
	RET

;------------------------------------------------------------------------------
; PRELOAD_DRIVE_USER_PREFIX: Preload drive/user prefix into filename input box
;
; Purpose:
;   Writes drive letter (e.g. 'A') and user area digits (e.g. '0:') into
;   INPUT_FILENAME_BUF so user sees explicit context when saving or opening.
;
; Call Usage / Protocol:
;   Called via CALL when initializing filename input in file dialogs.
;
; Inputs:
;   DIR_DRIVE, DIR_USER.
;
; Outputs:
;   INPUT_FILENAME_BUF prefilled with prefix.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
PRELOAD_DRIVE_USER_PREFIX:
	LD A,(CURRENT_DIR_IS_FAT)
	OR A
	JR NZ,PDUP_FAT

	LD DE,INPUT_FILENAME_BUF
	LD C,0				; Length counter

	; Emit drive letter (CURRENT_DIR_DRIVE)
	LD A,(CURRENT_DIR_DRIVE)
	OR A
	JR NZ,PDUP_HAS_DRV
	LD A,1				; Fallback drive A if 0
PDUP_HAS_DRV:
	ADD A,'A'-1
	LD (DE),A
	INC DE
	INC C

	; Emit user area digits (CURRENT_DIR_USER)
	LD A,(CURRENT_DIR_USER)
	CP 10
	JR C,PDUP_U_1DIGIT
	PUSH AF
	LD A,'1'
	LD (DE),A
	INC DE
	INC C
	POP AF
	SUB 10
PDUP_U_1DIGIT:
	ADD A,'0'
	LD (DE),A
	INC DE
	INC C

	; Emit ':'
	LD A,':'
	LD (DE),A
	INC DE
	INC C

	; Null-terminate buffer
	XOR A
	LD (DE),A
	LD A,C
	LD (INPUT_BUF_LEN),A
	RET

PDUP_FAT:
	LD DE,INPUT_FILENAME_BUF
	LD A,'U'
	LD (DE),A
	INC DE
	LD C,1
	LD A,(CURRENT_DIR_FAT_UNIT)
	CP 0FFH
	JR Z,PDUP_FAT_NO_UNIT
	ADD A,'0'
	LD (DE),A
	INC DE
	INC C
PDUP_FAT_NO_UNIT:
	LD A,':'
	LD (DE),A
	INC DE
	INC C
	XOR A
	LD (DE),A
	LD A,C
	LD (INPUT_BUF_LEN),A
	RET

;------------------------------------------------------------------------------
; IS_DRIVE_LETTER: Validate if character is a CP/M drive letter ('A'..'P')
;
; Purpose:
;   Converts ASCII character in A to uppercase and verifies whether it lies
;   in the valid CP/M drive range ('A'..'P').
;
; Call Usage / Protocol:
;   Called via CALL from filename prefix parsers.
;
; Inputs:
;   A = ASCII character to test.
;
; Outputs:
;   Carry = 0 and A uppercase if valid drive letter; Carry = 1 if invalid.
;
; Preserves / Modifies:
;   Modifies AF; preserves BC, DE, HL.
;------------------------------------------------------------------------------
IS_DRIVE_LETTER:
	CALL TO_UPPER
	CP 'A'
	JR C,IDL_NOT_DRV
	CP 'P'+1
	JR NC,IDL_NOT_DRV
	SUB 'A'-1			; 'A' -> 1, ..., 'P' -> 16
	SCF
	RET
IDL_NOT_DRV:
	OR A				; Carry = 0
	RET

;------------------------------------------------------------------------------
; IS_DIGIT_CHAR: Test if character is a decimal digit ('0'..'9')
;
; Purpose:
;   Checks if ASCII character in A is between '0' and '9'. If so, converts it
;   to numeric binary value (0..9) in A and clears Carry flag.
;
; Call Usage / Protocol:
;   Called via CALL from user number and line number parsing routines.
;
; Inputs:
;   A = ASCII character to test.
;
; Outputs:
;   Carry = 0 and A = numeric value (0..9) if digit; Carry = 1 if non-digit.
;
; Preserves / Modifies:
;   Modifies AF; preserves BC, DE, HL.
;------------------------------------------------------------------------------
IS_DIGIT_CHAR:
	CP '0'
	JR C,IDC_NOT_DIG
	CP '9'+1
	JR NC,IDC_NOT_DIG
	SUB '0'				; 0..9
	SCF
	RET
IDC_NOT_DIG:
	OR A
	RET

;------------------------------------------------------------------------------
; PARSE_2DIGIT_USER: Parse 1- or 2-digit decimal user number (0..31)
;
; Purpose:
;   Reads one or two decimal digits from string at HL, computes user number
;   (0..31), and validates against CP/M user area bounds.
;
; Call Usage / Protocol:
;   Called via CALL from PARSE_DRIVE_USER_PREFIX.
;
; Inputs:
;   HL = Pointer to ASCII digit string.
;
; Outputs:
;   Carry = 0 and A = user number (0..31) on success; Carry = 1 on invalid user.
;
; Preserves / Modifies:
;   Modifies AF, HL; preserves BC, DE.
;------------------------------------------------------------------------------
PARSE_2DIGIT_USER:
	LD A,D
	CP '0'
	JR Z,P2U_TENS_ZERO
	CP '1'
	JR NZ,P2U_INVALID		; Tens > 1 -> invalid (> 19)
	; Tens is '1'
	LD A,E
	CP '5'+1
	JR NC,P2U_INVALID		; Units > '5' -> invalid (> 15)
	SUB '0'
	ADD A,10			; 10..15
	SCF
	RET
P2U_TENS_ZERO:
	LD A,E
	SUB '0'				; 0..9
	SCF
	RET
P2U_INVALID:
	OR A
	RET

;------------------------------------------------------------------------------
; PARSE_DRIVE_USER_PREFIX: Parse optional drive and user prefix from string
;
; Purpose:
;   Parses drive letter ('A'..'P') and optional user area (0..31) followed by
;   a colon (e.g. "B:", "A3:", "C15:FILE.TXT") from string at DE.
;
; Call Usage / Protocol:
;   Called via CALL when evaluating user input in file dialogs.
;
; Inputs:
;   DE = Pointer to input string.
;
; Outputs:
;   Carry = 0 if prefix found; DIR_DRIVE and DIR_USER updated; DE points past
;   colon. Carry = 1 if no valid prefix found.
;
; Preserves / Modifies:
;   Clobbers AF, BC, HL; advances DE.
;------------------------------------------------------------------------------
PARSE_DRIVE_USER_PREFIX:
	PUSH HL
PDUP_SKIP_SPACES:
	LD A,(HL)
	CP ' '
	JR NZ,PDUP_CHECK_COLON
	INC HL
	JR PDUP_SKIP_SPACES

PDUP_CHECK_COLON:
	; Look for ':' at HL+1, HL+2, or HL+3
	INC HL
	LD A,(HL)
	CP ':'
	JR Z,PDUP_LEN1			; ':' at HL+1 -> 1 char before colon

	INC HL
	LD A,(HL)
	CP ':'
	JP Z,PDUP_LEN2			; ':' at HL+2 -> 2 chars before colon

	INC HL
	LD A,(HL)
	CP ':'
	JP Z,PDUP_LEN3			; ':' at HL+3 -> 3 chars before colon

PDUP_FAIL:
	POP HL				; Restore original HL
	OR A				; Carry = 0
	RET

; Length 1 before colon: (HL-1)
PDUP_LEN1:
	DEC HL				; HL points to Char 0
	LD A,(HL)
	CALL IS_DRIVE_LETTER
	JR C,PDUP_L1_DRIVE
	LD A,(HL)
	CALL IS_DIGIT_CHAR
	JR C,PDUP_L1_USER
	JP PDUP_FAIL

PDUP_L1_DRIVE:
	LD (PREFIX_DRIVE),A
	LD A,0FFH
	LD (PREFIX_USER),A
	INC HL				; past Char 0
	INC HL				; past ':'
	JP PDUP_SUCCESS

PDUP_L1_USER:
	LD (PREFIX_USER),A
	XOR A
	LD (PREFIX_DRIVE),A
	INC HL				; past Char 0
	INC HL				; past ':'
	JP PDUP_SUCCESS

; Length 2 before colon: (HL-2), (HL-1)
PDUP_LEN2:
	DEC HL
	DEC HL				; HL points to Char 0
	LD A,(HL)
	CALL IS_DRIVE_LETTER
	JR C,PDUP_L2_LETTER_FIRST
	LD A,(HL)
	CALL IS_DIGIT_CHAR
	JR C,PDUP_L2_DIGIT_FIRST
	JP PDUP_FAIL

PDUP_L2_LETTER_FIRST:
	LD (PREFIX_DRIVE),A
	INC HL				; Char 1
	LD A,(HL)
	CALL IS_DIGIT_CHAR
	JP NC,PDUP_FAIL
	LD (PREFIX_USER),A
	INC HL				; past Char 1
	INC HL				; past ':'
	JP PDUP_SUCCESS

PDUP_L2_DIGIT_FIRST:
	INC HL				; Char 1
	LD A,(HL)
	CALL IS_DRIVE_LETTER
	JR C,PDUP_L2_DIGIT_LETTER

	LD A,(HL)
	CALL IS_DIGIT_CHAR
	JP NC,PDUP_FAIL

	DEC HL				; Char 0
	LD D,(HL)
	INC HL				; Char 1
	LD E,(HL)
	CALL PARSE_2DIGIT_USER
	JP NC,PDUP_FAIL
	LD (PREFIX_USER),A
	XOR A
	LD (PREFIX_DRIVE),A
	INC HL				; past Char 1
	INC HL				; past ':'
	JP PDUP_SUCCESS

PDUP_L2_DIGIT_LETTER:
	LD (PREFIX_DRIVE),A
	DEC HL				; Char 0
	LD A,(HL)
	SUB '0'
	LD (PREFIX_USER),A
	INC HL				; Char 1
	INC HL				; past Char 1
	INC HL				; past ':'
	JP PDUP_SUCCESS

; Length 3 before colon: (HL-3), (HL-2), (HL-1)
PDUP_LEN3:
	DEC HL
	DEC HL
	DEC HL				; HL points to Char 0
	LD A,(HL)
	CALL IS_DRIVE_LETTER
	JR C,PDUP_L3_LETTER_FIRST
	LD A,(HL)
	CALL IS_DIGIT_CHAR
	JR C,PDUP_L3_DIGIT_FIRST
	JP PDUP_FAIL

PDUP_L3_LETTER_FIRST:
	LD (PREFIX_DRIVE),A
	INC HL				; Char 1
	LD D,(HL)
	INC HL				; Char 2
	LD E,(HL)
	CALL PARSE_2DIGIT_USER
	JP NC,PDUP_FAIL
	LD (PREFIX_USER),A
	INC HL				; past Char 2
	INC HL				; past ':'
	JP PDUP_SUCCESS

PDUP_L3_DIGIT_FIRST:
	LD D,(HL)			; Char 0
	INC HL
	LD E,(HL)			; Char 1
	INC HL
	LD A,(HL)			; Char 2
	CALL IS_DRIVE_LETTER
	JP NC,PDUP_FAIL
	LD (PREFIX_DRIVE),A
	CALL PARSE_2DIGIT_USER
	JP NC,PDUP_FAIL
	LD (PREFIX_USER),A
	INC HL				; past Char 2
	INC HL				; past ':'
	JP PDUP_SUCCESS

PDUP_SUCCESS:
	POP AF				; Discard saved initial HL
	LD A,(PREFIX_DRIVE)
	LD C,A
	LD A,(PREFIX_USER)
	EX AF,AF'
	LD A,C
	EX AF,AF'
	LD C,A
	EX AF,AF'
	SCF
	RET

;------------------------------------------------------------------------------
; CHECK_DRIVE_SWITCH: Check if input string represents drive/user switch
;
; Purpose:
;   Tests if INPUT_FILENAME_BUF contains only a drive and optional user area
;   with a trailing colon (e.g. "B:" or "A1:"). If so, updates DIR_DRIVE/USER
;   and sets Carry = 0 so the directory view refreshes to that location.
;
; Call Usage / Protocol:
;   Called via CALL on Enter key in file dialog.
;
; Inputs:
;   INPUT_FILENAME_BUF.
;
; Outputs:
;   Carry = 0 if drive/user switch handled; Carry = 1 if regular filename.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
CHECK_DRIVE_SWITCH:
	LD HL,INPUT_FILENAME_BUF
	CALL PARSE_DRIVE_USER_PREFIX
	RET NC				; No prefix -> Carry = 0

	; Check that remainder after ':' is empty (only null or spaces)
CDS_CHECK_REM:
	LD A,(HL)
	OR A
	JR Z,CDS_IS_SWITCH
	CP ' '
	JR NZ,CDS_NOT_SWITCH
	INC HL
	JR CDS_CHECK_REM

CDS_IS_SWITCH:
	LD A,(PREFIX_DRIVE)
	LD C,A
	LD A,(PREFIX_USER)
	EX AF,AF'
	LD A,C
	EX AF,AF'
	LD C,A
	EX AF,AF'
	SCF
	RET

CDS_NOT_SWITCH:
	OR A				; Carry = 0
	RET

;------------------------------------------------------------------------------
; CHECK_FILTER_PATTERN: Check if input string contains wildcard filter pattern
;
; Purpose:
;   Scans INPUT_FILENAME_BUF for wildcard characters ('*' or '?'). If present,
;   updates DIR_FILTER_BUF and sets Carry = 0 so the file list re-filters.
;
; Call Usage / Protocol:
;   Called via CALL on Enter key in file dialog.
;
; Inputs:
;   INPUT_FILENAME_BUF.
;
; Outputs:
;   Carry = 0 if wildcard pattern detected and stored; Carry = 1 otherwise.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
CHECK_FILTER_PATTERN:
	LD A,(INPUT_BUF_LEN)
	OR A
	RET Z				; Empty buffer -> Carry = 0

	; Scan buffer for '*' or '?'
	LD B,A
	LD HL,INPUT_FILENAME_BUF
CFP_SCAN_LOOP:
	LD A,(HL)
	CP '*'
	JR Z,CFP_FOUND_WC
	CP '?'
	JR Z,CFP_FOUND_WC
	INC HL
	DJNZ CFP_SCAN_LOOP
	OR A				; Carry = 0
	RET

CFP_FOUND_WC:
	LD HL,INPUT_FILENAME_BUF
	CALL PARSE_DRIVE_USER_PREFIX
	JR NC,CFP_NO_DRIVE_PREFIX

	; Prefix was found! Check if drive was specified
	LD A,(PREFIX_DRIVE)
	OR A
	JR Z,CFP_CHECK_USER_PRE
	LD C,A				; C = target drive (1..16)

	; Guard: if target drive matches hibernated RAM drive, reject switch
	LD A,(RAMDRIVE_IS_HIBERNATED)
	OR A
	JR Z,CFP_DRIVE_OK
	LD A,(RAMDRIVE_DRIVE_NUM)
	CP 0FFH
	JR Z,CFP_DRIVE_OK
	INC A
	CP C
	JR Z,CFP_CHECK_USER_PRE

CFP_DRIVE_OK:
	LD A,C
	LD (CURRENT_DIR_DRIVE),A
	ADD A,'A'-1
	LD (STR_DIR_DRIVE_CHAR),A
	LD (STR_SAVE_DRIVE_CHAR),A

CFP_CHECK_USER_PRE:
	LD A,(PREFIX_USER)
	CP 0FFH
	JR Z,CFP_USER_DEFAULT_ZERO
	LD (CURRENT_DIR_USER),A
	JR CFP_PARSE_START
CFP_USER_DEFAULT_ZERO:
	XOR A
	LD (CURRENT_DIR_USER),A
	JR CFP_PARSE_START

CFP_NO_DRIVE_PREFIX:
	XOR A
	LD (CURRENT_DIR_USER),A
	LD HL,INPUT_FILENAME_BUF

CFP_PARSE_START:
	; Copy uppercase pattern to DIR_FILTER_STR (max 12 chars
	; null-terminated)
	PUSH HL
	LD DE,DIR_FILTER_STR
	LD B,12
CFP_COPY_STR:
	LD A,(HL)
	OR A
	JR Z,CFP_COPY_END
	CALL TO_UPPER
	LD (DE),A
	INC HL
	INC DE
	DJNZ CFP_COPY_STR
CFP_COPY_END:
	XOR A
	LD (DE),A			; Null-terminate
	POP HL

	; Clear DIR_FILTER_FCB with 11 spaces
	PUSH HL
	LD HL,DIR_FILTER_FCB
	LD B,11
CFP_CLR_FCB:
	LD (HL),' '
	INC HL
	DJNZ CFP_CLR_FCB
	POP HL

	; Parse filename part (bytes 0..7 of DIR_FILTER_FCB)
	LD DE,DIR_FILTER_FCB
	LD B,8
CFP_NAME_LOOP:
	LD A,(HL)
	OR A
	JR Z,CFP_NAME_END_NODOT
	CP ' '
	JR Z,CFP_NAME_END_NODOT
	CP '.'
	JR Z,CFP_NAME_DOT
	CP '*'
	JR Z,CFP_NAME_STAR
	CALL TO_UPPER
	LD (DE),A
	INC DE
	INC HL
	DJNZ CFP_NAME_LOOP

	; Consumed 8 chars of name -> skip until '.' or end
CFP_SKIP_NAME_REST:
	LD A,(HL)
	OR A
	JR Z,CFP_NAME_END_NODOT
	CP ' '
	JR Z,CFP_NAME_END_NODOT
	CP '.'
	JR Z,CFP_NAME_DOT
	INC HL
	JR CFP_SKIP_NAME_REST

CFP_NAME_STAR:
	; Fill remaining name bytes with '?'
	LD A,'?'
CFP_STAR_NAME_PAD:
	LD (DE),A
	INC DE
	DJNZ CFP_STAR_NAME_PAD
	INC HL
CFP_SKIP_STAR_REST:
	LD A,(HL)
	OR A
	JR Z,CFP_NAME_END_NODOT
	CP ' '
	JR Z,CFP_NAME_END_NODOT
	CP '.'
	JR Z,CFP_NAME_DOT
	INC HL
	JR CFP_SKIP_STAR_REST

CFP_NAME_DOT:
	INC HL				; Skip '.'
	JR CFP_PARSE_EXT

CFP_NAME_END_NODOT:
	; No '.' in input (e.g. '*' or 'A*') -> fill ext with '?'
	LD DE,DIR_FILTER_FCB+8
	LD A,'?'
	LD (DE),A
	INC DE
	LD (DE),A
	INC DE
	LD (DE),A
	JR CFP_CHECK_ACTIVE

CFP_PARSE_EXT:
	LD DE,DIR_FILTER_FCB+8
	LD B,3
CFP_EXT_LOOP:
	LD A,(HL)
	OR A
	JR Z,CFP_CHECK_ACTIVE
	CP ' '
	JR Z,CFP_CHECK_ACTIVE
	CP '*'
	JR Z,CFP_EXT_STAR
	CALL TO_UPPER
	LD (DE),A
	INC DE
	INC HL
	DJNZ CFP_EXT_LOOP
	JR CFP_CHECK_ACTIVE

CFP_EXT_STAR:
	LD A,'?'
CFP_STAR_EXT_PAD:
	LD (DE),A
	INC DE
	DJNZ CFP_STAR_EXT_PAD

CFP_CHECK_ACTIVE:
	; Check if DIR_FILTER_FCB is all '?' (meaning *.*)
	LD HL,DIR_FILTER_FCB
	LD B,11
CFP_CHK_QM:
	LD A,(HL)
	CP '?'
	JR NZ,CFP_SET_ACTIVE
	INC HL
	DJNZ CFP_CHK_QM

	; All 11 chars are '?' -> Inactive (standard *.*)
	XOR A
	LD (DIR_FILTER_ACTIVE),A
	LD HL,DIR_FILTER_STR
	LD (HL),'*'
	INC HL
	LD (HL),'.'
	INC HL
	LD (HL),'*'
	INC HL
	LD (HL),0
	SCF
	RET

CFP_SET_ACTIVE:
	LD A,1
	LD (DIR_FILTER_ACTIVE),A
	SCF
	RET

;------------------------------------------------------------------------------
; FCB_TO_FILENAME_STR: Convert FCB 8.3 filename to formatted string
;
; Purpose:
;   Extracts 8-character filename and 3-character extension from FCB at HL,
;   strips padding spaces, inserts '.', and writes null-terminated string to DE.
;
; Call Usage / Protocol:
;   Called via CALL for status bar, dialog, and message formatting.
;
; Inputs:
;   HL = Pointer to FCB (bytes 1..11: name and ext).
;   DE = Pointer to destination string buffer.
;
; Outputs:
;   Null-terminated formatted filename written to DE.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
FCB_TO_FILENAME_STR:
	LD A,(HAS_FILE_ARG)
	OR A
	JR NZ,DO_CONVERT_FCB

	; No file argument -> empty buffer
	XOR A
	LD (INPUT_BUF_LEN),A
	LD HL,INPUT_FILENAME_BUF
	LD (HL),0
	RET

DO_CONVERT_FCB:
	LD DE,INPUT_FILENAME_BUF
	LD C,0				; C = length counter

	; Check drive (WORK_FCB+0)
	LD A,(WORK_FCB)
	OR A
	JR NZ,FCB_HAS_DRV
	LD A,(CURRENT_DIR_DRIVE)
	OR A
	JR NZ,FCB_HAS_DRV
	LD A,1				; Fallback drive A if 0
FCB_HAS_DRV:
	; Explicit drive 1..16
	ADD A,'A'-1
	LD (DE),A
	INC DE
	INC C

FCB_CHECK_USER:
	; Always emit user area digits (DOC_USER_NUM), including 0
	LD A,(DOC_USER_NUM)
	CP 10
	JR C,FCB_U_1DIGIT
	PUSH AF
	LD A,'1'
	LD (DE),A
	INC DE
	INC C
	POP AF
	SUB 10
FCB_U_1DIGIT:
	ADD A,'0'
	LD (DE),A
	INC DE
	INC C

FCB_EMIT_COLON:
	LD A,':'
	LD (DE),A
	INC DE
	INC C

FCB_NO_DRIVE:
	; Copy up to 8 characters of filename (WORK_FCB+1..8)
	LD HL,WORK_FCB+1
	LD B,8
FCB_NAME_LOOP:
	LD A,(HL)
	CP ' '
	JR Z,FCB_NAME_DONE
	OR A
	JR Z,FCB_NAME_DONE
	LD (DE),A
	INC DE
	INC HL
	INC C
	DJNZ FCB_NAME_LOOP

FCB_NAME_DONE:
	; Check extension (WORK_FCB+9..11)
	LD HL,WORK_FCB+9
	LD A,(HL)
	CP ' '
	JR Z,FCB_CONV_DONE
	OR A
	JR Z,FCB_CONV_DONE

	; Has extension: add '.'
	LD A,'.'
	LD (DE),A
	INC DE
	INC C

	LD B,3
FCB_EXT_LOOP:
	LD A,(HL)
	CP ' '
	JR Z,FCB_CONV_DONE
	OR A
	JR Z,FCB_CONV_DONE
	LD (DE),A
	INC DE
	INC HL
	INC C
	DJNZ FCB_EXT_LOOP

FCB_CONV_DONE:
	XOR A
	LD (DE),A			; Null-terminate
	LD A,C
	LD (INPUT_BUF_LEN),A
	RET

;------------------------------------------------------------------------------
; DISPLAY_SAVE_PROMPT: Render Save As input prompt and format info
;
; Purpose:
;   Emits "Save file: [ ... ]" prompt line, line ending format mode indicator,
;   and positions cursor at active edit position within the filename box.
;
; Call Usage / Protocol:
;   Called via CALL from RENDER_SAVE_PAGE.
;
; Inputs:
;   None.
;
; Outputs:
;   Prompt line drawn on terminal.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DISPLAY_SAVE_PROMPT:
	LD A,(DIR_PAGE_COUNT)
	CP 2
	JR C,DISP_SINGLE_SAVE_PROMPT

	; Multi-page prompt
	LD HL,UI_CUR_ROW
	INC (HL)
	CALL PRINT_HR_DASH
	INC (HL)
	CALL PRINT_DIR_PREFIX
	LD DE,STR_PAGE_PREFIX_TXT
	CALL PRINT_STR

	LD A,(DIR_PAGE_INDEX)
	INC A
	LD L,A
	LD H,0
	CALL PRINT_DEC_WORD

	LD DE,STR_PAGE_MID
	CALL PRINT_STR

	LD A,(DIR_PAGE_COUNT)
	LD L,A
	LD H,0
	CALL PRINT_DEC_WORD

	LD DE,STR_PAGE_SUFFIX
	CALL PRINT_STR
	CALL PRINT_SAVE_FMT_INFO
	JR DISP_SAVE_PROMPT_BODY

DISP_SINGLE_SAVE_PROMPT:
	LD HL,UI_CUR_ROW
	INC (HL)
	CALL PRINT_HR_DASH
	CALL PRINT_SAVE_FMT_INFO

DISP_SAVE_PROMPT_BODY:
	LD HL,UI_CUR_ROW
	INC (HL)			; For STR_ESC_CANCEL
	INC (HL)			; For Prompt line itself!
	CALL PRINT_DIR_PREFIX
	LD DE,STR_ESC_CANCEL_TXT
	CALL PRINT_STR
	CALL PRINT_DIR_PREFIX
	CALL TERM_INVERSE_ON
	LD DE,STR_SAVE_PROMPT_TXT	; "Enter filename to save:"
	CALL PRINT_STR
	CALL TERM_INVERSE_OFF
	CALL DRAW_FILENAME_BOX
	RET

;------------------------------------------------------------------------------
; PRINT_SAVE_FMT_INFO: Print active line ending format indicator string
;
; Purpose:
;   Outputs bracketed line ending mode (" [CRLF]", " [LF]", or " [CR]") inside
;   the save prompt bar to inform user of output line format.
;
; Call Usage / Protocol:
;   Called via CALL from DISPLAY_SAVE_PROMPT.
;
; Inputs:
;   FILE_LINE_ENDING_MODE.
;
; Outputs:
;   Format string emitted to terminal.
;
; Preserves / Modifies:
;   Clobbers AF, DE.
;------------------------------------------------------------------------------
PRINT_SAVE_FMT_INFO:
	LD HL,UI_CUR_ROW
	INC (HL)
	CALL PRINT_DIR_PREFIX
	LD DE,STR_SAVE_FMT_PREFIX_TXT
	CALL PRINT_STR
	LD A,(SAVE_FORMAT)
	CP FMT_CPM
	JR NZ,PRINT_SAVE_FMT_LINUX
	LD DE,STR_SAVE_FMT_CPM
	CALL PRINT_STR
	JR PRINT_SAVE_FMT_END
PRINT_SAVE_FMT_LINUX:
	LD DE,STR_SAVE_FMT_LINUX
	CALL PRINT_STR
PRINT_SAVE_FMT_END:
	LD DE,STR_SAVE_FMT_SUFFIX
	CALL PRINT_STR
	RET

;------------------------------------------------------------------------------
; COLLECT_DIR_ENTRIES: Query directory entries via BDOS and populate buffer
;
; Purpose:
;   Enumerates directory entries from CP/M default drive via BDOS Search First
;   (17) and Search Next (18), strips bit 7 high attributes, filters duplicates,
;   filters swap files, applies wildcard filter, and sorts entries.
;
; Call Usage / Protocol:
;   Called via CALL when opening or refreshing file modal browser dialogs.
;
; Inputs:
;   DIR_DRIVE, DIR_USER, DIR_FILTER_BUF.
;
; Outputs:
;   DIR_FILE_COUNT populated; DIR_NAMES_BUF filled with sorted 11-byte entries.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
COLLECT_DIR_ENTRIES:
	XOR A
	LD (DIR_FILE_COUNT),A

	; Check if active directory mode is FAT volume
	LD A,(CURRENT_DIR_IS_FAT)
	OR A
	JP NZ,COLLECT_FAT_DIR_ENTRIES

	; Guard: if RAM drive is hibernated and CURRENT_DIR_DRIVE matches,
	; return empty directory
	LD A,(RAMDRIVE_IS_HIBERNATED)
	OR A
	JR Z,CDE_DRIVE_OK
	LD A,(RAMDRIVE_DRIVE_NUM)
	CP 0FFH
	JR Z,CDE_DRIVE_OK
	INC A
	LD B,A
	LD A,(CURRENT_DIR_DRIVE)
	CP B
	RET Z				; Hibernated drive -> return empty
CDE_DRIVE_OK:
	; Set DMA address to RAW_SECTOR_BUF (128 bytes)
	LD DE,RAW_SECTOR_BUF
	LD C,26				; BDOS Set DMA
	CALL BDOS_ENTRY

	; Prepare DIR_SEARCH_FCB: Drive = CURRENT_DIR_DRIVE, 11 filter bytes,
	; rest 0
	LD HL,DIR_SEARCH_FCB
	LD A,(CURRENT_DIR_DRIVE)
	LD (HL),A		; Active directory drive (1=A, 2=B, etc.)
	INC HL
	EX DE,HL
	LD HL,DIR_FILTER_FCB
	LD BC,11
	LDIR
	EX DE,HL
	LD B,24
SET_SEARCH_ZEROS:
	LD (HL),0
	INC HL
	DJNZ SET_SEARCH_ZEROS

	; Set BDOS user area to CURRENT_DIR_USER
	LD A,(CURRENT_DIR_USER)
	LD E,A
	LD C,32				; BDOS Set User Area
	CALL BDOS_ENTRY

	; Search First (BDOS 17)
	LD DE,DIR_SEARCH_FCB
	LD C,17
	CALL BDOS_ENTRY
	CP 0FFH
	RET Z				; No files on drive

DIR_COLLECT_LOOP:
	; A = directory entry index (0..3) in RAW_SECTOR_BUF
	; Calculate entry address: RAW_SECTOR_BUF + (A * 32)
	LD L,A
	LD H,0
	ADD HL,HL			; *2
	ADD HL,HL			; *4
	ADD HL,HL			; *8
	ADD HL,HL			; *16
	ADD HL,HL			; *32
	LD DE,RAW_SECTOR_BUF
	ADD HL,DE		; HL = pointer to 32-byte directory entry

	; Check user number / deleted status (byte 0):
	LD A,(HL)
	CP 0E5H
	JR Z,DIR_NEXT_ENTRY		; Deleted entry
	LD B,A
	LD A,(CURRENT_DIR_USER)
	CP B
	JR NZ,DIR_NEXT_ENTRY		; Non-matching user entry

	; Check that filename is not blank (first char != space and != 0, with
	; bit 7 stripped)
	INC HL				; HL = pointer to filename (bytes 1..8)
	LD A,(HL)
	AND 07FH
	CP ' '
	JR Z,DIR_NEXT_ENTRY
	OR A
	JR Z,DIR_NEXT_ENTRY

	; Format entry into DIR_TEMP_ENTRY (13 bytes: 8 name + '.' + 3 ext + 0)
	LD DE,DIR_TEMP_ENTRY
	LD B,8
COPY_NAME_TEMP:
	LD A,(HL)
	AND 07FH
	LD (DE),A
	INC HL
	INC DE
	DJNZ COPY_NAME_TEMP

	LD A,'.'
	LD (DE),A
	INC DE

	LD B,3
COPY_EXT_TEMP:
	LD A,(HL)
	AND 07FH
	LD (DE),A
	INC HL
	INC DE
	DJNZ COPY_EXT_TEMP

	XOR A
	LD (DE),A

	; Filter out temporary swap files ($$$SE$$$.SWP or $$$*.SWP)
	CALL CHECK_DIR_SWAP_FILE
	JR C,DIR_NEXT_ENTRY		; Swap file -> skip

	; In Plugin Load UI, filter for .PRL and .OVL files
	; unless a custom wildcard filter is active
	LD A,(IS_PLUGIN_LOAD_UI)
	OR A
	JR Z,CDE_NOT_PLUGIN_UI
	LD A,(DIR_FILTER_ACTIVE)
	OR A
	JR NZ,CDE_NOT_PLUGIN_UI
	CALL CHECK_PLUGIN_EXT
	JR NC,DIR_NEXT_ENTRY		; Not a plugin file -> skip
CDE_NOT_PLUGIN_UI:

	; Check if this filename is already in DIR_NAMES_BUF (duplicate extent
	; filter)
	CALL CHECK_DIR_DUPLICATE
	JR C,DIR_NEXT_ENTRY		; Already collected -> skip duplicate

	; Not a duplicate: append DIR_TEMP_ENTRY into DIR_NAMES_BUF
	LD A,(DIR_FILE_COUNT)
	LD L,A
	LD H,0
	; HL = A * 13
	LD D,H
	LD E,L				; DE = A
	ADD HL,HL			; *2
	ADD HL,HL			; *4
	ADD HL,DE			; *5
	ADD HL,HL			; *10
	ADD HL,DE			; *11
	ADD HL,DE			; *12
	ADD HL,DE			; *13
	LD DE,DIR_NAMES_BUF
	ADD HL,DE
	EX DE,HL			; DE = Destination in DIR_NAMES_BUF

	LD HL,DIR_TEMP_ENTRY
	LD BC,13
	LDIR

	; Increment DIR_FILE_COUNT
	LD A,(DIR_FILE_COUNT)
	INC A
	LD (DIR_FILE_COUNT),A
	CP 255				; Max 255 entries
	RET NC

DIR_NEXT_ENTRY:
	; Search Next (BDOS 18)
	LD DE,DIR_SEARCH_FCB
	LD C,18
	CALL BDOS_ENTRY
	CP 0FFH
	RET Z
	JP DIR_COLLECT_LOOP

;------------------------------------------------------------------------------
; CHECK_DIR_DUPLICATE: Check if candidate entry already exists in DIR_NAMES_BUF
;
; Purpose:
;   Compares 11-byte candidate filename at DE against all existing entries in
;   DIR_NAMES_BUF to filter out redundant multi-extent CP/M directory records.
;
; Call Usage / Protocol:
;   Called via CALL from COLLECT_DIR_ENTRIES loop for each found directory item.
;
; Inputs:
;   DE = Pointer to 11-byte candidate filename.
;   DIR_FILE_COUNT = Current number of entries in DIR_NAMES_BUF.
;
; Outputs:
;   Carry = 1 if duplicate found; Carry = 0 if candidate is unique.
;
; Preserves / Modifies:
;   Clobbers AF, BC, HL; preserves DE.
;------------------------------------------------------------------------------
CHECK_DIR_DUPLICATE:
	LD A,(DIR_FILE_COUNT)
	OR A
	RET Z				; 0 entries -> cannot be duplicate (NC)

	LD B,A				; B = number of entries to check
	LD HL,DIR_NAMES_BUF

CHECK_DUP_ENTRY_LOOP:
	PUSH BC
	PUSH HL				; Save entry pointer in DIR_NAMES_BUF
	LD DE,DIR_TEMP_ENTRY
	LD C,12			; Compare 12 bytes (8 name + '.' + 3 ext)

CHECK_DUP_BYTE_LOOP:
	LD A,(DE)
	CP (HL)
	JR NZ,CHECK_DUP_NO_MATCH
	INC HL
	INC DE
	DEC C
	JR NZ,CHECK_DUP_BYTE_LOOP

	; Found identical 12-byte filename match!
	POP HL
	POP BC
	SCF				; Carry = 1 (duplicate)
	RET

CHECK_DUP_NO_MATCH:
	POP HL				; Restore entry pointer
	LD DE,13
	ADD HL,DE			; Advance to next entry
	POP BC
	DJNZ CHECK_DUP_ENTRY_LOOP

	OR A				; Carry = 0 (not duplicate)
	RET

;------------------------------------------------------------------------------
; CHECK_DIR_SWAP_FILE: Test if entry matches virtual memory swap file
;
; Purpose:
;   Compares 11-byte filename at DE against "SESWAP  TMP" and temporary swap
;   patterns to prevent internal virtual paging files from appearing in browser.
;
; Call Usage / Protocol:
;   Called via CALL from COLLECT_DIR_ENTRIES.
;
; Inputs:
;   DE = Pointer to 11-byte candidate filename.
;
; Outputs:
;   Carry = 1 if swap file (exclude); Carry = 0 if regular file (include).
;
; Preserves / Modifies:
;   Clobbers AF, BC, HL; preserves DE.
;------------------------------------------------------------------------------
CHECK_DIR_SWAP_FILE:
	PUSH BC
	PUSH DE
	PUSH HL

	; 1. Check exact match with $$$SE$$$.SWP (12 characters)
	LD HL,DIR_TEMP_ENTRY
	LD DE,STR_SWAP_FILE_MATCH
	LD B,12
CDSF_MATCH_LOOP:
	LD A,(DE)
	CP (HL)
	JR NZ,CDSF_CHECK_GENERIC
	INC HL
	INC DE
	DJNZ CDSF_MATCH_LOOP
	SCF				; Carry = 1: matches $$$SE$$$.SWP
	JR CDSF_DONE

CDSF_CHECK_GENERIC:
	; 2. Check generic swap pattern: starts with "$$$" and extension "SWP"
	LD HL,DIR_TEMP_ENTRY
	LD A,(HL)
	CP '$'
	JR NZ,CDSF_NOT_SWAP
	INC HL
	LD A,(HL)
	CP '$'
	JR NZ,CDSF_NOT_SWAP
	INC HL
	LD A,(HL)
	CP '$'
	JR NZ,CDSF_NOT_SWAP
	; Extension is at DIR_TEMP_ENTRY+9 (3 bytes: 'S', 'W', 'P')
	LD HL,DIR_TEMP_ENTRY+9
	LD A,(HL)
	CP 'S'
	JR NZ,CDSF_NOT_SWAP
	INC HL
	LD A,(HL)
	CP 'W'
	JR NZ,CDSF_NOT_SWAP
	INC HL
	LD A,(HL)
	CP 'P'
	JR NZ,CDSF_NOT_SWAP
	SCF				; Carry = 1: matches $$$*.SWP
	JR CDSF_DONE

CDSF_NOT_SWAP:
	OR A				; Carry = 0: normal file
CDSF_DONE:
	POP HL
	POP DE
	POP BC
	RET

STR_SWAP_FILE_MATCH:
	DB "$$$SE$$$.SWP",0

;------------------------------------------------------------------------------
; CHECK_PLUGIN_EXT: Validate plugin extension (.PRL or .OVL) for plugin browser
;
; Purpose:
;   Examines 3-byte extension field at DE+8 to verify if it matches "PRL" or
;   "OVL" when user is browsing plugins.
;
; Call Usage / Protocol:
;   Called via CALL from COLLECT_DIR_ENTRIES when IS_PLUGIN_LOAD_UI is set.
;
; Inputs:
;   DE = Pointer to 11-byte filename.
;
; Outputs:
;   Carry = 0 if valid plugin extension; Carry = 1 otherwise.
;
; Preserves / Modifies:
;   Clobbers AF, HL; preserves BC, DE.
;------------------------------------------------------------------------------
CHECK_PLUGIN_EXT:
	LD HL,DIR_TEMP_ENTRY + 9
	LD A,(HL)
	CP 'P'
	JR NZ,CPE_CHECK_OVL
	INC HL
	LD A,(HL)
	CP 'R'
	JR NZ,CPE_FAIL
	INC HL
	LD A,(HL)
	CP 'L'
	JR NZ,CPE_FAIL
	SCF
	RET
CPE_CHECK_OVL:
	CP 'O'
	JR NZ,CPE_FAIL
	INC HL
	LD A,(HL)
	CP 'V'
	JR NZ,CPE_FAIL
	INC HL
	LD A,(HL)
	CP 'L'
	JR NZ,CPE_FAIL
	SCF
	RET
CPE_FAIL:
	OR A
	RET

;------------------------------------------------------------------------------
; SORT_DIR_ENTRIES: Alphabetically sort directory entries in DIR_NAMES_BUF
;
; Purpose:
;   Executes an in-place bubble sort across all 11-byte filename records stored
;   in DIR_NAMES_BUF so file listings appear in clean alphabetical order.
;
; Call Usage / Protocol:
;   Called via CALL from COLLECT_DIR_ENTRIES after file collection finishes.
;
; Inputs:
;   DIR_NAMES_BUF, DIR_FILE_COUNT.
;
; Outputs:
;   Entries in DIR_NAMES_BUF ordered alphabetically.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SORT_DIR_ENTRIES:
	LD A,(DIR_FILE_COUNT)
	CP 2
	RET C				; 0 or 1 files: already sorted

	LD B,A
	DEC B				; B = outer loop count (N-1)

SORT_OUTER_LOOP:
	PUSH BC
	LD HL,DIR_NAMES_BUF		; HL = entry j
	LD C,B				; C = inner loop count

SORT_INNER_LOOP:
	PUSH BC
	PUSH HL				; Save entry j pointer
	LD DE,13
	ADD HL,DE
	EX DE,HL			; DE = entry j+1 pointer
	POP HL				; HL = entry j pointer
	PUSH HL				; Save entry j pointer again

	; Compare entry j (HL) and entry j+1 (DE) (12 bytes)
	LD B,12
COMPARE_ENTRY_LOOP:
	LD A,(DE)
	CP (HL)
	JR NZ,COMPARE_FOUND_DIFF
	INC HL
	INC DE
	DJNZ COMPARE_ENTRY_LOOP
	JR NO_SWAP_NEEDED		; Exactly identical

COMPARE_FOUND_DIFF:
	JR NC,NO_SWAP_NEEDED	; (DE) >= (HL): already in alphabetical order!

	; Swap entry j and entry j+1 (13 bytes)
	POP HL				; HL = entry j pointer
	PUSH HL
	LD DE,13
	ADD HL,DE
	EX DE,HL			; DE = entry j+1 pointer
	POP HL				; HL = entry j pointer
	PUSH HL

	; Copy entry j into DIR_TEMP_ENTRY
	PUSH DE
	PUSH HL
	LD DE,DIR_TEMP_ENTRY
	LD BC,13
	LDIR
	POP HL
	POP DE

	; Copy entry j+1 (DE) into entry j (HL)
	PUSH DE
	PUSH HL
	EX DE,HL
	LD BC,13
	LDIR
	POP HL
	POP DE

	; Copy DIR_TEMP_ENTRY into entry j+1 (DE)
	PUSH HL
	LD HL,DIR_TEMP_ENTRY
	LD BC,13
	LDIR
	POP HL

NO_SWAP_NEEDED:
	POP HL				; HL = entry j pointer
	LD DE,13
	ADD HL,DE			; Advance HL to entry j+1
	POP BC				; Restore inner loop count C
	DEC C
	JR NZ,SORT_INNER_LOOP

	POP BC				; Restore outer loop count B
	DJNZ SORT_OUTER_LOOP
	RET

;------------------------------------------------------------------------------
; DISPLAY_DIR_PAGE: Format and render directory entries in multi-column grid
;
; Purpose:
;   Calculates pagination offset, iterates over entries for the active page,
;   and formats filenames across multiple columns with spacing and borders.
;
; Call Usage / Protocol:
;   Called via CALL from RENDER_OPEN_PAGE and RENDER_SAVE_PAGE.
;
; Inputs:
;   DIR_PAGE_NUM, DIR_FILE_COUNT, DIR_NAMES_BUF.
;
; Outputs:
;   Grid of filenames printed to terminal.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DIR_PAGE_FILE_CNT	EQU DIR_TEMP_ENTRY + 13
DIR_HL_INDEX		EQU DIR_TEMP_ENTRY + 14
DIR_HL_AUTO_MODE	EQU DIR_TEMP_ENTRY + 15

RESTORE_WORK_FCB_FROM_TEMP:
	LD HL,DIR_TEMP_FCB
	LD DE,WORK_FCB
	LD BC,36
	LDIR
	LD A,(DOC_USER_NUM)
	LD (WORK_FCB_USER),A
	RET

CALC_DIR_PAGES:
	XOR A
	LD (DIR_PAGE_INDEX),A
	LD (DIR_HL_AUTO_MODE),A
	LD A,(DIR_FILE_COUNT)
	OR A
	JR NZ,CDP_NONZERO
	INC A
	LD (DIR_PAGE_COUNT),A
	RET
CDP_NONZERO:
	DEC A				; A = N - 1
	LD B,0				; B = quotient
	LD HL,DIR_PAGE_CAPACITY
	LD C,(HL)
CDP_DIV_LOOP:
	CP C
	JR C,CDP_DIV_DONE
	SUB C
	INC B
	JR CDP_DIV_LOOP
CDP_DIV_DONE:
	INC B
	LD A,B
	LD (DIR_PAGE_COUNT),A
	RET

DISPLAY_DIR_PAGE:
	LD A,(DIR_FILE_COUNT)
	LD (DIR_PAGE_FILE_CNT),A
	OR A
	JR NZ,DO_SHOW_PAGE
	LD HL,UI_CUR_ROW
	INC (HL)
	INC (HL)
	CALL PRINT_DIR_PREFIX
	LD DE,STR_NO_FILES_FOUND_TXT
	CALL PRINT_STR
	RET

DO_SHOW_PAGE:
	; Calculate start file: DIR_START_FILE = DIR_PAGE_INDEX *
	; DIR_PAGE_CAPACITY
	CALL CALC_DIR_START_FILE

	; Calculate number of files on this page:
	; Count = min(DIR_PAGE_CAPACITY, DIR_FILE_COUNT - DIR_START_FILE)
	LD A,(DIR_FILE_COUNT)
	LD HL,DIR_START_FILE
	SUB (HL)
	LD HL,DIR_PAGE_CAPACITY
	CP (HL)
	JR C,HAVE_PAGE_COUNT
	LD A,(HL)
HAVE_PAGE_COUNT:
	LD (DIR_PAGE_FILE_CNT),A
	LD B,A			; B = number of files to display on this page

	LD A,(DIR_START_FILE)
	CALL CALC_ENTRY_PTR_A	; HL = pointer to start entry on this page

	XOR A
	LD (DIR_COL_COUNT),A

DISPLAY_PAGE_LOOP:
	PUSH BC
	PUSH HL				; Save entry pointer

	; If first column of row, emit prefix
	LD A,(DIR_COL_COUNT)
	OR A
	JR NZ,DPL_NOT_FIRST_COL
	CALL PRINT_DIR_PREFIX
DPL_NOT_FIRST_COL:

	CALL FORMAT_DIR_ENTRY_HL
	LD A,(DIR_COL_WIDTH)
	CALL PRINT_PADDED_ENTRY_A

	; Increment column counter
	LD A,(DIR_COL_COUNT)
	INC A
	LD (DIR_COL_COUNT),A
	LD HL,DIR_COLS_PER_ROW
	CP (HL)		; Wrap at DIR_COLS_PER_ROW (5 on 80x24, 7 on 120x40)
	JR NZ,NO_ROW_WRAP
	XOR A
	LD (DIR_COL_COUNT),A
	LD HL,UI_CUR_ROW
	INC (HL)
	CALL PRINT_CRLF

NO_ROW_WRAP:
	POP HL				; Restore entry pointer
	LD DE,13
	ADD HL,DE			; Next entry
	POP BC
	DEC B
	JP NZ,DISPLAY_PAGE_LOOP

	; If row didn't end on a newline, print CRLF
	LD A,(DIR_COL_COUNT)
	OR A
	JR Z,DISP_PAGE_DONE
	LD HL,UI_CUR_ROW
	INC (HL)
	CALL PRINT_CRLF

DISP_PAGE_DONE:
	LD HL,UI_CUR_ROW
	INC (HL)
	LD DE,STR_TILDE_CRLF
	CALL PRINT_STR
	RET

;------------------------------------------------------------------------------
; PRINT_DIR_COL_ENTRY: Print single directory filename entry in table column
;
; Purpose:
;   Prints filename and extension with trailing space padding to fill column
;   width cleanly within the directory grid.
;
; Call Usage / Protocol:
;   Called via CALL from DISPLAY_DIR_PAGE inner column loop.
;
; Inputs:
;   HL = Pointer to formatted filename entry string.
;
; Outputs:
;   Filename printed to terminal.
;
; Preserves / Modifies:
;   Clobbers AF, HL; preserves BC, DE.
;------------------------------------------------------------------------------
CALC_ENTRY_PTR_A:
	LD L,A
	LD H,0
	LD D,H
	LD E,L
	ADD HL,HL			; *2
	ADD HL,HL			; *4
	ADD HL,DE			; *5
	ADD HL,HL			; *10
	ADD HL,DE			; *11
	ADD HL,DE			; *12
	ADD HL,DE			; *13
	LD DE,DIR_NAMES_BUF
	ADD HL,DE
	RET

FORMAT_DIR_ENTRY_HL:
	LD DE,LOAD_LINE_TEMP
	LD B,8
COPY_DISP_NAME:
	LD A,(HL)
	CP ' '
	JR Z,SKIP_NAME_SPACE
	LD (DE),A
	INC DE
SKIP_NAME_SPACE:
	INC HL
	DJNZ COPY_DISP_NAME

	; Check if byte 8 is '/' (subdirectory indicator from VFS_CMD_LIST_DIR)
	LD A,(HL)
	CP '/'
	JR NZ,DPL_NOT_SUBDIR
	LD (DE),A
	INC DE
	JR FDE_TERMINATE

DPL_NOT_SUBDIR:
	; Check extension (3 chars) at HL+1
	INC HL				; Skip '.'
	LD A,(HL)
	CP ' '
	JR Z,FDE_TERMINATE
	LD A,'.'
	LD (DE),A
	INC DE
	LD B,3
COPY_DISP_EXT:
	LD A,(HL)
	CP ' '
	JR Z,SKIP_EXT_SPACE
	LD (DE),A
	INC DE
SKIP_EXT_SPACE:
	INC HL
	DJNZ COPY_DISP_EXT

FDE_TERMINATE:
	XOR A
	LD (DE),A
	LD HL,LOAD_LINE_TEMP
	LD A,E
	SUB L
	LD C,A				; C = formatted filename length
	RET

PRINT_PADDED_ENTRY_A:
	; A = target padded width, C = length of string in LOAD_LINE_TEMP
	SUB C
	LD B,A				; B = spaces to pad (if > 0)
	LD HL,LOAD_LINE_TEMP
PPE_CHAR_LOOP:
	LD A,(HL)
	OR A
	JR Z,PPE_PAD_CHECK
	CALL PUTC
	INC HL
	JR PPE_CHAR_LOOP
PPE_PAD_CHECK:
	LD A,B
	OR A
	RET Z
	RET M
PPE_SPACE_LOOP:
	LD A,' '
	CALL PUTC
	DJNZ PPE_SPACE_LOOP
	RET

;------------------------------------------------------------------------------
; DISPLAY_OPEN_PROMPT: Render Open File input prompt box
;
; Purpose:
;   Emits "Open file: [ ... ]" prompt line and sets cursor position to active
;   edit offset within the filename text box.
;
; Call Usage / Protocol:
;   Called via CALL from RENDER_OPEN_PAGE.
;
; Inputs:
;   None.
;
; Outputs:
;   Prompt line drawn on terminal.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DISPLAY_OPEN_PROMPT:
	LD A,(DIR_PAGE_COUNT)
	CP 2
	JR C,DISP_SINGLE_PROMPT

	; Multi-page prompt
	LD HL,UI_CUR_ROW
	INC (HL)
	CALL PRINT_HR_DASH
	INC (HL)
	CALL PRINT_DIR_PREFIX
	LD DE,STR_PAGE_PREFIX_TXT
	CALL PRINT_STR

	LD A,(DIR_PAGE_INDEX)
	INC A
	LD L,A
	LD H,0
	CALL PRINT_DEC_WORD

	LD DE,STR_PAGE_MID
	CALL PRINT_STR

	LD A,(DIR_PAGE_COUNT)
	LD L,A
	LD H,0
	CALL PRINT_DEC_WORD

	LD DE,STR_PAGE_SUFFIX
	CALL PRINT_STR
	JR DISP_OPEN_PROMPT_BODY

DISP_SINGLE_PROMPT:
	LD HL,UI_CUR_ROW
	INC (HL)
	CALL PRINT_HR_DASH

DISP_OPEN_PROMPT_BODY:
	LD HL,UI_CUR_ROW
	INC (HL)			; For STR_ESC_CANCEL
	INC (HL)			; For Prompt line itself!
	CALL PRINT_DIR_PREFIX
	LD DE,STR_ESC_CANCEL_TXT
	CALL PRINT_STR
	CALL PRINT_DIR_PREFIX
	CALL TERM_INVERSE_ON
	LD A,(IS_BLOCK_INSERT_UI)
	OR A
	JR NZ,DOP_SHOW_INSERT
	LD A,(IS_PLUGIN_LOAD_UI)
	OR A
	JR NZ,DOP_SHOW_PLUGIN
	LD DE,STR_OPEN_PROMPT_TXT	; "Enter filename to open:"
	JR DOP_SHOW_TXT
DOP_SHOW_INSERT:
	LD DE,STR_INSERT_PROMPT_TXT	; "Enter filename to insert:"
	JR DOP_SHOW_TXT
DOP_SHOW_PLUGIN:
	LD DE,STR_PLUG_LOAD_PROMPT_TXT	; "Load Plugin (.PRL/.OVL):"
DOP_SHOW_TXT:
	CALL PRINT_STR
	CALL TERM_INVERSE_OFF
	CALL DRAW_FILENAME_BOX
	RET

;------------------------------------------------------------------------------
; DRAW_FILENAME_BOX: Draw bracketed input box and position terminal cursor
;
; Purpose:
;   Emits opening bracket '[', prints current string in INPUT_FILENAME_BUF,
;   pads remaining box width with spaces, emits ']', and moves cursor back.
;
; Call Usage / Protocol:
;   Called via CALL from DISPLAY_OPEN_PROMPT and DISPLAY_SAVE_PROMPT.
;
; Inputs:
;   INPUT_FILENAME_BUF.
;
; Outputs:
;   Input text box drawn on terminal; cursor positioned inside box.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
DRAW_FILENAME_BOX:
	LD A,' '
	CALL PUTC
	LD A,'['
	CALL PUTC

	; Check if any prefilled text in INPUT_FILENAME_BUF
	LD A,(INPUT_BUF_LEN)
	LD (INPUT_CURSOR_POS),A
	LD B,A				; B = length of prefilled text (0..20)
	OR A
	JR Z,DFB_PAD_SPACES
	LD HL,INPUT_FILENAME_BUF
DFB_PRINT_LOOP:
	LD A,(HL)
	CALL PUTC
	INC HL
	DJNZ DFB_PRINT_LOOP

DFB_PAD_SPACES:
	; Pad (20 - INPUT_BUF_LEN) spaces
	LD A,20
	LD HL,INPUT_BUF_LEN
	SUB (HL)
	JR Z,DFB_CLOSE_BOX
	LD B,A
DFB_SPACE_LOOP:
	LD A,' '
	CALL PUTC
	DJNZ DFB_SPACE_LOOP

DFB_CLOSE_BOX:
	LD DE,STR_TAB_SELECT_HINT
	JP PRINT_STR

;------------------------------------------------------------------------------
; FINISH_UI_PAGE_AND_STATUS: Render bottom padding and modal navigation status
;
; Purpose:
;   Draws remaining vertical blank lines, bottom horizontal rule border, and
;   navigation hotkey help line ("Enter: Select | Esc: Cancel | PgUp/PgDn...").
;
; Call Usage / Protocol:
;   Called via CALL at conclusion of modal page rendering.
;
; Inputs:
;   None.
;
; Outputs:
;   Dialog footer emitted to terminal.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
FINISH_UI_PAGE_AND_STATUS:
	; Print CRLF after the prompt box
	LD A,13
	CALL PUTC
	LD A,10
	CALL PUTC

	; Fill remaining rows down to ACTIVE_ROWS - 1 with '~'
	LD A,(ACTIVE_ROWS)
	DEC A				; A = ACTIVE_ROWS - 1 (last content row)
	LD HL,UI_CUR_ROW
	SUB (HL)
	JR Z,FUPS_STATUS
	JR C,FUPS_STATUS
	LD B,A
FUPS_TILDE_LOOP:
	CALL PRINT_TILDE_CRLF
	DJNZ FUPS_TILDE_LOOP

FUPS_STATUS:
	CALL RENDER_STATUS_BAR

	; Reposition cursor inside filename input box on UI_CUR_ROW
	LD A,(INPUT_BUF_LEN)
	CALL LOCATE_INPUT_BOX_OFFSET_A
	JP TERM_SHOW_CURSOR

LOCATE_INPUT_BOX_OFFSET_A:
	; A = character offset inside filename text box (0..20)
	LD C,A
	LD A,(IS_BLOCK_INSERT_UI)
	OR A
	LD A,29
	JR NZ,LIBO_ADD
	LD A,(IS_PLUGIN_LOAD_UI)
	OR A
	LD A,28
	JR NZ,LIBO_ADD
	LD A,27
LIBO_ADD:
	LD HL,DIR_LEFT_PAD
	ADD A,(HL)
	ADD A,C
	LD L,A
	LD A,(UI_CUR_ROW)
	LD H,A
	JP LOCATE_RC

;------------------------------------------------------------------------------
; LOCATE_RC: Position terminal cursor with boundary clamping
;
; Purpose:
;   Validates 0-based row in B and column in C against active terminal bounds
;   (clamping if necessary) and emits VT100 cursor positioning escape sequence.
;
; Call Usage / Protocol:
;   Called via CALL throughout modal UI dialog rendering and input loops.
;
; Inputs:
;   B = Row index (0-based).
;   C = Column index (0-based).
;
; Outputs:
;   VT100 escape sequence emitted; cursor repositioned.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
LOCATE_RC:
	PUSH BC
	PUSH DE
	PUSH HL

	; Clamp Row H to [1 .. ACTIVE_ROWS]
	LD A,H
	OR A
	JR NZ,LRC_ROW_MIN_OK
	INC H				; H = 1 if 0
LRC_ROW_MIN_OK:
	LD A,(ACTIVE_ROWS)
	CP H				; Carry=1 if ACTIVE_ROWS < H
	JR NC,LRC_ROW_OK
	LD H,A				; Clamp H = ACTIVE_ROWS
LRC_ROW_OK:

	; Clamp Col L to [1 .. ACTIVE_COLS]
	LD A,L
	OR A
	JR NZ,LRC_COL_MIN_OK
	INC L				; L = 1 if 0
LRC_COL_MIN_OK:
	LD A,(ACTIVE_COLS)
	CP L				; Carry=1 if ACTIVE_COLS < L
	JR NC,LRC_COL_OK
	LD L,A				; Clamp L = ACTIVE_COLS
LRC_COL_OK:

	LD A,27
	CALL PUTC
	LD A,'['
	CALL PUTC
	LD A,H
	CALL PRINT_DEC_BYTE
	LD A,';'
	CALL PUTC
	LD A,L
	CALL PRINT_DEC_BYTE
	LD A,'H'
	CALL PUTC
	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; READ_FILENAME_INPUT_PREFILLED: Interactive entry with prefilled filename
;
; Purpose:
;   Alternative entry point to READ_FILENAME_INPUT when INPUT_FILENAME_BUF is
;   already populated; positions cursor at the end of the prefilled string.
;
; Call Usage / Protocol:
;   Called via CALL when opening Save As dialog with active document filename.
;
; Inputs:
;   INPUT_FILENAME_BUF populated with initial filename string.
;
; Outputs:
;   Carry = 0 on Enter; Carry = 1 on Esc.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
READ_FILENAME_INPUT_PREFILLED:
	XOR A
	LD (SHOWING_FNF_MSG),A
	LD A,(INPUT_BUF_LEN)
	LD (INPUT_CURSOR_POS),A
	LD A,(DIR_HL_AUTO_MODE)
	OR A
	JP NZ,INPUT_AUTO_DIR_NAV
	JR INPUT_CHAR_LOOP

INPUT_CHAR_LOOP:
	CALL GET_KEY
	CALL CHECK_CLEAR_FNF

	; Ctrl-F -> Toggle Save Format (Save Screen only)
	CP KEY_CTRL_F
	JR NZ,CHECK_ESC_KEY
	LD A,(IS_SAVE_UI)
	OR A
	JR Z,INPUT_CHAR_LOOP		; Ignore Ctrl-F in Open Screen
	LD A,(SAVE_FORMAT)
	XOR 1			; Toggle between FMT_CPM (0) and FMT_LINUX (1)
	LD (SAVE_FORMAT),A
	LD A,2				; A = 2 (Format toggled)
	SCF				; Carry = 1 (special action)
	RET

CHECK_ESC_KEY:
	CP KEY_ESC
	JP NZ,INPUT_CHECK_PAGE_KEYS

	; Check if character follows ESC within a short timeout
	LD BC,ESC_TIMEOUT_LOOPS
INPUT_WAIT_ESC:
	CALL CHECK_KEY_READY
	JR NZ,INPUT_GOT_ESC_BYTE
	DEC BC
	LD A,B
	OR C
	JR NZ,INPUT_WAIT_ESC

	; Standalone ESC key -> Cancel
	JP INPUT_CANCEL

INPUT_GOT_ESC_BYTE:
	CALL GET_KEY
	CP '['
	JR Z,INPUT_HANDLE_CSI
	CP 'O'
	JR Z,INPUT_HANDLE_SS3
	JP INPUT_CHAR_LOOP

INPUT_HANDLE_CSI:
	CALL GET_KEY
	CP 'D'				; Left Arrow (ESC [ D)
	JP Z,INPUT_CURSOR_LEFT
	CP 'C'				; Right Arrow (ESC [ C)
	JP Z,INPUT_CURSOR_RIGHT
	CP 'H'				; Home (ESC [ H)
	JP Z,INPUT_CURSOR_HOME
	CP 'F'				; End (ESC [ F)
	JP Z,INPUT_CURSOR_END
	CP '1'				; Home (ESC [ 1 ~)
	JR Z,INPUT_CSI_HOME_TILDE
	CP '4'				; End (ESC [ 4 ~)
	JR Z,INPUT_CSI_END_TILDE
	CP '7'				; Home (ESC [ 7 ~)
	JR Z,INPUT_CSI_HOME_TILDE
	CP '8'				; End (ESC [ 8 ~)
	JR Z,INPUT_CSI_END_TILDE
	CP '3'				; Delete key (ESC [ 3 ~)
	JR Z,INPUT_CSI_DEL
	CP '2'				; Insert key (ESC [ 2 ~)
	JR Z,INPUT_CSI_INS
	CP '5'				; Page Up (ESC [ 5 ~)
	JR Z,INPUT_CSI_PGUP
	CP '6'				; Page Down (ESC [ 6 ~)
	JR Z,INPUT_CSI_PGDN
	CP 'I'				; Page Up (VT alt)
	JR Z,INPUT_DO_PGUP
	CP 'G'				; Page Down (VT alt)
	JR Z,INPUT_DO_PGDN
	CP 'L'				; VT102 Insert line
	JP Z,INPUT_CHAR_LOOP
	CP '@'				; ICH Insert char
	JP Z,INPUT_CHAR_LOOP
	JP INPUT_CHAR_LOOP

INPUT_CSI_HOME_TILDE:
	CALL GET_KEY			; Consume trailing '~'
	JP INPUT_CURSOR_HOME

INPUT_CSI_END_TILDE:
	CALL GET_KEY			; Consume trailing '~'
	JP INPUT_CURSOR_END

INPUT_CSI_DEL:
	CALL GET_KEY			; Consume trailing '~'
	JP INPUT_DEL_CHAR

INPUT_CSI_INS:
	CALL GET_KEY			; Consume trailing '~'
	JP INPUT_CHAR_LOOP

INPUT_CSI_PGUP:
	CALL GET_KEY			; Consume trailing '~'
INPUT_DO_PGUP:
	LD A,3				; A = 3 (Previous Page / PgUp)
	SCF				; Carry = 1
	RET

INPUT_CSI_PGDN:
	CALL GET_KEY			; Consume trailing '~'
INPUT_DO_PGDN:
	LD A,1				; A = 1 (Next Page / PgDn)
	SCF				; Carry = 1
	RET

INPUT_HANDLE_SS3:
	CALL GET_KEY
	CP 'D'				; Left Arrow (ESC O D)
	JP Z,INPUT_CURSOR_LEFT
	CP 'C'				; Right Arrow (ESC O C)
	JP Z,INPUT_CURSOR_RIGHT
	CP 'H'				; Home (ESC O H)
	JP Z,INPUT_CURSOR_HOME
	CP 'F'				; End (ESC O F)
	JP Z,INPUT_CURSOR_END
	JP INPUT_CHAR_LOOP

INPUT_CHECK_PAGE_KEYS:
	; Ctrl+U -> Page Up
	CP KEY_CTRL_U
	JR Z,INPUT_DO_PGUP

	; Ctrl+V -> Page Down
	CP KEY_CTRL_V
	JR Z,INPUT_DO_PGDN

	; Canonical control keys (Ctrl+A Home, Ctrl+E End, Ctrl+D Delete)
	CP KEY_CTRL_A			; Ctrl+A -> Home
	JP Z,INPUT_CURSOR_HOME
	CP KEY_CTRL_E			; Ctrl+E -> End
	JP Z,INPUT_CURSOR_END
	CP KEY_CTRL_D			; Ctrl+D -> Delete char at cursor
	JP Z,INPUT_DEL_CHAR

CHECK_ENTER_KEY:
	; Tab -> Enter directory highlight bar navigation mode
	CP KEY_TAB
	JP Z,INPUT_TAB_TO_DIR_NAV

	; Enter -> Finish input or advance page if empty
	CP KEY_ENTER
	JP Z,INPUT_ENTER

	; Backspace / Delete
	CP KEY_BACKSPACE
	JP Z,INPUT_BS
	CP KEY_DEL
	JP Z,INPUT_BS

	; Printable character (0x20..0x7E)
	CP ' '
	JP C,INPUT_CHAR_LOOP
	CP 07FH
	JP NC,INPUT_CHAR_LOOP

	; Check buffer capacity (max 20 chars)
	LD (INPUT_CHAR_TEMP),A
	LD A,(INPUT_BUF_LEN)
	CP 20
	JP NC,INPUT_CHAR_LOOP

	; Check if cursor is at end of string or inside text
	LD A,(INPUT_CURSOR_POS)
	LD HL,INPUT_BUF_LEN
	CP (HL)
	JR NZ,INPUT_INSERT_MIDDLE

	; Appending at end:
	LD HL,INPUT_FILENAME_BUF
	LD E,A
	LD D,0
	ADD HL,DE
	LD A,(INPUT_CHAR_TEMP)
	LD (HL),A
	INC HL
	LD (HL),0			; Null-terminate

	LD HL,INPUT_BUF_LEN
	INC (HL)
	LD HL,INPUT_CURSOR_POS
	INC (HL)

	; Echo character
	LD A,(INPUT_CHAR_TEMP)
	CALL PUTC
	JP INPUT_CHAR_LOOP

INPUT_INSERT_MIDDLE:
	; Shift bytes right from INPUT_CURSOR_POS to INPUT_BUF_LEN
	; Source end: HL = INPUT_FILENAME_BUF + INPUT_BUF_LEN
	; Dest end:   DE = INPUT_FILENAME_BUF + INPUT_BUF_LEN + 1
	; Count:      BC = INPUT_BUF_LEN - INPUT_CURSOR_POS + 1
	LD A,(INPUT_BUF_LEN)
	LD E,A
	LD D,0
	LD HL,INPUT_FILENAME_BUF
	ADD HL,DE			; HL = Source end
	LD D,H
	LD E,L
	INC DE				; DE = Dest end: HL + 1

	LD A,(INPUT_BUF_LEN)
	LD C,A
	LD A,(INPUT_CURSOR_POS)
	SUB C				; A = P - L
	NEG				; A = L - P
	INC A				; +1 for null byte
	LD C,A
	LD B,0
	LDDR

	; Store character at INPUT_FILENAME_BUF + INPUT_CURSOR_POS
	LD A,(INPUT_CURSOR_POS)
	LD E,A
	LD D,0
	LD HL,INPUT_FILENAME_BUF
	ADD HL,DE
	LD A,(INPUT_CHAR_TEMP)
	LD (HL),A

	; Increment length and cursor position
	LD HL,INPUT_BUF_LEN
	INC (HL)
	LD HL,INPUT_CURSOR_POS
	INC (HL)

	; Echo character (screen cursor moves to new INPUT_CURSOR_POS)
	LD A,(INPUT_CHAR_TEMP)
	CALL PUTC

	; Refresh remaining box from new cursor position
	CALL REFRESH_BOX_FROM_CURSOR
	JP INPUT_CHAR_LOOP

INPUT_CURSOR_LEFT:
	LD A,(INPUT_CURSOR_POS)
	OR A
	JP Z,INPUT_CHAR_LOOP		; At col 0 -> ignore

	DEC A
	LD (INPUT_CURSOR_POS),A
	LD A,008H
	CALL PUTC
	JP INPUT_CHAR_LOOP

INPUT_CURSOR_RIGHT:
	LD A,(INPUT_CURSOR_POS)
	LD HL,INPUT_BUF_LEN
	CP (HL)
	JP NC,INPUT_CHAR_LOOP		; At end -> ignore

	; Advance cursor on screen by printing current character
	LD HL,INPUT_FILENAME_BUF
	LD E,A
	LD D,0
	ADD HL,DE
	LD A,(HL)
	CALL PUTC

	LD HL,INPUT_CURSOR_POS
	INC (HL)
	JP INPUT_CHAR_LOOP

;------------------------------------------------------------------------------
; INPUT_CURSOR_HOME: Move input cursor to beginning of filename text box
;
; Purpose:
;   Resets input cursor column index to 0 and emits VT100 backspace sequences
;   to reposition hardware cursor at the start of the input box.
;
; Call Usage / Protocol:
;   Called via jump/dispatch within READ_FILENAME_INPUT on Home key / Ctrl+A.
;
; Inputs:
;   None.
;
; Outputs:
;   Cursor moved to start of input box.
;
; Preserves / Modifies:
;   Clobbers AF, B.
;------------------------------------------------------------------------------
INPUT_CURSOR_HOME:
	LD A,(INPUT_CURSOR_POS)
	OR A
	JP Z,INPUT_CHAR_LOOP

	LD B,A
	XOR A
	LD (INPUT_CURSOR_POS),A
ICH_BS_LOOP:
	LD A,008H
	CALL PUTC
	DJNZ ICH_BS_LOOP
	JP INPUT_CHAR_LOOP

;------------------------------------------------------------------------------
; INPUT_CURSOR_END: Move input cursor to end of text in filename text box
;
; Purpose:
;   Sets input cursor column index to string length and advances hardware
;   cursor to point immediately following last character in input box.
;
; Call Usage / Protocol:
;   Called via jump/dispatch within READ_FILENAME_INPUT on End key / Ctrl+E.
;
; Inputs:
;   None.
;
; Outputs:
;   Cursor positioned at end of text.
;
; Preserves / Modifies:
;   Clobbers AF, B.
;------------------------------------------------------------------------------
INPUT_CURSOR_END:
	CALL INPUT_MOVE_CURSOR_TO_END
	JP INPUT_CHAR_LOOP

;------------------------------------------------------------------------------
; INPUT_DEL_CHAR: Delete character at cursor in filename text box
;
; Purpose:
;   Deletes character at active cursor position within INPUT_FILENAME_BUF,
;   shifts remaining string characters left by one byte, and refreshes box.
;
; Call Usage / Protocol:
;   Called via jump/dispatch within READ_FILENAME_INPUT on Del key / Ctrl+D.
;
; Inputs:
;   Active cursor offset in INPUT_FILENAME_BUF.
;
; Outputs:
;   Character deleted; buffer and screen display updated.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
INPUT_DEL_CHAR:
	LD A,(INPUT_CURSOR_POS)
	LD HL,INPUT_BUF_LEN
	CP (HL)
	JP NC,INPUT_CHAR_LOOP		; Nothing at/past cursor to delete

DO_DELETE_CHAR_AT_CURSOR:
	; Decrement INPUT_BUF_LEN
	LD HL,INPUT_BUF_LEN
	DEC (HL)

	; Shift bytes left from (INPUT_CURSOR_POS + 1) to INPUT_BUF_LEN
	; Dest:   DE = INPUT_FILENAME_BUF + INPUT_CURSOR_POS
	; Source: HL = INPUT_FILENAME_BUF + INPUT_CURSOR_POS + 1
	; Count:  BC = INPUT_BUF_LEN - INPUT_CURSOR_POS + 1 (null included)
	LD A,(INPUT_CURSOR_POS)
	LD E,A
	LD D,0
	LD HL,INPUT_FILENAME_BUF
	ADD HL,DE
	EX DE,HL			; DE = Dest
	LD H,D
	LD L,E
	INC HL				; HL = Source (DE + 1)

	LD A,(INPUT_BUF_LEN)
	LD C,A
	LD A,(INPUT_CURSOR_POS)
	SUB C				; A = P - L
	NEG				; A = L - P
	INC A				; +1 for null byte
	LD C,A
	LD B,0
	LDIR

	; Redraw box from cursor position
	CALL REFRESH_BOX_FROM_CURSOR
	JP INPUT_CHAR_LOOP

INPUT_BS:
	LD A,(INPUT_CURSOR_POS)
	OR A
	JP Z,INPUT_CHAR_LOOP		; At col 0 -> nothing to backspace

	DEC A
	LD (INPUT_CURSOR_POS),A

	; Move terminal cursor left 1 column
	LD A,008H
	CALL PUTC

	; Fall through to delete character at updated INPUT_CURSOR_POS
	JR DO_DELETE_CHAR_AT_CURSOR

;------------------------------------------------------------------------------
; REFRESH_BOX_FROM_CURSOR: Redraw filename input box from cursor to end
;
; Purpose:
;   Repaints remaining characters of INPUT_FILENAME_BUF starting from current
;   cursor offset, clears trailing space up to box width, and restores cursor.
;
; Call Usage / Protocol:
;   Called via CALL after character insertion or deletion in input box.
;
; Inputs:
;   Cursor offset in INPUT_FILENAME_BUF.
;
; Outputs:
;   Input box refreshed on screen.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
REFRESH_BOX_FROM_CURSOR:
	PUSH BC
	PUSH DE
	PUSH HL

	; 1. Print characters from INPUT_CURSOR_POS to INPUT_BUF_LEN
	LD A,(INPUT_CURSOR_POS)
	LD E,A
	LD D,0
	LD HL,INPUT_FILENAME_BUF
	ADD HL,DE			; HL = pointer to current char
	LD A,(INPUT_BUF_LEN)
	SUB E				; A = INPUT_BUF_LEN - INPUT_CURSOR_POS
	JR Z,RBFC_SPACES		; If past text, jump to spaces
	LD B,A
RBFC_CHAR_LOOP:
	LD A,(HL)
	CALL PUTC
	INC HL
	DJNZ RBFC_CHAR_LOOP

RBFC_SPACES:
	; 2. Print spaces from INPUT_BUF_LEN to 20: (20 - INPUT_BUF_LEN)
	LD A,20
	LD HL,INPUT_BUF_LEN
	SUB (HL)			; A = 20 - INPUT_BUF_LEN
	JR Z,RBFC_MOVE_BACK
	LD B,A
RBFC_SPACE_LOOP:
	LD A,' '
	CALL PUTC
	DJNZ RBFC_SPACE_LOOP

RBFC_MOVE_BACK:
	; 3. Emit (20 - INPUT_CURSOR_POS) backspaces to return to cursor
	LD A,20
	LD HL,INPUT_CURSOR_POS
	SUB (HL)			; A = 20 - INPUT_CURSOR_POS
	JR Z,RBFC_DONE
	LD B,A
RBFC_BS_LOOP:
	LD A,008H
	CALL PUTC
	DJNZ RBFC_BS_LOOP

RBFC_DONE:
	POP HL
	POP DE
	POP BC
	RET

;------------------------------------------------------------------------------
; INPUT_MOVE_CURSOR_TO_END: Advance hardware cursor to end of input string
;
; Purpose:
;   Emits forward cursor movement escape sequences or characters to position
;   terminal cursor at end of text in INPUT_FILENAME_BUF.
;
; Call Usage / Protocol:
;   Called via CALL from READ_FILENAME_INPUT_PREFILLED.
;
; Inputs:
;   INPUT_FILENAME_BUF length.
;
; Outputs:
;   Cursor positioned at end of text.
;
; Preserves / Modifies:
;   Clobbers AF, B.
;------------------------------------------------------------------------------
INPUT_MOVE_CURSOR_TO_END:
	LD A,(INPUT_CURSOR_POS)
	LD HL,INPUT_BUF_LEN
	CP (HL)
	RET NC				; Already at/past end

	LD B,(HL)
	SUB B
	NEG				; A = INPUT_BUF_LEN - INPUT_CURSOR_POS
	LD B,A
	LD A,(INPUT_CURSOR_POS)
	LD HL,INPUT_FILENAME_BUF
	LD E,A
	LD D,0
	ADD HL,DE
IMCTE_LOOP:
	LD A,(HL)
	CALL PUTC
	INC HL
	DJNZ IMCTE_LOOP
	LD A,(INPUT_BUF_LEN)
	LD (INPUT_CURSOR_POS),A
	RET

;------------------------------------------------------------------------------
; CHECK_CLEAR_FNF: Clear File-Not-Found error indicator on user keystroke
;
; Purpose:
;   Tests whether a previous "File Not Found" error banner is active on screen;
;   if so, erases error message and restores normal dialog status bar.
;
; Call Usage / Protocol:
;   Called via CALL on every keystroke received in READ_FILENAME_INPUT.
;
; Inputs:
;   None.
;
; Outputs:
;   Error banner cleared if previously visible.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
CHECK_CLEAR_FNF:
	RET

;------------------------------------------------------------------------------
; INPUT_CANCEL: Handle cancellation of filename input dialog
;
; Purpose:
;   Sets Carry flag to indicate user cancelled input dialog (via Esc key),
;   performing necessary cleanup before returning to caller.
;
; Call Usage / Protocol:
;   Jumped to from READ_FILENAME_INPUT on Esc key press.
;
; Inputs:
;   None.
;
; Outputs:
;   Carry = 1 indicating cancellation.
;
; Preserves / Modifies:
;   Clobbers AF.
;------------------------------------------------------------------------------
INPUT_CANCEL:
	XOR A				; A = 0 (cancel)
	LD (SHOWING_FNF_MSG),A
	SCF				; Carry = 1
	RET

INPUT_ENTER:
	LD A,(INPUT_BUF_LEN)
	OR A
	JR Z,INPUT_ENTER_EMPTY		; Empty string on Enter

	; Non-empty string: advance cursor to end of text
	CALL INPUT_MOVE_CURSOR_TO_END
	OR A				; Carry = 0 (success)
	RET

INPUT_ENTER_EMPTY:
	JP INPUT_CANCEL

;------------------------------------------------------------------------------
; Directory Highlight Bar Navigation Mode (Tab from Filename Text Box)
;------------------------------------------------------------------------------
INPUT_AUTO_DIR_NAV:
	LD B,A				; B = 1 (top-left) or 2 (bottom-right)
	XOR A
	LD (DIR_HL_AUTO_MODE),A
	LD A,(DIR_PAGE_FILE_CNT)
	OR A
	JP Z,INPUT_CHAR_LOOP
	DEC B
	JR Z,ITDN_SET_TOP_LEFT
	DEC A				; A = DIR_PAGE_FILE_CNT - 1 (last file)
	JR ITDN_HAVE_INDEX

INPUT_TAB_TO_DIR_NAV:
	LD A,(DIR_PAGE_FILE_CNT)
	OR A
	JP Z,INPUT_CHAR_LOOP		; No files on page -> stay in text box
ITDN_SET_TOP_LEFT:
	XOR A				; Start at top-left entry (index 0)
ITDN_HAVE_INDEX:
	LD (DIR_HL_INDEX),A
	CALL TERM_HIDE_CURSOR
	LD DE,STR_TAB_EDIT_HINT
	CALL DRAW_TAB_MODE_HINT
	CALL DRAW_HL_ON

DIR_NAV_LOOP:
	CALL GET_KEY

	; Ctrl-F -> Toggle Save Format (Save Screen only)
	CP KEY_CTRL_F
	JR NZ,DNL_CHK_TAB
	LD A,(IS_SAVE_UI)
	OR A
	JR Z,DIR_NAV_LOOP
	CALL TERM_SHOW_CURSOR
	LD A,(SAVE_FORMAT)
	XOR 1
	LD (SAVE_FORMAT),A
	LD A,2
	SCF
	RET

DNL_CHK_TAB:
	CP KEY_TAB
	JR NZ,DNL_CHK_ENTER
	; Tab pressed in highlight mode -> erase highlight and return to box
	CALL DRAW_HL_OFF
	LD DE,STR_TAB_SELECT_HINT
	CALL DRAW_TAB_MODE_HINT
	LD A,(INPUT_CURSOR_POS)
	CALL LOCATE_INPUT_BOX_OFFSET_A
	CALL TERM_SHOW_CURSOR
	JP INPUT_CHAR_LOOP

DNL_CHK_ENTER:
	CP KEY_ENTER
	JR NZ,DNL_CHK_ESC
	; Enter pressed in highlight mode -> accept highlighted filename
	CALL TERM_SHOW_CURSOR
	JP INPUT_ENTER

DNL_CHK_ESC:
	CP KEY_ESC
	JP NZ,DNL_CHK_PAGE_CTRL

	LD BC,ESC_TIMEOUT_LOOPS
DNL_WAIT_ESC:
	CALL CHECK_KEY_READY
	JR NZ,DNL_GOT_ESC_BYTE
	DEC BC
	LD A,B
	OR C
	JR NZ,DNL_WAIT_ESC
	; Standalone ESC -> Cancel dialog
	CALL TERM_SHOW_CURSOR
	JP INPUT_CANCEL

DNL_GOT_ESC_BYTE:
	CALL GET_KEY
	CP '['
	JR Z,DNL_CSI
	CP 'O'
	JR Z,DNL_SS3
	JR DIR_NAV_LOOP

DNL_CSI:
	CALL GET_KEY
	CP 'A'
	JP Z,DNL_MOVE_UP
	CP 'B'
	JP Z,DNL_MOVE_DOWN
	CP 'C'
	JP Z,DNL_MOVE_RIGHT
	CP 'D'
	JP Z,DNL_MOVE_LEFT
	CP '5'
	JR Z,DNL_CSI_PGUP
	CP '6'
	JR Z,DNL_CSI_PGDN
	CP 'I'
	JR Z,DNL_DO_PGUP
	CP 'G'
	JR Z,DNL_DO_PGDN
	JP DIR_NAV_LOOP

DNL_CSI_PGUP:
	CALL GET_KEY
DNL_DO_PGUP:
	LD A,(DIR_PAGE_COUNT)
	CP 2
	JP C,DIR_NAV_LOOP		; Single page -> stay on current file
	LD A,2				; 2 = auto-highlight bottom-right file
	LD (DIR_HL_AUTO_MODE),A
	JP INPUT_DO_PGUP

DNL_CSI_PGDN:
	CALL GET_KEY
DNL_DO_PGDN:
	LD A,(DIR_PAGE_COUNT)
	CP 2
	JP C,DIR_NAV_LOOP		; Single page -> stay on current file
	LD A,1				; 1 = auto-highlight top-left file
	LD (DIR_HL_AUTO_MODE),A
	JP INPUT_DO_PGDN

DNL_SS3:
	CALL GET_KEY
	CP 'A'
	JR Z,DNL_MOVE_UP
	CP 'B'
	JR Z,DNL_MOVE_DOWN
	CP 'C'
	JR Z,DNL_MOVE_RIGHT
	CP 'D'
	JR Z,DNL_MOVE_LEFT
	JP DIR_NAV_LOOP

DNL_CHK_PAGE_CTRL:
	CP KEY_CTRL_U
	JR Z,DNL_DO_PGUP
	CP KEY_CTRL_V
	JR Z,DNL_DO_PGDN
	JP DIR_NAV_LOOP

DNL_MOVE_LEFT:
	LD A,(DIR_HL_INDEX)
	OR A
	JP Z,DIR_NAV_LOOP
	DEC A
	JR DNL_UPDATE_INDEX

DNL_MOVE_RIGHT:
	LD A,(DIR_HL_INDEX)
	INC A
	LD HL,DIR_PAGE_FILE_CNT
	CP (HL)
	JP NC,DIR_NAV_LOOP
	JR DNL_UPDATE_INDEX

DNL_MOVE_UP:
	LD A,(DIR_HL_INDEX)
	LD HL,DIR_COLS_PER_ROW
	SUB (HL)
	JP C,DIR_NAV_LOOP
	JR DNL_UPDATE_INDEX

DNL_MOVE_DOWN:
	LD A,(DIR_HL_INDEX)
	LD HL,DIR_COLS_PER_ROW
	ADD A,(HL)
	LD HL,DIR_PAGE_FILE_CNT
	CP (HL)
	JP NC,DIR_NAV_LOOP

DNL_UPDATE_INDEX:
	PUSH AF
	CALL DRAW_HL_OFF
	POP AF
	LD (DIR_HL_INDEX),A
	CALL DRAW_HL_ON
	JP DIR_NAV_LOOP

DRAW_TAB_MODE_HINT:
	PUSH DE
	LD A,20				; Offset 20 is the closing ']'
	CALL LOCATE_INPUT_BOX_OFFSET_A
	POP DE
	JP PRINT_STR

DRAW_HL_OFF:
	CALL PREP_HL_CELL
	LD A,12
	JP PRINT_PADDED_ENTRY_A

DRAW_HL_ON:
	CALL PREP_HL_CELL
	CALL TERM_INVERSE_ON
	LD A,12
	CALL PRINT_PADDED_ENTRY_A
	CALL TERM_INVERSE_OFF

	; Auto-fill filename text box with highlighted filename
	CALL PRELOAD_DRIVE_USER_PREFIX
	LD A,(CURRENT_DIR_IS_FAT)
	OR A
	JR Z,DHO_APPEND_NAME
	; In FAT mode, replace buffer directly with entry name
	LD DE,INPUT_FILENAME_BUF
	LD C,0
DHO_APPEND_NAME:
	LD HL,LOAD_LINE_TEMP
DHO_COPY_LOOP:
	LD A,(HL)
	OR A
	JR Z,DHO_COPY_DONE
	LD (DE),A
	INC HL
	INC DE
	INC C
	JR DHO_COPY_LOOP
DHO_COPY_DONE:
	XOR A
	LD (DE),A
	LD (INPUT_CURSOR_POS),A
	LD A,C
	LD (INPUT_BUF_LEN),A

	; Redraw filename text box contents in-place
	XOR A
	CALL LOCATE_INPUT_BOX_OFFSET_A
	CALL REFRESH_BOX_FROM_CURSOR
	LD A,(INPUT_BUF_LEN)
	LD (INPUT_CURSOR_POS),A
	RET

PREP_HL_CELL:
	; Locate cursor at (DIR_HL_INDEX) grid cell and format entry into
	; LOAD_LINE_TEMP
	LD A,(DIR_HL_INDEX)
	LD B,0
	LD HL,DIR_COLS_PER_ROW
	LD C,(HL)
PHC_DIV_LOOP:
	CP C
	JR C,PHC_DIV_DONE
	SUB C
	INC B
	JR PHC_DIV_LOOP
PHC_DIV_DONE:
	; B = row_offset, A = col_offset
	LD C,A
	LD A,(DIR_TOP_PAD_COUNT)
	ADD A,4
	ADD A,B
	LD H,A				; H = 1-based screen row

	LD A,(DIR_COL_WIDTH)
	LD D,A
	LD A,C
	OR A
	LD A,0
	JR Z,PHC_MUL_DONE
	LD B,C
PHC_MUL_LOOP:
	ADD A,D
	DJNZ PHC_MUL_LOOP
PHC_MUL_DONE:
	LD B,A
	LD A,(DIR_LEFT_PAD)
	ADD A,2
	ADD A,B
	LD L,A				; L = 1-based screen col
	CALL LOCATE_RC

	LD A,(DIR_START_FILE)
	LD HL,DIR_HL_INDEX
	ADD A,(HL)
	CALL CALC_ENTRY_PTR_A
	JP FORMAT_DIR_ENTRY_HL

;------------------------------------------------------------------------------
; PARSE_OPEN_LINE_NUM: Parse optional ":<line>" suffix from filename string
;
; Purpose:
;   Scans filename string for trailing line number suffix (e.g. "MAIN.C:142"),
;   parses decimal line number into HL, and truncates string at the colon.
;
; Call Usage / Protocol:
;   Called via CALL after filename is entered in Open File dialog.
;
; Inputs:
;   DE = Pointer to null-terminated filename string.
;
; Outputs:
;   HL = Parsed 1-based line number (or 0 if no suffix); string truncated.
;
; Preserves / Modifies:
;   Clobbers AF, BC, DE, HL.
;------------------------------------------------------------------------------
PARSE_OPEN_LINE_NUM:
	LD HL,0
	LD (OPEN_GOTO_LINE),HL

	LD A,(INPUT_BUF_LEN)
	OR A
	RET Z				; Empty buffer

	; HL = pointer to end of input buffer: INPUT_FILENAME_BUF + length - 1
	LD E,A
	LD D,0
	LD HL,INPUT_FILENAME_BUF
	ADD HL,DE
	DEC HL				; HL points to last char of input

	; Trim trailing spaces
POLN_TRIM_SPACES:
	LD A,(HL)
	CP ' '
	JR NZ,POLN_CHECK_DIGITS
	DEC HL
	DEC E
	JR NZ,POLN_TRIM_SPACES
	RET				; Only spaces found

POLN_CHECK_DIGITS:
	; Last non-space character must be a digit '0'..'9'
	LD A,(HL)
	CP '0'
	RET C
	CP '9'+1
	RET NC

	; Scan backwards past all digits to find preceding ':'
POLN_SCAN_BACK:
	DEC HL
	DEC E
	RET Z				; Hit start of buffer without ':'
	LD A,(HL)
	CP ':'
	JR Z,POLN_FOUND_COLON
	CP '0'
	JR C,POLN_NOT_NUM
	CP '9'+1
	JR C,POLN_SCAN_BACK
POLN_NOT_NUM:
	RET

POLN_FOUND_COLON:
	; HL points to ':' in INPUT_FILENAME_BUF. Check if this colon is inside
	; a drive/user prefix.
	PUSH HL				; Save colon pointer
	LD HL,INPUT_FILENAME_BUF
	CALL PARSE_DRIVE_USER_PREFIX
	JR NC,POLN_IS_LINE_COLON	; No prefix at start -> line colon

	; Prefix matched: HL is now past the prefix colon!
	POP DE				; DE = colon pointer
	PUSH DE
	LD A,D
	CP H
	JR NZ,POLN_CMP
	LD A,E
	CP L
POLN_CMP:
	JR C,POLN_IS_DRIVE_COLON	; DE < HL -> colon is part of prefix!

POLN_IS_LINE_COLON:
	POP HL				; Restore colon pointer
	INC HL				; HL points to digits
	CALL PARSE_DEC_WORD		; DE = 16-bit parsed value
	LD (OPEN_GOTO_LINE),DE
	RET

POLN_IS_DRIVE_COLON:
	POP HL				; Restore colon pointer
	RET

;------------------------------------------------------------------------------
; PARSE_FILENAME_TO_FCB: Parse filename string into WORK_FCB
;
; Purpose:
;   Initializes destination pointer HL to WORK_FCB and delegates to
;   PARSE_STRING_TO_FCB to parse filename, drive, and user prefix.
;
; Call Usage / Protocol:
;   Called via CALL from file open and save command handlers.
;
; Inputs:
;   DE = Pointer to filename string.
;
; Outputs:
;   WORK_FCB populated; Carry = 0 on success.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
PARSE_FILENAME_TO_FCB:
	LD HL,INPUT_FILENAME_BUF

;------------------------------------------------------------------------------
; PARSE_STRING_TO_FCB: Parse filename string into standard CP/M FCB
;
; Purpose:
;   Parses drive letter, optional user area, 8-char filename, and 3-character
;   extension from string at DE into 36-byte CP/M FCB structure at HL.
;
; Call Usage / Protocol:
;   Called via CALL from PARSE_FILENAME_TO_FCB and overlay loaders.
;
; Inputs:
;   DE = Pointer to null-terminated source string.
;   HL = Pointer to 36-byte destination FCB buffer.
;
; Outputs:
;   FCB populated; Carry = 0 on success, Carry = 1 on syntax error.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
PARSE_STRING_TO_FCB:
	PUSH HL

	; Clear WORK_FCB (36 bytes of 0)
	LD HL,WORK_FCB
	LD (HL),0
	LD DE,WORK_FCB+1
	LD BC,35
	LDIR

	; Fill filename (bytes 1..8) and ext (bytes 9..11) with spaces
	LD HL,WORK_FCB+1
	LD B,11
FILL_FCB_SPACES:
	LD (HL),' '
	INC HL
	DJNZ FILL_FCB_SPACES

	POP HL

	; Skip leading spaces
PARSE_SKIP_SPACES:
	LD A,(HL)
	CP ' '
	JR NZ,PARSE_CHECK_PREFIX
	INC HL
	JR PARSE_SKIP_SPACES

PARSE_CHECK_PREFIX:
	CALL PARSE_DRIVE_USER_PREFIX
	JR NC,PARSE_NO_PREFIX

	; Prefix matched!
	; Check drive
	LD A,(PREFIX_DRIVE)
	OR A
	JR NZ,PSTF_USE_PDRIVE
	LD A,(CURRENT_DIR_DRIVE)
PSTF_USE_PDRIVE:
	LD (WORK_FCB),A

	; Check user
	LD A,(PREFIX_USER)
	CP 0FFH
	JR NZ,PSTF_USE_PUSER
	LD A,(CURRENT_DIR_USER)
PSTF_USE_PUSER:
	LD (WORK_FCB_USER),A
	JR PARSE_NAME_START

PARSE_NO_PREFIX:
	LD A,(CURRENT_DIR_DRIVE)
	LD (WORK_FCB),A
	LD A,(CURRENT_DIR_USER)
	LD (WORK_FCB_USER),A

PARSE_NAME_START:
	; Read up to 8 characters of filename into WORK_FCB+1 .. WORK_FCB+8
	LD DE,WORK_FCB+1
	LD B,8
PARSE_NAME_LOOP:
	LD A,(HL)
	OR A
	RET Z				; End of string
	CP ' '
	RET Z
	CP ':'
	RET Z
	CP '.'
	JR Z,PARSE_EXT_START
	CALL TO_UPPER
	LD (DE),A
	INC HL
	INC DE
	DJNZ PARSE_NAME_LOOP

	; If more than 8 chars before '.', skip to '.'
PARSE_SKIP_TO_DOT:
	LD A,(HL)
	OR A
	RET Z
	CP ' '
	RET Z
	CP ':'
	RET Z
	CP '.'
	JR Z,PARSE_EXT_START
	INC HL
	JR PARSE_SKIP_TO_DOT

PARSE_EXT_START:
	INC HL				; Skip '.'
	LD DE,WORK_FCB+9
	LD B,3
PARSE_EXT_LOOP:
	LD A,(HL)
	OR A
	RET Z
	CP ' '
	RET Z
	CP ':'
	RET Z
	CALL TO_UPPER
	LD (DE),A
	INC HL
	INC DE
	DJNZ PARSE_EXT_LOOP
	RET

;------------------------------------------------------------------------------
; TO_UPPER: Convert lowercase ASCII character to uppercase
;
; Purpose:
;   Checks if ASCII character in A is between 'a' and 'z'; if so, converts it
;   to uppercase ('A'..'Z') by subtracting 20H (AND 0DFH).
;
; Call Usage / Protocol:
;   Called via CALL extensively throughout string parsers and command loops.
;
; Inputs:
;   A = ASCII character to convert.
;
; Outputs:
;   A = Uppercase ASCII character; flags updated.
;
; Preserves / Modifies:
;   Modifies AF; preserves BC, DE, HL.
;------------------------------------------------------------------------------
TO_UPPER:
	CP 'a'
	RET C
	CP 'z'+1
	RET NC
	SUB 020H
	RET

;------------------------------------------------------------------------------
; STR_COPY: Copy null-terminated string from HL to DE
;
; Purpose:
;   Copies characters sequentially from source string at HL to buffer at DE
;   at DE until terminating null byte (0) is copied.
;
; Call Usage / Protocol:
;   Called via CALL for general string copying operations.
;
; Inputs:
;   HL = Pointer to source null-terminated string.
;   DE = Pointer to destination buffer.
;
; Outputs:
;   String copied; HL and DE point past copied null byte.
;
; Preserves / Modifies:
;   Modifies AF, DE, HL; preserves BC.
;------------------------------------------------------------------------------
STR_COPY:
STR_COPY_LOOP:
	LD A,(HL)
	LD (DE),A
	OR A
	RET Z
	INC HL
	INC DE
	JR STR_COPY_LOOP

;------------------------------------------------------------------------------
; SAVE_BLOCK_FILE: Write marked selection block to external disk file
;
; Purpose:
;   Creates or overwrites file specified in WORK_FCB, iterates through lines
;   spanning the marked block (BLOCK_START_ROW to BLOCK_END_ROW), clips text
;   to column boundaries, handles line endings, and flushes DMA sectors.
;
; Call Usage / Protocol:
;   Called via CALL from Block Save command handler.
;
; Inputs:
;   WORK_FCB, BLOCK_START_ROW/COL, BLOCK_END_ROW/COL.
;
; Outputs:
;   Selected block saved to file; Carry = 0 on success, Carry = 1 on error.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SAVE_BLOCK_FILE:
	; Guard: if target drive is hibernated RAM drive, reject save
	CALL CHECK_FCB_IS_HIBERNATED
	JR NC,SAVE_BLK_DRIVE_OK
	SCF
	RET

SAVE_BLK_DRIVE_OK:
	; Set BDOS user area to WORK_FCB_USER
	LD A,(WORK_FCB_USER)
	LD E,A
	LD C,32				; BDOS Set User Area
	CALL BDOS_ENTRY

	; Flush local cache dirty lines first
	CALL FLUSH_DIRTY_CACHE

	LD A,(WORK_FCB+1)
	CP ' '
	JP NZ,DO_SAVE_BLK_EXISTING

	; Zero entire WORK_FCB (36 bytes)
	LD HL,WORK_FCB
	LD (HL),0
	LD DE,WORK_FCB+1
	LD BC,35
	LDIR

	; Copy default filename (0, "OUTPUT  TXT")
	LD HL,DEFAULT_FCB_NAME
	LD DE,WORK_FCB
	LD BC,12
	LDIR

DO_SAVE_BLK_EXISTING:
	; Zero FCB extent and record bytes (bytes 12..35)
	LD HL,WORK_FCB+12
	LD (HL),0
	LD DE,WORK_FCB+13
	LD BC,23
	LDIR

	; Delete old file
	LD DE,WORK_FCB
	LD C,19				; BDOS Delete File
	CALL BDOS_ENTRY

	; Create new file
	LD DE,WORK_FCB
	LD C,22				; BDOS Make File
	CALL BDOS_ENTRY
	CP 0FFH
	JR NZ,MAKE_BLK_FILE_OK

	; Restore BDOS user area to CURRENT_DIR_USER
	LD A,(CURRENT_DIR_USER)
	LD E,A
	LD C,32				; BDOS Set User Area
	CALL BDOS_ENTRY
	SCF
	RET

MAKE_BLK_FILE_OK:
	CALL INIT_SAVE_PROGRESS

	; Prepare DMA write pointer
	LD DE,DEFAULT_DMA
	LD (CUR_DMA_PTR),DE
	LD A,128
	LD (DMA_BYTES_LEFT),A
	LD HL,0
	LD (SAVE_RECORD_NUM),HL

	; Check if block is empty:
	; BLOCK_START_ROW == BLOCK_END_ROW and BLOCK_START_COL == BLOCK_END_COL
	LD HL,(BLOCK_START_ROW)
	LD DE,(BLOCK_END_ROW)
	LD A,H
	CP D
	JR NZ,SBF_NON_EMPTY
	LD A,L
	CP E
	JR NZ,SBF_NON_EMPTY
	LD HL,(BLOCK_START_COL)
	LD DE,(BLOCK_END_COL)
	LD A,H
	CP D
	JR NZ,SBF_NON_EMPTY
	LD A,L
	CP E
	JR NZ,SBF_NON_EMPTY
	; Block is completely empty -> flush and close (0 bytes written)
	JP SAVE_FLUSH_REMAINDER

SBF_NON_EMPTY:
	; Check if single-line or multi-line
	LD HL,(BLOCK_START_ROW)
	LD DE,(BLOCK_END_ROW)
	LD A,H
	CP D
	JP NZ,SBF_MULTILINE
	LD A,L
	CP E
	JP NZ,SBF_MULTILINE

	;---------------------------------------------------------------------
	; Single-Line Block
	;---------------------------------------------------------------------
	LD BC,(BLOCK_START_ROW)
	LD DE,SPLIT_LINE_TEMP
	LD HL,MAX_ACTIVE_LINE_STRIDE-2
	CALL READ_FAR_LINE_MAX

	; Advance HL in SPLIT_LINE_TEMP to BLOCK_START_COL
	LD HL,SPLIT_LINE_TEMP
	LD BC,(BLOCK_START_COL)
SBF_SGL_ADV:
	LD A,B
	OR C
	JR Z,SBF_SGL_AT_START
	LD A,(HL)
	OR A
	JP Z,SAVE_FLUSH_REMAINDER	; Line ended before BLOCK_START_COL
	INC HL
	DEC BC
	JR SBF_SGL_ADV

SBF_SGL_AT_START:
	; Number of chars to stream: BC = BLOCK_END_COL - BLOCK_START_COL
	LD DE,(BLOCK_START_COL)
	LD BC,(BLOCK_END_COL)
	LD A,C
	SUB E
	LD C,A
	LD A,B
	SBC A,D
	LD B,A
	JP C,SAVE_FLUSH_REMAINDER
	OR C
	JP Z,SAVE_FLUSH_REMAINDER

SBF_SGL_STREAM:
	LD A,B
	OR C
	JR Z,SBF_SGL_DONE
	LD A,(HL)
	OR A
	JR Z,SBF_SGL_DONE		; Line ended before BLOCK_END_COL
	CALL WRITE_BYTE_TO_DMA
	INC HL
	DEC BC
	JR SBF_SGL_STREAM

SBF_SGL_DONE:
	CALL WRITE_SAVE_LINE_ENDING
	CALL TICK_SAVE_PROGRESS
	JP SAVE_FLUSH_REMAINDER

	;---------------------------------------------------------------------
	; Multi-Line Block
	;---------------------------------------------------------------------
SBF_MULTILINE:
	; Step 1: Head row (BLOCK_START_ROW), from BLOCK_START_COL to end of
	; line
	LD BC,(BLOCK_START_ROW)
	LD DE,SPLIT_LINE_TEMP
	LD HL,MAX_ACTIVE_LINE_STRIDE-2
	CALL READ_FAR_LINE_MAX

	LD HL,SPLIT_LINE_TEMP
	LD BC,(BLOCK_START_COL)
SBF_ML_HEAD_ADV:
	LD A,B
	OR C
	JR Z,SBF_ML_HEAD_STREAM
	LD A,(HL)
	OR A
	JR Z,SBF_ML_HEAD_DONE
	INC HL
	DEC BC
	JR SBF_ML_HEAD_ADV

SBF_ML_HEAD_STREAM:
	LD A,(HL)
	OR A
	JR Z,SBF_ML_HEAD_DONE
	CALL WRITE_BYTE_TO_DMA
	INC HL
	JR SBF_ML_HEAD_STREAM

SBF_ML_HEAD_DONE:
	CALL WRITE_SAVE_LINE_ENDING
	CALL TICK_SAVE_PROGRESS

	; Step 2: Middle rows: from (BLOCK_START_ROW + 1) to (BLOCK_END_ROW - 1)
	LD BC,(BLOCK_START_ROW)
	INC BC
SBF_ML_MID_LOOP:
	LD HL,(BLOCK_END_ROW)
	LD A,H
	CP B
	JR NZ,SBF_ML_MID_COMPARE
	LD A,L
	CP C
	JR Z,SBF_ML_TAIL
SBF_ML_MID_COMPARE:
	PUSH BC
	LD DE,SPLIT_LINE_TEMP
	LD HL,MAX_ACTIVE_LINE_STRIDE-2
	CALL READ_FAR_LINE_MAX

	LD HL,SPLIT_LINE_TEMP
SBF_ML_MID_STREAM:
	LD A,(HL)
	OR A
	JR Z,SBF_ML_MID_LINE_DONE
	CALL WRITE_BYTE_TO_DMA
	INC HL
	JR SBF_ML_MID_STREAM

SBF_ML_MID_LINE_DONE:
	CALL WRITE_SAVE_LINE_ENDING
	CALL TICK_SAVE_PROGRESS
	POP BC
	INC BC
	JR SBF_ML_MID_LOOP

	; Step 3: Tail row (BLOCK_END_ROW)
SBF_ML_TAIL:
	LD HL,(BLOCK_END_COL)
	LD A,H
	OR L
	JP Z,SAVE_FLUSH_REMAINDER

	LD BC,(BLOCK_END_ROW)
	LD DE,SPLIT_LINE_TEMP
	LD HL,MAX_ACTIVE_LINE_STRIDE-2
	CALL READ_FAR_LINE_MAX

	LD HL,SPLIT_LINE_TEMP
	LD BC,(BLOCK_END_COL)
SBF_ML_TAIL_STREAM:
	LD A,B
	OR C
	JR Z,SBF_ML_TAIL_DONE
	LD A,(HL)
	OR A
	JR Z,SBF_ML_TAIL_DONE
	CALL WRITE_BYTE_TO_DMA
	INC HL
	DEC BC
	JR SBF_ML_TAIL_STREAM

SBF_ML_TAIL_DONE:
	CALL WRITE_SAVE_LINE_ENDING
	CALL TICK_SAVE_PROGRESS
	JP SAVE_FLUSH_REMAINDER

;------------------------------------------------------------------------------
; WRITE_SAVE_LINE_ENDING: Emit line ending sequence to save DMA buffer
;
; Purpose:
;   Writes active line ending sequence (CRLF, LF, or CR) based on
;   FILE_LINE_ENDING_MODE into output DMA stream via WRITE_BYTE_TO_DMA.
;
; Call Usage / Protocol:
;   Called via CALL at end of each saved line in SAVE_FILE and block save.
;
; Inputs:
;   FILE_LINE_ENDING_MODE.
;
; Outputs:
;   Line ending bytes buffered to disk DMA.
;
; Preserves / Modifies:
;   Clobbers AF; preserves BC, DE, HL.
;------------------------------------------------------------------------------
WRITE_SAVE_LINE_ENDING:
	LD A,(SAVE_FORMAT)
	CP FMT_CPM
	JR NZ,WSLE_LF_ONLY
	LD A,13
	CALL WRITE_BYTE_TO_DMA
WSLE_LF_ONLY:
	LD A,10
	CALL WRITE_BYTE_TO_DMA
	RET

;------------------------------------------------------------------------------
; INIT_SAVE_PROGRESS: Initialize save progress indicator and display modal
;
; Purpose:
;   Renders modal progress dialog, stores total line count in SAVE_TOTAL_LINES,
;   zeros current progress counter, and draws empty progress bar.
;
; Call Usage / Protocol:
;   Called via CALL before starting file write loops in SAVE_FILE.
;
; Inputs:
;   HL = Total line count to save.
;
; Outputs:
;   Progress dialog displayed; counters initialized.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
INIT_SAVE_PROGRESS:
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL
	CALL TERM_HIDE_CURSOR
	LD A,1
	LD (IS_SAVING_FILE),A
	LD HL,0
	LD (LOAD_PROGRESS_LINES),HL
	LD A,100
	LD (LOAD_PROGRESS_COUNT),A
	LD DE,STR_POPUP_SAVING_TITLE
	CALL DRAW_PROGRESS_MODAL
	POP HL
	POP DE
	POP BC
	POP AF
	RET

;------------------------------------------------------------------------------
; TICK_SAVE_PROGRESS: Advance save progress counter and update progress bar
;
; Purpose:
;   Increments saved line counter and updates visual progress fill characters
;   inside progress modal dialog at regular line intervals.
;
; Call Usage / Protocol:
;   Called via CALL after each line is written to disk in SAVE_FILE.
;
; Inputs:
;   None.
;
; Outputs:
;   Visual progress bar updated.
;
; Preserves / Modifies:
;   Clobbers AF; preserves BC, DE, HL.
;------------------------------------------------------------------------------
TICK_SAVE_PROGRESS:
	PUSH AF
	PUSH HL
	LD HL,(LOAD_PROGRESS_LINES)
	INC HL
	LD (LOAD_PROGRESS_LINES),HL
	LD HL,LOAD_PROGRESS_COUNT
	DEC (HL)
	JR NZ,TSP_DONE
	LD (HL),100
	CALL UPDATE_LOAD_PROGRESS
TSP_DONE:
	POP HL
	POP AF
	RET

;------------------------------------------------------------------------------
; FINISH_SAVE_PROGRESS: Advance save progress bar to 100% completion
;
; Purpose:
;   Fills remaining progress bar characters to 100% full upon completing all
;   line writes before final file flush and close.
;
; Call Usage / Protocol:
;   Called via CALL from SAVE_FILE after last line written.
;
; Inputs:
;   None.
;
; Outputs:
;   Progress bar filled to 100%.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
FINISH_SAVE_PROGRESS:
	PUSH AF
	PUSH DE
	CALL UPDATE_LOAD_PROGRESS
	CALL DRAIN_INPUT_BUFFER
	JR CSP_COMMON

;------------------------------------------------------------------------------
; CLEANUP_SAVE_PROGRESS: Restore terminal screen after save progress modal
;
; Purpose:
;   Cleans up temporary save progress display and restores terminal cursor state
;   upon completing or aborting file save.
;
; Call Usage / Protocol:
;   Called via CALL after SAVE_FILE finishes or encounters an error.
;
; Inputs:
;   None.
;
; Outputs:
;   Screen restored.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
CLEANUP_SAVE_PROGRESS:
	PUSH AF
	PUSH DE
	CALL DRAIN_INPUT_BUFFER
CSP_COMMON:
	XOR A
	LD (IS_SAVING_FILE),A
	CALL TERM_SHOW_CURSOR
	POP DE
	POP AF
	RET

;------------------------------------------------------------------------------
; SAVE_FILE: Write active document lines from far RAM to disk/RAM drive
;
; Purpose:
;   Creates or replaces file in WORK_FCB, displays progress modal, iterates
;   through all lines in far RAM line table, writes characters via 128-byte
;   DMA sector buffering, appends EOF marker, and closes file.
;
; Call Usage / Protocol:
;   Called via CALL from Save File command handler and DO_ACTUAL_SAVE.
;
; Inputs:
;   WORK_FCB = Target file FCB; document lines in far RAM line storage.
;
; Outputs:
;   File written and closed; DOCUMENT_MODIFIED cleared; Carry = 0 on success;
;   Carry = 1 on write/close error.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SAVE_FILE:
	; Guard: if target drive is hibernated RAM drive, reject save
	CALL CHECK_FCB_IS_HIBERNATED
	JR NC,SAVE_DRIVE_OK
	SCF
	RET

SAVE_DRIVE_OK:
	; Set BDOS user area to WORK_FCB_USER
	LD A,(WORK_FCB_USER)
	LD E,A
	LD C,32				; BDOS Set User Area
	CALL BDOS_ENTRY

	; Flush local cache dirty lines first
	CALL FLUSH_DIRTY_CACHE

	LD A,(WORK_FCB+1)
	CP ' '
	JP NZ,DO_SAVE_EXISTING

	; Zero entire WORK_FCB (36 bytes)
	LD HL,WORK_FCB
	LD (HL),0
	LD DE,WORK_FCB+1
	LD BC,35
	LDIR

	; Copy default filename (0, "OUTPUT  TXT")
	LD HL,DEFAULT_FCB_NAME
	LD DE,WORK_FCB
	LD BC,12
	LDIR

DO_SAVE_EXISTING:
	; Zero FCB extent and record bytes (bytes 12..35)
	LD HL,WORK_FCB+12
	LD (HL),0
	LD DE,WORK_FCB+13
	LD BC,23
	LDIR

	; Delete old file
	LD DE,WORK_FCB
	LD C,19				; BDOS Delete File
	CALL BDOS_ENTRY

	; Create new file
	LD DE,WORK_FCB
	LD C,22				; BDOS Make File
	CALL BDOS_ENTRY
	CP 0FFH
	JR NZ,MAKE_FILE_OK
	; Restore BDOS user area to CURRENT_DIR_USER
	LD A,(CURRENT_DIR_USER)
	LD E,A
	LD C,32				; BDOS Set User Area
	CALL BDOS_ENTRY
	SCF
	RET

MAKE_FILE_OK:
	CALL INIT_SAVE_PROGRESS

	; Prepare DMA write pointer
	LD DE,DEFAULT_DMA
	LD (CUR_DMA_PTR),DE
	LD A,128
	LD (DMA_BYTES_LEFT),A
	LD HL,0
	LD (SAVE_RECORD_NUM),HL

	; Stream lines from Far RAM banks to disk
	LD BC,0				; BC = document line counter
SAVE_LINE_LOOP:
	LD HL,(DOC_TOTAL_LINES)
	LD A,H
	CP B
	JP C,SAVE_FLUSH_REMAINDER
	JP NZ,DO_SAVE_LINE
	LD A,L
	CP C
	JP Z,SAVE_FLUSH_REMAINDER
	JP C,SAVE_FLUSH_REMAINDER

DO_SAVE_LINE:
	PUSH BC				; BC = document line index

	; Lookup head slot ID: line BC in Far RAM line table
	CALL GET_LINE_SLOT		; HL = head slot ID
	LD B,H
	LD C,L				; BC = head slot ID

SAVE_STRIDE_LOOP:
	; Check if slot ID is 0xFFFF (SLOT_TERM)
	LD A,B
	AND C
	INC A
	JR Z,SAVE_LINE_END

	; Read slot BC into FAR_IO_BUF
	LD DE,FAR_IO_BUF
	CALL READ_FAR_SLOT

	; Next slot ID is in FAR_IO_BUF[0..1]
	LD HL,(FAR_IO_BUF)
	LD (SAVE_NEXT_SLOT),HL

	; Stream payload from FAR_IO_BUF+2
	LD HL,FAR_IO_BUF+2
	LD B,FAR_SLOT_PAYLOAD		; 126 bytes max
SAVE_PAYLOAD_LOOP:
	LD A,(HL)
	OR A
	; Null terminator reached: this line is complete!
	JR Z,SAVE_LINE_END
	CALL WRITE_BYTE_TO_DMA
	INC HL
	DJNZ SAVE_PAYLOAD_LOOP

	; Stride exhausted (all 126 bytes emitted): advance to next slot in
	; chain
	LD BC,(SAVE_NEXT_SLOT)
	JR SAVE_STRIDE_LOOP

SAVE_LINE_END:
	CALL WRITE_SAVE_LINE_ENDING
	CALL TICK_SAVE_PROGRESS
	POP BC
	INC BC
	JP SAVE_LINE_LOOP

SAVE_FLUSH_REMAINDER:
	; Pad remaining bytes in sector with ^Z (0x1A)
PAD_SECTOR_LOOP:
	LD A,(DMA_BYTES_LEFT)
	CP 128
	JP Z,CLOSE_OUTPUT_FILE
	LD A,26
	CALL WRITE_BYTE_TO_DMA
	JP PAD_SECTOR_LOOP

CLOSE_OUTPUT_FILE:
	LD DE,WORK_FCB
	LD C,16				; BDOS Close File
	CALL BDOS_ENTRY
	CP 0FFH
	JR NZ,CLOSE_FILE_OK
	CALL CLEANUP_SAVE_PROGRESS
	; Restore BDOS user area to CURRENT_DIR_USER
	LD A,(CURRENT_DIR_USER)
	LD E,A
	LD C,32				; BDOS Set User Area
	CALL BDOS_ENTRY
	SCF
	RET
CLOSE_FILE_OK:
	CALL FINISH_SAVE_PROGRESS
	; If this was NOT a block save, update DOC_USER_NUM and CURRENT_DIR_USER
	LD A,(IS_BLOCK_SAVE_UI)
	OR A
	JR NZ,CFO_IS_BLK
	LD A,(WORK_FCB_USER)
	LD (DOC_USER_NUM),A
	LD (CURRENT_DIR_USER),A
CFO_IS_BLK:
	; Restore BDOS user area to CURRENT_DIR_USER
	LD A,(CURRENT_DIR_USER)
	LD E,A
	LD C,32				; BDOS Set User Area
	CALL BDOS_ENTRY
	OR A				; Carry = 0 (success)
	RET

;------------------------------------------------------------------------------
; WRITE_BYTE_TO_DMA: Buffer single byte and flush DMA sector to disk when full
;
; Purpose:
;   Places byte in accumulator into 128-byte disk DMA buffer. When buffer fills
;   to 128 bytes, invokes BDOS Write Sequential (function 21) to flush sector.
;
; Call Usage / Protocol:
;   Called via CALL for every byte written in SAVE_FILE and SAVE_BLOCK_FILE.
;
; Inputs:
;   A = Byte to write.
;
; Outputs:
;   Byte buffered; Carry = 1 if BDOS write error occurs.
;
; Preserves / Modifies:
;   Clobbers AF; preserves BC, DE, HL.
;------------------------------------------------------------------------------
WRITE_BYTE_TO_DMA:
	PUSH HL
	PUSH BC
	LD HL,(CUR_DMA_PTR)
	LD (HL),A
	INC HL
	LD (CUR_DMA_PTR),HL

	LD A,(DMA_BYTES_LEFT)
	DEC A
	LD (DMA_BYTES_LEFT),A
	JR NZ,WRITE_BYTE_DONE

	; Sector full: flush DMA to disk
	PUSH DE
	LD DE,DEFAULT_DMA
	LD C,26				; BDOS Set DMA
	CALL BDOS_ENTRY

	LD HL,(SAVE_RECORD_NUM)
	LD (WORK_FCB+33),HL		; Set r0, r1 for BDOS Write Random
	XOR A
	LD (WORK_FCB+35),A		; Set r2 = 0
	INC HL
	LD (SAVE_RECORD_NUM),HL

	LD DE,WORK_FCB
	LD C,34			; BDOS Write Random (prevents ghost extent)
	CALL BDOS_ENTRY
	POP DE

	; Reset DMA buffer pointer
	LD HL,DEFAULT_DMA
	LD (CUR_DMA_PTR),HL
	LD A,128
	LD (DMA_BYTES_LEFT),A

WRITE_BYTE_DONE:
	POP BC
	POP HL
	RET

;------------------------------------------------------------------------------
; PRINT_DEC_WORD: Format and print 16-bit word in decimal to terminal
;
; Purpose:
;   Converts 16-bit unsigned integer in HL to ASCII decimal representation
;   (via repeated division by 10) and prints string to terminal.
;
; Call Usage / Protocol:
;   Called via CALL throughout editor for line numbers, counts, and statistics.
;
; Inputs:
;   HL = 16-bit unsigned integer value.
;
; Outputs:
;   Decimal string emitted to terminal.
;
; Preserves / Modifies:
;   Preserves AF, BC, DE, HL.
;------------------------------------------------------------------------------
PRINT_DEC_WORD:
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL
	LD DE,DEC_WORD_BUF+5
	LD A,'$'
	LD (DE),A			; '$' terminator for PRINT_STR
DEC_WORD_LOOP:
	CALL DIV_HL_10			; HL = HL / 10, A = HL % 10
	ADD A,'0'
	DEC DE
	LD (DE),A
	LD A,H
	OR L
	JR NZ,DEC_WORD_LOOP
	CALL PRINT_STR
	POP HL
	POP DE
	POP BC
	POP AF
	RET

;------------------------------------------------------------------------------
; DIV_HL_10: Compute 16-bit divide and modulo by 10 (HL = HL / 10, A = HL % 10)
;
; Purpose:
;   Executes 16-bit binary restoring division by 10 using shift-and-subtract
;   loop over 16 iterations.
;
; Call Usage / Protocol:
;   Called via CALL from PRINT_DEC_WORD decimal conversion loop.
;
; Inputs:
;   HL = 16-bit dividend.
;
; Outputs:
;   HL = Quotient (HL / 10), A = Remainder (0..9).
;
; Preserves / Modifies:
;   Modifies AF, HL; preserves BC, DE.
;------------------------------------------------------------------------------
DIV_HL_10:
	PUSH BC
	LD B,16
	XOR A
DIV_HL_10_LOOP:
	ADD HL,HL
	RLA
	CP 10
	JR C,DIV_HL_10_NEXT
	SUB 10
	INC L
DIV_HL_10_NEXT:
	DJNZ DIV_HL_10_LOOP
	POP BC
	RET

