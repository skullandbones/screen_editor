#!/usr/bin/env python3
"""Automated regression test for Bug 2.3.12:
File Browser Displays Native Path Syntax Under NextZXOS (SE.NEX and .se).

Validates that:
1. Native Next binaries SE.NEX and .se build cleanly.
2. Directory browser prompt string in SE.NEX and .se displays native path
   syntax '[path][pattern] to list (e.g. /dot/, *.TXT)' rather than CP/M
   user areas '[d:][u:][pattern]'.
3. Dot command binary size remains within the 48KB NextZXOS execution slot.
4. NextCPM SE_NEXT.COM retains CP/M drive/user area notation '[d:][u:]'.
5. RomWBW CP/M SE.COM byte-for-byte binary invariance is strictly preserved.
"""

import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
TARGET_NEX = os.path.join(PROJECT_DIR, "SE.NEX")
TARGET_DOT = os.path.join(PROJECT_DIR, ".se")
TARGET_NEXT_CPM = os.path.join(PROJECT_DIR, "SE_NEXT.COM")


def test_bug_2_3_12():
    print("[*] Testing Bug 2.3.12: Native Next File Browser Path Syntax...")

    # Step 1: Rebuild native Next targets
    res = subprocess.run(
        ["make", "-B", "se-next-native"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"make se-next-native failed:\n{res.stderr}"

    assert os.path.exists(TARGET_NEX), f"Missing {TARGET_NEX}"
    assert os.path.exists(TARGET_DOT), f"Missing {TARGET_DOT}"

    native_str = (
        b"[ESC]=Cancel  Enter [path][pattern] to list (e.g. /dot/, *.TXT)"
    )
    cpm_str = (
        b"[ESC]=Cancel  Enter [d:][u:][pattern] to list "
        b"(e.g. B:, C1:, 1C:, *.TXT)"
    )

    # Step 2: Validate SE.NEX contains native string and not CP/M string
    with open(TARGET_NEX, "rb") as f:
        nex_data = f.read()
    assert native_str in nex_data, (
        "SE.NEX must contain native path prompt syntax"
    )
    assert cpm_str not in nex_data, (
        "SE.NEX must not contain CP/M [d:][u:] prompt syntax"
    )
    print("    [+] SE.NEX displays native path syntax in file browser prompt")

    # Step 3: Validate .se contains native string and not CP/M string
    with open(TARGET_DOT, "rb") as f:
        dot_data = f.read()
    assert native_str in dot_data, (
        ".se must contain native path prompt syntax"
    )
    assert cpm_str not in dot_data, (
        ".se must not contain CP/M [d:][u:] prompt syntax"
    )
    assert len(dot_data) <= 49152, (
        f".se size {len(dot_data)} exceeds 48KB slot"
    )
    print(
        f"    [+] .se displays native path syntax (slot size: "
        f"{len(dot_data)} B <= 49152 B)"
    )

    # Step 4: Validate NextCPM SE_NEXT.COM retains CP/M drive/user notation
    res = subprocess.run(
        ["make", "-B", "se-next-cpm"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"make se-next-cpm failed:\n{res.stderr}"

    with open(TARGET_NEXT_CPM, "rb") as f:
        next_cpm_data = f.read()
    assert cpm_str in next_cpm_data, (
        "SE_NEXT.COM must retain CP/M [d:][u:] prompt syntax"
    )
    assert native_str not in next_cpm_data, (
        "SE_NEXT.COM must not contain native NextZXOS path syntax"
    )
    print("    [+] SE_NEXT.COM retains CP/M drive/user area prompt syntax")

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
    print("    [+] Bug 2.3.12 fix verified successfully.")


if __name__ == "__main__":
    test_bug_2_3_12()
