#!/usr/bin/env bash
# Pick one of the 20 most recently active sessions (any directory) and resume it on account a (~/.claude) or b (~/.claude-c).
# usage: claude-swap.sh a|b [extra claude args]
set -eu
acct=${1:-a}; shift || true
files=($(ls -t "$HOME"/.claude/projects/*/*.jsonl | head -20))
for i in "${!files[@]}"; do
  f=${files[$i]}
  title=$(grep -o '"aiTitle":"[^"]*"' "$f" | tail -1 | cut -d'"' -f4)
  dir=$(grep -m1 -o '"cwd":"[^"]*"' "$f" | cut -d'"' -f4)
  printf '%d) %s  %s  [%s]\n' $((i + 1)) "$(date -r "$f" +%H:%M)" "${title:-(untitled)}" "${dir/#$HOME/~}"
done
read -rp "resume which? [1] " n
f=${files[$(( ${n:-1} - 1 ))]}
cd "$(grep -m1 -o '"cwd":"[^"]*"' "$f" | cut -d'"' -f4)"
if [ "$acct" = b ]; then export CLAUDE_CONFIG_DIR="$HOME/.claude-c"; else unset CLAUDE_CONFIG_DIR; fi
exec claude --resume "$(basename "$f" .jsonl)" "$@"
