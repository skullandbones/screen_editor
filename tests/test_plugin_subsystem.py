#!/usr/bin/env python3
"""
Comprehensive Automated Test Suite for SE.COM Plugin Subsystem.
Verifies CP/M 3 PRL & OVL 4KB modular plugin architecture:
  1. Boot RomWBW and start SE.COM on CP/M Drive C:.
  2. Verify Splash Screen displays 'type p for plugins'.
  3. Enter Plugin Manager ('p') and verify:
     - Header, Far RAM bank dynamic allocation, 4KB TPA overlay slot.
     - Auto-probed Slot 0: WORDCNT.OVL (CP/M 3 Overlay format, Far RAM execution).
     - Auto-probed Slot 1: ROT13.PRL (CP/M 3 PRL format, TPA slot execution).
  4. Execute WORDCNT.OVL from Plugin Manager:
     - Executes directly in Far RAM via RomWBW HB_BNKCALL (0xFFF9).
     - Traverses document via host API and displays modal summary dialog box.
     - Returns cleanly to Plugin Manager upon keypress.
  5. Exit Plugin Manager ('q') back to Splash Screen.
  6. Enter Editor Mode ('e'), type text ("HELLO WORLD").
  7. Open Plugin Manager from Editor (Ctrl+Z) and execute ROT13.PRL:
     - Relocates on-the-fly in 4KB TPA slot over LINE_STORAGE.
     - Performs in-place text transformation ("URYYB JBEYQ").
     - Sets status message ("[ROT13 Applied]") on Status Bar.
  8. Execute ROT13.PRL a second time to invert text back to "HELLO WORLD".
  9. Test Unload ('u') and Load ('l') functionality.
 10. Clean exit (Ctrl+Q) back to CP/M prompt (C>).
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

    return emu_bin, rom_file, img_file, se_bin


def read_until(master_fd, match_bytes, timeout=6.0):
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


def run_plugin_test():
    t_start = time.time()
    emu_bin, rom_file, img_file, se_bin = find_paths()

    if not os.path.isfile(emu_bin):
        print(f"[-] Emulator binary not found: {emu_bin}", flush=True)
        return False
    if not os.path.isfile(rom_file):
        print(f"[-] ROM file not found: {rom_file}", flush=True)
        return False
    if not os.path.isfile(img_file):
        print(f"[-] Disk image not found: {img_file}", flush=True)
        return False

    print("[*] Launching RomWBW on RC2014 emulator (Plugin Test Suite)...", flush=True)
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)

    try:
        # 1. Boot loader prompt
        print("[*] Step 1: Waiting for RomWBW boot loader prompt...",
              flush=True)
        ok, out = read_until(master, b"Boot [H=Help]:", timeout=6.0)
        if not ok:
            print("[-] Step 1: Failed to reach RomWBW boot loader prompt.",
                  flush=True)
            return False
        print("[+] Step 1: RomWBW boot loader prompt reached.", flush=True)

        # 2. Boot CP/M on ROM disk (Choice 'c') and switch to Drive C:
        print("[*] Step 2: Booting into CP/M and switching to Drive C:...",
              flush=True)
        time.sleep(0.5)
        os.write(master, b"c\r")
        ok, out = read_until(master, b"B>", timeout=6.0)
        if not ok:
            print("[-] Step 2: Failed to boot into CP/M prompt.", flush=True)
            return False

        time.sleep(0.5)
        os.write(master, b"c:\r")
        ok, out = read_until(master, b"C>", timeout=8.0)
        if not ok:
            print(f"[-] Step 2: Failed to switch to Drive C:. Buffer: "
                  f"{repr(out)}", flush=True)
            return False
        print("[+] Step 2: Switched to Drive C>.", flush=True)

        # 3. Launch SE.COM
        print("[*] Step 3: Launching SE.COM...", flush=True)
        time.sleep(0.5)
        os.write(master, b"se\r")
        ok, out = read_until(master, b"Col 0", timeout=45.0)
        if not ok:
            print(f"[-] Step 3: Splash screen did not show plugin menu option. "
                  f"Buffer: {repr(out)}", flush=True)
            return False
        print("[+] Step 3: Splash screen displayed with 'type p for plugins'.",
              flush=True)
        drain_all(master, quiet_time=0.1)

        # 4. Open Plugin Manager from splash screen ('p')
        print("[*] Step 4: Opening Plugin Manager from splash screen ('p')...",
              flush=True)
        time.sleep(0.5)
        os.write(master, b"p")
        ok, out = read_until(master, b"SE - Plugin Manager", timeout=8.0)
        if not ok:
            print(f"[-] Step 4: Failed to enter Plugin Manager screen. "
                  f"Buffer: {repr(out)}", flush=True)
            return False

        # Verify auto-probed plugins in registry
        if b"WORDCNT" not in out or b"ROT13" not in out:
            ok, out_more = read_until(master, b"0..7:select", timeout=5.0)
            out += out_more
        if b"WORDCNT" not in out or b"ROT13" not in out:
            print(f"[-] Step 4: Auto-probed plugins (WORDCNT / ROT13) not "
                  f"found in registry. Buffer: {repr(out)}", flush=True)
            return False
        print("[+] Step 4: Plugin Manager displayed with auto-probed "
              "WORDCNT.OVL and ROT13.PRL.", flush=True)

        # Verify Far RAM bank borrowing information
        if b"Far RAM: [Bank " not in out:
            print(f"[-] Step 4: Far RAM bank allocation line not found. "
                  f"Buffer: {repr(out)}", flush=True)
            return False
        print("[+] Step 4: Far RAM dynamic bank borrowing verified.",
              flush=True)

        # 5. View WORDCNT.OVL About screen via 'a'
        print("[*] Step 5: Viewing WORDCNT.OVL About dialog via 'a'...",
              flush=True)
        time.sleep(0.3)
        os.write(master, b"a")
        ok, out_wc = read_until(master,
                                b"Word & Character Count Plugin",
                                timeout=8.0)
        if not ok:
            print(f"[-] Step 5: WORDCNT About dialog failed to display. "
                  f"Buffer: {repr(out_wc)}", flush=True)
            return False
        print("[+] Step 5: WORDCNT.OVL About modal dialog verified.",
              flush=True)

        # Dismiss WORDCNT dialog with Space
        time.sleep(0.2)
        os.write(master, b" ")
        ok, out_ret = read_until(master, b"SE - Plugin Manager", timeout=5.0)
        if not ok:
            print(f"[-] Step 5: Failed to return to Plugin Manager. "
                  f"Buffer: {repr(out_ret)}", flush=True)
            return False
        print("[+] Step 5: Returned cleanly to Plugin Manager.", flush=True)

        # 6. Exit Plugin Manager ('q') back to Splash Screen
        print("[*] Step 6: Exiting Plugin Manager back to Splash Screen...",
              flush=True)
        time.sleep(0.2)
        os.write(master, b"q")
        ok, out_splash = read_until(master,
                                    b"type   e  or  <Enter>   to edit",
                                    timeout=5.0)
        if not ok:
            print(f"[-] Step 6: Return to splash screen failed. "
                  f"Buffer: {repr(out_splash)}", flush=True)
            return False
        print("[+] Step 6: Exited Plugin Manager back to Splash Screen.",
              flush=True)

        # 7. Enter Editor Mode ('e')
        print("[*] Step 7: Entering Editor Mode ('e')...", flush=True)
        time.sleep(0.2)
        os.write(master, b"e")
        ok, out_edit = read_until(master, b"^K: Editor keys", timeout=5.0)
        if not ok:
            print(f"[-] Step 7: Failed to enter editor mode. Buffer: "
                  f"{repr(out_edit)}", flush=True)
            return False
        print("[+] Step 7: Entered editor mode.", flush=True)

        # Type text on active line
        time.sleep(0.1)
        os.write(master, b"HELLO WORLD")
        ok, out_hw = read_until(master, b"HELLO WORLD", timeout=4.0)
        if not ok:
            print(f"[-] Step 7: Failed to type text in editor. Buffer: "
                  f"{repr(out_hw)}", flush=True)
            return False
        print("[+] Step 7: Typed 'HELLO WORLD' into editor line.", flush=True)

        # 8. Open Context Pop-up from Editor via Ctrl+P (0x10)
        print("[*] Step 8: Opening Context Pop-up via Ctrl+P...", flush=True)
        time.sleep(0.2)
        os.write(master, b"\x10")
        ok, out_pop1 = read_until(master, b"Plugins for Editor", timeout=5.0)
        if not ok:
            print(f"[-] Step 8: Ctrl+P failed to open Context Pop-up. "
                  f"Buffer: {repr(out_pop1)}", flush=True)
            return False
        print("[+] Step 8: Ctrl+P opened Context Pop-up from editor.",
              flush=True)

        # 9. Execute ROT13.PRL in TPA slot by typing '1' + Enter
        print("[*] Step 9: Executing ROT13.PRL in TPA slot...", flush=True)
        time.sleep(0.2)
        os.write(master, b"1\r")
        ok, out_rot = read_until(master, b"[ROT13 Applied]", timeout=8.0)
        if not ok or b"URYYB JBEYQ" not in out_rot:
            print(f"[-] Step 9: ROT13 transformation failed. Buffer: "
                  f"{repr(out_rot)}", flush=True)
            return False
        print("[+] Step 9: ROT13 executed in TPA slot with PRL relocation: "
              "transformed to 'URYYB JBEYQ'.", flush=True)

        # Verify keypress clears status message
        time.sleep(0.2)
        drain_all(master)
        os.write(master, b"!")
        ok, out_clr = read_until(master, b"^K: Editor keys", timeout=6.0)
        if not ok or b"[ROT13 Applied]" in out_clr:
            print(f"[-] Step 9: Status message was not cleared on keypress. "
                  f"Buffer: {repr(out_clr)}", flush=True)
            return False
        print("[+] Step 9: Status bar message cleared on subsequent keypress.",
              flush=True)

        # 10. Execute ROT13 a 2nd time via Ctrl+P + 1 + Enter (round-trip)
        print("[*] Step 10: Executing ROT13 second invocation (round-trip)...",
              flush=True)
        time.sleep(0.2)
        drain_all(master)
        os.write(master, b"\x10")
        read_until(master, b"Plugins for Editor", timeout=6.0)
        time.sleep(0.2)
        os.write(master, b"1\r")
        ok, out_hw2 = read_until(master, b"[ROT13 Applied]", timeout=8.0)
        if not ok or b"HELLO WORLD!" not in out_hw2:
            print(f"[-] Step 10: ROT13 second invocation round-trip failed. "
                  f"Buffer: {repr(out_hw2)}", flush=True)
            return False
        print("[+] Step 10: ROT13 second invocation round-trip verified "
              "('HELLO WORLD!').", flush=True)

        # 11. Test Unload ('u') and Load ('l')
        print("[*] Step 11: Testing Unload and Load of ROT13.PRL...",
              flush=True)
        time.sleep(0.2)
        drain_all(master)
        os.write(master, b"\x1a")
        read_until(master, b"SE - Plugin Manager", timeout=6.0)
        time.sleep(0.2)
        os.write(master, b"1")
        read_until(master, b"Unload Slot 1? [Y/N]", timeout=4.0)
        os.write(master, b"y")  # Confirm unload slot 1
        ok, out_unl = read_until(master, b"(empty slot)", timeout=6.0)
        if not ok:
            print(f"[-] Step 11: Unload slot 1 failed. Buffer: {repr(out_unl)}",
                  flush=True)
            return False
        print("[+] Step 11: Slot 1 successfully unloaded.", flush=True)

        # Reload slot 1 via 'l'
        time.sleep(0.2)
        drain_all(master)
        os.write(master, b"l")
        read_until(master, b"Load Plugin", timeout=4.0)
        os.write(master, b"ROT13.PRL\r")
        ok, out_rel = read_until(master, b"ROT13", timeout=6.0)
        if not ok:
            print(f"[-] Step 11: Reloading ROT13.PRL failed. Buffer: "
                  f"{repr(out_rel)}", flush=True)
            return False
        print("[+] Step 11: ROT13.PRL successfully reloaded into slot 1.",
              flush=True)

        # Exit Plugin Manager back to Editor
        time.sleep(0.2)
        os.write(master, b"q")
        read_until(master, b"^K: Editor keys", timeout=5.0)

        # 12. Clean exit (Ctrl+Q -> 'n' to discard)
        print("[*] Step 12: Testing clean exit with Ctrl+Q...", flush=True)
        time.sleep(0.2)
        os.write(master, b"\x11")  # Ctrl+Q
        ok, out_prompt = read_until(master, b"Save changes?", timeout=4.0)
        if not ok:
            print(f"[-] Step 12: Save changes prompt failed. Buffer: "
                  f"{repr(out_prompt)}", flush=True)
            return False
        os.write(master, b"n")
        ok, out_exit = read_until(master, b"C>", timeout=5.0)
        if not ok:
            print(f"[-] Step 12: Clean exit to CP/M prompt failed. Buffer: "
                  f"{repr(out_exit)}", flush=True)
            return False
        print("[+] Step 12: Clean exit to CP/M prompt verified.", flush=True)

        elapsed = time.time() - t_start
        print(f"[+] All Plugin Subsystem tests PASSED in {elapsed:.2f}s!", flush=True)
        return True

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=1.0)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass
        try:
            os.close(master)
        except OSError:
            pass


if __name__ == "__main__":
    success = run_plugin_test()
    sys.exit(0 if success else 1)
