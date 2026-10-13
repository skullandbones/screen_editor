#!/usr/bin/env python3
"""Automated regression test for NextCPM entry point and MMU banking.

Validates that:
1. SE_NEXT.COM begins with JP START (opcode 0xC3) at TPA origin 0x0100.
2. The destination address of JP START matches the START symbol in the
   assembled binary.
3. NEXT_SYSBNKCPY in hal_nextcpm_memory.asm uses MMU Slot 1 ($2000-$3FFF)
   via NextReg 0x51 rather than Slot 0 to prevent self-page-out.
4. Interrupts are disabled (DI) prior to NextReg 0x51 banking switches.
5. RomWBW CP/M SE.COM byte-for-byte binary invariance (47,872 B) is preserved.
"""

import os
import struct
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
SE_NEXT_COM = os.path.join(PROJECT_DIR, "SE_NEXT.COM")
SE_COM = os.path.join(PROJECT_DIR, "SE.COM")
HAL_NEXTCPM_MEM = os.path.join(
    PROJECT_DIR, "src", "hal", "next_cpm", "hal_nextcpm_memory.asm"
)
HAL_NATIVE_MEM = os.path.join(
    PROJECT_DIR, "src", "hal", "next_native", "hal_next_memory.asm"
)


def test_nextcpm_entry():
    print("[*] Validating NextCPM entry point and MMU banking safety...")

    # Rebuild SE_NEXT.COM to ensure fresh symbols and binary
    cmd = ["make", "se-next-cpm"]
    res = subprocess.run(cmd, capture_output=True, text=True, cwd=PROJECT_DIR)
    assert res.returncode == 0, f"make se-next-cpm failed:\n{res.stderr}"

    assert os.path.exists(SE_NEXT_COM), f"Missing {SE_NEXT_COM}"
    with open(SE_NEXT_COM, "rb") as f:
        hdr = f.read(3)

    assert len(hdr) == 3, "Truncated binary header"
    opcode = hdr[0]
    target_addr = struct.unpack("<H", hdr[1:3])[0]

    assert opcode == 0xC3, (
        f"Expected JP opcode 0xC3 at 0x0100, got 0x{opcode:02X}"
    )
    print(f"    [+] SE_NEXT.COM entry opcode is JP (0xC3) to 0x{target_addr:04X}")

    # Check symbols in src/se_next_cpm.sym
    sym_path = os.path.join(PROJECT_DIR, "src", "se_next_cpm.sym")
    assert os.path.exists(sym_path), f"Missing {sym_path}"
    start_found = False
    with open(sym_path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("START "):
                parts = line.split()
                # Address is e.g. $00CD or $01CD
                sym_hex = parts[2].lstrip("$")
                sym_addr = int(sym_hex, 16)
                if sym_addr < 0x0100:
                    sym_addr += 0x0100
                assert target_addr == sym_addr, (
                    f"JP target 0x{target_addr:04X} does not match START "
                    f"symbol 0x{sym_addr:04X}"
                )
                start_found = True
                break
    assert start_found, "START symbol not found in se_next_cpm.sym"
    print(f"    [+] JP target matches START symbol address 0x{target_addr:04X}")

    # Verify hal_nextcpm_memory.asm uses Slot 1 (NextReg 0x51)
    with open(HAL_NEXTCPM_MEM, "r", encoding="utf-8") as f:
        src = f.read()

    assert "050H" not in src, "Slot 0 (050H) must not be used for Far RAM"
    assert "051H" in src, "Slot 1 (051H) must be used for Far RAM"
    assert "NEXT_SAVED_SLOT1_PAGE" in src, "NEXT_SAVED_SLOT1_PAGE required"
    assert "OR 020H" in src, "Slot 1 address offset (OR 020H) required"
    print("    [+] hal_nextcpm_memory.asm uses MMU Slot 1 ($2000-$3FFF)")

    # Verify DI occurs before NextReg 0x51 transfer
    xfer_idx = src.find("NCSB_DO_TRANSFER:")
    assert xfer_idx != -1, "NCSB_DO_TRANSFER not found"
    xfer_code = src[xfer_idx : xfer_idx + 200]
    di_pos = xfer_code.find("DI")
    out_pos = xfer_code.find("OUT (C),A")
    assert di_pos != -1 and di_pos < out_pos, (
        "DI must occur before NextReg page switch OUT (C),A"
    )
    print("    [+] DI occurs before NextReg 0x51 page switch")

    # Verify native Next memory also uses Slot 1
    with open(HAL_NATIVE_MEM, "r", encoding="utf-8") as f:
        nat_src = f.read()
    assert "050H" not in nat_src, "Slot 0 must not be used in native memory"
    assert "051H" in nat_src, "Slot 1 must be used in native memory"
    print("    [+] hal_next_memory.asm uses MMU Slot 1 ($2000-$3FFF)")

    # Verify RomWBW CP/M SE.COM byte-for-byte binary invariance
    assert os.path.exists(SE_COM), f"Missing {SE_COM}"
    assert os.path.getsize(SE_COM) == 47872, (
        f"SE.COM size must be 47,872 bytes, got {os.path.getsize(SE_COM)}"
    )
    res = subprocess.run(
        ["git", "diff", "--exit-code", "SE.COM"],
        capture_output=True,
        cwd=PROJECT_DIR,
    )
    assert res.returncode == 0, "SE.COM binary invariance violated"
    print("    [+] RomWBW CP/M SE.COM byte-for-byte binary invariance preserved")
    print("[+] All NextCPM entry point and MMU banking checks PASSED.")


if __name__ == "__main__":
    test_nextcpm_entry()
