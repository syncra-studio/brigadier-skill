# Contributing

Thanks for helping. Issues and pull requests are welcome.

## Ground rules

- Keep `brig` in portable bash: it must run on macOS's bash 3.2 and on Linux (no associative arrays, no `mapfile`, no GNU-only or BSD-only flags without a fallback).
- Start every bundled script with `bash <path>` and never rely on executable bits; installers don't always keep them.
- Never read or write `BRIGADIER_*` environment variables other than `BRIGADIER_SESSION`, and never create git branches under `brigadier/` or `overnight/`. Those belong to the Brigadier app.
- Every change keeps `bash tests/run.sh` green (shellcheck + fake-terminal suites + real-tmux smoke).

## Running the checks

```sh
bash tests/run.sh               # everything
bash tests/run.sh --no-smoke    # skip the real-tmux smoke test
bash tests/test_backends.sh cmux tmux-bg   # one suite, some backends
```

You need `shellcheck`, `jq`, `git` and, for the smoke test, `tmux`. The suites put fake `claude`, `codex`, `cmux` and `tmux` first on `PATH`, so they never touch your real sessions or spend any quota. Each run uses its own `/tmp/brig-test-XXXXXX` directory and its own tmux server, and cleans up only what it created.

## Adding a terminal backend

A backend is one file, `skills/brigadier/scripts/backends/<name>.sh`, that `brig` sources. Nothing else in `brig` talks to a terminal. Implement these functions:

| Function | Required | Contract |
|---|---|---|
| `be_available` | yes | exit 0 if this backend can run here |
| `be_init_run <run-dir> <slug>` | yes | set up for a new run; print `KEY=value` lines (shell-quoted) for `run.env`, including `MODE=attached` or `MODE=background` and anything your other functions need later |
| `be_spawn <cwd> <script> <title>` | yes | open a new tab, window or pane in `<cwd>` that runs `bash <script>`; print its id |
| `be_send_text <id> <text>` | yes | type `<text>` literally, without Enter |
| `be_send_enter <id>` | yes | press Enter |
| `be_read <id> <lines>` | yes | print the last `<lines>` lines of the screen |
| `be_close <id>` | yes | close it |
| `be_live_ids` | yes | print every live id, one per line; exit non-zero only if the terminal can't be queried |
| `be_self_id` | no | the id of the terminal this process runs in, so a rebirth can close the old brigadier |
| `be_notify <title> <body>`, `be_status <text>`, `be_status_clear` | no | best effort; must never fail |
| `be_watch_hint` | no | one line telling the user where to watch the workers |
| `be_finish` | no | clean up at the end of a run |

Variables from `run.env` are in scope when your functions run. Then:

1. Teach `pick_backend` in `brig` when to choose it automatically (an environment variable the terminal sets, for example).
2. Add a fake for it under `tests/fakes/term/` (the shared `faketerm.sh` does most of the work) and add it to the backend list in `tests/test_backends.sh`.
3. Mention it in the README's Terminals table.

Backends we'd love to see: Windows (wmux), Zellij, WezTerm, kitty, iTerm.

## Changing the playbook

`SKILL.md` is what the brigadier reads, and `worker-protocol.md` is what every worker reads. Keep both short, imperative and free of project- or person-specific details. The Agent Skills spec recommends keeping `SKILL.md` under 500 lines.

## Releases

Bump `BRIG_VERSION` in `brig`, `version` in `.claude-plugin/plugin.json` and `metadata.version` in `SKILL.md`, and add a CHANGELOG entry.
