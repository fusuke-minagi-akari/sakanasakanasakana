#!/bin/sh

set -eu

index=${1:?agent index required}
pane_id=$(herdr agent list \
  | jq -r --argjson n "$index" '.result.agents | map(select(.agent_status == "done")) | .[$n - 1].pane_id // empty')

if [ -n "$pane_id" ]; then
  herdr agent focus "$pane_id"
else
  herdr notification show "Herdr" --body "No done agent at position $index" --sound none >/dev/null 2>&1 || true
fi
