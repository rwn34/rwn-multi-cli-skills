#!/bin/bash
# Hook: preToolUse — block writes to sensitive files

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

# basename works on both relative and absolute paths, so the filename patterns
# below are already absolute-safe.
BASE=$(basename "$FILE_PATH")
case "$BASE" in
  .env|.env.*|*.key|*.pem|id_rsa*|id_ed25519*|*.p12|*.pfx|secrets.*|*.secrets|*-secrets.*|credentials|credentials.*|*-credentials.*) echo "BLOCKED: Sensitive file protection — cannot write to $BASE. Use config/ with .gitignore for secrets." >&2; exit 2 ;;
esac

# Directory rule (.aws/, .ssh/): segment-match so absolute paths (Kiro emits
# these) are caught too, not just relative ones. Normalize backslashes first.
REL=$(printf '%s' "$FILE_PATH" | tr '\\' '/')
case "$REL" in
  .aws/*|*/.aws/*|.ssh/*|*/.ssh/*) echo "BLOCKED: Sensitive directory — cannot write to $FILE_PATH." >&2; exit 2 ;;
esac
exit 0
