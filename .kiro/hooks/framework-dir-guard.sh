#!/bin/bash
# Hook: preToolUse — block subagent writes to other CLIs' framework dirs

FILE_PATH=$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || \
            python  -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || \
            echo "")
[ -z "$FILE_PATH" ] && exit 0

case "$FILE_PATH" in
  .kimi/*|.kimi\\*) echo "BLOCKED: Edit-boundary rule — Kiro cannot write to .kimi/. Create a handoff to .ai/handoffs/to-kimi/open/ instead." >&2; exit 2 ;;
  .claude/*|.claude\\*) echo "BLOCKED: Edit-boundary rule — Kiro cannot write to .claude/. Create a handoff to .ai/handoffs/to-claude/open/ instead." >&2; exit 2 ;;
esac
exit 0
