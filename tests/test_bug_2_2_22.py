#!/usr/bin/env python3
"""
test_bug_2_2_22.py - Regression test for Bug 2.2.22:
Splash Screen Blank Gap Row Replacing Omitted [2] set 120x40.

Verifies:
1. SE_NEXT.COM builds cleanly via `make -B se-next-cpm`.
2. STR_SPLASH_CMDS in SE_NEXT.COM contains exactly 13 command lines (no empty
   CRLF row between `type   [1]              set 80x24` and
   `type   [Q]  or  [^Q]    to exit`).
3. RENDER_SPLASH in SE_NEXT.COM uses `SPLASH_MENU_LINES = 20` (`SUB 20`,
   `0xD6 0x14`) so the 20-line Splash Screen block centers cleanly on 80x24.
4. SE.COM (RomWBW) builds cleanly, retains 14 command lines (including
   `[2] set 120x40`) and `SPLASH_MENU_LINES = 21`, and stays byte-identical.
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


def read_c_str(code, addr):
    off = addr - ORG
    end = code.index(b"\x00", off)
    return code[off:end]


def test_bug_2_2_22():
    print("[*] Testing Bug 2.2.22: Splash Screen blank gap row removal in "
          "SE_NEXT.COM...")

    res = subprocess.run(
        ["make", "-B", "se-next-cpm", "SE.COM"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"make failed:\n{res.stderr}"

    map_path = os.path.join(PROJECT_DIR, "SE_NEXT.map")
    bin_path = os.path.join(PROJECT_DIR, "SE_NEXT.COM")
    symbols = parse_symbols(map_path)
    with open(bin_path, "rb") as f:
        code = f.read()

    # Step 2: Verify STR_SPLASH_CMDS has 13 non-empty lines and no blank gap
    # between [1] set 80x24 and [Q] or [^Q] to exit
    assert "STR_SPLASH_CMDS" in symbols, "STR_SPLASH_CMDS missing from map"
    splash_cmds = read_c_str(code, symbols["STR_SPLASH_CMDS"])
    assert b"\r\n\r\n" not in splash_cmds, (
        "STR_SPLASH_CMDS must not contain consecutive CRLF (blank gap row)"
    )
    expected_adj = (
        b"  type   [1]              set 80x24\r\n"
        b"  type   [Q]  or  [^Q]    to exit\r\n"
    )
    assert expected_adj in splash_cmds, (
        "STR_SPLASH_CMDS must go directly from [1] set 80x24 to [Q] to exit"
    )
    lines = splash_cmds.split(b"\r\n")
    assert lines[-1] == b"", "STR_SPLASH_CMDS must end with CRLF before NUL"
    cmd_lines = lines[:-1]
    assert len(cmd_lines) == 13, (
        f"Expected 13 splash command lines in SE_NEXT.COM, got "
        f"{len(cmd_lines)}"
    )

    # Step 3: Verify RENDER_SPLASH subtracts SPLASH_MENU_LINES = 20 (0xD6 0x14)
    assert "RENDER_SPLASH" in symbols, "RENDER_SPLASH missing from map"
    rs_off = symbols["RENDER_SPLASH"] - ORG
    rs_head = code[rs_off:rs_off + 32]
    assert b"\xd6\x14" in rs_head, (
        "RENDER_SPLASH in SE_NEXT.COM must use SUB 20 (SPLASH_MENU_LINES=20)"
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

    print("    [+] STR_SPLASH_CMDS has 13 contiguous command lines (no gap)")
    print("    [+] RENDER_SPLASH uses SPLASH_MENU_LINES = 20")
    print("    [+] SE.COM byte-for-byte invariance preserved")
    print("    [+] CCP headroom verified")
    print("    [+] Bug 2.2.22 fix verified successfully.")


if __name__ == "__main__":
    test_bug_2_2_22()
