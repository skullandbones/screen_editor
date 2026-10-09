"""
Plugin subsystem and Host API bridge for native Python SE editor.
Reflects Upper Memory Host API vectors matching Z80 ABI specifications.
"""

import importlib.util
import os
from typing import Callable, Dict, List, Optional, Tuple


class HostAPI:
    """
    Host API interface exposed to Python plugins.
    Mirrors Z80 Upper Memory Host API trampoline vector table.
    """

    def __init__(self, editor):
        self._editor = editor

    def checkout_line(self, row: int) -> str:
        """Fetch line text at 0-based row index."""
        return self._editor.buffer.get_line(row)

    def commit_line(self, row: int, text: str):
        """Update line text at 0-based row index."""
        self._editor.buffer.set_line(row, text)

    def get_total_lines(self) -> int:
        """Return total document lines."""
        return self._editor.buffer.total_lines

    def get_cursor(self) -> Tuple[int, int]:
        """Return current cursor (row, col)."""
        return self._editor.buffer.cursor_row, self._editor.buffer.cursor_col

    def set_cursor(self, row: int, col: int):
        """Set current cursor (row, col)."""
        self._editor.buffer.cursor_row = max(
            0, min(self._editor.buffer.total_lines - 1, row)
        )
        self._editor.buffer.cursor_col = max(0, col)
        self._editor.buffer.target_col = self._editor.buffer.cursor_col

    def get_block_bounds(self) -> Optional[Tuple[int, int, int, int]]:
        """
        Return normalized (start_row, start_col, end_row, end_col) if active.
        """
        if self._editor.buffer.block_active > 0:
            return self._editor.buffer.get_normalized_block()
        return None

    def set_status_msg(self, msg: str):
        """Set transient status message displayed in status bar."""
        self._editor.status_msg = msg

    def show_modal(self, title: str, message: str):
        """Display a Tier 2 notification modal dialog."""
        self._editor.modal.show_notification(title, message)


class PluginBase:
    """Abstract base class for Python SE plugins."""

    NAME: str = "PLUGIN"
    DESCRIPTION: str = "Base SE Plugin"

    def run(self, api: HostAPI) -> bool:
        """Execute plugin action. Returns True on success."""
        raise NotImplementedError


class PluginManager:
    """
    Manages discovery, loading, and execution of Python SE plugins.
    """

    def __init__(self, editor):
        self.editor = editor
        self.api = HostAPI(editor)
        self.plugins: Dict[str, PluginBase] = {}
        self.discover_plugins()

    def discover_plugins(self):
        """Discover plugins located in plugins directory."""
        plugins_dir = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "plugins",
        )
        if not os.path.isdir(plugins_dir):
            return

        for fname in sorted(os.listdir(plugins_dir)):
            if fname.endswith(".py") and not fname.startswith("__"):
                plugin_path = os.path.join(plugins_dir, fname)
                self.load_plugin_file(plugin_path)

    def load_plugin_file(self, path: str) -> bool:
        """Load a plugin from a Python file path."""
        mod_name = os.path.splitext(os.path.basename(path))[0]
        try:
            spec = importlib.util.spec_from_file_location(mod_name, path)
            if spec and spec.loader:
                mod = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(mod)
                for attr in dir(mod):
                    obj = getattr(mod, attr)
                    if (
                        isinstance(obj, type)
                        and issubclass(obj, PluginBase)
                        and obj is not PluginBase
                    ):
                        instance = obj()
                        self.plugins[instance.NAME.upper()] = instance
                        return True
        except Exception:
            pass
        return False

    def list_plugins(self) -> List[Tuple[str, str]]:
        """Return list of (NAME, DESCRIPTION) for registered plugins."""
        return [(p.NAME, p.DESCRIPTION) for p in self.plugins.values()]

    def execute(self, name: str) -> bool:
        """Execute named plugin."""
        norm_name = name.strip().upper()
        plugin = self.plugins.get(norm_name)
        if plugin:
            return plugin.run(self.api)
        return False
