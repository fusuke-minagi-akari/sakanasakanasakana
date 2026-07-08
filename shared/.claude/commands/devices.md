---
description: Show Claude Code sessions across all devices via SSH, with cost proportion breakdown
---

Run the multi-device sessions viewer:

```bash
python3 ~/.claude/skills/sessions/sessions_multi.py
```

Display the output exactly as-is. Do not add commentary.

## Configuration

Devices are listed in `~/.claude/scripts/devices.txt`. Format:
```
<ssh-host>  <display-name>
```

Use `local` as the host for the current machine. Example:
```
local          MacBook
user@10.0.0.5  Dev-Server
user@lab-pc    Lab-PC
```

### Setup for remote devices

Each remote device needs:
1. SSH key-based auth (no password prompts — `BatchMode=yes` is used)
2. `python3` available on PATH
3. `~/.claude/skills/sessions/sessions_json.py` copied to the same path

To deploy the JSON script to a remote device:
```bash
scp ~/.claude/skills/sessions/sessions_json.py user@host:~/.claude/skills/sessions/
```
