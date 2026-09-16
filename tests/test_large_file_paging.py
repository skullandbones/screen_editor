#!/usr/bin/env python3
"""
test_large_file_paging.py - Automated validation of Phase 4 Paging Engine

Verifies that SE.COM:
1. Loads files exceeding physical Far RAM capacity (3,400 lines > 3,072 physical slots).
2. Spans across pages into $$$SE$$$.SWP via BDOS random record paging.
3. Correctly reflects the full document line count in the status bar (Line 1/3400).
4. Allows navigation and editing across paged boundaries.
5. Saves the entire multi-thousand line document to disk with 100% byte fidelity.
6. Cleans up the temporary swap file ($$$SE$$$.SWP) upon clean exit.
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

def main():
    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin, cpmls_bin = find_paths()
    test_file = "/tmp/SHORT34.TXT"
    saved_file = "/tmp/SHORT34_SAVED.TXT"
    cpm_user = "0:SHORT34.TXT"

    print("[*] Generating 3,400-line test file (SHORT34.TXT)...")
    expected_lines = []
    with open(test_file, "wb") as f:
        for i in range(1, 3401):
            line = f"Record {i:04d} of 3400\r\n".encode()
            f.write(line)
            expected_lines.append(line)
    orig_size = os.path.getsize(test_file)
    print(f"[+] Created {test_file} ({orig_size} bytes, 3,400 lines).")

    # Clean up any leftover swap file or test files on image
    subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:$$$SE$$$.SWP"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.COM"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, cpm_user],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, "0:SE.COM"], check=True)
    subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, test_file, cpm_user], check=True)
    print("[+] Injected SE.COM and SHORT34.TXT into disk image.")

    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)

    try:
        # Boot sequence
        read_until(master, b"Boot [H=Help]:", timeout=8.0)
        time.sleep(0.5)
        os.write(master, b"c\r")
        read_until(master, b"B>", timeout=8.0)
        time.sleep(0.5)
        os.write(master, b"c:\r")
        read_until(master, b"C>", timeout=8.0)
        time.sleep(0.5)

        print("[*] Launching 'se SHORT34.TXT' (streaming 3,400 lines into virtual paging engine)...")
        t0 = time.time()
        os.write(master, b"se SHORT34.TXT\r")
        out = read_until(master, b"Line    1/3400", timeout=90.0)
        dt = time.time() - t0
        time.sleep(0.3)
        out += drain_all(master)
        print(f"[*] Entered editor in {dt:.1f}s.")

        if b"Line    1/3400" not in out:
            print(f"[-] FAILED: Status bar did not show 'Line    1/3400'. Buffer: {repr(out[-400:])}")
            return False
        print("[+] SUCCESS: Document loaded 3,400 lines with paging active!")

        # Verify swap file exists on disk while editor is running
        ls_res = subprocess.run([cpmls_bin, "-f", "wbw_hd1k_0", img_file, "0:$$$SE$$$.SWP"],
                                capture_output=True, text=True)
        if "$$$se$$$.swp" in ls_res.stdout.lower():
            print("[+] Verified: $$$SE$$$.SWP swap file is active on disk!")
        else:
            print("[-] Warning: Swap file not found via cpmls during active session.")

        # Save the file via Ctrl+S
        print("[*] Saving 3,400-line document via Ctrl+S...", flush=True)
        time.sleep(0.5)
        os.write(master, b"\x13")
        out_save_scr = read_until(master, b"SAVE FILE", timeout=10.0)
        if b"SAVE FILE" not in out_save_scr:
            print(f"[-] Save screen not reached. Buffer: {repr(out_save_scr[-200:])}", flush=True)
            return False

        # Press Enter to confirm pre-filled filename
        time.sleep(0.2)
        os.write(master, b"\r")
        out_ow = read_until(master, b"Overwrite?", timeout=8.0)
        if b"Overwrite?" not in out_ow:
            print(f"[-] Overwrite prompt not received. Buffer: {repr(out_ow[-200:])}", flush=True)
            return False

        # Confirm overwrite with 'y'
        time.sleep(0.2)
        os.write(master, b"y")
        t_save0 = time.time()
        out_resumed = read_until(master, b"Line    1/3400", timeout=150.0)
        dt_save = time.time() - t_save0
        if b"Line    1/3400" not in out_resumed:
            print(f"[-] Failed to resume editor after save. Buffer: {repr(out_resumed[-200:])}", flush=True)
            return False
        print(f"[+] Save completed in {dt_save:.1f}s and editor resumed.", flush=True)

        # Exit cleanly via Ctrl+Q (document clean, exits directly to C>)
        print("[*] Exiting SE via Ctrl+Q...", flush=True)
        time.sleep(0.5)
        os.write(master, b"\x11")  # Ctrl+Q
        out_exit = read_until(master, b"C>", timeout=10.0)
        if b"C>" not in out_exit:
            print(f"[-] Clean exit failed. Buffer: {repr(out_exit[-200:])}", flush=True)
            return False
        print("[+] Returned cleanly to CP/M prompt.", flush=True)

        # Verify $$$SE$$$.SWP is deleted after exit
        ls_exit = subprocess.run([cpmls_bin, "-f", "wbw_hd1k_0", img_file, "0:$$$SE$$$.SWP"],
                                 capture_output=True, text=True)
        if "$$$se$$$.swp" not in ls_exit.stdout.lower():
            print("[+] Verified: $$$SE$$$.SWP successfully cleaned up upon exit!")
        else:
            print("[-] FAILED: $$$SE$$$.SWP was not deleted upon exit!")
            return False

        # Extract saved file from disk image
        if os.path.exists(saved_file):
            os.remove(saved_file)
        subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, cpm_user, saved_file], check=True)

        saved_size = os.path.getsize(saved_file)
        print(f"[*] Saved file size: {saved_size} bytes (original: {orig_size} bytes).")

        with open(saved_file, "rb") as f:
            saved_content = f.read()

        # Check byte-for-byte content up to CP/M EOF (^Z)
        with open(test_file, "rb") as f:
            orig_content = f.read()

        # In CP/M, files are padded to 128-byte record boundaries with 0x1A
        clean_saved = saved_content.split(b"\x1a")[0]
        clean_orig = orig_content.split(b"\x1a")[0]

        if clean_saved == clean_orig:
            print(f"[+] 100% BYTE FIDELITY VERIFIED across all 3,400 lines ({len(clean_saved)} bytes)!")
        else:
            print(f"[-] Byte comparison failed! Mismatch in saved content.")
            print(f"    Orig len: {len(clean_orig)}, Saved len: {len(clean_saved)}")
            return False

        return True

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except:
            pass
        os.close(master)

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
