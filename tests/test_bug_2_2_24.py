#!/usr/bin/env python3
"""
test_bug_2_2_24.py - Regression test for Bug 2.2.24:
Far RAM Plugin Manager (PLUGIN.PRL) and Far-Mode Plugins Call RomWBW
0FFF9H (HB_BNKCALL) and 0FFF3H (HB_BNKSEL) Under NextCPM.

Verifies:
1. SE_NEXT.COM builds cleanly.
2. NEXT_BNKCALL and NEXT_BNKSEL exist in Upper Memory (>= 0x8000) in
   SE_NEXT.COM.
3. EXEC_PLUGIN_MGR_ACTION and EXEC_PLUGIN_FAR call NEXT_BNKCALL rather than
   0FFF9H, and Host API trampolines (TRAMP_CHECKOUT_LINE, TRAMP_COMMIT_LINE,
   TRAMP_PUTC, TRAMP_LOCATE_RC, TRAMP_FAR_CALL) call NEXT_BNKSEL rather than
   0FFF3H.
4. No CALL 0FFF3H (CD F3 FF) or CALL 0FFF9H (CD F9 FF) instructions remain in
   the plugin manager or trampoline regions of SE_NEXT.COM.
5. SE.COM byte-for-byte binary invariance and CCP headroom pass.
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


def test_bug_2_2_24():
    print("[*] Testing Bug 2.2.24: Next MMU bank switching in SE_NEXT.COM...")

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
        "NEXT_BNKCALL",
        "NEXT_BNKSEL",
        "NEXT_SAVED_MMU_SLOTS",
        "EXEC_PLUGIN_MGR_ACTION",
        "EXEC_PLUGIN_FAR",
        "TRAMP_CHECKOUT_LINE",
        "TRAMP_COMMIT_LINE",
        "TRAMP_PUTC",
        "TRAMP_LOCATE_RC",
        "TRAMP_FAR_CALL",
        "ENSURE_PLUGIN_MGR_LOADED",
    )
    for sym in required_syms:
        assert sym in symbols, f"{sym} missing from SE_NEXT.map"

    # Verify NEXT_BNKCALL and NEXT_BNKSEL reside in Upper Memory (>= 0x8000)
    assert symbols["NEXT_BNKCALL"] >= 0x8000, (
        f"NEXT_BNKCALL (${symbols['NEXT_BNKCALL']:04X}) must be >= $8000"
    )
    assert symbols["NEXT_BNKSEL"] >= 0x8000, (
        f"NEXT_BNKSEL (${symbols['NEXT_BNKSEL']:04X}) must be >= $8000"
    )

    with open(bin_path, "rb") as f:
        code = f.read()

    bnkcall_addr = symbols["NEXT_BNKCALL"]
    bnksel_addr = symbols["NEXT_BNKSEL"]
    call_next_bnkcall = bytes(
        [0xCD, bnkcall_addr & 0xFF, (bnkcall_addr >> 8) & 0xFF]
    )
    call_next_bnksel = bytes(
        [0xCD, bnksel_addr & 0xFF, (bnksel_addr >> 8) & 0xFF]
    )
    call_hb_bnkcall = bytes([0xCD, 0xF9, 0xFF])
    call_hb_bnksel = bytes([0xCD, 0xF3, 0xFF])

    # Check EXEC_PLUGIN_MGR_ACTION calls NEXT_BNKCALL and not 0FFF9H
    epma_start = symbols["EXEC_PLUGIN_MGR_ACTION"] - 0x0100
    epma_end = symbols["BORROW_PLUGIN_MGR_BANK"] - 0x0100
    epma_bytes = code[epma_start:epma_end]
    assert call_next_bnkcall in epma_bytes, (
        "EXEC_PLUGIN_MGR_ACTION does not call NEXT_BNKCALL"
    )
    assert call_hb_bnkcall not in epma_bytes, (
        "EXEC_PLUGIN_MGR_ACTION still calls 0FFF9H"
    )

    # Check EXEC_PLUGIN_FAR calls NEXT_BNKCALL and not 0FFF9H
    epf_start = symbols["EXEC_PLUGIN_FAR"] - 0x0100
    epf_end = symbols["RELOCATE_PRL_LOOP"] - 0x0100
    epf_bytes = code[epf_start:epf_end]
    assert call_next_bnkcall in epf_bytes, (
        "EXEC_PLUGIN_FAR does not call NEXT_BNKCALL"
    )
    assert call_hb_bnkcall not in epf_bytes, (
        "EXEC_PLUGIN_FAR still calls 0FFF9H"
    )

    # Check trampolines call NEXT_BNKSEL and not 0FFF3H
    tramp_start = symbols["TRAMP_CHECKOUT_LINE"] - 0x0100
    tramp_end = symbols["EXEC_PLUGIN_MGR_ACTION"] - 0x0100
    tramp_bytes = code[tramp_start:tramp_end]
    assert tramp_bytes.count(call_next_bnksel) >= 10, (
        "Expected at least 10 calls to NEXT_BNKSEL in plugin_tramp.asm"
    )
    assert call_hb_bnksel not in tramp_bytes, (
        "Host API trampolines still call 0FFF3H"
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

    print("    [+] NEXT_BNKCALL and NEXT_BNKSEL verified in Upper Memory")
    print("    [+] All 0FFF3H/0FFF9H calls replaced with Next MMU trampolines")
    print("    [+] SE.COM binary invariance and CCP headroom verified")
    print("[+] Bug 2.2.24 regression test PASSED.")


if __name__ == "__main__":
    test_bug_2_2_24()
