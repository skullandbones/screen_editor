#!/usr/bin/env python3
"""
isolate_step.py - Isolated Test Harness for SE.COM Conformity Regression Steps.

Allows running individual steps from the 75-step test suite in complete
isolation to quickly reproduce, verify, and resolve failures.

Usage:
    python3 tests/isolate_step.py 27
    python3 tests/isolate_step.py 66
    python3 tests/isolate_step.py 68
    python3 tests/isolate_step.py 70
    python3 tests/isolate_step.py 73
    python3 tests/isolate_step.py 74
    python3 tests/isolate_step.py 75
    python3 tests/isolate_step.py all
"""

import os
import re
import select
import subprocess
import sys
import time
import tty
USE_SEC = False
CMD_NAME = b"se"


def find_paths(use_sec=False):
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
    se_bin = os.path.join(
        repo_root, "SEC.COM" if use_sec else "SE.COM"
    )
    cpmrm_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm"
    )
    cpmcp_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp"
    )

    return (
        emu_bin, rom_file, img_file, se_bin,
        cpmcp_bin, cpmrm_bin, repo_root
    )


def read_until(master_fd, match_bytes, timeout=8.0):
    buf = b""
    t0 = time.time()
    targets = (
        match_bytes if isinstance(match_bytes, (list, tuple))
        else [match_bytes]
    )
    while time.time() - t0 < timeout:
        r, _, _ = select.select([master_fd], [], [], 0.05)
        if r:
            try:
                chunk = os.read(master_fd, 4096)
                if not chunk:
                    break
                buf += chunk
                for t in targets:
                    if t in buf:
                        return True, buf
            except (BlockingIOError, OSError):
                pass
    return False, buf


def drain_all(master_fd, quiet_time=0.15):
    buf = b""
    time.sleep(quiet_time)
    while True:
        r, _, _ = select.select([master_fd], [], [], 0.05)
        if not r:
            break
        try:
            chunk = os.read(master_fd, 4096)
            if not chunk:
                break
            buf += chunk
        except (BlockingIOError, OSError):
            break
    return buf


def setup_disk_files(
    img_file, se_bin, cpmcp_bin, cpmrm_bin, repo_root, use_sec=False
):
    target_cpm = "0:SEC.COM" if use_sec else "0:SE.COM"
    # Prepare BIG.TXT and BIG300.TXT
    big_tmp = "/tmp/BIG.TXT"
    with open(big_tmp, "w") as f:
        for i in range(1, 3073):
            f.write(f"Line {i:04d}\r\n")
    big300_tmp = "/tmp/BIG300.TXT"
    with open(big300_tmp, "w") as f:
        for i in range(1, 301):
            f.write(f"Line {i:04d} of 300\r\n")
    cfg_tmp = "/tmp/SE.CFG"
    with open(cfg_tmp, "w") as f:
        f.write("SCREEN=120x40\r\nRAMDRIVE=ON\r\n")

    ins1_tmp = "/tmp/INS1.TXT"
    with open(ins1_tmp, "wb") as f:
        f.write(b"INSERTED")
    ins2_tmp = "/tmp/INS2.TXT"
    with open(ins2_tmp, "wb") as f:
        f.write(b"FIRST LINE\r\nSECOND LINE")
    u1_tmp = "/tmp/U1FILE.TXT"
    with open(u1_tmp, "w") as f:
        f.write("Hello from User 1 area!\r\nSecond line of user 1 file.\r\n")

    if os.path.isfile(cpmrm_bin):
        for fname in [
            "0:BIG.TXT", "0:BIG300.TXT", "0:SE.CFG", "0:se.cfg",
            "0:SE.COM", "0:se.com", "0:SEC.COM", "0:sec.com",
            "0:INS1.TXT", "0:INS2.TXT",
            "0:BLKSGL.TXT", "0:SAV300.TXT", "0:BLK300.TXT",
            "0:LONGNAME.TXT", "0:TESTF.TXT", "1:U1FILE.TXT",
            "1:SAVEU1.TXT", "1:BLKU1.TXT", "0:CPM1.TXT",
            "0:LIN1.TXT", "0:CPM2.TXT"
        ]:
            subprocess.run(
                [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, fname],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
        subprocess.run(
            [cpmrm_bin, "-f", "wbw_hd1k_1", img_file, "0:30.TXT"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )

    two_txt = os.path.join(repo_root, "2.TXT")
    thirty_txt = os.path.join(repo_root, "30.TXT")
    if os.path.isfile(cpmcp_bin):
        if os.path.isfile(two_txt):
            subprocess.run(
                [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, two_txt, "0:2.TXT"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
        if os.path.isfile(thirty_txt):
            subprocess.run(
                [
                    cpmcp_bin, "-f", "wbw_hd1k_0", img_file,
                    thirty_txt, "0:30.TXT"
                ],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
        subprocess.run(
            [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, big_tmp, "0:BIG.TXT"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        subprocess.run(
            [
                cpmcp_bin, "-f", "wbw_hd1k_0", img_file,
                big300_tmp, "0:BIG300.TXT"
            ],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        subprocess.run(
            [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, cfg_tmp, "0:SE.CFG"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        if os.path.isfile(se_bin):
            subprocess.run(
                [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, target_cpm],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
        subprocess.run(
            [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, ins1_tmp, "0:INS1.TXT"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        subprocess.run(
            [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, ins2_tmp, "0:INS2.TXT"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        subprocess.run(
            [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, u1_tmp, "1:U1FILE.TXT"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        cpm1_tmp = "/tmp/CPM1.TXT"
        with open(cpm1_tmp, "wb") as f:
            for i in range(1, 301):
                f.write(
                    f"CPM1 Line {i:04d} content CRLF\r\n".encode("ascii")
                )
        lin1_tmp = "/tmp/LIN1.TXT"
        with open(lin1_tmp, "wb") as f:
            for i in range(1, 301):
                f.write(
                    f"LIN1 Line {i:04d} content LF\n".encode("ascii")
                )
        cpm2_tmp = "/tmp/CPM2.TXT"
        with open(cpm2_tmp, "wb") as f:
            for i in range(1, 301):
                f.write(
                    f"CPM2 Line {i:04d} content CRLF\r\n".encode("ascii")
                )
        for fn, tmp_p in [
            ("0:CPM1.TXT", cpm1_tmp),
            ("0:LIN1.TXT", lin1_tmp),
            ("0:CPM2.TXT", cpm2_tmp),
        ]:
            subprocess.run(
                [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, tmp_p, fn],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )


def boot_cpm(master):
    ok, out = read_until(master, b"Boot [H=Help]:", timeout=8.0)
    if not ok:
        return False, f"Failed to reach bootloader: {out}"
    time.sleep(0.3)
    os.write(master, b"c\r")
    ok, out = read_until(master, b"B>", timeout=8.0)
    if not ok:
        return False, f"Failed to boot into CP/M Drive B: {out}"
    time.sleep(0.3)
    os.write(master, b"c:\r")
    ok, out = read_until(master, b"C>", timeout=8.0)
    if not ok:
        return False, f"Failed to switch to Drive C: {out}"
    drain_all(master)
    return True, "Booted to Drive C>"


# =============================================================================
# Step Handlers
# =============================================================================

def run_step_27(master):
    """Step 27: Save Screen Pre-filling, Overwrite Check & Cancellation."""
    print("[*] Running Isolated Step 27: Save Screen & Overwrite...")
    time.sleep(0.5)
    drain_all(master)
    os.write(master, CMD_NAME + b" 2.TXT\r")
    ok, out = read_until(master, b"Line    1/2", timeout=35.0)
    if not ok:
        return False, f"Failed to open 2.TXT: {out[-200:] if out else ''}"
    drain_all(master)

    # Trigger Save Screen via Ctrl+S (\x13)
    time.sleep(0.3)
    os.write(master, b"\x13")
    ok, out = read_until(
        master, b"SAVE FILE (DIRECTORY - DRIVE C:)", timeout=6.0
    )
    if not ok:
        return False, f"Save screen title not found: {out}"
    ok, out = read_until(master, b"2.TXT", timeout=3.0)
    if not ok:
        return False, f"Pre-filled filename '2.TXT' not found: {out}"

    # Press Enter (\r) to save with existing filename -> overwrite warning
    time.sleep(0.3)
    drain_all(master)
    os.write(master, b"\r")
    ok, out_warn = read_until(
        master, b"[Y]es", timeout=6.0
    )
    out_warn += drain_all(master)
    if not ok or b"File already exists. Overwrite?" not in out_warn:
        return False, f"Overwrite warning prompt missing: {out_warn}"
    if b"[Y]es" not in out_warn or b"[N]o" not in out_warn:
        return False, f"Missing bracketed hotkeys [Y]es/[N]o: {out_warn}"

    # Cancel overwrite with 'n'
    time.sleep(0.2)
    drain_all(master)
    os.write(master, b"n")
    ok, out_back = read_until(master, b"C:2.TXT", timeout=4.0)
    if not ok:
        return False, f"Editor mode not restored after cancelling: {out_back}"
    if b"Save cancelled" in out_back:
        return False, f"Prohibited raw 'Save cancelled' printed: {out_back}"

    # Re-open Save Screen and overwrite with 'y'
    time.sleep(0.3)
    os.write(master, b"\x13")
    read_until(master, b"Enter filename to save", timeout=4.0)
    read_until(master, b"2.TXT", timeout=3.0)
    time.sleep(0.2)
    os.write(master, b"\r")
    read_until(master, b"Overwrite?", timeout=4.0)
    time.sleep(0.2)
    os.write(master, b"y")
    ok, out_saved = read_until(master, b"^K: Editor keys", timeout=8.0)
    if not ok or b"C:2.TXT" not in out_saved:
        return False, f"Editor mode not restored after save: {out_saved}"

    # Return to splash screen (ESC)
    time.sleep(0.5)
    drain_all(master)
    os.write(master, b"\x1b")
    ok, out_sp = read_until(master, b"for about", timeout=6.0)
    if not ok:
        return False, f"Failed to return to splash screen: {out_sp[-200:]}"

    # Clean exit to CP/M ('q')
    time.sleep(0.3)
    os.write(master, b"q")
    ok, out_cpm = read_until(master, b"C>", timeout=6.0)
    if not ok:
        return False, f"Failed to return to CP/M: {out_cpm[-200:]}"
    return True, "Step 27 PASSED"


def run_step_66(master):
    """Step 66: Block Insert File Feature Verification."""
    print("[*] Running Isolated Step 66: Block Insert File...")
    time.sleep(0.3)
    os.write(master, CMD_NAME + b"\r")
    ok, _ = read_until(master, b"Col 0", timeout=30.0)
    if not ok:
        return False, "Failed to launch SE.COM"
    drain_all(master)

    # Enter editor with 'e'
    os.write(master, b"e")
    ok, out = read_until(master, b"^K: Editor keys", timeout=6.0)
    if not ok:
        return False, f"Failed to enter editor: {out}"
    drain_all(master)

    # Subtest 1: Open Insert File screen with block, verify title/prompt & ESC
    os.write(master, b"Hello ")
    time.sleep(0.2)
    os.write(master, b"\x02")  # Ctrl+B
    time.sleep(0.2)
    os.write(master, b"\x0f")  # Ctrl+O -> Insert File screen
    ok, out_ui = read_until(
        master, b"INSERT FILE (DIRECTORY - DRIVE", timeout=6.0
    )
    if not ok:
        return False, f"Insert File title not found: {out_ui}"
    ok, out_ui2 = read_until(master, b"Enter filename to insert:", timeout=4.0)
    if not ok:
        return False, f"Insert prompt not found: {out_ui2}"

    # Cancel with ESC back to editor
    time.sleep(0.2)
    os.write(master, b"\x1b")
    ok, out_esc = read_until(master, b"Hello ", timeout=4.0)
    if not ok:
        return False, f"ESC did not restore editor: {out_esc}"
    drain_all(master)

    # Subtest 2: Non-existent file error handling
    os.write(master, b"\x0f")
    read_until(master, b"Enter filename to insert:", timeout=6.0)
    os.write(master, b"NOFILE.TXT\r")
    ok, out_fnf = read_until(master, b"File Not Found", timeout=6.0)
    if not ok and b"File not found" not in out_fnf:
        return False, f"File Not Found popup missing: {out_fnf}"
    time.sleep(0.1)
    os.write(master, b" ")  # Dismiss popup
    read_until(master, b"Enter filename to insert:", timeout=6.0)
    os.write(master, b"\x1b")  # ESC to editor
    read_until(master, b"Hello ", timeout=4.0)
    os.write(master, b"\x1b")  # Clear block
    drain_all(master)

    # Subtest 3: Insert single-line file at empty block (cursor)
    os.write(master, b"\x02")  # Ctrl+B
    time.sleep(0.2)
    os.write(master, b"\x0f")  # Ctrl+O
    read_until(master, b"Enter filename to insert:", timeout=6.0)
    os.write(master, b"INS1.TXT\r")
    ok, out_ins1 = read_until(master, b"Block: 8 chars", timeout=8.0)
    if not ok:
        return False, f"Block: 8 chars missing after insert: {out_ins1}"
    if b"INSERTED" not in out_ins1:
        return False, f"'INSERTED' content not found: {out_ins1}"
    if b"(Untitled)" not in out_ins1:
        return False, f"Document filename corrupted: {out_ins1}"

    # Subtest 4: Replace single-line block with multi-line file
    os.write(master, b" END")
    time.sleep(0.2)
    # Move to start of INSERTED (col 6)
    os.write(master, b"\x01")  # Ctrl+A (Home)
    time.sleep(0.2)
    for _ in range(6):
        os.write(master, b"\x1b[C")
        time.sleep(0.02)
    # Start block at col 6, move 8 chars right to select "INSERTED"
    os.write(master, b"\x02")
    time.sleep(0.1)
    for _ in range(8):
        os.write(master, b"\x1b[C")
        time.sleep(0.02)
    # Insert INS2.TXT over active block
    os.write(master, b"\x0f")
    read_until(master, b"Enter filename to insert:", timeout=6.0)
    os.write(master, b"INS2.TXT\r")
    ok, out_ins2 = read_until(master, b"Block: 2 lines", timeout=8.0)
    if not ok:
        return False, f"Block: 2 lines not found: {out_ins2}"
    if b"FIRST LINE" not in out_ins2 or b"SECOND LINE" not in out_ins2:
        return False, f"Multi-line content missing: {out_ins2}"

    # Clean exit to CP/M
    time.sleep(0.3)
    os.write(master, b"\x1b")  # Unlock block
    read_until(master, b"^K: Editor keys", timeout=6.0)
    time.sleep(0.3)
    drain_all(master)
    os.write(master, b"\x11")  # Ctrl+Q
    ok, out_sc = read_until(master, b"Save changes?", timeout=6.0)
    if not ok:
        return False, f"Save changes prompt missing: {out_sc}"
    time.sleep(0.2)
    os.write(master, b"n")  # Don't save
    ok, out_cpm = read_until(master, b"C>", timeout=6.0)
    if not ok:
        return False, f"Failed to return to CP/M: {out_cpm}"
    return True, "Step 66 PASSED"


def run_step_68(master):
    """Step 68: Save Progress Indicator Verification."""
    print("[*] Running Isolated Step 68: Save Progress Indicator...")
    time.sleep(0.3)
    os.write(master, CMD_NAME + b" BIG300.TXT\r")
    ok, out_load = read_until(master, b"1/300", timeout=35.0)
    if not ok:
        return False, f"Failed to load BIG300.TXT: {out_load[-200:]}"
    drain_all(master)

    # Subtest 1: File Save progress on 300-line file
    time.sleep(0.2)
    os.write(master, b"\x13")  # Ctrl+S
    read_until(master, b"Enter filename to save:", timeout=6.0)
    read_until(master, b"\x1b[?25h", timeout=4.0)
    time.sleep(0.2)
    os.write(master, b"\x08" * 20 + b"SAV300.TXT\r")
    ok, out_save = read_until(master, b"^K: Editor keys", timeout=35.0)
    out_save += drain_all(master)
    if not ok:
        return False, f"Save did not complete: {out_save[-200:]}"
    if b"Saving File" not in out_save and b"Saving..." not in out_save:
        return False, f"Progress title 'Saving File' missing: {out_save[:400]}"
    if b"SAV300.TXT" not in out_save:
        return False, f"Target filename 'SAV300.TXT' missing: {out_save[:400]}"

    found_ticks = [
        t for t in [b"Line   100", b"Line   200", b"Line   300"]
        if t in out_save
    ]
    if len(found_ticks) < 3:
        return False, f"Missing save progress ticks: {found_ticks}"

    # Clean exit to CP/M
    time.sleep(0.3)
    os.write(master, b"\x11")  # Ctrl+Q
    ok, out_cpm = read_until(master, b"C>", timeout=6.0)
    if not ok:
        return False, f"Failed to return to CP/M: {out_cpm}"
    return True, f"Step 68 PASSED (Ticks: {[t.decode() for t in found_ticks]})"


def run_step_70(master):
    """Step 70: Directory Listing Filter on Open, Save, Insert, Block Save."""
    print("[*] Running Isolated Step 70: Directory Listing Filter...")
    time.sleep(0.3)
    os.write(master, CMD_NAME + b"\r")
    ok, _ = read_until(master, b"Free: ", timeout=35.0)
    if not ok:
        return False, "Could not reach splash screen"
    drain_all(master)

    # Subtest 1: Open File Screen Filter
    time.sleep(0.2)
    os.write(master, b"o")
    ok, out_open = read_until(
        master, b"Enter filename to open:", timeout=8.0
    )
    if not ok or b"OPEN FILE (DIRECTORY - DRIVE C:)" not in out_open:
        return False, f"Initial Open File header mismatch: {out_open}"
    if b"SE.COM" not in out_open:
        return False, "SE.COM not found in unfiltered directory listing"

    # Filter: '*.TXT'
    time.sleep(0.2)
    os.write(master, b"*.TXT\r")
    ok, out_filt = read_until(
        master, b"Enter filename to open:", timeout=8.0
    )
    if not ok or b"OPEN FILE (DIRECTORY - DRIVE C: [*.TXT])" not in out_filt:
        return False, f"Header did not update to [*.TXT]: {out_filt}"
    new_txt = out_filt[out_filt.rfind(b"[*.TXT]"):]
    if b"SE.COM" in new_txt:
        return False, "SE.COM unexpectedly found in *.TXT filtered listing"

    # Reset filter: '*.*'
    time.sleep(0.2)
    os.write(master, b"\x08" * 20 + b"*.*\r")
    ok, out_reset = read_until(
        master, b"Enter filename to open:", timeout=8.0
    )
    last_reset = out_reset[out_reset.rfind(b"DIRECTORY - DRIVE C:"):]
    hdr_reset = last_reset.split(b"\r\n")[0]
    if b": [" in hdr_reset:
        return False, f"Header did not reset after *.*: {hdr_reset}"

    # ESC to splash
    time.sleep(0.2)
    os.write(master, b"\x1b")
    read_until(master, b"Active Screen :", timeout=6.0)

    # Subtest 2: Save File Screen Filter & Filename Preservation
    time.sleep(0.2)
    os.write(master, b"e")
    read_until(master, b"Line    1/1", timeout=6.0)
    time.sleep(0.2)
    os.write(master, b"Hello Filter Test")

    # Save as TESTF.TXT
    time.sleep(0.3)
    os.write(master, b"\x13")
    read_until(master, b"Enter filename to save:", timeout=8.0)
    time.sleep(0.2)
    os.write(master, b"TESTF.TXT\r")
    ok, _ = read_until(master, b"^K: Editor keys", timeout=8.0)
    if not ok:
        return False, "Failed to return to editor after saving TESTF.TXT"
    time.sleep(0.3)
    drain_all(master)

    # Modify and check Ctrl+S prefill
    os.write(master, b" more")
    time.sleep(0.3)
    os.write(master, b"\x13")
    ok1, out1 = read_until(master, b"Enter filename to save:", timeout=8.0)
    ok2, out2 = read_until(master, b"TESTF.TXT", timeout=6.0)
    out_save2 = out1 + out2
    if b"TESTF.TXT" not in out_save2:
        return False, f"Save prompt did not prefill TESTF.TXT: {out_save2}"

    # Filter on Save screen: '*.TXT'
    time.sleep(0.3)
    os.write(master, b"\x08" * 20 + b"*.TXT\r")
    ok, out_sf = read_until(
        master, b"SAVE FILE (DIRECTORY - DRIVE C: [*.TXT])", timeout=8.0
    )
    if not ok:
        return False, f"Save header did not update to [*.TXT]: {out_sf}"

    # Save and clean exit
    time.sleep(0.2)
    os.write(master, b"\x08" * 20 + b"TESTF.TXT\r")
    _, out_ow = read_until(master, b"Overwrite?", timeout=6.0)
    if b"Overwrite?" in out_ow:
        time.sleep(0.1)
        os.write(master, b"y")
    ok, _ = read_until(master, b"^K: Editor keys", timeout=8.0)
    if not ok:
        return False, "Failed to return to editor after overwrite TESTF.TXT"

    time.sleep(0.2)
    os.write(master, b"\x11")  # Ctrl+Q
    ok, out_cpm = read_until(master, b"C>", timeout=6.0)
    if not ok:
        return False, f"Exit to CP/M failed: {out_cpm}"
    return True, "Step 70 PASSED"


def run_step_73(master):
    """Step 73: In-line Filename Edit Box Navigation and Editing."""
    print("[*] Running Isolated Step 73: Filename Edit Box In-line Editing...")
    time.sleep(0.3)
    os.write(master, CMD_NAME + b" 30.TXT\r")
    ok, out_ed = read_until(master, b"1/30", timeout=30.0)
    if not ok:
        return False, f"Failed to load 30.TXT into editor: {out_ed}"
    drain_all(master)

    # Subtest 1: Save File Dialog In-Line Editing
    time.sleep(0.3)
    os.write(master, b"\x13")  # Ctrl+S
    ok, out_save = read_until(
        master, b"Enter filename to save:", timeout=8.0
    )
    read_until(master, b"\x1b[?25h", timeout=4.0)
    if not ok:
        return False, f"Save prompt not found: {out_save}"

    # Home (ESC [ H) -> Delete (ESC [ 3 ~) -> 'D' -> Right Arrow x2 -> Left x3
    time.sleep(0.1)
    os.write(master, b"\x1b[H")
    time.sleep(0.1)
    os.write(master, b"\x1b[3~")
    time.sleep(0.1)
    os.write(master, b"D")
    time.sleep(0.1)
    os.write(master, b"\x1b[C\x1b[C")
    time.sleep(0.1)
    os.write(master, b"\x1b[D\x1b[D\x1b[D")
    time.sleep(0.1)
    os.write(master, b"\x1b[F")  # End key
    time.sleep(0.1)
    os.write(master, b"\x08")    # Backspace
    time.sleep(0.1)
    os.write(master, b"T")       # Restore 'T'
    time.sleep(0.1)
    os.write(master, b"\r")      # Save to D0:30.TXT
    ok, out_saved = read_until(master, b"^K: Editor keys", timeout=25.0)
    if not ok:
        return False, f"Save to D0:30.TXT failed: {out_saved}"

    # Subtest 2: Open File Dialog In-Line Editing
    time.sleep(0.3)
    os.write(master, b"\x0f")  # Ctrl+O
    ok, out_open = read_until(
        master, b"Enter filename to open:", timeout=8.0
    )
    if not ok:
        return False, f"Open prompt not found: {out_open}"

    # Cancel Open with ESC
    time.sleep(0.2)
    os.write(master, b"\x1b")
    read_until(master, b"^K: Editor keys", timeout=6.0)

    # Clean exit to CP/M
    time.sleep(0.2)
    os.write(master, b"\x11")  # Ctrl+Q
    ok, out_cpm = read_until(master, b"C>", timeout=6.0)
    if not ok:
        return False, f"Exit to CP/M failed: {out_cpm}"
    return True, "Step 73 PASSED"


def run_step_74(master):
    """Step 74: Splash RAM Drive Status and Unavailable RAM Drive Guard."""
    print("[*] Running Isolated Step 74: Splash RAM Drive Status & Guard...")
    time.sleep(0.3)
    os.write(master, b"era se.cfg\r")
    read_until(master, b"C>", timeout=10.0)

    time.sleep(0.3)
    os.write(master, CMD_NAME + b"\r")
    ok, out_sp = read_until(master, b"RAM Drive (", timeout=35.0)
    ok2, out_sp_free = read_until(master, b"Free: ", timeout=10.0)
    out_sp += out_sp_free
    if not ok or b"RAM Drive (A:): [Preserved (Active)]" not in out_sp:
        return False, f"RAM Drive (A:) Preserved missing: {out_sp}"
    if b"Max Lines     : [16,384 lines]" not in out_sp:
        return False, f"Max Lines missing: {out_sp}"

    # Enter config with 'c'
    time.sleep(0.3)
    os.write(master, b"c")
    ok, out_cfg = read_until(master, b"[ESC]=Exit", timeout=10.0)
    if b"Preserve (RAM Drive Active, 128KB)]" not in out_cfg:
        return False, f"Config Preserve missing: {out_cfg}"

    # Cycle to Hibernate ('2')
    time.sleep(0.3)
    os.write(master, b"2")
    ok, out_hib = read_until(
        master, b"Hibernate (Backup/Restore, 384KB)]", timeout=10.0
    )
    if not ok:
        return False, f"Toggle to Hibernate failed: {out_hib}"

    # Cycle to Overwrite ('2')
    time.sleep(0.3)
    os.write(master, b"2")
    ok, out_ovw = read_until(
        master, b"Overwrite (Sacrifice Drive, 384KB)]", timeout=10.0
    )
    if not ok:
        return False, f"Toggle to Overwrite failed: {out_ovw}"

    # Save config with 's' and return to splash with 'q'
    time.sleep(0.3)
    os.write(master, b"s")
    read_until(master, b"Saved to local drive", timeout=10.0)
    time.sleep(0.3)
    os.write(master, b"q")
    ok, out_sp2 = read_until(master, b"SE - Screen Editor", timeout=15.0)
    ok2, out_free = read_until(master, b"Free: ", timeout=10.0)
    out_sp2 += out_free
    if not ok or b"RAM Drive (A:): [Overwritten (Max RAM)]" not in out_sp2:
        return False, f"Splash did not update to Overwritten: {out_sp2}"

    # Clean exit to CP/M
    time.sleep(0.3)
    os.write(master, b"q")
    ok, out_cpm = read_until(master, b"C>", timeout=6.0)
    if not ok:
        return False, f"Exit to CP/M failed: {out_cpm}"
    return True, "Step 74 PASSED"


def run_step_65(master):
    """Step 65: Verifying About Screen ('a' key on splash screen)..."""
    time.sleep(0.5)
    os.write(master, CMD_NAME + b"\r")
    ok, out_sp = read_until(master, b"Free:", timeout=30.0)
    time.sleep(0.2)
    out_sp += drain_all(master)
    if not ok or b"for about" not in out_sp:
        return False, f"'for about' not on splash screen: {out_sp}"
    if b"version" in out_sp or b"Dean Jenkins" in out_sp:
        return False, f"Splash screen unexpectedly contains version/author"

    os.write(master, b"a")
    ok, out_about = read_until(
        master, b"Press any key to continue", timeout=6.0
    )
    time.sleep(0.2)
    out_about += drain_all(master)
    if not ok:
        return False, f"Return prompt not found on About screen: {out_about}"
    if b"SE - Screen Editor" not in out_about:
        return False, f"'SE - Screen Editor' title not found: {out_about}"
    if b"version 1.1.0" not in out_about:

        return False, f"Version details not found on About screen: {out_about}"
    if b"by Dean Jenkins" not in out_about:
        return False, f"Author attribution not found on About: {out_about}"
    if b"Google Antigravity 2.19.1" not in out_about:
        return False, f"Antigravity 2.19.1 not found on About: {out_about}"
    if b"Gemini FLASH 3.8 high" not in out_about:
        return False, f"Gemini FLASH 3.8 high not found on About: {out_about}"
    if b"MIT License" not in out_about:
        return False, f"MIT License not found on About screen: {out_about}"

    os.write(master, b"\r")
    ok, out_back = read_until(master, b"for about", timeout=6.0)
    time.sleep(0.2)
    out_back += drain_all(master)
    if not ok:
        return False, f"Return to splash screen failed: {out_back}"

    os.write(master, b"q")
    ok, out_cpm = read_until(master, b"C>", timeout=6.0)
    if not ok:
        return False, f"Exit to CP/M prompt failed: {out_cpm}"
    return True, "Step 65 PASSED"


def run_step_75(master):
    """Step 75: Regression Test for Bug 2.36 (Open Modal & Status Format)."""
    # 1. Launch SE with CPM1.TXT (CRLF format)
    time.sleep(0.3)
    os.write(master, CMD_NAME + b" cpm1.txt\r")
    ok, out1 = read_until(master, b"CPM1 Line 0038", timeout=30.0)
    out1 += drain_all(master, 0.4)
    if not ok:
        return False, f"CPM1.TXT buffer render timed out: {out1[-300:]}"
    if (b"CP/M  | " not in out1 or
            b"Line    1/300 " not in out1 or
            b"C:CPM1.TXT" not in out1):
        return False, f"Initial CPM1.TXT load state invalid: {out1[-300:]}"

    # 2. Open LIN1.TXT (Linux LF-only) via Ctrl+O
    time.sleep(0.5)
    os.write(master, b"\x0f")        # Ctrl+O
    ok, out_open1 = read_until(
        master, b"Enter filename to open:", timeout=10.0
    )
    if not ok:
        return False, f"Failed to enter Open File screen: {out_open1}"

    time.sleep(0.5)
    os.write(master, b"LIN1.TXT\r")
    ok, out2 = read_until(master, b"LIN1 Line 0038", timeout=30.0)
    out2 += drain_all(master, 0.4)
    if not ok:
        return False, f"LIN1.TXT buffer render timed out: {out2[-300:]}"
    if (b"File: C:LIN1.TXT" not in out2 or
            b"Opening File" not in out2):
        return False, f"Modal popup filename tracking error for LIN1: {out2}"
    if (b"|       |" not in out2 or
            b"Line    1/----" not in out2):
        return False, f"Loading status bar not blanked for LIN1: {out2}"
    if (b"Linux | " not in out2 or
            b"Line    1/300 " not in out2 or
            b"C:LIN1.TXT" not in out2):
        return False, f"Post-load status bar incorrect for LIN1: {out2[-300:]}"

    # 3. Open CPM2.TXT (CP/M CRLF) via Ctrl+O
    time.sleep(0.5)
    os.write(master, b"\x0f")        # Ctrl+O
    ok, out_open2 = read_until(
        master, b"Enter filename to open:", timeout=10.0
    )
    if not ok:
        return False, f"Failed to enter Open File screen: {out_open2}"

    time.sleep(0.5)
    os.write(master, b"CPM2.TXT\r")
    ok, out3 = read_until(master, b"CPM2 Line 0038", timeout=30.0)
    out3 += drain_all(master, 0.4)
    if not ok:
        return False, f"CPM2.TXT buffer render timed out: {out3[-300:]}"
    if (b"File: C:CPM2.TXT" not in out3 or
            b"Opening File" not in out3):
        return False, f"Modal popup filename tracking error for CPM2: {out3}"
    if (b"|       |" not in out3 or
            b"Line    1/----" not in out3):
        return False, f"Loading status bar not blanked for CPM2: {out3}"
    if (b"CP/M  | " not in out3 or
            b"Line    1/300 " not in out3 or
            b"C:CPM2.TXT" not in out3):
        return False, f"Post-load status bar not CP/M for CPM2: {out3[-300:]}"

    # 4. Clean exit to CP/M
    time.sleep(0.5)
    os.write(master, b"\x11")        # Ctrl+Q
    time.sleep(0.3)
    os.write(master, b"q\r")
    ok, out_exit = read_until(master, b"C>", timeout=8.0)
    if b"Save changes?" in out_exit:
        os.write(master, b"N")
        ok, out_exit2 = read_until(master, b"C>", timeout=8.0)
        ok = ok and (b"C>" in out_exit2)
    if not ok:
        return False, f"Clean exit to CP/M failed: {out_exit}"

    return True, "Step 75 PASSED"


# =============================================================================
# Dispatcher
# =============================================================================

STEP_HANDLERS = {
    27: run_step_27,
    65: run_step_65,
    66: run_step_66,
    68: run_step_68,
    70: run_step_70,
    73: run_step_73,
    74: run_step_74,
    75: run_step_75,
}


def run_isolated(step_num, use_sec=False):
    (
        emu_bin, rom_file, img_file, se_bin,
        cpmcp, cpmrm, repo_root
    ) = find_paths(use_sec=use_sec)
    target_name = "SEC.COM" if use_sec else "SE.COM"
    for p, name in [
        (emu_bin, "RC2014 emulator"),
        (rom_file, "ROM file"),
        (img_file, "Disk image"),
        (se_bin, target_name)
    ]:
        if not os.path.isfile(p):
            print(f"[-] Required file missing: {name} ({p})")
            return False

    setup_disk_files(img_file, se_bin, cpmcp, cpmrm, repo_root, use_sec=use_sec)

    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )
    os.close(slave)

    try:
        ok, msg = boot_cpm(master)
        if not ok:
            print(f"[-] Boot failed: {msg}")
            return False

        handler = STEP_HANDLERS[step_num]
        t0 = time.time()
        success, message = handler(master)
        elapsed = time.time() - t0
        if success:
            print(f"[+] STEP {step_num} PASSED in {elapsed:.2f}s: {message}")
            return True
        else:
            print(f"[-] STEP {step_num} FAILED in {elapsed:.2f}s: {message}")
            return False
    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            proc.kill()
        try:
            os.close(master)
        except OSError:
            pass


def main():
    global USE_SEC, CMD_NAME
    USE_SEC = "--sec" in sys.argv
    CMD_NAME = b"sec" if USE_SEC else b"se"
    args = [a for a in sys.argv[1:] if a != "--sec"]
    if len(args) < 1:
        steps_to_run = [27, 66, 68, 70, 73, 74, 75]
    elif args[0].lower() == "all":
        steps_to_run = sorted(STEP_HANDLERS.keys())
    else:
        try:
            steps_to_run = [int(arg) for arg in args]
        except ValueError:
            print(
                "Usage: python3 tests/isolate_step.py [--sec] "
                "[step_number ... | all]"
            )
            return 1

    results = {}
    for step in steps_to_run:
        if step not in STEP_HANDLERS:
            print(f"[-] Unknown step {step}. Available: {list(STEP_HANDLERS)}")
            results[step] = False
            continue
        print(f"\n{'=' * 60}\n  RUNNING ISOLATED STEP {step}\n{'=' * 60}")
        res = run_isolated(step, use_sec=USE_SEC)
        results[step] = res

    print("\n" + "=" * 60)
    print("  ISOLATION TEST SUMMARY")
    print("=" * 60)
    all_ok = True
    for step, res in results.items():
        status = "PASS" if res else "FAIL"
        print(f"  Step {step:02d}: [{status}]")
        if not res:
            all_ok = False
    print("=" * 60 + "\n")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
