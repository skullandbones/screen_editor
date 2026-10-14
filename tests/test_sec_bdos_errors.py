#!/usr/bin/env python3
"""Validation test for Steps 26-27: BDOS 0xFF return code casting in SEC.COM.

Verifies that all BDOS file operation error checks across ui_browser.c,
file_io.c, config.c, and hal_cpm_storage.c cast bdos() return values to uint8_t
before comparing against 0xFF, preventing signed 16-bit extension (-1 != 255)
from bypassing 'File Not Found' alerts and file creation error handlers.
"""

import os
import subprocess
import sys
import time


def test_sec_bdos_errors():
    start_time = time.time()
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    # Step 1: Verify ui_browser.c uint8_t cast
    print("[*] Step 1: Verifying uint8_t bdos cast in ui_browser.c...",
          flush=True)
    browser_path = os.path.join(repo_root, "src", "core", "ui_browser.c")
    with open(browser_path, "r") as f:
        browser_text = f.read()
    if "(uint8_t)bdos(15, (int)s_dir_fcb) == 0xFF" not in browser_text:
        print("[-] Step 1: Missing uint8_t cast in ui_browser.c open check.",
              flush=True)
        return False
    print("[+] Step 1: Verified uint8_t bdos cast in ui_browser.c.", flush=True)

    # Step 2: Verify file_io.c uint8_t casts
    print("[*] Step 2: Verifying uint8_t bdos casts in file_io.c...",
          flush=True)
    file_io_path = os.path.join(repo_root, "src", "core", "file_io.c")
    with open(file_io_path, "r") as f:
        file_io_text = f.read()
    if "(uint8_t)bdos(15, (int)&s_cpm_io_fcb) == 0xFF" not in file_io_text:
        print("[-] Step 2: Missing uint8_t cast in file_io.c open check.",
              flush=True)
        return False
    if "(uint8_t)bdos(22, (int)&s_cpm_io_fcb) == 0xFF" not in file_io_text:
        print("[-] Step 2: Missing uint8_t cast in file_io.c make check.",
              flush=True)
        return False
    print("[+] Step 2: Verified uint8_t bdos casts in file_io.c.", flush=True)

    # Step 3: Verify config.c and hal_cpm_storage.c uint8_t casts
    print("[*] Step 3: Verifying uint8_t bdos casts in config and HAL...",
          flush=True)
    cfg_path = os.path.join(repo_root, "src", "core", "config.c")
    with open(cfg_path, "r") as f:
        cfg_text = f.read()
    if "(uint8_t)bdos(15, (int)&s_cfg_fcb) == 0xFF" not in cfg_text:
        print("[-] Step 3: Missing uint8_t cast in config.c open check.",
              flush=True)
        return False

    hal_path = os.path.join(repo_root, "src", "hal", "cpm",
                            "hal_cpm_storage.c")
    with open(hal_path, "r") as f:
        hal_text = f.read()
    if "(uint8_t)bdos(15, (int)fcb) == 0xFF" not in hal_text:
        print("[-] Step 3: Missing uint8_t cast in hal_cpm_storage.c open.",
              flush=True)
        return False
    print("[+] Step 3: Verified uint8_t bdos casts in config and HAL.",
          flush=True)

    # Step 4: Compile SEC.COM with casted checks
    print("[*] Step 4: Compiling SEC.COM via 'make sec-cpm'...", flush=True)
    res = subprocess.run(
        ["make", "sec-cpm"],
        cwd=repo_root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if res.returncode != 0:
        print(f"[-] Step 4: Compilation failed. "
              f"Buffer: {repr(res.stderr[-300:])}", flush=True)
        return False
    print("[+] Step 4: SEC.COM compiled successfully with casted BDOS checks.",
          flush=True)

    elapsed = time.time() - start_time
    print(f"[+] All SEC BDOS Error Cast tests PASSED in {elapsed:.2f}s!",
          flush=True)
    return True


if __name__ == "__main__":
    if not test_sec_bdos_errors():
        sys.exit(1)
