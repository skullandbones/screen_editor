#!/usr/bin/env python3
"""
test_bug_2_1_16.py - Verification for Bug 2.1.16:
Forward Deletion Line Join Sticky Target Column Update.

Verifies:
  1. Boot RomWBW CP/M on RC2014 emulator.
  2. Launch SE.COM with a multi-line test file.
  3. Move cursor to Column 12 on Row 1 (establishing TARGET_COL = 12).
  4. Move cursor down to Row 2 (length 5, so cursor clamps to Col 5).
  5. Press Ctrl+D at EOL of Row 2 to join Row 2 and Row 3.
  6. Verify sticky TARGET_COL is updated to visual column (Col 5).
  7. Move cursor down to Row 3 (length 14) and verify cursor lands at Col 5.
  8. Exit cleanly to CP/M with Ctrl+Q and 'n'.
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


def test_bug_2_1_16():
    start_time = time.time()
    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = find_paths()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    test_txt_path = os.path.join(script_dir, "test16.txt")
    with open(test_txt_path, "wb") as f:
        f.write(b"ABCDEFGHIJKLMN\r\n12345\r\n67890\r\n0123456789ABCD\r\n")

    # Step 1: Inject updated SE.COM and TEST16.TXT into local disk image
    print("[*] Step 1: Injecting SE.COM and TEST16.TXT onto disk...",
          flush=True)
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.COM", "0:TEST16.TXT"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, "0:SE.COM"],
        check=True
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, test_txt_path,
         "0:TEST16.TXT"],
        check=True
    )
    print("[+] Step 1: Injected test files successfully.", flush=True)

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

        # Step 4: Launch SE TEST16.TXT
        print("[*] Step 4: Launching SE TEST16.TXT...", flush=True)
        time.sleep(0.4)
        os.write(master, b"se test16.txt\r")
        out_edit = read_until(master, b"TEST16.TXT", timeout=25.0)
        if b"TEST16.TXT" not in out_edit:
            buf_str = repr(out_edit[-300:])
            print(f"[-] Step 4: Editor load failed. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 4: Opened TEST16.TXT in editor.", flush=True)

        # Step 5: Position cursor at Row 1, Col 12
        print("[*] Step 5: Positioning cursor at Col 12 on Row 1...",
              flush=True)
        time.sleep(0.3)
        # Move right 12 times
        os.write(master, b"\x1b[C" * 12)
        out_col12 = read_until(master, b"Col 12", timeout=5.0)
        if b"Col 12" not in out_col12:
            buf_str = repr(out_col12[-300:])
            print(f"[-] Step 5: Col 12 not reached. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 5: Cursor positioned at Row 1, Col 12.", flush=True)

        # Step 6: Move cursor down to Row 2 (clamps to Col 5)
        print("[*] Step 6: Moving cursor down to Row 2...", flush=True)
        time.sleep(0.3)
        os.write(master, b"\x1b[B")
        out_row2 = read_until(master, b"Line    2/4    Col 5", timeout=5.0)
        if b"Line    2/4    Col 5" not in out_row2:
            buf_str = repr(out_row2[-300:])
            print(f"[-] Step 6: Line 2 Col 5 failed. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 6: Cursor clamped to Row 2, Col 5.", flush=True)

        # Step 7: Press Ctrl+D at EOL of Row 2 to join Row 2 and Row 3
        print("[*] Step 7: Pressing Ctrl+D to join Row 2 and Row 3...",
              flush=True)
        time.sleep(0.3)
        os.write(master, b"\x04")
        out_join = read_until(master, b"Line    2/3    Col 5", timeout=5.0)
        if b"Line    2/3    Col 5" not in out_join:
            buf_str = repr(out_join[-300:])
            print(f"[-] Step 7: Line join failed. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 7: Joined lines; cursor at Row 2, Col 5.", flush=True)

        # Step 8: Move cursor down to Row 3 (verify sticky TARGET_COL = 5)
        print("[*] Step 8: Moving down to Row 3 to verify TARGET_COL...",
              flush=True)
        time.sleep(0.3)
        os.write(master, b"\x1b[B")
        out_row3 = read_until(master, b"Line    3/3    Col 5", timeout=5.0)
        if b"Line    3/3    Col 5" not in out_row3:
            buf_str = repr(out_row3[-300:])
            print(f"[-] Step 8: TARGET_COL not 5 on Row 3. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 8: Row 3 verified at Col 5 (sticky TARGET_COL = 5).",
              flush=True)

        # Step 9: Exit cleanly via Ctrl+Q and discard prompt ('n')
        print("[*] Step 9: Exiting editor cleanly...", flush=True)
        time.sleep(0.3)
        os.write(master, b"\x11")  # Ctrl+Q
        out_prompt = read_until(master, b"Save", timeout=5.0)
        time.sleep(0.3)
        os.write(master, b"n")
        out_exit = read_until(master, b"C>", timeout=10.0)
        if b"C>" not in out_exit:
            buf_str = repr(out_exit[-300:])
            print(f"[-] Step 9: Clean exit failed. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 9: Exited cleanly to CP/M prompt.", flush=True)

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            pass
        os.close(master)
        if os.path.exists(test_txt_path):
            os.remove(test_txt_path)

    elapsed = time.time() - start_time
    print(f"[+] All Bug 2.1.16 tests PASSED in {elapsed:.2f}s!", flush=True)
    return True


if __name__ == "__main__":
    success = test_bug_2_1_16()
    sys.exit(0 if success else 1)
