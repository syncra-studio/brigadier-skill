# shellcheck shell=bash
# Terminal backend: wmux (Windows), the cmux port at https://github.com/amirlehmam/wmux.
# Workers are tabs (surfaces) in the brigadier's wmux workspace. The brigadier itself runs in a
# wmux tab, because wmux puts its `wmux` CLI on PATH only there. Written against wmux 2.24.0.
# Sourced by brig. Contract: see CONTRIBUTING.md ("Adding a terminal backend").
# Run-level variables available here (from run.env): WORKSPACE, WMUX_BASH (Git Bash's bash.exe:
# wmux opens tabs in PowerShell, where a bare `bash` is WSL's launcher or nothing at all).

# MSYS would rewrite any argument that looks like a POSIX path, message text included.
# Paths that wmux needs are converted explicitly instead.
wm() { MSYS2_ARG_CONV_EXCL='*' wmux "$@"; }

be_available() { [[ -n "${WMUX_SURFACE_ID:-}" ]] && command -v wmux >/dev/null 2>&1; }

# be_init_run <run-dir> <slug>: prints KEY=VALUE lines for run.env.
be_init_run() {
  [[ -n "${WMUX_SURFACE_ID:-}" ]] || die "wmux backend: not inside a wmux tab (WMUX_SURFACE_ID is unset)"
  local ws b
  ws="$(wm whoami | jq -r '.id // empty')" || die "wmux: 'wmux whoami' failed; is wmux running?"
  [[ -n "$ws" ]] || die "wmux: 'wmux whoami' did not name this tab's workspace"
  b="$(git_bash)" || die "wmux: Git Bash's bash.exe not found; set CLAUDE_CODE_GIT_BASH_PATH to it"
  printf 'MODE=attached\nWORKSPACE=%q\nWMUX_BASH=%q\n' "$ws" "$b"
}

be_self_id() { echo "${WMUX_SURFACE_ID:-}"; }

# A PowerShell single-quoted string.
ps_quote() { local sq="'"; printf "'%s'" "${1//$sq/$sq$sq}"; }

# `agent spawn` runs --cmd in the tab's PowerShell. `; exit` closes the tab when the worker ends,
# so a dead worker shows up as GONE instead of an idle prompt.
be_spawn() {
  local cwd="$1" cmd="$2" title="$3" out sid
  out="$(wm agent spawn --workspace "$WORKSPACE" --cwd "$(native_path "$cwd")" --label "$title" \
    --cmd "& $(ps_quote "$WMUX_BASH") $(ps_quote "$(native_path "$cmd")"); exit" 2>&1)" \
    || die "wmux: could not open a tab: $out"
  sid="$(jq -r '.surfaceId // empty' <<<"$out" 2>/dev/null)"
  [[ -n "$sid" ]] || die "wmux: could not read a surface id from: $out"
  wm rename-surface "$sid" "$title" >/dev/null 2>&1 || true
  # The new tab becomes the active one in its pane (App.tsx, the agent "spawned" handler); hand
  # the brigadier's own tab back so the user keeps seeing it.
  if [[ -n "${WMUX_SURFACE_ID:-}" ]]; then wm focus-surface "$WMUX_SURFACE_ID" >/dev/null 2>&1 || true; fi
  echo "$sid"
}

# `send` types its text literally: no escapes are interpreted, so backslashes need no special care.
be_send_text() { wm send --surface "$1" "$2" >/dev/null; }
be_send_enter() { wm send-key enter --surface "$1" >/dev/null; }
be_read() { wm read-screen --surface "$1" --lines "${2:-40}" | jq -r '.text // empty'; }
# close-surface answers ok even for an id that's already gone.
be_close() { wm close-surface "$1" >/dev/null 2>&1 || true; }
# list-surfaces covers one workspace, so walk them all.
be_live_ids() {
  local wss ws
  wss="$(wm list-workspaces | jq -r '.workspaces[].id')" || return 1
  for ws in $wss; do
    wm list-surfaces --workspace "$ws" | jq -r '.surfaces[].id' || return 1
  done
}
# wmux sends notifications as one line, with a fixed "wmux" title.
be_notify() { local t="$1: $2"; wm notify "${t//$'\n'/ }" >/dev/null 2>&1 || true; }
be_status() {
  if [[ -n "$1" ]]; then wm set-status --workspace "$WORKSPACE" --state running --text "$1" >/dev/null 2>&1 || true
  else be_status_clear; fi
}
be_status_clear() { wm set-status --workspace "$WORKSPACE" --state idle >/dev/null 2>&1 || true; }
be_watch_hint() { echo "Workers open as tabs in this wmux workspace."; }
