# Makefile for CP/M Full-Screen Editor (SE.COM)
# Assembler: z88dk-z80asm (Z80 Macro Assembler from z88dk)

# Support absolute or relative tools directory (TOOLS_DIR or TOOL_DIR).
# If neither is set, fall back to $(WORKSPACE_ROOT)/tools.
WORKSPACE_ROOT ?= ../..

ifeq ($(TOOLS_DIR),)
  TOOLS_DIR := $(TOOL_DIR)
endif
ifeq ($(TOOLS_DIR),)
  TOOLS_DIR := $(WORKSPACE_ROOT)/tools
endif

# Convert TOOLS_DIR to an absolute path relative to current directory
override TOOLS_DIR := $(abspath $(TOOLS_DIR))
override TOOL_DIR := $(TOOLS_DIR)

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

export TOOLS_DIR := $(TOOLS_ROOT)
export TOOL_DIR := $(TOOLS_ROOT)

ROMWBW_TOOLS ?= $(TOOLS_ROOT)/romwbw_src/Tools/Linux
Z80ASM ?= $(TOOLS_ROOT)/z88dk/bin/z88dk-z80asm
GOLDEN_IMAGE ?= $(TOOLS_ROOT)/romwbw_src/Binary/hd1k_combo.img
IMAGE_DIR ?= disks
IMAGE ?= $(IMAGE_DIR)/hd1k_combo.img
export DISKDEFS ?= $(TOOLS_ROOT)/romwbw_src/Tools/cpmtools/diskdefs
CPMCP ?= $(ROMWBW_TOOLS)/cpmcp
CPMRM ?= $(ROMWBW_TOOLS)/cpmrm

TARGET = SE.COM
ASM_SRC = src/se.asm

.PHONY: all plugins image init-image clean-image check-tpa check-plugins \
	check-lines test test-sanity test-conformity test-paging test-config \
	test-32k test-cpm3 test-plugins test-beautifier test-popup test-slots \
	test-plugin-cfg test-fatfs test-fatfs-slot test-fatfs-vfs \
	test-fatfs-hook test-full clean

all: $(TARGET) plugins

$(TARGET): $(ASM_SRC)
	@echo "==> Assembling $(TARGET) with z88dk-z80asm..."
	$(Z80ASM) -b -m -s -o=$(TARGET) $(ASM_SRC)

check-tpa: $(TARGET)
	@echo "==> Checking $(TARGET) memory footprint against TPA..."
	python3 check_tpa.py $(TARGET)

check-plugins:
	@echo "==> Checking plugin binaries and ABI conformance..."
	python3 check_plugin.py --all

check-lines:
	@echo "==> Checking for lines exceeding 80 characters..."
	python3 check_line_length.py

plugins:
	@echo "==> Building plugins (4K, 8K, 16K, 32K)..."
	TOOLS_DIR="$(TOOLS_ROOT)" TOOL_DIR="$(TOOLS_ROOT)" \
		python3 plugins/build_plugins.py
	@echo "==> Building FAT plugin (FATFS.PRL, FATTEST.COM)..."
	$(MAKE) -C plugins/fat TOOLS_DIR="$(TOOLS_ROOT)" \
		TOOL_DIR="$(TOOLS_ROOT)" all
	cp -f plugins/fat/FATFS.PRL plugins/FATFS.PRL

$(IMAGE):
	@mkdir -p $(IMAGE_DIR)
	@echo "==> Initializing workspace-isolated disk image from golden image..."
	cp --sparse=always $(GOLDEN_IMAGE) $(IMAGE)
	chmod 644 $(IMAGE)

init-image: $(IMAGE)

clean-image:
	rm -rf $(IMAGE_DIR)

image: $(IMAGE) $(TARGET) plugins
	@echo "==> Injecting $(TARGET) and plugins into hd1k image (0 & 3)..."
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:SE.COM 0:se.com 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) $(TARGET) 0:SE.COM
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:PLUGIN.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) plugins/PLUGIN.PRL 0:PLUGIN.PRL
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:PLUGIN.CFG 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) plugins/PLUGIN.CFG 0:PLUGIN.CFG
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:ROT13.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) plugins/ROT13.PRL 0:ROT13.PRL
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:WORDCNT.OVL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) plugins/WORDCNT.OVL 0:WORDCNT.OVL
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:BEAUTIFY.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) plugins/BEAUTIFY.PRL 0:BEAUTIFY.PRL
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:MIDPLUG.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) plugins/MIDPLUG.PRL 0:MIDPLUG.PRL
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:HALFPLUG.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) plugins/HALFPLUG.PRL 0:HALFPLUG.PRL
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:BIGPLUG.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) plugins/BIGPLUG.PRL 0:BIGPLUG.PRL
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:FATFS.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) plugins/fat/FATFS.PRL 0:FATFS.PRL
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:FATTEST.COM 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) plugins/fat/FATTEST.COM 0:FATTEST.COM
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:VFSTEST.COM 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) plugins/fat/VFSTEST.COM 0:VFSTEST.COM
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:HIBERN.OVL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) plugins/HIBERN.OVL 0:HIBERN.OVL
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:HELP.OVL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) plugins/HELP.OVL 0:HELP.OVL
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:2.TXT 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) 2.TXT 0:2.TXT
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:SE.COM 0:se.com 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) $(TARGET) 0:SE.COM
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:PLUGIN.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) plugins/PLUGIN.PRL 0:PLUGIN.PRL
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:PLUGIN.CFG 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) plugins/PLUGIN.CFG 0:PLUGIN.CFG
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:ROT13.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) plugins/ROT13.PRL 0:ROT13.PRL
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:WORDCNT.OVL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) plugins/WORDCNT.OVL 0:WORDCNT.OVL
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:BEAUTIFY.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) plugins/BEAUTIFY.PRL 0:BEAUTIFY.PRL
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:MIDPLUG.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) plugins/MIDPLUG.PRL 0:MIDPLUG.PRL
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:HALFPLUG.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) plugins/HALFPLUG.PRL 0:HALFPLUG.PRL
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:BIGPLUG.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) plugins/BIGPLUG.PRL 0:BIGPLUG.PRL
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:FATFS.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) plugins/fat/FATFS.PRL 0:FATFS.PRL
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:FATTEST.COM 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) plugins/fat/FATTEST.COM 0:FATTEST.COM
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:VFSTEST.COM 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) plugins/fat/VFSTEST.COM 0:VFSTEST.COM
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:HIBERN.OVL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) plugins/HIBERN.OVL 0:HIBERN.OVL
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:HELP.OVL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) plugins/HELP.OVL 0:HELP.OVL
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:2.TXT 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) 2.TXT 0:2.TXT

test: test-sanity

test-sanity: image
	@echo "==> Running fast SE.COM sanity test suite..."
	python3 tests/test_sanity.py

test-conformity: image
	@echo "==> Running full SE.COM conformity regression test suite..."
	python3 tests/test_editor_headless.py

test-paging: image
	@echo "==> Running SE.COM large file paging test suite (3,400 lines)..."
	python3 tests/test_large_file_paging.py

test-config: image
	@echo "==> Running SE.CFG configuration file test suite..."
	python3 tests/test_config_file.py

test-32k: image
	@echo "==> Running 32K document lines test suite..."
	python3 tests/test_32k_lines.py

test-cpm3: image
	@echo "==> Running CP/M 3.1 Z80 emulator test suite..."
	python3 tests/test_cpm3.py

test-plugins: image
	@echo "==> Running CP/M 3 PRL & OVL plugin subsystem test suite..."
	python3 tests/test_plugin_subsystem.py

test-beautifier: image
	@echo "==> Running SE.COM Z80 beautifier plugin test suite..."
	python3 tests/test_beautifier_cpm.py

test-popup: image
	@echo "==> Running SE.COM context-aware plugin popup test suite..."
	python3 tests/test_ctrl_p_popup.py

test-slots: image
	@echo "==> Running SE.COM modular plugin slots (4K/16K/32K) test suite..."
	python3 tests/test_plugin_slots.py

test-plugin-cfg: image
	@echo "==> Running SE.COM PLUGIN.CFG save & autoload test suite..."
	python3 tests/test_plugin_cfg_save_reload.py

test-fatfs:
	@echo "==> Running FATFS plugin build and structure test suite..."
	python3 tests/test_fatfs_plugin.py

test-fatfs-slot: image
	@echo "==> Running FATFS 32KB plugin slot integration test suite..."
	python3 tests/test_fatfs_slot.py

test-fatfs-vfs: image
	@echo "==> Running FATFS headless VFS integration test suite..."
	python3 tests/test_fatfs_vfs.py

test-fatfs-hook: image
	@echo "==> Running FATFS Phase 2 VFS hook & status bar test suite..."
	python3 tests/test_fatfs_vfs_hook.py

test-monkey: image
	@echo "==> Running SE.COM drunken monkey chaos test suite..."
	python3 tests/test_drunken_monkey.py --steps $(or $(STEPS),50)

view-monkey:
	@echo "==> Launching interactive drunken monkey session viewer..."
	python3 tools/monkey_viewer.py \
		$(or $(SESSION),tests/monkey_session_sample.json)

test-full: test-config test-32k test-cpm3 test-conformity test-plugins \
	test-beautifier test-popup test-slots test-plugin-cfg test-fatfs \
	test-fatfs-slot test-fatfs-vfs test-fatfs-hook test-paging test-monkey

clean:
	rm -f $(TARGET) *.lst src/*.lst *.obj src/*.obj *.lis *.def \
		*.map *.sym src/*.o src/*.map src/*.sym \
		plugins/*.PRL plugins/*.OVL plugins/*.bin plugins/*.lst plugins/*.sym
