#!/bin/bash
# Hook 4: Destructive command guard
# Block dangerous shell commands

read JSON

COMMAND=$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || \
          python -c  "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || \
          echo "")

[ -z "$COMMAND" ] && exit 0

# Normalize: lowercase for matching
CMD_LOWER=$(echo "$COMMAND" | tr '[:upper:]' '[:lower:]')

# Check destructive patterns
case "$CMD_LOWER" in
    *"rm -rf /"*|*"rm -rf /*"*)
        echo "BLOCKED: rm -rf / or rm -rf /* is extremely dangerous and not allowed." >&2
        exit 2
        ;;
    *"rm -rf *"*)
        echo "BLOCKED: rm -rf * is dangerous in the wrong directory. Use rm with explicit file list." >&2
        exit 2
        ;;
    *"rm -rf ~"*)
        echo "BLOCKED: rm -rf ~ destroys your home directory." >&2
        exit 2
        ;;
    *"rm -rf ."*)
        echo "BLOCKED: rm -rf . deletes the current directory." >&2
        exit 2
        ;;
esac

# git push --force / -f / --force-with-lease
if echo "$CMD_LOWER" | grep -qE 'git\s+push\s+.*(--force|-f|--force-with-lease)\b'; then
    echo "BLOCKED: git push --force or --force-with-lease is dangerous on shared branches. Delegate to infra-engineer." >&2
    exit 2
fi

# git reset --hard
if echo "$CMD_LOWER" | grep -qE 'git\s+reset\s+.*--hard\b'; then
    echo "BLOCKED: git reset --hard destroys uncommitted work. Use git stash or git reset --soft instead, or delegate to infra-engineer." >&2
    exit 2
fi

# DROP TABLE / DROP DATABASE / DROP SCHEMA
if echo "$CMD_LOWER" | grep -qE '\bdrop\s+table\b|\bdrop\s+database\b|\bdrop\s+schema\b'; then
    echo "BLOCKED: DROP TABLE/DATABASE/SCHEMA is destructive. Use migrations or delegate to data-migrator." >&2
    exit 2
fi

# TRUNCATE TABLE
if echo "$CMD_LOWER" | grep -qE '\btruncate\s+table\b'; then
    echo "BLOCKED: TRUNCATE TABLE is destructive. Use migrations or delegate to data-migrator." >&2
    exit 2
fi

exit 0
