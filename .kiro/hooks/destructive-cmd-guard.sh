#!/bin/bash
# Hook: preToolUse — block destructive shell commands
# See docs/architecture/0001-root-file-exceptions.md and consolidated audit for pattern rationale

CMD=$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || \
      python  -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || \
      echo "")
[ -z "$CMD" ] && exit 0

case "$CMD" in
  *"rm -rf /"*|*"rm -rf ~"*|*"rm -rf *"*|*"rm -rf ."*) echo "BLOCKED: Destructive command — rm -rf with dangerous target." >&2; exit 2 ;;
  *"git push --force"*|*"git push -f "*|*"git push --force-with-lease"*) echo "BLOCKED: Force-push not allowed. Use release-engineer for controlled pushes." >&2; exit 2 ;;
  *"git reset --hard"*) echo "BLOCKED: Hard reset not allowed without explicit user approval." >&2; exit 2 ;;
  *"DROP DATABASE"*|*"DROP TABLE"*|*"DROP SCHEMA"*|*"drop database"*|*"drop table"*|*"drop schema"*) echo "BLOCKED: Destructive SQL — DROP not allowed via hook. Use data-migrator with reversible migrations." >&2; exit 2 ;;
  *"TRUNCATE TABLE"*|*"truncate table"*) echo "BLOCKED: Destructive SQL — TRUNCATE not allowed via hook. Use data-migrator with reversible migrations." >&2; exit 2 ;;
esac
exit 0
