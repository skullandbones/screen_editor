#!/usr/bin/env python3
"""
Automated Test for Bug 2.27:
Configuration Screen Footer Uses Prohibited Slash Delimiter.

Verifies:
  1. Press 'C' from splash screen to enter Configuration screen.
  2. Footer displays canonical command triggers without slash delimiters:
     "[1-5]=Toggle Option   [S]=Save Config   [ESC]=Exit"
  3. No prohibited '/' delimiter is in the footer options.
  4. Returns cleanly to splash screen via ESC.
  5. Exits cleanly to CP/M via 'q'.
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
        for fname in ["0:SE.CFG", "0:se.cfg", "0:SE.COM", "0:se.com"]:
            subprocess.run(
                [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, fname],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )

    if os.path.isfile(cpmcp_bin):
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

        print("[*] Launching 'se'...", flush=True)
        time.sleep(0.3)
        os.write(master, b"se\r")
        out = read_until(master, b"to configure", timeout=35.0)
        if b"to configure" not in out:
            print(f"[-] Splash screen failed to display: {out[-200:]}")
            return False
        drain_all(master)

        # Enter Configuration Screen with 'c'
        print("[*] Entering Configuration Screen with 'c'...", flush=True)
        time.sleep(0.3)
        os.write(master, b"c")
        out_cfg = read_until(master, b"[ESC]=Exit", timeout=8.0)
        out_cfg += drain_all(master)

        expected_footer = b"[1-5]=Toggle Option   [S]=Save Config   [ESC]=Exit"
        if expected_footer not in out_cfg:
            print(f"[-] Config footer missing or mismatch: {out_cfg}")
            return False
        print(f"[+] Verified config footer: {repr(expected_footer)}")

        # Ensure prohibited slash delimiter is not present in footer
        if b"[Q]/[ESC]" in out_cfg or b"return to splash screen" in out_cfg:
            print("[-] Prohibited slash delimiter or lowercase text found: "
                  f"{out_cfg}")
            return False
        print("[+] Verified no prohibited slash delimiters or lowercase text.")

        # Return to splash via ESC
        print("[*] Pressing ESC to return to splash screen...", flush=True)
        time.sleep(0.3)
        os.write(master, b"\x1b")
        out_sp = read_until(master, b"to configure", timeout=8.0)
        if b"to configure" not in out_sp:
            print(f"[-] Return to splash failed: {out_sp}")
            return False
        drain_all(master)

        # Exit to CP/M via 'q'
        time.sleep(0.2)
        os.write(master, b"q")
        out_cpm = read_until(master, b"C>", timeout=6.0)
        if b"C>" not in out_cpm:
            print(f"[-] Exit to CP/M failed: {out_cpm}")
            return False

        print("[+] Bug 2.27 verification PASSED: Configuration screen footer "
              "uses canonical [ESC]=Exit without slash delimiters.")
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
