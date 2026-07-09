# DEPENDENCIES.md — what each functionality needs

Every capability in this repo mapped to its dependencies, per OS. Install with
`./bootstrap.sh` (reads the manifests in `deps/`), or by hand from the tables.
Legend: **core** = needed for the feature at all · **opt** = graceful degrade /
optional · 🍎 macOS-builtin · 🐧 Linux-only.

---

## Runtime baseline (needed by almost everything)

| Dep | Why | macOS | Linux (apt) |
|---|---|---|---|
| `bash` | scripts, hooks | 🍎 builtin | builtin |
| `git` | daemon, workflows | `git` | `git` |
| `python3` | hooks, skills | 🍎 builtin | `python3` `python3-pip` |
| `jq` | JSON in daemon/skills | `jq` | `jq` |
| `coreutils` | `md5sum` on Linux (macOS uses builtin `md5`) | 🍎 builtin | `coreutils` |

---

## 1. `show` — in-terminal file viewer

| Dep | Role | core/opt | macOS | Linux |
|---|---|---|---|---|
| `chafa` | image → kitty graphics | core (images) | `chafa` | `chafa` |
| `mpv` | video / audio | core (av) | `mpv` | `mpv` |
| `glow` | markdown render | opt (md only) | `glow` | `glow` ¹ |
| `file` | mime sniff for unknown ext | core | 🍎 builtin | `file` |
| `less` | text fallback (`$PAGER`) | core | 🍎 builtin | builtin |
| **Kitty.app** | outer terminal for inline image/video (herdr `kitty_graphics`) | opt ² | cask `kitty` | 🐧 `kitty` |

¹ `glow` may need the Charm apt repo / snap / `go install`. ² Without a
kitty-graphics terminal, `show` still runs but images/video won't render inline.

## 2. git branch-labels daemon (`herdr-branch-labels.sh`)

| Dep | Role | macOS | Linux |
|---|---|---|---|
| `herdr` | reads/writes workspace + pane labels | herdr.dev ³ | herdr.dev ³ |
| `git` | branch / status | `git` | `git` |
| `jq` | parse herdr JSON | `jq` | `jq` |
| `gh` | resolve PR number | `gh` | `gh` ⁴ |
| `perl` | timeout guard (no `timeout` on macOS) | 🍎 builtin | `perl` |
| `md5`/`md5sum` | cache key hash | 🍎 builtin | `coreutils` |
| service mgr | keep it running | 🍎 launchd (auto) | 🐧 systemd `--user` (SETUP.md §3) |

³ **herdr** is not in any package repo — install from https://herdr.dev
(typically `~/.local/bin/herdr`). ⁴ `gh` on Debian/Ubuntu needs the GitHub apt repo.

## 3. herdr itself + config / done-hook

| Dep | Role | Install |
|---|---|---|
| `herdr` | multiplexer | herdr.dev |
| Kitty.app | recommended outer terminal (kitty_graphics, sounds) | cask/pkg `kitty` |
| custom sound mp3s | opt — done/request cues | drop into `~/.config/herdr/sounds/` (none tracked) |

## 4. Claude Code — diagrams, PDFs, tables

| Feature | Dep | core/opt | macOS | Linux |
|---|---|---|---|---|
| `/diagram`, kalmia PNG | `node` + `npx` | core | `node` | `nodejs` `npm` |
| ↑ renderer | `@mermaid-js/mermaid-cli` (via `npx --yes`, auto-fetch) | core | (npx) | (npx) |
| kalmia PNG dims | `sips` 🍎 / `imagemagick` 🐧 | opt | 🍎 builtin | `imagemagick` |
| `report` skill (md→PDF) | `md-to-pdf` npm (bundles Chromium) | core | (npx/npm) | (npx/npm) ⁵ |
| `summarize-to-slack`, `render_table.py` | `python3` + `matplotlib` | core | `pip: matplotlib` | `python3-matplotlib` |
| ↑ CJK text in tables | CJK font | core (JP) | 🍎 Hiragino builtin | `fonts-noto-cjk` |

⁵ Chromium that `md-to-pdf`/puppeteer downloads needs libs on Linux
(`libnss3 libatk1.0-0 libgbm1 …`) — install if PDF gen fails.

## 5. Claude Code — data/workflow skills

| Feature | Dep | Notes |
|---|---|---|
| `sessions`, `token-usage`, `session-cost`, `budget`, `usage-improv` | `python3` only | stdlib (json/urllib/socket) — no 3rd-party |
| `nippo`, `standup`, `research` | `gh`, `jq`, `python3` | + **MCP servers** (below) |
| `sync-skills` (`sync_skills.sh`) | `rsync` (or `scp` fallback), `ssh` | targets in `~/.claude/scripts/devices.txt` |
| `melchior_headless` | `uv`, `python3`+`PIL` (target venv), `task` (go-task) | + external wrapper ⁶ ; macOS BetterDisplay / 🐧 `xvfb` |

⁶ `melchior_headless` needs `~/.local/share/melchior-headless/` (wrapper +
sitecustomize) — **not tracked in this repo**; a separate artifact. See that
skill's SKILL.md.

## 6. Claude Code integrations (not system packages)

These are Claude Code plugins / MCP servers, installed via Claude Code / claude.ai
auth — not `brew`/`apt`:

| Used by | Integration |
|---|---|
| statusline / caveman mode | `caveman` plugin (Claude Code marketplace) |
| `nippo`, `standup`, `research`, `kalmia` | MCP: Notion, Slack, Google (Calendar/Drive/Gmail) |
| herdr agent state/session hooks | `herdr integration install claude` (herdr-managed) |

---

## Install summary

```sh
./bootstrap.sh            # auto: uname → brew bundle | apt + pip + (npm)
./bootstrap.sh --dry-run  # print what it would install
./bootstrap.sh --full     # also pre-install npm globals + optional (melchior/kitty)
```

Manifests it reads: `deps/Brewfile` (macOS), `deps/packages-apt.txt` (Linux),
`deps/requirements.txt` (pip), `deps/npm-global.txt` (node globals).
**Not auto-installed** (manual, see notes above): `herdr`, `caveman` plugin, MCP
servers, `melchior-headless` wrapper, BetterDisplay.
