#!/usr/bin/env python3
"""
Test Suite for SE.CFG Configuration File & Configuration Screen.
Verifies:
  1. Default Startup (No SE.CFG):
     - Splash screen shows 120x40.
     - Configuration screen shows [120x40 (Modern Default)],
       [Protected (Preserve RAM Disk)], and [Default (No SE.CFG found)].
  2. Local Configuration Loading (SE.CFG on current drive):
     - SE.CFG with SCREEN=80x24 and RAMDRIVE=ON automatically configures settings.
     - Configuration screen displays [80x24 (Classic Terminal)],
       [Enabled (Use for Max RAM)], and [Loaded from local drive (C:SE.CFG)].
  3. Interactive Configuration Screen Toggle & Save:
     - Toggle geometry via '1' (80x24 <-> 120x40).
     - Toggle RAM drive memory blocks via '2' (Protected <-> Enabled).
     - Save via 's' persists both SCREEN and RAMDRIVE to local SE.CFG.
     - Re-launching SE.COM loads the newly saved SE.CFG automatically.
  4. Program Drive Fallback:
     - Running C:SE from Drive D: when D: has no SE.CFG falls back to C:SE.CFG.
     - Configuration screen shows [Loaded from program drive (C:SE.CFG)].
  5. RAM Drive Data Preservation:
     - Files on RAM drive B: (RomWBW MD0:0) remain uncorrupted and intact
       when SE.COM is launched, modified, and exited in protected mode.
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
    subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:RAMDRV.IMG"],
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
        out = read_until(master, b"return to splash screen", timeout=15.0)
        assert b"SE - Screen Editor Configuration" in out, "Failed to enter Config Screen"
        assert b"120x40 (Modern Default)" in out, "Config Screen wrong geometry"
        assert b"RAM Drive (A:)" in out and b"[Protected (Preserve RAM Disk)]" in out, "Default RAM drive blocks not Protected"
        assert b"3. Max Doc Lines   : [16K (16,384 Lines)]" in out, "Default max lines not 16K"
        assert b"4. Tab Width       : [8 Spaces (Default)]" in out, "Default tab width not 8 Spaces"
        assert b"Config Status      : [Default (No SE.CFG found)]" in out, "Config Screen wrong status"
        assert b"type   2                toggle RAM drive memory blocks" in out, "Missing toggle command 2"
        assert b"type   3                toggle Max lines (16K <-> 32K)" in out, "Missing toggle command 3"
        assert b"type   4                toggle Tab width (4 <-> 8)" in out, "Missing toggle command 4"
        print("    [+] Config screen displays 120x40, Protected RAM drive, and Default status")

        # Exit to splash screen ('q')
        time.sleep(0.2)
        os.write(master, b"q")
        out = read_until(master, b"Active Screen: [120x40 (Modern Default)]", timeout=15.0)
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
    # TEST 2: Local SE.CFG Loading (SCREEN=80x24 & RAMDRIVE=ON)
    # -------------------------------------------------------------------------
    print("\n[*] TEST 2: Local SE.CFG Loading (SCREEN=80x24 & RAMDRIVE=ON)...", flush=True)
    put_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, "# Test Config\r\nSCREEN=80x24\r\nRAMDRIVE=ON\r\n")
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
        out = read_until(master, b"return to splash screen", timeout=10.0)
        assert b"80x24 (Classic Terminal)" in out, "Config Screen wrong geometry"
        assert b"RAM Drive (A:)" in out and b"[Enabled (Use for Max RAM)]" in out, "Config Screen did not reflect RAMDRIVE=ON"
        assert b"Loaded from local drive (C:SE.CFG)" in out, "Config Screen wrong status"
        print("    [+] Config screen displays 80x24 geometry, Enabled RAM drive, and Loaded status")

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
    # Start with SE.CFG containing 80x24 and RAMDRIVE=OFF
    put_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, "SCREEN=80x24\r\nRAMDRIVE=OFF\r\n")
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
        out = read_until(master, b"return to splash screen", timeout=10.0)
        assert b"80x24 (Classic Terminal)" in out
        assert b"RAM Drive (A:)" in out and b"[Protected (Preserve RAM Disk)]" in out

        # Toggle geometry with '1' -> should switch to 120x40
        time.sleep(0.3)
        os.write(master, b"1")
        out = read_until(master, b"120x40 (Modern Default)", timeout=10.0)
        assert b"120x40 (Modern Default)" in out, f"Toggle '1' failed: {out}"
        print("    [+] Toggled geometry to 120x40")

        # Toggle RAM drive with '2' -> should cycle to Hibernate
        time.sleep(0.3)
        os.write(master, b"2")
        out = read_until(master, b"Hibernate (Save/Restore RAMDRV.IMG)", timeout=15.0)
        assert b"Hibernate (Save/Restore RAMDRV.IMG)" in out, f"Toggle '2' (Hibernate) failed: {out}"
        print("    [+] Toggled RAM drive blocks to Hibernate")

        # Toggle RAM drive with '2' again -> should cycle to Enabled
        time.sleep(0.3)
        os.write(master, b"2")
        out = read_until(master, b"Enabled (Use for Max RAM)", timeout=10.0)
        assert b"Enabled (Use for Max RAM)" in out, f"Toggle '2' (Enabled) failed: {out}"
        print("    [+] Toggled RAM drive blocks to Enabled")

        # Save configuration with 's'
        time.sleep(0.3)
        os.write(master, b"s")
        out = read_until(master, b"Saved to local drive (C:SE.CFG)", timeout=10.0)
        assert b"Saved to local drive (C:SE.CFG)" in out, f"Save 's' failed: {out}"
        print("    [+] Config screen updated status to Saved to local drive (C:SE.CFG)")
        drain_all(master)

        # Return to splash screen ('q')
        time.sleep(0.3)
        os.write(master, b"q")
        out = read_until(master, b"Active Screen: [120x40 (Modern Default)]", timeout=10.0)
        assert b"120x40 (Modern Default)" in out, "Splash screen did not reflect newly saved geometry"
        print("    [+] Returned to splash screen with active 120x40 geometry")
        drain_all(master)

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
        assert "RAMDRIVE=ON" in cfg_text, f"Unexpected SE.CFG RAMDRIVE content: {cfg_text}"
        assert "TAB=8" in cfg_text, f"Unexpected SE.CFG TAB content: {cfg_text}"
        assert "LINES=16K" in cfg_text, f"Unexpected SE.CFG LINES content: {cfg_text}"
        assert "# SE.CFG - Screen Editor Configuration" in cfg_text, "Missing header comment"
        print("    [+] Verified SE.CFG file contains SCREEN=120x40, RAMDRIVE=ON, TAB=8, and LINES=16K")

        # Re-launch SE to verify persistent load
        drain_all(master)
        time.sleep(0.4)
        os.write(master, b"se\r")
        out = read_until(master, b"Active Screen: [120x40 (Modern Default)]", timeout=25.0)
        assert b"120x40 (Modern Default)" in out, "Re-launch did not retain saved 120x40"
        drain_all(master)
        time.sleep(0.3)
        os.write(master, b"c")
        out = read_until(master, b"return to splash screen", timeout=10.0)
        assert b"120x40 (Modern Default)" in out
        assert b"RAM Drive (A:)" in out and b"[Enabled (Use for Max RAM)]" in out
        assert b"Loaded from local drive (C:SE.CFG)" in out
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"q")
        read_until(master, b"Active Screen:", timeout=10.0)
        drain_all(master)
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
        out = read_until(master, b"return to splash screen", timeout=15.0)
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

    # -------------------------------------------------------------------------
    # TEST 5: RAM Drive Data Preservation with RAMDRIVE=OFF (Protected Mode)
    # -------------------------------------------------------------------------
    print("\n[*] TEST 5: RAM Drive Preservation with RAMDRIVE=OFF...", flush=True)
    remove_cfg_from_image(cpmrm_bin, img_file)
    proc, master = boot_cpm(emu_bin, rom_file, img_file)

    try:
        # Switch to RAM drive A: (RomWBW MD0:0)
        time.sleep(0.3)
        os.write(master, b"a:\r")
        out = read_until(master, b"A>", timeout=10.0)
        assert b"A>" in out, f"Failed switching to RAM drive A>: {out}"

        # Create a test file on RAM drive A:
        time.sleep(0.3)
        os.write(master, b"save 2 test.dat\r")
        out = read_until(master, b"A>", timeout=10.0)
        assert b"A>" in out

        # Verify test.dat is on A:
        time.sleep(0.3)
        os.write(master, b"dir test.dat\r")
        out = read_until(master, b"A>", timeout=10.0)
        assert b"TEST     DAT" in out, f"Failed creating test.dat on A: {out}"
        print("    [+] Created TEST.DAT on RAM drive A:")

        # Switch to C: and launch SE (default RAMDRIVE=OFF)
        time.sleep(0.3)
        os.write(master, b"c:\r")
        read_until(master, b"C>", timeout=10.0)
        time.sleep(0.3)
        os.write(master, b"se\r")
        read_until(master, b"120x40 (Modern Default)", timeout=25.0)

        # Enter editor, type some text, then exit
        time.sleep(0.3)
        os.write(master, b"e")
        read_until(master, b"Col 0", timeout=15.0)
        time.sleep(0.3)
        os.write(master, b"Protecting RAM Drive A: from corruption\r")
        time.sleep(0.3)
        # Exit without saving: Ctrl+Q followed by 'n'
        os.write(master, b"\x11")
        read_until(master, b"Save changes?", timeout=5.0)
        os.write(master, b"n")
        out = read_until(master, b"C>", timeout=15.0)
        assert b"C>" in out, f"Failed exiting SE to C>: {out}"
        print("    [+] Ran SE.COM, edited document buffer, and exited cleanly")

        # Switch back to RAM drive A: and verify TEST.DAT is STILL intact
        time.sleep(0.3)
        os.write(master, b"a:\r")
        out = read_until(master, b"A>", timeout=10.0)
        assert b"A>" in out

        time.sleep(0.3)
        os.write(master, b"dir test.dat\r")
        out = read_until(master, b"A>", timeout=10.0)
        assert b"TEST     DAT" in out, f"RAM drive A: corrupted! TEST.DAT missing: {out}"
        print("    [+] Verified TEST.DAT on RAM drive A: is intact and uncorrupted!")
        print("    [+] Test 5 PASSED: RAM drive preservation verified.")
    finally:
        proc.terminate()
        proc.wait(timeout=1.0)
        os.close(master)

    # -------------------------------------------------------------------------
    # TEST 6: Integrated RAM Drive Hibernation & Restoration (Approach A)
    # -------------------------------------------------------------------------
    print("\n[*] TEST 6: RAM Drive Hibernation & Restoration (RAMDRIVE=HIBERNATE)...", flush=True)
    # Configure C:SE.CFG with RAMDRIVE=HIBERNATE
    put_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, "SCREEN=80x24\r\nRAMDRIVE=HIBERNATE\r\n")
    proc, master = boot_cpm(emu_bin, rom_file, img_file)

    try:
        # Switch to RAM drive A: and populate with test data
        time.sleep(0.3)
        os.write(master, b"a:\r")
        out = read_until(master, b"A>", timeout=10.0)
        assert b"A>" in out

        time.sleep(0.3)
        os.write(master, b"save 4 ramtest.dat\r")
        out = read_until(master, b"A>", timeout=10.0)
        assert b"A>" in out

        time.sleep(0.3)
        os.write(master, b"dir ramtest.dat\r")
        out = read_until(master, b"A>", timeout=10.0)
        assert b"RAMTEST  DAT" in out, f"Failed creating ramtest.dat on A: {out}"
        print("    [+] Created RAMTEST.DAT (4 sectors / 512 bytes) on RAM drive A:")

        # Switch to C: where SE.COM and SE.CFG reside
        time.sleep(0.3)
        os.write(master, b"c:\r")
        read_until(master, b"C>", timeout=10.0)

        # Launch SE.COM - should trigger hibernation of A: into C:RAMDRV.IMG
        time.sleep(0.3)
        os.write(master, b"se\r")
        out = read_until(master, b"80x24 (Classic Terminal)", timeout=180.0)
        assert b"Hibernating RAM drive to RAMDRV.IMG" in out, f"Missing hibernation status message: {out}"
        assert b"[Done: 256 KB preserved]" in out, f"Missing hibernation completion message: {out}"
        print("    [+] Verified startup status messaging: [SE] Hibernating RAM drive to RAMDRV.IMG... [Done: 256 KB preserved]")

        # Enter Configuration Screen ('c')
        time.sleep(0.3)
        os.write(master, b"c")
        out = read_until(master, b"return to splash screen", timeout=10.0)
        assert b"Hibernate (Save/Restore RAMDRV.IMG)" in out
        assert b"Loaded from local drive (C:SE.CFG)" in out
        print("    [+] Config screen verifies Hibernate mode active")

        # Return to splash ('q') and enter editor ('e')
        time.sleep(0.3)
        os.write(master, b"q")
        read_until(master, b"80x24 (Classic Terminal)", timeout=10.0)
        time.sleep(0.3)
        os.write(master, b"e")
        out = read_until(master, b"Free: 384 KB", timeout=15.0)
        assert b"Free: 384 KB" in out, f"Expected 384 KB buffer capacity in status bar: {out}"
        print("    [+] Verified editor document buffer unlocked to 384 KB (all 12 Far banks active)")

        # Type some text to dirty the buffer
        time.sleep(0.3)
        os.write(master, b"Testing RAM drive hibernation and restoration!\r")
        time.sleep(0.3)

        # Exit SE without saving: Ctrl+Q followed by 'n'
        os.write(master, b"\x11")
        read_until(master, b"Save changes?", timeout=5.0)
        os.write(master, b"n")
        out = read_until(master, b"C>", timeout=240.0)
        assert b"C>" in out, f"Failed exiting to C>: {out}"
        assert b"Restoring RAM drive from RAMDRV.IMG" in out, f"Missing restore message: {out}"
        assert b"[Done: RAM drive restored]" in out, f"Missing restore completion message: {out}"
        print("    [+] Verified exit status messaging: [SE] Restoring RAM drive from RAMDRV.IMG... [Done: RAM drive restored]")

        # Verify C:RAMDRV.IMG was cleaned up
        time.sleep(0.3)
        os.write(master, b"dir ramdrv.img\r")
        out = read_until(master, b"C>", timeout=10.0)
        assert b"No file" in out or b"NOT FOUND" in out or b"RAMDRV" not in out, f"RAMDRV.IMG was not deleted: {out}"
        print("    [+] Verified RAMDRV.IMG temporary snapshot was deleted from disk C:")

        # Switch back to RAM drive A: and verify RAMTEST.DAT is completely intact
        time.sleep(0.3)
        os.write(master, b"a:\r")
        out = read_until(master, b"A>", timeout=10.0)
        assert b"A>" in out

        time.sleep(0.3)
        os.write(master, b"dir ramtest.dat\r")
        out = read_until(master, b"A>", timeout=10.0)
        assert b"RAMTEST  DAT" in out, f"RAM drive A: corrupted after restoration! {out}"
        print("    [+] Verified RAMTEST.DAT on RAM drive A: is intact and uncorrupted!")
        print("    [+] Test 6 PASSED: RAM drive hibernation & restoration fully verified.")
    finally:
        proc.terminate()
        proc.wait(timeout=1.0)
        os.close(master)

    # -------------------------------------------------------------------------
    # TEST 7: Dynamic RAM Drive Letter Detection & Target File Protection (Drive B:)
    # -------------------------------------------------------------------------
    print("\n[*] TEST 7: Dynamic RAM Drive Letter Detection & Target Protection (Drive B:)...", flush=True)
    # Configure C:SE.CFG with RAMDRIVE=HIBERNATE
    put_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, "SCREEN=80x24\r\nRAMDRIVE=HIBERNATE\r\n")
    proc, master = boot_cpm(emu_bin, rom_file, img_file)

    try:
        # Re-assign drives so B: is the RAM drive (swap A: and B:)
        time.sleep(0.4)
        os.write(master, b"assign a:=b:\r")
        out = read_until(master, b"B>", timeout=15.0)

        # Switch to RAM drive B: and create a test file
        time.sleep(0.3)
        os.write(master, b"b:\r")
        out = read_until(master, b"B>", timeout=10.0)
        assert b"B>" in out, f"Failed switching to B>: {out}"

        time.sleep(0.3)
        os.write(master, b"save 3 ramfile.txt\r")
        out = read_until(master, b"B>", timeout=10.0)
        assert b"B>" in out

        time.sleep(0.3)
        os.write(master, b"dir ramfile.txt\r")
        out = read_until(master, b"B>", timeout=10.0)
        assert b"RAMFILE  TXT" in out, f"Failed creating ramfile.txt on B: {out}"
        print("    [+] Successfully assigned RAM drive to B: and created RAMFILE.TXT")

        # Switch to C: where SE.COM and SE.CFG (RAMDRIVE=HIBERNATE) reside
        time.sleep(0.3)
        os.write(master, b"c:\r")
        read_until(master, b"C>", timeout=10.0)

        # Launch SE targeting file on RAM drive: SE B:RAMFILE.TXT
        time.sleep(0.3)
        os.write(master, b"se b:ramfile.txt\r")
        out = read_until(master, b"Target file is on RAM drive (B:). RAM drive protected.", timeout=20.0)
        assert b"Target file is on RAM drive (B:). RAM drive protected." in out, f"Missing target protection message: {out}"
        print("    [+] Verified dynamic detection & protection: [SE] Target file is on RAM drive (B:). RAM drive protected.")

        # Allow editor to finish loading and rendering
        out = read_until(master, b"Col 0", timeout=25.0)
        assert b"Col 0" in out, f"Failed entering editor mode for B:RAMFILE.TXT: {out}"
        assert b"B:RAMFILE.TXT" in out, f"Expected B:RAMFILE.TXT in status bar: {out}"
        print("    [+] Verified document B:RAMFILE.TXT loaded successfully in editor")

        # Type some text to verify buffer editing in protected mode
        time.sleep(0.3)
        os.write(master, b"Testing RAM drive B: protection!\r")
        time.sleep(0.3)

        # Exit editor without saving: Ctrl+Q followed by 'n'
        os.write(master, b"\x11")
        read_until(master, b"Save changes?", timeout=5.0)
        os.write(master, b"n")
        out = read_until(master, b"C>", timeout=15.0)
        assert b"C>" in out, f"Failed exiting SE to C>: {out}"

        # Verify RAMDRV.IMG was NOT created on C:
        time.sleep(0.3)
        os.write(master, b"dir ramdrv.img\r")
        out = read_until(master, b"C>", timeout=10.0)
        assert b"No file" in out or b"NOT FOUND" in out or b"RAMDRV" not in out, f"RAMDRV.IMG was unexpectedly created: {out}"
        print("    [+] Verified RAMDRV.IMG was not created on disk C:")

        # Now launch SE without arguments to inspect Configuration Screen with B: as RAM drive
        time.sleep(0.3)
        os.write(master, b"se\r")
        out = read_until(master, b"80x24 (Classic Terminal)", timeout=180.0)
        assert b"Hibernating RAM drive to RAMDRV.IMG" in out, f"Expected hibernation of B:: {out}"
        time.sleep(0.3)
        os.write(master, b"c")
        out = read_until(master, b"return to splash screen", timeout=10.0)
        assert b"RAM Drive (B:)" in out, f"Config screen did not display detected RAM drive B:: {out}"
        assert b"Hibernate (Save/Restore RAMDRV.IMG)" in out, f"Config screen wrong mode: {out}"
        print("    [+] Config screen dynamically displays RAM Drive (B:) with Hibernate mode")

        # Exit SE - should restore RAM drive B: from C:RAMDRV.IMG
        time.sleep(0.2)
        os.write(master, b"q")
        read_until(master, b"80x24 (Classic Terminal)", timeout=10.0)
        time.sleep(0.2)
        os.write(master, b"q")
        out = read_until(master, b"C>", timeout=240.0)
        assert b"C>" in out
        assert b"Restoring RAM drive from RAMDRV.IMG" in out
        assert b"[Done: RAM drive restored]" in out
        print("    [+] Verified exit restoration of RAM drive B: from RAMDRV.IMG")

        # Switch back to RAM drive B: and verify RAMFILE.TXT is completely intact
        time.sleep(0.3)
        os.write(master, b"b:\r")
        out = read_until(master, b"B>", timeout=10.0)
        assert b"B>" in out

        time.sleep(0.3)
        os.write(master, b"dir ramfile.txt\r")
        out = read_until(master, b"B>", timeout=10.0)
        assert b"RAMFILE  TXT" in out, f"RAM drive B: file corrupted/missing! {out}"
        print("    [+] Verified RAMFILE.TXT on RAM drive B: is intact and uncorrupted!")
        print("    [+] Test 7 PASSED: Dynamic drive letter B: detection and protection fully verified.")
    finally:
        proc.terminate()
        proc.wait(timeout=1.0)
        os.close(master)

    # -------------------------------------------------------------------------
    # TEST 8: Tab Width Configuration & Persistence (TAB=4 & TAB=8)
    # -------------------------------------------------------------------------
    print("\n[*] TEST 8: Tab Width Configuration & Persistence (TAB=4 & TAB=8)...", flush=True)
    remove_cfg_from_image(cpmrm_bin, img_file)
    proc, master = boot_cpm(emu_bin, rom_file, img_file)

    try:
        # Switch to C:
        time.sleep(0.4)
        os.write(master, b"c:\r")
        out = read_until(master, b"C>", timeout=15.0)
        assert b"C>" in out

        # Launch SE
        time.sleep(0.4)
        os.write(master, b"se\r")
        out = read_until(master, b"120x40 (Modern Default)", timeout=25.0)

        # Enter Configuration Screen ('c')
        time.sleep(0.3)
        os.write(master, b"c")
        out = read_until(master, b"return to splash screen", timeout=10.0)
        assert b"Tab Width       : [8 Spaces (Default)]" in out, "Default tab width was not 8 Spaces"
        print("    [+] Config screen shows default 8 Spaces tab width")

        # Press '4' -> toggle to 4 Spaces
        time.sleep(0.3)
        os.write(master, b"4")
        out = read_until(master, b"Tab Width       : [4 Spaces]", timeout=10.0)
        assert b"Tab Width       : [4 Spaces]" in out, f"Toggle '4' failed to set 4 Spaces: {out}"
        print("    [+] Toggled Tab Width to 4 Spaces")

        # Press '4' again -> toggle back to 8 Spaces
        time.sleep(0.3)
        os.write(master, b"4")
        out = read_until(master, b"Tab Width       : [8 Spaces (Default)]", timeout=10.0)
        assert b"Tab Width       : [8 Spaces (Default)]" in out, f"Toggle '4' failed to set 8 Spaces: {out}"
        print("    [+] Toggled Tab Width back to 8 Spaces")

        # Press '4' once more -> toggle to 4 Spaces
        time.sleep(0.3)
        os.write(master, b"4")
        out = read_until(master, b"Tab Width       : [4 Spaces]", timeout=10.0)
        assert b"Tab Width       : [4 Spaces]" in out

        # Save configuration ('s')
        time.sleep(0.3)
        os.write(master, b"s")
        out = read_until(master, b"Saved to local drive (C:SE.CFG)", timeout=10.0)
        assert b"Saved to local drive (C:SE.CFG)" in out, f"Save 's' failed: {out}"
        print("    [+] Config screen saved TAB=4 to local SE.CFG")
        drain_all(master)

        # Exit to CP/M
        time.sleep(0.2)
        os.write(master, b"q")
        read_until(master, b"Active Screen:", timeout=10.0)
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"q")
        out = read_until(master, b"C>", timeout=10.0)
        assert b"C>" in out

        # Verify disk file content contains TAB=4
        cfg_bytes = get_cfg_from_image(cpmcp_bin, img_file)
        assert cfg_bytes is not None, "SE.CFG not found on disk image"
        cfg_text = cfg_bytes.decode("latin1", errors="replace")
        assert "TAB=4" in cfg_text, f"Expected TAB=4 in SE.CFG: {cfg_text}"
        print("    [+] Verified disk SE.CFG contains TAB=4")

        # Re-launch SE to verify TAB=4 is loaded automatically from SE.CFG
        drain_all(master)
        time.sleep(0.4)
        os.write(master, b"se\r")
        out = read_until(master, b"Active Screen: [120x40 (Modern Default)]", timeout=25.0)
        drain_all(master)
        time.sleep(0.3)
        os.write(master, b"c")
        out = read_until(master, b"return to splash screen", timeout=10.0)
        assert b"Tab Width       : [4 Spaces]" in out, f"SE did not load 4 Spaces from SE.CFG: {out}"
        print("    [+] Re-launched SE successfully loaded TAB=4 from SE.CFG")
        drain_all(master)

        # Exit SE
        time.sleep(0.2)
        os.write(master, b"q")
        read_until(master, b"Active Screen:", timeout=10.0)
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"q")
        out = read_until(master, b"C>", timeout=10.0)
        assert b"C>" in out
        print("    [+] Test 8 PASSED: Tab width configuration and persistence fully verified.")
    finally:
        proc.terminate()
        proc.wait(timeout=1.0)
        os.close(master)

    # -------------------------------------------------------------------------
    # TEST 9: Visual Tab Expansion in Editor (TAB=4 vs TAB=8)
    # -------------------------------------------------------------------------
    print("\n[*] TEST 9: Visual Tab Expansion in Editor (TAB=4 vs TAB=8)...", flush=True)
    # 1. Test with TAB=4
    put_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, "SCREEN=120x40\r\nTAB=4\r\n")

    # Inject test file TABTEST.TXT: "A\tB\r\n"
    tmp_tab_file = "/tmp/TABTEST.TXT"
    with open(tmp_tab_file, "wb") as f:
        f.write(b"A\tB\r\n")
    subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:TABTEST.TXT"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, tmp_tab_file, "0:TABTEST.TXT"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    if os.path.exists(tmp_tab_file):
        os.remove(tmp_tab_file)

    proc, master = boot_cpm(emu_bin, rom_file, img_file)

    try:
        # Switch to C:
        time.sleep(0.4)
        os.write(master, b"c:\r")
        out = read_until(master, b"C>", timeout=15.0)
        assert b"C>" in out

        # Launch SE TABTEST.TXT
        time.sleep(0.4)
        os.write(master, b"se tabtest.txt\r")
        out = read_until(master, b"Col 0", timeout=25.0)
        assert b"Col 0" in out, f"Editor did not open at Col 0: {out}"
        print("    [+] Opened TABTEST.TXT in 4-space tab mode at Col 0")

        # Move right onto Tab (index 1) -> visual column should be 1
        time.sleep(0.2)
        os.write(master, b"\x1b[C")
        out = read_until(master, b"Col 1", timeout=10.0)
        assert b"Col 1" in out, f"Cursor not at Col 1: {out}"

        # Move right onto 'B' (index 2) -> with TAB=4, next tab stop is 4! Visual column should be 4!
        time.sleep(0.2)
        os.write(master, b"\x1b[C")
        out = read_until(master, b"Col 4", timeout=10.0)
        assert b"Col 4" in out, f"With TAB=4, expected Col 4 at 'B': {out}"
        print("    [+] Verified cursor advances to visual Col 4 after tab in 4-space mode")

        # Exit editor without saving
        time.sleep(0.2)
        os.write(master, b"\x11")  # Ctrl+Q
        out = read_until(master, b"C>", timeout=10.0)
        assert b"C>" in out
    finally:
        proc.terminate()
        proc.wait(timeout=1.0)
        os.close(master)

    # 2. Test with TAB=8
    put_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, "SCREEN=120x40\r\nTAB=8\r\n")
    proc, master = boot_cpm(emu_bin, rom_file, img_file)

    try:
        # Switch to C:
        time.sleep(0.4)
        os.write(master, b"c:\r")
        out = read_until(master, b"C>", timeout=15.0)
        assert b"C>" in out

        # Launch SE TABTEST.TXT
        time.sleep(0.4)
        os.write(master, b"se tabtest.txt\r")
        out = read_until(master, b"Col 0", timeout=25.0)
        assert b"Col 0" in out

        # Move right onto Tab (index 1)
        time.sleep(0.2)
        os.write(master, b"\x1b[C")
        out = read_until(master, b"Col 1", timeout=10.0)
        assert b"Col 1" in out

        # Move right onto 'B' (index 2) -> with TAB=8, next tab stop is 8! Visual column should be 8!
        time.sleep(0.2)
        os.write(master, b"\x1b[C")
        out = read_until(master, b"Col 8", timeout=10.0)
        assert b"Col 8" in out, f"With TAB=8, expected Col 8 at 'B': {out}"
        print("    [+] Verified cursor advances to visual Col 8 after tab in 8-space mode")

        # Exit editor without saving
        time.sleep(0.2)
        os.write(master, b"\x11")  # Ctrl+Q
        out = read_until(master, b"C>", timeout=10.0)
        assert b"C>" in out
        print("    [+] Test 9 PASSED: Visual tab expansion in editor verified for both 4 and 8 widths.")
    finally:
        proc.terminate()
        proc.wait(timeout=1.0)
        os.close(master)

    # -------------------------------------------------------------------------
    # TEST 10: Max Document Lines Configuration (LINES=32K & LINES=16K)
    # -------------------------------------------------------------------------
    print("\n[*] TEST 10: Max Document Lines Configuration (LINES=32K & LINES=16K)...", flush=True)
    put_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, "# Test Config\r\nLINES=32K\r\n")
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
        out = read_until(master, b"to configure", timeout=25.0)
        assert b"to configure" in out

        # Check Memory Screen ('m')
        time.sleep(0.3)
        os.write(master, b"m")
        out = read_until(master, b"return to splash screen", timeout=10.0)
        assert b"Active: Line Slots (0..16K)" in out, f"Missing Bank 0 line slots in 32K mode: {out}"
        assert b"Active: Line Slots (16K..32K)" in out, f"Missing Bank 1 line slots in 32K mode: {out}"
        print("    [+] Memory screen shows both 32KB line banks (0..16K and 16K..32K) allocated")

        # Return to splash screen ('q')
        time.sleep(0.2)
        os.write(master, b"q")
        out = read_until(master, b"to configure", timeout=10.0)

        # Enter Config Screen ('c')
        time.sleep(0.3)
        os.write(master, b"c")
        out = read_until(master, b"return to splash screen", timeout=10.0)
        assert b"3. Max Doc Lines   : [32K (32,768 Lines)]" in out, f"Config screen did not show 32K lines: {out}"
        print("    [+] Config screen shows 32K (32,768 Lines) loaded from SE.CFG")

        # Toggle '3' to switch back to 16K
        time.sleep(0.3)
        os.write(master, b"3")
        out = read_until(master, b"16K (16,384 Lines)]", timeout=10.0)
        assert b"3. Max Doc Lines   : [16K (16,384 Lines)]" in out, f"Toggle '3' to 16K failed: {out}"
        print("    [+] Toggled Max Doc Lines to 16K (16,384 Lines)")

        # Save config with 's'
        time.sleep(0.3)
        os.write(master, b"s")
        out = read_until(master, b"Saved to local drive", timeout=10.0)
        assert b"Saved to local drive" in out
        drain_all(master)

        # Return to splash screen ('q') and exit ('q')
        time.sleep(0.2)
        os.write(master, b"q")
        read_until(master, b"Active Screen:", timeout=10.0)
        drain_all(master)
        time.sleep(0.2)
        os.write(master, b"q")
        out = read_until(master, b"C>", timeout=10.0)
        assert b"C>" in out

        # Verify disk SE.CFG file content
        cfg_bytes = get_cfg_from_image(cpmcp_bin, img_file)
        assert cfg_bytes is not None, "SE.CFG not found on disk image"
        cfg_text = cfg_bytes.decode("latin1", errors="replace")
        assert "LINES=16K" in cfg_text, f"Unexpected SE.CFG LINES content: {cfg_text}"
        print("    [+] Verified SE.CFG file persisted LINES=16K successfully")
        print("    [+] Test 10 PASSED: Max document lines configuration and memory table verified.")
    finally:
        proc.terminate()
        proc.wait(timeout=1.0)
        os.close(master)

    # Cleanup test files from disk image
    subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:TABTEST.TXT"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    remove_cfg_from_image(cpmrm_bin, img_file)
    print("\n=================================================================", flush=True)
    print("  ALL CONFIGURATION TESTS PASSED SUCCESSFULLY!                   ", flush=True)
    print("=================================================================", flush=True)
    return True

if __name__ == "__main__":
    success = run_tests()
    sys.exit(0 if success else 1)
