#!/usr/bin/env python3
"""
test_bug_2_3_14.py - Regression test for Bug 2.3.14:
Splash Screen Blank Gap Row Replacing Omitted [2] set 120x40 (Native Next).

Verifies:
1. SE.NEX and .se build cleanly via `make -B se-next-native`.
2. STR_SPLASH_CMDS in both SE_NEX.BIN and dot_se.bin (.se) contains exactly
   13 command lines (no empty CRLF row between `type   [1]              set
   80x24` and `type   [Q]  or  [^Q]    to exit`).
3. RENDER_SPLASH in both SE_NEX.BIN and dot_se.bin uses `SPLASH_MENU_LINES =
   20` (`SUB 20`, `0xD6 0x14`) so the 20-line Splash Screen block centers
   cleanly on 80x24.
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


def read_c_str(code, addr, org):
    off = addr - org
    end = code.index(b"\x00", off)
    return code[off:end]


def verify_target(bin_name, map_name, org):
    bin_path = os.path.join(PROJECT_DIR, bin_name)
    map_path = os.path.join(PROJECT_DIR, map_name)
    assert os.path.exists(bin_path), f"Missing {bin_path}"
    assert os.path.exists(map_path), f"Missing {map_path}"

    symbols = parse_symbols(map_path)
    with open(bin_path, "rb") as f:
        code = f.read()

    assert "STR_SPLASH_CMDS" in symbols, (
        f"STR_SPLASH_CMDS missing from {map_name}"
    )
    splash_cmds = read_c_str(code, symbols["STR_SPLASH_CMDS"], org)
    assert b"\r\n\r\n" not in splash_cmds, (
        f"{bin_name}: STR_SPLASH_CMDS must not contain consecutive CRLF "
        f"(blank gap row)"
    )
    expected_adj = (
        b"  type   [1]              set 80x24\r\n"
        b"  type   [Q]  or  [^Q]    to exit\r\n"
    )
    assert expected_adj in splash_cmds, (
        f"{bin_name}: STR_SPLASH_CMDS must go directly from [1] set 80x24 to "
        f"[Q] to exit"
    )
    lines = splash_cmds.split(b"\r\n")
    assert lines[-1] == b"", (
        f"{bin_name}: STR_SPLASH_CMDS must end with CRLF before NUL"
    )
    cmd_lines = lines[:-1]
    assert len(cmd_lines) == 13, (
        f"{bin_name}: Expected 13 splash command lines, got {len(cmd_lines)}"
    )

    assert "RENDER_SPLASH" in symbols, (
        f"RENDER_SPLASH missing from {map_name}"
    )
    rs_off = symbols["RENDER_SPLASH"] - org
    rs_head = code[rs_off:rs_off + 32]
    assert b"\xd6\x14" in rs_head, (
        f"{bin_name}: RENDER_SPLASH must use SUB 20 (SPLASH_MENU_LINES=20)"
    )
    return len(code)


def test_bug_2_3_14():
    print("[*] Testing Bug 2.3.14: Splash Screen blank gap row removal in "
          "SE.NEX and .se...")

    res = subprocess.run(
        ["make", "-B", "se-next-native"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"make se-next-native failed:\n{res.stderr}"

    verify_target("SE_NEX.BIN", "SE_NEX.map", 0x4000)
    dot_len = verify_target("dot_se.bin", "dot_se.map", 0x2000)
    assert dot_len <= 49152, f".se size {dot_len} exceeds 48KB slot"

    res = subprocess.run(
        ["git", "diff", "--exit-code", "--quiet", "SE.COM"],
        cwd=PROJECT_DIR,
    )
    assert res.returncode == 0, "SE.COM binary invariance broken"

    print("    [+] SE_NEX.BIN (SE.NEX) has 13 contiguous command lines and "
          "SPLASH_MENU_LINES = 20")
    print(f"    [+] dot_se.bin (.se) has 13 contiguous command lines and "
          f"SPLASH_MENU_LINES = 20 ({dot_len} B <= 49152 B)")
    print("    [+] SE.COM byte-for-byte invariance preserved")
    print("    [+] Bug 2.3.14 fix verified successfully.")


if __name__ == "__main__":
    test_bug_2_3_14()
