#!/usr/bin/env python3
"""
check_plugin.py - CP/M 3 PRL & OVL Plugin Binary & ABI Analyzer for SE.COM

Analyzes Digital Research CP/M 3 (CP/M Plus) Page-Relocatable (.PRL) and
Overlay (.OVL) plugin binaries designed for SE.COM (the CP/M full-screen
editor for RomWBW / RC2014 systems).

Validates:
  1. 256-Byte Header layout (NAME, PROG_SIZE, BSS_SIZE, LOAD_ADDR, CAPS).
  2. Size Class Slot Limits (4K <= 4,096 B, 16K <= 16,384 B, 32K <= 32,768 B).
  3. Execution model rules (16K/32K restricted from TPA overlay execution).
  4. Jump table vectors at 0x0100 (Action 0 Execute, Action 1 About,
     Action 2 Config, Action 3 Headless VFS).
  5. Relocation bitmap integrity (.PRL only: count, density, bounds).
  6. Capability bitflag consistency against implemented jump vectors.

Usable by both humans (rich visual cards & matrix table) and AI agents
(--json, --quiet, and standard exit codes: 0 = PASS, 1 = FAIL, 2 = ERROR).
"""

import argparse
import glob
import json
import os
import struct
import sys

# Standard CP/M 3 plugin execution origin
PLUGIN_ORIGIN = 0x0100

# 256-Byte Header Field Offsets & Sizes
HDR_PROG_SIZE = 0x01
HDR_BSS_SIZE = 0x04
HDR_LOAD_ADDR = 0x07
HDR_BIOS_LINK = 0x0A
HDR_NAME_OFFSET = 0x0C
HDR_NAME_LEN = 16
HDR_CAPS_OFFSET = 0x1C
HDR_MIN_SIZE = 256

# Capability Bitflags (PLUGIN_ABI.md Section 2)
CAP_TPA_EXEC = 0x0001    # Runs in 4KB TPA overlay slot (4KB only)
CAP_FAR_EXEC = 0x0002    # Executes in Far RAM via HB_BNKCALL
CAP_DOC_MUTATE = 0x0004  # Mutates document lines (triggers redraw)
CAP_MODAL_UI = 0x0008    # Renders modal UI dialog or summary box
CAP_HAS_ABOUT = 0x0010   # Implements modal About screen (ENTRY+3)
CAP_HAS_CONFIG = 0x0020  # Implements Config screen (ENTRY+6)
CAP_SIZE_4K = 0x0000     # 4KB size class (<= 4096B payload)
CAP_SIZE_8K = 0x0040     # 8KB size class (<= 8192B payload)
CAP_SIZE_16K = 0x0080    # 16KB size class (<= 16384B payload)
CAP_SIZE_32K = 0x00C0    # 32KB size class (<= 32768B payload)
CAP_SIZE_MASK = 0x00C0   # Mask for size class bits 7..6
CAP_HAS_VFS = 0x0100     # Implements Headless VFS Vector (ENTRY+9)
CAP_RESERVED_MASK = 0xFE00  # Reserved upper bits (must be 0)

# Size Class Specifications
SIZE_CLASSES = {
    CAP_SIZE_4K: {
        "name": "4K",
        "desc": "TPA Overlay / Far RAM sub-allocated",
        "limit": 4096,
        "far_pages": 16,
        "tpa_allowed": True,
    },
    CAP_SIZE_8K: {
        "name": "8K",
        "desc": "Far RAM bank (dedicated or shared sub-allocated)",
        "limit": 8192,
        "far_pages": 32,
        "tpa_allowed": True,
    },
    CAP_SIZE_16K: {
        "name": "16K",
        "desc": "Dedicated 32KB Far RAM bank",
        "limit": 16384,
        "far_pages": 64,
        "tpa_allowed": False,
    },
    CAP_SIZE_32K: {
        "name": "32K",
        "desc": "Dedicated 32KB Far RAM bank",
        "limit": 32768,
        "far_pages": 128,
        "tpa_allowed": False,
    },
}

# Jump Table Vector Actions
ACTIONS = [
    (0, "EXECUTE", 0, True, "Main execution vector (Action 0)"),
    (1, "ABOUT", 3, False, "Modal About dialog vector (Action 1)"),
    (2, "CONFIG", 6, False, "Configuration screen vector (Action 2)"),
    (3, "VFS", 9, False, "Headless VFS operations dispatcher (Action 3)"),
]


def decode_vector(chunk):
    """
    Decodes a 3-byte vector from the plugin jump table.
    Returns (disasm_str, vector_type, target_addr).
    """
    if len(chunk) < 3:
        return "TRUNCATED", "TRUNCATED", None
    b0, b1, b2 = chunk[0], chunk[1], chunk[2]
    raw_hex = f"{b0:02X} {b1:02X} {b2:02X}"
    if b0 == 0xC3:
        target = b1 | (b2 << 8)
        return f"JP 0x{target:04X}", "JUMP", target
    elif b0 == 0x37 and b1 == 0xC9:
        return "SCF ; RET", "NOT_IMPLEMENTED", None
    elif b0 == 0xC9:
        return "RET", "STUB", None
    return f"RAW ({raw_hex})", "OTHER", None


def decode_capability_flags(caps):
    """Returns a list of human-readable capability flag names."""
    flags = []
    if caps & CAP_TPA_EXEC:
        flags.append("TPA_EXEC")
    if caps & CAP_FAR_EXEC:
        flags.append("FAR_EXEC")
    if caps & CAP_DOC_MUTATE:
        flags.append("DOC_MUTATE")
    if caps & CAP_MODAL_UI:
        flags.append("MODAL_UI")
    if caps & CAP_HAS_ABOUT:
        flags.append("HAS_ABOUT")
    if caps & CAP_HAS_CONFIG:
        flags.append("HAS_CONFIG")

    sz = caps & CAP_SIZE_MASK
    if sz == CAP_SIZE_4K:
        flags.append("SIZE_4K")
    elif sz == CAP_SIZE_8K:
        flags.append("SIZE_8K")
    elif sz == CAP_SIZE_16K:
        flags.append("SIZE_16K")
    elif sz == CAP_SIZE_32K:
        flags.append("SIZE_32K")

    if caps & CAP_HAS_VFS:
        flags.append("HAS_VFS")

    rsvd = caps & CAP_RESERVED_MASK
    if rsvd:
        flags.append(f"RESERVED(0x{rsvd:04X})")

    return flags


def analyze_plugin_file(filepath):
    """
    Performs comprehensive binary, header, and ABI analysis on a plugin.
    Returns a dictionary of analysis metrics and validation status.
    """
    abs_path = os.path.abspath(filepath)
    if not os.path.isfile(abs_path):
        raise FileNotFoundError(f"File not found: '{filepath}'")

    file_size = os.path.getsize(abs_path)
    errors = []
    warnings = []

    if file_size < HDR_MIN_SIZE:
        raise ValueError(
            f"File too small ({file_size} B) to contain 256-byte header"
        )

    with open(abs_path, "rb") as f:
        data = f.read()

    hdr = data[:HDR_MIN_SIZE]
    prog_size = struct.unpack_from("<H", hdr, HDR_PROG_SIZE)[0]
    bss_size = struct.unpack_from("<H", hdr, HDR_BSS_SIZE)[0]
    load_addr = struct.unpack_from("<H", hdr, HDR_LOAD_ADDR)[0]
    bios_link = struct.unpack_from("<H", hdr, HDR_BIOS_LINK)[0]
    raw_name_bytes = hdr[HDR_NAME_OFFSET:HDR_NAME_OFFSET + HDR_NAME_LEN]
    plugin_name = raw_name_bytes.split(b"\x00")[0].decode(
        "ascii", errors="replace"
    ).strip()
    caps = struct.unpack_from("<H", hdr, HDR_CAPS_OFFSET)[0]

    # Format detection: PRL vs OVL
    ext = os.path.splitext(filepath)[1].upper()
    if ext == ".OVL":
        fmt = "OVL"
        is_prl = False
    elif ext == ".PRL":
        fmt = "PRL"
        is_prl = True
    else:
        # Infer from load address if extension is non-standard
        is_prl = (load_addr == 0x0000)
        fmt = "PRL" if is_prl else "OVL"

    # Size class resolution
    sz_bits = caps & CAP_SIZE_MASK
    sz_spec = SIZE_CLASSES.get(sz_bits)
    if sz_spec:
        size_class = sz_spec["name"]
        size_desc = sz_spec["desc"]
        slot_limit = sz_spec["limit"]
        far_pages = sz_spec["far_pages"]
        tpa_allowed = sz_spec["tpa_allowed"]
    else:
        size_class = "INVALID"
        size_desc = "Reserved / Invalid Size Class (0x00C0)"
        slot_limit = 0
        far_pages = 0
        tpa_allowed = False
        errors.append(
            "Capabilities specify invalid reserved size class (bits 7..6 = 11)"
        )

    # Slot limit validation
    headroom_bytes = slot_limit - prog_size if slot_limit > 0 else -prog_size
    headroom_kb = round(headroom_bytes / 1024.0, 3)
    headroom_pct = (
        round((headroom_bytes / slot_limit) * 100.0, 2)
        if slot_limit > 0
        else 0.0
    )
    slot_usage_pct = (
        round((prog_size / slot_limit) * 100.0, 2)
        if slot_limit > 0
        else 0.0
    )

    if slot_limit > 0 and prog_size > slot_limit:
        errors.append(
            f"Program size ({prog_size:,d} B) exceeds {size_class} slot limit "
            f"({slot_limit:,d} B) by {prog_size - slot_limit:,d} bytes"
        )

    if prog_size == 0:
        errors.append("Header declares PROG_SIZE of 0 bytes")

    # Execution model consistency checks
    can_tpa = bool(caps & CAP_TPA_EXEC)
    can_far = bool(caps & CAP_FAR_EXEC)
    if can_tpa:
        if size_class == "8K":
            bm_sz = (prog_size + 7) // 8 if is_prl else 0
            total_tpa = 256 + prog_size + bss_size + bm_sz
            if total_tpa > 5120:
                errors.append(
                    f"8K plugin runtime footprint ({total_tpa} B) exceeds "
                    f"5,120-byte TPA overlay slot"
                )
        elif not tpa_allowed:
            errors.append(
                f"{size_class} plugins cannot execute in TPA overlay slot "
                "(CAP_TPA_EXEC is restricted to 4KB and <=5KB 8KB plugins)"
            )

    if not can_tpa and not can_far:
        warnings.append(
            "Neither CAP_TPA_EXEC nor CAP_FAR_EXEC execution mode flag is set"
        )
    if caps & CAP_RESERVED_MASK:
        warnings.append(
            f"Reserved capability bits set: 0x{caps & CAP_RESERVED_MASK:04X}"
        )

    # File payload verification
    code_data = data[HDR_MIN_SIZE:HDR_MIN_SIZE + prog_size]
    if len(code_data) < prog_size:
        errors.append(
            f"File truncated: expected {prog_size:,d} bytes code, "
            f"found {len(code_data):,d} bytes"
        )

    # Relocation bitmap analysis (.PRL or relocatable .OVL)
    calc_bm_size = (prog_size + 7) // 8
    has_reloc_bitmap = is_prl or (
        load_addr == 0 and file_size >= HDR_MIN_SIZE + prog_size + calc_bm_size
    )
    bitmap_size = calc_bm_size if has_reloc_bitmap else 0
    expected_file_size = HDR_MIN_SIZE + prog_size + bitmap_size
    reloc_count = 0
    reloc_density_pct = 0.0
    invalid_trailing_bits = 0
    relocs_out_of_bounds = 0

    if has_reloc_bitmap:
        bitmap_data = data[HDR_MIN_SIZE + prog_size:]
        if len(bitmap_data) < bitmap_size:
            errors.append(
                f"Relocation bitmap truncated: expected {bitmap_size:,d} B, "
                f"found {len(bitmap_data):,d} B"
            )
        else:
            actual_bitmap = bitmap_data[:bitmap_size]
            max_page = (PLUGIN_ORIGIN + prog_size + bss_size + 255) >> 8

            # Scan bitstream
            for i in range(prog_size):
                byte_idx = i // 8
                bit_idx = 7 - (i % 8)
                if (actual_bitmap[byte_idx] >> bit_idx) & 1:
                    reloc_count += 1
                    # In Z80 little-endian, high byte of word is at code[i]
                    if i < len(code_data):
                        hi = code_data[i]
                        if hi < 1 or hi > max_page:
                            relocs_out_of_bounds += 1

            # Check trailing padding bits in last byte
            for k in range(prog_size, bitmap_size * 8):
                byte_idx = k // 8
                bit_idx = 7 - (k % 8)
                if (actual_bitmap[byte_idx] >> bit_idx) & 1:
                    invalid_trailing_bits += 1

            if invalid_trailing_bits > 0:
                warnings.append(
                    f"Relocation bitmap has {invalid_trailing_bits} non-zero "
                    "trailing padding bit(s)"
                )

            if relocs_out_of_bounds > 0:
                errors.append(
                    f"Found {relocs_out_of_bounds} relocation high-byte(s) "
                    "pointing outside program address space"
                )

            if prog_size > 0:
                reloc_density_pct = round(
                    (reloc_count / prog_size) * 100.0, 2
                )

    if file_size > expected_file_size:
        extra = file_size - expected_file_size
        warnings.append(
            f"File has {extra} trailing byte(s) beyond expected size "
            "(likely CP/M sector padding)"
        )

    # Jump table validation at offset 0x0100 (byte 256 in file)
    jump_table = []
    for action_id, action_name, act_offset, is_req, act_desc in ACTIONS:
        act_required = is_req
        if action_id == 1:
            act_required = bool(caps & CAP_HAS_ABOUT)
        elif action_id == 2:
            act_required = bool(caps & CAP_HAS_CONFIG)
        elif action_id == 3:
            act_required = bool(caps & CAP_HAS_VFS)

        chunk = code_data[act_offset:act_offset + 3]
        disasm, vtype, target = decode_vector(chunk)
        target_in_range = None
        act_status = "OK"

        if len(chunk) < 3:
            if act_required:
                act_status = "TRUNCATED"
                errors.append(
                    f"Action {action_id} ({action_name}) required but code "
                    f"is truncated at offset +{act_offset}"
                )
            else:
                act_status = "ABSENT"
        elif vtype == "JUMP":
            target_in_range = (
                PLUGIN_ORIGIN <= target < PLUGIN_ORIGIN + prog_size
            )
            if not target_in_range:
                act_status = "TARGET_OUT_OF_BOUNDS"
                errors.append(
                    f"Action {action_id} ({action_name}) jump target "
                    f"0x{target:04X} is outside code boundaries "
                    f"(0x{PLUGIN_ORIGIN:04X}..0x{PLUGIN_ORIGIN+prog_size:04X})"
                )
            elif not act_required and action_id != 0:
                # Vector is JP but capability flag is not advertised
                warnings.append(
                    f"Action {action_id} ({action_name}) is JP 0x{target:04X} "
                    f"but capability flag CAP_HAS_{action_name} is not set"
                )
        elif vtype == "NOT_IMPLEMENTED" or vtype == "STUB":
            if act_required:
                act_status = "MISSING_HANDLER"
                errors.append(
                    f"CAP_HAS_{action_name} advertised in header, but "
                    f"Action {action_id} vector contains {disasm}"
                )
            else:
                act_status = "NOT_IMPLEMENTED"
        else:
            # Other opcodes
            if act_required:
                act_status = "INVALID_OPCODE"
                errors.append(
                    f"Action {action_id} ({action_name}) required but vector "
                    f"slot contains unrecognized instruction ({disasm})"
                )
            else:
                # When Action 3 is not advertised, code body starts at +9
                act_status = "CODE_PAYLOAD"

        raw_hex = " ".join(f"{b:02X}" for b in chunk)
        jump_table.append({
            "action": action_id,
            "name": action_name,
            "offset": act_offset,
            "description": act_desc,
            "required": act_required,
            "raw_hex": raw_hex,
            "disasm": disasm,
            "vector_type": vtype,
            "target": target,
            "target_hex": f"0x{target:04X}" if target is not None else None,
            "target_in_range": target_in_range,
            "status": act_status,
        })

    # Overall verdict
    passed = (len(errors) == 0) and (headroom_bytes >= 0)
    verdict = "PASS" if passed else "FAIL"

    cap_flag_names = decode_capability_flags(caps)

    return {
        "file": abs_path,
        "filename": os.path.basename(abs_path),
        "file_size": file_size,
        "file_size_kb": round(file_size / 1024.0, 3),
        "format": fmt,
        "name": plugin_name,
        "prog_size": prog_size,
        "prog_size_kb": round(prog_size / 1024.0, 3),
        "bss_size": bss_size,
        "bss_size_kb": round(bss_size / 1024.0, 3),
        "total_memory": prog_size + bss_size,
        "total_memory_kb": round((prog_size + bss_size) / 1024.0, 3),
        "load_addr": load_addr,
        "load_addr_hex": f"0x{load_addr:04X}",
        "bios_link": bios_link,
        "capabilities_raw": caps,
        "capabilities_hex": f"0x{caps:04X}",
        "capabilities": cap_flag_names,
        "size_class": size_class,
        "size_desc": size_desc,
        "slot_limit": slot_limit,
        "slot_limit_kb": round(slot_limit / 1024.0, 2) if slot_limit else 0,
        "headroom_bytes": headroom_bytes,
        "headroom_kb": headroom_kb,
        "headroom_pct": headroom_pct,
        "slot_usage_pct": slot_usage_pct,
        "far_pages": far_pages,
        "can_tpa_exec": can_tpa,
        "can_far_exec": can_far,
        "has_reloc_bitmap": has_reloc_bitmap,
        "bitmap_size": bitmap_size,
        "reloc_count": reloc_count,
        "reloc_density_pct": reloc_density_pct,
        "invalid_trailing_bits": invalid_trailing_bits,
        "relocs_out_of_bounds": relocs_out_of_bounds,
        "jump_table": jump_table,
        "errors": errors,
        "warnings": warnings,
        "status": verdict,
    }


def format_single_report(res, verbose=False, no_color=False):
    """Formats rich human-readable diagnostic card for a single plugin."""
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
        f"   {c_bold}CP/M 3 Plugin Binary & ABI Analysis: "
        f"{res['filename']}{c_reset}"
    )
    lines.append("=" * 80)
    lines.append(f"  Plugin Name        : {res['name']}")
    lines.append(
        f"  Binary Format      : {res['format']} "
        f"({'Page-Relocatable' if res['format'] == 'PRL' else 'Overlay'})"
    )
    lines.append(
        f"  File Size On Disk  : {res['file_size']:,d} bytes "
        f"({res['file_size_kb']:.2f} KB)"
    )
    lines.append(
        f"  Load Origin        : {res['load_addr_hex']} "
        f"({'Relocatable' if res['load_addr'] == 0 else 'Fixed Address'})"
    )
    lines.append("-" * 80)

    # Memory & Slot Capacity
    lines.append(f"  {c_bold}[Memory Footprint & Slot Capacity]{c_reset}")
    lines.append(
        f"  Size Class         : {res['size_class']} Slot "
        f"({res['size_desc']})"
    )
    lines.append(
        f"  Code + Data Size   : {res['prog_size']:,d} bytes "
        f"({res['prog_size_kb']:.2f} KB / {res['slot_usage_pct']:.1f}% "
        f"of {res['slot_limit_kb']:.0f}KB slot)"
    )
    lines.append(
        f"  BSS Buffer Size    : {res['bss_size']:,d} bytes "
        f"({res['bss_size_kb']:.2f} KB)"
    )
    lines.append(
        f"  Total Memory Need  : {res['total_memory']:,d} bytes "
        f"({res['total_memory_kb']:.2f} KB)"
    )
    sign = "+" if res["headroom_bytes"] >= 0 else ""
    lines.append(
        f"  Slot Free Headroom : {c_bold}{sign}{res['headroom_bytes']:,d} bytes"
        f" ({sign}{res['headroom_kb']:.2f} KB / "
        f"{res['headroom_pct']:.1f}% margin){c_reset}"
    )
    lines.append("")

    # Capabilities & Execution Modes
    lines.append(f"  {c_bold}[Capabilities & Execution Modes]{c_reset}")
    lines.append(f"  Capabilities Word  : {res['capabilities_hex']}")
    cap_hdr = "  Capability Flags   : "
    cap_indent = " " * len(cap_hdr)
    current_cap_line = cap_hdr
    for idx, flag in enumerate(res["capabilities"]):
        sep = ", " if idx < len(res["capabilities"]) - 1 else ""
        item = flag + sep
        if len(current_cap_line) + len(item) > 78:
            lines.append(current_cap_line)
            current_cap_line = cap_indent + item
        else:
            current_cap_line += item
    if current_cap_line.strip():
        lines.append(current_cap_line)
    tpa_str = (
        "Supported (Runs in 4KB overlay slot)"
        if res["can_tpa_exec"]
        else "Restricted (Far RAM execution only)"
    )
    lines.append(f"  TPA Overlay Exec   : {tpa_str}")
    far_str = (
        "Supported (via RomWBW HB_BNKCALL proxy 0xFFF9)"
        if res["can_far_exec"]
        else "Disabled"
    )
    lines.append(f"  Far RAM Execution  : {far_str}")
    lines.append("")

    # Jump Table Vector Table
    lines.append(
        f"  {c_bold}[Jump Table Vector Table (Offset 0x0100)]{c_reset}"
    )
    for vec in res["jump_table"]:
        v_stat = vec["status"]
        if v_stat in ("OK", "NOT_IMPLEMENTED"):
            c_st = f"{c_green}{v_stat:<18}{c_reset}"
        elif v_stat == "CODE_PAYLOAD":
            c_st = f"{c_cyan}{v_stat:<18}{c_reset}"
        else:
            c_st = f"{c_red}{v_stat:<18}{c_reset}"
        lines.append(
            f"  Action {vec['action']} (+{vec['offset']:02d}h)     : "
            f"{vec['disasm']:<14} [{vec['name']:<7}] {c_st}"
        )
    lines.append("")

    # Relocation Bitmap Analysis
    lines.append(f"  {c_bold}[Relocation Bitmap Analysis]{c_reset}")
    if res["has_reloc_bitmap"]:
        lines.append(
            f"  Relocation Bitmap  : {res['bitmap_size']:,d} bytes "
            f"({res['bitmap_size'] * 8:,d} bits)"
        )
        lines.append(
            f"  Total Relocations  : {res['reloc_count']:,d} address "
            f"high-bytes ({res['reloc_density_pct']:.2f}% density)"
        )
        tgt_str = (
            "All in-bounds"
            if res["relocs_out_of_bounds"] == 0
            else f"{res['relocs_out_of_bounds']} out of bounds"
        )
        lines.append(f"  Relocation Targets : {tgt_str}")
        pad_stat = (
            "Valid (Zero-padded)"
            if res["invalid_trailing_bits"] == 0
            else f"WARNING ({res['invalid_trailing_bits']} non-zero bits)"
        )
        lines.append(f"  Trailing Pad Bits  : {pad_stat}")
    else:
        lines.append(
            "  Relocation Bitmap  : N/A (CP/M 3 Overlay format has no bitmap)"
        )
    lines.append("-" * 80)

    # Diagnostic messages
    if res["errors"]:
        lines.append(f"  {c_red}Errors Detected:{c_reset}")
        for err in res["errors"]:
            lines.append(f"    - {err}")
    if res["warnings"] and (verbose or not res["errors"]):
        lines.append(f"  {c_yellow}Warnings:{c_reset}")
        for warn in res["warnings"]:
            lines.append(f"    - {warn}")

    # Verdict
    if res["status"] == "PASS":
        verdict = (
            f"  {c_bold}VERDICT: {status_badge} Plugin conforms to SE.COM "
            f"ABI and fits within {res['size_class']} slot.\n"
            f"           Headroom: {sign}{res['headroom_bytes']:,d} bytes free "
            f"below {res['slot_limit']:,d}-byte ceiling."
        )
    else:
        verdict = (
            f"  {c_bold}VERDICT: {status_badge} Plugin FAILS ABI compliance or "
            f"exceeds slot limit!\n"
            f"           Check errors listed above."
        )
    lines.append(verdict)
    lines.append("=" * 80)
    return "\n".join(lines)


def format_multi_table(results, no_color=False):
    """
    Formats multi-plugin summary matrix table.
    Guaranteed width: strictly 79 characters.
    """
    use_color = (
        not no_color
        and sys.stdout.isatty()
        and os.environ.get("TERM") != "dumb"
    )
    c_bold = "\033[1m" if use_color else ""
    c_green = "\033[32m" if use_color else ""
    c_red = "\033[31m" if use_color else ""
    c_reset = "\033[0m" if use_color else ""

    tbl_border = (
        "  +--------------+-----+-----+---------+"
        "---------+----------+-------+------+"
    )
    tbl_hdr = (
        "  | Plugin       | Typ | Cls | Program |"
        " SlotMax | Headroom | Reloc | Stat |"
    )

    lines = []
    lines.append("")
    lines.append(
        f"  {c_bold}SE.COM Plugin Size & ABI Validation Summary:{c_reset}"
    )
    lines.append(tbl_border)
    lines.append(tbl_hdr)
    lines.append(tbl_border)

    for r in results:
        fname = r["filename"]
        if len(fname) > 12:
            fname = fname[:11] + "~"
        fmt = r["format"]
        s_class = r["size_class"]
        prog_b = f"{r['prog_size']:,d}B"
        slot_b = f"{r['slot_limit']:,d}B" if r["slot_limit"] else "N/A"
        sign = "+" if r["headroom_bytes"] >= 0 else ""
        head_b = f"{sign}{r['headroom_bytes']:,d}B"
        relocs = f"{r['reloc_count']:,d}" if r["has_reloc_bitmap"] else "N/A"

        c_stat = (
            f"{c_green}PASS{c_reset}"
            if r["status"] == "PASS"
            else f"{c_red}FAIL{c_reset}"
        )

        row = (
            f"  | {fname:<12} | {fmt:<3} | {s_class:>3} | "
            f"{prog_b:>7} | {slot_b:>7} | {head_b:>8} | "
            f"{relocs:>5} | {c_stat} |"
        )
        lines.append(row)

    lines.append(tbl_border)
    lines.append("")
    return "\n".join(lines)


def build_arg_parser():
    """Builds command-line argument parser."""
    parser = argparse.ArgumentParser(
        description=(
            "Check SE.COM plugin binary size, header, and ABI conformance"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  ./check_plugin.py plugins/FATFS.PRL
  ./check_plugin.py --all
  ./check_plugin.py plugins/*.PRL plugins/*.OVL
  ./check_plugin.py --json plugins/FATFS.PRL
  ./check_plugin.py --quiet --all
""",
    )
    parser.add_argument(
        "plugin_files",
        nargs="*",
        default=[],
        help="Path to plugin .PRL or .OVL binary file(s)",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Scan all .PRL and .OVL files in plugins/ directory",
    )
    parser.add_argument(
        "--dir",
        dest="plugin_dir",
        default=None,
        help=(
            "Base directory to search for plugins with --all (default: plugins)"
        ),
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output machine-readable JSON (ideal for AI agents and CI/CD)",
    )
    parser.add_argument(
        "-q",
        "--quiet",
        action="store_true",
        help="Output concise one-line status per plugin",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Display verbose diagnostics",
    )
    parser.add_argument(
        "--no-color",
        action="store_true",
        help="Disable ANSI color output in terminal",
    )
    return parser


def find_plugins_in_dir(search_dir):
    """Finds all unique .PRL and .OVL plugin binaries in directory tree."""
    if not os.path.isdir(search_dir):
        return []
    candidates = []
    seen_hashes = {}
    for root, _, files in os.walk(search_dir):
        for f in sorted(files):
            u = f.upper()
            if u.endswith(".PRL") or u.endswith(".OVL"):
                fpath = os.path.join(root, f)
                try:
                    with open(fpath, "rb") as fp:
                        content_hash = hash(fp.read())
                    if content_hash in seen_hashes:
                        continue
                    seen_hashes[content_hash] = fpath
                    candidates.append(fpath)
                except OSError:
                    candidates.append(fpath)
    return sorted(candidates)


def main(argv=None):
    """Main CLI entry point."""
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    target_files = list(args.plugin_files)

    if args.all or not target_files:
        # Determine plugins directory
        search_dirs = []
        if args.plugin_dir:
            search_dirs.append(args.plugin_dir)
        else:
            # Check likely locations
            here = os.path.dirname(os.path.abspath(__file__))
            search_dirs.extend([
                os.path.join(here, "plugins"),
                os.path.join(os.getcwd(), "plugins"),
                os.path.join(here, "..", "plugins"),
                here,
            ])

        found = []
        for sdir in search_dirs:
            p = find_plugins_in_dir(sdir)
            if p:
                found = p
                break

        if args.all or not target_files:
            if not found and not target_files:
                sys.stderr.write(
                    "[-] Error: No plugin files specified and none found "
                    "in plugins/ directory.\n"
                )
                return 2
            # Add found files without duplicating
            existing_sets = {os.path.abspath(f) for f in target_files}
            for f in found:
                if os.path.abspath(f) not in existing_sets:
                    target_files.append(f)
                    existing_sets.add(os.path.abspath(f))

    # Deduplicate canonical paths while preserving order
    seen = set()
    deduped = []
    for f in target_files:
        norm = os.path.normpath(f)
        if norm not in seen:
            deduped.append(norm)
            seen.add(norm)
    target_files = deduped

    results = []
    has_error = False

    for fpath in target_files:
        if not os.path.isfile(fpath):
            sys.stderr.write(f"[-] Error: File not found: '{fpath}'\n")
            has_error = True
            continue
        try:
            res = analyze_plugin_file(fpath)
            results.append(res)
        except Exception as e:
            sys.stderr.write(f"[-] Error analyzing '{fpath}': {e}\n")
            has_error = True

    if not results:
        return 2

    any_fail = any(r["status"] == "FAIL" for r in results)

    # Machine-readable JSON output for AI agents & automation
    if args.json:
        if len(results) == 1:
            print(json.dumps(results[0], indent=2))
        else:
            summary = {
                "total": len(results),
                "passed": sum(1 for r in results if r["status"] == "PASS"),
                "failed": sum(1 for r in results if r["status"] == "FAIL"),
                "status": "FAIL" if any_fail else "PASS",
                "plugins": results,
            }
            print(json.dumps(summary, indent=2))
        return 1 if any_fail else (2 if has_error else 0)

    # Quiet mode: concise one-line summary per plugin
    if args.quiet:
        for r in results:
            sign = "+" if r["headroom_bytes"] >= 0 else ""
            reloc_info = (
                f", {r['reloc_count']:,d} relocs"
                if r["has_reloc_bitmap"]
                else ""
            )
            print(
                f"{r['status']}: {r['filename']} "
                f"({r['size_class']}: {r['prog_size']:,d} / "
                f"{r['slot_limit']:,d} B, "
                f"{sign}{r['headroom_bytes']:,d} B free{reloc_info})"
            )
        return 1 if any_fail else (2 if has_error else 0)

    # Human-readable output:
    # If 1 file was analyzed, show rich diagnostic card.
    # If multiple files, show summary matrix table (plus cards if verbose
    # or failed).
    if len(results) == 1:
        report = format_single_report(
            results[0], verbose=args.verbose, no_color=args.no_color
        )
        print(report)
    else:
        table = format_multi_table(results, no_color=args.no_color)
        print(table)
        if args.verbose or any_fail:
            for r in results:
                if args.verbose or r["status"] == "FAIL":
                    print(
                        format_single_report(
                            r, verbose=args.verbose, no_color=args.no_color
                        )
                    )

    return 1 if any_fail else (2 if has_error else 0)


if __name__ == "__main__":
    sys.exit(main())
