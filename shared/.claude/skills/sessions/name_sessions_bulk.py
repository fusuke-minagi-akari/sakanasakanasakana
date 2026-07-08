#!/usr/bin/env python3
"""Extract unnamed sessions with their first few messages for bulk naming.

Outputs JSON array:
[
  {
    "session_id": "...",
    "meta_file": "/path/to/<pid>.json",
    "cwd": "...",
    "first_messages": ["msg1", "msg2", ...]
  },
  ...
]
"""

import json
import os
import glob
import sys

CLAUDE_DIR = os.path.expanduser("~/.claude")
PROJECTS_DIR = os.path.join(CLAUDE_DIR, "projects")
SESSIONS_DIR = os.path.join(CLAUDE_DIR, "sessions")

MAX_MSGS = 4        # how many user messages to extract
MAX_MSG_LEN = 300   # truncate each message to this length


def load_all_session_meta():
    """Returns dict: session_id -> (meta_dict, meta_file_path)"""
    result = {}
    for f in glob.glob(os.path.join(SESSIONS_DIR, "*.json")):
        try:
            with open(f) as fh:
                data = json.load(fh)
            sid = data.get("sessionId")
            if sid:
                result[sid] = (data, f)
        except (OSError, json.JSONDecodeError):
            pass
    return result


def extract_first_messages(jsonl_path, max_msgs=MAX_MSGS):
    """Read first N non-empty user text messages from a transcript."""
    msgs = []
    try:
        with open(jsonl_path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if obj.get("type") != "user":
                    continue
                content = obj.get("message", {}).get("content", "")
                if isinstance(content, list):
                    text = " ".join(
                        p.get("text", "")
                        for p in content
                        if isinstance(p, dict) and p.get("type") == "text"
                    )
                else:
                    text = str(content)
                text = text.strip()
                # Skip bare "resume" or very short bootstrap messages
                if len(text) < 8:
                    continue
                msgs.append(text[:MAX_MSG_LEN])
                if len(msgs) >= max_msgs:
                    break
    except OSError:
        pass
    return msgs


def main():
    all_meta = load_all_session_meta()

    # Build map: session_id -> meta_file_path (only unnamed)
    unnamed = {}
    for sid, (data, meta_path) in all_meta.items():
        name = data.get("name", "").strip()
        if not name:
            unnamed[sid] = (data, meta_path)

    results = []

    for proj_dir in glob.glob(os.path.join(PROJECTS_DIR, "*")):
        if not os.path.isdir(proj_dir):
            continue
        for jsonl in glob.glob(os.path.join(proj_dir, "*.jsonl")):
            sid = os.path.basename(jsonl).replace(".jsonl", "")
            if sid not in unnamed:
                continue

            data, meta_path = unnamed[sid]
            cwd = data.get("cwd", "")
            msgs = extract_first_messages(jsonl)

            if not msgs:
                continue  # no content to name from

            results.append({
                "session_id": sid,
                "meta_file": meta_path,
                "cwd": cwd,
                "first_messages": msgs,
            })

    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
