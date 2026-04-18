#!/bin/bash
# Hook 2: Framework directory guard
# Block writes to other CLIs' framework directories (.claude/, .kiro/)
# .kimi/ is Kimi's own territory. .ai/ is shared with other CLIs
# (allowed for orchestrator; subagent writes restricted per agent config).

read JSON

FILE_PATH=$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || \
            python -c  "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || \
            echo "")

[ -z "$FILE_PATH" ] && exit 0

# Block .claude/ and .kiro/ directories
case "$FILE_PATH" in
    .claude/*|.kiro/*)
        echo "BLOCKED: Writing to '$FILE_PATH' is not allowed. .claude/ and .kiro/ are owned by other CLIs. Use .ai/ or .kimi/ for framework-level files." >&2
        exit 2
        ;;
    *)
        exit 0
        ;;
esac
