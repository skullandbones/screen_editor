#!/usr/bin/env python3
"""
check_ccp.py - CP/M CCP (Console Command Processor) Headroom & Integrity Auditor

Audits CP/M .COM binaries (specifically SE.COM) to verify that runtime memory
and BSS buffers do not penetrate or corrupt the Console Command Processor (CCP).

Unlike programs that warm-boot on exit via BIOS WBOOT (JP 0x0000), SE.COM
exits via direct RET to the CCP (LD SP,(SAVED_SP) / RET) for instant sub-
millisecond return to the CP/M command line. Corrupting the CCP causes an
immediate exit hang.

Standard TPA checks test against the BDOS entry point (e.g. 0xD800 on RomWBW),
which includes the 2,048-byte CCP region (0xD000..0xD7FF) as usable space.
This tool strictly enforces the 0xD000 CCP boundary and audits the 256-byte
page alignment margin to detect cliff-edge overflow risks before they occur.
"""

import argparse
import json
import os
import re
import sys

# Standard CP/M TPA load origin
CPM_TPA_ORIGIN = 0x0100

# RomWBW CP/M 2.2 Console Command Processor (CCP) base address
DEFAULT_CCP_BASE = 0xD000

# Expected BSS buffer size (LINE_STORAGE: 40 lines x 128 bytes = 5,120 bytes)
DEFAULT_BSS_SIZE = 5120


def find_companion_file(com_path, extension):
    """Locate companion .map or .sym file."""
    base_dir = os.path.dirname(os.path.abspath(com_path))
    stem = os.path.splitext(os.path.basename(com_path))[0]
    candidates = [
        os.path.join(base_dir, f"{stem}.{extension}"),
        os.path.join(base_dir, f"{stem.lower()}.{extension}"),
        os.path.join(base_dir, "src", f"{stem}.{extension}"),
        os.path.join(base_dir, "src", f"{stem.lower()}.{extension}"),
    ]
    for path in candidates:
        if os.path.isfile(path):
            return path
    return None


def parse_symbols(map_path, sym_path):
    """Extract symbol dictionary from companion map and symbol files."""
    symbols = {}
    # Parse .sym first, then .map so .map has final authority
    files_to_parse = [
        f for f in (sym_path, map_path) if f and os.path.isfile(f)
    ]

    for fpath in files_to_parse:
        with open(fpath, "r", encoding="latin1") as f:
            for line in f:
                line = line.strip()
                m = re.match(
                    r"^([A-Za-z0-9_]+)\s*(?:=|EQU)\s*\$?([0-9A-Fa-f]+)",
                    line,
                )
                if m:
                    name = m.group(1)
                    val_str = m.group(2)
                    try:
                        val = int(val_str, 16)
                        if val != 0 or name not in symbols:
                            symbols[name] = val
                    except ValueError:
                        pass
    return symbols


def audit_ccp_headroom(
    com_path,
    ccp_base=DEFAULT_CCP_BASE,
    map_path=None,
    sym_path=None,
):
    """
    Audits com_path against the CCP base boundary.
    Returns structured results dict.
    """
    com_abs = os.path.abspath(com_path)
    if not os.path.isfile(com_abs):
        raise FileNotFoundError(f"Binary file not found: {com_path}")

    filesize = os.path.getsize(com_abs)
    code_end = CPM_TPA_ORIGIN + filesize

    if not map_path:
        map_path = find_companion_file(com_abs, "map")
    if not sym_path:
        sym_path = find_companion_file(com_abs, "sym")

    symbols = parse_symbols(map_path, sym_path)

    # Determine BSS start, BSS end, and stack top
    local_stack = symbols.get("LOCAL_STACK")
    bss_start = None
    for sym in (
        "BSS_START",
        "_BSS_START",
        "__BSS_START",
        "_bss_start",
        "__bss_start",
        "__BSS_head",
    ):
        if sym in symbols:
            bss_start = symbols[sym]
            break

    bss_end = None
    for sym in (
        "BSS_END",
        "_BSS_END",
        "__BSS_END",
        "_bss_end",
        "__bss_end",
        "__BSS_END_tail",
        "__BSS_END_head",
        "__tail",
    ):
        if sym in symbols and symbols[sym] >= code_end:
            bss_end = symbols[sym]
            break

    # If symbols missing, infer page-aligned BSS layout
    if bss_start is None:
        bss_start = (code_end + 255) & ~255
    if bss_end is None:
        line_storage_size = symbols.get("LINE_STORAGE_SIZE", DEFAULT_BSS_SIZE)
        bss_end = bss_start + line_storage_size
    else:
        line_storage_size = symbols.get(
            "LINE_STORAGE_SIZE", bss_end - bss_start
        )

    # Calculate page margin before next ALIGN 256 bump
    code_page_base = code_end & ~255
    next_page_boundary = (code_end + 255) & ~255
    if local_stack is not None:
        align_boundary = (local_stack + 255) & ~255
        page_margin = align_boundary - local_stack
    else:
        page_margin = next_page_boundary - code_end

    # CCP Headroom calculation
    ccp_headroom = ccp_base - bss_end
    max_safe_code_end = ccp_base - line_storage_size

    # Status evaluation
    if bss_end > ccp_base:
        status = "FAIL"
        summary = (
            f"OVERFLOW: Runtime memory penetrates {abs(ccp_headroom)} "
            f"bytes into CCP (0x{ccp_base:04X})!"
        )
    elif code_end > max_safe_code_end:
        status = "FAIL"
        summary = (
            f"OVERFLOW: Binary on disk ({code_end:#06x}) exceeds "
            f"maximum safe code end ({max_safe_code_end:#06x})!"
        )
    else:
        status = "PASS"
        summary = (
            f"CCP preserved: BSS_END (0x{bss_end:04X}) <= CCP base "
            f"(0x{ccp_base:04X}). Headroom: +{ccp_headroom} B."
        )

    return {
        "file": com_abs,
        "filename": os.path.basename(com_abs),
        "filesize": filesize,
        "load_origin": CPM_TPA_ORIGIN,
        "code_end": code_end,
        "local_stack": local_stack,
        "page_margin": page_margin,
        "bss_start": bss_start,
        "bss_end": bss_end,
        "bss_size": bss_end - bss_start,
        "ccp_base": ccp_base,
        "ccp_headroom": ccp_headroom,
        "max_safe_code_end": max_safe_code_end,
        "status": status,
        "summary": summary,
    }


def format_report(res):
    """Format visual diagnostic report."""
    border = "=" * 80
    sep = "-" * 80
    lines = [
        border,
        "   CP/M CCP (Console Command Processor) Integrity & Headroom Audit",
        border,
        f"  Target Binary     : {res['filename']} ({res['filesize']:,} bytes)",
        f"  Load Origin       : 0x{res['load_origin']:04X}",
        f"  Code + Data End   : 0x{res['code_end']:04X} "
        f"(Max Safe: 0x{res['max_safe_code_end']:04X})",
    ]

    if res["local_stack"] is not None:
        lines.append(
            f"  LOCAL_STACK End   : 0x{res['local_stack']:04X} "
            f"({res['page_margin']} bytes margin to ALIGN 256 page)"
        )
    else:
        lines.append(
            f"  Page Align Margin : {res['page_margin']} bytes "
            f"remaining before next 256-byte page"
        )

    lines.extend([
        f"  BSS Allocation    : 0x{res['bss_start']:04X} .. "
        f"0x{res['bss_end']:04X} ({res['bss_size']:,} bytes)",
        sep,
        f"  CCP Base Boundary : 0x{res['ccp_base']:04X} ({res['ccp_base']:,})",
        f"  Runtime Memory Top: 0x{res['bss_end']:04X} ({res['bss_end']:,})",
    ])

    if res["ccp_headroom"] >= 0:
        lines.append(
            f"  CCP Headroom      : +{res['ccp_headroom']:,} bytes "
            f"[CCP 100% PRESERVED]"
        )
    else:
        lines.append(
            f"  CCP Headroom      : -{abs(res['ccp_headroom']):,} bytes "
            f"[CRITICAL: CCP OVERWRITTEN!]"
        )

    lines.append(
        f"  Page Cliff Margin : {res['page_margin']} bytes before code "
        f"triggers 256-byte alignment bump"
    )
    lines.append(sep)

    if res["status"] == "PASS":
        lines.append(
            f"  VERDICT: [ PASS ] {res['summary']}"
        )
    else:
        lines.append(
            f"  VERDICT: [ FAIL ] {res['summary']}"
        )
        lines.append(
            "  ACTION REQUIRED : Trim code size to prevent CCP corruption "
            "and exit hang."
        )

    lines.append(border)
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Audit CP/M binary CCP headroom and page alignment margin."
    )
    parser.add_argument(
        "target",
        nargs="?",
        default="SE.COM",
        help="Path to .COM binary to audit (default: SE.COM)",
    )
    parser.add_argument(
        "--ccp-base",
        type=lambda x: int(x, 0),
        default=DEFAULT_CCP_BASE,
        help="Base address of CCP in hex or decimal (default: 0xD000)",
    )
    parser.add_argument(
        "--map",
        dest="map_path",
        default=None,
        help="Path to .map file",
    )
    parser.add_argument(
        "--sym",
        dest="sym_path",
        default=None,
        help="Path to .sym file",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output results in JSON format",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress output, exit code indicates status",
    )

    args = parser.parse_args()

    try:
        res = audit_ccp_headroom(
            args.target,
            ccp_base=args.ccp_base,
            map_path=args.map_path,
            sym_path=args.sym_path,
        )
    except Exception as e:
        if not args.quiet:
            print(f"[-] Error: {e}", file=sys.stderr)
        sys.exit(2)

    if args.json:
        print(json.dumps(res, indent=2))
    elif not args.quiet:
        print(format_report(res))

    if res["status"] != "PASS":
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
