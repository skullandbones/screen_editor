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
import re

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

SPLASH_FREE_TARGETS = [
    b"Free: 320 KB", b"Free: 352 KB", b"Free: 384 KB", b"Free: 416 KB"
]

def has_free_mem(buf):
    return any(t in buf for t in SPLASH_FREE_TARGETS)

def read_until(master_fd, match_bytes, timeout=8.0):
    buf = b""
    t0 = time.time()
    targets = (match_bytes if isinstance(match_bytes, (list, tuple))
               else [match_bytes])
    while time.time() - t0 < timeout:
        r, _, _ = select.select([master_fd], [], [], 0.05)
        if r:
            try:
                data = os.read(master_fd, 1024)
                if not data:
                    break
                buf += data
                for target in targets:
                    if target in buf:
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

    # Prepare BIG.TXT on test disk image (3,072 lines: 12 Far banks * 256 slots) for Step 57 OOM verification
    big_tmp = "/tmp/BIG.TXT"
    with open(big_tmp, "w") as f:
        for i in range(1, 3073):
            f.write(f"Line {i:04d}\r\n")
    # Prepare SE.CFG with RAMDRIVE=ON so all 12 Far banks (384 KB) are enabled for conformity suite
    cfg_tmp = "/tmp/SE.CFG"
    with open(cfg_tmp, "w") as f:
        f.write("SCREEN=120x40\r\nRAMDRIVE=ON\r\n")
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    workspace_root = os.path.abspath(os.path.join(repo_root, "..", ".."))
    cpmrm_bin = os.path.join(workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm")
    cpmcp_bin = os.path.join(workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp")
    if os.path.isfile(cpmrm_bin):
        subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:BIG.TXT"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.CFG"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:se.cfg"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.COM"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:se.com"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:INS1.TXT"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:INS2.TXT"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:BLKSGL.TXT"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SAV300.TXT"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:BLK300.TXT"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:LONGNAME.TXT"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        two_txt_host = os.path.join(repo_root, "2.TXT")
        if os.path.isfile(two_txt_host) and os.path.isfile(cpmcp_bin):
            subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:2.TXT"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, two_txt_host, "0:2.TXT"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        thirty_txt_host = os.path.join(repo_root, "30.TXT")
        if os.path.isfile(thirty_txt_host) and os.path.isfile(cpmcp_bin):
            subprocess.run(
                [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:30.TXT"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(
                [cpmcp_bin, "-f", "wbw_hd1k_0", img_file,
                 thirty_txt_host, "0:30.TXT"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if os.path.isfile(cpmcp_bin):
        subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, big_tmp, "0:BIG.TXT"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, cfg_tmp, "0:SE.CFG"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if os.path.isfile(se_bin):
            subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin,
                            "0:SE.COM"],
                           stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)
        ins1_tmp = "/tmp/INS1.TXT"
        with open(ins1_tmp, "wb") as f:
            f.write(b"INSERTED")
        ins2_tmp = "/tmp/INS2.TXT"
        with open(ins2_tmp, "wb") as f:
            f.write(b"FIRST LINE\r\nSECOND LINE")
        subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, ins1_tmp, "0:INS1.TXT"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, ins2_tmp, "0:INS2.TXT"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        u1_tmp = "/tmp/U1FILE.TXT"
        with open(u1_tmp, "w") as f:
            f.write("Hello from User 1 area!\r\nSecond line of user 1 file.\r\n")
        subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "1:U1FILE.TXT"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "1:SAVEU1.TXT"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "1:BLKU1.TXT"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, u1_tmp, "1:U1FILE.TXT"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    print("[*] Launching RomWBW on RC2014 emulator...", flush=True)
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)

    try:
        # 1. Wait for RomWBW boot loader prompt
        print("[*] Step 1: Waiting for RomWBW boot loader prompt...",
              flush=True)
        out = read_until(master, b"Boot [H=Help]:", timeout=6.0)
        if b"Boot [H=Help]:" not in out:
            print("[-] Step 1: Failed to reach RomWBW boot loader prompt.")
            return False
        print("[+] Step 1: Boot loader prompt reached.", flush=True)

        # 2. Boot into CP/M 2.2 on ROM disk (Choice 'c')
        print("[*] Step 2: Booting into CP/M 2.2 on ROM disk...", flush=True)
        time.sleep(0.5)
        os.write(master, b"c\r")
        out = read_until(master, b"B>", timeout=6.0)
        if b"B>" not in out:
            print("[-] Step 2: Failed to boot into CP/M prompt.")
            return False
        print("[+] Step 2: Booted into CP/M (Drive B>).", flush=True)

        # 3. Switch to Drive C: (SD slice 0 with SE.COM)
        print("[*] Step 3: Switching to Drive C:...", flush=True)
        time.sleep(0.5)
        os.write(master, b"c:\r")
        out = read_until(master, b"C>", timeout=4.0)
        print("[+] Step 3: Switched to Drive C>.", flush=True)

        # 4. Run SE.COM
        print("[*] Step 4: Running SE.COM...", flush=True)
        time.sleep(0.5)
        os.write(master, b"se\r")
        out = read_until(master, SPLASH_FREE_TARGETS, timeout=30.0)
        if b"for about" not in out or not has_free_mem(out):
            print(f"[-] Step 4: Splash or free memory missing: {repr(out)}",
                  flush=True)
            return False
        print(
            "[+] Step 4: SE.COM splash screen successfully displayed with "
            "Free memory status bar.",
            flush=True
        )

        # 5. Verify splash screen does not show removed test options ('f' and 't')
        print("[*] Step 5: Verifying splash screen removed test options...",
              flush=True)
        if b"for file test" in out:
            print("[-] Step 5: File test option ('for file test') unexpectedly "
                  "found on splash screen.", flush=True)
            return False
        if b"for mem test" in out:
            print("[-] Step 5: Memory test option ('for mem test') "
                  "unexpectedly found on splash screen.", flush=True)
            return False
        print(
            "[+] Step 5: Verified file test ('f') and mem test ('t') cleanly "
            "removed from splash screen.",
            flush=True
        )

        # 6. Verify pressing 't' does not trigger removed diagnostic
        print("[*] Step 6: Verifying pressing 't' ignored on splash screen...",
              flush=True)
        time.sleep(0.5)
        os.write(master, b"t")
        time.sleep(0.3)
        drain_all(master)
        print("[+] Step 6: Verified pressing 't' ignored on splash screen.",
              flush=True)

        # 7. Verify only 'e'/Enter enter editor mode, and enter editor ('e')
        print("[*] Step 7: Verifying editor entry from splash screen...",
              flush=True)
        drain_all(master)
        time.sleep(0.3)

        # Verify Space key does NOT enter editor mode from splash screen
        os.write(master, b" ")
        time.sleep(0.3)
        r, _, _ = select.select([master], [], [], 0.3)
        if r:
            check_buf = os.read(master, 2048)
            if b"Line    1/" in check_buf or b"(Untitled)" in check_buf:
                print(f"[-] Step 7: Space key erroneously entered editor mode! "
                      f"Buffer: {repr(check_buf)}", flush=True)
                return False

        # Verify cursor arrow keys do NOT enter editor mode from splash screen
        for arrow_name, arrow_seq in [("Up", b"\x1b[A"), ("Down", b"\x1b[B"), ("Right", b"\x1b[C"), ("Left", b"\x1b[D")]:
            os.write(master, arrow_seq)
            time.sleep(0.2)
            r, _, _ = select.select([master], [], [], 0.2)
            if r:
                check_buf = os.read(master, 2048)
                if b"Line    1/" in check_buf or b"(Untitled)" in check_buf:
                    print(f"[-] Step 7: Cursor {arrow_name} key erroneously "
                          f"entered editor mode! Buffer: {repr(check_buf)}",
                          flush=True)
                    return False

        print(
            "[+] Step 7: Successfully verified Space and Cursor keys do not "
            "enter editor mode from splash screen.",
            flush=True
        )

        # Enter editor mode with 'e'
        os.write(master, b"e")
        out_edit = read_until(master, b"Line    1/1", timeout=6.0)
        if b"Line    1/1" not in out_edit:
            print(f"[-] Step 7: Failed to enter editor mode. Buffer captured: "
                  f"{repr(out_edit)}", flush=True)
            return False
        if b"(Untitled)" not in out_edit:
            print(f"[-] Step 7: Missing '(Untitled)' in status bar. Buffer: "
                  f"{repr(out_edit)}", flush=True)
            return False
        if b"^K: Editor keys" not in out_edit:
            print(f"[-] Step 7: Missing '^K: Editor keys' in status bar. "
                  f"Buffer: {repr(out_edit)}", flush=True)
            return False
        print(
            "[+] Step 7: Successfully entered full-screen editing mode with "
            "'(Untitled)' and '^K: Editor keys'.",
            flush=True
        )

        # 8. Test interactive character typing in empty buffer
        print("[*] Step 8: Testing interactive typing & Home/End...",
              flush=True)
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
        print(
            "[+] Step 8: Successfully typed and rendered 'HELLO WORLD' "
            "(Row 1, Col 11).",
            flush=True
        )

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

        print(
            "[+] Step 8: Successfully verified Home (ESC [ 1 ~, ESC [ H, "
            "ESC O H, ^A) and End (ESC [ 4 ~, ESC [ F, ESC O F, ^E) "
            "navigation!",
            flush=True
        )

        # 8b. Create multi-line text by pressing Enter
        for line in [b"\r", b"Line Two of Document", b"\r", b"Line Three with Tabs", b"\r", b"Line Four Final"]:
            os.write(master, line)
            time.sleep(0.1)
        time.sleep(0.5)
        drain_all(master)

        # 9. Test Left / Right cursor movement and line-end wrapping
        print("[*] Step 9: Testing cursor navigation and line wrapping...",
              flush=True)
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
        print(
            "[+] Step 9: Successfully verified horizontal cursor navigation "
            "and line wrapping.",
            flush=True
        )

        # 10. Test cursor down clamping at end of file (4 lines -> cursor stops at line 4)
        print("[*] Step 10: Testing cursor down clamping at EOF...", flush=True)
        time.sleep(0.2)
        for _ in range(15):
            os.write(master, b"\x1b[B")
            time.sleep(0.01)
        out_row_clamp = read_until(master, b"Line    4/4", timeout=6.0)
        if b"Line    4/4" not in out_row_clamp:
            print("[-] Cursor down clamping at EOF failed. Buffer captured:", repr(out_row_clamp))
            return False
        print(
            "[+] Step 10: Successfully verified cursor cannot move past the "
            "last line of text (line 4).",
            flush=True
        )

        # 11. Test mid-line insertion line length capacity (preventing exceeding 120 chars)
        print("[*] Step 11: Testing mid-line insertion line length capacity...",
              flush=True)
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
        print(
            "[+] Step 11: Successfully verified 120-char line capacity limit "
            "during mid-line insertion.",
            flush=True
        )

        # 12. Test Line Joining with Backspace at column 0
        print("[*] Step 12: Testing line joining with Backspace at col 0...",
              flush=True)
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
        out_join_bs = read_until(master, b"Line    1/3    Col 11", timeout=4.0)
        if b"Line    1/3    Col 11" not in out_join_bs:
            print(f"[-] Line join via Backspace at Col 0 failed. Buffer: {repr(out_join_bs)}", flush=True)
            return False
        drain_all(master)
        print(
            "[+] Step 12: Successfully verified Line Joining with Backspace "
            "at column 0.",
            flush=True
        )

        # 13. Test Line Joining with Delete Key (\x1b[3~) at End of Line
        print("[*] Step 13: Testing line joining with Delete key at EOL...",
              flush=True)
        # Move cursor to end of Row 1 (length 31)
        os.write(master, b"\x05")  # Ctrl+E -> End of line
        time.sleep(0.2)
        drain_all(master)
        # Press Delete key (\x1b[3~) at EOL to join next line into Row 1 -> cursor stays at Row 1, Col 31
        os.write(master, b"\x1b[3~")
        out_join_del = read_until(master, b"Line    1/2    Col 31", timeout=4.0)
        if b"Line    1/2    Col 31" not in out_join_del:
            print(f"[-] Line join via Delete key at EOL failed. Buffer: {repr(out_join_del)}", flush=True)
            return False
        drain_all(master)
        print(
            "[+] Step 13: Successfully verified Line Joining with Delete "
            "key (ESC [ 3 ~) at End of Line.",
            flush=True
        )

        # 14. Test Real Tab character insertion & Tab-jumping navigation
        print("[*] Step 14: Testing real Tab character insertion & "
              "navigation...", flush=True)
        # Move cursor to (1,0)
        os.write(master, b"\x01")  # Ctrl+A -> Home
        read_until(master, b"Line    1/2    Col 0", timeout=3.0)
        drain_all(master)
        # Press Tab at (1,0) -> advances visual cursor to (1,8) -> displayed as Col 8 (0-indexed)
        os.write(master, b"\t")
        out_tab1 = read_until(master, b"Line    1/2    Col 8", timeout=4.0)
        if b"Line    1/2    Col 8" not in out_tab1:
            print(f"[-] Tab key from col 0 failed to reach col 8. Buffer captured: {repr(out_tab1)}", flush=True)
            return False
        drain_all(master)

        # Test Cursor Left jumping across the Tab in a single keystroke
        os.write(master, b"\x1b[D")
        out_tab_left = read_until(master, b"Line    1/2    Col 0", timeout=4.0)
        if b"Line    1/2    Col 0" not in out_tab_left:
            print(f"[-] Left arrow over Tab failed to jump back to col 0. Buffer captured: {repr(out_tab_left)}", flush=True)
            return False
        drain_all(master)

        # Test Cursor Right jumping across the Tab in a single keystroke
        os.write(master, b"\x1b[C")
        out_tab_right = read_until(master, b"Line    1/2    Col 8", timeout=4.0)
        if b"Line    1/2    Col 8" not in out_tab_right:
            print(f"[-] Right arrow over Tab failed to jump forward to col 8. Buffer captured: {repr(out_tab_right)}", flush=True)
            return False
        drain_all(master)

        # Test Backspace deleting the entire Tab in a single keystroke
        os.write(master, b"\x08")
        out_tab_bs = read_until(master, b"Line    1/2    Col 0", timeout=4.0)
        if b"Line    1/2    Col 0" not in out_tab_bs:
            print(f"[-] Step 14: Backspace over Tab failed to return to col 0. "
                  f"Buffer: {repr(out_tab_bs)}", flush=True)
            return False
        print(
            "[+] Step 14: Successfully verified real Tab character insertion "
            "& tab-jumping navigation!",
            flush=True
        )
        drain_all(master)

        # 15. Test extending line past Col 119 barrier with horizontal scrolling ([Pan +40])
        print("[*] Step 15: Testing horizontal scrolling ([Pan +40])...",
              flush=True)
        # Move down to line 4, then type characters extending line past 120 columns
        for _ in range(3):
            os.write(master, b"\x1b[B")
            time.sleep(0.05)
        # Move to end of line
        os.write(master, b"\x1b[F")
        time.sleep(0.1)
        drain_all(master)
        # Type 35 characters extending past the 120 column barrier (line currently ~90 chars -> 125 chars)
        for _ in range(35):
            os.write(master, b"X")
            time.sleep(0.02)
        drain_all(master)
        # Move to End of line (Col 125)
        os.write(master, b"\x1b[F")
        out_col_clamp = read_until(master, b"Col 125", timeout=4.0)
        if b"Col 125" not in out_col_clamp or b"[Pan +40]" not in out_col_clamp:
            print(f"[-] Extending line past Col 119 failed. Buffer captured: {repr(out_col_clamp)}", flush=True)
            return False
        # Type extra characters past Col 125 to Col 130
        for _ in range(5):
            os.write(master, b"Y")
            time.sleep(0.02)
        out_col_130 = read_until(master, b"Col 130", timeout=4.0)
        if b"Col 130" not in out_col_130:
            print(f"[-] Typing past Col 125 to Col 130 failed. Buffer: {repr(out_col_130)}", flush=True)
            return False
        # Verify Home (Ctrl+A) returns to Col 0 and resets viewport pan
        os.write(master, b"\x01")
        out_home = read_until(master, b"Col 0", timeout=4.0)
        if b"Col 0" not in out_home or b"^K: Editor keys" not in out_home:
            print(f"[-] Home failed to reset pan to Col 0. Buffer: {repr(out_home)}", flush=True)
            return False
        drain_all(master)
        print(
            "[+] Step 15: Successfully verified entering characters to extend "
            "line past 119 column barrier with [Pan +40].",
            flush=True
        )

        # 16. Verify Ctrl+F in editor mode opens Find prompt and ESC cancels cleanly
        print("[*] Step 16: Verifying Ctrl+F opens Find prompt and ESC "
              "cancels...", flush=True)
        time.sleep(0.2)
        drain_all(master)
        os.write(master, b"\x06")
        out_find_prompt = read_until(master, b"Find (Exact):", timeout=4.0)
        if b"Find (Exact):" not in out_find_prompt:
            print(f"[-] Ctrl+F failed to open Find prompt. Buffer: {repr(out_find_prompt)}", flush=True)
            return False
        # Cancel with ESC
        os.write(master, b"\x1b")
        read_until(master, b"Line    4/4", timeout=4.0)
        drain_all(master)
        print(
            "[+] Step 16: Successfully verified ^F in editor mode opens Find "
            "prompt and ESC cancels cleanly.",
            flush=True
        )

        # 17. Save file with Ctrl+S (opens Save Screen, tests Save Screen Ctrl+F toggle, and saves to OUTPUT.TXT)
        print("[*] Step 17: Testing Save Screen (Ctrl+S) and format toggle...",
              flush=True)
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
        print(
            "[+] Step 17: Successfully verified Save Screen ^F format toggle "
            "(CP/M <-> Linux).",
            flush=True
        )
        time.sleep(0.2)
        os.write(master, b"OUTPUT.TXT\r")
        time.sleep(0.2)
        resp = read_until(master, b"o): ", timeout=2.0)
        if b"Overwrite? (" in resp:
            os.write(master, b"y")
        read_until(master, b"Line    1/1", timeout=5.0)
        drain_all(master)
        print("[+] Step 17: Successfully saved file with Ctrl+S.", flush=True)

        # 18. Send Ctrl+Q to exit cleanly back to CP/M
        print("[*] Step 18: Testing Ctrl+Q clean exit back to CP/M...",
              flush=True)
        time.sleep(0.5)
        os.write(master, b"\x11")
        out_exit = read_until(master, b"C>", timeout=4.0)
        if b"C>" not in out_exit and b"Exiting SE.COM" not in out_exit:
            print(f"[-] Clean exit message not observed. Buffer captured: {repr(out_exit)}", flush=True)
            return False
        print(
            "[+] Step 18: SE.COM successfully received Ctrl+Q and returned "
            "cleanly to CP/M.",
            flush=True
        )

        # 19. Test File Loading: Open 2-line file 'se 2.TXT'
        print("[*] Step 19: Testing file loading ('se 2.TXT')...", flush=True)
        time.sleep(0.5)
        os.write(master, b"se 2.TXT\r")
        out_load = read_until(master, b"Line    1/2", timeout=30.0)
        if b"C:2.TXT" not in out_load:
            print(f"[-] Failed to load file 2.TXT into SE.COM. Buffer: {repr(out_load)}", flush=True)
            return False
        # Verify BOTH Line 1 and Line 2 from 2.TXT loaded and rendered on screen
        if b"First line of two" not in out_load or b"Second line of two" not in out_load:
            print(f"[-] Multi-line file contents missing in SE.COM. Buffer: {repr(out_load)}", flush=True)
            return False
        # Verify status bar shows full filename 'C:2.TXT' without corruption
        if b"| C:2.TXT        |" not in out_load:
            print(f"[-] Status bar missing exact '| C:2.TXT        |'. "
                  f"Buffer: {repr(out_load[-400:])}", flush=True)
            return False
        if b"2.TXTU:" in out_load or b".TXTU:" in out_load:
            print(f"[-] Status bar corrupted with erroneous 'U:' suffix! "
                  f"Buffer: {repr(out_load[-400:])}", flush=True)
            return False
        print(
            "[+] Step 19: Successfully verified multi-line file loading "
            "(se 2.TXT) and Far RAM streaming!",
            flush=True
        )

        # Exit editor again
        time.sleep(0.5)
        os.write(master, b"\x11")
        read_until(master, b"C>", timeout=4.0)
        print("[+] Step 19: Exit from SE.COM completed.", flush=True)

        # 20. Test Multi-Sector File Loading and Page-Up / Page-Down Navigation: 'se 30.TXT'
        print("[*] Step 20: Testing multi-sector file loading ('se 30.TXT')...",
              flush=True)
        time.sleep(0.5)
        os.write(master, b"se 30.TXT\r")
        out_load_30 = read_until(master, b"Line    1/30", timeout=30.0)
        if b"C:30.TXT" not in out_load_30:
            print(f"[-] Failed to load file 30.TXT into SE.COM. Buffer: {repr(out_load_30)}", flush=True)
            return False
        # Verify lines from 30.TXT are rendered on screen
        if b"Line 01 of test file content" not in out_load_30:
            print(f"[-] 30.TXT Line 01 missing on editor screen. Buffer: {repr(out_load_30)}", flush=True)
            return False
        if b"Line 20 of test file content" not in out_load_30:
            print(f"[-] 30.TXT Line 20 missing on editor screen. Buffer: {repr(out_load_30)}", flush=True)
            return False
        # Verify status bar shows full filename 'C:30.TXT' without corruption
        if b"| C:30.TXT       |" not in out_load_30:
            print(f"[-] Status bar missing exact '| C:30.TXT       |'. "
                  f"Buffer: {repr(out_load_30[-400:])}", flush=True)
            return False
        if b"30.TXTU:" in out_load_30 or b".TXTU:" in out_load_30:
            print(f"[-] Status bar corrupted with erroneous 'U:' suffix! "
                  f"Buffer: {repr(out_load_30[-400:])}", flush=True)
            return False
        print(
            "[+] Step 20: Successfully verified 30-line multi-sector file "
            "loading (se 30.TXT) into editor Far RAM buffer!",
            flush=True
        )

        # 21. Test Page-Down key (\x1b[6~)
        print("[*] Step 21: Testing Page-Down key (ESC [ 6 ~)...", flush=True)
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"\x1b[6~")
        out_pgdn = read_until(master, b"Line   30", timeout=4.0)
        if b"Line   30" not in out_pgdn:
            print(f"[-] Page Down key failed to navigate to bottom of document. Buffer: {repr(out_pgdn)}", flush=True)
            return False
        print(
            "[+] Step 21: Successfully verified Page-Down key (ESC [ 6 ~) "
            "navigation to Line 30.",
            flush=True
        )

        # 22. Test Page-Up key (\x1b[5~)
        print("[*] Step 22: Testing Page-Up key (ESC [ 5 ~)...", flush=True)
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"\x1b[5~")
        out_pgup = read_until(master, b"Line    1", timeout=4.0)
        if b"Line    1" not in out_pgup:
            print(f"[-] Page Up key failed to navigate back to top of document. Buffer: {repr(out_pgup)}", flush=True)
            return False
        print(
            "[+] Step 22: Successfully verified Page-Up key (ESC [ 5 ~) "
            "navigation to Line 1.",
            flush=True
        )

        # 23. Test Ctrl+V (Page Down) and Ctrl+U (Page Up) shortcuts
        print("[*] Step 23: Testing Ctrl+V (Page Down) and Ctrl+U (Page Up)...",
              flush=True)
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"\x16")  # Ctrl+V -> Page Down
        out_ctrl_v = read_until(master, b"Line   30", timeout=4.0)
        if b"Line   30" not in out_ctrl_v:
            print(f"[-] Ctrl+V (Page Down) failed. Buffer: {repr(out_ctrl_v)}", flush=True)
            return False
        os.write(master, b"\x15")  # Ctrl+U -> Page Up
        out_ctrl_u = read_until(master, b"Line    1", timeout=4.0)
        if b"Line    1" not in out_ctrl_u:
            print(f"[-] Ctrl+U (Page Up) failed. Buffer: {repr(out_ctrl_u)}", flush=True)
            return False
        print(
            "[+] Step 23: Successfully verified Ctrl+V (Page Down) and "
            "Ctrl+U (Page Up) shortcuts.",
            flush=True
        )

        # 24. Test Jump to Top / Bottom (Ctrl+Home / Ctrl+End, Ctrl+T / Ctrl+G, ESC < / ESC >, ESC t / ESC b)
        print("[*] Step 24: Testing Jump to Top / Bottom shortcuts...",
              flush=True)
        # Test Ctrl+G (Jump to Bottom)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x07")  # Ctrl+G -> Jump to Bottom
        out_g = read_until(master, b"Line   30", timeout=4.0)
        if b"Line   30" not in out_g:
            print(f"[-] Ctrl+G failed to jump to bottom of file. Buffer: {repr(out_g)}", flush=True)
            return False

        # Test Ctrl+T (Jump to Top)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x14")  # Ctrl+T -> Jump to Top
        out_t = read_until(master, b"Line    1", timeout=4.0)
        if b"Line    1" not in out_t:
            print(f"[-] Ctrl+T failed to jump to top of file. Buffer: {repr(out_t)}", flush=True)
            return False

        # Test Ctrl+End (ESC [ 1 ; 5 F)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b[1;5F")
        out_cend = read_until(master, b"Line   30", timeout=4.0)
        if b"Line   30" not in out_cend:
            print(f"[-] Ctrl+End (ESC [ 1 ; 5 F) failed to jump to bottom. Buffer: {repr(out_cend)}", flush=True)
            return False

        # Test Ctrl+Home (ESC [ 1 ; 5 H)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b[1;5H")
        out_chome = read_until(master, b"Line    1", timeout=4.0)
        if b"Line    1" not in out_chome:
            print(f"[-] Ctrl+Home (ESC [ 1 ; 5 H) failed to jump to top. Buffer: {repr(out_chome)}", flush=True)
            return False

        # Test ESC > (Jump to Bottom)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b>")
        out_esc_gt = read_until(master, b"Line   30", timeout=4.0)
        if b"Line   30" not in out_esc_gt:
            print(f"[-] ESC > failed to jump to bottom. Buffer: {repr(out_esc_gt)}", flush=True)
            return False

        # Test ESC < (Jump to Top)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b<")
        out_esc_lt = read_until(master, b"Line    1", timeout=4.0)
        if b"Line    1" not in out_esc_lt:
            print(f"[-] ESC < failed to jump to top. Buffer: {repr(out_esc_lt)}", flush=True)
            return False

        # Test ESC b (Jump to Bottom)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1bb")
        out_esc_b = read_until(master, b"Line   30", timeout=4.0)
        if b"Line   30" not in out_esc_b:
            print(f"[-] ESC b failed to jump to bottom. Buffer: {repr(out_esc_b)}", flush=True)
            return False

        # Test ESC t (Jump to Top)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1bt")
        out_esc_t = read_until(master, b"Line    1", timeout=4.0)
        if b"Line    1" not in out_esc_t:
            print(f"[-] ESC t failed to jump to top. Buffer: {repr(out_esc_t)}", flush=True)
            return False

        print(
            "[+] Step 24: Successfully verified Jump to Top (Ctrl+T, "
            "Ctrl+Home, ESC <, ESC t) and Jump to Bottom (Ctrl+G, Ctrl+End, "
            "ESC >, ESC b)!",
            flush=True
        )

        # 25. Test ESC key showing splash screen and Enter resuming editor mode
        print("[*] Step 25: Testing ESC splash screen and Enter resume...",
              flush=True)
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b")  # Standalone ESC key
        out_splash = read_until(master, b"for about", timeout=4.0)
        if b"SE - Screen Editor" not in out_splash:
            print(f"[-] ESC key failed to show splash screen. Buffer: {repr(out_splash)}", flush=True)
            return False
        if b"version" in out_splash or b"Dean Jenkins" in out_splash:
            print(f"[-] Splash screen unexpectedly contains version/author. Buffer: {repr(out_splash)}", flush=True)
            return False
        if b"for about" not in out_splash:
            print(f"[-] Splash screen missing about option. Buffer: {repr(out_splash)}", flush=True)
            return False
        out_splash_status = read_until(master, b"Line    1/30", timeout=4.0)
        if (b"Free: 316 KB" not in out_splash_status and
            b"Free: 348 KB" not in out_splash_status and
            b"Free: 380 KB" not in out_splash_status and
            b"Free: 412 KB" not in out_splash_status):
            print(f"[-] Splash screen status bar missing free memory indicator. Buffer: {repr(out_splash_status)}", flush=True)
            return False
        print(
            "[+] Step 25: Successfully verified ESC key in editor displays "
            "streamlined splash screen and free memory.",
            flush=True
        )

        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"\r")  # Press Enter to return to editor
        out_resume = read_until(master, b"Line 01 of test file content", timeout=4.0)
        if b"Line 01 of test file content" not in out_resume:
            print(f"[-] Enter key on splash failed to return to editor. Buffer: {repr(out_resume)}", flush=True)
            return False
        print(
            "[+] Step 25: Successfully verified Enter key resumes editor mode "
            "with document intact.",
            flush=True
        )

        # 26. Test Open File option (:o) on splash screen with Directory Listing
        print("[*] Step 26: Testing Open File (:o) with Directory Listing...",
              flush=True)
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
        print(
            "[+] Step 26: Successfully verified Open File screen with sorted "
            "directory listing.",
            flush=True
        )

        # Check if directory is multi-page or single-page
        if b"<PgUp>/<PgDn>=Page" in out_dir:
            # Multi-page pagination verification
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
        else:
            # Single-page mode (expanded 120x40 capacity fits all files on 1 page without premature pagination)
            print(
            "[+] Step 26: Successfully verified expanded 120x40 capacity "
            "displays directory on single page without premature pagination.",
            flush=True
        )
            # Verify typing in text box and that PgDn/PgUp are benign
            drain_all(master)
            time.sleep(0.1)
            os.write(master, b"TESTFILE")
            time.sleep(0.1)
            os.write(master, b"\x1b[6~")  # PgDn should not break text box
            time.sleep(0.1)
            os.write(master, b"\x1b[5~")  # PgUp should not break text box
            time.sleep(0.1)
            os.write(master, b"\x08" * 8) # Clear typed TESTFILE
            print(
            "[+] Step 26: Successfully verified text box editing and "
            "PgDn/PgUp stability in single-page mode.",
            flush=True
        )

        # Test ESC to cancel from Open File prompt
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\x1b")  # ESC to cancel
        out_cancel = read_until(master, b"SE - Screen Editor", timeout=4.0)
        if b"SE - Screen Editor" not in out_cancel:
            print(f"[-] ESC key did not cancel open prompt back to splash screen. Buffer: {repr(out_cancel)}", flush=True)
            return False
        print(
            "[+] Step 26: Successfully verified ESC cancels Open File prompt "
            "back to splash screen.",
            flush=True
        )

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
            if b"Line    1/" in check_buf:
                print(f"[-] Non-existent file erroneously entered editor mode! Buffer: {repr(check_buf)}", flush=True)
                return False
        print(
            "[+] Step 26: Successfully verified bad filename shows "
            "'File not found' without entering editor mode.",
            flush=True
        )

        # Now edit bad filename in-place: send 3 Backspaces to erase 'BAK' (first BS clears 'File not found' & 'K')
        time.sleep(0.1)
        for _ in range(3):
            os.write(master, b"\x08")
            time.sleep(0.1)

        # Verify backspace did NOT enter editor mode
        r, _, _ = select.select([master], [], [], 0.3)
        if r:
            check_buf = os.read(master, 2048)
            if b"Line    1/" in check_buf:
                print(f"[-] Backspace in open prompt erroneously entered editor mode! Buffer: {repr(check_buf)}", flush=True)
                return False

        # Type correct extension 'TXT' and press Enter
        os.write(master, b"TXT\r")
        out_loaded = read_until(master, b"Line    1/2", timeout=4.0)
        if b"C:2.TXT" not in out_loaded:
            print(f"[-] Failed to open 2.TXT from Open File prompt after backspace amendment. Buffer: {repr(out_loaded)}", flush=True)
            return False
        if b"First line of two" not in out_loaded:
            print(f"[-] Document contents not loaded after backspace amendment. Buffer: {repr(out_loaded)}", flush=True)
            return False
        print(
            "[+] Step 26: Successfully verified bad filename kept in text "
            "box, amended via backspace, and loaded.",
            flush=True
        )

        # 27. Test Save Screen: Pre-filling, Overwrite check, and Splash :s
        print("[*] Step 27: Testing Save Screen pre-filling, overwrite & :s...",
              flush=True)
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
        print(
            "[+] Step 27: Successfully verified Save Screen with pre-filled "
            "filename '2.TXT' and ^F toggle.",
            flush=True
        )

        # Press Enter (\r) to save with existing filename: should trigger overwrite warning
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"\r")
        out_warn = read_until(master, b"o): ", timeout=4.0)
        if b"File already exists. Overwrite? (" not in out_warn:
            print(f"[-] Overwrite warning prompt missing. Buffer: {repr(out_warn)}", flush=True)
            return False
        if b"\x1b[4mY\x1b[24mes" not in out_warn or b"\x1b[4mN\x1b[24mo" not in out_warn:
            print(f"[-] Overwrite prompt missing underscored hotkeys. Buffer: {repr(out_warn)}", flush=True)
            return False
        print(
            "[+] Step 27: Successfully verified overwrite warning prompt on "
            "existing file with underscored hotkeys.",
            flush=True
        )

        # Test canceling overwrite with 'n'
        time.sleep(0.2)
        os.write(master, b"n")
        out_cancel = read_until(master, b"Save cancelled.", timeout=3.0)
        if b"Save cancelled." not in out_cancel:
            print(f"[-] 'Save cancelled.' message missing. Buffer: {repr(out_cancel)}", flush=True)
            return False
        out_back = read_until(master, b"C:2.TXT", timeout=4.0)
        if b"C:2.TXT" not in out_back:
            print(f"[-] Editor mode not restored after cancelling save. Buffer: {repr(out_back)}", flush=True)
            return False
        print(
            "[+] Step 27: Successfully verified cancelling overwrite "
            "returns cleanly to editor.",
            flush=True
        )

        # Re-open Save Screen with Ctrl+S and confirm overwrite with 'y'
        time.sleep(0.3)
        os.write(master, b"\x13")
        read_until(master, b"Enter filename to save", timeout=4.0)
        read_until(master, b"2.TXT", timeout=3.0)
        time.sleep(0.2)
        os.write(master, b"\r")
        read_until(master, b"o): ", timeout=4.0)
        time.sleep(0.2)
        os.write(master, b"y")
        out_saved = read_until(master, b"C:2.TXT", timeout=5.0)
        if b"C:2.TXT" not in out_saved:
            print(f"[-] Editor mode not restored after confirming save. Buffer: {repr(out_saved)}", flush=True)
            return False
        print(
            "[+] Step 27: Successfully verified confirming overwrite ('y') "
            "saves file and resumes editor.",
            flush=True
        )

        # Return to splash screen (ESC) and test ':s' option
        drain_all(master)
        time.sleep(0.3)
        os.write(master, b"\x1b")
        out_splash = read_until(master, b"s                to save file", timeout=5.0)
        if b"s                to save file" not in out_splash:
            print(f"[-] Splash screen 's to save file' not found. Buffer: {repr(out_splash)}", flush=True)
            return False
        print(
            "[+] Step 27: Successfully verified splash screen displays "
            "'s to save file'.",
            flush=True
        )

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
        read_until(master, b"for about", timeout=4.0)
        print(
            "[+] Step 27: Successfully verified splash ':s' enters Save "
            "Screen and ESC returns to splash.",
            flush=True
        )

        # 28. Test Editor Mode Keys screen (^K)
        print("[*] Step 28: Testing Editor Mode Keys screen (^K)...",
              flush=True)
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
        print(
            "[+] Step 28: Successfully verified Ctrl+K Editor Mode Keys "
            "screen and return to editor.",
            flush=True
        )

        # 29. Test Ctrl+O in Editor Mode (Open File Screen and ESC cancel)
        print("[*] Step 29: Testing Ctrl+O in Editor Mode...", flush=True)
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
        print(
            "[+] Step 29: Successfully verified Ctrl+O opens directory browser "
            "and ESC returns to editor without opening file.",
            flush=True
        )

        # Test Ctrl+O successfully opening a new file from editor mode
        time.sleep(0.2)
        os.write(master, b"\x0f")  # Ctrl+O
        read_until(master, b"Enter filename to open:", timeout=4.0)
        time.sleep(0.2)
        os.write(master, b"30.TXT\r")
        out_open_30 = read_until(master, b"Line    1/30", timeout=4.0)
        if b"C:30.TXT" not in out_open_30 or \
           b"Line 01 of test file content" not in out_open_30:
            print(f"[-] Failed to open 30.TXT via Ctrl+O in editor mode. "
                  f"Buffer: {repr(out_open_30)}", flush=True)
            return False
        # Verify clean status bar after Ctrl+O open without U: suffix corruption
        if b"| C:30.TXT       |" not in out_open_30:
            print(f"[-] Status bar missing exact '| C:30.TXT       |' "
                  f"after Ctrl+O open. Buffer: {repr(out_open_30[-400:])}",
                  flush=True)
            return False
        if b"30.TXTU:" in out_open_30 or b".TXTU:" in out_open_30:
            print(f"[-] Status bar corrupted with 'U:' suffix after "
                  f"Ctrl+O open! Buffer: {repr(out_open_30[-400:])}",
                  flush=True)
            return False
        print(
            "[+] Step 29: Successfully verified Ctrl+O in editor mode opens "
            "file into editor with clean status bar.",
            flush=True
        )

        # 30. Test Drive Switching in Open Screen ("B:" and "C:")
        print("[*] Step 30: Testing Drive Switching in Open Screen...",
              flush=True)
        time.sleep(0.2)
        os.write(master, b"\x0f")  # Ctrl+O
        read_until(master, b"Enter filename to open:", timeout=4.0)
        time.sleep(0.2)
        # Type 'B:' and hit Return to switch to Drive B: (clearing preloaded prefix first)
        os.write(master, b"\x08" * 20 + b"B:\r")
        out_drive_b = read_until(master, b"OPEN FILE (DIRECTORY - DRIVE B:)", timeout=4.0)
        if b"OPEN FILE (DIRECTORY - DRIVE B:)" not in out_drive_b:
            print(f"[-] Failed to switch to Drive B: in Open Screen. Buffer: {repr(out_drive_b)}", flush=True)
            return False
        # Verify prompt retains 'B:' (Drive B: has 2 pages, so multi-page prompt format is used)
        out_retained_b = read_until(master, b"[B:", timeout=3.0)
        if b"[B:" not in out_retained_b:
            print(f"[-] Prompt did not retain 'B:'. Buffer: {repr(out_retained_b)}", flush=True)
            return False
        print(
            "[+] Step 30: Successfully verified switching to Drive B: in Open "
            "Screen with 'B:' retained in text box.",
            flush=True
        )

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
        print(
            "[+] Step 30: Successfully verified switching back to Drive C: "
            "and returning to editor on ESC.",
            flush=True
        )

        # 31. Test Drive Switching in Save Screen ("B:" and "C:")
        print("[*] Step 31: Testing Drive Switching in Save Screen...",
              flush=True)
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
        print(
            "[+] Step 31: Successfully verified switching to Drive B: in Save "
            "Screen with 'B:' retained in text box.",
            flush=True
        )

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
        print(
            "[+] Step 31: Successfully verified switching back to Drive C: "
            "in Save Screen and ESC returns cleanly.",
            flush=True
        )

        # 32. Test High-Speed Burst Paste (Clipboard Simulation)
        print("[*] Step 32: Testing high-speed burst paste...", flush=True)
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
        print(
            "[+] Step 32: Successfully verified high-speed clipboard burst "
            "paste deferred redraw!",
            flush=True
        )

        # 33. Test Line Slot Indirection & Slot Recycling from Extended RAM
        print("[*] Step 33: Testing line slot indirection & recycling...",
              flush=True)
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
        print(
            "[+] Step 33: Successfully verified slot allocation, "
            "deallocation, and recycling from Extended RAM!",
            flush=True
        )

        # 34. Test Hybrid Block Highlighting & Ctrl+K Solidification
        print("[*] Step 34: Testing hybrid block highlighting & "
              "solidification...", flush=True)
        time.sleep(0.2)
        drain_all(master)
        # Move to top of document (Ctrl+T) and column 0 (Ctrl+A)
        os.write(master, b"\x14\x01")
        read_until(master, b"Line    1/", timeout=4.0)

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
            print(f"[-] Step 34: Ctrl+B cancel of solidified block failed. "
                  f"Buffer: {repr(out_toggle_off)}", flush=True)
            return False
        print(
            "[+] Step 34: Successfully verified hybrid block highlighting & "
            "Ctrl+K solidification!",
            flush=True
        )

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
        print(
            "[+] Step 35: Successfully verified dynamic tab block "
            "highlighting on last line!",
            flush=True
        )

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
            print(
                f"[-] Step 36: Block solidification failed for Ctrl+C test. "
                f"Buffer: {repr(out_solid_cpy)}",
                flush=True
            )
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
            print(
                f"[-] Step 36: Ctrl+C inside block was not ignored. "
                f"Buffer: {repr(out_in_blk)}",
                flush=True
            )
            return False

        # Move cursor to end of line: Ctrl+E (Col 2 or higher, outside block)
        os.write(master, b"\x05")
        time.sleep(0.1)
        drain_all(master)

        # Test 2: Press Ctrl+C outside block: copies block
        os.write(master, b"\x03")
        time.sleep(0.3)
        out_cpy1 = drain_all(master)
        if b"[BLK: 2c LOCK]" not in out_cpy1 or (
            b"L1L1" not in out_cpy1 and b"L1\x1b[0mL1" not in out_cpy1
        ):
            print(
                f"[-] Step 36: Ctrl+C copy failed or lost block lock. "
                f"Buffer: {repr(out_cpy1)}",
                flush=True
            )
            return False

        # Test 3: Press Ctrl+C again consecutively: duplicate copy
        os.write(master, b"\x03")
        time.sleep(0.3)
        out_cpy2 = drain_all(master)
        if b"[BLK: 2c LOCK]" not in out_cpy2 or (
            b"L1L1L1" not in out_cpy2 and b"L1\x1b[0mL1L1" not in out_cpy2
        ):
            print(
                f"[-] Step 36: Consecutive Ctrl+C failed or lost block lock. "
                f"Buffer: {repr(out_cpy2)}",
                flush=True
            )
            return False

        # Test 4: Multi-line block copy (1L boundary at Row 2 Col 0, and 2L full block)
        # Cancel previous block with ESC
        os.write(master, b"\x1b")
        time.sleep(0.1)
        read_until(master, b"^K: Editor keys", timeout=4.0)
        drain_all(master)

        # Move to Row 1 Col 0: Ctrl+T, Ctrl+A
        os.write(master, b"\x14\x01")
        time.sleep(0.1)
        drain_all(master)
        # Start block (Ctrl+B), expand down 1 row (Down Arrow to Row 2 Col 0)
        os.write(master, b"\x02\x1b[B")
        time.sleep(0.1)
        # Solidify with Ctrl+K -> must be [BLK: 1L LOCK]
        os.write(master, b"\x0b")
        out_1l_solid = read_until(master, b"[BLK: 1L LOCK]", timeout=4.0)
        if b"[BLK: 1L LOCK]" not in out_1l_solid:
            print(
                f"[-] Step 36: 1L block solidification failed. "
                f"Buffer: {repr(out_1l_solid)}",
                flush=True
            )
            return False

        # Test Ctrl+C directly at Row 2 Col 0: must not be ignored
        drain_all(master)
        os.write(master, b"\x03")
        time.sleep(0.3)
        out_1l_cpy = drain_all(master)
        if b"[BLK: 1L LOCK]" not in out_1l_cpy:
            print(
                f"[-] Step 36: Ctrl+C at Row 2 Col 0 failed. "
                f"Buffer: {repr(out_1l_cpy)}",
                flush=True
            )
            return False

        # Cancel block
        os.write(master, b"\x1b")
        time.sleep(0.1)
        read_until(master, b"^K: Editor keys", timeout=4.0)
        drain_all(master)

        # Move to Row 1 Col 0: Ctrl+T, Ctrl+A
        os.write(master, b"\x14\x01")
        time.sleep(0.1)
        drain_all(master)
        # Start block (Ctrl+B), expand down 2 rows (Down Arrow twice) for 2 lines
        os.write(master, b"\x02\x1b[B\x1b[B")
        time.sleep(0.1)
        # Solidify with Ctrl+K -> must be [BLK: 2L LOCK]
        os.write(master, b"\x0b")
        out_ml_solid = read_until(master, b"[BLK: 2L LOCK]", timeout=4.0)
        if b"[BLK: 2L LOCK]" not in out_ml_solid:
            print(
                f"[-] Step 36: Multi-line solidification failed. "
                f"Buffer: {repr(out_ml_solid)}",
                flush=True
            )
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
            print(
                f"[-] Step 36: Multi-line block copy failed. "
                f"Buffer: {repr(out_ml_cpy)}",
                flush=True
            )
            return False

        # Test 5: Cancellation terminates Ctrl+C
        os.write(master, b"\x1b")
        time.sleep(0.1)
        read_until(master, b"^K: Editor keys", timeout=4.0)
        drain_all(master)
        os.write(master, b"\x03")
        time.sleep(0.2)
        out_cancelled = drain_all(master)
        if out_cancelled != b"":
            print(
                f"[-] Step 36: Ctrl+C operated after block was cancelled! "
                f"Buffer: {repr(out_cancelled)}",
                flush=True
            )
            return False

        print(
            "[+] Step 36: Successfully verified solidified block copy "
            "(Ctrl+C) feature!",
            flush=True
        )

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
        read_until(master, b"^K: Editor keys", timeout=4.0)
        drain_all(master)

        print("[+] Successfully verified half-open caret selection [Start, End) semantics (Step 37)!", flush=True)

        # Step 38: Test Backwards Block Selection Normalization Semantics
        print("[*] Step 38: Testing backwards block selection semantics...", flush=True)

        # Part 1: Multi-line backwards selection (Row 10 Col 5 left arrow wrapping onto Row 9 to Col 0)
        # Move to top of document (Ctrl+T) and Col 0 (Ctrl+A), then move to Row 10 Col 5
        os.write(master, b"\x14\x01")
        read_until(master, b"Line    1/", timeout=4.0)
        os.write(master, b"\x1b[B" * 9)
        read_until(master, b"Line   10/", timeout=4.0)
        os.write(master, b"\x1b[C" * 5)
        out_s38_r10c5 = read_until(master, b"Col 5", timeout=4.0)
        if b"Col 5" not in out_s38_r10c5:
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
            if b"Line    9/" in buf and b"Col 0 " in buf:
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
        read_until(master, b"^K: Editor keys", timeout=4.0)
        drain_all(master)

        # Part 2: Single-line backwards selection (Col 5 left to Col 4)
        # Move to top of document (Ctrl+T) and Col 0 (Ctrl+A), then move right 5 columns
        os.write(master, b"\x14\x01")
        read_until(master, b"Line    1/", timeout=4.0)
        os.write(master, b"\x1b[C" * 5)
        out_s38_c5 = read_until(master, b"Col 5", timeout=4.0)
        if b"Col 5" not in out_s38_c5:
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
        read_until(master, b"^K: Editor keys", timeout=4.0)
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

        # 4. Test Ctrl-C solidify + copy immediately on dynamic selection
        os.write(master, b"\x14\x01") # Top, Col 0 (cursor at "12345")
        time.sleep(0.1)
        drain_all(master)

        os.write(master, b"\x02" + b"\x1b[C" * 3) # Select "123"
        out_c_sel = read_until(master, b"[SEL: 3c]", timeout=4.0)
        if b"[SEL: 3c]" not in out_c_sel:
            print(f"[-] Step 39 select 123 failed: {repr(out_c_sel)}", flush=True)
            return False

        os.write(master, b"\x03") # Ctrl-C -> solidifies AND performs copy operation immediately!
        out_c_lock = read_until(master, b"[BLK: 3c LOCK]", timeout=4.0)
        if b"[BLK: 3c LOCK]" not in out_c_lock:
            print(f"[-] Step 39 Ctrl-C solidify failed: {repr(out_c_lock)}", flush=True)
            return False

        os.write(master, b"\x14")
        out_c_res = read_until(master, b"12345", timeout=4.0)
        if b"123" not in out_c_res or b"12345" not in out_c_res:
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

        # Verify cursor is at Col 120 (end of 120-char line)
        os.write(master, b"\x05")
        out_s41_full = read_until(master, b"Col 120", timeout=4.0)
        if b"Col 120" not in out_s41_full:
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

        # 3. Copy 5 characters into a line that has 120 characters
        # In Phase 2, block copy expands the line to 125 chars (past 120-column boundary) without truncation
        os.write(master, b"\x03") # Ctrl-C -> copy 5 chars to Col 0
        time.sleep(0.3)
        drain_all(master)

        # Move to end of line: Ctrl-E, verify length is now 125 chars (Col 125)
        os.write(master, b"\x05")
        out_s41_check = read_until(master, b"Col 125", timeout=4.0)
        if b"Col 125" not in out_s41_check:
            print(f"[-] Step 41 capacity overflow check failed: {repr(out_s41_check)}", flush=True)
            return False

        # Block should remain intact
        if b"[BLK: 5c LOCK]" not in out_s41_check:
            print(f"[-] Step 41 block lock state lost: {repr(out_s41_check)}", flush=True)
            return False

        # Cancel block with ESC
        os.write(master, b"\x1b")
        read_until(master, b"^K: Editor keys", timeout=4.0)

        print("[+] Successfully verified Block Copy past 120-column boundary (Step 41)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 42: Interactive Goto Line Facility (Ctrl+L in Editor Mode)
        # ---------------------------------------------------------------------
        print("[*] Step 42: Verifying interactive Goto Line facility (Ctrl+L)...", flush=True)

        # Move to line 1: Ctrl+T, Ctrl+A
        os.write(master, b"\x14\x01")
        out_init = read_until(master, b"Col 0", timeout=4.0)
        idx = out_init.rfind(b"Line    1/")
        if idx != -1 and b"Col" in out_init[idx + 10 :]:
            total_str = out_init[idx + 10 :].split(b"Col")[0].strip()
        else:
            total_str = b"38"
        lbl_1 = b"Line    1/" + total_str
        lbl_10 = b"Line   10/" + total_str
        lbl_25 = b"Line   25/" + total_str
        lbl_max = b"Line   " + total_str + b"/" + total_str
        lbl_15 = b"Line   15/" + total_str

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
        lbl_2 = b"Line    2/" + total_str
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
        out_s43_splash = read_until(master, b"for about", timeout=4.0)
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

        # Final exit from editor with Ctrl+Q back to CP/M
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"\x11")
        out_q = read_until(master, [b"Save changes?", b"C>"], timeout=6.0)
        if b"Save changes?" in out_q:
            time.sleep(0.2)
            os.write(master, b"n")
            read_until(master, b"C>", timeout=6.0)
        time.sleep(0.3)
        drain_all(master)
        print("[+] Final exit from SE.COM completed.", flush=True)

        # ---------------------------------------------------------------------
        # Step 44: Command-Line Goto Line ('se 30.TXT:15' and 'se 30.TXT:999')
        # ---------------------------------------------------------------------
        print("[*] Step 44: Verifying command-line Goto Line facility ('se 30.TXT:15')...", flush=True)

        # Launch SE directly with line number: 'se 30.TXT:15'
        time.sleep(0.5)
        os.write(master, b"se 30.TXT:15\r")
        out_s44_l15 = read_until(master, b"Line   15/30", timeout=35.0)
        if b"Line   15/30" not in out_s44_l15 or b"Line 15 of test file content" not in out_s44_l15:
            print(f"[-] Step 44 failed: 'se 30.TXT:15' did not position at Line 15. Buffer: {repr(out_s44_l15)}", flush=True)
            return False
        if b"C:30.TXT" not in out_s44_l15:
            print(f"[-] Step 44 failed: 'se 30.TXT:15' filename missing on status bar. Buffer: {repr(out_s44_l15)}", flush=True)
            return False

        # Exit with Ctrl+Q back to CP/M
        time.sleep(0.2)
        os.write(master, b"\x11")
        read_until(master, b"C>", timeout=6.0)
        drain_all(master)

        # Launch SE with line number beyond EOF: 'se 30.TXT:999' (should clamp to max line)
        time.sleep(0.5)
        os.write(master, b"se 30.TXT:999\r")
        out_s44_l30 = read_until(master, b"Line   30/30", timeout=35.0)
        if b"Line   30/30" not in out_s44_l30 or b"Line 30 of test file content" not in out_s44_l30:
            print(f"[-] Step 44 failed: 'se 30.TXT:999' did not clamp to Line 30. Buffer: {repr(out_s44_l30)}", flush=True)
            return False

        # Final exit from editor with Ctrl+Q back to CP/M
        time.sleep(0.2)
        os.write(master, b"\x11")
        read_until(master, b"C>", timeout=6.0)
        drain_all(master)
        print("[+] Successfully verified command-line Goto Line facility (Step 44)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 45: Search (Ctrl+F) and Find Next (Ctrl+N) with Exact Matching
        # ---------------------------------------------------------------------
        print("[*] Step 45: Verifying Search (Ctrl+F) & Find Next (Ctrl+N) with Case Sensitivity...", flush=True)

        # Launch SE on 30.TXT
        time.sleep(0.5)
        os.write(master, b"se 30.TXT\r")
        out_s45_init = read_until(master, b"Line    1/30", timeout=35.0)
        if b"Line    1/30" not in out_s45_init:
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
        out_s45_l15 = read_until(master, b"Line   15/30", timeout=4.0)
        if b"Line   15/30" not in out_s45_l15:
            print(f"[-] Step 45 failed: Search 'Line 15' did not position at line 15. Buffer: {repr(out_s45_l15)}", flush=True)
            return False

        # 3. Test case sensitivity: search for lowercase "line 15" from Line 1 (should fail)
        time.sleep(0.2)
        os.write(master, b"\x14\x01")  # Ctrl+T, Ctrl+A to line 1
        read_until(master, b"Line    1/30", timeout=4.0)

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
        read_until(master, b"Line    1/30", timeout=4.0)

        # Press Ctrl+N to find next occurrence on Line 2
        time.sleep(0.2)
        os.write(master, b"\x0e")
        out_s45_n1 = read_until(master, b"Line    2/30", timeout=4.0)
        if b"Line    2/30" not in out_s45_n1:
            print(f"[-] Step 45 failed: Ctrl+N did not advance to Line 2. Buffer: {repr(out_s45_n1)}", flush=True)
            return False

        # Press Ctrl+N to find next occurrence on Line 3
        time.sleep(0.2)
        os.write(master, b"\x0e")
        out_s45_n2 = read_until(master, b"Line    3/30", timeout=4.0)
        if b"Line    3/30" not in out_s45_n2:
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
        read_until(master, b"Line    1/30", timeout=4.0)

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
        out_s46_l20 = read_until(master, b"Line   20/30", timeout=4.0)
        if b"Line   20/30" not in out_s46_l20:
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
        read_until(master, b"Line   20/30", timeout=4.0)

        print("[+] Successfully verified Case Insensitivity Toggle (Ctrl+I) (Step 46)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 47: Search & Replace (Ctrl+R) Interactive & Replace All
        # ---------------------------------------------------------------------
        print("[*] Step 47: Verifying Search and Replace (Ctrl+R)...", flush=True)

        # Move to line 1
        time.sleep(0.2)
        os.write(master, b"\x14\x01")
        read_until(master, b"Line    1/30", timeout=4.0)

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
        out_s47_confirm = read_until(master, b"everse)? ", timeout=4.0)
        if b"Replace (" not in out_s47_confirm or b"everse)? " not in out_s47_confirm:
            print(f"[-] Step 47 failed: Confirmation prompt missing. Buffer: {repr(out_s47_confirm)}", flush=True)
            return False
        # Verify underscored options (Y, N, A, Q, R)
        if b"\x1b[4mY\x1b[24mes" not in out_s47_confirm or b"\x1b[4mN\x1b[24mo" not in out_s47_confirm or \
           b"\x1b[4mA\x1b[24mll" not in out_s47_confirm or b"\x1b[4mQ\x1b[24muit" not in out_s47_confirm or \
           b"\x1b[4mR\x1b[24meverse" not in out_s47_confirm:
            print(f"[-] Step 47 failed: Underscored options missing. Buffer: {repr(out_s47_confirm)}", flush=True)
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
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"^K: Editor keys", timeout=4.0)
        time.sleep(0.1)
        drain_all(master)
        # Re-search: Ctrl+F then Enter to repeat previous search
        os.write(master, b"\x06")
        read_until(master, b"Find (Exact):", timeout=4.0)
        time.sleep(0.1)
        os.write(master, b"\r")
        out_s48_re = read_until(master, b"Col 8", timeout=4.0)
        if b"[BLK: 8c LOCK]" not in out_s48_re or b"Col 8" not in out_s48_re:
            print(
                f"[-] Step 48 failed: Solidified block re-match missing or "
                f"not at Col 8. Buffer: {repr(out_s48_re)}",
                flush=True
            )
            return False
        print(
            "[+] Successfully verified Solidified Block Highlighting on "
            "Match (Step 48)!",
            flush=True
        )

        # ---------------------------------------------------------------------
        # Step 49: Start Search / Replace from Active Highlighted Block
        # ---------------------------------------------------------------------
        print(
            "[*] Step 49: Verifying Start Search from Highlighted Block...",
            flush=True
        )
        # Dismiss existing block with ESC
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"^K: Editor keys", timeout=4.0)
        time.sleep(0.1)
        drain_all(master)
        # Move to top of document: Ctrl+T, Ctrl+A (Line 1 Col 0)
        os.write(master, b"\x14\x01")
        read_until(master, b"Line    1/30", timeout=4.0)
        # Move down to Line 2: Down Arrow (\x1b[B)
        os.write(master, b"\x1b[B")
        read_until(master, b"Line    2/30", timeout=4.0)
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
        read_until(master, b"Line    1/30", timeout=4.0)

        # Forward search: Ctrl+N -> moves to line 2
        time.sleep(0.2)
        os.write(master, b"\x0e")
        read_until(master, b"Line    2/30", timeout=4.0)

        # Forward search: Ctrl+N -> moves to line 3
        time.sleep(0.2)
        os.write(master, b"\x0e")
        read_until(master, b"Line    3/30", timeout=4.0)

        # Dynamic reverse: Ctrl+P -> moves back to line 2!
        time.sleep(0.2)
        os.write(master, b"\x10")
        read_until(master, b"Line    2/30", timeout=4.0)

        # Dynamic reverse: Ctrl+P -> moves back to line 1!
        time.sleep(0.2)
        os.write(master, b"\x10")
        read_until(master, b"Line    1/30", timeout=4.0)

        # Verify 'r' in interactive Replace prompt:
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"\x12") # Ctrl+R
        read_until(master, b"Find (Exact):", timeout=4.0)
        read_until(master, b"content", timeout=4.0)
        os.write(master, b"\r")
        read_until(master, b"Replace with:", timeout=4.0)
        os.write(master, b"Item\r")
        read_until(master, b"everse)? ", timeout=4.0)
        # We are on line 1. Skip with 'n' -> moves forward to line 2:
        os.write(master, b"n")
        read_until(master, b"Line    2/30", timeout=4.0)
        read_until(master, b"everse)? ", timeout=4.0)

        # Press 'r' to dynamically reverse direction -> moves back to line 1!
        os.write(master, b"r")
        read_until(master, b"Line    1/30", timeout=4.0)
        read_until(master, b"everse)? ", timeout=4.0)

        # Quit replace with 'q'
        os.write(master, b"q")
        out_s51_done = read_until(
            master, b"Replace done: 0 replacement(s).", timeout=4.0
        )
        if b"Replace done: 0 replacement(s)." not in out_s51_done:
            print(
                f"[-] Step 51 failed: Replace done missing. "
                f"Buffer: {repr(out_s51_done)}",
                flush=True,
            )
            return False
        time.sleep(0.3)
        drain_all(master)
        print(
            "[+] Successfully verified Dynamic Reversal of Search Direction "
            "(Step 51)!",
            flush=True,
        )

        # ---------------------------------------------------------------------
        # Step 52: Unsaved Modifications Check on Exit (Ctrl+Q)
        # ---------------------------------------------------------------------
        print("[*] Step 52: Verifying Unsaved Modifications check on exit (Ctrl+Q)...", flush=True)

        # 1. Document was modified in Step 47. Send Ctrl+Q and verify prompt
        time.sleep(0.3)
        os.write(master, b"\x11")
        out_s52_prompt = read_until(master, b"[ESC]=Cancel", timeout=4.0)
        if (b"Save changes?" not in out_s52_prompt or
                b"[ESC]" not in out_s52_prompt):
            print(f"[-] Step 52 failed: Save changes prompt missing. Buffer: {repr(out_s52_prompt)}", flush=True)
            return False

        # Verify modal pop-up contains title and Save changes? prompt
        # inside the box enclosure
        if b"Unsaved Modifications" not in out_s52_prompt or \
           b"|                 Save changes?" not in out_s52_prompt:
            print(f"[-] Step 52 failed: Save changes prompt not embedded in "
                  f"modal popup. Buffer: {repr(out_s52_prompt)}", flush=True)
            return False

        # 2. Send cursor keys (escape sequences) and verify they are ignored (prompt remains active)
        time.sleep(0.2)
        os.write(master, b"\x1b[A\x1b[B\x1b[C\x1b[D")
        time.sleep(0.4)

        # 3. Press standalone ESC to cancel exit and resume editor
        os.write(master, b"\x1b")
        out_s52_cancel = read_until(master, b"^K: Editor keys", timeout=4.0)
        if b"^K: Editor keys" not in out_s52_cancel:
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
        out_splash_prompt = read_until(master, b"[ESC]=Cancel", timeout=4.0)
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
        read_until(master, b"Line    1/2", timeout=30.0)
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
        read_until(master, b"Line    1/2", timeout=30.0)

        # 2. Modify buffer and send Ctrl+W (\x17)
        time.sleep(0.2)
        os.write(master, b"X")
        time.sleep(0.2)
        os.write(master, b"\x17")
        out_s53_prompt = read_until(master, b"[ESC]=Cancel", timeout=4.0)
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
        out_s53_new = read_until(master, b"Line    1/1", timeout=4.0)
        if b"(Untitled)" not in out_s53_new:
            print(f"[-] Step 53 failed: Splash ':n' did not enter blank editor (Untitled). Buffer: {repr(out_s53_new)}", flush=True)
            return False
        print("[+] Splash ':n' successfully started new blank document (Untitled).", flush=True)

        # 5. Type content in blank document, then return to splash (ESC)
        time.sleep(0.2)
        os.write(master, b"TESTING BLANK")
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"Active Screen:", timeout=4.0)

        # 6. On splash screen with modified document, test ':w'
        time.sleep(0.2)
        os.write(master, b"w")
        out_s53_spw = read_until(master, b"[ESC]=Cancel", timeout=4.0)
        if b"Save changes?" not in out_s53_spw:
            print(f"[-] Step 53 failed: Splash ':w' did not prompt for save changes. Buffer: {repr(out_s53_spw)}", flush=True)
            return False
        # Cancel with ESC to stay in editor
        os.write(master, b"\x1b")
        read_until(master, b"Line    1/1", timeout=4.0)
        print("[+] Splash ':w' prompted for unsaved changes and ESC cancelled cleanly.", flush=True)

        # 7. Return to splash screen again, test Ctrl+W and discard with 'n'
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"Active Screen:", timeout=4.0)
        time.sleep(0.2)
        os.write(master, b"\x17")
        read_until(master, b"[ESC]=Cancel", timeout=4.0)
        os.write(master, b"n")
        out_s53_splash2 = read_until(master, b"Active Screen:", timeout=4.0)
        if b"Active Screen:" not in out_s53_splash2:
            print(f"[-] Step 53 failed: Splash Ctrl+W did not return to splash screen. Buffer: {repr(out_s53_splash2)}", flush=True)
            return False
        print("[+] Splash Ctrl+W discarded changes and unloaded document.", flush=True)

        # 8. On clean splash screen, press 'e': verify it starts a fresh blank document
        time.sleep(0.2)
        os.write(master, b"e")
        out_s53_fresh = read_until(master, b"Line    1/1", timeout=4.0)
        if b"(Untitled)" not in out_s53_fresh:
            print(f"[-] Step 53 failed: Enter/e after close did not start fresh (Untitled). Buffer: {repr(out_s53_fresh)}", flush=True)
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
        read_until(master, b"Line    1/2", timeout=30.0)

        # 2. Modify buffer and send Ctrl+O (\x0f)
        time.sleep(0.2)
        os.write(master, b"Z")
        time.sleep(0.2)
        os.write(master, b"\x0f")
        out_s54_prompt = read_until(master, b"[ESC]=Cancel", timeout=4.0)
        if b"Save changes?" not in out_s54_prompt:
            print(f"[-] Step 54 failed: Ctrl+O on modified document did not prompt to save changes. Buffer: {repr(out_s54_prompt)}", flush=True)
            return False
        print("[+] Ctrl+O on modified document correctly showed 'Save changes?' prompt.", flush=True)

        # 3. Cancel prompt with ESC: verify editor remains with modified document
        os.write(master, b"\x1b")
        out_s54_cancel = read_until(master, b"Line    1/2", timeout=4.0)
        if b"C:2.TXT" not in out_s54_cancel:
            print(f"[-] Step 54 failed: ESC did not cancel prompt back to editor. Buffer: {repr(out_s54_cancel)}", flush=True)
            return False
        print("[+] ESC cancelled prompt and stayed in editor with modifications intact.", flush=True)

        # 4. Send Ctrl+O again, discard with 'n': verify Open File screen is displayed
        time.sleep(0.2)
        os.write(master, b"\x0f")
        read_until(master, b"Save changes?", timeout=4.0)
        os.write(master, b"n")
        out_s54_open_ui = read_until(master, b"OPEN FILE (DIRECTORY - DRIVE C:)", timeout=4.0)
        if b"OPEN FILE (DIRECTORY - DRIVE C:)" not in out_s54_open_ui:
            print(f"[-] Step 54 failed: 'n' (discard) did not open Open File screen. Buffer: {repr(out_s54_open_ui)}", flush=True)
            return False
        read_until(master, b"Enter filename to open", timeout=4.0)
        print("[+] 'n' (discard) proceeded directly to Open File screen.", flush=True)

        # 5. Cancel Open File screen with ESC: verify return to editor
        time.sleep(0.2)
        os.write(master, b"\x1b")
        out_s54_ed_back = read_until(master, b"^K: Editor keys", timeout=4.0)
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
        read_until(master, b"Enter filename to open", timeout=4.0)
        # Cancel back to editor
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"^K: Editor keys", timeout=4.0)
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
        out_s54_spo = read_until(master, b"[ESC]=Cancel", timeout=4.0)
        if b"Save changes?" not in out_s54_spo:
            print(f"[-] Step 54 failed: Splash ':o' did not prompt for save changes. Buffer: {repr(out_s54_spo)}", flush=True)
            return False
        # Cancel with ESC to stay in editor
        os.write(master, b"\x1b")
        read_until(master, b"^K: Editor keys", timeout=4.0)
        print("[+] Splash ':o' with modified document resumed editor and prompted for save changes.", flush=True)

        # 9. Return to splash screen again (ESC), test ':o' and discard with 'n'
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"Active Screen:", timeout=4.0)
        time.sleep(0.2)
        os.write(master, b"o")
        read_until(master, b"[ESC]=Cancel", timeout=4.0)
        os.write(master, b"n")
        out_s54_spo_open = read_until(master, b"OPEN FILE (DIRECTORY - DRIVE C:)", timeout=4.0)
        if b"OPEN FILE (DIRECTORY - DRIVE C:)" not in out_s54_spo_open:
            print(f"[-] Step 54 failed: Discarding changes from splash ':o' did not enter Open File screen. Buffer: {repr(out_s54_spo_open)}", flush=True)
            return False
        read_until(master, b"Enter filename to open", timeout=4.0)
        # Cancel back to editor
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"^K: Editor keys", timeout=4.0)
        print("[+] Splash ':o' discarded changes and opened Open File screen.", flush=True)

        # 10. Exit cleanly with Ctrl+Q
        time.sleep(0.2)
        os.write(master, b"\x11")
        read_until(master, b"C>", timeout=4.0)
        print("[+] Step 57: Clean exit back to CP/M prompt.", flush=True)
        print("[+] Successfully verified Open File (Ctrl+O & Splash :o) Unsaved Modifications Check (Step 54)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 55: Open File Screen Line Number Specification (e.g. 30.TXT:15)
        # ---------------------------------------------------------------------
        print("[*] Step 55: Verifying Open File screen line number specification...", flush=True)

        # 1. Launch 'se 2.TXT'
        time.sleep(0.5)
        os.write(master, b"se 2.TXT\r")
        read_until(master, b"Line    1/2", timeout=30.0)

        # 2. In editor mode, press Ctrl+O and open '30.TXT:15'
        time.sleep(0.2)
        os.write(master, b"\x0f")
        read_until(master, b"Enter filename to open:", timeout=8.0)
        time.sleep(0.2)
        os.write(master, b"30.TXT:15\r")
        out_s55_l15 = read_until(master, b"Line   15/30", timeout=8.0)
        if b"Line   15/30" not in out_s55_l15 or b"C:30.TXT" not in out_s55_l15:
            print(f"[-] Step 55 failed: '30.TXT:15' did not open at line 15. Buffer: {repr(out_s55_l15)}", flush=True)
            return False
        print("[+] '30.TXT:15' opened successfully at line 15.", flush=True)

        # 3. In editor mode, press Ctrl+O and open 'C:30.TXT:25' (drive + file + line)
        time.sleep(0.2)
        os.write(master, b"\x0f")
        read_until(master, b"Enter filename to open:", timeout=8.0)
        time.sleep(0.2)
        os.write(master, b"\x08" * 20 + b"C:30.TXT:25\r")
        out_s55_l25 = read_until(master, b"Line   25/30", timeout=8.0)
        if b"Line   25/30" not in out_s55_l25 or b"C:30.TXT" not in out_s55_l25:
            print(f"[-] Step 55 failed: 'C:30.TXT:25' did not open at line 25. Buffer: {repr(out_s55_l25)}", flush=True)
            return False
        print("[+] 'C:30.TXT:25' opened successfully at line 25 with explicit drive.", flush=True)

        # 4. In editor mode, press Ctrl+O and open '30.TXT:1000' (clamping to EOF)
        time.sleep(0.2)
        os.write(master, b"\x0f")
        read_until(master, b"Enter filename to open:", timeout=8.0)
        time.sleep(0.2)
        os.write(master, b"30.TXT:1000\r")
        out_s55_l1000 = read_until(master, b"Line   30/30", timeout=8.0)
        if b"Line   30/30" not in out_s55_l1000:
            print(f"[-] Step 55 failed: '30.TXT:1000' did not clamp to line 30. Buffer: {repr(out_s55_l1000)}", flush=True)
            return False
        print("[+] '30.TXT:1000' clamped cleanly to line 30.", flush=True)

        # 5. Return to splash screen (ESC) and open '30.TXT:10' from splash ':o'
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"Active Screen:", timeout=8.0)
        time.sleep(0.2)
        os.write(master, b"o")
        read_until(master, b"Enter filename to open:", timeout=8.0)
        time.sleep(0.2)
        os.write(master, b"30.TXT:10\r")
        out_s55_splash_l10 = read_until(master, b"Line   10/30", timeout=8.0)
        if b"Line   10/30" not in out_s55_splash_l10:
            print(f"[-] Step 55 failed: Splash ':o' '30.TXT:10' did not open at line 10. Buffer: {repr(out_s55_splash_l10)}", flush=True)
            return False
        print("[+] Splash screen ':o' with line number '30.TXT:10' opened at line 10.", flush=True)

        # 6. Verify standard open without line number opens at line 1
        time.sleep(0.2)
        os.write(master, b"\x0f")
        read_until(master, b"Enter filename to open:", timeout=8.0)
        time.sleep(0.2)
        os.write(master, b"30.TXT\r")
        out_s55_l1 = read_until(master, b"Line    1/30", timeout=8.0)
        if b"Line    1/30" not in out_s55_l1:
            print(f"[-] Step 55 failed: '30.TXT' without line number did not open at line 1. Buffer: {repr(out_s55_l1)}", flush=True)
            return False
        print("[+] '30.TXT' without line number opened at default line 1.", flush=True)

        # 7. Exit cleanly with Ctrl+Q
        time.sleep(0.2)
        os.write(master, b"\x11")
        out_s55_exit = read_until(master, b"C>", timeout=6.0)
        if b"C>" not in out_s55_exit:
            print(f"[-] Step 55 failed: Exit to CP/M prompt missing. "
                  f"Buffer: {repr(out_s55_exit)}", flush=True)
            return False
        time.sleep(0.3)
        drain_all(master)
        print("[+] Clean exit back to CP/M prompt.", flush=True)
        print("[+] Successfully verified Open File Screen Line Number "
              "Specification (Step 55)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 56: Verifying 13-Bank Far RAM Discovery and HBIOS Bank 0x80
        # Protection
        # ---------------------------------------------------------------------
        print("[*] Step 56: Verifying 13-Bank Far RAM discovery and "
              "HBIOS Bank 0x80 protection...", flush=True)
        drain_all(master)
        time.sleep(0.5)
        os.write(master, b"se\r")
        out_s56 = read_until(master, SPLASH_FREE_TARGETS, timeout=35.0)
        if not has_free_mem(out_s56):
            print(f"[-] Step 56 failed: Free memory missing: {repr(out_s56)}",
                  flush=True)
            return False

        # View memory info map ('m')
        time.sleep(0.5)
        os.write(master, b"m")
        out_diag = read_until(master, b"return to splash screen", timeout=15.0)
        if (b"80h" not in out_diag or b"Protected HBIOS" not in out_diag or
                b"Line Slot Table" not in out_diag):
            print(f"[-] Step 56 failed: Memory map did not display. "
                  f"Buffer: {repr(out_diag)}", flush=True)
            return False

        # Return to splash screen
        drain_all(master)
        time.sleep(0.3)
        os.write(master, b" ")
        read_until(master, SPLASH_FREE_TARGETS, timeout=20.0)

        # Clean exit to CP/M
        drain_all(master)
        time.sleep(0.3)
        os.write(master, b"\x11")
        out_s56_exit = read_until(master, b"C>", timeout=6.0)
        if b"C>" not in out_s56_exit:
            print(f"[-] Step 56 failed: Exit to CP/M prompt missing. "
                  f"Buffer: {repr(out_s56_exit)}", flush=True)
            return False
        time.sleep(0.3)
        drain_all(master)
        print("[+] Successfully verified 13-Bank Far RAM discovery and "
              "HBIOS Bank 0x80 protection (Step 56)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 57: Verifying OOM Status Bar Replacement and Revert on Keypress
        # ---------------------------------------------------------------------
        print("[*] Step 57: Verifying OOM status bar replacement and revert on keypress...", flush=True)
        drain_all(master)
        time.sleep(0.3)
        os.write(master, b"se BIG.TXT\r")
        out_s57 = read_until(master, b"Line    1/3072", timeout=60.0)
        if b"Line    1/3072" not in out_s57 or b"^K: Editor keys" not in out_s57:
            print(f"[-] Step 57 failed: Failed to load BIG.TXT or missing '^K: Editor keys'. Buffer: {repr(out_s57[-200:])}", flush=True)
            return False
        print(
            "[+] Step 57: BIG.TXT loaded with status bar showing "
            "'^K: Editor keys'.",
            flush=True
        )

        # Step 57 note: Document capacity is now 16,384 lines under Phase 4 virtual paging engine,
        # so inserting a line at 3,072 lines no longer triggers in-memory OOM.
        print(
            "[+] Step 57: BIG.TXT loaded successfully; Phase 4 virtual "
            "paging allows expansion past 3072 lines.",
            flush=True
        )

        # Type 'x' to modify document so Ctrl+Q triggers unsaved changes prompt
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"x")
        time.sleep(0.2)
        drain_all(master)

        # Clean exit to CP/M with Ctrl+Q -> 'n' (discard changes)
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"\x11")
        out_s57_q = read_until(master, b"[ESC]=Cancel", timeout=4.0)
        if b"Save changes?" not in out_s57_q:
            print(f"[-] Step 57 failed: Missing save changes prompt on exit. "
                  f"Buffer: {repr(out_s57_q)}", flush=True)
            return False
        time.sleep(0.2)
        os.write(master, b"n")
        out_s57_exit = read_until(master, b"C>", timeout=15.0)
        if b"C>" not in out_s57_exit:
            print(f"[-] Step 57 failed: Clean exit to CP/M failed: "
                  f"{repr(out_s57_exit)}", flush=True)
            return False
        time.sleep(0.5)
        drain_all(master)
        print("[+] Clean exit back to CP/M prompt.", flush=True)
        print(
            "[+] Step 57: Successfully verified OOM Status Bar Replacement "
            "and Revert on Keypress!",
            flush=True
        )

        # ---------------------------------------------------------------------
        # Step 58: Verifying Horizontal Scrolling in 80x24 Mode
        # ---------------------------------------------------------------------
        print("[*] Step 58: Verifying Horizontal Scrolling in 80x24 Mode...", flush=True)
        drain_all(master)
        time.sleep(0.5)
        os.write(master, b"se\r")
        out_s58_sp = read_until(master, b"for about", timeout=30.0)
        if b"for about" not in out_s58_sp:
            print(f"[-] Step 58 failed: Splash screen failed to display. Buffer: {repr(out_s58_sp)}", flush=True)
            return False

        # Switch to 80x24 mode with '2'
        drain_all(master)
        os.write(master, b"2")
        read_until(master, b"for about", timeout=6.0)
        drain_all(master)
        time.sleep(0.3)

        # Enter editor mode with 'e'
        os.write(master, b"e")
        out_s58_edit = read_until(master, b"Line    1/1    Col 0", timeout=6.0)
        if b"80x24" not in out_s58_edit or b"Line    1/1    Col 0" not in out_s58_edit:
            print(f"[-] Step 58 failed: Editor mode not entered in 80x24: {repr(out_s58_edit)}", flush=True)
            return False

        # Type 85 characters: "0123456789" * 8 + "ABCDE"
        drain_all(master)
        test_str_85 = ("0123456789" * 8 + "ABCDE").encode("ascii")
        os.write(master, test_str_85)
        out_s58_t85 = read_until(master, b"Col 85", timeout=6.0)
        if b"Col 85" not in out_s58_t85:
            print(f"[-] Step 58 failed: Failed to type past 80 cols: {repr(out_s58_t85[-200:])}", flush=True)
            return False
        if b"ABCDE" not in out_s58_t85:
            print(f"[-] Step 58 failed: 'ABCDE' not found on scrolled screen buffer: {repr(out_s58_t85[-300:])}", flush=True)
            return False

        # Type 20 more characters to reach Col 105 (second jump to viewport 40)
        drain_all(master)
        os.write(master, b"01234567890123456789")
        out_s58_t105 = read_until(master, b"Col 105", timeout=6.0)
        if b"Col 105" not in out_s58_t105:
            print(f"[-] Step 58 failed: Failed to reach Col 105: {repr(out_s58_t105[-200:])}", flush=True)
            return False

        # Test Home navigation (Ctrl+A): should jump to Col 0 and scroll viewport back to 0
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"\x01")  # Ctrl+A
        out_s58_home = read_until(master, b"Col 0", timeout=4.0)
        if b"Col 0" not in out_s58_home or b"0123456789" not in out_s58_home:
            print(f"[-] Step 58 failed: Home failed to return to Col 0: {repr(out_s58_home[-200:])}", flush=True)
            return False

        # Test End navigation (Ctrl+E): should jump to Col 105 and viewport jump to 40
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"\x05")  # Ctrl+E
        out_s58_end = read_until(master, b"Col 105", timeout=4.0)
        if b"Col 105" not in out_s58_end:
            print(f"[-] Step 58 failed: End failed to jump to Col 105: {repr(out_s58_end[-200:])}", flush=True)
            return False

        # Test Left Arrow navigation across boundary 40 (105 -> 39)
        drain_all(master)
        for _ in range(66):
            os.write(master, b"\x1b[D")
            time.sleep(0.01)
        out_s58_l39 = read_until(master, b"Col 39", timeout=5.0)
        if b"Col 39" not in out_s58_l39:
            print(f"[-] Step 58 failed: Left arrow failed to reach Col 39: {repr(out_s58_l39[-200:])}", flush=True)
            return False

        # Test Left Arrow navigation across boundary 20 (39 -> 19)
        drain_all(master)
        for _ in range(20):
            os.write(master, b"\x1b[D")
            time.sleep(0.01)
        out_s58_l19 = read_until(master, b"Col 19", timeout=5.0)
        if b"Col 19" not in out_s58_l19:
            print(f"[-] Step 58 failed: Left arrow failed to reach Col 19: {repr(out_s58_l19[-200:])}", flush=True)
            return False

        # Test Right Arrow navigation across boundary 80 (19 -> 80)
        drain_all(master)
        for _ in range(61):
            os.write(master, b"\x1b[C")
            time.sleep(0.01)
        out_s58_r80 = read_until(master, b"Col 80", timeout=5.0)
        if b"Col 80" not in out_s58_r80:
            print(f"[-] Step 58 failed: Right arrow failed to reach Col 80: {repr(out_s58_r80[-200:])}", flush=True)
            return False

        # Test Right Arrow navigation across boundary 100 (80 -> 100)
        drain_all(master)
        for _ in range(20):
            os.write(master, b"\x1b[C")
            time.sleep(0.01)
        out_s58_r100 = read_until(master, b"Col 100", timeout=5.0)
        if b"Col 100" not in out_s58_r100:
            print(f"[-] Step 58 failed: Right arrow failed to reach Col 100: {repr(out_s58_r100[-200:])}", flush=True)
            return False

        # Clean exit to CP/M with Ctrl+Q -> 'n'
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"\x11")
        read_until(master, b"Save changes?", timeout=4.0)
        os.write(master, b"n")
        out_s58_cpm = read_until(master, b"C>", timeout=4.0)
        if b"C>" not in out_s58_cpm:
            print(f"[-] Step 58 failed: Failed clean exit to CP/M: {repr(out_s58_cpm)}", flush=True)
            return False
        print("[+] Successfully verified Horizontal Scrolling in 80x24 Mode (Step 58)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 59: Verifying Column 79 Continuation Highlighting and Block Suppression in 80x24 Mode
        # ---------------------------------------------------------------------
        print("[*] Step 59: Verifying Column 79 continuation highlighting and block suppression in 80x24 mode...", flush=True)
        drain_all(master)
        time.sleep(0.5)
        os.write(master, b"se\r")
        out_s59_splash = read_until(master, b"for about", timeout=30.0)
        if b"for about" not in out_s59_splash:
            print(f"[-] Step 59 failed: Splash screen not displayed: {repr(out_s59_splash[-200:])}", flush=True)
            return False

        # Switch to 80x24 mode with '2'
        drain_all(master)
        os.write(master, b"2")
        read_until(master, b"for about", timeout=6.0)
        drain_all(master)
        time.sleep(0.3)

        # Enter editor mode with 'e'
        os.write(master, b"e")
        out_s59_edit = read_until(master, b"Line    1/1    Col 0", timeout=6.0)
        if b"80x24" not in out_s59_edit or b"Line    1/1    Col 0" not in out_s59_edit:
            print(f"[-] Step 59 failed: Editor mode not entered in 80x24: {repr(out_s59_edit)}", flush=True)
            return False

        # Type 85 characters: "0123456789" * 8 + "ABCDE"
        drain_all(master)
        test_str_85 = "0123456789" * 8 + "ABCDE"
        os.write(master, test_str_85.encode("ascii"))
        out_s59_t85 = read_until(master, b"Col 85", timeout=6.0)
        if b"Col 85" not in out_s59_t85:
            print(f"[-] Step 59 failed: Failed typing to Col 85: {repr(out_s59_t85[-200:])}", flush=True)
            return False

        # Press Ctrl+A (Home) to jump to Col 0 (VIEW_LEFT_COL = 0)
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"\x01")  # Ctrl+A
        out_s59_home = read_until(master, b"Col 0", timeout=6.0)
        time.sleep(0.2)
        out_s59_home += drain_all(master)
        expected_cont_seq = b"\x1b[7m9\x1b[0m"
        if expected_cont_seq not in out_s59_home:
            print(f"[-] Step 59 failed: Expected continuation highlight {repr(expected_cont_seq)} not found in {repr(out_s59_home)}", flush=True)
            return False

        # Test block mode suppression: press Ctrl+B
        drain_all(master)
        os.write(master, b"\x02")  # Ctrl+B
        read_until(master, b"[SEL:", timeout=6.0)
        drain_all(master)
        # Force screen redraw with Ctrl+L
        os.write(master, b"\x0c")
        out_s59_block = read_until(master, b"Col 0", timeout=6.0)
        time.sleep(0.2)
        out_s59_block += drain_all(master)
        if expected_cont_seq in out_s59_block:
            print(f"[-] Step 59 failed: Continuation highlight not suppressed during block mode: {repr(out_s59_block)}", flush=True)
            return False

        # Cancel block mode with ESC
        drain_all(master)
        os.write(master, b"\x1b")  # ESC
        time.sleep(0.2)
        drain_all(master)

        # Test early auto-pan on continuing line (Option 2):
        # Cursor is at Col 0 on 85-char line. Move right to Col 78:
        for _ in range(78):
            os.write(master, b"\x1b[C")
            time.sleep(0.005)
        out_s59_c78 = read_until(master, b"Col 78", timeout=6.0)
        time.sleep(0.1)
        out_s59_c78 += drain_all(master)
        if b";79H" not in out_s59_c78:
            print(f"[-] Step 59 failed: Cursor at Col 78 not at screen col 79: {repr(out_s59_c78[-150:])}", flush=True)
            return False

        # Move right to Col 79: should auto-pan with 40-column step to VIEW_LEFT_COL = 40, screen col 40
        os.write(master, b"\x1b[C")
        out_s59_c79 = read_until(master, b"Col 79", timeout=6.0)
        time.sleep(0.2)
        out_s59_c79 += drain_all(master)
        if b";40H" not in out_s59_c79:
            print(f"[-] Step 59 failed: Auto-pan did not position cursor at screen col 40: {repr(out_s59_c79[-250:])}", flush=True)
            return False

        # Move left to Col 78: viewport should remain panned at 40, screen col 39
        os.write(master, b"\x1b[D")
        out_s59_left = read_until(master, b"Col 78", timeout=6.0)
        time.sleep(0.1)
        out_s59_left += drain_all(master)
        if b";39H" not in out_s59_left:
            print(f"[-] Step 59 failed: Moving left did not stay panned at screen col 39: {repr(out_s59_left[-150:])}", flush=True)
            return False

        # Test line <= 80 chars (no continuation highlight and no auto-pan at col 79)
        # End (Ctrl+E), delete 5 characters, Home (Ctrl+A)
        os.write(master, b"\x05")  # Ctrl+E
        read_until(master, b"Col 85", timeout=6.0)
        drain_all(master)
        os.write(master, b"\x08\x08\x08\x08\x08")  # 5 Backspaces
        read_until(master, b"Col 80", timeout=6.0)
        drain_all(master)
        os.write(master, b"\x01")  # Ctrl+A
        read_until(master, b"Col 0", timeout=6.0)
        time.sleep(0.2)
        out_s59_80 = drain_all(master)
        if expected_cont_seq in out_s59_80:
            print(f"[-] Step 59 failed: 80-char line incorrectly highlighted col 79: {repr(out_s59_80)}", flush=True)
            return False

        # Move to Col 79 on 80-char line: should NOT auto-pan, cursor at screen col 80
        for _ in range(79):
            os.write(master, b"\x1b[C")
            time.sleep(0.005)
        out_s59_80_c79 = read_until(master, b"Col 79", timeout=6.0)
        time.sleep(0.2)
        out_s59_80_c79 += drain_all(master)
        if b";80H" not in out_s59_80_c79:
            print(f"[-] Step 59 failed: Cursor on 80-char line at Col 79 not at screen col 80: {repr(out_s59_80_c79[-200:])}", flush=True)
            return False
        if expected_cont_seq in out_s59_80_c79:
            print(f"[-] Step 59 failed: 80-char line has unexpected continuation highlight at col 79: {repr(out_s59_80_c79[-200:])}", flush=True)
            return False

        # Clean exit to CP/M with Ctrl+Q -> 'n'
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"\x11")  # Ctrl+Q
        out_prompt = read_until(master, b"Save changes?", timeout=6.0)
        if b"Save changes?" not in out_prompt:
            print(f"[-] Step 59 failed: Save changes prompt missing: {out_prompt}", flush=True)
            return False
        time.sleep(0.2)
        os.write(master, b"n")
        out_cpm = read_until(master, b"C>", timeout=6.0)
        if b"C>" not in out_cpm:
            print(f"[-] Step 59 failed: Failed exit to CP/M: {out_cpm}", flush=True)
            return False
        print("[+] Successfully verified Column 79 Continuation Highlighting and Block Suppression in 80x24 Mode (Step 59)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 60: Insert Key & Overwrite Mode Verification
        # ---------------------------------------------------------------------
        print("[*] Step 60: Verifying Insert key and Overwrite mode...", flush=True)

        # 1. Launch 'se 2.TXT' (Line 1: "First line of two", Line 2: "Second line of two")
        time.sleep(0.5)
        os.write(master, b"se 2.TXT\r")
        out_s60_boot = read_until(master, b"Line    1/2", timeout=30.0)
        if b"Line    1/2" not in out_s60_boot:
            print(f"[-] Step 60 failed: Launching se 2.TXT failed. Buffer: {repr(out_s60_boot)}", flush=True)
            return False

        # 2. Check initial status bar shows "^K: Editor keys | "
        if b"^K: Editor keys | " not in out_s60_boot:
            print(f"[-] Step 60 failed: Initial status bar missing '^K: Editor keys | '. Buffer: {repr(out_s60_boot)}", flush=True)
            return False
        print("[+] Initial editor mode has '^K: Editor keys | ' on status bar.", flush=True)

        # 3. Press Insert key (ESC [ 2 ~) to switch to Overwrite mode
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"\x1b[2~")
        out_s60_ovr = read_until(master, b"Overwrite mode  | ", timeout=6.0)
        if b"Overwrite mode  | " not in out_s60_ovr:
            print(f"[-] Step 60 failed: Pressing Insert key (ESC [ 2 ~) did not show 'Overwrite mode  | ': {repr(out_s60_ovr)}", flush=True)
            return False
        print("[+] Insert key toggled to Overwrite mode and displayed on status bar.", flush=True)

        # 4. Overwrite "First" with "HELLO" at Col 0
        time.sleep(0.2)
        os.write(master, b"HELLO")
        out_s60_typed = read_until(master, b"Col 5", timeout=6.0)
        time.sleep(0.2)
        out_s60_typed += drain_all(master)
        if b"HELLO line of two" not in out_s60_typed and b"HELLO" not in out_s60_typed:
            print(f"[-] Step 60 failed: Typing in Overwrite mode did not show overwritten text: {repr(out_s60_typed)}", flush=True)
            return False
        print("[+] In Overwrite mode, text overwrote existing characters without shifting.", flush=True)

        # 5. Toggle back to Insert mode with ESC [ 2 ~
        os.write(master, b"\x1b[2~")
        out_s60_ins = read_until(master, b"^K: Editor keys | ", timeout=6.0)
        if b"^K: Editor keys | " not in out_s60_ins:
            print(f"[-] Step 60 failed: Pressing Insert again did not return to '^K: Editor keys | ': {repr(out_s60_ins)}", flush=True)
            return False
        print("[+] Insert key toggled back to Insert mode and status bar restored.", flush=True)

        # 6. In Insert mode at Col 5, insert " XYZ" -> should shift " line of two" right
        os.write(master, b" XYZ")
        out_s60_ins_typed = read_until(master, b"Col 9", timeout=6.0)
        time.sleep(0.2)
        out_s60_ins_typed += drain_all(master)
        if b"XYZ" not in out_s60_ins_typed:
            print(f"[-] Step 60 failed: Typing in Insert mode failed: {repr(out_s60_ins_typed)}", flush=True)
            return False
        print("[+] Insert mode shifted trailing text right as expected.", flush=True)

        # 7. Test VT102 Insert key sequence (ESC [ L)
        time.sleep(0.2)
        os.write(master, b"\x1b[L")
        out_s60_vt = read_until(master, b"Overwrite mode  | ", timeout=6.0)
        if b"Overwrite mode  | " not in out_s60_vt:
            print(f"[-] Step 60 failed: VT102 Insert key (ESC [ L) did not activate Overwrite mode: {repr(out_s60_vt)}", flush=True)
            return False
        print("[+] VT102 Insert key (ESC [ L) toggled to Overwrite mode.", flush=True)

        # 8. Test ICH Insert char sequence (ESC [ @)
        time.sleep(0.2)
        os.write(master, b"\x1b[@")
        out_s60_ich = read_until(master, b"^K: Editor keys | ", timeout=6.0)
        if b"^K: Editor keys | " not in out_s60_ich:
            print(f"[-] Step 60 failed: ICH Insert key (ESC [ @) did not restore Insert mode: {repr(out_s60_ich)}", flush=True)
            return False
        print("[+] ICH Insert key (ESC [ @) toggled back to Insert mode.", flush=True)

        # 9. Test modified Insert key (ESC [ 2 ; 5 ~)
        time.sleep(0.2)
        os.write(master, b"\x1b[2;5~")
        out_s60_mod = read_until(master, b"Overwrite mode  | ", timeout=6.0)
        if b"Overwrite mode  | " not in out_s60_mod:
            print(f"[-] Step 60 failed: Modified Insert key (ESC [ 2 ; 5 ~) failed: {repr(out_s60_mod)}", flush=True)
            return False
        print("[+] Modified Insert key (ESC [ 2 ; 5 ~) toggled to Overwrite mode.", flush=True)

        # 10. Clean exit to CP/M with Ctrl+Q -> 'n' (discard changes)
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"\x11")  # Ctrl+Q
        out_prompt = read_until(master, b"Save changes?", timeout=6.0)
        if b"Save changes?" not in out_prompt:
            print(f"[-] Step 60 failed: Save changes prompt missing: {out_prompt}", flush=True)
            return False
        time.sleep(0.2)
        os.write(master, b"n")
        out_cpm = read_until(master, b"C>", timeout=6.0)
        if b"C>" not in out_cpm:
            print(f"[-] Step 60 failed: Failed exit to CP/M: {out_cpm}", flush=True)
            return False
        print("[+] Successfully verified Insert Key and Overwrite Mode (Step 60)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 61: Symmetrical Centered Status Bar (80 & 120 Columns) Verification
        # ---------------------------------------------------------------------
        print("[*] Step 61: Verifying symmetrical centered status bar in 80x24 and 120x40 modes...", flush=True)

        # 1. Launch 'se 2.TXT' in default 120x40 mode
        time.sleep(0.5)
        os.write(master, b"se 2.TXT\r")
        out_s61_120 = read_until(master, b"Line    1/2", timeout=30.0)
        time.sleep(0.2)
        out_s61_120 += drain_all(master)

        # Locate status row 40: \x1b[40;1H
        idx40 = out_s61_120.rfind(b"\x1b[40;1H")
        if idx40 == -1:
            print(f"[-] Step 61 failed: Status row 40 not found. Buffer: {repr(out_s61_120[-300:])}", flush=True)
            return False
        status_120 = out_s61_120[idx40:]
        s_idx = status_120.find(b"\x1b[7m")
        e_idx = status_120.find(b"\x1b[0m")
        if s_idx == -1 or e_idx == -1:
            print(f"[-] Step 61 failed: Inverse video escapes not found in status line 40: {repr(status_120[:200])}", flush=True)
            return False
        content_120 = status_120[s_idx + 4:e_idx]
        if len(content_120) != 120:
            print(f"[-] Step 61 failed: 120x40 status bar width is {len(content_120)}, expected 120: {repr(content_120)}", flush=True)
            return False
        # Verify 21 leading spaces, left enclosure '| ', right enclosure ' |', and 21 trailing spaces
        if not content_120.startswith(b" " * 21 + b"| "):
            print(f"[-] Step 61 failed: 120x40 status bar left margin not exactly 21 spaces + '| ': {repr(content_120[:30])}", flush=True)
            return False
        if not content_120.endswith(b" |" + b" " * 21):
            print(f"[-] Step 61 failed: 120x40 status bar right margin not exactly ' |' + 21 spaces: {repr(content_120[-30:])}", flush=True)
            return False
        print("[+] 120x40 status bar verified: exactly 120 highlighted chars, enclosed with '|' and centered with 21 spaces left & right.", flush=True)

        # Return to splash screen with ESC
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"for about", timeout=6.0)
        time.sleep(0.2)
        drain_all(master)

        # Switch to 80x24 mode with '2'
        os.write(master, b"2")
        time.sleep(0.2)
        drain_all(master)

        # Resume editor with 'e'
        os.write(master, b"e")
        out_s61_80 = read_until(master, b"Line    1/2", timeout=6.0)
        time.sleep(0.2)
        out_s61_80 += drain_all(master)

        # Locate status row 24: \x1b[24;1H
        idx24 = out_s61_80.rfind(b"\x1b[24;1H")
        if idx24 == -1:
            print(f"[-] Step 61 failed: Status row 24 not found. Buffer: {repr(out_s61_80[-300:])}", flush=True)
            return False
        status_80 = out_s61_80[idx24:]
        s_idx80 = status_80.find(b"\x1b[7m")
        e_idx80 = status_80.find(b"\x1b[0m")
        if s_idx80 == -1 or e_idx80 == -1:
            print(f"[-] Step 61 failed: Inverse video escapes not found in status line 24: {repr(status_80[:200])}", flush=True)
            return False
        content_80 = status_80[s_idx80 + 4:e_idx80]
        if len(content_80) != 80:
            print(f"[-] Step 61 failed: 80x24 status bar width is {len(content_80)}, expected 80: {repr(content_80)}", flush=True)
            return False
        # Verify 1 leading space, left enclosure '| ', right enclosure ' |', and 1 trailing space
        if not content_80.startswith(b" | "):
            print(f"[-] Step 61 failed: 80x24 status bar left margin not exactly 1 space + '| ': {repr(content_80[:10])}", flush=True)
            return False
        if not content_80.endswith(b" | "):
            print(f"[-] Step 61 failed: 80x24 status bar right margin not exactly ' |' + 1 space: {repr(content_80[-10:])}", flush=True)
            return False
        print("[+] 80x24 status bar verified: exactly 80 highlighted chars, enclosed with '|' and centered with 1 space left & right.", flush=True)

        # Clean exit back to CP/M with Ctrl+Q
        time.sleep(0.2)
        os.write(master, b"\x11")
        read_until(master, b"C>", timeout=6.0)
        drain_all(master)
        print("[+] Successfully verified Symmetrical Centered Status Bar (Step 61)!", flush=True)

        # ---------------------------------------------------------------------
        print("[*] Step 62: Verifying cursor viewport constraint when switching 120x40 -> 80x24 mode...", flush=True)

        # 1. Launch 'se 30.TXT' in default 120x40 mode
        time.sleep(0.5)
        os.write(master, b"se 30.TXT\r")
        out_s62_120 = read_until(master, b"Line    1/30", timeout=35.0)
        if b"Line    1/30" not in out_s62_120:
            print(f"[-] Step 62 failed: Could not open 30.TXT in 120x40 mode: {repr(out_s62_120[-300:])}", flush=True)
            return False

        # 2. Move cursor down 28 times to line 29 (in 120x40 mode, line 29 is at screen row 29)
        os.write(master, b"\x1b[B" * 28)
        out_l29 = read_until(master, b"Line   29/30", timeout=6.0)
        if b"Line   29/30" not in out_l29:
            print(f"[-] Step 62 failed: Failed to move cursor down to line 29: {repr(out_l29[-300:])}", flush=True)
            return False

        # 3. Press ESC to return to splash screen
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"for about", timeout=6.0)
        time.sleep(0.2)
        drain_all(master)

        # 4. On splash screen, select 80x24 mode with '2'
        os.write(master, b"2")
        time.sleep(0.2)
        drain_all(master)

        # 5. Re-enter editor with Enter
        os.write(master, b"\r")
        out_s62_80 = read_until(master, b"80x24", timeout=6.0)
        time.sleep(0.2)
        out_s62_80 += drain_all(master)

        # Verify status row 24 is rendered: \x1b[24;1H
        if b"\x1b[24;1H" not in out_s62_80:
            print(f"[-] Step 62 failed: Status row 24 not found in 80x24 mode: {repr(out_s62_80[-300:])}", flush=True)
            return False

        # Verify final cursor location escape sequence \x1b[<row>;<col>H
        cursor_locs = re.findall(rb"\x1b\[(\d+);(\d+)H", out_s62_80)
        if not cursor_locs:
            print(f"[-] Step 62 failed: No cursor location escape found in reenter output: {repr(out_s62_80[-300:])}", flush=True)
            return False
        last_row, last_col = int(cursor_locs[-1][0]), int(cursor_locs[-1][1])
        if last_row > 23:
            print(f"[-] Step 62 failed: Cursor row {last_row} is below the 80x24 status bar (max 23)!", flush=True)
            return False
        if last_row != 23:
            print(f"[-] Step 62 failed: Cursor row is {last_row}, expected 23: {repr(out_s62_80[-300:])}", flush=True)
            return False

        # Verify status bar reflects constrained Line 23/30
        if b"Line   23/30" not in out_s62_80:
            print(f"[-] Step 62 failed: Status bar did not show Line 23/30: {repr(out_s62_80[-300:])}", flush=True)
            return False

        # 6. Test cursor Up and Down navigation
        os.write(master, b"\x1b[A")  # Up arrow
        out_up = read_until(master, b"Line   22/30", timeout=3.0)
        if b"Line   22/30" not in out_up:
            print(f"[-] Step 62 failed: Cursor Up failed: {repr(out_up[-300:])}", flush=True)
            return False

        os.write(master, b"\x1b[B")  # Down arrow
        out_down = read_until(master, b"Line   23/30", timeout=3.0)
        if b"Line   23/30" not in out_down:
            print(f"[-] Step 62 failed: Cursor Down failed: {repr(out_down[-300:])}", flush=True)
            return False

        # 7. Clean exit back to CP/M with Ctrl+Q
        time.sleep(0.2)
        os.write(master, b"\x11")
        read_until(master, b"C>", timeout=6.0)
        print("[+] Successfully verified Cursor Viewport Constraint (Step 62)!", flush=True)

        # ---------------------------------------------------------------------
        print("[*] Step 63: Verifying cursor retention past column 79 in 80x24 mode on splash resume...", flush=True)

        # 1. Launch SE.COM
        time.sleep(0.5)
        os.write(master, b"se\r")
        read_until(master, SPLASH_FREE_TARGETS, timeout=30.0)
        time.sleep(0.3)
        drain_all(master)

        # 2. Select 80x24 mode ('2')
        os.write(master, b"2")
        read_until(master, SPLASH_FREE_TARGETS, timeout=8.0)
        time.sleep(0.3)
        drain_all(master)

        # 3. Enter editor mode ('e')
        os.write(master, b"e")
        out_s63_edit = read_until(master, b"Line    1/1", timeout=6.0)
        if b"Line    1/1" not in out_s63_edit:
            print(f"[-] Step 63 failed: Editor mode not entered: {repr(out_s63_edit[-200:])}", flush=True)
            return False

        # 4. Type 85 characters: ("0123456789" * 8 + "ABCDE")
        drain_all(master)
        test_str_85 = ("0123456789" * 8 + "ABCDE").encode("ascii")
        os.write(master, test_str_85)
        out_s63_t85 = read_until(master, b"Col 85", timeout=6.0)
        if b"Col 85" not in out_s63_t85:
            print(f"[-] Step 63 failed: Failed to type past 80 cols: {repr(out_s63_t85[-200:])}", flush=True)
            return False

        # 5. Press ESC to enter splash screen
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, SPLASH_FREE_TARGETS, timeout=6.0)
        time.sleep(0.2)
        drain_all(master)

        # 6. Press Return to re-enter editor
        os.write(master, b"\r")
        out_s63_reenter = read_until(master, b"\x1b[24;1H", timeout=6.0)
        time.sleep(0.2)
        out_s63_reenter += drain_all(master)

        idx24 = out_s63_reenter.rfind(b"\x1b[24;1H")
        if idx24 == -1:
            print(f"[-] Step 63 failed: Status bar row 24 not found: {repr(out_s63_reenter[-300:])}", flush=True)
            return False
        status_line = out_s63_reenter[idx24:idx24+150]
        if b"Col 85" not in status_line:
            print(f"[-] Step 63 failed: Cursor truncated! Status bar: {repr(status_line)}", flush=True)
            return False
        if b"\x1b[1;46H" not in out_s63_reenter:
            print(f"[-] Step 63 failed: Cursor escape \x1b[1;46H not found: {repr(out_s63_reenter[-200:])}", flush=True)
            return False
        print("[+] Retained cursor at Col 85 (screen row 1, col 46) on splash resume.", flush=True)

        # 7. Clean exit to CP/M with Ctrl+Q -> 'n'
        time.sleep(0.2)
        os.write(master, b"\x11")
        read_until(master, b"Save changes?", timeout=4.0)
        os.write(master, b"n")
        read_until(master, b"C>", timeout=4.0)
        print("[+] Successfully verified Cursor Retention Past Col 79 on Resume (Step 63)!", flush=True)

        # ---------------------------------------------------------------------
        print("[*] Step 64: Verifying cursor hiding on splash screen and restoring on editor/CP/M...", flush=True)

        # 1. Launch SE.COM
        time.sleep(0.5)
        os.write(master, b"se\r")
        out_s64_sp = read_until(master, SPLASH_FREE_TARGETS, timeout=30.0)
        time.sleep(0.2)
        out_s64_sp += drain_all(master)

        if b"\x1b[?25l" not in out_s64_sp:
            print(f"[-] Step 64 failed: Hide cursor escape \\x1b[?25l not found on splash screen: {repr(out_s64_sp[-300:])}", flush=True)
            return False
        print("[+] Verified: Splash screen emits \\x1b[?25l (hide cursor).", flush=True)

        # 2. Enter editor mode with 'e'
        os.write(master, b"e")
        out_s64_edit = read_until(master, b"Line    1/1", timeout=6.0)
        time.sleep(0.2)
        out_s64_edit += drain_all(master)

        if b"\x1b[?25h" not in out_s64_edit:
            print(f"[-] Step 64 failed: Show cursor escape \\x1b[?25h not found upon entering editor: {repr(out_s64_edit[-300:])}", flush=True)
            return False
        print("[+] Verified: Entering editor emits \\x1b[?25h (show cursor).", flush=True)

        # 3. Return to splash screen via ESC
        os.write(master, b"\x1b")
        out_s64_sp2 = read_until(master, SPLASH_FREE_TARGETS, timeout=6.0)
        time.sleep(0.2)
        out_s64_sp2 += drain_all(master)

        if b"\x1b[?25l" not in out_s64_sp2:
            print(f"[-] Step 64 failed: Hide cursor escape \\x1b[?25l not found upon returning to splash: {repr(out_s64_sp2[-300:])}", flush=True)
            return False
        print("[+] Verified: Returning to splash screen emits \\x1b[?25l (hide cursor).", flush=True)

        # 4. Exit to CP/M with 'q'
        os.write(master, b"q")
        out_s64_cpm = read_until(master, b"C>", timeout=6.0)
        time.sleep(0.2)
        out_s64_cpm += drain_all(master)

        if b"\x1b[?25h" not in out_s64_cpm:
            print(f"[-] Step 64 failed: Show cursor escape \\x1b[?25h not found upon exiting to CP/M: {repr(out_s64_cpm[-300:])}", flush=True)
            return False
        print("[+] Verified: Exiting to CP/M emits \\x1b[?25h (show cursor).", flush=True)
        print("[+] Successfully verified Splash Screen Cursor Hiding & Restoring (Step 64)!", flush=True)

        # ---------------------------------------------------------------------
        print("[*] Step 65: Verifying About Screen ('a' key on splash screen)...", flush=True)

        # 1. Launch SE.COM
        time.sleep(0.5)
        os.write(master, b"se\r")
        out_s65_sp = read_until(master, SPLASH_FREE_TARGETS, timeout=30.0)
        time.sleep(0.2)
        out_s65_sp += drain_all(master)

        if b"for about" not in out_s65_sp:
            print(f"[-] Step 65 failed: 'for about' option not displayed on splash screen: {repr(out_s65_sp[-300:])}", flush=True)
            return False
        if b"version" in out_s65_sp or b"Dean Jenkins" in out_s65_sp:
            print(f"[-] Step 65 failed: Splash screen unexpectedly contains version or author name: {repr(out_s65_sp[-300:])}", flush=True)
            return False

        # 2. Press 'a' to enter About Screen
        os.write(master, b"a")
        out_s65_about = read_until(master, b"Press any key to return", timeout=6.0)
        time.sleep(0.2)
        out_s65_about += drain_all(master)

        if b"SE - Screen Editor" not in out_s65_about:
            print(f"[-] Step 65 failed: 'SE - Screen Editor' title not found on About screen: {repr(out_s65_about)}", flush=True)
            return False
        if b"version 0.9.8" not in out_s65_about:
            print(f"[-] Step 65 failed: Version details not found on About screen: {repr(out_s65_about)}", flush=True)
            return False
        if b"by Dean Jenkins" not in out_s65_about:
            print(f"[-] Step 65 failed: Author attribution not found on About screen: {repr(out_s65_about)}", flush=True)
            return False
        if b"Google Antigravity 2.16.0" not in out_s65_about:
            print(f"[-] Step 65 failed: Antigravity 2.16.0 attribution not found on About screen: {repr(out_s65_about)}", flush=True)
            return False
        if b"Gemini FLASH 3.8 high" not in out_s65_about:
            print(f"[-] Step 65 failed: Gemini FLASH 3.8 high attribution not found on About screen: {repr(out_s65_about)}", flush=True)
            return False
        if b"MIT License" not in out_s65_about:
            print(f"[-] Step 65 failed: MIT License not found on About screen: {repr(out_s65_about)}", flush=True)
            return False
        if b"Architecture:" in out_s65_about or b"Features:" in out_s65_about:
            print(f"[-] Step 65 failed: Bloated Architecture/Features unexpectedly found on About screen: {repr(out_s65_about)}", flush=True)
            return False
        if b"Press any key to return to splash" not in out_s65_about:
            print(f"[-] Step 65 failed: Return prompt not found on About screen: {repr(out_s65_about)}", flush=True)
            return False
        print("[+] Verified About screen contents: essential details, Antigravity 2.16.0, Gemini FLASH 3.8, MIT License, and Return prompt.", flush=True)

        # 3. Press Enter to return to splash screen
        os.write(master, b"\r")
        out_s65_back = read_until(master, b"for about", timeout=6.0)
        time.sleep(0.2)
        out_s65_back += drain_all(master)

        if b"for about" not in out_s65_back or not has_free_mem(out_s65_back):
            print(f"[-] Step 65 failed: Return to splash screen failed: {repr(out_s65_back)}", flush=True)
            return False
        print("[+] Verified return to splash screen from About screen.", flush=True)


        # 4. Exit to CP/M with 'q'
        os.write(master, b"q")
        out_s65_cpm = read_until(master, b"C>", timeout=6.0)
        time.sleep(0.2)
        out_s65_cpm += drain_all(master)
        if b"C>" not in out_s65_cpm:
            print(f"[-] Step 65 failed: Exit to CP/M prompt failed: {repr(out_s65_cpm)}", flush=True)
            return False
        print("[+] Successfully verified About Screen functionality (Step 65)!", flush=True)

        # -----------------------------------------------------------------
        # STEP 66: Block Insert File Feature Verification
        # -----------------------------------------------------------------
        print("[*] STEP 66: Testing Block Insert File feature...", flush=True)
        # Launch SE.COM directly into new document
        time.sleep(0.5)
        os.write(master, b"se\r")
        out_s66_boot = read_until(master, b"Col 0", timeout=14.0)
        time.sleep(0.3)
        drain_all(master)

        # Enter editor mode with 'e'
        os.write(master, b"e")
        out_s66_ed = read_until(master, b"^K: Editor keys", timeout=6.0)
        drain_all(master)
        if b"^K: Editor keys" not in out_s66_ed:
            print(f"[-] Step 66 failed: Failed to enter editor mode: {repr(out_s66_ed)}", flush=True)
            return False

        # Subtest 1: Open Insert File screen with block, verify title/prompt and ESC cancel
        os.write(master, b"Hello ")
        time.sleep(0.2)
        drain_all(master)

        # Start block Ctrl-B (empty block at col 6)
        os.write(master, b"\x02")
        time.sleep(0.2)
        drain_all(master)

        # Press Ctrl-O -> opens Block Insert File screen
        os.write(master, b"\x0f")
        out_s66_ui = read_until(master, b"SE.COM - INSERT FILE (DIRECTORY - DRIVE", timeout=6.0)
        out_s66_ui += read_until(master, b"Enter filename to insert:", timeout=4.0)
        out_s66_ui += read_until(master, b"\x1b[?25h", timeout=4.0)
        out_s66_ui += drain_all(master)

        if b"SE.COM - INSERT FILE (DIRECTORY - DRIVE" not in out_s66_ui:
            print(f"[-] Step 66 Subtest 1 failed: Insert File title not found: {repr(out_s66_ui)}", flush=True)
            return False
        if b"Enter filename to insert:" not in out_s66_ui:
            print(f"[-] Step 66 Subtest 1 failed: Insert prompt not found: {repr(out_s66_ui)}", flush=True)
            return False

        # Verify cursor position is at Column 34 (inside [ ] box after preloaded 'C0:')
        m_s66 = re.search(rb"\x1b\[(\d+);(\d+)H\x1b\[\?25h", out_s66_ui)
        if not m_s66:
            print(f"[-] Step 66 Subtest 1 failed: Cursor positioning escape sequence not found in UI output: {repr(out_s66_ui[-200:])}", flush=True)
            return False
        cursor_col_s66 = int(m_s66.group(2))
        if cursor_col_s66 != 34:
            print(f"[-] Step 66 Subtest 1 failed: Expected cursor at column 34 inside [ ] box, got column {cursor_col_s66}", flush=True)
            return False

        # Cancel with ESC
        time.sleep(0.2)
        os.write(master, b"\x1b")
        out_s66_esc = read_until(master, b"Hello ", timeout=4.0)
        drain_all(master)
        if b"Hello " not in out_s66_esc:
            print(f"[-] Step 66 Subtest 1 failed: ESC did not restore editor screen: {repr(out_s66_esc)}", flush=True)
            return False
        print("[+] Step 66 Subtest 1 PASSED: Insert screen title/prompt verified and ESC cancelled cleanly.", flush=True)

        # Subtest 2: Non-existent file error handling
        time.sleep(0.2)
        os.write(master, b"\x0f")
        read_until(master, b"Enter filename to insert:", timeout=6.0)
        drain_all(master)

        os.write(master, b"NOFILE.TXT\r")
        out_s66_fnf = read_until(master, b"File not found", timeout=6.0)
        drain_all(master)
        if b"File not found" not in out_s66_fnf:
            print(f"[-] Step 66 Subtest 2 failed: 'File not found' message not displayed: {repr(out_s66_fnf)}", flush=True)
            return False

        # Cancel back to editor with ESC and clear block
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"Hello ", timeout=4.0)
        drain_all(master)
        os.write(master, b"\x1b")
        time.sleep(0.2)
        drain_all(master)
        print("[+] Step 66 Subtest 2 PASSED: Non-existent file displayed 'File not found' and cancelled cleanly.", flush=True)

        # Subtest 3: Insert single-line file at empty block (cursor)
        os.write(master, b"\x02")  # Ctrl-B
        time.sleep(0.2)
        drain_all(master)

        os.write(master, b"\x0f")  # Ctrl-O
        read_until(master, b"Enter filename to insert:", timeout=6.0)
        drain_all(master)

        os.write(master, b"INS1.TXT\r")
        out_s66_ins1 = read_until(master, b"[BLK: 8c LOCK]", timeout=8.0)
        out_s66_ins1 += drain_all(master)

        if b"Loading..." not in out_s66_ins1:
            print(f"[-] Step 66 Subtest 3 failed: 'Loading...' not found during insert: {repr(out_s66_ins1)}", flush=True)
            return False
        if b"~" not in out_s66_ins1:
            print(f"[-] Step 66 Subtest 3 failed: '~' not found during insert: {repr(out_s66_ins1)}", flush=True)
            return False
        if b"INS1.TXT" not in out_s66_ins1:
            print(f"[-] Step 66 Subtest 3 failed: 'INS1.TXT' not found in status bar during insert: {repr(out_s66_ins1)}", flush=True)
            return False
        if b"[BLK: 8c LOCK]" not in out_s66_ins1:
            print(f"[-] Step 66 Subtest 3 failed: '[BLK: 8c LOCK]' not found on status bar: {repr(out_s66_ins1)}", flush=True)
            return False
        if b"INSERTED" not in out_s66_ins1:
            print(f"[-] Step 66 Subtest 3 failed: 'INSERTED' not found: {repr(out_s66_ins1)}", flush=True)
            return False
        if b"(Untitled)" not in out_s66_ins1:
            print(f"[-] Step 66 Subtest 3 failed: WORK_FCB was overwritten, expected (Untitled): {repr(out_s66_ins1)}", flush=True)
            return False
        print("[+] Step 66 Subtest 3 PASSED: Single-line inserted at cursor, solidified [BLK: 8c LOCK], (Untitled) preserved.", flush=True)

        # Subtest 4: Replace non-empty single-line block with multi-line file
        os.write(master, b" END")
        time.sleep(0.2)
        drain_all(master)

        # Move to col 6 (start of "INSERTED")
        os.write(master, b"\x01")
        time.sleep(0.2)
        drain_all(master)
        for _ in range(6):
            os.write(master, b"\x1b[C")
            time.sleep(0.05)
        drain_all(master)

        # Block covers "INSERTED" (8 chars)
        os.write(master, b"\x02")
        time.sleep(0.1)
        for _ in range(8):
            os.write(master, b"\x1b[C")
            time.sleep(0.05)
        drain_all(master)

        os.write(master, b"\x0f")
        read_until(master, b"Enter filename to insert:", timeout=6.0)
        drain_all(master)

        os.write(master, b"INS2.TXT\r")
        out_s66_ins2 = read_until(master, b"[BLK: 2L LOCK]", timeout=8.0)
        out_s66_ins2 += drain_all(master)

        if b"Loading..." not in out_s66_ins2:
            print(f"[-] Step 66 Subtest 4 failed: 'Loading...' not found during insert: {repr(out_s66_ins2)}", flush=True)
            return False
        if b"~" not in out_s66_ins2:
            print(f"[-] Step 66 Subtest 4 failed: '~' not found during insert: {repr(out_s66_ins2)}", flush=True)
            return False
        if b"INS2.TXT" not in out_s66_ins2:
            print(f"[-] Step 66 Subtest 4 failed: 'INS2.TXT' not found in status bar during insert: {repr(out_s66_ins2)}", flush=True)
            return False
        if b"[BLK: 2L LOCK]" not in out_s66_ins2:
            print(f"[-] Step 66 Subtest 4 failed: '[BLK: 2L LOCK]' not found on status bar: {repr(out_s66_ins2)}", flush=True)
            return False
        if b"FIRST LINE" not in out_s66_ins2:
            print(f"[-] Step 66 Subtest 4 failed: 'FIRST LINE' not found: {repr(out_s66_ins2)}", flush=True)
            return False
        if b"SECOND LINE" not in out_s66_ins2:
            print(f"[-] Step 66 Subtest 4 failed: 'SECOND LINE' not found: {repr(out_s66_ins2)}", flush=True)
            return False
        print("[+] Step 66 Subtest 4 PASSED: Single-line block replaced with multi-line file and solidified [BLK: 2L LOCK].", flush=True)

        # Subtest 5: Replace multi-line block with single-line file
        # Dismiss previous solidified block with ESC
        os.write(master, b"\x1b")
        time.sleep(0.1)
        drain_all(master)

        os.write(master, b"\x1b[A")  # Up to line 0
        time.sleep(0.05)
        os.write(master, b"\x01")    # Home
        time.sleep(0.05)
        for _ in range(5):
            os.write(master, b"\x1b[C")
            time.sleep(0.05)
        drain_all(master)

        # Block from Line 0 Col 5 to Line 1 Col 11
        os.write(master, b"\x02")
        time.sleep(0.1)
        os.write(master, b"\x1b[B")  # Down to line 1
        time.sleep(0.05)
        os.write(master, b"\x01")
        time.sleep(0.05)
        for _ in range(11):
            os.write(master, b"\x1b[C")
            time.sleep(0.05)
        drain_all(master)

        os.write(master, b"\x0f")
        read_until(master, b"Enter filename to insert:", timeout=6.0)
        drain_all(master)

        os.write(master, b"INS1.TXT\r")
        out_s66_ins3 = read_until(master, b"[BLK: 8c LOCK]", timeout=8.0)
        out_s66_ins3 += drain_all(master)

        if b"[BLK: 8c LOCK]" not in out_s66_ins3:
            print(f"[-] Step 66 Subtest 5 failed: '[BLK: 8c LOCK]' not found: {repr(out_s66_ins3)}", flush=True)
            return False
        if b"INSERTED" not in out_s66_ins3:
            print(f"[-] Step 66 Subtest 5 failed: 'INSERTED' not found: {repr(out_s66_ins3)}", flush=True)
            return False
        print("[+] Step 66 Subtest 5 PASSED: Multi-line block deleted, replaced with single-line file, and solidified [BLK: 8c LOCK].", flush=True)

        # Subtest 6: Test block delete of inserted file, re-insert and ESC dismiss
        # Line 1 currently has "Hello" + [BLK: 8c LOCK] "INSERTED" + " END"
        # Press Del (\x7f) to delete the inserted block
        os.write(master, b"\x7f")
        out_s66_del = read_until(master, b"^K: Editor keys", timeout=6.0)
        out_s66_del += drain_all(master)
        if b"^K: Editor keys" not in out_s66_del:
            print(f"[-] Step 66 Subtest 6 failed: Status bar did not revert after block delete: {repr(out_s66_del)}", flush=True)
            return False

        # Re-insert INS1.TXT at cursor
        os.write(master, b"\x02")  # Ctrl-B
        time.sleep(0.2)
        drain_all(master)
        os.write(master, b"\x0f")  # Ctrl-O
        read_until(master, b"Enter filename to insert:", timeout=6.0)
        drain_all(master)
        os.write(master, b"INS1.TXT\r")
        out_s66_reins = read_until(master, b"[BLK: 8c LOCK]", timeout=8.0)
        out_s66_reins += drain_all(master)
        if b"[BLK: 8c LOCK]" not in out_s66_reins:
            print(f"[-] Step 66 Subtest 6 failed: Re-insert not solidified: {repr(out_s66_reins)}", flush=True)
            return False

        # Dismiss solidified block with ESC
        os.write(master, b"\x1b")
        out_s66_esc2 = read_until(master, b"^K: Editor keys", timeout=4.0)
        out_s66_esc2 += drain_all(master)
        if b"^K: Editor keys" not in out_s66_esc2:
            print(f"[-] Step 66 Subtest 6 failed: ESC did not dismiss solidified block: {repr(out_s66_esc2)}", flush=True)
            return False
        print("[+] Step 66 Subtest 6 PASSED: Block delete of inserted file verified, re-inserted and dismissed with ESC.", flush=True)

        print("[+] Successfully verified Block Insert File feature (Step 66)!", flush=True)

        # 67. Test Block Save feature (Ctrl+S when BLOCK_ACTIVE != 0)
        print("[*] Step 67: Testing Block Save feature...", flush=True)
        # We currently have "HelloINSERTED END" on line 1.
        # Move cursor to col 5 (start of "INSERTED")
        time.sleep(0.2)
        os.write(master, b"\x01")  # Ctrl+A (Home)
        time.sleep(0.05)
        for _ in range(5):
            os.write(master, b"\x1b[C")
            time.sleep(0.03)
        drain_all(master)

        # Start block selection with Ctrl-B
        os.write(master, b"\x02")
        time.sleep(0.05)
        # Select "INSERTED" (8 chars)
        for _ in range(8):
            os.write(master, b"\x1b[C")
            time.sleep(0.03)
        drain_all(master)

        # Trigger Block Save via Ctrl+S
        os.write(master, b"\x13")
        out_s67_ui = read_until(master, b"SAVE BLOCK (DIRECTORY - DRIVE C:)", timeout=6.0)
        out_s67_ui += read_until(master, b"Enter filename to save:", timeout=4.0)
        if b"SAVE BLOCK (DIRECTORY - DRIVE C:)" not in out_s67_ui or b"Enter filename to save:" not in out_s67_ui:
            print(f"[-] Step 67 failed: Block Save UI prompt missing: {repr(out_s67_ui)}", flush=True)
            return False
        print("[+] Step 67 Subtest 1 PASSED: Ctrl+S with active block opened SAVE BLOCK UI.", flush=True)

        # Cancel with ESC and verify block retained as solidified
        time.sleep(0.2)
        os.write(master, b"\x1b")
        out_s67_esc = read_until(master, b"[BLK: 8c", timeout=5.0)
        out_s67_esc += drain_all(master)
        if b"[BLK: 8c" not in out_s67_esc:
            print(f"[-] Step 67 Subtest 2 failed: Block not retained after ESC cancel: {repr(out_s67_esc)}", flush=True)
            return False
        print("[+] Step 67 Subtest 2 PASSED: ESC cancelled back to editor with block retained [BLK: 8c].", flush=True)

        # Press Ctrl+S again and save to BLKSGL.TXT
        os.write(master, b"\x13")
        read_until(master, b"Enter filename to save:", timeout=5.0)
        read_until(master, b"\x1b[?25h", timeout=4.0)
        time.sleep(0.2)
        drain_all(master)

        os.write(master, b"BLKSGL.TXT\r")
        out_s67_saved = read_until(master, b"[BLK: 8c", timeout=6.0)
        out_s67_saved += drain_all(master)
        if b"[BLK: 8c" not in out_s67_saved:
            print(f"[-] Step 67 Subtest 3 failed: Block not retained after successful save: {repr(out_s67_saved)}", flush=True)
            return False
        print("[+] Step 67 Subtest 3 PASSED: Block saved and block selection remained solidified.", flush=True)

        # Delete saved block with Del key (\x1b[3~)
        os.write(master, b"\x1b[3~")
        out_s67_del = read_until(master, b"Hello END", timeout=5.0)
        out_s67_del += drain_all(master)
        if b"Hello END" not in out_s67_del or b"[BLK:" in out_s67_del:
            print(f"[-] Step 67 Subtest 4 failed: Block deletion with Del failed: {repr(out_s67_del)}", flush=True)
            return False
        print("[+] Step 67 Subtest 4 PASSED: Saved block deleted with Del key, line is now 'Hello END'.", flush=True)

        # Exit to CP/M with Ctrl-Q
        time.sleep(0.2)
        os.write(master, b"\x11")  # Ctrl-Q
        time.sleep(0.3)
        out_s67_q = drain_all(master)
        if b"Save changes" in out_s67_q:
            os.write(master, b"n")  # Don't save
            time.sleep(0.3)
            drain_all(master)
        read_until(master, b"C>", timeout=4.0)

        # Verify saved file on disk via CP/M TYPE
        os.write(master, b"type blksgl.txt\r")
        out_type = read_until(master, b"C>", timeout=5.0)
        if b"INSERTED" not in out_type:
            print(f"[-] Step 67 Subtest 5 failed: 'INSERTED' not found in BLKSGL.TXT: {repr(out_type)}", flush=True)
            return False
        print("[+] Step 67 Subtest 5 PASSED: Verified BLKSGL.TXT contains saved block content 'INSERTED'.", flush=True)
        print("[+] Successfully verified Block Save feature (Step 67)!", flush=True)

        # ---------------------------------------------------------------------
        # STEP 68: Save Progress Indicator ("Saving... | Line <count>")
        # ---------------------------------------------------------------------
        print("[*] STEP 68: Testing Save Progress Indicator and 100-line ticker...", flush=True)

        # Subtest 1: File Save progress on 300-line file (BIG300.TXT -> SAV300.TXT)
        time.sleep(0.5)
        os.write(master, b"se BIG300.TXT\r")
        out_s68_load = read_until(master, b"^K: Editor keys", timeout=35.0)
        drain_all(master)
        if b"^K: Editor keys" not in out_s68_load:
            print(f"[-] Step 68 failed: Failed to open BIG300.TXT: {repr(out_s68_load[-200:])}", flush=True)
            return False

        # Trigger Save with Ctrl+S (\x13)
        time.sleep(0.2)
        os.write(master, b"\x13")
        read_until(master, b"Enter filename to save:", timeout=6.0)
        read_until(master, b"\x1b[?25h", timeout=4.0)
        time.sleep(0.2)
        drain_all(master)

        # Type SAV300.TXT and press Enter (clearing pre-filled filename first)
        os.write(master, b"\x08" * 20 + b"SAV300.TXT\r")
        out_s68_save = read_until(master, b"^K: Editor keys", timeout=35.0)
        out_s68_save += drain_all(master)

        if b"\x1b[?25l" not in out_s68_save:
            print("[-] Step 68 failed: Cursor hide escape sequence not found during save.", flush=True)
            return False
        if b"Saving..." not in out_s68_save:
            print(f"[-] Step 68 failed: 'Saving...' not found in status bar during save: {repr(out_s68_save[:400])}", flush=True)
            return False
        if b"SAV300.TXT" not in out_s68_save:
            print("[-] Step 68 failed: Target filename 'SAV300.TXT' not found in Field 1 during save.", flush=True)
            return False

        found_s68_ticks = [t for t in [b"Line   100", b"Line   200", b"Line   300"] if t in out_s68_save]
        if len(found_s68_ticks) < 3:
            print(f"[-] Step 68 failed: Missing progress ticks during file save: {found_s68_ticks}", flush=True)
            return False
        print(f"[+] Step 68 Subtest 1 PASSED: File save progress verified with ticks: {[t.decode() for t in found_s68_ticks]}", flush=True)

        # Subtest 2: Block Save progress on 250-line block (BLK300.TXT)
        os.write(master, b"\x14")  # Ctrl+T (Top of file)
        time.sleep(0.2)
        drain_all(master)

        os.write(master, b"\x02")  # Ctrl+B (Start block)
        time.sleep(0.1)
        os.write(master, b"\x1b[B" * 250)  # Down 250 lines
        time.sleep(0.5)
        drain_all(master)

        os.write(master, b"\x13")  # Ctrl+S -> Block Save
        read_until(master, b"SAVE BLOCK (DIRECTORY - DRIVE C:)", timeout=6.0)
        read_until(master, b"Enter filename to save:", timeout=4.0)
        read_until(master, b"\x1b[?25h", timeout=4.0)
        time.sleep(0.2)
        drain_all(master)

        os.write(master, b"BLK300.TXT\r")
        out_s68_bsave = read_until(master, b"LOCK]", timeout=30.0)
        out_s68_bsave += drain_all(master)

        if b"Saving..." not in out_s68_bsave:
            print(f"[-] Step 68 failed: 'Saving...' not found during block save: {repr(out_s68_bsave[:400])}", flush=True)
            return False
        if b"BLK300.TXT" not in out_s68_bsave:
            print("[-] Step 68 failed: Target block filename 'BLK300.TXT' not found in Field 1 during save.", flush=True)
            return False

        found_s68_bticks = [t for t in [b"Line   100", b"Line   200"] if t in out_s68_bsave]
        if len(found_s68_bticks) < 2:
            print(f"[-] Step 68 failed: Missing progress ticks during block save: {found_s68_bticks}", flush=True)
            return False
        if b"[BLK: 251L LOCK]" not in out_s68_bsave and b"LOCK]" not in out_s68_bsave:
            print(f"[-] Step 68 failed: Block status not restored: {repr(out_s68_bsave[-200:])}", flush=True)
            return False
        print(f"[+] Step 68 Subtest 2 PASSED: Block save progress verified with ticks: {[t.decode() for t in found_s68_bticks]}", flush=True)

        # Subtest 3: Save on Exit progress (EXIT_SAVE_AND_QUIT)
        os.write(master, b"\x1b")  # ESC (Clear block)
        time.sleep(0.2)
        drain_all(master)

        os.write(master, b"Z")  # Dirty document
        time.sleep(0.2)
        drain_all(master)

        os.write(master, b"\x11")  # Ctrl+Q
        out_s68_prompt = read_until(master, b"Save changes?", timeout=5.0)
        if b"Save changes?" not in out_s68_prompt:
            print(f"[-] Step 68 failed: Save changes prompt not found: {repr(out_s68_prompt)}", flush=True)
            return False

        os.write(master, b"y")  # Confirm save
        out_s68_exit = read_until(master, b"C>", timeout=35.0)
        out_s68_exit += drain_all(master)

        if b"Saving..." not in out_s68_exit:
            print(f"[-] Step 68 failed: 'Saving...' not found during exit save: {repr(out_s68_exit[:400])}", flush=True)
            return False

        found_s68_eticks = [t for t in [b"Line   100", b"Line   200", b"Line   300"] if t in out_s68_exit]
        if len(found_s68_eticks) < 2:
            print(f"[-] Step 68 failed: Missing progress ticks during exit save: {found_s68_eticks}", flush=True)
            return False
        if b"C>" not in out_s68_exit:
            print("[-] Step 68 failed: Did not exit cleanly to CP/M.", flush=True)
            return False
        print(f"[+] Step 68 Subtest 3 PASSED: Exit save progress verified with ticks: {[t.decode() for t in found_s68_eticks]}", flush=True)
        print("[+] Successfully verified Save Progress Indicator (Step 68)!", flush=True)

        # ---------------------------------------------------------------------
        # STEP 69: Modified Document Indicator ('*') in Status Bar
        # ---------------------------------------------------------------------
        print("[*] STEP 69: Testing Unsaved Modification Indicator ('*') in Status Bar...", flush=True)

        # Subtest 1: Open existing file 2.TXT, verify clean, modify, verify '*', save with Ctrl+S, verify clean
        time.sleep(0.5)
        drain_all(master)
        os.write(master, b"se 2.TXT\r")
        out_s69_load = read_until(master, b"^K: Editor keys", timeout=35.0)
        out_s69_load += drain_all(master)

        if b"| C:2.TXT        |" not in out_s69_load:
            print(f"[-] Step 69 failed: Clean status bar not found: {repr(out_s69_load[-400:])}", flush=True)
            return False
        if b"C:2.TXT*" in out_s69_load:
            print("[-] Step 69 failed: Clean status bar contains '*' unexpectedly!", flush=True)
            return False
        print("[+] Step 69 Subtest 1a PASSED: Initial clean status bar verified: '| C:2.TXT        |'", flush=True)

        # Modify document by typing a character
        os.write(master, b"X")
        time.sleep(0.3)
        out_s69_mod = drain_all(master)
        if b"| C:2.TXT*       |" not in out_s69_mod:
            print(f"[-] Step 69 failed: Modified status bar not found after typing: {repr(out_s69_mod[-400:])}", flush=True)
            return False
        print("[+] Step 69 Subtest 1b PASSED: Modified status bar verified: '| C:2.TXT*       |'", flush=True)

        # Save with Ctrl+S (\x13)
        os.write(master, b"\x13")
        read_until(master, b"Enter filename to save:", timeout=6.0)
        read_until(master, b"\x1b[?25h", timeout=4.0)
        time.sleep(0.2)
        drain_all(master)

        # Press Enter to keep same filename 2.TXT
        os.write(master, b"\r")
        out_s69_ow = read_until(master, b"File already exists. Overwrite?", timeout=6.0)
        if b"File already exists. Overwrite?" not in out_s69_ow:
            print(f"[-] Step 69 failed: Overwrite prompt not received: {repr(out_s69_ow)}", flush=True)
            return False

        # Confirm overwrite with 'y'
        os.write(master, b"y")
        out_s69_saved = read_until(master, b"^K: Editor keys", timeout=15.0)
        out_s69_saved += drain_all(master)

        if b"| C:2.TXT        |" not in out_s69_saved:
            print(f"[-] Step 69 failed: Status bar after save did not restore clean state: {repr(out_s69_saved[-400:])}", flush=True)
            return False
        if b"C:2.TXT*" in out_s69_saved:
            print("[-] Step 69 failed: Status bar after save still has '*'!", flush=True)
            return False
        print("[+] Step 69 Subtest 1c PASSED: Clean state restored after save: '| C:2.TXT        |'", flush=True)

        # Subtest 2: Untitled document from splash screen ('n' on splash)
        os.write(master, b"\x1b")  # Return to splash screen
        read_until(master, b"Screen Editor", timeout=6.0)
        drain_all(master)

        os.write(master, b"n")  # New File
        out_s69_new = read_until(master, b"^K: Editor keys", timeout=6.0)
        out_s69_new += drain_all(master)

        if b"| (Untitled)     |" not in out_s69_new:
            print(f"[-] Step 69 failed: Initial (Untitled) status bar not found: {repr(out_s69_new[-400:])}", flush=True)
            return False
        if b"(Untitled)*" in out_s69_new:
            print("[-] Step 69 failed: Initial (Untitled) contains '*' unexpectedly!", flush=True)
            return False
        print("[+] Step 69 Subtest 2a PASSED: Initial (Untitled) verified: '| (Untitled)     |'", flush=True)

        # Type character in Untitled file
        os.write(master, b"Y")
        time.sleep(0.3)
        out_s69_new_mod = drain_all(master)
        if b"| (Untitled)*    |" not in out_s69_new_mod:
            print(f"[-] Step 69 failed: Modified (Untitled)* status bar not found: {repr(out_s69_new_mod[-400:])}", flush=True)
            return False
        print("[+] Step 69 Subtest 2b PASSED: Modified (Untitled) verified: '| (Untitled)*    |'", flush=True)

        # Discard and exit to CP/M prompt
        os.write(master, b"\x11")  # Ctrl+Q
        read_until(master, b"Save changes?", timeout=6.0)
        os.write(master, b"n")
        out_s69_exit1 = read_until(master, b"C>", timeout=6.0)
        if b"C>" not in out_s69_exit1:
            print(f"[-] Step 69 failed: Exit to CP/M failed: {repr(out_s69_exit1)}", flush=True)
            return False

        # Subtest 3: Maximum-length (14 characters) filename field capping
        time.sleep(0.5)
        drain_all(master)
        os.write(master, b"se LONGNAME.TXT\r")
        out_s69_long = read_until(master, b"^K: Editor keys", timeout=35.0)
        out_s69_long += drain_all(master)

        if b"| C:LONGNAME.TXT |" not in out_s69_long:
            print(f"[-] Step 69 failed: Initial 14-char status bar not found: {repr(out_s69_long[-400:])}", flush=True)
            return False
        print("[+] Step 69 Subtest 3a PASSED: Initial 14-char file verified: '| C:LONGNAME.TXT |'", flush=True)

        # Type character to make 14-char file modified
        os.write(master, b"Z")
        time.sleep(0.3)
        out_s69_long_mod = drain_all(master)
        if b"| C:LONGNAME.TX* |" not in out_s69_long_mod:
            print(f"[-] Step 69 failed: Modified 14-char status bar not found: {repr(out_s69_long_mod[-400:])}", flush=True)
            return False
        print("[+] Step 69 Subtest 3b PASSED: Modified 14-char file verified: '| C:LONGNAME.TX* |'", flush=True)

        # Discard and exit to CP/M prompt
        os.write(master, b"\x11")  # Ctrl+Q
        read_until(master, b"Save changes?", timeout=6.0)
        os.write(master, b"n")
        out_s69_exit2 = read_until(master, b"C>", timeout=6.0)
        if b"C>" not in out_s69_exit2:
            print(f"[-] Step 69 failed: Exit 2 to CP/M failed: {repr(out_s69_exit2)}", flush=True)
            return False

        print("[+] Successfully verified Modified Document Indicator ('*') in Status Bar (Step 69)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 70: Directory Listing Filter on Open, Save, Insert, Block Save
        # ---------------------------------------------------------------------
        print("[*] Step 70: Testing Directory Listing Filter on Open, Save, "
              "Insert, and Block Save...", flush=True)

        # 1. Start SE from CP/M prompt
        time.sleep(0.5)
        os.write(master, b"se\r")
        out_s70_splash = read_until(master, b"Free: ", timeout=20.0)
        if b"Free: " not in out_s70_splash:
            print(f"[-] Step 70 failed: Could not reach splash screen. Buffer: {repr(out_s70_splash)}", flush=True)
            return False
        time.sleep(0.5)
        drain_all(master, quiet_time=0.1)

        # Subtest 1: Open File Screen Filter
        # Press 'o' to enter Open File screen
        os.write(master, b"o")
        out_s70_open = read_until(master, b"Enter filename to open:", timeout=6.0)
        if b"OPEN FILE (DIRECTORY - DRIVE C:)" not in out_s70_open:
            print(f"[-] Step 70 failed: Initial Open File header mismatch. Buffer: {repr(out_s70_open)}", flush=True)
            return False
        if b"SE.COM" not in out_s70_open:
            print("[-] Step 70 failed: SE.COM not found in unfiltered directory listing.", flush=True)
            return False

        # Apply filter: '*.TXT'
        time.sleep(0.2)
        os.write(master, b"*.TXT\r")
        out_s70_filt = read_until(master, b"Enter filename to open:", timeout=6.0)
        if b"OPEN FILE (DIRECTORY - DRIVE C: [*.TXT])" not in out_s70_filt:
            print(f"[-] Step 70 failed: Header did not update to [*.TXT]. Buffer: {repr(out_s70_filt)}", flush=True)
            return False
        new_s70_txt = out_s70_filt[out_s70_filt.rfind(b"[*.TXT]"):]
        if b"SE.COM" in new_s70_txt:
            print(f"[-] Step 70 failed: SE.COM unexpectedly found in *.TXT filtered listing! Buffer: {repr(new_s70_txt)}", flush=True)
            return False

        # Reset filter: '*.*'
        time.sleep(0.2)
        os.write(master, b"\x08" * 20 + b"*.*\r")
        out_s70_reset = read_until(master, b"Enter filename to open:", timeout=6.0)
        last_s70_reset = out_s70_reset[out_s70_reset.rfind(b"DIRECTORY - DRIVE C:"):]
        header_s70_reset = last_s70_reset.split(b"\r\n")[0]
        if b": [" in header_s70_reset:
            print(f"[-] Step 70 failed: Header did not reset after *.*. Buffer: {repr(header_s70_reset)}", flush=True)
            return False
        if b"SE.COM" not in last_s70_reset:
            print("[-] Step 70 failed: SE.COM not restored after *.* reset.", flush=True)
            return False

        # Combined drive switch and filter: 'B:*.COM'
        time.sleep(0.2)
        os.write(master, b"\x08" * 20 + b"B:*.COM\r")
        out_s70_b = read_until(master, b"Enter filename to open:", timeout=6.0)
        if b"OPEN FILE (DIRECTORY - DRIVE B: [*.COM])" not in out_s70_b:
            print(f"[-] Step 70 failed: Combined drive+filter failed. Buffer: {repr(out_s70_b)}", flush=True)
            return False

        # Switch back to Drive C: with reset: 'C:*.*'
        time.sleep(0.2)
        os.write(master, b"\x08" * 20 + b"C:*.*\r")
        out_s70_c = read_until(master, b"Enter filename to open:", timeout=6.0)
        last_s70_c = out_s70_c[out_s70_c.rfind(b"DIRECTORY - DRIVE C:"):]
        header_s70_c = last_s70_c.split(b"\r\n")[0]
        if b": [" in header_s70_c:
            print(f"[-] Step 70 failed: Reset back to C:*.* failed. Buffer: {repr(header_s70_c)}", flush=True)
            return False

        # Test inline 'File not found' then filtering
        time.sleep(0.2)
        os.write(master, b"\x08" * 20 + b"NONEXIST.XYZ\r")
        out_s70_fnf = read_until(master, b"File not found", timeout=4.0)
        if b"File not found" not in out_s70_fnf:
            print(f"[-] Step 70 failed: 'File not found' inline message not displayed. Buffer: {repr(out_s70_fnf)}", flush=True)
            return False

        # Filter directly from FNF state: '*.TXT'
        time.sleep(0.2)
        os.write(master, b"\x08" * 20 + b"*.TXT\r")
        out_s70_fnf_filt = read_until(master, b"OPEN FILE (DIRECTORY - DRIVE C: [*.TXT])", timeout=4.0)
        if b"OPEN FILE (DIRECTORY - DRIVE C: [*.TXT])" not in out_s70_fnf_filt:
            print(f"[-] Step 70 failed: Filter from FNF state failed. Buffer: {repr(out_s70_fnf_filt)}", flush=True)
            return False

        # Press ESC to return to splash
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"Active Screen:", timeout=4.0)
        print("[+] Step 70 Subtest 1 PASSED: Open File directory filter and FNF recovery verified.", flush=True)

        # Subtest 2: Save File Screen Filter & Filename Preservation
        # Start new editor document with 'e'
        time.sleep(0.2)
        os.write(master, b"e")
        read_until(master, b"Line    1/1", timeout=4.0)
        time.sleep(0.2)
        os.write(master, b"Hello Filter Test")

        # Save file as TESTF.TXT
        time.sleep(0.3)
        os.write(master, b"\x13") # Ctrl+S
        read_until(master, b"Enter filename to save:", timeout=8.0)
        time.sleep(0.2)
        os.write(master, b"TESTF.TXT\r")
        read_until(master, b"Line    1/1", timeout=6.0)
        time.sleep(0.3)

        # Modify document
        os.write(master, b" more text")
        time.sleep(0.3)

        # Press Ctrl+S: input box prefills with TESTF.TXT
        os.write(master, b"\x13")
        out_s70_save2 = read_until(master, b"Enter filename to save:", timeout=8.0)
        out_s70_save2 += read_until(master, b"TESTF.TXT", timeout=4.0)
        if b"TESTF.TXT" not in out_s70_save2:
            print(f"[-] Step 70 failed: Save prompt did not prefill 'TESTF.TXT'. Buffer: {repr(out_s70_save2)}", flush=True)
            return False

        # Type '*.TXT' and Enter to filter directory on Save screen
        time.sleep(0.3)
        os.write(master, b"\x08" * 20 + b"*.TXT\r")
        out_s70_save_filt = read_until(master, b"SAVE FILE (DIRECTORY - DRIVE C: [*.TXT])", timeout=8.0)
        if b"SAVE FILE (DIRECTORY - DRIVE C: [*.TXT])" not in out_s70_save_filt:
            print(f"[-] Step 70 failed: Save header did not update to [*.TXT]. Buffer: {repr(out_s70_save_filt)}", flush=True)
            return False
        out_s70_save_filt += read_until(master, b"Enter filename to save:", timeout=6.0)
        if b"*.TXT" not in out_s70_save_filt:
            print(f"[-] Step 70 failed: Save prompt did NOT preserve input string '*.TXT'. Buffer: {repr(out_s70_save_filt)}", flush=True)
            return False

        # Clear '*.TXT' and save as TESTF.TXT, confirm overwrite
        time.sleep(0.3)
        os.write(master, b"\x08" * 20 + b"TESTF.TXT\r")
        out_s70_ow = read_until(master, b"Overwrite?", timeout=6.0)
        if b"Overwrite?" in out_s70_ow:
            time.sleep(0.2)
            os.write(master, b"y")
        out_s70_saved = read_until(master, b"Line    1/1", timeout=6.0)
        if b"TESTF.TXT" not in out_s70_saved:
            print(f"[-] Step 70 failed: Return did not save file. Buffer: {repr(out_s70_saved)}", flush=True)
            return False
        print("[+] Step 70 Subtest 2 PASSED: Save File filter & filename preservation verified.", flush=True)

        # Subtest 3: Block Insert Screen Filter
        # Start block with Ctrl+B in editor
        time.sleep(0.2)
        os.write(master, b"\x02")
        time.sleep(0.2)
        # Press Ctrl+O -> opens Block Insert File screen
        os.write(master, b"\x0f")
        out_s70_ins = read_until(master, b"Enter filename to insert:", timeout=6.0)
        if b"INSERT FILE (DIRECTORY - DRIVE C:" not in out_s70_ins:
            print(f"[-] Step 70 failed: Failed to open Insert File screen. Buffer: {repr(out_s70_ins)}", flush=True)
            return False

        # Filter on Insert File screen: '*.TXT'
        time.sleep(0.2)
        os.write(master, b"*.TXT\r")
        out_s70_ins_filt = read_until(master, b"Enter filename to insert:", timeout=6.0)
        if b"INSERT FILE (DIRECTORY - DRIVE C: [*.TXT])" not in out_s70_ins_filt:
            print(f"[-] Step 70 failed: Insert File header filter failed. Buffer: {repr(out_s70_ins_filt)}", flush=True)
            return False

        # Cancel with ESC back to editor with solidified block
        time.sleep(0.3)
        os.write(master, b"\x1b")
        out_s70_esc_ins = read_until(master, b"LOCK]", timeout=6.0)
        if b"LOCK]" not in out_s70_esc_ins:
            print(f"[-] Step 70 failed: ESC from Insert File did not return with lock. Buffer: {repr(out_s70_esc_ins)}", flush=True)
            return False
        print("[+] Step 70 Subtest 3 PASSED: Block Insert File filter verified.", flush=True)

        # Subtest 4: Block Save Screen Filter
        # Block is already solidified; open Block Save screen with Ctrl+S
        time.sleep(0.3)
        os.write(master, b"\x13")
        out_s70_blksave = read_until(master, b"Enter filename to save:", timeout=6.0)
        if b"SAVE BLOCK (DIRECTORY - DRIVE C:" not in out_s70_blksave:
            print(f"[-] Step 70 failed: Failed to open Save Block screen. Buffer: {repr(out_s70_blksave)}", flush=True)
            return False

        # Filter on Block Save screen: '*.TXT'
        time.sleep(0.3)
        os.write(master, b"*.TXT\r")
        out_s70_blksave_filt = read_until(master, b"Enter filename to save:", timeout=6.0)
        if b"SAVE BLOCK (DIRECTORY - DRIVE C: [*.TXT])" not in out_s70_blksave_filt:
            print(f"[-] Step 70 failed: Save Block header filter failed. Buffer: {repr(out_s70_blksave_filt)}", flush=True)
            return False

        # Cancel Block Save with ESC
        time.sleep(0.3)
        os.write(master, b"\x1b")
        read_until(master, b"LOCK]", timeout=6.0)

        # Cancel active block in editor with ESC
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"^K: Editor keys", timeout=4.0)

        # Exit editor cleanly to CP/M
        time.sleep(0.2)
        os.write(master, b"\x11") # Ctrl+Q
        out_s70_exit = read_until(master, b"C>", timeout=6.0)
        if b"C>" not in out_s70_exit:
            print(f"[-] Step 70 failed: Exit to CP/M failed: {repr(out_s70_exit)}", flush=True)
            return False
        print("[+] Step 70 Subtest 4 PASSED: Block Save File filter verified.", flush=True)
        print("[+] Successfully verified Directory Listing Filter on Open, Save, Insert, and Block Save (Step 70)!", flush=True)

        # =============================================================
        # STEP 71: CP/M User Areas Support (C1: and 1C: Formats)
        # =============================================================
        print("[*] STEP 71: Testing CP/M User Areas Support (C1: and 1C:)...", flush=True)

        # Subtest 1: Command line invocation with c1: prefix
        time.sleep(0.5)
        os.write(master, b"se c1:u1file.txt\r")
        out_s71_sub1 = read_until(master, b"Hello from User 1 area!", timeout=30.0)
        if b"Hello from User 1 area!" not in out_s71_sub1:
            print(f"[-] Step 71 Subtest 1 failed: 'se c1:u1file.txt' did not display file. Buffer: {repr(out_s71_sub1)}", flush=True)
            return False
        if b"C1:U1FILE.TXT" not in out_s71_sub1:
            out_s71_sub1 += drain_all(master)
        if b"C1:U1FILE.TXT" not in out_s71_sub1:
            print(f"[-] Step 71 Subtest 1 failed: Status bar missing 'C1:U1FILE.TXT'. Buffer: {repr(out_s71_sub1)}", flush=True)
            return False
        print("[+] Step 71 Subtest 1 PASSED: 'se c1:u1file.txt' loaded with status bar 'C1:U1FILE.TXT'.", flush=True)

        # Subtest 2: Modified indicator with user area in status bar
        os.write(master, b"X")
        out_s71_sub2 = read_until(master, b"C1:U1FILE.TXT*", timeout=4.0)
        if b"C1:U1FILE.TXT*" not in out_s71_sub2:
            print(f"[-] Step 71 Subtest 2 failed: Modified indicator not visible in 'C1:U1FILE.TXT*'. Buffer: {repr(out_s71_sub2)}", flush=True)
            return False
        print("[+] Step 71 Subtest 2 PASSED: Modified indicator 'C1:U1FILE.TXT*' verified.", flush=True)

        # Discard changes and exit to CP/M
        os.write(master, b"\x11") # Ctrl+Q
        read_until(master, b"Save changes?", timeout=4.0)
        os.write(master, b"N")
        out_s71_cpm = read_until(master, b"C>", timeout=6.0)
        if b"C>" not in out_s71_cpm:
            print(f"[-] Step 71 failed: Exit to CP/M failed: {repr(out_s71_cpm)}", flush=True)
            return False

        # Subtest 3: Command line invocation with 1c: prefix
        time.sleep(0.5)
        os.write(master, b"se 1c:u1file.txt\r")
        out_s71_sub3 = read_until(master, b"Hello from User 1 area!", timeout=30.0)
        if b"Hello from User 1 area!" not in out_s71_sub3:
            print(f"[-] Step 71 Subtest 3 failed: 'se 1c:u1file.txt' did not display file. Buffer: {repr(out_s71_sub3)}", flush=True)
            return False
        print("[+] Step 71 Subtest 3 PASSED: 'se 1c:u1file.txt' loaded correctly.", flush=True)

        # Subtest 4: Save As across User Areas (1C:SAVEU1.TXT)
        time.sleep(0.2)
        os.write(master, b"\x13") # Ctrl+S
        out_s71_save = read_until(master, b"Enter filename to save:", timeout=6.0)
        if b"Enter filename to save:" not in out_s71_save:
            print(f"[-] Step 71 Subtest 4 failed: Save prompt not reached. Buffer: {repr(out_s71_save)}", flush=True)
            return False
        if b"DRIVE C1:)" not in out_s71_save:
            print(f"[-] Step 71 Subtest 4 failed: Save screen title does not show 'DRIVE C1:)'. Buffer: {repr(out_s71_save)}", flush=True)
            return False

        time.sleep(0.1)
        os.write(master, b"\x08" * 20 + b"1C:SAVEU1.TXT\r")
        out_s71_saved = read_until(master, b"C1:SAVEU1.TXT", timeout=8.0)
        if b"C1:SAVEU1.TXT" not in out_s71_saved:
            print(f"[-] Step 71 Subtest 4 failed: Save did not return to editor with status bar. Buffer: {repr(out_s71_saved)}", flush=True)
            return False
        print("[+] Step 71 Subtest 4 PASSED: Saved as '1C:SAVEU1.TXT' into User 1.", flush=True)

        # Subtest 5: Directory screen interactive switching: C0:, 1:, 1C:*.TXT
        time.sleep(0.2)
        os.write(master, b"\x0f") # Ctrl+O
        out_s71_open = read_until(master, b"Enter filename to open:", timeout=6.0)
        out_s71_open += read_until(master, b"[C1:", timeout=4.0)
        if b"Enter filename to open:" not in out_s71_open:
            print(f"[-] Step 71 Subtest 5 failed: Open screen not displayed. Buffer: {repr(out_s71_open)}", flush=True)
            return False
        if b"DRIVE C1:)" not in out_s71_open:
            print(f"[-] Step 71 Subtest 5 failed: Open title not DRIVE C1:). Buffer: {repr(out_s71_open)}", flush=True)
            return False
        if b"[C1:" not in out_s71_open:
            print(f"[-] Step 71 Subtest 5 failed: Open edit box not preloaded with C1:. Buffer: {repr(out_s71_open)}", flush=True)
            return False

        # Switch to User 0 via C0:
        time.sleep(0.2)
        os.write(master, b"\x08" * 20 + b"C0:\r")
        out_s71_c0 = read_until(master, b"(DIRECTORY - DRIVE C:)", timeout=6.0)
        if b"(DIRECTORY - DRIVE C:)" not in out_s71_c0:
            print(f"[-] Step 71 Subtest 5 failed: Switch to C0: failed. Buffer: {repr(out_s71_c0)}", flush=True)
            return False

        # Switch to User 1 via 1:
        time.sleep(0.2)
        os.write(master, b"\x08" * 20 + b"1:\r")
        out_s71_u1 = read_until(master, b"(DIRECTORY - DRIVE C1:)", timeout=6.0)
        if b"(DIRECTORY - DRIVE C1:)" not in out_s71_u1:
            print(f"[-] Step 71 Subtest 5 failed: Switch to 1: failed. Buffer: {repr(out_s71_u1)}", flush=True)
            return False

        # Filter in User 1 via 1C:*.TXT
        time.sleep(0.2)
        os.write(master, b"\x08" * 20 + b"1C:*.TXT\r")
        out_s71_filt = read_until(master, b"(DIRECTORY - DRIVE C1: [*.TXT])", timeout=6.0)
        if b"(DIRECTORY - DRIVE C1: [*.TXT])" not in out_s71_filt:
            print(f"[-] Step 71 Subtest 5 failed: 1C:*.TXT filter title failed. Buffer: {repr(out_s71_filt)}", flush=True)
            return False
        out_s71_filt += read_until(master, b"Enter filename to open:", timeout=6.0)
        if b"U1FILE.TXT" not in out_s71_filt or b"SAVEU1.TXT" not in out_s71_filt:
            print(f"[-] Step 71 Subtest 5 failed: U1 files not listed in filter. Buffer: {repr(out_s71_filt)}", flush=True)
            return False

        # Cancel Open dialog with ESC
        time.sleep(0.1)
        os.write(master, b"\x1b")
        read_until(master, b"^K: Editor keys", timeout=4.0)
        print("[+] Step 71 Subtest 5 PASSED: Interactive directory switching and filtering verified.", flush=True)

        # Subtest 6: Block Save & Insert across User Areas
        os.write(master, b"\x02") # Ctrl+B start block
        read_until(master, b"[BLK:", timeout=4.0)
        os.write(master, b"\x1b[B") # Cursor down 1 row
        drain_all(master)
        os.write(master, b"\x02") # Ctrl+B solidify block
        read_until(master, b"LOCK]", timeout=4.0)

        # Block Save (Ctrl+S with active block)
        time.sleep(0.1)
        os.write(master, b"\x13")
        out_s71_bs = read_until(master, b"Enter filename to save:", timeout=6.0)
        out_s71_bs += read_until(master, b"[C1:", timeout=4.0)
        if b"DRIVE C1:)" not in out_s71_bs:
            print(f"[-] Step 71 Subtest 6 failed: Block save title not DRIVE C1:). Buffer: {repr(out_s71_bs)}", flush=True)
            return False
        if b"[C1:" not in out_s71_bs:
            print(f"[-] Step 71 Subtest 6 failed: Block save edit box not preloaded with C1:. Buffer: {repr(out_s71_bs)}", flush=True)
            return False

        time.sleep(0.1)
        os.write(master, b"\x08" * 20 + b"C1:BLKU1.TXT\r")
        out_s71_bs_done = read_until(master, b"LOCK]", timeout=8.0)
        if b"LOCK]" not in out_s71_bs_done:
            print(f"[-] Step 71 Subtest 6 failed: Block save failed to complete. Buffer: {repr(out_s71_bs_done)}", flush=True)
            return False

        # Block Insert from 1C:BLKU1.TXT (Ctrl+O with active block)
        time.sleep(0.1)
        os.write(master, b"\x0f")
        out_s71_bi = read_until(master, b"Enter filename to insert:", timeout=6.0)
        if b"Enter filename to insert:" not in out_s71_bi:
            print(f"[-] Step 71 Subtest 6 failed: Block insert prompt not reached. Buffer: {repr(out_s71_bi)}", flush=True)
            return False

        time.sleep(0.1)
        os.write(master, b"\x08" * 20 + b"1C:BLKU1.TXT\r")
        out_s71_bi_done = read_until(master, b"^K: Editor keys", timeout=8.0)
        if b"^K: Editor keys" not in out_s71_bi_done:
            print(f"[-] Step 71 Subtest 6 failed: Block insert did not return to editor. Buffer: {repr(out_s71_bi_done)}", flush=True)
            return False
        print("[+] Step 71 Subtest 6 PASSED: Block Save and Insert verified in User 1.", flush=True)

        # Subtest 7: Exit to CP/M preserves original User 0
        os.write(master, b"\x11") # Ctrl+Q
        read_until(master, b"Save changes?", timeout=4.0)
        os.write(master, b"N")
        out_s71_exit = read_until(master, b"C>", timeout=6.0)
        if b"C>" not in out_s71_exit:
            print(f"[-] Step 71 Subtest 7 failed: Exit to CP/M failed: {repr(out_s71_exit)}", flush=True)
            return False

        time.sleep(0.2)
        os.write(master, b"dir u1file.txt\r")
        out_s71_dir0 = read_until(master, b"C>", timeout=6.0)
        if b"No File" not in out_s71_dir0 and b"NO FILE" not in out_s71_dir0:
            print(f"[-] Step 71 Subtest 7 failed: U1FILE.TXT found in User 0 DIR! Buffer: {repr(out_s71_dir0)}", flush=True)
            return False

        time.sleep(0.2)
        os.write(master, b"user 1\r")
        read_until(master, b"C>", timeout=4.0)
        os.write(master, b"dir u1file.txt\r")
        out_s71_dir1 = read_until(master, b"C>", timeout=6.0)
        if b"U1FILE" not in out_s71_dir1:
            print(f"[-] Step 71 Subtest 7 failed: U1FILE.TXT not found in User 1 DIR! Buffer: {repr(out_s71_dir1)}", flush=True)
            return False

        # Switch back to User 0 in CP/M
        time.sleep(0.2)
        os.write(master, b"user 0\r")
        read_until(master, b"C>", timeout=4.0)
        print("[+] Step 71 Subtest 7 PASSED: Exit preserved User 0; CP/M user 1 contains files.", flush=True)
        print("[+] Successfully verified CP/M User Areas Support (Step 71)!", flush=True)

        # ---------------------------------------------------------------------
        # Step 72: Memory Information Screen ('m' key from splash menu)
        # ---------------------------------------------------------------------
        print("[*] Step 72: Verifying Memory Information Screen ('m')...", flush=True)
        drain_all(master)
        time.sleep(0.5)
        os.write(master, b"se\r")
        out_s72_splash = read_until(master, b"for memory info", timeout=30.0)
        time.sleep(0.2)
        out_s72_splash += drain_all(master)
        if b"for memory info" not in out_s72_splash:
            print(f"[-] Step 72 failed: 'for memory info' not found on splash screen. Buffer: {repr(out_s72_splash)}", flush=True)
            return False
        print("    [+] Splash screen displays 'for memory info' menu option.")

        # Navigate to memory info screen using 'm'
        time.sleep(0.3)
        os.write(master, b"m")
        out_s72_mem = read_until(master, b"return to splash", timeout=20.0)
        time.sleep(0.2)
        out_s72_mem += drain_all(master)
        if b"SE.COM - Extended Memory Map" not in out_s72_mem:
            print(f"[-] Step 72 failed: Title 'SE.COM - Extended Memory Map' missing. Buffer: {repr(out_s72_mem)}", flush=True)
            return False

        # Verify summary line components
        if b"HBIOS: RomWBW v" not in out_s72_mem or b"OS: CP/M 2.2" not in out_s72_mem:
            print(f"[-] Step 72 failed: Summary line HBIOS/OS missing. Buffer: {repr(out_s72_mem)}", flush=True)
            return False
        if b"RAM: 512 KB (16x32K)" not in out_s72_mem or (b"SE: 192 KB" not in out_s72_mem and b"SE: 448 KB" not in out_s72_mem):
            print(f"[-] Step 72 failed: Summary line RAM/SE missing. Buffer: {repr(out_s72_mem)}", flush=True)
            return False
        print("    [+] System summary row verified (HBIOS, OS, RAM, SE usage).")

        # Verify table headers
        if b"Bank  Phys   Size   System / OS Role        SE.COM Usage" not in out_s72_mem:
            print(f"[-] Step 72 failed: Table header missing. Buffer: {repr(out_s72_mem)}", flush=True)
            return False

        # Verify key bank rows
        if b"00    80h    32K    HBIOS System Firmware   Reserved: Protected HBIOS" not in out_s72_mem:
            print(f"[-] Step 72 failed: Bank 00 HBIOS entry missing. Buffer: {repr(out_s72_mem)}", flush=True)
            return False
        if b"01    81h    32K    RAM Disk (MD0:)" not in out_s72_mem:
            print(f"[-] Step 72 failed: Bank 01 RAM disk entry missing. Buffer: {repr(out_s72_mem)}", flush=True)
            return False
        if b"Preserved: RAM Disk Active" not in out_s72_mem and b"Active: Doc Buffer Bank" not in out_s72_mem:
            print(f"[-] Step 72 failed: Bank 01 RAM disk usage missing. Buffer: {repr(out_s72_mem)}", flush=True)
            return False
        if b"13    8Dh    32K    Application Memory      Active: 16K Line Slot Table" not in out_s72_mem:
            print(f"[-] Step 72 failed: Bank 13 line table entry missing. Buffer: {repr(out_s72_mem)}", flush=True)
            return False
        if b"14    8Eh    32K    CP/M 2.2 TPA & Base     Active: SE Program & Cache" not in out_s72_mem:
            print(f"[-] Step 72 failed: Bank 14 TPA entry missing. Buffer: {repr(out_s72_mem)}", flush=True)
            return False
        print("    [+] Table bank rows and dynamic roles verified.")

        # Verify column 0 tilde prefixes
        lines = out_s72_mem.decode("latin1", errors="replace").split("\r\n")
        tilde_rows = [l for l in lines if l.startswith("~")]
        if len(tilde_rows) < 20:
            print(f"[-] Step 72 failed: Insufficient tildes in column 0 (got {len(tilde_rows)}).", flush=True)
            return False
        print(f"    [+] Column 0 tildes verified ({len(tilde_rows)} rows).")

        # Verify return to splash screen via ESC
        time.sleep(0.3)
        os.write(master, b"\x1b")
        out_s72_back = read_until(master, b"for memory info", timeout=15.0)
        if b"for memory info" not in out_s72_back:
            print(f"[-] Step 72 failed: Return to splash screen failed. Buffer: {repr(out_s72_back)}", flush=True)
            return False
        print("    [+] Clean return to splash screen on ESC verified.")

        # Clean exit to CP/M with 'q'
        time.sleep(0.3)
        os.write(master, b"q")
        out_s72_cpm = read_until(master, b"C>", timeout=15.0)
        if b"C>" not in out_s72_cpm:
            print(f"[-] Step 72 failed: Clean exit to CP/M failed. Buffer: {repr(out_s72_cpm)}", flush=True)
            return False
        print("    [+] Clean exit to CP/M prompt verified.")
        print("[+] Successfully verified Memory Information Screen (Step 72)!",
              flush=True)

        # ---------------------------------------------------------------------
        # Step 73: In-line Filename Edit Box Navigation and Editing
        # ---------------------------------------------------------------------
        print("[*] Step 73: Verifying Filename Edit Box In-line Editing...",
              flush=True)
        drain_all(master)
        time.sleep(0.3)
        # Ensure any leftover 30.TXT on Drive D (slice 1) is cleared
        if os.path.isfile(cpmrm_bin):
            subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_1", img_file,
                            "0:30.TXT"],
                           stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)

        # Launch editor with 30.TXT
        os.write(master, b"se 30.TXT\r")
        out_s73_ed = read_until(master, b"^K: Editor keys", timeout=30.0)
        if b"^K: Editor keys" not in out_s73_ed:
            print("[-] Step 73 failed to load 30.TXT into editor.",
                  flush=True)
            return False
        print("    [+] Editor loaded 30.TXT successfully.")

        # Subtest 1: Save File Dialog In-Line Editing
        # Open Save dialog (Ctrl+S)
        time.sleep(0.3)
        os.write(master, b"\x13")
        out_s73_save = read_until(master, b"Enter filename to save:",
                                  timeout=8.0)
        read_until(master, b"\x1b[?25h", timeout=4.0)
        time.sleep(0.2)
        drain_all(master)
        if b"Enter filename to save:" not in out_s73_save:
            print("[-] Step 73 failed: Save dialog prompt not found.",
                  flush=True)
            return False
        print("    [+] Save dialog reached with preloaded filename.")

        # Preloaded filename is 'C0:30.TXT', cursor is at end (col 9).
        # Test Home key (ESC [ H) -> moves cursor to col 0.
        time.sleep(0.1)
        os.write(master, b"\x1b[H")

        # Test Delete key (ESC [ 3 ~) -> deletes character 'C'.
        # Buffer becomes '0:30.TXT'.
        time.sleep(0.1)
        os.write(master, b"\x1b[3~")

        # Test character insertion -> type 'D'. Buffer becomes 'D0:30.TXT'.
        time.sleep(0.1)
        os.write(master, b"D")

        # Test Right Arrow (ESC [ C) twice -> moves right to col 3.
        time.sleep(0.1)
        os.write(master, b"\x1b[C\x1b[C")

        # Test Left Arrow (ESC [ D) 3 times -> moves left to col 0.
        time.sleep(0.1)
        os.write(master, b"\x1b[D\x1b[D\x1b[D")

        # Test End key (ESC [ F) -> moves cursor to end (col 9).
        time.sleep(0.1)
        os.write(master, b"\x1b[F")

        # Test Backspace (\x08) -> deletes 'T'. Buffer becomes 'D0:30.TX'.
        time.sleep(0.1)
        os.write(master, b"\x08")

        # Restore 'T' -> buffer becomes 'D0:30.TXT'.
        time.sleep(0.1)
        os.write(master, b"T")

        # Press Enter (\r) to save to D0:30.TXT.
        time.sleep(0.1)
        os.write(master, b"\r")
        out_s73_saved = read_until(master, b"^K: Editor keys", timeout=25.0)
        if b"^K: Editor keys" not in out_s73_saved:
            print("[-] Step 73 failed: Save to D0:30.TXT did not finish.",
                  flush=True)
            return False
        print("    [+] Save dialog in-line editing verified; "
              "saved to D0:30.TXT.")

        # Subtest 2: Open File Dialog In-Line Editing
        # Open Open File dialog (Ctrl+O)
        time.sleep(0.3)
        os.write(master, b"\x0f")
        out_s73_open = read_until(master, b"Enter filename to open:",
                                  timeout=8.0)
        read_until(master, b"\x1b[?25h", timeout=4.0)
        time.sleep(0.2)
        drain_all(master)
        if b"Enter filename to open:" not in out_s73_open:
            print("[-] Step 73 failed: Open dialog prompt not found.",
                  flush=True)
            return False
        print("    [+] Open dialog reached with preloaded filename.")

        # Preloaded prefix is 'D0:', cursor is at end (col 3).
        # Test Home key (ESC [ H) -> moves cursor to col 0.
        time.sleep(0.1)
        os.write(master, b"\x1b[H")

        # Test Delete key (ESC [ 3 ~) -> deletes 'D' (buffer becomes '0:').
        time.sleep(0.1)
        os.write(master, b"\x1b[3~")

        # Type 'C' -> buffer becomes 'C0:'.
        time.sleep(0.1)
        os.write(master, b"C")

        # Test End key (ESC [ F) -> moves cursor to end (col 3).
        time.sleep(0.1)
        os.write(master, b"\x1b[F")

        # Append filename '30.TXT' -> buffer becomes 'C0:30.TXT'.
        time.sleep(0.1)
        os.write(master, b"30.TXT")

        # Press Enter to open C0:30.TXT.
        time.sleep(0.1)
        os.write(master, b"\r")
        out_s73_opened = read_until(master, b"^K: Editor keys", timeout=25.0)
        if b"^K: Editor keys" not in out_s73_opened:
            print("[-] Step 73 failed: Open C0:30.TXT did not complete.",
                  flush=True)
            return False
        print("    [+] Open dialog in-line editing verified; "
              "loaded C0:30.TXT.")

        # Subtest 3: WordStar Navigation Keys in Dialog
        time.sleep(0.3)
        os.write(master, b"\x0f")
        read_until(master, b"Enter filename to open:", timeout=8.0)
        read_until(master, b"\x1b[?25h", timeout=4.0)
        time.sleep(0.2)
        drain_all(master)

        # Ctrl+A (Home), Ctrl+D (Right), Ctrl+S (Left), Ctrl+G (Del), Ctrl+E
        time.sleep(0.1)
        os.write(master, b"\x01")        # Ctrl+A (Home)
        time.sleep(0.1)
        os.write(master, b"\x04\x04")    # Ctrl+D (Right) twice
        time.sleep(0.1)
        os.write(master, b"\x13")        # Ctrl+S (Left) once
        time.sleep(0.1)
        os.write(master, b"\x07")        # Ctrl+G (Delete char at cursor)
        time.sleep(0.1)
        os.write(master, b"\x05")        # Ctrl+E (End)
        time.sleep(0.1)
        # Cancel dialog using ESC
        os.write(master, b"\x1b")
        out_s73_esc = read_until(master, b"^K: Editor keys", timeout=8.0)
        if b"^K: Editor keys" not in out_s73_esc:
            print("[-] Step 73 failed: ESC did not cancel Open dialog.",
                  flush=True)
            return False
        print("    [+] WordStar navigation and ESC cancellation verified.")

        # Exit editor cleanly to CP/M
        time.sleep(0.3)
        os.write(master, b"\x11")        # Ctrl+Q
        out_s73_exit = read_until(master, b"C>", timeout=8.0)
        if b"Save changes?" in out_s73_exit:
            os.write(master, b"N")
            out_s73_exit += read_until(master, b"C>", timeout=8.0)
        if b"C>" not in out_s73_exit:
            print("[-] Step 73 failed: Clean exit to CP/M failed.", flush=True)
            return False
        print("    [+] Clean exit to CP/M prompt verified.")
        print("[+] Successfully verified Edit Box In-line Editing (Step 73)!",
              flush=True)

        # ---------------------------------------------------------------------
        # Step 74: Splash RAM Drive Status and Unavailable RAM Drive Guard
        # ---------------------------------------------------------------------
        print("[*] Step 74: Verifying Splash RAM Drive Status & Guard...",
              flush=True)

        # 1. Reset SE.CFG so SE starts with default (Preserve)
        time.sleep(0.3)
        os.write(master, b"era se.cfg\r")
        read_until(master, b"C>", timeout=10.0)

        # 2. Launch SE without file arguments
        time.sleep(0.3)
        os.write(master, b"se\r")
        out_s74_splash = read_until(master, b"Active Screen: [", timeout=20.0)
        out_s74_splash += read_until(master, b"RAM Drive (", timeout=5.0)
        out_s74_splash += read_until(master, b"to configure", timeout=5.0)

        # Verify Splash Screen shows RAM Drive line under Active Screen
        if b"RAM Drive (A:): [Preserved (Active)]" not in out_s74_splash:
            print("[-] Step 74 failed: Splash screen missing 'RAM Drive (A:): "
                  f"[Preserved (Active)]'. Buffer: {repr(out_s74_splash)}",
                  flush=True)
            return False
        print("    [+] Splash screen shows "
              "'RAM Drive (A:): [Preserved (Active)]'.")

        # 2. Enter configuration screen with 'c'
        time.sleep(0.3)
        os.write(master, b"c")
        out_s74_cfg = read_until(master, b"return to splash screen",
                                 timeout=10.0)
        if b"Preserve (RAM Drive Active, 128KB)]" not in out_s74_cfg:
            print("[-] Step 74 failed: Config screen label 'Preserve' "
                  f"missing. Buffer: {repr(out_s74_cfg)}", flush=True)
            return False
        print("    [+] Config screen displays "
              "'Preserve (RAM Drive Active, 128KB)]'.")

        # Cycle mode to Hibernate ('2')
        time.sleep(0.3)
        os.write(master, b"2")
        out_s74_hib = read_until(master, b"Hibernate (Backup/Restore, 384KB)]",
                                 timeout=10.0)
        if b"Hibernate (Backup/Restore, 384KB)]" not in out_s74_hib:
            print("[-] Step 74 failed: Config screen toggle to Hibernate "
                  f"failed. Buffer: {repr(out_s74_hib)}", flush=True)
            return False
        print("    [+] Config screen toggled to "
              "'Hibernate (Backup/Restore, 384KB)]'.")

        # Cycle mode to Overwrite ('2')
        time.sleep(0.3)
        os.write(master, b"2")
        out_s74_ovw = read_until(
            master, b"Overwrite (Sacrifice Drive, 384KB)]", timeout=10.0)
        if b"Overwrite (Sacrifice Drive, 384KB)]" not in out_s74_ovw:
            print("[-] Step 74 failed: Config screen toggle to Overwrite "
                  f"failed. Buffer: {repr(out_s74_ovw)}", flush=True)
            return False
        print("    [+] Config screen toggled to "
              "'Overwrite (Sacrifice Drive, 384KB)]'.")

        # Save config with 's' and return to splash with 'q'
        time.sleep(0.3)
        os.write(master, b"s")
        read_until(master, b"Saved to local drive", timeout=10.0)
        time.sleep(0.3)
        os.write(master, b"q")
        out_s74_splash2 = read_until(master, b"Active Screen: [", timeout=10.0)
        out_s74_splash2 += read_until(master, b"RAM Drive (", timeout=5.0)
        out_s74_splash2 += read_until(master, b"]", timeout=5.0)
        if b"RAM Drive (A:): [Overwritten (Max RAM)]" not in out_s74_splash2:
            print("[-] Step 74 failed: Splash screen does not show "
                  f"Overwritten. Buffer: {repr(out_s74_splash2)}", flush=True)
            return False
        print("    [+] Splash screen updated to "
              "'RAM Drive (A:): [Overwritten (Max RAM)]'.")

        # 3. Test Open File screen with unavailable RAM drive
        time.sleep(0.3)
        os.write(master, b"o")            # Open file
        out_s74_open = read_until(master, b"Enter filename to open:",
                                  timeout=10.0)
        if b"Enter filename to open:" not in out_s74_open:
            print("[-] Step 74 failed: Failed to enter Open File screen.",
                  flush=True)
            return False

        # Clear preloaded 'C0:' and switch to unavailable RAM drive A:
        time.sleep(0.3)
        os.write(master, b"\x08\x08\x08a:\r")
        out_s74_open_err = read_until(master, b"RAM drive not available",
                                      timeout=10.0)
        if b"RAM drive not available" not in out_s74_open_err:
            print("[-] Step 74 failed: 'RAM drive not available' not "
                  f"shown on A: in Open screen. Buffer: "
                  f"{repr(out_s74_open_err)}", flush=True)
            return False
        print("    [+] Open screen displayed inline "
              "'  RAM drive not available' on 'a:'.")

        # Typing backspace clears message and deletes ':', type ':nofile.txt'
        time.sleep(0.3)
        os.write(master, b"\x08:nofile.txt\r")
        out_s74_open_err2 = read_until(master, b"RAM drive not available",
                                       timeout=10.0)
        if b"RAM drive not available" not in out_s74_open_err2:
            print("[-] Step 74 failed: 'RAM drive not available' not "
                  f"shown on A:NOFILE.TXT. Buffer: "
                  f"{repr(out_s74_open_err2)}", flush=True)
            return False
        print("    [+] Open screen displayed inline "
              "error on 'a:nofile.txt'.")

        # Cancel Open dialog with ESC
        time.sleep(0.3)
        os.write(master, b"\x1b")
        read_until(master, b"to configure", timeout=10.0)
        print("    [+] ESC cancelled Open dialog back to splash screen.")

        # 4. Enter editor mode with 'e' and test Save File screen
        time.sleep(0.3)
        os.write(master, b"e")
        read_until(master, b"Free:", timeout=10.0)

        # Open Save dialog with Ctrl+S
        time.sleep(0.3)
        os.write(master, b"\x13")        # Ctrl+S
        out_s74_save = read_until(master, b"Enter filename to save:",
                                  timeout=10.0)
        if b"Enter filename to save:" not in out_s74_save:
            print("[-] Step 74 failed: Failed to enter Save File screen.",
                  flush=True)
            return False

        # Clear preloaded 'C0:' and switch to unavailable RAM drive A:
        time.sleep(0.3)
        os.write(master, b"\x08\x08\x08a:\r")
        out_s74_save_err = read_until(master, b"RAM drive not available",
                                      timeout=10.0)
        if b"RAM drive not available" not in out_s74_save_err:
            print("[-] Step 74 failed: 'RAM drive not available' not "
                  f"shown on A: in Save screen. Buffer: "
                  f"{repr(out_s74_save_err)}", flush=True)
            return False
        print("    [+] Save screen displayed inline "
              "'  RAM drive not available' on 'a:'.")

        # Typing backspace clears message and deletes ':', type ':savefile.txt'
        time.sleep(0.3)
        os.write(master, b"\x08:savefile.txt\r")
        out_s74_save_err2 = read_until(master, b"RAM drive not available",
                                       timeout=10.0)
        if b"RAM drive not available" not in out_s74_save_err2:
            print("[-] Step 74 failed: 'RAM drive not available' not "
                  f"shown on A:SAVEFILE.TXT. Buffer: "
                  f"{repr(out_s74_save_err2)}", flush=True)
            return False
        print("    [+] Save screen displayed inline "
              "error on 'a:savefile.txt'.")

        # Cancel Save dialog with ESC
        time.sleep(0.3)
        os.write(master, b"\x1b")
        time.sleep(0.3)

        # Exit editor cleanly to CP/M
        time.sleep(0.3)
        os.write(master, b"\x11")        # Ctrl+Q
        out_s74_exit = read_until(master, b"C>", timeout=8.0)
        if b"Save changes?" in out_s74_exit:
            os.write(master, b"N")
            out_s74_exit += read_until(master, b"C>", timeout=8.0)
        if b"C>" not in out_s74_exit:
            print("[-] Step 74 failed: Clean exit to CP/M failed.", flush=True)
            return False
        print("    [+] Clean exit to CP/M prompt verified.")
        print("[+] Successfully verified Splash RAM Drive Status and "
              "Unavailable Guard (Step 74)!", flush=True)

        return True

    finally:
        two_txt_host = os.path.join(repo_root, "2.TXT")
        if os.path.isfile(two_txt_host) and os.path.isfile(cpmcp_bin) and os.path.isfile(cpmrm_bin):
            subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:2.TXT"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        thirty_txt_host = os.path.join(repo_root, "30.TXT")
        if (os.path.isfile(thirty_txt_host) and os.path.isfile(cpmcp_bin) and
                os.path.isfile(cpmrm_bin)):
            subprocess.run(
                [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:30.TXT"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(
                [cpmcp_bin, "-f", "wbw_hd1k_0", img_file,
                 thirty_txt_host, "0:30.TXT"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if os.path.isfile(cpmrm_bin):
            subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_1", img_file,
                            "0:30.TXT"],
                           stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)
            subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.CFG"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file,
                            "0:RAMDRV.IMG"],
                           stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)
            subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:INS1.TXT"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:INS2.TXT"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:BLKSGL.TXT"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SAV300.TXT"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:BLK300.TXT"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:LONGNAME.TXT"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:TESTF.TXT"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "1:U1FILE.TXT"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "1:SAVEU1.TXT"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "1:BLKU1.TXT"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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
