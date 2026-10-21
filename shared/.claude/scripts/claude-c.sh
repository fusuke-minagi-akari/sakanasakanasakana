#!/usr/bin/env bash
# Backup Claude account (~/.claude-c) sharing state with the main one (~/.claude),
# so a session that hits its limit can be resumed on the other account.
# Idempotent: first run sets it up, later runs re-link and re-sync (claude-c-sync).
#   - shared via symlink: transcripts + memory (projects/), history, settings, skills...
#   - kept per account:   .claude.json (login), keychain/credentials, daemon/, usage stats
#   - copied A→B each run: user-scope mcpServers and trusted folders from ~/.claude.json
# Never open the same session on both accounts at once (both append to one transcript).
set -euo pipefail

A="$HOME/.claude"
B="$HOME/.claude-c"
SHARED=(projects file-history history.jsonl paste-cache session-env shell-snapshots
        CLAUDE.md settings.json settings.local.json hooks scripts skills commands plugins
        budgets jobs backups sessions ide)

mkdir -p "$B"
for f in "${SHARED[@]}"; do
  if [ ! -e "$A/$f" ]; then
    echo "skip $f (not in $A yet; re-run later)"
  elif [ -e "$B/$f" ] && [ ! -L "$B/$f" ]; then
    echo "skip $f ($B/$f is a real file; move it away to share)"
  else
    ln -sfn "$A/$f" "$B/$f"
  fi
done

python3 - "$HOME/.claude.json" "$B/.claude.json" <<'EOF'
import json, os, sys, tempfile
src, dst = sys.argv[1:]
a = json.load(open(src)) if os.path.exists(src) else {}
b = json.load(open(dst)) if os.path.exists(dst) else {}
b["mcpServers"] = {**b.get("mcpServers", {}), **a.get("mcpServers", {})}
trusted = [p for p, c in a.get("projects", {}).items() if c.get("hasTrustDialogAccepted")]
for p in trusted:
    b.setdefault("projects", {}).setdefault(p, {})["hasTrustDialogAccepted"] = True
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(dst))
with os.fdopen(fd, "w") as fh:
    json.dump(b, fh, indent=2)
os.chmod(tmp, 0o600)
os.replace(tmp, dst)
print(f"synced: mcpServers={sorted(b['mcpServers'])} trusted_dirs={len(trusted)}")
EOF

case "${SHELL##*/}" in zsh) RC="$HOME/.zshrc" ;; *) RC="$HOME/.bashrc" ;; esac
touch "$RC"
add() { grep -qF "alias $1=" "$RC" || { echo "alias $1='$2'" >> "$RC"; echo "added alias $1 to $RC"; }; }
add claude-c      'CLAUDE_CONFIG_DIR="$HOME/.claude-c" claude'
add swap-c        'CLAUDE_CONFIG_DIR="$HOME/.claude-c" claude --continue'
add swap-a        'claude --continue'
add claude-c-sync 'bash "$HOME/.claude/scripts/claude-c.sh"'

grep -q '"emailAddress"' "$B/.claude.json" 2>/dev/null \
  || echo "not logged in yet: run claude-c, then /login (open the URL in a private window)"
