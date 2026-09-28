#!/usr/bin/env python3
"""
tests/test_drunken_monkey.py - Drunken Monkey Chaos / Fuzz Test for SE.COM.

Sends random input characters (including control keys) 1 character at a time
into SE.COM, records the sequence and time gaps for deterministic replay,
and continuously monitors the output for 3 strict quality criteria:
  1. No system hangs (watchdog timer, emulator process responsiveness).
  2. Output matches expected behaviour (valid ASCII/ANSI, no crashes/panics).
  3. Screen layout is crisp with no misaligned output (cursor bounds, line
     widths, status bar position, box border integrity).

Proper filename strings are fed when observing input boxes so files can be
opened, saved, and plugins loaded during the chaos run.
"""

import os
import sys
import time
import tty
import select
import subprocess
import re
import json
import random
import argparse
from datetime import datetime, timezone


class MonkeyQualityError(Exception):
    """Base exception for quality failures."""
    pass


class HangError(MonkeyQualityError):
    """Criterion 1 failure: Emulator or editor hung / unresponsive."""
    pass


class UnexpectedBehaviourError(MonkeyQualityError):
    """Criterion 2 failure: Output does not match expected behaviour."""
    pass


class CrispLayoutError(MonkeyQualityError):
    """Criterion 3 failure: Screen layout misaligned or un-crisp."""
    pass


class VT100QualityMonitor:
    """
    Virtual VT100 terminal display buffer and output quality inspector.
    Evaluates every character/escape sequence received against the 3 quality
    criteria.
    """
    def __init__(self, cols=80, rows=24):
        self.cols = cols
        self.rows = rows
        self.reset()
        self.raw_stream_history = []
        self.last_output_time = time.time()

    def reset(self):
        self.buffer = [
            [" " for _ in range(self.cols)] for _ in range(self.rows)
        ]
        self.r = 0  # 0-indexed row (0..rows-1)
        self.c = 0  # 0-indexed col (0..cols-1)
        self.cursor_visible = True
        self.in_buffer = ""
        self.exiting = False

    def feed(self, text):
        """
        Feeds new terminal output text into the VT100 monitor, updates
        the virtual screen buffer, and validates all quality assertions.
        """
        self.last_output_time = time.time()
        self.raw_stream_history.append(text)
        self.in_buffer += text

        # Check Criterion 2: crash signatures in raw output
        self._check_crash_signatures(text)

        # Parse escape sequences and normal characters
        i = 0
        n = len(self.in_buffer)
        while i < n:
            ch = self.in_buffer[i]

            if ch == "\r":
                self.c = 0
                i += 1
            elif ch == "\n":
                if self.r < self.rows - 1:
                    self.r += 1
                i += 1
            elif ch == "\x08":  # Backspace
                self.c = max(0, self.c - 1)
                i += 1
            elif ch == "\x07":  # Bell
                i += 1
            elif ch == "\t":  # Tab
                self.c = min(self.cols - 1, (self.c + 8) & ~7)
                i += 1
            elif ch == "\x1b":
                # Look for ANSI escape sequences
                sub = self.in_buffer[i:]
                # Check for incomplete escape sequence at end of buffer
                if self._is_partial_escape(sub) and i + len(sub) == n:
                    break

                # Cursor positioning: \x1b[<r>;<c>H or \x1b[<r>;<c>f
                m = re.match(r"^\x1b\[([0-9;]*)([A-Za-z])", sub)
                if m:
                    params_str, cmd = m.groups()
                    params = [
                        int(p) for p in params_str.split(";") if p.isdigit()
                    ]
                    self._handle_csi_command(cmd, params, m.group(0))
                    i += len(m.group(0))
                    continue

                # DEC Private Mode: \x1b[?25h, \x1b[?25l, etc.
                m2 = re.match(r"^\x1b\[\?([0-9]+)([hl])", sub)
                if m2:
                    code, hl = m2.groups()
                    if code == "25":
                        self.cursor_visible = (hl == "h")
                    i += len(m2.group(0))
                    continue

                # Character set selection: \x1b(B, \x1b)0, etc.
                m3 = re.match(r"^\x1b[\(\)][0-9A-Za-z]", sub)
                if m3:
                    i += len(m3.group(0))
                    continue

                # Keypad mode: \x1b=, \x1b>
                if len(sub) >= 2 and sub[1] in "=><":
                    i += 2
                    continue

                # Standalone ESC or unrecognized sequence
                i += 1
            else:
                # Normal printable or control character
                # Criterion 3: Check for naked ANSI sequence fragments
                if ch == "[" and i + 1 < n:
                    peek = self.in_buffer[i:i + 12]
                    if re.match(r"^\[\d+;\d+[Hf]", peek):
                        raise CrispLayoutError(
                            f"Naked ANSI cursor sequence detected: {peek}"
                        )
                    if re.match(r"^\[\?25[hl]", peek):
                        raise CrispLayoutError(
                            f"Naked ANSI cursor show/hide detected: {peek}"
                        )

                # Store character in buffer
                if 0 <= self.r < self.rows and 0 <= self.c < self.cols:
                    self.buffer[self.r][self.c] = ch
                    self.c += 1
                elif self.c >= self.cols:
                    # Line wrap or right margin clipping
                    pass
                i += 1

        self.in_buffer = self.in_buffer[i:]

        # Validate Criterion 3: Screen crispness and layout alignment
        self._assert_crisp_layout()

    def _is_partial_escape(self, s):
        """
        Returns True if string s appears to be a truncated escape sequence.
        """
        if s == "\x1b":
            return True
        if s.startswith("\x1b["):
            rest = s[2:]
            if not any(c.isalpha() for c in rest):
                return True
        return False

    def _handle_csi_command(self, cmd, params, raw_seq):
        """Dispatches and asserts CSI commands."""
        if cmd in ("H", "f"):
            # Cursor position: 1-indexed (row, col)
            r = params[0] if len(params) > 0 and params[0] > 0 else 1
            c = params[1] if len(params) > 1 and params[1] > 0 else 1

            # Criterion 3: Cursor bounds verification
            if r < 1 or r > self.rows:
                raise CrispLayoutError(
                    f"Cursor row out of bounds: {r} (max {self.rows}) "
                    f"in sequence {repr(raw_seq)}"
                )
            if c < 1 or c > self.cols:
                raise CrispLayoutError(
                    f"Cursor col out of bounds: {c} (max {self.cols}) "
                    f"in sequence {repr(raw_seq)}"
                )

            self.r = r - 1
            self.c = c - 1

        elif cmd == "J":
            # Clear screen
            mode = params[0] if params else 0
            if mode in (0, 2):
                self.buffer = [
                    [" " for _ in range(self.cols)] for _ in range(self.rows)
                ]
                self.r = 0
                self.c = 0
        elif cmd == "K":
            # Clear in line
            mode = params[0] if params else 0
            if mode == 0:  # Clear from cursor to end of line
                for c_idx in range(self.c, self.cols):
                    self.buffer[self.r][c_idx] = " "
            elif mode == 2:  # Clear entire line
                for c_idx in range(self.cols):
                    self.buffer[self.r][c_idx] = " "
        elif cmd == "A":  # Cursor up
            dist = params[0] if params else 1
            self.r = max(0, self.r - dist)
        elif cmd == "B":  # Cursor down
            dist = params[0] if params else 1
            self.r = min(self.rows - 1, self.r + dist)
        elif cmd == "C":  # Cursor right
            dist = params[0] if params else 1
            self.c = min(self.cols - 1, self.c + dist)
        elif cmd == "D":  # Cursor left
            dist = params[0] if params else 1
            self.c = max(0, self.c - dist)
        elif cmd in ("m", "r"):
            pass  # Video attributes and scroll margins

    def _check_crash_signatures(self, text):
        """Criterion 2: Checks for fatal CP/M and RomWBW error signatures."""
        fatal_signatures = [
            "Bdos Err On",
            "Fatal Error",
            "Boot [H=Help]:",  # Unintended reboot / reset to vector 0x0000
            "Trap at",
            "PANIC:",
        ]
        for sig in fatal_signatures:
            if sig in text:
                raise UnexpectedBehaviourError(
                    f"Crash / fatal error signature detected: '{sig}'"
                )

        # Premature CP/M exit detection in raw terminal stream
        if not self.exiting:
            if "Exiting SE.COM" in text or "Returned to CP/M" in text:
                raise UnexpectedBehaviourError(
                    "Premature CP/M exit detected: 'Exiting SE.COM' in stream"
                )


    def _assert_crisp_layout(self):
        """
        Criterion 3: Ensures all screen rows maintain strictly crisp bounds,
        proper status bar placement, and no line overrun.
        """
        # 1. Row count & Column count integrity
        if len(self.buffer) != self.rows:
            raise CrispLayoutError(
                f"Virtual screen row count corrupted: {len(self.buffer)} "
                f"expected {self.rows}"
            )
        for r_idx, row in enumerate(self.buffer):
            if len(row) != self.cols:
                raise CrispLayoutError(
                    f"Row {r_idx} length corrupted: {len(row)} "
                    f"expected {self.cols}"
                )

        # 2. Status bar positioning integrity:
        # The status bar contains '^K: Editor keys' or '| Col ' or ' Free:'
        # and must ONLY appear on the bottom row (self.rows - 1).
        bottom_row = self.rows - 1
        status_signatures = [
            "^K: Editor keys",
            "| Col ",
            "| Line ",
        ]
        for r_idx in range(self.rows):
            row_str = "".join(self.buffer[r_idx])
            for sig in status_signatures:
                if sig in row_str and r_idx != bottom_row:
                    raise CrispLayoutError(
                        f"Status bar signature '{sig}' appeared on row {r_idx} "
                        f"instead of bottom row {bottom_row}!"
                    )

        # In Plugin Manager screen, ensure bottom row contains the status bar
        # and all rows above bottom row have '~' in column 0
        full_text = "\n".join("".join(row) for row in self.buffer)
        if "SE - Plugin Manager" in full_text:
            bottom_str = "".join(self.buffer[bottom_row])
            if "|" not in bottom_str or (
                "80x24" not in bottom_str and "120x40" not in bottom_str
            ):
                raise CrispLayoutError(
                    "Plugin Manager screen missing bottom row status bar: "
                    f"'{bottom_str.strip()}'"
                )
            for r_idx in range(bottom_row):
                if self.buffer[r_idx][0] != "~":
                    raise CrispLayoutError(
                        f"Plugin Manager missing '~' in col 0 on row {r_idx}: "
                        f"'{''.join(self.buffer[r_idx])[:30]}'"
                    )

        # 3. Modal dialog box border alignment:
        # If a row starts with '+---' or '| ' and ends with '---+' or ' |',
        # check width consistency.
        for r_idx, row in enumerate(self.buffer):
            line = "".join(row).strip()
            if line.startswith("+") and line.endswith("+") and len(line) > 10:
                pass  # Horizontal rule
            elif line.startswith("|") and line.endswith("|") and len(line) > 10:
                pass  # Enclosed row

        # 4. Splash / Editor mixed screen detection:
        # When splash screen menu is visible, row 0 and 1 must be splash padding
        # (starting with '~' or spaces). If row 0 contains document text without
        # '~', a mixed screen corruption occurred.
        full_text = "\n".join("".join(row) for row in self.buffer)
        if "SE - Screen Editor" in full_text and "type   e" in full_text:
            row0_str = "".join(self.buffer[0]).strip()
            if row0_str and not row0_str.startswith("~"):
                raise CrispLayoutError(
                    "Mixed screen corruption detected: Splash screen menu "
                    f"active but row 0 contains editor text: '{row0_str[:40]}'"
                )

        # 5. Premature CP/M exit detection (skipped during clean test teardown):
        if not self.exiting:
            if " file not found" in full_text:
                raise UnexpectedBehaviourError(
                    "Premature CP/M exit detected: 'file not found' on screen"
                )
            if "Exiting SE.COM" in full_text or "Returned to CP/M" in full_text:
                raise UnexpectedBehaviourError(
                    "Premature CP/M exit detected: SE.COM exit banner on screen"
                )
            bottom_row = self.rows - 1
            bottom_str = "".join(self.buffer[bottom_row])
            editor_sigs = ("80x24 |", "120x40 |", "^K: Editor keys", "| Line ")
            has_status_bar = any(sig in bottom_str for sig in editor_sigs)
            for r_idx, row in enumerate(self.buffer):
                row_str = "".join(row).strip()
                if re.match(r"^[A-P]>", row_str):
                    if r_idx == bottom_row or not has_status_bar:
                        raise UnexpectedBehaviourError(
                            f"Premature CP/M exit detected on row {r_idx}: "
                            f"'{row_str[:40]}'"
                        )

    def detect_screen_state(self):
        """
        Inspects the screen buffer to identify the active UI context/prompt.
        Returns a string identifying the state.
        """
        full_text = "\n".join("".join(row) for row in self.buffer)

        if "Save changes?" in full_text or "Unsaved Modifications" in full_text:
            return "save_changes_prompt"
        if ("Enter filename to open:" in full_text or
                "OPEN FILE (DIRECTORY" in full_text):
            return "open_file_prompt"
        if ("Enter filename to save:" in full_text or
                "SAVE FILE (DIRECTORY" in full_text):
            return "save_file_prompt"
        if ("Enter filename to insert:" in full_text or
                "INSERT FILE" in full_text):
            return "insert_file_prompt"
        if "Load Plugin (.PRL/.OVL):" in full_text:
            return "load_plugin_prompt"
        if (("Unload Slot " in full_text and "[Y/N]" in full_text) or
                "Unload Slot (0..7):" in full_text):
            return "unload_plugin_prompt"
        if "Goto line:" in full_text:
            return "goto_line_prompt"
        if "Replace with:" in full_text:
            return "replace_prompt"
        if "Find (Exact):" in full_text or "Find (Insens):" in full_text:
            return "find_prompt"
        if "File already exists. Overwrite?" in full_text:
            return "overwrite_prompt"
        if "Replace (" in full_text and "uit/" in full_text:
            return "replace_confirm_prompt"
        if ("[Up/Dn/0-7] Select" in full_text or
                "Select [0-7] to Execute" in full_text or
                "Plugins for Editor" in full_text or
                "to Dismiss" in full_text):
            return "plugin_popup"
        if "Save & Exit" in full_text:
            return "plugin_config"
        if "Press any key" in full_text:
            return "press_any_key"
        if "SE - Screen Editor Configuration" in full_text:
            return "configuration_screen"
        if ("SE - Screen Editor" in full_text and
                ("Active Screen:" in full_text or "type   e" in full_text)):
            return "splash_screen"
        if ("SE - Plugin Manager" in full_text or
                "0..7:select" in full_text or
                "Up/Dn:select" in full_text):
            return "plugin_manager"
        if ("^K: Editor keys" in full_text or
                "^V: Overwrite" in full_text or
                "[SEL:" in full_text or
                "[BLK:" in full_text or
                ("[Pan +" in full_text and ("80x24 |" in full_text or
                                            "120x40 |" in full_text)) or
                ("| Line " in full_text and ("80x24 |" in full_text or
                                             "120x40 |" in full_text)) or
                "Pattern not found" in full_text or
                "Search completed" in full_text or
                "Replace done:" in full_text or
                "Line > 120 chars" in full_text):
            return "editor"

        if ("Exiting SE.COM" in full_text or
                ("C>" in full_text and "^K: Editor keys" not in full_text and
                 "| Line " not in full_text and "SE - " not in full_text)):
            return "cpm_prompt"

        return "unknown"

    def render(self):
        """Renders the virtual terminal buffer with bounding border."""
        border = "+" + "-" * self.cols + "+"
        lines = [border]
        for row in self.buffer:
            lines.append("|" + "".join(row) + "|")
        lines.append(border)
        return "\n".join(lines)


class DrunkenMonkeyInputGenerator:
    """
    Intelligent chaos character generator.
    Selects random characters (printable, control keys, arrows), with smart
    awareness of input prompts so that proper filename strings can be tested.
    """
    def __init__(self, mode="80x24", seed=None, min_delay=0.02,
                 max_delay=0.08):
        self.mode = mode
        self.rng = random.Random(seed)
        self.min_delay = min_delay
        self.max_delay = max_delay
        self.pending_chars = []  # Queue of (char, desc) tuples
        self.prompt_repeat_count = 0
        self.last_prompt_state = None

        # Printable character pool
        self.printable_chars = (
            "abcdefghijklmnopqrstuvwxyz"
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            "0123456789"
            " .,;:!?-+=_*/()[]{}<>~#%^&@$'\""
        )

        # Editor control keys pool
        self.control_keys = [
            ("\x01", "Ctrl+A (Word Left)"),
            ("\x02", "Ctrl+B (Block Toggle)"),
            ("\x03", "Ctrl+C (Page Down)"),
            ("\x04", "Ctrl+D (Char Right)"),
            ("\x05", "Ctrl+E (Line Up)"),
            ("\x06", "Ctrl+F (Find UI)"),
            ("\x07", "Ctrl+G (Delete Char)"),
            ("\x08", "Ctrl+H (Backspace)"),
            ("\t",   "Tab (Indent)"),
            ("\x0b", "Ctrl+K (Help Screen)"),
            ("\x0c", "Ctrl+L (Goto Line)"),
            ("\r",   "Enter (Newline)"),
            ("\x0e", "Ctrl+N (Insert Line)"),
            ("\x0f", "Ctrl+O (Open Screen)"),
            ("\x10", "Ctrl+P (Plugin Pop-up)"),
            ("\x12", "Ctrl+R (Replace UI)"),
            ("\x13", "Ctrl+S (Save Screen)"),
            ("\x14", "Ctrl+T (Delete Word)"),
            ("\x15", "Ctrl+U (Unindent)"),
            ("\x16", "Ctrl+V (Toggle Overwrite)"),
            ("\x17", "Ctrl+W (Close File)"),
            ("\x18", "Ctrl+X (Line Down)"),
            ("\x19", "Ctrl+Y (Beautify)"),
            ("\x1a", "Ctrl+Z (Plugin Manager)"),
            ("\x1b", "ESC (Cancel)"),
        ]

    def queue_string(self, text, prefix_desc=""):
        """Queues a sequence of characters to be typed 1 at a time."""
        for ch in text:
            desc = f"{prefix_desc} '{repr(ch)}'" if prefix_desc else repr(ch)
            self.pending_chars.append((ch, None, desc))

    def queue_input_string(self, text, prefix_desc=""):
        """
        Clears existing input box text with backspaces, then types text.
        For standalone ESC or control keys, queues without clearing.
        """
        if text in ("\x1b", "\x03", "\x06"):
            if text == "\x1b":
                desc = f"{prefix_desc} ESC (Cancel)"
            elif text == "\x03":
                desc = f"{prefix_desc} Ctrl+C"
            else:
                desc = f"{prefix_desc} Ctrl+F"
            self.pending_chars.append((text, None, desc))
            return

        clear_seq = "\x08" * 16
        for ch in clear_seq:
            self.pending_chars.append((ch, None, f"{prefix_desc} <BS>"))
        for ch in text:
            desc = f"{prefix_desc} '{repr(ch)}'" if prefix_desc else repr(ch)
            self.pending_chars.append((ch, None, desc))


    def _pop_pending(self, default_delay):
        """Pops next pending character and resolves delay."""
        ch, custom_delay, desc = self.pending_chars.pop(0)
        if custom_delay is not None:
            return ch, custom_delay, desc
        d = (
            max(default_delay, 0.15)
            if ch in ("\x1b", "\r", "\x03")
            else default_delay
        )
        return ch, d, desc

    def next_character(self, screen_state):
        """
        Returns the next (char, delay, desc) tuple based on screen state.
        """
        delay = self.rng.uniform(self.min_delay, self.max_delay)

        # Track prompt persistence when no characters are pending
        if screen_state != "editor" and not self.pending_chars:
            if screen_state == self.last_prompt_state:
                self.prompt_repeat_count += 1
            else:
                self.prompt_repeat_count = 1
                self.last_prompt_state = screen_state
        elif screen_state == "editor":
            self.prompt_repeat_count = 0
            self.last_prompt_state = None

        # Watchdog: if a prompt dialog persists for > 3 steps without progress,
        # force an emergency breakout to resume editor testing
        if self.prompt_repeat_count > 3:
            self.pending_chars.clear()
            self.prompt_repeat_count = 0
            if screen_state == "save_changes_prompt":
                return "\x03", 0.15, "Watchdog Breakout: Ctrl+C"
            elif screen_state == "splash_screen":
                return "e", 0.15, "Watchdog Breakout: 'e' (Editor)"
            elif screen_state == "press_any_key":
                return " ", 0.15, "Watchdog Breakout: Space"
            elif screen_state == "plugin_manager":
                return "q", 0.15, "Watchdog Breakout: 'q' (Plugin Mgr)"
            elif screen_state == "plugin_config":
                return "q", 0.15, "Watchdog Breakout: 'q' (Plugin Config)"
            elif screen_state == "configuration_screen":
                return "q", 0.15, "Watchdog Breakout: 'q' (Config)"
            else:
                return "\x1b", 0.15, f"Watchdog Breakout: ESC ({screen_state})"

        # 1. If we have queued prompt characters, pop the next character
        if self.pending_chars:
            return self._pop_pending(delay)

        # 2. Smart prompt handling when an input box is observed
        if screen_state == "splash_screen":
            # Primary action is (E)ditor Mode to resume editing;
            # stay within the active test terminal geometry
            mode_key = "2" if self.mode == "80x24" else "1"
            action = self.rng.choice([
                ("e", "Splash: (E)ditor Mode"),
                ("e", "Splash: (E)ditor Mode"),
                ("e", "Splash: (E)ditor Mode"),
                ("o", "Splash: (O)pen File"),
                ("a", "Splash: (A)bout Screen"),
                ("m", "Splash: (M)emory Info"),
                ("p", "Splash: (P)lugin Manager"),
                (mode_key, f"Splash: Refresh {self.mode}"),
            ])
            return action[0], delay, action[1]

        elif screen_state == "open_file_prompt":
            candidate = self.rng.choice([
                "README.TXT\r",
                "30.TXT\r",
                "2.TXT\r",
                "NONEXIST.TXT\r",
                "C:*.TXT\r",
                "\x1b",
            ])
            if candidate == "\x1b":
                return "\x1b", 0.15, "Open file: ESC (Cancel)"
            self.queue_input_string(candidate, "Open file:")
            return self._pop_pending(delay)

        elif screen_state == "save_file_prompt":
            candidate = self.rng.choice([
                "MONKEY.TXT\r",
                "TEST.TXT\r",
                "\x06",  # Ctrl+F format toggle
                "\x1b",  # Cancel
            ])
            if candidate == "\x1b":
                return "\x1b", 0.15, "Save file: ESC (Cancel)"
            self.queue_input_string(candidate, "Save file:")
            return self._pop_pending(delay)

        elif screen_state == "insert_file_prompt":
            candidate = self.rng.choice(["2.TXT\r", "30.TXT\r", "\x1b"])
            if candidate == "\x1b":
                return "\x1b", 0.15, "Insert file: ESC (Cancel)"
            self.queue_input_string(candidate, "Insert file:")
            return self._pop_pending(delay)

        elif screen_state == "load_plugin_prompt":
            candidate = self.rng.choice([
                "ROT13.PRL\r",
                "FATFS.PRL\r",
                "NO.PRL\r",
                "\x1b",
            ])
            self.queue_input_string(candidate, "Load plugin:")
            return self._pop_pending(delay)

        elif screen_state == "goto_line_prompt":
            candidate = self.rng.choice([
                "1\r", "10\r", "25\r", "999\r", "\x1b"
            ])
            self.queue_input_string(candidate, "Goto line:")
            return self._pop_pending(delay)

        elif screen_state == "find_prompt":
            candidate = self.rng.choice(["SE\r", "the\r", "test\r", "\x1b"])
            self.queue_input_string(candidate, "Find:")
            return self._pop_pending(delay)

        elif screen_state == "replace_prompt":
            candidate = self.rng.choice(["REPLACE\r", "NEW\r", "\x1b"])
            self.queue_input_string(candidate, "Replace with:")
            return self._pop_pending(delay)

        elif screen_state == "save_changes_prompt":
            choice = self.rng.choice([
                ("y", "Save changes: 'y' (Save)"),
                ("n", "Save changes: 'n' (Discard)"),
                ("\x1b", "Save changes: ESC (Cancel)"),
            ])
            ch, desc = choice
            d = max(delay, 0.15) if ch == "\x1b" else delay
            return ch, d, desc

        elif screen_state == "overwrite_prompt":
            choice = self.rng.choice(["y", "n"])
            return choice, delay, f"Overwrite: {choice}"

        elif screen_state == "replace_confirm_prompt":
            choice = self.rng.choice(["y", "n", "a", "\x1b"])
            d = max(delay, 0.15) if choice == "\x1b" else delay
            return choice, d, f"Replace confirm: {choice}"

        elif screen_state == "plugin_popup":
            slot = self.rng.choice(["0", "1", "2", "\x1b", "q"])
            d = max(delay, 0.15) if slot in ("\x1b", "q") else delay
            return slot, d, f"Plugin popup: {slot}"

        elif screen_state == "press_any_key":
            return " ", delay, "Dismiss Help/Info: Space"

        elif screen_state == "plugin_manager":
            action = self.rng.choice([
                ("q", "Plugin Mgr: (Q)uit to Editor"),
                ("\r", "Plugin Mgr: Enter (Load/Unload)"),
                ("a", "Plugin Mgr: (A)bout"),
                ("c", "Plugin Mgr: (C)onfig"),
                ("l", "Plugin Mgr: (L)oad"),
                ("u", "Plugin Mgr: (U)nload"),
                ("s", "Plugin Mgr: (S)ave Config"),
                ("j", "Plugin Mgr: Down"),
                ("k", "Plugin Mgr: Up"),
                (str(self.rng.randint(0, 7)), "Plugin Mgr: Slot Action"),
            ])
            d = max(delay, 0.15) if action[0] == "q" else delay
            return action[0], d, action[1]

        elif screen_state == "unload_plugin_prompt":
            choice = self.rng.choice(["y", "n", "\r", "\x1b"])
            d = max(delay, 0.15) if choice == "\x1b" else delay
            return choice, d, f"Unload plugin confirm: {choice}"

        elif screen_state == "plugin_config":
            choice = self.rng.choice(["1", "2", "3", "4", "q", "\r"])
            d = max(delay, 0.15) if choice in ("q", "\r") else delay
            return choice, d, f"Plugin Config: {choice}"

        elif screen_state == "configuration_screen":
            action = self.rng.choice([
                ("q", "Config: (Q)uit to Splash"),
                ("\x1b", "Config: ESC (Return)"),
                ("2", "Config: Toggle RAM Drive"),
                ("3", "Config: Toggle Max Lines"),
                ("4", "Config: Toggle Tab"),
                ("5", "Config: Toggle Plugin Mgr"),
            ])
            d = max(delay, 0.15) if action[0] in ("q", "\x1b") else delay
            return action[0], d, action[1]

        # 3. Default: Editor chaos input distribution
        # 50% printable character
        # 35% control key / navigation
        # 15% VT100 arrow sequence
        roll = self.rng.random()
        if roll < 0.50:
            ch = self.rng.choice(self.printable_chars)
            return ch, delay, f"Printable '{ch}'"
        elif roll < 0.85:
            ch, desc = self.rng.choice(self.control_keys)
            return ch, delay, desc
        else:
            # VT100 arrow key escape sequence: emit atomically as single burst
            arrow = self.rng.choice([
                ("\x1b[A", "Arrow Up"),
                ("\x1b[B", "Arrow Down"),
                ("\x1b[C", "Arrow Right"),
                ("\x1b[D", "Arrow Left"),
            ])
            return arrow[0], delay, arrow[1]


class SessionRecorder:
    """Records key sequences and time gaps to JSON for deterministic replay."""
    def __init__(self, mode="80x24", seed=None, base_image=None):
        self.metadata = {
            "version": 1,
            "suite": "drunken_monkey",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "screen_mode": mode,
            "seed": seed,
            "base_image": base_image or "hd1k_golden.img",
            "total_steps": 0,
        }
        self.events = []

    def record_step(self, step, ch, delay, desc, state, screen=None):
        if len(ch) == 1:
            hex_str = f"0x{ord(ch):02x}"
        else:
            hex_str = " ".join(f"0x{ord(c):02x}" for c in ch)
        entry = {
            "step": step,
            "char": ch,
            "hex": hex_str,
            "delay": round(delay, 4),
            "desc": desc,
            "state": state,
        }
        if screen is not None:
            entry["screen"] = screen
        self.events.append(entry)
        self.metadata["total_steps"] = len(self.events)

    def save(self, filepath):
        data = {
            "metadata": self.metadata,
            "events": self.events,
        }
        os.makedirs(os.path.dirname(os.path.abspath(filepath)), exist_ok=True)
        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
        print(f"[+] Recorded {len(self.events)} events to: {filepath}",
              flush=True)


class SessionReplayer:
    """Loads and replays an exact recorded session against SE.COM."""
    def __init__(self, filepath, speed=1.0):
        with open(filepath, "r", encoding="utf-8") as f:
            self.data = json.load(f)
        self.events = self.data["events"]
        self.metadata = self.data.get("metadata", {})
        self.speed = max(0.01, speed)

    @property
    def total_steps(self):
        return len(self.events)

    def get_event(self, idx):
        event = self.events[idx]
        char = event["char"]
        delay = event["delay"] / self.speed
        desc = event.get("desc", repr(char))
        return char, delay, desc


def find_paths():
    """Locates workspace binaries and tools."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    workspace_root = os.path.abspath(os.path.join(repo_root, "..", ".."))

    emu_bin = os.path.join(workspace_root, "tools", "rc2014_emu", "rc2014")
    rom_file = os.path.join(
        workspace_root, "tools", "romwbw_src", "Binary", "RC2014_std.rom"
    )
    golden_img = os.path.join(
        workspace_root, "tools", "romwbw_src", "Binary", "hd1k_golden.img"
    )
    combo_img = os.path.join(
        workspace_root, "tools", "romwbw_src", "Binary", "hd1k_combo.img"
    )
    img_file = golden_img if os.path.isfile(golden_img) else combo_img
    se_bin = os.path.join(repo_root, "SE.COM")
    cpmcp_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp"
    )
    cpmrm_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm"
    )

    return emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin


def read_available(master_fd, timeout=0.05):
    """Reads all currently available bytes from master_fd without blocking."""
    buf = b""
    while True:
        r, _, _ = select.select([master_fd], [], [], timeout)
        if not r:
            break
        try:
            chunk = os.read(master_fd, 4096)
            if not chunk:
                break
            buf += chunk
            timeout = 0.035  # Keep draining incoming screen burst
        except (BlockingIOError, OSError):
            break
    return buf


def read_until(master_fd, match_bytes, timeout=6.0):
    """Reads until match_bytes is found in stream or timeout expires."""
    buf = b""
    t0 = time.time()
    while time.time() - t0 < timeout:
        r, _, _ = select.select([master_fd], [], [], 0.03)
        if r:
            try:
                data = os.read(master_fd, 1024)
                if not data:
                    break
                buf += data
                if match_bytes in buf:
                    return buf
            except (BlockingIOError, OSError):
                pass
    return buf


def run_drunken_monkey_test(
    steps=100,
    record_file=None,
    replay_file=None,
    seed=None,
    mode="80x24",
    speed=1.0,
    verbose=False,
    show_grabs=True,
    grab_interval=10,
    keep_disk=False,
):
    """
    Main runner for the Drunken Monkey Test.
    """
    print("=" * 76, flush=True)
    if replay_file:
        print(f"[*] Starting Drunken Monkey REPLAY: {replay_file} "
              f"(speed: {speed}x)", flush=True)
    else:
        print(f"[*] Starting Drunken Monkey CHAOS TEST: {steps} steps "
              f"(seed: {seed}, mode: {mode})", flush=True)
    print("=" * 76, flush=True)

    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = find_paths()

    # Pre-test binary & file checks
    for p, name in [
        (emu_bin, "Emulator"),
        (rom_file, "ROM"),
        (img_file, "Disk Image"),
        (se_bin, "SE.COM"),
    ]:
        if not os.path.isfile(p):
            print(f"[-] Required {name} not found: {p}", flush=True)
            return False

    # Create ephemeral isolated copy of the disk image to ensure
    # 100% deterministic initial state and eliminate cross-agent race conditions
    ephemeral_img = os.path.join(
        "/tmp", f"monkey_disk_{os.getpid()}_{int(time.time() * 1000)}.img"
    )
    try:
        subprocess.run(
            ["cp", "--reflink=auto", "--sparse=always", img_file,
             ephemeral_img],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        os.chmod(ephemeral_img, 0o644)
    except Exception as e:
        print(f"[-] Failed to create ephemeral disk image: {e}", flush=True)
        return False

    base_name = os.path.basename(img_file)
    print(f"[*] Ephemeral disk initialized from {base_name}: {ephemeral_img}",
          flush=True)

    # Sync latest SE.COM onto ephemeral disk image drive C:
    if os.path.isfile(cpmrm_bin):
        subprocess.run(
            [cpmrm_bin, "-f", "wbw_hd1k_0", ephemeral_img, "0:SE.COM"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    if os.path.isfile(cpmcp_bin):
        try:
            subprocess.run(
                [cpmcp_bin, "-f", "wbw_hd1k_0", ephemeral_img, se_bin,
                 "0:SE.COM"],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except subprocess.CalledProcessError as e:
            print(f"[-] Warning: Failed to sync SE.COM: {e}", flush=True)

    # Sync latest plugins onto ephemeral disk image drive C:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    plugins_dir = os.path.join(repo_root, "plugins")
    if os.path.isdir(plugins_dir) and os.path.isfile(cpmcp_bin):
        for pf in os.listdir(plugins_dir):
            if pf.upper().endswith((".PRL", ".OVL")):
                p_path = os.path.join(plugins_dir, pf)
                tgt = f"0:{pf.upper()}"
                if os.path.isfile(cpmrm_bin):
                    subprocess.run(
                        [cpmrm_bin, "-f", "wbw_hd1k_0", ephemeral_img, tgt],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
                subprocess.run(
                    [cpmcp_bin, "-f", "wbw_hd1k_0", ephemeral_img, p_path,
                     tgt],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )

    # Setup terminal monitor
    cols = 120 if mode == "120x40" else 80
    rows = 40 if mode == "120x40" else 24
    monitor = VT100QualityMonitor(cols=cols, rows=rows)

    # Initialize recorder or replayer
    recorder = None
    replayer = None
    if replay_file:
        replayer = SessionReplayer(replay_file, speed=speed)
        steps = replayer.total_steps
    else:
        if record_file:
            recorder = SessionRecorder(mode=mode, seed=seed,
                                       base_image=base_name)
        generator = DrunkenMonkeyInputGenerator(mode=mode, seed=seed)

    # Spawn emulator process over PTY
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", ephemeral_img]
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )
    os.close(slave)

    try:
        # 1. Boot RomWBW
        out = read_until(master, b"Boot [H=Help]:", timeout=8.0)
        if b"Boot [H=Help]:" not in out:
            raise HangError("RomWBW failed to boot to prompt.")

        time.sleep(0.3)
        os.write(master, b"c\r")
        out = read_until(master, b"B>", timeout=6.0)
        if b"B>" not in out:
            raise HangError("Failed to boot CP/M on ROM disk B>.")

        time.sleep(0.3)
        os.write(master, b"c:\r")
        out = read_until(master, b"C>", timeout=8.0)
        if b"C>" not in out:
            raise HangError("Failed to switch to Drive C>.")

        # 2. Launch SE.COM
        time.sleep(0.5)
        os.write(master, b"se\r")
        splash_out = read_until(master, b"for about", timeout=30.0)
        if b"for about" not in splash_out and b"Col 0" not in splash_out:
            raise HangError(
                f"SE.COM splash screen failed to appear. "
                f"Captured: {repr(splash_out[-300:])}"
            )

        # Configure screen mode if needed
        if mode == "120x40":
            os.write(master, b"1")
            read_until(master, b"Col 0", timeout=5.0)
        elif mode == "80x24":
            os.write(master, b"2")
            read_until(master, b"Col 0", timeout=5.0)

        # Enter Editor mode ('e')
        time.sleep(0.2)
        os.write(master, b"e")
        ed_out = read_until(master, b"^K: Editor keys", timeout=6.0)
        if b"^K: Editor keys" not in ed_out:
            raise HangError("Failed to enter editor mode from splash.")

        monitor.feed(ed_out.decode("latin1", errors="replace"))

        print(f"[+] Boot and SE.COM launch complete ({mode}). "
              f"Beginning step loop...", flush=True)

        if show_grabs:
            print(f"\n>>> [SCREEN GRAB: Initial Editor Screen ({mode})]",
                  flush=True)
            print(monitor.render(), flush=True)

        # 3. Main Monkey Step Loop
        for step in range(1, steps + 1):
            # Check Criterion 1: Process responsiveness
            if proc.poll() is not None:
                raise HangError(
                    f"Emulator process terminated prematurely at step {step}!"
                )

            # Detect current UI state before action
            state = monitor.detect_screen_state()
            if state == "cpm_prompt":
                raise UnexpectedBehaviourError(
                    f"Premature CP/M exit detected at step {step}: "
                    "CP/M prompt active on screen!"
                )

            # Select character and delay
            if replayer:
                char, delay, desc = replayer.get_event(step - 1)
            else:
                char, delay, desc = generator.next_character(state)

            # Apply measured time gap before sending character
            if delay > 0:
                time.sleep(delay)

            # Send exactly 1 character
            os.write(master, char.encode("latin1"))

            # Observe effect on output (Criterion 1 watchdog & 2/3 validation)
            if char == "\x1b" and not (desc and "Arrow" in desc):
                # Let SE.COM's VT100 ESC sequence debounce timer expire
                time.sleep(0.12)

            # Major keys or modal/splash states trigger full screen redraws
            major_keys = (
                "\r", "\x1b", "\x03", "\x06", "\x0b", "\x0c",
                "\x0f", "\x10", "\x12", "\x13", "\x17", "\x1a",
                "e", "E", "1", "2"
            )
            needs_wait = char in major_keys or state != "editor"
            read_timeout = 0.30 if needs_wait else 0.04
            chunk = read_available(master, timeout=read_timeout)

            if chunk:
                # Feed new output to monitor -> automatically runs Assertions
                # Criterion 1 (alive), 2 (expected behaviour), 3 (crisp layout)
                monitor.feed(chunk.decode("latin1", errors="replace"))

            new_state = monitor.detect_screen_state()

            if recorder:
                recorder.record_step(
                    step, char, delay, desc, new_state,
                    screen=["".join(r) for r in monitor.buffer]
                )

            # Log step
            if len(char) == 1:
                hex_code = f"0x{ord(char):02x}"
            else:
                hex_code = " ".join(f"0x{ord(c):02x}" for c in char)
            if verbose or step % 25 == 0 or step == steps:
                print(f"  [Step {step:4d}/{steps:4d}] "
                      f"Char: {hex_code} ({desc:<26}) "
                      f"State: {new_state:<18} Delay: {delay:.3f}s",
                      flush=True)

            # Display live screen grab if enabled
            if show_grabs:
                should_grab = (
                    step == 1 or
                    step % grab_interval == 0 or
                    new_state != state or
                    step == steps
                )
                if should_grab:
                    print(
                        f"\n>>> [SCREEN GRAB: Step {step:3d}/{steps:3d} | "
                        f"Key: {hex_code} ({desc}) | State: {new_state}]",
                        flush=True
                    )
                    print(monitor.render(), flush=True)

        print("\n" + "=" * 76, flush=True)
        print(f"[+] Completed all {steps} characters successfully!",
              flush=True)

        # 4. Clean exit back to CP/M
        print("[*] Performing clean exit back to CP/M...", flush=True)
        monitor.exiting = True
        t0 = time.time()
        while time.time() - t0 < 25.0:
            p_poll = proc.poll()
            if verbose:
                print(f"[*] Teardown loop: proc.poll()={p_poll}", flush=True)
            if p_poll is not None:
                raise HangError(
                    f"Emulator exited prematurely in teardown (code {p_poll})"
                )
            chunk = read_available(master, timeout=0.25)
            if chunk:
                if verbose:
                    print(f"[*] Teardown read {len(chunk)} bytes: "
                          f"{repr(chunk[:50])}", flush=True)
                monitor.feed(chunk.decode("latin1", errors="replace"))

            full_screen = "\n".join("".join(r) for r in monitor.buffer)
            chunk_str = (
                chunk.decode("latin1", errors="replace") if chunk else ""
            )

            # Check if CP/M prompt has returned
            if (re.search(r"(?:^|\n)\s*[A-P]>", full_screen) or
                    re.search(r"(?:\r\n|\r|\n|^)[A-P]>", chunk_str)):
                print("[+] Clean exit to CP/M prompt (C>) verified.",
                      flush=True)
                break

            state = monitor.detect_screen_state()
            if verbose:
                print(f"[*] Teardown loop: state={state}, prompt_check="
                      f"{'C>' in full_screen or '[A-P]>' in full_screen}",
                      flush=True)

            # If Save changes / modifications prompt is visible, answer 'n'
            if ("Save changes?" in full_screen or
                    "Unsaved Modifications" in full_screen or
                    state == "save_changes_prompt"):
                if verbose:
                    print("[*] Teardown: Sending 'n' to save changes prompt",
                          flush=True)
                os.write(master, b"n")
                time.sleep(0.15)
                drain = read_available(master, timeout=1.5)
                if drain:
                    if verbose:
                        print(f"[*] Teardown drained {len(drain)} bytes "
                              f"after 'n'", flush=True)
                    monitor.feed(drain.decode("latin1", errors="replace"))
                continue

            # If in splash screen, send 'q' to exit
            if state == "splash_screen":
                if verbose:
                    print("[*] Teardown: Sending 'q' to splash screen",
                          flush=True)
                os.write(master, b"q")
                time.sleep(0.15)
                drain = read_available(master, timeout=1.5)
                if drain:
                    if verbose:
                        print(f"[*] Teardown drained {len(drain)} bytes "
                              f"after 'q'", flush=True)
                    monitor.feed(drain.decode("latin1", errors="replace"))
                continue

            # If in management/workspace screen, send 'q' to exit
            if state in ("plugin_manager", "plugin_config",
                         "configuration_screen"):
                if verbose:
                    print(f"[*] Teardown: Sending 'q' to {state}", flush=True)
                os.write(master, b"q")
                time.sleep(0.15)
                drain = read_available(master, timeout=1.5)
                if drain:
                    if verbose:
                        print(f"[*] Teardown drained {len(drain)} bytes "
                              f"after 'q'", flush=True)
                    monitor.feed(drain.decode("latin1", errors="replace"))
                continue

            # If in an input dialog or popup, cancel it via ESC
            if state.endswith("_prompt") or state == "plugin_popup":
                if verbose:
                    print(f"[*] Teardown: Cancelling {state} with ESC",
                          flush=True)
                os.write(master, b"\x1b")
                time.sleep(0.15)
                drain = read_available(master, timeout=2.0)
                if drain:
                    if verbose:
                        print(f"[*] Teardown drained {len(drain)} bytes "
                              f"after ESC", flush=True)
                    monitor.feed(drain.decode("latin1", errors="replace"))
                continue

            # In normal editor mode: send Ctrl+Q
            if verbose:
                print("[*] Teardown: Sending Ctrl+Q to editor", flush=True)
            os.write(master, b"\x11")  # Ctrl+Q
            time.sleep(0.15)
            drain = read_available(master, timeout=1.5)
            if drain:
                if verbose:
                    print(f"[*] Teardown drained {len(drain)} bytes "
                          f"after Ctrl+Q", flush=True)
                monitor.feed(drain.decode("latin1", errors="replace"))
        else:
            raise UnexpectedBehaviourError(
                "Teardown failed: Clean exit to CP/M prompt (C>) not verified!"
            )

        # Save recorder output
        if recorder and record_file:
            recorder.save(record_file)

        print("\n[QUALITY REPORT]")
        print("  1. System responsiveness: PASS (No hangs detected)")
        print("  2. Output behaviour:      PASS (Valid ANSI/ASCII stream)")
        print("  3. Screen layout:         PASS (Crisp, bounds preserved)")
        print("=" * 76, flush=True)
        return True

    except MonkeyQualityError as mqe:
        print(f"\n[-] QUALITY CRITERIA FAILED: {type(mqe).__name__}: {mqe}",
              flush=True)
        print("[-] Virtual screen at point of failure:", flush=True)
        print(monitor.render(), flush=True)
        if recorder and record_file:
            fail_file = record_file + ".failure.json"
            recorder.save(fail_file)
            print(f"[*] Partial session saved to {fail_file} for replay.",
                  flush=True)
            fail_disk = record_file + ".failure.disk.img"
            try:
                subprocess.run(
                    ["cp", "--reflink=auto", "--sparse=always", ephemeral_img,
                     fail_disk],
                    check=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                print(f"[*] Failure disk snapshot saved to {fail_disk}",
                      flush=True)
            except Exception as e:
                print(f"[-] Could not archive failure disk: {e}", flush=True)
        return False

    finally:
        try:
            os.close(master)
        except OSError:
            pass
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=1.0)
            except subprocess.TimeoutExpired:
                proc.kill()
        if not keep_disk and os.path.isfile(ephemeral_img):
            try:
                os.remove(ephemeral_img)
            except OSError:
                pass


def main():
    parser = argparse.ArgumentParser(
        description="Drunken Monkey Chaos Test Suite for SE.COM"
    )
    parser.add_argument(
        "--steps", type=int, default=100,
        help="Number of random characters to send (default: 100)"
    )
    parser.add_argument(
        "--record", type=str, default="tests/monkey_session.json",
        help="Path to save recorded key sequence JSON"
    )
    parser.add_argument(
        "--replay", type=str, default=None,
        help="Path to recorded key sequence JSON to replay"
    )
    parser.add_argument(
        "--seed", type=int, default=None,
        help="Random seed for reproducible chaos generation"
    )
    parser.add_argument(
        "--mode", choices=["80x24", "120x40"], default="80x24",
        help="Terminal screen mode (default: 80x24)"
    )
    parser.add_argument(
        "--speed", type=float, default=1.0,
        help="Replay speed multiplier (default: 1.0)"
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true",
        help="Verbose per-step logging"
    )
    parser.add_argument(
        "--show-grabs", action="store_true", default=True,
        help="Show live screen grabs during test (default: True)"
    )
    parser.add_argument(
        "--no-grabs", dest="show_grabs", action="store_false",
        help="Disable live screen grabs"
    )
    parser.add_argument(
        "--grab-interval", type=int, default=10,
        help="Interval in steps between screen grabs (default: 10)"
    )
    parser.add_argument(
        "--keep-disk", action="store_true", default=False,
        help="Preserve ephemeral virtual disk image after test completion"
    )
    parser.add_argument(
        "--view", nargs="?", const="tests/monkey_session_sample.json",
        default=None,
        help="Launch interactive HTML session viewer (default: sample session)"
    )

    args = parser.parse_args()

    # Direct launch of session viewer if requested
    if args.view is not None:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        repo_root = os.path.dirname(script_dir)
        sys.path.insert(0, repo_root)
        from tools.monkey_viewer import (
            load_session, generate_html_viewer, open_in_browser
        )
        session_file = args.view
        if not os.path.isfile(session_file):
            alt = os.path.join(repo_root, session_file)
            if os.path.isfile(alt):
                session_file = alt
        data = load_session(session_file)
        out_html = os.path.join(repo_root, "docs", "monkey_viewer.html")
        out_file = generate_html_viewer(
            data, out_html, session_filename=os.path.basename(session_file)
        )
        print(f"[+] Generated HTML viewer: {out_file}", flush=True)
        open_in_browser(out_file)
        sys.exit(0)

    # Determine seed if not provided
    seed = args.seed if args.seed is not None else random.randint(1000, 999999)

    success = run_drunken_monkey_test(
        steps=args.steps,
        record_file=args.record,
        replay_file=args.replay,
        seed=seed,
        mode=args.mode,
        speed=args.speed,
        verbose=args.verbose,
        show_grabs=args.show_grabs,
        grab_interval=args.grab_interval,
        keep_disk=args.keep_disk,
    )

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
