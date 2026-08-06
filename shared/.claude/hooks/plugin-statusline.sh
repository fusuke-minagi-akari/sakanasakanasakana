#!/usr/bin/env bash
# Statusline badge for whichever of ponytail / caveman is currently enabled.
#
# Resolves the plugin's install path from installed_plugins.json at runtime instead of
# hardcoding a versioned cache dir. The previous caveman statusline pinned
# .../caveman/25d22f864ad6/... and silently kept pointing at the old build after an
# upgrade; this survives version bumps and enable/disable swaps.
set -uo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Emits "<install_path>" for the first enabled plugin whose badge script exists.
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

# settings.local.json is the machine-local override (gitignored) — settings.json
# is a symlink into the shared dotfiles repo, so the per-device plugin choice
# lives in local and must win here too.
enabled = load(os.path.join(claude_dir, "settings.json")).get("enabledPlugins", {})
enabled.update(load(os.path.join(claude_dir, "settings.local.json")).get("enabledPlugins", {}))
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
        print(candidate)
        break
PY
}

SCRIPT="$(resolve)"
[ -n "$SCRIPT" ] || exit 0     # nothing enabled -> empty statusline, not an error
exec bash "$SCRIPT" "$@"
