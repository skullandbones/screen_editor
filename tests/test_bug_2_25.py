#!/usr/bin/env python3
"""
Automated Test for Bug 2.25:
Missing Description Line & Asymmetric Spacing in Find Modal Pop-up.

Verifies:
  1. Ctrl+F opens Find modal pop-up.
  2. Row 4 displays centered search pattern description line:
     "|       Search Pattern: [Case Sensitive  ]       |" (50 chars).
  3. Row 5 displays centered query prompt:
     "|      Find: [" ... "]      |" (6 spaces left, 6 spaces right).
  4. Row 6 displays centered query options:
     "| [Enter]=Find   [Tab]=Toggle Case   [ESC]=Cancel |" (50 chars).
  5. Tab toggles case mode to:
     "|       Search Pattern: [Case Insensitive]       |" (50 chars).
  6. ESC cancels modal and returns cleanly to editor.
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
    cfg_tmp = "/tmp/SE.CFG"
    with open(cfg_tmp, "w") as f:
        f.write("SCREEN=120x40\r\nRAMDRIVE=ON\r\n")

    if os.path.isfile(cpmrm_bin):
        for fname in ["0:SE.CFG", "0:se.cfg", "0:SE.COM", "0:se.com"]:
            subprocess.run(
                [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, fname],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )

    two_txt = os.path.join(repo_root, "2.TXT")
    if os.path.isfile(cpmcp_bin):
        if os.path.isfile(two_txt):
            subprocess.run(
                [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, two_txt, "0:2.TXT"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
        subprocess.run(
            [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, cfg_tmp, "0:SE.CFG"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        if os.path.isfile(se_bin):
            subprocess.run(
                [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, "0:SE.COM"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
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


def run_test():
    paths = find_paths()
    repo_root, emu_bin, rom_file, img_file, se_bin, cpmcp, cpmrm = paths

    setup_disk_files(img_file, se_bin, cpmcp, cpmrm, repo_root)

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

        print("[*] Launching 'se 2.TXT'...", flush=True)
        time.sleep(0.3)
        os.write(master, b"se 2.TXT\r")
        out = read_until(master, b"Line    1/2", timeout=35.0)
        if b"Line    1/2" not in out:
            print(f"[-] Failed to open 2.TXT: {out[-200:]}")
            return False
        drain_all(master)

        # Open Find modal pop-up via Ctrl+F
        print("[*] Opening Find modal pop-up with Ctrl+F...", flush=True)
        time.sleep(0.3)
        os.write(master, b"\x06")  # Ctrl+F
        out_f = read_until(master, b"[ESC]=Cancel", timeout=6.0)
        out_f += drain_all(master)

        expected_desc_sens = (
            b"|       Search Pattern: [Case Sensitive  ]       |"
        )
        if expected_desc_sens not in out_f:
            print(f"[-] Search Pattern description missing: {out_f}")
            return False
        print(f"[+] Row 4 verified: {repr(expected_desc_sens)}")

        expected_prompt_pre = b"|      Find: ["
        expected_prompt_post = b"]      |"
        if (expected_prompt_pre not in out_f or
                expected_prompt_post not in out_f):
            print(f"[-] Symmetrical Find prompt line missing: {out_f}")
            return False
        print(f"[+] Row 5 verified: {repr(expected_prompt_pre)} ... "
              f"{repr(expected_prompt_post)}")

        expected_keys = (
            b"| [Enter]=Find   [Tab]=Toggle Case   [ESC]=Cancel |"
        )
        if expected_keys not in out_f:
            print(f"[-] Symmetrical keys line missing: {out_f}")
            return False
        print(f"[+] Row 6 verified: {repr(expected_keys)}")

        # Toggle case sensitivity with Tab
        print("[*] Toggling case sensitivity with Tab...", flush=True)
        time.sleep(0.2)
        os.write(master, b"\t")
        out_tab = read_until(master, b"[ESC]=Cancel", timeout=6.0)
        out_tab += drain_all(master)

        expected_desc_insens = (
            b"|       Search Pattern: [Case Insensitive]       |"
        )
        if expected_desc_insens not in out_tab:
            print(f"[-] Search Pattern (Insensitive) missing: {out_tab}")
            return False
        print("[+] Row 4 toggled to Case Insensitive: "
              f"{repr(expected_desc_insens)}")

        # Cancel Find modal via ESC
        print("[*] Cancelling Find modal via ESC...", flush=True)
        time.sleep(0.2)
        os.write(master, b"\x1b")
        out_ed = read_until(master, b"^K: Editor keys", timeout=6.0)
        if b"^K: Editor keys" not in out_ed:
            print(f"[-] Return to editor after ESC failed: {out_ed}")
            return False
        drain_all(master)

        # Clean exit to CP/M
        time.sleep(0.2)
        os.write(master, b"\x11")  # Ctrl+Q
        out_cpm = read_until(master, b"C>", timeout=6.0)
        if b"C>" not in out_cpm:
            print(f"[-] Clean exit to CP/M failed: {out_cpm}")
            return False

        print("[+] Bug 2.25 verification PASSED: Find modal pop-up layout and "
              "centering conform to specifications.")
        return True
    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            proc.kill()
        try:
            os.close(master)
        except OSError:
            pass


if __name__ == "__main__":
    success = run_test()
    sys.exit(0 if success else 1)
