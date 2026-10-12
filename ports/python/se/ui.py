"""
UI rendering engine, universal status bar, and surface taxonomy for SE editor.
Enforces column 0 tilde discipline, viewport clipping, and screen centering.
"""

import os
from typing import List, Optional, Tuple
from se.buffer import (
    DocumentBuffer,
    calc_visual_col,
    expand_tabs_visual,
)
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

        # Geometry and format fields (8 chars each)
        geom_field = f" {geometry_str:>6} |"
        fmt_str = "CP/M " if buf.format_cpm else "Linux"
        fmt_field = f" {fmt_str} |"

        # Field 4 (Help Hint / Context / Block Selection, 18 chars)
        if buf.block_active > 0:
            r1, c1, r2, c2 = buf.get_normalized_block()
            prefix = "Sel: " if buf.block_active == 1 else "Block: "
            if r1 == r2:
                count = max(0, c2 - c1)
                unit = "char" if count == 1 else "chars"
            else:
                count = (r2 - r1) + 1
                unit = "line" if count == 1 else "lines"
            metric = f"{prefix}{count} {unit}"
            help_field = f" {metric[:14]:<15} |"
        else:
            help_field = " ^K: Editor keys |"

        # Cursor and pan position field
        cur_line = buf.cursor_row + 1
        tot_lines = buf.total_lines
        cur_col = buf.get_visual_col()
        pan_str = f" [Pan +{buf.pan_col}]" if buf.pan_col > 0 else ""

        pos_field = (
            f" Line {cur_line:>4}/{tot_lines:<4} "
            f"Col {cur_col:<3}{pan_str} |"
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
        tab_width: Optional[int] = None,
    ):
        """
        Render active document editor workspace with column 0 tildes.
        """
        cols = self.term.cols
        rows = self.term.rows
        body_rows = rows - 1  # Exclude status bar row
        tab_w = tab_width if tab_width is not None else buf.tab_width

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
                # Render line sliced by horizontal pan in visual space
                raw_line = buf.get_line(doc_r)
                vis_line = expand_tabs_visual(raw_line, tab_w)
                if buf.pan_col < len(vis_line):
                    visible = vis_line[buf.pan_col : buf.pan_col + cols]
                else:
                    visible = ""

                # Handle block selection highlighting if active
                if buf.block_active > 0:
                    r1, c1, r2, c2 = buf.get_normalized_block()
                    if r1 <= doc_r <= r2:
                        self._render_highlighted_line(
                            visible,
                            raw_line,
                            doc_r,
                            buf.pan_col,
                            r1,
                            c1,
                            r2,
                            c2,
                            tab_w,
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
        vis_c = calc_visual_col(buf.current_line, buf.cursor_col, tab_w)
        sc_c = (vis_c - buf.pan_col) + 1
        sc_r = max(1, min(body_rows, sc_r))
        sc_c = max(1, min(cols, sc_c))
        self.term.locate(sc_r, sc_c)
        self.term.flush()

    def _render_highlighted_line(
        self,
        visible_text: str,
        raw_line: str,
        doc_r: int,
        pan_col: int,
        r1: int,
        c1: int,
        r2: int,
        c2: int,
        tab_w: int,
    ):
        """Render line with inverse video applied to selected block range."""
        start_c = c1 if doc_r == r1 else 0
        end_c = c2 if doc_r == r2 else len(raw_line)

        # Map buffer byte offsets to document visual columns
        start_vis_col = calc_visual_col(raw_line, start_c, tab_w)
        end_vis_col = calc_visual_col(raw_line, end_c, tab_w)

        # Adjust for horizontal pan
        start_vis = max(0, start_vis_col - pan_col)
        end_vis = max(0, min(len(visible_text), end_vis_col - pan_col))

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

    def render_directory_workspace(
        self,
        mode: str,
        current_dir: str,
        files: List[str],
        page_idx: int,
        page_count: int,
        input_text: str,
        cursor_pos: int,
        buf: DocumentBuffer,
        format_cpm: bool = True,
        geometry_str: str = "80x24",
    ):
        """
        Render full-screen Tier 1 Directory Browser workspace.
        Supports Open, Save, Insert, and Block Save modes.
        """
        cols = self.term.cols
        rows = self.term.rows
        body_rows = rows - 1

        num_cols = 7 if cols >= 120 else 5
        col_width = 16 if cols >= 120 else 15
        grid_rows = 28 if rows >= 40 else 12
        rule_width = min(cols - 2, 108 if cols >= 120 else 68)
        page_capacity = num_cols * grid_rows

        mode_titles = {
            "open": "OPEN FILE",
            "save": "SAVE FILE",
            "insert": "INSERT FILE",
            "save_block": "SAVE BLOCK",
        }
        title_mode = mode_titles.get(mode, "DIRECTORY")
        dir_label = os.path.basename(current_dir) or current_dir
        title_str = f"{title_mode} (DIRECTORY - {dir_label}/)"
        if len(title_str) > rule_width:
            title_str = title_str[: rule_width - 4] + "...)"

        hr_eq = "=" * rule_width
        hr_dash = "-" * rule_width
        title_centered = title_str.center(rule_width)

        start_idx = page_idx * page_capacity
        page_files = files[start_idx : start_idx + page_capacity]

        grid_lines = []
        for r in range(grid_rows):
            r_files = page_files[r * num_cols : (r + 1) * num_cols]
            if r_files:
                line_items = [
                    f[: col_width - 1].ljust(col_width) for f in r_files
                ]
                grid_lines.append("  " + "".join(line_items).rstrip())
            elif r == 0 and not files:
                grid_lines.append("  [No files found on current drive]")
            else:
                grid_lines.append("")

        if mode in ("save", "save_block"):
            fmt_str = "CP/M" if format_cpm else "Linux"
            if page_count > 1:
                info_line = (
                    f"  [Page {page_idx + 1}/{page_count}]"
                    f"  <PgUp>/<PgDn>=Page   "
                    f"Format: [{fmt_str}]   [^F]=Toggle Format"
                )
            else:
                info_line = f"  Format: [{fmt_str}]   [^F]=Toggle Format"
        else:
            if page_count > 1:
                info_line = (
                    f"  [Page {page_idx + 1}/{page_count}]"
                    f"  <PgUp>/<PgDn>=Page"
                )
            else:
                info_line = ""

        verb_map = {
            "open": "open",
            "insert": "insert",
            "save": "save",
            "save_block": "save",
        }
        verb = verb_map.get(mode, "open")
        prompt_prefix = f"  Enter filename to {verb}: ["
        box_width = min(30, max(12, cols - len(prompt_prefix) - 6))
        offset = max(0, cursor_pos - box_width + 1)
        visible_text = input_text[offset : offset + box_width].ljust(box_width)
        prompt_line = f"{prompt_prefix} {visible_text} ]"

        esc_line = (
            "  [ESC]=Cancel  [d:][u:][pattern] to list (e.g. B:, C1:, *.TXT)"
        )

        content = (
            [hr_eq, title_centered, hr_eq]
            + grid_lines
            + [info_line, hr_dash, esc_line, prompt_line]
        )

        content_h = len(content)
        top_row = max(1, (body_rows - content_h) // 2 + 1)
        prompt_screen_row = top_row + content_h - 1
        cursor_offset = cursor_pos - offset
        prompt_cursor_col = len(prompt_prefix) + cursor_offset + 3

        for screen_r in range(1, body_rows + 1):
            self.term.locate(screen_r, 1)
            self.term.write("~")
            content_idx = screen_r - top_row
            if 0 <= content_idx < content_h:
                ln = content[content_idx]
                if ln:
                    self.term.write(ln)
            self.term.clear_eol()

        self.render_status_bar(buf, geometry_str=geometry_str)
        self.term.locate(prompt_screen_row, prompt_cursor_col)
        self.term.flush()

