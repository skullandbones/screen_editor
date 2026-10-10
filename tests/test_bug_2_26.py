#!/usr/bin/env python3
"""
Automated Test for Bug 2.26:
Asymmetric Left-Aligned Messages in Truncated & Error Modal Pop-ups.

Verifies:
  1. Ctrl+F search for non-existent pattern (e.g. 'ZZZ') triggers
     "Pattern Not Found" modal pop-up.
  2. Modal Row 4 displays horizontally centered:
     "|               Pattern not found.               |" (50 chars).
  3. Dismisses cleanly via space / any key and returns to editor.
  4. Exits cleanly to CP/M.
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

        # Trigger Find: Ctrl+F
        print("[*] Opening Find modal with Ctrl+F...", flush=True)
        time.sleep(0.3)
        os.write(master, b"\x06")
        out_f = read_until(master, b"[ESC]=Cancel", timeout=6.0)
        if b"Find: [" not in out_f:
            print(f"[-] Find modal missing: {out_f}")
            return False
        time.sleep(0.2)
        drain_all(master)

        # Search for non-existent pattern 'ZZZ'
        print("[*] Searching for 'ZZZ' to trigger Pattern Not Found...",
              flush=True)
        os.write(master, b"ZZZ\r")
        out_nf = read_until(master, b"Pattern not found.", timeout=6.0)
        out_nf += drain_all(master)

        expected_msg = b"|               Pattern not found.               |"
        if expected_msg not in out_nf:
            print(f"[-] Centered Pattern Not Found message missing: {out_nf}")
            return False
        print(f"[+] Verified centered Row 4: {repr(expected_msg)} "
              f"(len={len(expected_msg)})")

        # Dismiss modal on space
        time.sleep(0.2)
        os.write(master, b" ")
        out_ed = read_until(master, b"^K: Editor keys", timeout=6.0)
        if b"^K: Editor keys" not in out_ed:
            print(f"[-] Return to editor after dismiss failed: {out_ed}")
            return False
        drain_all(master)

        # Clean exit to CP/M
        time.sleep(0.2)
        os.write(master, b"\x11")  # Ctrl+Q
        out_cpm = read_until(master, b"C>", timeout=6.0)
        if b"C>" not in out_cpm:
            print(f"[-] Clean exit to CP/M failed: {out_cpm}")
            return False

        print("[+] Bug 2.26 verification PASSED: Pattern Not Found modal "
              "message is horizontally centered with 15 spaces on both sides.")
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
