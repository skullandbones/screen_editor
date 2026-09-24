#==============================================================================
# Makefile for FATFS.PRL - SE.COM FAT Filesystem Plugin
# Target: CP/M 3 Page-Relocatable 32KB Far RAM Executable
#==============================================================================

ZCC ?= ../../../../tools/z88dk/bin/zcc
MKPRL ?= ../../tools/mkprl.py
PYTHON ?= python3

TOOLS_BIN = $(abspath ../../../../tools/z88dk/bin)
TOOLS_CFG = $(abspath ../../../../tools/z88dk/lib/config)

ZCC_FLAGS = +cpm -Isource -SO3 --opt-code-size

SOURCES = source/ff.c source/diskio.c fat_plugin.c

all: FATFS.PRL FATTEST.COM

fat_100.bin: fat_entry.asm $(SOURCES) source/ffconf.h fat_plugin.h
	@export PATH="$(TOOLS_BIN):$$PATH"; \
	export ZCCCFG="$(TOOLS_CFG)"; \
	$(ZCC) $(ZCC_FLAGS) -zorg=0x0100 -crt0=fat_entry.asm $(SOURCES) -o $@

fat_200.bin: fat_entry_200.asm $(SOURCES) source/ffconf.h fat_plugin.h
	@export PATH="$(TOOLS_BIN):$$PATH"; \
	export ZCCCFG="$(TOOLS_CFG)"; \
	$(ZCC) $(ZCC_FLAGS) -zorg=0x0200 -crt0=fat_entry_200.asm $(SOURCES) -o $@

FATFS.PRL: fat_100.bin fat_200.bin mkfatprl.py
	$(PYTHON) mkfatprl.py fat_100.bin fat_200.bin $@

FATTEST.COM: fattest.c source/ff.c source/diskio.c source/ffconf.h
	@export PATH="$(TOOLS_BIN):$$PATH"; \
	export ZCCCFG="$(TOOLS_CFG)"; \
	$(ZCC) $(ZCC_FLAGS) source/ff.c source/diskio.c $< -o $@

clean:
	rm -f *.bin *.o *.PRL *.COM source/*.o

.PHONY: all clean
