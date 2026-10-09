"""
Core Editor controller and interactive command dispatch loop for SE editor.
Implements WordStar keybindings, workspace transitions, and modal workflows.
"""

import os
from typing import Optional
from se.buffer import DocumentBuffer
from se.config import Config
from se.modal import ModalDialog
from se.plugin import PluginManager
from se.terminal import (
    Terminal,
    KEY_UP,
    KEY_DOWN,
    KEY_LEFT,
    KEY_RIGHT,
    KEY_HOME,
    KEY_END,
    KEY_PGUP,
    KEY_PGDN,
    KEY_DELETE,
    KEY_ESC,
    KEY_ENTER,
    KEY_TAB,
    KEY_BACKSPACE,
    KEY_CTRL_A,
    KEY_CTRL_B,
    KEY_CTRL_C,
    KEY_CTRL_D,
    KEY_CTRL_E,
    KEY_CTRL_F,
    KEY_CTRL_G,
    KEY_CTRL_K,
    KEY_CTRL_L,
    KEY_CTRL_N,
    KEY_CTRL_O,
    KEY_CTRL_P,
    KEY_CTRL_Q,
    KEY_CTRL_R,
    KEY_CTRL_S,
    KEY_CTRL_T,
    KEY_CTRL_U,
    KEY_CTRL_V,
    KEY_CTRL_X,
    KEY_CTRL_Y,
)
from se.ui import UIRenderer


class Editor:
    """
    Main editor application controller.
    """

    def __init__(self, filename: Optional[str] = None):
        self.config = Config()
        cols, rows = self.config.screen_geometry
        self.terminal = Terminal(default_cols=cols, default_rows=rows)
        self.renderer = UIRenderer(self.terminal)
        self.modal = ModalDialog(self.terminal)
        self.buffer = DocumentBuffer(filename=filename)
        self.search_query: str = ""
        self.replace_query: str = ""
        self.case_sensitive: bool = True
        self.running: bool = False
        self.status_msg: Optional[str] = None
        self.plugin_mgr = PluginManager(self)

        if filename and os.path.isfile(filename):
            self.buffer.load_file(filename)

    def run(self):
        """Run the main interactive editor event loop."""
        self.terminal.enter_raw_mode()
        self.running = True

        try:
            while self.running:
                geom_str = f"{self.terminal.cols}x{self.terminal.rows}"
                self.renderer.render_editor(
                    self.buffer,
                    geometry_str=geom_str,
                    status_msg=self.status_msg,
                )
                self.status_msg = None

                key = self.terminal.get_key()
                if key is None:
                    continue

                self.dispatch_key(key)
        finally:
            self.terminal.exit_raw_mode()

    def dispatch_key(self, key: str):
        """Dispatch a single keypress or symbolic action."""
        # 1. Navigation Keys
        if key == KEY_LEFT:
            self.buffer.move_left()
        elif key == KEY_RIGHT or key == KEY_CTRL_D:
            self.buffer.move_right()
        elif key == KEY_UP:
            self.buffer.move_up()
        elif key == KEY_DOWN:
            self.buffer.move_down()
        elif key == KEY_HOME or key == KEY_CTRL_A:
            self.buffer.move_home()
        elif key == KEY_END or key == KEY_CTRL_E:
            self.buffer.move_end()
        elif key == KEY_CTRL_T or key == "JUMP_TOP":
            self.buffer.move_top()
        elif key == KEY_CTRL_G or key == "JUMP_BOTTOM":
            self.buffer.move_bottom()
        elif key == KEY_PGUP or key == KEY_CTRL_U:
            self.buffer.page_up(self.terminal.rows - 2)
        elif key == KEY_PGDN or key == KEY_CTRL_V:
            self.buffer.page_down(self.terminal.rows - 2)

        # 2. Text Editing & Layout
        elif key == KEY_ENTER:
            self.buffer.split_line()
        elif key == KEY_BACKSPACE:
            self.buffer.backspace()
        elif key == KEY_DELETE:
            self.buffer.delete_char()
        elif key == KEY_TAB:
            # Expand tab to spaces based on config tab width
            spaces = self.config.tab_width - (
                self.buffer.cursor_col % self.config.tab_width
            )
            for _ in range(spaces):
                self.buffer.insert_char(" ")

        # 3. Block Selection & Clipboard
        elif key == KEY_CTRL_B:
            self.buffer.toggle_block()
        elif key == KEY_CTRL_C:
            copied = self.buffer.copy_block()
            if copied:
                self.status_msg = f"Copied {len(copied)}c"
        elif key == KEY_CTRL_X:
            cut = self.buffer.cut_block()
            if cut:
                self.status_msg = f"Cut {len(cut)}c"

        # 4. Modals and Workspaces
        elif key == KEY_CTRL_F:
            self.action_find()
        elif key == KEY_CTRL_N:
            self.action_find_next()
        elif key == KEY_CTRL_R:
            self.action_replace()
        elif key == KEY_CTRL_L:
            self.action_goto_line()
        elif key == KEY_CTRL_K:
            self.action_help()
        elif key == KEY_CTRL_O:
            self.action_open_file()
        elif key == KEY_CTRL_S:
            self.action_save_file()
        elif key == KEY_CTRL_P:
            self.action_plugin_palette()
        elif key == KEY_CTRL_Y:
            self.action_beautify()
        elif key == KEY_CTRL_Q:
            self.action_quit()
        elif key == KEY_ESC:
            self.action_splash_screen()

        # 5. Printable Character Insertion
        elif len(key) == 1 and 32 <= ord(key) <= 126:
            self.buffer.insert_char(key)

    def action_quit(self):
        """Prompt to save changes if modified, then exit cleanly."""
        if self.buffer.modified:
            ans = self.modal.show_confirm(
                title="Unsaved Modifications",
                desc="Any unsaved edits will be lost if discarded.",
                query="Save changes?",
                options_text="[Y]es      [N]o      [ESC]=Cancel",
            )
            if ans is None:
                return  # Cancelled
            if ans == "y":
                if not self.action_save_file():
                    return  # Save cancelled or failed

        self.running = False

    def action_goto_line(self):
        """Prompt for line number in Tier 2 modal and jump cursor."""
        ans = self.modal.show_input(
            title="Goto Line",
            desc="Enter target line number to jump to",
            label="Goto line:",
            options_text="[Enter]=Goto Line      [ESC]=Cancel",
        )
        if ans and ans.strip().isdigit():
            target_line = int(ans.strip())
            # Convert 1-based line number to 0-based row
            target_row = max(
                0, min(self.buffer.total_lines - 1, target_line - 1)
            )
            self.buffer.cursor_row = target_row
            self.buffer.cursor_col = 0
            self.buffer.target_col = 0

    def action_find(self):
        """Prompt for search text and search forward from cursor."""
        query = self.modal.show_input(
            title="Find Text",
            desc="Enter search string to locate",
            label="Find:",
            initial_text=self.search_query,
            options_text="[Enter]=Find      [ESC]=Cancel",
        )
        if query:
            self.search_query = query
            self.action_find_next()

    def action_find_next(self):
        """Find next occurrence of search_query."""
        if not self.search_query:
            return

        query = self.search_query
        target = query if self.case_sensitive else query.lower()

        # Search starting from next character position
        start_row = self.buffer.cursor_row
        start_col = self.buffer.cursor_col

        found = False
        tot = self.buffer.total_lines

        for offset in range(tot):
            r = (start_row + offset) % tot
            line = self.buffer.get_line(r)
            comp_line = line if self.case_sensitive else line.lower()

            c_from = (start_col + 1) if offset == 0 else 0
            idx = comp_line.find(target, c_from)
            if idx != -1:
                self.buffer.cursor_row = r
                self.buffer.cursor_col = idx
                self.buffer.target_col = idx

                # Lock highlighted block on match
                self.buffer.block_active = 2
                self.buffer.block_start_row = r
                self.buffer.block_start_col = idx
                self.buffer.block_end_row = r
                self.buffer.block_end_col = idx + len(query)

                found = True
                break

        if not found:
            self.modal.show_notification(
                title="Search Result", message="Pattern not found."
            )

    def action_replace(self):
        """Search and replace prompt workflow."""
        find_q = self.modal.show_input(
            title="Search and Replace",
            desc="Enter search string to match",
            label="Find:",
            initial_text=self.search_query,
        )
        if not find_q:
            return
        self.search_query = find_q

        rep_q = self.modal.show_input(
            title="Replace Text",
            desc="Enter replacement text to substitute for match",
            label="Replace with:",
            initial_text=self.replace_query,
            options_text="[Enter]=Confirm      [ESC]=Cancel",
        )
        if rep_q is None:
            return
        self.replace_query = rep_q

        # Perform replacement loop on matches
        replacements = 0
        for r in range(self.buffer.total_lines):
            line = self.buffer.get_line(r)
            if find_q in line:
                new_line = line.replace(find_q, rep_q)
                self.buffer.set_line(r, new_line)
                replacements += line.count(find_q)

        self.modal.show_notification(
            title="Replace Complete",
            message=f"Replace done: {replacements} replacement(s).",
        )

    def action_help(self):
        """Display full-screen Help workspace."""
        lines = [
            "SE.COM — EDITOR MODE KEYS",
            "",
            "Cursor Navigation:                 Block Operations:",
            "  Arrows / WordStar (^S,^D,^E,^X)     Ctrl+B: Toggle Block",
            "  Ctrl+A / Ctrl+E: Home / End         Ctrl+C: Copy Block",
            "  Ctrl+T / Ctrl+G: Top / Bottom       Ctrl+X: Cut Block",
            "  Ctrl+U / Ctrl+V: Page Up / Down     Ctrl+V: Paste Block",
            "",
            "Search & Replace:                  File & System:",
            "  Ctrl+F: Find Text                   Ctrl+S: Save File",
            "  Ctrl+N: Find Next                   Ctrl+O: Open File",
            "  Ctrl+R: Search and Replace          Ctrl+Q: Safe Quit",
            "  Ctrl+L: Goto Line Number            Ctrl+P: Plugin Palette",
            "  Ctrl+Y: Beautify Source Code        ESC   : Splash Screen",
            "",
            "Press any key to return to editor",
        ]
        geom = f"{self.terminal.cols}x{self.terminal.rows}"
        self.renderer.render_centered_workspace(
            lines, self.buffer, geometry_str=geom
        )
        self.terminal.get_key()

    def action_open_file(self):
        """Display directory browser and open selected file."""
        filename = self.modal.show_input(
            title="Open File",
            desc="Enter filename to open",
            label="Filename:",
            initial_text="",
        )
        if filename:
            if os.path.isfile(filename):
                self.buffer.load_file(filename)
            else:
                self.modal.show_notification(
                    title="Open Error", message="File not found"
                )

    def action_save_file(self) -> bool:
        """Prompt for filename and save document."""
        is_untitled = self.buffer.filename == "(Untitled)"
        initial = "" if is_untitled else self.buffer.filename
        target_name = self.modal.show_input(
            title="Save File",
            desc="Enter filename to save",
            label="Filename:",
            initial_text=initial,
        )
        if not target_name:
            return False

        if os.path.exists(target_name) and target_name != self.buffer.filename:
            ans = self.modal.show_confirm(
                title="Overwrite Warning",
                desc="File already exists on disk.",
                query=f"Overwrite {target_name}?",
            )
            if ans != "y":
                return False

        ok = self.buffer.save_file(target_name)
        if ok:
            self.modal.show_notification(
                title="Save Complete", message=f"Saved to {target_name}"
            )
            return True
        else:
            self.modal.show_notification(
                title="Save Error", message=f"Could not write to {target_name}"
            )
            return False

    def action_splash_screen(self):
        """Display full-screen Splash screen workspace."""
        lines = [
            "SE — Screen Editor",
            "Version v1.1.0 (Python Native Linux)",
            "",
            "Free Memory: [Dynamic Heap]   Lines: [32K Max]",
            "",
            ":e to edit",
            ":o to open file",
            ":s to save file",
            ":c for config",
            ":p for plugins",
            ":? for help",
            ":q to quit",
            "",
            "Enter choice: ",
        ]
        geom = f"{self.terminal.cols}x{self.terminal.rows}"
        self.renderer.render_centered_workspace(
            lines, self.buffer, geometry_str=geom
        )

        while True:
            k = self.terminal.get_key()
            if not k:
                continue
            ch = k.lower()
            if ch in ("e", "\r"):
                return  # Return to editor
            elif ch == "o":
                self.action_open_file()
                return
            elif ch == "s":
                self.action_save_file()
                return
            elif ch == "c":
                self.action_config_screen()
                self.renderer.render_centered_workspace(
                    lines, self.buffer, geometry_str=geom
                )
            elif ch == "p":
                self.action_plugin_palette()
                self.renderer.render_centered_workspace(
                    lines, self.buffer, geometry_str=geom
                )
            elif ch == "?":
                self.action_help()
                self.renderer.render_centered_workspace(
                    lines, self.buffer, geometry_str=geom
                )
            elif ch == "q":
                self.action_quit()
                return

    def action_plugin_palette(self):
        """Display context-aware plugin palette modal and execute choice."""
        plugins = self.plugin_mgr.list_plugins()
        if not plugins:
            self.modal.show_notification(
                title="Plugin Palette",
                message="No plugins loaded.",
            )
            return

        choice = self.modal.show_menu(
            title="Plugin Palette",
            desc="Select a plugin to execute:",
            items=plugins,
        )
        if choice is not None and 0 <= choice < len(plugins):
            plugin_name, _ = plugins[choice]
            self.plugin_mgr.execute(plugin_name)

    def action_beautify(self):
        """Execute BEAUTIFY plugin on current block or document."""
        if not self.plugin_mgr.execute("BEAUTIFY"):
            self.modal.show_notification(
                title="Plugin Error",
                message="BEAUTIFY plugin not loaded.",
            )
        else:
            self.buffer.block_active = 0

    def action_config_screen(self):
        """Display centered Configuration Screen workspace."""
        while True:
            cols = self.config.screen_cols
            rows = self.config.screen_rows
            ram = "Enabled" if self.config.ramdrive_enabled else "Disabled"
            lines = [
                "SE — Configuration Manager",
                "",
                f"1. Screen Geometry  : {cols}x{rows}",
                f"2. Tab Width        : {self.config.tab_width}",
                f"3. Max Line Capacity: {self.config.max_lines}",
                f"4. RAM Drive Mode   : {ram}",
                "",
                "[S] Save to SE.CFG    [ESC]/[Enter] Return to Splash",
                "",
                "Enter option: ",
            ]
            geom = f"{self.terminal.cols}x{self.terminal.rows}"
            self.renderer.render_centered_workspace(
                lines, self.buffer, geometry_str=geom
            )

            k = self.terminal.get_key()
            if not k:
                continue
            ch = k.lower()
            if ch in ("\r", "\x1b", "q"):
                return
            elif ch == "1":
                if self.config.screen_cols == 80:
                    self.config.screen_cols = 120
                    self.config.screen_rows = 40
                else:
                    self.config.screen_cols = 80
                    self.config.screen_rows = 24
                self.terminal.cols = self.config.screen_cols
                self.terminal.rows = self.config.screen_rows
            elif ch == "2":
                self.config.tab_width = 8 if self.config.tab_width == 4 else 4
            elif ch == "s":
                self.config.save_config()
                self.modal.show_notification(
                    title="Config Saved",
                    message="Configuration saved to SE.CFG.",
                )

