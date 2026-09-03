# Makefile for CP/M Full-Screen Editor (SE.COM)
# Assembler: uz80as (micro Z80 assembler from RomWBW)

WORKSPACE_ROOT ?= ../..
TOOLS_DIR ?= $(WORKSPACE_ROOT)/tools/romwbw_src/Tools/Linux
UZ80AS ?= $(TOOLS_DIR)/uz80as
IMAGE ?= $(WORKSPACE_ROOT)/tools/romwbw_src/Binary/hd1k_combo.img
CPMCP ?= $(TOOLS_DIR)/cpmcp
CPMRM ?= $(TOOLS_DIR)/cpmrm

TARGET = SE.COM
ASM_SRC = src/se.asm

.PHONY: all image test test-sanity test-conformity test-full clean

all: $(TARGET)

$(TARGET): $(ASM_SRC)
	@echo "==> Assembling $(TARGET) with uz80as..."
	$(UZ80AS) -q $(ASM_SRC) $(TARGET)

image: $(TARGET)
	@echo "==> Injecting $(TARGET) into modern hd1k combo image (Slice 0)..."
	$(CPMRM) -f wbw_hd1k_0 $(IMAGE) 0:SE.COM 2>/dev/null || true
	$(CPMCP) -f wbw_hd1k_0 $(IMAGE) $(TARGET) 0:SE.COM

test: test-sanity

test-sanity: image
	@echo "==> Running fast SE.COM sanity test suite..."
	python3 tests/test_sanity.py

test-conformity: image
	@echo "==> Running full SE.COM conformity regression test suite..."
	python3 tests/test_editor_headless.py

test-full: test-conformity

clean:
	rm -f $(TARGET) *.lst src/*.lst *.obj src/*.obj *.lis *.def
