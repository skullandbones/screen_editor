#!/usr/bin/env python3
"""
Automated Test for Bug 2.19:
Help Screen Top-Aligned at Row 1 Without Symmetrical Margins.

Verifies:
  1. Help screen calculates dynamic vertical margins:
     Top padding rows = ((HELP_ROWS - 1) - HELP_LINES) / 2
     Bottom padding rows = (HELP_ROWS - 1) - HELP_TOP_PAD_COUNT - HELP_LINES
  2. On 80x24 geometry:
     - Top margin padding: 0 rows (Rule 1 starts at Row 1).
     - Body lines have column 0 '~' with 0 extra spaces.
     - Bottom margin padding: exactly 1 row of '~' at Row 23.
     - Status bar: at Row 24.
  3. On 120x40 geometry:
     - Top margin padding: exactly 8 rows of '~' before first rule.
     - Title block starts at Row 9.
     - Body lines have column 0 '~' followed by 20 horizontal centering spaces.
     - Bottom margin padding: exactly 9 rows of '~' between prompt & status bar.
     - Status bar: at Row 40.
  4. Any key cleanly dismisses Help and returns to editor mode.
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
    help_bin = os.path.join(repo_root, "plugins", "HELP.OVL")
    cpmcp_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp"
    )
    cpmrm_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm"
    )

    return (
        repo_root, emu_bin, rom_file, img_file, se_bin, help_bin,
        cpmcp_bin, cpmrm_bin
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
    repo_root, cpmcp_bin, cpmrm_bin, img_file, se_bin, help_bin
):
    # Remove and copy SE.COM
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
    # Remove and copy HELP.OVL
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:HELP.OVL"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, help_bin, "0:HELP.OVL"],
        check=True
    )


def test_help_screen_centering(use_sec=False):
    print("[*] Starting Bug 2.19 Help Screen Centering Test...")
    (
        repo_root, emu_bin, rom_file, img_file, se_bin, help_bin,
        cpmcp_bin, cpmrm_bin
    ) = find_paths()

    setup_disk_files(
        repo_root, cpmcp_bin, cpmrm_bin, img_file, se_bin, help_bin
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

        # Launch SE.COM to splash screen
        os.write(master, cmd_name + b"\r")
        ok, out = read_until(master, b"SE - Screen Editor", timeout=45.0)
        assert ok, f"Splash screen not displayed: {out}"
        print("[+] Splash screen loaded.")
        drain_all(master)

        # ---------------------------------------------------------------------
        # Case 1: 80x24 Geometry Test
        # ---------------------------------------------------------------------
        print("\n[*] Case 1: Testing Help Screen in 80x24 mode...")
        time.sleep(0.3)
        os.write(master, b"2")  # Select 80x24
        ok, out = read_until(master, b"SE - Screen Editor", timeout=5.0)
        assert ok, f"Failed to select 80x24 mode: {out}"
        time.sleep(0.2)

        # Enter editor mode ('e')
        os.write(master, b"e")
        ok, out = read_until(master, b"^K: Editor keys", timeout=8.0)
        assert ok, f"Failed to enter editor: {out}"
        print("[+] Entered editor mode (80x24).")
        drain_all(master)

        # Press Ctrl+K to enter Help screen
        time.sleep(0.3)
        os.write(master, b"\x0b")  # Ctrl+K
        ok, out = read_until(
            master, b"Press any key to continue", timeout=8.0
        )
        assert ok, f"Help screen not loaded in 80x24: {out}"
        ok, out_more = read_until(master, b"\x1b[0m", timeout=3.0)
        out += out_more
        drain_all(master)

        # In 80x24:
        # Top padding = 0 rows
        # Row 1 is first rule
        expected_rule_80 = b"~" + (b"=" * 79)
        assert expected_rule_80 in out, (
            f"80x24 Help missing full-width rule: {out}"
        )
        expected_title_80 = (
            b"~" + (b" " * 31) + b"EDITOR MODE KEYS\r\n"
        )
        assert expected_title_80 in out, (
            f"80x24 Help missing centered title: {out}"
        )
        # Body Line 1 has '~' with 0 extra padding
        expected_body1_80 = b"~  FILE & SYSTEM:\r\n"
        assert expected_body1_80 in out, (
            f"80x24 Help missing body line 1: {out}"
        )
        # Symmetrical bottom margin: 1 row of '~' before status bar
        expected_bottom_80 = (
            b"~" + (b" " * 26) + b"Press any key to continue\r\n"
            + b"~\r\n"
        )
        assert expected_bottom_80 in out, (
            f"80x24 Help missing bottom margin padding tilde: {out}"
        )
        assert b"\x1b[24;1H" in out, "80x24 Help missing status bar on row 24"
        print("[+] 80x24 Help screen vertical & horizontal layout verified.")

        # Dismiss Help screen via space
        time.sleep(0.3)
        os.write(master, b" ")
        ok, out = read_until(master, b"^K: Editor keys", timeout=5.0)
        assert ok, f"Failed to return to editor from Help: {out}"
        print("[+] Returned cleanly to editor mode.")
        drain_all(master)

        # Return to splash screen via Ctrl+W
        time.sleep(0.3)
        os.write(master, b"\x17")  # Ctrl+W
        ok, out = read_until(master, b"SE - Screen Editor", timeout=8.0)
        assert ok, f"Failed to return to splash screen: {out}"
        print("[+] Returned to splash screen.")
        drain_all(master)

        # ---------------------------------------------------------------------
        # Case 2: 120x40 Geometry Test
        # ---------------------------------------------------------------------
        print("\n[*] Case 2: Testing Help Screen in 120x40 mode...")
        time.sleep(0.3)
        os.write(master, b"1")  # Select 120x40
        ok, out = read_until(master, b"SE - Screen Editor", timeout=5.0)
        assert ok, f"Failed to select 120x40 mode: {out}"
        time.sleep(0.2)

        # Enter editor mode ('e')
        os.write(master, b"e")
        ok, out = read_until(master, b"^K: Editor keys", timeout=8.0)
        assert ok, f"Failed to enter editor in 120x40: {out}"
        print("[+] Entered editor mode (120x40).")
        drain_all(master)

        # Press Ctrl+K to enter Help screen
        time.sleep(0.3)
        os.write(master, b"\x0b")  # Ctrl+K
        ok, out = read_until(
            master, b"Press any key to continue", timeout=8.0
        )
        assert ok, f"Help screen not loaded in 120x40: {out}"
        ok, out_more = read_until(master, b"\x1b[0m", timeout=3.0)
        out += out_more
        drain_all(master)

        # In 120x40:
        # Top padding = exactly 8 rows of '~' before first rule
        expected_top_pad_120 = b"\x1b[2J\x1b[H" + (b"~\r\n" * 8)
        assert expected_top_pad_120 in out, (
            f"120x40 Help missing 8 top margin tilde rows: {out[:200]}"
        )
        print("[+] Verified 8 top margin tilde rows precede header in 120x40.")

        # Row 9 is first rule (119 '=')
        expected_rule_120 = b"~" + (b"=" * 119)
        assert expected_rule_120 in out, (
            f"120x40 Help missing full-width rule: {out}"
        )
        print("[+] Verified full-width '=' rule (120 cols).")

        # Row 10 is centered title
        expected_title_120 = (
            b"~" + (b" " * 51) + b"EDITOR MODE KEYS\r\n"
        )
        assert expected_title_120 in out, (
            f"120x40 Help missing centered title: {out}"
        )
        print("[+] Verified centered title in 120 cols.")

        # Rows 12..28: Body lines horizontally centered with 20 spaces after '~'
        expected_body1_120 = b"~" + (b" " * 20) + b"  FILE & SYSTEM:\r\n"
        assert expected_body1_120 in out, (
            f"120x40 Help missing centered body line 1: {out}"
        )
        expected_body2_120 = (
            b"~" + (b" " * 20)
            + b"    Ctrl+O           Open file screen        "
            + b"Ctrl+S          Save file screen\r\n"
        )
        assert expected_body2_120 in out, (
            f"120x40 Help missing centered body line 2: {out}"
        )
        print("[+] Verified body table horizontally centered (+20 spaces).")

        # Symmetrical bottom margin: exactly 9 rows of '~' before status bar
        expected_prompt_120 = (
            b"~" + (b" " * 46) + b"Press any key to continue\r\n"
        )
        assert expected_prompt_120 in out, (
            f"120x40 Help missing centered return prompt: {out}"
        )
        expected_bottom_pad_120 = expected_prompt_120 + (b"~\r\n" * 9)
        assert expected_bottom_pad_120 in out, (
            f"120x40 Help missing 9 bottom margin tildes: {out}"
        )
        print("[+] Verified 9 bottom margin tildes follow footer in 120x40.")

        assert b"\x1b[40;1H" in out, "120x40 Help missing status bar on row 40"
        print("[+] Verified persistent status bar on Row 40.")

        # Dismiss Help screen via space
        time.sleep(0.3)
        os.write(master, b" ")
        ok, out = read_until(master, b"^K: Editor keys", timeout=5.0)
        assert ok, f"Failed to return to editor from Help: {out}"
        print("[+] Returned cleanly to editor mode.")
        drain_all(master)

        # ---------------------------------------------------------------------
        # Case 3: Exit to CP/M
        # ---------------------------------------------------------------------
        print("\n[*] Case 3: Exiting to CP/M prompt...")
        time.sleep(0.3)
        os.write(master, b"\x11")  # Ctrl+Q
        ok, out = read_until(master, b"C>", timeout=8.0)
        assert ok, f"Failed to exit cleanly to CP/M: {out}"
        print("[+] Returned to CP/M prompt cleanly.")

        print("\n=======================================================")
        print("  BUG 2.19 VERIFICATION PASSED (100%)!")
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
    use_sec_arg = "--sec" in sys.argv
    sys.exit(test_help_screen_centering(use_sec=use_sec_arg))
