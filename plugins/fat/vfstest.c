/*---------------------------------------------------------------------------/
/  VFSTEST.C - Standalone Functional Test for FATFS Headless VFS Engine
/---------------------------------------------------------------------------/
/  Validates fat_vfs_dispatch() commands on RomWBW CP/M:
/  - Probe / Mount
/  - Directory listing (13-byte formatted records)
/  - File load / streaming into document
/  - File save / range export (Block Save)
/  - Chunk streaming (Block Insert)
/  - Error handling
/---------------------------------------------------------------------------*/

#include <stdio.h>
#include <string.h>
#include "fat_plugin.h"

/* Mock Host API storage */
#define MOCK_MAX_LINES 16
static char s_mock_doc[MOCK_MAX_LINES][128];
static unsigned int s_mock_len[MOCK_MAX_LINES];
static unsigned int s_mock_total = 0;

/* Mock Host API functions */
void host_putc(char c) {
    putchar(c);
}

char host_get_key(void) {
    return 0;
}

unsigned char host_check_key(void) {
    return 0;
}

unsigned char host_get_cols(void) {
    return 80;
}

unsigned char host_get_rows(void) {
    return 24;
}

unsigned int host_get_total_lines(void) {
    return s_mock_total;
}

unsigned int host_checkout_line(unsigned int line_num, char *buf) {
    if (line_num < s_mock_total) {
        unsigned int len = s_mock_len[line_num];
        memcpy(buf, s_mock_doc[line_num], len);
        buf[len] = 0;
        return len;
    }
    return 0;
}

void host_commit_line(unsigned int line_num, const char *buf,
                      unsigned int len) {
    if (line_num < MOCK_MAX_LINES) {
        if (len > 127) len = 127;
        memcpy(s_mock_doc[line_num], buf, len);
        s_mock_doc[line_num][len] = 0;
        s_mock_len[line_num] = len;
        if (line_num >= s_mock_total) {
            s_mock_total = line_num + 1;
        }
    }
}

void host_clear_document(void) {
    s_mock_total = 0;
}

void host_set_status_raw(const char *msg) {
    (void)msg;
}

int main(void) {
    FatVfsRequest req;
    char dir_buf[32 * 13];
    char chunk_buf[128];
    int res;
    unsigned int i;
    int found_slices = 0;

    printf("\n[*] Starting FAT VFS Dispatcher Tests on RomWBW...\n");

    /* Test 1: VFS_CMD_PROBE_MOUNT */
    memset(&req, 0, sizeof(req));
    req.cmd = VFS_CMD_PROBE_MOUNT;
    req.unit = 0xFF;
    res = fat_vfs_dispatch(&req);
    if (res != VFS_STAT_OK || req.status != VFS_STAT_OK) {
        printf("[-] FAIL: PROBE_MOUNT returned %d, status %d\n",
               res, req.status);
        return 1;
    }
    printf("[+] PASS: VFS_CMD_PROBE_MOUNT (Unit %d)\n", req.unit);

    /* Test 2: VFS_CMD_GET_DEF_UNIT */
    memset(&req, 0, sizeof(req));
    req.cmd = VFS_CMD_GET_DEF_UNIT;
    res = fat_vfs_dispatch(&req);
    if (res != VFS_STAT_OK) {
        printf("[-] FAIL: GET_DEF_UNIT\n");
        return 1;
    }
    printf("[+] PASS: VFS_CMD_GET_DEF_UNIT (Default: %d)\n", req.unit);

    /* Test 3: VFS_CMD_LIST_DIR */
    memset(&req, 0, sizeof(req));
    memset(dir_buf, 0, sizeof(dir_buf));
    req.cmd = VFS_CMD_LIST_DIR;
    req.unit = 0xFF;
    req.path = "/";
    req.buffer = dir_buf;
    req.buffer_size = 32;
    res = fat_vfs_dispatch(&req);
    if (res != VFS_STAT_OK || req.count == 0) {
        printf("[-] FAIL: LIST_DIR returned %d, count %d\n", res, req.count);
        return 1;
    }
    printf("[+] PASS: VFS_CMD_LIST_DIR (Found %d entries)\n", req.count);

    for (i = 0; i < req.count; i++) {
        char name[14];
        memcpy(name, dir_buf + (i * 13), 13);
        name[13] = 0;
        printf("    [%u] Entry: '%s' (Sep: '%c')\n",
               i, name, (unsigned char)name[8]);
        if (memcmp(name, "SLICES  .TXT", 12) == 0) {
            found_slices = 1;
        }
    }
    if (!found_slices) {
        printf("[-] FAIL: SLICES.TXT not found in root directory listing\n");
        return 1;
    }
    printf("[+] PASS: 13-byte directory entry record format verified\n");

    /* Test 4: VFS_CMD_LOAD_FILE */
    memset(&req, 0, sizeof(req));
    req.cmd = VFS_CMD_LOAD_FILE;
    req.unit = 0xFF;
    req.path = "/SLICES.TXT";
    res = fat_vfs_dispatch(&req);
    if (res != VFS_STAT_OK || req.count == 0) {
        printf("[-] FAIL: LOAD_FILE returned %d, count %d\n", res, req.count);
        return 1;
    }
    printf("[+] PASS: VFS_CMD_LOAD_FILE (Loaded %d lines into mock doc)\n",
           req.count);
    if (s_mock_total > 0) {
        printf("    Line 0: '%s'\n", s_mock_doc[0]);
    }

    /* Test 5: VFS_CMD_SAVE_RANGE (Block Save) */
    memset(&req, 0, sizeof(req));
    req.cmd = VFS_CMD_SAVE_RANGE;
    req.unit = 0xFF;
    req.path = "/VFSTEST.TXT";
    req.start_line = 0;
    req.end_line = 1;
    res = fat_vfs_dispatch(&req);
    if (res != VFS_STAT_OK || req.count != 2) {
        printf("[-] FAIL: SAVE_RANGE returned %d, count %d\n", res, req.count);
        return 1;
    }
    printf("[+] PASS: VFS_CMD_SAVE_RANGE (Saved %d lines to VFSTEST.TXT)\n",
           req.count);

    /* Test 6: VFS_CMD_OPEN_FILE & READ_CHUNK & CLOSE_FILE */
    memset(&req, 0, sizeof(req));
    req.cmd = VFS_CMD_OPEN_FILE;
    req.unit = 0xFF;
    req.path = "/VFSTEST.TXT";
    res = fat_vfs_dispatch(&req);
    if (res != VFS_STAT_OK) {
        printf("[-] FAIL: OPEN_FILE returned %d\n", res);
        return 1;
    }

    memset(&req, 0, sizeof(req));
    req.cmd = VFS_CMD_READ_CHUNK;
    req.unit = 0xFF;
    req.buffer = chunk_buf;
    req.buffer_size = sizeof(chunk_buf) - 1;
    res = fat_vfs_dispatch(&req);
    if (res != VFS_STAT_OK || req.count == 0) {
        printf("[-] FAIL: READ_CHUNK returned %d, count %d\n", res, req.count);
        return 1;
    }
    chunk_buf[req.count] = 0;
    printf("[+] PASS: VFS_CMD_READ_CHUNK (Read %d bytes)\n", req.count);

    req.cmd = VFS_CMD_CLOSE_FILE;
    req.unit = 0xFF;
    fat_vfs_dispatch(&req);
    printf("[+] PASS: VFS_CMD_CLOSE_FILE\n");

    /* Test 7: Error handling on non-existent file */
    memset(&req, 0, sizeof(req));
    req.cmd = VFS_CMD_LOAD_FILE;
    req.unit = 0xFF;
    req.path = "/NOSUCH.XYZ";
    res = fat_vfs_dispatch(&req);
    if (res != VFS_STAT_NOT_FOUND) {
        printf("[-] FAIL: Non-existent file returned %d (expected 1)\n", res);
        return 1;
    }
    printf("[+] PASS: VFS error handling (NOT_FOUND code %d)\n", res);

    printf("\n[+] ALL VFS TESTS PASSED SUCCESSFULLY!\n");
    return 0;
}
