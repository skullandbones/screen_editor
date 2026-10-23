;==============================================================================
; NEXTFS.ASM - NextZXOS Host Filesystem VFS Plugin for SE_NEXT.COM
; Digital Research CP/M 3 Page-Relocatable (.PRL) Format
;
; Provides transparent Headless VFS access (Action 3 at ENTRY+9) to NextZXOS
; native host drives (FAT32 SD card C:, RAM drive M:, etc.) under NextCPM
; without triggering CP/M BDOS Select Errors or crashes to the prompt.
;
; Utilizes NextCPM BIOS USERF API (BIOS Function 30):
;   - C=1: NextZXOS / +3DOS kernel file services (DOS_OPEN $0106,
;          DOS_READ $0112, DOS_WRITE $0115, DOS_CLOSE $0109,
;          DOS_CATALOG $011E) with buffers in Upper Memory ($8000..$BFFF).
;   - C=2: NextZXOS dynamic drive mapping tables.
;
; Host API Bridge:
;   Resolves Host API vector via IX/IY pointer passed at entry.
;   Dispatches USERF calls through host trampoline TRAMP_NEXTCPM_USERF (at
;   HOST_API+82) to maintain memory bank consistency during inter-mode calls.
;==============================================================================

	ORG	0100H

;------------------------------------------------------------------------------
; Standard 4-Entry Jump Table
;------------------------------------------------------------------------------
ENTRY:
	JP	DO_RUN			; +0: Action 0 (Main Execution / Info)
	JP	DO_ABOUT		; +3: Action 1 (About Screen)
	JP	DO_CONFIG		; +6: Action 2 (Config Screen)
	JP	DO_VFS			; +9: Action 3 (Headless VFS Operations)

;------------------------------------------------------------------------------
; VFS Command Codes
;------------------------------------------------------------------------------
VFS_CMD_PROBE_MOUNT	EQU	0
VFS_CMD_LIST_DIR	EQU	1
VFS_CMD_LOAD_FILE	EQU	2
VFS_CMD_SAVE_FILE	EQU	3
VFS_CMD_SAVE_RANGE	EQU	4
VFS_CMD_OPEN_FILE	EQU	5
VFS_CMD_READ_CHUNK	EQU	6
VFS_CMD_CLOSE_FILE	EQU	7
VFS_CMD_GET_DEF_UNIT	EQU	8
VFS_CMD_SET_DEF_UNIT	EQU	9

;------------------------------------------------------------------------------
; VFS Status Codes
;------------------------------------------------------------------------------
VFS_STAT_OK		EQU	0
VFS_STAT_NOT_FOUND	EQU	1
VFS_STAT_DISK_ERR	EQU	2
VFS_STAT_BUFFER_FULL	EQU	3
VFS_STAT_INV_UNIT	EQU	4
VFS_STAT_READ_ONLY	EQU	5
VFS_STAT_EOF		EQU	6
VFS_STAT_UNSUPPORTED	EQU	0FFH

;------------------------------------------------------------------------------
; NextZXOS / +3DOS Call IDs
;------------------------------------------------------------------------------
DOS_OPEN		EQU	0106H
DOS_CLOSE		EQU	0109H
DOS_READ		EQU	0112H
DOS_WRITE		EQU	0115H
DOS_CATALOG		EQU	011EH

;------------------------------------------------------------------------------
; Action 0: Main Execution / Info
;------------------------------------------------------------------------------
DO_RUN:
	CALL	SAVE_HOST_API
	JP	SHOW_ABOUT_MODAL

;------------------------------------------------------------------------------
; Action 1: About Screen
;------------------------------------------------------------------------------
DO_ABOUT:
	CALL	SAVE_HOST_API
	JP	SHOW_ABOUT_MODAL

;------------------------------------------------------------------------------
; Action 2: Config Screen (No configuration required)
;------------------------------------------------------------------------------
DO_CONFIG:
	XOR	A
	RET

;------------------------------------------------------------------------------
; SAVE_HOST_API: Resolve and store host API pointer from IX or IY
;------------------------------------------------------------------------------
SAVE_HOST_API:
	LD	A,(IX+0)
	CP	'S'
	JR	NZ,SHA_TRY_IY
	LD	A,(IX+1)
	CP	'E'
	JR	Z,SHA_GOT_IX
SHA_TRY_IY:
	PUSH	IY
	POP	IX
SHA_GOT_IX:
	LD	(HOST_API_PTR),IX
	RET

;------------------------------------------------------------------------------
; SHOW_ABOUT_MODAL: Display informative modal banner for NEXTFS plugin
;------------------------------------------------------------------------------
SHOW_ABOUT_MODAL:
	LD	HL,(HOST_API_PTR)
	LD	DE,27			; Offset to CALL_PRINT_STR
	ADD	HL,DE
	LD	DE,STR_ABOUT_MSG
	CALL	CALL_INDIRECT_HL
	LD	HL,(HOST_API_PTR)
	LD	DE,30			; Offset to CALL_GET_KEY
	ADD	HL,DE
	CALL	CALL_INDIRECT_HL
	XOR	A			; Return clean (no doc modification)
	RET

CALL_INDIRECT_HL:
	JP	(HL)

STR_ABOUT_MSG:
	DB	13,10
	DB	"+--------------------------------------------------+",13,10
	DB	"|      NEXTFS.PRL - NextZXOS Host VFS Driver       |",13,10
	DB	"+--------------------------------------------------+",13,10
	DB	"| Transparent access to NextZXOS native host       |",13,10
	DB	"| drives (FAT32 SD card C:, RAM disk M:, etc.)     |",13,10
	DB	"| for SE_NEXT.COM without CP/M BDOS errors.        |",13,10
	DB	"| Uses NextCPM BIOS USERF (Func 30) call gate.     |",13,10
	DB	"+--------------------------------------------------+",13,10
	DB	"Press any key to return...",13,10,0

;------------------------------------------------------------------------------
; Action 3: Headless VFS Dispatcher (ENTRY+9)
; Inputs:
;   DE = Pointer to VFS_REQ_PKT in Upper Common RAM (> 0x8000)
;   IX / IY = Host API Table Pointer
; Outputs:
;   Carry = 0 on success, Carry = 1 on error
;   (DE+2) = VFS_REQ_STATUS
;------------------------------------------------------------------------------
DO_VFS:
	LD	(SAVED_SP),SP
	CALL	SAVE_HOST_API
	LD	(REQ_PKT_PTR),DE

	; Read command opcode at (DE+0)
	LD	A,(DE)

	CP	VFS_CMD_PROBE_MOUNT
	JP	Z,VFS_PROBE_MOUNT

	CP	VFS_CMD_LIST_DIR
	JP	Z,VFS_LIST_DIR

	CP	VFS_CMD_LOAD_FILE
	JP	Z,VFS_LOAD_FILE

	CP	VFS_CMD_SAVE_FILE
	JP	Z,VFS_SAVE_FILE

	CP	VFS_CMD_SAVE_RANGE
	JP	Z,VFS_SAVE_RANGE

	CP	VFS_CMD_OPEN_FILE
	JP	Z,VFS_OPEN_FILE

	CP	VFS_CMD_READ_CHUNK
	JP	Z,VFS_READ_CHUNK

	CP	VFS_CMD_CLOSE_FILE
	JP	Z,VFS_CLOSE_FILE

	CP	VFS_CMD_GET_DEF_UNIT
	JP	Z,VFS_GET_DEF_UNIT

	CP	VFS_CMD_SET_DEF_UNIT
	JP	Z,VFS_SET_DEF_UNIT

	; Unsupported opcode
	LD	A,VFS_STAT_UNSUPPORTED
	JP	VFS_SET_STATUS_ERR

;------------------------------------------------------------------------------
; VFS_PROBE_MOUNT: Verify filesystem availability
;------------------------------------------------------------------------------
VFS_PROBE_MOUNT:
	XOR	A
	JP	VFS_SET_STATUS_OK

;------------------------------------------------------------------------------
; VFS_GET_DEF_UNIT: Query default drive unit
;------------------------------------------------------------------------------
VFS_GET_DEF_UNIT:
	LD	HL,(REQ_PKT_PTR)
	INC	HL			; +1: VFS_REQ_UNIT
	LD	A,(DEF_DRV_UNIT)
	LD	(HL),A
	XOR	A
	JP	VFS_SET_STATUS_OK

;------------------------------------------------------------------------------
; VFS_SET_DEF_UNIT: Set default drive unit
;------------------------------------------------------------------------------
VFS_SET_DEF_UNIT:
	LD	HL,(REQ_PKT_PTR)
	INC	HL			; +1: VFS_REQ_UNIT
	LD	A,(HL)
	LD	(DEF_DRV_UNIT),A
	XOR	A
	JP	VFS_SET_STATUS_OK

;------------------------------------------------------------------------------
; VFS Status Return Helpers
;------------------------------------------------------------------------------
VFS_SET_STATUS_OK:
	LD	HL,(REQ_PKT_PTR)
	INC	HL
	INC	HL			; +2: VFS_REQ_STATUS
	LD	(HL),0
	OR	A			; Carry = 0 (Success)
	RET

VFS_SET_STATUS_ERR:
	LD	HL,(REQ_PKT_PTR)
	INC	HL
	INC	HL			; +2: VFS_REQ_STATUS
	LD	(HL),A
	SCF				; Carry = 1 (Error)
	RET

;------------------------------------------------------------------------------
; CALL_USERF_GATE: Call NextCPM BIOS USERF via host trampoline at HOST_API+82
; Inputs:
;   C = 1 (NextZXOS call) or 2 (Drive map tables)
;   IY = Call ID (e.g. DOS_OPEN, DOS_READ, etc.)
;   Registers prepared for inter-mode call
; Outputs:
;   Results returned from NextZXOS / BIOS
;------------------------------------------------------------------------------
CALL_USERF_GATE:
	PUSH	HL
	LD	HL,(HOST_API_PTR)
	LD	DE,82			; Offset to JP TRAMP_NEXTCPM_USERF
	ADD	HL,DE
	EX	(SP),HL
	RET				; Jumps to TRAMP_NEXTCPM_USERF

;------------------------------------------------------------------------------
; NORMALIZE_DRV_UNIT: Extract 0-based drive index (0..15 for A..P)
; Inputs:
;   A = Unit from request packet (0..15 or 'A'..'P' or 'a'..'p' or 0xFF)
; Outputs:
;   A = 0-based drive index (0=A..15=P)
;------------------------------------------------------------------------------
NORMALIZE_DRV_UNIT:
	CP	'a'
	JR	C,NDU_NOT_LOWER
	CP	'p'+1
	JR	NC,NDU_NOT_LOWER
	SUB	'a'
	RET
NDU_NOT_LOWER:
	CP	'A'
	JR	C,NDU_NOT_UPPER
	CP	'P'+1
	JR	NC,NDU_NOT_UPPER
	SUB	'A'
	RET
NDU_NOT_UPPER:
	CP	16
	RET	C			; Already 0..15
	LD	A,(DEF_DRV_UNIT)	; Fall back to default
	RET

;------------------------------------------------------------------------------
; PREPARE_PATH: Format filespec into Upper Memory buffer (ACTIVE_LINE_BUF)
; Inputs:
;   req->path, req->unit
; Outputs:
;   HL = Pointer to null-terminated filespec in Upper Memory
;------------------------------------------------------------------------------
PREPARE_PATH:
	LD	HL,(REQ_PKT_PTR)
	INC	HL			; +1: unit
	LD	A,(HL)
	CALL	NORMALIZE_DRV_UNIT
	ADD	A,'A'
	LD	C,A			; C = Drive letter 'A'..'P'

	; Retrieve req->path at +4
	INC	HL
	INC	HL
	INC	HL			; +4: req->path pointer
	LD	E,(HL)
	INC	HL
	LD	D,(HL)			; DE = Path string pointer

	; Destination: ACTIVE_LINE_BUF via HOST_API+4
	LD	HL,(HOST_API_PTR)
	INC	HL
	INC	HL
	INC	HL
	INC	HL			; +4: Pointer to ACTIVE_LINE_BUF
	LD	A,(HL)
	INC	HL
	LD	H,(HL)
	LD	L,A			; HL = ACTIVE_LINE_BUF
	PUSH	HL			; Save start of destination

	; Check if path already starts with drive letter and colon
	LD	A,(DE)
	OR	A
	JR	Z,PP_EMPTY
	INC	DE
	LD	A,(DE)
	DEC	DE
	CP	':'
	JR	NZ,PP_NEEDS_DRIVE

	; Path already has drive prefix (e.g. "C:FOO.TXT")
PP_COPY_EXISTING:
	LD	A,(DE)
	LD	(HL),A
	INC	DE
	INC	HL
	OR	A
	JR	NZ,PP_COPY_EXISTING
	POP	HL
	RET

PP_NEEDS_DRIVE:
	LD	(HL),C			; Drive letter
	INC	HL
	LD	(HL),':'		; Colon
	INC	HL
	LD	A,(DE)
	CP	'/'
	JR	Z,PP_COPY_REST
	CP	'\\'
	JR	Z,PP_COPY_REST
	LD	(HL),'/'		; Prepend '/' if missing
	INC	HL

PP_COPY_REST:
	LD	A,(DE)
	LD	(HL),A
	INC	DE
	INC	HL
	OR	A
	JR	NZ,PP_COPY_REST
	POP	HL
	RET

PP_EMPTY:
	; Empty path -> "C:/"
	LD	(HL),C
	INC	HL
	LD	(HL),':'
	INC	HL
	LD	(HL),'/'
	INC	HL
	LD	(HL),0
	POP	HL
	RET

;------------------------------------------------------------------------------
; VFS_LIST_DIR: Enumerate directory records into 13-byte VFS entries
; Inputs:
;   req->path, req->unit, req->buffer, req->buffer_size
; Outputs:
;   req->count = Number of entries; req->status = VFS_STAT_OK / NOT_FOUND
;------------------------------------------------------------------------------
VFS_LIST_DIR:
	; Format target drive index
	LD	HL,(REQ_PKT_PTR)
	INC	HL			; +1: unit
	LD	A,(HL)
	CALL	NORMALIZE_DRV_UNIT
	LD	(CAT_DRV_IDX),A

	; Read buffer pointer at +6
	INC	HL
	INC	HL
	INC	HL
	INC	HL
	INC	HL			; +6: req->buffer
	LD	E,(HL)
	INC	HL
	LD	D,(HL)			; DE = Output buffer (DIR_NAMES_BUF)
	LD	(CAT_OUT_PTR),DE

	; Read buffer_size at +8
	INC	HL			; +8: req->buffer_size
	LD	E,(HL)
	INC	HL
	LD	D,(HL)			; DE = Buffer capacity
	LD	A,D
	OR	A
	JR	Z,VLD_USE_DEF_MAX
	LD	A,255
	JR	VLD_GOT_MAX
VLD_USE_DEF_MAX:
	LD	A,E
	OR	A
	JR	NZ,VLD_GOT_MAX
	LD	A,255
VLD_GOT_MAX:
	LD	(CAT_MAX_ENTRIES),A
	XOR	A
	LD	(CAT_CUR_COUNT),A

	; Check if path represents subdirectory to synthesize ".." entry
	LD	HL,(REQ_PKT_PTR)
	LD	DE,4
	ADD	HL,DE
	LD	E,(HL)
	INC	HL
	LD	D,(HL)			; DE = req->path
	LD	A,(DE)
	OR	A
	JR	Z,VLD_START_CAT
	CP	'/'
	JR	NZ,VLD_SYNTH_PARENT
	INC	DE
	LD	A,(DE)
	OR	A
	JR	Z,VLD_START_CAT

VLD_SYNTH_PARENT:
	; Emit "..      /   \0" into output buffer
	LD	HL,(CAT_OUT_PTR)
	LD	DE,STR_PARENT_DIR_REC
	LD	BC,13
	LDIR
	LD	(CAT_OUT_PTR),HL
	LD	A,1
	LD	(CAT_CUR_COUNT),A

VLD_START_CAT:
	; Prepare 13-byte parameter block of zeroes in Upper Memory
	; Use ACTIVE_LINE_BUF + 512 as parameter block
	LD	HL,(HOST_API_PTR)
	LD	DE,4
	ADD	HL,DE
	LD	E,(HL)
	INC	HL
	LD	D,(HL)			; DE = ACTIVE_LINE_BUF
	LD	HL,512
	ADD	HL,DE			; HL = ACTIVE_LINE_BUF + 512
	LD	(CAT_PARAM_PTR),HL
	PUSH	HL
	EX	DE,HL
	XOR	A
	LD	B,13
VLD_CLR_PARAM:
	LD	(DE),A
	INC	DE
	DJNZ	VLD_CLR_PARAM
	POP	DE			; DE = Parameter buffer

	; Staging buffer for catalog entries: ACTIVE_LINE_BUF
	LD	HL,(HOST_API_PTR)
	LD	BC,4
	ADD	HL,BC
	LD	C,(HL)
	INC	HL
	LD	B,(HL)
	PUSH	BC
	POP	HL			; HL = ACTIVE_LINE_BUF (Catalog buffer)
	LD	(CAT_BUF_PTR),HL

	; Initial catalog request: B = 0xFF, C = drive_index
	LD	A,(CAT_DRV_IDX)
	LD	C,A
	LD	B,0FFH
	LD	IY,DOS_CATALOG
	PUSH	BC
	LD	C,1
	CALL	CALL_USERF_GATE
	POP	BC
	JP	NC,VLD_CHECK_EMPTY

VLD_PROCESS_BATCH:
	; B = entries returned in this batch, HL = catalog buffer
	LD	A,B
	OR	A
	JR	Z,VLD_FINISH

	PUSH	AF			; Save continuation flag / count
	LD	HL,(CAT_BUF_PTR)

VLD_ENTRY_LOOP:
	; Check if maximum entries reached
	LD	A,(CAT_CUR_COUNT)
	LD	C,A
	LD	A,(CAT_MAX_ENTRIES)
	CP	C
	JR	Z,VLD_BATCH_DONE

	; Inspect entry at HL (13 bytes: 8 name + 3 ext + attributes)
	LD	A,(HL)
	OR	A
	JR	Z,VLD_SKIP_ENTRY
	CP	0E5H
	JR	Z,VLD_SKIP_ENTRY
	CP	'.'
	JR	Z,VLD_SKIP_ENTRY
	CP	' '
	JR	Z,VLD_SKIP_ENTRY

	; Copy to output buffer
	PUSH	BC
	PUSH	HL
	LD	DE,(CAT_OUT_PTR)

	; Copy 8 bytes filename
	LD	B,8
VLD_CP_NAME:
	LD	A,(HL)
	LD	(DE),A
	INC	HL
	INC	DE
	DJNZ	VLD_CP_NAME

	; Check attribute in byte 11 for directory flag (0x10)
	PUSH	HL
	INC	HL
	INC	HL
	INC	HL			; HL points to byte 11
	LD	A,(HL)
	AND	010H			; AM_DIR
	POP	HL
	JR	NZ,VLD_IS_DIR

	; File: separator '.'
	LD	A,'.'
	LD	(DE),A
	INC	DE
	JR	VLD_CP_EXT

VLD_IS_DIR:
	; Directory: separator '/'
	LD	A,'/'
	LD	(DE),A
	INC	DE

VLD_CP_EXT:
	; Copy 3 bytes extension
	LD	B,3
VLD_CP_EXT_LOOP:
	LD	A,(HL)
	RES	7,A			; Strip +3DOS read-only/system bits
	LD	(DE),A
	INC	HL
	INC	DE
	DJNZ	VLD_CP_EXT_LOOP

	; Null-terminate 13-byte record
	XOR	A
	LD	(DE),A
	INC	DE
	LD	(CAT_OUT_PTR),DE

	; Increment count
	LD	HL,CAT_CUR_COUNT
	INC	(HL)

	POP	HL
	POP	BC

VLD_SKIP_ENTRY:
	LD	DE,13
	ADD	HL,DE			; Next catalog entry
	DJNZ	VLD_ENTRY_LOOP

VLD_BATCH_DONE:
	POP	AF			; Restore continuation flag
	CP	0FFH
	JR	NZ,VLD_FINISH

	; Request next batch: B = 1, C = drive_index
	LD	A,(CAT_DRV_IDX)
	LD	C,A
	LD	B,1
	LD	HL,(CAT_BUF_PTR)
	LD	DE,(CAT_PARAM_PTR)
	LD	IY,DOS_CATALOG
	PUSH	BC
	LD	C,1
	CALL	CALL_USERF_GATE
	POP	BC
	JR	C,VLD_PROCESS_BATCH

VLD_FINISH:
	; Store total count into req->count at +10
	LD	HL,(REQ_PKT_PTR)
	LD	DE,10
	ADD	HL,DE
	LD	A,(CAT_CUR_COUNT)
	LD	(HL),A
	INC	HL
	LD	(HL),0
	XOR	A
	JP	VFS_SET_STATUS_OK

VLD_CHECK_EMPTY:
	LD	A,(CAT_CUR_COUNT)
	OR	A
	JR	NZ,VLD_FINISH
	; Return empty directory with success
	XOR	A
	JR	VLD_FINISH

STR_PARENT_DIR_REC:
	DB	"..      /   ",0

;------------------------------------------------------------------------------
; VFS_LOAD_FILE: Load NextZXOS file into host editor document
; Inputs:
;   req->path, req->unit
; Outputs:
;   req->count = lines loaded; req->status = VFS_STAT_OK / NOT_FOUND
;------------------------------------------------------------------------------
VFS_LOAD_FILE:
	CALL	PREPARE_PATH		; HL = Filespec in Upper Memory
	LD	DE,0002H		; Open existing file
	LD	BC,0001H		; File 0, mode read
	LD	IY,DOS_OPEN
	LD	C,1
	CALL	CALL_USERF_GATE
	JR	C,VLF_OPEN_OK

	; Failed to open file
	LD	HL,(REQ_PKT_PTR)
	LD	DE,10
	ADD	HL,DE
	LD	(HL),0
	INC	HL
	LD	(HL),0
	LD	A,VFS_STAT_NOT_FOUND
	JP	VFS_SET_STATUS_ERR

VLF_OPEN_OK:
	; Reset host document lines via CALL_CLEAR_DOCUMENT (HOST_API+49)
	LD	HL,(HOST_API_PTR)
	LD	DE,49
	ADD	HL,DE
	CALL	CALL_INDIRECT_HL

	LD	HL,0
	LD	(LOAD_LINE_NUM),HL
	LD	(LOAD_LINE_POS),HL

	; Staging buffers in Upper Memory:
	; Line accumulator: ACTIVE_LINE_BUF (HOST_API+4)
	; Chunk read buffer: ACTIVE_LINE_BUF + 512
	LD	HL,(HOST_API_PTR)
	LD	DE,4
	ADD	HL,DE
	LD	E,(HL)
	INC	HL
	LD	D,(HL)			; DE = ACTIVE_LINE_BUF
	LD	(LOAD_LINE_BUF),DE
	LD	HL,512
	ADD	HL,DE
	LD	(LOAD_CHUNK_BUF),HL

VLF_READ_LOOP:
	LD	HL,(LOAD_CHUNK_BUF)
	LD	DE,128			; Request 128 bytes
	LD	BC,0003H		; File 0, page 3
	LD	IY,DOS_READ
	LD	C,1
	CALL	CALL_USERF_GATE

	; Bytes read = 128 - DE
	LD	A,128
	SUB	E
	JR	Z,VLF_READ_DONE
	LD	B,A			; B = Byte count read
	LD	HL,(LOAD_CHUNK_BUF)

VLF_BYTE_LOOP:
	LD	A,(HL)
	INC	HL
	CP	01AH			; CP/M EOF
	JR	Z,VLF_READ_DONE
	CP	13			; CR
	JR	Z,VLF_NEXT_BYTE
	CP	10			; LF
	JR	Z,VLF_COMMIT_LINE

	; Append character to line accumulator
	PUSH	HL
	LD	HL,(LOAD_LINE_POS)
	LD	A,H
	CP	3			; Limit 768 bytes
	JR	NC,VLF_SKIP_CHAR
	LD	DE,(LOAD_LINE_BUF)
	ADD	HL,DE
	POP	DE			; DE = Source HL
	DEC	DE
	LD	A,(DE)
	INC	DE
	PUSH	DE			; Re-save source HL
	LD	(HL),A
	LD	HL,(LOAD_LINE_POS)
	INC	HL
	LD	(LOAD_LINE_POS),HL

VLF_SKIP_CHAR:
	POP	HL
	JR	VLF_NEXT_BYTE

VLF_COMMIT_LINE:
	; Commit current line to host editor
	PUSH	BC
	PUSH	HL
	LD	HL,(LOAD_LINE_POS)
	LD	DE,(LOAD_LINE_BUF)
	ADD	HL,DE
	LD	(HL),0			; Null-terminate line
	LD	BC,(LOAD_LINE_POS)	; BC = Length
	LD	HL,(LOAD_LINE_NUM)	; HL = Line number
	LD	DE,(LOAD_LINE_BUF)	; DE = Buffer
	CALL	COMMIT_LINE_HOST
	LD	HL,(LOAD_LINE_NUM)
	INC	HL
	LD	(LOAD_LINE_NUM),HL
	LD	HL,0
	LD	(LOAD_LINE_POS),HL
	POP	HL
	POP	BC

VLF_NEXT_BYTE:
	DJNZ	VLF_BYTE_LOOP

	; Check if last chunk was partial (< 128 bytes)
	LD	A,128
	SUB	E
	CP	128
	JR	Z,VLF_READ_LOOP		; Full chunk -> read more

VLF_READ_DONE:
	; Check if trailing line pending
	LD	HL,(LOAD_LINE_POS)
	LD	A,H
	OR	L
	JR	NZ,VLF_COMMIT_FINAL
	LD	HL,(LOAD_LINE_NUM)
	LD	A,H
	OR	L
	JR	NZ,VLF_CLOSE_FILE

VLF_COMMIT_FINAL:
	LD	HL,(LOAD_LINE_POS)
	LD	DE,(LOAD_LINE_BUF)
	ADD	HL,DE
	LD	(HL),0
	LD	BC,(LOAD_LINE_POS)
	LD	HL,(LOAD_LINE_NUM)
	LD	DE,(LOAD_LINE_BUF)
	CALL	COMMIT_LINE_HOST
	LD	HL,(LOAD_LINE_NUM)
	INC	HL
	LD	(LOAD_LINE_NUM),HL

VLF_CLOSE_FILE:
	LD	B,0
	LD	IY,DOS_CLOSE
	LD	C,1
	CALL	CALL_USERF_GATE

	; Set req->count = total lines loaded
	LD	HL,(REQ_PKT_PTR)
	LD	DE,10
	ADD	HL,DE
	LD	DE,(LOAD_LINE_NUM)
	LD	(HL),E
	INC	HL
	LD	(HL),D
	XOR	A
	JP	VFS_SET_STATUS_OK

;------------------------------------------------------------------------------
; COMMIT_LINE_HOST: Invoke TRAMP_COMMIT_LINE (HOST_API+21)
; Inputs:
;   HL = Line number, DE = Buffer pointer, BC = Line length
;------------------------------------------------------------------------------
COMMIT_LINE_HOST:
	PUSH	IX
	PUSH	IY
	LD	IX,(HOST_API_PTR)
	LD	IY,(HOST_API_PTR)
	PUSH	DE
	LD	DE,21
	ADD	IY,DE
	POP	DE
	CALL	CALL_INDIRECT_IY
	POP	IY
	POP	IX
	RET

CALL_INDIRECT_IY:
	JP	(IY)

;------------------------------------------------------------------------------
; VFS_SAVE_FILE: Save entire document
;------------------------------------------------------------------------------
VFS_SAVE_FILE:
	LD	HL,(REQ_PKT_PTR)
	LD	DE,12
	ADD	HL,DE
	LD	(HL),0
	INC	HL
	LD	(HL),0			; start_line = 0
	INC	HL
	LD	(HL),0FFH
	INC	HL
	LD	(HL),0FFH		; end_line = 0xFFFF
	JR	VFS_SAVE_RANGE

;------------------------------------------------------------------------------
; VFS_SAVE_RANGE: Export host editor line range to NextZXOS file
; Inputs:
;   req->path, req->unit, req->start_line, req->end_line
; Outputs:
;   req->count = lines written; req->status = VFS_STAT_OK / DISK_ERR
;------------------------------------------------------------------------------
VFS_SAVE_RANGE:
	CALL	PREPARE_PATH		; HL = Filespec in Upper Memory
	LD	DE,0204H		; Replace if exists, create if not
	LD	BC,0002H		; File 0, mode write
	LD	IY,DOS_OPEN
	LD	C,1
	CALL	CALL_USERF_GATE
	JR	C,VSR_OPEN_OK

	LD	A,VFS_STAT_DISK_ERR
	JP	VFS_SET_STATUS_ERR

VSR_OPEN_OK:
	; Query DOC_TOTAL_LINES via HOST_API+10
	LD	HL,(HOST_API_PTR)
	LD	DE,10
	ADD	HL,DE
	LD	E,(HL)
	INC	HL
	LD	D,(HL)			; DE = Pointer to DOC_TOTAL_LINES
	LD	A,(DE)
	LD	L,A
	INC	DE
	LD	A,(DE)
	LD	H,A			; HL = Total lines count
	LD	(SAVE_TOTAL_LINES),HL

	; Check if empty document
	LD	A,H
	OR	L
	JP	Z,VSR_CLOSE_FILE

	; Read start_line (+12) and end_line (+14)
	LD	HL,(REQ_PKT_PTR)
	LD	DE,12
	ADD	HL,DE
	LD	E,(HL)
	INC	HL
	LD	D,(HL)			; DE = start_line
	LD	(SAVE_CUR_LINE),DE

	INC	HL			; +14: end_line
	LD	E,(HL)
	INC	HL
	LD	D,(HL)
	LD	HL,(SAVE_TOTAL_LINES)
	DEC	HL			; HL = max line index
	; Clamp end_line to max line index
	PUSH	HL
	AND	A
	SBC	HL,DE
	POP	HL
	JR	NC,VSR_END_OK
	EX	DE,HL
VSR_END_OK:
	LD	(SAVE_END_LINE),DE

	LD	HL,0
	LD	(SAVE_WRITTEN_CNT),HL

VSR_LINE_LOOP:
	LD	HL,(SAVE_CUR_LINE)
	LD	DE,(SAVE_END_LINE)
	PUSH	HL
	AND	A
	SBC	HL,DE
	POP	HL
	JR	C,VSR_DO_LINE
	JR	Z,VSR_DO_LINE
	JR	VSR_CLOSE_FILE

VSR_DO_LINE:
	; Checkout line via TRAMP_CHECKOUT_LINE (HOST_API+18)
	PUSH	IX
	PUSH	IY
	LD	IX,(HOST_API_PTR)
	LD	IY,(HOST_API_PTR)
	LD	DE,18
	ADD	IY,DE
	; Returns BC = length, ACTIVE_LINE_BUF has text
	CALL	CALL_INDIRECT_IY
	POP	IY
	POP	IX

	; Write line text if length > 0
	LD	A,B
	OR	C
	JR	Z,VSR_WRITE_CRLF

	PUSH	BC
	; HL = ACTIVE_LINE_BUF via HOST_API+4
	LD	HL,(HOST_API_PTR)
	LD	DE,4
	ADD	HL,DE
	LD	E,(HL)
	INC	HL
	LD	D,(HL)
	EX	DE,HL			; HL = ACTIVE_LINE_BUF
	POP	DE			; DE = Byte count (BC)
	LD	BC,0003H		; File 0, page 3
	LD	IY,DOS_WRITE
	LD	C,1
	CALL	CALL_USERF_GATE

VSR_WRITE_CRLF:
	; Write "\r\n" CRLF sequence (2 bytes)
	; Prepare CRLF in ACTIVE_LINE_BUF
	LD	HL,(HOST_API_PTR)
	LD	DE,4
	ADD	HL,DE
	LD	E,(HL)
	INC	HL
	LD	D,(HL)
	EX	DE,HL
	LD	(HL),13
	INC	HL
	LD	(HL),10
	DEC	HL			; HL = Buffer with CRLF
	LD	DE,2			; 2 bytes
	LD	BC,0003H
	LD	IY,DOS_WRITE
	LD	C,1
	CALL	CALL_USERF_GATE

	LD	HL,(SAVE_WRITTEN_CNT)
	INC	HL
	LD	(SAVE_WRITTEN_CNT),HL

	LD	HL,(SAVE_CUR_LINE)
	INC	HL
	LD	(SAVE_CUR_LINE),HL
	JR	VSR_LINE_LOOP

VSR_CLOSE_FILE:
	LD	B,0
	LD	IY,DOS_CLOSE
	LD	C,1
	CALL	CALL_USERF_GATE

	; Set req->count = lines written
	LD	HL,(REQ_PKT_PTR)
	LD	DE,10
	ADD	HL,DE
	LD	DE,(SAVE_WRITTEN_CNT)
	LD	(HL),E
	INC	HL
	LD	(HL),D
	XOR	A
	JP	VFS_SET_STATUS_OK

;------------------------------------------------------------------------------
; VFS_OPEN_FILE: Open stream handle
;------------------------------------------------------------------------------
VFS_OPEN_FILE:
	LD	A,(STREAM_IS_OPEN)
	OR	A
	JR	Z,VOF_DO_OPEN
	; Close active stream first
	LD	B,0
	LD	IY,DOS_CLOSE
	LD	C,1
	CALL	CALL_USERF_GATE
	XOR	A
	LD	(STREAM_IS_OPEN),A

VOF_DO_OPEN:
	CALL	PREPARE_PATH
	LD	DE,0002H		; Open existing
	LD	BC,0001H		; File 0, read
	LD	IY,DOS_OPEN
	LD	C,1
	CALL	CALL_USERF_GATE
	JR	C,VOF_OPEN_OK

	LD	A,VFS_STAT_NOT_FOUND
	JP	VFS_SET_STATUS_ERR

VOF_OPEN_OK:
	LD	A,1
	LD	(STREAM_IS_OPEN),A
	XOR	A
	JP	VFS_SET_STATUS_OK

;------------------------------------------------------------------------------
; VFS_READ_CHUNK: Read raw bytes from open stream
; Inputs:
;   req->buffer, req->buffer_size
; Outputs:
;   req->count = bytes read; req->status = VFS_STAT_OK / EOF / DISK_ERR
;------------------------------------------------------------------------------
VFS_READ_CHUNK:
	LD	A,(STREAM_IS_OPEN)
	OR	A
	JR	NZ,VRC_HAVE_STREAM

	LD	A,VFS_STAT_DISK_ERR
	JP	VFS_SET_STATUS_ERR

VRC_HAVE_STREAM:
	; Destination: req->buffer at +6
	LD	HL,(REQ_PKT_PTR)
	LD	DE,6
	ADD	HL,DE
	LD	E,(HL)
	INC	HL
	LD	D,(HL)			; DE = req->buffer
	PUSH	DE			; Save buffer pointer

	; Capacity: req->buffer_size at +8
	INC	HL
	LD	E,(HL)
	INC	HL
	LD	D,(HL)			; DE = Requested byte count
	LD	(CHUNK_REQ_SIZE),DE

	POP	HL			; HL = Destination buffer
	LD	BC,0003H		; File 0, page 3
	LD	IY,DOS_READ
	LD	C,1
	CALL	CALL_USERF_GATE

	; Bytes read = CHUNK_REQ_SIZE - DE
	LD	HL,(CHUNK_REQ_SIZE)
	AND	A
	SBC	HL,DE			; HL = Actual bytes read

	; Set req->count at +10
	PUSH	HL
	LD	HL,(REQ_PKT_PTR)
	LD	DE,10
	ADD	HL,DE
	POP	DE
	LD	(HL),E
	INC	HL
	LD	(HL),D

	; Check if 0 bytes read -> EOF
	LD	A,D
	OR	E
	JR	Z,VRC_EOF

	XOR	A
	JP	VFS_SET_STATUS_OK

VRC_EOF:
	LD	A,VFS_STAT_EOF
	JP	VFS_SET_STATUS_OK

;------------------------------------------------------------------------------
; VFS_CLOSE_FILE: Close stream handle
;------------------------------------------------------------------------------
VFS_CLOSE_FILE:
	LD	A,(STREAM_IS_OPEN)
	OR	A
	JR	Z,VCF_DONE
	XOR	A
	LD	(STREAM_IS_OPEN),A
	LD	B,0
	LD	IY,DOS_CLOSE
	LD	C,1
	CALL	CALL_USERF_GATE
VCF_DONE:
	XOR	A
	JP	VFS_SET_STATUS_OK

;------------------------------------------------------------------------------
; Internal State & Working Variables
;------------------------------------------------------------------------------
SAVED_SP:		DW	0
HOST_API_PTR:		DW	0
REQ_PKT_PTR:		DW	0
DEF_DRV_UNIT:		DB	2	; Default C: (unit 2)
STREAM_IS_OPEN:		DB	0
CHUNK_REQ_SIZE:		DW	0

CAT_DRV_IDX:		DB	0
CAT_OUT_PTR:		DW	0
CAT_MAX_ENTRIES:	DB	0
CAT_CUR_COUNT:		DB	0
CAT_PARAM_PTR:		DW	0
CAT_BUF_PTR:		DW	0

LOAD_LINE_NUM:		DW	0
LOAD_LINE_POS:		DW	0
LOAD_LINE_BUF:		DW	0
LOAD_CHUNK_BUF:		DW	0

SAVE_TOTAL_LINES:	DW	0
SAVE_CUR_LINE:		DW	0
SAVE_END_LINE:		DW	0
SAVE_WRITTEN_CNT:	DW	0
