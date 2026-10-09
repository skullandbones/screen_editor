"""
Configuration file reader, parser, and serializer for SE editor.
Supports standard SE.CFG formats, defaults, and overrides.
"""

import os
from typing import Dict, Optional, Tuple


class Config:
    """
    Manages editor configuration settings compatible with SE.CFG.
    """

    DEFAULT_SCREEN = "80x24"
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
        if val == "120X40":
            return (120, 40)
        return (80, 24)

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
