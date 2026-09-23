# SE.COM Modular Plugins

This directory contains modular plugins and build scripts for the **`SE.COM`** CP/M full-screen text editor.

Plugins conform to Digital Research CP/M 3 (CP/M Plus) **Page-Relocatable (`.PRL`)** and **Overlay (`.OVL`)** specifications.

---

## Technical Documentation

* **[PLUGIN_ABI.md](PLUGIN_ABI.md)**: The authoritative technical specification for the SE.COM Plugin Architecture & Application Binary Interface (ABI), including:
  * Dual execution models (Far RAM via RomWBW `HB_BNKCALL` vs 4KB TPA cache overlay)
  * 256-byte PRL/OVL file header and capability bitflags
  * 3-entry jump table calling convention (`+0` Execute, `+3` About, `+6` Config)
  * Host API vector table (`PLUGIN_HOST_API`)
  * Minimal plugin assembly template and build guide

---

## Included Plugins

| Plugin | File | Format | Execution Mode | Capabilities | Description |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **`BEAUTIFY`** | `BEAUTIFY.PRL` | `.PRL` (3.5KB) | Far RAM / TPA Slot | `0x0037` | Z80 assembly source code formatter with embedded About & Config screens. |
| **`WORDCNT`** | `WORDCNT.OVL` | `.OVL` (1.0KB) | Far RAM | `0x003B` | Document statistics analyzer (words, lines, characters) with embedded About & Config screens. |
| **`ROT13`** | `ROT13.PRL` | `.PRL` (0.4KB) | TPA Slot (Relocated) | `0x0015` | Reversible ROT13 text cipher transform with embedded About screen. |

---

## Building Plugins

Plugins are compiled and packaged automatically via:
```bash
python3 plugins/build_plugins.py
```
Or as part of the overall build:
```bash
make plugins
```
