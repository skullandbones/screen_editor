#!/usr/bin/env python3
"""
Automated Test for Bug 2.28:
Save File UI Format Option Uses Parenthesized Colon Hotkey.

Verifies:
  1. Open editor with 'se 2.TXT'.
  2. Press Ctrl+S to enter Save File UI.
  3. Verify format line contains canonical bracket notation:
     "Format: [CP/M]   [^F]=Toggle Format"
  4. Verify parenthesized colon syntax "(^F: toggle format)" is absent.
  5. Press Ctrl+F to toggle format to Linux and verify:
     "Format: [Linux]   [^F]=Toggle Format"
  6. Cancel via ESC and exit cleanly to CP/M.
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


def setup_disk_files(
    img_file,
    se_bin,
    cpmcp_bin,
    cpmrm_bin,
    repo_root,
    use_sec=False
):
    if os.path.isfile(cpmrm_bin):
        for fname in ["0:SE.COM", "0:se.com"]:
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
        if os.path.isfile(se_bin):
            subprocess.run(
                target_cpm = "0:SEC.COM" if use_sec else "0:SE.COM"
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, target_cpm],
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


def run_test(use_sec=False):
    paths = find_paths(use_sec=use_sec)
    repo_root, emu_bin, rom_file, img_file, se_bin, cpmcp, cpmrm = paths
    target_name = "SEC.COM" if use_sec else "SE.COM"
    cmd_name = b"sec" if use_sec else b"se"
    target_name = "SEC.COM" if use_sec else "SE.COM"
    cmd_name = b"sec" if use_sec else b"se"

    setup_disk_files(img_file, se_bin, cpmcp, cpmrm, repo_root, use_sec=use_sec)

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
        os.write(master, cmd_name + b" 2.TXT\r")
        out = read_until(master, b"Line    1/2", timeout=35.0)
        if b"Line    1/2" not in out:
            print(f"[-] Failed to open 2.TXT: {out[-200:]}")
            return False
        drain_all(master)

        # Enter Save File screen via Ctrl+S
        print("[*] Entering Save File screen with Ctrl+S...", flush=True)
        time.sleep(0.3)
        os.write(master, b"\x13")  # Ctrl+S
        out_save = read_until(master, b"Enter filename to save:", timeout=6.0)
        out_save += drain_all(master)

        expected_init = b"Format: [Linux]   [^F]=Toggle Format"
        if expected_init not in out_save:
            print(f"[-] Initial format row mismatch: {out_save}")
            return False
        print(f"[+] Verified initial format row: {repr(expected_init)}")

        # Verify parenthesized colon syntax is absent
        if b"(^F: toggle format)" in out_save or b": toggle" in out_save:
            print("[-] Prohibited parenthesized colon syntax found: "
                  f"{out_save}")
            return False
        print("[+] Verified parenthesized colon syntax is absent.")

        # Toggle format via Ctrl+F
        print("[*] Toggling format with Ctrl+F...", flush=True)
        time.sleep(0.2)
        os.write(master, b"\x06")  # Ctrl+F
        out_cpm = read_until(master, b"Format: [CP/M]", timeout=6.0)
        out_cpm += drain_all(master)

        expected_toggled = b"Format: [CP/M]   [^F]=Toggle Format"
        if expected_toggled not in out_cpm:
            print(f"[-] Toggled format row mismatch: {out_cpm}")
            return False
        print(f"[+] Verified toggled format row: {repr(expected_toggled)}")

        # Cancel Save File screen via ESC
        print("[*] Cancelling Save File screen via ESC...", flush=True)
        time.sleep(0.2)
        os.write(master, b"\x1b")
        out_ed = read_until(master, b"^K: Editor keys", timeout=6.0)
        if b"^K: Editor keys" not in out_ed:
            print(f"[-] Return to editor after ESC failed: {out_ed}")
            return False
        drain_all(master)

        # Exit to CP/M via Ctrl+Q -> 'n'
        time.sleep(0.2)
        os.write(master, b"\x11")  # Ctrl+Q
        out_cpm = read_until(master, b"C>", timeout=6.0)
        if b"C>" not in out_cpm:
            print(f"[-] Clean exit to CP/M failed: {out_cpm}")
            return False

        print("[+] Bug 2.28 verification PASSED: Save File UI format row "
              "uses canonical bracket notation [^F]=Toggle Format.")
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
    use_sec_arg = "--sec" in sys.argv
    success = run_test(use_sec=use_sec_arg)
    sys.exit(0 if success else 1)
