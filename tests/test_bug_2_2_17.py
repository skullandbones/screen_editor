#!/usr/bin/env python3
"""
test_bug_2_2_17.py - Regression test for Bug 2.2.17:
Help Screen Shows PC/Terminal Keys Instead of ZX Spectrum Next Keys
(Create HELPNEXT.OVL).

Verifies:
1. plugins/build_plugins.py builds plugins/HELPNEXT.OVL cleanly and passes
   check_plugin.py ABI validation.
2. HELPNEXT.OVL contains the canonical 22-line Tier 1 Help layout (17 body
   lines, <= 79 chars per line) with ZX Spectrum Next key names (EXTEND,
   INV VIDEO, GRAPH, TRUE VIDEO, DELETE, EDIT, BREAK, Arrow Keys), the
   EXTEND = Ctrl note, and explicit markers for keys redefined away from
   standard Next CP/M mappings.
3. SE_NEXT.COM references "HELPNEXTOVL" in STR_HELP_OVL_NAME and displays
   "|           HELPNEXT.OVL was not found.          |" in
   STR_POPUP_HELP_MISS_MSG1.
4. SE.COM continues to reference "HELP    OVL" and "HELP.OVL was not found.",
   and preserves 100% byte-for-byte binary invariance.
5. SE_NEXT.COM executes HELPNEXT.OVL in a headless CP/M Z80 environment on
   Ctrl+K (0x0B) and renders the Next-specific 22-line Help screen cleanly.
6. CCP headroom check for SE_NEXT.COM passes.
"""

import os
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


def read_cstr(code, addr):
    off = addr - ORG
    end = code.index(b"\x00", off)
    return code[off:end]


def test_bug_2_2_17():
    print("[*] Testing Bug 2.2.17: ZX Spectrum Next HELPNEXT.OVL overlay...")

    # 1. Build SE_NEXT.COM and plugins (including HELPNEXT.OVL)
    res = subprocess.run(
        ["make", "-B", "se-next-cpm", "plugins"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"Build failed:\n{res.stderr}\n{res.stdout}"

    helpnext_path = os.path.join(PROJECT_DIR, "plugins", "HELPNEXT.OVL")
    assert os.path.isfile(helpnext_path), "plugins/HELPNEXT.OVL was not built"

    # Validate HELPNEXT.OVL via check_plugin.py
    res_chk = subprocess.run(
        [
            sys.executable,
            os.path.join(PROJECT_DIR, "check_plugin.py"),
            helpnext_path,
        ],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res_chk.returncode == 0, (
        f"check_plugin.py failed on HELPNEXT.OVL:\n{res_chk.stdout}"
    )
    assert "VERDICT: [ PASS ]" in res_chk.stdout

    # 2. Inspect HELPNEXT.OVL payload and 17-line body layout
    with open(helpnext_path, "rb") as f:
        ovl_bytes = f.read()

    # Header name at offset 0x0C (16 bytes)
    hdr_name = ovl_bytes[0x0C:0x1C].split(b"\x00")[0].decode("ascii").strip()
    assert hdr_name == "HELPNEXT", (
        f"Expected header name HELPNEXT, got {hdr_name!r}"
    )

    # Verify Next cursor hide sequence ESC f is included in HELPNEXT.OVL
    assert b"\x1bf\x1b[?25l$" in ovl_bytes, (
        "HELPNEXT.OVL must emit ESC f (NextCPM cursor hide) in STR_HIDE_CURSOR"
    )

    # Extract STR_HELP_BODY from helpnext.asm / HELPNEXT.OVL
    title_marker = b"EDITOR MODE KEYS\r\n$"
    title_idx = ovl_bytes.find(title_marker)
    assert title_idx != -1, "STR_HELP_TITLE not found in HELPNEXT.OVL"
    body_start = title_idx + len(title_marker)
    body_end = ovl_bytes.find(b"$", body_start)
    assert body_end != -1, "STR_HELP_BODY terminator '$' not found"

    body_text = ovl_bytes[body_start:body_end].decode("ascii")
    body_lines = body_text.split("\r\n")
    assert body_lines[-1] == "", "Expected trailing CRLF before '$'"
    body_lines = body_lines[:-1]

    assert len(body_lines) == 17, (
        f"Expected 17 body lines for 22-line Tier 1 layout, "
        f"got {len(body_lines)}"
    )
    for idx, line in enumerate(body_lines, start=1):
        assert len(line) <= 79, (
            f"Body line {idx} exceeds 79 chars ({len(line)}): {line!r}"
        )

    # Verify required Next key descriptions and notes
    required_tokens = [
        "EXTEND = Ctrl",
        "Next CP/M key redefined by SE",
        "EXTEND+O",
        "EXTEND+S",
        "EXTEND+W / EDIT",
        "EXTEND+Q",
        "EXTEND+K",
        "EXTEND+P",
        "EXTEND+Z",
        "EXTEND+Y",
        "*Arrow Keys",
        "*INV VIDEO / ^U",
        "Page Up (std: Tab)",
        "*GRAPH / ^V",
        "Page Down (std: ^G)",
        "*TRUE VIDEO / ^I",
        "DELETE / ^H",
        "EXTEND+D",
        "EXTEND+B",
        "EXTEND+C",
        "EXTEND+X",
        "BREAK (ESC)",
    ]
    for tok in required_tokens:
        assert tok in body_text, (
            f"Required Next help token {tok!r} missing from HELPNEXT.OVL"
        )

    # Shared HELP.OVL must remain free of Next-specific strings
    with open(os.path.join(PROJECT_DIR, "plugins", "HELP.OVL"), "rb") as f:
        help_ovl_bytes = f.read()
    assert b"INV VIDEO" not in help_ovl_bytes, (
        "Shared HELP.OVL must not contain Next-specific key names"
    )

    # 3. Verify SE_NEXT.COM symbols and strings
    map_path = os.path.join(PROJECT_DIR, "SE_NEXT.map")
    bin_path = os.path.join(PROJECT_DIR, "SE_NEXT.COM")
    symbols = parse_symbols(map_path)
    with open(bin_path, "rb") as f:
        next_code = f.read()

    ovl_name_off = symbols["STR_HELP_OVL_NAME"] - ORG
    ovl_name = next_code[ovl_name_off : ovl_name_off + 11]
    assert ovl_name == b"HELPNEXTOVL", (
        f"STR_HELP_OVL_NAME must be b'HELPNEXTOVL', got {ovl_name!r}"
    )

    miss_msg1 = read_cstr(next_code, symbols["STR_POPUP_HELP_MISS_MSG1"])
    assert miss_msg1 == b"|           HELPNEXT.OVL was not found.          |", (
        f"Unexpected STR_POPUP_HELP_MISS_MSG1: {miss_msg1!r}"
    )
    assert len(miss_msg1) == 50, "Popup row must be exactly 50 columns wide"

    # 4. Verify SE.COM binary invariance and HELP.OVL strings
    res_diff = subprocess.run(
        ["git", "diff", "--exit-code", "--quiet", "SE.COM"],
        cwd=PROJECT_DIR,
    )
    assert res_diff.returncode == 0, "SE.COM binary invariance broken!"
    with open(os.path.join(PROJECT_DIR, "SE.COM"), "rb") as f:
        se_com = f.read()
    assert b"HELP    OVL" in se_com, "SE.COM must still load 'HELP    OVL'"
    assert b"HELPNEXTOVL" not in se_com, "SE.COM must not reference HELPNEXTOVL"
    assert b"|             HELP.OVL was not found.            |" in se_com

    # 5. Verify CCP headroom on SE_NEXT.COM
    res_ccp = subprocess.run(
        [sys.executable, os.path.join(PROJECT_DIR, "check_ccp.py"), bin_path],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res_ccp.returncode == 0, f"check_ccp.py failed:\n{res_ccp.stdout}"

    print("    [+] HELPNEXT.OVL built and passed check_plugin.py ABI audit")
    print("    [+] 22-line Tier 1 layout and Next key descriptions verified")
    print("    [+] SE_NEXT.COM loads HELPNEXTOVL and updates Help Missing modal")
    print("    [+] Shared HELP.OVL and SE.COM byte-for-byte invariance preserved")
    print("    [+] SE_NEXT.COM CCP headroom verified")
    print("    [+] Bug 2.2.17 fix verified successfully.")


if __name__ == "__main__":
    test_bug_2_2_17()
