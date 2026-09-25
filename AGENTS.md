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
* **Merge commits**: Standard git merge messages (starting with `Merge `)
  are exempt from `Why:` / `How:` requirements but must still respect the
  $\le 80$ character line width limit.

---

## 2. Hard House Rules

1. **Line Length**:
   * All files (Assembly `.asm`, C `.c`, `.h`, Python `.py`, Markdown `.md`)
     MUST strictly maintain lines $\le 80$ characters.
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

---

## 3. Protected Branches (ENFORCED ON COLOSSUS & LOCAL HOOKS)

The following branches are strictly protected from deletion and history
rewriting (force pushes):
* `master`
* `agy1_dev_branch`
* `agy2_dev_branch`

Enforced by:
1. Server-side `pre-receive` hook on Colossus (`/git_repos/screen_editor.git`).
2. Client-side `pre-push` hook (`.githooks/pre-push`).

All updates to these branches must be fast-forward or standard merge commits.
Never attempt `git push --force` or `git push --delete` on these branches.
