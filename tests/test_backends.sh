#!/usr/bin/env bash
# The full worker lifecycle against every terminal backend, through brig's backend interface.
# usage: bash tests/test_backends.sh [cmux] [wmux] [wmux-ow] [tmux-bg] [tmux-attached]   (default: all five)
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# The fake terminals share one state dir, so the fake cmux can list and close any surface.
# A wmux-ow id is <surface>@<pty>; the fake terminal knows the pty.
keys_of() { cat "$FAKE_TERM_DIR/s/$(printf '%s' "${1#*@}" | tr -c 'A-Za-z0-9_-' '_')/keys" 2>/dev/null; }
fake_gone() { ! bash "$TESTS_DIR/fakes/term/cmux" tree | grep -qF "\"${1#*@}\""; }

lifecycle() {
  local kind="$1" out
  echo "== lifecycle on $kind"
  new_env "$kind"
  out="$(brig init demo 2>&1)"; RID="$(run_id_of "$out")"
  expect_has "init prints BRIG_RUN" "$out" "BRIG_RUN="
  export BRIG_RUN="$RID"
  local R="$BRIG_HOME/runs/$RID"
  case "$kind" in
    cmux) expect_has "run.env records cmux" "$(cat "$R/run.env")" "BACKEND=cmux" ;;
    wmux)
      expect_has "run.env records wmux" "$(cat "$R/run.env")" "BACKEND=wmux"
      expect_has "run.env records the workspace from whoami" "$(cat "$R/run.env")" "WORKSPACE=ws-test"
      expect_has "and the Git Bash to start workers with" "$(cat "$R/run.env")" "WMUX_BASH=" ;;
    wmux-ow)
      expect_has "run.env records wmux-ow" "$(cat "$R/run.env")" "BACKEND=wmux-ow"
      expect_has "run.env records this tab's workspace" "$(cat "$R/run.env")" "WORKSPACE=ws-test"
      expect_has "and the pipe" "$(cat "$R/run.env")" "OW_PIPE=wmux-tester" ;;
    tmux-bg)
      expect_has "run.env records background tmux" "$(cat "$R/run.env")" "MODE=background"
      expect_has "init tells how to watch" "$out" "tmux attach -t brigadier-demo"
      check "background session created" test -d "$FAKE_TERM_DIR/sessions/brigadier-demo" ;;
    tmux-attached)
      expect_has "run.env records attached tmux" "$(cat "$R/run.env")" "MODE=attached"
      expect_has "attached run uses the session's socket" "$(cat "$R/run.env")" "TMUX_SOCKET_PATH=/tmp/$T_PREFIX-fake-sock" ;;
  esac

  # A worker that finishes on its own.
  out="$(brig spawn w01 "$E_DIR/task.md" --title "Phase 1 · lead" 2>&1)"
  expect_has "spawn w01" "$out" "spawned w01 [claude opus effort=high]"
  expect_has "launch uses the configured permission mode" "$(cat "$R/workers/w01/launch.sh")" "--permission-mode bypassPermissions"
  expect_has "hooks run through bash" "$(jq -r '.hooks.Stop[0].hooks[0].command' "$R/workers/w01/settings.json")" "bash "
  expect_has "protocol is rendered" "$(cat "$R/workers/w01/task.md")" "Brigadier worker session: w01"
  expect_not "no placeholders left" "$(cat "$R/workers/w01/task.md")" "{{"
  out="$(brig wait 30 2>&1)"
  expect_has "wait sees w01 finish" "$out" "TURN_END w01 status=done"
  check "w01 wrote its report" test -s "$R/workers/w01/report.md"
  out="$(brig kill w01 2>&1)"
  expect_has "kill w01" "$out" "closed w01"
  check "w01 terminal is gone" wait_for 5 fake_gone "$(surface_of w01)"
  expect_has "status shows w01 closed" "$(brig status)" "closed"

  # A worker that asks, gets an answer, then hands off to a successor.
  fake_mode w02 ask
  brig spawn w02 "$E_DIR/task.md" >/dev/null 2>&1
  out="$(brig wait 30 2>&1)"
  expect_has "wait sees w02's question" "$out" "TURN_END w02 status=working ctx=20% :: Question"
  expect_has "last shows the full question" "$(brig last w02)" "Recommendation: yes"
  sleep 1
  brig send w02 "Go ahead." >/dev/null
  out="$(brig wait 30 2>&1)"
  expect_has "w02 got the answer" "$out" "TURN_END w02 status=working ctx=20% :: ack: Go ahead."
  # Keys for a dialog: every backend presses them in order; digits and space may be typed.
  sleep 1
  out="$(brig key w02 Down 3 space enter 2>&1)"
  expect_has "key presses keys in order" "$out" "pressed in w02: down 3 space enter"
  out="$(brig wait 30 2>&1)"
  expect_has "the worker got the keys" "$out" "ack: <key:down>3"
  local k2; k2="$(keys_of "$(surface_of w02)")"
  expect_has "the terminal pressed down" "$k2" "down"
  check "and enter last" test "$(tail -1 <<<"$k2")" = enter
  out="$(brig key w02 down f5 2>&1)"
  expect_has "an unknown key is refused" "$out" "key 'f5' is not one brig presses"
  check "and nothing was pressed" test "$(keys_of "$(surface_of w02)")" = "$k2"
  expect_has "the press is logged" "$(cat "$R/events.log")" "key w02: down 3 space enter"
  sleep 1
  brig handoff w02 >/dev/null
  out="$(brig wait 30 2>&1)"
  expect_has "w02 hands off" "$out" "TURN_END w02 status=handoff"
  check "w02 wrote handoff.md" test -s "$R/workers/w02/handoff.md"
  out="$(BRIG_MAX_WORKERS=1 brig spawn w03 "$E_DIR/task.md" --continues w02 2>&1)"
  expect_has "successor spawns at the worker cap" "$out" "spawned w03"
  expect_has "successor reads the predecessor's handoff" "$(cat "$R/workers/w03/task.md")" "$R/workers/w02/handoff.md"
  out="$(brig wait 30 2>&1)"
  expect_has "w03 finishes" "$out" "TURN_END w03 status=done"
  brig kill w02 >/dev/null; brig kill w03 >/dev/null

  # Context running high, then a terminal that disappears.
  fake_mode w04 ctx
  brig spawn w04 "$E_DIR/task.md" >/dev/null 2>&1
  out="$(brig wait 30 2>&1)"
  if ! has "$out" "CTX_HIGH w04"; then out+="$(brig wait 10 2>&1)"; fi
  expect_has "wait raises CTX_HIGH" "$out" "CTX_HIGH w04 ctx=85%"
  local s4; s4="$(surface_of w04)"
  bash "$TESTS_DIR/fakes/term/cmux" close-surface --force --surface "${s4#*@}" >/dev/null 2>&1
  out="$(brig wait 30 2>&1)"
  expect_has "wait raises GONE" "$out" "GONE w04"

  out="$(brig wait 5 2>&1)"
  expect_has "no live workers" "$out" "NO_LIVE_WORKERS"
  out="$(brig finish "demo done" 2>&1)"
  expect_has "finish" "$out" "finished $RID"
  check "run marked finished" test -f "$R/finished"
  if [[ "$kind" == tmux-bg ]]; then check "background session removed" test ! -d "$FAKE_TERM_DIR/sessions/brigadier-demo"; fi
  unset BRIG_RUN
}

kinds=("$@"); (( ${#kinds[@]} )) || kinds=(cmux wmux wmux-ow tmux-bg tmux-attached)
for k in "${kinds[@]}"; do lifecycle "$k"; done
summary
