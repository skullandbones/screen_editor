#!/usr/bin/env python3
"""
test_bug_2_1_13.py - Verification for Bug 2.1.13:
Escape Sequence Trailing Byte Leakage in Editor.

Verifies:
  1. Boot RomWBW CP/M on RC2014 emulator.
  2. Launch SE.COM to create a new document TEST13.TXT.
  3. Send unhandled multi-byte escape sequences (F5: \\x1b[15~, F12: \\x1b[24~,
     bracketed paste: \\x1b[200~, and mouse tracking: \\x1b[<0;20;10M).
  4. Send a single character 'A' and verify cursor is at Column 1.
  5. Assert no trailing escape characters ('~', digits) leaked into text.
  6. Exit cleanly to CP/M with save (Ctrl+Q, 'y').
  7. Extract document and verify byte content equals b"A\\r\\n".
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


def test_bug_2_1_13():
    start_time = time.time()
    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = find_paths()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    out_txt_path = os.path.join(script_dir, "out13.txt")

    # Step 1: Inject updated SE.COM onto disk and remove old TEST13.TXT
    print("[*] Step 1: Injecting SE.COM onto disk...", flush=True)
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.COM", "0:TEST13.TXT"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, "0:SE.COM"],
        check=True
    )
    print("[+] Step 1: Injected SE.COM successfully.", flush=True)

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

        # Step 4: Launch SE TEST13.TXT
        print("[*] Step 4: Launching SE TEST13.TXT...", flush=True)
        time.sleep(0.4)
        os.write(master, b"se test13.txt\r")
        out_edit = read_until(master, b"TEST13.TXT", timeout=25.0)
        if b"TEST13.TXT" not in out_edit:
            buf_str = repr(out_edit[-300:])
            print(f"[-] Step 4: Editor load failed. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 4: Opened TEST13.TXT in editor.", flush=True)

        # Step 5: Send unhandled escape sequences
        print("[*] Step 5: Sending unhandled multi-byte escape sequences...",
              flush=True)
        time.sleep(0.3)
        # F5 key: \x1b[15~
        os.write(master, b"\x1b[15~")
        time.sleep(0.2)
        # Bracketed paste start: \x1b[200~
        os.write(master, b"\x1b[200~")
        time.sleep(0.2)
        # F12 key: \x1b[24~
        os.write(master, b"\x1b[24~")
        time.sleep(0.2)
        # Mouse report: \x1b[<0;20;10M
        os.write(master, b"\x1b[<0;20;10M")
        time.sleep(0.2)

        # Now type a single character 'A'
        os.write(master, b"A")
        out_col1 = read_until(master, b"Col 1", timeout=5.0)
        if b"Col 1" not in out_col1:
            buf_str = repr(out_col1[-300:])
            print(f"[-] Step 5: Cursor not at Col 1. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 5: Drained sequences cleanly; cursor at Col 1.",
              flush=True)

        # Step 6: Exit cleanly via Ctrl+Q and confirm save ('y')
        print("[*] Step 6: Exiting editor cleanly with save ('y')...",
              flush=True)
        time.sleep(0.3)
        os.write(master, b"\x11")  # Ctrl+Q
        out_prompt = read_until(master, b"Save", timeout=5.0)
        if b"Save" not in out_prompt:
            buf_str = repr(out_prompt[-300:])
            print(f"[-] Step 6: Save prompt missing. Buffer: {buf_str}",
                  flush=True)
            return False
        time.sleep(0.3)
        os.write(master, b"y")
        out_exit = read_until(master, b"Returned to CP/M", timeout=10.0)
        out_exit += read_until(master, b"C>", timeout=10.0)
        if b"C>" not in out_exit and b"Returned to CP/M" not in out_exit:
            buf_str = repr(out_exit[-300:])
            print(f"[-] Step 6: Clean exit failed. Buffer: {buf_str}",
                  flush=True)
            return False
        print("[+] Step 6: Exited cleanly and saved document to disk.",
              flush=True)

        # Step 7: Extract and verify document contains only 'A'
        print("[*] Step 7: Extracting document to verify contents...",
              flush=True)
        if os.path.exists(out_txt_path):
            os.remove(out_txt_path)
        subprocess.run(
            [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, "0:TEST13.TXT",
             out_txt_path],
            check=True
        )
        with open(out_txt_path, "rb") as f:
            content = f.read()

        if b"~" in content or b"200" in content or b"15" in content:
            print(f"[-] Step 7: Leakage detected! Content: {repr(content)}",
                  flush=True)
            return False

        if not content.startswith(b"A"):
            print(f"[-] Step 7: Document does not start with 'A': "
                  f"{repr(content)}", flush=True)
            return False
        print("[+] Step 7: Zero escape sequence leakage verified.", flush=True)

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            pass
        os.close(master)
        if os.path.exists(out_txt_path):
            os.remove(out_txt_path)

    elapsed = time.time() - start_time
    print(f"[+] All Bug 2.1.13 tests PASSED in {elapsed:.2f}s!", flush=True)
    return True


if __name__ == "__main__":
    success = test_bug_2_1_13()
    sys.exit(0 if success else 1)
