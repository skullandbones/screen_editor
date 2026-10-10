/*==============================================================================
 * HAL_CPM_STORAGE.C: CP/M Hardware Abstraction Layer - Storage & Sector I/O
 *
 * Purpose:
 *   Implements 128-byte sector file operations (open, make, close, read, write)
 *   for CP/M file systems.
 *   Strictly adheres to docs/UI_UX_DESIGN.md.
 *
 * Part of SE.COM / CP/M C Semantic Equivalent Profile (SEC.COM)
 *============================================================================*/

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "../../include/config.h"
#include "../../include/hal.h"

int hal_storage_open(const char *path, void *handle)
{
    FILE *fp;
    if (!path || !handle) {
        return -1;
    }
    fp = fopen(path, "rb");
    if (!fp) {
        return -1;
    }
    *(FILE **)handle = fp;
    return 0;
}

int hal_storage_make(const char *path, void *handle)
{
    FILE *fp;
    if (!path || !handle) {
        return -1;
    }
    fp = fopen(path, "wb+");
    if (!fp) {
        return -1;
    }
    *(FILE **)handle = fp;
    return 0;
}

int hal_storage_close(void *handle)
{
    FILE *fp;
    if (!handle) {
        return -1;
    }
    fp = *(FILE **)handle;
    if (fp) {
        fclose(fp);
        *(FILE **)handle = NULL;
    }
    return 0;
}

int hal_storage_read_sec(void *handle, uint8_t *buf)
{
    FILE *fp;
    size_t n;
    if (!handle || !buf) {
        return -1;
    }
    fp = *(FILE **)handle;
    if (!fp) {
        return -1;
    }
    n = fread(buf, 1, 128, fp);
    return (n == 128) ? 0 : 1;
}

int hal_storage_write_sec(void *handle, const uint8_t *buf)
{
    FILE *fp;
    size_t n;
    if (!handle || !buf) {
        return -1;
    }
    fp = *(FILE **)handle;
    if (!fp) {
        return -1;
    }
    n = fwrite(buf, 1, 128, fp);
    return (n == 128) ? 0 : 1;
}
