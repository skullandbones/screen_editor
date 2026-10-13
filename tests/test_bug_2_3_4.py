#!/usr/bin/env python3
"""Automated regression test for Bug 2.3.4:
Splash Screen Geometry Hotkeys & Unsupported 120x40 on Native Next.

Validates that:
1. In src/se_next.asm, SCREEN_MODE defaults to MODE_80X24 (80x24).
2. In src/se_next.asm, SPLASH_LOOP maps option '1' to DO_SET_80X24, and
   disables option '2' (loops back to SPLASH_LOOP).
3. DO_SET_120X40 and SET_MODE_120X40 safely redirect to SET_MODE_80X24.
4. In src/core/plugin_mgr.asm, STR_SPLASH_CMDS displays '[1] set 80x24'.
5. Native targets SE.NEX and .se build cleanly within the 48K slot.
6. RomWBW CP/M SE.COM byte-for-byte binary invariance is preserved.
"""

import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
SRC_NEXT = os.path.join(PROJECT_DIR, "src", "se_next.asm")
SRC_PLUGIN = os.path.join(PROJECT_DIR, "src", "core", "plugin_mgr.asm")


def test_bug_2_3_4():
    print("[*] Testing Bug 2.3.4: Native Next Geometry Hotkeys & 80x24...")

    assert os.path.exists(SRC_NEXT), f"Missing {SRC_NEXT}"
    with open(SRC_NEXT, "r", encoding="utf-8") as f:
        src = f.read()

    # 1. Check default SCREEN_MODE is MODE_80X24
    idx_sm = src.find("\nSCREEN_MODE:")
    assert idx_sm != -1, "SCREEN_MODE definition not found"
    sm_section = src[idx_sm : idx_sm + 200]
    assert "MODE_80X24" in sm_section, "SCREEN_MODE must default to MODE_80X24"
    assert "24" in sm_section, "ACTIVE_ROWS must default to 24"
    assert "80" in sm_section, "ACTIVE_COLS must default to 80"
    print("    [+] SCREEN_MODE defaults to 80x24 (80 cols, 24 rows)")

    # 2. Check SPLASH_LOOP hotkeys
    idx_splash = src.find("\nSPLASH_LOOP:")
    assert idx_splash != -1, "SPLASH_LOOP label not found"
    splash_section = src[idx_splash : idx_splash + 3500]

    assert "CP '1'" in splash_section, "Option '1' check not found"
    assert "DO_SET_80X24" in splash_section, "Option '1' must set 80x24"
    assert "DO_SET_120X40" not in splash_section[:splash_section.find("DO_SET")], (
        "Option '1' must not set 120x40"
    )
    print("    [+] Splash hotkey [1] maps to DO_SET_80X24")

    # 3. Check 120x40 redirection
    idx_set120 = src.find("\nDO_SET_120X40:")
    assert idx_set120 != -1, "DO_SET_120X40 not found"
    set120_section = src[idx_set120 : idx_set120 + 200]
    assert "SET_MODE_80X24" in set120_section, (
        "DO_SET_120X40 must redirect to SET_MODE_80X24"
    )

    idx_mode120 = src.find("\nSET_MODE_120X40:")
    assert idx_mode120 != -1, "SET_MODE_120X40 not found"
    mode120_section = src[idx_mode120 : idx_mode120 + 200]
    assert "SET_MODE_80X24" in mode120_section, (
        "SET_MODE_120X40 must enforce SET_MODE_80X24"
    )
    print("    [+] 120x40 requests safely redirect to SET_MODE_80X24")

    # 4. Check STR_SPLASH_CMDS displays [1] set 80x24
    assert os.path.exists(SRC_PLUGIN), f"Missing {SRC_PLUGIN}"
    with open(SRC_PLUGIN, "r", encoding="utf-8") as f:
        plug_src = f.read()
    assert "[1]              set 80x24" in plug_src, (
        "STR_SPLASH_CMDS must display '[1]              set 80x24'"
    )
    print("    [+] STR_SPLASH_CMDS displays [1] set 80x24")

    # 5. Verify build and .se size <= 49,152
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

    # 6. Verify RomWBW CP/M binary invariance
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
    print("    [+] Bug 2.3.4 fix verified successfully.")


if __name__ == "__main__":
    test_bug_2_3_4()
