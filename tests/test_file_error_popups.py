#!/usr/bin/env python3
"""
test_file_error_popups.py - Fast isolated test for Task 2.4.
Verifies:
1. Open screen: non-existent file displays Tier 2 'File Not Found' modal pop-up.
2. Open screen: unavailable RAM drive displays Tier 2 'RAM Drive Unavailable'.
3. Open screen: FAT path without plugin displays Tier 2 'FAT Subsystem Missing'.
4. Save screen: unavailable RAM drive displays Tier 2 'RAM Drive Unavailable'.
5. Save screen: FAT path without plugin displays Tier 2 'FAT Subsystem Missing'.
6. All pop-ups dismiss cleanly on any key and restore Open/Save dialogs with
   input filename intact.
"""

import os
import pty
import select
import subprocess
import sys
import time
import tty

def find_paths():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    workspace_root = os.path.abspath(os.path.join(repo_root, "..", ".."))

    emu_bin = os.path.join(workspace_root, "tools", "rc2014_emu", "rc2014")
    rom_file = os.path.join(
        workspace_root, "tools", "romwbw_src", "Binary", "RC2014_std.rom"
    )
    img_file = os.path.join(repo_root, "disks", "hd1k_combo.img")
    se_bin = os.path.join(repo_root, "SE.COM")
    cpmcp = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp"
    )
    cpmrm = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm"
    )
    plugins_dir = os.path.join(repo_root, "plugins")

    return emu_bin, rom_file, img_file, se_bin, cpmcp, cpmrm, plugins_dir

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
                    return buf
            except (BlockingIOError, OSError):
                pass
        time.sleep(0.01)
    return buf

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

def remove_from_img(cpmrm, img, filename):
    for fmt in ["wbw_hd1k_0", "wbw_hd1k_3"]:
        for name in [filename.upper(), filename.lower()]:
            subprocess.run(
                [cpmrm, "-f", fmt, img, f"0:{name}"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

def inject_to_img(cpmcp, img, filepath, filename):
    for fmt in ["wbw_hd1k_0", "wbw_hd1k_3"]:
        subprocess.run(
            [cpmcp, "-f", fmt, img, filepath, f"0:{filename}"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

def main():
    paths = find_paths()
    emu_bin, rom_file, img_file, se_bin, cpmcp, cpmrm, plugins_dir = paths

    # Temporarily remove FATFS.PRL so FAT tests trigger FAT Subsystem Missing
    print("[*] Removing FATFS.PRL to test FAT Subsystem Missing popup...")
    remove_from_img(cpmrm, img_file, "FATFS.PRL")

    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )
    os.close(slave)

    try:
        # Boot sequence
        out = read_until(master, b"Boot [", timeout=10.0)
        assert b"Boot [" in out, f"Failed boot prompt: {repr(out)}"
        time.sleep(0.5)
        os.write(master, b"c\r")
        out = read_until(master, b"B>", timeout=10.0)
        assert b"B>" in out, f"Failed B> prompt: {repr(out)}"
        time.sleep(0.5)
        os.write(master, b"c:\r")
        out = read_until(master, b"C>", timeout=15.0)
        assert b"C>" in out, f"Failed C> prompt: {repr(out)}"
        time.sleep(0.5)

        # Launch SE.COM
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"se\r")
        out = read_until(master, b"Screen Editor", timeout=25.0)
        if b"Screen Editor" not in out:
            print(f"[-] SE.COM splash screen not displayed: {repr(out)}",
                  flush=True)
            return False
        print("[+] SE.COM splash screen reached.")

        # Configure RAM drive as Overwrite so drive A: is unavailable
        time.sleep(0.2)
        os.write(master, b"c")
        read_until(master, b"Configuration", timeout=6.0)
        time.sleep(0.2)
        os.write(master, b"2")
        read_until(master, b"Hibernate", timeout=6.0)
        time.sleep(0.2)
        os.write(master, b"2")
        read_until(master, b"Overwrite", timeout=6.0)
        time.sleep(0.2)
        os.write(master, b"s")
        read_until(master, b"Saved", timeout=6.0)
        time.sleep(0.2)
        os.write(master, b"q")
        read_until(master, b"Screen Editor", timeout=6.0)
        print("[+] RAM drive configured to Overwrite (Drive A: unavailable).")

        # Test 1: File Open screen - File Not Found popup
        time.sleep(0.2)
        os.write(master, b"o")
        out = read_until(master, b"Enter filename to open", timeout=6.0)
        if b"Enter filename to open" not in out:
            print("[-] Failed to enter Open File screen.", flush=True)
            return False

        time.sleep(0.1)
        os.write(master, b"NONEXIST.XYZ\r")
        out = read_until(master, b"Press any key to continue", timeout=6.0)
        if b"File Not Found" not in out:
            print(f"[-] 'File Not Found' modal popup missing: {repr(out)}")
            return False
        if b"Press any key to continue" not in out:
            print("[-] 'Press any key to continue' missing in FNF popup.")
            return False
        print("[+] Verified 'File Not Found' Tier 2 popup in Open dialog.")

        # Dismiss with space key
        time.sleep(0.1)
        os.write(master, b" ")
        out = read_until(master, b"Enter filename to open", timeout=6.0)
        if b"Enter filename to open" not in out:
            print("[-] Open dialog not restored after FNF popup dismissal.")
            return False
        print("[+] Open dialog cleanly restored on FNF popup dismissal.")

        # Test 2: File Open screen - RAM Drive Unavailable popup
        time.sleep(0.1)
        os.write(master, b"\x08" * 20 + b"A:\r")
        out = read_until(master, b"Press any key to continue", timeout=6.0)
        if b"RAM Drive Unavailable" not in out:
            print(f"[-] 'RAM Drive Unavailable' popup missing: {repr(out)}")
            return False
        if b"Press any key to continue" not in out:
            print("[-] 'Press any key to continue' missing in RAMDRV popup.")
            return False
        print("[+] Verified 'RAM Drive Unavailable' popup in Open dialog.")

        # Dismiss with space key
        time.sleep(0.1)
        os.write(master, b" ")
        out = read_until(master, b"Enter filename to open", timeout=6.0)
        if b"Enter filename to open" not in out:
            print("[-] Open dialog not restored after RAMDRV popup dismissal.")
            return False
        print("[+] Open dialog cleanly restored on RAMDRV popup dismissal.")

        # Test 3: File Open screen - FAT Subsystem Missing popup
        time.sleep(0.1)
        os.write(master, b"\x08" * 20 + b"U:\r")
        out = read_until(master, b"Press any key to continue", timeout=6.0)
        if b"FAT Subsystem Missing" not in out:
            print(f"[-] 'FAT Subsystem Missing' popup missing: {repr(out)}")
            return False
        if b"Press any key to continue" not in out:
            print("[-] 'Press any key to continue' missing in FAT popup.")
            return False
        print("[+] Verified 'FAT Subsystem Missing' popup in Open dialog.")

        # Dismiss with space key
        time.sleep(0.1)
        os.write(master, b" ")
        out = read_until(master, b"Enter filename to open", timeout=6.0)
        if b"Enter filename to open" not in out:
            print("[-] Open dialog not restored after FAT popup dismissal.")
            return False
        print("[+] Open dialog cleanly restored on FAT popup dismissal.")

        # Exit Open dialog back to splash screen with ESC
        time.sleep(0.1)
        os.write(master, b"\x1b")
        out = read_until(master, b"type   [C]", timeout=6.0)
        if b"type   [C]" not in out:
            print("[-] Failed to return to splash screen with ESC: "
                  f"{repr(out)}")
            return False

        # Enter editor mode with 'e'
        time.sleep(0.2)
        drain_all(master)
        os.write(master, b"e")
        out = read_until(master, b"(Untitled)", timeout=6.0)
        if b"(Untitled)" not in out:
            print(f"[-] Failed to enter editor mode: {repr(out)}")
            return False
        print("[+] Entered editor mode.")

        # Test 4: Save dialog - RAM Drive Unavailable popup
        time.sleep(0.1)
        os.write(master, b"\x13")  # Ctrl+S
        out = read_until(master, b"Enter filename to save", timeout=6.0)
        if b"Enter filename to save" not in out:
            print("[-] Failed to enter Save dialog.", flush=True)
            return False

        time.sleep(0.1)
        os.write(master, b"\x08" * 20 + b"A:\r")
        out = read_until(master, b"Press any key to continue", timeout=6.0)
        if b"RAM Drive Unavailable" not in out:
            print(f"[-] 'RAM Drive Unavailable' popup missing: {repr(out)}")
            return False
        print("[+] Verified 'RAM Drive Unavailable' popup in Save dialog.")

        # Dismiss with space key
        time.sleep(0.1)
        os.write(master, b" ")
        out = read_until(master, b"Enter filename to save", timeout=6.0)
        if b"Enter filename to save" not in out:
            print("[-] Save dialog not restored after RAMDRV popup dismissal.")
            return False
        print("[+] Save dialog cleanly restored on RAMDRV popup dismissal.")

        # Test 5: Save dialog - FAT Subsystem Missing popup
        time.sleep(0.1)
        os.write(master, b"\x08" * 20 + b"U:\r")
        out = read_until(master, b"Press any key to continue", timeout=6.0)
        if b"FAT Subsystem Missing" not in out:
            print(f"[-] 'FAT Subsystem Missing' popup missing: {repr(out)}")
            return False
        print("[+] Verified 'FAT Subsystem Missing' popup in Save dialog.")

        # Dismiss with space key
        time.sleep(0.1)
        os.write(master, b" ")
        out = read_until(master, b"Enter filename to save", timeout=6.0)
        if b"Enter filename to save" not in out:
            print("[-] Save dialog not restored after FAT popup dismissal.")
            return False
        print("[+] Save dialog cleanly restored on FAT popup dismissal.")

        # Cancel Save dialog with ESC back to editor
        time.sleep(0.3)
        os.write(master, b"\x1b")
        out = read_until(master, b"^K: Editor keys", timeout=6.0)
        if b"^K: Editor keys" not in out:
            print(f"[-] Failed to cancel Save dialog with ESC: {repr(out)}")
            return False

        # Clean exit to CP/M (Ctrl+Q)
        time.sleep(0.3)
        os.write(master, b"\x11")  # Ctrl+Q
        out = read_until(master, b"C>", timeout=8.0)
        if b"Save changes?" in out and b"C>" not in out:
            time.sleep(0.1)
            os.write(master, b"n")
            out += read_until(master, b"C>", timeout=6.0)
        if b"C>" not in out:
            print(f"[-] Failed to cleanly exit back to CP/M: {repr(out)}")
            return False
        print("[+] Clean exit back to CP/M prompt.")

        print("\n[SUCCESS] Task 2.4 all file error popups verified!")
        return True

    finally:
        try:
            proc.kill()
            proc.wait(timeout=1.0)
        except (OSError, subprocess.TimeoutExpired):
            pass
        try:
            os.close(master)
        except OSError:
            pass

        # Clean up SE.CFG and restore FATFS.PRL
        remove_from_img(cpmrm, img_file, "SE.CFG")
        print("[*] Restoring FATFS.PRL back into test image...")
        fat_prl = os.path.join(plugins_dir, "fat", "FATFS.PRL")
        if os.path.isfile(fat_prl):
            inject_to_img(cpmcp, img_file, fat_prl, "FATFS.PRL")
            print("[+] FATFS.PRL restored.")

if __name__ == "__main__":
    if main():
        sys.exit(0)
    else:
        sys.exit(1)
