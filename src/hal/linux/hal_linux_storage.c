/*==============================================================================
 * HAL_LINUX_STORAGE.C: Linux POSIX HAL - File I/O & Directory Enumeration
 *
 * Purpose:
 *   Implements standard POSIX file I/O operations (open, close, read, write)
 *   and directory scanning (opendir, readdir) for Linux file paths.
 *
 * Part of SE.COM / Linux Native Profile (x86_64 and AArch64)
 *============================================================================*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>
#include "../../include/config.h"
#include "../../include/hal.h"
#include "../../include/ui_browser.h"

int hal_storage_open(const char *path, void *handle)
{
    int fd;
    if (!path || !handle) return -1;
    fd = open(path, O_RDONLY);
    if (fd < 0) return -1;
    *(int *)handle = fd;
    return 0;
}

int hal_storage_make(const char *path, void *handle)
{
    int fd;
    if (!path || !handle) return -1;
    fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return -1;
    *(int *)handle = fd;
    return 0;
}

int hal_storage_close(void *handle)
{
    int fd;
    if (!handle) return -1;
    fd = *(int *)handle;
    if (fd >= 0) {
        close(fd);
        *(int *)handle = -1;
    }
    return 0;
}

int hal_storage_read_sec(void *handle, uint8_t *buf)
{
    int fd;
    ssize_t n;
    if (!handle || !buf) return -1;
    fd = *(int *)handle;
    n = read(fd, buf, 128);
    return (n == 128) ? 0 : 1;
}

int hal_storage_write_sec(void *handle, const uint8_t *buf)
{
    int fd;
    ssize_t n;
    if (!handle || !buf) return -1;
    fd = *(int *)handle;
    n = write(fd, buf, 128);
    return (n == 128) ? 0 : 1;
}

void hal_linux_scan_directory(const char *dir_path)
{
    DIR *d;
    struct dirent *dir;
    struct stat st;
    char path_buf[512];
    char clean_dir[512];
    size_t dlen;

    if (!dir_path || dir_path[0] == '\0') {
        dir_path = ".";
    }

    snprintf(clean_dir, sizeof(clean_dir), "%s", dir_path);
    dlen = strlen(clean_dir);
    while (dlen > 1 && clean_dir[dlen - 1] == '/') {
        clean_dir[--dlen] = '\0';
    }

    d = opendir(clean_dir);
    if (!d) {
        return;
    }

    while ((dir = readdir(d)) != NULL) {
        uint32_t size = 0;
        uint8_t is_dir = 0;

        /* Ignore hidden files and special entries */
        if (dir->d_name[0] == '.') {
            continue;
        }

        snprintf(path_buf, sizeof(path_buf), "%s/%s", clean_dir, dir->d_name);
        if (stat(path_buf, &st) == 0) {
            size = (uint32_t)st.st_size;
            if (S_ISDIR(st.st_mode)) {
                is_dir = 1;
            }
        }
        ui_browser_add_entry(dir->d_name, size, is_dir);
    }
    closedir(d);
}
