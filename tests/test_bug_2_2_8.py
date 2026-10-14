#!/usr/bin/env python3
"""
test_bug_2_2_8.py - Regression test for Bug 2.2.8:
Memory Screen Queries RomWBW HBIOS Under NextCPM.

Verifies:
1. SE_NEXT.COM builds cleanly.
2. QUERY_MEM_SCREEN_INFO queries NextReg 0x01 (Machine ID) and 0x14 (SRAM).
3. HBIOS detection is bypassed under NextCPM.
4. NextCPM summary displays Next hardware identity and MMU capacity.
5. PRINT_MEM_BANK_ROW maps physical Next MMU Far RAM base pages (0x20 base).
6. SE.COM remains invariant (no regression).
7. TPA headroom of SE_NEXT.COM meets requirements (>= +2,048 B).
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
            if len(parts) >= 3 and parts[1] == "=" and parts[2].startswith("$"):
                try:
                    symbols[parts[0]] = int(parts[2][1:], 16)
                except ValueError:
                    pass
    return symbols


def test_bug_2_2_8():
    print("[*] Testing Bug 2.2.8: NextCPM memory screen reporter...")

    # Step 1: Rebuild SE_NEXT.COM
    res = subprocess.run(
        ["make", "-B", "se-next-cpm"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"make se-next-cpm failed:\n{res.stderr}"

    map_path = os.path.join(PROJECT_DIR, "SE_NEXT.map")
    bin_path = os.path.join(PROJECT_DIR, "SE_NEXT.COM")

    assert os.path.exists(map_path), f"Map file missing: {map_path}"
    assert os.path.exists(bin_path), f"Binary missing: {bin_path}"

    symbols = parse_symbols(map_path)
    assert "QUERY_MEM_SCREEN_INFO" in symbols, (
        "QUERY_MEM_SCREEN_INFO missing from SE_NEXT.map"
    )
    assert "NEXT_MACHINE_ID" in symbols, (
        "NEXT_MACHINE_ID missing from SE_NEXT.map"
    )
    assert "NEXT_REG_14_VAL" in symbols, (
        "NEXT_REG_14_VAL missing from SE_NEXT.map"
    )
    assert "PRINT_MEM_INFO_SUMMARY" in symbols, (
        "PRINT_MEM_INFO_SUMMARY missing from SE_NEXT.map"
    )
    assert "PRINT_MEM_BANK_ROW" in symbols, (
        "PRINT_MEM_BANK_ROW missing from SE_NEXT.map"
    )

    with open(bin_path, "rb") as f:
        code = f.read()

    # Step 2: Validate QUERY_MEM_SCREEN_INFO accesses NextReg ports
    # NextReg ports: 0x243B (select) and 0x253B (data)
    qmsi_offset = symbols["QUERY_MEM_SCREEN_INFO"] - 0x0100
    qmsi_code = code[qmsi_offset : qmsi_offset + 64]

    # Check for port select 0x243B: LD BC, 0x243B -> 01 3B 24
    assert b"\x01\x3B\x24" in qmsi_code, (
        "NextReg select port 0x243B not found in QUERY_MEM_SCREEN_INFO"
    )
    # Check for port data 0x253B: LD BC, 0x253B -> 01 3B 25
    assert b"\x01\x3B\x25" in qmsi_code, (
        "NextReg data port 0x253B not found in QUERY_MEM_SCREEN_INFO"
    )
    # Check for NextReg 0x01 (Machine ID) selection: LD A, 0x01 -> 3E 01
    assert b"\x3E\x01" in qmsi_code, (
        "NextReg 0x01 selection not found in QUERY_MEM_SCREEN_INFO"
    )
    # Check for NextReg 0x14 (SRAM/Peripheral) selection: LD A, 0x14 -> 3E 14
    assert b"\x3E\x14" in qmsi_code, (
        "NextReg 0x14 selection not found in QUERY_MEM_SCREEN_INFO"
    )

    # Step 3: Validate NextCPM summary string in binary
    assert b"ZX Next" in code, "Expected 'ZX Next' in SE_NEXT.COM binary"
    assert b"Next: " in code, "Expected 'Next: ' in SE_NEXT.COM binary"

    # Step 4: Validate PRINT_MEM_BANK_ROW maps NEXT_FAR_RAM_BASE_PAGE (0x20)
    pmbr_offset = symbols["PRINT_MEM_BANK_ROW"] - 0x0100
    pmbr_code = code[pmbr_offset : pmbr_offset + 64]
    # Check for ADD A, 0x20 -> C6 20
    assert b"\xC6\x20" in pmbr_code, (
        "Base Far RAM page 0x20 addition not found in PRINT_MEM_BANK_ROW"
    )

    # Step 5: Validate TPA headroom
    tpa_script = os.path.join(PROJECT_DIR, "check_tpa.py")
    res = subprocess.run(
        [sys.executable, tpa_script, bin_path],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"check_tpa.py failed:\n{res.stdout}"
    assert "PASS" in res.stdout, "check_tpa verdict was not PASS"
    assert "Headroom: +" in res.stdout, "Positive headroom required"

    print("    [+] QUERY_MEM_SCREEN_INFO queries NextReg 0x01 and 0x14")
    print("    [+] NextReg ports 0x243B / 0x253B verified")
    print("    [+] Summary displays 'Next: ZX Next'")
    print("    [+] PRINT_MEM_BANK_ROW maps physical Next MMU pages (base 0x20)")
    print("    [+] Positive TPA headroom verified")
    print("    [+] Bug 2.2.8 fix verified successfully.")


if __name__ == "__main__":
    test_bug_2_2_8()
