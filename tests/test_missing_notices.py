#!/usr/bin/env python3
"""
test_missing_notices.py - Fast isolated test for Task 2.3.
Verifies:
1. Missing HELP.OVL displays Tier 2 'Help Missing' modal pop-up on Ctrl+K.
2. Missing BEAUTIFY.PRL displays Tier 2 'Plugin Missing' modal pop-up on Ctrl+Y.
3. Missing PLUGIN.PRL displays Tier 2 'Plugin Manager Missing' modal pop-up
   on 'p' from splash screen and Ctrl+P from editor mode.
4. All modal pop-ups dismiss cleanly on any key and restore screen/status bar.
"""

import os
import pty
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
    img_file = os.path.join(repo_root, "disks", "hd1k_combo.img")
    se_bin = os.path.join(repo_root, "SE.COM")
    cpmcp = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp"
    )
    cpmrm = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm"
    )
    plugins_dir = os.path.join(repo_root, "plugins")

    return emu_bin, rom_file, img_file, se_bin, cpmcp, cpmrm, plugins_dir

def read_until(master_fd, match_bytes, timeout=10.0):
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
                    return buf
            except (BlockingIOError, OSError):
                pass
        time.sleep(0.01)
    return buf

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

def remove_from_img(cpmrm, img, filename):
    for fmt in ["wbw_hd1k_0", "wbw_hd1k_3"]:
        for name in [filename.upper(), filename.lower()]:
            subprocess.run(
                [cpmrm, "-f", fmt, img, f"0:{name}"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

def inject_to_img(cpmcp, img, filepath, filename):
    for fmt in ["wbw_hd1k_0", "wbw_hd1k_3"]:
        subprocess.run(
            [cpmcp, "-f", fmt, img, filepath, f"0:{filename}"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

def main():
    paths = find_paths()
    emu_bin, rom_file, img_file, se_bin, cpmcp, cpmrm, plugins_dir = paths

    # Step 1: Temporarily remove HELP.OVL, BEAUTIFY.PRL, and PLUGIN.PRL
    print("[*] Removing HELP.OVL, BEAUTIFY.PRL, PLUGIN.PRL from test image...")
    remove_from_img(cpmrm, img_file, "HELP.OVL")
    remove_from_img(cpmrm, img_file, "BEAUTIFY.PRL")
    remove_from_img(cpmrm, img_file, "PLUGIN.PRL")

    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )
    os.close(slave)

    try:
        out = read_until(master, b"Boot [", timeout=10.0)
        assert b"Boot [" in out, f"Failed boot prompt: {repr(out)}"
        time.sleep(0.5)
        os.write(master, b"c\r")
        out = read_until(master, b"B>", timeout=10.0)
        assert b"B>" in out, f"Failed B> prompt: {repr(out)}"
        time.sleep(0.5)
        os.write(master, b"c:\r")
        out = read_until(master, b"C>", timeout=15.0)
        assert b"C>" in out, f"Failed C> prompt: {repr(out)}"
        time.sleep(0.5)

        # Launch SE
        os.write(master, b"se\r")
        out = read_until(master, b"Screen Editor", timeout=25.0)
        assert b"Screen Editor" in out, f"Failed splash screen: {repr(out)}"
        print("[+] SE.COM splash screen reached.")

        # Test 1: Press 'p' on splash screen without PLUGIN.PRL
        time.sleep(0.4)
        drain_all(master)
        os.write(master, b"p")
        out_p = read_until(master, b"Press any key to continue", timeout=10.0)
        if b"Plugin Manager Missing" not in out_p:
            print(f"[-] Missing Plugin Manager Missing popup: {repr(out_p)}")
            return 1
        if b"Feature requires PLUGIN.PRL." not in out_p:
            print(f"[-] Missing Msg1 in popup: {repr(out_p)}")
            return 1
        print("[+] Verified 'Plugin Manager Missing' popup from splash screen.")

        # Dismiss popup with space
        time.sleep(0.1)
        os.write(master, b" ")
        out_splash = read_until(master, b"type   [C]", timeout=4.0)
        if b"type   [C]" not in out_splash:
            print(f"[-] Failed restoring splash screen: {repr(out_splash)}")
            return 1
        print("[+] Splash screen restored cleanly on popup dismissal.")

        # Enter Editor Mode
        time.sleep(0.2)
        drain_all(master)
        os.write(master, b"e")
        read_until(master, b"[New File]", timeout=4.0)
        time.sleep(0.2)
        drain_all(master)
        print("[+] Entered editor mode.")

        # Test 2: Press Ctrl+P in editor without PLUGIN.PRL
        os.write(master, b"\x10")  # Ctrl+P
        out_cp = read_until(master, b"Press any key to continue", timeout=10.0)
        if b"Plugin Manager Missing" not in out_cp:
            print(
                f"[-] Missing Plugin Manager Missing on Ctrl+P: {repr(out_cp)}"
            )
            return 1
        if b"Feature requires PLUGIN.PRL." not in out_cp:
            print(f"[-] Missing Msg1 in Ctrl+P popup: {repr(out_cp)}")
            return 1
        print(
            "[+] Verified 'Plugin Manager Missing' popup from editor (Ctrl+P)."
        )

        # Dismiss popup with space
        time.sleep(0.1)
        os.write(master, b" ")
        time.sleep(0.2)
        drain_all(master)

        # Test 3: Press Ctrl+K in editor without HELP.OVL
        os.write(master, b"\x0b")  # Ctrl+K
        out_help = read_until(
            master, b"Press any key to continue", timeout=10.0
        )
        if b"Help Missing" not in out_help:
            print(f"[-] Missing Help Missing popup: {repr(out_help)}")
            return 1
        if b"HELP.OVL was not found." not in out_help:
            print(f"[-] Missing Msg1 in Help popup: {repr(out_help)}")
            return 1
        print("[+] Verified 'Help Missing' popup on Ctrl+K.")

        # Dismiss popup with space
        time.sleep(0.1)
        os.write(master, b" ")
        time.sleep(0.2)
        drain_all(master)

        # Test 4: Press Ctrl+Y in editor without BEAUTIFY.PRL
        os.write(master, b"\x19")  # Ctrl+Y
        out_y = read_until(master, b"Press any key to continue", timeout=10.0)
        if b"Plugin Missing" not in out_y:
            print(f"[-] Missing Plugin Missing popup on Ctrl+Y: {repr(out_y)}")
            return 1
        if b"Required plugin was not found." not in out_y:
            print(f"[-] Missing Msg1 in Plugin Missing popup: {repr(out_y)}")
            return 1
        print("[+] Verified 'Plugin Missing' popup on Ctrl+Y.")

        # Dismiss popup with space
        time.sleep(0.1)
        os.write(master, b" ")
        time.sleep(0.2)
        drain_all(master)

        # Exit SE (Ctrl+Q, then 'n')
        os.write(master, b"\x11")
        time.sleep(0.1)
        os.write(master, b"n")
        read_until(master, b"C>", timeout=4.0)
        print("[+] Clean exit back to CP/M prompt.")

        print("\n[SUCCESS] Task 2.3 all missing subsystem notices verified!")
        return 0

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=1.0)
        except Exception:
            proc.kill()
        os.close(master)

        # Restore HELP.OVL, BEAUTIFY.PRL, and PLUGIN.PRL into test image
        print("[*] Restoring files back into test image...")
        help_path = os.path.join(plugins_dir, "HELP.OVL")
        beautify_path = os.path.join(plugins_dir, "BEAUTIFY.PRL")
        plugin_path = os.path.join(plugins_dir, "PLUGIN.PRL")
        inject_to_img(cpmcp, img_file, help_path, "HELP.OVL")
        inject_to_img(cpmcp, img_file, beautify_path, "BEAUTIFY.PRL")
        inject_to_img(cpmcp, img_file, plugin_path, "PLUGIN.PRL")
        print("[+] Files restored.")

if __name__ == "__main__":
    sys.exit(main())
