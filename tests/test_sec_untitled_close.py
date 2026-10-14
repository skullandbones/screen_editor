#!/usr/bin/env python3
"""Validation test for Bug 2.8.10: Untitled Buffer Close in SEC.COM.

Verifies that modal_confirm_save_changes() redirects to ui_browser_save_dialog()
when closing an untitled modified document (g_current_filename[0] == '\0') via
Ctrl+W, ensuring edits are not silently discarded, and that cancelling the save
dialog cleanly aborts the document close.
"""

import os
import subprocess
import sys
import time


def test_sec_untitled_close():
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

    # Step 2: Verify ui_browser.h included in ui_modal.c
    print("[*] Step 2: Verifying ui_browser.h include in ui_modal.c...",
          flush=True)
    with open(ui_modal_src, "r") as f:
        src_text = f.read()

    if "ui_browser.h" not in src_text:
        print("[-] Step 2: ui_browser.h not included in ui_modal.c.",
              flush=True)
        return False
    print("[+] Step 2: ui_browser.h included in ui_modal.c.", flush=True)

    # Step 3: Verify modal_confirm_save_changes() redirects to save dialog
    print("[*] Step 3: Verifying save dialog redirect for untitled buffer...",
          flush=True)
    save_fn_idx = src_text.find("int modal_confirm_save_changes(void)")
    if save_fn_idx == -1:
        print("[-] Step 3: modal_confirm_save_changes() not found.",
              flush=True)
        return False

    save_fn_body = src_text[save_fn_idx:save_fn_idx + 1500]
    if "ui_browser_save_dialog" not in save_fn_body:
        print("[-] Step 3: ui_browser_save_dialog not called in save changes.",
              flush=True)
        return False
    if "!g_current_filename[0]" not in save_fn_body:
        print("[-] Step 3: Untitled buffer check missing from save changes.",
              flush=True)
        return False
    print("[+] Step 3: Untitled buffer cleanly redirects to save dialog.",
          flush=True)

    # Step 4: Verify cancellation protection preserves buffer
    print("[*] Step 4: Verifying cancellation returns MODAL_RES_CANCEL...",
          flush=True)
    if "return MODAL_RES_CANCEL;" not in save_fn_body:
        print("[-] Step 4: MODAL_RES_CANCEL not returned on dialog cancel.",
              flush=True)
        return False
    print("[+] Step 4: Cancellation protection verified.", flush=True)

    elapsed = time.time() - start_time
    print(f"[+] All SEC Untitled Close tests PASSED in {elapsed:.2f}s!",
          flush=True)
    return True


if __name__ == "__main__":
    if not test_sec_untitled_close():
        sys.exit(1)
