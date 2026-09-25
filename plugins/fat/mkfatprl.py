#!/usr/bin/env python3
"""
mkfatprl.py - Dedicated PRL Packager for FATFS.PRL (32KB Far RAM Plugin)

Packages fat_100.bin and fat_200.bin into Digital Research CP/M 3
Page-Relocatable (.PRL) format with 256-byte header and relocation bitmap.
"""

import struct
import sys

CAP_FAR_EXEC   = 0x0002
CAP_DOC_MUTATE = 0x0004
CAP_MODAL_UI   = 0x0008
CAP_HAS_ABOUT  = 0x0010
CAP_HAS_CONFIG = 0x0020
CAP_SIZE_32K   = 0x00C0
CAP_HAS_VFS    = 0x0100


def build_reloc_bitmap(code_100: bytes, code_200: bytes) -> bytes:
    if len(code_100) != len(code_200):
        raise ValueError(
            f"Image lengths differ: {len(code_100)} vs {len(code_200)}"
        )

    prog_len = len(code_100)
    bitmap_len = (prog_len + 7) // 8
    bitmap = bytearray(bitmap_len)

    for i in range(prog_len):
        diff = (code_200[i] - code_100[i]) & 0xFF
        if diff == 1:
            byte_idx = i // 8
            bit_idx = 7 - (i % 8)
            bitmap[byte_idx] |= (1 << bit_idx)

    return bytes(bitmap)


def main():
    if len(sys.argv) < 4:
        print("Usage: mkfatprl.py <image_100> <image_200> <output_prl>")
        sys.exit(1)

    image_100_path = sys.argv[1]
    image_200_path = sys.argv[2]
    output_path = sys.argv[3]

    with open(image_100_path, "rb") as f:
        code_100 = f.read()

    with open(image_200_path, "rb") as f:
        code_200 = f.read()

    prog_size = len(code_100)
    if prog_size > 32768:
        raise ValueError(f"Code size {prog_size} exceeds 32KB slot limit")

    caps = (CAP_FAR_EXEC | CAP_DOC_MUTATE | CAP_MODAL_UI |
            CAP_HAS_ABOUT | CAP_HAS_CONFIG | CAP_SIZE_32K | CAP_HAS_VFS)

    # 256-byte CP/M 3 PRL Header
    header = bytearray(256)
    struct.pack_into("<H", header, 0x01, prog_size)  # PROG_SIZE
    struct.pack_into("<H", header, 0x04, 0x0000)     # BSS_SIZE
    struct.pack_into("<H", header, 0x07, 0x0000)     # LOAD_ADDR (0 for PRL)
    struct.pack_into("<H", header, 0x0A, 0x0000)     # BIOS_LINK

    name_bytes = b"FATFS\x00"
    header[0x0C:0x0C+len(name_bytes)] = name_bytes

    struct.pack_into("<H", header, 0x1C, caps)       # CAPABILITIES

    bitmap = build_reloc_bitmap(code_100, code_200)

    result = bytes(header) + code_100 + bitmap

    with open(output_path, "wb") as f:
        f.write(result)

    reloc_count = sum(bin(b).count("1") for b in bitmap)
    print(f"[+] Successfully wrote {len(result)} bytes to {output_path}")
    print(f"    Name: FATFS, ProgSize: {prog_size}B, Caps: 0x{caps:04X}, "
          f"Relocs: {reloc_count}")


if __name__ == "__main__":
    main()
