#!/usr/bin/env bash
# brig setup on every platform it knows, with fake package managers: what it prints, what it
# installs and when, what it never touches, and doctor as its last step.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

export FAKE_REAL_JQ FAKE_REAL_GIT
FAKE_REAL_JQ="$(command -v jq)"; FAKE_REAL_GIT="$(command -v git)"

# A PATH with the basics and the fake claude, but no jq, tmux, cmux, wmux or codex.
# setup_env <name> [extra dir first on PATH]...
setup_env() {
  new_env tmux-bg
  local bin="$E_DIR/bin" c p d
  mkdir -p "$bin"
  for c in bash git grep cut head tail mkdir sed tr date cat dirname basename find sort awk env stat ls rm mv cp ln wc mktemp sleep readlink chmod tee seq; do
    p="$(command -v "$c")" && ln -sf "$p" "$bin/$c"
  done
  ln -sf "$TESTS_DIR/fakes/bin/claude" "$bin/claude"
  export FAKE_INSTALL_DIR="$E_DIR/installed"; mkdir -p "$FAKE_INSTALL_DIR"
  PATH="$bin:$FAKE_INSTALL_DIR"
  for d in "$@"; do PATH="$d:$PATH"; done
  export PATH
  unset FAKE_UNAME_S BRIG_OS_RELEASE FAKE_SUDO_NOPASS FAKE_WINGET_DIR LOCALAPPDATA FAKE_WIN_ROOT
}
os_release() { printf '%s\n' "$@" >"$E_DIR/os-release"; export BRIG_OS_RELEASE="$E_DIR/os-release"; }
# Hide brew or winget from PATH by name: they live with the other fakes, so link the rest instead.
only_fakes() { # only_fakes <dir> <fake>...
  local dir="$1" f; shift; mkdir -p "$dir"
  for f in "$@"; do printf '#!/usr/bin/env bash\nexec %q "$@"\n' "$TESTS_DIR/fakes/os/$f" >"$dir/$f"; chmod +x "$dir/$f"; done
}
CFG() { cat "$BRIG_HOME/config.env"; }

echo "== setup on macOS"
setup_env; only_fakes "$E_DIR/os" uname brew; PATH="$E_DIR/os:$PATH"; export FAKE_UNAME_S=Darwin
out="$(brig setup </dev/null 2>&1)"; code=$?
expect_has "names the platform" "$out" "platform: macOS (Homebrew)"
expect_has "lists what's missing" "$out" "missing  jq"
expect_has "prints one exact install command" "$out" "run:  brew install jq tmux"
expect_has "says nothing was installed" "$out" "Nothing was installed."
expect_not "and installs nothing by default" "$(cat "$FAKE_LOG" 2>/dev/null)" "brew install"
expect_has "runs doctor last" "$(tail -3 <<<"$out")" "fix the FAIL lines first"
check "and exits with doctor's failure" test "$code" -ne 0
expect_has "creates the user config" "$out" "created  config $BRIG_HOME/config.env"
check "with every setting commented out" bash -c "! grep -Eq '^BRIG_' '$BRIG_HOME/config.env' && grep -q '^# BRIG_DEFAULT_MODEL=opus' '$BRIG_HOME/config.env'"
expect_has "so the defaults apply" "$(brig config)" "BRIG_DEFAULT_MODEL     opus                     default"
out="$(brig setup --install </dev/null 2>&1)"
expect_has "--install without a terminal asks for --yes" "$out" "Not installing: there's no terminal to confirm in"
expect_not "and installs nothing" "$(cat "$FAKE_LOG" 2>/dev/null)" "brew install"
echo "BRIG_MAX_WORKERS=2   # mine" >>"$BRIG_HOME/config.env"; before="$(CFG)"
out="$(brig setup --install --yes </dev/null 2>&1)"; code=$?
expect_has "--install --yes runs the command shown" "$(cat "$FAKE_LOG")" "brew install jq tmux"
expect_has "then doctor passes" "$out" "all good"
check "and setup exits 0" test "$code" -eq 0
out="$(brig setup </dev/null 2>&1)"; code=$?
expect_has "a second run finds everything" "$out" "ok       jq"
expect_not "and has nothing to do" "$out" "to do:"
expect_has "leaves the config alone" "$out" "(left as it is)"
check "byte for byte" test "$(CFG)" == "$before"
check "and still passes" test "$code" -eq 0
check "brew ran once" test "$(grep -c '^brew install' "$FAKE_LOG")" -eq 1

echo "== setup on macOS without Homebrew"
setup_env; only_fakes "$E_DIR/os" uname; PATH="$E_DIR/os:$PATH"; export FAKE_UNAME_S=Darwin
out="$(brig setup --install --yes </dev/null 2>&1)"
expect_has "points at brew.sh instead of running anything" "$out" "by hand: Homebrew is needed for: brew install jq tmux (get Homebrew from https://brew.sh)"
expect_not "and doesn't try" "$out" "\$ brew"

echo "== setup on Debian and Fedora"
setup_env "$TESTS_DIR/fakes/os"; os_release 'ID=ubuntu' 'ID_LIKE=debian'
out="$(brig setup </dev/null 2>&1)"
expect_has "names the distribution" "$out" "platform: Linux (debian)"
expect_has "prints the apt command" "$out" "run:  sudo apt install -y jq tmux"
out="$(brig setup --install --yes </dev/null 2>&1)"
expect_has "a sudo command needing a password is handed to the user" "$out" "needs your password, so run it yourself (in Claude Code: ! sudo apt install -y jq tmux)"
expect_not "and not run" "$(cat "$FAKE_LOG" 2>/dev/null)" "apt install"
out="$(FAKE_SUDO_NOPASS=1 brig setup --install --yes </dev/null 2>&1)"
expect_has "with sudo already allowed, it runs" "$(cat "$FAKE_LOG")" "sudo apt install -y jq tmux"
expect_has "and doctor passes" "$out" "all good"
setup_env "$TESTS_DIR/fakes/os"; os_release 'ID=fedora'
expect_has "Fedora gets dnf" "$(brig setup </dev/null 2>&1)" "run:  sudo dnf install -y jq tmux"
setup_env "$TESTS_DIR/fakes/os"; os_release 'ID=arch'
expect_has "Arch gets pacman" "$(brig setup </dev/null 2>&1)" "run:  sudo pacman -S --needed jq tmux"
setup_env "$TESTS_DIR/fakes/os"; os_release 'ID=nixos'
expect_has "an unknown distribution gets plain words" "$(brig setup </dev/null 2>&1)" "by hand: jq tmux: install with your package manager"

echo "== setup on Windows (Git Bash, simulated)"
setup_env; only_fakes "$E_DIR/os" winget; PATH="$TESTS_DIR/fakes/win:$E_DIR/os:$PATH"
export LOCALAPPDATA="$E_DIR/la" FAKE_WINGET_DIR="$E_DIR/la/Microsoft/WinGet/Links"
out="$(brig setup </dev/null 2>&1)"
expect_has "names the platform" "$out" "platform: Windows, Git Bash (winget)"
expect_has "prints the winget command" "$out" "run:  winget install --id jqlang.jq -e --source winget"
expect_has "and how to get wmux" "$out" "by hand: wmux: On Windows, Brigadier runs its workers in wmux"
expect_has "with its release page" "$out" "https://github.com/amirlehmam/wmux/releases/latest"
expect_not "never suggests tmux" "$out" "tmux"
expect_not "never offers to download wmux" "$out" "curl"
expect_has "recommends amirlehmam/wmux first" "$out" "by hand: wmux: On Windows, Brigadier runs its workers in wmux (tabs, like cmux on macOS), and this isn't a wmux tab. Recommended: amirlehmam/wmux."
expect_has "offers openwong2kim/wmux through winget as the alternative" "$out" "run:  winget install --id openwong2kim.wmux -e --source winget   (only if you choose openwong2kim/wmux over amirlehmam/wmux"
check "the recommendation comes before the alternative" bash -c "grep -n . <<<\"\$1\" | grep -m1 -E 'amirlehmam|openwong2kim' | grep -q amirlehmam" _ "$out"
out="$(brig setup --install --yes </dev/null 2>&1)"
expect_has "runs winget" "$(cat "$FAKE_LOG")" "winget install --id jqlang.jq -e --source winget"
expect_not "but never picks the alternative wmux by itself" "$(cat "$FAKE_LOG")" "openwong2kim.wmux"
expect_has "and says how to" "$out" "skipped: winget install --id openwong2kim.wmux -e --source winget (add --wmux-ow"
brig setup --install --yes --wmux-ow </dev/null >/dev/null 2>&1
expect_has "--wmux-ow installs it" "$(cat "$FAKE_LOG")" "winget install --id openwong2kim.wmux -e --source winget"
expect_has "and finds jq where winget put it, though PATH doesn't have it yet" "$out" "ok    jq"
expect_has "doctor still wants wmux" "$out" "FAIL  no terminal backend: On Windows"
out="$(PATH="$TESTS_DIR/fakes/term:$PATH" WMUX=1 WMUX_SURFACE_ID=surf-me brig setup </dev/null 2>&1)"; code=$?
expect_has "inside wmux everything passes" "$out" "ok       wmux (this tab, amirlehmam/wmux)"
expect_has "doctor too" "$out" "all good"
check "exit 0" test "$code" -eq 0
expect_not "no wmux to install from a wmux tab" "$out" "openwong2kim.wmux"
mkdir -p "$E_DIR/up"; printf 'tok\n' >"$E_DIR/up/.wmux-auth-token"
out="$(PATH="$TESTS_DIR/fakes/term:$PATH" WMUX_PTY_ID=pty-me WMUX_WORKSPACE_ID=ws-test TERM_PROGRAM=wmux USERNAME=tester USERPROFILE="$E_DIR/up" brig setup </dev/null 2>&1)"; code=$?
expect_has "inside openwong2kim/wmux too" "$out" "ok       wmux (this tab, openwong2kim/wmux: supported as the fallback)"
expect_has "and doctor names it" "$out" "terminal: wmux-ow (openwong2kim/wmux 4.5.0-fake"
check "exit 0 there too" test "$code" -eq 0
setup_env; only_fakes "$E_DIR/os" winget; PATH="$TESTS_DIR/fakes/win:$E_DIR/os:$PATH"
export LOCALAPPDATA="$E_DIR/la" FAKE_WINGET_DIR="$E_DIR/somewhere-else"
out="$(brig setup --install --yes </dev/null 2>&1)"
expect_has "a tool winget installed out of sight gets a plain instruction" "$out" "jq is installed but this terminal can't see it yet: restart wmux and Claude Code, then run /brigadier setup again."

echo "== line endings"
setup_env "$TESTS_DIR/fakes/os"; os_release 'ID=ubuntu'
inst="$E_DIR/skill"; cp -R "$SKILL_SRC" "$inst"; SKILL="$inst"
printf 'one\r\ntwo\r\n' >>"$inst/worker-protocol.md"
expect_has "doctor flags skill files with CRLF" "$(brig doctor 2>&1)" "1 skill files have Windows line endings (CRLF); run /brigadier setup to fix them"
printf 'BRIG_CTX_PCT=60\r\n' >"$BRIG_HOME/config.env"
out="$(brig setup </dev/null 2>&1)"
expect_has "setup fixes them" "$out" "fixed    Windows line endings in 1 skill files"
check "the file has no CR left" bash -c "! grep -q $'\r' '$inst/worker-protocol.md'"
expect_has "and fixes a CRLF config, keeping the original" "$out" "had Windows line endings (original kept as config.env.bak)"
check "config.env.bak kept" test -f "$BRIG_HOME/config.env.bak"
check "config keeps its setting" grep -qx "BRIG_CTX_PCT=60" "$BRIG_HOME/config.env"
expect_not "doctor is happy afterwards" "$(brig doctor 2>&1)" "Windows line endings"
SKILL="$SKILL_SRC"

echo "== guards"
setup_env "$TESTS_DIR/fakes/os"
expect_has "setup is guarded inside the Brigadier app" "$(BRIGADIER_SESSION=1 brig setup 2>&1)" "doesn't run inside the Brigadier app"
expect_has "workers don't run setup" "$(BRIG_WORKER=w01 brig setup 2>&1)" "workers don't run setup"
expect_has "unknown flags are refused" "$(brig setup --force 2>&1)" "usage: brig setup"

summary
