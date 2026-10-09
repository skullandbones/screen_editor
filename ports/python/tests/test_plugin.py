"""
Unit tests for Python SE Editor plugin subsystem and built-in plugins.
Conforms to Rule 9 output standards and <= 80 chars line length.
"""

import unittest
from se.buffer import DocumentBuffer
from se.editor import Editor
from se.plugin import PluginManager, HostAPI
from plugins.beautify import beautify_asm_line
from plugins.rot13 import rot13_text


class TestPluginSubsystem(unittest.TestCase):
    """Test suite validating plugin manager and built-in plugins."""

    def setUp(self):
        self.editor = Editor()
        self.manager = PluginManager(self.editor)
        self.api = HostAPI(self.editor)

    def test_01_plugin_discovery(self):
        """Step 1: Discover registered plugins in plugins directory."""
        print("[*] Step 1: Discovering registered plugins...", flush=True)
        plugins = dict(self.manager.list_plugins())
        self.assertIn("ROT13", plugins)
        self.assertIn("WORDCNT", plugins)
        self.assertIn("BEAUTIFY", plugins)
        print("[+] Step 1: Registered plugins discovered.", flush=True)

    def test_02_rot13_line_and_block(self):
        """Step 2: Test ROT13 execution on line and block selection."""
        print("[*] Step 2: Testing ROT13 transformation...", flush=True)
        # Line transformation
        self.editor.buffer.set_line(0, "Hello World")
        self.editor.buffer.cursor_row = 0
        self.editor.buffer.cursor_col = 0
        self.editor.buffer.block_active = 0

        ok = self.manager.execute("ROT13")
        self.assertTrue(ok)
        self.assertEqual(self.editor.buffer.get_line(0), "Uryyb Jbeyq")

        # Second ROT13 restores original text
        ok = self.manager.execute("ROT13")
        self.assertTrue(ok)
        self.assertEqual(self.editor.buffer.get_line(0), "Hello World")

        # Block transformation
        self.editor.buffer.set_line(0, "ABCDEFGHIJ")
        self.editor.buffer.block_active = 2
        self.editor.buffer.block_start_row = 0
        self.editor.buffer.block_start_col = 3
        self.editor.buffer.block_end_row = 0
        self.editor.buffer.block_end_col = 7

        ok = self.manager.execute("ROT13")
        self.assertTrue(ok)
        # Characters 3..7 ("DEFG") -> "QRSF" ? D->Q, E->R, F->S, G->T
        # 'D'(68)->Q, 'E'(69)->R, 'F'(70)->S, 'G'(71)->T
        expected = "ABC" + rot13_text("DEFG") + "HIJ"
        self.assertEqual(self.editor.buffer.get_line(0), expected)
        print("[+] Step 2: ROT13 transformations verified.", flush=True)

    def test_03_wordcnt_execution(self):
        """Step 3: Test WORDCNT execution on document."""
        print("[*] Step 3: Testing WORDCNT plugin execution...", flush=True)
        self.editor.buffer.lines = [
            "The quick brown fox",
            "jumps over the lazy dog",
        ]
        self.editor.buffer.block_active = 0
        modal_captures = []
        self.editor.modal.show_notification = (
            lambda title, msg: modal_captures.append((title, msg))
        )
        ok = self.manager.execute("WORDCNT")
        self.assertTrue(ok)
        self.assertEqual(len(modal_captures), 1)
        title, msg = modal_captures[0]
        self.assertEqual(title, "Word Count")
        self.assertIn("Lines     : 2", msg)
        self.assertIn("Words     : 9", msg)
        print("[+] Step 3: WORDCNT plugin execution verified.", flush=True)

    def test_04_beautify_formatting(self):
        """Step 4: Test BEAUTIFY plugin Z80 assembly code alignment."""
        print("[*] Step 4: Testing BEAUTIFY formatting...", flush=True)
        raw_line = "start: ld a, 10 ; init count"
        formatted = beautify_asm_line(raw_line)
        self.assertTrue(formatted.startswith("start:"))
        self.assertIn("LD", formatted)
        self.assertIn("; init count", formatted)

        # Full document beautify
        self.editor.buffer.lines = [
            "loop: djnz loop ; loop back",
            "ret",
        ]
        self.editor.buffer.block_active = 0
        ok = self.manager.execute("BEAUTIFY")
        self.assertTrue(ok)
        self.assertTrue(self.editor.buffer.get_line(0).startswith("loop:"))
        self.assertIn("DJNZ", self.editor.buffer.get_line(0))
        print("[+] Step 4: BEAUTIFY formatting verified.", flush=True)

    def test_05_host_api_primitives(self):
        """Step 5: Test HostAPI getter and setter primitives."""
        print("[*] Step 5: Testing HostAPI primitives...", flush=True)
        self.api.commit_line(0, "Test Host API")
        self.assertEqual(self.api.checkout_line(0), "Test Host API")
        self.assertEqual(self.api.get_total_lines(), 1)

        self.api.set_cursor(0, 5)
        self.assertEqual(self.api.get_cursor(), (0, 5))

        self.api.set_status_msg("Plugin Status")
        self.assertEqual(self.editor.status_msg, "Plugin Status")
        print("[+] Step 5: HostAPI primitives verified.", flush=True)


if __name__ == "__main__":
    unittest.main()
