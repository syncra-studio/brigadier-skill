# Brigadier

**Hand Claude Code a goal before bed. Wake up to commits, verified phases and a report.**

[![CI](https://github.com/OWNER/brigadier-skill/actions/workflows/ci.yml/badge.svg)](https://github.com/OWNER/brigadier-skill/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![skills.sh](https://img.shields.io/badge/skills.sh-brigadier-black)](https://skills.sh)

Brigadier is a Claude Code skill that keeps work moving while you sleep. It runs a crew of Claude Code workers (plus Codex workers, if you have Codex) in your terminal and answers their questions from your plan. It swaps each worker for a fresh session before its context fills, reviews every phase, and leaves you a morning report.

**Runs in any terminal.** Uses cmux or tmux if you have them, and starts tmux in the background if you don't.

<!-- DEMO: record a short screen capture (a goal going in, worker tabs/windows appearing,
     a handoff, the morning REPORT.md), save it as docs/demo.gif, then uncomment the line below. -->
<!-- ![Brigadier running a crew of workers overnight](docs/demo.gif) -->

## Install

With [skills.sh](https://skills.sh):

```sh
npx skills add OWNER/brigadier-skill -g -a claude-code
```

Or as a Claude Code plugin:

```text
/plugin marketplace add OWNER/brigadier-skill
/plugin install brigadier-skill@brigadier-skill
```

Pick one of the two. Either way you get the `/brigadier` command (as a plugin it's also `/brigadier-skill:brigadier`).

## 60-second quick start

1. In Claude Code, run **`/brigadier doctor`**. It checks your terminal (cmux or tmux), `claude`, `jq`, `git` and the optional `codex`, and prints the exact fix for anything missing.
2. Try a tiny goal in a scratch repo:
   ```text
   /brigadier In this repo, add hello.txt containing "hi" and commit it. One phase only; stop after it.
   ```
3. Watch a worker open in a new tab (cmux), a new window (tmux), or a background tmux session. The brigadier tells you the `tmux attach -t brigadier-<slug>` line to watch it, and `Ctrl-b d` leaves without stopping anything.
4. When it's done, read `~/.claude/brigadier/runs/<run-id>/REPORT.md`. To continue a run later, use `/brigadier resume`.

Then give it a real night's work. Good goals look like this:

```text
/brigadier Implement phases 2-4 of docs/PLAN.md. Stop after Phase 4 or at 07:30.

Rules:
- Work on main in small commits. Never push.
- Each phase starts with an outline; wait for "Go ahead." before building.
- Don't add dependencies the plan doesn't name.

Done when (per phase): the phase's "done when" list in docs/PLAN.md passes, with the commands shown in the report.
```

## How it works

```mermaid
flowchart LR
  you([You, before bed]) -->|/brigadier goal| B[Brigadier session]
  B -->|brig spawn| W1[Worker w01<br/>Claude Code]
  B -->|brig spawn| W2[Worker w02<br/>Claude Code or Codex]
  W1 -. hooks: turn end, context %, prompts .-> S[(run state<br/>~/.claude/brigadier)]
  W2 -. hooks .-> S
  S -->|brig wait wakes it| B
  B -->|answers, handoffs,<br/>reviews| W1
  B -->|REPORT.md| you2([You, in the morning])
```

- **One brigadier, a few workers.** Your session becomes the brigadier. It doesn't write code. Each worker is a full, separate Claude Code (or Codex) session in its own terminal tab or window, with its own context window.
- **It waits cheaply.** `brig wait` blocks in the background until something needs attention, so the brigadier spends almost nothing while workers work.
- **It answers for you, within limits.** Questions and outline approvals get answers from your plan, CLAUDE.md and the goal's rules. Every answer is logged under "Decided on your behalf". Pushes, payments, sign-ups, credentials and messages to people are never approved; they're listed under "Waiting on you".
- **Fresh sessions, not compaction.** When a worker's context passes the threshold, it writes a handoff and a successor picks up from it. The brigadier does the same for itself.
- **Every phase is verified.** A fresh worker reviews the phase's diff (Codex if installed, otherwise a read-only Claude session), checks every "done when" item for real, and fixes what it finds.

| Event from `brig wait` | What the brigadier does |
|---|---|
| `TURN_END wN status=working` | reads the question or outline, reviews plans, answers |
| `TURN_END wN status=done` | checks the report against "done when", closes the worker, verifies the phase |
| `CTX_HIGH` / `COMPACTING` | asks for a handoff, starts a successor with `--continues` |
| `NEEDS_INPUT` | answers a permission prompt if its rules allow, otherwise denies |
| `INTERRUPTED` / `STALL` / `GONE` | checks the screen, nudges, or replaces the worker |
| `RATE_LIMIT` | stops spawning Claude workers, moves bounded work to Codex if available, sleeps until the reset |
| `REBIRTH_DUE` | hands the run to a fresh brigadier session, which confirms before the old one exits |

## Terminals

| You run Claude Code in… | Brigadier uses | Workers appear as |
|---|---|---|
| [cmux](https://cmux.com) | cmux | tabs in your workspace |
| tmux | tmux (attached) | windows in your session (`Ctrl-b w` to pick one) |
| Terminal.app, iTerm, Ghostty, VS Code, an SSH shell… | tmux (background) | windows in a detached session `brigadier-<slug>` (`tmux attach -t brigadier-<slug>`) |

No tmux? `/brigadier doctor` prints the one-line install for your system (`brew install tmux`, `sudo apt install tmux`, …). Windows (wmux), Zellij, WezTerm and kitty backends are welcome as contributions; each is one small file (see [CONTRIBUTING.md](CONTRIBUTING.md)).

## Configuration

All settings live in one file, `~/.claude/brigadier/config.env`. Copy [`config.example.env`](skills/brigadier/config.example.env) there and change what you need. A run can override settings in `<run>/config.env`, and environment variables override both. `/brigadier doctor` checks the file, and `/brigadier config` shows the effective values and where each one came from.

| Setting | Default | What it does |
|---|---|---|
| `BRIG_BACKEND` | `auto` | `cmux`, `tmux`, or auto-detect |
| `BRIG_DEFAULT_MODEL` | `opus` | model for workers and the reborn brigadier |
| `BRIG_CHORE_MODEL` | `sonnet` | model suggested for mechanical chores |
| `BRIG_ALLOWED_MODELS` | `*` | allowlist, e.g. `"opus sonnet"`; enforced for workers and their subagents |
| `BRIG_DEFAULT_EFFORT` / `BRIG_MAX_EFFORT` | `high` / `high` | effort for workers, and the ceiling nothing may exceed (Claude and Codex) |
| `BRIG_MAX_WORKERS` | `3` | most workers at once |
| `BRIG_CTX_PCT` / `BRIG_CTX_TOKENS` | `70` / `300000` | hand a worker off at whichever comes first |
| `BRIG_SELF_TOKENS` | `150000` | the brigadier's own handoff point |
| `BRIG_STALL_MIN`, `BRIG_IDLE_SEC`, `BRIG_RATE_PCT` | `30`, `120`, `95` | watchdog thresholds |
| `BRIG_CODEX` | `auto` | use Codex when it's on PATH; `off` to never use it |
| `BRIG_REVIEWER` | `auto` | `codex`, `claude`, or `off` |
| `BRIG_PERMISSION_MODE` | `bypassPermissions` | worker permission mode (see Safety) |
| `BRIG_CLAUDE_CONFIG_DIR` | — | run new workers under another Claude Code config dir |

## Safety & cost

Read this before your first night.

- **Workers run unattended with permissions bypassed by default** (`--permission-mode bypassPermissions`, and Codex without its sandbox). That's what lets work continue while you sleep, and it means a worker can run any command your user account can. Run Brigadier on repos and machines where that's acceptable. To be stricter, set `BRIG_PERMISSION_MODE` to `acceptEdits`, `auto`, `dontAsk` or `manual`. Prompts then reach the brigadier, which approves only what its rules allow, and Codex workers run in their workspace-write sandbox.
- **Its rules forbid pushing, publishing, deploying, spending money, signing up for anything or contacting anyone on your behalf.** Workers stub those and the report lists them under "Waiting on you". The worker protocol also bans killing processes by name and deleting other runs' scratch files. These are instructions the sessions follow, not a sandbox: with permissions bypassed, nothing technically stops a worker that ignores them.
- **It uses your own subscription quota.** Every worker is a normal Claude Code (or Codex) session on your account, so a night of work uses your plan's limits like a day of work would. When the 5-hour window passes `BRIG_RATE_PCT` (95%), the brigadier stops starting Claude workers and waits for the reset. If you also run the Brigadier app at the same time, both share that one subscription's 5-hour window.
- **It drives your own, unmodified `claude` and `codex` binaries in your own terminal.** No tokens are shared or proxied, there's no API intermediary, and nothing is sent anywhere except by those official CLIs. Run state stays in `~/.claude/brigadier/` on your machine.
- **Keep the machine awake.** A sleeping laptop stops the run. On macOS, `caffeinate -dimsu` in a spare tab works.

## FAQ

**Do I need Codex?** No. Everything works with Claude Code alone. If `codex` is installed, Brigadier also uses it as a second reviewer and for bounded tasks, which helps when Claude's 5-hour window runs out.

**Which plan or model do I need?** Any Claude Code setup works. Workers use `opus` by default. If your plan doesn't include it, set `BRIG_DEFAULT_MODEL=sonnet`.

**How is this different from subagents?** Subagents live inside one session and return when the session's turn ends. Brigadier workers are separate full sessions, each with its own context window. They run for hours, get replaced before their context fills, and leave a paper trail (task, report, handoff) for every step.

**Can I watch or step in?** Yes. Open any worker's tab or window and read along. To change direction, tell the brigadier session; it speaks to the workers. `/brigadier resume` picks a run up again after a restart.

**Can I run two at once?** Yes, in different repos or tabs. Each brigadier session is bound to its own run.

**Does it work on Linux, WSL or a remote server?** Yes, through tmux. CI runs on Ubuntu and macOS. WSL should work the same way, but it isn't tested yet.

**Windows?** A native Windows (wmux) edition is experimental and coming later.

**Where does state live, and how do I uninstall?** Runs live in `~/.claude/brigadier/runs/`. Remove the skill with `npx skills remove -g brigadier`, or with `/plugin uninstall brigadier-skill@brigadier-skill`. Then delete `~/.claude/brigadier/` if you want the run history gone.

**Does it work inside the Brigadier app?** No, on purpose. The app has its own Overnight mode, and the skill stops with a one-line pointer to it.

---

Brigadier has a big sibling: the [Brigadier app](APP_URL).

[Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [Changelog](CHANGELOG.md) · [MIT License](LICENSE)
