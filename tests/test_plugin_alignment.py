#!/usr/bin/env python3
"""
Validates the visual column alignment of the SE.COM Plugin Manager table
in RomWBW on the RC2014 emulator.
"""

import os
import sys
import time
import tty
import select
import subprocess
import re

script_dir = os.path.dirname(os.path.abspath(__file__))
repo_root = os.path.dirname(script_dir)
workspace_root = os.path.abspath(os.path.join(repo_root, "..", ".."))

emu_bin = os.path.join(workspace_root, "tools", "rc2014_emu", "rc2014")
rom_file = os.path.join(workspace_root, "tools", "romwbw_src", "Binary", "RC2014_std.rom")
img_file = os.path.join(workspace_root, "tools", "romwbw_src", "Binary", "hd1k_combo.img")

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

def main():
    print("[*] Launching emulator to verify Plugin Manager column alignment...")
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)

    try:
        read_until(master, b"Boot [H=Help]:", timeout=6.0)
        time.sleep(0.5)
        os.write(master, b"c\r")
        read_until(master, b"B>", timeout=6.0)
        time.sleep(0.5)
        os.write(master, b"c:\r")
        read_until(master, b"C>", timeout=8.0)
        time.sleep(0.5)
        os.write(master, b"se\r")
        read_until(master, b"Col 0", timeout=18.0)
        drain_all(master)

        time.sleep(0.5)
        os.write(master, b"p")
        ok, out = read_until(master, b"type 0..7 to run", timeout=10.0)
        
        # Capture screen text
        text = out.decode("latin1", errors="replace")
        # Clean escape sequences
        clean = re.sub(r"\x1b\[[0-9;]*[a-zA-Z]", "\n", text)
        clean = re.sub(r"\x1b\[\?[0-9]+[hl]", "", clean)
        lines = [l.strip() for l in clean.splitlines() if l.strip()]

        print("\n--- [Captured Plugin Manager Table Lines] ---")
        table_lines = []
        for l in lines:
            if any(k in l for k in ["Slot", "----+", "[0]", "[1]", "[2]", "[3]", "[4]"]):
                table_lines.append(l)
                print(f"| {l} |")
        print("---------------------------------------------")

        # Exit cleanly
        time.sleep(0.3)
        os.write(master, b"q")
        time.sleep(0.5)
        os.write(master, b"q")
        time.sleep(0.5)

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=1.0)
        except Exception:
            pass
        os.close(master)

if __name__ == "__main__":
    main()
