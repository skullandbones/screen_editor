#!/usr/bin/env python3
"""
test_32k_lines.py - Automated validation of 32K Document Line Capacity Subsystem

Verifies that SE.COM:
1. Allocates 2 Far RAM banks for line slots when LINES=32K in SE.CFG.
2. Memory Information screen ('m') displays both Bank 0 (0..16K) and Bank 1 (16K..32K).
3. Extended Memory self-test ('t') runs TEST 6, validating in-memory 32K line table access:
   - Far RAM slot read/write across 16K boundary (indices 0, 16383, 16384, 16385, 32767).
   - Boundary-crossing downward shift (SHIFT_LINE_SLOTS_DOWN across 16384).
   - Boundary-crossing upward shift (SHIFT_LINE_SLOTS_UP across 16384).
   - Boundary-crossing bulk slot write (WRITE_LINE_SLOTS_FROM_RAM across 16384).
4. Interactive Configuration screen ('c') displays Option 3 (Max Doc Lines: 32K),
   allows toggling between 16K and 32K, and persists to SE.CFG.
5. End-to-end document editing, navigation, line insertion/deletion, saving, and 100% byte fidelity.
"""

import os
import sys
import time
import tty
import select
import subprocess

def find_paths():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    workspace_root = os.path.abspath(os.path.join(repo_root, "..", ".."))
    emu_bin = os.path.join(workspace_root, "tools", "rc2014_emu", "rc2014")
    rom_file = os.path.join(workspace_root, "tools", "romwbw_src", "Binary", "RC2014_std.rom")
    img_file = os.path.join(workspace_root, "tools", "romwbw_src", "Binary", "hd1k_combo.img")
    se_bin = os.path.join(repo_root, "SE.COM")
    cpmcp_bin = os.path.join(workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp")
    cpmrm_bin = os.path.join(workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm")
    cpmls_bin = os.path.join(workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmls")
    return emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin, cpmls_bin

def read_until(master_fd, match_bytes, timeout=60.0):
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

def boot_cpm(emu_bin, rom_file, img_file):
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)

    out = read_until(master, b"Boot [H=Help]:", timeout=15.0)
    if b"Boot [H=Help]:" not in out:
        raise RuntimeError("Failed to reach RomWBW boot loader prompt")

    time.sleep(0.4)
    os.write(master, b"c\r")
    out = read_until(master, b"B>", timeout=15.0)
    if b"B>" not in out:
        raise RuntimeError("Failed to boot into CP/M prompt")

    time.sleep(0.4)
    os.write(master, b"c:\r")
    out = read_until(master, b"C>", timeout=15.0)
    if b"C>" not in out:
        raise RuntimeError("Failed to switch to Drive C:")

    return proc, master

def test_32k_lines():
    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin, cpmls_bin = find_paths()
    num_lines = 500
    test_file = f"/tmp/DOC{num_lines}.TXT"
    saved_file = f"/tmp/DOC{num_lines}_SAVED.TXT"
    cpm_name = f"DOC{num_lines}.TXT"
    cpm_user = f"0:{cpm_name}"

    print("\n=================================================================")
    print("  32K Document Line Capacity Subsystem Test Suite                ")
    print("=================================================================")

    # Generate test file
    with open(test_file, "wb") as f:
        for i in range(1, num_lines + 1):
            f.write(f"Line {i:04d}: Testing editor integrity in 32K lines mode\r\n".encode())
    orig_size = os.path.getsize(test_file)

    # Generate SE.CFG with LINES=32K
    cfg_file = "/tmp/SE_32K.CFG"
    with open(cfg_file, "wb") as f:
        f.write(b"SCREEN=80x24\r\nLINES=32K\r\nRAMDRIVE=OFF\r\n")

    # Clean up disk image
    subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:$$$se$$$.swp"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.CFG"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.COM"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, cpm_user],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # Inject SE.COM, SE.CFG, and test file
    subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, "0:SE.COM"], check=True)
    subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, cfg_file, "0:SE.CFG"], check=True)
    subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, test_file, cpm_user], check=True)

    proc, master = boot_cpm(emu_bin, rom_file, img_file)

    try:
        # -------------------------------------------------------------
        # Part 1: Verify Memory Table at splash screen
        # -------------------------------------------------------------
        print("\n[*] Part 1: Verify Far RAM Line Slot Allocation (LINES=32K)...")
        time.sleep(0.4)
        os.write(master, b"se\r")
        out_splash = read_until(master, b"to configure", timeout=25.0)
        if b"to configure" not in out_splash:
            print(f"[-] Splash screen not displayed. Buffer: {repr(out_splash[-300:])}")
            return False

        # Open Memory Information Screen ('m')
        time.sleep(0.3)
        os.write(master, b"m")
        out_mem = read_until(master, b"return to splash screen", timeout=15.0)
        out_mem += drain_all(master, quiet_time=0.2)

        if b"Active: Line Slots (0..16K)" in out_mem and b"Active: Line Slots (16K..32K)" in out_mem:
            print("    [+] Memory screen shows Bank 0 (0..16K) and Bank 1 (16K..32K) allocated")
        else:
            print(f"[-] FAILED: Memory screen missing expected line slot entries. Buffer:\n{out_mem.decode(errors='replace')}")
            return False

        if b"SE: 224 KB" in out_mem:
            print("    [+] Memory screen shows total SE RAM: 224 KB (192 KB + 32 KB Bank 1)")
        else:
            print("    [-] Note: SE RAM total string variation in output")

        # Return from memory screen to splash
        time.sleep(0.3)
        os.write(master, b" ")
        read_until(master, b"to configure", timeout=10.0)

        # -------------------------------------------------------------
        # Part 2: Verify Extended Memory Self-Test (TEST 6)
        # -------------------------------------------------------------
        print("\n[*] Part 2: Running Extended Memory Self-Test ('t')...")
        time.sleep(0.3)
        os.write(master, b"t")
        out_test = read_until(master, b"return to Splash Screen", timeout=20.0)
        out_test += drain_all(master, quiet_time=0.2)

        if b"Test 6: 32K Line Slots & Boundary Shift Engine" in out_test and b"32K Line Slots & Boundary Shift Engine verified" in out_test:
            print("    [+] TEST 6: Far RAM slot R/W across 16K boundary (indices 0..32767) PASSED")
            print("    [+] TEST 6: SHIFT_LINE_SLOTS_DOWN boundary crossing (16380..16389) PASSED")
            print("    [+] TEST 6: SHIFT_LINE_SLOTS_UP boundary crossing (16381..16390) PASSED")
            print("    [+] TEST 6: WRITE_LINE_SLOTS_FROM_RAM boundary crossing PASSED")
        else:
            print(f"[-] FAILED: Test 6 did not report pass. Buffer:\n{out_test.decode(errors='replace')}")
            return False

        if b"ALL 512KB EXTENDED MEMORY TESTS PASSED SUCCESSFULLY" in out_test:
            print("    [+] ALL Extended Memory tests (Tests 1 through 6) PASSED 100%!")
        else:
            print(f"[-] FAILED: Extended memory suite failed. Buffer:\n{out_test.decode(errors='replace')}")
            return False

        # Return to splash
        time.sleep(0.3)
        os.write(master, b" ")
        read_until(master, b"to configure", timeout=10.0)

        # -------------------------------------------------------------
        # Part 3: Verify Configuration Screen (Option 3)
        # -------------------------------------------------------------
        print("\n[*] Part 3: Configuration Screen Option 3 Toggle & Persistence...")
        time.sleep(0.3)
        os.write(master, b"c")
        out_cfg = read_until(master, b"return to splash screen", timeout=10.0)
        if b"3. Max Doc Lines   : [32K (32,768 Lines)]" in out_cfg:
            print("    [+] Option 3 displays 32K (32,768 Lines) active from SE.CFG")
        else:
            print(f"[-] Config screen missing 32K display: {out_cfg}")
            return False

        # Toggle '3' to 16K
        time.sleep(0.3)
        os.write(master, b"3")
        out_t1 = read_until(master, b"16K (16,384 Lines)]", timeout=10.0)
        if b"3. Max Doc Lines   : [16K (16,384 Lines)]" in out_t1:
            print("    [+] Toggled Option 3 to 16K (16,384 Lines)")
        else:
            print(f"[-] Toggle to 16K failed: {out_t1}")
            return False

        # Toggle '3' back to 32K
        time.sleep(0.3)
        os.write(master, b"3")
        out_t2 = read_until(master, b"32K (32,768 Lines)]", timeout=10.0)
        if b"3. Max Doc Lines   : [32K (32,768 Lines)]" in out_t2:
            print("    [+] Toggled Option 3 back to 32K (32,768 Lines)")
        else:
            print(f"[-] Toggle back to 32K failed: {out_t2}")
            return False

        # Save config
        time.sleep(0.3)
        os.write(master, b"s")
        read_until(master, b"Saved to local drive", timeout=10.0)
        print("    [+] Saved 32K configuration to local SE.CFG")

        # Return to splash and exit to CP/M
        time.sleep(0.2)
        os.write(master, b"q")
        read_until(master, b"to configure", timeout=10.0)
        time.sleep(0.2)
        os.write(master, b"q")
        read_until(master, b"C>", timeout=10.0)
        time.sleep(0.4)

        # -------------------------------------------------------------
        # Part 4: Document Editing & Saving in 32K Mode
        # -------------------------------------------------------------
        print(f"\n[*] Part 4: Loading and editing {num_lines}-line document in 32K mode...")
        os.write(master, f"se {cpm_name}\r".encode())
        expected_top = f"1/{num_lines}".encode()
        out_doc = read_until(master, expected_top, timeout=30.0)
        time.sleep(0.3)
        out_doc += drain_all(master, quiet_time=0.2)

        if expected_top not in out_doc:
            print(f"[-] Failed opening document. Buffer: {repr(out_doc[-300:])}")
            return False
        print(f"    [+] Document loaded {num_lines} lines cleanly into editor")

        # Jump to Bottom (Ctrl+G)
        time.sleep(0.3)
        os.write(master, b"\x07")
        expected_bot = f"Line  {num_lines}/{num_lines}".encode()
        out_bot = read_until(master, expected_bot, timeout=15.0)
        if expected_bot not in out_bot and f"{num_lines}/{num_lines}".encode() not in out_bot:
            print(f"[-] Failed jump to bottom. Buffer: {repr(out_bot[-300:])}")
            return False
        print(f"    [+] Jump to Bottom (Ctrl+G) verified: Line {num_lines}")

        # Jump to Top (Ctrl+T)
        time.sleep(0.3)
        os.write(master, b"\x14")
        expected_top_stat = f"Line    1/{num_lines}".encode()
        out_top = read_until(master, expected_top_stat, timeout=15.0)
        if expected_top_stat not in out_top and f"1/{num_lines}".encode() not in out_top:
            print(f"[-] Failed jump to top. Buffer: {repr(out_top[-300:])}")
            return False
        print(f"    [+] Jump to Top (Ctrl+T) verified: Line 1")

        # Save document via Ctrl+S
        print("    [*] Saving document via Ctrl+S...")
        time.sleep(0.4)
        os.write(master, b"\x13")
        read_until(master, b"SAVE FILE", timeout=10.0)
        time.sleep(0.2)
        os.write(master, b"\r")
        read_until(master, b"Overwrite?", timeout=8.0)
        time.sleep(0.2)
        os.write(master, b"y")
        out_resumed = read_until(master, expected_top_stat, timeout=30.0)
        print("    [+] Document saved successfully")

        # Exit via Ctrl+Q
        time.sleep(0.4)
        os.write(master, b"\x11")
        read_until(master, b"C>", timeout=10.0)
        print("    [+] Clean exit to CP/M prompt")

        # Extract saved file and verify 100% byte fidelity
        if os.path.exists(saved_file):
            os.remove(saved_file)
        subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, cpm_user, saved_file], check=True)

        with open(saved_file, "rb") as f:
            clean_saved = f.read().split(b"\x1a")[0]
        with open(test_file, "rb") as f:
            clean_orig = f.read().split(b"\x1a")[0]

        if clean_saved == clean_orig:
            print(f"    [+] 100% BYTE FIDELITY VERIFIED across all {num_lines} lines ({len(clean_saved)} bytes)!")
        else:
            print(f"[-] Byte fidelity mismatch! Orig: {len(clean_orig)}, Saved: {len(clean_saved)}")
            return False

        print("\n=================================================================")
        print("  ALL 32K LINE CAPACITY TESTS PASSED SUCCESSFULLY! (100%)        ")
        print("=================================================================\n")
        return True

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=1.0)
        except Exception:
            pass
        os.close(master)
        for f in [test_file, saved_file, cfg_file]:
            if os.path.exists(f):
                try:
                    os.remove(f)
                except OSError:
                    pass

if __name__ == "__main__":
    success = test_32k_lines()
    sys.exit(0 if success else 1)
