#!/usr/bin/env python3
"""
test_bug_2_2_26.py - Regression test for Bug 2.2.26:
Configuration Manager Displays Inapplicable RomWBW RAM Drive Options and
120x40 Toggle Hint on Next Hardware.

Verifies:
1. SE_NEXT.COM builds cleanly.
2. STR_RAM_PROTECTED_LBL in SE_NEXT.COM displays
   "None Detected (Next MMU 384KB)]    " rather than RomWBW HBIOS RAM drive
   preservation modes ("Preserve (RAM Drive Active, 128KB)]").
3. STR_CONFIG_FOOTER in SE_NEXT.COM displays
   "[3-5]=Toggle Option   [S]=Save Config   [ESC]=Exit".
4. SE.COM byte-for-byte binary invariance and CCP headroom pass.
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


def test_bug_2_2_26():
    print("[*] Testing Bug 2.2.26: NextCPM Configuration Manager options...")

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

    for sym in (
        "STR_RAM_PROTECTED_LBL",
        "STR_CONFIG_FOOTER",
        "SCS_RAM_MODE",
        "SCS_LINES_MODE",
    ):
        assert sym in symbols, f"{sym} missing from SE_NEXT.map"

    with open(bin_path, "rb") as f:
        code = f.read()

    ram_lbl_off = symbols["STR_RAM_PROTECTED_LBL"] - 0x0100
    expected_ram_lbl = b"None Detected (Next MMU 384KB)]    \r\n$"
    actual_ram_lbl = code[ram_lbl_off : ram_lbl_off + len(expected_ram_lbl)]
    assert actual_ram_lbl == expected_ram_lbl, (
        f"Expected STR_RAM_PROTECTED_LBL={expected_ram_lbl!r}, "
        f"got {actual_ram_lbl!r}"
    )

    footer_off = symbols["STR_CONFIG_FOOTER"] - 0x0100
    expected_footer = b"[3-5]=Toggle Option   [S]=Save Config   [ESC]=Exit$"
    actual_footer = code[footer_off : footer_off + len(expected_footer)]
    assert actual_footer == expected_footer, (
        f"Expected STR_CONFIG_FOOTER={expected_footer!r}, "
        f"got {actual_footer!r}"
    )

    # Ensure RomWBW RAM drive strings are not emitted in SE_NEXT.COM
    assert b"Preserve (RAM Drive Active, 128KB)]" not in code
    assert b"Hibernate (Backup/Restore, 384KB)]" not in code
    assert b"Overwrite (Sacrifice Drive, 384KB)]" not in code

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

    print("    [+] STR_RAM_PROTECTED_LBL shows Next MMU 384KB status")
    print("    [+] STR_CONFIG_FOOTER shows [3-5]=Toggle Option")
    print("    [+] SE.COM binary invariance and CCP headroom verified")
    print("[+] Bug 2.2.26 regression test PASSED.")


if __name__ == "__main__":
    test_bug_2_2_26()
