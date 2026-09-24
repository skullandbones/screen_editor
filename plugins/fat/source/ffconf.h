/*---------------------------------------------------------------------------/
/  FatFs Configuration for SE.COM FAT Plugin (Z80 / RomWBW CP/M)
/---------------------------------------------------------------------------*/

#ifndef FFCONF_DEF
#define FFCONF_DEF 80286

/* Function Configurations */
#define FF_FS_READONLY    0   /* 0: Read/Write enabled */
#ifdef FATTEST_APP
#define FF_FS_MINIMIZE    0   /* 0: Full API for test harness: f_stat, f_mkdir, f_unlink, f_rename, f_truncate */
#else
#define FF_FS_MINIMIZE    1   /* 1: Removes f_stat, f_mkdir, etc. to fit in 32KB Far RAM slot */
#endif
#define FF_USE_FIND       0   /* Disable filtered find */
#define FF_USE_MKFS       0   /* Disable format (not needed) */
#define FF_USE_FASTSEEK   0
#define FF_USE_EXPAND     0
#define FF_USE_CHMOD      0
#define FF_USE_LABEL      0
#define FF_USE_FORWARD    0
#define FF_USE_STRFUNC    0   /* Disable strfuncs; we do our own line tokenizing */
#define FF_PRINT_LLI      0
#define FF_PRINT_FLOAT    0
#define FF_STRF_ENCODE    0

/* Locale and Namespace */
#define FF_CODE_PAGE      437 /* U.S. OEM Code Page */
#define FF_USE_LFN        0   /* 0: 8.3 Short File Names (leanest footprint) */
#define FF_MAX_LFN        255
#define FF_LFN_UNICODE    0
#define FF_LFN_BUF        255
#define FF_SFN_BUF        12
#ifdef FATTEST_APP
#define FF_FS_RPATH       2   /* 2: Enable f_chdir, f_chdrive, f_getcwd in test harness */
#else
#define FF_FS_RPATH       0   /* 0: Full paths from root */
#endif

/* Drive/Volume Configurations */
#define FF_VOLUMES        1   /* Single SD card volume */
#define FF_STR_VOLUME_ID  0
#define FF_MULTI_PARTITION 1  /* 1: Support MBR partitions on SD card */
#define FF_MIN_SS         512 /* Standard 512-byte sector size */
#define FF_MAX_SS         512
#define FF_LBA64          0   /* Disable 64-bit LBA */
#define FF_MIN_GPT        0x10000000
#define FF_USE_TRIM       0

/* System Configurations */
#define FF_FS_TINY        1   /* 1: Tiny buffer mode (FIL shares sector buffer in FATFS) */
#define FF_FS_EXFAT       0   /* 0: Disable exFAT */
#define FF_FS_NORTC       1   /* 1: Fixed timestamp, no external RTC call needed */
#define FF_NORTC_MON      9
#define FF_NORTC_MDAY     24
#define FF_NORTC_YEAR     2026
#define FF_FS_NOFSINFO    0
#define FF_FS_LOCK        0
#define FF_FS_REENTRANT   0
#define FF_FS_TIMEOUT     1000

#endif /* FFCONF_DEF */
