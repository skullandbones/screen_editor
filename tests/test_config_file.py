#!/usr/bin/env python3
"""
Test Suite for SE.CFG Configuration File & Configuration Screen.
Verifies:
  1. Default Startup (No SE.CFG):
     - Splash screen shows 120x40.
     - Configuration screen shows [120x40 (Modern Default)] and [Default (No SE.CFG found)].
  2. Local Configuration Loading (SE.CFG on current drive):
     - SE.CFG with SCREEN=80x24 automatically configures 80x24 geometry at startup.
     - Configuration screen displays [80x24 (Classic Terminal)] and [Loaded from local drive (C:SE.CFG)].
  3. Interactive Configuration Screen Toggle & Save:
     - Toggle geometry via '1' (80x24 -> 120x40).
     - Save via 's' persists to local SE.CFG.
     - Configuration status updates to [Saved to local drive (C:SE.CFG)].
     - Return to splash shows [120x40 (Modern Default)].
     - Re-launching SE.COM loads the newly saved SE.CFG automatically.
  4. Program Drive Fallback:
     - Running C:SE from Drive B: when B: has no SE.CFG falls back to C:SE.CFG.
     - Configuration screen shows [Loaded from program drive (C:SE.CFG)].
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

def read_until(master_fd, match_bytes, timeout=20.0):
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

def boot_cpm(emu_bin, rom_file, img_file):
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)

    out = read_until(master, b"Boot [H=Help]:", timeout=8.0)
    if b"Boot [H=Help]:" not in out:
        raise RuntimeError("Failed to reach RomWBW boot loader prompt")

    time.sleep(0.4)
    os.write(master, b"c\r")
    out = read_until(master, b"B>", timeout=15.0)
    if b"B>" not in out:
        raise RuntimeError("Failed to boot into CP/M prompt")

    return proc, master

def remove_cfg_from_image(cpmrm_bin, img_file):
    subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.CFG"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def put_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, content_str):
    remove_cfg_from_image(cpmrm_bin, img_file)
    tmp_path = "/tmp/TEST_SE.CFG"
    with open(tmp_path, "wb") as f:
        f.write(content_str.encode("latin1"))
    subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, tmp_path, "0:SE.CFG"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    if os.path.exists(tmp_path):
        os.remove(tmp_path)

def get_cfg_from_image(cpmcp_bin, img_file):
    tmp_path = "/tmp/EXTRACT_SE.CFG"
    if os.path.exists(tmp_path):
        os.remove(tmp_path)
    res = subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.CFG", tmp_path],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if res.returncode != 0 or not os.path.exists(tmp_path):
        return None
    with open(tmp_path, "rb") as f:
        data = f.read()
    os.remove(tmp_path)
    return data

def run_tests():
    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = find_paths()
    print("=================================================================", flush=True)
    print("  SE.CFG Configuration Subsystem Regression Test Suite           ", flush=True)
    print("=================================================================", flush=True)

    # -------------------------------------------------------------------------
    # TEST 1: Default Startup (No SE.CFG)
    # -------------------------------------------------------------------------
    print("\n[*] TEST 1: Default Startup without SE.CFG...", flush=True)
    remove_cfg_from_image(cpmrm_bin, img_file)
    proc, master = boot_cpm(emu_bin, rom_file, img_file)

    try:
        # Switch to C:
        time.sleep(0.4)
        os.write(master, b"c:\r")
        out = read_until(master, b"C>", timeout=15.0)
        assert b"C>" in out, f"Failed switching to C: {out}"

        # Run SE
        time.sleep(0.4)
        os.write(master, b"se\r")
        out = read_until(master, b"120x40 (Modern Default)", timeout=25.0)
        assert b"120x40 (Modern Default)" in out, f"Splash did not show 120x40 default: {out}"
        assert b"type   c                to configure" in out, "Splash missing 'to configure' option"
        print("    [+] Splash screen shows 120x40 (Modern Default)")

        # Enter Configuration Screen ('c')
        time.sleep(0.3)
        os.write(master, b"c")
        out = read_until(master, b"Default (No SE.CFG found)", timeout=15.0)
        assert b"SE - Screen Editor Configuration" in out, "Failed to enter Config Screen"
        assert b"120x40 (Modern Default)" in out, "Config Screen wrong geometry"
        assert b"Default (No SE.CFG found)" in out, "Config Screen wrong status"
        print("    [+] Config screen displays 120x40 geometry and Default (No SE.CFG found) status")

        # Exit to splash screen ('q')
        time.sleep(0.2)
        os.write(master, b"q")
        out = read_until(master, b"120x40 (Modern Default)", timeout=15.0)
        assert b"120x40 (Modern Default)" in out, "Failed returning to splash"

        # Exit SE ('q')
        time.sleep(0.2)
        os.write(master, b"q")
        out = read_until(master, b"C>", timeout=15.0)
        assert b"C>" in out, "Failed exiting to C>"
        print("    [+] Test 1 PASSED: Default startup behaves correctly.")
    finally:
        proc.terminate()
        proc.wait(timeout=1.0)
        os.close(master)

    # -------------------------------------------------------------------------
    # TEST 2: Local SE.CFG Loading (SCREEN=80x24)
    # -------------------------------------------------------------------------
    print("\n[*] TEST 2: Local SE.CFG Loading (SCREEN=80x24)...", flush=True)
    put_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, "# Test Config\r\nSCREEN=80x24\r\n")
    proc, master = boot_cpm(emu_bin, rom_file, img_file)

    try:
        # Switch to C:
        time.sleep(0.4)
        os.write(master, b"c:\r")
        out = read_until(master, b"C>", timeout=15.0)
        assert b"C>" in out

        # Run SE
        time.sleep(0.4)
        os.write(master, b"se\r")
        out = read_until(master, b"80x24 (Classic Terminal)", timeout=25.0)
        assert b"80x24 (Classic Terminal)" in out, f"Splash did not load 80x24 from SE.CFG: {out}"
        print("    [+] Splash screen shows 80x24 (Classic Terminal) loaded from SE.CFG")

        # Enter Configuration Screen ('c')
        time.sleep(0.3)
        os.write(master, b"c")
        out = read_until(master, b"Loaded from local drive (C:SE.CFG)", timeout=10.0)
        assert b"80x24 (Classic Terminal)" in out, "Config Screen wrong geometry"
        assert b"Loaded from local drive (C:SE.CFG)" in out, "Config Screen wrong status"
        print("    [+] Config screen displays 80x24 geometry and Loaded from local drive (C:SE.CFG)")

        # Exit SE
        time.sleep(0.2)
        os.write(master, b"q")
        read_until(master, b"80x24 (Classic Terminal)", timeout=10.0)
        time.sleep(0.2)
        os.write(master, b"q")
        out = read_until(master, b"C>", timeout=10.0)
        assert b"C>" in out
        print("    [+] Test 2 PASSED: Local SE.CFG loaded and applied successfully.")
    finally:
        proc.terminate()
        proc.wait(timeout=1.0)
        os.close(master)

    # -------------------------------------------------------------------------
    # TEST 3: Interactive Toggle & Save to SE.CFG
    # -------------------------------------------------------------------------
    print("\n[*] TEST 3: Interactive Toggle & Save to SE.CFG...", flush=True)
    # Start with SE.CFG containing 80x24
    put_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, "SCREEN=80x24\r\n")
    proc, master = boot_cpm(emu_bin, rom_file, img_file)

    try:
        # Switch to C:
        time.sleep(0.4)
        os.write(master, b"c:\r")
        out = read_until(master, b"C>", timeout=10.0)
        assert b"C>" in out

        # Run SE
        time.sleep(0.4)
        os.write(master, b"se\r")
        out = read_until(master, b"80x24 (Classic Terminal)", timeout=25.0)
        assert b"80x24 (Classic Terminal)" in out

        # Enter Configuration Screen ('c')
        time.sleep(0.3)
        os.write(master, b"c")
        out = read_until(master, b"Loaded from local drive (C:SE.CFG)", timeout=10.0)
        assert b"80x24 (Classic Terminal)" in out

        # Toggle geometry with '1' -> should switch to 120x40
        time.sleep(0.3)
        os.write(master, b"1")
        out = read_until(master, b"120x40 (Modern Default)", timeout=10.0)
        assert b"120x40 (Modern Default)" in out, f"Toggle '1' failed: {out}"
        print("    [+] Toggled geometry to 120x40")

        # Save configuration with 's'
        time.sleep(0.3)
        os.write(master, b"s")
        out = read_until(master, b"Saved to local drive (C:SE.CFG)", timeout=10.0)
        assert b"Saved to local drive (C:SE.CFG)" in out, f"Save 's' failed: {out}"
        print("    [+] Config screen updated status to Saved to local drive (C:SE.CFG)")

        # Return to splash screen ('q')
        time.sleep(0.3)
        os.write(master, b"q")
        out = read_until(master, b"120x40 (Modern Default)", timeout=10.0)
        assert b"120x40 (Modern Default)" in out, "Splash screen did not reflect newly saved geometry"
        print("    [+] Returned to splash screen with active 120x40 geometry")

        # Exit SE ('q')
        time.sleep(0.3)
        os.write(master, b"q")
        out = read_until(master, b"C>", timeout=10.0)
        assert b"C>" in out

        # Verify disk file content
        cfg_bytes = get_cfg_from_image(cpmcp_bin, img_file)
        assert cfg_bytes is not None, "SE.CFG not found on disk image"
        cfg_text = cfg_bytes.decode("latin1", errors="replace")
        assert "SCREEN=120x40" in cfg_text, f"Unexpected SE.CFG content: {cfg_text}"
        assert "# SE.CFG - Screen Editor Configuration" in cfg_text, "Missing header comment"
        print("    [+] Verified SE.CFG file on disk contains valid header and SCREEN=120x40")

        # Re-launch SE to verify persistent load
        time.sleep(0.4)
        os.write(master, b"se\r")
        out = read_until(master, b"120x40 (Modern Default)", timeout=25.0)
        assert b"120x40 (Modern Default)" in out, "Re-launch did not retain saved 120x40"
        time.sleep(0.3)
        os.write(master, b"c")
        out = read_until(master, b"Loaded from local drive (C:SE.CFG)", timeout=10.0)
        assert b"120x40 (Modern Default)" in out
        assert b"Loaded from local drive (C:SE.CFG)" in out
        time.sleep(0.2)
        os.write(master, b"q")
        read_until(master, b"120x40 (Modern Default)", timeout=10.0)
        time.sleep(0.2)
        os.write(master, b"q")
        out = read_until(master, b"C>", timeout=10.0)
        assert b"C>" in out
        print("    [+] Test 3 PASSED: Interactive toggle, save, and reload fully verified.")
    finally:
        proc.terminate()
        proc.wait(timeout=1.0)
        os.close(master)

    # -------------------------------------------------------------------------
    # TEST 4: Program Drive Fallback (Run C:SE from Drive D:)
    # -------------------------------------------------------------------------
    print("\n[*] TEST 4: Program Drive Fallback (Run C:SE from Drive D:)...", flush=True)
    # Ensure C: has SE.CFG with SCREEN=80x24 and D: has no SE.CFG
    subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_1", img_file, "0:SE.CFG"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    put_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, "SCREEN=80x24\r\n")
    proc, master = boot_cpm(emu_bin, rom_file, img_file)

    try:
        # Switch to C: to log in slice 0
        time.sleep(0.4)
        os.write(master, b"c:\r")
        out = read_until(master, b"C>", timeout=15.0)
        assert b"C>" in out, f"Failed switching to C: {out}"

        # Switch to D: (slice 1)
        time.sleep(0.4)
        os.write(master, b"d:\r")
        out = read_until(master, b"D>", timeout=15.0)
        assert b"D>" in out, f"Failed switching to D: {out}"

        # Run C:SE from D>
        time.sleep(0.5)
        os.write(master, b"c:se\r")
        out = read_until(master, b"80x24 (Classic Terminal)", timeout=25.0)
        assert b"80x24 (Classic Terminal)" in out, f"C:SE from D> did not load 80x24: {out}"
        print("    [+] C:SE launched from D> successfully loaded 80x24 geometry from C:SE.CFG")

        # Allow splash screen and status bar to complete rendering
        read_until(master, b"Col 0", timeout=15.0)

        # Enter Configuration Screen ('c')
        time.sleep(0.3)
        os.write(master, b"c")
        out = read_until(master, b"Loaded from program drive (C:SE.CFG)", timeout=15.0)
        assert b"80x24 (Classic Terminal)" in out
        assert b"Loaded from program drive (C:SE.CFG)" in out, f"Expected program drive status: {out}"
        print("    [+] Config screen displays Loaded from program drive (C:SE.CFG)")

        # Exit back to splash screen ('q'), then exit to D> ('q')
        time.sleep(0.2)
        os.write(master, b"q")
        read_until(master, b"80x24 (Classic Terminal)", timeout=15.0)
        time.sleep(0.2)
        os.write(master, b"q")
        out = read_until(master, b"D>", timeout=15.0)
        assert b"D>" in out, f"Failed exiting to D>: {out}"
        print("    [+] Test 4 PASSED: Program drive fallback verified.")
    finally:
        proc.terminate()
        proc.wait(timeout=1.0)
        os.close(master)

    # Cleanup test SE.CFG from disk image
    remove_cfg_from_image(cpmrm_bin, img_file)
    print("\n=================================================================", flush=True)
    print("  ALL CONFIGURATION TESTS PASSED SUCCESSFULLY!                   ", flush=True)
    print("=================================================================", flush=True)
    return True

if __name__ == "__main__":
    success = run_tests()
    sys.exit(0 if success else 1)
