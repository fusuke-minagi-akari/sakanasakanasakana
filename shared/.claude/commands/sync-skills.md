---
description: Sync Claude skills, commands, and scripts to all remote devices in devices.txt
---

Run the skills sync script:

```bash
bash ~/.claude/scripts/sync_skills.sh
```

Display the output exactly as-is.

## What gets synced

- `~/.claude/commands/` — skill definitions (including this one)
- `~/.claude/skills/` — skill implementations
- `~/.claude/scripts/` — helper scripts (including `devices.txt`)
- `~/.claude/CLAUDE.md` — global instructions

## Configuration

Devices are listed in `~/.claude/scripts/devices.txt`. Format:

```
# Comments are ignored
local          MacBook        ← skipped (local machine)
user@10.0.0.5  Dev-Server     ← synced via SSH
user@lab-pc    Lab-PC         ← synced via SSH
```

**To add a new device:** add a line to `devices.txt`, then run `/sync-skills`.

## Requirements for remote devices

Each remote device needs:
1. SSH key-based auth (no password prompts)
2. `rsync` available (pre-installed on macOS/most Linux)
3. `~/.claude/` directory (created automatically on first sync)
