#!/usr/bin/env python3
"""
test_bug_2_2_21.py - Regression test for Bug 2.2.21:
Splash Screen Ctrl+S (^S) Not Dispatched in SPLASH_LOOP.

Verifies:
1. SE_NEXT.COM builds cleanly via `make -B se-next-cpm`.
2. STR_SPLASH_CMDS in SE_NEXT.COM displays:
     "type   [O]  or  [^O]    to open file"
     "type   [S]  or  [^S]    to save file"
3. SPLASH_LOOP in SE_NEXT.COM dispatches 'o', 'O', and KEY_CTRL_O (0x0F) to
   HANDLE_SPLASH_OPEN, and dispatches 's', 'S', and KEY_CTRL_S (0x13) to
   DO_SPLASH_SAVE.
4. SE.COM (RomWBW) stays byte-identical.
5. CCP headroom check (`check_ccp.py SE_NEXT.COM`) passes.
"""

import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
ORG = 0x0100


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


def test_bug_2_2_21():
    print("[*] Testing Bug 2.2.21: Splash Screen Ctrl+S dispatch in "
          "SE_NEXT.COM...")

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
    with open(bin_path, "rb") as f:
        code = f.read()

    # Step 2: Verify Splash Screen command strings advertise [^O] and [^S]
    assert b"type   [O]  or  [^O]    to open file" in code, (
        "STR_SPLASH_CMDS must contain 'type   [O]  or  [^O]    to open file'"
    )
    assert b"type   [S]  or  [^S]    to save file" in code, (
        "STR_SPLASH_CMDS must contain 'type   [S]  or  [^S]    to save file'"
    )

    # Step 3: Verify SPLASH_LOOP dispatches 's', 'S', and KEY_CTRL_S (0x13)
    # to DO_SPLASH_SAVE, and 'o', 'O', and KEY_CTRL_O (0x0F) to
    # HANDLE_SPLASH_OPEN.
    for sym in ("SPLASH_LOOP", "DO_SPLASH_SAVE", "HANDLE_SPLASH_OPEN"):
        assert sym in symbols, f"{sym} missing from SE_NEXT.map"

    splash_off = symbols["SPLASH_LOOP"] - ORG
    # Bound the search to the SPLASH_LOOP dispatch block (~160 bytes)
    splash_block = code[splash_off:splash_off + 180]

    open_addr = symbols["HANDLE_SPLASH_OPEN"]
    for key_byte, key_name in ((ord("o"), "'o'"),
                               (ord("O"), "'O'"),
                               (0x0F, "KEY_CTRL_O")):
        seq = cp_jp_z_bytes(key_byte, open_addr)
        assert seq in splash_block, (
            f"SPLASH_LOOP missing CP {key_name} / JP Z,HANDLE_SPLASH_OPEN"
        )

    save_addr = symbols["DO_SPLASH_SAVE"]
    expected_save_seq = (
        cp_jp_z_bytes(ord("s"), save_addr)
        + cp_jp_z_bytes(ord("S"), save_addr)
        + cp_jp_z_bytes(0x13, save_addr)
    )
    assert expected_save_seq in splash_block, (
        "SPLASH_LOOP must dispatch 's', 'S', and KEY_CTRL_S (0x13) "
        "consecutively to DO_SPLASH_SAVE"
    )

    # Step 4: Verify SE.COM binary invariance
    res = subprocess.run(
        ["git", "diff", "--exit-code", "--quiet", "SE.COM"],
        cwd=PROJECT_DIR,
    )
    assert res.returncode == 0, "SE.COM binary invariance broken"

    # Step 5: Verify CCP headroom
    res = subprocess.run(
        [sys.executable, os.path.join(PROJECT_DIR, "check_ccp.py"), bin_path],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"check_ccp.py failed:\n{res.stdout}"

    print("    [+] STR_SPLASH_CMDS advertises [O] or [^O] and [S] or [^S]")
    print("    [+] SPLASH_LOOP dispatches 's', 'S', and KEY_CTRL_S (0x13) "
          "to DO_SPLASH_SAVE")
    print("    [+] SE.COM byte-for-byte invariance preserved")
    print("    [+] CCP headroom verified")
    print("    [+] Bug 2.2.21 fix verified successfully.")


if __name__ == "__main__":
    test_bug_2_2_21()
