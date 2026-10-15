# shellcheck shell=bash
# Shared by the fake package managers: "installing" a tool links a working stand-in into
# $FAKE_INSTALL_DIR (on the test's PATH) and logs the call.
fi_log() { [[ -n "${FAKE_LOG:-}" ]] && printf '%s\n' "$*" >>"$FAKE_LOG"; true; }
fi_install() { # fi_install <dir> <tool>...
  local dir="$1" t src; shift
  mkdir -p "$dir"
  for t in "$@"; do
    case "$t" in
      jq|jqlang.jq) src="$FAKE_REAL_JQ"; t=jq ;;
      tmux) src="$(dirname "${BASH_SOURCE[0]}")/../term/tmux" ;;
      git|Git.Git) src="$FAKE_REAL_GIT"; t=git ;;
      *) continue ;;
    esac
    ln -sf "$src" "$dir/$t"
  done
}
