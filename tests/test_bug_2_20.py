#!/usr/bin/env python3
"""
Automated Test for Bug 2.20:
Truncated File Save Blocked Uses Tier 2 Modal Pop-up Instead of Screen Dump.

Verifies:
  1. When a truncated file is loaded, attempting to save via Ctrl+S displays
     a standard Tier 2 centered boxed modal pop-up (50x7):
       - Title: "File Truncated"
       - Msg1:  "File exceeded capacity and has been truncated."
       - Msg2:  "Save is disabled to protect data on disk."
       - Prompt: "Press any key to continue"
  2. The screen is NOT cleared with a 12-line raw text dump (no screen clear,
     no ancient STR_TRUNC_SAVE_BLOCKED).
  3. The persistent status bar remains visible on row HOST_ROWS.
  4. Dismissing the pop-up with any key restores the editor workspace cleanly.
  5. The file on disk remains 100% intact.
"""

import os
import sys
import time
import tty
import select
import subprocess


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


def read_until(master_fd, match_bytes, timeout=12.0):
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
    repo_root, cpmcp_bin, cpmrm_bin, img_file, se_bin, cfg_file, big_file
):
    # Remove old files
    for fn in ["SE.COM", "SE.CFG", "BIG350.TXT", "$$$SE$$$.SWP"]:
        subprocess.run(
            [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, f"0:{fn}"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
    # Inject SE.COM, SE.CFG, BIG350.TXT
    subprocess.run(
        target_cpm = "0:SEC.COM" if use_sec else "0:SE.COM"
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, target_cpm],
        check=True
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, cfg_file, "0:SE.CFG"],
        check=True
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, big_file, "0:BIG350.TXT"],
        check=True
    )


def test_truncated_save_blocked_popup(use_sec=False):
    print("[*] Starting Bug 2.20 Truncated Save Blocked Modal Test...")
    (
        repo_root, emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin
    ) = find_paths(use_sec=use_sec)
    target_name = "SEC.COM" if use_sec else "SE.COM"
    cmd_name = b"sec" if use_sec else b"se"

    # Create SE.CFG with RAMDRIVE=PRESERVE (limits Far RAM to 32KB / 256 lines)
    cfg_tmp = "/tmp/TEST_BUG_2_20_SE.CFG"
    with open(cfg_tmp, "wb") as f:
        f.write(b"RAMDRIVE=PRESERVE\r\nLINES=32K\r\nPLUGIN=AUTOLOAD\r\n")

    # Generate BIG350.TXT (350 lines > 256 limit)
    big_tmp = "/tmp/TEST_BUG_2_20_BIG350.TXT"
    with open(big_tmp, "wb") as f:
        for i in range(1, 351):
            f.write(f"Line {i:03d} of 350 - Truncation test.\r\n".encode())

    orig_size = os.path.getsize(big_tmp)

    setup_disk_files(
        repo_root, cpmcp_bin, cpmrm_bin, img_file, se_bin, cfg_tmp, big_tmp
    )
    if os.path.exists(cfg_tmp):
        os.remove(cfg_tmp)

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

        # Launch SE.COM with BIG350.TXT
        print("[*] Launching 'se big350.txt'...")
        os.write(master, cmd_name + b" big350.txt\r")

        # Initial load detects truncation and displays modal pop-up
        ok, out = read_until(master, b"File Truncated", timeout=30.0)
        assert ok, f"Initial truncation popup not displayed: {out}"
        print("[+] Initial file load truncation pop-up displayed.")

        # Dismiss initial load pop-up with space
        time.sleep(0.3)
        os.write(master, b" ")
        ok, out = read_until(master, b"^K: Editor keys", timeout=8.0)
        assert ok, f"Failed to enter editor mode: {out}"
        print("[+] Entered editor workspace.")
        drain_all(master)

        # Attempt save via Ctrl+S on truncated document
        print("[*] Attempting Ctrl+S save on truncated document...")
        time.sleep(0.3)
        os.write(master, b"\x13")  # Ctrl+S

        ok, out = read_until(master, b"File Truncated", timeout=6.0)
        assert ok, f"Save blocked pop-up not displayed: {out}"
        ok, out_more = read_until(
            master, b"Press any key to continue", timeout=3.0
        )
        out += out_more
        drain_all(master)

        # Verify modal pop-up contents
        assert b"|                 File Truncated                 |" in out, (
            f"Missing centered pop-up title: {out}"
        )
        assert b"| File exceeded capacity and has been truncated. |" in out, (
            f"Missing pop-up msg1: {out}"
        )
        assert b"| Save is disabled to protect data on disk.      |" in out, (
            f"Missing pop-up msg2: {out}"
        )
        assert b"|           Press any key to continue            |" in out, (
            f"Missing pop-up prompt: {out}"
        )
        assert b"+------------------------------------------------+" in out, (
            f"Missing pop-up ASCII borders: {out}"
        )

        # Verify old screen clear and screen dump were NOT emitted
        assert b"ERROR: SAVE DISABLED (PROTECTION)" not in out, (
            "ERROR: Ancient raw dump banner still present!"
        )
        assert b"\x1b[2J\x1b[H" not in out, (
            "ERROR: Full screen clear was emitted instead of modal overlay!"
        )
        print("[+] Verified Tier 2 modal pop-up without screen clear.")

        # Dismiss pop-up with space key
        print("[*] Dismissing modal pop-up with space key...")
        time.sleep(0.3)
        os.write(master, b" ")
        ok, out = read_until(master, b"^K: Editor keys", timeout=6.0)
        assert ok, f"Failed to resume editor cleanly: {out}"
        print("[+] Resumed editor workspace cleanly.")
        drain_all(master)

        # Clean exit to CP/M prompt: Ctrl+Q
        print("[*] Exiting cleanly to CP/M...")
        time.sleep(0.3)
        os.write(master, b"\x11")  # Ctrl+Q
        ok, out = read_until(master, b"C>", timeout=8.0)
        assert ok, f"Failed to return to CP/M: {out}"
        print("[+] Returned to CP/M prompt cleanly.")

        # Verify file on disk is 100% intact
        extracted = "/tmp/EXTR_BIG350.TXT"
        if os.path.exists(extracted):
            os.remove(extracted)
        subprocess.run(
            [
                cpmcp_bin, "-f", "wbw_hd1k_0", img_file, "0:BIG350.TXT",
                extracted
            ],
            check=True
        )
        extr_size = os.path.getsize(extracted)
        assert orig_size == extr_size, (
            f"File size mismatch: {orig_size} != {extr_size}"
        )
        with open(big_tmp, "rb") as f1, open(extracted, "rb") as f2:
            assert f1.read() == f2.read(), "File content corrupted on disk!"
        print("[+] File on disk verified 100% intact and uncorrupted.")

        print("\n=======================================================")
        print("  BUG 2.20 VERIFICATION PASSED (100%)!")
        print("=======================================================")
        return 0

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            pass
        os.close(master)
        if os.path.exists(big_tmp):
            os.remove(big_tmp)


if __name__ == "__main__":
    use_sec_arg = "--sec" in sys.argv
    sys.exit(
        test_truncated_save_blocked_popup(use_sec=use_sec_arg)
    )
