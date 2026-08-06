#!/usr/bin/env bash
# Claude Code statusline: caveman badge + status.claude.com dot.
# Wired via settings.json "statusLine.command". Composed HERE rather than by
# editing the caveman plugin script — the plugin cache is overwritten on update.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)          # Claude Code feeds session JSON on stdin
parts=()

# caveman badge — the plugin cache path carries a version hash, and the layout
# differs between plugin versions (…/<hash>/hooks/ vs …/<hash>/src/hooks/), so
# glob both instead of hardcoding either.
for c in "$HOME"/.claude/plugins/cache/caveman/caveman/*/hooks/caveman-statusline.sh \
         "$HOME"/.claude/plugins/cache/caveman/caveman/*/src/hooks/caveman-statusline.sh; do
  [ -f "$c" ] || continue
  out=$(printf '%s' "$INPUT" | bash "$c" 2>/dev/null)
  [ -n "$out" ] && parts+=("$out")
  break
done

if [ -f "$HERE/segment.sh" ]; then
  out=$(bash "$HERE/segment.sh" 2>/dev/null)
  [ -n "$out" ] && parts+=("$out")
fi

printf '%s' "$(IFS=' '; echo "${parts[*]:-}")"
