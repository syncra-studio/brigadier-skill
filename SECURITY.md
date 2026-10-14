# Security policy

## What Brigadier is, security-wise

Brigadier starts Claude Code and, optionally, Codex sessions on your machine and lets them work unattended. By default, workers run with permissions bypassed (`BRIG_PERMISSION_MODE=bypassPermissions`), so they can run any command your user account can. See "Safety & cost" in the README for how to run stricter.

Brigadier itself:
- runs your own, unmodified `claude` and `codex` binaries, and never handles, stores or forwards your credentials or tokens;
- makes no network requests of its own;
- keeps all run state in `~/.claude/brigadier/` on your machine.

## Reporting a vulnerability

Please report security problems privately, through GitHub's **Report a vulnerability** button on this repository's Security tab, not in a public issue. Include what you found, how to reproduce it, and the impact you see. You'll get an acknowledgement within a few days.

Examples of what counts:
- a way for a worker or a crafted repository to make `brig` run commands the user didn't intend (e.g. through task files, run ids or config values);
- `brig` touching processes, files or terminal sessions that don't belong to its own run;
- anything that leaks credentials, tokens or private run state.

Behaviour that is documented and intended, such as workers running with permissions bypassed when that mode is configured, isn't a vulnerability, but ideas for safer defaults are welcome as regular issues.

## Supported versions

Only the latest release gets fixes.
