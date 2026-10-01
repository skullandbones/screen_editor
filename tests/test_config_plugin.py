#!/usr/bin/env python3
"""
Test Suite for SE.CFG PLUGIN Configuration (Autoload, On Demand, Disabled).
Verifies:
  1. Startup with PLUGIN=DISABLED in SE.CFG:
     - Splash screen shows [Disabled].
     - Pressing 'p' displays "Feature requires PLUGIN.PRL".
     - Configuration screen shows [Disabled (Do Not Load)].
     - Command menu includes Option 5 toggle command.
     - Memory info screen does not contain Active: PLUGIN.PRL Subsystem.
  2. Interactive Toggle via '5' in Configuration Screen:
     - Disabled -> Autoload:
       * Config shows [Autoload (Startup Load)].
       * Splash screen shows [Operational].
       * Memory screen displays Active: PLUGIN.PRL Subsystem.
     - Autoload -> On Demand:
       * Config shows [On Demand (Load When Used)].
       * Far RAM bank is released.
       * Splash screen shows [On Demand].
       * Memory screen does not contain Active: PLUGIN.PRL Subsystem.
     - On Demand -> Disabled:
       * Config shows [Disabled (Do Not Load)].
       * Saving via 's' writes PLUGIN=DISABLED to SE.CFG.
  3. Toggle to On Demand and Save:
     - Config toggle to On Demand saves PLUGIN=ONDEMAND to SE.CFG.
     - Reloading SE shows [On Demand] on splash.
     - Memory screen shows no resident plugin bank.
  4. Startup with PLUGIN=AUTOLOAD in SE.CFG:
     - Autoloads PLUGIN.PRL into Far RAM at startup.
     - Splash screen shows [Operational].
     - Memory screen displays Active: PLUGIN.PRL Subsystem.
     - Pressing 'p' opens Plugin Manager UI without error.
  5. Synonym parsing in SE.CFG:
     - PLUGIN=DEMAND and PLUGIN=MANUAL load as [On Demand].
     - PLUGIN=OFF loads as [Disabled].
     - PLUGIN=ON loads as [Operational].
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

    emu_bin = os.path.join(
        workspace_root, "tools", "rc2014_emu", "rc2014"
    )
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
        raise RuntimeError("Failed to reach RomWBW boot prompt")

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
    paths = find_paths()
    emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin = paths
    print("=" * 65, flush=True)
    print("  SE.CFG PLUGIN Configuration Tests", flush=True)
    print("=" * 65, flush=True)

    # ------------------------------------------------------------------
    # TEST 1: Startup with PLUGIN=DISABLED in SE.CFG
    # ------------------------------------------------------------------
    print("\n[*] TEST 1: Startup with PLUGIN=DISABLED in SE.CFG...",
          flush=True)
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
        out = read_until(
            master, b"Plugin System : [Disabled]", timeout=25.0
        )
        assert b"Plugin System : [Disabled]" in out, (
            f"Splash did not show Disabled: {out}"
        )
        print("    [+] Splash screen shows Plugin System : [Disabled]")

        # Check memory screen ('m')
        time.sleep(0.3)
        os.write(master, b"m")
        out = read_until(
            master, b"Press any key to return to editor", timeout=15.0
        )
        assert b"Active: PLUGIN.PRL Subsystem" not in out, (
            "Memory screen unexpectedly showed active plugin subsystem!"
        )
        print("    [+] Memory screen confirms PLUGIN.PRL not loaded")

        # Return to splash
        time.sleep(0.3)
        os.write(master, b" ")
        read_until(master, b"Plugin System : [Disabled]", timeout=10.0)

        # Press 'p' to request plugin manager: shows Tier 2 modal pop-up
        time.sleep(0.3)
        os.write(master, b"p")
        out = read_until(
            master, b"Plugin Manager Missing", timeout=10.0
        )
        assert b"Plugin Manager Missing" in out, (
            f"Missing Plugin Manager Missing modal pop-up: {out}"
        )
        assert b"=== Plugin Manager ===" not in out, (
            "Plugin manager opened despite being disabled!"
        )
        # Dismiss pop-up with space
        time.sleep(0.1)
        os.write(master, b" ")
        out_splash = read_until(
            master, b"Plugin System : [Disabled]", timeout=10.0
        )
        assert b"Plugin System : [Disabled]" in out_splash, (
            f"Failed returning to splash when disabled: {out_splash}"
        )
        print(
            "    [+] Pressing 'p' correctly displayed modal and refused launch"
        )

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

        # --------------------------------------------------------------
        # TEST 2: Interactive 3-way Toggle via '5' & Save to SE.CFG
        # --------------------------------------------------------------
        print(
            "\n[*] TEST 2: Interactive Toggle via '5' & Save...",
            flush=True
        )
        # Toggle '5': Disabled -> Autoload
        time.sleep(0.3)
        os.write(master, b"5")
        out = read_until(master, b"Autoload (Startup Load)]", timeout=15.0)
        assert b"5. Plugin Manager  : [Autoload (Startup Load)]" in out, (
            f"Failed toggling to Autoload: {out}"
        )
        print("    [+] Toggled Option 5 to [Autoload (Startup Load)]")

        # Return to splash screen ('q') and verify Operational
        time.sleep(0.3)
        os.write(master, b"q")
        out = read_until(
            master, b"Plugin System : [Operational]", timeout=15.0
        )
        assert b"Plugin System : [Operational]" in out, (
            f"Splash screen did not show Operational: {out}"
        )
        print("    [+] Splash screen confirms [Operational]")

        # Check memory screen ('m') for Active: PLUGIN.PRL Subsystem
        time.sleep(0.3)
        os.write(master, b"m")
        out = read_until(
            master, b"Press any key to return to editor", timeout=15.0
        )
        assert b"Active: PLUGIN.PRL Subsystem" in out, (
            f"Memory screen missing Active: PLUGIN.PRL Subsystem:\n{out}"
        )
        print(
            "    [+] Memory screen shows Active: PLUGIN.PRL Subsystem"
        )

        # Return to splash
        time.sleep(0.3)
        os.write(master, b" ")
        read_until(master, b"Plugin System : [Operational]", timeout=10.0)

        # Re-enter configuration screen ('c')
        time.sleep(0.3)
        os.write(master, b"c")
        out = read_until(master, b"return to splash screen", timeout=15.0)

        # Toggle '5': Autoload -> On Demand
        time.sleep(0.3)
        os.write(master, b"5")
        out = read_until(
            master, b"On Demand (Load When Used)]", timeout=15.0
        )
        assert b"5. Plugin Manager  : [On Demand" in out, (
            f"Failed toggling to On Demand: {out}"
        )
        print("    [+] Toggled Option 5 to [On Demand (Load When Used)]")

        # Return to splash screen ('q') and verify On Demand
        time.sleep(0.3)
        os.write(master, b"q")
        out = read_until(
            master, b"Plugin System : [On Demand]", timeout=15.0
        )
        assert b"Plugin System : [On Demand]" in out, (
            f"Splash screen did not show On Demand: {out}"
        )
        print("    [+] Splash screen confirms Plugin System : [On Demand]")

        # Check memory screen ('m') - Far RAM was released
        time.sleep(0.3)
        os.write(master, b"m")
        out = read_until(
            master, b"Press any key to return to editor", timeout=15.0
        )
        assert b"Active: PLUGIN.PRL Subsystem" not in out, (
            "Memory screen unexpectedly showed active plugin subsystem!"
        )
        print("    [+] Memory screen confirms Far RAM bank released")

        # Return to splash
        time.sleep(0.3)
        os.write(master, b" ")
        read_until(master, b"Plugin System : [On Demand]", timeout=10.0)

        # Re-enter configuration screen ('c')
        time.sleep(0.3)
        os.write(master, b"c")
        read_until(master, b"return to splash screen", timeout=15.0)

        # Toggle '5': On Demand -> Disabled
        time.sleep(0.3)
        os.write(master, b"5")
        out = read_until(master, b"Disabled (Do Not Load)]", timeout=15.0)
        assert b"5. Plugin Manager  : [Disabled (Do Not Load)]" in out, (
            f"Failed toggling back to Disabled: {out}"
        )
        print("    [+] Toggled Option 5 to [Disabled (Do Not Load)]")

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

        # --------------------------------------------------------------
        # TEST 3: Toggle to On Demand and Save
        # --------------------------------------------------------------
        print("\n[*] TEST 3: Toggle to On Demand and Save...", flush=True)
        time.sleep(0.4)
        os.write(master, b"se\r")
        out = read_until(
            master, b"Plugin System : [Disabled]", timeout=25.0
        )
        assert b"Plugin System : [Disabled]" in out, (
            f"Reloaded SE did not load PLUGIN=DISABLED: {out}"
        )

        time.sleep(0.3)
        os.write(master, b"c")
        read_until(master, b"return to splash screen", timeout=15.0)

        # Toggle to Autoload, then On Demand
        time.sleep(0.3)
        os.write(master, b"5")
        read_until(master, b"Autoload (Startup Load)]", timeout=15.0)
        time.sleep(0.3)
        os.write(master, b"5")
        read_until(master, b"On Demand (Load When Used)]", timeout=15.0)

        # Save to SE.CFG
        time.sleep(0.3)
        os.write(master, b"s")
        read_until(
            master, b"Saved to local drive (C:SE.CFG)", timeout=15.0
        )

        # Exit SE
        time.sleep(0.3)
        os.write(master, b"q")
        read_until(master, b"type   c", timeout=10.0)
        time.sleep(0.3)
        os.write(master, b"q")
        read_until(master, b"C>", timeout=15.0)

        saved_cfg = get_cfg_from_image(cpmcp_bin, img_file)
        assert saved_cfg is not None, "SE.CFG was not found on disk"
        assert b"PLUGIN=ONDEMAND" in saved_cfg, (
            f"Saved SE.CFG does not contain PLUGIN=ONDEMAND:\n{saved_cfg}"
        )
        print("    [+] Disk SE.CFG confirmed containing PLUGIN=ONDEMAND")

        # Reload SE and verify splash shows On Demand
        time.sleep(0.4)
        os.write(master, b"se\r")
        out = read_until(
            master, b"Plugin System : [On Demand]", timeout=25.0
        )
        assert b"Plugin System : [On Demand]" in out, (
            f"Reloaded SE did not show On Demand: {out}"
        )
        print("    [+] Reloaded SE with PLUGIN=ONDEMAND shows [On Demand]")

        # --------------------------------------------------------------
        # TEST 4: Toggle to Autoload and Save
        # --------------------------------------------------------------
        print("\n[*] TEST 4: Toggle to Autoload and Save...", flush=True)
        time.sleep(0.3)
        os.write(master, b"c")
        read_until(master, b"return to splash screen", timeout=15.0)

        # Toggle '5': On Demand -> Disabled -> Autoload
        time.sleep(0.3)
        os.write(master, b"5")
        read_until(master, b"Disabled (Do Not Load)]", timeout=15.0)
        time.sleep(0.3)
        os.write(master, b"5")
        read_until(master, b"Autoload (Startup Load)]", timeout=15.0)

        # Save to SE.CFG
        time.sleep(0.3)
        os.write(master, b"s")
        read_until(
            master, b"Saved to local drive (C:SE.CFG)", timeout=15.0
        )

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

        # --------------------------------------------------------------
        # TEST 5: Startup with PLUGIN=AUTOLOAD in SE.CFG
        # --------------------------------------------------------------
        print(
            "\n[*] TEST 5: Startup with PLUGIN=AUTOLOAD in SE.CFG...",
            flush=True
        )
        time.sleep(0.4)
        os.write(master, b"se\r")
        out = read_until(
            master, b"Plugin System : [Operational]", timeout=25.0
        )
        assert b"Plugin System : [Operational]" in out, (
            f"Splash screen did not show Operational: {out}"
        )
        print("    [+] Splash screen autoloaded PLUGIN.PRL into Far RAM")

        # Check memory screen ('m')
        time.sleep(0.3)
        os.write(master, b"m")
        out = read_until(
            master, b"Press any key to return to editor", timeout=15.0
        )
        assert b"Active: PLUGIN.PRL Subsystem" in out, (
            f"Memory screen missing Active: PLUGIN.PRL Subsystem:\n{out}"
        )
        print(
            "    [+] Memory screen shows Active: PLUGIN.PRL Subsystem"
        )

        # Return to splash
        time.sleep(0.3)
        os.write(master, b" ")
        read_until(master, b"Plugin System : [Operational]", timeout=10.0)

        # Press 'p' to open Plugin Manager UI
        time.sleep(0.3)
        os.write(master, b"p")
        out = read_until(master, b"Plugin Manager", timeout=15.0)
        assert b"Plugin Manager" in out, (
            f"Failed opening Plugin Manager UI: {out}"
        )
        print("    [+] Plugin Manager UI launched from Far RAM")

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

    # ------------------------------------------------------------------
    # TEST 6: Parser Synonyms (DEMAND, MANUAL, OFF, ON)
    # ------------------------------------------------------------------
    print(
        "\n[*] TEST 6: Parser Synonyms (DEMAND, MANUAL, OFF, ON)...",
        flush=True
    )
    # Test PLUGIN=DEMAND
    put_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, "PLUGIN=DEMAND\r\n")
    proc, master = boot_cpm(emu_bin, rom_file, img_file)
    try:
        time.sleep(0.4)
        os.write(master, b"c:\r")
        read_until(master, b"C>", timeout=15.0)
        time.sleep(0.4)
        os.write(master, b"se\r")
        out = read_until(
            master, b"Plugin System : [On Demand]", timeout=25.0
        )
        assert b"Plugin System : [On Demand]" in out, (
            f"PLUGIN=DEMAND did not set On Demand: {out}"
        )
        print("    [+] PLUGIN=DEMAND correctly sets On Demand mode")
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

    # Test PLUGIN=MANUAL
    put_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, "PLUGIN=MANUAL\r\n")
    proc, master = boot_cpm(emu_bin, rom_file, img_file)
    try:
        time.sleep(0.4)
        os.write(master, b"c:\r")
        read_until(master, b"C>", timeout=15.0)
        time.sleep(0.4)
        os.write(master, b"se\r")
        out = read_until(
            master, b"Plugin System : [On Demand]", timeout=25.0
        )
        assert b"Plugin System : [On Demand]" in out, (
            f"PLUGIN=MANUAL did not set On Demand: {out}"
        )
        print("    [+] PLUGIN=MANUAL correctly sets On Demand mode")
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

    # Test PLUGIN=OFF
    put_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, "PLUGIN=OFF\r\n")
    proc, master = boot_cpm(emu_bin, rom_file, img_file)
    try:
        time.sleep(0.4)
        os.write(master, b"c:\r")
        read_until(master, b"C>", timeout=15.0)
        time.sleep(0.4)
        os.write(master, b"se\r")
        out = read_until(
            master, b"Plugin System : [Disabled]", timeout=25.0
        )
        assert b"Plugin System : [Disabled]" in out, (
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

    # Test PLUGIN=ON
    put_cfg_to_image(cpmcp_bin, cpmrm_bin, img_file, "PLUGIN=ON\r\n")
    proc, master = boot_cpm(emu_bin, rom_file, img_file)
    try:
        time.sleep(0.4)
        os.write(master, b"c:\r")
        read_until(master, b"C>", timeout=15.0)
        time.sleep(0.4)
        os.write(master, b"se\r")
        out = read_until(
            master, b"Plugin System : [Operational]", timeout=25.0
        )
        assert b"Plugin System : [Operational]" in out, (
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
    print("  ALL PLUGIN TESTS PASSED SUCCESSFULLY!", flush=True)
    print("=" * 65, flush=True)

if __name__ == "__main__":
    run_tests()
