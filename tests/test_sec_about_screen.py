#!/usr/bin/env python3
"""Validation test for Bugs 2.8.6 & 2.8.12: About Screen Layout in SEC.COM.

Verifies that show_about_screen() adopts the canonical 9-line centered layout
from docs/UI_UX_DESIGN.md §7.12 & §15.2, eliminates the misleading '(Linux)'
banner on CP/M, displays 'version 1.1.3 (2026-10-17) (C)', renders
'Google Antigravity 2.23.0 & Gemini 4 Argon Medium', includes the blank row
between AI attribution and MIT License, and centers each line per §15.2.2.
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


def read_until(master, target, timeout=10.0):
    buf = b""
    deadline = time.time() + timeout
    while time.time() < deadline:
        r, _, _ = select.select([master], [], [], 0.05)
        if r:
            try:
                chunk = os.read(master, 4096)
                if not chunk:
                    break
                buf += chunk
                if target in buf:
                    break
            except OSError:
                break
    return buf


def test_sec_about_screen():
    start_time = time.time()
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sec_bin = os.path.join(repo_root, "SEC.COM")
    ui_render_src = os.path.join(repo_root, "src", "core", "ui_render.c")
    sec_cpm_src = os.path.join(repo_root, "src", "sec_cpm.c")

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

    # Step 2: Verify "(Linux)" banner is eliminated from About screen
    print("[*] Step 2: Verifying '(Linux)' is absent from About screen...",
          flush=True)
    with open(ui_render_src, "r") as f:
        src_text = f.read()

    about_fn_idx = src_text.find("void show_about_screen(void)")
    if about_fn_idx == -1:
        print("[-] Step 2: show_about_screen() not found in ui_render.c.",
              flush=True)
        return False

    about_fn_body = src_text[about_fn_idx:about_fn_idx + 1000]
    if "(Linux)" in about_fn_body:
        print("[-] Step 2: Found '(Linux)' in show_about_screen().",
              flush=True)
        return False
    print("[+] Step 2: Misleading '(Linux)' tag eliminated from About screen.",
          flush=True)

    # Step 3: Verify canonical C version string present in SEC.COM and sec_cpm.c
    print("[*] Step 3: Verifying 'version 1.1.3 (2026-10-17) (C)'...",
          flush=True)
    expected_version = b"version 1.1.3 (2026-10-17) (C)"
    if expected_version not in binary_data:
        print("[-] Step 3: Canonical version string missing from SEC.COM.",
              flush=True)
        return False
    with open(sec_cpm_src, "r") as f:
        sec_cpm_text = f.read()
    if "(v1.1.3)" not in sec_cpm_text:
        print("[-] Step 3: '(v1.1.3)' missing from src/sec_cpm.c.",
              flush=True)
        return False
    print("[+] Step 3: Canonical C language version string verified.",
          flush=True)

    # Step 4: Verify author and open-source credits in SEC.COM
    print("[*] Step 4: Verifying author and open-source credits...",
          flush=True)
    required_credits = [
        b"by Dean Jenkins",
        b"Google Antigravity 2.23.0 & Gemini 4 Argon Medium",
        b"Open source software under the MIT License",
        b"Press any key to continue",
    ]
    missing = [c for c in required_credits if c not in binary_data]
    if missing:
        print(f"[-] Step 4: Missing credits from SEC.COM binary: {missing}",
              flush=True)
        return False
    print("[+] Step 4: All author and open-source credits verified.",
          flush=True)

    # Step 5: Verify live SEC.COM About screen layout & centering on RomWBW
    print("[*] Step 5: Verifying live SEC.COM About screen on RomWBW...",
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
            print(f"[-] Step 5: Boot prompt timeout. "
                  f"Buffer: {repr(out_boot[-300:])}", flush=True)
            return False
        time.sleep(0.3)
        os.write(master, b"c\r")
        out_b = read_until(master, b"B>", timeout=10.0)
        if b"B>" not in out_b:
            print(f"[-] Step 5: B> prompt timeout. "
                  f"Buffer: {repr(out_b[-300:])}", flush=True)
            return False
        time.sleep(0.3)
        os.write(master, b"c:\r")
        read_until(master, b"C>", timeout=10.0)
        time.sleep(0.3)
        os.write(master, b"sec\r")
        read_until(master, b"Col 0", timeout=25.0)
        time.sleep(0.3)

        os.write(master, b"a")
        out_about = read_until(
            master, b"Press any key to continue", timeout=10.0
        )
        time.sleep(0.2)
        out_about += read_until(master, b"Col 0", timeout=2.0)

        # In 80x24 with content_width=48 (left_col=17, 15 spaces after '~'):
        # Row 8:  15 + 15 = 30 spaces after '~' -> "SE - Screen Editor"
        # Row 9:  15 +  9 = 24 spaces after '~' -> "version 1.1.3 ..."
        # Row 10: 15 + 17 = 32 spaces after '~' -> "by Dean Jenkins"
        # Row 11: blank '~' row (\x1b[11;1H~\x1b[K)
        # Row 12: 15 +  0 = 15 spaces after '~' -> "Google Antigravity ..."
        # Row 13: blank '~' row (\x1b[13;1H~\x1b[K)
        # Row 14: 15 +  3 = 18 spaces after '~' -> "Open source software..."
        # Row 15: blank '~' row (\x1b[15;1H~\x1b[K)
        # Row 16: 15 + 12 = 27 spaces after '~' -> "Press any key..."
        expected_rows = [
            b"\x1b[8;17H               SE - Screen Editor",
            b"\x1b[9;17H         version 1.1.3 (2026-10-17) (C)",
            b"\x1b[10;17H                 by Dean Jenkins",
            b"\x1b[11;1H~\x1b[K",
            b"\x1b[12;17HGoogle Antigravity 2.23.0 & Gemini 4 Argon Medium",
            b"\x1b[13;1H~\x1b[K",
            b"\x1b[14;17H   Open source software under the MIT License",
            b"\x1b[15;1H~\x1b[K",
            b"\x1b[16;17H            Press any key to continue",
        ]
        for exp in expected_rows:
            if exp not in out_about:
                print(f"[-] Step 5: Missing expected About row {repr(exp)}. "
                      f"Buffer: {repr(out_about[-400:])}", flush=True)
                return False

        os.write(master, b" ")
        read_until(master, b"for about", timeout=10.0)
        time.sleep(0.2)
        os.write(master, b"q")
        out_quit = read_until(master, b"C>", timeout=10.0)
        if b"C>" not in out_quit:
            print(f"[-] Step 5: Clean exit failed. "
                  f"Buffer: {repr(out_quit[-300:])}", flush=True)
            return False
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2.0)
        except subprocess.TimeoutExpired:
            proc.kill()
        os.close(master)

    print("[+] Step 5: Live RomWBW About screen layout & centering verified.",
          flush=True)

    elapsed = time.time() - start_time
    print(f"[+] All SEC About Screen tests PASSED in {elapsed:.2f}s!",
          flush=True)
    return True


if __name__ == "__main__":
    if not test_sec_about_screen():
        sys.exit(1)
