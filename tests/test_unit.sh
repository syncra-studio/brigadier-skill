#!/usr/bin/env bash
# Policy, config, run binding, rebirth, reviews, Codex workers and doctor, on the fake cmux
# (and the fake tmux where the terminal matters).
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "== Brigadier app guard"
new_env cmux
out="$(BRIGADIER_SESSION=1 brig status 2>&1)"; code=$?
expect_has "refuses inside the Brigadier app" "$out" "Brigadier skill doesn't run inside the Brigadier app. Use the app's Overnight mode there."
check "with exit code 3" test "$code" -eq 3
out="$(BRIGADIER_SESSION=1 brig doctor 2>&1)"
expect_has "doctor is guarded too" "$out" "doesn't run inside the Brigadier app"
out="$(BRIGADIER_SESSION=1 brig init x 2>&1)"
expect_has "init is guarded too" "$out" "doesn't run inside the Brigadier app"
check "help still works" bash -c "BRIGADIER_SESSION=1 bash '$SKILL/scripts/brig' help >/dev/null"
expect_has "version still works" "$(BRIGADIER_SESSION=1 brig version)" "brig 0.1.0"

echo "== model and effort policy"
new_env cmux
RID="$(run_id_of "$(brig init policy)")"; export BRIG_RUN="$RID"; R="$BRIG_HOME/runs/$RID"
out="$(BRIG_ALLOWED_MODELS="opus sonnet" brig spawn w01 "$E_DIR/task.md" --model haiku 2>&1)"
expect_has "refuses a model outside the allowlist" "$out" "model 'haiku' is not in BRIG_ALLOWED_MODELS"
out="$(brig spawn w01 "$E_DIR/task.md" --effort max 2>&1)"
expect_has "refuses effort above the ceiling" "$out" "effort 'max' is above BRIG_MAX_EFFORT=high"
out="$(brig spawn w01 "$E_DIR/task.md" --effort extreme 2>&1)"
expect_has "refuses an unknown effort" "$out" "unknown effort 'extreme'"
out="$(BRIG_ALLOWED_MODELS="opus sonnet" brig spawn w01 "$E_DIR/task.md" --model sonnet --effort medium 2>&1)"
expect_has "spawns an allowed model" "$out" "spawned w01 [claude sonnet effort=medium]"
expect_has "worker settings carry the allowlist" "$(jq -c .availableModels "$R/workers/w01/settings.json")" '["opus","sonnet"]'
expect_has "protocol names the allowed models" "$(cat "$R/workers/w01/task.md")" "only these models: opus sonnet"
out="$(BRIG_MAX_EFFORT=max brig spawn w02 "$E_DIR/task.md" --effort max 2>&1)"
expect_has "a raised ceiling allows max" "$out" "spawned w02 [claude opus effort=max]"
expect_has "default settings allow any model" "$(jq -c '.availableModels // "unset"' "$R/workers/w02/settings.json")" '"unset"'
out="$(BRIG_MAX_WORKERS=2 brig spawn w03 "$E_DIR/task.md" 2>&1)"
expect_has "refuses past BRIG_MAX_WORKERS" "$out" "already 2 live workers (BRIG_MAX_WORKERS=2)"
out="$(brig spawn w01 "$E_DIR/task.md" 2>&1)"
expect_has "never reuses a worker id" "$out" "worker w01 already exists"
out="$(BRIG_PERMISSION_MODE=yolo brig spawn w04 "$E_DIR/task.md" 2>&1)"
expect_has "refuses an unknown permission mode" "$out" "BRIG_PERMISSION_MODE 'yolo'"
out="$(BRIG_PERMISSION_MODE=acceptEdits brig spawn w05 "$E_DIR/task.md" 2>&1)"
expect_has "stricter permission mode reaches the worker" "$(cat "$R/workers/w05/launch.sh")" "--permission-mode acceptEdits"
expect_has "and drops the bypass dialog skip" "$(jq -c .skipDangerousModePermissionPrompt "$R/workers/w05/settings.json")" "false"
for w in w01 w02 w05; do brig kill "$w" >/dev/null 2>&1; done
unset BRIG_RUN

echo "== config precedence"
new_env cmux
RID="$(run_id_of "$(brig init cfg)")"; R="$BRIG_HOME/runs/$RID"
echo "BRIG_CTX_PCT=50" >"$BRIG_HOME/config.env"
out="$(BRIG_RUN=$RID brig config)"
expect_has "user config applies" "$out" "BRIG_CTX_PCT           50                       user"
echo "BRIG_CTX_PCT=60" >"$R/config.env"
out="$(BRIG_RUN=$RID brig config)"
expect_has "run config beats user config" "$out" "BRIG_CTX_PCT           60                       run"
out="$(BRIG_RUN=$RID BRIG_CTX_PCT=65 brig config)"
expect_has "environment beats both" "$out" "BRIG_CTX_PCT           65                       env"
expect_has "defaults are listed" "$out" "BRIG_DEFAULT_MODEL     opus                     default"

echo "== two runs at once"
new_env cmux
a="$(CMUX_SURFACE_ID=tab-a brig init alpha)"; A="$(run_id_of "$a")"
b="$(CMUX_SURFACE_ID=tab-b brig init beta)"; B="$(run_id_of "$b")"
expect_has "tab a is bound to its run" "$(CMUX_SURFACE_ID=tab-a brig run)" "$A"
expect_has "tab b is bound to its run" "$(CMUX_SURFACE_ID=tab-b brig run)" "$B"
out="$(env -u CMUX_SURFACE_ID bash "$SKILL/scripts/brig" run 2>&1)"
expect_has "an unbound session is refused, not guessed" "$out" "several runs are active"
expect_has "BRIG_RUN picks explicitly" "$(env -u CMUX_SURFACE_ID BRIG_RUN="$A" bash "$SKILL/scripts/brig" run)" "$A"
brig use "$A" >/dev/null
expect_has "use binds a session" "$(brig run)" "$A"
new_env tmux-bg
a="$(CLAUDE_CODE_SESSION_ID=sess-a brig init alpha)"; A="$(run_id_of "$a")"
b="$(CLAUDE_CODE_SESSION_ID=sess-b brig init beta)"; B="$(run_id_of "$b")"
expect_has "plain-terminal session a keeps its run" "$(CLAUDE_CODE_SESSION_ID=sess-a brig run)" "$A"
expect_has "plain-terminal session b keeps its run" "$(CLAUDE_CODE_SESSION_ID=sess-b brig run)" "$B"
check "each background run has its own session" test -d "$FAKE_TERM_DIR/sessions/brigadier-alpha" -a -d "$FAKE_TERM_DIR/sessions/brigadier-beta"
fake_mode w01 "done"
BRIG_RUN="$A" brig spawn w01 "$E_DIR/task.md" >/dev/null
BRIG_RUN="$B" brig spawn w01 "$E_DIR/task.md" >/dev/null
expect_has "run a's worker sees its own run" "$(cat "$BRIG_HOME/runs/$A/workers/w01/launch.sh")" "BRIG_RUN=$BRIG_HOME/runs/$A"
out="$(BRIG_RUN="$A" brig wait 20)"; expect_has "run a waits on its own worker" "$out" "TURN_END w01 status=done"
out="$(BRIG_RUN="$B" brig wait 20)"; expect_has "run b waits on its own worker" "$out" "TURN_END w01 status=done"
BRIG_RUN="$A" brig finish a >/dev/null; BRIG_RUN="$B" brig finish b >/dev/null

echo "== rebirth"
new_env cmux
RID="$(run_id_of "$(brig init --slash /brigadier-skill:brigadier reborn)")"; export BRIG_RUN="$RID"; R="$BRIG_HOME/runs/$RID"
fake_mode successor ack
out="$(BRIG_REBIRTH_TIMEOUT=20 brig rebirth 2>&1)"; code=$?
expect_has "successor confirms" "$out" "REBIRTH_OK"
check "rebirth exits 0" test "$code" -eq 0
expect_has "successor is invoked with the recorded command" "$(cat "$R/rebirth.sh")" "/brigadier-skill:brigadier\\ resume\\ $RID"
check "ack recorded" test -f "$R/rebirth.ack"
check "old tab closes itself after the ack" wait_for 10 grep -q "close-surface --force --surface $CMUX_SURFACE_ID" "$FAKE_TERM_DIR/log"
brig kill successor >/dev/null
fake_mode successor noack
out="$(BRIG_REBIRTH_TIMEOUT=4 brig rebirth 2>&1)"; code=$?
expect_has "a silent successor times out" "$out" "REBIRTH_TIMEOUT"
check "and rebirth fails" test "$code" -ne 0
check "the old brigadier stays (no close of its own tab)" test "$(grep -c "close-surface --force --surface $CMUX_SURFACE_ID" "$FAKE_TERM_DIR/log")" -eq 1
expect_has "the successor can be inspected" "$(brig screen successor)" "fake brigadier resuming"
brig kill successor >/dev/null
unset BRIG_RUN
new_env tmux-bg
export CLAUDE_CODE_SESSION_ID=plain-1
RID="$(run_id_of "$(brig init bgreborn)")"; export BRIG_RUN="$RID"
fake_mode successor ack
out="$(BRIG_REBIRTH_TIMEOUT=20 brig rebirth 2>&1)"
expect_has "background rebirth confirms" "$out" "REBIRTH_OK"
expect_has "and tells the user where it went" "$out" "tmux attach -t brigadier-bgreborn"
brig kill successor >/dev/null; brig finish "done" >/dev/null
unset BRIG_RUN CLAUDE_CODE_SESSION_ID

echo "== reviews"
new_env cmux
out="$(brig review plan "$E_DIR/task.md" --out "$E_DIR/r1.md" 2>&1)"
expect_has "plan review uses codex when installed" "$out" "FAKE CODEX PLAN REVIEW"
expect_has "read-only, effort from config" "$(cat "$FAKE_LOG")" "-s read-only -c model_reasoning_effort=\"high\""
out="$(brig review code --base HEAD~1 --out "$E_DIR/r2.md" 2>&1)"
expect_has "code review uses codex exec review" "$out" "FAKE CODEX REVIEW"
out="$(BRIG_CODEX=off brig review plan "$E_DIR/task.md" --out "$E_DIR/r3.md" 2>&1)"
expect_has "without codex, Claude reviews" "$out" "FAKE CLAUDE REVIEW"
expect_has "read-only Claude" "$(tail -1 "$FAKE_LOG")" "claude -p model=opus effort=high perm=dontAsk"
out="$(brig review plan "$E_DIR/task.md" --effort max 2>&1)"
expect_has "review effort obeys the ceiling" "$out" "above BRIG_MAX_EFFORT"
out="$(brig review code --base HEAD 2>&1)"
expect_has "an empty change set fails loudly" "$out" "no changes between HEAD and HEAD"

mkdir -p "$E_DIR/elsewhere"; out="$(cd "$E_DIR/elsewhere" && cp "$E_DIR/task.md" plan.md && brig review plan plan.md --repo "$E_DIR/repo" --out r4.md 2>&1)"
expect_has "relative paths with --repo: the plan is found" "$(cat "$FAKE_LOG")" "$E_DIR/elsewhere/plan.md"
check "relative paths with --repo: the review lands in the caller's dir" test -s "$E_DIR/elsewhere/r4.md"

echo "== cmux input and paths with spaces"
new_env cmux
export BRIG_HOME="$E_DIR/home dir/brigadier"; mkdir -p "$BRIG_HOME/fake-modes"
RID="$(run_id_of "$(brig init spaced)")"; export BRIG_RUN="$RID"
fake_mode w01 ask
brig spawn w01 "$E_DIR/task.md" >/dev/null
out="$(brig wait 30)"; expect_has "a worker starts from a state dir with a space" "$out" "TURN_END w01 status=working"
sid="$(surface_of w01)"
sleep 1; brig send w01 'use \n literally' >/dev/null
expect_has "text with a backslash is pasted, not typed" "$(cat "$FAKE_TERM_DIR/log")" "cmux send --paste --force --surface $sid -- use \\n literally"
brig send w01 "1" >/dev/null
expect_has "plain text is typed, even into an open dialog" "$(cat "$FAKE_TERM_DIR/log")" "cmux send --force --surface $sid -- 1"
expect_has "Enter reaches an open dialog too" "$(cat "$FAKE_TERM_DIR/log")" "cmux send-key --force --surface $sid enter"
brig kill w01 >/dev/null; brig finish "done" >/dev/null
unset BRIG_RUN

echo "== resuming a finished background run"
new_env tmux-bg
RID="$(run_id_of "$(brig init again)")"; export BRIG_RUN="$RID"
brig finish "first night" >/dev/null
check "finish removed the background session" test ! -d "$FAKE_TERM_DIR/sessions/brigadier-again"
brig use "$RID" >/dev/null
out="$(brig spawn w01 "$E_DIR/task.md" 2>&1)"; expect_has "spawn works after resume" "$out" "spawned w01"
check "the background session is back" test -d "$FAKE_TERM_DIR/sessions/brigadier-again"
check "the run is active again" test ! -f "$BRIG_HOME/runs/$RID/finished"
out="$(brig wait 30)"; expect_has "and its worker reports in" "$out" "TURN_END w01 status=done"
brig finish "done" >/dev/null
unset BRIG_RUN

echo "== codex workers"
new_env cmux
RID="$(run_id_of "$(brig init cx)")"; export BRIG_RUN="$RID"; R="$BRIG_HOME/runs/$RID"
out="$(brig spawn c01 "$E_DIR/task.md" --agent codex 2>&1)"
expect_has "codex worker spawns" "$out" "spawned c01 [codex effort=high]"
out="$(brig wait 30)"; expect_has "codex worker finishes" "$out" "TURN_END c01 status=done"
sleep 1; brig send c01 "one more thing" >/dev/null
out="$(brig wait 30)"; expect_has "queued message becomes a resumed turn" "$out" "ack: one more thing"
first="$(grep -m1 '^codex exec ' "$FAKE_LOG")"; resumed="$(grep -m1 '^codex exec resume' "$FAKE_LOG")"
expect_has "bypass mode, first turn" "$first" "--dangerously-bypass-approvals-and-sandbox"
expect_has "bypass mode, resumed turn" "$resumed" "--dangerously-bypass-approvals-and-sandbox"
brig kill c01 >/dev/null
: >"$FAKE_LOG"
out="$(BRIG_PERMISSION_MODE=acceptEdits brig spawn c02 "$E_DIR/task.md" --agent codex 2>&1)"
out="$(brig wait 30)"; expect_has "sandboxed codex worker finishes" "$out" "TURN_END c02 status=done"
sleep 1; brig send c02 "again" >/dev/null
out="$(brig wait 30)"; expect_has "sandboxed codex worker resumes" "$out" "ack: again"
first="$(grep -m1 '^codex exec ' "$FAKE_LOG")"; resumed="$(grep -m1 '^codex exec resume' "$FAKE_LOG")"
for t in first resumed; do
  v="${!t}"
  expect_has "sandbox mode on the $t turn" "$v" "sandbox_mode=\"workspace-write\""
  expect_has "no prompts on the $t turn" "$v" "approval_policy=\"never\""
  expect_has "control dir writable on the $t turn" "$v" "sandbox_workspace_write.writable_roots=[\"$R/workers/c02\"]"
  expect_not "no --full-auto on the $t turn" "$v" "--full-auto"
done
brig kill c02 >/dev/null
out="$(BRIG_CODEX=off brig spawn c03 "$E_DIR/task.md" --agent codex 2>&1)"
expect_has "codex workers need codex" "$out" "Codex workers need the 'codex' CLI"
unset BRIG_RUN

echo "== bindings are plain files"
new_env cmux
a="$(CMUX_SURFACE_ID=tab-a brig init alpha)"; A="$(run_id_of "$a")"
check "a binding is a file, not a symlink" test -f "$BRIG_HOME/bindings/cmux-tab-a" -a ! -L "$BRIG_HOME/bindings/cmux-tab-a"
ln -s "$BRIG_HOME/runs/$A" "$BRIG_HOME/bindings/cmux-legacy"
expect_has "a symlink binding from an older version still resolves" "$(CMUX_SURFACE_ID=legacy brig run)" "$A"
CMUX_SURFACE_ID=legacy brig use "$A" >/dev/null
check "and is rewritten as a file on the next use" test -f "$BRIG_HOME/bindings/cmux-legacy" -a ! -L "$BRIG_HOME/bindings/cmux-legacy"
expect_has "the rewritten binding resolves" "$(CMUX_SURFACE_ID=legacy brig run)" "$A"

echo "== files written on Windows"
new_env cmux
RID="$(run_id_of "$(brig init crlf)")"; export BRIG_RUN="$RID"; R="$BRIG_HOME/runs/$RID"
printf 'BRIG_CTX_PCT=55\r\nBRIG_MAX_WORKERS=2\r\n' >"$BRIG_HOME/config.env"
out="$(brig config)"
expect_has "a CRLF config file loads" "$out" "BRIG_CTX_PCT           55                       user"
expect_has "without a stray carriage return" "$out" "BRIG_MAX_WORKERS       2                        user"
expect_has "doctor accepts it" "$(brig doctor 2>&1)" "ok    config $BRIG_HOME/config.env"
rm -f "$BRIG_HOME/config.env"
brig spawn w01 "$E_DIR/task.md" >/dev/null 2>&1; brig wait 30 >/dev/null
printf '\377\376d\000o\000n\000e\000\r\000\n\000' >"$R/workers/w01/status"
expect_has "a UTF-16 status file from PowerShell reads as its word" "$(brig status)" "w01   live    done"
brig kill w01 >/dev/null; unset BRIG_RUN

echo "== Windows (Git Bash, simulated)"
new_env cmux
export PATH="$TESTS_DIR/fakes/win:$PATH" FAKE_WIN_ROOT="$T_ROOT"
RID="$(run_id_of "$(brig init win)")"; export BRIG_RUN="$RID"; R="$BRIG_HOME/runs/$RID"
win="C:/fake${R#"$T_ROOT"}"
brig spawn w01 "$E_DIR/task.md" >/dev/null 2>&1
L="$(cat "$R/workers/w01/launch.sh")"
expect_has "the kickoff names task.md as a Windows path" "$L" "Read\\ $win/workers/w01/task.md"
expect_has "--settings gets a Windows path" "$L" "--settings $win/workers/w01/settings.json"
expect_has "the worker gets the brigadier's PATH" "$L" "export PATH="
expect_has "the protocol shows Windows paths" "$(cat "$R/workers/w01/task.md")" "Your private directory: \`$win/workers/w01\`"
expect_has "hooks keep the bash path" "$(jq -r '.hooks.Stop[0].hooks[0].command' "$R/workers/w01/settings.json")" "bash $SKILL/scripts/brig _hook stop $R/workers/w01"
brig kill w01 >/dev/null
out="$(env -u BRIG_HOME CLAUDE_CONFIG_DIR='C:\fake\cfg' bash "$SKILL/scripts/brig" config 2>&1)"
expect_has "a Windows-style CLAUDE_CONFIG_DIR is read as a bash path" "$out" "user config: $T_ROOT/cfg/brigadier/config.env"
unset BRIG_RUN FAKE_WIN_ROOT; export PATH="${PATH#"$TESTS_DIR/fakes/win:"}"

echo "== doctor"
new_env cmux
out="$(brig doctor 2>&1)"; code=$?
expect_has "doctor passes with everything present" "$out" "all good"
check "doctor exits 0" test "$code" -eq 0
expect_has "doctor names the backend" "$out" "terminal: cmux"
new_env tmux-bg
expect_has "doctor explains background mode" "$(brig doctor 2>&1)" "background mode"
# A PATH with the basics but no cmux and no tmux.
nb="$T_ROOT/notmux"; mkdir -p "$nb"
for c in bash jq git uname grep cut head tail mkdir sed tr date cat dirname basename find sort awk env stat ls rm mv ln wc mktemp; do
  p="$(command -v "$c")" && ln -sf "$p" "$nb/$c"
done
ln -sf "$TESTS_DIR/fakes/bin/claude" "$nb/claude"
unset CMUX_WORKSPACE_ID CMUX_SURFACE_ID
out="$(PATH="$nb" brig doctor 2>&1)"; code=$?
expect_has "doctor fails without a terminal backend" "$out" "FAIL  no terminal backend"
expect_has "and prints the install line" "$out" "Install it with:"
check "doctor exits non-zero" test "$code" -ne 0
out="$(PATH="$nb" brig init x 2>&1)"
expect_has "init stops with the same message" "$out" "neither is available"
out="$(BRIG_DEFAULT_EFFORT=max brig doctor 2>&1)"
expect_has "doctor checks the effort settings" "$out" "BRIG_DEFAULT_EFFORT=max must be"

echo "== installed copy without exec bits"
new_env cmux
inst="$T_ROOT/install/.claude/skills/brigadier"; mkdir -p "$(dirname "$inst")"
cp -R "$SKILL_SRC" "$inst"
find "$inst" -type f -exec chmod a-x {} +
SKILL="$inst"; export FAKE_BRIG="$inst/scripts/brig"
expect_has "doctor runs from the copy" "$(brig doctor 2>&1)" "all good"
RID="$(run_id_of "$(brig init noexec)")"; export BRIG_RUN="$RID"
brig spawn w01 "$E_DIR/task.md" >/dev/null 2>&1
out="$(brig wait 30)"; expect_has "a worker runs with hooks from the copy" "$out" "TURN_END w01 status=done"
brig spawn c01 "$E_DIR/task.md" --agent codex >/dev/null 2>&1
out="$(brig wait 30)"; expect_has "codex-worker runs from the copy" "$out" "TURN_END c01 status=done"
brig kill w01 >/dev/null; brig kill c01 >/dev/null
SKILL="$SKILL_SRC"; unset BRIG_RUN

summary
