---
name: session-cost
description: Show token usage, cost breakdown, and timing for the current session. Use when the user asks about cost, tokens, spend, or usage.
argument-hint: [model-override]
disable-model-invocation: true
allowed-tools: Bash(python3 *) Bash(find *)
---

Run the session cost analysis script on the current session transcript.

Find the transcript by running:
```
find ~/.claude/projects/ -name "${CLAUDE_SESSION_ID}.jsonl" -type f 2>/dev/null | head -1
```

Then run the cost script with that path:
```
python3 ${CLAUDE_SKILL_DIR}/cost.py "<transcript_path>" $ARGUMENTS
```

Display the output exactly as-is. Do not add commentary.
