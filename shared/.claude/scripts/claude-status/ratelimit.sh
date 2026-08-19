#!/usr/bin/env bash
# claude-status rate-limit segment — prints a block-fill bar (filled to used%)
# plus "<elapsed%>/<used%>%" per rate-limit window. Bar color signals pace:
# green if used% trails elapsed% (you're using less than your time share),
# red if used% is running well ahead of elapsed% (burning faster than time
# is passing). Recomputed from live data every statusline render, so the bar
# updates on its own — no separate refresh loop needed.
# Reads Claude Code's session JSON (rate_limits.{five_hour,seven_day}) from stdin.

set -uo pipefail

WINDOW_SECONDS_five_hour=18000     # 5 * 3600
WINDOW_SECONDS_seven_day=604800    # 7 * 86400

RESET=$'\033[0m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
BG_TRACK=$'\033[48;5;238m'   # dim gray track — makes the unfilled part visible; edit to taste

BAR_CHARS=(' ' '▏' '▎' '▍' '▌' '▋' '▊' '▉' '█')
BAR_WIDTH=8

# elapsed_pct <resets_at> <window_seconds> <now> -> integer 0-100
elapsed_pct() {
  local resets_at="$1" window="$2" now="$3"
  local elapsed=$(( now - (resets_at - window) ))
  (( elapsed < 0 )) && elapsed=0
  (( elapsed > window )) && elapsed=$window
  echo $(( elapsed * 100 / window ))
}

# bar <pct 0-100> -> BAR_WIDTH-char block-fill string (eighth-block resolution)
bar() {
  local pct="$1"
  (( pct < 0 )) && pct=0
  (( pct > 100 )) && pct=100
  local eighths=$(( pct * BAR_WIDTH * 8 / 100 ))
  local full=$(( eighths / 8 )) rem=$(( eighths % 8 ))
  local out="" i
  for (( i=0; i<full; i++ )); do out+="█"; done
  if (( full < BAR_WIDTH )); then
    out+="${BAR_CHARS[$rem]}"
    full=$(( full + 1 ))
  fi
  for (( ; full<BAR_WIDTH; full++ )); do out+=" "; done
  printf '%s' "$out"
}

# pace_color <used_pct> <elapsed_pct> -> ANSI color for how used tracks elapsed
pace_color() {
  local used="$1" elapsed="$2" diff=$(( used - elapsed ))
  if (( diff <= 10 )); then printf '%s' "$GREEN"
  elif (( diff <= 25 )); then printf '%s' "$YELLOW"
  else printf '%s' "$RED"
  fi
}

# level_color <pct> -> ANSI color by absolute fill level (no pace concept for ctx)
level_color() {
  local pct="$1"
  if (( pct < 70 )); then printf '%s' "$GREEN"
  elif (( pct < 90 )); then printf '%s' "$YELLOW"
  else printf '%s' "$RED"
  fi
}

# fmt_tokens <n> -> "12", "125K", or "1M"-style compact count
fmt_tokens() {
  local n="$1"
  if (( n >= 1000000 )); then printf '%dM' "$(( n / 1000000 ))"
  elif (( n >= 1000 )); then printf '%dK' "$(( n / 1000 ))"
  else printf '%d' "$n"
  fi
}

render() {
  local json="$1" now="$2"
  local out="" key label used resets window_var window elapsed color

  # ctx — current session's context window usage, resets with /clear (unlike
  # the account-wide 5h/7d rate limits below).
  local ctx_size ctx_used ctx_pct
  ctx_size=$(jq -r '.context_window.context_window_size // empty' <<<"$json")
  if [ -n "$ctx_size" ] && [ "$ctx_size" -gt 0 ]; then
    ctx_used=$(jq -r '(.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0)' <<<"$json")
    ctx_pct=$(( ctx_used * 100 / ctx_size ))
    out="ctx ${BG_TRACK}$(level_color "$ctx_pct")$(bar "$ctx_pct")${RESET} $(fmt_tokens "$ctx_used")/$(fmt_tokens "$ctx_size")"
  fi

  for key_label in "five_hour:5h" "seven_day:7d"; do
    key="${key_label%%:*}"; label="${key_label##*:}"
    used=$(jq -r ".rate_limits.${key}.used_percentage // empty" <<<"$json")
    [ -z "$used" ] && continue
    used=$(printf '%.0f' "$used")
    resets=$(jq -r ".rate_limits.${key}.resets_at // empty" <<<"$json")
    window_var="WINDOW_SECONDS_${key}"
    window="${!window_var}"
    if [ -n "$resets" ]; then
      elapsed=$(elapsed_pct "${resets%.*}" "$window" "$now")
      color=$(pace_color "$used" "$elapsed")
      out="${out:+$out }${label} ${BG_TRACK}${color}$(bar "$used")${RESET} ${elapsed}/${used}%"
    else
      out="${out:+$out }${label}${used}%"
    fi
  done
  printf '%s' "$out"
}

if [ "${1:-}" = "--selftest" ]; then
  ok=1
  [ "$(bar 0)"   = "        " ] || { echo "bar(0) failed: '$(bar 0)'"     >&2; ok=0; }
  [ "$(bar 50)"  = "████    " ] || { echo "bar(50) failed: '$(bar 50)'"   >&2; ok=0; }
  [ "$(bar 100)" = "████████" ] || { echo "bar(100) failed: '$(bar 100)'" >&2; ok=0; }

  [ "$(fmt_tokens 999)" = "999" ]      || { echo "fmt_tokens(999) failed"     >&2; ok=0; }
  [ "$(fmt_tokens 124936)" = "124K" ]  || { echo "fmt_tokens(124936) failed"  >&2; ok=0; }
  [ "$(fmt_tokens 1000000)" = "1M" ]   || { echo "fmt_tokens(1000000) failed" >&2; ok=0; }

  now=1700000000
  json='{"context_window":{"total_input_tokens":124769,"total_output_tokens":167,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":40,"resets_at":'$((now + 9000))'}}}'
  result=$(render "$json" "$now" | sed $'s/\033\\[[0-9;]*m//g')
  case "$result" in
    "ctx "*" 124K/1M "*"5h "*"50/40%") : ;;
    *) echo "render mismatch: '$result'" >&2; ok=0 ;;
  esac

  [ "$ok" = 1 ] && echo "selftest ok: $result" || exit 1
  exit 0
fi

INPUT=$(cat)
render "$INPUT" "$(date +%s)"
