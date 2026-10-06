#!/usr/bin/env python3
"""
Automated Test for Bug 2.29:
Plugin Configuration Pop-ups Omit Toggle Hotkeys and Delimiters.

Verifies:
  1. Launch SE and enter Plugin Manager ('p').
  2. Open Word Count configuration pop-up on Slot 0 ('c').
  3. Verify option labels use bracketed notation [1] and [2], closing
     brackets are horizontally aligned, and footer documents toggle
     keys [1-2]=Toggle Option.
  4. Dismiss via ESC and move down to Slot 2 (Beautify).
  5. Open Beautify configuration pop-up ('c').
  6. Verify option labels use bracketed notation [1]..[4] and footer
     documents toggle keys [1-4]=Toggle Option.
  7. Verify clean dismissal via ESC and clean exit to CP/M.
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
    cpmcp_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp"
    )
    cpmrm_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm"
    )

    return (
        repo_root, emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin
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


def setup_disk_files(img_file, se_bin, cpmcp_bin, cpmrm_bin, repo_root):
    if os.path.isfile(cpmrm_bin):
        for fname in ["0:SE.COM", "0:se.com", "0:BEAUTIFY.PRL",
                      "0:beautify.prl", "0:WORDCNT.OVL", "0:wordcnt.ovl",
                      "0:PLUGIN.PRL", "0:plugin.prl"]:
            subprocess.run(
                [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, fname],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )

    if os.path.isfile(cpmcp_bin):
        if os.path.isfile(se_bin):
            subprocess.run(
                [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, se_bin, "0:SE.COM"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
        wordcnt_ovl = os.path.join(repo_root, "plugins", "WORDCNT.OVL")
        if os.path.isfile(wordcnt_ovl):
            subprocess.run(
                [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, wordcnt_ovl,
                 "0:WORDCNT.OVL"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
        beautify_prl = os.path.join(repo_root, "plugins", "BEAUTIFY.PRL")
        if os.path.isfile(beautify_prl):
            subprocess.run(
                [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, beautify_prl,
                 "0:BEAUTIFY.PRL"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
        plugin_prl = os.path.join(repo_root, "plugins", "PLUGIN.PRL")
        if os.path.isfile(plugin_prl):
            subprocess.run(
                [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, plugin_prl,
                 "0:PLUGIN.PRL"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
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


def run_test():
    paths = find_paths()
    repo_root, emu_bin, rom_file, img_file, se_bin, cpmcp, cpmrm = paths

    setup_disk_files(img_file, se_bin, cpmcp, cpmrm, repo_root)

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
        time.sleep(0.3)
        os.write(master, b"se\r")
        out = read_until(master, b"for plugins", timeout=35.0)
        if b"for plugins" not in out:
            print(f"[-] Splash screen failed to display: {out[-200:]}")
            return False
        drain_all(master)

        # Enter Plugin Manager via 'p'
        print("[*] Entering Plugin Manager with 'p'...", flush=True)
        time.sleep(0.3)
        os.write(master, b"p")
        out_pm = read_until(master, b"Plugin Manager", timeout=12.0)
        if b"Plugin Manager" not in out_pm:
            print(f"[-] Plugin Manager screen failed to display: {out_pm}")
            return False
        time.sleep(0.3)
        drain_all(master)

        # -------------------------------------------------------------
        # Part 1: Word Count Configuration Pop-up (Slot 0)
        # -------------------------------------------------------------
        print("[*] Opening Word Count config pop-up on Slot 0...",
              flush=True)
        time.sleep(0.2)
        os.write(master, b"c")
        out_wc = read_until(master, b"Save & Exit", timeout=8.0)
        out_wc += drain_all(master)

        if b"Word Count Configuration" not in out_wc:
            print(f"[-] Word Count config dialog missing: {out_wc}")
            return False

        expected_wc_l1 = b"| [1] Count Blank Lines  : [YES]     |"
        expected_wc_l2 = b"| [2] Count Whitespace   : [YES]     |"
        for lbl in [expected_wc_l1, expected_wc_l2]:
            if lbl not in out_wc:
                print(f"[-] Word Count option label missing or misaligned: "
                      f"{lbl}")
                return False
            print(f"[+] Verified Word Count label: {repr(lbl)} "
                  f"(len={len(lbl)})")

        expected_wc_toggle = b"|        [1-2]=Toggle Option         |"
        if expected_wc_toggle not in out_wc:
            print(f"[-] Word Count toggle footer missing: {out_wc}")
            return False
        print("[+] Verified Word Count footer toggle: "
              f"{repr(expected_wc_toggle)}")

        # Dismiss Word Count config via ESC
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"Plugin Manager", timeout=8.0)
        drain_all(master)

        # -------------------------------------------------------------
        # Part 2: Beautify Configuration Pop-up (Slot 2)
        # -------------------------------------------------------------
        print("[*] Navigating to Slot 2 (Beautify)...", flush=True)
        time.sleep(0.2)
        os.write(master, b"\x1b[B\x1b[B")  # Down arrow twice to Slot 2
        time.sleep(0.3)
        drain_all(master)

        print("[*] Opening Beautify config pop-up with 'c'...", flush=True)
        os.write(master, b"c")
        out_bt = read_until(master, b"Save & Exit", timeout=8.0)
        out_bt += drain_all(master)

        if b"Z80 Beautifier Configuration" not in out_bt:
            print(f"[-] Beautify config dialog missing: {out_bt}")
            return False

        expected_bt_l1 = b"| [1] Columns   : [Standard (9/17)]  |"
        expected_bt_l2 = b"| [2] Mnemonics : [UPPERCASE      ]  |"
        expected_bt_l3 = b"| [3] Registers : [UPPERCASE      ]  |"
        expected_bt_l4 = b"| [4] Animation : [ON (Real-Time) ]  |"

        for lbl in [expected_bt_l1, expected_bt_l2, expected_bt_l3,
                    expected_bt_l4]:
            if lbl not in out_bt:
                print(f"[-] Beautify option label missing or misaligned: {lbl}")
                return False
            print(f"[+] Verified Beautify label: {repr(lbl)} (len={len(lbl)})")

        expected_bt_toggle = b"|        [1-4]=Toggle Option         |"
        if expected_bt_toggle not in out_bt:
            print(f"[-] Beautify toggle option footer missing: {out_bt}")
            return False
        print("[+] Verified Beautify footer toggle: "
              f"{repr(expected_bt_toggle)} (len={len(expected_bt_toggle)})")

        # Cancel config via ESC
        print("[*] Cancelling config dialog via ESC...", flush=True)
        time.sleep(0.2)
        os.write(master, b"\x1b")
        read_until(master, b"Plugin Manager", timeout=8.0)
        drain_all(master)

        # Exit Plugin Manager via 'q'
        time.sleep(0.2)
        os.write(master, b"q")
        read_until(master, b"for plugins", timeout=8.0)
        drain_all(master)

        # Exit SE to CP/M via 'q'
        time.sleep(0.2)
        os.write(master, b"q")
        out_cpm = read_until(master, b"C>", timeout=6.0)
        if b"C>" not in out_cpm:
            print(f"[-] Clean exit to CP/M failed: {out_cpm}")
            return False

        print("[+] Bug 2.29 verification PASSED: Both Word Count and Beautify "
              "configuration dialogs conform to UI/UX specifications.")
        return True
    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            proc.kill()
        try:
            os.close(master)
        except OSError:
            pass


if __name__ == "__main__":
    success = run_test()
    sys.exit(0 if success else 1)
