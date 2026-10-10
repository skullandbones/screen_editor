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
#include "../../include/config.h"
#include "../../include/hal.h"

#define CPM_LOCAL_SLOTS 48

static uint8_t  s_cpm_local_slots[CPM_LOCAL_SLOTS][FAR_SLOT_SIZE];
static uint8_t  s_hbios_present = 0;
static uint8_t  s_user_bank = 0;
static uint8_t  s_first_app_bank = 0;

static uint8_t  s_hbios_src_bank = 0;
static uint8_t  s_hbios_dst_bank = 0;
static uint16_t s_hbios_src_addr = 0;
static uint16_t s_hbios_dst_addr = 0;

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

static void hbios_do_copy_128(void)
{
#asm
    push ix
    push iy
    ld a, (_s_hbios_dst_bank)
    ld d, a
    ld a, (_s_hbios_src_bank)
    ld e, a
    ld hl, 128
    ld b, 0F4h      ; SYSSETCPY
    rst 08h

    ld hl, (_s_hbios_src_addr)
    ld de, (_s_hbios_dst_addr)
    ld b, 0F5h      ; SYSBNKCPY
    rst 08h
    pop iy
    pop ix
#endasm
}

int hal_mem_init(void)
{
    s_hbios_present = (uint8_t)hbios_detect();
    if (s_hbios_present) {
        s_user_bank = hbios_get_user_bank();
        s_first_app_bank = hbios_get_app_bank();
        if (s_first_app_bank == 0) {
            s_first_app_bank = 0x89;
        }
        return 12;
    }
    memset(s_cpm_local_slots, 0, sizeof(s_cpm_local_slots));
    return 1;
}

int hal_mem_read_slot(uint16_t slot_id, uint8_t *dest)
{
    if (!dest || slot_id >= MAX_ACTIVE_SLOTS) {
        return -1;
    }
    if (s_hbios_present) {
        uint8_t bank_offset = (uint8_t)(slot_id / 256);
        uint16_t slot_in_bank = slot_id % 256;
        s_hbios_dst_bank = s_user_bank;
        s_hbios_src_bank = (uint8_t)(s_first_app_bank + bank_offset);
        s_hbios_src_addr = slot_in_bank * FAR_SLOT_SIZE;
        s_hbios_dst_addr = (uint16_t)dest;
        hbios_do_copy_128();
        return 0;
    }
    if (slot_id < CPM_LOCAL_SLOTS) {
        memcpy(dest, s_cpm_local_slots[slot_id], FAR_SLOT_SIZE);
        return 0;
    }
    return -1;
}

int hal_mem_write_slot(uint16_t slot_id, const uint8_t *src)
{
    if (!src || slot_id >= MAX_ACTIVE_SLOTS) {
        return -1;
    }
    if (s_hbios_present) {
        uint8_t bank_offset = (uint8_t)(slot_id / 256);
        uint16_t slot_in_bank = slot_id % 256;
        s_hbios_dst_bank = (uint8_t)(s_first_app_bank + bank_offset);
        s_hbios_src_bank = s_user_bank;
        s_hbios_src_addr = (uint16_t)src;
        s_hbios_dst_addr = slot_in_bank * FAR_SLOT_SIZE;
        hbios_do_copy_128();
        return 0;
    }
    if (slot_id < CPM_LOCAL_SLOTS) {
        memcpy(s_cpm_local_slots[slot_id], src, FAR_SLOT_SIZE);
        return 0;
    }
    return -1;
}

void hal_mem_set_bank(uint8_t bank)
{
    (void)bank;
}
