/*---------------------------------------------------------------------------/
/  FATFS.PRL - FAT Filesystem Plugin for SE.COM (RomWBW CP/M)
/---------------------------------------------------------------------------*/

#include "fat_plugin.h"

#define NAV_KEY_UP    0x81
#define NAV_KEY_DOWN  0x82
#define NAV_KEY_PGUP  0x83
#define NAV_KEY_PGDN  0x84

#define MAX_ENTRIES   32
#define VISIBLE_ROWS  10

typedef struct {
    char          name[13];
    unsigned long size;
    unsigned char is_dir;
} FileEntry;

static FATFS     s_fs;
static FIL       s_fil;
static DIR       s_dir;
static FILINFO   s_fno;

static FileEntry     s_entries[MAX_ENTRIES];
static int           s_entry_count = 0;
static char          s_line_buf[1024];
static char          s_read_chunk[512];
static FIL           s_vfs_stream_fil;
static unsigned char s_vfs_stream_open = 0;

/*---------------------------------------------------------------------------/
/ Terminal & VT100 Utility Routines
/---------------------------------------------------------------------------*/

static void host_print(const char *s) {
    while (*s) {
        host_putc(*s++);
    }
}

static void host_print_num(unsigned int n) {
    char buf[7];
    int i = 0;
    if (n == 0) {
        host_putc('0');
        return;
    }
    while (n > 0) {
        buf[i++] = (char)('0' + (n % 10));
        n /= 10;
    }
    while (i > 0) {
        host_putc(buf[--i]);
    }
}

static int num_digits(unsigned long n) {
    int d = 1;
    while (n >= 10) {
        d++;
        n /= 10;
    }
    return d;
}

static void host_print_ulong(unsigned long n) {
    char buf[11];
    int i = 0;
    if (n == 0) {
        host_putc('0');
        return;
    }
    while (n > 0) {
        buf[i++] = (char)('0' + (n % 10));
        n /= 10;
    }
    while (i > 0) {
        host_putc(buf[--i]);
    }
}

static void host_print_spaces(int count) {
    while (count-- > 0) {
        host_putc(' ');
    }
}

static void vt_cursor(int row, int col) {
    host_print("\x1b[");
    host_print_num(row);
    host_putc(';');
    host_print_num(col);
    host_putc('H');
}

static void vt_reverse(int on) {
    if (on) {
        host_print("\x1b[7m");
    } else {
        host_print("\x1b[0m");
    }
}

static void vt_clear_screen(void) {
    host_print("\x1b[2J\x1b[H");
}

/* Read key with VT100 arrow key sequence decoding */
static int get_nav_key(void) {
    char c = host_get_key();
    if ((unsigned char)c == 0x1B) {
        if (host_check_key()) {
            char c2 = host_get_key();
            if (c2 == '[') {
                char c3 = host_get_key();
                if (c3 == 'A') return NAV_KEY_UP;
                if (c3 == 'B') return NAV_KEY_DOWN;
                if (c3 == '5') { host_get_key(); return NAV_KEY_PGUP; }
                if (c3 == '6') { host_get_key(); return NAV_KEY_PGDN; }
            }
        }
        return 0x1B;
    }
    if (c == 'k' || c == 'K') return NAV_KEY_UP;
    if (c == 'j' || c == 'J') return NAV_KEY_DOWN;
    return (int)(unsigned char)c;
}

/*---------------------------------------------------------------------------/
/ Action 1: About Screen (CAP_HAS_ABOUT)
/---------------------------------------------------------------------------*/

int fat_plugin_about(void) {
    int rows = (int)host_get_rows();
    int cols = (int)host_get_cols();
    int top_row = ((rows - 15) / 2) + 1;
    int left_col = ((cols - 50) / 2) + 1;
    int r = top_row;

    vt_cursor(r++, left_col);
    host_print("+------------------------------------------------+");
    vt_cursor(r++, left_col);
    host_print("|          FAT Filesystem Plugin v0.1.0          |");
    vt_cursor(r++, left_col);
    host_print("|        Compatible with SE.COM >= v0.9.7        |");
    vt_cursor(r++, left_col);
    host_print("+------------------------------------------------+");
    vt_cursor(r++, left_col);
    host_print("| Features:                                      |");
    vt_cursor(r++, left_col);
    host_print("|  - FAT12 / FAT16 / FAT32 Filesystem Support    |");
    vt_cursor(r++, left_col);
    host_print("|  - Direct SD Card & CF Access via RomWBW HBIOS |");
    vt_cursor(r++, left_col);
    host_print("|  - MBR Partition Auto-Detection                |");
    vt_cursor(r++, left_col);
    host_print("|  - Seamless Editor Text Import and Export      |");
    vt_cursor(r++, left_col);
    host_print("|                                                |");
    vt_cursor(r++, left_col);
    host_print("| Engine: Elm-Chan FatFs R0.15 (1-Clause BSD)    |");
    vt_cursor(r++, left_col);
    host_print("| Driver: RomWBW HBIOS by Dean Jenkins           |");
    vt_cursor(r++, left_col);
    host_print("+------------------------------------------------+");
    vt_cursor(r++, left_col);
    host_print("|           Press any key to continue            |");
    vt_cursor(r++, left_col);
    host_print("+------------------------------------------------+");

    host_get_key();
    return PLUG_RET_CLEAN;
}

/*---------------------------------------------------------------------------/
/ Action 2: Configuration Screen (CAP_HAS_CONFIG)
/---------------------------------------------------------------------------*/

int fat_plugin_config(void) {
    int rows = (int)host_get_rows();
    int cols = (int)host_get_cols();
    int top_row = ((rows - 11) / 2) + 1;
    int left_col = ((cols - 50) / 2) + 1;

    while (1) {
        unsigned char cur_unit = get_hbios_disk_unit();
        int key;
        int r = top_row;

        vt_cursor(r++, left_col);
        host_print("+------------------------------------------------+");
        vt_cursor(r++, left_col);
        host_print("|           FAT Plugin Configuration             |");
        vt_cursor(r++, left_col);
        host_print("+------------------------------------------------+");
        vt_cursor(r++, left_col);
        host_print("| Current HBIOS Disk Unit: [ Unit ");
        host_print_num(cur_unit);
        host_print(" ]             |");
        vt_cursor(r++, left_col);
        host_print("|                                                |");
        vt_cursor(r++, left_col);
        host_print("|  [0] Unit 0 (Primary CF/IDE)  [1] Unit 1 (SD)  |");
        vt_cursor(r++, left_col);
        host_print("|  [2] Unit 2 (Secondary IDE)   [3] Unit 3 (Ext) |");
        vt_cursor(r++, left_col);
        host_print("|  [4] Unit 4 (RC2014 SD0)      [5..7] Extended  |");
        vt_cursor(r++, left_col);
        host_print("|                                                |");
        vt_cursor(r++, left_col);
        host_print("|     Select [0-7] to change    [ESC]=Cancel     |");
        vt_cursor(r++, left_col);
        host_print("+------------------------------------------------+");

        key = host_get_key();
        if (key >= '0' && key <= '7') {
            set_hbios_disk_unit((unsigned char)(key - '0'));
        } else if (key == 0x1B) {
            break;
        }
    }
    return PLUG_RET_CLEAN;
}

/*---------------------------------------------------------------------------/
/ FAT Directory Scanner
/---------------------------------------------------------------------------*/

static FRESULT scan_directory(void) {
    FRESULT fr;
    s_entry_count = 0;

    fr = f_opendir(&s_dir, "/");
    if (fr != FR_OK) return fr;

    while (s_entry_count < MAX_ENTRIES) {
        int i;
        fr = f_readdir(&s_dir, &s_fno);
        if (fr != FR_OK || s_fno.fname[0] == 0) break;
        if (s_fno.fname[0] == '.') continue; /* Skip . and .. */

        for (i = 0; i < 12 && s_fno.fname[i]; i++) {
            s_entries[s_entry_count].name[i] = s_fno.fname[i];
        }
        s_entries[s_entry_count].name[i] = 0;
        s_entries[s_entry_count].size    = s_fno.fsize;
        s_entries[s_entry_count].is_dir  = (s_fno.fattrib & AM_DIR) ? 1 : 0;
        s_entry_count++;
    }

    f_closedir(&s_dir);
    return FR_OK;
}

/*---------------------------------------------------------------------------/
/ File Importer: Streams FAT file lines into SE.COM document
/---------------------------------------------------------------------------*/

static int vfs_load_file(FatVfsRequest *req) {
    FRESULT fr;
    UINT    br;
    unsigned int line_num = 0;
    unsigned int line_pos = 0;
    UINT i;

    fr = f_open(&s_fil, req->path, FA_READ);
    if (fr != FR_OK) {
        req->count = 0;
        req->status = (fr == FR_NO_FILE || fr == FR_NO_PATH) ?
                      VFS_STAT_NOT_FOUND : VFS_STAT_DISK_ERR;
        return (int)req->status;
    }

    /* Reset host editor buffer before streaming lines */
    host_clear_document();

    while (1) {
        fr = f_read(&s_fil, s_read_chunk, sizeof(s_read_chunk), &br);
        if (fr != FR_OK || br == 0) break;

        for (i = 0; i < br; i++) {
            char ch = s_read_chunk[i];
            if (ch == 0x1A) break; /* CP/M EOF marker */

            if (ch == '\r') {
                continue; /* Skip CR, handle on LF */
            } else if (ch == '\n') {
                /* Commit accumulated line */
                s_line_buf[line_pos] = '\0';
                host_commit_line(line_num++, s_line_buf, line_pos);
                line_pos = 0;
            } else {
                if (line_pos < sizeof(s_line_buf) - 1) {
                    s_line_buf[line_pos++] = ch;
                }
            }
        }
        if (i < br && s_read_chunk[i] == 0x1A) break;
    }

    /* Commit final line if file ended without trailing newline */
    if (line_pos > 0 || line_num == 0) {
        s_line_buf[line_pos] = '\0';
        host_commit_line(line_num++, s_line_buf, line_pos);
    }

    f_close(&s_fil);
    req->count = line_num;
    req->status = VFS_STAT_OK;
    return VFS_STAT_OK;
}

static int import_fat_file(const char *filename) {
    FatVfsRequest req;
    req.path = filename;
    if (vfs_load_file(&req) == VFS_STAT_OK) {
        return (int)req.count;
    }
    return 0;
}

/*---------------------------------------------------------------------------/
/ File Exporter: Writes SE.COM document lines out to FAT file
/---------------------------------------------------------------------------*/

static int vfs_save_range(FatVfsRequest *req, unsigned int start,
                          unsigned int end) {
    FRESULT fr;
    UINT    bw;
    unsigned int total = host_get_total_lines();
    unsigned int i;
    unsigned int count = 0;

    fr = f_open(&s_fil, req->path, FA_CREATE_ALWAYS | FA_WRITE);
    if (fr != FR_OK) {
        req->count = 0;
        req->status = (fr == FR_WRITE_PROTECTED) ?
                      VFS_STAT_READ_ONLY : VFS_STAT_DISK_ERR;
        return (int)req->status;
    }

    if (total > 0) {
        if (start >= total) start = total - 1;
        if (end >= total) end = total - 1;
        if (start > end) start = end;

        for (i = start; i <= end; i++) {
            unsigned int len = host_checkout_line(i, s_line_buf);
            if (len > 0) {
                fr = f_write(&s_fil, s_line_buf, len, &bw);
                if (fr != FR_OK) break;
            }
            fr = f_write(&s_fil, "\r\n", 2, &bw);
            if (fr != FR_OK) break;
            count++;
        }
    }

    f_close(&s_fil);
    req->count = count;
    if (fr != FR_OK) {
        req->status = VFS_STAT_DISK_ERR;
        return VFS_STAT_DISK_ERR;
    }
    req->status = VFS_STAT_OK;
    return VFS_STAT_OK;
}

static int export_fat_file(const char *filename) {
    FatVfsRequest req;
    req.path = filename;
    if (vfs_save_range(&req, 0, 0xFFFF) == VFS_STAT_OK) {
        return (int)req.count;
    }
    return 0;
}

/*---------------------------------------------------------------------------/
/ Action 0: Main Execution (Interactive FAT File Manager)
/---------------------------------------------------------------------------*/

int fat_plugin_run(void) {
    FRESULT fr;
    int selected = 0;
    int top_row  = 0;
    int doc_mutated = 0;

    vt_clear_screen();

    /* Mount volume on configured HBIOS unit */
    fr = f_mount(&s_fs, "", 1);
    if (fr != FR_OK) {
        /* Mount failure dialog */
        vt_cursor(7, 14);
        host_print("+----------------------------------------------------+");
        vt_cursor(8, 14);
        host_print("|             FAT Filesystem Mount Error             |");
        vt_cursor(9, 14);
        host_print("+----------------------------------------------------+");
        vt_cursor(10, 14);
        host_print("| Could not mount FAT volume on RomWBW Unit ");
        host_print_num(get_hbios_disk_unit());
        host_print("!      |");
        vt_cursor(11, 14);
        host_print("| FatFs Error Code: ");
        host_print_num((unsigned int)fr);
        host_print_spaces(52 - 19 - ((fr >= 10) ? 2 : 1));
        host_print("|");
        vt_cursor(12, 14);
        host_print("|                                                    |");
        vt_cursor(13, 14);
        host_print("|  [C] Configure HBIOS Disk Unit                     |");
        vt_cursor(14, 14);
        host_print("|  [Q] Exit to Editor                                |");
        vt_cursor(15, 14);
        host_print("+----------------------------------------------------+");

        while (1) {
            int k = host_get_key();
            if (k == 'c' || k == 'C') {
                fat_plugin_config();
                return fat_plugin_run(); /* Retry */
            }
            if (k == 'q' || k == 'Q' || k == 0x1B) {
                vt_clear_screen();
                return PLUG_RET_CLEAN;
            }
        }
    }

    scan_directory();

    while (1) {
        int r, key;

        /* Header Box */
        vt_cursor(2, 12);
        host_print(
            "+--------------------------------------------------------+");
        vt_cursor(3, 12);
        host_print(
            "|             FAT Filesystem Manager v0.1.0              |");
        vt_cursor(4, 12);
        host_print("| Drive: RomWBW Unit ");
        host_print_num(get_hbios_disk_unit());
        host_print(" | Files: ");
        host_print_num(s_entry_count);
        host_print_spaces(24 - num_digits(s_entry_count));
        host_print("|");
        vt_cursor(5, 12);
        host_print(
            "+--------------------------------------------------------+");

        /* File List Rows */
        for (r = 0; r < VISIBLE_ROWS; r++) {
            int idx = top_row + r;
            vt_cursor(6 + r, 12);
            host_putc('|');

            if (idx < s_entry_count) {
                int is_sel = (idx == selected);
                int name_len = 0;
                const char *p = s_entries[idx].name;
                while (*p++) name_len++;

                if (is_sel) vt_reverse(1);
                host_putc(' ');

                if (s_entries[idx].is_dir) {
                    host_print("[DIR] ");
                } else {
                    host_print("      ");
                }

                host_print(s_entries[idx].name);
                host_print_spaces(13 - name_len);

                if (!s_entries[idx].is_dir) {
                    unsigned long sz = s_entries[idx].size;
                    int sz_len = num_digits(sz) + 2;
                    if (sz_len < 12) host_print_spaces(12 - sz_len);
                    host_print_ulong(sz);
                    host_print(" B");
                } else {
                    host_print_spaces(12);
                }

                host_print_spaces(24);
                if (is_sel) vt_reverse(0);
            } else {
                host_print_spaces(56);
            }
            host_putc('|');
        }

        /* Controls Footer */
        vt_cursor(16, 12);
        host_print(
            "+--------------------------------------------------------+");
        vt_cursor(17, 12);
        host_print(
            "| [ENTER/O] Open  [S] Save Buffer  [U] Unit  [Q/ESC] Quit |");
        vt_cursor(18, 12);
        host_print(
            "+--------------------------------------------------------+");

        key = get_nav_key();

        if (key == NAV_KEY_UP) {
            if (selected > 0) {
                selected--;
                if (selected < top_row) top_row = selected;
            }
        } else if (key == NAV_KEY_DOWN) {
            if (selected < s_entry_count - 1) {
                selected++;
                if (selected >= top_row + VISIBLE_ROWS)
                    top_row = selected - VISIBLE_ROWS + 1;
            }
        } else if (key == '\r' || key == '\n' || key == 'o' || key == 'O') {
            if (s_entry_count > 0 && !s_entries[selected].is_dir) {
                /* Confirm Open Dialog */
                vt_cursor(19, 12);
                host_print("Load '");
                host_print(s_entries[selected].name);
                host_print("' into editor? [Y/N]: ");
                key = host_get_key();
                vt_cursor(19, 12);
                host_print_spaces(58);
                if (key == 'y' || key == 'Y' || key == '\r' || key == '\n') {
                    int lines = import_fat_file(s_entries[selected].name);
                    if (lines > 0) {
                        doc_mutated = 1;
                        break; /* Exit with PLUG_RET_DOC_MOD */
                    }
                }
            }
        } else if (key == 's' || key == 'S') {
            /* Save Editor Buffer Dialog */
            char save_name[14];
            int s_idx = 0;

            vt_cursor(19, 12);
            host_print("Save as FAT file [EXPORT.TXT]: ");
            while (s_idx < 12) {
                char ch = host_get_key();
                if (ch == '\r' || ch == '\n') break;
                if (ch == 0x08 || ch == 0x7F) {
                    if (s_idx > 0) {
                        s_idx--;
                        host_print("\b \b");
                    }
                } else if (ch >= ' ' && ch <= '~') {
                    if (ch >= 'a' && ch <= 'z') ch -= 32; /* Uppercase */
                    save_name[s_idx++] = ch;
                    host_putc(ch);
                }
            }
            save_name[s_idx] = 0;
            if (s_idx == 0) {
                /* Default name */
                save_name[0] = 'E'; save_name[1] = 'X'; save_name[2] = 'P';
                save_name[3] = 'O'; save_name[4] = 'R'; save_name[5] = 'T';
                save_name[6] = '.'; save_name[7] = 'T'; save_name[8] = 'X';
                save_name[9] = 'T'; save_name[10] = 0;
            }

            export_fat_file(save_name);
            scan_directory(); /* Refresh file list */
            vt_cursor(19, 12);
            host_print_spaces(58);
        } else if (key == 'u' || key == 'U') {
            f_unmount("");
            fat_plugin_config();
            vt_clear_screen();
            fr = f_mount(&s_fs, "", 1);
            if (fr == FR_OK) {
                scan_directory();
                selected = 0;
                top_row = 0;
            }
        } else if (key == 'q' || key == 'Q' || key == 0x1B) {
            break;
        }
    }

    f_unmount("");
    vt_clear_screen();
    return doc_mutated ? PLUG_RET_DOC_MOD : PLUG_RET_CLEAN;
}

/*---------------------------------------------------------------------------/
/ Action 3: Headless VFS Dispatcher (CAP_HAS_VFS)
/---------------------------------------------------------------------------*/

/* Format entry into 13-byte SE.COM record (8 name + '.'/'/' + 3 ext + null) */
static void vfs_format_entry(char *dest, const char *fname,
                             unsigned char is_dir) {
    int i = 0;
    int j;
    const char *dot;

    for (j = 0; j < 12; j++) {
        dest[j] = ' ';
    }
    dest[12] = 0;

    if (is_dir) {
        dest[8] = '/';
        while (*fname && i < 8) {
            char c = *fname++;
            if (c >= 'a' && c <= 'z') c -= 32;
            dest[i++] = c;
        }
        return;
    }

    dest[8] = '.';
    dot = fname;
    while (*dot && *dot != '.') {
        dot++;
    }

    while (*fname && fname < dot && i < 8) {
        char c = *fname++;
        if (c >= 'a' && c <= 'z') c -= 32;
        dest[i++] = c;
    }

    if (*dot == '.') {
        dot++;
        i = 9;
        while (*dot && i < 12) {
            char c = *dot++;
            if (c >= 'a' && c <= 'z') c -= 32;
            dest[i++] = c;
        }
    }
}

static int vfs_list_dir(FatVfsRequest *req) {
    FRESULT fr;
    DIR dir;
    FILINFO fno;
    char *out_buf = (char *)req->buffer;
    unsigned int max_entries;
    unsigned int count = 0;
    const char *dir_path = req->path;

    if (!dir_path || !dir_path[0]) {
        dir_path = "/";
    }

    if (req->buffer_size == 0) {
        max_entries = 255;
    } else if (req->buffer_size > 255) {
        max_entries = req->buffer_size / 13;
        if (max_entries > 255) max_entries = 255;
    } else {
        max_entries = req->buffer_size;
    }

    fr = f_opendir(&dir, dir_path);
    if (fr != FR_OK) {
        req->count = 0;
        req->status = (fr == FR_NO_PATH || fr == FR_NO_FILE) ?
                      VFS_STAT_NOT_FOUND : VFS_STAT_DISK_ERR;
        return (int)req->status;
    }

    /* Synthesize ".." entry if listing a subdirectory */
    if (dir_path[0] != 0 && (dir_path[0] != '/' || dir_path[1] != 0)) {
        vfs_format_entry(out_buf + (count * 13), "..", 1);
        count++;
    }

    while (count < max_entries) {
        fr = f_readdir(&dir, &fno);
        if (fr != FR_OK || fno.fname[0] == 0) {
            break;
        }

        /* Skip "." current directory entry */
        if (fno.fname[0] == '.' && fno.fname[1] == 0) {
            continue;
        }

        /* Skip hidden and system files */
        if (fno.fattrib & (AM_HID | AM_SYS)) {
            continue;
        }

        vfs_format_entry(out_buf + (count * 13), fno.fname,
                         (fno.fattrib & AM_DIR) ? 1 : 0);
        count++;
    }

    f_closedir(&dir);
    req->count = count;
    req->status = VFS_STAT_OK;
    return VFS_STAT_OK;
}

static int vfs_open_stream(FatVfsRequest *req) {
    FRESULT fr;
    if (s_vfs_stream_open) {
        f_close(&s_vfs_stream_fil);
        s_vfs_stream_open = 0;
    }
    fr = f_open(&s_vfs_stream_fil, req->path, FA_READ);
    if (fr != FR_OK) {
        req->status = (fr == FR_NO_FILE || fr == FR_NO_PATH) ?
                      VFS_STAT_NOT_FOUND : VFS_STAT_DISK_ERR;
        return (int)req->status;
    }
    s_vfs_stream_open = 1;
    req->status = VFS_STAT_OK;
    return VFS_STAT_OK;
}

static int vfs_read_chunk(FatVfsRequest *req) {
    FRESULT fr;
    UINT br = 0;
    if (!s_vfs_stream_open) {
        req->count = 0;
        req->status = VFS_STAT_DISK_ERR;
        return VFS_STAT_DISK_ERR;
    }
    fr = f_read(&s_vfs_stream_fil, req->buffer, req->buffer_size, &br);
    req->count = br;
    if (fr != FR_OK) {
        req->status = VFS_STAT_DISK_ERR;
        return VFS_STAT_DISK_ERR;
    }
    if (br == 0) {
        req->status = VFS_STAT_EOF;
        return VFS_STAT_EOF;
    }
    req->status = VFS_STAT_OK;
    return VFS_STAT_OK;
}

static int vfs_close_stream(FatVfsRequest *req) {
    if (s_vfs_stream_open) {
        f_close(&s_vfs_stream_fil);
        s_vfs_stream_open = 0;
    }
    req->status = VFS_STAT_OK;
    return VFS_STAT_OK;
}

static int vfs_ensure_mounted(unsigned char unit) {
    if (unit != 0xFF) {
        if (unit > 7) {
            return VFS_STAT_INV_UNIT;
        }
        if (unit != get_hbios_disk_unit()) {
            set_hbios_disk_unit(unit);
            s_fs.fs_type = 0;
        }
    }
    if (s_fs.fs_type == 0) {
        FRESULT fr = f_mount(&s_fs, "", 1);
        if (fr != FR_OK) {
            return VFS_STAT_DISK_ERR;
        }
    }
    return VFS_STAT_OK;
}

int fat_vfs_dispatch(FatVfsRequest *req) {
    int ret;

    if (!req) return VFS_STAT_UNSUPPORTED;

    if (req->cmd != VFS_CMD_GET_DEF_UNIT &&
        req->cmd != VFS_CMD_SET_DEF_UNIT &&
        req->cmd != VFS_CMD_READ_CHUNK &&
        req->cmd != VFS_CMD_CLOSE_FILE) {
        ret = vfs_ensure_mounted(req->unit);
        if (ret != VFS_STAT_OK) {
            req->status = (unsigned char)ret;
            return ret;
        }
    }

    switch (req->cmd) {
    case VFS_CMD_PROBE_MOUNT:
        req->unit = get_hbios_disk_unit();
        req->status = VFS_STAT_OK;
        return VFS_STAT_OK;

    case VFS_CMD_LIST_DIR:
        return vfs_list_dir(req);

    case VFS_CMD_LOAD_FILE:
        return vfs_load_file(req);

    case VFS_CMD_SAVE_FILE:
        return vfs_save_range(req, 0, 0xFFFF);

    case VFS_CMD_SAVE_RANGE:
        return vfs_save_range(req, req->start_line, req->end_line);

    case VFS_CMD_OPEN_FILE:
        return vfs_open_stream(req);

    case VFS_CMD_READ_CHUNK:
        return vfs_read_chunk(req);

    case VFS_CMD_CLOSE_FILE:
        return vfs_close_stream(req);

    case VFS_CMD_GET_DEF_UNIT:
        req->unit = get_hbios_disk_unit();
        req->status = VFS_STAT_OK;
        return VFS_STAT_OK;

    case VFS_CMD_SET_DEF_UNIT:
        if (req->unit <= 7) {
            set_hbios_disk_unit(req->unit);
            s_fs.fs_type = 0;
            req->status = VFS_STAT_OK;
            return VFS_STAT_OK;
        }
        req->status = VFS_STAT_INV_UNIT;
        return VFS_STAT_INV_UNIT;

    default:
        req->status = VFS_STAT_UNSUPPORTED;
        return VFS_STAT_UNSUPPORTED;
    }
}
