#!/usr/bin/env python3
"""
test_bugs_2_1_21_to_27.py - Regression test suite for SE.COM UI/UX Design
Conformance Bugs 2.1.21 and 2.1.23 through 2.1.27:
  - Bug 2.1.21: HELP.OVL lists Ctrl+Z (Plugin Manager) and Ctrl+Y (Beautify
    text) within the canonical 22-line (17-body-line) Tier 1 layout.
  - Bug 2.1.23: READ_FILENAME_INPUT maps Ctrl+D to forward delete and drops
    prohibited WordStar navigation keys (Ctrl+S, Ctrl+G, Ctrl+B).
  - Bug 2.1.24: PLUGIN.PRL drops prohibited WordStar (Ctrl+E, Ctrl+X) and Vi
    (J, K) navigation keys while preserving Up/Down arrow navigation.
  - Bug 2.1.25: REPLACE_CONFIRM_KEY drains multi-byte escape sequences (such
    as arrow keys) instead of aborting Replace and leaking bytes.
  - Bug 2.1.26: DO_SAVE_CHANGES_POPUP and OVERWRITE_KEY_LOOP accept Enter
    (0x0D) to confirm Yes.
  - Bug 2.1.27: INPUT_HANDLE_CSI and DNL_CSI drain unhandled multi-byte CSI
    sequences (e.g. F5 ESC[15~, modified arrows ESC[1;5D) via DRAIN_CSI_TAIL.
"""

import os
import pty
import select
import shutil
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
        "[*] Step 1: Verifying HELP.OVL 17-line body layout (Bug 2.1.21)...",
        flush=True,
    )
    help_ovl = os.path.join(repo_root, "plugins", "HELP.OVL")
    with open(help_ovl, "rb") as f:
        ovl_data = f.read()

    title_marker = b"EDITOR MODE KEYS\r\n$"
    t_idx = ovl_data.find(title_marker)
    if t_idx == -1:
        print(
            "[-] Step 1: STR_HELP_TITLE missing in HELP.OVL.",
            flush=True,
        )
        return False
    b_start = t_idx + len(title_marker)
    b_end = ovl_data.find(b"$", b_start)
    body_str = ovl_data[b_start:b_end].decode("ascii")
    body_lines = body_str.split("\r\n")[:-1]
    if (
        len(body_lines) != 17
        or "Ctrl+Z" not in body_str
        or "Plugin Manager" not in body_str
        or "Ctrl+Y" not in body_str
        or "Beautify text" not in body_str
    ):
        print(
            f"[-] Step 1: Invalid HELP.OVL body ({len(body_lines)} lines). "
            f"Buffer: {repr(body_str)}",
            flush=True,
        )
        return False
    print(
        "[+] Step 1: HELP.OVL verified (17 body lines with Ctrl+Z & Ctrl+Y).",
        flush=True,
    )

    print(
        "[*] Step 2: Injecting SE.COM, HELP.OVL, and PLUGIN.PRL to disk...",
        flush=True,
    )
    for target in ["0:SE.COM", "0:HELP.OVL", "0:PLUGIN.PRL", "0:T2127.TXT"]:
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
            os.path.join(repo_root, "SE.COM"),
            "0:SE.COM",
        ],
        check=True,
    )
    subprocess.run(
        [
            cpmcp,
            "-f",
            "wbw_hd1k_0",
            img_file,
            help_ovl,
            "0:HELP.OVL",
        ],
        check=True,
    )
    subprocess.run(
        [
            cpmcp,
            "-f",
            "wbw_hd1k_0",
            img_file,
            os.path.join(repo_root, "plugins", "PLUGIN.PRL"),
            "0:PLUGIN.PRL",
        ],
        check=True,
    )
    print(
        "[+] Step 2: Injected SE.COM, HELP.OVL, and PLUGIN.PRL into disk.",
        flush=True,
    )

    print(
        "[*] Step 3: Booting RC2014 RomWBW emulator and launching SE.COM...",
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
                f"[-] Step 3: Boot prompt timeout. Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        time.sleep(0.4)
        os.write(master, b"c\r")
        ok, out = read_until(master, b"B>", timeout=15.0)
        if not ok:
            print(
                f"[-] Step 3: B> prompt timeout. Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        time.sleep(0.4)
        os.write(master, b"c:\r")
        ok, out = read_until(master, b"C>", timeout=10.0)
        if not ok:
            print(
                f"[-] Step 3: C> prompt timeout. Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        time.sleep(0.4)
        os.write(master, b"SE\r")
        ok, out = read_until(master, b"Max Lines", timeout=30.0)
        if not ok:
            print(
                f"[-] Step 3: Splash timeout. Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.3)
        print(
            "[+] Step 3: Booted CP/M and reached SE.COM Splash Screen.",
            flush=True,
        )

        print(
            "[*] Step 4: Testing Plugin Manager WordStar/Vi key removal "
            "(Bug 2.1.24)...",
            flush=True,
        )
        os.write(master, b"p")
        ok, out = read_until(master, b"SE - Plugin Manager", timeout=8.0)
        if not ok:
            print(
                f"[-] Step 4: Failed to open Plugin Manager. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.3)
        # Send 'j', 'k', Ctrl+E (0x05), Ctrl+X (0x18) -> should be ignored
        os.write(master, b"jk\x05\x18")
        out_ignored = drain_pty(master, 0.4)
        if b"[1]" in out_ignored:
            print(
                f"[-] Step 4: Prohibited Vi/WordStar keys moved selection. "
                f"Buffer: {repr(out_ignored)}",
                flush=True,
            )
            return False
        # Down arrow (\x1b[B) should move to slot [1]
        os.write(master, b"\x1b[B")
        ok, out_arrow = read_until(master, b"\x1b[7m", timeout=4.0)
        if not ok:
            print(
                f"[-] Step 4: Down arrow failed in Plugin Manager. "
                f"Buffer: {repr(out_arrow)}",
                flush=True,
            )
            return False
        os.write(master, b"q")
        ok, out = read_until(master, b"Max Lines", timeout=6.0)
        if not ok:
            print(
                f"[-] Step 4: Failed to exit Plugin Manager. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.3)
        print(
            "[+] Step 4: Plugin Manager ignores J/K/^E/^X and honors arrows.",
            flush=True,
        )

        print(
            "[*] Step 5: Testing Replace Confirmation multi-byte ESC drain "
            "(Bug 2.1.25)...",
            flush=True,
        )
        os.write(master, b"e")
        ok, out = read_until(master, b"^K: Editor keys", timeout=6.0)
        if not ok:
            print(
                f"[-] Step 5: Failed to enter Editor Mode. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.3)
        os.write(master, b"FOO BAR\rSECOND LINE")
        drain_pty(master, 0.3)
        # Move to top of file (Ctrl+T, Ctrl+A) -> commits line 0 to Far RAM!
        os.write(master, b"\x14\x01")
        drain_pty(master, 0.3)
        # Start Ctrl+R: find "FOO", then replace with "BAZ"
        os.write(master, b"\x12")
        ok, out = read_until(master, b"[ESC]=Cancel", timeout=6.0)
        if not ok:
            print(
                f"[-] Step 5: Find modal did not appear. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        time.sleep(0.1)
        os.write(master, b"FOO\r")
        ok, out = read_until(master, b"Replace with:", timeout=6.0)
        if not ok:
            print(
                f"[-] Step 5: Replace with modal did not appear. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        time.sleep(0.1)
        os.write(master, b"BAZ\r")
        ok, out = read_until(master, b"Replace this occurrence?", timeout=6.0)
        if not ok:
            print(
                f"[-] Step 5: Replace Confirm modal did not appear. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.2)
        # Send Up Arrow (\x1b[A) -> must be drained and NOT abort Replace
        os.write(master, b"\x1b[A")
        out_esc_seq = drain_pty(master, 0.4)
        if b"Replace Done" in out_esc_seq or b"Replace done:" in out_esc_seq:
            print(
                f"[-] Step 5: Arrow key prematurely aborted Replace. "
                f"Buffer: {repr(out_esc_seq)}",
                flush=True,
            )
            return False
        # Now confirm replacement with Enter (\r)
        os.write(master, b"\r")
        ok, out = read_until(
            master, b"Replace done: 1 replacement(s).", timeout=6.0
        )
        if not ok:
            print(
                f"[-] Step 5: Enter did not complete Replace after arrow key. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        os.write(master, b" ")
        drain_pty(master, 0.3)
        print(
            "[+] Step 5: Replace Confirmation drained arrow key and "
            "substituted cleanly.",
            flush=True,
        )

        print(
            "[*] Step 6: Testing Save Changes Enter confirmation and Browser "
            "Ctrl+D / CSI drain (Bugs 2.1.23, 2.1.26, 2.1.27)...",
            flush=True,
        )
        # Press Ctrl+W to close modified untitled file -> Save Changes popup
        os.write(master, b"\x17")
        ok, out = read_until(master, b"Save changes?", timeout=6.0)
        if not ok:
            print(
                f"[-] Step 6: Save Changes modal did not appear. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        # Press Enter (\r) -> should confirm Yes and open Save File browser!
        os.write(master, b"\r")
        ok, out = read_until(master, b"Enter filename to save:", timeout=8.0)
        if not ok:
            print(
                f"[-] Step 6: Enter did not confirm Save Changes modal. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.2)
        # In Save File input box (pre-filled with "C0:"):
        # 1) Type "XT2127.TXT" -> "C0:XT2127.TXT"
        # 2) Press Ctrl+A (Home) then Right x 3 -> cursor on 'X'
        # 3) Press Ctrl+D (Delete at cursor) -> deletes 'X' -> "C0:T2127.TXT"
        # 4) Send F5 (\x1b[15~) and Ctrl+Left (\x1b[1;5D) -> must be drained
        #    without leaking '~' or '5D' into the filename!
        # 5) Press Enter (\r) -> saves "T2127.TXT" and closes to Splash Screen
        os.write(
            master,
            b"XT2127.TXT\x01\x1b[C\x1b[C\x1b[C\x04\x1b[15~\x1b[1;5D\r",
        )
        ok, out = read_until(master, b"Max Lines", timeout=20.0)
        if not ok:
            print(
                f"[-] Step 6: Save & Close via Ctrl+D / CSI drain failed. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.3)
        print(
            "[+] Step 6: Save Changes Enter, Browser Ctrl+D delete, and "
            "5-byte CSI drain verified.",
            flush=True,
        )

        print(
            "[*] Step 7: Testing Overwrite Confirmation via Enter "
            "(Bug 2.1.26)...",
            flush=True,
        )
        # Re-enter editor, type "NEW", press Ctrl+S, enter "T2127.TXT\r",
        # and confirm Overwrite modal with Enter (\r)
        os.write(master, b"e")
        ok, out = read_until(master, b"^K: Editor keys", timeout=6.0)
        if not ok:
            print(
                f"[-] Step 7: Failed to re-enter Editor Mode. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.3)
        os.write(master, b"UPDATED LINE\x13")
        ok, out = read_until(master, b"Enter filename to save:", timeout=8.0)
        if not ok:
            print(
                f"[-] Step 7: Save File screen did not appear. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.2)
        os.write(master, b"T2127.TXT\r")
        ok, out = read_until(
            master, b"File already exists. Overwrite?", timeout=6.0
        )
        if not ok:
            print(
                f"[-] Step 7: Overwrite modal did not appear. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        # Confirm overwrite with Enter (\r)
        os.write(master, b"\r")
        ok, out = read_until(master, b"^K: Editor keys", timeout=20.0)
        if not ok or b"C:T2127.TXT" not in out:
            print(
                f"[-] Step 7: Enter did not confirm Overwrite modal. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        drain_pty(master, 0.3)
        # Quit to CP/M (Ctrl+Q)
        os.write(master, b"\x11")
        ok, out = read_until(master, b"C>", timeout=8.0)
        if not ok:
            print(
                f"[-] Step 7: Failed to quit cleanly to CP/M. "
                f"Buffer: {repr(out[-300:])}",
                flush=True,
            )
            return False
        print(
            "[+] Step 7: Overwrite modal confirmed with Enter and saved "
            "T2127.TXT.",
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
        f"[+] All Bugs 2.1.21 and 2.1.23-2.1.27 tests PASSED in "
        f"{elapsed:.2f}s!",
        flush=True,
    )
    return True


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
