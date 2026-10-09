"""
Headless integration test suite for native Python SE editor using PTY.
Validates PTY lifecycle, universal status bar, modals, and clean shutdown.
Conforms strictly to Rule 9 logging standards and <= 80 characters line length.
"""

import fcntl
import os
import pty
import select
import struct
import subprocess
import sys
import termios
import time
import unittest


def read_pty_until(fd: int, pattern: str, timeout: float = 3.0) -> str:
    """Read from PTY master fd until pattern is matched or timeout occurs."""
    start_time = time.time()
    accumulated = ""
    while time.time() - start_time < timeout:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try:
                chunk = os.read(fd, 1024).decode("utf-8", errors="replace")
                accumulated += chunk
                if pattern in accumulated:
                    return accumulated
            except OSError:
                break
    return accumulated


class TestEditorHeadless(unittest.TestCase):
    """Test suite executing SE editor inside a headless PTY environment."""

    def test_pty_lifecycle(self):
        """Execute full editor workflow inside pseudo-terminal."""
        suite_start = time.time()

        py_root = os.path.dirname(
            os.path.dirname(os.path.abspath(__file__))
        )
        se_bin = os.path.join(py_root, "bin", "se")

        master_fd, slave_fd = pty.openpty()

        # Set standard 80x24 terminal window geometry
        winsz = struct.pack("HHHH", 24, 80, 0, 0)
        fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, winsz)

        env = os.environ.copy()
        env["PYTHONPATH"] = py_root
        env["TERM"] = "vt100"
        env["COLUMNS"] = "80"
        env["LINES"] = "24"

        print("[*] Step 1: Booting SE editor under PTY...", flush=True)
        proc = subprocess.Popen(
            [sys.executable, se_bin],
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            close_fds=True,
            env=env,
        )
        os.close(slave_fd)

        try:
            # Step 1: Wait for status bar to render
            output = read_pty_until(master_fd, "(Untitled)", timeout=3.0)
            if "(Untitled)" not in output:
                print(
                    f"[-] Step 1: Failed to boot editor. Buffer: "
                    f"{repr(output[-300:])}",
                    flush=True,
                )
            self.assertIn("(Untitled)", output)
            print("[+] Step 1: Editor booted with status bar.", flush=True)

            # Step 2: Inject text
            print("[*] Step 2: Typing text into editor...", flush=True)
            os.write(master_fd, b"HELLO PYTHON SE\r\n")
            time.sleep(0.2)
            output = read_pty_until(master_fd, "HELLO PYTHON SE", timeout=2.0)
            self.assertIn("HELLO PYTHON SE", output)
            print("[+] Step 2: Text insertion verified.", flush=True)

            # Step 3: Trigger Splash screen via ESC
            print("[*] Step 3: Opening Splash screen via ESC...", flush=True)
            os.write(master_fd, b"\x1b")
            output = read_pty_until(
                master_fd, "Screen Editor", timeout=2.0
            )
            self.assertIn("Screen Editor", output)
            print("[+] Step 3: Splash screen workspace verified.", flush=True)

            # Return to editor from splash
            os.write(master_fd, b"e")
            time.sleep(0.2)

            # Step 4: Trigger Plugin Palette via Ctrl+P (\x10)
            print(
                "[*] Step 4: Opening Plugin Palette via Ctrl+P...",
                flush=True,
            )
            os.write(master_fd, b"\x10")
            output = read_pty_until(master_fd, "Plugin Palette", timeout=2.0)
            self.assertIn("Plugin Palette", output)

            # Dismiss Plugin Palette with ESC
            os.write(master_fd, b"\x1b")
            time.sleep(0.2)
            print("[+] Step 4: Plugin Palette modal verified.", flush=True)

            # Step 5: Quit via Ctrl+Q (\x11)
            print("[*] Step 5: Quitting editor via Ctrl+Q...", flush=True)
            os.write(master_fd, b"\x11")
            # Unsaved modifications prompt appears: answer 'n'
            output = read_pty_until(master_fd, "Save changes?", timeout=2.0)
            if "Save changes?" in output:
                os.write(master_fd, b"n")

            proc.wait(timeout=3.0)
            self.assertEqual(proc.returncode, 0)
            print("[+] Step 5: Editor cleanly exited with code 0.", flush=True)

        finally:
            os.close(master_fd)
            if proc.poll() is None:
                proc.kill()
                proc.wait()

        elapsed = time.time() - suite_start
        print(
            f"[+] All Headless PTY tests PASSED in {elapsed:.2f}s!",
            flush=True,
        )


if __name__ == "__main__":
    unittest.main()
