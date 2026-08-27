;==============================================================================
; CP/M FULL-SCREEN TEXT EDITOR FOR ROMWBW / RC2014 (SE.COM)
; Target: Z80 CPU, CP/M 2.2+, RomWBW HBIOS 512K Extended RAM, Minicom/VT100
;==============================================================================

	.org	$0100

start:
	; Print Startup Banner via BDOS 9
	ld	de,msg_start
	ld	c,9
	call	5

	; Clean return to CCP
	ret

msg_start:
	.db	$1b, "[2J", $1b, "[H"			; Clear screen & home cursor
	.db	"=== RomWBW Full-Screen Editor: SE.COM (Z80) ===", $0d, $0a
	.db	"Ready for 512K Extended Buffer allocation.", $0d, $0a, "$"

	.end

