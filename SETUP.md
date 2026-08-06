# SETUP.md — OS adaptation playbook (for Claude Code)

This is an executable runbook. When asked to "set up", "adapt", or "install" this
repo on a machine, **follow these steps in order** and report a summary. Do not
guess package names — use the tables here. Stop and ask the user only where a step
says to.

Repo lives at the clone location (assume `~/sakanasakanasakana` unless told otherwise).
Everything is idempotent: safe to re-run.

---

## 0. Detect the environment

```sh
uname -s          # Darwin | Linux
```

- `Darwin` → **macOS track**: Homebrew + launchd.
- `Linux`  → **Linux track**: apt (or the host's package manager) + systemd `--user`.

Detect the package manager on Linux: try `apt-get`, else `dnf`, else `pacman`.
Translate package names accordingly; the apt names are the reference.

---

## 1. Install dependencies + link (`./install.sh`)

`install.sh` does BOTH the terminal-stack deps and the symlinking in one run:

```sh
cd <repo> && ./install.sh   # deps (herdr/kitty/CLI) + link + seed + launchd
./install.sh --dry-run      # preview, change nothing
./install.sh --no-deps      # link only, skip dependency install
```

**Layer 1 — terminal stack** (via `lib/deps.sh`, state-aware): detects the
package manager (brew / apt / pacman via `/etc/os-release`), installs from
`packages/{brew,apt,pacman}.txt` (glow chafa mpv jq gh git file), then ensures
**herdr** (herdr.dev installer, brew fallback) and **kitty** (per-OS installer).
Handles bare/half-built/corrupt/healthy per component. Do NOT edit `lib/deps.sh`
or `packages/apt.txt`/`packages/pacman.txt` on a machine you can't test them on.

Then `install.sh` links `shared/` + `<os>/` into `$HOME` (existing files → `~/backup`),
seeds `*.example` configs, and on macOS renders + loads the launchd job.

**Layer 2 — Claude-feature extras** (optional, additive — never touches layer 1):

```sh
./bootstrap.sh          # node, python3 (for /diagram, report)
./bootstrap.sh --npm    # also pin npm globals; else npx --yes auto-fetches them
```

**`DEPENDENCIES.md`** is the full functionality→dependency matrix (per-OS package
names, core vs optional). Consult it if a feature fails or to install selectively.

Still manual (confirm with user): **`caveman` plugin** (Claude Code marketplace),
**MCP servers** (Notion/Slack/Google via claude.ai auth — nippo/standup/research/kalmia),
**`melchior-headless` wrapper** (`~/.local/share/melchior-headless/`) + BetterDisplay.
On Debian/Ubuntu `gh`/`glow` may need their own apt repos (see `packages/apt.txt`).

---

## 2. Background daemon (branch labels)

The git-branch visualizer (`~/.local/bin/herdr-branch-labels.sh`) must run as a
service. Note: `hashkey()` uses macOS `md5`; on a distro without `md5` it degrades
to a shared cache key (labels still render) — swap to `md5sum` there if desired.
The *service manager* differs:

- **macOS** — `install.sh` already handled it (launchd job
  `dev.herdr.branchlabels`, rendered from `macos/…/*.plist.tmpl`). Verify:
  ```sh
  launchctl print gui/$UID/dev.herdr.branchlabels | grep state
  ```

- **Linux** — no unit ships yet. Create a systemd **user** service (write it,
  then enable). If `linux/.config/systemd/user/herdr-branch-labels.service`
  already exists in the repo, link/copy that instead of regenerating.
  ```sh
  mkdir -p ~/.config/systemd/user
  cat > ~/.config/systemd/user/herdr-branch-labels.service <<EOF
  [Unit]
  Description=herdr git branch labels daemon
  After=default.target

  [Service]
  ExecStart=%h/.local/bin/herdr-branch-labels.sh
  Restart=always
  Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin
  StandardOutput=append:%h/.config/herdr/branch-labels.log
  StandardError=append:%h/.config/herdr/branch-labels.log

  [Install]
  WantedBy=default.target
  EOF
  systemctl --user daemon-reload
  systemctl --user enable --now herdr-branch-labels.service
  loginctl enable-linger "$USER"   # keep it running after logout
  ```
  After confirming it works, offer to commit the unit into
  `linux/.config/systemd/user/` so future clones are one-step.

---

## 2b. Background service (Claude status poller)

`~/.claude/scripts/claude-status/poll.sh` polls <https://status.claude.com>
(Statuspage, no auth) every 60s, caches a colored dot for the Claude Code
statusline, and fires a herdr + desktop notification when the status *changes*.
Both service units ship in the repo, so `install.sh` wires them automatically:

- **macOS** — launchd job `dev.claude.statuspoll`, rendered from
  `macos/Library/LaunchAgents/dev.claude.statuspoll.plist.tmpl`.
  ```sh
  launchctl print gui/$UID/dev.claude.statuspoll | grep -E 'state|runs'
  ```
- **Linux** — systemd user timer `claude-status.timer` (unit + timer live in
  `linux/.config/systemd/user/`, symlinked by `install.sh`, then enabled).
  ```sh
  systemctl --user status claude-status.timer
  loginctl enable-linger "$USER"   # keep polling after logout
  notify-send --version            # desktop popups need libnotify (herdr popups don't)
  ```

The statusline itself is `statusline.sh` (caveman badge + status dot), wired via
`statusLine.command` in `~/.claude/settings.json`. Never point that at the
caveman plugin file directly — the plugin cache is overwritten on update.

Test without waiting for a real outage — fixtures are built locally, no network:
```sh
~/.claude/scripts/claude-status/test.sh render      # every scenario -> segment
~/.claude/scripts/claude-status/test.sh notify      # fire real notifications
~/.claude/scripts/claude-status/test.sh pin major   # freeze the LIVE statusline
~/.claude/scripts/claude-status/test.sh state       # pin / cache age / service
~/.claude/scripts/claude-status/test.sh unpin
```

---

## 3. herdr-managed Claude hook

`~/.claude/hooks/herdr-agent-state.sh` is generated/overwritten by herdr and is
**intentionally not tracked**. Recreate it:
```sh
herdr integration install claude
```
This also writes the SessionStart entry into `~/.claude/settings.json` (which is
now a symlink to the repo — that's fine).

---

## 4. Fill per-user configs (seeded from `*.example`)

These hold secrets/PII, so only `.example` templates are committed. `install.sh`
copied them to their real names if missing. Fill in real values (kept local,
gitignored — never commit them):

- `~/.claude/scripts/standup_config.json` — your Slack/Notion ids, channels, mentor.
- `~/.claude/scripts/devices.txt` — your ssh hosts.
- `~/.claude/skills/kalmia/SKILL.md` — replace `<KALMIA_NOTION_COLLECTION_ID>`.

---

## 5. Verify

```sh
# symlinks resolve into the repo
for f in ~/.local/bin/show ~/.config/herdr/config.toml ~/.claude/settings.json; do
  readlink "$f"; done
# show works
show --help
# daemon alive
#   macOS: launchctl print gui/$UID/dev.herdr.branchlabels | grep state
#   Linux: systemctl --user status herdr-branch-labels.service
# claude status poller + statusline
~/.claude/scripts/claude-status/test.sh state
```

Report: OS detected, deps installed vs already-present, daemon state, and any
per-user config still needing values.

---

## Guardrails (NDA — always)

- **Never commit real secrets/PII.** Client names, AWS account ids, amounts,
  real Slack/Notion ids, colleague names, LAN ips, internal Notion ids → they
  belong only in the gitignored real configs, never in tracked files.
- When editing a tracked file, keep values generic/placeholder. If you must add a
  concrete example, use an obviously-fake one.
- Before any `git add`/commit here, scan the diff for the markers above.
- See `shared/.claude/CLAUDE.md` for the full 機密情報フィルター rules.
