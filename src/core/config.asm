;==============================================================================
; CONFIG.ASM: Core Subsystem - Editor Configuration Manager (SE.CFG)
;
; Purpose:
;   Reads, parses, searches, and saves persistent editor configuration.
;   Search order: Local default drive first, then fallback to program drive.
;   Save: Always writes to local default drive.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;==============================================================================
; Configuration File Subsystem (SE.CFG)
; Reads, parses, searches, and saves persistent editor configuration.
; Search order: Local default drive first, then fallback to program drive.
; Save: Always writes to local default drive.
;==============================================================================

;------------------------------------------------------------------------------
; LOAD_CONFIG: Load and parse configuration settings from SE.CFG
;
; Purpose:
;   Searches for SE.CFG on current drive first, then on program drive if
;   different. If found, reads up to 256 bytes and calls PARSE_CONFIG_BUFFER
;   to configure screen mode, RAM drive, tab width, line limit, and plugins.
;
; Call Usage / Protocol:
;   Called via CALL from START during initialization.
;
; Inputs:
;   None.
;
; Outputs:
;   Configuration variables populated.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
LOAD_CONFIG:
	; 1. Query current default drive via BDOS 25
	LD C,25				; BDOS Get Current Drive
	CALL BDOS_ENTRY
	LD (CURRENT_DEFAULT_DRIVE),A
	XOR A
	LD (CONFIG_STATUS_FLAG),A
	LD A,0FFH
	LD (CONFIG_SOURCE_DRIVE),A

	; 2. Try to open SE.CFG on current default drive (drive byte = 0)
	CALL INIT_CFG_FCB_LOCAL
	LD DE,CFG_FCB
	LD C,15				; BDOS Open File
	CALL BDOS_ENTRY
	CP 0FFH
	JR Z,LOAD_CFG_NOT_LOCAL

	; Local SE.CFG found! Read 128 bytes
	CALL READ_CFG_RECORD
	JR C,LOAD_CFG_NOT_LOCAL
	LD A,1
	LD (CONFIG_STATUS_FLAG),A
	LD A,(CURRENT_DEFAULT_DRIVE)
	LD (CONFIG_SOURCE_DRIVE),A
	CALL PARSE_CONFIG_BUFFER
	RET

LOAD_CFG_NOT_LOCAL:
	; 3. Probe other logged-in drives for SE.COM
	; Returns A = drive index (0..15) if found, Carry = 0
	CALL PROBE_PROGRAM_DRIVE
	RET C				; Not found on any other drive

	; SE.COM found on drive A! Try opening SE.CFG on that drive
	LD (CONFIG_SOURCE_DRIVE),A	; Save program drive index (0..15)
	INC A				; A = FCB drive code (1=A..16=P)
	CALL INIT_CFG_FCB_DRIVE
	LD DE,CFG_FCB
	LD C,15				; BDOS Open File
	CALL BDOS_ENTRY
	CP 0FFH
	JR Z,LOAD_CFG_NOT_PROG		; No SE.CFG on program drive

	; SE.CFG found on program drive! Read 128 bytes
	CALL READ_CFG_RECORD
	JR C,LOAD_CFG_NOT_PROG
	LD A,2
	LD (CONFIG_STATUS_FLAG),A
	CALL PARSE_CONFIG_BUFFER
	RET

LOAD_CFG_NOT_PROG:
	LD A,0FFH
	LD (CONFIG_SOURCE_DRIVE),A
	RET

;------------------------------------------------------------------------------
; PROBE_PROGRAM_DRIVE: Search logged-in drives for SE.COM executable
;
; Purpose:
;   Queries logged-in drive vector via BDOS function 24, iterating through
;   all online drives other than current drive, looking for SE.COM via BDOS
;   Search First (function 17) to determine program home drive.
;
; Call Usage / Protocol:
;   Called via CALL from LOAD_CONFIG when SE.CFG is not in current drive.
;
; Inputs:
;   CURRENT_DEFAULT_DRIVE.
;
; Outputs:
;   A = Drive index (0..15), Carry = 0 if found; Carry = 1 if not found.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
PROBE_PROGRAM_DRIVE:
	LD C,24				; BDOS Return Login Vector
	CALL BDOS_ENTRY		; HL = 16-bit vector (bit 0=A, bit 1=B...)
	LD D,0				; D = drive index (0..15)
PPD_LOOP:
	LD A,D
	CP 16
	JR NC,PPD_NOT_FOUND

	SRL H
	RR L				; Carry = bit D of login vector
	JR NC,PPD_NEXT			; Drive not logged in!

	; Skip if D == CURRENT_DEFAULT_DRIVE
	LD A,(CURRENT_DEFAULT_DRIVE)
	CP D
	JR Z,PPD_NEXT

	; Drive D is valid and distinct! Probe for SE.COM on drive D+1
	PUSH HL
	PUSH DE
	LD A,D
	INC A				; 1=A, 2=B...
	CALL INIT_COM_PROBE_FCB
	LD DE,COM_PROBE_FCB
	LD C,15				; BDOS Open File
	CALL BDOS_ENTRY
	POP DE
	POP HL
	CP 0FFH
	JR Z,PPD_NEXT			; SE.COM not on drive D

	; Found SE.COM on drive D! Close it
	PUSH DE
	LD DE,COM_PROBE_FCB
	LD C,16				; BDOS Close File
	CALL BDOS_ENTRY
	POP DE
	LD A,D				; A = drive index (0..15)
	OR A				; Carry = 0
	RET

PPD_NEXT:
	INC D
	JR PPD_LOOP

PPD_NOT_FOUND:
	SCF				; Carry = 1
	RET

;------------------------------------------------------------------------------
; READ_CFG_RECORD: Read up to 256 bytes from open CFG_FCB into CFG_IO_BUF
;
; Purpose:
;   Reads up to 2 sequential 128-byte records from open CFG_FCB using BDOS
;   Read Sequential (function 20), null-terminating the resulting buffer.
;
; Call Usage / Protocol:
;   Called via CALL from LOAD_CONFIG after opening configuration file.
;
; Inputs:
;   CFG_FCB (opened file control block).
;
; Outputs:
;   CFG_IO_BUF populated; Carry = 0 on success, Carry = 1 on read error.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
READ_CFG_RECORD:
	XOR A
	LD (CFG_FCB+32),A		; Clear record byte (cr)

	; Clear CFG_IO_BUF with 1AH EOF markers first
	LD HL,CFG_IO_BUF
	LD (HL),1AH
	LD DE,CFG_IO_BUF+1
	LD BC,255
	LDIR

	; Read record 0
	LD DE,CFG_IO_BUF
	LD C,26				; BDOS Set DMA
	CALL BDOS_ENTRY

	LD DE,CFG_FCB
	LD C,20				; BDOS Read Next Record
	CALL BDOS_ENTRY
	OR A
	JR NZ,RCR_ERR

	; Try reading record 1 (if available)
	LD DE,CFG_IO_BUF+128
	LD C,26				; BDOS Set DMA
	CALL BDOS_ENTRY

	LD DE,CFG_FCB
	LD C,20				; BDOS Read Next Record
	CALL BDOS_ENTRY
	; Ignore EOF on record 1 (fine if file has only 1 record)

	LD DE,CFG_FCB
	LD C,16				; BDOS Close File
	CALL BDOS_ENTRY

	LD DE,DEFAULT_DMA
	LD C,26				; Restore BDOS DMA
	CALL BDOS_ENTRY

	OR A				; Carry = 0
	RET
RCR_ERR:
	LD DE,CFG_FCB
	LD C,16				; BDOS Close File
	CALL BDOS_ENTRY

	LD DE,DEFAULT_DMA
	LD C,26				; Restore BDOS DMA
	CALL BDOS_ENTRY

	SCF				; Carry = 1
	RET

;------------------------------------------------------------------------------
; PARSE_CONFIG_BUFFER: Scan CFG_IO_BUF for configuration key-value parameters
;
; Purpose:
;   Parses line-by-line configuration text in CFG_IO_BUF matching supported
;   keys (screen, ramdrive, tab, lines, maxlines, plugin) and updating
;   corresponding runtime settings.
;
; Call Usage / Protocol:
;   Called via CALL from LOAD_CONFIG after reading file.
;
; Inputs:
;   CFG_IO_BUF (null-terminated configuration text).
;
; Outputs:
;   CFG_SCREEN_MODE, CFG_RAMDRIVE_FLAG, CFG_TAB_WIDTH, CFG_LINES_MODE,
;   CFG_AUTOLOAD_PLUGIN_MGR updated.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
PARSE_CONFIG_BUFFER:
	LD HL,CFG_IO_BUF
PCB_LINE_START:
	; Check if HL >= CFG_IO_BUF + 256
	LD DE,CFG_IO_BUF + 256
	LD A,L
	CP E
	JR NZ,PCB_NOT_END
	LD A,H
	CP D
	RET Z				; End of buffer!
PCB_NOT_END:
	LD A,(HL)
	CP 1AH				; EOF (^Z)
	RET Z
	OR A				; Null
	RET Z

	; Skip leading whitespace (spaces / tabs / CR / LF)
	CP ' '
	JR Z,PCB_SKIP_CHAR
	CP 9				; Tab
	JR Z,PCB_SKIP_CHAR
	CP 13				; CR
	JR Z,PCB_SKIP_CHAR
	CP 10				; LF
	JR Z,PCB_SKIP_CHAR

	; Check if comment (# or ;)
	CP '#'
	JR Z,PCB_SKIP_LINE
	CP ';'
	JR Z,PCB_SKIP_LINE
	JR PCB_CHECK_KEYS

PCB_SKIP_CHAR:
	INC HL
	JP PCB_LINE_START

PCB_SKIP_LINE:
	; Advance HL until LF, CR, EOF, or HL >= CFG_IO_BUF + 256
	LD DE,CFG_IO_BUF + 256
	LD A,L
	CP E
	JR NZ,PSL_CHECK_CHR
	LD A,H
	CP D
	RET Z
PSL_CHECK_CHR:
	LD A,(HL)
	INC HL
	CP 1AH
	RET Z
	CP 10				; LF
	JP Z,PCB_LINE_START
	JR PCB_SKIP_LINE

PCB_CHECK_KEYS:
	; Check for "SCREEN"
	CALL MATCH_KEY_SCREEN	; Carry = 0 if matched, HL past '=' and spaces
	JR NC,PCB_SCREEN_VAL

	; Check for "RAMDRIVE" or "RAMDISK"
	CALL MATCH_KEY_RAMDRIVE
	JR NC,PCB_RAMDRIVE_VAL

	; Check for "TAB" or "TABS"
	CALL MATCH_KEY_TAB
	JP NC,PCB_TAB_VAL

	; Check for "LINES" or "LINE"
	CALL MATCH_KEY_LINES
	JP NC,PCB_LINES_VAL

	; Check for "MAXLINES" or "MAXLINE"
	CALL MATCH_KEY_MAXLINES
	JP NC,PCB_LINES_VAL

	; Check for "PLUGIN" or "PLUGINS"
	CALL MATCH_KEY_PLUGIN
	JP NC,PCB_PLUGIN_VAL

	JP PCB_SKIP_LINE

PCB_SCREEN_VAL:
	; HL now points to value after '='
	; Check if starts with "80"
	LD A,(HL)
	CP '8'
	JR NZ,PCB_CHECK_120
	INC HL
	LD A,(HL)
	CP '0'
	JP NZ,PCB_SKIP_LINE
	PUSH HL
	CALL SET_MODE_80X24
	POP HL
	JP PCB_SKIP_LINE

PCB_CHECK_120:
	CP '1'
	JP NZ,PCB_SKIP_LINE
	INC HL
	LD A,(HL)
	CP '2'
	JP NZ,PCB_SKIP_LINE
	INC HL
	LD A,(HL)
	CP '0'
	JP NZ,PCB_SKIP_LINE
	PUSH HL
	CALL SET_MODE_120X40
	POP HL
	JP PCB_SKIP_LINE

PCB_RAMDRIVE_VAL:
	; HL now points to value after '='
	LD A,(HL)
	CALL TO_UPPER
	CP 'H'				; HIBERNATE
	JR Z,PCB_RAM_SET_HIB
	CP 'A'				; AUTO
	JR Z,PCB_RAM_SET_HIB
	CP '2'
	JR Z,PCB_RAM_SET_HIB
	CP 'O'				; ON, OFF, or OVERWRITE?
	JR NZ,PCB_RAM_CHECK_YES
	INC HL
	LD A,(HL)
	CALL TO_UPPER
	CP 'N'				; ON
	JR Z,PCB_RAM_SET_ON
	CP 'V'				; OVERWRITE
	JR Z,PCB_RAM_SET_ON
	CP 'F'				; OFF
	JR Z,PCB_RAM_SET_OFF
	JP PCB_SKIP_LINE

PCB_RAM_CHECK_YES:
	CP 'Y'				; YES
	JR Z,PCB_RAM_SET_ON
	CP '1'
	JR Z,PCB_RAM_SET_ON
	CP 'E'				; ENABLED
	JR Z,PCB_RAM_SET_ON
	CP 'T'				; TRUE
	JR Z,PCB_RAM_SET_ON
	CP 'M'				; MAXRAM
	JR Z,PCB_RAM_SET_ON

	CP 'N'				; NO
	JR Z,PCB_RAM_SET_OFF
	CP '0'
	JR Z,PCB_RAM_SET_OFF
	CP 'P'				; PRESERVE / PROTECTED
	JR Z,PCB_RAM_SET_OFF
	CP 'F'				; FALSE
	JR Z,PCB_RAM_SET_OFF
	JP PCB_SKIP_LINE

PCB_RAM_SET_HIB:
	LD A,RAMDRV_MODE_HIBERNATE
	LD (CFG_RAMDRIVE_FLAG),A
	JP PCB_SKIP_LINE

PCB_RAM_SET_ON:
	LD A,RAMDRV_MODE_ENABLED
	LD (CFG_RAMDRIVE_FLAG),A
	JP PCB_SKIP_LINE

PCB_RAM_SET_OFF:
	XOR A
	LD (CFG_RAMDRIVE_FLAG),A
	JP PCB_SKIP_LINE

PCB_TAB_VAL:
	; HL now points to value after '='
	LD A,(HL)
	CP '4'
	JR NZ,PCB_TAB_CHK_8
	LD A,4
	LD (CFG_TAB_WIDTH),A
	LD A,3
	LD (CFG_TAB_MASK),A
	JP PCB_SKIP_LINE

PCB_TAB_CHK_8:
	CP '8'
	JP NZ,PCB_SKIP_LINE
	LD A,8
	LD (CFG_TAB_WIDTH),A
	LD A,7
	LD (CFG_TAB_MASK),A
	JP PCB_SKIP_LINE

PCB_LINES_VAL:
	; HL now points to value after '='
PCB_LV_WS:
	LD A,(HL)
	CP ' '
	JR Z,PCB_LV_WS_INC
	CP 9
	JR NZ,PCB_LV_CHECK
PCB_LV_WS_INC:
	INC HL
	JR PCB_LV_WS
PCB_LV_CHECK:
	LD A,(HL)
	CP '3'				; 32K or 32768 or 32
	JR Z,PCB_LV_SET_32K
	CP '1'				; 16K or 16384 or 16
	JR Z,PCB_LV_SET_16K
	JP PCB_SKIP_LINE

PCB_LV_SET_32K:
	LD A,1
	LD (CFG_LINES_MODE),A
	JP PCB_SKIP_LINE

PCB_LV_SET_16K:
	XOR A
	LD (CFG_LINES_MODE),A
	JP PCB_SKIP_LINE

PCB_PLUGIN_VAL:
	; HL now points to value after '='
PCB_PV_WS:
	LD A,(HL)
	CP ' '
	JR Z,PCB_PV_WS_INC
	CP 9
	JR NZ,PCB_PV_CHECK
PCB_PV_WS_INC:
	INC HL
	JR PCB_PV_WS
PCB_PV_CHECK:
	LD A,(HL)
	CALL TO_UPPER
	CP 'A'				; AUTOLOAD / AUTO
	JR Z,PCB_PLUG_SET_AUTO
	CP 'Y'				; YES
	JR Z,PCB_PLUG_SET_AUTO
	CP '1'				; 1
	JR Z,PCB_PLUG_SET_AUTO
	CP 'E'				; ENABLE / ENABLED
	JR Z,PCB_PLUG_SET_AUTO
	CP 'T'				; TRUE
	JR Z,PCB_PLUG_SET_AUTO

	CP '2'				; 2
	JR Z,PCB_PLUG_SET_ONDEMAND
	CP 'M'				; MANUAL
	JR Z,PCB_PLUG_SET_ONDEMAND

	CP 'N'				; NO / NONE
	JR Z,PCB_PLUG_SET_OFF
	CP '0'				; 0
	JR Z,PCB_PLUG_SET_OFF
	CP 'F'				; FALSE
	JR Z,PCB_PLUG_SET_OFF

	CP 'D'				; DEMAND vs DISABLED
	JR Z,PCB_PV_CHK_D
	CP 'O'				; ONDEMAND vs ON vs OFF
	JR Z,PCB_PV_CHK_O
	JP PCB_SKIP_LINE

PCB_PV_CHK_D:
	INC HL
	LD A,(HL)
	CALL TO_UPPER
	CP 'E'				; DEMAND
	JR Z,PCB_PLUG_SET_ONDEMAND
	JR PCB_PLUG_SET_OFF		; DISABLED / DISABLE / other

PCB_PV_CHK_O:
	INC HL
	LD A,(HL)
	CALL TO_UPPER
	CP 'F'				; OFF
	JR Z,PCB_PLUG_SET_OFF
	CP 'N'				; ON or ONDEMAND?
	JP NZ,PCB_SKIP_LINE
	INC HL
	LD A,(HL)
	CALL TO_UPPER
	CP 'D'				; ONDEMAND
	JR Z,PCB_PLUG_SET_ONDEMAND
	JR PCB_PLUG_SET_AUTO		; ON

PCB_PLUG_SET_AUTO:
	LD A,PLUGIN_MODE_AUTOLOAD
	LD (CFG_AUTOLOAD_PLUGIN_MGR),A
	JP PCB_SKIP_LINE

PCB_PLUG_SET_ONDEMAND:
	LD A,PLUGIN_MODE_ONDEMAND
	LD (CFG_AUTOLOAD_PLUGIN_MGR),A
	JP PCB_SKIP_LINE

PCB_PLUG_SET_OFF:
	XOR A
	LD (CFG_AUTOLOAD_PLUGIN_MGR),A
	JP PCB_SKIP_LINE


;------------------------------------------------------------------------------
; MATCH_KEY_SCREEN: Match 'screen' or 'geometry' key name at buffer pointer HL
;
; Purpose:
;   Performs case-insensitive prefix comparison against "screen" and
;   "geometry" followed by '=' and optional spaces.
;
; Call Usage / Protocol:
;   Called via CALL from PARSE_CONFIG_BUFFER.
;
; Inputs:
;   HL = Pointer to position in line buffer.
;
; Outputs:
;   Carry = 0 if matched (HL advanced past '=' and spaces);
;   Carry = 1 if no match (HL restored to starting position).
;
; Preserves / Modifies:
;   Preserves BC, DE; clobbers AF.
;------------------------------------------------------------------------------
MATCH_KEY_SCREEN:
	PUSH HL
	LD DE,STR_KEY_SCREEN_NAME
	LD B,6
MKS_LOOP:
	LD A,(HL)
	CALL TO_UPPER
	LD C,A
	LD A,(DE)
	CP C
	JR NZ,MKS_FAIL
	INC HL
	INC DE
	DJNZ MKS_LOOP

	; Skip optional spaces before '='
MKS_WS1:
	LD A,(HL)
	CP ' '
	JR Z,MKS_WS1_INC
	CP 9
	JR NZ,MKS_CHECK_EQ
MKS_WS1_INC:
	INC HL
	JR MKS_WS1

MKS_CHECK_EQ:
	CP '='
	JR NZ,MKS_FAIL
	INC HL				; Skip '='

	; Skip optional spaces after '='
MKS_WS2:
	LD A,(HL)
	CP ' '
	JR Z,MKS_WS2_INC
	CP 9
	JR NZ,MKS_OK
MKS_WS2_INC:
	INC HL
	JR MKS_WS2

MKS_OK:
	POP AF				; Discard saved HL
	OR A				; Carry = 0
	RET

MKS_FAIL:
	POP HL				; Restore HL
	SCF				; Carry = 1
	RET

;------------------------------------------------------------------------------
; MATCH_KEY_RAMDRIVE: Match 'ramdrive' or 'ramdisk' key at buffer pointer HL
;
; Purpose:
;   Performs case-insensitive prefix comparison against "ramdrive" and
;   "ramdisk" followed by '=' and optional spaces.
;
; Call Usage / Protocol:
;   Called via CALL from PARSE_CONFIG_BUFFER.
;
; Inputs:
;   HL = Pointer to position in line buffer.
;
; Outputs:
;   Carry = 0 if matched (HL advanced past '=' and spaces);
;   Carry = 1 if no match (HL restored to starting position).
;
; Preserves / Modifies:
;   Preserves BC, DE; clobbers AF.
;------------------------------------------------------------------------------
MATCH_KEY_RAMDRIVE:
	PUSH HL
	LD DE,STR_KEY_RAMD_NAME
	LD B,4
MKR_LOOP:
	LD A,(HL)
	CALL TO_UPPER
	LD C,A
	LD A,(DE)
	CP C
	JR NZ,MKR_FAIL
	INC HL
	INC DE
	DJNZ MKR_LOOP

	; Skip remaining key characters until '=' or whitespace
MKR_SKIP_KEY:
	LD A,(HL)
	CP ' '
	JR Z,MKR_WS1
	CP 9
	JR Z,MKR_WS1
	CP '='
	JR Z,MKR_GOT_EQ
	CP 13
	JR Z,MKR_FAIL
	CP 10
	JR Z,MKR_FAIL
	CP 1AH
	JR Z,MKR_FAIL
	INC HL
	JR MKR_SKIP_KEY

MKR_WS1:
	LD A,(HL)
	CP ' '
	JR Z,MKR_WS1_INC
	CP 9
	JR NZ,MKR_CHECK_EQ
MKR_WS1_INC:
	INC HL
	JR MKR_WS1

MKR_CHECK_EQ:
	CP '='
	JR NZ,MKR_FAIL
MKR_GOT_EQ:
	INC HL				; Skip '='

	; Skip optional spaces after '='
MKR_WS2:
	LD A,(HL)
	CP ' '
	JR Z,MKR_WS2_INC
	CP 9
	JR NZ,MKR_OK
MKR_WS2_INC:
	INC HL
	JR MKR_WS2

MKR_OK:
	POP AF				; Discard saved HL
	OR A				; Carry = 0
	RET

MKR_FAIL:
	POP HL
	SCF				; Carry = 1
	RET

;------------------------------------------------------------------------------
; MATCH_KEY_TAB: Match 'tab' or 'tabwidth' key name at buffer pointer HL
;
; Purpose:
;   Performs case-insensitive prefix comparison against "tab" and "tabwidth"
;   followed by '=' and optional spaces.
;
; Call Usage / Protocol:
;   Called via CALL from PARSE_CONFIG_BUFFER.
;
; Inputs:
;   HL = Pointer to position in line buffer.
;
; Outputs:
;   Carry = 0 if matched (HL advanced past '=' and spaces);
;   Carry = 1 if no match (HL restored to starting position).
;
; Preserves / Modifies:
;   Preserves BC, DE; clobbers AF.
;------------------------------------------------------------------------------
MATCH_KEY_TAB:
	PUSH HL
	LD DE,STR_KEY_TAB_NAME
	LD B,3
MKT_LOOP:
	LD A,(HL)
	CALL TO_UPPER
	LD C,A
	LD A,(DE)
	CP C
	JR NZ,MKT_FAIL
	INC HL
	INC DE
	DJNZ MKT_LOOP

	; Skip remaining key characters until '=' or whitespace
MKT_SKIP_KEY:
	LD A,(HL)
	CP ' '
	JR Z,MKT_WS1
	CP 9
	JR Z,MKT_WS1
	CP '='
	JR Z,MKT_GOT_EQ
	CP 13
	JR Z,MKT_FAIL
	CP 10
	JR Z,MKT_FAIL
	CP 1AH
	JR Z,MKT_FAIL
	INC HL
	JR MKT_SKIP_KEY

MKT_WS1:
	LD A,(HL)
	CP ' '
	JR Z,MKT_WS1_INC
	CP 9
	JR NZ,MKT_CHECK_EQ
MKT_WS1_INC:
	INC HL
	JR MKT_WS1

MKT_CHECK_EQ:
	CP '='
	JR NZ,MKT_FAIL
MKT_GOT_EQ:
	INC HL				; Skip '='

	; Skip optional spaces after '='
MKT_WS2:
	LD A,(HL)
	CP ' '
	JR Z,MKT_WS2_INC
	CP 9
	JR NZ,MKT_OK
MKT_WS2_INC:
	INC HL
	JR MKT_WS2

MKT_OK:
	POP AF				; Discard saved HL
	OR A				; Carry = 0
	RET

MKT_FAIL:
	POP HL
	SCF				; Carry = 1
	RET

;------------------------------------------------------------------------------
; MATCH_KEY_LINES: Match 'line' prefix key name at buffer pointer HL
;
; Purpose:
;   Performs case-insensitive comparison against "line" followed by '=' and
;   optional spaces.
;
; Call Usage / Protocol:
;   Called via CALL from PARSE_CONFIG_BUFFER.
;
; Inputs:
;   HL = Pointer to position in line buffer.
;
; Outputs:
;   Carry = 0 if matched (HL advanced past '=' and spaces);
;   Carry = 1 if no match (HL restored to starting position).
;
; Preserves / Modifies:
;   Preserves BC, DE; clobbers AF.
;------------------------------------------------------------------------------
MATCH_KEY_LINES:
	PUSH HL
	LD DE,STR_KEY_LINES_NAME
	LD B,4
	JR MKL_SHARED_LOOP

;------------------------------------------------------------------------------
; MATCH_KEY_MAXLINES: Match 'maxline' prefix key name at buffer pointer HL
;
; Purpose:
;   Performs case-insensitive comparison against "maxline" followed by '=' and
;   optional spaces.
;
; Call Usage / Protocol:
;   Called via CALL from PARSE_CONFIG_BUFFER.
;
; Inputs:
;   HL = Pointer to position in line buffer.
;
; Outputs:
;   Carry = 0 if matched (HL advanced past '=' and spaces);
;   Carry = 1 if no match (HL restored to starting position).
;
; Preserves / Modifies:
;   Preserves BC, DE; clobbers AF.
;------------------------------------------------------------------------------
MATCH_KEY_MAXLINES:
	PUSH HL
	LD DE,STR_KEY_MAXLINES_NAME
	LD B,7
	JR MKL_SHARED_LOOP

;------------------------------------------------------------------------------
; MATCH_KEY_PLUGIN: Match 'plugin' key name at buffer pointer HL
;
; Purpose:
;   Performs case-insensitive comparison against "plugin" followed by '=' and
;   optional spaces.
;
; Call Usage / Protocol:
;   Called via CALL from PARSE_CONFIG_BUFFER.
;
; Inputs:
;   HL = Pointer to position in line buffer.
;
; Outputs:
;   Carry = 0 if matched (HL advanced past '=' and spaces);
;   Carry = 1 if no match (HL restored to starting position).
;
; Preserves / Modifies:
;   Preserves BC, DE; clobbers AF.
;------------------------------------------------------------------------------
MATCH_KEY_PLUGIN:
	PUSH HL
	LD DE,STR_KEY_PLUGIN_NAME
	LD B,6
	JR MKL_SHARED_LOOP
MKL_SHARED_LOOP:
MKL_LOOP:
	LD A,(HL)
	CALL TO_UPPER
	LD C,A
	LD A,(DE)
	CP C
	JR NZ,MKL_FAIL
	INC HL
	INC DE
	DJNZ MKL_LOOP

	; Skip remaining key characters until '=' or whitespace
MKL_SKIP_KEY:
	LD A,(HL)
	CP ' '
	JR Z,MKL_WS1
	CP 9
	JR Z,MKL_WS1
	CP '='
	JR Z,MKL_GOT_EQ
	CP 13
	JR Z,MKL_FAIL
	CP 10
	JR Z,MKL_FAIL
	CP 1AH
	JR Z,MKL_FAIL
	INC HL
	JR MKL_SKIP_KEY

MKL_WS1:
	LD A,(HL)
	CP ' '
	JR Z,MKL_WS1_INC
	CP 9
	JR NZ,MKL_CHECK_EQ
MKL_WS1_INC:
	INC HL
	JR MKL_WS1

MKL_CHECK_EQ:
	CP '='
	JR NZ,MKL_FAIL
MKL_GOT_EQ:
	INC HL				; Skip '='

	; Skip optional spaces after '='
MKL_WS2:
	LD A,(HL)
	CP ' '
	JR Z,MKL_WS2_INC
	CP 9
	JR NZ,MKL_OK
MKL_WS2_INC:
	INC HL
	JR MKL_WS2

MKL_OK:
	POP AF				; Discard saved HL
	OR A				; Carry = 0
	RET

MKL_FAIL:
	POP HL
	SCF				; Carry = 1
	RET

;------------------------------------------------------------------------------
; SAVE_CONFIG: Save current editor configuration settings to local SE.CFG
;
; Purpose:
;   Formats active editor parameters (screen mode, RAM drive mode, tab width,
;   max lines, plugin manager mode) into an ASCII text buffer and writes to
;   SE.CFG on current drive using BDOS file operations (19 delete, 22 make,
;   21 write, 16 close).
;
; Call Usage / Protocol:
;   Called via CALL from CONFIG_LOOP on 'S' key.
;
; Inputs:
;   Runtime configuration variables.
;
; Outputs:
;   SE.CFG file written to disk; status message updated.
;
; Preserves / Modifies:
;   Clobbers all working registers.
;------------------------------------------------------------------------------
SAVE_CONFIG:
	; Fill CFG_IO_BUF with 256 bytes of 0x1A (EOF)
	LD HL,CFG_IO_BUF
	LD (HL),1AH
	LD DE,CFG_IO_BUF+1
	LD BC,255
	LDIR

	; Write header to CFG_IO_BUF
	LD HL,STR_CFG_HDR
	LD DE,CFG_IO_BUF
	CALL SC_APPEND_STRING

	; Write "SCREEN="
	LD HL,STR_KEY_SCREEN_FULL
	CALL SC_APPEND_STRING

	; Write value: "120x40" or "80x24" + CRLF
	LD A,(SCREEN_MODE)
	CP MODE_120X40
	JR NZ,SC_VAL_80
	LD HL,STR_VAL_120X40
	JR SC_PUT_SCREEN
SC_VAL_80:
	LD HL,STR_VAL_80X24
SC_PUT_SCREEN:
	CALL SC_APPEND_STRING

	; Write "RAMDRIVE="
	LD HL,STR_KEY_RAMDRIVE_FULL
	CALL SC_APPEND_STRING

	; Write value: "PRESERVE\r\n", "HIBERNATE\r\n", or "OVERWRITE\r\n"
	LD A,(CFG_RAMDRIVE_FLAG)
	CP RAMDRV_MODE_HIBERNATE
	JR Z,SC_RAM_VAL_HIB
	CP RAMDRV_MODE_ENABLED
	JR Z,SC_RAM_VAL_ON
	LD HL,STR_VAL_RAMDRIVE_OFF
	JR SC_PUT_RAM
SC_RAM_VAL_HIB:
	LD HL,STR_VAL_RAMDRIVE_HIB
	JR SC_PUT_RAM
SC_RAM_VAL_ON:
	LD HL,STR_VAL_RAMDRIVE_ON
SC_PUT_RAM:
	CALL SC_APPEND_STRING

	; Write "TAB="
	LD HL,STR_KEY_TAB_FULL
	CALL SC_APPEND_STRING

	; Write value: "8" or "4" + CRLF
	LD A,(CFG_TAB_WIDTH)
	CP 4
	JR Z,SC_TAB_VAL_4
	LD HL,STR_VAL_TAB_8
	JR SC_PUT_TAB
SC_TAB_VAL_4:
	LD HL,STR_VAL_TAB_4
SC_PUT_TAB:
	CALL SC_APPEND_STRING

	; Write "LINES="
	LD HL,STR_KEY_LINES_FULL
	CALL SC_APPEND_STRING

	; Write value: "32K\r\n" or "16K\r\n"
	LD A,(CFG_LINES_MODE)
	CP 1
	JR Z,SC_LINES_VAL_32K
	LD HL,STR_VAL_LINES_16K
	JR SC_PUT_LINES
SC_LINES_VAL_32K:
	LD HL,STR_VAL_LINES_32K
SC_PUT_LINES:
	CALL SC_APPEND_STRING

	; Write "PLUGIN="
	LD HL,STR_KEY_PLUGIN_FULL
	CALL SC_APPEND_STRING

	; Write value: "AUTOLOAD\r\n", "ONDEMAND\r\n", or "DISABLED\r\n"
	LD A,(CFG_AUTOLOAD_PLUGIN_MGR)
	CP PLUGIN_MODE_AUTOLOAD
	JR Z,SC_PLUG_VAL_AUTO
	CP PLUGIN_MODE_ONDEMAND
	JR Z,SC_PLUG_VAL_ONDEMAND
	LD HL,STR_VAL_PLUG_DIS
	JR SC_PUT_PLUG
SC_PLUG_VAL_ONDEMAND:
	LD HL,STR_VAL_PLUG_ONDEMAND
	JR SC_PUT_PLUG
SC_PLUG_VAL_AUTO:
	LD HL,STR_VAL_PLUG_AUTO
SC_PUT_PLUG:
	CALL SC_APPEND_STRING

	; Set BDOS DMA to CFG_IO_BUF (record 0)
	LD DE,CFG_IO_BUF
	LD C,26
	CALL BDOS_ENTRY

	; Prepare local CFG_FCB
	CALL INIT_CFG_FCB_LOCAL

	; Delete existing SE.CFG on current drive (BDOS 19)
	LD DE,CFG_FCB
	LD C,19
	CALL BDOS_ENTRY

	; Prepare local CFG_FCB again
	CALL INIT_CFG_FCB_LOCAL

	; Make file on current drive (BDOS 22)
	LD DE,CFG_FCB
	LD C,22
	CALL BDOS_ENTRY
	CP 0FFH
	JR Z,SC_ERR

	; Write first 128-byte record (BDOS 21)
	LD DE,CFG_FCB
	LD C,21
	CALL BDOS_ENTRY
	OR A
	JR NZ,SC_ERR_CLOSE

	; Set BDOS DMA to CFG_IO_BUF + 128 (record 1)
	LD DE,CFG_IO_BUF + 128
	LD C,26
	CALL BDOS_ENTRY

	; Write second 128-byte record (BDOS 21)
	LD DE,CFG_FCB
	LD C,21
	CALL BDOS_ENTRY
	OR A
	JR NZ,SC_ERR_CLOSE

	; Close file (BDOS 16)
	LD DE,CFG_FCB
	LD C,16
	CALL BDOS_ENTRY
	CP 0FFH
	JR Z,SC_ERR

	; Restore DMA
	LD DE,DEFAULT_DMA
	LD C,26
	CALL BDOS_ENTRY

	; Success!
	LD A,3
	LD (CONFIG_STATUS_FLAG),A
	LD A,(CURRENT_DEFAULT_DRIVE)
	LD (CONFIG_SOURCE_DRIVE),A
	RET

SC_ERR_CLOSE:
	LD DE,CFG_FCB
	LD C,16
	CALL BDOS_ENTRY
SC_ERR:
	LD DE,DEFAULT_DMA
	LD C,26
	CALL BDOS_ENTRY
	LD A,4
	LD (CONFIG_STATUS_FLAG),A
	RET

;------------------------------------------------------------------------------
; SC_APPEND_STRING: Append null-terminated string from DE to buffer at HL
;
; Purpose:
;   Copies bytes from DE to HL until encountering null terminator, leaving
;   HL pointing to terminating null.
;
; Call Usage / Protocol:
;   Called via CALL by SAVE_CONFIG formatting sequence.
;
; Inputs:
;   DE = Pointer to source ASCII string, HL = Pointer to destination buffer.
;
; Outputs:
;   HL points to terminating null of copied string.
;
; Preserves / Modifies:
;   Preserves BC; clobbers AF, DE.
;------------------------------------------------------------------------------
SC_APPEND_STRING:
	LD A,(HL)
	OR A
	RET Z
	LD (DE),A
	INC HL
	INC DE
	JR SC_APPEND_STRING

;------------------------------------------------------------------------------
; INIT_CFG_FCB_LOCAL: Initialize CFG_FCB for default drive
;
; Purpose:
;   Initializes CFG_FCB with drive 0 (current default drive) and filename
;   "SE.CFG".
;
; Call Usage / Protocol:
;   Called via CALL from LOAD_CONFIG and SAVE_CONFIG.
;
; Inputs:
;   None.
;
; Outputs:
;   CFG_FCB formatted for default drive.
;
; Preserves / Modifies:
;   Clobbers AF, B, HL.
;------------------------------------------------------------------------------
INIT_CFG_FCB_LOCAL:
	XOR A
	JR INIT_CFG_FCB_COMMON

;------------------------------------------------------------------------------
; INIT_CFG_FCB_DRIVE: Initialize CFG_FCB for specified drive code in register A
;
; Purpose:
;   Initializes CFG_FCB with drive code in register A (1=A, 2=B...) and
;   filename "SE.CFG".
;
; Call Usage / Protocol:
;   Called via CALL from LOAD_CONFIG when probing program drive.
;
; Inputs:
;   A = 1-indexed drive code (1..16).
;
; Outputs:
;   CFG_FCB formatted for drive A.
;
; Preserves / Modifies:
;   Clobbers AF, B, HL.
;------------------------------------------------------------------------------
INIT_CFG_FCB_DRIVE:
	; A = drive code (1=A, 2=B...)
INIT_CFG_FCB_COMMON:
	LD HL,CFG_FCB
	LD (HL),A			; Drive byte
	INC HL
	LD (HL),'S'
	INC HL
	LD (HL),'E'
	INC HL
	LD (HL),' '
	INC HL
	LD (HL),' '
	INC HL
	LD (HL),' '
	INC HL
	LD (HL),' '
	INC HL
	LD (HL),' '
	INC HL
	LD (HL),' '
	INC HL
	LD (HL),'C'
	INC HL
	LD (HL),'F'
	INC HL
	LD (HL),'G'
	INC HL
	LD B,24

;------------------------------------------------------------------------------
; INIT_CFG_ZERO: Zero-fill extent and allocation record bytes in CFG_FCB
;
; Purpose:
;   Clears bytes 12..35 (24 bytes) of CFG_FCB to zero.
;
; Call Usage / Protocol:
;   Called via CALL by CFG_FCB initialization routines.
;
; Inputs:
;   None.
;
; Outputs:
;   CFG_FCB extent and record count bytes zeroed.
;
; Preserves / Modifies:
;   Preserves DE; clobbers AF, B, HL.
;------------------------------------------------------------------------------
INIT_CFG_ZERO:
	LD (HL),0
	INC HL
	DJNZ INIT_CFG_ZERO
	RET

;------------------------------------------------------------------------------
; INIT_COM_PROBE_FCB: Initialize PROBE_FCB for drive in register A with SE.COM
;
; Purpose:
;   Initializes PROBE_FCB with drive code in register A (1=A, 2=B...) and
;   filename "SE.COM" to search for program executable.
;
; Call Usage / Protocol:
;   Called via CALL from PROBE_PROGRAM_DRIVE.
;
; Inputs:
;   A = 1-indexed drive code (1..16).
;
; Outputs:
;   PROBE_FCB formatted for search.
;
; Preserves / Modifies:
;   Clobbers AF, B, HL.
;------------------------------------------------------------------------------
INIT_COM_PROBE_FCB:
	; A = drive code (1=A, 2=B...)
	LD HL,COM_PROBE_FCB
	LD (HL),A
	INC HL
	LD (HL),'S'
	INC HL
	LD (HL),'E'
	INC HL
	LD (HL),' '
	INC HL
	LD (HL),' '
	INC HL
	LD (HL),' '
	INC HL
	LD (HL),' '
	INC HL
	LD (HL),' '
	INC HL
	LD (HL),' '
	INC HL
	LD (HL),'C'
	INC HL
	LD (HL),'O'
	INC HL
	LD (HL),'M'
	INC HL
	LD B,24
INIT_COM_ZERO:
	LD (HL),0
	INC HL
	DJNZ INIT_COM_ZERO
	RET

