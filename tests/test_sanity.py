#!/usr/bin/env python3
"""
Fast Sanity Test Runner for SE.COM (Screen Editor).
Verifies the core lifecycle of SE.COM in ~4 seconds:
  1. Boot RomWBW and start SE.COM from CP/M
  2. Verify Splash Screen rendering
  3. Enter Editor Mode and verify Status Bar
  4. Type text and verify character buffer rendering
  5. Toggle Block Selection (Ctrl+B) and verify [SEL: 0c]
  6. Cancel Block Selection (Ctrl+B)
  7. Open Editor Mode Keys Help (Ctrl+K) and return to editor
  8. Clean exit (Ctrl+Q) back to CP/M prompt (C>)
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

    return emu_bin, rom_file, img_file, se_bin

def read_until(master_fd, match_bytes, timeout=5.0):
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

def run_sanity_test():
    t_start = time.time()
    emu_bin, rom_file, img_file, se_bin = find_paths()

    if not os.path.isfile(emu_bin):
        print(f"[-] Emulator binary not found: {emu_bin}", flush=True)
        return False
    if not os.path.isfile(rom_file):
        print(f"[-] ROM file not found: {rom_file}", flush=True)
        return False
    if not os.path.isfile(img_file):
        print(f"[-] Disk image not found: {img_file}", flush=True)
        return False

    print("[*] Launching RomWBW on RC2014 emulator (Sanity Suite)...", flush=True)
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)

    try:
        # 1. Boot loader prompt
        out = read_until(master, b"Boot [H=Help]:", timeout=6.0)
        if b"Boot [H=Help]:" not in out:
            print("[-] Failed to reach RomWBW boot loader prompt.", flush=True)
            return False

        # 2. Boot CP/M on ROM disk (Choice 'c') and switch to Drive C:
        time.sleep(0.5)
        os.write(master, b"c\r")
        out = read_until(master, b"B>", timeout=6.0)
        if b"B>" not in out:
            print("[-] Failed to boot into CP/M prompt.", flush=True)
            return False

        time.sleep(0.5)
        os.write(master, b"c:\r")
        out = read_until(master, b"C>", timeout=10.0)
        if b"C>" not in out:
            print(f"[-] Failed to switch to Drive C:. Buffer captured: {repr(out)}", flush=True)
            return False
        print("[+] Switched to Drive C>.", flush=True)

        # 3. Launch SE.COM
        time.sleep(0.5)
        os.write(master, b"se\r")
        out = read_until(master, b"Auto-detects CP/M [CRLF]", timeout=14.0)
        if b"Auto-detects CP/M [CRLF]" not in out:
            print(f"[-] SE.COM splash screen not detected. Buffer: {repr(out)}", flush=True)
            return False
        print("[+] Splash screen displayed successfully.", flush=True)

        # 4. Enter Editor Mode ('e')
        time.sleep(0.1)
        os.write(master, b"e")
        out_edit = read_until(master, b"Line 1/1,", timeout=4.0)
        if b"SE v0.7.4" not in out_edit or b"[No Name]" not in out_edit:
            print(f"[-] Failed to enter editor mode. Buffer: {repr(out_edit)}", flush=True)
            return False
        print("[+] Entered editor mode with status bar verified.", flush=True)

        # 5. Type 'SANITY CHECK OK'
        os.write(master, b"SANITY CHECK OK")
        out_typed = read_until(master, b"Col 16", timeout=3.0)
        if b"SANITY CHECK OK" not in out_typed:
            print(f"[-] Text insertion failed. Buffer: {repr(out_typed)}", flush=True)
            return False
        print("[+] Text insertion and cursor tracking verified.", flush=True)

        # 6. Test Block Mode toggle: Ctrl+B to start, verify [SEL: 0c], Ctrl+B to toggle off
        os.write(master, b"\x02")
        out_blk = read_until(master, b"[SEL: 0c]", timeout=3.0)
        if b"[SEL: 0c]" not in out_blk:
            print(f"[-] Block mode activation failed. Buffer: {repr(out_blk)}", flush=True)
            return False
        os.write(master, b"\x02")
        out_unblk = read_until(master, b"^K: Editor keys", timeout=3.0)
        if b"^K: Editor keys" not in out_unblk:
            print(f"[-] Block mode deactivation failed. Buffer: {repr(out_unblk)}", flush=True)
            return False
        print("[+] Block mode toggle verified.", flush=True)

        # 7. Test Editor Mode Keys Help Screen: Ctrl+K, then return with Enter
        os.write(master, b"\x0b")
        out_help = read_until(master, b"Press any key to return to editor", timeout=3.0)
        if b"EDITOR MODE KEYS" not in out_help:
            print(f"[-] Help screen failed. Buffer: {repr(out_help)}", flush=True)
            return False
        os.write(master, b"\r")
        out_back = read_until(master, b"Line 1/1,", timeout=3.0)
        if b"SANITY CHECK OK" not in out_back:
            print(f"[-] Return from help screen failed. Buffer: {repr(out_back)}", flush=True)
            return False
        print("[+] Help screen and return verified.", flush=True)

        # 8. Clean exit to CP/M with Ctrl+Q
        time.sleep(0.1)
        os.write(master, b"\x11")
        out_exit = read_until(master, b"C>", timeout=4.0)
        if b"C>" not in out_exit:
            print(f"[-] Clean exit with Ctrl+Q failed. Buffer: {repr(out_exit)}", flush=True)
            return False
        print("[+] Clean exit to CP/M prompt verified.", flush=True)

        elapsed = time.time() - t_start
        print(f"[+] All SE.COM sanity tests PASSED in {elapsed:.2f}s!", flush=True)
        return True

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
        except OSError:
            pass

if __name__ == "__main__":
    success = run_sanity_test()
    sys.exit(0 if success else 1)
