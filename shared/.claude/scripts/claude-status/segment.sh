#!/usr/bin/env bash
# claude-status statusline segment — prints the cached dot. NEVER does network I/O
# inline (Claude Code re-renders the statusline every ~300ms); if the cache is
# stale it kicks off a detached poll and prints the stale value dimmed.

set -uo pipefail

CACHE_DIR="${CLAUDE_STATUS_CACHE_DIR:-$HOME/.claude/cache/claude-status}"
SEGMENT="$CACHE_DIR/segment.txt"
POLL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/poll.sh"
STALE_AFTER="${CLAUDE_STATUS_STALE_AFTER:-180}"   # seconds before cache counts as stale
LOCK="$CACHE_DIR/poll.lock"

mkdir -p "$CACHE_DIR"

case "$(uname -s)" in
  Darwin) mtime() { stat -f %m "$1" 2>/dev/null || echo 0; } ;;
  *)      mtime() { stat -c %Y "$1" 2>/dev/null || echo 0; } ;;
esac

refresh_bg() {
  # mkdir is the atomic lock primitive (macOS has no flock).
  if mkdir "$LOCK" 2>/dev/null; then
    ( bash "$POLL" >/dev/null 2>&1; rmdir "$LOCK" 2>/dev/null ) &
    disown 2>/dev/null
  elif [ -d "$LOCK" ]; then
    # Drop a lock older than 60s (crashed poll).
    local age; age=$(( $(date +%s) - $(mtime "$LOCK") ))
    [ "$age" -gt 60 ] && rmdir "$LOCK" 2>/dev/null
  fi
  return 0
}

if [ ! -f "$SEGMENT" ]; then
  refresh_bg
  printf '\033[90m●\033[0m'
  exit 0
fi

age=$(( $(date +%s) - $(mtime "$SEGMENT") ))
if [ "$age" -gt "$STALE_AFTER" ]; then
  refresh_bg
  # stale -> gray, original colors stripped
  printf '\033[90m%s\033[0m' "$(sed $'s/\033\\[[0-9;]*m//g' "$SEGMENT")"
else
  cat "$SEGMENT"
fi
