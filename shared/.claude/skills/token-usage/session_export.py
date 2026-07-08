#!/usr/bin/env python3
"""Export this device's sessions to iCloud Drive for cross-device visibility.

Run automatically via a Stop hook, or manually:
    python3 ~/.claude/skills/token-usage/session_export.py
"""

import json
import os
import socket
import subprocess
import sys
from datetime import datetime, timezone

ICLOUD_DIR = os.path.expanduser(
    "~/Library/Mobile Documents/com~apple~CloudDocs/.claude-sessions"
)
SESSIONS_SCRIPT = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "../sessions/sessions_json.py"
)


def main():
    hostname = socket.gethostname()

    result = subprocess.run(
        [sys.executable, SESSIONS_SCRIPT, "--all"],
        capture_output=True, text=True, timeout=30
    )

    if result.returncode != 0 or not result.stdout.strip():
        print(f"session_export: failed to fetch sessions: {result.stderr.strip()}", file=sys.stderr)
        sys.exit(1)

    data = json.loads(result.stdout)
    data["hostname"] = hostname
    data["exported_at"] = datetime.now(timezone.utc).isoformat()

    os.makedirs(ICLOUD_DIR, exist_ok=True)
    output_path = os.path.join(ICLOUD_DIR, f"{hostname}.json")
    with open(output_path, "w") as f:
        json.dump(data, f, indent=2)

    count = len(data.get("sessions", []))
    print(f"session_export: {count} sessions → {output_path}")


if __name__ == "__main__":
    main()
