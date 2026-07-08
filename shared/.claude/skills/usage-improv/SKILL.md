---
name: usage-improv
description: Enhanced usage dashboard — shows all sessions today/this week, total cost in USD+JPY, and daily/weekly limit progress bars.
allowed-tools: Bash(python3 *) Bash(find *)
---

Run the enhanced usage dashboard:

```
python3 ${CLAUDE_SKILL_DIR}/usage_dashboard.py --session ${CLAUDE_SESSION_ID} $ARGUMENTS
```

Display the output exactly as-is. Do not add commentary.

Supports `--watch N` to refresh every N seconds (default: 5).
