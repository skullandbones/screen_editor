#!/usr/bin/env python3
"""Automated regression test for Bug 2.3.10:
Forward Deletion Line Join Sticky Target Column Update on Native Next.

Validates that:
1. Native Next binaries SE.NEX and .se build cleanly.
2. DO_DEL_JOIN_OK in both binaries calls CHECKOUT_ACTIVE_LINE and
   CALC_VISUAL_COL, and updates (TARGET_COL),HL upon line join on Delete at EOL.
3. Dot command binary size remains within the 48KB NextZXOS execution slot.
4. RomWBW CP/M SE.COM byte-for-byte binary invariance is strictly preserved.
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


def test_bug_2_3_10():
    print("[*] Testing Bug 2.3.10: Line join TARGET_COL update on Next...")

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

    # Step 2: Validate SE.NEX
    syms_nex = parse_symbols(MAP_NEX)
    assert "DO_DEL_JOIN_OK" in syms_nex, "DO_DEL_JOIN_OK missing from SE_NEX"
    assert "CHECKOUT_ACTIVE_LINE" in syms_nex, (
        "CHECKOUT_ACTIVE_LINE missing from SE_NEX"
    )
    assert "CALC_VISUAL_COL" in syms_nex, (
        "CALC_VISUAL_COL missing from SE_NEX"
    )
    assert "TARGET_COL" in syms_nex, "TARGET_COL missing from SE_NEX"

    join_ok_nex = syms_nex["DO_DEL_JOIN_OK"]
    chk_nex = syms_nex["CHECKOUT_ACTIVE_LINE"]
    calc_nex = syms_nex["CALC_VISUAL_COL"]
    target_nex = syms_nex["TARGET_COL"]

    with open(BIN_NEX, "rb") as f:
        data_nex = f.read()

    # ORG $4000
    offset_nex = join_ok_nex - 0x4000
    slice_nex = data_nex[offset_nex : offset_nex + 32]

    chk_call_nex = bytes([0xCD, chk_nex & 0xFF, (chk_nex >> 8) & 0xFF])
    calc_call_nex = bytes([0xCD, calc_nex & 0xFF, (calc_nex >> 8) & 0xFF])
    store_tgt_nex = bytes(
        [0x22, target_nex & 0xFF, (target_nex >> 8) & 0xFF]
    )

    assert chk_call_nex in slice_nex, (
        f"Missing CALL CHECKOUT_ACTIVE_LINE in SE.NEX DO_DEL_JOIN_OK"
    )
    assert calc_call_nex in slice_nex, (
        f"Missing CALL CALC_VISUAL_COL in SE.NEX DO_DEL_JOIN_OK"
    )
    assert store_tgt_nex in slice_nex, (
        f"Missing LD (TARGET_COL),HL in SE.NEX DO_DEL_JOIN_OK"
    )
    print("    [+] SE.NEX DO_DEL_JOIN_OK updates TARGET_COL correctly")

    # Step 3: Validate dot_se (.se)
    syms_dot = parse_symbols(MAP_DOT)
    assert "DO_DEL_JOIN_OK" in syms_dot, "DO_DEL_JOIN_OK missing from dot_se"
    assert "CHECKOUT_ACTIVE_LINE" in syms_dot, (
        "CHECKOUT_ACTIVE_LINE missing from dot_se"
    )
    assert "CALC_VISUAL_COL" in syms_dot, (
        "CALC_VISUAL_COL missing from dot_se"
    )
    assert "TARGET_COL" in syms_dot, "TARGET_COL missing from dot_se"

    join_ok_dot = syms_dot["DO_DEL_JOIN_OK"]
    chk_dot = syms_dot["CHECKOUT_ACTIVE_LINE"]
    calc_dot = syms_dot["CALC_VISUAL_COL"]
    target_dot = syms_dot["TARGET_COL"]

    with open(BIN_DOT, "rb") as f:
        data_dot = f.read()

    # ORG $2000
    offset_dot = join_ok_dot - 0x2000
    slice_dot = data_dot[offset_dot : offset_dot + 32]

    chk_call_dot = bytes([0xCD, chk_dot & 0xFF, (chk_dot >> 8) & 0xFF])
    calc_call_dot = bytes([0xCD, calc_dot & 0xFF, (calc_dot >> 8) & 0xFF])
    store_tgt_dot = bytes(
        [0x22, target_dot & 0xFF, (target_dot >> 8) & 0xFF]
    )

    assert chk_call_dot in slice_dot, (
        f"Missing CALL CHECKOUT_ACTIVE_LINE in .se DO_DEL_JOIN_OK"
    )
    assert calc_call_dot in slice_dot, (
        f"Missing CALL CALC_VISUAL_COL in .se DO_DEL_JOIN_OK"
    )
    assert store_tgt_dot in slice_dot, (
        f"Missing LD (TARGET_COL),HL in .se DO_DEL_JOIN_OK"
    )
    print("    [+] .se DO_DEL_JOIN_OK updates TARGET_COL correctly")

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
    print("    [+] Bug 2.3.10 fix verified successfully.")


if __name__ == "__main__":
    test_bug_2_3_10()
