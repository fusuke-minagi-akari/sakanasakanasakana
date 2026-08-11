#!/usr/bin/env bash
# Self-check for the per-session ponytail badge: run the UserPromptSubmit hook,
# then the statusline, in a throwaway CLAUDE_CONFIG_DIR and assert what renders.
#   bash test-ponytail-session-mode.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/plugins"
cp "$HOME/.claude/settings.json" "$TMP/settings.json"
cp "$HOME/.claude/plugins/installed_plugins.json" "$TMP/plugins/"
export CLAUDE_CONFIG_DIR="$TMP" XDG_CONFIG_HOME="$TMP/xdg"   # no ponytail config -> default full
unset PONYTAIL_DEFAULT_MODE

prompt() { printf '{"session_id":"%s","prompt":"%s"}' "$1" "$2" | bash "$HERE/ponytail-session-mode.sh"; }
badge()  { printf '{"session_id":"%s"}' "$1" | bash "$HERE/plugin-statusline.sh" | sed 's/\x1b\[[0-9;]*m//g'; }

check() { [ "$2" = "$3" ] || { echo "FAIL $1: got '$2' want '$3'"; exit 1; }; echo "ok   $1"; }

check "untracked session shows the default" "$(badge sA)" "[PONYTAIL]"

prompt sA "/ponytail ultra"
check "switch is recorded for that session" "$(badge sA)" "[PONYTAIL:ULTRA]"
check "other panes are unaffected"          "$(badge sB)" "[PONYTAIL]"

prompt sB "stop ponytail"
check "deactivation is session-scoped"      "$(badge sB)" ""
check "the ultra pane survives it"          "$(badge sA)" "[PONYTAIL:ULTRA]"   # this was the bug

prompt sA "/ponytail"
check "bare /ponytail is report-only"       "$(badge sA)" "[PONYTAIL:ULTRA]"
prompt sA "/ponytail default lite"
check "/ponytail default leaves session be" "$(badge sA)" "[PONYTAIL:ULTRA]"
prompt sA "/ponytail lite"
check "lite renders its level"              "$(badge sA)" "[PONYTAIL:LITE]"

printf 'evil\033]0;pwned\007' > "$TMP/ponytail-modes/sC"
check "junk in the flag renders nothing"    "$(badge sC)" ""

echo "all checks passed"
