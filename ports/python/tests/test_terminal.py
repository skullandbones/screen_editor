#!/usr/bin/env python3
"""
Unit tests for terminal management and escape sequence decoding in SE.
"""

import io
import sys
import unittest
from unittest.mock import patch

from se.terminal import (
    Terminal,
    KEY_UP,
    KEY_DOWN,
    KEY_LEFT,
    KEY_RIGHT,
    KEY_HOME,
    KEY_END,
    KEY_PGUP,
    KEY_PGDN,
    KEY_DELETE,
    KEY_ESC,
    KEY_ENTER,
    KEY_BACKSPACE,
    KEY_CTRL_A,
    KEY_CTRL_K,
    KEY_CTRL_Q,
    KEY_CTRL_S,
    KEY_CTRL_F,
    KEY_CTRL_R,
    KEY_CTRL_B,
)


class TestTerminal(unittest.TestCase):
    """Test suite for Terminal input decoding and ANSI output routines."""

    def setUp(self):
        self.term = Terminal(default_cols=80, default_rows=24)

    def test_control_key_constants(self):
        """Step 1: Verify standard control key constant byte values."""
        print("[*] Step 1: Verifying control key constants...", flush=True)
        self.assertEqual(KEY_CTRL_A, "\x01")
        self.assertEqual(KEY_CTRL_B, "\x02")
        self.assertEqual(KEY_CTRL_F, "\x06")
        self.assertEqual(KEY_CTRL_K, "\x0b")
        self.assertEqual(KEY_CTRL_Q, "\x11")
        self.assertEqual(KEY_CTRL_R, "\x12")
        self.assertEqual(KEY_CTRL_S, "\x13")
        print("[+] Step 1: Control key constants verified.", flush=True)

    def test_csi_arrow_keys(self):
        """Step 2: Verify decoding of standard CSI arrow keys."""
        print("[*] Step 2: Testing CSI arrow keys decoding...", flush=True)
        sequences = {
            "\x1b[A": KEY_UP,
            "\x1b[B": KEY_DOWN,
            "\x1b[C": KEY_RIGHT,
            "\x1b[D": KEY_LEFT,
        }
        for seq, expected in sequences.items():
            with patch("sys.stdin", io.StringIO(seq)):
                with patch.object(self.term, "is_key_ready", return_value=True):
                    key = self.term.get_key(timeout=0.1)
                    self.assertEqual(key, expected)
        print("[+] Step 2: CSI arrow keys decoded successfully.", flush=True)

    def test_csi_navigation_keys(self):
        """Step 3: Verify decoding of Home, End, PgUp, PgDn, and Delete."""
        print("[*] Step 3: Testing navigation keys decoding...", flush=True)
        sequences = {
            "\x1b[H": KEY_HOME,
            "\x1b[F": KEY_END,
            "\x1b[1~": KEY_HOME,
            "\x1b[4~": KEY_END,
            "\x1b[5~": KEY_PGUP,
            "\x1b[6~": KEY_PGDN,
            "\x1b[3~": KEY_DELETE,
        }
        for seq, expected in sequences.items():
            with patch("sys.stdin", io.StringIO(seq)):
                with patch.object(self.term, "is_key_ready", return_value=True):
                    key = self.term.get_key(timeout=0.1)
                    self.assertEqual(key, expected)
        print("[+] Step 3: Navigation keys decoded successfully.", flush=True)

    def test_ss3_navigation_keys(self):
        """Step 4: Verify decoding of SS3 (ESC O ...) navigation keys."""
        print("[*] Step 4: Testing SS3 sequence decoding...", flush=True)
        sequences = {
            "\x1bOA": KEY_UP,
            "\x1bOB": KEY_DOWN,
            "\x1bOC": KEY_RIGHT,
            "\x1bOD": KEY_LEFT,
            "\x1bOH": KEY_HOME,
            "\x1bOF": KEY_END,
        }
        for seq, expected in sequences.items():
            with patch("sys.stdin", io.StringIO(seq)):
                with patch.object(self.term, "is_key_ready", return_value=True):
                    key = self.term.get_key(timeout=0.1)
                    self.assertEqual(key, expected)
        print("[+] Step 4: SS3 sequences decoded successfully.", flush=True)

    def test_two_key_shortcuts(self):
        """Step 5: Verify Jump to Top/Bottom shortcuts (ESC <, ESC >)."""
        print("[*] Step 5: Testing two-key Jump shortcuts...", flush=True)
        sequences = {
            "\x1b<": "JUMP_TOP",
            "\x1b>": "JUMP_BOTTOM",
            "\x1bt": "JUMP_TOP",
            "\x1bb": "JUMP_BOTTOM",
        }
        for seq, expected in sequences.items():
            with patch("sys.stdin", io.StringIO(seq)):
                with patch.object(self.term, "is_key_ready", return_value=True):
                    key = self.term.get_key(timeout=0.1)
                    self.assertEqual(key, expected)
        print("[+] Step 5: Jump shortcuts verified.", flush=True)

    def test_standalone_esc(self):
        """Step 6: Verify standalone ESC key when no sequence follows."""
        print("[*] Step 6: Testing standalone ESC key...", flush=True)
        with patch("sys.stdin", io.StringIO("\x1b")):
            with patch.object(self.term, "is_key_ready", return_value=False):
                key = self.term.get_key(timeout=0.1)
                self.assertEqual(key, KEY_ESC)
        print("[+] Step 6: Standalone ESC verified.", flush=True)

    def test_backspace_and_enter(self):
        """Step 7: Verify Backspace (0x08 & 0x7F) and Enter mapping."""
        print("[*] Step 7: Testing Backspace and Enter mapping...", flush=True)
        for char in ("\x08", "\x7f"):
            with patch("sys.stdin", io.StringIO(char)):
                key = self.term.get_key(timeout=0.1)
                self.assertEqual(key, KEY_BACKSPACE)
        for char in ("\r", "\n"):
            with patch("sys.stdin", io.StringIO(char)):
                key = self.term.get_key(timeout=0.1)
                self.assertEqual(key, KEY_ENTER)
        print("[+] Step 7: Backspace and Enter verified.", flush=True)

    def test_cursor_locate_bounds(self):
        """Step 8: Verify cursor positioning bounds clamping."""
        print("[*] Step 8: Testing cursor positioning bounds...", flush=True)
        out = io.StringIO()
        with patch("sys.stdout", out):
            self.term.locate(1, 1)
            self.term.locate(24, 80)
            self.term.locate(-5, -10)   # clamped to 1, 1
            self.term.locate(100, 200) # clamped to 24, 80
        expected = (
            "\x1b[1;1H"
            "\x1b[24;80H"
            "\x1b[1;1H"
            "\x1b[24;80H"
        )
        self.assertEqual(out.getvalue(), expected)
        print("[+] Step 8: Cursor locate clamping verified.", flush=True)


if __name__ == "__main__":
    t0 = unittest.runner.time.time()
    suite = unittest.TestLoader().loadTestsFromTestCase(TestTerminal)
    res = unittest.TextTestRunner(verbosity=1).run(suite)
    elapsed = unittest.runner.time.time() - t0
    if res.wasSuccessful():
        print(f"[+] All Terminal tests PASSED in {elapsed:.2f}s!", flush=True)
        sys.exit(0)
    else:
        print("[-] Terminal tests FAILED.", flush=True)
        sys.exit(1)
