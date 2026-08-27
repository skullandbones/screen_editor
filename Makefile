# Makefile for CP/M Screen Editor (Z80 / RomWBW)

UZ80AS = ../../tools/romwbw_src/Tools/Linux/uz80as
TARGET = SE.COM

SOURCES = editor.asm

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SOURCES)
	@echo "==> Assembling $(TARGET)..."
	$(UZ80AS) -q editor.asm $(TARGET)

clean:
	rm -f $(TARGET) *.lst *.obj *.tmp
