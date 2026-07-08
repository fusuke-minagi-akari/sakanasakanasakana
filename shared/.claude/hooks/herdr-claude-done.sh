#!/usr/bin/env bash
# Fires on Claude Code Stop -> custom herdr banner + sound.
# Edit TITLE/BODY/POSITION/SOUND below. Safe no-op if herdr not on PATH.
set -euo pipefail

command -v herdr >/dev/null 2>&1 || exit 0

TITLE="Claude done"
BODY="$(basename "${PWD:-session}") finished"
POSITION="bottom-right"   # top-left|top-right|bottom-left|bottom-right
SOUND="done"              # none|done|request

herdr notification show "$TITLE" \
  --body "$BODY" \
  --position "$POSITION" \
  --sound "$SOUND" >/dev/null 2>&1 || true
