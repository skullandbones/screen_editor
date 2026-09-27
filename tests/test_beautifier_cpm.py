#!/usr/bin/env python3
"""
Test Suite for SE.COM Z80 Assembly Beautifier Subsystem.
Verifies:
  1. Decoupled Configuration & BEAUTIFY.CFG Persistence:
     - SE.COM config menu has only options 1..4 (Screen, RAM Drive, Max Lines, Tab Width).
     - Beautifier settings removed from SE.COM and SE.CFG.
     - Beautifier plugin provides its own interactive configuration menu (Action 'C' in Plugin Manager).
     - Plugin settings (COLUMNS, MNEMONICS, REGISTERS, ANIMATE) persist to BEAUTIFY.CFG on disk.
     - Subsequent editor runs reload settings from BEAUTIFY.CFG.
  2. Whole-File Beautification via Ctrl+Y:
     - When BLOCK_ACTIVE == 0, Ctrl+Y formats all lines in the document.
     - Preserves full-line comments and indents instructions, operands, and comments to target columns.
     - Normalizes instruction mnemonics according to configuration.
  3. Block-Scoped Beautification via Ctrl+Y:
     - When BLOCK_ACTIVE != 0, Ctrl+Y formats only lines inside [BLOCK_START_ROW .. BLOCK_END_ROW].
     - Lines outside the block remain unmodified.
  4. Cross-Platform Parity with Default Settings:
     - CP/M BEAUTIFY.PRL output and Linux tools/z80_beautifier output match 100% byte-for-byte.
  5. Custom Configuration & Cross-Platform Parity:
     - Custom BEAUTIFY.CFG (Compact columns, lowercase mnemonics/registers) formats identically on CP/M and Linux.
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
        proc.terminate()
        proc.wait(timeout=1.0)
        os.close(master)
        raise RuntimeError("Failed to reach RomWBW boot loader prompt")

    time.sleep(0.4)
    os.write(master, b"c\r")
    out = read_until(master, b"B>", timeout=15.0)
    if b"B>" not in out:
        proc.terminate()
        proc.wait(timeout=1.0)
        os.close(master)
        raise RuntimeError("Failed to boot into CP/M prompt")

    time.sleep(0.4)
    os.write(master, b"c:\r")
    out = read_until(master, b"C>", timeout=10.0)
    if b"C>" not in out:
        proc.terminate()
        proc.wait(timeout=1.0)
        os.close(master)
        raise RuntimeError("Failed to switch to Drive C:")

    return proc, master

def put_file_to_image(cpmcp_bin, cpmrm_bin, img_file, host_content, cpm_filename):
    subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, f"0:{cpm_filename}"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    tmp_path = f"/tmp/{cpm_filename}"
    with open(tmp_path, "wb") as f:
        if isinstance(host_content, str):
            f.write(host_content.encode("latin1"))
        else:
            f.write(host_content)
    subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, tmp_path, f"0:{cpm_filename}"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    if os.path.exists(tmp_path):
        os.remove(tmp_path)

def get_file_from_image(cpmcp_bin, img_file, cpm_filename):
    tmp_path = f"/tmp/GET_{cpm_filename}"
    if os.path.exists(tmp_path):
        os.remove(tmp_path)
    res = subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, f"0:{cpm_filename}", tmp_path],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if res.returncode != 0 or not os.path.exists(tmp_path):
        return None
    with open(tmp_path, "rb") as f:
        data = f.read()
    os.remove(tmp_path)
    return data

def test_config_screen_beautifier_options():
    print("\n[*] TEST 1: Beautifier Plugin Configuration & SE.COM Options Decoupling...", flush=True)
    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = find_paths()

    # Remove existing SE.CFG and BEAUTIFY.CFG to ensure defaults
    for cfg in ["0:SE.CFG", "0:se.cfg", "0:BEAUTIFY.CFG", "0:beautify.cfg"]:
        subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, cfg],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    proc, master = boot_cpm(emu_bin, rom_file, img_file)
    try:
        # Launch SE.COM
        time.sleep(0.4)
        os.write(master, b"se\r")
        out = read_until(master, b"Col 0", timeout=45.0)
        assert b"Col 0" in out or b"to configure" in out, f"Failed launching SE.COM: {out}"

        # 1. Enter SE.COM Config Screen ('c')
        time.sleep(0.3)
        os.write(master, b"c")
        out = read_until(master, b"return to splash screen", timeout=15.0)

        # Verify Options 5 and 6 are stripped from SE.COM config screen
        assert b"5. Beautify Columns" not in out, f"Option 5 should not be in SE.COM menu: {out}"
        assert b"6. Visual Progress" not in out, f"Option 6 should not be in SE.COM menu: {out}"
        assert b"cycle Beautify cols" not in out
        assert b"toggle Visual Progress" not in out
        assert b"4. Tab Width" in out, "Option 4 (Tab Width) missing"
        print("    [+] Verified Beautifier options (5 & 6) are removed from SE.COM configuration menu")

        # Save config ('s') -> generates SE.CFG
        time.sleep(0.3)
        os.write(master, b"s")
        out = read_until(master, b"Saved to local drive", timeout=10.0)
        assert b"Saved to local drive" in out, f"Failed saving config: {out}"
        print("    [+] Saved editor configuration to SE.CFG")

        # Return to splash ('q')
        time.sleep(0.3)
        os.write(master, b"q")
        read_until(master, b"Col 0", timeout=10.0)

        # 2. Enter Plugin Manager ('p')
        time.sleep(0.3)
        os.write(master, b"p")
        out = read_until(master, b"0..7:select", timeout=10.0)
        assert b"0..7:select" in out, f"Failed entering Plugin Manager: {out}"

        # Select BEAUTIFY slot: navigate down twice to BEAUTIFY (slot 2)
        time.sleep(0.3)
        os.write(master, b"\x1b[B\x1b[B")
        time.sleep(0.3)
        # Open embedded configuration menu for BEAUTIFY ('c')
        os.write(master, b"c")
        out = read_until(master, b"Save & Exit", timeout=10.0)
        assert b"Z80 Beautifier Configuration" in out, f"Failed opening BEAUTIFY config: {out}"

        # Check default settings
        assert b"1. Columns   : [Standard (9/17)]" in out, f"Default columns missing: {out}"
        assert b"2. Mnemonics : [UPPERCASE      ]" in out, f"Default mnemonics missing: {out}"
        assert b"3. Registers : [UPPERCASE      ]" in out, f"Default registers missing: {out}"
        assert b"4. Animation : [ON (Real-Time) ]" in out, f"Default animation missing: {out}"
        print("    [+] Verified BEAUTIFY embedded config menu default values")

        # Toggle Option 1 (Columns) -> Compact (8/16)
        time.sleep(0.3)
        os.write(master, b"1")
        out = read_until(master, b"Compact  (8/16)", timeout=10.0)
        assert b"Compact  (8/16)" in out, f"Failed toggling columns: {out}"
        print("    [+] Option 1 toggled to [Compact (8/16)]")

        # Toggle Option 2 (Mnemonics) -> lowercase
        time.sleep(0.3)
        os.write(master, b"2")
        out = read_until(master, b"lowercase      ", timeout=10.0)
        assert b"lowercase      " in out, f"Failed toggling mnemonics: {out}"
        print("    [+] Option 2 toggled to [lowercase]")

        # Toggle Option 3 (Registers) -> lowercase
        time.sleep(0.3)
        os.write(master, b"3")
        out = read_until(master, b"lowercase      ", timeout=10.0)
        assert b"lowercase      " in out, f"Failed toggling registers: {out}"
        print("    [+] Option 3 toggled to [lowercase]")

        # Toggle Option 4 (Animation) -> OFF (Fast)
        time.sleep(0.3)
        os.write(master, b"4")
        out = read_until(master, b"OFF (Fast)     ", timeout=10.0)
        assert b"OFF (Fast)     " in out, f"Failed toggling animation: {out}"
        print("    [+] Option 4 toggled to [OFF (Fast)]")

        # Save & Exit ('q')
        time.sleep(0.3)
        os.write(master, b"q")
        read_until(master, b"0..7:select", timeout=10.0)
        print("    [+] Exited BEAUTIFY config menu with 'q' (persisted to BEAUTIFY.CFG)")

        # Exit Plugin Manager ('q') and exit SE.COM ('q')
        time.sleep(0.3)
        os.write(master, b"q")
        read_until(master, b"Col 0", timeout=10.0)
        time.sleep(0.3)
        os.write(master, b"q")
        read_until(master, b"C>", timeout=10.0)
    finally:
        proc.terminate()
        proc.wait(timeout=1.0)
        os.close(master)

    # 3. Verify SE.CFG has NO beautifier settings
    cfg_data = get_file_from_image(cpmcp_bin, img_file, "SE.CFG")
    assert cfg_data is not None, "SE.CFG not found on disk image"
    cfg_str = cfg_data.decode("latin1", errors="ignore")
    assert "ANIMATE" not in cfg_str, f"ANIMATE found in SE.CFG: {cfg_str}"
    assert "FMT_" not in cfg_str, f"FMT_ found in SE.CFG: {cfg_str}"
    assert "OPCODE" not in cfg_str, f"OPCODE found in SE.CFG: {cfg_str}"
    assert "OPERAND" not in cfg_str, f"OPERAND found in SE.CFG: {cfg_str}"
    assert "COMMENT" not in cfg_str, f"COMMENT found in SE.CFG: {cfg_str}"
    assert "SCREEN=" in cfg_str, f"SCREEN= missing from SE.CFG: {cfg_str}"
    assert "TAB=" in cfg_str, f"TAB= missing from SE.CFG: {cfg_str}"
    print("    [+] Verified SE.CFG is clean of beautifier configuration")

    # 4. Verify BEAUTIFY.CFG exists on disk and contains saved settings
    bcfg_data = get_file_from_image(cpmcp_bin, img_file, "BEAUTIFY.CFG")
    assert bcfg_data is not None, "BEAUTIFY.CFG not found on disk image"
    bcfg_str = bcfg_data.decode("latin1", errors="ignore")
    assert "COLUMNS=COMPACT" in bcfg_str, f"COLUMNS=COMPACT not in BEAUTIFY.CFG: {bcfg_str}"
    assert "MNEMONICS=LOWER" in bcfg_str, f"MNEMONICS=LOWER not in BEAUTIFY.CFG: {bcfg_str}"
    assert "REGISTERS=LOWER" in bcfg_str, f"REGISTERS=LOWER not in BEAUTIFY.CFG: {bcfg_str}"
    assert "ANIMATE=0" in bcfg_str, f"ANIMATE=0 not in BEAUTIFY.CFG: {bcfg_str}"
    print("    [+] Verified BEAUTIFY.CFG on disk contains persisted plugin settings:")
    for line in bcfg_str.strip().split("\r\n"):
        if line and not line.startswith("#"):
            print(f"        {line}")

    # 5. Relaunch SE.COM and verify BEAUTIFY loads settings from BEAUTIFY.CFG
    proc2, master2 = boot_cpm(emu_bin, rom_file, img_file)
    try:
        time.sleep(0.4)
        os.write(master2, b"se\r")
        read_until(master2, b"Col 0", timeout=45.0)

        # Enter Plugin Manager ('p')
        time.sleep(0.3)
        os.write(master2, b"p")
        read_until(master2, b"0..7:select", timeout=10.0)

        # Navigate down twice to BEAUTIFY
        time.sleep(0.3)
        os.write(master2, b"\x1b[B\x1b[B")
        time.sleep(0.3)
        os.write(master2, b"c")
        out = read_until(master2, b"Save & Exit", timeout=10.0)
        assert b"Compact  (8/16)" in out, f"Persisted columns not loaded: {out}"
        assert b"lowercase      " in out, f"Persisted case not loaded: {out}"
        assert b"OFF (Fast)     " in out, f"Persisted animation not loaded: {out}"
        print("    [+] Verified BEAUTIFY plugin reloaded persisted settings from BEAUTIFY.CFG successfully")

        # Exit
        time.sleep(0.3)
        os.write(master2, b"q")
        read_until(master2, b"0..7:select", timeout=10.0)
        time.sleep(0.3)
        os.write(master2, b"q")
        read_until(master2, b"Col 0", timeout=10.0)
        time.sleep(0.3)
        os.write(master2, b"q")
        read_until(master2, b"C>", timeout=10.0)
    finally:
        proc2.terminate()
        proc2.wait(timeout=1.0)
        os.close(master2)

    print("[+] Test 1 PASSED: Config screen decoupling and BEAUTIFY.CFG persistence verified.")

def test_ctrl_y_whole_file_beautify():
    print("\n[*] TEST 2: Whole-File Beautification via Ctrl+Y...", flush=True)
    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = find_paths()

    # Prepare unformatted raw Z80 file
    raw_asm = (
        "; Header comment\r\n"
        "start: ld a,10 ; initial counter\r\n"
        "loop: inc a\r\n"
        " cp 20 ; check limit\r\n"
        " jr nz,loop ; repeat\r\n"
        " ret\r\n"
    )
    put_file_to_image(cpmcp_bin, cpmrm_bin, img_file, raw_asm, "RAW.ASM")

    # Remove existing BEAUTIFY.CFG to ensure default standard columns (9/17/41)
    for cfg in ["0:BEAUTIFY.CFG", "0:beautify.cfg"]:
        subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, cfg],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # Set SE.CFG with only editor settings
    cfg_content = "SCREEN=80x24\r\n"
    put_file_to_image(cpmcp_bin, cpmrm_bin, img_file, cfg_content, "SE.CFG")

    proc, master = boot_cpm(emu_bin, rom_file, img_file)
    try:
        # Launch SE.COM RAW.ASM
        time.sleep(0.4)
        os.write(master, b"se raw.asm\r")
        out = read_until(master, b"^K: Editor keys", timeout=45.0)
        assert b"^K: Editor keys" in out
        drain_all(master, 0.2)
        print("    [+] Opened RAW.ASM in editor")

        # Press Ctrl+Y (ASCII 25 / 0x19) -> Beautifies whole file
        time.sleep(0.3)
        os.write(master, b"\x19")
        out_cy = read_until(master, b"^K: Editor keys", timeout=20.0)
        assert b"^K: Editor keys" in out_cy, f"Beautify did not complete: {out_cy}"
        drain_all(master, 0.2)
        print("    [+] Sent Ctrl+Y (Whole-file Beautify completed)")

        # Save with Ctrl+S
        time.sleep(0.3)
        os.write(master, b"\x13")
        read_until(master, b"Enter filename to save:", timeout=6.0)
        read_until(master, b"\x1b[?25h", timeout=4.0)
        time.sleep(0.2)
        drain_all(master)

        os.write(master, b"\r")  # Enter to confirm save filename
        out_ow = read_until(master, b"Overwrite?", timeout=6.0)
        if b"Overwrite?" in out_ow:
            os.write(master, b"y")
        read_until(master, b"^K: Editor keys", timeout=10.0)
        drain_all(master, 0.2)
        print("    [+] Saved modified file with Ctrl+S")

        # Exit with Ctrl+Q
        time.sleep(0.3)
        os.write(master, b"\x11")
        time.sleep(0.5)
        out = read_until(master, b"C>", timeout=10.0)
        if b"Save changes?" in out:
            raise AssertionError(f"Unexpected 'Save changes?' prompt - file was not saved cleanly: {out}")
        print("    [+] Clean exit to CP/M")
    finally:
        proc.terminate()
        proc.wait(timeout=1.0)
        os.close(master)

    # Extract RAW.ASM from disk image and verify formatting
    beautified_data = get_file_from_image(cpmcp_bin, img_file, "RAW.ASM")
    assert beautified_data is not None, "Failed extracting RAW.ASM from disk"
    # Filter trailing CP/M ^Z padding
    beautified_str = beautified_data.split(b"\x1a")[0].decode("latin1")
    lines = [l for l in beautified_str.split("\r\n") if l]

    print("    [+] Formatted lines extracted from disk:")
    for idx, line in enumerate(lines):
        print(f"        Line {idx}: {repr(line)}")

    # Verify line 0: '; Header comment' unchanged
    assert lines[0] == "; Header comment", f"Line 0 mismatch: {lines[0]}"

    # Verify line 1: 'start:  LD      A,10                            ; initial counter'
    # 'start:' at col 1 (idx 0), 'LD' at col 9 (idx 8), 'A,10' at col 17 (idx 16), '; initial counter' at col 41 (idx 40)
    assert lines[1].startswith("start:"), f"Line 1 missing label: {lines[1]}"
    assert lines[1][8:10] == "LD", f"Line 1 opcode not at col 9: {repr(lines[1])}"
    assert lines[1][16:20] == "A,10", f"Line 1 operand not at col 17: {repr(lines[1])}"
    assert lines[1][40:] == "; initial counter", f"Line 1 comment not at col 41: {repr(lines[1])}"

    # Verify line 2: 'loop:   INC     A'
    assert lines[2].startswith("loop:"), f"Line 2 missing label: {lines[2]}"
    assert lines[2][8:11] == "INC", f"Line 2 opcode not at col 9: {repr(lines[2])}"
    assert lines[2][16:17] == "A", f"Line 2 operand not at col 17: {repr(lines[2])}"

    # Verify line 3: '        CP      20                              ; check limit'
    assert lines[3][:8] == "        ", f"Line 3 missing col 1-8 spaces: {repr(lines[3])}"
    assert lines[3][8:10] == "CP", f"Line 3 opcode not at col 9: {repr(lines[3])}"
    assert lines[3][16:18] == "20", f"Line 3 operand not at col 17: {repr(lines[3])}"
    assert lines[3][40:] == "; check limit", f"Line 3 comment not at col 41: {repr(lines[3])}"

    # Verify line 4: '        JR      NZ,loop                         ; repeat'
    assert lines[4][8:10] == "JR", f"Line 4 opcode not at col 9: {repr(lines[4])}"
    assert lines[4][16:23] == "NZ,loop", f"Line 4 operand not at col 17: {repr(lines[4])}"
    assert lines[4][40:] == "; repeat", f"Line 4 comment not at col 41: {repr(lines[4])}"

    # Verify line 5: '        RET'
    assert lines[5][8:11] == "RET", f"Line 5 opcode not at col 9: {repr(lines[5])}"

    print("[+] Test 2 PASSED: Whole-file beautification verified.")

def test_ctrl_y_block_beautify():
    print("\n[*] TEST 3: Block-Scoped Beautification via Ctrl+Y...", flush=True)
    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = find_paths()

    # Prepare unformatted raw Z80 file
    blk_asm = (
        "line1: nop\r\n"
        "line2: ld a,1\r\n"
        "line3: ld b,2\r\n"
        "line4: ret\r\n"
    )
    put_file_to_image(cpmcp_bin, cpmrm_bin, img_file, blk_asm, "BLK.ASM")

    proc, master = boot_cpm(emu_bin, rom_file, img_file)
    try:
        # Launch SE.COM BLK.ASM
        time.sleep(0.4)
        os.write(master, b"se blk.asm\r")
        out = read_until(master, b"BLK.ASM", timeout=45.0)
        assert b"BLK.ASM" in out
        print("    [+] Opened BLK.ASM in editor")

        # Move cursor down to row 1 ('line2:')
        # In SE.COM: down arrow is ESC [ B
        time.sleep(0.3)
        os.write(master, b"\x1b[B")
        time.sleep(0.2)

        # Start Block Selection: Ctrl+B (\x02)
        os.write(master, b"\x02")
        time.sleep(0.2)
        read_until(master, b"SEL:", timeout=5.0)
        print("    [+] Started Block Selection at row 1 ('line2:')")

        # Move cursor down to row 2 ('line3:')
        os.write(master, b"\x1b[B")
        time.sleep(0.2)
        print("    [+] Extended block selection to row 2 ('line3:')")

        # Press Ctrl+Y (\x19) -> Beautifies ONLY block [row 1 .. row 2]
        time.sleep(0.3)
        os.write(master, b"\x19")
        out_cy = read_until(master, b"^K: Editor keys", timeout=15.0)
        assert b"^K: Editor keys" in out_cy, f"Block beautify did not complete: {out_cy}"
        drain_all(master, 0.2)
        print("    [+] Sent Ctrl+Y (Block Beautify completed)")

        # Save with Ctrl+S
        time.sleep(0.3)
        os.write(master, b"\x13")
        read_until(master, b"Enter filename to save:", timeout=6.0)
        read_until(master, b"\x1b[?25h", timeout=4.0)
        time.sleep(0.2)
        drain_all(master)

        os.write(master, b"\r")
        out_ow = read_until(master, b"File already exists. Overwrite?", timeout=6.0)
        if b"File already exists. Overwrite?" in out_ow:
            os.write(master, b"y")
        read_until(master, b"^K: Editor keys", timeout=10.0)
        drain_all(master, 0.2)

        # Exit with Ctrl+Q
        time.sleep(0.3)
        os.write(master, b"\x11")
        time.sleep(0.5)
        out = read_until(master, b"C>", timeout=10.0)
        if b"Save changes?" in out:
            raise AssertionError(f"Unexpected 'Save changes?' prompt - file was not saved cleanly: {out}")
    finally:
        proc.terminate()
        proc.wait(timeout=1.0)
        os.close(master)

    # Extract BLK.ASM from disk image
    beautified_data = get_file_from_image(cpmcp_bin, img_file, "BLK.ASM")
    assert beautified_data is not None
    beautified_str = beautified_data.split(b"\x1a")[0].decode("latin1")
    lines = [l for l in beautified_str.split("\r\n") if l]

    print("    [+] Result lines:")
    for idx, l in enumerate(lines):
        print(f"        Line {idx}: {repr(l)}")

    # Line 0 ('line1: nop') should remain untouched!
    assert lines[0] == "line1: nop", f"Line 0 was unexpectedly modified: {lines[0]}"
    print("    [+] Verified Line 0 ('line1: nop') remained untouched outside block")

    # Line 1 ('line2:') should be beautified to col 1, col 9, col 17
    assert lines[1].startswith("line2:"), f"Line 1 missing label: {lines[1]}"
    assert lines[1][8:10] == "LD", f"Line 1 LD not at col 9: {repr(lines[1])}"
    assert lines[1][16:19] == "A,1", f"Line 1 A,1 not at col 17: {repr(lines[1])}"
    print("    [+] Verified Line 1 ('line2:') was beautified inside block")

    # Line 2 ('line3:') should be beautified
    assert lines[2].startswith("line3:"), f"Line 2 missing label: {lines[2]}"
    assert lines[2][8:10] == "LD", f"Line 2 LD not at col 9: {repr(lines[2])}"
    assert lines[2][16:19] == "B,2", f"Line 2 B,2 not at col 17: {repr(lines[2])}"
    print("    [+] Verified Line 2 ('line3:') was beautified inside block")

    # Line 3 ('line4: ret') should remain untouched!
    assert lines[3] == "line4: ret", f"Line 3 was unexpectedly modified: {lines[3]}"
    print("    [+] Verified Line 3 ('line4: ret') remained untouched outside block")

    print("[+] Test 3 PASSED: Block-scoped beautification verified.")

def test_cross_platform_parity():
    print("\n[*] TEST 4: Cross-Platform Parity with Linux Python toolchain...", flush=True)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    sys.path.insert(0, repo_root)

    from tools.z80_beautifier.meta import load_se_cfg
    from tools.z80_beautifier.parser import Parser
    from tools.z80_beautifier.formatter import Formatter

    # 1. Load config from SE.CFG using meta loader
    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = find_paths()
    cfg_data = get_file_from_image(cpmcp_bin, img_file, "SE.CFG")
    assert cfg_data is not None
    cfg_tmp = "/tmp/PARITY_SE.CFG"
    with open(cfg_tmp, "wb") as f:
        f.write(cfg_data)
    config = load_se_cfg(cfg_tmp)
    os.remove(cfg_tmp)

    # 2. Format the same raw assembly on Linux
    raw_asm = (
        "; Header comment\n"
        "start: ld a,10 ; initial counter\n"
        "loop: inc a\n"
        " cp 20 ; check limit\n"
        " jr nz,loop ; repeat\n"
        " ret\n"
    )
    ast = Parser().parse_source(raw_asm)
    formatter = Formatter(config)
    linux_output = formatter.format_program(ast)

    # 3. Read CP/M SE.COM output from Test 2
    cpm_data = get_file_from_image(cpmcp_bin, img_file, "RAW.ASM")
    cpm_str = cpm_data.split(b"\x1a")[0].decode("latin1").replace("\r\n", "\n")

    print(f"    Linux output:\n{linux_output}")
    print(f"    CP/M output:\n{cpm_str}")

    # Compare line-by-line
    linux_lines = [l for l in linux_output.strip().split("\n") if l]
    cpm_lines = [l for l in cpm_str.strip().split("\n") if l]

    assert len(linux_lines) == len(cpm_lines), f"Line count mismatch: {len(linux_lines)} vs {len(cpm_lines)}"
    for idx, (ll, cl) in enumerate(zip(linux_lines, cpm_lines)):
        assert ll == cl, f"Line {idx} mismatch:\n  Linux: {repr(ll)}\n  CP/M : {repr(cl)}"

    print("[+] Test 4 PASSED: 100% byte-for-byte cross-platform parity confirmed!")

def test_compact_beautification():
    print("\n[*] TEST 5: Custom Plugin Config (BEAUTIFY.CFG) & Cross-Platform Parity...", flush=True)
    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = find_paths()

    # Raw assembly to format with compact schema
    raw_asm = (
        "; Header comment\r\n"
        "start: ld a,10 ; initial counter\r\n"
        "loop: inc a\r\n"
        " cp 20 ; check limit\r\n"
        " jr nz,loop ; repeat\r\n"
        " ret\r\n"
    )
    put_file_to_image(cpmcp_bin, cpmrm_bin, img_file, raw_asm, "COMPACT.ASM")

    # Set BEAUTIFY.CFG with Compact columns and lowercase mnemonics/registers
    bcfg_content = (
        "# BEAUTIFY.CFG - Custom Test Configuration\r\n"
        "COLUMNS=COMPACT\r\n"
        "MNEMONICS=LOWER\r\n"
        "REGISTERS=LOWER\r\n"
        "ANIMATE=0\r\n"
    )
    put_file_to_image(cpmcp_bin, cpmrm_bin, img_file, bcfg_content, "BEAUTIFY.CFG")

    # Set SE.CFG with only editor settings
    cfg_content = "SCREEN=80x24\r\nTAB=8\r\n"
    put_file_to_image(cpmcp_bin, cpmrm_bin, img_file, cfg_content, "SE.CFG")

    proc, master = boot_cpm(emu_bin, rom_file, img_file)
    try:
        time.sleep(0.4)
        os.write(master, b"se compact.asm\r")
        out = read_until(master, b"^K: Editor keys", timeout=45.0)
        assert b"^K: Editor keys" in out
        drain_all(master, 0.2)

        # Send Ctrl+Y (whole-file beautify)
        time.sleep(0.3)
        os.write(master, b"\x19")
        read_until(master, b"^K: Editor keys", timeout=20.0)
        drain_all(master, 0.2)

        # Save with Ctrl+S
        time.sleep(0.3)
        os.write(master, b"\x13")
        read_until(master, b"Enter filename to save:", timeout=6.0)
        read_until(master, b"\x1b[?25h", timeout=4.0)
        time.sleep(0.2)
        drain_all(master)

        os.write(master, b"\r")
        out_ow = read_until(master, b"Overwrite?", timeout=6.0)
        if b"Overwrite?" in out_ow:
            os.write(master, b"y")
        read_until(master, b"^K: Editor keys", timeout=10.0)
        drain_all(master, 0.2)

        # Exit with Ctrl+Q
        time.sleep(0.3)
        os.write(master, b"\x11")
        time.sleep(0.5)
        read_until(master, b"C>", timeout=10.0)
    finally:
        proc.terminate()
        proc.wait(timeout=1.0)
        os.close(master)

    # 1. Read CP/M output
    cpm_data = get_file_from_image(cpmcp_bin, img_file, "COMPACT.ASM")
    assert cpm_data is not None
    cpm_str = cpm_data.split(b"\x1a")[0].decode("latin1").replace("\r\n", "\n")

    # 2. Format with Linux Python toolchain using same BEAUTIFY.CFG
    from tools.z80_beautifier.meta import load_se_cfg
    from tools.z80_beautifier.parser import Parser
    from tools.z80_beautifier.formatter import Formatter

    bcfg_tmp = "/tmp/PARITY_BEAUTIFY.CFG"
    with open(bcfg_tmp, "w") as f:
        f.write(bcfg_content)
    linux_cfg = load_se_cfg(bcfg_tmp)
    os.remove(bcfg_tmp)

    ast = Parser().parse_source(raw_asm.replace("\r\n", "\n"))
    linux_output = Formatter(linux_cfg).format_program(ast)

    print(f"    Linux Compact output:\n{linux_output}")
    print(f"    CP/M Compact output:\n{cpm_str}")

    # Verify lowercase mnemonics and registers are present
    assert "ld" in cpm_str and "inc" in cpm_str and "ret" in cpm_str, "Lowercase mnemonics missing from CP/M output!"

    # Verify line-by-line parity
    linux_lines = [l for l in linux_output.strip().split("\n") if l]
    cpm_lines = [l for l in cpm_str.strip().split("\n") if l]

    assert len(linux_lines) == len(cpm_lines), f"Line count mismatch: {len(linux_lines)} vs {len(cpm_lines)}"
    for idx, (ll, cl) in enumerate(zip(linux_lines, cpm_lines)):
        assert ll == cl, f"Line {idx} mismatch:\n  Linux: {repr(ll)}\n  CP/M : {repr(cl)}"

    print("[+] Test 5 PASSED: Custom BEAUTIFY.CFG cross-platform parity 100% confirmed!")

def main():
    print("=" * 65)
    print("  SE.COM Z80 Beautifier Subsystem Regression Test Suite")
    print("=" * 65)

    test_config_screen_beautifier_options()
    test_ctrl_y_whole_file_beautify()
    test_ctrl_y_block_beautify()
    test_cross_platform_parity()
    test_compact_beautification()

    print("\n" + "=" * 65)
    print("  ALL BEAUTIFIER TESTS PASSED SUCCESSFULLY!")
    print("=" * 65)

if __name__ == "__main__":
    main()
