#!/bin/bash
# Hook: preToolUse — block destructive shell commands
EVENT=$(cat)
CMD=$(echo "$EVENT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//')
[ -z "$CMD" ] && exit 0
case "$CMD" in
  *"rm -rf /"*|*"rm -rf ~"*|*"rm -rf *"*) echo "BLOCKED: Destructive command — rm -rf with dangerous target." >&2; exit 2 ;;
  *"git push --force"*|*"git push -f "*) echo "BLOCKED: Force-push not allowed. Use release-engineer for controlled pushes." >&2; exit 2 ;;
  *"git reset --hard"*) echo "BLOCKED: Hard reset not allowed without explicit user approval." >&2; exit 2 ;;
  *"DROP DATABASE"*|*"DROP TABLE"*|*"drop database"*|*"drop table"*) echo "BLOCKED: Destructive SQL — DROP not allowed via hook. Use data-migrator with reversible migrations." >&2; exit 2 ;;
esac
exit 0