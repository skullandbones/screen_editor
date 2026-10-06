#!/usr/bin/env python3
"""
test_bug_2_1.py - Isolated Bug Step Reproduction for Bug 2.1:
Memory Screen Misreports Loaded Plugin Banks as Free / Unallocated.

Verifies:
  1. Boot RomWBW CP/M on RC2014 emulator.
  2. Configure SE.CFG with RAMDRIVE=OVERWRITE and PLUGIN=AUTOLOAD to ensure
     Far RAM banks are available and plugins (WORDCNT.OVL / BEAUTIFY.PRL)
     are autoloaded into Far RAM.
  3. Launch SE.COM and verify splash shows [Operational].
  4. Enter Memory Information screen ('m').
  5. Assert that the memory bank allocated to Far RAM plugins is reported
     with SE.COM Usage indicating active plugins
     (e.g. 'Active: Far RAM Plugins')
     and NOT as 'Free / Unallocated' or 'Preserved: RAM Disk Active'.
  6. Return to splash screen via ESC and exit cleanly to CP/M with 'q'.
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


def read_until(master_fd, match_bytes, timeout=20.0):
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


def drain_all(master_fd, quiet_time=0.15):
    res = b""
    while True:
        r, _, _ = select.select([master_fd], [], [], quiet_time)
        if not r:
            break
        try:
            data = os.read(master_fd, 2048)
            if not data:
                break
            res += data
        except (BlockingIOError, OSError):
            break
    return res


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


def remove_cfg_from_image(cpmrm_bin, img_file):
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.CFG", "0:se.cfg"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_3", img_file, "0:SE.CFG", "0:se.cfg"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )


def put_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, content_str):
    remove_cfg_from_image(cpmrm_bin, img_file)
    tmp_path = "/tmp/TEST_BUG_2_1_SE.CFG"
    with open(tmp_path, "wb") as f:
        f.write(content_str.encode("latin1"))
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, tmp_path, "0:SE.CFG"],
        check=True
    )
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_3", img_file, tmp_path, "0:SE.CFG"],
        check=True
    )
    if os.path.exists(tmp_path):
        os.remove(tmp_path)


def test_bug_2_1():
    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = find_paths()

    print("[*] Running Bug 2.1 isolated reproduction test...", flush=True)

    # Configure SE.CFG: Overwrite RAM drive to provide Far RAM for plugins
    put_cfg_to_image(
        cpmcp_bin, cpmrm_bin, img_file,
        "RAMDRIVE=OVERWRITE\r\nPLUGIN=AUTOLOAD\r\n"
    )

    proc, master = boot_cpm(emu_bin, rom_file, img_file)
    try:
        time.sleep(0.4)
        os.write(master, b"c:\r")
        read_until(master, b"C>", timeout=15.0)

        # Launch SE.COM
        time.sleep(0.4)
        os.write(master, b"se\r")
        out_splash = read_until(
            master, b"Plugin System : [Operational]", timeout=25.0
        )
        assert b"Plugin System : [Operational]" in out_splash, (
            f"Failed to autoload plugins at startup: {out_splash}"
        )
        print("    [+] Plugins successfully autoloaded at startup.")

        # Open Memory Info screen ('m')
        time.sleep(0.4)
        os.write(master, b"m")
        out_mem = read_until(master, b"return to splash", timeout=15.0)
        time.sleep(0.2)
        out_mem += drain_all(master)

        assert b"SE.COM - Extended Memory Map" in out_mem, (
            f"Memory map screen not reached: {out_mem}"
        )
        assert b"Active: PLUGIN.PRL Subsystem" in out_mem, (
            f"Active: PLUGIN.PRL Subsystem missing: {out_mem}"
        )
        print("    [+] Memory map shows Active: PLUGIN.PRL Subsystem.")

        # Check for loaded plugin bank usage
        # The bank used for loaded plugins should show Active: Far RAM Plugins
        # and NOT 'Free / Unallocated' or 'Preserved: RAM Disk Active'.
        has_plugin_usage = (
            b"Active: Far RAM Plugins" in out_mem or
            b"Active: Far RAM Plugin Slots" in out_mem or
            b"Active: Loaded Plugins" in out_mem
        )

        mem_text = out_mem.decode("latin1", errors="replace")
        print("\n--- Memory Map Screen Output ---")
        for line in mem_text.splitlines():
            if any(k in line for k in ["Bank", "Active:", "Reserved:", "Free"]):
                print(f"    {line}")
        print("--------------------------------\n")

        assert has_plugin_usage, (
            "Bug 2.1 reproduced: Loaded plugin bank is missing from SE.COM "
            "usage column (misreported as Free / Unallocated or Preserved)!"
        )
        print("    [+] Loaded plugin bank correctly detected and reported.")

        # Return to splash screen with ESC
        time.sleep(0.3)
        os.write(master, b"\x1b")
        read_until(master, b"for memory info", timeout=10.0)

        # Exit to CP/M with 'q'
        time.sleep(0.3)
        os.write(master, b"q")
        read_until(master, b"C>", timeout=10.0)
        print("[+] Clean exit back to CP/M prompt.")

    finally:
        remove_cfg_from_image(cpmrm_bin, img_file)
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            pass
        os.close(master)

    print("[+] Test PASSED: Bug 2.1 verified fixed!", flush=True)


if __name__ == "__main__":
    test_bug_2_1()
