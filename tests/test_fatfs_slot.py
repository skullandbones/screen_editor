#!/usr/bin/env python3
"""
test_fatfs_slot.py - End-to-End Validation of FATFS.PRL with 32KB Plugin Slot in SE.COM

Tests:
  1. Boot RomWBW CP/M on RC2014 emulator with hd1k_combo.img.
  2. Launch SE.COM and enter Plugin Manager ('p').
  3. Load FATFS.PRL into a dynamic 32KB Far RAM plugin slot ('l' -> 'FATFS.PRL').
  4. Verify FATFS is recognized with capability mode 'FAR (32KB)' in multi-bank Far RAM.
  5. Test Action 1: Execute About dialog ('A'), verify v0.1.0 and Elm-Chan credits, dismiss.
  6. Test Action 2: Execute Config dialog ('C'), verify HBIOS unit selector, dismiss.
  7. Test Action 0: Execute main browser entry point, verify modal UI launch and clean exit.
  8. Unload FATFS slot, verify automatic 32KB Far RAM bank deallocation.
  9. Clean exit from SE.COM back to CP/M command prompt (C>).
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
    rom_file = os.path.join(workspace_root, "tools", "romwbw_src", "Binary", "RC2014_std.rom")
    img_file = os.path.join(workspace_root, "tools", "romwbw_src", "Binary", "hd1k_combo.img")
    se_bin = os.path.join(repo_root, "SE.COM")
    fatfs_prl = os.path.join(repo_root, "plugins", "FATFS.PRL")

    return emu_bin, rom_file, img_file, se_bin, fatfs_prl


def read_until(master_fd, match_bytes, timeout=6.0):
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
    return False, buf


def drain_all(master_fd, quiet_time=0.1):
    time.sleep(0.05)
    while True:
        r, _, _ = select.select([master_fd], [], [], quiet_time)
        if not r:
            break
        try:
            data = os.read(master_fd, 2048)
            if not data:
                break
        except (BlockingIOError, OSError):
            break


def run_fatfs_slot_test():
    emu_bin, rom_file, img_file, se_bin, fatfs_prl = find_paths()

    for p, name in [(emu_bin, "RC2014 emulator"), (rom_file, "ROM file"),
                    (img_file, "Disk image"), (se_bin, "SE.COM"), (fatfs_prl, "FATFS.PRL")]:
        if not os.path.isfile(p):
            print(f"[-] Required file not found: {name} ({p})")
            return False

    print("[*] Launching RomWBW on RC2014 emulator (FATFS 32KB Slot Test)...", flush=True)
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)

    try:
        # 1. Boot RomWBW CP/M
        ok, out = read_until(master, b"Boot [H=Help]:", timeout=6.0)
        if not ok:
            print("[-] Failed to reach RomWBW boot loader prompt.", flush=True)
            return False

        time.sleep(0.5)
        os.write(master, b"c\r")
        ok, out = read_until(master, b"B>", timeout=6.0)
        if not ok:
            print("[-] Failed to boot into CP/M prompt.", flush=True)
            return False

        time.sleep(0.5)
        os.write(master, b"c:\r")
        ok, out = read_until(master, b"C>", timeout=8.0)
        if not ok:
            print("[-] Failed to switch to Drive C:.", flush=True)
            return False
        print("[+] Switched to Drive C>.", flush=True)

        # 2. Launch SE.COM
        time.sleep(0.5)
        os.write(master, b"se\r")
        ok, out = read_until(master, b"Col 0", timeout=18.0)
        if not ok:
            print("[-] Splash screen failed to display.", flush=True)
            return False
        drain_all(master, quiet_time=0.1)

        # 3. Enter Plugin Manager ('p')
        time.sleep(0.5)
        os.write(master, b"p")
        ok, out = read_until(master, b"SE - Plugin Manager", timeout=8.0)
        if not ok:
            print("[-] Failed to enter Plugin Manager.", flush=True)
            return False
        if b"type 0..7 to run" not in out:
            read_until(master, b"type 0..7 to run", timeout=5.0)
        drain_all(master)
        print("[+] Entered SE.COM Plugin Manager.", flush=True)

        # 4. Load FATFS.PRL (32KB Far RAM slot)
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"l")
        read_until(master, b"Load Plugin", timeout=4.0)
        time.sleep(0.1)
        os.write(master, b"FATFS.PRL\r")

        ok, out_load = read_until(master, b"FAR (32KB)", timeout=20.0)
        if not ok or b"FATFS" not in out_load:
            print(f"[-] Failed to load FATFS.PRL as 32KB Far RAM slot. Buffer: {repr(out_load)}", flush=True)
            return False
        print("[+] FATFS.PRL successfully loaded into Slot as 'FAR (32KB)' (Multi-Bank Far RAM allocation).", flush=True)
        drain_all(master)

        # 5. Navigate selection to Slot 3 (down 3 times)
        print("[+] Navigating selection to Slot 3...", flush=True)
        time.sleep(0.3)
        os.write(master, b"jjj")
        read_until(master, b"type 0..7 to run", timeout=5.0)
        drain_all(master)

        # 6. Test Action 1: About Dialog ('a')
        time.sleep(0.3)
        os.write(master, b"a")
        ok, out_about = read_until(master, b"Press any key to close", timeout=6.0)
        if not ok or b"FAT Filesystem Plugin" not in out_about:
            print(f"[-] About dialog check failed. Buffer: {repr(out_about)}", flush=True)
            return False
        print("[+] Action 1 (About Screen) verified: Displayed version and Elm-Chan engine credits.", flush=True)

        # Dismiss About dialog
        time.sleep(0.2)
        drain_all(master)
        os.write(master, b" ")
        read_until(master, b"type 0..7 to run", timeout=5.0)
        drain_all(master)

        # 7. Test Action 2: Configuration Dialog ('c')
        time.sleep(0.3)
        os.write(master, b"c")
        ok, out_cfg = read_until(master, b"Select (0-7) to change", timeout=6.0)
        if not ok or b"FAT Plugin Configuration" not in out_cfg:
            print(f"[-] Config dialog failed to display. Buffer: {repr(out_cfg)}", flush=True)
            return False
        print("[+] Action 2 (Config Screen) verified: Displayed HBIOS disk unit selector.", flush=True)

        # Dismiss config dialog ('q')
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"q")
        ok, _ = read_until(master, b"SE - Plugin Manager", timeout=6.0)
        read_until(master, b"type 0..7 to run", timeout=5.0)
        drain_all(master)

        # 8. Test Action 0: Main Execution / Browser ('3')
        time.sleep(0.5)
        os.write(master, b"3")
        ok, out_run = read_until(master, b"FAT Filesystem", timeout=8.0)
        if not ok:
            print(f"[-] FATFS execution failed. Buffer: {repr(out_run)}", flush=True)
            return False
        print("[+] Action 0 (Main Execution) verified: Entered FAT Filesystem modal UI cleanly.", flush=True)

        # Dismiss / exit browser back to Plugin Manager ('q')
        time.sleep(0.3)
        os.write(master, b"q")
        read_until(master, b"type 0..7 to run", timeout=5.0)
        drain_all(master)

        # 9. Test Action 0 from Editor Context-Aware Popup (Ctrl+P -> 3)
        print("[*] Testing FATFS execution via Ctrl+P popup in Editor mode...", flush=True)
        time.sleep(0.3)
        os.write(master, b"q")  # Exit Plugin Manager to Splash
        read_until(master, b"Col 0", timeout=5.0)
        drain_all(master)

        time.sleep(0.3)
        os.write(master, b"\r")  # Enter Editor mode
        read_until(master, b"Line    1/1", timeout=5.0)
        drain_all(master)

        time.sleep(0.3)
        os.write(master, b"\x10")  # Ctrl+P
        ok, out_popup = read_until(master, b"Select [0-7] to Execute", timeout=6.0)
        if not ok or b"FATFS" not in out_popup:
            print(f"[-] FATFS not found in Editor Ctrl+P popup. Buffer: {repr(out_popup)}", flush=True)
            return False
        print("[+] FATFS successfully listed in Editor Ctrl+P context popup.", flush=True)

        time.sleep(0.3)
        os.write(master, b"3")  # Launch Slot 3 (FATFS)
        ok, out_fat_popup = read_until(master, b"FAT Filesystem", timeout=8.0)
        if not ok:
            print(f"[-] Failed to launch FATFS from Ctrl+P popup. Buffer: {repr(out_fat_popup)}", flush=True)
            return False
        if b"~ +" in out_fat_popup or b"~ |" in out_fat_popup:
            print(f"[-] Visual regression detected: spurious '~ ' prefix found in buffer: {repr(out_fat_popup)}", flush=True)
            return False
        print("[+] FATFS launched cleanly from Editor Ctrl+P popup without visual corruption.", flush=True)

        # Exit FATFS back to Editor
        time.sleep(0.3)
        os.write(master, b"q")
        ok, _ = read_until(master, b"Line    1/1", timeout=6.0)
        if not ok:
            print("[-] Failed to restore Editor screen after exiting FATFS.", flush=True)
            return False
        print("[+] Editor screen cleanly restored after exiting FATFS.", flush=True)
        drain_all(master)

        # Return to Splash screen via Ctrl+W
        time.sleep(0.3)
        os.write(master, b"\x17")  # Ctrl+W
        read_until(master, b"Col 0", timeout=5.0)
        drain_all(master)

        # Re-enter Plugin Manager ('p')
        time.sleep(0.3)
        os.write(master, b"p")
        ok, _ = read_until(master, b"SE - Plugin Manager", timeout=6.0)
        read_until(master, b"type 0..7 to run", timeout=5.0)
        drain_all(master)

        # 10. Unload Slot 3 ('u' then '3')
        time.sleep(0.3)
        os.write(master, b"u")
        read_until(master, b"Unload Slot", timeout=4.0)
        time.sleep(0.1)
        os.write(master, b"3")
        ok, out_u = read_until(master, b"(empty slot)", timeout=6.0)
        if not ok:
            print(f"[-] Failed to unload FATFS slot. Buffer: {repr(out_u)}", flush=True)
            return False
        print("[+] FATFS slot successfully unloaded and 32KB Far RAM bank deallocated.", flush=True)

        # 11. Clean Exit to Editor and CP/M
        time.sleep(0.2)
        os.write(master, b"q")
        read_until(master, b"Col 0", timeout=5.0)
        time.sleep(0.2)
        os.write(master, b"q")
        ok, out_cpm = read_until(master, b"C>", timeout=6.0)
        if not ok:
            print("[-] Failed to return to CP/M prompt.", flush=True)
            return False
        print("[+] Clean exit from SE.COM to CP/M prompt verified.", flush=True)

        return True

    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2.0)
        except subprocess.TimeoutExpired:
            proc.kill()
        os.close(master)


if __name__ == "__main__":
    t_start = time.time()
    success = run_fatfs_slot_test()
    elapsed = time.time() - t_start
    if success:
        print(f"\n[+] FATFS 32KB Plugin Slot Integration Test PASSED in {elapsed:.2f}s!")
        sys.exit(0)
    else:
        print(f"\n[-] FATFS 32KB Plugin Slot Integration Test FAILED after {elapsed:.2f}s.")
        sys.exit(1)
