# FAT Filesystem Plugin Architecture & Implementation Plan
**Plugin Identifier: `FATFS.PRL` / `FATLOAD.PRL`**  
**Target Platform: SE.COM v0.9.7+ on RomWBW CP/M 2.2 / CP/M 3.0**  
**Author: Antigravity Agent**  
**Status: Planning & Specification Phase**  

---

## 1. Executive Summary & Constraints

### 1.1 Goal
Create a modular CP/M 3 plugin (`FATFS.PRL`) that enables **`SE.COM`** to read (and optionally write) text files residing on **FAT12 / FAT16 / FAT32 partitions** of SD cards or CompactFlash cards connected to RomWBW hardware (such as the SC131, RC2014, SC126).

### 1.2 Strict Invariants
1. **Zero Modifications to `SE.COM`**: The host editor (`src/se.asm`, `Makefile`, etc.) is actively maintained by another agent and must remain untouched.
2. **Hard 4KB Binary Limit**: `SE.COM`'s existing plugin loader (`LOAD_PLUGIN_BY_NAME` at line 19326) strictly enforces `PROG_SIZE <= 4096`. The assembled code, constant tables, and initialized data must fit within **4,096 bytes**.
3. **No External Runtime Bloat**: Because standard C libraries (like FatFs / `ff.c`) compile to 15KB–40KB with 32-bit runtime emulation, the 4KB plugin will be implemented in **100% hand-crafted Z80 assembly**, optimized specifically for text file extraction.
4. **Hardware Agnostic via HBIOS**: The plugin will not talk directly to SPI or CF hardware registers; it will leverage RomWBW's standardized **HBIOS `RST 08H`** disk I/O vectors.

---

## 2. Technical Feasibility & The 4KB Budget

### 2.1 Why Generic FatFs Exceeds 4KB
RomWBW's standalone `FAT.COM` binary is **40,442 bytes** because it includes Elm-Chan's full generic `ff.c`, SDCC C-runtime 32-bit math, Unicode/OEM LFN tables, formatting, and sub-directory manipulation.

### 2.2 Why a Hand-Crafted Z80 ASM Driver Fits in $\le 4\text{KB}$
A specialized FAT reader/importer only needs a subset of operations:
* Reading sectors via HBIOS.
* Parsing the MBR partition table (offset `0x01BE`).
* Reading the Volume Boot Record (BPB) to locate FAT and Root Directory.
* Following cluster chains.
* Filtering directory entries for short 8.3 text files (`.TXT`, `.ASM`, `.C`, `.SUB`, `.PRN`).
* Feeding lines to `SE.COM` via `CALL_COMMIT_LINE` (`IX + 21`).

### 2.3 Binary Size Breakdown Estimate (Target: $\le 3,200\text{ bytes}$)

| Module | Purpose | Estimated Size |
| :--- | :--- | :---: |
| **`fat_entry.asm`** | 3-entry jump table ABI, magic verification, dispatch | 60 B |
| **`fat_hbios.asm`** | HBIOS `RST 08H` wrappers (`BF_DIOREAD`, `BF_SYSGET_DIOCNT`) | 120 B |
| **`fat_mbr.asm`** | MBR partition table scanner & LBA offset calculation | 150 B |
| **`fat_bpb.asm`** | BPB geometry parser (SectorsPerCluster, FAT LBA, Root LBA) | 220 B |
| **`fat_chain.asm`** | Cluster-to-LBA math (32-bit) & FAT16/FAT32 chain traversal | 380 B |
| **`fat_dir.asm`** | Directory sector parser, 8.3 filename filter, size extraction | 450 B |
| **`fat_stream.asm`** | Sector stream to CRLF/LF line tokenizer & Host API commit | 350 B |
| **`fat_ui.asm`** | VT100 interactive modal file selector with scroll cursor | 650 B |
| **`fat_about.asm`** | Modal About dialog (Action 1) & Config dialog (Action 2) | 320 B |
| **Data & Tables** | Prompts, error strings, box borders, variable storage | 400 B |
| **Total Estimated Code Image** | **Fully within the 4,096-byte CP/M 3 slot** | **$\approx 3,100\text{ B}$** |

---

## 3. Architecture & Data Flow

```
+-------------------------------------------------------------------------+
|                              SE.COM Host                                |
|  - Upper Common RAM: PLUGIN_HOST_API (IX)                               |
|  - Host Trampolines: COMMIT_LINE (IX+21), PRINT_STR (IX+27), PUTC (IX+24)|
+-------------------------------------------------------------------------+
                                    ^
                                    | Host API Vectors (IX)
                                    v
+-------------------------------------------------------------------------+
|                         FATFS.PRL (4KB Slot)                            |
|                                                                         |
|  [Action 0: Run] ---> Modal Directory Browser (VT100 UI)                |
|                             | (User selects file)                       |
|                             v                                           |
|                      FAT Cluster Traversal                              |
|                             |                                           |
|                             v                                           |
|                    HBIOS Sector Read ($13)                              |
|                             |                                           |
|                             v                                           |
|                  Line Tokenizer (\r\n / \n)                             |
|                             |                                           |
|                             +---> COMMIT_LINE (IX+21) ---> Far RAM Doc  |
+-------------------------------------------------------------------------+
                                    |
                                    | RST 08H (B = 13h: BF_DIOREAD)
                                    v
+-------------------------------------------------------------------------+
|                         RomWBW HBIOS Subsystem                          |
|  - Disk Unit 0: Primary CF/IDE (CP/M Slices)                            |
|  - Disk Unit 1: Secondary SD Card (FAT Partition)                       |
+-------------------------------------------------------------------------+
```

---

## 4. Detailed Component Design

### 4.1 Memory Allocation & Buffer Management
Inside the 4,096-byte slot:
* **Code & Constants**: `0x0100 .. 0x0CFF` ($\sim 3,072$ bytes).
* **Static BSS & State**: `0x0D00 .. 0x0DFF` (256 bytes).
  * `HBIOS_DISK_UNIT`: Byte (default: `1`).
  * `PART_START_LBA`: 32-bit (4 bytes).
  * `FAT_START_LBA`: 32-bit (4 bytes).
  * `DATA_START_LBA`: 32-bit (4 bytes).
  * `ROOT_DIR_LBA`: 32-bit (4 bytes).
  * `ROOT_DIR_ENTRIES`: 16-bit word (FAT16) or 0 (FAT32).
  * `SECTORS_PER_CLUS`: Byte (1, 2, 4, 8, 16, 32, 64).
  * `FAT_TYPE`: Byte (`16` for FAT16, `32` for FAT32).
  * `CUR_CLUSTER`: 32-bit (4 bytes).
* **Sector Scratch Buffer**: `0x0E00 .. 0x0FFF` (512 bytes).
  * Reusable buffer for MBR, BPB, FAT table sectors, and active data sectors.

### 4.2 RomWBW HBIOS Block I/O Interface
To read a sector:
```z80
; Input:
;   DE:HL = 32-bit LBA sector index (DE = High Word, HL = Low Word)
;   A     = Target Disk Unit (e.g. 1)
;   BC    = Buffer Address (e.g. SECTOR_BUFFER at 0x0E00)
HBIOS_READ_SECTOR:
    PUSH    AF
    LD      A,(CPM_USER_BANK)   ; Destination RAM bank
    LD      E,A                 ; E = Destination Bank
    POP     AF                  ; A = Disk Unit
    LD      B,13H               ; BF_DIOREAD (13h)
    LD      C,1                 ; Sector count = 1
    RST     08H                 ; Call HBIOS
    OR      A                   ; A = 0 on success
    RET
```

### 4.3 32-Bit Math Primitives
Because the Z80 lacks 32-bit registers, the driver implements a compact set of 32-bit macros:
* `ADD32 (DE:HL, BC:IX)`
* `MUL32_8 (DE:HL * A)` (for cluster to sector conversion: $\text{Cluster} \times \text{SecPerClus}$)
* `DIV32_512 (DE:HL >> 9)` (to determine FAT sector index from cluster number)

### 4.4 Filesystem Detection Logic
1. **Read Sector 0**:
   * Inspect bytes `0x01FE..0x01FF` for boot signature `0x55, 0xAA`.
   * Check partition 1 type at `0x01C2`:
     * `0x01`: FAT12
     * `0x04`, `0x06`, `0x0E`: FAT16
     * `0x0B`, `0x0C`: FAT32
     * If partition type is 0 or non-FAT, check if sector 0 itself is a superfloppy VBR (`BPB_BytsPerSec == 512`).
2. **Compute Base LBAs**:
   * $\text{FAT\_LBA} = \text{PartLBA} + \text{BPB\_RsvdSecCnt}$
   * For FAT16:
     * $\text{RootDirSectors} = (\text{BPB\_RootEntCnt} \times 32 + 511) / 512$
     * $\text{DataStartLBA} = \text{FAT\_LBA} + (\text{BPB\_NumFATs} \times \text{BPB\_FATSz16}) + \text{RootDirSectors}$
   * For FAT32:
     * $\text{DataStartLBA} = \text{FAT\_LBA} + (\text{BPB\_NumFATs} \times \text{BPB\_FATSz32})$
     * $\text{RootDirLBA} = \text{DataStartLBA} + (\text{BPB\_RootClus} - 2) \times \text{SecPerClus}$

### 4.5 Stream-to-Line Ingestion (`fat_stream.asm`)
When reading the file data clusters:
1. Load 512-byte sector into `SECTOR_BUFFER`.
2. Iterate byte by byte:
   * Ignore `\r` (0x0D).
   * Accumulate characters into a local line buffer (up to 1,000 characters).
   * Upon encountering `\n` (0x0A) or EOF:
     * Null-terminate line.
     * Call `CALL_COMMIT_LINE` (`IX + 21`) with line index `HL`, buffer pointer `DE`, length `BC`.
     * Increment `HL`.
3. When cluster finishes, query FAT table for `NEXT_CLUSTER`. Repeat until cluster $\ge \text{0x0FFFFFF8}$ (EOF).
4. Update `PTR_TOTAL_LINES` (`IX + 10`) with `HL`.
5. Return `A = 2` (`CAP_DOC_MUTATE`), causing `SE.COM` to refresh the display with the new file!

---

## 5. User Interface & Workflow

### 5.1 Interactive Directory Browser UI
When the plugin is launched (`Ctrl+Z` in editor or `p` on splash screen):
```text
  +-------------------------------------------------------------+
  |              FAT SD-Card File Importer (FAT16/FAT32)        |
  +-------------------------------------------------------------+
  | Disk Unit: [1]  Partition: [1]  Type: [FAT32]               |
  | Directory: /                                                |
  +-------------------------------------------------------------+
  | > [1] SE.ASM            438,670 bytes   2026-09-23 15:40    |
  |   [2] README.TXT         11,801 bytes   2026-09-22 10:14    |
  |   [3] KERNEL.C           24,192 bytes   2026-08-14 18:22    |
  |   [4] BUILD.SUB             512 bytes   2026-09-01 09:00    |
  +-------------------------------------------------------------+
  | [Up/Down] Navigate  [Enter] Import to Editor  [ESC] Exit     |
  +-------------------------------------------------------------+
```

### 5.2 Embedded About & Config Screens
* **Action 1 (About Screen)**: Shows version, author, and HBIOS block device status.
* **Action 2 (Config Screen)**: Allows toggling default RomWBW Disk Unit (`0`..`7`), partition index (`0`..`3`), and newline convention (`LF` vs `CRLF`).

---

## 6. Phased Implementation Roadmap

* [ ] **Phase 1: Driver Primitives (`fat_hbios.asm` & `fat_math.asm`)**
  * HBIOS `RST 08H` read wrapper.
  * 32-bit math helpers (add, multiply by sectors/cluster, divide by 512).
* [ ] **Phase 2: Partition & BPB Identification (`fat_mbr.asm` & `fat_bpb.asm`)**
  * MBR parsing and FAT16/FAT32 geometry calculations.
  * Unit test on simulated RomWBW SD card image.
* [ ] **Phase 3: Directory Walker & Cluster Engine (`fat_dir.asm` & `fat_chain.asm`)**
  * Traverse FAT table cluster chain.
  * Read root directory entries and parse 8.3 names and file lengths.
* [ ] **Phase 4: Text Ingestion & Host API Integration (`fat_stream.asm`)**
  * Tokenize CRLF/LF into lines and commit to `SE.COM` Far RAM buffer via `CALL_COMMIT_LINE`.
* [ ] **Phase 5: Modal UI & Packaging (`fat_ui.asm` & `tools/mkprl.py`)**
  * VT100 interactive selector.
  * Package into `FATFS.PRL` with `CAP_TPA_EXEC | CAP_FAR_EXEC | CAP_DOC_MUTATE | CAP_MODAL_UI | CAP_HAS_ABOUT | CAP_HAS_CONFIG`.
  * Verify size $\le 4,096$ bytes.
