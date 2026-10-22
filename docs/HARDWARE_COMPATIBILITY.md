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
  - Dual ACIA serial or SIO/2 serial interfaces at 115200 bps.
- **Small Computer Central SC126 / SC130 / SC131**:
  - Z180 / Z80 motherboards running RomWBW v3.6.0+ firmware.
- **Zeta 2 SBC**:
  - Z80 single-board computer with floppy and IDE CF interfaces.
- **RetroBrew SBC-180**:
  - Z180 high-speed systems with banked memory architectures.

---

## 4. Foreign Filesystem & Removable Storage Access (FAT / SD Card)

`SE.COM` and `SEC.COM` support direct reading, writing, and directory browsing
of foreign FAT filesystems (FAT12, FAT16, and FAT32) residing on SD cards,
CompactFlash cards, and IDE drives via RomWBW HBIOS disk devices and the
modular `FATFS.PRL` Far RAM VFS plugin.

### 4.1 Architecture & Device Mapping

RomWBW HBIOS enumerates block storage devices into physical disk units:
- **`U0:` through `U7:`**: Logical HBIOS disk units. On RomWBW systems,
  unit numbers correspond to enumerated hardware interfaces (e.g. `U0:` /
  `U1:` for primary/secondary IDE/CF, `U2:` / `U4:` for SD card interfaces
  like the RC2014 SD Module or SC126/SC131 onboard SPI SD reader).
- **`U:` (Default Unit)**: Refers to the first available non-CP/M removable
  storage device discovered during RomWBW startup (unit `0xFF` internally).

### 4.2 Far RAM VFS Subsystem & `FATFS.PRL`

Foreign drive access does not consume precious CP/M 64KB TPA memory:
1. **Dynamic Plugin Execution**:
   The FAT filesystem driver is packaged as an independent 32KB Far RAM
   plugin (`FATFS.PRL`). When loaded into a plugin slot, it runs in a banked
   Far RAM page and exports Headless VFS operations via Action 3 (`ENTRY + 9`).
2. **Path Syntax & Virtual Drives**:
   Users can navigate and edit files on foreign drives using canonical path
   syntax:
   - `U<unit>:<path>` (e.g. `U4:`, `U4:SLICES.TXT`, `U4:/TURBOPAS/HELLO.PAS`).
   - Root navigation: Typing `U4:` in Open/Save switches the directory view to
     the FAT volume root (`/`).
   - Subdirectory navigation: Typing a directory name (e.g. `TURBOPAS/`)
     descends into the subdirectory; typing `..` ascends to the parent.
   - Wildcard filtering: Patterns such as `*.PAS` or `*.*` filter directory
     listings while preserving subdirectories.
3. **Missing Plugin Safeguard**:
   If a user specifies a FAT path prefix (`U0:`..`U7:` or `U:`) while
   `FATFS.PRL` is not loaded in the plugin registry, the editor intercepts the
   request and presents a modal alert:
   ```text
   +------------------------------------------------+
   |              FAT Subsystem Missing             |
   +------------------------------------------------+
   |           Feature requires FATFS.PRL.          |
   |      FAT filesystem plugin is not loaded.      |
   +------------------------------------------------+
   ```
4. **Byte Fidelity & Endianness**:
   `FATFS.PRL` transparently converts between CP/M CRLF line conventions and
   DOS/FAT text encodings without losing byte fidelity across sector
   boundaries.

---

## 5. ZX Spectrum Next Hardware & System Requirements

Starting with v1.1.0, the `SE` editor natively supports the **ZX Spectrum Next**
platform across both CP/M emulation and native NextZXOS operating environments.

### 5.1 Hardware & FPGA Core Requirements

| Subsystem | Requirement | Notes |
| :--- | :--- | :--- |
| **FPGA Core** | Core 3.01.00 or later | Core 3.0+ required for NextRegs |
| **CPU** | Z80N (28 MHz Turbo) | Configured via NextReg 0x07 |
| **SRAM** | 1024KB or 2048KB | Internal static RAM expansion |
| **MMU** | NextReg 0x50–0x57 | 8KB page banking across SRAM |
| **Storage** | SD Card via DivMMC / NextZXOS | FAT16 / FAT32 filesystem |
| **Display** | 80x24 Column Text Stream | Via RST 10H or NextCPM console |
| **Keyboard** | Sinclair Matrix (Port 0xFE) | Full WordStar cursor navigation |

### 5.2 Next Architectural Features Utilized

1. **28 MHz CPU Turbo Mode**:
   - At startup, native Next targets (`SE.NEX` and `.se`) program NextReg
     `0x07` (`0x03` = 28 MHz turbo). This provides 8x to 10x the processing
     throughput of standard 3.5 MHz / 4 MHz retro Z80 platforms.
2. **NextReg MMU 8KB Banking**:
   - NextRegs `0x50` through `0x57` control 8KB memory banking across physical
     slots 0 through 7 (spanning the full 64KB Z80 address space).
   - Document line buffers, Far RAM edit pools, and transient plugins are
     dynamically paged into 8KB slots without consuming base execution memory.
3. **NextZXOS / ESXDOS Storage Services**:
   - The native `.se` dot command and `SE.NEX` standalone application invoke
     the NextZXOS kernel via `RST 08H` ESXDOS API vectors (`M_GETSETDRV`,
     `F_OPEN`, `F_CLOSE`, `F_READ`, `F_WRITE`, `F_SEEK`) for direct,
     zero-copy FAT filesystem access.
4. **NextCPM Console & Storage Integration**:
   - Under NextCPM (`SE_NEXT.COM`), standard CP/M BDOS console calls (Functions
     1, 2, 6, 9) and BIOS vectors are routed to the NextCPM 80-column console
     driver with Sinclair keyboard translation.

### 5.3 Verified Next Emulators

- **CSpect** (by Mike Dailly):
  - Recommended launch flags: `-w3 -zxnext -nextrom -mmc=<next_sd.img>`
  - Requires `enNextFileSystem.dll` and standard NextZXOS system files.
- **ZEsarUX** (by Cesar Hernandez):
  - Machine selection: `--tbblue-features` / `ZX Spectrum Next`.
  - Supports 28 MHz turbo execution, NextReg MMU banking, and DivMMC SD images.

---

## 6. Operating System Compatibility Matrix

Memory footprint verified with `check_tpa.py` against `SE.COM` (v1.1.0):


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

## 7. Terminal Emulator Configuration

For optimal full-screen editing over serial connections, configure your
terminal emulator (Minicom, PuTTY, TeraTerm, screen, or Windows Terminal)
as follows:

- **Speed / Framing**: `115200 bps 8N1` (or SBC default speed).
- **Flow Control**: Full-duplex RTR/CTS hardware flow control via the
  RTS/CTS pins (strongly recommended).
- **Terminal Emulation**: `VT100`, `VT102`, or `ANSI`.
- **Screen Geometry**:
  - Modern Default: **120 columns $\times$ 40 rows** (`SE` splash mode `1`).
  - Classic Retro: **80 columns $\times$ 24 rows** (`SE` splash mode `2`).
- **Backspace Key**: Set to emit `BS` (`0x08`) or `DEL` (`0x7F`).
- **Character Encoding**: Standard 7-bit ASCII or ISO-8859-1 (Latin-1).

---

## 8. Operational Troubleshooting & Diagnostics

If your system displays `[256 lines (RAM)]` or encounters serial flow control
issues, consult the dedicated [Troubleshooting Guide](TROUBLESHOOTING.md) for
step-by-step resolution procedures.


