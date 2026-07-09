#!/bin/bash
# Hook: preToolUse — block subagent writes to other CLIs' framework dirs

FILE_PATH=$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || \
            python  -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || \
            echo "")
[ -z "$FILE_PATH" ] && exit 0

case "$FILE_PATH" in
  .kimi/*|.kimi\\*) echo "BLOCKED: Edit-boundary rule — Kiro cannot write to .kimi/. Create a handoff to .ai/handoffs/to-kimi/open/ instead." >&2; exit 2 ;;
  .claude/*|.claude\\*) echo "BLOCKED: Edit-boundary rule — Kiro cannot write to .claude/. Create a handoff to .ai/handoffs/to-claude/open/ instead." >&2; exit 2 ;;
  .codegraph/*|.codegraph\\*) echo "BLOCKED: Edit-boundary rule — Kiro cannot write to .codegraph/ (Claude's graph dir)." >&2; exit 2 ;;
  .kimigraph/*|.kimigraph\\*) echo "BLOCKED: Edit-boundary rule — Kiro cannot write to .kimigraph/ (Kimi's graph dir)." >&2; exit 2 ;;
  .kirograph/*|.kirograph\\*) echo "BLOCKED: KiroGraph removed 2026-07-09 (ADR-0003 amendment). No re-enable path short of a fresh ADR." >&2; exit 2 ;;
esac
exit 0
