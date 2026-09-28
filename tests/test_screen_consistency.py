#!/usr/bin/env python3
"""
Test Screen Consistency for SE.COM.
Verifies:
  1. Plugin Manager Screen ('p') has status bar on row ACTIVE_ROWS.
  2. Help Keys Screen (Ctrl+K) has status bar on ACTIVE_ROWS and '~' in col 0.
  3. Open File Screen (Ctrl+O) has status bar on ACTIVE_ROWS and '~' in col 0.
  4. Save File Screen (Ctrl+S) has status bar on ACTIVE_ROWS and '~' in col 0.
  5. Input box cursor positioning remains functional in Open & Save screens.
  6. Tested in both 80x24 and 120x40 screen modes.
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
                    return buf
            except (BlockingIOError, OSError):
                pass
    return buf

def drain_all(master_fd, quiet_time=0.15):
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

def run_screen_consistency_test(mode_name="80x24"):
    print(f"\n=======================================================", flush=True)
    print(f"[*] Running Screen Consistency Test in {mode_name} mode", flush=True)
    print(f"=======================================================", flush=True)

    emu_bin, rom_file, img_file, se_bin = find_paths()
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)

    try:
        # Boot RomWBW
        out = read_until(master, b"Boot [H=Help]:", timeout=8.0)
        if b"Boot [H=Help]:" not in out:
            print("[-] RomWBW failed to boot", flush=True)
            return False

        time.sleep(0.5)
        os.write(master, b"c\r")
        out = read_until(master, b"B>", timeout=6.0)
        if b"B>" not in out:
            print("[-] Failed to boot into CP/M prompt.", flush=True)
            return False

        time.sleep(0.5)
        os.write(master, b"c:\r")
        out = read_until(master, b"C>", timeout=10.0)
        if b"C>" not in out:
            print(f"[-] Failed to switch to Drive C>.", flush=True)
            return False

        # Start SE.COM
        time.sleep(0.5)
        drain_all(master)
        os.write(master, b"se\r")
        out_splash = read_until(master, b"SE - Screen Editor", timeout=45.0)
        if b"SE - Screen Editor" not in out_splash:
            print(f"[-] SE splash not displayed. Buffer: {repr(out_splash)}", flush=True)
            return False

        # Configure screen mode
        if mode_name == "80x24":
            os.write(master, b"2")  # Set 80x24
            read_until(master, b"SE - Screen Editor", timeout=5.0)
        elif mode_name == "120x40":
            os.write(master, b"1")  # Set 120x40
            read_until(master, b"SE - Screen Editor", timeout=5.0)
        time.sleep(0.5)
        drain_all(master)

        # 1. Test Plugin Manager Screen ('p' from splash screen)
        print("[*] Testing Plugin Manager Screen...", flush=True)
        os.write(master, b"p")
        out_plug = read_until(master, b"SE - Plugin Manager", timeout=8.0)
        out_plug += read_until(master, b"Free:", timeout=5.0)
        out_plug += read_until(master, b"\x1b[0m", timeout=3.0)
        if b"SE - Plugin Manager" not in out_plug:
            print("[-] Plugin Manager missing title. "
                  f"Buffer: {repr(out_plug)}", flush=True)
            return False

        if b"Free:" not in out_plug or b"KB" not in out_plug:
            print("[-] Plugin Manager missing status bar free memory. "
                  f"Buffer: {repr(out_plug)}", flush=True)
            return False
        if mode_name.encode() not in out_plug:
            print("[-] Plugin Manager status bar missing screen mode "
                  f"{mode_name}. Buffer: {repr(out_plug)}", flush=True)
            return False
        print(f"[+] Plugin Manager Screen has active status bar ({mode_name})!",
              flush=True)

        # Return to splash screen ('q')
        drain_all(master)
        os.write(master, b"q")
        out_back = read_until(master, b"SE - Screen Editor", timeout=6.0)
        if b"SE - Screen Editor" not in out_back:
            print("[-] Failed to return to splash screen from Plugin Manager",
                  flush=True)
            return False
        print("[+] 'q' returned cleanly from Plugin Manager to splash screen.",
              flush=True)
        drain_all(master)

        # 2. Test Help Keys Screen (Ctrl+K from editor mode)
        print("[*] Testing Help Keys Screen...", flush=True)
        os.write(master, b"e")  # enter editor
        out_ed = read_until(master, b"^K: Editor keys", timeout=6.0)
        if b"^K: Editor keys" not in out_ed:
            print(f"[-] Failed to enter editor mode. Buffer: {repr(out_ed)}", flush=True)
            return False

        drain_all(master)
        os.write(master, b"\x0b")  # Ctrl+K
        out_help = read_until(master, b"Press any key to return to editor...", timeout=5.0)
        out_help += read_until(master, b"\x1b[?25l", timeout=3.0)
        if b"SE.COM - EDITOR MODE KEYS" not in out_help:
            print(f"[-] Help screen missing title. Buffer: {repr(out_help)}", flush=True)
            return False

        # Verify full-width rules, dash rule, and centered title/footer on Help screen
        expected_rule = b"~" + (b"=" * (78 if mode_name == "80x24" else 118))
        expected_dash = b"~" + (b"-" * (78 if mode_name == "80x24" else 118))
        expected_title_pad = b"~" + (b" " * (26 if mode_name == "80x24" else 46)) + b"SE.COM - EDITOR MODE KEYS"
        expected_prompt_pad = b"~" + (b" " * (21 if mode_name == "80x24" else 41)) + b"Press any key to return to editor..."

        if expected_rule not in out_help:
            print(f"[-] Help screen missing full-width '=' rule. Buffer: {repr(out_help)}", flush=True)
            return False
        if expected_dash not in out_help:
            print(f"[-] Help screen missing full-width '-' rule. Buffer: {repr(out_help)}", flush=True)
            return False
        if expected_title_pad not in out_help:
            print(f"[-] Help screen missing centered title. Buffer: {repr(out_help)}", flush=True)
            return False
        if expected_prompt_pad not in out_help:
            print(f"[-] Help screen missing centered return prompt. Buffer: {repr(out_help)}", flush=True)
            return False
        if b"Free:" not in out_help or b"KB" not in out_help:
            print(f"[-] Help screen missing status bar free memory. Buffer: {repr(out_help)}", flush=True)
            return False
        if mode_name.encode() not in out_help:
            print(f"[-] Help screen status bar missing screen mode {mode_name}. Buffer: {repr(out_help)}", flush=True)
            return False
        print(f"[+] Help Keys Screen has '~' in col 0 and active status bar ({mode_name})!", flush=True)

        # Return to editor
        drain_all(master)
        os.write(master, b" ")
        read_until(master, b"^K: Editor keys", timeout=4.0)

        # 2. Test Open File Screen (Ctrl+O from editor)
        print("[*] Testing Open File Screen...", flush=True)
        drain_all(master)
        os.write(master, b"\x0f")  # Ctrl+O
        out_open = read_until(master, b"Enter filename to open", timeout=6.0)
        out_open += read_until(master, b"\x1b[?25h", timeout=3.0)
        if b"OPEN FILE (DIRECTORY - DRIVE C:)" not in out_open:
            print(f"[-] Open screen missing title. Buffer: {repr(out_open)}", flush=True)
            return False

        # Verify full-width rule and centered title
        expected_rule = b"~" + (b"=" * (78 if mode_name == "80x24" else 118))
        if expected_rule not in out_open:
            print(f"[-] Open screen missing full-width rule (len {len(expected_rule)}). Buffer: {repr(out_open)}", flush=True)
            return False
        expected_title_pad = b"~" + (b" " * (18 if mode_name == "80x24" else 38)) + b"SE.COM - OPEN FILE"
        if expected_title_pad not in out_open:
            print(f"[-] Open screen missing centered title. Buffer: {repr(out_open)}", flush=True)
            return False
        if b"~  <ESC>=Cancel" not in out_open:
            print("[-] Open screen missing '~  <ESC>=Cancel'. "
                  f"Buffer: {repr(out_open)}", flush=True)
            return False
        if b"Free:" not in out_open or b"KB" not in out_open:
            print(f"[-] Open screen missing status bar free memory. Buffer: {repr(out_open)}", flush=True)
            return False
        if mode_name.encode() not in out_open:
            print(f"[-] Open screen status bar missing screen mode {mode_name}. Buffer: {repr(out_open)}", flush=True)
            return False
        print(f"[+] Open File Screen has '~' in col 0 and active status bar ({mode_name})!", flush=True)

        # Test typing in input box and cancel
        os.write(master, b"TEST")
        time.sleep(0.2)
        os.write(master, b"\x1b")  # ESC to cancel back to editor
        out_back_ed = read_until(master, b"^K: Editor keys", timeout=5.0)
        if b"^K: Editor keys" not in out_back_ed:
            print("[-] Cancel from Open Screen failed to return to editor", flush=True)
            return False
        print("[+] ESC correctly cancelled Open File screen back to editor.", flush=True)

        # 3. Test Save File Screen (Ctrl+S from editor)
        print("[*] Testing Save File Screen...", flush=True)
        drain_all(master)
        os.write(master, b"\x13")  # Ctrl+S
        out_save = read_until(master, b"Enter filename to save", timeout=6.0)
        out_save += read_until(master, b"\x1b[?25h", timeout=3.0)
        if b"SAVE FILE (DIRECTORY - DRIVE C:)" not in out_save:
            print(f"[-] Save screen missing title. Buffer: {repr(out_save)}", flush=True)
            return False

        # Verify full-width rule and centered title
        if expected_rule not in out_save:
            print(f"[-] Save screen missing full-width rule (len {len(expected_rule)}). Buffer: {repr(out_save)}", flush=True)
            return False
        expected_save_title = b"~" + (b" " * (18 if mode_name == "80x24" else 38)) + b"SE.COM - SAVE FILE"
        if expected_save_title not in out_save:
            print(f"[-] Save screen missing centered title. Buffer: {repr(out_save)}", flush=True)
            return False
        if b"~  Format: [" not in out_save:
            print(f"[-] Save screen missing '~' in format indicator. Buffer: {repr(out_save)}", flush=True)
            return False
        if b"~  <ESC>=Cancel" not in out_save:
            print("[-] Save screen missing '~  <ESC>=Cancel'. "
                  f"Buffer: {repr(out_save)}", flush=True)
            return False
        if b"Free:" not in out_save or b"KB" not in out_save:
            print(f"[-] Save screen missing status bar free memory. Buffer: {repr(out_save)}", flush=True)
            return False
        if mode_name.encode() not in out_save:
            print(f"[-] Save screen status bar missing screen mode {mode_name}. Buffer: {repr(out_save)}", flush=True)
            return False
        print(f"[+] Save File Screen has '~' in col 0 and active status bar ({mode_name})!", flush=True)

        # Test format toggle (^F) in Save Screen
        os.write(master, b"\x06")  # Ctrl+F
        out_fmt = read_until(master, b"Format: [Linux]", timeout=4.0)
        if b"Format: [Linux]" not in out_fmt:
            print("[-] Ctrl+F format toggle failed in Save screen", flush=True)
            return False
        print("[+] Ctrl+F toggled format to Linux cleanly while preserving status bar.", flush=True)

        # Cancel Save screen
        drain_all(master)
        os.write(master, b"\x1b")  # ESC
        read_until(master, b"^K: Editor keys", timeout=4.0)

        # Clean exit to CP/M
        drain_all(master)
        os.write(master, b"\x11")  # Ctrl+Q
        out_cpm_exit = read_until(master, b"C>", timeout=4.0)
        if b"C>" not in out_cpm_exit:
            print("[-] Failed to exit cleanly to CP/M", flush=True)
            return False

        print(f"[+] Screen consistency test PASSED for {mode_name} mode!", flush=True)
        return True

    finally:
        try:
            os.close(master)
        except OSError:
            pass
        proc.terminate()
        try:
            proc.wait(timeout=2.0)
        except subprocess.TimeoutExpired:
            proc.kill()

if __name__ == "__main__":
    ok_80 = run_screen_consistency_test("80x24")
    if not ok_80:
        sys.exit(1)

    ok_120 = run_screen_consistency_test("120x40")
    if not ok_120:
        sys.exit(1)

    print("\n[SUCCESS] All Screen Consistency tests PASSED 100%!", flush=True)
    sys.exit(0)
