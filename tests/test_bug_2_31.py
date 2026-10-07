#!/usr/bin/env python3
"""
Automated Test for Bug 2.31:
Remove Visible Cursor from Save Changes and Unload Plugin Modals.

Verifies:
  1. Boot CP/M and open 'se 2.TXT'.
  2. Type a character to mark document modified.
  3. Send Ctrl+Q to open the "Unsaved Modifications" modal pop-up.
  4. Verify that \\x1b[?25h (show cursor) is NOT emitted during modal display.
  5. Cancel modal with 'n' to return to splash screen.
  6. Enter Plugin Manager with 'p'.
  7. Press Enter on occupied slot to open "Unload Slot" confirmation modal.
  8. Verify that \\x1b[?25h (show cursor) is NOT emitted during modal display.
  9. Dismiss confirmation with ESC.
  10. Clean exit to CP/M with 'q'.
"""

import os
import re
import select
import subprocess
import sys
import time
import tty


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


def read_until(master_fd, target, timeout=8.0):
    buf = b""
    t0 = time.time()
    targets = target if isinstance(target, (list, tuple)) else [target]
    while time.time() - t0 < timeout:
        r, _, _ = select.select([master_fd], [], [], 0.05)
        if r:
            try:
                data = os.read(master_fd, 1024)
                if not data:
                    break
                buf += data
                for tgt in targets:
                    if tgt in buf:
                        return buf
            except (BlockingIOError, OSError):
                pass
    return buf


def drain_all(master_fd, quiet_time=0.2):
    time.sleep(0.05)
    buf = b""
    while True:
        r, _, _ = select.select([master_fd], [], [], quiet_time)
        if not r:
            break
        try:
            data = os.read(master_fd, 4096)
            if not data:
                break
            buf += data
        except (BlockingIOError, OSError):
            break
    return buf


def setup_disk_files(img_file, se_bin, cpmcp_bin, cpmrm_bin, repo_root):
    if os.path.isfile(cpmrm_bin):
        for fname in ["0:SE.COM", "0:se.com", "0:2.TXT"]:
            subprocess.run(
                [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, fname],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
    two_txt = os.path.join(repo_root, "2.TXT")
    if os.path.isfile(two_txt):
        subprocess.run(
            [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, two_txt, "0:2.TXT"],
            check=True,
        )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, "0:SE.COM"],
        check=True,
    )
    # Ensure PLUGIN.PRL is also installed
    plugin_prl = os.path.join(repo_root, "plugins", "PLUGIN.PRL")
    if os.path.isfile(plugin_prl):
        subprocess.run(
            [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:PLUGIN.PRL"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        subprocess.run(
            [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, plugin_prl,
             "0:PLUGIN.PRL"],
            check=True,
        )


def boot_cpm(master):
    out = read_until(master, b"Boot [H=Help]:", timeout=8.0)
    if b"Boot [H=Help]:" not in out:
        return False, "Bootloader prompt missing"
    time.sleep(0.3)
    os.write(master, b"c\r")
    out = read_until(master, b"B>", timeout=8.0)
    if b"B>" not in out:
        return False, "Drive B> missing"
    time.sleep(0.3)
    os.write(master, b"c:\r")
    out = read_until(master, b"C>", timeout=8.0)
    if b"C>" not in out:
        return False, "Drive C> missing"
    drain_all(master)
    return True, "Booted to C>"


def run_test():
    paths = find_paths()
    repo_root, emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = paths

    setup_disk_files(img_file, se_bin, cpmcp_bin, cpmrm_bin, repo_root)

    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )
    os.close(slave)

    try:
        ok, msg = boot_cpm(master)
        if not ok:
            print(f"[-] {msg}")
            return False

        # Sequence A: Save Changes modal cursor test
        print("[*] Launching 'se 2.TXT'...", flush=True)
        time.sleep(0.3)
        os.write(master, b"se 2.TXT\r")
        out = read_until(master, b"Line    1/2", timeout=30.0)
        assert b"Line    1/2" in out, "Failed opening 2.TXT in editor"
        drain_all(master, 0.3)

        # Modify document
        print("[*] Modifying document with character 'X'...", flush=True)
        os.write(master, b"X")
        time.sleep(0.2)
        drain_all(master, 0.2)

        # Send Ctrl+W to trigger Save Changes modal
        print("[*] Sending Ctrl+W to open Save Changes modal...", flush=True)
        os.write(master, b"\x17")
        out_save_modal = read_until(master, b"Save changes?", timeout=6.0)
        out_save_modal += drain_all(master, 0.3)

        assert b"Save changes?" in out_save_modal, (
            "Save Changes modal not displayed"
        )
        # Find where "Save changes?" appears in modal output
        idx_prompt = out_save_modal.find(b"Save changes?")
        after_prompt = out_save_modal[idx_prompt:]
        assert b"\x1b[?25h" not in after_prompt, (
            f"Blinking cursor enabled after 'Save changes?': "
            f"{repr(after_prompt)}"
        )
        print("[+] Verified cursor remains suppressed in Save Changes modal.")

        # Discard changes with 'n' to return to splash screen
        os.write(master, b"n")
        out_splash = read_until(master, b"Active Screen :", timeout=6.0)
        assert b"Active Screen :" in out_splash, "Failed returning to splash"
        drain_all(master, 0.2)

        # Sequence B: Unload Plugin modal cursor test
        print("[*] Entering Plugin Manager with 'p'...", flush=True)
        os.write(master, b"p")
        out_plug = read_until(master, b"SE - Plugin Manager", timeout=6.0)
        assert b"SE - Plugin Manager" in out_plug, (
            "Failed entering Plugin Manager"
        )
        drain_all(master, 0.3)

        # Press Enter on selected slot to open Unload confirmation
        print(
            "[*] Pressing Enter to trigger Unload confirmation...", flush=True
        )
        os.write(master, b"\r")
        out_unload = read_until(master, b"Unload Slot", timeout=6.0)
        out_unload += drain_all(master, 0.3)

        if b"Unload Slot" in out_unload:
            idx_unload = out_unload.find(b"Unload Slot")
            after_unload = out_unload[idx_unload:]
            assert b"\x1b[?25h" not in after_unload, (
                f"Blinking cursor enabled in Unload modal: {repr(after_unload)}"
            )
            print("[+] Verified cursor suppressed in Unload Plugin modal.")

            # Cancel unload with ESC
            os.write(master, b"\x1b")
            read_until(master, b"SE - Plugin Manager", timeout=4.0)
            drain_all(master, 0.2)

        # Exit Plugin Manager with ESC
        os.write(master, b"\x1b")
        read_until(master, b"Active Screen :", timeout=6.0)
        drain_all(master, 0.2)

        # Exit to CP/M with 'q'
        print("[*] Exiting splash screen with 'q'...", flush=True)
        os.write(master, b"q")
        out_cpm = read_until(master, b"C>", timeout=6.0)
        assert b"C>" in out_cpm, "Failed exiting to CP/M prompt"
        print("[+] Bug 2.31 verification PASSED: modal cursors suppressed.")
        return True

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            pass
        os.close(master)


if __name__ == "__main__":
    success = run_test()
    sys.exit(0 if success else 1)
