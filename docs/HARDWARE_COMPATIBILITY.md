# SE.COM Hardware & System Compatibility Guide

This document specifies the hardware, firmware, and operating system
requirements for running **`SE.COM`**.

---

## 1. System Requirements

`SE.COM` is strictly designed, implemented, and supported to run on **RomWBW
v3.6.0 and later**. Pre-v3.6.0 firmware releases and non-RomWBW platforms are
explicitly unsupported.

| Subsystem | Requirement | Notes |
| :--- | :--- | :--- |
| **CPU** | Zilog Z80, Z180, or compat. | Standard Z80 instruction set |
| **Base RAM** | 64KB System RAM | Min 51.75KB TPA (BDOS >= 0xD000) |
| **Far RAM** | 512KB Banked RAM | Document buffer & plugins |
| **Firmware** | RomWBW HBIOS v3.6.0+ (REQ.) | Core HBIOS API & Far RAM |
| **OS** | RomWBW CP/M 2.2 / CP/M 3 | CP/M BDOS / BIOS services |
| **Terminal** | VT100 / VT102 / ANSI | 120x40 modern or 80x24 classic |

---

## 2. Why RomWBW v3.6.0 or Later is Strictly Required

`SE.COM` breaks the traditional 64KB CP/M memory barrier by utilizing RomWBW
HBIOS architectural features. Running on systems earlier than RomWBW v3.6.0 or
generic CP/M implementations is unsupported due to the following dependencies:

### 2.1 Standardized HBIOS `RST 08H` API Services

`SE.COM` relies directly on RomWBW HBIOS firmware calls via vector `RST 08H`:
- **`BF_SYSGET` (Function `0xF8`)**: Probes installed physical RAM bank counts,
  identifies active CP/M bank mappings, and discovers RAM disk memory layouts.
- **`BF_SYSCOPY` (Function `0xFA`)**: High-speed inter-bank block memory
  transfers between Common RAM (0x8000..0xFFFF) and Far RAM banks. This avoids
  CPU-bound byte-by-byte manual copy loops and enables instant document paging.
- **`BF_SYSSET` (Function `0xF9`)**: Configures physical bank mapping and
  hardware settings.

RomWBW v3.6.0 finalized and standardized the signatures, register contracts,
and calling conventions for these services across all supported architectures.

### 2.2 Hardware-Agnostic Banked Memory Model

Different Z80 and Z180 SBCs implement bank switching using distinct hardware
mechanisms:
- RC2014 512KB RAM/ROM modules use 74HCT670 register-based bank selectors.
- SC126, SC130, and SC131 utilize integrated Z180 MMU registers (`BBR` / `CBR`).
- Zeta 2 and SBC-180 use custom CPLD or latch-based bank decoders.

RomWBW v3.6.0 unifies all hardware variations behind a standardized 32KB/64KB
logical bank interface. `SE.COM` programs exclusively against this HBIOS
abstraction layer, enabling a single unified binary (`SE.COM`) to operate across
all compliant single-board computers without recompilation.

### 2.3 RAM Drive (`A:`) Introspection & Protection

RomWBW typically assigns drive `A:` to an in-memory RAM disk located in upper
RAM banks. `SE.COM` provides three protection modes:
1. **Preserve Mode**: Detects the RAM disk boundary via RomWBW v3.6.0 disk
   allocation tables and caps editor bank allocation below the RAM disk.
2. **Hibernate Mode**: Backs up RAM disk structures to a temporary swap file on
   persistent media, reclaims banks for large documents, and restores the RAM
   disk upon exit.
3. **Overwrite Mode**: Frees all Far RAM banks for document editing.

Pre-v3.6.0 firmware lacks consistent disk descriptor layouts, risking silent
corruption of RAM disk filesystems.

### 2.4 Standardized 512-Byte Disk Geometries

RomWBW v3.6.0 standardizes 512-byte per sector IDE, CF, and SD storage drivers
(`wbw_hd1k_0` / `hd1k_combo.img`), guaranteeing deterministic sector buffering
and file I/O behavior across all supported media types.

### 2.5 Risks of Running on Unsupported Systems

Attempting to run `SE.COM` on non-RomWBW platforms or pre-v3.6.0 firmware
causes:
- Complete failure to allocate Far RAM document page slots.
- CPU lockups or fatal illegal instruction traps when executing `RST 08H`.
- Uncontrolled overwriting of upper memory banks and RAM disk data.

---

## 3. Verified Systems and Single-Board Computers

`SE.COM` is tested and verified on the following hardware platforms running
**RomWBW v3.6.0 or later**:

- **RC2014 Pro / Classic II / Micro**:
  - Full support with RomWBW HBIOS 512KB RAM/ROM modules.
  - Dual ACIA serial or SIO/2 serial interfaces at 115200 baud.
- **Small Computer Central SC126 / SC130 / SC131**:
  - Z180 / Z80 motherboards running RomWBW v3.6.0+ firmware.
- **Zeta 2 SBC**:
  - Z80 single-board computer with floppy and IDE CF interfaces.
- **RetroBrew SBC-180**:
  - Z180 high-speed systems with banked memory architectures.

---

## 4. Operating System Compatibility Matrix

Memory footprint verified with `check_tpa.py` against `SE.COM` (v0.9.9):

| Environment | BDOS | TPA | Used | Margin | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **RomWBW RC2014** | 0xD800 | 53.75K | 51.75K | +2,048 B | **PASS** |
| **Standard 64K CP/M** | 0xDC00 | 54.75K | 51.75K | +3,072 B | **PASS** |
| **Minimal 64K CP/M** | 0xD000 | 51.75K | 51.75K | +0 B | **PASS** |
| **CP/M Plus (Banked)** | 0xF600 | 61.25K | 51.75K | +9,728 B | **PASS** |
| **CP/M Plus (Non-Bnk)** | 0xC000 | 47.75K | 51.75K | -4,096 B | **FAIL** |
| **Z-System / ZSDOS** | 0xD000 | 51.75K | 51.75K | +0 B | **PASS** |

*Note: Environments require RomWBW HBIOS v3.6.0+ services underneath CP/M to
support Far RAM document buffering.*

- **RomWBW RC2014 CP/M 2.2 (BDOS at 0xD800)**:
  - Official target platform. Full support with banked Far RAM buffers.
  - TPA Headroom: **+2,048 bytes free** (+2.00 KB margin).
- **CP/M Plus 3.0 Non-Banked (BDOS at 0xC000)**:
  - **Unsupported (FAIL)**: Non-banked CP/M Plus top of memory leaves only
    47.75 KB TPA, which cannot accommodate the 51.75 KB footprint of `SE.COM`.

---

## 5. Terminal Emulator Configuration

For optimal full-screen editing over serial connections, configure your
terminal emulator (Minicom, PuTTY, TeraTerm, screen, or Windows Terminal)
as follows:

- **Baud Rate**: `115200 8N1` (or SBC default speed).
- **Flow Control**: Hardware (RTS/CTS) strongly recommended.
- **Terminal Emulation**: `VT100`, `VT102`, or `ANSI`.
- **Screen Geometry**:
  - Modern Default: **120 columns $\times$ 40 rows** (`SE` splash mode `1`).
  - Classic Retro: **80 columns $\times$ 24 rows** (`SE` splash mode `2`).
- **Backspace Key**: Set to emit `BS` (`0x08`) or `DEL` (`0x7F`).
- **Character Encoding**: Standard 7-bit ASCII or ISO-8859-1 (Latin-1).

---

## 6. Operational Troubleshooting & Diagnostics

If your system displays `[256 lines (RAM)]` or encounters serial flow control
issues, consult the dedicated [Troubleshooting Guide](TROUBLESHOOTING.md) for
step-by-step resolution procedures.

