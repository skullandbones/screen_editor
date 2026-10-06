#!/usr/bin/env python3
"""
Automated Test for Bug 2.34:
Progress Dialog Line Counter Leaks Debris Trailing Zero.

Verifies:
  1. Boot CP/M and copy a multi-hundred line file (e.g. 250 lines) to disk.
  2. Launch 'se LONG.TXT' and capture the progress modal output.
  3. Verify the initial progress line template has initial '0' aligned at col 30:
     "|                   Line     0                   |"
  4. Verify the line counter updates correctly:
     - Shows "Line   100" at 100 lines (NOT "Line   1000")
     - Shows "Line   200" at 200 lines (NOT "Line   2000")
     - Shows "Line   250" at completion
  5. Verify saving the file with Ctrl+S also updates line progress cleanly
     without trailing zero debris.
  6. Clean exit to CP/M.
"""

import os
import re
import select
import subprocess
import sys
import time
import tty


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
        else:
            time.sleep(0.01)
    return False, buf


def drain_all(master_fd, duration=0.2):
    buf = b""
    t0 = time.time()
    while time.time() - t0 < duration:
        r, _, _ = select.select([master_fd], [], [], 0.03)
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


def setup_disk_files(repo_root, cpmcp_bin, cpmrm_bin, img_file, se_bin):
    if os.path.isfile(cpmrm_bin):
        for fname in ["0:SE.COM", "0:se.com", "0:LONG.TXT", "0:long.txt"]:
            subprocess.run(
                [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, fname],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

    # Ensure fresh SE.COM is installed on drive C (user 0)
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, "0:SE.COM"],
        check=True,
    )

    # Create a 250-line test file on host and copy to drive C
    long_path = os.path.join(repo_root, "LONG.TXT")
    lines = [f"This is line {i:03d} of test file.\r\n" for i in range(1, 251)]
    with open(long_path, "w", encoding="ascii") as f:
        f.writelines(lines)
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, long_path, "0:LONG.TXT"],
        check=True,
    )


def cleanup_disk_files(repo_root, cpmrm_bin, img_file):
    long_path = os.path.join(repo_root, "LONG.TXT")
    if os.path.isfile(long_path):
        try:
            os.remove(long_path)
        except OSError:
            pass
    if os.path.isfile(cpmrm_bin):
        subprocess.run(
            [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:LONG.TXT"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def boot_cpm(master):
    ok, out = read_until(master, b"Boot [H=Help]:", timeout=8.0)
    if not ok:
        return False, "Bootloader prompt missing"
    time.sleep(0.3)
    os.write(master, b"c\r")
    ok, out = read_until(master, b"B>", timeout=8.0)
    if not ok:
        return False, "Drive B> missing"
    time.sleep(0.3)
    os.write(master, b"c:\r")
    ok, out = read_until(master, b"C>", timeout=8.0)
    if not ok:
        return False, "Drive C> missing"
    drain_all(master)
    return True, "Booted to C>"


def main():
    paths = find_paths()
    repo_root, emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = paths

    for p, name in [
        (emu_bin, "RC2014 emulator"),
        (rom_file, "ROM file"),
        (img_file, "Disk image"),
        (se_bin, "SE.COM binary"),
        (cpmcp_bin, "cpmcp binary"),
        (cpmrm_bin, "cpmrm binary"),
    ]:
        if not os.path.isfile(p):
            print(f"[-] Error: {name} not found at {p}")
            sys.exit(1)

    print("=" * 65)
    print("  Bug 2.34: Progress Dialog Line Counter Debris Zero Test")
    print("=" * 65)

    setup_disk_files(repo_root, cpmcp_bin, cpmrm_bin, img_file, se_bin)

    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )
    os.close(slave)

    try:
        ok, reason = boot_cpm(master)
        if not ok:
            print(f"[-] Failed to boot CP/M: {reason}")
            return 1

        # ---------------------------------------------------------------------
        # Subtest 1: Verify Initial Progress Template Alignment
        # ---------------------------------------------------------------------
        print("[*] Subtest 1: Testing initial progress template alignment...")
        os.write(master, b"se LONG.TXT\r")
        ok, load_out = read_until(
            master, b"Please wait for completion", timeout=30.0
        )
        if not ok:
            print(f"[-] Failed to open LONG.TXT in editor: {repr(load_out)}")
            return 1

        exp_init_line = (
            b"|                   Line     0                   |"
        )
        if exp_init_line not in load_out:
            print(
                f"[-] Expected template '{exp_init_line.decode()}' not found."
            )
            print(f"    Full Load output: {repr(load_out)}")
            return 1
        print(f"[+] Subtest 1 PASSED: Found '{exp_init_line.decode()}'.")

        # ---------------------------------------------------------------------
        # Subtest 2: Verify No Trailing Zero Debris During Load
        # ---------------------------------------------------------------------
        print("[*] Subtest 2: Verifying no trailing zero debris during load...")
        ok, rest = read_until(master, b"Line    1/250", timeout=30.0)
        load_out += rest
        if not ok:
            print("[-] Editor did not finish loading 250 lines.")
            return 1

        # Check for debris: "Line   1000" or "Line   2000" must NOT appear
        if b"Line   1000" in load_out:
            print("[-] DEFECT FOUND: 'Line   1000' debris zero detected!")
            return 1
        if b"Line   2000" in load_out:
            print("[-] DEFECT FOUND: 'Line   2000' debris zero detected!")
            return 1

        # Check that proper line counts were printed
        if b"Line   100" not in load_out:
            print("[-] Expected 'Line   100' progress update not found.")
            return 1
        if b"Line   200" not in load_out:
            print("[-] Expected 'Line   200' progress update not found.")
            return 1
        if b"Line   250" not in load_out:
            print("[-] Expected 'Line   250' final progress update not found.")
            return 1
        print("[+] Subtest 2 PASSED: 100, 200, 250 verified without debris.")

        # ---------------------------------------------------------------------
        # Subtest 3: Verify No Trailing Zero Debris During Save
        # ---------------------------------------------------------------------
        print("[*] Subtest 3: Verifying progress display during save...")
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"\x13")  # Ctrl+S
        ok, out = read_until(master, b"Enter filename to save:", timeout=6.0)
        if not ok:
            print("[-] Failed to open Save dialog with Ctrl+S.")
            return 1
        time.sleep(0.2)
        drain_all(master)

        os.write(master, b"\r")  # Accept pre-filled LONG.TXT
        ok_ow, _ = read_until(master, b"Overwrite?", timeout=6.0)
        if ok_ow:
            time.sleep(0.2)
            os.write(master, b"y")  # Confirm overwrite

        ok, save_out = read_until(master, b"Line    1/250", timeout=30.0)
        if not ok:
            print("[-] Save operation did not return to editor.")
            return 1

        if b"Line   1000" in save_out or b"Line   2000" in save_out:
            print("[-] DEFECT FOUND: Debris zero detected during file save!")
            return 1
        print("[+] Subtest 3 PASSED: Save completed cleanly without debris.")

        # Exit to CP/M
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"\x11")  # Ctrl+Q
        ok_sc, _ = read_until(master, b"Save changes?", timeout=3.0)
        if ok_sc:
            time.sleep(0.2)
            os.write(master, b"n")
        read_until(master, b"C>", timeout=6.0)

        print("\n" + "=" * 65)
        print("  [SUCCESS] All Progress Counter Debris Subtests PASSED!")
        print("=" * 65)
        return 0

    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2.0)
        except Exception:
            proc.kill()
        cleanup_disk_files(repo_root, cpmrm_bin, img_file)


if __name__ == "__main__":
    sys.exit(main())
