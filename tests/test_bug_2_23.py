#!/usr/bin/env python3
"""
test_bug_2_23.py - Verification of Bug 2.23: FAT Plugin Dialogs Compliance

Validates:
1. Dynamic Centering:
   - 80x24:
     - About dialog (50x15): TopRow 5, LeftCol 16 (\\x1b[5;16H).
     - Config dialog (50x11): TopRow 7, LeftCol 16 (\\x1b[7;16H).
   - 120x40:
     - About dialog (50x15): TopRow 13, LeftCol 36 (\\x1b[13;36H).
     - Config dialog (50x11): TopRow 15, LeftCol 36 (\\x1b[15;36H).
2. Elimination of vt_clear_screen():
   - No \\x1b[2J emitted when invoking or exiting About or Config dialogs.
3. Decision Option Delimiters:
   - Prohibit slash delimiters; options formatted as:
     'Select [0-7] to change    [ESC]=Cancel'.
4. ESC Cancellation Exclusivity:
   - 'q' / 'Q' is prohibited from dismissing the configuration dialog.
   - ESC (0x1b) cleanly dismisses the dialog back to the parent screen.
"""

import os
import pty
import select
import struct
import subprocess
import sys
import time
import tty


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
    fatfs_prl = os.path.join(repo_root, "plugins", "FATFS.PRL")
    cpmcp_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp"
    )
    cpmrm_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm"
    )

    return (
        repo_root,
        emu_bin,
        rom_file,
        img_file,
        se_bin,
        fatfs_prl,
        cpmcp_bin,
        cpmrm_bin,
    )


def read_until(master_fd, match_bytes, timeout=12.0):
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
        time.sleep(0.01)
    return False, buf


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


def ensure_fat_test_image(img_file):
    target_size = 1837056 * 512
    if os.path.getsize(img_file) < target_size:
        with open(img_file, "a") as f:
            f.truncate(target_size)
    part_offset = 1050624 * 512
    slices_content = (
        b"Slice 0: CP/M 2.2 System\r\n"
        b"Slice 1: Z-System / ZSDOS\r\n"
        b"Slice 2: NZ-COM Operating Environment\r\n"
        b"Slice 3: CP/M Plus (CP/M 3.0)\r\n"
    )
    vbr = bytearray(512)
    vbr[0:3] = b"\xeb\x3c\x90"
    vbr[3:11] = b"MSDOS5.0"
    struct.pack_into("<H", vbr, 11, 512)
    vbr[13] = 8
    struct.pack_into("<H", vbr, 14, 16)
    vbr[16] = 2
    struct.pack_into("<H", vbr, 17, 512)
    struct.pack_into("<H", vbr, 19, 0)
    vbr[21] = 0xF8
    struct.pack_into("<H", vbr, 22, 192)
    struct.pack_into("<H", vbr, 24, 63)
    struct.pack_into("<H", vbr, 26, 255)
    struct.pack_into("<I", vbr, 28, 1050624)
    struct.pack_into("<I", vbr, 32, 393216)
    vbr[36] = 0x80
    vbr[38] = 0x29
    struct.pack_into("<I", vbr, 39, 0x12345678)
    vbr[43:54] = b"NO NAME    "
    vbr[54:62] = b"FAT16   "
    vbr[510:512] = b"\x55\xaa"

    with open(img_file, "r+b") as f:
        f.seek(part_offset)
        f.write(vbr)
        fat_init = struct.pack("<HH", 0xFFF8, 0xFFFF)
        f.seek(part_offset + 16 * 512)
        f.write(fat_init)
        f.seek(part_offset + (16 + 192) * 512)
        f.write(fat_init)
        fat_entry_2 = struct.pack("<H", 0xFFFF)
        f.seek(part_offset + 16 * 512 + 4)
        f.write(fat_entry_2)
        f.seek(part_offset + (16 + 192) * 512 + 4)
        f.write(fat_entry_2)
        dirent = struct.pack(
            "<11sBBBHHHHHHHI",
            b"SLICES  TXT", 0x20, 0, 0, 0, 0, 0, 0, 0, 0, 2,
            len(slices_content),
        )
        f.seek(part_offset + 400 * 512)
        f.write(dirent)
        f.seek(part_offset + 432 * 512)
        f.write(slices_content)


def test_bug_2_23():
    print("[*] Starting Bug 2.23 FAT Plugin Dialogs Compliance Test...")
    paths = find_paths()
    (
        repo_root,
        emu_bin,
        rom_file,
        img_file,
        se_bin,
        fatfs_prl,
        cpmcp_bin,
        cpmrm_bin,
    ) = paths

    for p, name in [
        (emu_bin, "RC2014 emulator"),
        (rom_file, "ROM file"),
        (img_file, "Disk image"),
        (se_bin, "SE.COM"),
        (fatfs_prl, "FATFS.PRL"),
        (cpmcp_bin, "cpmcp"),
        (cpmrm_bin, "cpmrm"),
    ]:
        assert os.path.isfile(p), f"Required file not found: {name} ({p})"

    ensure_fat_test_image(img_file)

    # Inject latest SE.COM and FATFS.PRL into test image
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.COM", "0:se.com"],
        check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, "0:SE.COM"],
        check=True,
    )
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:FATFS.PRL", "0:fatfs.prl"],
        check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, fatfs_prl, "0:FATFS.PRL"],
        check=True,
    )

    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )
    os.close(slave)

    try:
        # Boot RomWBW CP/M
        ok, out = read_until(master, b"Boot [H=Help]:", timeout=8.0)
        assert ok, f"Failed to reach bootloader prompt: {out}"
        time.sleep(0.5)
        os.write(master, b"c\r")
        ok, out = read_until(master, b"B>", timeout=8.0)
        assert ok, f"Failed to boot into CP/M: {out}"
        time.sleep(0.5)
        os.write(master, b"c:\r")
        ok, out = read_until(master, b"C>", timeout=8.0)
        assert ok, f"Failed to switch to Drive C: {out}"

        # Launch SE.COM
        time.sleep(0.5)
        os.write(master, b"se\r")
        ok, out = read_until(master, b"SE - Screen Editor", timeout=25.0)
        assert ok, f"Failed to display splash screen: {out}"
        print("[+] Splash screen loaded.")
        drain_all(master)

        # Ensure 80x24 Classic Mode ('2')
        time.sleep(0.3)
        os.write(master, b"2")
        ok, out = read_until(master, b"80x24", timeout=6.0)
        assert ok, f"Failed to select 80x24 mode: {out}"
        drain_all(master)

        # Enter Plugin Manager ('p')
        time.sleep(0.5)
        os.write(master, b"p")
        ok, out = read_until(master, b"SE - Plugin Manager", timeout=8.0)
        assert ok, f"Failed to enter Plugin Manager: {out}"
        read_until(master, b"Plugin", timeout=5.0)
        time.sleep(0.3)

        # Load FATFS.PRL into Slot 3
        os.write(master, b"3")
        time.sleep(0.2)
        os.write(master, b"\r")
        read_until(master, b"Load Plugin (.PRL/.OVL):", timeout=6.0)
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"FATFS.PRL\r")
        ok, out = read_until(master, b"FAR (32KB)", timeout=15.0)
        assert ok, f"Failed to load FATFS.PRL into Slot 3: {out}"
        print("[+] FATFS.PRL loaded into Slot 3.")
        read_until(master, b"[Down]=Select", timeout=5.0)
        drain_all(master)

        # ---------------------------------------------------------------------
        # Case 1: 80x24 Mode Tests
        # ---------------------------------------------------------------------
        print("[*] Case 1: Testing 80x24 Mode Dialog Compliance...")

        # Subtest 1.1: 80x24 About Dialog ('a')
        print("    [*] Subtest 1.1: FAT About Dialog in 80x24...")
        time.sleep(0.3)
        os.write(master, b"a")
        ok, out_abt = read_until(
            master, b"Press any key to continue", timeout=6.0
        )
        assert ok, f"FAT About dialog missing prompt: {out_abt}"

        # Assert dynamic centering coordinates for 80x24: TopRow 5, LeftCol 16
        assert b"\x1b[5;16H" in out_abt, (
            f"About dialog not centered at (5, 16) in 80x24: {out_abt}"
        )
        # Assert no full screen clear sequence (\x1b[2J) emitted by plugin
        assert b"\x1b[2J" not in out_abt, (
            f"Spurious screen clear (\\x1b[2J) in About dialog: {out_abt}"
        )
        print("    [+] 80x24 About dialog centered at (5, 16) without "
              "screen clear.")

        # Dismiss About with Space
        time.sleep(0.2)
        drain_all(master)
        os.write(master, b" ")
        ok, out_pm = read_until(master, b"SE - Plugin Manager", timeout=6.0)
        assert ok, f"Failed to return cleanly to Plugin Manager: {out_pm}"
        read_until(master, b"[Down]=Select", timeout=5.0)
        drain_all(master)

        # Subtest 1.2: 80x24 Config Dialog ('c')
        print("    [*] Subtest 1.2: FAT Config Dialog in 80x24...")
        time.sleep(0.3)
        os.write(master, b"c")
        ok, out_cfg = read_until(
            master, b"[ESC]=Cancel", timeout=6.0
        )
        assert ok, f"FAT Config dialog not displayed: {out_cfg}"

        # Assert dynamic centering coordinates for 80x24: TopRow 7, LeftCol 16
        assert b"\x1b[7;16H" in out_cfg, (
            f"Config dialog not centered at (7, 16) in 80x24: {out_cfg}"
        )
        assert b"\x1b[2J" not in out_cfg, (
            f"Spurious screen clear emitted by Config dialog: {out_cfg}"
        )

        # Assert decision options formatting: space-separated, [ESC]=Cancel
        assert b"Select [0-7] to change    [ESC]=Cancel" in out_cfg, (
            f"Config prompt options not formatted properly: {out_cfg}"
        )
        assert b"[ESC]/[Q]" not in out_cfg, (
            f"Slash delimiter unexpectedly present in config prompt: {out_cfg}"
        )
        print("    [+] 80x24 Config dialog centered at (7, 16) without "
              "slash delimiters.")

        # Subtest 1.3: Verify 'q' and other keys do NOT dismiss config dialog
        print("    [*] Subtest 1.3: Verifying 'q' cancellation prohibition...")
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"q")
        ok_dismiss, _ = read_until(master, b"SE - Plugin Manager", timeout=0.5)
        assert not ok_dismiss, "Config dialog erroneously dismissed on 'q'!"
        os.write(master, b"Q")
        ok_dismiss, _ = read_until(master, b"SE - Plugin Manager", timeout=0.5)
        assert not ok_dismiss, "Config dialog erroneously dismissed on 'Q'!"
        print("    [+] Verified 'q' and 'Q' cannot cancel or dismiss Config "
              "dialog.")

        # Subtest 1.4: Dismiss config dialog via ESC (0x1b)
        print("    [*] Subtest 1.4: Dismissing Config dialog via ESC...")
        time.sleep(0.2)
        os.write(master, b"\x1b")
        ok, out_pm = read_until(master, b"SE - Plugin Manager", timeout=6.0)
        assert ok, f"Config dialog failed to dismiss on ESC: {out_pm}"
        read_until(master, b"[Down]=Select", timeout=5.0)
        drain_all(master)
        print("    [+] Config dialog dismissed cleanly via ESC.")

        # Return to Splash screen
        time.sleep(0.3)
        os.write(master, b"q")
        ok, _ = read_until(master, b"for about", timeout=6.0)
        assert ok, "Failed to return to splash screen"
        drain_all(master)

        # ---------------------------------------------------------------------
        # Case 2: 120x40 Mode Tests
        # ---------------------------------------------------------------------
        print("[*] Case 2: Testing 120x40 Mode Dialog Compliance...")
        time.sleep(0.3)
        os.write(master, b"1")  # Switch to 120x40 mode
        ok, out = read_until(master, b"120x40", timeout=6.0)
        assert ok, f"Failed to switch to 120x40 mode: {out}"
        time.sleep(0.2)
        drain_all(master)

        # Enter Plugin Manager in 120x40 ('p')
        os.write(master, b"p")
        ok, _ = read_until(master, b"SE - Plugin Manager", timeout=6.0)
        assert ok, "Failed to enter Plugin Manager in 120x40"
        read_until(master, b"[Down]=Select", timeout=5.0)
        drain_all(master)

        # Select Slot 3 (FATFS.PRL)
        print("    [*] Selecting Slot 3 (FATFS.PRL)...")
        time.sleep(0.3)
        selected = False
        for _ in range(8):
            os.write(master, b"j")
            ok, _ = read_until(master, b">[3]", timeout=0.6)
            if ok:
                selected = True
                break
        assert selected, "Failed to select Slot 3 in 120x40 Plugin Manager"
        drain_all(master)

        # Subtest 2.1: 120x40 About Dialog ('a')
        print("    [*] Subtest 2.1: FAT About Dialog in 120x40...")
        time.sleep(0.3)
        os.write(master, b"a")
        ok, out_abt120 = read_until(
            master, b"Press any key to continue", timeout=6.0
        )
        assert ok, f"FAT About dialog missing prompt in 120x40: {out_abt120}"

        # Assert dynamic centering coordinates for 120x40: TopRow 13, LeftCol 36
        assert b"\x1b[13;36H" in out_abt120, (
            f"About dialog not centered at (13, 36) in 120x40: {out_abt120}"
        )
        assert b"\x1b[2J" not in out_abt120, (
            f"Spurious screen clear emitted by 120x40 About: {out_abt120}"
        )
        print("    [+] 120x40 About dialog centered at (13, 36) without "
              "screen clear.")

        # Dismiss About with Space
        time.sleep(0.2)
        drain_all(master)
        os.write(master, b" ")
        ok, _ = read_until(master, b"SE - Plugin Manager", timeout=6.0)
        assert ok, "Failed to return to Plugin Manager from 120x40 About"
        read_until(master, b"[Down]=Select", timeout=5.0)
        drain_all(master)

        # Subtest 2.2: 120x40 Config Dialog ('c')
        print("    [*] Subtest 2.2: FAT Config Dialog in 120x40...")
        time.sleep(0.3)
        os.write(master, b"c")
        ok, out_cfg120 = read_until(
            master, b"[ESC]=Cancel", timeout=6.0
        )
        assert ok, f"FAT Config dialog not displayed in 120x40: {out_cfg120}"

        # Assert dynamic centering coordinates for 120x40: TopRow 15, LeftCol 36
        assert b"\x1b[15;36H" in out_cfg120, (
            f"Config dialog not centered at (15, 36) in 120x40: {out_cfg120}"
        )
        assert b"\x1b[2J" not in out_cfg120, (
            f"Spurious screen clear emitted by 120x40 Config: {out_cfg120}"
        )
        assert b"Select [0-7] to change    [ESC]=Cancel" in out_cfg120, (
            f"Config prompt options not formatted: {out_cfg120}"
        )
        assert b"[ESC]/[Q]" not in out_cfg120, (
            f"Slash delimiter present in 120x40 config prompt: {out_cfg120}"
        )
        print("    [+] 120x40 Config dialog centered at (15, 36) without "
              "slash delimiters.")

        # Subtest 2.3: Verify 'q' cannot dismiss in 120x40
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"q")
        ok_dismiss, _ = read_until(master, b"SE - Plugin Manager", timeout=0.5)
        assert not ok_dismiss, "120x40 Config erroneously dismissed on 'q'!"

        # Dismiss via ESC
        time.sleep(0.2)
        os.write(master, b"\x1b")
        ok, _ = read_until(master, b"SE - Plugin Manager", timeout=6.0)
        assert ok, "Failed to dismiss 120x40 Config via ESC"
        read_until(master, b"[Down]=Select", timeout=5.0)
        drain_all(master)
        print("    [+] 120x40 Config dialog dismissed cleanly via ESC.")

        # Clean exit to CP/M
        time.sleep(0.3)
        os.write(master, b"q")  # Exit Plugin Manager
        read_until(master, b"for about", timeout=6.0)
        time.sleep(0.3)
        os.write(master, b"\x11")  # Exit SE.COM (Ctrl+Q)
        ok, out = read_until(master, b"C>", timeout=6.0)
        assert ok, f"Failed to exit cleanly to CP/M prompt: {out}"
        print("[+] Returned to CP/M cleanly.")

        print("\n=======================================================")
        print("  BUG 2.23 VERIFICATION PASSED (100%)!")
        print("=======================================================\n")
        return True

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            proc.kill()
        os.close(master)


if __name__ == "__main__":
    t0 = time.time()
    success = test_bug_2_23()
    elapsed = time.time() - t0
    if not success:
        sys.exit(1)
    print(f"Elapsed: {elapsed:.2f}s")
