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
from se.terminal import (
    KEY_CTRL_S,
    KEY_CTRL_V,
    KEY_LEFT,
    KEY_RIGHT,
    KEY_HOME,
    KEY_END,
    KEY_DELETE,
    KEY_BACKSPACE,
    KEY_ENTER,
    KEY_PGDN,
)


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

    def test_ctrl_v_pastes_clipboard(self):
        """Step 2: Verify Ctrl+V dispatches paste_block (Bug 2.7.3)."""
        print(
            "[*] Step 2: Testing Ctrl+V dispatches paste_block...",
            flush=True,
        )
        self.editor.buffer.lines = ["Hello World"]
        self.editor.buffer.cursor_row = 0
        self.editor.buffer.cursor_col = 5
        self.editor.buffer.clipboard = " Beautiful"

        # Dispatch Ctrl+V
        self.editor.dispatch_key(KEY_CTRL_V)

        self.assertEqual(
            self.editor.buffer.current_line, "Hello Beautiful World"
        )
        self.assertEqual(self.editor.buffer.cursor_col, 15)

        # Verify empty clipboard falls back to page_down
        self.editor.buffer.clipboard = ""
        self.editor.buffer.page_down = MagicMock()
        self.editor.dispatch_key(KEY_CTRL_V)
        self.editor.buffer.page_down.assert_called_once()

        print(
            "[+] Step 2: Ctrl+V paste dispatch verified successfully.",
            flush=True,
        )

    def test_status_bar_field4_invariance(self):
        """Step 3: Verify status bar Field 4 invariance (Bug 2.7.4)."""
        print(
            "[*] Step 3: Testing status bar Field 4 invariance...",
            flush=True,
        )
        written = []
        self.editor.terminal.write = lambda s: written.append(s)

        # Render status bar with hypothetical status_msg
        self.editor.renderer.render_status_bar(
            self.editor.buffer, status_msg="Custom Msg"
        )
        full_bar = "".join(written)
        self.assertIn("^K: Editor keys", full_bar)
        self.assertNotIn("Custom Msg", full_bar)

        print(
            "[+] Step 3: Status bar Field 4 invariance verified.",
            flush=True,
        )

    def test_plugin_palette_child_isolation(self):
        """Step 4: Verify child pop-up isolation protocol (Bug 2.7.5)."""
        print(
            "[*] Step 4: Testing child pop-up isolation protocol...",
            flush=True,
        )
        self.editor.plugin_mgr.list_plugins = MagicMock(
            return_value=[("ROT13", "Rotate letters")]
        )
        self.editor.modal.show_menu = MagicMock(return_value=0)
        order_of_events = []
        self.editor.renderer.render_editor = MagicMock(
            side_effect=lambda *a, **k: order_of_events.append("render_editor")
        )
        self.editor.plugin_mgr.execute = MagicMock(
            side_effect=lambda *a, **k: order_of_events.append("execute_plugin")
        )

        # Trigger plugin palette action
        self.editor.action_plugin_palette()

        self.assertIn("render_editor", order_of_events)
        self.assertIn("execute_plugin", order_of_events)
        # Must clear parent menu before executing child plugin
        self.assertEqual(order_of_events, ["render_editor", "execute_plugin"])

        print(
            "[+] Step 4: Child pop-up isolation protocol verified.",
            flush=True,
        )

    def test_modal_dialog_framing_layout(self):
        """Step 5: Verify modal dialog framing and 8-row height (Bug 2.7.6)."""
        print(
            "[*] Step 5: Testing modal dialog framing and 8-row layout...",
            flush=True,
        )
        captured_boxes = []

        def mock_draw_box(top, left, width, lines):
            captured_boxes.append((top, left, width, list(lines)))

        self.editor.modal.draw_box = mock_draw_box
        self.editor.terminal.get_key = MagicMock(return_value="y")

        # Test show_confirm (Archetype B)
        ans = self.editor.modal.show_confirm(
            title="Query", desc="Warning description", query="Continue?"
        )
        self.assertEqual(ans, "y")
        self.assertEqual(len(captured_boxes), 1)
        _, _, _, lines = captured_boxes[0]
        # 6 lines + 2 borders = 8 rows total
        self.assertEqual(len(lines), 6)
        self.assertEqual(lines[4], "")  # Empty row before options
        self.assertIn("[Y]es", lines[5])

        # Test show_input (Archetype C)
        captured_boxes.clear()
        self.editor.terminal.get_key = MagicMock(return_value="\r")
        res = self.editor.modal.show_input(
            title="Input", desc="Description", label="Target:"
        )
        self.assertEqual(res, "")
        self.assertEqual(len(captured_boxes), 1)
        _, _, _, lines = captured_boxes[0]
        self.assertEqual(len(lines), 6)
        self.assertEqual(lines[4], "")  # Empty row before options
        self.assertIn("[Enter]=Confirm", lines[5])

        print(
            "[+] Step 5: Modal dialog framing and 8-row layout verified.",
            flush=True,
        )

    def test_modal_input_navigation_and_editing(self):
        """Step 6: Verify navigation and delete in show_input (Bug 2.7.7)."""
        print(
            "[*] Step 6: Testing navigation keys in show_input...",
            flush=True,
        )
        self.editor.modal.draw_box = MagicMock()

        # Key sequence to test left, right, home, end, delete, backspace
        keys = [
            KEY_LEFT,
            KEY_LEFT,  # Cursor between B and D
            "C",  # Insert C -> "ABCDE"
            KEY_HOME,  # Cursor at 0
            KEY_DELETE,  # Delete A -> "BCDE"
            KEY_END,  # Cursor at end (4)
            KEY_BACKSPACE,  # Delete E -> "BCD"
            KEY_ENTER,  # Submit
        ]
        key_iter = iter(keys)
        self.editor.terminal.get_key = lambda: next(key_iter)

        res = self.editor.modal.show_input(
            title="Edit",
            desc="Edit text",
            label="Value:",
            initial_text="ABDE",
        )
        self.assertEqual(res, "BCD")

        print(
            "[+] Step 6: Modal input navigation & editing verified.",
            flush=True,
        )


if __name__ == "__main__":
    unittest.main()
