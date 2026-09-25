#!/usr/bin/env python3
"""
mkprl.py - Digital Research CP/M 3 PRL (Page-Relocatable) and OVL (Overlay) Packager.

Wraps assembled Z80 binaries into standard CP/M 3 PRL and OVL files with a 256-byte
header and relocation bitmap.

Specification (Digital Research CP/M Plus / CP/M 3 & GSX):
  Header (256 bytes):
    00h:        00h
    01h..02h:   PROG_SIZE (16-bit word, little-endian: Code + Data size in bytes)
    03h:        00h
    04h..05h:   BSS_SIZE (16-bit word, little-endian: Uninitialized BSS size)
    06h:        00h
    07h..08h:   LOAD_ADDR (16-bit word: 0000h for PRL, target address for OVL)
    09h:        00h
    0Ah..0Bh:   BIOS_LINK (16-bit word: 0000h)
    0Ch..1Bh:   NAME (16 bytes: ASCII uppercase name, null padded)
    1Ch..1Dh:   CAPABILITIES (16-bit word: bitflags)
                  bit 0 (0x0001): TPA_EXEC   (Can run in TPA slot)
                  bit 1 (0x0002): FAR_EXEC   (Can run directly in Far RAM)
                  bit 2 (0x0004): DOC_MUTATE (Modifies document lines)
                  bit 3 (0x0008): MODAL_UI   (Draws modal dialog/screen)
    1Eh..1Fh:   RESERVED (0000h)
    20h..FFh:   Zero padding to 256 bytes
  Body:
    Code and Initialized Data (assembled origin 0100h)
  Relocation Bitmap (for PRL files only):
    (PROG_SIZE + 7) // 8 bytes.
    Bit 7 of byte 0 = first byte of code image, bit 0 = eighth byte.
    A bit set to 1 indicates an address high-byte that needs relocation bias:
      byte += (target_page - 1)
"""

import argparse
import os
import struct
import sys

CAP_TPA_EXEC   = 0x0001
CAP_FAR_EXEC   = 0x0002
CAP_DOC_MUTATE = 0x0004
CAP_MODAL_UI   = 0x0008
CAP_HAS_ABOUT  = 0x0010
CAP_HAS_CONFIG = 0x0020
CAP_SIZE_4K    = 0x0000
CAP_SIZE_8K    = 0x0040
CAP_SIZE_16K   = 0x0080
CAP_SIZE_32K   = 0x00C0
CAP_SIZE_MASK  = 0x00C0

SIZE_MAP = {
    "4k": CAP_SIZE_4K,
    "8k": CAP_SIZE_8K,
    "16k": CAP_SIZE_16K,
    "32k": CAP_SIZE_32K,
}

SIZE_MAX_BYTES = {
    "4k": 4096,
    "8k": 8192,
    "16k": 16384,
    "32k": 32768,
}

def build_reloc_bitmap(code_100: bytes, code_200: bytes) -> bytes:
    """
    Computes CP/M 3 relocation bitmap by comparing two identical code images
    assembled at ORG 0100h and ORG 0200h.
    Wherever code_200[i] == (code_100[i] + 1) & 0xFF, that offset is an address
    high-byte that must be relocated.
    """
    if len(code_100) != len(code_200):
        raise ValueError(f"Image lengths differ: {len(code_100)} vs {len(code_200)}")

    prog_len = len(code_100)
    bitmap_len = (prog_len + 7) // 8
    bitmap = bytearray(bitmap_len)

    for i in range(prog_len):
        diff = (code_200[i] - code_100[i]) & 0xFF
        if diff == 1:
            byte_idx = i // 8
            bit_idx = 7 - (i % 8)
            bitmap[byte_idx] |= (1 << bit_idx)
        elif diff != 0:
            pass

    return bytes(bitmap)

def create_header(name: str, prog_size: int, bss_size: int = 0,
                  load_addr: int = 0, capabilities: int = 0) -> bytes:
    header = bytearray(256)
    header[0] = 0x00
    struct.pack_into("<H", header, 0x01, prog_size)
    header[0x03] = 0x00
    struct.pack_into("<H", header, 0x04, bss_size)
    header[0x06] = 0x00
    struct.pack_into("<H", header, 0x07, load_addr)
    header[0x09] = 0x00
    struct.pack_into("<H", header, 0x0A, 0x0000)

    clean_name = name.strip().upper().encode("ascii", errors="replace")[:15]
    header[0x0C:0x0C+len(clean_name)] = clean_name
    header[0x0C+len(clean_name)] = 0x00

    struct.pack_into("<H", header, 0x1C, capabilities)
    struct.pack_into("<H", header, 0x1E, 0x0000)

    return bytes(header)

def make_prl(name: str, code_100: bytes, code_200: bytes = None,
             bss_size: int = 0, load_addr: int = 0, is_ovl: bool = False,
             capabilities: int = CAP_TPA_EXEC, size: str = "4k") -> bytes:
    size = size.lower()
    if size not in SIZE_MAP:
        raise ValueError(
            f"Invalid size '{size}', must be '4k', '8k', '16k', or '32k'")
    max_slot = SIZE_MAX_BYTES[size]
    prog_size = len(code_100)
    if prog_size > max_slot:
        raise ValueError(
            f"Plugin code size {prog_size} exceeds {size.upper()} "
            f"slot limit ({max_slot} bytes)")

    size_flag = SIZE_MAP[size]
    capabilities = (capabilities & ~CAP_SIZE_MASK) | size_flag

    if size in ("8k", "16k", "32k"):
        if capabilities & CAP_TPA_EXEC:
            raise ValueError(
                f"{size.upper()} plugins cannot execute in TPA overlay slot "
                f"(restricted to 4KB plugins)")
        capabilities |= CAP_FAR_EXEC

    if is_ovl:
        header = create_header(name, prog_size, bss_size, load_addr, capabilities)
        return header + code_100
    else:
        if code_200 is not None:
            bitmap = build_reloc_bitmap(code_100, code_200)
        else:
            bitmap = bytes((prog_size + 7) // 8)
        header = create_header(name, prog_size, bss_size, load_addr=0, capabilities=capabilities)
        return header + code_100 + bitmap

def main():
    parser = argparse.ArgumentParser(description="Package Z80 binaries into CP/M 3 PRL/OVL format.")
    parser.add_argument("image_100", help="Binary assembled at ORG 0100h (or target address for OVL)")
    parser.add_argument("image_200", nargs="?", default=None,
                        help="Binary assembled at ORG 0200h (optional, for automatic relocation bitmap generation)")
    parser.add_argument("-o", "--output", required=True, help="Output .PRL or .OVL filename")
    parser.add_argument("-n", "--name", required=True, help="Plugin name (up to 15 chars)")
    parser.add_argument("--ovl", action="store_true", help="Generate CP/M 3 Overlay (OVL) without relocation bitmap")
    parser.add_argument("--load-addr", type=lambda x: int(x, 0), default=0,
                        help="Target execution address (e.g. 0xA84F for TPA slot overlay, 0x1000 for Far RAM slot)")
    parser.add_argument("--bss", type=lambda x: int(x, 0), default=0, help="BSS uninitialized size in bytes")
    parser.add_argument("--size", choices=["4k", "8k", "16k", "32k"],
                        default=None,
                        help="Slot size class: 4k (default), 8k, 16k, or 32k")
    parser.add_argument("--size-4k", dest="size_4k", action="store_true",
                        help="Alias for --size 4k")
    parser.add_argument("--size-8k", dest="size_8k", action="store_true",
                        help="Alias for --size 8k")
    parser.add_argument("--size-16k", dest="size_16k", action="store_true",
                        help="Alias for --size 16k")
    parser.add_argument("--size-32k", dest="size_32k", action="store_true",
                        help="Alias for --size 32k")
    parser.add_argument("--tpa", action="store_true", default=None,
                        help="Can run in TPA slot (4KB plugins only)")
    parser.add_argument("--far", action="store_true", default=False,
                        help="Can run directly in Far RAM")
    parser.add_argument("--mutate", action="store_true", default=False,
                        help="Modifies document lines")
    parser.add_argument("--modal", action="store_true", default=False,
                        help="Draws modal dialog/screen")
    parser.add_argument("--has-about", action="store_true", default=False,
                        help="Implements embedded About screen")
    parser.add_argument("--has-config", action="store_true", default=False,
                        help="Implements embedded Configuration screen")
    parser.add_argument("--caps", type=lambda x: int(x, 0), default=None,
                        help="Explicit 16-bit capabilities bitmask override")

    args = parser.parse_args()

    size = "4k"
    if args.size:
        size = args.size.lower()
    elif args.size_8k:
        size = "8k"
    elif args.size_16k:
        size = "16k"
    elif args.size_32k:
        size = "32k"
    elif args.size_4k:
        size = "4k"

    with open(args.image_100, "rb") as f:
        code_100 = f.read()

    code_200 = None
    if args.image_200:
        with open(args.image_200, "rb") as f:
            code_200 = f.read()

    if args.caps is not None:
        caps = args.caps
        if (not args.size and not args.size_4k and not args.size_8k
                and not args.size_16k and not args.size_32k):
            sz_bits = caps & CAP_SIZE_MASK
            if sz_bits == CAP_SIZE_8K:
                size = "8k"
            elif sz_bits == CAP_SIZE_16K:
                size = "16k"
            elif sz_bits == CAP_SIZE_32K:
                size = "32k"
            else:
                size = "4k"
    else:
        caps = 0
        if size in ("8k", "16k", "32k"):
            if args.tpa:
                parser.error(
                    f"{size.upper()} plugins cannot use --tpa (TPA overlay "
                    f"execution is strictly restricted to 4KB plugins)")
            caps |= CAP_FAR_EXEC
        else:
            if args.tpa is not None:
                if args.tpa:
                    caps |= CAP_TPA_EXEC
            else:
                caps |= CAP_TPA_EXEC
            if args.far:
                caps |= CAP_FAR_EXEC

        if args.mutate:
            caps |= CAP_DOC_MUTATE
        if args.modal:
            caps |= CAP_MODAL_UI
        if args.has_about:
            caps |= CAP_HAS_ABOUT
        if args.has_config:
            caps |= CAP_HAS_CONFIG

        caps = (caps & ~CAP_SIZE_MASK) | SIZE_MAP[size]

    result = make_prl(
        name=args.name,
        code_100=code_100,
        code_200=code_200,
        bss_size=args.bss,
        load_addr=args.load_addr,
        is_ovl=args.ovl,
        capabilities=caps,
        size=size
    )

    with open(args.output, "wb") as f:
        f.write(result)

    print(f"[+] Successfully wrote {len(result)} bytes to {args.output} (Name: {args.name}, Size: {size.upper()}, Caps: 0x{caps:04X})")

if __name__ == "__main__":
    main()
