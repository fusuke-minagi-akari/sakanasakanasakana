#!/usr/bin/env bash
# Claude Code statusline: plugin badge (ponytail/caveman) + status.claude.com dot.
# Wired via settings.json "statusLine.command". Composed HERE rather than by
# editing the caveman plugin script — the plugin cache is overwritten on update.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)          # Claude Code feeds session JSON on stdin
parts=()

# plugin badge — plugin-statusline.sh resolves whichever of ponytail/caveman is
# enabled from installed_plugins.json, so it survives version bumps and swaps.
BADGE="$HOME/.claude/hooks/plugin-statusline.sh"
if [ -f "$BADGE" ]; then
  out=$(printf '%s' "$INPUT" | bash "$BADGE" 2>/dev/null)
  [ -n "$out" ] && parts+=("$out")
fi

if [ -f "$HERE/segment.sh" ]; then
  out=$(bash "$HERE/segment.sh" 2>/dev/null)
  [ -n "$out" ] && parts+=("$out")
fi

printf '%s' "$(IFS=' '; echo "${parts[*]:-}")"
