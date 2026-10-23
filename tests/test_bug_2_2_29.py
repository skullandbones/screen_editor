#!/usr/bin/env python3
"""
test_bug_2_2_29.py - Regression test for Bug 2.2.29:
SE_NEXT.COM crashes to prompt when accessing NextZXOS drives (C:, M:, etc.)
from file-related screens.

Verifies:
1. SE_NEXT.COM and NEXTFS.PRL build cleanly.
2. SE_NEXT.map exports NEXTCPM_USERF_VEC, NEXTCPM_INIT_DRV_TABLES,
   NEXTCPM_CLASSIFY_DRIVE, TRAMP_NEXTCPM_USERF, STR_NEXTFS_PRL,
   NEXTCPM_CPM_TO_NEXT, and NEXTCPM_NEXT_TO_CPM.
3. Host API jump table at HOST_API_MGR_SLOT + 82 contains trampoline to
   TRAMP_NEXTCPM_USERF, NEXTCPM_CPM_TO_NEXT, and NEXTCPM_NEXT_TO_CPM.
4. NEXTFS.PRL conforms to PRL ABI with CAP_HAS_VFS (0x015A).
5. SE.COM byte-for-byte binary invariance is preserved.
6. CCP headroom passes on both SE.COM and SE_NEXT.COM.
"""

import os
import struct
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


def test_bug_2_2_29():
    print("[*] Testing Bug 2.2.29: NextCPM VFS & NextZXOS Drive Access...")

    # 1. Build SE_NEXT.COM and plugins
    res = subprocess.run(
        ["make", "SE_NEXT.COM", "plugins"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"make failed:\n{res.stderr}"

    bin_path = os.path.join(PROJECT_DIR, "SE_NEXT.COM")
    map_path = os.path.join(PROJECT_DIR, "SE_NEXT.map")
    prl_path = os.path.join(PROJECT_DIR, "plugins", "NEXTFS.PRL")

    assert os.path.exists(bin_path), "SE_NEXT.COM not found"
    assert os.path.exists(map_path), "SE_NEXT.map not found"
    assert os.path.exists(prl_path), "NEXTFS.PRL not found"

    symbols = parse_symbols(map_path)

    # 2. Check required symbols in SE_NEXT.map
    required_symbols = [
        "NEXTCPM_USERF_VEC",
        "NEXTCPM_INIT_DRV_TABLES",
        "NEXTCPM_CLASSIFY_DRIVE",
        "TRAMP_NEXTCPM_USERF",
        "STR_NEXTFS_PRL",
        "NEXTCPM_CPM_TO_NEXT",
        "NEXTCPM_NEXT_TO_CPM",
        "PLUGIN_HOST_API",
    ]
    for sym in required_symbols:
        assert sym in symbols, f"Missing symbol in SE_NEXT.map: {sym}"

    # 3. Verify Host API jump table layout in SE_NEXT.COM
    with open(bin_path, "rb") as f:
        code = f.read()

    host_api_offset = symbols["PLUGIN_HOST_API"] - 0x0100
    userf_slot = host_api_offset + 82
    jp_opcode = code[userf_slot]
    target_addr = struct.unpack_from("<H", code, userf_slot + 1)[0]
    cpm_to_next_ptr = struct.unpack_from("<H", code, userf_slot + 3)[0]
    next_to_cpm_ptr = struct.unpack_from("<H", code, userf_slot + 5)[0]

    assert jp_opcode == 0xC3, "Expected JP opcode (0xC3) at Host API + 82"
    assert target_addr == symbols["TRAMP_NEXTCPM_USERF"], (
        f"Expected JP to TRAMP_NEXTCPM_USERF "
        f"({symbols['TRAMP_NEXTCPM_USERF']:#x}), got {target_addr:#x}"
    )
    assert cpm_to_next_ptr == symbols["NEXTCPM_CPM_TO_NEXT"], (
        f"Expected ptr to NEXTCPM_CPM_TO_NEXT, got {cpm_to_next_ptr:#x}"
    )
    assert next_to_cpm_ptr == symbols["NEXTCPM_NEXT_TO_CPM"], (
        f"Expected ptr to NEXTCPM_NEXT_TO_CPM, got {next_to_cpm_ptr:#x}"
    )

    # 4. Verify STR_NEXTFS_PRL content
    str_offset = symbols["STR_NEXTFS_PRL"] - 0x0100
    assert code[str_offset : str_offset + 11] == b"NEXTFS.PRL\x00", (
        "STR_NEXTFS_PRL mismatch"
    )

    # 5. Check NEXTFS.PRL header and capabilities
    with open(prl_path, "rb") as f:
        prl_data = f.read()

    name = (
        prl_data[0x0C:0x1C]
        .decode("ascii", errors="replace")
        .replace("\x00", "")
        .strip()
    )
    caps = struct.unpack_from("<H", prl_data, 0x1C)[0]

    assert name == "NEXTFS", f"Expected plugin name NEXTFS, got {name}"
    assert caps == 0x017A, (
        f"Expected caps 0x017A (RUN|ABOUT|CFG|8K|VFS), got {caps:#06x}"
    )

    # Verify check_plugin.py succeeds on NEXTFS.PRL
    chk_script = os.path.join(PROJECT_DIR, "check_plugin.py")
    res_chk = subprocess.run(
        [sys.executable, chk_script, prl_path],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res_chk.returncode == 0, f"check_plugin.py failed:\n{res_chk.stdout}"

    # 6. Verify SE.COM byte-for-byte binary invariance
    res_se = subprocess.run(
        ["git", "diff", "--exit-code", "SE.COM"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res_se.returncode == 0, "SE.COM binary invariance violated!"

    # 7. Verify CCP headroom for SE_NEXT.COM and SE.COM
    ccp_script = os.path.join(PROJECT_DIR, "check_ccp.py")
    res_ccp_next = subprocess.run(
        [sys.executable, ccp_script, bin_path],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res_ccp_next.returncode == 0, (
        f"check_ccp.py failed on SE_NEXT.COM:\n{res_ccp_next.stdout}"
    )

    se_bin = os.path.join(PROJECT_DIR, "SE.COM")
    res_ccp_se = subprocess.run(
        [sys.executable, ccp_script, se_bin],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res_ccp_se.returncode == 0, (
        f"check_ccp.py failed on SE.COM:\n{res_ccp_se.stdout}"
    )

    print("    [+] SE_NEXT.COM and NEXTFS.PRL built cleanly")
    print("    [+] SE_NEXT.map symbols verified")
    print("    [+] Host API jump table (+82) and drive table pointers verified")
    print("    [+] NEXTFS.PRL PRL ABI and CAP_HAS_VFS verified")
    print("    [+] SE.COM binary invariance verified")
    print("    [+] CCP preservation verified on both SE_NEXT.COM and SE.COM")
    print("[+] Bug 2.2.29 regression test PASSED.")


if __name__ == "__main__":
    test_bug_2_2_29()
