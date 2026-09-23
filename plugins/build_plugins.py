#!/usr/bin/env python3
"""
build_plugins.py - Assembles and packages SE.COM reference plugins.
Generates:
  - plugins/ROT13.PRL (CP/M 3 Page-Relocatable format)
  - plugins/WORDCNT.OVL (CP/M 3 Overlay format)
"""

import os
import subprocess
import sys

def main():
    plugin_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(plugin_dir)
    workspace_root = os.path.abspath(os.path.join(repo_root, "..", ".."))

    z80asm_bin = os.path.join(workspace_root, "tools", "z88dk", "bin", "z88dk-z80asm")
    mkprl_bin = os.path.join(repo_root, "tools", "mkprl.py")

    # 1. Build ROT13.PRL
    # Assemble at 0100h
    subprocess.run([z80asm_bin, "-b", f"-o={os.path.join(plugin_dir, 'rot13_100.bin')}",
                    os.path.join(plugin_dir, "rot13.asm")], check=True)

    # Prepare temporary source at 0200h for relocation bitmap computation
    rot13_200_asm = os.path.join(plugin_dir, "rot13_200.asm")
    with open(os.path.join(plugin_dir, "rot13.asm"), "r") as f:
        src = f.read().replace("ORG\t0100H", "ORG\t0200H")
    with open(rot13_200_asm, "w") as f:
        f.write(src)

    # Assemble at 0200h
    subprocess.run([z80asm_bin, "-b", f"-o={os.path.join(plugin_dir, 'rot13_200.bin')}",
                    rot13_200_asm], check=True)
    if os.path.exists(rot13_200_asm):
        os.remove(rot13_200_asm)

    # Package into ROT13.PRL
    subprocess.run([sys.executable, mkprl_bin, "-n", "ROT13",
                    "-o", os.path.join(plugin_dir, "ROT13.PRL"),
                    "--tpa", "--mutate", "--has-about",
                    os.path.join(plugin_dir, "rot13_100.bin"),
                    os.path.join(plugin_dir, "rot13_200.bin")], check=True)

    # 2. Build WORDCNT.OVL
    subprocess.run([z80asm_bin, "-b", f"-o={os.path.join(plugin_dir, 'wordcnt.bin')}",
                    os.path.join(plugin_dir, "wordcnt.asm")], check=True)

    subprocess.run([sys.executable, mkprl_bin, "-n", "WORDCNT",
                    "-o", os.path.join(plugin_dir, "WORDCNT.OVL"),
                    "--ovl", "--tpa", "--far", "--modal", "--has-about", "--has-config",
                    os.path.join(plugin_dir, "wordcnt.bin")], check=True)

    # 3. Build BEAUTIFY.PRL (CP/M 3 Page-Relocatable, Far-RAM & TPA executable)
    # Assemble at 0100h
    subprocess.run([z80asm_bin, "-b", f"-o={os.path.join(plugin_dir, 'beautify_100.bin')}",
                    os.path.join(plugin_dir, "beautify.asm")], check=True)

    # Prepare temporary source at 0200h for relocation bitmap computation
    beautify_200_asm = os.path.join(plugin_dir, "beautify_200.asm")
    with open(os.path.join(plugin_dir, "beautify.asm"), "r") as f:
        src = f.read().replace("ORG\t0100H", "ORG\t0200H")
    with open(beautify_200_asm, "w") as f:
        f.write(src)

    # Assemble at 0200h
    subprocess.run([z80asm_bin, "-b", f"-o={os.path.join(plugin_dir, 'beautify_200.bin')}",
                    beautify_200_asm], check=True)
    if os.path.exists(beautify_200_asm):
        os.remove(beautify_200_asm)

    # Package into BEAUTIFY.PRL
    subprocess.run([sys.executable, mkprl_bin, "-n", "BEAUTIFY",
                    "-o", os.path.join(plugin_dir, "BEAUTIFY.PRL"),
                    "--tpa", "--mutate", "--has-about", "--has-config",
                    "--bss", "544",
                    os.path.join(plugin_dir, "beautify_100.bin"),
                    os.path.join(plugin_dir, "beautify_200.bin")], check=True)

    # Clean up temporary binaries
    for tmp in ["rot13_100.bin", "rot13_200.bin", "wordcnt.bin",
                "beautify_100.bin", "beautify_200.bin"]:
        p = os.path.join(plugin_dir, tmp)
        if os.path.exists(p):
            os.remove(p)

    print("[+] Plugins built successfully:")
    print(f"    - {os.path.join(plugin_dir, 'ROT13.PRL')}")
    print(f"    - {os.path.join(plugin_dir, 'WORDCNT.OVL')}")
    print(f"    - {os.path.join(plugin_dir, 'BEAUTIFY.PRL')}")

if __name__ == "__main__":
    main()
