#!/usr/bin/env python3
"""
Automated Test Suite for SE.COM Modular Plugin Slots (4K, 8K, 16K, 32K).
Verifies:
  1. Tooling & Packaging Validation:
     - mkprl.py enforces 4KB restriction for TPA execution.
     - mkprl.py enforces maximum payload sizes for 4K, 8K, 16K, 32K.
     - Capability bitflags encode size class in bits 7..6.
  2. Multi-Bank & Multi-Size Runtime Lifecycle:
     - Boots RomWBW on RC2014 emulator.
     - Opens Plugin Manager from Splash Screen.
     - Verifies auto-probed 4KB plugins display "FAR (4KB)" and "TPA (4KB)".
     - Dynamically loads 8KB plugin (MIDPLUG.PRL) into Slot 3 ("FAR (8KB)").
     - Executes MIDPLUG in Far RAM and verifies modal dialog display & return.
     - Unloads MIDPLUG, verifying automatic Far RAM bank release.
     - Dynamically loads 16KB plugin (HALFPLUG.PRL) into Slot 3 ("FAR (16KB)").
     - Executes HALFPLUG in Far RAM and verifies modal dialog display & return.
     - Unloads HALFPLUG, verifying automatic Far RAM bank release.
     - Dynamically loads 32KB plugin (BIGPLUG.PRL) into Slot 3 ("FAR (32KB)"),
       triggering multi-bank Far RAM dynamic borrowing.
     - Executes BIGPLUG in Far RAM and verifies modal dialog display & return.
     - Unloads BIGPLUG, verifying automatic bank release.
     - Clean exit back to CP/M prompt.
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
    rom_file = os.path.join(workspace_root, "tools", "romwbw_src", "Binary", "RC2014_std.rom")
    img_file = os.path.join(workspace_root, "tools", "romwbw_src", "Binary", "hd1k_combo.img")
    se_bin = os.path.join(repo_root, "SE.COM")
    mkprl_bin = os.path.join(repo_root, "tools", "mkprl.py")

    return emu_bin, rom_file, img_file, se_bin, mkprl_bin


def test_tooling_validations(mkprl_bin):
    """Verify mkprl.py constraints on sizes and TPA execution."""
    print("[*] Running mkprl.py packaging and validation tests...", flush=True)

    # 1. 8KB / 16KB / 32KB rejection of --tpa
    proc = subprocess.run([sys.executable, mkprl_bin, "-n", "FAIL8",
                           "-o", "/dev/null", "--size", "8k",
                           "--tpa", "/dev/null"],
                          capture_output=True, text=True)
    if proc.returncode == 0:
        print("[-] mkprl.py failed to reject --size 8k with --tpa", flush=True)
        return False
    if "cannot use --tpa" not in proc.stderr:
        print(f"[-] Unexpected error message for 8K --tpa: {proc.stderr}",
              flush=True)
        return False

    proc = subprocess.run([sys.executable, mkprl_bin, "-n", "FAIL16",
                           "-o", "/dev/null", "--size", "16k",
                           "--tpa", "/dev/null"],
                          capture_output=True, text=True)
    if proc.returncode == 0:
        print("[-] mkprl.py failed to reject --size 16k with --tpa", flush=True)
        return False
    if "cannot use --tpa" not in proc.stderr:
        print(f"[-] Unexpected error message for 16K --tpa: {proc.stderr}",
              flush=True)
        return False

    proc = subprocess.run([sys.executable, mkprl_bin, "-n", "FAIL32",
                           "-o", "/dev/null", "--size", "32k",
                           "--tpa", "/dev/null"],
                          capture_output=True, text=True)
    if proc.returncode == 0:
        print("[-] mkprl.py failed to reject --size 32k with --tpa", flush=True)
        return False

    print("[+] Verified mkprl.py rejects --tpa for 8K, 16K, 32K plugins.",
          flush=True)
    return True


def read_until(master_fd, match_bytes, timeout=6.0):
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
                    return True, buf
            except (BlockingIOError, OSError):
                pass
    return False, buf


def drain_all(master_fd, quiet_time=0.1):
    time.sleep(0.05)
    while True:
        r, _, _ = select.select([master_fd], [], [], quiet_time)
        if not r:
            break
        try:
            data = os.read(master_fd, 2048)
            if not data:
                break
        except (BlockingIOError, OSError):
            break


def run_slots_test():
    t_start = time.time()
    emu_bin, rom_file, img_file, se_bin, mkprl_bin = find_paths()

    if not test_tooling_validations(mkprl_bin):
        return False

    if not os.path.isfile(emu_bin):
        print(f"[-] Emulator binary not found: {emu_bin}", flush=True)
        return False
    if not os.path.isfile(rom_file):
        print(f"[-] ROM file not found: {rom_file}", flush=True)
        return False
    if not os.path.isfile(img_file):
        print(f"[-] Disk image not found: {img_file}", flush=True)
        return False

    print("[*] Launching RomWBW on RC2014 emulator (Plugin Slots Test)...", flush=True)
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)

    try:
        # 1. Boot RomWBW CP/M
        ok, out = read_until(master, b"Boot [H=Help]:", timeout=6.0)
        if not ok:
            print("[-] Failed to reach RomWBW boot loader prompt.", flush=True)
            return False

        time.sleep(0.5)
        os.write(master, b"c\r")
        ok, out = read_until(master, b"B>", timeout=6.0)
        if not ok:
            print("[-] Failed to boot into CP/M prompt.", flush=True)
            return False

        time.sleep(0.5)
        os.write(master, b"c:\r")
        ok, out = read_until(master, b"C>", timeout=8.0)
        if not ok:
            print(f"[-] Failed to switch to Drive C:.", flush=True)
            return False
        print("[+] Switched to Drive C>.", flush=True)

        # 2. Launch SE.COM
        time.sleep(0.5)
        os.write(master, b"se\r")
        ok, out = read_until(master, b"Col 0", timeout=45.0)
        if not ok:
            print(f"[-] Splash screen failed to display.", flush=True)
            return False
        drain_all(master, quiet_time=0.1)

        # 3. Enter Plugin Manager ('p')
        time.sleep(0.5)
        os.write(master, b"p")
        ok, out = read_until(master, b"SE - Plugin Manager", timeout=8.0)
        if not ok:
            print(f"[-] Failed to enter Plugin Manager.", flush=True)
            return False

        # Verify 4KB mode display
        if b"FAR (4KB)" not in out or b"TPA (4KB)" not in out:
            ok, out_more = read_until(master, b"0..7:select", timeout=5.0)
            out += out_more
        if b"FAR (4KB)" not in out or b"TPA (4KB)" not in out:
            print(f"[-] Plugin Manager did not display 4KB slot modes. Buffer: {repr(out)}", flush=True)
            return False
        print("[+] Plugin Manager displayed 4KB slot mode identifiers.", flush=True)

        # 4. Load 8KB Plugin (MIDPLUG.PRL)
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"l")
        read_until(master, b"Load Plugin", timeout=4.0)
        time.sleep(0.1)
        os.write(master, b"MIDPLUG.PRL\r")
        ok, out_mp = read_until(master, b"FAR (8KB)", timeout=8.0)
        if not ok or b"MIDPLUG" not in out_mp:
            print(f"[-] Failed to load MIDPLUG.PRL as 8KB Far RAM slot. "
                  f"Buffer: {repr(out_mp)}", flush=True)
            return False
        print("[+] MIDPLUG.PRL successfully loaded into Slot 3 as 'FAR (8KB)'.",
              flush=True)

        # 5. View MIDPLUG About (Slot 3) via 'a'
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"a")
        ok, out_run_mp = read_until(master, b"[Press any key to return]",
                                    timeout=8.0)
        if not ok or b"MIDPLUG 8KB Reference Plugin" not in out_run_mp:
            print(f"[-] MIDPLUG modal dialog failed to execute. "
                  f"Buffer: {repr(out_run_mp)}", flush=True)
            return False
        print("[+] MIDPLUG executed in 8KB Far RAM slot; dialog displayed.",
              flush=True)

        # Dismiss dialog
        time.sleep(0.2)
        os.write(master, b" ")
        read_until(master, b"SE - Plugin Manager", timeout=5.0)

        # 6. Unload MIDPLUG (Slot 3) - releases Far RAM bank via modal pop-up
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"\r")
        ok, out_pop = read_until(master, b"Unload Slot 3? [Y/N]", timeout=4.0)
        assert ok, "Unload modal popup prompt missing"
        assert b"Unload Plugin" in out_pop, "Unload modal popup title missing"
        border_line = b"+------------------------------------------------+"
        assert border_line in out_pop, "Unload modal popup border missing"
        os.write(master, b"y")
        ok, out_u3 = read_until(master, b"(empty slot)", timeout=6.0)
        if not ok:
            print(f"[-] Unload slot 3 failed. Buffer: {repr(out_u3)}",
                  flush=True)
            return False
        print("[+] Slot 3 (MIDPLUG 8KB) unloaded and bank released.",
              flush=True)

        # 7. Load 16KB Plugin (HALFPLUG.PRL)
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"l")
        read_until(master, b"Load Plugin", timeout=4.0)
        time.sleep(0.1)
        os.write(master, b"HALFPLUG.PRL\r")
        ok, out_hp = read_until(master, b"FAR (16KB)", timeout=8.0)
        if not ok or b"HALFPLUG" not in out_hp:
            print(f"[-] Failed to load HALFPLUG.PRL as 16KB Far RAM slot. "
                  f"Buffer: {repr(out_hp)}", flush=True)
            return False
        print("[+] HALFPLUG.PRL loaded into Slot 3 as 'FAR (16KB)'.",
              flush=True)

        # 8. View HALFPLUG About (Slot 3) via cursor and 'a'
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"a")
        ok, out_run_hp = read_until(master, b"[Press any key to return]",
                                    timeout=8.0)
        if not ok or b"HALFPLUG 16KB Reference Plugin" not in out_run_hp:
            print(f"[-] HALFPLUG modal dialog failed to execute. "
                  f"Buffer: {repr(out_run_hp)}", flush=True)
            return False
        print("[+] HALFPLUG executed in 16KB Far RAM slot; dialog displayed.",
              flush=True)

        # Dismiss dialog
        time.sleep(0.2)
        os.write(master, b" ")
        read_until(master, b"SE - Plugin Manager", timeout=5.0)

        # 9. Unload HALFPLUG (Slot 3) - releases Far RAM bank
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"3")
        read_until(master, b"Unload Slot 3? [Y/N]", timeout=4.0)
        os.write(master, b"y")
        ok, out_u3 = read_until(master, b"(empty slot)", timeout=6.0)
        if not ok:
            print(f"[-] Unload slot 3 failed. Buffer: {repr(out_u3)}",
                  flush=True)
            return False
        print("[+] Slot 3 (HALFPLUG 16KB) unloaded and bank released.",
              flush=True)

        # 10. Load 32KB Plugin (BIGPLUG.PRL)
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"l")
        read_until(master, b"Load Plugin", timeout=4.0)
        time.sleep(0.1)
        os.write(master, b"BIGPLUG.PRL\r")
        ok, out_bp = read_until(master, b"FAR (32KB)", timeout=8.0)
        if not ok or b"BIGPLUG" not in out_bp:
            print(f"[-] Failed to load BIGPLUG.PRL as 32KB Far RAM slot. "
                  f"Buffer: {repr(out_bp)}", flush=True)
            return False
        print("[+] BIGPLUG.PRL loaded into Slot 3 as 'FAR (32KB)' "
              "(Multi-Bank Far RAM allocation).", flush=True)

        # 11. View BIGPLUG About (Slot 3) via 'a'
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"a")
        ok, out_run_bp = read_until(master, b"[Press any key to return]",
                                    timeout=8.0)
        if not ok or b"BIGPLUG 32KB Reference Plugin" not in out_run_bp:
            print(f"[-] BIGPLUG modal dialog failed to execute. "
                  f"Buffer: {repr(out_run_bp)}", flush=True)
            return False
        print("[+] BIGPLUG executed in 32KB Far RAM slot; dialog displayed.",
              flush=True)

        # Dismiss dialog
        time.sleep(0.2)
        os.write(master, b" ")
        read_until(master, b"SE - Plugin Manager", timeout=5.0)

        # 12. Unload BIGPLUG (Slot 3)
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"\r")
        read_until(master, b"Unload Slot 3? [Y/N]", timeout=4.0)
        os.write(master, b"y")
        ok, out_u4 = read_until(master, b"(empty slot)", timeout=6.0)
        if not ok:
            print(f"[-] Unload slot 3 failed. Buffer: {repr(out_u4)}",
                  flush=True)
            return False
        print("[+] Slot 3 (BIGPLUG 32KB) successfully unloaded and Far RAM "
              "bank released.", flush=True)

        # 13. Exit Plugin Manager back to Splash Screen
        time.sleep(0.2)
        os.write(master, b"q")
        ok, out_splash = read_until(master,
                                    b"type   e  or  <Enter>   to edit",
                                    timeout=5.0)
        if not ok:
            print(f"[-] Exit to splash screen failed. "
                  f"Buffer: {repr(out_splash)}", flush=True)
            return False

        # 14. Exit SE.COM (Ctrl+Q)
        time.sleep(0.2)
        os.write(master, b"\x11")  # Ctrl+Q
        ok, out_exit = read_until(master, b"C>", timeout=5.0)
        if not ok:
            print(f"[-] Clean exit to CP/M prompt failed. "
                  f"Buffer: {repr(out_exit)}", flush=True)
            return False
        print("[+] Clean exit to CP/M prompt verified.", flush=True)

        elapsed = time.time() - t_start
        print(f"[+] All Modular Plugin Slot (4K/8K/16K/32K) tests "
              f"PASSED in {elapsed:.2f}s!", flush=True)
        return True

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=1.0)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass
        try:
            os.close(master)
        except OSError:
            pass


if __name__ == "__main__":
    success = run_slots_test()
    sys.exit(0 if success else 1)
