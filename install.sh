#!/usr/bin/env bash
# install.sh — link herdr/Claude customizations from this repo into $HOME.
#
# Symlinks every plain file under home/ into the matching path in $HOME, so
# edits in the repo are live immediately. Existing real files are moved to
# ~/backup (mirrored tree) before a link replaces them; nothing is clobbered.
#
# Special cases:
#   * The launchd plist is a template (…​.plist.tmpl). It is RENDERED (not
#     linked) with $HOME baked in, because launchd needs absolute paths.
#   * The herdr Claude *state* hook (~/.claude/hooks/herdr-agent-state.sh) is
#     managed by herdr itself and is intentionally NOT tracked here — run
#     `herdr integration install claude` to (re)create it. See README.
#
# Usage:
#   ./install.sh            # link everything + render plist + load launchd job
#   ./install.sh --dry-run  # print actions, change nothing
#   ./install.sh --no-load  # link/render but don't (re)load the launchd job
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO/home"
BACKUP="$HOME/backup"
DRY=0
LOAD=1

for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --no-load) LOAD=0 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown arg: $a" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
run() { if [ "$DRY" = 1 ]; then say "  [dry] $*"; else eval "$*"; fi; }

# link SRC_FILE DEST — back up an existing real DEST, then symlink SRC_FILE→DEST.
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

say "dotfiles: linking from $SRC"

# --- symlink every tracked plain file except the plist template ---
while IFS= read -r src; do
  case "$src" in *.plist.tmpl) continue ;; esac
  rel="${src#"$SRC"/}"
  link "$src" "$HOME/$rel"
done < <(find "$SRC" -type f | sort)

# --- render the launchd plist (absolute paths → can't be a symlink) ---
TMPL="$SRC/Library/LaunchAgents/dev.herdr.branchlabels.plist.tmpl"
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

  # --- load / restart the launchd job (macOS) ---
  if [ "$LOAD" = 1 ] && [ "$DRY" = 0 ] && command -v launchctl >/dev/null 2>&1; then
    launchctl bootout "gui/$UID/dev.herdr.branchlabels" 2>/dev/null || true
    launchctl bootstrap "gui/$UID" "$PLIST" 2>/dev/null || true
    launchctl kickstart -k "gui/$UID/dev.herdr.branchlabels" 2>/dev/null || true
    say "  launchd: (re)started dev.herdr.branchlabels"
  fi
fi

say "done. herdr state hook is herdr-managed — run: herdr integration install claude"
