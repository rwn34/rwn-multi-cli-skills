#!/bin/bash
# PreToolUse hook — matcher: Bash
# Blocks destructive commands that should require explicit user action.
# Reads tool call JSON from stdin; exit 2 + stderr to block.

cmd=$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || \
     python  -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || \
     echo "")

[ -z "$cmd" ] && exit 0

# Normalize whitespace to single spaces for matching
norm=$(echo "$cmd" | tr -s ' \t' '  ')

block() {
    echo "BLOCKED by hook: $1" >&2
    exit 2
}

# Dangerous rm patterns — broad targets (/ ~ * .)
# Boundary-aware: the target must be followed by whitespace, a shell separator
# (; & |), or end-of-string. Otherwise `rm -rf /tmp/foo` would false-positive
# on a naive substring match against `rm -rf /`.
rm_flags='(-[rRfF]+|-r[[:space:]]+-f|-f[[:space:]]+-r|--recursive[[:space:]]+--force|--force[[:space:]]+--recursive)'
rm_target='(/|~|\*|\.)'
rm_tail='([[:space:]]|[;|&]|$)'
if [[ " $norm " =~ [[:space:]]rm[[:space:]]+${rm_flags}[[:space:]]+${rm_target}${rm_tail} ]]; then
    block "'rm -rf' with a broad target (/, ~, *, .) is destructive. Use a specific path, or ask the user to run it manually."
fi

# Force push — any variant (including --force-with-lease, which is still risky)
case " $norm " in
    *"git push --force"*|*"git push -f "*|*"git push -f"|*"--force-with-lease"*)
        block "Force-push variants (--force, -f, --force-with-lease) overwrite remote history. Route through release-engineer with explicit user approval." ;;
esac

# Hard reset
case " $norm " in
    *"git reset --hard"*|*"git reset -q --hard"*|*"git reset --hard "*)
        block "'git reset --hard' discards uncommitted changes. Ask the user before resetting." ;;
esac

# DROP / TRUNCATE in SQL contexts (uppercase match)
upper=$(echo "$norm" | tr '[:lower:]' '[:upper:]')
case " $upper " in
    *" DROP DATABASE "*|*" DROP TABLE "*|*" DROP SCHEMA "*|*" TRUNCATE TABLE "*|*"DROP DATABASE "*|*"DROP TABLE "*|*"DROP SCHEMA "*|*"TRUNCATE TABLE "*)
        block "DROP / TRUNCATE destroys data. Route through data-migrator with explicit user confirmation." ;;
esac

exit 0
