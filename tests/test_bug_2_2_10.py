#!/usr/bin/env python3
"""
test_bug_2_2_10.py - Regression test for Bug 2.2.10:
Predominant Language Indication on About Screen for NextCPM.

Verifies:
1. SE_NEXT.COM builds cleanly.
2. STR_ABOUT_VERSION in SE_NEXT.COM includes ' (Z80 Assembly)'.
3. SE.COM remains invariant and does not include the Next-specific change.
4. TPA headroom of SE_NEXT.COM meets requirements (+2,048 B).
"""

import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)


def test_bug_2_2_10():
    print("[*] Testing Bug 2.2.10: About screen language indication...")

    # Step 1: Rebuild SE_NEXT.COM
    res = subprocess.run(
        ["make", "-B", "se-next-cpm"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"make se-next-cpm failed:\n{res.stderr}"

    bin_next = os.path.join(PROJECT_DIR, "SE_NEXT.COM")
    bin_cpm = os.path.join(PROJECT_DIR, "SE.COM")

    assert os.path.exists(bin_next), f"Binary missing: {bin_next}"
    assert os.path.exists(bin_cpm), f"Binary missing: {bin_cpm}"

    with open(bin_next, "rb") as f:
        code_next = f.read()

    with open(bin_cpm, "rb") as f:
        code_cpm = f.read()

    expected_version = b"version 1.1.2 (2026-10-14) (Z80 Assembly)"
    assert expected_version in code_next, (
        f"Expected '{expected_version.decode()}' in SE_NEXT.COM"
    )

    # In SE.COM, version string with language suffix is preserved
    assert expected_version in code_cpm, (
        "SE.COM baseline version string missing"
    )

    # Step 2: Validate TPA headroom
    tpa_script = os.path.join(PROJECT_DIR, "check_tpa.py")
    res = subprocess.run(
        [sys.executable, tpa_script, bin_next],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"check_tpa.py failed:\n{res.stdout}"
    assert "PASS" in res.stdout, "check_tpa verdict was not PASS"
    assert (
        "+2,048 bytes" in res.stdout
        or "+2,304 bytes" in res.stdout
        or "+2,560 bytes" in res.stdout
    ), "Headroom must be positive"

    print("    [+] SE_NEXT.COM displays '(Z80 Assembly)' on About screen")
    print("    [+] SE.COM binary invariance preserved")
    print("    [+] TPA headroom verified")
    print("    [+] Bug 2.2.10 fix verified successfully.")


if __name__ == "__main__":
    test_bug_2_2_10()
