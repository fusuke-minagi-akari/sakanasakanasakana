#!/usr/bin/env python3
"""Output Claude Code sessions as JSON — used by sessions_multi.py over SSH."""

import json
import os
import glob
import sys
from datetime import datetime, timezone

CLAUDE_DIR = os.path.expanduser("~/.claude")
PROJECTS_DIR = os.path.join(CLAUDE_DIR, "projects")
SESSIONS_DIR = os.path.join(CLAUDE_DIR, "sessions")

PRICING = {
    "claude-opus-4-6":   {"input": 5.00, "output": 25.00, "cache_create_mult": 1.25, "cache_read_mult": 0.10},
    "claude-sonnet-4-6": {"input": 3.00, "output": 15.00, "cache_create_mult": 1.25, "cache_read_mult": 0.10},
    "claude-haiku-4-5":  {"input": 1.00, "output":  5.00, "cache_create_mult": 1.25, "cache_read_mult": 0.10},
}


def resolve_pricing(model_id):
    if not model_id:
        return None
    model_id = model_id.lower().strip()
    for key, val in PRICING.items():
        if key in model_id:
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


_SYSTEM_PREFIXES = (
    "<local-command-caveat>",
    "<command-message>",
    "<command-name>",
    "<system-reminder>",
)


def _is_system_content(text):
    """Return True if the text is an injected system/skill message, not a human prompt."""
    return any(text.startswith(p) for p in _SYSTEM_PREFIXES)


def scan_transcript(path):
    first_ts = None
    last_ts = None
    turns = 0
    per_model = {}
    description = ""
    total_input = 0
    total_output = 0

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

                if msg_type == "user":
                    if ts and first_ts is None:
                        first_ts = ts
                    # Extract first human-typed text as description
                    if not description:
                        content = obj.get("message", {}).get("content", "")
                        if isinstance(content, str):
                            text = content.strip()
                            if text and not _is_system_content(text):
                                description = text[:80]
                        elif isinstance(content, list):
                            for block in content:
                                if isinstance(block, dict) and block.get("type") == "text":
                                    text = block.get("text", "").strip()
                                    if text and not _is_system_content(text):
                                        description = text[:80]
                                        break

                if msg_type == "assistant":
                    msg = obj.get("message", {})
                    usage = msg.get("usage", {})
                    model = msg.get("model", "unknown")
                    if ts:
                        last_ts = ts
                    turns += 1
                    inp = usage.get("input_tokens", 0)
                    out = usage.get("output_tokens", 0)
                    total_input += inp
                    total_output += out
                    if model not in per_model:
                        per_model[model] = {"input": 0, "output": 0, "cache_create": 0, "cache_read": 0}
                    per_model[model]["input"] += inp
                    per_model[model]["output"] += out
                    per_model[model]["cache_create"] += usage.get("cache_creation_input_tokens", 0)
                    per_model[model]["cache_read"] += usage.get("cache_read_input_tokens", 0)
    except OSError:
        return None

    if turns == 0:
        return None

    cost = 0.0
    rate = 1 / 1_000_000
    models_used = []
    for model, c in per_model.items():
        p = resolve_pricing(model)
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
        "models": list(set(models_used)),
        "description": description,
        "total_tokens": total_input + total_output,
    }


def main():
    show_all = "--all" in sys.argv
    now = datetime.now(timezone.utc)
    home = os.path.expanduser("~")

    # Load session metadata
    session_meta = {}
    if os.path.isdir(SESSIONS_DIR):
        for f in glob.glob(os.path.join(SESSIONS_DIR, "*.json")):
            try:
                with open(f) as fh:
                    data = json.load(fh)
                sid = data.get("sessionId")
                if sid:
                    session_meta[sid] = data
            except (OSError, json.JSONDecodeError):
                pass

    sessions = []
    for proj_dir in glob.glob(os.path.join(PROJECTS_DIR, "*")):
        if not os.path.isdir(proj_dir):
            continue
        for jsonl in glob.glob(os.path.join(proj_dir, "*.jsonl")):
            sid = os.path.basename(jsonl).replace(".jsonl", "")
            result = scan_transcript(jsonl)
            if not result:
                continue

            meta = session_meta.get(sid, {})
            pid = meta.get("pid")
            alive = is_pid_alive(pid) if pid else False
            cwd = meta.get("cwd", "")
            name = meta.get("name", "")

            first = parse_ts(result["first_ts"])
            last = parse_ts(result["last_ts"])
            dur = (last - first).total_seconds() if first and last else 0
            age = (now - last).total_seconds() if last else float("inf")

            # Default: active + last 24h. With --all: no time limit.
            if not show_all and not alive and age >= 24 * 3600:
                continue

            date_str = last.strftime("%m/%d %H:%M") if last else ""

            sessions.append({
                "sid": sid,
                "name": name,
                "description": result.get("description", ""),
                "cwd_short": cwd.replace(home, "~"),
                "alive": alive,
                "duration": dur,
                "turns": result["turns"],
                "cost": result["cost"],
                "models": result["models"],
                "total_tokens": result.get("total_tokens", 0),
                "date": date_str,
                "last_ts": result["last_ts"] or "",
            })

    sessions.sort(key=lambda s: (not s["alive"], s.get("last_ts", "")), reverse=False)
    sessions.sort(key=lambda s: not s["alive"])
    print(json.dumps({"sessions": sessions}))


if __name__ == "__main__":
    main()
