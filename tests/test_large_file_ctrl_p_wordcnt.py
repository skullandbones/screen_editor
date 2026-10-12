#!/usr/bin/env python3
"""
test_large_file_ctrl_p_wordcnt.py - Reproduces and validates the large file
Ctrl+P plugin pop-up dialog issues in SE.COM:
  1. Opens a large file (3,000 lines).
  2. Opens the Ctrl+P plugin pop-up dialog.
  3. Checks text alignment on the right-hand side of the pop-up box
     (detecting overruns beyond the box border).
  4. Runs [0] WORDCNT via Enter and waits for Document Statistics dialog.
  5. Clears the WORDCNT dialog and checks for hierarchical modal return
     to the Ctrl+P menu.
  6. Attempts typing in the editor and validates cursor placement and
     screen bounds (detecting cursor positioning off the screen).
"""

import os
import re
import select
import subprocess
import sys
import time
import tty


def find_paths(use_sec=False):
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    workspace_root = repo_root
    curr = script_dir
    while curr != os.path.dirname(curr):
        if os.path.isdir(os.path.join(curr, "tools", "romwbw_src")):
            workspace_root = curr
            break
        curr = os.path.dirname(curr)

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
    se_bin = os.path.join(repo_root, "SEC.COM" if use_sec else "SE.COM")
    cpmcp_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp"
    )
    cpmrm_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm"
    )

    return emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin


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
        time.sleep(0.01)
    return buf


def drain_all(master_fd, timeout=0.2):
    buf = b""
    t0 = time.time()
    while time.time() - t0 < timeout:
        r, _, _ = select.select([master_fd], [], [], 0.02)
        if r:
            try:
                data = os.read(master_fd, 1024)
                if not data:
                    break
                buf += data
            except (BlockingIOError, OSError):
                break
        else:
            break
    return buf


class ScreenBuffer:
    """Minimal VT100 screen buffer for layout inspection."""
    def __init__(self, cols=80, rows=24):
        self.cols = cols
        self.rows = rows
        self.buffer = [[" " for _ in range(cols)] for _ in range(rows)]
        self.r = 0
        self.c = 0
        self.cursor_seqs = []

    def feed(self, text):
        i = 0
        n = len(text)
        while i < n:
            ch = text[i]
            if ch == "\r":
                self.c = 0
                i += 1
            elif ch == "\n":
                if self.r < self.rows - 1:
                    self.r += 1
                i += 1
            elif ch == "\x08":
                self.c = max(0, self.c - 1)
                i += 1
            elif ch == "\x1b":
                sub = text[i:]
                m = re.match(r"^\x1b\[([0-9;]*)([A-Za-z])", sub)
                if m:
                    params_str, cmd = m.groups()
                    params = [
                        int(p) for p in params_str.split(";") if p.isdigit()
                    ]
                    if cmd in ("H", "f"):
                        row = params[0] if len(params) > 0 else 1
                        col = params[1] if len(params) > 1 else 1
                        self.cursor_seqs.append((row, col, m.group(0)))
                        self.r = min(self.rows - 1, max(0, row - 1))
                        self.c = min(self.cols - 1, max(0, col - 1))
                    elif cmd == "J":
                        mode = params[0] if params else 0
                        if mode in (0, 2):
                            self.buffer = [
                                [" " for _ in range(self.cols)]
                                for _ in range(self.rows)
                            ]
                            self.r = 0
                            self.c = 0
                    elif cmd == "K":
                        for c_idx in range(self.c, self.cols):
                            self.buffer[self.r][c_idx] = " "
                    i += len(m.group(0))
                    continue
                m2 = re.match(r"^\x1b\[\?[0-9]+[hl]", sub)
                if m2:
                    i += len(m2.group(0))
                    continue
                i += 1
            else:
                if 0 <= self.r < self.rows and 0 <= self.c < self.cols:
                    self.buffer[self.r][self.c] = ch
                    self.c += 1
                i += 1

    def render(self):
        border = "+" + "-" * self.cols + "+"
        lines = [border]
        for row in self.buffer:
            lines.append("|" + "".join(row) + "|")
        lines.append(border)
        return "\n".join(lines)


def main(use_sec=False):
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    (
        emu_bin, rom_file, img_file, se_bin,
        cpmcp_bin, cpmrm_bin
    ) = find_paths(use_sec=use_sec)
    target_name = "SEC.COM" if use_sec else "SE.COM"
    target_cpm = "0:SEC.COM" if use_sec else "0:SE.COM"
    cmd_name = b"sec" if use_sec else b"se"

    for p, name in [
        (emu_bin, "RC2014 emulator"), (rom_file, "ROM file"),
        (img_file, "Disk image"), (se_bin, f"{target_name} binary"),
        (cpmcp_bin, "cpmcp binary"), (cpmrm_bin, "cpmrm binary")
    ]:
        if not os.path.isfile(p):
            print(f"[-] Error: {name} not found at {p}")
            sys.exit(1)

    print("=" * 76)
    print("  SE.COM Large File (3000 lines) Ctrl+P & WORDCNT Regression Test")
    print("=" * 76)

    # 1. Generate 3000-line test file
    test_lines = 3000
    tmp_txt = f"/tmp/test_{test_lines}_{os.getpid()}.txt"
    print(f"[*] Generating {test_lines}-line test file at {tmp_txt}...")
    with open(tmp_txt, "w") as f:
        for idx in range(1, test_lines + 1):
            f.write(
                f"Line {idx:04d} of test file content for wordcnt bug "
                f"reproduction\r\n"
            )

    # 2. Create isolated ephemeral disk image
    ephemeral_img = os.path.join(
        "/tmp", f"monkey_3000_{os.getpid()}_{int(time.time() * 1000)}.img"
    )
    subprocess.run(
        ["cp", "--reflink=auto", "--sparse=always", img_file, ephemeral_img],
        check=True,
    )
    os.chmod(ephemeral_img, 0o644)
    print(f"[*] Ephemeral disk initialized: {ephemeral_img}")

    # Setup SE.CFG for 80x24 mode and RAMDRIVE=ON (fast Far RAM paging)
    cfg_tmp = f"/tmp/se_cfg_{os.getpid()}.cfg"
    with open(cfg_tmp, "wb") as f:
        f.write(b"SCREEN=80x24\r\nRAMDRIVE=ON\r\n")

    # Remove existing files from disk image if present, then inject
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", ephemeral_img, "0:SE.CFG"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", ephemeral_img, "0:$$$se$$$.swp"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", ephemeral_img, target_cpm],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", ephemeral_img, "0:3000.TXT"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", ephemeral_img, se_bin, target_cpm],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", ephemeral_img, cfg_tmp, "0:SE.CFG"],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", ephemeral_img, tmp_txt, "0:3000.TXT"],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )

    # Inject freshly built plugin binaries so tests run against active code
    plugin_files = [
        "PLUGIN.PRL", "PLUGIN.CFG", "ROT13.PRL", "WORDCNT.OVL", "BEAUTIFY.PRL"
    ]
    for p_name in plugin_files:
        p_path = os.path.join(repo_root, "plugins", p_name)
        if os.path.isfile(p_path):
            subprocess.run(
                [cpmrm_bin, "-f", "wbw_hd1k_0", ephemeral_img, f"0:{p_name}"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            subprocess.run(
                [cpmcp_bin, "-f", "wbw_hd1k_0", ephemeral_img,
                 p_path, f"0:{p_name}"],
                check=True, stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", ephemeral_img]
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )
    os.close(slave)

    bugs_detected = []
    screen = ScreenBuffer(cols=80, rows=24)

    try:
        # Boot CP/M
        out = read_until(master, b"Boot [H=Help]:", timeout=8.0)
        if b"Boot [H=Help]:" not in out:
            raise RuntimeError("RomWBW boot prompt not reached.")
        time.sleep(0.3)
        os.write(master, b"c\r")
        read_until(master, b"B>", timeout=6.0)
        time.sleep(0.3)
        os.write(master, b"c:\r")
        read_until(master, b"C>", timeout=8.0)
        print("[+] Switched to Drive C>.")

        # Open 3000-line file in SE.COM
        time.sleep(0.5)
        t0 = time.time()
        os.write(master, cmd_name + b" 3000.txt\r")
        print("[*] Loading 3000.TXT into SE.COM (standard 80x24)...")
        ed_out = read_until(master, b"1/3000", timeout=120.0)
        dt = time.time() - t0
        time.sleep(0.3)
        ed_out += drain_all(master)
        screen.feed(ed_out.decode("latin1", errors="replace"))

        if b"1/3000" not in ed_out:
            raise RuntimeError(
                f"SE.COM failed to open 3000.TXT within 120s. "
                f"Buffer: {repr(ed_out[-300:])}"
            )
        print(f"[+] 3000.TXT successfully loaded in editor in {dt:.1f}s.")
        print(f"    Status: {''.join(screen.buffer[23])}")

        # -------------------------------------------------------------
        # STEP 1: Open Ctrl+P plugin pop-up dialog
        # -------------------------------------------------------------
        print("\n[*] STEP 1: Pressing Ctrl+P to open plugin pop-up...")
        time.sleep(0.3)
        drain_all(master)
        screen.cursor_seqs.clear()
        os.write(master, b"\x10")  # Ctrl+P
        popup_out = read_until(master, b"Exit", timeout=8.0)
        time.sleep(0.2)
        popup_out += drain_all(master, timeout=0.2)
        screen.feed(popup_out.decode("latin1", errors="replace"))

        print(">>> [SCREEN GRAB: Ctrl+P Pop-up Dialog]")
        print(screen.render())

        # Inspect alignment on the right-hand side of the pop-up box
        # Box top border is "+------------------------------------------------+"
        # Exactly 50 chars wide. All rows in box must have '|' at same col.
        border_col_start = None
        border_col_end = None
        misaligned_rows = []

        for r_idx, row in enumerate(screen.buffer):
            line_str = "".join(row)
            if "+------------------------------------------------+" in line_str:
                border_col_start = line_str.find("+")
                border_col_end = line_str.rfind("+")
                break

        if border_col_start is not None and border_col_end is not None:
            width = border_col_end - border_col_start + 1
            print(f"[*] Box border: {border_col_start}..{border_col_end}"
                  f" (width: {width})")
            for r_idx, row in enumerate(screen.buffer):
                line_str = "".join(row)
                if ("|" in line_str and
                        r_idx < 23 and  # exclude status bar
                        border_col_start < len(line_str)):
                    first_pipe = line_str.find("|", border_col_start)
                    last_pipe = line_str.rfind("|")
                    if first_pipe == border_col_start:
                        if last_pipe != border_col_end:
                            misaligned_rows.append(
                                (r_idx, line_str, last_pipe, border_col_end)
                            )

        if misaligned_rows:
            bug_msg = (
                "Ctrl+P pop-up dialog has bad text alignment on right "
                "border:\n"
            )
            for r_idx, row_text, actual_col, expected_col in misaligned_rows:
                bug_msg += (
                    f"  Row {r_idx:2d}: right border '|' at col {actual_col} "
                    f"(expected {expected_col}):\n    '{row_text.strip()}'\n"
                )
            print(f"[-] BUG CONFIRMED: {bug_msg}")
            bugs_detected.append("CTRL_P_RIGHT_BORDER_MISALIGNMENT")
        else:
            print("[+] Right-hand border alignment is clean.")

        # -------------------------------------------------------------
        # STEP 2: Press Enter to execute [0] WORDCNT
        # -------------------------------------------------------------
        print("\n[*] STEP 2: Pressing Enter to run [0] WORDCNT...")
        time.sleep(0.3)
        drain_all(master)
        screen.cursor_seqs.clear()
        os.write(master, b"\r")  # Enter

        print("[*] Waiting for WORDCNT to count 3,000 lines...")
        t0 = time.time()
        wcnt_out = read_until(master, b"Document Statistics", timeout=90.0)
        dt = time.time() - t0
        time.sleep(0.3)
        wcnt_out += drain_all(master)
        screen.feed(wcnt_out.decode("latin1", errors="replace"))

        if b"Document Statistics" not in wcnt_out:
            raise RuntimeError(
                f"WORDCNT Document Statistics dialog failed within 90s. "
                f"Buffer: {repr(wcnt_out[-300:])}"
            )
        print(f"[+] WORDCNT dialog displayed after {dt:.1f}s.")

        print(">>> [SCREEN GRAB: WORDCNT Results Dialog]")
        print(screen.render())

        # -------------------------------------------------------------
        # STEP 3: Clear WORDCNT pop-up and check modal hierarchy
        # -------------------------------------------------------------
        print("\n[*] STEP 3: Pressing Space to clear WORDCNT pop-up...")
        time.sleep(0.3)
        drain_all(master)
        screen.cursor_seqs.clear()
        os.write(master, b" ")  # Clear WORDCNT dialog

        # Wait for Ctrl+P popup to be restored hierarchically (or timeout)
        post_wcnt_out = read_until(master, b"Plugins for Editor", timeout=6.0)
        time.sleep(0.3)
        post_wcnt_out += drain_all(master, timeout=0.3)
        screen.feed(post_wcnt_out.decode("latin1", errors="replace"))

        print(">>> [SCREEN GRAB: Screen immediately after clearing WORDCNT]")
        print(screen.render())

        # Check if original Ctrl+P popup is restored (hierarchical)
        post_text = "".join("".join(r) for r in screen.buffer)
        if "Plugins for Editor" in post_text:
            print("[+] Hierarchical return: Ctrl+P pop-up restored cleanly.")
        else:
            print(
                "[-] BUG CONFIRMED: Original Ctrl+P pop-up disappeared! "
                "Modal hierarchy broken."
            )
            bugs_detected.append("CTRL_P_HIERARCHY_LOST")

        # -------------------------------------------------------------
        # STEP 4: Test typing into editor screen & cursor positioning
        # -------------------------------------------------------------
        print("\n[*] STEP 4: Inspecting cursor positioning & testing "
              "editor typing...")

        # If Ctrl+P pop-up is active on screen, dismiss it with ESC to return
        # to editor
        if "Plugins for Editor" in post_text:
            print("[*] Dismissing Ctrl+P pop-up with ESC to return...")
            screen.cursor_seqs.clear()
            os.write(master, b"\x1b")
            esc_out = read_until(master, b"1/3000", timeout=8.0)
            time.sleep(0.3)
            esc_out += drain_all(master, timeout=0.3)
            screen.feed(esc_out.decode("latin1", errors="replace"))

        # Inspect cursor positioning sequences received on return to editor
        invalid_cursor_seqs = []
        for row, col, raw_seq in screen.cursor_seqs:
            if row < 1 or row > 24:  # Valid terminal screen rows are 1..24
                invalid_cursor_seqs.append((row, col, raw_seq))

        if invalid_cursor_seqs:
            print(
                "[-] BUG CONFIRMED: Out-of-bounds cursor positioning detected:"
            )
            for r, c, seq in invalid_cursor_seqs:
                print(
                    f"    Cursor row {r}, col {c} ({repr(seq)}) - OFF SCREEN!"
                )
            bugs_detected.append("CURSOR_OUT_OF_BOUNDS")
        else:
            print("[+] All cursor coordinates within screen bounds [1..24].")

        # Verify active editor caret is restored to row 1, col 1 (Line 1)
        editor_cursor_seqs = [
            (r, c) for r, c, _ in screen.cursor_seqs if 1 <= r <= 23
        ]
        if editor_cursor_seqs:
            last_editor_pos = editor_cursor_seqs[-1]
            if last_editor_pos != (1, 1):
                print(
                    f"[-] BUG CONFIRMED: Editor cursor placed at "
                    f"{last_editor_pos} instead of (1, 1)!"
                )
                bugs_detected.append(
                    f"CURSOR_DESYNC_ROW_{last_editor_pos[0]}_"
                    f"COL_{last_editor_pos[1]}"
                )
            else:
                print("[+] Editor cursor correctly restored to (1, 1).")

        # Now type characters into editor
        print("[*] Typing 'XYZABC' into editor...")
        screen.cursor_seqs.clear()
        os.write(master, b"XYZABC")
        type_out = read_until(master, b"XYZABC", timeout=8.0)
        time.sleep(0.3)
        type_out += drain_all(master, timeout=0.3)
        screen.feed(type_out.decode("latin1", errors="replace"))

        print(">>> [SCREEN GRAB: Screen after typing 'XYZABC']")
        print(screen.render())

        # Verify where 'XYZABC' landed
        found_typed_row = None
        for r_idx, row in enumerate(screen.buffer):
            if "XYZABC" in "".join(row):
                found_typed_row = r_idx
                break

        if found_typed_row is None:
            print("[-] BUG CONFIRMED: Typed text 'XYZABC' did not appear in "
                  "editor viewport!")
            bugs_detected.append("TYPING_FAILED_INVISIBLE")
        elif found_typed_row == 0:
            print(f"[+] Typed text appeared at row 0 (Line 1).")
        else:
            print(f"[-] BUG CONFIRMED: Typed text appeared at unexpected row "
                  f"{found_typed_row} instead of row 0!")
            bugs_detected.append(f"TYPING_DISPLACED_ROW_{found_typed_row}")

        # Summary report
        print("\n" + "=" * 76)
        print("  TEST SUMMARY: Large File Ctrl+P & WORDCNT Scenario")
        print("=" * 76)
        if bugs_detected:
            print(f"[-] Total bugs reproduced: {len(bugs_detected)}")
            for b in bugs_detected:
                print(f"    - {b}")
            print("\n[-] TEST RESULT: BUGS REPRODUCED SUCCESSFULLY")
            return 1
        else:
            print("[+] All checks passed cleanly. No bugs detected.")
            print("\n[+] TEST RESULT: PASS")
            return 0

    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2.0)
        except Exception:
            proc.kill()
        if os.path.isfile(ephemeral_img):
            try:
                os.remove(ephemeral_img)
            except OSError:
                pass
        if os.path.isfile(tmp_txt):
            try:
                os.remove(tmp_txt)
            except OSError:
                pass
        if os.path.isfile(cfg_tmp):
            try:
                os.remove(cfg_tmp)
            except OSError:
                pass


if __name__ == "__main__":
    use_sec_arg = "--sec" in sys.argv
    sys.exit(main(use_sec=use_sec_arg))
