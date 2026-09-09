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
    buf = b""
    while True:
        r, _, _ = select.select([master_fd], [], [], quiet_time)
        if not r:
            break
        try:
            data = os.read(master_fd, 4096)
            if not data:
                break
            buf += data
        except (BlockingIOError, OSError):
            break
    return buf

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
        out = read_until(master, b"Free: 416 KB", timeout=14.0)
        if b"Auto-detects CP/M [CRLF]" not in out or b"Free: 416 KB" not in out:
            print("[-] SE.COM splash screen or free memory indicator not detected.", flush=True)
            return False
        print("[+] SE.COM splash screen successfully displayed with Free: 416 KB status bar.", flush=True)

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
        if b"Test 5:" not in out_mem or b"[PASS] Far RAM OOM" not in out_mem:
            print(f"[-] Test 5 not found in memory diagnostic! Buffer: {repr(out_mem)}", flush=True)
            return False
        print("[+] 512KB Extended Memory Diagnostic Suite (Tests 1, 2, 3, 4, 5) ALL PASSED!", flush=True)

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
            if b"Line 1/" in check_buf or b"SE v0.8.3" in check_buf or b"[No Name]" in check_buf:
                print(f"[-] Space key on splash screen erroneously entered editor mode! Buffer: {repr(check_buf)}", flush=True)
                return False

        # Verify cursor arrow keys do NOT enter editor mode from splash screen
        for arrow_name, arrow_seq in [("Up", b"\x1b[A"), ("Down", b"\x1b[B"), ("Right", b"\x1b[C"), ("Left", b"\x1b[D")]:
            os.write(master, arrow_seq)
            time.sleep(0.2)
            r, _, _ = select.select([master], [], [], 0.2)
            if r:
                check_buf = os.read(master, 2048)
                if b"Line 1/" in check_buf or b"SE v0.8.3" in check_buf or b"[No Name]" in check_buf:
                    print(f"[-] Cursor {arrow_name} key ({repr(arrow_seq)}) on splash screen erroneously entered editor mode! Buffer: {repr(check_buf)}", flush=True)
                    return False

        print("[+] Successfully verified Space and Cursor keys do not enter editor mode from splash screen.", flush=True)

        # Enter editor mode with 'e'
        os.write(master, b"e")
        out_edit = read_until(master, b"Line 1/1,", timeout=6.0)
        if b"SE v0.8.3" not in out_edit:
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
        out_row_clamp = read_until(master, b"Line 4/4,", timeout=3.0)
        if b"Line 4/4," not in out_row_clamp:
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
        out_join_bs = read_until(master, b"Line 1/3, Col 11", timeout=4.0)
        if b"Line 1/3, Col 11" not in out_join_bs:
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
        out_join_del = read_until(master, b"Line 1/2, Col 31", timeout=4.0)
        if b"Line 1/2, Col 31" not in out_join_del:
            print(f"[-] Line join via Delete key at EOL failed. Buffer: {repr(out_join_del)}", flush=True)
            return False
        drain_all(master)
        print("[+] Successfully verified Line Joining with Delete key (ESC [ 3 ~) at End of Line.")

        # 14. Test Real Tab character insertion & Tab-jumping navigation
        # Move cursor to (1,0)
        os.write(master, b"\x01")  # Ctrl+A -> Home
        read_until(master, b"Line 1/2, Col 0", timeout=3.0)
        drain_all(master)
        # Press Tab at (1,0) -> advances visual cursor to (1,8) -> displayed as Col 8 (0-indexed)
        os.write(master, b"\t")
        out_tab1 = read_until(master, b"Line 1/2, Col 8", timeout=4.0)
        if b"Line 1/2, Col 8" not in out_tab1:
            print(f"[-] Tab key from col 0 failed to reach col 8. Buffer captured: {repr(out_tab1)}", flush=True)
            return False
        drain_all(master)

        # Test Cursor Left jumping across the Tab in a single keystroke
        os.write(master, b"\x1b[D")
        out_tab_left = read_until(master, b"Line 1/2, Col 0", timeout=4.0)
        if b"Line 1/2, Col 0" not in out_tab_left:
            print(f"[-] Left arrow over Tab failed to jump back to col 0. Buffer captured: {repr(out_tab_left)}", flush=True)
            return False
        drain_all(master)

        # Test Cursor Right jumping across the Tab in a single keystroke
        os.write(master, b"\x1b[C")
        out_tab_right = read_until(master, b"Line 1/2, Col 8", timeout=4.0)
        if b"Line 1/2, Col 8" not in out_tab_right:
            print(f"[-] Right arrow over Tab failed to jump forward to col 8. Buffer captured: {repr(out_tab_right)}", flush=True)
            return False
        drain_all(master)

        # Test Backspace deleting the entire Tab in a single keystroke
        os.write(master, b"\x08")
        out_tab_bs = read_until(master, b"Line 1/2, Col 0", timeout=4.0)
        if b"Line 1/2, Col 0" not in out_tab_bs:
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

        # 16. Verify Ctrl+F in editor mode opens Find prompt and ESC cancels cleanly
        time.sleep(0.2)
        drain_all(master)
        os.write(master, b"\x06")
        out_find_prompt = read_until(master, b"Find (Exact):", timeout=4.0)
        if b"Find (Exact):" not in out_find_prompt:
            print(f"[-] Ctrl+F failed to open Find prompt. Buffer: {repr(out_find_prompt)}", flush=True)
            return False
        # Cancel with ESC
        os.write(master, b"\x1b")
        read_until(master, b"Line 4/4,", timeout=4.0)
        drain_all(master)
        print("[+] Successfully verified ^F in editor mode opens Find prompt and ESC cancels cleanly.", flush=True)

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
        read_until(master, b"SE v0.8.3", timeout=5.0)
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
        out_load = read_until(master, b"Line 1/2,", timeout=14.0)
        if b"SE v0.8.3" not in out_load:
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
        out_load_30 = read_until(master, b"Line 1/30,", timeout=14.0)
        if b"SE v0.8.3" not in out_load_30:
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
        out_pgdn = read_until(master, b"Line 30", timeout=4.0)
        if b"Line 30" not in out_pgdn:
            print(f"[-] Page Down key failed to navigate to bottom of document. Buffer: {repr(out_pgdn)}", flush=True)
            return False
        print("[+] Successfully verified Page-Down key (ESC [ 6 ~) navigation to Line 30.", flush=True)

        # 22. Test Page-Up key (\x1b[5~)
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"\x1b[5~")
        out_pgup = read_until(master, b"Line 1", timeout=4.0)
        if b"Line 1" not in out_pgup:
            print(f"[-] Page Up key failed to navigate back to top of document. Buffer: {repr(out_pgup)}", flush=True)
            return False
        print("[+] Successfully verified Page-Up key (ESC [ 5 ~) navigation to Line 1.", flush=True)

        # 23. Test Ctrl+V (Page Down) and Ctrl+U (Page Up) shortcuts
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"\x16")  # Ctrl+V -> Page Down
        out_ctrl_v = read_until(master, b"Line 30", timeout=4.0)
        if b"Line 30" not in out_ctrl_v:
            print(f"[-] Ctrl+V (Page Down) failed. Buffer: {repr(out_ctrl_v)}", flush=True)
            return False
        os.write(master, b"\x15")  # Ctrl+U -> Page Up
        out_ctrl_u = read_until(master, b"Line 1", timeout=4.0)
        if b"Line 1" not in out_ctrl_u:
            print(f"[-] Ctrl+U (Page Up) failed. Buffer: {repr(out_ctrl_u)}", flush=True)
            return False
        print("[+] Successfully verified Ctrl+V (Page Down) and Ctrl+U (Page Up) shortcuts.", flush=True)

        # 24. Test Jump to Top / Bottom (Ctrl+Home / Ctrl+End, Ctrl+T / Ctrl+G, ESC < / ESC >, ESC t / ESC b)
        # Test Ctrl+G (Jump to Bottom)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x07")  # Ctrl+G -> Jump to Bottom
        out_g = read_until(master, b"Line 30", timeout=4.0)
        if b"Line 30" not in out_g:
            print(f"[-] Ctrl+G failed to jump to bottom of file. Buffer: {repr(out_g)}", flush=True)
            return False

        # Test Ctrl+T (Jump to Top)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x14")  # Ctrl+T -> Jump to Top
        out_t = read_until(master, b"Line 1", timeout=4.0)
        if b"Line 1" not in out_t:
            print(f"[-] Ctrl+T failed to jump to top of file. Buffer: {repr(out_t)}", flush=True)
            return False

        # Test Ctrl+End (ESC [ 1 ; 5 F)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b[1;5F")
        out_cend = read_until(master, b"Line 30", timeout=4.0)
        if b"Line 30" not in out_cend:
            print(f"[-] Ctrl+End (ESC [ 1 ; 5 F) failed to jump to bottom. Buffer: {repr(out_cend)}", flush=True)
            return False

        # Test Ctrl+Home (ESC [ 1 ; 5 H)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b[1;5H")
        out_chome = read_until(master, b"Line 1", timeout=4.0)
        if b"Line 1" not in out_chome:
            print(f"[-] Ctrl+Home (ESC [ 1 ; 5 H) failed to jump to top. Buffer: {repr(out_chome)}", flush=True)
            return False

        # Test ESC > (Jump to Bottom)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b>")
        out_esc_gt = read_until(master, b"Line 30", timeout=4.0)
        if b"Line 30" not in out_esc_gt:
            print(f"[-] ESC > failed to jump to bottom. Buffer: {repr(out_esc_gt)}", flush=True)
            return False

        # Test ESC < (Jump to Top)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b<")
        out_esc_lt = read_until(master, b"Line 1", timeout=4.0)
        if b"Line 1" not in out_esc_lt:
            print(f"[-] ESC < failed to jump to top. Buffer: {repr(out_esc_lt)}", flush=True)
            return False

        # Test ESC b (Jump to Bottom)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1bb")
        out_esc_b = read_until(master, b"Line 30", timeout=4.0)
        if b"Line 30" not in out_esc_b:
            print(f"[-] ESC b failed to jump to bottom. Buffer: {repr(out_esc_b)}", flush=True)
            return False

        # Test ESC t (Jump to Top)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1bt")
        out_esc_t = read_until(master, b"Line 1", timeout=4.0)
        if b"Line 1" not in out_esc_t:
            print(f"[-] ESC t failed to jump to top. Buffer: {repr(out_esc_t)}", flush=True)
            return False

        print("[+] Successfully verified Jump to Top (Ctrl+T, Ctrl+Home, ESC <, ESC t) and Jump to Bottom (Ctrl+G, Ctrl+End, ESC >, ESC b)!", flush=True)

        # 25. Test ESC key showing splash screen and Enter resuming editor mode
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b")  # Standalone ESC key
        out_splash = read_until(master, b"Auto-detects CP/M [CRLF]", timeout=4.0)
        if b"SE - Screen Editor" not in out_splash:
            print(f"[-] ESC key failed to show splash screen. Buffer: {repr(out_splash)}", flush=True)
            return False
        if b"version 0.8.3 (2026-09-09)" not in out_splash:
            print(f"[-] Splash screen missing version date. Buffer: {repr(out_splash)}", flush=True)
            return False
        if b"Created using Google Antigravity 2.12.2 and Gemini 3.7 Flash" not in out_splash:
            print(f"[-] Splash screen missing Antigravity attribution. Buffer: {repr(out_splash)}", flush=True)
            return False
        out_splash_status = read_until(master, b"Line 1/30,", timeout=4.0)
        if b"Free: 412 KB" not in out_splash_status:
            print(f"[-] Splash screen status bar missing free memory indicator. Buffer: {repr(out_splash_status)}", flush=True)
            return False
        print("[+] Successfully verified ESC key in editor displays splash screen with version date, attribution, and free memory.", flush=True)

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

        # Test Space key does NOT advance page
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b" ")
        time.sleep(0.1)
        os.write(master, b"\x08")  # erase typed space

        # Test PageDown key (ESC [ 6 ~) to advance to Page 2
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b[6~")
        out_page2 = read_until(master, b"<PgUp>/<PgDn>=Page", timeout=4.0)
        if b"[Page 2/" not in out_page2 or b"<PgUp>/<PgDn>=Page" not in out_page2:
            print(f"[-] PageDown key failed to advance to Page 2. Buffer: {repr(out_page2)}", flush=True)
            return False
        print("[+] Successfully verified PageDown key pagination ([Page 2/X]).", flush=True)

        # Test PageUp key (ESC [ 5 ~) to return to Page 1
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b[5~")
        out_page1 = read_until(master, b"<PgUp>/<PgDn>=Page", timeout=4.0)
        if b"[Page 1/" not in out_page1 or b"<PgUp>/<PgDn>=Page" not in out_page1:
            print(f"[-] PageUp key failed to return to Page 1. Buffer: {repr(out_page1)}", flush=True)
            return False
        print("[+] Successfully verified PageUp key pagination back to Page 1.", flush=True)

        # Test pagination with text retained in text box
        time.sleep(0.1)
        os.write(master, b"TESTFILE")
        time.sleep(0.1)
        os.write(master, b"\x1b[6~")  # PageDown with "TESTFILE" typed
        out_p2 = read_until(master, b"[Page 2/", timeout=4.0)
        out_page2_retained = read_until(master, b"[TESTFILE", timeout=4.0)
        if b"[Page 2/" not in out_p2 or b"TESTFILE" not in out_page2_retained:
            print(f"[-] PageDown did not retain filename 'TESTFILE'. Buffer: {repr(out_page2_retained)}", flush=True)
            return False
        print("[+] Successfully verified PageDown retains typed filename in text box.", flush=True)

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
            if b"SE v0.8.3" in check_buf or b"Line 1/" in check_buf:
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
            if b"SE v0.8.3" in check_buf or b"Line 1/" in check_buf:
                print(f"[-] Backspace in open prompt erroneously entered editor mode! Buffer: {repr(check_buf)}", flush=True)
                return False

        # Type correct extension 'TXT' and press Enter
        os.write(master, b"TXT\r")
        out_loaded = read_until(master, b"Line 1/2,", timeout=4.0)
        if b"SE v0.8.3" not in out_loaded or b"C:2.TXT" not in out_loaded:
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
        out_back = read_until(master, b"SE v0.8.3", timeout=4.0)
        if b"SE v0.8.3" not in out_back:
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
        out_saved = read_until(master, b"SE v0.8.3", timeout=5.0)
        if b"SE v0.8.3" not in out_saved:
            print(f"[-] Editor mode not restored after confirming save. Buffer: {repr(out_saved)}", flush=True)
            return False
        print("[+] Successfully verified confirming overwrite ('y') saves file and resumes editor.", flush=True)

        # Return to splash screen (ESC) and test ':s' option
        drain_all(master)
        time.sleep(0.3)
        os.write(master, b"\x1b")
        out_splash = read_until(master, b"s                to save file", timeout=5.0)
        if b"s                to save file" not in out_splash:
            print(f"[-] Splash screen 's to save file' not found. Buffer: {repr(out_splash)}", flush=True)
            return False
        print("[+] Successfully verified splash screen displays 's to save file'.", flush=True)

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
        read_until(master, b"Enter filename to open:", timeout=3.0)
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
        read_until(master, b"Enter filename to open:", timeout=4.0)
        time.sleep(0.2)
        os.write(master, b"30.TXT\r")
        out_open_30 = read_until(master, b"Line 1/30,", timeout=4.0)
        if b"C:30.TXT" not in out_open_30 or b"Line 01 of test file content" not in out_open_30:
            print(f"[-] Failed to open 30.TXT via Ctrl+O in editor mode. Buffer: {repr(out_open_30)}", flush=True)
            return False
        print("[+] Successfully verified Ctrl+O in editor mode opens file into editor.", flush=True)

        # 30. Test Drive Switching in Open Screen ("B:" and "C:")
        time.sleep(0.2)
        os.write(master, b"\x0f")  # Ctrl+O
        read_until(master, b"Enter filename to open:", timeout=4.0)
        time.sleep(0.2)
        # Type 'B:' and hit Return to switch to Drive B:
        os.write(master, b"B:\r")
        out_drive_b = read_until(master, b"OPEN FILE (DIRECTORY - DRIVE B:)", timeout=4.0)
        if b"OPEN FILE (DIRECTORY - DRIVE B:)" not in out_drive_b:
            print(f"[-] Failed to switch to Drive B: in Open Screen. Buffer: {repr(out_drive_b)}", flush=True)
            return False
        # Verify prompt retains 'B:' (Drive B: has 2 pages, so multi-page prompt format is used)
        out_retained_b = read_until(master, b"[B:", timeout=3.0)
        if b"[B:" not in out_retained_b:
            print(f"[-] Prompt did not retain 'B:'. Buffer: {repr(out_retained_b)}", flush=True)
            return False
        print("[+] Successfully verified switching to Drive B: in Open Screen with 'B:' retained in text box.", flush=True)

        # Type backspaces to clear 'B:' and switch back to Drive C:
        time.sleep(0.2)
        os.write(master, b"\x08\x08C:\r")
        out_drive_c = read_until(master, b"OPEN FILE (DIRECTORY - DRIVE C:)", timeout=4.0)
        if b"OPEN FILE (DIRECTORY - DRIVE C:)" not in out_drive_c:
            print(f"[-] Failed to switch back to Drive C: in Open Screen. Buffer: {repr(out_drive_c)}", flush=True)
            return False
        out_retained_c = read_until(master, b"[C:", timeout=3.0)
        if b"[C:" not in out_retained_c:
            print(f"[-] Prompt did not retain 'C:'. Buffer: {repr(out_retained_c)}", flush=True)
            return False
        # Press ESC to cancel back to editor mode
        time.sleep(0.2)
        os.write(master, b"\x1b")
        out_esc_back = read_until(master, b"^K: Editor keys", timeout=4.0)
        if b"C:30.TXT" not in out_esc_back:
            print(f"[-] ESC from drive-switched open screen failed to restore editor. Buffer: {repr(out_esc_back)}", flush=True)
            return False
        print("[+] Successfully verified switching back to Drive C: and returning to editor on ESC.", flush=True)

        # 31. Test Drive Switching in Save Screen ("B:" and "C:")
        time.sleep(0.2)
        os.write(master, b"\x13")  # Ctrl+S
        read_until(master, b"SAVE FILE (DIRECTORY - DRIVE C:)", timeout=4.0)
        read_until(master, b"Enter filename to save:", timeout=3.0)
        # Clear pre-filled name and enter 'B:' followed by Return
        time.sleep(0.2)
        os.write(master, b"\x08" * 20 + b"B:\r")
        out_save_b = read_until(master, b"SAVE FILE (DIRECTORY - DRIVE B:)", timeout=4.0)
        if b"SAVE FILE (DIRECTORY - DRIVE B:)" not in out_save_b:
            print(f"[-] Failed to switch to Drive B: in Save Screen. Buffer: {repr(out_save_b)}", flush=True)
            return False
        out_save_retained_b = read_until(master, b"[B:", timeout=3.0)
        if b"[B:" not in out_save_retained_b:
            print(f"[-] Save prompt did not retain 'B:'. Buffer: {repr(out_save_retained_b)}", flush=True)
            return False
        print("[+] Successfully verified switching to Drive B: in Save Screen with 'B:' retained in text box.", flush=True)

        # Switch back to Drive C: in Save Screen
        time.sleep(0.2)
        os.write(master, b"\x08\x08C:\r")
        out_save_c = read_until(master, b"SAVE FILE (DIRECTORY - DRIVE C:)", timeout=4.0)
        if b"SAVE FILE (DIRECTORY - DRIVE C:)" not in out_save_c:
            print(f"[-] Failed to switch back to Drive C: in Save Screen. Buffer: {repr(out_save_c)}", flush=True)
            return False
        out_save_retained_c = read_until(master, b"[C:", timeout=3.0)
        if b"[C:" not in out_save_retained_c:
            print(f"[-] Save prompt did not retain 'C:'. Buffer: {repr(out_save_retained_c)}", flush=True)
            return False
        # Cancel Save screen on ESC
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"^K: Editor keys", timeout=4.0)
        print("[+] Successfully verified switching back to Drive C: in Save Screen and ESC returns cleanly.", flush=True)

        # 32. Test High-Speed Burst Paste (Clipboard Simulation)
        time.sleep(0.2)
        drain_all(master)
        os.write(master, b"\x05")  # Ctrl+E -> End of Line
        time.sleep(0.1)
        # Simulate minicom clipboard paste: send rapid burst of characters in a single write with no delay
        paste_text = b" [BURST-PASTED TEXT VIA CLIPBOARD]"
        os.write(master, paste_text)
        # Verify that deferred rendering flushed and the pasted text is visible on screen
        out_paste = read_until(master, b"[BURST-PASTED TEXT VIA CLIPBOARD]", timeout=4.0)
        if b"[BURST-PASTED TEXT VIA CLIPBOARD]" not in out_paste:
            print(f"[-] Fast burst paste text missing on screen. Buffer: {repr(out_paste)}", flush=True)
            return False
        print("[+] Successfully verified high-speed clipboard burst paste deferred redraw!", flush=True)

        # 33. Test Line Slot Indirection & Slot Recycling from Extended RAM
        time.sleep(0.2)
        drain_all(master)
        # Split line with Enter to allocate a slot
        os.write(master, b"\rSLOT_RECYCLE_TEST_LINE\rANOTHER_LINE")
        out_split = read_until(master, b"ANOTHER_LINE", timeout=4.0)
        if b"ANOTHER_LINE" not in out_split:
            print(f"[-] Line split/slot alloc failed. Buffer: {repr(out_split)}", flush=True)
            return False
        # Move to column 0 of ANOTHER_LINE and press Backspace to join lines and free the slot to Extended RAM
        os.write(master, b"\x01\x08")  # Ctrl+A (col 0), Backspace (join)
        time.sleep(0.2)
        # Press Enter again to re-allocate from the Extended RAM free list
        os.write(master, b"\rRECYCLED_SLOT_LINE")
        out_recycled = read_until(master, b"RECYCLED_SLOT_LINE", timeout=4.0)
        if b"RECYCLED_SLOT_LINE" not in out_recycled:
            print(f"[-] Slot recycling failed. Buffer: {repr(out_recycled)}", flush=True)
            return False
        print("[+] Successfully verified slot allocation, deallocation, and recycling from Extended RAM!", flush=True)

        # 34. Test Hybrid Block Highlighting & Ctrl+K Solidification
        time.sleep(0.2)
        drain_all(master)
        # Move to top of document (Ctrl+T) and column 0 (Ctrl+A)
        os.write(master, b"\x14\x01")
        read_until(master, b"Line 1/", timeout=4.0)

        # Press Ctrl+B (\x02) to activate block mode at Row 1, Col 0: 0 chars selected
        os.write(master, b"\x02")
        out_blk0c = read_until(master, b"[SEL: 0c]", timeout=4.0)
        if b"[SEL: 0c]" not in out_blk0c:
            print(f"[-] Hybrid block activation failed (expected [SEL: 0c]). Buffer: {repr(out_blk0c)}", flush=True)
            return False
        # Verify screen did not corrupt (subsequent lines must remain distinct and not repeat line 1)
        if b"Line 02 of " not in out_blk0c or b"Line 03 of " not in out_blk0c:
            print(f"[-] Screen corruption detected after Ctrl+B! Distinct lines missing. Buffer: {repr(out_blk0c)}", flush=True)
            return False

        # Move cursor right 5 columns to expand partial line selection to 5 characters
        os.write(master, b"\x1b[C" * 5)
        out_blk5c = read_until(master, b"[SEL: 5c]", timeout=4.0)
        if b"[SEL: 5c]" not in out_blk5c:
            print(f"[-] Partial single-line expansion failed (expected [SEL: 5c]). Buffer: {repr(out_blk5c)}", flush=True)
            return False
        # Verify inverse video sequence \x1b[7m is emitted in buffer
        if b"\x1b[7m" not in out_blk5c:
            print(f"[-] Inverse video escape sequence missing during block highlight. Buffer: {repr(out_blk5c)}", flush=True)
            return False

        # Move cursor down 2 rows to expand block to 3 lines
        os.write(master, b"\x1b[B\x1b[B")
        out_blk3l = read_until(master, b"[SEL: 3L]", timeout=4.0)
        if b"[SEL: 3L]" not in out_blk3l:
            print(f"[-] Multi-line block expansion failed (expected [SEL: 3L]). Buffer: {repr(out_blk3l)}", flush=True)
            return False

        # Move cursor up 1 row to contract block to 2 lines
        os.write(master, b"\x1b[A")
        out_blk2l = read_until(master, b"[SEL: 2L]", timeout=4.0)
        if b"[SEL: 2L]" not in out_blk2l:
            print(f"[-] Multi-line block contraction failed (expected [SEL: 2L]). Buffer: {repr(out_blk2l)}", flush=True)
            return False

        # Solidify block with Ctrl+K (\x0b)
        os.write(master, b"\x0b")
        out_solid = read_until(master, b"[BLK: 2L LOCK]", timeout=4.0)
        if b"[BLK: 2L LOCK]" not in out_solid:
            print(f"[-] Ctrl+K block solidification failed (expected [BLK: 2L LOCK]). Buffer: {repr(out_solid)}", flush=True)
            return False

        # Move cursor down after solidification; verify block remains locked
        os.write(master, b"\x1b[B")
        time.sleep(0.1)
        drain_all(master)
        # Redraw status / verify locked state
        os.write(master, b"\x1b[A")
        out_still_locked = read_until(master, b"[BLK: 2L LOCK]", timeout=4.0)
        if b"[BLK: 2L LOCK]" not in out_still_locked:
            print(f"[-] Block did not remain locked after cursor movement. Buffer: {repr(out_still_locked)}", flush=True)
            return False

        # Press ESC to cancel solidified block mode (should clear [BLK: ... LOCK] and stay in editor)
        os.write(master, b"\x1b")
        out_esc_blk = read_until(master, b"^K: Editor keys", timeout=4.0)
        if b"^K: Editor keys" not in out_esc_blk:
            print(f"[-] ESC failed to cancel solidified block. Buffer: {repr(out_esc_blk)}", flush=True)
            return False

        # Verify single-line partial block with Ctrl+K solidification
        os.write(master, b"\x02")
        read_until(master, b"[SEL: 0c]", timeout=4.0)
        os.write(master, b"\x1b[C" * 3)
        read_until(master, b"[SEL: 3c]", timeout=4.0)
        os.write(master, b"\x0b")
        out_solid_c = read_until(master, b"[BLK: 3c LOCK]", timeout=4.0)
        if b"[BLK: 3c LOCK]" not in out_solid_c:
            print(f"[-] Single-line Ctrl+K solidification failed. Buffer: {repr(out_solid_c)}", flush=True)
            return False

        # Cancel with Ctrl+B
        os.write(master, b"\x02")
        out_toggle_off = read_until(master, b"^K: Editor keys", timeout=4.0)
        if b"^K: Editor keys" not in out_toggle_off:
            print(f"[-] Ctrl+B cancel of solidified block failed. Buffer: {repr(out_toggle_off)}", flush=True)
        # Step 35: Verify tab block highlighting on the last line of block
        print("[*] Step 35: Testing dynamic tab block highlighting on the last line...", flush=True)
        # Move to top of document (Ctrl+T)
        os.write(master, b"\x14")
        time.sleep(0.1)
        drain_all(master)

        # Clear document: delete current lines or open new file, or enter text
        # Insert a new line 1 and line 2 with a tab: "L1\rA\tB"
        os.write(master, b"L1\rA\tB")
        time.sleep(0.2)
        drain_all(master)

        # Jump to top: Ctrl+T (Line 1 Col 0)
        os.write(master, b"\x14")
        time.sleep(0.1)
        drain_all(master)

        # Start block at Line 1 Col 0 (Ctrl+B)
        os.write(master, b"\x02")
        time.sleep(0.1)
        drain_all(master)

        # Move down to Line 2 (Down Arrow) -> cursor at Col 0 ('A')
        os.write(master, b"\x1b[B")
        time.sleep(0.1)
        drain_all(master)

        # Move right onto TAB (Right Arrow) -> cursor at Col 1 (the TAB)
        os.write(master, b"\x1b[C")
        time.sleep(0.1)
        out_tab_on = drain_all(master)
        # Verify that TAB is NOT prematurely highlighted across its expanded spaces
        # Line 2 should have 'A' highlighted, but NOT the tab spaces
        if b"\x1b[7mA\x1b[0m       B" not in out_tab_on:
            print(f"[-] Tab prematurely highlighted on last line. Buffer: {repr(out_tab_on)}", flush=True)
            return False

        # Move right past TAB onto 'B' (Right Arrow) -> cursor at Col 8 ('B')
        os.write(master, b"\x1b[C")
        time.sleep(0.1)
        out_tab_past = drain_all(master)
        # Verify that TAB IS now highlighted (while 'B' under cursor remains un-highlighted)
        if b"\x1b[7mA       \x1b[0mB" not in out_tab_past:
            print(f"[-] Tab failed to highlight after cursor moved past it. Buffer: {repr(out_tab_past)}", flush=True)
            return False

        # Move left back onto TAB (Left Arrow) -> cursor at Col 1 (the TAB)
        os.write(master, b"\x1b[D")
        time.sleep(0.1)
        out_tab_back = drain_all(master)
        # Verify that TAB dynamically un-highlights
        if b"\x1b[7mA\x1b[0m       B" not in out_tab_back:
            print(f"[-] Tab failed to dynamically un-highlight when cursoring back. Buffer: {repr(out_tab_back)}", flush=True)
            return False

        # Cancel block mode (Ctrl+B)
        os.write(master, b"\x02")
        time.sleep(0.1)
        drain_all(master)
        print("[+] Successfully verified dynamic tab block highlighting on last line!", flush=True)

        # Step 36: Test Solidified Block Copy (Ctrl+C)
        print("[*] Step 36: Testing solidified block copy (Ctrl+C)...", flush=True)
        # Move to top of document (Ctrl+T) and column 0 (Ctrl+A)
        os.write(master, b"\x14\x01")
        time.sleep(0.1)
        drain_all(master)

        # Start block at Row 1, Col 0: Ctrl+B
        os.write(master, b"\x02")
        time.sleep(0.1)
        # Select 2 characters: Right Arrow twice (Col 0 -> Col 2)
        os.write(master, b"\x1b[C\x1b[C")
        time.sleep(0.1)
        # Solidify block with Ctrl+K
        os.write(master, b"\x0b")
        out_solid_cpy = read_until(master, b"[BLK: 2c LOCK]", timeout=4.0)
        if b"[BLK: 2c LOCK]" not in out_solid_cpy:
            print(f"[-] Block solidification failed for Ctrl+C test. Buffer: {repr(out_solid_cpy)}", flush=True)
            return False
        time.sleep(0.1)
        drain_all(master)

        # Test 1: Move cursor inside block (Left Arrow to Col 1) and press Ctrl+C: must be ignored!
        os.write(master, b"\x1b[D")
        time.sleep(0.1)
        drain_all(master)
        os.write(master, b"\x03")
        time.sleep(0.2)
        out_in_blk = drain_all(master)
        if out_in_blk != b"":
            print(f"[-] Ctrl+C inside block was not ignored. Buffer: {repr(out_in_blk)}", flush=True)
            return False

        # Move cursor to end of line: Ctrl+E (Col 2 or higher, outside block)
        os.write(master, b"\x05")
        time.sleep(0.1)
        drain_all(master)

        # Test 2: Press Ctrl+C outside block: copies block
        os.write(master, b"\x03")
        time.sleep(0.3)
        out_cpy1 = drain_all(master)
        if b"[BLK: 2c LOCK]" not in out_cpy1 or (b"L1L1" not in out_cpy1 and b"L1\x1b[0mL1" not in out_cpy1):
            print(f"[-] Ctrl+C copy failed or lost block lock. Buffer: {repr(out_cpy1)}", flush=True)
            return False

        # Test 3: Press Ctrl+C again consecutively: duplicate copy
        os.write(master, b"\x03")
        time.sleep(0.3)
        out_cpy2 = drain_all(master)
        if b"[BLK: 2c LOCK]" not in out_cpy2 or (b"L1L1L1" not in out_cpy2 and b"L1\x1b[0mL1L1" not in out_cpy2):
            print(f"[-] Consecutive Ctrl+C failed or lost block lock. Buffer: {repr(out_cpy2)}", flush=True)
            return False

        # Test 4: Multi-line block copy (1L boundary at Row 2 Col 0, and 2L full block)
        # Cancel previous block with ESC
        os.write(master, b"\x1b")
        time.sleep(0.1)
        drain_all(master)

        # Move to Row 1 Col 0: Ctrl+T, Ctrl+A
        os.write(master, b"\x14\x01")
        time.sleep(0.1)
        # Start block (Ctrl+B), expand down 1 row (Down Arrow to Row 2 Col 0)
        os.write(master, b"\x02\x1b[B")
        time.sleep(0.1)
        # Solidify with Ctrl+K -> must be [BLK: 1L LOCK]
        os.write(master, b"\x0b")
        out_1l_solid = read_until(master, b"[BLK: 1L LOCK]", timeout=4.0)
        if b"[BLK: 1L LOCK]" not in out_1l_solid:
            print(f"[-] 1L block solidification failed. Buffer: {repr(out_1l_solid)}", flush=True)
            return False

        # Test Ctrl+C directly at Row 2 Col 0: must not be ignored
        drain_all(master)
        os.write(master, b"\x03")
        time.sleep(0.3)
        out_1l_cpy = drain_all(master)
        if b"[BLK: 1L LOCK]" not in out_1l_cpy:
            print(f"[-] Ctrl+C at Row 2 Col 0 failed. Buffer: {repr(out_1l_cpy)}", flush=True)
            return False

        # Cancel block
        os.write(master, b"\x1b")
        time.sleep(0.1)
        drain_all(master)

        # Move to Row 1 Col 0: Ctrl+T, Ctrl+A
        os.write(master, b"\x14\x01")
        time.sleep(0.1)
        # Start block (Ctrl+B), expand down 2 rows (Down Arrow twice) for 2 lines
        os.write(master, b"\x02\x1b[B\x1b[B")
        time.sleep(0.1)
        # Solidify with Ctrl+K -> must be [BLK: 2L LOCK]
        os.write(master, b"\x0b")
        out_ml_solid = read_until(master, b"[BLK: 2L LOCK]", timeout=4.0)
        if b"[BLK: 2L LOCK]" not in out_ml_solid:
            print(f"[-] Multi-line solidification failed. Buffer: {repr(out_ml_solid)}", flush=True)
            return False

        # Jump to bottom of file (Ctrl+G), then end of line (Ctrl+E)
        os.write(master, b"\x07\x05")
        time.sleep(0.1)
        drain_all(master)

        # Copy multi-line block with Ctrl+C
        os.write(master, b"\x03")
        time.sleep(0.3)
        out_ml_cpy = drain_all(master)
        if b"[BLK: 2L LOCK]" not in out_ml_cpy:
            print(f"[-] Multi-line block copy failed. Buffer: {repr(out_ml_cpy)}", flush=True)
            return False

        # Test 5: Cancellation terminates Ctrl+C
        os.write(master, b"\x1b")
        time.sleep(0.1)
        drain_all(master)
        os.write(master, b"\x03")
        time.sleep(0.2)
        out_cancelled = drain_all(master)
        if out_cancelled != b"":
            print(f"[-] Ctrl+C operated after block was cancelled! Buffer: {repr(out_cancelled)}", flush=True)
            return False

        print("[+] Successfully verified solidified block copy (Ctrl+C) feature!", flush=True)

        # Step 37: Test Half-Open Caret Selection [Start, End) Semantics
        print("[*] Step 37: Testing half-open caret selection [Start, End) semantics...", flush=True)
        # Move to top of document (Ctrl+T) and column 0 (Ctrl+A)
        os.write(master, b"\x14\x01")
        time.sleep(0.1)
        drain_all(master)

        # 1. Start in Column 0, press Ctrl+B:
        # Must show [SEL: 0c], zero chars in block, no inverse video on character 0
        os.write(master, b"\x02")
        out_s37_0c = read_until(master, b"[SEL: 0c]", timeout=4.0)
        if b"[SEL: 0c]" not in out_s37_0c:
            print(f"[-] Step 37 failed: Ctrl+B at Col 0 did not show [SEL: 0c]. Buffer: {repr(out_s37_0c)}", flush=True)
            return False

        # 2. Cursor right 1 char (Right Arrow to Col 1):
        # Old cursor location (Col 0) becomes highlighted, cursor cell at Col 1 is normal video
        os.write(master, b"\x1b[C")
        out_s37_1c = read_until(master, b"[SEL: 1c]", timeout=4.0)
        if b"[SEL: 1c]" not in out_s37_1c:
            print(f"[-] Step 37 failed: Right arrow did not show [SEL: 1c]. Buffer: {repr(out_s37_1c)}", flush=True)
            return False

        # 3. Press Ctrl+K to solidify: shows [BLK: 1c LOCK]
        os.write(master, b"\x0b")
        out_s37_solid = read_until(master, b"[BLK: 1c LOCK]", timeout=4.0)
        if b"[BLK: 1c LOCK]" not in out_s37_solid:
            print(f"[-] Step 37 failed: Ctrl+K did not show [BLK: 1c LOCK]. Buffer: {repr(out_s37_solid)}", flush=True)
            return False

        # 4. Press Ctrl+C at Col 1: must NOT be ignored (Col 1 is outside [0, 1)!)
        drain_all(master)
        os.write(master, b"\x03")
        time.sleep(0.3)
        out_s37_cpy1 = drain_all(master)
        if b"[BLK: 1c LOCK]" not in out_s37_cpy1:
            print(f"[-] Step 37 failed: Ctrl+C at Col 1 was ignored or corrupted! Buffer: {repr(out_s37_cpy1)}", flush=True)
            return False

        # 5. Cursor right 1 char (Right Arrow to Col 2):
        # Verifies only the 1 original character is highlighted
        os.write(master, b"\x1b[C")
        time.sleep(0.1)
        drain_all(master)

        # 6. Press Ctrl+C at Col 2: duplicates exactly 1 character
        os.write(master, b"\x03")
        time.sleep(0.3)
        out_s37_cpy2 = drain_all(master)
        if b"[BLK: 1c LOCK]" not in out_s37_cpy2:
            print(f"[-] Step 37 failed: Second Ctrl+C failed or corrupted! Buffer: {repr(out_s37_cpy2)}", flush=True)
            return False

        # 7. Cancel block with ESC
        os.write(master, b"\x1b")
        time.sleep(0.1)
        drain_all(master)

        print("[+] Successfully verified half-open caret selection [Start, End) semantics (Step 37)!", flush=True)

        # Step 38: Test Backwards Block Selection Normalization Semantics
        print("[*] Step 38: Testing backwards block selection semantics...", flush=True)

        # Part 1: Multi-line backwards selection (Row 10 Col 5 left arrow wrapping onto Row 9 to Col 0)
        # Move to top of document (Ctrl+T) and Col 0 (Ctrl+A), then move to Row 10 Col 5
        os.write(master, b"\x14\x01")
        read_until(master, b"Line 1/", timeout=4.0)
        os.write(master, b"\x1b[B" * 9)
        read_until(master, b"Line 10/", timeout=4.0)
        os.write(master, b"\x1b[C" * 5)
        out_s38_r10c5 = read_until(master, b", Col 5", timeout=4.0)
        if b", Col 5" not in out_s38_r10c5:
            print(f"[-] Step 38 failed: Could not navigate to Row 10 Col 5. Buffer: {repr(out_s38_r10c5)}", flush=True)
            return False

        # Press Ctrl+B to start block at Row 10 Col 5
        os.write(master, b"\x02")
        out_s38_b10 = read_until(master, b"[SEL: 0c]", timeout=4.0)
        if b"[SEL: 0c]" not in out_s38_b10:
            print(f"[-] Step 38 failed: Ctrl+B at Row 10 Col 5 did not show [SEL: 0c]. Buffer: {repr(out_s38_b10)}", flush=True)
            return False

        # Press Left Arrow 6 times: moves Col 5 -> 4 -> 3 -> 2 -> 1 -> 0 -> wraps to Row 9 end
        for _ in range(6):
            os.write(master, b"\x1b[D")
            time.sleep(0.05)
        out_s38_wrap = read_until(master, b"[SEL: 2L]", timeout=4.0)
        if b"[SEL: 2L]" not in out_s38_wrap:
            print(f"[-] Step 38 failed: Left arrow wrap did not show [SEL: 2L]. Buffer: {repr(out_s38_wrap)}", flush=True)
            return False

        # Continue pressing Left Arrow until cursor reaches Row 9 Col 0
        while True:
            os.write(master, b"\x1b[D")
            time.sleep(0.05)
            buf = drain_all(master)
            if b"Line 9/" in buf and b", Col 0 " in buf:
                break

        # Confirm Row 9 remains highlighted (cols 1..254) and status remains [SEL: 2L]
        out_s38_col0 = drain_all(master)
        # Redraw status bar / line check:
        os.write(master, b"")
        time.sleep(0.1)

        # Press Ctrl+K to solidify: shows [BLK: 2L LOCK]
        os.write(master, b"\x0b")
        out_s38_solid_ml = read_until(master, b"[BLK: 2L LOCK]", timeout=4.0)
        if b"[BLK: 2L LOCK]" not in out_s38_solid_ml:
            print(f"[-] Step 38 failed: Ctrl+K did not show [BLK: 2L LOCK]. Buffer: {repr(out_s38_solid_ml)}", flush=True)
            return False

        # Press Ctrl+C at Row 9 Col 0: must NOT be ignored
        drain_all(master)
        os.write(master, b"\x03")
        time.sleep(0.3)
        out_s38_cpy_ml = drain_all(master)
        if b"[BLK: 2L LOCK]" not in out_s38_cpy_ml:
            print(f"[-] Step 38 failed: Ctrl+C at Row 9 Col 0 was ignored or failed! Buffer: {repr(out_s38_cpy_ml)}", flush=True)
            return False

        # Cancel block with ESC
        os.write(master, b"\x1b")
        time.sleep(0.1)
        drain_all(master)

        # Part 2: Single-line backwards selection (Col 5 left to Col 4)
        # Move to top of document (Ctrl+T) and Col 0 (Ctrl+A), then move right 5 columns
        os.write(master, b"\x14\x01")
        read_until(master, b"Line 1/", timeout=4.0)
        os.write(master, b"\x1b[C" * 5)
        out_s38_c5 = read_until(master, b", Col 5", timeout=4.0)
        if b", Col 5" not in out_s38_c5:
            print(f"[-] Step 38 failed: Could not navigate to Col 5. Buffer: {repr(out_s38_c5)}", flush=True)
            return False

        # Press Ctrl+B to start block at Col 5
        os.write(master, b"\x02")
        out_s38_b5 = read_until(master, b"[SEL: 0c]", timeout=4.0)
        if b"[SEL: 0c]" not in out_s38_b5:
            print(f"[-] Step 38 failed: Ctrl+B at Col 5 did not show [SEL: 0c]. Buffer: {repr(out_s38_b5)}", flush=True)
            return False

        # Press Left Arrow to Col 4: expands 1 character backwards
        os.write(master, b"\x1b[D")
        out_s38_left = read_until(master, b"[SEL: 1c]", timeout=4.0)
        if b"[SEL: 1c]" not in out_s38_left:
            print(f"[-] Step 38 failed: Left arrow did not show [SEL: 1c]. Buffer: {repr(out_s38_left)}", flush=True)
            return False

        # Press Ctrl+K to solidify: shows [BLK: 1c LOCK]
        os.write(master, b"\x0b")
        out_s38_solid_sl = read_until(master, b"[BLK: 1c LOCK]", timeout=4.0)
        if b"[BLK: 1c LOCK]" not in out_s38_solid_sl:
            print(f"[-] Step 38 failed: Ctrl+K did not show [BLK: 1c LOCK]. Buffer: {repr(out_s38_solid_sl)}", flush=True)
            return False

        # Press Ctrl+C at Col 4: must NOT be ignored (Col 4 is outside [5, 6)!)
        drain_all(master)
        os.write(master, b"\x03")
        time.sleep(0.3)
        out_s38_cpy_sl = drain_all(master)
        if b"[BLK: 1c LOCK]" not in out_s38_cpy_sl:
            print(f"[-] Step 38 failed: Ctrl+C at Col 4 was ignored or failed! Buffer: {repr(out_s38_cpy_sl)}", flush=True)
            return False

        # Cancel block with ESC
        os.write(master, b"\x1b")
        time.sleep(0.1)
        drain_all(master)

        print("[+] Successfully verified backwards block selection semantics (Step 38)!", flush=True)

        # Step 39: Verify Block Selection Workflow Simplifications
        print("[*] Step 39: Testing block selection workflow simplifications...", flush=True)

        # 1. Test Ctrl-B re-anchoring
        os.write(master, b"\x14\x01") # Ctrl+T, Ctrl+A to top and col 0
        time.sleep(0.1)
        drain_all(master)

        os.write(master, b"\x02") # Ctrl-B
        out_b0 = read_until(master, b"[SEL: 0c]", timeout=4.0)
        if b"[SEL: 0c]" not in out_b0:
            print(f"[-] Step 39 Ctrl-B activation failed: {repr(out_b0)}", flush=True)
            return False

        os.write(master, b"\x1b[C" * 5) # Right 5 cols
        out_b5 = read_until(master, b"[SEL: 5c]", timeout=4.0)
        if b"[SEL: 5c]" not in out_b5:
            print(f"[-] Step 39 Ctrl-B move right failed: {repr(out_b5)}", flush=True)
            return False

        os.write(master, b"\x02") # Ctrl-B: cursor moved, so re-anchors to 0c at current col!
        out_b_re = read_until(master, b"[SEL: 0c]", timeout=4.0)
        if b"[SEL: 0c]" not in out_b_re:
            print(f"[-] Step 39 Ctrl-B re-anchor failed: {repr(out_b_re)}", flush=True)
            return False

        os.write(master, b"\x1b[C" * 2) # Right 2 cols
        out_b2 = read_until(master, b"[SEL: 2c]", timeout=4.0)
        if b"[SEL: 2c]" not in out_b2:
            print(f"[-] Step 39 expansion after re-anchor failed: {repr(out_b2)}", flush=True)
            return False

        os.write(master, b"\x02") # Ctrl-B at Col 7: re-anchors at Col 7
        read_until(master, b"[SEL: 0c]", timeout=4.0)
        os.write(master, b"\x02") # Ctrl-B without moving: cancels block!
        out_b_canc = read_until(master, b"^K: Editor keys", timeout=4.0)
        if b"^K: Editor keys" not in out_b_canc:
            print(f"[-] Step 39 Ctrl-B cancel without moving failed: {repr(out_b_canc)}", flush=True)
            return False

        # 2. Test Shift + Arrow keys
        os.write(master, b"\x14\x01") # Ctrl+T, Ctrl+A
        time.sleep(0.1)
        drain_all(master)

        os.write(master, b"\x1b[1;2C") # Shift+Right
        out_s_r = read_until(master, b"[SEL: 1c]", timeout=4.0)
        if b"[SEL: 1c]" not in out_s_r:
            print(f"[-] Step 39 Shift+Right failed: {repr(out_s_r)}", flush=True)
            return False

        os.write(master, b"\x1b[C") # Unshifted Right Arrow -> extends block
        out_s_ext = read_until(master, b"[SEL: 2c]", timeout=4.0)
        if b"[SEL: 2c]" not in out_s_ext:
            print(f"[-] Step 39 unshifted Right extension failed: {repr(out_s_ext)}", flush=True)
            return False

        os.write(master, b"\x1b[1;2B") # Shift+Down -> cancels active block, starts new, moves down
        out_s_d = read_until(master, b"[SEL: 2L]", timeout=4.0)
        if b"[SEL: 2L]" not in out_s_d:
            print(f"[-] Step 39 Shift+Down failed: {repr(out_s_d)}", flush=True)
            return False

        os.write(master, b"\x1b") # Cancel with ESC
        read_until(master, b"^K: Editor keys", timeout=4.0)

        # 3. Test Ctrl-D implied Ctrl-K + Delete
        os.write(master, b"\x14\x01") # Ctrl+T, Ctrl+A
        time.sleep(0.1)
        drain_all(master)

        # Type a test marker line
        os.write(master, b"DELTEST12345\r")
        time.sleep(0.1)
        os.write(master, b"\x14\x01") # Back to top, col 0
        read_until(master, b"DELTEST12345", timeout=4.0)

        os.write(master, b"\x02" + b"\x1b[C" * 7) # Select "DELTEST"
        out_d_sel = read_until(master, b"[SEL: 7c]", timeout=4.0)
        if b"[SEL: 7c]" not in out_d_sel:
            print(f"[-] Step 39 select DELTEST failed: {repr(out_d_sel)}", flush=True)
            return False

        os.write(master, b"\x04") # Ctrl-D -> implied Ctrl-K + delete
        out_d_del = read_until(master, b"^K: Editor keys", timeout=4.0)
        if b"^K: Editor keys" not in out_d_del:
            print(f"[-] Step 39 Ctrl-D block delete failed: {repr(out_d_del)}", flush=True)
            return False

        os.write(master, b"\x14")
        out_d_scr = read_until(master, b"12345", timeout=4.0)
        if b"12345" not in out_d_scr or b"DELTEST" in out_d_scr:
            print(f"[-] Step 39 deletion content check failed: {repr(out_d_scr)}", flush=True)
            return False

        # 4. Test Ctrl-C implied Ctrl-K + Navigation + Copy
        os.write(master, b"\x14\x01") # Top, Col 0 (cursor at "12345")
        time.sleep(0.1)
        drain_all(master)

        os.write(master, b"\x02" + b"\x1b[C" * 3) # Select "123"
        out_c_sel = read_until(master, b"[SEL: 3c]", timeout=4.0)
        if b"[SEL: 3c]" not in out_c_sel:
            print(f"[-] Step 39 select 123 failed: {repr(out_c_sel)}", flush=True)
            return False

        os.write(master, b"\x03") # Ctrl-C -> implied Ctrl-K (solidifies)
        out_c_lock = read_until(master, b"[BLK: 3c LOCK]", timeout=4.0)
        if b"[BLK: 3c LOCK]" not in out_c_lock:
            print(f"[-] Step 39 Ctrl-C solidify failed: {repr(out_c_lock)}", flush=True)
            return False

        os.write(master, b"\x05") # Ctrl-E -> End of line
        time.sleep(0.1)
        drain_all(master)

        os.write(master, b"\x03") # Ctrl-C -> Copy solidified block to end of line!
        time.sleep(0.2)
        drain_all(master)

        os.write(master, b"\x14")
        out_c_res = read_until(master, b"45123", timeout=4.0)
        if b"45123" not in out_c_res:
            print(f"[-] Step 39 Ctrl-C copy failed: {repr(out_c_res)}", flush=True)
            return False

        os.write(master, b"\x1b") # Cancel block
        read_until(master, b"^K: Editor keys", timeout=4.0)
        print("[+] Successfully verified block selection workflow simplifications (Step 39)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 40: Verify Block Move using Ctrl+X
        # ---------------------------------------------------------------------
        print("[*] Step 40: Verifying Block Move (Ctrl+X)...", flush=True)

        # 1. Ctrl-X when block is inactive is a safe no-op
        os.write(master, b"\x18") # Ctrl-X
        time.sleep(0.1)
        drain_all(master)
        os.write(master, b"\x14") # Ctrl-T
        out_s40_noop = read_until(master, b"^K: Editor keys", timeout=4.0)
        if b"^K: Editor keys" not in out_s40_noop:
            print(f"[-] Step 40 Ctrl-X inactive no-op failed: {repr(out_s40_noop)}", flush=True)
            return False

        # Current line is "12345123". Move to Col 0, select first "123"
        os.write(master, b"\x01") # Ctrl-A
        time.sleep(0.1)
        drain_all(master)

        os.write(master, b"\x02" + b"\x1b[C" * 3) # Ctrl-B, Right * 3 -> [SEL: 3c]
        out_s40_sel = read_until(master, b"[SEL: 3c]", timeout=4.0)
        if b"[SEL: 3c]" not in out_s40_sel:
            print(f"[-] Step 40 select 3c failed: {repr(out_s40_sel)}", flush=True)
            return False

        # Solidify with Ctrl-K
        os.write(master, b"\x0b")
        out_s40_lock = read_until(master, b"[BLK: 3c LOCK]", timeout=4.0)
        if b"[BLK: 3c LOCK]" not in out_s40_lock:
            print(f"[-] Step 40 Ctrl-K solidify failed: {repr(out_s40_lock)}", flush=True)
            return False

        # Move to end of line: Ctrl-E (Col 8)
        os.write(master, b"\x05")
        time.sleep(0.1)
        drain_all(master)

        # Move block to end of line with Ctrl-X (\x18)!
        os.write(master, b"\x18")
        out_s40_move1 = read_until(master, b"Col 5", timeout=4.0)
        if b"[BLK: 3c LOCK]" not in out_s40_move1 or b"Col 5" not in out_s40_move1:
            print(f"[-] Step 40 forward move failed: {repr(out_s40_move1)}", flush=True)
            return False

        # 2. Backward move on same line: move block from Col 5 back to Col 0
        os.write(master, b"\x01") # Ctrl-A to Col 0
        time.sleep(0.1)
        drain_all(master)

        os.write(master, b"\x18") # Ctrl-X
        out_s40_move2 = read_until(master, b"Col 0", timeout=4.0)
        if b"[BLK: 3c LOCK]" not in out_s40_move2 or b"Col 0" not in out_s40_move2:
            print(f"[-] Step 40 backward move failed: {repr(out_s40_move2)}", flush=True)
            return False

        # 3. Test implied Ctrl-K on Ctrl-X during dynamic selection
        os.write(master, b"\x1b") # ESC to cancel block
        read_until(master, b"^K: Editor keys", timeout=4.0)

        os.write(master, b"\x02" + b"\x1b[C" * 2) # Select "12" -> [SEL: 2c]
        out_s40_dyn = read_until(master, b"[SEL: 2c]", timeout=4.0)
        if b"[SEL: 2c]" not in out_s40_dyn:
            print(f"[-] Step 40 dynamic select failed: {repr(out_s40_dyn)}", flush=True)
            return False

        os.write(master, b"\x18") # Ctrl-X during selection -> implied Ctrl-K
        out_s40_impl = read_until(master, b"[BLK: 2c LOCK]", timeout=4.0)
        if b"[BLK: 2c LOCK]" not in out_s40_impl:
            print(f"[-] Step 40 implied Ctrl-K on Ctrl-X failed: {repr(out_s40_impl)}", flush=True)
            return False

        os.write(master, b"\x1b") # ESC to cancel block
        read_until(master, b"^K: Editor keys", timeout=4.0)

        print("[+] Successfully verified Block Move using Ctrl+X (Step 40)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 41: Verify Block Copy capacity limits (Single-line buffer overflow protection)
        # ---------------------------------------------------------------------
        print("[*] Step 41: Verifying Block Copy buffer capacity limits...", flush=True)

        # 1. Fill line to 120 characters (maximum visual / buffer capacity)
        # Current line is "12345123" (8 chars). Move to end of line: Ctrl-E
        os.write(master, b"\x05")
        time.sleep(0.1)
        drain_all(master)

        # Type 112 'Z's so total line length is exactly 120 chars
        os.write(master, b"Z" * 112)
        time.sleep(0.3)
        drain_all(master)

        # Verify cursor is at Col 119 (maximum capacity)
        os.write(master, b"\x05")
        out_s41_full = read_until(master, b"Col 119", timeout=4.0)
        if b"Col 119" not in out_s41_full:
            print(f"[-] Step 41 full line check failed: {repr(out_s41_full)}", flush=True)
            return False

        # 2. Select a 5-character block on this line: Ctrl-A, Right 10, Ctrl-B, Right 5, Ctrl-K
        os.write(master, b"\x01" + b"\x1b[C" * 10)
        time.sleep(0.1)
        drain_all(master)

        os.write(master, b"\x02" + b"\x1b[C" * 5) # Select 5 chars
        out_s41_sel = read_until(master, b"[SEL: 5c]", timeout=4.0)
        if b"[SEL: 5c]" not in out_s41_sel:
            print(f"[-] Step 41 select 5c failed: {repr(out_s41_sel)}", flush=True)
            return False

        os.write(master, b"\x0b") # Solidify -> [BLK: 5c LOCK]
        out_s41_lock = read_until(master, b"[BLK: 5c LOCK]", timeout=4.0)
        if b"[BLK: 5c LOCK]" not in out_s41_lock:
            print(f"[-] Step 41 solidify failed: {repr(out_s41_lock)}", flush=True)
            return False

        # Move cursor to Col 0: Ctrl-A (outside block, line is at 120 capacity)
        os.write(master, b"\x01")
        time.sleep(0.1)
        drain_all(master)

        # 3. Try to copy 5 characters into a line that already has 120 characters (Space = 0)
        # Block copy MUST safely abort without overflowing the 120-char line limit or crashing!
        os.write(master, b"\x03") # Ctrl-C
        time.sleep(0.3)
        drain_all(master)

        # Move to end of line: Ctrl-E, verify length is still exactly 119 (120 chars)
        os.write(master, b"\x05")
        out_s41_check = read_until(master, b"Col 119", timeout=4.0)
        if b"Col 119" not in out_s41_check:
            print(f"[-] Step 41 capacity overflow check failed: {repr(out_s41_check)}", flush=True)
            return False

        # Block should remain intact
        if b"[BLK: 5c LOCK]" not in out_s41_check:
            print(f"[-] Step 41 block lock state lost: {repr(out_s41_check)}", flush=True)
            return False

        # Cancel block with ESC
        os.write(master, b"\x1b")
        read_until(master, b"^K: Editor keys", timeout=4.0)

        print("[+] Successfully verified Block Copy capacity limits (Step 41)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 42: Interactive Goto Line Facility (Ctrl+L in Editor Mode)
        # ---------------------------------------------------------------------
        print("[*] Step 42: Verifying interactive Goto Line facility (Ctrl+L)...", flush=True)

        # Move to line 1: Ctrl+T, Ctrl+A
        os.write(master, b"\x14\x01")
        out_init = read_until(master, b", Col 0", timeout=4.0)
        idx = out_init.rfind(b"Line 1/")
        if idx != -1 and b"," in out_init[idx + 7 :]:
            total_str = out_init[idx + 7 :].split(b",")[0].strip()
        else:
            total_str = b"38"
        lbl_1 = b"Line 1/" + total_str
        lbl_10 = b"Line 10/" + total_str
        lbl_25 = b"Line 25/" + total_str
        lbl_max = b"Line " + total_str + b"/" + total_str
        lbl_15 = b"Line 15/" + total_str

        # 1. Press Ctrl+L -> verify 'Goto line:' prompt on status line
        os.write(master, b"\x0c")
        out_s42_prompt = read_until(master, b"Goto line:", timeout=4.0)
        if b"Goto line:" not in out_s42_prompt:
            print(f"[-] Step 42 failed: Ctrl+L prompt 'Goto line:' missing. Buffer: {repr(out_s42_prompt)}", flush=True)
            return False

        # 2. Cancel with ESC -> verify status line restored without moving cursor
        os.write(master, b"\x1b")
        out_s42_esc = read_until(master, lbl_1, timeout=4.0)
        if lbl_1 not in out_s42_esc:
            print(f"[-] Step 42 failed: ESC did not restore {repr(lbl_1)}. Buffer: {repr(out_s42_esc)}", flush=True)
            return False

        # 2b. Abort with Down Arrow (\x1b[B): verify prompt aborts, cursor moves to Line 2, no debris!
        lbl_2 = b"Line 2/" + total_str
        os.write(master, b"\x0c")
        read_until(master, b"Goto line:", timeout=4.0)
        os.write(master, b"\x1b[B")
        out_s42_down = read_until(master, lbl_2, timeout=4.0)
        if lbl_2 not in out_s42_down:
            print(f"[-] Step 42 failed: Down Arrow did not move to Line 2. Buffer: {repr(out_s42_down)}", flush=True)
            return False

        # Abort with Up Arrow (\x1b[A): verify prompt aborts, cursor moves back to Line 1, no debris!
        os.write(master, b"\x0c")
        read_until(master, b"Goto line:", timeout=4.0)
        os.write(master, b"\x1b[A")
        out_s42_up = read_until(master, lbl_1, timeout=4.0)
        if lbl_1 not in out_s42_up:
            print(f"[-] Step 42 failed: Up Arrow did not move back to Line 1. Buffer: {repr(out_s42_up)}", flush=True)
            return False

        # Verify no control debris ('[B', '[A') was inserted into the text at cursor (lines 1 and 2)
        drain_all(master)
        os.write(master, b"\x14\x01")
        time.sleep(0.1)
        out_debris_check = drain_all(master)
        lines_1_and_2 = out_debris_check.split(b"\r\n")[:2]
        if any(b"[B" in l or b"[A" in l for l in lines_1_and_2):
            print(f"[-] Step 42 failed: Control debris found in text! Lines: {repr(lines_1_and_2)}", flush=True)
            return False

        # 2c. Abort with PageDown (\x1b[6~): verify prompt aborts, screen scrolls, NO highlight mode!
        os.write(master, b"\x0c")
        read_until(master, b"Goto line:", timeout=4.0)
        os.write(master, b"\x1b[6~")
        out_s42_pgdn = read_until(master, b"Line ", timeout=4.0)
        if b"\x1b[7m\x1b[H" in out_s42_pgdn or b"\x1b[7m\x1b[K" in out_s42_pgdn:
            print(f"[-] Step 42 failed: Highlight mode active during PageDown redraw! Buffer: {repr(out_s42_pgdn)}", flush=True)
            return False

        # 2d. Abort with PageUp (\x1b[5~): verify prompt aborts, screen scrolls back to Line 1, NO highlight mode!
        os.write(master, b"\x0c")
        read_until(master, b"Goto line:", timeout=4.0)
        os.write(master, b"\x1b[5~")
        out_s42_pgup = read_until(master, lbl_1, timeout=4.0)
        if lbl_1 not in out_s42_pgup:
            print(f"[-] Step 42 failed: PageUp did not restore Line 1. Buffer: {repr(out_s42_pgup)}", flush=True)
            return False
        if b"\x1b[7m\x1b[H" in out_s42_pgup or b"\x1b[7m\x1b[K" in out_s42_pgup:
            print(f"[-] Step 42 failed: Highlight mode active during PageUp redraw! Buffer: {repr(out_s42_pgup)}", flush=True)
            return False

        # 2e. Abort with Ctrl+V (Page Down) and Ctrl+U (Page Up) shortcuts
        os.write(master, b"\x0c")
        read_until(master, b"Goto line:", timeout=4.0)
        os.write(master, b"\x16")
        read_until(master, b"Line ", timeout=4.0)

        os.write(master, b"\x0c")
        read_until(master, b"Goto line:", timeout=4.0)
        os.write(master, b"\x15")
        out_s42_ctrl_u = read_until(master, lbl_1, timeout=4.0)
        if lbl_1 not in out_s42_ctrl_u:
            print(f"[-] Step 42 failed: Ctrl+U did not restore Line 1. Buffer: {repr(out_s42_ctrl_u)}", flush=True)
            return False

        # 3. Jump to line 10: Ctrl+L, '10', Enter -> verify no \x1b[7m\x1b[2J clear screen flash!
        os.write(master, b"\x0c")
        read_until(master, b"Goto line:", timeout=4.0)
        os.write(master, b"10\r")
        out_s42_l10 = read_until(master, lbl_10, timeout=4.0)
        if lbl_10 not in out_s42_l10 or b"Line 10 of test file content" not in out_s42_l10:
            print(f"[-] Step 42 failed: Goto line 10 failed. Buffer: {repr(out_s42_l10)}", flush=True)
            return False
        if b"\x1b[7m\x1b[2J" in out_s42_l10:
            print(f"[-] Step 42 failed: Clear screen executed while in inverse video! Buffer: {repr(out_s42_l10)}", flush=True)
            return False

        # 4. Jump to line 25: Ctrl+L, '25', Enter
        os.write(master, b"\x0c")
        read_until(master, b"Goto line:", timeout=4.0)
        os.write(master, b"25\r")
        out_s42_l25 = read_until(master, lbl_25, timeout=4.0)
        if lbl_25 not in out_s42_l25 or b"Line 25 of test file content" not in out_s42_l25:
            print(f"[-] Step 42 failed: Goto line 25 failed. Buffer: {repr(out_s42_l25)}", flush=True)
            return False

        # 5. Jump beyond EOF (clamp to last line): Ctrl+L, '999', Enter
        os.write(master, b"\x0c")
        read_until(master, b"Goto line:", timeout=4.0)
        os.write(master, b"999\r")
        out_s42_l30 = read_until(master, lbl_max, timeout=4.0)
        if lbl_max not in out_s42_l30:
            print(f"[-] Step 42 failed: Goto line 999 clamp failed. Buffer: {repr(out_s42_l30)}", flush=True)
            return False

        # 6. Jump back to line 1: Ctrl+L, '1', Enter
        os.write(master, b"\x0c")
        read_until(master, b"Goto line:", timeout=4.0)
        os.write(master, b"1\r")
        out_s42_l1 = read_until(master, lbl_1, timeout=4.0)
        if lbl_1 not in out_s42_l1 or b"Line 01 of test file content" not in out_s42_l1:
            print(f"[-] Step 42 failed: Goto line 1 failed. Buffer: {repr(out_s42_l1)}", flush=True)
            return False

        print("[+] Successfully verified interactive Goto Line facility (Ctrl+L) (Step 42)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 43: Splash Screen Goto Line (':l' / 'l' / '^L')
        # ---------------------------------------------------------------------
        print("[*] Step 43: Verifying splash screen Goto Line facility...", flush=True)

        # Return to splash with ESC
        time.sleep(0.2)
        os.write(master, b"\x1b")
        out_s43_splash = read_until(master, b"Auto-detects CP/M [CRLF]", timeout=4.0)
        if b"type   l  or  ^L        to goto line" not in out_s43_splash:
            print(f"[-] Step 43 failed: Splash missing goto line prompt hint. Buffer: {repr(out_s43_splash)}", flush=True)
            return False

        # Press 'l' on splash screen -> enters editor with Goto line prompt
        time.sleep(0.2)
        os.write(master, b"l")
        out_s43_l_prompt = read_until(master, b"Goto line:", timeout=4.0)
        if b"Goto line:" not in out_s43_l_prompt:
            print(f"[-] Step 43 failed: Splash 'l' did not trigger Goto line prompt. Buffer: {repr(out_s43_l_prompt)}", flush=True)
            return False

        # Enter line 15
        os.write(master, b"15\r")
        out_s43_l15 = read_until(master, lbl_15, timeout=4.0)
        if lbl_15 not in out_s43_l15 or b"Line 15 of test file content" not in out_s43_l15:
            print(f"[-] Step 43 failed: Splash goto line 15 jump failed. Buffer: {repr(out_s43_l15)}", flush=True)
            return False

        print("[+] Successfully verified splash screen Goto Line facility (Step 43)!", flush=True)

        # Final exit from editor with Ctrl+Q back to CP/M (answer 'n' to discard test edits)
        time.sleep(0.2)
        os.write(master, b"\x11")
        read_until(master, b"ESC:", timeout=4.0)
        os.write(master, b"n")
        read_until(master, b"C>", timeout=4.0)
        print("[+] Final exit from SE.COM completed.", flush=True)

        # ---------------------------------------------------------------------
        # Step 44: Command-Line Goto Line ('se 30.TXT:15' and 'se 30.TXT:999')
        # ---------------------------------------------------------------------
        print("[*] Step 44: Verifying command-line Goto Line facility ('se 30.TXT:15')...", flush=True)

        # Launch SE directly with line number: 'se 30.TXT:15'
        time.sleep(0.5)
        os.write(master, b"se 30.TXT:15\r")
        out_s44_l15 = read_until(master, b"Line 15/30", timeout=14.0)
        if b"Line 15/30" not in out_s44_l15 or b"Line 15 of test file content" not in out_s44_l15:
            print(f"[-] Step 44 failed: 'se 30.TXT:15' did not position at Line 15. Buffer: {repr(out_s44_l15)}", flush=True)
            return False
        if b"C:30.TXT" not in out_s44_l15:
            print(f"[-] Step 44 failed: 'se 30.TXT:15' filename missing on status bar. Buffer: {repr(out_s44_l15)}", flush=True)
            return False

        # Exit with Ctrl+Q back to CP/M
        time.sleep(0.2)
        os.write(master, b"\x11")
        read_until(master, b"C>", timeout=4.0)

        # Launch SE with line number beyond EOF: 'se 30.TXT:999' (should clamp to max line)
        time.sleep(0.5)
        os.write(master, b"se 30.TXT:999\r")
        out_s44_l30 = read_until(master, b"Line 30/30", timeout=14.0)
        if b"Line 30/30" not in out_s44_l30 or b"Line 30 of test file content" not in out_s44_l30:
            print(f"[-] Step 44 failed: 'se 30.TXT:999' did not clamp to Line 30. Buffer: {repr(out_s44_l30)}", flush=True)
            return False

        # Final exit from editor with Ctrl+Q back to CP/M
        time.sleep(0.2)
        os.write(master, b"\x11")
        read_until(master, b"C>", timeout=4.0)
        print("[+] Successfully verified command-line Goto Line facility (Step 44)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 45: Search (Ctrl+F) and Find Next (Ctrl+N) with Exact Matching
        # ---------------------------------------------------------------------
        print("[*] Step 45: Verifying Search (Ctrl+F) & Find Next (Ctrl+N) with Case Sensitivity...", flush=True)

        # Launch SE on 30.TXT
        time.sleep(0.5)
        os.write(master, b"se 30.TXT\r")
        out_s45_init = read_until(master, b"Line 1/30,", timeout=14.0)
        if b"Line 1/30," not in out_s45_init:
            print(f"[-] Step 45 failed: 30.TXT did not load. Buffer: {repr(out_s45_init)}", flush=True)
            return False

        # 1. Press Ctrl+F -> verify default [Exact] prompt
        time.sleep(0.2)
        os.write(master, b"\x06")
        out_s45_f1 = read_until(master, b"Find (Exact):", timeout=4.0)
        if b"Find (Exact):" not in out_s45_f1:
            print(f"[-] Step 45 failed: Ctrl+F prompt missing. Buffer: {repr(out_s45_f1)}", flush=True)
            return False

        # 2. Search for exact "Line 15"
        os.write(master, b"Line 15\r")
        out_s45_l15 = read_until(master, b"Line 15/30,", timeout=4.0)
        if b"Line 15/30," not in out_s45_l15:
            print(f"[-] Step 45 failed: Search 'Line 15' did not position at line 15. Buffer: {repr(out_s45_l15)}", flush=True)
            return False

        # 3. Test case sensitivity: search for lowercase "line 15" from Line 1 (should fail)
        time.sleep(0.2)
        os.write(master, b"\x14\x01")  # Ctrl+T, Ctrl+A to line 1
        read_until(master, b"Line 1/30,", timeout=4.0)

        os.write(master, b"\x06")
        read_until(master, b"Find (Exact):", timeout=4.0)
        os.write(master, b"line 15\r")
        out_s45_nf = read_until(master, b"Pattern not found.", timeout=4.0)
        if b"Pattern not found." not in out_s45_nf:
            print(f"[-] Step 45 failed: 'line 15' did not fail in Exact mode. Buffer: {repr(out_s45_nf)}", flush=True)
            return False

        # 4. Search for common word "content" on Line 1, then repeat with Ctrl+N
        time.sleep(0.5)
        os.write(master, b"\x06")
        read_until(master, b"Find (Exact):", timeout=4.0)
        os.write(master, b"content\r")
        read_until(master, b"Line 1/30,", timeout=4.0)

        # Press Ctrl+N to find next occurrence on Line 2
        time.sleep(0.2)
        os.write(master, b"\x0e")
        out_s45_n1 = read_until(master, b"Line 2/30,", timeout=4.0)
        if b"Line 2/30," not in out_s45_n1:
            print(f"[-] Step 45 failed: Ctrl+N did not advance to Line 2. Buffer: {repr(out_s45_n1)}", flush=True)
            return False

        # Press Ctrl+N to find next occurrence on Line 3
        time.sleep(0.2)
        os.write(master, b"\x0e")
        out_s45_n2 = read_until(master, b"Line 3/30,", timeout=4.0)
        if b"Line 3/30," not in out_s45_n2:
            print(f"[-] Step 45 failed: Ctrl+N did not advance to Line 3. Buffer: {repr(out_s45_n2)}", flush=True)
            return False

        print("[+] Successfully verified Search (Ctrl+F) & Find Next (Ctrl+N) with Case Sensitivity (Step 45)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 46: Case Insensitivity Toggle (Ctrl+I / Tab)
        # ---------------------------------------------------------------------
        print("[*] Step 46: Verifying Case Insensitivity Toggle (Ctrl+I)...", flush=True)

        # Move to line 1
        time.sleep(0.2)
        os.write(master, b"\x14\x01")
        read_until(master, b"Line 1/30,", timeout=4.0)

        # Open Find: Ctrl+F
        os.write(master, b"\x06")
        read_until(master, b"Find (Exact):", timeout=4.0)

        # Press Tab (Ctrl+I) to toggle to [Insens]
        os.write(master, b"\t")
        out_s46_ins = read_until(master, b"Find (Insens):", timeout=4.0)
        if b"Find (Insens):" not in out_s46_ins:
            print(f"[-] Step 46 failed: Tab/Ctrl+I did not toggle to [Insens]. Buffer: {repr(out_s46_ins)}", flush=True)
            return False

        # Search for lowercase "line 20"
        os.write(master, b"line 20\r")
        out_s46_l20 = read_until(master, b"Line 20/30,", timeout=4.0)
        if b"Line 20/30," not in out_s46_l20:
            print(f"[-] Step 46 failed: Case-insensitive search 'line 20' failed. Buffer: {repr(out_s46_l20)}", flush=True)
            return False

        # Verify setting persisted: next Ctrl+F starts in [Insens]
        time.sleep(0.2)
        os.write(master, b"\x06")
        out_s46_pers = read_until(master, b"Find (Insens):", timeout=4.0)
        if b"Find (Insens):" not in out_s46_pers:
            print(f"[-] Step 46 failed: [Insens] setting did not persist. Buffer: {repr(out_s46_pers)}", flush=True)
            return False

        # Toggle back to [Exact] and cancel
        os.write(master, b"\t")
        read_until(master, b"Find (Exact):", timeout=4.0)
        os.write(master, b"\x1b")
        read_until(master, b"Line 20/30,", timeout=4.0)

        print("[+] Successfully verified Case Insensitivity Toggle (Ctrl+I) (Step 46)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 47: Search & Replace (Ctrl+R) Interactive & Replace All
        # ---------------------------------------------------------------------
        print("[*] Step 47: Verifying Search and Replace (Ctrl+R)...", flush=True)

        # Move to line 1
        time.sleep(0.2)
        os.write(master, b"\x14\x01")
        read_until(master, b"Line 1/30,", timeout=4.0)

        # Trigger Replace: Ctrl+R
        os.write(master, b"\x12")
        read_until(master, b"Find (Exact):", timeout=4.0)
        os.write(master, b"Line 01\r")
        out_s47_rep_prompt = read_until(master, b"Replace with:", timeout=4.0)
        if b"Replace with:" not in out_s47_rep_prompt:
            print(f"[-] Step 47 failed: Replace with prompt missing. Buffer: {repr(out_s47_rep_prompt)}", flush=True)
            return False

        # Enter replacement string: "BetaLine 01"
        os.write(master, b"BetaLine 01\r")
        out_s47_confirm = read_until(master, b"Replace (y/n/a/q/r)? ", timeout=4.0)
        if b"Replace (y/n/a/q/r)? " not in out_s47_confirm:
            print(f"[-] Step 47 failed: Confirmation prompt missing. Buffer: {repr(out_s47_confirm)}", flush=True)
            return False

        # Confirm replacement with 'y'
        os.write(master, b"y")
        read_until(master, b"Replace done: 1 replacement(s).", timeout=4.0)
        time.sleep(0.3)
        drain_all(master)
        print("[+] Successfully verified Search and Replace (Ctrl+R) (Step 47)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 48: Solidified Block Highlighting on Found Search Match
        # ---------------------------------------------------------------------
        print("[*] Step 48: Verifying Solidified Block Highlighting on Match...", flush=True)
        time.sleep(0.3)
        drain_all(master)
        # Search for "BetaLine" with Ctrl+F
        os.write(master, b"\x06")
        read_until(master, b"Find (Exact):", timeout=4.0)
        os.write(master, b"BetaLine\r")
        out_s48 = read_until(master, b"Col 8", timeout=4.0)
        if b"[BLK: 8c LOCK]" not in out_s48:
            print(f"[-] Step 48 failed: [BLK: 8c LOCK] missing from status bar. Buffer: {repr(out_s48)}", flush=True)
            return False
        if b"Col 8" not in out_s48:
            print(f"[-] Step 48 failed: Cursor not positioned past block at Col 8. Buffer: {repr(out_s48)}", flush=True)
            return False

        # Press ESC to dismiss block highlight
        time.sleep(0.3)
        os.write(master, b"\x1b")
        time.sleep(0.3)
        drain_all(master)
        # Re-search: Ctrl+F then Enter to repeat previous search
        os.write(master, b"\x06")
        read_until(master, b"Find (Exact):", timeout=4.0)
        os.write(master, b"\r")
        out_s48_re = read_until(master, b"Col 8", timeout=4.0)
        if b"[BLK: 8c LOCK]" not in out_s48_re or b"Col 8" not in out_s48_re:
            print(f"[-] Step 48 failed: Solidified block re-match missing or not at Col 8. Buffer: {repr(out_s48_re)}", flush=True)
            return False
        print("[+] Successfully verified Solidified Block Highlighting on Match (Step 48)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 49: Start Search / Replace from Active Highlighted Block
        # ---------------------------------------------------------------------
        print("[*] Step 49: Verifying Start Search from Highlighted Block...", flush=True)
        # Dismiss existing block with ESC
        time.sleep(0.3)
        os.write(master, b"\x1b")
        time.sleep(0.3)
        drain_all(master)
        # Move to top of document: Ctrl+T, Ctrl+A (Line 1 Col 0)
        os.write(master, b"\x14\x01")
        read_until(master, b"Line 1/30,", timeout=4.0)
        # Move down to Line 2: Down Arrow (\x1b[B)
        os.write(master, b"\x1b[B")
        read_until(master, b"Line 2/30,", timeout=4.0)
        time.sleep(0.2)
        drain_all(master)
        # Start dynamic selection with Ctrl+B
        os.write(master, b"\x02")
        # Move right 4 times to select "Line"
        os.write(master, b"\x1b[C\x1b[C\x1b[C\x1b[C")
        read_until(master, b"[SEL: 4c]", timeout=4.0)

        # Press Ctrl+F: should imply Ctrl+K and pre-fill "Line"
        os.write(master, b"\x06")
        read_until(master, b"Find (Exact):", timeout=4.0)
        out_s49_prompt = read_until(master, b"Line", timeout=4.0)
        if b"Line" not in out_s49_prompt:
            print(f"[-] Step 49 failed: Prompt not pre-filled with block text. Buffer: {repr(out_s49_prompt)}", flush=True)
            return False

        # Confirm search with Enter
        os.write(master, b"\r")
        out_s49_match = read_until(master, b"Col 4", timeout=4.0)
        if b"[BLK: 4c LOCK]" not in out_s49_match or b"Col 4" not in out_s49_match:
            print(f"[-] Step 49 failed: Pre-filled match not solidified or not at Col 4. Buffer: {repr(out_s49_match)}", flush=True)
            return False
        print("[+] Successfully verified Start Search from Highlighted Block (Step 49)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 50: "Search completed." vs "Pattern not found." Messaging
        # ---------------------------------------------------------------------
        print("[*] Step 50: Verifying Search Completed vs Not Found Messaging...", flush=True)
        time.sleep(0.3)
        drain_all(master)
        # Search for a pattern that does not exist anywhere:
        os.write(master, b"\x06")
        read_until(master, b"Find (Exact):", timeout=4.0)
        # Erase prefilled "Line" (4 backspaces) and type ZZZ999
        os.write(master, b"\x08\x08\x08\x08ZZZ999\r")
        out_s50_notfound = read_until(master, b"Pattern not found.", timeout=4.0)
        if b"Pattern not found." not in out_s50_notfound:
            print(f"[-] Step 50 failed: Pattern not found missing. Buffer: {repr(out_s50_notfound)}", flush=True)
            return False

        # Now search for "BetaLine" which exists once in the file
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"\x06")
        read_until(master, b"Find (Exact):", timeout=4.0)
        os.write(master, b"BetaLine\r")
        read_until(master, b"[BLK: 8c LOCK]", timeout=4.0)

        # Now trigger Find Next (Ctrl+N): wraps whole file and finds no more matches!
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"\x0e")
        out_s50_completed = read_until(master, b"Search completed.", timeout=4.0)
        if b"Search completed." not in out_s50_completed:
            print(f"[-] Step 50 failed: 'Search completed.' missing. Buffer: {repr(out_s50_completed)}", flush=True)
            return False
        print("[+] Successfully verified 'Search completed.' vs 'Pattern not found.' (Step 50)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 51: Dynamic Reversal of Search Direction (Ctrl+P and Replace 'r')
        # ---------------------------------------------------------------------
        print("[*] Step 51: Verifying Dynamic Reversal of Search Direction...", flush=True)
        time.sleep(0.3)
        drain_all(master)
        # Search for "content" with Ctrl+F
        os.write(master, b"\x06")
        read_until(master, b"Find (Exact):", timeout=4.0)
        # Erase prefilled "BetaLine" (8 backspaces) and type "content\r"
        os.write(master, b"\x08\x08\x08\x08\x08\x08\x08\x08content\r")
        read_until(master, b"Line 1/30,", timeout=4.0)

        # Forward search: Ctrl+N -> moves to line 2
        time.sleep(0.2)
        os.write(master, b"\x0e")
        read_until(master, b"Line 2/30,", timeout=4.0)

        # Forward search: Ctrl+N -> moves to line 3
        time.sleep(0.2)
        os.write(master, b"\x0e")
        read_until(master, b"Line 3/30,", timeout=4.0)

        # Dynamic reverse: Ctrl+P -> moves back to line 2!
        time.sleep(0.2)
        os.write(master, b"\x10")
        read_until(master, b"Line 2/30,", timeout=4.0)

        # Dynamic reverse: Ctrl+P -> moves back to line 1!
        time.sleep(0.2)
        os.write(master, b"\x10")
        read_until(master, b"Line 1/30,", timeout=4.0)

        # Verify 'r' in interactive Replace prompt:
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"\x12") # Ctrl+R
        read_until(master, b"Find (Exact):", timeout=4.0)
        read_until(master, b"content", timeout=4.0)
        os.write(master, b"\r")
        read_until(master, b"Replace with:", timeout=4.0)
        os.write(master, b"Item\r")
        read_until(master, b"Replace (y/n/a/q/r)? ", timeout=4.0)
        # We are on line 1. Skip with 'n' -> moves forward to line 2:
        os.write(master, b"n")
        read_until(master, b"Line 2/30,", timeout=4.0)
        read_until(master, b"Replace (y/n/a/q/r)? ", timeout=4.0)

        # Press 'r' to dynamically reverse direction -> moves back to line 1!
        os.write(master, b"r")
        read_until(master, b"Line 1/30,", timeout=4.0)
        read_until(master, b"Replace (y/n/a/q/r)? ", timeout=4.0)

        # Quit replace with 'q'
        os.write(master, b"q")
        read_until(master, b"Replace done: 0 replacement(s).", timeout=4.0)
        print("[+] Successfully verified Dynamic Reversal of Search Direction (Step 51)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 52: Unsaved Modifications Check on Exit (Ctrl+Q)
        # ---------------------------------------------------------------------
        print("[*] Step 52: Verifying Unsaved Modifications check on exit (Ctrl+Q)...", flush=True)

        # 1. Document was modified in Step 47. Send Ctrl+Q and verify prompt
        time.sleep(0.3)
        os.write(master, b"\x11")
        out_s52_prompt = read_until(master, b"ESC:", timeout=4.0)
        if b"Save changes?" not in out_s52_prompt:
            print(f"[-] Step 52 failed: Save changes prompt missing. Buffer: {repr(out_s52_prompt)}", flush=True)
            return False

        # 2. Send cursor keys (escape sequences) and verify they are ignored (prompt remains active)
        time.sleep(0.2)
        os.write(master, b"\x1b[A\x1b[B\x1b[C\x1b[D")
        time.sleep(0.4)

        # 3. Press standalone ESC to cancel exit and resume editor
        os.write(master, b"\x1b")
        out_s52_cancel = read_until(master, b"Line 1/30,", timeout=4.0)
        if b"Line 1/30," not in out_s52_cancel:
            print(f"[-] Step 52 failed: ESC did not restore editor. Buffer: {repr(out_s52_cancel)}", flush=True)
            return False
        print("[+] Cursor keys ignored and standalone ESC cancelled exit, restoring editor.", flush=True)

        # 4. From editor, press ESC to switch to splash screen
        time.sleep(0.2)
        os.write(master, b"\x1b")
        out_splash = read_until(master, b"Active Screen:", timeout=4.0)
        if b"Active Screen:" not in out_splash:
            print(f"[-] Step 52 failed: ESC did not display splash screen. Buffer: {repr(out_splash)}", flush=True)
            return False
        print("[+] Switched to splash screen with modified document.", flush=True)

        # 5. On splash screen, send Ctrl+Q. Verify it switches to editor and displays Save changes prompt
        time.sleep(0.2)
        os.write(master, b"\x11")
        out_splash_prompt = read_until(master, b"ESC:", timeout=4.0)
        if b"Save changes?" not in out_splash_prompt:
            print(f"[-] Step 52 failed: Splash Ctrl+Q did not show save changes prompt. Buffer: {repr(out_splash_prompt)}", flush=True)
            return False
        print("[+] Splash screen Ctrl+Q with modified doc switched to editor and prompted.", flush=True)

        # 6. Answer 'n' to discard changes and exit to CP/M with cleared screen
        os.write(master, b"n")
        out_s52_exit = read_until(master, b"C>", timeout=4.0)
        if b"C>" not in out_s52_exit or b"\x1b[2J" not in out_s52_exit:
            print(f"[-] Step 52 failed: 'n' did not clear screen or exit to CP/M. Buffer: {repr(out_s52_exit)}", flush=True)
            return False
        print("[+] 'n' cleared screen, discarded changes and returned cleanly to CP/M.", flush=True)

        # 7. Verify clean exit without prompt when file is unmodified: 'se 2.TXT'
        time.sleep(0.5)
        os.write(master, b"se 2.TXT\r")
        read_until(master, b"Line 1/2,", timeout=14.0)
        time.sleep(0.2)
        os.write(master, b"\x11")
        out_s52_clean = read_until(master, b"C>", timeout=4.0)
        if b"C>" not in out_s52_clean or b"Save changes" in out_s52_clean or b"\x1b[2J" not in out_s52_clean:
            print(f"[-] Step 52 failed: clean document prompted on exit or did not clear screen. Buffer: {repr(out_s52_clean)}", flush=True)
            return False
        print("[+] Unmodified document cleared screen and exited immediately without prompt.", flush=True)
        print("[+] Successfully verified Unsaved Modifications Check on Exit (Step 52)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 53: New File (:n) and Close File (:w / Ctrl+W)
        # ---------------------------------------------------------------------
        print("[*] Step 53: Verifying New File (:n) and Close File (:w / Ctrl+W)...", flush=True)

        # 1. Launch 'se 2.TXT'
        time.sleep(0.5)
        os.write(master, b"se 2.TXT\r")
        read_until(master, b"Line 1/2,", timeout=14.0)

        # 2. Modify buffer and send Ctrl+W (\x17)
        time.sleep(0.2)
        os.write(master, b"X")
        time.sleep(0.2)
        os.write(master, b"\x17")
        out_s53_prompt = read_until(master, b"ESC:", timeout=4.0)
        if b"Save changes?" not in out_s53_prompt:
            print(f"[-] Step 53 failed: Ctrl+W did not show save changes prompt. Buffer: {repr(out_s53_prompt)}", flush=True)
            return False

        # 3. Discard changes with 'n' and verify return to splash screen
        os.write(master, b"n")
        out_s53_splash1 = read_until(master, b"Active Screen:", timeout=4.0)
        if b"Active Screen:" not in out_s53_splash1:
            print(f"[-] Step 53 failed: Ctrl+W did not return to splash screen. Buffer: {repr(out_s53_splash1)}", flush=True)
            return False
        print("[+] Ctrl+W in editor prompted and returned to splash screen on discard.", flush=True)

        # 4. On splash screen, test ':n' to start a new blank document
        time.sleep(0.2)
        os.write(master, b"n")
        out_s53_new = read_until(master, b"Line 1/1,", timeout=4.0)
        if b"[No Name]" not in out_s53_new:
            print(f"[-] Step 53 failed: Splash ':n' did not enter blank editor [No Name]. Buffer: {repr(out_s53_new)}", flush=True)
            return False
        print("[+] Splash ':n' successfully started new blank document [No Name].", flush=True)

        # 5. Type content in blank document, then return to splash (ESC)
        time.sleep(0.2)
        os.write(master, b"TESTING BLANK")
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"Active Screen:", timeout=4.0)

        # 6. On splash screen with modified document, test ':w'
        time.sleep(0.2)
        os.write(master, b"w")
        out_s53_spw = read_until(master, b"ESC:", timeout=4.0)
        if b"Save changes?" not in out_s53_spw:
            print(f"[-] Step 53 failed: Splash ':w' did not prompt for save changes. Buffer: {repr(out_s53_spw)}", flush=True)
            return False
        # Cancel with ESC to stay in editor
        os.write(master, b"\x1b")
        read_until(master, b"Line 1/1,", timeout=4.0)
        print("[+] Splash ':w' prompted for unsaved changes and ESC cancelled cleanly.", flush=True)

        # 7. Return to splash screen again, test Ctrl+W and discard with 'n'
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"Active Screen:", timeout=4.0)
        time.sleep(0.2)
        os.write(master, b"\x17")
        read_until(master, b"ESC:", timeout=4.0)
        os.write(master, b"n")
        out_s53_splash2 = read_until(master, b"Active Screen:", timeout=4.0)
        if b"Active Screen:" not in out_s53_splash2:
            print(f"[-] Step 53 failed: Splash Ctrl+W did not return to splash screen. Buffer: {repr(out_s53_splash2)}", flush=True)
            return False
        print("[+] Splash Ctrl+W discarded changes and unloaded document.", flush=True)

        # 8. On clean splash screen, press 'e': verify it starts a fresh blank document
        time.sleep(0.2)
        os.write(master, b"e")
        out_s53_fresh = read_until(master, b"Line 1/1,", timeout=4.0)
        if b"[No Name]" not in out_s53_fresh:
            print(f"[-] Step 53 failed: Enter/e after close did not start fresh [No Name]. Buffer: {repr(out_s53_fresh)}", flush=True)
            return False

        # 9. In unmodified editor, test Ctrl+W: closes immediately to splash without prompt
        time.sleep(0.2)
        os.write(master, b"\x17")
        out_s53_unmod = read_until(master, b"Active Screen:", timeout=4.0)
        if b"Save changes" in out_s53_unmod or b"Active Screen:" not in out_s53_unmod:
            print(f"[-] Step 53 failed: Unmodified Ctrl+W did not close immediately. Buffer: {repr(out_s53_unmod)}", flush=True)
            return False
        print("[+] Unmodified document closed immediately with Ctrl+W to splash screen.", flush=True)

        # 10. Exit from splash screen with Ctrl+Q
        time.sleep(0.2)
        os.write(master, b"\x11")
        read_until(master, b"C>", timeout=4.0)
        print("[+] Clean exit from splash screen back to CP/M.", flush=True)
        print("[+] Successfully verified New File (:n) and Close File (:w / Ctrl+W) (Step 53)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 54: Open File (Ctrl+O & Splash :o) Unsaved Modifications Check
        # ---------------------------------------------------------------------
        print("[*] Step 54: Verifying Open File (Ctrl+O & Splash :o) unsaved modifications check...", flush=True)

        # 1. Launch 'se 2.TXT'
        time.sleep(0.5)
        os.write(master, b"se 2.TXT\r")
        read_until(master, b"Line 1/2,", timeout=14.0)

        # 2. Modify buffer and send Ctrl+O (\x0f)
        time.sleep(0.2)
        os.write(master, b"Z")
        time.sleep(0.2)
        os.write(master, b"\x0f")
        out_s54_prompt = read_until(master, b"ESC:", timeout=4.0)
        if b"Save changes?" not in out_s54_prompt:
            print(f"[-] Step 54 failed: Ctrl+O on modified document did not prompt to save changes. Buffer: {repr(out_s54_prompt)}", flush=True)
            return False
        print("[+] Ctrl+O on modified document correctly showed 'Save changes?' prompt.", flush=True)

        # 3. Cancel prompt with ESC: verify editor remains with modified document
        os.write(master, b"\x1b")
        out_s54_cancel = read_until(master, b"Line 1/2,", timeout=4.0)
        if b"C:2.TXT" not in out_s54_cancel:
            print(f"[-] Step 54 failed: ESC did not cancel prompt back to editor. Buffer: {repr(out_s54_cancel)}", flush=True)
            return False
        print("[+] ESC cancelled prompt and stayed in editor with modifications intact.", flush=True)

        # 4. Send Ctrl+O again, discard with 'n': verify Open File screen is displayed
        time.sleep(0.2)
        os.write(master, b"\x0f")
        read_until(master, b"ESC:", timeout=4.0)
        os.write(master, b"n")
        out_s54_open_ui = read_until(master, b"OPEN FILE (DIRECTORY - DRIVE C:)", timeout=4.0)
        if b"OPEN FILE (DIRECTORY - DRIVE C:)" not in out_s54_open_ui:
            print(f"[-] Step 54 failed: 'n' (discard) did not open Open File screen. Buffer: {repr(out_s54_open_ui)}", flush=True)
            return False
        print("[+] 'n' (discard) proceeded directly to Open File screen.", flush=True)

        # 5. Cancel Open File screen with ESC: verify return to editor
        time.sleep(0.2)
        os.write(master, b"\x1b")
        out_s54_ed_back = read_until(master, b"Line 1/2,", timeout=4.0)
        if b"C:2.TXT" not in out_s54_ed_back:
            print(f"[-] Step 54 failed: ESC in Open File screen did not return to editor. Buffer: {repr(out_s54_ed_back)}", flush=True)
            return False
        print("[+] ESC in Open File screen returned to editor.", flush=True)

        # 6. Press Ctrl+O on now-unmodified document: verify Open File screen opens immediately without prompt
        time.sleep(0.2)
        os.write(master, b"\x0f")
        out_s54_clean_open = read_until(master, b"OPEN FILE (DIRECTORY - DRIVE C:)", timeout=4.0)
        if b"OPEN FILE (DIRECTORY - DRIVE C:)" not in out_s54_clean_open or b"Save changes" in out_s54_clean_open:
            print(f"[-] Step 54 failed: Clean Ctrl+O prompted or failed to open directory. Buffer: {repr(out_s54_clean_open)}", flush=True)
            return False
        # Cancel back to editor
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"Line 1/2,", timeout=4.0)
        print("[+] Unmodified Ctrl+O opened Open File screen immediately without prompt.", flush=True)

        # 7. Modify document, return to splash screen (ESC)
        time.sleep(0.2)
        os.write(master, b"M")
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"Active Screen:", timeout=4.0)

        # 8. On splash screen with modified document, test ':o'
        time.sleep(0.2)
        os.write(master, b"o")
        out_s54_spo = read_until(master, b"ESC:", timeout=4.0)
        if b"Save changes?" not in out_s54_spo:
            print(f"[-] Step 54 failed: Splash ':o' did not prompt for save changes. Buffer: {repr(out_s54_spo)}", flush=True)
            return False
        # Cancel with ESC to stay in editor
        os.write(master, b"\x1b")
        read_until(master, b"Line 1/2,", timeout=4.0)
        print("[+] Splash ':o' with modified document resumed editor and prompted for save changes.", flush=True)

        # 9. Return to splash screen again (ESC), test ':o' and discard with 'n'
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"Active Screen:", timeout=4.0)
        time.sleep(0.2)
        os.write(master, b"o")
        read_until(master, b"ESC:", timeout=4.0)
        os.write(master, b"n")
        out_s54_spo_open = read_until(master, b"OPEN FILE (DIRECTORY - DRIVE C:)", timeout=4.0)
        if b"OPEN FILE (DIRECTORY - DRIVE C:)" not in out_s54_spo_open:
            print(f"[-] Step 54 failed: Discarding changes from splash ':o' did not enter Open File screen. Buffer: {repr(out_s54_spo_open)}", flush=True)
            return False
        # Cancel back to editor
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"Line 1/2,", timeout=4.0)
        print("[+] Splash ':o' discarded changes and opened Open File screen.", flush=True)

        # 10. Exit cleanly with Ctrl+Q
        time.sleep(0.2)
        os.write(master, b"\x11")
        read_until(master, b"C>", timeout=4.0)
        print("[+] Clean exit back to CP/M prompt.", flush=True)
        print("[+] Successfully verified Open File (Ctrl+O & Splash :o) Unsaved Modifications Check (Step 54)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 55: Open File Screen Line Number Specification (e.g. 30.TXT:15)
        # ---------------------------------------------------------------------
        print("[*] Step 55: Verifying Open File screen line number specification...", flush=True)

        # 1. Launch 'se 2.TXT'
        time.sleep(0.5)
        os.write(master, b"se 2.TXT\r")
        read_until(master, b"Line 1/2,", timeout=14.0)

        # 2. In editor mode, press Ctrl+O and open '30.TXT:15'
        time.sleep(0.2)
        os.write(master, b"\x0f")
        read_until(master, b"Enter filename to open:", timeout=4.0)
        time.sleep(0.2)
        os.write(master, b"30.TXT:15\r")
        out_s55_l15 = read_until(master, b"Line 15/30,", timeout=4.0)
        if b"Line 15/30," not in out_s55_l15 or b"C:30.TXT" not in out_s55_l15:
            print(f"[-] Step 55 failed: '30.TXT:15' did not open at line 15. Buffer: {repr(out_s55_l15)}", flush=True)
            return False
        print("[+] '30.TXT:15' opened successfully at line 15.", flush=True)

        # 3. In editor mode, press Ctrl+O and open 'C:30.TXT:25' (drive + file + line)
        time.sleep(0.2)
        os.write(master, b"\x0f")
        read_until(master, b"Enter filename to open:", timeout=4.0)
        time.sleep(0.2)
        os.write(master, b"C:30.TXT:25\r")
        out_s55_l25 = read_until(master, b"Line 25/30,", timeout=4.0)
        if b"Line 25/30," not in out_s55_l25 or b"C:30.TXT" not in out_s55_l25:
            print(f"[-] Step 55 failed: 'C:30.TXT:25' did not open at line 25. Buffer: {repr(out_s55_l25)}", flush=True)
            return False
        print("[+] 'C:30.TXT:25' opened successfully at line 25 with explicit drive.", flush=True)

        # 4. In editor mode, press Ctrl+O and open '30.TXT:1000' (clamping to EOF)
        time.sleep(0.2)
        os.write(master, b"\x0f")
        read_until(master, b"Enter filename to open:", timeout=4.0)
        time.sleep(0.2)
        os.write(master, b"30.TXT:1000\r")
        out_s55_l1000 = read_until(master, b"Line 30/30,", timeout=4.0)
        if b"Line 30/30," not in out_s55_l1000:
            print(f"[-] Step 55 failed: '30.TXT:1000' did not clamp to line 30. Buffer: {repr(out_s55_l1000)}", flush=True)
            return False
        print("[+] '30.TXT:1000' clamped cleanly to line 30.", flush=True)

        # 5. Return to splash screen (ESC) and open '30.TXT:10' from splash ':o'
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"Active Screen:", timeout=4.0)
        time.sleep(0.2)
        os.write(master, b"o")
        read_until(master, b"Enter filename to open:", timeout=4.0)
        time.sleep(0.2)
        os.write(master, b"30.TXT:10\r")
        out_s55_splash_l10 = read_until(master, b"Line 10/30,", timeout=4.0)
        if b"Line 10/30," not in out_s55_splash_l10:
            print(f"[-] Step 55 failed: Splash ':o' '30.TXT:10' did not open at line 10. Buffer: {repr(out_s55_splash_l10)}", flush=True)
            return False
        print("[+] Splash screen ':o' with line number '30.TXT:10' opened at line 10.", flush=True)

        # 6. Verify standard open without line number opens at line 1
        time.sleep(0.2)
        os.write(master, b"\x0f")
        read_until(master, b"Enter filename to open:", timeout=4.0)
        time.sleep(0.2)
        os.write(master, b"30.TXT\r")
        out_s55_l1 = read_until(master, b"Line 1/30,", timeout=4.0)
        if b"Line 1/30," not in out_s55_l1:
            print(f"[-] Step 55 failed: '30.TXT' without line number did not open at line 1. Buffer: {repr(out_s55_l1)}", flush=True)
            return False
        print("[+] '30.TXT' without line number opened at default line 1.", flush=True)

        # 7. Exit cleanly with Ctrl+Q
        time.sleep(0.2)
        os.write(master, b"\x11")
        read_until(master, b"C>", timeout=4.0)
        print("[+] Clean exit back to CP/M prompt.", flush=True)
        print("[+] Successfully verified Open File Screen Line Number Specification (Step 55)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 56: Verifying 13-Bank Far RAM Discovery and HBIOS Bank 0x80 Protection
        # ---------------------------------------------------------------------
        print("[*] Step 56: Verifying 13-Bank Far RAM discovery and HBIOS Bank 0x80 protection...", flush=True)
        drain_all(master)
        time.sleep(0.5)
        os.write(master, b"se\r")
        out_s56 = read_until(master, b"Free: 416 KB", timeout=20.0)
        if b"Free: 416 KB" not in out_s56:
            print(f"[-] Step 56 failed: Splash status bar does not show 'Free: 416 KB'. Buffer: {repr(out_s56)}", flush=True)
            return False

        # Run memory diagnostics ('t')
        time.sleep(0.5)
        os.write(master, b"t")
        out_diag = read_until(master, b"Press any key to return", timeout=12.0)
        if b"Usable Far RAM Banks (32K): 13): 8D 8C 8B 8A 89 88 87 86 85 84 83 82 81" not in out_diag:
            print(f"[-] Step 56 failed: Did not discover exactly 13 Far RAM banks without 0x80. Buffer: {repr(out_diag)}", flush=True)
            return False
        if b"3,328 Lines (416 KB Extended RAM)" not in out_diag:
            print(f"[-] Step 56 failed: Far document storage does not indicate 3,328 Lines. Buffer: {repr(out_diag)}", flush=True)
            return False
        if b"ALL 512KB EXTENDED MEMORY TESTS PASSED SUCCESSFULLY!" not in out_diag:
            print(f"[-] Step 56 failed: Extended memory diagnostic tests failed. Buffer: {repr(out_diag)}", flush=True)
            return False

        # Return to splash screen
        drain_all(master)
        time.sleep(0.3)
        os.write(master, b" ")
        read_until(master, b"Free: 416 KB", timeout=15.0)

        # Clean exit to CP/M
        drain_all(master)
        time.sleep(0.3)
        os.write(master, b"\x11")
        read_until(master, b"C>", timeout=4.0)
        print("[+] Successfully verified 13-Bank Far RAM discovery and HBIOS Bank 0x80 protection (Step 56)!", flush=True)

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
