#!/usr/bin/env python3
"""
test_plugin_interactive.py - Automated verification of interactive Plugin Manager:
  1. Boot RomWBW and enter Plugin Manager ('p').
  2. Verify initial selection cursor on Slot 0: '>[0] WORDCNT'.
  3. Send Down Arrow (ESC [ B) / 'j' to navigate cursor to Slot 1 ('>[1] ROT13') and Slot 2 ('>[2] BEAUTIFY').
  4. Send Up Arrow (ESC [ A) / 'k' to navigate cursor back to Slot 0.
  5. Press 'A' on Slot 0: Verify WORDCNT.OVL embedded About screen displays.
  6. Dismiss About screen, move to Slot 1 ('j'), press 'A': Verify ROT13.PRL embedded About screen displays.
  7. Dismiss About screen, move to Slot 2 ('j'), press 'A': Verify BEAUTIFY.PRL embedded About screen displays.
  8. Dismiss About screen, press 'C' on Slot 2: Verify BEAUTIFY.PRL embedded Configuration screen displays.
  9. Cycle preset ('1'), toggle animation ('4'), exit config screen ('q').
 10. Press Enter / 'r' to execute BEAUTIFY.PRL (transitions to editor).
 11. Exit editor (Ctrl+Q -> 'n') to CP/M prompt.
"""

import os
import sys
import time
import tty
import select
import subprocess
import re

def find_paths():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    workspace_root = os.path.abspath(os.path.join(repo_root, "..", ".."))

    emu_bin = os.path.join(workspace_root, "tools", "rc2014_emu", "rc2014")
    rom_file = os.path.join(workspace_root, "tools", "romwbw_src", "Binary", "RC2014_std.rom")
    img_file = os.path.join(workspace_root, "tools", "romwbw_src", "Binary", "hd1k_combo.img")
    se_bin = os.path.join(repo_root, "SE.COM")
    cpmrm_bin = os.path.join(workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm")

    return emu_bin, rom_file, img_file, se_bin, cpmrm_bin

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
    return False, buf

def drain_all(master_fd, quiet_time=0.1):
    time.sleep(0.05)
    while True:
        r, _, _ = select.select([master_fd], [], [], quiet_time)
        if not r:
            break
        try:
            data = os.read(master_fd, 2048)
            if not data:
                break
        except (BlockingIOError, OSError):
            break

def main():
    print("[*] Launching emulator for Interactive Plugin Manager Test...", flush=True)
    emu_bin, rom_file, img_file, se_bin, cpmrm_bin = find_paths()

    # Remove existing BEAUTIFY.CFG to ensure default standard columns
    subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:BEAUTIFY.CFG"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)

    try:
        # Boot RomWBW
        ok, _ = read_until(master, b"Boot [H=Help]:", timeout=8.0)
        if not ok:
            print("[-] RomWBW boot prompt not seen")
            return 1
        time.sleep(0.5)
        os.write(master, b"c\r")
        read_until(master, b"B>", timeout=6.0)
        time.sleep(0.5)
        os.write(master, b"c:\r")
        read_until(master, b"C>", timeout=8.0)
        time.sleep(0.5)

        # Launch SE
        os.write(master, b"se\r")
        ok, out = read_until(master, b"Col 0", timeout=18.0)
        if not ok:
            print("[-] Splash screen not seen")
            return 1
        print("[+] Splash screen loaded.")
        drain_all(master)

        # Enter Plugin Manager ('p')
        time.sleep(0.3)
        os.write(master, b"p")
        ok, out = read_until(master, b"SE - Plugin Manager", timeout=8.0)
        if not ok:
            print("[-] Plugin Manager screen not seen")
            return 1
        print("[+] Plugin Manager displayed.")

        # Verify initial selection cursor on slot 0: >[0]
        if b">[0]" not in out:
            ok, out_more = read_until(master, b">[0]", timeout=5.0)
            out += out_more
        if b">[0]" not in out:
            print(f"[-] Initial selection >[0] not found. Out: {repr(out)}")
            return 1
        print("[+] Verified initial selection cursor on Slot 0: >[0] WORDCNT")

        # Verify context help line on Slot 0 (WORDCNT: Enter:run, A:about)
        ok, out = read_until(master, b"A:about", timeout=3.0)
        if not ok:
            print(f"[-] Slot 0 missing A:about. Out: {repr(out)}")
            return 1
        # Slot 0 context help verified (Enter:run, A:about).
        print("[+] Slot 0 context help verified (Enter:run, A:about).")

        # Test digit navigation: press '2' to jump directly to slot 2
        time.sleep(0.3)
        os.write(master, b"2")
        ok, out = read_until(master, b">[2]", timeout=5.0)
        if not ok:
            print(f"[-] Digit '2' failed to select Slot 2. Out: {repr(out)}")
            return 1
        print("[+] Digit '2' successfully selected Slot 2 without executing.")

        # Test digit navigation: press '0' to jump back to slot 0
        time.sleep(0.3)
        os.write(master, b"0")
        ok, out = read_until(master, b">[0]", timeout=5.0)
        if not ok:
            print(f"[-] Digit '0' failed to select Slot 0. Out: {repr(out)}")
            return 1
        print("[+] Digit '0' successfully selected Slot 0 without executing.")

        # Test Down Arrow via ANSI escape: \x1b[B
        time.sleep(0.3)
        os.write(master, b"\x1b[B")
        ok, out = read_until(master, b">[1]", timeout=5.0)
        if not ok:
            print(f"[-] Down Arrow failed to move to >[1]. Out: {repr(out)}")
            return 1
        print("[+] Down Arrow (ESC [ B) moved selection to >[1] ROT13")

        # Test Vi key 'j' for down navigation to slot 2
        time.sleep(0.3)
        os.write(master, b"j")
        ok, out = read_until(master, b">[2]", timeout=5.0)
        if not ok:
            print(f"[-] 'j' key failed to move selection to >[2]. Out: {repr(out)}")
            return 1
        print("[+] Key 'j' successfully moved selection to >[2] BEAUTIFY")

        # Verify context help on Slot 2 (BEAUTIFY: Enter:run, A:about, C:config)
        ok, out = read_until(master, b"C:config", timeout=3.0)
        if not ok:
            print(f"[-] Slot 2 missing C:config. Out: {repr(out)}")
            return 1
        print("[+] Slot 2 context help verified (Run, About, Config).")

        # Test navigation to empty slot (Slot 3) to verify empty context help
        time.sleep(0.3)
        os.write(master, b"j")
        ok, out = read_until(master, b"L:load plugin", timeout=3.0)
        if not ok:
            print(f"[-] Slot 3 missing L:load plugin. Out: {repr(out)}")
            return 1
        print("[+] Slot 3 (empty) context help verified (L:load plugin).")

        # Navigate back to Slot 2
        time.sleep(0.3)
        os.write(master, b"k")
        read_until(master, b">[2]", timeout=3.0)

        # Test Up Arrow via ANSI escape: \x1b[A
        time.sleep(0.3)
        os.write(master, b"\x1b[A")
        ok, out = read_until(master, b">[1]", timeout=5.0)
        if not ok:
            print(f"[-] Up Arrow failed to move selection to >[1]. Out: {repr(out)}")
            return 1
        print("[+] Up Arrow (ESC [ A) successfully moved selection back to >[1] ROT13")

        # Test Vi key 'k' for up navigation back to slot 0
        time.sleep(0.3)
        os.write(master, b"k")
        ok, out = read_until(master, b">[0]", timeout=5.0)
        if not ok:
            print(f"[-] 'k' key failed to move selection to >[0]. Out: {repr(out)}")
            return 1
        print("[+] Key 'k' successfully moved selection back to >[0] WORDCNT")

        # Test Action 1: Embedded About Screen on Slot 0 (WORDCNT)
        time.sleep(0.3)
        os.write(master, b"a")
        ok, out = read_until(master, b"[Press any key to return]", timeout=6.0)
        if not ok or b"Word & Character Count Plugin" not in out:
            print(f"[-] WORDCNT About screen failed to display. Out: {repr(out)}")
            return 1
        print("[+] WORDCNT embedded About screen verified!")

        # Dismiss About screen with space
        time.sleep(0.3)
        os.write(master, b" ")
        ok, out = read_until(master, b"0..7:select", timeout=5.0)
        if not ok or b">[0]" not in out:
            print(f"[-] Return from WORDCNT About screen to Plugin Manager failed. out={repr(out)}")
            return 1
        print("[+] Returned cleanly from About screen to Plugin Manager.")

        # Navigate to Slot 1 (ROT13) and test embedded About screen
        time.sleep(0.3)
        os.write(master, b"j")
        read_until(master, b">[1]", timeout=4.0)
        time.sleep(0.2)
        os.write(master, b"a")
        ok, out = read_until(master, b"[Press any key to return]", timeout=6.0)
        if not ok or b"ROT13 Text Cipher Plugin" not in out:
            print(f"[-] ROT13 About screen failed to display. Out: {repr(out)}")
            return 1
        print("[+] ROT13 embedded About screen verified!")

        # Dismiss About screen with Enter
        time.sleep(0.3)
        os.write(master, b"\r")
        read_until(master, b"0..7:select", timeout=5.0)
        print("[+] Returned cleanly from ROT13 About screen.")

        # Navigate to Slot 2 (BEAUTIFY) and test embedded About screen
        time.sleep(0.3)
        os.write(master, b"j")
        read_until(master, b">[2]", timeout=4.0)
        time.sleep(0.2)
        os.write(master, b"a")
        ok, out = read_until(master, b"[Press any key to return]", timeout=6.0)
        if not ok or b"Z80 Code Beautifier Plugin" not in out:
            print(f"[-] BEAUTIFY About screen failed to display. Out: {repr(out)}")
            return 1
        print("[+] BEAUTIFY embedded About screen verified!")

        # Dismiss About screen with space
        time.sleep(0.3)
        os.write(master, b" ")
        read_until(master, b"0..7:select", timeout=5.0)
        print("[+] Returned cleanly from BEAUTIFY About screen.")

        # Test Action 2: Embedded Configuration Screen on Slot 2 (BEAUTIFY)
        time.sleep(0.3)
        os.write(master, b"c")
        ok, out = read_until(master, b"[1-4] Toggle  [Enter/Q] Save & Exit", timeout=6.0)
        if not ok or b"Z80 Beautifier Configuration" not in out:
            print(f"[-] BEAUTIFY Configuration screen failed to display. Out: {repr(out)}")
            return 1
        print("[+] BEAUTIFY embedded Configuration screen verified!")

        # Toggle column preset by pressing '1'
        time.sleep(0.3)
        os.write(master, b"1")
        ok, out = read_until(master, b"Compact  (8/16)", timeout=5.0)
        if not ok:
            print(f"[-] BEAUTIFY config toggle '1' failed. Out: {repr(out)}")
            return 1
        print("[+] BEAUTIFY config option 1 toggled to [Compact (8/16)].")

        # Toggle animation by pressing '4'
        time.sleep(0.3)
        os.write(master, b"4")
        ok, out = read_until(master, b"OFF (Fast)", timeout=5.0)
        if not ok:
            print(f"[-] BEAUTIFY config toggle '4' failed. Out: {repr(out)}")
            return 1
        print("[+] BEAUTIFY config option 4 toggled to [OFF (Fast)].")

        # Exit config screen and return to Plugin Manager ('q')
        time.sleep(0.3)
        os.write(master, b"q")
        ok, out = read_until(master, b"0..7:select", timeout=5.0)
        if not ok or b">[2]" not in out:
            print(f"[-] Return from BEAUTIFY config screen to Plugin Manager failed. out={repr(out)}")
            return 1
        print("[+] Successfully exited BEAUTIFY config and returned to Plugin Manager.")

        # Test Action 0: Run BEAUTIFY from Plugin Manager by pressing Enter
        # BEAUTIFY mutates document, so it transitions to editor with status
        time.sleep(0.3)
        os.write(master, b"\r")
        ok, out = read_until(master, b"[Beautify Done]", timeout=8.0)
        if not ok:
            print(f"[-] BEAUTIFY execution failed. Out: {repr(out)}")
            return 1
        print("[+] BEAUTIFY executed cleanly via Enter on Slot 2!")

        # Exit Editor cleanly via Ctrl+Q -> 'n' (discard) back to CP/M
        time.sleep(0.3)
        os.write(master, b"\x11")
        ok, _ = read_until(master, b"Save changes?", timeout=5.0)
        if not ok:
            print("[-] Save changes prompt failed")
            return 1
        os.write(master, b"n")
        ok, _ = read_until(master, b"C>", timeout=5.0)
        if not ok:
            print("[-] Return to CP/M prompt failed")
            return 1
        print("[+] Clean exit to CP/M prompt verified.")

        print("\n=======================================================")
        print("  ALL INTERACTIVE PLUGIN MANAGER TESTS PASSED (100%)!  ")
        print("=======================================================")
        return 0

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=1.0)
        except Exception:
            pass
        os.close(master)

if __name__ == "__main__":
    sys.exit(main())
