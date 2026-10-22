#!/usr/bin/env python3
"""Print Claude (2 accounts) + Codex limit usage as JSON for UsageBar.swift."""
import glob, hashlib, json, os, subprocess, time, urllib.error, urllib.request
from datetime import datetime

CACHE = os.path.expanduser("~/.local/usagebar/cache.json")
# anthropic oauth/usage 429s at 1/min per account (Retry-After: 0); codex is fine at 1/min
CLAUDE_MIN_INTERVAL = 180


def claude_accounts():
    """[(label, keychain service)] for ~/.claude ("main") and every ~/.claude-<label> that is logged in.
    Claude Code names the keychain item "Claude Code-credentials" + "-" + sha256(CLAUDE_CONFIG_DIR)[:8]."""
    dirs = [("main", None)] + [(d.rsplit(".claude-", 1)[1], d) for d in sorted(glob.glob(os.path.expanduser("~/.claude-*")))
                               if os.path.isdir(d)]
    for label, d in dirs:
        svc = "Claude Code-credentials" + (f"-{hashlib.sha256(d.encode()).hexdigest()[:8]}" if d else "")
        if subprocess.run(["security", "find-generic-password", "-s", svc], capture_output=True, timeout=10).returncode == 0:
            yield label, svc


def get(url, headers):
    req = urllib.request.Request(url, headers={"User-Agent": "usagebar", **headers})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)


def iso(s):
    return datetime.fromisoformat(s).timestamp() if s else None


def claude(service):
    creds = json.loads(subprocess.check_output(
        ["security", "find-generic-password", "-s", service, "-w"], text=True, timeout=10))["claudeAiOauth"]
    # ponytail: no token refresh (would rotate Claude Code's refresh token); expired = stale until that account runs claude again
    if creds["expiresAt"] / 1000 < time.time():
        raise RuntimeError("token expired - run claude on this account")
    u = get("https://api.anthropic.com/api/oauth/usage",
            {"Authorization": "Bearer " + creds["accessToken"], "anthropic-beta": "oauth-2025-04-20"})
    return {"5h": (u["five_hour"]["utilization"], iso(u["five_hour"]["resets_at"])),
            "wk": (u["seven_day"]["utilization"], iso(u["seven_day"]["resets_at"]))}, time.time(), None


def codex_windows(windows):
    """windows: [(used_pct, window_seconds, reset_epoch)] -> {"5h"|"wk": (pct, reset)}"""
    return {("5h" if secs <= 5 * 3600 else "wk"): (pct, reset) for pct, secs, reset in windows}


def tail(path, size=256 * 1024):
    with open(path, "rb") as f:
        f.seek(max(0, os.path.getsize(path) - size))
        return f.read().decode(errors="ignore").splitlines()


def codex():
    """-> (data, as_of, note); note set when falling back to the (possibly old) session log"""
    try:
        a = json.load(open(os.path.expanduser("~/.codex/auth.json")))["tokens"]
        u = get("https://chatgpt.com/backend-api/wham/usage",
                {"Authorization": "Bearer " + a["access_token"], "ChatGPT-Account-Id": a["account_id"]})
        ws = [u["rate_limit"].get(k) for k in ("primary_window", "secondary_window")]
        return codex_windows([(w["used_percent"], w["limit_window_seconds"], w["reset_at"]) for w in ws if w]), time.time(), None
    except Exception as e:  # fall back to last rate_limits written by a codex session
        note = f"api failed ({str(e)[:40]}), using codex log"
        files = sorted(glob.glob(os.path.expanduser("~/.codex/sessions/*/*/*/*.jsonl")), key=os.path.getmtime)
        for f in reversed(files[-5:]):
            for line in reversed(tail(f)):
                if '"rate_limits"' in line:
                    rl = json.loads(line)["payload"]["rate_limits"]
                    ws = [rl.get(k) for k in ("primary", "secondary")]
                    return codex_windows([(w["used_percent"], w["window_minutes"] * 60, w["resets_at"]) for w in ws if w]), os.path.getmtime(f), note
        raise


def main():
    try:
        cache = json.load(open(CACHE))
    except Exception:  # missing or corrupt: start fresh rather than dying every run
        cache = {}
    sources = [(n, lambda s=s: claude(s)) for n, s in claude_accounts()] + [("codex", codex)]
    out = []
    for name, fn in sources:
        c = cache.setdefault(name, {})
        try:
            if time.time() < c.get("backoff_until", 0):
                raise RuntimeError("rate limited, retrying " + datetime.fromtimestamp(c["backoff_until"]).strftime("%H:%M"))
            if time.time() - c.get("tried", 0) >= (0 if name == "codex" else CLAUDE_MIN_INTERVAL):
                c["tried"] = time.time()
                data, at, note = fn()
                c.update(data=data, at=at, backoff_until=0, error=note)
        except urllib.error.HTTPError as e:
            if e.code == 429:
                ra = e.headers.get("Retry-After") or ""
                c["backoff_until"] = time.time() + max(300, int(ra) if ra.isdigit() else 0)
            c["error"] = f"HTTP {e.code}"
        except Exception as e:
            c["error"] = c.get("error") if "rate limited" in str(e) else str(e)[:80]
        data, err = c.get("data"), c.get("error")
        windows = []
        for k in ("5h", "wk"):
            if data and k in data and data[k][0] is not None:
                pct, reset = data[k]
                if reset and reset < time.time():  # window rolled over since we last saw it
                    pct, reset = 0, None
                windows.append({"kind": k, "pct": pct, "reset": reset})
        out.append({"name": name, "error": err, "checked": c.get("at"), "windows": windows})
    with open(CACHE + ".tmp", "w") as f:
        json.dump(cache, f)
    os.replace(CACHE + ".tmp", CACHE)  # atomic: a crash mid-write can't corrupt the cache
    print(json.dumps(out))  # consumed by UsageBar.swift


if __name__ == "__main__":
    main()
