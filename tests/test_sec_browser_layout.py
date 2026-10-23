#!/usr/bin/env python3
"""Validation test for Bug 2.8.13: SEC.COM Directory Browser Layout & UX.

Verifies that src/core/ui_browser.c conforms to docs/UI_UX_DESIGN.md
Sections 7.5-7.9 and 15.3:
  1. Dynamic vertical centering (DIR_TOP_PAD_COUNT, FileRows, PromptRows).
  2. 78-column '=' and '-' rules and 15-column file grid cells in 80x24.
  3. Inverse video prompt label, '<Drive><User>:' preload, and '[TAB]' hint.
  4. Single-Page Invariant (no '[Page 1/1]' row) and canonical guide row.
  5. '[TAB]' Highlight Bar Navigation Mode, drive/user switching, and filter.
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


def drain_pty(master, duration=0.4):
    buf = b""
    deadline = time.time() + duration
    while time.time() < deadline:
        r, _, _ = select.select([master], [], [], 0.05)
        if r:
            try:
                chunk = os.read(master, 4096)
                if not chunk:
                    break
                buf += chunk
            except OSError:
                break
    return buf


def test_sec_browser_layout():
    start_time = time.time()
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sec_bin = os.path.join(repo_root, "SEC.COM")

    # Step 1: Compile SEC.COM and audit CCP headroom
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
    print("[+] Step 1: SEC.COM compiled and CCP audit passed.", flush=True)

    # Step 2: Inject SEC.COM and 2.TXT onto workspace disk image
    print("[*] Step 2: Injecting SEC.COM into workspace disk image...",
          flush=True)
    emu_bin, rom_file, img_file, cpmcp_bin, cpmrm_bin = find_emu_paths(
        repo_root
    )
    txt_bin = os.path.join(repo_root, "2.TXT")
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file,
         "0:SEC.COM", "0:SE.CFG", "0:2.TXT"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, sec_bin, "0:SEC.COM"],
        check=True,
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, txt_bin, "0:2.TXT"],
        check=True,
    )
    print("[+] Step 2: SEC.COM injected onto Drive C: user 0.", flush=True)

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
        # Step 3: Boot RomWBW and launch SEC.COM
        print("[*] Step 3: Booting RomWBW and launching SEC.COM...",
              flush=True)
        out_boot = read_until(master, b"Boot [H=Help]:", timeout=10.0)
        if b"Boot [H=Help]:" not in out_boot:
            print(f"[-] Step 3: Boot prompt timeout. "
                  f"Buffer: {repr(out_boot[-300:])}", flush=True)
            return False
        time.sleep(0.3)
        os.write(master, b"c\r")
        out_b = read_until(master, b"B>", timeout=10.0)
        if b"B>" not in out_b:
            print(f"[-] Step 3: B> prompt timeout. "
                  f"Buffer: {repr(out_b[-300:])}", flush=True)
            return False
        time.sleep(0.3)
        os.write(master, b"c:\r")
        read_until(master, b"C>", timeout=10.0)
        time.sleep(0.3)
        os.write(master, b"sec\r")
        out_splash = read_until(master, b"Col 0", timeout=25.0)
        if b"Col 0" not in out_splash:
            print(f"[-] Step 3: SEC.COM splash timeout. "
                  f"Buffer: {repr(out_splash[-300:])}", flush=True)
            return False
        time.sleep(0.3)
        print("[+] Step 3: SEC.COM launched and splash screen ready.",
              flush=True)

        # Step 4: Open File Browser ('o') and verify centering, rules, prompt
        print("[*] Step 4: Opening File Browser ('o') and auditing layout...",
              flush=True)
        os.write(master, b"o")
        out_open = read_until(master, b"[TAB]=Select File", timeout=15.0)
        out_open += drain_pty(master, 0.5)

        eq_rule = b"~" + (b"=" * 78) + b"\x1b[K"
        dash_rule = b"~" + (b"-" * 78) + b"\x1b[K"
        if eq_rule not in out_open:
            print(f"[-] Step 4: Missing 78-col '=' rule. "
                  f"Buffer: {repr(out_open[-400:])}", flush=True)
            return False
        if dash_rule not in out_open:
            print(f"[-] Step 4: Missing 78-col '-' rule. "
                  f"Buffer: {repr(out_open[-400:])}", flush=True)
            return False
        if b"OPEN FILE (DIRECTORY - DRIVE C:)" not in out_open:
            print(f"[-] Step 4: Missing centered OPEN FILE title. "
                  f"Buffer: {repr(out_open[:500])}", flush=True)
            return False
        if b"\x1b[1;1H~\x1b[K" not in out_open:
            print(f"[-] Step 4: Missing top padding '~' row at Row 1. "
                  f"Buffer: {repr(out_open[:500])}", flush=True)
            return False
        if (
            b"[Page 1/" not in out_open
            or b"]  <PgUp>/<PgDn>=Page" not in out_open
        ):
            print(
                "[-] Step 4: Missing '[Page 1/N]  <PgUp>/<PgDn>=Page' row. "
                f"Buffer: {repr(out_open[-400:])}",
                flush=True,
            )
            return False
        expected_guide = (
            b"~  [ESC]=Cancel  Enter [d:][u:][pattern] to list "
            b"(e.g. B:, C1:, 1C:, *.TXT)"
        )
        if expected_guide not in out_open:
            print(f"[-] Step 4: Missing canonical guide hint. "
                  f"Buffer: {repr(out_open[-400:])}", flush=True)
            return False
        expected_prompt = (
            b"~  \x1b[7mEnter filename to open:\x1b[0m ["
        )
        if expected_prompt not in out_open:
            print(f"[-] Step 4: Missing inverse prompt label. "
                  f"Buffer: {repr(out_open[-400:])}", flush=True)
            return False
        if b"C0:                 " not in out_open:
            print(f"[-] Step 4: Missing 'C0:' preload in 20-char box. "
                  f"Buffer: {repr(out_open[-400:])}", flush=True)
            return False
        if b"]  [TAB]=Select File          " not in out_open:
            print(f"[-] Step 4: Missing '[TAB]=Select File' mode hint. "
                  f"Buffer: {repr(out_open[-400:])}", flush=True)
            return False
        if b"\x1b[7m2.TXT" in out_open:
            print(f"[-] Step 4: Grid cell highlighted in text input mode. "
                  f"Buffer: {repr(out_open[:500])}", flush=True)
            return False
        if b"2.TXT          " not in out_open:
            print(f"[-] Step 4: Missing 15-col padded '2.TXT          ' cell."
                  f" Buffer: {repr(out_open[:600])}", flush=True)
            return False
        print("[+] Step 4: Centering, 78-col rules, 15-col grid, inverse "
              "prompt, 'C0:' preload & multi-page indicator verified.",
              flush=True)

        # Step 5: Test [TAB] Highlight Bar Navigation Mode
        print("[*] Step 5: Testing [TAB] Highlight Bar Navigation Mode...",
              flush=True)
        os.write(master, b"\t")
        out_tab1 = read_until(
            master, b"]  [TAB]=Edit Name  [Enter]=OK", timeout=10.0
        )
        out_tab1 += drain_pty(master, 0.3)
        if b"\x1b[?25l" not in out_tab1:
            print(f"[-] Step 5: Cursor not hidden on TAB highlight mode. "
                  f"Buffer: {repr(out_tab1[-300:])}", flush=True)
            return False
        if b"\x1b[7m2.TXT       \x1b[0m" not in out_tab1:
            print(f"[-] Step 5: First cell '2.TXT' not highlighted (12-char). "
                  f"Buffer: {repr(out_tab1[-300:])}", flush=True)
            return False
        if b"C0:2.TXT            " not in out_tab1:
            print(f"[-] Step 5: Input box not updated to 'C0:2.TXT'. "
                  f"Buffer: {repr(out_tab1[-300:])}", flush=True)
            return False

        # Navigate right with Right Arrow
        os.write(master, b"\x1b[C")
        out_right = drain_pty(master, 0.5)
        if b"\x1b[0m" not in out_right or b"C0:" not in out_right:
            print(f"[-] Step 5: Right arrow highlight navigation failed. "
                  f"Buffer: {repr(out_right[-300:])}", flush=True)
            return False

        # Press TAB again to return to Text Input Mode
        os.write(master, b"\t")
        out_tab2 = read_until(master, b"[TAB]=Select File", timeout=10.0)
        out_tab2 += drain_pty(master, 0.3)
        if b"\x1b[?25h" not in out_tab2:
            print(f"[-] Step 5: Cursor not restored on second TAB. "
                  f"Buffer: {repr(out_tab2[-300:])}", flush=True)
            return False
        print("[+] Step 5: [TAB] Highlight Bar Mode toggle & arrow navigation "
              "verified.", flush=True)

        # Step 6: Test user area switch (C1: empty) and wildcard filter (*.TXT)
        print("[*] Step 6: Testing user switch (C1:), filter (*.TXT) & "
              "Single-Page Invariant...", flush=True)
        os.write(master, b"\x7f" * 20 + b"C1:\r")
        out_c1 = read_until(
            master, b"[No files found on current drive]", timeout=15.0
        )
        out_c1 += drain_pty(master, 0.4)
        if b"OPEN FILE (DIRECTORY - DRIVE C1:)" not in out_c1:
            print(f"[-] Step 6: Missing 'DRIVE C1:' title after user switch. "
                  f"Buffer: {repr(out_c1[-400:])}", flush=True)
            return False
        if b"[Page " in out_c1:
            print(f"[-] Step 6: Single-Page Invariant violated on C1:. "
                  f"Buffer: {repr(out_c1[-400:])}", flush=True)
            return False
        # Empty drive: FileRows=2, PromptRows=3 -> BodyRows=5 -> top_pad=7
        # So top '=' border is at Row 8 (\x1b[8;1H~===...)
        if b"\x1b[8;1H~" + (b"=" * 78) not in out_c1:
            print(f"[-] Step 6: Empty drive top '=' border not centered at "
                  f"Row 8. Buffer: {repr(out_c1[:400])}", flush=True)
            return False

        # Filter C0:*.TXT
        os.write(master, b"\x7f" * 10 + b"C0:*.TXT\r")
        out_flt = read_until(
            master, b"OPEN FILE (DIRECTORY - DRIVE C: [*.TXT])", timeout=15.0
        )
        out_flt += drain_pty(master, 0.5)
        if b"2.TXT" not in out_flt or b"SEC.COM" in out_flt:
            print(f"[-] Step 6: Wildcard filter '*.TXT' did not filter grid. "
                  f"Buffer: {repr(out_flt[-400:])}", flush=True)
            return False
        if b"[Page " in out_flt:
            print(f"[-] Step 6: Single-Page Invariant violated on C0:*.TXT. "
                  f"Buffer: {repr(out_flt[-400:])}", flush=True)
            return False
        print("[+] Step 6: User switch (C1:), wildcard filter (C0:*.TXT), "
              "and Single-Page Invariant verified.", flush=True)

        # Step 7: Select 2.TXT via TAB+Enter, verify Save Browser & clean exit
        print("[*] Step 7: Selecting 2.TXT via TAB+Enter and checking Save "
              "Browser...", flush=True)
        os.write(master, b"\t")
        read_until(master, b"[TAB]=Edit Name  [Enter]=OK", timeout=10.0)
        os.write(master, b"\r")
        out_load = read_until(master, b"| C:2.TXT", timeout=15.0)
        out_load += drain_pty(master, 0.4)
        if b"| C:2.TXT" not in out_load:
            print(f"[-] Step 7: Failed to open 2.TXT via TAB+Enter. "
                  f"Buffer: {repr(out_load[-400:])}", flush=True)
            return False

        # Press Ctrl+S (\x13) to open Save File Browser
        os.write(master, b"\x13")
        out_save = read_until(master, b"[^F]=Toggle Format", timeout=15.0)
        out_save += drain_pty(master, 0.5)
        if b"SAVE FILE (DIRECTORY - DRIVE C:" not in out_save:
            print(f"[-] Step 7: Missing SAVE FILE header. "
                  f"Buffer: {repr(out_save[-400:])}", flush=True)
            return False
        if b"\x1b[7mEnter filename to save:\x1b[0m [" not in out_save:
            print(f"[-] Step 7: Missing inverse save prompt label. "
                  f"Buffer: {repr(out_save[-400:])}", flush=True)
            return False
        if b"C0:2.TXT            " not in out_save:
            print(f"[-] Step 7: Save box not preloaded with 'C0:2.TXT'. "
                  f"Buffer: {repr(out_save[-400:])}", flush=True)
            return False

        # Cancel Save Browser with ESC, then quit SEC.COM with Ctrl+Q
        os.write(master, b"\x1b")
        read_until(master, b"| C:2.TXT", timeout=10.0)
        time.sleep(0.2)
        os.write(master, b"\x11")
        out_quit = read_until(master, b"C>", timeout=10.0)
        if b"C>" not in out_quit:
            print(f"[-] Step 7: Clean exit to C> failed. "
                  f"Buffer: {repr(out_quit[-300:])}", flush=True)
            return False
        print("[+] Step 7: File open via TAB+Enter, Save Browser preload, "
              "and clean exit verified.", flush=True)
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2.0)
        except subprocess.TimeoutExpired:
            proc.kill()
        os.close(master)

    elapsed = time.time() - start_time
    print(f"[+] All SEC Browser Layout tests PASSED in {elapsed:.2f}s!",
          flush=True)
    return True


if __name__ == "__main__":
    if not test_sec_browser_layout():
        sys.exit(1)
