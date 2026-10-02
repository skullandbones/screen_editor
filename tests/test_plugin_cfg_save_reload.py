#!/usr/bin/env python3
"""
test_plugin_cfg_save_reload.py - Verification of PLUGIN.CFG Save & Autoload

Verifies:
  1. Boots RomWBW CP/M and launches SE.COM.
  2. Opens Plugin Manager ('p') and verifies initial autoloaded slots.
  3. Unloads slot 1 (ROT13.PRL) and loads MIDPLUG.PRL (8KB).
  4. Saves configuration with 's' and verifies '[Saved to PLUGIN.CFG]'.
  5. Exits SE.COM to CP/M prompt.
  6. Verifies on-disk PLUGIN.CFG contains SLOT1=MIDPLUG.PRL.
  7. Relaunches SE.COM from CP/M prompt.
  8. Enters Plugin Manager and verifies MIDPLUG.PRL was autoloaded into Slot 1.
  9. Clean exit back to CP/M prompt and restoration of default PLUGIN.CFG.
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
    rom_file = os.path.join(workspace_root, "tools", "romwbw_src", "Binary",
                            "RC2014_std.rom")
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
    cpmcp_bin = os.path.join(workspace_root, "tools", "romwbw_src", "Tools",
                             "Linux", "cpmcp")
    cpmrm_bin = os.path.join(workspace_root, "tools", "romwbw_src", "Tools",
                             "Linux", "cpmrm")

    return emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin


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


DEFAULT_CFG = (
    "SLOT0=WORDCNT.OVL\r\n"
    "SLOT1=ROT13.PRL\r\n"
    "SLOT2=BEAUTIFY.PRL\r\n"
    "SLOT3=\r\n"
    "SLOT4=\r\n"
    "SLOT5=\r\n"
    "SLOT6=\r\n"
    "SLOT7=\r\n"
)


def write_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, cfg_text):
    tmp_path = "/tmp/_test_plugin.cfg"
    with open(tmp_path, "wb") as f:
        f.write(cfg_text.encode("latin1"))
    subprocess.run([cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:PLUGIN.CFG"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file, tmp_path,
                    "0:PLUGIN.CFG"], check=True)
    if os.path.exists(tmp_path):
        os.remove(tmp_path)


def read_cfg_from_image(cpmcp_bin, img_file):
    tmp_path = "/tmp/_read_plugin.cfg"
    if os.path.exists(tmp_path):
        os.remove(tmp_path)
    res = subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file,
                          "0:PLUGIN.CFG", tmp_path],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if res.returncode != 0 or not os.path.exists(tmp_path):
        subprocess.run([cpmcp_bin, "-f", "wbw_hd1k_0", img_file,
                        "0:plugin.cfg", tmp_path],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if not os.path.exists(tmp_path):
        return ""
    with open(tmp_path, "rb") as f:
        data = f.read()
    os.remove(tmp_path)
    raw = data.split(b"\x1a")[0]
    return raw.decode("latin1", errors="replace")


def run_test():
    print("=" * 65)
    print("  SE.COM PLUGIN.CFG Save & Autoload Round-Trip Test")
    print("=" * 65)

    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = find_paths()

    # Reset default PLUGIN.CFG on disk
    write_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, DEFAULT_CFG)

    print("[*] Launching RomWBW on RC2014 emulator...", flush=True)
    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave,
                            close_fds=True)
    os.close(slave)

    try:
        # Boot RomWBW CP/M
        ok, _ = read_until(master, b"Boot [H=Help]:", timeout=8.0)
        assert ok, "Failed to reach RomWBW boot prompt"
        time.sleep(0.5)
        os.write(master, b"c\r")
        ok, _ = read_until(master, b"B>", timeout=6.0)
        assert ok, "Failed to boot B>"
        time.sleep(0.5)
        os.write(master, b"c:\r")
        ok, _ = read_until(master, b"C>", timeout=8.0)
        assert ok, "Failed to switch to C>"
        print("[+] Switched to Drive C>.", flush=True)

        # 1. Launch SE.COM (Session 1)
        print("[*] Step 1: Launching SE.COM (Session 1)...", flush=True)
        time.sleep(0.5)
        os.write(master, b"se\r")
        ok, _ = read_until(master, b"Col 0", timeout=45.0)
        assert ok, "Failed to display splash screen"
        drain_all(master)
        print("[+] Step 1: SE.COM splash screen displayed.", flush=True)

        # 2. Enter Plugin Manager ('p')
        print("[*] Step 2: Entering Plugin Manager ('p')...", flush=True)
        time.sleep(0.5)
        os.write(master, b"p")
        ok, out = read_until(master, b"SE - Plugin Manager", timeout=8.0)
        assert ok, "Failed to enter Plugin Manager"
        ok, out_tbl = read_until(master, b"0..7:select", timeout=5.0)
        out += out_tbl

        assert b"WORDCNT" in out, "WORDCNT not found in Slot 0"
        assert b"ROT13" in out, "ROT13 not found in Slot 1"
        assert b"BEAUTIFY" in out, "BEAUTIFY not found in Slot 2"
        print("[+] Step 2: Initial autoloaded slots verified "
              "(WORDCNT, ROT13, BEAUTIFY).",
              flush=True)

        # 3. Unload Slot 1 (ROT13)
        print("[*] Step 3: Unloading Slot 1 (ROT13)...", flush=True)
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"1")
        ok, out_pop = read_until(master, b"Unload Slot 1?", timeout=4.0)
        assert ok, "Unload confirmation prompt missing"
        os.write(master, b"y")
        ok, out_u = read_until(master, b"(empty slot)", timeout=6.0)
        assert ok, "Failed to unload Slot 1"
        print("[+] Step 3: Slot 1 (ROT13) successfully unloaded.", flush=True)

        # 4. Load MIDPLUG.PRL (8KB) into next free slot (Slot 1)
        print("[*] Step 4: Loading MIDPLUG.PRL into Slot 1...", flush=True)
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"l")
        read_until(master, b"Load Plugin", timeout=4.0)
        time.sleep(0.1)
        os.write(master, b"MIDPLUG.PRL\r")
        ok, out_l = read_until(master, b"FAR (8KB)", timeout=8.0)
        assert ok and b"MIDPLUG" in out_l, "Failed to load MIDPLUG into Slot 1"
        print("[+] Step 4: MIDPLUG.PRL loaded into Slot 1 as 'FAR (8KB)'.",
              flush=True)

        # 5. Save configuration to PLUGIN.CFG ('s') and verify modal pop-up
        print("[*] Step 5: Saving configuration to PLUGIN.CFG ('s')...",
              flush=True)
        time.sleep(0.3)
        drain_all(master)
        os.write(master, b"s")
        ok, out_s = read_until(master, b"Press any key to continue",
                               timeout=6.0)
        assert ok, f"Save pop-up not displayed. Buffer: {repr(out_s)}"
        assert b"Save Plugin Configuration" in out_s, \
            "Save configuration modal pop-up title missing"
        assert b"[Saved to PLUGIN.CFG]" in out_s, \
            "Save configuration confirmation message missing"
        assert b"+------------------------------------------------+" in out_s, \
            "Save configuration modal pop-up border missing"
        print("[+] Step 5: 's' key successfully displayed modal pop-up and "
              "saved configuration to PLUGIN.CFG.", flush=True)

        # 6. Dismiss pop-up with Space, verify clean redraw, then exit ('q')
        print("[*] Step 6: Dismissing pop-up and exiting to CP/M...",
              flush=True)
        time.sleep(0.2)
        os.write(master, b" ")
        ok, _ = read_until(master, b"Up/Dn:select", timeout=5.0)
        assert ok, "Failed to redraw Plugin Manager upon modal dismissal"
        time.sleep(0.2)
        os.write(master, b"q")
        read_until(master, b"type   e  or  <Enter>   to edit", timeout=5.0)
        time.sleep(0.2)
        os.write(master, b"\x11")  # Ctrl+Q
        ok, _ = read_until(master, b"C>", timeout=6.0)
        assert ok, "Failed to exit SE.COM to CP/M prompt"
        print("[+] Step 6: Exited SE.COM cleanly to CP/M prompt.", flush=True)

        # 7. Verify PLUGIN.CFG on disk
        print("[*] Step 7: Verifying on-disk PLUGIN.CFG...", flush=True)
        cfg_disk = read_cfg_from_image(cpmcp_bin, img_file)
        print(f"[*] Step 7: On-disk PLUGIN.CFG contents:\n{cfg_disk.strip()}",
              flush=True)
        assert "SLOT0=WORDCNT.OVL" in cfg_disk, "SLOT0 missing WORDCNT"
        assert "SLOT1=MIDPLUG.PRL" in cfg_disk, "SLOT1 missing MIDPLUG"
        assert "SLOT2=BEAUTIFY.PRL" in cfg_disk, "SLOT2 missing BEAUTIFY"
        assert "SLOT3=" in cfg_disk, "SLOT3 not empty"
        print("[+] Step 7: On-disk PLUGIN.CFG verified: SLOT1 contains "
              "MIDPLUG.PRL.", flush=True)

        # 8. Relaunch SE.COM (Session 2 - testing autoload)
        print("[*] Step 8: Relaunching SE.COM (Session 2)...", flush=True)
        time.sleep(0.5)
        os.write(master, b"se\r")
        ok, _ = read_until(master, b"Col 0", timeout=45.0)
        assert ok, "Failed to display splash screen on relaunch"
        drain_all(master)
        print("[+] Step 8: SE.COM relaunched successfully.", flush=True)

        # 9. Enter Plugin Manager ('p') on second launch
        print("[*] Step 9: Entering Plugin Manager on second launch...",
              flush=True)
        time.sleep(0.5)
        os.write(master, b"p")
        ok, out2 = read_until(master, b"SE - Plugin Manager", timeout=8.0)
        assert ok, "Failed to enter Plugin Manager on relaunch"
        ok, out2_tbl = read_until(master, b"0..7:select", timeout=5.0)
        out2 += out2_tbl

        tbl_str = out2.decode('latin1', 'replace')
        print(f"[*] Step 9: Relaunched Plugin Manager table:\n{tbl_str}")
        assert b"WORDCNT" in out2, "WORDCNT not autoloaded in Slot 0"
        assert b"MIDPLUG" in out2, "MIDPLUG not autoloaded in Slot 1"
        assert b"FAR (8KB)" in out2, "MIDPLUG 8KB mode not displayed"
        assert b"BEAUTIFY" in out2, "BEAUTIFY not autoloaded in Slot 2"
        print("[+] Step 9: Autoload on relaunch verified: "
              "MIDPLUG.PRL successfully loaded!",
              flush=True)

        # 10. Clean exit back to CP/M prompt
        print("[*] Step 10: Exiting second session cleanly to CP/M...",
              flush=True)
        time.sleep(0.3)
        os.write(master, b"q")
        read_until(master, b"type   e  or  <Enter>   to edit", timeout=5.0)
        time.sleep(0.2)
        os.write(master, b"\x11")  # Ctrl+Q
        ok, _ = read_until(master, b"C>", timeout=6.0)
        assert ok, "Failed to exit second SE.COM session to CP/M prompt"
        print("[+] Step 10: Clean exit from second session confirmed.",
              flush=True)

        print("\n" + "=" * 65)
        print("  PLUGIN.CFG SAVE & RELOAD TEST PASSED 100%!")
        print("=" * 65)
        return True

    finally:
        # Restore default PLUGIN.CFG
        try:
            write_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, DEFAULT_CFG)
        except Exception:
            pass
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
    success = run_test()
    sys.exit(0 if success else 1)
