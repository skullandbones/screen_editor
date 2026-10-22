/*==============================================================================
 * PLUGIN.H: Far RAM Plugin Manager, Host API Jump Vector & PRL/OVL Interface
 *
 * Purpose:
 *   Defines plugin registry structures, capability bitmasks, Upper Memory
 *   resident Host API vectors, execution modes, and plugin loader contracts.
 *   C semantic equivalent header mirroring src/include/plugin.inc.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#ifndef SE_PLUGIN_H
#define SE_PLUGIN_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "config.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Plugin Registry Limits & Geometry */
#define PLUGIN_ENTRY_SIZE       32  /* Bytes per plugin descriptor */
#define PLUGIN_MAX_SLOTS        8   /* Maximum concurrent plugin slots */
#define PLUGIN_UI_LINES         17  /* Plugin Manager interactive menu height */

/* Plugin Capability Bitflags */
#define CAP_TPA_EXEC            0x0001
#define CAP_FAR_EXEC            0x0002
#define CAP_DOC_MUTATE          0x0004
#define CAP_MODAL_UI            0x0008
#define CAP_HAS_ABOUT           0x0010
#define CAP_HAS_CONFIG          0x0020
#define CAP_SIZE_4K             0x0000
#define CAP_SIZE_8K             0x0040
#define CAP_SIZE_16K            0x0080
#define CAP_SIZE_32K            0x00C0
#define CAP_SIZE_MASK           0x00C0
#define CAP_HAS_VFS             0x0100

/* Context-Aware Plugin Screen IDs */
#define PLUG_CTX_EDITOR         0
#define PLUG_CTX_SPLASH         1
#define PLUG_CTX_CONFIG         2
#define PLUG_CTX_MEM_INFO       3
#define PLUG_CTX_PLUGIN_MGR     4
#define PLUG_CTX_HELP           5
#define PLUG_CTX_ABOUT          6

/* Plugin Descriptor Record */
typedef struct {
    char     name[8];           /* 8-character ASCII name */
    char     ext[3];            /* Extension (PRL or OVL) */
    uint8_t  slot_id;           /* Slot index (0..7) */
    uint16_t load_address;      /* Base RAM execution address */
    uint16_t entry_point;       /* Execution entry point */
    uint16_t capabilities;      /* Capability bitmask (CAP_*) */
    uint8_t  active;            /* Non-zero if slot is occupied */
#ifndef __CPM__
    uint8_t  reserved[12];      /* Future expansion padding */
#endif
} plugin_entry_t;

/* Headless VFS Command Codes */
#define VFS_CMD_PROBE_MOUNT     0
#define VFS_CMD_LIST_DIR        1
#define VFS_CMD_LOAD_FILE       2
#define VFS_CMD_SAVE_FILE       3
#define VFS_CMD_SAVE_RANGE      4
#define VFS_CMD_OPEN_FILE       5
#define VFS_CMD_READ_CHUNK      6
#define VFS_CMD_CLOSE_FILE      7

/* Headless VFS Status Codes */
#define VFS_STAT_OK             0
#define VFS_STAT_NOT_FOUND      1
#define VFS_STAT_DISK_ERR       2
#define VFS_STAT_BUFFER_FULL    3
#define VFS_STAT_INV_UNIT       4
#define VFS_STAT_READ_ONLY      5
#define VFS_STAT_EOF            6
#define VFS_STAT_UNSUPPORTED    0xFF

/* 16-byte Headless VFS Request Packet (Upper Common RAM > 0x8000) */
typedef struct {
    uint8_t      cmd;           /* +0: Command opcode (VFS_CMD_*) */
    uint8_t      unit;          /* +1: HBIOS unit (0..7 or 0xFF=default) */
    uint8_t      status;        /* +2: Output status (VFS_STAT_*) */
    uint8_t      flags;         /* +3: Option flags */
    const char  *path;          /* +4: DOS path string pointer */
    void        *buffer;        /* +6: Data buffer pointer (> 0x8000) */
    uint16_t     buffer_size;   /* +8: Capacity (bytes or entries) */
    uint16_t     count;         /* +10: Output count */
    uint16_t     start_line;    /* +12: Range start line */
    uint16_t     end_line;      /* +14: Range end line */
} fat_vfs_request_t;

/* Plugin Subsystem Function Entry Points */
void plugin_init_registry(void);
void plugin_autoload_mgr(void);
int  plugin_find_vfs(void);
int  plugin_ensure_vfs(void);
int  plugin_vfs_exec_cmd(uint8_t cmd, uint8_t unit, const char *path,
                         void *buf, uint16_t size, uint16_t start,
                         uint16_t end);
uint8_t plugin_vfs_last_unit(void);
void plugin_alert_fat_missing(void);
int  plugin_load_by_name(const char *filename);
void plugin_unload_slot(uint8_t slot);
int  plugin_exec_slot(uint8_t slot, uint8_t action);
void plugin_manager_ui(void);
void show_plugin_palette(void);
void show_plugin_palette_ctx(uint8_t ctx);
const plugin_entry_t *plugin_get_entry(uint8_t slot);

#ifdef __cplusplus
}
#endif

#endif /* SE_PLUGIN_H */
