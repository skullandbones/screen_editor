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

    z80asm_bin = os.path.join(
        workspace_root, "tools", "z88dk", "bin", "z88dk-z80asm"
    )
    mkprl_bin = os.path.join(repo_root, "tools", "mkprl.py")

    # 1. Build ROT13.PRL
    # Assemble at 0100h
    subprocess.run([z80asm_bin, "-b",
                    f"-o={os.path.join(plugin_dir, 'rot13_100.bin')}",
                    os.path.join(plugin_dir, "rot13.asm")], check=True)

    # Prepare temporary source at 0200h for relocation bitmap computation
    rot13_200_asm = os.path.join(plugin_dir, "rot13_200.asm")
    with open(os.path.join(plugin_dir, "rot13.asm"), "r") as f:
        src = f.read().replace("ORG\t0100H", "ORG\t0200H")
    with open(rot13_200_asm, "w") as f:
        f.write(src)

    # Assemble at 0200h
    subprocess.run([z80asm_bin, "-b",
                    f"-o={os.path.join(plugin_dir, 'rot13_200.bin')}",
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
    subprocess.run([z80asm_bin, "-b",
                    f"-o={os.path.join(plugin_dir, 'wordcnt.bin')}",
                    os.path.join(plugin_dir, "wordcnt.asm")], check=True)

    subprocess.run([sys.executable, mkprl_bin, "-n", "WORDCNT",
                    "-o", os.path.join(plugin_dir, "WORDCNT.OVL"),
                    "--ovl", "--tpa", "--far", "--modal", "--has-about",
                    "--has-config",
                    os.path.join(plugin_dir, "wordcnt.bin")], check=True)

    # 3. Build BEAUTIFY.PRL (CP/M 3 Page-Relocatable, Far-RAM & TPA executable)
    # Assemble at 0100h
    subprocess.run([z80asm_bin, "-b",
                    f"-o={os.path.join(plugin_dir, 'beautify_100.bin')}",
                    os.path.join(plugin_dir, "beautify.asm")], check=True)

    # Prepare temporary source at 0200h for relocation bitmap computation
    beautify_200_asm = os.path.join(plugin_dir, "beautify_200.asm")
    with open(os.path.join(plugin_dir, "beautify.asm"), "r") as f:
        src = f.read().replace("ORG\t0100H", "ORG\t0200H")
    with open(beautify_200_asm, "w") as f:
        f.write(src)

    # Assemble at 0200h
    subprocess.run([z80asm_bin, "-b",
                    f"-o={os.path.join(plugin_dir, 'beautify_200.bin')}",
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

    # 4. Build MIDPLUG.PRL (8KB Slot Class)
    subprocess.run([z80asm_bin, "-b",
                    f"-o={os.path.join(plugin_dir, 'midplug_100.bin')}",
                    os.path.join(plugin_dir, "midplug.asm")], check=True)

    midplug_200_asm = os.path.join(plugin_dir, "midplug_200.asm")
    with open(os.path.join(plugin_dir, "midplug.asm"), "r") as f:
        src = f.read().replace("ORG\t0100H", "ORG\t0200H")
    with open(midplug_200_asm, "w") as f:
        f.write(src)

    subprocess.run([z80asm_bin, "-b",
                    f"-o={os.path.join(plugin_dir, 'midplug_200.bin')}",
                    midplug_200_asm], check=True)
    if os.path.exists(midplug_200_asm):
        os.remove(midplug_200_asm)

    subprocess.run([sys.executable, mkprl_bin, "-n", "MIDPLUG",
                    "-o", os.path.join(plugin_dir, "MIDPLUG.PRL"),
                    "--size", "8k", "--far", "--modal", "--has-about",
                    os.path.join(plugin_dir, "midplug_100.bin"),
                    os.path.join(plugin_dir, "midplug_200.bin")], check=True)

    # 5. Build HALFPLUG.PRL (16KB Slot Class)
    subprocess.run([z80asm_bin, "-b",
                    f"-o={os.path.join(plugin_dir, 'halfplug_100.bin')}",
                    os.path.join(plugin_dir, "halfplug.asm")], check=True)

    halfplug_200_asm = os.path.join(plugin_dir, "halfplug_200.asm")
    with open(os.path.join(plugin_dir, "halfplug.asm"), "r") as f:
        src = f.read().replace("ORG\t0100H", "ORG\t0200H")
    with open(halfplug_200_asm, "w") as f:
        f.write(src)

    subprocess.run([z80asm_bin, "-b",
                    f"-o={os.path.join(plugin_dir, 'halfplug_200.bin')}",
                    halfplug_200_asm], check=True)
    if os.path.exists(halfplug_200_asm):
        os.remove(halfplug_200_asm)

    subprocess.run([sys.executable, mkprl_bin, "-n", "HALFPLUG",
                    "-o", os.path.join(plugin_dir, "HALFPLUG.PRL"),
                    "--size", "16k", "--far", "--modal", "--has-about",
                    os.path.join(plugin_dir, "halfplug_100.bin"),
                    os.path.join(plugin_dir, "halfplug_200.bin")], check=True)

    # 6. Build BIGPLUG.PRL (32KB Slot Class)
    subprocess.run([z80asm_bin, "-b",
                    f"-o={os.path.join(plugin_dir, 'bigplug_100.bin')}",
                    os.path.join(plugin_dir, "bigplug.asm")], check=True)

    bigplug_200_asm = os.path.join(plugin_dir, "bigplug_200.asm")
    with open(os.path.join(plugin_dir, "bigplug.asm"), "r") as f:
        src = f.read().replace("ORG\t0100H", "ORG\t0200H")
    with open(bigplug_200_asm, "w") as f:
        f.write(src)

    subprocess.run([z80asm_bin, "-b",
                    f"-o={os.path.join(plugin_dir, 'bigplug_200.bin')}",
                    bigplug_200_asm], check=True)
    if os.path.exists(bigplug_200_asm):
        os.remove(bigplug_200_asm)

    subprocess.run([sys.executable, mkprl_bin, "-n", "BIGPLUG",
                    "-o", os.path.join(plugin_dir, "BIGPLUG.PRL"),
                    "--size", "32k", "--far", "--modal", "--has-about",
                    os.path.join(plugin_dir, "bigplug_100.bin"),
                    os.path.join(plugin_dir, "bigplug_200.bin")], check=True)

    # 7. Build PLUGIN.PRL (8KB Far RAM Plugin Manager & Context Pop-up)
    subprocess.run([z80asm_bin, "-b",
                    f"-o={os.path.join(plugin_dir, 'plugin_100.bin')}",
                    os.path.join(plugin_dir, "plugin.asm")], check=True)

    plugin_200_asm = os.path.join(plugin_dir, "plugin_200.asm")
    with open(os.path.join(plugin_dir, "plugin.asm"), "r") as f:
        src = f.read().replace("ORG\t0100H", "ORG\t0200H")
    with open(plugin_200_asm, "w") as f:
        f.write(src)

    subprocess.run([z80asm_bin, "-b",
                    f"-o={os.path.join(plugin_dir, 'plugin_200.bin')}",
                    plugin_200_asm], check=True)
    if os.path.exists(plugin_200_asm):
        os.remove(plugin_200_asm)

    subprocess.run([sys.executable, mkprl_bin, "-n", "PLUGIN",
                    "-o", os.path.join(plugin_dir, "PLUGIN.PRL"),
                    "--size", "8k", "--far", "--modal", "--has-about",
                    "--bss", "512",
                    os.path.join(plugin_dir, "plugin_100.bin"),
                    os.path.join(plugin_dir, "plugin_200.bin")], check=True)

    # 8. Build HIBERN.OVL (4KB TPA Relocatable Overlay)
    subprocess.run([z80asm_bin, "-b",
                    f"-o={os.path.join(plugin_dir, 'hibern_100.bin')}",
                    os.path.join(plugin_dir, "hibern.asm")], check=True)

    hibern_200_asm = os.path.join(plugin_dir, "hibern_200.asm")
    with open(os.path.join(plugin_dir, "hibern.asm"), "r") as f:
        src = f.read().replace("ORG\t0100H", "ORG\t0200H")
    with open(hibern_200_asm, "w") as f:
        f.write(src)

    subprocess.run([z80asm_bin, "-b",
                    f"-o={os.path.join(plugin_dir, 'hibern_200.bin')}",
                    hibern_200_asm], check=True)
    if os.path.exists(hibern_200_asm):
        os.remove(hibern_200_asm)

    subprocess.run([sys.executable, mkprl_bin, "-n", "HIBERN",
                    "-o", os.path.join(plugin_dir, "HIBERN.OVL"),
                    "--tpa", "--has-about", "--has-config",
                    os.path.join(plugin_dir, "hibern_100.bin"),
                    os.path.join(plugin_dir, "hibern_200.bin")], check=True)

    # 9. Build HELP.OVL (4KB TPA Relocatable Overlay)
    subprocess.run([z80asm_bin, "-b",
                    f"-o={os.path.join(plugin_dir, 'help_100.bin')}",
                    os.path.join(plugin_dir, "help.asm")], check=True)

    help_200_asm = os.path.join(plugin_dir, "help_200.asm")
    with open(os.path.join(plugin_dir, "help.asm"), "r") as f:
        src = f.read().replace("ORG\t0100H", "ORG\t0200H")
    with open(help_200_asm, "w") as f:
        f.write(src)

    subprocess.run([z80asm_bin, "-b",
                    f"-o={os.path.join(plugin_dir, 'help_200.bin')}",
                    help_200_asm], check=True)
    if os.path.exists(help_200_asm):
        os.remove(help_200_asm)

    subprocess.run([sys.executable, mkprl_bin, "-n", "HELP",
                    "-o", os.path.join(plugin_dir, "HELP.OVL"),
                    "--tpa", "--has-about", "--has-config",
                    os.path.join(plugin_dir, "help_100.bin"),
                    os.path.join(plugin_dir, "help_200.bin")], check=True)

    # Clean up temporary binaries
    for tmp in ["rot13_100.bin", "rot13_200.bin", "wordcnt.bin",
                "beautify_100.bin", "beautify_200.bin",
                "midplug_100.bin", "midplug_200.bin",
                "halfplug_100.bin", "halfplug_200.bin",
                "bigplug_100.bin", "bigplug_200.bin",
                "plugin_100.bin", "plugin_200.bin",
                "hibern_100.bin", "hibern_200.bin",
                "help_100.bin", "help_200.bin"]:
        p = os.path.join(plugin_dir, tmp)
        if os.path.exists(p):
            os.remove(p)

    cfg_path = os.path.join(plugin_dir, "PLUGIN.CFG")
    if not os.path.exists(cfg_path):
        cfg_lines = [
            b"SLOT0=WORDCNT.OVL\r\n",
            b"SLOT1=ROT13.PRL\r\n",
            b"SLOT2=BEAUTIFY.PRL\r\n",
            b"SLOT3=\r\n",
            b"SLOT4=\r\n",
            b"SLOT5=\r\n",
            b"SLOT6=\r\n",
            b"SLOT7=\r\n",
        ]
        cfg_data = b"".join(cfg_lines)
        cfg_data += b"\x1a" * (128 - len(cfg_data))
        with open(cfg_path, "wb") as f:
            f.write(cfg_data)

    print("[+] Plugins built successfully:")
    print(f"    - {os.path.join(plugin_dir, 'ROT13.PRL')}")
    print(f"    - {os.path.join(plugin_dir, 'WORDCNT.OVL')}")
    print(f"    - {os.path.join(plugin_dir, 'BEAUTIFY.PRL')}")
    print(f"    - {os.path.join(plugin_dir, 'MIDPLUG.PRL')}")
    print(f"    - {os.path.join(plugin_dir, 'HALFPLUG.PRL')}")
    print(f"    - {os.path.join(plugin_dir, 'BIGPLUG.PRL')}")
    print(f"    - {os.path.join(plugin_dir, 'PLUGIN.PRL')}")
    print(f"    - {os.path.join(plugin_dir, 'HIBERN.OVL')}")
    print(f"    - {os.path.join(plugin_dir, 'HELP.OVL')}")

if __name__ == "__main__":
    main()
