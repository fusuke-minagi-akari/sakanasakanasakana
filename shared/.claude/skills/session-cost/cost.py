#!/usr/bin/env python3
"""Session cost analyzer for Claude Code.

Usage: python3 cost.py <transcript.jsonl> [model-override]

Reads a Claude Code session transcript and reports:
- Token counts (input, output, cache creation, cache read)
- Cost breakdown in both USD and JPY
- Session duration and per-turn timing
- Percentage of daily/weekly limits used by this session
"""

import json
import sys
import os
import glob
import urllib.request
import urllib.error
from datetime import datetime, timezone

# ── Pricing (per million tokens) ─────────────────────────────────────────────
PRICING = {
    "claude-opus-4-6":   {"input": 5.00, "output": 25.00, "cache_create_mult": 1.25, "cache_read_mult": 0.10},
    "claude-sonnet-4-6": {"input": 3.00, "output": 15.00, "cache_create_mult": 1.25, "cache_read_mult": 0.10},
    "claude-haiku-4-5":  {"input": 1.00, "output":  5.00, "cache_create_mult": 1.25, "cache_read_mult": 0.10},
    # Aliases
    "opus":   "claude-opus-4-6",
    "sonnet": "claude-sonnet-4-6",
    "haiku":  "claude-haiku-4-5",
}

LIMITS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "limits.json")

def load_limits():
    """Load 5h/weekly USD limits from limits.json."""
    try:
        with open(LIMITS_PATH) as f:
            data = json.load(f)
        return data.get("five_hour_usd"), data.get("weekly_usd"), data.get("plan", "unknown")
    except (OSError, json.JSONDecodeError):
        return None, None, None

def resolve_pricing(model_id):
    """Resolve model ID to pricing dict, handling aliases and partial matches."""
    if not model_id:
        return None, None
    model_id = model_id.lower().strip()
    if model_id in PRICING:
        v = PRICING[model_id]
        if isinstance(v, str):
            return v, PRICING[v]
        return model_id, v
    for key, val in PRICING.items():
        if isinstance(val, dict) and key in model_id:
            return key, val
    return model_id, None


def parse_transcript(path):
    """Parse a JSONL transcript and return usage stats."""
    path = os.path.expanduser(path)
    if not os.path.exists(path):
        print(f"Error: transcript not found at {path}")
        sys.exit(1)

    stats = {
        "turns": 0,
        "input_tokens": 0,
        "output_tokens": 0,
        "cache_creation_tokens": 0,
        "cache_read_tokens": 0,
        "models_used": {},
        "first_user_ts": None,
        "last_assistant_ts": None,
        "user_timestamps": [],
        "assistant_timestamps": [],
        "web_search_requests": 0,
        "web_fetch_requests": 0,
        "per_model": {},
    }

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
                if stats["first_user_ts"] is None:
                    stats["first_user_ts"] = ts
                stats["user_timestamps"].append(ts)

            if msg_type == "assistant":
                msg = obj.get("message", {})
                usage = msg.get("usage", {})
                model = msg.get("model", "unknown")

                if ts:
                    stats["last_assistant_ts"] = ts
                    stats["assistant_timestamps"].append(ts)

                inp = usage.get("input_tokens", 0)
                out = usage.get("output_tokens", 0)
                cc = usage.get("cache_creation_input_tokens", 0)
                cr = usage.get("cache_read_input_tokens", 0)

                stats["input_tokens"] += inp
                stats["output_tokens"] += out
                stats["cache_creation_tokens"] += cc
                stats["cache_read_tokens"] += cr
                stats["turns"] += 1

                stats["models_used"][model] = stats["models_used"].get(model, 0) + 1
                if model not in stats["per_model"]:
                    stats["per_model"][model] = {"input": 0, "output": 0, "cache_create": 0, "cache_read": 0}
                stats["per_model"][model]["input"] += inp
                stats["per_model"][model]["output"] += out
                stats["per_model"][model]["cache_create"] += cc
                stats["per_model"][model]["cache_read"] += cr

                stu = usage.get("server_tool_use", {})
                stats["web_search_requests"] += stu.get("web_search_requests", 0)
                stats["web_fetch_requests"] += stu.get("web_fetch_requests", 0)

    return stats


def calc_cost(input_tok, output_tok, cache_create_tok, cache_read_tok, pricing):
    """Calculate cost given token counts and pricing dict."""
    if pricing is None:
        return None
    rate = 1 / 1_000_000
    input_cost = input_tok * pricing["input"] * rate
    output_cost = output_tok * pricing["output"] * rate
    cache_create_cost = cache_create_tok * pricing["input"] * pricing["cache_create_mult"] * rate
    cache_read_cost = cache_read_tok * pricing["input"] * pricing["cache_read_mult"] * rate
    return {
        "input": input_cost,
        "output": output_cost,
        "cache_create": cache_create_cost,
        "cache_read": cache_read_cost,
        "total": input_cost + output_cost + cache_create_cost + cache_read_cost,
    }


def parse_ts(ts_str):
    """Parse ISO timestamp string."""
    if not ts_str:
        return None
    try:
        return datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None


def format_duration(seconds):
    """Format seconds into human readable duration."""
    if seconds < 60:
        return f"{seconds:.1f}s"
    elif seconds < 3600:
        m = int(seconds // 60)
        s = seconds % 60
        return f"{m}m {s:.0f}s"
    else:
        h = int(seconds // 3600)
        m = int((seconds % 3600) // 60)
        return f"{h}h {m}m"


def fetch_usd_jpy_rate():
    """Fetch current USD/JPY exchange rate from a free API."""
    try:
        url = "https://open.er-api.com/v6/latest/USD"
        req = urllib.request.Request(url, headers={"User-Agent": "claude-code-cost/1.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode())
            if data.get("result") == "success":
                return data["rates"].get("JPY")
    except (urllib.error.URLError, json.JSONDecodeError, KeyError, OSError):
        pass
    return None


def bar(pct, width=20):
    """Render a progress bar."""
    filled = int(pct / 100 * width)
    filled = min(filled, width)
    return "█" * filled + "░" * (width - filled)


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 cost.py <transcript.jsonl> [model-override]")
        sys.exit(1)

    path = sys.argv[1]

    stats = parse_transcript(path)

    if stats["turns"] == 0:
        print("No assistant messages found in transcript.")
        sys.exit(0)

    # ── Timing ───────────────────────────────────────────────────────────
    first_ts = parse_ts(stats["first_user_ts"])
    last_ts = parse_ts(stats["last_assistant_ts"])
    duration = (last_ts - first_ts).total_seconds() if first_ts and last_ts else None

    # ── Totals ───────────────────────────────────────────────────────────
    total_input_equiv = stats["input_tokens"] + stats["cache_creation_tokens"] + stats["cache_read_tokens"]
    total_all = total_input_equiv + stats["output_tokens"]

    # ── Per-model cost (actual) ──────────────────────────────────────────
    per_model_costs = {}
    cost_total = {"input": 0, "output": 0, "cache_create": 0, "cache_read": 0, "total": 0}
    nocache_total = 0.0
    unknown_models = []

    for model, counts in stats["per_model"].items():
        _, model_pricing = resolve_pricing(model)
        if model_pricing is None:
            unknown_models.append(model)
            continue
        mc = calc_cost(counts["input"], counts["output"], counts["cache_create"], counts["cache_read"], model_pricing)
        per_model_costs[model] = mc
        for k in cost_total:
            cost_total[k] += mc[k]
        # nocache for this model
        rate = 1 / 1_000_000
        equiv = counts["input"] + counts["cache_create"] + counts["cache_read"]
        nocache_total += equiv * model_pricing["input"] * rate + counts["output"] * model_pricing["output"] * rate

    cost = cost_total if cost_total["total"] > 0 else None
    nocache_cost = nocache_total if nocache_total > 0 else None

    # ── JPY Rate ─────────────────────────────────────────────────────────
    jpy_rate = fetch_usd_jpy_rate()

    # ── Limits ───────────────────────────────────────────────────────────
    daily_limit, weekly_limit, plan_name = load_limits()

    # ── Print Report ─────────────────────────────────────────────────────
    w = 60
    print("=" * w)
    print("  SESSION COST REPORT")
    print("=" * w)

    # Timing
    print()
    print("  TIMING")
    print("  " + "-" * (w - 4))
    if duration:
        print(f"  Session duration:    {format_duration(duration)}")
    if first_ts:
        print(f"  Started:             {first_ts.strftime('%Y-%m-%d %H:%M:%S %Z')}")
    if last_ts:
        print(f"  Last activity:       {last_ts.strftime('%Y-%m-%d %H:%M:%S %Z')}")
    print(f"  Assistant turns:     {stats['turns']}")
    if duration and stats["turns"] > 0:
        print(f"  Avg time per turn:   {format_duration(duration / stats['turns'])}")

    # Tokens
    print()
    print("  TOKENS")
    print("  " + "-" * (w - 4))
    print(f"  Input tokens:        {stats['input_tokens']:>14,}")
    print(f"  Output tokens:       {stats['output_tokens']:>14,}")
    print(f"  Cache creation:      {stats['cache_creation_tokens']:>14,}")
    print(f"  Cache read:          {stats['cache_read_tokens']:>14,}")
    print(f"                       {'':>14}")
    print(f"  Total tokens:        {total_all:>14,}")

    # Per-model breakdown (tokens + cost)
    if len(stats["per_model"]) > 1:
        print()
        print("  COST BY MODEL")
        print("  " + "-" * (w - 4))
        for model, counts in sorted(stats["per_model"].items(), key=lambda x: -sum(x[1].values())):
            turns = stats["models_used"].get(model, 0)
            mc = per_model_costs.get(model)
            model_short = model.replace("claude-", "")
            if mc:
                cost_str = f"${mc['total']:.4f}"
                if jpy_rate:
                    cost_str += f"  (¥{mc['total'] * jpy_rate:,.0f})"
                print(f"  {model_short:<20s} {turns:>3d} turns   {cost_str}")
            else:
                print(f"  {model_short:<20s} {turns:>3d} turns   (unknown pricing)")
            total_tok = counts["input"] + counts["output"] + counts["cache_create"] + counts["cache_read"]
            print(f"    tokens: {total_tok:>12,}  (in={counts['input']:,} out={counts['output']:,} cc={counts['cache_create']:,} cr={counts['cache_read']:,})")

    # Cost
    print()
    models_list = ", ".join(sorted(set(
        resolve_pricing(m)[0] or m for m in stats["per_model"]
    )))
    print(f"  COST TOTAL ({models_list})")
    print("  " + "-" * (w - 4))
    if cost:
        def cost_line(label, usd):
            if jpy_rate:
                return f"  {label:<20s} ${usd:>8.4f}   ¥{usd * jpy_rate:>8.0f}"
            return f"  {label:<20s} ${usd:>8.4f}"

        if jpy_rate:
            print(f"  {'':20s} {'USD':>9s}   {'JPY':>9s}")
        print(cost_line("Input:", cost['input']))
        print(cost_line("Output:", cost['output']))
        print(cost_line("Cache creation:", cost['cache_create']))
        print(cost_line("Cache read:", cost['cache_read']))
        print()
        print(cost_line("TOTAL:", cost['total']))
        if nocache_cost:
            savings = nocache_cost - cost["total"]
            pct = (savings / nocache_cost * 100) if nocache_cost > 0 else 0
            print()
            print(cost_line("Without caching:", nocache_cost))
            print(f"  {'Cache savings:':<20s} ${savings:>8.4f}   ", end="")
            if jpy_rate:
                print(f"¥{savings * jpy_rate:>8.0f}  ({pct:.0f}%)")
            else:
                print(f"({pct:.0f}%)")
        if jpy_rate:
            print()
            print(f"  Exchange rate:       1 USD = {jpy_rate:.2f} JPY")
    else:
        print(f"  (No cost data — unknown model pricing)")
        print(f"  Update PRICING dict in cost.py to add rates.")
    if unknown_models:
        print()
        print(f"  Warning: unknown pricing for: {', '.join(unknown_models)}")

    # Limit usage (this session's share)
    five_hour_limit, weekly_limit, plan_name2 = load_limits()
    if cost and (five_hour_limit or weekly_limit):
        print()
        print(f"  SESSION vs LIMITS (plan: {plan_name2 or 'unknown'})")
        print("  " + "-" * (w - 4))
        if five_hour_limit:
            pct_5h = cost["total"] / five_hour_limit * 100
            print(f"  5h:      {bar(pct_5h)} {pct_5h:>5.1f}%  (${cost['total']:.4f} / ${five_hour_limit:.2f})")
        if weekly_limit:
            pct_wk = cost["total"] / weekly_limit * 100
            print(f"  Weekly:  {bar(pct_wk)} {pct_wk:>5.1f}%  (${cost['total']:.4f} / ${weekly_limit:.2f})")
        print(f"  (this session only — use /usage-improv for aggregate)")

    # Web tool usage
    if stats["web_search_requests"] or stats["web_fetch_requests"]:
        print()
        print("  WEB TOOL USAGE")
        print("  " + "-" * (w - 4))
        print(f"  Web searches:        {stats['web_search_requests']}")
        print(f"  Web fetches:         {stats['web_fetch_requests']}")

    # Efficiency
    if cost and duration:
        print()
        print("  EFFICIENCY")
        print("  " + "-" * (w - 4))
        cpm = cost['total'] / (duration / 60)
        if jpy_rate:
            print(f"  Cost per minute:     ${cpm:.4f}  (¥{cpm * jpy_rate:.0f})")
        else:
            print(f"  Cost per minute:     ${cpm:.4f}")
        if stats["output_tokens"] > 0:
            out_per_sec = stats["output_tokens"] / duration
            print(f"  Output tokens/sec:   {out_per_sec:>14.1f}")

    print()
    print("=" * w)


if __name__ == "__main__":
    main()
