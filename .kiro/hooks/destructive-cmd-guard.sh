#!/bin/bash
# Hook: preToolUse — block destructive shell commands
# See docs/architecture/0001-root-file-exceptions.md and consolidated audit for pattern rationale

# Extraction MUST NOT depend on python (fail-CLOSED). python3 can resolve to a
# Windows Store alias stub (empty stdout, exit 0), so a `|| python` chain keyed on
# exit status silently no-ops → a destructive command sails through (fail-OPEN).
# Mirror .claude/hooks/pretool-write-edit.sh (588ed9c): python optional-first,
# pure-sed fallback on EMPTY output, fail-CLOSED if nothing parses. Matched to
# execute_bash only, so stdin always carries command.
INPUT=$(cat)
# Empty (or whitespace-only) stdin → nothing to evaluate → allow.
if [ -z "$(printf '%s' "$INPUT" | tr -d '[:space:]')" ]; then
    exit 0
fi
CMD=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)
[ -z "$CMD" ] && CMD=$(printf '%s' "$INPUT" | python -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)
[ -z "$CMD" ] && CMD=$(printf '%s' "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
# Non-empty stdin but no command parsed → refuse to fail open.
if [ -z "$CMD" ]; then
    echo "BLOCKED: could not parse tool input (no command found) — refusing to fail open." >&2
    exit 2
fi
CMD=$(echo "$CMD" | tr '[:upper:]' '[:lower:]')

# Normalize whitespace for boundary matching
NORM=$(echo "$CMD" | tr -s ' \t' '  ')

# rm -rf with dangerous target (/, ~, *, .) — boundary-aware
rm_flags='(-[rf]+|-r[[:space:]]+-f|-f[[:space:]]+-r|--recursive[[:space:]]+--force|--force[[:space:]]+--recursive)'
rm_target='(/|~|\*|\.)'
rm_tail='([[:space:]]|[;|&]|$)'
if [[ " $NORM " =~ [[:space:]]rm[[:space:]]+${rm_flags}[[:space:]]+${rm_target}${rm_tail} ]]; then
    echo "BLOCKED: Destructive command — rm -rf with dangerous target." >&2
    exit 2
fi

case "$CMD" in
  *"git push --force"*|*"git push -f "*|*"git push --force-with-lease"*) echo "BLOCKED: Force-push not allowed. Use release-engineer for controlled pushes." >&2; exit 2 ;;
  *"git reset --hard"*) echo "BLOCKED: Hard reset not allowed without explicit user approval." >&2; exit 2 ;;
  *"drop database"*|*"drop table"*|*"drop schema"*) echo "BLOCKED: Destructive SQL — DROP not allowed via hook. Use data-migrator with reversible migrations." >&2; exit 2 ;;
  *"truncate table"*) echo "BLOCKED: Destructive SQL — TRUNCATE not allowed via hook. Use data-migrator with reversible migrations." >&2; exit 2 ;;
esac
exit 0
