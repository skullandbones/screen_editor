#!/usr/bin/env python3
"""
test_fatfs_vfs_hook.py - Validation of SE.COM Phase 4 FAT VFS Integration

Validates:
  1. Missing plugin guard in Open and Save screens without FATFS.PRL.
  2. Plugin detection and loading into Far RAM.
  3. FAT drive switch & directory enumeration (U4:).
  4. Subdirectory navigation: descent (TURBOPAS/) and ascent (..).
  5. FAT directory wildcard filtering (*.PAS preserving subdirectories).
  6. CP/M drive switch and return to FAT volume.
  7. Implied FAT volume context: opening bare filename (SLICES.TXT).
  8. Status bar display (U4:SLICES.TXT) and dirty indicator (*).
  9. Save dialog prefill with full path (U4:/SLICES.TXT).
  10. Block file insertion from FAT volume.
  11. Clean exit back to CP/M prompt (C>).
  12. Command-line FAT auto-load (se U4:SLICES.TXT).
  13. Command-line FAT subdirectory auto-load (se U4:/TURBOPAS/HELLO.PAS).
"""

import os
import pty
import select
import struct
import subprocess
import sys
import time


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
    return emu_bin, rom_file, img_file


def read_until(master_fd, match_bytes, timeout=6.0, buf=b""):
    if match_bytes in buf:
        return True, buf
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


def send_str(master_fd, text, char_delay=0.03):
    for ch in text:
        os.write(master_fd, ch.encode("latin1"))
        time.sleep(char_delay)


def ensure_fat_test_image(img_file):
    target_size = 1837056 * 512
    if os.path.getsize(img_file) < target_size:
        with open(img_file, "a") as f:
            f.truncate(target_size)
    part_offset = 1050624 * 512
    slices_content = (
        b"Slice 0: CP/M 2.2 System\r\n"
        b"Slice 1: Z-System / ZSDOS\r\n"
        b"Slice 2: NZ-COM Operating Environment\r\n"
        b"Slice 3: CP/M Plus (CP/M 3.0)\r\n"
    )
    hello_content = (
        b"PROGRAM Hello;\r\n"
        b"BEGIN\r\n"
        b"  WriteLn('Hello from FAT!');\r\n"
        b"END.\r\n"
    )
    vbr = bytearray(512)
    vbr[0:3] = b"\xeb\x3c\x90"
    vbr[3:11] = b"MSDOS5.0"
    struct.pack_into("<H", vbr, 11, 512)
    vbr[13] = 8
    struct.pack_into("<H", vbr, 14, 16)
    vbr[16] = 2
    struct.pack_into("<H", vbr, 17, 512)
    struct.pack_into("<H", vbr, 19, 0)
    vbr[21] = 0xF8
    struct.pack_into("<H", vbr, 22, 192)
    struct.pack_into("<H", vbr, 24, 63)
    struct.pack_into("<H", vbr, 26, 255)
    struct.pack_into("<I", vbr, 28, 1050624)
    struct.pack_into("<I", vbr, 32, 393216)
    vbr[36] = 0x80
    vbr[38] = 0x29
    struct.pack_into("<I", vbr, 39, 0x12345678)
    vbr[43:54] = b"NO NAME    "
    vbr[54:62] = b"FAT16   "
    vbr[510:512] = b"\x55\xaa"

    with open(img_file, "r+b") as f:
        f.seek(part_offset)
        f.write(vbr)
        fat_init = struct.pack("<HH", 0xFFF8, 0xFFFF)
        f.seek(part_offset + 16 * 512)
        f.write(fat_init)
        f.seek(part_offset + (16 + 192) * 512)
        f.write(fat_init)
        fat_eof = struct.pack("<H", 0xFFFF)
        for clus in (2, 3, 4):
            f.seek(part_offset + 16 * 512 + clus * 2)
            f.write(fat_eof)
            f.seek(part_offset + (16 + 192) * 512 + clus * 2)
            f.write(fat_eof)

        # Clear root directory
        f.seek(part_offset + 400 * 512)
        f.write(b"\x00" * 1024)

        # Root directory entries: SLICES.TXT and TURBOPAS/
        dirent = struct.pack(
            "<11sBBBHHHHHHHI",
            b"SLICES  TXT", 0x20, 0, 0, 0, 0, 0, 0, 0, 0, 2,
            len(slices_content),
        )
        dirent_dir = struct.pack(
            "<11sBBBHHHHHHHI",
            b"TURBOPAS   ", 0x10, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0,
        )
        f.seek(part_offset + 400 * 512)
        f.write(dirent)
        f.write(dirent_dir)

        # Cluster 2: SLICES.TXT
        f.seek(part_offset + 432 * 512)
        f.write(slices_content + b"\x00" * (512 - len(slices_content)))

        # Cluster 3: TURBOPAS/ directory (., .., HELLO.PAS)
        f.seek(part_offset + 440 * 512)
        f.write(b"\x00" * 512)
        dot_ent = struct.pack(
            "<11sBBBHHHHHHHI",
            b".          ", 0x10, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0,
        )
        dotdot_ent = struct.pack(
            "<11sBBBHHHHHHHI",
            b"..         ", 0x10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        )
        hello_ent = struct.pack(
            "<11sBBBHHHHHHHI",
            b"HELLO   PAS", 0x20, 0, 0, 0, 0, 0, 0, 0, 0, 4,
            len(hello_content),
        )
        f.seek(part_offset + 440 * 512)
        f.write(dot_ent)
        f.write(dotdot_ent)
        f.write(hello_ent)

        # Cluster 4: HELLO.PAS
        f.seek(part_offset + 448 * 512)
        f.write(hello_content + b"\x00" * (512 - len(hello_content)))



def main(use_sec=False):
    target_name = "SEC.COM" if use_sec else "SE.COM"
    cmd_name = b"sec" if use_sec else b"se"
    emu_bin, rom_file, img_file = find_paths()
    if not os.path.exists(emu_bin):
        print(f"[-] Emulator binary not found: {emu_bin}")
        sys.exit(1)

    ensure_fat_test_image(img_file)

    master, slave = os.openpty()
    import tty
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )
    os.close(slave)

    try:
        print("[*] Booting RomWBW CP/M on RC2014 emulator...")
        ok, buf = read_until(master, b"Boot [H=Help]:", timeout=8.0)
        if not ok:
            print("[-] RomWBW boot prompt not reached. Buffer:\n", buf)
            sys.exit(1)

        time.sleep(0.5)
        os.write(master, b"c\r")
        ok, buf = read_until(master, b"B>", timeout=6.0)
        if not ok:
            print("[-] CP/M prompt not reached. Buffer:\n", buf)
            sys.exit(1)

        time.sleep(0.5)
        send_str(master, "c:\r")
        ok, buf = read_until(master, b"C>", timeout=8.0)
        if not ok:
            print("[-] Failed to switch to Drive C>. Buffer:\n", buf)
            sys.exit(1)
        print("[+] Switched to Drive C>.")

        # Launch fresh SE.COM without plugins loaded
        time.sleep(0.5)
        os.write(master, cmd_name + b"\r")
        ok, buf = read_until(master, b"Col 0", timeout=45.0)
        if not ok:
            print(
                f"[-] {target_name} splash screen not displayed. "
                f"Buffer:\n", buf
            )
            sys.exit(1)
        drain_all(master, quiet_time=0.1)
        print(f"[+] {target_name} splash screen displayed.")

        # --- Test 1: Missing Plugin Guard in Open Dialog ---
        print("[*] Testing missing plugin guard in Open File dialog...")
        time.sleep(0.5)
        os.write(master, b"o")
        ok, buf = read_until(master, b"Enter filename to open:", timeout=8.0)
        if not ok:
            print("[-] Open File dialog not reached. Buffer:\n", buf)
            sys.exit(1)

        # Enter U2:TEST.TXT without FATFS.PRL loaded (clear prefilled C0:)
        time.sleep(0.2)
        send_str(master, "\x08" * 20 + "U2:TEST.TXT\r")
        ok, buf = read_until(
            master, b"requires FATFS.PRL", timeout=8.0
        )
        if not ok:
            print("[-] Missing plugin message not displayed in Open dialog! "
                  "Buffer:\n", buf)
            sys.exit(1)
        print("[+] Missing plugin guard verified in Open dialog: "
              "'feature requires FATFS.PRL'")

        # Dismiss popup with Space, then dismiss Open dialog with ESC
        time.sleep(0.3)
        os.write(master, b" ")
        time.sleep(0.3)
        os.write(master, b"\x1b")
        read_until(master, b"to save file", timeout=10.0)
        drain_all(master, quiet_time=0.1)

        # --- Test 2: Missing Plugin Guard in Save Dialog ---
        print("[*] Testing missing plugin guard in Save File dialog...")
        time.sleep(0.5)
        os.write(master, b"s")
        ok, buf = read_until(master, b"Enter filename to save:", timeout=8.0)
        if not ok:
            print("[-] Save File dialog not reached. Buffer:\n", buf)
            sys.exit(1)

        time.sleep(0.2)
        send_str(master, "\x08" * 20 + "U4:OUTPUT.TXT\r")
        ok, buf = read_until(
            master, b"requires FATFS.PRL", timeout=8.0
        )
        if not ok:
            print("[-] Missing plugin message not displayed in Save dialog! "
              "Buffer:\n", buf)
            sys.exit(1)
        print("[+] Missing plugin guard verified in Save dialog: "
              "'feature requires FATFS.PRL'")

        # Dismiss popup with Space, then dismiss Save dialog with ESC
        time.sleep(0.3)
        os.write(master, b" ")
        time.sleep(0.3)
        os.write(master, b"\x1b")
        read_until(master, b"to save file", timeout=10.0)
        drain_all(master, quiet_time=0.1)

        # --- Test 3: Load FATFS.PRL into Slot 3 ---
        print("[*] Loading FATFS.PRL into plugin slot...")
        time.sleep(0.5)
        os.write(master, b"p")
        ok, buf = read_until(master, b"SE - Plugin Manager", timeout=8.0)
        if not ok:
            print("[-] Plugin Manager not reached. Buffer:\n", buf)
            sys.exit(1)
        if b"0..7:select" not in buf:
            read_until(master, b"0..7:select", timeout=5.0)
        drain_all(master, quiet_time=0.1)
        time.sleep(0.3)
        drain_all(master, quiet_time=0.1)
        os.write(master, b"l")
        ok, buf = read_until(master, b"Load Plugin", timeout=6.0)
        if not ok:
            print("[-] Load Plugin prompt not reached. Buffer:\n", buf)
            sys.exit(1)

        time.sleep(0.1)
        send_str(master, "\x08" * 20 + "FATFS.PRL\r")
        ok, buf = read_until(master, b"FAR (32KB)", timeout=20.0)
        if not ok or b"FATFS" not in buf:
            print("[-] FATFS not loaded in Plugin Manager. Buffer:\n", buf)
            sys.exit(1)
        print("[+] FATFS.PRL loaded successfully into plugin slot.")
        drain_all(master, quiet_time=0.1)

        # Return to splash screen ('q' exits Plugin Manager)
        time.sleep(0.3)
        os.write(master, b"q")
        read_until(master, b"Col 0", timeout=8.0)
        drain_all(master, quiet_time=0.1)

        # --- Test 4: FAT Drive Switch & Directory Enumeration ---
        print("[*] Testing FAT drive switch in Open dialog (U4:)...")
        time.sleep(0.5)
        os.write(master, b"o")
        ok, buf = read_until(master, b"Enter filename to open:", timeout=8.0)
        if not ok:
            print("[-] Open File dialog not reached. Buffer:\n", buf)
            sys.exit(1)

        time.sleep(0.2)
        send_str(master, "\x08" * 20 + "U4:\r")
        ok, buf = read_until(master, b"TURBOPAS/", timeout=8.0)
        if not ok:
            print("[-] Subdirectory 'TURBOPAS/' not found in listing. "
                  "Buffer:\n", buf)
            sys.exit(1)
        if b"SLICES.TXT" not in buf:
            print("[-] File 'SLICES.TXT' not found in listing. Buffer:\n",
                  buf)
            sys.exit(1)
        if b"DRIVE U4:/)" not in buf:
            print("[-] Directory title does not contain 'DRIVE U4:/)'. "
                  "Buffer:\n", buf)
            sys.exit(1)
        print("[+] FAT directory enumeration and 'TURBOPAS/' verified.")

        # --- Test 4b: Subdirectory Navigation (Descent & Ascent) ---
        print("[*] Testing subdirectory descent into TURBOPAS/...")
        time.sleep(0.2)
        send_str(master, "\x08" * 20 + "TURBOPAS/\r")
        ok, buf = read_until(master, b"DRIVE U4:/TURBOPAS/)", timeout=8.0)
        if not ok:
            print("[-] Title does not contain 'DRIVE U4:/TURBOPAS/)'. "
                  "Buffer:\n", buf)
            sys.exit(1)
        ok, buf = read_until(master, b"../", timeout=6.0, buf=buf)
        if not ok:
            print("[-] Parent link '../' not found in TURBOPAS/. Buffer:\n",
                  buf)
            sys.exit(1)
        ok, buf = read_until(master, b"HELLO.PAS", timeout=6.0, buf=buf)
        if not ok:
            print("[-] 'HELLO.PAS' not found in TURBOPAS/. Buffer:\n", buf)
            sys.exit(1)
        print("[+] Subdirectory descent verified: 'DRIVE U4:/TURBOPAS/)'.")

        # --- Test 4c: Subdirectory Ascent via '..' ---
        print("[*] Testing subdirectory ascent via '..'...")
        time.sleep(0.2)
        send_str(master, "\x08" * 20 + "..\r")
        ok, buf = read_until(master, b"DRIVE U4:/)", timeout=8.0)
        if not ok:
            print("[-] Directory title does not restore 'DRIVE U4:/)'. "
                  "Buffer:\n", buf)
            sys.exit(1)
        ok, buf = read_until(master, b"TURBOPAS/", timeout=6.0, buf=buf)
        if not ok:
            print("[-] 'TURBOPAS/' not found after '..'. Buffer:\n", buf)
            sys.exit(1)
        ok, buf = read_until(master, b"SLICES.TXT", timeout=6.0, buf=buf)
        if not ok:
            print("[-] 'SLICES.TXT' not found after '..'. Buffer:\n", buf)
            sys.exit(1)
        print("[+] Subdirectory ascent verified: 'DRIVE U4:/)' restored.")

        # --- Test 4d: FAT Directory Wildcard Filtering ---
        print("[*] Testing FAT directory wildcard filter (*.PAS)...")
        time.sleep(0.2)
        send_str(master, "\x08" * 20 + "*.PAS\r")
        ok, buf = read_until(master, b"[*.PAS]", timeout=8.0)
        if not ok:
            print("[-] Filter indicator '[*.PAS]' not in title. Buffer:\n",
                  buf)
            sys.exit(1)
        ok, buf = read_until(master, b"TURBOPAS/", timeout=6.0, buf=buf)
        if not ok:
            print("[-] Subdirectory 'TURBOPAS/' filtered out! Buffer:\n", buf)
            sys.exit(1)
        drain_all(master, quiet_time=0.2)
        if b"SLICES.TXT" in buf:
            print("[-] 'SLICES.TXT' was not filtered by '*.PAS'. Buffer:\n",
                  buf)
            sys.exit(1)
        print("[+] Wildcard filter (*.PAS) verified (directory preserved).")

        # Reset filter with *.*
        time.sleep(0.2)
        send_str(master, "\x08" * 20 + "*.*\r")
        ok, buf = read_until(master, b"SLICES.TXT", timeout=8.0)
        if not ok:
            print("[-] 'SLICES.TXT' not restored after filter reset. "
                  "Buffer:\n", buf)
            sys.exit(1)
        print("[+] Wildcard filter reset (*.*) verified.")

        # --- Test 5: CP/M Drive Switch in Open Dialog ---
        print("[*] Testing CP/M drive switch back to C0:...")
        time.sleep(0.2)
        send_str(master, "\x08" * 20 + "C0:\r")
        ok, buf = read_until(master, b"DRIVE C:)", timeout=8.0)
        if not ok:
            print("[-] CP/M directory listing not restored. Buffer:\n", buf)
            sys.exit(1)
        ok, buf = read_until(master, b"ED.COM", timeout=8.0, buf=buf)
        if not ok:
            print("[-] 'ED.COM' not found in listing. Buffer:\n", buf)
            sys.exit(1)
        print("[+] CP/M directory switch restored successfully.")

        # --- Test 5b: Switch back to FAT Drive U4: ---
        print("[*] Switching back to FAT volume U4:...")
        time.sleep(0.2)
        send_str(master, "\x08" * 20 + "U4:\r")
        ok, buf = read_until(master, b"DRIVE U4:/)", timeout=8.0)
        if not ok:
            print("[-] Switch back to U4: failed. Buffer:\n", buf)
            sys.exit(1)
        ok, buf = read_until(master, b"SLICES.TXT", timeout=6.0, buf=buf)
        if not ok:
            print("[-] 'SLICES.TXT' not found on U4:. Buffer:\n", buf)
            sys.exit(1)
        ok, buf = read_until(
            master, b"Enter filename to open:", timeout=6.0, buf=buf
        )
        if not ok:
            print("[-] Prompt not reached on U4:. Buffer:\n", buf)
            sys.exit(1)
        print("[+] Active FAT volume U4: restored.")

        # --- Test 6: Implied FAT File Open (Bare Filename SLICES.TXT) ---
        print("[*] Opening bare FAT filename (SLICES.TXT)...")
        time.sleep(0.3)
        send_str(master, "\x08" * 20 + "SLICES.TXT\r")

        # Expect file text to load and status bar to show U4:SLICES.TXT
        ok, buf = read_until(master, b"Slice 0: CP/M 2.2 System", timeout=10.0)
        if not ok:
            print("[-] File content not loaded into editor! Buffer:\n", buf)
            sys.exit(1)
        print("[+] File content loaded successfully via implied FAT context.")

        # Check status bar for U4:SLICES.TXT
        ok, buf = read_until(master, b"U4:SLICES.TXT", timeout=3.0, buf=buf)
        if b"U4:SLICES.TXT" not in buf:
            print("[-] Status bar does not contain 'U4:SLICES.TXT'! Buffer:\n",
                  buf)
            sys.exit(1)
        print("[+] Status bar correctly displays 'U4:SLICES.TXT'.")

        # --- Test 7: Status Bar Dirty Indicator ---
        print("[*] Testing status bar dirty indicator (U4:SLICES.TXT*)...")
        time.sleep(0.3)
        send_str(master, "X")
        ok, buf = read_until(master, b"U4:SLICES.TXT*", timeout=4.0)
        if not ok:
            print("[-] Status bar did not show dirty indicator '*'! "
                  "Buffer:\n", buf)
            sys.exit(1)
        print("[+] Status bar dirty indicator verified: 'U4:SLICES.TXT*'.")

        # --- Test 8: Save Dialog Path Prefill ---
        print("[*] Testing Save dialog prefill with full FAT path...")
        time.sleep(0.3)
        os.write(master, b"\x13")
        ok, buf = read_until(master, b"Enter filename to save:", timeout=6.0)
        if not ok:
            print("[-] Save File dialog not reached. Buffer:\n", buf)
            sys.exit(1)

        ok, buf = read_until(master, b"U4:/SLICES.TXT", timeout=3.0, buf=buf)
        if b"U4:/SLICES.TXT" not in buf:
            print("[-] Save dialog did not prefill 'U4:/SLICES.TXT'! "
                  "Buffer:\n", buf)
            sys.exit(1)
        print("[+] Save dialog prefilled with full path: 'U4:/SLICES.TXT'.")

        # Press Enter to confirm save
        send_str(master, "\r")
        ok, buf = read_until(master, b"U4:SLICES.TXT", timeout=6.0)
        if not ok:
            print("[-] Editor did not restore after save. Buffer:\n", buf)
            sys.exit(1)

        time.sleep(0.3)
        drain_all(master, 0.2)
        print("[+] Save completed, clean status bar restored.")

        # --- Test 9: Block Insert File from FAT Volume ---
        print("[*] Testing Block Insert file from FAT volume...")
        time.sleep(0.3)
        os.write(master, b"\x02")
        time.sleep(0.2)
        os.write(master, b"\x0f")
        ok, buf = read_until(
            master, b"Enter filename to insert:", timeout=6.0
        )
        if not ok:
            print("[-] Block Insert dialog not reached. Buffer:\n", buf)
            sys.exit(1)
        print("[+] Block Insert dialog reached: 'Enter filename to insert:'.")

        # Confirm insertion of bare SLICES.TXT (implied context)
        time.sleep(0.2)
        send_str(master, "\x08" * 20 + "SLICES.TXT\r")
        ok, buf = read_until(master, b"U4:SLICES.TXT*", timeout=10.0)
        if not ok:
            print("[-] Editor did not return with dirty status after "
                  "block insert! Buffer:\n", buf)
            sys.exit(1)
        print("[+] Block insert completed, dirty status verified: "
              "'U4:SLICES.TXT*'.")
        if b"Slice 1: Z-System / ZSDOS" not in buf:
            print("[-] Inserted file content not found in editor buffer! "
                  "Buffer:\n", buf)
            sys.exit(1)
        print("[+] Verified inserted FAT file content present in editor.")

        # --- Test 10: Clean Exit to CP/M Prompt ---
        print("[*] Exiting SE.COM to CP/M prompt...")
        time.sleep(0.2)
        os.write(master, b"\x11")
        ok, buf = read_until(master, b"Save changes?", timeout=6.0)
        if not ok:
            print("[-] 'Save changes?' dialog not reached. Buffer:\n", buf)
            sys.exit(1)
        os.write(master, b"n")
        ok, buf = read_until(master, b"C>", timeout=6.0)
        if not ok:
            print("[-] Return to CP/M prompt failed after exit. "
                  "Buffer:\n", buf)
            sys.exit(1)
        print("[+] Clean return to CP/M prompt verified: 'C>'.")
        drain_all(master, 0.2)

        # --- Test 11: Command-Line FAT Auto-Load ---
        print("[*] Testing command-line FAT auto-load (se U4:SLICES.TXT)...")
        time.sleep(0.5)
        send_str(master, "se U4:SLICES.TXT\r")
        ok, buf = read_until(
            master, b"Slice 0: CP/M 2.2 System", timeout=50.0
        )
        if not ok:
            print("[-] Command-line FAT auto-load failed. Buffer:\n", buf)
            sys.exit(1)
        ok, buf = read_until(master, b"U4:SLICES.TXT", timeout=4.0, buf=buf)
        if b"U4:SLICES.TXT" not in buf:
            print("[-] Status bar does not contain 'U4:SLICES.TXT'! "
                  "Buffer:\n", buf)
            sys.exit(1)
        print("[+] Command-line FAT auto-load verified: 'se U4:SLICES.TXT'.")

        # Exit clean editor with Ctrl+Q
        time.sleep(0.2)
        os.write(master, b"\x11")
        ok, buf = read_until(master, b"C>", timeout=6.0)
        if not ok:
            print("[-] Exit to CP/M failed after CLI test. Buffer:\n", buf)
            sys.exit(1)
        print("[+] Clean exit from CLI session back to 'C>'.")
        drain_all(master, 0.2)

        # --- Test 12: Command-Line FAT Subdirectory Auto-Load ---
        print("[*] Testing command-line FAT subdir auto-load "
              "(se U4:/TURBOPAS/HELLO.PAS)...")
        time.sleep(0.5)
        send_str(master, "se U4:/TURBOPAS/HELLO.PAS\r")
        ok, buf = read_until(master, b"Hello from FAT!", timeout=50.0)
        if not ok:
            print("[-] CLI FAT subdir auto-load failed. Buffer:\n", buf)
            sys.exit(1)
        ok, buf = read_until(master, b"U4:HELLO.PAS", timeout=4.0, buf=buf)
        if b"U4:HELLO.PAS" not in buf:
            print("[-] Status bar does not contain 'U4:HELLO.PAS'! "
                  "Buffer:\n", buf)
            sys.exit(1)
        print("[+] Subdirectory auto-load verified: "
              "'se U4:/TURBOPAS/HELLO.PAS'.")

        # Exit clean editor with Ctrl+Q
        time.sleep(0.2)
        os.write(master, b"\x11")
        ok, buf = read_until(master, b"C>", timeout=6.0)
        if not ok:
            print("[-] Exit to CP/M failed after CLI subdir test. "
                  "Buffer:\n", buf)
            sys.exit(1)
        print("[+] Clean exit from subdir CLI session back to 'C>'.")

        print("\n[+] ALL SE.COM PHASE 4 FAT VFS TESTS PASSED!\n")

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            proc.kill()
        os.close(master)


if __name__ == "__main__":
    use_sec_arg = "--sec" in sys.argv
    main(use_sec=use_sec_arg)
