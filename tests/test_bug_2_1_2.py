#!/usr/bin/env python3
"""
test_bug_2_1_2.py - Verification for Bug 2.1.2:
Startup Screen Geometry Inversion (Defaults to 80x24).

Verifies:
  1. Boot RomWBW CP/M on RC2014 emulator.
  2. Launch SE.COM from CP/M prompt and reach splash screen.
  3. Assert splash screen indicates:
     "Active Screen : [80x24 (Classic Terminal)]".
  4. Enter editor mode with 'e'.
  5. Assert editor status bar is present and active geometry is 80x24.
  6. Exit cleanly to CP/M with Ctrl+Q.
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

    return emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin


def read_until(master_fd, match_bytes, timeout=15.0):
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
                    return buf
            except (BlockingIOError, OSError):
                pass
    return buf


def drain_all(master_fd, quiet_time=0.15):
    res = b""
    while True:
        r, _, _ = select.select([master_fd], [], [], quiet_time)
        if not r:
            break
        try:
            data = os.read(master_fd, 2048)
            if not data:
                break
            res += data
        except (BlockingIOError, OSError):
            break
    return res


def boot_cpm(emu_bin, rom_file, img_file):
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )
    os.close(slave)

    out = read_until(master, b"Boot [H=Help]:", timeout=8.0)
    if b"Boot [H=Help]:" not in out:
        raise RuntimeError("Failed to reach RomWBW boot prompt")

    time.sleep(0.4)
    os.write(master, b"c\r")
    out = read_until(master, b"B>", timeout=15.0)
    if b"B>" not in out:
        raise RuntimeError("Failed to boot into CP/M prompt")

    return proc, master


def test_bug_2_1_2():
    start_time = time.time()
    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = find_paths()

    # Step 1: Inject updated SE.COM into local disk image
    print("[*] Step 1: Injecting SE.COM onto CP/M drive C:...", flush=True)
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.COM", "0:se.com"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, "0:SE.COM"],
        check=True
    )
    print("[+] Step 1: Injected SE.COM successfully.", flush=True)

    # Step 2: Boot RomWBW CP/M
    print("[*] Step 2: Booting RomWBW CP/M on RC2014 emulator...", flush=True)
    proc, master = boot_cpm(emu_bin, rom_file, img_file)
    print("[+] Step 2: Booted into CP/M prompt.", flush=True)

    try:
        # Step 3: Switch to drive C:
        print("[*] Step 3: Switching to drive C:...", flush=True)
        time.sleep(0.4)
        os.write(master, b"c:\r")
        out_c = read_until(master, b"C>", timeout=10.0)
        if b"C>" not in out_c:
            buf_str = repr(out_c[-300:])
            print(f"[-] Step 3: Failed to reach C>. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 3: Switched to drive C:.", flush=True)

        # Step 4: Launch SE.COM
        print("[*] Step 4: Launching SE.COM...", flush=True)
        time.sleep(0.4)
        os.write(master, b"se\r")
        out_splash = read_until(master, b"Col 0", timeout=30.0)
        if b"Col 0" not in out_splash:
            buf_str = repr(out_splash[-300:])
            print(f"[-] Step 4: Failed to load splash. Buffer: {buf_str}",
                  flush=True)
            return False

        expected_mode = b"Active Screen : [80x24 (Classic Terminal)]"
        if expected_mode not in out_splash:
            buf_str = repr(out_splash[-300:])
            print(f"[-] Step 4: Mode not 80x24. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 4: Splash indicates default 80x24 mode.", flush=True)

        # Step 5: Enter editor mode ('e')
        print("[*] Step 5: Entering editor mode ('e')...", flush=True)
        time.sleep(0.4)
        os.write(master, b"e")
        out_edit = read_until(master, b"^K: Editor keys", timeout=10.0)
        if b"^K: Editor keys" not in out_edit:
            buf_str = repr(out_edit[-300:])
            print(f"[-] Step 5: Failed to enter editor. Buffer: {buf_str}",
                  flush=True)
            return False
        # Field 2 of status bar in 80x24 should be " 80x24 |"
        if b" 80x24 |" not in out_edit:
            buf_str = repr(out_edit[-300:])
            print(f"[-] Step 5: Status bar not 80x24. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 5: Entered editor with 80x24 status bar.", flush=True)

        # Step 6: Exit cleanly back to CP/M
        print("[*] Step 6: Exiting to CP/M with Ctrl+Q...", flush=True)
        time.sleep(0.3)
        os.write(master, b"\x11")  # Ctrl+Q
        out_exit = read_until(master, b"C>", timeout=10.0)
        if b"C>" not in out_exit:
            buf_str = repr(out_exit[-300:])
            print(f"[-] Step 6: Failed to exit cleanly. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 6: Exited cleanly to CP/M prompt.", flush=True)

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            pass
        os.close(master)

    elapsed = time.time() - start_time
    print(f"[+] All Bug 2.1.2 tests PASSED in {elapsed:.2f}s!", flush=True)
    return True


if __name__ == "__main__":
    success = test_bug_2_1_2()
    sys.exit(0 if success else 1)
