# shellcheck shell=bash
# Terminal backend: cmux (macOS). Workers are tabs (surfaces) in the brigadier's cmux workspace.
# Sourced by brig. Contract: see CONTRIBUTING.md ("Adding a terminal backend").
# Run-level variables available here (from run.env): WORKSPACE.

be_available() { [[ -n "${CMUX_WORKSPACE_ID:-}" ]] && command -v cmux >/dev/null 2>&1; }

# be_init_run <run-dir> <slug>: prints KEY=VALUE lines for run.env.
be_init_run() {
  [[ -n "${CMUX_WORKSPACE_ID:-}" ]] || die "cmux backend: not inside a cmux terminal (CMUX_WORKSPACE_ID is unset)"
  printf 'MODE=attached\n'
  printf 'WORKSPACE=%q\n' "$CMUX_WORKSPACE_ID"
}

be_self_id() { echo "${CMUX_SURFACE_ID:-}"; }

be_spawn() {
  local cwd="$1" cmd="$2" title="$3" out sid
  out="$(cmux --id-format uuids new-surface --workspace "$WORKSPACE" --working-directory "$cwd" --command "bash $(q "$cmd")" --focus false)"
  sid="$(grep -Eo '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' <<<"$out" | head -1)"
  [[ -n "$sid" ]] || die "cmux: could not parse a surface id from: $out"
  cmux rename-tab --surface "$sid" "$title" >/dev/null 2>&1 || true
  echo "$sid"
}

# --force: the brigadier is the only typist in a worker tab, and NEEDS_INPUT answers go into open dialogs.
# Keystroke mode turns \n, \r and \t into keys, so text with a backslash is pasted instead.
be_send_text() {
  if [[ "$2" == *\\* ]]; then cmux send --paste --force --surface "$1" -- "$2" >/dev/null
  else cmux send --force --surface "$1" -- "$2" >/dev/null; fi
}
be_send_enter() { cmux send-key --force --surface "$1" enter >/dev/null; }
be_read() { cmux read-screen --surface "$1" --lines "${2:-40}"; }
be_close() { cmux close-surface --force --surface "$1" >/dev/null; }
be_live_ids() {
  local j; j="$(cmux --id-format uuids tree --all --json)" || return 1
  jq -r '.. | objects | select(has("surfaces")) | .surfaces[].id' <<<"$j"
}
be_notify() { cmux notify --title "$1" --body "$2" >/dev/null 2>&1 || true; }
be_status() { cmux set-status brigadier "$1" --workspace "$WORKSPACE" >/dev/null 2>&1 || true; }
be_status_clear() { cmux clear-status brigadier --workspace "$WORKSPACE" >/dev/null 2>&1 || true; }
be_watch_hint() { echo "Workers open as tabs in this cmux workspace."; }
