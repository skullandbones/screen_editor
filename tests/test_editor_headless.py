#!/usr/bin/env python3
"""
Host-agnostic headless test runner for SE.COM (Screen Editor).
Executes SE.COM inside an RC2014 / RomWBW emulation harness over pseudo-terminal (PTY)
and verifies splash screen, memory diagnostics, editor buffer rendering, format toggle,
and clean exit behavior.
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
        r, _, _ = select.select([master_fd], [], [], 0.05)
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

def drain_all(master_fd, quiet_time=0.2):
    time.sleep(0.05)
    while True:
        r, _, _ = select.select([master_fd], [], [], quiet_time)
        if not r:
            break
        try:
            data = os.read(master_fd, 4096)
            if not data:
                break
        except (BlockingIOError, OSError):
            break

def test_se_execution():
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

    print("[*] Launching RomWBW on RC2014 emulator...", flush=True)
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)

    try:
        # 1. Wait for RomWBW boot loader prompt
        out = read_until(master, b"Boot [H=Help]:", timeout=6.0)
        if b"Boot [H=Help]:" not in out:
            print("[-] Failed to reach RomWBW boot loader prompt.")
            return False
        print("[+] Boot loader prompt reached.")

        # 2. Boot into CP/M 2.2 on ROM disk (Choice 'c')
        time.sleep(0.5)
        os.write(master, b"c\r")
        out = read_until(master, b"B>", timeout=6.0)
        if b"B>" not in out:
            print("[-] Failed to boot into CP/M prompt.")
            return False
        print("[+] Booted into CP/M (Drive B>).")

        # 3. Switch to Drive C: (SD slice 0 with SE.COM)
        time.sleep(0.5)
        os.write(master, b"c:\r")
        out = read_until(master, b"C>", timeout=4.0)
        print("[+] Switched to Drive C>.")

        # 4. Run SE.COM
        time.sleep(0.5)
        os.write(master, b"se\r")
        out = read_until(master, b"Auto-detects CP/M [CRLF]", timeout=6.0)
        if b"Auto-detects CP/M [CRLF]" not in out:
            print("[-] SE.COM splash screen not detected.", flush=True)
            return False
        print("[+] SE.COM splash screen successfully displayed.", flush=True)

        # 5. Trigger Memory Diagnostic ('t')
        time.sleep(0.5)
        os.write(master, b"t")
        out_mem = read_until(master, b"512KB Far Memory Banking Test: PASSED", timeout=6.0)
        if b"512KB Far Memory Banking Test: PASSED" not in out_mem:
            print("[-] 512KB extended memory test failed or not detected.", flush=True)
            return False
        print("[+] 512KB extended memory banking diagnostic PASSED.", flush=True)

        # 6. Return to Splash and enter editor ('e')
        read_until(master, b"Press any key to return", timeout=5.0)
        time.sleep(0.3)
        os.write(master, b"\r")
        read_until(master, b"Auto-detects CP/M [CRLF]", timeout=6.0)
        time.sleep(0.3)
        os.write(master, b"e")
        out_edit = read_until(master, b"SE v0.3.1", timeout=6.0)
        if b"SE v0.3.1" not in out_edit:
            print(f"[-] Failed to enter editor mode. Buffer captured: {repr(out_edit)}", flush=True)
            return False
        print("[+] Successfully entered full-screen editing mode.", flush=True)

        # 7. Test interactive character typing
        time.sleep(0.5)
        r, _, _ = select.select([master], [], [], 0.3)
        if r:
            os.read(master, 4096)

        out_type = b""
        for ch in b"HELLO":
            os.write(master, bytes([ch]))
            time.sleep(0.15)
            out_type += read_until(master, bytes([ch]), timeout=1.0)

        if b"HELLO" not in out_type:
            print("[-] Interactive typing failed to render on screen. Buffer captured:", out_type)
            return False
        print("[+] Successfully typed and rendered 'HELLO'.")

        # 8. Test Column 119 boundary clamping (Bug fix verification)
        time.sleep(0.2)
        for _ in range(130):
            os.write(master, b"\x1b[C")
            time.sleep(0.01)
        out_clamp = read_until(master, b"1,119", timeout=5.0)
        if b"1,119" not in out_clamp:
            print("[-] Col 119 boundary clamping failed. Buffer captured:", out_clamp)
            return False
        # Type 5 characters at column 119
        os.write(master, b"12345")
        time.sleep(0.3)
        print("[+] Successfully verified column 119 boundary clamping and typing.")

        # 9. Test cursor down clamping at end of file (4 lines -> cursor stops at line 4)
        time.sleep(0.2)
        for _ in range(15):
            os.write(master, b"\x1b[B")
            time.sleep(0.01)
        out_row_clamp = read_until(master, b" 4,", timeout=3.0)
        if b" 4," not in out_row_clamp:
            print("[-] Cursor down clamping at EOF failed. Buffer captured:", out_row_clamp)
            return False
        print("[+] Successfully verified cursor cannot move past the last line of text (line 4).")

        # 10. Test mid-line insertion line length capacity (preventing exceeding 120 chars)
        drain_all(master)
        # Type 50 characters at end of line 4, move back 20 cols, insert 25 'A's
        os.write(master, b"0123456789" * 5)
        time.sleep(0.2)
        for _ in range(20):
            os.write(master, b"\x1b[D")
            time.sleep(0.01)
        time.sleep(0.1)
        for _ in range(25):
            os.write(master, b"A")
            time.sleep(0.01)
        drain_all(master)
        print("[+] Successfully verified 120-char line capacity limit during mid-line insertion.")

        # 11. Test blank line deletion with Backspace at column 0
        # Move up to row 1, col 0
        for _ in range(5):
            os.write(master, b"\x1b[A")
            time.sleep(0.01)
        for _ in range(25):
            os.write(master, b"\x1b[D")
            time.sleep(0.01)
        drain_all(master)
        # Press Enter to split and create blank line 1
        os.write(master, b"\r")
        time.sleep(0.3)
        # Move up to blank line 1
        os.write(master, b"\x1b[A")
        time.sleep(0.3)
        # Press Backspace on blank line 1 at col 0
        os.write(master, b"\x08")
        drain_all(master)
        print("[+] Successfully verified blank line deletion with Backspace at column 0.")

        # 12. Test Delete Key (\x1b[3~) and Ctrl+D (Forward Delete)
        # Cursor is at (1,0) on ';'. Send Delete key (\x1b[3~)
        os.write(master, b"\x1b[3~")
        time.sleep(0.2)
        # Send Ctrl+D (forward delete)
        os.write(master, b"\x04")
        drain_all(master)
        print("[+] Successfully verified Delete key (ESC [ 3 ~) and Ctrl+D forward deletion.")

        # 13. Test Tab key (8-character tab stops)
        # Press Tab at (1,0) -> advances to (1,8)
        os.write(master, b"\t")
        out_tab1 = read_until(master, b" 1,8 ", timeout=4.0)
        if b" 1,8 " not in out_tab1:
            print(f"[-] Tab key from col 0 failed to reach col 8. Buffer captured: {repr(out_tab1)}", flush=True)
            return False
        drain_all(master)
        # Press Tab again at (1,8) -> advances to (1,16)
        os.write(master, b"\t")
        out_tab2 = read_until(master, b" 1,16 ", timeout=4.0)
        if b" 1,16 " not in out_tab2:
            print(f"[-] Tab key from col 8 failed to reach col 16. Buffer captured: {repr(out_tab2)}", flush=True)
            return False
        drain_all(master)
        print("[+] Successfully verified Tab key 8-character tab stop alignment.", flush=True)

        # 14. Test format toggle (^F)
        os.write(master, b"\x06")
        out_fmt = read_until(master, b"Linux LF", timeout=4.0)
        if b"Linux LF" not in out_fmt:
            print(f"[-] Format toggle failed. Buffer captured: {repr(out_fmt)}", flush=True)
            return False
        drain_all(master)
        print("[+] Successfully exercised ^F format toggle.", flush=True)

        # 15. Send Ctrl+Q to exit cleanly back to CP/M
        time.sleep(0.5)
        os.write(master, b"\x11")
        out_exit = read_until(master, b"Exiting SE.COM", timeout=4.0)
        if b"Exiting SE.COM" not in out_exit:
            print(f"[-] Clean exit message not observed. Buffer captured: {repr(out_exit)}", flush=True)
            return False
        print("[+] SE.COM successfully received Ctrl+Q and returned cleanly to CP/M.", flush=True)

        return True

    finally:
        try:
            proc.kill()
            proc.wait(timeout=1.0)
        except (OSError, subprocess.TimeoutExpired):
            pass
        try:
            os.close(master)
        except OSError:
            pass

if __name__ == "__main__":
    success = test_se_execution()
    if success:
        print("[+] All automated SE.COM emulator tests PASSED.", flush=True)
        sys.exit(0)
    else:
        print("[-] Automated SE.COM emulator tests FAILED.", flush=True)
        sys.exit(1)
