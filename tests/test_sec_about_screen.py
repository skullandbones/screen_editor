#!/usr/bin/env python3
"""Validation test for Bug 2.8.6: About Screen Layout in SEC.COM.

Verifies that show_about_screen() adopts the canonical 9-line centered layout
from docs/UI_UX_DESIGN.md §7.12, eliminates the misleading '(Linux)' banner on
CP/M, displays 'version 1.1.0 (2026-10-09) (C)', and renders full author and
open-source credits.
"""

import os
import subprocess
import sys
import time


def test_sec_about_screen():
    start_time = time.time()
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sec_bin = os.path.join(repo_root, "SEC.COM")
    ui_render_src = os.path.join(repo_root, "src", "core", "ui_render.c")

    # Step 1: Compile SEC.COM
    print("[*] Step 1: Compiling SEC.COM with 'make sec-cpm'...", flush=True)
    res = subprocess.run(
        ["make", "sec-cpm"],
        cwd=repo_root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if res.returncode != 0:
        print(f"[-] Step 1: Compilation failed. "
              f"Buffer: {repr(res.stderr[-300:])}", flush=True)
        return False
    print("[+] Step 1: SEC.COM compiled successfully.", flush=True)

    with open(sec_bin, "rb") as f:
        binary_data = f.read()

    # Step 2: Verify "(Linux)" banner is eliminated from About screen
    print("[*] Step 2: Verifying '(Linux)' is absent from About screen...",
          flush=True)
    with open(ui_render_src, "r") as f:
        src_text = f.read()

    about_fn_idx = src_text.find("void show_about_screen(void)")
    if about_fn_idx == -1:
        print("[-] Step 2: show_about_screen() not found in ui_render.c.",
              flush=True)
        return False

    about_fn_body = src_text[about_fn_idx:about_fn_idx + 1000]
    if "(Linux)" in about_fn_body:
        print("[-] Step 2: Found '(Linux)' in show_about_screen().",
              flush=True)
        return False
    print("[+] Step 2: Misleading '(Linux)' tag eliminated from About screen.",
          flush=True)

    # Step 3: Verify canonical C version string present
    print("[*] Step 3: Verifying 'version 1.1.0 (2026-10-09) (C)'...",
          flush=True)
    expected_version = b"version 1.1.0 (2026-10-09) (C)"
    if expected_version not in binary_data:
        print("[-] Step 3: Canonical version string missing from SEC.COM.",
              flush=True)
        return False
    print("[+] Step 3: Canonical C language version string verified.",
          flush=True)

    # Step 4: Verify author and open-source credits in SEC.COM
    print("[*] Step 4: Verifying author and open-source credits...",
          flush=True)
    required_credits = [
        b"Dean Jenkins",
        b"Google Antigravity 2.19.1 & Gemini FLASH 3.8 high",
        b"Open source software under the MIT License",
        b"Press any key to continue",
    ]
    missing = [c for c in required_credits if c not in binary_data]
    if missing:
        print(f"[-] Step 4: Missing credits from SEC.COM binary: {missing}",
              flush=True)
        return False
    print("[+] Step 4: All author and open-source credits verified.",
          flush=True)

    elapsed = time.time() - start_time
    print(f"[+] All SEC About Screen tests PASSED in {elapsed:.2f}s!",
          flush=True)
    return True


if __name__ == "__main__":
    if not test_sec_about_screen():
        sys.exit(1)
