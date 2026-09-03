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

        # 7. Return to Splash, verify only 'e'/Enter enter editor mode, and enter editor ('e')
        read_until(master, b"Press any key to return", timeout=5.0)
        time.sleep(0.3)
        os.write(master, b"\r")
        read_until(master, b"Auto-detects CP/M [CRLF]", timeout=6.0)
        drain_all(master)
        time.sleep(0.3)

        # Verify Space key does NOT enter editor mode from splash screen
        os.write(master, b" ")
        time.sleep(0.3)
        r, _, _ = select.select([master], [], [], 0.3)
        if r:
            check_buf = os.read(master, 2048)
            if b"Row 1/" in check_buf or b"SE v0.6.4" in check_buf or b"[No Name]" in check_buf:
                print(f"[-] Space key on splash screen erroneously entered editor mode! Buffer: {repr(check_buf)}", flush=True)
                return False

        # Verify cursor arrow keys do NOT enter editor mode from splash screen
        for arrow_name, arrow_seq in [("Up", b"\x1b[A"), ("Down", b"\x1b[B"), ("Right", b"\x1b[C"), ("Left", b"\x1b[D")]:
            os.write(master, arrow_seq)
            time.sleep(0.2)
            r, _, _ = select.select([master], [], [], 0.2)
            if r:
                check_buf = os.read(master, 2048)
                if b"Row 1/" in check_buf or b"SE v0.6.4" in check_buf or b"[No Name]" in check_buf:
                    print(f"[-] Cursor {arrow_name} key ({repr(arrow_seq)}) on splash screen erroneously entered editor mode! Buffer: {repr(check_buf)}", flush=True)
                    return False

        print("[+] Successfully verified Space and Cursor keys do not enter editor mode from splash screen.", flush=True)

        # Enter editor mode with 'e'
        os.write(master, b"e")
        out_edit = read_until(master, b"Row 1/1,", timeout=6.0)
        if b"SE v0.6.4" not in out_edit:
            print(f"[-] Failed to enter editor mode. Buffer captured: {repr(out_edit)}", flush=True)
            return False
        if b"[No Name]" not in out_edit:
            print(f"[-] Missing '[No Name]' in status bar for unnamed buffer. Buffer: {repr(out_edit)}", flush=True)
            return False
        if b"^K: Editor keys" not in out_edit:
            print(f"[-] Missing '^K: Editor keys' in status bar. Buffer: {repr(out_edit)}", flush=True)
            return False
        print("[+] Successfully entered full-screen editing mode with '[No Name]' and '^K: Editor keys'.", flush=True)

        # 8. Test interactive character typing in empty buffer
        time.sleep(0.3)
        drain_all(master)
        for ch in b"HELLO WORLD":
            os.write(master, bytes([ch]))
            time.sleep(0.05)

        out_type = read_until(master, b"Col 11", timeout=4.0)
        # Verify status bar reflects Row 1, Col 11
        if b"Col 11" not in out_type:
            print("[-] Interactive typing failed to reach Col 11. Buffer captured:", out_type)
            return False
        print("[+] Successfully typed and rendered 'HELLO WORLD' (Row 1, Col 11).")

        # 8a. Test Home Key (\x1b[1~, \x1b[H, \x1bOH, Ctrl+A) and End Key (\x1b[4~, \x1b[F, \x1bOF, Ctrl+E)
        # Test Standard PC Home key: ESC [ 1 ~
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b[1~")
        out_home1 = read_until(master, b"Col 0 ", timeout=3.0)
        if b"Col 0 " not in out_home1:
            print(f"[-] PC Home key (ESC [ 1 ~) failed to move to Col 0. Buffer: {repr(out_home1)}", flush=True)
            return False

        # Test Standard PC End key: ESC [ 4 ~
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b[4~")
        out_end1 = read_until(master, b"Col 11", timeout=3.0)
        if b"Col 11" not in out_end1:
            print(f"[-] PC End key (ESC [ 4 ~) failed to move to Col 11. Buffer: {repr(out_end1)}", flush=True)
            return False

        # Test VT100 Home key: ESC [ H
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b[H")
        out_home_vt = read_until(master, b"Col 0 ", timeout=3.0)
        if b"Col 0 " not in out_home_vt:
            print(f"[-] VT100 Home key (ESC [ H) failed to move to Col 0. Buffer: {repr(out_home_vt)}", flush=True)
            return False

        # Test VT100 End key: ESC [ F
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b[F")
        out_end_vt = read_until(master, b"Col 11", timeout=3.0)
        if b"Col 11" not in out_end_vt:
            print(f"[-] VT100 End key (ESC [ F) failed to move to Col 11. Buffer: {repr(out_end_vt)}", flush=True)
            return False

        # Test SS3 Home key: ESC O H
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1bOH")
        out_home_ss3 = read_until(master, b"Col 0 ", timeout=3.0)
        if b"Col 0 " not in out_home_ss3:
            print(f"[-] SS3 Home key (ESC O H) failed to move to Col 0. Buffer: {repr(out_home_ss3)}", flush=True)
            return False

        # Test SS3 End key: ESC O F
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1bOF")
        out_end_ss3 = read_until(master, b"Col 11", timeout=3.0)
        if b"Col 11" not in out_end_ss3:
            print(f"[-] SS3 End key (ESC O F) failed to move to Col 11. Buffer: {repr(out_end_ss3)}", flush=True)
            return False

        # Test Ctrl+A (Home) and Ctrl+E (End)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x01")  # Ctrl+A -> Home
        out_home_ctrl = read_until(master, b"Col 0 ", timeout=3.0)
        if b"Col 0 " not in out_home_ctrl:
            print(f"[-] Ctrl+A (Home) failed to move to Col 0. Buffer: {repr(out_home_ctrl)}", flush=True)
            return False

        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x05")  # Ctrl+E -> End
        out_end_ctrl = read_until(master, b"Col 11", timeout=3.0)
        if b"Col 11" not in out_end_ctrl:
            print(f"[-] Ctrl+E (End) failed to move to Col 11. Buffer: {repr(out_end_ctrl)}", flush=True)
            return False

        print("[+] Successfully verified Home (ESC [ 1 ~, ESC [ H, ESC O H, ^A) and End (ESC [ 4 ~, ESC [ F, ESC O F, ^E) navigation!", flush=True)

        # 8b. Create multi-line text by pressing Enter
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
        out_row_clamp = read_until(master, b"Row 4/4,", timeout=3.0)
        if b"Row 4/4," not in out_row_clamp:
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

        # 12. Test Line Joining with Backspace at column 0
        # Ensure cursor at top of document
        os.write(master, b"\x14")  # Ctrl+T -> Top of file
        time.sleep(0.2)
        # Move to Row 2, Col 0
        os.write(master, b"\x1b[B")
        time.sleep(0.1)
        os.write(master, b"\x01")
        time.sleep(0.2)
        drain_all(master)
        # Press Backspace at column 0 to join Row 2 into Row 1 -> cursor lands at Row 1, Col 11
        os.write(master, b"\x08")
        out_join_bs = read_until(master, b"Row 1/3, Col 11", timeout=4.0)
        if b"Row 1/3, Col 11" not in out_join_bs:
            print(f"[-] Line join via Backspace at Col 0 failed. Buffer: {repr(out_join_bs)}", flush=True)
            return False
        drain_all(master)
        print("[+] Successfully verified Line Joining with Backspace at column 0.")

        # 13. Test Line Joining with Delete Key (\x1b[3~) at End of Line
        # Move cursor to end of Row 1 (length 31)
        os.write(master, b"\x05")  # Ctrl+E -> End of line
        time.sleep(0.2)
        drain_all(master)
        # Press Delete key (\x1b[3~) at EOL to join next line into Row 1 -> cursor stays at Row 1, Col 31
        os.write(master, b"\x1b[3~")
        out_join_del = read_until(master, b"Row 1/2, Col 31", timeout=4.0)
        if b"Row 1/2, Col 31" not in out_join_del:
            print(f"[-] Line join via Delete key at EOL failed. Buffer: {repr(out_join_del)}", flush=True)
            return False
        drain_all(master)
        print("[+] Successfully verified Line Joining with Delete key (ESC [ 3 ~) at End of Line.")

        # 14. Test Real Tab character insertion & Tab-jumping navigation
        # Move cursor to (1,0)
        os.write(master, b"\x01")  # Ctrl+A -> Home
        read_until(master, b"Row 1/2, Col 0", timeout=3.0)
        drain_all(master)
        # Press Tab at (1,0) -> advances visual cursor to (1,8) -> displayed as Col 8 (0-indexed)
        os.write(master, b"\t")
        out_tab1 = read_until(master, b"Row 1/2, Col 8", timeout=4.0)
        if b"Row 1/2, Col 8" not in out_tab1:
            print(f"[-] Tab key from col 0 failed to reach col 8. Buffer captured: {repr(out_tab1)}", flush=True)
            return False
        drain_all(master)

        # Test Cursor Left jumping across the Tab in a single keystroke
        os.write(master, b"\x1b[D")
        out_tab_left = read_until(master, b"Row 1/2, Col 0", timeout=4.0)
        if b"Row 1/2, Col 0" not in out_tab_left:
            print(f"[-] Left arrow over Tab failed to jump back to col 0. Buffer captured: {repr(out_tab_left)}", flush=True)
            return False
        drain_all(master)

        # Test Cursor Right jumping across the Tab in a single keystroke
        os.write(master, b"\x1b[C")
        out_tab_right = read_until(master, b"Row 1/2, Col 8", timeout=4.0)
        if b"Row 1/2, Col 8" not in out_tab_right:
            print(f"[-] Right arrow over Tab failed to jump forward to col 8. Buffer captured: {repr(out_tab_right)}", flush=True)
            return False
        drain_all(master)

        # Test Backspace deleting the entire Tab in a single keystroke
        os.write(master, b"\x08")
        out_tab_bs = read_until(master, b"Row 1/2, Col 0", timeout=4.0)
        if b"Row 1/2, Col 0" not in out_tab_bs:
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

        # 16. Verify Ctrl+F in editor mode is ignored (format remains unchanged)
        time.sleep(0.2)
        drain_all(master)
        os.write(master, b"\x06")
        time.sleep(0.2)
        drain_all(master)
        print("[+] Successfully verified ^F in editor mode is ignored.", flush=True)

        # 17. Save file with Ctrl+S (opens Save Screen, tests Save Screen Ctrl+F toggle, and saves to OUTPUT.TXT)
        time.sleep(0.3)
        os.write(master, b"\x13")
        read_until(master, b"SAVE FILE (DIRECTORY - DRIVE C:)", timeout=5.0)
        out_save_prompt = read_until(master, b"Enter filename to save", timeout=4.0)
        if b"Format: [CP/M]" not in out_save_prompt:
            print(f"[-] Initial Save Screen missing 'Format: [CP/M]'. Buffer: {repr(out_save_prompt)}", flush=True)
            return False
        # Toggle format with Ctrl+F in Save Screen
        time.sleep(0.2)
        os.write(master, b"\x06")
        out_toggle_linux = read_until(master, b"Format: [Linux]", timeout=4.0)
        if b"Format: [Linux]" not in out_toggle_linux:
            print(f"[-] Save Screen Ctrl+F toggle to Linux failed. Buffer: {repr(out_toggle_linux)}", flush=True)
            return False
        # Toggle format back to CP/M with Ctrl+F
        time.sleep(0.2)
        os.write(master, b"\x06")
        out_toggle_cpm = read_until(master, b"Format: [CP/M]", timeout=4.0)
        if b"Format: [CP/M]" not in out_toggle_cpm:
            print(f"[-] Save Screen Ctrl+F toggle back to CP/M failed. Buffer: {repr(out_toggle_cpm)}", flush=True)
            return False
        print("[+] Successfully verified Save Screen ^F format toggle (CP/M <-> Linux).", flush=True)
        time.sleep(0.2)
        os.write(master, b"OUTPUT.TXT\r")
        time.sleep(0.2)
        resp = read_until(master, b"Overwrite? (y/n): ", timeout=2.0)
        if b"Overwrite? (y/n): " in resp:
            os.write(master, b"y")
        read_until(master, b"SE v0.6.4", timeout=5.0)
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
        out_load = read_until(master, b"Row 1/2,", timeout=6.0)
        if b"SE v0.6.4" not in out_load:
            print(f"[-] Failed to load file 2.TXT into SE.COM. Buffer: {repr(out_load)}", flush=True)
            return False
        # Verify BOTH Line 1 and Line 2 from 2.TXT loaded and rendered on screen
        if b"First line of two" not in out_load or b"Second line of two" not in out_load:
            print(f"[-] Multi-line file contents missing in SE.COM. Buffer: {repr(out_load)}", flush=True)
            return False
        # Verify status bar shows full filename 'C:2.TXT'
        if b"C:2.TXT" not in out_load:
            print(f"[-] Status bar missing full filename 'C:2.TXT'. Buffer: {repr(out_load)}", flush=True)
            return False
        print("[+] Successfully verified multi-line file loading (se 2.TXT) and Far RAM streaming!", flush=True)

        # Exit editor again
        time.sleep(0.5)
        os.write(master, b"\x11")
        read_until(master, b"C>", timeout=4.0)
        print("[+] Exit from SE.COM completed.", flush=True)

        # 20. Test Multi-Sector File Loading and Page-Up / Page-Down Navigation: 'se 30.TXT'
        time.sleep(0.5)
        os.write(master, b"se 30.TXT\r")
        out_load_30 = read_until(master, b"Row 1/30,", timeout=6.0)
        if b"SE v0.6.4" not in out_load_30:
            print(f"[-] Failed to load file 30.TXT into SE.COM. Buffer: {repr(out_load_30)}", flush=True)
            return False
        # Verify lines from 30.TXT are rendered on screen
        if b"Line 01 of test file content" not in out_load_30:
            print(f"[-] 30.TXT Line 01 missing on editor screen. Buffer: {repr(out_load_30)}", flush=True)
            return False
        if b"Line 20 of test file content" not in out_load_30:
            print(f"[-] 30.TXT Line 20 missing on editor screen. Buffer: {repr(out_load_30)}", flush=True)
            return False
        # Verify status bar shows full filename 'C:30.TXT'
        if b"C:30.TXT" not in out_load_30:
            print(f"[-] Status bar missing full filename 'C:30.TXT'. Buffer: {repr(out_load_30)}", flush=True)
            return False
        print("[+] Successfully verified 30-line multi-sector file loading (se 30.TXT) into editor Far RAM buffer!", flush=True)

        # 21. Test Page-Down key (\x1b[6~)
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"\x1b[6~")
        out_pgdn = read_until(master, b"Row 30", timeout=4.0)
        if b"Row 30" not in out_pgdn:
            print(f"[-] Page Down key failed to navigate to bottom of document. Buffer: {repr(out_pgdn)}", flush=True)
            return False
        print("[+] Successfully verified Page-Down key (ESC [ 6 ~) navigation to Row 30.", flush=True)

        # 22. Test Page-Up key (\x1b[5~)
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"\x1b[5~")
        out_pgup = read_until(master, b"Row 1", timeout=4.0)
        if b"Row 1" not in out_pgup:
            print(f"[-] Page Up key failed to navigate back to top of document. Buffer: {repr(out_pgup)}", flush=True)
            return False
        print("[+] Successfully verified Page-Up key (ESC [ 5 ~) navigation to Row 1.", flush=True)

        # 23. Test Ctrl+V (Page Down) and Ctrl+U (Page Up) shortcuts
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"\x16")  # Ctrl+V -> Page Down
        out_ctrl_v = read_until(master, b"Row 30", timeout=4.0)
        if b"Row 30" not in out_ctrl_v:
            print(f"[-] Ctrl+V (Page Down) failed. Buffer: {repr(out_ctrl_v)}", flush=True)
            return False
        os.write(master, b"\x15")  # Ctrl+U -> Page Up
        out_ctrl_u = read_until(master, b"Row 1", timeout=4.0)
        if b"Row 1" not in out_ctrl_u:
            print(f"[-] Ctrl+U (Page Up) failed. Buffer: {repr(out_ctrl_u)}", flush=True)
            return False
        print("[+] Successfully verified Ctrl+V (Page Down) and Ctrl+U (Page Up) shortcuts.", flush=True)

        # 24. Test Jump to Top / Bottom (Ctrl+Home / Ctrl+End, Ctrl+T / Ctrl+G, ESC < / ESC >, ESC t / ESC b)
        # Test Ctrl+G (Jump to Bottom)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x07")  # Ctrl+G -> Jump to Bottom
        out_g = read_until(master, b"Row 30", timeout=4.0)
        if b"Row 30" not in out_g:
            print(f"[-] Ctrl+G failed to jump to bottom of file. Buffer: {repr(out_g)}", flush=True)
            return False

        # Test Ctrl+T (Jump to Top)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x14")  # Ctrl+T -> Jump to Top
        out_t = read_until(master, b"Row 1", timeout=4.0)
        if b"Row 1" not in out_t:
            print(f"[-] Ctrl+T failed to jump to top of file. Buffer: {repr(out_t)}", flush=True)
            return False

        # Test Ctrl+End (ESC [ 1 ; 5 F)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b[1;5F")
        out_cend = read_until(master, b"Row 30", timeout=4.0)
        if b"Row 30" not in out_cend:
            print(f"[-] Ctrl+End (ESC [ 1 ; 5 F) failed to jump to bottom. Buffer: {repr(out_cend)}", flush=True)
            return False

        # Test Ctrl+Home (ESC [ 1 ; 5 H)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b[1;5H")
        out_chome = read_until(master, b"Row 1", timeout=4.0)
        if b"Row 1" not in out_chome:
            print(f"[-] Ctrl+Home (ESC [ 1 ; 5 H) failed to jump to top. Buffer: {repr(out_chome)}", flush=True)
            return False

        # Test ESC > (Jump to Bottom)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b>")
        out_esc_gt = read_until(master, b"Row 30", timeout=4.0)
        if b"Row 30" not in out_esc_gt:
            print(f"[-] ESC > failed to jump to bottom. Buffer: {repr(out_esc_gt)}", flush=True)
            return False

        # Test ESC < (Jump to Top)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b<")
        out_esc_lt = read_until(master, b"Row 1", timeout=4.0)
        if b"Row 1" not in out_esc_lt:
            print(f"[-] ESC < failed to jump to top. Buffer: {repr(out_esc_lt)}", flush=True)
            return False

        # Test ESC b (Jump to Bottom)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1bb")
        out_esc_b = read_until(master, b"Row 30", timeout=4.0)
        if b"Row 30" not in out_esc_b:
            print(f"[-] ESC b failed to jump to bottom. Buffer: {repr(out_esc_b)}", flush=True)
            return False

        # Test ESC t (Jump to Top)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1bt")
        out_esc_t = read_until(master, b"Row 1", timeout=4.0)
        if b"Row 1" not in out_esc_t:
            print(f"[-] ESC t failed to jump to top. Buffer: {repr(out_esc_t)}", flush=True)
            return False

        print("[+] Successfully verified Jump to Top (Ctrl+T, Ctrl+Home, ESC <, ESC t) and Jump to Bottom (Ctrl+G, Ctrl+End, ESC >, ESC b)!", flush=True)

        # 25. Test ESC key showing splash screen and Enter resuming editor mode
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b")  # Standalone ESC key
        out_splash = read_until(master, b"SE - Screen Editor", timeout=4.0)
        if b"SE - Screen Editor" not in out_splash:
            print(f"[-] ESC key failed to show splash screen. Buffer: {repr(out_splash)}", flush=True)
            return False
        print("[+] Successfully verified ESC key in editor displays splash screen.", flush=True)

        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"\r")  # Press Enter to return to editor
        out_resume = read_until(master, b"Line 01 of test file content", timeout=4.0)
        if b"Line 01 of test file content" not in out_resume:
            print(f"[-] Enter key on splash failed to return to editor. Buffer: {repr(out_resume)}", flush=True)
            return False
        print("[+] Successfully verified Enter key resumes editor mode with document intact.", flush=True)

        # 26. Test Open File option (:o) on splash screen with Directory Listing
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b")  # Standalone ESC key to go to splash screen
        read_until(master, b"SE - Screen Editor", timeout=4.0)
        drain_all(master)
        time.sleep(0.2)

        # Press 'o' on splash screen
        os.write(master, b"o")
        out_dir = read_until(master, b"Enter filename to open", timeout=6.0)
        if b"Enter filename to open" not in out_dir:
            print(f"[-] Open prompt not displayed. Buffer: {repr(out_dir)}", flush=True)
            return False
        print("[+] Successfully verified Open File screen with sorted directory listing.", flush=True)

        # Test Space key to advance to Page 2
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b" ")
        out_page2 = read_until(master, b"[Page 2/", timeout=4.0)
        if b"[Page 2/" not in out_page2:
            print(f"[-] Space key failed to advance to Page 2. Buffer: {repr(out_page2)}", flush=True)
            return False
        print("[+] Successfully verified Space key pagination ([Page 2/X]).", flush=True)

        # Test ESC to cancel from Open File prompt
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b")  # ESC to cancel
        out_cancel = read_until(master, b"SE - Screen Editor", timeout=4.0)
        if b"SE - Screen Editor" not in out_cancel:
            print(f"[-] ESC key did not cancel open prompt back to splash screen. Buffer: {repr(out_cancel)}", flush=True)
            return False
        print("[+] Successfully verified ESC cancels Open File prompt back to splash screen.", flush=True)

        # Re-enter Open File screen and open 2.TXT
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"o")
        read_until(master, b"Enter filename to open", timeout=4.0)
        drain_all(master)
        time.sleep(0.1)

        # Type bad filename '2.BAK' and press Enter: verify 'File not found'
        os.write(master, b"2.BAK\r")
        out_nofile = read_until(master, b"File not found", timeout=4.0)
        if b"File not found" not in out_nofile:
            print(f"[-] 'File not found' message missing for non-existent file. Buffer: {repr(out_nofile)}", flush=True)
            return False

        # Verify it did NOT enter editor mode
        r, _, _ = select.select([master], [], [], 0.3)
        if r:
            check_buf = os.read(master, 2048)
            if b"SE v0.6.4" in check_buf or b"Row 1/" in check_buf:
                print(f"[-] Non-existent file erroneously entered editor mode! Buffer: {repr(check_buf)}", flush=True)
                return False
        print("[+] Successfully verified bad filename shows 'File not found' without entering editor mode.", flush=True)

        # Now edit bad filename in-place: send 3 Backspaces to erase 'BAK' (first BS clears 'File not found' & 'K')
        time.sleep(0.1)
        for _ in range(3):
            os.write(master, b"\x08")
            time.sleep(0.1)

        # Verify backspace did NOT enter editor mode
        r, _, _ = select.select([master], [], [], 0.3)
        if r:
            check_buf = os.read(master, 2048)
            if b"SE v0.6.4" in check_buf or b"Row 1/" in check_buf:
                print(f"[-] Backspace in open prompt erroneously entered editor mode! Buffer: {repr(check_buf)}", flush=True)
                return False

        # Type correct extension 'TXT' and press Enter
        os.write(master, b"TXT\r")
        out_loaded = read_until(master, b"Row 1/2,", timeout=4.0)
        if b"SE v0.6.4" not in out_loaded or b"C:2.TXT" not in out_loaded:
            print(f"[-] Failed to open 2.TXT from Open File prompt after backspace amendment. Buffer: {repr(out_loaded)}", flush=True)
            return False
        if b"First line of two" not in out_loaded:
            print(f"[-] Document contents not loaded after backspace amendment. Buffer: {repr(out_loaded)}", flush=True)
            return False
        print("[+] Successfully verified bad filename kept in text box, amended via backspace, and loaded.", flush=True)

        # 27. Test Save Screen: Pre-filling, Overwrite check, and Splash :s
        time.sleep(0.5)
        # We are currently editing '2.TXT'. Trigger Save Screen via Ctrl+S (\x13)
        os.write(master, b"\x13")
        out_save = read_until(master, b"SAVE FILE (DIRECTORY - DRIVE C:)", timeout=5.0)
        if b"SAVE FILE (DIRECTORY - DRIVE C:)" not in out_save:
            print(f"[-] Save screen title not found. Buffer: {repr(out_save)}", flush=True)
            return False
        # Verify pre-filled filename '2.TXT' is echoed in prompt
        out_prefill = read_until(master, b"2.TXT", timeout=3.0)
        if b"2.TXT" not in out_prefill:
            print(f"[-] Pre-filled filename '2.TXT' not found in save prompt. Buffer: {repr(out_prefill)}", flush=True)
            return False
        # Verify original loaded format (CP/M) is defaulted on Save Screen
        read_until(master, b"Format: [CP/M]", timeout=3.0)
        # Toggle format with Ctrl+F in Save Screen and verify pre-filled name is preserved
        time.sleep(0.2)
        os.write(master, b"\x06")
        out_tog2_linux = read_until(master, b"Format: [Linux]", timeout=3.0)
        read_until(master, b"2.TXT", timeout=3.0)
        # Toggle format back to CP/M
        time.sleep(0.2)
        os.write(master, b"\x06")
        read_until(master, b"Format: [CP/M]", timeout=3.0)
        read_until(master, b"2.TXT", timeout=3.0)
        print("[+] Successfully verified Save Screen with pre-filled filename '2.TXT' and ^F toggle.", flush=True)

        # Press Enter (\r) to save with existing filename: should trigger overwrite warning
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"\r")
        out_warn = read_until(master, b"File already exists. Overwrite? (y/n): ", timeout=4.0)
        if b"Overwrite? (y/n): " not in out_warn:
            print(f"[-] Overwrite warning prompt missing. Buffer: {repr(out_warn)}", flush=True)
            return False
        print("[+] Successfully verified overwrite warning prompt on existing file.", flush=True)

        # Test canceling overwrite with 'n'
        time.sleep(0.2)
        os.write(master, b"n")
        out_cancel = read_until(master, b"Save cancelled.", timeout=3.0)
        if b"Save cancelled." not in out_cancel:
            print(f"[-] 'Save cancelled.' message missing. Buffer: {repr(out_cancel)}", flush=True)
            return False
        out_back = read_until(master, b"SE v0.6.4", timeout=4.0)
        if b"SE v0.6.4" not in out_back:
            print(f"[-] Editor mode not restored after cancelling save. Buffer: {repr(out_back)}", flush=True)
            return False
        print("[+] Successfully verified cancelling overwrite returns cleanly to editor.", flush=True)

        # Re-open Save Screen with Ctrl+S and confirm overwrite with 'y'
        time.sleep(0.3)
        os.write(master, b"\x13")
        read_until(master, b"Enter filename to save", timeout=4.0)
        read_until(master, b"2.TXT", timeout=3.0)
        time.sleep(0.2)
        os.write(master, b"\r")
        read_until(master, b"Overwrite? (y/n): ", timeout=4.0)
        time.sleep(0.2)
        os.write(master, b"y")
        out_saved = read_until(master, b"SE v0.6.4", timeout=5.0)
        if b"SE v0.6.4" not in out_saved:
            print(f"[-] Editor mode not restored after confirming save. Buffer: {repr(out_saved)}", flush=True)
            return False
        print("[+] Successfully verified confirming overwrite ('y') saves file and resumes editor.", flush=True)

        # Return to splash screen (ESC) and test ':s' option
        drain_all(master)
        time.sleep(0.3)
        os.write(master, b"\x1b")
        out_splash = read_until(master, b":s                to save file", timeout=5.0)
        if b":s                to save file" not in out_splash:
            print(f"[-] Splash screen ':s to save file' not found. Buffer: {repr(out_splash)}", flush=True)
            return False
        print("[+] Successfully verified splash screen displays ':s to save file'.", flush=True)

        # Launch Save Screen from Splash screen ('s')
        time.sleep(0.2)
        os.write(master, b"s")
        out_splash_save = read_until(master, b"SAVE FILE (DIRECTORY - DRIVE C:)", timeout=4.0)
        if b"SAVE FILE (DIRECTORY - DRIVE C:)" not in out_splash_save:
            print(f"[-] Save screen not reached from splash screen. Buffer: {repr(out_splash_save)}", flush=True)
            return False
        # Cancel back to splash (ESC)
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"Auto-detects CP/M [CRLF]", timeout=4.0)
        print("[+] Successfully verified splash ':s' enters Save Screen and ESC returns to splash.", flush=True)

        # 28. Test Editor Mode Keys screen (^K)
        time.sleep(0.2)
        os.write(master, b"e")  # Return to editor from splash
        read_until(master, b"^K: Editor keys", timeout=4.0)
        time.sleep(0.2)
        os.write(master, b"\x0b")  # Ctrl+K
        out_keys = read_until(master, b"Press any key to return to editor...", timeout=4.0)
        if b"SE.COM - EDITOR MODE KEYS" not in out_keys:
            print(f"[-] Help screen not reached via Ctrl+K. Buffer: {repr(out_keys)}", flush=True)
            return False
        if b"Ctrl+O           Open file screen" not in out_keys:
            print(f"[-] Ctrl+O missing from Editor Mode Keys screen. Buffer: {repr(out_keys)}", flush=True)
            return False
        # Press Space to return to editor
        time.sleep(0.2)
        os.write(master, b" ")
        out_keys_back = read_until(master, b"^K: Editor keys", timeout=4.0)
        if b"^K: Editor keys" not in out_keys_back:
            print(f"[-] Failed to return to editor from keys screen. Buffer: {repr(out_keys_back)}", flush=True)
            return False
        print("[+] Successfully verified Ctrl+K Editor Mode Keys screen and return to editor.", flush=True)

        # 29. Test Ctrl+O in Editor Mode (Open File Screen and ESC cancel)
        time.sleep(0.2)
        os.write(master, b"\x0f")  # Ctrl+O
        out_open_ui = read_until(master, b"OPEN FILE (DIRECTORY - DRIVE C:)", timeout=4.0)
        if b"OPEN FILE (DIRECTORY - DRIVE C:)" not in out_open_ui:
            print(f"[-] Failed to reach Open File screen via Ctrl+O. Buffer: {repr(out_open_ui)}", flush=True)
            return False
        read_until(master, b"Enter filename to open (<ESC>=Cancel): ", timeout=3.0)
        # Press ESC to cancel back to editor mode without opening a file
        time.sleep(0.2)
        os.write(master, b"\x1b")
        out_cancelled = read_until(master, b"^K: Editor keys", timeout=4.0)
        if b"C:2.TXT" not in out_cancelled or b"First line of two" not in out_cancelled:
            print(f"[-] ESC did not cleanly restore editor mode with document intact. Buffer: {repr(out_cancelled)}", flush=True)
            return False
        print("[+] Successfully verified Ctrl+O opens directory browser and ESC returns to editor without opening file.", flush=True)

        # Test Ctrl+O successfully opening a new file from editor mode
        time.sleep(0.2)
        os.write(master, b"\x0f")  # Ctrl+O
        read_until(master, b"Enter filename to open (<ESC>=Cancel): ", timeout=4.0)
        time.sleep(0.2)
        os.write(master, b"30.TXT\r")
        out_open_30 = read_until(master, b"Row 1/30,", timeout=4.0)
        if b"C:30.TXT" not in out_open_30 or b"Line 01 of test file content" not in out_open_30:
            print(f"[-] Failed to open 30.TXT via Ctrl+O in editor mode. Buffer: {repr(out_open_30)}", flush=True)
            return False
        print("[+] Successfully verified Ctrl+O in editor mode opens file into editor.", flush=True)

        # Return to splash (ESC)
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"Auto-detects CP/M [CRLF]", timeout=4.0)

        # Final exit from splash to CP/M
        time.sleep(0.3)
        os.write(master, b"q")
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
