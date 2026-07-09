#!/usr/bin/env bash
# install.sh — link this repo's dotfiles into $HOME.
#
# Layout: files are grouped by OS applicability, each mirroring $HOME:
#   shared/   linked on every OS
#   macos/    linked only on Darwin   (launchd, md5, Homebrew paths)
#   linux/    linked only on Linux    (systemd, md5sum) — add units here
# The active set = shared/ + <detected-os>/.
#
# Rules:
#   * Plain files are SYMLINKED into $HOME (edit in repo = live instantly).
#     An existing real file is moved to ~/backup/<relpath> first; never clobbered.
#   * *.plist.tmpl is RENDERED (not linked) with $HOME baked in — launchd needs
#     absolute paths — then the launchd job is (re)loaded.
#   * *.example.* is SEEDED: copied to its de-example'd name only if that target
#     does not exist. Per-user configs (Slack/Notion ids, ssh hosts) stay local
#     and are never overwritten. Fill them in after first install.
#
# Not handled here: ~/.claude/hooks/herdr-agent-state.sh is herdr-managed —
# run `herdr integration install claude` to create it. See README.
#
# Usage:
#   ./install.sh            # install deps + link + render plist + seed + load launchd
#   ./install.sh --dry-run  # print actions, change nothing
#   ./install.sh --no-load  # skip the launchd (re)load step
#   ./install.sh --no-deps  # skip dependency install (herdr/kitty/CLI tools)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP="$HOME/backup"
DRY=0
LOAD=1
DEPS=1

for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --no-load) LOAD=0 ;;
    --no-deps) DEPS=0 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown arg: $a" >&2; exit 2 ;;
  esac
done

case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux)  OS=linux ;;
  *)      OS=unknown ;;
esac
LAYERS=(shared "$OS")

say() { printf '%s\n' "$*"; }
run() { if [ "$DRY" = 1 ]; then say "  [dry] $*"; else eval "$*"; fi; }

# link SRC DEST — back up an existing real DEST, then symlink SRC->DEST.
link() {
  local src="$1" dest="$2"
  run "mkdir -p '$(dirname "$dest")'"
  if [ -L "$dest" ]; then
    [ "$(readlink "$dest")" = "$src" ] && { say "  ok    $dest"; return; }
    run "rm -f '$dest'"
  elif [ -e "$dest" ]; then
    local bdir; bdir="$BACKUP/${dest#"$HOME"/}"
    run "mkdir -p '$(dirname "$bdir")'"
    run "mv '$dest' '$bdir'"
    say "  saved $dest -> $bdir"
  fi
  run "ln -s '$src' '$dest'"
  say "  link  $dest"
}

# seed SRC DEST — copy SRC to DEST only if DEST is missing.
seed() {
  local src="$1" dest="$2"
  if [ -e "$dest" ]; then say "  keep  $dest (exists)"; return; fi
  run "mkdir -p '$(dirname "$dest")'"
  run "cp '$src' '$dest'"
  say "  seed  $dest (fill in your values)"
}

# --- dependencies (herdr, kitty, CLI tools) before linking ---
# State-aware: installs on a bare machine, fills gaps on a half-built one,
# cleans + reinstalls corrupt pieces, skips anything already healthy.
if [ "$DEPS" = 1 ] && [ "$OS" != unknown ]; then
  # shellcheck source=lib/deps.sh
  . "$REPO/lib/deps.sh"
  install_deps
else
  say "deps: skipped"
fi

for layer in "${LAYERS[@]}"; do
  base="$REPO/$layer"
  [ -d "$base" ] || continue
  say "dotfiles: $layer -> \$HOME"
  while IFS= read -r src; do
    rel="${src#"$base"/}"
    case "$src" in
      *.plist.tmpl) continue ;;                        # rendered below
      *.example.*)
        # strip the ".example" marker from the basename for the target
        d="$(dirname "$rel")"; b="$(basename "$rel")"
        seed "$src" "$HOME/$d/${b/.example/}" ;;
      *) link "$src" "$HOME/$rel" ;;
    esac
  done < <(find "$base" -type f | sort)
done

# --- render launchd plist(s) on macOS ---
if [ "$OS" = macos ]; then
  TMPL="$REPO/macos/Library/LaunchAgents/dev.herdr.branchlabels.plist.tmpl"
  PLIST="$HOME/Library/LaunchAgents/dev.herdr.branchlabels.plist"
  if [ -f "$TMPL" ]; then
    say "dotfiles: rendering $PLIST"
    if [ "$DRY" = 1 ]; then
      say "  [dry] sed 's|__HOME__|$HOME|g' '$TMPL' > '$PLIST'"
    else
      mkdir -p "$(dirname "$PLIST")"
      sed "s|__HOME__|$HOME|g" "$TMPL" > "$PLIST"
      say "  wrote $PLIST"
    fi
    if [ "$LOAD" = 1 ] && [ "$DRY" = 0 ] && command -v launchctl >/dev/null 2>&1; then
      launchctl bootout   "gui/$UID/dev.herdr.branchlabels" 2>/dev/null || true
      launchctl bootstrap "gui/$UID" "$PLIST"               2>/dev/null || true
      launchctl kickstart -k "gui/$UID/dev.herdr.branchlabels" 2>/dev/null || true
      say "  launchd: (re)started dev.herdr.branchlabels"
    fi
  fi
fi

say ""
say "done. Next: herdr integration install claude   # (re)creates the herdr-managed state hook"
