#!/usr/bin/env python3
"""Common transport abstractions and test utilities for SE editor testing.

Provides a unified interface across different execution environments:
  - EditorTransport: Abstract base class for I/O transports.
  - PtyTransport: RC2014 / RomWBW CP/M 2.2 / 3.0 via UNIX pseudo-terminal.
  - SocketUartTransport: TCP / Unix socket bridge to hardware UART.
  - ZrcpTransport: ZEsarUX Remote Control Protocol (ZRCP) socket.
  - VirtualTerminal: 80x24 / 120x40 ANSI screen state emulator.

Part of SE.COM / Multi-Target Regression Test Infrastructure.
"""

import abc
import os
import pty
import re
import select
import shutil
import socket
import subprocess
import sys
import time
import tty


class EditorTransport(abc.ABC):
    """Abstract base class for editor I/O transports."""

    @abc.abstractmethod
    def write(self, data: bytes) -> None:
        """Write raw bytes (keystrokes / commands) to the editor."""
        pass

    @abc.abstractmethod
    def read(self, max_bytes: int = 4096) -> bytes:
        """Read available raw bytes from the editor."""
        pass

    @abc.abstractmethod
    def read_until(
        self,
        match_bytes: bytes | list[bytes] | tuple[bytes, ...],
        timeout: float = 8.0,
    ) -> bytes:
        """Read until any of match_bytes appears in buffer or timeout."""
        pass

    @abc.abstractmethod
    def drain_all(self, quiet_time: float = 0.2) -> bytes:
        """Drain incoming data until idle for quiet_time seconds."""
        pass

    @abc.abstractmethod
    def close(self) -> None:
        """Clean up transport and terminate associated processes."""
        pass

    def fileno(self) -> int:
        """Return underlying OS file descriptor if available."""
        raise NotImplementedError("fileno() not supported on this transport")

    def __enter__(self) -> "EditorTransport":
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        self.close()


class PtyTransport(EditorTransport):
    """UNIX pseudo-terminal (PTY) transport for CP/M emulators (RC2014)."""

    def __init__(
        self,
        cmd: list[str],
        env: dict[str, str] | None = None,
        cwd: str | None = None,
    ) -> None:
        self.master_fd, slave_fd = os.openpty()
        tty.setraw(slave_fd)
        os.set_blocking(self.master_fd, False)

        self.proc = subprocess.Popen(
            cmd,
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            close_fds=True,
            env=env,
            cwd=cwd,
        )
        os.close(slave_fd)
        self.closed = False

    def fileno(self) -> int:
        return self.master_fd

    def write(self, data: bytes) -> None:
        if self.closed:
            raise OSError("PtyTransport is closed")
        os.write(self.master_fd, data)

    def read(self, max_bytes: int = 4096) -> bytes:
        if self.closed:
            return b""
        try:
            return os.read(self.master_fd, max_bytes)
        except (BlockingIOError, OSError):
            return b""

    def read_until(
        self,
        match_bytes: bytes | list[bytes] | tuple[bytes, ...],
        timeout: float = 8.0,
    ) -> bytes:
        buf = b""
        t0 = time.time()
        targets = (
            list(match_bytes)
            if isinstance(match_bytes, (list, tuple))
            else [match_bytes]
        )
        while time.time() - t0 < timeout:
            r, _, _ = select.select([self.master_fd], [], [], 0.05)
            if r:
                try:
                    data = os.read(self.master_fd, 1024)
                    if not data:
                        break
                    buf += data
                    for target in targets:
                        if target in buf:
                            return buf
                except (BlockingIOError, OSError):
                    pass
        return buf

    def drain_all(self, quiet_time: float = 0.2) -> bytes:
        time.sleep(0.05)
        buf = b""
        while True:
            r, _, _ = select.select([self.master_fd], [], [], quiet_time)
            if not r:
                break
            try:
                data = os.read(self.master_fd, 4096)
                if not data:
                    break
                buf += data
            except (BlockingIOError, OSError):
                break
        return buf

    def close(self) -> None:
        if self.closed:
            return
        self.closed = True
        try:
            self.proc.kill()
            self.proc.wait(timeout=1.0)
        except (OSError, subprocess.TimeoutExpired):
            pass
        try:
            os.close(self.master_fd)
        except OSError:
            pass


class SocketUartTransport(EditorTransport):
    """TCP or Unix Domain Socket transport for UART-bridged emulators."""

    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = 10011,
        unix_path: str | None = None,
        proc: subprocess.Popen | None = None,
        timeout: float = 5.0,
    ) -> None:
        self.proc = proc
        self.closed = False
        if unix_path:
            self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.sock.settimeout(timeout)
            self.sock.connect(unix_path)
        else:
            self.sock = socket.create_connection((host, port), timeout=timeout)
        self.sock.setblocking(False)

    def fileno(self) -> int:
        return self.sock.fileno()

    def write(self, data: bytes) -> None:
        if self.closed:
            raise OSError("SocketUartTransport is closed")
        self.sock.sendall(data)

    def read(self, max_bytes: int = 4096) -> bytes:
        if self.closed:
            return b""
        try:
            return self.sock.recv(max_bytes)
        except (BlockingIOError, OSError, socket.error):
            return b""

    def read_until(
        self,
        match_bytes: bytes | list[bytes] | tuple[bytes, ...],
        timeout: float = 8.0,
    ) -> bytes:
        buf = b""
        t0 = time.time()
        targets = (
            list(match_bytes)
            if isinstance(match_bytes, (list, tuple))
            else [match_bytes]
        )
        while time.time() - t0 < timeout:
            r, _, _ = select.select([self.sock], [], [], 0.05)
            if r:
                try:
                    data = self.sock.recv(1024)
                    if not data:
                        break
                    buf += data
                    for target in targets:
                        if target in buf:
                            return buf
                except (BlockingIOError, OSError, socket.error):
                    pass
        return buf

    def drain_all(self, quiet_time: float = 0.2) -> bytes:
        time.sleep(0.05)
        buf = b""
        while True:
            r, _, _ = select.select([self.sock], [], [], quiet_time)
            if not r:
                break
            try:
                data = self.sock.recv(4096)
                if not data:
                    break
                buf += data
            except (BlockingIOError, OSError, socket.error):
                break
        return buf

    def close(self) -> None:
        if self.closed:
            return
        self.closed = True
        try:
            self.sock.close()
        except OSError:
            pass
        if self.proc:
            try:
                self.proc.kill()
                self.proc.wait(timeout=1.0)
            except (OSError, subprocess.TimeoutExpired):
                pass


class ZrcpTransport(EditorTransport):
    """ZEsarUX Remote Control Protocol (ZRCP) socket transport."""

    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = 10010,
        proc: subprocess.Popen | None = None,
        timeout: float = 5.0,
    ) -> None:
        self.proc = proc
        self.closed = False
        self.sock = socket.create_connection((host, port), timeout=timeout)
        time.sleep(0.2)
        # Drain initial greeting
        try:
            self.sock.recv(4096)
        except Exception:
            pass

    def fileno(self) -> int:
        return self.sock.fileno()

    def send_cmd(self, cmd: str) -> str:
        """Send command to ZRCP server and return text response."""
        if self.closed:
            raise OSError("ZrcpTransport is closed")
        self.sock.sendall((cmd + "\n").encode("latin1"))
        time.sleep(0.05)
        resp = b""
        while True:
            try:
                self.sock.settimeout(0.3)
                chunk = self.sock.recv(4096)
                if not chunk:
                    break
                resp += chunk
                if b"command> " in resp or b"command@cpu-step> " in resp:
                    break
            except Exception:
                break
        return resp.decode("latin1", errors="ignore")

    def write(self, data: bytes) -> None:
        for b in data:
            self.send_cmd(f"send-keys-ascii 50 {b}")
            time.sleep(0.02)

    def read(self, max_bytes: int = 4096) -> bytes:
        return b""

    def read_until(
        self,
        match_bytes: bytes | list[bytes] | tuple[bytes, ...],
        timeout: float = 8.0,
    ) -> bytes:
        t0 = time.time()
        targets = (
            list(match_bytes)
            if isinstance(match_bytes, (list, tuple))
            else [match_bytes]
        )
        while time.time() - t0 < timeout:
            regs = self.send_cmd("get-registers")
            for target in targets:
                if target.decode("latin1", errors="ignore") in regs:
                    return regs.encode("latin1")
            time.sleep(0.1)
        return b""

    def drain_all(self, quiet_time: float = 0.2) -> bytes:
        time.sleep(quiet_time)
        return b""

    def close(self) -> None:
        if self.closed:
            return
        self.closed = True
        try:
            self.send_cmd("exit-emulator")
            self.sock.close()
        except Exception:
            pass
        if self.proc:
            try:
                self.proc.kill()
                self.proc.wait(timeout=1.0)
            except (OSError, subprocess.TimeoutExpired):
                pass


class VirtualTerminal:
    """Emulates an 80x24 (or 120x40) ANSI/VT100 terminal grid."""

    def __init__(self, rows: int = 24, cols: int = 80) -> None:
        self.rows = rows
        self.cols = cols
        self.grid = [[" " for _ in range(cols)] for _ in range(rows)]
        self.inv = [[False for _ in range(cols)] for _ in range(rows)]
        self.row = 0
        self.col = 0
        self.inverse = False

    def clear_screen(self) -> None:
        self.grid = [[" " for _ in range(self.cols)] for _ in range(self.rows)]
        self.inv = [
            [False for _ in range(self.cols)] for _ in range(self.rows)
        ]
        self.row = 0
        self.col = 0

    def clear_eol(self) -> None:
        if 0 <= self.row < self.rows:
            for c in range(self.col, self.cols):
                self.grid[self.row][c] = " "
                self.inv[self.row][c] = False

    def feed(self, data: bytes) -> None:
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
                i += 1
            elif ch == "\r":
                self.col = 0
                i += 1
            elif ch == "\n":
                if self.row < self.rows - 1:
                    self.row += 1
                i += 1
            elif ch == "\b":
                if self.col > 0:
                    self.col -= 1
                i += 1
            elif ord(ch) >= 32:
                if 0 <= self.row < self.rows and 0 <= self.col < self.cols:
                    self.grid[self.row][self.col] = ch
                    self.inv[self.row][self.col] = self.inverse
                    self.col += 1
                i += 1
            else:
                i += 1

    def _handle_csi(self, params: str, cmd: str) -> None:
        if cmd in ("H", "f"):
            parts = params.split(";") if params else []
            r = int(parts[0]) - 1 if len(parts) > 0 and parts[0] else 0
            c = int(parts[1]) - 1 if len(parts) > 1 and parts[1] else 0
            self.row = max(0, min(r, self.rows - 1))
            self.col = max(0, min(c, self.cols - 1))
        elif cmd == "J":
            if params == "2":
                self.clear_screen()
        elif cmd == "K":
            self.clear_eol()
        elif cmd == "m":
            parts = params.split(";") if params else ["0"]
            for p in parts:
                code = int(p) if p else 0
                if code == 7:
                    self.inverse = True
                elif code == 0:
                    self.inverse = False

    def get_line(self, row: int) -> str:
        if 0 <= row < self.rows:
            return "".join(self.grid[row])
        return ""

    def get_status_bar(self) -> str:
        return self.get_line(self.rows - 1)

    def contains(self, pattern: str) -> bool:
        for r in range(self.rows):
            if pattern in "".join(self.grid[r]):
                return True
        return False


def read_until(
    transport_or_fd: EditorTransport | int,
    match_bytes: bytes | list[bytes] | tuple[bytes, ...],
    timeout: float = 8.0,
) -> bytes:
    """Read until target appears, accepting EditorTransport or integer fd."""
    if isinstance(transport_or_fd, EditorTransport):
        return transport_or_fd.read_until(match_bytes, timeout=timeout)

    master_fd = transport_or_fd
    buf = b""
    t0 = time.time()
    targets = (
        list(match_bytes)
        if isinstance(match_bytes, (list, tuple))
        else [match_bytes]
    )
    while time.time() - t0 < timeout:
        r, _, _ = select.select([master_fd], [], [], 0.05)
        if r:
            try:
                data = os.read(master_fd, 1024)
                if not data:
                    break
                buf += data
                for target in targets:
                    if target in buf:
                        return buf
            except (BlockingIOError, OSError):
                pass
    return buf


def drain_all(
    transport_or_fd: EditorTransport | int,
    quiet_time: float = 0.2,
) -> bytes:
    """Drain data until quiet, accepting EditorTransport or integer fd."""
    if isinstance(transport_or_fd, EditorTransport):
        return transport_or_fd.drain_all(quiet_time=quiet_time)

    master_fd = transport_or_fd
    time.sleep(0.05)
    buf = b""
    while True:
        r, _, _ = select.select([master_fd], [], [], quiet_time)
        if not r:
            break
        try:
            data = os.read(master_fd, 4096)
            if not data:
                break
            buf += data
        except (BlockingIOError, OSError):
            break
    return buf


def stage_headless_fixtures(work_dir: str, repo_root: str) -> None:
    """Stage standard CP/M test fixture files into a working directory."""
    for fname in ("2.TXT", "30.TXT"):
        src = os.path.join(repo_root, fname)
        if os.path.exists(src):
            shutil.copy2(src, os.path.join(work_dir, fname))

    with open(os.path.join(work_dir, "BIG.TXT"), "w") as f:
        for i in range(1, 3073):
            f.write(f"Line {i:04d}\r\n")
    with open(os.path.join(work_dir, "BIG300.TXT"), "w") as f:
        for i in range(1, 301):
            f.write(f"Line {i:04d} of 300\r\n")
    with open(os.path.join(work_dir, "SE.COM"), "wb") as f:
        f.write(b"\x00" * 1024)
    with open(os.path.join(work_dir, "SE.CFG"), "w") as f:
        f.write("SCREEN=120x40\r\nRAMDRIVE=ON\r\n")
    with open(os.path.join(work_dir, "INS1.TXT"), "wb") as f:
        f.write(b"INSERTED")
    with open(os.path.join(work_dir, "INS2.TXT"), "wb") as f:
        f.write(b"FIRST LINE\r\nSECOND LINE")
    with open(os.path.join(work_dir, "U1FILE.TXT"), "w") as f:
        f.write("Hello from User 1 area!\r\nSecond line of user 1 file.\r\n")
    with open(os.path.join(work_dir, "CPM1.TXT"), "wb") as f:
        for i in range(1, 301):
            f.write(f"CPM1 Line {i:04d} content CRLF\r\n".encode("ascii"))
    with open(os.path.join(work_dir, "LIN1.TXT"), "wb") as f:
        for i in range(1, 301):
            f.write(f"LIN1 Line {i:04d} content LF\n".encode("ascii"))
    with open(os.path.join(work_dir, "CPM2.TXT"), "wb") as f:
        for i in range(1, 301):
            f.write(f"CPM2 Line {i:04d} content CRLF\r\n".encode("ascii"))


def _resolve_ci(name: str) -> str:
    """Resolve filename case-insensitively in current directory."""
    if ":" in name:
        name = name.split(":", 1)[1]
    if os.path.exists(name):
        return name
    low = name.lower()
    for entry in os.listdir("."):
        if entry.lower() == low:
            return entry
    return name


def run_ccp_shim(se_bin_path: str) -> None:
    """Minimal CP/M CCP shell shim for running Python SE in headless tests."""
    tty.setraw(sys.stdin.fileno())
    out = sys.stdout.buffer
    out.write(b"Boot [H=Help]: ")
    out.flush()

    state = "BOOT"
    drive = "B"
    line_buf = bytearray()

    while True:
        ch = os.read(sys.stdin.fileno(), 1)
        if not ch:
            break
        b = ch[0]
        if b in (13, 10):
            out.write(b"\r\n")
            out.flush()
            cmd_line = line_buf.decode("latin1", errors="ignore").strip()
            line_buf.clear()

            if state == "BOOT":
                if cmd_line.lower().startswith("c"):
                    state = "CCP"
                    drive = "B"
                    out.write(f"{drive}>".encode("latin1"))
                    out.flush()
                else:
                    out.write(b"Boot [H=Help]: ")
                    out.flush()
                continue

            low = cmd_line.lower()
            if low in ("b:", "c:", "a:", "d:"):
                drive = low[0].upper()
            elif low.startswith("user "):
                pass
            elif low.startswith("era "):
                arg = cmd_line[4:].strip()
                path = _resolve_ci(arg)
                if os.path.exists(path):
                    try:
                        os.remove(path)
                    except OSError:
                        pass
            elif low.startswith("type "):
                arg = cmd_line[5:].strip()
                path = _resolve_ci(arg)
                if os.path.exists(path):
                    with open(path, "rb") as f:
                        data = f.read()
                    if b"\x1a" in data:
                        data = data.split(b"\x1a", 1)[0]
                    data = data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
                    out.write(data)
                    if not data.endswith(b"\r\n"):
                        out.write(b"\r\n")
            elif low == "se" or low.startswith("se ") or low == "sec" or (
                low.startswith("sec ")
            ):
                parts = cmd_line.split()
                subprocess.run([sys.executable, se_bin_path] + parts[1:])
                tty.setraw(sys.stdin.fileno())

            out.write(f"\r\n{drive}>".encode("latin1"))
            out.flush()
        elif b in (8, 127):
            if line_buf:
                line_buf.pop()
                out.write(b"\b \b")
                out.flush()
        else:
            line_buf.append(b)
            out.write(ch)
            out.flush()


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "--ccp-shim":
        run_ccp_shim(sys.argv[2])

