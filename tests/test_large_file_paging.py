#!/usr/bin/env python3
"""
test_large_file_paging.py - Automated validation of Phase 4 Paging Engine

Verifies that SE.COM:
1. Loads files exceeding physical Far RAM capacity in Protected Mode
   (1,200 lines > 1,024 physical slots).
2. Loads files exceeding physical Far RAM capacity in Enabled Mode
   (3,400 lines > 3,072 physical slots).
3. Spans across pages into $$$SE$$$.SWP via BDOS random record paging.
4. Correctly reflects the full document line count in status bar (Line 1/N).
5. Supports jump-to-bottom (Ctrl+G) & jump-to-top (Ctrl+T) without corruption.
6. Saves multi-thousand line documents to disk with 100% byte fidelity.
7. Cleans up temporary swap file ($$$SE$$$.SWP) upon clean exit.
"""

import os
import sys
import time
import tty
import select
import subprocess


def find_paths(use_sec=False):
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
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
    se_bin = os.path.join(repo_root, "SEC.COM" if use_sec else "SE.COM")
    cpmcp_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp"
    )
    cpmrm_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm"
    )
    cpmls_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmls"
    )
    return (
        emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin, cpmls_bin
    )


def read_until(master_fd, match_bytes, timeout=80.0):
    buf = b""
    t0 = time.time()
    while time.time() - t0 < timeout:
        r, _, _ = select.select([master_fd], [], [], 0.05)
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


def drain_all(master_fd, quiet_time=0.2):
    buf = b""
    while True:
        r, _, _ = select.select([master_fd], [], [], quiet_time)
        if not r:
            break
        try:
            data = os.read(master_fd, 4096)
            if not data:
                break
            buf += data
        except (BlockingIOError, OSError):
            break
    return buf


def run_paging_test(num_lines, ramdrive_mode="OFF"):
    (
        emu_bin, rom_file, img_file, se_bin,
        cpmcp_bin, cpmrm_bin, cpmls_bin,
    ) = find_paths()
    test_file = f"/tmp/SHORT{num_lines}.TXT"
    saved_file = f"/tmp/SHORT{num_lines}_SAVED.TXT"
    cpm_user = f"0:S{num_lines}.TXT"
    cmd_arg = f"S{num_lines}.TXT"

    print("\n" + "=" * 65)
    print(f"[*] Testing {num_lines} lines (RAMDRIVE={ramdrive_mode})...")
    print("=" * 65)

    # Generate test file
    with open(test_file, "wb") as f:
        for i in range(1, num_lines + 1):
            f.write(f"Record {i:04d} of {num_lines:04d}\r\n".encode())

    # Clean up disk image
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:$$$se$$$.swp"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.CFG"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, target_cpm],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, cpm_user],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )

    # Inject SE.COM and test file
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, target_cpm],
        check=True,
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, test_file, cpm_user],
        check=True,
    )

    # Setup configuration if RAMDRIVE=ON
    if ramdrive_mode == "ON":
        cfg_tmp = "/tmp/SE_TEST.CFG"
        with open(cfg_tmp, "wb") as f:
            f.write(b"SCREEN=120x40\r\nRAMDRIVE=ON\r\n")
        subprocess.run(
            [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, cfg_tmp, "0:SE.CFG"],
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
        # Boot sequence
        read_until(master, b"Boot [H=Help]:", timeout=8.0)
        time.sleep(0.3)
        os.write(master, b"c\r")
        read_until(master, b"B>", timeout=8.0)
        time.sleep(0.3)
        os.write(master, b"c:\r")
        read_until(master, b"C>", timeout=8.0)
        time.sleep(0.3)

        print(
            f"[*] Launching '{cmd_name} {cmd_arg}' (streaming {num_lines} "
            "lines into virtual paging engine)..."
        )
        t0 = time.time()
        os.write(master, f"{cmd_name} {cmd_arg}\r".encode())
        expected_top = f"1/{num_lines}".encode()
        load_timeout = max(120.0, num_lines * 0.08)
        out = read_until(master, expected_top, timeout=load_timeout)
        dt = time.time() - t0
        time.sleep(0.3)
        out += drain_all(master)
        print(f"[*] Entered editor in {dt:.1f}s.")

        if expected_top not in out:
            print(
                f"[-] FAILED: Status bar did not show "
                f"'{expected_top.decode()}'. Buffer: {repr(out[-300:])}"
            )
            return False
        print(
            f"[+] SUCCESS: Document loaded {num_lines} lines "
            "with paging active!"
        )

        # Verify swap file exists on disk while editor is running
        ls_res = subprocess.run(
            [cpmls_bin, "-f", "wbw_hd1k_0", img_file, "0:$$$SE$$$.SWP"],
            capture_output=True, text=True,
        )
        if "$$$se$$$.swp" in ls_res.stdout.lower():
            print("[+] Verified: $$$SE$$$.SWP swap file is active on disk!")
        else:
            print(
                "[-] Warning: Swap file not found via cpmls during "
                "active session."
            )

        # Test Ctrl+O directory listing while swap file is active
        print("[*] Testing Ctrl+O directory listing with active swap...")
        os.write(master, b"\x0f")
        out_open = read_until(master, b"OPEN FILE (DIRECTORY", timeout=10.0)
        time.sleep(0.3)
        out_open += drain_all(master)
        if b"OPEN FILE (DIRECTORY" not in out_open:
            print(f"[-] FAILED Ctrl+O screen: {repr(out_open[-200:])}")
            return False
        if b"$$$SE$$$" in out_open or b"$$$se$$$" in out_open:
            print("[-] FAILED: Swap file displayed in directory listing!")
            return False
        # Press ESC to cancel back to editor
        os.write(master, b"\x1b")
        out_resume = read_until(master, expected_top, timeout=10.0)
        time.sleep(0.2)
        out_resume += drain_all(master)
        if expected_top not in out_resume:
            print(f"[-] FAILED to resume after ESC: {repr(out_resume[-200:])}")
            return False
        print("[+] Verified: Ctrl+O directory cleanly filters swap file!")

        # Test Jump to Bottom (Ctrl+G)
        print("[*] Testing Jump to Bottom (Ctrl+G) across paged memory...")
        os.write(master, b"\x07")
        expected_bot = f"Line {num_lines}/{num_lines}".encode()
        out_bot = read_until(master, expected_bot, timeout=60.0)
        time.sleep(0.3)
        out_bot += drain_all(master)
        if expected_bot not in out_bot:
            print(f"[-] FAILED jump to bottom. Buffer: {repr(out_bot[-300:])}")
            return False
        print(f"[+] Reached bottom: {expected_bot.decode()}")

        bot_rec = f"Record {num_lines:04d} of {num_lines:04d}".encode()
        if bot_rec in out_bot:
            print(
                "[+] Screen content verified uncorrupted: "
                f"'{bot_rec.decode()}'!"
            )
        else:
            print(
                f"[-] Screen content mismatch at bottom: '{bot_rec.decode()}' "
                f"not found! Raw: {repr(out_bot[-300:])}"
            )
            return False

        # Test Jump to Top (Ctrl+T)
        print("[*] Testing Jump to Top (Ctrl+T) across paged memory...")
        os.write(master, b"\x14")
        expected_top_stat = f"Line    1/{num_lines}".encode()
        out_top = read_until(master, expected_top_stat, timeout=60.0)
        time.sleep(0.3)
        out_top += drain_all(master)
        if expected_top_stat not in out_top:
            print(f"[-] FAILED jump to top. Buffer: {repr(out_top[-300:])}")
            return False
        print(f"[+] Reached top: {expected_top_stat.decode()}")

        top_rec = f"Record 0001 of {num_lines:04d}".encode()
        if top_rec in out_top:
            print(
                "[+] Screen content verified uncorrupted: "
                f"'{top_rec.decode()}'!"
            )
        else:
            print(
                f"[-] Screen content mismatch at top: '{top_rec.decode()}' "
                f"not found! Raw: {repr(out_top[-300:])}"
            )
            return False

        # Save the file via Ctrl+S
        print(f"[*] Saving {num_lines}-line document via Ctrl+S...", flush=True)
        time.sleep(0.5)
        os.write(master, b"\x13")
        out_save_scr = read_until(master, b"SAVE FILE", timeout=10.0)
        if b"SAVE FILE" not in out_save_scr:
            print(
                f"[-] Save screen not reached. Buffer: "
                f"{repr(out_save_scr[-200:])}", flush=True,
            )
            return False
        if b"$$$SE$$$" in out_save_scr or b"$$$se$$$" in out_save_scr:
            print("[-] FAILED: Swap file found in Save File directory!")
            return False

        # Press Enter to confirm pre-filled filename
        time.sleep(0.2)
        os.write(master, b"\r")
        out_ow = read_until(master, b"Overwrite?", timeout=8.0)
        if b"Overwrite?" not in out_ow:
            print(
                f"[-] Overwrite prompt not received. Buffer: "
                f"{repr(out_ow[-200:])}", flush=True,
            )
            return False

        # Confirm overwrite with 'y'
        time.sleep(0.2)
        os.write(master, b"y")
        t_save0 = time.time()
        save_timeout = max(120.0, num_lines * 0.08)
        out_resumed = read_until(
            master, expected_top_stat, timeout=save_timeout
        )
        dt_save = time.time() - t_save0
        if expected_top_stat not in out_resumed:
            print(
                f"[-] Failed to resume editor after save. Buffer: "
                f"{repr(out_resumed[-200:])}", flush=True,
            )
            return False
        print(
            f"[+] Save completed in {dt_save:.1f}s and editor resumed.",
            flush=True,
        )

        # Exit cleanly via Ctrl+Q (document clean, exits directly to C>)
        print("[*] Exiting SE via Ctrl+Q...", flush=True)
        time.sleep(0.5)
        os.write(master, b"\x11")
        out_exit = read_until(master, b"C>", timeout=10.0)
        if b"C>" not in out_exit:
            print(
                f"[-] Clean exit failed. Buffer: {repr(out_exit[-200:])}",
                flush=True,
            )
            return False
        print("[+] Returned cleanly to CP/M prompt.", flush=True)

        # Verify $$$SE$$$.SWP is deleted after exit
        ls_exit = subprocess.run(
            [cpmls_bin, "-f", "wbw_hd1k_0", img_file, "0:$$$SE$$$.SWP"],
            capture_output=True, text=True,
        )
        if "$$$se$$$.swp" not in ls_exit.stdout.lower():
            print(
                "[+] Verified: $$$SE$$$.SWP successfully cleaned up upon exit!"
            )
        else:
            print("[-] FAILED: $$$SE$$$.SWP was not deleted upon exit!")
            return False

        # Extract saved file and verify byte fidelity
        if os.path.exists(saved_file):
            os.remove(saved_file)
        subprocess.run(
            [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, cpm_user, saved_file],
            check=True,
        )

        with open(saved_file, "rb") as f:
            clean_saved = f.read().split(b"\x1a")[0]
        with open(test_file, "rb") as f:
            clean_orig = f.read().split(b"\x1a")[0]

        if clean_saved == clean_orig:
            print(
                f"[+] 100% BYTE FIDELITY VERIFIED across all {num_lines} "
                f"lines ({len(clean_saved)} bytes)!"
            )
            return True
        else:
            print("[-] Byte comparison failed! Mismatch in saved content.")
            print(
                f"    Orig len: {len(clean_orig)}, "
                f"Saved len: {len(clean_saved)}"
            )
            return False

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            pass
        os.close(master)
        # Cleanup SE.CFG on disk image
        subprocess.run(
            [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.CFG"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )


def main(use_sec=False):
    # Test 1: Protected Mode Paging (1,200 lines > 1,024 physical slots)
    ok1 = run_paging_test(1200, ramdrive_mode="OFF", use_sec=use_sec)
    if not ok1:
        print("[-] Protected Mode Paging test FAILED.")
        return False

    # Test 2: Max RAM Mode Paging (3,400 lines > 3,072 physical slots)
    ok2 = run_paging_test(3400, ramdrive_mode="ON", use_sec=use_sec)
    if not ok2:
        print("[-] Max RAM Mode Paging test FAILED.")
        return False

    print("\n" + "=" * 65)
    print("  ALL LARGE FILE PAGING TESTS PASSED SUCCESSFULLY!               ")
    print("=" * 65)
    return True


if __name__ == "__main__":
    use_sec_arg = "--sec" in sys.argv
    success = main(use_sec=use_sec_arg)
    sys.exit(0 if success else 1)
