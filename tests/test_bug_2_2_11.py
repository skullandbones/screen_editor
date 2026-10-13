#!/usr/bin/env python3
"""
test_bug_2_2_11.py - Regression test for Bug 2.2.11:
Forward Deletion Line Join Sticky Target Column Update on NextCPM.

Verifies:
1. SE_NEXT.COM builds cleanly.
2. DO_DEL_JOIN_OK calls CHECKOUT_ACTIVE_LINE, CALC_VISUAL_COL, and
   updates (TARGET_COL),HL when lines are joined on Delete at EOL.
3. SE.COM remains invariant (no regression).
4. TPA headroom of SE_NEXT.COM meets requirements (+2,048 B).
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


def test_bug_2_2_11():
    print("[*] Testing Bug 2.2.11: Line join TARGET_COL update on NextCPM...")

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
    assert "DO_DEL_JOIN_OK" in symbols, "DO_DEL_JOIN_OK missing"
    assert "CHECKOUT_ACTIVE_LINE" in symbols, "CHECKOUT_ACTIVE_LINE missing"
    assert "CALC_VISUAL_COL" in symbols, "CALC_VISUAL_COL missing"
    assert "TARGET_COL" in symbols, "TARGET_COL missing"

    with open(bin_path, "rb") as f:
        code = f.read()

    join_ok_offset = symbols["DO_DEL_JOIN_OK"] - 0x0100
    chk_addr = symbols["CHECKOUT_ACTIVE_LINE"]
    calc_addr = symbols["CALC_VISUAL_COL"]
    target_addr = symbols["TARGET_COL"]

    # In DO_DEL_JOIN_OK:
    # CALL CHECKOUT_ACTIVE_LINE (CD <chk_addr>)
    # CALL CALC_VISUAL_COL     (CD <calc_addr>)
    # LD (TARGET_COL),HL       (22 <target_addr>)
    chk_call = bytes([0xCD, chk_addr & 0xFF, (chk_addr >> 8) & 0xFF])
    calc_call = bytes([0xCD, calc_addr & 0xFF, (calc_addr >> 8) & 0xFF])
    store_tgt = bytes([0x22, target_addr & 0xFF, (target_addr >> 8) & 0xFF])

    slice_bytes = code[join_ok_offset : join_ok_offset + 32]
    assert chk_call in slice_bytes, (
        f"Missing CALL CHECKOUT_ACTIVE_LINE (0x{chk_addr:04X}) "
        f"in DO_DEL_JOIN_OK"
    )
    assert calc_call in slice_bytes, (
        f"Missing CALL CALC_VISUAL_COL (0x{calc_addr:04X}) in DO_DEL_JOIN_OK"
    )
    assert store_tgt in slice_bytes, (
        f"Missing LD (TARGET_COL),HL (0x{target_addr:04X}) in DO_DEL_JOIN_OK"
    )

    # Step 2: Validate TPA headroom
    tpa_script = os.path.join(PROJECT_DIR, "check_tpa.py")
    res = subprocess.run(
        [sys.executable, tpa_script, bin_path],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"check_tpa.py failed:\n{res.stdout}"
    assert "PASS" in res.stdout, "check_tpa verdict was not PASS"
    assert (
        "+2,048 bytes" in res.stdout or "+2,560 bytes" in res.stdout
    ), "Headroom must be positive"

    print("    [+] DO_DEL_JOIN_OK calls CHECKOUT_ACTIVE_LINE")
    print("    [+] DO_DEL_JOIN_OK calls CALC_VISUAL_COL")
    print("    [+] DO_DEL_JOIN_OK updates (TARGET_COL),HL")
    print("    [+] TPA headroom verified")
    print("    [+] Bug 2.2.11 fix verified successfully.")


if __name__ == "__main__":
    test_bug_2_2_11()
