#!/usr/bin/env python3
"""Aggregate Claude Code sessions across multiple devices via SSH."""

import json
import os
import subprocess
import sys
from datetime import datetime, timezone

DEVICES_FILE = os.path.expanduser("~/.claude/scripts/devices.txt")
SESSIONS_SCRIPT = os.path.expanduser("~/.claude/skills/sessions/sessions_json.py")

R = '\033[0m'
DIM = '\033[2m'
BOLD = '\033[1m'
GREEN = '\033[32m'
RED = '\033[31m'
YELLOW = '\033[33m'
CYAN = '\033[36m'


def load_devices():
    devices = []
    if not os.path.isfile(DEVICES_FILE):
        return [("local", "This Mac")]
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


def fetch_sessions(host):
    """Run the JSON session reporter on a device, return parsed list."""
    try:
        if host == "local":
            result = subprocess.run(
                [sys.executable, SESSIONS_SCRIPT],
                capture_output=True, text=True, timeout=15
            )
        else:
            result = subprocess.run(
                ["ssh", "-o", "ConnectTimeout=5", "-o", "BatchMode=yes", host,
                 f"python3 ~/.claude/skills/sessions/sessions_json.py"],
                capture_output=True, text=True, timeout=15
            )
        if result.returncode == 0 and result.stdout.strip():
            return json.loads(result.stdout)
    except (subprocess.TimeoutExpired, json.JSONDecodeError, OSError) as e:
        return {"error": str(e)}
    return {"error": f"exit code {result.returncode}: {result.stderr.strip()[:100]}"}


def format_duration(seconds):
    if seconds < 60:
        return f"{seconds:.0f}s"
    elif seconds < 3600:
        return f"{int(seconds // 60)}m {int(seconds % 60)}s"
    else:
        return f"{int(seconds // 3600)}h {int((seconds % 3600) // 60)}m"


def main():
    devices = load_devices()
    w = 88

    print("=" * w)
    print(f"  {BOLD}CLAUDE CODE SESSIONS — ALL DEVICES{R}")
    print("=" * w)

    grand_active_cost = 0.0
    grand_total_cost = 0.0
    grand_active_count = 0
    all_active = []

    for host, device_name in devices:
        print()
        print(f"  {CYAN}{BOLD}{device_name}{R}  {DIM}({host}){R}")
        print("  " + "-" * (w - 4))

        data = fetch_sessions(host)

        if isinstance(data, dict) and "error" in data:
            print(f"  {RED}unreachable{R} — {DIM}{data['error']}{R}")
            continue

        sessions = data.get("sessions", [])
        if not sessions:
            print(f"  {DIM}No sessions found{R}")
            continue

        active = [s for s in sessions if s.get("alive")]
        recent = [s for s in sessions if not s.get("alive")]

        device_active_cost = sum(s.get("cost", 0) for s in active)
        device_total_cost = sum(s.get("cost", 0) for s in sessions)
        grand_active_cost += device_active_cost
        grand_total_cost += device_total_cost
        grand_active_count += len(active)

        for s in active:
            _print_session(s, active=True)
            all_active.append({**s, "device": device_name})
        for s in recent:
            _print_session(s, active=False)

        print(f"  {DIM}Device total: ${device_total_cost:.2f} "
              f"({len(active)} active, {len(recent)} recent){R}")

    # Grand summary
    print()
    print("=" * w)
    print(f"  {BOLD}TOTAL{R}  "
          f"Active: {grand_active_count} sessions  ${grand_active_cost:.2f}  |  "
          f"All visible: ${grand_total_cost:.2f}")
    print("=" * w)

    if len(all_active) > 1 and grand_active_cost > 0:
        print()
        print(f"  {BOLD}COST SHARE (active sessions){R}")
        print("  " + "-" * (w - 4))
        for s in sorted(all_active, key=lambda x: x.get("cost", 0), reverse=True):
            cost = s.get("cost", 0)
            pct = (cost / grand_active_cost * 100) if grand_active_cost > 0 else 0
            bar_len = int(pct / 100 * 30)
            bar = "█" * bar_len + "░" * (30 - bar_len)
            label = s.get("name") or s.get("sid", "?")[:8]
            device = s.get("device", "?")
            print(f"  {bar}  {pct:5.1f}%  ${cost:>8.2f}  {device}: {label}")
        print()


def _print_session(s, active=False):
    sid_short = s.get("sid", "?")[:8]
    status = f"{GREEN}●{R}" if active else f"{DIM}○{R}"
    label = s.get("name") or s.get("cwd_short") or sid_short
    if len(label) > 28:
        label = label[:25] + "..."
    dur_str = format_duration(s.get("duration", 0))
    cost_str = f"${s.get('cost', 0):.4f}"
    turns = s.get("turns", 0)
    model_str = ",".join(s.get("models", [])) or "?"

    print(f"  {status} {sid_short}  {label:<28s}  {dur_str:>8s}  {turns:>4d}t  "
          f"{cost_str:>10s}  {DIM}{model_str}{R}")


if __name__ == "__main__":
    main()
