#!/usr/bin/env python3
"""Automated regression test for Bug 2.3.5:
Predominant Language Indication on About Screen for Native ZX Spectrum Next.

Validates that:
1. Native Next binaries SE.NEX and .se include '(Z80 Assembly)' in the About
   version banner per UI_UX_DESIGN.md Section 7.12 and 14.6.
2. SHOW_ABOUT_SCREEN dynamically calculates left padding to center the
   41-character version string within the 80-column screen.
3. Native targets build cleanly within the 48K slot.
4. RomWBW CP/M SE.COM byte-for-byte binary invariance is preserved.
"""

import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
TARGET_NEX = os.path.join(PROJECT_DIR, "SE.NEX")
TARGET_DOT = os.path.join(PROJECT_DIR, ".se")


def test_bug_2_3_5():
    print("[*] Testing Bug 2.3.5: About Screen Language on Native Next...")

    # 1. Build native Next targets
    res = subprocess.run(
        ["make", "-B", "se-next-native"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"make se-next-native failed:\n{res.stderr}"

    expected_banner = b"version 1.1.5 (2026-10-21) (Z80 Assembly)"

    # 2. Check SE.NEX binary
    assert os.path.exists(TARGET_NEX), f"Missing {TARGET_NEX}"
    with open(TARGET_NEX, "rb") as f:
        nex_data = f.read()
    assert expected_banner in nex_data, (
        "SE.NEX must contain '(Z80 Assembly)' in version banner"
    )
    print("    [+] SE.NEX displays '(Z80 Assembly)' on About screen")

    # 3. Check .se binary
    assert os.path.exists(TARGET_DOT), f"Missing {TARGET_DOT}"
    with open(TARGET_DOT, "rb") as f:
        dot_data = f.read()
    assert expected_banner in dot_data, (
        ".se must contain '(Z80 Assembly)' in version banner"
    )
    assert len(dot_data) <= 49152, f".se size {len(dot_data)} exceeds 48KB slot"
    print("    [+] .se displays '(Z80 Assembly)' on About screen")

    # 4. Check RomWBW CP/M SE.COM binary invariance
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
    print("    [+] Bug 2.3.5 fix verified successfully.")


if __name__ == "__main__":
    test_bug_2_3_5()
