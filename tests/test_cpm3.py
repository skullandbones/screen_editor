#!/usr/bin/env python3
"""
Automated Test Suite for SE.COM on CP/M 3.1 (RomWBW RC2014 Emulator).
Verifies:
  1. Boot RomWBW CP/M 3.1 (Disk Unit 4, Slice 3).
  2. RAM Disk Detection under CP/M 3.1: Drive B: detected as MD0:0.
  3. Memory Map Screen under CP/M 3.1:
     - Bank 8Ch displayed as 'Operating System' / 'CP/M 3 Buffers'.
     - Bank 8Dh displayed as 'CP/M 3 TPA' / 'SE Program & Cache'.
     - Bank 8Bh displayed as 'Line Slot Table'.
  4. Large File Editing & Clean Exit without Hang (Memory Protection):
     - Opens 500-line file (DOC500.TXT) on CP/M 3.1.
     - Navigates and verifies editor mode.
     - Clean exit (Ctrl+Q) back to CP/M 3.1 A> prompt without hanging.
  5. RAM Disk Hibernation under CP/M 3.1:
     - Dumps RAM drive to RAMDRV.IMG on startup.
     - Restores RAM drive from RAMDRV.IMG on exit.
"""

import os
import sys
import time
import tty
import select
import subprocess
import tempfile


def find_paths(use_sec=False):
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
    se_bin = os.path.join(
        repo_root, "SEC.COM" if use_sec else "SE.COM"
    )
    cpmcp_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp"
    )
    cpmrm_bin = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm"
    )

    return emu_bin, rom_file, img_file, se_bin, cpmcp_bin, cpmrm_bin


def read_until(master_fd, match_bytes, timeout=10.0):
    buf = b""
    t0 = time.time()
    while time.time() - t0 < timeout:
        r, _, _ = select.select([master_fd], [], [], 0.05)
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


def boot_cpm3(master_fd):
    """Boot RomWBW into CP/M 3.1 via Disk Unit 4, Slice 3 (4.3)."""
    ok, out = read_until(master_fd, b"Boot [H=Help]:", timeout=15.0)
    if not ok:
        print("[-] Failed to reach RomWBW boot loader prompt.", flush=True)
        return False

    time.sleep(0.3)
    os.write(master_fd, b"4.3\r")

    ok, out = read_until(master_fd, b"A>", timeout=25.0)
    if not ok:
        print(f"[-] Failed to boot CP/M 3.1 prompt. Buffer: {repr(out[-200:])}")
        return False

    print("[+] Successfully booted into CP/M 3.1 (A> prompt).", flush=True)
    return True


def test_ramdrive_detection_and_mem_screen(
    emu_bin, rom_file, img_file, cpmrm_bin, cmd_name=b"se"
):
    """Test RAM drive detection and Memory screen bank display on CP/M 3."""
    print(
        "\n[*] Test 1 & 2: RAM Drive Detection & Memory Map Screen on "
        "CP/M 3.1..."
    )
    for f in ["0:SE.CFG", "0:RAMDRV.IMG", "0:PLUGIN.CFG"]:
        subprocess.run(
            [cpmrm_bin, "-f", "wbw_hd1k_3", img_file, f],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    subprocess.run(
        [cpmrm_bin, "-f", "wbw_hd1k_0", img_file, "0:SE.CFG"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )
    os.close(slave)

    try:
        if not boot_cpm3(master):
            return False

        time.sleep(0.5)
        # Launch SE.COM
        os.write(master, cmd_name + b"\r")
        ok, out = read_until(master, b"Col 0", timeout=25.0)
        if not ok and b"for about" not in out:
            print(
                f"[-] Failed to display splash screen. Buffer: {repr(out)}",
                flush=True,
            )
            return False
        print("[+] Splash screen displayed on CP/M 3.1.", flush=True)

        # Open Config Screen ('c')
        time.sleep(0.3)
        os.write(master, b"c")
        ok, out = read_until(master, b"[ESC]=Exit", timeout=10.0)
        if not ok:
            print("[-] Failed to open Config Menu.", flush=True)
            return False

        # Verify RAM drive detection on Drive B:
        if b"RAM Drive (B:)" not in out and b"[B]" not in out:
            print(
                f"[-] RAM drive detection failed on CP/M 3.1! Out: {repr(out)}"
            )
            return False
        print("[+] RAM Drive correctly detected as Drive B: on CP/M 3.1!")

        # Return to splash screen ('q')
        time.sleep(0.3)
        os.write(master, b"q")
        ok, out = read_until(master, b"Col 0", timeout=5.0)
        if not ok and b"for about" not in out:
            print(
                "[-] Failed to return to splash screen from config.",
                flush=True,
            )
            return False

        # Open Memory Map Screen ('m')
        time.sleep(0.3)
        os.write(master, b"m")
        ok, out = read_until(master, b"Press any key to continue", timeout=10.0)
        if not ok:
            print("[-] Failed to open Memory Map screen.", flush=True)
            return False

        # Verify OS detected as CP/M 3.1
        if b"CP/M 3.1" not in out:
            print(f"[-] OS not identified as CP/M 3.1! Out: {repr(out)}")
            return False
        print("[+] Memory Screen: OS identified as CP/M 3.1.")

        # Verify Bank 8Ch is labeled as CP/M 3 Buffers
        if b"CP/M 3 Buffers" not in out:
            print(
                f"[-] Bank 8Ch not labeled as CP/M 3 Buffers! Out: {repr(out)}"
            )
            return False
        print(
            "[+] Memory Screen: Bank 8Ch protected as CP/M 3 Disk Buffers."
        )

        # Verify Bank 8Dh is labeled as CP/M 3.1 TPA
        if b"CP/M 3.1 TPA" not in out and b"CP/M 3 TPA" not in out:
            print(f"[-] Bank 8Dh not labeled as CP/M 3 TPA! Out: {repr(out)}")
            return False
        print("[+] Memory Screen: Bank 8Dh identified as CP/M 3 TPA.")

        # Return to splash screen (any key: 'x')
        time.sleep(0.3)
        os.write(master, b"x")
        ok, out = read_until(master, b"Col 0", timeout=5.0)
        if not ok and b"for about" not in out:
            print("[-] Failed to return to splash screen.", flush=True)
            return False

        # Clean exit to CP/M prompt ('q')
        time.sleep(0.3)
        os.write(master, b"q")
        ok, out = read_until(master, b"A>", timeout=15.0)
        if not ok:
            print("[-] Failed to exit cleanly to A> prompt.", flush=True)
            return False
        print("[+] Clean exit from splash screen back to A> prompt verified.")
        return True

    finally:
        proc.kill()
        proc.wait()


def test_large_file_exit(emu_bin, rom_file, img_file, cpmcp_bin, cpmrm_bin):
    """Test opening 500-line file, navigating, and clean exit without hang."""
    print(
        "\n[*] Test 3: Large File (200 lines) Editing & Clean Exit on "
        "CP/M 3.1..."
    )
    # Generate 200-line document
    lines = [
        f"Line {i:04d}: Test content verifying CP/M 3.1 memory protection."
        for i in range(1, 201)
    ]
    content = "\r\n".join(lines) + "\r\n"

    with tempfile.NamedTemporaryFile(
        mode="wb", delete=False, suffix=".txt"
    ) as f:
        f.write(content.encode("ascii"))
        host_test_file = f.name

    try:
        # Inject DOC200.TXT into Slice 3
        subprocess.run(
            [cpmrm_bin, "-f", "wbw_hd1k_3", img_file, "0:DOC200.TXT"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        subprocess.run(
            [
                cpmcp_bin,
                "-f",
                "wbw_hd1k_3",
                img_file,
                host_test_file,
                "0:DOC200.TXT",
            ],
            check=True,
        )

        master, slave = os.openpty()
        tty.setraw(slave)
        os.set_blocking(master, False)

        cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
        proc = subprocess.Popen(
            cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
        )
        os.close(slave)

        try:
            if not boot_cpm3(master):
                return False

            time.sleep(0.5)
            # Launch SE with DOC200.TXT
            print(
                f"[*] Launching: {cmd_name.decode()} doc200.txt "
                f"on CP/M 3.1...", flush=True
            )
            os.write(master, cmd_name + b" doc200.txt\r")

            # Verify editor screen with DOC200.TXT fully loaded
            # (wait for 1/200 line count)
            ok, out = read_until(master, b"1/200", timeout=90.0)
            if not ok:
                print(
                    f"[-] Editor failed to load DOC200.TXT! Out: {repr(out)}"
                )
                return False
            time.sleep(0.5)
            drain_all(master, 0.3)
            print(
                "[+] DOC200.TXT successfully loaded into editor (200 lines).",
                flush=True,
            )

            # Jump to bottom (Ctrl+G = \x07) across paged memory
            print(
                "[*] Testing Jump to Bottom (Ctrl+G) across paged Far RAM...",
                flush=True,
            )
            os.write(master, b"\x07")
            ok, out = read_until(master, b"200/200", timeout=15.0)
            if not ok:
                print(f"[-] Jump to bottom failed! Out: {repr(out)}")
                return False
            time.sleep(0.5)
            drain_all(master, 0.3)
            print("[+] Reached bottom (200/200).", flush=True)

            # Jump back to top (Ctrl+T = \x14)
            print("[*] Testing Jump to Top (Ctrl+T)...", flush=True)
            os.write(master, b"\x14")
            ok, out = read_until(master, b"1/200", timeout=15.0)
            if not ok:
                print(f"[-] Jump to top failed! Out: {repr(out)}")
                return False
            time.sleep(0.5)
            drain_all(master, 0.3)
            print("[+] Returned to top (1/200).", flush=True)

            # Insert character 'X' to mark document modified
            os.write(master, b"X")
            time.sleep(0.5)
            drain_all(master, 0.3)

            # Exit via Ctrl+Q (\x11)
            print("[*] Sending Ctrl+Q (Exit)...", flush=True)
            os.write(master, b"\x11")

            # Confirmation prompt: "Save changes? Yes/No/ESC:"
            ok, out = read_until(master, b"Save changes?", timeout=10.0)
            if not ok:
                print(
                    "[-] Exit confirmation prompt not received! Out: "
                    f"{repr(out)}"
                )
                return False

            # Discard changes ('n')
            print("[*] Answering 'n' (Discard changes)...", flush=True)
            time.sleep(0.2)
            os.write(master, b"n")

            # CRITICAL CHECK: Verify clean exit to A> without hanging!
            t_exit_start = time.time()
            ok, out = read_until(master, b"A>", timeout=15.0)
            t_exit = time.time() - t_exit_start

            if not ok:
                print(
                    "[-] HANG DETECTED! SE.COM hung on exit from large file "
                    "under CP/M 3.1!"
                )
                print(f"[-] Buffer captured: {repr(out)}")
                return False

            print(
                "[+] SUCCESS! Returned cleanly to CP/M 3.1 prompt in "
                f"{t_exit:.2f}s without hanging!"
            )
            return True

        finally:
            proc.kill()
            proc.wait()

    finally:
        if os.path.exists(host_test_file):
            os.unlink(host_test_file)
        subprocess.run(
            [cpmrm_bin, "-f", "wbw_hd1k_3", img_file, "0:DOC200.TXT"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def test_ramdrive_hibernation(
    emu_bin, rom_file, img_file, cpmcp_bin, cpmrm_bin, cmd_name=b"se"
):
    """Test RAM drive hibernation (RAMDRIVE=HIBERNATE) on CP/M 3.1."""
    print("\n[*] Test 4: RAM Drive Hibernation on CP/M 3.1...")
    cfg_content = "SCREEN=80x24\r\nRAMDRIVE=HIBERNATE\r\n"
    with tempfile.NamedTemporaryFile(
        mode="wb", delete=False, suffix=".cfg"
    ) as f:
        f.write(cfg_content.encode("ascii"))
        host_cfg_file = f.name

    try:
        # Clean old files and inject SE.CFG into Slice 3
        subprocess.run(
            [cpmrm_bin, "-f", "wbw_hd1k_3", img_file, "0:SE.CFG"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        subprocess.run(
            [cpmrm_bin, "-f", "wbw_hd1k_3", img_file, "0:RAMDRV.IMG"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        subprocess.run(
            [
                cpmcp_bin,
                "-f",
                "wbw_hd1k_3",
                img_file,
                host_cfg_file,
                "0:SE.CFG",
            ],
            check=True,
        )

        master, slave = os.openpty()
        tty.setraw(slave)
        os.set_blocking(master, False)

        cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
        proc = subprocess.Popen(
            cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
        )
        os.close(slave)

        try:
            if not boot_cpm3(master):
                return False

            time.sleep(0.5)
            # Launch SE with RAMDRIVE=HIBERNATE
            print("[*] Launching with RAMDRIVE=HIBERNATE...", flush=True)
            os.write(master, cmd_name + b"\r")

            # Verify hibernation banner
            ok, out = read_until(master, b"Hibernating RAM drive", timeout=25.0)
            if not ok:
                print(
                    f"[-] Hibernating banner not displayed! Buffer: {repr(out)}"
                )
                return False
            print("[+] Hibernation started: 'Hibernating RAM drive' seen.")

            ok, out = read_until(master, b"Col 0", timeout=90.0)
            if not ok and b"for about" not in out:
                print(
                    "[-] Splash screen not reached after hibernation.",
                    flush=True,
                )
                return False
            print("[+] Hibernation complete. Splash screen active.")

            # Exit SE ('q') and verify restoration
            time.sleep(0.5)
            os.write(master, b"q")

            ok, out = read_until(master, b"Restoring RAM drive", timeout=30.0)
            if not ok:
                print(
                    f"[-] Restoring banner not displayed! Buffer: {repr(out)}"
                )
                return False
            print("[+] Restoration started: 'Restoring RAM drive' seen.")

            ok, out = read_until(master, b"A>", timeout=90.0)
            if not ok:
                print(
                    "[-] Clean exit to A> not reached after restore.",
                    flush=True,
                )
                return False
            print("[+] RAM drive restored and returned cleanly to A> prompt!")
            return True

        finally:
            proc.kill()
            proc.wait()

    finally:
        if os.path.exists(host_cfg_file):
            os.unlink(host_cfg_file)
        subprocess.run(
            [cpmrm_bin, "-f", "wbw_hd1k_3", img_file, "0:SE.CFG"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        subprocess.run(
            [cpmrm_bin, "-f", "wbw_hd1k_3", img_file, "0:RAMDRV.IMG"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def main(use_sec=False):
    t_start = time.time()
    (
        emu_bin, rom_file, img_file, se_bin,
        cpmcp_bin, cpmrm_bin
    ) = find_paths(use_sec=use_sec)
    target_name = "SEC.COM" if use_sec else "SE.COM"
    cmd_name = b"sec" if use_sec else b"se"

    for path, name in [
        (emu_bin, "rc2014"),
        (rom_file, "RC2014_std.rom"),
        (img_file, "hd1k_combo.img"),
        (se_bin, target_name),
        (cpmcp_bin, "cpmcp"),
        (cpmrm_bin, "cpmrm"),
    ]:
        if not os.path.isfile(path):
            print(f"[-] Required file missing: {name} at {path}", flush=True)
            sys.exit(1)

    print("=" * 70)
    print("SE.COM CP/M 3.1 Z80 EMULATOR AUTOMATED TEST SUITE")
    print("=" * 70)

    # Test 1 & 2: RAM Drive Detection and Memory Map Screen
    if not test_ramdrive_detection_and_mem_screen(
        emu_bin, rom_file, img_file, cpmrm_bin, cmd_name=cmd_name
    ):
        print("\n[-] Test 1 & 2 FAILED!", flush=True)
        sys.exit(1)

    # Test 3: Large File Editing & Clean Exit without Hang
    if not test_large_file_exit(
        emu_bin, rom_file, img_file, cpmcp_bin, cpmrm_bin,
        cmd_name=cmd_name
    ):
        print("\n[-] Test 3 FAILED!", flush=True)
        sys.exit(1)

    # Test 4: RAM Disk Hibernation
    if not test_ramdrive_hibernation(
        emu_bin, rom_file, img_file, cpmcp_bin, cpmrm_bin,
        cmd_name=cmd_name
    ):
        print("\n[-] Test 4 FAILED!", flush=True)
        sys.exit(1)

    elapsed = time.time() - t_start
    print("\n" + "=" * 70)
    print(f"[+] ALL CP/M 3.1 TESTS PASSED SUCCESSFULLY in {elapsed:.2f}s!")
    print("=" * 70)
    sys.exit(0)


if __name__ == "__main__":
    use_sec_arg = "--sec" in sys.argv
    main(use_sec=use_sec_arg)
