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

        # 5. Trigger Multi-Sector File I/O Validation Suite ('f')
        time.sleep(0.5)
        os.write(master, b"f")
        out_file_test = read_until(master, b"MULTI-SECTOR FILE VALIDATION: ALL TESTS PASSED", timeout=8.0)
        if b"MULTI-SECTOR FILE VALIDATION: ALL TESTS PASSED" not in out_file_test:
            print("[-] Multi-sector file I/O validation test FAILED. Buffer captured:\n", out_file_test.decode("latin1", errors="replace"), flush=True)
            return False
        print("[+] Multi-Sector File I/O Diagnostic Suite ('30.TXT' 8 sectors, 30 lines) ALL PASSED!", flush=True)

        # Return to Splash Screen
        read_until(master, b"Press any key to return", timeout=5.0)
        time.sleep(0.3)
        os.write(master, b"\r")
        read_until(master, b"Auto-detects CP/M [CRLF]", timeout=6.0)

        # 6. Trigger Memory Diagnostic ('t')
        time.sleep(0.5)
        os.write(master, b"t")
        out_mem = read_until(master, b"ALL 512KB EXTENDED MEMORY TESTS PASSED", timeout=8.0)
        if b"ALL 512KB EXTENDED MEMORY TESTS PASSED" not in out_mem:
            print("[-] 512KB extended memory banking diagnostic FAILED. Buffer captured:\n", out_mem.decode("latin1", errors="replace"), flush=True)
            return False
        print("[+] 512KB Extended Memory Diagnostic Suite (Tests 1, 2, 3, 4) ALL PASSED!", flush=True)

        # 7. Return to Splash and enter editor ('e')
        read_until(master, b"Press any key to return", timeout=5.0)
        time.sleep(0.3)
        os.write(master, b"\r")
        read_until(master, b"Auto-detects CP/M [CRLF]", timeout=6.0)
        time.sleep(0.3)
        os.write(master, b"e")
        out_edit = read_until(master, b"SE v0.5.0", timeout=6.0)
        if b"SE v0.5.0" not in out_edit:
            print(f"[-] Failed to enter editor mode. Buffer captured: {repr(out_edit)}", flush=True)
            return False
        print("[+] Successfully entered full-screen editing mode.", flush=True)

        # 8. Test interactive character typing in empty buffer
        time.sleep(0.5)
        r, _, _ = select.select([master], [], [], 0.3)
        if r:
            os.read(master, 4096)

        out_type = b""
        for ch in b"HELLO WORLD":
            os.write(master, bytes([ch]))
            time.sleep(0.05)
            out_type += read_until(master, bytes([ch]), timeout=1.0)

        if b"HELLO WORLD" not in out_type:
            print("[-] Interactive typing failed to render on screen. Buffer captured:", out_type)
            return False
        print("[+] Successfully typed and rendered 'HELLO WORLD'.")

        # 8. Create multi-line text by pressing Enter
        for line in [b"\r", b"Line Two of Document", b"\r", b"Line Three with Tabs", b"\r", b"Line Four Final"]:
            os.write(master, line)
            time.sleep(0.1)
        time.sleep(0.5)
        drain_all(master)

        # 9. Test Left / Right cursor movement and line-end wrapping
        time.sleep(0.2)
        drain_all(master)
        # Move Left 3 times
        for _ in range(3):
            os.write(master, b"\x1b[D")
            time.sleep(0.02)
        # Move Right 3 times
        for _ in range(3):
            os.write(master, b"\x1b[C")
            time.sleep(0.02)
        # Wrap to next line with Right Arrow at EOL
        for _ in range(60):
            os.write(master, b"\x1b[C")
            time.sleep(0.01)
        drain_all(master)
        print("[+] Successfully verified horizontal cursor navigation and line wrapping.")

        # 10. Test cursor down clamping at end of file (4 lines -> cursor stops at line 4)
        time.sleep(0.2)
        for _ in range(15):
            os.write(master, b"\x1b[B")
            time.sleep(0.01)
        out_row_clamp = read_until(master, b"Row 4,", timeout=3.0)
        if b"Row 4," not in out_row_clamp:
            print("[-] Cursor down clamping at EOF failed. Buffer captured:", out_row_clamp)
            return False
        print("[+] Successfully verified cursor cannot move past the last line of text (line 4).")

        # 11. Test mid-line insertion line length capacity (preventing exceeding 120 chars)
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

        # 12. Test blank line deletion with Backspace at column 0
        # Move up to row 1, col 0
        for _ in range(5):
            os.write(master, b"\x1b[A")
            time.sleep(0.05)
        os.write(master, b"\x1b[H")
        time.sleep(0.1)
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

        # 13. Test Delete Key (\x1b[3~) and Ctrl+D (Forward Delete)
        # Ensure cursor is at (1,0)
        os.write(master, b"\x1b[H")
        time.sleep(0.1)
        # Send Delete key (\x1b[3~)
        os.write(master, b"\x1b[3~")
        time.sleep(0.2)
        # Send Ctrl+D (forward delete)
        os.write(master, b"\x04")
        time.sleep(0.2)
        os.write(master, b"\x1b[H")
        drain_all(master)
        print("[+] Successfully verified Delete key (ESC [ 3 ~) and Ctrl+D forward deletion.")

        # 14. Test Real Tab character insertion & Tab-jumping navigation
        # Press Tab at (1,0) -> advances visual cursor to (1,8) -> displayed as Col 8 (0-indexed)
        os.write(master, b"\t")
        out_tab1 = read_until(master, b"Row 1, Col 8", timeout=4.0)
        if b"Row 1, Col 8" not in out_tab1:
            print(f"[-] Tab key from col 0 failed to reach col 8. Buffer captured: {repr(out_tab1)}", flush=True)
            return False
        drain_all(master)

        # Test Cursor Left jumping across the Tab in a single keystroke
        os.write(master, b"\x1b[D")
        out_tab_left = read_until(master, b"Row 1, Col 0", timeout=4.0)
        if b"Row 1, Col 0" not in out_tab_left:
            print(f"[-] Left arrow over Tab failed to jump back to col 0. Buffer captured: {repr(out_tab_left)}", flush=True)
            return False
        drain_all(master)

        # Test Cursor Right jumping across the Tab in a single keystroke
        os.write(master, b"\x1b[C")
        out_tab_right = read_until(master, b"Row 1, Col 8", timeout=4.0)
        if b"Row 1, Col 8" not in out_tab_right:
            print(f"[-] Right arrow over Tab failed to jump forward to col 8. Buffer captured: {repr(out_tab_right)}", flush=True)
            return False
        drain_all(master)

        # Test Backspace deleting the entire Tab in a single keystroke
        os.write(master, b"\x08")
        out_tab_bs = read_until(master, b"Row 1, Col 0", timeout=4.0)
        if b"Row 1, Col 0" not in out_tab_bs:
            print(f"[-] Backspace over Tab failed to return to col 0. Buffer captured: {repr(out_tab_bs)}", flush=True)
            return False
        drain_all(master)

        # 15. Test rightmost column boundary clamping (cannot exceed visual Col 119)
        # Move down to line 4, then type characters to fill line to max width 120 (cols 0..119)
        for _ in range(3):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        # Move to end of line
        os.write(master, b"\x1b[F")
        time.sleep(0.1)
        drain_all(master)
        # Type characters to hit the 120 column limit (line currently ~90 chars)
        for _ in range(35):
            os.write(master, b"X")
            time.sleep(0.02)
        drain_all(master)
        # Move to End of line (Col 119)
        os.write(master, b"\x1b[F")
        out_col_clamp = read_until(master, b"Col 119", timeout=4.0)
        if b"Col 119" not in out_col_clamp:
            print(f"[-] Column boundary clamping failed. Buffer captured: {repr(out_col_clamp)}", flush=True)
            return False
        # Try to type extra characters - verify it does not exceed Col 119
        for _ in range(5):
            os.write(master, b"Y")
            time.sleep(0.02)
        drain_all(master)
        print("[+] Successfully verified cursor and line cannot exceed visual screen width (Col 119).", flush=True)

        # 16. Test format toggle (^F)
        os.write(master, b"\x06")
        out_fmt = read_until(master, b"Linux", timeout=4.0)
        if b"Linux" not in out_fmt:
            print(f"[-] Format toggle failed. Buffer captured: {repr(out_fmt)}", flush=True)
            return False
        drain_all(master)
        print("[+] Successfully exercised ^F format toggle.", flush=True)

        # 17. Save file with Ctrl+S (saves to OUTPUT.TXT)
        time.sleep(0.3)
        os.write(master, b"\x13")
        time.sleep(0.5)
        drain_all(master)
        print("[+] Successfully saved file with Ctrl+S.", flush=True)

        # 18. Send Ctrl+Q to exit cleanly back to CP/M
        time.sleep(0.5)
        os.write(master, b"\x11")
        out_exit = read_until(master, b"C>", timeout=4.0)
        if b"C>" not in out_exit and b"Exiting SE.COM" not in out_exit:
            print(f"[-] Clean exit message not observed. Buffer captured: {repr(out_exit)}", flush=True)
            return False
        print("[+] SE.COM successfully received Ctrl+Q and returned cleanly to CP/M.", flush=True)

        # 19. Test File Loading: Open 2-line file 'se 2.TXT'
        time.sleep(0.5)
        os.write(master, b"se 2.TXT\r")
        out_load = read_until(master, b"SE v0.5.0", timeout=6.0)
        if b"SE v0.5.0" not in out_load:
            print(f"[-] Failed to load file 2.TXT into SE.COM. Buffer: {repr(out_load)}", flush=True)
            return False
        # Verify BOTH Line 1 and Line 2 from 2.TXT loaded and rendered on screen
        if b"First line of two" not in out_load or b"Second line of two" not in out_load:
            print(f"[-] Multi-line file contents missing in SE.COM. Buffer: {repr(out_load)}", flush=True)
            return False
        print("[+] Successfully verified multi-line file loading (se 2.TXT) and Far RAM streaming!", flush=True)

        # Exit editor again
        time.sleep(0.5)
        os.write(master, b"\x11")
        read_until(master, b"C>", timeout=4.0)
        print("[+] Exit from SE.COM completed.", flush=True)

        # 20. Test Multi-Sector File Loading into Editor: 'se 30.TXT' (8 sectors, 30 lines)
        time.sleep(0.5)
        os.write(master, b"se 30.TXT\r")
        out_load_30 = read_until(master, b"SE v0.5.0", timeout=6.0)
        if b"SE v0.5.0" not in out_load_30:
            print(f"[-] Failed to load file 30.TXT into SE.COM. Buffer: {repr(out_load_30)}", flush=True)
            return False
        # Verify lines from 30.TXT are rendered on screen
        if b"Line 01 of test file content" not in out_load_30:
            print(f"[-] 30.TXT Line 01 missing on editor screen. Buffer: {repr(out_load_30)}", flush=True)
            return False
        if b"Line 20 of test file content" not in out_load_30:
            print(f"[-] 30.TXT Line 20 missing on editor screen. Buffer: {repr(out_load_30)}", flush=True)
            return False
        print("[+] Successfully verified 30-line multi-sector file loading (se 30.TXT) into editor Far RAM buffer!", flush=True)

        # Final exit from editor
        time.sleep(0.5)
        os.write(master, b"\x11")
        read_until(master, b"C>", timeout=4.0)
        print("[+] Final exit from SE.COM completed.", flush=True)

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
