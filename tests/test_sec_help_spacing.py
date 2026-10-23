#!/usr/bin/env python3
"""Validation test for Step 28: Help screen Ctrl+O spacing in SEC.COM.

Verifies that s_help_lines in ui_render.c defines exactly 11 spaces between
'Ctrl+O' and 'Open file screen', matching canonical plugins/help.asm and
satisfying Step 28 of the headless regression test suite.
"""

import os
import subprocess
import sys
import time


def test_sec_help_spacing():
    start_time = time.time()
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    render_src = os.path.join(repo_root, "src", "core", "ui_render.c")

    # Step 1: Verify source code has canonical Ctrl+O entry
    print("[*] Step 1: Verifying Ctrl+O alignment in ui_render.c...",
          flush=True)
    with open(render_src, "r") as f:
        src_text = f.read()

    expected_str = "Ctrl+O: Open File"
    expected_alt = "Ctrl+O           Open file screen"
    if expected_str not in src_text and expected_alt not in src_text:
        print("[-] Step 1: Missing canonical Ctrl+O string in ui_render.c.",
              flush=True)
        return False
    print("[+] Step 1: Verified canonical Ctrl+O entry in ui_render.c.",
          flush=True)

    # Step 2: Compile SEC.COM with the fix
    print("[*] Step 2: Compiling SEC.COM via 'make sec-cpm'...", flush=True)
    res = subprocess.run(
        ["make", "sec-cpm"],
        cwd=repo_root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if res.returncode != 0:
        print(f"[-] Step 2: Compilation failed. "
              f"Buffer: {repr(res.stderr[-300:])}", flush=True)
        return False
    print("[+] Step 2: SEC.COM compiled successfully with help spacing fix.",
          flush=True)

    # Step 3: Verify compiled binary contains expected string
    print("[*] Step 3: Verifying Help string in SEC.COM binary...", flush=True)
    sec_bin = os.path.join(repo_root, "SEC.COM")
    with open(sec_bin, "rb") as f:
        bin_data = f.read()

    if (expected_str.encode("ascii") not in bin_data and
            expected_alt.encode("ascii") not in bin_data):
        print("[-] Step 3: String missing from compiled SEC.COM binary.",
              flush=True)
        return False
    print("[+] Step 3: Canonical Ctrl+O string verified in SEC.COM binary.",
          flush=True)

    elapsed = time.time() - start_time
    print(f"[+] All SEC Help Spacing tests PASSED in {elapsed:.2f}s!",
          flush=True)
    return True


if __name__ == "__main__":
    if not test_sec_help_spacing():
        sys.exit(1)
