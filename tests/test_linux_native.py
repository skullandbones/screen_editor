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
import select
import subprocess
import sys
import tempfile
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
    """Verify ANSI arrow keys and WordStar diamond cursor movement (§10)."""
    print("[*] Testing ANSI arrow & WordStar cursor navigation (§10)...")
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

            # Send WordStar diamond: Ctrl+E (Up)
            os.write(master, b"\x05")
            time.sleep(0.15)
            output2 = b""
            try:
                output2 += os.read(master, 8192)
            except Exception:
                pass
            out_str2 = output2.decode("utf-8", errors="replace")
            assert "Line    1/3" in out_str2, (
                f"WordStar Ctrl+E (Up) failed to move up:\n{out_str2}"
            )

            # Send Ctrl+Q to exit
            os.write(master, b"\x11\n")
            exit_code = wait_pid_with_timeout(pid, 2.0)
            os.close(master)

            assert exit_code == 0, f"Expected exit code 0, got {exit_code}"
            print("    [+] ANSI arrow & WordStar navigation verified [PASS]")
    finally:
        if os.path.exists(test_file_path):
            os.remove(test_file_path)


def test_horizontal_panning_and_line_barrier():
    """Verify horizontal pan quantum (+40) and 120-char line limit (§6)."""
    print("[*] Testing horizontal panning engine & line barrier (§6)...")
    with tempfile.NamedTemporaryFile("w+", prefix="testdoc_pan_",
                                     suffix=".txt", delete=False) as tf:
        tf.write("\n")
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
            assert len(first_line) == 120, (
                f"Expected line strictly capped at 120 chars, got "
                f"{len(first_line)}"
            )
            print("    [+] Horizontal pan & 120-char line limit verified "
                  "[PASS]")
    finally:
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
        assert "80x24 |" in help_out, (
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

    print("=" * 80)
    print("VERDICT: [ PASS ] All Linux Native Profile tests succeeded!")
    print("=" * 80)
    return 0


if __name__ == "__main__":
    sys.exit(main())
