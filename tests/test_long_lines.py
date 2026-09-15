#!/usr/bin/env python3
"""
Test Suite for Multi-Stride Line Storage & Generalized Horizontal Scrolling.
Verifies:
  1. File loading of lines up to 500+ characters across chained Far-RAM strides.
  2. Horizontal scrolling and [Pan +<offset>] indicator in both 120x40 and 80x24 modes.
  3. 100% byte-for-byte fidelity when saving files containing lines > 126, 250, 300, 500 characters.
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
    cpmcp_bin = os.path.join(workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp")
    cpmrm_bin = os.path.join(workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm")

    return emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin

def read_until(master_fd, match_bytes, timeout=5.0):
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

def drain_all(master_fd, quiet_time=0.1):
    buf = b""
    while True:
        r, _, _ = select.select([master_fd], [], [], quiet_time)
        if not r:
            break
        try:
            data = os.read(master_fd, 2048)
            if not data:
                break
            buf += data
        except (BlockingIOError, OSError):
            break
    return buf

def run_long_lines_test():
    t_start = time.time()
    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = find_paths()

    for path, name in [(emu_bin, "Emulator"), (rom_file, "ROM"), (img_file, "Disk Image"),
                       (se_bin, "SE.COM"), (cpmcp_bin, "cpmcp"), (cpmrm_bin, "cpmrm")]:
        if not os.path.isfile(path):
            print(f"[-] {name} not found: {path}", flush=True)
            return False

    # 1. Prepare /tmp/LONGLINE.TXT with lines of lengths 50, 150, 300, 500, 20
    test_lines = [
        "A" * 50,
        "B" * 150,
        "C" * 300,
        "D" * 500,
        "E" * 20
    ]
    test_content = "\r\n".join(test_lines) + "\r\n"
    local_test_file = "/tmp/LONGLINE.TXT"
    local_saved_file = "/tmp/LONGLINE_SAVED.TXT"
    with open(local_test_file, "w", newline="") as f:
        f.write(test_content)

    print(f"[*] Created test file with {len(test_lines)} lines ({len(test_content)} bytes).", flush=True)

    # 2. Inject SE.COM and LONGLINE.TXT into modern hd1k combo image
    subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.COM"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, "0:SE.COM"], check=True)

    subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:LONGLINE.TXT"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, local_test_file, "0:LONGLINE.TXT"], check=True)
    print("[+] Injected SE.COM and LONGLINE.TXT into CP/M disk image.", flush=True)

    # 3. Launch emulator
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)

    try:
        # Boot loader
        out = read_until(master, b"Boot [H=Help]:", timeout=6.0)
        if b"Boot [H=Help]:" not in out:
            print("[-] Failed to reach RomWBW boot loader prompt.", flush=True)
            return False

        # Boot CP/M on ROM disk (Choice 'c') and switch to Drive C:
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
            print("[-] Failed to switch to Drive C:.", flush=True)
            return False
        print("[+] Switched to Drive C>.", flush=True)

        # ---------------------------------------------------------------------
        # Part 1: Open 'se LONGLINE.TXT' in default 120x40 mode
        # ---------------------------------------------------------------------
        print("[*] Part 1: Opening multi-stride file in 120x40 mode...", flush=True)
        time.sleep(0.5)
        os.write(master, b"se LONGLINE.TXT\r")
        out_load = read_until(master, b"Line    1/5", timeout=30.0)
        if b"LONGLINE.TXT" not in out_load or b"Line    1/5" not in out_load:
            print(f"[-] Failed to load LONGLINE.TXT. Buffer: {repr(out_load[-300:])}", flush=True)
            return False
        print("[+] LONGLINE.TXT loaded successfully: 5 lines verified in status bar.", flush=True)

        # Test extending Line 1 (50 chars) past column 119 barrier by interactive typing
        print("[*] Extending Line 1 past column 119 barrier by interactive typing...", flush=True)
        # Move to end of Line 1
        os.write(master, b"\x05") # Ctrl+E
        read_until(master, b"Col 50", timeout=4.0)
        # Type 75 'X' characters (reaching Col 125 > 119 barrier, engaging [Pan +40])
        for _ in range(75):
            os.write(master, b"X")
            time.sleep(0.01)
        out_type125 = read_until(master, b"Col 125", timeout=6.0)
        if b"Col 125" not in out_type125 or b"[Pan +40]" not in out_type125:
            print(f"[-] Failed to type past col 119 to col 125: {repr(out_type125[-250:])}", flush=True)
            return False
        # Type 25 more 'Y' characters (reaching Col 150)
        for _ in range(25):
            os.write(master, b"Y")
            time.sleep(0.01)
        out_type150 = read_until(master, b"Col 150", timeout=6.0)
        if b"Col 150" not in out_type150:
            print(f"[-] Failed to type to col 150: {repr(out_type150[-250:])}", flush=True)
            return False
        print("[+] Successfully verified interactive typing extends line past column 119 into [Pan +40]!", flush=True)
        # Reset cursor to Col 0 via Home
        os.write(master, b"\x01")
        read_until(master, b"Col 0", timeout=4.0)
        # Update expected test_lines[0] for Part 3 fidelity check
        test_lines[0] = "A" * 50 + "X" * 75 + "Y" * 25

        # Move to Line 2 (150 chars)
        time.sleep(0.2)
        os.write(master, b"\x1b[B")
        out_l2 = read_until(master, b"Line    2/5", timeout=4.0)
        if b"Line    2/5" not in out_l2:
            print(f"[-] Failed to move to Line 2. Buffer: {repr(out_l2[-200:])}", flush=True)
            return False

        # Move right across column 120 to trigger 120x40 viewport panning
        print("[*] Navigating past column 120 in 120-column mode...", flush=True)
        os.write(master, b"\x1b[C" * 125)
        out_pan120 = read_until(master, b"[Pan +40]", timeout=5.0)
        if b"[Pan +40]" not in out_pan120:
            print(f"[-] [Pan +40] not observed in 120-col mode. Buffer: {repr(out_pan120[-300:])}", flush=True)
            return False
        print("[+] Verified 120-column viewport panning: [Pan +40] active at column > 120.", flush=True)

        # Return cursor to column 0 via Home key (Ctrl+A / \x01)
        os.write(master, b"\x01")
        out_home = read_until(master, b"Col 0", timeout=4.0)
        if b"Col 0" not in out_home or b"^K: Editor keys" not in out_home:
            print(f"[-] Failed to reset pan via Home key. Buffer: {repr(out_home[-200:])}", flush=True)
            return False
        print("[+] Verified pan resets to [Pan +0] / default when cursor returns to left edge.", flush=True)

        # Move down to Line 3 (300 chars)
        os.write(master, b"\x1b[B")
        out_l3 = read_until(master, b"Line    3/5", timeout=4.0)
        if b"Line    3/5" not in out_l3:
            print(f"[-] Failed to move to Line 3. Buffer: {repr(out_l3[-200:])}", flush=True)
            return False

        # Verify 120-col mode: horizontal panning past column 238 into [Pan +200] and Col 300
        print("[*] Navigating Line 3 past column 238 into [Pan +200] in 120-column mode...", flush=True)
        os.write(master, b"\x05") # Ctrl+E (End key -> lands at Col 300)
        out_l3_end = read_until(master, b"Col 300", timeout=8.0)
        if b"Col 300" not in out_l3_end or b"[Pan +200]" not in out_l3_end:
            print(f"[-] Failed to pan past column 238 to [Pan +200] at Col 300: {repr(out_l3_end[-250:])}", flush=True)
            return False
        if b"CCCCCCCCCC" not in out_l3_end:
            print(f"[-] Line 3 disappeared at Col 300! Buffer: {repr(out_l3_end[-250:])}", flush=True)
            return False
        print("[+] Verified 120-col mode: Transition past column 238 cleanly pans to [Pan +200] and displays line content at Col 300!", flush=True)

        # Reset cursor to Col 0 via Home
        os.write(master, b"\x01")
        read_until(master, b"Col 0", timeout=4.0)

        # Move down to Line 4 (500 chars)
        os.write(master, b"\x1b[B")
        out_l4 = read_until(master, b"Line    4/5", timeout=4.0)
        if b"Line    4/5" not in out_l4:
            print(f"[-] Failed to move to Line 4. Buffer: {repr(out_l4[-200:])}", flush=True)
            return False
        print("[+] Verified Line 4 (500 characters) loaded into editor without crash.", flush=True)

        # Save the file using Ctrl+S and overwrite confirmation
        print("[*] Saving file via Ctrl+S...", flush=True)
        time.sleep(0.2)
        os.write(master, b"\x13")
        out_save_scr = read_until(master, b"SAVE FILE", timeout=8.0)
        if b"SAVE FILE" not in out_save_scr:
            print(f"[-] Save screen not reached. Buffer: {repr(out_save_scr[-200:])}", flush=True)
            return False

        # Press Enter to save with pre-filled name
        os.write(master, b"\r")
        out_ow = read_until(master, b"Overwrite?", timeout=6.0)
        if b"Overwrite?" not in out_ow:
            print(f"[-] Overwrite prompt not received. Buffer: {repr(out_ow[-200:])}", flush=True)
            return False

        # Confirm overwrite with 'y'
        os.write(master, b"y")
        out_resumed = read_until(master, b"Line    4/5", timeout=10.0)
        if b"LONGLINE.TXT" not in out_resumed:
            print(f"[-] Failed to resume editor after save. Buffer: {repr(out_resumed[-200:])}", flush=True)
            return False
        print("[+] File saved successfully and editor resumed.", flush=True)

        # ---------------------------------------------------------------------
        # Part 2: 80x24 Mode Horizontal Panning Verification
        # ---------------------------------------------------------------------
        print("[*] Part 2: Switching to 80x24 mode via splash screen...", flush=True)
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"for about", timeout=8.0)

        # Switch to 80x24 mode ('2')
        time.sleep(0.2)
        os.write(master, b"2")
        out_m80 = read_until(master, b"80x24 (Classic Terminal)", timeout=6.0)
        if b"80x24" not in out_m80:
            print("[-] Failed to switch to 80x24 mode in splash screen.", flush=True)
            return False
        time.sleep(0.2)
        drain_all(master)

        # Resume editor with 'e'
        os.write(master, b"e")
        out_80_load = read_until(master, b"Line    4/5", timeout=15.0)
        if b"Line    4/5" not in out_80_load:
            print(f"[-] Failed to resume LONGLINE.TXT in 80x24 mode. Buffer: {repr(out_80_load[-200:])}", flush=True)
            return False
        print("[+] LONGLINE.TXT resumed in 80x24 mode.", flush=True)

        # Move to Line 2 (150 chars): Up arrow twice
        time.sleep(0.2)
        os.write(master, b"\x1b[A\x1b[A")
        read_until(master, b"Line    2/5", timeout=4.0)

        # Move right across column 79 to column 85
        os.write(master, b"\x1b[C" * 85)
        out_pan80_40 = read_until(master, b"[Pan +40]", timeout=5.0)
        if b"[Pan +40]" not in out_pan80_40:
            print(f"[-] [Pan +40] not observed at col 85 in 80-col mode. Buffer: {repr(out_pan80_40[-300:])}", flush=True)
            return False
        print("[+] 80x24 mode: [Pan +40] verified at column 85.", flush=True)

        # Move right across column 119 to column 125
        os.write(master, b"\x1b[C" * 40)
        out_pan80_80 = read_until(master, b"[Pan +80]", timeout=5.0)
        if b"[Pan +80]" not in out_pan80_80:
            print(f"[-] [Pan +80] not observed at col 125 in 80-col mode. Buffer: {repr(out_pan80_80[-300:])}", flush=True)
            return False
        print("[+] 80x24 mode: [Pan +80] verified at column 125.", flush=True)

        # Move left across column 80 to column 75
        os.write(master, b"\x1b[D" * 50)
        out_pan80_back = read_until(master, b"[Pan +40]", timeout=5.0)
        if b"[Pan +40]" not in out_pan80_back:
            print(f"[-] [Pan +40] not observed on scroll-back in 80-col mode. Buffer: {repr(out_pan80_back[-300:])}", flush=True)
            return False
        print("[+] 80x24 mode: scroll-back to [Pan +40] verified.", flush=True)

        # Return to column 0 via Home key (Ctrl+A / \x01)
        os.write(master, b"\x01")
        out_pan80_zero = read_until(master, b"Col 0", timeout=4.0)
        if b"Col 0" not in out_pan80_zero or b"^K: Editor keys" not in out_pan80_zero:
            print(f"[-] Pan not reset to zero at Col 0 in 80-col mode. Buffer: {repr(out_pan80_zero[-200:])}", flush=True)
            return False
        print("[+] 80x24 mode: scroll-back to origin [Pan +0] verified.", flush=True)

        # Move to Line 3 (300 chars) in 80x24 mode and test panning past col 238
        print("[*] 80x24 mode: Navigating Line 3 past column 238 into [Pan +240]...", flush=True)
        os.write(master, b"\x1b[B")
        read_until(master, b"Line    3/5", timeout=4.0)
        os.write(master, b"\x05") # Ctrl+E -> Col 300
        out_end80_l3 = read_until(master, b"Col 300", timeout=8.0)
        if b"Col 300" not in out_end80_l3 or b"[Pan +240]" not in out_end80_l3:
            print(f"[-] 80x24 mode: End key failed to reach [Pan +240] at Col 300: {repr(out_end80_l3[-250:])}", flush=True)
            return False
        if b"CCCCCCCCCC" not in out_end80_l3:
            print(f"[-] Line 3 disappeared in 80-col mode at Col 300! Buffer: {repr(out_end80_l3[-250:])}", flush=True)
            return False
        print("[+] 80x24 mode: Transition past column 238 cleanly reaches [Pan +240] with line visible at Col 300!", flush=True)

        # Reset pan via Home
        os.write(master, b"\x01")
        read_until(master, b"Col 0", timeout=4.0)

        # Exit editor with Ctrl+Q (document clean, returns directly to C>)
        time.sleep(0.2)
        os.write(master, b"\x11")
        out_cpm = read_until(master, b"C>", timeout=6.0)
        if b"C>" not in out_cpm:
            print(f"[-] Clean exit with Ctrl+Q failed. Buffer: {repr(out_cpm[-200:])}", flush=True)
            return False
        print("[+] Returned cleanly to CP/M prompt.", flush=True)

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

    # -------------------------------------------------------------------------
    # Part 3: Byte-for-Byte Fidelity Verification of Saved File
    # -------------------------------------------------------------------------
    print("[*] Part 3: Extracting saved file and verifying 100% data fidelity...", flush=True)
    if os.path.isfile(local_saved_file):
        os.remove(local_saved_file)

    subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, "0:LONGLINE.TXT", local_saved_file], check=True)

    with open(local_saved_file, "rb") as f:
        saved_raw = f.read()

    # Strip CP/M sector EOF padding (0x1A / ^Z)
    saved_trimmed = saved_raw.rstrip(b"\x1a")
    saved_lines = saved_trimmed.decode("ascii", errors="replace").split("\r\n")
    if saved_lines and saved_lines[-1] == "":
        saved_lines.pop()

    print(f"[+] Saved file read: {len(saved_lines)} lines, {len(saved_trimmed)} bytes.", flush=True)

    if len(saved_lines) != len(test_lines):
        print(f"[-] Line count mismatch: got {len(saved_lines)}, expected {len(test_lines)}.", flush=True)
        return False

    for idx, (expected, actual) in enumerate(zip(test_lines, saved_lines), 1):
        if len(actual) != len(expected):
            print(f"[-] Line {idx} length mismatch: got {len(actual)}, expected {len(expected)}.", flush=True)
            return False
        if actual != expected:
            print(f"[-] Line {idx} content mismatch!", flush=True)
            return False
        print(f"[+] Line {idx} (length {len(actual)}): 100% BYTE-FOR-BYTE MATCH!", flush=True)

    elapsed = time.time() - t_start
    print(f"[*] ALL MULTI-STRIDE & HORIZONTAL PANNING TESTS PASSED in {elapsed:.2f}s!", flush=True)
    return True

if __name__ == "__main__":
    success = run_long_lines_test()
    sys.exit(0 if success else 1)
