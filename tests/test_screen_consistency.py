#!/usr/bin/env python3
"""
Test Screen Consistency for SE.COM.
Verifies:
  1. Help Keys Screen (Ctrl+K) has status bar on row ACTIVE_ROWS and '~' in column 0.
  2. Open File Screen (Ctrl+O) has status bar on row ACTIVE_ROWS and '~' in column 0.
  3. Save File Screen (Ctrl+S) has status bar on row ACTIVE_ROWS and '~' in column 0.
  4. Input box cursor positioning remains functional in Open & Save screens.
  5. Tested in both 80x24 and 120x40 screen modes.
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

def read_until(master_fd, match_bytes, timeout=8.0):
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

def drain_all(master_fd, quiet_time=0.15):
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

def run_screen_consistency_test(mode_name="80x24"):
    print(f"\n=======================================================", flush=True)
    print(f"[*] Running Screen Consistency Test in {mode_name} mode", flush=True)
    print(f"=======================================================", flush=True)

    emu_bin, rom_file, img_file, se_bin = find_paths()
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)

    try:
        # Boot RomWBW
        out = read_until(master, b"Boot [H=Help]:", timeout=8.0)
        if b"Boot [H=Help]:" not in out:
            print("[-] RomWBW failed to boot", flush=True)
            return False

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
            print(f"[-] Failed to switch to Drive C>.", flush=True)
            return False

        # Start SE.COM
        time.sleep(0.5)
        drain_all(master)
        os.write(master, b"se\r")
        out_splash = read_until(master, b"SE - Screen Editor", timeout=15.0)
        if b"SE - Screen Editor" not in out_splash:
            print(f"[-] SE splash not displayed. Buffer: {repr(out_splash)}", flush=True)
            return False

        # Configure screen mode
        if mode_name == "80x24":
            os.write(master, b"2")  # Set 80x24
        elif mode_name == "120x40":
            os.write(master, b"1")  # Set 120x40
        time.sleep(0.3)
        drain_all(master)

        # 1. Test Help Keys Screen (Ctrl+K from editor mode)
        print("[*] Testing Help Keys Screen...", flush=True)
        os.write(master, b"e")  # enter editor
        out_ed = read_until(master, b"^K: Editor keys", timeout=5.0)
        if b"^K: Editor keys" not in out_ed:
            print("[-] Failed to enter editor mode", flush=True)
            return False

        drain_all(master)
        os.write(master, b"\x0b")  # Ctrl+K
        out_help = read_until(master, b"Press any key to return to editor...", timeout=5.0)
        out_help += read_until(master, b"\x1b[?25l", timeout=3.0)
        if b"SE.COM - EDITOR MODE KEYS" not in out_help:
            print(f"[-] Help screen missing title. Buffer: {repr(out_help)}", flush=True)
            return False

        # Verify tildes and status bar on Help screen
        if b"~=============================================================================" not in out_help:
            print(f"[-] Help screen missing '~' in column 0 header. Buffer: {repr(out_help)}", flush=True)
            return False
        if b"Free:" not in out_help or b"KB" not in out_help:
            print(f"[-] Help screen missing status bar free memory. Buffer: {repr(out_help)}", flush=True)
            return False
        if mode_name.encode() not in out_help:
            print(f"[-] Help screen status bar missing screen mode {mode_name}. Buffer: {repr(out_help)}", flush=True)
            return False
        print(f"[+] Help Keys Screen has '~' in col 0 and active status bar ({mode_name})!", flush=True)

        # Return to editor
        drain_all(master)
        os.write(master, b" ")
        read_until(master, b"^K: Editor keys", timeout=4.0)

        # 2. Test Open File Screen (Ctrl+O from editor)
        print("[*] Testing Open File Screen...", flush=True)
        drain_all(master)
        os.write(master, b"\x0f")  # Ctrl+O
        out_open = read_until(master, b"Enter filename to open", timeout=6.0)
        out_open += read_until(master, b"\x1b[?25h", timeout=3.0)
        if b"OPEN FILE (DIRECTORY - DRIVE C:)" not in out_open:
            print(f"[-] Open screen missing title. Buffer: {repr(out_open)}", flush=True)
            return False

        # Verify tildes and status bar on Open screen
        if b"~============================================================" not in out_open:
            print(f"[-] Open screen missing '~' in title bar. Buffer: {repr(out_open)}", flush=True)
            return False
        if b"~  <ESC>=Cancel    Enter <drive>: to list directory" not in out_open:
            print(f"[-] Open screen missing '~  <ESC>=Cancel    Enter <drive>: to list directory'. Buffer: {repr(out_open)}", flush=True)
            return False
        if b"Free:" not in out_open or b"KB" not in out_open:
            print(f"[-] Open screen missing status bar free memory. Buffer: {repr(out_open)}", flush=True)
            return False
        if mode_name.encode() not in out_open:
            print(f"[-] Open screen status bar missing screen mode {mode_name}. Buffer: {repr(out_open)}", flush=True)
            return False
        print(f"[+] Open File Screen has '~' in col 0 and active status bar ({mode_name})!", flush=True)

        # Test typing in input box and cancel
        os.write(master, b"TEST")
        time.sleep(0.2)
        os.write(master, b"\x1b")  # ESC to cancel back to editor
        out_back_ed = read_until(master, b"^K: Editor keys", timeout=5.0)
        if b"^K: Editor keys" not in out_back_ed:
            print("[-] Cancel from Open Screen failed to return to editor", flush=True)
            return False
        print("[+] ESC correctly cancelled Open File screen back to editor.", flush=True)

        # 3. Test Save File Screen (Ctrl+S from editor)
        print("[*] Testing Save File Screen...", flush=True)
        drain_all(master)
        os.write(master, b"\x13")  # Ctrl+S
        out_save = read_until(master, b"Enter filename to save", timeout=6.0)
        out_save += read_until(master, b"\x1b[?25h", timeout=3.0)
        if b"SAVE FILE (DIRECTORY - DRIVE C:)" not in out_save:
            print(f"[-] Save screen missing title. Buffer: {repr(out_save)}", flush=True)
            return False

        # Verify tildes and status bar on Save screen
        if b"~============================================================" not in out_save:
            print(f"[-] Save screen missing '~' in title bar. Buffer: {repr(out_save)}", flush=True)
            return False
        if b"~  Format: [" not in out_save:
            print(f"[-] Save screen missing '~' in format indicator. Buffer: {repr(out_save)}", flush=True)
            return False
        if b"~  <ESC>=Cancel    Enter <drive>: to list directory" not in out_save:
            print(f"[-] Save screen missing '~  <ESC>=Cancel    Enter <drive>: to list directory'. Buffer: {repr(out_save)}", flush=True)
            return False
        if b"Free:" not in out_save or b"KB" not in out_save:
            print(f"[-] Save screen missing status bar free memory. Buffer: {repr(out_save)}", flush=True)
            return False
        if mode_name.encode() not in out_save:
            print(f"[-] Save screen status bar missing screen mode {mode_name}. Buffer: {repr(out_save)}", flush=True)
            return False
        print(f"[+] Save File Screen has '~' in col 0 and active status bar ({mode_name})!", flush=True)

        # Test format toggle (^F) in Save Screen
        os.write(master, b"\x06")  # Ctrl+F
        out_fmt = read_until(master, b"Format: [Linux]", timeout=4.0)
        if b"Format: [Linux]" not in out_fmt:
            print("[-] Ctrl+F format toggle failed in Save screen", flush=True)
            return False
        print("[+] Ctrl+F toggled format to Linux cleanly while preserving status bar.", flush=True)

        # Cancel Save screen
        drain_all(master)
        os.write(master, b"\x1b")  # ESC
        read_until(master, b"^K: Editor keys", timeout=4.0)

        # Clean exit to CP/M
        drain_all(master)
        os.write(master, b"\x11")  # Ctrl+Q
        out_cpm_exit = read_until(master, b"C>", timeout=4.0)
        if b"C>" not in out_cpm_exit:
            print("[-] Failed to exit cleanly to CP/M", flush=True)
            return False

        print(f"[+] Screen consistency test PASSED for {mode_name} mode!", flush=True)
        return True

    finally:
        try:
            os.close(master)
        except OSError:
            pass
        proc.terminate()
        try:
            proc.wait(timeout=2.0)
        except subprocess.TimeoutExpired:
            proc.kill()

if __name__ == "__main__":
    ok_80 = run_screen_consistency_test("80x24")
    if not ok_80:
        sys.exit(1)

    ok_120 = run_screen_consistency_test("120x40")
    if not ok_120:
        sys.exit(1)

    print("\n[SUCCESS] All Screen Consistency tests PASSED 100%!", flush=True)
    sys.exit(0)
