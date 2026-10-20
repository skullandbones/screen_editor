/*==============================================================================
 * HAL_CPM_STORAGE.C: CP/M Hardware Abstraction Layer - Storage & Sector I/O
 *
 * Purpose:
 *   Implements 128-byte sector file operations (open, make, close, read, write)
 *   for CP/M file systems using native BDOS calls, eliminating stdio fopen.
 *   Strictly adheres to docs/UI_UX_DESIGN.md.
 *
 * Part of SE.COM / CP/M C Semantic Equivalent Profile (SEC.COM)
 *============================================================================*/

#include <stdint.h>
#include <string.h>
#include <cpm.h>
#include "../../include/config.h"
#include "../../include/hal.h"
#include "../../include/file_io.h"

#ifndef __CPM__
int hal_storage_open(const char *path, void *handle)
{
    cpm_fcb_t *fcb = (cpm_fcb_t *)handle;
    if (!path || !handle) {
        return -1;
    }
    file_populate_fcb(path, fcb);
    return ((uint8_t)bdos(15, (int)fcb) == 0xFF) ? -1 : 0;
}

int hal_storage_make(const char *path, void *handle)
{
    cpm_fcb_t *fcb = (cpm_fcb_t *)handle;
    if (!path || !handle) {
        return -1;
    }
    file_populate_fcb(path, fcb);
    bdos(19, (int)fcb);
    return ((uint8_t)bdos(22, (int)fcb) == 0xFF) ? -1 : 0;
}

int hal_storage_close(void *handle)
{
    cpm_fcb_t *fcb = (cpm_fcb_t *)handle;
    if (!handle) {
        return -1;
    }
    bdos(16, (int)fcb);
    return 0;
}

int hal_storage_read_sec(void *handle, uint8_t *buf)
{
    cpm_fcb_t *fcb = (cpm_fcb_t *)handle;
    if (!handle || !buf) {
        return -1;
    }
    bdos(26, (int)buf);
    return (bdos(20, (int)fcb) == 0) ? 0 : 1;
}

int hal_storage_write_sec(void *handle, const uint8_t *buf)
{
    cpm_fcb_t *fcb = (cpm_fcb_t *)handle;
    if (!handle || !buf) {
        return -1;
    }
    bdos(26, (int)buf);
    return (bdos(21, (int)fcb) == 0) ? 0 : 1;
}
#endif
