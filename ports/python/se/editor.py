"""
Core Editor controller and interactive command dispatch loop for SE editor.
Implements WordStar keybindings, workspace transitions, and modal workflows.
"""

import fnmatch
import os
from typing import List, Optional, Tuple
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
    KEY_CTRL_W,
    KEY_CTRL_X,
    KEY_CTRL_Y,
)
from se.ui import UIRenderer


class Editor:
    """
    Main editor application controller.
    """

    def __init__(
        self,
        filename: Optional[str] = None,
        config_path: Optional[str] = None,
    ):
        self.config = Config()
        self.loaded_config_path = self.config.discover_and_load(config_path)
        cols, rows = self.config.screen_geometry
        is_fixed = not self.config.is_native_screen
        self.terminal = Terminal(
            default_cols=cols, default_rows=rows, fixed_geometry=is_fixed
        )
        self.renderer = UIRenderer(self.terminal)
        self.modal = ModalDialog(self.terminal)
        self.buffer = DocumentBuffer(
            filename=filename, tab_width=self.config.tab_width
        )
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
        self.terminal.term_init()
        self.running = True

        if not self.buffer.has_file:
            self.action_splash_screen()

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
            self.terminal.term_exit()
            self.terminal.exit_raw_mode()

    def dispatch_key(self, key: str):
        """Dispatch a single keypress or symbolic action."""
        # 1. Navigation Keys
        if key == KEY_LEFT:
            self.buffer.move_left()
        elif key == KEY_RIGHT:
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
        elif key in (KEY_PGDN, KEY_CTRL_V):
            self.buffer.page_down(self.terminal.rows - 2)

        # 2. Text Editing & Layout
        elif key == KEY_ENTER:
            if self.buffer.block_active == 1:
                self.buffer.solidify_block()
            else:
                if self.buffer.block_active > 0:
                    self.buffer.cancel_block()
                self.buffer.split_line()
        elif key == KEY_BACKSPACE:
            if self.buffer.block_active == 1:
                self.buffer.cancel_block()
            else:
                if self.buffer.block_active > 0:
                    self.buffer.cancel_block()
                self.buffer.backspace()
        elif key == KEY_DELETE or key == KEY_CTRL_D:
            if self.buffer.block_active > 0:
                self.buffer.delete_block()
            else:
                self.buffer.delete_char()
        elif key == KEY_TAB:
            if self.buffer.block_active == 1:
                self.buffer.cancel_block()
            else:
                if self.buffer.block_active > 0:
                    self.buffer.cancel_block()
                self.buffer.insert_char("\t")

        # 3. Block Selection & Manipulation
        elif key == KEY_CTRL_B:
            self.buffer.toggle_block()
        elif key == KEY_CTRL_C:
            self.buffer.copy_block_to_cursor()
        elif key == KEY_CTRL_X:
            self.buffer.move_block_to_cursor()

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
            if self.buffer.block_active > 0:
                self.action_block_popup()
            elif self.terminal.is_key_ready(timeout=0.1):
                next_k = self.terminal.get_key()
                if next_k in ("r", "R"):
                    self.action_insert_file()
                elif next_k in ("s", "S"):
                    self.action_block_save()
                elif next_k in ("q", "Q", "x", "X"):
                    self.action_quit()
                elif next_k == KEY_ESC:
                    pass
                else:
                    self.action_help()
            else:
                self.action_help()
        elif key == KEY_CTRL_O:
            if self.buffer.block_active > 0:
                self.action_insert_file()
            else:
                self.action_open_file()
        elif key == KEY_CTRL_S:
            if self.buffer.block_active > 0:
                self.action_block_save()
            else:
                self.action_save_file()
        elif key == KEY_CTRL_W:
            self.action_close_file(to_splash=True)
        elif key == KEY_CTRL_P:
            self.action_plugin_palette()
        elif key == KEY_CTRL_Y:
            self.action_beautify()
        elif key == KEY_CTRL_Q:
            self.action_quit()
        elif key == KEY_ESC:
            if self.buffer.block_active > 0:
                self.buffer.cancel_block()
            else:
                self.action_splash_screen()

        # 5. Printable Character Insertion
        elif len(key) == 1 and 32 <= ord(key) <= 126:
            if self.buffer.block_active == 1:
                self.buffer.cancel_block()
            else:
                if self.buffer.block_active > 0:
                    self.buffer.cancel_block()
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
        """Prompt for search text with Tab case toggle and search forward."""
        initial = self.search_query
        if self.buffer.block_active > 0:
            selected = self.buffer.get_selected_text()
            if selected:
                initial = selected.split("\n")[0]

        query, case_sens = self.modal.show_find_dialog(
            initial_text=initial,
            initial_case_sensitive=self.case_sensitive,
        )
        self.case_sensitive = case_sens
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
        """Display full-screen Help workspace (17 lines, 70 cols)."""
        lines = [
            "SE - EDITOR MODE KEYS".center(70),
            "",
            "  Cursor Navigation:".ljust(38) + "Block Operations:",
            "    Arrow Keys / Arrows / ANSI VT100".ljust(38)
            + "Ctrl+B: Toggle Block",
            "    Ctrl+A / Ctrl+E: Home / End".ljust(38)
            + "Ctrl+C: Copy Block to Cursor",
            "    Ctrl+T / Ctrl+G: Top / Bottom".ljust(38)
            + "Ctrl+X: Move Block to Cursor",
            "    PgUp / PgDn : Page Up / Down".ljust(38)
            + "Ctrl+D: Delete Block",
            "",
            "  Search & Replace:".ljust(38) + "File & System:",
            "    Ctrl+F: Find Text".ljust(38) + "Ctrl+S: Save File",
            "    Ctrl+N: Find Next".ljust(38) + "Ctrl+O: Open File",
            "    Ctrl+R: Search and Replace".ljust(38) + "Ctrl+Q: Safe Quit",
            "    Ctrl+L: Goto Line Number".ljust(38) + "Ctrl+P: Plugin Palette",
            "    Ctrl+Y: Beautify Source Code".ljust(38)
            + "ESC   : Splash Screen",
            "",
            "Press any key to continue".center(70),
            "",
        ]
        geom = f"{self.terminal.cols}x{self.terminal.rows}"
        self.renderer.render_centered_workspace(
            lines, self.buffer, geometry_str=geom
        )
        self.terminal.get_key()

    @staticmethod
    def _get_dir_entries(
        dir_path: str, pattern: Optional[str] = None
    ) -> List[str]:
        """List subdirectories and files matching optional filter pattern."""
        try:
            raw_entries = os.listdir(dir_path)
        except OSError:
            return []
        dirs = []
        files = []
        if dir_path != "/":
            dirs.append("../")
        for name in sorted(raw_entries, key=lambda s: s.lower()):
            if name.startswith(".") and not (
                pattern and pattern.startswith(".")
            ):
                continue
            full = os.path.join(dir_path, name)
            if os.path.isdir(full):
                dirs.append(name + "/")
            else:
                if pattern:
                    if fnmatch.fnmatch(name.lower(), pattern.lower()):
                        files.append(name)
                else:
                    files.append(name)
        return dirs + files

    def action_directory_browser(
        self,
        mode: str = "open",
        initial_text: str = "",
    ) -> Optional[Tuple[str, bool]]:
        """
        Interactive full-screen Tier 1 Directory Browser workspace.
        Supports Open, Save, Insert, and Block Save modes.
        """
        current_dir = os.path.abspath(os.getcwd())
        filter_pattern: Optional[str] = None
        input_text = initial_text
        cursor_pos = len(input_text)
        page_idx = 0
        fmt_cpm = self.buffer.format_cpm
        geometry_str = f"{self.terminal.cols}x{self.terminal.rows}"
        if geometry_str not in ("80x24", "120x40"):
            geometry_str = "80x24"

        need_full_render = True
        all_entries: List[str] = []
        page_capacity = 60
        grid_rows = 12

        while True:
            if self.terminal.resized:
                self.terminal.update_geometry()
                geometry_str = f"{self.terminal.cols}x{self.terminal.rows}"
                if geometry_str not in ("80x24", "120x40"):
                    geometry_str = "80x24"
                need_full_render = True

            num_cols = 7 if self.terminal.cols >= 120 else 5
            grid_rows = 28 if self.terminal.rows >= 40 else 12
            page_capacity = num_cols * grid_rows

            if need_full_render:
                all_entries = self._get_dir_entries(
                    current_dir, filter_pattern
                )
                page_count = max(
                    1, (len(all_entries) + page_capacity - 1) // page_capacity
                )
                page_idx = max(0, min(page_idx, page_count - 1))

                self.renderer.render_directory_workspace(
                    mode=mode,
                    current_dir=current_dir,
                    files=all_entries,
                    page_idx=page_idx,
                    page_count=page_count,
                    input_text=input_text,
                    cursor_pos=cursor_pos,
                    buf=self.buffer,
                    format_cpm=fmt_cpm,
                    geometry_str=geometry_str,
                )
                need_full_render = False
            else:
                self.renderer.render_directory_prompt(
                    mode=mode,
                    input_text=input_text,
                    cursor_pos=cursor_pos,
                    grid_rows=grid_rows,
                )

            key = self.terminal.get_key()
            if key is None:
                continue

            if key == KEY_ESC:
                return None
            elif key == KEY_ENTER:
                cleaned = input_text.strip()
                if not cleaned:
                    continue
                if any(ch in cleaned for ch in ("*", "?")):
                    filter_pattern = cleaned
                    input_text = ""
                    cursor_pos = 0
                    page_idx = 0
                    need_full_render = True
                    continue
                target = os.path.abspath(os.path.join(current_dir, cleaned))
                if os.path.isdir(target):
                    current_dir = target
                    input_text = ""
                    cursor_pos = 0
                    page_idx = 0
                    need_full_render = True
                    continue
                if mode in ("open", "insert") and not os.path.isfile(target):
                    self.modal.show_file_not_found(cleaned)
                    need_full_render = True
                    continue
                return (target, fmt_cpm)
            elif key == KEY_PGUP or key == KEY_CTRL_U:
                if page_idx > 0:
                    page_idx -= 1
                    need_full_render = True
            elif key == KEY_PGDN or key == KEY_CTRL_V:
                if (page_idx + 1) * page_capacity < len(all_entries):
                    page_idx += 1
                    need_full_render = True
            elif key == KEY_CTRL_F and mode in ("save", "save_block"):
                fmt_cpm = not fmt_cpm
                need_full_render = True
            elif key == KEY_LEFT:
                cursor_pos = max(0, cursor_pos - 1)
            elif key == KEY_RIGHT:
                cursor_pos = min(len(input_text), cursor_pos + 1)
            elif key in (KEY_HOME, KEY_CTRL_A):
                cursor_pos = 0
            elif key in (KEY_END, KEY_CTRL_E):
                cursor_pos = len(input_text)
            elif key == KEY_BACKSPACE:
                if cursor_pos > 0:
                    input_text = (
                        input_text[: cursor_pos - 1] + input_text[cursor_pos:]
                    )
                    cursor_pos -= 1
            elif key in (KEY_DELETE, KEY_CTRL_D):
                if cursor_pos < len(input_text):
                    input_text = (
                        input_text[:cursor_pos] + input_text[cursor_pos + 1 :]
                    )
            elif len(key) == 1 and 32 <= ord(key) <= 126:
                input_text = (
                    input_text[:cursor_pos] + key + input_text[cursor_pos:]
                )
                cursor_pos += 1

        return None

    def action_open_file(self):
        """Display Tier 1 Directory Browser and open selected file."""
        target = self.action_directory_browser(mode="open")
        if not target:
            return
        filename, _fmt = target
        if os.path.isfile(filename):
            self.buffer.load_file(filename)

    def action_insert_file(self):
        """Insert disk file contents into document buffer at cursor."""
        if self.buffer.block_active == 1:
            self.buffer.solidify_block()

        target = self.action_directory_browser(mode="insert")
        if not target:
            return
        filename, _fmt = target
        if not os.path.isfile(filename):
            return

        ok = self.buffer.insert_file(filename)
        if ok:
            self.modal.show_notification(
                title="Insert Complete",
                message=f"Inserted {os.path.basename(filename)}",
            )
        else:
            self.modal.show_notification(
                title="Insert Error",
                message=f"Could not read {os.path.basename(filename)}",
            )

    def action_save_file(self) -> bool:
        """Display Tier 1 Save File workspace and save document."""
        initial = (
            "" if self.buffer.filename == "(Untitled)" else self.buffer.filename
        )
        target = self.action_directory_browser(
            mode="save", initial_text=initial
        )
        if not target:
            return False
        target_name, fmt_cpm = target
        if os.path.exists(target_name) and target_name != self.buffer.filename:
            ans = self.modal.show_overwrite_dialog()
            if ans != "y":
                return False

        self.buffer.format_cpm = fmt_cpm
        ok = self.buffer.save_file(target_name, format_cpm=fmt_cpm)
        if ok:
            self.modal.show_notification(
                title="Save Complete",
                message=f"Saved to {os.path.basename(target_name)}",
            )
            return True
        else:
            self.modal.show_notification(
                title="Save Error", message=f"Could not write to {target_name}"
            )
            return False

    def action_block_save(self) -> bool:
        """Display Tier 1 Save Block workspace and save block to file."""
        if self.buffer.block_active == 0:
            return False
        if self.buffer.block_active == 1:
            self.buffer.solidify_block()

        target = self.action_directory_browser(
            mode="save_block", initial_text=""
        )
        if not target:
            return False
        target_name, fmt_cpm = target
        if os.path.exists(target_name) and target_name != self.buffer.filename:
            ans = self.modal.show_overwrite_dialog()
            if ans != "y":
                return False

        ok = self.buffer.save_block(target_name, format_cpm=fmt_cpm)
        if ok:
            self.modal.show_notification(
                title="Save Complete",
                message=f"Block saved to {os.path.basename(target_name)}",
            )
            return True
        else:
            self.modal.show_notification(
                title="Save Error", message=f"Could not write to {target_name}"
            )
            return False

    def action_block_popup(self):
        """
        Display canonical Tier 2 Block Operations modal dialog (Ctrl+K
        when block_active > 0) and dispatch the selected action.
        """
        if self.buffer.block_active == 0:
            return

        action = self.modal.show_block_operations_dialog(self.buffer)
        if action == "enter":
            self.buffer.solidify_block()
        elif action == "clear":
            self.buffer.cancel_block()
        elif action == "copy":
            self.buffer.copy_block_to_cursor()
        elif action in ("cut", "move"):
            self.buffer.move_block_to_cursor()
        elif action == "delete":
            self.buffer.delete_block()
        elif action == "save":
            self.buffer.solidify_block()
            self.action_block_save()

        self.terminal.show_cursor()

    def action_new_file(self):
        """Create new empty document (prompting if unsaved edits)."""
        if self.buffer.modified:
            ans = self.modal.show_confirm(
                title="Unsaved Modifications",
                desc="Any unsaved edits will be lost if discarded.",
                query="Save changes?",
                options_text="[Y]es      [N]o      [ESC]=Cancel",
            )
            if ans is None:
                return
            if ans == "y":
                if not self.action_save_file():
                    return
        self.buffer = DocumentBuffer(
            filename="(Untitled)", tab_width=self.config.tab_width
        )
        self.buffer.has_file = False

    def action_close_file(self, to_splash: bool = True) -> bool:
        """Close active document and return to Splash Screen workspace."""
        if self.buffer.modified:
            ans = self.modal.show_confirm(
                title="Unsaved Modifications",
                desc="Any unsaved edits will be lost if discarded.",
                query="Save changes?",
                options_text="[Y]es      [N]o      [ESC]=Cancel",
            )
            if ans is None:
                return False  # Cancelled with ESC, keep document state intact
            if ans == "y":
                if not self.action_save_file():
                    return False  # Save cancelled or failed

        self.buffer = DocumentBuffer(
            filename="(Untitled)", tab_width=self.config.tab_width
        )
        self.buffer.has_file = False

        if to_splash:
            self.action_splash_screen()
        return True

    def action_about(self):
        """Display Tier 1 About screen workspace."""
        lines = [
            "SE - Screen Editor",
            "version 1.1.0 (2026-10-09) (Python)",
            "by Dean Jenkins",
            "",
            "Google Antigravity 2.19.1 & Gemini FLASH 3.8 high",
            "",
            "Open source software under the MIT License",
            "",
            "Press any key to continue",
        ]
        geom = f"{self.terminal.cols}x{self.terminal.rows}"
        self.renderer.render_centered_workspace(
            lines, self.buffer, geometry_str=geom
        )
        self.terminal.get_key()

    def action_mem_info(self):
        """Display Tier 1 Memory Information workspace."""
        ram_lbl = (
            "Preserved (Active)"
            if self.config.ramdrive_enabled
            else "None Detected"
        )
        plugin_lbl = (
            "Operational" if self.plugin_mgr.list_plugins() else "Disabled"
        )
        lines = [
            "SE - Extended Memory Map",
            f"OS: Linux | RAM: Dynamic Heap | Plugins: {plugin_lbl}",
            "",
            "Bank  Phys   Size   System / OS Role        SE Usage",
            "----  ----   ----   ---------------------   "
            "----------------------------",
            "0     0x00   64KB   Linux OS / Python VM    Code & Runtime Buffer",
            "1     0x01   64KB   Document Buffer         Active Lines & Cache",
            "2     0x02   32KB   Plugin Subsystem        Dynamic Plugin Memory",
            "3     0x03   32KB   Clipboard Buffer        Cut/Copy Storage",
            f"4     0x04   RAM    RAM Drive Storage       {ram_lbl}",
            "",
            "Press any key to continue",
        ]
        geom = f"{self.terminal.cols}x{self.terminal.rows}"
        self.renderer.render_centered_workspace(
            lines, self.buffer, geometry_str=geom
        )
        self.terminal.get_key()

    def action_splash_screen(self):
        """
        Display canonical Tier 1 Splash screen workspace (14 lines x 50 cols).
        Supports bare hotkeys and colon-prefixed command syntax (:e, :o, etc.).
        """
        need_render = True
        while True:
            if need_render:
                screen_mode_label = (
                    f"{self.terminal.cols}x{self.terminal.rows}"
                )
                if getattr(self.config, "is_native_screen", False):
                    geom_tag = f"{screen_mode_label} (Native Terminal)"
                elif self.terminal.cols >= 120:
                    geom_tag = f"{screen_mode_label} (Wide Console)"
                else:
                    geom_tag = f"{screen_mode_label} (Classic Terminal)"

                if self.config.max_lines == "16K":
                    max_lines_str = "16,384 lines"
                elif self.config.max_lines == "32K":
                    max_lines_str = "32,768 lines"
                else:
                    max_lines_str = f"{self.config.max_lines} lines"
                lines = [
                    "SE - Screen Editor",
                    "",
                    "type   [E]  or  [Enter] to edit",
                    "type   [N]              to new file",
                    "type   [O]              to open file",
                    "type   [S]              to save file",
                    "type   [W]  or  [^W]    to close file",
                    "type   [L]  or  [^L]    to goto line",
                    "type   [A]              for about",
                    "type   [M]              for memory info",
                    "type   [P]              for plugins",
                    "type   [^P]             for context plugin menu",
                    "type   [C]              to configure",
                    "type   [1]              set 80x24",
                    "type   [2]              set 120x40",
                    "type   [Q]  or  [^Q]    to exit",
                    "",
                    f"Active Screen : [{geom_tag}]",
                    "RAM Drive (A:): [Preserved (Active)]",
                    "Plugin System : [Operational]",
                    f"Max Lines     : [{max_lines_str}]",
                ]
                geom = f"{self.terminal.cols}x{self.terminal.rows}"
                self.renderer.render_centered_workspace(
                    lines, self.buffer, geometry_str=geom
                )
                need_render = False

            k = self.terminal.get_key()
            if not k:
                continue

            ch = k.lower() if isinstance(k, str) else ""
            if ch == "e" or k == KEY_ENTER or k == "\r":
                return  # Return to editor
            elif ch == "n":
                self.action_new_file()
                return
            elif ch == "o" or k == KEY_CTRL_O:
                self.action_open_file()
                return
            elif ch == "s" or k == KEY_CTRL_S:
                self.action_save_file()
                need_render = True
            elif ch == "w" or k == KEY_CTRL_W:
                self.action_close_file(to_splash=False)
                need_render = True
            elif ch == "l" or k == KEY_CTRL_L:
                self.action_goto_line()
                return
            elif ch == "a":
                self.action_about()
                need_render = True
            elif ch == "m":
                self.action_mem_info()
                need_render = True
            elif ch == "p" or k == KEY_CTRL_P:
                self.action_plugin_palette()
                need_render = True
            elif ch == "c":
                self.action_config_screen()
                need_render = True
            elif ch in ("?", "h") or k == KEY_CTRL_K:
                self.action_help()
                need_render = True
            elif ch == "1":
                self.terminal.term_init()
                self.config.set("SCREEN", "80x24")
                self.terminal.fixed_geometry = True
                self.terminal.default_cols = 80
                self.terminal.default_rows = 24
                self.terminal.cols = 80
                self.terminal.rows = 24
                need_render = True
            elif ch == "2":
                self.terminal.term_init()
                self.config.set("SCREEN", "120x40")
                self.terminal.fixed_geometry = True
                self.terminal.default_cols = 120
                self.terminal.default_rows = 40
                self.terminal.cols = 120
                self.terminal.rows = 40
                need_render = True
            elif ch == "3":
                self.terminal.term_init()
                self.config.set("SCREEN", "NATIVE")
                self.terminal.fixed_geometry = False
                self.terminal.update_geometry()
                need_render = True
            elif ch == "q" or k == KEY_CTRL_Q:
                self.action_quit()
                return
            else:
                # Non-entry key exclusion: silently ignore Space, ESC, arrows
                continue

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
            # Child pop-up isolation protocol (Section 8.4): clear parent menu
            geom = f"{self.terminal.cols}x{self.terminal.rows}"
            self.renderer.render_editor(self.buffer, geometry_str=geom)
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
        self.terminal.hide_cursor()
        try:
            while True:
                cols = self.terminal.cols
                rows = self.terminal.rows
                cur_ram = self.config.get("RAMDRIVE", "PRESERVE").upper()
                if cur_ram == "PRESERVE":
                    ram_lbl = "Protected"
                elif cur_ram == "DISABLED":
                    ram_lbl = "Disabled"
                else:
                    ram_lbl = cur_ram.capitalize()

                geom_lbl = (
                    f"{cols}x{rows} (Native)"
                    if self.config.is_native_screen
                    else f"{cols}x{rows}"
                )

                cur_plg = self.config.get("PLUGIN", "AUTOLOAD").upper()
                plugin_lbl = (
                    "Autoload" if cur_plg != "DISABLED" else "Disabled"
                )

                cfg_origin = (
                    "Loaded from SE.CFG"
                    if os.path.exists("SE.CFG")
                    else "Defaults"
                )

                lines = [
                    "SE - Configuration Manager",
                    "",
                    f"Config Status: {cfg_origin}",
                    "",
                    f"1. Screen Geometry  : {geom_lbl}",
                    f"2. RAM Drive Mode   : {ram_lbl}",
                    f"3. Max Doc Lines    : {self.config.max_lines}",
                    f"4. Tab Width        : {self.config.tab_width}",
                    f"5. Plugin Manager   : {plugin_lbl}",
                    "",
                    "[1-5]=Toggle Option  [S]=Save Config  [ESC]=Exit",
                ]
                geom = f"{self.terminal.cols}x{self.terminal.rows}"
                self.renderer.render_centered_workspace(
                    lines, self.buffer, geometry_str=geom
                )

                k = self.terminal.get_key()
                if not k:
                    continue
                ch = k.lower() if isinstance(k, str) else ""
                if k in (KEY_ESC, KEY_ENTER, "\r", "\x1b") or ch == "q":
                    return
                elif ch == "1":
                    self.terminal.term_init()
                    cur_screen = self.config.get("SCREEN", "120X40").upper()
                    if cur_screen == "80X24":
                        self.config.set("SCREEN", "120x40")
                        self.terminal.fixed_geometry = True
                        self.terminal.default_cols = 120
                        self.terminal.default_rows = 40
                        self.terminal.cols = 120
                        self.terminal.rows = 40
                    elif cur_screen == "120X40":
                        self.config.set("SCREEN", "NATIVE")
                        self.terminal.fixed_geometry = False
                        self.terminal.update_geometry()
                    else:
                        self.config.set("SCREEN", "80x24")
                        self.terminal.fixed_geometry = True
                        self.terminal.default_cols = 80
                        self.terminal.default_rows = 24
                        self.terminal.cols = 80
                        self.terminal.rows = 24
                elif ch == "2":
                    new_ram = (
                        "DISABLED" if cur_ram != "DISABLED" else "PRESERVE"
                    )
                    self.config.set("RAMDRIVE", new_ram)
                elif ch == "3":
                    cur_cap = self.config.max_lines
                    new_cap = "32K" if cur_cap == "16K" else "16K"
                    self.config.set("MAXLINES", new_cap)
                elif ch == "4":
                    new_tab = "4" if self.config.tab_width == 8 else "8"
                    self.config.set("TAB", new_tab)
                elif ch == "5":
                    cur_plg = self.config.get("PLUGIN", "AUTOLOAD").upper()
                    new_plg = (
                        "DISABLED" if cur_plg != "DISABLED" else "AUTOLOAD"
                    )
                    self.config.set("PLUGIN", new_plg)
                elif ch == "s":
                    self.config.save_config()
                    self.modal.show_notification(
                        title="Config Saved",
                        message="Configuration saved to SE.CFG.",
                    )
        finally:
            self.terminal.show_cursor()

