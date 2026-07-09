# CLAUDE.md — sakanasakanasakana (dotfiles)

Private dotfiles repo for herdr + Claude Code. Read this first when working here.

## What this repo is

Versioned herdr + Claude Code config, symlinked into `$HOME` by `install.sh`.
Structure is OS-split, each dir mirroring `$HOME`:

- `shared/` — linked on every OS
- `macos/`  — Darwin only (launchd)
- `linux/`  — Linux only (systemd; may be empty until first Linux setup)

Active set on any machine = `shared/` + `<uname>/`.

## Setting up / adapting to a new machine

**When the user asks to set up, install, adapt, or bootstrap this on a machine:
follow `SETUP.md` step by step.** Order: detect OS (`uname -s`) → `./install.sh`
(installs the terminal stack — herdr/kitty/CLI — via `lib/deps.sh`, then symlinks
+ service) → `./bootstrap.sh` (optional Claude-feature extras: node/python/
matplotlib) → OS-specific service + `herdr integration install claude` → seed
per-user configs → verify. `DEPENDENCIES.md` is the functionality→deps authority.
Do NOT edit the layer-1 build (`lib/deps.sh`, `packages/*.txt`, `install.sh`) on a
machine you can't test it on — it's the shared cross-OS installer. `caveman`
plugin, MCP servers, and the melchior wrapper are manual (DEPENDENCIES.md §6).

## How it works (quick facts)

- `install.sh`: symlinks tracked files (existing real files → `~/backup` first,
  never clobbered); renders `*.plist.tmpl` with `$HOME` baked in; seeds
  `*.example.*` to their real name only if missing. Flags: `--dry-run`, `--no-load`.
- Editing a tracked file changes the live config immediately (it's a symlink).
  After edits: `herdr server reload-config` (config.toml) or restart the daemon
  (`launchctl kickstart -k gui/$UID/dev.herdr.branchlabels`, or
  `systemctl --user restart herdr-branch-labels`).
- `~/.claude/hooks/herdr-agent-state.sh` is herdr-managed — NOT tracked; recreate
  with `herdr integration install claude`.

## Guardrails (NDA — non-negotiable)

- **Never commit secrets/PII** to tracked files: client names, AWS account ids,
  amounts, real Slack/Notion ids, colleague names, LAN ips, internal Notion ids.
  They live only in gitignored real configs (`standup_config.json`, `devices.txt`).
- Keep tracked files generic; use obviously-fake examples.
- Scan the diff for those markers before every `git add`/commit here.
- Full rules: `shared/.claude/CLAUDE.md` (機密情報フィルター).
