"""
Configuration file reader, parser, and serializer for SE editor.
Supports standard SE.CFG formats, defaults, and overrides.
"""

import os
import sys
from typing import Dict, Optional, Tuple


class Config:
    """
    Manages editor configuration settings compatible with SE.CFG.
    """

    DEFAULT_SCREEN = "80X24"
    DEFAULT_TAB_WIDTH = 8
    DEFAULT_FORMAT = "CPM"
    DEFAULT_MAX_LINES = "16K"
    DEFAULT_PLUGIN = "AUTOLOAD"
    DEFAULT_RAMDRIVE = "PRESERVE"

    def __init__(self):
        self.settings: Dict[str, str] = {
            "SCREEN": self.DEFAULT_SCREEN,
            "TAB": str(self.DEFAULT_TAB_WIDTH),
            "FORMAT": self.DEFAULT_FORMAT,
            "MAXLINES": self.DEFAULT_MAX_LINES,
            "PLUGIN": self.DEFAULT_PLUGIN,
            "RAMDRIVE": self.DEFAULT_RAMDRIVE,
        }
        self.custom_settings: Dict[str, str] = {}

    @property
    def screen_geometry(self) -> Tuple[int, int]:
        """Return (cols, rows) tuple corresponding to SCREEN setting."""
        val = self.get("SCREEN", self.DEFAULT_SCREEN).upper()
        if val == "80X24":
            return (80, 24)
        elif val == "NATIVE":
            try:
                sz = os.get_terminal_size()
                if sz.columns > 0 and sz.lines > 0:
                    return (sz.columns, sz.lines)
            except (AttributeError, OSError):
                pass
            return (80, 24)
        return (120, 40)

    @property
    def is_native_screen(self) -> bool:
        """Return True if SCREEN setting is configured as NATIVE."""
        return self.get("SCREEN", self.DEFAULT_SCREEN).upper() == "NATIVE"

    @property
    def screen_cols(self) -> int:
        """Return active screen column count (80 or 120)."""
        return self.screen_geometry[0]

    @property
    def screen_rows(self) -> int:
        """Return active screen row count (24 or 40)."""
        return self.screen_geometry[1]

    @property
    def max_lines(self) -> str:
        """Return maximum line capacity setting (e.g. 16K, 32K)."""
        return self.get("MAXLINES", self.DEFAULT_MAX_LINES).upper()

    @property
    def ramdrive_enabled(self) -> bool:
        """Return True if RAM drive mode is enabled (non-DISABLED)."""
        return self.get("RAMDRIVE", self.DEFAULT_RAMDRIVE).upper() != "DISABLED"

    def save_config(self, path: str = "SE.CFG") -> bool:
        """Save active configuration to target path (default SE.CFG)."""
        return self.save(path)

    @property
    def tab_width(self) -> int:
        """Return tab stop width (4 or 8)."""
        val = self.get("TAB", str(self.DEFAULT_TAB_WIDTH))
        try:
            w = int(val)
            return w if w in (4, 8) else 8
        except ValueError:
            return 8

    @property
    def format_cpm(self) -> bool:
        """Return True if default file save format is CP/M (CRLF)."""
        return self.get("FORMAT", "CPM").upper() == "CPM"

    @property
    def plugin_autoload(self) -> bool:
        """Return True if plugin manager autoloads at startup."""
        return self.get("PLUGIN", "AUTOLOAD").upper() == "AUTOLOAD"

    @property
    def plugin_disabled(self) -> bool:
        """Return True if plugin manager is completely disabled."""
        return self.get("PLUGIN", "AUTOLOAD").upper() == "DISABLED"

    def get(self, key: str, default: Optional[str] = None) -> Optional[str]:
        """Get configuration value by case-insensitive key name."""
        norm_key = key.strip().upper()
        if norm_key in self.settings:
            return self.settings[norm_key]
        return self.custom_settings.get(norm_key, default)

    def set(self, key: str, value: str):
        """Set configuration key-value pair."""
        norm_key = key.strip().upper()
        norm_val = value.strip()
        if norm_key in self.settings:
            self.settings[norm_key] = norm_val
        else:
            self.custom_settings[norm_key] = norm_val

    def load(self, path: str) -> bool:
        """
        Load settings from SE.CFG file.
        Returns True on success, False if file could not be read.
        """
        if not os.path.isfile(path):
            return False
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    line_str = line.strip()
                    if not line_str or line_str.startswith(("#", ";")):
                        continue
                    if "=" in line_str:
                        key, val = line_str.split("=", 1)
                        self.set(key, val)
            return True
        except OSError:
            return False

    def save(self, path: str) -> bool:
        """
        Serialize settings to SE.CFG with standard CRLF line endings.
        """
        try:
            with open(path, "wb") as f:
                for key in sorted(self.settings.keys()):
                    f.write(f"{key}={self.settings[key]}\r\n".encode("ascii"))
                for key in sorted(self.custom_settings.keys()):
                    f.write(
                        f"{key}={self.custom_settings[key]}\r\n".encode(
                            "ascii"
                        )
                    )
            return True
        except OSError:
            return False

    def discover_and_load(
        self, custom_path: Optional[str] = None
    ) -> Optional[str]:
        """
        Probe and load SE.CFG according to canonical discovery priority:
        1. Explicit custom path if provided.
        2. Current working directory (./SE.CFG).
        3. Program directory (location of SE package/executable).
        Returns the path loaded, or None if no configuration file was found.
        """
        if custom_path:
            norm_path = os.path.abspath(custom_path)
            if os.path.isfile(norm_path) and self.load(norm_path):
                return norm_path
            return None

        # Priority 1: Current working directory
        cwd_cfg = os.path.abspath("SE.CFG")
        if os.path.isfile(cwd_cfg) and self.load(cwd_cfg):
            return cwd_cfg

        # Priority 2: Program directory
        prog_dir = os.path.dirname(os.path.abspath(__file__))
        prog_cfg = os.path.join(prog_dir, "SE.CFG")
        if os.path.isfile(prog_cfg) and self.load(prog_cfg):
            return prog_cfg

        # Fallback: check sys.argv[0] directory if different
        if getattr(sys, "argv", None) and sys.argv and sys.argv[0]:
            argv_dir = os.path.dirname(os.path.abspath(sys.argv[0]))
            argv_cfg = os.path.join(argv_dir, "SE.CFG")
            if os.path.isfile(argv_cfg) and self.load(argv_cfg):
                return argv_cfg

        return None

