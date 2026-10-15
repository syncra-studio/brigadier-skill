# shellcheck shell=bash
# A tiny fake terminal multiplexer shared by the fake `cmux` and `tmux`.
# Each surface is a background process whose stdin is a FIFO (what gets "typed")
# and whose output goes to a screen file. State lives in $FAKE_TERM_DIR.
set -euo pipefail
: "${FAKE_TERM_DIR:?FAKE_TERM_DIR must be set by the test}"
mkdir -p "$FAKE_TERM_DIR/s"

ft_log() { printf '%s\n' "$*" >>"$FAKE_TERM_DIR/log"; }
ft_next() {
  local n; n=$(( $(cat "$FAKE_TERM_DIR/seq" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$FAKE_TERM_DIR/seq"; echo "$n"
}
ft_dir() { printf '%s/s/%s' "$FAKE_TERM_DIR" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9_-' '_')"; }

# ft_spawn <id> <cwd> <shell-command> [group]
ft_spawn() {
  local id="$1" cwd="$2" cmd="$3" group="${4:-}" sd; sd="$(ft_dir "$id")"
  mkdir -p "$sd"; mkfifo "$sd/in"; : >"$sd/screen"; : >"$sd/pending"
  printf '%s\n' "$id" >"$sd/id"; printf '%s\n' "$group" >"$sd/group"
  # The runner keeps the FIFO open read-write so writers never block, runs the command
  # with the FIFO as stdin, and records the command's PID so it can be closed later.
  # shellcheck disable=SC2016 # the inner script expands its own positional parameters
  nohup bash -c '
    sd="$1"; cd "$2" || exit 1
    exec 3<>"$sd/in"
    bash -c "$3" <&3 >"$sd/screen" 2>&1 &
    echo $! >"$sd/pid"
    wait $! 2>/dev/null
    touch "$sd/exited"
  ' _ "$sd" "$cwd" "$cmd" >/dev/null 2>&1 &
  local _; for _ in $(seq 1 50); do [[ -s "$sd/pid" ]] && break; sleep 0.05; done
}
ft_alive() {
  local sd; sd="$(ft_dir "$1")"
  [[ -s "$sd/pid" && ! -e "$sd/exited" && ! -e "$sd/closed" ]] && kill -0 "$(cat "$sd/pid")" 2>/dev/null
}
ft_ids() {
  local sd
  for sd in "$FAKE_TERM_DIR"/s/*; do
    [[ -d "$sd" ]] || continue
    if ft_alive "$(cat "$sd/id")"; then cat "$sd/id"; fi
  done
}
ft_type() { local sd; sd="$(ft_dir "$1")"; ft_alive "$1" || return 1; printf '%s' "$2" >>"$sd/pending"; }
ft_enter() {
  local sd; sd="$(ft_dir "$1")"; ft_alive "$1" || return 1
  echo enter >>"$sd/keys"
  { cat "$sd/pending"; printf '\n'; } >"$sd/in"; : >"$sd/pending"
}
# ft_key <id> <name>: any other key. It is recorded, and reaches the program as a <key:NAME> token
# on the line the next Enter sends (the fake claude reads its dialogs that way).
ft_key() {
  local sd; sd="$(ft_dir "$1")"; ft_alive "$1" || return 1
  echo "$2" >>"$sd/keys"; printf '<key:%s>' "$2" >>"$sd/pending"
  case "$2" in up|down) ft_move_cursor "$sd/screen" "$2" ;; esac
}
# ft_move_cursor <screen> <up|down>: a list on screen redraws its ❯ cursor one row up or down, as a
# dialog does. Rows look like " ❯ Option" and "   Option"; the screen keeps its length in bytes.
ft_move_cursor() {
  local t; t="$(mktemp "$1.XXXXXX")" || return 0
  awk -v dir="$2" '{ l[NR] = $0; if (index($0, "❯")) c = NR }
    END {
      t = (dir == "down") ? c + 1 : c - 1
      if (c && t >= 1 && t <= NR && l[t] ~ /^   [^ ]/) { sub(/❯/, " ", l[c]); sub(/^   /, " ❯ ", l[t]) }
      for (i = 1; i <= NR; i++) print l[i]
    }' "$1" >"$t" && cat "$t" >"$1"
  rm -f "$t"
}
ft_read() { local sd; sd="$(ft_dir "$1")"; [[ -d "$sd" ]] || return 1; tail -n "${2:-40}" "$sd/screen"; }
ft_close() {
  local sd; sd="$(ft_dir "$1")"; [[ -d "$sd" ]] || return 0
  touch "$sd/closed"
  if [[ -s "$sd/pid" ]]; then kill "$(cat "$sd/pid")" 2>/dev/null || true; fi
}
ft_group_ids() {
  local sd
  for sd in "$FAKE_TERM_DIR"/s/*; do
    [[ -d "$sd" && "$(cat "$sd/group")" == "$1" ]] && cat "$sd/id"
  done; true
}
