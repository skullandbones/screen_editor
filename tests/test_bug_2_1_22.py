#!/usr/bin/env python3
"""
test_bug_2_1_22.py - Verification for Bug 2.1.22:
Splash Screen Ctrl+O and Ctrl+S Support.

Verifies:
  1. Inject SE.COM onto CP/M drive C:.
  2. Boot RomWBW CP/M on RC2014 emulator.
  3. Switch to drive C: and launch SE.COM to splash screen.
  4. Verify splash menu displays:
       "type   [O]  or  [^O]    to open file"
       "type   [S]  or  [^S]    to save file"
  5. Press Ctrl+O (0x0F) on splash screen and verify "Open File" browser
     opens; press Esc to cancel back to splash screen.
  6. Press Ctrl+S (0x13) on splash screen and verify "Save File" modal
     opens ("Enter Filename:"); enter "SPLCTRLS.TXT" and save.
  7. Quit SE.COM ('q') and verify SPLCTRLS.TXT was saved on drive C:.
"""

import os
import select
import subprocess
import sys
import time
import tty


def find_paths():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    workspace_root = os.path.abspath(os.path.join(repo_root, "..", ".."))
    if not os.path.isdir(os.path.join(workspace_root, "tools")):
        workspace_root = os.path.abspath(
            os.path.join(repo_root, "..", "screen_editor")
        )

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


def drain_all(master_fd, quiet_time=0.2):
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


def test_bug_2_1_22():
    start_time = time.time()
    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = find_paths()

    print("[*] Step 1: Injecting SE.COM onto CP/M drive C:...", flush=True)
    subprocess.run(
        [
            cpmrm_bin,
            "-f",
            "wbw_hd1k_0",
            img_file,
            "0:SE.COM",
            "0:se.com",
            "0:SPLCTRLS.TXT",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, "0:SE.COM"],
        check=True,
    )
    print("[+] Step 1: Injected SE.COM successfully.", flush=True)

    print("[*] Step 2: Booting RomWBW CP/M on RC2014 emulator...", flush=True)
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )
    os.close(slave)

    try:
        out_boot = read_until(master, b"Boot [H=Help]:", timeout=10.0)
        if b"Boot [H=Help]:" not in out_boot:
            buf_str = repr(out_boot[-300:])
            print(
                f"[-] Step 2: Failed to reach Boot prompt. Buffer: {buf_str}",
                flush=True,
            )
            return False

        time.sleep(0.4)
        os.write(master, b"c\r")
        out_cpm = read_until(master, b"B>", timeout=15.0)
        if b"B>" not in out_cpm:
            buf_str = repr(out_cpm[-300:])
            print(
                f"[-] Step 2: Failed to reach B> prompt. Buffer: {buf_str}",
                flush=True,
            )
            return False
        print("[+] Step 2: Booted into CP/M prompt.", flush=True)

        print("[*] Step 3: Switching to drive C:...", flush=True)
        time.sleep(0.4)
        os.write(master, b"c:\r")
        out_c = read_until(master, b"C>", timeout=10.0)
        if b"C>" not in out_c:
            buf_str = repr(out_c[-300:])
            print(
                f"[-] Step 3: Failed to reach C>. Buffer: {buf_str}",
                flush=True,
            )
            return False
        print("[+] Step 3: Switched to drive C:.", flush=True)

        print(
            "[*] Step 4: Launching SE.COM and checking splash hints...",
            flush=True,
        )
        time.sleep(0.4)
        os.write(master, b"se\r")
        out_splash = read_until(master, b"Col 0", timeout=30.0)
        if (
            b"[O]  or  [^O]    to open file" not in out_splash
            or b"[S]  or  [^S]    to save file" not in out_splash
        ):
            buf_str = repr(out_splash[-400:])
            print(
                f"[-] Step 4: Splash hints missing [^O]/[^S]. "
                f"Buffer: {buf_str}",
                flush=True,
            )
            return False
        print(
            "[+] Step 4: Verified [O] or [^O] and [S] or [^S] on splash.",
            flush=True,
        )

        print(
            "[*] Step 5: Pressing Ctrl+O (0x0F) on splash screen...",
            flush=True,
        )
        drain_all(master)
        time.sleep(0.4)
        os.write(master, b"\x0f")
        out_open = read_until(master, b"Enter filename to open:", timeout=15.0)
        out_open += drain_all(master)
        if (
            b"OPEN FILE (DIRECTORY - DRIVE C:)" not in out_open
            or b"Enter filename to open:" not in out_open
        ):
            buf_str = repr(out_open[-300:])
            print(
                f"[-] Step 5: Ctrl+O failed to open File Browser. "
                f"Buffer: {buf_str}",
                flush=True,
            )
            return False
        time.sleep(0.4)
        os.write(master, b"\x1b")
        out_cancel = read_until(master, b"for about", timeout=15.0)
        out_cancel += drain_all(master)
        if b"[O]  or  [^O]    to open file" not in out_cancel:
            buf_str = repr(out_cancel[-300:])
            print(
                f"[-] Step 5: Esc failed to return to splash. "
                f"Buffer: {buf_str}",
                flush=True,
            )
            return False
        print(
            "[+] Step 5: Ctrl+O opened File Browser and Esc returned.",
            flush=True,
        )

        print(
            "[*] Step 6: Pressing Ctrl+S (0x13) on splash screen...",
            flush=True,
        )
        time.sleep(0.4)
        os.write(master, b"\x13")
        out_save_prompt = read_until(
            master, b"Enter filename to save:", timeout=15.0
        )
        out_save_prompt += drain_all(master)
        if (
            b"SAVE FILE (DIRECTORY - DRIVE C:)" not in out_save_prompt
            or b"Enter filename to save:" not in out_save_prompt
        ):
            buf_str = repr(out_save_prompt[-300:])
            print(
                f"[-] Step 6: Ctrl+S failed to open Save File screen. "
                f"Buffer: {buf_str}",
                flush=True,
            )
            return False
        time.sleep(0.4)
        os.write(master, b"SPLCTRLS.TXT\r")
        out_saved = read_until(master, b"for about", timeout=15.0)
        out_saved += drain_all(master)
        if b"C:SPLCTRLS.TXT" not in out_saved:
            buf_str = repr(out_saved[-300:])
            print(
                f"[-] Step 6: Save from splash Ctrl+S failed. "
                f"Buffer: {buf_str}",
                flush=True,
            )
            return False
        print(
            "[+] Step 6: Ctrl+S opened Save screen and saved SPLCTRLS.TXT.",
            flush=True,
        )

        print(
            "[*] Step 7: Quitting SE.COM and verifying C:SPLCTRLS.TXT...",
            flush=True,
        )
        time.sleep(0.4)
        os.write(master, b"q")
        out_quit = read_until(master, b"C>", timeout=15.0)
        if b"C>" not in out_quit:
            buf_str = repr(out_quit[-300:])
            print(
                f"[-] Step 7: Failed to quit to C>. Buffer: {buf_str}",
                flush=True,
            )
            return False
        time.sleep(0.3)
        os.write(master, b"dir splctrls.txt\r")
        out_dir = read_until(master, b"C>", timeout=10.0)
        if b"SPLCTRLS" not in out_dir:
            buf_str = repr(out_dir[-300:])
            print(
                f"[-] Step 7: SPLCTRLS.TXT not found on C:. Buffer: {buf_str}",
                flush=True,
            )
            return False
        print(
            "[+] Step 7: Verified SPLCTRLS.TXT on drive C: and exited cleanly.",
            flush=True,
        )

        elapsed = time.time() - start_time
        print(
            f"[+] All Bug 2.1.22 Splash Ctrl+O/Ctrl+S tests PASSED "
            f"in {elapsed:.2f}s!",
            flush=True,
        )
        return True
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2.0)
        except subprocess.TimeoutExpired:
            proc.kill()
        os.close(master)


if __name__ == "__main__":
    ok = test_bug_2_1_22()
    sys.exit(0 if ok else 1)
