#!/usr/bin/env python3
"""
test_fatfs_vfs.py - End-to-End Validation of FATFS Headless VFS Engine

Validates headless VFS operations executed on RomWBW CP/M via VFSTEST.COM:
1. Boot RomWBW CP/M on RC2014 emulator with hd1k_combo.img.
2. Launch VFSTEST.COM.
3. Test 1: VFS_CMD_PROBE_MOUNT on Unit 0.
4. Test 2: VFS_CMD_GET_DEF_UNIT.
5. Test 3: VFS_CMD_LIST_DIR on root ("/") and verify 13-byte record layout.
6. Test 4: VFS_CMD_LOAD_FILE (/SLICES.TXT) and line streaming.
7. Test 5: VFS_CMD_SAVE_RANGE (/VFSTEST.TXT) (Block Save).
8. Test 6: VFS_CMD_OPEN_FILE, VFS_CMD_READ_CHUNK, VFS_CMD_CLOSE_FILE.
9. Test 7: Error handling on non-existent file path.
10. Verify clean return to CP/M prompt (C>).
"""

import os
import pty
import select
import struct
import subprocess
import sys
import time
import tty

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
WORKSPACE_ROOT = os.path.abspath(os.path.join(REPO_ROOT, "..", ".."))

EMU_BIN = os.path.join(WORKSPACE_ROOT, "tools", "rc2014_emu", "rc2014")
ROM_FILE = os.path.join(
    WORKSPACE_ROOT, "tools", "romwbw_src", "Binary", "RC2014_std.rom"
)
GOLDEN_IMG = os.path.join(
    WORKSPACE_ROOT, "tools", "romwbw_src", "Binary", "hd1k_combo.img"
)
IMG_DIR = os.path.join(REPO_ROOT, "disks")
IMG_FILE = os.path.join(IMG_DIR, "hd1k_combo.img")
if not os.path.isfile(IMG_FILE):
    os.makedirs(IMG_DIR, exist_ok=True)
    subprocess.run(
        ["cp", "--sparse=always", GOLDEN_IMG, IMG_FILE], check=True
    )
    os.chmod(IMG_FILE, 0o644)



def ensure_fat_test_image(img_file):
    target_size = 1837056 * 512
    if os.path.getsize(img_file) < target_size:
        with open(img_file, "a") as f:
            f.truncate(target_size)
        subprocess.run(
            ["/usr/sbin/mkfs.vfat", "-F", "16", "--offset=1050624",
             img_file, "393216"],
            check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
    part_offset = 1050624 * 512
    slices_content = (
        b"Slice 0: CP/M 2.2 System\r\n"
        b"Slice 1: Z-System / ZSDOS\r\n"
        b"Slice 2: NZ-COM Operating Environment\r\n"
        b"Slice 3: CP/M Plus (CP/M 3.0)\r\n"
        b"Slice 4: ZPM3 System\r\n"
        b"Slice 5: WordStar & Utilities\r\n"
    )
    with open(img_file, "r+b") as f:
        fat_entry_2 = struct.pack("<H", 0xFFFF)
        f.seek(part_offset + 16 * 512 + 4)
        f.write(fat_entry_2)
        f.seek(part_offset + (16 + 192) * 512 + 4)
        f.write(fat_entry_2)
        dirent = struct.pack(
            "<11sBBBHHHHHHHI",
            b"SLICES  TXT", 0x20, 0, 0, 0, 0, 0, 0, 0, 0, 2, len(slices_content)
        )
        f.seek(part_offset + 400 * 512)
        f.write(dirent)
        f.seek(part_offset + 432 * 512)
        f.write(slices_content)


def read_until(master_fd, match_bytes, timeout=10.0):
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
    return False, buf


def drain_all(master_fd, quiet_time=0.1):
    time.sleep(0.05)
    while True:
        r, _, _ = select.select([master_fd], [], [], quiet_time)
        if not r:
            break
        try:
            data = os.read(master_fd, 2048)
            if not data:
                break
        except (BlockingIOError, OSError):
            break


def send_cmd(master_fd, cmd):
    time.sleep(0.2)
    drain_all(master_fd)
    for ch in cmd:
        os.write(master_fd, ch.encode())
        time.sleep(0.03)
    os.write(master_fd, b"\r")


def main():
    if not os.path.exists(EMU_BIN):
        print(f"[-] Emulator binary not found: {EMU_BIN}")
        sys.exit(1)

    ensure_fat_test_image(IMG_FILE)

    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [EMU_BIN, "-b", "-r", ROM_FILE, "-1", "-S", IMG_FILE]
    proc = subprocess.Popen(
        cmd,
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
    )
    os.close(slave)

    try:
        print("[*] Launching RomWBW on RC2014 emulator (VFSTEST)...")
        # 1. Boot RomWBW CP/M
        ok, buf = read_until(master, b"Boot [H=Help]:", timeout=8.0)
        if not ok:
            print("[-] Failed to reach RomWBW boot loader prompt. Buffer:\n",
                  buf)
            sys.exit(1)

        time.sleep(0.5)
        os.write(master, b"c\r")
        ok, buf = read_until(master, b"B>", timeout=6.0)
        if not ok:
            print("[-] Failed to boot into CP/M prompt. Buffer:\n", buf)
            sys.exit(1)

        time.sleep(0.5)
        send_cmd(master, "c:")
        ok, buf = read_until(master, b"C>", timeout=8.0)
        if not ok:
            print("[-] Failed to switch to Drive C:. Buffer:\n", buf)
            sys.exit(1)
        print("[+] Switched to Drive C>.")

        # Launch VFSTEST.COM
        send_cmd(master, "vfstest")

        # Check for start of tests
        ok, buf = read_until(
            master, b"Starting FAT VFS Dispatcher Tests", timeout=25.0
        )
        if not ok:
            print("[-] Timed out waiting for VFSTEST to start. Buffer:\n", buf)
            sys.exit(1)
        print("[+] VFSTEST launched successfully.")

        # Wait for all tests to pass
        ok, buf = read_until(
            master,
            b"[+] ALL VFS TESTS PASSED SUCCESSFULLY!",
            timeout=20.0,
        )
        if not ok:
            print("[-] VFS tests did not pass. Output:\n",
                  buf.decode(errors="replace"))
            sys.exit(1)
        print("[+] Headless VFS test suite passed!")

        # Wait for return to CP/M prompt
        ok, buf = read_until(master, b">", timeout=8.0)
        if not ok:
            print("[-] Timed out waiting for CP/M prompt. Buffer:\n", buf)
            sys.exit(1)
        print(f"[+] Clean return to CP/M prompt verified: {repr(buf.strip())}")

        print("\n[+] FATFS Headless VFS Dispatcher Test PASSED!\n")

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            proc.kill()
        os.close(master)


if __name__ == "__main__":
    main()
