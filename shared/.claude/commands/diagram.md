---
description: Generate a Mermaid diagram as a PNG image, saved to ~/Desktop/claude-outputs/diagrams/
---

Generate a diagram from the user's request, render it as a PNG, and save it for easy Slack sharing.

## What to diagram

$ARGUMENTS

If no arguments are provided, diagram the most relevant thing from the current conversation (architecture, flow, relationship, sequence, etc.).

## Instructions

### Step 1: Choose the right diagram type

Pick the Mermaid diagram type that best fits the request:
- `flowchart TD/LR` — processes, decision trees, pipelines
- `sequenceDiagram` — API calls, message flows, request/response
- `classDiagram` — data models, class relationships
- `erDiagram` — database schemas
- `stateDiagram-v2` — state machines, lifecycle
- `gantt` — timelines, project phases
- `graph` — general relationships

### Step 2: Write the Mermaid file

Write the diagram source to `/tmp/claude_diagram.mmd`.

Guidelines:
- Keep labels concise — long text breaks layout
- Use meaningful node IDs
- For Japanese text in labels, wrap in quotes: `A["日本語ラベル"]`
- Limit complexity — aim for readability, not completeness
- Use subgraphs to group related nodes when helpful

### Step 3: Render as PNG

```bash
mkdir -p ~/Desktop/claude-outputs/diagrams
npx --yes @mermaid-js/mermaid-cli -i /tmp/claude_diagram.mmd -o ~/Desktop/claude-outputs/diagrams/diagram.png -b transparent --scale 2 2>&1
```

If the render fails, check the Mermaid syntax, fix it, and retry.

### Step 4: Verify and report

Read the generated PNG to verify it rendered correctly. Show the user:
- The diagram image
- Where it was saved
- The Mermaid source (in a code block) in case they want to tweak it

Remind: drag the PNG into Slack to share.
