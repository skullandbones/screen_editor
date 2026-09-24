/*-----------------------------------------------------------------------*/
/* RomWBW HBIOS Block I/O Driver for Elm-Chan FatFs                     */
/*-----------------------------------------------------------------------*/
/* Interfaces Elm-Chan FatFs with RomWBW HBIOS RST 08H disk vectors:     */
/* - BF_SYSGETBNK (0xF3): Fetch active RAM bank for Far RAM buffers      */
/* - BF_DIOSTATUS (0x10): Check physical drive readiness                 */
/* - BF_DIOSEEK   (0x12): Seek 32-bit LBA (bit 7 of D set for LBA mode)   */
/* - BF_DIOREAD   (0x13): Read 512-byte sectors into target memory bank   */
/* - BF_DIOWRITE  (0x14): Write 512-byte sectors from target memory bank  */
/*-----------------------------------------------------------------------*/

#include "ff.h"
#include "diskio.h"

#if FF_MULTI_PARTITION
PARTITION VolToPart[FF_VOLUMES] = {
    {0, 0}  /* Volume 0 -> Physical Drive 0, Auto-detect FAT partition */
};
#endif

static unsigned char s_hbios_bank = 0;
static unsigned char s_hbios_unit = 1; /* Default: unit 1 (RomWBW SD Card) */
static unsigned long s_hbios_lba  = 0;
static void*         s_hbios_buf  = 0;
static unsigned char s_hbios_count= 1;

/* Query active lower RAM bank ID from HBIOS */
static unsigned char hbios_get_current_bank(void) {
#asm
    ld   b, 0f3h      ; BF_SYSGETBNK
    rst  08h
    ld   a, c         ; Bank ID returned in C
    ld   l, a
    ld   h, 0
#endasm
}

/* Query disk unit readiness (BF_DIOSTATUS) */
static unsigned char hbios_dio_status(unsigned char unit) {
#asm
    ld   a, (_s_hbios_unit)
    ld   c, a
    ld   b, 10h       ; BF_DIOSTATUS
    rst  08h
    jr   nz, hb_stat_fail
    ld   hl, 0        ; Ready (success)
    ret
hb_stat_fail:
    ld   hl, 1        ; Not ready / error
    ret
#endasm
}

/* Perform LBA seek and sector read */
static unsigned char hbios_do_read(void) {
#asm
    ; 1. Seek to target 32-bit LBA
    ld   hl, (_s_hbios_lba)        ; Lower 16 bits
    ld   de, (_s_hbios_lba + 2)    ; Upper 16 bits
    set  7, d                      ; RomWBW convention: set bit 7 of D for LBA mode
    ld   a, (_s_hbios_unit)
    ld   c, a                      ; Disk unit
    ld   b, 12h                    ; BF_DIOSEEK
    rst  08h
    jr   nz, hb_rd_error

    ; 2. Read sector(s) into buffer in target bank
    ld   hl, (_s_hbios_buf)        ; Buffer address
    ld   a, (_s_hbios_count)
    ld   e, a                      ; Sector count
    ld   a, (_s_hbios_bank)
    ld   d, a                      ; Target memory bank
    ld   a, (_s_hbios_unit)
    ld   c, a                      ; Disk unit
    ld   b, 13h                    ; BF_DIOREAD
    rst  08h
    jr   nz, hb_rd_error

    ld   hl, 0                     ; Success
    ret

hb_rd_error:
    ld   hl, 1                     ; Error
    ret
#endasm
}

/* Perform LBA seek and sector write */
static unsigned char hbios_do_write(void) {
#asm
    ; 1. Seek to target 32-bit LBA
    ld   hl, (_s_hbios_lba)        ; Lower 16 bits
    ld   de, (_s_hbios_lba + 2)    ; Upper 16 bits
    set  7, d                      ; RomWBW convention: set bit 7 of D for LBA mode
    ld   a, (_s_hbios_unit)
    ld   c, a                      ; Disk unit
    ld   b, 12h                    ; BF_DIOSEEK
    rst  08h
    jr   nz, hb_wr_error

    ; 2. Write sector(s) from buffer in target bank
    ld   hl, (_s_hbios_buf)        ; Buffer address
    ld   a, (_s_hbios_count)
    ld   e, a                      ; Sector count
    ld   a, (_s_hbios_bank)
    ld   d, a                      ; Target memory bank
    ld   a, (_s_hbios_unit)
    ld   c, a                      ; Disk unit
    ld   b, 14h                    ; BF_DIOWRITE
    rst  08h
    jr   nz, hb_wr_error

    ld   hl, 0                     ; Success
    ret

hb_wr_error:
    ld   hl, 1                     ; Error
    ret
#endasm
}

/* Public API for plugin configuration */
unsigned char get_hbios_disk_unit(void) {
    return s_hbios_unit;
}

void set_hbios_disk_unit(unsigned char unit) {
    s_hbios_unit = unit;
}

/*-----------------------------------------------------------------------*/
/* FatFs Low Level Disk Interface Implementation                         */
/*-----------------------------------------------------------------------*/

DSTATUS disk_initialize (BYTE pdrv) {
    if (pdrv != 0) return STA_NOINIT;
    s_hbios_bank = hbios_get_current_bank();
    if (hbios_dio_status(s_hbios_unit) != 0) {
        return STA_NOINIT;
    }
    return 0;
}

DSTATUS disk_status (BYTE pdrv) {
    if (pdrv != 0) return STA_NOINIT;
    if (hbios_dio_status(s_hbios_unit) != 0) {
        return STA_NOINIT;
    }
    return 0;
}

DRESULT disk_read (BYTE pdrv, BYTE* buff, LBA_t sector, UINT count) {
    UINT i;
    if (pdrv != 0) return RES_PARERR;
    for (i = 0; i < count; i++) {
        s_hbios_buf   = (void*)(buff + (i << 9));
        s_hbios_lba   = sector + i;
        s_hbios_count = 1;
        if (hbios_do_read() != 0) {
            return RES_ERROR;
        }
    }
    return RES_OK;
}

DRESULT disk_write (BYTE pdrv, const BYTE* buff, LBA_t sector, UINT count) {
    UINT i;
    if (pdrv != 0) return RES_PARERR;
    for (i = 0; i < count; i++) {
        s_hbios_buf   = (void*)(buff + (i << 9));
        s_hbios_lba   = sector + i;
        s_hbios_count = 1;
        if (hbios_do_write() != 0) {
            return RES_ERROR;
        }
    }
    return RES_OK;
}

DRESULT disk_ioctl (BYTE pdrv, BYTE cmd, void* buff) {
    if (pdrv != 0) return RES_PARERR;
    switch (cmd) {
    case CTRL_SYNC:
        return RES_OK;
    case GET_SECTOR_SIZE:
        *(WORD*)buff = 512;
        return RES_OK;
    case GET_BLOCK_SIZE:
        *(DWORD*)buff = 1;
        return RES_OK;
    default:
        break;
    }
    return RES_PARERR;
}
