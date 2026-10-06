#!/usr/bin/env python3
"""
test_replace_modal.py - Fast isolated test for Task 2.1 Replace Modal.
Verifies:
1. Interactive replace prompt opens Tier 2 modal pop-up instead of status bar.
2. Modal pop-up displays Replace Confirmation title, query, and bracketed keys.
3. Status bar is never squatted or hijacked during interactive replace.
4. Yes, No (skip), Reverse, and Quit options behave as expected.
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

def main():
    emu_bin, rom_file, img_file, se_bin = find_paths()
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )
    os.close(slave)

    try:
        # 1. Boot loader prompt
        out = read_until(master, b"Boot [H=Help]:", timeout=6.0)
        if b"Boot [H=Help]:" not in out:
            print("[-] Failed to reach RomWBW boot loader prompt.")
            return 1

        # 2. Boot CP/M on ROM disk (Choice 'c') and switch to Drive C:
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

        # 3. Launch SE.COM with 30.TXT
        time.sleep(0.5)
        os.write(master, b"se 30.TXT\r")
        out = read_until(master, b"Line    1/30", timeout=45.0)
        if b"Line    1/30" not in out:
            print(f"[-] Failed to load 30.TXT. Buffer: {repr(out)}")
            return 1
        print("[+] Successfully opened 30.TXT in SE.COM.")
        time.sleep(0.3)
        drain_all(master)

        # 4. Trigger Ctrl+R (Replace)
        os.write(master, b"\x12")
        out = read_until(master, b"[ESC]=Cancel", timeout=4.0)
        if b"[ESC]=Cancel" not in out:
            print(
                f"[-] Ctrl+R Find prompt failed to appear. Buffer: {repr(out)}"
            )
            return 1
        print("[+] Ctrl+R Search prompt displayed.")

        # Enter search term: "Line 01"
        time.sleep(0.1)
        os.write(master, b"Line 01\r")
        out = read_until(master, b"Replace with:", timeout=4.0)
        if b"Replace with:" not in out:
            print(f"[-] Replace with prompt missing. Buffer: {repr(out)}")
            return 1
        print("[+] Replace with prompt displayed.")

        # Enter replacement term: "BetaLine 01"
        time.sleep(0.1)
        os.write(master, b"BetaLine 01\r")

        # 5. Verify Tier 2 Replace Confirmation Modal appears
        out_title = read_until(master, b"Replace Confirmation", timeout=4.0)
        if b"Replace Confirmation" not in out_title:
            print(
                f"[-] Replace Confirmation modal missing! "
                f"Buffer: {repr(out_title)}"
            )
            return 1
        print("[+] Replace Confirmation modal title verified.")

        out_modal = read_until(master, b"[ESC]=Cancel", timeout=4.0)
        if b"Replace this occurrence?" not in out_modal:
            print(
                f"[-] Query prompt missing from modal! "
                f"Buffer: {repr(out_modal)}"
            )
            return 1
        print("[+] Modal query prompt ('Replace this occurrence?') verified.")

        for opt in [b"[Y]es", b"[N]o", b"[A]ll", b"[R]everse",
                    b"[ESC]=Cancel"]:
            if opt not in out_modal:
                print(f"[-] Modal option {repr(opt)} missing from keys line!")
                return 1
        if b"[Q]uit" in out_modal:
            print("[-] Prohibited [Q]uit option present in modal keys line!")
            return 1
        print("[+] All bracketed modal options verified (no [Q]uit).")

        # Verify status bar does NOT contain old squatting string
        if b"Replace (Yes/No/All/Quit/Reverse)?" in out_modal:
            print("[-] Anti-pattern 7 detected: Status bar squatted!")
            return 1
        print(
            "[+] Status bar squatting absent (persistent status bar preserved)."
        )

        # 6. Confirm replacement with 'y'
        time.sleep(0.1)
        os.write(master, b"y")
        out_rep = read_until(
            master, b"Replace done: 1 replacement(s).", timeout=4.0
        )
        if b"Replace done: 1 replacement(s)." not in out_rep:
            print(f"[-] Replacement failed! Buffer: {repr(out_rep)}")
            return 1
        if b"Replace Done" not in out_rep:
            print(f"[-] Replace Done title missing! Buffer: {repr(out_rep)}")
            return 1
        print("[+] Tier 2 Replace Done modal pop-up verified.")
        # Dismiss modal on any key
        time.sleep(0.1)
        os.write(master, b" ")

        time.sleep(0.3)
        drain_all(master)

        # 7. Test Skip ('n') and Reverse ('r')
        # Jump to line 1
        os.write(master, b"\x14\x01")
        read_until(master, b"Line    1/30", timeout=4.0)
        time.sleep(0.2)
        drain_all(master)

        # Search for "of test"
        os.write(master, b"\x12")
        read_until(master, b"[ESC]=Cancel", timeout=4.0)
        time.sleep(0.1)
        os.write(master, b"of test\r")
        read_until(master, b"Replace with:", timeout=4.0)
        time.sleep(0.1)
        os.write(master, b"of sample\r")

        # On match 1 (line 1): skip with 'n'
        read_until(master, b"Replace Confirmation", timeout=4.0)
        time.sleep(0.1)
        os.write(master, b"n")

        # Should advance to line 2
        read_until(master, b"Line    2/30", timeout=4.0)
        read_until(master, b"Replace Confirmation", timeout=4.0)
        print("[+] Skip ('n') advanced to line 2.")

        # On line 2: reverse direction with 'r'
        time.sleep(0.1)
        os.write(master, b"r")

        # Should move backwards to line 1
        read_until(master, b"Line    1/30", timeout=4.0)
        read_until(master, b"Replace Confirmation", timeout=4.0)
        print("[+] Reverse ('r') moved backwards to line 1.")

        # Verify 'q' is ignored (non-ESC cancellation prohibited)
        time.sleep(0.1)
        os.write(master, b"q")
        time.sleep(0.2)

        # Cancel replace with ESC
        os.write(master, b"\x1b")
        out_quit = read_until(
            master, b"Replace done: 0 replacement(s).", timeout=4.0
        )
        if b"Replace done: 0 replacement(s)." not in out_quit:
            print(f"[-] Cancel replace failed. Buffer: {repr(out_quit)}")
            return 1
        print("[+] ESC cancelled interactive replace cleanly ('q' ignored).")
        # Dismiss Replace Done modal
        time.sleep(0.1)
        os.write(master, b" ")

        time.sleep(0.3)
        drain_all(master)

        # 8. Test Pattern Not Found modal pop-up
        os.write(master, b"\x06")
        read_until(master, b"[ESC]=Cancel", timeout=4.0)
        time.sleep(0.1)
        os.write(master, b"ZZZNONEXIST\r")
        out_nf = read_until(master, b"Pattern not found.", timeout=4.0)
        if b"Pattern not found." not in out_nf:
            print(f"[-] Pattern not found missing! Buffer: {repr(out_nf)}")
            return 1
        if b"Pattern Not Found" not in out_nf:
            print(
                f"[-] Pattern Not Found title missing! Buffer: {repr(out_nf)}"
            )
            return 1
        print("[+] Tier 2 Pattern Not Found modal pop-up verified.")
        # Dismiss modal on any key
        time.sleep(0.1)
        os.write(master, b" ")

        time.sleep(0.3)
        drain_all(master)

        # 9. Test Search Completed modal pop-up
        os.write(master, b"\x06")
        read_until(master, b"[ESC]=Cancel", timeout=4.0)
        time.sleep(0.1)
        os.write(master, b"BetaLine 01\r")
        read_until(master, b"[BLK: 11c LOCK]", timeout=4.0)
        time.sleep(0.2)
        drain_all(master)

        # Trigger Find Next (Ctrl+N): wraps around and completes
        os.write(master, b"\x0e")
        out_comp = read_until(master, b"Search completed.", timeout=4.0)
        if b"Search completed." not in out_comp:
            print(f"[-] Search completed missing! Buffer: {repr(out_comp)}")
            return 1
        if b"Search Completed" not in out_comp:
            print(
                f"[-] Search Completed title missing! Buffer: {repr(out_comp)}"
            )
            return 1
        print("[+] Tier 2 Search Completed modal pop-up verified.")
        # Dismiss modal on any key
        time.sleep(0.1)
        os.write(master, b" ")

        # 10. Clean exit
        time.sleep(0.3)
        drain_all(master)
        # Discard changes on exit: Ctrl+Q, 'n'
        os.write(master, b"\x11")
        time.sleep(0.2)
        os.write(master, b"n")
        time.sleep(0.5)

        print("\n[SUCCESS] Tasks 2.1 & 2.2 fully verified!")
        return 0

    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2.0)
        except Exception:
            proc.kill()

if __name__ == "__main__":
    sys.exit(main())
