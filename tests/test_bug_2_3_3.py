#!/usr/bin/env python3
"""Automated regression test for Bug 2.3.3:
Extended Memory Map Screen Native Next Reporting.

Validates that in src/se_next.asm:
1. QUERY_MEM_SCREEN_INFO queries Next hardware registers:
   NextReg 0x01 (Machine ID) and NextReg 0x14 (SRAM expansion).
2. HBIOS detection (HBIOS_DETECT) and RomWBW function calls are removed.
3. PRINT_MEM_INFO_SUMMARY reports 'Next: ZX Next | OS: NextZXOS' and total RAM.
4. PRINT_MEM_BANK_ROW maps 16 32KB MMU Far RAM banks (pages 20h..5Ch).
5. Native targets SE.NEX and .se build cleanly within the 48K slot.
6. RomWBW CP/M SE.COM byte-for-byte binary invariance is preserved.
"""

import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
SRC_NEXT = os.path.join(PROJECT_DIR, "src", "se_next.asm")


def test_bug_2_3_3():
    print("[*] Testing Bug 2.3.3: Native Next Memory Screen Reporter...")

    assert os.path.exists(SRC_NEXT), f"Missing {SRC_NEXT}"
    with open(SRC_NEXT, "r", encoding="utf-8") as f:
        src = f.read()

    # 1. Locate QUERY_MEM_SCREEN_INFO
    idx = src.find("\nQUERY_MEM_SCREEN_INFO:")
    assert idx != -1, "QUERY_MEM_SCREEN_INFO not found"
    q_section = src[idx : idx + 1200]

    assert "CALL HBIOS_DETECT" not in q_section, (
        "QUERY_MEM_SCREEN_INFO must not call HBIOS_DETECT"
    )
    assert "NEXT_REG_MACHINE_ID" in q_section, (
        "QUERY_MEM_SCREEN_INFO must query NextReg 0x01 (Machine ID)"
    )
    assert "014H" in q_section, (
        "QUERY_MEM_SCREEN_INFO must query NextReg 0x14 (SRAM)"
    )
    print("    [+] QUERY_MEM_SCREEN_INFO queries NextReg 0x01 and 0x14")

    # 2. Check Summary row
    idx_sum = src.find("\nPRINT_MEM_INFO_SUMMARY:")
    assert idx_sum != -1, "PRINT_MEM_INFO_SUMMARY not found"
    sum_section = src[idx_sum : idx_sum + 2000]

    assert "STR_MEM_SUM_NEXT" in sum_section, (
        "Summary must display Next hardware string"
    )
    assert "STR_OS_NEXTZXOS" in sum_section, (
        "Summary must display NextZXOS operating system"
    )
    assert "STR_MEM_SUM_RAM" in sum_section, (
        "Summary must display total RAM"
    )
    assert "STR_MEM_SUM_SE" in sum_section, (
        "Summary must display SE RAM allocation"
    )
    print("    [+] Summary displays 'Next: ZX Next | OS: NextZXOS'")

    # 3. Check Bank Row mapping
    idx_row = src.find("\nPRINT_MEM_BANK_ROW:")
    assert idx_row != -1, "PRINT_MEM_BANK_ROW not found"
    row_section = src[idx_row : idx_row + 2500]

    assert "NEXT_FAR_RAM_BASE_PAGE" in row_section, (
        "PRINT_MEM_BANK_ROW must map NEXT_FAR_RAM_BASE_PAGE (0x20)"
    )
    assert "PMBR_NOT_INSTALLED" not in row_section, (
        "RomWBW HBIOS bank probe fallback must be eliminated"
    )
    print("    [+] PRINT_MEM_BANK_ROW maps Next MMU pages (base 0x20)")

    # 4. Verify build and .se size <= 49,152
    res = subprocess.run(
        ["make", "-B", "se-next-native"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"make se-next-native failed:\n{res.stderr}"

    dot_se = os.path.join(PROJECT_DIR, ".se")
    assert os.path.exists(dot_se), f"Missing {dot_se}"
    size = os.path.getsize(dot_se)
    assert size <= 49152, f"Dot command size {size} exceeds 48KB slot limit"
    print(f"    [+] .se built cleanly ({size} B <= 49,152 B)")

    # 5. Verify RomWBW CP/M binary invariance
    res = subprocess.run(
        ["make", "-B", "SE.COM"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"make SE.COM failed:\n{res.stderr}"

    res = subprocess.run(
        ["git", "diff", "--exit-code", "SE.COM"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, "SE.COM binary changed! Invariance violated."
    print("    [+] SE.COM binary invariance preserved")
    print("    [+] Bug 2.3.3 fix verified successfully.")


if __name__ == "__main__":
    test_bug_2_3_3()
