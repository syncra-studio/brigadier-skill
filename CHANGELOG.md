# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `/brigadier setup`: the one setup step after installing. It checks git, jq, claude, the terminal and codex, and prints the exact install command for your OS (macOS, Debian/Ubuntu, Fedora, Arch, Alpine, openSUSE, Windows with winget). It runs that command only with `--install` and your confirmation. It also creates a commented-out config.env and fixes Windows line endings, then runs doctor.
- Windows support through Git Bash, with two wmux backends: `wmux` for amirlehmam/wmux (recommended) and `wmux-ow` for openwong2kim/wmux (fallback, driven over its RPC pipe through PowerShell). The right one is picked automatically, and doctor names the one it found and its version.
- `brig send <wid> --file <path>` for long answers; inline messages over 2000 characters are refused with a pointer to it.
- `REJECTED` event in `brig wait`: a Codex worker refused a queued message that didn't come from `brig send`.
- Guardrails section in SKILL.md; doctor prints how Claude and Codex workers are allowed to act.
- `brig key <wid> <key>...` presses keys in a worker's terminal (`enter`, `escape`, the arrows, `tab`, `space`, `1`–`9`) and refuses any other key. Every backend implements the new `be_send_key`. The brigadier uses it to answer `NEEDS_INPUT` dialogs instead of sending text.
- Claude Code's "trust this folder" dialog: `brig spawn` notes when Claude Code hasn't trusted the worker's folder yet (it reads `.claude.json` and never writes it), `brig wait` raises `TRUST_PROMPT <wid>` with the folder and options, and `brig check` shows it. `brig trust <wid>` reads which option has the cursor, moves to "Yes, I trust this folder" and presses Enter, and presses nothing if it can't tell (`TRUST_UNREADABLE`). The brigadier accepts only for the run's own repo, or a worktree or subfolder of it.
- `brig runs` shows each run's repo and the first line of its goal; `--here` lists this repo's runs only and `--overlap` names other runs on the same repo that were active during this one (REPORT.md mentions them under Problems).

### Changed
- **Codex workers now run in Codex's `workspace-write` sandbox by default** (network on; the repo, its real git dirs and the worker's control dir writable, so commits work in worktrees too). Set `BRIG_CODEX_SANDBOX=bypass` for the old unsandboxed behaviour. `BRIG_PERMISSION_MODE` now applies to Claude workers only.
- Codex workers accept queued messages only with their per-worker token, strip control characters, cap them at 8 KB and frame them as the brigadier's message.
- README: install is two steps (install the skill, then `/brigadier setup`).
- A bare `/brigadier resume` resumes the only unfinished run of this repo if it has a goal; otherwise it lists the runs and asks which one. `resume <run-id>` and rebirth never ask.
- A model named in the goal without a role applies to every worker of the run, verifiers included; a model named for a role applies to that role only. A run-level model keeps Codex workers out unless the goal names Codex.
- A run's `config.env` may tighten `BRIG_MAX_EFFORT` and `BRIG_ALLOWED_MODELS` but no longer loosen them; `brig config` shows what it ignored.
- The reborn brigadier follows `BRIG_PERMISSION_MODE`, like workers, and the user's own default model rather than the run's. Doctor and the Guardrails say so.
- `/brigadier` starts with `brig init` in a Bash call of its own and reads CLAUDE.md, AGENTS.md and project memory with the Read tool, so a missing file is no error.
- Doctor for openwong2kim/wmux says it was tested on a real PC with 4.3.0 (source read at 4.5.0).

### Fixed
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
