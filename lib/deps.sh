# shellcheck shell=bash
# Dependency layer for install.sh. Sourced AFTER install.sh defines say()/run()
# and the $DRY / $OS variables. Installs herdr + kitty + the CLI tools that
# `show` and herdr-branch-labels.sh need, handling four machine states per
# component: brand-new (install), half-built (fill gaps), corrupt (clean +
# reinstall), already-built (skip).
#
# Reuses install.sh's run() (string-eval, honours $DRY) and say().

# /etc/os-release is a runtime file, not available to the linter.
# shellcheck disable=SC1091
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
is_dangling() { [ -L "$1" ] && [ ! -e "$1" ]; }

STATE_OK=0; STATE_MISSING=1; STATE_CORRUPT=2

# ensure NAME check_fn install_fn [clean_fn] — dispatch on component state.
ensure() {
    local name="$1" check="$2" install="$3" clean="${4:-}" st=0
    "$check" || st=$?
    case "$st" in
        "$STATE_OK")      say "  ok    $name (healthy)";;
        "$STATE_MISSING") say "deps: $name missing — installing"; "$install"; _verify "$name" "$check";;
        "$STATE_CORRUPT")
            say "deps: $name corrupt — cleaning + reinstalling"
            [ -n "$clean" ] && "$clean"
            "$install"; _verify "$name" "$check";;
        *) die "$name: check returned $st";;
    esac
}
_verify() {
    [ "$DRY" = 1 ] && return 0
    local st=0; "$2" || st=$?
    if [ "$st" = "$STATE_OK" ]; then say "  ok    $1 (verified)"; else say "  WARN  $1 still unhealthy (state=$st)"; fi
}

verify_commands() {
    [ "$DRY" = 1 ] && return 0
    local c
    for c in $1; do
        if have "$c"; then say "  ok    cmd $c"; else say "  WARN  cmd $c missing after install"; fi
    done
}

# --- package-manager detection: sets PKG_INSTALL + PKG_LIST ---------------
detect_pkg() {
    case "$OS" in
        macos)
            PKG_INSTALL="brew install"; PKG_LIST="$REPO/packages/brew.txt";;
        linux)
            if [ -r /etc/os-release ]; then . /etc/os-release; fi
            case "${ID:-}${ID_LIKE:-}" in
                *debian*|*ubuntu*) PKG_INSTALL="sudo apt-get install -y"; PKG_LIST="$REPO/packages/apt.txt";;
                *arch*)            PKG_INSTALL="sudo pacman -S --needed --noconfirm"; PKG_LIST="$REPO/packages/pacman.txt";;
                *) die "unsupported Linux distro (ID=${ID:-?}); supported: debian/ubuntu, arch";;
            esac;;
        *) die "unsupported OS for deps: $OS";;
    esac
}

install_packages() {
    [ -f "$PKG_LIST" ] || { say "  WARN  no package list: $PKG_LIST"; return; }
    local pkgs=() p
    while IFS= read -r p; do p="${p%%#*}"; p="${p// /}"; [ -n "$p" ] && pkgs+=("$p"); done < "$PKG_LIST"
    [ "${#pkgs[@]}" -gt 0 ] || return
    say "deps: packages -> ${pkgs[*]}"
    run "$PKG_INSTALL ${pkgs[*]}"
}

# --- herdr (herdr.dev installer; same on every Unix) ----------------------
HERDR_BIN="$HOME/.local/bin/herdr"
check_herdr() {
    if have herdr && herdr --version >/dev/null 2>&1; then return "$STATE_OK"; fi
    if have herdr || [ -e "$HERDR_BIN" ] || compgen -G "$HERDR_BIN"'*.tmp' >/dev/null 2>&1 \
       || compgen -G "$HERDR_BIN"'*.part' >/dev/null 2>&1; then return "$STATE_CORRUPT"; fi
    return "$STATE_MISSING"
}
clean_herdr() { run "rm -f '$HERDR_BIN' '$HERDR_BIN'*.tmp '$HERDR_BIN'*.part"; }
install_herdr() {
    have curl || die "curl required to install herdr"
    if [ "$OS" = macos ] && brew install herdr >/dev/null 2>&1; then say "  herdr via brew"; return; fi
    run "curl -fsSL https://herdr.dev/install.sh | sh"
}

# --- kitty (per-OS install; graphics protocol terminal) -------------------
check_kitty() {
    if have kitty && kitty --version >/dev/null 2>&1; then return "$STATE_OK"; fi
    case "$OS" in
        macos) { brew list --cask kitty >/dev/null 2>&1 || [ -d /Applications/kitty.app ]; } && return "$STATE_CORRUPT";;
        linux) { [ -e "$HOME/.local/kitty.app" ] || is_dangling "$HOME/.local/bin/kitty" || is_dangling "$HOME/.local/bin/kitten"; } && return "$STATE_CORRUPT";;
    esac
    return "$STATE_MISSING"
}
clean_kitty() {
    case "$OS" in
        macos) run "brew uninstall --cask --force kitty || true";;
        linux)
            run "rm -rf '$HOME/.local/kitty.app'"
            is_dangling "$HOME/.local/bin/kitty"  && run "rm -f '$HOME/.local/bin/kitty'"
            is_dangling "$HOME/.local/bin/kitten" && run "rm -f '$HOME/.local/bin/kitten'";;
    esac
}
install_kitty() {
    case "$OS" in
        macos) run "brew install --cask kitty";;
        linux)
            if [ -r /etc/os-release ]; then . /etc/os-release; fi
            case "${ID:-}${ID_LIKE:-}" in
                *arch*) run "sudo pacman -S --needed --noconfirm kitty";;
                *)  # official installer into ~/.local, then launcher symlinks
                    run "curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin"
                    run "mkdir -p '$HOME/.local/bin'"
                    run "ln -sf '$HOME/.local/kitty.app/bin/kitty'  '$HOME/.local/bin/kitty'"
                    run "ln -sf '$HOME/.local/kitty.app/bin/kitten' '$HOME/.local/bin/kitten'";;
            esac;;
    esac
}

# --- top-level entry called by install.sh ---------------------------------
install_deps() {
    say "deps: detecting package manager for $OS"
    detect_pkg
    # prerequisites for the curl-piped installers on a bare OS
    case "$OS" in
        linux)
            if [ -r /etc/os-release ]; then . /etc/os-release; fi
            case "${ID:-}${ID_LIKE:-}" in
                *arch*) run "sudo pacman -Sy --needed --noconfirm curl ca-certificates git file tar";;
                *)      run "sudo apt-get update -y"; run "sudo apt-get install -y curl ca-certificates git file tar";;
            esac;;
        macos)
            have git || run "xcode-select --install || true"
            if ! have brew; then
                run "/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
            fi;;
    esac
    install_packages
    verify_commands "glow chafa mpv jq gh git"
    ensure kitty check_kitty install_kitty clean_kitty
    ensure herdr check_herdr install_herdr clean_herdr
}
