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
; HAL Storage & File I/O API Entry Points
;------------------------------------------------------------------------------
HAL_STORAGE_OPEN	EQU	NEXT_STORAGE_OPEN
HAL_STORAGE_MAKE	EQU	NEXT_STORAGE_MAKE
HAL_STORAGE_CLOSE	EQU	NEXT_STORAGE_CLOSE
HAL_STORAGE_READ_SEC	EQU	NEXT_STORAGE_READ_SEC
HAL_STORAGE_WRITE_SEC	EQU	NEXT_STORAGE_WRITE_SEC

;------------------------------------------------------------------------------
; NEXT_STORAGE_OPEN: Open file by path string via NextZXOS RST 08h
;
; Inputs:
;   DE = Pointer to null-terminated ASCII path string.
;
; Outputs:
;   Carry = 0 on success; A = file handle (saved in NEXT_DOC_HANDLE).
;   Carry = 1 on error (file not found or access denied).
;
; Preserves / Modifies:
;   Preserves BC, DE; clobbers AF, HL, IX.
;------------------------------------------------------------------------------
NEXT_STORAGE_OPEN:
	PUSH BC
	PUSH DE
	PUSH DE
	POP IX				; IX = path string pointer
	LD A,ESX_DRIVE_CURRENT		; Default current drive '*'
	LD B,ESX_MODE_READ | ESX_MODE_OPEN_EXIST
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_OPEN
	POP DE
	POP BC
	RET C				; Carry = 1 on failure

	LD (NEXT_DOC_HANDLE),A		; Save active handle
	OR A				; Clear carry (success)
	RET

;------------------------------------------------------------------------------
; NEXT_STORAGE_MAKE: Create / replace file by path string
;
; Inputs:
;   DE = Pointer to null-terminated ASCII path string.
;
; Outputs:
;   Carry = 0 on success; A = file handle (saved in NEXT_DOC_HANDLE).
;   Carry = 1 on error.
;
; Preserves / Modifies:
;   Preserves BC, DE; clobbers AF, HL, IX.
;------------------------------------------------------------------------------
NEXT_STORAGE_MAKE:
	PUSH BC
	PUSH DE
	PUSH DE
	POP IX
	LD A,ESX_DRIVE_CURRENT
	LD B,ESX_MODE_WRITE | ESX_MODE_CREAT_TRUNC
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_OPEN
	POP DE
	POP BC
	RET C

	LD (NEXT_DOC_HANDLE),A
	OR A
	RET

;------------------------------------------------------------------------------
; NEXT_STORAGE_CLOSE: Flush and close active document file handle
;
; Inputs:
;   None (uses NEXT_DOC_HANDLE).
;
; Outputs:
;   Carry = 0 on success, 1 on error.
;
; Preserves / Modifies:
;   Preserves BC, DE, HL; modifies AF.
;------------------------------------------------------------------------------
NEXT_STORAGE_CLOSE:
	LD A,(NEXT_DOC_HANDLE)
	OR A
	RET Z				; Already closed

	PUSH BC
	PUSH DE
	PUSH HL
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_CLOSE
	POP HL
	POP DE
	POP BC
	XOR A
	LD (NEXT_DOC_HANDLE),A
	RET

;------------------------------------------------------------------------------
; NEXT_STORAGE_READ_SEC: Read 128-byte sector into active DMA buffer
;
; Outputs:
;   A = 0 on success; A = 1 on EOF / error.
;   Carry = 0 on success, 1 on error.
;
; Preserves / Modifies:
;   Preserves DE; clobbers AF, BC, HL, IX.
;------------------------------------------------------------------------------
NEXT_STORAGE_READ_SEC:
	LD A,(NEXT_DOC_HANDLE)
	OR A
	JR Z,NSR_ERROR

	PUSH DE
	LD BC,128			; Read 128-byte CP/M sector stride
	LD HL,DEFAULT_DMA
	PUSH HL
	POP IX				; IX = destination buffer
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_READ
	POP DE
	JR C,NSR_ERROR

	; Verify 128 bytes read
	LD A,B
	OR C
	JR Z,NSR_EOF			; 0 bytes read = EOF
	XOR A				; A = 0 (success)
	RET

NSR_EOF:
	LD A,1				; A = 1 (EOF)
	SCF
	RET

NSR_ERROR:
	LD A,0FFH
	SCF
	RET

;------------------------------------------------------------------------------
; NEXT_STORAGE_WRITE_SEC: Write 128-byte sector from active DMA buffer
;
; Outputs:
;   A = 0 on success; A = non-zero on error.
;   Carry = 0 on success, 1 on error.
;
; Preserves / Modifies:
;   Preserves DE; clobbers AF, BC, HL, IX.
;------------------------------------------------------------------------------
NEXT_STORAGE_WRITE_SEC:
	LD A,(NEXT_DOC_HANDLE)
	OR A
	JR Z,NSW_ERROR

	PUSH DE
	LD BC,128
	LD HL,DEFAULT_DMA
	PUSH HL
	POP IX
	RST ESX_RST_SYS
	DEFB ESX_SYS_F_WRITE
	POP DE
	JR C,NSW_ERROR
	XOR A
	RET

NSW_ERROR:
	LD A,0FFH
	SCF
	RET

;------------------------------------------------------------------------------
; Native Next Storage State Variables
;------------------------------------------------------------------------------
NEXT_DOC_HANDLE:
	DEFB 0				; Active NextZXOS document file handle
NEXT_SWAP_HANDLE:
	DEFB 0				; Active NextZXOS swap file handle

; End of HAL_NEXT_STORAGE.ASM
