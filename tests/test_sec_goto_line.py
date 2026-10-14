#!/usr/bin/env python3
"""Validation test for Bug 2.8.9: Goto Line Modal Framing in SEC.COM.

Verifies that modal_goto_line() adheres strictly to canonical 7-row Archetype C
framing (50 cols x 7 rows), displays canonical 'Goto line: [     ]' prompt,
renders explicit action footer '[Enter]=Goto Line     [ESC]=Cancel', and
performs in-place character echoing without full-frame repaints on keystrokes.
"""

import os
import subprocess
import sys
import time


def test_sec_goto_line():
    start_time = time.time()
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sec_bin = os.path.join(repo_root, "SEC.COM")
    ui_modal_src = os.path.join(repo_root, "src", "core", "ui_modal.c")

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

    # Step 2: Verify modal_goto_line() dimensions in source
    print("[*] Step 2: Verifying 50x7 modal dimensions in ui_modal.c...",
          flush=True)
    with open(ui_modal_src, "r") as f:
        src_text = f.read()

    goto_idx = src_text.find("int modal_goto_line(")
    if goto_idx == -1:
        print("[-] Step 2: modal_goto_line() not found in ui_modal.c.",
              flush=True)
        return False

    goto_body = src_text[goto_idx:goto_idx + 2500]
    if "height = 7;" not in goto_body or "width = 50;" not in goto_body:
        print("[-] Step 2: modal_goto_line() does not set 50x7 dimensions.",
              flush=True)
        return False
    print("[+] Step 2: Canonical 50 cols x 7 rows framing verified.",
          flush=True)

    # Step 3: Verify canonical framing strings and action footer in SEC.COM
    print("[*] Step 3: Verifying canonical prompt and action footer...",
          flush=True)
    required_strings = [
        b"Goto line: [     ]",
        b"[Enter]=Goto Line     [ESC]=Cancel",
        b"Enter line number to jump to",
    ]
    missing = [s for s in required_strings if s not in binary_data]
    if missing:
        print(f"[-] Step 3: Missing expected Goto Line strings: {missing}",
              flush=True)
        return False
    print("[+] Step 3: Canonical query prompt and action footer verified.",
          flush=True)

    # Step 4: Verify in-place echo discipline (no full redraws on keystrokes)
    print("[*] Step 4: Verifying in-place character echo in modal loop...",
          flush=True)
    if "\\x08 \\x08" not in goto_body and "\\b \\b" not in goto_body:
        print("[-] Step 4: Visual backspace sequence missing from modal loop.",
              flush=True)
        return False
    if "hal_console_putc((char)k);" not in goto_body:
        print("[-] Step 4: In-place digit putc missing from modal loop.",
              flush=True)
        return False
    print("[+] Step 4: In-place character echoing verified.", flush=True)

    elapsed = time.time() - start_time
    print(f"[+] All SEC Goto Line tests PASSED in {elapsed:.2f}s!",
          flush=True)
    return True


if __name__ == "__main__":
    if not test_sec_goto_line():
        sys.exit(1)
