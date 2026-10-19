#!/usr/bin/env python3
"""
test_bug_2_2_25.py - Regression test for Bug 2.2.25:
Max Document Lines (CFG_LINES_MODE) Hardcoded to 32K in NEXTCPM_MEM_INIT,
Ignoring SE.CFG and Configuration Manager [3] Toggle.

Verifies:
1. SE_NEXT.COM builds cleanly.
2. NEXTCPM_MEM_INIT checks CFG_LINES_MODE (LD A,(CFG_LINES_MODE)) and branches
   between MAX_DOC_LINES_16K (16,384) and MAX_DOC_LINES_32K (32,768).
3. PRINT_MEM_BANK_ROW (PMBR_LINE_0 and PMBR_LINE_1) checks CFG_LINES_MODE so
   Bank 00 and Bank 01 display 16K vs 32K usage accurately.
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


def test_bug_2_2_25():
    print("[*] Testing Bug 2.2.25: CFG_LINES_MODE 16K/32K in SE_NEXT.COM...")

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
        "NEXTCPM_MEM_INIT",
        "NCMI_MODE_32K",
        "NCMI_SET_LIMIT",
        "NEXT_SYSSETCPY",
        "CFG_LINES_MODE",
        "MAX_DOC_LINES_LIMIT",
        "PMBR_LINE_0",
        "PMBR_LINE_1",
        "PMBR_DOC_BANK",
    )
    for sym in required_syms:
        assert sym in symbols, f"{sym} missing from SE_NEXT.map"

    with open(bin_path, "rb") as f:
        code = f.read()

    cfg_lines_addr = symbols["CFG_LINES_MODE"]
    ld_a_cfg_lines = bytes(
        [0x3A, cfg_lines_addr & 0xFF, (cfg_lines_addr >> 8) & 0xFF]
    )
    ld_hl_16k = bytes([0x21, 0x00, 0x40])  # MAX_DOC_LINES_16K = 0x4000
    ld_hl_32k = bytes([0x21, 0x00, 0x80])  # MAX_DOC_LINES_32K = 0x8000

    ncmi_start = symbols["NEXTCPM_MEM_INIT"] - 0x0100
    ncmi_end = symbols["NEXT_SYSSETCPY"] - 0x0100
    ncmi_bytes = code[ncmi_start:ncmi_end]

    assert ld_a_cfg_lines in ncmi_bytes, (
        "NEXTCPM_MEM_INIT does not read CFG_LINES_MODE"
    )
    assert ld_hl_16k in ncmi_bytes, (
        "NEXTCPM_MEM_INIT does not load MAX_DOC_LINES_16K (0x4000)"
    )
    assert ld_hl_32k in ncmi_bytes, (
        "NEXTCPM_MEM_INIT does not load MAX_DOC_LINES_32K (0x8000)"
    )

    pmbr_start = symbols["PMBR_LINE_0"] - 0x0100
    pmbr_end = symbols["PMBR_DOC_BANK"] - 0x0100
    pmbr_bytes = code[pmbr_start:pmbr_end]
    assert pmbr_bytes.count(ld_a_cfg_lines) == 2, (
        "Expected PMBR_LINE_0 and PMBR_LINE_1 to both check CFG_LINES_MODE"
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

    print("    [+] NEXTCPM_MEM_INIT honors CFG_LINES_MODE (16K vs 32K)")
    print("    [+] PRINT_MEM_BANK_ROW reflects 16K/32K for Bank 00 & Bank 01")
    print("    [+] SE.COM binary invariance and CCP headroom verified")
    print("[+] Bug 2.2.25 regression test PASSED.")


if __name__ == "__main__":
    test_bug_2_2_25()
