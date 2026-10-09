"""
Tier 2 centered modal pop-up dialog engine for SE editor.
Implements framed pop-up boxes, query modals, and single-level lifecycles.
"""

from typing import List, Optional, Tuple
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
    KEY_CTRL_D,
    KEY_CTRL_E,
    KEY_CTRL_G,
    KEY_CTRL_S,
)


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
        width = max(50, len(title) + 10, len(message) + 8)
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
        width = 50
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
        width = 50
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
            elif k in (KEY_DELETE, KEY_CTRL_G):
                if cursor_idx < len(buf):
                    buf.pop(cursor_idx)
            elif k in (KEY_LEFT, KEY_CTRL_S):
                if cursor_idx > 0:
                    cursor_idx -= 1
            elif k in (KEY_RIGHT, KEY_CTRL_D):
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

