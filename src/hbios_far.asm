;==============================================================================
; RomWBW HBIOS Far Memory Banking Primitives for z88dk / CP/M
; Functions:
;   _hbios_get_bank: returns active bank in L/A
;   _hbios_detect: checks for HBIOS ident vector at 0xFFFC
;   _hbios_copy: performs inter-bank memory transfer via SYSSETCPY & SYSBNKCPY
;==============================================================================

        SECTION code_user

        PUBLIC _hbios_get_bank
        PUBLIC _hbios_detect
        PUBLIC _hbios_copy

;------------------------------------------------------------------------------
; uint8_t hbios_get_bank(void)
; Returns active bank ID in L (and A)
;------------------------------------------------------------------------------
_hbios_get_bank:
        PUSH BC
        LD B,0F3H               ; SYSGETBNK
        RST 08H                 ; RomWBW HBIOS call
        LD L,C                  ; Returned Bank ID in C -> L
        LD H,0
        POP BC
        RET

;------------------------------------------------------------------------------
; bool hbios_detect(void)
; Returns 1 in L if RomWBW HBIOS is detected, 0 otherwise
;------------------------------------------------------------------------------
_hbios_detect:
        PUSH BC
        PUSH DE
        ; Query character device count (CIOCNT: B=0xF8, C=0x00)
        LD B,0F8H
        LD C,000H
        RST 08H
        OR A                    ; HBIOS returns A=0 on success
        JR NZ,.not_found
        LD HL,1                 ; True
        JR .done
.not_found:
        LD HL,0                 ; False
.done:
        POP DE
        POP BC
        RET

;------------------------------------------------------------------------------
; uint8_t hbios_copy(uint8_t dst_bank, void *dst_addr,
;                    uint8_t src_bank, const void *src_addr,
;                    uint16_t count)
;
; z88dk C calling convention (cdecl):
;   Stack:
;     [SP+2]  = dst_bank (16-bit pushed)
;     [SP+4]  = dst_addr (16-bit pointer)
;     [SP+6]  = src_bank (16-bit pushed)
;     [SP+8]  = src_addr (16-bit pointer)
;     [SP+10] = count    (16-bit length)
;------------------------------------------------------------------------------
_hbios_copy:
        PUSH IX
        LD IX,0
        ADD IX,SP

        PUSH BC
        PUSH DE

        ; Step 1: Call SYSSETCPY (B = 0xF4)
        ;   D  = Destination Bank ID
        ;   E  = Source Bank ID
        ;   HL = Byte Count
        LD D,(IX+4)             ; dst_bank
        LD E,(IX+8)             ; src_bank
        LD L,(IX+12)            ; count low
        LD H,(IX+13)            ; count high
        LD B,0F4H               ; SYSSETCPY
        RST 08H                 ; Set up transfer registers

        ; Step 2: Call SYSBNKCPY (B = 0xF5)
        ;   DE = Destination Address
        ;   HL = Source Address
        LD E,(IX+6)             ; dst_addr low
        LD D,(IX+7)             ; dst_addr high
        LD L,(IX+10)            ; src_addr low
        LD H,(IX+11)            ; src_addr high
        LD B,0F5H               ; SYSBNKCPY
        RST 08H                 ; Execute hardware inter-bank copy

        LD L,A                  ; Return HBIOS status code in L
        LD H,0

        POP DE
        POP BC
        POP IX
        RET
