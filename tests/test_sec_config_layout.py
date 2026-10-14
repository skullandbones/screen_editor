#!/usr/bin/env python3
"""Validation test for Bug 2.8.5: Configuration Manager Workspace in SEC.COM.

Verifies that show_config_screen() conforms to the canonical 5-option hotkey
layout (1 Geometry, 2 RAM Drive, 3 Max Lines, 4 Tab Width, 5 Plugins),
eliminates the prohibited 'Enter option: _' prompt line, displays the canonical
footer, and does not serialize illegal FORMAT parameter into SE.CFG.
"""

import os
import subprocess
import sys
import time


def test_sec_config_layout():
    start_time = time.time()
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sec_bin = os.path.join(repo_root, "SEC.COM")
    ui_render_src = os.path.join(repo_root, "src", "core", "ui_render.c")
    config_src = os.path.join(repo_root, "src", "core", "config.c")

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

    # Step 2: Verify prohibited "Enter option:" prompt is removed
    print("[*] Step 2: Verifying 'Enter option:' is absent from SEC.COM...",
          flush=True)
    if b"Enter option:" in binary_data:
        print("[-] Step 2: Prohibited 'Enter option:' found in SEC.COM binary.",
              flush=True)
        return False

    with open(ui_render_src, "r") as f:
        render_text = f.read()
    if "Enter option:" in render_text:
        print("[-] Step 2: Prohibited 'Enter option:' found in ui_render.c.",
              flush=True)
        return False
    print("[+] Step 2: Prohibited prompt 'Enter option:' cleanly eliminated.",
          flush=True)

    # Step 3: Verify canonical 5 options and footer present in SEC.COM
    print("[*] Step 3: Verifying 5 canonical options and footer in SEC.COM...",
          flush=True)
    expected_strings = [
        b"1. Screen Geometry  :",
        b"2. RAM Drive Mode   :",
        b"3. Max Doc Lines    :",
        b"4. Tab Width        :",
        b"5. Plugin Manager   :",
        b"[1-5]=Toggle Option",
    ]
    missing = [s for s in expected_strings if s not in binary_data]
    if missing:
        print(f"[-] Step 3: Missing config strings from SEC.COM binary: "
              f"{missing}", flush=True)
        return False
    print("[+] Step 3: All 5 options and canonical footer verified.",
          flush=True)

    # Step 4: Verify FORMAT parameter is not serialized in config_save_file()
    print("[*] Step 4: Verifying FORMAT= is not serialized in config...",
          flush=True)
    with open(config_src, "r") as f:
        config_text = f.read()

    save_fn_idx = config_text.find("int config_save_file(")
    if save_fn_idx == -1:
        print("[-] Step 4: config_save_file() not found in config.c.",
              flush=True)
        return False

    save_fn_body = config_text[save_fn_idx:save_fn_idx + 1500]
    if "FORMAT=" in save_fn_body:
        print("[-] Step 4: Found illegal FORMAT= serialization in config.c.",
              flush=True)
        return False
    print("[+] Step 4: FORMAT= parameter serialization successfully removed.",
          flush=True)

    elapsed = time.time() - start_time
    print(f"[+] All SEC Config Layout tests PASSED in {elapsed:.2f}s!",
          flush=True)
    return True


if __name__ == "__main__":
    if not test_sec_config_layout():
        sys.exit(1)
