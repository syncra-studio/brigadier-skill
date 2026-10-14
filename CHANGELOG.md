# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
