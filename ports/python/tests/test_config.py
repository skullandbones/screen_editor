#!/usr/bin/env python3
"""
Unit tests for configuration file parser and serializer in SE editor port.
"""

import os
import sys
import tempfile
import time
import unittest

from se.config import Config


class TestConfig(unittest.TestCase):
    """Test suite for SE.CFG parsing, serialization, and default settings."""

    def setUp(self):
        self.cfg = Config()

    def test_default_settings(self):
        """Step 1: Verify default settings match canonical SE specifications."""
        print("[*] Step 1: Verifying default settings...", flush=True)
        self.assertEqual(self.cfg.get("SCREEN"), "120X40")
        self.assertEqual(self.cfg.screen_geometry, (120, 40))
        self.assertEqual(self.cfg.tab_width, 8)
        self.assertTrue(self.cfg.format_cpm)
        self.assertTrue(self.cfg.plugin_autoload)
        self.assertFalse(self.cfg.plugin_disabled)
        print("[+] Step 1: Default settings verified.", flush=True)

    def test_case_insensitive_lookup_and_set(self):
        """Step 2: Verify case-insensitive key-value access and overrides."""
        print(
            "[*] Step 2: Testing case-insensitive configuration...",
            flush=True,
        )
        self.cfg.set("screen", "80x24")
        self.assertEqual(self.cfg.get("SCREEN"), "80x24")
        self.assertEqual(self.cfg.screen_geometry, (80, 24))

        self.cfg.set("screen", "120x40")
        self.assertEqual(self.cfg.get("SCREEN"), "120x40")
        self.assertEqual(self.cfg.screen_geometry, (120, 40))

        self.cfg.set("tab", "4")
        self.assertEqual(self.cfg.tab_width, 4)

        self.cfg.set("custom_key", "custom_val")
        self.assertEqual(self.cfg.get("CUSTOM_KEY"), "custom_val")
        print("[+] Step 2: Case-insensitive access verified.", flush=True)

    def test_load_and_save_cfg(self):
        """Step 3: Verify loading and saving SE.CFG files with CRLF."""
        print(
            "[*] Step 3: Testing SE.CFG load and save with CRLF...",
            flush=True,
        )
        with tempfile.NamedTemporaryFile(
            delete=False, suffix=".cfg"
        ) as tmp_file:
            tmp_path = tmp_file.name

        try:
            # Write sample configuration with comments
            content = (
                "# SE Editor Configuration\r\n"
                "; System settings\r\n"
                "SCREEN=120x40\r\n"
                "TAB=4\r\n"
                "FORMAT=LINUX\r\n"
                "PLUGIN=DISABLED\r\n"
                "RAMDRIVE=OVERWRITE\r\n"
                "MYFLAG=ENABLED\r\n"
            )
            with open(tmp_path, "wb") as f:
                f.write(content.encode("ascii"))

            # Load into config
            loaded = self.cfg.load(tmp_path)
            self.assertTrue(loaded)
            self.assertEqual(self.cfg.screen_geometry, (120, 40))
            self.assertEqual(self.cfg.tab_width, 4)
            self.assertFalse(self.cfg.format_cpm)
            self.assertTrue(self.cfg.plugin_disabled)
            self.assertEqual(self.cfg.get("RAMDRIVE"), "OVERWRITE")
            self.assertEqual(self.cfg.get("MYFLAG"), "ENABLED")

            # Save back out
            saved_path = tmp_path + ".saved"
            saved = self.cfg.save(saved_path)
            self.assertTrue(saved)

            with open(saved_path, "rb") as f:
                saved_bytes = f.read()

            self.assertIn(b"SCREEN=120x40\r\n", saved_bytes)
            self.assertIn(b"TAB=4\r\n", saved_bytes)
            self.assertIn(b"MYFLAG=ENABLED\r\n", saved_bytes)
            os.remove(saved_path)
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)

        print("[+] Step 3: SE.CFG load and save cycle verified.", flush=True)

    def test_secfg_canonical_default_and_discovery(self):
        """Step 4: Verify startup SE.CFG discovery and 120x40 default."""
        print(
            "[*] Step 4: Testing canonical 120x40 default and discovery...",
            flush=True,
        )
        cfg = Config()
        self.assertEqual(cfg.DEFAULT_SCREEN, "120X40")
        self.assertEqual(cfg.screen_geometry, (120, 40))

        # Test custom path discovery
        with tempfile.NamedTemporaryFile(
            delete=False, suffix=".cfg"
        ) as tmp_file:
            tmp_path = tmp_file.name
        try:
            with open(tmp_path, "wb") as f:
                f.write(b"SCREEN=80x24\r\nTAB=4\r\n")

            cfg_custom = Config()
            loaded_path = cfg_custom.discover_and_load(tmp_path)
            self.assertEqual(loaded_path, os.path.abspath(tmp_path))
            self.assertEqual(cfg_custom.screen_geometry, (80, 24))
            self.assertEqual(cfg_custom.tab_width, 4)
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)

        # Test current working directory (./SE.CFG) discovery
        with tempfile.TemporaryDirectory() as tmp_dir:
            cwd_cfg = os.path.join(tmp_dir, "SE.CFG")
            with open(cwd_cfg, "wb") as f:
                f.write(b"SCREEN=80x24\r\nTAB=4\r\n")

            orig_cwd = os.getcwd()
            try:
                os.chdir(tmp_dir)
                cfg_cwd = Config()
                loaded_cwd = cfg_cwd.discover_and_load()
                self.assertEqual(loaded_cwd, os.path.abspath("SE.CFG"))
                self.assertEqual(cfg_cwd.screen_geometry, (80, 24))
                self.assertEqual(cfg_cwd.tab_width, 4)
            finally:
                os.chdir(orig_cwd)

        # Test fallback returns None when no SE.CFG exists
        with tempfile.TemporaryDirectory() as empty_dir:
            orig_cwd = os.getcwd()
            try:
                os.chdir(empty_dir)
                cfg_empty = Config()
                prog_dir = os.path.dirname(
                    os.path.abspath(sys.modules[Config.__module__].__file__)
                )
                prog_cfg = os.path.join(prog_dir, "SE.CFG")
                if not os.path.isfile(prog_cfg):
                    self.assertIsNone(cfg_empty.discover_and_load())
                    self.assertEqual(cfg_empty.screen_geometry, (120, 40))
            finally:
                os.chdir(orig_cwd)

        print("[+] Step 4: Canonical discovery rules verified.", flush=True)


if __name__ == "__main__":
    t0 = time.time()
    suite = unittest.TestLoader().loadTestsFromTestCase(TestConfig)
    res = unittest.TextTestRunner(verbosity=1).run(suite)
    elapsed = time.time() - t0
    if res.wasSuccessful():
        print(f"[+] All Config tests PASSED in {elapsed:.2f}s!", flush=True)
        sys.exit(0)
    else:
        print("[-] Config tests FAILED.", flush=True)
        sys.exit(1)
