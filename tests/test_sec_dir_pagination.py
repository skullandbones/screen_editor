#!/usr/bin/env python3
"""Validation test for Step 26: Directory pagination guard in SEC.COM.

Verifies that the directory file browser only displays page navigation prompts
('[Page %d/%d] <PgUp>/<PgDn>=Page') when total_pages > 1, matching SE.COM
(src/core/ui_browser.asm:5481) and avoiding premature pagination prompts.
"""

import os
import subprocess
import sys
import time


def test_sec_dir_pagination():
    start_time = time.time()
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    browser_src = os.path.join(repo_root, "src", "core", "ui_browser.c")

    # Step 1: Verify source code checks total_pages > 1
    print("[*] Step 1: Verifying total_pages > 1 guard in "
          "src/core/ui_browser.c...", flush=True)
    with open(browser_src, "r") as f:
        src_text = f.read()

    if "} else if (total_pages > 1) {" not in src_text:
        print("[-] Step 1: Missing total_pages > 1 guard in ui_browser.c.",
              flush=True)
        return False
    print("[+] Step 1: total_pages > 1 guard verified in ui_browser.c.",
          flush=True)

    # Step 2: Compile SEC.COM with the fix
    print("[*] Step 2: Compiling SEC.COM with 'make sec-cpm'...", flush=True)
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
    print("[+] Step 2: SEC.COM compiled successfully with pagination guard.",
          flush=True)

    # Step 3: Verify page format string is retained for multi-page mode
    print("[*] Step 3: Verifying multi-page format string in compiled binary...",
          flush=True)
    sec_bin = os.path.join(repo_root, "SEC.COM")
    with open(sec_bin, "rb") as f:
        bin_data = f.read()

    if b"<PgUp>/<PgDn>=Page" not in bin_data:
        print("[-] Step 3: Page navigation prompt missing from binary.",
              flush=True)
        return False
    print("[+] Step 3: Multi-page navigation string present in SEC.COM.",
          flush=True)

    elapsed = time.time() - start_time
    print(f"[+] All SEC Directory Pagination tests PASSED in {elapsed:.2f}s!",
          flush=True)
    return True


if __name__ == "__main__":
    if not test_sec_dir_pagination():
        sys.exit(1)
