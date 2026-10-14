#!/usr/bin/env python3
"""
test_bug_2_1_18.py - Verification for Bug 2.1.18:
Splash Screen Geometry Hotkeys (1=80x24, 2=120x40).

Verifies:
  1. Boot RomWBW CP/M on RC2014 emulator.
  2. Launch SE.COM from CP/M prompt and reach splash screen.
  3. Assert splash screen commands display:
     "type   [1]              set 80x24"
     "type   [2]              set 120x40"
  4. Press '2' and verify switch to 120x40 mode.
  5. Press '1' and verify switch back to 80x24 mode.
  6. Exit cleanly to CP/M with 'q'.
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


def test_bug_2_1_18():
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

        if b"set 80x24" not in out_splash or b"set 120x40" not in out_splash:
            buf_str = repr(out_splash[-300:])
            print(f"[-] Step 4: Hotkey labels missing. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 4: Splash displays 1=80x24 and 2=120x40.", flush=True)

        # Step 5: Press '2' to switch to 120x40 mode
        print("[*] Step 5: Pressing '2' to switch to 120x40 mode...",
              flush=True)
        time.sleep(0.3)
        os.write(master, b"2")
        out_120 = read_until(master, b"120x40", timeout=10.0)
        if b"120x40" not in out_120:
            buf_str = repr(out_120[-300:])
            print(f"[-] Step 5: Failed switch to 120x40. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 5: Switched to 120x40 mode successfully.", flush=True)

        # Step 6: Press '1' to switch back to 80x24 mode
        print("[*] Step 6: Pressing '1' to switch back to 80x24 mode...",
              flush=True)
        time.sleep(0.3)
        os.write(master, b"1")
        out_80 = read_until(master, b"80x24", timeout=10.0)
        if b"80x24" not in out_80:
            buf_str = repr(out_80[-300:])
            print(f"[-] Step 6: Failed switch to 80x24. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 6: Switched back to 80x24 mode successfully.",
              flush=True)

        # Step 7: Exit cleanly with 'q'
        print("[*] Step 7: Exiting to CP/M with 'q'...", flush=True)
        time.sleep(0.3)
        os.write(master, b"q")
        out_exit = read_until(master, b"C>", timeout=10.0)
        if b"C>" not in out_exit:
            buf_str = repr(out_exit[-300:])
            print(f"[-] Step 7: Failed to exit cleanly. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 7: Exited cleanly to CP/M prompt.", flush=True)

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            pass
        os.close(master)

    elapsed = time.time() - start_time
    print(f"[+] All Bug 2.1.18 tests PASSED in {elapsed:.2f}s!", flush=True)
    return True


if __name__ == "__main__":
    success = test_bug_2_1_18()
    sys.exit(0 if success else 1)
