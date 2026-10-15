#!/usr/bin/env python3
"""
test_bug_2_2_15.py - Regression test for Bug 2.2.15:
Visible Cursor on Splash, Memory, Configure, and Modal Pop-up Screens.

The NextCPM console emulates a Zenith Z-19 terminal plus the Locomotive
Spectrum +3 extensions (see the NextZXOS CP/M terminal documentation). It
does not implement the DEC private mode sequences ESC [ ? 25 l / h, so
SE_NEXT.COM must hide/show the cursor with ESC f / ESC e instead.

Verifies:
1. SE_NEXT.COM builds cleanly.
2. TERM_HIDE_CURSOR emits ESC f and TERM_SHOW_CURSOR emits ESC e.
3. Splash, Memory Info, Configure and About screens finish rendering with
   CALL TERM_HIDE_CURSOR, as does the Tier 2 status event pop-up.
4. SE.COM (RomWBW) still uses ESC [ ? 25 l / h and stays byte-identical.
5. CCP headroom check for SE_NEXT.COM still passes.
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
            if len(parts) >= 3 and parts[1] == "=" and parts[2].startswith("$"):
                try:
                    symbols[parts[0]] = int(parts[2][1:], 16)
                except ValueError:
                    pass
    return symbols


def call_bytes(addr):
    return bytes([0xCD, addr & 0xFF, (addr >> 8) & 0xFF])


def ld_de_target(code, symbols, label):
    """Return the 16-bit operand of the LD DE,nn at the start of label."""
    off = symbols[label] - ORG
    assert code[off] == 0x11, f"{label} must start with LD DE,nn"
    return code[off + 1] | (code[off + 2] << 8)


def read_dollar_str(code, addr):
    off = addr - ORG
    end = code.index(b"$", off)
    return code[off:end]


def test_bug_2_2_15():
    print("[*] Testing Bug 2.2.15: NextCPM cursor hide/show sequences...")

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

    # Step 2: hide/show routines emit the NextCPM (+3) sequences
    hide_str = read_dollar_str(
        code, ld_de_target(code, symbols, "TERM_HIDE_CURSOR"))
    show_str = read_dollar_str(
        code, ld_de_target(code, symbols, "TERM_SHOW_CURSOR"))
    assert hide_str == b"\x1bf", (
        f"TERM_HIDE_CURSOR must emit ESC f, got {hide_str!r}")
    assert show_str == b"\x1be", (
        f"TERM_SHOW_CURSOR must emit ESC e, got {show_str!r}")

    # Step 3: non-input screens and pop-ups end with the cursor hidden
    hide_call = call_bytes(symbols["TERM_HIDE_CURSOR"])
    checks = {
        "SPLASH_BOTTOM_DONE": 12,       # Splash screen
        "MEM_INFO_BOTTOM_DONE": 12,     # Memory Info screen
        "SCS_FOOTER_DONE": 12,          # Configure screen
        "ABOUT_BOTTOM_DONE": 12,        # About screen
        "SHOW_STATUS_EVENT_POPUP": 64,  # Tier 2 pop-ups (Plugin Mgr etc.)
    }
    for label, span in checks.items():
        assert label in symbols, f"{label} missing from SE_NEXT.map"
        off = symbols[label] - ORG
        assert hide_call in code[off:off + span], (
            f"{label} must CALL TERM_HIDE_CURSOR")

    # Step 4: SE.COM keeps DEC sequences and stays byte-identical
    res = subprocess.run(
        ["git", "diff", "--exit-code", "--quiet", "SE.COM"],
        cwd=PROJECT_DIR,
    )
    assert res.returncode == 0, "SE.COM binary invariance broken"
    with open(os.path.join(PROJECT_DIR, "SE.COM"), "rb") as f:
        se_com = f.read()
    assert b"\x1b[?25l$" in se_com, "SE.COM must still hide via ESC[?25l"

    # Step 5: CCP headroom
    res = subprocess.run(
        [sys.executable, os.path.join(PROJECT_DIR, "check_ccp.py"),
         bin_path],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"check_ccp.py failed:\n{res.stdout}"

    print("    [+] TERM_HIDE_CURSOR emits ESC f (disable cursor blob)")
    print("    [+] TERM_SHOW_CURSOR emits ESC e (enable cursor blob)")
    print("    [+] Splash/Memory/Configure/About/pop-ups hide the cursor")
    print("    [+] SE.COM byte-for-byte invariance preserved")
    print("    [+] CCP headroom verified")
    print("    [+] Bug 2.2.15 fix verified successfully.")


if __name__ == "__main__":
    test_bug_2_2_15()
