# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-10-16

### Added
- `brig --run <run-id> <command>` selects a run without an environment prefix, so a narrow Bash permission rule can match. The skill grants only its bundled `brig` script for the invoking turn; rebirth settings grant that script for the new session.
- Doctor advises about the brigadier’s auto mode, including the interactive built-in default, using user/project/local settings read only. It prints a non-auto launch command and the exact scoped allow rule, and warns when openwong2kim/wmux runs non-bypass workers.
- `/brigadier setup`: the one setup step after installing. It checks git, jq, claude, the terminal and codex, and prints the exact install command for your OS (macOS, Debian/Ubuntu, Fedora, Arch, Alpine, openSUSE, Windows with winget). It runs that command only with `--install` and your confirmation. It also creates a commented-out config.env and fixes Windows line endings, then runs doctor.
- Windows support through Git Bash, with two wmux backends: `wmux` for amirlehmam/wmux (recommended) and `wmux-ow` for openwong2kim/wmux (fallback, driven over its RPC pipe through PowerShell). The right one is picked automatically, and doctor names the one it found and its version.
- `brig send <wid> --file <path>` for long answers; inline messages over 2000 characters are refused with a pointer to it.
- `REJECTED` event in `brig wait`: a Codex worker refused a queued message that didn't come from `brig send`.
- Guardrails section in SKILL.md; doctor prints how Claude and Codex workers are allowed to act.
- `brig key <wid> <key>...` presses keys in a worker's terminal (`enter`, `escape`, the arrows, `tab`, `space`, `1`–`9`) and refuses any other key. Every backend implements the new `be_send_key`. The brigadier uses it to answer `NEEDS_INPUT` dialogs instead of sending text.
- Claude Code's "trust this folder" dialog: `brig spawn` notes when Claude Code hasn't trusted the worker's folder yet (it reads `.claude.json` and never writes it), `brig wait` raises `TRUST_PROMPT <wid>` with the folder and options, and `brig check` shows it. `brig trust <wid>` reads which option has the cursor, moves to "Yes, I trust this folder" and presses Enter only once the screen shows the cursor there (the list wraps around, so a lost or extra arrow would land on "No, exit"); if it can't tell, it doesn't press Enter (`TRUST_UNREADABLE`). The brigadier accepts only for the run's own repo, or a worktree or subfolder of it.
- `brig runs` shows each run's repo and the first line of its goal, and lists every unfinished run (finished ones up to 30 rows); `--here` lists this repo's runs only and `--overlap` names other runs on the same repo that were active during this one (REPORT.md mentions them under Problems).

### Changed
- Default state and config move to `~/.brigadier`, outside Claude Code’s protected config directory. When only the old `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/brigadier` exists it stays in use; doctor prints a manual move command. `BRIG_HOME` wins, and old absolute bindings still resolve after a move. Nothing moves automatically.
- Generated worker settings allow reading the run and editing only the worker’s own control directory, so task reads and status/report writes need no approval in acceptEdits or Manual outside protected paths. The reborn brigadier gets its run directory too.
- The playbook takes ledger times from `date +%H:%M` or `events.log`, and never retries wmux’s refusal to approve a worker dialog; Escape denies only when the rules require denial.
- **Codex workers now run in Codex's `workspace-write` sandbox by default** (network on; the repo, its real git dirs and the worker's control dir writable, so commits work in worktrees too). Set `BRIG_CODEX_SANDBOX=bypass` for the old unsandboxed behaviour. `BRIG_PERMISSION_MODE` applies to Claude workers and the reborn brigadier.
- Codex workers accept queued messages only with their per-worker token, strip control characters, cap them at 8 KB and frame them as the brigadier's message.
- README: install is two steps (install the skill, then `/brigadier setup`).
- A bare `/brigadier resume` resumes the only unfinished run of this repo if it has a goal; otherwise it lists the runs and asks which one. `resume <run-id>` and rebirth never ask.
- A model named in the goal without a role applies to every worker of the run, verifiers included; a model named for a role applies to that role only. A run-level model keeps Codex workers out unless the goal names Codex.
- A run's `config.env` may tighten `BRIG_MAX_EFFORT` and `BRIG_ALLOWED_MODELS` but no longer loosen them; `brig config` shows what it ignored.
- The reborn brigadier follows `BRIG_PERMISSION_MODE`, like workers, and the user's own default model rather than the run's, at an effort no higher than `BRIG_MAX_EFFORT`. Doctor and the Guardrails say so.
- `/brigadier` starts with `brig init` in a Bash call of its own and reads CLAUDE.md, AGENTS.md and project memory with the Read tool, so a missing file is no error.
- Doctor for openwong2kim/wmux says it was tested on a real PC with 4.3.0 (newer releases read from source up to 4.5.0).

### Fixed
- Run migration remaps only the old state directory's paths; an unrelated missing run path is still an error.
- Permission rules escape metacharacters in control-directory names, keeping Read/Edit grants scoped to the literal directory.
- The second idle-screen read rechecks hooks and transcript activity, so a worker that finishes during the pause is not reported as interrupted or stalled.
- Permission dialogs no longer look like idle/interrupted workers: NEEDS_INPUT refreshes their idle clock, screens recognize dialogs, and INTERRUPTED requires a second idle read.
- openwong2kim/wmux errors name the method only once; backend documentation now says Escape can deny a worker permission dialog, while approvals need the user.
- Windows (Git Bash):
  - `.gitattributes` keeps every file LF, so a checkout with `core.autocrlf` no longer breaks the scripts.
  - jq runs with `-b`, so its output has no CR.
  - Config and status files written by Windows editors or PowerShell are read correctly.
  - Run bindings are plain files, because `ln -s` copies there.
  - Paths given to Claude, Codex and wmux are native (`C:/…`).
  - Hooks, the statusLine and launch scripts start Git Bash by its full path instead of a bare `bash`, which can be WSL's launcher.
  - `/brigadier resume …` reaches claude.exe without MSYS rewriting it into a path.
  - New workers find tools that winget installed after the terminal opened.
  - `send --file` and `rebirth` accept a `C:/…` path; Codex workers and the rebirth closer find a jq that winget installed as `jq-*.exe`.
  - doctor fails with the upgrade command when jq is too old for `-b`.
  - Paths with curly apostrophes (’) are quoted safely for PowerShell.
- `/brigadier setup` writes config.env with one preamble instead of two.
- A worker's settings.json `effortLevel` is the effort it starts with (`--effort`), not always `BRIG_DEFAULT_EFFORT`.
- `brig status` shows `-` for a Codex worker's 5-hour window instead of `0%`.
- Doctor finds openwong2kim/wmux's version from its pipe, or else from its newest `%LOCALAPPDATA%\wmux\app-X.Y.Z` folder, since its CLI has no `--version`.

## [0.1.0] - 2026-10-14

First public release.

### Added
- `/brigadier <goal>`, `/brigadier resume [run-id]`, `/brigadier doctor` and `/brigadier config`.
- `brig` control helper: runs, workers, `wait` events, handoffs with `--continues`, self-rebirth with an acknowledgement handshake, reviews, `doctor`, `config`.
- Terminal backends: cmux, tmux attached, and tmux background mode for plain terminals.
- Optional Codex support: Codex workers and Codex reviews when `codex` is on PATH, read-only Claude reviews otherwise.
- One config file for models, effort ceiling, crew size, thresholds and worker permission mode, enforced by `brig`.
- Installs through skills.sh (`npx skills add`) or as a Claude Code plugin marketplace.
- Test suite with fake `claude`, `codex`, `cmux` and `tmux`, a real-tmux smoke test, and CI on Ubuntu and macOS.
