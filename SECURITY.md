# Security policy

## What Brigadier is, security-wise

Brigadier starts Claude Code and, optionally, Codex sessions on your machine and lets them work unattended. The defaults differ by agent:
- **Claude workers** run with permissions bypassed (`BRIG_PERMISSION_MODE=bypassPermissions`), so they can run any command your user account can. Set a stricter mode to have prompts reach the brigadier instead.
- **Codex workers** run in Codex's `workspace-write` sandbox (`BRIG_CODEX_SANDBOX=workspace-write`): they can write the repo, its git dirs and their own control dir, with network on and no prompts. `BRIG_CODEX_SANDBOX=bypass` turns the sandbox off. A Codex worker accepts queued messages only when they carry its per-worker inbox token, which only `brig send` writes; other files are refused and reported to the brigadier.

`brig doctor` prints both settings. See "Safety & cost" in the README.

Brigadier itself:
- runs your own, unmodified `claude` and `codex` binaries, and never handles, stores or forwards your credentials or tokens;
- makes no network requests of its own (on Windows with openwong2kim/wmux it talks to that app's local named pipe, using the app's own auth token file);
- keeps all run state in `~/.claude/brigadier/` on your machine.

`brig setup` (`/brigadier setup`):
- prints the exact package-manager command for anything missing (brew, apt, dnf, pacman, apk, zypper, winget) and runs it only with `--install`, after you confirm or pass `--yes`;
- never runs a `sudo` command that would ask for a password without a terminal; it leaves that command for you;
- never downloads or runs an installer itself (amirlehmam/wmux is a manual download from its releases page);
- never overwrites an existing `config.env`; it only creates one with every setting commented out, and strips Windows line endings from it (keeping the original as `config.env.bak`) and from the skill's own files.

## Reporting a vulnerability

Please report security problems privately, through GitHub's **Report a vulnerability** button on this repository's Security tab, not in a public issue. Include what you found, how to reproduce it, and the impact you see. You'll get an acknowledgement within a few days.

Examples of what counts:
- a way for a worker or a crafted repository to make `brig` run commands the user didn't intend (e.g. through task files, run ids or config values);
- `brig` touching processes, files or terminal sessions that don't belong to its own run;
- anything that leaks credentials, tokens or private run state.

Behaviour that is documented and intended, such as workers running with permissions bypassed when that mode is configured, isn't a vulnerability, but ideas for safer defaults are welcome as regular issues.

## Supported versions

Only the latest release gets fixes.
