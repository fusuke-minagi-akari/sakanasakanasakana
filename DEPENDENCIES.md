# DEPENDENCIES.md — what each functionality needs

Every capability in this repo mapped to its dependencies, per OS. Terminal stack
installs via `./install.sh` (→ `lib/deps.sh` + `packages/*.txt`); Claude-feature
extras via `./bootstrap.sh` (→ `deps/`). See "Install summary" at the bottom.
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
| `less` | pager for diff/table/json | core | 🍎 builtin | builtin |
| **Kitty.app** | outer terminal for inline image/video (herdr `kitty_graphics`) | opt ² | cask `kitty` | 🐧 `kitty` |
| `poppler` (`pdftoppm`) | **PDF** → all pages | opt ³ | `poppler` | `poppler-utils` |
| `delta` / `bat` | **diff/patch** colorizer | opt ⁴ | `git-delta` / `bat` | `git-delta` / `bat` |
| `csvkit` (`csvlook`) | **CSV** pretty table | opt ⁵ | `csvkit` (pip) | `csvkit` (pip) |
| `jq` | **JSON** colorized | opt ⁶ | `jq` | `jq` |
| `uv` | **.pcd/.urdf/.usd\*/.ply** — runs `pcdview`/`urdfview`/`usdshow`/`plyview` (inline PEP-723 deps) | opt ⁷ | `uv` | `uv` |
| `pcl` (`pcl_viewer`) | ↑ **.pcd** interactive 3D window; `--png` needs neither | opt ⁷ | `pcl` | `pcl-tools` |

¹ `glow` may need the Charm apt repo / snap / `go install`. ² Without a
kitty-graphics terminal, `show` still runs but images/video won't render inline.
³ PDF fallback order: `pdftoppm` (all pages) → macOS `qlmanage` (1st page) →
`sips`. Install `poppler` for reliable multi-page. ⁴ diff falls back to a built-in
`awk` colorizer if neither `delta` nor `bat` is present. ⁵ CSV falls back to a
built-in `python3` aligner. ⁶ JSON falls back to `python3 -m json.tool`.
So `show` for pdf/diff/csv/json **works with zero extra installs**; the named
tools just make it nicer.

⁷ `.pcd`/`.urdf`/`.usd`+`.usda`+`.usdc`+`.usdz`/`.ply` have no fallback. `pcdview`,
`urdfview`, `usdshow`, `plyview` ship with this repo; each is a `uv run --script`
with its own PEP-723 deps block (yourdfpy+trimesh for URDF, usd-core+trimesh for
USD, open3d for PLY), fetched by `uv` on first launch — no separate install
step. The default 3D window for `.pcd` additionally needs `pcl_viewer`; `show
cloud.pcd --png` skips `pcl` entirely (matplotlib quad view, painted with
`chafa` on macOS / `kitten icat` on Linux). URDF/USD/PLY windows are always
interactive (no `--png` mode).

## 1a. `gsplatview` — real Gaussian-Splat rendering (not part of `show`)

| Dep | Role | core/opt | Linux |
|---|---|---|---|
| `uv` | runs the PEP-723 script | core | `uv` |
| NVIDIA GPU + driver | gsplat's CUDA rasterizer | core | 🐧 (this repo is Linux-only for this tool) |
| CUDA toolkit ≥12.x (`nvcc` with C++20 support) | JIT-compiles gsplat's kernels on first run (~1-2 min, cached after) | core ⁸ | apt/NVIDIA repo `cuda-toolkit-12-*` |

`plyview` (§1) only plots opaque colored dots at each Gaussian's center —
fast, no GPU needed, but nothing like superspl.at's actual render.
`gsplatview <file.ply>` instead runs gsplat's real rasterizer (alpha-blended
anisotropic ellipses, view-dependent SH color) and serves an interactive
mouse-orbit viewer over a local web server (`viser`+`nerfview`, opened in a
browser) — same technique and feel as superspl.at, run locally on a GPU
machine (confirmed working with the RTX 3090 on dx-galois). Separate command
from `show`/`plyview` since it needs a GPU, a real CUDA toolkit, and a
browser tab, not just a terminal window.

⁸ If the default `nvcc` on `PATH` predates C++20 (e.g. the system's
apt-installed CUDA 11.5), `gsplatview` auto-detects and switches to
`/usr/local/cuda-12*` if present; otherwise set `CUDA_HOME` to a newer
toolkit yourself before running.

## 1b. `notify` — long-command completion ping

| Dep | Role | core/opt | macOS | Linux |
|---|---|---|---|---|
| `herdr` | fires the notification | core | (herdr.dev) | (herdr.dev) |

`notify <cmd…>` runs the command, then `herdr notification show`s ✓/✗ + elapsed +
exit code. No-op notification if herdr absent (command still runs). Cross-OS
(`shared/`).

## 2. git branch-labels daemon (`herdr-branch-labels.sh`)

| Dep | Role | macOS | Linux |
|---|---|---|---|
| `herdr` | reads/writes workspace + pane labels | herdr.dev ³ | herdr.dev ³ |
| `git` | branch / status | `git` | `git` |
| `jq` | parse herdr JSON | `jq` | `jq` |
| `gh` | resolve PR number | `gh` | `gh` ⁴ |
| `perl` | timeout guard (no `timeout` on macOS) | 🍎 builtin | `perl` |
| `md5`/`md5sum` | cache key hash | 🍎 builtin | `coreutils` |
| service mgr | keep it running | 🍎 launchd (auto) | 🐧 systemd `--user` (SETUP.md §2) |

³ **herdr** is not in any package repo — install from https://herdr.dev
(typically `~/.local/bin/herdr`). ⁴ `gh` on Debian/Ubuntu needs the GitHub apt repo.

## 2b. Claude status poller + statusline (`claude-status/`)

| Dep | Role | core/opt | macOS | Linux |
|---|---|---|---|---|
| `curl` | fetch status.claude.com Statuspage JSON (no auth) | core | 🍎 builtin | `curl` |
| `jq` | parse indicator / components / incidents | core | `jq` | `jq` |
| service mgr | poll every 60s | core | 🍎 launchd `dev.claude.statuspoll` (auto) | 🐧 systemd `--user` `claude-status.timer` (auto) |
| `herdr` | in-terminal popup on status change | opt | herdr.dev ³ | herdr.dev ³ |
| `osascript` / `notify-send` | desktop popup on status change | opt | 🍎 builtin | `libnotify-bin` / `libnotify` |

Statusline dot is cache-only (never hits the network inline); the poller writes
the cache. `test.sh` fakes any outage state offline — see SETUP.md §2b.

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

## Install summary — two layers

**Layer 1 — terminal stack (primary, cross-OS, state-aware).** Part of
`./install.sh` (via `lib/deps.sh`); installs herdr, kitty, and the CLI tools for
`show` + the branch-labels daemon. Package lists: `packages/brew.txt` (macOS),
`packages/apt.txt` (Debian/Ubuntu), `packages/pacman.txt` (Arch).

```sh
./install.sh              # deps (herdr/kitty/CLI) + link dotfiles + service
./install.sh --dry-run    # preview
./install.sh --no-deps    # link only, skip dependency install
```

**Layer 2 — Claude-feature extras (optional, additive).** `./bootstrap.sh` adds
what layer 1 doesn't cover: node, python3, and (optionally) the npm
diagram/PDF tools. Never touches the layer-1 build.

```sh
./bootstrap.sh            # node, python3
./bootstrap.sh --npm      # also pin npm globals (deps/npm-global.txt); else npx auto-fetches
```

**Not auto-installed** (manual — see notes above): `caveman` plugin, MCP servers,
`melchior-headless` wrapper, BetterDisplay. (`herdr`/`kitty` ARE handled by layer 1.)
