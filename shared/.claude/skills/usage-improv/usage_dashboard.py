#!/usr/bin/env python3
"""Enhanced usage dashboard for Claude Code.

Scans all session transcripts to show:
- All sessions today and this week with per-session cost
- Aggregate daily/weekly cost in USD + JPY
- Progress bars for cost limits, tokens, cache, sessions
- Active sessions (currently running)
- Current session highlight
- Optional --watch mode for real-time refresh
"""

import json
import os
import sys
import glob
import time
import argparse
import urllib.request
import urllib.error
from datetime import datetime, timezone, timedelta

CLAUDE_DIR = os.path.expanduser("~/.claude")
PROJECTS_DIR = os.path.join(CLAUDE_DIR, "projects")
SESSIONS_DIR = os.path.join(CLAUDE_DIR, "sessions")
LIMITS_PATH = os.path.join(CLAUDE_DIR, "skills", "session-cost", "limits.json")

PRICING = {
    "claude-opus-4-6":   {"input": 5.00, "output": 25.00, "cache_create_mult": 1.25, "cache_read_mult": 0.10},
    "claude-sonnet-4-6": {"input": 3.00, "output": 15.00, "cache_create_mult": 1.25, "cache_read_mult": 0.10},
    "claude-haiku-4-5":  {"input": 1.00, "output":  5.00, "cache_create_mult": 1.25, "cache_read_mult": 0.10},
}

# ANSI color codes
C_RESET  = "\033[0m"
C_BOLD   = "\033[1m"
C_DIM    = "\033[2m"
C_WHITE  = "\033[97m"
C_CYAN   = "\033[36m"
C_YELLOW = "\033[33m"
C_GREEN  = "\033[32m"
C_RED    = "\033[31m"
C_BLUE   = "\033[34m"
C_MAGENTA = "\033[35m"
C_BG_DARK = "\033[48;5;236m"
C_STAR   = "\033[93m"  # bright yellow


def resolve_pricing(model_id):
    if not model_id:
        return None
    model_id = model_id.lower().strip()
    for key, val in PRICING.items():
        if isinstance(val, dict) and key in model_id:
            return val
    return None


def load_limits():
    try:
        with open(LIMITS_PATH) as f:
            data = json.load(f)
        return data.get("five_hour_usd"), data.get("weekly_usd"), data.get("plan", "unknown")
    except (OSError, json.JSONDecodeError):
        return None, None, None


def fetch_usd_jpy_rate():
    try:
        url = "https://open.er-api.com/v6/latest/USD"
        req = urllib.request.Request(url, headers={"User-Agent": "claude-code-usage/1.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode())
            if data.get("result") == "success":
                return data["rates"].get("JPY")
    except (urllib.error.URLError, json.JSONDecodeError, KeyError, OSError):
        pass
    return None


def parse_ts(ts_str):
    if not ts_str:
        return None
    try:
        return datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None


def load_session_metadata():
    """Load session metadata from sessions/*.json."""
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


def scan_transcript(path):
    """Quick scan of a transcript — returns summary dict or None."""
    first_ts = None
    last_ts = None
    turns = 0
    input_tokens = 0
    output_tokens = 0
    cache_create = 0
    cache_read = 0
    models = {}
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

                if msg_type == "user" and ts:
                    if first_ts is None:
                        first_ts = ts

                if msg_type == "assistant":
                    msg = obj.get("message", {})
                    usage = msg.get("usage", {})
                    model = msg.get("model", "unknown")

                    if ts:
                        last_ts = ts

                    inp = usage.get("input_tokens", 0)
                    out = usage.get("output_tokens", 0)
                    cc = usage.get("cache_creation_input_tokens", 0)
                    cr = usage.get("cache_read_input_tokens", 0)

                    input_tokens += inp
                    output_tokens += out
                    cache_create += cc
                    cache_read += cr
                    turns += 1
                    models[model] = models.get(model, 0) + 1

                    if model not in per_model:
                        per_model[model] = {"input": 0, "output": 0, "cache_create": 0, "cache_read": 0}
                    per_model[model]["input"] += inp
                    per_model[model]["output"] += out
                    per_model[model]["cache_create"] += cc
                    per_model[model]["cache_read"] += cr
    except OSError:
        return None

    if turns == 0:
        return None

    cost_usd = 0.0
    rate = 1 / 1_000_000
    for model, counts in per_model.items():
        pricing = resolve_pricing(model)
        if pricing:
            cost_usd += (
                counts["input"] * pricing["input"] * rate
                + counts["output"] * pricing["output"] * rate
                + counts["cache_create"] * pricing["input"] * pricing["cache_create_mult"] * rate
                + counts["cache_read"] * pricing["input"] * pricing["cache_read_mult"] * rate
            )

    primary_model = max(models, key=models.get) if models else "unknown"
    sid = os.path.basename(path).replace(".jsonl", "")

    return {
        "session_id": sid,
        "first_ts": first_ts,
        "last_ts": last_ts,
        "turns": turns,
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "cache_create": cache_create,
        "cache_read": cache_read,
        "total_tokens": input_tokens + output_tokens + cache_create + cache_read,
        "cost_usd": cost_usd,
        "primary_model": primary_model,
        "path": path,
    }


def format_duration(seconds):
    if seconds < 60:
        return f"{seconds:.0f}s"
    elif seconds < 3600:
        return f"{int(seconds // 60)}m {int(seconds % 60)}s"
    else:
        return f"{int(seconds // 3600)}h {int((seconds % 3600) // 60)}m"


def progress_bar(value, maximum, width=30, label="", show_pct=True, color=None, warn_threshold=0.8, crit_threshold=0.95):
    """Render a colored progress bar with optional label."""
    if maximum <= 0:
        pct = 0
    else:
        pct = min(value / maximum, 1.0)

    filled = int(pct * width)
    empty = width - filled

    # Auto-color based on thresholds
    if color is None:
        if pct >= crit_threshold:
            color = C_RED
        elif pct >= warn_threshold:
            color = C_YELLOW
        else:
            color = C_GREEN

    bar_str = f"{color}{'━' * filled}{C_DIM}{'─' * empty}{C_RESET}"
    pct_str = f" {pct * 100:5.1f}%" if show_pct else ""

    if label:
        return f"  {label}  {bar_str}{pct_str}"
    return f"  {bar_str}{pct_str}"


def mini_bar(value, maximum, width=12, color=C_CYAN):
    """Small inline bar for session rows."""
    if maximum <= 0:
        return "─" * width
    pct = min(value / maximum, 1.0)
    filled = int(pct * width)
    return f"{color}{'━' * filled}{C_DIM}{'─' * (width - filled)}{C_RESET}"


def section_header(title, width=70):
    """Render a styled section header."""
    pad = width - len(title) - 6
    return f"\n  {C_BOLD}{C_CYAN}┌─ {title} {'─' * max(pad, 0)}┐{C_RESET}"


def section_line(width=70):
    return f"  {C_DIM}{'─' * (width - 4)}{C_RESET}"


def format_cost(usd, jpy_rate=None):
    """Format cost as USD + JPY."""
    s = f"${usd:,.4f}"
    if jpy_rate:
        s += f"  {C_DIM}(¥{usd * jpy_rate:,.0f}){C_RESET}"
    return s


def format_tokens(n):
    """Human-readable token count."""
    if n >= 1_000_000_000:
        return f"{n / 1_000_000_000:.1f}B"
    elif n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    elif n >= 1_000:
        return f"{n / 1_000:.1f}K"
    return str(n)


def render_dashboard(current_session_id=None, jpy_rate=None):
    """Render the dashboard once. Returns the output as a string."""
    lines = []
    p = lines.append

    now = datetime.now(timezone.utc)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    five_hour_ago = now - timedelta(hours=5)
    week_start = today_start - timedelta(days=today_start.weekday())

    w = 70

    # Load limits
    five_hour_limit, weekly_limit, plan_name = load_limits()

    # Scan all transcripts
    all_transcripts = []
    for proj_dir in glob.glob(os.path.join(PROJECTS_DIR, "*")):
        if not os.path.isdir(proj_dir):
            continue
        for jsonl in glob.glob(os.path.join(proj_dir, "*.jsonl")):
            all_transcripts.append(jsonl)

    sessions = []
    for t_path in all_transcripts:
        result = scan_transcript(t_path)
        if result:
            sessions.append(result)

    # Classify
    five_hour_sessions = []
    today_sessions = []
    week_sessions = []

    for s in sessions:
        ts = parse_ts(s["last_ts"]) or parse_ts(s["first_ts"])
        if ts is None:
            continue
        if ts >= five_hour_ago:
            five_hour_sessions.append(s)
        if ts >= today_start:
            today_sessions.append(s)
            week_sessions.append(s)
        elif ts >= week_start:
            week_sessions.append(s)

    today_sessions.sort(key=lambda s: s["last_ts"] or "", reverse=True)
    week_sessions.sort(key=lambda s: s["last_ts"] or "", reverse=True)

    session_meta = load_session_metadata()

    # Totals
    five_hour_cost = sum(s["cost_usd"] for s in five_hour_sessions)
    today_cost = sum(s["cost_usd"] for s in today_sessions)
    week_cost = sum(s["cost_usd"] for s in week_sessions)
    today_tokens = sum(s["total_tokens"] for s in today_sessions)
    week_tokens = sum(s["total_tokens"] for s in week_sessions)
    today_turns = sum(s["turns"] for s in today_sessions)
    today_cache_read = sum(s["cache_read"] for s in today_sessions)
    today_cache_total = sum(s["cache_create"] + s["cache_read"] for s in today_sessions)

    # Find current session
    current_session_data = None
    if current_session_id:
        for s in sessions:
            if s["session_id"] == current_session_id:
                current_session_data = s
                break

    # Active sessions
    active_pids = set()
    active_metas = []
    for meta_sid, meta in session_meta.items():
        pid = meta.get("pid")
        if pid:
            try:
                os.kill(pid, 0)
                active_pids.add(meta_sid)
                active_metas.append(meta)
            except OSError:
                pass

    # ═══════════════════════════════════════════════════════════════════
    # HEADER
    # ═══════════════════════════════════════════════════════════════════
    p(f"  {C_BOLD}{C_CYAN}╔{'═' * (w - 4)}╗{C_RESET}")
    p(f"  {C_BOLD}{C_CYAN}║{C_RESET}  {C_BOLD}{C_WHITE}CLAUDE CODE USAGE DASHBOARD{C_RESET}{'':>{w - 33}}{C_BOLD}{C_CYAN}║{C_RESET}")
    p(f"  {C_BOLD}{C_CYAN}║{C_RESET}  {C_DIM}{now.strftime('%Y-%m-%d %H:%M:%S UTC')}{C_RESET}{'':>{w - 29}}{C_BOLD}{C_CYAN}║{C_RESET}")
    if jpy_rate:
        rate_str = f"1 USD = {jpy_rate:.2f} JPY"
        p(f"  {C_BOLD}{C_CYAN}║{C_RESET}  {C_DIM}{rate_str}{C_RESET}{'':>{w - len(rate_str) - 6}}{C_BOLD}{C_CYAN}║{C_RESET}")
    if plan_name:
        plan_str = f"Plan: {plan_name}"
        p(f"  {C_BOLD}{C_CYAN}║{C_RESET}  {C_DIM}{plan_str}{C_RESET}{'':>{w - len(plan_str) - 6}}{C_BOLD}{C_CYAN}║{C_RESET}")
    p(f"  {C_BOLD}{C_CYAN}╚{'═' * (w - 4)}╝{C_RESET}")

    # ═══════════════════════════════════════════════════════════════════
    # COST LIMITS (progress bars)
    # ═══════════════════════════════════════════════════════════════════
    p(section_header("COST LIMITS", w))

    if five_hour_limit:
        p(f"  {C_BOLD}5-hour window{C_RESET}   {format_cost(five_hour_cost, jpy_rate)}  /  ${five_hour_limit:.0f}")
        p(progress_bar(five_hour_cost, five_hour_limit, width=40, label="         "))
    else:
        p(f"  {C_BOLD}Last 5h{C_RESET}  {format_cost(five_hour_cost, jpy_rate)}  ({len(five_hour_sessions)} sessions)")

    p("")
    if weekly_limit:
        p(f"  {C_BOLD}Weekly{C_RESET}          {format_cost(week_cost, jpy_rate)}  /  ${weekly_limit:.0f}")
        p(progress_bar(week_cost, weekly_limit, width=40, label="         "))
    else:
        p(f"  {C_BOLD}Weekly{C_RESET}   {format_cost(week_cost, jpy_rate)}  ({len(week_sessions)} sessions)")

    # ═══════════════════════════════════════════════════════════════════
    # CURRENT SESSION
    # ═══════════════════════════════════════════════════════════════════
    if current_session_data:
        cs = current_session_data
        p(section_header("CURRENT SESSION", w))

        meta = session_meta.get(current_session_id, {})
        name = meta.get("name")
        cwd = meta.get("cwd", "")
        label = name or os.path.basename(cwd) or current_session_id[:8]

        first = parse_ts(cs["first_ts"])
        last = parse_ts(cs["last_ts"])
        dur = format_duration((last - first).total_seconds()) if first and last else "?"

        model_short = cs["primary_model"].replace("claude-", "").replace("-4-6", "").replace("-4-5", "")
        cache_total = cs["cache_create"] + cs["cache_read"]
        cache_pct = (cs["cache_read"] / cache_total * 100) if cache_total > 0 else 0

        p(f"  {C_STAR}★{C_RESET} {C_BOLD}{label}{C_RESET}  {C_DIM}({current_session_id[:12]}...){C_RESET}")
        p(f"    Model: {C_BOLD}{model_short}{C_RESET}  |  Duration: {C_BOLD}{dur}{C_RESET}  |  Turns: {C_BOLD}{cs['turns']}{C_RESET}")
        p(f"    Cost:  {C_BOLD}{format_cost(cs['cost_usd'], jpy_rate)}{C_RESET}")
        p(f"    Tokens: {format_tokens(cs['total_tokens'])}")

        # Cache hit bar
        p(f"    Cache:  {progress_bar(cache_pct, 100, width=20, label='', show_pct=True, color=C_GREEN if cache_pct > 80 else C_YELLOW if cache_pct > 50 else C_RED, warn_threshold=2, crit_threshold=2).strip()}  hit rate")

        # Token breakdown bar
        total_tk = cs["input_tokens"] + cs["output_tokens"] + cs["cache_create"] + cs["cache_read"]
        if total_tk > 0:
            tk_bar_w = 40
            inp_w = max(int(cs["input_tokens"] / total_tk * tk_bar_w), 0)
            out_w = max(int(cs["output_tokens"] / total_tk * tk_bar_w), 0)
            cc_w = max(int(cs["cache_create"] / total_tk * tk_bar_w), 0)
            cr_w = tk_bar_w - inp_w - out_w - cc_w
            cr_w = max(cr_w, 0)
            tk_bar = (f"{C_BLUE}{'━' * inp_w}{C_MAGENTA}{'━' * out_w}"
                      f"{C_YELLOW}{'━' * cc_w}{C_GREEN}{'━' * cr_w}{C_RESET}")
            p(f"    Tokens: {tk_bar}")
            p(f"            {C_BLUE}━{C_RESET}in  {C_MAGENTA}━{C_RESET}out  {C_YELLOW}━{C_RESET}cache-w  {C_GREEN}━{C_RESET}cache-r")

    # ═══════════════════════════════════════════════════════════════════
    # TODAY'S SESSIONS
    # ═══════════════════════════════════════════════════════════════════
    p(section_header(f"TODAY  {now.strftime('%Y-%m-%d')}  —  {len(today_sessions)} sessions", w))

    # Summary stats
    p(f"  Cost:    {C_BOLD}{format_cost(today_cost, jpy_rate)}{C_RESET}")
    p(f"  Tokens:  {C_BOLD}{format_tokens(today_tokens)}{C_RESET}   Turns: {C_BOLD}{today_turns}{C_RESET}")

    if today_cache_total > 0:
        today_cache_pct = today_cache_read / today_cache_total * 100
        p(f"  Cache:   {today_cache_pct:.0f}% hit rate")
    p("")

    # Session table
    if today_sessions:
        max_cost_today = max(s["cost_usd"] for s in today_sessions) if today_sessions else 1
        for s in today_sessions:
            sid = s["session_id"]
            sid_short = sid[:8]
            is_current = (sid == current_session_id)
            is_active = sid in active_pids

            meta = session_meta.get(sid, {})
            name = meta.get("name")
            cwd = meta.get("cwd", "")
            label = name or os.path.basename(cwd or "") or sid_short
            if len(label) > 22:
                label = label[:19] + "..."

            first = parse_ts(s["first_ts"])
            last = parse_ts(s["last_ts"])
            dur = format_duration((last - first).total_seconds()) if first and last else ""

            cost_str = f"${s['cost_usd']:>8.4f}"
            jpy_str = f"¥{s['cost_usd'] * jpy_rate:>6,.0f}" if jpy_rate else ""

            # Status indicator
            if is_current:
                marker = f"{C_STAR}★{C_RESET}"
            elif is_active:
                marker = f"{C_GREEN}●{C_RESET}"
            else:
                marker = f"{C_DIM}○{C_RESET}"

            cost_bar = mini_bar(s["cost_usd"], max_cost_today, width=10,
                                color=C_STAR if is_current else C_CYAN)

            p(f"  {marker} {C_BOLD if is_current else ''}{label:<22s}{C_RESET if is_current else ''}"
              f"  {dur:>7s}  {s['turns']:>4d}t"
              f"  {cost_bar}  {cost_str} {C_DIM}{jpy_str}{C_RESET}")

    # ═══════════════════════════════════════════════════════════════════
    # EARLIER THIS WEEK
    # ═══════════════════════════════════════════════════════════════════
    week_only = [s for s in week_sessions if s not in today_sessions]
    if week_only:
        p(section_header(f"EARLIER THIS WEEK  —  {len(week_only)} sessions", w))
        week_only_cost = sum(s["cost_usd"] for s in week_only)
        week_only_tokens = sum(s["total_tokens"] for s in week_only)
        week_only_turns = sum(s["turns"] for s in week_only)
        p(f"  Cost:    {C_BOLD}{format_cost(week_only_cost, jpy_rate)}{C_RESET}")
        p(f"  Tokens:  {format_tokens(week_only_tokens)}   Turns: {week_only_turns}")

    # ═══════════════════════════════════════════════════════════════════
    # WEEK TOTAL
    # ═══════════════════════════════════════════════════════════════════
    if week_only:
        p(section_header(f"WEEK TOTAL  {week_start.strftime('%m/%d')} – {now.strftime('%m/%d')}", w))
        p(f"  Cost:      {C_BOLD}{format_cost(week_cost, jpy_rate)}{C_RESET}")
        p(f"  Tokens:    {format_tokens(week_tokens)}")
        p(f"  Sessions:  {len(week_sessions)}")

        if weekly_limit:
            daily_avg = week_cost / max((now - week_start).days, 1)
            p(f"  Daily avg: {format_cost(daily_avg, jpy_rate)}")

    # ═══════════════════════════════════════════════════════════════════
    # ACTIVE SESSIONS
    # ═══════════════════════════════════════════════════════════════════
    if active_metas:
        p(section_header(f"ACTIVE  —  {len(active_metas)} sessions", w))
        for meta in active_metas:
            sid = meta.get("sessionId", "?")
            sid_short = sid[:8]
            is_current = (sid == current_session_id)
            name = meta.get("name", "")
            cwd = meta.get("cwd", "")
            label = name or os.path.basename(cwd) or "unknown"
            if len(label) > 30:
                label = label[:27] + "..."
            pid = meta.get("pid", "?")
            if is_current:
                marker = f"{C_STAR}★{C_RESET}"
            else:
                marker = f"{C_GREEN}●{C_RESET}"
            p(f"  {marker} {sid_short}  PID {pid:<6}  {label}")

    # ═══════════════════════════════════════════════════════════════════
    # FOOTER
    # ═══════════════════════════════════════════════════════════════════
    p(f"\n  {C_DIM}{'─' * (w - 4)}{C_RESET}")
    p(f"  {C_DIM}Data: real-time from ~/.claude transcript files{C_RESET}")
    p(f"  {C_DIM}Limits are estimates — use /usage for official numbers{C_RESET}")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Claude Code usage dashboard")
    parser.add_argument("--session", default=None, help="Current session ID for highlighting")
    parser.add_argument("--watch", nargs="?", const=5, type=int, metavar="SECS",
                        help="Refresh every N seconds (default: 5)")
    args = parser.parse_args()

    # Fetch JPY rate once (not on every refresh)
    jpy_rate = fetch_usd_jpy_rate()

    if args.watch:
        interval = max(args.watch, 2)  # minimum 2s
        try:
            while True:
                # Clear screen
                print("\033[2J\033[H", end="")
                output = render_dashboard(
                    current_session_id=args.session,
                    jpy_rate=jpy_rate,
                )
                print(output)
                print(f"  {C_DIM}Refreshing every {interval}s — Ctrl+C to stop{C_RESET}")
                time.sleep(interval)
        except KeyboardInterrupt:
            print("\n  Dashboard stopped.")
    else:
        output = render_dashboard(
            current_session_id=args.session,
            jpy_rate=jpy_rate,
        )
        print(output)


if __name__ == "__main__":
    main()
