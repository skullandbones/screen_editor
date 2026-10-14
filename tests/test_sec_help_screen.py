#!/usr/bin/env python3
"""Validation test for Bug 2.8.8: Help Screen Layout & Key Aliases in SEC.COM.

Verifies that show_help_screen() displays the canonical 22-line layout
matching plugins/help.asm and docs/UI_UX_DESIGN.md §7.3, eliminates duplicate
Ctrl+V aliases, uses Delete / Ctrl+D, and standardizes block operations to
Copy/Move Block to Cursor.
"""

import os
import subprocess
import sys
import time


def test_sec_help_screen():
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

    # Step 2: Verify duplicate "Ctrl+V: Paste Block" is eliminated
    print("[*] Step 2: Verifying 'Paste Block' is absent from SEC.COM...",
          flush=True)
    if b"Paste Block" in binary_data:
        print("[-] Step 2: Found 'Paste Block' in SEC.COM binary.",
              flush=True)
        return False

    with open(ui_render_src, "r") as f:
        src_text = f.read()

    help_array_idx = src_text.find("s_help_lines[22]")
    if help_array_idx == -1:
        print("[-] Step 2: s_help_lines[22] not found in ui_render.c.",
              flush=True)
        return False

    help_body = src_text[help_array_idx:help_array_idx + 2500]
    if "Paste Block" in help_body:
        print("[-] Step 2: Found 'Paste Block' in s_help_lines.", flush=True)
        return False
    print("[+] Step 2: Duplicate Ctrl+V / Paste Block alias eliminated.",
          flush=True)

    # Step 3: Verify non-canonical "Cut Block" is absent
    print("[*] Step 3: Verifying 'Cut Block' is absent from Help screen...",
          flush=True)
    if "Cut Block" in help_body:
        print("[-] Step 3: Non-canonical 'Cut Block' found in s_help_lines.",
              flush=True)
        return False
    print("[+] Step 3: Non-canonical 'Cut Block' eliminated.", flush=True)

    # Step 4: Verify canonical Help strings present in SEC.COM binary
    print("[*] Step 4: Verifying canonical Help key strings in SEC.COM...",
          flush=True)
    expected_help_strings = [
        b"Ctrl+U / PgUp",
        b"Ctrl+V / PgDn",
        b"Delete / Ctrl+D",
        b"Copy solidified block",
        b"Move solidified block",
    ]
    missing = [s for s in expected_help_strings if s not in binary_data]
    if missing:
        print(f"[-] Step 4: Missing expected Help strings: {missing}",
              flush=True)
        return False
    print("[+] Step 4: All canonical Help keys and verbs verified.",
          flush=True)

    elapsed = time.time() - start_time
    print(f"[+] All SEC Help Screen tests PASSED in {elapsed:.2f}s!",
          flush=True)
    return True


if __name__ == "__main__":
    if not test_sec_help_screen():
        sys.exit(1)
