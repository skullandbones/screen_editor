/*---------------------------------------------------------------------------/
/  FAT Filesystem Plugin Header for SE.COM
/---------------------------------------------------------------------------*/

#ifndef FAT_PLUGIN_H
#define FAT_PLUGIN_H

#include "ff.h"

/* Plugin Capability Bitflags */
#define CAP_TPA_EXEC       0x0001
#define CAP_FAR_EXEC       0x0002
#define CAP_DOC_MUTATE     0x0004
#define CAP_MODAL_UI       0x0008
#define CAP_HAS_ABOUT      0x0010
#define CAP_HAS_CONFIG     0x0020
#define CAP_SIZE_8K        0x0040
#define CAP_SIZE_16K       0x0080
#define CAP_SIZE_32K       0x00C0
#define CAP_HAS_VFS        0x0100

/* Return status codes for SE.COM Actions 0..2 */
#define PLUG_RET_CLEAN     0  /* Document buffer not modified */
#define PLUG_RET_LINE_MOD  1  /* Active line modified */
#define PLUG_RET_DOC_MOD   2  /* Full document modified (full redraw) */
#define PLUG_RET_ERROR     0xFF

/* Headless VFS Command Codes (Action 3 at ENTRY+9) */
#define VFS_CMD_PROBE_MOUNT  0   /* Mount / verify unit */
#define VFS_CMD_LIST_DIR     1   /* Read directory entries (13B each) */
#define VFS_CMD_LOAD_FILE    2   /* Import text file into editor */
#define VFS_CMD_SAVE_FILE    3   /* Export editor document to text file */
#define VFS_CMD_SAVE_RANGE   4   /* Export line range (start..end) */
#define VFS_CMD_OPEN_FILE    5   /* Open file for chunk streaming */
#define VFS_CMD_READ_CHUNK   6   /* Read next chunk (up to N bytes) */
#define VFS_CMD_CLOSE_FILE   7   /* Close open chunk stream */
#define VFS_CMD_GET_DEF_UNIT 8   /* Query default configured unit */
#define VFS_CMD_SET_DEF_UNIT 9   /* Update default configured unit */

/* Headless VFS Status Codes */
#define VFS_STAT_OK          0   /* Success */
#define VFS_STAT_NOT_FOUND   1   /* File or path not found */
#define VFS_STAT_DISK_ERR    2   /* Physical I/O or FatFs error */
#define VFS_STAT_BUFFER_FULL 3   /* Buffer overflow or count limit */
#define VFS_STAT_INV_UNIT    4   /* Invalid HBIOS unit */
#define VFS_STAT_READ_ONLY   5   /* Write protected / read only */
#define VFS_STAT_EOF         6   /* End of file reached */
#define VFS_STAT_UNSUPPORTED 0xFF/* Unsupported command */

/* 16-byte Headless VFS Request Packet (Upper Common RAM > 0x8000) */
typedef struct {
    unsigned char cmd;          /* +0: Command opcode (VFS_CMD_*) */
    unsigned char unit;         /* +1: HBIOS unit (0..7 or 0xFF=default) */
    unsigned char status;       /* +2: Output status (VFS_STAT_*) */
    unsigned char flags;        /* +3: Option flags */
    const char   *path;         /* +4: DOS path string pointer */
    void         *buffer;       /* +6: Data buffer pointer (> 0x8000) */
    unsigned int  buffer_size;  /* +8: Capacity (bytes or entries) */
    unsigned int  count;        /* +10: Output count */
    unsigned int  start_line;   /* +12: Range start line */
    unsigned int  end_line;     /* +14: Range end line */
} FatVfsRequest;

/* Host API Functions implemented in fat_entry.asm */
void host_putc(char c);
char host_get_key(void);
unsigned char host_check_key(void);
unsigned int host_get_total_lines(void);
unsigned int host_checkout_line(unsigned int line_num, char *buf);
void host_commit_line(unsigned int line_num, const char *buf, unsigned int len);
void host_clear_document(void);
void host_set_status_raw(const char *msg);

/* HBIOS disk unit access in diskio.c */
unsigned char get_hbios_disk_unit(void);
void set_hbios_disk_unit(unsigned char unit);

/* Plugin Entry Points */
int fat_plugin_run(void);
int fat_plugin_about(void);
int fat_plugin_config(void);
int fat_vfs_dispatch(FatVfsRequest *req);

#endif /* FAT_PLUGIN_H */
