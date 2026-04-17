#!/bin/bash
# Hook 1: Root file guard
# Block writes to project root except files listed in ADR Category A
# See docs/architecture/0001-root-file-exceptions.md for the full allowlist

read JSON

FILE_PATH=$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || \
            python -c  "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || \
            echo "")

# If we couldn't parse, fail open
[ -z "$FILE_PATH" ] && exit 0

# Check if file is at root (no directory separator)
# Allow root files that ARE explicitly permitted
BASENAME=$(basename "$FILE_PATH")

if echo "$FILE_PATH" | grep -q '/'; then
    # Path contains / — not at root, allow
    exit 0
fi

# Path is at root level — check allowlist
case "$BASENAME" in
    AGENTS.md|README.md|CLAUDE.md)
        exit 0
        ;;
    *)
        echo "BLOCKED: Writing '$BASENAME' to project root is not allowed. Root-level files are restricted to AGENTS.md, README.md, CLAUDE.md. Move this file to the appropriate subdirectory (e.g., config/, infra/, src/)." >&2
        exit 2
        ;;
esac
