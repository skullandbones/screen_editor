#!/usr/bin/env python3
"""
Unit tests for Editor controller in SE editor port.
Validates key dispatch, WordStar mappings, modal actions, and workspace flows.
Strictly adheres to Rule 9 logging standards and <= 80 characters line length.
"""

import os
import sys
import unittest
from unittest.mock import MagicMock

from se.editor import Editor
from se.terminal import KEY_CTRL_S, KEY_LEFT


class TestEditor(unittest.TestCase):
    """Test suite for Editor controller dispatch and commands."""

    def setUp(self):
        self.editor = Editor()
        self.editor.terminal.enter_raw_mode = MagicMock()
        self.editor.terminal.exit_raw_mode = MagicMock()

    def test_ctrl_s_dispatches_save_file(self):
        """Step 1: Verify Ctrl+S invokes action_save_file (Bug 2.7.1)."""
        print(
            "[*] Step 1: Testing Ctrl+S dispatches action_save_file...",
            flush=True,
        )
        self.editor.action_save_file = MagicMock(return_value=True)
        self.editor.buffer.cursor_col = 5

        # Dispatch Ctrl+S
        self.editor.dispatch_key(KEY_CTRL_S)

        # Must invoke action_save_file and NOT move cursor left
        self.editor.action_save_file.assert_called_once()
        self.assertEqual(self.editor.buffer.cursor_col, 5)

        # Dispatch KEY_LEFT to verify it still moves cursor left
        self.editor.dispatch_key(KEY_LEFT)
        self.assertEqual(self.editor.buffer.cursor_col, 4)

        print(
            "[+] Step 1: Ctrl+S save dispatch verified successfully.",
            flush=True,
        )


if __name__ == "__main__":
    unittest.main()
