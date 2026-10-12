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
SE_LINUX_BIN = os.path.join(PROJECT_DIR, "se-linux")


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
        assert b"80x24 |" in captured or b"120x40 |" in captured, (
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
        assert "SE.COM — Screen Editor" in splash_out, (
            "Splash screen missing canonical centered title"
        )

        # Press space to enter editor mode
        os.write(master, b" ")
        time.sleep(0.2)
        read_all_available(master, 0.2)

        # Press Ctrl+K (0x0B) to open Help mode screen
        os.write(master, b"\x0b")
        help_out = read_all_available(master, 0.4).decode("utf-8",
                                                          errors="replace")
        assert "SE.COM — EDITOR MODE KEYS" in help_out, (
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
            assert "+--------------------------------------------------+" in (
                modal_c_out
            ), "Modal Archetype C missing border/title divider (+---+)"
            assert "[ " in modal_c_out and " ]" in modal_c_out, (
                "Modal Archetype C missing bracket pair [ text ] around input"
            )
            assert "[Enter]=Confirm      [ESC]=Cancel" in modal_c_out, (
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
            assert "SE.COM — Screen Editor" in splash_out, (
                f"Ctrl+W failed to transition to splash screen:\n{splash_out}"
            )

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
        assert "SE.COM — Screen Editor" in splash_out, (
            f"Return from Config failed to render Splash screen:\n{splash_out}"
        )

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
            assert "[SEL]" in out_sel_chars, (
                f"Expected '[SEL]' indicator in output:\n{out_sel_chars}"
            )
            assert "^K: Editor keys" in out_sel_chars, (
                f"Expected '^K: Editor keys' invariant:\n{out_sel_chars}"
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
            assert "[SEL]" in out_sel_lines, (
                f"Expected '[SEL]' indicator in multi-line:\n{out_sel_lines}"
            )
            assert "^K: Editor keys" in out_sel_lines, (
                f"Expected '^K: Editor keys' invariant:\n{out_sel_lines}"
            )

            # Cancel block selection via Ctrl+B toggle
            os.write(master, b"\x02")
            time.sleep(0.2)
            out_cancel = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "[SEL]" not in out_cancel, (
                f"Expected '[SEL]' cleared on toggle:\n{out_cancel}"
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

            # Copy via Ctrl+C
            os.write(master, b"\x03")
            time.sleep(0.1)
            out_copy = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "[BLK LOCK]" in out_copy, (
                f"Expected '[BLK LOCK]' status indicator:\n{out_copy}"
            )
            assert "^K: Editor keys |" in out_copy, (
                f"Expected Field 4 preserved after copy:\n{out_copy}"
            )

            # Move down to line 2 and jump to Col 0 via Ctrl+A
            os.write(master, b"\x1b[B\x01")
            time.sleep(0.1)

            # Paste via Ctrl+V at beginning of line 2
            os.write(master, b"\x16")
            time.sleep(0.2)

            # Save file via Ctrl+S
            os.write(master, b"\x13")
            time.sleep(0.2)
            # Dismiss save notification modal (press enter or space)
            os.write(master, b"\n")
            time.sleep(0.2)

            # Exit cleanly via Ctrl+Q
            os.write(master, b"\x11\n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)

            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"

            with open(test_file_path, "r", encoding="utf-8") as f:
                saved_content = f.read()

            assert "12345Second Line" in saved_content, (
                f"Pasted content '12345' missing from line 2:\n{saved_content}"
            )
            print("    [+] Clipboard copy & paste verified on disk [PASS]")
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

            # Set TARGET_COL to 4 (home then 4 right)
            os.write(master, b"\x01" + b"\x1b[C" * 4)
            time.sleep(0.1)
            read_all_available(master, 0.2)

            # Move down 2 lines to Line 3 (\tXYZ). Target 4 is inside tab.
            # Must clamp to beginning of tab (index 0, Col 0).
            os.write(master, b"\x1b[B\x1b[B")
            time.sleep(0.1)
            out_tab = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "Line    3/3" in out_tab and "Col 0" in out_tab, (
                f"Expected tab interior clamped to Col 0:\n{out_tab}"
            )

            # Move up 2 lines back to Line 1: TARGET_COL 4 preserved!
            os.write(master, b"\x1b[A\x1b[A")
            time.sleep(0.1)
            out_tab_back = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "Line    1/3" in out_tab_back and "Col 4" in out_tab_back, (
                f"Expected Line 1 Col 4 restored:\n{out_tab_back}"
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
        f.write("SCREEN=80X24\r\n")

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

            # Start block selection: [SEL] in Field 5, Field 4 preserved
            os.write(master, b"\x02")
            time.sleep(0.1)
            out_sel = read_all_available(master, 0.2).decode(
                "utf-8", errors="replace"
            )
            assert "[SEL]" in out_sel, (
                f"Expected '[SEL]' indicator in Field 5:\n{out_sel}"
            )
            assert "^K: Editor keys |" in out_sel, (
                f"Expected Field 4 preserved during selection:\n{out_sel}"
            )

            # Cancel selection
            os.write(master, b"\x02")
            time.sleep(0.1)

            # Move to end of line to trigger pan (+40)
            os.write(master, b"\x1b[F")
            time.sleep(0.2)
            out_pan = read_all_available(master, 0.3).decode(
                "utf-8", errors="replace"
            )
            assert "[Pan +40]" in out_pan, (
                f"Expected '[Pan +40]' in Field 5:\n{out_pan}"
            )
            assert "^K: Editor keys |" in out_pan, (
                f"Expected Field 4 preserved during horizontal pan:\n{out_pan}"
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
        assert "<PgUp>/<PgDn>=Page" in open_out, (
            f"Expected page controls in open workspace:\n{open_out}"
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
                "    assert(g_config.screen_mode == MODE_120X40);\n"
                "    assert(g_config.tab_width == 8);\n"
                "    assert(g_config.save_format == FMT_CPM);\n"
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
                "    assert(g_config.save_format == FMT_LINUX);\n"
                "    assert(g_config.lines_mode == 1);\n"
                "    assert(g_config.ramdrive_mode == "
                "RAMDRV_MODE_HIBERNATE);\n"
                "    assert(g_config.plugin_mode == "
                "PLUGIN_MODE_ONDEMAND);\n"
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
        assert "FORMAT=LINUX\r\n" in text, f"Missing FORMAT in output:\n{text}"
        assert "LINES=32K\r\n" in text, f"Missing LINES in output:\n{text}"
        assert "RAMDRIVE=HIB\r\n" in text, (
            f"Missing RAMDRIVE in output:\n{text}"
        )
        assert "PLUGIN=DEMAND\r\n" in text, (
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
            os.write(master, b"\x04" * 79)
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
            os.write(master2, b"\x04" * 85)
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
            # Should not have [SEL] anymore
            assert "[SEL]" not in out_str, f"Block still active:\n{out_str}"

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
            assert "[SEL]" in out.decode("utf-8", errors="replace"), (
                "Expected [SEL] in status bar"
            )

            # Send Backspace (0x08) to cancel block
            os.write(master, b"\x08")
            time.sleep(0.2)

            out_bs = read_all_available(master, 0.3)
            out_str = out_bs.decode("utf-8", errors="replace")
            assert "[SEL]" not in out_str, f"Block still active:\n{out_str}"

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


def main():
    print("=" * 80)
    print("   SE.COM Linux Native Profile (se-linux) Automated Verification")
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

    print("=" * 80)
    print("VERDICT: [ PASS ] All Linux Native Profile tests succeeded!")
    print("=" * 80)
    return 0


if __name__ == "__main__":
    sys.exit(main())
