#!/usr/bin/env bash
# UserPromptSubmit — record THIS session's ponytail mode.
#
# The plugin keeps mode in ONE machine-global $CLAUDE_DIR/.ponytail-active
# (ponytail-runtime.js builds statePath with no session key), so with several
# Claude panes open in herdr: `stop ponytail` in one pane deleted the flag and
# every other pane's badge vanished, and every new session start rewrote the
# flag with the default, silently reverting a pane that was on ultra/lite.
#
# Mode is per-session in *behaviour* already (the ruleset is injected once at
# SessionStart), so only the badge was lying. plugin-statusline.sh reads the
# per-session file this hook writes instead of the shared flag.
#
# Prints nothing: UserPromptSubmit stdout gets injected into the prompt.
set -uo pipefail

# Hook JSON goes in via the environment, not stdin: the script itself arrives on
# stdin through the heredoc, so sys.stdin is already spoken for.
PONY_INPUT=$(cat) python3 - "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" <<'PY'
import json, os, re, sys

try:
    data = json.loads(os.environ.get("PONY_INPUT") or "{}")
except Exception:
    sys.exit(0)

sid = data.get("session_id") or ""
prompt = " ".join((data.get("prompt") or "").lower().split()).rstrip(".!?")
if not sid or not prompt:
    sys.exit(0)

# Mirrors the plugin's own parsing: ponytail-mode-tracker.js for the slash
# commands, isDeactivationCommand() in ponytail-config.js for the two phrases.
# `/ponytail` bare is report-only and `/ponytail default X` only writes the
# config default — neither changes the current session, so neither writes here.
mode = None
if re.match(r'^[/@$](?:ponytail:)?ponytail-review(?:\s|$)', prompt):
    mode = "review"
else:
    m = re.match(r'^[/@$](?:ponytail:)?ponytail(?:\s+(off|lite|full|ultra))?(?:\s|$)', prompt)
    if m and m.group(1):
        mode = m.group(1)
    elif prompt in ("stop ponytail", "normal mode"):
        mode = "off"
if not mode:
    sys.exit(0)

# ponytail: no pruning — one ~5-byte file per session that actually switched
# mode. Add a find -mtime +30 -delete sweep here if the dir ever gets noisy.
d = os.path.join(sys.argv[1], "ponytail-modes")
os.makedirs(d, exist_ok=True)
with open(os.path.join(d, re.sub(r'[^A-Za-z0-9._-]', '', sid)), "w") as fh:
    fh.write(mode)
PY

exit 0   # never block a prompt over a badge
