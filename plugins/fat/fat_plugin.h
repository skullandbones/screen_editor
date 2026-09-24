/*---------------------------------------------------------------------------/
/  FAT Filesystem Plugin Header for SE.COM
/---------------------------------------------------------------------------*/

#ifndef FAT_PLUGIN_H
#define FAT_PLUGIN_H

#include "ff.h"

/* Return status codes for SE.COM */
#define PLUG_RET_CLEAN     0  /* Document buffer not modified */
#define PLUG_RET_LINE_MOD  1  /* Active line modified */
#define PLUG_RET_DOC_MOD   2  /* Full document modified (triggers full redraw) */
#define PLUG_RET_ERROR     0xFF

/* Host API Functions implemented in fat_entry.asm */
void host_putc(char c);
char host_get_key(void);
unsigned char host_check_key(void);
unsigned int host_get_total_lines(void);
unsigned int host_checkout_line(unsigned int line_num, char *buf);
void host_commit_line(unsigned int line_num, const char *buf, unsigned int len);
void host_set_status_raw(const char *msg);

/* HBIOS disk unit access in diskio.c */
unsigned char get_hbios_disk_unit(void);
void set_hbios_disk_unit(unsigned char unit);

/* Plugin Entry Points */
int fat_plugin_run(void);
int fat_plugin_about(void);
int fat_plugin_config(void);

#endif /* FAT_PLUGIN_H */
