"""
Terminal management and ANSI VT100 console driver for SE editor.
Provides raw mode terminal I/O, escape sequence decoding, and styling.
"""

import atexit
import io
import os
import select
import signal
import sys
import termios
import tty

# Key Code Constants
KEY_CTRL_A = "\x01"
KEY_CTRL_B = "\x02"
KEY_CTRL_C = "\x03"
KEY_CTRL_D = "\x04"
KEY_CTRL_E = "\x05"
KEY_CTRL_F = "\x06"
KEY_CTRL_G = "\x07"
KEY_CTRL_H = "\x08"
KEY_CTRL_I = "\x09"
KEY_CTRL_J = "\x0a"
KEY_CTRL_K = "\x0b"
KEY_CTRL_L = "\x0c"
KEY_CTRL_M = "\x0d"
KEY_CTRL_N = "\x0e"
KEY_CTRL_O = "\x0f"
KEY_CTRL_P = "\x10"
KEY_CTRL_Q = "\x11"
KEY_CTRL_R = "\x12"
KEY_CTRL_S = "\x13"
KEY_CTRL_T = "\x14"
KEY_CTRL_U = "\x15"
KEY_CTRL_V = "\x16"
KEY_CTRL_W = "\x17"
KEY_CTRL_X = "\x18"
KEY_CTRL_Y = "\x19"
KEY_CTRL_Z = "\x1a"

KEY_ESC = "\x1b"
KEY_TAB = "\t"
KEY_ENTER = "\r"
KEY_BACKSPACE = "\x08"
KEY_DEL_CHAR = "\x7f"

# Symbolic Keys for Navigation
KEY_UP = "KEY_UP"
KEY_DOWN = "KEY_DOWN"
KEY_LEFT = "KEY_LEFT"
KEY_RIGHT = "KEY_RIGHT"
KEY_HOME = "KEY_HOME"
KEY_END = "KEY_END"
KEY_PGUP = "KEY_PGUP"
KEY_PGDN = "KEY_PGDN"
KEY_DELETE = "KEY_DELETE"

# VT100 ANSI Escape Sequences
ANSI_CLEAR_SCREEN = "\x1b[2J\x1b[H"
ANSI_CLEAR_EOL = "\x1b[K"
ANSI_HIDE_CURSOR = "\x1b[?25l"
ANSI_SHOW_CURSOR = "\x1b[?25h"
ANSI_INVERSE_ON = "\x1b[7m"
ANSI_INVERSE_OFF = "\x1b[0m"
ANSI_UNDERLINE_ON = "\x1b[4m"
ANSI_UNDERLINE_OFF = "\x1b[24m"

# Canonical Exit Banner
MSG_EXIT_HOST = "\r\nExiting SE. Returned to OS prompt.\r\n"


class Terminal:
    """
    Manages raw terminal state, cursor positioning, and key decoding.
    """

    def __init__(self, default_cols=80, default_rows=24):
        self.default_cols = default_cols
        self.default_rows = default_rows
        self.cols = default_cols
        self.rows = default_rows
        self.in_raw_mode = False
        self.old_termios = None
        self.resized = False
        self._setup_signals()

    def _setup_signals(self):
        """Install signal handlers for terminal resize and exit."""
        signal.signal(signal.SIGWINCH, self._handle_sigwinch)
        atexit.register(self.exit_raw_mode)

    def _handle_sigwinch(self, _signum, _frame):
        """Flag terminal resize event on SIGWINCH."""
        self.resized = True

    def update_geometry(self):
        """Query terminal dimensions and update active cols and rows."""
        try:
            sz = os.get_terminal_size(sys.stdin.fileno())
            if sz.columns > 0 and sz.lines > 0:
                self.cols = sz.columns
                self.rows = sz.lines
            else:
                self.cols = self.default_cols
                self.rows = self.default_rows
        except (AttributeError, OSError):
            self.cols = self.default_cols
            self.rows = self.default_rows
        self.resized = False
        return self.cols, self.rows

    def enter_raw_mode(self):
        """Place stdin into raw mode without echo or line buffering."""
        if self.in_raw_mode:
            return
        if not sys.stdin.isatty():
            return
        fd = sys.stdin.fileno()
        self.old_termios = termios.tcgetattr(fd)
        tty.setraw(fd)
        self.in_raw_mode = True
        self.update_geometry()

    def exit_raw_mode(self):
        """Restore previous terminal mode and ensure cursor is visible."""
        if not self.in_raw_mode:
            return
        self.show_cursor()
        self.inverse_off()
        self.flush()
        if self.old_termios and sys.stdin.isatty():
            termios.tcsetattr(
                sys.stdin.fileno(), termios.TCSADRAIN, self.old_termios
            )
        self.in_raw_mode = False

    def write(self, s):
        """Write string to stdout."""
        sys.stdout.write(s)

    def flush(self):
        """Flush stdout buffer immediately."""
        sys.stdout.flush()

    def locate(self, row, col):
        """
        Move terminal cursor to 1-based (row, col) coordinate.
        Clamps to valid screen bounds [1..rows, 1..cols].
        """
        r = max(1, min(self.rows, row))
        c = max(1, min(self.cols, col))
        self.write(f"\x1b[{r};{c}H")

    def hide_cursor(self):
        """Hide blinking terminal cursor."""
        self.write(ANSI_HIDE_CURSOR)

    def show_cursor(self):
        """Restore blinking terminal cursor."""
        self.write(ANSI_SHOW_CURSOR)

    def clear_screen(self):
        """Clear entire terminal surface and home cursor."""
        self.write(ANSI_CLEAR_SCREEN)

    def term_init(self):
        """
        Canonical terminal initialization (TERM_INIT):
        Resets rendition attributes (\x1b[0m), enables cursor visibility
        (\x1b[?25h), and clears the screen to home (\x1b[2J\x1b[H).
        """
        self.inverse_off()
        self.show_cursor()
        self.clear_screen()
        self.flush()

    def term_exit(self, msg: str = MSG_EXIT_HOST):
        """
        Canonical terminal session exit (EXIT_PROGRAM):
        Clears screen (\x1b[2J\x1b[H), emits exit banner, and restores cursor.
        """
        self.term_init()
        self.write(msg)
        self.show_cursor()
        self.flush()

    def clear_eol(self):
        """Clear from cursor to end of active row."""
        self.write(ANSI_CLEAR_EOL)

    def inverse_on(self):
        """Enable inverse video styling."""
        self.write(ANSI_INVERSE_ON)

    def inverse_off(self):
        """Reset video styling to normal."""
        self.write(ANSI_INVERSE_OFF)

    def underline_on(self):
        """Enable underline styling."""
        self.write(ANSI_UNDERLINE_ON)

    def underline_off(self):
        """Disable underline styling."""
        self.write(ANSI_UNDERLINE_OFF)

    def is_key_ready(self, timeout=0.0):
        """Check if characters are waiting to be read on stdin."""
        if hasattr(sys.stdin, "fileno"):
            try:
                fd = sys.stdin.fileno()
                r, _, _ = select.select([fd], [], [], timeout)
                return bool(r)
            except (io.UnsupportedOperation, OSError, AttributeError):
                return True
        return True

    def get_char(self, timeout=None):
        """Read a single raw character from stdin with optional timeout."""
        if hasattr(sys.stdin, "fileno"):
            try:
                fd = sys.stdin.fileno()
                if timeout is not None:
                    r, _, _ = select.select([fd], [], [], timeout)
                    if not r:
                        return None
                b = os.read(fd, 1)
                return b.decode("latin1", errors="replace") if b else None
            except (io.UnsupportedOperation, OSError, AttributeError):
                pass
        ch = sys.stdin.read(1)
        return ch if ch else None

    def get_key(self, timeout=None):
        """
        Read a keypress or decode multi-byte escape sequence.
        Returns a symbolic key, control character, or single printable char.
        """
        ch = self.get_char(timeout=timeout)
        if ch is None:
            return None

        # Handle ESC sequence decoding
        if ch == KEY_ESC:
            # Check if additional characters follow within short timeout
            if not self.is_key_ready(timeout=0.05):
                return KEY_ESC

            seq = self.get_char(timeout=0.05)
            if seq is None:
                return KEY_ESC

            # CSI sequence: ESC [ ...
            if seq == "[":
                c2 = self.get_char(timeout=0.05)
                if c2 is None:
                    return KEY_ESC
                if c2 == "A":
                    return KEY_UP
                if c2 == "B":
                    return KEY_DOWN
                if c2 == "C":
                    return KEY_RIGHT
                if c2 == "D":
                    return KEY_LEFT
                if c2 == "H":
                    return KEY_HOME
                if c2 == "F":
                    return KEY_END
                if c2 in ("1", "4", "5", "6", "3"):
                    # Check for trailing tilde '~'
                    c3 = self.get_char(timeout=0.05)
                    if c3 == "~":
                        if c2 == "1":
                            return KEY_HOME
                        if c2 == "4":
                            return KEY_END
                        if c2 == "5":
                            return KEY_PGUP
                        if c2 == "6":
                            return KEY_PGDN
                        if c2 == "3":
                            return KEY_DELETE
                    return KEY_ESC
                return KEY_ESC

            # SS3 sequence: ESC O ...
            if seq == "O":
                c2 = self.get_char(timeout=0.05)
                if c2 == "A":
                    return KEY_UP
                if c2 == "B":
                    return KEY_DOWN
                if c2 == "C":
                    return KEY_RIGHT
                if c2 == "D":
                    return KEY_LEFT
                if c2 == "H":
                    return KEY_HOME
                if c2 == "F":
                    return KEY_END
                return KEY_ESC

            # Two-key shortcuts: ESC < (Jump Top), ESC > (Jump Bottom)
            if seq in ("<", "t"):
                return "JUMP_TOP"
            if seq in (">", "b"):
                return "JUMP_BOTTOM"

            return KEY_ESC

        # Map DEL (0x7F) to KEY_DELETE per Section 10
        if ch == KEY_DEL_CHAR:
            return KEY_DELETE

        # Map Backspace (0x08)
        if ch == KEY_BACKSPACE:
            return KEY_BACKSPACE

        # Enter / Carriage Return
        if ch in ("\r", "\n"):
            return KEY_ENTER

        return ch
