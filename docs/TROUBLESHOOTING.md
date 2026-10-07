# SE.COM Troubleshooting & Operational Guide

This guide provides troubleshooting procedures, diagnostic steps, and solutions
for common operational issues encountered when running **`SE.COM`** on RomWBW
and CP/M systems.

---

## 1. Document Capacity & Line Limit Troubleshooting

### 1.1 Why Does SE.COM Show "Max Lines: [256 lines (RAM)]"?

#### Symptom
On the startup splash screen, the **Max Lines** field displays:
```text
~        Max Lines     : [256 lines (RAM)]
```
Attempting to load large documents (> 256 lines) fails with an out-of-memory
error or limits editing to the first 256 lines.

#### Cause
`SE.COM` switches to conventional 64KB RAM mode whenever fewer than two Far
RAM banks are available (`EXT_BANK_COUNT < 2`). This typically occurs when:
1. **RAM Drive Protection (`Preserve` Mode)**: By default, `SE.COM` runs in
   `Preserve` mode to protect the RomWBW in-memory RAM disk (`Drive A:`).
   If RomWBW has assigned all upper RAM banks to the RAM disk and reports no
   free application banks (`BF_SYSGET_APPBNKS`), `SE.COM` respects this
   boundary and allocates zero Far RAM banks.
2. **Missing Banked Memory Hardware**: The system is running standard unbanked
   CP/M without RomWBW HBIOS banked Far RAM (512KB RAM/ROM module).
3. **Firmware Earlier than RomWBW v3.6.0**: Pre-v3.6.0 releases lack the
   standardized `RST 08H` Far RAM memory query vectors.

#### Solution
If running on RomWBW hardware with 512KB RAM:

1. **Switch RAM Drive Mode to Hibernate or Overwrite**:
   - From the splash screen, press **`c`** or **`C`** to enter the
     **Configuration** screen.
   - Press **`2`** to cycle the **RAM Drive** setting:
     - **`Hibernate` (Recommended)**: Backs up RAM disk structures to a swap
       file (`RAMDRV.IMG`) on persistent storage while editing, freeing all
       upper banks for large files, and restores `Drive A:` upon exit.
     - **`Overwrite`**: Sacrifices RAM disk `A:` data to gain immediate access
       to all upper Far RAM banks (~384KB to 512KB).
   - Press **`s`** or **`S`** to save the configuration permanently to
     `SE.CFG`.
   - Return to the splash screen. The **Max Lines** field will now display
     `[16,384 lines]` or `[32,768 lines]`.

2. **Verify Memory Allocation on the Memory Info Screen**:
   - On the splash screen, press **`m`** or **`M`** to open the **Memory Map &
     Bank Allocation Screen**.
   - Verify that RomWBW HBIOS Far RAM banks are detected and that document
     buffer banks are active.

---

### 1.2 How to Maximise the Number of Editor Lines (Up to 32,768 Lines)

`SE.COM` supports editing massive documents (up to 32,768 lines, ~8.3 MB virtual
capacity) using dual Far RAM line pointer tables and virtual slot paging.

To configure `SE.COM` for maximum document capacity:

1. **Enable 32,768 Lines Mode**:
   - On the splash screen, press **`c`** to open Configuration.
   - Press **`3`** to toggle **Max Document Lines** from `16,384 lines` to
     `32,768 lines`.
   - Press **`s`** to save to `SE.CFG`.

2. **Ensure Sufficient Far RAM Banks Are Available**:
   - `32,768 lines` mode requires at least **three** free Far RAM banks:
     - **Bank 1**: Line Table Bank 0 (descriptors for lines 0..16,383).
     - **Bank 2**: Line Table Bank 1 (descriptors for lines 16,384..32,767).
     - **Bank 3+**: Document text slot page storage.
   - If fewer than 3 banks are free, `SE.COM` automatically falls back to
     `16,384 lines` mode.
   - Set RAM Drive to `Hibernate` or `Overwrite` to provide up to 14 Far RAM
     banks.

3. **Unload Resident Far RAM Plugins**:
   - High-capacity plugins (such as `FATFS.PRL` or `BIGPLUG.PRL`) occupy
     dedicated 16KB/32KB Far RAM banks.
   - From splash, press **`p`** to enter the **Plugin Manager**.
   - Select unused resident plugins and press **`u`** to unload them, returning
     their Far RAM banks to the document paging engine.

4. **Verify Allocation on the Memory Map Screen**:
   - Press **`m`** on the splash screen to view the **Memory Map**.
   - Confirm that:
     - `Line Table (0..16K)` is assigned to a physical bank.
     - `Line Table (16K..32K)` is assigned to a second physical bank.
     - Multiple banks are marked for `Document Paging`.

---

## 2. Display, Geometry & Terminal Troubleshooting

### 2.1 Garbled Screens, Misaligned Pop-ups, or Text Wrapped at Column 80

#### Symptom
Modal pop-up boxes appear split across rows, column framing is skewed, or
text wraps prematurely onto subsequent lines.

#### Cause
Terminal geometry mismatch. `SE.COM` defaults to **120 columns $\times$ 40
rows** (`Modern Default`). If your terminal emulator window is configured for
standard retro **80 $\times$ 24** geometry, 120-column status bars and boxes
will wrap.

#### Solution
Choose one of the following:

- **Switch SE.COM to 80x24 Classic Mode**:
  - On the splash screen, press **`2`** to activate `80x24 (Classic Mode)`.
  - Press **`c`** then **`s`** to persist this setting in `SE.CFG`.
- **Resize Terminal Window**:
  - In Minicom, PuTTY, Windows Terminal, or xterm, resize the window to at
    least 120 columns and 40 rows.
  - On splash screen, press **`1`** to re-assert `120x40 (Widescreen)`.

---

### 2.2 Ghost Characters or Screen Corruption Over Serial (115200 bps)

#### Symptom
During fast scrolling or continuous cursor movement, characters appear dropped,
escape sequences leak as raw characters (`[1;1H`), or screen updates jitter.

#### Cause
At 115200 bps, high-speed ANSI escape sequences overwhelm the serial buffer
unless hardware flow control is active. Full-duplex hardware flow control
operates as RTR/CTS (Ready To Receive / Clear To Send) by utilizing the
physical RTS/CTS pins. Each endpoint asserts its RTS pin as an RTR signal
to indicate that its local receive FIFO/buffer has space; this signal
connects to the CTS pin of the transmitting peer to grant permission to
send.

#### Solution
1. **Enable Hardware Flow Control (RTS/CTS)** in your terminal program:
   - In Minicom: `Ctrl+A` $\rightarrow$ `O` $\rightarrow$ `Serial port setup`
     $\rightarrow$ set `Hardware Flow Control: Yes` and
     `Software Flow Control: No`.
   - In PuTTY: Connection $\rightarrow$ Serial $\rightarrow$ Flow control:
     `RTS/CTS`.
2. **Verify Full-Duplex RTR/CTS Cabling**:
   Ensure null-modem serial cabling cross-connects TX and RX, and
   cross-connects RTS (acting as RTR) to CTS in both directions between
   host and SBC for unthrottled, bidirectional hardware flow control.

---

### 2.3 Backspace Key Types `^H` or `^?` Instead of Deleting

#### Cause
Terminal emulator key mapping mismatch.

#### Solution
- In Minicom: `Ctrl+A` $\rightarrow$ `Z` $\rightarrow$ `Terminal settings`
  $\rightarrow$ toggle `Backspace key` to emit `BS` (`0x08`) or `DEL` (`0x7F`).
- In PuTTY: Terminal $\rightarrow$ Keyboard $\rightarrow$ `The Backspace key`
  $\rightarrow$ select `Control-H` or `Control-? (127)`.
- `SE.COM` natively handles both `0x08` (BS) and `0x7F` (DEL).

---

## 3. Storage, File I/O & Swap Troubleshooting

### 3.1 "Out of Memory" or Disk Full Error During Large File Editing

#### Cause
When a document exceeds physical Far RAM capacity, `SE.COM` activates its
virtual swap engine, creating a temporary paging file (`SE.SWP`) on the
current drive. If the drive runs out of disk space, paging fails.

#### Solution
- Ensure the working drive has at least **512 KB to 1 MB** of free disk space.
- Check free disk space before launching:
  ```text
  C>STAT
  ```
- If disk space is tight, close unused files or switch to a drive with larger
  free space (e.g., hard disk drive `C:` or `D:`).

---

### 3.2 Stale Swap Files After Abnormal Power Cycle

#### Symptom
A leftover file named `SE.SWP` or `RAMDRV.IMG` remains on disk after a system
reset or power interruption.

#### Solution
- `SE.COM` automatically cleans up its swap files during clean exits (`Ctrl+Q`).
- If an unexpected power loss occurred, safely delete stale temporary files:
  ```text
  C>ERA SE.SWP
  ```
- If a hibernated session was interrupted, you can inspect or remove the RAM
  drive backup file:
  ```text
  C>ERA RAMDRV.IMG
  ```

---

## 4. Quick Problem Diagnostic Matrix

| Symptom | Cause | Solution |
| :--- | :--- | :--- |
| **Max lines: 256** | RAM disk preserved | Use `Hibernate` (`[C]` -> `[2]`) |
| **32K fallback** | < 3 banks free | Unload plugins, hibernate RAM disk |
| **Screen wraps** | 120x40 on 80x24 term | Press `[2]` on splash for 80x24 |
| **Dropped chars** | Missing RTR/CTS | Enable RTS/CTS flow control |
| **RAM disk lost** | `Overwrite` active | Switch to `Preserve` or `Hibernate` |
| **Plugin error** | Far RAM slots full | Unload plugins with `[U]` in `[P]` |
| **Paging OOM** | Drive disk full | Free space on drive for `SE.SWP` |
