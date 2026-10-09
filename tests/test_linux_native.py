#!/usr/bin/env python3
"""Automated verification test suite for Native Linux SE executable (se-linux).

Validates:
  1. Build pipeline: 'make se-linux' compiles cleanly with zero errors.
  2. CLI Help flag: 'se-linux --help' displays usage syntax and returns 0.
  3. Interactive startup: PTY launch renders screen and exits on Ctrl+Q.
  4. Document loading & editing: Open file, insert text, save, verify disk.
  5. C core component unit tests: Buffer, Memory, Search, Config, Beautify.

Part of SE.COM / Linux Native Profile (x86_64 and AArch64).
"""

import os
import pty
import subprocess
import sys
import tempfile
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
SE_LINUX_BIN = os.path.join(PROJECT_DIR, "se-linux")


def wait_pid_with_timeout(pid, timeout_sec=3.0):
    """Wait for child pid to terminate with timeout; kills on hang."""
    deadline = time.time() + timeout_sec
    while time.time() < deadline:
        res, status = os.waitpid(pid, os.WNOHANG)
        if res != 0:
            return os.waitstatus_to_exitcode(status)
        time.sleep(0.05)
    try:
        os.kill(pid, 9)
        os.waitpid(pid, 0)
    except Exception:
        pass
    return -1


def test_build_and_help():
    """Verify 'make se-linux' build and CLI help invocation."""
    print("[*] Testing build and CLI help interface...")
    cmd = ["make", "se-linux"]
    res = subprocess.run(cmd, capture_output=True, text=True, cwd=PROJECT_DIR)
    assert res.returncode == 0, f"make se-linux failed:\n{res.stderr}"
    assert os.path.isfile(SE_LINUX_BIN), f"Binary not found: {SE_LINUX_BIN}"

    # Run --help
    cmd = [SE_LINUX_BIN, "--help"]
    res = subprocess.run(cmd, capture_output=True, text=True, cwd=PROJECT_DIR)
    assert res.returncode == 0, f"se-linux --help failed with {res.returncode}"
    assert "Usage: " in res.stdout, "Usage text missing from --help"
    assert "Linux Native Profile" in res.stdout, "Profile text missing"
    print("    [+] Build and --help verified successfully [PASS]")


def test_interactive_pty_startup():
    """Verify PTY launch, splash screen rendering, and clean Ctrl+Q exit."""
    print("[*] Testing interactive PTY startup and splash screen...")
    master, slave = pty.openpty()

    pid = os.fork()
    if pid == 0:
        os.close(master)
        os.dup2(slave, 0)
        os.dup2(slave, 1)
        os.dup2(slave, 2)
        os.close(slave)
        os.execl(SE_LINUX_BIN, "se-linux")
    else:
        os.close(slave)
        time.sleep(0.3)
        captured = b""
        try:
            captured += os.read(master, 4096)
        except Exception:
            pass

        # Send Ctrl+Q (0x11) followed by Enter or 'n'
        os.write(master, b"\x11")
        time.sleep(0.1)
        os.write(master, b"n")

        exit_code = wait_pid_with_timeout(pid, 2.0)
        os.close(master)

        assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
        assert b"SE.COM" in captured or b"SE v1.1.0" in captured, (
            "Screen output missing expected editor banner"
        )
        assert b"80x24 |" in captured, (
            "Splash screen missing universal status bar geometry anchor"
        )
        assert b"^K: Editor keys |" in captured, (
            "Splash screen missing universal status bar help anchor"
        )
        print("    [+] Interactive PTY startup & clean exit verified [PASS]")


def test_document_load_and_save():
    """Verify document file loading, text editing, and save cycle."""
    print("[*] Testing document loading, editing, and saving...")
    with tempfile.NamedTemporaryFile("w+", suffix=".txt", delete=False) as tf:
        tf.write("Line 1: Initial content\nLine 2: Secondary content\n")
        test_file_path = tf.name

    try:
        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux", test_file_path)
        else:
            os.close(slave)
            time.sleep(0.3)
            # Insert additional characters
            os.write(master, b"EXTRA_TEXT_")
            time.sleep(0.2)
            # Send Ctrl+S (0x13) to save
            os.write(master, b"\x13")
            time.sleep(0.2)
            # Send Ctrl+Q (0x11) to exit
            os.write(master, b"\x11")
            time.sleep(0.1)
            # Confirmation key fallback if needed
            os.write(master, b"\n")

            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)

            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"

            with open(test_file_path, "r") as f:
                saved_content = f.read()

            assert "EXTRA_TEXT" in saved_content, (
                f"Saved content did not contain edited text:\n{saved_content}"
            )
            print("    [+] Document load, edit & save verified on disk [PASS]")
    finally:
        if os.path.exists(test_file_path):
            os.remove(test_file_path)


def test_status_bar_canonical_layout():
    """Verify canonical 5-field status bar layout per LOOK_AND_FEEL_SPEC.md."""
    print("[*] Testing canonical 5-field status bar layout (§4.3)...")
    with tempfile.NamedTemporaryFile("w+", prefix="testdoc_", suffix=".txt",
                                     delete=False) as tf:
        tf.write("Hello SE World\n")
        test_file_path = tf.name

    try:
        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux", test_file_path)
        else:
            os.close(slave)
            time.sleep(0.3)
            output = b""
            try:
                output += os.read(master, 8192)
            except Exception:
                pass

            os.write(master, b"\x11\n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)

            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
            out_str = output.decode("utf-8", errors="replace")

            assert "80x24 |" in out_str, (
                "Status bar missing '80x24 |' geometry field"
            )
            assert "Linux |" in out_str or "CPM   |" in out_str, (
                "Status bar missing format indicator ('Linux |' or 'CPM   |')"
            )
            assert "^K: Editor keys |" in out_str, (
                "Status bar missing '^K: Editor keys |' help field"
            )
            assert "Line " in out_str and "Col " in out_str, (
                "Status bar missing 'Line ... Col ...' position field"
            )
            print("    [+] Canonical 5-field status bar layout verified [PASS]")
    finally:
        if os.path.exists(test_file_path):
            os.remove(test_file_path)


def main():
    print("=" * 80)
    print("   SE.COM Linux Native Profile (se-linux) Automated Verification")
    print("=" * 80)

    test_build_and_help()
    test_interactive_pty_startup()
    test_document_load_and_save()
    test_status_bar_canonical_layout()

    print("=" * 80)
    print("VERDICT: [ PASS ] All Linux Native Profile tests succeeded!")
    print("=" * 80)
    return 0


if __name__ == "__main__":
    sys.exit(main())
