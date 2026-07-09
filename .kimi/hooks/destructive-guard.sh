#!/bin/bash
# Hook 4: Destructive command guard
# Block dangerous shell commands

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

extract_command() {
    local out
    out=$(printf '%s' "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null)
    [ -n "$out" ] && { printf '%s' "$out"; return; }
    out=$(printf '%s' "$1" | python  -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null)
    [ -n "$out" ] && { printf '%s' "$out"; return; }
    out=$(printf '%s' "$1" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    [ -n "$out" ] && { printf '%s' "$out"; return; }
}

COMMAND=$(extract_command "$INPUT")

if [ -z "$COMMAND" ]; then
    echo "BLOCKED: Could not parse Bash command input; failing closed against destructive commands." >&2
    exit 2
fi

# Normalize: lowercase for matching
CMD_LOWER=$(echo "$COMMAND" | tr '[:upper:]' '[:lower:]')

# Check destructive patterns
# Normalize whitespace
NORM=$(echo "$CMD_LOWER" | tr -s ' \t' '  ')

rm_flags='(-[rf]+|-r[[:space:]]+-f|-f[[:space:]]+-r|--recursive[[:space:]]+--force|--force[[:space:]]+--recursive)'
rm_target='(/|~|\*|\.)'
rm_tail='([[:space:]]|[;|&]|$)'
if [[ " $NORM " =~ [[:space:]]rm[[:space:]]+${rm_flags}[[:space:]]+${rm_target}${rm_tail} ]]; then
    echo "BLOCKED: rm -rf with a dangerous target (/, ~, *, .) is not allowed." >&2
    exit 2
fi

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
