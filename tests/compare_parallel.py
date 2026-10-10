#!/usr/bin/env python3
"""
Parallel Comparative Test Harness for SE.COM (CP/M) vs SE (Python Port).
Executes both editors in lockstep over pseudo-terminals (PTY), feeds identical
input keystrokes, captures 80x24 VT100 screen buffers, and compares behavior.
Strictly adheres to line length limit <= 80 characters.
"""

import fcntl
import os
import re
import select
import struct
import subprocess
import sys
import termios
import time
import tty
from typing import Dict, List, Optional, Tuple


def find_paths():
    """Locate emulator, ROM, disk image, and SE binaries."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    workspace_root = os.path.abspath(os.path.join(repo_root, "..", ".."))

    emu_bin = os.path.join(workspace_root, "tools", "rc2014_emu", "rc2014")
    rom_file = os.path.join(
        workspace_root, "tools", "romwbw_src", "Binary", "RC2014_std.rom"
    )
    img_file = os.path.join(repo_root, "disks", "hd1k_combo.img")
    se_bin = os.path.join(repo_root, "SE.COM")
    cpmcp_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp"
    )

    return repo_root, emu_bin, rom_file, img_file, se_bin, cpmcp_bin


class AnsiScreen:
    """Virtual 80x24 VT100 / ANSI terminal screen buffer."""

    def __init__(self, cols: int = 80, rows: int = 24):
        self.cols = cols
        self.rows = rows
        self.grid = [[" " for _ in range(cols)] for _ in range(rows)]
        self.cursor_row = 1  # 1-based
        self.cursor_col = 1  # 1-based

    def clear(self):
        """Clear all character cells."""
        self.grid = [
            [" " for _ in range(self.cols)] for _ in range(self.rows)
        ]

    def feed(self, data: bytes):
        """Process byte stream and update virtual screen state."""
        text = data.decode("latin1", errors="replace")
        i = 0
        n = len(text)
        while i < n:
            ch = text[i]
            if ch == "\x1b":
                if i + 1 < n and text[i + 1] == "[":
                    j = i + 2
                    while j < n and not ("@" <= text[j] <= "~"):
                        j += 1
                    if j < n:
                        cmd = text[j]
                        params = text[i + 2 : j]
                        self._handle_csi(cmd, params)
                        i = j + 1
                        continue
                    else:
                        break
                elif i + 1 < n and text[i + 1] in ("(", ")"):
                    i += 3
                    continue
                else:
                    i += 1
                    continue
            elif ch == "\r":
                self.cursor_col = 1
                i += 1
            elif ch == "\n":
                if self.cursor_row < self.rows:
                    self.cursor_row += 1
                i += 1
            elif ch == "\b":
                self.cursor_col = max(1, self.cursor_col - 1)
                i += 1
            elif 32 <= ord(ch) <= 126:
                if (
                    1 <= self.cursor_row <= self.rows
                    and 1 <= self.cursor_col <= self.cols
                ):
                    self.grid[self.cursor_row - 1][self.cursor_col - 1] = ch
                if self.cursor_col < self.cols:
                    self.cursor_col += 1
                i += 1
            else:
                i += 1

    def _handle_csi(self, cmd: str, params: str):
        if cmd in ("H", "f"):
            if not params:
                r, c = 1, 1
            else:
                parts = params.split(";")
                r = int(parts[0]) if parts[0] else 1
                c = int(parts[1]) if len(parts) > 1 and parts[1] else 1
            self.cursor_row = max(1, min(self.rows, r))
            self.cursor_col = max(1, min(self.cols, c))
        elif cmd == "J":
            if params in ("", "0"):
                for r in range(self.cursor_row - 1, self.rows):
                    start_c = (
                        self.cursor_col - 1 if r == self.cursor_row - 1 else 0
                    )
                    for c in range(start_c, self.cols):
                        self.grid[r][c] = " "
            elif params == "2":
                self.clear()
        elif cmd == "K":
            if 1 <= self.cursor_row <= self.rows:
                r = self.cursor_row - 1
                if params in ("", "0"):
                    for c in range(self.cursor_col - 1, self.cols):
                        self.grid[r][c] = " "
                elif params == "1":
                    for c in range(0, self.cursor_col):
                        self.grid[r][c] = " "
                elif params == "2":
                    for c in range(0, self.cols):
                        self.grid[r][c] = " "
        elif cmd == "A":
            n = int(params) if params.isdigit() else 1
            self.cursor_row = max(1, self.cursor_row - n)
        elif cmd == "B":
            n = int(params) if params.isdigit() else 1
            self.cursor_row = min(self.rows, self.cursor_row + n)
        elif cmd == "C":
            n = int(params) if params.isdigit() else 1
            self.cursor_col = min(self.cols, self.cursor_col + n)
        elif cmd == "D":
            n = int(params) if params.isdigit() else 1
            self.cursor_col = max(1, self.cursor_col - n)

    def render(self) -> List[str]:
        return ["".join(row) for row in self.grid]


def read_available(fd: int, timeout: float = 0.5) -> bytes:
    """Read all currently available bytes from file descriptor."""
    buf = b""
    t0 = time.time()
    while time.time() - t0 < timeout:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                chunk = os.read(fd, 4096)
                if not chunk:
                    break
                buf += chunk
            except (BlockingIOError, OSError):
                break
        elif buf:
            break
    return buf


def read_until_match(
    fd: int, match_bytes: bytes, timeout: float = 12.0
) -> bytes:
    """Read until target pattern appears in stream."""
    buf = b""
    t0 = time.time()
    while time.time() - t0 < timeout:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                chunk = os.read(fd, 1024)
                if not chunk:
                    break
                buf += chunk
                if match_bytes in buf:
                    return buf
            except (BlockingIOError, OSError):
                break
    return buf


def set_pty_size(fd: int, cols: int = 80, rows: int = 24):
    """Set window dimensions for pseudo-terminal."""
    winsize = struct.pack("HHHH", rows, cols, 0, 0)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, winsize)


def main():
    print("=" * 60, flush=True)
    print("SE Parallel Comparative Engine: CP/M SE.COM vs Python SE",
          flush=True)
    print("=" * 60, flush=True)

    repo_root, emu_bin, rom_file, img_file, se_bin, cpmcp_bin = find_paths()

    cfg_tmp = "/tmp/SE_TEST.CFG"
    with open(cfg_tmp, "w") as f:
        f.write("SCREEN=80x24\r\nTAB=8\r\nMAXLINES=16K\r\n")

    if os.path.isfile(cpmcp_bin):
        subprocess.run(
            [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, "0:SE.COM"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        subprocess.run(
            [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, cfg_tmp, "0:SE.CFG"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    # 1. Boot CP/M SE.COM in RC2014 emulator
    print("[*] Launching CP/M SE.COM in RC2014 emulator PTY...", flush=True)
    cpm_master, cpm_slave = os.openpty()
    set_pty_size(cpm_slave, 80, 24)
    tty.setraw(cpm_slave)
    os.set_blocking(cpm_master, False)

    cpm_cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    cpm_proc = subprocess.Popen(
        cpm_cmd,
        stdin=cpm_slave,
        stdout=cpm_slave,
        stderr=cpm_slave,
        close_fds=True,
    )
    os.close(cpm_slave)

    out = read_until_match(cpm_master, b"Boot [H=Help]:", timeout=8.0)
    if b"Boot [H=Help]:" not in out:
        print("[-] Failed to boot RomWBW.")
        cpm_proc.kill()
        return 1

    time.sleep(0.3)
    os.write(cpm_master, b"c\r")
    read_until_match(cpm_master, b"B>", timeout=6.0)
    time.sleep(0.3)
    os.write(cpm_master, b"c:\r")
    read_until_match(cpm_master, b"C>", timeout=4.0)
    time.sleep(0.5)
    read_available(cpm_master, timeout=0.5)

    # 2. Launch Python SE
    print("[*] Launching Python SE in PTY...", flush=True)
    py_master, py_slave = os.openpty()
    set_pty_size(py_slave, 80, 24)
    tty.setraw(py_slave)
    os.set_blocking(py_master, False)

    py_env = dict(os.environ)
    py_env["PYTHONPATH"] = os.path.join(repo_root, "ports", "python")
    py_env["TERM"] = "vt100"
    py_env["COLUMNS"] = "80"
    py_env["LINES"] = "24"

    py_cmd = [
        sys.executable,
        "-m",
        "se",
        "--config",
        cfg_tmp,
    ]
    py_proc = subprocess.Popen(
        py_cmd,
        stdin=py_slave,
        stdout=py_slave,
        stderr=py_slave,
        env=py_env,
        cwd=repo_root,
        close_fds=True,
    )
    os.close(py_slave)

    # 3. Start CP/M SE.COM
    time.sleep(0.3)
    os.write(cpm_master, b"se\r")

    cpm_screen = AnsiScreen(80, 24)
    py_screen = AnsiScreen(80, 24)

    # Wait for CP/M splash screen to load completely
    cpm_raw = read_until_match(cpm_master, b"for about", timeout=15.0)
    cpm_raw += read_available(cpm_master, timeout=0.8)
    py_raw = read_available(py_master, timeout=1.0)
    cpm_screen.feed(cpm_raw)
    py_screen.feed(py_raw)

    print("[+] Both SE instances initialized.", flush=True)

    # Define test scenario sequences
    scenarios = [
        ("Step 1: Initial Startup Screen", []),
        ("Step 2: Enter Editor Workspace ('e')", [b"e"]),
        (
            "Step 3: Insert Document Line",
            [b"Hello World from Comparative SE!\r"],
        ),
        ("Step 4: Cursor Up", [b"\x1b[A"]),
        ("Step 5: Cursor Home (Ctrl+A)", [b"\x01"]),
        ("Step 6: Help Screen (Ctrl+K)", [b"\x0b"]),
        ("Step 7: Dismiss Help Screen (Space)", [b" "]),
        ("Step 8: Find Dialog (Ctrl+F)", [b"\x06"]),
        ("Step 9: Cancel Find Dialog (ESC)", [b"\x1b"]),
        ("Step 10: Block Selection (Ctrl+B)", [b"\x02"]),
        ("Step 11: Extend Selection (Right, Right)", [b"\x1b[C", b"\x1b[C"]),
        ("Step 12: Cancel Selection (ESC)", [b"\x1b"]),
        ("Step 13: Return to Splash (ESC)", [b"\x1b"]),
        ("Step 14: Config Screen ('c')", [b"c"]),
        ("Step 15: Exit Config to Splash (ESC)", [b"\x1b"]),
        ("Step 16: Safe Quit (Ctrl+Q)", [b"\x11"]),
    ]

    divergences = []

    for name, keys in scenarios:
        print(f"\n{'=' * 60}\n{name} (keys: {keys})\n{'=' * 60}", flush=True)
        if keys:
            for k in keys:
                os.write(cpm_master, k)
                os.write(py_master, k)
                time.sleep(0.15)
            cpm_data = read_available(cpm_master, timeout=1.0)
            py_data = read_available(py_master, timeout=0.5)
            cpm_screen.feed(cpm_data)
            py_screen.feed(py_data)

        cpm_lines = cpm_screen.render()
        py_lines = py_screen.render()

        print(
            f"CP/M Cursor  : Row {cpm_screen.cursor_row}, "
            f"Col {cpm_screen.cursor_col}"
        )
        print(
            f"Python Cursor: Row {py_screen.cursor_row}, "
            f"Col {py_screen.cursor_col}"
        )

        diffs = []
        for r in range(24):
            c_ln = cpm_lines[r]
            p_ln = py_lines[r]
            if c_ln != p_ln:
                diffs.append((r + 1, c_ln, p_ln))

        print(f"Status Bar Row 24:")
        print(f"  CP/M  : [{cpm_lines[23]}]")
        print(f"  Python: [{py_lines[23]}]")

        if diffs:
            print(f"Total row divergences: {len(diffs)}/24")
            for r_num, c_ln, p_ln in diffs[:6]:
                print(f"  Row {r_num:02d}:")
                print(f"    CP/M  : [{c_ln}]")
                print(f"    Python: [{p_ln}]")
            divergences.append((name, len(diffs), diffs))
        else:
            print("[+] Exact visual match (0 row divergences)!")

    # Cleanup processes
    try:
        cpm_proc.kill()
        py_proc.kill()
    except Exception:
        pass

    print("\n" + "=" * 60, flush=True)
    print(f"Execution complete. Analyzed {len(scenarios)} scenarios, "
          f"{len(divergences)} diverged.", flush=True)
    print("=" * 60, flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
