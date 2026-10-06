# FAT Filesystem Browser & Transfer Plugin (`FATFS.PRL`)

The **FAT Filesystem Plugin (`FATFS.PRL`)** provides native FAT12, FAT16, and FAT32 filesystem access for the **`SE.COM`** full-screen text editor on **RomWBW CP/M 2.2 / CP/M 3.0** systems (including the SC131, RC2014, and compatible Z80 single-board computers).

It solves the classic CP/M data exchange bottleneck: rather than relying on slow serial XMODEM transfers or external tools like `cpmtools`, users can directly browse SD cards and CompactFlash media, view directory contents and file sizes, stream text files straight into the `SE.COM` active editor buffer, and export editor buffers back out to FAT storage.

---

## Visual Interface & Expected Screenshots

The plugin provides a self-contained VT100 modal user interface operating at 50 to 60 columns. In accordance with the RomWBW console convention, all modal dialog lines are prefixed with the margin tilde (`~ +` / `~ |`) standard to prevent column 0 blanking or line-wrap artifacts on hardware serial terminals.

### 1. Interactive Directory Browser (Main Screen)

Invoked via `SE.COM`'s plugin launcher (Action 0). Displays the active RomWBW disk unit, volume file count, file entries with byte sizes or `[DIR]` flags, an inverse-video cursor selection bar, and the hotkey control footer.

```text
          ~ +--------------------------------------------------------+
          ~ |             FAT Filesystem Manager v0.1.0              |
          ~ | Drive: RomWBW Unit 1 | Files: 6                        |
          ~ +--------------------------------------------------------+
          ~ |       README.TXT    1420 B                             |
          ~ |       CONFIG.SYS    256 B                              |
          ~ | [DIR] TURBOPAS                                         |
          ~ | ===== HELLO.C       512 B                        ===== | <- [Cursor Highlight]
          ~ |       NOTES.DOC     4096 B                             |
          ~ |       PROJECT.ASM   18432 B                            |
          ~ |                                                        |
          ~ |                                                        |
          ~ |                                                        |
          ~ |                                                        |
          ~ +--------------------------------------------------------+
          ~ | [ENTER/O] Open  [S] Save Buffer  [U] Unit  [Q/ESC] Quit |
          ~ +--------------------------------------------------------+
```

*(Note: On VT100 terminals, the active selection line is rendered in full reverse video via `\x1b[7m` ... `\x1b[0m`)*.

---

### 2. File Import Confirmation Dialog

Pressing `ENTER` or `O` on a highlighted file prompts for confirmation before streaming the file content into `SE.COM`'s document buffer.

```text
          ~ +--------------------------------------------------------+
          ~ |             FAT Filesystem Manager v0.1.0              |
          ~ | Drive: RomWBW Unit 1 | Files: 6                        |
          ~ +--------------------------------------------------------+
          ~ | ===== README.TXT    1420 B                       ===== |
          ~ |       CONFIG.SYS    256 B                              |
          ~ | [DIR] TURBOPAS                                         |
          ~ |       HELLO.C       512 B                              |
          ~ |       NOTES.DOC     4096 B                             |
          ~ |       PROJECT.ASM   18432 B                            |
          ~ |                                                        |
          ~ |                                                        |
          ~ |                                                        |
          ~ |                                                        |
          ~ +--------------------------------------------------------+
          ~ | [ENTER/O] Open  [S] Save Buffer  [U] Unit  [Q/ESC] Quit |
          ~ +--------------------------------------------------------+
          ~ | Load 'README.TXT' into editor? [Y/N]: Y
```

Upon pressing `Y` or `ENTER`:
1. The file is opened via FatFs `f_open()`.
2. 512-byte sectors are read and line-buffered.
3. Each line is transferred into `SE.COM` via host callback `host_commit_line()`.
4. The plugin exits with return code `A = 0x02` (`PLUG_RET_DOC_MOD`), signaling `SE.COM` that the document buffer has been replaced. The editor refreshes its screen immediately.

---

### 3. File Export Dialog

Pressing `S` opens an inline prompt to write the current `SE.COM` editor buffer out to a FAT file.

```text
          ~ +--------------------------------------------------------+
          ~ |             FAT Filesystem Manager v0.1.0              |
          ~ | Drive: RomWBW Unit 1 | Files: 6                        |
          ~ +--------------------------------------------------------+
          ~ |       README.TXT    1420 B                             |
          ~ |       CONFIG.SYS    256 B                              |
          ~ | [DIR] TURBOPAS                                         |
          ~ |       HELLO.C       512 B                              |
          ~ |       NOTES.DOC     4096 B                             |
          ~ |       PROJECT.ASM   18432 B                            |
          ~ |                                                        |
          ~ |                                                        |
          ~ |                                                        |
          ~ |                                                        |
          ~ +--------------------------------------------------------+
          ~ | [ENTER/O] Open  [S] Save Buffer  [U] Unit  [Q/ESC] Quit |
          ~ +--------------------------------------------------------+
          ~ | Save as FAT file [EXPORT.TXT]: MYCODE.C_
```

* Backspace (`0x08` / `0x7F`) editing is fully supported.
* Pressing `ENTER` on an empty line defaults to `EXPORT.TXT`.
* Document lines are fetched sequentially via `host_checkout_line()` and written with standard `CRLF` (`\r\n`) line endings.
* Once complete, the directory listing refreshes immediately to display the newly saved file.

---

### 4. About Dialog (Action 1)

Invoked from the `SE.COM` Plugin Manager (`About` action) or directly via entry point offset `+03H`.

```text
                ~ +------------------------------------------------+
                ~ |          FAT Filesystem Plugin v0.1.0          |
                ~ |        Compatible with SE.COM >= v0.9.7        |
                ~ +------------------------------------------------+
                ~ | Features:                                      |
                ~ |  - FAT12 / FAT16 / FAT32 Filesystem Support    |
                ~ |  - Direct SD Card & CF Access via RomWBW HBIOS |
                ~ |  - MBR Partition Auto-Detection                |
                ~ |  - Seamless Editor Text Import and Export      |
                ~ |                                                |
                ~ | Engine: Elm-Chan FatFs R0.15 (1-Clause BSD)    |
                ~ | Driver: RomWBW RST 08H by Dean Jenkins         |
                ~ +------------------------------------------------+
                ~ |           Press any key to continue            |
                ~ +------------------------------------------------+
```

---

### 5. HBIOS Disk Unit Configuration Dialog (Action 2)

Invoked from the `SE.COM` Plugin Manager (`Config` action) or dynamically by pressing `U` in the file browser.

```text
                ~ +------------------------------------------------+
                ~ |           FAT Plugin Configuration             |
                ~ +------------------------------------------------+
                ~ | Current HBIOS Disk Unit: [ Unit 1 ]            |
                ~ |                                                |
                ~ |  [0] Unit 0 (Primary CF/IDE)  [1] Unit 1 (SD)  |
                ~ |  [2] Unit 2 (Secondary IDE)   [3] Unit 3 (Ext) |
                ~ |  [4] Unit 4 (RC2014 SD0)      [5..7] Extended  |
                ~ |                                                |
                ~ | Select (0-7) to change, or [ESC]/[Q] to exit:  |
                ~ +------------------------------------------------+
```

Pressing keys `0` through `7` switches the target hardware disk unit on the fly. The plugin unmounts the previous volume and re-mounts the newly selected unit.

---

### 6. Mount Error & Recovery Dialog

If the configured HBIOS disk unit lacks a valid FAT volume (e.g. unformatted, raw CP/M slice, or absent media), the plugin catches the error gracefully instead of crashing or hanging:

```text
              ~ +----------------------------------------------------+
              ~ |             FAT Filesystem Mount Error             |
              ~ +----------------------------------------------------+
              ~ | Could not mount FAT volume on RomWBW Unit 0!       |
              ~ | FatFs Error Code: 3                                |
              ~ |                                                    |
              ~ |  [C] Configure HBIOS Disk Unit                     |
              ~ |  [Q] Exit to Editor                                |
              ~ +----------------------------------------------------+
```

Pressing `C` immediately opens the Configuration Dialog so the user can select the correct drive unit (e.g., switching from Unit 0 to Unit 1 on SC131 or Unit 4 on RC2014) and retry mounting.

---

## Keyboard Controls & Navigation Reference

| Key / Sequence | Action | Description |
| :--- | :--- | :--- |
| **`Up`** / **`k`** | Cursor Up | Move selection bar up by one file. Scrolls view if at top. |
| **`Down`** / **`j`** | Cursor Down | Move selection bar down by one file. Scrolls view if at bottom. |
| **`PgUp`** | Page Up | Scroll directory list upward by 10 entries. |
| **`PgDn`** | Page Down | Scroll directory list downward by 10 entries. |
| **`ENTER`** / **`O`** | Open File | Open selected file and prompt to import into active editor buffer. |
| **`S`** | Save Buffer | Export current editor lines to a FAT file. |
| **`U`** | Select Unit | Switch active RomWBW HBIOS disk unit (0–7). |
| **`Q`** / **`ESC`** | Exit | Return to `SE.COM` editor. |

---

## Technical Architecture

```text
 +-------------------------------------------------------------------------+
 |                              SE.COM Host                                |
 |  - Document Line Storage & Virtual Screen Buffer                        |
 |  - Banked Far RAM Plugin Loader (Allocates 32KB Far RAM Slot)           |
 +--------------------+-------------------------------+--------------------+
                      | Callbacks                     | Far Bank Call
                      v                               v
 +-------------------------------------------------------------------------+
 |                           FATFS.PRL Plugin                              |
 |                                                                         |
 |  [fat_entry.asm / Jump Table + Host API Trampolines]                    |
 |   +00H: JP fat_plugin_run      (Action 0: Browser)                      |
 |   +03H: JP fat_plugin_about    (Action 1: About Dialog)                 |
 |   +06H: JP fat_plugin_config   (Action 2: Config Dialog)                |
 |                                                                         |
 |  [fat_plugin.c]                                                         |
 |   - VT100 Windowing & Tilde-Margin Box Renderer                         |
 |   - File Navigation & User Interaction                                  |
 |   - Line-by-Line Document Import & Export Streams                       |
 |                                                                         |
 |  [Elm-Chan FatFs R0.15 Core (ff.c)]                                     |
 |   - FAT12 / FAT16 / FAT32 Driver & MBR Partition Table Parser           |
 |   - Tiny Buffer Architecture (Single Sector Memory Footprint)           |
 |                                                                         |
 |  [source/diskio.c (RomWBW HBIOS Block Driver)]                          |
 |   - Dynamic HBIOS Unit Addressing (Units 0..7)                          |
 |   - Direct 32-bit LBA Sector Translation                                |
 +------------------------------------+------------------------------------+
                                      | RST 08H Fast BIOS Calls
                                      v
 +-------------------------------------------------------------------------+
 |                          RomWBW HBIOS Firmware                          |
 |  - BF_SYSGETBNK (0xF3): Query Target Execution Memory Bank              |
 |  - BF_DIOSTATUS (0x10): Check Media Presence & Device Ready Status      |
 |  - BF_DIOSEEK   (0x12): 32-bit LBA Sector Seek (Bit 7 of D set for LBA) |
 |  - BF_DIOREAD   (0x13): Physical 512-Byte Sector Direct Memory Read     |
 |  - BF_DIOWRITE  (0x14): Physical 512-Byte Sector Direct Memory Write    |
 +--------------------+----------------------------------------------------+
                      | Hardware Bus (IDE / SPI / CF)
                      v
         [ Physical SD Card / CompactFlash Storage ]
```

### 1. CP/M 3 PRL Header & Capability Specification

`FATFS.PRL` is packaged as a standard Digital Research CP/M 3 Page-Relocatable (`.PRL`) binary with a 256-byte header followed by the executable code/data and a bitmask relocation table.

The header encodes the plugin's metadata and required capabilities word at offset `0x1C`:

```
Capabilities Word: 0x00BE
  - CAP_FAR_EXEC   (0x0002): Requires Far Banked RAM execution
  - CAP_DOC_MUTATE (0x0004): Modifies/replaces editor document lines
  - CAP_MODAL_UI   (0x0008): Uses full-screen modal interactive VT100 UI
  - CAP_HAS_ABOUT  (0x0010): Provides Action 1 About dialog (+03H)
  - CAP_HAS_CONFIG (0x0020): Provides Action 2 Configuration dialog (+06H)
  - CAP_SIZE_32K   (0x0080): Requires 32KB banked plugin memory slot
```

### 2. Memory Footprint

* **Code + Initialized Data**: ~28,339 bytes
* **Relocation Bitmap**: ~3,543 bytes (2,537 page relocations)
* **Total File Size**: 32,138 bytes (`FATFS.PRL`)
* Fits entirely within `SE.COM`'s 32KB banked plugin slot (`0x8000`–`0xFFFF` or dedicated bank), leaving CP/M's transient program area (TPA) completely unencumbered.

### 3. RomWBW Storage Device Mapping

RomWBW assigns hardware storage devices to logical disk units during firmware boot:

| Hardware Platform | Typical Device | HBIOS Unit Number | Configuration Notes |
| :--- | :--- | :---: | :--- |
| **SC131** | MicroSD Slot | **Unit 1** | Primary SD storage on single-drive systems |
| **SC131** | CF / IDE Board | **Unit 0** | When optional IDE/CF expansion board is fitted |
| **RC2014** | Primary CF | **Unit 0** | Standard CF module (e.g. 128MB–2GB) |
| **RC2014** | SD Module (SD0) | **Unit 4** | Secondary or primary SD interface |
| **Generic RomWBW** | Extended Units | **Units 2, 3, 5..7** | Secondary IDE, SD1, or USB/PPIDE interfaces |

*The default unit in `FATFS.PRL` is Unit 1 (optimal for standalone SC131). The unit can be changed at any time via Action 2 or pressing `U`.*

---

## File Inventory

| Path | Description |
| :--- | :--- |
| [`fat_plugin.c`](fat_plugin.c) | Interactive VT100 browser, modal dialogs, and text import/export routines. |
| [`fat_plugin.h`](fat_plugin.h) | Data structures, constants, and host interface function prototypes. |
| [`fat_entry.asm`](fat_entry.asm) | Standard 3-entry jump table and trampolines for `org 0x0100`. |
| [`fat_entry_200.asm`](fat_entry_200.asm) | Dual-pass entry point for `org 0x0200` relocation generation. |
| [`source/diskio.c`](source/diskio.c) | Clean-room RomWBW `RST 08H` HBIOS sector driver. |
| [`source/diskio.h`](source/diskio.h) | Elm-Chan FatFs disk I/O interface definitions. |
| [`source/ff.c`](source/ff.c) | Upstream Elm-Chan FatFs R0.15 filesystem implementation. |
| [`source/ff.h`](source/ff.h) | FatFs core definitions and API declarations. |
| [`source/ffconf.h`](source/ffconf.h) | Customized configuration (`FF_FS_TINY`, SFN 8.3, MBR auto-detect). |
| [`mkfatprl.py`](mkfatprl.py) | Standalone packager computing page relocations and generating CP/M 3 PRL headers. |
| [`Makefile`](Makefile) | Automated dual-origin compilation and packaging targets. |
| [`FATFS.PRL`](FATFS.PRL) | Assembled and linked 32KB page-relocatable plugin binary. |

---

## Building and Verification

### Prerequisites

* **`z88dk`** (with `sccz80` compiler and Z80 assembler tools).
* **Python 3** (for `mkfatprl.py` and the test suite).

### Build Commands

To build the plugin from source:
```bash
make -C plugins/fat clean
make -C plugins/fat all
```

The build pipeline performs the following steps:
1. Compiles `fat_100.bin` linked at origin `0x0100` using `sccz80`.
2. Compiles `fat_200.bin` linked at origin `0x0200` using `sccz80`.
3. Runs `mkfatprl.py` to compare images, construct the relocation bitmap, prepend the 256-byte CP/M 3 header with capability flags `0x00BE`, and output `FATFS.PRL`.

### Running Automated Tests

A dedicated test suite validates the binary integrity, PRL header fields, 32KB capability flag, relocation bitmap, and jump table alignment:

```bash
python3 tests/test_fatfs_plugin.py
```

Expected output:
```text
....
----------------------------------------------------------------------
Ran 4 tests in 0.003s

OK
```

---

## Integration Status with `SE.COM`

* **Plugin Status**: Complete, fully packaged (`FATFS.PRL`), and verified.
* **Host Compatibility**:
  * Standard 4KB TPA overlay plugins (`CAP_SIZE_4K` / default) run in `SE.COM` versions $\ge$ `v0.9.5`.
  * `FATFS.PRL` requires **32KB Far RAM execution** (`CAP_SIZE_32K = 0x0080`), currently being finalized in the `SE.COM` host core (`src/se.asm`).
  * Once the host loader completes banking support for 32KB plugins, copy `FATFS.PRL` to your CP/M boot disk (`A:`) and launch it directly from `SE.COM`'s Plugin Manager.
