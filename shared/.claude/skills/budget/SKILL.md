---
name: budget
description: Set a soft USD budget for the current session. Shows warning when exceeded. Run with no args to check status, or pass a dollar amount to set/update.
argument-hint: [$amount]
allowed-tools: Bash(python3 *) Read Write
---

Run the budget manager for the current session:

```
python3 ${CLAUDE_SKILL_DIR}/budget.py ${CLAUDE_SESSION_ID} $ARGUMENTS
```

If the script outputs a budget warning or status, display it exactly as-is.

If a new budget was set, confirm it to the user.
