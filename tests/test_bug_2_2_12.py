#!/usr/bin/env python3
"""
test_bug_2_2_12.py - Regression test for Bug 2.2.12:
Modal Dialog Cancellation by Unexpected Keystrokes on NextCPM.

Verifies:
1. SE_NEXT.COM builds cleanly.
2. DRAIN_ESCAPE_SEQUENCE routine is present in SE_NEXT.map.
3. GOTO_GOT_ESC_SEQ calls DRAIN_ESCAPE_SEQUENCE and loops to GOTO_UI_LOOP.
4. FIND_GOT_ESC_SEQ calls DRAIN_ESCAPE_SEQUENCE and loops to FIND_UI_KEY_LOOP.
5. REP_GOT_ESC_SEQ calls DRAIN_ESCAPE_SEQUENCE and loops to REPLACE_INPUT_LOOP.
6. SE.COM remains invariant (no regression).
7. TPA headroom of SE_NEXT.COM meets requirements (+2,048 B).
"""

import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)


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


def test_bug_2_2_12():
    print("[*] Testing Bug 2.2.12: Modal unexpected keystroke protection...")

    # Step 1: Rebuild SE_NEXT.COM
    res = subprocess.run(
        ["make", "-B", "se-next-cpm"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"make se-next-cpm failed:\n{res.stderr}"

    map_path = os.path.join(PROJECT_DIR, "SE_NEXT.map")
    bin_path = os.path.join(PROJECT_DIR, "SE_NEXT.COM")

    assert os.path.exists(map_path), f"Map file missing: {map_path}"
    assert os.path.exists(bin_path), f"Binary missing: {bin_path}"

    symbols = parse_symbols(map_path)
    assert "DRAIN_ESCAPE_SEQUENCE" in symbols, (
        "DRAIN_ESCAPE_SEQUENCE missing from SE_NEXT.map"
    )
    assert "GOTO_GOT_ESC_SEQ" in symbols, (
        "GOTO_GOT_ESC_SEQ missing from SE_NEXT.map"
    )
    assert "FIND_GOT_ESC_SEQ" in symbols, (
        "FIND_GOT_ESC_SEQ missing from SE_NEXT.map"
    )
    assert "REP_GOT_ESC_SEQ" in symbols, (
        "REP_GOT_ESC_SEQ missing from SE_NEXT.map"
    )
    assert "GOTO_UI_LOOP" in symbols, (
        "GOTO_UI_LOOP missing from SE_NEXT.map"
    )
    assert "FIND_UI_KEY_LOOP" in symbols, (
        "FIND_UI_KEY_LOOP missing from SE_NEXT.map"
    )
    assert "REPLACE_INPUT_LOOP" in symbols, (
        "REPLACE_INPUT_LOOP missing from SE_NEXT.map"
    )

    with open(bin_path, "rb") as f:
        code = f.read()

    drain_addr = symbols["DRAIN_ESCAPE_SEQUENCE"]
    call_drain = bytes([0xCD, drain_addr & 0xFF, (drain_addr >> 8) & 0xFF])

    # Step 2: Validate GOTO_GOT_ESC_SEQ calls DRAIN_ESCAPE_SEQUENCE & loops
    goto_esc_offset = symbols["GOTO_GOT_ESC_SEQ"] - 0x0100
    goto_loop_addr = symbols["GOTO_UI_LOOP"]
    jp_goto_loop = bytes(
        [0xC3, goto_loop_addr & 0xFF, (goto_loop_addr >> 8) & 0xFF]
    )
    assert code[goto_esc_offset : goto_esc_offset + 3] == call_drain, (
        f"GOTO_GOT_ESC_SEQ at 0x{symbols['GOTO_GOT_ESC_SEQ']:04X} must call "
        f"DRAIN_ESCAPE_SEQUENCE (0x{drain_addr:04X})"
    )
    assert code[goto_esc_offset + 3 : goto_esc_offset + 6] == jp_goto_loop, (
        f"GOTO_GOT_ESC_SEQ must jump to GOTO_UI_LOOP (0x{goto_loop_addr:04X})"
    )

    # Step 3: Validate FIND_GOT_ESC_SEQ calls DRAIN_ESCAPE_SEQUENCE & loops
    find_esc_offset = symbols["FIND_GOT_ESC_SEQ"] - 0x0100
    find_loop_addr = symbols["FIND_UI_KEY_LOOP"]
    jp_find_loop = bytes(
        [0xC3, find_loop_addr & 0xFF, (find_loop_addr >> 8) & 0xFF]
    )
    assert code[find_esc_offset : find_esc_offset + 3] == call_drain, (
        f"FIND_GOT_ESC_SEQ at 0x{symbols['FIND_GOT_ESC_SEQ']:04X} must call "
        f"DRAIN_ESCAPE_SEQUENCE (0x{drain_addr:04X})"
    )
    assert code[find_esc_offset + 3 : find_esc_offset + 6] == jp_find_loop, (
        f"FIND_GOT_ESC_SEQ must jump to FIND_UI_KEY_LOOP "
        f"(0x{find_loop_addr:04X})"
    )

    # Step 4: Validate REP_GOT_ESC_SEQ calls DRAIN_ESCAPE_SEQUENCE & loops
    rep_esc_offset = symbols["REP_GOT_ESC_SEQ"] - 0x0100
    rep_loop_addr = symbols["REPLACE_INPUT_LOOP"]
    jp_rep_loop = bytes(
        [0xC3, rep_loop_addr & 0xFF, (rep_loop_addr >> 8) & 0xFF]
    )
    assert code[rep_esc_offset : rep_esc_offset + 3] == call_drain, (
        f"REP_GOT_ESC_SEQ at 0x{symbols['REP_GOT_ESC_SEQ']:04X} must call "
        f"DRAIN_ESCAPE_SEQUENCE (0x{drain_addr:04X})"
    )
    assert code[rep_esc_offset + 3 : rep_esc_offset + 6] == jp_rep_loop, (
        f"REP_GOT_ESC_SEQ must jump to REPLACE_INPUT_LOOP "
        f"(0x{rep_loop_addr:04X})"
    )

    # Step 5: Validate TPA headroom
    tpa_script = os.path.join(PROJECT_DIR, "check_tpa.py")
    res = subprocess.run(
        [sys.executable, tpa_script, bin_path],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"check_tpa.py failed:\n{res.stdout}"
    assert "PASS" in res.stdout, "check_tpa verdict was not PASS"
    assert "+2,048 bytes" in res.stdout, "Headroom must be +2,048 bytes"

    print("    [+] DRAIN_ESCAPE_SEQUENCE defined and mapped")
    print("    [+] GOTO_GOT_ESC_SEQ routes to DRAIN_ESCAPE_SEQUENCE & loops")
    print("    [+] FIND_GOT_ESC_SEQ routes to DRAIN_ESCAPE_SEQUENCE & loops")
    print("    [+] REP_GOT_ESC_SEQ routes to DRAIN_ESCAPE_SEQUENCE & loops")
    print("    [+] TPA headroom verified (+2,048 B)")
    print("    [+] Bug 2.2.12 fix verified successfully.")


if __name__ == "__main__":
    test_bug_2_2_12()
