"""
Tier 2 centered modal pop-up dialog engine for SE editor.
Implements framed pop-up boxes, query modals, and single-level lifecycles.
"""

import os
from typing import List, Optional, Tuple, TYPE_CHECKING
from se.terminal import (
    Terminal,
    KEY_UP,
    KEY_DOWN,
    KEY_LEFT,
    KEY_RIGHT,
    KEY_HOME,
    KEY_END,
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
    KEY_CTRL_G,
    KEY_CTRL_S,
    KEY_CTRL_X,
)

if TYPE_CHECKING:
    from se.buffer import DocumentBuffer


class ModalDialog:
    """
    Renders and manages interactive modal pop-ups strictly conforming to
    docs/UI_UX_DESIGN.md.
    """

    def __init__(self, terminal: Terminal):
        self.term = terminal

    def compute_popup_pos(self, width: int, height: int) -> Tuple[int, int]:
        """
        Calculate dynamically centered (top_row, left_col) in 1-based coords.
        """
        top_row = max(1, ((self.term.rows - height) // 2) + 1)
        left_col = max(1, ((self.term.cols - width) // 2) + 1)
        return top_row, left_col

    def draw_box(self, top: int, left: int, width: int, lines: List[str]):
        """
        Draw boxed framed pop-up window with borders.
        """
        border_top = "+" + ("-" * (width - 2)) + "+"
        border_sep = border_top
        border_bot = border_top

        self.term.hide_cursor()
        self.term.locate(top, left)
        self.term.write(border_top)

        for i, line_text in enumerate(lines):
            self.term.locate(top + 1 + i, left)
            if line_text == "---":
                self.term.write(border_sep)
            else:
                interior_w = width - 2
                padded = f"|{line_text.center(interior_w)}|"
                self.term.write(padded)

        self.term.locate(top + 1 + len(lines), left)
        self.term.write(border_bot)
        self.term.flush()

    def show_notification(self, title: str, message: str):
        """
        Display a Tier 2 status/notification pop-up.
        Dismissible by any key.
        """
        width = max(52, len(title) + 10, len(message) + 8)
        height = 7
        top, left = self.compute_popup_pos(width, height)

        lines = [
            title,
            "---",
            message,
            "",
            "Press any key to continue",
        ]
        self.draw_box(top, left, width, lines)
        self.term.get_key()
        self.term.show_cursor()

    def show_file_not_found(self, filename: str):
        """
        Display canonical Archetype A File Not Found modal alert (50x7).
        Dismissible by any key.
        """
        width = 50
        height = 7
        top, left = self.compute_popup_pos(width, height)
        base = os.path.basename(filename) or filename
        lines = [
            "File Not Found",
            "---",
            f"'{base}' was not found.",
            "Specified file not found on disk.",
            "Press any key to continue",
        ]
        self.draw_box(top, left, width, lines)
        self.term.get_key()
        self.term.show_cursor()

    def show_confirm(
        self,
        title: str,
        desc: str,
        query: str,
        options_text: str = "[Y]es      [N]o      [ESC]=Cancel",
    ) -> Optional[str]:
        """
        Display a Tier 2 query modal (e.g. Save Changes, Overwrite).
        Returns 'y'/'Y', 'n'/'N', or None on ESC.
        """
        width = 52
        height = 8
        top, left = self.compute_popup_pos(width, height)

        lines = [
            title,
            "---",
            desc,
            query,
            "",
            options_text,
        ]
        self.draw_box(top, left, width, lines)

        # Reposition blinking cursor adjacent to query
        query_row = top + 4
        interior_w = width - 2
        query_lead_spaces = (interior_w - len(query)) // 2
        cursor_c = left + 1 + query_lead_spaces + len(query) + 1
        self.term.locate(query_row, cursor_c)
        self.term.show_cursor()
        self.term.flush()

        while True:
            k = self.term.get_key()
            if k == KEY_ESC:
                return None
            if k and k.lower() in ("y", "n"):
                return k.lower()

    def show_overwrite_dialog(self) -> Optional[str]:
        """
        Display canonical Archetype B Overwrite File modal dialog (50x7).
        Returns 'y'/'Y', 'n'/'N', or None on ESC.
        """
        width = 50
        height = 7
        top, left = self.compute_popup_pos(width, height)

        query = "File already exists. Overwrite?"
        lines = [
            "Overwrite File",
            "---",
            "Existing file contents will be lost",
            query,
            "[Y]es      [N]o      [ESC]=Cancel",
        ]
        self.draw_box(top, left, width, lines)

        # Reposition blinking cursor adjacent to query prompt
        query_row = top + 4
        interior_w = width - 2
        query_lead_spaces = (interior_w - len(query)) // 2
        cursor_c = left + 1 + query_lead_spaces + len(query) + 1
        self.term.locate(query_row, cursor_c)
        self.term.show_cursor()
        self.term.flush()

        while True:
            k = self.term.get_key()
            if k == KEY_ESC:
                return None
            if k and k.lower() in ("y", "n"):
                return k.lower()

    def show_input(
        self,
        title: str,
        desc: str,
        label: str,
        initial_text: str = "",
        max_len: int = 20,
        options_text: str = "[Enter]=Confirm      [ESC]=Cancel",
    ) -> Optional[str]:
        """
        Display a Tier 2 single-line text input modal (e.g. Goto Line, Find).
        Returns entered text or None on ESC.
        """
        width = 52
        height = 8
        top, left = self.compute_popup_pos(width, height)

        buf = list(initial_text[:max_len])
        cursor_idx = len(buf)

        while True:
            # Format input line: "Label: [  text  ]"
            input_box_w = max_len + 2
            field = "".join(buf).ljust(max_len)
            query_line = f"{label} [{field}]"

            lines = [
                title,
                "---",
                desc,
                query_line,
                "",
                options_text,
            ]
            self.draw_box(top, left, width, lines)

            # Position cursor inside the input bracket
            query_row = top + 4
            interior_w = width - 2
            lead_spaces = (interior_w - len(query_line)) // 2
            box_start_c = left + 1 + lead_spaces + len(label) + 2
            self.term.locate(query_row, box_start_c + cursor_idx)
            self.term.show_cursor()
            self.term.flush()

            k = self.term.get_key()
            if k == KEY_ESC:
                return None
            if k == KEY_ENTER:
                return "".join(buf)
            if k == KEY_BACKSPACE:
                if cursor_idx > 0:
                    cursor_idx -= 1
                    buf.pop(cursor_idx)
            elif k in (KEY_DELETE, KEY_CTRL_D, KEY_CTRL_G):
                if cursor_idx < len(buf):
                    buf.pop(cursor_idx)
            elif k == KEY_LEFT:
                if cursor_idx > 0:
                    cursor_idx -= 1
            elif k == KEY_RIGHT:
                if cursor_idx < len(buf):
                    cursor_idx += 1
            elif k in (KEY_HOME, KEY_CTRL_A):
                cursor_idx = 0
            elif k in (KEY_END, KEY_CTRL_E):
                cursor_idx = len(buf)
            elif k and len(k) == 1 and 32 <= ord(k) <= 126:
                if len(buf) < max_len:
                    buf.insert(cursor_idx, k)
                    cursor_idx += 1

    def show_find_dialog(
        self,
        initial_text: str = "",
        initial_case_sensitive: bool = True,
        max_len: int = 20,
    ) -> Tuple[Optional[str], bool]:
        """
        Display Archetype C Find Text modal with dynamic [Tab] case toggle.
        Returns (search_query, is_case_sensitive) or (None, is_case_sensitive).
        """
        width = 50
        height = 7
        top, left = self.compute_popup_pos(width, height)

        buf = list(initial_text[:max_len])
        cursor_idx = len(buf)
        case_sensitive = initial_case_sensitive

        while True:
            case_label = (
                "Case Sensitive  " if case_sensitive else "Case Insensitive"
            )
            desc = f"Search Pattern: [{case_label}]"
            field = "".join(buf).ljust(max_len)
            query_line = f"Find: [{field}]"
            options_text = "[Enter]=Find   [Tab]=Toggle Case   [ESC]=Cancel"

            lines = [
                "Find Text",
                "---",
                desc,
                query_line,
                options_text,
            ]
            self.draw_box(top, left, width, lines)

            # Position cursor inside the input bracket
            query_row = top + 4
            interior_w = width - 2
            lead_spaces = (interior_w - len(query_line)) // 2
            box_start_c = left + 1 + lead_spaces + len("Find:") + 2
            self.term.locate(query_row, box_start_c + cursor_idx)
            self.term.show_cursor()
            self.term.flush()

            k = self.term.get_key()
            if k == KEY_ESC:
                return None, case_sensitive
            if k == KEY_ENTER:
                return "".join(buf), case_sensitive
            if k == KEY_TAB:
                case_sensitive = not case_sensitive
                continue
            if k == KEY_BACKSPACE:
                if cursor_idx > 0:
                    cursor_idx -= 1
                    buf.pop(cursor_idx)
            elif k in (KEY_DELETE, KEY_CTRL_D, KEY_CTRL_G):
                if cursor_idx < len(buf):
                    buf.pop(cursor_idx)
            elif k == KEY_LEFT:
                if cursor_idx > 0:
                    cursor_idx -= 1
            elif k == KEY_RIGHT:
                if cursor_idx < len(buf):
                    cursor_idx += 1
            elif k in (KEY_HOME, KEY_CTRL_A):
                cursor_idx = 0
            elif k in (KEY_END, KEY_CTRL_E):
                cursor_idx = len(buf)
            elif k and len(k) == 1 and 32 <= ord(k) <= 126:
                if len(buf) < max_len:
                    buf.insert(cursor_idx, k)
                    cursor_idx += 1

    def show_menu(
        self,
        title: str,
        desc: str,
        items: List[Tuple[str, str]],
        options_text: str = "[Up/Down]=Select  [Enter]=Run  [ESC]=Cancel",
    ) -> Optional[int]:
        """
        Display a Tier 2 selection menu pop-up (e.g. Plugin Palette).
        Returns selected 0-based index or None on ESC.
        """
        if not items:
            return None

        max_item_len = max(len(f"{name} - {d}") for name, d in items)
        width = min(self.term.cols - 4, max(52, max_item_len + 8))
        height = len(items) + 6
        top, left = self.compute_popup_pos(width, height)
        selected_idx = 0

        while True:
            lines = [title, "---", desc]
            interior_w = width - 2
            for i, (name, d) in enumerate(items):
                prefix = "> " if i == selected_idx else "  "
                entry = f"{prefix}{i + 1}. {name.ljust(8)} - {d}"
                if len(entry) > interior_w - 2:
                    entry = entry[: interior_w - 5] + "..."
                padded_entry = f"  {entry}".ljust(interior_w)
                lines.append(padded_entry)
            lines.append("")
            lines.append(options_text)

            self.draw_box(top, left, width, lines)

            k = self.term.get_key()
            if k == KEY_ESC:
                return None
            if k == KEY_ENTER:
                return selected_idx
            if k == KEY_UP:
                selected_idx = (selected_idx - 1) % len(items)
            elif k == KEY_DOWN:
                selected_idx = (selected_idx + 1) % len(items)
            elif k and k.isdigit():
                num = int(k) - 1
                if 0 <= num < len(items):
                    return num

    def show_block_operations_dialog(
        self, buf: "DocumentBuffer"
    ) -> Optional[str]:
        """
        Display canonical Tier 2 Block Operations modal dialog (50x7).
        Returns one of: 'enter', 'clear', 'copy', 'cut', 'delete', 'save',
        or None on ESC.
        """
        width = 50
        height = 7
        top, left = self.compute_popup_pos(width, height)

        r1, c1, r2, c2 = buf.get_normalized_block()
        if r1 == r2:
            chars = c2 - c1
            unit = "char" if chars == 1 else "chars"
            metric = f"{chars} {unit}"
        else:
            lines_spanned = r2 - r1 + (1 if c2 > 0 else 0)
            unit = "line" if lines_spanned == 1 else "lines"
            metric = f"{lines_spanned} {unit}"

        prefix = "Marked Block: " if buf.block_active == 2 else "Selection: "
        msg = f"{prefix}{metric}"

        if buf.block_active == 2:
            line5 = "      [^C]=Copy Block      [^X]=Move Block      "
        else:
            line5 = "  [Enter]=Lock/Set    [^C]=Copy    [^X]=Move    "

        line6 = "  [^D]=Del  [^S]=Save  [^B]=Clear  [ESC]=Close  "

        lines = [
            "Block Operations",
            "---",
            msg,
            line5,
            line6,
        ]
        self.draw_box(top, left, width, lines)

        while True:
            k = self.term.get_key()
            if k is None or k == KEY_ESC:
                self.term.show_cursor()
                return None
            if k == KEY_ENTER:
                self.term.show_cursor()
                return "enter"
            if k in (KEY_CTRL_B, "b", "B"):
                self.term.show_cursor()
                return "clear"
            if k in (KEY_CTRL_C, "c", "C"):
                self.term.show_cursor()
                return "copy"
            if k in (KEY_CTRL_X, "x", "X"):
                self.term.show_cursor()
                return "cut"
            if k in (KEY_CTRL_D, "d", "D", KEY_DELETE):
                self.term.show_cursor()
                return "delete"
            if k in (KEY_CTRL_S, "s", "S"):
                self.term.show_cursor()
                return "save"

