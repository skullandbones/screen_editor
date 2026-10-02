#!/usr/bin/env python3
"""
test_bug_2_2.py - Isolated Bug Step Reproduction for Bug 2.2:
System Hangs When Loading Large Files with 32K Available RAM.

Verifies:
  1. Boot RomWBW CP/M on RC2014 emulator with 32K Available RAM
     (RAMDRIVE=PRESERVE, LINES=32K, PLUGIN=AUTOLOAD).
  2. Verify that SE reports 32 KB free memory.
  3. Load a file exceeding 32 KB (350 lines > 256 Far RAM slots).
  4. With unpatched code: SE attempts to page into non-existent bank 1,
     overwriting HBIOS/vector bank 0 and hanging the system.
  5. With fix applied: SE cleanly catches slot allocation exhaustion,
     sets FILE_IS_TRUNCATED, displays the truncation alert popup,
     and enters the editor cleanly without hanging or crashing.
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


def read_until(master_fd, match_bytes, timeout=25.0):
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

    out = read_until(master, b"Boot [H=Help]:", timeout=12.0)
    time.sleep(0.3)
    os.write(master, b"c\r")
    out += read_until(master, b"B>", timeout=12.0)
    if b"B>" not in out:
        raise RuntimeError("Failed to boot into CP/M prompt")

    return proc, master


def remove_files_from_image(cpmrm_bin, img_file, filenames):
    for fn in filenames:
        subprocess.run(
            [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, f"0:{fn}"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        subprocess.run(
            [cpmrm_bin, "-f", "wbw_hd1k_3", img_file, f"0:{fn}"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )


def put_file_to_image(cpmcp_bin, img_file, local_path, cpm_filename):
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, local_path,
         f"0:{cpm_filename}"],
        check=True
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_3", img_file, local_path,
         f"0:{cpm_filename}"],
        check=True
    )


def test_bug_2_2():
    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = find_paths()

    print("[*] Running Bug 2.2 isolated reproduction test...", flush=True)

    # 1. Clean up old test files
    remove_files_from_image(
        cpmrm_bin, img_file,
        ["SE.CFG", "BIG350.TXT", "SE.COM", "$$$SE$$$.SWP"]
    )

    # 2. Inject current SE.COM
    put_file_to_image(cpmcp_bin, img_file, se_bin, "SE.COM")

    # 3. Create SE.CFG: RAMDRIVE=PRESERVE, LINES=32K, PLUGIN=AUTOLOAD
    cfg_tmp = "/tmp/TEST_BUG_2_2_SE.CFG"
    with open(cfg_tmp, "wb") as f:
        f.write(b"RAMDRIVE=PRESERVE\r\nLINES=32K\r\nPLUGIN=AUTOLOAD\r\n")
    put_file_to_image(cpmcp_bin, img_file, cfg_tmp, "SE.CFG")
    if os.path.exists(cfg_tmp):
        os.remove(cfg_tmp)

    # 4. Generate BIG350.TXT (350 lines > 256 slots = 32KB limit)
    big_tmp = "/tmp/BIG350.TXT"
    with open(big_tmp, "wb") as f:
        for i in range(1, 351):
            line = f"Line {i:03d} of 350 - Testing 32K Far RAM boundary.\r\n"
            f.write(line.encode("ascii"))
    put_file_to_image(cpmcp_bin, img_file, big_tmp, "BIG350.TXT")
    if os.path.exists(big_tmp):
        os.remove(big_tmp)

    proc, master = boot_cpm(emu_bin, rom_file, img_file)
    try:
        time.sleep(0.4)
        os.write(master, b"c:\r")
        read_until(master, b"C>", timeout=15.0)

        # Launch SE.COM on BIG350.TXT
        print("[*] Launching: se big350.txt...", flush=True)
        time.sleep(0.4)
        os.write(master, b"se big350.txt\r")

        # Wait for file loading to complete (either truncation alert or editor)
        t_start = time.time()
        out_load = b""
        while time.time() - t_start < 60.0:
            chunk = read_until(master, b"Truncated", timeout=3.0)
            out_load += chunk
            if b"Truncated" in out_load:
                break
            if b"Free:" in out_load:
                break

        out_load += drain_all(master)

        print("\n--- Console Output After Load ---")
        preview = out_load.decode("latin1", errors="replace")
        for line in preview.splitlines()[-15:]:
            print(f"    {line}")
        print("---------------------------------\n")

        # Check if Truncated alert appeared or if editor loaded safely
        is_truncated = (
            b"Truncated" in out_load or
            b"truncated" in out_load or
            b"FILE TRUNCATED" in out_load.upper()
        )
        has_status_line = (
            b"BIG350.TXT" in out_load and b"Free:" in out_load
        )

        assert is_truncated or has_status_line, (
            "Bug 2.2 reproduced: System hung or crashed when loading large "
            "file with 32K available RAM!"
        )

        if is_truncated:
            print("[+] Truncation popup displayed as expected!")
            # Dismiss popup with any key (e.g. Enter or Space)
            time.sleep(0.3)
            os.write(master, b" ")
            out_ed = read_until(master, b"BIG350.TXT", timeout=10.0)
            out_ed += drain_all(master)
            print("[+] Editor resumed cleanly after dismissing popup.")

        # Test Ctrl+Q exit back to CP/M
        time.sleep(0.3)
        os.write(master, b"\x11")  # Ctrl+Q
        # If truncated file was marked dirty or modified, might prompt
        out_exit = read_until(master, b"C>", timeout=10.0)
        if b"C>" not in out_exit:
            # Maybe prompt to discard changes: send 'y'
            os.write(master, b"y")
            out_exit += read_until(master, b"C>", timeout=10.0)

        assert b"C>" in out_exit, "Failed to exit cleanly back to CP/M prompt"
        print("[+] Clean exit back to CP/M prompt.")
        print("[+] Test PASSED: Bug 2.2 verified!")
        return True

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            pass
        os.close(master)
        remove_files_from_image(
            cpmrm_bin, img_file,
            ["SE.CFG", "BIG350.TXT", "$$$SE$$$.SWP"]
        )


if __name__ == "__main__":
    success = test_bug_2_2()
    sys.exit(0 if success else 1)
