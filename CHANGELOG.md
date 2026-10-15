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

### Changed
- **Codex workers now run in Codex's `workspace-write` sandbox by default** (network on; the repo, its real git dirs and the worker's control dir writable, so commits work in worktrees too). Set `BRIG_CODEX_SANDBOX=bypass` for the old unsandboxed behaviour. `BRIG_PERMISSION_MODE` now applies to Claude workers only.
- Codex workers accept queued messages only with their per-worker token, strip control characters, cap them at 8 KB and frame them as the brigadier's message.
- README: install is two steps (install the skill, then `/brigadier setup`).

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
