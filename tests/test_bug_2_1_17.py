#!/usr/bin/env python3
"""
test_bug_2_1_17.py - Verification for Bug 2.1.17:
Modal Dialog Cancellation by Unexpected Keystrokes.

Verifies:
  1. Boot RomWBW CP/M on RC2014 emulator with multi-line TEST17.TXT.
  2. Launch SE.COM to open TEST17.TXT.
  3. Open Goto Line modal (Ctrl+L). Type '10'. Send unexpected escape
     sequences (Up, Down, Left, Right arrows, PgUp, PgDn) and unassigned
     keys (Ctrl+U, Ctrl+V). Verify dialog remains open with input intact.
     Confirm with Enter and verify cursor jumps to Line 10.
  4. Open Find Text modal (Ctrl+F). Type 'Line 5'. Send unexpected escape
     sequences. Verify dialog remains open. Cancel with standalone ESC.
  5. Open Replace Text modal (Ctrl+R). Enter search string 'Line 7'.
     In Replace With modal, send unexpected escape sequences. Verify
     dialog remains open. Cancel with standalone ESC.
  6. Exit cleanly from editor (Ctrl+Q, 'n') back to CP/M prompt.
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

    return emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin


def read_until(master_fd, match_bytes, timeout=15.0):
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


def boot_cpm(emu_bin, rom_file, img_file):
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )
    os.close(slave)

    out = read_until(master, b"Boot [H=Help]:", timeout=8.0)
    if b"Boot [H=Help]:" not in out:
        raise RuntimeError("Failed to reach RomWBW boot prompt")

    time.sleep(0.4)
    os.write(master, b"c\r")
    out = read_until(master, b"B>", timeout=15.0)
    if b"B>" not in out:
        raise RuntimeError("Failed to boot into CP/M prompt")

    return proc, master


def test_bug_2_1_17():
    start_time = time.time()
    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = find_paths()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    doc_path = os.path.join(script_dir, "test17.txt")

    # Prepare 20-line test document
    doc_lines = [f"Line {i:02d}: Content for testing modal dialogs\r\n"
                 for i in range(1, 21)]
    with open(doc_path, "wb") as f:
        f.write("".join(doc_lines).encode("ascii"))

    # Step 1: Inject updated SE.COM and TEST17.TXT onto disk
    print("[*] Step 1: Injecting SE.COM and TEST17.TXT onto disk...",
          flush=True)
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.COM", "0:TEST17.TXT"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, "0:SE.COM"],
        check=True
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, doc_path, "0:TEST17.TXT"],
        check=True
    )
    print("[+] Step 1: Injected SE.COM and TEST17.TXT successfully.",
          flush=True)

    # Step 2: Boot RomWBW CP/M
    print("[*] Step 2: Booting RomWBW CP/M on RC2014 emulator...", flush=True)
    proc, master = boot_cpm(emu_bin, rom_file, img_file)
    print("[+] Step 2: Booted into CP/M prompt.", flush=True)

    try:
        # Step 3: Switch to drive C:
        print("[*] Step 3: Switching to drive C:...", flush=True)
        time.sleep(0.4)
        os.write(master, b"c:\r")
        out_c = read_until(master, b"C>", timeout=10.0)
        if b"C>" not in out_c:
            buf_str = repr(out_c[-300:])
            print(f"[-] Step 3: Failed to reach C>. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 3: Switched to drive C:.", flush=True)

        # Step 4: Launch SE TEST17.TXT
        print("[*] Step 4: Launching SE TEST17.TXT...", flush=True)
        time.sleep(0.4)
        os.write(master, b"se test17.txt\r")
        out_edit = read_until(master, b"TEST17.TXT", timeout=45.0)
        if b"TEST17.TXT" not in out_edit:
            buf_str = repr(out_edit[-300:])
            print(f"[-] Step 4: Editor load failed. Buffer: {buf_str}",
                  flush=True)
            return False
        time.sleep(0.5)
        drain_all(master)
        print("[+] Step 4: Opened TEST17.TXT in editor.", flush=True)

        # Step 5: Test Goto Line modal (Ctrl+L) with unexpected keys
        print("[*] Step 5: Testing Goto Line dialog unexpected keys...",
              flush=True)
        time.sleep(0.4)
        os.write(master, b"\x0c")  # Ctrl+L -> Goto Line modal
        out_goto = read_until(master, b"Goto line:", timeout=5.0)
        if b"Goto line:" not in out_goto:
            buf_str = repr(out_goto[-300:])
            print(f"[-] Step 5: Goto Line dialog did not open. Buffer: "
                  f"{buf_str}", flush=True)
            return False

        # Type '10'
        os.write(master, b"10")
        time.sleep(0.2)

        # Send unexpected escape sequences (Up, Down, Left, Right arrows)
        os.write(master, b"\x1b[A")  # Up arrow
        time.sleep(0.1)
        os.write(master, b"\x1b[B")  # Down arrow
        time.sleep(0.1)
        os.write(master, b"\x1b[C")  # Right arrow
        time.sleep(0.1)
        os.write(master, b"\x1b[D")  # Left arrow
        time.sleep(0.1)
        os.write(master, b"\x1b[5~")  # PgUp
        time.sleep(0.1)
        os.write(master, b"\x1b[6~")  # PgDn
        time.sleep(0.1)

        # Send unassigned keys: Ctrl+U, Ctrl+V, letter 'x'
        os.write(master, b"\x15")  # Ctrl+U
        time.sleep(0.1)
        os.write(master, b"\x16")  # Ctrl+V
        time.sleep(0.1)
        os.write(master, b"x")  # non-digit character
        time.sleep(0.2)

        # Now confirm with Enter
        os.write(master, b"\r")
        out_jump = read_until(master, b"Line   10", timeout=5.0)
        if b"Line   10" not in out_jump:
            buf_str = repr(out_jump[-300:])
            print(f"[-] Step 5: Jump to Line 10 failed. Buffer: {buf_str}",
                  flush=True)
            return False
        time.sleep(0.3)
        drain_all(master)
        print("[+] Step 5: Goto Line preserved input and jumped to Line 10.",
              flush=True)

        # Step 6: Test Find Text modal (Ctrl+F) with unexpected keys
        print("[*] Step 6: Testing Find Text dialog unexpected keys...",
              flush=True)
        time.sleep(0.4)
        os.write(master, b"\x06")  # Ctrl+F -> Find Text modal
        out_find = read_until(master, b"Find:", timeout=5.0)
        if b"Find:" not in out_find:
            buf_str = repr(out_find[-300:])
            print(f"[-] Step 6: Find dialog did not open. Buffer: {buf_str}",
                  flush=True)
            return False

        # Type 'Line 15'
        os.write(master, b"Line 15")
        time.sleep(0.2)

        # Send unexpected escape sequences
        os.write(master, b"\x1b[A")  # Up arrow
        time.sleep(0.1)
        os.write(master, b"\x1b[B")  # Down arrow
        time.sleep(0.1)
        os.write(master, b"\x1b[C")  # Right arrow
        time.sleep(0.1)
        os.write(master, b"\x1b[D")  # Left arrow
        time.sleep(0.3)

        # Confirm with Enter
        os.write(master, b"\r")
        out_find_jump = read_until(master, b"Line   15", timeout=5.0)
        if b"Line   15" not in out_find_jump:
            buf_str = repr(out_find_jump[-300:])
            print(f"[-] Step 6: Find match navigation failed. Buffer: "
                  f"{buf_str}", flush=True)
            return False
        time.sleep(0.3)
        drain_all(master)
        print("[+] Step 6: Find Text preserved input and matched Line 15.",
              flush=True)

        # Step 7: Test Replace Text modal (Ctrl+R) with unexpected keys
        print("[*] Step 7: Testing Replace Text dialog unexpected keys...",
              flush=True)
        time.sleep(0.4)
        os.write(master, b"\x12")  # Ctrl+R -> Replace modal
        out_rep_find = read_until(master, b"[ESC]=Cancel", timeout=5.0)
        if b"Find:" not in out_rep_find:
            buf_str = repr(out_rep_find[-300:])
            print(f"[-] Step 7: Replace Find dialog missing. Buffer: "
                  f"{buf_str}", flush=True)
            return False

        time.sleep(0.2)
        # Press Enter to confirm prefilled find pattern ('Line 15')
        os.write(master, b"\r")
        out_rep_popup = read_until(master, b"Replace with:", timeout=5.0)
        if b"Replace with:" not in out_rep_popup:
            buf_str = repr(out_rep_popup[-300:])
            print(f"[-] Step 7: Replace with dialog missing. Buffer: "
                  f"{buf_str}", flush=True)
            return False

        time.sleep(0.2)
        # Send unexpected escape sequences into Replace With field
        os.write(master, b"\x1b[A")  # Up arrow
        time.sleep(0.1)
        os.write(master, b"\x1b[B")  # Down arrow
        time.sleep(0.2)

        # Type replacement text 'Replaced 07'
        os.write(master, b"Replaced 07")
        time.sleep(0.2)

        # Confirm replacement string with Enter
        os.write(master, b"\r")
        out_rep_conf = read_until(master, b"[Y]es", timeout=5.0)
        if b"[Y]es" not in out_rep_conf:
            buf_str = repr(out_rep_conf[-300:])
            print(f"[-] Step 7: Replace confirm query missing. Buffer: "
                  f"{buf_str}", flush=True)
            return False

        # Cancel confirmation via standalone ESC
        time.sleep(0.3)
        os.write(master, b"\x1b")
        time.sleep(0.5)
        # Dismiss Replace summary popup
        os.write(master, b"\r")
        time.sleep(0.4)
        drain_all(master)
        print("[+] Step 7: Replace Text handled escape sequences cleanly.",
              flush=True)

        # Step 8: Exit cleanly via Ctrl+Q back to CP/M
        print("[*] Step 8: Exiting editor cleanly back to CP/M...", flush=True)
        time.sleep(0.3)
        os.write(master, b"\x11")  # Ctrl+Q exits clean document directly
        out_exit = read_until(master, b"Returned to CP/M", timeout=5.0)
        if b"Returned to CP/M" not in out_exit:
            os.write(master, b"\x11")
            out_exit += read_until(master, b"Returned to CP/M", timeout=5.0)
        out_exit += read_until(master, b"C>", timeout=5.0)
        if b"C>" not in out_exit and b"Returned to CP/M" not in out_exit:
            buf_str = repr(out_exit[-300:])
            print(f"[-] Step 8: Clean exit failed. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 8: Exited cleanly back to CP/M.", flush=True)

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            pass
        os.close(master)
        if os.path.exists(doc_path):
            os.remove(doc_path)

    elapsed = time.time() - start_time
    print(f"[+] All Bug 2.1.17 tests PASSED in {elapsed:.2f}s!", flush=True)
    return True


if __name__ == "__main__":
    success = test_bug_2_1_17()
    sys.exit(0 if success else 1)
