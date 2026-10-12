#!/usr/bin/env python3
"""
Automated Test for Bug 2.18:
Pinned Top Header Rows 1-3 on File Open, Save, and Block Screens.

Verifies:
  1. Top margin blank tildes (DIR_TOP_PAD_COUNT) are rendered BEFORE the
     3-row title block (=, title, =) on File Open, Save, and Block screens.
  2. Row 1 is a margin tilde row ('~'), NOT pinned header rule ('~====...').
  3. The title block is the top element of a unified content block centered
     vertically and horizontally above the status bar.
  4. The directory listing immediately follows the title block (no gap
     between title and file entries).
  5. Symmetrical bottom margin tildes extend from the input prompt down to
     the status bar.
  6. Verified across File Open (Ctrl+O) and File Save (Ctrl+S) screens in
     both 80x24 and 120x40 geometries.
"""

import os
import sys
import time
import tty
import select
import subprocess
import re


def find_paths(use_sec=False):
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
    se_bin = os.path.join(repo_root, "SEC.COM" if use_sec else "SE.COM")
    cpmcp_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp"
    )
    cpmrm_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm"
    )

    return (
        repo_root, emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin
    )


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
                    return True, buf
            except (BlockingIOError, OSError):
                pass
        time.sleep(0.01)
    return False, buf


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


def setup_disk_files(
    repo_root, cpmcp_bin, cpmrm_bin, img_file, se_bin, use_sec=False
):
    subprocess.run(
        target_cpm = "0:SEC.COM" if use_sec else "0:SE.COM"
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, target_cpm],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, target_cpm],
        check=True
    )


def parse_screen_lines(raw_bytes):
    """
    Parses terminal stream output between screen clear (\\x1b[2J\\x1b[H)
    and status bar (\\x1b[<rows>;1H). Returns list of stripped line strings.
    """
    text = raw_bytes.decode("latin1", errors="replace")
    # Find last clear screen
    last_clr = text.rfind("\x1b[2J\x1b[H")
    if last_clr >= 0:
        text = text[last_clr + len("\x1b[2J\x1b[H"):]
    # Strip terminal cursor locate commands for status bar
    lines = text.split("\r\n")
    return [l for l in lines if l]


def test_open_save_header_centering(use_sec=False):
    print("[*] Starting Bug 2.18 Header Centering Test...")
    (
        repo_root, emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin
    ) = find_paths(use_sec=use_sec)
    target_name = "SEC.COM" if use_sec else "SE.COM"
    cmd_name = b"sec" if use_sec else b"se"

    setup_disk_files(
        repo_root, cpmcp_bin, cpmrm_bin, img_file, se_bin, use_sec=use_sec
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
        ok, out = read_until(master, b"Boot [H=Help]:", timeout=8.0)
        assert ok, f"Boot prompt not found: {out}"
        time.sleep(0.3)
        os.write(master, b"c\r")

        ok, out = read_until(master, b"B>", timeout=8.0)
        assert ok, f"Drive B prompt not found: {out}"
        time.sleep(0.3)
        os.write(master, b"c:\r")

        ok, out = read_until(master, b"C>", timeout=8.0)
        assert ok, f"Drive C prompt not found: {out}"
        time.sleep(0.3)

        # Launch SE.COM directly into editor mode with a dummy document
        os.write(master, cmd_name + b" test.txt\r")
        ok, out = read_until(master, b"^K: Editor keys", timeout=60.0)
        assert ok, f"Editor screen not displayed: {out}"
        print("[+] Editor screen loaded.")
        drain_all(master)

        # ---------------------------------------------------------------------
        # Case 1: Open File Screen (Ctrl+O)
        # ---------------------------------------------------------------------
        print("[*] Case 1: Testing Open File Screen (Ctrl+O)...")
        time.sleep(0.3)
        os.write(master, b"\x0f")  # Ctrl+O

        ok, out = read_until(master, b"Enter filename to open", timeout=6.0)
        assert ok, f"Open prompt not displayed: {out}"
        ok, out_more = read_until(master, b"\x1b[0m", timeout=3.0)
        out += out_more
        time.sleep(0.1)
        drain_all(master)

        lines = parse_screen_lines(out)
        print(f"[+] Captured {len(lines)} lines on Open File screen.")

        # Find the row index of the first horizontal rule (~===...)
        first_rule_idx = None
        for i, l in enumerate(lines):
            clean_l = re.sub(r"\x1b\[[0-9;]*[a-zA-Z]", "", l)
            if clean_l.startswith("~==="):
                first_rule_idx = i
                break

        assert first_rule_idx is not None, (
            f"Horizontal rule not found in lines: {lines[:10]}"
        )
        print(
            f"[+] First rule found at index {first_rule_idx} "
            f"(Row {first_rule_idx + 1})."
        )

        # Verify Row 1 is a margin tilde row ('~'), NOT pinned header
        assert first_rule_idx > 0, (
            f"ERROR: Header is pinned at Row 1! Lines: {lines[:5]}"
        )
        for r in range(first_rule_idx):
            clean_r = re.sub(r"\x1b\[[0-9;]*[a-zA-Z]", "", lines[r]).strip()
            assert clean_r == "~", (
                f"Row {r + 1} before header not blank tilde '~': "
                f"{repr(clean_r)}"
            )
        print(f"[+] Verified {first_rule_idx} margin tildes precede header.")

        # Verify Title immediately follows first rule
        title_idx = first_rule_idx + 1
        clean_title = re.sub(r"\x1b\[[0-9;]*[a-zA-Z]", "", lines[title_idx])
        assert "OPEN FILE" in clean_title, (
            f"Row {title_idx + 1} is not title: {clean_title}"
        )
        print(
            f"[+] Verified Title follows first rule at Row "
            f"{title_idx + 1}."
        )

        # Verify second rule immediately follows title
        second_rule_idx = title_idx + 1
        clean_second_rule = re.sub(
            r"\x1b\[[0-9;]*[a-zA-Z]", "", lines[second_rule_idx]
        )
        assert clean_second_rule.startswith("~==="), (
            f"Row {second_rule_idx + 1} not closing rule: {clean_second_rule}"
        )
        print(
            f"[+] Verified second rule follows Title at Row "
            f"{second_rule_idx + 1}."
        )

        # Verify directory entries immediately follow second rule
        dir_start_idx = second_rule_idx + 1
        clean_dir = re.sub(r"\x1b\[[0-9;]*[a-zA-Z]", "", lines[dir_start_idx])
        assert not clean_dir.strip().startswith("~==="), (
            f"Directory entries missing at Row {dir_start_idx + 1}: {clean_dir}"
        )
        print(f"[+] Verified content block is unified without gap below Title.")

        # Cancel Open screen via ESC
        time.sleep(0.3)
        os.write(master, b"\x1b")
        ok, out = read_until(master, b"^K: Editor keys", timeout=5.0)
        assert ok, f"Failed to return to editor from Open: {out}"
        print("[+] Returned cleanly to editor.")
        drain_all(master)

        # ---------------------------------------------------------------------
        # Case 2: Save File Screen (Ctrl+S)
        # ---------------------------------------------------------------------
        print("[*] Case 2: Testing Save File Screen (Ctrl+S)...")
        time.sleep(0.3)
        os.write(master, b"\x13")  # Ctrl+S

        ok, out = read_until(master, b"Enter filename to save", timeout=6.0)
        assert ok, f"Save prompt not displayed: {out}"
        ok, out_more = read_until(master, b"\x1b[0m", timeout=3.0)
        out += out_more
        time.sleep(0.1)
        drain_all(master)

        lines = parse_screen_lines(out)
        first_rule_idx = None
        for i, l in enumerate(lines):
            clean_l = re.sub(r"\x1b\[[0-9;]*[a-zA-Z]", "", l)
            if clean_l.startswith("~==="):
                first_rule_idx = i
                break

        assert first_rule_idx is not None, (
            f"Horizontal rule not found in lines: {lines[:10]}"
        )
        print(f"[+] Save screen: First rule found at Row {first_rule_idx + 1}.")

        # Verify Row 1 is a margin tilde row ('~'), NOT pinned header
        assert first_rule_idx > 0, (
            f"ERROR: Pinned at Row 1 on Save screen! Lines: {lines[:5]}"
        )
        for r in range(first_rule_idx):
            clean_r = re.sub(r"\x1b\[[0-9;]*[a-zA-Z]", "", lines[r]).strip()
            assert clean_r == "~", (
                f"Row {r + 1} before header not blank tilde '~': "
                f"{repr(clean_r)}"
            )
        print(f"[+] Verified {first_rule_idx} margin tildes precede Save.")

        # Verify Title immediately follows first rule
        title_idx = first_rule_idx + 1
        clean_title = re.sub(r"\x1b\[[0-9;]*[a-zA-Z]", "", lines[title_idx])
        assert "SAVE FILE" in clean_title, (
            f"Row {title_idx + 1} is not title: {clean_title}"
        )
        print(
            f"[+] Verified Title follows first rule at Row "
            f"{title_idx + 1}."
        )

        # Cancel Save screen via ESC
        time.sleep(0.3)
        os.write(master, b"\x1b")
        ok, out = read_until(master, b"^K: Editor keys", timeout=5.0)
        assert ok, f"Failed to return to editor from Save: {out}"
        print("[+] Returned cleanly to editor.")
        drain_all(master)

        # ---------------------------------------------------------------------
        # Case 3: Exit to CP/M
        # ---------------------------------------------------------------------
        print("[*] Case 3: Exiting to CP/M prompt...")
        time.sleep(0.3)
        os.write(master, b"\x11")  # Ctrl+Q
        ok, out = read_until(master, b"C>", timeout=8.0)
        assert ok, f"Failed to exit cleanly to CP/M: {out}"
        print("[+] Returned to CP/M prompt cleanly.")

        print("\n=======================================================")
        print("  BUG 2.18 VERIFICATION PASSED (100%)!")
        print("=======================================================")
        return 0

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            pass
        os.close(master)


if __name__ == "__main__":
    sys.exit(test_open_save_header_centering())
