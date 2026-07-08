---
description: Generate a Slack-ready report — tables as PNG images + text summary, saved to ~/Desktop
---

Generate a report optimized for drag-and-drop sharing into Slack.

## What to analyze

$ARGUMENTS

If no arguments are provided, summarize the most recent analysis or discussion in this conversation.

## Output format

Produce TWO types of output, saved to `~/Desktop/`:

### 1. Table images (PNG)

For each table in the report:

1. Write a JSON file to `/tmp/slack_report_table_N.json`:
```json
{
  "title": "Descriptive Table Title",
  "headers": ["Column1", "Column2", "Column3"],
  "rows": [["value1", "value2", "value3"]]
}
```

2. Render it as a PNG:
```bash
~/.claude/scripts/render_table.py ~/Desktop/slack_report_table_N.png < /tmp/slack_report_table_N.json
```

Keep table content concise — truncate long strings so cells stay readable. Use short labels.

### 2. Slack text summary

Write `~/Desktop/slack_summary.txt` formatted for Slack's mrkdwn:
- `*Bold*` for section headings (not markdown `##`)
- `• ` for bullet points
- Single backticks for inline code/values
- Triple backticks for code blocks
- Keep it concise — aim for a message, not a document
- Do NOT reproduce tables in text — just reference the attached images
- End with a line like: `📎 See attached table(s) above`

### 3. Tell the user what was created

After generating everything, list the files saved to ~/Desktop and show a preview of the text summary. Remind the user:
> Drag the PNG image(s) into your Slack message, then paste the text from `slack_summary.txt`.
