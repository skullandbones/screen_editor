# Makefile for CP/M Full-Screen Editor (SE.COM)
# Assembler: z88dk-z80asm (Z80 Macro Assembler from z88dk)

WORKSPACE_ROOT ?= ../..
TOOLS_DIR ?= $(WORKSPACE_ROOT)/tools/romwbw_src/Tools/Linux
Z80ASM ?= $(WORKSPACE_ROOT)/tools/z88dk/bin/z88dk-z80asm
IMAGE ?= $(WORKSPACE_ROOT)/tools/romwbw_src/Binary/hd1k_combo.img
CPMCP ?= $(TOOLS_DIR)/cpmcp
CPMRM ?= $(TOOLS_DIR)/cpmrm

TARGET = SE.COM
ASM_SRC = src/se.asm

.PHONY: all plugins image test test-sanity test-conformity test-paging \
	test-config test-32k test-cpm3 test-plugins test-beautifier test-popup test-slots test-full clean

all: $(TARGET) plugins

$(TARGET): $(ASM_SRC)
	@echo "==> Assembling $(TARGET) with z88dk-z80asm..."
	$(Z80ASM) -b -m -s -o=$(TARGET) $(ASM_SRC)

plugins:
	@echo "==> Building plugins (ROT13.PRL, WORDCNT.OVL, BEAUTIFY.PRL, HALFPLUG.PRL, BIGPLUG.PRL)..."
	python3 plugins/build_plugins.py
	@echo "==> Building FAT plugin (FATFS.PRL, FATTEST.COM)..."
	$(MAKE) -C plugins/fat all
	cp -f plugins/fat/FATFS.PRL plugins/FATFS.PRL

image: $(TARGET) plugins
	@echo "==> Injecting $(TARGET) and plugins into modern hd1k combo image (Slices 0 & 3)..."
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:SE.COM 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) $(TARGET) 0:SE.COM
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:ROT13.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) plugins/ROT13.PRL 0:ROT13.PRL
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:WORDCNT.OVL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) plugins/WORDCNT.OVL 0:WORDCNT.OVL
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:BEAUTIFY.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) plugins/BEAUTIFY.PRL 0:BEAUTIFY.PRL
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:HALFPLUG.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) plugins/HALFPLUG.PRL 0:HALFPLUG.PRL
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:BIGPLUG.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) plugins/BIGPLUG.PRL 0:BIGPLUG.PRL
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:FATFS.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) plugins/fat/FATFS.PRL 0:FATFS.PRL
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:FATTEST.COM 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) plugins/fat/FATTEST.COM 0:FATTEST.COM
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:SE.COM 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) $(TARGET) 0:SE.COM
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:ROT13.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) plugins/ROT13.PRL 0:ROT13.PRL
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:WORDCNT.OVL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) plugins/WORDCNT.OVL 0:WORDCNT.OVL
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:BEAUTIFY.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) plugins/BEAUTIFY.PRL 0:BEAUTIFY.PRL
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:HALFPLUG.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) plugins/HALFPLUG.PRL 0:HALFPLUG.PRL
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:BIGPLUG.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) plugins/BIGPLUG.PRL 0:BIGPLUG.PRL
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:FATFS.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) plugins/fat/FATFS.PRL 0:FATFS.PRL
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:FATTEST.COM 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) plugins/fat/FATTEST.COM 0:FATTEST.COM

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

test-fatfs:
	@echo "==> Running FATFS plugin build and structure test suite..."
	python3 tests/test_fatfs_plugin.py

test-fatfs-slot: image
	@echo "==> Running FATFS 32KB plugin slot integration test suite..."
	python3 tests/test_fatfs_slot.py

test-full: test-config test-32k test-cpm3 test-conformity test-plugins test-beautifier test-popup test-slots test-fatfs test-fatfs-slot test-paging

clean:
	rm -f $(TARGET) *.lst src/*.lst *.obj src/*.obj *.lis *.def \
		*.map *.sym src/*.o src/*.map src/*.sym \
		plugins/*.PRL plugins/*.OVL plugins/*.bin plugins/*.lst plugins/*.sym
