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

/* Plugin Subsystem Function Entry Points */
void plugin_init_registry(void);
int  plugin_load_by_name(const char *filename);
void plugin_unload_slot(uint8_t slot);
int  plugin_exec_slot(uint8_t slot, uint8_t action);
void plugin_manager_ui(void);
void show_plugin_palette(void);
const plugin_entry_t *plugin_get_entry(uint8_t slot);

#ifdef __cplusplus
}
#endif

#endif /* SE_PLUGIN_H */
