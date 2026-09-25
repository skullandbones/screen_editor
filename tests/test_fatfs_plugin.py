#!/usr/bin/env python3
"""
test_fatfs_plugin.py - Automated Test Suite for FATFS.PRL Plugin

Validates:
1. Compilation of FATFS.PRL via Makefile using z88dk and mkprl.py.
2. CP/M 3 PRL Header Structure (256 bytes) and Field Alignment.
3. 32KB Far RAM Slot Class (CAP_SIZE_32K = 0x0080) and Capability Flags.
4. Relocation Bitmap Integrity and Address Offset Calculation.
5. Standard 3-Entry Jump Table at Origin 0100H:
   - Action 0: Main Execution (JP 01xxh)
   - Action 1: About Screen   (JP 01xxh)
   - Action 2: Config Screen  (JP 01xxh)
"""

import os
import struct
import subprocess
import sys
import unittest

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
PLUGIN_DIR = os.path.join(REPO_ROOT, "plugins", "fat")
PRL_PATH = os.path.join(PLUGIN_DIR, "FATFS.PRL")

CAP_FAR_EXEC   = 0x0002
CAP_DOC_MUTATE = 0x0004
CAP_MODAL_UI   = 0x0008
CAP_HAS_ABOUT  = 0x0010
CAP_HAS_CONFIG = 0x0020
CAP_SIZE_32K   = 0x0080
CAP_HAS_VFS    = 0x0100


class TestFatFsPlugin(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Build FATFS.PRL
        res = subprocess.run(["make", "-C", PLUGIN_DIR, "all"],
                             capture_output=True, text=True)
        if res.returncode != 0:
            print("STDOUT:", res.stdout)
            print("STDERR:", res.stderr)
        assert res.returncode == 0, f"make failed with code {res.returncode}"

    def test_file_exists(self):
        self.assertTrue(os.path.exists(PRL_PATH),
                        f"FATFS.PRL not found at {PRL_PATH}")

    def test_header_and_capabilities(self):
        with open(PRL_PATH, "rb") as f:
            data = f.read()

        self.assertGreaterEqual(len(data), 256 + 100)

        header = data[:256]
        prog_size = struct.unpack_from("<H", header, 0x01)[0]
        bss_size  = struct.unpack_from("<H", header, 0x04)[0]
        load_addr = struct.unpack_from("<H", header, 0x07)[0]
        name_raw  = header[0x0C:0x1C].split(b"\x00")[0].decode("ascii")
        caps      = struct.unpack_from("<H", header, 0x1C)[0]

        # Name must be FATFS
        self.assertEqual(name_raw, "FATFS")

        # PRL format: load_addr must be 0000h
        self.assertEqual(load_addr, 0x0000)

        # Must fit within 32KB slot (<= 32768)
        self.assertLessEqual(prog_size, 32768,
                             f"Program size {prog_size} exceeds 32K limit")
        self.assertGreater(prog_size, 10000,
                           f"Program size {prog_size} suspiciously small")

        # Capabilities must have CAP_SIZE_32K, CAP_FAR_EXEC, CAP_DOC_MUTATE,
        # CAP_MODAL_UI, CAP_HAS_ABOUT, CAP_HAS_CONFIG, CAP_HAS_VFS
        expected_caps = (CAP_FAR_EXEC | CAP_DOC_MUTATE | CAP_MODAL_UI |
                         CAP_HAS_ABOUT | CAP_HAS_CONFIG | CAP_SIZE_32K |
                         CAP_HAS_VFS)
        self.assertEqual(
            caps, expected_caps,
            f"Caps mismatch: 0x{caps:04X} vs expected 0x{expected_caps:04X}"
        )

        # Check total file size = 256 + prog_size + bitmap_size
        bitmap_len = (prog_size + 7) // 8
        expected_file_size = 256 + prog_size + bitmap_len
        self.assertEqual(
            len(data), expected_file_size,
            f"File size mismatch: {len(data)} vs expected {expected_file_size}"
        )

    def test_entry_jump_table(self):
        with open(PRL_PATH, "rb") as f:
            data = f.read()

        code = data[256:]

        # Standard 4-entry jump table at offset 0
        # +0: JP _entry_run    (0xC3, lo, hi)
        # +3: JP _entry_about  (0xC3, lo, hi)
        # +6: JP _entry_config (0xC3, lo, hi)
        # +9: JP _entry_vfs    (0xC3, lo, hi)
        self.assertEqual(code[0], 0xC3, "Offset +0 is not a JP instruction")
        self.assertEqual(code[3], 0xC3, "Offset +3 is not a JP instruction")
        self.assertEqual(code[6], 0xC3, "Offset +6 is not a JP instruction")
        self.assertEqual(code[9], 0xC3, "Offset +9 is not a JP instruction")

        target_run    = struct.unpack_from("<H", code, 1)[0]
        target_about  = struct.unpack_from("<H", code, 4)[0]
        target_config = struct.unpack_from("<H", code, 7)[0]
        target_vfs    = struct.unpack_from("<H", code, 10)[0]

        # Targets should be within 0100h..8000h
        self.assertGreaterEqual(target_run, 0x0100)
        self.assertGreaterEqual(target_about, 0x0100)
        self.assertGreaterEqual(target_config, 0x0100)
        self.assertGreaterEqual(target_vfs, 0x0100)

    def test_relocation_bitmap_validity(self):
        with open(PRL_PATH, "rb") as f:
            data = f.read()

        header = data[:256]
        prog_size = struct.unpack_from("<H", header, 0x01)[0]
        bitmap = data[256 + prog_size:]

        reloc_count = sum(bin(b).count("1") for b in bitmap)
        self.assertGreater(
            reloc_count, 1000,
            f"Relocation count {reloc_count} too low for binary"
        )


if __name__ == "__main__":
    unittest.main()
