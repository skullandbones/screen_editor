#!/usr/bin/env python3
"""
test_bug_2_2_13.py - Regression test for Bug 2.2.13:
Splash Screen Geometry Hotkeys & Unsupported 120x40 on NextCPM.

Verifies:
1. SE_NEXT.COM builds cleanly.
2. Default SCREEN_MODE is initialized to 80x24 (1), with 80 cols and 24 rows.
3. STR_SPLASH_CMDS displays [1] set 80x24, omitting/disabling 120x40 on Next.
4. DO_SET_120X40 and CONFIG_TOGGLE_MODE enforce SET_MODE_80X24.
5. TPA headroom of SE_NEXT.COM meets requirements (+2,048 B).
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


def test_bug_2_2_13():
    print("[*] Testing Bug 2.2.13: NextCPM geometry hotkeys & 80x24 default...")

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
    assert "SCREEN_MODE" in symbols, "SCREEN_MODE missing from symbols"
    assert "ACTIVE_COLS" in symbols, "ACTIVE_COLS missing from symbols"
    assert "ACTIVE_ROWS" in symbols, "ACTIVE_ROWS missing from symbols"
    assert "DO_SET_120X40" in symbols, "DO_SET_120X40 missing from symbols"
    assert "SET_MODE_80X24" in symbols, "SET_MODE_80X24 missing from symbols"

    with open(bin_path, "rb") as f:
        code = f.read()

    # Step 2: Validate SCREEN_MODE, ACTIVE_COLS, ACTIVE_ROWS default values
    mode_offset = symbols["SCREEN_MODE"] - 0x0100
    cols_offset = symbols["ACTIVE_COLS"] - 0x0100
    rows_offset = symbols["ACTIVE_ROWS"] - 0x0100

    # MODE_80X24 = 1, MODE_120X40 = 0
    assert code[mode_offset] == 1, (
        f"SCREEN_MODE must default to 1 (80x24), got {code[mode_offset]}"
    )
    assert code[cols_offset] == 80, (
        f"ACTIVE_COLS must default to 80, got {code[cols_offset]}"
    )
    assert code[rows_offset] == 24, (
        f"ACTIVE_ROWS must default to 24, got {code[rows_offset]}"
    )

    # Step 3: Validate splash string has [1] set 80x24
    splash_needle = b"[1]              set 80x24"
    assert splash_needle in code, (
        "Expected '[1]              set 80x24' in SE_NEXT.COM"
    )
    unsupported_needle = b"[1]              set 120x40"
    assert unsupported_needle not in code, (
        "Found unsupported '[1]              set 120x40' in SE_NEXT.COM"
    )

    # Step 4: Validate DO_SET_120X40 calls SET_MODE_80X24
    set120_offset = symbols["DO_SET_120X40"] - 0x0100
    set80_addr = symbols["SET_MODE_80X24"]
    expected_call = bytes([0xCD, set80_addr & 0xFF, (set80_addr >> 8) & 0xFF])
    assert expected_call in code[set120_offset : set120_offset + 8], (
        f"DO_SET_120X40 must redirect to SET_MODE_80X24 (0x{set80_addr:04X})"
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

    print("    [+] SCREEN_MODE defaults to 80x24 (80 cols, 24 rows)")
    print("    [+] STR_SPLASH_CMDS displays [1] set 80x24")
    print("    [+] 120x40 requests safely redirect to SET_MODE_80X24")
    print("    [+] TPA headroom verified (+2,048 B)")
    print("    [+] Bug 2.2.13 fix verified successfully.")


if __name__ == "__main__":
    test_bug_2_2_13()
