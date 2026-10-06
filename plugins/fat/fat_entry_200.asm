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
    PUBLIC _host_clear_document
    PUBLIC _host_set_status_raw
    PUBLIC _host_check_key
    PUBLIC _host_get_cols
    PUBLIC _host_get_rows

    EXTERN _fat_plugin_run
    EXTERN _fat_plugin_about
    EXTERN _fat_plugin_config
    EXTERN _fat_vfs_dispatch

    ORG 0200H

;------------------------------------------------------------------------------
; Standard 4-Entry Jump Table
;------------------------------------------------------------------------------
ENTRY:
    JP  _entry_run      ; +0: Action 0 (Main Execution / Browser)
    JP  _entry_about    ; +3: Action 1 (About Screen)
    JP  _entry_config   ; +6: Action 2 (Configuration Screen)
    JP  _entry_vfs      ; +9: Action 3 (Headless VFS Operations)

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
    LD  A,L             ; Return code in A (0=Clean, 1=Line, 2=Doc dirty)
    OR  A               ; CY = 0 (Success)
    RET

_entry_about:
    LD  (_saved_sp),SP
    CALL _save_host_api
    CALL _fat_plugin_about
    LD  SP,(_saved_sp)
    LD  A,L
    OR  A               ; CY = 0 (Success)
    RET

_entry_config:
    LD  (_saved_sp),SP
    CALL _save_host_api
    CALL _fat_plugin_config
    LD  SP,(_saved_sp)
    LD  A,L
    OR  A               ; CY = 0 (Success)
    RET

_entry_vfs:
    LD  (_saved_sp),SP
    CALL _save_host_api
    PUSH DE             ; Pass request packet pointer (in DE) to C handler
    CALL _fat_vfs_dispatch
    POP  DE             ; Balance stack
    LD   SP,(_saved_sp)
    LD   A,L            ; L = status code (0 = OK, non-zero = error)
    OR   A              ; Sets Z/NZ; CY = 0
    RET  Z              ; Success (CY = 0)
    SCF                 ; Error (CY = 1)
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
    POP  AF             ; Return address
    POP  DE             ; DE = buf (2nd arg)
    POP  HL             ; HL = line_num (1st arg)
    PUSH HL
    PUSH DE
    PUSH AF

    PUSH IX
    LD   IX,(_host_api_ptr)
    PUSH DE             ; Save destination buffer (buf)

    ; CALL_CHECKOUT_LINE (IX+18): HL = line_num -> BC = length
    PUSH IX
    POP  IY
    LD   DE,18
    ADD  IY,DE
    CALL _call_iy       ; Returns BC = length

    POP  DE             ; DE = destination buffer (buf)

    ; Source: ACTIVE_LINE_BUF (offset +4 in host API)
    LD   L,(IX+4)
    LD   H,(IX+5)       ; HL = ACTIVE_LINE_BUF

    ; Copy BC bytes from HL (ACTIVE_LINE_BUF) to DE (buf)
    PUSH BC             ; Save length
    LD   A,B
    OR   C
    JR   Z,_hco_null_term
    LDIR

_hco_null_term:
    XOR  A
    LD   (DE),A         ; Null-terminate destination buffer

    POP  HL             ; HL = length returned
    POP  IX
    RET

; void host_commit_line(unsigned int line_num, const char *buf,
;                       unsigned int len)
_host_commit_line:
    POP  AF             ; Return address
    POP  BC             ; BC = len
    POP  DE             ; DE = buf
    POP  HL             ; HL = line_num
    PUSH HL
    PUSH DE
    PUSH BC
    PUSH AF

    PUSH IX
    LD   IX,(_host_api_ptr)

    LD   (_save_hl),HL  ; Save line_num
    PUSH BC             ; Save len

    LD   L,(IX+4)
    LD   H,(IX+5)       ; HL = ACTIVE_LINE_BUF
    PUSH HL             ; Save ACTIVE_LINE_BUF

    ; Copy BC bytes from DE (buf) to HL (ACTIVE_LINE_BUF)
    EX   DE,HL          ; HL = buf (src), DE = ACTIVE_LINE_BUF (dst)
    LD   A,B
    OR   C
    JR   Z,_hcl_null_term
    LDIR

_hcl_null_term:
    XOR  A
    LD   (DE),A         ; Null-terminate ACTIVE_LINE_BUF

    POP  DE             ; DE = ACTIVE_LINE_BUF
    POP  BC             ; BC = len
    LD   L,(IX+6)
    LD   H,(IX+7)       ; HL = ACTIVE_LINE_LEN ptr
    LD   (HL),C
    INC  HL
    LD   (HL),B

    ; CALL_COMMIT_LINE (IX+21): HL = line_num, DE = ACTIVE_LINE_BUF, BC = len
    LD   HL,(_save_hl)
    PUSH DE
    PUSH IX
    POP  IY
    LD   DE,21
    ADD  IY,DE
    POP  DE             ; DE = ACTIVE_LINE_BUF
    CALL _call_iy
    POP  IX
    RET

; void host_clear_document(void)
_host_clear_document:
    PUSH IX
    LD   IX,(_host_api_ptr)
    PUSH IX
    POP  IY
    LD   DE,49          ; Offset to CALL_CLEAR_DOCUMENT
    ADD  IY,DE
    CALL _call_iy
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

; unsigned char host_get_cols(void)
_host_get_cols:
    LD   HL,(_host_api_ptr)
    LD   A,H
    OR   L
    JR   Z,_dflt_cols
    LD   DE,14          ; Offset to HOST_API_COLS
    ADD  HL,DE
    LD   A,(HL)
    OR   A
    JR   Z,_dflt_cols
    LD   L,A
    LD   H,0
    RET
_dflt_cols:
    LD   HL,80
    RET

; unsigned char host_get_rows(void)
_host_get_rows:
    LD   HL,(_host_api_ptr)
    LD   A,H
    OR   L
    JR   Z,_dflt_rows
    LD   DE,16          ; Offset to HOST_API_ROWS
    ADD  HL,DE
    LD   A,(HL)
    OR   A
    JR   Z,_dflt_rows
    LD   L,A
    LD   H,0
    RET
_dflt_rows:
    LD   HL,24
    RET

_call_iy:
    JP   (IY)

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
