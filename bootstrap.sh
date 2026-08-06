#!/usr/bin/env bash
# bootstrap.sh — OPTIONAL feature-extra dependencies (Claude Code power features).
#
# The primary installer is ./install.sh (+ lib/deps.sh + packages/*.txt): it
# installs the terminal stack — herdr, kitty, and the CLI tools `show` and the
# branch-labels daemon need (glow chafa mpv jq gh git file). Run that first.
#
# THIS script adds only the extras that terminal stack doesn't cover, needed for
# the Claude Code diagram/PDF/table features:
#   * node          — /diagram, kalmia PNG, report (via npx)
#   * python3       — skills (stdlib only; no pip deps)
#   * npm globals   — @mermaid-js/mermaid-cli, md-to-pdf (deps/npm-global.txt);
#                     OPTIONAL — npx --yes auto-fetches these on first use.
#
# It NEVER touches the install.sh / lib/deps.sh / packages/ build. Additive only.
# See DEPENDENCIES.md for the full functionality->dependency matrix.
#
# Usage:
#   ./bootstrap.sh            # install missing feature-extras for this OS
#   ./bootstrap.sh --dry-run  # print what it would do
#   ./bootstrap.sh --npm      # also install the npm globals (else left to npx)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0; NPM=0
for a in "$@"; do case "$a" in
  --dry-run) DRY=1 ;;
  --npm)     NPM=1 ;;
  -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done

say() { printf '%s\n' "$*"; }
run() { say "  \$ $*"; [ "$DRY" = 1 ] || eval "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
manifest() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$REPO/deps/$1" | grep -vE '^[[:space:]]*$'; }

# pm_install <pkg...> — install via the OS package manager (only for what's missing here)
pm_install() {
  case "$(uname -s)" in
    Darwin) have brew || { say "!! Homebrew missing (https://brew.sh)"; return 1; }
            run "brew install $*" ;;
    Linux)  if   have apt-get; then run "sudo apt-get install -y $*"
            elif have dnf;     then run "sudo dnf install -y $*"
            elif have pacman;  then run "sudo pacman -S --needed --noconfirm $*"
            else say "!! no apt/dnf/pacman"; return 1; fi ;;
  esac
}

say "bootstrap: feature-extras (run ./install.sh first for the terminal stack)"

# node (for npx: mermaid-cli, md-to-pdf)
have node || { say "node missing — installing"; pm_install node || pm_install nodejs npm || true; }
have node && say "  ok    node ($(command -v node))"

# python3 (skills — stdlib only, so nothing to pip install)
have python3 || { say "python3 missing — installing"; pm_install python3 || pm_install python@3.12 || true; }
have python3 && say "  ok    python3 ($(command -v python3))"

# npm globals — optional; npx --yes auto-fetches otherwise
if [ "$NPM" = 1 ]; then
  if have npm; then
    say "npm globals: deps/npm-global.txt"
    # shellcheck disable=SC2046
    run "npm install -g $(manifest npm-global.txt | tr '\n' ' ')"
  else say "!! npm missing — skipping npm globals"; fi
else
  say "npm globals: skipped (npx --yes auto-fetches; use --npm to pin)"
fi

say ""
say "feature-extras done. CJK table fonts: macOS ships Hiragino; Linux needs fonts-noto-cjk."
