# shellcheck shell=bash
# Shared helpers for the brig test suite. Plain bash, no test framework needed.
# Every invocation works in its own temp dir (/tmp/$BRIG_TEST_PREFIX-XXXXXX, default brig-test) and removes
# only what it created: the fake terminal processes it started and its own tmux server.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
SKILL_SRC="$ROOT_DIR/skills/brigadier"
PASS=0; FAIL=0
T_PREFIX="${BRIG_TEST_PREFIX:-brig-test}"
T_ROOT="$(mktemp -d "/tmp/$T_PREFIX-XXXXXX")"
T_ROOT="$(cd "$T_ROOT" && pwd -P)"
T_SOCKETS=()

cleanup() {
  local sd s
  if [[ -d "$T_ROOT/term/s" ]]; then
    for sd in "$T_ROOT"/term/s/*; do
      [[ -s "$sd/pid" ]] && kill "$(cat "$sd/pid")" 2>/dev/null
    done
  fi
  for s in ${T_SOCKETS[@]+"${T_SOCKETS[@]}"}; do tmux -L "$s" kill-server >/dev/null 2>&1; done
  # Watch loops and successors started inside fake terminals exit with their surfaces; give them a moment.
  sleep 0.3
  rm -rf "$T_ROOT"
}
trap cleanup EXIT

ok() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$*"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$*"; }
check() { local msg="$1"; shift; if "$@"; then ok "$msg"; else bad "$msg"; fi; }
has() { grep -qF -- "$2" <<<"$1"; }
expect_has() { if has "$2" "$3"; then ok "$1"; else bad "$1 (missing: $3)"; printf '%s\n' "$2" | sed 's/^/        | /' | tail -25; fi; }
expect_not() { if has "$2" "$3"; then bad "$1 (unexpected: $3)"; else ok "$1"; fi; }
summary() {
  echo "  -- $PASS passed, $FAIL failed"
  (( FAIL == 0 ))
}
# wait_for <seconds> <command...>: poll until the command succeeds.
wait_for() {
  local n=$(( $1 * 10 )); shift
  while (( n-- > 0 )); do "$@" && return 0; sleep 0.1; done
  return 1
}

# A clean environment for one scenario: own state dir, own repo, fakes on PATH.
# new_env <backend: cmux|wmux|tmux-bg|tmux-attached|tmux-real-bg|tmux-real-attached>
new_env() {
  local kind="$1"
  E_DIR="$T_ROOT/env$((++ENV_N))"
  mkdir -p "$E_DIR/home" "$E_DIR/repo"
  unset CMUX_WORKSPACE_ID CMUX_SURFACE_ID TMUX TMUX_PANE CLAUDE_CODE_SESSION_ID BRIGADIER_SESSION
  unset WMUX WMUX_SURFACE_ID WMUX_PIPE WMUX_PTY_ID CLAUDE_CODE_GIT_BASH_PATH
  unset BRIG_RUN BRIG_WORKER BRIG_WORKER_DIR CLAUDECODE
  local k; for k in $(env | sed -n 's/^\(BRIG_[A-Z_]*\)=.*/\1/p'); do unset "$k"; done
  export CLAUDE_CONFIG_DIR="$E_DIR/home"
  export BRIG_HOME="$E_DIR/home/brigadier"
  export BRIG_POLL=1 FAKE_LOG="$E_DIR/fake.log" FAKE_TERM_DIR="$T_ROOT/term"
  export FAKE_BRIG="$SKILL/scripts/brig"
  mkdir -p "$BRIG_HOME/fake-modes"
  case "$kind" in
    cmux) export PATH="$TESTS_DIR/fakes/term:$TESTS_DIR/fakes/bin:$BASE_PATH"
          export CMUX_WORKSPACE_ID="ws-test" CMUX_SURFACE_ID="self-$ENV_N" ;;
    wmux) export PATH="$TESTS_DIR/fakes/term:$TESTS_DIR/fakes/bin:$BASE_PATH"
          export WMUX=1 WMUX_SURFACE_ID="surf-self-$ENV_N" ;;
    tmux-bg) export PATH="$TESTS_DIR/fakes/term:$TESTS_DIR/fakes/bin:$BASE_PATH" ;;
    tmux-attached) export PATH="$TESTS_DIR/fakes/term:$TESTS_DIR/fakes/bin:$BASE_PATH"
          export TMUX="/tmp/$T_PREFIX-fake-sock,999,0" TMUX_PANE="%9$ENV_N" ;;
    tmux-real-*) export PATH="$TESTS_DIR/fakes/bin:$BASE_PATH" ;;
  esac
  git -C "$E_DIR/repo" init -q -b main
  git -C "$E_DIR/repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m "first"
  echo "hello" >"$E_DIR/repo/a.txt"
  git -C "$E_DIR/repo" add a.txt
  git -C "$E_DIR/repo" -c user.name=t -c user.email=t@example.invalid commit -q -m "second"
  cd "$E_DIR/repo" || exit 1
  printf 'Do the thing.\n' >"$E_DIR/task.md"
}
ENV_N=0
BASE_PATH="$PATH"
SKILL="$SKILL_SRC"
brig() { bash "$SKILL/scripts/brig" "$@"; }
fake_mode() { echo "$2" >"$BRIG_HOME/fake-modes/$1"; }
run_id_of() { sed -n 's/^BRIG_RUN=//p' <<<"$1"; }
surface_of() { cat "$BRIG_HOME/runs/$RID/workers/$1/surface"; }
