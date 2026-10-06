#==============================================================================
# Makefile for FATFS.PRL - SE.COM FAT Filesystem Plugin
# Target: CP/M 3 Page-Relocatable 32KB Far RAM Executable
#==============================================================================

# Support absolute or relative TOOLS_DIR
ifeq ($(TOOLS_DIR),)
  ifneq ($(wildcard ../../../../../tools/z88dk),)
    TOOLS_DIR := ../../../../../tools
  else ifneq ($(wildcard ../../../../tools/z88dk),)
    TOOLS_DIR := ../../../../tools
  else ifneq ($(wildcard ../../tools/z88dk),)
    TOOLS_DIR := ../../tools
  else
    TOOLS_DIR := ../../../../tools
  endif
endif

override TOOLS_DIR := $(abspath $(TOOLS_DIR))

# If TOOLS_DIR was pointed directly at romwbw_src/Tools/Linux, navigate up
ifeq ($(wildcard $(TOOLS_DIR)/z88dk),)
  ifneq ($(wildcard $(TOOLS_DIR)/../../z88dk),)
    TOOLS_ROOT := $(abspath $(TOOLS_DIR)/../..)
  else
    TOOLS_ROOT := $(TOOLS_DIR)
  endif
else
  TOOLS_ROOT := $(TOOLS_DIR)
endif

TOOLS_BIN ?= $(TOOLS_ROOT)/z88dk/bin
TOOLS_CFG ?= $(TOOLS_ROOT)/z88dk/lib/config
ZCC ?= $(TOOLS_BIN)/zcc
MKPRL ?= ../../tools/mkprl.py
PYTHON ?= python3

ZCC_FLAGS = +cpm -Isource -SO3 --opt-code-size

SOURCES = source/ff.c source/diskio.c fat_plugin.c

all: FATFS.PRL FATTEST.COM VFSTEST.COM

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
	$(ZCC) $(ZCC_FLAGS) -DFATTEST_APP source/ff.c source/diskio.c $< -o $@

VFSTEST.COM: vfstest.c $(SOURCES) source/ffconf.h fat_plugin.h
	@export PATH="$(TOOLS_BIN):$$PATH"; \
	export ZCCCFG="$(TOOLS_CFG)"; \
	$(ZCC) $(ZCC_FLAGS) $(SOURCES) $< -o $@

clean:
	rm -f *.bin *.o *.PRL *.COM source/*.o

.PHONY: all clean
