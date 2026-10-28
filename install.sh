#!/usr/bin/env bash
# vela bootstrap: puts the `vela` command on your PATH, then runs `vela install`
# (distro packages, mise, PHP, nginx, DNS). Every argument is passed to `vela install`.
#   ./install.sh [--php=8.5,8.4] [--node=ask|lts|skip] [--xdebug=ask|yes|no] [--addons=ask|none|...] [--yes] [--deps-only]
#   curl -fsSL https://raw.githubusercontent.com/iniandrew/vela/main/install.sh | bash
set -euo pipefail

VELA_REPO=${VELA_REPO:-https://github.com/iniandrew/vela.git}
VELA_SRC=${VELA_SRC:-$HOME/.local/share/vela/src}

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ $(uname -s) == Linux ]] || die "Linux only (macOS has the real Herd)."
(( EUID != 0 )) || [[ " $* " == *" --deps-only "* ]] || die "do not run as root."

HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)
if [[ -n $HERE && -x $HERE/bin/vela ]]; then
  VELA_BIN=$HERE/bin/vela
else
  command -v git >/dev/null || die "git is required to fetch vela (install it, then rerun)."
  if [[ -d $VELA_SRC/.git ]]; then git -C "$VELA_SRC" pull --ff-only
  else mkdir -p "$(dirname "$VELA_SRC")" && git clone --depth 1 "$VELA_REPO" "$VELA_SRC"; fi
  VELA_BIN=$VELA_SRC/bin/vela
fi

mkdir -p "$HOME/.local/bin"
ln -sfn "$VELA_BIN" "$HOME/.local/bin/vela"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) warn "$HOME/.local/bin is not on PATH; add it to your shell profile." ;; esac

say "running: vela install $*"
exec "$HOME/.local/bin/vela" install "$@"
