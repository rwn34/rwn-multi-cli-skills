#!/bin/bash
# Hook 2: Framework directory guard
# Block writes to other CLIs' framework directories (.claude/, .kiro/)
# .kimi/ is Kimi's own territory. .ai/ is shared with other CLIs
# (allowed for orchestrator; subagent writes restricted per agent config).

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

extract_path() {
    local out
    out=$(printf '%s' "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); ti=d.get('tool_input',{}); print(ti.get('file_path') or ti.get('path',''))" 2>/dev/null)
    [ -n "$out" ] && { printf '%s' "$out"; return; }
    out=$(printf '%s' "$1" | python  -c "import sys,json; d=json.load(sys.stdin); ti=d.get('tool_input',{}); print(ti.get('file_path') or ti.get('path',''))" 2>/dev/null)
    [ -n "$out" ] && { printf '%s' "$out"; return; }
    out=$(printf '%s' "$1" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    [ -n "$out" ] && { printf '%s' "$out"; return; }
    out=$(printf '%s' "$1" | sed -n 's/.*"path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    [ -n "$out" ] && { printf '%s' "$out"; return; }
}

FILE_PATH=$(extract_path "$INPUT")

if [ -z "$FILE_PATH" ]; then
    echo "BLOCKED: Could not parse tool input path; failing closed against cross-CLI writes." >&2
    exit 2
fi

# Block other CLIs' framework and graph directories
case "$FILE_PATH" in
    .claude/*|.kiro/*|.codegraph/*|.kirograph/*|.kimigraph/*)
        echo "BLOCKED: Writing to '$FILE_PATH' is not allowed. That path is owned by another CLI. Use .ai/ or .kimi/ for framework-level files." >&2
        exit 2
        ;;
    *)
        exit 0
        ;;
esac
