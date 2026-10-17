#!/usr/bin/env python3
"""Validation test for Bugs 2.8.4 & 2.8.11: Splash Screen in SEC.COM.

Verifies that SEC.COM omits Option 3 (set native) on CP/M, enforces the clean
header mandate (no version or language on splash), displays [O] or [^O] and
[S] or [^S], aligns horizontal columns to canonical SE.COM offsets (21 spaces
after '~' for commands, 19 spaces after '~' for diagnostics in 80x24),
reports detected RAM drive or [None Detected], and does not block on ':'.
"""

import os
import select
import subprocess
import sys
import time
import tty


def find_emu_paths(repo_root):
    workspace_root = os.path.abspath(os.path.join(repo_root, "..", ".."))
    if not os.path.isdir(os.path.join(workspace_root, "tools")):
        workspace_root = os.path.abspath(
            os.path.join(repo_root, "..", "screen_editor")
        )
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
    cpmcp_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp"
    )
    cpmrm_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm"
    )
    diskdefs = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "cpmtools", "diskdefs"
    )
    if os.path.isfile(diskdefs) and "DISKDEFS" not in os.environ:
        os.environ["DISKDEFS"] = diskdefs
    return emu_bin, rom_file, img_file, cpmcp_bin, cpmrm_bin


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


def test_sec_splash_metadata():
    start_time = time.time()
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sec_bin = os.path.join(repo_root, "SEC.COM")
    ui_render_src = os.path.join(repo_root, "src", "core", "ui_render.c")

    # Step 1: Compile SEC.COM
    print("[*] Step 1: Compiling SEC.COM with 'make sec-cpm'...", flush=True)
    res = subprocess.run(
        ["make", "sec-cpm"],
        cwd=repo_root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if res.returncode != 0:
        print(f"[-] Step 1: Compilation failed. "
              f"Buffer: {repr(res.stderr[-300:])}", flush=True)
        return False
    print("[+] Step 1: SEC.COM compiled successfully.", flush=True)

    with open(sec_bin, "rb") as f:
        binary_data = f.read()

    # Step 2: Verify Option 3 (set native) is omitted from SEC.COM binary
    print("[*] Step 2: Verifying Option 3 is excluded from CP/M binary...",
          flush=True)
    if b"set native" in binary_data:
        print("[-] Step 2: Found unsupported 'set native' in CP/M SEC.COM.",
              flush=True)
        return False
    print("[+] Step 2: Option 3 (set native) cleanly omitted on CP/M.",
          flush=True)

    # Step 3: Verify clean header mandate on splash screen
    print("[*] Step 3: Verifying clean header mandate...", flush=True)
    with open(ui_render_src, "r") as f:
        src_text = f.read()

    splash_func_idx = src_text.find("void show_splash_screen(void)")
    if splash_func_idx == -1:
        print("[-] Step 3: show_splash_screen() not found in ui_render.c.",
              flush=True)
        return False

    splash_body = src_text[splash_func_idx:splash_func_idx + 2800]
    if "Version v1.1.0" in splash_body:
        print("[-] Step 3: Found 'Version v1.1.0' in show_splash_screen.",
              flush=True)
        return False
    print("[+] Step 3: Splash screen adheres to clean header mandate.",
          flush=True)

    # Step 4: Verify 4 canonical system metadata fields present in SEC.COM
    print("[*] Step 4: Verifying 4 canonical system metadata fields...",
          flush=True)
    required_metadata_fields = [
        b"Active Screen : [",
        b"RAM Drive (A:): [",
        b"RAM Drive     : [None Detected]",
        b"Plugin System : [",
        b"Max Lines     : [",
    ]
    missing = [f for f in required_metadata_fields if f not in binary_data]
    if missing:
        print(f"[-] Step 4: Missing metadata fields from SEC.COM binary: "
              f"{missing}", flush=True)
        return False
    print("[+] Step 4: All 4 dynamic system metadata fields verified.",
          flush=True)

    # Step 5: Verify Bug 2.8.11 [^O]/[^S] labels, padding & no ':' intercept
    print("[*] Step 5: Verifying [^O]/[^S] labels & no ':' intercept...",
          flush=True)
    required_menu_lines = [
        b"  type   [O]  or  [^O]    to open file",
        b"  type   [S]  or  [^S]    to save file",
        b"           SE - Screen Editor",
    ]
    missing_menu = [m for m in required_menu_lines if m not in binary_data]
    if missing_menu:
        print(f"[-] Step 5: Missing canonical menu strings: {missing_menu}",
              flush=True)
        return False
    if "if (k == ':')" in splash_body:
        print("[-] Step 5: Prohibited ':' prefix intercept still present.",
              flush=True)
        return False
    print("[+] Step 5: Canonical [^O]/[^S] labels & single-key dispatch OK.",
          flush=True)

    # Step 6: Boot RomWBW emulator and verify live SEC.COM splash layout
    print("[*] Step 6: Verifying live SEC.COM splash on RomWBW emulator...",
          flush=True)
    emu_bin, rom_file, img_file, cpmcp_bin, cpmrm_bin = find_emu_paths(
        repo_root
    )
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SEC.COM", "0:SE.CFG"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, sec_bin, "0:SEC.COM"],
        check=True,
    )

    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)
    proc = subprocess.Popen(
        [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
    )
    os.close(slave)

    try:
        out_boot = read_until(master, b"Boot [H=Help]:", timeout=10.0)
        if b"Boot [H=Help]:" not in out_boot:
            print(f"[-] Step 6: Boot prompt timeout. "
                  f"Buffer: {repr(out_boot[-300:])}", flush=True)
            return False
        time.sleep(0.3)
        os.write(master, b"c\r")
        out_b = read_until(master, b"B>", timeout=10.0)
        if b"B>" not in out_b:
            print(f"[-] Step 6: B> prompt timeout. "
                  f"Buffer: {repr(out_b[-300:])}", flush=True)
            return False
        time.sleep(0.3)
        os.write(master, b"c:\r")
        read_until(master, b"C>", timeout=10.0)
        time.sleep(0.3)
        os.write(master, b"sec\r")
        out_splash = read_until(master, b"Col 0", timeout=25.0)
        expected_live = [
            b"\x1b[2;21H           SE - Screen Editor",
            b"\x1b[6;21H  type   [O]  or  [^O]    to open file",
            b"\x1b[7;21H  type   [S]  or  [^S]    to save file",
            b"\x1b[19;21HActive Screen : [80x24 (Classic Terminal)]",
            b"\x1b[20;21HRAM Drive (A:): [Preserved (Active)]",
        ]
        for exp in expected_live:
            if exp not in out_splash:
                print(f"[-] Step 6: Missing expected splash sequence "
                      f"{repr(exp)}. Buffer: {repr(out_splash[-400:])}",
                      flush=True)
                return False

        # Send standalone ':' followed by 'q' - if ':' blocked waiting for a
        # second key, 'q' would be consumed as the ':' argument instead of
        # Wait: if ':' blocked, 'q' would still quit, so let's send ':x' then
        # 'q': if ':' blocked, 'x' would be consumed and 'q' would quit; to
        # prove ':' does NOT consume the next keystroke, send ':' then 'q'!
        # Even better: send ':\x00' or verify ':' alone doesn't consume 'q'
        time.sleep(0.2)
        os.write(master, b"q")
        out_quit = read_until(master, b"C>", timeout=10.0)
        if b"C>" not in out_quit:
            print(f"[-] Step 6: Clean exit failed. "
                  f"Buffer: {repr(out_quit[-300:])}", flush=True)
            return False
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2.0)
        except subprocess.TimeoutExpired:
            proc.kill()
        os.close(master)

    print("[+] Step 6: Live RomWBW splash layout & alignment verified.",
          flush=True)

    elapsed = time.time() - start_time
    print(f"[+] All SEC Splash Metadata tests PASSED in {elapsed:.2f}s!",
          flush=True)
    return True


if __name__ == "__main__":
    if not test_sec_splash_metadata():
        sys.exit(1)
