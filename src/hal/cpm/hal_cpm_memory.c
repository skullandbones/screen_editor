/*==============================================================================
 * HAL_CPM_MEMORY.C: CP/M Hardware Abstraction Layer - Memory & Far RAM Driver
 *
 * Purpose:
 *   Implements slot memory management with automatic RomWBW HBIOS Far RAM
 *   banking detection and transparent fallback to local RAM slots for
 *   standard CP/M 2.2 / 3.0 environments.
 *   Strictly adheres to docs/UI_UX_DESIGN.md.
 *
 * Part of SE.COM / CP/M C Semantic Equivalent Profile (SEC.COM)
 *============================================================================*/

#include <stdint.h>
#include <string.h>
#include <cpm.h>
#include "../../include/config.h"
#include "../../include/buffer.h"
#include "../../include/editor.h"
#include "../../include/block.h"
#include "../../include/memory.h"
#include "../../include/file_io.h"
#include "../../include/ui.h"
#include "../../include/ui_modal.h"
#include "../../include/ui_browser.h"
#include "../../include/plugin.h"
#include "../../include/hal.h"

#define CPM_LOCAL_SLOTS 2

extern char     g_scratch_line_buf[MAX_ACTIVE_LINE_STRIDE];
char            g_ramdrive_char = 0;
uint8_t         g_cpm_hbios_present = 0;
uint8_t         g_cpm_user_bank = 0;
uint8_t         g_cpm_first_app_bank = 0;

uint8_t         g_hbios_src_bank = 0;
uint8_t         g_hbios_dst_bank = 0;
uint16_t        g_hbios_src_addr = 0;
uint16_t        g_hbios_dst_addr = 0;
uint16_t        g_hbios_word_tmp = 0;
uint16_t        g_hbios_len_tmp = 16;

static void hbios_detect_ramdrive(void)
{
#asm
    push ix
    push iy
    ld hl, 0040h
    ld a, (hl)
    cp 'W'
    jr nz, no_ramdrv
    inc hl
    ld a, (hl)
    cp 0A8h
    jr nz, no_ramdrv
    ld hl, (0044h)
    inc hl
    inc hl
    ld e, (hl)
    inc hl
    ld d, (hl)
    ld a, d
    or e
    jr z, no_ramdrv
    ex de, hl
    dec hl
    ld a, (hl)
    inc hl
    or a
    jr z, no_ramdrv
    cp 17
    jr nc, no_ramdrv
    ld b, a
    ld c, 0
ramdrv_loop:
    ld a, (hl)
    inc hl
    inc hl
    inc hl
    inc hl
    cp 0FFh
    jr z, ramdrv_next
    push bc
    push hl
    ld c, a
    ld b, 17h
    rst 08h
    ld a, d
    or e
    pop hl
    pop bc
    jr nz, ramdrv_next
    ld a, c
    add a, 'A'
    ld (_g_ramdrive_char), a
    jr no_ramdrv
ramdrv_next:
    inc c
    djnz ramdrv_loop
no_ramdrv:
    pop iy
    pop ix
#endasm
}

static int hbios_detect(void)
{
#asm
    push ix
    push iy
    ld b, 0F8h
    ld c, 000h
    rst 08h
    pop iy
    pop ix
    or a
    ld l, 0
    jr nz, no_hbios
    ld l, 1
no_hbios:
    ld h, 0
#endasm
}

static uint8_t hbios_get_user_bank(void)
{
#asm
    push ix
    push iy
    ld b, 0F3h
    rst 08h
    ld a, c
    pop iy
    pop ix
    ld l, a
    ld h, 0
#endasm
}

static uint8_t hbios_get_app_bank(void)
{
#asm
    push ix
    push iy
    ld b, 0F8h
    ld c, 0F5h
    rst 08h
    ld a, h
    pop iy
    pop ix
    ld l, a
    ld h, 0
#endasm
}

void hbios_do_copy_len(void);

static void hbios_do_copy_128(void)
{
    g_hbios_len_tmp = 128;
    hbios_do_copy_len();
}

static void hbios_do_copy_2(void)
{
    g_hbios_len_tmp = 2;
    hbios_do_copy_len();
}

void hbios_do_copy_len(void)
{
#asm
    push ix
    push iy
    ld a, (_g_hbios_dst_bank)
    ld d, a
    ld a, (_g_hbios_src_bank)
    ld e, a
    ld hl, (_g_hbios_len_tmp)
    ld b, 0F4h      ; SYSSETCPY
    rst 08h

    ld hl, (_g_hbios_src_addr)
    ld de, (_g_hbios_dst_addr)
    ld b, 0F5h      ; SYSBNKCPY
    rst 08h
    pop iy
    pop ix
#endasm
}

void hal_dir_entry_get(uint8_t idx, char *out_name)
{
    if (g_cpm_hbios_present) {
        g_hbios_dst_bank = g_cpm_user_bank;
        g_hbios_src_bank = (uint8_t)(g_cpm_user_bank - 1);
        g_hbios_src_addr = (uint16_t)(0x7800U + ((uint16_t)idx << 4));
        g_hbios_dst_addr = (uint16_t)out_name;
        g_hbios_len_tmp = 16;
        hbios_do_copy_len();
    } else {
        out_name[0] = '\0';
    }
}

void hal_dir_entry_set(uint8_t idx, const char *name)
{
    if (g_cpm_hbios_present) {
        g_hbios_dst_bank = (uint8_t)(g_cpm_user_bank - 1);
        g_hbios_src_bank = g_cpm_user_bank;
        g_hbios_src_addr = (uint16_t)name;
        g_hbios_dst_addr = (uint16_t)(0x7800U + ((uint16_t)idx << 4));
        g_hbios_len_tmp = 16;
        hbios_do_copy_len();
    }
}

void hal_dir_entry_shift(uint8_t idx, uint8_t count)
{
    uint16_t cur = (uint16_t)(idx + count);
    if (!g_cpm_hbios_present || count == 0) {
        return;
    }
    while (cur > idx) {
        uint8_t chunk = (uint8_t)(cur - idx);
        uint16_t bytes;
        if (chunk > 7) {
            chunk = 7;
        }
        cur -= chunk;
        bytes = (uint16_t)chunk << 4;
        g_hbios_dst_bank = g_cpm_user_bank;
        g_hbios_src_bank = (uint8_t)(g_cpm_user_bank - 1);
        g_hbios_src_addr = (uint16_t)(0x7800U + (cur << 4));
        g_hbios_dst_addr = (uint16_t)(g_scratch_line_buf + 32);
        g_hbios_len_tmp = bytes;
        hbios_do_copy_len();

        g_hbios_dst_bank = (uint8_t)(g_cpm_user_bank - 1);
        g_hbios_src_bank = g_cpm_user_bank;
        g_hbios_src_addr = (uint16_t)(g_scratch_line_buf + 32);
        g_hbios_dst_addr = (uint16_t)(0x7810U + (cur << 4));
        g_hbios_len_tmp = bytes;
        hbios_do_copy_len();
    }
}

uint16_t hal_line_slot_get(uint16_t idx)
{
    if (g_cpm_hbios_present) {
        g_hbios_dst_bank = g_cpm_user_bank;
        g_hbios_src_bank = (uint8_t)(g_cpm_user_bank - 1);
        g_hbios_src_addr = (uint16_t)(idx << 1);
        g_hbios_dst_addr = (uint16_t)&g_hbios_word_tmp;
        hbios_do_copy_2();
        return g_hbios_word_tmp;
    }
    return SLOT_TERM;
}

void hal_line_slot_set(uint16_t idx, uint16_t slot_id)
{
    if (g_cpm_hbios_present) {
        g_hbios_word_tmp = slot_id;
        g_hbios_dst_bank = (uint8_t)(g_cpm_user_bank - 1);
        g_hbios_src_bank = g_cpm_user_bank;
        g_hbios_src_addr = (uint16_t)&g_hbios_word_tmp;
        g_hbios_dst_addr = (uint16_t)(idx << 1);
        hbios_do_copy_2();
    }
}

int hal_mem_init(void)
{
    g_ramdrive_char = 0;
    g_cpm_hbios_present = (uint8_t)hbios_detect();
    if (g_cpm_hbios_present) {
        g_cpm_user_bank = hbios_get_user_bank();
        g_cpm_first_app_bank = hbios_get_app_bank();
        if (g_cpm_first_app_bank == 0) {
            g_cpm_first_app_bank = 0x89;
        }
        hbios_detect_ramdrive();
        return 12;
    }
    return 1;
}

int hal_mem_read_slot(uint16_t slot_id, uint8_t *dest)
{
    if (!dest || slot_id >= MAX_ACTIVE_SLOTS || !g_cpm_hbios_present) {
        return -1;
    }
    g_hbios_dst_bank = g_cpm_user_bank;
    g_hbios_src_bank = (uint8_t)((g_cpm_user_bank - 2) - (slot_id >> 8));
    g_hbios_src_addr = (slot_id & 0xFF) << 7;
    g_hbios_dst_addr = (uint16_t)dest;
    hbios_do_copy_128();
    return 0;
}

int hal_mem_write_slot(uint16_t slot_id, const uint8_t *src)
{
    if (!src || slot_id >= MAX_ACTIVE_SLOTS || !g_cpm_hbios_present) {
        return -1;
    }
    g_hbios_dst_bank = (uint8_t)((g_cpm_user_bank - 2) - (slot_id >> 8));
    g_hbios_src_bank = g_cpm_user_bank;
    g_hbios_src_addr = (uint16_t)src;
    g_hbios_dst_addr = (slot_id & 0xFF) << 7;
    hbios_do_copy_128();
    return 0;
}

/*==============================================================================
 * Upper Memory Host API Trampoline & Vector Table (Must reside >= 0x8000)
 *============================================================================*/
uint8_t  g_plugin_registry[256];
uint8_t  g_plugin_far_bank = 0;
uint8_t  g_plugin_is_far_exec = 0;
uint8_t  g_plugin_mgr_bank = 0;
uint8_t  g_plugin_mgr_loaded = 0;
uint8_t  g_popup_context_id = 0;
uint16_t g_far_entry_addr = 0;
uint16_t g_far_de_arg = 0;
uint16_t g_far_reloc_addr = 0;
uint16_t g_far_reloc_bmap = 0;
uint16_t g_far_reloc_size = 0;
uint8_t  g_far_reloc_bias = 0;
uint8_t  g_far_reloc_cur_byte = 0;
uint8_t  g_far_ret_a = 0;
uint8_t  g_far_ret_c = 0;
uint8_t  g_far_ret_carry = 0;
uint16_t g_tramp_hl_arg = 0;
uint16_t g_tramp_de_arg = 0;
uint16_t g_tramp_bc_arg = 0;
uint8_t  g_tramp_a_arg = 0;
uint16_t g_far_bdos_dma = 0x0080;
uint8_t  g_far_bdos_c = 0;
uint16_t g_far_bdos_de = 0;
uint8_t  g_far_bdos_ret = 0;
#define g_tramp_str_buf (g_scratch_line_buf + 88)

uint16_t host_c_checkout_line(void)
{
    g_cur_doc_row = g_tramp_hl_arg;
    checkout_active_line(g_tramp_hl_arg);
    return g_active_line_len;
}

int host_c_commit_line(void)
{
    uint16_t row = g_tramp_hl_arg;
    char *buf = (char *)g_tramp_de_arg;
    uint16_t len = g_tramp_bc_arg;

    buf[len] = '\0';
    if (g_active_line_valid && g_active_line_row == row) {
        if (buf != g_active_line_buf) {
            memcpy(g_active_line_buf, buf, len + 1);
        }
        g_active_line_len = len;
        commit_active_line();
        return 0;
    }
    if (row == g_doc_total_lines) {
        uint16_t slot = SLOT_TERM;
        if (len > 0 && mem_write_line(&slot, buf, len) < 0) {
            return -1;
        }
        set_line_slot(row, slot);
        g_doc_total_lines++;
        return 0;
    }
    if (row < g_doc_total_lines) {
        int err = 0;
        uint16_t slot = get_line_slot(row, &err);
        if (len == 0) {
            if (slot != SLOT_TERM) {
                mem_free_line_chain(slot);
                set_line_slot(row, SLOT_TERM);
            }
        } else {
            if (mem_write_line(&slot, buf, len) < 0) {
                return -1;
            }
            set_line_slot(row, slot);
        }
        return 0;
    }
    return 0;
}

void host_c_putc(void)
{
    hal_console_putc((char)g_tramp_a_arg);
}

extern int bios_const(void);
extern int bios_conin(void);

int host_c_getkey(void)
{
    return (int)(uint8_t)bios_conin();
}

int host_c_check_key(void)
{
    return bios_const() ? 1 : 0;
}

void host_c_set_status_msg(void)
{
    if (g_tramp_str_buf[0] != '\0') {
        modal_alert("Plugin Notification", g_tramp_str_buf, NULL);
    }
}

void host_c_clear_document(void)
{
    mem_init_paging();
    init_empty_document();
    g_cur_col = 0;
    g_target_col = 0;
    g_top_doc_row = 0;
    g_horiz_pan_offset = 0;
    g_block_mode = BLOCK_MODE_OFF;
}

void host_c_locate_rc(void)
{
    uint8_t r = (uint8_t)((g_tramp_hl_arg >> 8) & 0xFF);
    uint8_t c = (uint8_t)(g_tramp_hl_arg & 0xFF);
    hal_console_locate((uint8_t)(r + 1), (uint8_t)(c + 1));
}

int host_c_load_plugin(void)
{
    return plugin_load_by_name(g_tramp_str_buf);
}

void host_c_unload_slot(void)
{
    plugin_unload_slot(g_tramp_a_arg);
}

void host_c_redraw_base(void)
{
    g_popup_context_id = g_tramp_a_arg;
    redraw_base_screen(g_tramp_a_arg);
}

int host_c_open_plugin_ui(void)
{
    return ui_browser_load_plugin_dialog();
}

int host_c_save_plugin_cfg(void)
{
    uint8_t res;
    file_populate_fcb("PLUGIN.CFG", &g_cpm_fcb);
    g_cpm_fcb.drive = 0;
    bdos(26, (int)g_cpm_dma_buf);
    bdos(19, (int)&g_cpm_fcb);
    file_populate_fcb("PLUGIN.CFG", &g_cpm_fcb);
    g_cpm_fcb.drive = 0;
    if ((uint8_t)bdos(22, (int)&g_cpm_fcb) == 0xFF) {
        bdos(26, DEFAULT_DMA);
        return -1;
    }
    res = (uint8_t)bdos(21, (int)&g_cpm_fcb);
    bdos(16, (int)&g_cpm_fcb);
    bdos(26, DEFAULT_DMA);
    return (res == 0) ? 0 : -1;
}

int host_c_load_plugin_cfg(void)
{
    uint8_t res;
    file_populate_fcb("PLUGIN.CFG", &g_cpm_fcb);
    g_cpm_fcb.drive = 0;
    bdos(26, (int)g_cpm_dma_buf);
    if ((uint8_t)bdos(15, (int)&g_cpm_fcb) == 0xFF) {
        bdos(26, DEFAULT_DMA);
        return -1;
    }
    memset(g_cpm_dma_buf, 0x1A, 128);
    res = (uint8_t)bdos(20, (int)&g_cpm_fcb);
    bdos(16, (int)&g_cpm_fcb);
    bdos(26, DEFAULT_DMA);
    return (res == 0) ? 0 : -1;
}

void host_c_far_bdos(void)
{
    if (g_far_bdos_c == 15 || g_far_bdos_c == 16 ||
        g_far_bdos_c == 19 || g_far_bdos_c == 20 ||
        g_far_bdos_c == 21 || g_far_bdos_c == 22) {
        bdos(26, (int)g_cpm_dma_buf);
        g_far_bdos_ret = (uint8_t)bdos(g_far_bdos_c, (int)&g_cpm_fcb);
        bdos(26, DEFAULT_DMA);
    } else {
        g_far_bdos_ret = 0;
    }
}

void plugin_tramp_dummy_anchor(void)
{
#asm
    PUBLIC _g_plugin_host_api
    PUBLIC _g_host_api_cols
    PUBLIC _g_host_api_context
    PUBLIC _g_host_api_rows
    PUBLIC _g_host_api_mgr_slot
    PUBLIC _tramp_far_bdos

_g_plugin_host_api:
    defb 'S', 'E'
    defw 0115h
    defw _g_active_line_buf
    defw _g_active_line_len
    defw _g_cur_doc_row
    defw _g_doc_total_lines
    defw _g_cur_col
_g_host_api_cols:
    defb 80
_g_host_api_context:
    defb 0
_g_host_api_rows:
    defb 24
_g_host_api_mgr_slot:
    defb 0FFh
    jp _tramp_checkout_line
    jp _tramp_commit_line
    jp _tramp_putc
    jp _tramp_print_str
    jp _tramp_get_key
    jp _tramp_set_status_msg
    defw _g_block_mode
    defw _g_norm_start_row
    defw _g_norm_end_row
    defw _g_config + 3
    defw _g_plugin_registry
    jp _tramp_check_key
    jp _tramp_clear_document
    jp _tramp_locate_rc
    jp _tramp_load_plugin
    jp _tramp_unload_slot
    jp _tramp_redraw_base
    jp _tramp_open_plugin_ui
    jp _tramp_save_plugin_cfg
    jp _tramp_load_plugin_cfg
    jp _tramp_render_status_bar
    jp _tramp_hide_cursor
    jp _tramp_show_cursor

_tramp_enter_user_bank:
    ld a, (_g_plugin_is_far_exec)
    or a
    ret z
    ld a, (_g_cpm_user_bank)
    call 0FFF3h
    ei
    ret

_tramp_exit_user_bank:
    ld a, (_g_plugin_is_far_exec)
    or a
    ret z
    di
    ld a, (_g_plugin_far_bank)
    call 0FFF3h
    ret

_tramp_call_hl:
    jp (hl)

_tramp_common_void:
    push af
    push bc
    push de
    push hl
    push ix
    push iy
    call _tramp_enter_user_bank
    call _tramp_call_hl
    call _tramp_exit_user_bank
    pop iy
    pop ix
    pop hl
    pop de
    pop bc
    pop af
    ret

_tramp_common_int:
    push bc
    push de
    push hl
    push ix
    push iy
    call _tramp_enter_user_bank
    call _tramp_call_hl
    ld a, h
    ld c, l
    push af
    push bc
    call _tramp_exit_user_bank
    pop bc
    pop af
    bit 7, a
    jr nz, tci_err
    ld a, c
    or a
    jr tci_ret
tci_err:
    scf
tci_ret:
    pop iy
    pop ix
    pop hl
    pop de
    pop bc
    ret

_tramp_checkout_line:
    push af
    push de
    push hl
    push ix
    push iy
    ld (_g_tramp_hl_arg), hl
    call _tramp_enter_user_bank
    call _host_c_checkout_line
    ld b, h
    ld c, l
    call _tramp_exit_user_bank
    pop iy
    pop ix
    pop hl
    pop de
    pop af
    ret

_tramp_commit_line:
    ld (_g_tramp_hl_arg), hl
    ld (_g_tramp_de_arg), de
    ld (_g_tramp_bc_arg), bc
    ld hl, _host_c_commit_line
    jr _tramp_common_int

_tramp_putc:
    ld (_g_tramp_a_arg), a
    push hl
    ld hl, _host_c_putc
    jr _tramp_common_void_pop_hl

_tramp_common_void_pop_hl:
    push af
    push bc
    push de
    push ix
    push iy
    call _tramp_enter_user_bank
    call _tramp_call_hl
    call _tramp_exit_user_bank
    pop iy
    pop ix
    pop de
    pop bc
    pop af
    pop hl
    ret

_tramp_print_str:
    push af
    push bc
    push de
    push hl
    ex de, hl
tps_loop:
    ld a, (hl)
    or a
    jr z, tps_done
    cp '$'
    jr z, tps_done
    push hl
    call _tramp_putc
    pop hl
    inc hl
    jr tps_loop
tps_done:
    pop hl
    pop de
    pop bc
    pop af
    ret

_tramp_get_key:
    push bc
    ld hl, _host_c_getkey
    call _tramp_common_int
    pop bc
    ret

_tramp_check_key:
    push bc
    ld hl, _host_c_check_key
    call _tramp_common_int
    or a
    pop bc
    ret

_tramp_copy_de_str:
    ld hl, _g_scratch_line_buf + 88
    ld b, 62
tcds_loop:
    ld a, (de)
    or a
    jr z, tcds_done
    cp '$'
    jr z, tcds_done
    ld (hl), a
    inc de
    inc hl
    djnz tcds_loop
tcds_done:
    xor a
    ld (hl), a
    ret

_tramp_set_status_msg:
    push af
    ld a, d
    or e
    jr z, tssm_skip
    pop af
    push hl
    push de
    push bc
    push af
    call _tramp_copy_de_str
    pop af
    pop bc
    pop de
    ld hl, _host_c_set_status_msg
    jp _tramp_common_void_pop_hl
tssm_skip:
    pop af
    ret

_tramp_clear_document:
    push hl
    ld hl, _host_c_clear_document
    jp _tramp_common_void_pop_hl

_tramp_locate_rc:
    ld (_g_tramp_hl_arg), hl
    push hl
    ld hl, _host_c_locate_rc
    jp _tramp_common_void_pop_hl

_tramp_load_plugin:
    push bc
    push de
    push hl
    call _tramp_copy_de_str
    pop hl
    pop de
    pop bc
    ld hl, _host_c_load_plugin
    jp _tramp_common_int

_tramp_unload_slot:
    ld (_g_tramp_a_arg), a
    push hl
    ld hl, _host_c_unload_slot
    jp _tramp_common_void_pop_hl

_tramp_redraw_base:
    ld (_g_tramp_a_arg), a
    push hl
    ld hl, _host_c_redraw_base
    jp _tramp_common_void_pop_hl

_tramp_open_plugin_ui:
    ld hl, _host_c_open_plugin_ui
    jp _tramp_common_int

_tramp_save_plugin_cfg:
    push bc
    push de
    push hl
    ld hl, _g_cpm_dma_buf
    ex de, hl
    ld bc, 128
    ldir
    pop hl
    pop de
    pop bc
    ld hl, _host_c_save_plugin_cfg
    jp _tramp_common_int

_tramp_load_plugin_cfg:
    push bc
    push de
    push hl
    ld hl, _host_c_load_plugin_cfg
    call _tramp_common_int
    pop hl
    pop de
    pop bc
    ret c
    push bc
    push de
    push hl
    ld hl, _g_cpm_dma_buf
    ld bc, 128
    ldir
    or a
    pop hl
    pop de
    pop bc
    ret

_tramp_render_status_bar:
    push hl
    ld hl, _render_status_bar
    jp _tramp_common_void_pop_hl

_tramp_hide_cursor:
    push hl
    ld hl, _hal_console_hide_cursor
    jp _tramp_common_void_pop_hl

_tramp_show_cursor:
    push hl
    ld hl, _hal_console_show_cursor
    jp _tramp_common_void_pop_hl

_tramp_far_bdos:
    ld a, c
    cp 26
    jr nz, tfb_not_dma
    ld (_g_far_bdos_dma), de
    xor a
    ret
tfb_not_dma:
    push bc
    push de
    push hl
    push ix
    push iy
    ld (_g_far_bdos_c), a
    ld (_g_far_bdos_de), de
    ld hl, (_g_far_bdos_de)
    ld de, _g_cpm_fcb
    ld bc, 36
    ldir
    ld a, (_g_far_bdos_c)
    cp 21
    jr nz, tfb_no_write_copy
    ld hl, (_g_far_bdos_dma)
    ld de, _g_cpm_dma_buf
    ld bc, 128
    ldir
tfb_no_write_copy:
    call _tramp_enter_user_bank
    call _host_c_far_bdos
    call _tramp_exit_user_bank
    ld hl, _g_cpm_fcb
    ld de, (_g_far_bdos_de)
    ld bc, 36
    ldir
    ld a, (_g_far_bdos_c)
    cp 20
    jr nz, tfb_done
    ld a, (_g_far_bdos_ret)
    or a
    jr nz, tfb_done
    ld hl, _g_cpm_dma_buf
    ld de, (_g_far_bdos_dma)
    ld bc, 128
    ldir
tfb_done:
    ld a, (_g_far_bdos_ret)
    ld l, a
    or a
    pop iy
    pop ix
    pop hl
    pop de
    pop bc
    ret
#endasm
}

void hal_far_exec_call(void)
{
#asm
    push ix
    push iy
    ld a, (_g_plugin_far_bank)
    push af
    ld a, (_g_plugin_is_far_exec)
    push af
    ld a, 1
    ld (_g_plugin_is_far_exec), a
    ld hl, (_g_far_entry_addr)
    push hl
    pop ix
    ld iy, _g_plugin_host_api
    ld de, (_g_far_de_arg)
    ld a, (_g_plugin_far_bank)
    di
    call 0FFF9h
    ei
    ld (_g_far_ret_a), a
    ld a, c
    ld (_g_far_ret_c), a
    ld a, 0
    jr nc, hfec_no_cy
    inc a
hfec_no_cy:
    ld (_g_far_ret_carry), a
    pop af
    ld (_g_plugin_is_far_exec), a
    pop af
    ld (_g_plugin_far_bank), a
    pop iy
    pop ix
#endasm
}

void hal_far_relocate_prl(uint8_t bank)
{
#asm
    pop hl
    pop de
    push de
    push hl
    push ix
    push iy
    di
    ld a, e
    call 0FFF3h
    ld hl, (_g_far_reloc_addr)
    ld de, (_g_far_reloc_bmap)
    ld bc, (_g_far_reloc_size)
hfrp_loop:
    ld a, b
    or c
    jr z, hfrp_done
    ld a, (de)
    inc de
    ld (_g_far_reloc_cur_byte), a
    ld a, 8
hfrp_bit:
    push af
    ld a, (_g_far_reloc_cur_byte)
    rla
    ld (_g_far_reloc_cur_byte), a
    jr nc, hfrp_skip
    ld a, (_g_far_reloc_bias)
    add a, (hl)
    ld (hl), a
hfrp_skip:
    inc hl
    dec bc
    ld a, b
    or c
    jr z, hfrp_pop_done
    pop af
    dec a
    jr nz, hfrp_bit
    jr hfrp_loop
hfrp_pop_done:
    pop af
hfrp_done:
    ld a, (_g_cpm_user_bank)
    call 0FFF3h
    ei
    pop iy
    pop ix
#endasm
}
