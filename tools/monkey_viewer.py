#!/usr/bin/env python3
"""
tools/monkey_viewer.py - Visual HTML & CLI Viewer for Drunken Monkey Sessions.

By default, generates and launches a rich, interactive HTML terminal player
in the user's default browser (via xdg-open / webbrowser). Also supports
an optional in-terminal TUI player (--cli) and non-interactive step dumps.
"""

import os
import sys
import time
import json
import shutil
import select
import tty
import termios
import argparse
import webbrowser
import socket
from http.server import SimpleHTTPRequestHandler, HTTPServer


def get_local_ip():
    """Attempts to determine the local network IP of this workstation."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("1.1.1.1", 80))
        ip = s.getsockname()[0]
    except Exception:
        ip = "127.0.0.1"
    finally:
        s.close()
    return ip


def serve_html_viewer(html_file, port=8000, launch_browser=True):
    """
    Serves the HTML viewer directory over local Wi-Fi for mobile phone access.
    """
    serve_dir = os.path.dirname(os.path.abspath(html_file))
    html_name = os.path.basename(html_file)
    local_ip = get_local_ip()

    class QuietHandler(SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=serve_dir, **kwargs)

        def log_message(self, fmt, *args):
            if len(args) >= 2 and str(args[1]) not in ("200", "304"):
                super().log_message(fmt, *args)

    try:
        server = HTTPServer(("0.0.0.0", port), QuietHandler)
    except OSError as err:
        print(f"[-] Failed to bind port {port}: {err}", file=sys.stderr)
        return

    url_lan = f"http://{local_ip}:{port}/{html_name}"
    url_local = f"http://localhost:{port}/{html_name}"

    print("=" * 76, flush=True)
    print("📱 Smartphone / Mobile Wi-Fi Server Running", flush=True)
    print("=" * 76, flush=True)
    print(f"[*] Local Workstation URL : {url_local}", flush=True)
    print(f"[+] Smartphone Wi-Fi URL  : {url_lan}", flush=True)
    print("", flush=True)
    print("  👉 On your phone (connected to same Wi-Fi), open the URL above.",
          flush=True)
    print("  💡 Tip: Rotate phone to landscape mode for full 80x24 view.",
          flush=True)
    print("  Press Ctrl+C to stop the server.", flush=True)
    print("=" * 76, flush=True)

    if launch_browser:
        open_in_browser(url_local)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] Stopping mobile web server...", flush=True)
    finally:
        server.server_close()


def load_session(filepath):
    """Loads recorded monkey session JSON."""
    if not os.path.isfile(filepath):
        print(f"[-] Session file not found: {filepath}", file=sys.stderr)
        sys.exit(1)
    with open(filepath, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data


def generate_html_viewer(session_data, output_path, session_filename=""):
    """
    Generates a standalone, rich HTML viewer for recorded monkey sessions.
    """
    script_dir = os.path.dirname(os.path.abspath(__file__))
    tpl_path = os.path.join(script_dir, "monkey_viewer_template.html")
    if not os.path.isfile(tpl_path):
        # Look in workspace
        alt = os.path.join(os.path.dirname(script_dir), "tools",
                           "monkey_viewer_template.html")
        if os.path.isfile(alt):
            tpl_path = alt

    with open(tpl_path, "r", encoding="utf-8") as f:
        template = f.read()

    session_data["filename"] = session_filename or "monkey_session.json"
    json_payload = json.dumps(session_data)

    html_content = template.replace(
        "/* __SESSION_DATA_JSON__ */ {}", json_payload
    )

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(html_content)
    return output_path


class TerminalViewer:
    """
    Fallback interactive full-screen CLI player for terminal environments.
    """
    def __init__(self, session_data, filename="session.json"):
        self.metadata = session_data.get("metadata", {})
        self.events = session_data.get("events", [])
        self.total = len(self.events)
        self.filename = os.path.basename(filename)
        self.idx = 0
        self.playing = False
        self.speed = 1.0
        self.speeds = [0.1, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
        self.speed_idx = 3  # 1.0x

        mode = self.metadata.get("screen_mode", "80x24")
        if mode == "120x40":
            self.cols = 120
            self.rows = 40
        else:
            self.cols = 80
            self.rows = 24

    def render_screen(self):
        if not self.events:
            return "No recorded events in session.\n"

        ev = self.events[self.idx]
        step_num = ev.get("step", self.idx + 1)
        hex_code = ev.get("hex", "0x??")
        desc = ev.get("desc", "N/A")
        state = ev.get("state", "unknown")
        delay = ev.get("delay", 0.0)
        screen_lines = ev.get("screen", [])

        c_reset = "\x1b[0m"
        c_bold = "\x1b[1m"
        c_dim = "\x1b[2m"
        c_cyan = "\x1b[36m"
        c_green = "\x1b[32m"
        c_yellow = "\x1b[33m"
        c_magenta = "\x1b[35m"
        c_inv = "\x1b[7m"

        out = ["\x1b[H"]
        w = max(self.cols, 80)
        title = " 🐒 SE.COM Drunken Monkey Session Player "
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

        step_str = f"[{step_num:3d}/{self.total:3d}]"
        status_line = (
            f" {c_bold}Step:{c_reset} {c_magenta}{step_str}{c_reset}  "
            f"{c_bold}Key:{c_reset} {c_yellow}{hex_code}{c_reset} "
            f"({desc[:24]:<24})  "
            f"{c_bold}State:{c_reset} {c_cyan}{state:<18}{c_reset}  "
            f"{c_bold}Delay:{c_reset} {delay:.3f}s"
        )
        out.append(status_line + "\n")

        bar_w = w - 18
        progress = int((self.idx + 1) / self.total * bar_w) if self.total else 0
        prog_bar = (
            f" [{c_green}{'=' * max(0, progress - 1)}"
            f"{'>' if progress > 0 else ''}{c_dim}"
            f"{'-' * max(0, bar_w - progress)}{c_reset}] "
            f"{int((self.idx + 1) / self.total * 100):3d}%"
        )
        out.append(prog_bar + "\n")

        out.append(f"{c_dim}+{'-' * self.cols}+{c_reset}\n")
        for r_idx in range(self.rows):
            line = screen_lines[r_idx] if r_idx < len(screen_lines) else ""
            line = line.ljust(self.cols)[:self.cols]

            if r_idx == self.rows - 1 and ("| " in line or "^K:" in line):
                out.append(f"{c_dim}|{c_reset}{c_inv}{line}{c_reset}"
                           f"{c_dim}|{c_reset}\n")
            elif line.startswith("~"):
                out.append(f"{c_dim}|{c_reset}{c_dim}~{c_reset}"
                           f"{line[1:]}{c_dim}|{c_reset}\n")
            else:
                out.append(f"{c_dim}|{c_reset}{line}{c_dim}|{c_reset}\n")
        out.append(f"{c_dim}+{'-' * self.cols}+{c_reset}\n")

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
        t_cols, t_rows = shutil.get_terminal_size()
        min_cols = self.cols + 4
        min_rows = self.rows + 9
        if t_cols < min_cols or t_rows < min_rows:
            print(
                f"[!] Notice: Your terminal size is {t_cols}x{t_rows}.\n"
                f"    For optimal text display, enlarge to at least "
                f"{min_cols}x{min_rows},\n"
                f"    or use the visual HTML viewer (default): "
                f"python3 tools/monkey_viewer.py\n",
                flush=True
            )
            time.sleep(1.5)

        fd = sys.stdin.fileno()
        old_settings = termios.tcgetattr(fd)

        try:
            tty.setraw(fd)
            sys.stdout.write("\x1b[?1049h\x1b[?25l\x1b[2J")
            sys.stdout.flush()

            last_tick = time.time()
            dirty = True

            while True:
                if dirty:
                    sys.stdout.write(self.render_screen())
                    sys.stdout.flush()
                    dirty = False

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
                        if self.playing:
                            self.playing = False
                            dirty = True
                        else:
                            break
                    elif ch.startswith(b"\x1b[") or ch.startswith(b"\x1bO"):
                        seq = ch[2:]
                        if seq in (b"C", b"OC"):
                            self.playing = False
                            self.next_step()
                            dirty = True
                        elif seq in (b"D", b"OD"):
                            self.playing = False
                            self.prev_step()
                            dirty = True
                        elif seq in (b"H", b"1~"):
                            self.playing = False
                            self.idx = 0
                            dirty = True
                        elif seq in (b"F", b"4~"):
                            self.playing = False
                            self.idx = self.total - 1
                            dirty = True
                    elif ch in (b" ", b"k"):
                        self.playing = not self.playing
                        last_tick = time.time()
                        dirty = True
                    elif ch in (b"l", b"n", b"\r", b"\n"):
                        self.playing = False
                        self.next_step()
                        dirty = True
                    elif ch in (b"h", b"p", b"\x7f", b"\x08"):
                        self.playing = False
                        self.prev_step()
                        dirty = True
                    elif ch in (b"0", b"g"):
                        self.playing = False
                        self.idx = 0
                        dirty = True
                    elif ch in (b"$", b"G"):
                        self.playing = False
                        self.idx = self.total - 1
                        dirty = True
                    elif ch in (b"+", b"="):
                        self.speed_up()
                        dirty = True
                    elif ch in (b"-", b"_"):
                        self.speed_down()
                        dirty = True
                    elif ch >= b"1" and ch <= b"9":
                        digit = int(ch.decode())
                        self.jump_percent((digit - 1) / 9.0)
                        dirty = True

                elif self.playing:
                    if self.next_step():
                        last_tick = time.time()
                    dirty = True

        finally:
            sys.stdout.write("\x1b[?25h\x1b[?1049l")
            sys.stdout.flush()
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)


def dump_step(session_data, step_index):
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


def open_in_browser(target):
    """Opens the generated HTML viewer or URL in the default browser."""
    if target.startswith("http://") or target.startswith("https://"):
        target_url = target
    else:
        abs_path = os.path.abspath(target)
        target_url = f"file://{abs_path}"

    print(f"[+] Launching default browser: {target_url}", flush=True)
    try:
        webbrowser.open(target_url)
    except Exception as exc:
        print(f"[!] Could not launch browser automatically: {exc}",
              flush=True)
        print(f"[*] Please open this URL manually:\n    {target_url}",
              flush=True)


def main():
    parser = argparse.ArgumentParser(
        description="Visual HTML & CLI Viewer for Drunken Monkey Sessions"
    )
    parser.add_argument(
        "session", nargs="?",
        default="tests/monkey_session_sample.json",
        help="Path to session JSON (default: tests/monkey_session_sample.json)"
    )
    parser.add_argument(
        "--output", "-o", type=str, default=None,
        help="Custom output path for generated HTML viewer"
    )
    parser.add_argument(
        "--no-browse", action="store_true",
        help="Generate HTML viewer without opening browser"
    )
    parser.add_argument(
        "--cli", action="store_true",
        help="Run in-terminal TUI player instead of HTML viewer"
    )
    parser.add_argument(
        "--step", type=int, default=None,
        help="Dump specific step non-interactively and exit"
    )
    parser.add_argument(
        "--all", action="store_true",
        help="Dump all steps non-interactively and exit"
    )
    parser.add_argument(
        "--serve", nargs="?", const=8000, type=int, default=None,
        metavar="PORT",
        help="Serve HTML viewer over Wi-Fi for mobile / phone access "
             "(default port: 8000)"
    )

    args = parser.parse_args()

    session_file = args.session
    if not os.path.isfile(session_file):
        alt = os.path.join(os.path.dirname(__file__), "..", session_file)
        if os.path.isfile(alt):
            session_file = alt

    data = load_session(session_file)

    # 1. Non-interactive step dump
    if args.step is not None:
        dump_step(data, args.step)
        return

    if args.all:
        total = len(data.get("events", []))
        for s in range(1, total + 1):
            dump_step(data, s)
            print()
        return

    # 2. In-terminal CLI TUI player if explicitly requested
    if args.cli:
        viewer = TerminalViewer(data, filename=session_file)
        viewer.run_interactive()
        return

    # 3. Default: Generate and launch HTML Viewer
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    default_html = os.path.join(repo_root, "docs", "monkey_viewer.html")
    html_target = args.output if args.output else default_html

    out_file = generate_html_viewer(
        data, html_target, session_filename=os.path.basename(session_file)
    )

    if args.serve is not None:
        serve_html_viewer(
            out_file, port=args.serve, launch_browser=not args.no_browse
        )
        return

    print("=" * 76, flush=True)
    print("🐒 SE.COM Drunken Monkey — Visual HTML Session Player", flush=True)
    print("=" * 76, flush=True)
    print(f"[+] Loaded session : {session_file}", flush=True)
    print(f"[+] Total steps    : {len(data.get('events', []))} events",
          flush=True)
    print(f"[+] HTML file      : {out_file}", flush=True)

    if not args.no_browse:
        open_in_browser(out_file)
    else:
        print(f"[*] To view: open file://{os.path.abspath(out_file)}",
              flush=True)
    print("=" * 76, flush=True)


if __name__ == "__main__":
    main()
