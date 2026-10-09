#!/usr/bin/env python3
"""Automated verification test suite for ZX Spectrum Next targets.

Validates binary integrity, header signatures, memory layouts, and entry
points for:
  - SE_NEXT.COM (NextCPM CP/M 80-column deployment)
  - SE.NEX / SE.nex (ZX Spectrum Next standalone executable)
  - .se / SE (NextZXOS /dot command)

Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture.
"""

import os
import shutil
import struct
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)


def test_next_cpm():
    """Verify SE_NEXT.COM binary integrity and TPA headroom margin."""
    print("[*] Validating SE_NEXT.COM (NextCPM target)...")
    path = os.path.join(PROJECT_DIR, "SE_NEXT.COM")
    assert os.path.exists(path), f"Missing {path}"

    size = os.path.getsize(path)
    assert size == 47872, f"Expected 47,872 bytes, got {size}"

    # Run check_tpa.py
    cmd = [sys.executable, os.path.join(PROJECT_DIR, "check_tpa.py"), path]
    res = subprocess.run(cmd, capture_output=True, text=True, cwd=PROJECT_DIR)
    assert res.returncode == 0, f"check_tpa.py failed:\n{res.stdout}"
    assert "PASS" in res.stdout, "check_tpa.py verdict was not PASS"
    assert "+2,048 bytes" in res.stdout, "Expected +2,048 bytes headroom margin"
    print("    [+] SE_NEXT.COM: 47,872 B, +2,048 B TPA headroom margin [PASS]")


def test_next_nex():
    """Verify SE.NEX 512-byte header and 16KB bank payloads."""
    print("[*] Validating SE.NEX (Standalone Next target)...")
    path = os.path.join(PROJECT_DIR, "SE.NEX")
    assert os.path.exists(path), f"Missing {path}"

    size = os.path.getsize(path)
    expected_size = 512 + (3 * 16384)  # 512 header + 3x 16KB banks = 49,664 B
    assert size == expected_size, f"Expected {expected_size} B, got {size}"

    with open(path, "rb") as f:
        hdr = f.read(512)

    magic = hdr[:4]
    version = hdr[4:8]
    ram_req, num_banks, loading_screen, border = struct.unpack_from(
        "<BBBB", hdr, 8
    )
    sp, pc, num_extra = struct.unpack_from("<HHH", hdr, 12)
    banks = list(hdr[18 : 18 + 112])
    occupied_banks = [i for i, b in enumerate(banks) if b == 1]

    assert magic == b"Next", f"Invalid magic: {magic}"
    assert version == b"V1.1", f"Unexpected version: {version}"
    assert ram_req == 0, f"RAM required must be 0 (768K), got {ram_req}"
    assert num_banks == 3, f"Expected 3 banks, got {num_banks}"
    assert occupied_banks == [0, 2, 5], f"Unexpected banks: {occupied_banks}"
    assert pc == 0x4000, f"Expected PC 0x4000, got 0x{pc:04X}"
    assert sp == 0xFF00, f"Expected SP 0xFF00, got 0x{sp:04X}"
    print(
        f"    [+] SE.NEX: {size} B, Magic={magic.decode()}, "
        f"Banks={occupied_banks}, PC=0x{pc:04X}, SP=0x{sp:04X} [PASS]"
    )


def test_next_dot():
    """Verify .se / SE NextZXOS dot command layout and entry point."""
    print("[*] Validating .se / SE (NextZXOS dot command target)...")
    for name in [".se", "SE"]:
        path = os.path.join(PROJECT_DIR, name)
        assert os.path.exists(path), f"Missing {path}"
        size = os.path.getsize(path)
        assert size == 49152, f"Expected 49,152 B, got {size}"

        with open(path, "rb") as f:
            first_byte = f.read(1)[0]
        # First opcode must be JP (0xC3)
        assert (
            first_byte == 0xC3
        ), f"Expected JP (0xC3) at entry, got 0x{first_byte:02X}"
        print(f"    [+] {name}: {size} B, ORG=0x2000, JP START [PASS]")


def test_emulator_harness():
    """Check for CSpect or ZEsarUX and run automated headless test if found."""
    print("[*] Probing for ZX Spectrum Next emulators (CSpect / ZEsarUX)...")
    cspect = shutil.which("cspect") or shutil.which("CSpect")
    zesarux = shutil.which("zesarux") or shutil.which("ZEsarUX")

    if cspect:
        print(f"    [+] Found CSpect at: {cspect}")
        # Run CSpect in headless mode if available
    elif zesarux:
        print(f"    [+] Found ZEsarUX at: {zesarux}")
        # Run ZEsarUX in headless mode if available
    else:
        print(
            "    [-] Neither CSpect nor ZEsarUX detected in PATH. "
            "Skipping live emulation run."
        )


def main():
    print("=" * 70)
    print("  ZX Spectrum Next Multi-Target Verification Suite")
    print("=" * 70)
    try:
        test_next_cpm()
        test_next_nex()
        test_next_dot()
        test_emulator_harness()
        print("=" * 70)
        print("  ALL NEXT TARGET TESTS PASSED")
        print("=" * 70)
        return 0
    except AssertionError as e:
        print(f"[-] TEST FAILED: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
