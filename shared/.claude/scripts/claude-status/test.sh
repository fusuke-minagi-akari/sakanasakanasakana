#!/usr/bin/env bash
# test.sh — exercise every claude-status render path without waiting for a real
# outage. Fixtures are built locally (no network), so this works offline.
#
#   test.sh render          render every scenario in a throwaway cache dir
#   test.sh notify          same, but let transitions fire real notifications
#   test.sh pin <scenario>  freeze the LIVE statusline in that state (survives
#                           the poll daemon — it honors the pin file)
#   test.sh unpin           back to real status
#   test.sh state           show pin / cache age / last indicator / service state
#
# Scenarios: ok minor major critical maintenance incident multi unknown

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLL="$HERE/poll.sh"
LIVE_CACHE="${CLAUDE_STATUS_CACHE_DIR:-$HOME/.claude/cache/claude-status}"
TMP="${TMPDIR:-/tmp}/claude-status-test.$$"

SCENARIOS=(ok minor major critical maintenance incident multi unknown)

case "$(uname -s)" in
  Darwin) mtime() { stat -f %m "$1" 2>/dev/null || echo 0; } ;;
  *)      mtime() { stat -c %Y "$1" 2>/dev/null || echo 0; } ;;
esac

# Statuspage summary.json skeleton — same shape as the real endpoint.
base_json() {
  cat <<'JSON'
{
  "page": {"id": "tymt9n04zgry", "name": "Claude"},
  "components": [
    {"id": "c1", "name": "claude.ai", "status": "operational", "group": false},
    {"id": "c2", "name": "Claude Console (platform.claude.com)", "status": "operational", "group": false},
    {"id": "c3", "name": "Claude API (api.anthropic.com)", "status": "operational", "group": false},
    {"id": "c4", "name": "Claude Code", "status": "operational", "group": false},
    {"id": "c5", "name": "Claude Cowork", "status": "operational", "group": false},
    {"id": "c6", "name": "Claude for Government", "status": "operational", "group": false}
  ],
  "incidents": [],
  "scheduled_maintenances": [],
  "status": {"indicator": "none", "description": "All Systems Operational"}
}
JSON
}

# fixture <scenario> -> path of a summary.json for that scenario
fixture() {
  local s="$1" out="$TMP/$1.json"
  mkdir -p "$TMP"
  case "$s" in
    ok)     base_json >"$out" ;;
    minor)  base_json | jq '.status={"indicator":"minor","description":"Partially Degraded Service"}
              | (.components[] | select(.name=="Claude Code") | .status)="degraded_performance"' >"$out" ;;
    major)  base_json | jq '.status={"indicator":"major","description":"Partial System Outage"}
              | (.components[] | select(.name=="Claude Code") | .status)="major_outage"' >"$out" ;;
    critical) base_json | jq '.status={"indicator":"critical","description":"Major Service Outage"}
              | (.components[] | select(.name|startswith("Claude API")) | .status)="major_outage"' >"$out" ;;
    maintenance) base_json | jq '.status={"indicator":"maintenance","description":"Service Under Maintenance"}
              | (.components[] | select(.name=="Claude Console (platform.claude.com)") | .status)="under_maintenance"' >"$out" ;;
    incident) base_json | jq '.incidents=[{"name":"Elevated error rates on Claude Code","status":"investigating","impact":"minor"}]' >"$out" ;;
    multi)  base_json | jq '.status={"indicator":"major","description":"Partial System Outage"}
              | (.components[] | select(.name=="Claude Code") | .status)="major_outage"
              | (.components[] | select(.name|startswith("Claude API")) | .status)="partial_outage"
              | .incidents=[{"name":"API and Code errors","status":"identified","impact":"major"}]' >"$out" ;;
    unknown) echo '{"status":{"indicator":"weird-new-value","description":"Something New"},"components":[],"incidents":[]}' >"$out" ;;
    *) echo "unknown scenario: $s (have: ${SCENARIOS[*]})" >&2; return 2 ;;
  esac
  printf '%s' "$out"
}

# render_one <scenario> [notify] -> prints the segment this scenario produces
render_one() {
  local s="$1" notify="${2:-0}" fx cache
  fx=$(fixture "$s") || return 2
  cache="$TMP/cache-$s"
  mkdir -p "$cache"
  CLAUDE_STATUS_CACHE_DIR="$cache" CLAUDE_STATUS_NOTIFY="$notify" \
    CLAUDE_STATUS_API="file://$fx" bash "$POLL" >/dev/null 2>&1
  cat "$cache/segment.txt" 2>/dev/null
}

cmd_render() {
  local notify="${1:-0}"
  printf 'scenario     segment\n'
  printf -- '------------ -------------------------\n'
  for s in "${SCENARIOS[@]}"; do
    printf '%-12s %s\n' "$s" "$(render_one "$s" "$notify")"
  done
  # stale path: an old cache file must gray out and trigger a bg refresh
  local cache="$TMP/cache-stale"
  mkdir -p "$cache"
  printf '\033[32m●\033[0m' >"$cache/segment.txt"
  printf '%-12s %s\n' "stale" \
    "$(CLAUDE_STATUS_CACHE_DIR="$cache" CLAUDE_STATUS_STALE_AFTER=-1 bash "$HERE/segment.sh")"
  printf '%-12s %s\n' "no-cache" \
    "$(CLAUDE_STATUS_CACHE_DIR="$TMP/cache-empty" bash "$HERE/segment.sh")"
  rm -rf "$TMP"
}

cmd_notify() {
  echo "Firing real notifications: ok -> critical -> ok"
  local cache="$TMP/cache-notify" fx
  mkdir -p "$cache"
  for s in ok critical ok; do
    fx=$(fixture "$s")
    CLAUDE_STATUS_CACHE_DIR="$cache" CLAUDE_STATUS_NOTIFY=1 \
      CLAUDE_STATUS_API="file://$fx" bash "$POLL" >/dev/null 2>&1
    printf '  %-9s -> %s\n' "$s" "$(cat "$cache/segment.txt")"
    sleep 1
  done
  echo "transitions logged in $cache/poll.log:"
  grep transition "$cache/poll.log" 2>/dev/null | sed 's/^/  /'
  rm -rf "$TMP"
}

cmd_pin() {
  local s="${1:-}"
  [ -z "$s" ] && { echo "usage: test.sh pin <${SCENARIOS[*]}>" >&2; exit 2; }
  local seg; seg=$(render_one "$s")
  [ -z "$seg" ] && { echo "could not render scenario: $s" >&2; exit 2; }
  mkdir -p "$LIVE_CACHE"
  printf '%s' "$seg" >"$LIVE_CACHE/pin"
  printf '%s' "$seg" >"$LIVE_CACHE/segment.txt"
  rm -rf "$TMP"
  echo "pinned: $seg"
  echo "statusline shows this until: test.sh unpin"
}

cmd_unpin() {
  rm -f "$LIVE_CACHE/pin"
  bash "$POLL" >/dev/null 2>&1
  echo "unpinned. live: $(cat "$LIVE_CACHE/segment.txt" 2>/dev/null)"
}

cmd_state() {
  echo "cache dir : $LIVE_CACHE"
  if [ -f "$LIVE_CACHE/pin" ]; then echo "pin       : ACTIVE ($(cat "$LIVE_CACHE/pin"))"; else echo "pin       : none"; fi
  if [ -f "$LIVE_CACHE/segment.txt" ]; then
    echo "segment   : $(cat "$LIVE_CACHE/segment.txt")  (age $(( $(date +%s) - $(mtime "$LIVE_CACHE/segment.txt") ))s)"
  else
    echo "segment   : (none yet)"
  fi
  echo "indicator : $(cat "$LIVE_CACHE/last-indicator" 2>/dev/null || echo n/a)"
  local svc
  case "$(uname -s)" in
    Darwin)
      if out=$(launchctl print "gui/$UID/dev.claude.statuspoll" 2>/dev/null); then
        svc="loaded ($(sed -n 's/.*state = //p' <<<"$out" | head -1), runs=$(sed -n 's/.*runs = //p' <<<"$out" | head -1))"
      else svc="not loaded"; fi ;;
    *)
      svc="$(systemctl --user is-active claude-status.timer 2>/dev/null || echo "not loaded")" ;;
  esac
  echo "service   : $svc"
  tail -3 "$LIVE_CACHE/poll.log" 2>/dev/null | sed 's/^/log       : /'
}

case "${1:-render}" in
  render) cmd_render 0 ;;
  notify) cmd_notify ;;
  pin)    cmd_pin "${2:-}" ;;
  unpin)  cmd_unpin ;;
  state)  cmd_state ;;
  -h|--help) sed -n '2,16p' "$0" ;;
  *) echo "unknown command: $1" >&2; sed -n '2,16p' "$0"; exit 2 ;;
esac
