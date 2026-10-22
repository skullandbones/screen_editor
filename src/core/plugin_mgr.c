/*==============================================================================
 * PLUGIN_MGR.C: Core Subsystem - Far RAM Plugin Manager & Host API Bridge
 *
 * Purpose:
 *   Implements the plugin registry table, dynamic PRL/OVL slot allocation,
 *   Host API vector registration, and Plugin Manager user interface.
 *   C semantic equivalent to src/core/plugin_mgr.asm.
 *
 * Part of SE.COM / Multi-Platform Modular Screen Editor Architecture
 *============================================================================*/

#include <string.h>
#include <stdio.h>
#include "../include/config.h"
#include "../include/buffer.h"
#include "../include/ui.h"
#include "../include/ui_modal.h"
#include "../include/plugin.h"
#include "../include/editor.h"
#include "../include/block.h"
#include "../include/beautify.h"
#include "../include/file_io.h"
#include "../include/hal.h"
#ifdef __CPM__
#include <cpm.h>
#else
#include <unistd.h>
#endif

#ifndef __CPM__
static plugin_entry_t s_plugin_registry[PLUGIN_MAX_SLOTS];
static uint8_t        s_plugin_count = 0;

void plugin_init_registry(void)
{
    memset(s_plugin_registry, 0, sizeof(s_plugin_registry));
    s_plugin_count = 0;
}

void plugin_autoload_mgr(void)
{
}

const plugin_entry_t *plugin_get_entry(uint8_t slot)
{
    if (slot < PLUGIN_MAX_SLOTS && s_plugin_registry[slot].active) {
        return &s_plugin_registry[slot];
    }
    return NULL;
}

int plugin_load_by_name(const char *filename)
{
    uint8_t slot;

    if (!filename || filename[0] == '\0') {
        return -1;
    }

    for (slot = 0; slot < PLUGIN_MAX_SLOTS; slot++) {
        if (!s_plugin_registry[slot].active) {
            strncpy(s_plugin_registry[slot].name, filename, 8);
            s_plugin_registry[slot].slot_id = slot;
            s_plugin_registry[slot].active = 1;
            s_plugin_registry[slot].capabilities = CAP_FAR_EXEC |
                                                   CAP_DOC_MUTATE;
            s_plugin_count++;
            return slot;
        }
    }
    return -1;
}

void plugin_unload_slot(uint8_t slot)
{
    if (slot < PLUGIN_MAX_SLOTS && s_plugin_registry[slot].active) {
        s_plugin_registry[slot].active = 0;
        if (s_plugin_count > 0) {
            s_plugin_count--;
        }
    }
}

int plugin_exec_slot(uint8_t slot, uint8_t action)
{
    if (slot >= PLUGIN_MAX_SLOTS || !s_plugin_registry[slot].active) {
        return -1;
    }
    (void)action;
    /* Dispatch action to plugin */
    return 0;
}

void plugin_manager_ui(void)
{
    uint8_t width = 60;
    uint8_t height = 16;
    uint8_t top = (uint8_t)(((g_active_rows - height) / 2) + 1);
    uint8_t left = (uint8_t)(((g_active_cols - width) / 2) + 1);
    uint8_t i;

    hal_console_hide_cursor();
    modal_draw_frame(top, left, width, height, "Plugin Manager");

    modal_draw_row_left(top + 3, left, width,
                        "   Slot  Name      Status      Capabilities");

    for (i = 0; i < PLUGIN_MAX_SLOTS; i++) {
        char buf[48];
        if (s_plugin_registry[i].active) {
            snprintf(buf, sizeof(buf),
                     "   [%u]   %-8.8s  Active      Far RAM Exec",
                     (unsigned)i, s_plugin_registry[i].name);
        } else {
            snprintf(buf, sizeof(buf), "   [%u]   --------  (empty)     ---",
                     (unsigned)i);
        }
        modal_draw_row_left(top + 4 + i, left, width, buf);
    }

    modal_draw_row_centered(top + 13, left, width,
                            "[Q]/[ESC]=Return");
    while (1) {
        int k;
        while ((k = hal_console_getkey()) <= 0) {
            usleep(5000);
        }
        if (k == KEY_ESC || k == 'q' || k == 'Q') {
            if (k == KEY_ESC) {
                while (hal_console_getkey() > 0) {
                    /* Drain trailing escape sequence bytes */
                }
            }
            break;
        }
    }
    g_need_screen_render = 1;
}

static void exec_rot13(void)
{
    uint16_t i;
    for (i = 0; i < g_active_line_len; i++) {
        char c = g_active_line_buf[i];
        if (c >= 'a' && c <= 'z') {
            g_active_line_buf[i] = (char)('a' + (c - 'a' + 13) % 26);
        } else if (c >= 'A' && c <= 'Z') {
            g_active_line_buf[i] = (char)('A' + (c - 'A' + 13) % 26);
        }
    }
    g_doc_modified = 1;
}

static void exec_wordcnt(void)
{
    uint16_t r;
    uint16_t words = 0;
    uint16_t chars = 0;
    char *lbuf = g_scratch_line_buf;
    char msg1[48];
    char msg2[48];

    commit_active_line();
    for (r = 0; r < g_doc_total_lines; r++) {
        uint16_t len = fetch_line_to_buffer(r, lbuf, MAX_ACTIVE_PAYLOAD);
        const char *p = lbuf;
        int in_word = 0;
        chars += len;
        while (*p) {
            if ((unsigned char)*p > ' ') {
                if (!in_word) {
                    words++;
                    in_word = 1;
                }
            } else {
                in_word = 0;
            }
            p++;
        }
    }
    snprintf(msg1, sizeof(msg1), "Lines: %u    Words: %u",
             (unsigned)g_doc_total_lines, (unsigned)words);
    snprintf(msg2, sizeof(msg2), "Characters: %u", (unsigned)chars);
    modal_alert("Word Count", msg1, msg2);
}

typedef struct {
    const char *name;
    const char *desc;
} palette_item_t;

static const palette_item_t s_palette_items[3] = {
    {"ROT13", "Rotate letters by 13"},
    {"WORDCNT", "Document word, line, count"},
    {"BEAUTIFY", "Align Z80 assembly labels"}
};

void show_plugin_palette(void)
{
    uint8_t num_items = 3;
    uint8_t selected = 0;
    uint8_t width = 50;
    uint8_t height = 9;
    uint8_t top, left;
    uint8_t i;

    top = (uint8_t)(((g_active_rows - height) / 2) + 1);
    left = (uint8_t)(((g_active_cols - width) / 2) + 1);

    hal_console_hide_cursor();

    while (1) {
        modal_draw_frame(top, left, width, height, "Plugin Palette");
        modal_draw_row_centered(top + 3, left, width,
                                "Select a plugin to execute:");

        for (i = 0; i < num_items; i++) {
            char line_buf[60];
            snprintf(line_buf, sizeof(line_buf), "  %s%u. %-8s - %s",
                     (i == selected) ? "> " : "  ",
                     (unsigned)(i + 1),
                     s_palette_items[i].name,
                     s_palette_items[i].desc);
            modal_draw_row_left(top + 4 + i, left, width, line_buf);
        }

        modal_draw_row_centered(top + 4 + num_items, left, width,
            "[Up/Down]=Select   [Enter]=Run   [ESC]=Cancel");

        int k;
        while ((k = hal_console_getkey()) <= 0) {
            usleep(5000);
        }

        if (k == KEY_ESC || k == KEY_CTRL_P || k == 'q' || k == 'Q') {
            if (k == KEY_ESC) {
                while (hal_console_getkey() > 0) {
                    /* Drain trailing escape sequence bytes */
                }
            }
            break;
        }
        if (k >= '1' && k <= '3') {
            selected = (uint8_t)(k - '1');
            k = KEY_ENTER;
        }
        if (k == KEY_ENTER || k == '\r' || k == '\n') {
            g_need_screen_render = 1;
            g_need_status_render = 1;
            if (selected == 0) {
                exec_rot13();
            } else if (selected == 1) {
                exec_wordcnt();
            } else if (selected == 2) {
                do_ctrl_y_beautify();
            }
            break;
        }
        if (k == KEY_UP) {
            selected = (selected == 0) ? (num_items - 1) : (selected - 1);
        } else if (k == KEY_DOWN) {
            selected = (selected + 1) % num_items;
        }
    }

    g_need_screen_render = 1;
    g_need_status_render = 1;
}

void show_plugin_palette_ctx(uint8_t ctx)
{
    (void)ctx;
    show_plugin_palette();
}

int plugin_find_vfs(void) { return -1; }
int plugin_ensure_vfs(void) { return -1; }
int plugin_vfs_exec_cmd(uint8_t cmd, uint8_t unit, const char *path,
                        void *buf, uint16_t size, uint16_t start,
                        uint16_t end)
{
    (void)cmd; (void)unit; (void)path; (void)buf; (void)size;
    (void)start; (void)end;
    return -1;
}
uint8_t plugin_vfs_last_unit(void) { return 0xFF; }
void plugin_alert_fat_missing(void) {}
#else
/*==============================================================================
 * CP/M Far RAM Plugin Manager & PRL/OVL Loader Implementation (SEC.COM)
 *============================================================================*/
extern uint8_t  g_cpm_hbios_present;
extern uint8_t  g_cpm_user_bank;
extern uint8_t  g_cpm_first_app_bank;
extern uint8_t  g_hbios_src_bank;
extern uint8_t  g_hbios_dst_bank;
extern uint16_t g_hbios_src_addr;
extern uint16_t g_hbios_dst_addr;
extern uint16_t g_hbios_len_tmp;
void hbios_do_copy_len(void);

extern uint8_t  g_plugin_registry[256];
extern uint8_t  g_plugin_far_bank;
extern uint8_t  g_plugin_is_far_exec;
extern uint8_t  g_plugin_mgr_bank;
extern uint8_t  g_plugin_mgr_loaded;
extern uint8_t  g_popup_context_id;
extern uint16_t g_far_entry_addr;
extern uint16_t g_far_de_arg;
extern uint16_t g_far_reloc_addr;
extern uint16_t g_far_reloc_bmap;
extern uint16_t g_far_reloc_size;
extern uint8_t  g_far_reloc_bias;
extern uint8_t  g_far_ret_a;
extern uint8_t  g_far_ret_c;
extern uint8_t  g_far_ret_carry;
extern uint8_t  g_host_api_cols;
extern uint8_t  g_host_api_context;
extern uint8_t  g_host_api_rows;
extern uint8_t  g_host_api_mgr_slot;
extern uint8_t  tramp_far_bdos;
void hal_far_exec_call(void);
void hal_far_relocate_prl(uint8_t bank);

static uint8_t s_borrowed_banks[4];
static uint8_t s_borrowed_cnt = 0;
static uint8_t s_avail_banks[4];
static uint8_t s_avail_cnt = 0;
static uint8_t s_plugin_ret_code = 0;
#define s_plug_fcb g_cpm_fcb

static void copy_to_far_bank(uint8_t bank, uint16_t src, uint16_t dst,
                             uint16_t len)
{
    g_hbios_src_bank = g_cpm_user_bank;
    g_hbios_dst_bank = bank;
    g_hbios_src_addr = src;
    g_hbios_dst_addr = dst;
    g_hbios_len_tmp = len;
    hbios_do_copy_len();
}

static void init_far_bank_page0(uint8_t bank)
{
    uint8_t *p0 = (uint8_t *)g_scratch_line_buf;
    uint16_t tramp = (uint16_t)&tramp_far_bdos;

    copy_to_far_bank(bank, 0x0000, 0x0000, 256);
    p0[0] = 0xC3;
    p0[1] = (uint8_t)(tramp & 0xFF);
    p0[2] = (uint8_t)(tramp >> 8);
    copy_to_far_bank(bank, (uint16_t)p0, 0x0005, 3);
}

void plugin_init_registry(void)
{
    uint8_t base_bank;

    memset(g_plugin_registry, 0, 256);
    s_borrowed_cnt = 0;
    s_avail_cnt = 0;
    g_plugin_mgr_loaded = 0;
    g_plugin_mgr_bank = 0;
    if (!g_cpm_hbios_present) {
        return;
    }
    base_bank = g_cpm_first_app_bank ? g_cpm_first_app_bank : 0x89;
    if (base_bank + 2 <= (uint8_t)(g_cpm_user_bank - 3)) {
        g_plugin_mgr_bank = base_bank;
        s_avail_banks[0] = (uint8_t)(base_bank - 2);
        s_avail_banks[1] = (uint8_t)(base_bank - 1);
        s_avail_banks[2] = (uint8_t)(base_bank + 2);
        s_avail_banks[3] = (uint8_t)(base_bank + 1);
        s_avail_cnt = 4;
    }
}

static uint8_t borrow_far_bank(void)
{
    uint8_t b;
    if (s_avail_cnt == 0) {
        return 0;
    }
    s_avail_cnt--;
    b = s_avail_banks[s_avail_cnt];
    s_borrowed_banks[s_borrowed_cnt++] = b;
    return b;
}

static void release_far_bank(uint8_t bank)
{
    uint8_t i, j;
    for (i = 0; i < s_borrowed_cnt; i++) {
        if (s_borrowed_banks[i] == bank) {
            for (j = i; j + 1 < s_borrowed_cnt; j++) {
                s_borrowed_banks[j] = s_borrowed_banks[j + 1];
            }
            s_borrowed_cnt--;
            if (s_avail_cnt < 4) {
                s_avail_banks[s_avail_cnt++] = bank;
            }
            return;
        }
    }
}

static int is_range_free_in_bank(uint8_t bank, uint8_t cand_page,
                                 uint8_t page_cnt)
{
    uint8_t slot;
    uint16_t cand_end = (uint16_t)cand_page + (uint16_t)page_cnt;

    if (bank == g_plugin_mgr_bank || cand_end > 128) {
        return 0;
    }
    for (slot = 0; slot < PLUGIN_MAX_SLOTS; slot++) {
        uint8_t *ent = &g_plugin_registry[slot * 32];
        if (ent[22] != 0 && ent[24] == bank) {
            uint16_t sj = ent[25];
            uint16_t ej = sj + ent[27];
            if (cand_page < ej && sj < cand_end) {
                return 0;
            }
        }
    }
    return 1;
}

static int alloc_far_plugin_slot(uint8_t can_suballoc, uint8_t page_cnt,
                                 uint8_t *out_bank, uint8_t *out_page)
{
    uint8_t i, b;

    if (can_suballoc) {
        for (i = 0; i < s_borrowed_cnt; i++) {
            uint16_t c;
            b = s_borrowed_banks[i];
            for (c = 0; c + page_cnt <= 128; c++) {
                if (is_range_free_in_bank(b, (uint8_t)c, page_cnt)) {
                    *out_bank = b;
                    *out_page = (uint8_t)c;
                    return 0;
                }
            }
        }
    } else {
        for (i = 0; i < s_borrowed_cnt; i++) {
            b = s_borrowed_banks[i];
            if (is_range_free_in_bank(b, 0, 128)) {
                *out_bank = b;
                *out_page = 0;
                return 0;
            }
        }
    }

    b = borrow_far_bank();
    if (b == 0) {
        return -1;
    }
    *out_bank = b;
    *out_page = 0;
    return 0;
}

static void sync_host_api_state(void)
{
    g_host_api_cols = g_active_cols;
    g_host_api_context = g_popup_context_id;
    g_host_api_rows = g_active_rows;
    g_host_api_mgr_slot = 0xFF;
}

static void exec_plugin_mgr_action(uint8_t action)
{
    sync_host_api_state();
    g_plugin_far_bank = g_plugin_mgr_bank;
    g_far_entry_addr = (uint16_t)(0x0100U + (uint16_t)action * 3U);
    hal_far_exec_call();
}

static int read_prl_header(uint8_t *hdr)
{
    bdos(26, (int)hdr);
    if (bdos(20, (int)&s_plug_fcb) != 0) return -1;
    bdos(26, (int)g_cpm_dma_buf);
    if (bdos(20, (int)&s_plug_fcb) != 0) return -1;
    return 0;
}

static int read_sectors_to_bank(uint8_t bank, uint16_t dest_addr,
                                uint16_t sectors)
{
    uint8_t *hdr = (uint8_t *)g_scratch_line_buf;
    while (sectors > 0) {
        sectors--;
        bdos(26, (int)hdr);
        if (bdos(20, (int)&s_plug_fcb) != 0) return -1;
        copy_to_far_bank(bank, (uint16_t)hdr, dest_addr, 128);
        dest_addr += 128;
        if (dest_addr >= 0x8000U) break;
    }
    return 0;
}

static void close_plug_fcb(int orig_u)
{
    bdos(16, (int)&s_plug_fcb);
    bdos(32, orig_u);
    bdos(26, DEFAULT_DMA);
}

static int ensure_plugin_mgr_loaded(void)
{
    uint8_t *hdr = (uint8_t *)g_scratch_line_buf;
    uint16_t prog_size;
    int orig_u;

    if (g_plugin_mgr_loaded) {
        return 0;
    }
    if (g_config.plugin_mode == PLUGIN_MODE_DISABLED ||
        !g_cpm_hbios_present || g_plugin_mgr_bank == 0) {
        return -1;
    }

    init_far_bank_page0(g_plugin_mgr_bank);
    file_populate_fcb("PLUGIN.PRL", &s_plug_fcb);
    orig_u = bdos(32, 0xFF);
    bdos(32, g_target_user);

    if ((uint8_t)bdos(15, (int)&s_plug_fcb) == 0xFF) {
        bdos(32, orig_u);
        return -1;
    }

    if (read_prl_header(hdr) < 0) goto mgr_err;
    prog_size = (uint16_t)hdr[1] | ((uint16_t)hdr[2] << 8);
    if (read_sectors_to_bank(g_plugin_mgr_bank, 0x0100,
                             (uint16_t)((prog_size + 127U) >> 7)) < 0) {
        goto mgr_err;
    }

    close_plug_fcb(orig_u);
    g_plugin_mgr_loaded = 1;
    exec_plugin_mgr_action(3);
    return 0;

mgr_err:
    close_plug_fcb(orig_u);
    return -1;
}

void plugin_autoload_mgr(void)
{
    if (g_config.plugin_mode == PLUGIN_MODE_AUTOLOAD) {
        ensure_plugin_mgr_loaded();
    }
}

int plugin_load_by_name(const char *filename)
{
    uint8_t slot;
    uint8_t *hdr = (uint8_t *)g_scratch_line_buf;
    uint16_t prog_size, bss_size, load_addr, caps, payload_bytes, sectors;
    uint8_t size_bits, size_class, can_suballoc, page_cnt;
    uint8_t far_bank = 0, base_page = 0;
    uint16_t base_addr;
    uint8_t *ent;
    int orig_u;

    if (!filename || filename[0] == '\0' || !g_cpm_hbios_present) {
        return -1;
    }

    for (slot = 0; slot < PLUGIN_MAX_SLOTS; slot++) {
        if (g_plugin_registry[slot * 32 + 22] == 0) {
            break;
        }
    }
    if (slot >= PLUGIN_MAX_SLOTS) {
        return -1;
    }

    file_populate_fcb(filename, &s_plug_fcb);
    orig_u = bdos(32, 0xFF);
    bdos(32, g_target_user);

    if (s_plug_fcb.ext[0] == ' ') {
        memcpy(s_plug_fcb.ext, "PRL", 3);
        if ((uint8_t)bdos(15, (int)&s_plug_fcb) == 0xFF) {
            memcpy(s_plug_fcb.ext, "OVL", 3);
            memset(&s_plug_fcb.extent, 0, 24);
            if ((uint8_t)bdos(15, (int)&s_plug_fcb) == 0xFF) {
                bdos(32, orig_u);
                return -1;
            }
        }
    } else if ((uint8_t)bdos(15, (int)&s_plug_fcb) == 0xFF) {
        bdos(32, orig_u);
        return -1;
    }

    if (read_prl_header(hdr) < 0) goto load_err;

    prog_size = (uint16_t)hdr[1] | ((uint16_t)hdr[2] << 8);
    bss_size = (uint16_t)hdr[4] | ((uint16_t)hdr[5] << 8);
    load_addr = (uint16_t)hdr[7] | ((uint16_t)hdr[8] << 8);
    caps = (uint16_t)hdr[28] | ((uint16_t)hdr[29] << 8);
    size_bits = (uint8_t)(caps & CAP_SIZE_MASK);

    if (size_bits == CAP_SIZE_4K) {
        size_class = 0;
        if (prog_size > 4096) goto load_err;
    } else if (size_bits == CAP_SIZE_8K) {
        size_class = 1;
        if (prog_size > 8192) goto load_err;
        if (caps & CAP_TPA_EXEC) {
            uint16_t fp = prog_size + bss_size + 256;
            if (load_addr == 0) fp += (prog_size + 7) >> 3;
            if (fp > 5120) goto load_err;
        }
    } else if (size_bits == CAP_SIZE_16K) {
        size_class = 2;
        if (prog_size > 16384 || (caps & CAP_TPA_EXEC)) goto load_err;
    } else {
        size_class = 3;
        if (prog_size > 32768U || (caps & CAP_TPA_EXEC)) goto load_err;
    }

    payload_bytes = prog_size;
    if (load_addr == 0 && (caps & CAP_TPA_EXEC)) {
        payload_bytes += (uint16_t)((prog_size + 7U) >> 3);
    }
    sectors = (uint16_t)((payload_bytes + 127U) >> 7);

    if (caps & CAP_TPA_EXEC) {
        can_suballoc = 1;
        page_cnt = (uint8_t)((sectors + 3U) >> 1);
    } else {
        can_suballoc = 0;
        page_cnt = (size_class == 1) ? 32 : ((size_class == 2) ? 64 : 128);
    }

    if (alloc_far_plugin_slot(can_suballoc, page_cnt,
                              &far_bank, &base_page) < 0) {
        goto load_err;
    }

    base_addr = (uint16_t)base_page << 8;

    ent = &g_plugin_registry[slot * 32];
    memcpy(ent, hdr + 12, 16);
    ent[16] = hdr[1];
    ent[17] = hdr[2];
    ent[18] = hdr[7];
    ent[19] = hdr[8];
    ent[20] = hdr[28];
    ent[21] = hdr[29];
    ent[22] = 1;
    ent[23] = ((caps & CAP_FAR_EXEC) &&
               (load_addr != 0 || base_page == 0)) ? 1 : 0;
    ent[24] = far_bank;
    ent[25] = base_page;
    ent[26] = size_class;
    ent[27] = page_cnt;
    ent[28] = (uint8_t)s_plug_fcb.ext[0];

    read_sectors_to_bank(far_bank, (uint16_t)(base_addr + 256U), sectors);
    close_plug_fcb(orig_u);

    if (base_page == 0) {
        init_far_bank_page0(far_bank);
    }

    if (load_addr == 0 && base_page != 0) {
        g_far_reloc_addr = (uint16_t)(base_addr + 256U);
        g_far_reloc_bmap = (uint16_t)(base_addr + 256U + prog_size);
        g_far_reloc_size = prog_size;
        g_far_reloc_bias = base_page;
        hal_far_relocate_prl(far_bank);
    }

    return (int)slot;

load_err:
    close_plug_fcb(orig_u);
    return -1;
}

void plugin_unload_slot(uint8_t slot)
{
    uint8_t *ent;
    uint8_t bank, i;

    if (slot >= PLUGIN_MAX_SLOTS) {
        return;
    }
    ent = &g_plugin_registry[slot * 32];
    if (ent[22] == 0) {
        return;
    }
    bank = ent[24];
    memset(ent, 0, 32);

    if (bank == 0) {
        return;
    }
    for (i = 0; i < PLUGIN_MAX_SLOTS; i++) {
        if (g_plugin_registry[i * 32 + 22] != 0 &&
            g_plugin_registry[i * 32 + 24] == bank) {
            return;
        }
    }
    release_far_bank(bank);
}

int plugin_exec_slot(uint8_t slot, uint8_t action)
{
    uint8_t *ent;
    uint8_t ret;

    if (slot >= PLUGIN_MAX_SLOTS) {
        return -1;
    }
    ent = &g_plugin_registry[slot * 32];
    if (ent[22] == 0) {
        return -1;
    }

    checkout_active_line(g_cur_doc_row);
    if (g_block_mode != BLOCK_MODE_OFF) {
        normalize_block_bounds();
    }
    sync_host_api_state();

    g_plugin_far_bank = ent[24];
    g_far_entry_addr = (uint16_t)(((uint16_t)(ent[25] + 1) << 8) +
                                  (uint16_t)action * 3U);
    hal_far_exec_call();
    ret = g_far_ret_a;
    s_plugin_ret_code = ret;

    if (ret == 1) {
        g_doc_modified = 1;
        g_active_line_len = (uint16_t)strlen(g_active_line_buf);
        commit_active_line();
        if (!g_is_splash_screen) {
            render_screen();
        }
    } else if (ret == 2) {
        g_doc_modified = 1;
        g_is_splash_screen = 0;
        invalidate_active_line();
        if (g_cur_doc_row >= g_doc_total_lines) {
            g_cur_doc_row = g_doc_total_lines ? (g_doc_total_lines - 1) : 0;
        }
        checkout_active_line(g_cur_doc_row);
        if (g_cur_col > g_active_line_len) {
            g_cur_col = g_active_line_len;
        }
        render_screen();
    }
    return (int)ret;
}

static void show_need_plugin_mgr_popup(void)
{
    modal_alert("Plugin Manager Unavailable",
                "PLUGIN.PRL not loaded or disabled.", NULL);
}

void plugin_manager_ui(void)
{
    show_plugin_palette_ctx(0xFF);
}

void show_plugin_palette_ctx(uint8_t ctx)
{
    uint16_t saved_row = g_cur_doc_row;
    uint16_t saved_col = g_cur_col;
    uint16_t saved_tcol = g_target_col;
    uint16_t saved_top = g_top_doc_row;
    uint16_t saved_pan = g_horiz_pan_offset;
    uint8_t is_mgr = (uint8_t)(ctx == 0xFF);
    uint8_t in_editor = is_mgr ? (uint8_t)(!g_is_splash_screen)
                               : (uint8_t)(ctx == PLUG_CTX_EDITOR);

    if (!is_mgr) {
        g_popup_context_id = ctx;
    }
    s_plugin_ret_code = 0;

    if (in_editor) {
        checkout_active_line(g_cur_doc_row);
        commit_active_line();
    }

    if (ensure_plugin_mgr_loaded() < 0) {
        show_need_plugin_mgr_popup();
        if (is_mgr) {
            g_need_screen_render = 1;
        } else {
            redraw_base_screen(ctx);
        }
        return;
    }

    while (1) {
        uint8_t slot, act, is_modal;
        exec_plugin_mgr_action(is_mgr ? 0 : 1);
        if (g_far_ret_carry) {
            break;
        }
        slot = g_far_ret_a;
        act = g_far_ret_c;
        if (is_mgr) {
            plugin_exec_slot(slot, act);
            if (s_plugin_ret_code == 2 ||
                (s_plugin_ret_code == 1 && in_editor)) {
                break;
            }
            continue;
        }
        is_modal = (uint8_t)(act != 0 ||
            (g_plugin_registry[slot * 32 + 20] & CAP_MODAL_UI));
        if (is_modal) {
            redraw_base_screen(ctx);
        }
        plugin_exec_slot(slot, act);
        if (!is_modal) {
            break;
        }
        redraw_base_screen(ctx);
    }

    if (s_plugin_ret_code == 2) {
        g_is_splash_screen = 0;
        g_need_screen_render = 1;
        g_need_status_render = 1;
        return;
    }
    if (in_editor && s_plugin_ret_code == 0) {
        g_cur_doc_row = saved_row;
        g_cur_col = saved_col;
        g_target_col = saved_tcol;
        g_top_doc_row = saved_top;
        g_horiz_pan_offset = saved_pan;
        checkout_active_line(g_cur_doc_row);
    }
    if (is_mgr) {
        g_need_screen_render = 1;
        g_need_status_render = 1;
    } else {
        redraw_base_screen(ctx);
    }
}

int plugin_find_vfs(void)
{
    uint8_t slot;
    for (slot = 0; slot < PLUGIN_MAX_SLOTS; slot++) {
        uint8_t *ent = &g_plugin_registry[slot * 32];
        if (ent[22] != 0) {
            uint16_t caps = (uint16_t)ent[20] | ((uint16_t)ent[21] << 8);
            if (caps & CAP_HAS_VFS) {
                return (int)slot;
            }
        }
    }
    return -1;
}

int plugin_ensure_vfs(void)
{
    int slot = plugin_find_vfs();
    if (slot >= 0) return slot;
    slot = plugin_load_by_name("FATFS.PRL");
    if (slot >= 0) return slot;
    return -1;
}

static fat_vfs_request_t s_vfs_req;

int plugin_vfs_exec_cmd(uint8_t cmd, uint8_t unit, const char *path,
                        void *buf, uint16_t size, uint16_t start,
                        uint16_t end)
{
    int slot = plugin_find_vfs();
    uint8_t *ent;
    if (slot < 0) return -1;
    s_vfs_req.cmd = cmd;
    s_vfs_req.unit = unit;
    s_vfs_req.status = 0;
    s_vfs_req.flags = 0;
    s_vfs_req.path = path;
    s_vfs_req.buffer = buf;
    s_vfs_req.buffer_size = size;
    s_vfs_req.count = 0;
    s_vfs_req.start_line = start;
    s_vfs_req.end_line = end;
    ent = &g_plugin_registry[slot * 32];
    sync_host_api_state();
    g_plugin_far_bank = ent[24];
    g_far_entry_addr = (uint16_t)(((uint16_t)(ent[25] + 1) << 8) + 9U);
    g_far_de_arg = (uint16_t)&s_vfs_req;
    hal_far_exec_call();
    if (s_vfs_req.status != VFS_STAT_OK) {
        return -1;
    }
    return (int)s_vfs_req.count;
}

uint8_t plugin_vfs_last_unit(void)
{
    return s_vfs_req.unit;
}

void plugin_alert_fat_missing(void)
{
    modal_alert("FAT Subsystem Missing",
                "Feature requires FATFS.PRL.",
                "FAT filesystem plugin is not loaded.");
}
#endif
