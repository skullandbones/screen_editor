#!/usr/bin/env python3
"""
compare_cpm_linux.py - Parallel Comparison of SE.COM (CP/M) and se-linux.

Runs SE.COM in the RC2014 CP/M emulator and se-linux in a Linux PTY in parallel.
Applies identical input sequences to both and compares screen layouts, status
bars, Tier 1 centering/tildes, Tier 2 modal dialogs, and key behaviors against
UI_UX_DESIGN.md.
"""

import os
import pty
import re
import select
import subprocess
import sys
import time
import tty


class VirtualTerminal:
    """Simulates an 80x24 ANSI/VT100 terminal grid."""

    def __init__(self, rows=24, cols=80):
        self.rows = rows
        self.cols = cols
        self.grid = [[" " for _ in range(cols)] for _ in range(rows)]
        self.inv = [[False for _ in range(cols)] for _ in range(rows)]
        self.row = 0
        self.col = 0
        self.inverse = False

    def clear_screen(self):
        self.grid = [[" " for _ in range(self.cols)] for _ in range(self.rows)]
        self.inv = [
            [False for _ in range(self.cols)] for _ in range(self.rows)
        ]
        self.row = 0
        self.col = 0

    def clear_eol(self):
        if 0 <= self.row < self.rows:
            for c in range(self.col, self.cols):
                self.grid[self.row][c] = " "
                self.inv[self.row][c] = False

    def feed(self, data: bytes):
        text = data.decode("latin-1", errors="replace")
        i = 0
        n = len(text)
        while i < n:
            ch = text[i]
            if ch == "\x1b":
                if i + 1 < n and text[i + 1] == "[":
                    m = re.match(r"^\x1b\[([0-9;?]*)([A-Za-z])", text[i:])
                    if m:
                        params = m.group(1)
                        cmd = m.group(2)
                        i += len(m.group(0))
                        self._handle_csi(params, cmd)
                        continue
                    else:
                        i += 2
                        continue
                elif i + 1 < n and text[i + 1] in ("=", ">", "(", ")"):
                    i += 2
                    continue
                else:
                    i += 1
                    continue
            elif ch == "\r":
                self.col = 0
                i += 1
            elif ch == "\n":
                if self.row + 1 < self.rows:
                    self.row += 1
                i += 1
            elif ch == "\b":
                if self.col > 0:
                    self.col -= 1
                i += 1
            elif ch == "\t":
                self.col = min(self.cols - 1, (self.col + 8) & ~7)
                i += 1
            elif ord(ch) >= 32:
                if 0 <= self.row < self.rows and 0 <= self.col < self.cols:
                    self.grid[self.row][self.col] = ch
                    self.inv[self.row][self.col] = self.inverse
                    self.col += 1
                i += 1
            else:
                i += 1

    def _handle_csi(self, params: str, cmd: str):
        if cmd in ("H", "f"):
            parts = params.split(";") if params else []
            r = int(parts[0]) if len(parts) > 0 and parts[0] else 1
            c = int(parts[1]) if len(parts) > 1 and parts[1] else 1
            self.row = max(0, min(self.rows - 1, r - 1))
            self.col = max(0, min(self.cols - 1, c - 1))
        elif cmd == "J":
            if params in ("", "2"):
                self.clear_screen()
        elif cmd == "K":
            self.clear_eol()
        elif cmd == "m":
            parts = params.split(";") if params else ["0"]
            for p in parts:
                val = int(p) if p else 0
                if val == 0:
                    self.inverse = False
                elif val == 7:
                    self.inverse = True
                elif val == 27:
                    self.inverse = False
        elif cmd == "A":
            n = int(params) if params else 1
            self.row = max(0, self.row - n)
        elif cmd == "B":
            n = int(params) if params else 1
            self.row = min(self.rows - 1, self.row + n)
        elif cmd == "C":
            n = int(params) if params else 1
            self.col = min(self.cols - 1, self.col + n)
        elif cmd == "D":
            n = int(params) if params else 1
            self.col = max(0, self.col - n)

    def get_line(self, r: int) -> str:
        if 0 <= r < self.rows:
            return "".join(self.grid[r])
        return ""

    def get_screen_text(self) -> str:
        return "\n".join("".join(row) for row in self.grid)


def find_paths():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    workspace_root = os.path.abspath(os.path.join(repo_root, "..", ".."))

    emu_bin = os.path.join(workspace_root, "tools", "rc2014_emu", "rc2014")
    rom_file = os.path.join(
        workspace_root, "tools", "romwbw_src", "Binary", "RC2014_std.rom"
    )
    img_file = os.path.join(repo_root, "disks", "hd1k_combo.img")
    se_linux_bin = os.path.join(repo_root, "se-linux")

    return emu_bin, rom_file, img_file, se_linux_bin


def read_until_match(fd, match_bytes, timeout=10.0):
    buf = b""
    t0 = time.time()
    while time.time() - t0 < timeout:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                data = os.read(fd, 2048)
                if not data:
                    break
                buf += data
                if match_bytes in buf:
                    return buf
            except (BlockingIOError, OSError):
                pass
    return buf


def drain(fd, quiet_time=0.1, max_wait=2.0):
    chunks = []
    t0 = time.time()
    time.sleep(0.05)
    while time.time() - t0 < max_wait:
        r, _, _ = select.select([fd], [], [], quiet_time)
        if not r:
            break
        try:
            data = os.read(fd, 4096)
            if not data:
                break
            chunks.append(data)
        except (BlockingIOError, OSError):
            break
    return b"".join(chunks)


def run_comparison():
    emu_bin, rom_file, img_file, se_linux_bin = find_paths()

    print("[*] Launching CP/M RC2014 emulator...", flush=True)
    cpm_master, cpm_slave = os.openpty()
    tty.setraw(cpm_slave)
    os.set_blocking(cpm_master, False)

    cpm_cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    cpm_proc = subprocess.Popen(
        cpm_cmd, stdin=cpm_slave, stdout=cpm_slave, stderr=cpm_slave,
        close_fds=True
    )
    os.close(cpm_slave)

    lin_master, lin_slave = None, None
    lin_proc = None

    try:
        # Boot CP/M
        out = read_until_match(cpm_master, b"Boot [H=Help]:", timeout=8.0)
        assert b"Boot [H=Help]:" in out, "Failed RomWBW boot"
        time.sleep(0.5)
        os.write(cpm_master, b"c\r")
        out = read_until_match(cpm_master, b"B>", timeout=8.0)
        assert b"B>" in out, "Failed CP/M B> boot"
        time.sleep(0.5)
        os.write(cpm_master, b"c:\r")
        out = read_until_match(cpm_master, b"C>", timeout=10.0)
        assert b"C>" in out, "Failed switch to Drive C>"
        drain(cpm_master, quiet_time=0.1, max_wait=1.0)
        print("[+] CP/M prompt C> ready.", flush=True)

        print("[*] Launching se-linux native PTY...", flush=True)
        lin_master, lin_slave = pty.openpty()
        tty.setraw(lin_slave)
        os.set_blocking(lin_master, False)

        lin_cmd = [se_linux_bin]
        lin_proc = subprocess.Popen(
            lin_cmd, stdin=lin_slave, stdout=lin_slave, stderr=lin_slave,
            close_fds=True
        )
        os.close(lin_slave)
        lin_slave = None
        print("[+] se-linux native process started.", flush=True)

        vt_cpm = VirtualTerminal(rows=24, cols=80)
        vt_lin = VirtualTerminal(rows=24, cols=80)

        # Launch SE.COM
        print("[*] Launching SE.COM on CP/M...", flush=True)
        time.sleep(0.3)
        os.write(cpm_master, b"se\r")
        cpm_splash_raw = read_until_match(cpm_master, b"for about",
                                          timeout=25.0)
        cpm_splash_raw += drain(cpm_master, quiet_time=0.2, max_wait=2.0)
        lin_splash_raw = drain(lin_master, quiet_time=0.2, max_wait=2.0)

        # Step 1: Compare Splash Screen
        print("\n" + "=" * 78, flush=True)
        print("STEP 1: Initial Launch & Splash Screen Comparison", flush=True)
        print("=" * 78, flush=True)
        vt_cpm.feed(cpm_splash_raw)
        vt_lin.feed(lin_splash_raw)

        print("--- CP/M SE.COM Splash (Rows 1-5 & 24) ---", flush=True)
        for r in range(5):
            print(f"Row {r+1:2d}: {vt_cpm.get_line(r)}", flush=True)
        print(f"Row 24: {vt_cpm.get_line(23)}", flush=True)

        print("\n--- Linux se-linux Splash (Rows 1-5 & 24) ---", flush=True)
        for r in range(5):
            print(f"Row {r+1:2d}: {vt_lin.get_line(r)}", flush=True)
        print(f"Row 24: {vt_lin.get_line(23)}", flush=True)

        # Step 2: Switch to 80x24 on CP/M (press '2')
        print("\n" + "=" * 78, flush=True)
        print("STEP 2: Geometry Mode Switch on CP/M (Option '2' -> 80x24)",
              flush=True)
        print("=" * 78, flush=True)
        os.write(cpm_master, b"2")
        time.sleep(0.5)
        cpm_data = drain(cpm_master, quiet_time=0.2, max_wait=2.0)
        vt_cpm.clear_screen()
        vt_cpm.feed(cpm_data)
        print("--- CP/M SE.COM in 80x24 Mode (Row 24) ---", flush=True)
        print(f"Row 24: {vt_cpm.get_line(23)}", flush=True)

        # Step 3: Enter Editor Mode ('e')
        print("\n" + "=" * 78, flush=True)
        print("STEP 3: Enter Editor Mode (Input: 'e')", flush=True)
        print("=" * 78, flush=True)
        os.write(cpm_master, b"e")
        os.write(lin_master, b"e")
        time.sleep(0.5)
        cpm_data = read_until_match(cpm_master, b"^K: Editor keys", timeout=6.0)
        cpm_data += drain(cpm_master, quiet_time=0.2, max_wait=2.0)
        lin_data = drain(lin_master, quiet_time=0.2, max_wait=2.0)
        vt_cpm.clear_screen()
        vt_cpm.feed(cpm_data)
        vt_lin.clear_screen()
        vt_lin.feed(lin_data)

        print("--- CP/M SE.COM Editor Viewport ---", flush=True)
        print(f"Row  1: {vt_cpm.get_line(0)}", flush=True)
        print(f"Row  2: {vt_cpm.get_line(1)}", flush=True)
        print(f"Row 23: {vt_cpm.get_line(22)}", flush=True)
        print(f"Row 24: {vt_cpm.get_line(23)}", flush=True)

        print("\n--- Linux se-linux Editor Viewport ---", flush=True)
        print(f"Row  1: {vt_lin.get_line(0)}", flush=True)
        print(f"Row  2: {vt_lin.get_line(1)}", flush=True)
        print(f"Row 23: {vt_lin.get_line(22)}", flush=True)
        print(f"Row 24: {vt_lin.get_line(23)}", flush=True)

        # Step 4: Text Input
        print("\n" + "=" * 78, flush=True)
        print("STEP 4: Text Input ('PARALLEL TEST 123')", flush=True)
        print("=" * 78, flush=True)
        test_str = b"PARALLEL TEST 123"
        os.write(cpm_master, test_str)
        os.write(lin_master, test_str)
        time.sleep(0.5)
        cpm_data = drain(cpm_master, quiet_time=0.2, max_wait=2.0)
        lin_data = drain(lin_master, quiet_time=0.2, max_wait=2.0)
        vt_cpm.feed(cpm_data)
        vt_lin.feed(lin_data)

        print(f"CP/M  Row  1: {vt_cpm.get_line(0)}", flush=True)
        print(f"CP/M  Row 24: {vt_cpm.get_line(23)}", flush=True)
        print(f"Linux Row  1: {vt_lin.get_line(0)}", flush=True)
        print(f"Linux Row 24: {vt_lin.get_line(23)}", flush=True)

        # Step 5: ANSI Arrow Navigation
        print("\n" + "=" * 78, flush=True)
        print("STEP 5: ANSI Arrow Navigation (Left x3, Right x1, Home Ctrl+A)",
              flush=True)
        print("=" * 78, flush=True)
        # ANSI Left: \x1b[D x 3, ANSI Right: \x1b[C x 1, Home: \x01
        ansi_nav = b"\x1b[D\x1b[D\x1b[D\x1b[C\x01"
        os.write(cpm_master, ansi_nav)
        os.write(lin_master, ansi_nav)
        time.sleep(0.5)
        cpm_data = drain(cpm_master, quiet_time=0.2, max_wait=2.0)
        lin_data = drain(lin_master, quiet_time=0.2, max_wait=2.0)
        vt_cpm.feed(cpm_data)
        vt_lin.feed(lin_data)

        print(f"CP/M  Row 24: {vt_cpm.get_line(23)}", flush=True)
        print(f"Linux Row 24: {vt_lin.get_line(23)}", flush=True)

        # Step 6: Block Selection Mode (Ctrl+B)
        print("\n" + "=" * 78, flush=True)
        print("STEP 6: Block Selection Mode (Ctrl+B)", flush=True)
        print("=" * 78, flush=True)
        os.write(cpm_master, b"\x02")
        os.write(lin_master, b"\x02")
        time.sleep(0.5)
        cpm_data = drain(cpm_master, quiet_time=0.2, max_wait=2.0)
        lin_data = drain(lin_master, quiet_time=0.2, max_wait=2.0)
        vt_cpm.feed(cpm_data)
        vt_lin.feed(lin_data)

        print(f"CP/M  Row 24 (Block On) : {vt_cpm.get_line(23)}", flush=True)
        print(f"Linux Row 24 (Block On) : {vt_lin.get_line(23)}", flush=True)

        # Cancel Block Mode
        os.write(cpm_master, b"\x02")
        os.write(lin_master, b"\x02")
        time.sleep(0.3)
        drain(cpm_master, quiet_time=0.1, max_wait=1.0)
        drain(lin_master, quiet_time=0.1, max_wait=1.0)

        # Step 7: Help Screen (Ctrl+K)
        print("\n" + "=" * 78, flush=True)
        print("STEP 7: Help Workspace (Ctrl+K)", flush=True)
        print("=" * 78, flush=True)
        os.write(cpm_master, b"\x0b")
        os.write(lin_master, b"\x0b")
        time.sleep(0.5)
        cpm_data = read_until_match(cpm_master, b"continue", timeout=5.0)
        cpm_data += drain(cpm_master, quiet_time=0.2, max_wait=2.0)
        lin_data = drain(lin_master, quiet_time=0.2, max_wait=2.0)
        vt_cpm.clear_screen()
        vt_cpm.feed(cpm_data)
        vt_lin.clear_screen()
        vt_lin.feed(lin_data)

        print("--- CP/M Help Screen (Rows 1-5 & 24) ---", flush=True)
        for r in range(5):
            print(f"Row {r+1:2d}: {vt_cpm.get_line(r)}", flush=True)
        print(f"Row 24: {vt_cpm.get_line(23)}", flush=True)

        print("\n--- Linux Help Screen (Rows 1-5 & 24) ---", flush=True)
        for r in range(5):
            print(f"Row {r+1:2d}: {vt_lin.get_line(r)}", flush=True)
        print(f"Row 24: {vt_lin.get_line(23)}", flush=True)

        # Return from Help Screen (Enter)
        os.write(cpm_master, b"\r")
        os.write(lin_master, b"\r")
        time.sleep(0.3)
        drain(cpm_master, quiet_time=0.1, max_wait=1.0)
        drain(lin_master, quiet_time=0.1, max_wait=1.0)

        # Step 8: Goto Line Modal (Ctrl+L)
        print("\n" + "=" * 78, flush=True)
        print("STEP 8: Goto Line Modal (Ctrl+L)", flush=True)
        print("=" * 78, flush=True)
        os.write(cpm_master, b"\x0c")
        os.write(lin_master, b"\x0c")
        time.sleep(0.5)
        cpm_data = drain(cpm_master, quiet_time=0.2, max_wait=2.0)
        lin_data = drain(lin_master, quiet_time=0.2, max_wait=2.0)
        vt_cpm.clear_screen()
        vt_cpm.feed(cpm_data)
        vt_lin.clear_screen()
        vt_lin.feed(lin_data)

        print("--- CP/M Goto Line (Rows 8-16) ---", flush=True)
        for r in range(7, 16):
            print(f"Row {r+1:2d}: {vt_cpm.get_line(r)}", flush=True)

        print("\n--- Linux Goto Line (Rows 8-16) ---", flush=True)
        for r in range(7, 16):
            print(f"Row {r+1:2d}: {vt_lin.get_line(r)}", flush=True)

        # Cancel Goto Line (ESC)
        os.write(cpm_master, b"\x1b")
        os.write(lin_master, b"\x1b")
        time.sleep(0.3)
        drain(cpm_master, quiet_time=0.1, max_wait=1.0)
        drain(lin_master, quiet_time=0.1, max_wait=1.0)

        # Step 9: Safe Exit Modal (Ctrl+Q)
        print("\n" + "=" * 78, flush=True)
        print("STEP 9: Safe Exit Modal (Ctrl+Q)", flush=True)
        print("=" * 78, flush=True)
        os.write(cpm_master, b"\x11")
        os.write(lin_master, b"\x11")
        time.sleep(0.5)
        cpm_data = read_until_match(cpm_master, b"Cancel", timeout=5.0)
        cpm_data += drain(cpm_master, quiet_time=0.2, max_wait=2.0)
        lin_data = drain(lin_master, quiet_time=0.2, max_wait=2.0)
        vt_cpm.clear_screen()
        vt_cpm.feed(cpm_data)
        vt_lin.clear_screen()
        vt_lin.feed(lin_data)

        print("--- CP/M Exit Modal (Rows 8-16) ---", flush=True)
        for r in range(7, 16):
            print(f"Row {r+1:2d}: {vt_cpm.get_line(r)}", flush=True)

        print("\n--- Linux Exit Modal (Rows 8-16) ---", flush=True)
        for r in range(7, 16):
            print(f"Row {r+1:2d}: {vt_lin.get_line(r)}", flush=True)

        # Answer 'n' to exit both cleanly
        os.write(cpm_master, b"n")
        os.write(lin_master, b"n")
        time.sleep(0.5)
        cpm_exit_out = drain(cpm_master, quiet_time=0.2, max_wait=2.0)
        lin_exit_out = drain(lin_master, quiet_time=0.2, max_wait=2.0)

        print(f"\nCP/M Exit Result: {repr(cpm_exit_out[:100])}", flush=True)
        print(f"Linux Exit Result: {repr(lin_exit_out[:100])}", flush=True)

    finally:
        # Clean up processes
        for p in (cpm_proc, lin_proc):
            if p:
                try:
                    p.terminate()
                    p.wait(timeout=1.0)
                except Exception:
                    try:
                        p.kill()
                    except Exception:
                        pass

        if cpm_master:
            try:
                os.close(cpm_master)
            except OSError:
                pass
        if lin_master:
            try:
                os.close(lin_master)
            except OSError:
                pass
        print("\n[+] Comparison run finished cleanly.", flush=True)


if __name__ == "__main__":
    run_comparison()
