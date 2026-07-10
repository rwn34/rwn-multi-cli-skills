#!/bin/bash
# Hook: preToolUse — block writes to project root unless the file is on the ADR-0001 allowlist

# Extraction MUST NOT depend on python (fail-CLOSED). python3 can resolve to a
# Windows Store alias stub (empty stdout, exit 0), so a `|| python` chain keyed on
# exit status silently no-ops → fail-OPEN. Mirror .claude/hooks/pretool-write-edit.sh
# (588ed9c): python optional-first, pure-sed fallback on EMPTY output, fail-CLOSED
# if nothing parses. Matched to fs_write only, so stdin always carries file_path.
INPUT=$(cat)
if [ -z "$(printf '%s' "$INPUT" | tr -d '[:space:]')" ]; then
    exit 0
fi
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)
[ -z "$FILE_PATH" ] && FILE_PATH=$(printf '%s' "$INPUT" | python -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)
[ -z "$FILE_PATH" ] && FILE_PATH=$(printf '%s' "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
# Kiro's fs_write / str_replace tool_input carries the target under "path", not
# "file_path" — fall back to it so str_replace/fs_write edits are actually
# path-evaluated (not blanket fail-CLOSED-blocked). python optional-first,
# pure-sed fallback on EMPTY output; the sed pattern needs a literal quote
# before "path" so it never mis-matches "file_path".
[ -z "$FILE_PATH" ] && FILE_PATH=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('path',''))" 2>/dev/null)
[ -z "$FILE_PATH" ] && FILE_PATH=$(printf '%s' "$INPUT" | python -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('path',''))" 2>/dev/null)
[ -z "$FILE_PATH" ] && FILE_PATH=$(printf '%s' "$INPUT" | sed -n 's/.*"path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
if [ -z "$FILE_PATH" ]; then
    echo "BLOCKED: could not parse tool input (no file_path or path found) — refusing to fail open." >&2
    exit 2
fi

# Normalize absolute → project-root-relative so the "at root" check works when
# the runtime emits an ABSOLUTE file_path (Kiro does). Prefer Windows-form cwd
# (C:/…) via `pwd -W` to match drive-letter paths; strip the root prefix
# case-insensitively (Windows FS) by LENGTH. Without this, an absolute path's
# dirname is never "." so a root-level write (e.g. evil.txt) bypassed the guard
# — same class as validation T-K2, 2026-07-09.
FP=$(printf '%s' "$FILE_PATH" | tr '\\' '/')
ROOT_W=$(pwd -W 2>/dev/null || pwd); ROOT_W="${ROOT_W%/}"
REL="$FP"
shopt -s nocasematch 2>/dev/null
case "$FP" in
  "$ROOT_W"/*) REL="${FP:$((${#ROOT_W}+1))}" ;;
esac
shopt -u nocasematch 2>/dev/null

# Check if file is at root (no directory separator after normalization)
DIR=$(dirname "$REL")
if [ "$DIR" = "." ]; then
  BASE=$(basename "$REL")
  case "$BASE" in
    # ADR category A — docs entry points
    AGENTS.md|README.md|CLAUDE.md) exit 0 ;;
    LICENSE|LICENSE.*) exit 0 ;;
    CHANGELOG|CHANGELOG.*) exit 0 ;;
    CONTRIBUTING.md|SECURITY.md|CODE_OF_CONDUCT.md) exit 0 ;;
    # ADR category E (partial) — MCP convention
    .mcp.json|.mcp.json.example) exit 0 ;;
    # Category B — git-mandated dotfiles
    .gitignore|.gitattributes) exit 0 ;;
    # Category C — editor-mandated
    .editorconfig) exit 0 ;;
    # Category D — platform / CI-vendor dotfiles at root
    .dockerignore|.gitlab-ci.yml) exit 0 ;;
    # Categories F/G/H — amend alongside the ADR when a language/tool is chosen.
    # See docs/architecture/0001-root-file-exceptions.md for the full allowlist.
    *) echo "BLOCKED: Root file policy — '$BASE' not in the allowlist from docs/architecture/0001-root-file-exceptions.md. Place this file in the appropriate directory (src/, config/, infra/, etc.) or amend the ADR if it's a tooling-required exception." >&2; exit 2 ;;
  esac
fi
exit 0
