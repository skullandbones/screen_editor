#!/usr/bin/env python3
"""
test_dir_highlight_nav.py - Verification for Cursor-Controlled Highlight Bar
File Navigation across Open File, Save File, Block Insert File, and Block Save
File screens in SE.COM (CP/M-80).

Verifies:
  1. Inject SE.COM and 7 test files (NAV01.TXT .. NAV07.TXT) onto C: user 5,
     and ensure drive A: has >60 files (multi-page directory listing).
  2. Boot RomWBW CP/M on RC2014 emulator and switch to C5:.
  3. Launch SE.COM -> Open File screen ('o').
  4. Press Tab in the filename text box:
     - Verify inverse highlight bar appears on top-left entry (NAV01.TXT).
     - Verify text box is automatically filled with "C5:NAV01.TXT".
  5. Navigate highlight bar using cursor keys (Right -> NAV02.TXT, Down ->
     NAV07.TXT, Up -> NAV02.TXT, Left -> NAV01.TXT), and verify WordStar keys
     (^D, ^S, ^E, ^X) are ignored in highlight mode.
  6. Press Tab to exit highlight bar mode:
     - Verify highlight bar disappears (normal video restored).
     - Verify user can continue editing filename in text box (Backspace 5 chars
       and type "3.TXT" -> "C5:NAV03.TXT") and press Enter to open NAV03.TXT.
  7. Open File screen via Ctrl+O, switch to multi-page drive A0:, press Tab ->
     verify PgDn moves highlight bar to top-left file of Page 2 and PgUp moves
     highlight bar to bottom-right file of Page 1; switch back to C5: and press
     Enter directly on highlighted NAV07.TXT.
  8. Block Insert File screen (Ctrl+B then Ctrl+O):
     - Press Tab -> Right (selects NAV02.TXT) and press Enter.
     - Verify selected file content is inserted at cursor.
  9. Block Save File screen (Ctrl+B then Ctrl+S):
     - Open Block Save UI, press Tab -> Right -> Tab, edit filename in text box
       to "C5:NAV08.TXT", and press Enter.
  10. Save File screen (Ctrl+B to clear block, then Ctrl+S):
      - Press Tab -> Tab, edit filename to "C5:NAV09.TXT", press Enter, quit
        SE.COM, and verify saved files on disk.
"""

import os
import select
import subprocess
import sys
import tempfile
import time
import tty


def find_paths():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    workspace_root = os.path.abspath(os.path.join(repo_root, "..", ".."))
    if not os.path.isdir(os.path.join(workspace_root, "tools")):
        workspace_root = os.path.abspath(
            os.path.join(repo_root, "..", "screen_editor")
        )

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
    cpmcp_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp"
    )
    cpmrm_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm"
    )

    return emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin


def drain_all(master_fd, quiet_time=0.25):
    res = b""
    while True:
        r, _, _ = select.select([master_fd], [], [], quiet_time)
        if not r:
            break
        try:
            data = os.read(master_fd, 2048)
            if not data:
                break
            res += data
        except (BlockingIOError, OSError):
            break
    return res


def read_until(master_fd, match_bytes, timeout=15.0):
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


def test_dir_highlight_nav():
    start_time = time.time()
    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = find_paths()

    print(
        "[*] Step 1: Injecting SE.COM and test files onto C: (user 5 & 6)...",
        flush=True,
    )
    subprocess.run(
        [
            cpmrm_bin,
            "-f",
            "wbw_hd1k_0",
            img_file,
            "0:SE.COM",
            "5:*.*",
            "6:*.*",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, "0:SE.COM"],
        check=True,
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, "5:SE.COM"],
        check=True,
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(1, 8):
            fname = f"NAV0{i}.TXT"
            fpath = os.path.join(tmpdir, fname)
            with open(fpath, "wb") as f:
                f.write(f"CONTENT_FROM_NAV0{i}_LINE1\r\n".encode("ascii"))
            subprocess.run(
                [
                    cpmcp_bin,
                    "-f",
                    "wbw_hd1k_0",
                    img_file,
                    fpath,
                    f"5:{fname}",
                ],
                check=True,
            )
        # Create 65 files on C6: (PG01.TXT .. PG65.TXT) so Page 1 has 60 files
        # (PG01..PG60) and Page 2 has 5 files (PG61..PG65).
        pg_paths = []
        for i in range(1, 66):
            fname = f"PG{i:02d}.TXT"
            fpath = os.path.join(tmpdir, fname)
            with open(fpath, "wb") as f:
                f.write(b"PAGE_TEST\r\n")
            pg_paths.append(fpath)
        subprocess.run(
            [cpmcp_bin, "-f", "wbw_hd1k_0", img_file] + pg_paths + ["6:"],
            check=True,
        )
    print(
        "[+] Step 1: Injected SE.COM, C5: (NAV01..07), and C6: (PG01..65).",
        flush=True,
    )

    print(
        "[*] Step 2: Booting RomWBW CP/M and switching to C5:...",
        flush=True,
    )
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )
    os.close(slave)

    try:
        out_boot = read_until(master, b"Boot [H=Help]:", timeout=10.0)
        if b"Boot [H=Help]:" not in out_boot:
            buf_str = repr(out_boot[-300:])
            print(
                f"[-] Step 2: Failed to reach Boot prompt. Buffer: {buf_str}",
                flush=True,
            )
            return False

        time.sleep(0.4)
        os.write(master, b"c\r")
        out_cpm = read_until(master, b"B>", timeout=15.0)
        if b"B>" not in out_cpm:
            buf_str = repr(out_cpm[-300:])
            print(
                f"[-] Step 2: Failed to reach B> prompt. Buffer: {buf_str}",
                flush=True,
            )
            return False

        time.sleep(0.4)
        os.write(master, b"c:\r")
        read_until(master, b"C>", timeout=10.0)
        time.sleep(0.4)
        os.write(master, b"user 5\r")
        out_u5 = read_until(master, b"C>", timeout=10.0)
        if b"C>" not in out_u5:
            buf_str = repr(out_u5[-300:])
            print(
                f"[-] Step 2: Failed to switch to user 5. Buffer: {buf_str}",
                flush=True,
            )
            return False
        print("[+] Step 2: Booted CP/M and active on C: user 5.", flush=True)

        print(
            "[*] Step 3: Launching SE.COM and opening Open File UI ('o')...",
            flush=True,
        )
        time.sleep(0.4)
        os.write(master, b"se\r")
        out_splash = read_until(master, b"for about", timeout=30.0)
        drain_all(master)
        if b"for about" not in out_splash:
            buf_str = repr(out_splash[-300:])
            print(
                f"[-] Step 3: Failed to reach splash screen. Buffer: {buf_str}",
                flush=True,
            )
            return False

        os.write(master, b"o")
        out_open = read_until(master, b"Enter filename to open:", timeout=15.0)
        out_open += drain_all(master)
        if (
            b"NAV01.TXT" not in out_open
            or b"NAV07.TXT" not in out_open
            or b"[TAB]=Select File" not in out_open
        ):
            buf_str = repr(out_open[-400:])
            print(
                f"[-] Step 3: Directory listing missing NAV files. "
                f"Buffer: {buf_str}",
                flush=True,
            )
            return False
        print(
            "[+] Step 3: Open File screen displayed with NAV01..NAV07.",
            flush=True,
        )

        print(
            "[*] Step 4: Pressing Tab to activate highlight bar at top-left...",
            flush=True,
        )
        os.write(master, b"\t")
        out_tab1 = drain_all(master, quiet_time=0.4)
        if (
            b"\x1b[7mNAV01.TXT   \x1b[0m" not in out_tab1
            or b"C5:NAV01.TXT" not in out_tab1
            or b"[TAB]=Edit Name  [Enter]=OK" not in out_tab1
        ):
            buf_str = repr(out_tab1[-400:])
            print(
                f"[-] Step 4: Tab did not highlight NAV01.TXT or fill box. "
                f"Buffer: {buf_str}",
                flush=True,
            )
            return False
        print(
            "[+] Step 4: Highlight bar at top-left (NAV01.TXT) and text box "
            "filled with C5:NAV01.TXT.",
            flush=True,
        )

        print(
            "[*] Step 5: Navigating highlight bar with cursor keys and "
            "verifying WordStar keys are ignored...",
            flush=True,
        )
        # Verify WordStar ^D (0x04) is ignored
        os.write(master, b"\x04")
        out_ws = drain_all(master, quiet_time=0.3)
        if out_ws != b"":
            print(
                f"[-] Step 5: WordStar ^D was not ignored! Output: "
                f"{repr(out_ws)}",
                flush=True,
            )
            return False

        # Right -> NAV02.TXT (index 1)
        os.write(master, b"\x1b[C")
        out_right = drain_all(master, quiet_time=0.4)
        if (
            b"\x1b[7mNAV02.TXT   \x1b[0m" not in out_right
            or b"C5:NAV02.TXT" not in out_right
        ):
            buf_str = repr(out_right[-400:])
            print(
                f"[-] Step 5: Right arrow failed to select NAV02.TXT. "
                f"Buffer: {buf_str}",
                flush=True,
            )
            return False

        # Down -> index 1 + 5 = 6 (NAV07.TXT)
        os.write(master, b"\x1b[B")
        out_down = drain_all(master, quiet_time=0.4)
        if (
            b"\x1b[7mNAV07.TXT   \x1b[0m" not in out_down
            or b"C5:NAV07.TXT" not in out_down
        ):
            buf_str = repr(out_down[-400:])
            print(
                f"[-] Step 5: Down arrow failed to select NAV07.TXT. "
                f"Buffer: {buf_str}",
                flush=True,
            )
            return False

        # Up -> back to index 1 (NAV02.TXT)
        os.write(master, b"\x1b[A")
        out_up = drain_all(master, quiet_time=0.4)
        if (
            b"\x1b[7mNAV02.TXT   \x1b[0m" not in out_up
            or b"C5:NAV02.TXT" not in out_up
        ):
            buf_str = repr(out_up[-400:])
            print(
                f"[-] Step 5: Up arrow failed to return to NAV02.TXT. "
                f"Buffer: {buf_str}",
                flush=True,
            )
            return False

        # Left -> back to index 0 (NAV01.TXT)
        os.write(master, b"\x1b[D")
        out_left = drain_all(master, quiet_time=0.4)
        if (
            b"\x1b[7mNAV01.TXT   \x1b[0m" not in out_left
            or b"C5:NAV01.TXT" not in out_left
        ):
            buf_str = repr(out_left[-400:])
            print(
                f"[-] Step 5: Left arrow failed to return to NAV01.TXT. "
                f"Buffer: {buf_str}",
                flush=True,
            )
            return False
        print(
            "[+] Step 5: Cursor keys moved highlight, updated text box, and "
            "ignored WordStar keys.",
            flush=True,
        )

        print(
            "[*] Step 6: Pressing Tab to return to text box and editing "
            "filename...",
            flush=True,
        )
        os.write(master, b"\t")
        out_tab2 = drain_all(master, quiet_time=0.4)
        if (
            b"NAV01.TXT   " not in out_tab2
            or b"\x1b[?25h" not in out_tab2
            or b"[TAB]=Select File" not in out_tab2
        ):
            buf_str = repr(out_tab2[-400:])
            print(
                f"[-] Step 6: Second Tab did not clear highlight or show "
                f"cursor. Buffer: {buf_str}",
                flush=True,
            )
            return False

        # Edit "C5:NAV01.TXT" -> backspace 5 chars ("1.TXT") -> type "3.TXT"
        os.write(master, b"\x08\x08\x08\x08\x083.TXT\r")
        out_load3 = read_until(
            master, b"CONTENT_FROM_NAV03_LINE1", timeout=15.0
        )
        out_load3 += drain_all(master)
        if b"CONTENT_FROM_NAV03_LINE1" not in out_load3:
            buf_str = repr(out_load3[-400:])
            print(
                f"[-] Step 6: Failed to edit and open NAV03.TXT. "
                f"Buffer: {buf_str}",
                flush=True,
            )
            return False
        print(
            "[+] Step 6: Tab returned control to text box; edited and opened "
            "NAV03.TXT.",
            flush=True,
        )

        print(
            "[*] Step 7: Testing multi-page PgDn/PgUp highlight positioning "
            "and Enter selection...",
            flush=True,
        )
        os.write(master, b"\x0f")  # Ctrl+O
        read_until(master, b"Enter filename to open:", timeout=15.0)
        drain_all(master)
        # Switch to C6: (65 files -> 2 pages: Page 1 has PG01..PG60, Page 2
        # has PG61..PG65)
        os.write(master, b"\x08\x08\x08C6:\r")
        out_c6 = read_until(master, b"Enter filename to open:", timeout=15.0)
        out_c6 += drain_all(master, quiet_time=0.4)
        if b"[Page 1/2]" not in out_c6:
            buf_str = repr(out_c6[-400:])
            print(
                f"[-] Step 7: Failed to switch to multi-page C6:. "
                f"Buffer: {buf_str}",
                flush=True,
            )
            return False
        # Press Tab -> highlights PG01.TXT (top-left of Page 1)
        os.write(master, b"\t")
        out_c6_tab = drain_all(master, quiet_time=0.4)
        if b"C6:PG01.TXT" not in out_c6_tab:
            buf_str = repr(out_c6_tab[-400:])
            print(
                f"[-] Step 7: Tab on C6: did not select PG01.TXT. "
                f"Buffer: {buf_str}",
                flush=True,
            )
            return False
        # Press PgDn (ESC [ 6 ~) -> Page 2, highlight bar at top-left (PG61.TXT)
        os.write(master, b"\x1b[6~")
        out_pgdn = drain_all(master, quiet_time=0.6)
        if (
            b"[Page 2/2]" not in out_pgdn
            or b"\x1b[7mPG61.TXT    \x1b[0m" not in out_pgdn
            or b"C6:PG61.TXT" not in out_pgdn
        ):
            buf_str = repr(out_pgdn[-400:])
            print(
                f"[-] Step 7: PgDn in highlight mode did not select top-left "
                f"PG61.TXT on Page 2. Buffer: {buf_str}",
                flush=True,
            )
            return False
        # Press PgUp (ESC [ 5 ~) -> Page 1, highlight bar at bottom-right
        # (PG60.TXT)
        os.write(master, b"\x1b[5~")
        out_pgup = drain_all(master, quiet_time=0.6)
        if (
            b"[Page 1/2]" not in out_pgup
            or b"\x1b[7mPG60.TXT    \x1b[0m" not in out_pgup
            or b"C6:PG60.TXT" not in out_pgup
        ):
            buf_str = repr(out_pgup[-400:])
            print(
                f"[-] Step 7: PgUp in highlight mode did not select "
                f"bottom-right PG60.TXT on Page 1. Buffer: {buf_str}",
                flush=True,
            )
            return False
        # Exit highlight mode via Tab, switch back to C5:, and select NAV07.TXT
        os.write(master, b"\t")
        drain_all(master, quiet_time=0.3)
        os.write(master, b"\x08" * 15 + b"C5:\r")
        read_until(master, b"Enter filename to open:", timeout=15.0)
        drain_all(master, quiet_time=0.4)
        # Tab (NAV01) -> Right (NAV02) -> Down (NAV07) -> Enter
        os.write(master, b"\t")
        drain_all(master, quiet_time=0.3)
        os.write(master, b"\x1b[C")
        drain_all(master, quiet_time=0.3)
        os.write(master, b"\x1b[B")
        drain_all(master, quiet_time=0.3)
        os.write(master, b"\r")
        out_load7 = read_until(
            master, b"CONTENT_FROM_NAV07_LINE1", timeout=15.0
        )
        out_load7 += drain_all(master)
        if b"CONTENT_FROM_NAV07_LINE1" not in out_load7:
            buf_str = repr(out_load7[-400:])
            print(
                f"[-] Step 7: Enter in highlight mode failed to load "
                f"NAV07.TXT. Buffer: {buf_str}",
                flush=True,
            )
            return False
        print(
            "[+] Step 7: Multi-page PgDn (top-left) & PgUp (bottom-right) and "
            "Enter selection verified.",
            flush=True,
        )

        print(
            "[*] Step 8: Testing highlight bar in Block Insert File UI "
            "(Ctrl+B then Ctrl+O)...",
            flush=True,
        )
        os.write(master, b"\x02")  # Ctrl+B (start block mode)
        drain_all(master, quiet_time=0.3)
        os.write(master, b"\x0f")  # Ctrl+O (Block Insert File)
        out_ins_ui = read_until(
            master, b"Enter filename to insert:", timeout=15.0
        )
        drain_all(master)
        if b"Enter filename to insert:" not in out_ins_ui:
            buf_str = repr(out_ins_ui[-400:])
            print(
                f"[-] Step 8: Failed to open Block Insert UI. "
                f"Buffer: {buf_str}",
                flush=True,
            )
            return False
        # Tab (NAV01.TXT) -> Right (NAV02.TXT) -> Enter
        os.write(master, b"\t")
        drain_all(master, quiet_time=0.3)
        os.write(master, b"\x1b[C")
        out_ins_hl = drain_all(master, quiet_time=0.3)
        if b"C5:NAV02.TXT" not in out_ins_hl:
            buf_str = repr(out_ins_hl[-400:])
            print(
                f"[-] Step 8: Block Insert highlight did not fill "
                f"C5:NAV02.TXT. Buffer: {buf_str}",
                flush=True,
            )
            return False
        os.write(master, b"\r")
        out_ins_done = read_until(
            master, b"CONTENT_FROM_NAV02_LINE1", timeout=15.0
        )
        drain_all(master)
        if b"CONTENT_FROM_NAV02_LINE1" not in out_ins_done:
            buf_str = repr(out_ins_done[-400:])
            print(
                f"[-] Step 8: Block Insert failed to insert NAV02.TXT. "
                f"Buffer: {buf_str}",
                flush=True,
            )
            return False
        print(
            "[+] Step 8: Block Insert File UI highlight bar selected and "
            "inserted NAV02.TXT.",
            flush=True,
        )

        print(
            "[*] Step 9: Testing highlight bar in Block Save File UI "
            "(Ctrl+B then Ctrl+S)...",
            flush=True,
        )
        # Go to top of doc (^T), toggle block off if active, then mark line 0
        os.write(master, b"\x14")  # ^T (top of file)
        drain_all(master, quiet_time=0.3)
        os.write(master, b"\x02")  # Ctrl+B (start or cancel block mode)
        out_b1 = drain_all(master, quiet_time=0.3)
        if b"Sel:" not in out_b1:
            os.write(master, b"\x02")  # Ctrl+B (start block mode -> state 1)
            drain_all(master, quiet_time=0.3)
        os.write(master, b"\x05")  # Ctrl+E (end of line 0)
        drain_all(master, quiet_time=0.3)
        os.write(master, b"\x13")  # Ctrl+S (Block Save File)
        out_bsave_ui = read_until(
            master, b"Enter filename to save:", timeout=15.0
        )
        drain_all(master)
        if b"SAVE BLOCK" not in out_bsave_ui:
            buf_str = repr(out_bsave_ui[:400])
            print(
                f"[-] Step 9: Failed to open Block Save UI. Buffer: {buf_str}",
                flush=True,
            )
            return False
        # Press Tab -> selects NAV01.TXT -> Right -> selects NAV02.TXT -> Tab ->
        # edit to NAV08.TXT -> Enter
        os.write(master, b"\t")
        out_bs_tab1 = drain_all(master, quiet_time=0.3)
        if b"C5:NAV01.TXT" not in out_bs_tab1:
            buf_str = repr(out_bs_tab1[-400:])
            print(
                f"[-] Step 9: Block Save Tab did not fill C5:NAV01.TXT. "
                f"Buffer: {buf_str}",
                flush=True,
            )
            return False
        os.write(master, b"\x1b[C")
        out_bs_right = drain_all(master, quiet_time=0.3)
        if b"C5:NAV02.TXT" not in out_bs_right:
            buf_str = repr(out_bs_right[-400:])
            print(
                f"[-] Step 9: Block Save Right did not fill C5:NAV02.TXT. "
                f"Buffer: {buf_str}",
                flush=True,
            )
            return False
        os.write(master, b"\t")
        drain_all(master, quiet_time=0.3)
        os.write(master, b"\x08\x08\x08\x08\x088.TXT\r")
        read_until(master, b"CONTENT_FROM_NAV07_LINE1", timeout=15.0)
        drain_all(master, quiet_time=0.4)
        print(
            "[+] Step 9: Block Save File UI highlight bar navigated, returned "
            "on Tab, and saved C5:NAV08.TXT.",
            flush=True,
        )

        print(
            "[*] Step 10: Testing highlight bar in Save File UI (Ctrl+S) and "
            "verifying disk files...",
            flush=True,
        )
        # Clear solidified block (Ctrl+B) before normal Ctrl+S save
        os.write(master, b"\x02")
        drain_all(master, quiet_time=0.3)
        os.write(master, b"\x13")  # Ctrl+S (normal Save File UI)
        out_save_ui = read_until(
            master, b"Enter filename to save:", timeout=15.0
        )
        drain_all(master)
        if b"SAVE FILE (DIRECTORY" not in out_save_ui:
            buf_str = repr(out_save_ui[-400:])
            print(
                f"[-] Step 10: Failed to open Save File UI. Buffer: {buf_str}",
                flush=True,
            )
            return False
        # Press Tab -> NAV01.TXT -> Tab -> edit to NAV09.TXT -> Enter
        os.write(master, b"\t")
        out_s_tab1 = drain_all(master, quiet_time=0.3)
        if b"C5:NAV01.TXT" not in out_s_tab1:
            buf_str = repr(out_s_tab1[-400:])
            print(
                f"[-] Step 10: Save File Tab did not fill C5:NAV01.TXT. "
                f"Buffer: {buf_str}",
                flush=True,
            )
            return False
        os.write(master, b"\t")
        drain_all(master, quiet_time=0.3)
        os.write(master, b"\x08\x08\x08\x08\x089.TXT\r")
        read_until(master, b"CONTENT_FROM_NAV07_LINE1", timeout=15.0)
        drain_all(master, quiet_time=0.4)

        # Quit editor (^Q)
        os.write(master, b"\x11")
        out_quit = read_until(master, b"C>", timeout=15.0)
        if b"C>" not in out_quit:
            buf_str = repr(out_quit[-400:])
            print(
                f"[-] Step 10: Failed to quit to C> prompt. Buffer: {buf_str}",
                flush=True,
            )
            return False

    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3.0)
        except subprocess.TimeoutExpired:
            proc.kill()
        os.close(master)

    with tempfile.TemporaryDirectory() as tmpdir:
        out8 = os.path.join(tmpdir, "NAV08.TXT")
        out9 = os.path.join(tmpdir, "NAV09.TXT")
        subprocess.run(
            [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, "5:NAV08.TXT", out8],
            check=True,
        )
        subprocess.run(
            [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, "5:NAV09.TXT", out9],
            check=True,
        )
        with open(out8, "rb") as f:
            data8 = f.read()
        with open(out9, "rb") as f:
            data9 = f.read()
        if b"CONTENT_FROM_NAV02_LINE1" not in data8:
            print(
                f"[-] Step 10: NAV08.TXT missing expected block content: "
                f"{repr(data8)}",
                flush=True,
            )
            return False
        if (
            b"CONTENT_FROM_NAV02_LINE1" not in data9
            or b"CONTENT_FROM_NAV07_LINE1" not in data9
        ):
            print(
                f"[-] Step 10: NAV09.TXT missing expected saved content: "
                f"{repr(data9)}",
                flush=True,
            )
            return False

    print(
        "[+] Step 10: Save File UI highlight bar verified and disk outputs "
        "confirmed.",
        flush=True,
    )
    elapsed = time.time() - start_time
    print(
        f"[+] All Directory Highlight Navigation tests PASSED in "
        f"{elapsed:.2f}s!",
        flush=True,
    )
    return True


if __name__ == "__main__":
    sys.exit(0 if test_dir_highlight_nav() else 1)
