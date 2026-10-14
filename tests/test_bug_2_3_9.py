#!/usr/bin/env python3
"""Automated regression test for Bug 2.3.9:
Escape Sequence Trailing Byte Leakage in Native Next (SE.NEX and .se).

Validates that:
1. Native Next binaries SE.NEX and .se build cleanly.
2. DRAIN_REMAINING_CSI is compiled and symbol-mapped in both targets.
3. Unrecognized CSI sequence paths (CSI_DONE) route to DRAIN_REMAINING_CSI
   to absorb trailing bytes instead of returning immediately.
4. DRAIN_REMAINING_CSI includes boundary checks for terminal bytes (0x40..0x7E).
5. Dot command binary size remains within the 48KB NextZXOS execution slot.
6. RomWBW CP/M SE.COM byte-for-byte binary invariance is strictly preserved.
"""

import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
MAP_NEX = os.path.join(PROJECT_DIR, "SE_NEX.map")
MAP_DOT = os.path.join(PROJECT_DIR, "dot_se.map")
BIN_NEX = os.path.join(PROJECT_DIR, "SE_NEX.BIN")
BIN_DOT = os.path.join(PROJECT_DIR, "dot_se.bin")
TARGET_DOT = os.path.join(PROJECT_DIR, ".se")


def parse_symbols(map_path):
    symbols = {}
    with open(map_path, "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 3 and parts[1] == "=" and parts[2].startswith("$"):
                try:
                    symbols[parts[0]] = int(parts[2][1:], 16)
                except ValueError:
                    pass
    return symbols


def test_bug_2_3_9():
    print("[*] Testing Bug 2.3.9: Escape sequence trailing byte draining...")

    # Step 1: Rebuild native Next targets
    res = subprocess.run(
        ["make", "-B", "se-next-native"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"make se-next-native failed:\n{res.stderr}"

    assert os.path.exists(MAP_NEX), f"Map file missing: {MAP_NEX}"
    assert os.path.exists(MAP_DOT), f"Map file missing: {MAP_DOT}"
    assert os.path.exists(BIN_NEX), f"Binary missing: {BIN_NEX}"
    assert os.path.exists(BIN_DOT), f"Binary missing: {BIN_DOT}"
    assert os.path.exists(TARGET_DOT), f"Dot command missing: {TARGET_DOT}"

    # Step 2: Check SE.NEX symbols and jump target
    syms_nex = parse_symbols(MAP_NEX)
    assert "DRAIN_REMAINING_CSI" in syms_nex, (
        "DRAIN_REMAINING_CSI missing from SE_NEX.map"
    )
    assert "CSI_DONE" in syms_nex, "CSI_DONE missing from SE_NEX.map"

    drain_nex = syms_nex["DRAIN_REMAINING_CSI"]
    csi_done_nex = syms_nex["CSI_DONE"]

    with open(BIN_NEX, "rb") as f:
        data_nex = f.read()

    # SE_NEX.BIN starts at ORG $4000
    offset_nex = csi_done_nex - 0x4000
    expected_jp_nex = bytes(
        [0xC3, drain_nex & 0xFF, (drain_nex >> 8) & 0xFF]
    )
    assert data_nex[offset_nex : offset_nex + 3] == expected_jp_nex, (
        f"SE_NEX CSI_DONE at 0x{csi_done_nex:04X} does not jump to "
        f"DRAIN_REMAINING_CSI (0x{drain_nex:04X})"
    )

    drain_off_nex = drain_nex - 0x4000
    drain_bytes_nex = data_nex[drain_off_nex : drain_off_nex + 32]
    assert 0x40 in drain_bytes_nex and 0x7F in drain_bytes_nex, (
        "SE_NEX DRAIN_REMAINING_CSI missing 0x40/0x7F boundary checks"
    )
    print("    [+] SE.NEX CSI_DONE routes to DRAIN_REMAINING_CSI")

    # Step 3: Check dot_se symbols and jump target
    syms_dot = parse_symbols(MAP_DOT)
    assert "DRAIN_REMAINING_CSI" in syms_dot, (
        "DRAIN_REMAINING_CSI missing from dot_se.map"
    )
    assert "CSI_DONE" in syms_dot, "CSI_DONE missing from dot_se.map"

    drain_dot = syms_dot["DRAIN_REMAINING_CSI"]
    csi_done_dot = syms_dot["CSI_DONE"]

    with open(BIN_DOT, "rb") as f:
        data_dot = f.read()

    # dot_se.bin starts at ORG $2000
    offset_dot = csi_done_dot - 0x2000
    expected_jp_dot = bytes(
        [0xC3, drain_dot & 0xFF, (drain_dot >> 8) & 0xFF]
    )
    assert data_dot[offset_dot : offset_dot + 3] == expected_jp_dot, (
        f"dot_se CSI_DONE at 0x{csi_done_dot:04X} does not jump to "
        f"DRAIN_REMAINING_CSI (0x{drain_dot:04X})"
    )

    drain_off_dot = drain_dot - 0x2000
    drain_bytes_dot = data_dot[drain_off_dot : drain_off_dot + 32]
    assert 0x40 in drain_bytes_dot and 0x7F in drain_bytes_dot, (
        "dot_se DRAIN_REMAINING_CSI missing 0x40/0x7F boundary checks"
    )
    print("    [+] .se CSI_DONE routes to DRAIN_REMAINING_CSI")

    # Step 4: Validate slot size
    assert len(data_dot) <= 49152, (
        f".se size {len(data_dot)} exceeds 48KB slot"
    )
    print(f"    [+] .se slot size {len(data_dot)} bytes <= 49152 bytes")

    # Step 5: Check RomWBW CP/M SE.COM binary invariance
    res = subprocess.run(
        ["make", "-B", "SE.COM"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"make SE.COM failed:\n{res.stderr}"

    res = subprocess.run(
        ["git", "diff", "--exit-code", "SE.COM"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, "SE.COM binary changed! Invariance violated."
    print("    [+] SE.COM binary invariance preserved")
    print("    [+] Bug 2.3.9 fix verified successfully.")


if __name__ == "__main__":
    test_bug_2_3_9()
