#!/usr/bin/env bash
# Sync Claude skills, commands, and scripts to remote devices listed in devices.txt
# Compatible: bash 3.2+ (macOS default), bash 4+ (Linux), WSL on Windows
set -euo pipefail

DEVICES_FILE="$HOME/.claude/scripts/devices.txt"
CLAUDE_DIR="$HOME/.claude"

SYNC_ITEMS=(
  "commands/"
  "skills/"
  "scripts/"
  "CLAUDE.md"
)

if [[ ! -f "$DEVICES_FILE" ]]; then
  echo "Error: $DEVICES_FILE not found"
  exit 1
fi

# Parse devices.txt — bash 3.2 compatible (no mapfile)
REMOTES=()
while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  host=$(echo "$line" | awk '{print $1}')
  [[ "$host" == "local" ]] && continue
  REMOTES+=("$host")
done < "$DEVICES_FILE"

if [[ ${#REMOTES[@]} -eq 0 ]]; then
  echo "No remote devices found in $DEVICES_FILE"
  echo "Add entries like:  user@hostname  DeviceName"
  exit 0
fi

# Detect if rsync is available
HAS_RSYNC=true
command -v rsync >/dev/null 2>&1 || HAS_RSYNC=false

ERRORS=0

for host in "${REMOTES[@]}"; do
  echo ""
  echo "==> Syncing to $host"

  # Test SSH connectivity
  if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" \
      "mkdir -p ~/.claude/commands ~/.claude/skills ~/.claude/scripts" 2>/dev/null; then
    echo "    [SKIP] Cannot connect to $host"
    ((ERRORS++)) || true
    continue
  fi

  for item in "${SYNC_ITEMS[@]}"; do
    src="$CLAUDE_DIR/$item"
    [[ ! -e "$src" ]] && continue

    if $HAS_RSYNC; then
      # rsync: fast, incremental
      if rsync -az --delete \
          --exclude '*.pyc' \
          --exclude '__pycache__' \
          "$src" "$host:~/.claude/$item" 2>/dev/null; then
        echo "    [OK]   $item"
      else
        echo "    [FAIL] $item"
        ((ERRORS++)) || true
      fi
    else
      # scp fallback (Windows Git Bash / no rsync)
      if [[ -d "$src" ]]; then
        if scp -r -q "$src" "$host:~/.claude/$item" 2>/dev/null; then
          echo "    [OK]   $item  (via scp)"
        else
          echo "    [FAIL] $item"
          ((ERRORS++)) || true
        fi
      else
        if scp -q "$src" "$host:~/.claude/$item" 2>/dev/null; then
          echo "    [OK]   $item  (via scp)"
        else
          echo "    [FAIL] $item"
          ((ERRORS++)) || true
        fi
      fi
    fi
  done
done

echo ""
if [[ $ERRORS -eq 0 ]]; then
  echo "Done. All devices synced successfully."
else
  echo "Done with $ERRORS error(s). Check connection/SSH keys for failed devices."
fi
