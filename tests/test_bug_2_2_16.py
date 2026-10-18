#!/usr/bin/env python3
"""
test_bug_2_2_16.py - Regression test for Bug 2.2.16:
Cursor Visible While HELPNEXT.OVL / PLUGIN.PRL Overlays Are Displayed.

Verifies:
1. SE_NEXT.COM and plugins (HELPNEXT.OVL, PLUGIN.PRL) build cleanly.
2. PLUGIN_HOST_API in SE_NEXT.COM declares Host API version 0x0114 (v1.1.4)
   and exposes TRAMP_HIDE_CURSOR at offset +76 and TRAMP_SHOW_CURSOR at +79,
   which invoke TERM_HIDE_CURSOR (ESC f) and TERM_SHOW_CURSOR (ESC e).
3. HELPNEXT.OVL and PLUGIN.PRL check for Host API version >= 0x0114 and call
   the +76 (hide cursor) and +79 (show cursor) trampolines, falling back to
   their local cursor strings when loaded on an older host (< 0x0114).
4. SE.COM (RomWBW) remains byte-for-byte identical (Host API v0x0113, so
   PLUGIN.PRL falls back to emitting ESC[?25l on RomWBW).
5. CCP headroom check (`check_ccp.py SE_NEXT.COM`) and plugin ABI check
   (`check_plugin.py`) pass.
"""

import os
import struct
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


def jp_bytes(addr):
    return bytes([0xC3, addr & 0xFF, (addr >> 8) & 0xFF])


def test_bug_2_2_16():
    print("[*] Testing Bug 2.2.16: Host API cursor hide/show trampolines in "
          "SE_NEXT.COM, HELPNEXT.OVL, and PLUGIN.PRL...")

    # Step 1: Rebuild SE_NEXT.COM, SE.COM, and plugins
    res = subprocess.run(
        ["make", "-B", "se-next-cpm", "SE.COM", "plugins"],
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

    # Step 2: Verify PLUGIN_HOST_API in SE_NEXT.COM
    for sym in (
        "PLUGIN_HOST_API",
        "TRAMP_RENDER_STATUS_BAR",
        "TRAMP_HIDE_CURSOR",
        "TRAMP_SHOW_CURSOR",
        "TERM_HIDE_CURSOR",
        "TERM_SHOW_CURSOR",
    ):
        assert sym in symbols, f"{sym} missing from SE_NEXT.map"

    api_off = symbols["PLUGIN_HOST_API"] - ORG
    assert code[api_off:api_off + 2] == b"SE", "Host API magic must be 'SE'"
    api_ver = struct.unpack_from("<H", code, api_off + 2)[0]
    assert api_ver >= 0x0114, (
        f"SE_NEXT.COM Host API version must be >= 0x0114, got 0x{api_ver:04X}"
    )

    assert code[api_off + 73:api_off + 76] == jp_bytes(
        symbols["TRAMP_RENDER_STATUS_BAR"]
    ), "Host API +73 must JP TRAMP_RENDER_STATUS_BAR"
    assert code[api_off + 76:api_off + 79] == jp_bytes(
        symbols["TRAMP_HIDE_CURSOR"]
    ), "Host API +76 must JP TRAMP_HIDE_CURSOR"
    assert code[api_off + 79:api_off + 82] == jp_bytes(
        symbols["TRAMP_SHOW_CURSOR"]
    ), "Host API +79 must JP TRAMP_SHOW_CURSOR"

    # Verify TRAMP_HIDE_CURSOR references TERM_HIDE_CURSOR and
    # TRAMP_SHOW_CURSOR references TERM_SHOW_CURSOR
    thc_off = symbols["TRAMP_HIDE_CURSOR"] - ORG
    tsc_off = symbols["TRAMP_SHOW_CURSOR"] - ORG
    hide_addr = symbols["TERM_HIDE_CURSOR"]
    show_addr = symbols["TERM_SHOW_CURSOR"]
    assert struct.pack("<H", hide_addr) in code[thc_off:thc_off + 16], (
        "TRAMP_HIDE_CURSOR must target TERM_HIDE_CURSOR"
    )
    assert struct.pack("<H", show_addr) in code[tsc_off:tsc_off + 16], (
        "TRAMP_SHOW_CURSOR must target TERM_SHOW_CURSOR"
    )

    # Step 3: Verify HELPNEXT.OVL and PLUGIN.PRL use +76 / +79 and version
    # check 0x14 (v1.1.4)
    helpnext_path = os.path.join(PROJECT_DIR, "plugins", "HELPNEXT.OVL")
    plugin_path = os.path.join(PROJECT_DIR, "plugins", "PLUGIN.PRL")
    with open(helpnext_path, "rb") as f:
        helpnext_bin = f.read()
    with open(plugin_path, "rb") as f:
        plugin_bin = f.read()

    # HELPNEXT.OVL uses `LD C,76` (0x0E 0x4C) and `LD C,79` (0x0E 0x4F) and
    # `CP 14H` (0xFE 0x14)
    assert b"\x0e\x4c" in helpnext_bin, (
        "HELPNEXT.OVL must dispatch offset +76 (LD C,76)"
    )
    assert b"\x0e\x4f" in helpnext_bin, (
        "HELPNEXT.OVL must dispatch offset +79 (LD C,79)"
    )
    assert b"\xfe\x14" in helpnext_bin, (
        "HELPNEXT.OVL must check Host API version minor >= 0x14"
    )

    # PLUGIN.PRL uses `LD BC,76` (0x01 0x4C 0x00) and `LD BC,79`
    # (0x01 0x4F 0x00), `CP 14H` (0xFE 0x14), and retains fallback
    # STR_HIDE_CURSOR (`\x1b[?25l$`)
    assert b"\x01\x4c\x00" in plugin_bin, (
        "PLUGIN.PRL must dispatch offset +76 (LD BC,76)"
    )
    assert b"\x01\x4f\x00" in plugin_bin, (
        "PLUGIN.PRL must dispatch offset +79 (LD BC,79)"
    )
    assert b"\xfe\x14" in plugin_bin, (
        "PLUGIN.PRL must check Host API version minor >= 0x14"
    )
    assert b"\x1b[?25l$" in plugin_bin, (
        "PLUGIN.PRL must retain fallback STR_HIDE_CURSOR for older hosts"
    )

    # Step 4: Verify SE.COM binary invariance
    res = subprocess.run(
        ["git", "diff", "--exit-code", "--quiet", "SE.COM"],
        cwd=PROJECT_DIR,
    )
    assert res.returncode == 0, "SE.COM binary invariance broken"

    # Step 5: Verify CCP headroom and plugin ABI
    res = subprocess.run(
        [sys.executable, os.path.join(PROJECT_DIR, "check_ccp.py"), bin_path],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"check_ccp.py failed:\n{res.stdout}"

    res = subprocess.run(
        [
            sys.executable,
            os.path.join(PROJECT_DIR, "check_plugin.py"),
            helpnext_path,
            plugin_path,
        ],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"check_plugin.py failed:\n{res.stdout}"

    print("    [+] SE_NEXT.COM Host API v1.1.4 exposes +76/+79 cursor "
          "trampolines")
    print("    [+] HELPNEXT.OVL and PLUGIN.PRL invoke +76/+79 with v1.1.4 "
          "fallback")
    print("    [+] SE.COM byte-for-byte invariance preserved")
    print("    [+] CCP headroom and plugin ABI checks passed")
    print("    [+] Bug 2.2.16 fix verified successfully.")


if __name__ == "__main__":
    test_bug_2_2_16()
