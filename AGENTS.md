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
7. **Scratch Python Scripts Over Ad-Hoc Snippets (MANDATORY)**:
   * Scratch python scripts should be used instead of ad-hoc python code
     snippets (`python3 -c '...'`).
   * Executing a standalone scratch python script by filename allows the user
     to grant the agent permission to run the python script by name only
     once for the project (via command prefix matching).
   * In contrast, inline ad-hoc snippets generate novel command strings each
     time, disabling prefix auto-approval and repeatedly prompting the user.
8. **Pre-Merge Validation & Test Summaries (MANDATORY)**:
   * Agents must not merge unvalidated commits into the `master` branch.
   * All changes must undergo rigorous local validation (sanity checks,
     regression test suites, line length checks, and TPA headroom audits)
     prior to requesting a merge.
   * Agents must provide a clear summary of their test results to the user
     before requesting permission to merge to `master`.

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
  - `dd` targeting block devices (e.g. `dd if=... of=/dev/sd*`, `/dev/nvme*`,
    `/dev/loop*`).
  - `mkfs`, `fdisk`, `parted`, `gparted`, `sfdisk`, `mkswap`.
  - `mount`, `umount` (unless operating within a sandboxed virtual image).

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

### 6. Scratch Python Scripts vs. Ad-Hoc Python Code Snippets
* **Prohibited**:
  - Ad-hoc python code snippets (`python3 -c "..."` or multi-line
    `python3 -c '...'`).
  - Arbitrary python evaluation one-liners embedded in shell commands.
* **Required**:
  - Scratch python scripts should be used instead of ad-hoc python code
    snippets.
  - Always write a persistent scratch script to disk (e.g. in the scratch
    directory or `tests/`) and execute it by filename:
    ```bash
    python3 tests/scratch_probe.py
    ```
  - For line length checks, always use the audited repository scripts:
    `python3 check_line_length.py` or `make check-lines`.
  - For TPA and plugin checks, use `python3 check_tpa.py` and
    `python3 check_plugin.py`.
* **Rationale**:
  - Using scratch python scripts allows the user to grant the agent
    permission to run the python script by name only once for the project
    (command prefix auto-approval).
  - In contrast, ad-hoc inline code snippets create unique command strings on
    every invocation, which breaks tool approval prefix matching and repeatedly
    forces the user to manually review and approve modal prompts.

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
