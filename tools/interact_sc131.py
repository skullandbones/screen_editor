#!/usr/bin/env python3
"""
interact_sc131.py - Live Interactive Session with SC131 CP/M box over Serial.
Connects to /dev/ttyUSB0 at 115200 bps with hardware flow control (RTS/CTS),
navigates the CP/M command line, runs SE.COM from drive J:, and demonstrates
interactive control of SE.COM (Splash, About, Memory, Plugins, Config, and Editor).
"""

import os
import sys
import time
import re
import serial


class VT100Screen:
    """Emulates a VT100 terminal display buffer for visual representation."""
    def __init__(self, cols=80, rows=24):
        self.cols = cols
        self.rows = rows
        self.reset()

    def reset(self, cols=None, rows=None):
        if cols: self.cols = cols
        if rows: self.rows = rows
        self.buffer = [[" " for _ in range(self.cols)] for _ in range(self.rows)]
        self.r = 0
        self.c = 0

    def feed(self, text):
        i = 0
        n = len(text)
        while i < n:
            ch = text[i]
            if ch == "\r":
                self.c = 0
                i += 1
            elif ch == "\n":
                if self.r < self.rows - 1:
                    self.r += 1
                i += 1
            elif ch == "\x1b":
                m = re.match(r"\x1b\[([0-9;]*)([A-Za-z])", text[i:])
                if m:
                    params_str, cmd = m.groups()
                    params = [int(p) for p in params_str.split(";") if p.isdigit()]
                    if cmd == "J":
                        # Clear screen
                        self.buffer = [[" " for _ in range(self.cols)] for _ in range(self.rows)]
                        self.r = 0
                        self.c = 0
                    elif cmd == "H":
                        row = (params[0] - 1) if len(params) > 0 and params[0] > 0 else 0
                        col = (params[1] - 1) if len(params) > 1 and params[1] > 0 else 0
                        # Auto-expand rows if needed
                        if row >= self.rows:
                            for _ in range(row - self.rows + 1):
                                self.buffer.append([" " for _ in range(self.cols)])
                            self.rows = row + 1
                        self.r = min(self.rows - 1, max(0, row))
                        self.c = min(self.cols - 1, max(0, col))
                    elif cmd == "K":
                        for c_idx in range(self.c, self.cols):
                            self.buffer[self.r][c_idx] = " "
                    elif cmd == "A":  # Cursor Up
                        dist = params[0] if params else 1
                        self.r = max(0, self.r - dist)
                    elif cmd == "B":  # Cursor Down
                        dist = params[0] if params else 1
                        self.r = min(self.rows - 1, self.r + dist)
                    elif cmd == "C":  # Cursor Right
                        dist = params[0] if params else 1
                        self.c = min(self.cols - 1, self.c + dist)
                    elif cmd == "D":  # Cursor Left
                        dist = params[0] if params else 1
                        self.c = max(0, self.c - dist)
                    i += len(m.group(0))
                else:
                    m2 = re.match(r"\x1b\[\?[0-9]+[hl]", text[i:])
                    if m2:
                        i += len(m2.group(0))
                    else:
                        i += 1
            else:
                if 0 <= self.r < self.rows and 0 <= self.c < self.cols:
                    self.buffer[self.r][self.c] = ch
                    self.c += 1
                i += 1

    def render(self, max_cols=80, max_rows=24):
        c_limit = min(self.cols, max_cols)
        r_limit = min(self.rows, max_rows)
        top = "+" + "-" * c_limit + "+"
        lines = [top]
        for row in range(r_limit):
            row_str = "".join(self.buffer[row][:c_limit])
            lines.append("|" + row_str + "|")
        lines.append(top)
        return "\n".join(lines)


class SC131Session:
    def __init__(self, port="/dev/ttyUSB0", baudrate=115200):
        self.port = port
        self.baudrate = baudrate
        self.ser = None
        self.screen = VT100Screen(cols=80, rows=24)

    def connect(self):
        print("=" * 80)
        print(f"[*] Opening serial port {self.port} at {self.baudrate} bps...")
        print("[*] Setting hardware flow control: rtscts=True (CRITICAL for SC131)")
        self.ser = serial.Serial(
            self.port,
            self.baudrate,
            timeout=0.5,
            rtscts=True,
            dsrdtr=False
        )
        self.ser.reset_input_buffer()
        self.ser.reset_output_buffer()
        print("[+] Serial port connected successfully!")
        print("=" * 80)
        sys.stdout.flush()

    def type_command(self, cmd_text, char_delay=0.08, end_char="\r"):
        print(f"\n>>> [You type]: ", end="", flush=True)
        for ch in cmd_text:
            sys.stdout.write(ch)
            sys.stdout.flush()
            self.ser.write(ch.encode("ascii"))
            time.sleep(char_delay)
        print(" <Enter>")
        self.ser.write(end_char.encode("ascii"))
        time.sleep(0.1)

    def type_keys(self, keys, desc=""):
        if desc:
            print(f"\n>>> [Action: {desc}] Typing: {repr(keys)}")
        else:
            print(f"\n>>> [You type]: {repr(keys)}")
        sys.stdout.flush()
        for k in keys:
            if isinstance(k, str):
                self.ser.write(k.encode("latin1"))
            elif isinstance(k, int):
                self.ser.write(bytes([k]))
            time.sleep(0.08)

    def send_escape_seq(self, seq, desc=""):
        if desc:
            print(f"\n>>> [Action: {desc}] Sending escape sequence: {repr(seq)}")
        else:
            print(f"\n>>> [Sending escape sequence]: {repr(seq)}")
        sys.stdout.flush()
        # Write whole escape sequence at once so Z80 timeout is never triggered
        self.ser.write(seq.encode("latin1"))
        time.sleep(0.1)

    def read_response(self, timeout=1.5, raw_echo=True):
        t0 = time.time()
        raw = b""
        while time.time() - t0 < timeout:
            if self.ser.in_waiting:
                chunk = self.ser.read(self.ser.in_waiting)
                raw += chunk
                t0 = time.time()  # reset timer on new data
            time.sleep(0.05)
        
        text = raw.decode("latin1", errors="replace")
        if raw_echo and text.strip():
            # Filter non-printable ANSI for console log output
            clean = re.sub(r"\x1b\[[0-9;]*[a-zA-Z]", "", text)
            clean = re.sub(r"\x1b\[\?[0-9]+[hl]", "", clean)
            lines = [l for l in clean.splitlines() if l.strip()]
            for l in lines:
                print(f"    [SC131]: {l}")
        self.screen.feed(text)
        sys.stdout.flush()
        return text

    def show_screen(self, title="", cols=80, rows=24):
        print(f"\n--- [SC131 VT100 Screen Display: {title}] ---")
        print(self.screen.render(max_cols=cols, max_rows=rows))
        print("-" * (cols + 2))
        sys.stdout.flush()

    def close(self):
        if self.ser and self.ser.is_open:
            self.ser.close()
            print("\n[+] Serial connection closed cleanly.")


def main():
    session = SC131Session("/dev/ttyUSB0", 115200)
    try:
        session.connect()

        # Step 1: Wake up CP/M console and ensure we are on J:
        print("\n[*] Pinging CP/M console...")
        session.ser.write(b"\r\n")
        time.sleep(0.3)
        session.read_response(timeout=1.0)

        # Switch to drive J:
        session.type_command("J:")
        session.read_response(timeout=1.0)

        # Step 2: Show directory on drive J:
        session.type_command("DIR")
        session.read_response(timeout=1.2)

        # Step 3: Run SE.COM
        session.type_command("SE")
        session.read_response(timeout=1.5, raw_echo=False)
        session.show_screen(title="SE.COM Initial Splash Screen (120x40)")

        # Step 4: Switch geometry to 80x24 (press '2')
        time.sleep(1.0)
        session.type_keys("2", desc="Set Geometry to 80x24 Standard")
        session.screen.reset(cols=80, rows=24)
        session.read_response(timeout=1.2, raw_echo=False)
        session.show_screen(title="SE.COM Splash Screen (80x24)")

        # Step 5: View About Screen ('a')
        time.sleep(1.0)
        session.type_keys("a", desc="Open About Screen")
        session.screen.reset(cols=80, rows=24)
        session.read_response(timeout=1.2, raw_echo=False)
        session.show_screen(title="SE.COM About Screen (v1.1.5)")


        # Return to Splash (Space)
        time.sleep(1.2)
        session.type_keys(" ", desc="Return to Splash Screen")
        session.screen.reset(cols=80, rows=24)
        session.read_response(timeout=1.0, raw_echo=False)

        # Step 6: View Memory Info Screen ('m')
        time.sleep(1.0)
        session.type_keys("m", desc="Open Memory & Bank Allocation Screen")
        session.screen.reset(cols=80, rows=24)
        session.read_response(timeout=1.2, raw_echo=False)
        session.show_screen(title="SE.COM Memory Map & Far RAM Allocation")

        # Return to Splash (Space)
        time.sleep(1.2)
        session.type_keys(" ", desc="Return to Splash Screen")
        session.screen.reset(cols=80, rows=24)
        session.read_response(timeout=1.0, raw_echo=False)

        # Step 7: View Plugin Manager ('p')
        time.sleep(1.0)
        session.type_keys("p", desc="Open Plugin Manager Screen")
        session.screen.reset(cols=80, rows=24)
        session.read_response(timeout=1.2, raw_echo=False)
        session.show_screen(title="SE.COM Plugin Manager (Far RAM & TPA Slots)")

        # Return to Splash ('q')
        time.sleep(1.2)
        session.type_keys("q", desc="Return to Splash Screen")
        session.screen.reset(cols=80, rows=24)
        session.read_response(timeout=1.0, raw_echo=False)

        # Step 8: View Configuration Screen ('c')
        time.sleep(1.0)
        session.type_keys("c", desc="Open Configuration Screen")
        session.screen.reset(cols=80, rows=24)
        session.read_response(timeout=1.2, raw_echo=False)
        session.show_screen(title="SE.COM Configuration Screen")

        # Cycle Beautify Columns ('5')
        time.sleep(1.0)
        session.type_keys("5", desc="Cycle Beautify Columns Preset")
        session.screen.reset(cols=80, rows=24)
        session.read_response(timeout=1.0, raw_echo=False)
        session.show_screen(title="Configuration Screen (Cycled Option 5)")

        # Return to Splash ('q')
        time.sleep(1.0)
        session.type_keys("q", desc="Return to Splash Screen")
        session.screen.reset(cols=80, rows=24)
        session.read_response(timeout=1.0, raw_echo=False)

        # Step 9: Enter Editor Mode ('e')
        time.sleep(1.0)
        session.type_keys("e", desc="Enter Full-Screen Editor Mode")
        session.screen.reset(cols=80, rows=24)
        session.read_response(timeout=1.2, raw_echo=False)
        session.show_screen(title="Editor Mode Initial Buffer")

        # Step 10: Type unformatted Z80 source code into editor
        print("\n[*] Typing unformatted assembly code lines into SE.COM editor...")
        code_lines = [
            "start: ld a,10 ; initial counter",
            "loop: inc a",
            " cp 20 ; check limit",
            " jr nz,loop ; repeat",
            " ret ; exit"
        ]
        for line in code_lines:
            session.type_keys(line + "\r", desc=f"Insert line: {line}")
            session.read_response(timeout=0.4, raw_echo=False)
            time.sleep(0.15)

        session.show_screen(title="Editor Screen with Unformatted Z80 Code")

        # Step 11: Execute Ctrl+Y (Plugin Execution)
        time.sleep(1.0)
        session.type_keys("\x19", desc="Press Ctrl+Y to run plugin")
        session.read_response(timeout=2.0, raw_echo=False)
        session.show_screen(title="Editor Screen: Plugin Modal Dialog")

        # Step 12: Dismiss modal dialog
        time.sleep(1.0)
        session.type_keys(" ", desc="Dismiss modal dialog (Press any key)")
        session.read_response(timeout=1.0, raw_echo=False)
        session.show_screen(title="Editor Screen Restored after Dialog")

        # Step 13: Move cursor up using Up Arrow sequences
        time.sleep(0.8)
        for _ in range(3):
            session.send_escape_seq("\x1b[A", desc="Cursor Up")
            session.read_response(timeout=0.3, raw_echo=False)
            time.sleep(0.15)
        session.show_screen(title="Editor Screen (Cursor Moved Up)")

        # Step 14: Show Editor Keybindings Help screen (^K)
        time.sleep(1.0)
        session.type_keys("\x0b", desc="Press Ctrl+K (Editor Help Screen)")
        session.read_response(timeout=1.5, raw_echo=False)
        session.show_screen(title="Editor Mode Help Screen (^K)")

        # Dismiss Help with Space
        time.sleep(1.2)
        session.type_keys(" ", desc="Press Space to return to editing")
        session.read_response(timeout=1.2, raw_echo=False)
        session.show_screen(title="Editor Screen Restored from Help")

        # Step 15: Exit SE.COM (^Q -> prompt 'Save changes? Yes/No/ESC:' -> 'n')
        time.sleep(1.0)
        session.type_keys("\x11", desc="Press Ctrl+Q to Exit")
        session.read_response(timeout=1.0, raw_echo=False)
        session.show_screen(title="Exit Prompt: Save changes? Yes/No/ESC:")

        time.sleep(0.8)
        session.type_keys("n", desc="Press 'n' to discard and return to CP/M")
        raw_exit = session.read_response(timeout=1.5, raw_echo=True)

        print("\n" + "=" * 80)
        print("[+] Session completed successfully! Returned to CP/M prompt on J: drive.")
        print("=" * 80)

    finally:
        session.close()


if __name__ == "__main__":
    main()
