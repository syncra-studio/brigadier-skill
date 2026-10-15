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
check "and passes" test "$code" -eq 0
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
out="$(env -u BRIG_HOME CLAUDE_CONFIG_DIR='C:\fake\cfg' bash "$SKILL/scripts/brig" config 2>&1)"
expect_has "a Windows-style CLAUDE_CONFIG_DIR is read as a bash path" "$out" "user config: $T_ROOT/cfg/brigadier/config.env"
unset BRIG_RUN FAKE_WIN_ROOT; export PATH="${PATH#"$TESTS_DIR/fakes/win:"}"

echo "== doctor"
new_env cmux
out="$(brig doctor 2>&1)"; code=$?
expect_has "doctor passes with everything present" "$out" "all good"
check "doctor exits 0" test "$code" -eq 0
expect_has "doctor names the backend" "$out" "terminal: cmux"
expect_has "doctor states how workers may act" "$out" "workers: Claude bypassPermissions · Codex sandboxed"
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
