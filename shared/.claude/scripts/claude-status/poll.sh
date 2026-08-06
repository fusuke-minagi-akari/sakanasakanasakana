#!/usr/bin/env bash
# claude-status poller — fetches https://status.claude.com Statuspage API,
# caches a rendered statusline segment, and fires a notification on transitions.
# Cross-OS: macOS (launchd + osascript) and Linux (systemd --user + notify-send).
# herdr notifications are used on both when herdr is on PATH.
#
#   poll.sh            single fetch + cache (+ notify on change)   <- service entrypoint
#   poll.sh --loop     forever loop, $CLAUDE_STATUS_INTERVAL apart
#   poll.sh --print    single fetch, then print segment + human summary
#
# Env: CLAUDE_STATUS_API (override URL; file:// fixtures work — see test.sh)
#      CLAUDE_STATUS_CACHE_DIR, CLAUDE_STATUS_NOTIFY=0, CLAUDE_STATUS_INTERVAL

set -uo pipefail

API="${CLAUDE_STATUS_API:-https://status.claude.com/api/v2/summary.json}"
CACHE_DIR="${CLAUDE_STATUS_CACHE_DIR:-$HOME/.claude/cache/claude-status}"
SUMMARY="$CACHE_DIR/summary.json"
SEGMENT="$CACHE_DIR/segment.txt"
STATE="$CACHE_DIR/last-indicator"
PIN="$CACHE_DIR/pin"
LOG="$CACHE_DIR/poll.log"
INTERVAL="${CLAUDE_STATUS_INTERVAL:-60}"
NOTIFY="${CLAUDE_STATUS_NOTIFY:-1}"

mkdir -p "$CACHE_DIR"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"; }

# Long Statuspage component names -> short statusline labels.
short_name() {
  case "$1" in
    "Claude Code") echo "Code" ;;
    "Claude API (api.anthropic.com)") echo "API" ;;
    "Claude Console (platform.claude.com)") echo "Console" ;;
    "claude.ai") echo "Web" ;;
    "Claude Cowork") echo "Cowork" ;;
    "Claude for Government") echo "Gov" ;;
    *) echo "$1" ;;
  esac
}

# render <summary-json> -> ANSI segment on stdout
render() {
  local json="$1"
  local indicator desc names incidents raw color text

  indicator=$(jq -r '.status.indicator // "unknown"' <<<"$json")
  desc=$(jq -r '.status.description // "unknown"' <<<"$json")
  incidents=$(jq -r '[.incidents[]? | select(.status != "resolved" and .status != "postmortem")] | length' <<<"$json")

  # Non-operational leaf components (groups carry no real status).
  raw=$(jq -r '.components[]? | select((.group // false) | not) | select(.status != "operational") | .name' <<<"$json")
  names=""
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    names="${names:+$names/}$(short_name "$n")"
  done <<<"$raw"

  case "$indicator" in
    none)        color=32 ;;   # green
    minor)       color=33 ;;   # yellow
    major)       color=31 ;;   # red
    critical)    color=31 ;;
    maintenance) color=34 ;;   # blue
    *)           color=90 ;;   # gray
  esac

  text=""
  if [ -n "$names" ]; then
    case "$indicator" in
      major|critical) text=" $names outage" ;;
      maintenance)    text=" $names maint" ;;
      *)              text=" $names degraded" ;;
    esac
  elif [ "$indicator" != "none" ]; then
    text=" $desc"
  elif [ "${incidents:-0}" -gt 0 ] 2>/dev/null; then
    color=33
    text=" incident"
  fi

  printf '\033[%sm●%s\033[0m' "$color" "$text"
}

desktop_notify() {
  local title="$1" body="$2"
  case "$(uname -s)" in
    Darwin)
      command -v osascript >/dev/null 2>&1 && \
        osascript -e "display notification \"$(sed 's/"/\\"/g' <<<"$body")\" with title \"$(sed 's/"/\\"/g' <<<"$title")\"" >/dev/null 2>&1
      ;;
    *)
      command -v notify-send >/dev/null 2>&1 && \
        notify-send "$title" "$body" >/dev/null 2>&1
      ;;
  esac
  return 0
}

notify_change() {
  local old="$1" new="$2" desc="$3" detail="$4" title body
  [ "$NOTIFY" = "1" ] || return 0
  [ "$old" = "$new" ] && return 0

  if [ "$new" = "none" ]; then
    title="Claude status recovered"; body="All Systems Operational"
  else
    title="Claude status: $desc"; body="${detail:-$new}"
  fi

  command -v herdr >/dev/null 2>&1 && \
    herdr notification show "$title" --body "$body" --position bottom-right --sound request >/dev/null 2>&1
  desktop_notify "$title" "$body"
  log "transition $old -> $new ($desc)"
}

fetch_once() {
  # A pin (test.sh pin <state>) freezes the segment; keep it fresh so the
  # statusline's staleness check never grays it out mid-test.
  if [ -f "$PIN" ]; then
    cp -f "$PIN" "$SEGMENT.tmp" && mv -f "$SEGMENT.tmp" "$SEGMENT"
    return 0
  fi

  local json seg indicator desc detail old
  json=$(curl -fsSL --max-time 8 -H 'User-Agent: claude-status-statusline' "$API" 2>>"$LOG")
  if [ -z "$json" ] || ! jq -e '.status.indicator' >/dev/null 2>&1 <<<"$json"; then
    log "fetch failed"
    return 1
  fi

  printf '%s' "$json" >"$SUMMARY.tmp" && mv -f "$SUMMARY.tmp" "$SUMMARY"
  seg=$(render "$json")
  printf '%s' "$seg" >"$SEGMENT.tmp" && mv -f "$SEGMENT.tmp" "$SEGMENT"

  indicator=$(jq -r '.status.indicator // "unknown"' <<<"$json")
  desc=$(jq -r '.status.description // "unknown"' <<<"$json")
  detail=$(jq -r '[.components[]? | select((.group // false) | not) | select(.status != "operational") | "\(.name): \(.status)"] | join(", ")' <<<"$json")
  [ -z "$detail" ] && detail=$(jq -r '[.incidents[]? | select(.status != "resolved") | .name] | join("; ")' <<<"$json")

  old=$(cat "$STATE" 2>/dev/null || echo "")
  [ -n "$old" ] && notify_change "$old" "$indicator" "$desc" "$detail"
  printf '%s' "$indicator" >"$STATE.tmp" && mv -f "$STATE.tmp" "$STATE"
  return 0
}

case "${1:-}" in
  --loop)
    while true; do fetch_once; sleep "$INTERVAL"; done
    ;;
  --print)
    fetch_once
    printf '%s\n' "$(cat "$SEGMENT" 2>/dev/null)"
    if [ -f "$SUMMARY" ]; then
      jq -r '"\(.status.description)\n" + ([.components[] | select((.group // false) | not) | "  \(.name): \(.status)"] | join("\n"))' "$SUMMARY"
      jq -r 'if (([.incidents[]? | select(.status != "resolved")] | length) > 0) then "\nActive incidents:\n" + ([.incidents[] | select(.status != "resolved") | "  [\(.impact)] \(.name) — \(.status)"] | join("\n")) else "" end' "$SUMMARY"
    fi
    if [ -f "$PIN" ]; then echo "(PINNED — run: claude-status/test.sh unpin)"; fi
    ;;
  *)
    fetch_once
    ;;
esac
