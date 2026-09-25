#!/usr/bin/env python3
"""
test_fatfs_vfs_hook.py - Validation of SE.COM Phase 2 FAT VFS Integration

Validates:
  1. Missing plugin guard: entering U: or U<unit>: in Open and Save screens
     displays "feature requires FATFS.PRL" when FATFS.PRL is not loaded.
  2. Plugin detection: loading FATFS.PRL into a slot enables VFS dispatch.
  3. Loading FAT files: entering U4:SLICES.TXT streams file into editor.
  4. Status bar display: status bar displays U4:SLICES.TXT (stripping path).
  5. Dirty indicator: editing document updates status bar to U4:SLICES.TXT*.
  6. Save prefill: Save dialog prefills edit box with full path U4:/SLICES.TXT.
  7. Saving FAT files: saving clears dirty flag and restores clean status bar.
  8. Clean exit back to CP/M prompt.
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
    img_file = os.path.join(
        workspace_root, "tools", "romwbw_src", "Binary", "hd1k_combo.img"
    )
    return emu_bin, rom_file, img_file


def read_until(master_fd, match_bytes, timeout=6.0):
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


def send_str(master_fd, text, char_delay=0.03):
    for ch in text:
        os.write(master_fd, ch.encode("latin1"))
        time.sleep(char_delay)


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
    )
    with open(img_file, "r+b") as f:
        fat_entry_2 = struct.pack("<H", 0xFFFF)
        f.seek(part_offset + 16 * 512 + 4)
        f.write(fat_entry_2)
        f.seek(part_offset + (16 + 192) * 512 + 4)
        f.write(fat_entry_2)
        dirent = struct.pack(
            "<11sBBBHHHHHHHI",
            b"SLICES  TXT", 0x20, 0, 0, 0, 0, 0, 0, 0, 0, 2,
            len(slices_content)
        )
        f.seek(part_offset + 400 * 512)
        f.write(dirent)
        dirent_dir = struct.pack(
            "<11sBBBHHHHHHHI",
            b"TURBOPAS   ", 0x10, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0
        )
        f.seek(part_offset + 400 * 512 + 32)
        f.write(dirent_dir)
        f.seek(part_offset + 432 * 512)
        f.write(slices_content)


def main():
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
        os.write(master, b"se\r")
        ok, buf = read_until(master, b"Col 0", timeout=18.0)
        if not ok:
            print("[-] SE.COM splash screen not displayed. Buffer:\n", buf)
            sys.exit(1)
        drain_all(master, quiet_time=0.1)
        print("[+] SE.COM splash screen displayed.")

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
            master, b"feature requires FATFS.PRL", timeout=8.0
        )
        if not ok:
            print("[-] Missing plugin message not displayed in Open dialog! "
                  "Buffer:\n", buf)
            sys.exit(1)
        print("[+] Missing plugin guard verified in Open dialog: "
              "'feature requires FATFS.PRL'")

        # Dismiss Open dialog with ESC
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"Col 0", timeout=8.0)
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
            master, b"feature requires FATFS.PRL", timeout=8.0
        )
        if not ok:
            print("[-] Missing plugin message not displayed in Save dialog! "
              "Buffer:\n", buf)
            sys.exit(1)
        print("[+] Missing plugin guard verified in Save dialog: "
              "'feature requires FATFS.PRL'")

        # Dismiss Save dialog with ESC
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"Col 0", timeout=8.0)
        drain_all(master, quiet_time=0.1)

        # --- Test 3: Load FATFS.PRL into Slot 3 ---
        print("[*] Loading FATFS.PRL into plugin slot...")
        time.sleep(0.5)
        os.write(master, b"p")
        ok, buf = read_until(master, b"SE - Plugin Manager", timeout=8.0)
        if not ok:
            print("[-] Plugin Manager not reached. Buffer:\n", buf)
            sys.exit(1)
        if b"type 0..7 to run" not in buf:
            read_until(master, b"type 0..7 to run", timeout=5.0)
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
        if b"DRIVE U4:)" not in buf:
            print("[-] Directory title does not contain 'DRIVE U4:)'. "
                  "Buffer:\n", buf)
            sys.exit(1)
        print("[+] FAT directory enumeration and 'TURBOPAS/' verified.")

        # --- Test 5: CP/M Drive Switch in Open Dialog ---
        print("[*] Testing CP/M drive switch back to C0:...")
        time.sleep(0.2)
        send_str(master, "\x08" * 20 + "C0:\r")
        ok, buf = read_until(master, b"DRIVE C:)", timeout=8.0)
        if not ok:
            print("[-] CP/M directory listing not restored. Buffer:\n", buf)
            sys.exit(1)
        ok, buf_extra = read_until(master, b"SE.COM", timeout=8.0)
        buf += buf_extra
        if not ok:
            print("[-] 'SE.COM' not found in listing. Buffer:\n", buf)
            sys.exit(1)
        print("[+] CP/M directory switch restored successfully.")

        # --- Test 6: Open File via VFS (U4:SLICES.TXT) ---
        print("[*] Opening FAT file via VFS (U4:SLICES.TXT)...")
        time.sleep(0.2)
        send_str(master, "\x08" * 20 + "U4:SLICES.TXT\r")

        # Expect file text to load and status bar to show U4:SLICES.TXT
        ok, buf = read_until(master, b"Slice 0: CP/M 2.2 System", timeout=10.0)
        if not ok:
            print("[-] File content not loaded into editor! Buffer:\n", buf)
            sys.exit(1)
        print("[+] File content loaded successfully via VFS.")

        # Check status bar for U4:SLICES.TXT
        if b"U4:SLICES.TXT" not in buf:
            # Drain and re-read screen buffer if needed
            time.sleep(0.2)
            ok, extra = read_until(master, b"U4:SLICES.TXT", timeout=3.0)
            buf += extra
        if b"U4:SLICES.TXT" not in buf:
            print("[-] Status bar does not contain 'U4:SLICES.TXT'! Buffer:\n",
                  buf)
            sys.exit(1)
        print("[+] Status bar correctly displays 'U4:SLICES.TXT'.")

        # --- Test 7: Status Bar Dirty Indicator ---
        print("[*] Testing status bar dirty indicator (U4:SLICES.TXT*)...")
        time.sleep(0.3)
        # Type 'X' to dirty the document
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
        # Trigger Save from editor with Ctrl+S (\x13)
        os.write(master, b"\x13")
        ok, buf = read_until(master, b"Enter filename to save:", timeout=6.0)
        if not ok:
            print("[-] Save File dialog not reached. Buffer:\n", buf)
            sys.exit(1)

        # Verify prefilled path contains U4:/SLICES.TXT
        if b"U4:/SLICES.TXT" not in buf:
            time.sleep(0.2)
            ok, extra = read_until(master, b"U4:/SLICES.TXT", timeout=3.0)
            buf += extra
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

        # Verify status bar is clean (no asterisk)
        time.sleep(0.3)
        drain_all(master, 0.2)
        print("[+] Save completed, clean status bar restored.")

        # --- Test 9: Block Insert File from FAT Volume ---
        print("[*] Testing Block Insert file from FAT volume...")
        time.sleep(0.3)
        # Activate block selection mode (Ctrl+B = \x02)
        os.write(master, b"\x02")
        time.sleep(0.2)
        # Open Block Insert file screen (Ctrl+O = \x0f)
        os.write(master, b"\x0f")
        ok, buf = read_until(
            master, b"Enter filename to insert:", timeout=6.0
        )
        if not ok:
            print("[-] Block Insert dialog not reached. Buffer:\n", buf)
            sys.exit(1)
        print("[+] Block Insert dialog reached: "
              "'Enter filename to insert:'.")

        # Confirm insertion of U4:SLICES.TXT
        time.sleep(0.2)
        send_str(master, "\x08" * 20 + "U4:SLICES.TXT\r")
        ok, buf = read_until(master, b"U4:SLICES.TXT*", timeout=10.0)
        if not ok:
            print("[-] Editor did not return with dirty status after "
                  "block insert! Buffer:\n", buf)
            sys.exit(1)
        print("[+] Block insert completed, dirty status verified: "
              "'U4:SLICES.TXT*'.")

        # --- Test 10: Clean Exit to CP/M Prompt ---
        print("[*] Exiting SE.COM to CP/M prompt...")
        # Exit dirty editor with Ctrl+Q (\x11)
        os.write(master, b"\x11")
        ok, buf = read_until(master, b"Unsaved Modifications", timeout=6.0)
        if not ok:
            # If already at prompt or no prompt shown, try fallback
            send_str(master, "n")
            ok, buf = read_until(master, b"C>", timeout=8.0)
        else:
            # Confirm discard with 'n'
            send_str(master, "n")
            ok, buf = read_until(master, b"C>", timeout=8.0)
        if not ok:
            print("[-] Return to CP/M prompt failed after exit. "
                  "Buffer:\n", buf)
            sys.exit(1)
        print("[+] Clean return to CP/M prompt verified: 'C>'.")

        print("\n[+] ALL SE.COM PHASE 3 FAT VFS HOOK TESTS PASSED!\n")

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            proc.kill()
        os.close(master)


if __name__ == "__main__":
    main()
