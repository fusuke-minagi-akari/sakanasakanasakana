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

## 1. Install dependencies

Check each with `command -v <bin>`; install only what's missing.

| Purpose | Binary | macOS (brew) | Linux (apt) |
|---|---|---|---|
| terminal multiplexer | `herdr` | see note ¹ | see note ¹ |
| git | `git` | `git` | `git` |
| JSON parse (daemon) | `jq` | `jq` | `jq` |
| GitHub CLI (PR labels) | `gh` | `gh` | `gh` ² |
| timeout guard (daemon) | `perl` | preinstalled | `perl` |
| md5 (daemon) | `md5`/`md5sum` | preinstalled | `coreutils` |
| image viewer (`show`) | `chafa` | `chafa` | `chafa` |
| video/audio (`show`) | `mpv` | `mpv` | `mpv` |
| markdown (`show`) | `glow` | `glow` | `glow` ³ |

¹ **herdr** is not in a public package repo — install from https://herdr.dev
   (typically `~/.local/bin/herdr`). Confirm with the user before downloading.
² `gh` on Debian/Ubuntu needs the GitHub apt repo; or use `brew`/`snap`.
³ `glow` may need the Charm apt repo, or `brew`, or `go install`. `show` degrades
   gracefully (only markdown routing is affected) if `glow` is absent.

macOS one-liner (only for missing bins):
```sh
brew install jq gh chafa mpv glow
```
Linux/apt one-liner (only for missing bins):
```sh
sudo apt-get update && sudo apt-get install -y jq perl coreutils chafa mpv
# gh + glow: add their apt repos, or install via brew/snap/go — see notes.
```

---

## 2. Link the dotfiles

```sh
cd <repo> && ./install.sh
```

`install.sh` detects `uname`, links `shared/` + `<os>/` into `$HOME` (backing up
existing files to `~/backup`), seeds `*.example` configs if missing, and — on
macOS — renders + loads the launchd job. Use `--dry-run` first if unsure.

---

## 3. Background daemon (branch labels)

The git-branch visualizer (`~/.local/bin/herdr-branch-labels.sh`) must run as a
service. The script itself is cross-OS (md5 shim built in). The *service manager*
differs:

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

## 4. herdr-managed Claude hook

`~/.claude/hooks/herdr-agent-state.sh` is generated/overwritten by herdr and is
**intentionally not tracked**. Recreate it:
```sh
herdr integration install claude
```
This also writes the SessionStart entry into `~/.claude/settings.json` (which is
now a symlink to the repo — that's fine).

---

## 5. Fill per-user configs (seeded from `*.example`)

These hold secrets/PII, so only `.example` templates are committed. `install.sh`
copied them to their real names if missing. Fill in real values (kept local,
gitignored — never commit them):

- `~/.claude/scripts/standup_config.json` — your Slack/Notion ids, channels, mentor.
- `~/.claude/scripts/devices.txt` — your ssh hosts.
- `~/.claude/skills/kalmia/SKILL.md` — replace `<KALMIA_NOTION_COLLECTION_ID>`.

---

## 6. Verify

```sh
# symlinks resolve into the repo
for f in ~/.local/bin/show ~/.config/herdr/config.toml ~/.claude/settings.json; do
  readlink "$f"; done
# show works
show --help
# daemon alive
#   macOS: launchctl print gui/$UID/dev.herdr.branchlabels | grep state
#   Linux: systemctl --user status herdr-branch-labels.service
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
