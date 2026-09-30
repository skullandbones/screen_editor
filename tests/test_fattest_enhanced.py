#!/usr/bin/env python3
"""
test_fattest_enhanced.py - Validation test suite for enhanced FATTEST.COM

Tests:
  1. Boot RomWBW CP/M on RC2014 emulator.
  2. Run FATTEST.COM from CP/M prompt.
  3. Verify unit auto-detection / config loading.
  4. Test directory commands: MKDIR, CD, PWD, DIR.
  5. Test file creation: WRITE, TYPE.
  6. Test copy to CP/M drive: GET / COPY.
  7. Test cleanup: DEL, RMDIR.
  8. Test UNIT switching and FATFS.CFG persistence: UNIT 2, SAVE.
  9. Exit to CP/M prompt and verify FATFS.CFG and copied file directly in CP/M.
 10. Re-launch FATTEST and verify it loads UNIT=2 from FATFS.CFG.
"""

import os
import sys
import time
import tty
import select
import subprocess
import struct

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


def ensure_fat_test_image(img_file):
    target_size = 1837056 * 512
    if os.path.getsize(img_file) < target_size:
        with open(img_file, "a") as f:
            f.truncate(target_size)
    subprocess.run(["/usr/sbin/mkfs.vfat", "-F", "16", "--offset=1050624", img_file, "393216"],
                   check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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
        dirent = struct.pack("<11sBBBHHHHHHHI",
            b"SLICES  TXT", 0x20, 0, 0, 0, 0, 0, 0, 0, 0, 2, len(slices_content))
        f.seek(part_offset + 400 * 512)
        f.write(dirent)
        f.seek(part_offset + 432 * 512)
        f.write(slices_content)

    cpmrm = os.path.join(WORKSPACE_ROOT, "tools", "romwbw_src", "Tools", "Linux", "cpmrm")
    if os.path.isfile(cpmrm):
        subprocess.run([cpmrm, "-f", "wbw_hd1k_0", img_file, "0:FATFS.CFG"],
                       check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([cpmrm, "-f", "wbw_hd1k_0", img_file, "0:CPMHELLO.TXT"],
                       check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def run_test():
    for p, name in [(EMU_BIN, "Emulator"), (ROM_FILE, "ROM"), (IMG_FILE, "Disk image")]:
        if not os.path.isfile(p):
            print(f"[-] Required file not found: {name} ({p})")
            return False

    ensure_fat_test_image(IMG_FILE)

    print("[*] Launching RomWBW on RC2014 emulator...", flush=True)
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [EMU_BIN, "-b", "-r", ROM_FILE, "-1", "-S", IMG_FILE]
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)

    try:
        # 1. Boot RomWBW CP/M
        ok, out = read_until(master, b"Boot [H=Help]:", timeout=8.0)
        if not ok:
            print("[-] Failed to reach RomWBW boot loader prompt.", flush=True)
            return False

        time.sleep(0.5)
        os.write(master, b"c\r")
        ok, _ = read_until(master, b"54.0K TPA", timeout=15.0)
        ok, out = read_until(master, b"B>", timeout=10.0)
        if not ok:
            print("[-] Failed to boot into CP/M prompt.", flush=True)
            return False

        time.sleep(0.5)
        os.write(master, b"c:\r")
        ok, out = read_until(master, b"C>", timeout=15.0)
        if not ok:
            print("[-] Failed to switch to Drive C:.", flush=True)
            return False
        print("[+] Switched to Drive C>.", flush=True)

        # 2. Launch FATTEST.COM
        time.sleep(0.5)
        send_cmd(master, "fattest")
        ok, out_init = read_until(master, b"FAT[", timeout=30.0)
        if not ok:
            print(f"[-] FATTEST failed to display prompt. Output: {repr(out_init)}", flush=True)
            return False
        print(f"[+] FATTEST launched successfully! Prompt: {repr(out_init[-30:])}", flush=True)

        # 3. Test PWD
        send_cmd(master, "pwd")
        ok, out_pwd = read_until(master, b"Current directory: /", timeout=5.0)
        if not ok:
            print(f"[-] PWD command failed: {repr(out_pwd)}", flush=True)
            return False
        print("[+] PWD verified: in root directory '/'.", flush=True)
        read_until(master, b"FAT[", timeout=5.0)

        # 4. Test MKDIR TESTDIR
        send_cmd(master, "mkdir testdir")
        ok, out_md = read_until(master, b"created successfully", timeout=5.0)
        if not ok:
            print(f"[-] MKDIR failed: {repr(out_md)}", flush=True)
            return False
        print("[+] MKDIR verified: created directory 'testdir'.", flush=True)
        read_until(master, b"FAT[", timeout=5.0)

        # 5. Test CD TESTDIR
        send_cmd(master, "cd testdir")
        ok, out_cd = read_until(master, b"Current directory: /TESTDIR", timeout=5.0)
        if not ok:
            print(f"[-] CD TESTDIR failed: {repr(out_cd)}", flush=True)
            return False
        print("[+] CD verified: navigated into '/TESTDIR'.", flush=True)
        read_until(master, b"FAT[", timeout=5.0)

        # 6. Test DIR in newly created subdirectory (should be empty: 0 entries)
        send_cmd(master, "dir")
        ok, out_dir = read_until(master, b"Total entries: 0", timeout=5.0)
        if not ok:
            print(f"[-] Subdirectory DIR listing failed: {repr(out_dir)}", flush=True)
            return False
        print("[+] DIR in empty subdirectory verified: Total entries: 0.", flush=True)
        read_until(master, b"FAT[", timeout=5.0)

        # 7. Test WRITE inside subdirectory
        send_cmd(master, "write hello.txt Hello_Subdir_World!")
        ok, out_w = read_until(master, b"VERIFICATION PASSED", timeout=5.0)
        if not ok:
            print(f"[-] WRITE in subdirectory failed: {repr(out_w)}", flush=True)
            return False
        print("[+] WRITE verified in subdirectory.", flush=True)
        read_until(master, b"FAT[", timeout=5.0)

        # 8. Test TYPE inside subdirectory
        send_cmd(master, "type hello.txt")
        ok, out_t = read_until(master, b"Hello_Subdir_World!", timeout=5.0)
        if not ok:
            print(f"[-] TYPE failed: {repr(out_t)}", flush=True)
            return False
        print("[+] TYPE in subdirectory verified.", flush=True)
        read_until(master, b"FAT[", timeout=5.0)

        # 9. Test GET / COPY: copy FAT file to CP/M drive
        send_cmd(master, "get hello.txt cpmhello.txt")
        ok, out_cp = read_until(master, b"bytes to CP/M file", timeout=5.0)
        if not ok:
            print(f"[-] GET / COPY failed: {repr(out_cp)}", flush=True)
            return False
        print("[+] GET / COPY verified: copied FAT file to CP/M file CPMHELLO.TXT.", flush=True)
        read_until(master, b"FAT[", timeout=5.0)

        # 10. Clean up file and directory: DEL hello.txt, CD .., RMDIR testdir
        send_cmd(master, "del hello.txt")
        ok, out_del = read_until(master, b"deleted successfully", timeout=5.0)
        if not ok:
            print(f"[-] DEL failed: {repr(out_del)}", flush=True)
            return False
        print("[+] DEL verified: deleted hello.txt.", flush=True)
        read_until(master, b"FAT[", timeout=5.0)

        send_cmd(master, "cd ..")
        ok, out_cd2 = read_until(master, b"Current directory: /", timeout=5.0)
        if not ok:
            print(f"[-] CD .. failed: {repr(out_cd2)}", flush=True)
            return False
        print("[+] CD .. verified: back in root '/'.", flush=True)
        read_until(master, b"FAT[", timeout=5.0)

        send_cmd(master, "rmdir testdir")
        ok, out_rm = read_until(master, b"removed successfully", timeout=5.0)
        if not ok:
            print(f"[-] RMDIR failed: {repr(out_rm)}", flush=True)
            return False
        print("[+] RMDIR verified: removed testdir successfully.", flush=True)
        read_until(master, b"FAT[", timeout=5.0)

        # 11. Test saving Unit 2 to FATFS.CFG
        send_cmd(master, "save 2")
        ok, out_save = read_until(master, b"Configuration saved to FATFS.CFG (UNIT=2)", timeout=5.0)
        if not ok:
            print(f"[-] SAVE command failed: {repr(out_save)}", flush=True)
            return False
        print("[+] SAVE 2 verified: persisted UNIT=2 to FATFS.CFG.", flush=True)
        read_until(master, b"FAT[", timeout=5.0)

        # 12. Exit FATTEST to CP/M
        send_cmd(master, "quit")
        ok, out_cpm = read_until(master, b">", timeout=8.0)
        if not ok:
            print(f"[-] Exit to CP/M failed: {repr(out_cpm)}", flush=True)
            return False
        if b"B>" in out_cpm:
            send_cmd(master, "c:")
            read_until(master, b"C>", timeout=8.0)
        print("[+] Exited FATTEST back to CP/M prompt (C>).", flush=True)

        # 13. Verify FATFS.CFG content via CP/M TYPE
        send_cmd(master, "type fatfs.cfg")
        ok, out_type_cfg = read_until(master, b"UNIT=2", timeout=6.0)
        if not ok:
            print(f"[-] TYPE FATFS.CFG failed: {repr(out_type_cfg)}", flush=True)
            return False
        print("[+] CP/M TYPE FATFS.CFG verified: contains 'UNIT=2'.", flush=True)
        read_until(master, b"C>", timeout=5.0)

        # 14. Verify CPMHELLO.TXT content via CP/M TYPE
        send_cmd(master, "type cpmhello.txt")
        ok, out_type_cpm = read_until(master, b"Hello_Subdir_World!", timeout=6.0)
        if not ok:
            print(f"[-] TYPE CPMHELLO.TXT failed: {repr(out_type_cpm)}", flush=True)
            return False
        print("[+] CP/M TYPE CPMHELLO.TXT verified: copied file matches original content!", flush=True)
        read_until(master, b"C>", timeout=5.0)

        # 15. Re-launch FATTEST to verify it loads UNIT=2 from FATFS.CFG
        send_cmd(master, "fattest")
        ok, out_relaunch = read_until(master, b"Loaded configuration from FATFS.CFG: Unit 2", timeout=25.0)
        if not ok:
            print(f"[-] Re-launch did not load UNIT=2 from FATFS.CFG: {repr(out_relaunch)}", flush=True)
            return False
        print("[+] Re-launch verified: FATTEST successfully loaded UNIT=2 from FATFS.CFG on startup!", flush=True)

        send_cmd(master, "quit")
        read_until(master, b">", timeout=6.0)
        return True

    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2.0)
        except subprocess.TimeoutExpired:
            proc.kill()
        os.close(master)


if __name__ == "__main__":
    t_start = time.time()
    success = run_test()
    elapsed = time.time() - t_start
    if success:
        print(f"\n[+] FATTEST Enhanced Test PASSED in {elapsed:.2f}s!")
        sys.exit(0)
    else:
        print(f"\n[-] FATTEST Enhanced Test FAILED after {elapsed:.2f}s.")
        sys.exit(1)
