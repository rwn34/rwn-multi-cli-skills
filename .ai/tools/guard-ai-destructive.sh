#!/usr/bin/env bash
# guard-ai-destructive.sh — block destructive git/shell commands when .ai/ is
# junctioned into the canonical coordination plane.
#
# Usage:
#   bash .ai/tools/guard-ai-destructive.sh --check [path]   # exit 0 if safe
#   bash .ai/tools/guard-ai-destructive.sh <command>...     # run command if safe
#
# The canonical deletion incident (2026-07-16, saja-qr): `git clean -fd` and
# `git worktree remove --force` followed .ai/ junctions into the primary checkout
# and deleted shared coordination-plane state. This guard refuses those commands
# while .ai/ is still mounted.
#
# Designed to be sourced or invoked standalone. Returns 0 / runs the command when
# .ai/ is absent, a normal directory, or explicitly unmounted; exits 1 when .ai/
# is a junction/symlink.
set -euo pipefail

err() { echo "[guard-ai-destructive] ERROR: $*" >&2; }
warn() { echo "[guard-ai-destructive] WARN: $*" >&2; }

is_windows() {
  case "$(uname -s 2>/dev/null || echo "${OS:-}")" in
    *MINGW*|*MSYS*|*CYGWIN*|Windows_NT) return 0 ;;
    *) return 1 ;;
  esac
}

winpath() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    echo "$1" | sed -e 's|^/\([a-zA-Z]\)/|\1:/|' -e 's|/|\\|g'
  fi
}

cmd_islink() {
  local name
  name="$(basename "$1")"
  name="${name//./\\.}"
  cmd //c dir //a:l "$(dirname "$(winpath "$1")")" 2>/dev/null \
    | grep -i "$name" || true
}

# Return 0 if <path>/.ai is a junction (Windows) or symlink (POSIX).
ai_is_mounted() {
  local wt_path="${1:-.}"
  local link="$wt_path/.ai"
  [ -e "$link" ] || return 1
  if [ -L "$link" ]; then
    return 0
  fi
  if is_windows && [ -d "$link" ] && [ -n "$(cmd_islink "$link")" ]; then
    return 0
  fi
  return 1
}

print_help() {
  cat <<'EOF'
guard-ai-destructive.sh — refuse destructive ops while .ai/ is junctioned.

Usage:
  bash guard-ai-destructive.sh --check [path]     # exit 0 if .ai/ is safe
  bash guard-ai-destructive.sh <command>...       # run command if .ai/ is safe

Examples:
  bash guard-ai-destructive.sh git clean -fd
  bash guard-ai-destructive.sh git worktree remove --force .wt/proj/kiro
  bash guard-ai-destructive.sh --check .wt/proj/kiro && echo safe

When .ai/ is a junction/symlink, the guard prints the command it blocked and
exits 1 without running it. Use `scripts/wt-bootstrap.sh --remove <proj> <cli>`
to unmount .ai/ and remove the worktree safely.
EOF
}

# Resolve target directory from optional --cwd flag or first positional arg.
cwd="."
cmd_start=1
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  print_help
  exit 0
fi
if [ "${1:-}" = "--check" ]; then
  if [ -n "${2:-}" ]; then
    cwd="$2"
  fi
  if ai_is_mounted "$cwd"; then
    err ".ai/ is still mounted at $cwd/.ai — destructive operations are blocked"
    exit 1
  fi
  exit 0
fi

if [ "$#" -eq 0 ]; then
  print_help
  exit 1
fi

if ai_is_mounted "$cwd"; then
  err ".ai/ is still mounted at $cwd/.ai — blocked command: $*"
  err "Use: bash scripts/wt-bootstrap.sh --remove <project-dir> <executor>"
  exit 1
fi

# Safe: run the requested command.
exec "$@"
