#!/usr/bin/env bash
# Real tmux, fake Claude: background mode (brigadier in a plain terminal) and attached mode
# (brigadier inside tmux). Uses a private tmux server per invocation, so your own tmux
# sessions are never touched.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v tmux >/dev/null 2>&1 || { echo "smoke_tmux: tmux not installed, skipping"; exit 0; }
SOCK="$T_PREFIX-smoke-$$"; T_SOCKETS+=("$SOCK")

flow() { # flow <label> <session>: spawn, wait for done, read screen, kill
  local label="$1" sess="$2" out sid
  fake_mode w01 "done"
  out="$(brig spawn w01 "$E_DIR/task.md" --title smoke 2>&1)"
  expect_has "$label: spawn" "$out" "spawned w01"
  out="$(brig wait 40 2>&1)"
  expect_has "$label: wait sees TURN_END done" "$out" "TURN_END w01 status=done"
  sid="$(surface_of w01)"
  check "$label: worker is a real tmux pane" bash -c "tmux $TM list-panes -a -F '#{pane_id}' | grep -qxF '$sid'"
  expect_has "$label: worker runs in session $sess" "$(tmux -L "$SOCK" display-message -p -t "$sid" '#{session_name}')" "$sess"
  check "$label: screen is readable" wait_for 10 bash -c "bash '$SKILL/scripts/brig' screen w01 | grep -q 'finished w01'"
  brig kill w01 >/dev/null
  check "$label: kill closes the pane" wait_for 10 bash -c "! tmux $TM list-panes -a -F '#{pane_id}' | grep -qxF '$sid'"
}

echo "== real tmux, background mode"
new_env tmux-real-bg
export BRIG_TMUX_SOCKET="$SOCK"; TM="-L $SOCK"
out="$(brig init smoke 2>&1)"; RID="$(run_id_of "$out")"; export BRIG_RUN="$RID"
expect_has "background mode chosen from a plain terminal" "$(cat "$BRIG_HOME/runs/$RID/run.env")" "MODE=background"
expect_has "init says how to watch" "$out" "tmux -L $SOCK attach -t brigadier-smoke"
check "detached session exists" tmux -L "$SOCK" has-session -t "=brigadier-smoke"
check "window 0 shows the status table" wait_for 10 bash -c "tmux -L '$SOCK' capture-pane -p -t '=brigadier-smoke:status' | grep -q 'Brigadier ·'"
flow background brigadier-smoke
out="$(brig finish "smoke done" 2>&1)"
check "finish removes the background session" bash -c "! tmux -L '$SOCK' has-session -t '=brigadier-smoke' 2>/dev/null"
unset BRIG_RUN BRIG_TMUX_SOCKET

echo "== real tmux, attached mode"
new_env tmux-real-attached
tmux -L "$SOCK" new-session -d -s outer -x 200 -y 50
TMUX="$(tmux -L "$SOCK" display-message -p -t outer '#{socket_path},#{pid},0')"; export TMUX
TMUX_PANE="$(tmux -L "$SOCK" display-message -p -t outer '#{pane_id}')"; export TMUX_PANE
TM="-L $SOCK"
out="$(brig init smoke2 2>&1)"; RID="$(run_id_of "$out")"; export BRIG_RUN="$RID"
expect_has "attached mode chosen inside tmux" "$(cat "$BRIG_HOME/runs/$RID/run.env")" "MODE=attached"
flow attached outer
brig finish "smoke done" >/dev/null
unset BRIG_RUN TMUX TMUX_PANE

summary
