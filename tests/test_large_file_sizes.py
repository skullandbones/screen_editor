#!/usr/bin/env python3
"""
test_large_file_sizes.py - Validation of Loading and Saving Large Text Files

Verifies that SE.COM loads, navigates, and saves text files in the range
16,384 bytes to 32,768 bytes (32K max size) with 100% byte fidelity.

Test Cases (4 file sizes across the range):
  1. 16,384 bytes (16.0 KB - range minimum, 128 sectors)
  2. 21,845 bytes (21.3 KB - intermediate unaligned size)
  3. 27,306 bytes (26.7 KB - intermediate unaligned size)
  4. 32,768 bytes (32.0 KB - range maximum, 256 sectors)
"""

import os
import sys
import time
import tty
import select
import subprocess

TEST_SIZES = [
    (16384, "F16K.TXT", "16,384 bytes (16 KB min)"),
    (21845, "F21K.TXT", "21,845 bytes (21.3 KB)"),
    (27306, "F27K.TXT", "27,306 bytes (26.7 KB)"),
    (32768, "F32K.TXT", "32,768 bytes (32 KB max)"),
]

def find_workspace_root(start_dir):
    curr = os.path.abspath(start_dir)
    while curr != os.path.dirname(curr):
        if os.path.isdir(os.path.join(curr, "tools", "romwbw_src")):
            return curr
        curr = os.path.dirname(curr)
    raise RuntimeError("Could not locate tools/romwbw_src")

def find_paths():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    workspace_root = find_workspace_root(repo_root)
    emu_bin = os.path.join(
        workspace_root, "tools", "rc2014_emu", "rc2014"
    )
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
        emu_bin, rom_file, img_file, se_bin,
        cpmcp_bin, cpmrm_bin, cpmls_bin
    )

def generate_text_file(target_bytes, output_path):
    """
    Generate an ASCII text file of exactly target_bytes.
    All lines end with CRLF (\\r\\n) and stay <= 72 characters wide.
    """
    lines = []
    current_bytes = 0
    line_num = 1

    # Standard line template: 48 bytes total
    # "Line 00001: Data payload buffer test 1234567890\\r\\n"
    while current_bytes + 64 <= target_bytes:
        line_str = (
            f"Line {line_num:05d}: Data payload buffer test "
            f"1234567890\r\n"
        )
        encoded = line_str.encode("ascii")
        lines.append(encoded)
        current_bytes += len(encoded)
        line_num += 1

    remaining = target_bytes - current_bytes
    if remaining > 0:
        prefix = f"Line {line_num:05d}: End payload "
        prefix_len = len(prefix)
        if remaining >= prefix_len + 2:
            pad_len = remaining - prefix_len - 2
            final_str = prefix + ("=" * pad_len) + "\r\n"
        else:
            if lines:
                last_line = lines.pop()
                current_bytes -= len(last_line)
                remaining = target_bytes - current_bytes
                prefix = f"Line {line_num - 1:05d}: End "
                pad_len = remaining - len(prefix) - 2
                final_str = prefix + ("=" * pad_len) + "\r\n"
            else:
                final_str = ("X" * (remaining - 2)) + "\r\n"
        lines.append(final_str.encode("ascii"))

    content = b"".join(lines)
    assert len(content) == target_bytes, (
        f"Length mismatch: {len(content)} != {target_bytes}"
    )
    with open(output_path, "wb") as f:
        f.write(content)
    return len(lines)

def read_until(master_fd, match_bytes, timeout=40.0):
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

def boot_cpm(emu_bin, rom_file, img_file):
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )
    os.close(slave)

    out = read_until(master, b"Boot [H=Help]:", timeout=15.0)
    if b"Boot [H=Help]:" not in out:
        proc.terminate()
        os.close(master)
        raise RuntimeError("Failed to reach RomWBW boot prompt")

    time.sleep(0.4)
    os.write(master, b"c\r")
    out = read_until(master, b"B>", timeout=15.0)
    if b"B>" not in out:
        proc.terminate()
        os.close(master)
        raise RuntimeError("Failed to boot CP/M")

    time.sleep(0.4)
    os.write(master, b"c:\r")
    out = read_until(master, b"C>", timeout=15.0)
    if b"C>" not in out:
        proc.terminate()
        os.close(master)
        raise RuntimeError("Failed to switch to Drive C:")

    return proc, master

def run_single_size_test(target_bytes, cpm_filename, description):
    paths = find_paths()
    emu_bin, rom_file, img_file, se_bin = paths[0], paths[1], paths[2], paths[3]
    cpmcp_bin, cpmrm_bin = paths[4], paths[5]

    test_file = f"/tmp/{cpm_filename}"
    saved_file = f"/tmp/{cpm_filename}.SAVED"
    cpm_user = f"0:{cpm_filename}"

    print("\n" + "=" * 70)
    print(f"[*] Testing {description} ({target_bytes} bytes)...")
    print("=" * 70)

    # 1. Generate exact test file
    print(f"[*] Step 1: Generating exact test file ({cpm_filename})...")
    total_lines = generate_text_file(target_bytes, test_file)
    print(
        f"[+] Step 1: Generated {test_file}: {target_bytes} bytes, "
        f"{total_lines} lines."
    )

    # 2. Prepare disk image
    print("[*] Step 2: Preparing disk image...")
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:$$$se$$$.swp"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.CFG"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:RAMDRV.IMG"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, cpm_user],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.COM"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, "0:SE.COM"],
        check=True
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, test_file, cpm_user],
        check=True
    )
    print(f"[+] Step 2: Injected SE.COM and {cpm_filename} into disk image.")

    # 3. Boot emulator
    print("[*] Step 3: Booting emulator...")
    proc, master = boot_cpm(emu_bin, rom_file, img_file)
    print("[+] Step 3: RomWBW booted into CP/M successfully.")

    try:
        # 4. Ensure drive C directory is logged in
        print("[*] Step 4: Ensuring drive C directory is logged in...")
        time.sleep(0.4)
        os.write(master, f"dir {cpm_filename}\r".encode("ascii"))
        out_dir = read_until(master, b"C>", timeout=10.0)
        dir_text = out_dir.decode("ascii", errors="replace")
        print(f"[*] CP/M DIR output:\n{dir_text}")
        time.sleep(0.4)
        drain_all(master, quiet_time=0.1)
        print("[+] Step 4: Drive C directory logged in.")

        # 5. Launch editor
        cmd_str = f"se {cpm_filename}\r".encode("ascii")
        print(f"[*] Step 5: Executing 'se {cpm_filename}'...")
        t0 = time.time()
        os.write(master, cmd_str)

        expected_line_stat = f"1/{total_lines}".encode("ascii")
        out_load = read_until(master, expected_line_stat, timeout=120.0)
        dt_load = time.time() - t0
        time.sleep(0.3)
        out_load += drain_all(master)

        if expected_line_stat not in out_load:
            print(f"[-] Step 5: Failed to load {cpm_filename}.")
            print(f"    out_load len: {len(out_load)}")
            print(f"    out_load head: {repr(out_load[:300])}")
            print(f"    out_load tail: {repr(out_load[-300:])}")
            return False
        print(
            f"[+] Step 5: Document loaded in {dt_load:.2f}s "
            f"(verified Line 1/{total_lines})."
        )

        # 6. Verify Jump to Bottom (Ctrl+G)
        print("[*] Step 6: Verifying Jump to Bottom (Ctrl+G)...")
        drain_all(master, quiet_time=0.15)
        os.write(master, b"\x07")  # Ctrl+G
        expected_bot = f"{total_lines}/{total_lines}".encode("ascii")
        out_bot = read_until(master, expected_bot, timeout=20.0)
        out_bot += drain_all(master, quiet_time=0.15)

        if expected_bot not in out_bot:
            print(f"[-] Step 6: Jump to bottom failed: {repr(out_bot[-200:])}")
            return False
        print(
            f"[+] Step 6: Jump to bottom (Ctrl+G) verified: Line {total_lines}."
        )

        # 7. Jump back to top (Ctrl+T)
        print("[*] Step 7: Verifying Jump back to top (Ctrl+T)...")
        drain_all(master, quiet_time=0.15)
        os.write(master, b"\x14")  # Ctrl+T
        out_top = read_until(master, expected_line_stat, timeout=20.0)
        out_top += drain_all(master, quiet_time=0.15)
        if expected_line_stat not in out_top:
            print(f"[-] Step 7: Jump to top failed: {repr(out_top[-200:])}")
            return False
        print(
            f"[+] Step 7: Jump to top (Ctrl+T) verified: Line 1/{total_lines}."
        )

        # 8. Save document via Ctrl+S
        print("[*] Step 8: Saving file via Ctrl+S...")
        drain_all(master, quiet_time=0.15)
        os.write(master, b"\x13")  # Ctrl+S
        out_save = read_until(master, b"SAVE FILE", timeout=10.0)
        if b"SAVE FILE" not in out_save:
            print(f"[-] Step 8: Save prompt not shown: {repr(out_save[-200:])}")
            return False

        # Confirm filename (Enter)
        time.sleep(0.3)
        os.write(master, b"\r")
        out_ow = read_until(master, b"Overwrite?", timeout=8.0)
        if b"Overwrite?" not in out_ow:
            print(
                f"[-] Step 8: Overwrite prompt not received: "
                f"{repr(out_ow[-200:])}"
            )
            return False

        # Confirm overwrite ('y') - ensure buffer drained first
        drain_all(master, quiet_time=0.2)
        time.sleep(0.2)
        os.write(master, b"y")
        t_save0 = time.time()
        out_resumed = read_until(master, b"^K: Editor keys", timeout=80.0)
        out_resumed += read_until(master, expected_line_stat, timeout=10.0)
        dt_save = time.time() - t_save0
        if b"^K: Editor keys" not in out_resumed:
            print(
                f"[-] Step 8: Editor did not resume after save: "
                f"{repr(out_resumed[-200:])}"
            )
            return False
        print(f"[+] Step 8: File saved and editor resumed in {dt_save:.2f}s.")

        # 9. Clean exit via Ctrl+Q
        print("[*] Step 9: Exiting editor cleanly via Ctrl+Q...")
        drain_all(master, quiet_time=0.2)
        time.sleep(0.2)
        os.write(master, b"\x11")  # Ctrl+Q
        out_exit = read_until(master, b"C>", timeout=10.0)
        if b"C>" not in out_exit:
            print(f"[-] Step 9: Failed clean exit to CP/M: "
                  f"{repr(out_exit[-200:])}")
            return False
        print("[+] Step 9: Exited cleanly to CP/M prompt.")

        # 10. Extract saved file and verify 100% byte fidelity
        print("[*] Step 10: Extracting saved file and verifying byte "
              "fidelity...")
        if os.path.exists(saved_file):
            os.remove(saved_file)
        subprocess.run(
            [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, cpm_user, saved_file],
            check=True
        )

        with open(saved_file, "rb") as f:
            clean_saved = f.read().split(b"\x1a")[0]
        with open(test_file, "rb") as f:
            clean_orig = f.read().split(b"\x1a")[0]

        if clean_saved != clean_orig:
            print("[-] Step 10: Byte comparison mismatch!")
            print(
                f"    Orig: {len(clean_orig)} bytes, "
                f"Saved: {len(clean_saved)} bytes"
            )
            return False

        if len(clean_saved) != target_bytes:
            print(
                f"[-] Step 10: Size mismatch: got {len(clean_saved)}, "
                f"expected {target_bytes}"
            )
            return False

        print(
            f"[+] Step 10: 100% BYTE FIDELITY VERIFIED: exact {target_bytes} "
            f"bytes preserved across load/save cycle!"
        )
        return True

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            pass
        os.close(master)
        # Cleanup CP/M disk
        subprocess.run(
            [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, cpm_user],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )

def main():
    print("==================================================================")
    print("  SE.COM Large File Size Test Suite (16,384 B to 32,768 B)        ")
    print("==================================================================")

    sizes_to_test = TEST_SIZES
    if len(sys.argv) > 1:
        target = int(sys.argv[1])
        sizes_to_test = [
            (target, f"F{target//1024}K.TXT", f"Custom {target} bytes")
        ]

    for target_bytes, cpm_fn, desc in sizes_to_test:
        ok = run_single_size_test(target_bytes, cpm_fn, desc)
        if not ok:
            print(f"\n[-] FAILED on {desc} ({target_bytes} bytes)")
            return False

    print("\n" + "=" * 70)
    print("  ALL 4 LARGE FILE SIZE TESTS PASSED WITH 100% BYTE FIDELITY!    ")
    print("==================================================================")
    return True

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
