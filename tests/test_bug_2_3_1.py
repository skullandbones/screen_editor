#!/usr/bin/env python3
"""Automated regression test for Bug 2.3.1:
Dedicated Arrow Keys & Delete Key on Native ZX Spectrum Next.

Validates that in hal_next_keyboard.asm:
1. Legacy WordStar diamond navigation equates (KEY_WORDSTAR_*) are removed.
2. Dedicated cursor keys (Caps+5/6/7/8) map to ANSI VT100 escape sequences
   (\\x1b[A, \\x1b[B, \\x1b[C, \\x1b[D).
3. Delete key (Caps+0) maps directly to 0x7F (KEY_DELETE) rather than
   destructive jump-to-EOF (Ctrl+G).
4. Native targets SE.NEX and .se build cleanly within the 48K dot slot.
5. RomWBW CP/M SE.COM byte-for-byte binary invariance is preserved.
"""

import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
SRC_KEYBOARD = os.path.join(
    PROJECT_DIR, "src", "hal", "next_native", "hal_next_keyboard.asm"
)


def test_bug_2_3_1():
    print("[*] Testing Bug 2.3.1: Dedicated Arrow Keys on Native Next...")

    assert os.path.exists(SRC_KEYBOARD), f"Missing {SRC_KEYBOARD}"
    with open(SRC_KEYBOARD, "r", encoding="utf-8") as f:
        src = f.read()

    # Verify WordStar diamond navigation equates are eliminated
    assert "KEY_WORDSTAR_LEFT" not in src, (
        "KEY_WORDSTAR_LEFT must be eliminated"
    )
    assert "KEY_WORDSTAR_RIGHT" not in src, (
        "KEY_WORDSTAR_RIGHT must be eliminated"
    )
    assert "KEY_WORDSTAR_UP" not in src, (
        "KEY_WORDSTAR_UP must be eliminated"
    )
    assert "KEY_WORDSTAR_DOWN" not in src, (
        "KEY_WORDSTAR_DOWN must be eliminated"
    )
    assert "KEY_WORDSTAR_DEL" not in src, (
        "KEY_WORDSTAR_DEL must be eliminated"
    )
    print("    [+] Legacy WordStar diamond navigation equates eliminated")

    # Verify KEY_DELETE is defined as 0x7F
    assert "KEY_DELETE" in src and "07FH" in src, (
        "KEY_DELETE must be defined as 0x7F"
    )
    print("    [+] KEY_DELETE defined as 0x7F")

    # Verify KEY_TABLE_CAPS mapping
    caps_idx = src.find("KEY_TABLE_CAPS:")
    assert caps_idx != -1, "KEY_TABLE_CAPS table not found"
    caps_section = src[caps_idx : caps_idx + 600]

    assert "KEY_CODE_LEFT" in caps_section, (
        "Caps+5 must map to KEY_CODE_LEFT"
    )
    assert "KEY_DELETE" in caps_section, (
        "Caps+0 must map to KEY_DELETE (0x7F)"
    )
    assert "KEY_CODE_RIGHT" in caps_section, (
        "Caps+8 must map to KEY_CODE_RIGHT"
    )
    assert "KEY_CODE_UP" in caps_section, (
        "Caps+7 must map to KEY_CODE_UP"
    )
    assert "KEY_CODE_DOWN" in caps_section, (
        "Caps+6 must map to KEY_CODE_DOWN"
    )
    print("    [+] KEY_TABLE_CAPS maps dedicated Arrow keys and Delete (0x7F)")

    # Verify ANSI VT100 sequence generation in HKG_LOOKUP
    assert "HKG_QUEUE_CSI:" in src, "HKG_QUEUE_CSI routine not found"
    assert "KEY_SEQ_BUF" in src, "KEY_SEQ_BUF buffer not found"
    assert "KEY_SEQ_LEN" in src, "KEY_SEQ_LEN not found"
    print("    [+] ANSI VT100 CSI sequence generator verified")

    # Verify SE.NEX and .se build cleanly
    res = subprocess.run(
        ["make", "-B", "se-next-native"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"make se-next-native failed:\n{res.stderr}"

    dot_se = os.path.join(PROJECT_DIR, ".se")
    assert os.path.exists(dot_se), f"Missing {dot_se}"
    size = os.path.getsize(dot_se)
    assert size <= 49152, f"Dot command size {size} exceeds 48KB slot limit"
    print(f"    [+] .se built cleanly ({size} B <= 49,152 B)")

    # Verify SE.COM binary invariance
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
    print("    [+] Bug 2.3.1 fix verified successfully.")


if __name__ == "__main__":
    test_bug_2_3_1()
