#!/usr/bin/env python3
"""
Automated Test for Bug 2.16:
Progress Pop-up Uses "Loading" Instead of "Opening" and "Inserting".

Verifies:
  1. File Open Progress Modal displays centered title:
     "|                  Opening File                  |"
  2. File Save Progress Modal displays centered title:
     "|                  Saving File                   |"
  3. Block Insert Progress Modal displays centered title:
     "|                 Inserting File                 |"
  4. User Area File Open Progress Modal displays centered title:
     "|                  Opening File                  |"
"""

import os
import sys
import time
import tty
import select
import subprocess


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


def setup_disk_files(repo_root, cpmcp_bin, cpmrm_bin, img_file, se_bin):
    # Ensure SE.COM is installed on drive C (user 0)
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, "0:SE.COM"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )

    # Ensure 2.TXT exists on user 0
    two_path = os.path.join(repo_root, "2.TXT")
    if not os.path.isfile(two_path):
        with open(two_path, "w", encoding="ascii") as f:
            f.write("Line 1 of 2.TXT\r\nLine 2 of 2.TXT\r\n")
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, two_path, "0:2.TXT"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )

    # Ensure INS1.TXT exists on user 0
    ins1_path = os.path.join(repo_root, "INS1.TXT")
    with open(ins1_path, "w", encoding="ascii") as f:
        f.write("INSERTED LINE 1\r\n")
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, ins1_path, "0:INS1.TXT"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )

    # Ensure U1FILE.TXT exists on user 1
    u1_path = os.path.join(repo_root, "U1FILE.TXT")
    with open(u1_path, "w", encoding="ascii") as f:
        f.write("USER 1 LINE 1\r\nUSER 1 LINE 2\r\n")
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, u1_path, "1:U1FILE.TXT"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )


def cleanup_disk_files(repo_root, cpmrm_bin, img_file):
    for f in ["INS1.TXT", "U1FILE.TXT"]:
        host_f = os.path.join(repo_root, f)
        if os.path.isfile(host_f):
            try:
                os.remove(host_f)
            except OSError:
                pass
        subprocess.run(
            [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, f"0:{f}"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "1:U1FILE.TXT"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )


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
    print("  Bug 2.16: Progress Pop-up Terminology (Opening/Inserting) Test ")
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
        # Boot RomWBW
        ok, _ = read_until(master, b"Boot [H=Help]:", timeout=8.0)
        if not ok:
            print("[-] RomWBW boot prompt not seen")
            return 1
        time.sleep(0.5)
        os.write(master, b"c\r")
        read_until(master, b"B>", timeout=6.0)
        time.sleep(0.5)
        os.write(master, b"c:\r")
        read_until(master, b"C>", timeout=8.0)
        time.sleep(0.5)

        # ---------------------------------------------------------------------
        # Subtest 1: File Open Progress Modal displays "Opening File"
        # ---------------------------------------------------------------------
        print("[*] Subtest 1: Testing File Open Progress Modal title...")
        os.write(master, b"se 2.TXT\r")
        ok, load_out = read_until(
            master, b"Please wait for completion", timeout=30.0
        )
        load_out += drain_all(master)
        if not ok:
            print(f"[-] Failed to load 2.TXT into editor: {repr(load_out)}")
            return 1

        exp_open_title = b"|                  Opening File                  |"
        if exp_open_title not in load_out:
            print(
                f"[-] Expected title '{exp_open_title.decode()}' not found."
            )
            print(f"    Buffer snippet: {repr(load_out[:500])}")
            return 1
        print(f"[+] Subtest 1 PASSED: Found '{exp_open_title.decode()}'.")

        read_until(master, b"Line    1/2", timeout=30.0)

        # ---------------------------------------------------------------------
        # Subtest 2: File Save Progress Modal displays "Saving File"
        # ---------------------------------------------------------------------
        print("[*] Subtest 2: Testing File Save Progress Modal title...")
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"\x13")  # Ctrl+S
        ok, out = read_until(master, b"Enter filename to save:", timeout=6.0)
        if not ok:
            print("[-] Failed to open Save dialog with Ctrl+S.")
            return 1
        time.sleep(0.2)
        drain_all(master)

        os.write(master, b"\r")  # Accept pre-filled 2.TXT
        ok_ow, ow_out = read_until(master, b"Overwrite?", timeout=6.0)
        if ok_ow:
            time.sleep(0.2)
            os.write(master, b"y")  # Confirm overwrite
        ok, save_out = read_until(
            master, b"Please wait for completion", timeout=20.0
        )
        save_out = ow_out + save_out + drain_all(master)
        if not ok:
            print(f"[-] Failed to complete file save: {repr(save_out)}")
            return 1

        exp_save_title = b"|                  Saving File                   |"
        if exp_save_title not in save_out:
            print(
                f"[-] Expected title '{exp_save_title.decode()}' not found."
            )
            print(f"    Buffer snippet: {repr(save_out[:500])}")
            return 1
        print(f"[+] Subtest 2 PASSED: Found '{exp_save_title.decode()}'.")

        read_until(master, b"Line    1/2", timeout=20.0)

        # ---------------------------------------------------------------------
        # Subtest 3: Block Insert Progress Modal displays "Inserting File"
        # ---------------------------------------------------------------------
        print("[*] Subtest 3: Testing Block Insert Progress Modal title...")
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"\x02")  # Ctrl+B (Start block)
        time.sleep(0.2)
        drain_all(master)

        os.write(master, b"\x0f")  # Ctrl+O (Block Insert)
        ok, out = read_until(master, b"Enter filename to insert:", timeout=6.0)
        if not ok:
            print("[-] Failed to open Block Insert prompt.")
            return 1
        time.sleep(0.2)
        drain_all(master)

        os.write(master, b"INS1.TXT\r")
        ok, ins_out = read_until(
            master, b"Please wait for completion", timeout=15.0
        )
        ins_out += drain_all(master)
        if not ok:
            print(f"[-] Block Insert modal failed to appear: {repr(ins_out)}")
            return 1

        exp_ins_title = b"|                 Inserting File                 |"
        if exp_ins_title not in ins_out:
            print(
                f"[-] Expected title '{exp_ins_title.decode()}' not found."
            )
            print(f"    Buffer snippet: {repr(ins_out)}")
            return 1
        print(f"[+] Subtest 3 PASSED: Found '{exp_ins_title.decode()}'.")

        # Wait for insert to complete and editor to return to main loop
        read_until(master, b"INSERTED LINE 1", timeout=15.0)

        # ---------------------------------------------------------------------
        # Subtest 4: User Area File Open Progress Modal displays "Opening File"
        # ---------------------------------------------------------------------
        print("[*] Subtest 4: Testing User Area Open Progress Modal title...")
        # Exit to CP/M
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"\x11")  # Ctrl+Q
        ok_sc, _ = read_until(master, b"Save changes?", timeout=6.0)
        if ok_sc:
            time.sleep(0.2)
            os.write(master, b"n")  # Don't save
        ok_cpm, _ = read_until(master, b"C>", timeout=8.0)
        if not ok_cpm:
            print("[-] Failed to exit to CP/M prompt before Subtest 4.")
            return 1
        time.sleep(0.5)
        drain_all(master)

        # Launch SE with User 1 file: se 1C:U1FILE.TXT
        os.write(master, b"se 1C:U1FILE.TXT\r")
        ok, u1_out = read_until(
            master, b"Please wait for completion", timeout=45.0
        )
        u1_out += drain_all(master)
        if not ok:
            print(f"[-] Failed to load 1C:U1FILE.TXT: {repr(u1_out)}")
            return 1

        if exp_open_title not in u1_out:
            print(
                f"[-] Expected title '{exp_open_title.decode()}' not found."
            )
            print(f"    Buffer snippet: {repr(u1_out)}")
            return 1
        print(f"[+] Subtest 4 PASSED: Found '{exp_open_title.decode()}'.")

        read_until(master, b"Line    1/2", timeout=30.0)

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
        print("  [SUCCESS] All 4 Progress Modal Terminology Subtests PASSED!")
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
