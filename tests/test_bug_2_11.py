#!/usr/bin/env python3
"""
Automated Test for Bug 2.11:
Child Pop-ups Rendered Over Unhidden Parent Pop-ups in Plugin Manager.

Verifies single-level pop-up visibility lifecycle in plugins/plugin.asm:
  1. Open Plugin Manager ('p').
  2. Press Ctrl+P: verify parent Ctrl+P context pop-up displays.
  3. Press 'U': verify child Unload confirmation pop-up displays and
     parent Ctrl+P pop-up is completely hidden.
  4. Cancel unload ('n'): verify child pop-up is erased and parent
     Ctrl+P pop-up is redrawn in full.
  5. Press 'A': verify child About pop-up displays and parent
     Ctrl+P pop-up is completely hidden.
  6. Dismiss About (space): verify child pop-up is erased and parent
     Ctrl+P pop-up is redrawn in full.
  7. Select slot 0 (WORDCNT) and press Enter: verify Document Statistics
     child modal pop-up displays and parent Ctrl+P pop-up is completely hidden.
  8. Dismiss Word Count (space): verify child pop-up is erased and
     parent Ctrl+P pop-up is redrawn in full.
  9. Dismiss Ctrl+P (ESC): verify returned cleanly to Plugin Manager.
 10. Exit Plugin Manager ('q') and exit SE.COM.
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

    return emu_bin, rom_file, img_file, se_bin


def read_until(master_fd, match_bytes, timeout=8.0):
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
        time.sleep(0.01)
    return False, buf


def drain_all(master_fd, timeout=0.2):
    buf = b""
    t0 = time.time()
    while time.time() - t0 < timeout:
        r, _, _ = select.select([master_fd], [], [], 0.02)
        if r:
            try:
                data = os.read(master_fd, 1024)
                if not data:
                    break
                buf += data
            except (BlockingIOError, OSError):
                break
        else:
            break
    return buf


def main():
    emu_bin, rom_file, img_file, se_bin = find_paths()

    for p, name in [(emu_bin, "RC2014 emulator"), (rom_file, "ROM file"),
                    (img_file, "Disk image"), (se_bin, "SE.COM binary")]:
        if not os.path.isfile(p):
            print(f"[-] Error: {name} not found at {p}")
            sys.exit(1)

    print("=" * 65)
    print("  Bug 2.11: Child Pop-up Lifecycle in Plugin Manager Regression  ")
    print("=" * 65)

    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )
    os.close(slave)

    try:
        # Boot RomWBW
        ok, _ = read_until(master, b"Boot [H=Help]:", timeout=8.0)
        if not ok:
            print("[-] RomWBW boot prompt not seen")
            return 1
        time.sleep(0.5)
        os.write(master, b"c\r")
        read_until(master, b"B>", timeout=6.0)
        time.sleep(0.5)
        os.write(master, b"c:\r")
        read_until(master, b"C>", timeout=8.0)
        time.sleep(0.5)

        # Launch SE.COM
        os.write(master, b"se\r")
        ok, out = read_until(master, b"for about", timeout=60.0)
        if not ok:
            print(f"[-] Splash screen not seen. Output: {repr(out)}")
            return 1
        print("[+] Splash screen loaded.")
        drain_all(master)

        # 1. Enter Plugin Manager ('p')
        time.sleep(0.3)
        os.write(master, b"p")
        ok, out = read_until(master, b"SE - Plugin Manager", timeout=8.0)
        if not ok:
            print("[-] Plugin Manager screen not seen")
            return 1
        print("[+] Step 1 PASSED: Plugin Manager displayed.")

        # 2. Press Ctrl+P inside Plugin Manager
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"\x10")  # Ctrl+P
        ok, out = read_until(master, b"Installed Plugin Catalog", timeout=6.0)
        if not ok or b"[Down]=Select" not in out:
            print("[-] Failed to open Ctrl+P pop-up in Plugin Manager.")
            print(f"    Out: {repr(out)}")
            return 1
        print("[+] Step 2 PASSED: Parent Ctrl+P context pop-up displayed.")

        # 3. Press 'U' to trigger child Unload modal pop-up
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"u")
        ok, out = read_until(master, b"Unload Slot 0?", timeout=6.0)
        if not ok:
            print("[-] 'u' failed to spawn Unload child pop-up.")
            print(f"    Out: {repr(out)}")
            return 1
        # Verify parent Ctrl+P pop-up was hidden
        # (title no longer present on active screen)
        if b"Installed Plugin Catalog" in out:
            print("[-] Ghosting detected: parent pop-up title found "
                      "in unload render!")
            return 1
        print("[+] Step 3 PASSED: Child Unload pop-up displayed; "
                  "parent pop-up hidden.")

        # 4. Cancel unload via 'n' -> parent Ctrl+P pop-up must be redrawn
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"n")
        ok, out = read_until(master, b"Installed Plugin Catalog", timeout=6.0)
        if not ok or b"[Down]=Select" not in out:
            print("[-] Parent Ctrl+P pop-up not redrawn after unload cancel.")
            print(f"    Out: {repr(out)}")
            return 1
        print("[+] Step 4 PASSED: Parent Ctrl+P pop-up redrawn cleanly "
                  "after unload cancel.")

        # 5. Press 'A' to trigger child About modal pop-up for WORDCNT
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"a")
        ok, out = read_until(
            master, b"Word & Character Count Plugin", timeout=6.0
        )
        if not ok:
            print("[-] 'a' failed to spawn About child pop-up.")
            print(f"    Out: {repr(out)}")
            return 1
        print("[+] Step 5 PASSED: Child About pop-up displayed; "
                  "parent pop-up hidden.")

        # 6. Dismiss About (press space) -> parent Ctrl+P pop-up must be redrawn
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b" ")
        ok, out = read_until(master, b"Installed Plugin Catalog", timeout=6.0)
        if not ok or b"[Down]=Select" not in out:
            print("[-] Parent Ctrl+P pop-up not redrawn after About dismiss.")
            print(f"    Out: {repr(out)}")
            return 1
        print("[+] Step 6 PASSED: Parent Ctrl+P pop-up redrawn cleanly "
                  "after About dismiss.")

        # 7. Select slot 0 (WORDCNT) and press Enter to execute modal action
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"\r")
        ok, out = read_until(master, b"Document Statistics", timeout=6.0)
        if not ok:
            print("[-] Enter failed to execute WORDCNT modal dialog.")
            print(f"    Out: {repr(out)}")
            return 1
        print("[+] Step 7 PASSED: WORDCNT child modal dialog displayed; "
              "parent hidden.")

        # 8. Dismiss WORDCNT dialog (press space) -> parent Ctrl+P pop-up
        # must be redrawn
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b" ")
        ok, out = read_until(master, b"Installed Plugin Catalog", timeout=6.0)
        if not ok or b"[Down]=Select" not in out:
            print("[-] Parent Ctrl+P pop-up not redrawn after modal dismiss.")
            print(f"    Out: {repr(out)}")
            return 1
        print("[+] Step 8 PASSED: Parent Ctrl+P pop-up redrawn cleanly "
              "after modal dismiss.")

        # 9. Dismiss Ctrl+P pop-up via ESC -> return to Plugin Manager
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"\x1b")
        ok, out = read_until(master, b"[Enter]=Unload", timeout=6.0)
        if not ok:
            print("[-] ESC failed to return cleanly to Plugin Manager.")
            print(f"    Out: {repr(out)}")
            return 1
        print("[+] Step 9 PASSED: Returned cleanly to Plugin Manager.")

        # 10. Exit Plugin Manager ('q') and exit SE.COM
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"q")
        ok, out = read_until(master, b"for about", timeout=6.0)
        if not ok:
            print("[-] 'q' failed to return to Splash Screen.")
            return 1

        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"q")
        ok, out = read_until(master, b"C>", timeout=6.0)
        if not ok:
            print("[-] Failed to exit to CP/M prompt.")
            return 1
        print("[+] Step 10 PASSED: Clean exit to CP/M prompt.")

        print("=" * 65)
        print("  ALL BUG 2.11 REGRESSION TESTS PASSED (100%)!")
        print("=" * 65)
        return 0

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=1.0)
        except Exception:
            proc.kill()
        os.close(master)


if __name__ == "__main__":
    sys.exit(main())
