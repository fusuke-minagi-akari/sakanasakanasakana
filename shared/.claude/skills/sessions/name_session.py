#!/usr/bin/env python3
"""Name the current Claude Code session by walking up the process tree.

Usage:
    python3 name_session.py "kalmia qwen debug"
"""

import json
import os
import subprocess
import sys


SESSIONS_DIR = os.path.expanduser("~/.claude/sessions")


def find_session_meta_file():
    """Walk up the process tree from our parent to find a ~/.claude/sessions/<pid>.json."""
    pid = os.getppid()
    visited = set()
    while pid > 1 and pid not in visited:
        visited.add(pid)
        meta_file = os.path.join(SESSIONS_DIR, f"{pid}.json")
        if os.path.isfile(meta_file):
            return meta_file, pid
        try:
            result = subprocess.run(
                ["ps", "-p", str(pid), "-o", "ppid="],
                capture_output=True, text=True
            )
            ppid = int(result.stdout.strip())
            if ppid == pid:
                break
            pid = ppid
        except Exception:
            break
    return None, None


def main():
    if len(sys.argv) < 2:
        print("Usage: name_session.py <name>", file=sys.stderr)
        sys.exit(1)

    name = " ".join(sys.argv[1:]).strip()

    meta_file, pid = find_session_meta_file()
    if not meta_file:
        print("ERROR: Could not find session metadata — are you running inside Claude Code?", file=sys.stderr)
        sys.exit(1)

    with open(meta_file) as f:
        data = json.load(f)

    old_name = data.get("name", "")
    data["name"] = name

    with open(meta_file, "w") as f:
        json.dump(data, f, indent=2)

    sid = data.get("sessionId", "?")[:8]
    if old_name:
        print(f'Session {sid} renamed: "{old_name}" → "{name}"')
    else:
        print(f'Session {sid} named: "{name}"')


if __name__ == "__main__":
    main()
