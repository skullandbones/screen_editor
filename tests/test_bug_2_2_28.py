#!/usr/bin/env python3
"""
test_bug_2_2_28.py - Regression test for Bug 2.2.28:
Exit Banner and Extended Memory Map Title Hardcode SE.COM Instead of the
Actual Executable Name (src/core/plugin_mgr.asm & src/se_next_cpm.asm).

Verifies:
1. SE_NEXT.COM builds cleanly.
2. Both SE_NEXT.COM and SE.COM variants of the Memory Map title, table header,
   and Exit Banner exist in SE_NEXT.COM (STR_MEM_INFO_TITLE_NEXT /
   STR_MEM_INFO_TITLE, STR_MEM_TABLE_HDR_NEXT / STR_MEM_TABLE_HDR, and
   MSG_EXIT_NEXT / MSG_EXIT).
3. SHOW_MEM_INFO_SCREEN and EXIT_PROGRAM read EXEC_IS_SE_COM to dynamically
   select the matching executable name strings.
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


def test_bug_2_2_28():
    print("[*] Testing Bug 2.2.28: Dynamic executable name in UI & exit...")

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

    required_syms = (
        "EXEC_IS_SE_COM",
        "STR_MEM_TITLE_PAD_NEXT",
        "STR_MEM_TITLE_PAD",
        "STR_MEM_INFO_TITLE_NEXT",
        "STR_MEM_INFO_TITLE",
        "STR_MEM_TABLE_HDR_NEXT",
        "STR_MEM_TABLE_HDR",
        "MSG_EXIT_NEXT",
        "MSG_EXIT",
        "EXIT_PROGRAM",
        "MEM_INFO_CONTENT_START",
    )
    for sym in required_syms:
        assert sym in symbols, f"{sym} missing from SE_NEXT.map"

    with open(bin_path, "rb") as f:
        code = f.read()

    # Check string contents
    assert b"SE_NEXT.COM - Extended Memory Map\r\n$" in code
    assert b"SE.COM - Extended Memory Map\r\n$" in code
    assert (
        b"Bank  Phys   Size   System / OS Role        SE_NEXT.COM Usage\r\n$"
        in code
    )
    assert (
        b"Bank  Phys   Size   System / OS Role        SE.COM Usage\r\n$"
        in code
    )
    assert b"\r\nExiting SE_NEXT.COM. Returned to CP/M.\r\n$" in code
    assert b"\r\nExiting SE.COM. Returned to CP/M.\r\n$" in code

    # Check that EXIT_PROGRAM and SHOW_MEM_INFO_SCREEN inspect EXEC_IS_SE_COM
    exec_flag_addr = symbols["EXEC_IS_SE_COM"]
    ld_a_exec_flag = bytes(
        [0x3A, exec_flag_addr & 0xFF, (exec_flag_addr >> 8) & 0xFF]
    )

    ep_start = symbols["EXIT_PROGRAM"] - 0x0100
    ep_end = symbols["SET_MODE_120X40"] - 0x0100
    assert ld_a_exec_flag in code[ep_start:ep_end], (
        "EXIT_PROGRAM does not check EXEC_IS_SE_COM"
    )

    smis_start = symbols["MEM_INFO_CONTENT_START"] - 0x0100
    smis_end = symbols["MEM_BANK_ROW_LOOP"] - 0x0100
    assert code[smis_start:smis_end].count(ld_a_exec_flag) == 2, (
        "SHOW_MEM_INFO_SCREEN should check EXEC_IS_SE_COM for title & header"
    )

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

    print("    [+] Both SE_NEXT.COM and SE.COM UI/exit strings verified")
    print("    [+] Dynamic selection via EXEC_IS_SE_COM verified")
    print("    [+] SE.COM binary invariance and CCP headroom verified")
    print("[+] Bug 2.2.28 regression test PASSED.")


if __name__ == "__main__":
    test_bug_2_2_28()
