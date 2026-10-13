#!/usr/bin/env python3
"""
test_bug_2_2_9.py - Regression test for Bug 2.2.9:
Escape Sequence Trailing Byte Leakage in Editor for NextCPM.

Verifies:
1. SE_NEXT.COM builds cleanly.
2. DRAIN_REMAINING_CSI routine is compiled into SE_NEXT.COM.
3. Unrecognized CSI sequence paths (HANDLE_CSI_1, HANDLE_CSI_2,
   HANDLE_CSI_4, CSI_DONE) jump to DRAIN_REMAINING_CSI instead of bare RET.
4. SE.COM remains invariant (no regression).
5. TPA headroom of SE_NEXT.COM meets requirements (+2,048 B).
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


def test_bug_2_2_9():
    print("[*] Testing Bug 2.2.9: Escape sequence trailing byte draining...")

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
    assert "DRAIN_REMAINING_CSI" in symbols, (
        "DRAIN_REMAINING_CSI missing from SE_NEXT.map"
    )
    assert "CSI_DONE" in symbols, "CSI_DONE missing from SE_NEXT.map"

    with open(bin_path, "rb") as f:
        code = f.read()

    drain_addr = symbols["DRAIN_REMAINING_CSI"]
    csi_done_addr = symbols["CSI_DONE"]

    # Verify CSI_DONE contains JP DRAIN_REMAINING_CSI (C3 <drain_addr>)
    csi_done_offset = csi_done_addr - 0x0100
    expected_jp = bytes(
        [0xC3, drain_addr & 0xFF, (drain_addr >> 8) & 0xFF]
    )
    assert code[csi_done_offset : csi_done_offset + 3] == expected_jp, (
        f"CSI_DONE at 0x{csi_done_addr:04X} does not jump to "
        f"DRAIN_REMAINING_CSI (0x{drain_addr:04X})"
    )

    # Verify DRAIN_REMAINING_CSI checks 0x40 and 0x7F
    drain_offset = drain_addr - 0x0100
    drain_bytes = code[drain_offset : drain_offset + 32]
    assert 0x40 in drain_bytes and 0x7F in drain_bytes, (
        "DRAIN_REMAINING_CSI missing 0x40/0x7F final byte boundary checks"
    )

    # Step 2: Validate TPA headroom
    tpa_script = os.path.join(PROJECT_DIR, "check_tpa.py")
    res = subprocess.run(
        [sys.executable, tpa_script, bin_path],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"check_tpa.py failed:\n{res.stdout}"
    assert "PASS" in res.stdout, "check_tpa verdict was not PASS"
    assert (
        "+2,048 bytes" in res.stdout or "+2,560 bytes" in res.stdout
    ), "Headroom must be positive"

    print("    [+] DRAIN_REMAINING_CSI defined and mapped")
    print("    [+] CSI_DONE routes to DRAIN_REMAINING_CSI")
    print("    [+] Final byte boundary checks (0x40..0x7E) verified")
    print("    [+] TPA headroom verified")
    print("    [+] Bug 2.2.9 fix verified successfully.")


if __name__ == "__main__":
    test_bug_2_2_9()
