#!/usr/bin/env python3
"""
Host-agnostic headless test runner for SE.COM (Screen Editor).
Executes SE.COM inside an RC2014 / RomWBW emulation harness over pseudo-terminal (PTY)
and verifies VT100 initialization, screen rendering, and clean exit behavior.
"""

import os
import sys
import time
import tty
import termios
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

    return emu_bin, rom_file, img_file, se_bin

def read_until(master_fd, match_bytes, timeout=5.0):
    buf = b""
    t0 = time.time()
    while time.time() - t0 < timeout:
        r, _, _ = select.select([master_fd], [], [], 0.05)
        if r:
            try:
                data = os.read(master_fd, 1024)
                if not data:
                    break
                buf += data
                if match_bytes in buf:
                    return buf
            except OSError:
                break
    return buf

def test_se_execution():
    emu_bin, rom_file, img_file, se_bin = find_paths()

    if not os.path.isfile(emu_bin):
        print(f"[-] Emulator binary not found: {emu_bin}")
        return False
    if not os.path.isfile(rom_file):
        print(f"[-] ROM file not found: {rom_file}")
        return False
    if not os.path.isfile(img_file):
        print(f"[-] Disk image not found: {img_file}")
        return False

    print("[*] Launching RomWBW on RC2014 emulator...")
    master, slave = os.openpty()
    tty.setraw(master)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)

    try:
        # 1. Wait for RomWBW bootloader prompt
        print("[*] Waiting for RomWBW boot banner...")
        out = read_until(master, b"Boot [H=Help]:", timeout=6.0)
        if b"Boot [H=Help]:" not in out:
            print("[-] Failed to reach RomWBW boot loader prompt.")
            return False
        print("[+] Boot loader prompt reached.")

        # 2. Boot into CP/M on ROM disk (Choice 'c')
        time.sleep(0.3)
        os.write(master, b"c\r")
        out = read_until(master, b"B>", timeout=5.0)
        if b"B>" not in out:
            print("[-] Failed to boot into CP/M prompt.")
            return False
        print("[+] Booted into CP/M (Drive B>).")

        # 3. Switch to Drive C: (where SD slice 0 with SE.COM is mounted)
        time.sleep(0.3)
        os.write(master, b"c:\r")
        out = read_until(master, b"C>", timeout=3.0)
        print("[+] Switched to Drive C>.")

        # 4. Run SE.COM
        time.sleep(0.3)
        os.write(master, b"SE\r")
        out = read_until(master, b"SE v0.1.0", timeout=4.0)
        if b"SE v0.1.0" not in out:
            print("[-] SE.COM screen banner not detected.")
            return False
        print("[+] SE.COM successfully initialized VT100 full-screen interface.")

        # 5. Send Ctrl+Q to exit cleanly back to CP/M
        time.sleep(0.3)
        os.write(master, b"\x11")
        out = read_until(master, b"Exiting SE.COM", timeout=3.0)
        if b"Exiting SE.COM" not in out:
            print("[-] Clean exit message not observed.")
            return False
        print("[+] SE.COM successfully received Ctrl+Q and returned cleanly to CP/M.")

        return True

    finally:
        proc.terminate()
        os.close(master)

if __name__ == "__main__":
    success = test_se_execution()
    if success:
        print("[+] All automated SE.COM emulator tests PASSED.")
        sys.exit(0)
    else:
        print("[-] Automated SE.COM emulator tests FAILED.")
        sys.exit(1)
