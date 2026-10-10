#!/usr/bin/env python3
"""
Fast Sanity Test Runner for SE.COM (Screen Editor).
Verifies the core lifecycle of SE.COM:
  1. Boot RomWBW and start SE.COM from CP/M
  2. Verify Splash Screen rendering
  3. Enter Editor Mode and verify Status Bar
  4. Type text and verify character buffer rendering
  5. Toggle Block Selection (Ctrl+B) and verify Sel: 0 chars
  6. Cancel Block Selection (Ctrl+B)
  7. Open Editor Mode Keys Help (Ctrl+K) and return to editor
  8. Clean exit (Ctrl+Q) back to CP/M prompt (C>)
  9. Open CP/M file (se 2.TXT) and verify clean status bar (no U: suffix)
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
    cpmrm_bin = os.path.join(workspace_root, "tools", "romwbw_src", "Tools",
                             "Linux", "cpmrm")

    return emu_bin, rom_file, img_file, se_bin, cpmrm_bin

def read_until(master_fd, match_bytes, timeout=5.0):
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

def run_sanity_test(use_sec=False):
    t_start = time.time()
    emu_bin, rom_file, img_file, se_bin, cpmrm_bin = find_paths()
    target_name = "SEC.COM" if use_sec else "SE.COM"
    cmd_name = b"sec" if use_sec else b"se"

    if not os.path.isfile(emu_bin):
        print(f"[-] Emulator binary not found: {emu_bin}", flush=True)
        return False
    if not os.path.isfile(rom_file):
        print(f"[-] ROM file not found: {rom_file}", flush=True)
        return False
    if not os.path.isfile(img_file):
        print(f"[-] Disk image not found: {img_file}", flush=True)
        return False

    if os.path.isfile(cpmrm_bin):
        subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file,
                        "0:RAMDRV.IMG"],
                       stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
        subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.CFG"],
                       stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)

    print(f"[*] Launching RomWBW on RC2014 emulator ({target_name} Sanity)...",
          flush=True)
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave,
                            close_fds=True)
    os.close(slave)

    try:
        # 1. Boot loader prompt
        print("[*] Step 1: Waiting for RomWBW boot loader prompt...",
              flush=True)
        out = read_until(master, b"Boot [H=Help]:", timeout=6.0)
        if b"Boot [H=Help]:" not in out:
            print("[-] Step 1: Failed to reach RomWBW boot loader prompt.",
                  flush=True)
            return False
        print("[+] Step 1: Boot loader prompt reached.", flush=True)

        # 2. Boot CP/M on ROM disk (Choice 'c') and switch to Drive C:
        print("[*] Step 2: Booting into CP/M and switching to Drive C:...",
              flush=True)
        time.sleep(0.5)
        os.write(master, b"c\r")
        out = read_until(master, b"B>", timeout=6.0)
        if b"B>" not in out:
            print("[-] Step 2: Failed to boot into CP/M prompt.", flush=True)
            return False

        time.sleep(0.5)
        os.write(master, b"c:\r")
        out = read_until(master, b"C>", timeout=10.0)
        if b"C>" not in out:
            print(f"[-] Step 2: Failed to switch to Drive C:. Buffer: "
                  f"{repr(out)}", flush=True)
            return False
        print("[+] Step 2: Switched to Drive C>.", flush=True)

        # 3. Launch editor binary
        print(f"[*] Step 3: Launching {target_name}...", flush=True)
        time.sleep(0.5)
        os.write(master, cmd_name + b"\r")
        out = read_until(master, b"Col 0", timeout=30.0)
        if b"Col 0" not in out:
            print(f"[-] Step 3: {target_name} splash screen not detected. "
                  f"Buffer: {repr(out)}", flush=True)
            return False
        print(f"[+] Step 3: {target_name} splash screen displayed "
              f"successfully.", flush=True)

        # 4. Enter Editor Mode ('e')
        print("[*] Step 4: Entering Editor Mode ('e')...", flush=True)
        time.sleep(0.3)
        os.write(master, b"e")
        out_edit = read_until(master, b"^K: Editor keys", timeout=6.0)
        if b"(Untitled)" not in out_edit or b"^K: Editor keys" not in out_edit:
            print(f"[-] Step 4: Failed to enter editor mode. Buffer: "
                  f"{repr(out_edit)}", flush=True)
            return False
        print("[+] Step 4: Entered editor mode with status bar verified.",
              flush=True)

        # 5. Type 'SANITY CHECK OK'
        print("[*] Step 5: Typing 'SANITY CHECK OK'...", flush=True)
        time.sleep(0.1)
        os.write(master, b"SANITY CHECK OK")
        out_typed = read_until(master, b"Col 15", timeout=3.0)
        if b"SANITY CHECK OK" not in out_typed:
            print(f"[-] Step 5: Text insertion failed. Buffer: "
                  f"{repr(out_typed)}", flush=True)
            return False
        print("[+] Step 5: Text insertion and cursor tracking verified.",
              flush=True)

        # 6. Test Block Mode toggle: Ctrl+B to start, verify Sel: 0 chars
        print("[*] Step 6: Testing Block Mode toggle (Ctrl+B)...", flush=True)
        time.sleep(0.1)
        os.write(master, b"\x02")
        out_blk = read_until(master, b"Sel: 0 chars", timeout=3.0)
        if b"Sel: 0 chars" not in out_blk:
            print(f"[-] Step 6: Block mode activation failed. Buffer: "
                  f"{repr(out_blk)}", flush=True)
            return False
        time.sleep(0.1)
        os.write(master, b"\x02")
        out_unblk = read_until(master, b"^K: Editor keys", timeout=3.0)
        if b"^K: Editor keys" not in out_unblk:
            print(f"[-] Step 6: Block mode deactivation failed. Buffer: "
                  f"{repr(out_unblk)}", flush=True)
            return False
        print("[+] Step 6: Block mode toggle verified.", flush=True)

        # 7. Test Editor Mode Keys Help Screen: Ctrl+K, then return with Enter
        print("[*] Step 7: Testing Editor Mode Keys Help Screen (Ctrl+K)...",
              flush=True)
        time.sleep(0.1)
        os.write(master, b"\x0b")
        out_help = read_until(master,
                              b"Press any key to continue",
                              timeout=3.0)
        if b"EDITOR MODE KEYS" not in out_help:
            print(f"[-] Step 7: Help screen failed. Buffer: {repr(out_help)}",
                  flush=True)
            return False
        drain_all(master)
        time.sleep(0.1)
        os.write(master, b"\r")
        out_back = read_until(master, b"^K: Editor keys", timeout=3.0)
        if b"SANITY CHECK OK" not in out_back:
            print(f"[-] Step 7: Return from help screen failed. Buffer: "
                  f"{repr(out_back)}", flush=True)
            return False
        print("[+] Step 7: Help screen and return verified.", flush=True)

        # 8. Clean exit to CP/M with Ctrl+Q (prompts for unsaved changes)
        print("[*] Step 8: Testing clean exit with Ctrl+Q and prompt...",
              flush=True)
        time.sleep(0.1)
        os.write(master, b"\x11")
        out_prompt = read_until(master, b"Cancel", timeout=3.0)
        if b"Save changes?" not in out_prompt or b"ESC" not in out_prompt:
            print(f"[-] Step 8: Save changes prompt failed. Buffer: "
                  f"{repr(out_prompt)}", flush=True)
            return False
        # Verify modal pop-up contains title and Save changes? prompt
        # inside the box enclosure
        if b"Unsaved Modifications" not in out_prompt or \
           b"|                 Save changes?" not in out_prompt:
            print(f"[-] Step 8: Save changes prompt not embedded in popup. "
                  f"Buffer: {repr(out_prompt)}", flush=True)
            return False

        # Answer 'n' to discard changes and return to CP/M
        os.write(master, b"n")
        out_exit = read_until(master, b"C>", timeout=8.0)
        if b"C>" not in out_exit:
            print(f"[-] Step 8: Clean exit with Ctrl+Q failed. Buffer: "
                  f"{repr(out_exit)}", flush=True)
            return False
        print("[+] Step 8: Clean exit with unsaved prompt verified.",
              flush=True)

        # 9. Verify CLI file load & clean status bar filename: '<cmd> 2.TXT'
        print(f"[*] Step 9: Verifying CLI file load & status bar "
              f"({cmd_name.decode()} 2.TXT)...", flush=True)
        drain_all(master)
        time.sleep(0.5)
        os.write(master, cmd_name + b" 2.TXT\r")
        out_load = read_until(master, b"Line    1/2", timeout=30.0)
        if b"| C:2.TXT        |" not in out_load:
            print(f"[-] Step 9: Status bar filename malformed (expected "
                  f"'| C:2.TXT        |'). Buffer: {repr(out_load[-400:])}",
                  flush=True)
            return False
        if b"2.TXTU:" in out_load or b".TXTU:" in out_load:
            print("[-] Step 9: Status bar corrupted with "
                  f"erroneous 'U:' suffix! Buffer: {repr(out_load[-400:])}",
                  flush=True)
            return False
        print(f"[+] Step 9: Verified clean status bar for CP/M file "
              f"({cmd_name.decode()} 2.TXT): '| C:2.TXT        |'.", flush=True)

        # Clean exit to CP/M
        time.sleep(0.3)
        os.write(master, b"\x11")
        out_exit2 = read_until(master, b"C>", timeout=6.0)
        if b"C>" not in out_exit2:
            print(f"[-] Step 9: Exit from 2.TXT session failed. "
                  f"Buffer: {repr(out_exit2)}", flush=True)
            return False
        print("[+] Step 9: Clean exit back to CP/M prompt.", flush=True)

        elapsed = time.time() - t_start
        print(f"[+] All {target_name} sanity tests PASSED in {elapsed:.2f}s!",
              flush=True)
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
    use_sec_arg = "--sec" in sys.argv
    success = run_sanity_test(use_sec=use_sec_arg)
    sys.exit(0 if success else 1)
