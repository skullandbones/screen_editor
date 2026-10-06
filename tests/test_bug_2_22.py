#!/usr/bin/env python3
"""
Automated Test for Bug 2.22:
Non-Standard Dismissal Prompts in About, Memory, Help, and FAT Plugin.

Verifies:
  1. FAT Plugin About Dialog (Plugin Mgr -> Slot 3 -> 'a'):
     - Prompt is canonical:
       "|           Press any key to continue            |".
     - Prohibited prompt "Press any key to close" is absent.
     - Dismissal via space cleanly returns to Plugin Manager.
  2. About Screen ('a'):
     - Prompt is canonical: "Press any key to continue" (centered, col 0 '~').
     - Prohibited prompt "Press any key to return to splash" is absent.
     - Dismissal via space cleanly returns to splash screen.
  3. Memory Map Screen ('m'):
     - Prompt is canonical: "Press any key to continue" (centered, col 0 '~').
     - Prohibited prompt "Press any key to return to splash screen" is absent.
     - Dismissal via space cleanly returns to splash screen.
  4. Help Keys Screen (Ctrl+K):
     - Prompt is canonical: "Press any key to continue" (centered, col 0 '~').
     - Prohibited prompt "Press any key to return to editor" is absent.
     - Dismissal via space cleanly returns to editor mode.
  5. Both 80x24 and 120x40 screen geometries are verified.
  6. Clean exit to CP/M prompt.
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
    img_file = os.path.join(repo_root, "disks", "hd1k_combo.img")
    se_bin = os.path.join(repo_root, "SE.COM")

    return repo_root, emu_bin, rom_file, img_file, se_bin


def read_until(master_fd, match_bytes, timeout=12.0):
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
                    return True, buf
            except (BlockingIOError, OSError):
                pass
        time.sleep(0.01)
    return False, buf


def drain_all(master_fd, timeout=0.2):
    buf = b""
    t0 = time.time()
    while time.time() - t0 < timeout:
        r, _, _ = select.select([master_fd], [], [], 0.02)
        if r:
            try:
                data = os.read(master_fd, 1024)
                if not data:
                    break
                buf += data
            except (BlockingIOError, OSError):
                break
        else:
            break
    return buf


def test_dismissal_prompts():
    print("[*] Starting Bug 2.22 Standardized Dismissal Prompts Test...")
    repo_root, emu_bin, rom_file, img_file, se_bin = find_paths()

    for p, name in [
        (emu_bin, "RC2014 emulator"),
        (rom_file, "ROM file"),
        (img_file, "Disk image"),
        (se_bin, "SE.COM"),
    ]:
        assert os.path.isfile(p), f"Required file not found: {name} ({p})"

    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )
    os.close(slave)

    try:
        # Boot RomWBW CP/M
        ok, out = read_until(master, b"Boot [H=Help]:", timeout=8.0)
        assert ok, f"RomWBW boot failed: {out}"
        time.sleep(0.3)
        os.write(master, b"c\r")
        ok, out = read_until(master, b"B>", timeout=6.0)
        assert ok, f"Failed to reach B>: {out}"
        time.sleep(0.3)
        os.write(master, b"c:\r")
        ok, out = read_until(master, b"C>", timeout=10.0)
        assert ok, f"Failed to switch to C>: {out}"

        # Launch SE.COM
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"se\r")
        ok, out = read_until(master, b"SE - Screen Editor", timeout=35.0)
        assert ok, f"SE splash screen failed: {out}"
        print("[+] Splash screen loaded.")
        drain_all(master)

        # ---------------------------------------------------------------------
        # Case 1: FAT Plugin About Modal Dismissal Prompt
        # ---------------------------------------------------------------------
        print("[*] Case 1: Testing FAT Plugin About Modal Dismissal Prompt...")
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"p")  # Open Plugin Manager
        ok, out = read_until(master, b"SE - Plugin Manager", timeout=8.0)
        assert ok, f"Failed to open Plugin Manager: {out}"
        drain_all(master)

        # Load FATFS.PRL into Slot 3
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"l")
        ok, out = read_until(master, b"Load Plugin", timeout=6.0)
        assert ok, f"Load Plugin screen not shown: {out}"
        time.sleep(0.2)
        os.write(master, b"FATFS.PRL\r")
        ok, out = read_until(master, b"FAR (32KB)", timeout=20.0)
        assert ok, f"Failed to load FATFS.PRL: {out}"
        print("[+] FATFS.PRL loaded into Slot 3.")
        drain_all(master)

        # Action 'a' (About dialog for FATFS)
        time.sleep(0.2)
        os.write(master, b"a")
        ok, out = read_until(
            master, b"|           Press any key to continue            |",
            timeout=8.0
        )
        assert ok, f"FAT About dialog missing canonical prompt: {out}"
        assert b"Press any key to close" not in out, (
            f"FAT About dialog has non-standard 'Press any key to close': {out}"
        )
        print("    [+] FAT About dialog displays canonical 50-col prompt.")

        # Dismiss with space
        time.sleep(0.2)
        drain_all(master)
        os.write(master, b" ")
        ok, out = read_until(master, b"[Down]=Select", timeout=6.0)
        assert ok, f"Failed to return to Plugin Manager from FAT About: {out}"
        print("    [+] Space returned cleanly to Plugin Manager.")
        drain_all(master)

        # Return to splash ('q')
        time.sleep(0.2)
        os.write(master, b"q")
        ok, out = read_until(master, b"SE - Screen Editor", timeout=6.0)
        assert ok, f"Failed to return to splash: {out}"
        drain_all(master)

        # ---------------------------------------------------------------------
        # Case 2: 80x24 Mode Dismissal Prompts
        # ---------------------------------------------------------------------
        print("[*] Case 2: Testing 80x24 Mode Dismissal Prompts...")
        os.write(master, b"2")  # Mode 80x24
        time.sleep(0.2)
        drain_all(master)

        # Subtest 2.1: About Screen ('a')
        print("    [*] Subtest 2.1: About Screen ('a')...")
        os.write(master, b"a")
        ok, out = read_until(master, b"Press any key to continue", timeout=6.0)
        assert ok, f"About screen missing 'Press any key to continue': {out}"
        ok, out_more = read_until(master, b"\x1b[0m", timeout=3.0)
        out += out_more
        assert b"return to splash" not in out, (
            f"About screen contains non-standard 'return to splash': {out}"
        )
        # Symmetrical centering: '~' + 27 spaces + "Press any key to continue"
        expected_about_80 = b"~" + (b" " * 27) + b"Press any key to continue"
        assert expected_about_80 in out, (
            f"About screen footer not centered in 80x24: {out}"
        )
        print("    [+] About screen has centered 'Press any key to continue'.")

        # Dismiss About with Space
        time.sleep(0.2)
        drain_all(master)
        os.write(master, b" ")
        ok, out = read_until(master, b"for about", timeout=6.0)
        assert ok, f"Failed to return to splash from About: {out}"
        print("    [+] Space returned cleanly to splash screen.")
        drain_all(master)

        # Subtest 2.2: Memory Screen ('m')
        print("    [*] Subtest 2.2: Memory Map Screen ('m')...")
        os.write(master, b"m")
        ok, out = read_until(master, b"Press any key to continue", timeout=6.0)
        assert ok, f"Memory screen missing 'Press any key to continue': {out}"
        ok, out_more = read_until(master, b"\x1b[0m", timeout=3.0)
        out += out_more
        assert b"return to splash screen" not in out, (
            f"Memory screen has non-standard 'return to splash screen': {out}"
        )
        # Centering within 72-col block: 23 spaces padding
        assert b"                       Press any key to continue" in out, (
            f"Memory screen prompt not centered in 72-col block: {out}"
        )
        print("    [+] Memory screen has centered 'Press any key to continue'.")

        # Dismiss Memory with Space
        time.sleep(0.2)
        drain_all(master)
        os.write(master, b" ")
        ok, out = read_until(master, b"for memory info", timeout=6.0)
        assert ok, f"Failed to return to splash from Memory: {out}"
        print("    [+] Space returned cleanly to splash screen.")
        drain_all(master)

        # Subtest 2.3: Help Screen (Ctrl+K in editor)
        print("    [*] Subtest 2.3: Help Screen (Ctrl+K in editor)...")
        os.write(master, b"e")
        ok, out = read_until(master, b"^K: Editor keys", timeout=6.0)
        assert ok, f"Failed to enter editor: {out}"
        drain_all(master)

        time.sleep(0.2)
        os.write(master, b"\x0b")  # Ctrl+K
        ok, out = read_until(master, b"Press any key to continue", timeout=6.0)
        assert ok, f"Help screen missing 'Press any key to continue': {out}"
        ok, out_more = read_until(master, b"\x1b[0m", timeout=3.0)
        out += out_more
        assert b"return to editor" not in out, (
            f"Help screen contains non-standard 'return to editor': {out}"
        )
        # Symmetrical centering: '~' + 26 spaces + "Press any key to continue"
        expected_help_80 = b"~" + (b" " * 26) + b"Press any key to continue"
        assert expected_help_80 in out, (
            f"Help screen footer not centered in 80x24: {out}"
        )
        print("    [+] Help screen has centered 'Press any key to continue'.")

        # Dismiss Help with Space
        time.sleep(0.2)
        drain_all(master)
        os.write(master, b" ")
        ok, out = read_until(master, b"^K: Editor keys", timeout=6.0)
        assert ok, f"Failed to return to editor from Help: {out}"
        print("    [+] Space returned cleanly to editor.")
        drain_all(master)

        # Return to splash screen with ESC
        time.sleep(0.2)
        os.write(master, b"\x1b")
        ok, out = read_until(master, b"SE - Screen Editor", timeout=6.0)
        assert ok, f"Failed to return to splash via ESC: {out}"
        drain_all(master)

        # ---------------------------------------------------------------------
        # Case 3: 120x40 Mode Dismissal Prompts
        # ---------------------------------------------------------------------
        print("[*] Case 3: Testing 120x40 Mode Dismissal Prompts...")
        time.sleep(0.3)
        os.write(master, b"1")  # Select 120x40
        ok, out = read_until(master, b"SE - Screen Editor", timeout=5.0)
        assert ok, f"Failed to select 120x40 mode: {out}"
        time.sleep(0.2)
        drain_all(master)

        # Subtest 3.1: About Screen in 120x40
        print("    [*] Subtest 3.1: About Screen in 120x40...")
        os.write(master, b"a")
        ok, out = read_until(master, b"Press any key to continue", timeout=6.0)
        assert ok, f"120x40 About missing 'Press any key to continue': {out}"
        ok, out_more = read_until(master, b"\x1b[0m", timeout=3.0)
        out += out_more
        # Centering in 120 cols: '~' + 47 spaces + "Press any key to continue"
        expected_about_120 = b"~" + (b" " * 47) + b"Press any key to continue"
        assert expected_about_120 in out, (
            f"About screen footer not centered in 120x40: {out}"
        )
        print("    [+] 120x40 About screen centered prompt verified.")

        time.sleep(0.2)
        drain_all(master)
        os.write(master, b" ")
        ok, out = read_until(master, b"for about", timeout=6.0)
        assert ok, f"Failed to return to splash: {out}"
        drain_all(master)

        # Subtest 3.2: Memory Screen in 120x40
        print("    [*] Subtest 3.2: Memory Map Screen in 120x40...")
        os.write(master, b"m")
        ok, out = read_until(master, b"Press any key to continue", timeout=6.0)
        assert ok, f"120x40 Memory missing 'Press any key to continue': {out}"
        ok, out_more = read_until(master, b"\x1b[0m", timeout=3.0)
        out += out_more
        # Table block is 72 cols, prefix pads (120 - 74)/2 = 23 spaces
        assert b"                       Press any key to continue" in out, (
            f"120x40 Memory prompt not centered: {out}"
        )
        print("    [+] 120x40 Memory screen prompt verified.")

        time.sleep(0.2)
        drain_all(master)
        os.write(master, b" ")
        ok, out = read_until(master, b"for memory info", timeout=6.0)
        assert ok, f"Failed to return to splash: {out}"
        drain_all(master)

        # Subtest 3.3: Help Screen in 120x40
        print("    [*] Subtest 3.3: Help Screen in 120x40...")
        os.write(master, b"e")
        ok, out = read_until(master, b"^K: Editor keys", timeout=6.0)
        assert ok, f"Failed to enter editor: {out}"
        drain_all(master)

        time.sleep(0.2)
        os.write(master, b"\x0b")  # Ctrl+K
        ok, out = read_until(master, b"Press any key to continue", timeout=6.0)
        assert ok, f"120x40 Help missing 'Press any key to continue': {out}"
        ok, out_more = read_until(master, b"\x1b[0m", timeout=3.0)
        out += out_more
        # Symmetrical centering: '~' + 46 spaces + "Press any key to continue"
        expected_help_120 = b"~" + (b" " * 46) + b"Press any key to continue"
        assert expected_help_120 in out, (
            f"120x40 Help screen footer not centered: {out}"
        )
        print("    [+] 120x40 Help screen centered prompt verified.")

        time.sleep(0.2)
        drain_all(master)
        os.write(master, b" ")
        ok, out = read_until(master, b"^K: Editor keys", timeout=6.0)
        assert ok, f"Failed to return to editor from Help: {out}"
        drain_all(master)

        # Return to splash screen with ESC
        time.sleep(0.2)
        os.write(master, b"\x1b")
        ok, out = read_until(master, b"SE - Screen Editor", timeout=6.0)
        assert ok, f"Failed to return to splash via ESC: {out}"
        drain_all(master)

        # ---------------------------------------------------------------------
        # Case 4: Clean exit to CP/M
        # ---------------------------------------------------------------------
        print("[*] Case 4: Exiting cleanly to CP/M...")
        time.sleep(0.2)
        os.write(master, b"q")
        ok, out = read_until(master, b"C>", timeout=8.0)
        assert ok, f"Failed to return to CP/M: {out}"
        print("[+] Returned to CP/M cleanly.")

        print("\n=======================================================")
        print("  BUG 2.22 VERIFICATION PASSED (100%)!")
        print("=======================================================\n")
        return 0

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=1.0)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass
        try:
            os.close(master)
        except Exception:
            pass


if __name__ == "__main__":
    sys.exit(test_dismissal_prompts())
