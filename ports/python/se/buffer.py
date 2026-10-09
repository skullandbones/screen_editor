"""
Document buffer, line storage, and text editing engine for SE editor.
Enforces 120-column line limits, block selection, and file streaming.
"""

import os
from typing import List, Optional, Tuple

MAX_LINE_LENGTH = 120


def calc_visual_col(line: str, cur_col: int, tab_width: int = 4) -> int:
    """
    Map buffer byte offset cur_col to 0-indexed document visual column.
    Expands tab characters (0x09) to tab stops according to tab_width.
    """
    vis_col = 0
    limit = max(0, min(cur_col, len(line)))
    for i in range(limit):
        if line[i] == "\t":
            vis_col += tab_width - (vis_col % tab_width)
        else:
            vis_col += 1
    return min(vis_col, MAX_LINE_LENGTH - 1)


def expand_tabs_visual(line: str, tab_width: int = 4) -> str:
    """
    Expand tab characters in line into visual space for terminal display.
    """
    result = []
    vis_col = 0
    for ch in line:
        if ch == "\t":
            spaces = tab_width - (vis_col % tab_width)
            result.append(" " * spaces)
            vis_col += spaces
        else:
            result.append(ch)
            vis_col += 1
    return "".join(result)



class DocumentBuffer:
    """
    Manages document lines, cursor positioning, and block selections.
    """

    def __init__(
        self, filename: Optional[str] = None, tab_width: int = 4
    ):
        self.filename: str = filename if filename else "(Untitled)"
        self.has_file: bool = bool(filename)
        self.lines: List[str] = [""]
        self.cursor_row: int = 0
        self.cursor_col: int = 0
        self.target_col: int = 0
        self.top_row: int = 0
        self.pan_col: int = 0
        self.tab_width: int = tab_width
        self.modified: bool = False
        self.format_cpm: bool = True  # True = CP/M CRLF, False = Linux LF
        self.clipboard: str = ""

        # Block selection state: 0 = none, 1 = dynamic, 2 = solidified
        self.block_active: int = 0
        self.block_start_row: int = 0
        self.block_start_col: int = 0
        self.block_end_row: int = 0
        self.block_end_col: int = 0

    @property
    def total_lines(self) -> int:
        """Return total number of lines in the document."""
        return len(self.lines)

    @property
    def current_line(self) -> str:
        """Return text of line currently under the cursor."""
        if 0 <= self.cursor_row < len(self.lines):
            return self.lines[self.cursor_row]
        return ""

    def get_line(self, row: int) -> str:
        """Get text of line at 0-based row index."""
        if 0 <= row < len(self.lines):
            return self.lines[row]
        return ""

    def set_line(self, row: int, text: str):
        """Set text of line at 0-based row index."""
        if 0 <= row < len(self.lines):
            self.lines[row] = text[:MAX_LINE_LENGTH]
            self.modified = True

    def get_visual_col(self, col: Optional[int] = None) -> int:
        """Return visual column for cursor_col or specified col."""
        c = self.cursor_col if col is None else col
        return calc_visual_col(self.current_line, c, self.tab_width)

    def update_pan(self, view_cols: int):
        """
        Calculate horizontal viewport pan offset [Pan +40] based on cursor.
        """
        if view_cols >= MAX_LINE_LENGTH:
            self.pan_col = 0
            return

        if self.cursor_col >= view_cols:
            self.pan_col = 40 if self.cursor_col < view_cols + 40 else 80
        elif self.cursor_col < 40:
            self.pan_col = 0
        elif self.cursor_col < 80 and self.pan_col == 80:
            self.pan_col = 40

    def insert_char(self, ch: str) -> bool:
        """
        Insert a printable character at cursor position.
        Enforces 120-character maximum line capacity limit.
        """
        line = self.current_line
        if len(line) >= MAX_LINE_LENGTH:
            return False

        col = min(len(line), self.cursor_col)
        new_line = line[:col] + ch + line[col:]
        self.lines[self.cursor_row] = new_line
        self.cursor_col = col + 1
        self.target_col = self.get_visual_col()
        self.modified = True
        return True

    def split_line(self) -> bool:
        """
        Split current line at cursor position (Enter key).
        """
        line = self.current_line
        col = min(len(line), self.cursor_col)
        left = line[:col]
        right = line[col:]

        self.lines[self.cursor_row] = left
        self.lines.insert(self.cursor_row + 1, right)
        self.cursor_row += 1
        self.cursor_col = 0
        self.target_col = 0
        self.modified = True
        return True

    def delete_char(self) -> bool:
        """
        Delete character under cursor (Delete key).
        If at end of line, joins current line with next line if within limits.
        """
        line = self.current_line
        if self.cursor_col < len(line):
            self.lines[self.cursor_row] = (
                line[: self.cursor_col] + line[self.cursor_col + 1 :]
            )
            self.modified = True
            return True

        # At end of line: join with next line
        if self.cursor_row < len(self.lines) - 1:
            next_line = self.lines[self.cursor_row + 1]
            if len(line) + len(next_line) <= MAX_LINE_LENGTH:
                self.lines[self.cursor_row] = line + next_line
                self.lines.pop(self.cursor_row + 1)
                self.modified = True
                return True
        return False

    def backspace(self) -> bool:
        """
        Delete character preceding cursor (Backspace key).
        If at column 0, joins current line with previous line.
        """
        if self.cursor_col > 0:
            line = self.current_line
            col = min(len(line), self.cursor_col)
            self.lines[self.cursor_row] = line[: col - 1] + line[col:]
            self.cursor_col = col - 1
            self.target_col = self.get_visual_col()
            self.modified = True
            return True

        # At column 0: join with previous line
        if self.cursor_row > 0:
            prev_line = self.lines[self.cursor_row - 1]
            cur_line = self.current_line
            if len(prev_line) + len(cur_line) <= MAX_LINE_LENGTH:
                join_col = len(prev_line)
                self.lines[self.cursor_row - 1] = prev_line + cur_line
                self.lines.pop(self.cursor_row)
                self.cursor_row -= 1
                self.cursor_col = join_col
                self.target_col = self.get_visual_col()
                self.modified = True
                return True
        return False

    def move_left(self):
        """Move cursor left one column or wrap to end of previous line."""
        if self.cursor_col > 0:
            self.cursor_col -= 1
        elif self.cursor_row > 0:
            self.cursor_row -= 1
            self.cursor_col = len(self.lines[self.cursor_row])
        self.target_col = self.get_visual_col()

    def move_right(self):
        """Move cursor right one column or wrap to start of next line."""
        line_len = len(self.current_line)
        if self.cursor_col < line_len:
            self.cursor_col += 1
        elif self.cursor_row < len(self.lines) - 1:
            self.cursor_row += 1
            self.cursor_col = 0
        self.target_col = self.get_visual_col()

    def move_up(self):
        """Move cursor up one line, preserving target column."""
        if self.cursor_row > 0:
            self.cursor_row -= 1
            self.cursor_col = min(self.target_col, len(self.current_line))

    def move_down(self):
        """Move cursor down one line, preserving target column."""
        if self.cursor_row < len(self.lines) - 1:
            self.cursor_row += 1
            self.cursor_col = min(self.target_col, len(self.current_line))

    def move_home(self):
        """Move cursor to beginning of current line."""
        self.cursor_col = 0
        self.target_col = 0

    def move_end(self):
        """Move cursor to end of current line."""
        self.cursor_col = len(self.current_line)
        self.target_col = self.get_visual_col()

    def move_top(self):
        """Jump to top of document (Line 1, Col 0)."""
        self.cursor_row = 0
        self.cursor_col = 0
        self.target_col = 0
        self.top_row = 0

    def move_bottom(self):
        """Jump to bottom of document (Last Line, Col 0)."""
        self.cursor_row = max(0, len(self.lines) - 1)
        self.cursor_col = 0
        self.target_col = 0

    def page_up(self, page_size: int):
        """Navigate up by page_size lines."""
        self.cursor_row = max(0, self.cursor_row - page_size)
        self.cursor_col = min(self.target_col, len(self.current_line))

    def page_down(self, page_size: int):
        """Navigate down by page_size lines."""
        self.cursor_row = min(len(self.lines) - 1, self.cursor_row + page_size)
        self.cursor_col = min(self.target_col, len(self.current_line))

    def toggle_block(self):
        """Toggle block selection state (Ctrl+B)."""
        if self.block_active == 0:
            self.block_active = 1
            self.block_start_row = self.cursor_row
            self.block_start_col = self.cursor_col
            self.block_end_row = self.cursor_row
            self.block_end_col = self.cursor_col
        else:
            self.block_active = 0

    def solidify_block(self):
        """Solidify dynamic block selection to locked bounds."""
        if self.block_active == 1:
            self.block_end_row = self.cursor_row
            self.block_end_col = self.cursor_col
            self.block_active = 2

    def get_normalized_block(self) -> Tuple[int, int, int, int]:
        """
        Return normalized (start_row, start_col, end_row, end_col)
        where start <= end. Dynamic blocks follow the active cursor.
        """
        r1, c1 = self.block_start_row, self.block_start_col
        if self.block_active == 1:
            r2, c2 = self.cursor_row, self.cursor_col
        else:
            r2, c2 = self.block_end_row, self.block_end_col
        if (r1, c1) > (r2, c2):
            return r2, c2, r1, c1
        return r1, c1, r2, c2

    def copy_block(self) -> str:
        """Copy selected block text into clipboard buffer."""
        if self.block_active == 0:
            return ""
        if self.block_active == 1:
            self.solidify_block()
        r1, c1, r2, c2 = self.get_normalized_block()
        if r1 == r2:
            text = self.lines[r1][c1:c2]
        else:
            parts = [self.lines[r1][c1:]]
            for r in range(r1 + 1, r2):
                parts.append(self.lines[r])
            parts.append(self.lines[r2][:c2])
            text = "\n".join(parts)
        self.clipboard = text
        return text

    def cut_block(self) -> str:
        """Cut selected block text, deleting it from document."""
        if self.block_active == 0:
            return ""
        if self.block_active == 1:
            self.solidify_block()
        text = self.copy_block()
        r1, c1, r2, c2 = self.get_normalized_block()
        if r1 == r2:
            line = self.lines[r1]
            self.lines[r1] = line[:c1] + line[c2:]
        else:
            first = self.lines[r1][:c1]
            last = self.lines[r2][c2:]
            combined = first + last
            del self.lines[r1 + 1 : r2 + 1]
            self.lines[r1] = combined[:MAX_LINE_LENGTH]

        self.cursor_row = r1
        self.cursor_col = c1
        self.target_col = c1
        self.block_active = 0
        self.modified = True
        return text

    def paste_block(self) -> bool:
        """Paste clipboard text at cursor position."""
        if not self.clipboard:
            return False
        parts = self.clipboard.split("\n")
        if len(parts) == 1:
            line = self.current_line
            col = min(len(line), self.cursor_col)
            rem = MAX_LINE_LENGTH - len(line)
            to_insert = parts[0][:rem]
            self.lines[self.cursor_row] = (
                line[:col] + to_insert + line[col:]
            )[:MAX_LINE_LENGTH]
            self.cursor_col = col + len(to_insert)
            self.target_col = self.cursor_col
        else:
            line = self.current_line
            col = min(len(line), self.cursor_col)
            prefix = line[:col]
            suffix = line[col:]
            self.lines[self.cursor_row] = (prefix + parts[0])[:MAX_LINE_LENGTH]
            for i in range(1, len(parts) - 1):
                self.lines.insert(
                    self.cursor_row + i, parts[i][:MAX_LINE_LENGTH]
                )
            last_idx = self.cursor_row + len(parts) - 1
            self.lines.insert(
                last_idx, (parts[-1] + suffix)[:MAX_LINE_LENGTH]
            )
            self.cursor_row = last_idx
            self.cursor_col = len(parts[-1])
            self.target_col = self.cursor_col

        self.modified = True
        return True

    def load_file(self, path: str) -> bool:
        """
        Load document from filesystem, auto-detecting CRLF vs LF format.
        """
        if not os.path.isfile(path):
            return False
        try:
            with open(path, "rb") as f:
                content = f.read()

            # Strip EOF marker (Ctrl+Z / 0x1A) common in CP/M text files
            content = content.split(b"\x1a")[0]

            # Detect line format
            if b"\r\n" in content:
                self.format_cpm = True
                lines = content.split(b"\r\n")
            else:
                self.format_cpm = False
                lines = content.split(b"\n")

            # Remove trailing empty item from final newline
            if lines and lines[-1] == b"":
                lines.pop()

            self.lines = [
                ln.decode("ascii", errors="replace")[:MAX_LINE_LENGTH]
                for ln in lines
            ]
            if not self.lines:
                self.lines = [""]

            self.filename = os.path.basename(path)
            self.has_file = True
            self.cursor_row = 0
            self.cursor_col = 0
            self.target_col = 0
            self.top_row = 0
            self.pan_col = 0
            self.modified = False
            self.block_active = 0
            return True
        except OSError:
            return False

    def save_file(self, path: str, format_cpm: Optional[bool] = None) -> bool:
        """
        Save document to filesystem using requested or detected line format.
        """
        if format_cpm is None:
            format_cpm = self.format_cpm

        sep = b"\r\n" if format_cpm else b"\n"
        try:
            with open(path, "wb") as f:
                for line in self.lines:
                    f.write(line.encode("ascii", errors="replace") + sep)
                if format_cpm:
                    f.write(b"\x1a")  # CP/M EOF marker

            self.filename = os.path.basename(path)
            self.has_file = True
            self.format_cpm = format_cpm
            self.modified = False
            return True
        except OSError:
            return False
