# shellcheck shell=bash
# Terminal backend: tmux (macOS, Linux, WSL, SSH servers).
#   attached:   the brigadier runs inside tmux; workers are windows of its session.
#   background: the brigadier runs in a plain terminal; brig starts a detached session
#               named brigadier-<slug> and runs the workers there.
# Sourced by brig. Contract: see CONTRIBUTING.md ("Adding a terminal backend").
# Run-level variables available here (from run.env): MODE, TMUX_SESSION, TMUX_SOCKET, TMUX_SOCKET_PATH.

# Attached runs talk to the server the brigadier was started in (socket path from $TMUX),
# background runs to the default server, or to BRIG_TMUX_SOCKET (-L) when set.
tm() {
  if [[ -n "${TMUX_SOCKET_PATH:-}" ]]; then tmux -S "$TMUX_SOCKET_PATH" "$@"
  elif [[ -n "${TMUX_SOCKET:-}" ]]; then tmux -L "$TMUX_SOCKET" "$@"
  else tmux "$@"; fi
}

be_available() { command -v tmux >/dev/null 2>&1; }

# tm_bg_session <name> <run-dir> <cwd>: a detached session whose window 0 shows `brig watch`.
tm_bg_session() {
  tm new-session -d -s "$1" -c "$3" -n status -x 200 -y 50 "BRIG_RUN=$(q "$2") bash $(q "$BRIG_SCRIPT") watch" \
    || die "tmux: could not start the background session $1"
}

be_init_run() {
  local slug="$2"
  command -v tmux >/dev/null 2>&1 || die "tmux is not installed. $(install_hint tmux)"
  if [[ -n "${TMUX:-}" && "${BRIG_TMUX_MODE:-auto}" != background ]]; then
    TMUX_SOCKET_PATH="${TMUX%%,*}"
    local sess; sess="$(tm display-message -p ${TMUX_PANE:+-t "$TMUX_PANE"} '#{session_id}')" || die "tmux: cannot read the current session"
    printf 'MODE=attached\nTMUX_SESSION=%q\nTMUX_SOCKET_PATH=%q\n' "$sess" "$TMUX_SOCKET_PATH"
    return
  fi
  TMUX_SOCKET="${BRIG_TMUX_SOCKET:-}"
  local base="brigadier-$slug" name n=1
  name="$base"
  while tm has-session -t "=$name" 2>/dev/null; do n=$((n + 1)); name="$base-$n"; done
  tm_bg_session "$name" "$1" "$REPO"
  printf 'MODE=background\nTMUX_SESSION=%q\nTMUX_SOCKET=%q\n' "$name" "$TMUX_SOCKET"
}

# Our own pane, if this process runs inside the run's tmux server.
be_self_id() { if [[ -n "${TMUX:-}" ]]; then echo "${TMUX_PANE:-}"; fi; }

be_spawn() {
  local cwd="$1" cmd="$2" title="$3" id
  # `brig finish` or a reboot removes the background session; a resumed run starts it again.
  if [[ "$MODE" == background ]] && ! tm has-session -t "=$TMUX_SESSION" 2>/dev/null; then
    tm_bg_session "$TMUX_SESSION" "$RUN" "$cwd"
  fi
  id="$(tm new-window -d -P -F '#{pane_id}' -t "$TMUX_SESSION:" -c "$cwd" -n "$title" "bash $(q "$cmd")")" \
    || die "tmux: could not open a window in session $TMUX_SESSION"
  tm set-window-option -t "$id" automatic-rename off >/dev/null 2>&1 || true
  tm set-window-option -t "$id" allow-rename off >/dev/null 2>&1 || true
  echo "$id"
}

be_send_text() { tm send-keys -t "$1" -l -- "$2"; }
be_send_enter() { tm send-keys -t "$1" Enter; }
# Last N non-blank-trailing lines of the visible pane.
be_read() {
  tm capture-pane -p -t "$1" | awk '{ l[NR] = $0; if ($0 ~ /[^[:space:]]/) last = NR } END { for (i = 1; i <= last; i++) print l[i] }' | tail -n "${2:-40}"
}
be_close() { tm kill-pane -t "$1" >/dev/null 2>&1 || true; }
# Every pane on the server. No server means nothing is alive, which is an answer, not an error.
be_live_ids() {
  local out
  if out="$(tm list-panes -a -F '#{pane_id}' 2>&1)"; then printf '%s\n' "$out"; return 0; fi
  case "$out" in *"no server running"*|*"error connecting"*|*"No such file"*) return 0 ;; esac
  return 1
}
be_notify() {
  tm display-message -d 8000 "$1: $2" >/dev/null 2>&1 || true
  if [[ "$MODE" == background ]] && command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"${2//\"/}\" with title \"${1//\"/}\"" >/dev/null 2>&1 || true
  fi
}
be_status() { :; }
be_status_clear() { :; }
be_attach_cmd() {
  local s=""; [[ -n "${TMUX_SOCKET:-}" ]] && s="-L $TMUX_SOCKET "
  echo "tmux ${s}attach -t $TMUX_SESSION"
}
be_watch_hint() {
  if [[ "$MODE" == background ]]; then
    echo "Watch the workers: $(be_attach_cmd)   (switch windows: Ctrl-b n / Ctrl-b p · leave without stopping anything: Ctrl-b d)"
  else
    echo "Workers open as windows in this tmux session (pick one: Ctrl-b w)."
  fi
}
# At the end of a run: remove the background session brig created, once no worker is left in it.
be_finish() {
  [[ "$MODE" == background ]] || return 0
  [[ -z "$(live_workers)" ]] || { echo "tmux session $TMUX_SESSION left open: a worker is still in it ($(be_attach_cmd))"; return 0; }
  tm kill-session -t "=$TMUX_SESSION" >/dev/null 2>&1 || true
}
