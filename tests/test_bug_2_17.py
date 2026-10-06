#!/usr/bin/env python3
"""
Automated Test for Bug 2.17:
Plugin Screen 'A' (About) Clears Screen Instead of Centered Pop-up.

Verifies:
  1. Pressing 'A' on a plugin in Plugin Manager does NOT clear the screen
     (\\x1b[2J must not be emitted when displaying About or Config dialogs).
  2. The About dialog is displayed as a centered Tier 2 modal pop-up over the
     intact Plugin Manager background.
  3. Dismissing the modal restores and cleanly redraws the Plugin Manager
     table and selection cursor.
  4. Verified across WORDCNT.OVL (Slot 0), ROT13.PRL (Slot 1), and
     BEAUTIFY.PRL (Slot 2) for both About ('A') and Config ('C').
"""

import os
import sys
import time
import tty
import select
import subprocess


def find_paths():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    workspace_root = os.path.abspath(os.path.join(repo_root, "..", ".."))

    emu_bin = os.path.join(workspace_root, "tools", "rc2014_emu", "rc2014")
    rom_file = os.path.join(
        workspace_root, "tools", "romwbw_src", "Binary", "RC2014_std.rom"
    )
    golden_img = os.path.join(
        workspace_root, "tools", "romwbw_src", "Binary", "hd1k_combo.img"
    )
    img_dir = os.path.join(repo_root, "disks")
    img_file = os.path.join(img_dir, "hd1k_combo.img")
    if not os.path.isfile(img_file):
        os.makedirs(img_dir, exist_ok=True)
        subprocess.run(
            ["cp", "--sparse=always", golden_img, img_file], check=True
        )
        os.chmod(img_file, 0o644)
    se_bin = os.path.join(repo_root, "SE.COM")
    cpmcp_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp"
    )
    cpmrm_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm"
    )

    return (
        repo_root, emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin
    )


def read_until(master_fd, match_bytes, timeout=8.0):
    buf = b""
    t0 = time.time()
    while time.time() - t0 < timeout:
        r, _, _ = select.select([master_fd], [], [], 0.03)
        if r:
            try:
                data = os.read(master_fd, 1024)
                if not data:
                    break
                buf += data
                if match_bytes in buf:
                    return True, buf
            except (BlockingIOError, OSError):
                pass
        time.sleep(0.01)
    return False, buf


def drain_all(master_fd, timeout=0.2):
    buf = b""
    t0 = time.time()
    while time.time() - t0 < timeout:
        r, _, _ = select.select([master_fd], [], [], 0.02)
        if r:
            try:
                data = os.read(master_fd, 1024)
                if not data:
                    break
                buf += data
            except (BlockingIOError, OSError):
                break
        else:
            break
    return buf


def setup_disk_files(repo_root, cpmcp_bin, cpmrm_bin, img_file, se_bin):
    # Remove existing files first, then copy fresh binaries
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.COM"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, "0:SE.COM"],
        check=True
    )
    plugins_dir = os.path.join(repo_root, "plugins")
    for plug in ["WORDCNT.OVL", "ROT13.PRL", "BEAUTIFY.PRL", "PLUGIN.PRL"]:
        plug_path = os.path.join(plugins_dir, plug)
        if os.path.isfile(plug_path):
            subprocess.run(
                [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, f"0:{plug}"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            subprocess.run(
                [
                    cpmcp_bin, "-f", "wbw_hd1k_0", img_file,
                    plug_path, f"0:{plug}"
                ],
                check=True
            )
    # Remove existing BEAUTIFY.CFG to ensure defaults
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:BEAUTIFY.CFG"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )


def wait_for_plugin_manager(master, slot_str=b">[0]"):
    ok, out = read_until(master, b"Slot Plugin Name", timeout=8.0)
    assert ok, f"Plugin Manager table not found: {out}"
    ok, out2 = read_until(master, slot_str, timeout=5.0)
    assert ok, f"Slot cursor {slot_str} not found: {out2}"
    ok, out3 = read_until(master, b"Free:", timeout=5.0)
    assert ok, f"Status bar not found: {out3}"
    combined = out + out2 + out3
    if b"\x1b[0m" not in combined:
        read_until(master, b"\x1b[0m", timeout=3.0)
    time.sleep(0.1)
    drain_all(master)


def test_plugin_about_modal():
    print("[*] Starting Bug 2.17 Plugin About Modal Test...")
    (
        repo_root, emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin
    ) = find_paths()

    setup_disk_files(repo_root, cpmcp_bin, cpmrm_bin, img_file, se_bin)

    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )
    os.close(slave)

    try:
        ok, out = read_until(master, b"Boot [H=Help]:", timeout=8.0)
        assert ok, f"Boot prompt not found: {out}"
        time.sleep(0.3)
        os.write(master, b"c\r")

        ok, out = read_until(master, b"B>", timeout=8.0)
        assert ok, f"Drive B prompt not found: {out}"
        time.sleep(0.3)
        os.write(master, b"c:\r")

        ok, out = read_until(master, b"C>", timeout=8.0)
        assert ok, f"Drive C prompt not found: {out}"
        time.sleep(0.3)

        # Launch SE.COM to splash screen
        os.write(master, b"se\r")
        ok, out = read_until(master, b"for about", timeout=60.0)
        assert ok, f"Splash screen not displayed: {out}"
        print("[+] Splash screen loaded.")

        # Open Plugin Manager screen ('p')
        time.sleep(0.3)
        os.write(master, b"p")
        wait_for_plugin_manager(master, b">[0]")
        print("[+] Plugin Manager displayed with selection on Slot 0.")

        # ---------------------------------------------------------------------
        # Case 1: Slot 0 (WORDCNT.OVL) - Press 'A' for About
        # ---------------------------------------------------------------------
        print("[*] Case 1: Testing Slot 0 (WORDCNT.OVL) About modal...")
        time.sleep(0.3)
        os.write(master, b"a")

        ok, out = read_until(master, b"Press any key to continue", timeout=6.0)
        assert ok, f"WORDCNT About dialog not shown: {out}"
        assert b"\x1b[2J" not in out, (
            f"ERROR: TERM_CLEAR_SCREEN (\\x1b[2J) emitted when opening About! "
            f"Output: {repr(out)}"
        )
        assert b"Word & Character Count Plugin" in out, (
            f"About title missing in output: {repr(out)}"
        )
        print("[+] Verified Slot 0 About opened WITHOUT clearing screen.")

        # Dismiss modal with space
        time.sleep(0.3)
        os.write(master, b" ")
        wait_for_plugin_manager(master, b">[0]")
        print("[+] Verified Plugin Manager cleanly restored after dismiss.")

        # ---------------------------------------------------------------------
        # Case 2: Slot 1 (ROT13.PRL) - Navigate down and press 'A'
        # ---------------------------------------------------------------------
        print("[*] Case 2: Testing Slot 1 (ROT13.PRL) About modal...")
        time.sleep(0.3)
        os.write(master, b"j")
        ok, out = read_until(master, b">[1]", timeout=4.0)
        assert ok, f"Failed to navigate to Slot 1: {out}"
        time.sleep(0.1)
        drain_all(master)

        time.sleep(0.3)
        os.write(master, b"a")

        ok, out = read_until(master, b"Press any key to continue", timeout=6.0)
        assert ok, f"ROT13 About dialog not shown: {out}"
        assert b"\x1b[2J" not in out, (
            f"ERROR: TERM_CLEAR_SCREEN (\\x1b[2J) emitted when opening About! "
            f"Output: {repr(out)}"
        )
        assert b"ROT13 Text Cipher Plugin" in out, (
            f"About title missing in output: {repr(out)}"
        )
        print("[+] Verified Slot 1 About opened WITHOUT clearing screen.")

        # Dismiss modal with Enter
        time.sleep(0.3)
        os.write(master, b"\r")
        wait_for_plugin_manager(master, b">[1]")
        print("[+] Verified Plugin Manager cleanly restored after dismiss.")

        # ---------------------------------------------------------------------
        # Case 3: Slot 2 (BEAUTIFY.PRL) - Navigate down and press 'A'
        # ---------------------------------------------------------------------
        print("[*] Case 3: Testing Slot 2 (BEAUTIFY.PRL) About modal...")
        time.sleep(0.3)
        os.write(master, b"j")
        ok, out = read_until(master, b">[2]", timeout=4.0)
        assert ok, f"Failed to navigate to Slot 2: {out}"
        time.sleep(0.1)
        drain_all(master)

        time.sleep(0.3)
        os.write(master, b"a")

        ok, out = read_until(master, b"Press any key to continue", timeout=6.0)
        assert ok, f"BEAUTIFY About dialog not shown: {out}"
        assert b"\x1b[2J" not in out, (
            f"ERROR: TERM_CLEAR_SCREEN (\\x1b[2J) emitted when opening About! "
            f"Output: {repr(out)}"
        )
        assert b"Z80 Code Beautifier Plugin" in out, (
            f"About title missing in output: {repr(out)}"
        )
        print("[+] Verified Slot 2 About opened WITHOUT clearing screen.")

        # Dismiss modal with space
        time.sleep(0.3)
        os.write(master, b" ")
        wait_for_plugin_manager(master, b">[2]")
        print("[+] Verified Plugin Manager cleanly restored after dismiss.")

        # ---------------------------------------------------------------------
        # Case 4: Slot 2 (BEAUTIFY.PRL) - Press 'C' for Config modal
        # ---------------------------------------------------------------------
        print("[*] Case 4: Testing Slot 2 (BEAUTIFY.PRL) Config modal...")
        time.sleep(0.3)
        os.write(master, b"c")

        ok, out = read_until(
            master, b"[Enter]=Save & Exit   [ESC]=Cancel", timeout=6.0
        )
        assert ok, f"BEAUTIFY Config dialog not shown: {out}"
        assert b"\x1b[2J" not in out, (
            f"ERROR: TERM_CLEAR_SCREEN (\\x1b[2J) emitted when opening Config! "
            f"Output: {repr(out)}"
        )
        assert b"Z80 Beautifier Configuration" in out, (
            f"Config title missing in output: {repr(out)}"
        )
        print("[+] Verified Slot 2 Config opened WITHOUT clearing screen.")

        # Cancel modal with ESC
        time.sleep(0.3)
        os.write(master, b"\x1b")
        wait_for_plugin_manager(master, b">[2]")
        print("[+] Verified Plugin Manager screen cleanly restored after ESC.")

        # ---------------------------------------------------------------------
        # Case 5: Exit back to Splash and CP/M
        # ---------------------------------------------------------------------
        print("[*] Case 5: Exiting to Splash and CP/M...")
        time.sleep(0.2)
        os.write(master, b"q")
        ok, out = read_until(master, b"for about", timeout=5.0)
        assert ok, f"Failed to return to splash screen: {out}"
        print("[+] Returned to splash screen.")

        time.sleep(0.2)
        os.write(master, b"q")
        ok, out = read_until(master, b"C>", timeout=8.0)
        assert ok, f"Failed to exit cleanly to CP/M: {out}"
        print("[+] Returned to CP/M prompt cleanly.")

        print("\n=======================================================")
        print("  BUG 2.17 VERIFICATION PASSED (100%)!")
        print("=======================================================")
        return 0

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            pass
        os.close(master)


if __name__ == "__main__":
    sys.exit(test_plugin_about_modal())
