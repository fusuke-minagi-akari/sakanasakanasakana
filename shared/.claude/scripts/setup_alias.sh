#!/usr/bin/env bash
# Cross-platform alias installer for Claude Code sync
# Supports: macOS, Ubuntu 22/24, Windows (WSL or Git Bash)
#
# Usage:
#   bash ~/.claude/scripts/setup_alias.sh
#
# After running, type `csync` in any terminal to sync skills.

ALIAS_NAME="csync"
SCRIPT="$HOME/.claude/scripts/sync_skills.sh"

# ── OS detection ─────────────────────────────────────────────────────────────

detect_os() {
  local uname
  uname=$(uname -s 2>/dev/null || echo "Windows_NT")
  case "$uname" in
    Darwin*)  echo "macos" ;;
    Linux*)
      if grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl"
      else
        echo "linux"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*) echo "gitbash" ;;
    *)        echo "unknown" ;;
  esac
}

# ── Helpers ───────────────────────────────────────────────────────────────────

append_if_missing() {
  local file="$1"
  local line="$2"
  if [[ ! -f "$file" ]]; then
    touch "$file"
  fi
  if grep -qF "$ALIAS_NAME" "$file" 2>/dev/null; then
    echo "  already set in $file"
  else
    echo "$line" >> "$file"
    echo "  added to $file"
  fi
}

# ── PowerShell profile helper (called by install_windows) ────────────────────

install_pwsh() {
  local profile_path
  profile_path=$(powershell.exe -NoProfile -Command \
    '[System.Environment]::GetFolderPath("MyDocuments") + "\PowerShell\Microsoft.PowerShell_profile.ps1"' \
    2>/dev/null | tr -d '\r')

  if [[ -z "$profile_path" ]]; then
    echo "  Could not detect PowerShell profile path"
    return 1
  fi

  # Convert Windows path to WSL path
  local wsl_path
  wsl_path=$(wslpath "$profile_path" 2>/dev/null || echo "")

  if [[ -z "$wsl_path" ]]; then
    echo "  Could not convert path — add manually to PowerShell \$PROFILE:"
    echo "    function $ALIAS_NAME { wsl bash ~/.claude/scripts/sync_skills.sh }"
    return
  fi

  mkdir -p "$(dirname "$wsl_path")"
  local pwsh_line="function $ALIAS_NAME { wsl bash ~/.claude/scripts/sync_skills.sh }"
  if grep -qF "$ALIAS_NAME" "$wsl_path" 2>/dev/null; then
    echo "  already set in PowerShell profile"
  else
    echo "$pwsh_line" >> "$wsl_path"
    echo "  added to PowerShell profile: $profile_path"
  fi
}

# ── Per-OS install ────────────────────────────────────────────────────────────

install_macos() {
  local line="alias $ALIAS_NAME='bash $SCRIPT'"
  echo "macOS detected — adding alias to shell rc files"
  append_if_missing "$HOME/.zshrc"  "$line"
  append_if_missing "$HOME/.bashrc" "$line"
  echo ""
  echo "  Reload: source ~/.zshrc   (or open a new terminal)"
}

install_linux() {
  local line="alias $ALIAS_NAME='bash $SCRIPT'"
  echo "Linux detected — adding alias to ~/.bashrc"
  append_if_missing "$HOME/.bashrc" "$line"
  if [[ -f "$HOME/.bash_aliases" ]]; then
    append_if_missing "$HOME/.bash_aliases" "$line"
  fi
  echo ""
  echo "  Reload: source ~/.bashrc   (or open a new terminal)"
}

install_wsl() {
  echo "WSL detected — installing for both bash and PowerShell"
  echo ""
  echo "  [bash]"
  local line="alias $ALIAS_NAME='bash $SCRIPT'"
  append_if_missing "$HOME/.bashrc" "$line"

  echo ""
  echo "  [PowerShell]"
  install_pwsh

  echo ""
  echo "  Reload bash:       source ~/.bashrc"
  echo "  Reload PowerShell: . \$PROFILE"
}

install_gitbash() {
  local line="alias $ALIAS_NAME='bash $SCRIPT'"
  echo "Git Bash detected — adding alias to ~/.bashrc"
  append_if_missing "$HOME/.bashrc" "$line"
  echo ""
  echo "  Reload: source ~/.bashrc   (or open a new Git Bash window)"
  echo ""
  echo "  Note: rsync is not included in Git Bash by default."
  echo "  The script falls back to scp automatically."
  echo "  For full rsync support install: https://itefix.net/cwrsync"
}

# ── Main ─────────────────────────────────────────────────────────────────────

echo "=== Claude Code sync alias installer ==="
echo "Alias:  $ALIAS_NAME"
echo "Script: $SCRIPT"
echo ""

OS=$(detect_os)

case "$OS" in
  macos)   install_macos ;;
  linux)   install_linux ;;
  wsl)     install_wsl ;;
  gitbash) install_gitbash ;;
  *)
    echo "Unknown OS — add the alias manually:"
    echo ""
    echo "  bash/zsh:   alias $ALIAS_NAME='bash $SCRIPT'"
    echo "  PowerShell: function $ALIAS_NAME { wsl bash $SCRIPT }"
    ;;
esac

echo ""
echo "=== Done. Type '$ALIAS_NAME' to sync skills to all devices. ==="
