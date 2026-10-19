#!/usr/bin/env python3
"""
test_bug_2_2_23.py - Regression test for Bug 2.2.23:
SE.CFG SCREEN=120X40 Not Overridden to 80x24 on Startup in SE_NEXT.COM.

Verifies:
1. SE_NEXT.COM builds cleanly.
2. SET_MODE_120X40 in SE_NEXT.COM immediately jumps to SET_MODE_80X24
   (0xC3 <addr>), so PARSE_CONFIG_BUFFER (PCB_CHECK_120) enforces 80x24
   even when SE.CFG specifies SCREEN=120X40.
3. SE.COM byte-for-byte binary invariance is preserved.
4. TPA and CCP headroom of SE_NEXT.COM pass check_ccp.py.
"""

import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)


def parse_symbols(map_path):
    symbols = {}
    with open(map_path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.strip().split()
            if (
                len(parts) >= 3
                and parts[1] == "="
                and parts[2].startswith("$")
            ):
                try:
                    symbols[parts[0]] = int(parts[2][1:], 16)
                except ValueError:
                    pass
    return symbols


def test_bug_2_2_23():
    print("[*] Testing Bug 2.2.23: SE.CFG SCREEN=120X40 override to 80x24...")

    res = subprocess.run(
        ["make", "-B", "se-next-cpm"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"make se-next-cpm failed:\n{res.stderr}"

    map_path = os.path.join(PROJECT_DIR, "SE_NEXT.map")
    bin_path = os.path.join(PROJECT_DIR, "SE_NEXT.COM")
    symbols = parse_symbols(map_path)

    for sym in ("SET_MODE_120X40", "SET_MODE_80X24", "PCB_CHECK_120"):
        assert sym in symbols, f"{sym} missing from SE_NEXT.map"

    with open(bin_path, "rb") as f:
        code = f.read()

    # Verify SET_MODE_120X40 starts with JP SET_MODE_80X24 (0xC3 lo hi)
    set120_off = symbols["SET_MODE_120X40"] - 0x0100
    set80_addr = symbols["SET_MODE_80X24"]
    expected_jp = bytes([0xC3, set80_addr & 0xFF, (set80_addr >> 8) & 0xFF])
    actual = code[set120_off : set120_off + 3]
    assert actual == expected_jp, (
        f"Expected SET_MODE_120X40 to be JP SET_MODE_80X24 "
        f"({expected_jp.hex()}), got {actual.hex()}"
    )

    # Verify SE.COM byte-for-byte binary invariance
    res_se = subprocess.run(
        ["git", "diff", "--exit-code", "SE.COM"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res_se.returncode == 0, "SE.COM binary invariance violated!"

    # Verify CCP headroom
    ccp_script = os.path.join(PROJECT_DIR, "check_ccp.py")
    res_ccp = subprocess.run(
        [sys.executable, ccp_script, bin_path],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res_ccp.returncode == 0, f"check_ccp.py failed:\n{res_ccp.stdout}"

    print("    [+] SET_MODE_120X40 redirects to SET_MODE_80X24 via JP")
    print("    [+] SE.COM binary invariance and CCP headroom verified")
    print("[+] Bug 2.2.23 regression test PASSED.")


if __name__ == "__main__":
    test_bug_2_2_23()
