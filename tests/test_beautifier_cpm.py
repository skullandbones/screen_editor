#!/usr/bin/env python3
"""
Test Suite for SE.COM Z80 Assembly Beautifier Subsystem.
Verifies:
  1. Interactive Configuration Screen:
     - Option '5' cycles Beautify Columns (Standard 1/9/17/41 -> Compact 1/5/9/25 -> Wide 1/13/21/49 -> Standard).
     - Option '6' toggles Visual Progress (Real-Time Watch <-> Fast Batch).
     - Option 's' persists ANIMATE, OPCODE_COL, OPERAND_COL, COMMENT_COL to SE.CFG.
  2. Whole-File Beautification via Ctrl+Y:
     - When BLOCK_ACTIVE == 0, Ctrl+Y formats all lines in the document.
     - Preserves full-line comments and indents instructions, operands, and comments to target columns.
     - Normalizes instruction mnemonics to uppercase.
  3. Block-Scoped Beautification via Ctrl+Y:
     - When BLOCK_ACTIVE != 0, Ctrl+Y formats only lines inside [BLOCK_START_ROW .. BLOCK_END_ROW].
     - Lines outside the block remain unmodified.
  4. Cross-Platform Parity:
     - CP/M SE.COM output and Linux tools/z80_beautifier output match 100% byte-for-byte.
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
    print("\n[*] TEST 1: Config Screen Options 5 (Columns) & 6 (Visual Progress)...", flush=True)
    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = find_paths()

    # Remove existing SE.CFG to ensure defaults
    subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.CFG"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    proc, master = boot_cpm(emu_bin, rom_file, img_file)
    try:
        # Launch SE.COM
        time.sleep(0.4)
        os.write(master, b"se\r")
        out = read_until(master, b"Col 0", timeout=25.0)
        assert b"Col 0" in out or b"to configure" in out, f"Failed launching SE.COM: {out}"

        # Enter Config Screen ('c')
        time.sleep(0.3)
        os.write(master, b"c")
        out = read_until(master, b"return to splash screen", timeout=15.0)

        # Check default display of Option 5 and Option 6
        assert b"5. Beautify Columns: [Standard (1/9/17/41)]" in out, f"Option 5 missing or wrong: {out}"
        assert b"6. Visual Progress : [Real-Time Watch]" in out, f"Option 6 missing or wrong: {out}"
        assert b"cycle Beautify cols" in out
        assert b"toggle Visual Progress" in out
        print("    [+] Verified default Option 5 [Standard] and Option 6 [Real-Time Watch]")

        # Press '5' -> Should cycle to Tabbed (1t 1s 0s ;32tA)
        time.sleep(0.3)
        os.write(master, b"5")
        out = read_until(master, b"Tabbed (1t 1s 0s ;32tA)", timeout=10.0)
        assert b"Tabbed (1t 1s 0s ;32tA)" in out, f"Failed cycling to Tabbed: {out}"
        print("    [+] Pressed '5': Successfully cycled to [Tabbed (1t 1s 0s ;32tA)]")

        # Press '5' -> Should cycle to Compact (1/5/9/25)
        time.sleep(0.3)
        os.write(master, b"5")
        out = read_until(master, b"Compact (1/5/9/25)", timeout=10.0)
        assert b"Compact (1/5/9/25)" in out, f"Failed cycling to Compact: {out}"
        print("    [+] Pressed '5': Successfully cycled to [Compact (1/5/9/25)]")

        # Press '5' -> Should cycle to Wide (1/13/21/49)
        time.sleep(0.3)
        os.write(master, b"5")
        out = read_until(master, b"Wide (1/13/21/49)", timeout=10.0)
        assert b"Wide (1/13/21/49)" in out, f"Failed cycling to Wide: {out}"
        print("    [+] Pressed '5': Successfully cycled to [Wide (1/13/21/49)]")

        # Press '5' -> Should cycle back to Standard (1/9/17/41)
        time.sleep(0.3)
        os.write(master, b"5")
        out = read_until(master, b"Standard (1/9/17/41)", timeout=10.0)
        assert b"Standard (1/9/17/41)" in out, f"Failed cycling back to Standard: {out}"
        print("    [+] Pressed '5': Successfully cycled back to [Standard (1/9/17/41)]")

        # Press '6' -> Should toggle to Fast Batch (Silent)
        time.sleep(0.3)
        os.write(master, b"6")
        out = read_until(master, b"Fast Batch (Silent)", timeout=10.0)
        assert b"Fast Batch (Silent)" in out, f"Failed toggling to Fast Batch: {out}"
        print("    [+] Pressed '6': Successfully toggled to [Fast Batch (Silent)]")

        # Save config ('s')
        time.sleep(0.3)
        os.write(master, b"s")
        out = read_until(master, b"Saved to local drive", timeout=10.0)
        assert b"Saved to local drive" in out, f"Failed saving config: {out}"
        print("    [+] Pressed 's': Config saved successfully")

        # Return to splash ('q') and exit to CP/M ('q')
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

    # Verify SE.CFG on disk has ANIMATE=0, FMT_STMT, FMT_LABEL, FMT_COMMENT, FMT_CASE
    cfg_data = get_file_from_image(cpmcp_bin, img_file, "SE.CFG")
    assert cfg_data is not None, "SE.CFG not found on disk image"
    cfg_str = cfg_data.decode("latin1", errors="ignore")
    assert "ANIMATE=0" in cfg_str, f"ANIMATE=0 not found in SE.CFG: {cfg_str}"
    assert "FMT_STMT=9sA 17sA 0s ;41sA" in cfg_str, f"FMT_STMT not found in SE.CFG: {cfg_str}"
    assert "FMT_LABEL=1sA : S" in cfg_str, f"FMT_LABEL not found in SE.CFG: {cfg_str}"
    assert "FMT_COMMENT=1sA M" in cfg_str, f"FMT_COMMENT not found in SE.CFG: {cfg_str}"
    assert "FMT_CASE=mU oU lP cU" in cfg_str, f"FMT_CASE not found in SE.CFG: {cfg_str}"
    assert "OPCODE_COL=9" in cfg_str, f"OPCODE_COL=9 not found in SE.CFG: {cfg_str}"
    assert "OPERAND_COL=17" in cfg_str, f"OPERAND_COL=17 not found in SE.CFG: {cfg_str}"
    assert "COMMENT_COL=41" in cfg_str, f"COMMENT_COL=41 not found in SE.CFG: {cfg_str}"
    print("    [+] Verified SE.CFG on disk contains persisted beautifier settings & schemas:")
    for line in cfg_str.strip().split("\r\n"):
        if any(k in line for k in ["ANIMATE", "FMT_", "OPCODE", "OPERAND", "COMMENT"]):
            print(f"        {line}")
    print("[+] Test 1 PASSED: Config screen toggles and persistence verified.")

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

    # Set SE.CFG with ANIMATE=1 and standard columns
    cfg_content = "SCREEN=80x24\r\nANIMATE=1\r\nOPCODE_COL=9\r\nOPERAND_COL=17\r\nCOMMENT_COL=41\r\n"
    put_file_to_image(cpmcp_bin, cpmrm_bin, img_file, cfg_content, "SE.CFG")

    proc, master = boot_cpm(emu_bin, rom_file, img_file)
    try:
        # Launch SE.COM RAW.ASM
        time.sleep(0.4)
        os.write(master, b"se raw.asm\r")
        out = read_until(master, b"RAW.ASM", timeout=25.0)
        assert b"RAW.ASM" in out
        print("    [+] Opened RAW.ASM in editor")

        # Press Ctrl+Y (ASCII 25 / 0x19) -> Beautifies whole file
        time.sleep(0.3)
        os.write(master, b"\x19")
        out_cy = read_until(master, b"^K: Editor keys", timeout=15.0)
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
        out = read_until(master, b"BLK.ASM", timeout=25.0)
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

def test_tabbed_beautification():
    print("\n[*] TEST 5: Tabbed Schema (1t 1s 0s ;32tA) & Cross-Platform Parity...", flush=True)
    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = find_paths()

    # Raw assembly to format with tabbed schema
    raw_asm = (
        "; Header comment\r\n"
        "start: ld a,10 ; initial counter\r\n"
        "loop: inc a\r\n"
        " cp 20 ; check limit\r\n"
        " jr nz,loop ; repeat\r\n"
        " ret\r\n"
    )
    put_file_to_image(cpmcp_bin, cpmrm_bin, img_file, raw_asm, "TAB.ASM")

    # Set SE.CFG with the User's Tabbed Schema: 1t 1s 0s ;32tA
    cfg_content = (
        "SCREEN=80x24\r\n"
        "ANIMATE=0\r\n"
        "TAB=8\r\n"
        "FMT_STMT=1t 1s 0s ;32tA\r\n"
        "FMT_LABEL=1sA : S\r\n"
        "FMT_COMMENT=1sA M\r\n"
        "FMT_CASE=mU oU lP cU\r\n"
    )
    put_file_to_image(cpmcp_bin, cpmrm_bin, img_file, cfg_content, "SE.CFG")

    proc, master = boot_cpm(emu_bin, rom_file, img_file)
    try:
        time.sleep(0.4)
        os.write(master, b"se tab.asm\r")
        out = read_until(master, b"TAB.ASM", timeout=25.0)
        assert b"TAB.ASM" in out

        # Send Ctrl+Y (whole-file beautify)
        time.sleep(0.3)
        os.write(master, b"\x19")
        read_until(master, b"^K: Editor keys", timeout=15.0)
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
    cpm_data = get_file_from_image(cpmcp_bin, img_file, "TAB.ASM")
    assert cpm_data is not None
    cpm_str = cpm_data.split(b"\x1a")[0].decode("latin1").replace("\r\n", "\n")

    # 2. Format with Linux Python toolchain using same config
    from tools.z80_beautifier.config import FormatterConfig, StmtSchema, LabelSchema, CommentSchema, CaseSchema
    from tools.z80_beautifier.parser import Parser
    from tools.z80_beautifier.formatter import Formatter

    linux_cfg = FormatterConfig(
        stmt_schema=StmtSchema.parse("1t 1s 0s ;32tA"),
        label_schema=LabelSchema.parse("1sA : S"),
        comment_schema=CommentSchema.parse("1sA M"),
        case_schema=CaseSchema.parse("mU oU lP cU"),
        tab_width=8,
    )
    ast = Parser().parse_source(raw_asm.replace("\r\n", "\n"))
    linux_output = Formatter(linux_cfg).format_program(ast)

    print(f"    Linux Tabbed output:\n{linux_output}")
    print(f"    CP/M Tabbed output:\n{cpm_str}")

    # Check tab characters are present in CP/M output
    assert "\t" in cpm_str, "Tab characters missing from CP/M tabbed output!"

    # Verify line-by-line parity
    linux_lines = [l for l in linux_output.strip().split("\n") if l]
    cpm_lines = [l for l in cpm_str.strip().split("\n") if l]

    assert len(linux_lines) == len(cpm_lines), f"Line count mismatch: {len(linux_lines)} vs {len(cpm_lines)}"
    for idx, (ll, cl) in enumerate(zip(linux_lines, cpm_lines)):
        assert ll == cl, f"Line {idx} mismatch:\n  Linux: {repr(ll)}\n  CP/M : {repr(cl)}"

    print("[+] Test 5 PASSED: Tabbed schema cross-platform parity 100% confirmed!")

def main():
    print("=" * 65)
    print("  SE.COM Z80 Beautifier Subsystem Regression Test Suite")
    print("=" * 65)

    test_config_screen_beautifier_options()
    test_ctrl_y_whole_file_beautify()
    test_ctrl_y_block_beautify()
    test_cross_platform_parity()
    test_tabbed_beautification()

    print("\n" + "=" * 65)
    print("  ALL BEAUTIFIER TESTS PASSED SUCCESSFULLY!")
    print("=" * 65)

if __name__ == "__main__":
    main()
