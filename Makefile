# Makefile for CP/M Full-Screen Editor (SE.COM)
# Compiler: z88dk (zcc targeting CP/M +cpm)

CC = zcc
CFLAGS = +cpm -O3 -Iinclude --list

TARGET = SE.COM

C_SRCS = src/main.c src/terminal.c src/buffer.c src/fileio.c
ASM_SRCS = src/hbios_far.asm

OBJS = $(C_SRCS:.c=.o)

.PHONY: all test clean

all: $(TARGET)

$(TARGET): $(C_SRCS) $(ASM_SRCS)
	@echo "==> Compiling and Linking $(TARGET) with z88dk..."
	$(CC) $(CFLAGS) -o $(TARGET) $(C_SRCS) $(ASM_SRCS)

test: $(TARGET)
	@echo "==> Running automated SE.COM integration tests..."
	python3 tests/test_editor_headless.py

clean:
	rm -f $(TARGET) src/*.o src/*.lst src/*.sym *.lis *.def
