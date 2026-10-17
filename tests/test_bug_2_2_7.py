#!/usr/bin/env python3
"""
test_bug_2_2_7.py - Regression test for Bug 2.2.7:
Dedicated Next Delete Key Normalized to Backspace in NextCPM.

Verifies:
1. SE_NEXT.COM builds cleanly.
2. HAL_KEYBOARD_TRANSLATE does NOT translate 0x7F (NEXT_KEY_DELETE) to 0x08.
3. HAL_CONSOLE_GETKEY / GET_KEY routes console input through
   HAL_KEYBOARD_TRANSLATE to preserve forward deletion and block deletion.
4. TPA headroom of SE_NEXT.COM meets requirements (+2,048 B).
"""

import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)


def parse_symbols(sym_path):
    symbols = {}
    with open(sym_path, "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 3 and parts[1] == "=" and parts[2].startswith("$"):
                try:
                    symbols[parts[0]] = int(parts[2][1:], 16)
                except ValueError:
                    pass
    return symbols


def test_bug_2_2_7():
    print("[*] Testing Bug 2.2.7: NextCPM Delete key preservation...")

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
    assert "HAL_KEYBOARD_TRANSLATE" in symbols, (
        "HAL_KEYBOARD_TRANSLATE missing from symbols"
    )
    assert "HAL_CONSOLE_GETKEY" in symbols, (
        "HAL_CONSOLE_GETKEY missing from symbols"
    )

    with open(bin_path, "rb") as f:
        code = f.read()

    trans_addr = symbols["HAL_KEYBOARD_TRANSLATE"]
    trans_offset = trans_addr - 0x0100
    assert 0 <= trans_offset < len(code), (
        f"Invalid offset for HAL_KEYBOARD_TRANSLATE: 0x{trans_addr:04X}"
    )

    # Verify HAL_KEYBOARD_TRANSLATE preserves 0x7F (CP 0x7F / JP Z)
    trans_bytes = code[trans_offset : trans_offset + 16]
    assert bytes([0xFE, 0x7F]) in trans_bytes, (
        "HAL_KEYBOARD_TRANSLATE must check 0x7F to preserve Delete key"
    )

    # Verify old translation pattern (FE 7F ... 3E 08) is absent
    old_pattern = bytes([0xFE, 0x7F, 0xC0, 0x3E, 0x08, 0xC9])
    assert old_pattern not in trans_bytes, (
        "Detected legacy translation of 0x7F to 0x08"
    )

    # Verify console input hooks HAL_KEYBOARD_TRANSLATE
    call_opcode = 0xCD
    expected_call = bytes(
        [call_opcode, trans_addr & 0xFF, (trans_addr >> 8) & 0xFF]
    )
    assert expected_call in code, (
        "Console input does not call HAL_KEYBOARD_TRANSLATE"
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
    assert "Headroom: +" in res.stdout, "Headroom must be positive"

    print("    [+] HAL_KEYBOARD_TRANSLATE preserves 0x7F (Delete)")
    print("    [+] Console input hooks HAL_KEYBOARD_TRANSLATE")
    print("    [+] TPA headroom verified")
    print("    [+] Bug 2.2.7 fix verified successfully.")


if __name__ == "__main__":
    test_bug_2_2_7()
