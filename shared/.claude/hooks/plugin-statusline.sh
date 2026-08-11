#!/usr/bin/env bash
# Statusline badge for whichever of ponytail / caveman is currently enabled.
#
# Resolves the plugin's install path from installed_plugins.json at runtime instead of
# hardcoding a versioned cache dir. The previous caveman statusline pinned
# .../caveman/25d22f864ad6/... and silently kept pointing at the old build after an
# upgrade; this survives version bumps and enable/disable swaps.
set -uo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
INPUT=$(cat)     # Claude Code feeds session JSON on stdin (session_id, model, ...)

# Emits "<plugin key>\t<install_path>" for the first enabled plugin whose badge script exists.
resolve() {
  python3 - "$CLAUDE_DIR" <<'PY'
import json, os, sys

claude_dir = sys.argv[1]

def load(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except Exception:
        return {}

# settings.json only. Claude Code does NOT honor enabledPlugins from a user-level
# settings.local.json (verified via `claude plugin list`), so reading local here
# would make the badge claim a plugin that never actually loaded.
enabled = load(os.path.join(claude_dir, "settings.json")).get("enabledPlugins", {})
installed = load(os.path.join(claude_dir, "plugins", "installed_plugins.json")).get("plugins", {})

for key, script in (("ponytail@ponytail", "hooks/ponytail-statusline.sh"),
                    ("caveman@caveman", "src/hooks/caveman-statusline.sh")):
    if not enabled.get(key):
        continue
    entries = installed.get(key) or []
    if not entries:
        continue
    candidate = os.path.join(entries[0].get("installPath", ""), script)
    if os.path.isfile(candidate):
        print(key + "\t" + candidate)
        break
PY
}

IFS=$'\t' read -r KEY SCRIPT < <(resolve)
KEY="${KEY:-}"; SCRIPT="${SCRIPT:-}"
[ -n "$KEY" ] || exit 0     # nothing enabled -> empty statusline, not an error

# ponytail: rendered here rather than by the plugin's own statusline script,
# because that script reads the machine-global $CLAUDE_DIR/.ponytail-active —
# one file shared by every session on the box. With a dozen herdr panes open,
# `stop ponytail` in one pane deleted it and every badge vanished, and each new
# session start rewrote it with the default, reverting panes set to ultra/lite.
# ponytail-session-mode.sh records the mode per session id; no per-session file
# means the session is still on the configured default. Same colors as the
# plugin (108 green, 173 amber for ultra).
if [ "$KEY" = "ponytail@ponytail" ]; then
  mode=$(PONY_INPUT="$INPUT" python3 - "$CLAUDE_DIR" <<'PY'
import json, os, sys

try:
    sid = json.loads(os.environ.get("PONY_INPUT") or "{}").get("session_id") or ""
except Exception:
    sid = ""

mode = ""
path = os.path.join(sys.argv[1], "ponytail-modes", sid)
if sid and not os.path.islink(path) and os.path.isfile(path):
    with open(path) as fh:
        mode = fh.read(16).strip().lower()

# Same precedence as the plugin's getDefaultMode(): env, then config, then full.
if not mode:
    mode = (os.environ.get("PONYTAIL_DEFAULT_MODE") or "").lower()
if not mode:
    cfg = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    try:
        with open(os.path.join(cfg, "ponytail", "config.json")) as fh:
            mode = str(json.load(fh).get("defaultMode") or "").lower()
    except Exception:
        pass
print(mode or "full")
PY
)
  # Allowlisted values only — never printf an unvetted file's bytes into the
  # terminal (that flag file is the one thing here a local process can write).
  case "$mode" in
    full)         printf '\033[38;5;108m[PONYTAIL]\033[0m' ;;
    lite|review)  printf '\033[38;5;108m[PONYTAIL:%s]\033[0m' "$(printf '%s' "$mode" | tr 'a-z' 'A-Z')" ;;
    ultra)        printf '\033[38;5;173m[PONYTAIL:ULTRA]\033[0m' ;;
    *)            exit 0 ;;   # off, or anything unrecognized -> no badge
  esac
  exit 0
fi

printf '%s' "$INPUT" | bash "$SCRIPT" "$@"
