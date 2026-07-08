---
description: Show token usage per session across all devices, with natural language descriptions
---

Run the multi-device token usage viewer:

```bash
python3 ~/.claude/skills/token-usage/token_usage.py
```

Display the output exactly as-is. Do not add commentary.

## What it shows

For each device (live via SSH, or cached from iCloud if offline):
- Session description (first message you typed, or session name)
- Token count, turn count, cost, duration, model
- Grand total across all devices

## Data sources

- **Live**: SSHes to online devices (same as `/devices`)
- **Cached**: Reads `~/Library/Mobile Documents/com~apple~CloudDocs/.claude-sessions/<hostname>.json`
  — updated automatically when a session ends via the Stop hook

## Configuration

Devices are listed in `~/.claude/scripts/devices.txt`. Format:
```
<ssh-host>  <display-name>
```

Use `local` for the current machine. Example:
```
local          MacBook
user@10.0.0.5  Dev-Server
user@lab-pc    Lab-PC
```

## Setup for sub-devices

Copy the required scripts to each device:
```bash
scp ~/.claude/skills/sessions/sessions_json.py user@host:~/.claude/skills/sessions/sessions_json.py
scp ~/.claude/skills/token-usage/session_export.py user@host:~/.claude/skills/token-usage/session_export.py
```

Then add the Stop hook on each device (edit `~/.claude/settings.json`):
```json
"hooks": {
  "Stop": [{"hooks": [{"type": "command", "command": "python3 ~/.claude/skills/token-usage/session_export.py > /dev/null 2>&1"}]}]
}
```
