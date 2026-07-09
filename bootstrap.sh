#!/usr/bin/env bash
# bootstrap.sh — install dependencies for this repo, per OS.
#
# Reads the manifests in deps/ and installs what's missing:
#   macOS : brew bundle deps/Brewfile        + pip -r deps/requirements.txt
#   Linux : apt/dnf/pacman deps/packages-apt.txt + pip -r deps/requirements.txt
# With --full also installs optional extras (npm globals, melchior/kitty bits).
#
# Does NOT install (manual — see DEPENDENCIES.md): herdr, the caveman Claude
# plugin, MCP servers, the melchior-headless wrapper, BetterDisplay.
#
# Usage:
#   ./bootstrap.sh            # install core deps for this OS
#   ./bootstrap.sh --dry-run  # print what it would do
#   ./bootstrap.sh --full     # + optional extras
# Run ./install.sh afterwards to link the dotfiles.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0; FULL=0
for a in "$@"; do case "$a" in
  --dry-run) DRY=1 ;;
  --full)    FULL=1 ;;
  -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done

say() { printf '%s\n' "$*"; }
run() { say "  \$ $*"; [ "$DRY" = 1 ] || eval "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
# emit package names from a manifest: strip inline+full-line comments, blanks, trailing ws
manifest() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$REPO/deps/$1" | grep -vE '^[[:space:]]*$'; }

install_macos() {
  if ! have brew; then
    say "!! Homebrew missing. Install: https://brew.sh  then re-run."; exit 1
  fi
  say "== brew bundle (deps/Brewfile) =="
  run "brew bundle --file '$REPO/deps/Brewfile'"
  if [ "$FULL" = 1 ]; then
    say "== optional (--full) =="
    run "brew install uv go-task || true"
    run "brew install --cask kitty betterdisplay || true"
  fi
}

install_linux() {
  local pm="" inst=""
  if   have apt-get; then pm=apt;    inst="sudo apt-get install -y"
  elif have dnf;     then pm=dnf;    inst="sudo dnf install -y"
  elif have pacman;  then pm=pacman; inst="sudo pacman -S --noconfirm"
  else say "!! no supported package manager (apt/dnf/pacman)"; exit 1; fi
  say "== $pm packages (deps/packages-apt.txt; translate names if not apt) =="
  [ "$pm" = apt ] && run "sudo apt-get update"
  # shellcheck disable=SC2046
  run "$inst $(manifest packages-apt.txt | tr '\n' ' ')"
  if [ "$FULL" = 1 ]; then
    say "== optional (--full) =="
    run "$inst xvfb kitty libnss3 libatk1.0-0 libgbm1 libasound2 || true"
    have uv || run "curl -LsSf https://astral.sh/uv/install.sh | sh"
  fi
  say "NOTE: gh/glow may need extra apt repos — see deps/packages-apt.txt notes."
}

install_pip() {
  local py; py=python3; have "$py" || { say "!! python3 missing"; return; }
  say "== pip (deps/requirements.txt) =="
  run "$py -m pip install --user -r '$REPO/deps/requirements.txt'"
}

install_npm_globals() {
  [ "$FULL" = 1 ] || { say "== npm globals: skipped (npx --yes auto-fetches; use --full to pin) =="; return; }
  have npm || { say "!! npm missing — skipping npm globals"; return; }
  say "== npm globals (deps/npm-global.txt) =="
  # shellcheck disable=SC2046
  run "npm install -g $(manifest npm-global.txt | tr '\n' ' ')"
}

case "$(uname -s)" in
  Darwin) install_macos ;;
  Linux)  install_linux ;;
  *) say "unsupported OS: $(uname -s)"; exit 1 ;;
esac
install_pip
install_npm_globals

say ""
say "core deps done. Check herdr (not auto-installed):"
have herdr && say "  herdr: $(command -v herdr)" || say "  herdr: MISSING — install from https://herdr.dev"
say ""
say "next: ./install.sh   # link dotfiles + register service"
