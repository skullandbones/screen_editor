#!/usr/bin/env python3
"""
Automated Test for Bug 2.30:
Misalignment of Splash Screen "Active Screen" Status Bracket.

Verifies:
  1. Boot CP/M and launch 'se'.
  2. Capture the splash screen content.
  3. Verify "Active Screen : [" is present with a space before the colon.
  4. Verify "Active Screen: [" without a space before the colon is absent.
  5. Verify the opening bracket '[' on all four status lines:
     - "Active Screen : ["
     - "RAM Drive" line opening bracket
     - "Plugin System : ["
     - "Max Lines     : ["
     align at the exact same horizontal column.
  6. Exit cleanly to CP/M with 'q'.
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


def read_until(master_fd, target, timeout=8.0):
    buf = b""
    t0 = time.time()
    targets = target if isinstance(target, (list, tuple)) else [target]
    while time.time() - t0 < timeout:
        r, _, _ = select.select([master_fd], [], [], 0.05)
        if r:
            try:
                data = os.read(master_fd, 1024)
                if not data:
                    break
                buf += data
                for tgt in targets:
                    if tgt in buf:
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


def setup_disk_files(img_file, se_bin, cpmcp_bin, cpmrm_bin, repo_root):
    if os.path.isfile(cpmrm_bin):
        for fname in ["0:SE.COM", "0:se.com"]:
            subprocess.run(
                [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, fname],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, "0:SE.COM"],
        check=True,
    )


def boot_cpm(master):
    out = read_until(master, b"Boot [H=Help]:", timeout=8.0)
    if b"Boot [H=Help]:" not in out:
        return False, "Bootloader prompt missing"
    time.sleep(0.3)
    os.write(master, b"c\r")
    out = read_until(master, b"B>", timeout=8.0)
    if b"B>" not in out:
        return False, "Drive B> missing"
    time.sleep(0.3)
    os.write(master, b"c:\r")
    out = read_until(master, b"C>", timeout=8.0)
    if b"C>" not in out:
        return False, "Drive C> missing"
    drain_all(master)
    return True, "Booted to C>"


def strip_ansi(text):
    ansi_re = re.compile(r"\x1b\[[0-9;]*[a-zA-Z]|\x1b\([AB012]")
    return ansi_re.sub("", text)


def run_test():
    paths = find_paths()
    repo_root, emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = paths

    setup_disk_files(img_file, se_bin, cpmcp_bin, cpmrm_bin, repo_root)

    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )
    os.close(slave)

    try:
        ok, msg = boot_cpm(master)
        if not ok:
            print(f"[-] {msg}")
            return False

        print("[*] Launching 'se' to display splash screen...", flush=True)
        time.sleep(0.5)
        os.write(master, b"se\r")
        out = read_until(master, b"lines]", timeout=30.0)
        out += drain_all(master, 0.3)

        raw_str = out.decode("latin1", errors="replace")
        clean_text = strip_ansi(raw_str)

        # 1. Verify "Active Screen : [" is present
        assert "Active Screen : [" in clean_text, (
            f"'Active Screen : [' not found in splash output: {clean_text}"
        )
        print("[+] Verified 'Active Screen : [' label present.")

        # 2. Verify misaligned "Active Screen: [" is absent
        assert "Active Screen: [" not in clean_text, (
            f"Misaligned 'Active Screen: [' still present in output!"
        )
        print("[+] Verified misaligned 'Active Screen: [' is absent.")

        # 3. Locate each status line and measure column index of '['
        lines = [
            line.rstrip() for line in clean_text.splitlines() if line.strip()
        ]
        status_bracket_cols = {}
        for line in lines:
            if "Active Screen :" in line and "[" in line:
                status_bracket_cols["Active Screen"] = line.index("[")
            elif "RAM Drive" in line and "[" in line:
                status_bracket_cols["RAM Drive"] = line.index("[")
            elif "Plugin System :" in line and "[" in line:
                status_bracket_cols["Plugin System"] = line.index("[")
            elif "Max Lines" in line and "[" in line:
                status_bracket_cols["Max Lines"] = line.index("[")

        print(f"[*] Detected status row bracket columns: {status_bracket_cols}")
        assert "Active Screen" in status_bracket_cols, (
            "Active Screen status row not found"
        )
        assert "Plugin System" in status_bracket_cols, (
            "Plugin System status row not found"
        )
        assert "Max Lines" in status_bracket_cols, (
            "Max Lines status row not found"
        )

        expected_col = status_bracket_cols["Max Lines"]
        for label, col in status_bracket_cols.items():
            assert col == expected_col, (
                f"Bracket misalignment in '{label}': "
                f"col {col} != {expected_col}"
            )
            print(f"[+] '{label}' bracket aligned at column {col}.")

        # 4. Exit cleanly with 'q'
        print("[*] Exiting splash screen with 'q'...", flush=True)
        time.sleep(0.2)
        os.write(master, b"q")
        out_exit = read_until(master, b"C>", timeout=6.0)
        assert b"C>" in out_exit, "Failed to exit back to CP/M prompt"
        print("[+] Bug 2.30 verification PASSED: splash brackets aligned.")
        return True

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            pass
        os.close(master)


if __name__ == "__main__":
    success = run_test()
    sys.exit(0 if success else 1)
