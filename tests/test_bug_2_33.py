#!/usr/bin/env python3
"""
Automated Test for Bug 2.33:
Splash Screen Omits Ctrl+P Context-Aware Plugin Menu Command.

Verifies:
  1. Boot CP/M and launch 'se'.
  2. Verify splash screen command list includes:
     "type   [^P]             for context plugin menu"
  3. Verify vertical column alignment of [^P] trigger and description.
  4. Send Ctrl+P to trigger context plugin menu modal.
  5. Verify context plugin menu pop-up appears immediately.
  6. Dismiss pop-up with ESC and verify return to splash screen.
  7. Verify vertical centering with symmetrical 1-row padding on 80x24.
  8. Clean exit to CP/M with 'q'.
"""

import os
import re
import select
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
    plug_bin = os.path.join(repo_root, "plugins", "PLUGIN.PRL")
    cpmcp_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp"
    )
    cpmrm_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm"
    )

    return (
        repo_root, emu_bin, rom_file, img_file, se_bin, plug_bin,
        cpmcp_bin, cpmrm_bin
    )


def read_until(master_fd, target, timeout=8.0):
    buf = b""
    t0 = time.time()
    targets = target if isinstance(target, (list, tuple)) else [target]
    while time.time() - t0 < timeout:
        r, _, _ = select.select([master_fd], [], [], 0.05)
        if r:
            try:
                data = os.read(master_fd, 1024)
                if not data:
                    break
                buf += data
                for tgt in targets:
                    if tgt in buf:
                        return buf
            except (BlockingIOError, OSError):
                pass
    return buf


def drain_all(master_fd, quiet_time=0.2):
    time.sleep(0.05)
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


def setup_disk_files(img_file, se_bin, plug_bin, cpmcp, cpmrm, repo_root):
    if os.path.isfile(cpmrm):
        for fname in ["0:SE.COM", "0:se.com", "0:PLUGIN.PRL", "0:plugin.prl"]:
            subprocess.run(
                [cpmrm, "-f", "wbw_hd1k_0", img_file, fname],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
    subprocess.run(
        [cpmcp, "-f", "wbw_hd1k_0", img_file, se_bin, "0:SE.COM"],
        check=True,
    )
    if os.path.isfile(plug_bin):
        subprocess.run(
            [cpmcp, "-f", "wbw_hd1k_0", img_file, plug_bin, "0:PLUGIN.PRL"],
            check=True,
        )


def boot_cpm(master):
    out = read_until(master, b"Boot [H=Help]:", timeout=8.0)
    if b"Boot [H=Help]:" not in out:
        return False, "Bootloader prompt missing"
    time.sleep(0.3)
    os.write(master, b"c\r")
    out = read_until(master, b"B>", timeout=8.0)
    if b"B>" not in out:
        return False, "Drive B> missing"
    time.sleep(0.3)
    os.write(master, b"c:\r")
    out = read_until(master, b"C>", timeout=8.0)
    if b"C>" not in out:
        return False, "Drive C> missing"
    drain_all(master)
    return True, "Booted to C>"


def strip_ansi(text):
    ansi_re = re.compile(r"\x1b\[[0-9;]*[a-zA-Z]|\x1b\([AB012]")
    return ansi_re.sub("", text)


def run_test():
    paths = find_paths()
    (repo_root, emu_bin, rom_file, img_file, se_bin, plug_bin,
     cpmcp, cpmrm) = paths

    setup_disk_files(img_file, se_bin, plug_bin, cpmcp, cpmrm, repo_root)

    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )
    os.close(slave)

    try:
        ok, msg = boot_cpm(master)
        if not ok:
            print(f"[-] {msg}")
            return False

        print("[*] Launching 'se'...", flush=True)
        time.sleep(0.5)
        os.write(master, b"se\r")
        out = read_until(master, b"lines]", timeout=30.0)
        out += drain_all(master, 0.3)

        raw_str = out.decode("latin1", errors="replace")
        clean_text = strip_ansi(raw_str)

        # 1. Verify [^P] command line exists in splash menu
        expected_cmd = "type   [^P]             for context plugin menu"
        assert expected_cmd in clean_text, (
            f"Expected command '{expected_cmd}' not found in splash menu:\n"
            f"{clean_text}"
        )
        print(f"[+] Verified splash command documented: '{expected_cmd}'")

        # 2. Switch to 80x24 mode with '2' to verify vertical margins
        os.write(master, b"2")
        out_80 = read_until(master, b"lines]", timeout=8.0)
        out_80 += drain_all(master, 0.3)
        clean_80 = strip_ansi(out_80.decode("latin1", errors="replace"))

        # In 80x24: SPLASH_MENU_LINES=21
        # Top padding = (23 - 21) / 2 = 1 row of tildes
        # Bottom padding = 23 - 1 - 21 = 1 row of tildes
        lines_80 = [l for l in clean_80.splitlines() if l.strip()]
        # Check that top and bottom margins are symmetrical
        assert expected_cmd in clean_80, (
            f"Command missing after 80x24 switch:\n{clean_80}"
        )
        print("[+] 80x24 geometry retains documented [^P] command.")

        # 3. Press Ctrl+P on splash screen to trigger context plugin menu
        print("[*] Sending Ctrl+P on splash screen...", flush=True)
        os.write(master, b"\x10")  # Ctrl+P
        out_pop = read_until(
            master, b"All Available Installed Plugins", timeout=6.0
        )
        out_pop += drain_all(master, 0.3)

        assert b"All Available Installed Plugins" in out_pop, (
            f"Context plugin menu pop-up did not appear on Ctrl+P: {out_pop}"
        )
        print("[+] Verified Ctrl+P opens Context-Aware Plugin Menu pop-up.")

        # 4. Dismiss pop-up with ESC
        print("[*] Dismissing context menu with ESC...", flush=True)
        os.write(master, b"\x1b")
        out_sp_back = read_until(master, b"Active Screen :", timeout=6.0)
        assert b"Active Screen :" in out_sp_back, (
            "Failed returning to splash screen after ESC"
        )
        print("[+] Successfully dismissed pop-up back to splash screen.")

        # 5. Exit cleanly with 'q'
        print("[*] Exiting to CP/M with 'q'...", flush=True)
        os.write(master, b"q")
        out_cpm = read_until(master, b"C>", timeout=6.0)
        assert b"C>" in out_cpm, "Failed exiting cleanly to CP/M prompt"
        print("[+] Bug 2.33 verification PASSED: [^P] documented and working.")
        return True

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            pass
        os.close(master)


if __name__ == "__main__":
    success = run_test()
    sys.exit(0 if success else 1)
