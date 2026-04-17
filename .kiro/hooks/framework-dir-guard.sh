#!/bin/bash
# Hook: preToolUse — block subagent writes to other CLIs' framework dirs
EVENT=$(cat)
FILE_PATH=$(echo "$EVENT" | grep -o '"path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"path"[[:space:]]*:[[:space:]]*"//;s/"$//')
[ -z "$FILE_PATH" ] && exit 0
case "$FILE_PATH" in
  .kimi/*|.kimi\\*) echo "BLOCKED: Edit-boundary rule — Kiro cannot write to .kimi/. Create a handoff to .ai/handoffs/to-kimi/open/ instead." >&2; exit 2 ;;
  .claude/*|.claude\\*) echo "BLOCKED: Edit-boundary rule — Kiro cannot write to .claude/. Create a handoff to .ai/handoffs/to-claude/open/ instead." >&2; exit 2 ;;
esac
exit 0