#!/bin/bash
# Hook: preToolUse — worktree confinement (ADR-0004 Rule 2.6)
# Sessions running inside an executor worktree (*/.wt/*/*) may only write
# inside their worktree + the junctioned .ai/. Absolute paths that escape
# the tree and ../ traversals are blocked.

INPUT=$(cat)
# Empty (or whitespace-only) stdin → nothing to evaluate → allow.
if [ -z "$(printf '%s' "$INPUT" | tr -d '[:space:]')" ]; then
    exit 0
fi
# Extraction MUST NOT depend on python (fail-CLOSED). python3 can resolve to a
# Windows Store alias stub (empty stdout, exit 0); a `|| python` chain keyed on
# exit status silently no-ops → fail-OPEN. python optional-first; pure-sed fallback
# on EMPTY output; fail-CLOSED if nothing parses. Matched to fs_write only.
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

# Normalize backslashes to forward slashes
FILE_PATH=$(echo "$FILE_PATH" | tr '\\' '/')

# Only applies when cwd matches */.wt/*/*  (executor worktree layout)
PROJECT_ROOT=$(pwd)
case "$PROJECT_ROOT" in
  */.wt/*/*) ;;
  *) exit 0 ;;  # not in a worktree — rule does not apply
esac

# Block absolute paths (they escape the worktree by definition since they
# didn't normalize to a relative path under this tree)
case "$FILE_PATH" in
  /*|[A-Za-z]:/*)
    echo "BLOCKED: Worktree confinement (ADR-0004) — this session runs in executor worktree '$PROJECT_ROOT' and may write only inside it (+ the junctioned .ai/). Escaping to '$FILE_PATH' is blocked — cross-tree changes go through .ai/handoffs/." >&2
    exit 2 ;;
esac

# Block ../ traversal (escapes the worktree boundary)
case "$FILE_PATH" in
  ..|../*|*/..|*/../*)
    echo "BLOCKED: Worktree confinement (ADR-0004) — relative path '$FILE_PATH' escapes the worktree. Write only inside this worktree; cross-tree changes go through .ai/handoffs/." >&2
    exit 2 ;;
esac

# In-tree relative paths (including .ai/ via junction) are allowed
exit 0
