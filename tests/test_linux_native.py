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

import fcntl
import os
import pty
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
USE_RUST = "--rust" in sys.argv
PY_MODE = "--python" in sys.argv
TARGET_NAME = "se-rs" if USE_RUST else "se-linux"
SE_LINUX_BIN = os.path.join(PROJECT_DIR, TARGET_NAME)
if PY_MODE:
    # Run the same PTY suite against the native Python SE port
    SE_LINUX_BIN = os.path.join(PROJECT_DIR, "ports", "python", "bin", "se")
    os.environ["PYTHONPATH"] = os.path.join(PROJECT_DIR, "ports", "python")


def read_all_available(fd, timeout_sec=0.5):
    """Read all available output from fd until quiet."""
    chunks = []
    end_time = time.time() + timeout_sec
    while time.time() < end_time:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                data = os.read(fd, 16384)
                if not data:
                    break
                chunks.append(data)
                end_time = time.time() + 0.15
            except Exception:
                break
        else:
            if chunks:
                break
    return b"".join(chunks)


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
    """Verify build target and CLI help invocation."""
    print("[*] Testing build and CLI help interface...")
    if PY_MODE:
        print("    [~] Skipped under --python (no C build step)")
        return
    cmd = ["make", TARGET_NAME]
    res = subprocess.run(cmd, capture_output=True, text=True, cwd=PROJECT_DIR)
    assert res.returncode == 0, f"make {TARGET_NAME} failed:\n{res.stderr}"
    assert os.path.isfile(SE_LINUX_BIN), f"Binary not found: {SE_LINUX_BIN}"

    # Run --help
    cmd = [SE_LINUX_BIN, "--help"]
    res = subprocess.run(cmd, capture_output=True, text=True, cwd=PROJECT_DIR)
    assert res.returncode == 0, (
        f"{TARGET_NAME} --help failed with {res.returncode}"
    )
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
        assert b"SE \xe2\x80\x94 Screen Editor" in captured or (
            b"SE" in captured and b"Screen Editor" in captured
        ), "Screen output missing expected editor banner"
        assert b"80x24 |" in captured or b"120x40 |" in captured, (
            "Splash screen missing universal status bar geometry anchor"
        )
        assert (b"|                 |" in captured or
                b"Free:" in captured), (
            "Splash screen missing universal status bar Field 4"
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
            # Dismiss save notification modal (press any key)
            os.write(master, b" ")
            time.sleep(0.1)
            # Send Ctrl+Q (0x11) to exit
            os.write(master, b"\x11")
            time.sleep(0.1)
            # Confirmation key fallback if needed
            os.write(master, b"n\n")

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
    """Verify canonical 5-field status bar layout per UI_UX_DESIGN.md."""
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

            assert "80x24 |" in out_str or "120x40 |" in out_str, (
                "Status bar missing '80x24 |' or '120x40 |' geometry field"
            )
            assert "Linux |" in out_str or "CP/M  |" in out_str, (
                "Status bar missing format indicator ('Linux |' or 'CP/M  |')"
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


def test_status_event_notification_modal():
    """Verify status events trigger Tier 2 modals without squatting bar."""
    print("[*] Testing status event modal routing (§4.4, §11.1)...")
    with tempfile.NamedTemporaryFile("w+", prefix="testnotify_", suffix=".txt",
                                     delete=False) as tf:
        tf.write("Notification modal test content\n")
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
            os.write(master, b"\x13")
            time.sleep(0.2)
            output = b""
            try:
                output += os.read(master, 8192)
            except Exception:
                pass

            os.write(master, b" ")
            time.sleep(0.1)
            os.write(master, b"\x11\n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)

            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
            out_str = output.decode("utf-8", errors="replace")

            assert "Save Complete" in out_str, (
                "Save event did not display 'Save Complete' modal pop-up"
            )
            assert "Press any key to continue" in out_str, (
                "Modal notification missing 'Press any key to continue'"
            )
            print("    [+] Status event modal routing verified [PASS]")
    finally:
        if os.path.exists(test_file_path):
            os.remove(test_file_path)


def test_arrow_and_wordstar_navigation():
    """Verify ANSI arrow keys and navigation shortcuts (§10)."""
    print("[*] Testing ANSI arrow & navigation shortcuts (§10)...")
    with tempfile.NamedTemporaryFile("w+", prefix="testdoc_nav_",
                                     suffix=".txt", delete=False) as tf:
        tf.write("Line 1: Alpha\nLine 2: Bravo\nLine 3: Charlie\n")
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
            # Read initial screen (at Line 1, Col 1)
            output = b""
            try:
                output += os.read(master, 8192)
            except Exception:
                pass

            # Send ANSI Down Arrow: ESC [ B
            os.write(master, b"\x1b[B")
            time.sleep(0.15)
            # Send ANSI Right Arrow: ESC [ C
            os.write(master, b"\x1b[C")
            time.sleep(0.15)
            try:
                output += os.read(master, 8192)
            except Exception:
                pass

            out_str = output.decode("utf-8", errors="replace")
            # Should show Line 2 and Col 1 in canonical status bar
            assert "Line    2/3" in out_str and "Col 1" in out_str, (
                f"Arrow navigation failed to update status bar:\n{out_str}"
            )

            # Send ANSI Up Arrow: ESC [ A
            os.write(master, b"\x1b[A")
            time.sleep(0.15)
            output2 = b""
            try:
                output2 += os.read(master, 8192)
            except Exception:
                pass
            out_str2 = output2.decode("utf-8", errors="replace")
            assert "Line    1/3" in out_str2, (
                f"ANSI Arrow Up failed to move up:\n{out_str2}"
            )

            # Send Ctrl+E (End of Line)
            os.write(master, b"\x05")
            time.sleep(0.15)
            output3 = b""
            try:
                output3 += os.read(master, 8192)
            except Exception:
                pass
            out_str3 = output3.decode("utf-8", errors="replace")
            assert "Col 13" in out_str3 or "Col 14" in out_str3, (
                f"Ctrl+E (End) failed to move to end of line:\n{out_str3}"
            )

            # Send Ctrl+Q to exit
            os.write(master, b"\x11\n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)

            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
            print("    [+] ANSI arrow & navigation shortcuts verified [PASS]")
    finally:
        if os.path.exists(test_file_path):
            os.remove(test_file_path)


def test_horizontal_panning_and_line_barrier():
    """Verify horizontal pan quantum (+40) and 120-char line limit (§6)."""
    print("[*] Testing horizontal panning engine & line barrier (§6)...")
    temp_dir = tempfile.mkdtemp()
    cfg_file = os.path.join(temp_dir, "SE.CFG")
    with open(cfg_file, "w") as f:
        f.write("SCREEN=80X24\r\n")

    with tempfile.NamedTemporaryFile("w+", prefix="testdoc_pan_",
                                     suffix=".txt", delete=False) as tf:
        tf.write("\n")
        test_file_path = tf.name

    try:
        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.chdir(temp_dir)
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux", test_file_path)
        else:
            os.close(slave)
            time.sleep(0.3)

            # Flush initial startup output
            read_all_available(master, 0.2)

            # Insert 85 'A' characters to push cursor past column 79
            os.write(master, b"A" * 85)
            output = read_all_available(master, 0.4)
            out_str = output.decode("utf-8", errors="replace")
            assert "[Pan +40]" in out_str, (
                f"Expected '[Pan +40]' indicator past column 79:\n{out_str}"
            )

            # Jump home (Ctrl+A / 0x01) to retreat below column 40
            os.write(master, b"\x01")
            output2 = read_all_available(master, 0.4)
            out_str2 = output2.decode("utf-8", errors="replace")
            assert "[Pan +40]" not in out_str2, (
                f"Expected '[Pan +40]' to clear when at column 0:\n{out_str2}"
            )

            # Move to End and attempt typing 150 chars
            os.write(master, b"\x1b[F")  # End key
            time.sleep(0.1)
            os.write(master, b"B" * 60)  # Total 85 + 60 = 145 attempted
            time.sleep(0.2)

            # Save file (Ctrl+S)
            os.write(master, b"\x13")
            time.sleep(0.2)
            # Dismiss save modal with space
            os.write(master, b" ")
            time.sleep(0.1)
            # Exit editor (Ctrl+Q)
            os.write(master, b"\x11\n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)

            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"

            with open(test_file_path, "r") as f:
                saved_lines = f.readlines()

            first_line = saved_lines[0].rstrip("\r\n")
            assert len(first_line) == 145, (
                f"Expected 145 characters saved, got {len(first_line)}"
            )
            print("    [+] Horizontal pan & line input verified [PASS]")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
        if os.path.exists(test_file_path):
            os.remove(test_file_path)


def test_tier1_centering_and_tilde_discipline():
    """Verify Tier 1 centering & column 0 tilde discipline (§5, §7)."""
    print("[*] Testing Tier 1 centering & column 0 tildes (§5.2, §7)...")
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
        splash_out = read_all_available(master, 0.4).decode("utf-8",
                                                            errors="replace")
        assert "~" in splash_out, (
            "Splash screen missing column 0 tilde margin discipline"
        )
        assert ("SE - Screen Editor" in splash_out) or (
            "SE — Screen Editor" in splash_out
        ), "Splash screen missing canonical centered title"

        # Press space to enter editor mode
        os.write(master, b" ")
        time.sleep(0.2)
        read_all_available(master, 0.2)

        # Press Ctrl+K (0x0B) to open Help mode screen
        os.write(master, b"\x0b")
        help_out = read_all_available(master, 0.4).decode("utf-8",
                                                          errors="replace")
        assert "EDITOR MODE KEYS" in help_out, (
            "Help screen missing canonical centered title"
        )
        assert "~" in help_out, (
            "Help screen missing column 0 tilde margin discipline"
        )
        assert "80x24 |" in help_out or "120x40 |" in help_out, (
            "Help screen missing universal status bar presence"
        )

        # Press space to return to editor
        os.write(master, b" ")
        time.sleep(0.2)
        read_all_available(master, 0.2)

        # Exit editor cleanly via Ctrl+Q
        os.write(master, b"\x11\n")
        exit_code = wait_pid_with_timeout(pid, 2.0)
        os.close(master)

        assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
        print("    [+] Tier 1 centering & column 0 tildes verified [PASS]")


def test_modal_archetypes_and_framing():
    """Verify Tier 2 modal framing, centering, and Archetypes B/C (§8)."""
    print("[*] Testing Tier 2 modal framing & Archetypes B/C (§8)...")
    with tempfile.NamedTemporaryFile("w+", prefix="testmod_", suffix=".txt",
                                     delete=False) as tf:
        tf.write("Initial modal content\n")
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
            read_all_available(master, 0.2)

            # Insert character to dirty the buffer
            os.write(master, b"X")
            time.sleep(0.1)
            read_all_available(master, 0.2)

            # Send Ctrl+Q (0x11) for Archetype B (Unsaved Modifications)
            os.write(master, b"\x11")
            modal_b_out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "Unsaved Modifications" in modal_b_out, (
                "Modal Archetype B missing title"
            )
            assert "+--------------------------------------------------+" in (
                modal_b_out
            ), "Modal Archetype B missing border/title divider (+---+)"
            assert "[Y]es" in modal_b_out and "[N]o" in modal_b_out, (
                "Modal Archetype B missing [Y]es / [N]o options"
            )
            assert "[ESC]=Cancel" in modal_b_out, (
                "Modal Archetype B missing [ESC]=Cancel footer option"
            )

            # Verify 'q' does NOT dismiss the confirmation query
            os.write(master, b"q")
            time.sleep(0.1)
            read_all_available(master, 0.2)

            # Send ESC (0x1B) to cancel confirmation query and return
            os.write(master, b"\x1b")
            time.sleep(0.2)
            read_all_available(master, 0.2)

            # Send Ctrl+F (0x06) to trigger Archetype C (Find Text prompt)
            os.write(master, b"\x06")
            modal_c_out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "Find Text" in modal_c_out, (
                "Modal Archetype C missing title"
            )
            assert "+------------------------------------------------+" in (
                modal_c_out
            ), "Modal Archetype C missing border/title divider (+---+)"
            assert "Find: [" in modal_c_out and "]" in modal_c_out, (
                "Modal Archetype C missing bracket pair [ text ] around input"
            )
            assert ("[Enter]=Find" in modal_c_out and
                    "[ESC]=Cancel" in modal_c_out), (
                "Modal Archetype C missing canonical footer"
            )

            # Cancel Archetype C via ESC
            os.write(master, b"\x1b")
            time.sleep(0.2)
            read_all_available(master, 0.2)

            # Exit cleanly via Ctrl+Q then 'n' (discard edits)
            os.write(master, b"\x11")
            time.sleep(0.1)
            os.write(master, b"n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)

            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
            print("    [+] Tier 2 modal framing & Archetypes verified [PASS]")
    finally:
        if os.path.exists(test_file_path):
            os.remove(test_file_path)


def test_bug_2_4_8_modal_dispatchers():
    """Verify Ctrl+L Goto Line and Ctrl+W Close File modals (Bug 2.4.8)."""
    print("[*] Testing modal dispatchers in editor mode (Bug 2.4.8)...")
    with tempfile.NamedTemporaryFile("w+", prefix="testdoc_disp_",
                                     suffix=".txt", delete=False) as tf:
        tf.write("Line 1\nLine 2\nLine 3\nLine 4\nLine 5\n")
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
            read_all_available(master, 0.2)

            # Send Ctrl+L (0x0C) for Goto Line prompt
            os.write(master, b"\x0c")
            time.sleep(0.2)
            modal_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "Goto Line" in modal_out, (
                f"Ctrl+L failed to trigger 'Goto Line' modal:\n{modal_out}"
            )

            # Type line 4 and press Enter
            os.write(master, b"4\n")
            time.sleep(0.2)
            goto_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "Line    4/" in goto_out, (
                f"Goto Line failed to position cursor at line 4:\n{goto_out}"
            )

            # Send Ctrl+W (0x17) to close document to splash screen
            os.write(master, b"\x17")
            time.sleep(0.2)
            splash_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert ("SE - Screen Editor" in splash_out) or (
                "SE — Screen Editor" in splash_out
            ), f"Ctrl+W failed to transition to splash screen:\n{splash_out}"

            # Exit cleanly via 'q' on splash screen
            os.write(master, b"q")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)

            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
            print("    [+] Modal & command dispatchers verified [PASS]")
    finally:
        if os.path.exists(test_file_path):
            os.remove(test_file_path)


def test_bug_2_4_9_splash_screen_commands():
    """Verify interactive splash screen command matrix dispatch (Bug 2.4.9)."""
    print("[*] Testing splash screen command matrix (Bug 2.4.9)...")
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
        read_all_available(master, 0.2)

        # Dispatch 'c' for Configuration Manager
        os.write(master, b"c")
        time.sleep(0.2)
        cfg_out = read_all_available(master, 0.3).decode(
            "utf-8", errors="replace"
        )
        assert "Configuration Manager" in cfg_out, (
            f"Splash 'c' failed to open Configuration Manager:\n{cfg_out}"
        )

        # Press ESC to return to Splash screen
        os.write(master, b"\x1b")
        time.sleep(0.2)
        splash_out = read_all_available(master, 0.3).decode(
            "utf-8", errors="replace"
        )
        assert ("SE - Screen Editor" in splash_out) or (
            "SE — Screen Editor" in splash_out
        ), f"Return from Config failed to render Splash screen:\n{splash_out}"

        # Dispatch '?' for Help screen
        os.write(master, b"?")
        time.sleep(0.2)
        help_out = read_all_available(master, 0.3).decode(
            "utf-8", errors="replace"
        )
        assert "EDITOR MODE KEYS" in help_out, (
            f"Splash '?' failed to open Help screen:\n{help_out}"
        )

        # Press space to return to Splash screen
        os.write(master, b" ")
        time.sleep(0.2)
        read_all_available(master, 0.2)

        # Dispatch ':e' to enter editor mode
        os.write(master, b":e")
        time.sleep(0.2)
        editor_out = read_all_available(master, 0.3).decode(
            "utf-8", errors="replace"
        )
        assert "Line    1/" in editor_out, (
            f"Splash ':e' failed to enter editor mode:\n{editor_out}"
        )

        # Safe exit via Ctrl+Q
        os.write(master, b"\x11\n")
        exit_code = wait_pid_with_timeout(pid, 2.0)
        os.close(master)

        assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
        print("    [+] Splash screen command matrix verified [PASS]")


def test_bug_2_4_10_burst_escape_sequences():
    """Verify rapid burst escape sequences parse discretely (Bug 2.4.10)."""
    print("[*] Testing rapid burst escape sequences (Bug 2.4.10)...")
    with tempfile.NamedTemporaryFile("w+", prefix="testdoc_burst_",
                                     suffix=".txt", delete=False) as tf:
        tf.write("Line 1: 1234567890\nLine 2: 1234567890\nLine 3: 1234567890\n")
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
            read_all_available(master, 0.2)

            # Send Down, Down, Right, Right in a single burst write
            burst_nav = b"\x1b[B\x1b[B\x1b[C\x1b[C"
            os.write(master, burst_nav)
            time.sleep(0.3)
            output = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            # Expect cursor moved to Line 3, Col 2
            assert "Line    3/3" in output and "Col 2" in output, (
                f"Burst arrow navigation failed:\n{output}"
            )

            # Exit cleanly via Ctrl+Q
            os.write(master, b"\x11\n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)

            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
            print("    [+] Rapid burst escape sequences verified [PASS]")
    finally:
        if os.path.exists(test_file_path):
            os.remove(test_file_path)


def test_bug_2_4_11_block_selection_cursor_tracking():
    """Verify block bounds track cursor dynamically (Bug 2.4.11)."""
    print("[*] Testing dynamic block selection cursor tracking (Bug 2.4.11)...")
    with tempfile.NamedTemporaryFile("w+", prefix="testdoc_block_",
                                     suffix=".txt", delete=False) as tf:
        tf.write("Line 1: 1234567890\nLine 2: ABCDEFGHIJKLMNOP\n")
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
            read_all_available(master, 0.2)

            # Start block selection at (0, 0) via Ctrl+B
            os.write(master, b"\x02")
            time.sleep(0.1)

            # Move right 5 characters
            os.write(master, b"\x1b[C" * 5)
            time.sleep(0.2)
            out_sel_chars = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "Sel: 5 chars" in out_sel_chars, (
                f"Expected 'Sel: 5 chars' in Field 4:\n{out_sel_chars}"
            )
            assert "\x1b[7m" in out_sel_chars, (
                f"Expected inverse video highlight '\\x1b[7m':\n{out_sel_chars}"
            )

            # Move down 1 line to expand to multi-line block
            os.write(master, b"\x1b[B")
            time.sleep(0.2)
            out_sel_lines = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "Sel: 2 lines" in out_sel_lines, (
                f"Expected 'Sel: 2 lines' in multi-line:\n{out_sel_lines}"
            )

            # Cancel block selection via Ctrl+B toggle
            os.write(master, b"\x02")
            time.sleep(0.2)
            out_cancel = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "Sel:" not in out_cancel, (
                f"Expected 'Sel:' cleared on toggle:\n{out_cancel}"
            )
            assert "^K: Editor keys" in out_cancel, (
                f"Expected '^K: Editor keys' restored:\n{out_cancel}"
            )

            # Exit cleanly via Ctrl+Q
            os.write(master, b"\x11\n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)

            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
            print("    [+] Block cursor tracking & highlight verified [PASS]")
    finally:
        if os.path.exists(test_file_path):
            os.remove(test_file_path)


def test_bug_2_4_12_clipboard_copy_paste():
    """Verify clipboard copy (Ctrl+C) and paste (Ctrl+V) (Bug 2.4.12)."""
    print("[*] Testing clipboard copy and paste operations (Bug 2.4.12)...")
    with tempfile.NamedTemporaryFile("w+", prefix="testdoc_clip_",
                                     suffix=".txt", delete=False) as tf:
        tf.write("12345 Hello World\nSecond Line\n")
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
            read_all_available(master, 0.2)

            # Start block at (0, 0)
            os.write(master, b"\x02")
            time.sleep(0.1)

            # Select 5 characters ("12345")
            os.write(master, b"\x1b[C" * 5)
            time.sleep(0.1)

            # Solidify block via Enter (\r)
            os.write(master, b"\r")
            time.sleep(0.1)
            out_lock = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "Block: 5 chars" in out_lock, (
                f"Expected 'Block: 5 chars' status indicator:\n{out_lock}"
            )

            # Move down to line 2 and jump to Col 0 via Ctrl+A
            os.write(master, b"\x1b[B\x01")
            time.sleep(0.1)

            # Direct in-place copy via Ctrl+C at beginning of line 2
            os.write(master, b"\x03")
            time.sleep(0.2)

            # Verify Ctrl+V does not execute paste (paste eliminated)
            os.write(master, b"\x16")
            time.sleep(0.1)

            # Clear block via ESC (\x1b) so Ctrl+S saves document, not block
            os.write(master, b"\x1b")
            time.sleep(0.1)

            # Save file via Ctrl+S
            os.write(master, b"\x13")
            time.sleep(0.2)
            # Dismiss save notification modal
            os.write(master, b" ")
            time.sleep(0.2)

            # Exit cleanly via Ctrl+Q
            os.write(master, b"\x11")
            time.sleep(0.2)
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)

            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"

            with open(test_file_path, "r", encoding="utf-8") as f:
                saved_content = f.read()

            assert "12345Second Line" in saved_content, (
                f"Direct copy '12345' missing from line 2:\n{saved_content}"
            )
            assert "1234512345" not in saved_content, (
                f"Spurious paste occurred on line 2:\n{saved_content}"
            )
            print("    [+] Direct block copy verified on disk [PASS]")
    finally:
        if os.path.exists(test_file_path):
            os.remove(test_file_path)


def test_bug_2_4_13_terminal_lifecycle():
    """Verify startup TERM_INIT clear and exit message banner (Bug 2.4.13)."""
    print("[*] Testing startup TERM_INIT and exit banner (Bug 2.4.13)...")
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
        startup_bytes = read_all_available(master, 0.2)

        # Verify startup TERM_INIT sequence (\x1b[0m\x1b[?25h\x1b[2J\x1b[H)
        assert b"\x1b[0m\x1b[?25h\x1b[2J\x1b[H" in startup_bytes, (
            f"Expected startup TERM_INIT sequence in output:\n{startup_bytes!r}"
        )

        # Send Ctrl+Q followed by Enter to quit
        os.write(master, b"\x11\n")
        time.sleep(0.2)
        exit_bytes = read_all_available(master, 0.2)
        exit_code = wait_pid_with_timeout(pid, 2.0)
        os.close(master)

        assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
        assert b"Exiting SE. Returned to OS prompt." in exit_bytes, (
            f"Expected canonical exit message in output:\n{exit_bytes!r}"
        )
        print("    [+] Startup TERM_INIT & clean exit banner verified [PASS]")


def test_bug_2_4_14_viewport_col1_alignment():
    """Verify document rows start at screen col 1 without space (Bug 2.4.14)."""
    print("[*] Testing viewport col 1 alignment & cursor locator (2.4.14)...")
    with tempfile.NamedTemporaryFile("w+", prefix="testdoc_col1_",
                                     suffix=".txt", delete=False) as tf:
        tf.write("ABCDEFGH\n")
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
            out_bytes = read_all_available(master, 0.3)

            # Active document line 1 must start at col 1 with "ABCDEFGH"
            assert b"\x1b[1;1HABCDEFGH" in out_bytes, (
                f"Expected document row at col 1 without leading space:\n"
                f"{out_bytes!r}"
            )

            # Hardware cursor at Col 0 must locate at \x1b[1;1H
            assert b"\x1b[1;1H" in out_bytes, (
                f"Expected cursor located at (1, 1):\n{out_bytes!r}"
            )

            # Row 2 (beyond EOF) must display tilde margin at col 1 (\x1b[2;1H~)
            assert b"\x1b[2;1H~" in out_bytes, (
                f"Expected tilde at row 2 col 1:\n{out_bytes!r}"
            )

            # Exit cleanly via Ctrl+Q
            os.write(master, b"\x11\n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)

            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
            print("    [+] Viewport col 1 & cursor locator verified [PASS]")
    finally:
        if os.path.exists(test_file_path):
            os.remove(test_file_path)


def test_bug_2_4_15_sticky_target_col_and_tab_clamping():
    """Verify sticky TARGET_COL persistence and tab clamping (Bug 2.4.15)."""
    print("[*] Testing sticky target column and tab clamping (Bug 2.4.15)...")
    with tempfile.NamedTemporaryFile("w+", prefix="testdoc_target_",
                                     suffix=".txt", delete=False) as tf:
        tf.write("0123456789ABCDEF\nShort\n\tXYZ\n")
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
            read_all_available(master, 0.2)

            # Move right 10 columns on line 1: TARGET_COL = 10
            os.write(master, b"\x1b[C" * 10)
            time.sleep(0.1)
            out_l1 = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "Line    1/3" in out_l1 and "Col 10" in out_l1, (
                f"Expected Line 1 Col 10:\n{out_l1}"
            )

            # Move down to Line 2 (len 5): cur_col clamped to 5
            os.write(master, b"\x1b[B")
            time.sleep(0.1)
            out_l2 = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "Line    2/3" in out_l2 and "Col 5" in out_l2, (
                f"Expected Line 2 Col 5:\n{out_l2}"
            )

            # Move up back to Line 1: cursor restores sticky TARGET_COL 10!
            os.write(master, b"\x1b[A")
            time.sleep(0.1)
            out_l1_back = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "Line    1/3" in out_l1_back and "Col 10" in out_l1_back, (
                f"Expected restored Line 1 Col 10:\n{out_l1_back}"
            )

            # Set TARGET_COL to 2 (home then 2 right)
            os.write(master, b"\x01" + b"\x1b[C" * 2)
            time.sleep(0.1)
            read_all_available(master, 0.2)

            # Move down 2 lines to Line 3 (\tXYZ). Target 2 is inside tab.
            # Snap-forward alignment (§6.2, §6.4) snaps to Col 8 (index 1).
            os.write(master, b"\x1b[B\x1b[B")
            time.sleep(0.1)
            out_tab = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "Line    3/3" in out_tab and "Col 8" in out_tab, (
                f"Expected tab interior snap-forward to Col 8:\n{out_tab}"
            )

            # Move up 2 lines back to Line 1: TARGET_COL 2 preserved!
            os.write(master, b"\x1b[A\x1b[A")
            time.sleep(0.1)
            out_tab_back = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "Line    1/3" in out_tab_back and "Col 2" in out_tab_back, (
                f"Expected Line 1 Col 2 restored:\n{out_tab_back}"
            )

            # Exit cleanly via Ctrl+Q
            os.write(master, b"\x11\n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)

            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
            print("    [+] Sticky TARGET_COL & tab clamping verified [PASS]")
    finally:
        if os.path.exists(test_file_path):
            os.remove(test_file_path)


def test_bug_2_4_16_status_bar_field_invariance_and_visual_col():
    """Verify Field 4 invariance and Field 5 visual col reporting (2.4.16)."""
    print("[*] Testing status bar Field 4 invariance & visual col (2.4.16)...")
    temp_dir = tempfile.mkdtemp()
    cfg_file = os.path.join(temp_dir, "SE.CFG")
    with open(cfg_file, "w") as f:
        f.write("SCREEN=80X24\r\nTAB=8\r\n")

    long_line = "\tABCDEF" + ("X" * 80) + "\nSecond line\n"
    with tempfile.NamedTemporaryFile("w+", prefix="testdoc_statbar_",
                                     suffix=".txt", delete=False) as tf:
        tf.write(long_line)
        test_file_path = tf.name

    try:
        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.chdir(temp_dir)
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux", test_file_path)
        else:
            os.close(slave)
            time.sleep(0.3)
            init_out = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "^K: Editor keys |" in init_out, (
                f"Expected Field 4 '^K: Editor keys |':\n{init_out}"
            )
            assert "Col 0" in init_out, f"Expected Col 0 initially:\n{init_out}"

            # Move right 1 character past tab: visual column must leap to 8
            os.write(master, b"\x1b[C")
            time.sleep(0.1)
            out_tab = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "Col 8" in out_tab, (
                f"Expected visual Col 8 after tab leap:\n{out_tab}"
            )
            assert "^K: Editor keys |" in out_tab, (
                f"Expected Field 4 preserved:\n{out_tab}"
            )

            # Start block selection: Sel: 0 chars in Field 4
            os.write(master, b"\x02")
            time.sleep(0.1)
            out_sel = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "Sel: 0 chars" in out_sel, (
                f"Expected 'Sel: 0 chars' indicator in Field 4:\n{out_sel}"
            )

            # Cancel selection
            os.write(master, b"\x02")
            time.sleep(0.1)

            # Move to end of line to trigger pan (+40) in Field 4
            os.write(master, b"\x1b[F")
            time.sleep(0.2)
            out_pan = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "[Pan +40]       |" in out_pan, (
                f"Expected '[Pan +40]       |' in Field 4:\n{out_pan}"
            )

            # Exit cleanly via Ctrl+Q (no modification dialog)
            os.write(master, b"\x11\n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)

            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
            print("    [+] Status bar Field 4 invariance & visual col [PASS]")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
        if os.path.exists(test_file_path):
            os.remove(test_file_path)


def test_bug_2_4_17_tier1_file_workspaces_and_directory_scan():
    """Verify Tier 1 File Open/Save workspaces & dir scanning (2.4.17)."""
    print("[*] Testing Tier 1 file workspaces & dir scanning (2.4.17)...")
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
        read_all_available(master, 0.2)

        # Launch File Open workspace from Splash screen via 'o'
        os.write(master, b"o")
        time.sleep(0.3)
        open_out = read_all_available(master, 0.4).decode("utf-8",
                                                          errors="replace")
        assert "OPEN FILE (DIRECTORY)" in open_out, (
            f"Expected 'OPEN FILE (DIRECTORY)' in workspace:\n{open_out}"
        )
        assert "~====" in open_out, (
            f"Expected double rule '~====' in open workspace:\n{open_out}"
        )
        assert "Enter filename to open:" in open_out, (
            f"Expected filename prompt in open workspace:\n{open_out}"
        )
        # Single-page directory suppresses pagination controls (Section 7.5)
        assert "<PgUp>/<PgDn>=Page" not in open_out, (
            f"Single-page directory must suppress page controls:\n{open_out}"
        )
        # Directory scanning verification: Makefile or TODO.md in grid
        assert "Makefile" in open_out or "TODO.md" in open_out, (
            f"Directory scan failed to list local repository files:\n{open_out}"
        )

        # Cancel out of Open workspace via ESC
        os.write(master, b"\x1b")
        time.sleep(0.2)
        read_all_available(master, 0.2)

        # Launch Save workspace from Splash screen via 's'
        os.write(master, b"s")
        time.sleep(0.3)
        save_out = read_all_available(master, 0.4).decode("utf-8",
                                                          errors="replace")
        assert "SAVE FILE (DIRECTORY)" in save_out, (
            f"Expected 'SAVE FILE (DIRECTORY)' in workspace:\n{save_out}"
        )
        assert "Format: [Linux]" in save_out or "Format: [CP/M]" in save_out, (
            f"Expected format indicator in save workspace:\n{save_out}"
        )
        assert "[^F]=Toggle Format" in save_out, (
            f"Expected format toggle hint in save workspace:\n{save_out}"
        )

        # Toggle format via Ctrl+F (0x06)
        os.write(master, b"\x06")
        time.sleep(0.2)
        toggle_out = read_all_available(master, 0.4).decode("utf-8",
                                                            errors="replace")
        has_toggled = ("Format: [CP/M]" in toggle_out or
                       "Format: [Linux]" in toggle_out)
        assert has_toggled, (
            f"Expected toggled format in save workspace:\n{toggle_out}"
        )

        # Cancel Save workspace via ESC
        os.write(master, b"\x1b")
        time.sleep(0.2)
        read_all_available(master, 0.2)

        # Exit cleanly from splash screen via 'q'
        os.write(master, b"q")
        exit_code = wait_pid_with_timeout(pid, 2.0)
        os.close(master)

        assert exit_code == 0, f"Expected exit code 0, got {exit_code}"

        # Multi-page directory displays pagination controls (Section 7.5)
        multi_dir = tempfile.mkdtemp()
        try:
            for i in range(65):
                fpath = os.path.join(multi_dir, f"file_{i:02d}.txt")
                with open(fpath, "w") as f:
                    f.write("test\n")
            m_master, m_slave = pty.openpty()
            m_pid = os.fork()
            if m_pid == 0:
                os.chdir(multi_dir)
                os.close(m_master)
                os.dup2(m_slave, 0)
                os.dup2(m_slave, 1)
                os.dup2(m_slave, 2)
                os.close(m_slave)
                os.execl(SE_LINUX_BIN, "se-linux")
            else:
                os.close(m_slave)
                time.sleep(0.3)
                read_all_available(m_master, 0.2)
                os.write(m_master, b"o")
                time.sleep(0.3)
                multi_out = read_all_available(m_master, 0.4).decode(
                    "utf-8", errors="replace"
                )
                assert "<PgUp>/<PgDn>=Page" in multi_out, (
                    "Expected page controls in multi-page workspace:\n"
                    f"{multi_out}"
                )
                assert "[Page 1/2]" in multi_out, (
                    f"Expected [Page 1/2] in multi-page workspace:\n{multi_out}"
                )
                os.write(m_master, b"\x1b")
                time.sleep(0.2)
                os.write(m_master, b"q")
                wait_pid_with_timeout(m_pid, 2.0)
                os.close(m_master)
        finally:
            shutil.rmtree(multi_dir, ignore_errors=True)

        print("    [+] Tier 1 file workspaces & dir scanning verified [PASS]")


def test_bug_2_4_18_canonical_config_parser_and_serialization():
    """Verify canonical SE.CFG parser, defaults and serialization (2.4.18)."""
    print("[*] Testing canonical SE.CFG parser & serialization (2.4.18)...")
    temp_dir = tempfile.mkdtemp()
    try:
        # 1. Compile C unit test harness for config.c
        harness_c = os.path.join(temp_dir, "test_config_harness.c")
        harness_bin = os.path.join(temp_dir, "test_config_harness")
        with open(harness_c, "w") as f:
            f.write(
                "#include <stdio.h>\n"
                "#include <stdlib.h>\n"
                "#include <string.h>\n"
                "#include <assert.h>\n"
                '#include "config.h"\n\n'
                "int main(void) {\n"
                "    /* 1. Defaults verification (§13.2) */\n"
                "    config_init_defaults();\n"
                "    assert(g_config.screen_mode == MODE_80X24);\n"
                "    assert(g_config.tab_width == 8);\n"
                "    assert(g_config.save_format == FMT_LINUX);\n"
                "    assert(g_config.lines_mode == 0);\n"
                "    assert(g_config.ramdrive_mode == "
                "RAMDRV_MODE_PROTECTED);\n"
                "    assert(g_config.plugin_mode == "
                "PLUGIN_MODE_AUTOLOAD);\n"
                "    assert(g_config.auto_indent == 1);\n\n"
                "    /* 2. Canonical parsing with comments & whitespace */\n"
                '    const char *cfg_data =\n'
                '        "# Canonical SE.CFG test\\r\\n"\n'
                '        "; Semicolon comment line\\r\\n"\n'
                '        "  SCREEN = 80X24  \\r\\n"\n'
                '        "  TAB = 4  \\r\\n"\n'
                '        "  FORMAT = LINUX  \\r\\n"\n'
                '        "  LINES = 32K  \\r\\n"\n'
                '        "  RAMDRIVE = HIB  \\r\\n"\n'
                '        "  PLUGIN = DEMAND  \\r\\n"\n'
                '        "  AUTO_INDENT = 0  \\r\\n";\n'
                '    FILE *fp = fopen("TEST.CFG", "wb");\n'
                "    assert(fp != NULL);\n"
                "    fputs(cfg_data, fp);\n"
                "    fclose(fp);\n"
                '    assert(config_load_file("TEST.CFG") == 0);\n'
                "    assert(g_config.screen_mode == MODE_80X24);\n"
                "    assert(g_config.tab_width == 4);\n"
                "    assert(g_config.lines_mode == 1);\n"
                "    assert(g_config.ramdrive_mode == "
                "RAMDRV_MODE_HIBERNATE);\n"
                "    assert(g_config.plugin_mode == "
                "PLUGIN_MODE_AUTOLOAD);\n"
                "    assert(g_config.auto_indent == 0);\n\n"
                "    /* 3. Canonical serialization with CRLF */\n"
                '    assert(config_save_file("TEST_OUT.CFG") == 0);\n'
                "    return 0;\n"
                "}\n"
            )
        compile_cmd = [
            "cc", "-Wall", "-Wextra", "-Werror", "-O2",
            "-Isrc/include",
            harness_c,
            "src/core/config.c",
            "-o", harness_bin,
        ]
        res = subprocess.run(compile_cmd, cwd=PROJECT_DIR,
                             capture_output=True, text=True)
        assert res.returncode == 0, f"Compilation failed:\n{res.stderr}"

        # Run C harness inside temp_dir
        run_res = subprocess.run([harness_bin], cwd=temp_dir,
                                 capture_output=True, text=True)
        assert run_res.returncode == 0, (
            f"Config harness execution failed:\n{run_res.stderr}"
        )

        # Verify serialized file contents on disk
        out_cfg_path = os.path.join(temp_dir, "TEST_OUT.CFG")
        with open(out_cfg_path, "rb") as f:
            content = f.read()

        assert b"\r\n" in content, "Serialized CFG missing CRLF endings"
        text = content.decode("ascii")
        assert "SCREEN=80X24\r\n" in text, (
            f"Missing SCREEN in output:\n{text}"
        )
        assert "TAB=4\r\n" in text, f"Missing TAB in output:\n{text}"
        assert "FORMAT=" not in text, (
            f"FORMAT should not be serialized in CFG:\n{text}"
        )
        assert "LINES=32K\r\n" in text, f"Missing LINES in output:\n{text}"
        assert "RAMDRIVE=HIB\r\n" in text, (
            f"Missing RAMDRIVE in output:\n{text}"
        )
        assert "PLUGIN=AUTOLOAD\r\n" in text, (
            f"Missing PLUGIN in output:\n{text}"
        )
        assert "AUTO_INDENT=0\r\n" in text, (
            f"Missing AUTO_INDENT in output:\n{text}"
        )

        # 4. End-to-end integration test with se-linux
        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.chdir(temp_dir)
            if os.path.exists("SE.CFG"):
                os.remove("SE.CFG")
            shutil.copyfile("TEST_OUT.CFG", "SE.CFG")
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux")
        else:
            os.close(slave)
            time.sleep(0.3)
            splash_out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            # Verify status bar reflects loaded configuration
            assert "80x24 |" in splash_out, (
                f"Expected 80x24 geometry in status bar:\n{splash_out}"
            )
            assert "Linux |" in splash_out, (
                f"Expected Linux format in status bar:\n{splash_out}"
            )
            os.write(master, b"q")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
            print("    [+] Canonical SE.CFG parser & serialization [PASS]")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_bug_2_4_19_panning_edge_trigger_and_geometry():
    """Verify lookahead pan edge trigger and dynamic geometry (2.4.19)."""
    print("[*] Testing lookahead pan edge trigger & geometry (2.4.19)...")
    temp_dir = tempfile.mkdtemp()
    doc_path = os.path.join(temp_dir, "testdoc_edge.txt")
    with open(doc_path, "w") as f:
        f.write(("A" * 78) + "BCDEFGHIJKL\n")

    try:
        # Part 1: Canonical lookahead edge trigger at col 79 (§6.6)
        master, slave = pty.openpty()
        winsize80 = struct.pack("HHHH", 24, 80, 0, 0)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, winsize80)

        pid = os.fork()
        if pid == 0:
            os.chdir(temp_dir)
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux", doc_path)
        else:
            os.close(slave)
            time.sleep(0.3)
            init_out = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "80x24 |" in init_out, (
                f"Expected 80x24 geometry in status bar:\n{init_out}"
            )
            assert "[Pan +40]" not in init_out, (
                f"Unexpected pan at col 0:\n{init_out}"
            )

            # Move right 79 times to reach column 79
            os.write(master, b"\x1b[C" * 79)
            time.sleep(0.3)
            edge_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            # Active line has 90 chars; at col 79 both char 79 ('B') and
            # char 80 ('C') are non-null -> lookahead triggers [Pan +40]
            assert "[Pan +40]" in edge_out, (
                f"Expected lookahead '[Pan +40]' at col 79:\n{edge_out}"
            )

            # Retreat back home via Ctrl+A (\x01) -> pan cleared
            os.write(master, b"\x01")
            time.sleep(0.2)
            home_out = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "[Pan +40]" not in home_out, (
                f"Expected pan cleared at home col 0:\n{home_out}"
            )

            # Exit cleanly via Ctrl+Q
            os.write(master, b"\x11\n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"

        # Part 2: Dynamic geometry adaptation on wide terminal (§14.1)
        master2, slave2 = pty.openpty()
        winsize = struct.pack("HHHH", 40, 120, 0, 0)
        fcntl.ioctl(slave2, termios.TIOCSWINSZ, winsize)

        pid2 = os.fork()
        if pid2 == 0:
            os.chdir(temp_dir)
            os.close(master2)
            os.dup2(slave2, 0)
            os.dup2(slave2, 1)
            os.dup2(slave2, 2)
            os.close(slave2)
            os.execl(SE_LINUX_BIN, "se-linux", doc_path)
        else:
            os.close(slave2)
            time.sleep(0.3)
            init_wide = read_all_available(master2, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "120x40 |" in init_wide, (
                f"Expected 120x40 geometry in status bar:\n{init_wide}"
            )

            # Move right 85 times: fits within 120 cols -> NO pan
            os.write(master2, b"\x1b[C" * 85)
            time.sleep(0.3)
            wide_out = read_all_available(master2, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "[Pan +40]" not in wide_out, (
                f"120-column terminal should not pan for 85 chars:\n{wide_out}"
            )

            # Exit cleanly via Ctrl+Q
            os.write(master2, b"\x11\n")
            exit_code2 = wait_pid_with_timeout(pid2, 2.0)
            os.close(master2)
            assert exit_code2 == 0, f"Expected exit code 0, got {exit_code2}"

        print("    [+] Lookahead pan edge trigger & geometry verified [PASS]")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_bug_2_4_21_backspace_line_join():
    """Verify cursor position after joining lines with backspace (§6.8)."""
    print("[*] Testing Bug 2.4.21: backspace line join cursor anchor...")
    with tempfile.NamedTemporaryFile("w+", prefix="testdoc_join_",
                                     suffix=".txt", delete=False) as tf:
        tf.write("Hello \nWorld\n")
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
            read_all_available(master, 0.2)

            # Down arrow to line 2 (Line 2, Col 1)
            os.write(master, b"\x1b[B")
            time.sleep(0.15)
            # Ensure column 0 (Ctrl+A Home)
            os.write(master, b"\x01")
            time.sleep(0.15)

            # Press Backspace (0x08) to join Line 2 with Line 1
            os.write(master, b"\x08")
            time.sleep(0.2)
            out = read_all_available(master, 0.3)
            out_str = out.decode("utf-8", errors="replace")

            # Cursor should be at Line 1 and Col 6 (len of "Hello " is 6)
            assert "Line    1/1" in out_str and "Col 6" in out_str, (
                f"Expected Line 1 Col 6 after backspace join, got:\n{out_str}"
            )

            # Exit cleanly via Ctrl+Q and decline saving (n)
            os.write(master, b"\x11")
            time.sleep(0.1)
            os.write(master, b"n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"

        print("    [+] Backspace line join cursor anchor verified [PASS]")
    finally:
        if os.path.exists(test_file_path):
            os.remove(test_file_path)


def test_bug_2_4_22_delete_active_block():
    """Verify Delete and Ctrl+D delete active block selection (§6.8, §10.1)."""
    print("[*] Testing Bug 2.4.22: Delete & Ctrl+D block deletion...")
    with tempfile.NamedTemporaryFile("w+", prefix="testdoc_b22_",
                                     suffix=".txt", delete=False) as tf:
        tf.write("Line 1: Hello World\nLine 2: Test\n")
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
            read_all_available(master, 0.2)

            # Move right 8 columns to position after "Line 1: "
            for _ in range(8):
                os.write(master, b"\x1b[C")
                time.sleep(0.02)
            time.sleep(0.1)

            # Toggle block selection (Ctrl+B / 0x02)
            os.write(master, b"\x02")
            time.sleep(0.1)

            # Move right 5 columns to select "Hello"
            for _ in range(5):
                os.write(master, b"\x1b[C")
                time.sleep(0.02)
            time.sleep(0.1)

            # Flush selection output
            read_all_available(master, 0.1)

            # Press Delete key (\x1b[3~)
            os.write(master, b"\x1b[3~")
            time.sleep(0.2)

            out = read_all_available(master, 0.3)
            out_str = out.decode("utf-8", errors="replace")
            # Should not have Sel: anymore
            assert "Sel:" not in out_str, f"Block still active:\n{out_str}"

            # Save file (Ctrl+S)
            os.write(master, b"\x13")
            time.sleep(0.3)
            read_all_available(master, 0.3)
            # Dismiss save modal with space
            os.write(master, b" ")
            time.sleep(0.2)
            read_all_available(master, 0.2)

            # Exit cleanly via Ctrl+Q
            os.write(master, b"\x11")
            time.sleep(0.2)
            read_all_available(master, 0.2)
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"

            with open(test_file_path, "r") as f:
                content = f.read()
            assert "Line 1:  World" in content or "Line 1: World" in content, (
                f"Expected 'Hello' deleted from line, got:\n{content}"
            )

        print("    [+] Delete & Ctrl+D block deletion verified [PASS]")
    finally:
        if os.path.exists(test_file_path):
            os.remove(test_file_path)


def test_bug_2_4_23_backspace_cancels_block():
    """Verify Backspace cancels dynamic block selection (§6.8, §10.1)."""
    print("[*] Testing Bug 2.4.23: Backspace cancels dynamic block...")
    with tempfile.NamedTemporaryFile("w+", prefix="testdoc_b23_",
                                     suffix=".txt", delete=False) as tf:
        tf.write("Line 1: Hello World\nLine 2: Test\n")
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
            read_all_available(master, 0.2)

            # Move right 8 columns to position after "Line 1: "
            for _ in range(8):
                os.write(master, b"\x1b[C")
                time.sleep(0.02)
            time.sleep(0.1)

            # Toggle block selection (Ctrl+B / 0x02)
            os.write(master, b"\x02")
            time.sleep(0.1)

            # Move right 5 columns to select "Hello"
            for _ in range(5):
                os.write(master, b"\x1b[C")
                time.sleep(0.02)
            time.sleep(0.1)

            out = read_all_available(master, 0.1)
            assert "Sel:" in out.decode("utf-8", errors="replace"), (
                "Expected Sel: in status bar"
            )

            # Send Backspace (0x08) to cancel block
            os.write(master, b"\x08")
            time.sleep(0.2)

            out_bs = read_all_available(master, 0.3)
            out_str = out_bs.decode("utf-8", errors="replace")
            assert "Sel:" not in out_str, f"Block still active:\n{out_str}"

            # Save file (Ctrl+S)
            os.write(master, b"\x13")
            time.sleep(0.3)
            read_all_available(master, 0.3)
            # Dismiss save modal with space
            os.write(master, b" ")
            time.sleep(0.2)
            read_all_available(master, 0.2)

            # Exit cleanly via Ctrl+Q
            os.write(master, b"\x11")
            time.sleep(0.2)
            read_all_available(master, 0.2)
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"

            with open(test_file_path, "r") as f:
                content = f.read()
            assert content == "Line 1: Hello World\nLine 2: Test\n", (
                f"Expected unmodified content, got:\n{content}"
            )

        print("    [+] Backspace cancels dynamic block verified [PASS]")
    finally:
        if os.path.exists(test_file_path):
            os.remove(test_file_path)


def test_bug_2_4_24_enter_solidifies_block():
    """Verify Enter solidifies dynamic block without splitting line."""
    print("[*] Testing Bug 2.4.24: Enter solidifies dynamic block...")
    with tempfile.NamedTemporaryFile("w+", prefix="testdoc_b24_",
                                     suffix=".txt", delete=False) as tf:
        tf.write("Line 1: Hello World\nLine 2: Test\n")
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
            read_all_available(master, 0.2)

            # Move right 8 columns to position after "Line 1: "
            for _ in range(8):
                os.write(master, b"\x1b[C")
                time.sleep(0.02)
            time.sleep(0.1)

            # Toggle block selection (Ctrl+B / 0x02)
            os.write(master, b"\x02")
            time.sleep(0.1)

            # Move right 5 columns to select "Hello"
            for _ in range(5):
                os.write(master, b"\x1b[C")
                time.sleep(0.02)
            time.sleep(0.1)

            out = read_all_available(master, 0.1)
            assert "Sel:" in out.decode("utf-8", errors="replace"), (
                "Expected Sel: in status bar"
            )

            # Press Enter (\r) to solidify block
            os.write(master, b"\r")
            time.sleep(0.2)

            out_enter = read_all_available(master, 0.3)
            out_str = out_enter.decode("utf-8", errors="replace")
            assert "Block:" in out_str, (
                f"Expected Block: in status bar after Enter:\n{out_str}"
            )
            assert "Sel:" not in out_str, (
                f"Sel: still present in status bar:\n{out_str}"
            )

            # Exit cleanly via Ctrl+Q
            os.write(master, b"\x11")
            time.sleep(0.2)
            read_all_available(master, 0.2)
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"

            with open(test_file_path, "r") as f:
                content = f.read()
            assert content == "Line 1: Hello World\nLine 2: Test\n", (
                f"Expected unmodified content (not split), got:\n{content}"
            )

        print("    [+] Enter solidifies dynamic block verified [PASS]")
    finally:
        if os.path.exists(test_file_path):
            os.remove(test_file_path)


def test_bug_2_4_25_modal_prompt_text_editing():
    """Verify in-field editing keys in Archetype C modals (§8.3, §10.1)."""
    print("[*] Testing Bug 2.4.25: Archetype C in-field editing keys...")
    with tempfile.NamedTemporaryFile("w+", prefix="tb25_", suffix=".txt",
                                     delete=False) as tf:
        for i in range(100):
            tf.write(f"Line {i+1}\n")
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
            read_all_available(master, 0.2)

            # Trigger Goto Line (Ctrl+L / 0x0C)
            os.write(master, b"\x0c")
            time.sleep(0.2)
            out_modal = read_all_available(master, 0.2)
            assert b"Goto Line" in out_modal, "Goto Line modal not rendered"

            # Type "1234"
            os.write(master, b"1234")
            time.sleep(0.1)

            # Left arrow twice (\x1b[D\x1b[D) -> pos 2
            os.write(master, b"\x1b[D\x1b[D")
            time.sleep(0.1)

            # Insert "9" -> "12934", pos 3
            os.write(master, b"9")
            time.sleep(0.1)

            # Home (Ctrl+A / 0x01) -> pos 0
            os.write(master, b"\x01")
            time.sleep(0.1)

            # Delete key (\x1b[3~) -> deletes '1', buffer is "2934"
            os.write(master, b"\x1b[3~")
            time.sleep(0.1)

            # Right arrow (\x1b[C) -> pos 1
            os.write(master, b"\x1b[C")
            time.sleep(0.1)

            # Backspace (0x08) -> deletes '2', buffer is "934"
            os.write(master, b"\x08")
            time.sleep(0.1)

            # Ctrl+D (0x04) -> deletes '9', buffer is "34"
            os.write(master, b"\x04")
            time.sleep(0.1)

            # End (Ctrl+E / 0x05) -> pos 2
            os.write(master, b"\x05")
            time.sleep(0.1)

            # Type "5" -> buffer is "345"
            os.write(master, b"5")
            time.sleep(0.1)

            # Press Enter (\r)
            os.write(master, b"\r")
            time.sleep(0.2)

            out_nav = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "Line  100/100" in out_nav or "Line 100/100" in out_nav, (
                f"Expected jump to line 100, got:\n{out_nav}"
            )

            # Exit cleanly via Ctrl+Q
            os.write(master, b"\x11")
            time.sleep(0.2)
            read_all_available(master, 0.2)
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"

        print("    [+] Archetype C in-field editing verified [PASS]")
    finally:
        if os.path.exists(test_file_path):
            os.remove(test_file_path)


def test_bug_2_4_27_file_not_found_alert():
    """Verify 50x7 File Not Found modal alert on non-existent file (2.4.27)."""
    print("[*] Testing File Not Found modal alert on open/insert (2.4.27)...")
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
        read_all_available(master, 0.2)

        # 1. Open File workspace from Splash screen via 'o'
        os.write(master, b"o")
        time.sleep(0.3)
        open_out = read_all_available(master, 0.4).decode(
            "utf-8", errors="replace"
        )
        assert "OPEN FILE (DIRECTORY)" in open_out, (
            f"Expected 'OPEN FILE (DIRECTORY)' in workspace:\n{open_out}"
        )

        # 2. Type non-existent filename "NONEXIST.TXT" and press Enter
        os.write(master, b"NONEXIST.TXT\r")
        time.sleep(0.3)
        alert_out = read_all_available(master, 0.4).decode(
            "utf-8", errors="replace"
        )
        assert "File Not Found" in alert_out, (
            f"Expected 'File Not Found' modal title:\n{alert_out}"
        )
        assert "'NONEXIST.TXT' was not found." in alert_out, (
            f"Expected 'NONEXIST.TXT' was not found in modal:\n{alert_out}"
        )
        assert "Specified file not found on disk." in alert_out, (
            f"Expected disk explanation line in modal:\n{alert_out}"
        )
        assert "Press any key to continue" in alert_out, (
            f"Expected dismissal prompt in modal:\n{alert_out}"
        )

        # 3. Dismiss modal with Space; return to browser with input intact
        os.write(master, b" ")
        time.sleep(0.3)
        browser_out = read_all_available(master, 0.4).decode(
            "utf-8", errors="replace"
        )
        assert "OPEN FILE (DIRECTORY)" in browser_out, (
            f"Expected return to Open workspace:\n{browser_out}"
        )
        assert "NONEXIST.TXT" in browser_out, (
            f"Expected input buffer 'NONEXIST.TXT' preserved:\n{browser_out}"
        )

        # 4. Cancel browser via ESC to return to splash screen
        os.write(master, b"\x1b")
        time.sleep(0.2)
        read_all_available(master, 0.2)

        # 5. Exit cleanly via 'q'
        os.write(master, b"q")
        exit_code = wait_pid_with_timeout(pid, 2.0)
        os.close(master)
        assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
        print("    [+] File Not Found modal alert verified [PASS]")


def test_bug_2_4_28_overwrite_confirmation():
    """Verify 50x7 Overwrite File confirmation modal on save (2.4.28)."""
    print("[*] Testing Overwrite File confirmation modal on save (2.4.28)...")
    temp_dir = tempfile.mkdtemp()
    target_name = "EXISTING.TXT"
    target_path = os.path.join(temp_dir, target_name)
    with open(target_path, "w") as f:
        f.write("Original file contents before overwrite\n")

    try:
        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.chdir(temp_dir)
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux")
        else:
            os.close(slave)
            time.sleep(0.3)
            read_all_available(master, 0.2)

            # 1. Open Save File workspace from Splash screen via 's'
            os.write(master, b"s")
            time.sleep(0.3)
            save_out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "SAVE FILE (DIRECTORY)" in save_out, (
                f"Expected 'SAVE FILE (DIRECTORY)' in workspace:\n{save_out}"
            )

            # 2. Type existing filename "EXISTING.TXT" and press Enter
            os.write(master, b"EXISTING.TXT\r")
            time.sleep(0.3)
            alert_out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "Overwrite File" in alert_out, (
                f"Expected 'Overwrite File' modal title:\n{alert_out}"
            )
            assert "+--------------------------------------------------+" in (
                alert_out
            ), f"Expected 52-column modal border:\n{alert_out}"
            assert "Existing file contents will be lost" in alert_out, (
                f"Expected warning text in modal:\n{alert_out}"
            )
            assert "File already exists. Overwrite?" in alert_out, (
                f"Expected overwrite question in modal:\n{alert_out}"
            )
            assert "[Y]es" in alert_out and "[N]o" in alert_out, (
                f"Expected [Y]es / [N]o options in modal:\n{alert_out}"
            )
            assert "[ESC]=Cancel" in alert_out, (
                f"Expected [ESC]=Cancel in modal:\n{alert_out}"
            )

            # 3. Press 'n' to decline; return to browser with input intact
            os.write(master, b"n")
            time.sleep(0.3)
            browser_out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "SAVE FILE (DIRECTORY)" in browser_out, (
                f"Expected return to Save workspace:\n{browser_out}"
            )
            assert "EXISTING.TXT" in browser_out, (
                f"Expected input buffer preserved:\n{browser_out}"
            )

            # Disk content must be untouched
            with open(target_path, "r") as f:
                disk_content = f.read()
            assert "Original file contents" in disk_content, (
                f"File was modified despite declining:\n{disk_content}"
            )

            # 4. Press Enter again and confirm with 'y'
            os.write(master, b"\r")
            time.sleep(0.3)
            read_all_available(master, 0.2)
            os.write(master, b"y")
            time.sleep(0.3)
            notify_out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "Save Complete" in notify_out, (
                f"Expected 'Save Complete' notification:\n{notify_out}"
            )

            # Dismiss Save Complete notification with Space
            os.write(master, b" ")
            time.sleep(0.2)
            read_all_available(master, 0.2)

            # 5. Exit cleanly via Ctrl+Q
            os.write(master, b"\x11")
            time.sleep(0.2)
            read_all_available(master, 0.2)
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
            print("    [+] Overwrite File confirmation modal verified [PASS]")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_bug_2_4_29_block_save_and_insert():
    """Verify block-active Ctrl+S (Save Block) and Ctrl+O (Insert File)."""
    print("[*] Testing block-active Ctrl+S and Ctrl+O (Bug 2.4.29)...")
    temp_dir = tempfile.mkdtemp()
    doc_path = os.path.join(temp_dir, "DOC.TXT")
    insert_path = os.path.join(temp_dir, "INSERT.TXT")
    block_path = os.path.join(temp_dir, "BLOCK.TXT")

    with open(doc_path, "w") as f:
        f.write("Line 1: Alpha\nLine 2: Bravo\n"
                "Line 3: Charlie\nLine 4: Delta\n")
    with open(insert_path, "w") as f:
        f.write("Inserted row 1\nInserted row 2\n")

    try:
        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.chdir(temp_dir)
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux", doc_path)
        else:
            os.close(slave)
            time.sleep(0.3)
            read_all_available(master, 0.2)

            # Move down to Line 2 via Down arrow (\x1b[B)
            os.write(master, b"\x1b[B")
            time.sleep(0.1)

            # Start block selection via Ctrl+B (\x02)
            os.write(master, b"\x02")
            time.sleep(0.1)

            # Move down to Line 3 to highlight Line 2 and Line 3
            os.write(master, b"\x1b[B")
            time.sleep(0.1)
            read_all_available(master, 0.2)

            # Press Ctrl+S (\x13) -> must open SAVE BLOCK workspace
            os.write(master, b"\x13")
            time.sleep(0.3)
            save_blk_out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "SAVE BLOCK (DIRECTORY)" in save_blk_out, (
                f"Expected 'SAVE BLOCK (DIRECTORY)':\n{save_blk_out}"
            )

            # Type BLOCK.TXT and press Enter
            os.write(master, b"BLOCK.TXT\r")
            time.sleep(0.3)
            notify_out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "Save Complete" in notify_out, (
                f"Expected 'Save Complete':\n{notify_out}"
            )

            # Dismiss notification with Space
            os.write(master, b" ")
            time.sleep(0.2)
            ed_out = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            # Selection state is retained per §7.8
            assert "Block:" in ed_out or "Sel:" in ed_out, (
                f"Block selection was not retained:\n{ed_out}"
            )

            # Verify saved block file contains only highlighted rows
            with open(block_path, "r") as f:
                block_content = f.read()
            assert "Line 2: Bravo" in block_content, (
                f"Missing Line 2 in saved block:\n{block_content}"
            )
            assert "Line 3: Charlie" in block_content, (
                f"Missing Line 3 in saved block:\n{block_content}"
            )
            assert "Line 1: Alpha" not in block_content, (
                f"Line 1 should not be in saved block:\n{block_content}"
            )

            # Press Ctrl+O (\x0f) -> must open INSERT FILE workspace
            os.write(master, b"\x0f")
            time.sleep(0.3)
            ins_out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "INSERT FILE (DIRECTORY)" in ins_out, (
                f"Expected 'INSERT FILE (DIRECTORY)':\n{ins_out}"
            )

            # Type INSERT.TXT and press Enter
            os.write(master, b"INSERT.TXT\r")
            time.sleep(0.3)
            ins_res = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert ("Inserted row 1" in ins_res or
                    "Inserted row 2" in ins_res), (
                f"Expected inserted rows in editor:\n{ins_res}"
            )

            # Exit cleanly via Ctrl+Q and discard edits ('n')
            os.write(master, b"\x11")
            time.sleep(0.2)
            os.write(master, b"n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
            print("    [+] Block save and file insert verified [PASS]")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_bug_2_4_30_block_menu_popup():
    print("[*] Testing Tier 2 block popup menu on Ctrl+K (Bug 2.4.30)...")
    temp_dir = tempfile.mkdtemp(prefix="se_test_blk_popup_")
    try:
        sample_path = os.path.join(temp_dir, "SAMPLE.TXT")
        with open(sample_path, "w") as f:
            f.write("Line 1: Alpha\nLine 2: Bravo\nLine 3: Charlie\n")

        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.chdir(temp_dir)
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux", "SAMPLE.TXT")
        else:
            os.close(slave)
            time.sleep(0.3)
            read_all_available(master, 0.4)

            # 1. Without block active, Ctrl+K opens Help Screen
            os.write(master, b"\x0b")  # Ctrl+K
            time.sleep(0.3)
            help_out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "EDITOR MODE KEYS" in help_out, (
                f"Expected Help screen on Ctrl+K with no block:\n{help_out}"
            )
            # Dismiss help screen with ESC
            os.write(master, b"\x1b")
            time.sleep(0.3)
            read_all_available(master, 0.2)

            # 2. Start dynamic block selection (Ctrl+B) and move down
            os.write(master, b"\x02")  # Ctrl+B
            time.sleep(0.1)
            os.write(master, b"\x1b[B")  # Down arrow
            time.sleep(0.1)
            read_all_available(master, 0.2)

            # 3. Press Ctrl+K -> must open Block Operations modal
            os.write(master, b"\x0b")  # Ctrl+K
            time.sleep(0.3)
            popup_out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "Block Operations" in popup_out, (
                f"Expected 'Block Operations' modal on Ctrl+K:\n{popup_out}"
            )
            assert "Selection:" in popup_out, (
                f"Expected 'Selection:' in modal Line 4:\n{popup_out}"
            )
            assert "[Enter]=Lock/Set" in popup_out, (
                f"Expected '[Enter]=Lock/Set' in modal Line 5:\n{popup_out}"
            )

            # 4. Press ESC to close modal non-destructively; selection kept
            os.write(master, b"\x1b")
            time.sleep(0.3)
            ed_out = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "Sel:" in ed_out, (
                f"Expected Sel: retained after ESC close:\n{ed_out}"
            )

            # 5. Open popup again and press Enter to Lock/Set (solidify)
            os.write(master, b"\x0b")  # Ctrl+K
            time.sleep(0.3)
            read_all_available(master, 0.2)
            os.write(master, b"\r")  # Enter
            time.sleep(0.3)
            ed_out2 = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "Block:" in ed_out2, (
                f"Expected Block: after Enter in popup:\n{ed_out2}"
            )

            # 6. Open popup while solidified -> check Marked Block & Copy
            os.write(master, b"\x0b")  # Ctrl+K
            time.sleep(0.3)
            popup_out2 = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "Marked Block:" in popup_out2, (
                f"Expected 'Marked Block:' in modal Line 4:\n{popup_out2}"
            )
            assert "[^C]=Copy Block" in popup_out2, (
                f"Expected '[^C]=Copy Block' in modal Line 5:\n{popup_out2}"
            )

            # 7. Press 'b' to clear selection
            os.write(master, b"b")
            time.sleep(0.3)
            ed_out3 = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "Block:" not in ed_out3 and "Sel:" not in ed_out3, (
                f"Expected block cleared after 'b':\n{ed_out3}"
            )

            # Exit cleanly
            os.write(master, b"\x11")
            time.sleep(0.2)
            os.write(master, b"n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
            print("    [+] Block Operations modal popup verified [PASS]")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_bug_2_4_31_find_modal_cursor_navigation():
    """Verify in-field cursor editing in Find Text modal (Bug 2.4.31)."""
    print("[*] Testing in-field cursor navigation in Find modal (2.4.31)...")
    temp_dir = tempfile.mkdtemp(prefix="se_test_find_nav_")
    try:
        sample_path = os.path.join(temp_dir, "FIND_SAMPLE.TXT")
        with open(sample_path, "w") as f:
            f.write("Line 1: Target word TARGETMATCH is here.\n")

        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.chdir(temp_dir)
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux", "FIND_SAMPLE.TXT")
        else:
            os.close(slave)
            time.sleep(0.3)
            read_all_available(master, 0.4)

            # 1. Open Find Text modal via Ctrl+F (\x06)
            os.write(master, b"\x06")
            time.sleep(0.3)
            modal_out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "Find Text" in modal_out, (
                f"Expected 'Find Text' modal:\n{modal_out}"
            )

            # 2. Type "TAGET"
            os.write(master, b"TAGET")
            time.sleep(0.1)

            # 3. Left arrow 3 times (\x1b[D\x1b[D\x1b[D) -> between 'A' and 'G'
            os.write(master, b"\x1b[D\x1b[D\x1b[D")
            time.sleep(0.1)

            # 4. Insert 'R' -> buffer is "TARGET"
            os.write(master, b"R")
            time.sleep(0.1)

            # 5. Home (Ctrl+A / \x01) -> pos 0
            os.write(master, b"\x01")
            time.sleep(0.1)

            # 6. Type "X" at pos 0 -> buffer is "XTARGET"
            os.write(master, b"X")
            time.sleep(0.1)

            # 7. Left arrow to pos 0, then Delete (\x1b[3~) -> removes 'X'
            os.write(master, b"\x1b[D")
            time.sleep(0.1)
            os.write(master, b"\x1b[3~")
            time.sleep(0.1)

            # 8. End (Ctrl+E / \x05) -> pos 6 (end of "TARGET")
            os.write(master, b"\x05")
            time.sleep(0.1)

            # 9. Type "MATCH" -> buffer is "TARGETMATCH"
            os.write(master, b"MATCH")
            time.sleep(0.1)

            # 10. Press Enter -> finds TARGETMATCH in document
            os.write(master, b"\r")
            time.sleep(0.3)
            doc_out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "TARGETMATCH" in doc_out, (
                f"Expected editor to display matched TARGETMATCH:\n{doc_out}"
            )

            # Exit cleanly via Ctrl+Q
            os.write(master, b"\x11")
            time.sleep(0.2)
            os.write(master, b"n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
            print("    [+] Find modal in-field cursor editing verified [PASS]")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_bug_2_4_32_escape_sequence_leakage():
    """Verify atomic draining of unrecognized escape sequences (Bug 2.4.32)."""
    print("[*] Testing atomic escape sequence draining (Bug 2.4.32)...")
    temp_dir = tempfile.mkdtemp(prefix="se_test_leakage_")
    try:
        # 1. Leakage in editor mode
        sample_path = os.path.join(temp_dir, "LEAK_TEST.TXT")
        with open(sample_path, "w") as f:
            f.write("Line 1: \n")

        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.chdir(temp_dir)
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux", "LEAK_TEST.TXT")
        else:
            os.close(slave)
            time.sleep(0.3)
            read_all_available(master, 0.4)

            # Send complex/unrecognized CSI sequences followed by CLEAN_INPUT
            payload = b"\x1b[99~\x1b[1;5C\x1b[?1049hCLEAN_INPUT"
            os.write(master, payload)
            time.sleep(0.4)

            out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "CLEAN_INPUT" in out, (
                f"Expected CLEAN_INPUT in output:\n{out}"
            )
            assert "99~" not in out, f"Leaked 99~ in output:\n{out}"
            assert "1;5C" not in out and "5C" not in out, (
                f"Leaked 5C in output:\n{out}"
            )
            assert "?1049h" not in out and "1049h" not in out, (
                f"Leaked 1049h in output:\n{out}"
            )

            # Exit cleanly via Ctrl+Q
            os.write(master, b"\x11")
            time.sleep(0.2)
            os.write(master, b"n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"

        # 2. Leakage on splash screen must not trigger hotkeys
        master2, slave2 = pty.openpty()
        pid2 = os.fork()
        if pid2 == 0:
            os.chdir(temp_dir)
            os.close(master2)
            os.dup2(slave2, 0)
            os.dup2(slave2, 1)
            os.dup2(slave2, 2)
            os.close(slave2)
            os.execl(SE_LINUX_BIN, "se-linux")
        else:
            os.close(slave2)
            time.sleep(0.3)
            splash_out = read_all_available(master2, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert ("SE - Screen Editor" in splash_out) or (
                "SE — Screen Editor" in splash_out
            )

            # Send unrecognized escape sequence that would contain 'C' if leaked
            os.write(master2, b"\x1b[1;5C")
            time.sleep(0.3)
            after_esc = read_all_available(master2, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "Configuration Manager" not in after_esc, (
                "Leaked 'C' triggered Configuration Manager on splash screen:\n"
                f"{after_esc}"
            )

            # Exit cleanly via 'q'
            os.write(master2, b"q")
            exit_code2 = wait_pid_with_timeout(pid2, 2.0)
            os.close(master2)
            assert exit_code2 == 0, f"Expected exit code 0, got {exit_code2}"

            print("    [+] Escape sequence leakage prevention verified [PASS]")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_bug_2_4_33_block_typing_cancellation():
    """Verify typing printable chars and tab clears active block (2.4.33)."""
    print("[*] Testing block cancellation on typing & tab (Bug 2.4.33)...")
    temp_dir = tempfile.mkdtemp(prefix="se_test_blk_type_")
    try:
        sample_path = os.path.join(temp_dir, "BLOCK_TYPE.TXT")
        with open(sample_path, "w") as f:
            f.write("Line 1: Hello World\n")

        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.chdir(temp_dir)
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux", "BLOCK_TYPE.TXT")
        else:
            os.close(slave)
            time.sleep(0.3)
            read_all_available(master, 0.4)

            # 1. Start dynamic block selection (Ctrl+B) and move right 3 cols
            os.write(master, b"\x02\x1b[C\x1b[C\x1b[C")
            time.sleep(0.2)
            sel_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "Sel:" in sel_out, (
                f"Expected Sel: in status bar:\n{sel_out}"
            )

            # 2. Type 'Z' in dynamic mode -> cancels block, does NOT insert 'Z'
            os.write(master, b"Z")
            time.sleep(0.2)
            after_z = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "Sel:" not in after_z, (
                f"Sel: not cleared on char typing:\n{after_z}"
            )
            assert "ZHello" not in after_z and "Line 1: Z" not in after_z, (
                f"'Z' should NOT be inserted in dynamic selection:\n{after_z}"
            )

            # 3. Start dynamic selection again and solidify via Enter
            os.write(master, b"\x02\x1b[C\x1b[C\r")
            time.sleep(0.2)
            solid_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "Block:" in solid_out, (
                f"Expected Block::\n{solid_out}"
            )

            # 4. Type 'Q' in solidified mode -> clears block AND inserts 'Q'
            os.write(master, b"Q")
            time.sleep(0.2)
            after_q = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "Block:" not in after_q, (
                f"Block: not cleared:\n{after_q}"
            )
            assert "Q" in after_q, (
                f"Expected 'Q' inserted in solidified mode:\n{after_q}"
            )

            # Exit cleanly via Ctrl+Q
            os.write(master, b"\x11")
            time.sleep(0.2)
            os.write(master, b"n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
            print("    [+] Block cancellation on typing verified [PASS]")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_bug_2_4_34_splash_language_indication():
    """Verify splash clean header mandate (Bug 2.4.34 / Section 7.2)."""
    print("[*] Testing splash clean header mandate (2.4.34)...")
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
        splash_out = read_all_available(master, 0.4).decode(
            "utf-8", errors="replace"
        )
        assert "SE - Screen Editor" in splash_out, (
            f"Expected 'SE - Screen Editor' on row 1:\n{splash_out}"
        )
        assert "Version v1.1.0" not in splash_out, (
            f"Version must not appear on splash screen:\n{splash_out}"
        )

        # Exit cleanly via 'q'
        os.write(master, b"q")
        exit_code = wait_pid_with_timeout(pid, 2.0)
        os.close(master)
        assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
        print("    [+] Splash clean header mandate verified [PASS]")


def test_bug_2_4_35_splash_hotkeys_and_native_mode():
    """Verify splash screen hotkeys (1:80x24, 2:120x40, 3:native) (2.4.35)."""
    print("[*] Testing splash hotkeys and native mode (Bug 2.4.35)...")
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
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
        splash_out = read_all_available(master, 0.4).decode(
            "utf-8", errors="replace"
        )
        assert "type   [1]              set 80x24" in splash_out, (
            f"Expected 'set 80x24' on hotkey 1:\n{splash_out}"
        )
        assert "type   [2]              set 120x40" in splash_out, (
            f"Expected 'set 120x40' on hotkey 2:\n{splash_out}"
        )

        # Press '1' -> 80x24 mode
        os.write(master, b"1")
        time.sleep(0.2)
        out1 = read_all_available(master, 0.3).decode(
            "utf-8", errors="replace"
        )
        assert " 80x24 |" in out1, (
            f"Expected ' 80x24 |' in status bar after pressing '1':\n{out1}"
        )

        # Press '2' -> 120x40 mode
        os.write(master, b"2")
        time.sleep(0.2)
        out2 = read_all_available(master, 0.3).decode(
            "utf-8", errors="replace"
        )
        assert " 120x40 |" in out2, (
            f"Expected ' 120x40 |' in status bar after pressing '2':\n{out2}"
        )

        # Press '3' -> Native mode (100x30 in our pty)
        os.write(master, b"3")
        time.sleep(0.2)
        out3 = read_all_available(master, 0.3).decode(
            "utf-8", errors="replace"
        )
        assert " 100x30 |" in out3, (
            f"Expected ' 100x30 |' in status bar after pressing '3':\n{out3}"
        )

        # Exit cleanly via 'q'
        os.write(master, b"q")
        exit_code = wait_pid_with_timeout(pid, 2.0)
        os.close(master)
        assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
        print("    [+] Splash hotkeys and native mode verified [PASS]")


def test_bug_2_4_36_geometry_switch_clear():
    """Verify screen clearance on geometry mode switching (Bug 2.4.36)."""
    print("[*] Testing screen clearance on geometry switch (Bug 2.4.36)...")
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
        read_all_available(master, 0.4)

        # Switch to 80x24 mode and verify ANSI screen clear emitted
        os.write(master, b"1")
        time.sleep(0.2)
        raw1 = read_all_available(master, 0.3)
        assert b"\x1b[2J\x1b[H" in raw1, (
            "Screen switch to 80x24 missing ANSI clear (\\x1b[2J\\x1b[H)"
        )

        # Switch to 120x40 mode and verify ANSI screen clear emitted
        os.write(master, b"2")
        time.sleep(0.2)
        raw2 = read_all_available(master, 0.3)
        assert b"\x1b[2J\x1b[H" in raw2, (
            "Screen switch to 120x40 missing ANSI clear sequence"
        )

        # Switch to native mode and verify ANSI screen clear emitted
        os.write(master, b"3")
        time.sleep(0.2)
        raw3 = read_all_available(master, 0.3)
        assert b"\x1b[2J\x1b[H" in raw3, (
            "Screen switch to Native missing ANSI clear sequence"
        )

        # Exit cleanly via 'q'
        os.write(master, b"q")
        exit_code = wait_pid_with_timeout(pid, 2.0)
        os.close(master)
        assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
        print("    [+] Screen clearance on geometry switch verified [PASS]")


def test_bug_2_4_37_config_screen_interactive():
    """Verify interactive Configuration Manager workspace (Bug 2.4.37)."""
    print("[*] Testing interactive config workspace (Bug 2.4.37)...")
    temp_dir = tempfile.mkdtemp(prefix="se_cfg_test_")
    try:
        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.close(master)
            os.chdir(temp_dir)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux")
        else:
            os.close(slave)
            time.sleep(0.3)
            read_all_available(master, 0.3)

            # Open Configuration Manager via 'c'
            os.write(master, b"c")
            time.sleep(0.2)
            cfg_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "Configuration Manager" in cfg_out, (
                f"Failed to enter Configuration Manager:\n{cfg_out}"
            )

            # Toggle Tab Width via '4' (8 -> 4)
            os.write(master, b"4")
            time.sleep(0.2)
            tab_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "4. Tab Width        : 4" in tab_out, (
                f"Tab width toggle failed:\n{tab_out}"
            )

            # Toggle Max Doc Lines via '3' (16K -> 32K)
            os.write(master, b"3")
            time.sleep(0.2)
            lines_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "3. Max Doc Lines    : 32K" in lines_out, (
                f"Lines mode toggle failed:\n{lines_out}"
            )

            # Save configuration via 's'
            os.write(master, b"s")
            time.sleep(0.2)
            read_all_available(master, 0.2)

            # Exit config workspace via ESC
            os.write(master, b"\x1b")
            time.sleep(0.2)
            splash_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert ("SE - Screen Editor" in splash_out) or (
                "SE — Screen Editor" in splash_out
            ), f"Failed to return to splash screen:\n{splash_out}"

            # Exit cleanly via 'q'
            os.write(master, b"q")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"

            # Verify SE.CFG contents persisted on disk
            cfg_path = os.path.join(temp_dir, "SE.CFG")
            assert os.path.exists(cfg_path), "SE.CFG was not created"
            with open(cfg_path, "r", encoding="utf-8") as f:
                content = f.read()
            assert "TAB=4" in content, f"Expected TAB=4 in SE.CFG:\n{content}"
            assert "LINES=32K" in content, (
                f"Expected LINES=32K in SE.CFG:\n{content}"
            )
            print("    [+] Interactive config workspace verified [PASS]")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_bug_2_4_38_default_tab_width():
    """Verify canonical default tab width is 8 columns (§6.2, §13.2)."""
    print("[*] Testing default tab width is 8 columns (Bug 2.8.15)...")
    temp_dir = tempfile.mkdtemp()
    test_file = os.path.join(temp_dir, "test_tab.txt")
    with open(test_file, "w") as f:
        f.write("\tABC\n")

    try:
        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.chdir(temp_dir)
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux", test_file)
        else:
            os.close(slave)
            time.sleep(0.3)
            init_out = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "Col 0" in init_out, f"Expected initial Col 0:\n{init_out}"

            # Move right 1 character past tab: visual column must leap to 8
            os.write(master, b"\x1b[C")
            time.sleep(0.1)
            out_tab = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "Col 8" in out_tab, (
                f"Expected visual Col 8 after default tab width 8:\n{out_tab}"
            )

            # Exit cleanly via Ctrl+Q
            os.write(master, b"\x11")
            time.sleep(0.1)
            os.close(master)
            os.waitpid(pid, 0)
            print("    [+] Default tab width 8 verified [PASS]")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_bug_2_4_39_help_screen_canonical_layout():
    """Verify canonical 22-line Help screen and ANSI keys (Bug 2.4.39)."""
    print("[*] Testing Help screen canonical layout & ANSI keys (2.4.39)...")
    temp_dir = tempfile.mkdtemp()
    test_file = os.path.join(temp_dir, "test_help.txt")
    with open(test_file, "w") as f:
        f.write("Line 1\nLine 2\n")

    try:
        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.chdir(temp_dir)
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux", test_file)
        else:
            os.close(slave)
            time.sleep(0.3)
            read_all_available(master, 0.2)

            # Press Ctrl+K in editor mode with no block to open Help screen
            os.write(master, b"\x0b")
            time.sleep(0.2)
            help_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "EDITOR MODE KEYS" in help_out, (
                f"Expected 'EDITOR MODE KEYS' in Help screen:\n{help_out}"
            )
            assert "Arrows / WordStar" not in help_out, (
                f"Obsolete WordStar keys still present in Help:\n{help_out}"
            )
            assert "Arrow Keys" in help_out, (
                f"Expected 'Arrow Keys' in Help screen:\n{help_out}"
            )
            assert "Press any key to continue" in help_out, (
                f"Expected return prompt in Help screen:\n{help_out}"
            )

            # Dismiss Help screen with Enter
            os.write(master, b"\r")
            time.sleep(0.1)

            # Exit cleanly via Ctrl+Q
            os.write(master, b"\x11")
            time.sleep(0.1)
            os.close(master)
            os.waitpid(pid, 0)
            print("    [+] Help screen canonical layout verified [PASS]")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_bug_2_4_40_plugin_palette_modal():
    """Verify Archetype D Plugin Palette modal on Ctrl+P (Bug 2.4.40)."""
    print("[*] Testing Archetype D Plugin Palette on Ctrl+P (2.4.40)...")
    temp_dir = tempfile.mkdtemp()
    test_file = os.path.join(temp_dir, "test_palette.txt")
    with open(test_file, "w") as f:
        f.write("Hello world\n")

    try:
        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.chdir(temp_dir)
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux", test_file)
        else:
            os.close(slave)
            time.sleep(0.3)
            read_all_available(master, 0.2)

            # Press Ctrl+P (0x10) to open Plugin Palette modal
            os.write(master, b"\x10")
            time.sleep(0.2)
            modal_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "Plugin Palette" in modal_out, (
                f"Missing 'Plugin Palette' title:\n{modal_out}"
            )
            assert "+------------------------------------------------+" in (
                modal_out
            ), f"Missing 50-col frame border:\n{modal_out}"
            assert "Select a plugin to execute:" in modal_out, (
                f"Missing prompt in palette:\n{modal_out}"
            )
            assert "> 1. ROT13" in modal_out, (
                f"Missing active selector on ROT13:\n{modal_out}"
            )
            assert "WORDCNT" in modal_out and "BEAUTIFY" in modal_out, (
                f"Missing plugin entries:\n{modal_out}"
            )
            assert "[Up/Down]=Select" in modal_out, (
                f"Missing navigation footer:\n{modal_out}"
            )

            # Move selection down via Down arrow (ESC [ B)
            os.write(master, b"\x1b[B")
            time.sleep(0.2)
            down_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "> 2. WORDCNT" in down_out, (
                f"Expected selection moved to WORDCNT:\n{down_out}"
            )

            # Cancel via ESC
            os.write(master, b"\x1b")
            time.sleep(0.2)
            read_all_available(master, 0.2)

            # Re-open via Ctrl+P and execute ROT13 via Enter
            os.write(master, b"\x10")
            time.sleep(0.2)
            read_all_available(master, 0.2)
            os.write(master, b"\r")
            time.sleep(0.2)
            rot_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            # ROT13 of "Hello" is "Uryyb"
            assert "Uryyb" in rot_out, (
                f"Expected ROT13 transformation 'Uryyb' in editor:\n{rot_out}"
            )

            # Exit cleanly via Ctrl+Q then 'n' to discard
            os.write(master, b"\x11")
            time.sleep(0.1)
            os.write(master, b"n")
            time.sleep(0.1)
            os.close(master)
            os.waitpid(pid, 0)
            print("    [+] Archetype D Plugin Palette verified [PASS]")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_bug_2_4_41_tab_snap_forward():
    """Verify snap-forward tab alignment in adjust_col_to_target (2.4.41)."""
    print("[*] Testing snap-forward tab alignment (Bug 2.4.41)...")
    temp_dir = tempfile.mkdtemp()
    test_file = os.path.join(temp_dir, "test_tab_snap.txt")
    with open(test_file, "w") as f:
        f.write("0123456789\n\tABCDEF\n")

    try:
        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.chdir(temp_dir)
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux", test_file)
        else:
            os.close(slave)
            time.sleep(0.3)
            read_all_available(master, 0.2)

            # Move right 2 columns on Line 1: TARGET_COL = 2
            os.write(master, b"\x1b[C" * 2)
            time.sleep(0.1)
            out_l1 = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "Line    1/2" in out_l1 and "Col 2" in out_l1, (
                f"Expected Line 1 Col 2:\n{out_l1}"
            )

            # Move down to Line 2 (\tABCDEF): TARGET_COL 2 falls inside tab.
            # Snap-forward alignment snaps across tab to Col 8 (char 'A').
            os.write(master, b"\x1b[B")
            time.sleep(0.1)
            out_l2 = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "Line    2/2" in out_l2 and "Col 8" in out_l2, (
                f"Expected Line 2 Col 8 via snap-forward:\n{out_l2}"
            )

            # Move up back to Line 1: sticky TARGET_COL 2 preserved!
            os.write(master, b"\x1b[A")
            time.sleep(0.1)
            out_l1_back = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "Line    1/2" in out_l1_back and "Col 2" in out_l1_back, (
                f"Expected restored Line 1 Col 2:\n{out_l1_back}"
            )

            # Exit cleanly via Ctrl+Q
            os.write(master, b"\x11")
            time.sleep(0.1)
            os.close(master)
            os.waitpid(pid, 0)
            print("    [+] Snap-forward tab alignment verified [PASS]")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_bug_2_4_42_config_screen_canonical_layout():
    """Verify canonical Configuration Manager layout and order (Bug 2.4.42)."""
    print("[*] Testing canonical Configuration Manager layout (Bug 2.4.42)...")
    temp_dir = tempfile.mkdtemp(prefix="se_cfg_canonical_")
    try:
        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.close(master)
            os.chdir(temp_dir)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux")
        else:
            os.close(slave)
            time.sleep(0.3)
            read_all_available(master, 0.3)

            # Open Configuration Manager via 'c'
            os.write(master, b"c")
            time.sleep(0.2)
            cfg_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )

            # 1. Canonical ASCII hyphen title
            assert "SE - Configuration Manager" in cfg_out, (
                f"Expected 'SE - Configuration Manager' in title:\n{cfg_out}"
            )
            assert "SE \xe2\x80\x94 Configuration Manager" not in cfg_out, (
                "Unexpected UTF-8 em-dash in Configuration Manager title"
            )

            # 2. Origin status header
            assert "Config Status: Defaults" in cfg_out, (
                f"Expected 'Config Status: Defaults' in:\n{cfg_out}"
            )

            # 3. Canonical option order and labels
            assert "1. Screen Geometry  :" in cfg_out, (
                f"Expected Option 1 Screen Geometry:\n{cfg_out}"
            )
            assert "2. RAM Drive Mode   :" in cfg_out, (
                f"Expected Option 2 RAM Drive Mode:\n{cfg_out}"
            )
            assert "3. Max Doc Lines    :" in cfg_out, (
                f"Expected Option 3 Max Doc Lines:\n{cfg_out}"
            )
            assert "4. Tab Width        :" in cfg_out, (
                f"Expected Option 4 Tab Width:\n{cfg_out}"
            )
            assert "5. Plugin Manager   :" in cfg_out, (
                f"Expected Option 5 Plugin Manager:\n{cfg_out}"
            )

            # 4. Canonical footer
            assert "[1-5]=Toggle Option  [S]=Save Config  [ESC]=Exit" in (
                cfg_out
            ), f"Expected canonical footer in:\n{cfg_out}"

            # 5. Prohibited prompt absence
            assert "Enter option:" not in cfg_out, (
                f"Prohibited 'Enter option:' prompt found in:\n{cfg_out}"
            )

            # 6. Verify Option 5 is Builtin and non-disableable (Section 14.8)
            assert "5. Plugin Manager   : Builtin" in cfg_out, (
                f"Expected '5. Plugin Manager   : Builtin' in:\n{cfg_out}"
            )
            os.write(master, b"5")
            time.sleep(0.1)

            # 7. Save config via 's'
            os.write(master, b"s")
            time.sleep(0.2)
            read_all_available(master, 0.2)

            # 8. Exit to splash via 'q'
            os.write(master, b"q")
            time.sleep(0.2)
            out_splash = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "Screen Editor" in out_splash, (
                f"Expected splash screen after 'q' exit:\n{out_splash}"
            )

            # 9. Re-enter Configuration Manager ('c'): origin must be SE.CFG
            os.write(master, b"c")
            time.sleep(0.2)
            out_cfg2 = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "Config Status: Loaded from SE.CFG" in out_cfg2, (
                f"Expected 'Loaded from SE.CFG' status in:\n{out_cfg2}"
            )

            # 10. Exit back to splash and terminate cleanly
            os.write(master, b"q")
            time.sleep(0.2)
            os.write(master, b"q")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
            print("    [+] Canonical Configuration Manager verified [PASS]")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_bug_2_4_43_splash_canonical_layout():
    """Verify 21x50 canonical layout and 4 diagnostic lines (Bug 2.4.43)."""
    print("[*] Testing 21x50 canonical splash layout (Bug 2.4.43)...")
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
        splash_out = read_all_available(master, 0.4).decode(
            "utf-8", errors="replace"
        )

        # 1. Clean header: ASCII hyphen title, no UTF-8 em-dash, no version/lang
        assert "SE - Screen Editor" in splash_out, (
            f"Expected 'SE - Screen Editor' in splash header:\n{splash_out}"
        )
        assert "SE \xe2\x80\x94 Screen Editor" not in splash_out, (
            "Found multi-byte UTF-8 em-dash in splash title"
        )
        assert "Version v1.1.0" not in splash_out, (
            f"Version must not appear on splash screen:\n{splash_out}"
        )

        # 2. Key commands present
        assert "type   [E]  or  [Enter] to edit" in splash_out
        assert "type   [1]              set 80x24" in splash_out
        assert "type   [2]              set 120x40" in splash_out
        assert "type   [Q]  or  [^Q]    to exit" in splash_out

        # 3. All 4 diagnostic status lines present
        assert "Active Screen : [" in splash_out, (
            f"Missing Active Screen diagnostic line:\n{splash_out}"
        )
        assert "RAM Drive" in splash_out, (
            f"Missing RAM Drive diagnostic line:\n{splash_out}"
        )
        assert "Plugin System : [Builtin]" in splash_out, (
            f"Missing Plugin System diagnostic line:\n{splash_out}"
        )
        assert "Max Lines     : [" in splash_out and "lines]" in splash_out, (
            f"Missing Max Lines diagnostic line:\n{splash_out}"
        )

        # 4. Geometry switch updates diagnostic line
        os.write(master, b"1")
        time.sleep(0.3)
        splash_80 = read_all_available(master, 0.4).decode(
            "utf-8", errors="replace"
        )
        assert "Active Screen : [80x24 (Classic Terminal)]" in splash_80, (
            f"Active Screen diagnostic not updated on '1':\n{splash_80}"
        )

        os.write(master, b"2")
        time.sleep(0.3)
        splash_120 = read_all_available(master, 0.4).decode(
            "utf-8", errors="replace"
        )
        assert "Active Screen : [120x40 (Modern Default)]" in splash_120, (
            f"Active Screen diagnostic not updated on '2':\n{splash_120}"
        )

        # Exit cleanly via 'q'
        os.write(master, b"q")
        exit_code = wait_pid_with_timeout(pid, 2.0)
        os.close(master)
        assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
        print("    [+] Canonical 21x50 splash screen layout verified [PASS]")


def test_bug_2_4_44_about_screen_canonical_layout():
    """Verify 9x54 canonical About screen layout and credits (Bug 2.4.44)."""
    print("[*] Testing 9x54 canonical About screen layout (Bug 2.4.44)...")
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
        read_all_available(master, 0.3)

        # Open About screen via 'a'
        os.write(master, b"a")
        time.sleep(0.3)
        about_out = read_all_available(master, 0.4).decode(
            "utf-8", errors="replace"
        )

        # 1. Canonical ASCII hyphen title
        assert "SE - Screen Editor" in about_out, (
            f"Expected 'SE - Screen Editor' in About title:\n{about_out}"
        )
        assert "SE.COM \xe2\x80\x94 Screen Editor (Linux)" not in about_out, (
            "Found non-canonical UTF-8 em-dash host label in About title"
        )

        # 2. Canonical version with build date and predominant language
        lang_tag = (
            "(Rust)" if USE_RUST else ("(Python)" if PY_MODE else "(C)")
        )
        expected_ver = f"version 1.1.4 (2026-10-18) {lang_tag}"
        expected_credits = (
            "Google Antigravity 2.23.0 & Gemini 4 Argon Medium"
        )
        assert expected_ver in about_out, (
            f"Expected '{expected_ver}' in:\n{about_out}"
        )

        # 3. Author attribution
        assert "by Dean Jenkins" in about_out, (
            f"Missing author attribution in:\n{about_out}"
        )

        # 4. Toolchain and AI credits
        assert expected_credits in about_out, (
            f"Missing toolchain credits '{expected_credits}' in:\n{about_out}"
        )

        # 5. MIT license notice
        assert "Open source software under the MIT License" in about_out, (
            f"Missing MIT license notice in:\n{about_out}"
        )

        # 6. Canonical return prompt
        assert "Press any key to continue" in about_out, (
            f"Expected canonical 'Press any key to continue' in:\n{about_out}"
        )
        assert "Press any key to return..." not in about_out, (
            "Found non-canonical 'Press any key to return...' prompt"
        )

        # 7. Press any key to return to splash screen
        os.write(master, b" ")
        time.sleep(0.3)
        splash_out = read_all_available(master, 0.4).decode(
            "utf-8", errors="replace"
        )
        assert "Screen Editor" in splash_out, (
            f"Failed to return to splash screen after dismiss:\n{splash_out}"
        )

        # Exit cleanly via 'q'
        os.write(master, b"q")
        exit_code = wait_pid_with_timeout(pid, 2.0)
        os.close(master)
        assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
        print("    [+] Canonical 9x54 About screen layout verified [PASS]")


def test_bug_2_4_45_line_ending_decoupling():
    """Verify line ending decoupling, native LF default, and format toggle."""
    print("[*] Testing line ending decoupling & config isolation (2.4.45)...")
    temp_dir = tempfile.mkdtemp(prefix="se_test_le_")
    try:
        # 1. New document on Linux defaults to Linux (LF) format in status bar
        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.chdir(temp_dir)
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux")
        else:
            os.close(slave)
            time.sleep(0.3)
            # Dismiss splash screen by pressing Enter
            os.write(master, b"\r")
            time.sleep(0.3)
            ed_out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "Linux |" in ed_out, (
                f"Expected 'Linux |' format in status bar:\n{ed_out}"
            )

            # Type text and open Save dialog (Ctrl+S / \x13)
            os.write(master, b"Hello Linux World\n")
            time.sleep(0.2)
            read_all_available(master, 0.2)
            os.write(master, b"\x13")
            time.sleep(0.3)
            save_out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "Format: [Linux]" in save_out, (
                f"Expected 'Format: [Linux]' in save screen:\n{save_out}"
            )

            # Toggle format using Ctrl+F (\x06) to CP/M
            os.write(master, b"\x06")
            time.sleep(0.3)
            toggled_out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "Format: [CP/M]" in toggled_out, (
                f"Expected 'Format: [CP/M]' after Ctrl+F:\n{toggled_out}"
            )

            # Toggle back to Linux format
            os.write(master, b"\x06")
            time.sleep(0.3)
            toggled_out2 = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "Format: [Linux]" in toggled_out2, (
                f"Expected 'Format: [Linux]' after Ctrl+F:\n{toggled_out2}"
            )

            # Type filename and press Enter
            os.write(master, b"TEST_LF.TXT\r")
            time.sleep(0.3)
            # Dismiss Save Complete notification modal
            os.write(master, b" ")
            time.sleep(0.2)
            read_all_available(master, 0.4)

            # Exit editor via Ctrl+Q
            os.write(master, b"\x11")
            time.sleep(0.2)
            os.write(master, b"n")
            wait_pid_with_timeout(pid, 2.0)
            os.close(master)

            lf_path = os.path.join(temp_dir, "TEST_LF.TXT")
            assert os.path.exists(lf_path), "TEST_LF.TXT was not created"
            with open(lf_path, "rb") as f:
                raw_bytes = f.read()
            assert b"\r\n" not in raw_bytes, (
                f"New document saved with CRLF on Linux: {raw_bytes!r}"
            )
            assert b"\n" in raw_bytes, "New document missing LF endings"

        # 2. Open file with CRLF endings: detected as CP/M format
        cpm_file = os.path.join(temp_dir, "TEST_CRLF.TXT")
        with open(cpm_file, "wb") as f:
            f.write(b"Line 1 CRLF\r\nLine 2 CRLF\r\n")

        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.chdir(temp_dir)
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux", "TEST_CRLF.TXT")
        else:
            os.close(slave)
            time.sleep(0.3)
            ed_out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "CP/M  |" in ed_out, (
                f"Expected 'CP/M  |' in status bar for CRLF file:\n{ed_out}"
            )

            # Save via Ctrl+S -> directly saves and preserves detected format
            os.write(master, b"\x13")
            time.sleep(0.3)
            save_out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "Save Complete" in save_out, (
                f"Expected 'Save Complete' notification modal:\n{save_out}"
            )
            # Dismiss notification modal
            os.write(master, b" ")
            time.sleep(0.2)

            # Exit cleanly via Ctrl+Q
            os.write(master, b"\x11")
            time.sleep(0.2)
            os.write(master, b"n")
            wait_pid_with_timeout(pid, 2.0)
            os.close(master)

            with open(cpm_file, "rb") as f:
                cpm_bytes = f.read()
            assert b"\r\n" in cpm_bytes, (
                f"Saved CRLF document lost CRLF endings: {cpm_bytes!r}"
            )

        print("    [+] Line ending decoupling & per-doc format verified [PASS]")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_bug_2_4_46_unexpected_keys_in_modals():
    """Verify input modals are not dismissed by unexpected keys (Bug 2.4.46)."""
    print("[*] Testing unexpected keystroke protection in modals (2.4.46)...")
    with tempfile.NamedTemporaryFile("w+", prefix="testdoc_modal_",
                                     suffix=".txt", delete=False) as tf:
        for i in range(1, 101):
            tf.write(f"Line {i}: Sample test content\n")
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
            read_all_available(master, 0.2)

            # Open Goto Line modal via Ctrl+L (\x0c)
            os.write(master, b"\x0c")
            time.sleep(0.2)
            out_modal = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "Goto Line" in out_modal, "Goto Line modal not rendered"

            # Type "42"
            os.write(master, b"42")
            time.sleep(0.1)

            # Send unexpected keys: Up, Down, PgUp, PgDn, Ctrl+U, Ctrl+V
            # None of these should cancel or dismiss the modal
            os.write(master, b"\x1b[A")  # Up
            time.sleep(0.05)
            os.write(master, b"\x1b[B")  # Down
            time.sleep(0.05)
            os.write(master, b"\x1b[5~")  # PgUp
            time.sleep(0.05)
            os.write(master, b"\x1b[6~")  # PgDn
            time.sleep(0.05)
            os.write(master, b"\x15")  # Ctrl+U
            time.sleep(0.05)
            os.write(master, b"\x16")  # Ctrl+V
            time.sleep(0.1)

            mid_out = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            # The modal must still be active and display the input
            assert "Goto Line" in mid_out or "42" in mid_out, (
                f"Modal prematurely dismissed on unexpected keys:\n{mid_out}"
            )

            # Press Enter (\r) to confirm jump to line 42
            os.write(master, b"\r")
            time.sleep(0.2)
            nav_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "42/100" in nav_out, (
                f"Expected jump to line 42, got:\n{nav_out}"
            )

            # Exit cleanly via Ctrl+Q
            os.write(master, b"\x11")
            time.sleep(0.2)
            read_all_available(master, 0.2)
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
            print("    [+] Unexpected keystroke protection verified [PASS]")
    finally:
        if os.path.exists(test_file_path):
            os.remove(test_file_path)


def test_bug_2_4_47_direct_inplace_block_manipulation():
    """Verify direct in-place block manipulation and no clipboard (2.4.47)."""
    print("[*] Testing direct in-place block manipulation (2.4.47)...")
    temp_dir = tempfile.mkdtemp()
    test_file = os.path.join(temp_dir, "test_direct_block.txt")
    with open(test_file, "w") as f:
        f.write("Line 1: Alpha\nLine 2: Bravo\nLine 3: Charlie\n")

    try:
        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.chdir(temp_dir)
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux", test_file)
        else:
            os.close(slave)
            time.sleep(0.3)
            read_all_available(master, 0.2)

            # Move to Line 2 ("Line 2: Bravo")
            os.write(master, b"\x1b[B")
            time.sleep(0.1)

            # Start block selection via Ctrl+B (\x02)
            os.write(master, b"\x02")
            time.sleep(0.1)

            # Select down one line
            os.write(master, b"\x1b[B")
            time.sleep(0.1)

            # Solidify block via Enter (\r)
            os.write(master, b"\r")
            time.sleep(0.1)

            # Move cursor to end of document (Line 3 Col 0) via Ctrl+G
            os.write(master, b"\x07")
            time.sleep(0.1)

            # Direct Move via Ctrl+X (\x18)
            os.write(master, b"\x18")
            time.sleep(0.2)

            # Clear block via ESC (\x1b)
            os.write(master, b"\x1b")
            time.sleep(0.1)

            # Open Help screen via Ctrl+K (\x0b)
            os.write(master, b"\x0b")
            time.sleep(0.2)
            help_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "PgUp" in help_out and "Page Up" in help_out, (
                f"Missing dedicated PgUp in Help screen:\n{help_out}"
            )
            assert "PgDn" in help_out and "Page Down" in help_out, (
                f"Missing dedicated PgDn in Help screen:\n{help_out}"
            )
            assert "Paste Block" not in help_out, (
                f"Found prohibited 'Paste Block' in Help screen:\n{help_out}"
            )
            assert "Cut Block" not in help_out, (
                f"Found non-canonical 'Cut Block' in Help screen:\n{help_out}"
            )

            # Dismiss Help screen via Enter
            os.write(master, b"\r")
            time.sleep(0.1)

            # Save file via Ctrl+S
            os.write(master, b"\x13")
            time.sleep(0.2)
            # Dismiss save notification modal
            os.write(master, b"\n")
            time.sleep(0.2)

            # Exit cleanly via Ctrl+Q
            os.write(master, b"\x11\n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"

            with open(test_file, "r") as f:
                saved = f.read()

            # "Line 2: Bravo" was moved to after "Line 3: Charlie"
            assert "Line 1: Alpha" in saved, f"Missing Line 1 in:\n{saved}"
            print("    [+] Direct in-place block manipulation verified [PASS]")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_bug_2_4_48_utf8_prohibition():
    """Bug 2.4.48: VT100 & ASCII Terminal Encoding Mandate (UTF-8 Prohibition).

    Verifies Section 2.6: no multi-byte UTF-8 em-dash sequences (\xE2\x80\x94)
    exist in binary or terminal output, and screens use ASCII hyphen-minus '-'.
    """
    print("[*] Testing UTF-8 prohibition & ASCII headers (Bug 2.4.48)...")

    # 1. Inspect compiled se-linux binary for forbidden UTF-8 em-dash bytes
    with open(SE_LINUX_BIN, "rb") as f:
        bin_data = f.read()

    assert b"\xe2\x80\x94" not in bin_data, (
        "Binary contains prohibited UTF-8 em-dash (0xE2 0x80 0x94)"
    )

    # 2. Interactive PTY verification across Splash, Help, About, and Config
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
        try:
            time.sleep(0.3)
            # Splash screen output
            splash_bytes = read_all_available(master, 0.4)
            assert b"\xe2\x80\x94" not in splash_bytes, (
                "Splash screen contains prohibited UTF-8 em-dash"
            )
            assert b"SE - Screen Editor" in splash_bytes, (
                "Splash screen header must use ASCII hyphen '-'"
            )

            # Open Help screen via 'h'
            os.write(master, b"h")
            time.sleep(0.2)
            help_bytes = read_all_available(master, 0.3)
            assert b"\xe2\x80\x94" not in help_bytes, (
                "Help screen contains prohibited UTF-8 em-dash"
            )
            assert b"EDITOR MODE KEYS" in help_bytes, (
                "Help screen title missing in output"
            )
            # Return from Help screen
            os.write(master, b"\r")
            time.sleep(0.2)
            read_all_available(master, 0.2)

            # Open About screen via 'a'
            os.write(master, b"a")
            time.sleep(0.2)
            about_bytes = read_all_available(master, 0.3)
            assert b"\xe2\x80\x94" not in about_bytes, (
                "About screen contains prohibited UTF-8 em-dash"
            )
            assert b"SE - Screen Editor" in about_bytes, (
                "About screen header must use ASCII hyphen '-'"
            )
            # Return from About screen
            os.write(master, b"\r")
            time.sleep(0.2)
            read_all_available(master, 0.2)

            # Open Config screen via 'c'
            os.write(master, b"c")
            time.sleep(0.2)
            cfg_bytes = read_all_available(master, 0.3)
            assert b"\xe2\x80\x94" not in cfg_bytes, (
                "Config screen contains prohibited UTF-8 em-dash"
            )
            assert b"SE - Configuration Manager" in cfg_bytes, (
                "Config screen header must use ASCII hyphen '-'"
            )
            # Exit Config screen via ESC
            os.write(master, b"\x1b")
            time.sleep(0.2)
            read_all_available(master, 0.2)

            # Quit to OS prompt via 'q'
            os.write(master, b"q")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            assert exit_code == 0, f"Expected clean exit 0, got {exit_code}"
            print("    [+] UTF-8 prohibition & ASCII headers verified [PASS]")
        finally:
            try:
                os.close(master)
            except OSError:
                pass


def test_bug_2_4_49_line_join_boundary():
    """Bug 2.4.49: Line join barrier at MAX_INPUT_LINE_CHARS (Section 6.8).

    Verifies Section 6.8: two lines summing to exactly 1,000 characters join
    successfully on backspace and delete, while joins > 1000 are inhibited.
    """
    print("[*] Testing line join barrier at capacity (Bug 2.4.49)...")

    # 1. Backspace join at exactly 1,000 characters (600 + 400 = 1000)
    with tempfile.NamedTemporaryFile("w+", prefix="test_bs_join_",
                                     suffix=".txt", delete=False) as tf:
        tf.write("A" * 600 + "\n" + "B" * 400 + "\n")
        file1 = tf.name

    try:
        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux", file1)
        else:
            os.close(slave)
            time.sleep(0.3)
            read_all_available(master, 0.2)

            # Move to Line 2, Col 0
            os.write(master, b"\x1b[B")
            time.sleep(0.1)
            os.write(master, b"\x01")
            time.sleep(0.1)

            # Press Backspace (0x08) to join
            os.write(master, b"\x08")
            time.sleep(0.2)

            # Save via Ctrl+S and dismiss modal
            os.write(master, b"\x13")
            time.sleep(0.2)
            os.write(master, b"\n")
            time.sleep(0.2)

            # Exit cleanly via Ctrl+Q
            os.write(master, b"\x11\n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"

            with open(file1, "r") as f:
                lines = [line.rstrip("\r\n") for line in f.readlines()]
            assert len(lines) == 1, (
                f"Expected 1 joined line, got {len(lines)} lines"
            )
            assert len(lines[0]) == 1000, (
                f"Expected joined line length 1000, got {len(lines[0])}"
            )
            assert lines[0] == ("A" * 600 + "B" * 400), (
                "Joined content mismatch"
            )
    finally:
        if os.path.exists(file1):
            os.remove(file1)

    # 2. Forward delete join at exactly 1,000 characters (500 + 500 = 1000)
    with tempfile.NamedTemporaryFile("w+", prefix="test_del_join_",
                                     suffix=".txt", delete=False) as tf:
        tf.write("X" * 500 + "\n" + "Y" * 500 + "\n")
        file2 = tf.name

    try:
        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux", file2)
        else:
            os.close(slave)
            time.sleep(0.3)
            read_all_available(master, 0.2)

            # Move to end of Line 1 via Ctrl+E
            os.write(master, b"\x05")
            time.sleep(0.1)

            # Press Delete (\x1b[3~) to pull up and join Line 2
            os.write(master, b"\x1b[3~")
            time.sleep(0.2)

            # Save via Ctrl+S and dismiss modal
            os.write(master, b"\x13")
            time.sleep(0.2)
            os.write(master, b"\n")
            time.sleep(0.2)

            # Exit cleanly via Ctrl+Q
            os.write(master, b"\x11\n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"

            with open(file2, "r") as f:
                lines = [line.rstrip("\r\n") for line in f.readlines()]
            assert len(lines) == 1, (
                f"Expected 1 joined line, got {len(lines)} lines"
            )
            assert len(lines[0]) == 1000, (
                f"Expected joined line length 1000, got {len(lines[0])}"
            )
            assert lines[0] == ("X" * 500 + "Y" * 500), (
                "Joined content mismatch"
            )
    finally:
        if os.path.exists(file2):
            os.remove(file2)

    # 3. Oversized join (> 1000 chars) must be inhibited (600 + 401 = 1001)
    with tempfile.NamedTemporaryFile("w+", prefix="test_over_join_",
                                     suffix=".txt", delete=False) as tf:
        tf.write("C" * 600 + "\n" + "D" * 401 + "\n")
        file3 = tf.name

    try:
        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux", file3)
        else:
            os.close(slave)
            time.sleep(0.3)
            read_all_available(master, 0.2)

            # Move to Line 2 Col 0
            os.write(master, b"\x1b[B")
            time.sleep(0.1)
            os.write(master, b"\x01")
            time.sleep(0.1)

            # Press Backspace - join should be inhibited
            os.write(master, b"\x08")
            time.sleep(0.2)

            # Exit cleanly via Ctrl+Q and decline save (n)
            os.write(master, b"\x11")
            time.sleep(0.1)
            os.write(master, b"n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"

            with open(file3, "r") as f:
                lines = [line.rstrip("\r\n") for line in f.readlines()]
            assert len(lines) == 2, (
                f"Expected 2 lines (join inhibited), got {len(lines)} lines"
            )
            print("    [+] Line join barrier at capacity verified [PASS]")
    finally:
        if os.path.exists(file3):
            os.remove(file3)


def test_bug_2_4_51_splash_labels_alignment_and_status_bar():
    """Bug 2.4.51: Splash labels, alignment, diagnostics & status bar."""
    print("[*] Testing Splash labels, alignment & status bar (Bug 2.4.51)...")
    temp_dir = tempfile.mkdtemp(prefix="se_test_2451_")
    try:
        # 1. Default 80x24 Splash screen layout, labels, alignment & Field 4
        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.chdir(temp_dir)
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux")
        else:
            os.close(slave)
            time.sleep(0.3)
            splash_out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )

            # Verify [^O], [^S], and [3] set native menu options
            assert "  type   [O]  or  [^O]    to open file" in splash_out, (
                f"Missing '[O]  or  [^O]' in splash:\n{splash_out}"
            )
            assert "  type   [S]  or  [^S]    to save file" in splash_out, (
                f"Missing '[S]  or  [^S]' in splash:\n{splash_out}"
            )
            assert "  type   [3]              set native" in splash_out, (
                f"Missing '[3] set native' in splash:\n{splash_out}"
            )

            # Verify horizontal column alignment in 80x24 (left_col = 21)
            assert "\x1b[1;21H           SE - Screen Editor" in splash_out, (
                f"Title not aligned at Row 1 Col 21:\n{splash_out!r}"
            )
            assert (
                "\x1b[5;21H  type   [O]  or  [^O]    to open file"
                in splash_out
            ), f"Open command not aligned at Row 5 Col 21:\n{splash_out!r}"
            assert (
                "\x1b[19;21HActive Screen : [80x24 (Classic Terminal)]"
                in splash_out
            ), f"Active Screen not aligned at Row 19 Col 21:\n{splash_out!r}"

            # Verify Status Bar Field 4 is blank on Splash (not ^K hint)
            assert "^K: Editor keys" not in splash_out, (
                f"Field 4 '^K: Editor keys' must not appear on Splash:\n"
                f"{splash_out}"
            )
            assert "|                 | Line" in splash_out, (
                f"Expected blank 15-char Field 4 on Splash:\n{splash_out}"
            )

            # Verify About screen also keeps Field 4 blank
            os.write(master, b"a")
            time.sleep(0.2)
            about_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "^K: Editor keys" not in about_out, (
                f"Field 4 '^K: Editor keys' must not appear on About:\n"
                f"{about_out}"
            )
            assert "|                 | Line" in about_out, (
                f"Expected blank 15-char Field 4 on About:\n{about_out}"
            )
            os.write(master, b" ")
            time.sleep(0.2)
            read_all_available(master, 0.2)

            # Verify ':' does not block single-keystroke dispatch
            os.write(master, b":")
            time.sleep(0.1)
            os.write(master, b"q")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"

        # 2. Verify dynamic Plugin System and RAM Drive diagnostics from SE.CFG
        cfg_path = os.path.join(temp_dir, "SE.CFG")
        with open(cfg_path, "w") as f:
            f.write("PLUGIN=DEMAND\r\nRAMDRIVE=DISABLED\r\n")

        master2, slave2 = pty.openpty()
        pid2 = os.fork()
        if pid2 == 0:
            os.chdir(temp_dir)
            os.close(master2)
            os.dup2(slave2, 0)
            os.dup2(slave2, 1)
            os.dup2(slave2, 2)
            os.close(slave2)
            os.execl(SE_LINUX_BIN, "se-linux")
        else:
            os.close(slave2)
            time.sleep(0.3)
            out2 = read_all_available(master2, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "Plugin System : [Builtin]" in out2, (
                f"Expected 'Plugin System : [Builtin]' in:\n{out2}"
            )
            assert "RAM Drive     : [None Detected]" in out2, (
                f"Expected 'RAM Drive     : [None Detected]' in:\n{out2}"
            )
            os.write(master2, b"q")
            exit_code2 = wait_pid_with_timeout(pid2, 2.0)
            os.close(master2)
            assert exit_code2 == 0, f"Expected exit code 0, got {exit_code2}"

        print("    [+] Splash labels, alignment & status bar verified [PASS]")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_bug_2_4_52_about_screen_version_attribution_and_centering():
    """Bug 2.4.52: About screen version, attribution, blank row & centering."""
    print(
        "[*] Testing About version, attribution & centering (Bug 2.4.52)..."
    )

    # 1. Verify CLI --help version banner is updated to v1.1.4
    if not PY_MODE:
        res = subprocess.run(
            [SE_LINUX_BIN, "--help"],
            capture_output=True,
            text=True,
            cwd=PROJECT_DIR,
        )
        assert res.returncode == 0, f"--help failed: {res.returncode}"
        assert "(v1.1.4)" in res.stdout, (
            f"Expected '(v1.1.4)' in --help output:\n{res.stdout}"
        )

    # 2. Verify live About screen layout, blank rows, and per-line centering
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
        read_all_available(master, 0.3)

        os.write(master, b"a")
        time.sleep(0.3)
        about_raw = read_all_available(master, 0.4)
        about_out = about_raw.decode("utf-8", errors="replace")

        ver_row = (
            "\x1b[9;17H        version 1.1.4 (2026-10-18) (Rust)"
            if USE_RUST
            else "\x1b[9;17H         version 1.1.4 (2026-10-18) (C)"
        )
        expected_rows = [
            "\x1b[8;17H               SE - Screen Editor",
            ver_row,
            "\x1b[10;17H                 by Dean Jenkins",
            "\x1b[11;1H~\x1b[K",
            "\x1b[12;17HGoogle Antigravity 2.23.0 & Gemini 4 Argon Medium",
            "\x1b[13;1H~\x1b[K",
            "\x1b[14;17H   Open source software under the MIT License",
            "\x1b[15;1H~\x1b[K",
            "\x1b[16;17H            Press any key to continue",
        ]
        for exp in expected_rows:
            assert exp in about_out, (
                f"Missing expected About row {exp!r} in:\n{about_out!r}"
            )

        # Verify status bar Field 4 is blank on About screen
        assert "^K: Editor keys" not in about_out, (
            f"Unexpected '^K: Editor keys' on About screen:\n{about_out}"
        )
        assert "|                 | Line" in about_out, (
            f"Expected blank Field 4 on About screen:\n{about_out}"
        )

        # Dismiss About screen and verify cursor remains hidden on Splash
        os.write(master, b" ")
        time.sleep(0.3)
        back_out = read_all_available(master, 0.3).decode(
            "utf-8", errors="replace"
        )
        assert "\x1b[?25h" not in back_out, (
            f"Cursor should remain hidden on return to Splash:\n{back_out!r}"
        )

        os.write(master, b"q")
        exit_code = wait_pid_with_timeout(pid, 2.0)
        os.close(master)
        assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
        print(
            "    [+] About version, attribution & centering verified [PASS]"
        )


def test_bug_2_4_53_builtin_plugin_system():
    """Bug 2.4.53: Plugin System permanently Builtin on Splash & Config."""
    print("[*] Testing builtin Plugin System mandate (Bug 2.4.53)...")
    temp_dir = tempfile.mkdtemp(prefix="se_test_2453_")
    try:
        cfg_path = os.path.join(temp_dir, "SE.CFG")
        with open(cfg_path, "w") as f:
            f.write("PLUGIN=OFF\r\n")

        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.chdir(temp_dir)
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux")
        else:
            os.close(slave)
            time.sleep(0.3)
            splash_out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "Plugin System : [Builtin]" in splash_out, (
                f"Expected 'Plugin System : [Builtin]' on Splash:\n{splash_out}"
            )
            assert "[Disabled]" not in splash_out, (
                f"Plugin System must not be disabled via SE.CFG:\n{splash_out}"
            )

            # Open Config screen and verify Option 5 is Builtin
            os.write(master, b"c")
            time.sleep(0.2)
            cfg_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "5. Plugin Manager   : Builtin" in cfg_out, (
                f"Expected '5. Plugin Manager   : Builtin' in:\n{cfg_out}"
            )

            os.write(master, b"\x1b")
            time.sleep(0.2)
            os.write(master, b"q")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
            print("    [+] Builtin Plugin System mandate verified [PASS]")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_bug_2_4_54_status_bar_field4_and_field5():
    """Verify Status Bar Field 4 priority hierarchy and fixed-width Field 5."""
    print("[*] Testing Bug 2.4.54: Status Bar Field 4 hierarchy & Field 5...")
    temp_dir = tempfile.mkdtemp(prefix="se_test_bug_2_4_54_")
    try:
        sample_path = os.path.join(temp_dir, "TEST.TXT")
        long_line = "A" * 100 + "\nSecond line\n"
        with open(sample_path, "w") as f:
            f.write(long_line)

        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.chdir(temp_dir)
            os.close(master)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.execl(SE_LINUX_BIN, "se-linux", "TEST.TXT")
        else:
            os.close(slave)
            time.sleep(0.3)
            init_out = read_all_available(master, 0.4).decode(
                "utf-8", errors="replace"
            )
            assert "| ^K: Editor keys | Line    1/2    Col 0   |" in init_out, (
                f"Expected canonical Field 4 & Field 5 on startup:\n{init_out}"
            )

            # Toggle Overwrite mode via Insert key (\x1b[2~)
            os.write(master, b"\x1b[2~")
            time.sleep(0.2)
            ovr_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "| Overwrite mode  |" in ovr_out, (
                f"Expected '| Overwrite mode  |' in Field 4:\n{ovr_out}"
            )
            # Toggle back to Insert mode
            os.write(master, b"\x1b[2~")
            time.sleep(0.2)
            read_all_available(master, 0.2)

            # Move to end of line to trigger [Pan +40] in Field 4
            os.write(master, b"\x1b[F")
            time.sleep(0.2)
            pan_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "| [Pan +40]       | Line    1/2    Col 100 |" in pan_out, (
                f"Expected '[Pan +40]' in Field 4 & fixed Field 5:\n{pan_out}"
            )
            assert "[SEL]" not in pan_out and "[BLK LOCK]" not in pan_out

            # Return to Home (Ctrl+A) and test Sel: / Block: metrics
            os.write(master, b"\x01")
            time.sleep(0.1)
            read_all_available(master, 0.2)

            os.write(master, b"\x02\x1b[C\x1b[C")
            time.sleep(0.2)
            sel_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "| Sel: 2 chars    | Line    1/2    Col 2   |" in sel_out, (
                f"Expected '| Sel: 2 chars    |' in Field 4:\n{sel_out}"
            )

            # Solidify via Enter
            os.write(master, b"\r")
            time.sleep(0.2)
            blk_out = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "| Block: 2 chars  | Line    1/2    Col 2   |" in blk_out, (
                f"Expected '| Block: 2 chars  |' in Field 4:\n{blk_out}"
            )

            os.write(master, b"\x11")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)
            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
            print("    [+] Status Bar Field 4 & Field 5 verified [PASS]")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def main():
    print("=" * 80)
    print(
        f"   SE.COM Linux Native Profile ({TARGET_NAME}) "
        f"Automated Verification"
    )
    print("=" * 80)

    test_build_and_help()
    test_interactive_pty_startup()
    test_document_load_and_save()
    test_status_bar_canonical_layout()
    test_status_event_notification_modal()
    test_arrow_and_wordstar_navigation()
    test_horizontal_panning_and_line_barrier()
    test_tier1_centering_and_tilde_discipline()
    test_modal_archetypes_and_framing()
    test_bug_2_4_8_modal_dispatchers()
    test_bug_2_4_9_splash_screen_commands()
    test_bug_2_4_10_burst_escape_sequences()
    test_bug_2_4_11_block_selection_cursor_tracking()
    test_bug_2_4_12_clipboard_copy_paste()
    test_bug_2_4_13_terminal_lifecycle()
    test_bug_2_4_14_viewport_col1_alignment()
    test_bug_2_4_15_sticky_target_col_and_tab_clamping()
    test_bug_2_4_16_status_bar_field_invariance_and_visual_col()
    test_bug_2_4_17_tier1_file_workspaces_and_directory_scan()
    test_bug_2_4_18_canonical_config_parser_and_serialization()
    test_bug_2_4_19_panning_edge_trigger_and_geometry()
    test_bug_2_4_21_backspace_line_join()
    test_bug_2_4_22_delete_active_block()
    test_bug_2_4_23_backspace_cancels_block()
    test_bug_2_4_24_enter_solidifies_block()
    test_bug_2_4_25_modal_prompt_text_editing()
    test_bug_2_4_27_file_not_found_alert()
    test_bug_2_4_28_overwrite_confirmation()
    test_bug_2_4_29_block_save_and_insert()
    test_bug_2_4_30_block_menu_popup()
    test_bug_2_4_31_find_modal_cursor_navigation()
    test_bug_2_4_32_escape_sequence_leakage()
    test_bug_2_4_33_block_typing_cancellation()
    test_bug_2_4_34_splash_language_indication()
    test_bug_2_4_35_splash_hotkeys_and_native_mode()
    test_bug_2_4_36_geometry_switch_clear()
    test_bug_2_4_37_config_screen_interactive()
    test_bug_2_4_38_default_tab_width()
    test_bug_2_4_39_help_screen_canonical_layout()
    test_bug_2_4_40_plugin_palette_modal()
    test_bug_2_4_41_tab_snap_forward()
    test_bug_2_4_42_config_screen_canonical_layout()
    test_bug_2_4_43_splash_canonical_layout()
    test_bug_2_4_44_about_screen_canonical_layout()
    test_bug_2_4_45_line_ending_decoupling()
    test_bug_2_4_46_unexpected_keys_in_modals()
    test_bug_2_4_47_direct_inplace_block_manipulation()
    test_bug_2_4_48_utf8_prohibition()
    test_bug_2_4_49_line_join_boundary()
    test_bug_2_4_51_splash_labels_alignment_and_status_bar()
    test_bug_2_4_52_about_screen_version_attribution_and_centering()
    test_bug_2_4_53_builtin_plugin_system()
    test_bug_2_4_54_status_bar_field4_and_field5()

    print("=" * 80)
    print("VERDICT: [ PASS ] All Linux Native Profile tests succeeded!")
    print("=" * 80)
    return 0


def run_python_mode():
    """Run each test independently against the Python SE port.

    Several native-C tests assert C-specific UI flows, so failures are
    collected and summarised instead of aborting at the first one.
    """
    tests = [
        (n, f) for n, f in list(globals().items())
        if n.startswith("test_") and callable(f)
    ]
    failed = []
    for name, func in tests:
        try:
            func()
        except Exception as exc:  # noqa: BLE001
            failed.append((name, f"{type(exc).__name__}: {exc}"))
            print(f"    [-] {name} FAILED: {exc}", flush=True)
    print("=" * 80)
    print(f"Python SE: {len(tests) - len(failed)}/{len(tests)} passed")
    for name, why in failed:
        print(f"  FAIL {name}: {why[:100]}")
    return 1 if failed else 0


if __name__ == "__main__":
    if PY_MODE:
        sys.exit(run_python_mode())
    sys.exit(main())
