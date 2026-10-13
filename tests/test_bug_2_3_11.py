#!/usr/bin/env python3
"""Automated regression test for Bug 2.3.11:
Modal Dialog Cancellation by Unexpected Keystrokes on Native Next.

Validates that:
1. Native Next binaries SE.NEX and .se build cleanly.
2. DRAIN_ESCAPE_SEQUENCE routine is present in both targets.
3. GOTO_GOT_ESC_SEQ calls DRAIN_ESCAPE_SEQUENCE and loops to GOTO_UI_LOOP.
4. FIND_GOT_ESC_SEQ calls DRAIN_ESCAPE_SEQUENCE and loops to FIND_UI_KEY_LOOP.
5. REP_GOT_ESC_SEQ calls DRAIN_ESCAPE_SEQUENCE and loops to REPLACE_INPUT_LOOP.
6. Dot command binary size remains within the 48KB NextZXOS execution slot.
7. RomWBW CP/M SE.COM byte-for-byte binary invariance is strictly preserved.
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


def verify_target(bin_path, org, symbols, name):
    with open(bin_path, "rb") as f:
        code = f.read()

    drain_addr = symbols["DRAIN_ESCAPE_SEQUENCE"]
    call_drain = bytes([0xCD, drain_addr & 0xFF, (drain_addr >> 8) & 0xFF])

    # 1. GOTO_GOT_ESC_SEQ
    goto_esc_offset = symbols["GOTO_GOT_ESC_SEQ"] - org
    goto_loop_addr = symbols["GOTO_UI_LOOP"]
    jp_goto_loop = bytes(
        [0xC3, goto_loop_addr & 0xFF, (goto_loop_addr >> 8) & 0xFF]
    )
    assert code[goto_esc_offset : goto_esc_offset + 3] == call_drain, (
        f"{name}: GOTO_GOT_ESC_SEQ must call DRAIN_ESCAPE_SEQUENCE"
    )
    assert (
        code[goto_esc_offset + 3 : goto_esc_offset + 6] == jp_goto_loop
    ), f"{name}: GOTO_GOT_ESC_SEQ must jump to GOTO_UI_LOOP"

    # 2. FIND_GOT_ESC_SEQ
    find_esc_offset = symbols["FIND_GOT_ESC_SEQ"] - org
    find_loop_addr = symbols["FIND_UI_KEY_LOOP"]
    jp_find_loop = bytes(
        [0xC3, find_loop_addr & 0xFF, (find_loop_addr >> 8) & 0xFF]
    )
    assert code[find_esc_offset : find_esc_offset + 3] == call_drain, (
        f"{name}: FIND_GOT_ESC_SEQ must call DRAIN_ESCAPE_SEQUENCE"
    )
    assert (
        code[find_esc_offset + 3 : find_esc_offset + 6] == jp_find_loop
    ), f"{name}: FIND_GOT_ESC_SEQ must jump to FIND_UI_KEY_LOOP"

    # 3. REP_GOT_ESC_SEQ
    rep_esc_offset = symbols["REP_GOT_ESC_SEQ"] - org
    rep_loop_addr = symbols["REPLACE_INPUT_LOOP"]
    jp_rep_loop = bytes(
        [0xC3, rep_loop_addr & 0xFF, (rep_loop_addr >> 8) & 0xFF]
    )
    assert code[rep_esc_offset : rep_esc_offset + 3] == call_drain, (
        f"{name}: REP_GOT_ESC_SEQ must call DRAIN_ESCAPE_SEQUENCE"
    )
    assert (
        code[rep_esc_offset + 3 : rep_esc_offset + 6] == jp_rep_loop
    ), f"{name}: REP_GOT_ESC_SEQ must jump to REPLACE_INPUT_LOOP"

    print(f"    [+] {name} modal dialog escape sequences drained and absorbed")


def test_bug_2_3_11():
    print("[*] Testing Bug 2.3.11: Modal unexpected keystroke protection...")

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
    verify_target(BIN_NEX, 0x4000, syms_nex, "SE.NEX")

    # Step 3: Validate dot_se (.se)
    syms_dot = parse_symbols(MAP_DOT)
    verify_target(BIN_DOT, 0x2000, syms_dot, ".se")

    # Step 4: Validate slot size
    with open(BIN_DOT, "rb") as f:
        data_dot = f.read()
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
    print("    [+] Bug 2.3.11 fix verified successfully.")


if __name__ == "__main__":
    test_bug_2_3_11()
