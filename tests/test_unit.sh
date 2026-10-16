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
expect_has "settings carry the effort it starts with" "$(jq -r .effortLevel "$R/workers/w01/settings.json")" "medium"
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
expect_has "a worker's own dir is a working directory" "$(jq -c .permissions.additionalDirectories "$R/workers/w05/settings.json")" "[\"$R/workers/w05\"]"
expect_has "it may read the run and edit only its own dir" "$(jq -c .permissions.allow "$R/workers/w05/settings.json")" "[\"Read(/$R/**)\",\"Edit(/$R/workers/w05/**)\"]"
expect_has "rules use the //absolute form" "$(jq -r '.permissions.allow[0]' "$R/workers/w05/settings.json")" "Read(//"
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
new_env tmux-attached
RID="$(run_id_of "$(brig init attreborn)")"; export BRIG_RUN="$RID"
fake_mode successor ack
out="$(BRIG_REBIRTH_TIMEOUT=20 brig rebirth 2>&1)"
expect_has "attached tmux rebirth confirms" "$out" "REBIRTH_OK: the new brigadier confirmed. Closing this tab in 5s."
check "and the old pane closes itself, on the run's tmux server" wait_for 10 grep -qF "tmux -S /tmp/$T_PREFIX-fake-sock kill-pane -t $TMUX_PANE" "$FAKE_TERM_DIR/log"
brig kill successor >/dev/null; brig finish "done" >/dev/null
unset BRIG_RUN

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
printf 'a long answer\n' >"$E_DIR/answer.md"
brig send w01 --file "$E_DIR/answer.md" >/dev/null
expect_has "send --file types a pointer to the file" "$(cat "$FAKE_TERM_DIR/log")" "-- Read $E_DIR/answer.md and proceed. It is the brigadier's message to you."
brig kill w01 >/dev/null; brig finish "done" >/dev/null
unset BRIG_RUN

echo "== wmux: quoting, input and rebirth"
new_env wmux
export BRIG_HOME="$E_DIR/it's here/brigadier"; mkdir -p "$BRIG_HOME/fake-modes"
RID="$(run_id_of "$(brig init wq)")"; export BRIG_RUN="$RID"; R="$BRIG_HOME/runs/$RID"
fake_mode w01 ask
brig spawn w01 "$E_DIR/task.md" --title "it's · lead" >/dev/null
out="$(brig wait 30)"; expect_has "a worker starts from a path with a quote and a space" "$out" "TURN_END w01 status=working"
sid="$(surface_of w01)"
L="$(cat "$FAKE_TERM_DIR/log")"
expect_has "the tab runs Git Bash on the script, PowerShell-quoted" "$L" "--cmd & '$BASH' '$E_DIR/it''s here/brigadier/runs/$RID/workers/w01/launch.sh'"
expect_has "then closes when the worker ends" "$L" "launch.sh'; exit"
expect_has "the quote is doubled for PowerShell" "$(grep -F 'agent spawn' "$FAKE_TERM_DIR/log" | tail -1)" "it''s here"
expect_has "the tab is opened in the run's workspace" "$L" "agent spawn --workspace ws-test --cwd $E_DIR/repo"
expect_has "and named after the worker" "$L" "wmux rename-surface $sid ⚙ w01 · it's · lead"
expect_has "then focus goes back to the brigadier's tab" "$L" "wmux focus-surface $WMUX_SURFACE_ID"
sleep 1; brig send w01 'use \n literally' >/dev/null
expect_has "text goes in literally, as one argument" "$(cat "$FAKE_TERM_DIR/log")" "wmux send --surface $sid use \\n literally"
out="$(brig wait 30)"; expect_has "and reaches the worker" "$out" "ack: use \\n literally"
expect_has "screen reads come back as text" "$(brig screen w01 5)" "ack: use \\n literally"
expect_has "status goes to the sidebar" "$(brig status >/dev/null; cat "$FAKE_TERM_DIR/log")" "wmux set-status --workspace ws-test --state running --text w01 idle"
brig kill w01 >/dev/null
fake_mode successor ack
out="$(BRIG_REBIRTH_TIMEOUT=20 brig rebirth 2>&1)"
expect_has "a wmux rebirth confirms" "$out" "REBIRTH_OK"
check "and the old tab closes itself after the ack" wait_for 10 grep -q "wmux close-surface $WMUX_SURFACE_ID" "$FAKE_TERM_DIR/log"
brig kill successor >/dev/null
brig finish "done" >/dev/null
expect_has "finish clears the sidebar status" "$(tail -3 "$FAKE_TERM_DIR/log")" "wmux set-status --workspace ws-test --state idle"
unset BRIG_RUN

echo "== wmux-ow (openwong2kim/wmux): pipe calls, focus and rebirth"
new_env wmux-ow
RID="$(run_id_of "$(brig init ow)")"; export BRIG_RUN="$RID"; R="$BRIG_HOME/runs/$RID"
fake_mode w01 ask
brig spawn w01 "$E_DIR/task.md" --title "lead" >/dev/null
out="$(brig wait 30)"; expect_has "a worker runs in an openwong2kim tab" "$out" "TURN_END w01 status=working"
sid="$(surface_of w01)"; L="$(cat "$FAKE_TERM_DIR/log")"
expect_has "the id pairs the surface and the pty" "$sid" "osurf-"
expect_has "the tab opens in this workspace and the repo, in PowerShell" "$L" "wmux-ow surface.new {\"workspaceId\":\"ws-test\",\"cwd\":\"$E_DIR/repo\",\"shell\":\"powershell.exe\"}"
expect_has "the command is typed into it" "$L" "wmux-ow input.send {\"ptyId\":\"${sid#*@}\",\"workspaceId\":\"ws-test\",\"text\":\"& '$BASH' '$R/workers/w01/launch.sh'; exit\"}"
expect_has "then Enter" "$L" "wmux-ow input.sendKey {\"ptyId\":\"${sid#*@}\""
expect_has "then focus goes back to the brigadier's tab" "$L" "wmux-ow surface.focus {\"id\":\"osurf-self-$WMUX_PTY_ID\"}"
sleep 1
# shellcheck disable=SC2016 # the $ is meant literally
brig send w01 'it'"'"'s "quoted" & $literal' >/dev/null
out="$(brig wait 30)"; expect_has "text reaches the worker unchanged" "$out" "ack: it's \"quoted\" & \$literal"
expect_has "screen reads come back as text" "$(brig screen w01 5)" "ack: it's"
out="$(brig key w01 escape 2>&1)"
expect_has "keys go through input.sendKey" "$(cat "$FAKE_TERM_DIR/log")" "wmux-ow input.sendKey {\"ptyId\":\"${sid#*@}\",\"workspaceId\":\"ws-test\",\"key\":\"escape\"}"
brig send w01 'show a permission dialog' >/dev/null; sleep 1
out="$(brig key w01 1 2>&1)"; code=$?
check "a key at a numbered approval prompt fails" test "$code" -ne 0
expect_has "with wmux's own reason, the method named once" "$out" "wmux: input.send: pane \"${sid#*@}\" is showing the agent's own permission dialog"
expect_not "not twice" "$out" "input.send: input.send:"
expect_has "and how many keys got through" "$out" "0 of 1 keys were pressed"
out="$(brig key w01 enter 2>&1)"
expect_has "a named key is refused the same way" "$out" "wmux: input.sendKey: pane"
out="$(brig key w01 escape 2>&1)"; code=$?
check "escape still gets through: the brigadier can deny" test "$code" -eq 0
brig kill w01 >/dev/null
check "kill closes the surface" grep -q "wmux-ow surface.close {\"id\":\"${sid%@*}\"}" "$FAKE_TERM_DIR/log"
fake_mode successor ack
out="$(BRIG_REBIRTH_TIMEOUT=20 brig rebirth 2>&1)"
expect_has "a wmux-ow rebirth confirms" "$out" "REBIRTH_OK"
check "and the old tab closes itself after the ack" wait_for 10 grep -q "wmux-ow surface.close {\"id\":\"osurf-self-$WMUX_PTY_ID\"}" "$FAKE_TERM_DIR/log"
brig kill successor >/dev/null
brig finish "done" >/dev/null
unset BRIG_RUN
rm -f "$USERPROFILE/.wmux-auth-token"
out="$(brig init badtoken 2>&1)"
expect_has "a pipe that refuses the token is explained" "$out" "openwong2kim/wmux's pipe (wmux-tester) didn't answer"
new_env wmux-ow
export FAKE_OW_HIDE_SELF=1 # the brigadier's own tab isn't in surface.list
RID="$(run_id_of "$(brig init noself)")"; export BRIG_RUN="$RID"
n0="$(wc -l <"$FAKE_TERM_DIR/log")"
out="$(brig spawn w01 "$E_DIR/task.md" 2>&1)"; code=$?
check "spawn works when the brigadier's own tab can't be found" test "$code" -eq 0
expect_not "and hands focus to no tab" "$(tail -n +"$((n0 + 1))" "$FAKE_TERM_DIR/log")" "surface.focus"
out="$(brig wait 30)"; expect_has "the worker reports in" "$out" "TURN_END w01 status=done"
brig kill w01 >/dev/null
fake_mode successor ack
out="$(BRIG_REBIRTH_TIMEOUT=20 brig rebirth 2>&1)"; code=$?
check "rebirth works too" test "$code" -eq 0
expect_has "and leaves this tab open for the user to close" "$out" "This session can stop here"
brig kill successor >/dev/null
brig finish "done" >/dev/null
unset BRIG_RUN FAKE_OW_HIDE_SELF

echo "== a worker at a permission dialog is not interrupted"
new_env cmux
RID="$(run_id_of "$(brig init dialog)")"; export BRIG_RUN="$RID"; R="$BRIG_HOME/runs/$RID"
fake_mode w01 ask
brig spawn w01 "$E_DIR/task.md" >/dev/null
out="$(brig wait 30)"; expect_has "the worker asks" "$out" "TURN_END w01 status=working"
sleep 1
brig send w01 'show a permission dialog' >/dev/null
out="$(BRIG_IDLE_SEC=1 brig wait 10)"
expect_has "the dialog raises NEEDS_INPUT" "$out" "NEEDS_INPUT w01: Claude needs your permission to use Bash"
check "and the hook notes when it asked" test -s "$R/workers/w01/needs_input.ts"
sleep 2
out="$(BRIG_IDLE_SEC=1 brig wait 3)"
expect_not "a quiet worker at the dialog is not INTERRUPTED" "$out" "INTERRUPTED"
expect_has "the wait just times out" "$out" "HEARTBEAT"
out="$(brig check)"
expect_has "check sees the dialog" "$out" "screen=dialog"
expect_has "and says it waits for an answer" "$out" "NEEDS_INPUT: a dialog is waiting for an answer (brig screen w01)"
rm -f "$R/workers/w01/needs_input.ts"
out="$(BRIG_IDLE_SEC=1 brig wait 3)"
expect_not "the dialog on screen alone is enough" "$out" "INTERRUPTED"
brig send w01 'simulate an interrupt' >/dev/null; sleep 1
date +%s >"$R/workers/w01/needs_input.ts"
out="$(BRIG_IDLE_SEC=8 brig wait 3)"
expect_not "a recent request for input holds INTERRUPTED back" "$out" "INTERRUPTED"
rm -f "$R/workers/w01/needs_input.ts"
out="$(BRIG_IDLE_SEC=1 brig wait 15)"
expect_has "a cut-off turn still raises INTERRUPTED" "$out" "INTERRUPTED w01: marked busy but its screen is interrupted"
out="$(BRIG_IDLE_SEC=1 brig wait 5)"
expect_not "once" "$out" "INTERRUPTED"
brig kill w01 >/dev/null
unset BRIG_RUN

echo "== which wmux"
new_env wmux-ow
export WMUX=1 WMUX_SURFACE_ID=surf-both
expect_has "both look present: amirlehmam wins" "$(brig doctor 2>&1)" "terminal: wmux (amirlehmam/wmux"
unset WMUX
expect_has "WMUX_SURFACE_ID alone doesn't make it amirlehmam" "$(brig doctor 2>&1)" "terminal: wmux-ow (openwong2kim/wmux"
new_env wmux-ow
out="$(brig doctor 2>&1)"; code=$?
expect_has "doctor names openwong2kim/wmux and its version" "$out" "ok    terminal: wmux-ow (openwong2kim/wmux 4.5.0-fake, pane opty-self-"
expect_has "and what the fallback can't do" "$out" "tabs keep wmux's own titles"
expect_has "and what it was tested with" "$out" "tested on a real PC with 4.3.0 (newer releases read from source up to 4.5.0)"
check "and passes" test "$code" -eq 0
expect_not "bypassPermissions needs no note about approvals" "$out" "can deny a prompt but not approve one"
out="$(BRIG_PERMISSION_MODE=acceptEdits brig doctor 2>&1)"
expect_has "a stricter mode gets a note: approvals wait for the user" "$out" "note  openwong2kim/wmux lets automation press only Escape at a worker's permission dialog: with BRIG_PERMISSION_MODE=acceptEdits the brigadier can deny a prompt but not approve one"
export LOCALAPPDATA="$E_DIR/localappdata"; mkdir -p "$LOCALAPPDATA/wmux/app-4.2.9" "$LOCALAPPDATA/wmux/app-4.10.0" "$LOCALAPPDATA/wmux/app-4.3.0"
mv "$USERPROFILE/.wmux-auth-token" "$E_DIR/token.away"
expect_has "with no answer from the pipe, the version comes from the install folder" "$(brig doctor 2>&1)" "openwong2kim/wmux 4.10.0 (from its install folder; its pipe did not answer)"
mv "$E_DIR/token.away" "$USERPROFILE/.wmux-auth-token"; unset LOCALAPPDATA
# Exactly what openwong2kim/wmux 4.3.0 set on the user's PC: no WMUX_SURFACE_ID, no WMUX.
(
  unset WMUX WMUX_SURFACE_ID WMUX_CLI WMUX_PIPE
  export WMUX_PTY_ID=daemon-97095f5f TERM_PROGRAM=wmux WMUX_WORKSPACE_ID=ws-test
  expect_has "the env on the user's PC means openwong2kim/wmux" "$(brig doctor 2>&1)" "ok    terminal: wmux-ow (openwong2kim/wmux 4.5.0-fake, pane daemon-97095f5f"
  out="$(brig init pcenv 2>&1)"
  expect_has "and a run uses wmux-ow" "$out" "backend: wmux-ow"
  check "bound to that pane" test -f "$BRIG_HOME/bindings/wmuxow-daemon-97095f5f"
  summary >/dev/null; echo "$PASS $FAIL" >"$E_DIR/sub.count"
)
read -r PASS FAIL <"$E_DIR/sub.count"
out="$(BRIG_BACKEND=wmux brig doctor 2>&1)"
expect_has "BRIG_BACKEND=wmux inside openwong2kim is refused" "$out" "BRIG_BACKEND=wmux (amirlehmam/wmux), but this isn't one of its tabs"
new_env wmux
out="$(brig doctor 2>&1)"
expect_has "doctor names amirlehmam/wmux and its version" "$out" "ok    terminal: wmux (amirlehmam/wmux 2.24.0-fake, tab surf-self-"
out="$(BRIG_BACKEND=wmux-ow brig doctor 2>&1)"
expect_has "BRIG_BACKEND=wmux-ow outside openwong2kim is refused" "$out" "BRIG_BACKEND=wmux-ow (openwong2kim/wmux), but this isn't one of its tabs"

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
expect_has "status shows no 5-hour window for Codex" "$(brig status)" "c01   live    done      -     idle   -     codex"
sleep 1; brig send c01 "one more thing" >/dev/null
check "the token is private to the user" bash -c "[[ \$(ls -l '$R/workers/c01/.inbox_token' | cut -c1-10) == -rw------- ]]"
out="$(brig wait 30)"; expect_has "queued message becomes a resumed turn" "$out" "one more thing"
expect_has "and is framed as the brigadier's message" "$out" "ack: Message from the Brigadier that coordinates this run"
first="$(grep -m1 '^codex exec ' "$FAKE_LOG")"; resumed="$(grep -m1 '^codex exec resume' "$FAKE_LOG")"
for t in first resumed; do
  v="${!t}"
  expect_has "sandboxed by default on the $t turn" "$v" "sandbox_mode=\"workspace-write\""
  expect_has "no prompts on the $t turn" "$v" "approval_policy=\"never\""
  expect_has "network on the $t turn" "$v" "sandbox_workspace_write.network_access=true"
  expect_has "control dir and git dir writable on the $t turn" "$v" "sandbox_workspace_write.writable_roots=[\"$R/workers/c01\",\"$E_DIR/repo/.git\"]"
  expect_not "no bypass on the $t turn" "$v" "--dangerously-bypass-approvals-and-sandbox"
  expect_not "no --full-auto on the $t turn" "$v" "--full-auto"
done
# A message dropped in the inbox by anything but brig is refused, kept aside and reported.
printf 'do something else\n' >"$R/workers/c01/inbox/00000099.msg"
out="$(brig wait 30)"; expect_has "a message without the token is reported" "$out" "REJECTED c01: a queued message was refused (missing or wrong token)"
check "and kept aside" test -f "$R/workers/c01/inbox/rejected/00000099.msg"
expect_not "and never delivered" "$(cat "$FAKE_LOG")" "do something else"
out="$(brig send c01 "$(printf 'colour \033[31mred\033[0m')" 2>&1; brig wait 30)"
expect_has "control characters are stripped" "$out" "ack: Message from the Brigadier"
expect_not "no escape bytes reach codex" "$(grep -a 'colour' "$FAKE_LOG")" $'\033'
long="$(printf 'x%.0s' $(seq 1 2100))"
out="$(brig send c01 "$long" 2>&1)"
expect_has "an over-long inline message is refused" "$out" "limit 2000"
expect_has "with the --file hint" "$out" "brig send c01 --file <path>"
mkdir -p "$R/msgs"; printf '%s\n' "$long" >"$R/msgs/long.md"
brig send c01 --file "$R/msgs/long.md" >/dev/null
out="$(brig wait 30)"; expect_has "send --file queues a pointer to the file" "$out" "Read $R/msgs/long.md and proceed"
brig kill c01 >/dev/null
brig send c01 "late" >/dev/null 2>&1
q="$(find "$R/workers/c01/inbox" -maxdepth 1 -name '*.msg' | head -1)"
expect_has "a queued message starts with the inbox token" "$(head -1 "$q")" "brig-token: $(cat "$R/workers/c01/.inbox_token")"
: >"$FAKE_LOG"
out="$(BRIG_CODEX_SANDBOX=bypass brig spawn c02 "$E_DIR/task.md" --agent codex 2>&1)"
out="$(brig wait 30)"; expect_has "unsandboxed codex worker finishes" "$out" "TURN_END c02 status=done"
sleep 1; brig send c02 "again" >/dev/null
out="$(brig wait 30)"; expect_has "unsandboxed codex worker resumes" "$out" "again"
first="$(grep -m1 '^codex exec ' "$FAKE_LOG")"; resumed="$(grep -m1 '^codex exec resume' "$FAKE_LOG")"
expect_has "bypass opt-in, first turn" "$first" "--dangerously-bypass-approvals-and-sandbox"
expect_has "bypass opt-in, resumed turn" "$resumed" "--dangerously-bypass-approvals-and-sandbox"
expect_not "no sandbox flags with bypass" "$first" "sandbox_mode="
brig kill c02 >/dev/null
out="$(BRIG_CODEX_SANDBOX=off brig spawn c04 "$E_DIR/task.md" --agent codex 2>&1)"
expect_has "refuses an unknown codex sandbox" "$out" "BRIG_CODEX_SANDBOX 'off' must be workspace-write or bypass"
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
gb="$T_ROOT/Program Files/Git/bin/bash.exe"; mkdir -p "${gb%/*}"; : >"$gb"
export CLAUDE_CODE_GIT_BASH_PATH="$gb"
RID="$(run_id_of "$(brig init --slash /brigadier-skill:brigadier win)")"; export BRIG_RUN="$RID"; R="$BRIG_HOME/runs/$RID"
win="C:/fake${R#"$T_ROOT"}"
brig spawn w01 "$E_DIR/task.md" >/dev/null 2>&1
L="$(cat "$R/workers/w01/launch.sh")"
S="$R/workers/w01/settings.json"
for k in Stop SessionStart UserPromptSubmit Notification PreCompact; do
  expect_has "the $k hook runs Git Bash by its full quoted path" "$(jq -r --arg k "$k" '.hooks[$k][0].hooks[0].command' "$S" | cut -c1-$(( ${#gb} + 3 )))" "\"$gb\" "
done
expect_has "so does the statusLine" "$(jq -r .statusLine.command "$S")" "\"$gb\" $SKILL/scripts/brig _hook statusline $R/workers/w01"
expect_has "launch.sh keeps MSYS off the slash command" "$L" "export MSYS2_ARG_CONV_EXCL=/brigadier-skill:brigadier"
expect_has "the kickoff names task.md as a Windows path" "$L" "Read\\ $win/workers/w01/task.md"
expect_has "--settings gets a Windows path" "$L" "--settings $win/workers/w01/settings.json"
expect_has "the worker gets the brigadier's PATH" "$L" "export PATH="
expect_has "the protocol shows Windows paths" "$(cat "$R/workers/w01/task.md")" "Your private directory: \`$win/workers/w01\`"
expect_has "the worker's own dir is added as a Windows path" "$(jq -c .permissions.additionalDirectories "$S")" "[\"$win/workers/w01\"]"
expect_has "and its rules use the bash form of the path" "$(jq -c .permissions.allow "$S")" "[\"Read(/$R/**)\",\"Edit(/$R/workers/w01/**)\"]"
brig kill w01 >/dev/null
brig spawn c01 "$E_DIR/task.md" --agent codex >/dev/null 2>&1
expect_has "a codex worker starts under Git Bash by its full path" "$(cat "$R/workers/c01/launch.sh")" "exec \"$gb\" $SKILL/scripts/codex-worker"
brig kill c01 >/dev/null
fake_mode successor ack
echo "note" >"$E_DIR/note.md"
BRIG_REBIRTH_TIMEOUT=20 brig rebirth "C:/fake${E_DIR#"$T_ROOT"}/note.md" >/dev/null 2>&1
B="$(cat "$R/rebirth.sh")"
expect_has "a rebirth note given as a C:/ path reaches the successor as one" "$B" "C:/fake${E_DIR#"$T_ROOT"}/note.md"
expect_has "rebirth.sh keeps MSYS off the slash command" "$B" "export MSYS2_ARG_CONV_EXCL=/brigadier-skill:brigadier"
expect_has "and still passes it to claude" "$B" "/brigadier-skill:brigadier\\ resume\\ $RID"
check "the old tab closes after the ack" wait_for 10 grep -q "close-surface --force --surface $CMUX_SURFACE_ID" "$FAKE_TERM_DIR/log"
brig kill successor >/dev/null 2>&1
# One codex-worker turn under Git Bash (.state isn't live, so it stops after the kickoff).
cw="$T_ROOT/cw-win"; mkdir -p "$cw"; : >"$FAKE_LOG"
bash "$SKILL/scripts/codex-worker" "$cw" "$E_DIR/repo" high "hello" >/dev/null 2>&1
expect_has "codex-worker hands codex its output file as a Windows path" "$(cat "$FAKE_LOG")" "-o C:/fake/cw-win/last.md"
expect_has "and keeps MSYS from rewriting codex's arguments" "$(cat "$FAKE_LOG")" "codex env MSYS2_ARG_CONV_EXCL=*"
expect_has "with Windows paths as writable roots" "$(cat "$FAKE_LOG")" "writable_roots=[\"C:/fake/cw-win\""
# winget's jq can be on PATH only as jq-windows-amd64.exe; codex-worker finds it the way brig does.
jb="$T_ROOT/jq-exe-only"; mkdir -p "$jb"
for c in bash git grep cut head tail mkdir sed tr date cat dirname basename find sort awk ls rm mv wc tee od; do
  p="$(command -v "$c")" && ln -sf "$p" "$jb/$c"
done
ln -sf "$(command -v jq)" "$jb/jq-windows-amd64.exe"
cw="$T_ROOT/cw-jq"; mkdir -p "$cw"; : >"$FAKE_LOG"
PATH="$TESTS_DIR/fakes/win:$TESTS_DIR/fakes/bin:$jb" bash "$SKILL/scripts/codex-worker" "$cw" "$E_DIR/repo" high "hello" >/dev/null 2>&1
expect_has "codex-worker uses a jq that is only there as jq-*.exe" "$(cat "$FAKE_LOG")" "writable_roots=[\"C:/fake/cw-jq\""
check "and writes its session file" jq -e .transcript_path "$cw/session.json"
mkdir -p "$E_DIR/msgs"; echo "the answer" >"$E_DIR/msgs/answer.md"
brig spawn w02 "$E_DIR/task.md" >/dev/null 2>&1
brig send w02 --file "C:/fake${E_DIR#"$T_ROOT"}/msgs/answer.md" >/dev/null
expect_has "send --file takes a C:/ path and passes it on as one" "$(cat "$FAKE_TERM_DIR/log")" "Read C:/fake${E_DIR#"$T_ROOT"}/msgs/answer.md and proceed"
brig kill w02 >/dev/null
out="$(brig doctor 2>&1)"
expect_has "doctor names the Git Bash that hooks and workers run" "$out" "ok    hooks and workers run $gb"
ob="$T_ROOT/old-jq"; mkdir -p "$ob"
# shellcheck disable=SC2016 # the fake jq's own script
printf '#!/usr/bin/env bash\n[[ "$1" == -b ]] && { echo "Unknown arguments: -b" >&2; exit 2; }\nexec %q "$@"\n' "$(command -v jq)" >"$ob/jq"; chmod +x "$ob/jq"
expect_has "doctor flags a jq too old for -b" "$(PATH="$ob:$PATH" brig doctor 2>&1)" "FAIL  jq can't run with -b, which Windows needs; upgrade it with: winget upgrade --id jqlang.jq"
for b in wmux wmux-ow; do
  # shellcheck disable=SC2016 # expanded by the inner bash
  expect_has "$b quotes curly apostrophes for PowerShell too" "$(bash -c 'source "$1"; ps_quote "$2"' _ "$SKILL/scripts/backends/$b.sh" "C:/Users/O’Neil's ‘x’")" "'C:/Users/O’’Neil''s ‘‘x’’'"
done
unset CLAUDE_CODE_GIT_BASH_PATH
mkdir -p "$T_ROOT/cfg/brigadier"
out="$(env -u BRIG_HOME HOME="$E_DIR/winhome" CLAUDE_CONFIG_DIR='C:\fake\cfg' bash "$SKILL/scripts/brig" config 2>&1)"
expect_has "a Windows-style CLAUDE_CONFIG_DIR is read as a bash path" "$out" "user config: $T_ROOT/cfg/brigadier/config.env"
unset BRIG_RUN FAKE_WIN_ROOT; export PATH="${PATH#"$TESTS_DIR/fakes/win:"}"

echo "== state dir: ~/.brigadier, or the old one inside Claude Code's config dir"
new_env cmux
H="$E_DIR/h"; mkdir -p "$H"
hb() { env -u BRIG_HOME HOME="$H" CLAUDE_CONFIG_DIR="$H/cfg" bash "$SKILL/scripts/brig" "$@"; }
expect_has "a new machine uses ~/.brigadier" "$(hb config)" "user config: $H/.brigadier/config.env"
expect_not "and doctor has nothing to say about it" "$(hb doctor 2>&1)" "move it"
rm -rf "$H/.brigadier"
OLD="$H/cfg/brigadier"; mkdir -p "$OLD/fake-modes"; echo "BRIG_CTX_PCT=44" >"$OLD/config.env"
expect_has "an existing old state dir stays in use" "$(hb config)" "user config: $OLD/config.env"
expect_has "with its config" "$(hb config)" "BRIG_CTX_PCT           44                       user"
oid="$(run_id_of "$(CMUX_SURFACE_ID=movetest hb init moved)")"
check "a run starts there" test -f "$OLD/runs/$oid/run.env"
expect_has "the binding names the old path" "$(cat "$OLD/bindings/cmux-movetest")" "$OLD/runs/$oid"
out="$(hb doctor 2>&1)"
expect_has "doctor says how to move it" "$out" "note  run state is still in $OLD, inside Claude Code's config dir"
expect_has "with the command" "$out" "mv $OLD $H/.brigadier"
# shellcheck disable=SC2016 # expanded by the inner bash
expect_has "without CLAUDE_CONFIG_DIR the old dir is ~/.claude/brigadier" "$(env -u BRIG_HOME -u CLAUDE_CONFIG_DIR HOME="$E_DIR/h2" bash -c 'mkdir -p "$HOME/.claude/brigadier"; bash "$1" config' _ "$SKILL/scripts/brig")" "user config: $E_DIR/h2/.claude/brigadier/config.env"
mv "$OLD" "$H/.brigadier"
expect_has "after the move, ~/.brigadier is used" "$(hb config)" "user config: $H/.brigadier/config.env"
expect_has "with the same config" "$(hb config)" "BRIG_CTX_PCT           44                       user"
expect_has "the old binding finds the moved run" "$(CMUX_SURFACE_ID=movetest hb run)" "$H/.brigadier/runs/$oid"
expect_has "so does a BRIG_RUN with the old path" "$(BRIG_RUN="$OLD/runs/$oid" hb status 2>&1)" "WID"
expect_has "resume works" "$(hb use "$oid")" "$H/.brigadier/runs/$oid"
out="$(CMUX_SURFACE_ID=movetest hb spawn w01 "$E_DIR/task.md" 2>&1)"
expect_has "and the moved run spawns workers in its new place" "$out" "dir=$H/.brigadier/runs/$oid/workers/w01"
CMUX_SURFACE_ID=movetest hb kill w01 >/dev/null
expect_not "doctor has no more note" "$(hb doctor 2>&1)" "run state is still in"
expect_has "a BRIG_HOME inside Claude Code's config dir gets a note" "$(BRIG_HOME="$H/cfg/elsewhere" CLAUDE_CONFIG_DIR="$H/cfg" bash "$SKILL/scripts/brig" doctor 2>&1)" "note  BRIG_HOME=$H/cfg/elsewhere is inside Claude Code's config dir"

echo "== doctor"
new_env cmux
out="$(brig doctor 2>&1)"; code=$?
expect_has "doctor passes with everything present" "$out" "all good"
check "doctor exits 0" test "$code" -eq 0
expect_has "doctor names the backend" "$out" "terminal: cmux"
expect_has "doctor states how workers may act" "$out" "workers and the reborn brigadier: Claude bypassPermissions · Codex sandboxed"
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
new_env wmux
out="$(brig doctor 2>&1)"; code=$?
expect_has "doctor finds wmux inside a wmux tab" "$out" "ok    terminal: wmux (amirlehmam/wmux 2.24.0-fake, tab surf-self-"
check "and passes" test "$code" -eq 0
# Windows without tmux, cmux or wmux on PATH.
new_env tmux-bg
wb="$T_ROOT/winbin"; mkdir -p "$wb"
for c in bash jq git grep cut head tail mkdir sed tr date cat dirname basename find sort awk env stat ls rm mv ln wc mktemp; do
  p="$(command -v "$c")" && ln -sf "$p" "$wb/$c"
done
ln -sf "$TESTS_DIR/fakes/bin/claude" "$wb/claude"; ln -sf "$TESTS_DIR/fakes/win/uname" "$wb/uname"; ln -sf "$TESTS_DIR/fakes/win/cygpath" "$wb/cygpath"
out="$(PATH="$wb" brig doctor 2>&1)"
expect_has "on Windows outside wmux, doctor says to use wmux" "$out" "FAIL  no terminal backend: On Windows, Brigadier runs its workers in wmux"
expect_has "with where to get it" "$out" "https://github.com/amirlehmam/wmux/releases/latest"
expect_not "and no tmux advice" "$out" "install tmux"
expect_has "with openwong2kim/wmux as the alternative" "$out" "Alternative: openwong2kim/wmux, with: winget install --id openwong2kim.wmux -e --source winget"
out="$(PATH="$wb" WMUX_PTY_ID=pty-1 TERM_PROGRAM=wmux brig doctor 2>&1)"
expect_has "an openwong2kim tab without powershell.exe is explained" "$out" "This is an openwong2kim/wmux tab, but powershell.exe isn't on PATH"
out="$(PATH="$wb" WMUX=1 WMUX_SURFACE_ID=surf-1 brig init x 2>&1)"
expect_has "a wmux tab without the CLI is explained" "$out" "the 'wmux' command isn't on PATH"

echo "== Claude Code's folder trust"
new_env cmux
CJ="$CLAUDE_CONFIG_DIR/.claude.json"
trust() { jq -n '{projects: ([$ARGS.positional[] | {key: ., value: {hasTrustDialogAccepted: true}}] | from_entries)}' --args "$@"; }
# spawn_in <dir>: a new run started in <dir>, one worker spawned; prints what spawn said.
spawn_in() {
  local rid; rid="$(cd "$1" && run_id_of "$(brig init tr)")"
  BRIG_RUN="$rid" brig spawn w01 "$E_DIR/task.md" 2>&1
  BRIG_RUN="$rid" brig kill w01 >/dev/null 2>&1
}
out="$(spawn_in "$E_DIR/repo")"
expect_has "no .claude.json: spawn says it can't tell" "$out" "note: can't read Claude Code's list of trusted folders ($CJ)"
trust "$E_DIR/repo" >"$CJ"; cp "$CJ" "$E_DIR/cj.before"
out="$(spawn_in "$E_DIR/repo")"
expect_not "a trusted repo: no note" "$out" "note:"
check ".claude.json is never written" cmp -s "$CJ" "$E_DIR/cj.before"
git -C "$E_DIR/repo" worktree add -q "$E_DIR/wt" -b wt-branch 2>/dev/null
expect_not "a worktree of a trusted repo is trusted" "$(spawn_in "$E_DIR/wt")" "note:"
mkdir -p "$E_DIR/repo/sub/deeper"
expect_has "the run is the repo, from any subfolder" "$(spawn_in "$E_DIR/repo/sub/deeper")" "spawned w01"
mkdir -p "$E_DIR/outer/inner" "$E_DIR/plain/child"; git -C "$E_DIR/outer/inner" init -q
trust "$E_DIR/outer" "$E_DIR/plain" >"$CJ"
out="$(spawn_in "$E_DIR/outer/inner")"
expect_has "a git repo inside a trusted folder is not trusted" "$out" "note: Claude Code hasn't trusted $E_DIR/outer/inner yet (no hasTrustDialogAccepted for it in $CJ), so w01 will stop at its 'trust this folder' dialog"
expect_not "a plain folder inside a trusted one is" "$(spawn_in "$E_DIR/plain/child")" "note:"
jq -n --arg k "$E_DIR/repo" '{projects: {($k): {hasTrustDialogAccepted: false}}}' >"$CJ"
expect_has "hasTrustDialogAccepted false is not trusted" "$(spawn_in "$E_DIR/repo")" "hasn't trusted $E_DIR/repo yet"
mkdir -p "$E_DIR/workercfg"; trust "$E_DIR/repo" >"$E_DIR/workercfg/.claude.json"
expect_not "workers' BRIG_CLAUDE_CONFIG_DIR is the one read" "$(BRIG_CLAUDE_CONFIG_DIR="$E_DIR/workercfg" spawn_in "$E_DIR/repo")" "note:"
RID="$(run_id_of "$(brig init dialogs)")"; export BRIG_RUN="$RID"
fake_mode w01 trust-yes-first
brig spawn w01 "$E_DIR/task.md" >/dev/null 2>&1; sleep 4
expect_has "check sees the trust dialog" "$(brig check)" "w01 flag=busy screen=trust status=- :: TRUST_PROMPT"
out="$(brig trust w01 2>&1)"
expect_has "trust reads the cursor: Yes first means Enter only" "$out" "accepted the trust dialog in w01 (enter)"
out="$(brig wait 30)"; expect_has "and the worker starts" "$out" "TURN_END w01 status=done"
fake_mode w02 trust-unreadable
brig spawn w02 "$E_DIR/task.md" >/dev/null 2>&1
out="$(brig wait 30)"; expect_has "a dialog without a cursor still raises TRUST_PROMPT" "$out" "TRUST_PROMPT w02"
expect_has "and shows its options" "$out" "[options: No, exit | Yes, I trust this folder]"
out="$(brig trust w02 2>&1)"; code=$?
check "trust refuses a dialog it can't read" test "$code" -ne 0
expect_has "and says why" "$out" "TRUST_UNREADABLE: can't tell which option of w02's trust dialog has the cursor"
check "nothing was pressed" test -z "$(cat "$FAKE_TERM_DIR/s/$(surface_of w02)/keys" 2>/dev/null)"
expect_has "it is logged" "$(cat "$BRIG_HOME/runs/$RID/events.log")" "trust w02: dialog not readable"
out="$(brig trust w01 2>&1)"
expect_has "trust presses nothing when there's no dialog" "$out" "TRUST_UNREADABLE: w01's screen doesn't show Claude Code's trust dialog"
fake_mode w03 trust-stuck
brig spawn w03 "$E_DIR/task.md" >/dev/null 2>&1; sleep 4
out="$(brig trust w03 2>&1)"; code=$?
check "trust fails when the cursor doesn't reach Yes" test "$code" -ne 0
expect_has "and doesn't press Enter" "$out" "TRUST_UNREADABLE: pressed down in w03's trust dialog, but the cursor isn't on 'Yes, I trust this folder'; Enter was not pressed"
check "only down was pressed" test "$(cat "$FAKE_TERM_DIR/s/$(surface_of w03)/keys")" = down
brig kill w01 >/dev/null; brig kill w02 >/dev/null
brig spawn w04 "$E_DIR/task.md" >/dev/null 2>&1; brig wait 30 >/dev/null; rm -f "$BRIG_HOME/runs/$RID/workers/w04/session.json"
out="$(brig trust w04 2>&1)"
expect_has "a worker without a session and without the dialog: trust says so" "$out" "TRUST_UNREADABLE: w04's screen doesn't show Claude Code's trust dialog; nothing was pressed"
brig kill w03 >/dev/null; brig kill w04 >/dev/null; unset BRIG_RUN
# Windows: Claude Code keys the folder as C:/…; letter case doesn't matter.
export PATH="$TESTS_DIR/fakes/win:$PATH" FAKE_WIN_ROOT="$T_ROOT"
gb="$T_ROOT/Program Files/Git/bin/bash.exe"; mkdir -p "${gb%/*}"; : >"$gb"; export CLAUDE_CODE_GIT_BASH_PATH="$gb"
winrepo="C:/fake${E_DIR#"$T_ROOT"}/repo"
trust "$(tr '[:lower:]' '[:upper:]' <<<"${winrepo:0:1}")$(tr '[:upper:]' '[:lower:]' <<<"${winrepo:1}")" >"$CJ"
expect_not "on Windows the C:/ key is found, in any case" "$(spawn_in "$E_DIR/repo")" "note:"
trust "$E_DIR/repo" >"$CJ"
expect_has "and a POSIX key is not Claude Code's" "$(spawn_in "$E_DIR/repo")" "hasn't trusted $winrepo yet"
unset FAKE_WIN_ROOT CLAUDE_CODE_GIT_BASH_PATH; export PATH="${PATH#"$TESTS_DIR/fakes/win:"}"

echo "== runs, resume candidates and overlapping runs"
new_env cmux
set_created() { sed -i.bak "s/^CREATED=.*/CREATED='$2'/" "$BRIG_HOME/runs/$1/run.env" && rm -f "$BRIG_HOME/runs/$1/run.env.bak"; }
A="$(run_id_of "$(brig init alpha)")"; printf '# Phase 1: build the thing\n\nmore\n' >"$BRIG_HOME/runs/$A/goal.md"
B="$(run_id_of "$(brig init bravo)")"; BRIG_RUN="$B" brig finish "x" >/dev/null
mkdir -p "$E_DIR/other"; C="$(cd "$E_DIR/other" && run_id_of "$(brig init charlie)")"
out="$(brig runs)"
expect_has "runs has a header" "$out" "RUN                                STATE     STARTED           LAST              REPO · GOAL"
expect_has "runs shows each run's state" "$out" "$(printf '%-34s %-9s' "$A" active)"
expect_has "the goal's first line" "$out" "$E_DIR/repo · Phase 1: build the thing"
expect_has "a run without goal.md says so" "$out" "$E_DIR/repo · (no goal.md)"
expect_has "finished runs are marked" "$out" "$(printf '%-34s %-9s' "$B" finished)"
out="$(brig runs --here)"
expect_has "--here keeps this repo's runs" "$out" "$(printf '%-34s %-9s' "$A" active)"
expect_not "and drops other repos' runs" "$out" "$C"
# Overlap is judged on full dates: an overnight run, and one that only looks close by HH:MM.
set_created "$A" "2026-10-14 22:00"
set_created "$B" "2026-10-14 21:30"; echo "2026-10-15 01:10" >"$BRIG_HOME/runs/$B/finished"
D="$(run_id_of "$(brig init delta)")"; set_created "$D" "2026-10-13 23:00"; echo "2026-10-13 23:30" >"$BRIG_HOME/runs/$D/finished"
set_created "$C" "2026-10-14 23:00"
out="$(BRIG_RUN="$A" brig runs --overlap)"
expect_has "an overnight run on the same repo overlaps" "$out" "overlap: $B (finished, 2026-10-14 21:30 to 2026-10-15 01:10)"
expect_not "a run two days earlier doesn't, whatever its HH:MM" "$out" "$D"
expect_not "nor a run on another repo" "$out" "$C"
out="$(BRIG_RUN="$D" brig runs --overlap)"
expect_has "no overlap is said plainly" "$out" "no other run on $E_DIR/repo was active during $D (2026-10-13 23:00 to 2026-10-13 23:30)"
E2="$(run_id_of "$(brig init echo)")"; set_created "$E2" "2026-10-15 00:30"
expect_has "an unfinished run counts as active until now" "$(BRIG_RUN="$D" brig runs --overlap; BRIG_RUN="$B" brig runs --overlap)" "overlap: $E2 (active, 2026-10-15 00:30 to now)"
# More than 30 runs: every unfinished one is still listed, so a bare resume sees them all.
old="$BRIG_HOME/runs/20200101-0000-old"; mkdir -p "$old"; printf 'REPO=%q\n' "$E_DIR/repo" >"$old/run.env"
for i in $(seq 1 31); do
  f="$BRIG_HOME/runs/20250101-0000-f$i"; mkdir -p "$f"; printf 'REPO=%q\n' "$E_DIR/repo" >"$f/run.env"; echo x >"$f/finished"
done
touch -t 202001010000 "$old"
out="$(brig runs --here)"
expect_has "an old unfinished run is listed past 30 newer finished ones" "$out" "20200101-0000-old"
check "finished runs stop at 30 rows" test "$(grep -c ' finished ' <<<"$out")" -le 30

echo "== a run may tighten the user's limits, never loosen them"
new_env cmux
printf 'BRIG_ALLOWED_MODELS="opus sonnet"\n' >"$BRIG_HOME/config.env"
RID="$(run_id_of "$(brig init limits)")"; export BRIG_RUN="$RID"; R="$BRIG_HOME/runs/$RID"
printf 'BRIG_MAX_EFFORT=max\nBRIG_ALLOWED_MODELS="opus sonnet haiku"\n' >"$R/config.env"
out="$(brig spawn w01 "$E_DIR/task.md" --effort max 2>&1)"
expect_has "a looser run-level effort ceiling is ignored" "$out" "effort 'max' is above BRIG_MAX_EFFORT=high"
out="$(brig spawn w01 "$E_DIR/task.md" --model haiku 2>&1)"
expect_has "a looser run-level allowlist is ignored" "$out" "model 'haiku' is not in BRIG_ALLOWED_MODELS (opus sonnet)"
out="$(brig config)"
expect_has "config says why" "$out" "BRIG_MAX_EFFORT        high                     user (the run's value is ignored: a run may tighten your limits, not loosen them)"
expect_has "for both" "$out" "BRIG_ALLOWED_MODELS    opus sonnet              user (the run's value is ignored"
printf 'BRIG_MAX_EFFORT=medium\nBRIG_ALLOWED_MODELS=sonnet\n' >"$R/config.env"
out="$(brig spawn w01 "$E_DIR/task.md" --effort high --model sonnet 2>&1)"
expect_has "a tighter run-level effort ceiling applies" "$out" "effort 'high' is above BRIG_MAX_EFFORT=medium"
out="$(brig spawn w01 "$E_DIR/task.md" --effort medium 2>&1)"
expect_has "a tighter run-level allowlist applies" "$out" "model 'opus' is not in BRIG_ALLOWED_MODELS (sonnet)"
expect_has "and config shows it as the run's" "$(brig config)" "BRIG_MAX_EFFORT        medium                   run"
rm -f "$BRIG_HOME/config.env"; printf 'BRIG_ALLOWED_MODELS="sonnet haiku"\n' >"$R/config.env"
expect_has "any list tightens '*'" "$(brig spawn w01 "$E_DIR/task.md" --model opus 2>&1)" "model 'opus' is not in BRIG_ALLOWED_MODELS (sonnet haiku)"
unset BRIG_RUN

echo "== a model directive in the goal"
new_env cmux
RID="$(run_id_of "$(brig init directive)")"; export BRIG_RUN="$RID"; R="$BRIG_HOME/runs/$RID"
printf 'BRIG_DEFAULT_MODEL=sonnet\nBRIG_CHORE_MODEL=sonnet\n' >"$R/config.env"
out="$(brig spawn w01 "$E_DIR/task.md" --title "Phase 1 · verify" 2>&1)"
expect_has "every worker gets the run's model, verifiers included" "$out" "spawned w01 [claude sonnet effort=high]"
out="$(brig spawn c01 "$E_DIR/task.md" --agent codex 2>&1)"
expect_has "and Codex workers are refused" "$out" "this run's goal names the workers' model ($R/config.env sets BRIG_DEFAULT_MODEL=sonnet), so no Codex workers"
printf 'BRIG_CODEX=on\n' >>"$R/config.env"
expect_has "unless the goal names Codex for a role" "$(brig spawn c01 "$E_DIR/task.md" --agent codex 2>&1)" "spawned c01 [codex"
fake_mode successor ack
out="$(BRIG_REBIRTH_TIMEOUT=20 brig rebirth 2>&1)"
expect_has "the reborn brigadier keeps the user's default model" "$(cat "$R/rebirth.sh")" "--model opus"
printf 'BRIG_DEFAULT_MODEL=haiku\n' >"$BRIG_HOME/config.env"
BRIG_REBIRTH_TIMEOUT=20 brig rebirth >/dev/null 2>&1
expect_has "from the user's config" "$(cat "$R/rebirth.sh")" "--model haiku"
printf 'BRIG_DEFAULT_EFFORT=max\n' >>"$R/config.env"
BRIG_REBIRTH_TIMEOUT=20 brig rebirth >/dev/null 2>&1
expect_has "its effort stays at or below BRIG_MAX_EFFORT" "$(cat "$R/rebirth.sh")" "--effort high"
brig kill successor >/dev/null 2>&1; brig kill w01 >/dev/null; brig kill c01 >/dev/null; unset BRIG_RUN

echo "== the reborn brigadier's permission mode"
new_env cmux
RID="$(run_id_of "$(brig init perms)")"; export BRIG_RUN="$RID"; R="$BRIG_HOME/runs/$RID"
fake_mode successor ack
BRIG_REBIRTH_TIMEOUT=20 brig rebirth >/dev/null 2>&1
expect_has "by default it bypasses permissions, like workers" "$(cat "$R/rebirth.sh")" "--permission-mode bypassPermissions"
expect_has "without the bypass warning" "$(jq -c .skipDangerousModePermissionPrompt "$R/rebirth-settings.json")" 'true'
expect_has "it reads and edits its run dir without a prompt" "$(jq -c .permissions "$R/rebirth-settings.json")" "{\"additionalDirectories\":[\"$R\"],\"allow\":[\"Read(/$R/**)\",\"Edit(/$R/**)\"]}"
brig kill successor >/dev/null 2>&1
printf 'BRIG_PERMISSION_MODE=manual\n' >"$BRIG_HOME/config.env"
BRIG_REBIRTH_TIMEOUT=20 brig rebirth >/dev/null 2>&1
expect_has "it follows BRIG_PERMISSION_MODE" "$(cat "$R/rebirth.sh")" "--permission-mode manual"
expect_has "with no bypass setting" "$(jq -c .skipDangerousModePermissionPrompt "$R/rebirth-settings.json")" 'false'
expect_has "doctor names the brigadier too" "$(brig doctor 2>&1)" "workers and the reborn brigadier: Claude manual"
brig kill successor >/dev/null 2>&1; unset BRIG_RUN

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
