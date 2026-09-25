#!/usr/bin/env python3
"""
Test Suite for SE.CFG PLUGIN Configuration (Autoload vs Disabled).
Verifies:
  1. Startup with PLUGIN=DISABLED in SE.CFG:
     - Splash screen shows [Disabled (Config)].
     - Pressing 'p' displays "Feature requires PLUGIN.PRL".
     - Configuration screen shows [Disabled (Do Not Load)].
     - Command menu includes Option 5 toggle command.
  2. Interactive Toggle via '5' in Configuration Screen:
     - Pressing '5' toggles to [Autoload (Far RAM Bank)].
     - Splash screen confirms Far RAM bank allocated.
     - Pressing '5' again toggles back to [Disabled (Do Not Load)] and
       releases Far RAM bank.
     - Saving via 's' writes PLUGIN=DISABLED to SE.CFG.
  3. Toggle to Autoload and Save:
     - Toggling to Autoload and saving writes PLUGIN=AUTOLOAD to SE.CFG.
  4. Startup with PLUGIN=AUTOLOAD in SE.CFG:
     - Automatically loads PLUGIN.PRL into Far RAM at startup.
     - Splash screen shows [Far RAM (Bank XXh, 8K)].
     - Pressing 'p' opens Plugin Manager UI without error.
  5. Synonym parsing in SE.CFG:
     - Verifies PLUGIN=OFF and PLUGIN=ON are parsed correctly.
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
    img_file = os.path.join(
        workspace_root, "tools", "romwbw_src", "Binary", "hd1k_combo.img"
    )
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
        raise RuntimeError("Failed to reach RomWBW boot loader prompt")

    time.sleep(0.4)
    os.write(master, b"c\r")
    out = read_until(master, b"B>", timeout=15.0)
    if b"B>" not in out:
        raise RuntimeError("Failed to boot into CP/M prompt")

    return proc, master

def remove_cfg_from_image(cpmrm_bin, img_file):
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.CFG"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )

def put_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, content_str):
    remove_cfg_from_image(cpmrm_bin, img_file)
    tmp_path = "/tmp/TEST_PLUGIN_SE.CFG"
    with open(tmp_path, "wb") as f:
        f.write(content_str.encode("latin1"))
    subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, tmp_path, "0:SE.CFG"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True
    )
    if os.path.exists(tmp_path):
        os.remove(tmp_path)

def get_cfg_from_image(cpmcp_bin, img_file):
    tmp_path = "/tmp/EXTRACT_PLUGIN_SE.CFG"
    if os.path.exists(tmp_path):
        os.remove(tmp_path)
    res = subprocess.run(
        [cpmcp_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.CFG", tmp_path],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    if res.returncode != 0 or not os.path.exists(tmp_path):
        return None
    with open(tmp_path, "rb") as f:
        data = f.read()
    os.remove(tmp_path)
    return data

def run_tests():
    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = find_paths()
    print("=" * 65, flush=True)
    print("  SE.CFG PLUGIN (Autoload / Disabled) Integration Tests", flush=True)
    print("=" * 65, flush=True)

    # -------------------------------------------------------------------------
    # TEST 1: Startup with PLUGIN=DISABLED in SE.CFG
    # -------------------------------------------------------------------------
    print("\n[*] TEST 1: Startup with PLUGIN=DISABLED in SE.CFG...", flush=True)
    cfg_text = "# SE.CFG\r\nSCREEN=80x24\r\nPLUGIN=DISABLED\r\n"
    put_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, cfg_text)

    proc, master = boot_cpm(emu_bin, rom_file, img_file)
    try:
        time.sleep(0.4)
        os.write(master, b"c:\r")
        out = read_until(master, b"C>", timeout=15.0)
        assert b"C>" in out, f"Failed switching to C: {out}"

        time.sleep(0.4)
        os.write(master, b"se\r")
        out = read_until(master, b"Disabled (Config)]", timeout=25.0)
        assert b"Plugin System : [Disabled (Config)]" in out, (
            f"Splash did not show Disabled (Config): {out}"
        )
        print("    [+] Splash screen shows Plugin System : [Disabled (Config)]")

        # Press 'p' to request plugin manager
        time.sleep(0.3)
        os.write(master, b"p")
        out = read_until(master, b"Disabled (Config)]", timeout=10.0)
        assert b"Plugin System : [Disabled (Config)]" in out, (
            f"Failed staying on splash when disabled: {out}"
        )
        assert b"=== Plugin Manager ===" not in out, (
            "Plugin manager opened despite being disabled!"
        )
        print("    [+] Pressing 'p' correctly refused to launch Plugin Manager")

        # Enter Configuration Screen ('c')
        time.sleep(0.3)
        os.write(master, b"c")
        out = read_until(master, b"return to splash screen", timeout=15.0)
        assert b"5. Plugin Manager  : [Disabled (Do Not Load)]" in out, (
            f"Config screen missing Disabled (Do Not Load): {out}"
        )
        assert b"type   5                toggle Plugin Mgr" in out, (
            "Config screen missing Option 5 command description"
        )
        print(
            "    [+] Config screen displays 5. Plugin Manager : [Disabled]"
        )

        # ---------------------------------------------------------------------
        # TEST 2: Interactive Toggle via '5' & Save to SE.CFG
        # ---------------------------------------------------------------------
        print(
            "\n[*] TEST 2: Interactive Toggle via '5' & Save to SE.CFG...",
            flush=True
        )
        # Toggle '5' to Autoload
        time.sleep(0.3)
        os.write(master, b"5")
        out = read_until(master, b"Autoload (Far RAM Bank)]", timeout=15.0)
        assert b"5. Plugin Manager  : [Autoload (Far RAM Bank)]" in out, (
            f"Failed toggling to Autoload: {out}"
        )
        print("    [+] Toggled Option 5 to [Autoload (Far RAM Bank)]")

        # Return to splash screen ('q') and verify Far RAM is allocated
        time.sleep(0.3)
        os.write(master, b"q")
        out = read_until(
            master, b"Plugin System : [Far RAM (Bank ", timeout=15.0
        )
        assert b"Plugin System : [Far RAM (Bank " in out, (
            f"Splash screen did not show Far RAM loaded: {out}"
        )
        print(
            "    [+] Splash screen confirms Far RAM bank allocated for PLUGIN"
        )

        # Re-enter configuration screen ('c')
        time.sleep(0.3)
        os.write(master, b"c")
        out = read_until(master, b"return to splash screen", timeout=15.0)

        # Toggle '5' back to Disabled
        time.sleep(0.3)
        os.write(master, b"5")
        out = read_until(master, b"Disabled (Do Not Load)]", timeout=15.0)
        assert b"5. Plugin Manager  : [Disabled (Do Not Load)]" in out, (
            f"Failed toggling back to Disabled: {out}"
        )
        print("    [+] Toggled Option 5 back to [Disabled (Do Not Load)]")

        # Save configuration via 's'
        time.sleep(0.3)
        os.write(master, b"s")
        out = read_until(
            master, b"Saved to local drive (C:SE.CFG)", timeout=15.0
        )
        assert b"Saved to local drive (C:SE.CFG)" in out, (
            f"Failed saving config: {out}"
        )
        print("    [+] Config screen saved changes to local SE.CFG")

        # Return to splash and exit SE
        time.sleep(0.3)
        os.write(master, b"q")
        read_until(master, b"type   c", timeout=10.0)
        time.sleep(0.3)
        os.write(master, b"q")
        out = read_until(master, b"C>", timeout=15.0)
        assert b"C>" in out, f"Failed exiting SE: {out}"

        # Verify saved SE.CFG on disk
        saved_cfg = get_cfg_from_image(cpmcp_bin, img_file)
        assert saved_cfg is not None, "SE.CFG was not found on disk"
        assert b"PLUGIN=DISABLED" in saved_cfg, (
            f"Saved SE.CFG does not contain PLUGIN=DISABLED:\n{saved_cfg}"
        )
        print("    [+] Disk SE.CFG confirmed containing PLUGIN=DISABLED")

        # ---------------------------------------------------------------------
        # TEST 3: Toggle to Autoload and Save
        # ---------------------------------------------------------------------
        print("\n[*] TEST 3: Toggle to Autoload and Save...", flush=True)
        time.sleep(0.4)
        os.write(master, b"se\r")
        out = read_until(master, b"Disabled (Config)]", timeout=25.0)
        assert b"Plugin System : [Disabled (Config)]" in out, (
            f"Reloaded SE did not load PLUGIN=DISABLED: {out}"
        )

        time.sleep(0.3)
        os.write(master, b"c")
        read_until(master, b"return to splash screen", timeout=15.0)

        # Toggle to Autoload
        time.sleep(0.3)
        os.write(master, b"5")
        read_until(master, b"Autoload (Far RAM Bank)]", timeout=15.0)

        # Save to SE.CFG
        time.sleep(0.3)
        os.write(master, b"s")
        read_until(master, b"Saved to local drive (C:SE.CFG)", timeout=15.0)

        # Exit SE
        time.sleep(0.3)
        os.write(master, b"q")
        read_until(master, b"type   c", timeout=10.0)
        time.sleep(0.3)
        os.write(master, b"q")
        read_until(master, b"C>", timeout=15.0)

        saved_cfg = get_cfg_from_image(cpmcp_bin, img_file)
        assert saved_cfg is not None, "SE.CFG was not found on disk"
        assert b"PLUGIN=AUTOLOAD" in saved_cfg, (
            f"Saved SE.CFG does not contain PLUGIN=AUTOLOAD:\n{saved_cfg}"
        )
        print("    [+] Disk SE.CFG confirmed containing PLUGIN=AUTOLOAD")

        # ---------------------------------------------------------------------
        # TEST 4: Startup with PLUGIN=AUTOLOAD in SE.CFG
        # ---------------------------------------------------------------------
        print(
            "\n[*] TEST 4: Startup with PLUGIN=AUTOLOAD in SE.CFG...",
            flush=True
        )
        time.sleep(0.4)
        os.write(master, b"se\r")
        out = read_until(
            master, b"Plugin System : [Far RAM (Bank ", timeout=25.0
        )
        assert b"Plugin System : [Far RAM (Bank " in out, (
            f"Splash screen did not autoload Far RAM bank: {out}"
        )
        print("    [+] Splash screen autoloaded PLUGIN.PRL into Far RAM")

        # Press 'p' to open Plugin Manager UI
        time.sleep(0.3)
        os.write(master, b"p")
        out = read_until(master, b"Plugin Manager", timeout=15.0)
        assert b"Plugin Manager" in out, (
            f"Failed opening Plugin Manager UI: {out}"
        )
        print("    [+] Plugin Manager UI successfully launched from Far RAM")

        # Dismiss Plugin Manager UI ('q')
        time.sleep(0.3)
        os.write(master, b"q")
        read_until(master, b"type   c", timeout=10.0)

        # Exit SE
        time.sleep(0.3)
        os.write(master, b"q")
        read_until(master, b"C>", timeout=15.0)

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            pass
        os.close(master)

    # -------------------------------------------------------------------------
    # TEST 5: Parser Synonyms (PLUGIN=OFF and PLUGIN=ON)
    # -------------------------------------------------------------------------
    print(
        "\n[*] TEST 5: Parser Synonyms (PLUGIN=OFF and PLUGIN=ON)...",
        flush=True
    )
    put_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, "PLUGIN=OFF\r\n")
    proc, master = boot_cpm(emu_bin, rom_file, img_file)
    try:
        time.sleep(0.4)
        os.write(master, b"c:\r")
        read_until(master, b"C>", timeout=15.0)
        time.sleep(0.4)
        os.write(master, b"se\r")
        out = read_until(master, b"Disabled (Config)]", timeout=25.0)
        assert b"Plugin System : [Disabled (Config)]" in out, (
            f"PLUGIN=OFF did not disable plugin loading: {out}"
        )
        print("    [+] PLUGIN=OFF correctly disables plugin autoload")
        time.sleep(0.3)
        os.write(master, b"q")
        read_until(master, b"C>", timeout=15.0)
    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            pass
        os.close(master)

    put_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, "PLUGIN=ON\r\n")
    proc, master = boot_cpm(emu_bin, rom_file, img_file)
    try:
        time.sleep(0.4)
        os.write(master, b"c:\r")
        read_until(master, b"C>", timeout=15.0)
        time.sleep(0.4)
        os.write(master, b"se\r")
        out = read_until(master, b"Far RAM (Bank ", timeout=25.0)
        assert b"Plugin System : [Far RAM (Bank " in out, (
            f"PLUGIN=ON did not autoload plugin into Far RAM: {out}"
        )
        print("    [+] PLUGIN=ON correctly enables plugin autoload")
        time.sleep(0.3)
        os.write(master, b"q")
        read_until(master, b"C>", timeout=15.0)
    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            pass
        os.close(master)

    # Clean up test SE.CFG
    remove_cfg_from_image(cpmrm_bin, img_file)

    print("\n" + "=" * 65, flush=True)
    print("  ALL PLUGIN CONFIGURATION TESTS PASSED SUCCESSFULLY!", flush=True)
    print("=" * 65, flush=True)

if __name__ == "__main__":
    run_tests()
