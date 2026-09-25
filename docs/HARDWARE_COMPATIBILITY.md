# SE.COM Hardware & System Compatibility Guide

This document specifies the hardware, firmware, and operating system
requirements for running **`SE.COM`**.

---

## 1. System Requirements

| Subsystem | Requirement | Notes |
| :--- | :--- | :--- |
| **CPU** | Zilog Z80, Z180, or compatible | Uses standard Z80 instruction set |
| **Base RAM** | 64KB System RAM | Minimum 48KB TPA (BDOS at 0xC000+) |
| **Far RAM** | 512KB Banked RAM (Optional) | Required for files > 40 lines |
| **Firmware** | RomWBW HBIOS 2.9+ / 3.x | Required for Far RAM bank switching |
| **OS** | CP/M 2.2, CP/M 3.0, or Z-System | Standard BDOS / BIOS entry points |
| **Terminal** | VT100 / VT102 / ANSI | Serial console or memory-mapped video |

---

## 2. Verified Systems and Single-Board Computers

`SE.COM` has been tested and verified on the following hardware platforms:

- **RC2014 Pro / Classic II / Micro**:
  - Full support with RomWBW HBIOS 512KB RAM/ROM modules.
  - Dual ACIA serial or SIO/2 serial interfaces at 115200 baud.
- **Small Computer Central SC126 / SC130 / SC131**:
  - Z180 / Z80 motherboards running RomWBW firmware.
- **Zeta 2 SBC**:
  - Z80 single-board computer with floppy and IDE CF interfaces.
- **RetroBrew SBC-180**:
  - Z180 high-speed systems with banked memory architectures.

---

## 3. Operating System Compatibility Matrix

Memory footprint verified with `check_tpa.py`:

- **RomWBW RC2014 CP/M 2.2 (BDOS at 0xD800)**:
  - Full support. High-performance banked document buffer active.
  - TPA Headroom: **+6,784 bytes free** (+6.62 KB margin).
- **Standard 64K CP/M 2.2 (BDOS at 0xDC00)**:
  - Full support. TPA Headroom: **+7,808 bytes free**.
- **Minimal 64K CP/M 2.2 (BDOS at 0xD000)**:
  - Full support. TPA Headroom: **+4,736 bytes free**.
- **CP/M Plus 3.0 Banked (BDOS at 0xF600)**:
  - Full support. TPA Headroom: **+14,464 bytes free**.
- **CP/M Plus 3.0 Non-Banked (BDOS at 0xC000)**:
  - Supported with `PLUGIN.PRL` extracted.
  - TPA Headroom: **+640 bytes free**.
- **Z-System / ZSDOS (BDOS at 0xD000)**:
  - Full support with standard CCP/FCP/RCP/NDR buffers.
  - TPA Headroom: **+4,736 bytes free**.

---

## 4. Terminal Emulator Configuration

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
