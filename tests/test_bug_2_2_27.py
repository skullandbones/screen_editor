#!/usr/bin/env python3
"""
test_bug_2_2_27.py - Regression test for Bug 2.2.27:
PROBE_PROGRAM_DRIVE Only Searches for SE.COM and Fails When Binary is Named
SE_NEXT.COM (src/core/config.asm).

Verifies:
1. SE_NEXT.COM builds cleanly.
2. PROBE_DRIVE_EXECUTABLE, INIT_NEXT_COM_PROBE_FCB, INIT_COM_PROBE_FCB,
   STR_PROBE_SE_NEXT ("SE_NEXT COM"), STR_PROBE_SE_COM ("SE      COM"), and
   EXEC_IS_SE_COM exist in SE_NEXT.COM.
3. LOAD_CONFIG and PROBE_PROGRAM_DRIVE invoke PROBE_DRIVE_EXECUTABLE to detect
   either SE_NEXT.COM or SE.COM on the current drive and logged-in drives.
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


def test_bug_2_2_27():
    print("[*] Testing Bug 2.2.27: Dual-name program drive probing...")

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
        "LOAD_CONFIG",
        "PROBE_PROGRAM_DRIVE",
        "PROBE_DRIVE_EXECUTABLE",
        "INIT_NEXT_COM_PROBE_FCB",
        "INIT_COM_PROBE_FCB",
        "STR_PROBE_SE_NEXT",
        "STR_PROBE_SE_COM",
        "EXEC_IS_SE_COM",
    )
    for sym in required_syms:
        assert sym in symbols, f"{sym} missing from SE_NEXT.map"

    with open(bin_path, "rb") as f:
        code = f.read()

    # Verify probe FCB strings
    se_next_off = symbols["STR_PROBE_SE_NEXT"] - 0x0100
    se_com_off = symbols["STR_PROBE_SE_COM"] - 0x0100
    assert code[se_next_off : se_next_off + 11] == b"SE_NEXT COM"
    assert code[se_com_off : se_com_off + 11] == b"SE      COM"

    # Verify LOAD_CONFIG and PROBE_PROGRAM_DRIVE call PROBE_DRIVE_EXECUTABLE
    pde_addr = symbols["PROBE_DRIVE_EXECUTABLE"]
    call_pde = bytes([0xCD, pde_addr & 0xFF, (pde_addr >> 8) & 0xFF])

    lc_start = symbols["LOAD_CONFIG"] - 0x0100
    ppd_end = symbols["READ_CFG_RECORD"] - 0x0100
    assert code[lc_start:ppd_end].count(call_pde) == 2, (
        "Expected LOAD_CONFIG and PROBE_PROGRAM_DRIVE to call "
        "PROBE_DRIVE_EXECUTABLE"
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

    print("    [+] Dual-name FCB probing (SE_NEXT.COM & SE.COM) verified")
    print("    [+] SE.COM binary invariance and CCP headroom verified")
    print("[+] Bug 2.2.27 regression test PASSED.")


if __name__ == "__main__":
    test_bug_2_2_27()
