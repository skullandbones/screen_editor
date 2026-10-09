;==============================================================================
; HAL_NEXT_STORAGE.ASM: Hardware Abstraction Layer - Native Next Storage Driver
;
; Purpose:
;   Implements native NextZXOS / ESXDOS file system services via RST 08h
;   system calls (F_OPEN, F_CLOSE, F_READ, F_WRITE, F_SEEK, F_OPENDIR).
;   Provides direct FAT16/FAT32 SD card file access for Profile 3
;   (Native ZX Spectrum Next / NextZXOS).
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; NextZXOS / ESXDOS RST 08h Syscall Definitions
;------------------------------------------------------------------------------
ESX_RST_SYS		EQU	008H	; RST 08h: ESXDOS system call vector

ESX_SYS_M_GETSETDRV	EQU	137	; M_GETSETDRV: Get/set current drive
ESX_SYS_F_OPEN		EQU	154	; F_OPEN: Open / create file
ESX_SYS_F_CLOSE		EQU	155	; F_CLOSE: Close file handle
ESX_SYS_F_SYNC		EQU	156	; F_SYNC: Flush cached writes
ESX_SYS_F_READ		EQU	157	; F_READ: Read byte block
ESX_SYS_F_WRITE		EQU	158	; F_WRITE: Write byte block
ESX_SYS_F_SEEK		EQU	159	; F_SEEK: Set 32-bit file position
ESX_SYS_F_OPENDIR	EQU	163	; F_OPENDIR: Open directory stream
ESX_SYS_F_READDIR	EQU	164	; F_READDIR: Read directory entry

; File Access Modes
ESX_MODE_READ		EQU	001H	; Open for read access
ESX_MODE_WRITE		EQU	002H	; Open for write access
ESX_MODE_OPEN_EXIST	EQU	000H	; Open existing file (error if missing)
ESX_MODE_OPEN_CREAT	EQU	008H	; Open existing or create if missing
ESX_MODE_CREAT_TRUNC	EQU	00CH	; Create new or truncate existing file

ESX_DRIVE_CURRENT	EQU	02AH	; Drive '*' = current active drive

;------------------------------------------------------------------------------
; Native Next Storage State Variables & Overlaid Buffers
;------------------------------------------------------------------------------
NATIVE_FT_ENTRIES	EQU	4
NATIVE_FILE_TABLE:	DS	12	; 4 entries (FCB DW, Handle DB)
NATIVE_DMA_ADDR:	DW	DEFAULT_DMA ; Current DMA address
NEXT_DIR_HANDLE:	DB	0	; Active directory handle
NEXT_DOT_PATH:		DB	".",0	; Current directory string
NEXT_SEEK_B0:		DB	0
NEXT_SEEK_B1:		DB	0
NEXT_SEEK_B2:		DB	0

; Scratch buffers overlaid on SPLIT_LINE_TEMP (1024 bytes) to save image size
NEXT_DIR_ENTRY_BUF	EQU	SPLIT_LINE_TEMP		; 260 bytes
NATIVE_PATH_BUF		EQU	SPLIT_LINE_TEMP + 260	; 64 bytes

;==============================================================================
; Native BDOS Compatibility Shim for NextZXOS
; Maps CP/M BDOS calls (CALL BDOS_ENTRY) to NextZXOS ESXDOS RST 08h syscalls
;==============================================================================

;------------------------------------------------------------------------------
; NATIVE_BDOS_ENTRY: Core BDOS emulation entry point
;
; Inputs:
;   C = BDOS Function Number
;   DE = Parameter (e.g. FCB address, string address, byte value in E)
;
; Outputs:
;   A = Return value (or HL for 16-bit returns like version / login vector)
;
; Preserves / Modifies:
;   Follows CP/M BDOS calling convention.
;------------------------------------------------------------------------------
NATIVE_BDOS_ENTRY:
	LD A,C
	CP 26				; BDOS 26: Set DMA Address
	JR Z,NBDOS_SET_DMA
	CP 25				; BDOS 25: Return Current Disk
	JR Z,NBDOS_GET_DISK
	CP 14				; BDOS 14: Select Disk
	JR Z,NBDOS_SELECT_DISK
	CP 32				; BDOS 32: Get/Set User Area
	JR Z,NBDOS_GETSET_USER
	CP 12				; BDOS 12: Return Version
	JR Z,NBDOS_VERSION
	CP 24				; BDOS 24: Return Login Vector
	JR Z,NBDOS_LOGIN_VEC
	CP 15				; BDOS 15: Open File
	JP Z,NBDOS_OPEN_FILE
	CP 16				; BDOS 16: Close File
	JP Z,NBDOS_CLOSE_FILE
	CP 19				; BDOS 19: Delete File
	JP Z,NBDOS_DELETE_FILE
	CP 20				; BDOS 20: Read Sequential
	JP Z,NBDOS_READ_SEQ
	CP 21				; BDOS 21: Write Sequential
	JP Z,NBDOS_WRITE_SEQ
	CP 22				; BDOS 22: Make File
	JP Z,NBDOS_MAKE_FILE
	CP 33				; BDOS 33: Read Random
	JP Z,NBDOS_READ_RAND
	CP 34				; BDOS 34: Write Random
	JP Z,NBDOS_WRITE_RAND
	CP 35				; BDOS 35: Compute File Size
	JP Z,NBDOS_COMPUTE_SIZE
	CP 17				; BDOS 17: Search First
	JP Z,NBDOS_SEARCH_FIRST
	CP 18				; BDOS 18: Search Next
	JP Z,NBDOS_SEARCH_NEXT
	CP 2				; BDOS 2: Console Output
	JR Z,NBDOS_CON_OUT
	CP 6				; BDOS 6: Direct Console I/O
	JR Z,NBDOS_CON_DIRECT
	CP 9				; BDOS 9: Print String '$'
	JR Z,NBDOS_PRINT_STR
	CP 11				; BDOS 11: Console Status
	JR Z,NBDOS_CON_STATUS
	CP 1				; BDOS 1: Console Input
	JR Z,NBDOS_CON_IN
	XOR A
	RET

; Console Handlers
NBDOS_SET_DMA:
	LD (NATIVE_DMA_ADDR),DE
	XOR A
	RET

NBDOS_GET_DISK:
	LD A,(CURRENT_DEFAULT_DRIVE)
	RET

NBDOS_SELECT_DISK:
	LD A,E
	LD (CURRENT_DEFAULT_DRIVE),A
	XOR A
	RET

NBDOS_GETSET_USER:
	LD A,E
	CP 0FFH
	JR Z,NBDOS_GET_USER
	LD (ORIG_CPM_USER),A
	LD (CURRENT_DIR_USER),A
	RET
NBDOS_GET_USER:
	LD A,(ORIG_CPM_USER)
	RET

NBDOS_VERSION:
	LD HL,0022H			; CP/M 2.2
	LD A,022H
	RET

NBDOS_LOGIN_VEC:
	LD HL,0001H			; Drive A logged in
	RET

NBDOS_CON_OUT:
	LD A,E
	CALL PUTC
	XOR A
	RET

NBDOS_CON_DIRECT:
	LD A,E
	CP 0FFH
	JR NZ,NBDOS_CON_OUT
	CALL CHECK_KEY_READY
	OR A
	RET Z				; Z set, A = 0: no key
	CALL NATIVE_CONIN
	RET

NBDOS_PRINT_STR:
	PUSH HL
	PUSH DE
	EX DE,HL
NBDOS_PSTR_LOOP:
	LD A,(HL)
	CP '$'
	JR Z,NBDOS_PSTR_DONE
	OR A
	JR Z,NBDOS_PSTR_DONE
	CALL PUTC
	INC HL
	JR NBDOS_PSTR_LOOP
NBDOS_PSTR_DONE:
	POP DE
	POP HL
	XOR A
	RET

NBDOS_CON_STATUS:
	CALL CHECK_KEY_READY
	OR A
	RET Z
	LD A,0FFH
	RET

NBDOS_CON_IN:
	CALL NATIVE_CONIN
	RET

;------------------------------------------------------------------------------
; NATIVE_FIND_HANDLE: Find NextZXOS file handle for FCB at DE
;------------------------------------------------------------------------------
NATIVE_FIND_HANDLE:
	LD HL,NATIVE_FILE_TABLE
	LD B,NATIVE_FT_ENTRIES
NFH_LOOP:
	LD A,(HL)
	CP E
	JR NZ,NFH_NEXT
	INC HL
	LD A,(HL)
	CP D
	JR NZ,NFH_NEXT_DEC
	INC HL
	LD A,(HL)			; A = handle
	OR A				; Carry = 0
	RET
NFH_NEXT_DEC:
	DEC HL
NFH_NEXT:
	INC HL
	INC HL
	INC HL
	DJNZ NFH_LOOP
	SCF				; Carry = 1 (not found)
	RET

;------------------------------------------------------------------------------
; NATIVE_ALLOC_HANDLE: Register handle A for FCB at DE
;------------------------------------------------------------------------------
NATIVE_ALLOC_HANDLE:
	PUSH BC
	PUSH HL
	LD C,A				; Save handle in C
	LD HL,NATIVE_FILE_TABLE
	LD B,NATIVE_FT_ENTRIES
NAH_LOOP:
	LD A,(HL)
	INC HL
	OR (HL)
	DEC HL
	JR Z,NAH_FOUND
	LD A,(HL)
	CP E
	JR NZ,NAH_NEXT
	INC HL
	LD A,(HL)
	CP D
	JR NZ,NAH_NEXT_DEC
	DEC HL
	JR NAH_FOUND
NAH_NEXT_DEC:
	DEC HL
NAH_NEXT:
	INC HL
	INC HL
	INC HL
	DJNZ NAH_LOOP
	LD HL,NATIVE_FILE_TABLE
NAH_FOUND:
	LD (HL),E
	INC HL
	LD (HL),D
	INC HL
	LD (HL),C
	POP HL
	POP BC
	RET

;------------------------------------------------------------------------------
; NATIVE_FREE_HANDLE: Unregister handle for FCB at DE
;------------------------------------------------------------------------------
NATIVE_FREE_HANDLE:
	PUSH BC
	PUSH HL
	LD HL,NATIVE_FILE_TABLE
	LD B,NATIVE_FT_ENTRIES
NFREE_LOOP:
	LD A,(HL)
	CP E
	JR NZ,NFREE_NEXT
	INC HL
	LD A,(HL)
	CP D
	JR NZ,NFREE_NEXT_DEC
	DEC HL
	LD (HL),0
	INC HL
	LD (HL),0
	INC HL
	LD (HL),0
	POP HL
	POP BC
	RET
NFREE_NEXT_DEC:
	DEC HL
NFREE_NEXT:
	INC HL
	INC HL
	INC HL
	DJNZ NFREE_LOOP
	POP HL
	POP BC
	RET

;------------------------------------------------------------------------------
; FCB_TO_PATH: Convert CP/M FCB at DE to null-terminated 8.3 filename
;------------------------------------------------------------------------------
FCB_TO_PATH:
	PUSH HL
	INC DE				; Skip drive byte (byte 0)
	LD B,8
FTP_NLOOP:
	LD A,(DE)
	CP ' '
	JR Z,FTP_NSPACE
	LD (HL),A
	INC HL
	INC DE
	DJNZ FTP_NLOOP
	JR FTP_CHKEXT
FTP_NSPACE:
	INC DE
	DJNZ FTP_NSPACE

FTP_CHKEXT:
	LD A,(DE)
	CP ' '
	JR NZ,FTP_WRITEDOT
	INC DE
	LD A,(DE)
	CP ' '
	JR NZ,FTP_WRITEDOT_1
	INC DE
	LD A,(DE)
	CP ' '
	JR Z,FTP_END
	DEC DE
	DEC DE
	JR FTP_WRITEDOT

FTP_WRITEDOT_1:
	DEC DE
FTP_WRITEDOT:
	LD (HL),'.'
	INC HL
	LD B,3
FTP_EXLOOP:
	LD A,(DE)
	CP ' '
	JR Z,FTP_END
	LD (HL),A
	INC HL
	INC DE
	DJNZ FTP_EXLOOP

FTP_END:
	LD (HL),0
	POP HL
	RET

;------------------------------------------------------------------------------
; File I/O BDOS Operations
;------------------------------------------------------------------------------
NBDOS_OPEN_FILE:
	PUSH DE
	LD HL,NATIVE_PATH_BUF
	CALL FCB_TO_PATH
	PUSH HL
	POP IX
	LD A,ESX_DRIVE_CURRENT
	LD B,ESX_MODE_READ | ESX_MODE_WRITE | ESX_MODE_OPEN_EXIST
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_OPEN
	JR NC,NOF_OK
	LD A,ESX_DRIVE_CURRENT
	LD B,ESX_MODE_READ | ESX_MODE_OPEN_EXIST
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_OPEN
	JR NC,NOF_OK
	POP DE
	LD A,0FFH			; Not found
	RET

NOF_OK:
	POP DE
	CALL NATIVE_ALLOC_HANDLE
	XOR A
	LD HL,12
	ADD HL,DE
	LD (HL),A			; EX
	INC HL
	LD (HL),A			; S1
	INC HL
	LD (HL),A			; S2
	INC HL
	LD (HL),128			; RC
	LD HL,32
	ADD HL,DE
	LD (HL),A			; CR
	XOR A
	RET

NBDOS_CLOSE_FILE:
	CALL NATIVE_FIND_HANDLE
	JR C,NCF_CLOSED
	PUSH DE
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_CLOSE
	POP DE
	CALL NATIVE_FREE_HANDLE
NCF_CLOSED:
	XOR A
	RET

NBDOS_MAKE_FILE:
	PUSH DE
	LD HL,NATIVE_PATH_BUF
	CALL FCB_TO_PATH
	PUSH HL
	POP IX
	LD A,ESX_DRIVE_CURRENT
	LD B,ESX_MODE_WRITE | ESX_MODE_CREAT_TRUNC
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_OPEN
	JR NC,NMF_OK
	POP DE
	LD A,0FFH
	RET

NMF_OK:
	POP DE
	CALL NATIVE_ALLOC_HANDLE
	XOR A
	LD HL,12
	ADD HL,DE
	LD (HL),A			; EX
	INC HL
	LD (HL),A			; S1
	INC HL
	LD (HL),A			; S2
	INC HL
	LD (HL),A			; RC = 0
	LD HL,32
	ADD HL,DE
	LD (HL),A			; CR = 0
	XOR A
	RET

NBDOS_DELETE_FILE:
	PUSH DE
	LD HL,NATIVE_PATH_BUF
	CALL FCB_TO_PATH
	PUSH HL
	POP IX
	LD A,ESX_DRIVE_CURRENT
	RST ESX_RST_SYS
	DEFB 160			; ESX_SYS_F_UNLINK
	POP DE
	JR C,NDEL_ERR
	XOR A
	RET
NDEL_ERR:
	LD A,0FFH
	RET

NBDOS_READ_SEQ:
	CALL NATIVE_FIND_HANDLE
	JR C,NRD_ERR
	PUSH DE
	LD IX,(NATIVE_DMA_ADDR)
	LD BC,128
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_READ
	POP DE
	JR C,NRD_ERR
	LD A,B
	OR C
	JR Z,NRD_EOF
	LD A,B
	OR A
	JR NZ,NRD_PAD_DONE
	LD A,C
	CP 128
	JR NC,NRD_PAD_DONE
	PUSH HL
	PUSH DE
	PUSH BC
	LD HL,(NATIVE_DMA_ADDR)
	LD B,0
	ADD HL,BC
	LD A,128
	SUB C
	LD B,A
NRD_PAD_LOOP:
	LD (HL),01AH			; Pad with CP/M ^Z EOF
	INC HL
	DJNZ NRD_PAD_LOOP
	POP BC
	POP DE
	POP HL
NRD_PAD_DONE:
	LD HL,32
	ADD HL,DE
	INC (HL)			; Increment CR
	XOR A
	RET

NRD_EOF:
	LD A,1
	RET
NRD_ERR:
	LD A,1
	RET

NBDOS_WRITE_SEQ:
	CALL NATIVE_FIND_HANDLE
	JR C,NWR_ERR
	PUSH DE
	LD IX,(NATIVE_DMA_ADDR)
	LD BC,128
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_WRITE
	POP DE
	JR C,NWR_ERR
	LD HL,32
	ADD HL,DE
	INC (HL)
	XOR A
	RET
NWR_ERR:
	LD A,1
	RET

;------------------------------------------------------------------------------
; NATIVE_SEEK_RANDOM: Seek file handle A to 128-byte record (r0, r1, r2)
;------------------------------------------------------------------------------
NATIVE_SEEK_RANDOM:
	PUSH HL
	LD HL,33
	ADD HL,DE
	LD E,(HL)			; E = r0
	INC HL
	LD D,(HL)			; D = r1
	; Byte 0: (r0 << 7) & 0x80
	LD A,E
	RRCA
	AND 080H
	LD (NEXT_SEEK_B0),A

	; Byte 1: ((r0 >> 1) & 0x7F) | ((r1 & 1) << 7)
	LD A,E
	RLCA
	AND 07FH
	LD E,A
	LD A,D
	RRCA
	AND 080H
	OR E
	LD (NEXT_SEEK_B1),A

	; Byte 2: (r1 >> 1) & 0x7F
	LD A,D
	RLCA
	AND 07FH
	LD (NEXT_SEEK_B2),A

	LD A,(NEXT_SEEK_B0)
	LD E,A
	LD A,(NEXT_SEEK_B1)
	LD D,A
	LD A,(NEXT_SEEK_B2)
	LD C,A
	LD B,0				; BCDE = 32-bit byte offset
	POP HL

	LD L,0				; ESX_SEEK_SET
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_SEEK
	RET

NBDOS_READ_RAND:
	CALL NATIVE_FIND_HANDLE
	JR C,NRAND_ERR
	PUSH DE
	CALL NATIVE_SEEK_RANDOM
	JR C,NRAND_SEEK_ERR
	LD IX,(NATIVE_DMA_ADDR)
	LD BC,128
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_READ
	POP DE
	JR C,NRAND_ERR
	LD A,B
	OR C
	JR Z,NRAND_ERR
	XOR A
	RET
NRAND_SEEK_ERR:
	POP DE
NRAND_ERR:
	LD A,1
	RET

NBDOS_WRITE_RAND:
	CALL NATIVE_FIND_HANDLE
	JR C,NWRAND_ERR
	PUSH DE
	CALL NATIVE_SEEK_RANDOM
	JR C,NWRAND_SEEK_ERR
	LD IX,(NATIVE_DMA_ADDR)
	LD BC,128
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_WRITE
	POP DE
	JR C,NWRAND_ERR
	XOR A
	RET
NWRAND_SEEK_ERR:
	POP DE
NWRAND_ERR:
	LD A,1
	RET

NBDOS_COMPUTE_SIZE:
	CALL NATIVE_FIND_HANDLE
	JR NC,NCS_OPENED
	PUSH DE
	LD HL,NATIVE_PATH_BUF
	CALL FCB_TO_PATH
	PUSH HL
	POP IX
	LD A,ESX_DRIVE_CURRENT
	LD B,ESX_MODE_READ | ESX_MODE_OPEN_EXIST
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_OPEN
	POP DE
	JR C,NCS_ERR
	PUSH AF				; Save handle
	PUSH DE				; Save FCB
	LD BC,0
	LD DE,0
	LD L,2				; ESX_SEEK_END
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_SEEK
	POP DE
	POP AF
	PUSH DE
	PUSH BC
	PUSH DE
	PUSH AF
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_CLOSE
	POP AF
	POP DE
	POP BC
	POP HL				; HL = FCB
	JR NCS_CALC

NCS_OPENED:
	PUSH DE				; Save FCB
	PUSH AF				; Save handle
	LD BC,0
	LD DE,0
	LD L,2				; ESX_SEEK_END
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_SEEK
	POP AF
	PUSH BC
	PUSH DE
	LD BC,0
	LD DE,0
	LD L,0				; Seek to start
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_SEEK
	POP DE
	POP BC
	POP HL				; HL = FCB

NCS_CALC:
	PUSH HL
	LD HL,127
	ADD HL,DE
	EX DE,HL
	JR NC,NCS_NOC
	INC BC
NCS_NOC:
	LD A,E
	RLCA
	AND 001H
	LD L,A
	LD A,D
	ADD A,A
	OR L
	LD (NEXT_SEEK_B0),A

	LD A,D
	RLCA
	AND 001H
	LD L,A
	LD A,C
	ADD A,A
	OR L
	LD (NEXT_SEEK_B1),A

	LD A,C
	RLCA
	AND 001H
	LD L,A
	LD A,B
	ADD A,A
	OR L
	LD (NEXT_SEEK_B2),A

	POP HL
	PUSH HL
	LD DE,33
	ADD HL,DE
	LD A,(NEXT_SEEK_B0)
	LD (HL),A
	INC HL
	LD A,(NEXT_SEEK_B1)
	LD (HL),A
	INC HL
	LD A,(NEXT_SEEK_B2)
	LD (HL),A
	POP HL
	XOR A
	RET

NCS_ERR:
	LD A,0FFH
	RET

NBDOS_SEARCH_FIRST:
	LD A,(NEXT_DIR_HANDLE)
	OR A
	JR Z,NSF_OPEN
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_CLOSE
	XOR A
	LD (NEXT_DIR_HANDLE),A

NSF_OPEN:
	LD HL,NEXT_DOT_PATH
	PUSH HL
	POP IX
	LD A,ESX_DRIVE_CURRENT
	LD B,0
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_OPENDIR
	JP C,NSF_ERR
	LD (NEXT_DIR_HANDLE),A

NBDOS_SEARCH_NEXT:
	LD A,(NEXT_DIR_HANDLE)
	OR A
	JP Z,NSF_ERR

NSF_READ_ENTRY:
	LD IX,NEXT_DIR_ENTRY_BUF
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_READDIR
	JR C,NSF_CLOSE_ERR
	LD A,B
	OR C
	JR Z,NSF_CLOSE_ERR

	; Check attribute (byte 0): skip if directory (bit 4 set)
	LD A,(NEXT_DIR_ENTRY_BUF)
	AND 010H
	JR NZ,NSF_READ_ENTRY

	PUSH HL
	PUSH DE
	PUSH BC
	LD HL,(NATIVE_DMA_ADDR)
	LD A,(CURRENT_DIR_USER)
	LD (HL),A
	INC HL

	LD B,11
NSF_SP_LOOP:
	LD (HL),' '
	INC HL
	DJNZ NSF_SP_LOOP

	LD HL,(NATIVE_DMA_ADDR)
	INC HL

	LD DE,NEXT_DIR_ENTRY_BUF+9
	LD B,8
NSF_CP_NAME:
	LD A,(DE)
	OR A
	JR Z,NSF_FORMAT_DONE
	CP '.'
	JR Z,NSF_GOTO_EXT
	CP 'a'
	JR C,NSF_NOT_LOWER
	CP 'z'+1
	JR NC,NSF_NOT_LOWER
	SUB 020H
NSF_NOT_LOWER:
	LD (HL),A
	INC HL
	INC DE
	DJNZ NSF_CP_NAME

NSF_SKIP_TO_DOT:
	LD A,(DE)
	OR A
	JR Z,NSF_FORMAT_DONE
	CP '.'
	JR Z,NSF_GOTO_EXT
	INC DE
	JR NSF_SKIP_TO_DOT

NSF_GOTO_EXT:
	INC DE
	LD HL,(NATIVE_DMA_ADDR)
	LD BC,9
	ADD HL,BC
	LD B,3
NSF_CP_EXT:
	LD A,(DE)
	OR A
	JR Z,NSF_FORMAT_DONE
	CP 'a'
	JR C,NSF_EXT_NOT_LOWER
	CP 'z'+1
	JR NC,NSF_EXT_NOT_LOWER
	SUB 020H
NSF_EXT_NOT_LOWER:
	LD (HL),A
	INC HL
	INC DE
	DJNZ NSF_CP_EXT

NSF_FORMAT_DONE:
	LD HL,(NATIVE_DMA_ADDR)
	LD BC,12
	ADD HL,BC
	LD B,20
NSF_CLR_TAIL:
	LD (HL),0
	INC HL
	DJNZ NSF_CLR_TAIL

	POP BC
	POP DE
	POP HL
	XOR A
	RET

NSF_CLOSE_ERR:
	LD A,(NEXT_DIR_HANDLE)
	OR A
	JR Z,NSF_ERR
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_CLOSE
	XOR A
	LD (NEXT_DIR_HANDLE),A
NSF_ERR:
	LD A,0FFH
	RET

; End of HAL_NEXT_STORAGE.ASM
