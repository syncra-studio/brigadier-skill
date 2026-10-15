#!/usr/bin/env bash
# Run every check: shellcheck, the fake-terminal suites, and the real-tmux smoke test.
# usage: bash tests/run.sh [--no-smoke] [--no-lint]
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
smoke=1 lint=1
for a in "$@"; do
  case "$a" in
    --no-smoke) smoke="" ;;
    --no-lint) lint="" ;;
    *) echo "usage: bash tests/run.sh [--no-smoke] [--no-lint]" >&2; exit 2 ;;
  esac
done

status=0
step() { echo; echo "### $*"; }

if [[ -n "$lint" ]]; then
  step shellcheck
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -x skills/brigadier/scripts/brig skills/brigadier/scripts/codex-worker skills/brigadier/scripts/backends/*.sh \
      tests/*.sh tests/fakes/bin/claude tests/fakes/bin/codex tests/fakes/term/cmux tests/fakes/term/tmux tests/fakes/term/wmux tests/fakes/term/powershell.exe tests/fakes/term/fakepwsh tests/fakes/term/faketerm.sh tests/fakes/win/* tests/fakes/os/* \
      && echo "  ok    shellcheck clean" || status=1
  else
    echo "  FAIL  shellcheck not installed"; status=1
  fi
fi

step "unit (policy, config, runs, rebirth, reviews, codex, doctor, install copy)"
bash tests/test_unit.sh || status=1
step "setup on macOS, Linux and Windows (fake package managers)"
bash tests/test_setup.sh || status=1
step "worker lifecycle on every backend (fake cmux, fake wmux, fake openwong2kim wmux, fake tmux background, fake tmux attached)"
bash tests/test_backends.sh || status=1
if [[ -n "$smoke" ]]; then
  step "real tmux smoke"
  bash tests/smoke_tmux.sh || status=1
fi

echo
if (( status == 0 )); then echo "ALL PASSED"; else echo "SOME CHECKS FAILED"; fi
exit "$status"
