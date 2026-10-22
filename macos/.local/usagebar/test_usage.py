# Self-check for usage.py (network/keychain faked): python3 -I test_usage.py
import importlib.util, io, json, os, sys, tempfile, time, urllib.error, contextlib
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("u", os.path.join(os.path.dirname(os.path.realpath(__file__)), "usage.py"))
u = importlib.util.module_from_spec(spec); spec.loader.exec_module(u)
u.CACHE = tempfile.mktemp()
now = time.time()

def run():
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf): u.main()
    return {s["name"]: s for s in json.loads(buf.getvalue())}

ok = lambda: ({"5h": (10.0, now + 3600), "wk": (50.0, now + 86400)}, time.time(), None)
u.claude_accounts = lambda: [("main", "svc-main"), ("c", "svc-c")]
u.claude = lambda s: ok(); u.codex = ok

# corrupt cache -> recovers
open(u.CACHE, "w").write("{bad")
assert run()["main"]["windows"][0]["pct"] == 10.0

# 429 with HTTP-date Retry-After -> no crash, backoff >= 300s, cached data kept
def r429(s): raise urllib.error.HTTPError("x", 429, "", {"Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"}, None)
u.claude = r429; u.CLAUDE_MIN_INTERVAL = 0
out = run(); c = json.load(open(u.CACHE))
assert out["main"]["error"] == "HTTP 429" and out["main"]["windows"][1]["pct"] == 50.0
assert c["main"]["backoff_until"] - time.time() > 290

# 180s interval counts failed attempts too
calls = []
u.CLAUDE_MIN_INTERVAL = 180; u.claude = lambda s: calls.append(s) or ok()
c = json.load(open(u.CACHE)); c["c"]["tried"] = time.time(); json.dump(c, open(u.CACHE, "w"))
run(); assert "svc-c" not in calls

# rolled-over window -> 0%, null pct -> window skipped
u.CLAUDE_MIN_INTERVAL = 0
u.codex = lambda: ({"5h": (None, None), "wk": (90.0, now - 10)}, time.time(), None)
w = run()["codex"]["windows"]
assert w == [{"kind": "wk", "pct": 0, "reset": None}], w

# fromisoformat variants the API could send (python 3.9 safe)
assert u.iso("2026-10-24T08:59:59.5+00:00") == u.iso("2026-10-24T08:59:59Z") == u.iso("2026-10-24T08:59:59+00:00")

# codex log fallback (fake $HOME): tail read, as_of = file mtime, note set
home = tempfile.mkdtemp(); os.environ["HOME"] = home
os.makedirs(f"{home}/.codex/sessions/2026/01/01")
json.dump({"tokens": {"access_token": "x", "account_id": "y"}}, open(f"{home}/.codex/auth.json", "w"))
log = f"{home}/.codex/sessions/2026/01/01/s.jsonl"
rl = {"primary": {"used_percent": 42.0, "window_minutes": 10080, "resets_at": now + 86400}, "secondary": None}
open(log, "w").write("x" * 300_000 + "\n" + json.dumps({"payload": {"rate_limits": rl}}) + "\n")
os.utime(log, (now - 7200, now - 7200))
spec2 = importlib.util.spec_from_file_location("u2", spec.origin)
u2 = importlib.util.module_from_spec(spec2); spec2.loader.exec_module(u2)
def boom(*a): raise urllib.error.HTTPError("x", 401, "", {}, None)
u2.get = boom
data, at, note = u2.codex()
assert data == {"wk": (42.0, now + 86400)} and abs(at - (now - 7200)) < 1 and "codex log" in note, (data, at, note)
print("all checks passed")
