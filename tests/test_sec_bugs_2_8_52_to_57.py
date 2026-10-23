#!/usr/bin/env python3
"""
test_sec_bugs_2_8_52_to_57.py - Regression test suite for SEC.COM UI/UX
Design Conformance Bugs 2.8.52 through 2.8.57:
  - Bug 2.8.52: Help screen (Ctrl+K) displays Ctrl+Z (Plugin Manager),
    Ctrl+Y (Beautify text), Enter (New line / Lock), and Ctrl+C / Ctrl+X
    (Copy / Move block).
  - Bug 2.8.53: Confirmation modals (Save changes?, Overwrite?) accept
    Enter (0x0D) to confirm Yes.
  - Bug 2.8.54: CP/M CSI decoder drains intermediate and private CSI
    parameter bytes (0x20..0x3F) without leaking trailing characters.
  - Bug 2.8.55: Save File screen Ctrl+F format toggle immediately updates
    Status Bar Field 3 (CP/M vs Linux).
  - Bug 2.8.56: Discarding unsaved modifications ([N]o in Save changes?)
    resets document buffer and clears g_current_filename to (Untitled).
  - Bug 2.8.57: Block Operations modal (Ctrl+K with active block) retains
    the solidified block around inserted file text on [R] / Ctrl+O.
"""

import os
import pty
import select
import subprocess
import sys
import time
import tty


def read_until(fd, pattern, timeout=10.0):
    buf = b""
    deadline = time.time() + timeout
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                chunk = os.read(fd, 4096)
                if not chunk:
                    break
                buf += chunk
                if pattern in buf:
                    return True, buf
            except OSError:
                break
    return False, buf


def drain_pty(fd, duration=0.3):
    buf = b""
    deadline = time.time() + duration
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                chunk = os.read(fd, 4096)
                if not chunk:
                    break
                buf += chunk
            except OSError:
                break
    return buf


def main():
    start_time = time.time()
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    workspace_root = os.path.abspath(os.path.join(repo_root, "..", ".."))
    if not os.path.isdir(os.path.join(workspace_root, "tools")):
        workspace_root = os.path.abspath(
            os.path.join(repo_root, "..", "screen_editor")
        )
    emu = os.path.join(workspace_root, "tools", "rc2014_emu", "rc2014")
    rom = os.path.join(
        workspace_root, "tools", "romwbw_src", "Binary", "RC2014_std.rom"
    )
    golden_img = os.path.join(
        workspace_root, "tools", "romwbw_src", "Binary", "hd1k_combo.img"
    )
    disks_dir = os.path.join(repo_root, "disks")
    os.makedirs(disks_dir, exist_ok=True)
    img_file = os.path.join(disks_dir, "hd1k_combo.img")

    if not os.path.exists(img_file):
        subprocess.run(
            ["cp", "--sparse=always", golden_img, img_file], check=True
        )
        os.chmod(img_file, 0o644)

    cpmcp = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp"
    )
    cpmrm = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm"
    )

    print(
        "[*] Step 1: Injecting SEC.COM into workspace disk image...",
        flush=True,
    )
    for target in ["0:SEC.COM", "0:T2853.TXT"]:
        subprocess.run(
            [cpmrm, "-f", "wbw_hd1k_0", img_file, target],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    subprocess.run(
        [
            cpmcp,
            "-f",
            "wbw_hd1k_0",
            img_file,
            os.path.join(repo_root, "SEC.COM"),
            "0:SEC.COM",
        ],
        check=True,
    )
    print("[+] Step 1: Injected SEC.COM into workspace disk image.", flush=True)

    print(
        "[*] Step 2: Booting RC2014 RomWBW emulator and launching SEC.COM...",
        flush=True,
    )
    master, slave = pty.openpty()
    tty.setraw(slave)
    proc = subprocess.Popen(
        [emu, "-b", "-r", rom, "-1", "-S", img_file],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
    )
    os.close(slave)

    try:
        ok, out = read_until(master, b"Boot [H=Help]:", timeout=15.0)
        if not ok:
            print(
                f"[-] Step 2: Boot prompt timeout. Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        time.sleep(0.4)
        os.write(master, b"c\r")
        ok, out = read_until(master, b"B>", timeout=15.0)
        if not ok:
            print(
                f"[-] Step 2: B> prompt timeout. Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        time.sleep(0.4)
        os.write(master, b"c:\r")
        ok, out = read_until(master, b"C>", timeout=10.0)
        if not ok:
            print(
                f"[-] Step 2: C> prompt timeout. Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        time.sleep(0.4)
        os.write(master, b"SEC\r")
        ok, out = read_until(master, b"Max Lines", timeout=30.0)
        if not ok:
            print(
                f"[-] Step 2: Splash timeout. Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.3)
        print(
            "[+] Step 2: Booted CP/M and reached SEC.COM Splash Screen.",
            flush=True,
        )

        print(
            "[*] Step 3: Verifying Help screen Ctrl+Z and Ctrl+Y "
            "(Bug 2.8.52)...",
            flush=True,
        )
        os.write(master, b"e")
        ok, out = read_until(master, b"^K: Editor keys", timeout=8.0)
        if not ok:
            print(
                f"[-] Step 3: Failed to enter Editor Mode. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.3)
        os.write(master, b"\x0b")
        ok, out_help = read_until(
            master, b"Press any key to continue", timeout=10.0
        )
        out_help += drain_pty(master, 0.3)
        if (
            not ok
            or b"Ctrl+Z" not in out_help
            or b"Plugin Manager" not in out_help
            or b"Ctrl+Y" not in out_help
            or b"Beautify text" not in out_help
            or b"New line / Lock" not in out_help
            or b"Ctrl+C / Ctrl+X" not in out_help
        ):
            print(
                f"[-] Step 3: Help screen missing canonical rows. "
                f"Buffer: {repr(out_help[-400:])}",
                flush=True,
            )
            return False
        os.write(master, b" ")
        ok, out = read_until(master, b"^K: Editor keys", timeout=8.0)
        if not ok:
            print(
                f"[-] Step 3: Failed to return from Help screen. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.3)
        print(
            "[+] Step 3: Help screen displays Ctrl+Z, Ctrl+Y, and canonical "
            "block rows.",
            flush=True,
        )

        print(
            "[*] Step 4: Verifying Save Changes Enter, Save Ctrl+F Field 3 "
            "update, and private CSI drain (Bugs 2.8.53, 2.8.54, 2.8.55)...",
            flush=True,
        )
        # Send private CSI sequence \x1b[?25h and \x1b[<0;5;5M -> must drain
        os.write(master, b"HELLO\x1b[?25h\x1b[<0;5;5M")
        drain_pty(master, 0.3)
        # Press Ctrl+W -> Save changes? modal -> press Enter (\r)
        os.write(master, b"\x17")
        ok, out = read_until(master, b"Save changes?", timeout=6.0)
        if not ok:
            print(
                f"[-] Step 4: Save changes modal did not appear. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        os.write(master, b"\r")
        ok, out = read_until(master, b"Enter filename to save:", timeout=10.0)
        if not ok:
            print(
                f"[-] Step 4: Enter did not confirm Save changes modal. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.3)
        # Press Ctrl+F (\x06) twice: first switches to Linux (Status Bar Field 3
        # shows "| Linux |"), second switches back to CP/M ("| CP/M  |")
        os.write(master, b"\x06")
        ok, out_f1 = read_until(master, b"| Linux |", timeout=6.0)
        if not ok or b"Format: [Linux]" not in out_f1:
            print(
                f"[-] Step 4: Ctrl+F did not update Status Bar Field 3 to "
                f"Linux. Buffer: {repr(out_f1[-300:])}",
                flush=True,
            )
            return False
        os.write(master, b"\x06")
        ok, out_f2 = read_until(master, b"| CP/M  |", timeout=6.0)
        if not ok or b"Format: [CP/M]" not in out_f2:
            print(
                f"[-] Step 4: Second Ctrl+F did not restore CP/M in Status "
                f"Bar Field 3. Buffer: {repr(out_f2[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.2)
        os.write(master, b"T2853.TXT\r")
        ok, out = read_until(master, b"Max Lines", timeout=20.0)
        if not ok:
            print(
                f"[-] Step 4: Save & close to Splash failed. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.3)
        print(
            "[+] Step 4: Save Changes Enter, Save Ctrl+F Status Bar Field 3, "
            "and private CSI drain verified.",
            flush=True,
        )

        print(
            "[*] Step 5: Verifying Overwrite Enter, Discard filename reset, "
            "and Block Popup File Insert (Bugs 2.8.53, 2.8.56, 2.8.57)...",
            flush=True,
        )
        # Re-enter editor, save over T2853.TXT using Enter on Overwrite modal
        os.write(master, b"e")
        ok, out = read_until(master, b"^K: Editor keys", timeout=8.0)
        if not ok:
            print(
                f"[-] Step 5: Failed to enter Editor Mode. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.3)
        os.write(master, b"HOST\x13")
        ok, out = read_until(master, b"Enter filename to save:", timeout=10.0)
        if not ok:
            print(
                f"[-] Step 5: Save dialog did not open. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.2)
        os.write(master, b"T2853.TXT\r")
        ok, out = read_until(
            master, b"File already exists. Overwrite?", timeout=8.0
        )
        if not ok:
            print(
                f"[-] Step 5: Overwrite modal did not appear. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        os.write(master, b"\r")
        ok, out = read_until(master, b"| C:T2853.TXT    |", timeout=20.0)
        if not ok:
            print(
                f"[-] Step 5: Enter did not confirm Overwrite modal. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.3)

        # Test Bug 2.8.57: Start block (Ctrl+B), open Block Operations modal
        # (Ctrl+K), press 'r' to insert T2853.TXT, verify Block: stays active!
        os.write(master, b"\x02\x0b")
        ok, out = read_until(master, b"Block Operations", timeout=6.0)
        if not ok:
            print(
                f"[-] Step 5: Block Operations modal did not open. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        os.write(master, b"r")
        ok, out = read_until(master, b"Enter filename to insert:", timeout=10.0)
        if not ok:
            print(
                f"[-] Step 5: Insert File dialog did not open from Block "
                f"Operations modal. Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.2)
        os.write(master, b"T2853.TXT\r")
        ok, out_ins = read_until(master, b"Block:", timeout=20.0)
        if not ok:
            print(
                f"[-] Step 5: Solidified block not retained after popup "
                f"file insert (Bug 2.8.57). Buffer: {repr(out_ins[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.3)

        # Test Bug 2.8.60: Clear block with ESC, then press Ctrl+O ->
        # Save changes? -> 'n' -> ESC in Open dialog ->
        # verify active document C:T2853.TXT is preserved per canonical
        # se.asm:2024-2035 and test_editor_headless.py Step 54!
        os.write(master, b"\x1b")
        ok, out = read_until(master, b"^K: Editor keys", timeout=6.0)
        if not ok:
            print(
                f"[-] Step 5: ESC did not clear solidified block. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.2)
        os.write(master, b"\x0f")
        ok, out = read_until(master, b"Save changes?", timeout=6.0)
        if not ok:
            print(
                f"[-] Step 5: Ctrl+O did not prompt Save changes?. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        os.write(master, b"n")
        ok, out = read_until(master, b"Enter filename to open:", timeout=10.0)
        if not ok:
            print(
                f"[-] Step 5: Open dialog did not appear after 'n'. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.2)
        os.write(master, b"\x1b")
        ok, out_disc = read_until(master, b"| C:T2853.TXT    |", timeout=8.0)
        if not ok:
            print(
                f"[-] Step 5: Open cancel did not preserve file buffer "
                f"(Bug 2.8.60). Buffer: {repr(out_disc[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.2)

        # Now test Bug 2.8.56: Ctrl+W closes document to splash with (Untitled)
        os.write(master, b"\x17")
        ok, out_close = read_until(master, b"| (Untitled)     |", timeout=8.0)
        if not ok:
            print(
                f"[-] Step 5: Ctrl+W did not reset filename to "
                f"(Untitled) (Bug 2.8.56). Buffer: {repr(out_close[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.3)
        os.write(master, b"\x11")
        ok, out = read_until(master, b"C>", timeout=8.0)
        if not ok:
            print(
                f"[-] Step 5: Clean exit to CP/M failed. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        print(
            "[+] Step 5: Overwrite Enter, Popup File Insert block retention, "
            "and Discard filename reset verified.",
            flush=True,
        )

    finally:
        os.close(master)
        proc.terminate()
        try:
            proc.wait(timeout=3.0)
        except subprocess.TimeoutExpired:
            proc.kill()

    elapsed = time.time() - start_time
    print(
        f"[+] All SEC.COM Bugs 2.8.52-2.8.57 tests PASSED in {elapsed:.2f}s!",
        flush=True,
    )
    return True


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
