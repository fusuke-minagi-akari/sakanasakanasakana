#!/usr/bin/env python3
"""List all active and recent Claude Code sessions."""

import json
import os
import glob
import signal
from datetime import datetime, timezone, timedelta

CLAUDE_DIR = os.path.expanduser("~/.claude")
PROJECTS_DIR = os.path.join(CLAUDE_DIR, "projects")
SESSIONS_DIR = os.path.join(CLAUDE_DIR, "sessions")

PRICING = {
    "claude-opus-4-6":   {"input": 5.00, "output": 25.00, "cache_create_mult": 1.25, "cache_read_mult": 0.10},
    "claude-sonnet-4-6": {"input": 3.00, "output": 15.00, "cache_create_mult": 1.25, "cache_read_mult": 0.10},
    "claude-haiku-4-5":  {"input": 1.00, "output":  5.00, "cache_create_mult": 1.25, "cache_read_mult": 0.10},
}

R   = '\033[0m'
DIM = '\033[2m'
BOLD = '\033[1m'
GREEN = '\033[32m'
RED = '\033[31m'
YELLOW = '\033[33m'
CYAN = '\033[36m'


def resolve_pricing(model_id):
    if not model_id:
        return None
    model_id = model_id.lower().strip()
    for key, val in PRICING.items():
        if isinstance(val, dict) and key in model_id:
            return val
    return None


def is_pid_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except (OSError, TypeError):
        return False


def parse_ts(ts_str):
    if not ts_str:
        return None
    try:
        return datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None


def format_duration(seconds):
    if seconds < 60:
        return f"{seconds:.0f}s"
    elif seconds < 3600:
        return f"{int(seconds // 60)}m {int(seconds % 60)}s"
    else:
        return f"{int(seconds // 3600)}h {int((seconds % 3600) // 60)}m"


def scan_transcript_quick(path):
    """Quick scan — first/last timestamps, turns, cost by model."""
    first_ts = None
    last_ts = None
    turns = 0
    per_model = {}

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

                ts = obj.get("timestamp")
                msg_type = obj.get("type")

                if msg_type == "user" and ts and first_ts is None:
                    first_ts = ts

                if msg_type == "assistant":
                    msg = obj.get("message", {})
                    usage = msg.get("usage", {})
                    model = msg.get("model", "unknown")
                    if ts:
                        last_ts = ts
                    turns += 1

                    if model not in per_model:
                        per_model[model] = {"input": 0, "output": 0, "cache_create": 0, "cache_read": 0}
                    per_model[model]["input"] += usage.get("input_tokens", 0)
                    per_model[model]["output"] += usage.get("output_tokens", 0)
                    per_model[model]["cache_create"] += usage.get("cache_creation_input_tokens", 0)
                    per_model[model]["cache_read"] += usage.get("cache_read_input_tokens", 0)
    except OSError:
        return None

    if turns == 0:
        return None

    # Per-model cost
    cost = 0.0
    total_tokens = 0
    rate = 1 / 1_000_000
    models_used = []
    for model, c in per_model.items():
        p = resolve_pricing(model)
        tok = c["input"] + c["output"] + c["cache_create"] + c["cache_read"]
        total_tokens += tok
        if p:
            cost += (
                c["input"] * p["input"] * rate
                + c["output"] * p["output"] * rate
                + c["cache_create"] * p["input"] * p["cache_create_mult"] * rate
                + c["cache_read"] * p["input"] * p["cache_read_mult"] * rate
            )
        short = model.replace("claude-", "").replace("-4-6", "").replace("-4-5", "")
        models_used.append(short)

    return {
        "first_ts": first_ts,
        "last_ts": last_ts,
        "turns": turns,
        "cost": cost,
        "total_tokens": total_tokens,
        "models": list(set(models_used)),
    }


def load_session_metadata():
    meta = {}
    if not os.path.isdir(SESSIONS_DIR):
        return meta
    for f in glob.glob(os.path.join(SESSIONS_DIR, "*.json")):
        try:
            with open(f) as fh:
                data = json.load(fh)
            sid = data.get("sessionId")
            if sid:
                meta[sid] = data
        except (OSError, json.JSONDecodeError):
            pass
    return meta


def main():
    now = datetime.now(timezone.utc)
    session_meta = load_session_metadata()

    # Find all transcripts
    sessions = []
    for proj_dir in glob.glob(os.path.join(PROJECTS_DIR, "*")):
        if not os.path.isdir(proj_dir):
            continue
        for jsonl in glob.glob(os.path.join(proj_dir, "*.jsonl")):
            sid = os.path.basename(jsonl).replace(".jsonl", "")
            result = scan_transcript_quick(jsonl)
            if not result:
                continue

            meta = session_meta.get(sid, {})
            pid = meta.get("pid")
            alive = is_pid_alive(pid) if pid else False
            cwd = meta.get("cwd", "")
            name = meta.get("name", "")
            kind = meta.get("kind", "")

            last = parse_ts(result["last_ts"])
            first = parse_ts(result["first_ts"])
            dur = (last - first).total_seconds() if first and last else 0
            age = (now - last).total_seconds() if last else float("inf")

            sessions.append({
                "sid": sid,
                "pid": pid,
                "alive": alive,
                "name": name,
                "cwd": cwd,
                "kind": kind,
                "first_ts": first,
                "last_ts": last,
                "duration": dur,
                "age": age,
                "turns": result["turns"],
                "cost": result["cost"],
                "tokens": result["total_tokens"],
                "models": result["models"],
            })

    # Sort: active first, then by recency
    sessions.sort(key=lambda s: (not s["alive"], s["age"]))

    # Filter: show active + last 24h
    cutoff = 24 * 3600
    visible = [s for s in sessions if s["alive"] or s["age"] < cutoff]
    older = [s for s in sessions if not s["alive"] and s["age"] >= cutoff]

    w = 80
    print("=" * w)
    print(f"  {BOLD}CLAUDE CODE SESSIONS{R}")
    print("=" * w)

    active = [s for s in visible if s["alive"]]
    recent = [s for s in visible if not s["alive"]]

    if active:
        print()
        print(f"  {GREEN}{BOLD}ACTIVE ({len(active)}){R}")
        print("  " + "-" * (w - 4))
        for s in active:
            _print_session(s, now)

    if recent:
        print()
        print(f"  {DIM}RECENT (last 24h, {len(recent)} sessions){R}")
        print("  " + "-" * (w - 4))
        for s in recent:
            _print_session(s, now)

    if older:
        older_cost = sum(s["cost"] for s in older)
        print()
        print(f"  {DIM}+ {len(older)} older sessions (${older_cost:.2f} total){R}")

    # Summary
    total_active_cost = sum(s["cost"] for s in active)
    total_today_cost = sum(s["cost"] for s in visible)
    print()
    print(f"  Active cost: ${total_active_cost:.4f}   Today: ${total_today_cost:.4f}")
    print("=" * w)


def _print_session(s, now):
    sid_short = s["sid"][:8]

    # Status indicator
    if s["alive"]:
        status = f"{GREEN}●{R}"
    else:
        status = f"{DIM}○{R}"

    # Label
    label = s["name"] or os.path.basename(s["cwd"]) or sid_short
    if len(label) > 28:
        label = label[:25] + "..."

    # Time info
    dur_str = format_duration(s["duration"]) if s["duration"] > 0 else "-"
    if s["alive"]:
        age_str = f"{GREEN}running{R}"
    elif s["age"] < 3600:
        age_str = f"{int(s['age'] // 60)}m ago"
    else:
        age_str = f"{int(s['age'] // 3600)}h ago"

    # Cost
    cost_str = f"${s['cost']:.4f}"

    # Models
    model_str = ",".join(s["models"]) if s["models"] else "?"

    # PID
    pid_str = f"PID {s['pid']}" if s['pid'] else "      "

    print(f"  {status} {sid_short}  {label:<28s}  {pid_str:<10s}  {dur_str:>8s}  {s['turns']:>3d}t  {cost_str:>10s}  {DIM}{model_str}{R}")

    # Second line: project path (dimmed)
    if s["cwd"]:
        home = os.path.expanduser("~")
        path = s["cwd"].replace(home, "~")
        print(f"    {DIM}{path}{R}")


if __name__ == "__main__":
    main()
