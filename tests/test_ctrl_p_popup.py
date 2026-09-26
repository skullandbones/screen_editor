#!/usr/bin/env python3
"""
Automated Test Suite for Context-Aware Plugin Pop-up Subsystem (Ctrl+P).
Tests Ctrl+P on every screen in SE.COM:
  1. Splash Screen: Lists all installed plugins, dismisses with ESC.
  2. Configuration Screen: Filters plugins supporting CAP_HAS_CONFIG
     (shows WORDCNT and BEAUTIFY, filters out ROT13), executes Action 2 (Config),
     returns cleanly to Configuration Screen.
  3. Memory Info Screen: Filters plugins supporting CAP_FAR_EXEC
     (shows WORDCNT, filters out ROT13 & BEAUTIFY), dismisses with ESC, returns cleanly.
  4. About Screen: Filters plugins supporting CAP_HAS_ABOUT
     (shows WORDCNT, ROT13, BEAUTIFY), executes Action 1 (About dialog),
     returns cleanly to About Screen.
  5. Editor Screen: Filters plugins supporting CAP_DOC_MUTATE / CAP_MODAL_UI,
     executes Action 0 (WORDCNT modal dialog), returns and restores editor text cleanly.
  6. Help Screen (Ctrl+K): Displays updated 'Ctrl+P Plugins pop-up' in help body,
     Ctrl+P opens documentation pop-up, dismisses with ESC, returns to Help screen.
  7. Plugin Manager (Ctrl+Z): Lists all plugins, dismisses with ESC, returns cleanly.
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
    rom_file = os.path.join(workspace_root, "tools", "romwbw_src", "Binary", "RC2014_std.rom")
    img_file = os.path.join(workspace_root, "tools", "romwbw_src", "Binary", "hd1k_combo.img")
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


def main():
    emu_bin, rom_file, img_file, se_bin = find_paths()

    for p, name in [(emu_bin, "RC2014 emulator"), (rom_file, "ROM file"),
                    (img_file, "Disk image"), (se_bin, "SE.COM binary")]:
        if not os.path.isfile(p):
            print(f"[-] Error: {name} not found at {p}")
            sys.exit(1)

    print("=================================================================")
    print("  SE.COM Context-Aware Plugin Pop-up (Ctrl+P) Regression Suite   ")
    print("=================================================================")

    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)

    try:
        # 1. Boot loader prompt
        out = read_until(master, b"Boot [H=Help]:", timeout=6.0)
        if b"Boot [H=Help]:" not in out:
            print("[-] Failed to reach RomWBW boot loader prompt.")
            return 1

        # 2. Boot CP/M on ROM disk (Choice 'c') and switch to Drive C:
        time.sleep(0.5)
        os.write(master, b"c\r")
        out = read_until(master, b"B>", timeout=6.0)
        if b"B>" not in out:
            print("[-] Failed to boot into CP/M prompt.")
            return 1

        time.sleep(0.5)
        os.write(master, b"c:\r")
        out = read_until(master, b"C>", timeout=10.0)
        if b"C>" not in out:
            print(f"[-] Failed to switch to Drive C:. Buffer captured: {repr(out)}")
            return 1
        print("[+] Switched to Drive C>.")

        # Launch SE.COM
        time.sleep(0.5)
        os.write(master, b"se\r")
        out = read_until(master, b"for about", timeout=20.0)
        if b"for about" not in out and b"Col 0" not in out:
            print(f"[-] Failed to reach Splash Screen. Output:\n{out.decode('latin1', errors='replace')}")
            return 1
        print("[+] Splash Screen displayed successfully.")

        # -----------------------------------------------------------------
        # TEST 1: Splash Screen Ctrl+P
        # -----------------------------------------------------------------
        print("[*] TEST 1: Context Pop-up on Splash Screen...")
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"\x10")  # Ctrl+P
        out = read_until(master, b"[Up/Dn/0-7] Select", timeout=14.0)
        if b"All Available Installed Plugins" not in out:
            print(f"[-] Test 1 failed: Title missing. Output:\n{out.decode('latin1', errors='replace')}")
            return 1
        if b"WORDCNT" not in out or b"ROT13" not in out or b"BEAUTIFY" not in out:
            print(f"[-] Test 1 failed: Expected all plugins. Output:\n{out.decode('latin1', errors='replace')}")
            return 1
        print("    [+] Splash pop-up listed all installed plugins (WORDCNT, ROT13, BEAUTIFY)")

        # Test Arrow navigation in pop-up: Down Arrow moves to >[1] ROT13
        time.sleep(0.2)
        os.write(master, b"\x1b[B")
        out = read_until(master, b">[1] ROT13", timeout=4.0)
        if b">[1] ROT13" not in out:
            print("[-] Test 1 failed: Down arrow did not select slot 1.")
            return 1
        print("    [+] Pop-up Down Arrow selected >[1] ROT13")

        # Test Up Arrow in pop-up: Up Arrow moves back to >[0] WORDCNT
        time.sleep(0.2)
        os.write(master, b"\x1b[A")
        out = read_until(master, b">[0] WORDCNT", timeout=4.0)
        if b">[0] WORDCNT" not in out:
            print("[-] Test 1 failed: Up arrow did not select slot 0.")
            return 1
        print("    [+] Pop-up Up Arrow selected >[0] WORDCNT")

        # Dismiss with ESC
        time.sleep(0.2)
        os.write(master, b"\x1b")
        out = read_until(master, b"for about", timeout=4.0)
        if b"for about" not in out:
            print(f"[-] Test 1 failed: ESC dismiss did not restore splash screen.")
            return 1
        print("[+] Test 1 PASSED: Splash pop-up arrow navigation verified.")

        # -----------------------------------------------------------------
        # TEST 2: Configuration Screen Ctrl+P
        # -----------------------------------------------------------------
        print("[*] TEST 2: Context Pop-up on Configuration Screen...")
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"c")  # Enter Config Screen
        out = read_until(master, b"Screen Editor Configuration", timeout=6.0)
        if b"Screen Editor Configuration" not in out:
            print(f"[-] Failed to enter Configuration Screen. Buffer captured: {repr(out)}")
            return 1

        time.sleep(0.2)
        drain_all(master)
        os.write(master, b"\x10")  # Ctrl+P
        out = read_until(master, b"[Up/Dn/0-7] Select", timeout=6.0)
        if b"Plugins with Configurable Settings" not in out:
            print(f"[-] Test 2 failed: Title missing. Output:\n{out.decode('latin1', errors='replace')}")
            return 1
        if b"WORDCNT" not in out or b"BEAUTIFY" not in out:
            print(f"[-] Test 2 failed: WORDCNT and BEAUTIFY should match. Output:\n{out.decode('latin1', errors='replace')}")
            return 1
        if b"ROT13" in out:
            print(f"[-] Test 2 failed: ROT13 does not have config, should NOT appear! Output:\n{out.decode('latin1', errors='replace')}")
            return 1
        print("    [+] Config pop-up listed only configurable plugins (WORDCNT & BEAUTIFY; ROT13 filtered)")

        # Select slot 2 ('2') and Execute (Enter) Action 2 (BEAUTIFY config)
        time.sleep(0.2)
        os.write(master, b"2\r")
        out = read_until(master, b"Beautifier Configuration", timeout=4.0)
        if b"Beautifier Configuration" not in out:
            print(f"[-] Test 2 failed: Option 2 did not open Beautifier Configuration screen.")
            return 1
        print("    [+] Action 2 invoked: Embedded Beautifier Configuration menu opened")

        # Exit Beautifier config with 'q' -> returns to Ctrl+P pop-up menu
        time.sleep(0.2)
        os.write(master, b"q")
        out = read_until(master, b"Plugins with Configurable Settings", timeout=6.0)
        if b"Plugins with Configurable Settings" not in out:
            print(f"[-] Test 2 failed: Return from Beautifier config did not restore Ctrl+P menu. Buffer: {repr(out)}")
            return 1
        print("    [+] Modal hierarchy verified: Returned cleanly to Ctrl+P Config pop-up menu")

        # Dismiss Ctrl+P pop-up menu with 'q'
        time.sleep(0.2)
        os.write(master, b"q")
        out = read_until(master, b"Screen Editor Configuration", timeout=6.0)
        if b"Screen Editor Configuration" not in out:
            print(f"[-] Test 2 failed: Return from Ctrl+P menu did not restore Host Config screen. Buffer: {repr(out)}")
            return 1
        print("    [+] Returned cleanly to Host Configuration Screen")

        # Exit Configuration Screen back to Splash Screen
        time.sleep(0.2)
        os.write(master, b"q")
        out = read_until(master, b"for about", timeout=4.0)
        if b"for about" not in out:
            print(f"[-] Test 2 failed: Return to Splash screen failed.")
            return 1
        print("[+] Test 2 PASSED: Config pop-up filtered correctly and executed Action 2 cleanly.")

        # -----------------------------------------------------------------
        # TEST 3: Memory Info Screen Ctrl+P
        # -----------------------------------------------------------------
        print("[*] TEST 3: Context Pop-up on Memory Info Screen...")
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"m")  # Enter Memory Info Screen
        out = read_until(master, b"Extended Memory Map", timeout=6.0)
        if b"Extended Memory Map" not in out:
            print(f"[-] Failed to enter Memory Info Screen. Buffer: {repr(out)}")
            return 1

        time.sleep(0.2)
        drain_all(master)
        os.write(master, b"\x10")  # Ctrl+P
        out = read_until(master, b"[Up/Dn/0-7] Select", timeout=6.0)
        if b"Plugins with Far RAM Memory Usage" not in out:
            print(f"[-] Test 3 failed: Title missing. Output:\n{out.decode('latin1', errors='replace')}")
            return 1
        if b"WORDCNT" not in out:
            print(f"[-] Test 3 failed: WORDCNT should match Far RAM. Output:\n{out.decode('latin1', errors='replace')}")
            return 1
        if b"ROT13" in out or b"BEAUTIFY" in out:
            print(f"[-] Test 3 failed: ROT13 and BEAUTIFY should NOT appear in Far RAM popup!")
            return 1
        print("    [+] Mem Info pop-up listed only Far RAM plugins (WORDCNT only; ROT13 & BEAUTIFY filtered)")

        # Dismiss with ESC
        time.sleep(0.2)
        os.write(master, b"\x1b")
        out = read_until(master, b"Extended Memory Map", timeout=6.0)
        if b"Extended Memory Map" not in out:
            print(f"[-] Test 3 failed: Return to Memory Info screen failed. Buffer: {repr(out)}")
            return 1

        # Return to Splash Screen
        time.sleep(0.2)
        os.write(master, b"\x1b")
        out = read_until(master, b"for about", timeout=4.0)
        if b"for about" not in out:
            print(f"[-] Test 3 failed: Return to Splash screen failed.")
            return 1
        print("[+] Test 3 PASSED: Memory Info pop-up filtered Far RAM plugins correctly.")

        # -----------------------------------------------------------------
        # TEST 4: About Screen Ctrl+P
        # -----------------------------------------------------------------
        print("[*] TEST 4: Context Pop-up on About Screen...")
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"a")  # Enter About Screen
        out = read_until(master, b"SE - Screen Editor", timeout=6.0)
        if b"SE - Screen Editor" not in out:
            print(f"[-] Failed to enter About Screen. Buffer: {repr(out)}")
            return 1

        time.sleep(0.2)
        drain_all(master)
        os.write(master, b"\x10")  # Ctrl+P
        out = read_until(master, b"[Up/Dn/0-7] Select", timeout=6.0)
        if b"Plugins with Embedded Documentation" not in out:
            print(f"[-] Test 4 failed: Title missing. Output:\n{out.decode('latin1', errors='replace')}")
            return 1
        if b"WORDCNT" not in out or b"ROT13" not in out or b"BEAUTIFY" not in out:
            print(f"[-] Test 4 failed: All plugins have about docs.")
            return 1
        print("    [+] About pop-up listed all documented plugins (WORDCNT, ROT13, BEAUTIFY)")

        # Execute Action 1 on slot 1 (ROT13 About dialog) via '1' + Enter
        time.sleep(0.2)
        os.write(master, b"1\r")
        out = read_until(master, b"ROT13 Text Cipher Plugin", timeout=4.0)
        if b"ROT13 Text Cipher Plugin" not in out:
            print(f"[-] Test 4 failed: Action 1 did not open ROT13 About dialog.")
            return 1
        print("    [+] Action 1 invoked: ROT13 Modal About dialog displayed")

        # Dismiss About dialog with space -> returns to Ctrl+P pop-up menu
        time.sleep(0.2)
        os.write(master, b" ")
        out = read_until(master, b"Plugins with Embedded Documentation", timeout=6.0)
        if b"Plugins with Embedded Documentation" not in out:
            print(f"[-] Test 4 failed: Return from About dialog did not restore Ctrl+P menu. Buffer: {repr(out)}")
            return 1
        print("    [+] Modal hierarchy verified: Returned cleanly to Ctrl+P pop-up menu")

        # Dismiss Ctrl+P pop-up menu with ESC
        time.sleep(0.2)
        os.write(master, b"\x1b")
        out = read_until(master, b"SE - Screen Editor", timeout=6.0)
        if b"SE - Screen Editor" not in out:
            print(f"[-] Test 4 failed: Dismissing Ctrl+P menu did not restore Host About screen. Buffer: {repr(out)}")
            return 1
        print("    [+] Cleanly restored Host About screen")

        # Return to Splash Screen
        time.sleep(0.2)
        os.write(master, b"\x1b")
        out = read_until(master, b"for about", timeout=4.0)
        if b"for about" not in out:
            print(f"[-] Test 4 failed: Return to Splash screen failed.")
            return 1
        print("[+] Test 4 PASSED: About pop-up executed Action 1 and restored screen cleanly.")

        # -----------------------------------------------------------------
        # TEST 5: Editor Screen & Help Screen (Ctrl+K) Ctrl+P
        # -----------------------------------------------------------------
        print("[*] TEST 5: Context Pop-up in Editor and Help (Ctrl+K) Screen...")
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"\r")  # Enter editor
        out = read_until(master, b"Line    1/1", timeout=4.0)
        if b"Line    1/1" not in out:
            print(f"[-] Failed to enter Editor mode.")
            return 1

        # Type text
        time.sleep(0.2)
        os.write(master, b"Sample Document Text for Popup Testing\r")
        read_until(master, b"Line    2/2", timeout=4.0)

        # Pop-up on Editor Screen
        time.sleep(0.2)
        drain_all(master)
        os.write(master, b"\x10")  # Ctrl+P
        out = read_until(master, b"[Up/Dn/0-7] Select", timeout=6.0)
        if b"Plugins for Editor (Run Plugin)" not in out:
            print(f"[-] Test 5 failed: Title missing. Output:\n{out.decode('latin1', errors='replace')}")
            return 1
        if b"WORDCNT" not in out or b"ROT13" not in out or b"BEAUTIFY" not in out:
            print(f"[-] Test 5 failed: All 3 plugins should match Editor.")
            return 1
        print("    [+] Editor pop-up listed editor tools (WORDCNT, ROT13, BEAUTIFY)")

        # Run Action 0 on slot 0 (WORDCNT modal dialog) via '0' + Enter
        time.sleep(0.2)
        os.write(master, b"0\r")
        out = read_until(master, b"Document Statistics", timeout=4.0)
        if b"Document Statistics" not in out:
            print(f"[-] Test 5 failed: WORDCNT modal dialog missing.")
            return 1
        print("    [+] Action 0 invoked: WORDCNT statistics dialog displayed")

        # Dismiss dialog with space
        time.sleep(0.2)
        os.write(master, b" ")
        out = read_until(master, b"Sample Document Text", timeout=4.0)
        if b"Sample Document Text" not in out:
            print(f"[-] Test 5 failed: Editor screen text not restored after WORDCNT dismissal.")
            return 1
        print("    [+] Editor viewport cleanly restored with original text intact")

        # Open Help Screen via Ctrl+K
        time.sleep(0.2)
        drain_all(master)
        os.write(master, b"\x0b")  # Ctrl+K
        out = read_until(master, b"return to editor", timeout=4.0)
        if b"EDITOR MODE KEYS" not in out:
            print(f"[-] Failed to open Help Screen via Ctrl+K.")
            return 1
        if b"Ctrl+P          Plugins pop-up" not in out:
            print(f"[-] Test 5 failed: 'Ctrl+P Plugins pop-up' missing from Help screen body.")
            return 1
        print("    [+] Help Screen body verifies 'Ctrl+P Plugins pop-up'")

        # Pop-up on Help Screen
        time.sleep(0.2)
        drain_all(master)
        os.write(master, b"\x10")  # Ctrl+P
        out = read_until(master, b"[Up/Dn/0-7] Select", timeout=6.0)
        if b"Plugins with Embedded Documentation" not in out:
            print(f"[-] Test 5 failed: Title missing on Help screen pop-up.")
            return 1
        print("    [+] Help Screen pop-up displayed successfully")

        # Dismiss with ESC
        time.sleep(0.2)
        os.write(master, b"\x1b")
        out = read_until(master, b"return to editor", timeout=4.0)
        if b"EDITOR MODE KEYS" not in out:
            print(f"[-] Test 5 failed: Return to Help Screen failed.")
            return 1

        # Return to Editor by pressing space
        time.sleep(0.2)
        os.write(master, b" ")
        out = read_until(master, b"Sample Document Text", timeout=4.0)
        if b"Sample Document Text" not in out:
            print(f"[-] Test 5 failed: Return to Editor from Help Screen failed.")
            return 1
        print("[+] Test 5 PASSED: Editor and Help screen pop-ups verified.")

        # -----------------------------------------------------------------
        # TEST 6: Plugin Manager (Ctrl+Z) Ctrl+P
        # -----------------------------------------------------------------
        print("[*] TEST 6: Context Pop-up in Plugin Manager Screen...")
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"\x1a")  # Ctrl+Z
        out = read_until(master, b"Plugin Manager", timeout=4.0)
        if b"Plugin Manager" not in out:
            print(f"[-] Failed to open Plugin Manager via Ctrl+Z.")
            return 1

        time.sleep(0.2)
        drain_all(master)
        os.write(master, b"\x10")  # Ctrl+P
        out = read_until(master, b"[Up/Dn/0-7] Select", timeout=6.0)
        if b"Installed Plugin Catalog" not in out:
            print(f"[-] Test 6 failed: Title missing in Plugin Manager pop-up.")
            return 1
        print("    [+] Plugin Manager pop-up displayed successfully")

        # Dismiss with ESC
        time.sleep(0.2)
        os.write(master, b"\x1b")
        out = read_until(master, b"Plugin Manager", timeout=4.0)
        if b"Plugin Manager" not in out:
            print(f"[-] Test 6 failed: Return to Plugin Manager failed.")
            return 1

        # Exit Plugin Manager back to Editor
        time.sleep(0.2)
        os.write(master, b"q")
        out = read_until(master, b"Sample Document Text", timeout=4.0)
        if b"Sample Document Text" not in out:
            print(f"[-] Test 6 failed: Return to Editor from Plugin Manager failed.")
            return 1
        print("[+] Test 6 PASSED: Plugin Manager pop-up verified.")

        # -----------------------------------------------------------------
        # Exit to CP/M Prompt
        # -----------------------------------------------------------------
        print("[*] Exiting SE.COM back to CP/M prompt...")
        time.sleep(0.2)
        os.write(master, b"\x11")  # Ctrl+Q
        # Unsaved changes confirmation: 'n' (discard changes)
        time.sleep(0.2)
        os.write(master, b"n")
        out = read_until(master, b"C>", timeout=4.0)
        if b"C>" not in out:
            print(f"[-] Exit to CP/M prompt failed. Buffer: {repr(out)}")
            return 1

        print("=================================================================")
        print("  ALL CONTEXT POP-UP (CTRL+P) TESTS PASSED SUCCESSFULLY!         ")
        print("=================================================================")
        return 0

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=1.0)
        except Exception:
            proc.kill()
        os.close(master)


if __name__ == "__main__":
    sys.exit(main())
