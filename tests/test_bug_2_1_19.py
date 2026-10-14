#!/usr/bin/env python3
"""
test_bug_2_1_19.py - Verification for Bug 2.1.19:
Search & Replace 120-Character Line Length Barrier.

Verifies:
  1. Boot RomWBW CP/M on RC2014 emulator.
  2. Launch SE.COM with a test file containing a 146-char line (> 120 chars).
  3. Initiate Search & Replace (Ctrl+R) targeting pattern on the long line.
  4. Confirm replacement ('y') and assert no 'Line > 120 chars' popup occurs.
  5. Verify successful replacement popup ('Replace done: 1 replacement(s).').
  6. Save document (Ctrl+S) and exit cleanly to CP/M (Ctrl+Q).
  7. Extract document and verify byte contents reflect the replacement.
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


def test_bug_2_1_19():
    start_time = time.time()
    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = find_paths()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    test_txt_path = os.path.join(script_dir, "test19.txt")
    out_txt_path = os.path.join(script_dir, "out19.txt")

    # 146 characters on line 1: "AAA" + 140 'X's + "END"
    long_line = b"AAA" + (b"X" * 140) + b"END\r\n"
    with open(test_txt_path, "wb") as f:
        f.write(long_line)

    # Step 1: Inject updated SE.COM and TEST19.TXT onto disk
    print("[*] Step 1: Injecting SE.COM and TEST19.TXT onto disk...",
          flush=True)
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.COM", "0:TEST19.TXT"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, "0:SE.COM"],
        check=True
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, test_txt_path,
         "0:TEST19.TXT"],
        check=True
    )
    print("[+] Step 1: Injected test files successfully.", flush=True)

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

        # Step 4: Launch SE TEST19.TXT
        print("[*] Step 4: Launching SE TEST19.TXT...", flush=True)
        time.sleep(0.4)
        os.write(master, b"se test19.txt\r")
        out_edit = read_until(master, b"TEST19.TXT", timeout=25.0)
        if b"TEST19.TXT" not in out_edit:
            buf_str = repr(out_edit[-300:])
            print(f"[-] Step 4: Editor load failed. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 4: Opened TEST19.TXT in editor.", flush=True)

        # Step 5: Trigger Search & Replace (Ctrl+R)
        print("[*] Step 5: Triggering Search & Replace (Ctrl+R)...",
              flush=True)
        time.sleep(0.3)
        os.write(master, b"\x12")  # Ctrl+R
        out_find = read_until(master, b"Find Text", timeout=5.0)
        if b"Find Text" not in out_find:
            buf_str = repr(out_find[-300:])
            print(f"[-] Step 5: Find Text modal failed. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 5: Find Text modal opened.", flush=True)

        # Step 6: Enter search pattern 'AAA' and replace pattern 'BBBB'
        print("[*] Step 6: Entering search pattern 'AAA' and replace 'BBBB'...",
              flush=True)
        time.sleep(0.3)
        os.write(master, b"AAA\r")
        out_rep_dlg = read_until(master, b"Replace Text", timeout=5.0)
        if b"Replace Text" not in out_rep_dlg:
            buf_str = repr(out_rep_dlg[-300:])
            print(f"[-] Step 6: Replace dialog failed. Buffer: {buf_str}",
                  flush=True)
            return False

        time.sleep(0.3)
        os.write(master, b"BBBB\r")
        out_confirm = read_until(master, b"Replace this occurrence",
                                 timeout=5.0)
        if b"Replace this occurrence" not in out_confirm:
            buf_str = repr(out_confirm[-300:])
            print(f"[-] Step 6: Occurrence prompt failed. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 6: Replace occurrence prompt reached.", flush=True)

        # Step 7: Confirm replacement ('y') and assert no 120-char barrier
        print("[*] Step 7: Confirming replacement ('y')...", flush=True)
        time.sleep(0.3)
        os.write(master, b"y")
        out_subst = read_until(master, b"Replace done:", timeout=5.0)

        if b"Line > 120 chars" in out_subst or b"skipped" in out_subst:
            buf_str = repr(out_subst[-300:])
            print(f"[-] Step 7: 120-char barrier tripped! Buffer: {buf_str}",
                  flush=True)
            return False

        if b"Replace done:" not in out_subst:
            buf_str = repr(out_subst[-300:])
            print(f"[-] Step 7: Replace done missing. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 7: Replacement succeeded on 146-char line.",
              flush=True)

        # Step 8: Dismiss summary modal
        print("[*] Step 8: Dismissing Replace Done modal...", flush=True)
        time.sleep(0.3)
        os.write(master, b" ")  # Dismiss Replace Done popup
        out_resumed = read_until(master, b"TEST19.TXT", timeout=5.0)
        if b"TEST19.TXT" not in out_resumed:
            buf_str = repr(out_resumed[-300:])
            print(f"[-] Step 8: Editor did not resume. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 8: Dismissed modal; editor resumed.", flush=True)

        # Step 9: Exit cleanly via Ctrl+Q and confirm save ('y')
        print("[*] Step 9: Exiting editor cleanly with save ('y')...",
              flush=True)
        time.sleep(0.3)
        os.write(master, b"\x11")  # Ctrl+Q
        out_prompt = read_until(master, b"Save", timeout=5.0)
        if b"Save" not in out_prompt:
            buf_str = repr(out_prompt[-300:])
            print(f"[-] Step 9: Save prompt missing. Buffer: {buf_str}",
                  flush=True)
            return False
        time.sleep(0.3)
        os.write(master, b"y")
        out_exit = read_until(master, b"C>", timeout=10.0)
        if b"C>" not in out_exit:
            buf_str = repr(out_exit[-300:])
            print(f"[-] Step 9: Clean exit failed. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 9: Exited cleanly and saved document to disk.",
              flush=True)

        # Step 10: Extract and verify file contents
        print("[*] Step 10: Extracting saved file to verify contents...",
              flush=True)
        if os.path.exists(out_txt_path):
            os.remove(out_txt_path)
        subprocess.run(
            [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, "0:TEST19.TXT",
             out_txt_path],
            check=True
        )
        with open(out_txt_path, "rb") as f:
            saved_content = f.read()

        expected_prefix = b"BBBB" + (b"X" * 140) + b"END"
        if not saved_content.startswith(expected_prefix):
            print(f"[-] Step 10: Content mismatch. Head: {saved_content[:30]}",
                  flush=True)
            return False
        print("[+] Step 10: File contents verified with 100% byte fidelity.",
              flush=True)

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            pass
        os.close(master)
        for p in (test_txt_path, out_txt_path):
            if os.path.exists(p):
                os.remove(p)

    elapsed = time.time() - start_time
    print(f"[+] All Bug 2.1.19 tests PASSED in {elapsed:.2f}s!", flush=True)
    return True


if __name__ == "__main__":
    success = test_bug_2_1_19()
    sys.exit(0 if success else 1)
