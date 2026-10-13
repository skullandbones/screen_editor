#!/usr/bin/env python3
"""
Unit tests for DocumentBuffer in SE editor port.
Verifies line editing, 120-column barrier, navigation, and block operations.
"""

import os
import sys
import tempfile
import time
import unittest

from se.buffer import (
    DocumentBuffer,
    LINE_JOIN_LIMIT,
    MAX_INPUT_LINE_CHARS,
    MAX_LINE_CHARS,
    MAX_LINE_LENGTH,
    adjust_col_to_target,
    calc_visual_col,
    expand_tabs_visual,
)


class TestBuffer(unittest.TestCase):
    """Test suite for DocumentBuffer operations and constraints."""

    def setUp(self):
        self.buf = DocumentBuffer()

    def test_initial_state(self):
        """Step 1: Verify initial buffer state and properties."""
        print("[*] Step 1: Verifying initial buffer state...", flush=True)
        self.assertEqual(self.buf.total_lines, 1)
        self.assertEqual(self.buf.current_line, "")
        self.assertEqual(self.buf.cursor_row, 0)
        self.assertEqual(self.buf.cursor_col, 0)
        self.assertFalse(self.buf.modified)
        self.assertEqual(self.buf.filename, "(Untitled)")
        print("[+] Step 1: Initial buffer state verified.", flush=True)

    def test_insertion_and_1000_char_limit(self):
        """Step 2: Verify typing insertion and 1,000-char line limit."""
        print(
            "[*] Step 2: Testing character insertion & 1,000 limit...",
            flush=True,
        )
        for ch in "HELLO WORLD":
            ok = self.buf.insert_char(ch)
            self.assertTrue(ok)
        self.assertEqual(self.buf.current_line, "HELLO WORLD")
        self.assertEqual(self.buf.cursor_col, 11)
        self.assertTrue(self.buf.modified)

        # Extend line to 1,000 chars
        remaining = MAX_LINE_CHARS - len("HELLO WORLD")
        for _ in range(remaining):
            self.buf.insert_char("X")
        self.assertEqual(len(self.buf.current_line), 1000)

        # 1001st character must be blocked
        blocked = self.buf.insert_char("Z")
        self.assertFalse(blocked)
        self.assertEqual(len(self.buf.current_line), 1000)
        print(
            "[+] Step 2: Insertion and 1,000-column limit verified.",
            flush=True,
        )

    def test_line_split_and_join(self):
        """Step 3: Verify Enter (split line) and Backspace/Delete."""
        print("[*] Step 3: Testing line split and line join...", flush=True)
        self.buf.insert_char("A")
        self.buf.insert_char("B")
        self.buf.cursor_col = 1  # between 'A' and 'B'
        self.buf.split_line()
        self.assertEqual(self.buf.total_lines, 2)
        self.assertEqual(self.buf.get_line(0), "A")
        self.assertEqual(self.buf.get_line(1), "B")
        self.assertEqual(self.buf.cursor_row, 1)
        self.assertEqual(self.buf.cursor_col, 0)

        # Backspace at col 0 joins line 1 back into line 0
        joined = self.buf.backspace()
        self.assertTrue(joined)
        self.assertEqual(self.buf.total_lines, 1)
        self.assertEqual(self.buf.current_line, "AB")
        self.assertEqual(self.buf.cursor_col, 1)

        # Split again, then join with Delete from line 0
        self.buf.split_line()
        self.buf.cursor_row = 0
        self.buf.cursor_col = 1  # end of line 0
        del_joined = self.buf.delete_char()
        self.assertTrue(del_joined)
        self.assertEqual(self.buf.total_lines, 1)
        self.assertEqual(self.buf.current_line, "AB")
        print("[+] Step 3: Line split and join verified.", flush=True)

    def test_cursor_navigation(self):
        """Step 4: Verify cursor navigation primitives."""
        print("[*] Step 4: Testing cursor navigation...", flush=True)
        self.buf.lines = ["FIRST LINE", "SECOND"]
        self.buf.move_top()
        self.assertEqual(self.buf.cursor_row, 0)
        self.assertEqual(self.buf.cursor_col, 0)

        self.buf.move_end()
        self.assertEqual(self.buf.cursor_col, 10)

        self.buf.move_down()
        self.assertEqual(self.buf.cursor_row, 1)
        self.assertEqual(self.buf.cursor_col, 6)  # clamped to "SECOND" length

        self.buf.move_home()
        self.assertEqual(self.buf.cursor_col, 0)

        self.buf.move_bottom()
        self.assertEqual(self.buf.cursor_row, 1)
        print("[+] Step 4: Navigation verified.", flush=True)

    def test_horizontal_panning(self):
        """Step 5: Verify horizontal pan offset [Pan +40] (Bug 2.7.12)."""
        print("[*] Step 5: Testing horizontal pan [Pan +40]...", flush=True)
        # Column 79 fits in 80 columns without panning (Bug 2.7.12)
        self.buf.cursor_col = 79
        self.buf.update_pan(view_cols=80)
        self.assertEqual(self.buf.pan_col, 0)

        # Column 80 triggers Pan +40
        self.buf.cursor_col = 80
        self.buf.update_pan(view_cols=80)
        self.assertEqual(self.buf.pan_col, 40)

        # Column 119 remains at Pan +40
        self.buf.cursor_col = 119
        self.buf.update_pan(view_cols=80)
        self.assertEqual(self.buf.pan_col, 40)

        # Column 120 triggers Pan +80
        self.buf.cursor_col = 120
        self.buf.update_pan(view_cols=80)
        self.assertEqual(self.buf.pan_col, 80)

        # Retreating below 80 returns to Pan +40
        self.buf.cursor_col = 79
        self.buf.update_pan(view_cols=80)
        self.assertEqual(self.buf.pan_col, 40)

        # Retreating below 40 returns to Pan 0
        self.buf.cursor_col = 39
        self.buf.update_pan(view_cols=80)
        self.assertEqual(self.buf.pan_col, 0)

        # 120-column geometry does not pan within 120 cols
        self.buf.cursor_col = 100
        self.buf.update_pan(view_cols=120)
        self.assertEqual(self.buf.pan_col, 0)

        print("[+] Step 5: Horizontal panning verified.", flush=True)

    def test_block_copy_cut_paste(self):
        """Step 6: Verify block selection, copy, cut, and paste."""
        print(
            "[*] Step 6: Testing block selection and clipboard...",
            flush=True,
        )
        self.buf.lines = ["Alpha Beta Gamma", "Second Line"]
        self.buf.cursor_row = 0
        self.buf.cursor_col = 6  # "Beta"
        self.buf.toggle_block()
        self.assertEqual(self.buf.block_active, 1)

        # Select "Beta" by moving cursor
        self.buf.cursor_col = 10
        copied = self.buf.copy_block()
        self.assertEqual(copied, "Beta")

        # Cut block
        cut = self.buf.cut_block()
        self.assertEqual(cut, "Beta")
        self.assertEqual(self.buf.get_line(0), "Alpha  Gamma")

        # Paste block
        self.buf.cursor_col = 6
        pasted = self.buf.paste_block()
        self.assertTrue(pasted)
        self.assertEqual(self.buf.get_line(0), "Alpha Beta Gamma")
        print("[+] Step 6: Block operations verified.", flush=True)

    def test_block_dynamic_cursor_tracking(self):
        """Step 8: Verify block selection dynamic tracking (Bug 2.7.2)."""
        print(
            "[*] Step 8: Testing dynamic block cursor tracking...",
            flush=True,
        )
        self.buf.lines = ["First Line", "Second Line"]
        self.buf.cursor_row = 0
        self.buf.cursor_col = 0
        self.buf.toggle_block()
        self.assertEqual(self.buf.block_active, 1)

        # Move cursor to col 5: dynamic block must span [0, 0] to [0, 5]
        self.buf.cursor_col = 5
        self.assertEqual(self.buf.get_normalized_block(), (0, 0, 0, 5))

        # Move cursor down to next line: must span across rows
        self.buf.cursor_row = 1
        self.buf.cursor_col = 6
        self.assertEqual(self.buf.get_normalized_block(), (0, 0, 1, 6))

        # Copying dynamic block must solidify and capture text across lines
        copied = self.buf.copy_block()
        self.assertEqual(copied, "First Line\nSecond")
        self.assertEqual(self.buf.block_active, 2)
        print(
            "[+] Step 8: Dynamic block cursor tracking verified.",
            flush=True,
        )

    def test_file_load_and_save(self):
        """Step 7: Verify file loading, saving, and format preservation."""
        print("[*] Step 7: Testing file load and save cycles...", flush=True)
        with tempfile.NamedTemporaryFile(
            delete=False, suffix=".txt"
        ) as tmp_file:
            tmp_path = tmp_file.name

        try:
            # Save file with CP/M format (CRLF + Ctrl+Z)
            self.buf.lines = ["Line 1 content", "Line 2 content"]
            saved = self.buf.save_file(tmp_path, format_cpm=True)
            self.assertTrue(saved)
            self.assertFalse(self.buf.modified)

            # Load into a new buffer
            buf2 = DocumentBuffer()
            loaded = buf2.load_file(tmp_path)
            self.assertTrue(loaded)
            self.assertEqual(buf2.total_lines, 2)
            self.assertEqual(buf2.get_line(0), "Line 1 content")
            self.assertEqual(buf2.get_line(1), "Line 2 content")
            self.assertTrue(buf2.format_cpm)
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)

        print("[+] Step 7: File load and save verified.", flush=True)

    def test_tab_traversal_and_coordinates(self):
        """Step 9: Verify 3-coordinate space and tab traversal (Bug 2.7.21)."""
        print(
            "[*] Step 9: Testing 3-coordinate space & tab traversal...",
            flush=True,
        )
        # 1. Visual column calculation with tab_width=4
        line = "\tA\tB"
        self.assertEqual(calc_visual_col(line, 0, tab_width=4), 0)
        self.assertEqual(calc_visual_col(line, 1, tab_width=4), 4)
        self.assertEqual(calc_visual_col(line, 2, tab_width=4), 5)
        self.assertEqual(calc_visual_col(line, 3, tab_width=4), 8)
        self.assertEqual(calc_visual_col(line, 4, tab_width=4), 9)

        # 2. Visual column calculation with tab_width=8
        self.assertEqual(calc_visual_col(line, 1, tab_width=8), 8)
        self.assertEqual(calc_visual_col(line, 2, tab_width=8), 9)
        self.assertEqual(calc_visual_col(line, 3, tab_width=8), 16)

        # 3. Tab expansion
        self.assertEqual(expand_tabs_visual("\tA", 4), "    A")
        self.assertEqual(expand_tabs_visual("A\tB", 4), "A   B")

        # 4. Discrete tab traversal in DocumentBuffer
        buf = DocumentBuffer(tab_width=4)
        buf.lines = ["\tXYZ"]
        buf.cursor_col = 0
        self.assertEqual(buf.get_visual_col(), 0)

        # Move right leaps forward by tab_spaces (4 cols) in 1 keypress
        buf.move_right()
        self.assertEqual(buf.cursor_col, 1)
        self.assertEqual(buf.get_visual_col(), 4)
        self.assertEqual(buf.target_col, 4)

        # Move left leaps backward to 0 in 1 keypress
        buf.move_left()
        self.assertEqual(buf.cursor_col, 0)
        self.assertEqual(buf.get_visual_col(), 0)
        self.assertEqual(buf.target_col, 0)

        print(
            "[+] Step 9: 3-coordinate space and tab traversal verified.",
            flush=True,
        )

    def test_vertical_navigation_sticky_col(self):
        """
        Step 10: Verify vertical navigation sticky target column (Bug 2.7.22).
        """
        print(
            "[*] Step 10: Testing vertical navigation & sticky target...",
            flush=True,
        )
        buf = DocumentBuffer(tab_width=4)
        buf.lines = [
            "0123456789ABCDEF",  # Row 0: 16 chars
            "SHORT",             # Row 1: 5 chars
            "\t\tINDENTED",      # Row 2: 2 tabs (vis 0..7) + INDENTED (vis 8..)
            "ANOTHER LONG LINE",  # Row 3: 17 chars
        ]

        # Place cursor at Row 0, col 10
        buf.cursor_row = 0
        buf.cursor_col = 10
        buf.target_col = 10

        # Move Down to Row 1 ("SHORT", len 5)
        buf.move_down()
        self.assertEqual(buf.cursor_row, 1)
        self.assertEqual(buf.cursor_col, 5)
        # target_col must stay sticky at 10
        self.assertEqual(buf.target_col, 10)

        # Move Down to Row 2 ("\t\tINDENTED")
        # Visual col 10 corresponds to char_idx 4 ('\t', '\t', 'I', 'N')
        buf.move_down()
        self.assertEqual(buf.cursor_row, 2)
        self.assertEqual(buf.cursor_col, 4)
        self.assertEqual(buf.get_visual_col(), 10)
        self.assertEqual(buf.target_col, 10)

        # Move Down to Row 3 ("ANOTHER LONG LINE")
        buf.move_down()
        self.assertEqual(buf.cursor_row, 3)
        self.assertEqual(buf.cursor_col, 10)
        self.assertEqual(buf.target_col, 10)

        # Move Up back through rows, preserving sticky target_col 10
        buf.move_up()
        self.assertEqual(buf.cursor_row, 2)
        self.assertEqual(buf.cursor_col, 4)
        self.assertEqual(buf.get_visual_col(), 10)

        buf.move_up()
        self.assertEqual(buf.cursor_row, 1)
        self.assertEqual(buf.cursor_col, 5)

        buf.move_up()
        self.assertEqual(buf.cursor_row, 0)
        self.assertEqual(buf.cursor_col, 10)

        # Test tab boundary clamping when target falls inside a tab
        buf.lines = ["0123", "\tXYZ", "012345"]
        buf.cursor_row = 0
        buf.cursor_col = 2
        buf.target_col = 2
        buf.move_down()
        self.assertEqual(buf.cursor_row, 1)
        # Target 2 falls inside the tab (0..3), so it must clamp to 0
        self.assertEqual(buf.cursor_col, 0)
        self.assertEqual(buf.target_col, 2)

        # Moving down restores cursor to col 2 on line without leading tabs
        buf.move_down()
        self.assertEqual(buf.cursor_row, 2)
        self.assertEqual(buf.cursor_col, 2)
        self.assertEqual(buf.target_col, 2)

        print(
            "[+] Step 10: Vertical navigation sticky target verified.",
            flush=True,
        )

    def test_horizontal_pan_left_boundary_and_lookahead(self):
        """
        Step 11: Verify pan left boundary <= 40 and lookahead (Bug 2.7.26).
        """
        print(
            "[*] Step 11: Testing pan left boundary <= 40 & lookahead...",
            flush=True,
        )
        buf = DocumentBuffer(tab_width=4)

        # 1. Test pan left boundary: retreating to col 40 resets to pan 0
        buf.cursor_col = 85
        buf.update_pan(view_cols=80)
        self.assertEqual(buf.pan_col, 40)

        # Move to exactly col 40: must reset pan_col to 0 (inclusive boundary)
        buf.cursor_col = 40
        buf.update_pan(view_cols=80)
        self.assertEqual(buf.pan_col, 0)

        # Move to col 80 while in pan 80: resets to pan 40
        buf.cursor_col = 120
        buf.update_pan(view_cols=80)
        self.assertEqual(buf.pan_col, 80)

        buf.cursor_col = 80
        buf.update_pan(view_cols=80)
        self.assertEqual(buf.pan_col, 40)

        # 2. Lookahead pan trigger on active line extending past col 79
        buf.pan_col = 0
        buf.lines = ["X" * 90]
        buf.cursor_col = 79
        buf.update_pan(view_cols=80)
        # Active line has characters past col 79, so lookahead triggers +40
        self.assertEqual(buf.pan_col, 40)

        # 3. No lookahead when typing at end of line (col 79 on line of len 79)
        buf.pan_col = 0
        buf.lines = ["X" * 79]
        buf.cursor_col = 79
        buf.update_pan(view_cols=80)
        self.assertEqual(buf.pan_col, 0)

        # 4. No lookahead on short lines
        buf.pan_col = 0
        buf.lines = ["SHORT"]
        buf.cursor_col = 4
        buf.update_pan(view_cols=80)
        self.assertEqual(buf.pan_col, 0)

        print(
            "[+] Step 11: Pan left boundary & lookahead verified.",
            flush=True,
        )

    def test_delete_and_paste_sticky_target_col(self):
        """
        Step 12: Verify sticky target column on delete and paste (Bug 2.7.31).
        """
        print(
            "[*] Step 12: Testing sticky target column on delete & paste...",
            flush=True,
        )
        buf = DocumentBuffer(tab_width=4)

        # 1. Single-line paste with tab synchronizes visual target_col
        buf.lines = ["Hello", "0123456789"]
        buf.cursor_row = 0
        buf.cursor_col = 0
        buf.clipboard = "\tA"
        buf.paste_block()
        # Line 0 is "\tAHello", cursor is at index 2 (after "\tA")
        # Visual col: \t (width 4) + 'A' (1) = 5
        self.assertEqual(buf.lines[0], "\tAHello")
        self.assertEqual(buf.cursor_col, 2)
        self.assertEqual(buf.target_col, 5)
        # Move down to Line 1 ("0123456789") -> should land on col 5
        buf.move_down()
        self.assertEqual(buf.cursor_row, 1)
        self.assertEqual(buf.cursor_col, 5)

        # 2. Multi-line paste ending with tab synchronizes visual target_col
        buf.lines = ["Line 1", "0123456789"]
        buf.cursor_row = 0
        buf.cursor_col = 0
        buf.clipboard = "First\n\tB"
        buf.paste_block()
        # Cursor is now at row 1, col 2 (after "\tB")
        # Line 1 is "\tBLine 1" -> visual col is 4 + 1 = 5
        self.assertEqual(buf.cursor_row, 1)
        self.assertEqual(buf.cursor_col, 2)
        self.assertEqual(buf.target_col, 5)

        # 3. delete_char() synchronizes visual target_col
        buf.lines = ["\t1234", "0123456789"]
        buf.cursor_row = 0
        buf.cursor_col = 1
        buf.target_col = 999  # deliberate stale target
        # Delete '1' at index 1; cursor stays at index 1 ('2')
        buf.delete_char()
        self.assertEqual(buf.lines[0], "\t234")
        self.assertEqual(buf.cursor_col, 1)
        self.assertEqual(buf.target_col, 4)

        # 4. delete_char() at end of line joining next line synchronizes target
        buf.lines = ["\t", "XYZ"]
        buf.cursor_row = 0
        buf.cursor_col = 1
        buf.target_col = 999  # deliberate stale target
        buf.delete_char()
        self.assertEqual(buf.lines[0], "\tXYZ")
        self.assertEqual(buf.cursor_col, 1)
        self.assertEqual(buf.target_col, 4)

        print(
            "[+] Step 12: Sticky target column on delete & paste verified.",
            flush=True,
        )

    def test_delete_char_eol_junction_cursor_col(self):
        """Step 13: Verify delete_char eol junction cursor (Bug 2.7.40)."""
        print(
            "[*] Step 13: Testing delete_char EOL junction cursor anchoring...",
            flush=True,
        )
        buf = DocumentBuffer(tab_width=8)
        buf.lines = ["Short", "Long trailing line"]
        buf.cursor_row = 0
        # Simulate cursor_col past len(line) (e.g. from sticky target or pan)
        buf.cursor_col = 15
        self.assertTrue(buf.delete_char())
        # Line 0 is joined: "Short" + "Long trailing line"
        self.assertEqual(buf.lines[0], "ShortLong trailing line")
        # cursor_col must be pinned to len("Short") == 5, NOT remaining at 15
        self.assertEqual(buf.cursor_col, 5)
        self.assertEqual(buf.target_col, 5)
        self.assertTrue(buf.modified)

        print(
            "[+] Step 13: delete_char EOL junction cursor anchoring verified.",
            flush=True,
        )

    def test_bug_2_7_47_line_capacity_limit_and_panning(self):
        """Step 14: Verify 1,000-char line capacity and pan (Bug 2.7.47)."""
        print(
            "[*] Step 14: Testing 1,000-char capacity and 120x40 pan...",
            flush=True,
        )
        self.assertEqual(MAX_LINE_CHARS, 1000)
        self.assertEqual(MAX_INPUT_LINE_CHARS, 1000)
        self.assertEqual(LINE_JOIN_LIMIT, 120)

        # 1. calc_visual_col clamps at 1,000 chars
        line_1000 = "A" * 1000
        self.assertEqual(calc_visual_col(line_1000, 500), 500)
        self.assertEqual(calc_visual_col(line_1000, 1000), 1000)
        self.assertEqual(calc_visual_col(line_1000, 1050), 1000)

        # 2. update_pan in 120-column mode (120x40 geometry)
        buf = DocumentBuffer()
        buf.lines = ["A" * 300]
        buf.cursor_col = 100
        buf.update_pan(view_cols=120)
        self.assertEqual(buf.pan_col, 0)

        # Cursor at 130 in 120-col view triggers Pan +40
        buf.cursor_col = 130
        buf.update_pan(view_cols=120)
        self.assertEqual(buf.pan_col, 40)

        # Cursor at 170 in 120-col view triggers Pan +80
        buf.cursor_col = 170
        buf.update_pan(view_cols=120)
        self.assertEqual(buf.pan_col, 80)

        # 3. Line joining is preserved at LINE_JOIN_LIMIT (120 chars)
        join_buf = DocumentBuffer()
        join_buf.lines = ["A" * 70, "B" * 60]  # 70 + 60 = 130 > 120
        join_buf.cursor_row = 0
        join_buf.cursor_col = 70
        self.assertFalse(join_buf.delete_char())
        join_buf.cursor_row = 1
        join_buf.cursor_col = 0
        self.assertFalse(join_buf.backspace())

        # Join when sum <= 120
        join_buf.lines = ["A" * 60, "B" * 60]  # 60 + 60 = 120
        join_buf.cursor_row = 0
        join_buf.cursor_col = 60
        self.assertTrue(join_buf.delete_char())
        self.assertEqual(len(join_buf.lines[0]), 120)

        print(
            "[+] Step 14: 1,000-char capacity and 120x40 pan verified.",
            flush=True,
        )

    def test_bug_2_7_60_direct_in_place_block_ops(self):
        """Step 15: Verify direct in-place copy and move block methods."""
        print(
            "[*] Step 15: Testing direct in-place block methods...",
            flush=True,
        )
        buf = DocumentBuffer()
        buf.lines = ["Line 1", "Line 2 - TARGET", "Line 3"]
        buf.cursor_row = 1
        buf.cursor_col = 9
        buf.block_active = 2
        buf.block_start_row = 1
        buf.block_start_col = 9
        buf.block_end_row = 1
        buf.block_end_col = 15  # "TARGET"

        # Check cursor inside block
        self.assertTrue(buf.is_cursor_in_block(1, 10))
        self.assertFalse(buf.is_cursor_in_block(1, 8))
        self.assertFalse(buf.is_cursor_in_block(1, 15))

        # Copy block to Line 0 Col 0
        buf.cursor_row = 0
        buf.cursor_col = 0
        ok = buf.copy_block_to_cursor()
        self.assertTrue(ok)
        self.assertEqual(buf.lines[0], "TARGETLine 1")
        # Source block shifted
        self.assertEqual(buf.block_start_row, 1)

        # Move block from Line 1 to Line 2 Col 0
        buf.cursor_row = 2
        buf.cursor_col = 0
        ok = buf.move_block_to_cursor()
        self.assertTrue(ok)
        self.assertEqual(buf.lines[2], "TARGETLine 3")
        self.assertEqual(buf.lines[1], "Line 2 - ")

        print(
            "[+] Step 15: Direct in-place block methods verified.",
            flush=True,
        )


if __name__ == "__main__":
    t0 = time.time()
    suite = unittest.TestLoader().loadTestsFromTestCase(TestBuffer)
    res = unittest.TextTestRunner(verbosity=1).run(suite)
    elapsed = time.time() - t0
    if res.wasSuccessful():
        print(f"[+] All Buffer tests PASSED in {elapsed:.2f}s!", flush=True)
        sys.exit(0)
    else:
        print("[-] Buffer tests FAILED.", flush=True)
        sys.exit(1)
