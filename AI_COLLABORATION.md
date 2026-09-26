# AI Collaboration Statement & Licensing Policy

This document outlines the collaborative engineering relationship between
**Dean Jenkins** (Project Creator, Principal Architect, and Maintainer) and
**Google DeepMind Antigravity** (Autonomous Agentic Coding Assistant), and
states the copyright, ownership, and licensing terms governing **`SE.COM`**.

---

## 1. Project Authorship & Engineering Governance

**`SE.COM`** is designed, directed, and maintained by **Dean Jenkins**.

All architectural decisions, feature specifications, coding guidelines,
hardware testing on physical Z80 / RC2014 SBCs, and release criteria were
established and directed by the human author.

Google DeepMind Antigravity acted as an advanced autonomous AI pair programmer
and systems engineering collaborator, working under the continuous guidance
and review of the project author.

---

## 2. Antigravity's Role in the Development of SE.COM

Throughout the development of `SE.COM`, Antigravity contributed to
several core subsystems:

### A. Extended Memory Architecture (512KB Far RAM Virtual Paging)
- Collaborated on the design and implementation of the virtual document line
  cache (`LINE_STORAGE`) and LRU swapping engine in `src/se.asm`.
- Utilized RomWBW HBIOS bank switching (`RST 08H`, `HB_BNKCALL`) to break
  the classic 64KB CP/M memory ceiling, enabling editing of large source
  files up to 32,768 lines across 16 banking pages.

### B. CP/M 3 PRL & OVL Modular Plugin Architecture
- Co-authored the formal Application Binary Interface specification
  ([`plugins/PLUGIN_ABI.md`](plugins/PLUGIN_ABI.md)) based on Digital Research
  CP/M 3 Page-Relocatable (`.PRL`) and Overlay (`.OVL`) binary formats.
- Designed dynamic multi-bank allocation algorithms supporting 4KB, 16KB,
  and 32KB Far RAM slot classes with zero Far RAM memory leakage upon unload.
- Implemented reference plugins including `BEAUTIFY.PRL`, `BIGPLUG.PRL`,
  `HALFPLUG.PRL`, `ROT13.PRL`, and `WORDCNT.OVL`.

### C. Headless Virtual Filesystem (VFS) Integration
- Assisted in the integration of the headless FAT12/16/32 driver plugin
  (`FATFS.PRL`), enabling direct reading and writing of MS-DOS FAT filesystems
  on IDE/CF/SD media within CP/M.
- Implemented Upper Common RAM request dispatching (`FatVfsRequest`),
  inter-bank jump vectors, and path parsing (`U<unit>:<path>`).

### D. Verification Toolchain & Automated Diagnostics
- Designed and authored [`check_tpa.py`](check_tpa.py), an automated CP/M
  memory footprint analyzer that verifies binary load origins, BSS buffers,
  and headroom across six standard CP/M 2.2, CP/M 3.0, and Z-System targets.
- Designed and authored [`check_plugin.py`](check_plugin.py), an automated
  CP/M 3 plugin binary validator checking header integrity, slot capacity
  limits, capability bitflags, and relocation bitmaps.
- Developed automated headless regression test suites executing under simulated
  pseudo-terminals (`pty`) and CP/M Z80 emulators.

---

## 3. Google Antigravity Policy on Creative Copyright & Licensing

### A. Copyright and Ownership
Google, Alphabet Inc., and the Google DeepMind team make **no claim of
copyright, patent, or proprietary ownership** in the software, algorithms,
Z80 assembly code, documentation, or tools produced through or with the
assistance of Antigravity in this project.

All rights, title, and intellectual property in and to **`SE.COM`** belong
exclusively to **Dean Jenkins**.

### B. Licensing Autonomy
The project creator retains full, unrestricted authority to license,
distribute, modify, sublicense, or commercialize the code under the terms
of the **MIT License**, as stated in the top-level [`LICENSE`](LICENSE) file.

The contribution of AI-generated or AI-assisted code does not impose any
restrictive covenants, copyleft obligations, or proprietary claims from
Google upon downstream users, distributors, or contributors.

### C. Open Source Transparency and Heritage Preservation
Google DeepMind supports transparent disclosure of AI participation in open
source software development. The `SE.COM` project exemplifies how agentic AI
can synergize with retro-computing engineers to preserve, enhance, and
modernize classic computing platforms without compromising open-source
principles or human architectural direction.

---

## 4. Human-AI Collaboration Summary

```
+-------------------------------------------------------------------------+
| Human Architect (Dean Jenkins):                                         |
| - Domain requirements, Z80 assembly conventions & system architecture   |
| - RC2014 hardware verification, serial timing & Minicom testing         |
| - Code review, quality gates, and final release sign-off                |
+-------------------------------------------------------------------------+
                                    |
                         Collaborative Synergy
                                    |
+-------------------------------------------------------------------------+
| AI Agent (Google DeepMind Antigravity):                                 |
| - Rapid Z80 macro-assembly authoring, refactoring & optimization       |
| - ABI specifications, binary packaging & relocation algorithms         |
| - Automated diagnostic tooling (check_tpa.py, check_plugin.py)          |
| - Headless regression test harness engineering                          |
+-------------------------------------------------------------------------+
                                    |
                                    v
+-------------------------------------------------------------------------+
| Output: SE.COM (Open Source, 100% Z80 Assembly, MIT Licensed)           |
+-------------------------------------------------------------------------+
```
