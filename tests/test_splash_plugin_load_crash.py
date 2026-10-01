#!/usr/bin/env python3
"""
test_splash_plugin_load_crash.py - Regression test for splash plugin load crash:
1. Start SE.COM with empty PLUGIN.CFG and LINES=16K in SE.CFG.
2. Open large file (2.TXT > 16384 lines).
3. Press ESC to return to splash screen.
4. Press 'p' to open Plugin Manager.
5. Load BEAUTIFY.PRL into Slot 0.
6. Press ESC to return to splash screen.
7. Verify clean return to splash screen without crashing/bombing out to CP/M.
"""

import os
import sys
import time
import tty
import select
import subprocess
import shutil

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
    base_img = os.path.join(img_dir, "hd1k_combo.img")
    if not os.path.isfile(base_img):
        os.makedirs(img_dir, exist_ok=True)
        subprocess.run(
            ["cp", "--sparse=always", golden_img, base_img], check=True
        )
        os.chmod(base_img, 0o644)
    cpmcp = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp"
    )
    cpmrm = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm"
    )
    return repo_root, emu_bin, rom_file, base_img, cpmcp, cpmrm

def read_until(master_fd, match_bytes, timeout=12.0):
    buf = b""
    t0 = time.time()
    while time.time() - t0 < timeout:
        r, _, _ = select.select([master_fd], [], [], 0.05)
        if r:
            try:
                d = os.read(master_fd, 1024)
                if not d:
                    break
                buf += d
                if match_bytes in buf:
                    return True, buf
            except (BlockingIOError, OSError):
                pass
    return False, buf

def drain_all(master_fd, timeout=0.2):
    while True:
        r, _, _ = select.select([master_fd], [], [], timeout)
        if not r:
            break
        try:
            d = os.read(master_fd, 2048)
            if not d:
                break
        except (BlockingIOError, OSError):
            break

def main():
    repo_root, emu_bin, rom_file, base_img, cpmcp, cpmrm = find_paths()
    test_img = "/tmp/test_splash_plugin_load.img"
    shutil.copyfile(base_img, test_img)

    plug_cfg = "/tmp/splash_test_plugin.cfg"
    with open(plug_cfg, "w") as f:
        for i in range(8):
            f.write(f"SLOT{i}=\r\n")

    se_cfg = "/tmp/splash_test_se.cfg"
    with open(se_cfg, "w") as f:
        f.write("LINES=16K\r\n")

    try:
        for fn, src in [("PLUGIN.CFG", plug_cfg), ("SE.CFG", se_cfg)]:
            subprocess.run(
                [cpmrm, "-f", "wbw_hd1k_0", test_img, f"0:{fn}"],
                stderr=subprocess.DEVNULL
            )
            subprocess.run(
                [cpmcp, "-f", "wbw_hd1k_0", test_img, src, f"0:{fn}"],
                check=True
            )

        master, slave = os.openpty()
        tty.setraw(slave)
        os.set_blocking(master, False)

        cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", test_img]
        proc = subprocess.Popen(
            cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
        )
        os.close(slave)

        ok, out = read_until(master, b"Boot [H=Help]:", timeout=10.0)
        assert ok, "Failed to reach boot prompt"
        time.sleep(0.3)
        os.write(master, b"c\r")

        ok, out = read_until(master, b"B>", timeout=8.0)
        assert ok, "Failed to reach B> prompt"
        time.sleep(0.3)
        os.write(master, b"c:\r")

        ok, out = read_until(master, b"C>", timeout=8.0)
        assert ok, "Failed to reach C> prompt"

        time.sleep(0.3)
        drain_all(master)
        print("[*] Launching: se 2.TXT")
        os.write(master, b"se 2.TXT\r")
        ok, out = read_until(master, b"Line    1/2", timeout=35.0)
        assert ok, f"Failed editor entry: {out}"
        print("[+] Entered editor with 2.TXT")

        time.sleep(0.3)
        drain_all(master)
        print("[*] Pressing ESC to return to splash screen...")
        os.write(master, b"\x1b")
        ok, out = read_until(master, b"SE - Screen Editor", timeout=8.0)
        assert ok, f"Failed splash screen return: {out}"
        print("[+] Returned to splash screen")

        time.sleep(0.3)
        drain_all(master)
        print("[*] Pressing 'p' for Plugin Manager...")
        os.write(master, b"p")
        ok, out = read_until(master, b"SE - Plugin Manager", timeout=8.0)
        assert ok, f"Failed plugin manager entry: {out}"
        print("[+] Opened Plugin Manager")

        time.sleep(0.3)
        drain_all(master)
        print("[*] Pressing Enter on Slot 0 to open load prompt...")
        os.write(master, b"\r")
        ok, out = read_until(master, b"Load Plugin (.PRL/.OVL):", timeout=8.0)
        assert ok, f"Failed load plugin prompt: {out}"
        print("[+] Load plugin prompt active")

        time.sleep(0.3)
        print("[*] Typing BEAUTIFY.PRL and Enter...")
        os.write(master, b"BEAUTIFY.PRL\r")
        ok, out = read_until(master, b"Up/Dn:select", timeout=15.0)
        assert ok, f"Failed waiting for plugin manager ready: {out}"
        print("[+] Plugin BEAUTIFY.PRL loaded successfully")

        time.sleep(0.3)
        drain_all(master)
        print("[*] Pressing ESC to return to splash screen...")
        os.write(master, b"\x1b")

        time.sleep(1.0)
        t0 = time.time()
        buf = b""
        while time.time() - t0 < 5.0:
            r, _, _ = select.select([master], [], [], 0.05)
            if r:
                try:
                    c = os.read(master, 1024)
                    if c:
                        buf += c
                except (BlockingIOError, OSError):
                    pass

        if b"C>" in buf or b"B>" in buf or b"J>" in buf:
            print(f"[FAIL] Bombed out to CP/M prompt: {buf}")
            sys.exit(1)

        assert b"SE - Screen Editor" in buf, (
            f"Expected splash screen, got: {buf}"
        )
        print("[+] Verified: Clean return to splash screen without CP/M crash!")

        # Cleanly exit splash screen
        os.write(master, b"q")
        ok, out = read_until(master, b"C>", timeout=5.0)
        assert ok, f"Failed clean exit to C> prompt: {out}"
        print("[+] Verified: Clean exit to CP/M prompt")

    finally:
        try:
            os.close(master)
        except OSError:
            pass
        proc.terminate()
        try:
            proc.wait(timeout=2.0)
        except subprocess.TimeoutExpired:
            proc.kill()
        for p in [test_img, plug_cfg, se_cfg]:
            if os.path.exists(p):
                os.remove(p)

    print("\n[PASS] test_splash_plugin_load_crash passed successfully.")

if __name__ == "__main__":
    main()
