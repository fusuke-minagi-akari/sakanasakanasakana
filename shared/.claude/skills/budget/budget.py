#!/usr/bin/env python3
"""Session budget manager for Claude Code.

Usage:
  python3 budget.py <session-id>          # Check current budget status
  python3 budget.py <session-id> $5       # Set budget to $5
  python3 budget.py <session-id> 5        # Set budget to $5
  python3 budget.py <session-id> clear    # Remove budget
"""

import json
import os
import sys
import glob
from datetime import datetime, timezone

CLAUDE_DIR = os.path.expanduser("~/.claude")
PROJECTS_DIR = os.path.join(CLAUDE_DIR, "projects")
BUDGETS_DIR = os.path.join(CLAUDE_DIR, "budgets")

PRICING = {
    "claude-opus-4-6":   {"input": 5.00, "output": 25.00, "cache_create_mult": 1.25, "cache_read_mult": 0.10},
    "claude-sonnet-4-6": {"input": 3.00, "output": 15.00, "cache_create_mult": 1.25, "cache_read_mult": 0.10},
    "claude-haiku-4-5":  {"input": 1.00, "output":  5.00, "cache_create_mult": 1.25, "cache_read_mult": 0.10},
}

R    = '\033[0m'
DIM  = '\033[2m'
BOLD = '\033[1m'
RED  = '\033[31m'
YELLOW = '\033[33m'
GREEN = '\033[32m'


def resolve_pricing(model_id):
    if not model_id:
        return None
    model_id = model_id.lower().strip()
    for key, val in PRICING.items():
        if isinstance(val, dict) and key in model_id:
            return val
    return None


def find_transcript(session_id):
    for proj_dir in glob.glob(os.path.join(PROJECTS_DIR, "*")):
        if not os.path.isdir(proj_dir):
            continue
        path = os.path.join(proj_dir, f"{session_id}.jsonl")
        if os.path.exists(path):
            return path
    return None


def calc_session_cost(path):
    per_model = {}
    turns = 0
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if obj.get("type") != "assistant":
                    continue
                msg = obj.get("message", {})
                usage = msg.get("usage", {})
                model = msg.get("model", "unknown")
                turns += 1

                if model not in per_model:
                    per_model[model] = {"input": 0, "output": 0, "cache_create": 0, "cache_read": 0}
                per_model[model]["input"] += usage.get("input_tokens", 0)
                per_model[model]["output"] += usage.get("output_tokens", 0)
                per_model[model]["cache_create"] += usage.get("cache_creation_input_tokens", 0)
                per_model[model]["cache_read"] += usage.get("cache_read_input_tokens", 0)
    except OSError:
        return 0.0, 0

    cost = 0.0
    rate = 1 / 1_000_000
    for model, c in per_model.items():
        p = resolve_pricing(model)
        if p:
            cost += (
                c["input"] * p["input"] * rate
                + c["output"] * p["output"] * rate
                + c["cache_create"] * p["input"] * p["cache_create_mult"] * rate
                + c["cache_read"] * p["input"] * p["cache_read_mult"] * rate
            )
    return cost, turns


def load_budget(session_id):
    path = os.path.join(BUDGETS_DIR, f"{session_id}.json")
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return None


def save_budget(session_id, amount):
    os.makedirs(BUDGETS_DIR, exist_ok=True)
    path = os.path.join(BUDGETS_DIR, f"{session_id}.json")
    data = {
        "budget_usd": amount,
        "session_id": session_id,
        "set_at": datetime.now(timezone.utc).isoformat(),
    }
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    return data


def clear_budget(session_id):
    path = os.path.join(BUDGETS_DIR, f"{session_id}.json")
    try:
        os.remove(path)
        return True
    except OSError:
        return False


def bar(pct, width=20):
    filled = min(int(pct / 100 * width), width)
    return "█" * filled + "░" * (width - filled)


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 budget.py <session-id> [$amount|clear]")
        sys.exit(1)

    session_id = sys.argv[1]
    action = sys.argv[2].strip() if len(sys.argv) > 2 else None

    # Handle "clear"
    if action and action.lower() == "clear":
        if clear_budget(session_id):
            print(f"Budget cleared for session {session_id[:8]}.")
        else:
            print(f"No budget was set for session {session_id[:8]}.")
        return

    # Handle setting a budget
    if action:
        amount_str = action.replace("$", "").replace("¥", "").strip()
        try:
            amount = float(amount_str)
        except ValueError:
            print(f"Invalid amount: {action}")
            print("Usage: /budget $5  or  /budget 5  or  /budget clear")
            sys.exit(1)

        save_budget(session_id, amount)

        # Also show current status
        transcript = find_transcript(session_id)
        if transcript:
            cost, turns = calc_session_cost(transcript)
            pct = cost / amount * 100 if amount > 0 else 0
            color = GREEN if pct < 70 else (YELLOW if pct < 100 else RED)
            print(f"Budget set: ${amount:.2f} for session {session_id[:8]}")
            print(f"Current:    {color}{bar(pct)}{R} {pct:.1f}%  (${cost:.4f} / ${amount:.2f})")
        else:
            print(f"Budget set: ${amount:.2f} for session {session_id[:8]}")
        return

    # No action — show status
    budget = load_budget(session_id)
    transcript = find_transcript(session_id)

    if not transcript:
        print(f"Session {session_id[:8]} not found.")
        sys.exit(1)

    cost, turns = calc_session_cost(transcript)

    w = 50
    print("=" * w)
    print(f"  {BOLD}SESSION BUDGET{R}  {session_id[:8]}")
    print("=" * w)

    if budget:
        amount = budget["budget_usd"]
        pct = cost / amount * 100 if amount > 0 else 0
        remaining = amount - cost

        if pct >= 100:
            color = RED
            status = f"{RED}{BOLD}OVER BUDGET{R}"
        elif pct >= 80:
            color = YELLOW
            status = f"{YELLOW}WARNING{R}"
        elif pct >= 50:
            color = YELLOW
            status = f"{GREEN}OK{R}"
        else:
            color = GREEN
            status = f"{GREEN}OK{R}"

        print()
        print(f"  Budget:    ${amount:.2f}")
        print(f"  Spent:     ${cost:.4f}  ({turns} turns)")
        print(f"  Remaining: ${remaining:.4f}")
        print()
        print(f"  {color}{bar(pct, 30)}{R} {pct:.1f}%  {status}")

        if pct >= 100:
            print()
            print(f"  {RED}{BOLD}⚠ This session has exceeded its ${amount:.2f} budget!{R}")
            print(f"  {RED}  Overage: ${abs(remaining):.4f}{R}")
        elif pct >= 80:
            print()
            print(f"  {YELLOW}⚠ Approaching budget limit ({pct:.0f}%){R}")
    else:
        print()
        print(f"  Spent: ${cost:.4f}  ({turns} turns)")
        print(f"  {DIM}No budget set.{R}")
        print(f"  {DIM}Use /budget $5 to set a budget for this session.{R}")

    print()
    print("=" * w)


if __name__ == "__main__":
    main()
