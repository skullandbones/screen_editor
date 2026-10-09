"""
UI rendering engine, universal status bar, and surface taxonomy for SE editor.
Enforces column 0 tilde discipline, viewport clipping, and screen centering.
"""

from typing import List, Optional, Tuple
from se.buffer import DocumentBuffer
from se.terminal import Terminal


def compute_centering(
    screen_cols: int, screen_rows: int, content_w: int, content_h: int
) -> Tuple[int, int]:
    """
    Calculate top row and left column for centered content blocks.
    Available rows exclude the bottom status bar row (HOST_ROWS).
    """
    avail_rows = max(1, screen_rows - 1)
    top_row = max(1, (avail_rows - content_h) // 2 + 1)
    left_col = max(2, (screen_cols - content_w) // 2 + 1)
    return top_row, left_col


class UIRenderer:
    """
    Coordinates terminal rendering for editor, workspaces, and status bar.
    """

    def __init__(self, terminal: Terminal):
        self.term = terminal

    def render_status_bar(
        self,
        buf: DocumentBuffer,
        geometry_str: str = "80x24",
        status_msg: Optional[str] = None,
    ):
        """
        Render universal status bar on bottom row (HOST_ROWS).
        Guaranteed to appear on all screens without a column 0 tilde.
        """
        cols = self.term.cols
        rows = self.term.rows

        # Filename section (padded to 16 chars)
        mod_char = "*" if buf.modified else " "
        raw_name = buf.filename + mod_char
        name_field = f"| {raw_name:<14} |"

        # Geometry and format fields
        geom_field = f" {geometry_str} |"
        fmt_str = "CPM  " if buf.format_cpm else "Linux"
        fmt_field = f" {fmt_str} |"

        # Field 4 (Help Hint / Context, 18 chars): persistent help context
        # Status events prohibited on status bar per Section 4.4
        help_field = " ^K: Editor keys |"

        # Cursor and pan position field
        cur_line = buf.cursor_row + 1
        tot_lines = buf.total_lines
        cur_col = buf.cursor_col
        pan_str = f" [Pan +{buf.pan_col}]" if buf.pan_col > 0 else ""

        # Block selection indicator
        blk_str = ""
        if buf.block_active == 1:
            blk_str = " [SEL]"
        elif buf.block_active == 2:
            blk_str = " [BLK LOCK]"

        pos_field = (
            f" Line {cur_line:>4}/{tot_lines:<4} "
            f"Col {cur_col:<3}{pan_str}{blk_str} |"
        )

        # Assemble full status bar content
        core = (
            f"{name_field}{geom_field}{fmt_field}{help_field}{pos_field}"
        )

        # Pad or center across terminal width
        if len(core) < cols:
            padding = cols - len(core)
            left_pad = padding // 2
            right_pad = padding - left_pad
            status_text = (" " * left_pad) + core + (" " * right_pad)
        else:
            status_text = core[:cols]

        self.term.locate(rows, 1)
        self.term.inverse_on()
        self.term.write(status_text)
        self.term.inverse_off()
        self.term.flush()

    def render_editor(
        self,
        buf: DocumentBuffer,
        geometry_str: str = "80x24",
        status_msg: Optional[str] = None,
    ):
        """
        Render active document editor workspace with column 0 tildes.
        """
        cols = self.term.cols
        rows = self.term.rows
        body_rows = rows - 1  # Exclude status bar row

        # Adjust vertical scroll window
        if buf.cursor_row < buf.top_row:
            buf.top_row = buf.cursor_row
        elif buf.cursor_row >= buf.top_row + body_rows:
            buf.top_row = buf.cursor_row - body_rows + 1

        buf.update_pan(cols)

        # Render document lines and unallocated tilde rows
        for screen_r in range(1, body_rows + 1):
            doc_r = buf.top_row + (screen_r - 1)
            self.term.locate(screen_r, 1)

            if doc_r < buf.total_lines:
                # Render document line sliced by horizontal pan
                line_text = buf.get_line(doc_r)
                if buf.pan_col < len(line_text):
                    visible = line_text[buf.pan_col : buf.pan_col + cols]
                else:
                    visible = ""

                # Handle block selection highlighting if active
                if buf.block_active > 0:
                    r1, c1, r2, c2 = buf.get_normalized_block()
                    if r1 <= doc_r <= r2:
                        self._render_highlighted_line(
                            visible, doc_r, buf.pan_col, r1, c1, r2, c2
                        )
                    else:
                        self.term.write(visible)
                else:
                    self.term.write(visible)

                self.term.clear_eol()
            else:
                # Column 0 tilde discipline for unallocated rows
                self.term.write("~")
                self.term.clear_eol()

        # Render status bar on row HOST_ROWS
        self.render_status_bar(
            buf, geometry_str=geometry_str, status_msg=status_msg
        )

        # Reposition terminal cursor at active document character
        sc_r = (buf.cursor_row - buf.top_row) + 1
        sc_c = (buf.cursor_col - buf.pan_col) + 1
        self.term.locate(sc_r, sc_c)
        self.term.flush()

    def _render_highlighted_line(
        self,
        visible_text: str,
        doc_r: int,
        pan_col: int,
        r1: int,
        c1: int,
        r2: int,
        c2: int,
    ):
        """Render line with inverse video applied to selected block range."""
        start_c = c1 if doc_r == r1 else 0
        end_c = c2 if doc_r == r2 else 9999

        # Adjust for horizontal pan
        start_vis = max(0, start_c - pan_col)
        end_vis = max(0, min(len(visible_text), end_c - pan_col))

        if start_vis >= len(visible_text):
            self.term.write(visible_text)
            return

        prefix = visible_text[:start_vis]
        selected = visible_text[start_vis:end_vis]
        suffix = visible_text[end_vis:]

        self.term.write(prefix)
        self.term.inverse_on()
        self.term.write(selected)
        self.term.inverse_off()
        self.term.write(suffix)

    def render_centered_workspace(
        self,
        lines: List[str],
        buf: DocumentBuffer,
        geometry_str: str = "80x24",
    ):
        """
        Render a full-screen centered workspace (Splash, Open, Save, Help).
        Applies column 0 tilde discipline to all rows above status bar.
        """
        cols = self.term.cols
        rows = self.term.rows
        body_rows = rows - 1

        content_h = len(lines)
        content_w = max((len(ln) for ln in lines), default=0)
        top_row, left_col = compute_centering(
            cols, rows, content_w, content_h
        )

        prompt_row = None
        prompt_col = None

        for screen_r in range(1, body_rows + 1):
            self.term.locate(screen_r, 1)
            # Column 0 tilde on all workspace rows
            self.term.write("~")

            # Check if this row is within content block
            content_idx = screen_r - top_row
            if 0 <= content_idx < content_h:
                line_str = lines[content_idx]
                self.term.locate(screen_r, left_col)
                self.term.write(line_str)
                if any(
                    p in line_str for p in ("Enter choice:", "Enter option:")
                ):
                    prompt_row = screen_r
                    prompt_col = left_col + len(line_str)

            self.term.clear_eol()

        # Bottom row status bar
        self.render_status_bar(buf, geometry_str=geometry_str)

        # Reposition cursor adjacent to prompt if present (Bug 2.7.9)
        if prompt_row is not None and prompt_col is not None:
            self.term.locate(prompt_row, prompt_col)

        self.term.flush()
