#!/bin/bash
# Hook: preToolUse — block writes to project root (except AGENTS.md, README.md, CLAUDE.md)
EVENT=$(cat)
FILE_PATH=$(echo "$EVENT" | grep -o '"path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"path"[[:space:]]*:[[:space:]]*"//;s/"$//')
[ -z "$FILE_PATH" ] && exit 0
# Check if file is at root (no directory separator)
DIR=$(dirname "$FILE_PATH")
if [ "$DIR" = "." ]; then
  BASE=$(basename "$FILE_PATH")
  case "$BASE" in
    AGENTS.md|README.md|CLAUDE.md) exit 0 ;;
    *) echo "BLOCKED: Root file policy — only AGENTS.md, README.md, CLAUDE.md allowed at root. Place this file in the appropriate directory (src/, config/, infra/, etc.)." >&2; exit 2 ;;
  esac
fi
exit 0