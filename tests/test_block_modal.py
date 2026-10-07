#!/usr/bin/env python3
"""
test_block_modal.py - Regression test for Block Mode Option A + 4 + 5.
Verifies:
1. Dynamic selection via Ctrl-B and status bar Field 4 human-readable format.
2. Enter in editor solidifies block (Point 4).
3. Ctrl-B in editor toggles/cancels active block (Option A).
4. Ctrl-K in block mode opens Tier 2 centered modal (50 cols x 7 rows).
5. Exact 50-col borders and no spill-over on any row of modal.
6. ESC in modal is safe NOP (leaves selection/block intact).
7. ^B in modal clears block and returns to normal editing.
8. Enter in modal solidifies block.
9. Ctrl-K on solidified block shows Marked Block header & Copy/Move actions.
"""

import os
import pty
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
    img_file = os.path.join(repo_root, "disks", "hd1k_combo.img")
    se_bin = os.path.join(repo_root, "SE.COM")
    cpmcp = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmcp"
    )
    cpmrm = os.path.join(
        workspace_root, "tools", "romwbw_src", "Tools", "Linux", "cpmrm"
    )
    return emu_bin, rom_file, img_file, se_bin, cpmcp, cpmrm, repo_root


def read_until(master_fd, match_bytes, timeout=10.0):
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
        time.sleep(0.01)
    return buf


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


def inject_file(cpmcp, cpmrm, img, local_path, user_disk):
    for fmt in ["wbw_hd1k_0", "wbw_hd1k_3"]:
        try:
            subprocess.run(
                [cpmrm, "-f", fmt, img, user_disk],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception:
            pass
    subprocess.run(
        [cpmcp, "-f", "wbw_hd1k_0", img, local_path, user_disk], check=True
    )


def test_block_modal_workflow():
    emu_bin, rom_file, img_file, se_bin, cpmcp, cpmrm, repo_root = find_paths()

    # Create test document with 4 lines
    test_doc_path = os.path.join(repo_root, "scratch_blk.txt")
    with open(test_doc_path, "wb") as f:
        f.write(b"Line One: Apple\r\nLine Two: Banana\r\n"
                b"Line Three: Cherry\r\nLine Four: Date\r\n")

    inject_file(cpmcp, cpmrm, img_file, se_bin, "0:SE.COM")
    inject_file(cpmcp, cpmrm, img_file, test_doc_path, "0:BLKTEST.TXT")

    master, slave = os.openpty()
    tty.setraw(slave)
    os.set_blocking(master, False)

    cmd = [emu_bin, "-b", "-r", rom_file, "-1", "-S", img_file]
    proc = subprocess.Popen(
        cmd,
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
    )
    os.close(slave)

    try:
        boot = read_until(master, b"Boot [", timeout=10.0)
        if b"Boot [" not in boot:
            print("[-] Boot prompt Boot [ not reached", file=sys.stderr)
            return False
        time.sleep(0.5)
        os.write(master, b"c\r")
        out_b = read_until(master, b"B>", timeout=10.0)
        if b"B>" not in out_b:
            print("[-] B> prompt not reached", file=sys.stderr)
            return False
        time.sleep(0.5)
        os.write(master, b"c:\r")
        out_c = read_until(master, b"C>", timeout=15.0)
        if b"C>" not in out_c:
            print("[-] C> prompt not reached", file=sys.stderr)
            return False
        time.sleep(0.5)

        # Launch editor
        drain_all(master)
        time.sleep(0.5)
        os.write(master, b"se\r")
        splash = read_until(master, b"Screen Editor", timeout=25.0)
        if b"Screen Editor" not in splash:
            print(f"[-] Splash screen not reached. Buffer: {repr(splash)}",
                  file=sys.stderr)
            return False

        # Enter editor mode with 'e'
        time.sleep(0.3)
        os.write(master, b"e")
        out_edit = read_until(master, b"^K: Editor keys", timeout=6.0)
        if b"^K: Editor keys" not in out_edit:
            print(f"[-] Failed to enter editor. Buffer: {repr(out_edit)}",
                  file=sys.stderr)
            return False

        # Type 3 test lines
        os.write(master, b"Line 1 Alpha\rLine 2 Beta\rLine 3 Gamma\r")
        time.sleep(0.3)
        # Move up to Line 1
        os.write(master, b"\x1b[A\x1b[A\x1b[A")
        time.sleep(0.3)
        drain_all(master)

        print("[+] Test 1: Start selection with Ctrl-B...", flush=True)
        os.write(master, b"\x02")  # Ctrl-B
        out = read_until(master, b"Sel: 0 chars", timeout=4.0)
        if b"Sel: 0 chars" not in out:
            print(f"[-] Ctrl-B failed to show 'Sel: 0 chars'. Got: {repr(out)}")
            return False
        print("[+] Test 1 PASSED: 'Sel: 0 chars' displayed on status bar.")

        print("[+] Test 1b: Move right on same line shows char count...",
              flush=True)
        os.write(master, b"\x1b[C")  # Right arrow
        out = read_until(master, b"Sel: 1 char ", timeout=4.0)
        if b"Sel: 1 char" not in out:
            print(f"[-] Failed to show 'Sel: 1 char'. Got: {repr(out)}")
            return False
        os.write(master, b"\x1b[C\x1b[C")  # Right arrow x2
        out = read_until(master, b"Sel: 3 chars", timeout=4.0)
        if b"Sel: 3 chars" not in out:
            print(f"[-] Failed to show 'Sel: 3 chars'. Got: {repr(out)}")
            return False
        print("[+] Test 1b PASSED: 'Sel: 1 char' and 'Sel: 3 chars' verified.")

        print("[+] Test 2: Cursor down expands selection to multi-line...",
              flush=True)
        os.write(master, b"\x1b[B")  # Down arrow
        out = read_until(master, b"Sel: 2 lines", timeout=4.0)
        if b"Sel: 2 lines" not in out:
            print(f"[-] Failed to show 'Sel: 2 lines'. Got: {repr(out)}")
            return False
        print("[+] Test 2 PASSED: 'Sel: 2 lines' displayed.")

        print("[+] Test 3: Enter in editor solidifies block (Point 4)...",
              flush=True)
        os.write(master, b"\r")  # Enter
        out = read_until(master, b"Block: 2 lines", timeout=4.0)
        if b"Block: 2 lines" not in out:
            print(f"[-] Enter failed to solidify block. Got: {repr(out)}")
            return False
        print("[+] Test 3 PASSED: 'Block: 2 lines' displayed on Enter.")

        print("[+] Test 4: Ctrl-B in editor cancels/clears block (Option A)...",
              flush=True)
        os.write(master, b"\x02")  # Ctrl-B
        out = read_until(master, b"^K: Editor keys", timeout=4.0)
        if b"^K: Editor keys" not in out:
            print(f"[-] Ctrl-B failed to clear block. Got: {repr(out)}")
            return False
        print("[+] Test 4 PASSED: Ctrl-B cleared block back to Editor keys.")

        print("[+] Test 5: Open Block Modal on dynamic selection (^K)...",
              flush=True)
        os.write(master, b"\x02")  # Ctrl-B
        read_until(master, b"Sel: 1 line", timeout=4.0)
        os.write(master, b"\x1b[B")  # Down arrow
        read_until(master, b"Sel: 2 lines", timeout=4.0)

        # Press Ctrl-K (\x0b) to open Block Operations modal
        os.write(master, b"\x0b")
        expected_line6 = b"|  [^D]=Del  [^S]=Save  [^B]=Clear  [ESC]=Close  |"
        modal = read_until(master, expected_line6, timeout=6.0)
        if expected_line6 not in modal:
            print("[-] Modal did not show line 6. Got: "
                  f"{repr(modal)}")
            return False

        # Verify exact box contents
        expected_title = b"|                Block Operations                |"
        expected_status = b"|               Selection: 2 lines               |"
        expected_line5 = b"|  [Enter]=Lock/Set    [^C]=Copy    [^X]=Move    |"
        expected_border = b"+------------------------------------------------+"

        if expected_title not in modal:
            print(f"[-] Missing expected title. Got: {repr(modal)}")
            return False
        if expected_status not in modal:
            print(f"[-] Missing expected status row. Got: {repr(modal)}")
            return False
        if expected_line5 not in modal:
            print(f"[-] Missing expected line 5. Got: {repr(modal)}")
            return False
        if expected_border not in modal:
            print(f"[-] Missing expected border. Got: {repr(modal)}")
            return False
        print("[+] Test 5 PASSED: 50x7 modal displayed with exact borders.")

        print("[+] Test 6: ESC in modal is safe NOP (leaves selection)...",
              flush=True)
        os.write(master, b"\x1b")  # ESC
        out_esc = read_until(master, b"Sel: 2 lines", timeout=5.0)
        if b"Sel: 2 lines" not in out_esc:
            print(f"[-] ESC did not restore selection. Got: {repr(out_esc)}")
            return False
        print("[+] Test 6 PASSED: ESC dismissed modal with selection intact.")

        print("[+] Test 7: ^B in modal clears block...", flush=True)
        os.write(master, b"\x0b")  # Open modal again
        read_until(master, b"Block Operations", timeout=4.0)
        os.write(master, b"\x02")  # Ctrl-B inside modal
        out_clr = read_until(master, b"^K: Editor keys", timeout=5.0)
        if b"^K: Editor keys" not in out_clr:
            print(f"[-] ^B in modal did not clear block. Got: {repr(out_clr)}")
            return False
        print("[+] Test 7 PASSED: ^B in modal cleared block.")

        print("[+] Test 8: Enter in modal solidifies block...", flush=True)
        # Move up to Line 1
        os.write(master, b"\x1b[A\x1b[A\x1b[A")
        time.sleep(0.2)
        os.write(master, b"\x02")  # Ctrl-B
        read_until(master, b"Sel: 0 chars", timeout=4.0)
        os.write(master, b"\x1b[B")  # Down arrow
        read_until(master, b"Sel: 2 lines", timeout=4.0)
        os.write(master, b"\x0b")  # Ctrl-K (modal)
        read_until(master, expected_line6, timeout=4.0)
        os.write(master, b"\r")  # Enter inside modal
        out_sol = read_until(master, b"Block: 2 lines", timeout=5.0)
        if b"Block: 2 lines" not in out_sol:
            print(f"[-] Enter in modal did not solidify. Got: {repr(out_sol)}")
            return False
        print("[+] Test 8 PASSED: Enter in modal solidified block.")

        print("[+] Test 9: Ctrl-K on solidified block shows Marked Block...",
              flush=True)
        os.write(master, b"\x0b")  # Ctrl-K on solidified block
        expected_sol_status = (
            b"|             Marked Block: 2 lines              |"
        )
        expected_sol_line5 = (
            b"|      [^C]=Copy Block      [^X]=Move Block      |"
        )
        modal_sol = read_until(master, expected_sol_line5, timeout=6.0)
        if expected_sol_status not in modal_sol:
            print(f"[-] Missing Marked Block status. Got: {repr(modal_sol)}")
            return False
        if expected_sol_line5 not in modal_sol:
            print(f"[-] Missing solidified line 5. Got: {repr(modal_sol)}")
            return False
        print("[+] Test 9 PASSED: Solidified modal layout verified.")

        print("[+] Test 10: Delete block from modal (^D)...", flush=True)
        os.write(master, b"\x04")  # Ctrl-D inside modal
        out_del = read_until(master, b"^K: Editor keys", timeout=5.0)
        if b"^K: Editor keys" not in out_del:
            print("[-] ^D in modal failed to clear block. Got: "
                  f"{repr(out_del)}")
            return False
        if b"Line 3 Gamma" not in out_del:
            print("[-] Document content incorrect after ^D. Got: "
                  f"{repr(out_del)}")
            return False
        print("[+] Test 10 PASSED: Block deleted from modal (^D).")

        # Clean exit from editor
        os.write(master, b"\x11")  # Ctrl-Q exit
        read_until(master, b"C>", timeout=5.0)
        print("[+] All Block Modal tests PASSED successfully!", flush=True)
        return True

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            pass
        os.close(master)
        if os.path.exists(test_doc_path):
            os.remove(test_doc_path)


if __name__ == "__main__":
    if not test_block_modal_workflow():
        sys.exit(1)
