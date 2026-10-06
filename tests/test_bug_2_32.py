#!/usr/bin/env python3
"""
Automated Test for Bug 2.32:
Redundant "SE.COM" Prefix in Open, Save, Help, Insert & Block Screens.

Verifies:
  1. Boot CP/M and launch 'se'.
  2. Test Open File screen:
     - Verify title is "OPEN FILE (DIRECTORY - DRIVE C:)"
     - Verify redundant "SE.COM - " prefix is absent
     - Verify horizontal centering padding (23 spaces after '~' on 80 cols)
  3. Test Save File screen:
     - Verify title is "SAVE FILE (DIRECTORY - DRIVE C:)"
     - Verify redundant "SE.COM - " prefix is absent
     - Verify horizontal centering padding (23 spaces after '~' on 80 cols)
  4. Test Editor Mode Keys (Help) screen:
     - Enter editor, send Ctrl+K
     - Verify title is "EDITOR MODE KEYS"
     - Verify redundant "SE.COM - " prefix is absent
     - Verify horizontal centering padding (31 spaces after '~' on 80 cols)
  5. Test Insert File screen:
     - Activate block selection (Ctrl+B), send Ctrl+O
     - Verify title is "INSERT FILE (DIRECTORY - DRIVE C:)"
     - Verify redundant "SE.COM - " prefix is absent
     - Verify horizontal centering padding (22 spaces after '~' on 80 cols)
  6. Test Block Save screen:
     - Activate block selection (Ctrl+B), send Ctrl+S
     - Verify title is "SAVE BLOCK (DIRECTORY - DRIVE C:)"
     - Verify redundant "SE.COM - " prefix is absent
     - Verify horizontal centering padding (22 spaces after '~' on 80 cols)
  7. Clean exit to CP/M with Ctrl+Q.
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


def setup_disk_files(img_file, se_bin, help_bin, cpmcp, cpmrm, repo_root):
    if os.path.isfile(cpmrm):
        for fname in ["0:SE.COM", "0:se.com", "0:HELP.OVL", "0:help.ovl",
                      "0:SE.CFG", "0:se.cfg"]:
            subprocess.run(
                [cpmrm, "-f", "wbw_hd1k_0", img_file, fname],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
    subprocess.run(
        [cpmcp, "-f", "wbw_hd1k_0", img_file, se_bin, "0:SE.COM"],
        check=True,
    )
    if os.path.isfile(help_bin):
        subprocess.run(
            [cpmcp, "-f", "wbw_hd1k_0", img_file, help_bin, "0:HELP.OVL"],
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


def run_test():
    paths = find_paths()
    (repo_root, emu_bin, rom_file, img_file, se_bin, help_bin,
     cpmcp, cpmrm) = paths

    setup_disk_files(img_file, se_bin, help_bin, cpmcp, cpmrm, repo_root)

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

        # Set 80x24 classic terminal mode via command line or switch
        print("[*] Launching 'se'...", flush=True)
        time.sleep(0.5)
        os.write(master, b"se\r")
        out = read_until(master, b"Active Screen :", timeout=30.0)
        assert b"Active Screen :" in out, "Failed reaching splash screen"
        drain_all(master, 0.3)

        # Switch to 80x24 mode with '2' to test exact 80-col centering
        os.write(master, b"2")
        time.sleep(0.3)
        read_until(master, b"Active Screen :", timeout=6.0)
        drain_all(master, 0.2)

        # 1. Test Open File screen
        print("[*] Testing Open File Screen title...", flush=True)
        os.write(master, b"o")
        out_open = read_until(master, b"Enter filename to open:", timeout=6.0)
        out_open += drain_all(master, 0.2)

        assert b"OPEN FILE (DIRECTORY - DRIVE C:)" in out_open, (
            f"Expected 'OPEN FILE (DIRECTORY - DRIVE C:)' not found: {out_open}"
        )
        assert b"SE.COM - OPEN FILE" not in out_open, (
            "Redundant 'SE.COM - ' prefix still present on Open File screen!"
        )
        expected_open_pad = (
            b"~" + (b" " * 23) + b"OPEN FILE (DIRECTORY - DRIVE C:)"
        )
        assert expected_open_pad in out_open, (
            f"Open screen title centering mismatch: {out_open}"
        )
        print("[+] Open File screen title and centering verified.")

        # Cancel back to splash with ESC
        os.write(master, b"\x1b")
        read_until(master, b"Active Screen :", timeout=6.0)
        drain_all(master, 0.2)

        # 2. Test Save File screen
        print("[*] Testing Save File Screen title...", flush=True)
        os.write(master, b"s")
        out_save = read_until(master, b"Enter filename to save:", timeout=6.0)
        out_save += drain_all(master, 0.2)

        assert b"SAVE FILE (DIRECTORY - DRIVE C:)" in out_save, (
            f"Expected 'SAVE FILE (DIRECTORY - DRIVE C:)' not found: {out_save}"
        )
        assert b"SE.COM - SAVE FILE" not in out_save, (
            "Redundant 'SE.COM - ' prefix still present on Save File screen!"
        )
        expected_save_pad = (
            b"~" + (b" " * 23) + b"SAVE FILE (DIRECTORY - DRIVE C:)"
        )
        assert expected_save_pad in out_save, (
            f"Save screen title centering mismatch: {out_save}"
        )
        print("[+] Save File screen title and centering verified.")

        # Cancel back to splash with ESC
        os.write(master, b"\x1b")
        read_until(master, b"Active Screen :", timeout=6.0)
        drain_all(master, 0.2)

        # 3. Enter editor and test Editor Mode Keys (Help) screen
        print("[*] Entering editor with 'e'...", flush=True)
        os.write(master, b"e")
        read_until(master, b"^K: Editor keys", timeout=6.0)
        drain_all(master, 0.2)

        print("[*] Testing Editor Mode Keys (Ctrl+K) title...", flush=True)
        os.write(master, b"\x0b")  # Ctrl+K
        out_help = read_until(
            master, b"Press any key to continue", timeout=6.0
        )
        out_help += drain_all(master, 0.2)

        assert b"EDITOR MODE KEYS" in out_help, (
            f"Expected 'EDITOR MODE KEYS' not found: {out_help}"
        )
        assert b"SE.COM - EDITOR MODE KEYS" not in out_help, (
            "Redundant 'SE.COM - ' prefix still present on Help screen!"
        )
        expected_help_pad = b"~" + (b" " * 31) + b"EDITOR MODE KEYS"
        assert expected_help_pad in out_help, (
            f"Help screen title centering mismatch: {out_help}"
        )
        print("[+] Editor Mode Keys screen title and centering verified.")

        # Dismiss Help with space
        os.write(master, b" ")
        read_until(master, b"^K: Editor keys", timeout=6.0)
        drain_all(master, 0.2)

        # 4. Test Insert File screen (Ctrl+B then Ctrl+O in editor)
        print("[*] Testing Insert File Screen title...", flush=True)
        os.write(master, b"\x02")  # Ctrl+B (start block selection)
        time.sleep(0.2)
        read_until(master, b"SEL:", timeout=4.0)
        os.write(master, b"\x0f")  # Ctrl+O (Block Insert File)
        out_insert = read_until(
            master, b"Enter filename to insert:", timeout=6.0
        )
        out_insert += drain_all(master, 0.2)

        assert b"INSERT FILE (DIRECTORY - DRIVE C:)" in out_insert, (
            f"Expected 'INSERT FILE (DIRECTORY - DRIVE C:)' not found: "
            f"{out_insert}"
        )
        assert b"SE.COM - INSERT FILE" not in out_insert, (
            "Redundant 'SE.COM - ' prefix still present on Insert screen!"
        )
        expected_insert_pad = (
            b"~" + (b" " * 22) + b"INSERT FILE (DIRECTORY - DRIVE C:)"
        )
        assert expected_insert_pad in out_insert, (
            f"Insert screen title centering mismatch: {out_insert}"
        )
        print("[+] Insert File screen title and centering verified.")

        # Cancel back to editor with ESC and dismiss any block
        os.write(master, b"\x1b")
        read_until(master, b"^K: Editor keys", timeout=6.0)
        time.sleep(0.1)
        os.write(master, b"\x1b")
        drain_all(master, 0.2)

        # 5. Test Block Save screen (Ctrl+B then Ctrl+S in editor)
        print("[*] Testing Save Block Screen title...", flush=True)
        os.write(master, b"\x02")  # Ctrl+B (start block selection)
        time.sleep(0.2)
        read_until(master, b"SEL:", timeout=4.0)
        os.write(master, b"\x1b[C")  # Extend block
        time.sleep(0.1)
        os.write(master, b"\x13")  # Ctrl+S (Block Save File)
        out_bsave = read_until(
            master, b"Enter filename to save:", timeout=6.0
        )
        out_bsave += drain_all(master, 0.2)

        assert b"SAVE BLOCK (DIRECTORY - DRIVE C:)" in out_bsave, (
            f"Expected 'SAVE BLOCK (DIRECTORY - DRIVE C:)' not found: "
            f"{out_bsave}"
        )
        assert b"SE.COM - SAVE BLOCK" not in out_bsave, (
            "Redundant 'SE.COM - ' prefix still present on Block Save screen!"
        )
        expected_bsave_pad = (
            b"~" + (b" " * 22) + b"SAVE BLOCK (DIRECTORY - DRIVE C:)"
        )
        assert expected_bsave_pad in out_bsave, (
            f"Block Save screen title centering mismatch: {out_bsave}"
        )
        print("[+] Save Block screen title and centering verified.")

        # Cancel back to editor with ESC
        os.write(master, b"\x1b")
        read_until(master, b"^K: Editor keys", timeout=6.0)
        drain_all(master, 0.2)

        # 6. Clean exit to CP/M with Ctrl+Q
        print("[*] Exiting editor to CP/M with Ctrl+Q...", flush=True)
        os.write(master, b"\x11")  # Ctrl+Q
        out_cpm = read_until(master, b"C>", timeout=6.0)
        assert b"C>" in out_cpm, "Failed exiting cleanly to CP/M prompt"
        print("[+] Bug 2.32 verification PASSED: 'SE.COM - ' prefix removed.")
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
