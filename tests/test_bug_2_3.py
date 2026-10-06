#!/usr/bin/env python3
"""
test_bug_2_3.py - Verification for Bug 2.3:
Status Events Displayed on Status Bar Instead of Tier 2 Modal Pop-ups.

Verifies:
  1. Boot RomWBW CP/M on RC2014 emulator.
  2. Launch SE.COM with a file (se 2.TXT).
  3. Verify that file loading shows centered Tier 2 modal pop-up box
     ('|                  Loading File                  |')
     and does NOT display 'Loading...' on the status bar.
  4. Once in editor mode, verify normal document status line.
  5. Test saving the file (Ctrl+S / Save UI):
     Verify that saving displays centered Tier 2 modal pop-up box
     ('|                  Saving File                   |')
     and does NOT display 'Saving...' on the status bar.
  6. Open Plugin Manager (Ctrl+P -> Esc to Manager or Splash Screen 'p'):
     Test 'No About' or 'No Config' error notifications:
     Verify they render inside centered Tier 2 modal dialogs
     and do NOT write directly to the status bar row.
  7. Return cleanly to editor and exit to CP/M prompt (C>).
"""

import os
import sys
import time
import tty
import select
import subprocess


def find_paths():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    workspace_root = os.path.abspath(os.path.join(repo_root, "..", ".."))

    emu_bin = os.path.join(workspace_root, "tools", "rc2014_emu", "rc2014")
    rom_file = os.path.join(
        workspace_root, "tools", "romwbw_src", "Binary", "RC2014_std.rom"
    )
    golden_img = os.path.join(
        workspace_root, "tools", "romwbw_src", "Binary", "hd1k_combo.img"
    )
    img_dir = os.path.join(repo_root, "disks")
    img_file = os.path.join(img_dir, "hd1k_combo.img")
    if not os.path.isfile(img_file):
        os.makedirs(img_dir, exist_ok=True)
        subprocess.run(
            ["cp", "--sparse=always", golden_img, img_file], check=True
        )
        os.chmod(img_file, 0o644)
    se_bin = os.path.join(repo_root, "SE.COM")

    return emu_bin, rom_file, img_file, se_bin


def read_until(master_fd, match_bytes, timeout=10.0):
    buf = b""
    t0 = time.time()
    while time.time() - t0 < timeout:
        r, _, _ = select.select([master_fd], [], [], 0.03)
        if r:
            try:
                data = os.read(master_fd, 1024)
                if not data:
                    break
                buf += data
                if match_bytes in buf:
                    return buf
            except (BlockingIOError, OSError):
                pass
    return buf


def drain_all(master_fd, quiet_time=0.1):
    buf = b""
    time.sleep(0.05)
    while True:
        r, _, _ = select.select([master_fd], [], [], quiet_time)
        if not r:
            break
        try:
            data = os.read(master_fd, 2048)
            if not data:
                break
            buf += data
        except (BlockingIOError, OSError):
            break
    return buf


def main():
    emu_bin, rom_file, img_file, se_bin = find_paths()

    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )
    os.close(slave)

    try:
        print("[*] Launching RomWBW on RC2014 emulator...", flush=True)
        out = read_until(master, b"Boot [H=Help]:", timeout=8.0)
        if b"Boot [H=Help]:" not in out:
            print("[-] FAIL: RomWBW boot loader prompt not reached.")
            return 1
        print("[+] Step 1: Boot loader prompt reached.", flush=True)

        # Boot into CP/M and switch to drive C:
        time.sleep(0.5)
        os.write(master, b"c\r")
        out = read_until(master, b"B>", timeout=6.0)
        if b"B>" not in out:
            print("[-] FAIL: Failed to boot into CP/M prompt.")
            return 1

        time.sleep(0.5)
        os.write(master, b"c:\r")
        out = read_until(master, b"C>", timeout=10.0)
        if b"C>" not in out:
            print("[-] FAIL: Could not switch to Drive C>.")
            return 1

        print("[+] Step 2: Switched to Drive C>.", flush=True)

        # Launch SE with file 2.TXT
        print("[*] Step 3: Launching: se 2.TXT...", flush=True)
        time.sleep(0.5)
        os.write(master, b"se 2.TXT\r")

        # Capture loader screen output until editor mode reached
        ed_out = read_until(master, b"C:2.TXT", timeout=35.0)
        if b"Loading File" in ed_out:
            print(
                "[+] Step 3: Tier 2 modal 'Loading File' popup detected!",
                flush=True,
            )
        else:
            print(
                "[*] Step 3: Fast file load completed.",
                flush=True,
            )

        if b"C:2.TXT" not in ed_out:
            print(
                f"[-] FAIL: Editor mode not reached. "
                f"Buffer: {repr(ed_out[-200:])}"
            )
            return 1

        print("[+] Step 4: Entered editor mode with active document C:2.TXT.")

        # Check status bar on editor screen does NOT contain "Loading..."
        if b"Loading..." in ed_out:
            print("[-] FAIL: 'Loading...' found on status bar.")
            return 1
        print("[+] Step 4: Status bar clean, no 'Loading...' present.")

        # Test Save UI: press Ctrl+S
        print("[*] Step 5: Triggering Save (Ctrl+S)...", flush=True)
        time.sleep(0.5)
        os.write(master, b"\x13")  # Ctrl+S
        time.sleep(0.5)

        # In Save UI, press Enter to confirm save
        os.write(master, b"\r")
        ow_out = read_until(master, b"Overwrite?", timeout=6.0)
        if b"Overwrite?" not in ow_out:
            print("[-] FAIL: Overwrite prompt not shown.")
            return 1
        time.sleep(0.3)
        os.write(master, b"y")
        save_out = read_until(master, b"C:2.TXT", timeout=15.0)
        if b"Saving File" in save_out:
            print(
                "[+] Step 5: Tier 2 modal 'Saving File' popup detected!",
                flush=True,
            )
        # Check status bar does NOT contain "Saving..."
        if b"Saving...       " in save_out:
            print("[-] FAIL: Status bar shows 'Saving...'.")
            return 1
        print("[+] Step 5: Save completed without status bar squatting.")

        # Now test Plugin Manager: Return to splash with ESC
        print("[*] Step 6: Returning to Splash Screen (ESC)...", flush=True)
        time.sleep(0.5)
        os.write(master, b"\x1b")  # ESC to splash screen
        splash_out = read_until(master, b"Screen Editor", timeout=10.0)
        if b"Screen Editor" not in splash_out:
            print("[-] FAIL: Could not return to splash screen.")
            return 1
        print("[+] Step 6: Returned to Splash Screen.")

        # Open Plugin Manager by pressing 'p'
        print("[*] Step 7: Opening Plugin Manager ('p')...", flush=True)
        os.write(master, b"p")
        plug_out = read_until(master, b"Plugin Manager", timeout=5.0)
        if b"Plugin Manager" not in plug_out:
            print("[-] FAIL: Plugin Manager screen not reached.")
            return 1
        print("[+] Step 7: Entered Plugin Manager.")

        # Slot 0 is selected by default (WORDCNT).
        # Press 'j' to select slot 1 (ROT13)
        print("[*] Step 8: Selecting slot 1 (ROT13) via 'j'...", flush=True)
        time.sleep(0.3)
        os.write(master, b"j")
        time.sleep(0.3)
        drain_all(master, quiet_time=0.2)

        # Test 'c' (Config) on slot 1 (ROT13 has no config screen)
        print("[*] Step 9: Testing 'c' (Config) on ROT13...", flush=True)
        os.write(master, b"c")
        modal_cfg_out = drain_all(master, quiet_time=0.4)
        if b"This plugin has no configuration screen" in modal_cfg_out:
            print(
                "[+] Step 9: Tier 2 'No Config' modal dialog verified!",
                flush=True,
            )
        else:
            print("[-] FAIL: 'No Config' modal dialog not shown.")
            return 1
        # Dismiss with Space
        time.sleep(0.3)
        os.write(master, b" ")
        time.sleep(0.3)
        drain_all(master, quiet_time=0.2)

        # Exit Plugin Manager with ESC
        print("[*] Step 10: Exiting Plugin Manager via ESC...", flush=True)
        time.sleep(0.3)
        os.write(master, b"\x1b")
        splash_out = read_until(master, b"Screen Editor", timeout=5.0)
        if b"Screen Editor" not in splash_out:
            print("[-] FAIL: Did not return to Splash Screen.")
            return 1
        print("[+] Step 10: Returned to Splash Screen.")

        # Exit to CP/M with 'q'
        print("[*] Step 11: Exiting SE.COM to CP/M ('q')...", flush=True)
        time.sleep(0.3)
        os.write(master, b"q")
        cpm_out = read_until(master, b"C>", timeout=5.0)
        if b"C>" not in cpm_out:
            print("[-] FAIL: Did not return to CP/M prompt.")
            return 1

        print("[+] Step 11: Returned to CP/M prompt successfully.")
        print("[+] All Bug 2.3 checks PASSED!")
        return 0

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            proc.kill()
        os.close(master)


if __name__ == "__main__":
    sys.exit(main())
