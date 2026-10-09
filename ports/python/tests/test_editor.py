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
from se.modal import ModalDialog
from se.terminal import (
    KEY_CTRL_D,
    KEY_CTRL_S,
    KEY_CTRL_V,
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

    def test_config_screen_option_toggles(self):
        """Step 7: Verify config options 3 & 4 toggle handlers (Bug 2.7.8)."""
        print(
            "[*] Step 7: Testing config screen option 3 & 4 toggles...",
            flush=True,
        )
        self.editor.renderer.render_centered_workspace = MagicMock()

        # Press '3' (toggle max lines), '4' (toggle ramdrive), and Enter (exit)
        keys = ["3", "4", "\r"]
        key_iter = iter(keys)
        self.editor.terminal.get_key = lambda: next(key_iter)

        # Ensure baseline values
        self.editor.config.set("MAXLINES", "16K")
        self.editor.config.set("RAMDRIVE", "PRESERVE")

        self.editor.action_config_screen()

        # Option 3 toggles 16K -> 32K
        self.assertEqual(self.editor.config.max_lines, "32K")
        # Option 4 toggles PRESERVE -> DISABLED
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

        # Case C: On splash screen, KEY_ESC exits back to editor
        del self.editor.action_splash_screen  # restore real method
        self.editor.renderer.render_centered_workspace = MagicMock()
        self.editor.terminal.get_key = MagicMock(return_value=KEY_ESC)
        self.editor.action_splash_screen()  # Must return cleanly on KEY_ESC

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

        # Single-line selection (dynamic follows cursor)
        self.editor.buffer.block_active = 1
        self.editor.buffer.block_start_row = 0
        self.editor.buffer.block_start_col = 0
        self.editor.buffer.cursor_row = 0
        self.editor.buffer.cursor_col = 5
        self.editor.renderer.render_status_bar(self.editor.buffer)

        status_texts = [w for w in written if not w.startswith("\x1b")]
        self.assertEqual(len(status_texts[0]), 80)
        self.assertIn("Sel: 5 chars", status_texts[0])
        self.assertNotIn("[SEL]", status_texts[0])

        # Multi-line selection (dynamic follows cursor)
        written.clear()
        self.editor.buffer.lines = ["Line 1", "Line 2", "Line 3"]
        self.editor.buffer.cursor_row = 2
        self.editor.buffer.cursor_col = 3
        self.editor.renderer.render_status_bar(self.editor.buffer)

        status_texts_multi = [w for w in written if not w.startswith("\x1b")]
        self.assertEqual(len(status_texts_multi[0]), 80)
        self.assertIn("Sel: 3 lines", status_texts_multi[0])

        # Solidified block (uses block_end_row / block_end_col)
        written.clear()
        self.editor.buffer.block_active = 2
        self.editor.buffer.block_end_row = 2
        self.editor.buffer.block_end_col = 3
        self.editor.renderer.render_status_bar(self.editor.buffer)

        status_texts_solid = [w for w in written if not w.startswith("\x1b")]
        self.assertEqual(len(status_texts_solid[0]), 80)
        self.assertIn("Block: 3 lines", status_texts_solid[0])

        print(
            "[+] Step 11: Status bar block metrics verified without spill.",
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
        self.editor.renderer.render_status_bar(
            self.editor.buffer, geometry_str="120x40"
        )
        texts_120 = [w for w in written if not w.startswith("\x1b")]
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
        """Step 14: Verify 14 splash commands & 4 status blocks (Bug 2.7.18)."""
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

        # Feed sequence: '1' (toggle 120x40), '2' (toggle 80x24), 'e' (exit)
        keys = ["1", "2", "e"]
        key_iter = iter(keys)
        self.editor.terminal.get_key = lambda timeout=None: next(
            key_iter, "e"
        )

        self.editor.action_splash_screen()

        self.assertTrue(len(rendered_lines_list) >= 3)
        splash_text = "\n".join(rendered_lines_list[0])

        # Verify 14 canonical commands
        expected_commands = [
            "[E]  or  [Enter] to edit",
            "[N]              to new file",
            "[O]              to open file",
            "[S]              to save file",
            "[W]  or  [^W]    to close file",
            "[L]  or  [^L]    to goto line",
            "[A]              for about",
            "[M]              for memory info",
            "[P]              for plugins",
            "[^P]             for context plugin menu",
            "[C]              to configure",
            "[1]              set 120x40",
            "[2]              set 80x24",
            "[Q]  or  [^Q]    to exit",
        ]
        for cmd in expected_commands:
            self.assertIn(cmd, splash_text)

        # Verify 4 status blocks
        self.assertIn("Active Screen : [", splash_text)
        self.assertIn("RAM Drive     : [", splash_text)
        self.assertIn("Plugin System : [", splash_text)
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
        self.editor.modal.show_confirm(
            title="Save", desc="Unsaved edits", query="Save?"
        )
        self.assertEqual(len(captured), 1)
        top, left, width = captured[-1]
        self.assertEqual(width, 52)
        # On 80-col screen, left should be (80 - 52) // 2 + 1 = 15
        self.assertEqual(left, 15)

        # 2. Text input modal (Archetype C)
        self.editor.terminal.get_key = MagicMock(return_value="\r")
        self.editor.modal.show_input(
            title="Goto", desc="Jump line", label="Line:"
        )
        self.assertEqual(captured[-1][2], 52)

        # 3. Find dialog (Archetype C with toggle)
        self.editor.modal.show_find_dialog(initial_text="test")
        self.assertEqual(captured[-1][2], 52)

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


if __name__ == "__main__":
    unittest.main()
