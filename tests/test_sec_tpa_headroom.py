#!/usr/bin/env python3
"""Validation test for Bug 2.8.2: CP/M TPA Headroom below BDOS 0xD800
in SEC.COM.

Verifies that SEC.COM binary size, data, and BSS memory allocation fit safely
within the RomWBW RC2014 CP/M TPA below BDOS entry point 0xD800 (55,296),
reclaiming negative headroom and restoring positive TPA headroom.
"""

import os
import subprocess
import sys
import time


def test_sec_tpa_headroom():
    start_time = time.time()
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sec_bin = os.path.join(repo_root, "SEC.COM")

    # Step 1: Compile SEC.COM with native sector I/O
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
    if not os.path.exists(sec_bin):
        print(f"[-] Step 1: SEC.COM binary not found at {sec_bin}.", flush=True)
        return False
    print("[+] Step 1: SEC.COM compiled successfully.", flush=True)

    # Step 2: Audit TPA headroom via check_tpa.py
    print("[*] Step 2: Running check_tpa.py SEC.COM to verify headroom...",
          flush=True)
    res_tpa = subprocess.run(
        ["python3", "check_tpa.py", "SEC.COM"],
        cwd=repo_root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    output = res_tpa.stdout
    if res_tpa.returncode != 0:
        print(f"[-] Step 2: check_tpa.py exited with failure. "
              f"Buffer: {repr(output[-300:])}", flush=True)
        return False

    if "VERDICT: [ PASS ]" not in output:
        print(f"[-] Step 2: VERDICT PASS missing from TPA analysis. "
              f"Buffer: {repr(output[-300:])}", flush=True)
        return False
    print("[+] Step 2: check_tpa.py reports VERDICT [ PASS ].", flush=True)

    # Step 3: Verify positive headroom below 0xD800
    print("[*] Step 3: Parsing headroom value below BDOS 0xD800...", flush=True)
    passed_romwbw = False
    for line in output.splitlines():
        if "RomWBW RC2014 CP/M" in line and "PASS" in line and "+" in line:
            passed_romwbw = True
            break
    if not passed_romwbw:
        print(f"[-] Step 3: Positive headroom not found for RomWBW CP/M. "
              f"Buffer: {repr(output[-400:])}", flush=True)
        return False
    print("[+] Step 3: Positive TPA headroom verified below BDOS 0xD800.",
          flush=True)

    elapsed = time.time() - start_time
    print(f"[+] All SEC TPA Headroom tests PASSED in {elapsed:.2f}s!",
          flush=True)
    return True


if __name__ == "__main__":
    if not test_sec_tpa_headroom():
        sys.exit(1)
