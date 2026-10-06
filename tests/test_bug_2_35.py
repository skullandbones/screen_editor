#!/usr/bin/env python3
"""
Automated Test for Bug 2.35:
File Not Found Modal Pop-up Omits Target Filename.

Verifies:
  1. Boot CP/M and launch SE.COM to splash screen.
  2. Press 'O' to enter Open File screen.
  3. Pre-filled drive/user test: Type 'NOFILE.TXT' (appended to 'C0:'):
     - Verify 'File Not Found' modal pop-up appears.
     - Verify Line 4 displays "'C0:NOFILE.TXT' was not found." centered.
     - Verify Line 5 displays "Specified file not found on disk.".
     - Dismiss pop-up with Space.
  4. Bare filename test: Clear buffer, type 'NOFILE.TXT':
     - Verify Line 4 displays "'NOFILE.TXT' was not found.".
     - Dismiss pop-up with Space.
  5. Explicit drive test: Clear buffer, type 'B:MISSING.DAT':
     - Verify Line 4 displays "'B:MISSING.DAT' was not found.".
     - Dismiss pop-up with Space.
  6. Lowercase test: Clear buffer, type 'nofile.txt':
     - Verify Line 4 displays "'NOFILE.TXT' was not found.".
     - Dismiss pop-up with Space.
  7. Cancel Open dialog with ESC and exit cleanly to CP/M with 'q'.
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
        for fname in ["0:SE.COM", "0:se.com"]:
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
    print("  Bug 2.35: 'File Not Found' Modal Displays Target Filename Test")
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

        # Launch SE.COM to splash screen
        time.sleep(0.5)
        os.write(master, b"se\r")
        ok, out = read_until(master, b"lines]", timeout=30.0)
        if not ok:
            print(f"[-] Failed to reach SE.COM splash screen: {repr(out)}")
            return 1
        time.sleep(0.3)
        drain_all(master)

        # ---------------------------------------------------------------------
        # Subtest 1: Open missing file with prefilled prefix ('C0:NOFILE.TXT')
        # ---------------------------------------------------------------------
        print("[*] Subtest 1: Testing prefilled missing 'C0:NOFILE.TXT'...")
        os.write(master, b"o")
        ok, out = read_until(master, b"Enter filename to open", timeout=6.0)
        if not ok:
            print("[-] Failed to open File Open screen.")
            return 1
        time.sleep(0.2)
        drain_all(master)

        os.write(master, b"NOFILE.TXT\r")
        ok, out = read_until(master, b"Press any key to continue", timeout=6.0)
        if not ok:
            print(f"[-] FNF modal did not appear: {repr(out)}")
            return 1

        exp_msg1_c0 = b"'C0:NOFILE.TXT' was not found."
        if exp_msg1_c0 not in out:
            print(
                f"[-] Expected '{exp_msg1_c0.decode()}' in modal, "
                f"got: {repr(out)}"
            )
            return 1

        exp_msg2 = b"Specified file not found on disk."
        if exp_msg2 not in out:
            print(
                f"[-] Expected '{exp_msg2.decode()}' in modal, got: {repr(out)}"
            )
            return 1
        print(f"[+] Subtest 1 PASSED: Found '{exp_msg1_c0.decode()}'.")

        # Dismiss modal with space
        time.sleep(0.1)
        os.write(master, b" ")
        ok, _ = read_until(master, b"Enter filename to open", timeout=6.0)
        if not ok:
            print("[-] Open dialog not restored after dismissing FNF modal.")
            return 1
        time.sleep(0.2)
        drain_all(master)

        # ---------------------------------------------------------------------
        # Subtest 2: Bare missing file without drive prefix ('NOFILE.TXT')
        # ---------------------------------------------------------------------
        print("[*] Subtest 2: Testing bare missing 'NOFILE.TXT'...")
        # Clear edit box with backspaces
        os.write(master, b"\x08" * 20)
        time.sleep(0.1)
        os.write(master, b"NOFILE.TXT\r")
        ok, out = read_until(master, b"Press any key to continue", timeout=6.0)
        if not ok:
            print(f"[-] FNF modal did not appear: {repr(out)}")
            return 1

        exp_msg1_bare = b"'NOFILE.TXT' was not found."
        if exp_msg1_bare not in out:
            print(
                f"[-] Expected '{exp_msg1_bare.decode()}' in modal, "
                f"got: {repr(out)}"
            )
            return 1
        print(f"[+] Subtest 2 PASSED: Found '{exp_msg1_bare.decode()}'.")

        # Dismiss modal with space
        time.sleep(0.1)
        os.write(master, b" ")
        ok, _ = read_until(master, b"Enter filename to open", timeout=6.0)
        if not ok:
            print("[-] Open dialog not restored after dismissing FNF modal.")
            return 1
        time.sleep(0.2)
        drain_all(master)

        # ---------------------------------------------------------------------
        # Subtest 3: Explicit drive prefix ('B:MISSING.DAT')
        # ---------------------------------------------------------------------
        print("[*] Subtest 3: Testing explicit drive 'B:MISSING.DAT'...")
        os.write(master, b"\x08" * 20)
        time.sleep(0.1)
        os.write(master, b"B:MISSING.DAT\r")
        ok, out = read_until(master, b"Press any key to continue", timeout=6.0)
        if not ok:
            print(f"[-] FNF modal did not appear: {repr(out)}")
            return 1

        exp_msg1_b = b"'B:MISSING.DAT' was not found."
        if exp_msg1_b not in out:
            print(
                f"[-] Expected '{exp_msg1_b.decode()}' in modal, "
                f"got: {repr(out)}"
            )
            return 1
        print(f"[+] Subtest 3 PASSED: Found '{exp_msg1_b.decode()}'.")

        # Dismiss modal with space
        time.sleep(0.1)
        os.write(master, b" ")
        ok, _ = read_until(master, b"Enter filename to open", timeout=6.0)
        if not ok:
            print("[-] Open dialog not restored after dismissing FNF modal.")
            return 1
        time.sleep(0.2)
        drain_all(master)

        # ---------------------------------------------------------------------
        # Subtest 4: Lowercase input converted to uppercase ('nofile.txt')
        # ---------------------------------------------------------------------
        print("[*] Subtest 4: Testing lowercase 'nofile.txt'...")
        os.write(master, b"\x08" * 20)
        time.sleep(0.1)
        os.write(master, b"nofile.txt\r")
        ok, out = read_until(master, b"Press any key to continue", timeout=6.0)
        if not ok:
            print(f"[-] FNF modal did not appear: {repr(out)}")
            return 1

        if exp_msg1_bare not in out:
            print(
                f"[-] Expected '{exp_msg1_bare.decode()}' for lowercase, "
                f"got: {repr(out)}"
            )
            return 1
        print(
            f"[+] Subtest 4 PASSED: Lowercase input converted to "
            f"'{exp_msg1_bare.decode()}'."
        )

        # Dismiss modal with space
        time.sleep(0.1)
        os.write(master, b" ")
        read_until(master, b"Enter filename to open", timeout=6.0)
        time.sleep(0.2)
        drain_all(master)

        # Cancel Open dialog with ESC to return to splash screen
        os.write(master, b"\x1b")
        ok, _ = read_until(master, b"lines]", timeout=6.0)
        if not ok:
            print("[-] Failed to return to splash screen with ESC.")
            return 1
        time.sleep(0.2)
        drain_all(master)

        # Exit to CP/M with 'q'
        os.write(master, b"q")
        ok, _ = read_until(master, b"C>", timeout=6.0)
        if not ok:
            print("[-] Failed to exit cleanly to CP/M with 'q'.")
            return 1

        print("\n" + "=" * 65)
        print("  [SUCCESS] All 'File Not Found' Filename Subtests PASSED!")
        print("=" * 65)
        return 0

    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2.0)
        except Exception:
            proc.kill()


if __name__ == "__main__":
    sys.exit(main())
