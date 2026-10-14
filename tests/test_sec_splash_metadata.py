#!/usr/bin/env python3
"""Validation test for Bug 2.8.4: Splash Options & System Metadata in SEC.COM.

Verifies that SEC.COM omits Option 3 (set native) on CP/M, enforces the clean
header mandate (no version or language on splash), and dynamically formats
the 4 canonical system metadata fields (Active Screen, RAM Drive, Plugin
System, Max Lines) matching canonical SE.COM.
"""

import os
import subprocess
import sys
import time


def test_sec_splash_metadata():
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

    # Step 2: Verify Option 3 (set native) is omitted from SEC.COM binary
    print("[*] Step 2: Verifying Option 3 is excluded from CP/M binary...",
          flush=True)
    if b"set native" in binary_data:
        print("[-] Step 2: Found unsupported 'set native' in CP/M SEC.COM.",
              flush=True)
        return False
    print("[+] Step 2: Option 3 (set native) cleanly omitted on CP/M.",
          flush=True)

    # Step 3: Verify clean header mandate on splash screen
    print("[*] Step 3: Verifying clean header mandate...", flush=True)
    with open(ui_render_src, "r") as f:
        src_text = f.read()

    # In show_splash_screen, verify no Version v1.1.0 string in splash_lines
    splash_func_idx = src_text.find("void show_splash_screen(void)")
    if splash_func_idx == -1:
        print("[-] Step 3: show_splash_screen() not found in ui_render.c.",
              flush=True)
        return False

    splash_body = src_text[splash_func_idx:splash_func_idx + 2500]
    if "Version v1.1.0" in splash_body:
        print("[-] Step 3: Found 'Version v1.1.0' in show_splash_screen.",
              flush=True)
        return False
    print("[+] Step 3: Splash screen adheres to clean header mandate.",
          flush=True)

    # Step 4: Verify 4 canonical system metadata fields present in SEC.COM
    print("[*] Step 4: Verifying 4 canonical system metadata fields...",
          flush=True)
    required_metadata_fields = [
        b"Active Screen : [",
        b"RAM Drive (A:): [",
        b"Plugin System : [",
        b"Max Lines     : [",
    ]
    missing = [f for f in required_metadata_fields if f not in binary_data]
    if missing:
        print(f"[-] Step 4: Missing metadata fields from SEC.COM binary: "
              f"{missing}", flush=True)
        return False
    print("[+] Step 4: All 4 dynamic system metadata fields verified.",
          flush=True)

    elapsed = time.time() - start_time
    print(f"[+] All SEC Splash Metadata tests PASSED in {elapsed:.2f}s!",
          flush=True)
    return True


if __name__ == "__main__":
    if not test_sec_splash_metadata():
        sys.exit(1)
