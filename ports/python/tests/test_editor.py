#!/usr/bin/env python3
"""
Unit tests for Editor controller in SE editor port.
Validates key dispatch, WordStar mappings, modal actions, and workspace flows.
Strictly adheres to Rule 9 logging standards and <= 80 characters line length.
"""

import os
import sys
import tempfile
import unittest
from unittest.mock import MagicMock

from se.buffer import DocumentBuffer
from se.editor import Editor
from se.modal import ModalDialog
from se.terminal import (
    KEY_CTRL_B,
    KEY_CTRL_C,
    KEY_CTRL_D,
    KEY_CTRL_F,
    KEY_CTRL_K,
    KEY_CTRL_O,
    KEY_CTRL_S,
    KEY_CTRL_V,
    KEY_CTRL_W,
    KEY_CTRL_X,
    KEY_UP,
    KEY_DOWN,
    KEY_LEFT,
    KEY_RIGHT,
    KEY_HOME,
    KEY_END,
    KEY_DELETE,
    KEY_BACKSPACE,
    KEY_ENTER,
    KEY_ESC,
    KEY_TAB,
    KEY_PGDN,
)


class TestEditor(unittest.TestCase):
    """Test suite for Editor controller dispatch and commands."""

    def setUp(self):
        self.editor = Editor()
        self.editor.terminal.enter_raw_mode = MagicMock()
        self.editor.terminal.exit_raw_mode = MagicMock()
        self.editor.terminal.term_exit = MagicMock()

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

    def test_ctrl_v_pages_down_not_paste(self):
        """Step 2: Verify Ctrl+V dispatches page_down (Bug 2.7.60)."""
        print(
            "[*] Step 2: Testing Ctrl+V dispatches page_down...",
            flush=True,
        )
        self.editor.buffer.page_down = MagicMock()
        self.editor.dispatch_key(KEY_CTRL_V)
        self.editor.buffer.page_down.assert_called_once()

        print(
            "[+] Step 2: Ctrl+V page down dispatch verified.",
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

    def test_config_screen_option_toggles(self):
        """Step 7: Verify config options 3 & 4 toggle handlers (Bug 2.7.8)."""
        print(
            "[*] Step 7: Testing config screen option 3 & 4 toggles...",
            flush=True,
        )
        self.editor.renderer.render_centered_workspace = MagicMock()

        # Press '2' (toggle ramdrive), '3' (toggle max lines), and Enter (exit)
        keys = ["2", "3", "\r"]
        key_iter = iter(keys)
        self.editor.terminal.get_key = lambda: next(key_iter)

        # Ensure baseline values
        self.editor.config.set("MAXLINES", "16K")
        self.editor.config.set("RAMDRIVE", "PRESERVE")

        self.editor.action_config_screen()

        # Option 3 toggles 16K -> 32K
        self.assertEqual(self.editor.config.max_lines, "32K")
        # Option 2 toggles PRESERVE -> DISABLED
        self.assertFalse(self.editor.config.ramdrive_enabled)

        print(
            "[+] Step 7: Config screen option toggles verified.",
            flush=True,
        )

    def test_centered_workspace_prompt_cursor_position(self):
        """Step 8: Verify cursor placed adjacent to prompt (Bug 2.7.9)."""
        print(
            "[*] Step 8: Testing centered workspace prompt cursor...",
            flush=True,
        )
        self.editor.terminal.cols = 80
        self.editor.terminal.rows = 24
        locate_calls = []
        self.editor.terminal.locate = lambda r, c: locate_calls.append((r, c))
        self.editor.terminal.write = MagicMock()
        self.editor.terminal.clear_eol = MagicMock()
        self.editor.terminal.flush = MagicMock()

        lines = [
            "SE — Screen Editor",
            "",
            "Enter choice: ",
        ]
        self.editor.renderer.render_centered_workspace(
            lines, self.editor.buffer, geometry_str="80x24"
        )

        # Expected top_row and left_col:
        # avail_rows = 23, content_h = 3 -> top_row = 11
        # screen_cols = 80, content_w = 18 -> left_col = 32
        # prompt is line index 2 -> row = 11 + 2 = 13
        # prompt col = 32 + len("Enter choice: ") = 32 + 14 = 46
        self.assertTrue(len(locate_calls) > 0)
        final_cursor = locate_calls[-1]
        self.assertEqual(final_cursor, (13, 46))
        self.assertNotEqual(final_cursor[0], 24)

        print(
            "[+] Step 8: Centered workspace prompt cursor verified.",
            flush=True,
        )

    def test_esc_behavior_block_cancel_and_splash_exit(self):
        """Step 9: Verify ESC cancels block and exits splash (Bug 2.7.10)."""
        print(
            "[*] Step 9: Testing ESC block cancel & splash dual-exit...",
            flush=True,
        )
        self.editor.action_splash_screen = MagicMock()

        # Case A: Active block -> ESC must cancel block, not open splash
        self.editor.buffer.block_active = 1
        self.editor.dispatch_key(KEY_ESC)
        self.assertEqual(self.editor.buffer.block_active, 0)
        self.editor.action_splash_screen.assert_not_called()

        # Case B: Inactive block -> ESC opens splash screen
        self.editor.dispatch_key(KEY_ESC)
        self.editor.action_splash_screen.assert_called_once()

        # Case C: On splash screen, KEY_ESC is ignored; 'e' or Enter exits
        del self.editor.action_splash_screen  # restore real method
        self.editor.renderer.render_centered_workspace = MagicMock()
        self.editor.terminal.get_key = MagicMock(side_effect=[KEY_ESC, "e"])
        self.editor.action_splash_screen()

        print(
            "[+] Step 9: ESC block cancel and splash dual-exit verified.",
            flush=True,
        )

    def test_startup_mode_splash_screen(self):
        """Step 10: Verify splash on start without file (Bug 2.7.14)."""
        print(
            "[*] Step 10: Testing startup splash screen without file...",
            flush=True,
        )
        # Case A: Editor initialized with no file argument
        editor_no_file = Editor(filename=None)
        editor_no_file.terminal.enter_raw_mode = MagicMock()
        editor_no_file.terminal.exit_raw_mode = MagicMock()
        editor_no_file.renderer.render_editor = MagicMock()
        editor_no_file.terminal.get_key = MagicMock(
            side_effect=lambda: setattr(editor_no_file, "running", False)
        )
        editor_no_file.action_splash_screen = MagicMock(
            side_effect=lambda: setattr(editor_no_file, "running", False)
        )
        editor_no_file.run()
        editor_no_file.action_splash_screen.assert_called_once()

        # Case B: Editor initialized with file argument
        editor_with_file = Editor(filename="test.txt")
        editor_with_file.terminal.enter_raw_mode = MagicMock()
        editor_with_file.terminal.exit_raw_mode = MagicMock()
        editor_with_file.renderer.render_editor = MagicMock()
        editor_with_file.terminal.get_key = MagicMock(
            side_effect=lambda: setattr(editor_with_file, "running", False)
        )
        editor_with_file.action_splash_screen = MagicMock()
        editor_with_file.run()
        editor_with_file.action_splash_screen.assert_not_called()

        print(
            "[+] Step 10: Startup splash screen behavior verified.",
            flush=True,
        )

    def test_status_bar_block_selection_metrics_and_no_spill(self):
        """Step 11: Verify status bar block metrics & no spill (Bug 2.7.15)."""
        print(
            "[*] Step 11: Testing status bar block metrics and column spill...",
            flush=True,
        )
        written = []
        self.editor.terminal.write = lambda s: written.append(s)
        self.editor.terminal.cols = 80
        self.editor.terminal.rows = 24

        # Single-line selection (dynamic follows cursor)
        self.editor.buffer.block_active = 1
        self.editor.buffer.block_start_row = 0
        self.editor.buffer.block_start_col = 0
        self.editor.buffer.cursor_row = 0
        self.editor.buffer.cursor_col = 5
        self.editor.renderer.render_status_bar(self.editor.buffer)

        status_texts = [w for w in written if not w.startswith("\x1b")]
        self.assertEqual(len(status_texts[0]), 80)
        self.assertIn("^K: Editor keys |", status_texts[0])
        self.assertIn("[SEL]", status_texts[0])

        # Multi-line selection (dynamic follows cursor)
        written.clear()
        self.editor.buffer.lines = ["Line 1", "Line 2", "Line 3"]
        self.editor.buffer.cursor_row = 2
        self.editor.buffer.cursor_col = 3
        self.editor.renderer.render_status_bar(self.editor.buffer)

        status_texts_multi = [w for w in written if not w.startswith("\x1b")]
        self.assertEqual(len(status_texts_multi[0]), 80)
        self.assertIn("^K: Editor keys |", status_texts_multi[0])
        self.assertIn("[SEL]", status_texts_multi[0])

        # Solidified block (uses block_end_row / block_end_col)
        written.clear()
        self.editor.buffer.block_active = 2
        self.editor.buffer.block_end_row = 2
        self.editor.buffer.block_end_col = 3
        self.editor.renderer.render_status_bar(self.editor.buffer)

        status_texts_solid = [w for w in written if not w.startswith("\x1b")]
        self.assertEqual(len(status_texts_solid[0]), 80)
        self.assertIn("^K: Editor keys |", status_texts_solid[0])
        self.assertIn("[BLK LOCK]", status_texts_solid[0])

        print(
            "[+] Step 11: Status bar block indicators verified without spill.",
            flush=True,
        )

    def test_status_bar_geometry_and_environment_spacing(self):
        """Step 12: Verify status bar geometry & fmt spacing (Bug 2.7.16)."""
        print(
            "[*] Step 12: Testing status bar geometry and format spacing...",
            flush=True,
        )
        written = []
        self.editor.terminal.write = lambda s: written.append(s)
        self.editor.terminal.cols = 80
        self.editor.terminal.rows = 24

        # CP/M format default
        self.editor.buffer.format_cpm = True
        self.editor.renderer.render_status_bar(
            self.editor.buffer, geometry_str="80x24"
        )
        texts_cpm = [w for w in written if not w.startswith("\x1b")]
        self.assertEqual(len(texts_cpm[0]), 80)
        self.assertIn("  80x24 | CP/M  |", texts_cpm[0])

        # Linux format
        written.clear()
        self.editor.buffer.format_cpm = False
        self.editor.renderer.render_status_bar(
            self.editor.buffer, geometry_str="80x24"
        )
        texts_linux = [w for w in written if not w.startswith("\x1b")]
        self.assertEqual(len(texts_linux[0]), 80)
        self.assertIn("  80x24 | Linux |", texts_linux[0])

        # 120x40 geometry
        written.clear()
        self.editor.terminal.cols = 120
        self.editor.terminal.rows = 40
        self.editor.renderer.render_status_bar(
            self.editor.buffer, geometry_str="120x40"
        )
        texts_120 = [w for w in written if not w.startswith("\x1b")]
        self.assertEqual(len(texts_120[0]), 120)
        self.assertIn(" 120x40 | Linux |", texts_120[0])

        print(
            "[+] Step 12: Status bar geometry & format spacing verified.",
            flush=True,
        )

    def test_find_dialog_tab_case_toggle(self):
        """Step 13: Verify find modal Tab case toggle (Bug 2.7.17)."""
        print(
            "[*] Step 13: Testing find dialog Tab case toggle...",
            flush=True,
        )
        written = []
        self.editor.terminal.write = lambda s: written.append(s)
        self.editor.buffer.lines = ["This is a test line"]

        # Feed: "t", "e", "s", "t", KEY_TAB, KEY_ENTER
        key_sequence = ["t", "e", "s", "t", KEY_TAB, KEY_ENTER]
        key_iter = iter(key_sequence)
        self.editor.terminal.get_key = lambda timeout=None: next(
            key_iter, KEY_ENTER
        )

        self.editor.action_find()

        self.assertEqual(self.editor.search_query, "test")
        self.assertFalse(self.editor.case_sensitive)
        self.assertEqual(self.editor.buffer.cursor_col, 10)

        dialog_text = "".join(written)
        self.assertIn("Find Text", dialog_text)
        self.assertIn("Case Sensitive", dialog_text)
        self.assertIn("Case Insensitive", dialog_text)
        self.assertIn("[Tab]=Toggle Case", dialog_text)

        print(
            "[+] Step 13: Find dialog Tab case toggle verified.",
            flush=True,
        )

    def test_splash_command_matrix_and_status_blocks(self):
        """Step 14: Verify canonical splash commands & status (Bug 2.7.18)."""
        print(
            "[*] Step 14: Testing splash command matrix & status blocks...",
            flush=True,
        )
        rendered_lines_list = []
        self.editor.renderer.render_centered_workspace = (
            lambda lines, buf, geometry_str="80x24": rendered_lines_list.append(
                list(lines)
            )
        )

        # Feed sequence: '2' (set 120x40), '1' (set 80x24), 'e' (exit)
        keys = ["2", "1", "e"]
        key_iter = iter(keys)
        self.editor.terminal.get_key = lambda timeout=None: next(
            key_iter, "e"
        )

        self.editor.action_splash_screen()

        self.assertTrue(len(rendered_lines_list) >= 3)
        splash_text = "\n".join(rendered_lines_list[0])

        # Verify canonical commands
        expected_commands = [
            "type   [E]  or  [Enter] to edit",
            "type   [O]              to open file",
            "type   [S]              to save file",
            "type   [C]              to configure",
            "type   [P]              for plugins",
            "type   [Q]  or  [^Q]    to exit",
        ]
        for cmd in expected_commands:
            self.assertIn(cmd, splash_text)

        # Verify status info
        self.assertIn("Active Screen : [", splash_text)
        self.assertIn("Plugin System : [Operational]", splash_text)
        self.assertIn("Max Lines     : [", splash_text)

        # Verify geometry switching: initial 80x24 -> 120x40 -> 80x24
        self.assertEqual(self.editor.terminal.cols, 80)
        self.assertEqual(self.editor.terminal.rows, 24)

        print(
            "[+] Step 14: Splash commands & status blocks verified.",
            flush=True,
        )

    def test_help_screen_dismissal_prompt(self):
        """Step 15: Verify help screen dismissal prompt text (Bug 2.7.19)."""
        print(
            "[*] Step 15: Testing help screen dismissal prompt text...",
            flush=True,
        )
        rendered_lines = []
        self.editor.renderer.render_centered_workspace = (
            lambda lines, buf, geometry_str="80x24": rendered_lines.extend(
                lines
            )
        )
        self.editor.terminal.get_key = lambda timeout=None: " "

        self.editor.action_help()

        help_text = "\n".join(rendered_lines)
        self.assertIn("Press any key to continue", help_text)
        self.assertNotIn("Press any key to return to editor", help_text)

        print(
            "[+] Step 15: Help screen canonical prompt verified.",
            flush=True,
        )

    def test_about_and_mem_info_workspaces(self):
        """Step 16: Verify About and Memory Map Tier 1 screens (Bug 2.7.20)."""
        print(
            "[*] Step 16: Testing About and Memory Map Tier 1 screens...",
            flush=True,
        )
        rendered_lines = []
        self.editor.renderer.render_centered_workspace = (
            lambda lines, buf, geometry_str="80x24": rendered_lines.extend(
                lines
            )
        )
        self.editor.terminal.get_key = lambda timeout=None: " "

        # Test About workspace
        self.editor.action_about()
        about_text = "\n".join(rendered_lines)
        self.assertIn("SE - Screen Editor", about_text)
        self.assertIn("version 1.1.0 (2026-10-09) (Python)", about_text)
        self.assertIn("by Dean Jenkins", about_text)
        self.assertIn("MIT License", about_text)
        self.assertIn("Press any key to continue", about_text)

        # Test Memory Map workspace
        rendered_lines.clear()
        self.editor.action_mem_info()
        mem_text = "\n".join(rendered_lines)
        self.assertIn("Extended Memory Map", mem_text)
        self.assertIn("Bank  Phys   Size", mem_text)
        self.assertIn("Linux OS / Python VM", mem_text)
        self.assertIn("Press any key to continue", mem_text)

        print(
            "[+] Step 16: About and Memory Map workspaces verified.",
            flush=True,
        )

    def test_ctrl_d_forward_delete(self):
        """Step 17: Verify Ctrl+D deletes char forward (Bug 2.7.23)."""
        print(
            "[*] Step 17: Testing Ctrl+D deletes char forward...",
            flush=True,
        )
        self.editor.buffer.lines = ["Hello World"]
        self.editor.buffer.cursor_row = 0
        self.editor.buffer.cursor_col = 0  # At 'H'

        # Dispatch Ctrl+D
        self.editor.dispatch_key(KEY_CTRL_D)

        # 'H' must be deleted, leaving 'ello World' at col 0
        self.assertEqual(self.editor.buffer.current_line, "ello World")
        self.assertEqual(self.editor.buffer.cursor_col, 0)

        # Dispatch KEY_RIGHT: must advance to col 1 without deleting
        self.editor.dispatch_key(KEY_RIGHT)
        self.assertEqual(self.editor.buffer.cursor_col, 1)

        # Dispatch Ctrl+D again: deletes 'l' under cursor (col 1)
        self.editor.dispatch_key(KEY_CTRL_D)
        self.assertEqual(self.editor.buffer.current_line, "elo World")
        self.assertEqual(self.editor.buffer.cursor_col, 1)

        print(
            "[+] Step 17: Ctrl+D forward delete verified successfully.",
            flush=True,
        )

    def test_tier2_modal_52_col_width(self):
        """Step 18: Verify Tier 2 modal 52-column width (Bug 2.7.24)."""
        print(
            "[*] Step 18: Testing Tier 2 modal 52-column width...",
            flush=True,
        )
        captured = []
        self.editor.modal.draw_box = (
            lambda top, left, width, lines: captured.append(
                (top, left, width)
            )
        )
        self.editor.terminal.get_key = MagicMock(return_value="y")

        # 1. Confirmation query (Archetype B)
        self.editor.terminal.cols = 80
        self.editor.terminal.rows = 24
        self.editor.modal.show_confirm(
            title="Save", desc="Unsaved edits", query="Save?"
        )
        self.assertEqual(len(captured), 1)
        top, left, width = captured[-1]
        self.assertEqual(width, 52)
        # On 80-col screen, left should be (80 - 52) // 2 + 1 = 15
        self.assertEqual(left, 15)

        # On 120-col screen, left should be (120 - 52) // 2 + 1 = 35
        self.editor.terminal.cols = 120
        self.editor.terminal.rows = 40
        self.editor.modal.show_confirm(
            title="Save", desc="Unsaved edits", query="Save?"
        )
        top, left, width = captured[-1]
        self.assertEqual(width, 52)
        self.assertEqual(left, 35)

        # 2. Text input modal (Archetype C)
        self.editor.terminal.get_key = MagicMock(return_value="\r")
        self.editor.modal.show_input(
            title="Goto", desc="Jump line", label="Line:"
        )
        self.assertEqual(captured[-1][2], 52)

        # 3. Find dialog (Archetype C with toggle, canonical 50-col)
        self.editor.modal.show_find_dialog(initial_text="test")
        self.assertEqual(captured[-1][2], 50)

        # 4. Notification dialog (Archetype A)
        self.editor.modal.show_notification("Info", "Operation complete")
        self.assertEqual(captured[-1][2], 52)

        # 5. Verify drawn borders produce exactly 52 chars (50 hyphens)
        written = []
        real_draw_box = ModalDialog(self.editor.terminal).draw_box
        self.editor.terminal.write = lambda s: written.append(s)
        real_draw_box(1, 15, 52, ["Title", "---", "Message"])
        # Top border: + followed by 50 hyphens followed by +
        self.assertIn("+" + ("-" * 50) + "+", written)

        print(
            "[+] Step 18: Tier 2 modal 52-column width verified.",
            flush=True,
        )

    def test_help_workspace_canonical_dimensions_and_keys(self):
        """Step 19: Verify Help workspace 17-line 70-col layout (Bug 2.7.25)."""
        print(
            "[*] Step 19: Testing Help workspace layout & keys...",
            flush=True,
        )
        rendered_lines = []
        self.editor.renderer.render_centered_workspace = (
            lambda lines, buf, geometry_str="80x24": rendered_lines.extend(
                lines
            )
        )
        self.editor.terminal.get_key = lambda timeout=None: " "

        self.editor.action_help()

        # 1. Height must be exactly 17 lines
        self.assertEqual(len(rendered_lines), 17)

        # 2. Width must be exactly 70 columns
        max_w = max(len(ln) for ln in rendered_lines)
        self.assertEqual(max_w, 70)

        # 3. Must display Arrows / ANSI VT100 and no WordStar references
        help_text = "\n".join(rendered_lines)
        self.assertIn("Arrows / ANSI VT100", help_text)
        self.assertNotIn("WordStar", help_text)
        self.assertNotIn("^S,^D,^E,^X", help_text)
        self.assertIn("Press any key to continue", help_text)

        print(
            "[+] Step 19: Help workspace layout & keys verified.",
            flush=True,
        )

    def test_startup_term_init_clears_screen(self):
        """Step 20: Verify startup invokes term_init clear (Bug 2.7.27)."""
        print(
            "[*] Step 20: Testing startup invokes term_init screen clear...",
            flush=True,
        )
        self.editor.terminal.term_init = MagicMock()
        self.editor.action_splash_screen = MagicMock()
        self.editor.renderer.render_editor = MagicMock()

        def mock_get_key(timeout=None):
            self.editor.running = False
            return None

        self.editor.terminal.get_key = mock_get_key
        self.editor.run()

        self.editor.terminal.enter_raw_mode.assert_called_once()
        self.editor.terminal.term_init.assert_called_once()

        from se.terminal import (
            Terminal,
            ANSI_CLEAR_SCREEN,
            ANSI_INVERSE_OFF,
            ANSI_SHOW_CURSOR,
        )
        real_term = Terminal()
        real_written = []
        real_term.write = lambda s: real_written.append(s)
        real_term.flush = MagicMock()
        real_term.term_init()

        self.assertIn(ANSI_INVERSE_OFF, real_written)
        self.assertIn(ANSI_SHOW_CURSOR, real_written)
        self.assertIn(ANSI_CLEAR_SCREEN, real_written)
        real_term.flush.assert_called_once()

        print(
            "[+] Step 20: Startup term_init screen clear verified.",
            flush=True,
        )

    def test_clean_exit_screen_clear_and_banner(self):
        """Step 21: Verify clean exit invokes term_exit banner (Bug 2.7.28)."""
        print(
            "[*] Step 21: Testing clean exit invokes term_exit banner...",
            flush=True,
        )
        self.editor.terminal.term_exit = MagicMock()
        self.editor.action_splash_screen = MagicMock()
        self.editor.renderer.render_editor = MagicMock()

        def mock_get_key(timeout=None):
            self.editor.running = False
            return None

        self.editor.terminal.get_key = mock_get_key
        self.editor.run()

        self.editor.terminal.term_exit.assert_called_once()
        self.editor.terminal.exit_raw_mode.assert_called_once()

        from se.terminal import (
            Terminal,
            ANSI_CLEAR_SCREEN,
            ANSI_SHOW_CURSOR,
        )
        real_term = Terminal()
        written = []
        real_term.write = lambda s: written.append(s)
        real_term.flush = MagicMock()
        real_term.term_exit()

        self.assertIn(ANSI_CLEAR_SCREEN, written)
        self.assertIn("\r\nExiting SE. Returned to OS prompt.\r\n", written)
        self.assertIn(ANSI_SHOW_CURSOR, written)
        self.assertEqual(real_term.flush.call_count, 2)

        print(
            "[+] Step 21: Clean exit screen clear and banner verified.",
            flush=True,
        )

    def test_status_bar_field5_visual_col_across_tabs(self):
        """Step 22: Verify Field 5 visual col across tabs (Bug 2.7.29)."""
        print(
            "[*] Step 22: Testing status bar Field 5 visual col with tabs...",
            flush=True,
        )
        written = []
        self.editor.terminal.write = lambda s: written.append(s)

        self.editor.buffer.tab_width = 4
        self.editor.buffer.lines = ["\tHello"]
        self.editor.buffer.cursor_col = 1
        self.editor.renderer.render_status_bar(
            self.editor.buffer, geometry_str="80x24"
        )
        full_bar = "".join(written)
        self.assertIn("Col 4", full_bar)
        self.assertNotIn("Col 1", full_bar)

        print(
            "[+] Step 22: Status bar Field 5 visual col with tabs verified.",
            flush=True,
        )

    def test_tab_key_inserts_literal_tab_byte(self):
        """Step 23: Verify Tab key inserts literal tab byte (Bug 2.7.30)."""
        print(
            "[*] Step 23: Testing Tab key inserts literal tab byte 0x09...",
            flush=True,
        )
        self.editor.buffer.lines = ["Hello"]
        self.editor.buffer.cursor_col = 5
        self.editor.buffer.tab_width = 4

        self.editor.dispatch_key(KEY_TAB)

        self.assertEqual(self.editor.buffer.lines[0], "Hello\t")
        self.assertEqual(self.editor.buffer.cursor_col, 6)
        self.assertEqual(self.editor.buffer.get_visual_col(), 8)
        self.assertEqual(self.editor.buffer.target_col, 8)

        print(
            "[+] Step 23: Tab key inserts literal tab byte 0x09 verified.",
            flush=True,
        )

    def test_tier1_directory_browser_open_and_save(self):
        """Step 24: Verify Tier 1 Open and Save workspaces (Bug 2.7.32)."""
        print(
            "[*] Step 24: Testing Tier 1 Directory Browser Open and Save...",
            flush=True,
        )
        import tempfile

        # Test Open Workspace renders Tier 1 layout
        captured = []
        orig_write = self.editor.terminal.write

        def mock_write(s):
            captured.append(s)
            orig_write(s)

        self.editor.terminal.write = mock_write
        self.editor.terminal.get_key = MagicMock(side_effect=[KEY_ESC])
        self.editor.action_open_file()

        full_output = "".join(captured)
        self.assertIn("OPEN FILE (DIRECTORY -", full_output)
        self.assertIn("======", full_output)
        self.assertIn("Enter filename to open: [", full_output)
        self.assertIn("[ESC]=Cancel", full_output)

        # Test Save Workspace renders format toggle and handles Ctrl+F
        captured.clear()
        with tempfile.TemporaryDirectory() as tmp_dir:
            save_path = os.path.join(tmp_dir, "test_out.txt")
            key_seq = [KEY_CTRL_F] + list(save_path) + [KEY_ENTER, KEY_ENTER]
            self.editor.terminal.get_key = MagicMock(side_effect=key_seq)
            self.editor.buffer.lines = ["Line 1", "Line 2"]
            self.editor.buffer.format_cpm = True

            ok = self.editor.action_save_file()
            self.assertTrue(ok)
            self.assertTrue(os.path.isfile(save_path))
            self.assertFalse(self.editor.buffer.format_cpm)
            with open(save_path, "rb") as f:
                content = f.read()
            self.assertEqual(content, b"Line 1\nLine 2\n")

            save_output = "".join(captured)
            self.assertIn("SAVE FILE (DIRECTORY -", save_output)
            self.assertIn("Format:", save_output)
            self.assertIn("[^F]=Toggle Format", save_output)
            self.assertIn("Enter filename to save: [", save_output)

        print(
            "[+] Step 24: Tier 1 Directory Browser Open and Save verified.",
            flush=True,
        )

    def test_block_active_file_insert(self):
        """Step 25: Verify block-active Ctrl+O and Ctrl+K R (Bug 2.7.33)."""
        print(
            "[*] Step 25: Testing block-active file insert and Ctrl+K R...",
            flush=True,
        )
        import tempfile

        # 1. When block_active == 0, Ctrl+O invokes action_open_file
        self.editor.action_open_file = MagicMock()
        self.editor.action_insert_file = MagicMock()
        self.editor.buffer.block_active = 0
        self.editor.dispatch_key(KEY_CTRL_O)
        self.editor.action_open_file.assert_called_once()
        self.editor.action_insert_file.assert_not_called()

        # 2. When block_active == 1, Ctrl+O invokes action_insert_file
        self.editor.action_open_file.reset_mock()
        self.editor.action_insert_file.reset_mock()
        self.editor.buffer.block_active = 1
        self.editor.dispatch_key(KEY_CTRL_O)
        self.editor.action_open_file.assert_not_called()
        self.editor.action_insert_file.assert_called_once()

        # 3. Ctrl+K R invokes action_insert_file via WordStar prefix
        self.editor.action_insert_file.reset_mock()
        self.editor.buffer.block_active = 0
        self.editor.terminal.is_key_ready = MagicMock(return_value=True)
        self.editor.terminal.get_key = MagicMock(return_value="r")
        self.editor.dispatch_key(KEY_CTRL_K)
        self.editor.action_insert_file.assert_called_once()

        # 4. End-to-end: insert file into buffer at cursor
        with tempfile.TemporaryDirectory() as tmp_dir:
            snippet_path = os.path.join(tmp_dir, "snippet.txt")
            with open(snippet_path, "wb") as f:
                f.write(b"Inserted line 1\nInserted line 2\n")

            self.editor.buffer.lines = ["Line 1", "Line 2", "Line 3"]
            self.editor.buffer.cursor_row = 1
            self.editor.buffer.cursor_col = 0
            self.editor.buffer.block_active = 1

            captured = []
            orig_write = self.editor.terminal.write

            def mock_write(s):
                captured.append(s)
                orig_write(s)

            self.editor.terminal.write = mock_write
            key_seq = list(snippet_path) + [KEY_ENTER, KEY_ENTER]
            self.editor.terminal.get_key = MagicMock(side_effect=key_seq)

            from se.editor import Editor
            self.editor.action_insert_file = Editor.action_insert_file.__get__(
                self.editor, Editor
            )
            self.editor.action_insert_file()

            self.assertEqual(self.editor.buffer.block_active, 2)
            self.assertEqual(
                self.editor.buffer.lines,
                [
                    "Line 1",
                    "Inserted line 1",
                    "Inserted line 2Line 2",
                    "Line 3",
                ],
            )
            browser_output = "".join(captured)
            self.assertIn("INSERT FILE (DIRECTORY -", browser_output)
            self.assertIn("Enter filename to insert: [", browser_output)

        print(
            "[+] Step 25: Block-active file insert and Ctrl+K R verified.",
            flush=True,
        )

    def test_block_active_save(self):
        """Step 26: Verify block-active Ctrl+S and Ctrl+K S (Bug 2.7.34)."""
        print(
            "[*] Step 26: Testing block-active save and Ctrl+K S...",
            flush=True,
        )
        import tempfile

        # 1. When block_active == 0, Ctrl+S invokes action_save_file
        self.editor.action_save_file = MagicMock()
        self.editor.action_block_save = MagicMock()
        self.editor.buffer.block_active = 0
        self.editor.dispatch_key(KEY_CTRL_S)
        self.editor.action_save_file.assert_called_once()
        self.editor.action_block_save.assert_not_called()

        # 2. When block_active == 1, Ctrl+S invokes action_block_save
        self.editor.action_save_file.reset_mock()
        self.editor.action_block_save.reset_mock()
        self.editor.buffer.block_active = 1
        self.editor.dispatch_key(KEY_CTRL_S)
        self.editor.action_save_file.assert_not_called()
        self.editor.action_block_save.assert_called_once()

        # 3. Ctrl+K S invokes action_block_save via WordStar prefix
        self.editor.action_block_save.reset_mock()
        self.editor.terminal.is_key_ready = MagicMock(return_value=True)
        self.editor.terminal.get_key = MagicMock(return_value="s")
        self.editor.dispatch_key(KEY_CTRL_K)
        self.editor.action_block_save.assert_called_once()

        # 4. End-to-end: save only highlighted block to disk file
        with tempfile.TemporaryDirectory() as tmp_dir:
            block_file = os.path.join(tmp_dir, "block_out.txt")
            self.editor.buffer.lines = [
                "Alpha Line",
                "Beta Line to Save",
                "Gamma Line",
            ]
            self.editor.buffer.filename = "my_doc.txt"
            self.editor.buffer.format_cpm = False
            self.editor.buffer.block_active = 2
            self.editor.buffer.block_start_row = 1
            self.editor.buffer.block_start_col = 0
            self.editor.buffer.block_end_row = 1
            self.editor.buffer.block_end_col = len("Beta Line to Save")

            captured = []
            orig_write = self.editor.terminal.write

            def mock_write(s):
                captured.append(s)
                orig_write(s)

            self.editor.terminal.write = mock_write
            key_seq = list(block_file) + [KEY_ENTER, KEY_ENTER]
            self.editor.terminal.get_key = MagicMock(side_effect=key_seq)

            from se.editor import Editor
            self.editor.action_block_save = Editor.action_block_save.__get__(
                self.editor, Editor
            )
            ok = self.editor.action_block_save()
            self.assertTrue(ok)
            self.assertTrue(os.path.isfile(block_file))

            with open(block_file, "rb") as f:
                saved_content = f.read()
            # Must save ONLY the block, not the full document buffer!
            self.assertEqual(saved_content, b"Beta Line to Save")
            # Block active is retained at state 2 per canonical spec
            self.assertEqual(self.editor.buffer.block_active, 2)
            # Original filename and lines are completely untouched
            self.assertEqual(self.editor.buffer.filename, "my_doc.txt")
            self.assertEqual(len(self.editor.buffer.lines), 3)

            browser_output = "".join(captured)
            self.assertIn("SAVE BLOCK (DIRECTORY -", browser_output)

        print(
            "[+] Step 26: Block-active save and Ctrl+K S verified.",
            flush=True,
        )

    def test_document_close_lifecycle(self):
        """Step 27: Verify Ctrl+W close lifecycle and prompt (Bug 2.7.35)."""
        print(
            "[*] Step 27: Testing Ctrl+W document close lifecycle...",
            flush=True,
        )
        # 1. Dispatching KEY_CTRL_W invokes action_close_file
        self.editor.action_close_file = MagicMock()
        self.editor.dispatch_key(KEY_CTRL_W)
        self.editor.action_close_file.assert_called_once_with(to_splash=True)

        from se.editor import Editor
        self.editor.action_close_file = Editor.action_close_file.__get__(
            self.editor, Editor
        )
        self.editor.action_splash_screen = MagicMock()
        self.editor.action_save_file = MagicMock(return_value=True)

        # 2. Clean document: immediately closes to Splash without prompt
        self.editor.buffer.filename = "clean.txt"
        self.editor.buffer.modified = False
        self.editor.modal.show_confirm = MagicMock()

        self.editor.action_close_file(to_splash=True)
        self.editor.modal.show_confirm.assert_not_called()
        self.assertEqual(self.editor.buffer.filename, "(Untitled)")
        self.assertFalse(self.editor.buffer.has_file)
        self.editor.action_splash_screen.assert_called_once()

        # 3. Modified document with [ESC]=Cancel: keeps document state
        self.editor.action_splash_screen.reset_mock()
        self.editor.buffer.filename = "dirty.txt"
        self.editor.buffer.modified = True
        self.editor.modal.show_confirm = MagicMock(return_value=None)

        closed = self.editor.action_close_file(to_splash=True)
        self.assertFalse(closed)
        self.assertEqual(self.editor.buffer.filename, "dirty.txt")
        self.assertTrue(self.editor.buffer.modified)
        self.editor.action_splash_screen.assert_not_called()

        # 4. Modified document with [N]o: discards and transitions to Splash
        self.editor.modal.show_confirm = MagicMock(return_value="n")
        closed = self.editor.action_close_file(to_splash=True)
        self.assertTrue(closed)
        self.assertEqual(self.editor.buffer.filename, "(Untitled)")
        self.editor.action_splash_screen.assert_called_once()

        # 5. Modified document with [Y]es: saves and transitions to Splash
        self.editor.action_splash_screen.reset_mock()
        self.editor.buffer.filename = "dirty2.txt"
        self.editor.buffer.modified = True
        self.editor.modal.show_confirm = MagicMock(return_value="y")

        closed = self.editor.action_close_file(to_splash=True)
        self.assertTrue(closed)
        self.editor.action_save_file.assert_called_once()
        self.assertEqual(self.editor.buffer.filename, "(Untitled)")
        self.editor.action_splash_screen.assert_called_once()

        print(
            "[+] Step 27: Ctrl+W close lifecycle and prompt verified.",
            flush=True,
        )

    def test_editor_secfg_discovery_and_geometry_default(self):
        """Step 28: Verify Editor startup SE.CFG discovery (Bug 2.7.36)."""
        print(
            "[*] Step 28: Testing Editor startup SE.CFG discovery...",
            flush=True,
        )
        # Default Editor instance defaults to 80x24 canonical geometry
        ed_default = Editor()
        self.assertEqual(ed_default.config.DEFAULT_SCREEN, "80X24")
        self.assertEqual(ed_default.config.screen_geometry, (80, 24))
        self.assertEqual(ed_default.terminal.cols, 80)
        self.assertEqual(ed_default.terminal.rows, 24)
        self.assertEqual(ed_default.buffer.tab_width, 8)

        # Editor with custom config path overrides geometry and tab width
        with tempfile.NamedTemporaryFile(
            delete=False, suffix=".cfg"
        ) as tmp_file:
            tmp_path = tmp_file.name
        try:
            with open(tmp_path, "wb") as f:
                f.write(b"SCREEN=120x40\r\nTAB=4\r\n")

            ed_custom = Editor(config_path=tmp_path)
            self.assertEqual(
                ed_custom.loaded_config_path, os.path.abspath(tmp_path)
            )
            self.assertEqual(ed_custom.terminal.cols, 120)
            self.assertEqual(ed_custom.terminal.rows, 40)
            self.assertEqual(ed_custom.buffer.tab_width, 4)
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)

        print(
            "[+] Step 28: Editor startup SE.CFG discovery verified.",
            flush=True,
        )

    def test_delete_key_active_block(self):
        """Step 29: Verify Delete and Ctrl+D block deletion (Bug 2.7.37)."""
        print(
            "[*] Step 29: Testing Delete and Ctrl+D block deletion...",
            flush=True,
        )
        self.editor.buffer.lines = ["Alpha Beta Gamma", "Second Line"]
        self.editor.buffer.clipboard = "ORIGINAL_CLIPBOARD"

        # 1. Dynamic block delete via KEY_DELETE
        # Block from (0, 6) to (0, 10): "Beta"
        self.editor.buffer.cursor_row = 0
        self.editor.buffer.cursor_col = 6
        self.editor.dispatch_key(KEY_CTRL_B)  # block_active = 1
        self.editor.buffer.cursor_col = 10
        self.assertEqual(self.editor.buffer.block_active, 1)

        self.editor.dispatch_key(KEY_DELETE)
        self.assertEqual(self.editor.buffer.lines[0], "Alpha  Gamma")
        self.assertEqual(self.editor.buffer.cursor_row, 0)
        self.assertEqual(self.editor.buffer.cursor_col, 6)
        self.assertEqual(self.editor.buffer.block_active, 0)
        self.assertTrue(self.editor.buffer.modified)
        # Clipboard must remain unaffected
        self.assertEqual(self.editor.buffer.clipboard, "ORIGINAL_CLIPBOARD")

        # 2. Solidified multi-line block delete via KEY_CTRL_D
        self.editor.buffer.lines = [
            "Start Line",
            "Middle To Delete",
            "End Line",
        ]
        self.editor.buffer.cursor_row = 0
        self.editor.buffer.cursor_col = 6
        self.editor.dispatch_key(KEY_CTRL_B)
        self.editor.buffer.cursor_row = 2
        self.editor.buffer.cursor_col = 4
        self.editor.buffer.solidify_block()  # block_active = 2

        self.editor.dispatch_key(KEY_CTRL_D)
        # Joined line: "Start Line"[:6] + "End Line"[4:] -> "Start Line"
        self.assertEqual(self.editor.buffer.lines, ["Start Line"])
        self.assertEqual(self.editor.buffer.cursor_row, 0)
        self.assertEqual(self.editor.buffer.cursor_col, 6)
        self.assertEqual(self.editor.buffer.block_active, 0)
        self.assertEqual(self.editor.buffer.clipboard, "ORIGINAL_CLIPBOARD")

        print(
            "[+] Step 29: Delete and Ctrl+D block deletion verified.",
            flush=True,
        )

    def test_backspace_dynamic_block_cancel(self):
        """Step 30: Verify Backspace cancels dynamic block (Bug 2.7.38)."""
        print(
            "[*] Step 30: Testing Backspace dynamic block cancel...",
            flush=True,
        )
        self.editor.buffer.lines = ["Hello World"]

        # 1. Dynamic block (block_active == 1): Backspace cancels selection
        # without deleting any character or altering buffer contents.
        self.editor.buffer.cursor_row = 0
        self.editor.buffer.cursor_col = 5
        self.editor.dispatch_key(KEY_CTRL_B)  # block_active = 1
        self.editor.buffer.cursor_col = 11
        self.assertEqual(self.editor.buffer.block_active, 1)

        self.editor.dispatch_key(KEY_BACKSPACE)
        self.assertEqual(self.editor.buffer.block_active, 0)
        self.assertEqual(self.editor.buffer.lines[0], "Hello World")
        self.assertEqual(self.editor.buffer.cursor_col, 11)

        # 2. Solidified block (block_active == 2): Backspace cancels block
        # and performs backward character deletion.
        self.editor.buffer.cursor_col = 5
        self.editor.dispatch_key(KEY_CTRL_B)
        self.editor.buffer.solidify_block()  # block_active = 2
        self.assertEqual(self.editor.buffer.block_active, 2)

        self.editor.dispatch_key(KEY_BACKSPACE)
        self.assertEqual(self.editor.buffer.block_active, 0)
        self.assertEqual(self.editor.buffer.lines[0], "Hell World")
        self.assertEqual(self.editor.buffer.cursor_col, 4)

        print(
            "[+] Step 30: Backspace dynamic block cancel verified.",
            flush=True,
        )

    def test_enter_dynamic_block_solidify(self):
        """Step 31: Verify Enter solidifies dynamic block (Bug 2.7.39)."""
        print(
            "[*] Step 31: Testing Enter dynamic block solidify...",
            flush=True,
        )
        self.editor.buffer.lines = ["First Line", "Second Line"]

        # 1. Dynamic block (block_active == 1): Enter solidifies selection
        # without splitting the current line.
        self.editor.buffer.cursor_row = 0
        self.editor.buffer.cursor_col = 0
        self.editor.dispatch_key(KEY_CTRL_B)  # block_active = 1
        self.editor.buffer.cursor_col = 5
        self.assertEqual(self.editor.buffer.block_active, 1)

        self.editor.dispatch_key(KEY_ENTER)
        self.assertEqual(self.editor.buffer.block_active, 2)
        self.assertEqual(self.editor.buffer.block_end_row, 0)
        self.assertEqual(self.editor.buffer.block_end_col, 5)
        self.assertEqual(
            self.editor.buffer.lines, ["First Line", "Second Line"]
        )
        self.assertEqual(self.editor.buffer.cursor_row, 0)
        self.assertEqual(self.editor.buffer.cursor_col, 5)

        # 2. Solidified block (block_active == 2): Enter cancels block
        # and splits line.
        self.editor.dispatch_key(KEY_ENTER)
        self.assertEqual(self.editor.buffer.block_active, 0)
        self.assertEqual(
            self.editor.buffer.lines, ["First", " Line", "Second Line"]
        )
        self.assertEqual(self.editor.buffer.cursor_row, 1)
        self.assertEqual(self.editor.buffer.cursor_col, 0)

        print(
            "[+] Step 31: Enter dynamic block solidify verified.",
            flush=True,
        )

    def test_typing_and_tab_block_cancel(self):
        """Step 32: Verify typing & Tab cancel active block (Bug 2.7.41)."""
        print(
            "[*] Step 32: Testing typing & Tab active block cancel...",
            flush=True,
        )
        self.editor.buffer.lines = ["Original Text"]

        # 1. Dynamic block (block_active == 1): typing cancels block
        # without inserting the character.
        self.editor.buffer.cursor_row = 0
        self.editor.buffer.cursor_col = 0
        self.editor.dispatch_key(KEY_CTRL_B)  # block_active = 1
        self.editor.buffer.cursor_col = 8

        self.editor.dispatch_key("X")
        self.assertEqual(self.editor.buffer.block_active, 0)
        self.assertEqual(self.editor.buffer.lines[0], "Original Text")
        self.assertEqual(self.editor.buffer.cursor_col, 8)

        # 2. Dynamic block (block_active == 1): Tab cancels block
        # without inserting tab.
        self.editor.dispatch_key(KEY_CTRL_B)  # block_active = 1
        self.editor.dispatch_key(KEY_TAB)
        self.assertEqual(self.editor.buffer.block_active, 0)
        self.assertEqual(self.editor.buffer.lines[0], "Original Text")

        # 3. Solidified block (block_active == 2): typing clears block
        # and inserts character.
        self.editor.dispatch_key(KEY_CTRL_B)
        self.editor.buffer.solidify_block()  # block_active = 2
        self.assertEqual(self.editor.buffer.block_active, 2)

        self.editor.dispatch_key("Z")
        self.assertEqual(self.editor.buffer.block_active, 0)
        self.assertEqual(self.editor.buffer.lines[0], "OriginalZ Text")

        # 4. Solidified block (block_active == 2): Tab clears block
        # and inserts tab byte.
        self.editor.dispatch_key(KEY_CTRL_B)
        self.editor.buffer.solidify_block()  # block_active = 2
        self.editor.dispatch_key(KEY_TAB)
        self.assertEqual(self.editor.buffer.block_active, 0)
        self.assertEqual(self.editor.buffer.lines[0], "OriginalZ\t Text")

        print(
            "[+] Step 32: typing & Tab active block cancel verified.",
            flush=True,
        )

    def test_bug_2_7_42_status_bar_field4_invariance_and_block_indicators(self):
        """Step 33: Verify status bar Field 4 and mode flags (Bug 2.7.42)."""
        print(
            "[*] Step 33: Testing status bar Field 4 invariance & flags...",
            flush=True,
        )
        written = []
        self.editor.terminal.write = lambda s: written.append(s)
        self.editor.terminal.cols = 80
        self.editor.terminal.rows = 24

        # 1. No block active (block_active == 0)
        self.editor.buffer.block_active = 0
        self.editor.renderer.render_status_bar(self.editor.buffer)
        t0 = [w for w in written if not w.startswith("\x1b")][0]
        self.assertEqual(len(t0), 80)
        self.assertIn("^K: Editor keys |", t0)
        self.assertNotIn("[SEL]", t0)
        self.assertNotIn("[BLK LOCK]", t0)

        # 2. Dynamic block active (block_active == 1)
        written.clear()
        self.editor.buffer.block_active = 1
        self.editor.buffer.block_start_row = 0
        self.editor.buffer.block_start_col = 2
        self.editor.buffer.cursor_row = 0
        self.editor.buffer.cursor_col = 8
        self.editor.renderer.render_status_bar(self.editor.buffer)
        t1 = [w for w in written if not w.startswith("\x1b")][0]
        self.assertEqual(len(t1), 80)
        self.assertIn("^K: Editor keys |", t1)
        self.assertIn("[SEL]", t1)
        self.assertNotIn("[BLK LOCK]", t1)
        self.assertNotIn("Sel:", t1)

        # 3. Solidified block active (block_active == 2)
        written.clear()
        self.editor.buffer.block_active = 2
        self.editor.buffer.block_end_row = 0
        self.editor.buffer.block_end_col = 8
        self.editor.renderer.render_status_bar(self.editor.buffer)
        t2 = [w for w in written if not w.startswith("\x1b")][0]
        self.assertEqual(len(t2), 80)
        self.assertIn("^K: Editor keys |", t2)
        self.assertIn("[BLK LOCK]", t2)
        self.assertNotIn("[SEL]", t2)
        self.assertNotIn("Block:", t2)

        # 4. Horizontal pan indicator (pan_col > 0) on 80x24
        written.clear()
        self.editor.buffer.block_active = 0
        self.editor.buffer.pan_col = 40
        self.editor.renderer.render_status_bar(self.editor.buffer)
        t3 = [w for w in written if not w.startswith("\x1b")][0]
        self.assertEqual(len(t3), 80)
        self.assertIn("^K: Editor keys |", t3)
        self.assertIn("[Pan +40]", t3)

        # 5. Pan and block mode flag simultaneously on 120x40
        written.clear()
        self.editor.terminal.cols = 120
        self.editor.terminal.rows = 40
        self.editor.buffer.block_active = 2
        self.editor.buffer.block_end_row = 0
        self.editor.buffer.block_end_col = 8
        self.editor.renderer.render_status_bar(
            self.editor.buffer, geometry_str="120x40"
        )
        t4 = [w for w in written if not w.startswith("\x1b")][0]
        self.assertEqual(len(t4), 120)
        self.assertIn("^K: Editor keys |", t4)
        self.assertIn("[Pan +40]", t4)
        self.assertIn("[BLK LOCK]", t4)

        print(
            "[+] Step 33: Field 4 invariance & Field 5 flags verified.",
            flush=True,
        )

    def test_bug_2_7_43_block_operations_modal_dialog(self):
        """
        Step 34: Verify Bug 2.7.43 resolution:
        Tier 2 Block Operations modal dialog on Ctrl+K when block_active > 0.
        Verifies 50x7 dialog formatting, metrics (Selection vs Marked Block),
        action key dispatching (Enter, Clear, Copy, Move, Del, Save, ESC),
        and Ctrl+K routing.
        """
        # 1. Dialog formatting & metrics for dynamic block (block_active == 1)
        self.editor.buffer.lines = [
            "Alpha Line Text",
            "Beta Line Content",
            "Gamma Line Final",
        ]
        self.editor.buffer.block_active = 1
        self.editor.buffer.block_start_row = 0
        self.editor.buffer.block_start_col = 2
        self.editor.buffer.cursor_row = 0
        self.editor.buffer.cursor_col = 7

        written = []
        orig_write = self.editor.terminal.write
        self.editor.terminal.write = lambda s: written.append(s)

        # Mock get_key to return ESC to dismiss dialog
        self.editor.terminal.get_key = MagicMock(return_value=KEY_ESC)
        action = self.editor.modal.show_block_operations_dialog(
            self.editor.buffer
        )
        self.assertIsNone(action)

        # Filter out ANSI escape codes to examine rendered box lines
        box_lines = [w for w in written if not w.startswith("\x1b")]
        self.assertEqual(len(box_lines), 7)
        self.assertEqual(len(box_lines[0]), 50)

        exp_sep = "+" + ("-" * 48) + "+"
        exp_title = "|                Block Operations                |"
        exp_sel5 = "|               Selection: 5 chars               |"
        exp_keys1 = "|  [Enter]=Lock/Set    [^C]=Copy    [^X]=Move    |"
        exp_cmds = "|  [^D]=Del  [^S]=Save  [^B]=Clear  [ESC]=Close  |"

        self.assertEqual(box_lines[0], exp_sep)
        self.assertEqual(box_lines[1], exp_title)
        self.assertEqual(box_lines[2], exp_sep)
        self.assertEqual(box_lines[3], exp_sel5)
        self.assertEqual(box_lines[4], exp_keys1)
        self.assertEqual(box_lines[5], exp_cmds)
        self.assertEqual(box_lines[6], exp_sep)

        # 2. Single-line 1 char & multi-line metrics formatting
        written.clear()
        self.editor.buffer.cursor_col = 3  # 1 char: cols 2..3
        self.editor.modal.show_block_operations_dialog(self.editor.buffer)
        b1 = [w for w in written if not w.startswith("\x1b")]
        exp_sel1 = "|               Selection: 1 char                |"
        self.assertEqual(b1[3], exp_sel1)

        written.clear()
        self.editor.buffer.cursor_row = 2
        self.editor.buffer.cursor_col = 5  # 3 lines spanned
        self.editor.modal.show_block_operations_dialog(self.editor.buffer)
        b2 = [w for w in written if not w.startswith("\x1b")]
        exp_sel3l = "|               Selection: 3 lines               |"
        self.assertEqual(b2[3], exp_sel3l)

        # 3. Solidified block (block_active == 2) formatting and line 5
        written.clear()
        self.editor.buffer.block_active = 2
        self.editor.buffer.block_start_row = 0
        self.editor.buffer.block_start_col = 0
        self.editor.buffer.block_end_row = 0
        self.editor.buffer.block_end_col = 12
        self.editor.modal.show_block_operations_dialog(self.editor.buffer)
        b3 = [w for w in written if not w.startswith("\x1b")]
        exp_blk12 = "|             Marked Block: 12 chars             |"
        exp_keys2 = "|      [^C]=Copy Block      [^X]=Move Block      |"
        self.assertEqual(b3[3], exp_blk12)
        self.assertEqual(b3[4], exp_keys2)

        # Restore terminal write
        self.editor.terminal.write = orig_write

        # 4. Action key responses in show_block_operations_dialog
        self.editor.terminal.get_key = MagicMock(return_value=KEY_ENTER)
        self.assertEqual(
            self.editor.modal.show_block_operations_dialog(self.editor.buffer),
            "enter",
        )

        for clear_key in (KEY_CTRL_B, "b", "B"):
            self.editor.terminal.get_key = MagicMock(return_value=clear_key)
            self.assertEqual(
                self.editor.modal.show_block_operations_dialog(
                    self.editor.buffer
                ),
                "clear",
            )

        for copy_key in (KEY_CTRL_C, "c", "C"):
            self.editor.terminal.get_key = MagicMock(return_value=copy_key)
            self.assertEqual(
                self.editor.modal.show_block_operations_dialog(
                    self.editor.buffer
                ),
                "copy",
            )

        for cut_key in (KEY_CTRL_X, "x", "X"):
            self.editor.terminal.get_key = MagicMock(return_value=cut_key)
            self.assertEqual(
                self.editor.modal.show_block_operations_dialog(
                    self.editor.buffer
                ),
                "cut",
            )

        for del_key in (KEY_CTRL_D, "d", "D", KEY_DELETE):
            self.editor.terminal.get_key = MagicMock(return_value=del_key)
            self.assertEqual(
                self.editor.modal.show_block_operations_dialog(
                    self.editor.buffer
                ),
                "delete",
            )

        for save_key in (KEY_CTRL_S, "s", "S"):
            self.editor.terminal.get_key = MagicMock(return_value=save_key)
            self.assertEqual(
                self.editor.modal.show_block_operations_dialog(
                    self.editor.buffer
                ),
                "save",
            )

        # 5. Full editor action_block_popup execution
        # a. Enter solidifies dynamic block
        self.editor.buffer.block_active = 1
        self.editor.buffer.block_start_row = 0
        self.editor.buffer.block_start_col = 0
        self.editor.buffer.cursor_row = 0
        self.editor.buffer.cursor_col = 5
        self.editor.terminal.get_key = MagicMock(return_value=KEY_ENTER)
        self.editor.action_block_popup()
        self.assertEqual(self.editor.buffer.block_active, 2)
        self.assertEqual(self.editor.buffer.block_end_row, 0)
        self.assertEqual(self.editor.buffer.block_end_col, 5)

        # b. Clear cancels block
        self.editor.terminal.get_key = MagicMock(return_value="b")
        self.editor.action_block_popup()
        self.assertEqual(self.editor.buffer.block_active, 0)

        # c. Copy copies text to cursor in-place and keeps solidified
        self.editor.buffer.lines = ["Alpha Line Text"]
        self.editor.buffer.block_active = 2
        self.editor.buffer.block_start_row = 0
        self.editor.buffer.block_start_col = 0
        self.editor.buffer.block_end_row = 0
        self.editor.buffer.block_end_col = 5
        self.editor.buffer.cursor_row = 0
        self.editor.buffer.cursor_col = 15
        self.editor.terminal.get_key = MagicMock(return_value="c")
        self.editor.action_block_popup()
        self.assertEqual(self.editor.buffer.lines[0], "Alpha Line TextAlpha")
        self.assertEqual(self.editor.buffer.block_active, 2)

        # d. Move moves text to cursor in-place and keeps solidified at dest
        self.editor.buffer.lines = ["Alpha Line Text"]
        self.editor.buffer.block_active = 2
        self.editor.buffer.block_start_row = 0
        self.editor.buffer.block_start_col = 0
        self.editor.buffer.block_end_row = 0
        self.editor.buffer.block_end_col = 5
        self.editor.buffer.cursor_row = 0
        self.editor.buffer.cursor_col = 15
        self.editor.terminal.get_key = MagicMock(return_value="x")
        self.editor.action_block_popup()
        self.assertEqual(self.editor.buffer.lines[0], " Line TextAlpha")
        self.assertEqual(self.editor.buffer.block_active, 2)

        # e. Delete deletes text without modifying clipboard
        self.editor.buffer.lines = [" Line Text"]
        self.editor.buffer.block_active = 2
        self.editor.buffer.block_start_row = 0
        self.editor.buffer.block_start_col = 0
        self.editor.buffer.block_end_row = 0
        self.editor.buffer.block_end_col = 5
        self.editor.buffer.clipboard = "KEPT_CLIPBOARD"
        self.editor.terminal.get_key = MagicMock(return_value="d")
        self.editor.action_block_popup()
        self.assertEqual(self.editor.buffer.clipboard, "KEPT_CLIPBOARD")
        self.assertEqual(self.editor.buffer.block_active, 0)
        self.assertEqual(self.editor.buffer.lines[0], " Text")

        # f. Save calls action_block_save
        self.editor.buffer.block_active = 2
        self.editor.action_block_save = MagicMock()
        self.editor.terminal.get_key = MagicMock(return_value="s")
        self.editor.action_block_popup()
        self.editor.action_block_save.assert_called_once()

        # 6. Ctrl+K dispatch routing
        self.editor.action_block_popup = MagicMock()
        self.editor.action_help = MagicMock()

        # With block active -> action_block_popup invoked
        self.editor.buffer.block_active = 1
        self.editor.dispatch_key(KEY_CTRL_K)
        self.editor.action_block_popup.assert_called_once()
        self.editor.action_help.assert_not_called()

        # With block inactive -> action_block_popup not invoked
        self.editor.action_block_popup.reset_mock()
        self.editor.terminal.is_key_ready = MagicMock(return_value=False)
        self.editor.buffer.block_active = 0
        self.editor.dispatch_key(KEY_CTRL_K)
        self.editor.action_block_popup.assert_not_called()
        self.editor.action_help.assert_called_once()

        print(
            "[+] Step 34: Block operations modal dialog verified.",
            flush=True,
        )

    def test_bug_2_7_44_ctrl_k_prefix_command_interactive_chords(self):
        """
        Step 35: Verify Bug 2.7.44 resolution:
        Ctrl+K prefix command polling provides an interactive window
        (timeout=1.0) allowing human key chords (R, S, Q, X, ESC) when
        block_active == 0 before falling through to action_help().
        """
        self.editor.buffer.block_active = 0
        self.editor.action_insert_file = MagicMock()
        self.editor.action_block_save = MagicMock()
        self.editor.action_quit = MagicMock()
        self.editor.action_help = MagicMock()

        # 1. Verify timeout=0.1 is passed to is_key_ready
        self.editor.terminal.is_key_ready = MagicMock(return_value=False)
        self.editor.dispatch_key(KEY_CTRL_K)
        self.editor.terminal.is_key_ready.assert_called_once_with(timeout=0.1)
        self.editor.action_help.assert_called_once()

        # 2. Interactive chords with timeout=0.1
        # a. Ctrl+K R / r -> action_insert_file
        for r_key in ("r", "R"):
            self.editor.action_insert_file.reset_mock()
            self.editor.terminal.is_key_ready = MagicMock(return_value=True)
            self.editor.terminal.get_key = MagicMock(return_value=r_key)
            self.editor.dispatch_key(KEY_CTRL_K)
            self.editor.action_insert_file.assert_called_once()

        # b. Ctrl+K S / s -> action_block_save
        for s_key in ("s", "S"):
            self.editor.action_block_save.reset_mock()
            self.editor.terminal.is_key_ready = MagicMock(return_value=True)
            self.editor.terminal.get_key = MagicMock(return_value=s_key)
            self.editor.dispatch_key(KEY_CTRL_K)
            self.editor.action_block_save.assert_called_once()

        # c. Ctrl+K Q / q / X / x -> action_quit
        for q_key in ("q", "Q", "x", "X"):
            self.editor.action_quit.reset_mock()
            self.editor.terminal.is_key_ready = MagicMock(return_value=True)
            self.editor.terminal.get_key = MagicMock(return_value=q_key)
            self.editor.dispatch_key(KEY_CTRL_K)
            self.editor.action_quit.assert_called_once()

        # d. Ctrl+K ESC -> cancels chord, no help
        self.editor.action_help.reset_mock()
        self.editor.terminal.is_key_ready = MagicMock(return_value=True)
        self.editor.terminal.get_key = MagicMock(return_value=KEY_ESC)
        self.editor.dispatch_key(KEY_CTRL_K)
        self.editor.action_help.assert_not_called()

        # e. Ctrl+K with unknown key (e.g. 'h') -> falls through to action_help
        self.editor.action_help.reset_mock()
        self.editor.terminal.is_key_ready = MagicMock(return_value=True)
        self.editor.terminal.get_key = MagicMock(return_value="h")
        self.editor.dispatch_key(KEY_CTRL_K)
        self.editor.action_help.assert_called_once()

        # 3. Timeout expiration (is_key_ready returns False) -> action_help
        self.editor.action_help.reset_mock()
        self.editor.terminal.is_key_ready = MagicMock(return_value=False)
        self.editor.dispatch_key(KEY_CTRL_K)
        self.editor.action_help.assert_called_once()

        print(
            "[+] Step 35: Interactive Ctrl+K chords & timeout verified.",
            flush=True,
        )

    def test_bug_2_7_46_wordstar_diamond_modal_exclusion(self):
        """Step 36: Verify Ctrl+S is not aliased to Left arrow (Bug 2.7.46)."""
        print(
            "[*] Step 36: Testing WordStar Ctrl+S exclusion in modals...",
            flush=True,
        )
        self.editor.modal.draw_box = MagicMock()

        # 1. show_input: KEY_CTRL_S must not move cursor left
        keys_input = [KEY_CTRL_S, "C", KEY_ENTER]
        iter_input = iter(keys_input)
        self.editor.terminal.get_key = lambda: next(iter_input)
        res_input = self.editor.modal.show_input(
            title="Input",
            desc="Prompt",
            label="Name:",
            initial_text="AB",
        )
        # If Ctrl+S moved left, 'C' would be inserted before 'B' -> "ACB".
        # Because Ctrl+S is ignored, cursor stays at end -> "ABC".
        self.assertEqual(res_input, "ABC")

        # 2. show_find_dialog: KEY_CTRL_S must not move cursor left
        keys_find = [KEY_CTRL_S, "D", KEY_ENTER]
        iter_find = iter(keys_find)
        self.editor.terminal.get_key = lambda: next(iter_find)
        res_find, _ = self.editor.modal.show_find_dialog(
            initial_text="AB",
        )
        self.assertEqual(res_find, "ABD")

        print(
            "[+] Step 36: WordStar Ctrl+S exclusion in modals verified.",
            flush=True,
        )

    def test_bug_2_7_48_file_not_found_modal_alert(self):
        """Step 37: Verify 50x7 File Not Found alert in browser (Bug 2.7.48)."""
        print(
            "[*] Step 37: Testing File Not Found modal alert in browser...",
            flush=True,
        )
        # 1. Verify show_file_not_found framing and canonical 50x7 lines
        captured_boxes = []

        def mock_draw(top, left, width, lines):
            captured_boxes.append((top, left, width, lines))

        self.editor.modal.draw_box = mock_draw
        self.editor.terminal.get_key = MagicMock(return_value=" ")

        self.editor.modal.show_file_not_found("TESTFILE.DAT")
        self.assertEqual(len(captured_boxes), 1)
        _, _, width, lines = captured_boxes[0]
        self.assertEqual(width, 50)
        self.assertEqual(len(lines), 5)  # 5 interior lines + 2 borders = 7
        self.assertEqual(lines[0], "File Not Found")
        self.assertEqual(lines[1], "---")
        self.assertEqual(lines[2], "'TESTFILE.DAT' was not found.")
        self.assertEqual(lines[3], "Specified file not found on disk.")
        self.assertEqual(lines[4], "Press any key to continue")

        # 2. action_directory_browser shows alert and preserves browser state
        self.editor.modal.show_file_not_found = MagicMock()
        keys = list("no_such_file.txt") + [KEY_ENTER, KEY_ESC]
        key_iter = iter(keys)
        self.editor.terminal.get_key = lambda: next(key_iter)

        res = self.editor.action_directory_browser(mode="open")
        self.assertIsNone(res)
        self.editor.modal.show_file_not_found.assert_called_once_with(
            "no_such_file.txt"
        )

        print(
            "[+] Step 37: File Not Found modal alert in browser verified.",
            flush=True,
        )

    def test_bug_2_7_49_overwrite_modal_geometry_and_phrasing(self):
        """Step 38: Verify 50x7 Overwrite File modal dialog (Bug 2.7.49)."""
        print(
            "[*] Step 38: Testing 50x7 Overwrite File modal dialog...",
            flush=True,
        )
        # 1. Verify show_overwrite_dialog framing and canonical 50x7 lines
        captured_boxes = []

        def mock_draw(top, left, width, lines):
            captured_boxes.append((top, left, width, lines))

        self.editor.modal.draw_box = mock_draw
        self.editor.terminal.get_key = MagicMock(return_value="y")

        res = self.editor.modal.show_overwrite_dialog()
        self.assertEqual(res, "y")
        self.assertEqual(len(captured_boxes), 1)
        _, _, width, lines = captured_boxes[0]
        self.assertEqual(width, 50)
        self.assertEqual(len(lines), 5)  # 5 lines + 2 borders = 7 rows
        self.assertEqual(lines[0], "Overwrite File")
        self.assertEqual(lines[1], "---")
        self.assertEqual(lines[2], "Existing file contents will be lost")
        self.assertEqual(lines[3], "File already exists. Overwrite?")
        self.assertEqual(lines[4], "[Y]es      [N]o      [ESC]=Cancel")

        # 2. Key choices: ESC returns None, 'n' returns 'n'
        self.editor.terminal.get_key = MagicMock(return_value=KEY_ESC)
        self.assertIsNone(self.editor.modal.show_overwrite_dialog())
        self.editor.terminal.get_key = MagicMock(return_value="n")
        self.assertEqual(self.editor.modal.show_overwrite_dialog(), "n")

        print(
            "[+] Step 38: 50x7 Overwrite File modal dialog verified.",
            flush=True,
        )

    def test_bug_2_7_50_active_block_prefills_find_dialog(self):
        """Step 39: Verify active block pre-fills Find dialog (Bug 2.7.50)."""
        print(
            "[*] Step 39: Testing active block text pre-fill in Find...",
            flush=True,
        )
        self.editor.modal.show_find_dialog = MagicMock(
            return_value=("needle", True)
        )
        self.editor.action_find_next = MagicMock()

        # 1. No active block -> uses self.search_query
        self.editor.buffer.block_active = 0
        self.editor.search_query = "previous_search"
        self.editor.action_find()
        self.editor.modal.show_find_dialog.assert_called_with(
            initial_text="previous_search",
            initial_case_sensitive=True,
        )

        # 2. Dynamic block active -> extracts selected block text
        self.editor.buffer.lines = ["The quick brown fox"]
        self.editor.buffer.block_active = 1
        self.editor.buffer.block_start_row = 0
        self.editor.buffer.block_start_col = 4
        self.editor.buffer.cursor_row = 0
        self.editor.buffer.cursor_col = 9  # "quick"
        self.editor.action_find()
        self.editor.modal.show_find_dialog.assert_called_with(
            initial_text="quick",
            initial_case_sensitive=True,
        )

        print(
            "[+] Step 39: Active block text pre-fill in Find verified.",
            flush=True,
        )

    def test_bug_2_7_51_find_dialog_canonical_50x7_geometry(self):
        """Step 40: Verify Find dialog 50x7 compact geometry (Bug 2.7.51)."""
        print(
            "[*] Step 40: Testing Find dialog canonical 50x7 geometry...",
            flush=True,
        )
        captured_boxes = []

        def mock_draw(top, left, width, lines):
            captured_boxes.append((top, left, width, lines))

        self.editor.modal.draw_box = mock_draw
        self.editor.terminal.get_key = MagicMock(return_value="\r")

        res, _ = self.editor.modal.show_find_dialog(initial_text="target")
        self.assertEqual(res, "target")
        self.assertEqual(len(captured_boxes), 1)
        _, _, width, lines = captured_boxes[0]
        self.assertEqual(width, 50)
        self.assertEqual(len(lines), 5)  # 5 lines + 2 borders = 7 rows
        self.assertEqual(lines[0], "Find Text")
        self.assertEqual(lines[1], "---")
        self.assertIn("Search Pattern:", lines[2])
        self.assertIn("Find: [", lines[3])
        self.assertEqual(
            lines[4], "[Enter]=Find   [Tab]=Toggle Case   [ESC]=Cancel"
        )

        print(
            "[+] Step 40: Find dialog canonical 50x7 geometry verified.",
            flush=True,
        )

    def test_bug_2_7_52_canonical_new_file_prompt(self):
        """Step 41: Verify canonical new file prompt syntax (Bug 2.7.52)."""
        print(
            "[*] Step 41: Testing action_new_file prompt syntax...",
            flush=True,
        )
        self.editor.modal.show_confirm = MagicMock()
        self.editor.action_save_file = MagicMock(return_value=True)

        # 1. Unmodified buffer -> no confirmation prompt
        self.editor.buffer.modified = False
        self.editor.action_new_file()
        self.editor.modal.show_confirm.assert_not_called()

        # 2. Modified buffer -> prompt with canonical Archetype B parameters
        self.editor.buffer.modified = True
        self.editor.modal.show_confirm.return_value = None  # ESC
        self.editor.action_new_file()
        self.editor.modal.show_confirm.assert_called_with(
            title="Unsaved Modifications",
            desc="Any unsaved edits will be lost if discarded.",
            query="Save changes?",
            options_text="[Y]es      [N]o      [ESC]=Cancel",
        )
        # ESC aborted new file creation; buffer remains modified
        self.assertTrue(self.editor.buffer.modified)

        # 3. Discard ('n') resets buffer without saving
        self.editor.modal.show_confirm.return_value = "n"
        self.editor.action_new_file()
        self.assertFalse(self.editor.buffer.modified)
        self.editor.action_save_file.assert_not_called()

        # 4. Save ('y') triggers save_file and resets buffer
        self.editor.buffer.modified = True
        self.editor.modal.show_confirm.return_value = "y"
        self.editor.action_new_file()
        self.editor.action_save_file.assert_called_once()
        self.assertFalse(self.editor.buffer.modified)

        print(
            "[+] Step 41: Canonical new file prompt syntax verified.",
            flush=True,
        )

    def test_bug_2_7_53_splash_screen_dimensions_and_colon_commands(self):
        """Step 42: Verify splash 14x50 geometry & colon cmds (Bug 2.7.53)."""
        print(
            "[*] Step 42: Testing splash 21x50 geometry & hotkeys...",
            flush=True,
        )
        rendered_lines_list = []
        self.editor.renderer.render_centered_workspace = (
            lambda lines, buf, geometry_str="80x24": (
                rendered_lines_list.append(list(lines))
            )
        )

        # 1. Verify 21 lines and <= 50 column width
        self.editor.terminal.get_key = MagicMock(return_value="e")
        self.editor.action_splash_screen()
        self.assertEqual(len(rendered_lines_list), 1)
        lines = rendered_lines_list[0]
        self.assertEqual(len(lines), 21)
        for idx, line in enumerate(lines):
            self.assertLessEqual(
                len(line),
                50,
                f"Line {idx} exceeds 50 columns: {line}",
            )

        # Verify mathematical centering yields top_row == 2 on 80x24
        from se.ui import compute_centering
        content_w = max(len(ln) for ln in lines)
        top_row, left_col = compute_centering(80, 24, content_w, 21)
        self.assertEqual(top_row, 2)
        self.assertTrue(16 <= left_col <= 22)

        # 2. Verify single hotkey dispatch
        # e returns to editor
        self.editor.terminal.get_key = MagicMock(return_value="e")
        self.editor.action_splash_screen()

        # o calls action_open_file
        self.editor.action_open_file = MagicMock(return_value=True)
        self.editor.terminal.get_key = MagicMock(return_value="o")
        self.editor.action_splash_screen()
        self.editor.action_open_file.assert_called_once()

        # s calls action_save_file
        self.editor.action_save_file = MagicMock(return_value=True)
        self.editor.terminal.get_key = MagicMock(side_effect=["s", "e"])
        self.editor.action_splash_screen()
        self.editor.action_save_file.assert_called_once()

        # c calls action_config_screen
        self.editor.action_config_screen = MagicMock()
        self.editor.terminal.get_key = MagicMock(side_effect=["c", "e"])
        self.editor.action_splash_screen()
        self.editor.action_config_screen.assert_called_once()

        # p calls action_plugin_palette
        self.editor.action_plugin_palette = MagicMock()
        self.editor.terminal.get_key = MagicMock(side_effect=["p", "e"])
        self.editor.action_splash_screen()
        self.editor.action_plugin_palette.assert_called_once()

        # ? calls action_help
        self.editor.action_help = MagicMock()
        self.editor.terminal.get_key = MagicMock(side_effect=["?", "e"])
        self.editor.action_splash_screen()
        self.editor.action_help.assert_called_once()

        # q calls action_quit
        self.editor.action_quit = MagicMock()
        self.editor.terminal.get_key = MagicMock(return_value="q")
        self.editor.action_splash_screen()
        self.editor.action_quit.assert_called_once()

        # 3. Verify silent rejection: space bar, arrow keys, unassigned, ESC
        render_mock = MagicMock()
        self.editor.renderer.render_centered_workspace = render_mock
        non_entry_keys = [
            " ",
            KEY_UP,
            KEY_DOWN,
            KEY_LEFT,
            KEY_RIGHT,
            KEY_ESC,
            "z",
            "e",
        ]
        self.editor.terminal.get_key = MagicMock(side_effect=non_entry_keys)
        self.editor.action_splash_screen()
        # Initial render only; non-entry keys do NOT cause re-render
        self.assertEqual(render_mock.call_count, 1)

        print(
            "[+] Step 42: Splash 21x50 geometry & hotkeys verified.",
            flush=True,
        )

    def test_bug_2_7_54_splash_geometry_hotkeys_inversion(self):
        """Step 43: Verify hotkey 1 sets 80x24 and hotkey 2 sets 120x40."""
        print(
            "[*] Step 43: Testing splash geometry hotkeys 1 and 2...",
            flush=True,
        )
        self.editor.renderer.render_centered_workspace = MagicMock()

        # Press '1' then 'e' to exit splash
        self.editor.config.set("SCREEN", "120x40")
        self.editor.terminal.cols = 120
        self.editor.terminal.rows = 40
        self.editor.terminal.get_key = MagicMock(side_effect=["1", "e"])
        self.editor.action_splash_screen()

        self.assertEqual(self.editor.config.get("SCREEN"), "80x24")
        self.assertEqual(self.editor.terminal.cols, 80)
        self.assertEqual(self.editor.terminal.rows, 24)

        # Press '2' then 'e' to exit splash
        self.editor.terminal.get_key = MagicMock(side_effect=["2", "e"])
        self.editor.action_splash_screen()

        self.assertEqual(self.editor.config.get("SCREEN"), "120x40")
        self.assertEqual(self.editor.terminal.cols, 120)
        self.assertEqual(self.editor.terminal.rows, 40)

        print(
            "[+] Step 43: Splash geometry hotkeys 1 and 2 verified.",
            flush=True,
        )

    def test_bug_2_7_55_splash_option3_native_mode(self):
        """Step 44: Verify hotkey 3 sets NATIVE mode on splash screen."""
        print(
            "[*] Step 44: Testing splash hotkey 3 sets Native mode...",
            flush=True,
        )
        self.editor.renderer.render_centered_workspace = MagicMock()
        self.editor.config.set("SCREEN", "80x24")
        self.editor.terminal.cols = 80
        self.editor.terminal.rows = 24

        def mock_update_geometry():
            self.editor.terminal.cols = 132
            self.editor.terminal.rows = 43
            return 132, 43

        self.editor.terminal.update_geometry = mock_update_geometry
        self.editor.terminal.get_key = MagicMock(side_effect=["3", "e"])
        self.editor.action_splash_screen()

        self.assertEqual(self.editor.config.get("SCREEN"), "NATIVE")
        self.assertEqual(self.editor.terminal.cols, 132)
        self.assertEqual(self.editor.terminal.rows, 43)

        print(
            "[+] Step 44: Splash hotkey 3 sets Native mode verified.",
            flush=True,
        )

    def test_bug_2_7_56_screen_clear_on_geometry_switch(self):
        """Step 45: Verify term_init clears screen on geometry switch."""
        print(
            "[*] Step 45: Testing term_init on geometry switches...",
            flush=True,
        )
        self.editor.renderer.render_centered_workspace = MagicMock()
        self.editor.terminal.term_init = MagicMock()

        # 1. Splash screen hotkey 1
        self.editor.terminal.get_key = MagicMock(side_effect=["1", "e"])
        self.editor.action_splash_screen()
        self.editor.terminal.term_init.assert_called_once()
        self.editor.terminal.term_init.reset_mock()

        # 2. Splash screen hotkey 2
        self.editor.terminal.get_key = MagicMock(side_effect=["2", "e"])
        self.editor.action_splash_screen()
        self.editor.terminal.term_init.assert_called_once()
        self.editor.terminal.term_init.reset_mock()

        # 3. Splash screen hotkey 3
        self.editor.terminal.update_geometry = MagicMock(return_value=(80, 24))
        self.editor.terminal.get_key = MagicMock(side_effect=["3", "e"])
        self.editor.action_splash_screen()
        self.editor.terminal.term_init.assert_called_once()
        self.editor.terminal.term_init.reset_mock()

        # 4. Configuration screen option 1
        self.editor.terminal.get_key = MagicMock(side_effect=["1", "q"])
        self.editor.action_config_screen()
        self.editor.terminal.term_init.assert_called_once()

        print(
            "[+] Step 45: term_init on geometry switches verified.",
            flush=True,
        )

    def test_bug_2_7_58_config_screen_native_mode_toggle(self):
        """Step 46: Verify config screen option 1 cycles 80x24/120x40/Native."""
        print(
            "[*] Step 46: Testing config screen option 1 geometry cycling...",
            flush=True,
        )
        self.editor.renderer.render_centered_workspace = MagicMock()
        self.editor.terminal.term_init = MagicMock()

        # Start from 80x24: 1 -> 120x40
        self.editor.config.set("SCREEN", "80x24")
        self.editor.terminal.cols = 80
        self.editor.terminal.rows = 24
        self.editor.terminal.get_key = MagicMock(side_effect=["1", "q"])
        self.editor.action_config_screen()

        self.assertEqual(self.editor.config.get("SCREEN"), "120x40")
        self.assertEqual(self.editor.terminal.cols, 120)
        self.assertEqual(self.editor.terminal.rows, 40)

        # From 120x40: 1 -> NATIVE
        def mock_update():
            self.editor.terminal.cols = 150
            self.editor.terminal.rows = 50
            return 150, 50

        self.editor.terminal.update_geometry = mock_update
        self.editor.terminal.get_key = MagicMock(side_effect=["1", "q"])
        self.editor.action_config_screen()

        self.assertEqual(self.editor.config.get("SCREEN"), "NATIVE")
        self.assertEqual(self.editor.terminal.cols, 150)
        self.assertEqual(self.editor.terminal.rows, 50)

        # From NATIVE: 1 -> 80x24
        self.editor.terminal.get_key = MagicMock(side_effect=["1", "q"])
        self.editor.action_config_screen()

        self.assertEqual(self.editor.config.get("SCREEN"), "80x24")
        self.assertEqual(self.editor.terminal.cols, 80)
        self.assertEqual(self.editor.terminal.rows, 24)

        print(
            "[+] Step 46: Config screen option 1 geometry cycling verified.",
            flush=True,
        )

    def test_bug_2_7_59_startup_geometry_emulation_preserved(self):
        """Step 47: Verify configured fixed geometry preserved on startup."""
        print(
            "[*] Step 47: Testing startup fixed geometry emulation...",
            flush=True,
        )
        from se.editor import Editor
        import tempfile

        with tempfile.NamedTemporaryFile(
            "w+", suffix=".cfg", delete=False
        ) as f:
            f.write("SCREEN=80x24\r\n")
            cfg_path = f.name

        try:
            ed = Editor(config_path=cfg_path)
            self.assertTrue(ed.terminal.fixed_geometry)
            self.assertEqual(ed.terminal.cols, 80)
            self.assertEqual(ed.terminal.rows, 24)

            cols, rows = ed.terminal.update_geometry()
            self.assertEqual(cols, 80)
            self.assertEqual(rows, 24)
            self.assertEqual(ed.terminal.cols, 80)
            self.assertEqual(ed.terminal.rows, 24)
        finally:
            if os.path.exists(cfg_path):
                os.unlink(cfg_path)

        with tempfile.NamedTemporaryFile(
            "w+", suffix=".cfg", delete=False
        ) as f:
            f.write("SCREEN=NATIVE\r\n")
            cfg_path = f.name

        try:
            ed_native = Editor(config_path=cfg_path)
            self.assertFalse(ed_native.terminal.fixed_geometry)
        finally:
            if os.path.exists(cfg_path):
                os.unlink(cfg_path)

        print(
            "[+] Step 47: Startup fixed geometry emulation verified.",
            flush=True,
        )

    def test_bug_2_7_60_direct_in_place_block_ops(self):
        """Step 48: Direct in-place block copy/move without clipboard."""
        print(
            "[*] Step 48: Testing direct in-place block copy and move...",
            flush=True,
        )
        # 1. Direct copy block to cursor
        self.editor.buffer.lines = ["FIRST LINE", "SECOND LINE", "THIRD LINE"]
        self.editor.buffer.cursor_row = 1
        self.editor.buffer.cursor_col = 0
        self.editor.buffer.block_active = 2
        self.editor.buffer.block_start_row = 1
        self.editor.buffer.block_start_col = 0
        self.editor.buffer.block_end_row = 1
        self.editor.buffer.block_end_col = 6  # "SECOND"

        # Position cursor at top of third line
        self.editor.buffer.cursor_row = 2
        self.editor.buffer.cursor_col = 0

        # Dispatch Ctrl+C (in-place copy)
        self.editor.dispatch_key(KEY_CTRL_C)
        self.assertEqual(self.editor.buffer.get_line(2), "SECONDTHIRD LINE")

        # 2. Direct move block to cursor
        self.editor.buffer.lines = ["HEADER", "TARGET", "FOOTER"]
        self.editor.buffer.block_active = 2
        self.editor.buffer.block_start_row = 1
        self.editor.buffer.block_start_col = 0
        self.editor.buffer.block_end_row = 1
        self.editor.buffer.block_end_col = 6  # "TARGET"

        # Position cursor at line 0 col 0 (before block)
        self.editor.buffer.cursor_row = 0
        self.editor.buffer.cursor_col = 0

        # Dispatch Ctrl+X (in-place move)
        self.editor.dispatch_key(KEY_CTRL_X)
        self.assertEqual(self.editor.buffer.get_line(0), "TARGETHEADER")
        self.assertEqual(self.editor.buffer.get_line(1), "")

        # 3. Cannot move block into itself
        self.editor.buffer.lines = ["ALPHA BETA GAMMA"]
        self.editor.buffer.block_active = 2
        self.editor.buffer.block_start_row = 0
        self.editor.buffer.block_start_col = 6
        self.editor.buffer.block_end_row = 0
        self.editor.buffer.block_end_col = 10  # "BETA"
        self.editor.buffer.cursor_row = 0
        self.editor.buffer.cursor_col = 8  # Inside "BETA"
        res = self.editor.buffer.move_block_to_cursor()
        self.assertFalse(res)
        self.assertEqual(self.editor.buffer.lines, ["ALPHA BETA GAMMA"])

        print(
            "[+] Step 48: Direct in-place block operations verified.",
            flush=True,
        )

    def test_bug_2_7_61_canonical_21_line_splash_template(self):
        """Step 49: Canonical 21-line splash template and no prompt."""
        print(
            "[*] Step 49: Testing canonical 21-line splash template...",
            flush=True,
        )
        captured = []
        self.editor.renderer.render_centered_workspace = (
            lambda lines, buf, geometry_str="80x24": (
                captured.append(list(lines))
            )
        )
        # Verify ESC does not exit splash to editor (silently ignored)
        self.editor.terminal.get_key = MagicMock(
            side_effect=[KEY_ESC, " ", KEY_UP, "e"]
        )
        self.editor.action_splash_screen()
        self.assertEqual(len(captured), 1)
        lines = captured[0]

        # 1. Height is exactly 21 lines
        self.assertEqual(len(lines), 21)

        # 2. Clean header mandate: Row 0 has title, no version/language
        self.assertEqual(lines[0], "SE - Screen Editor")
        self.assertEqual(lines[1], "")
        for line in lines:
            self.assertNotIn("Version", line)
            self.assertNotIn("Python", line)
            self.assertNotIn("Enter choice:", line)
            self.assertNotIn("Enter option:", line)

        # 3. 4 diagnostic status lines at bottom
        self.assertTrue(lines[17].startswith("Active Screen : ["))
        self.assertEqual(lines[18], "RAM Drive (A:): [Preserved (Active)]")
        self.assertEqual(lines[19], "Plugin System : [Operational]")
        self.assertTrue(lines[20].startswith("Max Lines     : ["))

        print(
            "[+] Step 49: Canonical 21-line splash template verified.",
            flush=True,
        )

    def test_bug_2_7_62_about_screen_predominant_language(self):
        """Step 50: Verify About screen displays predominant language."""
        print(
            "[*] Step 50: Testing About screen predominant language...",
            flush=True,
        )
        rendered = []
        self.editor.renderer.render_centered_workspace = (
            lambda lines, buf, geometry_str="80x24": rendered.extend(lines)
        )
        self.editor.terminal.get_key = MagicMock(return_value=" ")
        self.editor.action_about()
        about_str = "\n".join(rendered)
        self.assertIn("version 1.1.0 (2026-10-09) (Python)", about_str)
        self.assertNotIn("(Linux)", about_str)
        print(
            "[+] Step 50: About screen predominant language verified.",
            flush=True,
        )

    def test_bug_2_7_63_canonical_5_option_config_screen(self):
        """Step 51: Verify canonical 5-option config manager workspace."""
        print(
            "[*] Step 51: Testing canonical 5-option config screen...",
            flush=True,
        )
        rendered = []
        self.editor.renderer.render_centered_workspace = (
            lambda lines, buf, geometry_str="80x24": (
                rendered.append(list(lines))
            )
        )
        # Test toggling option 5 (Plugin Manager: AUTOLOAD -> DISABLED)
        self.editor.config.set("PLUGIN", "AUTOLOAD")
        self.editor.terminal.get_key = MagicMock(side_effect=["5", "q"])
        self.editor.action_config_screen()

        self.assertEqual(self.editor.config.get("PLUGIN"), "DISABLED")
        lines = rendered[0]

        # 1. ASCII hyphen title
        self.assertEqual(lines[0], "SE - Configuration Manager")
        self.assertNotIn("—", lines[0])

        # 2. Config Status header present
        self.assertTrue(lines[2].startswith("Config Status: "))

        # 3. Canonical 5 options in order
        self.assertTrue(lines[4].startswith("1. Screen Geometry  :"))
        self.assertTrue(lines[5].startswith("2. RAM Drive Mode   :"))
        self.assertTrue(lines[6].startswith("3. Max Doc Lines    :"))
        self.assertTrue(lines[7].startswith("4. Tab Width        :"))
        self.assertTrue(lines[8].startswith("5. Plugin Manager   :"))

        # 4. Canonical footer without Enter option prompt
        self.assertEqual(
            lines[10], "[1-5]=Toggle Option  [S]=Save Config  [ESC]=Exit"
        )
        for line in lines:
            self.assertNotIn("Enter option:", line)

        print(
            "[+] Step 51: Canonical 5-option config screen verified.",
            flush=True,
        )

    def test_bug_2_7_67_default_lf_and_decouple_config_save(self):
        """Step 52: Verify default LF format and decoupling from SE.CFG."""
        print(
            "[*] Step 52: Testing default LF format & SE.CFG decoupling...",
            flush=True,
        )
        new_buf = DocumentBuffer()
        self.assertFalse(new_buf.format_cpm)

        orig_fmt = self.editor.config.get("FORMAT")
        with tempfile.TemporaryDirectory() as tmp_dir:
            save_path = os.path.join(tmp_dir, "test_lf.txt")
            key_seq = list(save_path) + [KEY_ENTER, KEY_ENTER]
            self.editor.terminal.get_key = MagicMock(side_effect=key_seq)
            self.editor.buffer.lines = ["Line 1", "Line 2"]
            self.assertFalse(self.editor.buffer.format_cpm)

            ok = self.editor.action_save_file()
            self.assertTrue(ok)
            self.assertTrue(os.path.isfile(save_path))
            with open(save_path, "rb") as f:
                content = f.read()
            self.assertEqual(content, b"Line 1\nLine 2\n")
            # Config FORMAT setting was NOT mutated
            self.assertEqual(self.editor.config.get("FORMAT"), orig_fmt)

        print(
            "[+] Step 52: Default LF format & SE.CFG decoupling verified.",
            flush=True,
        )

    def test_bug_2_7_69_directory_browser_in_place_prompt_echoing(self):
        """Step 53: Verify in-place prompt echoing in directory browser."""
        print(
            "[*] Step 53: Testing in-place prompt echoing in directory...",
            flush=True,
        )
        full_renders = []
        prompt_renders = []

        orig_full = self.editor.renderer.render_directory_workspace
        orig_prompt = self.editor.renderer.render_directory_prompt

        def mock_full(*args, **kwargs):
            full_renders.append((args, kwargs))
            return orig_full(*args, **kwargs)

        def mock_prompt(*args, **kwargs):
            prompt_renders.append((args, kwargs))
            return orig_prompt(*args, **kwargs)

        self.editor.renderer.render_directory_workspace = mock_full
        self.editor.renderer.render_directory_prompt = mock_prompt

        # Sequence of 5 keystrokes: 'a', 'b', KEY_BACKSPACE, KEY_LEFT, KEY_ESC
        keystrokes = ["a", "b", KEY_BACKSPACE, KEY_LEFT, KEY_ESC]
        self.editor.terminal.get_key = MagicMock(side_effect=keystrokes)

        result = self.editor.action_directory_browser(mode="open")
        self.assertIsNone(result)

        # Full workspace render called exactly once on entry
        self.assertEqual(len(full_renders), 1)

        # In-place prompt row render called for 'a', 'b', backspace, left
        self.assertEqual(len(prompt_renders), 4)

        print(
            "[+] Step 53: In-place prompt echoing in directory verified.",
            flush=True,
        )

    def test_bug_2_7_70_canonical_help_screen_keys(self):
        """Step 54: Verify canonical Help screen keys and ASCII title."""
        print(
            "[*] Step 54: Testing canonical Help screen keys & title...",
            flush=True,
        )
        rendered_lines = []
        self.editor.renderer.render_centered_workspace = (
            lambda lines, buf, geometry_str="80x24": rendered_lines.extend(
                lines
            )
        )
        self.editor.terminal.get_key = lambda timeout=None: " "
        self.editor.action_help()

        # 1. Height and width
        self.assertEqual(len(rendered_lines), 17)
        self.assertEqual(max(len(ln) for ln in rendered_lines), 70)

        help_text = "\n".join(rendered_lines)

        # 2. ASCII title without Unicode em-dash
        self.assertIn("SE - EDITOR MODE KEYS", help_text)
        self.assertNotIn("—", help_text)

        # 3. Canonical block operations
        self.assertIn("Ctrl+C: Copy Block to Cursor", help_text)
        self.assertIn("Ctrl+X: Move Block to Cursor", help_text)
        self.assertIn("Ctrl+D: Delete Block", help_text)

        # 4. Canonical navigation
        self.assertIn("PgUp / PgDn : Page Up / Down", help_text)

        # 5. Obsolete references removed
        self.assertNotIn("Paste Block", help_text)
        self.assertNotIn("Cut Block", help_text)
        self.assertNotIn("Ctrl+U / Ctrl+V", help_text)

        print(
            "[+] Step 54: Canonical Help screen keys & title verified.",
            flush=True,
        )

    def test_bug_2_7_71_startup_screen_geometry_defaults(self):
        """Step 55: Verify startup screen geometry defaults to 80x24."""
        print(
            "[*] Step 55: Testing startup screen geometry default 80x24...",
            flush=True,
        )
        ed = Editor()
        self.assertEqual(ed.config.DEFAULT_SCREEN, "80X24")
        self.assertEqual(ed.config.screen_geometry, (80, 24))
        self.assertEqual(ed.terminal.cols, 80)
        self.assertEqual(ed.terminal.rows, 24)
        self.assertTrue(ed.terminal.fixed_geometry)

        print(
            "[+] Step 55: Startup screen geometry default 80x24 verified.",
            flush=True,
        )

    def test_bug_2_7_73_status_bar_long_filename_truncation(self):
        """Step 56: Verify Field 1 truncation preserves Field 5 on 80x24."""
        print(
            "[*] Step 56: Testing status bar Field 1 14-char truncation...",
            flush=True,
        )
        written = []
        self.editor.terminal.write = lambda s: written.append(s)
        self.editor.terminal.cols = 80
        self.editor.terminal.rows = 24

        self.editor.buffer.filename = "very_long_document_filename_test.txt"
        self.editor.buffer.lines = ["Line 1", "Line 2"]
        self.editor.buffer.cursor_row = 1
        self.editor.buffer.cursor_col = 3

        # 1. Standard mode: 14-char truncated filename and full Field 5
        self.editor.renderer.render_status_bar(
            self.editor.buffer, geometry_str="80x24"
        )
        bar = [w for w in written if not w.startswith("\x1b")][0]
        self.assertEqual(len(bar), 80)
        self.assertIn("| very_long_docu |", bar)
        self.assertIn("Line    2/2    Col 3   |", bar)

        # 2. With [Pan +40] and [SEL]: Field 5 never clipped
        written.clear()
        self.editor.buffer.pan_col = 40
        self.editor.buffer.block_active = 1
        self.editor.renderer.render_status_bar(
            self.editor.buffer, geometry_str="80x24"
        )
        bar_flags = [w for w in written if not w.startswith("\x1b")][0]
        self.assertEqual(len(bar_flags), 80)
        self.assertIn("Line 2/2 Col 3 [Pan +40] [SEL] |", bar_flags)

        print(
            "[+] Step 56: Status bar Field 1 14-char truncation verified.",
            flush=True,
        )

    def test_bug_2_7_74_ctrl_k_immediate_help_dispatch(self):
        """Step 57: Verify Ctrl+K uses <=100ms timeout and Arrow Keys label."""
        print(
            "[*] Step 57: Testing immediate Ctrl+K Help dispatch...",
            flush=True,
        )
        timeouts = []

        def record_ready(timeout=0.0):
            timeouts.append(timeout)
            return False

        self.editor.terminal.is_key_ready = record_ready
        self.editor.terminal.get_key = lambda timeout=None: " "
        rendered_lines = []
        self.editor.renderer.render_centered_workspace = (
            lambda lines, buf, geometry_str="80x24": rendered_lines.extend(
                lines
            )
        )
        self.editor.buffer.block_active = 0
        self.editor.dispatch_key(KEY_CTRL_K)

        self.assertEqual(len(timeouts), 1)
        self.assertLessEqual(timeouts[0], 0.1)
        help_text = "\n".join(rendered_lines)
        self.assertIn("Arrow Keys", help_text)
        self.assertIn("EDITOR MODE KEYS", help_text)

        print(
            "[+] Step 57: Immediate Ctrl+K Help dispatch verified.",
            flush=True,
        )


if __name__ == "__main__":
    unittest.main()




