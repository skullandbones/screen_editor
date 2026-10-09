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

from se.buffer import DocumentBuffer, MAX_LINE_LENGTH


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

    def test_insertion_and_120_col_limit(self):
        """Step 2: Verify typing insertion and 120-char line limit."""
        print(
            "[*] Step 2: Testing character insertion & 120 limit...",
            flush=True,
        )
        for ch in "HELLO WORLD":
            ok = self.buf.insert_char(ch)
            self.assertTrue(ok)
        self.assertEqual(self.buf.current_line, "HELLO WORLD")
        self.assertEqual(self.buf.cursor_col, 11)
        self.assertTrue(self.buf.modified)

        # Extend line to 120 chars
        remaining = MAX_LINE_LENGTH - len("HELLO WORLD")
        for _ in range(remaining):
            self.buf.insert_char("X")
        self.assertEqual(len(self.buf.current_line), 120)

        # 121st character must be blocked
        blocked = self.buf.insert_char("Z")
        self.assertFalse(blocked)
        self.assertEqual(len(self.buf.current_line), 120)
        print(
            "[+] Step 2: Insertion and 120-column limit verified.",
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
