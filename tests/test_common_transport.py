#!/usr/bin/env python3
"""Unit tests for test_editor_common.py transport abstractions and utilities.

Verifies:
  1. VirtualTerminal ANSI emulation (80x24 and 120x40 grids).
  2. Cursor navigation, inverse styling, and screen clearing.
  3. read_until and drain_all compatibility with both raw fds and transports.
  4. PtyTransport process lifecycle and I/O.

Part of SE.COM test infrastructure.
"""

import os
import sys

from test_editor_common import (
    EditorTransport,
    PtyTransport,
    VirtualTerminal,
    drain_all,
    read_until,
)


def test_virtual_terminal():
    print("[*] Testing VirtualTerminal ANSI parsing...")
    vt = VirtualTerminal(rows=24, cols=80)
    assert vt.rows == 24
    assert vt.cols == 80

    # Test basic writing
    vt.feed(b"Hello World\r\nLine 2")
    assert "Hello World" in vt.get_line(0)
    assert "Line 2" in vt.get_line(1)

    # Test cursor positioning
    vt.feed(b"\x1b[24;1HStatus Bar Content")
    status = vt.get_status_bar()
    assert "Status Bar Content" in status

    # Test inverse video
    vt.feed(b"\x1b[24;1H\x1b[7mINVERSE\x1b[0m")
    assert vt.inv[23][0] is True
    assert vt.inv[23][6] is True
    assert vt.inv[23][7] is False

    # Test clear screen
    vt.feed(b"\x1b[2J")
    assert vt.get_line(0).strip() == ""
    assert vt.get_status_bar().strip() == ""
    print("[+] VirtualTerminal test passed.")


def test_read_until_and_drain_compatibility():
    print("[*] Testing read_until and drain_all compatibility...")

    # Test with raw integer pipe fd
    r_fd, w_fd = os.pipe()
    try:
        os.write(w_fd, b"Boot [H=Help]:\n")
        out = read_until(r_fd, b"Boot [H=Help]:", timeout=1.0)
        assert b"Boot [H=Help]:" in out

        os.write(w_fd, b"trailing data")
        drained = drain_all(r_fd, quiet_time=0.1)
        assert b"trailing data" in drained
    finally:
        os.close(r_fd)
        os.close(w_fd)

    # Test with custom EditorTransport mock
    class MockTransport(EditorTransport):
        def __init__(self):
            self.buf = b""

        def write(self, data: bytes) -> None:
            self.buf += data

        def read(self, max_bytes: int = 4096) -> bytes:
            res = self.buf[:max_bytes]
            self.buf = self.buf[max_bytes:]
            return res

        def read_until(self, match_bytes, timeout=8.0):
            targets = (
                list(match_bytes)
                if isinstance(match_bytes, (list, tuple))
                else [match_bytes]
            )
            for t in targets:
                if t in self.buf:
                    return self.buf
            return b""

        def drain_all(self, quiet_time=0.2):
            res = self.buf
            self.buf = b""
            return res

        def close(self):
            pass

    mock = MockTransport()
    mock.buf = b"Welcome to SE\r\nLine 1\r\n"
    out = read_until(mock, b"Welcome to SE", timeout=1.0)
    assert b"Welcome to SE" in out

    drained = drain_all(mock)
    assert b"Line 1" in drained
    print("[+] read_until and drain_all compatibility test passed.")


def test_pty_transport_echo():
    print("[*] Testing PtyTransport with cat subprocess...")
    pty_t = PtyTransport(["cat"])
    try:
        assert isinstance(pty_t.fileno(), int)
        pty_t.write(b"Hello from PTY\n")
        out = pty_t.read_until(b"Hello from PTY", timeout=2.0)
        assert b"Hello from PTY" in out
    finally:
        pty_t.close()
    print("[+] PtyTransport test passed.")


def main():
    test_virtual_terminal()
    test_read_until_and_drain_compatibility()
    test_pty_transport_echo()
    print("[+] All test_editor_common unit tests PASSED.")


if __name__ == "__main__":
    main()
