#!/usr/bin/env bash
# Wait for a herdr Claude Code agent to go idle, then restart it in place so it
# rebinds to the currently-enabled plugin set. --resume keeps the conversation.
#
#   agent-plugin-refresh-watch.sh <pane_id> <label>
#
# Polls every 30s, gives up after MAX_WAIT. Only ever acts on an idle agent:
# a working agent is left alone, an absent one ends the watch. Logs to
# ~/.cache/agent-plugin-refresh/<pane>.log
set -uo pipefail

PANE="${1:?pane_id required}"
LABEL="${2:-$PANE}"
POLL_S=30
MAX_WAIT_S=$((12 * 3600))

LOG_DIR="$HOME/.cache/agent-plugin-refresh"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/${PANE//:/_}.log"

log() { printf '%s  %s\n' "$(date -Is)" "$*" >>"$LOG"; }

# Emits "<status> <session_id>" for PANE, or "absent" when the pane has no agent.
probe() {
  herdr agent list 2>/dev/null | PANE="$PANE" python3 -c '
import sys, json, os
pane = os.environ["PANE"]
try:
    agents = json.load(sys.stdin)["result"]["agents"]
except Exception:
    print("unknown")
    raise SystemExit
hit = [a for a in agents if a.get("pane_id") == pane]
if not hit:
    print("absent")
else:
    a = hit[0]
    print(a.get("agent_status", "unknown"), (a.get("agent_session") or {}).get("value", ""))
'
}

log "watch start ($LABEL)"
waited=0
while :; do
  read -r status sid <<<"$(probe)"

  case "$status" in
    idle)
      if [ -z "$sid" ]; then log "idle but no session id; retrying"; else
        log "idle -> refreshing (session ${sid:0:8})"
        herdr pane run "$PANE" "/exit" >/dev/null 2>&1; sleep 2
        herdr pane send-keys "$PANE" Enter >/dev/null 2>&1; sleep 7
        herdr pane run "$PANE" "claude --resume $sid" >/dev/null 2>&1; sleep 2
        herdr pane send-keys "$PANE" Enter >/dev/null 2>&1; sleep 11
        read -r after _ <<<"$(probe)"
        log "refreshed -> status=$after"
        exit 0
      fi
      ;;
    absent)
      log "agent gone; nothing to refresh"; exit 0 ;;
    working|blocked|unknown)
      : ;;  # keep waiting
  esac

  sleep "$POLL_S"
  waited=$((waited + POLL_S))
  if [ "$waited" -ge "$MAX_WAIT_S" ]; then
    log "gave up after ${MAX_WAIT_S}s still status=$status"
    exit 1
  fi
done
