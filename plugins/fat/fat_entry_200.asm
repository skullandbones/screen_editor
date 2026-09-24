;==============================================================================
; FAT_ENTRY_200.ASM - Entry Point at ORG 0200H for PRL Relocation Computation
;==============================================================================

    MODULE fat_entry
    INCLUDE "zcc_opt.def"

    PUBLIC l_dcal
    PUBLIC __Exit
    PUBLIC _host_api_ptr
    PUBLIC _host_putc
    PUBLIC _host_get_key
    PUBLIC _host_get_total_lines
    PUBLIC _host_checkout_line
    PUBLIC _host_commit_line
    PUBLIC _host_set_status_raw
    PUBLIC _host_check_key

    EXTERN _fat_plugin_run
    EXTERN _fat_plugin_about
    EXTERN _fat_plugin_config

    ORG 0200H

;------------------------------------------------------------------------------
; Standard 3-Entry Jump Table
;------------------------------------------------------------------------------
ENTRY:
    JP  _entry_run      ; +0: Action 0 (Main Execution / Browser)
    JP  _entry_about    ; +3: Action 1 (About Screen)
    JP  _entry_config   ; +6: Action 2 (Configuration Screen)

;------------------------------------------------------------------------------
; Host API Resolution
;------------------------------------------------------------------------------
_save_host_api:
    ; Verify IX points to "SE" magic; if not, test IY
    LD  A,(IX+0)
    CP  'S'
    JR  NZ,_chk_iy
    LD  A,(IX+1)
    CP  'E'
    JR  Z,_got_ix
_chk_iy:
    PUSH IY
    POP  IX
_got_ix:
    LD  (_host_api_ptr),IX
    RET

;------------------------------------------------------------------------------
; Entry Dispatchers
;------------------------------------------------------------------------------
_entry_run:
    LD  (_saved_sp),SP
    CALL _save_host_api
    CALL _fat_plugin_run
    LD  SP,(_saved_sp)
    OR  A               ; CY = 0 (Success)
    RET

_entry_about:
    LD  (_saved_sp),SP
    CALL _save_host_api
    CALL _fat_plugin_about
    LD  SP,(_saved_sp)
    OR  A               ; CY = 0 (Success)
    RET

_entry_config:
    LD  (_saved_sp),SP
    CALL _save_host_api
    CALL _fat_plugin_config
    LD  SP,(_saved_sp)
    OR  A               ; CY = 0 (Success)
    RET

l_dcal:
    JP  (HL)

__Exit:
    LD  SP,(_saved_sp)
    RET

;------------------------------------------------------------------------------
; Host API Bridge Functions (Callable from C)
;------------------------------------------------------------------------------

; void host_putc(char c)
_host_putc:
    POP  DE             ; Return address
    POP  BC             ; C = character
    PUSH BC
    PUSH DE
    LD   A,C
    LD   HL,(_host_api_ptr)
    LD   BC,24          ; Offset to CALL_PUTC
    ADD  HL,BC
    CALL l_dcal
    RET

; char host_get_key(void)
_host_get_key:
    LD   HL,(_host_api_ptr)
    LD   DE,30          ; Offset to CALL_GET_KEY
    ADD  HL,DE
    CALL l_dcal         ; Character returned in A
    LD   L,A
    LD   H,0
    RET

; unsigned int host_get_total_lines(void)
_host_get_total_lines:
    LD   HL,(_host_api_ptr)
    LD   DE,10          ; Offset to PTR_TOTAL_LINES
    ADD  HL,DE
    LD   E,(HL)
    INC  HL
    LD   D,(HL)         ; DE = pointer to line count word
    EX   DE,HL
    LD   E,(HL)
    INC  HL
    LD   D,(HL)         ; DE = line count
    EX   DE,HL          ; HL = line count
    RET

; unsigned int host_checkout_line(unsigned int line_num, char *buf)
_host_checkout_line:
    POP  BC             ; Return address
    POP  DE             ; DE = buf
    POP  HL             ; HL = line_num
    PUSH HL
    PUSH DE
    PUSH BC
    ; CALL_CHECKOUT_LINE (IX+18): HL = line_num, DE = buf -> BC = length
    PUSH IX
    LD   IX,(_host_api_ptr)
    PUSH HL
    LD   HL,(_host_api_ptr)
    LD   BC,18
    ADD  HL,BC
    LD   (_call_ptr),HL
    POP  HL
    CALL _do_indirect_call
    POP  IX
    LD   H,B
    LD   L,C            ; HL = length returned
    RET

; void host_commit_line(unsigned int line_num, const char *buf, unsigned int len)
_host_commit_line:
    POP  AF             ; Return address
    POP  BC             ; BC = len
    POP  DE             ; DE = buf
    POP  HL             ; HL = line_num
    PUSH HL
    PUSH DE
    PUSH BC
    PUSH AF
    ; CALL_COMMIT_LINE (IX+21): HL = line_num, DE = buf, BC = len
    PUSH IX
    LD   IX,(_host_api_ptr)
    LD   (_save_hl),HL
    LD   HL,(_host_api_ptr)
    PUSH DE
    LD   DE,21
    ADD  HL,DE
    LD   (_call_ptr),HL
    POP  DE
    LD   HL,(_save_hl)
    CALL _do_indirect_call
    POP  IX
    RET

; void host_set_status_raw(const char *msg)
_host_set_status_raw:
    POP  DE             ; Return address
    POP  HL             ; HL = string pointer
    PUSH HL
    PUSH DE
    EX   DE,HL          ; DE = string pointer
    LD   HL,(_host_api_ptr)
    LD   BC,33          ; Offset to CALL_SET_STATUS
    ADD  HL,BC
    CALL l_dcal
    RET

; unsigned char host_check_key(void)
_host_check_key:
    LD   HL,(_host_api_ptr)
    LD   BC,46          ; Offset to CALL_CHECK_KEY
    ADD  HL,BC
    CALL l_dcal
    LD   L,A
    LD   H,0
    RET

_do_indirect_call:
    LD   IY,(_call_ptr)
    JP   (IY)

;------------------------------------------------------------------------------
; BSS Data
;------------------------------------------------------------------------------
    SECTION bss_compiler
_host_api_ptr:
    DEFS 2
_saved_sp:
    DEFS 2
_call_ptr:
    DEFS 2
_save_hl:
    DEFS 2
