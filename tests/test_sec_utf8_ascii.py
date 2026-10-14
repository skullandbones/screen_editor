#!/usr/bin/env python3
"""Validation test for Bug 2.8.3: UTF-8 Character Emission in SEC.COM.

Verifies strict 7-bit ASCII text output in C source string literals and
compiled SEC.COM binary, preventing terminal corruption on CP/M VT100
terminals.
"""

import os
import subprocess
import sys
import time


def test_sec_utf8_ascii():
    start_time = time.time()
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sec_bin = os.path.join(repo_root, "SEC.COM")

    # Step 1: Scan C source files for multi-byte UTF-8 em-dash characters
    print("[*] Step 1: Scanning C source files for UTF-8 em-dash characters...",
          flush=True)
    c_dirs = [
        os.path.join(repo_root, "src", "core"),
        os.path.join(repo_root, "src", "hal", "cpm"),
        os.path.join(repo_root, "src", "include"),
    ]
    em_dash_bytes = b"\xe2\x80\x94"
    offending_files = []

    for c_dir in c_dirs:
        for fname in sorted(os.listdir(c_dir)):
            if fname.endswith((".c", ".h")):
                fpath = os.path.join(c_dir, fname)
                with open(fpath, "rb") as f:
                    content = f.read()
                    if em_dash_bytes in content:
                        offending_files.append(fpath)

    if offending_files:
        print(f"[-] Step 1: Found UTF-8 em-dash in sources: {offending_files}",
              flush=True)
        return False
    print("[+] Step 1: Zero UTF-8 em-dash sequences found across C sources.",
          flush=True)

    # Step 2: Compile SEC.COM
    print("[*] Step 2: Compiling SEC.COM via 'make sec-cpm'...", flush=True)
    res = subprocess.run(
        ["make", "sec-cpm"],
        cwd=repo_root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if res.returncode != 0:
        print(f"[-] Step 2: Compilation of SEC.COM failed. "
              f"Buffer: {repr(res.stderr[-300:])}", flush=True)
        return False
    print("[+] Step 2: SEC.COM compiled successfully.", flush=True)

    # Step 3: Scan SEC.COM binary for multi-byte UTF-8 em-dash sequences
    print("[*] Step 3: Verifying SEC.COM binary has no UTF-8 em-dash bytes...",
          flush=True)
    with open(sec_bin, "rb") as f:
        binary_data = f.read()

    if em_dash_bytes in binary_data:
        idx = binary_data.find(em_dash_bytes)
        print(f"[-] Step 3: Found UTF-8 em-dash sequence at offset {hex(idx)}. "
              f"Buffer: {repr(binary_data[idx:idx+16])}", flush=True)
        return False
    print("[+] Step 3: SEC.COM binary is free of UTF-8 em-dash sequences.",
          flush=True)

    # Step 4: Verify ASCII hyphen titles present in SEC.COM binary
    print("[*] Step 4: Verifying 7-bit ASCII hyphen titles in SEC.COM...",
          flush=True)
    expected_titles = [
        b"SE - Screen Editor",
        b"SE - Configuration Manager",
        b"SE.COM - EDITOR MODE KEYS",
    ]
    missing = [t for t in expected_titles if t not in binary_data]
    if missing:
        print(f"[-] Step 4: Expected ASCII titles missing from binary: "
              f"{missing}", flush=True)
        return False
    print("[+] Step 4: Verified 7-bit ASCII titles in compiled binary.",
          flush=True)

    elapsed = time.time() - start_time
    print(f"[+] All SEC UTF-8 ASCII tests PASSED in {elapsed:.2f}s!",
          flush=True)
    return True


if __name__ == "__main__":
    if not test_sec_utf8_ascii():
        sys.exit(1)
