#!/bin/bash
# Hook: preToolUse — block writes to sensitive files

FILE_PATH=$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || \
            python  -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || \
            echo "")
[ -z "$FILE_PATH" ] && exit 0

BASE=$(basename "$FILE_PATH")
case "$BASE" in
  .env|.env.*|*.key|*.pem|id_rsa*|*.p12|*.pfx) echo "BLOCKED: Sensitive file protection — cannot write to $BASE. Use config/ with .gitignore for secrets." >&2; exit 2 ;;
esac
case "$FILE_PATH" in
  .aws/*|.ssh/*) echo "BLOCKED: Sensitive directory — cannot write to $FILE_PATH." >&2; exit 2 ;;
esac
exit 0
