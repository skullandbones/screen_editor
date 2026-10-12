#!/usr/bin/env python3
"""Populate ZX Spectrum Next MMC image with editor binaries and test fixtures.

Supports FAT partition population (partition 1 at offset 1,048,576 bytes) for:
  - dot command: /dot/se and /se
  - Standalone Next executable: /SE.NEX
  - NextCPM CP/M 80-column binary: /SE_NEXT.COM
  - Headless test fixture files: BIG.TXT, BIG300.TXT, 2.TXT, 30.TXT,
    INS1.TXT, INS2.TXT, CPM1.TXT, LIN1.TXT, CPM2.TXT, SE.CFG

Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
MMC_BASE = "/usr/share/zesarux/tbblue.mmc"
MMC_DEFAULT_TARGET = os.path.join(PROJECT_DIR, "disks", "tbblue.mmc")
FAT_OFFSET = 1048576  # 1 MB (sector 2048 * 512 bytes)


def check_mtools() -> bool:
    """Verify mtools utilities (mcopy, mdir) are available."""
    if not shutil.which("mcopy") or not shutil.which("mdir"):
        print("[-] Error: mtools (mcopy/mdir) not found in PATH.", flush=True)
        return False
    return True


def ensure_mmc_image(target_path: str = MMC_DEFAULT_TARGET) -> bool:
    """Ensure destination MMC image exists, copying from template if needed."""
    if os.path.exists(target_path):
        return True

    if not os.path.exists(MMC_BASE):
        print(f"[-] Base MMC template not found at {MMC_BASE}", flush=True)
        return False

    os.makedirs(os.path.dirname(target_path), exist_ok=True)
    print(f"[*] Copying base MMC template to {target_path}...", flush=True)
    shutil.copyfile(MMC_BASE, target_path)
    return True


def generate_fixtures(temp_dir: str) -> dict[str, str]:
    """Generate all test fixture files in temporary directory."""
    fixtures = {}

    # 1. BIG.TXT (3,072 lines)
    big_path = os.path.join(temp_dir, "BIG.TXT")
    with open(big_path, "wb") as f:
        for i in range(1, 3073):
            f.write(f"Line {i:04d}\r\n".encode("ascii"))
    fixtures["BIG.TXT"] = big_path

    # 2. BIG300.TXT (300 lines)
    big300_path = os.path.join(temp_dir, "BIG300.TXT")
    with open(big300_path, "wb") as f:
        for i in range(1, 301):
            f.write(f"Line {i:04d} of 300\r\n".encode("ascii"))
    fixtures["BIG300.TXT"] = big300_path

    # 3. 2.TXT
    repo_2txt = os.path.join(PROJECT_DIR, "2.TXT")
    path_2txt = os.path.join(temp_dir, "2.TXT")
    if os.path.isfile(repo_2txt):
        shutil.copyfile(repo_2txt, path_2txt)
    else:
        with open(path_2txt, "wb") as f:
            f.write(b"Line 0001\r\nLine 0002\r\n")
    fixtures["2.TXT"] = path_2txt

    # 4. 30.TXT
    repo_30txt = os.path.join(PROJECT_DIR, "30.TXT")
    path_30txt = os.path.join(temp_dir, "30.TXT")
    if os.path.isfile(repo_30txt):
        shutil.copyfile(repo_30txt, path_30txt)
    else:
        with open(path_30txt, "wb") as f:
            for i in range(1, 31):
                f.write(f"Line {i:04d}\r\n".encode("ascii"))
    fixtures["30.TXT"] = path_30txt

    # 5. INS1.TXT and INS2.TXT
    ins1_path = os.path.join(temp_dir, "INS1.TXT")
    with open(ins1_path, "wb") as f:
        f.write(b"INSERTED")
    fixtures["INS1.TXT"] = ins1_path

    ins2_path = os.path.join(temp_dir, "INS2.TXT")
    with open(ins2_path, "wb") as f:
        f.write(b"FIRST LINE\r\nSECOND LINE")
    fixtures["INS2.TXT"] = ins2_path

    # 6. CPM1.TXT, LIN1.TXT, CPM2.TXT (300 lines each)
    cpm1_path = os.path.join(temp_dir, "CPM1.TXT")
    with open(cpm1_path, "wb") as f:
        for i in range(1, 301):
            f.write(f"CPM1 Line {i:04d} content CRLF\r\n".encode("ascii"))
    fixtures["CPM1.TXT"] = cpm1_path

    lin1_path = os.path.join(temp_dir, "LIN1.TXT")
    with open(lin1_path, "wb") as f:
        for i in range(1, 301):
            f.write(f"LIN1 Line {i:04d} content LF\n".encode("ascii"))
    fixtures["LIN1.TXT"] = lin1_path

    cpm2_path = os.path.join(temp_dir, "CPM2.TXT")
    with open(cpm2_path, "wb") as f:
        for i in range(1, 301):
            f.write(f"CPM2 Line {i:04d} content CRLF\r\n".encode("ascii"))
    fixtures["CPM2.TXT"] = cpm2_path

    # 7. SE.CFG
    cfg_path = os.path.join(temp_dir, "SE.CFG")
    with open(cfg_path, "wb") as f:
        f.write(b"SCREEN=80x24\r\nRAMDRIVE=ON\r\n")
    fixtures["SE.CFG"] = cfg_path

    return fixtures


def copy_to_mmc(mmc_spec: str, local_path: str, remote_dest: str) -> bool:
    """Copy local file into FAT MMC image using mcopy."""
    cmd = ["mcopy", "-o", "-i", mmc_spec, local_path, remote_dest]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[-] mcopy failed for {local_path} -> {remote_dest}:",
              flush=True)
        print(res.stderr, flush=True)
        return False
    return True


def populate_next_mmc(
    target_path: str = MMC_DEFAULT_TARGET,
    build_binaries: bool = False,
    test_uart_bridge: bool = True,
) -> bool:
    """Populate MMC image with Next binaries and regression test fixtures."""
    if not check_mtools():
        return False

    if not ensure_mmc_image(target_path):
        return False

    mmc_spec = f"{target_path}@@{FAT_OFFSET}"

    # Build binaries if requested
    if build_binaries:
        print("[*] Assembling Next binaries with test UART bridge...",
              flush=True)
        tools_root = os.path.abspath(os.path.join(PROJECT_DIR, "..", "..", "tools"))
        z80asm = os.path.join(tools_root, "z88dk", "bin", "z88dk-z80asm")
        appmake = os.path.join(tools_root, "z88dk", "bin", "z88dk-appmake")
        asm_src = os.path.join(PROJECT_DIR, "src", "se_next.asm")

        # 1. Assemble dot_se.bin
        dot_flags = ["-DNEXT_DOT_COMMAND", "-b", "-m", "-s", "-o=dot_se.bin"]
        if test_uart_bridge:
            dot_flags.insert(1, "-DTEST_UART_BRIDGE")
        res = subprocess.run([z80asm] + dot_flags + [asm_src],
                             cwd=PROJECT_DIR, capture_output=True, text=True)
        if res.returncode != 0:
            print(f"[-] Failed to assemble dot_se.bin: {res.stderr}",
                  flush=True)
            return False

        # 2. Assemble SE_NEX.BIN and convert via appmake
        nex_flags = ["-b", "-m", "-s", "-o=SE_NEX.BIN"]
        if test_uart_bridge:
            nex_flags.insert(0, "-DTEST_UART_BRIDGE")
        res = subprocess.run([z80asm] + nex_flags + [asm_src],
                             cwd=PROJECT_DIR, capture_output=True, text=True)
        if res.returncode != 0:
            print(f"[-] Failed to assemble SE_NEX.BIN: {res.stderr}",
                  flush=True)
            return False

        res = subprocess.run(
            [appmake, "+zxn", "-b", "SE_NEX.BIN", "-c", "SE_NEX",
             "-o", "SE.nex", "--nex"],
            cwd=PROJECT_DIR, capture_output=True, text=True
        )
        if res.returncode != 0:
            print(f"[-] appmake failed: {res.stderr}", flush=True)
            return False
        shutil.copyfile(os.path.join(PROJECT_DIR, "SE.nex"),
                        os.path.join(PROJECT_DIR, "SE.NEX"))

    with tempfile.TemporaryDirectory() as temp_dir:
        fixtures = generate_fixtures(temp_dir)

        print("[*] Injecting regression test fixtures into MMC image...",
              flush=True)
        for fname, fpath in fixtures.items():
            dest = f"::/{fname}"
            if not copy_to_mmc(mmc_spec, fpath, dest):
                return False
            print(f"    [+] Injected {fname} -> {dest}", flush=True)

    # Inject binaries
    binaries = [
        ("dot_se.bin", "::/dot/se"),
        ("dot_se.bin", "::/se"),
        ("SE.NEX", "::/SE.NEX"),
        ("SE_NEXT.COM", "::/SE_NEXT.COM"),
    ]

    print("[*] Injecting Next binaries into MMC image...", flush=True)
    for bname, dest in binaries:
        bpath = os.path.join(PROJECT_DIR, bname)
        if os.path.isfile(bpath):
            if not copy_to_mmc(mmc_spec, bpath, dest):
                return False
            size = os.path.getsize(bpath)
            print(f"    [+] Injected {bname} ({size} B) -> {dest}", flush=True)
        else:
            print(f"    [!] Skipping {bname} (not found on host)", flush=True)

    # Verification
    print("[*] Verifying MMC filesystem contents via mdir...", flush=True)
    res_root = subprocess.run(["mdir", "-b", "-i", mmc_spec, "::"],
                              capture_output=True, text=True)
    res_dot = subprocess.run(["mdir", "-b", "-i", mmc_spec, "::/dot"],
                             capture_output=True, text=True)

    root_files = [line.strip().upper() for line in res_root.stdout.splitlines()]
    dot_files = [line.strip().upper() for line in res_dot.stdout.splitlines()]

    assert "::/BIG.TXT" in root_files, "BIG.TXT not found in root"
    assert "::/30.TXT" in root_files, "30.TXT not found in root"
    assert "::/SE.CFG" in root_files, "SE.CFG not found in root"
    assert "::/DOT/SE" in dot_files, "se not found in /dot"

    print("[+] MMC disk image population verified successfully.", flush=True)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Populate Next MMC image with test fixtures and binaries."
    )
    parser.add_argument(
        "--target",
        default=MMC_DEFAULT_TARGET,
        help="Path to destination MMC image file",
    )
    parser.add_argument(
        "--build",
        action="store_true",
        help="Rebuild Next binaries with UART bridge before injecting",
    )
    args = parser.parse_args()

    success = populate_next_mmc(
        target_path=args.target,
        build_binaries=args.build,
        test_uart_bridge=True,
    )
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
