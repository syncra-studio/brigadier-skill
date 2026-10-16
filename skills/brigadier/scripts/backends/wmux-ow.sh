# shellcheck shell=bash
# Terminal backend: wmux-ow, for openwong2kim/wmux (https://github.com/openwong2kim/wmux), the
# fallback Windows backend (amirlehmam/wmux, backend wmux, is the recommended one).
# Tested on a real PC with openwong2kim/wmux 4.3.0 (newer releases read from source up to 4.5.0). Sourced by brig. Contract: see CONTRIBUTING.md.
# Run-level variables available here (from run.env): WORKSPACE, WMUX_BASH, OW_PIPE.
#
# Its CLI (wmux.cmd) can't open a tab in a given cwd or workspace, and cmd mangles message text,
# so every call goes straight to the app's RPC pipe, the way its own CLI does (src/cli/client.ts):
# one JSON line {id, method, params, token, clientName: "wmux-cli"} in, one JSON line
# {id, ok, result | error} back. The pipe is \\.\pipe\wmux<WMUX_DATA_SUFFIX>-<user>
# (src/shared/constants.ts getPipeName), the token is in ~/.wmux<suffix>-auth-token
# (getAuthTokenPath). PowerShell, which every Windows has, does the pipe I/O; the request goes
# in through an environment variable, so the script itself is fixed text.
#
# A backend id is <surfaceId>@<ptyId>: input and screen reads address the pty, closing and
# focusing address the surface.

# shellcheck disable=SC2016 # PowerShell's own variables, not bash's
OW_PS='$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$enc = New-Object System.Text.UTF8Encoding($false)
$c = New-Object System.IO.Pipes.NamedPipeClientStream(".", $env:WMUXOW_PIPE, [System.IO.Pipes.PipeDirection]::InOut)
try { $c.Connect(5000) } catch { [Console]::Error.WriteLine("cannot reach the wmux pipe " + $env:WMUXOW_PIPE + ": " + $_.Exception.Message); exit 3 }
$w = New-Object System.IO.StreamWriter($c, $enc); $w.NewLine = "`n"; $w.AutoFlush = $true
$r = New-Object System.IO.StreamReader($c, $enc)
$w.WriteLine($env:WMUXOW_REQ)
$deadline = (Get-Date).AddSeconds(15)
while ($true) {
  $t = $r.ReadLineAsync()
  $left = [int](($deadline - (Get-Date)).TotalMilliseconds)
  if ($left -le 0 -or -not $t.Wait($left)) { [Console]::Error.WriteLine("wmux did not answer"); exit 4 }
  $l = $t.Result
  if ($null -eq $l) { [Console]::Error.WriteLine("wmux closed the pipe"); exit 5 }
  if ($l.Contains($env:WMUXOW_ID)) { [Console]::Out.WriteLine($l); break }
}
$c.Dispose()'

ow_pipe() {
  local p="${WMUX_SOCKET_PATH:-}"
  if [[ -n "$p" ]]; then p="${p//\//\\}"; echo "${p##*\\}"; return; fi
  echo "wmux${WMUX_DATA_SUFFIX:-}-${USERNAME:-$(id -un 2>/dev/null)}"
}
ow_token() {
  local f; f="$(posix_path "${USERPROFILE:-$HOME}")/.wmux${WMUX_DATA_SUFFIX:-}-auth-token"
  if [[ -s "$f" ]]; then tr -d '\r\n' <"$f"; else printf '%s' "${WMUX_AUTH_TOKEN:-}"; fi
}

# ow_rpc <method> <params-json>: prints the result as JSON, or fails with wmux's error on stderr.
# wmux's errors often start with the method name already ("input.send: pane …"); it's printed once.
ow_rpc() {
  local id req out e
  id="brig-$(od -An -tx1 -N8 /dev/urandom | tr -d ' \n')"
  req="$(jq -cn --arg id "$id" --arg m "$1" --argjson p "$2" --arg t "$(ow_token)" \
    '{id: $id, method: $m, params: $p, token: $t, clientName: "wmux-cli"}')" || return 1
  out="$(MSYS2_ARG_CONV_EXCL='*' MSYS_NO_PATHCONV=1 WMUXOW_PIPE="${OW_PIPE:-$(ow_pipe)}" WMUXOW_REQ="$req" WMUXOW_ID="$id" \
    powershell.exe -NoProfile -NonInteractive -Command "$OW_PS" | tr -d '\r')" || return 1
  if [[ "$(jq -r '.ok' <<<"$out" 2>/dev/null)" != true ]]; then
    e="$(jq -r '.error // "no answer"' <<<"$out" 2>/dev/null || echo "$out")"
    echo "wmux: $1: ${e#"$1: "}" >&2
    return 1
  fi
  jq -c '.result' <<<"$out"
}
ow_sid() { echo "${1%@*}"; }
ow_pty() { echo "${1#*@}"; }

be_available() { [[ -n "${WMUX_PTY_ID:-}" ]] && command -v powershell.exe >/dev/null 2>&1; }

# The surface id of a pty in this workspace (the brigadier's own tab, for focus and rebirth).
ow_surface_of() {
  ow_rpc surface.list "$(jq -cn --arg w "$WORKSPACE" '{workspaceId: $w}')" \
    | jq -r --arg p "$1" '[(if type == "array" then . else .surfaces end)[] | select(.ptyId == $p) | .id][0] // empty'
}

be_init_run() {
  [[ -n "${WMUX_PTY_ID:-}" ]] || die "wmux-ow backend: not inside an openwong2kim/wmux tab (WMUX_PTY_ID is unset)"
  local ws="${WMUX_WORKSPACE_ID:-}" b
  ow_rpc system.identify '{}' >/dev/null || die "wmux-ow: openwong2kim/wmux's pipe ($(ow_pipe)) didn't answer; is wmux running?"
  if [[ -z "$ws" ]]; then
    # The workspace on screen, which is this tab's when the user just ran /brigadier in it.
    ws="$(ow_rpc workspace.current '{}' | jq -r '.id // empty')" || true
  fi
  [[ -n "$ws" ]] || die "wmux-ow: could not tell which workspace this tab is in"
  b="$(git_bash)" || die "wmux-ow: Git Bash's bash.exe not found; set CLAUDE_CODE_GIT_BASH_PATH to it"
  printf 'MODE=attached\nWORKSPACE=%q\nWMUX_BASH=%q\nOW_PIPE=%q\n' "$ws" "$b" "$(ow_pipe)"
}

be_self_id() {
  [[ -n "${WMUX_PTY_ID:-}" ]] || return 0
  local s="${WMUX_SURFACE_ID:-}"
  [[ -n "$s" ]] || s="$(ow_surface_of "$WMUX_PTY_ID" 2>/dev/null || true)"
  # Unknown is fine (no focus hand-back, no self-close on rebirth), but must not fail under set -e.
  if [[ -n "$s" ]]; then echo "$s@$WMUX_PTY_ID"; fi
}

# A PowerShell single-quoted string. PowerShell also ends one at the curly quotes ‘ ’ ‚ ‛, so those
# are doubled like the plain one.
ps_quote() {
  local s="$1" c
  for c in "'" "‘" "’" "‚" "‛"; do s="${s//$c/$c$c}"; done
  printf "'%s'" "$s"
}

# surface.new can't take a command (the pipe handler forwards only workspaceId, shell and cwd:
# src/main/pipe/handlers/surface.rpc.ts), so the tab opens in PowerShell and the command is typed
# once its prompt is up. `; exit` ends the shell cleanly, and wmux closes a tab whose shell exits
# with 0 (closeTabOnShellExit, on by default), so a dead worker shows up as GONE.
# The new tab takes focus; the brigadier's own tab gets it back.
be_spawn() {
  local cwd="$1" cmd="$2" title="$3" out sid pty self _
  out="$(ow_rpc surface.new "$(jq -cn --arg w "$WORKSPACE" --arg c "$(native_path "$cwd")" \
    '{workspaceId: $w, cwd: $c, shell: "powershell.exe"}')")" || die "wmux-ow: could not open a tab"
  sid="$(jq -r '.id // empty' <<<"$out")"; pty="$(jq -r '.ptyId // empty' <<<"$out")"
  [[ -n "$sid" && -n "$pty" ]] || die "wmux-ow: could not read the new tab's ids from: $out"
  for _ in $(seq 1 20); do
    be_read "$sid@$pty" 5 2>/dev/null | grep -q 'PS .*>' && break
    sleep 0.5
  done
  if ! be_send_text "$sid@$pty" "& $(ps_quote "$WMUX_BASH") $(ps_quote "$(native_path "$cmd")"); exit" \
    || ! be_send_enter "$sid@$pty"; then
    die "wmux-ow: could not start the command in tab $sid"
  fi
  self="$(be_self_id)"
  if [[ -n "$self" ]]; then
    ow_rpc surface.focus "$(jq -cn --arg s "$(ow_sid "$self")" '{id: $s}')" >/dev/null 2>&1 || true
  fi
  : "$title" # openwong2kim's pipe has no tab rename the CLI is allowed to call
  echo "$sid@$pty"
}

be_send_text() {
  ow_rpc input.send "$(jq -cn --arg p "$(ow_pty "$1")" --arg w "$WORKSPACE" --arg t "$2" \
    '{ptyId: $p, workspaceId: $w, text: $t}')" >/dev/null
}
be_send_enter() {
  ow_rpc input.sendKey "$(jq -cn --arg p "$(ow_pty "$1")" --arg w "$WORKSPACE" \
    '{ptyId: $p, workspaceId: $w, key: "enter"}')" >/dev/null
}
# input.sendKey knows enter, tab, escape and the arrows (KEY_MAP in src/main/pipe/handlers/input.rpc.ts);
# space and digits are typed. While a pane shows the agent's own permission dialog, wmux (4.3.0) refuses
# input.send and every input.sendKey except escape, which denies the dialog: brig can deny a prompt but
# never approve one; only the user can, in the pane. Its error says so.
be_send_key() {
  case "$2" in
    [1-9]) be_send_text "$1" "$2" ;;
    space) be_send_text "$1" " " ;;
    *) ow_rpc input.sendKey "$(jq -cn --arg p "$(ow_pty "$1")" --arg w "$WORKSPACE" --arg k "$2" \
         '{ptyId: $p, workspaceId: $w, key: $k}')" >/dev/null ;;
  esac
}
be_read() {
  ow_rpc input.readScreen "$(jq -cn --arg p "$(ow_pty "$1")" --arg w "$WORKSPACE" --argjson n "${2:-40}" \
    '{ptyId: $p, workspaceId: $w, tail_lines: $n}')" | jq -r '.text // empty'
}
be_close() { ow_rpc surface.close "$(jq -cn --arg s "$(ow_sid "$1")" '{id: $s}')" >/dev/null 2>&1 || true; }
# Tabs are spawned in the brigadier's workspace, and that's the one listed (a tab dragged to
# another workspace looks gone).
be_live_ids() {
  ow_rpc surface.list "$(jq -cn --arg w "$WORKSPACE" '{workspaceId: $w}')" \
    | jq -r '(if type == "array" then . else .surfaces end)[] | select(.ptyId != null) | "\(.id)@\(.ptyId)"'
}
be_notify() {
  ow_rpc notify "$(jq -cn --arg t "$1" --arg b "$2" --arg w "$WORKSPACE" '{title: $t, body: $b, workspaceId: $w}')" >/dev/null 2>&1 || true
}
# meta.setStatus wants the calling pane (senderPtyId) to place the status.
be_status() {
  ow_rpc meta.setStatus "$(jq -cn --arg t "$1" --arg p "${WMUX_PTY_ID:-}" --arg w "$WORKSPACE" \
    '{text: $t, senderPtyId: $p, workspaceId: $w}')" >/dev/null 2>&1 || true
}
be_status_clear() { be_status ""; }
be_watch_hint() { echo "Workers open as tabs in this wmux workspace (openwong2kim/wmux)."; }
