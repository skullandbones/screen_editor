#!/usr/bin/env python3
"""
check_tpa.py - CP/M Transient Program Area (TPA) Memory Footprint Analyzer

Analyzes CP/M .COM executable binaries to verify they do not exceed the
maximum allowable Transient Program Area (TPA) on CP/M systems (such as
RomWBW RC2014 CP/M 2.2, standard CP/M 2.2, CP/M 3.0 Plus, and Z-System).

Calculates:
  1. Disk image size (code + initialized data).
  2. Runtime BSS and stack allocations via companion .map and .sym files.
  3. Total memory footprint from load origin (0x0100) to top of memory.
  4. Free headroom below BDOS entry point.
  5. Multi-environment compatibility comparison.

Usable by both humans (rich visual report) and AI agents (--json, --quiet,
and standard exit codes: 0 = PASS, 1 = FAIL, 2 = ERROR).
"""

import argparse
import json
import os
import re
import struct
import sys

# Standard CP/M TPA load origin for all .COM executables
CPM_TPA_ORIGIN = 0x0100

# Recognized CP/M target system presets
TPA_PRESETS = {
    "romwbw": {
        "name": "RomWBW RC2014 CP/M",
        "bdos_entry": 0xD800,
        "desc": "Standard RomWBW HBIOS CP/M 2.2 (BDOS at 0xD800)",
    },
    "cpm22-std": {
        "name": "Standard 64K CP/M",
        "bdos_entry": 0xDC00,
        "desc": "Typical 64K CP/M 2.2 system (BDOS at 0xDC00)",
    },
    "cpm22-min": {
        "name": "Minimal 64K CP/M",
        "bdos_entry": 0xD000,
        "desc": "Minimal TPA 64K CP/M 2.2 with large BIOS (BDOS at 0xD000)",
    },
    "cpm3-banked": {
        "name": "CP/M Plus (Banked)",
        "bdos_entry": 0xF600,
        "desc": "Banked CP/M 3.0 / CP/M Plus (BDOS at 0xF600)",
    },
    "cpm3-nonbanked": {
        "name": "CP/M Plus (Non-Bnk)",
        "bdos_entry": 0xC000,
        "desc": "Non-banked CP/M 3.0 / CP/M Plus (BDOS at 0xC000)",
    },
    "zsystem": {
        "name": "Z-System / ZSDOS",
        "bdos_entry": 0xD000,
        "desc": "Z-System with full CCP/FCP/RCP/NDR buffers (BDOS at 0xD000)",
    },
}

DEFAULT_PRESET = "romwbw"

# Known BSS end symbol names across different assembler/linker toolchains
BSS_END_SYMBOLS = [
    "BSS_END",
    "_BSS_END",
    "__BSS_END",
    "_bss_end",
    "__bss_end",
    "__tail",
    "__BSS_tail",
    "BSS_LAST",
]

# Known BSS start symbol names
BSS_START_SYMBOLS = [
    "BSS_START",
    "_BSS_START",
    "__BSS_START",
    "_bss_start",
    "__bss_start",
    "__head",
    "__BSS_head",
]


def find_companion_file(com_path, extension):
    """
    Searches for companion files (.map or .sym) in likely directories:
    - Same directory with matching stem (e.g. SE.map, SE.sym)
    - Same directory with lowercase stem (e.g. se.map, se.sym)
    - Subdirectory 'src/' with matching or lowercase stem
    - Parent directory with matching or lowercase stem
    """
    directory = os.path.dirname(os.path.abspath(com_path))
    stem = os.path.splitext(os.path.basename(com_path))[0]
    candidates = [
        os.path.join(directory, f"{stem}.{extension}"),
        os.path.join(directory, f"{stem.lower()}.{extension}"),
        os.path.join(directory, f"{stem.upper()}.{extension}"),
        os.path.join(directory, "src", f"{stem}.{extension}"),
        os.path.join(directory, "src", f"{stem.lower()}.{extension}"),
        os.path.join(directory, "..", f"{stem}.{extension}"),
        os.path.join(directory, "..", f"{stem.lower()}.{extension}"),
    ]
    for c in candidates:
        if os.path.isfile(c):
            return os.path.abspath(c)
    return None


def parse_symbols_from_file(filepath):
    """
    Extracts symbol names and 16-bit address values from a map or symbol file.
    Supports z88dk-z80asm, TASM, SLR, and standard Link-80 map formats.
    """
    symbols = {}
    if not filepath or not os.path.isfile(filepath):
        return symbols

    # Pattern 1: SYMBOL = $HEX or SYMBOL = 0xHEX
    p1 = re.compile(
        r"^\s*([A-Za-z0-9_]+)\s*=\s*(?:\$|0x)([0-9A-Fa-f]+)\b"
    )
    # Pattern 2: SYMBOL EQU $HEX or SYMBOL EQU HEXH
    p2 = re.compile(
        r"^\s*([A-Za-z0-9_]+)\s+EQU\s+(?:\$|0x)?([0-9A-Fa-f]+)H?\b",
        re.IGNORECASE,
    )
    # Pattern 3: HEX SYMBOL (Link-80 / Digital Research map)
    p3 = re.compile(r"^\s*([0-9A-Fa-f]{4})\s+([A-Za-z0-9_]+)\b")
    # Pattern 4: SYMBOL HEX (symbol listing format)
    p4 = re.compile(r"^\s*([A-Za-z0-9_]+)\s+([0-9A-Fa-f]{4})\b")

    try:
        with open(filepath, "r", encoding="latin1") as f:
            for line in f:
                line = line.strip()
                m = p1.match(line)
                if m:
                    symbols[m.group(1)] = int(m.group(2), 16)
                    continue
                m = p2.match(line)
                if m:
                    symbols[m.group(1)] = int(m.group(2), 16)
                    continue
                m = p3.match(line)
                if m:
                    symbols[m.group(2)] = int(m.group(1), 16)
                    continue
                m = p4.match(line)
                if m:
                    symbols[m.group(1)] = int(m.group(2), 16)
                    continue
    except OSError:
        pass
    return symbols


def parse_memory_boundary(map_path, sym_path, code_end):
    """
    Resolves BSS_START, BSS_END, and the effective top of memory.
    Prefers .map file over .sym file (since .map contains resolved addresses).
    """
    map_syms = parse_symbols_from_file(map_path) if map_path else {}
    sym_syms = parse_symbols_from_file(sym_path) if sym_path else {}

    # Merge symbols, giving precedence to map file
    all_syms = dict(sym_syms)
    all_syms.update(map_syms)

    bss_end = None
    bss_end_sym = None
    for name in BSS_END_SYMBOLS:
        val = all_syms.get(name)
        if val is not None and val > 0:
            bss_end = val
            bss_end_sym = name
            break

    bss_start = None
    bss_start_sym = None
    for name in BSS_START_SYMBOLS:
        val = all_syms.get(name)
        if val is not None and val > 0:
            bss_start = val
            bss_start_sym = name
            break

    # If bss_end was resolved, memory top is at least bss_end
    if bss_end is not None and bss_end >= code_end:
        mem_top = bss_end
        bss_size = bss_end - (bss_start if bss_start else code_end)
        source = (
            map_path
            if (map_path and bss_end_sym in map_syms)
            else sym_path
        )
    else:
        mem_top = code_end
        bss_size = 0
        source = None

    return {
        "bss_start": bss_start,
        "bss_start_symbol": bss_start_sym,
        "bss_end": bss_end,
        "bss_end_symbol": bss_end_sym,
        "bss_size": bss_size,
        "mem_top": mem_top,
        "source_file": source,
        "all_symbols": all_syms,
    }


def find_plugins_dir(com_path, explicit_dir=None):
    """
    Locates companion plugins directory containing .PRL and .OVL files.
    Searches explicit_dir if provided, then common relative paths.
    Returns None if explicit_dir == 'none' or no directory found.
    """
    if explicit_dir is not None:
        if explicit_dir.strip().lower() == "none":
            return None
        if os.path.isdir(explicit_dir):
            return os.path.abspath(explicit_dir)
        return None

    directory = os.path.dirname(os.path.abspath(com_path))
    candidates = [
        os.path.join(directory, "plugins"),
        os.path.join(directory, "..", "plugins"),
        os.path.join(directory, "src", "plugins"),
    ]
    for c in candidates:
        if os.path.isdir(c):
            return os.path.abspath(c)
    return None


def analyze_plugin_file(filepath, tpa_slot_size=5120):
    """
    Analyzes a CP/M 3 .PRL or .OVL plugin binary against TPA overlay
    and Far RAM slot boundary capacity.
    """
    filename = os.path.basename(filepath)
    try:
        with open(filepath, "rb") as f:
            data = f.read()
    except OSError:
        return None

    if len(data) < 256:
        return None

    prog_size = struct.unpack_from("<H", data, 1)[0]
    bss_size = struct.unpack_from("<H", data, 4)[0]
    load_addr = struct.unpack_from("<H", data, 7)[0]
    name_bytes = data[12:28].split(b"\x00")[0]
    clean_name = name_bytes.decode("ascii", errors="replace").strip()
    caps = struct.unpack_from("<H", data, 28)[0]

    size_bits = caps & 0xC0
    is_ovl = (load_addr != 0) or filename.upper().endswith(".OVL")
    can_tpa = bool(caps & 0x01)
    can_far = bool(caps & 0x02)

    if size_bits == 0x00:
        sz_class = "4K"
        slot_limit = 4096
    elif size_bits == 0x40:
        sz_class = "8K"
        slot_limit = 8192
    elif size_bits == 0x80:
        sz_class = "16K"
        slot_limit = 16384
    else:
        sz_class = "32K"
        slot_limit = 32768

    bitmap_sz = 0 if is_ovl else (prog_size + 7) // 8

    # TPA execution overlay footprint (header + code + BSS + bitmap)
    tpa_needed = 256 + prog_size + bss_size + bitmap_sz
    tpa_headroom = tpa_slot_size - tpa_needed
    tpa_overflow = (
        (tpa_headroom < 0) if (can_tpa or sz_class == "4K") else False
    )

    # Far RAM storage footprint
    if sz_class == "4K" and not is_ovl:
        payload_sz = prog_size + bitmap_sz
    else:
        payload_sz = prog_size

    payload_sectors = (payload_sz + 127) // 128
    far_needed = 256 + payload_sectors * 128
    far_headroom = slot_limit - far_needed
    far_overflow = far_headroom < 0

    status = "PASS"
    issues = []
    if tpa_overflow:
        status = "FAIL"
        issues.append(
            f"TPA overlay overflow: {abs(tpa_headroom)} bytes past "
            f"{tpa_slot_size}-byte LINE_STORAGE slot"
        )
    if far_overflow:
        status = "FAIL"
        issues.append(
            f"Far RAM slot overflow: {abs(far_headroom)} bytes past "
            f"{slot_limit}-byte {sz_class} slot limit"
        )

    return {
        "file": filename,
        "name": clean_name or filename,
        "type": "OVL" if is_ovl else "PRL",
        "class": sz_class,
        "prog_size": prog_size,
        "bss_size": bss_size,
        "bitmap_size": bitmap_sz,
        "file_size": len(data),
        "can_tpa": can_tpa,
        "can_far": can_far,
        "tpa_needed": tpa_needed,
        "tpa_headroom": tpa_headroom,
        "tpa_overflow": tpa_overflow,
        "far_needed": far_needed,
        "far_limit": slot_limit,
        "far_headroom": far_headroom,
        "far_overflow": far_overflow,
        "status": status,
        "issues": issues,
    }


def analyze_com_file(
    com_path,
    map_path=None,
    sym_path=None,
    tpa_top=None,
    preset=DEFAULT_PRESET,
    plugins_dir=None,
):
    """
    Performs full TPA memory analysis on a CP/M .COM file and its
    companion plugins.

    Returns a comprehensive dictionary of results suitable for both
    human-formatted reports and machine-readable JSON output.
    """
    com_abs = os.path.abspath(com_path)
    if not os.path.isfile(com_abs):
        raise FileNotFoundError(f"File not found: {com_path}")

    filesize = os.path.getsize(com_abs)
    code_end = CPM_TPA_ORIGIN + filesize

    # Locate map and sym files if not explicitly provided
    if not map_path:
        map_path = find_companion_file(com_abs, "map")
    if not sym_path:
        sym_path = find_companion_file(com_abs, "sym")

    mem_info = parse_memory_boundary(map_path, sym_path, code_end)
    mem_top = mem_info["mem_top"]
    tpa_consumed = mem_top - CPM_TPA_ORIGIN

    # Resolve target TPA boundary
    preset_data = TPA_PRESETS.get(preset)
    if tpa_top is not None:
        target_bdos = tpa_top
        target_name = f"Custom (BDOS 0x{target_bdos:04X})"
    elif preset_data:
        target_bdos = preset_data["bdos_entry"]
        target_name = preset_data["name"]
    else:
        target_bdos = TPA_PRESETS[DEFAULT_PRESET]["bdos_entry"]
        target_name = TPA_PRESETS[DEFAULT_PRESET]["name"]

    target_tpa_size = target_bdos - CPM_TPA_ORIGIN
    headroom_bytes = target_bdos - mem_top
    headroom_kb = round(headroom_bytes / 1024.0, 3)
    headroom_pct = round((headroom_bytes / target_tpa_size) * 100.0, 2)
    exceeded = headroom_bytes < 0
    status = "FAIL" if exceeded else "PASS"

    # Analyze against all standard environments
    env_results = []
    for key, env in TPA_PRESETS.items():
        env_limit = env["bdos_entry"] - CPM_TPA_ORIGIN
        env_headroom = env["bdos_entry"] - mem_top
        env_pass = env_headroom >= 0
        env_results.append({
            "key": key,
            "name": env["name"],
            "bdos_entry": env["bdos_entry"],
            "bdos_entry_hex": f"0x{env['bdos_entry']:04X}",
            "tpa_limit": env_limit,
            "tpa_limit_kb": round(env_limit / 1024.0, 2),
            "headroom_bytes": env_headroom,
            "headroom_kb": round(env_headroom / 1024.0, 2),
            "status": "PASS" if env_pass else "FAIL",
            "is_selected": (key == preset and tpa_top is None),
        })

    # Resolve TPA plugin execution slot metrics from symbols
    syms = mem_info.get("all_symbols", {})
    tpa_slot_addr = syms.get(
        "LINE_STORAGE", syms.get("PLUGIN_TPA_SLOT", None)
    )
    tpa_slot_size = syms.get("LINE_STORAGE_SIZE", 5120)

    # Analyze companion plugins if directory is found
    p_dir = find_plugins_dir(com_abs, plugins_dir)
    plugin_results = []
    if p_dir and os.path.isdir(p_dir):
        for pf in sorted(os.listdir(p_dir)):
            if pf.upper().endswith((".PRL", ".OVL")):
                p_path = os.path.join(p_dir, pf)
                p_res = analyze_plugin_file(
                    p_path, tpa_slot_size=tpa_slot_size
                )
                if p_res:
                    plugin_results.append(p_res)

    plugins_failed = sum(1 for p in plugin_results if p["status"] == "FAIL")
    plugins_status = "FAIL" if plugins_failed > 0 else "PASS"

    return {
        "file": com_abs,
        "filename": os.path.basename(com_abs),
        "file_size": filesize,
        "file_size_kb": round(filesize / 1024.0, 3),
        "load_origin": CPM_TPA_ORIGIN,
        "load_origin_hex": f"0x{CPM_TPA_ORIGIN:04X}",
        "code_data_end": code_end,
        "code_data_end_hex": f"0x{code_end:04X}",
        "has_bss": mem_info["bss_size"] > 0,
        "bss_start": mem_info["bss_start"],
        "bss_start_hex": (
            f"0x{mem_info['bss_start']:04X}"
            if mem_info["bss_start"] is not None
            else None
        ),
        "bss_end": mem_info["bss_end"],
        "bss_end_hex": (
            f"0x{mem_info['bss_end']:04X}"
            if mem_info["bss_end"] is not None
            else None
        ),
        "bss_size": mem_info["bss_size"],
        "bss_size_kb": round(mem_info["bss_size"] / 1024.0, 3),
        "bss_symbol": mem_info["bss_end_symbol"],
        "map_source": mem_info["source_file"],
        "mem_top": mem_top,
        "mem_top_hex": f"0x{mem_top:04X}",
        "total_tpa_consumed": tpa_consumed,
        "total_tpa_consumed_kb": round(tpa_consumed / 1024.0, 3),
        "total_tpa_pct": round((tpa_consumed / target_tpa_size) * 100.0, 2),
        "target_preset": preset,
        "target_name": target_name,
        "target_bdos_entry": target_bdos,
        "target_bdos_entry_hex": f"0x{target_bdos:04X}",
        "target_tpa_limit": target_tpa_size,
        "target_tpa_limit_kb": round(target_tpa_size / 1024.0, 2),
        "headroom_bytes": headroom_bytes,
        "headroom_kb": headroom_kb,
        "headroom_percent": headroom_pct,
        "exceeded": exceeded,
        "status": status,
        "environments": env_results,
        "tpa_slot_addr": tpa_slot_addr,
        "tpa_slot_addr_hex": (
            f"0x{tpa_slot_addr:04X}" if tpa_slot_addr is not None else None
        ),
        "tpa_slot_size": tpa_slot_size,
        "plugins_dir": p_dir,
        "plugins": plugin_results,
        "plugins_count": len(plugin_results),
        "plugins_status": plugins_status if plugin_results else None,
        "plugins_failed_count": plugins_failed,
    }


def format_human_report(res, verbose=False, no_color=False):
    """Formats human-readable diagnostic summary with tables."""
    # Terminal color codes
    use_color = (
        not no_color
        and sys.stdout.isatty()
        and os.environ.get("TERM") != "dumb"
    )
    c_bold = "\033[1m" if use_color else ""
    c_green = "\033[32m" if use_color else ""
    c_red = "\033[31m" if use_color else ""
    c_cyan = "\033[36m" if use_color else ""
    c_yellow = "\033[33m" if use_color else ""
    c_reset = "\033[0m" if use_color else ""

    status_color = c_green if res["status"] == "PASS" else c_red
    status_badge = f"{status_color}[ {res['status']} ]{c_reset}"

    lines = []
    lines.append("=" * 80)
    lines.append(
        f"   {c_bold}CP/M TPA Memory Footprint Analysis: "
        f"{res['filename']}{c_reset}"
    )
    lines.append("=" * 80)
    lines.append(f"  Target Environment : {res['target_name']}")
    lines.append(
        f"  BDOS Entry Point   : {res['target_bdos_entry_hex']} "
        f"({res['target_bdos_entry']:,d})"
    )
    lines.append(
        f"  Max TPA Capacity   : {res['target_tpa_limit']:,d} bytes "
        f"({res['target_tpa_limit_kb']:.2f} KB)"
    )
    lines.append("-" * 80)
    lines.append(f"  {c_bold}[Binary On Disk]{c_reset}")
    lines.append(f"  File Path          : {res['file']}")
    lines.append(
        f"  File Size          : {res['file_size']:,d} bytes "
        f"({res['file_size_kb']:.2f} KB)"
    )
    lines.append(
        f"  Load Origin        : {res['load_origin_hex']} "
        f"({res['load_origin']}) - Standard CP/M TPA Base"
    )
    lines.append(
        f"  Code + Data Range  : {res['load_origin_hex']} .. "
        f"{res['code_data_end_hex']} ({res['file_size']:,d} bytes)"
    )
    lines.append("")

    lines.append(f"  {c_bold}[Runtime Memory & BSS Buffers]{c_reset}")
    if res["has_bss"]:
        b_start = res["bss_start_hex"] or res["code_data_end_hex"]
        b_end = res["bss_end_hex"]
        lines.append(
            f"  BSS Allocation     : {b_start} .. {b_end} "
            f"({res['bss_size']:,d} bytes / {res['bss_size_kb']:.2f} KB)"
        )
        lines.append(
            f"  BSS Symbol Source  : {os.path.basename(res['map_source'])} "
            f"({res['bss_symbol']} = {res['bss_end_hex']})"
        )
    else:
        lines.append(
            "  BSS Allocation     : None detected (file size matches memory)"
        )
    lines.append(
        f"  Top of Memory      : {res['mem_top_hex']} ({res['mem_top']:,d})"
    )
    lines.append("")

    lines.append(f"  {c_bold}[TPA Utilization & Headroom]{c_reset}")
    lines.append(
        f"  Total TPA Consumed : {res['total_tpa_consumed']:,d} bytes "
        f"({res['total_tpa_consumed_kb']:.2f} KB / {res['total_tpa_pct']}%)"
    )
    sign = "+" if res["headroom_bytes"] >= 0 else ""
    lines.append(
        f"  Free Headroom      : {c_bold}{sign}"
        f"{res['headroom_bytes']:,d} bytes "
        f"({sign}{res['headroom_kb']:.2f} KB / "
        f"{res['headroom_percent']}% margin){c_reset}"
    )
    lines.append("-" * 80)

    if res["status"] == "PASS":
        verdict = (
            f"  {c_bold}VERDICT: {status_badge} Binary fits safely within "
            f"{res['target_name']}\n"
            f"           Headroom: {sign}{res['headroom_bytes']:,d} bytes "
            f"({sign}{res['headroom_kb']:.2f} KB) below BDOS entry point."
        )
    else:
        verdict = (
            f"  {c_bold}VERDICT: {status_badge} Binary EXCEEDS TPA limit by "
            f"{abs(res['headroom_bytes']):,d} bytes!\n"
            f"           Overwrites BDOS at {res['target_bdos_entry_hex']}."
        )
    lines.append(verdict)
    lines.append("=" * 80)

    # Multi-environment comparison table (width <= 75 chars)
    tbl_border = (
        "  +----------------------+----------+---------+-----------+--------+"
    )
    tbl_hdr = (
        "  | Environment          | BDOS Top | TPA Max | Headroom  | Status |"
    )
    lines.append("")
    lines.append(f"  {c_bold}Target Environment Compatibility Matrix:{c_reset}")
    lines.append(tbl_border)
    lines.append(tbl_hdr)
    lines.append(tbl_border)
    for env in res["environments"]:
        e_sign = "+" if env["headroom_bytes"] >= 0 else ""
        e_stat = (
            f"{c_green}PASS{c_reset}"
            if env["status"] == "PASS"
            else f"{c_red}FAIL{c_reset}"
        )
        tag = " *" if env["is_selected"] else "  "
        line = (
            f"  | {env['name']:<19}{tag}| "
            f"{env['bdos_entry_hex']:<8} | "
            f"{env['tpa_limit_kb']:>5.2f} KB | "
            f"{e_sign}{env['headroom_bytes']:>7,d} B | "
            f"  {e_stat}  |"
        )
        lines.append(line)
    lines.append(tbl_border)
    lines.append("  (* = currently selected target)")
    lines.append("")

    if res.get("plugins"):
        p_border = (
            "  +----------------+------+-------+-------+-------+"
            "--------------+--------------+--------+"
        )
        p_hdr = (
            "  | Plugin Binary  | Type | Class | Code  | BSS   |"
            " TPA Headroom | Far Headroom | Status |"
        )
        lines.append("")
        lines.append(
            f"  {c_bold}Plugin Slot & TPA Overlay Verification:{c_reset}"
        )
        lines.append(f"  Plugins Directory  : {res['plugins_dir']}")
        slot_hex = res["tpa_slot_addr_hex"] or "BSS"
        lines.append(
            f"  TPA Overlay Slot   : {slot_hex} "
            f"({res['tpa_slot_size']:,d} bytes)"
        )
        lines.append(p_border)
        lines.append(p_hdr)
        lines.append(p_border)
        for p in res["plugins"]:
            tpa_str = (
                f"{p['tpa_headroom']:+d} B"
                if (p["can_tpa"] or p["class"] == "4K")
                else "N/A (Far)"
            )
            far_str = f"{p['far_headroom']:+d} B"
            p_stat = (
                f"{c_green}PASS{c_reset}"
                if p["status"] == "PASS"
                else f"{c_red}FAIL{c_reset}"
            )
            code_str = f"{p['prog_size']:,d}B"
            bss_str = f"{p['bss_size']:,d}B"
            line = (
                f"  | {p['file']:<14} | {p['type']:<4} | {p['class']:<5} | "
                f"{code_str:>5} | {bss_str:>5} | "
                f"{tpa_str:>12} | {far_str:>12} |  {p_stat}  |"
            )
            lines.append(line)
        lines.append(p_border)

        # Print detailed warnings for failing plugins
        failing_plugins = [p for p in res["plugins"] if p["status"] == "FAIL"]
        if failing_plugins:
            lines.append("")
            for p in failing_plugins:
                lines.append(
                    f"  {c_red}[!] WARNING: {p['file']} exceeds slot "
                    f"boundaries:{c_reset}"
                )
                for iss in p["issues"]:
                    lines.append(f"      - {iss}")

        lines.append("")
        p_badge = (
            f"{c_green}[ PASS ]{c_reset}"
            if res["plugins_status"] == "PASS"
            else f"{c_red}[ FAIL ]{c_reset}"
        )
        cnt = len(res["plugins"])
        if res["plugins_status"] == "PASS":
            lines.append(
                f"  {c_bold}PLUGIN VERDICT: {p_badge} All {cnt} "
                f"plugins fit within TPA and Far RAM slots.{c_reset}"
            )
        else:
            fail_names = ", ".join(p["file"] for p in failing_plugins)
            fcnt = res["plugins_failed_count"]
            lines.append(
                f"  {c_bold}PLUGIN VERDICT: {p_badge} {fcnt} plugin(s) exceed "
                f"slot boundaries ({fail_names})!{c_reset}"
            )
        lines.append("=" * 80)
        lines.append("")

    return "\n".join(lines)


def parse_hex_or_int(val_str):
    """Parses a string representing hex (0x1234, $1234) or decimal number."""
    val_str = val_str.strip()
    if val_str.startswith("$"):
        return int(val_str[1:], 16)
    if val_str.lower().startswith("0x"):
        return int(val_str, 16)
    if val_str.lower().endswith("h"):
        return int(val_str[:-1], 16)
    if val_str.lower().endswith("k"):
        return int(float(val_str[:-1]) * 1024)
    return int(val_str)


def build_arg_parser():
    """Builds command-line argument parser."""
    parser = argparse.ArgumentParser(
        description=(
            "Check CP/M .COM binary against TPA memory limits"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  ./check_tpa.py SE.COM
  ./check_tpa.py --preset cpm3-banked SE.COM
  ./check_tpa.py --tpa-top 0xD800 SE.COM
  ./check_tpa.py --json SE.COM
  ./check_tpa.py --quiet SE.COM
""",
    )
    parser.add_argument(
        "com_file",
        help="Path to CP/M .COM binary to analyze (e.g. SE.COM)",
    )
    parser.add_argument(
        "--map",
        dest="map_file",
        default=None,
        help="Path to companion .map file (auto-detected if omitted)",
    )
    parser.add_argument(
        "--sym",
        dest="sym_file",
        default=None,
        help="Path to companion .sym file (auto-detected if omitted)",
    )
    parser.add_argument(
        "--preset",
        choices=list(TPA_PRESETS.keys()),
        default=DEFAULT_PRESET,
        help=(
            f"Target CP/M environment preset (default: '{DEFAULT_PRESET}'). "
            "Presets: romwbw (53.8K), cpm22-std (55K), cpm22-min (51.8K), "
            "cpm3-banked (61.2K), cpm3-nonbanked (47.8K), zsystem (51.8K)."
        ),
    )
    parser.add_argument(
        "--tpa-top",
        dest="tpa_top",
        default=None,
        type=parse_hex_or_int,
        help="Override BDOS entry address (e.g. 0xD800, $D800, 55296)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output raw machine-readable JSON (ideal for AI agents and CI)",
    )
    parser.add_argument(
        "-q",
        "--quiet",
        action="store_true",
        help="Output only one-line concise PASS/FAIL result",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Display verbose diagnostics",
    )
    parser.add_argument(
        "--plugins",
        dest="plugins_dir",
        default=None,
        nargs="?",
        const="",
        help=(
            "Audit companion .PRL/.OVL plugins against TPA overlay and "
            "Far RAM slot boundaries (auto-detected if omitted; pass "
            "'none' to disable)"
        ),
    )
    parser.add_argument(
        "--strict-plugins",
        action="store_true",
        help=(
            "Exit with code 1 if any plugin exceeds TPA overlay or "
            "Far RAM slot boundaries"
        ),
    )
    parser.add_argument(
        "--no-color",
        action="store_true",
        help="Disable ANSI color output in terminal",
    )
    return parser


def main(argv=None):
    """Main CLI entry point."""
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    if not os.path.isfile(args.com_file):
        sys.stderr.write(f"[-] Error: File not found: '{args.com_file}'\n")
        return 2

    try:
        res = analyze_com_file(
            com_path=args.com_file,
            map_path=args.map_file,
            sym_path=args.sym_file,
            tpa_top=args.tpa_top,
            preset=args.preset,
            plugins_dir=args.plugins_dir,
        )
    except Exception as e:
        sys.stderr.write(f"[-] Error analyzing '{args.com_file}': {e}\n")
        return 2

    if args.json:
        # Machine-readable output for AI agents and automation scripts
        print(json.dumps(res, indent=2))
    elif args.quiet:
        # Minimal one-line summary
        sign = "+" if res["headroom_bytes"] >= 0 else ""
        print(
            f"{res['status']}: {res['filename']} "
            f"({res['total_tpa_consumed_kb']:.2f} KB used / "
            f"{res['target_tpa_limit_kb']:.2f} KB limit, "
            f"{sign}{res['headroom_bytes']:,d} bytes free)"
        )
    else:
        # Rich visual report for human operators
        report = format_human_report(
            res, verbose=args.verbose, no_color=args.no_color
        )
        print(report)

    has_failure = res["exceeded"]
    if args.strict_plugins and res.get("plugins_status") == "FAIL":
        has_failure = True
    return 1 if has_failure else 0


if __name__ == "__main__":
    sys.exit(main())
