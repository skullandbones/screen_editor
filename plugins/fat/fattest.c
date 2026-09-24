/*---------------------------------------------------------------------------/
/  FATTEST.COM - Standalone CP/M Test Harness for RomWBW FAT Filesystem
/---------------------------------------------------------------------------/
/  Target: CP/M 2.2 / CP/M 3.0 (SC131, RC2014, and RomWBW Z80 platforms)
/  Runs directly from the CP/M command line (0100H) without SE.COM.
/---------------------------------------------------------------------------*/

#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include "ff.h"
#include "diskio.h"

/* HBIOS unit access in diskio.c */
extern unsigned char get_hbios_disk_unit(void);
extern void set_hbios_disk_unit(unsigned char unit);

static FATFS s_fs;
static FIL   s_file;
static DIR   s_dir;
static FILINFO s_fno;
static char  s_iobuf[512];

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
    case FR_DENIED:              return "FR_DENIED (Access denied)";
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
/ Directory Listing
/---------------------------------------------------------------------------*/

static void do_dir(const char *path) {
    FRESULT fr;
    int count = 0;
    unsigned long total_bytes = 0;

    if (!path || *path == 0) path = "/";

    printf("\nDirectory listing for '%s':\n", path);
    printf("----------------------------------------------------\n");

    fr = f_opendir(&s_dir, path);
    if (fr != FR_OK) {
        printf("[-] f_opendir failed: %s\n", fresult_str(fr));
        return;
    }

    while (1) {
        fr = f_readdir(&s_dir, &s_fno);
        if (fr != FR_OK || s_fno.fname[0] == 0) break;
        if (s_fno.fname[0] == '.') continue;

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
    printf("  DIR [path]           - List files in directory (default '/')\n");
    printf("  TYPE <file>          - Display contents of text file\n");
    printf("  WRITE [file] [text]  - Write test file and verify readback\n");
    printf("  UNIT <0-7>           - Switch RomWBW HBIOS disk unit and remount\n");
    printf("  INFO                 - Display filesystem volume info\n");
    printf("  HELP                 - Display this command list\n");
    printf("  QUIT                 - Exit to CP/M prompt\n");
}

/*---------------------------------------------------------------------------/
/ Interactive Command Shell
/---------------------------------------------------------------------------*/

static void command_shell(void) {
    char line[80];

    print_help();

    while (1) {
        char cmd[16];
        char arg1[32];
        char arg2[48];
        int n;

        printf("\nFAT[%u]> ", (unsigned int)get_hbios_disk_unit());
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
            do_dir(arg1);
        } else if (strcmp(cmd, "TYPE") == 0 || strcmp(cmd, "T") == 0 || strcmp(cmd, "CAT") == 0) {
            do_type(arg1);
        } else if (strcmp(cmd, "WRITE") == 0 || strcmp(cmd, "W") == 0) {
            do_write_test(arg1[0] ? arg1 : NULL, arg2[0] ? arg2 : NULL);
        } else if (strcmp(cmd, "UNIT") == 0 || strcmp(cmd, "U") == 0) {
            if (arg1[0] >= '0' && arg1[0] <= '7') {
                mount_unit((unsigned char)(arg1[0] - '0'));
            } else {
                printf("Usage: UNIT <0-7>\n");
            }
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
    unsigned char target_unit = 1; /* Default: SC131 SD Card (Unit 1) */

    printf("\n====================================================\n");
    printf("  RomWBW FAT Filesystem Test Harness v1.0.0 (SC131)\n");
    printf("  Direct HBIOS RST 08H + Elm-Chan FatFs R0.15 Engine\n");
    printf("====================================================\n");

    /* Parse optional initial unit from command tail */
    if (argc > 1 && argv[1][0] >= '0' && argv[1][0] <= '7' && argv[1][1] == 0) {
        target_unit = (unsigned char)(argv[1][0] - '0');
    }

    if (mount_unit(target_unit)) {
        /* If batch command provided, run it directly */
        if (argc > 2) {
            char bcmd[16];
            int i;
            for (i = 0; i < 15 && argv[2][i]; i++) {
                bcmd[i] = (char)toupper((unsigned char)argv[2][i]);
            }
            bcmd[i] = 0;

            if (strcmp(bcmd, "DIR") == 0) {
                do_dir(argc > 3 ? argv[3] : "/");
            } else if (strcmp(bcmd, "TYPE") == 0 && argc > 3) {
                do_type(argv[3]);
            } else if (strcmp(bcmd, "WRITE") == 0) {
                do_write_test(argc > 3 ? argv[3] : NULL, argc > 4 ? argv[4] : NULL);
            }
            f_unmount("");
            return 0;
        }

        /* Otherwise, show initial root directory and enter command shell */
        do_dir("/");
        command_shell();
    } else {
        printf("\n[-] Could not mount default Unit %u.\n", (unsigned int)target_unit);
        printf("Entering interactive shell. Use 'UNIT <0-7>' to try another disk unit.\n");
        command_shell();
    }

    f_unmount("");
    printf("\nExiting FAT test harness. Back to CP/M.\n\n");
    return 0;
}
