#!/bin/bash
# Hook: preToolUse — worktree confinement (ADR-0004 Rule 2.6)
# Sessions running inside an executor worktree (*/.wt/*/*) may only write
# inside their worktree + the junctioned .ai/. Absolute paths that escape
# the tree and ../ traversals are blocked.

INPUT=$(cat)
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || \
            printf '%s' "$INPUT" | python  -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || \
            echo "")
[ -z "$FILE_PATH" ] && exit 0

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
