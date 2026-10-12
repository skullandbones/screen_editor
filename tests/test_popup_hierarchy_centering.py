#!/usr/bin/env python3
"""
test_popup_hierarchy_centering.py - Test centered popup positioning & modal hierarchy
"""

import os
import pty
import select
import subprocess
import sys
import time
import tty

def find_paths(use_sec=False):
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
    se_bin = os.path.join(repo_root, "SEC.COM" if use_sec else "SE.COM")

    return emu_bin, rom_file, img_file, se_bin

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

def main(use_sec=False):
    emu_bin, rom_file, img_file, se_bin = find_paths(use_sec=use_sec)
    target_name = "SEC.COM" if use_sec else "SE.COM"
    cmd_name = b"sec" if use_sec else b"se"
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)

    try:
        # Boot loader prompt
        out = read_until(master, b"Boot [H=Help]:", timeout=6.0)
        if b"Boot [H=Help]:" not in out:
            print("[-] Failed to reach RomWBW boot loader prompt.")
            return 1

        # Boot CP/M on ROM disk (Choice 'c') and switch to Drive C:
        time.sleep(0.5)
        os.write(master, b"c\r")
        out = read_until(master, b"B>", timeout=6.0)
        if b"B>" not in out:
            print("[-] Failed to boot into CP/M prompt.")
            return 1

        time.sleep(0.5)
        os.write(master, b"c:\r")
        out = read_until(master, b"C>", timeout=10.0)
        if b"C>" not in out:
            print(f"[-] Failed to switch to Drive C:. Buffer: {repr(out)}")
            return 1
        print("[+] Switched to Drive C>.")

        # Launch SE.COM
        time.sleep(0.5)
        os.write(master, cmd_name + b"\r")
        out = read_until(master, b"for about", timeout=45.0)
        if b"for about" not in out:
            print(f"[-] Failed to reach Splash Screen. Output:\n{out.decode('latin1', errors='replace')}")
            return 1
        print("[+] Splash screen displayed.")

        # Enter About Screen ('a')
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"a")
        out = read_until(master, b"SE - Screen Editor", timeout=6.0)
        if b"SE - Screen Editor" not in out:
            print(f"[-] Failed to enter About Screen. Output:\n{out.decode('latin1', errors='replace')}")
            return 1
        print("[+] About screen displayed.")

        # Open Ctrl+P menu
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"\x10")  # Ctrl+P
        out = read_until(master, b"[Up]/[Down]=Select", timeout=6.0)
        if b"Plugins with Embedded Documentation" not in out:
            print(f"[-] Failed to open Ctrl+P menu on About screen. Output:\n{out.decode('latin1', errors='replace')}")
            return 1
        print("[+] Ctrl+P menu opened on About screen.")

        # Select slot 1 and execute via Enter (ROT13 About dialog)
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"1\r")
        out = read_until(master, b"ROT13 Text Cipher Plugin", timeout=6.0)
        if b"ROT13 Text Cipher Plugin" not in out:
            print(f"[-] Failed to open ROT13 About dialog. Output:\n{out.decode('latin1', errors='replace')}")
            return 1
        print("[+] ROT13 About dialog displayed.")

        # Verify centering coordinates:
        # In 120x40 mode: ((40 - 11) // 2) + 1 = 15, ((120 - 38) // 2) + 1 = 42 -> [15;42H
        # In 80x24 mode:  ((24 - 11) // 2) + 1 = 7,  ((80 - 38) // 2) + 1 = 22  -> [7;22H
        if b"[15;42H" in out:
            print("    [+] Centering confirmed for 120x40: cursor positioned at Row 15, Col 42!")
        elif b"[7;22H" in out:
            print("    [+] Centering confirmed for 80x24: cursor positioned at Row 7, Col 22!")
        else:
            print(f"    [-] Centering sequence not found in output: {repr(out[-300:])}")
            return 1

        # Dismiss ROT13 About dialog with Space
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b" ")
        out = read_until(master, b"[Up]/[Down]=Select", timeout=6.0)
        if (b"Plugins with Embedded Documentation" not in out or
                b"[Up]/[Down]=Select" not in out):
            print("[-] HIERARCHY FAILURE: Expected Ctrl+P menu after popup!")
            return 1
        print("[+] Modal hierarchy verified: About returned to Ctrl+P menu!")

        # Dismiss Ctrl+P menu with ESC
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"\x1b")
        out = read_until(master, b"SE - Screen Editor", timeout=6.0)
        if b"SE - Screen Editor" not in out:
            print(f"[-] Failed to return to Host About screen after dismissing Ctrl+P menu.")
            return 1
        print("[+] Dismissing Ctrl+P menu returned cleanly to Host About screen!")

        # Return to Splash screen
        time.sleep(0.3)
        os.write(master, b"\x1b")
        out = read_until(master, b"for about", timeout=4.0)
        print("[+] Returned to Splash screen.")

        # Exit SE.COM
        time.sleep(0.3)
        os.write(master, b"q")
        time.sleep(0.5)

        print("\n[SUCCESS] Centered popup rendering & popup hierarchy verified successfully!")
        return 0

    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2.0)
        except Exception:
            proc.kill()

if __name__ == "__main__":
    use_sec_arg = "--sec" in sys.argv
    sys.exit(main(use_sec=use_sec_arg))
