# SE.COM — Agent Instructions & Project Guidelines

Guidelines for AI assistants (Antigravity, Claude, Grok, etc.) working
within the SE (Screen Editor) codebase.

---

## 1. Commit Message Standards (MANDATORY & ENFORCED)

All commits are automatically validated by the `.githooks/commit-msg` hook.
Any non-compliant commit will be rejected by git.

### Format Structure
```text
<type>(<scope>): <summary>

Why:
- Explain rationale, background, user requirements, or bug reproduction
- Detail why this change is necessary

How:
- Detail concrete implementation changes and routines modified
- List specific files, entry points, or data structures updated
```

### Commit Rules:
* **Subject line**: `<type>(<scope>): <summary>` where `<type>` is one of
  `feat`, `fix`, `refactor`, `perf`, `docs`, `test`, `chore`.
* **Title length**: Maximum **72 characters**.
* **Body line length**: Maximum **80 characters** strictly across all lines.
* **Mandatory Sections**: Both `Why:` and `How:` sections must be present
  with non-empty descriptive content.
* **Focused Sub-system Scope (MANDATORY)**:
  - Commits must be strictly scoped to a single logical sub-system or concern.
  - NEVER combine unrelated changes into one commit (e.g. do NOT bundle
    core editor assembly changes with drunken monkey test scripts, or plugin
    features with tooling documentation).
  - Use accurate conventional commit scopes (e.g. `feat(plugin)`,
    `fix(editor)`, `test(monkey)`, `docs(ui)`, `chore(tools)`).
* **Merge commits**: Standard git merge messages (starting with `Merge `)
  are exempt from `Why:` / `How:` requirements but must still respect the
  $\le 80$ character line width limit.

### Acceptable vs. Unacceptable Body Styles

#### Acceptable Styles:
1. **Compact Bullet List (Recommended)**:
   - Exactly one blank line between subject and `Why:`, and between `Why:`
     and `How:`.
   - Bullets immediately follow the section header without an intervening
     blank line.
   - List items are single-spaced (no blank lines between items).
   - Wrapped lines are indented with 2 spaces to align with the text.
   ```text
   test(editor): add test suite for 16KB to 32KB file sizes

   Why:
   - Validate editor loading and saving across large file sizes
     ranging from 16,384 bytes up to the maximum limit of 32,768 bytes.
   - Ensure end-to-end byte fidelity across multi-sector CP/M text files.

   How:
   - Implement tests/test_large_file_sizes.py targeting 4 sizes:
     16,384 B (16 KB min), 21,845 B, 27,306 B, and 32,768 B (32 KB max).
   - Generate valid ASCII lines ending in CRLF and inject onto CP/M disk.
   - Boot RC2014 RomWBW emulator, verify document load and line counts.
   - Test top and bottom jumps (Ctrl+G and Ctrl+T), trigger Ctrl+S save cycle.
   - Extract saved files via cpmcp and verify 100% byte fidelity.
   ```

2. **Prose / Numbered Implementation Style**:
   - Structured paragraphs or numbered steps explaining rationale and steps.
   - Paragraphs separated by a single blank line.
   ```text
   fix(file-io): prevent ghost extent creation when saving 32K documents

   Why:
   When saving documents whose sector count fills a directory extent exactly,
   CP/M 2.2 BDOS sequential write (Call 21) automatically advances the extent,
   allocating a new directory entry for extent 2 with 0 records and 0 blocks.
   Host extraction tools treat this as a sparse hole and append null bytes.

   How:
   1. Introduce 16-bit record counter SAVE_RECORD_NUM initialized to 0 in
      MAKE_FILE_OK and MAKE_BLK_FILE_OK.
   2. In WRITE_BYTE_TO_DMA, populate WORK_FCB random record bytes (r0, r1, r2)
      from SAVE_RECORD_NUM and invoke BDOS Call 34 (Write Random).
   3. BDOS Call 34 only allocates extents when records are actually written,
      preventing phantom extent creation upon filling extent boundaries.
   4. Verify 100% byte fidelity across all 4 large file sizes (16KB to 32KB).
   ```

#### Unacceptable Styles (Strictly Forbidden):
1. **Double-Spaced Bullets / Orphan Continuation Lines**:
   - NEVER insert blank lines between wrapped continuation lines of the same
     sentence or bullet point.
   - NEVER double-space bullet lists by inserting blank lines between every
     single bullet item.
   - NEVER place a blank line immediately after `Why:` or `How:` before the
     first bullet point.
   ```text
   [UNACCEPTABLE: broken continuation lines and double-spaced bullets]
   Why:

   - Validate editor loading, navigation, and saving across large file sizes

     ranging from 16,384 bytes up to the maximum limit of 32,768 bytes.

   - Ensure end-to-end byte fidelity across multi-sector CP/M text files.

   How:

   - Implement tests/test_large_file_sizes.py targeting 4 representative sizes:

     16,384 B (16 KB min), 21,845 B, 27,306 B, and 32,768 B (32 KB max).
   ```

2. **Uninformative Placeholders**:
   - NEVER write trivial, empty, or vague content (e.g. `Why:\n- Fix bug`,
     `How:\n- Updated code`).

3. **Exceeding 80 Characters**:
   - NEVER allow any line in the commit body to exceed 80 characters.
     Always run `python3 check_line_length.py` to audit commits before pushing.

---

## 2. Hard House Rules

1. **Line Length (MANDATORY & ENFORCED)**:
   * All files (Assembly `.asm`, C `.c`, `.h`, Python `.py`, Markdown `.md`)
     and git diffs MUST strictly maintain lines $\le 80$ characters.
   * **NEVER run inline python snippets** (`python3 -c "..."`) to check line
     lengths! Running arbitrary one-liner snippets triggers user approval
     prompts each time.
   * **ALWAYS run the project audit script instead**:
     ```bash
     python3 check_line_length.py
     ```
     or:
     ```bash
     make check-lines
     ```
     Command options:
     - `python3 check_line_length.py`: Audits added lines in git diff
       (both unstaged and staged) and latest commit.
     - `python3 check_line_length.py --diff`: Audits unstaged diff added lines.
     - `python3 check_line_length.py --staged`: Audits staged diff added lines.
     - `python3 check_line_length.py <file1> <file2>`: Audits specific files.
2. **Line Endings**:
   * Strictly Unix `LF` (`\n`). Never commit `CRLF`.
3. **CP/M TPA Headroom**:
   * SE.COM code, data, and BSS must fit below BDOS (`0xD800` / 55,296).
   * Always verify with `python3 check_tpa.py SE.COM` or `make check-tpa`.
   * Headroom must remain positive.
4. **Plugin ABI Conformance**:
   * All plugins (4KB, 16KB, 32KB) must pass validation via
     `python3 check_plugin.py --all` or `make check-plugins`.
5. **Hardware & Emulator Dual Compatibility**:
   * All changes must maintain compatibility with the RomWBW RC2014 emulator
     and SC131 real hardware (Z80 / Z180).
6. **UI/UX Design System Conformance (MANDATORY)**:
   * All visual surfaces, modal prompts, and command footers must adhere
     strictly to `docs/UI_UX_DESIGN.md`.
   * Agents must proactively audit screens against the **6 UI/UX
     Anti-Patterns** detailed in `docs/UI_UX_DESIGN.md`:
     1. *Status Bar Squatting* (drawing text input loops directly on Row 24).
     2. *Blind / Static Footers* (displaying static keys that do not match
        active item capabilities).
     3. *Terminal Column Spill* (emitting strings > 78 chars causing wraps).
     4. *Inverted Hierarchy* (asking questions before warning context).
     5. *Missing Dual-Exit* (supporting ESC but ignoring Q/q).
     6. *Buffer Pointer Clobber* (overwriting DE during string formatting).
   * When touching legacy UI routines, agents must remediate existing
     anti-patterns rather than perpetuating them.
7. **Prohibition of "python -c" & Mandatory Script Files (MANDATORY)**:
   * **Absolute Prohibition**: Invoking inline Python code via `python -c` or
     `python3 -c` (whether single-line or multi-line) is strictly prohibited
     under all circumstances without exception.
   * **Mandatory Script Construction**: Whenever Python execution is required
     for diagnostics, probing, test isolation, data parsing, or validation,
     agents MUST construct and save a standalone `.py` script to disk (e.g. in
     the persistent scratch directory or `tests/`) and execute it by filename:
     ```bash
     python3 /path/to/scratch/script.py
     ```
   * **Rationale**:
     - Executing standalone scripts by filename allows the user to grant command
       prefix permission once for the project (e.g. `python3 ...`).
     - In contrast, inline `-c` snippets generate unique command strings on
       every invocation, breaking command prefix matching and repeatedly
       forcing the user to manually approve interactive modal prompts.
     - Standalone scripts leave an auditable, reproducible trail for debugging.
8. **Pre-Merge Validation & Test Summaries (MANDATORY)**:
   * Agents must not merge unvalidated commits into the `master` branch.
   * All changes must undergo rigorous local validation (sanity checks,
     regression test suites, line length checks, and TPA headroom audits)
     prior to requesting a merge.
   * Agents must provide a clear summary of their test results to the user
     before requesting permission to merge to `master`.
   * **Mandatory TPA Headroom Evidence**: As part of the evidence when
     requesting a merge to the `master` branch, agents MUST provide a summary
     table of the `SE.COM` headroom TPA analysis results (from running
     `python3 check_tpa.py SE.COM`) demonstrating positive headroom below
     BDOS (`0xD800`):
     ```text
     +----------------------+----------+---------+-----------+--------+
     | Environment          | BDOS Top | TPA Max | Headroom  | Status |
     +----------------------+----------+---------+-----------+--------+
     | RomWBW RC2014 CP/M  *| 0xD800   | 53.75 KB | +  4,352 B |   PASS  |
     | Standard 64K CP/M    | 0xDC00   | 54.75 KB | +  5,376 B |   PASS  |
     | Minimal 64K CP/M     | 0xD000   | 51.75 KB | +  2,304 B |   PASS  |
     | CP/M Plus (Banked)   | 0xF600   | 61.25 KB | + 12,032 B |   PASS  |
     +----------------------+----------+---------+-----------+--------+
     ```

9. **Validation Test Script Output Standards (MANDATORY & ENFORCED)**:
   * All version-controlled automated test scripts (under `tests/`) must adhere
     to a standardized, three-tier sequential logging convention to ensure
     clear diagnostic pinpointing in automated and headless environments.
   * **Tag Prefixes**:
     - `[*]` (Asterisk): **Initiation Banner**. Logged immediately before
       actions in a step begin. Must include the step number and end with `...`:
       `[*] Step <N>: <Action or Target description>...`
     - `[+]` (Plus): **Completion / Success Tag**. Logged immediately after
       step assertions pass:
       `[+] Step <N>: <Verified Outcome description>.`
     - `[-]` (Minus): **Failure / Error Tag**. Logged upon assertion failure
       or timeout, detailing what failed and capturing diagnostic data:
       `[-] Step <N>: <Failure description>. Buffer: {repr(out[-300:])}`
   * **Sequential Step Numbering**:
     - Every distinct logical test phase must have a 1-based sequential step
       number: `Step 1:`, `Step 2:`, ..., `Step <N>:`.
     - The step number must remain identical across initiation
       (`[*] Step <N>:`), all intermediate assertions, failure logs
       (`[-] Step <N>:`), and the success log (`[+] Step <N>:`).
   * **Stream Flushing**:
     - All test logging `print()` statements must specify `flush=True` to
       prevent stdout buffering across PTYs and background tasks.
   * **Failure Diagnostic State**:
     - All failure logs must capture the terminal buffer or unexpected data
       (e.g. `Buffer: {repr(out)}` or `Buffer: {repr(out[-300:])}`) to allow
       instant root-cause analysis from log files.
   * **Suite Completion Banner**:
     - Tests must conclude with a standardized summary banner reporting elapsed
       wall-clock time:
       `[+] All <Suite Name> tests PASSED in {elapsed:.2f}s!`
   * **Line Width**:
     - All print statements and string concatenations must strictly satisfy
       the $\le 80$ characters per line limit.
   * **Acceptable Pattern**:
     ```python
     # [*] Initiation
     print("[*] Step 4: Entering Editor Mode ('e')...", flush=True)
     os.write(master, b"e")
     out_edit = read_until(master, b"^K: Editor keys", timeout=6.0)

     # [-] Failure with diagnostic context
     if b"(Untitled)" not in out_edit:
         print(f"[-] Step 4: Failed to enter editor mode. "
               f"Buffer: {repr(out_edit)}", flush=True)
         return False

     # [+] Success
     print("[+] Step 4: Entered editor mode with status bar verified.",
           flush=True)
     ```
   * **Unacceptable Patterns**:
     ```python
     # [UNACCEPTABLE: missing Step prefix, missing flush, no diagnostic buffer]
     print("[*] Entering editor mode...")
     if not ok:
         print("[-] Test failed.")
         return False
     print("[+] Editor mode OK.")

     # [UNACCEPTABLE: mismatched step numbers between start and failure logs]
     print("[*] Step 3: Launching editor...", flush=True)
     if not ok:
         print("[-] Step 4: Launch failed.", flush=True)
     ```

10. **Workspace-Isolated Disk Image Architecture (MANDATORY & ENFORCED)**:
    * **Vendor Golden Base Immutability**:
      - The vendor RomWBW disk image at
        `tools/romwbw_src/Binary/hd1k_combo.img` is strictly immutable and
        read-only (`chmod 444`).
      - Under NO circumstances may any agent, build script, test harness, or
        tool write to, modify, truncate, or inject files into this vendor
        image.
      - Mutating the vendor golden image contaminates other workspaces and
        destroys cross-workspace build reproducibility.
    * **Workspace-Local Disk Images**:
      - Every agent workspace must maintain its own dedicated disk image at
        `<workspace>/disks/hd1k_combo.img`.
      - The `disks/` directory and `*.img` files are ignored by git
        (`.gitignore`) to prevent repository bloat while providing full local
        isolation.
    * **Sparse Initialization & Copy-on-Write**:
      - The local image is initialized on demand from the vendor golden base
        using sparse allocation:
        ```bash
        cp --sparse=always $(GOLDEN_IMAGE) $(IMAGE)
        chmod 644 $(IMAGE)
        ```
      - This creates a zero-overhead, copy-on-write sparse file (~50 MB
        allocated blocks) in milliseconds without duplicating storage.
    * **Build System & Test Harness Conformance**:
      - `Makefile` defaults to `IMAGE ?= disks/hd1k_combo.img` with automatic
        sparse creation via the `$(IMAGE)` dependency rule and `init-image`.
      - `make clean-image` removes the workspace `disks/` directory to allow
        clean re-initialization.
      - All automated test scripts (under `tests/`) must resolve `img_file`
        to `os.path.join(repo_root, "disks", "hd1k_combo.img")` and
        auto-initialize via `cp --sparse=always` if not already present.
      - Test scripts and emulators must never point to the vendor golden
        image for read-write execution.

---

## 3. Prohibited Linux Commands (STRICTLY FORBIDDEN)

To safeguard user data, repository integrity, and the host operating system,
agents are strictly forbidden from executing certain destructive or high-risk
Linux commands. Any attempt to use these commands is a critical violation.

### 1. Destructive File Deletion (`rm`)
* **Prohibited**:
  - `rm -rf *`, `rm -rf *.*`, `rm -rf ./*`, `rm -rf /`, `rm -rf ~`: Wildcard
    or root/home recursive wipes.
  - `rm -rf <dir>` without explicit user confirmation.
  - `rm` without a specific, unambiguous filename or path (e.g. `rm -f ./-`
    or `rm -f -` where the target resembles a flag or stdin).
  - Blind batch deletions using globbing (e.g. `rm *.asm`, `rm *.py`).
* **Permitted**:
  - `rm <exact_single_filename>` for specific build artifacts or temporary files
    known to be safe to delete (or use `make clean`).
  - Target explicit files: `rm -f /full/path/to/specific_file.tmp`.

### 2. Destructive Git Commands
* **Prohibited**:
  - `git clean -fd` or `git clean -fdx`: Permanently destroys untracked files
    and work-in-progress.
  - `git reset --hard` (unless explicitly instructed by the user).
  - `git checkout .`, `git checkout -- .`, `git restore .`: Wipes unstaged
    edits across the entire repository.
  - `git push --force`, `git push -f`, or `git push --delete` on protected
    branches (`master`, `agy*_dev_branch`).
  - `git branch -D` on branches containing unmerged work.
* **Permitted**:
  - Scoped restores of individual files: `git restore <specific_file>`.
  - Staging/unstaging: `git add`, `git restore --staged <specific_file>`.
  - Inspecting status: `git status`, `git diff`, `git log`.

### 3. Raw Disk & Filesystem Modification
* **Prohibited**:
  - Direct in-place mutation, overwriting, truncation, or injection into the
    vendor RomWBW disk image (`tools/romwbw_src/Binary/hd1k_combo.img`). All
    disk modifications must strictly target workspace-local
    `disks/hd1k_combo.img`.
  - `dd` targeting block devices (e.g. `dd if=... of=/dev/sd*`, `/dev/nvme*`,
    `/dev/loop*`).
  - `mkfs`, `fdisk`, `parted`, `gparted`, `sfdisk`, `mkswap`.
  - `mount`, `umount` (unless operating within a sandboxed virtual image).
* **Permitted**:
  - Modifying workspace-isolated disk images inside `disks/`
    (e.g. `disks/hd1k_combo.img`) via `cpmtools` or virtual emulators.

### 4. Privilege Escalation & `sudo` Commands (STRICTLY FORBIDDEN)
* **Prohibited**:
  - `sudo` (any invocation, e.g. `sudo <cmd>`, `sudo -n`, `sudo su`, etc.).
    Executing any command with `sudo` is strictly prohibited.
  - `su`, `pkexec`, `doas`, or any privilege escalation mechanism.
  - Modifying `/etc`, `/usr`, `/var`, `/boot`, `/lib`, or system directories.
  - Modifying system services or firewall rules (`systemctl`, `ufw`,
    `iptables`).
  - Recursive permission changes on wide directories (`chmod -R 777 /`,
    `chown -R ... /`).
  - `shutdown`, `reboot`, `poweroff`, `init`.
  - `killall`, `kill -9 -1`, or terminating processes outside the agent task.
* **Rationale**:
  - Agents operate with standard unprivileged user permissions. Privilege
    escalation can corrupt host OS configuration, bypass isolation, or hang
    waiting on interactive password prompts in non-interactive subshells.

### 5. Blind Network & Execution Piping
* **Prohibited**:
  - Pipe-to-shell patterns: `curl ... | bash`, `wget ... | sh`, `fetch | zsh`.
  - Installing system-wide packages (`apt-get install`, `rpm`, `dnf`, `pacman`).
  - Executing untrusted remote scripts or downloading unverified binaries.

### 6. Absolute Prohibition of "python -c" & Use of Python Scripts
* **Prohibited**:
  - `python -c "..."`, `python3 -c "..."`, or any variant of inline Python
    command-line evaluation strings (both single-line and multi-line).
  - Arbitrary Python evaluation one-liners embedded in shell commands or
    command chains.
* **Required**:
  - Standalone Python scripts MUST always be constructed and executed instead
    of inline `-c` snippets.
  - Always write a persistent script to disk (in the scratch directory or
    `tests/`) and execute it by filename:
    ```bash
    python3 tests/scratch_probe.py
    ```
  - For line length checks, always use the audited repository scripts:
    `python3 check_line_length.py` or `make check-lines`.
  - For TPA and plugin checks, use `python3 check_tpa.py` and
    `python3 check_plugin.py`.
* **Rationale**:
  - Constructing and executing scripts by filename allows the user to grant
    the agent permission to run Python scripts by name only once for the project
    (command prefix auto-approval).
  - In contrast, `python -c` inline code snippets create unique command strings
    on every invocation, which breaks tool approval prefix matching and
    repeatedly forces the user to manually review and approve modal prompts.

---

## 4. Multi-Agent Workspace Architecture & On-boarding

To allow multiple autonomous agents (e.g. `agy1`, `agy2`, `agy3`) to work
concurrently without colliding, the project uses isolated git worktrees
and dedicated development branches.

### Repository & Worktree Topology
- **Master Worktree (Main Clone)**:
  `projects/experiment/src/screen_editor`
  Dedicated solely to the `master` branch. Agents must never perform active
  feature development directly inside this directory.
- **Agent Worktrees**:
  `projects/experiment/src/se.com_dev/agy<N>_dev`
  Each agent operates within its own dedicated directory checked out to its
  corresponding dev branch: `agy<N>_dev_branch`.
  - `agy1` -> `src/se.com_dev/agy1_dev` on `agy1_dev_branch`
  - `agy2` -> `src/se.com_dev/agy2_dev` on `agy2_dev_branch`
  - `agy3` -> `src/se.com_dev/agy3_dev` on `agy3_dev_branch`
- **Workspace-Isolated Storage**:
  `src/se.com_dev/agy<N>_dev/disks/`
  Each agent operates on its own isolated disk image (`disks/hd1k_combo.img`)
  sparsely cloned from `tools/romwbw_src/Binary/hd1k_combo.img`. No agent may
  ever touch another workspace's `disks/` or the shared RomWBW vendor image.

### Agent On-boarding Procedure (e.g. for `agy3`)
When initializing a new agent instance (e.g. `agy3`):
1. **Create the dedicated worktree and branch**:
   From the main repo (`projects/experiment/src/screen_editor`):
   ```bash
   git worktree add ../se.com_dev/agy3_dev -b agy3_dev_branch master
   ```
2. **Switch to agent workspace**:
   Ensure all file edits, builds, and test commands are executed strictly
   within `projects/experiment/src/se.com_dev/agy3_dev`.
3. **Configure local git hooks**:
   ```bash
   git config core.hooksPath .githooks
   ```
4. **Publish initial branch to remote**:
   ```bash
   git push -u colossus agy3_dev_branch
   ```
5. **Initialize workspace-isolated disk image**:
   ```bash
   make init-image
   ```

### Daily Agent Workflow & Synchronization
1. **Always verify identity & branch**:
   Run `git status` at startup to confirm working tree is clean and on the
   correct `agy<N>_dev_branch`.
2. **Syncing latest changes from master**:
   Fetch from colossus and merge master into the agent's dev branch:
   ```bash
   git fetch colossus
   git merge colossus/master
   ```
3. **Promoting changes to master**:
   - **Mandatory Pre-Merge Validation**: Agents must not merge unvalidated
     commits. All changes must be fully built, tested, and verified.
   - **Mandatory Test Results Summary**: Agents must provide a comprehensive
     summary of test results to the user before requesting approval to merge
     into `master`.
   - **Mandatory TPA Headroom Evidence**: Agents MUST provide a summary table
     of the `SE.COM` headroom TPA result (from `python3 check_tpa.py SE.COM`)
     verifying positive headroom below BDOS (`0xD800`) as part of the
     evidence provided when requesting permission to merge to `master`.
   - **Explicit User Approval Required**: Only when explicitly requested and
     approved by the user:
     - Commit all work cleanly to `agy<N>_dev_branch`.
     - Merge `agy<N>_dev_branch` into `master` (in `src/screen_editor`).
     - Push both `master` and `agy<N>_dev_branch` to `colossus`.

---

## 5. Protected Branches (ENFORCED ON COLOSSUS & LOCAL HOOKS)

The following branches are strictly protected from deletion, history
rewriting (force pushes), and rogue direct commits:
* `master`
* `agy*_dev_branch` (e.g. `agy1_dev_branch`, `agy2_dev_branch`,
  `agy3_dev_branch`)

Enforced by:
1. Server-side `pre-receive` hook on Colossus (`/git_repos/screen_editor.git`).
2. Client-side `pre-push` hook (`.githooks/pre-push`).
3. Local commit protection hooks (`.githooks/pre-commit` and
   `.githooks/commit-msg`):
   - Prohibit writing direct commits to the head of the local `master` branch.
   - Merging feature/dev branches into `master` (fast-forward or merge commit)
     is permitted.

All updates to these branches must be fast-forward or standard merge commits.
Never attempt `git push --force` or `git push --delete` on these branches.

---

## 6. Porting SE.COM

All AI agents and developers implementing, maintaining, or extending ported
variants of the Screen Editor (such as the Linux C profile `se-linux`, Python
port `se-py`, Rust native `se-rs`, CP/M-86 `SE.CMD`, or ZX Spectrum Next
targets) must conform strictly to the canonical Look and Feel specification:

- **Authoritative Specification Document**:
  [`docs/UI_UX_DESIGN.md`](docs/UI_UX_DESIGN.md).

### Mandatory Porting Invariance Rules:
1. **Universal Status Bar (Row 24 / Row 40)**:
   - Must appear on the bottom row of 100% of screens (Editor, Splash, Open,
     Save, Help, Config, and background of pop-up dialogs).
   - Rendered in inverse video (`\x1b[7m ... \x1b[0m`).
   - Column 0 on the status bar row never displays a tilde.
   - Status events (e.g. Save Confirmations, File Errors, Search Results) must
     NEVER be printed on the status bar; they must be Tier 2 pop-ups.
2. **Strict Column 0 Tilde (`~`) Discipline**:
   - Every unallocated body row below EOF in the editor workspace, and all
     margin rows in centered workspaces and pop-up backgrounds, must display a
     tilde (`~`) in column 0.
3. **Dedicated Surface Hierarchy (The 3 Tiers)**:
   - Tier 1: Mathematically centered full-screen workspaces (Splash, Help,
     Config, File Pickers) using the centering equations in the spec.
   - Tier 2: Mathematically centered boxed modal dialogs with ASCII frames
     (`+---+`, `|   |`) for all confirmations, inputs, and status events.
   - Tier 3: Universal status bar on the bottom row.
4. **Horizontal Panning (`Pan +40`) & Line Boundary**:
   - Strict 120-column physical line length ceiling (`MAX_LINE = 120`).
   - 40-column horizontal panning quantum (`[Pan +40]`, `[Pan +80]`).
5. **WordStar Keybinding Fidelity**:
   - 100% compliance with the canonical WordStar cursor diamond (`^S`, `^D`,
     `^E`, `^X`), navigation shortcuts, and action keys in the spec table.
6. **Automated Headless Conformance Testing**:
   - Every port must include automated headless PTY integration tests
     (validating boot, status bar presence, tildes, modals, and clean exit).

