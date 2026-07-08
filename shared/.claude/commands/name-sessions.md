---
description: Auto-name all unnamed Claude Code sessions based on their conversation content
---

Scan all unnamed sessions and assign short descriptive names based on their content.

## Instructions

### Step 1: Get unnamed sessions

```bash
python3 ~/.claude/skills/sessions/name_sessions_bulk.py
```

This outputs a JSON array. Each entry has:
- `session_id`: full UUID
- `meta_file`: path to the session's metadata JSON file
- `cwd`: working directory when the session started
- `first_messages`: first 2–4 user messages from the transcript

If the array is empty, reply "All sessions are already named." and stop.

### Step 2: Generate names

For each entry in the array, generate a concise name:

**Rules:**
- 2–4 words, kebab-case (e.g. `qwen-bbox-debug`, `kalmia-depth-fix`, `standup-setup`)
- Reflect the **primary task** — what the user was trying to accomplish
- Use technical terms from the messages if clear (e.g. `yolo-finetune`, `depth-estimation-bug`)
- Ignore generic openers like "resume", "help", "hi" — look at the substantive messages
- If cwd reveals the project (e.g. `kalmia-robot-learning`), use it as a prefix if helpful
- Max 40 chars total

### Step 3: Apply names

For each session, write the name to its metadata file:

```bash
python3 -c "
import json
path = '<meta_file>'
name = '<generated-name>'
with open(path) as f:
    d = json.load(f)
d['name'] = name
with open(path, 'w') as f:
    json.dump(d, f, indent=2)
print(f'Named {path.split(\"/\")[-1].replace(\".json\",\"\")[:8]}: {name}')
"
```

Run this for each session. It's safe to run on active sessions.

### Step 4: Report

Show a summary table:

```
Named N sessions:
  <session_id[:8]>  →  <name>
  ...
```

If any session had no usable messages (empty first_messages), skip it and note "X sessions skipped (no content)".
