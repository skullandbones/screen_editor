#!/usr/bin/env python3
"""
tools/monkey_viewer.py - Interactive CLI Terminal Viewer for Drunken Monkey.

Provides an interactive console player to review recorded chaos sessions:
  - Step forward / backward through key sequences
  - Auto-play / pause with adjustable speed (0.5x, 1x, 2x, 4x, 8x)
  - Interactive scrubber and jump-to-step controls
  - Authentic VT100 terminal rendering with inverse status bar and box borders
  - Step metadata: Key hex/desc, screen state, time delay, quality status

Works in any standard terminal without external dependencies.
"""

import os
import sys
import time
import json
import select
import tty
import termios
import argparse


def load_session(filepath):
    """Loads recorded monkey session JSON."""
    if not os.path.isfile(filepath):
        print(f"[-] Session file not found: {filepath}", file=sys.stderr)
        sys.exit(1)
    with open(filepath, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data


class TerminalViewer:
    """
    Interactive full-screen CLI player for Drunken Monkey test recordings.
    """
    def __init__(self, session_data, filename="session.json"):
        self.metadata = session_data.get("metadata", {})
        self.events = session_data.get("events", [])
        self.total = len(self.events)
        self.filename = os.path.basename(filepath if "filepath" in locals()
                                         else filename)
        self.idx = 0
        self.playing = False
        self.speed = 1.0
        self.speeds = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
        self.speed_idx = 2  # 1.0x

        # Screen dimensions
        mode = self.metadata.get("screen_mode", "80x24")
        if mode == "120x40":
            self.cols = 120
            self.rows = 40
        else:
            self.cols = 80
            self.rows = 24

    def render_screen(self):
        """Builds the full terminal display string."""
        if not self.events:
            return "No recorded events in session.\n"

        ev = self.events[self.idx]
        step_num = ev.get("step", self.idx + 1)
        hex_code = ev.get("hex", "0x??")
        desc = ev.get("desc", "N/A")
        state = ev.get("state", "unknown")
        delay = ev.get("delay", 0.0)
        screen_lines = ev.get("screen", [])

        # Color codes
        c_reset = "\x1b[0m"
        c_bold = "\x1b[1m"
        c_dim = "\x1b[2m"
        c_cyan = "\x1b[36m"
        c_green = "\x1b[32m"
        c_yellow = "\x1b[33m"
        c_magenta = "\x1b[35m"
        c_inv = "\x1b[7m"

        out = []
        # Move cursor to home (top-left) without flicker
        out.append("\x1b[H")

        # 1. Header Banner
        w = max(self.cols, 80)
        title = " 🐒 SE.COM Drunken Monkey Session Player "
        # ┌─[ (3) + title (visual 41) + ] (1) + ─*bar_len + ┐ (1) = 82
        bar_len = max(0, w + 2 - (len(title) + 6))
        out.append(f"{c_bold}{c_cyan}┌─[{title}]{'─' * bar_len}┐{c_reset}\n")

        seed_val = self.metadata.get("seed", "N/A")
        meta_info = (
            f" File: {self.filename[:28]}  |  "
            f"Mode: {self.cols}x{self.rows}  |  "
            f"Seed: {seed_val}  |  "
            f"PASS"
        )
        pad_meta = max(0, w - len(meta_info))
        out.append(f"{c_cyan}│{c_reset}{meta_info}{' ' * pad_meta}"
                   f"{c_cyan}│{c_reset}\n")
        out.append(f"{c_bold}{c_cyan}└{'─' * w}┘{c_reset}\n")

        # 2. Step Information & Status Dashboard
        step_str = f"[{step_num:3d}/{self.total:3d}]"
        status_line = (
            f" {c_bold}Step:{c_reset} {c_magenta}{step_str}{c_reset}  "
            f"{c_bold}Key:{c_reset} {c_yellow}{hex_code}{c_reset} "
            f"({desc[:24]:<24})  "
            f"{c_bold}State:{c_reset} {c_cyan}{state:<18}{c_reset}  "
            f"{c_bold}Delay:{c_reset} {delay:.3f}s"
        )
        out.append(status_line + "\n")

        # 3. Scrubber Progress Bar
        bar_w = w - 18
        progress = int((self.idx + 1) / self.total * bar_w) if self.total else 0
        prog_bar = (
            f" [{c_green}{'=' * max(0, progress - 1)}"
            f"{'>' if progress > 0 else ''}{c_dim}"
            f"{'-' * max(0, bar_w - progress)}{c_reset}] "
            f"{int((self.idx + 1) / self.total * 100):3d}%"
        )
        out.append(prog_bar + "\n")

        # 4. VT100 Screen Display Box
        out.append(f"{c_dim}+{'-' * self.cols}+{c_reset}\n")
        for r_idx in range(self.rows):
            line = screen_lines[r_idx] if r_idx < len(screen_lines) else ""
            line = line.ljust(self.cols)[:self.cols]

            # Highlight status bar on bottom row with inverted video
            if r_idx == self.rows - 1 and ("| " in line or "^K:" in line):
                out.append(f"{c_dim}|{c_reset}{c_inv}{line}{c_reset}"
                           f"{c_dim}|{c_reset}\n")
            elif line.startswith("~"):
                # Dim tildes on empty lines
                out.append(f"{c_dim}|{c_reset}{c_dim}~{c_reset}"
                           f"{line[1:]}{c_dim}|{c_reset}\n")
            else:
                out.append(f"{c_dim}|{c_reset}{line}{c_dim}|{c_reset}\n")
        out.append(f"{c_dim}+{'-' * self.cols}+{c_reset}\n")

        # 5. Interactive Controls Footer
        status_play = (
            f"{c_green}▶ PLAYING ({self.speed}x){c_reset}"
            if self.playing else
            f"{c_yellow}⏸ PAUSED ({self.speed}x){c_reset}"
        )
        footer = (
            f" {status_play}  "
            f"{c_bold}[Space]{c_reset}: Play/Pause  "
            f"{c_bold}[→/l]{c_reset}: Next  "
            f"{c_bold}[←/h]{c_reset}: Prev  "
            f"{c_bold}[Home/0]{c_reset}: First  "
            f"{c_bold}[End/$]{c_reset}: Last  "
            f"{c_bold}[+/-]{c_reset}: Speed  "
            f"{c_bold}[1-9]{c_reset}: Scrub  "
            f"{c_bold}[q]{c_reset}: Quit"
        )
        out.append(footer + "\n")

        return "".join(out)

    def next_step(self):
        if self.idx < self.total - 1:
            self.idx += 1
            return True
        else:
            self.playing = False
            return False

    def prev_step(self):
        if self.idx > 0:
            self.idx -= 1
            return True
        return False

    def jump_percent(self, pct):
        self.idx = min(self.total - 1, max(0, int(self.total * pct)))

    def speed_up(self):
        if self.speed_idx < len(self.speeds) - 1:
            self.speed_idx += 1
            self.speed = self.speeds[self.speed_idx]

    def speed_down(self):
        if self.speed_idx > 0:
            self.speed_idx -= 1
            self.speed = self.speeds[self.speed_idx]

    def run_interactive(self):
        """Runs the interactive key event loop."""
        fd = sys.stdin.fileno()
        old_settings = termios.tcgetattr(fd)

        try:
            # Setup raw terminal mode
            tty.setraw(fd)
            # Switch to alternate screen and hide cursor
            sys.stdout.write("\x1b[?1049h\x1b[?25l\x1b[2J")
            sys.stdout.flush()

            last_tick = time.time()
            dirty = True

            while True:
                if dirty:
                    sys.stdout.write(self.render_screen())
                    sys.stdout.flush()
                    dirty = False

                # Calculate select timeout based on playback state
                if self.playing:
                    ev = self.events[self.idx]
                    base_delay = ev.get("delay", 0.05)
                    step_delay = max(0.015, base_delay / self.speed)
                    elapsed = time.time() - last_tick
                    timeout = max(0.0, step_delay - elapsed)
                else:
                    timeout = 0.1

                r, _, _ = select.select([fd], [], [], timeout)

                if r:
                    ch = os.read(fd, 32)
                    if not ch:
                        break

                    # Exit keys: q, Q, Ctrl+C, Ctrl+Z
                    if ch in (b"q", b"Q", b"\x03", b"\x1a"):
                        break
                    elif ch == b"\x1b":
                        # Standalone ESC pauses or exits
                        if self.playing:
                            self.playing = False
                            dirty = True
                        else:
                            break
                    elif ch.startswith(b"\x1b[") or ch.startswith(b"\x1bO"):
                        seq = ch[2:]
                        if seq in (b"C", b"OC"):  # Right arrow
                            self.playing = False
                            self.next_step()
                            dirty = True
                        elif seq in (b"D", b"OD"):  # Left arrow
                            self.playing = False
                            self.prev_step()
                            dirty = True
                        elif seq in (b"H", b"1~"):  # Home
                            self.playing = False
                            self.idx = 0
                            dirty = True
                        elif seq in (b"F", b"4~"):  # End
                            self.playing = False
                            self.idx = self.total - 1
                            dirty = True
                    elif ch in (b" ", b"k"):  # Space: toggle play/pause
                        self.playing = not self.playing
                        last_tick = time.time()
                        dirty = True
                    elif ch in (b"l", b"n", b"\r", b"\n"):  # Next step
                        self.playing = False
                        self.next_step()
                        dirty = True
                    elif ch in (b"h", b"p", b"\x7f", b"\x08"):  # Prev step
                        self.playing = False
                        self.prev_step()
                        dirty = True
                    elif ch in (b"0", b"g"):  # Start
                        self.playing = False
                        self.idx = 0
                        dirty = True
                    elif ch in (b"$", b"G"):  # End
                        self.playing = False
                        self.idx = self.total - 1
                        dirty = True
                    elif ch in (b"+", b"="):  # Speed up
                        self.speed_up()
                        dirty = True
                    elif ch in (b"-", b"_"):  # Slow down
                        self.speed_down()
                        dirty = True
                    elif ch >= b"1" and ch <= b"9":  # Number keys 1..9: Scrub
                        digit = int(ch.decode())
                        self.jump_percent((digit - 1) / 9.0)
                        dirty = True

                elif self.playing:
                    # Timer expired during playback: advance to next step
                    if self.next_step():
                        last_tick = time.time()
                    dirty = True

        finally:
            # Restore terminal screen and cursor
            sys.stdout.write("\x1b[?25h\x1b[?1049l")
            sys.stdout.flush()
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)


def dump_step(session_data, step_index, mode_override=None):
    """Dumps a single step to stdout (for non-interactive use)."""
    events = session_data.get("events", [])
    if not events:
        print("No events in session.")
        return

    idx = max(0, min(len(events) - 1, step_index - 1))
    ev = events[idx]
    screen = ev.get("screen", [])
    cols = 120 if "120" in str(session_data.get("metadata", {})) else 80

    print(f"=== [Step {ev.get('step', idx + 1)}/{len(events)}] "
          f"Key: {ev.get('hex')} ({ev.get('desc')}) | "
          f"State: {ev.get('state')} ===")
    print("+" + "-" * cols + "+")
    for line in screen:
        print("|" + line.ljust(cols)[:cols] + "|")
    print("+" + "-" * cols + "+")


def main():
    parser = argparse.ArgumentParser(
        description="Interactive CLI Viewer for Drunken Monkey Sessions"
    )
    parser.add_argument(
        "session", nargs="?",
        default="tests/monkey_session_sample.json",
        help="Path to session JSON (default: tests/monkey_session_sample.json)"
    )
    parser.add_argument(
        "--step", type=int, default=None,
        help="Dump specific step non-interactively and exit"
    )
    parser.add_argument(
        "--all", action="store_true",
        help="Dump all steps non-interactively and exit"
    )

    args = parser.parse_args()

    # Locate session file
    session_file = args.session
    if not os.path.isfile(session_file):
        # Look in tests/
        alt = os.path.join(os.path.dirname(__file__), "..", session_file)
        if os.path.isfile(alt):
            session_file = alt

    data = load_session(session_file)

    # Non-interactive modes
    if args.step is not None:
        dump_step(data, args.step)
        return

    if args.all or not sys.stdin.isatty():
        total = len(data.get("events", []))
        for s in range(1, total + 1):
            dump_step(data, s)
            print()
        return

    # Interactive terminal viewer
    viewer = TerminalViewer(data, filename=session_file)
    viewer.run_interactive()


if __name__ == "__main__":
    main()
