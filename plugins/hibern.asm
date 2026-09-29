;==============================================================================
; HIBERN.ASM - RomWBW RAM Drive Hibernation & Restoration Overlay for SE.COM
; Digital Research CP/M 3 Overlay / PRL Format (Target: 4KB TPA Execution)
;
; Dumps RomWBW MD0:0 physical banks (0x81..0x88, 256KB) to RAMDRV.IMG on startup
; and restores them upon exit, unlocking 12 Far RAM banks for the editor buffer.
;
; Entry Jump Table:
;   +0: Action 0 (Detect RomWBW RAM drive)
;   +3: Action 1 (Hibernate RAM drive -> RAMDRV.IMG)
;   +6: Action 2 (Restore RAM drive <- RAMDRV.IMG)
;==============================================================================

	ORG	0100H

;------------------------------------------------------------------------------
; Constants & BDOS / HBIOS Vectors
;------------------------------------------------------------------------------
BDOS_ENTRY		EQU	0005H
RAMDRV_START_BANK	EQU	081H	; RomWBW MD0:0 starts at bank 0x81
RAMDRV_END_BANK		EQU	088H	; RomWBW MD0:0 ends at bank 0x88 (8 banks)
RAMDRV_MODE_PROTECTED	EQU	0
RAMDRV_MODE_ENABLED	EQU	1
RAMDRV_MODE_HIBERNATE	EQU	2
DEFAULT_DMA		EQU	0080H

;------------------------------------------------------------------------------
; Entry Jump Table
;------------------------------------------------------------------------------
ENTRY:
	JP	HIB_ACTION_DETECT	; +0: Action 0: Detect RAM drive
	JP	HIB_ACTION_HIBERNATE	; +3: Action 1: Detect & Hibernate
	JP	HIB_ACTION_RESTORE	; +6: Action 2: Restore RAM drive

;==============================================================================
; Action 0: Detect RomWBW RAM Drive
; Returns:
;   Carry = 0: Found
;              A = 0-based drive index (0=A, 1=B, ..., 15=P)
;              C = Drive character ('A'..'P')
;   Carry = 1: None found
;              A = 0xFF
;              C = '?'
;==============================================================================
HIB_ACTION_DETECT:
	LD	A,0FFH
	LD	(RAMDRIVE_DRIVE_NUM),A
	LD	A,'?'
	LD	(RAMDRIVE_DRIVE_CHAR),A

	; Check HBIOS presence
	CALL	HBIOS_DETECT
	JP	NZ,HAD_NOT_FOUND

	; Query CP/M version via BDOS 12
	LD	C,12
	CALL	BDOS_ENTRY
	LD	(CPM_VERSION_ID),HL
	LD	A,L
	CP	030H
	JP	NC,HAD_CPM3

	; CP/M 2.2: Check RomWBW CBIOS page zero stamp at 0x0040 ('W') & 0x0041
	LD	HL,0040H
	LD	A,(HL)
	CP	'W'
	JP	NZ,HAD_NOT_FOUND
	INC	HL
	LD	A,(HL)
	CP	0A8H			; ~'W'
	JP	NZ,HAD_NOT_FOUND

	; Word at 0x0044 is pointer to CBIOS extension (CBX)
	LD	HL,(0044H)
	; DRVMAPADR is at CBX + 2
	INC	HL
	INC	HL
	LD	E,(HL)
	INC	HL
	LD	D,(HL)			; DE = DRVMAPADR
	LD	A,D
	OR	E
	JP	Z,HAD_NOT_FOUND

	; DRVCNT is at DRVMAPADR - 1
	EX	DE,HL			; HL = DRVMAPADR
	DEC	HL
	LD	A,(HL)			; A = DRVCNT
	INC	HL			; HL = DRVMAPADR
	OR	A
	JP	Z,HAD_NOT_FOUND
	CP	17
	JP	NC,HAD_NOT_FOUND

	LD	B,A			; B = loop counter (DRVCNT)
	LD	C,0			; C = CP/M drive index (0=A, 1=B...)

HAD_CBIOS_LOOP:
	LD	A,(HL)			; A = HBIOS Disk Unit
	INC	HL
	INC	HL
	INC	HL
	INC	HL
	CP	0FFH
	JR	Z,HAD_CBIOS_NEXT

	PUSH	BC
	PUSH	HL
	LD	C,A			; C = HBIOS Disk Unit
	LD	B,17H			; BF_DIODEVICE (0x17)
	PUSH	IX
	RST	08H			; D = Device Type, E = Phys Unit
	POP	IX
	LD	A,D
	CP	00H			; DIODEV_MD (0x00)
	JR	NZ,HAD_CBIOS_NOT_MD
	LD	A,E
	CP	00H			; Physical Unit 0 = MD0 (RAM disk)
	JR	NZ,HAD_CBIOS_NOT_MD

	; Match found!
	POP	HL
	POP	BC
	LD	A,C
	LD	(RAMDRIVE_DRIVE_NUM),A
	ADD	A,'A'
	CALL	SET_RAMDRIVE_CHAR
	LD	A,(RAMDRIVE_DRIVE_NUM)
	LD	B,A
	LD	A,(RAMDRIVE_DRIVE_CHAR)
	LD	C,A
	OR	A			; Carry = 0
	RET

HAD_CBIOS_NOT_MD:
	POP	HL
	POP	BC

HAD_CBIOS_NEXT:
	INC	C
	DJNZ	HAD_CBIOS_LOOP
	JP	HAD_NOT_FOUND

HAD_CPM3:
	; Call BDOS 50: BIOS 22 (DRVTBL)
	LD	A,22
	LD	(CPM3_BIOSPB_FUNC),A
	XOR	A
	LD	(CPM3_BIOSPB_A),A
	LD	HL,0
	LD	(CPM3_BIOSPB_BC),HL
	LD	(CPM3_BIOSPB_DE),HL
	LD	(CPM3_BIOSPB_HL),HL
	LD	DE,CPM3_BIOSPB
	LD	C,50
	CALL	BDOS_ENTRY
	LD	A,H
	OR	L
	JP	Z,HAD_NOT_FOUND
	LD	(CPM3_DRVTBL_PTR),HL

	; Query System Bank ID from HBIOS (SYSGET BNKINFO: B=0xF8, C=0xF2)
	PUSH	IX
	LD	B,0F8H
	LD	C,0F2H
	RST	08H
	POP	IX
	LD	A,E
	LD	(CPM3_SYS_BANK),A

	; Query User Bank ID from HBIOS (SYSGETBNK: B=0xF3)
	PUSH	IX
	LD	B,0F3H
	RST	08H
	POP	IX
	LD	A,C
	LD	(CPM_USER_BANK),A

	; Iterate through 16 drive entries in DRVTBL
	LD	HL,(CPM3_DRVTBL_PTR)
	LD	B,16
	LD	C,0

HAD_CPM3_LOOP:
	PUSH	BC
	PUSH	HL

	LD	E,(HL)
	INC	HL
	LD	D,(HL)			; DE = DPH address
	LD	A,D
	OR	E
	JP	Z,HAD_CPM3_NEXT

	DEC	DE
	DEC	DE			; DE = DPH - 2
	EX	DE,HL			; HL = DPH - 2

	; Copy 2 bytes from SYS_BANK:(DPH-2) to CPM_USER_BANK:(CPM3_DPH_BUF)
	PUSH	HL
	PUSH	IX
	LD	B,0F4H			; SYSSETCPY
	LD	A,(CPM_USER_BANK)
	LD	D,A
	LD	A,(CPM3_SYS_BANK)
	LD	E,A
	LD	HL,2
	RST	08H
	POP	IX
	POP	HL

	LD	DE,CPM3_DPH_BUF
	PUSH	IX
	LD	B,0F5H			; SYSBNKCPY
	RST	08H
	POP	IX

	LD	A,(CPM3_DPH_BUF)
	LD	C,A
	LD	B,17H			; BF_DIODEVICE
	PUSH	IX
	RST	08H
	POP	IX
	LD	A,D
	OR	A
	JR	NZ,HAD_CPM3_NOT_MD
	LD	A,E
	OR	A
	JR	NZ,HAD_CPM3_NOT_MD

	; Match found!
	POP	HL
	POP	BC
	LD	A,C
	LD	(RAMDRIVE_DRIVE_NUM),A
	ADD	A,'A'
	CALL	SET_RAMDRIVE_CHAR
	LD	A,(RAMDRIVE_DRIVE_NUM)
	LD	B,A
	LD	A,(RAMDRIVE_DRIVE_CHAR)
	LD	C,A
	OR	A			; Carry = 0
	RET

HAD_CPM3_NOT_MD:
HAD_CPM3_NEXT:
	POP	HL
	INC	HL
	INC	HL
	POP	BC
	INC	C
	DEC	B
	JP	NZ,HAD_CPM3_LOOP
	JR	HAD_NOT_FOUND

HAD_NOT_FOUND:
	LD	A,0FFH
	LD	(RAMDRIVE_DRIVE_NUM),A
	LD	A,'?'
	LD	(RAMDRIVE_DRIVE_CHAR),A
	LD	C,A
	SCF
	RET

;==============================================================================
; Action 1: Hibernate RomWBW RAM Drive
; Inputs:
;   A  = CURRENT_DEFAULT_DRIVE (0-based)
;   DE = Pointer to WORK_FCB
;   C  = HAS_FILE_ARG (0=none, 1=has arg)
;   B  = Requested Mode (1=RAMDRV_MODE_ENABLED, 2=RAMDRV_MODE_HIBERNATE)
; Returns:
;   Carry = 0: Success
;              A = 1 (RAMDRIVE_IS_HIBERNATED) if Mode 2, or 0 if Mode 1
;              B = RAMDRIVE_DRIVE_NUM
;              C = RAMDRIVE_DRIVE_CHAR
;              D = Requested Mode (1 or 2)
;   Carry = 1: Aborted / Failed (reverted to protected)
;              A = 0 (RAMDRIVE_IS_HIBERNATED)
;              B = RAMDRIVE_DRIVE_NUM
;              C = RAMDRIVE_DRIVE_CHAR
;              D = 0 (RAMDRV_MODE_PROTECTED)
;==============================================================================
HIB_ACTION_HIBERNATE:
	LD	(PARAM_CUR_DRV),A
	LD	(PARAM_WORK_FCB),DE
	LD	A,C
	LD	(PARAM_HAS_FILE),A
	LD	A,B
	LD	(PARAM_REQ_MODE),A

	; 1. Detect RAM drive
	CALL	HIB_ACTION_DETECT
	JP	C,HAH_FAIL_NO_RAMDRV

	; 2. Safety Check 1: Prohibit hibernating if running from RAM drive
	LD	A,(PARAM_CUR_DRV)
	LD	HL,RAMDRIVE_DRIVE_NUM
	CP	(HL)
	JP	Z,HAH_FAIL_ACTIVE_DRV

	; 3. Safety Check 2: Prohibit hibernating if target file is on RAM drive
	LD	A,(PARAM_HAS_FILE)
	OR	A
	JR	Z,HAH_CHECK_MODE

	LD	HL,(PARAM_WORK_FCB)
	LD	A,(HL)
	OR	A
	JR	NZ,HAH_TARGET_EXP
	LD	A,(PARAM_CUR_DRV)
	JR	HAH_TARGET_CMP

HAH_TARGET_EXP:
	DEC	A			; 1->0 (A:), 2->1 (B:)...

HAH_TARGET_CMP:
	LD	HL,RAMDRIVE_DRIVE_NUM
	CP	(HL)
	JP	Z,HAH_FAIL_TARGET_FILE

HAH_CHECK_MODE:
	LD	A,(PARAM_REQ_MODE)
	CP	RAMDRV_MODE_HIBERNATE
	JR	Z,HAH_CHECK_SPACE

	; Mode 1 (Enabled / Raw): Safe to use, do not dump to disk
	LD	A,(RAMDRIVE_DRIVE_NUM)
	LD	B,A
	LD	A,(RAMDRIVE_DRIVE_CHAR)
	LD	C,A
	LD	D,RAMDRV_MODE_ENABLED
	XOR	A			; A = 0 (RAMDRIVE_IS_HIBERNATED)
	OR	A			; Carry = 0
	RET

HAH_CHECK_SPACE:
	; 4. Safety Check 3: Check DPB disk size (DSM >= 200 blocks)
	LD	C,31			; BDOS Get DPB
	CALL	BDOS_ENTRY		; HL = DPB address
	INC	HL
	INC	HL
	INC	HL
	INC	HL
	INC	HL
	LD	E,(HL)
	INC	HL
	LD	D,(HL)			; DE = DSM
	LD	A,D
	OR	A
	JR	NZ,HAH_SPACE_OK
	LD	A,E
	CP	200
	JP	C,HAH_FAIL_TOO_SMALL

HAH_SPACE_OK:
	; Query CPM_USER_BANK
	PUSH	IX
	LD	B,0F3H			; SYSGETBNK
	RST	08H
	POP	IX
	LD	A,C
	LD	(CPM_USER_BANK),A

	; Check for orphaned RAMDRV.IMG from previous crash
	CALL	INIT_RAMDRV_FCB
	LD	DE,HIB_FCB
	LD	C,15			; BDOS Open File
	CALL	BDOS_ENTRY
	CP	0FFH
	JR	Z,HAH_NO_ORPHAN

	; Orphan found! Restore it first
	LD	DE,STR_MSG_ORPHAN_FOUND
	CALL	PRINT_STR
	CALL	HIB_DO_RESTORE_BODY
	JP	C,HAH_WRITE_ERR
	LD	DE,STR_MSG_REST_DONE
	CALL	PRINT_STR

HAH_NO_ORPHAN:
	; Delete old RAMDRV.IMG
	CALL	INIT_RAMDRV_FCB
	LD	DE,HIB_FCB
	LD	C,19			; BDOS Delete File
	CALL	BDOS_ENTRY

	; Create new RAMDRV.IMG
	CALL	INIT_RAMDRV_FCB
	LD	DE,HIB_FCB
	LD	C,22			; BDOS Make File
	CALL	BDOS_ENTRY
	CP	0FFH
	JP	Z,HAH_CREATE_ERR

	; Display Hibernating banner
	LD	DE,STR_MSG_HIBERNATING
	CALL	PRINT_STR

	; Set BDOS DMA buffer to HIB_DMA_BUF
	LD	DE,HIB_DMA_BUF
	LD	C,26			; BDOS Set DMA
	CALL	BDOS_ENTRY

	; Outer Loop: Bank 0x81 through 0x88 (8 banks)
	LD	A,RAMDRV_START_BANK
	LD	(HIB_CUR_BANK),A

HAH_BANK_LOOP:
	LD	HL,0
	LD	(HIB_FAR_OFFSET),HL

HAH_SECTOR_LOOP:
	PUSH	IX
	LD	B,0F4H			; SYSSETCPY
	LD	A,(CPM_USER_BANK)
	LD	D,A
	LD	A,(HIB_CUR_BANK)
	LD	E,A
	LD	HL,128
	RST	08H
	POP	IX

	LD	HL,(HIB_FAR_OFFSET)
	LD	DE,HIB_DMA_BUF
	PUSH	IX
	LD	B,0F5H			; SYSBNKCPY
	RST	08H
	POP	IX

	; Write sector to disk
	LD	DE,HIB_FCB
	LD	C,21			; BDOS Write Sequential
	CALL	BDOS_ENTRY
	OR	A
	JR	NZ,HAH_WRITE_ERR

	LD	HL,(HIB_FAR_OFFSET)
	LD	DE,128
	ADD	HL,DE
	LD	(HIB_FAR_OFFSET),HL
	LD	A,H
	CP	080H			; 32KB reached?
	JR	NZ,HAH_SECTOR_LOOP

	LD	A,(HIB_CUR_BANK)
	INC	A
	LD	(HIB_CUR_BANK),A
	CP	RAMDRV_END_BANK + 1
	JR	NZ,HAH_BANK_LOOP

	; Close RAMDRV.IMG
	LD	DE,HIB_FCB
	LD	C,16			; BDOS Close File
	CALL	BDOS_ENTRY
	CP	0FFH
	JR	Z,HAH_CREATE_ERR

	; Reset DMA to default
	LD	DE,DEFAULT_DMA
	LD	C,26
	CALL	BDOS_ENTRY

	; Print completion banner
	LD	DE,STR_MSG_HIB_DONE
	CALL	PRINT_STR

	; Success exit
	LD	A,(RAMDRIVE_DRIVE_NUM)
	LD	B,A
	LD	A,(RAMDRIVE_DRIVE_CHAR)
	LD	C,A
	LD	D,RAMDRV_MODE_HIBERNATE
	LD	A,1			; RAMDRIVE_IS_HIBERNATED = 1
	OR	A			; Carry = 0
	RET

HAH_FAIL_NO_RAMDRV:
	XOR	A
	LD	B,0FFH
	LD	C,'?'
	LD	D,RAMDRV_MODE_PROTECTED
	SCF
	RET

HAH_FAIL_ACTIVE_DRV:
	LD	DE,STR_MSG_HIB_DRV_ERR
	CALL	PRINT_STR
	CALL	DELAY_BRIEF
	JR	HAH_FAIL_COMMON

HAH_FAIL_TARGET_FILE:
	LD	DE,STR_MSG_HIB_FILE_ERR
	CALL	PRINT_STR
	CALL	DELAY_BRIEF
	JR	HAH_FAIL_COMMON

HAH_FAIL_TOO_SMALL:
	LD	DE,STR_MSG_HIB_TOO_SMALL
	CALL	PRINT_STR
	CALL	DELAY_BRIEF
	JR	HAH_FAIL_COMMON

HAH_WRITE_ERR:
HAH_CREATE_ERR:
	; Cleanup partial file and reset DMA
	LD	DE,HIB_FCB
	LD	C,16			; BDOS Close
	CALL	BDOS_ENTRY
	CALL	INIT_RAMDRV_FCB
	LD	DE,HIB_FCB
	LD	C,19			; BDOS Delete
	CALL	BDOS_ENTRY
	LD	DE,DEFAULT_DMA
	LD	C,26			; BDOS Set DMA
	CALL	BDOS_ENTRY
	LD	DE,STR_MSG_HIB_ERR
	CALL	PRINT_STR

HAH_FAIL_COMMON:
	LD	A,(RAMDRIVE_DRIVE_NUM)
	LD	B,A
	LD	A,(RAMDRIVE_DRIVE_CHAR)
	LD	C,A
	LD	D,RAMDRV_MODE_PROTECTED
	XOR	A			; RAMDRIVE_IS_HIBERNATED = 0
	SCF				; Carry = 1
	RET

;==============================================================================
; Action 2: Restore RomWBW RAM Drive
; Returns:
;   Carry = 0: Restored successfully
;   Carry = 1: Error during restore
;==============================================================================
HIB_ACTION_RESTORE:
	; Ensure RAM drive letter is detected and known
	CALL	HIB_ACTION_DETECT

	; Query CPM_USER_BANK
	PUSH	IX
	LD	B,0F3H			; SYSGETBNK
	RST	08H
	POP	IX
	LD	A,C
	LD	(CPM_USER_BANK),A

	; Display Restoring banner
	LD	DE,STR_MSG_RESTORING
	CALL	PRINT_STR

	CALL	HIB_DO_RESTORE_BODY
	JR	C,HAR_FAILED

	; Successfully restored!
	LD	DE,STR_MSG_REST_DONE
	CALL	PRINT_STR
	OR	A			; Carry = 0
	RET

HAR_FAILED:
	LD	DE,STR_MSG_REST_ERR
	CALL	PRINT_STR
	SCF
	RET

;==============================================================================
; HIB_DO_RESTORE_BODY:
; Reads RAMDRV.IMG from disk and writes sectors into Far RAM banks 0x81..0x88.
; Deletes RAMDRV.IMG upon completion.
; Returns: Carry = 0 on success, Carry = 1 on failure.
;==============================================================================
HIB_DO_RESTORE_BODY:
	; Set BDOS DMA buffer to HIB_DMA_BUF
	LD	DE,HIB_DMA_BUF
	LD	C,26			; BDOS Set DMA
	CALL	BDOS_ENTRY

	; Open RAMDRV.IMG
	CALL	INIT_RAMDRV_FCB
	LD	DE,HIB_FCB
	LD	C,15			; BDOS Open File
	CALL	BDOS_ENTRY
	CP	0FFH
	JR	Z,HRB_OPEN_ERR

	; Ensure CR = 0
	XOR	A
	LD	(HIB_FCB + 32),A

	; Outer Loop: Bank 0x81 through 0x88
	LD	A,RAMDRV_START_BANK
	LD	(HIB_CUR_BANK),A

HRB_BANK_LOOP:
	LD	HL,0
	LD	(HIB_FAR_OFFSET),HL

HRB_SECTOR_LOOP:
	; Read 128 bytes from disk into HIB_DMA_BUF
	LD	DE,HIB_FCB
	LD	C,20			; BDOS Read Sequential
	CALL	BDOS_ENTRY
	OR	A
	JR	NZ,HRB_READ_ERR

	PUSH	IX
	LD	B,0F4H			; SYSSETCPY
	LD	A,(HIB_CUR_BANK)
	LD	D,A
	LD	A,(CPM_USER_BANK)
	LD	E,A
	LD	HL,128
	RST	08H
	POP	IX

	LD	HL,HIB_DMA_BUF
	LD	DE,(HIB_FAR_OFFSET)
	PUSH	IX
	LD	B,0F5H			; SYSBNKCPY
	RST	08H
	POP	IX

	LD	HL,(HIB_FAR_OFFSET)
	LD	DE,128
	ADD	HL,DE
	LD	(HIB_FAR_OFFSET),HL
	LD	A,H
	CP	080H			; 32KB reached?
	JR	NZ,HRB_SECTOR_LOOP

	LD	A,(HIB_CUR_BANK)
	INC	A
	LD	(HIB_CUR_BANK),A
	CP	RAMDRV_END_BANK + 1
	JR	NZ,HRB_BANK_LOOP

	; Close RAMDRV.IMG
	LD	DE,HIB_FCB
	LD	C,16			; BDOS Close File
	CALL	BDOS_ENTRY

	; Delete RAMDRV.IMG to free disk space
	CALL	INIT_RAMDRV_FCB
	LD	DE,HIB_FCB
	LD	C,19			; BDOS Delete File
	CALL	BDOS_ENTRY

	; Reset DMA buffer
	LD	DE,DEFAULT_DMA
	LD	C,26
	CALL	BDOS_ENTRY

	AND	A			; Carry = 0 (success)
	RET

HRB_READ_ERR:
HRB_OPEN_ERR:
	LD	DE,HIB_FCB
	LD	C,16			; BDOS Close
	CALL	BDOS_ENTRY
	LD	DE,DEFAULT_DMA
	LD	C,26			; BDOS Set DMA
	CALL	BDOS_ENTRY
	SCF				; Carry = 1 (error)
	RET

;==============================================================================
; Helper Routines
;==============================================================================
HBIOS_DETECT:
	PUSH	IX
	LD	B,0F8H			; CIOCNT
	LD	C,000H
	RST	08H
	POP	IX
	OR	A
	RET

INIT_RAMDRV_FCB:
	LD	HL,HIB_FCB
	LD	(HL),0			; Current default drive
	INC	HL
	LD	DE,STR_RAMDRV_FILENAME	; "RAMDRV  IMG"
	LD	B,11
IRF_COPY:
	LD	A,(DE)
	LD	(HL),A
	INC	HL
	INC	DE
	DJNZ	IRF_COPY
	LD	B,24
IRF_ZERO:
	LD	(HL),0
	INC	HL
	DJNZ	IRF_ZERO
	RET

SET_RAMDRIVE_CHAR:
	LD	(RAMDRIVE_DRIVE_CHAR),A
	LD	(STR_MSG_HIB_LETTER),A
	LD	(STR_MSG_REST_LETTER),A
	LD	(STR_MSG_REST_DONE_LTR),A
	LD	(STR_MSG_ORPHAN_LETTER),A
	LD	(STR_MSG_HIB_DRV_CHAR),A
	LD	(STR_MSG_HIB_FILE_CHAR),A
	RET

PRINT_STR:
	PUSH	BC
	PUSH	DE
	LD	C,9
	CALL	BDOS_ENTRY
	POP	DE
	POP	BC
	RET

DELAY_BRIEF:
	PUSH	BC
	LD	B,010H
DELAY_OUTER:
	LD	C,0FFH
DELAY_INNER:
	DEC	C
	JR	NZ,DELAY_INNER
	DJNZ	DELAY_OUTER
	POP	BC
	RET

;==============================================================================
; Static Strings & Messages
;==============================================================================
STR_RAMDRV_FILENAME:	DB	"RAMDRV  IMG"

STR_MSG_HIBERNATING:
	DB	13,10,"[SE] Hibernating RAM drive ("
STR_MSG_HIB_LETTER:
	DB	"A:) to RAMDRV.IMG... $"

STR_MSG_HIB_DONE:
	DB	"[Done: 256 KB preserved]",13,10,"$"

STR_MSG_RESTORING:
	DB	13,10,"[SE] Restoring RAM drive ("
STR_MSG_REST_LETTER:
	DB	"A:) from RAMDRV.IMG... $"

STR_MSG_REST_DONE:
	DB	"[Done: RAM drive ("
STR_MSG_REST_DONE_LTR:
	DB	"A:) restored]",13,10,"$"

STR_MSG_ORPHAN_FOUND:
	DB	13,10,"[SE] Existing RAMDRV.IMG found! Restoring RAM drive ("
STR_MSG_ORPHAN_LETTER:
	DB	"A:)... $"

STR_MSG_HIB_DRV_ERR:
	DB	13,10,"[SE] Active drive is RAM drive ("
STR_MSG_HIB_DRV_CHAR:
	DB	"A:). RAM drive protected.",13,10,"$"

STR_MSG_HIB_FILE_ERR:
	DB	13,10,"[SE] Target file is on RAM drive ("
STR_MSG_HIB_FILE_CHAR:
	DB	"A:). RAM drive protected.",13,10,"$"

STR_MSG_HIB_TOO_SMALL:
	DB	13,10,"[SE] Active drive has insufficient space (<256KB). "
	DB	"RAM drive protected.",13,10,"$"

STR_MSG_HIB_ERR:
	DB	13,10,"[Error] Hibernation failed. RAM drive protected.",13,10,"$"

STR_MSG_REST_ERR:
	DB	13,10,"[Error] RAM drive restoration incomplete.",13,10,"$"

;==============================================================================
; Variables & Buffers
;==============================================================================
RAMDRIVE_DRIVE_NUM:	DB	0FFH
RAMDRIVE_DRIVE_CHAR:	DB	'?'
CPM_USER_BANK:		DB	0
CPM_VERSION_ID:		DW	0
PARAM_CUR_DRV:		DB	0
PARAM_WORK_FCB:		DW	0
PARAM_HAS_FILE:		DB	0
PARAM_REQ_MODE:		DB	0
HIB_CUR_BANK:		DB	0
HIB_FAR_OFFSET:		DW	0

CPM3_DRVTBL_PTR:	DW	0
CPM3_SYS_BANK:		DB	0
CPM3_DPH_BUF:		DS	2

CPM3_BIOSPB:
CPM3_BIOSPB_FUNC:	DB	0
CPM3_BIOSPB_A:		DB	0
CPM3_BIOSPB_BC:		DW	0
CPM3_BIOSPB_DE:		DW	0
CPM3_BIOSPB_HL:		DW	0

HIB_FCB:		DS	36
HIB_DMA_BUF:		DS	128
