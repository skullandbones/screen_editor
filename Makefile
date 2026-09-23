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
	test-config test-32k test-cpm3 test-plugins test-full clean

all: $(TARGET) plugins

$(TARGET): $(ASM_SRC)
	@echo "==> Assembling $(TARGET) with z88dk-z80asm..."
	$(Z80ASM) -b -m -s -o=$(TARGET) $(ASM_SRC)

plugins:
	@echo "==> Building reference plugins (ROT13.PRL, WORDCNT.OVL)..."
	python3 plugins/build_plugins.py

image: $(TARGET) plugins
	@echo "==> Injecting $(TARGET) and plugins into modern hd1k combo image (Slices 0 & 3)..."
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:SE.COM 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) $(TARGET) 0:SE.COM
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:ROT13.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) plugins/ROT13.PRL 0:ROT13.PRL
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:WORDCNT.OVL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) plugins/WORDCNT.OVL 0:WORDCNT.OVL
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:SE.COM 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) $(TARGET) 0:SE.COM
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:ROT13.PRL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) plugins/ROT13.PRL 0:ROT13.PRL
	$(CPMRM) -f wbw_hd1k_3 $(IMAGE) 0:WORDCNT.OVL 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_3 $(IMAGE) plugins/WORDCNT.OVL 0:WORDCNT.OVL

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

test-full: test-config test-32k test-cpm3 test-conformity test-plugins test-paging

clean:
	rm -f $(TARGET) *.lst src/*.lst *.obj src/*.obj *.lis *.def \
		*.map *.sym src/*.o src/*.map src/*.sym \
		plugins/*.PRL plugins/*.OVL plugins/*.bin plugins/*.lst plugins/*.sym
