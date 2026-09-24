/*---------------------------------------------------------------------------/
/  FATTEST.COM - Standalone CP/M Test Harness for RomWBW FAT Filesystem
/---------------------------------------------------------------------------/
/  Target: CP/M 2.2 / CP/M 3.0 (SC131, RC2014, and RomWBW Z80 platforms)
/  Runs directly from the CP/M command line (0100H) without SE.COM.
/---------------------------------------------------------------------------*/

#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <cpm.h>
#include "ff.h"
#include "diskio.h"

#define CONFIG_FILENAME "FATFS.CFG"

/* HBIOS unit access in diskio.c */
extern unsigned char get_hbios_disk_unit(void);
extern void set_hbios_disk_unit(unsigned char unit);

static FATFS   s_fs;
static FIL     s_file;
static DIR     s_dir;
static FILINFO s_fno;
static char    s_iobuf[512];

/* Forward declarations */
static void do_pwd(void);

/*---------------------------------------------------------------------------/
/ Helper: CP/M FCB Initialization
/---------------------------------------------------------------------------*/

static void init_fcb(struct fcb *f, const char *fname) {
    int i = 0;
    const char *p = fname;
    memset(f, 0, sizeof(struct fcb));
    memset(f->name, ' ', 8);
    memset(f->ext, ' ', 3);

    /* Skip drive prefix if any (e.g. C:) */
    if (p[0] && p[1] == ':') {
        f->drive = (uint8_t)(toupper((unsigned char)p[0]) - 'A' + 1);
        p += 2;
    }

    while (*p && *p != '.' && i < 8) {
        f->name[i++] = (char)toupper((unsigned char)*p++);
    }
    while (*p && *p != '.') p++;
    if (*p == '.') p++;
    i = 0;
    while (*p && i < 3) {
        f->ext[i++] = (char)toupper((unsigned char)*p++);
    }
}

/*---------------------------------------------------------------------------/
/ Configuration File Management (FATFS.CFG) via Direct CP/M BDOS Calls
/---------------------------------------------------------------------------*/

static unsigned char load_config(int *found) {
    struct fcb f;
    char buf[128];
    unsigned char unit = 2; /* Default: SC131 SD Card (Unit 2) */
    int res, i;

    if (found) *found = 0;

    init_fcb(&f, CONFIG_FILENAME);
    res = bdos(CPM_OPN, (int)&f);
    if (res == -1) {
        return unit; /* File not found on CP/M drive, use default 2 */
    }

    /* Read first 128-byte record containing config text */
    memset(buf, 0, sizeof(buf));
    bdos(CPM_SDMA, (int)buf);
    res = bdos(CPM_READ, (int)&f);
    bdos(CPM_CLS, (int)&f);

    if (res == 0) {
        /* Scan buffer for UNIT=X */
        for (i = 0; i < 120; i++) {
            if ((buf[i] == 'U' || buf[i] == 'u') &&
                (buf[i+1] == 'N' || buf[i+1] == 'n') &&
                (buf[i+2] == 'I' || buf[i+2] == 'i') &&
                (buf[i+3] == 'T' || buf[i+3] == 't') &&
                buf[i+4] == '=') {
                int u = buf[i+5] - '0';
                if (u >= 0 && u <= 7) {
                    unit = (unsigned char)u;
                    if (found) *found = 1;
                    break;
                }
            }
        }
    }
    return unit;
}

static int save_config(unsigned char unit) {
    struct fcb f;
    char buf[128];
    int len, res;

    init_fcb(&f, CONFIG_FILENAME);
    bdos(CPM_DEL, (int)&f); /* Delete existing file */
    res = bdos(CPM_MAKE, (int)&f); /* Create file */
    if (res == -1) {
        printf("[-] Failed to create %s on CP/M drive\n", CONFIG_FILENAME);
        return 0;
    }

    memset(buf, 0x1A, sizeof(buf)); /* Fill with CP/M EOF 0x1A */
    sprintf(buf, "# FATFS.CFG - RomWBW FAT Filesystem Configuration\r\nUNIT=%u\r\n", (unsigned int)unit);
    len = strlen(buf);
    buf[len] = 0x1A; /* CP/M EOF marker */

    bdos(CPM_SDMA, (int)buf);
    res = bdos(CPM_WRIT, (int)&f);
    bdos(CPM_CLS, (int)&f);

    if (res == 0) {
        printf("[+] Configuration saved to %s (UNIT=%u)\n", CONFIG_FILENAME, (unsigned int)unit);
        return 1;
    } else {
        printf("[-] Error writing %s\n", CONFIG_FILENAME);
        return 0;
    }
}

/*---------------------------------------------------------------------------/
/ Helper: FatFs Error Code Descriptions
/---------------------------------------------------------------------------*/

static const char* fresult_str(FRESULT rc) {
    switch (rc) {
    case FR_OK:                  return "FR_OK (Success)";
    case FR_DISK_ERR:            return "FR_DISK_ERR (Hard disk I/O error)";
    case FR_INT_ERR:             return "FR_INT_ERR (Internal assertion failed)";
    case FR_NOT_READY:           return "FR_NOT_READY (Drive/media not ready)";
    case FR_NO_FILE:             return "FR_NO_FILE (File not found)";
    case FR_NO_PATH:             return "FR_NO_PATH (Path not found)";
    case FR_INVALID_NAME:        return "FR_INVALID_NAME (Invalid filename)";
    case FR_DENIED:              return "FR_DENIED (Access denied / directory not empty)";
    case FR_EXIST:               return "FR_EXIST (Object already exists)";
    case FR_INVALID_OBJECT:      return "FR_INVALID_OBJECT (Invalid file/dir)";
    case FR_WRITE_PROTECTED:     return "FR_WRITE_PROTECTED (Write protected)";
    case FR_INVALID_DRIVE:       return "FR_INVALID_DRIVE (Invalid drive)";
    case FR_NOT_ENABLED:         return "FR_NOT_ENABLED (Volume not mounted)";
    case FR_NO_FILESYSTEM:       return "FR_NO_FILESYSTEM (No valid FAT volume)";
    case FR_MKFS_ABORTED:        return "FR_MKFS_ABORTED (Format aborted)";
    case FR_TIMEOUT:             return "FR_TIMEOUT (Operation timed out)";
    case FR_LOCKED:              return "FR_LOCKED (Resource locked)";
    case FR_NOT_ENOUGH_CORE:     return "FR_NOT_ENOUGH_CORE (Out of memory)";
    case FR_TOO_MANY_OPEN_FILES: return "FR_TOO_MANY_OPEN_FILES (Too many files)";
    case FR_INVALID_PARAMETER:   return "FR_INVALID_PARAMETER (Invalid parameter)";
    default:                     return "Unknown FRESULT error";
    }
}

/*---------------------------------------------------------------------------/
/ Helper: 32-bit Number Printing without floating-point runtime bloat
/---------------------------------------------------------------------------*/

static void print_ulong(unsigned long n) {
    char buf[12];
    int i = 0;
    if (n == 0) {
        putchar('0');
        return;
    }
    while (n > 0) {
        buf[i++] = (char)('0' + (n % 10));
        n /= 10;
    }
    while (i > 0) {
        putchar(buf[--i]);
    }
}

/*---------------------------------------------------------------------------/
/ Display Volume Information
/---------------------------------------------------------------------------*/

static void show_volume_info(void) {
    const char *type_name = "Unknown";
    unsigned int cluster_size_kb;

    printf("\n--- RomWBW HBIOS FAT Volume Info ---\n");
    printf("HBIOS Disk Unit   : Unit %u\n", (unsigned int)get_hbios_disk_unit());

    if (s_fs.fs_type == FS_FAT12) type_name = "FAT12";
    else if (s_fs.fs_type == FS_FAT16) type_name = "FAT16";
    else if (s_fs.fs_type == FS_FAT32) type_name = "FAT32";

    printf("Filesystem Type   : %s\n", type_name);
    printf("Sectors / Cluster : %u\n", (unsigned int)s_fs.csize);

    cluster_size_kb = (s_fs.csize * 512) / 1024;
    printf("Cluster Size      : %u KB (%u bytes)\n",
           cluster_size_kb, (unsigned int)(s_fs.csize * 512));
    printf("FAT Start Sector  : ");
    print_ulong(s_fs.fatbase);
    putchar('\n');
    printf("Data Start Sector : ");
    print_ulong(s_fs.database);
    putchar('\n');
}

/*---------------------------------------------------------------------------/
/ Subdirectory Traversal: CD & PWD
/---------------------------------------------------------------------------*/

static void do_pwd(void) {
    char cwd[64];
    FRESULT fr;

    cwd[0] = 0;
    fr = f_getcwd(cwd, sizeof(cwd));
    if (fr != FR_OK) {
        printf("[-] PWD failed: %s\n", fresult_str(fr));
    } else {
        printf("Current directory: %s\n", cwd[0] ? cwd : "/");
    }
}

static void do_cd(const char *path) {
    FRESULT fr;
    char cwd[64];

    if (!path || *path == 0) {
        do_pwd();
        return;
    }

    fr = f_chdir(path);
    if (fr != FR_OK) {
        printf("[-] CD failed: %s\n", fresult_str(fr));
    } else {
        cwd[0] = 0;
        f_getcwd(cwd, sizeof(cwd));
        printf("[+] Current directory: %s\n", cwd[0] ? cwd : "/");
    }
}

/*---------------------------------------------------------------------------/
/ Directory Creation and Removal: MKDIR & RMDIR
/---------------------------------------------------------------------------*/

static void do_mkdir(const char *path) {
    FRESULT fr;
    if (!path || *path == 0) {
        printf("Usage: MKDIR <dirname>\n");
        return;
    }
    printf("[*] Creating directory '%s'...\n", path);
    fr = f_mkdir(path);
    if (fr == FR_OK) {
        printf("[+] Directory '%s' created successfully.\n", path);
    } else {
        printf("[-] MKDIR failed: %s\n", fresult_str(fr));
    }
}

static void do_rmdir(const char *path) {
    FRESULT fr;
    if (!path || *path == 0) {
        printf("Usage: RMDIR <dirname>\n");
        return;
    }
    printf("[*] Removing directory '%s'...\n", path);
    fr = f_unlink(path); /* f_unlink removes file or empty directory */
    if (fr == FR_OK) {
        printf("[+] Directory '%s' removed successfully.\n", path);
    } else {
        printf("[-] RMDIR failed: %s\n", fresult_str(fr));
    }
}

static void do_delete(const char *path) {
    FRESULT fr;
    if (!path || *path == 0) {
        printf("Usage: DEL <filename>\n");
        return;
    }
    printf("[*] Deleting '%s'...\n", path);
    fr = f_unlink(path);
    if (fr == FR_OK) {
        printf("[+] '%s' deleted successfully.\n", path);
    } else {
        printf("[-] DEL failed: %s\n", fresult_str(fr));
    }
}

/*---------------------------------------------------------------------------/
/ Copy Between FAT and CP/M: GET (FAT->CP/M) and PUT (CP/M->FAT)
/---------------------------------------------------------------------------*/

static void do_copy_to_cpm(const char *fat_path, const char *cpm_path) {
    FRESULT fr;
    struct fcb f;
    UINT br;
    unsigned long total_copied = 0;
    char dest_name[16];
    int res;

    if (!fat_path || *fat_path == 0) {
        printf("Usage: GET  <fat_file> [cpm_file]\n");
        printf("       COPY <fat_file> [cpm_file]\n");
        return;
    }

    /* If destination name omitted, derive 8.3 filename from FAT path */
    if (!cpm_path || *cpm_path == 0) {
        const char *p = strrchr(fat_path, '/');
        const char *p2 = strrchr(fat_path, '\\');
        const char *base;
        int i;
        if (p2 && (!p || p2 > p)) p = p2;
        base = p ? p + 1 : fat_path;
        for (i = 0; i < 12 && base[i]; i++) {
            dest_name[i] = (char)toupper((unsigned char)base[i]);
        }
        dest_name[i] = 0;
        cpm_path = dest_name;
    }

    printf("\n[*] Copying FAT '%s' -> CP/M '%s'...\n", fat_path, cpm_path);
    fr = f_open(&s_file, fat_path, FA_READ);
    if (fr != FR_OK) {
        printf("[-] Failed to open FAT file '%s': %s\n", fat_path, fresult_str(fr));
        return;
    }

    init_fcb(&f, cpm_path);
    bdos(CPM_DEL, (int)&f); /* Delete existing file */
    res = bdos(CPM_MAKE, (int)&f);
    if (res == -1) {
        printf("[-] Failed to create CP/M file '%s' (directory full?)\n", cpm_path);
        f_close(&s_file);
        return;
    }

    while (1) {
        memset(s_iobuf, 0x1A, 128); /* Standard CP/M EOF padding */
        fr = f_read(&s_file, s_iobuf, 128, &br);
        if (fr != FR_OK || br == 0) break;

        bdos(CPM_SDMA, (int)s_iobuf);
        res = bdos(CPM_WRIT, (int)&f);
        if (res != 0) {
            printf("[-] Failed writing to CP/M file '%s' (disk full?)\n", cpm_path);
            break;
        }
        total_copied += br;
        if (br < 128) break; /* Last record reached */
    }

    bdos(CPM_CLS, (int)&f);
    f_close(&s_file);

    if (fr == FR_OK) {
        printf("[+] Copied ");
        print_ulong(total_copied);
        printf(" bytes to CP/M file '%s'\n", cpm_path);
    } else {
        printf("[-] Error reading FAT file: %s\n", fresult_str(fr));
    }
}

static void do_copy_from_cpm(const char *cpm_path, const char *fat_path) {
    FRESULT fr;
    struct fcb f;
    UINT bw;
    unsigned long total_copied = 0;
    char dest_name[16];
    int res;

    if (!cpm_path || *cpm_path == 0) {
        printf("Usage: PUT <cpm_file> [fat_file]\n");
        return;
    }

    if (!fat_path || *fat_path == 0) {
        const char *p = strrchr(cpm_path, ':');
        const char *base = p ? p + 1 : cpm_path;
        int i;
        for (i = 0; i < 12 && base[i]; i++) {
            dest_name[i] = (char)toupper((unsigned char)base[i]);
        }
        dest_name[i] = 0;
        fat_path = dest_name;
    }

    init_fcb(&f, cpm_path);
    res = bdos(CPM_OPN, (int)&f);
    if (res == -1) {
        printf("[-] CP/M file '%s' not found\n", cpm_path);
        return;
    }

    printf("\n[*] Copying CP/M '%s' -> FAT '%s'...\n", cpm_path, fat_path);
    fr = f_open(&s_file, fat_path, FA_CREATE_ALWAYS | FA_WRITE);
    if (fr != FR_OK) {
        printf("[-] Failed to create FAT file '%s': %s\n", fat_path, fresult_str(fr));
        bdos(CPM_CLS, (int)&f);
        return;
    }

    while (1) {
        bdos(CPM_SDMA, (int)s_iobuf);
        res = bdos(CPM_READ, (int)&f);
        if (res != 0) break; /* EOF or error */

        fr = f_write(&s_file, s_iobuf, 128, &bw);
        if (fr != FR_OK || bw != 128) {
            printf("[-] Failed writing to FAT file '%s'\n", fat_path);
            break;
        }
        total_copied += bw;
    }

    f_close(&s_file);
    bdos(CPM_CLS, (int)&f);

    if (fr == FR_OK) {
        printf("[+] Copied ");
        print_ulong(total_copied);
        printf(" bytes to FAT file '%s'\n", fat_path);
    }
}

/*---------------------------------------------------------------------------/
/ Directory Listing
/---------------------------------------------------------------------------*/

static void do_dir(const char *path) {
    FRESULT fr;
    int count = 0;
    unsigned long total_bytes = 0;
    char display_path[64];

    if (!path || *path == 0) {
        display_path[0] = 0;
        f_getcwd(display_path, sizeof(display_path));
        if (display_path[0] == 0) strcpy(display_path, "/");
        path = "";
    } else {
        strncpy(display_path, path, sizeof(display_path) - 1);
        display_path[sizeof(display_path) - 1] = 0;
    }

    printf("\nDirectory listing for '%s':\n", display_path);
    printf("----------------------------------------------------\n");

    fr = f_opendir(&s_dir, path);
    if (fr != FR_OK) {
        printf("[-] f_opendir failed: %s\n", fresult_str(fr));
        return;
    }

    while (1) {
        fr = f_readdir(&s_dir, &s_fno);
        if (fr != FR_OK || s_fno.fname[0] == 0) break;
        if (s_fno.fname[0] == '.' && (s_fno.fname[1] == 0 || (s_fno.fname[1] == '.' && s_fno.fname[2] == 0))) {
            if (s_fno.fattrib & AM_DIR) {
                printf("  [DIR]  %-14s\n", s_fno.fname);
                count++;
            }
            continue;
        }

        if (s_fno.fattrib & AM_DIR) {
            printf("  [DIR]  %-14s\n", s_fno.fname);
        } else {
            printf("         %-14s  ", s_fno.fname);
            print_ulong(s_fno.fsize);
            printf(" bytes\n");
            total_bytes += s_fno.fsize;
        }
        count++;
    }

    f_closedir(&s_dir);
    printf("----------------------------------------------------\n");
    printf("Total entries: %d  (Files total: ", count);
    print_ulong(total_bytes);
    printf(" bytes)\n");
}

/*---------------------------------------------------------------------------/
/ Type / Display File Contents
/---------------------------------------------------------------------------*/

static void do_type(const char *filename) {
    FRESULT fr;
    UINT br;
    unsigned long total_read = 0;
    int eof_reached = 0;

    if (!filename || *filename == 0) {
        printf("Usage: TYPE <filename>\n");
        return;
    }

    printf("\n--- Displaying '%s' ---\n", filename);
    fr = f_open(&s_file, filename, FA_READ);
    if (fr != FR_OK) {
        printf("[-] Failed to open '%s': %s\n", filename, fresult_str(fr));
        return;
    }

    while (!eof_reached) {
        UINT i;
        fr = f_read(&s_file, s_iobuf, sizeof(s_iobuf), &br);
        if (fr != FR_OK || br == 0) break;

        for (i = 0; i < br; i++) {
            char ch = s_iobuf[i];
            if (ch == 0x1A) { /* CP/M EOF */
                eof_reached = 1;
                break;
            }
            putchar(ch);
        }
        total_read += br;
    }

    f_close(&s_file);
    printf("\n--- End of file (");
    print_ulong(total_read);
    printf(" bytes read) ---\n");
}

/*---------------------------------------------------------------------------/
/ File Write Test: Create test file, write pattern, read back & verify
/---------------------------------------------------------------------------*/

static void do_write_test(const char *filename, const char *msg) {
    FRESULT fr;
    UINT bw, br;
    const char *test_msg = msg ? msg : "Hello from RomWBW CP/M FAT Test Harness on SC131!\r\n";
    UINT len = (UINT)strlen(test_msg);

    if (!filename || *filename == 0) {
        filename = "SC131TST.TXT";
    }

    printf("\n--- Testing FAT Write: '%s' ---\n", filename);
    printf("[*] Opening file for writing...\n");
    fr = f_open(&s_file, filename, FA_CREATE_ALWAYS | FA_WRITE);
    if (fr != FR_OK) {
        printf("[-] f_open(FA_CREATE_ALWAYS) failed: %s\n", fresult_str(fr));
        return;
    }

    printf("[*] Writing %u bytes...\n", len);
    fr = f_write(&s_file, test_msg, len, &bw);
    if (fr != FR_OK || bw != len) {
        printf("[-] f_write failed: %s (wrote %u / %u bytes)\n", fresult_str(fr), bw, len);
        f_close(&s_file);
        return;
    }

    f_close(&s_file);
    printf("[+] File written and closed successfully.\n");

    /* Verification Readback */
    printf("[*] Re-opening for readback verification...\n");
    fr = f_open(&s_file, filename, FA_READ);
    if (fr != FR_OK) {
        printf("[-] Verification f_open failed: %s\n", fresult_str(fr));
        return;
    }

    memset(s_iobuf, 0, sizeof(s_iobuf));
    fr = f_read(&s_file, s_iobuf, sizeof(s_iobuf) - 1, &br);
    f_close(&s_file);

    if (fr == FR_OK && br == len && memcmp(s_iobuf, test_msg, len) == 0) {
        printf("[+] VERIFICATION PASSED: File readback matches written data exactly!\n");
    } else {
        printf("[-] VERIFICATION FAILED: Data mismatch on readback.\n");
    }
}

/*---------------------------------------------------------------------------/
/ Mount Selected Unit
/---------------------------------------------------------------------------*/

static int mount_unit(unsigned char unit) {
    FRESULT fr;

    set_hbios_disk_unit(unit);
    printf("[*] Initializing RomWBW Disk Unit %u...\n", (unsigned int)unit);

    f_unmount("");
    fr = f_mount(&s_fs, "", 1);
    if (fr != FR_OK) {
        printf("[-] Mount failed on Unit %u: %s\n", (unsigned int)unit, fresult_str(fr));
        if (fr == FR_NO_FILESYSTEM) {
            printf("    (Unit %u may contain raw CP/M slices rather than an MBR FAT partition)\n",
                   (unsigned int)unit);
        } else if (fr == FR_NOT_READY) {
            printf("    (Device on Unit %u is not ready or no media is inserted)\n",
                   (unsigned int)unit);
        }
        return 0;
    }

    printf("[+] Successfully mounted FAT volume on RomWBW Unit %u!\n", (unsigned int)unit);
    show_volume_info();
    return 1;
}

/*---------------------------------------------------------------------------/
/ Help Display
/---------------------------------------------------------------------------*/

static void print_help(void) {
    printf("\nAvailable Commands:\n");
    printf("  DIR [path]           - List files in current or specified directory\n");
    printf("  CD <path>            - Change current directory (e.g. CD SUBDIR, CD ..)\n");
    printf("  PWD                  - Print current working directory\n");
    printf("  MKDIR <path>         - Create a new directory\n");
    printf("  RMDIR <path>         - Remove an empty directory\n");
    printf("  DEL <file>           - Delete a file from FAT volume\n");
    printf("  TYPE <file>          - Display contents of text file\n");
    printf("  GET <fat> [cpm]      - Copy FAT file to CP/M drive (or COPY)\n");
    printf("  PUT <cpm> [fat]      - Copy CP/M file to FAT volume\n");
    printf("  WRITE [file] [txt]   - Write test file and verify readback\n");
    printf("  UNIT <0-7>           - Switch RomWBW HBIOS disk unit, remount, & save\n");
    printf("  SAVE [0-7]           - Save HBIOS unit to FATFS.CFG config file\n");
    printf("  INFO                 - Display filesystem volume info\n");
    printf("  HELP                 - Display this command list\n");
    printf("  QUIT                 - Exit to CP/M prompt\n");
}

/*---------------------------------------------------------------------------/
/ Interactive Command Shell
/---------------------------------------------------------------------------*/

static void command_shell(void) {
    char line[80];
    char cwd[64];

    print_help();

    while (1) {
        char cmd[16];
        char arg1[32];
        char arg2[48];
        int n;

        cwd[0] = 0;
        f_getcwd(cwd, sizeof(cwd));
        printf("\nFAT[%u:%s]> ", (unsigned int)get_hbios_disk_unit(), cwd[0] ? cwd : "/");
        fflush(stdout);

        if (!fgets(line, sizeof(line), stdin)) break;

        /* Strip newline */
        n = strlen(line);
        while (n > 0 && (line[n-1] == '\r' || line[n-1] == '\n')) {
            line[--n] = 0;
        }
        if (n == 0) continue;

        cmd[0] = 0; arg1[0] = 0; arg2[0] = 0;
        sscanf(line, "%15s %31s %47[^\n]", cmd, arg1, arg2);

        /* Uppercase command */
        for (n = 0; cmd[n]; n++) cmd[n] = (char)toupper((unsigned char)cmd[n]);

        if (strcmp(cmd, "QUIT") == 0 || strcmp(cmd, "Q") == 0 || strcmp(cmd, "EXIT") == 0) {
            break;
        } else if (strcmp(cmd, "DIR") == 0 || strcmp(cmd, "D") == 0 || strcmp(cmd, "LS") == 0) {
            do_dir(arg1[0] ? arg1 : NULL);
        } else if (strcmp(cmd, "CD") == 0 || strcmp(cmd, "CHDIR") == 0) {
            do_cd(arg1[0] ? arg1 : NULL);
        } else if (strcmp(cmd, "PWD") == 0) {
            do_pwd();
        } else if (strcmp(cmd, "MKDIR") == 0 || strcmp(cmd, "MD") == 0) {
            do_mkdir(arg1[0] ? arg1 : NULL);
        } else if (strcmp(cmd, "RMDIR") == 0 || strcmp(cmd, "RD") == 0) {
            do_rmdir(arg1[0] ? arg1 : NULL);
        } else if (strcmp(cmd, "DEL") == 0 || strcmp(cmd, "RM") == 0) {
            do_delete(arg1[0] ? arg1 : NULL);
        } else if (strcmp(cmd, "GET") == 0 || strcmp(cmd, "COPY") == 0 || strcmp(cmd, "CP") == 0) {
            do_copy_to_cpm(arg1[0] ? arg1 : NULL, arg2[0] ? arg2 : NULL);
        } else if (strcmp(cmd, "PUT") == 0) {
            do_copy_from_cpm(arg1[0] ? arg1 : NULL, arg2[0] ? arg2 : NULL);
        } else if (strcmp(cmd, "TYPE") == 0 || strcmp(cmd, "T") == 0 || strcmp(cmd, "CAT") == 0) {
            do_type(arg1[0] ? arg1 : NULL);
        } else if (strcmp(cmd, "WRITE") == 0 || strcmp(cmd, "W") == 0) {
            do_write_test(arg1[0] ? arg1 : NULL, arg2[0] ? arg2 : NULL);
        } else if (strcmp(cmd, "UNIT") == 0 || strcmp(cmd, "U") == 0) {
            if (arg1[0] >= '0' && arg1[0] <= '7') {
                unsigned char u = (unsigned char)(arg1[0] - '0');
                if (mount_unit(u)) {
                    save_config(u);
                }
            } else {
                printf("Usage: UNIT <0-7>\n");
            }
        } else if (strcmp(cmd, "SAVE") == 0) {
            unsigned char u = get_hbios_disk_unit();
            if (arg1[0] >= '0' && arg1[0] <= '7') {
                u = (unsigned char)(arg1[0] - '0');
            }
            save_config(u);
        } else if (strcmp(cmd, "INFO") == 0 || strcmp(cmd, "I") == 0) {
            show_volume_info();
        } else if (strcmp(cmd, "HELP") == 0 || strcmp(cmd, "H") == 0 || strcmp(cmd, "?") == 0) {
            print_help();
        } else {
            printf("Unknown command '%s'. Type HELP for available commands.\n", cmd);
        }
    }
}

/*---------------------------------------------------------------------------/
/ Main Entry Point
/---------------------------------------------------------------------------*/

int main(int argc, char **argv) {
    int has_cfg = 0;
    int has_cli_unit = 0;
    int cmd_arg_idx = 0;
    unsigned char target_unit = 2; /* SC131 SD Card default */

    printf("\n====================================================\n");
    printf("  RomWBW FAT Filesystem Test Harness v1.1.0 (SC131)\n");
    printf("  Direct HBIOS RST 08H + Elm-Chan FatFs R0.15 Engine\n");
    printf("====================================================\n");

    /* Try loading configuration from FATFS.CFG */
    target_unit = load_config(&has_cfg);
    if (has_cfg) {
        printf("[*] Loaded configuration from %s: Unit %u\n", CONFIG_FILENAME, (unsigned int)target_unit);
    } else {
        printf("[*] %s not found; default RomWBW unit is %u (SC131 SD Card)\n",
               CONFIG_FILENAME, (unsigned int)target_unit);
    }

    /* Parse optional initial unit or command from command line */
    if (argc > 1) {
        if (argv[1][0] >= '0' && argv[1][0] <= '7' && argv[1][1] == 0) {
            target_unit = (unsigned char)(argv[1][0] - '0');
            has_cli_unit = 1;
            printf("[*] Using unit specified on command line: Unit %u\n", (unsigned int)target_unit);
            if (argc > 2) cmd_arg_idx = 2;
        } else {
            cmd_arg_idx = 1;
        }
    }

    if (mount_unit(target_unit)) {
        /* If no config file existed yet, save default so it is persisted */
        if (!has_cfg && !has_cli_unit) {
            save_config(target_unit);
        }
    } else {
        /* If default unit failed and not explicitly forced by CLI or CFG, probe other units */
        int mounted = 0;
        if (!has_cli_unit && !has_cfg) {
            unsigned char u;
            printf("\n[*] Unit %u not available. Probing RomWBW HBIOS disk units...\n", (unsigned int)target_unit);
            for (u = 0; u < 8; u++) {
                if (u == target_unit) continue;
                if (mount_unit(u)) {
                    mounted = 1;
                    target_unit = u;
                    save_config(target_unit);
                    break;
                }
            }
        }
        if (!mounted) {
            printf("\n[-] Could not mount FAT volume on Unit %u.\n", (unsigned int)target_unit);
            printf("Entering interactive shell. Use 'UNIT <0-7>' to select and mount another disk unit.\n");
            command_shell();
            f_unmount("");
            printf("\nExiting FAT test harness. Back to CP/M.\n\n");
            return 0;
        }
    }

    /* If batch command provided, run it directly and exit */
    if (cmd_arg_idx > 0 && cmd_arg_idx < argc) {
        char bcmd[16];
        int i;
        for (i = 0; i < 15 && argv[cmd_arg_idx][i]; i++) {
            bcmd[i] = (char)toupper((unsigned char)argv[cmd_arg_idx][i]);
        }
        bcmd[i] = 0;

        if (strcmp(bcmd, "DIR") == 0 || strcmp(bcmd, "LS") == 0) {
            do_dir(cmd_arg_idx + 1 < argc ? argv[cmd_arg_idx + 1] : NULL);
        } else if (strcmp(bcmd, "CD") == 0) {
            do_cd(cmd_arg_idx + 1 < argc ? argv[cmd_arg_idx + 1] : NULL);
        } else if (strcmp(bcmd, "PWD") == 0) {
            do_pwd();
        } else if (strcmp(bcmd, "MKDIR") == 0 || strcmp(bcmd, "MD") == 0) {
            do_mkdir(cmd_arg_idx + 1 < argc ? argv[cmd_arg_idx + 1] : NULL);
        } else if (strcmp(bcmd, "RMDIR") == 0 || strcmp(bcmd, "RD") == 0) {
            do_rmdir(cmd_arg_idx + 1 < argc ? argv[cmd_arg_idx + 1] : NULL);
        } else if (strcmp(bcmd, "DEL") == 0 || strcmp(bcmd, "RM") == 0) {
            do_delete(cmd_arg_idx + 1 < argc ? argv[cmd_arg_idx + 1] : NULL);
        } else if (strcmp(bcmd, "GET") == 0 || strcmp(bcmd, "COPY") == 0) {
            do_copy_to_cpm(cmd_arg_idx + 1 < argc ? argv[cmd_arg_idx + 1] : NULL,
                           cmd_arg_idx + 2 < argc ? argv[cmd_arg_idx + 2] : NULL);
        } else if (strcmp(bcmd, "PUT") == 0) {
            do_copy_from_cpm(cmd_arg_idx + 1 < argc ? argv[cmd_arg_idx + 1] : NULL,
                             cmd_arg_idx + 2 < argc ? argv[cmd_arg_idx + 2] : NULL);
        } else if (strcmp(bcmd, "TYPE") == 0 || strcmp(bcmd, "CAT") == 0) {
            do_type(cmd_arg_idx + 1 < argc ? argv[cmd_arg_idx + 1] : NULL);
        } else if (strcmp(bcmd, "WRITE") == 0) {
            do_write_test(cmd_arg_idx + 1 < argc ? argv[cmd_arg_idx + 1] : NULL,
                          cmd_arg_idx + 2 < argc ? argv[cmd_arg_idx + 2] : NULL);
        } else if (strcmp(bcmd, "SAVE") == 0) {
            save_config(target_unit);
        } else {
            printf("[-] Unknown batch command '%s'\n", bcmd);
        }
        f_unmount("");
        return 0;
    }

    /* Otherwise, show initial root directory and enter command shell */
    do_dir(NULL);
    command_shell();

    f_unmount("");
    printf("\nExiting FAT test harness. Back to CP/M.\n\n");
    return 0;
}
