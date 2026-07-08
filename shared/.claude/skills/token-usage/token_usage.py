#!/usr/bin/env python3
"""Show token usage per session, per device. Reads iCloud for offline devices."""

import glob
import json
import os
import subprocess
import sys
from datetime import datetime, timezone

ICLOUD_DIR = os.path.expanduser(
    "~/Library/Mobile Documents/com~apple~CloudDocs/.claude-sessions"
)
DEVICES_FILE = os.path.expanduser("~/.claude/scripts/devices.txt")
SESSIONS_SCRIPT = os.path.expanduser("~/.claude/skills/sessions/sessions_json.py")

R = "\033[0m"
DIM = "\033[2m"
BOLD = "\033[1m"
GREEN = "\033[32m"
RED = "\033[31m"
YELLOW = "\033[33m"
CYAN = "\033[36m"


def load_devices():
    if not os.path.isfile(DEVICES_FILE):
        import socket
        return [("local", socket.gethostname())]
    devices = []
    with open(DEVICES_FILE) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(None, 1)
            host = parts[0]
            name = parts[1] if len(parts) > 1 else host
            devices.append((host, name))
    return devices


def fetch_live(host):
    try:
        if host == "local":
            result = subprocess.run(
                [sys.executable, SESSIONS_SCRIPT, "--all"],
                capture_output=True, text=True, timeout=20
            )
        else:
            result = subprocess.run(
                ["ssh", "-o", "ConnectTimeout=5", "-o", "BatchMode=yes", host,
                 "python3 ~/.claude/skills/sessions/sessions_json.py --all"],
                capture_output=True, text=True, timeout=20
            )
        if result.returncode == 0 and result.stdout.strip():
            data = json.loads(result.stdout)
            data["source"] = "live"
            return data
    except Exception as e:
        return {"error": str(e), "source": "error"}
    return {"error": f"exit {result.returncode}", "source": "error"}


def fetch_cached(device_name):
    """Find the most recent iCloud export matching this device name or hostname."""
    if not os.path.isdir(ICLOUD_DIR):
        return None
    candidates = []
    for f in glob.glob(os.path.join(ICLOUD_DIR, "*.json")):
        try:
            with open(f) as fh:
                data = json.load(fh)
            # Match on display name or actual hostname
            hn = data.get("hostname", "")
            if hn.lower() in device_name.lower() or device_name.lower() in hn.lower():
                candidates.append((data.get("exported_at", ""), data))
        except Exception:
            pass
    if not candidates:
        return None
    candidates.sort(reverse=True)
    data = candidates[0][1]
    data["source"] = "cached"
    return data


def fmt_tokens(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1000:
        return f"{n / 1000:.0f}K"
    return str(n)


def fmt_dur(s):
    if s < 60:
        return f"{s:.0f}s"
    if s < 3600:
        return f"{int(s // 60)}m"
    return f"{int(s // 3600)}h{int((s % 3600) // 60)}m"


def print_device_sessions(sessions, device_name, source, exported_at=None):
    w = 104
    if source == "live":
        src_label = f"{GREEN}live{R}"
    elif source == "cached":
        age = ""
        if exported_at:
            try:
                dt = datetime.fromisoformat(exported_at.replace("Z", "+00:00"))
                diff = datetime.now(timezone.utc) - dt
                h = int(diff.total_seconds() // 3600)
                age = f"  {DIM}last synced {h}h ago{R}"
            except Exception:
                age = f"  {DIM}{exported_at[:16]}{R}"
        src_label = f"{YELLOW}cached{R}{age}"
    else:
        src_label = f"{RED}offline{R}"

    print(f"\n  {CYAN}{BOLD}{device_name}{R}  [{src_label}]")
    print("  " + "─" * (w - 4))

    if not sessions:
        print(f"  {DIM}No sessions{R}")
        return 0, 0

    device_tokens = 0
    device_cost = 0.0

    for s in sessions:
        alive = s.get("alive", False)
        status = f"{GREEN}●{R}" if alive else f"{DIM}○{R}"
        sid = s.get("sid", "?")[:8]

        # Pick best label: explicit name > description > cwd > sid
        label = s.get("name") or s.get("description") or s.get("cwd_short") or sid
        # Clean up newlines / extra whitespace
        label = " ".join(label.split())
        if len(label) > 42:
            label = label[:39] + "..."

        tokens = s.get("total_tokens", 0)
        cost = s.get("cost", 0.0)
        turns = s.get("turns", 0)
        dur = fmt_dur(s.get("duration", 0))
        date = s.get("date", "")
        models = ",".join(s.get("models", [])) or "?"

        device_tokens += tokens
        device_cost += cost

        print(
            f"  {status} {date:>11s}  {label:<42s}  "
            f"{fmt_tokens(tokens):>6s} tok  {turns:>3d}t  "
            f"${cost:.4f}  {DIM}{dur:>5s}  {models}{R}"
        )

    print(f"  {DIM}{'─'*(w-4)}{R}")
    print(
        f"  {DIM}Device total: {fmt_tokens(device_tokens)} tokens  "
        f"${device_cost:.4f}  ({len(sessions)} sessions){R}"
    )
    return device_tokens, device_cost


def main():
    devices = load_devices()
    w = 104

    print("=" * w)
    print(f"  {BOLD}TOKEN USAGE — ALL DEVICES  (all-time, per session){R}")
    print("=" * w)

    grand_tokens = 0
    grand_cost = 0.0

    for host, device_name in devices:
        data = fetch_live(host)

        if "error" in data:
            cached = fetch_cached(device_name)
            if cached:
                sessions = cached.get("sessions", [])
                t, c = print_device_sessions(
                    sessions, device_name, "cached", cached.get("exported_at")
                )
            else:
                print(f"\n  {CYAN}{BOLD}{device_name}{R}  [{RED}offline — no cache{R}]")
                print(
                    f"  {DIM}Run session_export.py on that device to enable offline history{R}"
                )
                t, c = 0, 0.0
        else:
            sessions = data.get("sessions", [])
            t, c = print_device_sessions(sessions, device_name, "live")

        grand_tokens += t
        grand_cost += c

    print()
    print("=" * w)
    print(
        f"  {BOLD}GRAND TOTAL: {fmt_tokens(grand_tokens)} tokens  "
        f"${grand_cost:.4f}{R}"
    )
    print("=" * w)


if __name__ == "__main__":
    main()
