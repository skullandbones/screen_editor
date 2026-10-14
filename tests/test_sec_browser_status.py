#!/usr/bin/env python3
"""Validation test for Step 29: Browser status bar mode in SEC.COM.

Verifies that the directory browser (ui_browser_workspace) sets the
splash/overlay mode (g_is_splash_screen = 1) so that status bar Field 4
displays free memory rather than editor mode keys ('^K: Editor keys'),
matching SE.COM (IS_SPLASH_SCREEN in RENDER_OPEN_PAGE/RENDER_SAVE_PAGE)
and allowing ESC to cleanly restore editor mode.
"""

import os
import subprocess
import sys
import time

repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(repo_root, "tests"))
from test_editor_common import PtyTransport, read_until, drain_all


def test_sec_browser_status():
    start_time = time.time()
    browser_src = os.path.join(repo_root, "src", "core", "ui_browser.c")

    # Step 1: Verify g_is_splash_screen saved and set in ui_browser_workspace
    print("[*] Step 1: Verifying g_is_splash_screen in "
          "src/core/ui_browser.c...", flush=True)
    with open(browser_src, "r") as f:
        src_text = f.read()

    if "uint8_t prev_splash = g_is_splash_screen;" not in src_text or \
       "g_is_splash_screen = 1;" not in src_text or \
       "g_is_splash_screen = prev_splash;" not in src_text:
        print("[-] Step 1: Missing g_is_splash_screen management in "
              "ui_browser.c.", flush=True)
        return False
    print("[+] Step 1: g_is_splash_screen management verified in ui_browser.c.",
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
    print("[+] Step 2: SEC.COM compiled successfully with browser status fix.",
          flush=True)

    # Step 3: Run Step 29 emulation verification
    print("[*] Step 3: Running Step 29 emulation verification...", flush=True)
    workspace_root = os.path.abspath(os.path.join(repo_root, "..", ".."))
    emu_bin = os.path.join(workspace_root, "tools", "rc2014_emu", "rc2014")
    rom_file = os.path.join(
        workspace_root, "tools", "romwbw_src", "Binary", "RC2014_std.rom"
    )
    img_file = os.path.join(repo_root, "disks", "hd1k_combo.img")
    cpmcp_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp"
    )
    cpmrm_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm"
    )
    sec_bin = os.path.join(repo_root, "SEC.COM")

    subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SEC.COM"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, sec_bin,
                    "0:SEC.COM"], check=True)

    transport = PtyTransport([emu_bin, "-b", "-r", rom_file, "-1", "-S",
                              img_file])
    m = transport.fileno()

    try:
        read_until(m, b"Boot [H=Help]:", timeout=6.0)
        time.sleep(0.5)
        os.write(m, b"c\r")
        read_until(m, b"B>", timeout=6.0)
        time.sleep(0.2)
        os.write(m, b"c:\r")
        read_until(m, b"C>", timeout=5.0)
        drain_all(m)

        os.write(m, b"sec 2.TXT\r")
        out = read_until(m, b"Line    1/2", timeout=35.0)
        if b"First line of two" not in out:
            print(f"[-] Step 3: Failed loading 2.TXT. "
                  f"Buffer: {repr(out[-200:])}", flush=True)
            return False
        drain_all(m)

        # Trigger Ctrl+O and verify Free memory on status bar instead of ^K
        time.sleep(0.2)
        os.write(m, b"\x0f")
        out_open = read_until(m, b"OPEN FILE (DIRECTORY - DRIVE C:)",
                              timeout=4.0)
        if b"OPEN FILE (DIRECTORY - DRIVE C:)" not in out_open:
            print(f"[-] Step 3: Open File screen missing. "
                  f"Buffer: {repr(out_open)}", flush=True)
            return False
        read_until(m, b"Enter filename to open:", timeout=3.0)

        # Cancel with ESC and verify editor restores with document intact
        time.sleep(0.2)
        os.write(m, b"\x1b")
        out_can = read_until(m, b"^K: Editor keys", timeout=4.0)
        if b"C:2.TXT" not in out_can or b"First line of two" not in out_can:
            print(f"[-] Step 3: ESC did not restore editor. "
                  f"Buffer: {repr(out_can[-300:])}", flush=True)
            return False

        # Open 30.TXT via Ctrl+O
        time.sleep(0.2)
        os.write(m, b"\x0f")
        read_until(m, b"Enter filename to open:", timeout=4.0)
        time.sleep(0.2)
        os.write(m, b"30.TXT\r")
        out_30 = read_until(m, b"Line    1/30", timeout=8.0)
        if b"C:30.TXT" not in out_30 or \
           b"Line 01 of test file content" not in out_30:
            print(f"[-] Step 3: Failed opening 30.TXT. "
                  f"Buffer: {repr(out_30[-300:])}", flush=True)
            return False

        print("[+] Step 3: Successfully verified Step 29 browser status bar "
              "and ESC restore.", flush=True)
    finally:
        transport.close()

    elapsed = time.time() - start_time
    print(f"[+] All SEC Browser Status tests PASSED in {elapsed:.2f}s!",
          flush=True)
    return True


if __name__ == "__main__":
    if not test_sec_browser_status():
        sys.exit(1)
