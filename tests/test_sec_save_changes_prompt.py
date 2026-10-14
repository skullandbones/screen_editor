#!/usr/bin/env python3
"""Validation test for Unsaved Modifications prompt query in SEC.COM.

Verifies that modal_confirm_save_changes() passes 'Save changes?' as the
centered query line on row 4 rather than 'Yes', conforming strictly to
docs/UI_UX_DESIGN.md Section 8.3 (Archetype B) and passing Step 8 in the
sanity test suite.
"""

import os
import subprocess
import sys
import time

repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def test_sec_save_changes_prompt():
    start_time = time.time()
    modal_src = os.path.join(repo_root, "src", "core", "ui_modal.c")

    # Step 1: Verify 'Save changes?' query passed in modal_confirm_save_changes
    print("[*] Step 1: Verifying 'Save changes?' query in "
          "src/core/ui_modal.c...", flush=True)
    with open(modal_src, "r") as f:
        src_text = f.read()

    expected_call = 'modal_confirm("Unsaved Modifications",\n' \
                    '                        ' \
                    '"Any unsaved edits will be lost if discarded.",\n' \
                    '                        "Save changes?", NULL);'
    if expected_call not in src_text:
        print("[-] Step 1: Missing 'Save changes?' query in ui_modal.c.",
              flush=True)
        return False
    print("[+] Step 1: 'Save changes?' query verified in ui_modal.c.",
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
    print("[+] Step 2: SEC.COM compiled successfully with query prompt fix.",
          flush=True)

    # Step 3: Verify fast sanity test passes with SEC.COM
    print("[*] Step 3: Running SEC.COM sanity test...", flush=True)
    img_res = subprocess.run(["make", "image"], cwd=repo_root,
                             stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)
    if img_res.returncode != 0:
        print("[-] Step 3: make image failed.", flush=True)
        return False

    sanity_py = os.path.join(repo_root, "tests", "test_sanity.py")
    test_res = subprocess.run(
        [sys.executable, sanity_py, "--sec"],
        cwd=repo_root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if test_res.returncode != 0:
        print(f"[-] Step 3: SEC.COM sanity test failed. "
              f"Buffer: {repr(test_res.stdout[-300:])}", flush=True)
        return False
    print("[+] Step 3: SEC.COM sanity test passed with "
          "'Save changes?' verified.", flush=True)

    elapsed = time.time() - start_time
    print(f"[+] All SEC Save Changes Prompt tests PASSED in {elapsed:.2f}s!",
          flush=True)
    return True


if __name__ == "__main__":
    if not test_sec_save_changes_prompt():
        sys.exit(1)
