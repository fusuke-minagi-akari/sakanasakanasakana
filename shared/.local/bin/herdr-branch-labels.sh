#!/usr/bin/env bash
# herdr-branch-labels — annotate herdr with git info in two places:
#
#   1. Workspace SIDEBAR label:  <base> · <branch> · <N>Δ [· PR#<num>]
#      <base> = the user-visible workspace name (recovered as text before the
#      first " · ", so it survives repeated passes). The dir shown follows the
#      focused pane when it is in a git worktree, else the first git-rooted pane.
#
#   2. Per-pane BORDER title:    <repo> · <branch> · <N>Δ [· PR#<num>]
#      Set for every pane whose cwd is a git worktree, so each split/subterminal
#      shows its own repo. Cleared automatically when a pane leaves a repo.
#      Panes the daemon never titled are left untouched (manual names are safe).
#
# <branch> is the checked-out branch (or @<sha> when detached), N the count of
# `git status --porcelain` lines, PR#<num> the open PR for the branch (gh, cached).
#
# Usage:
#   herdr-branch-labels.sh          # run forever (poll loop) — used by launchd
#   herdr-branch-labels.sh once     # single pass, then exit (for testing)

set -u

SEP=' · '
INTERVAL="${HERDR_LABEL_INTERVAL:-4}"     # seconds between passes
PR_TTL="${HERDR_LABEL_PR_TTL:-300}"       # PR cache lifetime, seconds
GH_TIMEOUT="${HERDR_LABEL_GH_TIMEOUT:-8}" # gh call hard timeout, seconds
CACHE_DIR="${HOME}/.config/herdr/branch-label-cache"
MANAGED_DIR="${CACHE_DIR}/managed-panes"  # one flag file per pane we titled
mkdir -p "$CACHE_DIR" "$MANAGED_DIR"

now() { date +%s; }
hashkey() { md5 -qs "$1"; }
pane_key() { printf '%s' "${1//[^A-Za-z0-9]/_}"; }

# Resolve the branch's PR number in $dir, write "<num-or-empty>\t<epoch>" to the
# cache file atomically (temp + mv). Backgrounded + lock-guarded so a slow gh
# never blocks the loop.
refresh_pr_bg() {
  local dir="$1" branch="$2" cachef="$3" lockd="$4"
  mkdir "$lockd" 2>/dev/null || return 0   # a refresh is already in flight
  (
    local num tmp
    num=$(cd "$dir" 2>/dev/null && \
          perl -e 'alarm shift @ARGV; exec @ARGV' "$GH_TIMEOUT" \
              gh pr view "$branch" --json number --jq '.number' 2>/dev/null)
    [[ "$num" =~ ^[0-9]+$ ]] || num=''       # only accept a real PR number
    tmp="${cachef}.$$"
    printf '%s\t%s\n' "$num" "$(now)" > "$tmp" && mv -f "$tmp" "$cachef"
    rmdir "$lockd" 2>/dev/null
  ) &
}

# Echo the cached PR number (may be empty); trigger a background refresh when the
# cache is missing or stale. Parses defensively: the line MUST contain a tab and
# a numeric first field, else it is treated as no-PR (guards against a truncated
# read leaking the epoch from the second field).
pr_for() {
  local dir="$1" branch="$2"
  local key cachef lockd line num ts
  key=$(hashkey "${dir}|${branch}")
  cachef="${CACHE_DIR}/${key}.pr"
  lockd="${CACHE_DIR}/${key}.lock"
  num=''; ts=0
  if [ -f "$cachef" ]; then
    line=$(head -n1 "$cachef" 2>/dev/null)
    case "$line" in
      *$'\t'*)
        num="${line%%$'\t'*}"
        ts="${line##*$'\t'}"
        [[ "$num" =~ ^[0-9]+$ ]] || num=''
        [[ "$ts"  =~ ^[0-9]+$ ]] || ts=0
        ;;
    esac
  fi
  if [ ! -f "$cachef" ] || [ $(( $(now) - ts )) -gt "$PR_TTL" ]; then
    refresh_pr_bg "$dir" "$branch" "$cachef" "$lockd"
  fi
  printf '%s' "$num"
}

# compute_label <base> <cwd> -> "<base> · <branch> · <N>Δ [· PR#<num>]"
# When <cwd> is not a git worktree, echoes <base> unchanged.
compute_label() {
  local base="$1" cwd="$2"
  local top branch changes pr out
  [ -n "$cwd" ] || { printf '%s' "$base"; return; }
  top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || { printf '%s' "$base"; return; }
  [ -n "$top" ] || { printf '%s' "$base"; return; }

  branch=$(git -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null)
  [ -z "$branch" ] && branch="@$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)"
  changes=$(git -C "$cwd" status --porcelain 2>/dev/null | grep -c .)
  pr=$(pr_for "$top" "$branch")

  out="${base}${SEP}${branch}${SEP}${changes}Δ"
  [ -n "$pr" ] && out="${out}${SEP}PR#${pr}"
  printf '%s' "$out"
}

# Git toplevel dir for a cwd, or empty. Echoes "<top>".
git_top() { git -C "$1" rev-parse --show-toplevel 2>/dev/null; }

# --- Sidebar: pick the pane whose dir drives a workspace label -------------
#   1. focused pane, if in a git worktree (label follows where you cd)
#   2. else the first git-rooted pane
#   3. else the root pane's dir (base only)
choose_cwd() {
  local id="$1" f c chosen='' first=''
  while IFS=$'\t' read -r f c; do
    [ -n "$c" ] || continue
    [ -z "$first" ] && first="$c"
    if git -C "$c" rev-parse --show-toplevel >/dev/null 2>&1; then
      if [ "$f" = "true" ]; then printf '%s' "$c"; return; fi
      [ -z "$chosen" ] && chosen="$c"
    fi
  done < <(herdr pane list --workspace "$id" 2>/dev/null \
           | jq -r '.result.panes[] | [(.focused|tostring),(.foreground_cwd // .cwd)] | @tsv' 2>/dev/null)
  printf '%s' "${chosen:-$first}"
}

update_sidebar() {
  local list id label base cwd want
  list=$(herdr workspace list 2>/dev/null) || return 0
  while IFS=$'\t' read -r id label; do
    [ -n "$id" ] || continue
    base="${label%%${SEP}*}"
    cwd=$(choose_cwd "$id")
    want=$(compute_label "$base" "$cwd")
    [ "$want" != "$label" ] && herdr workspace rename "$id" "$want" >/dev/null 2>&1
  done < <(printf '%s' "$list" | jq -r '.result.workspaces[] | "\(.workspace_id)\t\(.label)"' 2>/dev/null)
}

# --- Pane titles: one per git-rooted pane; clear when a pane leaves git -----
# Only panes recorded under $MANAGED_DIR are ever cleared, so manually named
# panes we never touched stay intact. A per-pane cache of the last title we set
# avoids re-renaming (and redraw flicker) when nothing changed.
update_panes() {
  local seen_git="" pid cwd top base title key titlef last flag
  while IFS=$'\t' read -r pid cwd; do
    [ -n "$pid" ] || continue
    top=$(git_top "$cwd")
    key=$(pane_key "$pid")
    titlef="${CACHE_DIR}/pane-${key}.title"
    flag="${MANAGED_DIR}/${key}"
    if [ -n "$top" ]; then
      base=$(basename "$top")
      title=$(compute_label "$base" "$cwd")
      # worktree dir often == branch name → collapse "repo · repo ·" to "repo ·"
      title="${title/#${base}${SEP}${base}${SEP}/${base}${SEP}}"
      last=''; [ -f "$titlef" ] && last=$(cat "$titlef" 2>/dev/null)
      if [ "$title" != "$last" ]; then
        herdr pane rename "$pid" "$title" >/dev/null 2>&1 && printf '%s' "$title" > "$titlef"
      fi
      : > "$flag"
      seen_git="${seen_git} ${key} "
    elif [ -f "$flag" ]; then
      # pane left git (or closed→id reused): clear our title
      herdr pane rename "$pid" --clear >/dev/null 2>&1
      rm -f "$flag" "$titlef"
    fi
  done < <(herdr pane list 2>/dev/null \
           | jq -r '.result.panes[] | [.pane_id,(.foreground_cwd // .cwd)] | @tsv' 2>/dev/null)

  # Clear titles for managed panes that vanished from the pane list entirely.
  for flag in "$MANAGED_DIR"/*; do
    [ -e "$flag" ] || continue
    key=$(basename "$flag")
    case "$seen_git" in *" $key "*) continue;; esac
    rm -f "$flag" "${CACHE_DIR}/pane-${key}.title"
  done
}

pass() { update_sidebar; update_panes; }

if [ "${1:-}" = "once" ]; then pass; exit 0; fi
while :; do pass; sleep "$INTERVAL"; done
