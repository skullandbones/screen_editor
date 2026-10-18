#!/usr/bin/env python3
"""
test_bug_2_3_13.py - Regression test for Bug 2.3.13:
Splash Screen Ctrl+S (^S) Not Dispatched in SPLASH_LOOP (Native Next).

Verifies:
1. SE.NEX and .se build cleanly via `make -B se-next-native`.
2. STR_SPLASH_CMDS in both SE_NEX.BIN and dot_se.bin (.se) displays:
     "type   [O]  or  [^O]    to open file"
     "type   [S]  or  [^S]    to save file"
3. SPLASH_LOOP in both SE_NEX.BIN (ORG $4000) and dot_se.bin (ORG $2000)
   dispatches 'o', 'O', and KEY_CTRL_O (0x0F) to HANDLE_SPLASH_OPEN, and
   dispatches 's', 'S', and KEY_CTRL_S (0x13) to DO_SPLASH_SAVE.
4. .se binary size fits within the 48KB NextZXOS execution slot.
5. SE.COM (RomWBW) stays byte-identical.
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


def cp_jp_z_bytes(imm8, target_addr):
    """Return Z80 machine code for `CP imm8` followed by `JP Z,target_addr`."""
    return bytes([0xFE, imm8 & 0xFF, 0xCA,
                  target_addr & 0xFF, (target_addr >> 8) & 0xFF])


def verify_target(bin_name, map_name, org):
    bin_path = os.path.join(PROJECT_DIR, bin_name)
    map_path = os.path.join(PROJECT_DIR, map_name)
    assert os.path.exists(bin_path), f"Missing {bin_path}"
    assert os.path.exists(map_path), f"Missing {map_path}"

    symbols = parse_symbols(map_path)
    with open(bin_path, "rb") as f:
        code = f.read()

    assert b"type   [O]  or  [^O]    to open file" in code, (
        f"{bin_name}: STR_SPLASH_CMDS missing [O] or [^O]"
    )
    assert b"type   [S]  or  [^S]    to save file" in code, (
        f"{bin_name}: STR_SPLASH_CMDS missing [S] or [^S]"
    )

    for sym in ("SPLASH_LOOP", "DO_SPLASH_SAVE", "HANDLE_SPLASH_OPEN"):
        assert sym in symbols, f"{sym} missing from {map_name}"

    splash_off = symbols["SPLASH_LOOP"] - org
    splash_block = code[splash_off:splash_off + 180]

    open_addr = symbols["HANDLE_SPLASH_OPEN"]
    for key_byte, key_name in ((ord("o"), "'o'"),
                               (ord("O"), "'O'"),
                               (0x0F, "KEY_CTRL_O")):
        seq = cp_jp_z_bytes(key_byte, open_addr)
        assert seq in splash_block, (
            f"{bin_name}: SPLASH_LOOP missing CP {key_name} -> "
            f"HANDLE_SPLASH_OPEN"
        )

    save_addr = symbols["DO_SPLASH_SAVE"]
    expected_save_seq = (
        cp_jp_z_bytes(ord("s"), save_addr)
        + cp_jp_z_bytes(ord("S"), save_addr)
        + cp_jp_z_bytes(0x13, save_addr)
    )
    assert expected_save_seq in splash_block, (
        f"{bin_name}: SPLASH_LOOP must dispatch 's', 'S', and KEY_CTRL_S "
        f"(0x13) consecutively to DO_SPLASH_SAVE"
    )
    return len(code)


def test_bug_2_3_13():
    print("[*] Testing Bug 2.3.13: Splash Screen Ctrl+S dispatch in "
          "SE.NEX and .se...")

    res = subprocess.run(
        ["make", "-B", "se-next-native"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"make se-next-native failed:\n{res.stderr}"

    # Verify SE_NEX.BIN (ORG $4000) and dot_se.bin / .se (ORG $2000)
    verify_target("SE_NEX.BIN", "SE_NEX.map", 0x4000)
    dot_len = verify_target("dot_se.bin", "dot_se.map", 0x2000)
    assert dot_len <= 49152, f".se size {dot_len} exceeds 48KB slot"

    # Verify SE.COM binary invariance
    res = subprocess.run(
        ["git", "diff", "--exit-code", "--quiet", "SE.COM"],
        cwd=PROJECT_DIR,
    )
    assert res.returncode == 0, "SE.COM binary invariance broken"

    print("    [+] SE_NEX.BIN (SE.NEX) SPLASH_LOOP dispatches 's', 'S', and "
          "KEY_CTRL_S (0x13) to DO_SPLASH_SAVE")
    print(f"    [+] dot_se.bin (.se) SPLASH_LOOP dispatches 's', 'S', and "
          f"KEY_CTRL_S (0x13) to DO_SPLASH_SAVE ({dot_len} B <= 49152 B)")
    print("    [+] SE.COM byte-for-byte invariance preserved")
    print("    [+] Bug 2.3.13 fix verified successfully.")


if __name__ == "__main__":
    test_bug_2_3_13()
